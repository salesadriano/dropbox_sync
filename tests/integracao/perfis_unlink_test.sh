#!/usr/bin/env bash
# `unlink` com perfis e estado separado pela identidade (F-18, fase 8):
# RF-124, RF-125; TC-PFU, TC-PFE. Pelo executavel real, com duplo de `curl`.
#
# O estado de teste e montado a mao no formato de `lib/state` (cabecalho v1 de
# `retomada-*` e de `cursor-*`), com a identidade `cred-` calculada pela propria
# biblioteca a partir da credencial de cada perfil.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
DBX_ESTADO=0
DBX_SAIDA=''
DBX_ERRO=''

_amb() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/pfu.XXXXXX")
  mkdir -p "$base/bin" "$base/config" "$base/estado/dbx" "$base/loc"
  chmod 700 "$base/config" "$base/estado/dbx"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    printf 'printf "%%s\\n" "$*" >>"$base/argv"\n'
    printf 'opcoes=$(cat)\n'
    printf 'printf "%%s\\n" "$opcoes" >>"$base/opcoes"\n'
    printf 'saida=""; anterior=""; url=""; escrever=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'corpo=%s\n' "'{}'"
    printf 'if [[ $url == *oauth2/token* ]]; then\n'
    printf '  corpo=%s\n' "'{\"access_token\":\"sl.t\",\"token_type\":\"bearer\",\"expires_in\":14400,\"scope\":\"account_info.read\"}'"
    printf 'elif [[ $url == *get_space_usage* ]]; then corpo=%s\n' "'{\"used\":1,\"allocation\":{\".tag\":\"individual\",\"allocated\":1000}}'"
    printf 'elif [[ $url == *token/revoke* && -f "$base/regravar_no_revoke" ]]; then\n'
    printf '  cp "$base/regravar_conteudo" "$(cat "$base/regravar_no_revoke")"\n'
    printf 'fi\n'
    printf '[[ -n $escrever ]] && printf "200"\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_cred() { # <arquivo> <app_key> <refresh>
  mkdir -p "${1%/*}"
  printf '{"versao":1,"app_key":"%s","app_secret":"seg-%s","refresh_token":"%s","raiz_remota":"/"}' "$2" "$2" "$3" >"$1"
  chmod 600 "$1"
}

_padrao() {
  mkdir -p "$1/config/dbx"
  chmod 700 "$1/config/dbx"
  _cred "$1/config/dbx/credencial.json" AKP rt-padrao
}

_perfil() { # <base> <nome> [refresh] [app_key]
  mkdir -p "$1/config/dbx/perfis"
  chmod 700 "$1/config/dbx" "$1/config/dbx/perfis"
  _cred "$1/config/dbx/perfis/$2.json" "${4:-AK-$2}" "${3:-rt-$2}"
}

_identidade() { # <base> <nome> — cred-<32 hex> do perfil
  env -i PATH="$PATH" HOME="$1" XDG_CONFIG_HOME="$1/config" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/config.sh"
    dbx_config_perfil_selecionar "$2" opcao || exit 1
    dbx_config_carregar || exit 1
    dbx_config_identidade
    printf "%s" "$DBX_CONFIG_IDENTIDADE"
  ' _ "$DBX_HARNESS_RAIZ" "$2"
}

# _cursor <base> <cred> <nome> — cabecalho v1 valido (so ele e lido pelo listador)
_cursor() {
  printf '%s\0' dbx-cursor 1 "$2" dbid:CONTA ass /rem /loc CUR 1700000000 0 1700000000 0 >"$1/estado/dbx/$3"
  chmod 600 "$1/estado/dbx/$3"
}

# _retomada <base> <cred> <nome> [com_part] — download v1; com_part cria o .part real
_retomada() {
  local base=$1 cred=$2 nome=$3 part='.x.dbx-part.ABCDEF' devino='1|2' local_="$1/loc/arq.bin" hash
  printf -v hash '%064d' 7
  if [[ ${4:-} == 'com_part' ]]; then
    part=".${nome}.dbx-part.ABCDEF"
    printf 'parcial' >"$base/loc/$part"
    chmod 600 "$base/loc/$part"
    devino=$(stat -c '%d|%i' "$base/loc/$part")
  fi
  printf '%s\0' dbx-retomada 1 download "$cred" host1 /remoto 0123456789a 10 "$hash" "$part" "$devino" 1700000000 "$local_" >"$base/estado/dbx/$nome"
  chmod 600 "$base/estado/dbx/$nome"
}

_outros_estados() { # <base> — memoria, upload e travas do par, que nunca saem por perfil
  printf 'memoria' >"$1/estado/dbx/memoria-m1"
  printf 'upload' >"$1/estado/dbx/upload-u1"
  printf 'dbx-trava\t1\t12345\toutro:boot:ns\t1700000000\tsync\tfim\n' >"$1/estado/dbx/trava-par1"
  chmod 600 "$1/estado/dbx/memoria-m1" "$1/estado/dbx/upload-u1" "$1/estado/dbx/trava-par1"
}

_retrato() { # <diretorio ou arquivo...> — modo e soma de cada entrada
  local f
  for f in "$@"; do
    [[ -e $f || -L $f ]] || { printf '%s AUSENTE\n' "$f"; continue; }
    printf '%s %s %s\n' "$f" "$(stat -c '%a' "$f")" "$(cksum <"$f" 2>/dev/null)"
  done
}

_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  rm -f "$base/argv" "$base/opcoes"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

readonly CONFLITO=7 CONFIG=3 USO=2

# ---------------------------------------------------------------------------
# TC-PFU-01/02/14, TC-PFE-02..04: so o perfil e a identidade dele
# ---------------------------------------------------------------------------

teste_pfu01_pfe02_pfe04_unlink_de_um_perfil_so_toca_o_que_e_dele() {
  local base ia ib e_b e_comuns padrao_antes b_antes
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  _perfil "$base" b
  ia=$(_identidade "$base" a)
  ib=$(_identidade "$base" b)
  [[ $ia == cred-* && $ib == cred-* && $ia != "$ib" ]] || _harness_falhar 'identidades de teste'
  _cursor "$base" "$ia" cursor-aaa
  _retomada "$base" "$ia" retomada-aaa com_part
  _cursor "$base" "$ib" cursor-bbb
  _retomada "$base" "$ib" retomada-bbb
  printf 'lixo' >"$base/estado/dbx/retomada-lixo"
  _outros_estados "$base"
  padrao_antes=$(_retrato "$base/config/dbx/credencial.json")
  b_antes=$(_retrato "$base/config/dbx/perfis/b.json")
  e_b=$(_retrato "$base/estado/dbx/cursor-bbb" "$base/estado/dbx/retomada-bbb")
  e_comuns=$(_retrato "$base/estado/dbx/memoria-m1" "$base/estado/dbx/upload-u1" "$base/estado/dbx/trava-par1" "$base/estado/dbx/retomada-lixo")

  _rodar "$base" --json unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_arquivo_ausente "$base/config/dbx/perfis/a.json" 'o perfil sai'
  assert_igual "$b_antes" "$(_retrato "$base/config/dbx/perfis/b.json")" 'b byte a byte igual'
  assert_igual "$padrao_antes" "$(_retrato "$base/config/dbx/credencial.json")" 'padrao byte a byte igual'
  assert_igual "$e_b" "$(_retrato "$base/estado/dbx/cursor-bbb" "$base/estado/dbx/retomada-bbb")" 'estado de b intacto'
  assert_igual "$e_comuns" "$(_retrato "$base/estado/dbx/memoria-m1" "$base/estado/dbx/upload-u1" "$base/estado/dbx/trava-par1" "$base/estado/dbx/retomada-lixo")" \
    'memoria, upload, trava do par e registro ilegivel intactos'
  assert_arquivo_ausente "$base/estado/dbx/cursor-aaa" 'cursor de a'
  assert_arquivo_ausente "$base/estado/dbx/retomada-aaa" 'retomada de a'
  assert_arquivo_ausente "$base/loc/.retomada-aaa.dbx-part.ABCDEF" 'o .part de a sai pela barreira'
  assert_contem 'perfil=a' "$DBX_SAIDA" 'campo perfil'
  assert_contem 'base_removida=cursor-aaa' "$DBX_SAIDA" 'so o de a'
  assert_nao_contem 'bbb' "$DBX_SAIDA" 'nada de b na saida'
  assert_nao_contem 'cred-' "$DBX_SAIDA$DBX_ERRO" 'a identidade nunca sai (RF-131)'
  [[ -d $base/config/dbx/perfis ]] || _harness_falhar 'perfis/ some com b dentro'
}

teste_pfu02_revoga_o_token_do_perfil_e_adverte_a_cascata() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  _perfil "$base" b
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_contem 'rt-a' "$(cat "$base/opcoes")" 'a requisicao leva o refresh de a'
  assert_nao_contem 'rt-b' "$(cat "$base/opcoes")" 'nao o de b'
  assert_contem 'token/revoke' "$(cat "$base/argv")" 'revogou'
  assert_contem 'perfil a' "$DBX_ERRO" 'a advertencia nomeia o perfil'
  assert_contem 'cascata' "$DBX_ERRO" 'a advertencia de cascata'
}

teste_pfu03_sem_terminal_sem_confirmar_sai_2_e_nao_remove() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _rodar "$base" unlink --perfil a
  assert_igual $USO "$DBX_ESTADO" 'sem --confirmar'
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'nada removido'
}

teste_pfu04_perfil_inexistente_sai_3_antes_de_tudo() {
  local base antes
  base=$(_amb)
  _padrao "$base"
  _outros_estados "$base"
  antes=$(_retrato "$base/config/dbx/credencial.json" "$base/estado/dbx/memoria-m1")
  _rodar "$base" unlink --perfil x --confirmar
  assert_igual $CONFIG "$DBX_ESTADO" 'inexistente'
  assert_nao_contem 'cascata' "$DBX_ERRO" 'antes da advertencia'
  assert_arquivo_ausente "$base/argv" 'sem rede'
  assert_igual "$antes" "$(_retrato "$base/config/dbx/credencial.json" "$base/estado/dbx/memoria-m1")" 'nada removido'
  assert_contem 'perfil x inexistente' "$DBX_ERRO" 'nomeia o perfil'
}

teste_pfu05_unlink_do_padrao_sem_credencial_segue_saindo_0() {
  local base
  base=$(_amb)
  _rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "regressao: $DBX_ERRO"
  _rodar "$base" unlink --perfil padrao --confirmar
  assert_igual 0 "$DBX_ESTADO" '--perfil padrao equivale a omitir'
}

teste_pfu06_manter_aplicativo_regrava_o_perfil() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _rodar "$base" unlink --perfil a --confirmar --manter-aplicativo
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'o arquivo fica'
  assert_contem '"app_key":"AK-a"' "$(cat "$base/config/dbx/perfis/a.json")" 'chave preservada'
  assert_nao_contem 'rt-a' "$(cat "$base/config/dbx/perfis/a.json")" 'refresh removido'
  assert_igual 600 "$(stat -c %a "$base/config/dbx/perfis/a.json")" 'regravado 0600'
}

teste_pfu07_perfil_ilegivel_remove_o_arquivo_e_nao_toca_o_estado() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  printf 'isto nao e json' >"$base/config/dbx/perfis/a.json"
  chmod 600 "$base/config/dbx/perfis/a.json"
  _cursor "$base" "$(_identidade "$base" b)" cursor-bbb
  _outros_estados "$base"
  antes=$(_retrato "$base/estado/dbx/cursor-bbb" "$base/estado/dbx/memoria-m1")
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'como hoje (nao_concluida)'
  assert_arquivo_ausente "$base/config/dbx/perfis/a.json" 'o arquivo sai'
  assert_igual "$antes" "$(_retrato "$base/estado/dbx/cursor-bbb" "$base/estado/dbx/memoria-m1")" 'estado intocado'
  assert_contem 'nao pode ser calculada' "$DBX_ERRO" 'o aviso diz que o estado nao foi identificado'
}

teste_pfu08_identidade_compartilhada_nao_revoga_e_mantem_o_estado() {
  local base antes ia
  base=$(_amb)
  _perfil "$base" a RT-IGUAL AK-igual
  _perfil "$base" b RT-IGUAL AK-igual
  ia=$(_identidade "$base" a)
  _cursor "$base" "$ia" cursor-compartilhado
  _outros_estados "$base"
  antes=$(_retrato "$base/estado/dbx/cursor-compartilhado" "$base/estado/dbx/memoria-m1" "$base/config/dbx/perfis/b.json")
  _rodar "$base" --json unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_arquivo_ausente "$base/config/dbx/perfis/a.json" 'a sai'
  assert_nao_contem 'token/revoke' "$(cat "$base/argv" 2>/dev/null)" 'nao revogou'
  assert_contem 'revogacao=nao_emitida' "$DBX_SAIDA" 'revogacao'
  assert_contem 'compartilhada_com=b' "$DBX_SAIDA" 'nomeia o outro perfil'
  assert_nao_contem 'base_removida' "$DBX_SAIDA" 'nada removido'
  assert_igual "$antes" "$(_retrato "$base/estado/dbx/cursor-compartilhado" "$base/estado/dbx/memoria-m1" "$base/config/dbx/perfis/b.json")" \
    'estado daquele cred- e b byte a byte iguais'
  assert_contem 'b' "$DBX_ERRO" 'o aviso nomeia b'
  _rodar "$base" --perfil b space
  assert_igual 0 "$DBX_ESTADO" "b segue valido: $DBX_ERRO"
}

teste_pfu08_aviso_de_credencial_compartilhada_sai_no_stderr_com_o_texto() {
  local base
  base=$(_amb)
  _perfil "$base" a RT-IGUAL AK-igual
  _perfil "$base" b RT-IGUAL AK-igual
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_contem 'tem a MESMA credencial (app key e refresh token) de: b.' "$DBX_ERRO" 'aviso nomeia a origem'
  assert_contem 'O refresh token NAO sera revogado' "$DBX_ERRO" 'aviso diz que nao revoga'
}

teste_pfu09_perfil_nao_comparavel_entra_no_aviso_com_a_contagem() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" c
  chmod 644 "$base/config/dbx/perfis/c.json"
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_contem '1 perfil(is) nao puderam ser comparados' "$DBX_ERRO" 'contagem'
}

teste_pfu10_pfu16_trava_viva_de_qualquer_par_recusa_com_7() {
  local base pid host antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _cursor "$base" "$(_identidade "$base" a)" cursor-aaa
  sleep 30 &
  pid=$!
  host=$(env -i PATH="$PATH" bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; . "$1/lib/tmp.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ")
  printf 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\n' "$pid" "$host" >"$base/estado/dbx/trava-viva"
  chmod 600 "$base/estado/dbx/trava-viva"
  antes=$(_retrato "$base/config/dbx/perfis/a.json" "$base/estado/dbx/cursor-aaa")
  _rodar "$base" unlink --perfil a --confirmar
  kill "$pid" 2>/dev/null
  assert_igual $CONFLITO "$DBX_ESTADO" 'trava viva'
  assert_contem 'outro perfil' "$DBX_ERRO" 'pode ser de outro perfil'
  assert_igual "$antes" "$(_retrato "$base/config/dbx/perfis/a.json" "$base/estado/dbx/cursor-aaa")" 'nada removido'
  assert_arquivo_ausente "$base/argv" 'sem revogacao'
}

teste_pfu11_perfis_vazio_e_removido() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  [[ ! -d $base/config/dbx/perfis ]] || _harness_falhar 'perfis/ vazio devia sair'
}

teste_pfu12_dry_run_so_simula() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _cursor "$base" "$(_identidade "$base" a)" cursor-aaa
  antes=$(_retrato "$base/config/dbx/perfis/a.json" "$base/estado/dbx/cursor-aaa")
  _rodar "$base" --dry-run unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "dry-run: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulacao'
  assert_contem 'perfil=a' "$DBX_SAIDA" 'campo perfil'
  assert_igual "$antes" "$(_retrato "$base/config/dbx/perfis/a.json" "$base/estado/dbx/cursor-aaa")" 'disco intacto'
  assert_arquivo_ausente "$base/argv" 'sem rede'
}

# ---------------------------------------------------------------------------
# TC-PFU-13 (DIV-238): regra unica da remocao do estado
# ---------------------------------------------------------------------------

teste_pfu13_sobrando_outra_credencial_a_remocao_e_seletiva_inclusive_no_padrao() {
  local base ib antes
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" b
  ib=$(_identidade "$base" b)
  _cursor "$base" "$ib" cursor-bbb
  _outros_estados "$base"
  antes=$(_retrato "$base/estado/dbx/cursor-bbb" "$base/estado/dbx/memoria-m1" "$base/estado/dbx/upload-u1")
  _rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink do padrao: $DBX_ERRO"
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'o padrao sai'
  assert_igual "$antes" "$(_retrato "$base/estado/dbx/cursor-bbb" "$base/estado/dbx/memoria-m1" "$base/estado/dbx/upload-u1")" \
    'com perfis, o estado de b fica'
  assert_arquivo_existe "$base/config/dbx/perfis/b.json" 'b fica'
}

teste_pfu13_nao_sobrando_nenhuma_a_remocao_e_total_como_hoje() {
  local base
  base=$(_amb)
  _perfil "$base" so
  _cursor "$base" "$(_identidade "$base" so)" cursor-so
  _outros_estados "$base"
  _rodar "$base" unlink --perfil so --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_arquivo_ausente "$base/estado/dbx/cursor-so" 'cursor'
  assert_arquivo_ausente "$base/estado/dbx/memoria-m1" 'a memoria tambem sai: ultima credencial'
  assert_arquivo_ausente "$base/estado/dbx/upload-u1" 'upload'
  assert_arquivo_existe "$base/estado/dbx/trava-par1" 'trava nao viva fica, como hoje'
}

teste_pfr02_unlink_do_padrao_sem_perfis_apaga_o_estado_inteiro() {
  local base
  base=$(_amb)
  _padrao "$base"
  _cursor "$base" "$(_identidade "$base" padrao)" cursor-p
  printf 'x' >"$base/estado/dbx/memoria-m1"
  printf 'x' >"$base/estado/dbx/arquivo-qualquer"
  _rodar "$base" --json unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  assert_arquivo_ausente "$base/estado/dbx" 'o diretorio de estado some inteiro (RF-51)'
  assert_nao_contem 'perfil=' "$DBX_SAIDA" 'sem selecao nao ha campo perfil'
}

teste_pfu13_ilegivel_sendo_a_ultima_credencial_a_remocao_e_total() {
  local base
  base=$(_amb)
  _padrao "$base"
  printf 'lixo' >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  printf 'x' >"$base/estado/dbx/memoria-m1"
  _rodar "$base" unlink --confirmar
  assert_arquivo_ausente "$base/estado/dbx" 'DIV-253: como hoje'
}

# ---------------------------------------------------------------------------
# TC-PFU-15 (C8): corrida config x unlink
# ---------------------------------------------------------------------------

teste_pfu15_identidade_que_muda_depois_da_revogacao_nao_apaga_e_sai_7() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  printf '%s' "$base/config/dbx/perfis/a.json" >"$base/regravar_no_revoke"
  printf '{"versao":1,"app_key":"AK-a","app_secret":"novo","refresh_token":"rt-REGRAVADO","raiz_remota":"/"}' >"$base/regravar_conteudo"
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual $CONFLITO "$DBX_ESTADO" 'conflito'
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'nao apagou'
  assert_contem 'rt-REGRAVADO' "$(cat "$base/config/dbx/perfis/a.json")" 'o conteudo novo fica'
  assert_igual 1 "$(_harness_contar 'token/revoke' "$base/argv")" 'nao revogou de novo'
}

# ---------------------------------------------------------------------------
# TC-PFE: leitores expoem a identidade; identidades distintas nao se misturam
# ---------------------------------------------------------------------------

teste_pfe01_leitores_expoem_cred_lendo_so_o_cabecalho() {
  local base ia
  base=$(_amb)
  _perfil "$base" a
  ia=$(_identidade "$base" a)
  [[ $ia == cred-* ]] || _harness_falhar 'identidade de teste'
  _cursor "$base" "$ia" cursor-aaa
  _retomada "$base" "$ia" retomada-aaa
  printf 'lixo' >"$base/estado/dbx/retomada-lixo"
  # Cursor com corpo enorme depois do cabecalho: o leitor nao o le.
  head -c 3000000 /dev/zero >>"$base/estado/dbx/cursor-aaa"
  local resultado
  resultado=$(env -i PATH="$PATH" HOME="$base" XDG_STATE_HOME="$base/estado" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/hash.sh"; . "$1/lib/tmp.sh"; . "$1/lib/json.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"
    dbx_state_cursor_listar
    printf "cursor:%s\n" "${DBX_STATE_CURSORES_CRED[*]}"
    dbx_state_retomada_listar
    for i in "${!DBX_STATE_RETOMADAS_ARQUIVO[@]}"; do printf "retomada:%s:%s\n" "${DBX_STATE_RETOMADAS_ARQUIVO[i]##*/}" "${DBX_STATE_RETOMADAS_CRED[i]}"; done
  ' _ "$DBX_HARNESS_RAIZ")
  assert_contem "cursor:$ia" "$resultado" 'cursor expoe o cred-'
  assert_contem "retomada:retomada-aaa:$ia" "$resultado" 'retomada expoe o cred-'
  assert_contem 'retomada:retomada-lixo:' "$resultado" 'ilegivel sem cred-'
  assert_nao_contem "retomada:retomada-lixo:cred-" "$resultado" 'ilegivel nao e atribuivel'
}

harness_executar "$@"
