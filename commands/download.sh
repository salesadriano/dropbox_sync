#!/usr/bin/env bash
# download — recebimento de item remoto (RF-32, RF-30).
#
# DESTINO EM ARQUIVO E RECEBIDO DE FORMA ATOMICA (RF-55): temporario no mesmo
# diretorio, conferencia do `content_hash` e so entao a troca pelo alvo — ver
# `dbx_cmd_receber_arquivo`. Queda de rede ou resumo divergente deixam o
# arquivo anterior intacto.
#
# SEM DESTINO, o conteudo sai em fluxo pela saida padrao e o consumidor recebe
# os bytes antes de qualquer veredito; nao ha o que conferir depois. O modo
# suportado e `dbx download ... > arq && processar arq`.
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
      --forcar | --force)
        # aceito para paridade operacional
        ;;
      -)
        # `-` e o destino "saida padrao" (RF-32), e nao uma opcao: o ramo
        # abaixo o recusava como opcao desconhecida.
        if [[ -z $caminho ]]; then
          dbx_cmd_falhar uso_invalido 'informe o caminho remoto antes do destino'
          return $?
        elif [[ -n $destino ]]; then
          dbx_cmd_falhar uso_invalido 'informe apenas o caminho remoto e o destino'
          return $?
        fi
        destino=-
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

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao download
    dbx_output_campo caminho "$remoto"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  # Se o caminho for a raiz remota (""), trata-se obrigatoriamente de uma pasta.
  if [[ -z $remoto ]]; then
    if [[ -z $destino || $destino == '-' ]]; then
      dbx_cmd_falhar uso_invalido 'o caminho remoto e a raiz da conta (pasta); informe o diretorio local de destino'
      return $?
    fi
    local dir_raiz_local=$destino
    [[ $dir_raiz_local == */ ]] && dir_raiz_local=${dir_raiz_local%/}
    [[ -z $dir_raiz_local ]] && dir_raiz_local='/'
    mkdir -p -- "$dir_raiz_local" 2>/dev/null || {
      dbx_cmd_falhar configuracao "nao foi possivel criar o diretorio de destino: $dir_raiz_local"
      return $?
    }
    dbx_progress_mensagem "[download] o caminho remoto e uma pasta: recebendo conteudo recursivamente..."
    # shellcheck source=commands/sync.sh
    . "${BASH_SOURCE[0]%/*}/sync.sh"
    dbx_cmd_sync_executar --receber --origem / --destino "$dir_raiz_local"
    return $?
  fi

  dbx_json_escapar_cadeia "$remoto"
  local argumento="{\"path\":\"$DBX_JSON_ESCAPADO\"}"

  # Sem destino, o conteudo vai para a saida padrao. Se o destino informado
  # for um diretorio (ou terminar com barra), o arquivo e salvo com o nome
  # original dentro dele, criando o diretorio se necessario. Caso seja um caminho
  # com subdiretorios inexistentes, as pastas intermediarias sao criadas.
  local alvo=${destino:-/dev/stdout}
  if [[ -n $destino ]]; then
    if [[ $destino == */ || -d $destino ]]; then
      local nome_base=${remoto##*/}
      [[ -z $nome_base ]] && nome_base='raiz'
      local dir_destino=${destino%/}
      [[ -z $dir_destino ]] && dir_destino='/'
      if [[ ! -d $dir_destino ]]; then
        mkdir -p -- "$dir_destino" 2>/dev/null || {
          dbx_cmd_falhar configuracao "nao foi possivel criar o diretorio de destino: $dir_destino"
          return $?
        }
      fi
      if [[ -d $dir_destino && $(basename -- "$dir_destino") == "$nome_base" ]]; then
        alvo=$dir_destino
      else
        alvo="${dir_destino%/}/$nome_base"
      fi
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

  local str_barra_inicio=''
  dbx_progress_barra_gerar 0 20 str_barra_inicio
  dbx_progress_mensagem "[download] iniciando recebimento: $remoto -> $alvo $str_barra_inicio (0%)"

  local estado_recebimento=0
  if [[ $alvo == '/dev/stdout' || $alvo == '-' ]]; then
    # O cliente reabre a saida padrao do inicio (limite declarado em lib/http):
    # sobre arquivo que ja tem conteudo — o `>>` — isso o apagaria. Recusa
    # antes de qualquer chamada, em vez de perda silenciosa.
    if [[ -f /dev/stdout && -s /dev/stdout ]]; then
      dbx_cmd_falhar uso_invalido \
        'a saida padrao e um arquivo que ja tem conteudo e seria sobrescrito; use ">" para um arquivo novo, um cano, ou informe o destino'
      return $?
    fi
    dbx_auth_conteudo_receber GET \
      'https://content.dropboxapi.com/2/files/download' "$argumento" "$alvo"
    estado_recebimento=$?
  else
    dbx_cmd_receber_arquivo "$remoto" "$alvo"
    estado_recebimento=$?
  fi
  if [[ $estado_recebimento -ne 0 ]]; then
    if [[ -n ${DBX_CMD_FALHA_CLASSE:-} && $alvo != '/dev/stdout' && $alvo != '-' ]]; then
      dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
      return $?
    fi
    local classe=${DBX_HTTP_CLASSE:-erro_remoto}
    local detalhe=${DBX_HTTP_RESUMO_DE_ERRO:-sem detalhe}
    # QA-P2-05: falha local de escrita na saida padrao tem diagnostico proprio.
    if [[ $classe == 'configuracao' && ($alvo == '/dev/stdout' || $alvo == '-') ]]; then
      dbx_cmd_falhar configuracao "${DBX_HTTP_DIAGNOSTICO:-falha de escrita na saida padrao}"
      return $?
    fi
    if [[ $classe == 'consumidor_encerrou' ]]; then
      dbx_cmd_falhar consumidor_encerrou \
        'o consumidor da saida padrao encerrou antes do fim do fluxo; o recebimento foi interrompido e nao foi repetido'
      return $?
    fi
    case $detalhe in
      *not_file*)
        if [[ -z $destino || $destino == '-' ]]; then
          dbx_cmd_falhar uso_invalido \
            "o caminho remoto e uma pasta; informe o diretorio local de destino"
          return $?
        fi
        # RF-56: o destino que ja existe como arquivo e do usuario, e nao vira
        # diretorio. Remove-lo para dar lugar a pasta seria perda sem aviso.
        if [[ -e $alvo || -L $alvo ]] && [[ ! -d $alvo ]]; then
          dbx_cmd_falhar conflito \
            "o caminho remoto e uma pasta e o destino local ja existe e nao e diretorio: $alvo"
          return $?
        fi
        mkdir -p -- "$alvo" 2>/dev/null || {
          dbx_cmd_falhar configuracao "nao foi possivel criar o diretorio de destino: $alvo"
          return $?
        }
        dbx_progress_mensagem "[download] o caminho remoto e uma pasta: recebendo conteudo recursivamente..."
        # shellcheck source=commands/sync.sh
        . "${BASH_SOURCE[0]%/*}/sync.sh"
        local -a args_sync=(--receber --origem "$remoto" --destino "$alvo")
        [[ ${DBX_CLI_PROGRESSO:-} == 'sim' ]] && args_sync+=(--progresso)
        [[ ${DBX_CLI_PROGRESSO:-} == 'nao' ]] && args_sync+=(--sem-progresso)
        dbx_cmd_sync_executar "${args_sync[@]}"
        return $?
        ;;
      *not_found*)
        detalhe="caminho remoto nao encontrado no Dropbox: $remoto (verifique se o nome esta correto)"
        classe='nao_encontrado'
        ;;
    esac
    dbx_cmd_falhar "$classe" "recebimento recusado: $detalhe"
    return $?
  fi

  local str_barra_fim='' str_tam_baixado=''
  dbx_progress_barra_gerar 100 20 str_barra_fim
  # So destino em arquivo: medir `/dev/stdout` dentro da substituicao abaixo
  # leria o proprio cano da captura e nunca terminaria.
  if [[ $alvo != '/dev/stdout' && $alvo != '-' && -f $alvo ]]; then
    local bytes_baixados
    bytes_baixados=$(wc -c <"$alvo" 2>/dev/null)
    bytes_baixados=${bytes_baixados//[^0-9]/}
    if [[ -n $bytes_baixados ]]; then
      dbx_progress_formatar_bytes "$bytes_baixados" str_tam_baixado
    fi
  fi
  if [[ -n $str_tam_baixado ]]; then
    dbx_progress_mensagem "[download] recebimento concluido: $alvo ($str_tam_baixado) $str_barra_fim (100%)"
  else
    dbx_progress_mensagem "[download] recebimento concluido: $alvo $str_barra_fim (100%)"
  fi

  # Em arquivo, a conferencia ja ocorreu antes da substituicao (RF-55). Em
  # fluxo os bytes ja passaram e nao ha o que comparar: o comando nao afirma
  # integridade que nao verificou.
  local esperado='' verificacao='nao_aplicavel'
  if [[ $alvo == '/dev/stdout' || $alvo == '-' ]]; then
    dbx_cmd_content_hash_do_resultado
    esperado=$DBX_CMD_LIDO
  else
    esperado=$DBX_CMD_CONTENT_HASH
    verificacao=$DBX_CMD_INTEGRIDADE
  fi

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao download
  dbx_output_campo caminho "$remoto"
  dbx_output_campo destino "$alvo"
  dbx_output_campo integridade "$verificacao"
  [[ -n $esperado ]] && dbx_output_campo content_hash "$esperado"
  # RF-32(b): em fluxo a saida padrao E o conteudo; o registro do resultado
  # colado ao fim dele corromperia o que o consumidor recebe. Vai para a saida
  # de erro, como o diagnostico.
  if [[ $alvo == '/dev/stdout' || $alvo == '-' ]]; then
    dbx_output_render >&2
  else
    dbx_output_render
  fi
  return 0
}
