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
# CONJUNTO ONDE A REGRA DE PUBLICACAO INCIDE: os dois caminhos acima e o envio
# do `sync`. O objeto de publicacao — caminho, modo ou `rev` esperado,
# `client_modified`, `autorename`, `mute` — e montado UMA vez, em
# `dbx_transfer_objeto_de_publicacao`, e a escolha entre requisicao unica e
# sessao para arquivo local mora em `dbx_transfer_enviar_arquivo`, ambos em
# `lib/transfer`. Monta-los em cada comando e a forma exata das ocorrencias da
# familia de gemeos ja pagas neste projeto: o sintoma — arquivo publicado com
# metadado diferente conforme o comando ou o tamanho — nao se parece com a causa.
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

  # shellcheck source=lib/transfer.sh
  . "${BASH_SOURCE[0]%/*}/../lib/transfer.sh"
  dbx_transfer_objeto_de_publicacao "$remoto" "$modo" "$rev" "$origem"

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
    dbx_transfer_sessao "$DBX_TRANSFER_COMMIT" || {
      dbx_cmd_falhar "${DBX_TRANSFER_CLASSE:-nao_concluida}" \
        "envio em partes nao concluido: ${DBX_TRANSFER_MOTIVO:-sem detalhe}"
      return $?
    }
  else
    dbx_transfer_enviar_arquivo "$origem" "$DBX_TRANSFER_COMMIT" upload
    local estado_envio=$?
    por_sessao=$DBX_TRANSFER_POR_SESSAO
    [[ $estado_envio -eq 0 ]] || {
      if [[ $por_sessao == 'sim' ]]; then
        dbx_cmd_falhar "${DBX_TRANSFER_CLASSE:-nao_concluida}" \
          "envio em partes nao concluido: ${DBX_TRANSFER_MOTIVO:-sem detalhe}"
      else
        dbx_cmd_falhar "${DBX_TRANSFER_CLASSE:-erro_remoto}" "${DBX_TRANSFER_MOTIVO:-envio recusado}"
      fi
      return $?
    }
  fi

  local str_barra_fim=''
  dbx_progress_barra_gerar 100 20 str_barra_fim
  dbx_progress_mensagem "[upload] envio concluido com sucesso $str_barra_fim (100%)"

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
