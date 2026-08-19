#!/usr/bin/env bash
# upload — envio de arquivo local para caminho remoto (RF-07, RF-49, RF-15, RNF-27).
#
# Gemeo de `delete` na escrita remota: os dois passam por
# `_dbx_cmd_escrita_remota` para simulacao e mapeamento de conflito. A diferenca
# e o transporte — aqui o corpo e binario e os parametros vao no cabecalho, pelo
# modo de conteudo.
#
# LIMITE DECLARADO: envio a partir da entrada padrao (`-`) exige sessao em partes
# (`RF-08`, `RF-09`), que `lib/http` ainda nao possui. O comando RECUSA `-` com
# diagnostico explicito em vez de tentar ler tudo em memoria — falhar dizendo o
# que falta e melhor que exceder memoria em silencio.

dbx_cmd_upload_requisitos() { printf 'credencial'; }

dbx_cmd_upload_executar() {
  local origem='' destino='' modo='add' rev=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --modo | --mode)
        shift
        modo=${1-}
        ;;
      --rev)
        shift
        rev=${1-}
        ;;
      -)
        # `-` e posicional, nao opcao: e a convencao para entrada padrao. Cair no
        # ramo de opcao desconhecida esconderia o diagnostico que diz o que falta.
        if [[ -z $origem ]]; then origem='-'; else destino='-'; fi
        ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        if [[ -z $origem ]]; then
          origem=$1
        elif [[ -z $destino ]]; then
          destino=$1
        else
          dbx_cmd_falhar uso_invalido 'informe apenas origem e destino'
          return $?
        fi
        ;;
    esac
    shift
  done

  [[ -n $origem && -n $destino ]] || {
    dbx_cmd_falhar uso_invalido 'informe o arquivo local e o caminho remoto'
    return $?
  }

  case $modo in
    add | overwrite) ;;
    *)
      dbx_cmd_falhar uso_invalido "modo nao reconhecido: $modo (use add ou overwrite)"
      return $?
      ;;
  esac

  if [[ $origem == '-' ]]; then
    dbx_cmd_falhar nao_concluida \
      'envio pela entrada padrao exige sessao em partes, ainda nao implementada'
    return $?
  fi

  [[ -f $origem && -r $origem ]] || {
    dbx_cmd_falhar nao_encontrado "arquivo local inexistente ou ilegivel: $origem"
    return $?
  }

  local remoto
  _dbx_cmd_caminho_remoto "$destino" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $destino"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  # RNF-27 — `client_modified` a partir do `mtime` local.
  #
  # Isto NAO serve ao `upload`. Serve ao `sync`, que compara carimbos dos dois
  # lados: definindo `client_modified` no envio, todo arquivo que esta aplicacao
  # mandou passa a ter, nos dois lados, carimbo da MESMA origem de relogio, e a
  # incomparabilidade entre `mtime` local e horario do servico desaparece nesses
  # casos.
  #
  # A propriedade e permanente: o que subir sem ela nunca a ganha, porque o
  # servico nao recalcula depois. Por isso o custo se paga aqui, e nao la.
  local carimbo=''
  if carimbo=$(date -u -r "$origem" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null); then
    :
  else
    carimbo=''
  fi

  dbx_json_escapar_cadeia "$remoto"
  local argumento="{\"path\":\"$DBX_JSON_ESCAPADO\",\"mode\":"
  if [[ -n $rev ]]; then
    # RF-49: o `rev` esperado viaja com a escrita. Alteracao remota entre a
    # leitura e o envio vira conflito, e nao sobrescrita do que mudou.
    dbx_json_escapar_cadeia "$rev"
    argumento+="{\".tag\":\"update\",\"update\":\"$DBX_JSON_ESCAPADO\"}"
  else
    argumento+="\"$modo\""
  fi
  if [[ -n $carimbo ]]; then
    dbx_json_escapar_cadeia "$carimbo"
    argumento+=",\"client_modified\":\"$DBX_JSON_ESCAPADO\""
  fi
  argumento+=',"autorename":false,"mute":false}'

  # A guarda de cabecalho e de `lib/http` e recusa antes de qualquer invocacao do
  # cliente. Verificar aqui tambem seria duplicar a regra em dois lugares — e a
  # forma exata das nove ocorrencias da familia de gemeos.

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao upload
    dbx_output_campo origem "$origem"
    dbx_output_campo caminho "$remoto"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  dbx_auth_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
    "$argumento" "$origem" nao || {
    local classe=${DBX_HTTP_CLASSE:-erro_remoto}
    dbx_cmd_falhar "$classe" "envio recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-sem detalhe}"
    return $?
  }
  _dbx_cmd_analisar_corpo || return $?

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao upload
  dbx_output_campo origem "$origem"
  _dbx_cmd_metadado_em
  _dbx_cmd_encerrar_consulta
  dbx_output_render
  return 0
}
