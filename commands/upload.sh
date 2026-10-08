#!/usr/bin/env bash
# upload — envio para caminho remoto (RF-07, RF-08, RF-09, RF-31, RF-49, RF-15).
#
# Gemeo de `delete` na escrita remota. A diferenca e o transporte: aqui o corpo
# e binario e os parametros vao no cabecalho, pelo modo de conteudo.
#
# DOIS CAMINHOS DE ESCRITA, UM SO OBJETO DE PUBLICACAO
# ---------------------------------------------------
# O comando escreve por dois caminhos:
#
#   requisicao unica  `files/upload`, para arquivo local ate o teto por requisicao;
#   sessao em partes  `lib/transfer`, para a entrada padrao (RF-31) e para
#                     arquivo local acima do teto (RF-08).
#
# CONJUNTO ONDE A REGRA DE PUBLICACAO INCIDE: os dois caminhos acima, e o
# terceiro que `sync` vai trazer. O objeto de publicacao — caminho, modo ou
# `rev` esperado, `client_modified`, `autorename`, `mute` — e montado UMA vez,
# em `_dbx_upload_objeto_de_publicacao`, e usado pelos dois. Monta-lo em cada
# ramo e a forma exata das ocorrencias da familia de gemeos ja pagas neste
# projeto: a proxima correcao em `mode` ou em `client_modified` valeria para um
# caminho so, e o sintoma — arquivo publicado com metadado diferente conforme o
# tamanho — nao se parece com a causa.
#
# RF-15 — POSICAO DO GATE DE SIMULACAO
# ------------------------------------
# A verificacao de simulacao esta ANTES da bifurcacao entre os dois caminhos,
# e portanto DOMINA os dois. Nao e disciplina a lembrar: e estrutura. Um ramo de
# escrita novo escrito abaixo dela ja nasce coberto; um escrito acima dela seria
# visivel na leitura por estar antes do gate. `lib/transfer` ainda recusa
# executar sob simulacao, como segunda linha de defesa para chamador futuro.
#
# ROTEAMENTO POR TAMANHO MEDIDO
# -----------------------------
# O tamanho vem do arquivo, e nao de declaracao do chamador. O limiar e o teto
# por requisicao da Dropbox e tem um unico dono: `DBX_TRANSFER_LIMITE_REQUISICAO`.
#
# LIMITE DECLARADO, herdado de `lib/transfer`: quando a origem e um cano
# anonimo, produtor que morre no meio e INDISTINGUIVEL de fim de fluxo legitimo.
# O criterio de RF-31 sobre falha da origem e cumprido para falha de LEITURA,
# nao para produtor que encerrou mal depois de escrever um prefixo. Quem
# encadeia — `tar czf - /dados | dbx upload - /destino.tgz` — deve usar
# `set -o pipefail` para que o proprio encadeamento reprove. Medido: produtor
# que sai com status 3 apos escrever um prefixo faz este comando sair com ZERO;
# com `pipefail`, o encadeamento devolve 3.
#
# PENDENCIA ATENDIDA (RSK-36 / DIV-18 / DP-29): essa recomendacao operacional
# para encadeamento via entrada padrao (-) foi formalmente incorporada ao texto
# de ajuda de `bin/dbx` (`dbx help` e `dbx help upload`).

dbx_cmd_upload_requisitos() { printf 'credencial'; }

# _dbx_upload_objeto_de_publicacao <remoto> <modo> <rev> <origem>
#
# UNICO lugar que monta o objeto de publicacao. Resultado em DBX_UPLOAD_COMMIT.
#
# RNF-27 — `client_modified` a partir do `mtime` local.
#
# Isto NAO serve ao `upload`. Serve ao `sync`, que compara carimbos dos dois
# lados: definindo `client_modified` no envio, todo arquivo que esta aplicacao
# mandou passa a ter, nos dois lados, carimbo da MESMA origem de relogio, e a
# incomparabilidade entre `mtime` local e horario do servico desaparece nesses
# casos. A propriedade e permanente: o que subir sem ela nunca a ganha, porque o
# servico nao recalcula depois.
#
# Fluxo pela entrada padrao NAO tem `mtime` — nao ha arquivo de onde le-lo — e
# por isso sai sem o carimbo. Inventar um carimbo com o horario da execucao
# seria fabricar procedencia de relogio que o conteudo nao tem.
_dbx_upload_objeto_de_publicacao() {
  local remoto=$1 modo=$2 rev=$3 origem=$4 carimbo=''

  if [[ $origem != '-' ]] && carimbo=$(date -u -r "$origem" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null); then
    :
  else
    carimbo=''
  fi

  dbx_json_escapar_cadeia "$remoto"
  DBX_UPLOAD_COMMIT="{\"path\":\"$DBX_JSON_ESCAPADO\",\"mode\":"
  if [[ -n $rev ]]; then
    # RF-49: o `rev` esperado viaja com a escrita. Alteracao remota entre a
    # leitura e o envio vira conflito, e nao sobrescrita do que mudou.
    dbx_json_escapar_cadeia "$rev"
    DBX_UPLOAD_COMMIT+="{\".tag\":\"update\",\"update\":\"$DBX_JSON_ESCAPADO\"}"
  else
    DBX_UPLOAD_COMMIT+="\"$modo\""
  fi
  if [[ -n $carimbo ]]; then
    dbx_json_escapar_cadeia "$carimbo"
    DBX_UPLOAD_COMMIT+=",\"client_modified\":\"$DBX_JSON_ESCAPADO\""
  fi
  DBX_UPLOAD_COMMIT+=',"autorename":false,"mute":false}'
  return 0
}

dbx_cmd_upload_executar() {
  local origem='' destino='' modo='add' rev='' forcar='nao'
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
      --forcar | --force)
        forcar='sim'
        ;;
      --progresso | --progress | -p)
        DBX_CLI_PROGRESSO='sim'
        ;;
      --sem-progresso | --no-progress)
        DBX_CLI_PROGRESSO='nao'
        ;;
      -)
        # `-` e posicional, nao opcao: e a convencao para entrada padrao. Cair no
        # ramo de opcao desconhecida esconderia o caminho que RF-31 exige.
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

  local eh_diretorio='nao'
  if [[ $origem != '-' ]]; then
    if [[ -d $origem ]]; then
      eh_diretorio='sim'
      [[ -r $origem ]] || {
        dbx_cmd_falhar nao_encontrado "diretorio local ilegivel: $origem"
        return $?
      }
    elif [[ -f $origem && -r $origem ]]; then
      eh_diretorio='nao'
    else
      dbx_cmd_falhar nao_encontrado "arquivo local inexistente ou ilegivel: $origem"
      return $?
    fi
  fi

  local remoto
  _dbx_cmd_caminho_remoto "$destino" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $destino"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  if [[ $eh_diretorio == 'sim' ]]; then
    if [[ -n $rev ]]; then
      dbx_cmd_falhar uso_invalido '--rev nao e suportado para envio de diretorios'
      return $?
    fi

    local alvo_remoto=$remoto
    local nome_base_local=${origem##*/}
    [[ -z $nome_base_local ]] && nome_base_local=$(basename -- "$origem")
    if [[ $destino == '/' || $remoto == '/' || -z $remoto ]]; then
      alvo_remoto="/$nome_base_local"
    elif [[ $destino == */ ]]; then
      alvo_remoto="${remoto%/}/$nome_base_local"
    fi

    if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
      dbx_cmd_iniciar_saida
      dbx_output_campo operacao upload
      dbx_output_campo tipo diretorio
      dbx_output_campo origem "$origem"
      dbx_output_campo caminho "$alvo_remoto"
      dbx_output_campo simulado sim
      dbx_output_render
      return 0
    fi

    dbx_progress_mensagem "[upload] iniciando envio de diretorio: $origem -> $alvo_remoto"
    # shellcheck source=commands/sync.sh
    . "${BASH_SOURCE[0]%/*}/sync.sh"
    dbx_cmd_sync_executar --enviar --origem "$origem" --destino "$alvo_remoto"
    return $?
  fi

  _dbx_upload_objeto_de_publicacao "$remoto" "$modo" "$rev" "$origem"

  # A guarda de cabecalho e de `lib/http` e recusa antes de qualquer invocacao do
  # cliente. Verificar aqui tambem seria duplicar a regra em dois lugares — e a
  # forma exata das nove ocorrencias da familia de gemeos.

  # RF-15 — GATE UNICO, ANTES DA BIFURCACAO. Ver a nota no cabecalho.
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao upload
    dbx_output_campo origem "$origem"
    dbx_output_campo caminho "$remoto"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  # Carga sob demanda, no unico caminho que usa o componente. `bin/dbx` carrega
  # a camada de credencial; o envio em partes e propriedade deste comando.
  # shellcheck source=lib/transfer.sh
  . "${BASH_SOURCE[0]%/*}/../lib/transfer.sh"
  # shellcheck source=lib/db.sh
  . "${BASH_SOURCE[0]%/*}/../lib/db.sh"
  dbx_db_inicializar || :

  local tam_local='' mtime_local=''
  if [[ $origem != '-' ]]; then
    tam_local=$(stat -c '%s' "$origem" 2>/dev/null)
    mtime_local=$(stat -c '%Y' "$origem" 2>/dev/null)
    if [[ $forcar != 'sim' && -n $tam_local && -n $mtime_local ]]; then
      dbx_progress_mensagem "[upload] analisando arquivo local: $origem"
      if ! dbx_db_arquivo_alterado "$origem" "$remoto" "upload" "$tam_local" "$mtime_local"; then
        dbx_progress_mensagem "[upload] resultado da analise: $origem -> inalterado (envio dispensado)"
        dbx_cmd_iniciar_saida
        dbx_output_campo operacao upload
        dbx_output_campo origem "$origem"
        dbx_output_campo caminho "$remoto"
        dbx_output_campo status dispensado
        dbx_output_campo motivo inalterado
        dbx_output_render
        return 0
      fi
      dbx_progress_mensagem "[upload] resultado da analise: $origem -> alterado/novo (necessita envio)"
    fi
  fi

  dbx_progress_mensagem "[upload] iniciando envio: $origem -> $remoto"

  local por_sessao='nao'
  if [[ $origem == '-' ]]; then
    # RF-31: o tamanho total e desconhecido no inicio, entao nao ha decisao a
    # tomar — fluxo obriga sessao.
    por_sessao='sim'
  else
    dbx_transfer_tamanho_de_arquivo "$origem" || {
      dbx_cmd_falhar nao_encontrado "tamanho do arquivo local indeterminado: $origem"
      return $?
    }
    # A entrada do predicado e garantidamente numerica pela chamada acima, que
    # ja recusou o que nao fosse. Sem essa garantia a forma `&&` seria
    # FALHA ABERTA: um status de uso invalido cairia em "nao precisa de sessao"
    # e um arquivo grande iria por requisicao unica, para falhar no servico
    # longe da causa. A garantia esta aqui escrita porque e ela que autoriza a
    # forma curta.
    dbx_transfer_precisa_de_sessao "$DBX_TRANSFER_TAMANHO" && por_sessao='sim'
  fi

  if [[ $por_sessao == 'sim' ]]; then
    if [[ $origem == '-' ]]; then
      dbx_transfer_sessao "$DBX_UPLOAD_COMMIT"
    else
      # O MESMO laco de sessao, alimentado pelo arquivo. Um laco proprio para
      # arquivo seria o gemeo em que a proxima correcao de deslocamento valeria
      # para um lado so.
      dbx_transfer_sessao "$DBX_UPLOAD_COMMIT" <"$origem"
    fi || {
      dbx_cmd_falhar "${DBX_TRANSFER_CLASSE:-nao_concluida}" \
        "envio em partes nao concluido: ${DBX_TRANSFER_MOTIVO:-sem detalhe}"
      return $?
    }
  else
    dbx_progress_mensagem "[upload] enviando arquivo via requisicao unica..."
    dbx_auth_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
      "$DBX_UPLOAD_COMMIT" "$origem" nao || {
      local classe=${DBX_HTTP_CLASSE:-erro_remoto}
      dbx_cmd_falhar "$classe" "envio recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-sem detalhe}"
      return $?
    }
  fi

  dbx_progress_mensagem "[upload] envio concluido com sucesso"

  _dbx_cmd_analisar_corpo || return $?

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao upload
  dbx_output_campo origem "$origem"
  if [[ $por_sessao == 'sim' ]]; then
    dbx_output_campo modo_de_envio sessao_em_partes
    dbx_output_campo bytes_enviados "$DBX_TRANSFER_BYTES"
    # A conferencia so e declarada quando ocorreu. Afirmar verificacao que nao
    # houve e pior que nao verificar — mesmo criterio ja adotado em `download`.
    dbx_output_campo integridade "$DBX_TRANSFER_INTEGRIDADE"
  else
    dbx_output_campo modo_de_envio requisicao_unica
  fi
  _dbx_cmd_metadado_em

  local hash_gravado='' rev_gravado=''
  _dbx_cmd_campo content_hash && hash_gravado=$DBX_CMD_LIDO
  _dbx_cmd_campo rev && rev_gravado=$DBX_CMD_LIDO
  if [[ -z $hash_gravado && -n ${DBX_TRANSFER_HASH:-} ]]; then
    hash_gravado=$DBX_TRANSFER_HASH
  fi
  if [[ $origem != '-' && -n $hash_gravado && -n $tam_local && -n $mtime_local ]]; then
    dbx_db_salvar_metadado "$origem" "$tam_local" "$mtime_local" "$hash_gravado" || :
    dbx_db_salvar_operacao "$origem" "$remoto" "upload" "$tam_local" "$mtime_local" "$hash_gravado" "$rev_gravado" || :
  fi

  _dbx_cmd_encerrar_consulta
  dbx_output_render
  return 0
}
