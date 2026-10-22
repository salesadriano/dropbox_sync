#!/usr/bin/env bash
# lib/lote.sh — operacoes em lote da fase 9 (F-08; RF-136, RF-137; DIV-259, 262, 263).
#
# Camada: adaptadores. Depende de lib/auth, lib/http e lib/json (carregados pelo
# comando). Duas operacoes:
#
#   dbx_lote_excluir        `files/delete_batch` + `delete_batch/check` (exclusao)
#   dbx_lote_concluir_envio `upload_session/finish_batch_v2` (envio de pequenos)
#
# NENHUM ESTADO ENTRE EXECUCOES (DIV-263, RNF-38(c)): o job pendente nao e
# gravado; a exclusao que o servidor concluiu reaparece como ausente na proxima
# listagem, e o envio perdido e refeito pelo `content_hash`.
#
# A guarda destrutiva NAO mora aqui: quem chama (`sync --espelhar`; o `reter` nao usa lote, DIV-269) entrega uma
# lista que ja passou por todas as guardas, sem estado, e identificada por
# caminho canonico e `rev`. Esta biblioteca so executa e confere o resultado.
#
# CONFERENCIA POR POSICAO (RF-136(c)): so a entrada que o `check` confirma como
# `success` conta como excluida. Entrada com `failure`, ausente ou de tag
# desconhecida e FALHA do item, nunca sucesso.

[[ -n ${DBX_LOTE_CARREGADO:-} ]] && return 0
DBX_LOTE_CARREGADO=1

# Tamanho da fatia de exclusao (DIV-259: 250 consecutivas; o limite oficial de
# `delete_batch` nao esta nas fontes do projeto, e 250 tambem limita o dano de um
# job preso). Constante unica.
readonly DBX_LOTE_EXCLUSAO_FATIA=250
# Recuo do `check` (DIV-262): 1 s dobrando ate 10 s; teto de 120 s de espera
# acumulada por fatia. Estourado, a fatia inteira falha e a exclusao NAO e repetida.
readonly DBX_LOTE_ESPERA_INICIAL=1
readonly DBX_LOTE_ESPERA_MAXIMA=10
readonly DBX_LOTE_ESPERA_TETO=120
# Entradas por `finish_batch_v2` (RF-137(b): no maximo 1000). 250 e o que a
# resposta cabe no teto do analisador de JSON (lib/json, 256 KiB, ~490 B por
# entrada): 1000 entradas seriam recusadas como `tamanho` (DIV-SD-1).
# shellcheck disable=SC2034  # lida por commands/sync (grupos do finish_batch_v2)
readonly DBX_LOTE_ENVIO_MAXIMO=250

readonly DBX_LOTE_URL_EXCLUIR='https://api.dropboxapi.com/2/files/delete_batch'
readonly DBX_LOTE_URL_CONFERIR='https://api.dropboxapi.com/2/files/delete_batch/check'
readonly DBX_LOTE_URL_CONCLUIR='https://api.dropboxapi.com/2/files/upload_session/finish_batch_v2'

# Entrada de dbx_lote_excluir: vetores paralelos (caminho e, se houver, `rev`).
declare -ga DBX_LOTE_CAMINHOS=() DBX_LOTE_REVS=()
# Saida, por indice: ok | ausente | falhou | nao_tentado; e, quando houver, a
# classe e o motivo curto (so texto do dbx), mais a `metadata` do que foi
# confirmado (`.tag` e `path_lower`), para a conferencia de quem chama.
declare -ga DBX_LOTE_RESULTADO=() DBX_LOTE_CLASSE=() DBX_LOTE_MOTIVO=()
declare -ga DBX_LOTE_META_TAG=() DBX_LOTE_META_PL=()
# Classe que interrompe o lote (autenticacao, limite_taxa, rede) ou vazio.
DBX_LOTE_PARADA=''
# Funcao opcional chamada antes de cada fatia com <inicio> <fim>; status != 0
# interrompe: o restante fica `nao_tentado`.
DBX_LOTE_GANCHO_FATIA=''
# Indices em voo (fatia corrente), para o resumo de sinal de quem chama.
declare -ga DBX_LOTE_EM_VOO=()

# _dbx_lote_dormir <segundos> — ponto unico de espera (os testes o substituem).
_dbx_lote_dormir() { sleep "$1"; }

# _dbx_lote_fatia_falhou <inicio> <fim> <classe> <motivo> — falha a fatia inteira.
_dbx_lote_fatia_falhou() {
  local i
  for ((i = $1; i < $2; i++)); do
    DBX_LOTE_RESULTADO[i]='falhou' DBX_LOTE_CLASSE[i]=$3 DBX_LOTE_MOTIVO[i]=$4
  done
  case $3 in autenticacao | limite_taxa | rede) DBX_LOTE_PARADA=$3 ;; esac
}

# _dbx_lote_resumo_http — resumo SEGURO da recusa HTTP em _DBX_LOTE_RESUMO: so o
# prefixo do `error_summary` no alfabeto de tag (minusculas, `_`, `/`), como o
# item a item faz (RF-59(c)); corpo bruto e texto puro nunca entram (podem trazer
# token). Sem prefixo, `HTTP <codigo>`.
_dbx_lote_resumo_http() {
  local marca=${DBX_HTTP_RESUMO_DO_SERVICO:-}
  marca=${marca%%[!a-z_/]*}
  marca=${marca:0:80}
  while [[ $marca == */ ]]; do marca=${marca%/}; done
  _DBX_LOTE_RESUMO=${marca:-"HTTP ${DBX_HTTP_CODIGO:-0}"}
}

# _dbx_lote_corpo_excluir <inicio> <fim> — corpo JSON da fatia em _DBX_LOTE_CORPO.
_dbx_lote_corpo_excluir() {
  local i caminho rev lista=''
  for ((i = $1; i < $2; i++)); do
    dbx_json_escapar_cadeia "${DBX_LOTE_CAMINHOS[i]}"
    caminho=$DBX_JSON_ESCAPADO
    lista+="${lista:+,}{\"path\":\"$caminho\""
    if [[ -n ${DBX_LOTE_REVS[i]:-} ]]; then
      dbx_json_escapar_cadeia "${DBX_LOTE_REVS[i]}"
      rev=$DBX_JSON_ESCAPADO
      lista+=",\"parent_rev\":\"$rev\""
    fi
    lista+='}'
  done
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  _DBX_LOTE_CORPO="{\"entries\":[$lista]}"
}

# _dbx_lote_ler_marca <segmentos...> — `.tag` em _DBX_LOTE_MARCA ('' se ausente).
_dbx_lote_ler_marca() {
  _DBX_LOTE_MARCA=''
  dbx_json_valor "$@" >/dev/null 2>&1 && _DBX_LOTE_MARCA=$DBX_JSON_RESULTADO
  return 0
}

# _dbx_lote_conferir <inicio> <fim> — le `entries` do `complete` (contexto `lote`
# corrente) e confere por posicao.
_dbx_lote_conferir() {
  local inicio=$1 fim=$2 total=$((${2} - ${1})) n=0 i k marca falha
  if dbx_json_existe entries; then
    n=$(dbx_json_tamanho_arranjo entries 2>/dev/null) || n=0
  fi
  if ((n > total)); then
    _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto 'resposta do lote incoerente: mais entradas que o enviado'
    return 0
  fi
  for ((k = 0; k < total; k++)); do
    i=$((inicio + k))
    if ((k >= n)); then
      DBX_LOTE_RESULTADO[i]='falhou' DBX_LOTE_CLASSE[i]='erro_remoto'
      DBX_LOTE_MOTIVO[i]='sem confirmacao do servidor para este item'
      continue
    fi
    _dbx_lote_ler_marca entries "$k" '.tag'
    marca=$_DBX_LOTE_MARCA
    case $marca in
      success)
        DBX_LOTE_RESULTADO[i]='ok'
        _dbx_lote_ler_marca entries "$k" metadata '.tag'
        DBX_LOTE_META_TAG[i]=$_DBX_LOTE_MARCA
        _dbx_lote_ler_marca entries "$k" metadata path_lower
        DBX_LOTE_META_PL[i]=$_DBX_LOTE_MARCA
        # Chave repetida no documento: a resposta nao e confiavel (RF-97(e)).
        ((${DBX_JSON_DUPLICADAS:-0} > 0)) && DBX_LOTE_META_TAG[i]='duplicada'
        ;;
      failure)
        _dbx_lote_ler_marca entries "$k" failure '.tag'
        falha=$_DBX_LOTE_MARCA
        _dbx_lote_ler_marca entries "$k" failure path_lookup '.tag'
        if [[ $falha == 'path_lookup' && $_DBX_LOTE_MARCA == 'not_found' ]]; then
          DBX_LOTE_RESULTADO[i]='ausente' DBX_LOTE_CLASSE[i]='nao_encontrado'
          DBX_LOTE_MOTIVO[i]='path_lookup/not_found'
        else
          DBX_LOTE_RESULTADO[i]='falhou' DBX_LOTE_CLASSE[i]='erro_remoto'
          DBX_LOTE_MOTIVO[i]="exclusao recusada (${falha:-sem detalhe})"
          [[ $falha == 'too_many_write_operations' || $falha == 'too_many_files' ]] &&
            DBX_LOTE_CLASSE[i]='limite_taxa'
          if [[ $falha == 'path_write' ]]; then
            _dbx_lote_ler_marca entries "$k" failure path_write '.tag'
            case $_DBX_LOTE_MARCA in
              conflict) DBX_LOTE_CLASSE[i]='conflito' ;;
              no_write_permission | insufficient_space) DBX_LOTE_CLASSE[i]='permissao' ;;
            esac
            DBX_LOTE_MOTIVO[i]="exclusao recusada (path_write/${_DBX_LOTE_MARCA:-sem detalhe})"
          fi
        fi
        ;;
      *)
        DBX_LOTE_RESULTADO[i]='falhou' DBX_LOTE_CLASSE[i]='erro_remoto'
        DBX_LOTE_MOTIVO[i]='entrada do lote sem resultado reconhecido'
        ;;
    esac
  done
}

# _dbx_lote_excluir_fatia <inicio> <fim> — lanca, consulta e confere uma fatia.
_dbx_lote_excluir_fatia() {
  local inicio=$1 fim=$2 espera=$DBX_LOTE_ESPERA_INICIAL acumulado=0 tag job='' corpo estado
  DBX_LOTE_EM_VOO=()
  local i
  for ((i = inicio; i < fim; i++)); do DBX_LOTE_EM_VOO+=("$i"); done
  _dbx_lote_corpo_excluir "$inicio" "$fim"
  corpo=$_DBX_LOTE_CORPO
  # Escrita: sem retentativa cega (nao idempotente para esta camada).
  dbx_auth_requisitar POST "$DBX_LOTE_URL_EXCLUIR" "$corpo" nao
  estado=$?
  corpo=''
  _DBX_LOTE_CORPO=''
  if ((estado != 0)); then
    _dbx_lote_resumo_http
    _dbx_lote_fatia_falhou "$inicio" "$fim" "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "lote recusado: $_DBX_LOTE_RESUMO"
    DBX_LOTE_EM_VOO=()
    return 0
  fi
  dbx_json_contexto lote || { _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto 'contexto de analise indisponivel'; return 0; }
  if ! dbx_json_analisar "$DBX_HTTP_CORPO"; then
    dbx_json_descartar lote
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto 'resposta do lote nao interpretavel'
    DBX_LOTE_EM_VOO=()
    return 0
  fi
  _dbx_lote_ler_marca '.tag'
  tag=$_DBX_LOTE_MARCA
  if [[ $tag == 'async_job_id' ]]; then
    _dbx_lote_ler_marca async_job_id
    job=$_DBX_LOTE_MARCA
  fi
  if [[ $tag == 'complete' ]]; then
    _dbx_lote_conferir "$inicio" "$fim"
    dbx_json_descartar lote
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    DBX_LOTE_EM_VOO=()
    return 0
  fi
  dbx_json_descartar lote
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  if [[ -z $job || $tag != 'async_job_id' ]]; then
    _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto 'resposta do lote sem identificador de job'
    DBX_LOTE_EM_VOO=()
    return 0
  fi
  dbx_json_escapar_cadeia "$job"
  local corpo_check="{\"async_job_id\":\"$DBX_JSON_ESCAPADO\"}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  while :; do
    dbx_auth_requisitar POST "$DBX_LOTE_URL_CONFERIR" "$corpo_check" sim
    estado=$?
    if ((estado != 0)); then
      _dbx_lote_resumo_http
      _dbx_lote_fatia_falhou "$inicio" "$fim" "${DBX_HTTP_CLASSE:-erro_remoto}" \
        "consulta do lote recusada: $_DBX_LOTE_RESUMO"
      break
    fi
    dbx_json_contexto lote || { _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto 'contexto de analise indisponivel'; break; }
    if ! dbx_json_analisar "$DBX_HTTP_CORPO"; then
      dbx_json_descartar lote
      dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
      _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto 'resposta da consulta do lote nao interpretavel'
      break
    fi
    _dbx_lote_ler_marca '.tag'
    tag=$_DBX_LOTE_MARCA
    case $tag in
      complete)
        _dbx_lote_conferir "$inicio" "$fim"
        dbx_json_descartar lote
        dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
        break
        ;;
      in_progress)
        dbx_json_descartar lote
        dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
        if ((acumulado + espera > DBX_LOTE_ESPERA_TETO)); then
          _dbx_lote_fatia_falhou "$inicio" "$fim" nao_concluida \
            "lote nao confirmado em ${DBX_LOTE_ESPERA_TETO} s; a exclusao nao foi repetida"
          break
        fi
        _dbx_lote_dormir "$espera"
        acumulado=$((acumulado + espera))
        espera=$((espera * 2))
        ((espera > DBX_LOTE_ESPERA_MAXIMA)) && espera=$DBX_LOTE_ESPERA_MAXIMA
        ;;
      *)
        dbx_json_descartar lote
        dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
        _dbx_lote_fatia_falhou "$inicio" "$fim" erro_remoto \
          "lote falhou no servidor (${tag:-sem detalhe}); a exclusao nao foi repetida"
        break
        ;;
    esac
  done
  DBX_LOTE_EM_VOO=()
  return 0
}

# dbx_lote_excluir — executa a exclusao de DBX_LOTE_CAMINHOS (com DBX_LOTE_REVS)
# em fatias de DBX_LOTE_EXCLUSAO_FATIA, em serie. Lista vazia nao chama a API.
# Resultado em DBX_LOTE_RESULTADO e afins. Devolve 0 (o resultado e por item).
dbx_lote_excluir() {
  local total=${#DBX_LOTE_CAMINHOS[@]} ini fim i
  # shellcheck disable=SC2034  # canais publicos, lidos por commands/sync
  DBX_LOTE_RESULTADO=() DBX_LOTE_CLASSE=() DBX_LOTE_MOTIVO=() DBX_LOTE_META_TAG=() DBX_LOTE_META_PL=()
  DBX_LOTE_PARADA=''
  # shellcheck disable=SC2034  # canal publico, lido por commands/sync
  for ((i = 0; i < total; i++)); do DBX_LOTE_RESULTADO[i]='nao_tentado'; done
  ((total > 0)) || return 0
  # RF-15, segunda barreira da simulacao: o ponto unico de escrita em lote.
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then # MUTACAO:simulacao_lote
    return 0
  fi
  for ((ini = 0; ini < total; ini += DBX_LOTE_EXCLUSAO_FATIA)); do
    fim=$((ini + DBX_LOTE_EXCLUSAO_FATIA))
    ((fim > total)) && fim=$total
    [[ -z $DBX_LOTE_PARADA ]] || break
    if [[ -n $DBX_LOTE_GANCHO_FATIA ]]; then
      "$DBX_LOTE_GANCHO_FATIA" "$ini" "$fim" || break
    fi
    _dbx_lote_excluir_fatia "$ini" "$fim"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Envio em lote (RF-137)
# ---------------------------------------------------------------------------

# Entrada de dbx_lote_concluir_envio: por indice, a sessao, o deslocamento (bytes
# enviados no `start`) e o objeto de publicacao (`commit`). Saida: ok | falhou,
# com classe e motivo.
declare -ga DBX_LOTE_SESSOES=() DBX_LOTE_DESLOCAMENTOS=() DBX_LOTE_COMMITS=()
declare -ga DBX_LOTE_ENVIO_RESULTADO=() DBX_LOTE_ENVIO_CLASSE=() DBX_LOTE_ENVIO_MOTIVO=()
# Por indice: `content_hash` devolvido pelo servico para a entrada `success`
# (vazio = nao devolveu; DIV-278). A conferencia com o resumo local e de quem
# chama, por dbx_transfer_conferir_resumo, a mesma do envio unitario.
declare -ga DBX_LOTE_ENVIO_HASH=() DBX_LOTE_ENVIO_HASH_DEVOLVIDO=()

# dbx_lote_concluir_envio <inicio> <fim> — UMA chamada `finish_batch_v2` para as
# entradas [inicio, fim) (no maximo DBX_LOTE_ENVIO_MAXIMO), conferida por posicao.
# So no processo principal e em serie (DIV-264). Devolve 0; o resultado e por item.
# shellcheck disable=SC2034  # DBX_LOTE_ENVIO_*: canais publicos, lidos por commands/sync
dbx_lote_concluir_envio() {
  local inicio=$1 fim=$2 i k total n=0 lista='' corpo estado marca falha sub
  total=$((fim - inicio))
  for ((i = inicio; i < fim; i++)); do
    dbx_json_escapar_cadeia "${DBX_LOTE_SESSOES[i]}"
    lista+="${lista:+,}{\"cursor\":{\"session_id\":\"$DBX_JSON_ESCAPADO\",\"offset\":${DBX_LOTE_DESLOCAMENTOS[i]}},\"commit\":${DBX_LOTE_COMMITS[i]}}"
  done
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  corpo="{\"entries\":[$lista]}"
  dbx_auth_requisitar POST "$DBX_LOTE_URL_CONCLUIR" "$corpo" nao
  estado=$?
  corpo=''
  if ((estado != 0)); then
    for ((i = inicio; i < fim; i++)); do
      DBX_LOTE_ENVIO_RESULTADO[i]='falhou' DBX_LOTE_ENVIO_CLASSE[i]=${DBX_HTTP_CLASSE:-erro_remoto}
      DBX_LOTE_ENVIO_MOTIVO[i]="lote recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    done
    return 0
  fi
  if ! dbx_json_contexto lote || ! dbx_json_analisar "$DBX_HTTP_CORPO"; then
    dbx_json_descartar lote
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    for ((i = inicio; i < fim; i++)); do
      DBX_LOTE_ENVIO_RESULTADO[i]='falhou' DBX_LOTE_ENVIO_CLASSE[i]='erro_remoto'
      DBX_LOTE_ENVIO_MOTIVO[i]='resposta do lote nao interpretavel'
    done
    return 0
  fi
  if dbx_json_existe entries; then
    n=$(dbx_json_tamanho_arranjo entries 2>/dev/null) || n=0
  fi
  for ((k = 0; k < total; k++)); do
    i=$((inicio + k))
    marca='' falha=''
    if ((k < n)) && ((n <= total)); then
      _dbx_lote_ler_marca entries "$k" '.tag'
      marca=$_DBX_LOTE_MARCA
    fi
    if [[ $marca == 'success' ]]; then
      DBX_LOTE_ENVIO_RESULTADO[i]='ok'
      DBX_LOTE_ENVIO_HASH_DEVOLVIDO[i]='nao'
      DBX_LOTE_ENVIO_HASH[i]=''
      if dbx_json_existe entries "$k" content_hash 2>/dev/null; then
        _dbx_lote_ler_marca entries "$k" content_hash
        DBX_LOTE_ENVIO_HASH_DEVOLVIDO[i]='sim'
        DBX_LOTE_ENVIO_HASH[i]=$_DBX_LOTE_MARCA
      fi
      continue
    fi
    DBX_LOTE_ENVIO_RESULTADO[i]='falhou' DBX_LOTE_ENVIO_CLASSE[i]='erro_remoto'
    DBX_LOTE_ENVIO_MOTIVO[i]='sem confirmacao do servidor para este item'
    if [[ $marca == 'failure' ]]; then
      _dbx_lote_ler_marca entries "$k" failure '.tag'
      falha=$_DBX_LOTE_MARCA
      DBX_LOTE_ENVIO_MOTIVO[i]="envio recusado (${falha:-sem detalhe})"
      if [[ $falha == 'path' ]]; then
        _dbx_lote_ler_marca entries "$k" failure path '.tag'
        sub=$_DBX_LOTE_MARCA
        DBX_LOTE_ENVIO_MOTIVO[i]="path/${sub:-sem detalhe}"
        case $sub in
          conflict)
            DBX_LOTE_ENVIO_CLASSE[i]='conflito'
            # Mesmo resumo do envio unitario (`path/conflict/file`).
            _dbx_lote_ler_marca entries "$k" failure path conflict '.tag'
            [[ -n $_DBX_LOTE_MARCA ]] && DBX_LOTE_ENVIO_MOTIVO[i]+="/$_DBX_LOTE_MARCA"
            ;;
          insufficient_space) DBX_LOTE_ENVIO_CLASSE[i]='espaco' ;;
        esac
      fi
    fi
  done
  dbx_json_descartar lote
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  return 0
}
