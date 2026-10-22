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
  local origem='' destino='' modo='add' rev='' forcar='nao' sem_retomada='nao'
  local tem_limite='nao' opcao_limite='' valor_limite=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      # RF-82: limite de banda das requisicoes de conteudo; o ultimo vence.
      --limite-banda | --bwlimit)
        opcao_limite=$1
        shift
        valor_limite=${1-}
        tem_limite='sim'
        ;;
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
      # RF-108(a) (fase 7a): sem ler, gravar nem apagar estado de retomada.
      --sem-retomada | --no-resume)
        sem_retomada='sim'
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

  # RF-82(b)(g): opcao ou variavel, validada antes de qualquer chamada.
  dbx_cmd_limite_banda "$tem_limite" "$opcao_limite" "$valor_limite" || {
    dbx_cmd_falhar uso_invalido "$DBX_CMD_LIMITE_MOTIVO"
    return $?
  }

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
  _dbx_cmd_caminho_remoto "$destino" || return $?
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
    # RF-67(e): no diretorio, `--forcar` chega ao `sync`, onde so pula o espaco.
    local -a forcar_sync=()
    [[ $forcar == 'sim' ]] && forcar_sync=(--forcar)
    # RF-82: o limite vai ja convertido, para a variavel nao ser relida no sync.
    [[ -n $DBX_CMD_LIMITE_BANDA ]] && forcar_sync+=(--limite-banda "$DBX_CMD_LIMITE_BANDA")
    # RF-133: o upload de pasta nunca usa --paralelo nem DBX_PARALELO (fora do
    # escopo da fase 9).
    # shellcheck disable=SC2034  # lida por commands/sync, no escopo dinamico
    local DBX_CMD_SYNC_CHAMADOR='upload'
    dbx_cmd_sync_executar --enviar ${forcar_sync[@]+"${forcar_sync[@]}"} \
      --origem "$origem" --destino "$alvo_remoto"
    return $?
  fi

  # shellcheck source=lib/transfer.sh
  . "${BASH_SOURCE[0]%/*}/../lib/transfer.sh"
  dbx_transfer_objeto_de_publicacao "$remoto" "$modo" "$rev" "$origem"

  # A guarda de cabecalho e de `lib/http` e recusa antes de qualquer invocacao do
  # cliente. Verificar aqui tambem seria duplicar a regra em dois lugares — e a
  # forma exata das nove ocorrencias da familia de gemeos.

  # RF-15 — GATE UNICO, ANTES DA BIFURCACAO. Ver a nota no cabecalho.
  # RF-67(f): em simulacao a consulta de espaco e feita (e leitura) e, se nao
  # couber, o plano so anuncia que recusaria; o codigo continua 0.
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    # O-3 (RF-15/RF-44 emendados): mesma ordem da execucao real — primeiro a
    # leitura do `content_hash` remoto (RF-60), e so sem dispensa a checagem
    # de espaco. Leitura e permitida em simulacao; o cache nao e gravado.
    local recusaria='' dispensado='nao'
    if [[ $forcar != 'sim' && $origem != '-' && -z $rev ]] &&
      _dbx_cmd_upload_hash_remoto "$remoto" &&
      dbx_hash_publicar_arquivo "$origem" 2>/dev/null &&
      dbx_hash_iguais "$DBX_HASH_RESULTADO" "$DBX_CMD_UPLOAD_HASH_REMOTO"; then
      dispensado='sim'
    else
      _dbx_cmd_upload_checar_espaco "$origem" "$forcar" || recusaria=$DBX_CMD_ESPACO_MOTIVO
    fi
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao upload
    dbx_output_campo origem "$origem"
    dbx_output_campo caminho "$remoto"
    if [[ $dispensado == 'sim' ]]; then
      dbx_output_campo status dispensado
      dbx_output_campo motivo inalterado
    else
      dbx_cmd_espaco_campos
    fi
    [[ -n $recusaria ]] && dbx_output_campo recusaria "$recusaria"
    dbx_output_campo limite_banda "$DBX_CMD_LIMITE_BANDA"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  # RF-60, RF-61: cache do `content_hash` local em `lib/state`, namespace
  # `upload-*`. A chave e o caminho fisico canonico (RF-62); o arquivo lido,
  # medido e enviado continua sendo `origem`, como o operador o nomeou.
  # RF-63(a), QA-P3-02: credencial incompleta recusa aqui, antes da rede, com a
  # classe e o motivo da autenticacao — a consulta abaixo falharia em silencio.
  # Gemeo de `commands/sync.sh` (mesmo conjunto, ver `dbx_auth_preparar`).
  dbx_auth_preparar || {
    dbx_cmd_falhar "$DBX_AUTH_CLASSE" "${DBX_AUTH_MOTIVO:-nao foi possivel obter o token de acesso}"
    return $?
  }

  # shellcheck source=lib/state.sh
  . "${BASH_SOURCE[0]%/*}/../lib/state.sh"
  local chave='' identidade_antes=''
  if [[ $origem != '-' ]] && dbx_path_local_canonico "$origem"; then
    chave=$DBX_PATH_RESULTADO
    dbx_hash_identidade "$origem" && identidade_antes=$DBX_HASH_IDENTIDADE
  fi

  # RF-60(g), (h), (i): `--forcar`, entrada padrao e `--rev` nao comparam.
  if [[ $forcar != 'sim' && $origem != '-' && -z $rev ]]; then
    dbx_progress_mensagem "[upload] analisando arquivo local: $origem (consultando o destino remoto)"
    if ! _dbx_cmd_upload_hash_remoto "$remoto"; then
      dbx_errors_redigir "${DBX_CMD_FALHA_MOTIVO:-sem detalhe}" >/dev/null
      dbx_progress_mensagem "[upload] resultado da analise: $origem -> sem arquivo comparavel no destino (necessita envio; classe=${DBX_CMD_FALHA_CLASSE:-desconhecido}; motivo=$DBX_ERRORS_REDIGIDO)"
    else
      local hash_local=''
      if [[ -n $chave ]] && dbx_state_upload_consultar "$chave" "$identidade_antes"; then
        hash_local=$DBX_STATE_HASH
        dbx_progress_mensagem "[upload] resumo local em cache: $origem"
      else
        dbx_progress_mensagem "[upload] calculando resumo local: $origem"
        dbx_hash_publicar_arquivo "$origem" && hash_local=$DBX_HASH_RESULTADO
      fi
      if [[ -n $hash_local ]] && dbx_hash_iguais "$hash_local" "$DBX_CMD_UPLOAD_HASH_REMOTO"; then
        dbx_progress_mensagem "[upload] resultado da analise: $origem -> conteudo identico no destino (envio dispensado)"
        # A gravacao acontece tambem na dispensa: com resumo calculado, guarda;
        # com acerto, renova o carimbo de uso que a poda le (RF-61(g), (i)).
        _dbx_cmd_upload_gravar_cache "$chave" "$hash_local" "$identidade_antes" "$origem"
        # RF-102(c), C5 (fase 7a): a dispensa vem antes da retomada, e o
        # registro da chave, que ja nao vale, sai (sob a trava).
        if [[ $sem_retomada != 'sim' ]] && _dbx_cmd_upload_retomavel "$origem" "$chave"; then
          dbx_cmd_retomada_limpar upload "$chave" "$remoto"
        fi
        dbx_cmd_iniciar_saida
        dbx_output_campo operacao upload
        dbx_output_campo origem "$origem"
        dbx_output_campo caminho "$remoto"
        dbx_output_campo status dispensado
        dbx_output_campo motivo inalterado
        dbx_output_campo limite_banda "$DBX_CMD_LIMITE_BANDA"
        dbx_output_render
        return 0
      fi
      dbx_progress_mensagem "[upload] resultado da analise: $origem -> conteudo diferente no destino (necessita envio)"
    fi
  fi

  # RF-67: a recusa por espaco vem antes de qualquer escrita, inclusive da
  # abertura de sessao, e depois da dispensa por conteudo identico (que nao
  # envia nada e por isso nao consulta).
  _dbx_cmd_upload_checar_espaco "$origem" "$forcar" || {
    dbx_cmd_falhar espaco "$DBX_CMD_ESPACO_MOTIVO"
    return $?
  }

  # Fase 7a (RF-102, RF-103): so arquivo regular que vai por sessao retoma, e
  # so depois da decisao do comando acima (C5). A trava do registro fica com
  # este processo ate o fim do envio; ocupada, segue sem retomada.
  local retomavel='nao'
  if [[ $sem_retomada != 'sim' ]] && _dbx_cmd_upload_retomavel "$origem" "$chave"; then
    retomavel='sim'
    if dbx_cmd_retomada_preparar upload "$chave" "$remoto" && dbx_hash_identidade "$origem"; then
      # shellcheck disable=SC2034  # entradas de lib/transfer
      DBX_TRANSFER_RETOMADA_ATIVA='sim'
      # shellcheck disable=SC2034
      DBX_TRANSFER_RETOMADA_IDENTIDADE=$DBX_HASH_IDENTIDADE
      # shellcheck disable=SC2034
      DBX_TRANSFER_AVISAR=dbx_cmd_avisar
    else
      dbx_state_retomada_soltar
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
    # RF-108(b): acrescimo compativel, so no caminho retomavel.
    if [[ $retomavel == 'sim' ]]; then
      dbx_output_campo retomada "$DBX_TRANSFER_RETOMADA"
      dbx_output_campo retomado_de "$DBX_TRANSFER_RETOMADO_DE"
    fi
  else
    dbx_output_campo modo_de_envio requisicao_unica
  fi
  dbx_cmd_espaco_campos
  _dbx_cmd_metadado_em

  # RF-61(g), (j): o resumo do que foi enviado. Por sessao, o calculado sobre os
  # bytes lidos (`DBX_TRANSFER_CONTENT_HASH`, F-29); em requisicao unica, o que o
  # servico publicou para o conteudo recebido. Em ambos, so e guardado se a
  # identidade da origem nao mudou entre antes e depois do envio.
  if [[ $origem != '-' ]]; then
    local hash_enviado=''
    if [[ $por_sessao == 'sim' ]]; then
      hash_enviado=${DBX_TRANSFER_CONTENT_HASH:-}
    elif _dbx_cmd_campo content_hash; then
      hash_enviado=$DBX_CMD_LIDO
    fi
    _dbx_cmd_upload_gravar_cache "$chave" "$hash_enviado" "$identidade_antes" "$origem"
  fi

  _dbx_cmd_encerrar_consulta
  # RF-82(i): acrescimo compativel (RF-35); vazio sem limite.
  dbx_output_campo limite_banda "$DBX_CMD_LIMITE_BANDA"
  dbx_output_render
  return 0
}

# _dbx_cmd_upload_hash_remoto <caminho_remoto_api>
#
# RF-60: `get_metadata` do destino. Status 0 so quando o remoto e ARQUIVO com
# `content_hash` bem formado, publicado em DBX_CMD_UPLOAD_HASH_REMOTO. Qualquer
# outra coisa — `not_found`, pasta, falha de rede, resposta ilegivel — e status
# 1, e o chamador envia: a falha da consulta nunca dispensa o envio e nao aborta
# o comando (RF-60(d)). Nada e emitido aqui; o motivo vai em DBX_CMD_FALHA_CLASSE
# e DBX_CMD_FALHA_MOTIVO (O-5) e o chamador o inclui no progresso. A leitura do
# JSON e de `dbx_cmd_ler_corpo_silencioso`, em `lib/cmd`.
DBX_CMD_UPLOAD_HASH_REMOTO=''
_dbx_cmd_upload_hash_remoto() {
  local remoto=$1
  DBX_CMD_UPLOAD_HASH_REMOTO=''
  DBX_CMD_FALHA_CLASSE=''
  DBX_CMD_FALHA_MOTIVO=''
  dbx_json_escapar_cadeia "$remoto"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/get_metadata' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\"}" sim >/dev/null 2>&1 || {
    DBX_CMD_FALHA_CLASSE=${DBX_HTTP_CLASSE:-erro_remoto}
    DBX_CMD_FALHA_MOTIVO="consulta recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return 1
  }
  dbx_cmd_ler_corpo_silencioso .tag content_hash || return 1
  if [[ ${DBX_CMD_CAMPOS[0]} != 'file' ]]; then
    DBX_CMD_FALHA_CLASSE='erro_remoto'
    DBX_CMD_FALHA_MOTIVO='o destino nao e um arquivo comparavel'
    return 1
  fi
  if ! dbx_hash_formato_valido "${DBX_CMD_CAMPOS[1]}"; then
    DBX_CMD_FALHA_CLASSE='erro_remoto'
    DBX_CMD_FALHA_MOTIVO='content_hash ausente ou malformado na resposta'
    return 1
  fi
  DBX_CMD_UPLOAD_HASH_REMOTO=${DBX_CMD_CAMPOS[1]}
  return 0
}

# _dbx_cmd_upload_retomavel <origem> <chave> — 0 quando o envio e retomavel
# entre execucoes (RF-102(a)): arquivo regular, com chave canonica, que vai por
# sessao (acima de 150 MiB). Entrada padrao e requisicao unica: 1.
_dbx_cmd_upload_retomavel() {
  [[ $1 != '-' && -n $2 && -f $1 ]] || return 1
  dbx_transfer_tamanho_de_arquivo "$1" || return 1
  dbx_transfer_precisa_de_sessao "$DBX_TRANSFER_TAMANHO"
}

# _dbx_cmd_upload_checar_espaco <origem> <forcar> — RF-67 no `upload`.
#
# O total e o tamanho MEDIDO do arquivo de origem. A entrada padrao (`-`) tem
# tamanho desconhecido e nao e checada nem consulta a API (RF-67(h)); `--forcar`
# pula a consulta (RF-67(e)). Status 1 quando nao cabe, com a mensagem em
# DBX_CMD_ESPACO_MOTIVO.
_dbx_cmd_upload_checar_espaco() {
  local origem=$1 forcar=$2
  if [[ $origem == '-' ]]; then
    dbx_cmd_espaco_checar 0
    # shellcheck disable=SC2034  # canal de lib/cmd, emitido por dbx_cmd_espaco_campos
    DBX_CMD_ESPACO_NECESSARIO=''
    return 0
  fi
  local tamanho=0
  dbx_transfer_tamanho_de_arquivo "$origem" && tamanho=$DBX_TRANSFER_TAMANHO
  dbx_cmd_espaco_checar "$tamanho" "$forcar"
}

# _dbx_cmd_upload_gravar_cache <chave> <resumo> <identidade_antes> <origem>
#
# A segunda leitura de `stat` e feita AQUI, depois do calculo ou do envio, e a
# admissao e de `lib/state` (RF-61(c), (d), (e)). Falha de gravacao — inclusive
# diretorio de estado alheio — nao muda resultado nem codigo de saida.
_dbx_cmd_upload_gravar_cache() {
  local chave=$1 resumo=$2 antes=$3 origem=$4
  [[ -n $chave && -n $resumo && -n $antes ]] || return 0
  dbx_hash_identidade "$origem" || return 0
  dbx_state_upload_gravar "$chave" "$resumo" "$antes" "$DBX_HASH_IDENTIDADE" >/dev/null 2>&1 || :
  return 0
}
