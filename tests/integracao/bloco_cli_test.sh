#!/usr/bin/env bash
# RF-186 pela CLI: `--bloco`/`--batch`/`DBX_BLOCO` em sync, upload e download.
# Valor invalido sai com 2 ANTES de qualquer rede ou estado. O curl do cenario
# so registra a chamada e falha: chamada registrada onde nao devia e achado.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly USO=2

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/bloco.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local/pasta" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf 'x' >"$base/local/pasta/a.txt"
  printf 'x' >"$base/local/arquivo.txt"
  printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexit 22\n' "$BASH" "$base/chamadas" >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() {
  local base=$1
  shift
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_AMBIENTE[@]+"${DBX_T_AMBIENTE[@]}"} \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

teste_blc_sync_valor_invalido_sai_2_antes_da_rede_e_do_estado() {
  local base valor opcao
  base=$(_cenario)
  for opcao in --bloco --batch; do
    for valor in 0 1000001 -1 +2 01 abc '' ' 2' 1.5; do
      _rodar "$base" sync --receber --origem /r --destino "$base/local" "$opcao" "$valor"
      assert_igual "$USO" "$DBX_ESTADO" "sync $opcao [$valor]"
      assert_contem "$opcao" "$DBX_ERRO" "nomeia a opcao: [$valor]"
    done
  done
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --bloco
  assert_igual "$USO" "$DBX_ESTADO" 'sem valor'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
  assert_arquivo_ausente "$base/estado" 'nenhum estado'
}

teste_blc_sync_variavel_invalida_nomeia_a_variavel_e_a_opcao_vence() {
  local base valor
  base=$(_cenario)
  for valor in 0 1000001 abc '' 01; do
    DBX_T_AMBIENTE=("DBX_BLOCO=$valor")
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r
    assert_igual "$USO" "$DBX_ESTADO" "variavel [$valor]"
    assert_contem 'DBX_BLOCO' "$DBX_ERRO" "nomeia a variavel: [$valor]"
  done
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
  DBX_T_AMBIENTE=(DBX_BLOCO=abc)
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --bloco 100
  assert_diferente "$USO" "$DBX_ESTADO" 'a opcao vence a variavel invalida (a rede do cenario falha, nao o uso)'
  assert_nao_contem 'DBX_BLOCO' "$DBX_ERRO" 'a variavel nao foi lida'
}

teste_blc_upload_e_download_de_pasta_validam_antes_da_rede() {
  local base
  base=$(_cenario)
  _rodar "$base" upload --bloco 0 "$base/local/pasta" /pasta
  assert_igual "$USO" "$DBX_ESTADO" 'upload de pasta, opcao invalida'
  DBX_T_AMBIENTE=(DBX_BLOCO=abc)
  _rodar "$base" upload "$base/local/pasta" /pasta
  assert_igual "$USO" "$DBX_ESTADO" 'upload de pasta, variavel invalida'
  assert_contem 'DBX_BLOCO' "$DBX_ERRO" 'nomeia a variavel'
  DBX_T_AMBIENTE=()
  _rodar "$base" download --batch 1000001 / "$base/local/dest"
  assert_igual "$USO" "$DBX_ESTADO" 'download da raiz (pasta), opcao invalida'
  DBX_T_AMBIENTE=(DBX_BLOCO=abc)
  _rodar "$base" download / "$base/local/dest"
  assert_igual "$USO" "$DBX_ESTADO" 'download da raiz (pasta), variavel invalida'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
}

teste_blc_upload_de_arquivo_unico_ignora_a_opcao_e_a_variavel_invalida() {
  local base
  base=$(_cenario)
  DBX_T_AMBIENTE=(DBX_BLOCO=abc)
  _rodar "$base" upload "$base/local/arquivo.txt" /arquivo.txt
  assert_nao_contem 'DBX_BLOCO' "$DBX_ERRO" 'variavel invalida so e lida onde ha pasta'
  DBX_T_AMBIENTE=()
  _rodar "$base" upload --bloco 5 "$base/local/arquivo.txt" /arquivo.txt
  assert_nao_contem '--bloco' "$DBX_ERRO" 'a opcao valida e aceita e ignorada'
}

teste_blc_outro_comando_recusa_a_opcao_e_ignora_a_variavel() {
  local base
  base=$(_cenario)
  _rodar "$base" list --bloco 5 /
  assert_igual "$USO" "$DBX_ESTADO" 'list recusa --bloco'
  DBX_T_AMBIENTE=(DBX_BLOCO=abc)
  _rodar "$base" list /
  assert_nao_contem 'DBX_BLOCO' "$DBX_ERRO" 'variavel ignorada fora de sync/upload/download'
}

teste_blc_diagnostico_mostra_o_valor_efetivo_e_a_origem_da_variavel() {
  local base saida
  base=$(_cenario)
  DBX_T_AMBIENTE=(DBX_BLOCO=7)
  _rodar "$base" diagnostico
  IFS= read -r -d '' saida <"$base/out"
  assert_contem 'bloco' "$saida" 'a linha bloco aparece com a variavel definida'
  assert_contem '7 (origem: ambiente, DBX_BLOCO)' "$saida" 'valor e origem'
  DBX_T_AMBIENTE=(DBX_BLOCO=abc)
  _rodar "$base" diagnostico
  IFS= read -r -d '' saida <"$base/out"
  assert_contem 'DBX_BLOCO' "$saida" 'variavel invalida e aviso nomeando-a'
  DBX_T_AMBIENTE=()
  _rodar "$base" diagnostico
  IFS= read -r -d '' saida <"$base/out"
  assert_nao_contem 'DBX_BLOCO' "$saida" 'sem a variavel a saida e a de sempre'
}

harness_executar "$@"
