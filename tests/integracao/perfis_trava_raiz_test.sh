#!/usr/bin/env bash
# Trava por raiz local canonica no `sync --receber`, independente de perfil
# (F-18, fase 8; RF-132, DIV-250; TC-PFT-01..10, TC-PFE-06..09). Pelo executavel
# real, com um processo que DETEM a trava de raiz enquanto `dbx` roda.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly CONFLITO=7
DBX_ESTADO=0
DBX_SAIDA=''
DBX_ERRO=''

_amb() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/pft.XXXXXX")
  mkdir -p "$base/bin" "$base/config/dbx/perfis" "$base/estado" "$base/dados" "$base/tmp"
  chmod 700 "$base/config" "$base/config/dbx" "$base/config/dbx/perfis"
  printf '{"versao":1,"app_key":"AK-a","app_secret":"s","refresh_token":"rt-a","raiz_remota":"/"}' >"$base/config/dbx/perfis/a.json"
  printf '{"versao":1,"app_key":"AK-b","app_secret":"s","refresh_token":"rt-b","raiz_remota":"/"}' >"$base/config/dbx/perfis/b.json"
  chmod 600 "$base/config/dbx/perfis/a.json" "$base/config/dbx/perfis/b.json"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    printf 'printf "%%s\\n" "$*" >>"$base/argv"\n'
    printf 'cat >/dev/null\n'
    printf 'saida=""; anterior=""; url=""; escrever=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'corpo=%s\n' "'{}'"
    printf 'if [[ $url == *oauth2/token* ]]; then corpo=%s\n' "'{\"access_token\":\"sl.t\",\"token_type\":\"bearer\",\"expires_in\":14400}'"
    printf 'elif [[ $url == *get_current_account* ]]; then corpo=%s\n' "'{\"account_id\":\"dbid:CONTA\"}'"
    printf 'elif [[ $url == *list_folder* ]]; then corpo=%s\n' "'{\"entries\":[],\"cursor\":\"C1\",\"has_more\":false}'"
    printf 'fi\n'
    printf '[[ -n $escrever ]] && printf "200"\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  rm -f "$base/argv"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    timeout 60 bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _segurar <base> <raiz> — detem a trava de raiz ate existir "$base/solta".
_segurar() {
  local base=$1
  XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" BASE="$base" RAIZ="$DBX_HARNESS_RAIZ" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    dbx_state_trava_raiz_adquirir "$1" 0 || exit 9
    : >"$BASE/segurando"
    while [[ ! -e $BASE/solta ]]; do sleep 0.1; done
  ' _ "$2" </dev/null >/dev/null 2>&1 &
  SEGURANDO=$!
  local i
  for ((i = 0; i < 100; i++)); do
    [[ -e $base/segurando ]] && return 0
    sleep 0.1
  done
  _harness_falhar 'o processo nao adquiriu a trava de raiz'
}

_soltar() {
  : >"$1/solta"
  wait "$SEGURANDO" 2>/dev/null
}

_retrato() { # <diretorio> — nomes e somas
  local f
  for f in "$1" "$1"/* "$1"/.[!.]*; do
    [[ -e $f || -L $f ]] || continue
    printf '%s %s\n' "$f" "$(cksum <"$f" 2>/dev/null)"
  done
}

teste_pft01_outro_perfil_sobre_a_mesma_raiz_sai_7_sem_escrever_e_sem_perfil_na_mensagem() {
  local base antes
  base=$(_amb)
  _segurar "$base" "$base/dados"
  antes=$(_retrato "$base/dados")
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/dados"
  _soltar "$base"
  assert_igual $CONFLITO "$DBX_ESTADO" "conflito: $DBX_ERRO"
  assert_igual "$antes" "$(_retrato "$base/dados")" 'nada escrito na raiz'
  assert_contem 'pid' "$DBX_ERRO" 'o detentor'
  assert_nao_contem 'perfil' "$DBX_ERRO" 'a mensagem nunca cita perfil'
  assert_nao_contem 'cred-' "$DBX_ERRO" 'nem identidade'
}

teste_pft02_mesma_pasta_por_ligacao_simbolica_e_por_ponto_ponto() {
  local base
  base=$(_amb)
  ln -s "$base/dados" "$base/atalho"
  mkdir -p "$base/dados/sub"
  _segurar "$base" "$base/dados"
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/atalho"
  assert_igual $CONFLITO "$DBX_ESTADO" 'ligacao simbolica'
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/dados/sub/../"
  assert_igual $CONFLITO "$DBX_ESTADO" 'com .. e barra final'
  _soltar "$base"
}

teste_pft03_esperar_conclui_quando_a_primeira_termina() {
  local base
  base=$(_amb)
  _segurar "$base" "$base/dados"
  ( sleep 2; : >"$base/solta" ) &
  _rodar "$base" --perfil b sync --receber --esperar 8 --origem / --destino "$base/dados"
  wait "$SEGURANDO" 2>/dev/null
  assert_igual 0 "$DBX_ESTADO" "esperou e concluiu: $DBX_ERRO"
}

teste_pft04_enviar_e_verificar_nao_sao_bloqueados_pela_trava_de_raiz() {
  local base
  base=$(_amb)
  _segurar "$base" "$base/dados"
  _rodar "$base" --perfil b sync --enviar --origem "$base/dados" --destino /
  assert_diferente $CONFLITO "$DBX_ESTADO" "--enviar nao usa a trava de raiz: $DBX_ERRO"
  _rodar "$base" --perfil b verificar --origem "$base/dados" --destino /
  assert_diferente $CONFLITO "$DBX_ESTADO" "verificar nao usa a trava de raiz: $DBX_ERRO"
  _soltar "$base"
}

teste_pft05_download_de_pasta_usa_a_trava_de_raiz() {
  local base
  base=$(_amb)
  _segurar "$base" "$base/dados"
  _rodar "$base" --perfil b download / "$base/dados"
  _soltar "$base"
  assert_igual $CONFLITO "$DBX_ESTADO" "download de pasta: $DBX_ERRO"
}

teste_pft09_unlink_recusa_com_a_trava_viva_e_diagnostico_a_lista() {
  local base
  base=$(_amb)
  _segurar "$base" "$base/dados"
  _rodar "$base" --json --perfil a diagnostico
  assert_contem 'trava=ok: viva' "$DBX_SAIDA" 'o diagnostico lista a trava de raiz'
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual $CONFLITO "$DBX_ESTADO" 'unlink recusa'
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'nada removido'
  _soltar "$base"
  assert_arquivo_ausente "$base/estado/dbx/trava-NAO" 'controle'
}

teste_pft10_dry_run_adquire_as_duas() {
  local base
  base=$(_amb)
  _segurar "$base" "$base/dados"
  _rodar "$base" --dry-run --perfil b sync --receber --origem / --destino "$base/dados"
  _soltar "$base"
  assert_igual $CONFLITO "$DBX_ESTADO" "dry-run tambem trava: $DBX_ERRO"
}

teste_pft_raiz_inexistente_em_dry_run_nao_e_criada_nem_travada() {
  local base
  base=$(_amb)
  _rodar "$base" --dry-run --perfil b sync --receber --origem / --destino "$base/nova"
  assert_igual 0 "$DBX_ESTADO" "dry-run: $DBX_ERRO"
  [[ ! -e $base/nova ]] || _harness_falhar 'dry-run criou a raiz'
}

teste_pft_raiz_livre_adquire_e_libera() {
  local base
  base=$(_amb)
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/dados"
  assert_igual 0 "$DBX_ESTADO" "livre: $DBX_ERRO"
  local sobra=0 t
  for t in "$base"/estado/dbx/trava-*; do [[ -e $t ]] && sobra=$((sobra + 1)); done
  assert_igual 0 "$sobra" 'nenhuma trava sobra'
}

teste_pfe06_cursor_de_outra_identidade_nao_e_usado_nem_alterado() {
  local base antes
  base=$(_amb)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  # Registro de OUTRA identidade para o mesmo par de raizes: formato valido de
  # cabecalho; nao e o registro do perfil `b`, que tem outra chave.
  printf '%s\0' dbx-cursor 1 cred-0123456789abcdef0123456789abcdef dbid:CONTA ass '' "$base/dados" CUR 1700000000 0 1700000000 0 >"$base/estado/dbx/cursor-outra"
  chmod 600 "$base/estado/dbx/cursor-outra"
  antes=$(_retrato "$base/estado/dbx" | grep cursor-outra)
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/dados"
  assert_igual 0 "$DBX_ESTADO" "sync: $DBX_ERRO"
  assert_contem 'varredura=completa' "$DBX_SAIDA" 'o cursor de a nao e usado: varredura completa'
  assert_igual "$antes" "$(_retrato "$base/estado/dbx" | grep cursor-outra)" 'e nao e alterado'
}

harness_executar "$@"
