#!/usr/bin/env bash
# Testes de lib/db.sh — persistencia local SQLite para metadados e controle de alteracoes.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"
. "$DBX_HARNESS_RAIZ/lib/db.sh"

_ambiente_db() {
  local area=$1
  export XDG_STATE_HOME="$area"
  export XDG_CONFIG_HOME="$area"
  dbx_db_inicializar || return 1
}

teste_db_caminho_e_inicializacao() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/db_area.XXXXXX")
  _ambiente_db "$area"
  dbx_db_caminho
  assert_igual "$area/dbx/dbx.db" "$DBX_DB_ARQUIVO" "caminho do banco deve seguir XDG_STATE_HOME"
  assert_arquivo_existe "$DBX_DB_ARQUIVO" "banco SQLite deve ser criado fisicamente"
}

teste_db_salvar_e_consultar_metadado() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/db_area.XXXXXX")
  _ambiente_db "$area"
  local arq="/tmp/teste_db.txt"
  local hash="11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff"

  # Nao deve existir antes
  assert_status 1 dbx_db_consultar_metadado "$arq" 100 123456

  # Salva
  assert_status 0 dbx_db_salvar_metadado "$arq" 100 123456 "$hash"

  # Consulta existente com mesmos tamanho e mtime
  assert_status 0 dbx_db_consultar_metadado "$arq" 100 123456
  assert_igual "$hash" "$DBX_DB_HASH" "hash recuperado deve coincidir"

  # Consulta com mtime diferente nao deve encontrar
  assert_status 1 dbx_db_consultar_metadado "$arq" 100 999999
}

teste_db_salvar_e_consultar_operacao() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/db_area.XXXXXX")
  _ambiente_db "$area"
  local arq="/dados/bkp.tar.gz" remoto="/PeOuro/bkp.tar.gz"
  local hash="aabbccddeeff11223344556677889900aabbccddeeff11223344556677889900"

  # Nao deve existir antes
  assert_status 1 dbx_db_consultar_operacao "$arq" "$remoto" "upload"

  # Salva operacao de upload
  assert_status 0 dbx_db_salvar_operacao "$arq" "$remoto" "upload" 2048 1600000000 "$hash" "rev123"

  # Consulta
  assert_status 0 dbx_db_consultar_operacao "$arq" "$remoto" "upload"
  assert_igual "2048" "$DBX_DB_OP_TAMANHO" "tamanho registrado deve coincidir"
  assert_igual "1600000000" "$DBX_DB_OP_MTIME" "mtime registrado deve coincidir"
  assert_igual "$hash" "$DBX_DB_OP_HASH" "hash registrado deve coincidir"
  assert_igual "rev123" "$DBX_DB_OP_REV" "rev registrado deve coincidir"
}

teste_db_arquivo_alterado_logica() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/db_area.XXXXXX")
  _ambiente_db "$area"
  local dir="$DBX_TESTES_TMP/db_teste_$$"
  mkdir -p "$dir"
  local arq="$dir/arquivo.txt"
  printf 'conteudo 1' >"$arq"

  local tam mtime hash remoto="/remoto/arquivo.txt"
  tam=$(stat -c '%s' "$arq")
  mtime=$(stat -c '%Y' "$arq")
  hash=$(dbx_hash_conteudo_arquivo "$arq")

  # 1. Arquivo novo (sem operacao previa) -> deve reportar alterado (exit 0)
  assert_status 0 dbx_db_arquivo_alterado "$arq" "$remoto" "upload" "$tam" "$mtime"

  # Registra operacao concluida com sucesso
  dbx_db_salvar_operacao "$arq" "$remoto" "upload" "$tam" "$mtime" "$hash"

  # 2. Mesmo tamanho e mtime -> deve reportar inalterado (exit 1)
  assert_status 1 dbx_db_arquivo_alterado "$arq" "$remoto" "upload" "$tam" "$mtime"

  # 3. Mtime alterado (touch), mas conteudo identico -> deve reconhecer conteudo igual e retornar inalterado (exit 1)
  sleep 1
  touch "$arq"
  local novo_mtime
  novo_mtime=$(stat -c '%Y' "$arq")
  assert_status 1 dbx_db_arquivo_alterado "$arq" "$remoto" "upload" "$tam" "$novo_mtime"

  # 4. Conteudo alterado -> deve reportar alterado (exit 0)
  printf 'conteudo modificado' >"$arq"
  tam=$(stat -c '%s' "$arq")
  novo_mtime=$(stat -c '%Y' "$arq")
  assert_status 0 dbx_db_arquivo_alterado "$arq" "$remoto" "upload" "$tam" "$novo_mtime"
}

harness_executar "$@"
