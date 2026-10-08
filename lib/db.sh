#!/usr/bin/env bash
# lib/db.sh — camada de persistencia local SQLite para metadados e controle de alteracoes.
#
# Camada: adaptadores. Depende de lib/errors.sh, lib/config.sh e lib/hash.sh.
#
# Mantem um banco relacional local SQLite em $XDG_STATE_HOME/dbx/dbx.db (ou ~/.local/state/dbx/dbx.db).
# Registra tamanho, mtime e content_hash dos arquivos locais, bem como o historico das
# operacoes de upload e sync bem-sucedidas.
#
# MECANISMO DE EXECUCAO HIBRIDO:
# Detecta prioritariamente o binario CLI `sqlite3`. Caso ausente no sistema, utiliza o
# runtime nativo de `python3` com modulo `sqlite3` da biblioteca padrao, garantindo
# operacao imediata sem bloquear por dependencias adicionais do gerenciador de pacotes.

[[ -n ${DBX_DB_CARREGADO:-} ]] && return 0
DBX_DB_CARREGADO=1

_dbx_db_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_db_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_db_diretorio=.
_dbx_db_diretorio=$(cd -P -- "$_dbx_db_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_db_diretorio/errors.sh"
# shellcheck source=lib/config.sh
. "$_dbx_db_diretorio/config.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_db_diretorio/hash.sh"
unset _dbx_db_diretorio

# shellcheck disable=SC2034
DBX_DB_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
# shellcheck disable=SC2034
DBX_DB_ERRO_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
# shellcheck disable=SC2034
readonly DBX_DB_ERRO_USO DBX_DB_ERRO_CONFIGURACAO

# shellcheck disable=SC2034 # canais publicos de saida
DBX_DB_ARQUIVO=''
DBX_DB_RESULTADO=''
DBX_DB_HASH=''
DBX_DB_OP_TAMANHO=''
DBX_DB_OP_MTIME=''
DBX_DB_OP_HASH=''
DBX_DB_OP_SUCESSO=''
DBX_DB_OP_REV=''
DBX_DB_OP_DATA=''

# dbx_db_caminho — define em DBX_DB_ARQUIVO o caminho do banco SQLite.
dbx_db_caminho() {
  local base
  DBX_DB_ARQUIVO=''
  dbx_config_caminho_de_estado || return $?
  base=$DBX_CONFIG_RESULTADO
  DBX_DB_ARQUIVO="$base/dbx.db"
  return 0
}

# _dbx_db_executar_sql <sql>
_dbx_db_executar_sql() {
  local sql=$1 db tmp_saida
  DBX_DB_RESULTADO=''
  dbx_db_caminho || return 1
  db=$DBX_DB_ARQUIVO
  local dir=${db%/*}
  [[ -d $dir ]] || mkdir -p -- "$dir" 2>/dev/null || return 1

  tmp_saida=$(mktemp "${TMPDIR:-/tmp}/dbx-sql.XXXXXX") || return 1

  if command -v sqlite3 >/dev/null 2>&1; then
    local bin_sqlite='sqlite3'
    "$bin_sqlite" -batch -noheader "$db" "$sql" >"$tmp_saida" 2>/dev/null || {
      rm -f -- "$tmp_saida"
      return 1
    }
    IFS= read -r -d '' DBX_DB_RESULTADO <"$tmp_saida" || :
    rm -f -- "$tmp_saida"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    local bin_py='python3'
    local script_py='import sys, sqlite3; con = sqlite3.connect(sys.argv[1], timeout=10.0); cur = con.cursor(); cur.executescript(sys.argv[2]) if ";" in sys.argv[2] and not sys.argv[2].strip().upper().startswith("SELECT") else [print("|".join("" if c is None else str(c) for c in r)) for r in cur.execute(sys.argv[2])]; con.commit(); con.close()'
    "$bin_py" -c "$script_py" "$db" "$sql" >"$tmp_saida" 2>/dev/null || {
      rm -f -- "$tmp_saida"
      return 1
    }
    IFS= read -r -d '' DBX_DB_RESULTADO <"$tmp_saida" || :
    rm -f -- "$tmp_saida"
    return 0
  fi

  rm -f -- "$tmp_saida"
  return 1
}

# dbx_db_inicializar — cria as tabelas e indices se nao existirem.
dbx_db_inicializar() {
  local ddl='PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 5000; CREATE TABLE IF NOT EXISTS metadados_arquivos (caminho_local TEXT PRIMARY KEY, tamanho INTEGER NOT NULL, mtime INTEGER NOT NULL, content_hash TEXT NOT NULL, atualizado_em INTEGER NOT NULL); CREATE TABLE IF NOT EXISTS operacoes_arquivos (caminho_local TEXT NOT NULL, caminho_remoto TEXT NOT NULL, tipo_operacao TEXT NOT NULL, content_hash TEXT NOT NULL, tamanho INTEGER NOT NULL, mtime INTEGER NOT NULL, rev_remoto TEXT, sucesso INTEGER NOT NULL DEFAULT 1, executado_em INTEGER NOT NULL, PRIMARY KEY (caminho_local, caminho_remoto, tipo_operacao)); CREATE INDEX IF NOT EXISTS idx_metadados_lookup ON metadados_arquivos(caminho_local, tamanho, mtime); CREATE INDEX IF NOT EXISTS idx_operacoes_lookup ON operacoes_arquivos(caminho_local, caminho_remoto, tipo_operacao, content_hash);'
  _dbx_db_executar_sql "$ddl" || return 1
  return 0
}

# dbx_db_consultar_metadado <caminho_local> <tamanho> <mtime>
dbx_db_consultar_metadado() {
  [[ $# -eq 3 ]] || return "$DBX_DB_ERRO_USO"
  local caminho=$1 tamanho=$2 mtime=$3 esc_caminho
  DBX_DB_HASH=''
  esc_caminho=${caminho//\'/\'\'}

  local query="SELECT content_hash FROM metadados_arquivos WHERE caminho_local = '$esc_caminho' AND tamanho = $tamanho AND mtime = $mtime LIMIT 1;"
  _dbx_db_executar_sql "$query" || return 1
  [[ -n $DBX_DB_RESULTADO ]] || return 1
  DBX_DB_HASH=${DBX_DB_RESULTADO%$'\n'}
  return 0
}

# dbx_db_salvar_metadado <caminho_local> <tamanho> <mtime> <content_hash>
dbx_db_salvar_metadado() {
  [[ $# -eq 4 ]] || return "$DBX_DB_ERRO_USO"
  local caminho=$1 tamanho=$2 mtime=$3 hash=$4
  local esc_caminho=${caminho//\'/\'\'} esc_hash=${hash//\'/\'\'}

  local sql="INSERT INTO metadados_arquivos (caminho_local, tamanho, mtime, content_hash, atualizado_em) VALUES ('$esc_caminho', $tamanho, $mtime, '$esc_hash', strftime('%s', 'now')) ON CONFLICT(caminho_local) DO UPDATE SET tamanho = excluded.tamanho, mtime = excluded.mtime, content_hash = excluded.content_hash, atualizado_em = excluded.atualizado_em;"
  _dbx_db_executar_sql "$sql" || return 1
  return 0
}

# dbx_db_consultar_operacao <caminho_local> <caminho_remoto> <tipo_operacao>
dbx_db_consultar_operacao() {
  [[ $# -eq 3 ]] || return "$DBX_DB_ERRO_USO"
  local caminho_local=$1 caminho_remoto=$2 tipo=$3
  local esc_local=${caminho_local//\'/\'\'}
  local esc_remoto=${caminho_remoto//\'/\'\'}
  local esc_tipo=${tipo//\'/\'\'}

  DBX_DB_OP_TAMANHO=''
  DBX_DB_OP_MTIME=''
  DBX_DB_OP_HASH=''
  DBX_DB_OP_SUCESSO=''
  DBX_DB_OP_REV=''
  DBX_DB_OP_DATA=''

  local query="SELECT tamanho, mtime, content_hash, sucesso, rev_remoto, executado_em FROM operacoes_arquivos WHERE caminho_local = '$esc_local' AND caminho_remoto = '$esc_remoto' AND tipo_operacao = '$esc_tipo' LIMIT 1;"
  _dbx_db_executar_sql "$query" || return 1
  [[ -n $DBX_DB_RESULTADO ]] || return 1

  local linha=${DBX_DB_RESULTADO%$'\n'}
  local IFS='|'
  # shellcheck disable=SC2034
  read -r DBX_DB_OP_TAMANHO DBX_DB_OP_MTIME DBX_DB_OP_HASH DBX_DB_OP_SUCESSO DBX_DB_OP_REV DBX_DB_OP_DATA <<<"$linha"
  return 0
}

# dbx_db_salvar_operacao <caminho_local> <caminho_remoto> <tipo_operacao> <tamanho> <mtime> <content_hash> [rev_remoto]
dbx_db_salvar_operacao() {
  [[ $# -ge 6 ]] || return "$DBX_DB_ERRO_USO"
  local caminho_local=$1 caminho_remoto=$2 tipo=$3 tamanho=$4 mtime=$5 hash=$6
  local rev=${7:-}
  local esc_local=${caminho_local//\'/\'\'}
  local esc_remoto=${caminho_remoto//\'/\'\'}
  local esc_tipo=${tipo//\'/\'\'}
  local esc_hash=${hash//\'/\'\'}
  local esc_rev=${rev//\'/\'\'}

  local sql="INSERT INTO operacoes_arquivos (caminho_local, caminho_remoto, tipo_operacao, content_hash, tamanho, mtime, rev_remoto, sucesso, executado_em) VALUES ('$esc_local', '$esc_remoto', '$esc_tipo', '$esc_hash', $tamanho, $mtime, '$esc_rev', 1, strftime('%s', 'now')) ON CONFLICT(caminho_local, caminho_remoto, tipo_operacao) DO UPDATE SET content_hash = excluded.content_hash, tamanho = excluded.tamanho, mtime = excluded.mtime, rev_remoto = excluded.rev_remoto, sucesso = excluded.sucesso, executado_em = excluded.executado_em;"
  _dbx_db_executar_sql "$sql" || return 1
  return 0
}

# dbx_db_arquivo_alterado <caminho_local> <caminho_remoto> <tipo_operacao> <tamanho> <mtime>
# Retorna 0 se o arquivo foi alterado (precisa de envio) ou e novo.
# Retorna 1 se o arquivo permanece inalterado desde a ultima operacao bem-sucedida.
dbx_db_arquivo_alterado() {
  [[ $# -eq 5 ]] || return "$DBX_DB_ERRO_USO"
  local caminho_local=$1 caminho_remoto=$2 tipo=$3 tamanho=$4 mtime=$5

  # Se nao houver registro previo bem-sucedido, considera alterado/pendente
  dbx_db_consultar_operacao "$caminho_local" "$caminho_remoto" "$tipo" || return 0
  [[ $DBX_DB_OP_SUCESSO -eq 1 ]] || return 0

  # Se tamanho e mtime forem identicos a ultima operacao, o arquivo e inalterado
  if [[ "$tamanho" == "$DBX_DB_OP_TAMANHO" && "$mtime" == "$DBX_DB_OP_MTIME" ]]; then
    return 1
  fi

  # Se tamanho ou mtime diferirem, compara o content_hash
  local hash_atual=''
  if dbx_db_consultar_metadado "$caminho_local" "$tamanho" "$mtime"; then
    hash_atual=$DBX_DB_HASH
  else
    local tmp_hash
    tmp_hash=$(mktemp "${TMPDIR:-/tmp}/dbx-hash.XXXXXX") || return 0
    if dbx_hash_conteudo_arquivo "$caminho_local" >"$tmp_hash" 2>/dev/null; then
      IFS= read -r hash_atual <"$tmp_hash" || :
    fi
    rm -f -- "$tmp_hash"
    [[ -n $hash_atual ]] && dbx_db_salvar_metadado "$caminho_local" "$tamanho" "$mtime" "$hash_atual"
  fi

  # Se o hash de conteudo for identico ao da operacao anterior bem-sucedida,
  # apenas o carimbo mudou, o conteudo nao. Atualiza o banco e declara inalterado.
  if [[ -n $hash_atual && "$hash_atual" == "$DBX_DB_OP_HASH" ]]; then
    dbx_db_salvar_operacao "$caminho_local" "$caminho_remoto" "$tipo" "$tamanho" "$mtime" "$hash_atual" "$DBX_DB_OP_REV"
    return 1
  fi

  return 0
}
