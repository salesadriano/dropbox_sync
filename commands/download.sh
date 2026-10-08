#!/usr/bin/env bash
# download — recebimento de item remoto (RF-32, RF-30).
#
# EMITE E VALIDA EM PARALELO, por decisao do solicitante. O resumo e calculado
# enquanto os bytes sao entregues, e a divergencia e reportada por codigo de saida
# e diagnostico — nao por reter o conteudo.
#
# CONSEQUENCIA ACEITA, e ela precisa estar dita: o consumidor recebe os bytes
# ANTES do veredito. Quem redirecionar a saida e ignorar o codigo de saida fica
# com arquivo corrompido sem aviso. O modo suportado e
# `dbx download ... > arq && processar arq`, coerente com o uso em automacao.
#
# Gemeo de `upload` no transporte: os dois usam o modo de conteudo, em direcoes
# opostas. A assimetria que importa esta em `lib/http` — retentativa e propriedade
# do canal, e o de fluxo nao repete depois do primeiro byte.

dbx_cmd_download_requisitos() { printf 'credencial'; }

dbx_cmd_download_executar() {
  local caminho='' destino=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --progresso | --progress | -p)
        # shellcheck disable=SC2034 # variavel global consumida por lib/progress.sh
        DBX_CLI_PROGRESSO='sim'
        ;;
      --sem-progresso | --no-progress)
        # shellcheck disable=SC2034 # variavel global consumida por lib/progress.sh
        DBX_CLI_PROGRESSO='nao'
        ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        if [[ -z $caminho ]]; then
          caminho=$1
        elif [[ -z $destino ]]; then
          destino=$1
        else
          dbx_cmd_falhar uso_invalido 'informe apenas o caminho remoto e o destino'
          return $?
        fi
        ;;
    esac
    shift
  done

  [[ -n $caminho ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto'
    return $?
  }

  local remoto
  _dbx_cmd_caminho_remoto "$caminho" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $caminho"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  dbx_json_escapar_cadeia "$remoto"
  local argumento="{\"path\":\"$DBX_JSON_ESCAPADO\"}"

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao download
    dbx_output_campo caminho "$remoto"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  # Sem destino, o conteudo vai para a saida padrao. Se o destino informado
  # for um diretorio (ou terminar com barra), o arquivo e salvo com o nome
  # original dentro dele, criando o diretorio se necessario. Caso seja um caminho
  # com subdiretorios inexistentes, as pastas intermediarias sao criadas.
  local alvo=${destino:-/dev/stdout}
  if [[ -n $destino ]]; then
    if [[ $destino == */ || -d $destino ]]; then
      local nome_base=${remoto##*/}
      local dir_destino=${destino%/}
      [[ -z $dir_destino ]] && dir_destino='/'
      if [[ ! -d $dir_destino ]]; then
        mkdir -p -- "$dir_destino" 2>/dev/null || {
          dbx_cmd_falhar configuracao "nao foi possivel criar o diretorio de destino: $dir_destino"
          return $?
        }
      fi
      alvo="${dir_destino%/}/$nome_base"
    else
      local dir_pai=${destino%/*}
      if [[ $destino == */* && -n $dir_pai && ! -d $dir_pai ]]; then
        mkdir -p -- "$dir_pai" 2>/dev/null || {
          dbx_cmd_falhar configuracao "nao foi possivel criar o diretorio de destino: $dir_pai"
          return $?
        }
      fi
      alvo=$destino
    fi
  fi

  dbx_progress_mensagem "[download] iniciando recebimento: $remoto -> $alvo"

  dbx_auth_conteudo_receber GET \
    'https://content.dropboxapi.com/2/files/download' "$argumento" "$alvo" || {
    local classe=${DBX_HTTP_CLASSE:-erro_remoto}
    local detalhe=${DBX_HTTP_RESUMO_DE_ERRO:-sem detalhe}
    case $detalhe in
      *not_file*)
        detalhe="o caminho remoto e uma pasta, nao um arquivo (para baixar pastas completas, use: dbx sync --receber --origem $remoto --destino ${destino:-.})"
        classe='uso_invalido'
        ;;
    esac
    dbx_cmd_falhar "$classe" "recebimento recusado: $detalhe"
    return $?
  }

  dbx_progress_mensagem "[download] recebimento concluido: $alvo"

  # VERIFICACAO DE INTEGRIDADE, e o limite dela.
  #
  # O `content_hash` que o servico calculou vem no cabecalho `Dropbox-API-Result`.
  # Comparar exige ler o que foi entregue — possivel quando o destino e arquivo
  # regular, impossivel quando e fluxo, porque os bytes ja passaram.
  #
  # Quando nao da para comparar, o comando NAO afirma integridade: reportar
  # verificacao que nao ocorreu seria pior que nao verificar.
  local esperado='' obtido='' verificacao='nao_aplicavel'
  if [[ -n ${DBX_HTTP_RESULTADO_CABECALHO:-} ]]; then
    dbx_json_contexto resultado >/dev/null 2>&1
    if dbx_json_analisar "$DBX_HTTP_RESULTADO_CABECALHO" >/dev/null 2>&1 &&
      dbx_json_valor content_hash >/dev/null 2>&1; then
      esperado=$DBX_JSON_RESULTADO
    fi
    dbx_json_descartar resultado >/dev/null 2>&1
    dbx_json_contexto padrao >/dev/null 2>&1
  fi

  if [[ -n $esperado && -f $alvo ]]; then
    if obtido=$(dbx_hash_conteudo_arquivo "$alvo" 2>/dev/null) && [[ -n $obtido ]]; then
      if [[ $obtido == "$esperado" ]]; then
        verificacao='conferida'
      else
        verificacao='divergente'
      fi
    fi
  fi

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao download
  dbx_output_campo caminho "$remoto"
  dbx_output_campo destino "$alvo"
  dbx_output_campo integridade "$verificacao"
  [[ -n $esperado ]] && dbx_output_campo content_hash "$esperado"
  dbx_output_render

  if [[ $verificacao == 'divergente' ]]; then
    dbx_cmd_falhar integridade \
      'o conteudo recebido nao confere com o resumo publicado pelo servico'
    return $?
  fi
  return 0
}
