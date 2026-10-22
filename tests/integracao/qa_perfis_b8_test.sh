#!/usr/bin/env bash
# Suite independente do QA, fase 8 do backlog: perfis nomeados de credencial
# (F-18; RF-120..RF-132; DIV-236..DIV-255). Pelo executavel real `bin/dbx`, com
# duplo de `curl` proprio (sem rede). Focos adversarios:
#   - ataque pelo NOME do perfil (`..`, `/`, maiusculas, 33 caracteres, unicode,
#     inicio por `-`, `padrao` explicito, `perfis/padrao.json` plantado);
#   - symlink no lugar de `perfis/<nome>.json` e de `perfis/`; permissoes frouxas;
#   - `DBX_PERFIL` com segredo ou vazio; opcao repetida e ordem (DIV-241);
#   - perfil inexistente sem rede e sem recuo ao padrao;
#   - `unlink --perfil` com identidade compartilhada, credencial ilegivel, ultimo
#     perfil, trava viva (7) e trava por raiz entre perfis (7, `--esperar`);
#   - `dbx perfis` sem segredo na saida; CNF-03 (`carregar <arquivo> <nome>`).
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao.
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
  base=$(mktemp -d "$DBX_TESTES_TMP/qpf.XXXXXX")
  mkdir -p "$base/bin" "$base/config" "$base/estado/dbx" "$base/loc" "$base/tmp"
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
    printf 'elif [[ $url == *list_folder* ]]; then corpo=%s\n' "'{\"entries\":[],\"cursor\":\"C1\",\"has_more\":false}'"
    printf 'elif [[ $url == *get_current_account* ]]; then corpo=%s\n' "'{\"account_id\":\"dbid:CONTA\"}'"
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
  local base=$1 extra=()
  read -ra extra <<<"${DBX_ENV_EXTRA:-}"
  shift
  DBX_SAIDA='' DBX_ERRO=''
  rm -f "$base/argv" "$base/opcoes"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" "${extra[@]}" \
    timeout 60 bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

readonly CONFLITO=7 CONFIG=3 USO=2

_sem_rede() { # <base> — nenhuma chamada de rede ocorreu
  [[ ! -s $1/argv ]] || _harness_falhar "houve chamada de rede: $(cat "$1/argv")"
}

# ---------------------------------------------------------------------------
# Ataque pelo nome
# ---------------------------------------------------------------------------

teste_qpf01_nomes_hostis_sao_recusados_com_2_sem_rede_e_sem_tocar_o_disco() {
  local base n antes n33
  printf -v n33 '%.0sa' {1..33}
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  printf 'FORA' >"$base/config/dbx/fora.json"
  antes=$(_retrato "$base/config" "$base/config/dbx" "$base/config/dbx/perfis" "$base/estado/dbx")
  for n in '..' '../fora' 'a/b' '/etc/passwd' 'A' 'Maiuscula' '-x' '_x' 'a.b' 'a b' 'ação' 'é' ' ' $'a\nb' "$n33" '.json' 'a.json'; do
    for cmd in space unlink config perfis; do
      _rodar "$base" "$cmd" --perfil "$n" --confirmar
      [[ $DBX_ESTADO == "$USO" ]] || _harness_falhar "[$n] $cmd: saiu $DBX_ESTADO (esperado 2): $DBX_ERRO"
    done
    _rodar "$base" --perfil "$n" space
    [[ $DBX_ESTADO == "$USO" ]] || _harness_falhar "[$n] global: saiu $DBX_ESTADO"
  done
  _sem_rede "$base"
  assert_igual "$antes" "$(_retrato "$base/config" "$base/config/dbx" "$base/config/dbx/perfis" "$base/estado/dbx")" 'disco intacto'
  assert_arquivo_existe "$base/config/dbx/fora.json" 'arquivo fora do perfis/ intacto'
}

teste_qpf02_nome_de_32_caracteres_vale_e_de_33_nao() {
  local base n32 n33
  base=$(_amb)
  printf -v n32 '%.0sa' {1..32}
  n33=${n32}a
  _perfil "$base" "$n32"
  _rodar "$base" --perfil "$n32" space
  assert_igual 0 "$DBX_ESTADO" "32: $DBX_ERRO"
  _rodar "$base" --perfil "$n33" space
  assert_igual $USO "$DBX_ESTADO" '33'
}

teste_qpf03_digito_inicial_e_hifen_interno_validos() {
  local base
  base=$(_amb)
  _perfil "$base" 9-a_b
  _rodar "$base" --perfil 9-a_b space
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
}

teste_qpf04_padrao_explicito_usa_credencial_json_e_ignora_perfis_padrao_json() {
  local base
  base=$(_amb)
  _padrao "$base" rt-padrao
  _perfil "$base" padrao rt-PLANTADO
  _rodar "$base" --perfil padrao space
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'rt-padrao' "$(cat "$base/opcoes")" 'credencial.json'
  assert_nao_contem 'rt-PLANTADO' "$(cat "$base/opcoes")" 'perfis/padrao.json e reservado'
  _rodar "$base" --json perfis
  assert_igual 0 "$DBX_ESTADO" "perfis: $DBX_ERRO"
  assert_nao_contem 'rt-PLANTADO' "$DBX_SAIDA$DBX_ERRO" 'sem segredo'
}

teste_qpf05_unlink_padrao_com_padrao_json_plantado_nao_apaga_o_plantado() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" b
  _perfil "$base" padrao rt-PLANTADO
  _rodar "$base" unlink --perfil padrao --confirmar
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'o padrao sai'
  assert_arquivo_existe "$base/config/dbx/perfis/padrao.json" 'o plantado nao e tratado como padrao'
  assert_arquivo_existe "$base/config/dbx/perfis/b.json" 'b fica'
}

# ---------------------------------------------------------------------------
# Symlink e permissoes
# ---------------------------------------------------------------------------

teste_qpf06_symlink_no_lugar_do_arquivo_do_perfil_e_recusado_e_nao_lido() {
  local base
  base=$(_amb)
  _perfil "$base" b
  _cred "$base/alvo.json" AKX rt-ALVO
  ln -s "$base/alvo.json" "$base/config/dbx/perfis/a.json"
  _rodar "$base" --perfil a space
  [[ $DBX_ESTADO != 0 ]] || _harness_falhar 'aceitou symlink'
  assert_nao_contem 'rt-ALVO' "$(cat "$base/opcoes" 2>/dev/null)" 'nao leu o alvo'
  _sem_rede "$base"
  _rodar "$base" unlink --perfil a --confirmar
  assert_arquivo_existe "$base/alvo.json" 'o alvo do link nunca e apagado'
  _sem_rede "$base"
}

teste_qpf07_symlink_no_lugar_do_diretorio_perfis_e_recusado() {
  local base
  base=$(_amb)
  mkdir -p "$base/real" "$base/config/dbx"
  chmod 700 "$base/real" "$base/config/dbx"
  _cred "$base/real/a.json" AK-a rt-ALVO
  ln -s "$base/real" "$base/config/dbx/perfis"
  _rodar "$base" --perfil a space
  [[ $DBX_ESTADO != 0 ]] || _harness_falhar 'aceitou perfis/ simbolico'
  assert_nao_contem 'rt-ALVO' "$(cat "$base/opcoes" 2>/dev/null)" 'nao leu'
  _rodar "$base" unlink --perfil a --confirmar
  assert_arquivo_existe "$base/real/a.json" 'nada apagado atraves do link'
  _rodar "$base" --json perfis
  assert_nao_contem 'AK-a' "$DBX_SAIDA" 'perfis nao lista atraves do link'
  _sem_rede "$base"
}

teste_qpf08_permissoes_frouxas_no_arquivo_no_perfis_e_no_dbx_sao_recusadas() {
  local base
  base=$(_amb)
  _perfil "$base" a
  chmod 644 "$base/config/dbx/perfis/a.json"
  _rodar "$base" --perfil a space
  assert_igual $CONFIG "$DBX_ESTADO" "arquivo 644: $DBX_ERRO"
  chmod 600 "$base/config/dbx/perfis/a.json"
  chmod 755 "$base/config/dbx/perfis"
  _rodar "$base" --perfil a space
  assert_igual $CONFIG "$DBX_ESTADO" "perfis/ 755: $DBX_ERRO"
  chmod 700 "$base/config/dbx/perfis"
  chmod 777 "$base/config/dbx"
  _rodar "$base" --perfil a space
  assert_igual $CONFIG "$DBX_ESTADO" "dbx/ 777: $DBX_ERRO"
  chmod 700 "$base/config/dbx"
  _sem_rede "$base"
  _rodar "$base" --perfil a space
  assert_igual 0 "$DBX_ESTADO" "restaurado: $DBX_ERRO"
}

# ---------------------------------------------------------------------------
# DBX_PERFIL, opcao repetida, ordem, inexistente
# ---------------------------------------------------------------------------

teste_qpf09_dbx_perfil_com_segredo_e_recusado_sem_ecoar_o_valor() {
  local base v longo
  printf -v longo '%.0sx' {1..40}
  base=$(_amb)
  _padrao "$base"
  for v in 'sl.SEGREDOTOKEN123' 'Segredo/..' "$longo"; do
    DBX_ENV_EXTRA="DBX_PERFIL=$v" _rodar "$base" space
    assert_igual $USO "$DBX_ESTADO" "[$v]"
    assert_nao_contem "$v" "$DBX_SAIDA$DBX_ERRO" 'valor do ambiente nunca ecoado'
    DBX_ENV_EXTRA="DBX_PERFIL=$v" _rodar "$base" --json perfis
    assert_nao_contem "$v" "$DBX_SAIDA$DBX_ERRO" 'perfis tampouco'
  done
  _sem_rede "$base"
}

teste_qpf10_dbx_perfil_vazio_vale_como_nao_definido_e_a_opcao_vence_ambiente_invalido() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  DBX_ENV_EXTRA='DBX_PERFIL=' _rodar "$base" space
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'rt-padrao' "$(cat "$base/opcoes")" 'padrao'
  DBX_ENV_EXTRA='DBX_PERFIL=Inv@lido' _rodar "$base" --perfil a space
  assert_igual 0 "$DBX_ESTADO" "opcao valida vence ambiente invalido: $DBX_ERRO"
  assert_contem 'rt-a' "$(cat "$base/opcoes")" 'perfil a'
}

teste_qpf11_opcao_repetida_e_recusada_em_qualquer_posicao_inclusive_alias() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _rodar "$base" --perfil a --perfil b space
  assert_igual $USO "$DBX_ESTADO" 'global repetida'
  _rodar "$base" --perfil a --profile a space
  assert_igual $USO "$DBX_ESTADO" 'alias repetido, mesmo valor'
  _rodar "$base" --perfil a unlink --perfil b --confirmar
  assert_igual $USO "$DBX_ESTADO" 'global + depois do subcomando'
  _rodar "$base" --perfil a config --perfil a
  assert_igual $USO "$DBX_ESTADO" 'config: global + depois'
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'a intacto'
  assert_arquivo_existe "$base/config/dbx/perfis/b.json" 'b intacto'
  _sem_rede "$base"
}

teste_qpf12_perfil_sem_valor_e_recusado() {
  local base
  base=$(_amb)
  _rodar "$base" --perfil
  assert_igual $USO "$DBX_ESTADO" 'sem valor no fim'
  _rodar "$base" --perfil ''
  assert_igual $USO "$DBX_ESTADO" 'valor vazio'
  _rodar "$base" unlink --perfil
  assert_igual $USO "$DBX_ESTADO" 'unlink sem valor'
}

teste_qpf13_perfil_inexistente_sai_3_sem_rede_e_sem_recuar_ao_padrao() {
  local base cmd
  base=$(_amb)
  _padrao "$base"
  for cmd in space "unlink --confirmar" "sync --enviar --origem $base/loc --destino /"; do
    # shellcheck disable=SC2086
    _rodar "$base" --perfil fantasma $cmd
    assert_igual $CONFIG "$DBX_ESTADO" "$cmd: $DBX_ERRO"
    assert_contem 'fantasma' "$DBX_ERRO" 'nomeia o perfil'
    _sem_rede "$base"
  done
  DBX_ENV_EXTRA='DBX_PERFIL=fantasma' _rodar "$base" space
  assert_igual $CONFIG "$DBX_ESTADO" 'pelo ambiente'
  _sem_rede "$base"
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'o padrao nao foi tocado pelo unlink do fantasma'
}

# ---------------------------------------------------------------------------
# unlink
# ---------------------------------------------------------------------------

teste_qpf14_identidade_compartilhada_com_o_padrao_nao_revoga_nem_toca_o_estado() {
  local base ia antes
  base=$(_amb)
  _cred "$base/config/dbx/credencial.json" AK-i RT-I
  chmod 700 "$base/config/dbx"
  _perfil "$base" a RT-I AK-i
  ia=$(_identidade "$base" a)
  _cursor "$base" "$ia" cursor-comum
  _outros_estados "$base"
  antes=$(_retrato "$base/estado/dbx/cursor-comum" "$base/estado/dbx/memoria-m1" "$base/config/dbx/credencial.json")
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_arquivo_ausente "$base/config/dbx/perfis/a.json" 'a sai'
  assert_nao_contem 'token/revoke' "$(cat "$base/argv" 2>/dev/null)" 'sem revogacao'
  assert_igual "$antes" "$(_retrato "$base/estado/dbx/cursor-comum" "$base/estado/dbx/memoria-m1" "$base/config/dbx/credencial.json")" 'estado do padrao intacto'
}

teste_qpf15_unlink_do_padrao_com_identidade_igual_a_de_perfil_nao_revoga() {
  local base
  base=$(_amb)
  _cred "$base/config/dbx/credencial.json" AK-i RT-I
  chmod 700 "$base/config/dbx"
  _perfil "$base" a RT-I AK-i
  _rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_nao_contem 'token/revoke' "$(cat "$base/argv" 2>/dev/null)" 'sem revogacao'
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'a fica'
}

teste_qpf16_credencial_ilegivel_nao_remove_estado_algum() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _cursor "$base" "$(_identidade "$base" a)" cursor-aaa
  _cursor "$base" "$(_identidade "$base" b)" cursor-bbb
  _outros_estados "$base"
  printf '{quebrado' >"$base/config/dbx/perfis/a.json"
  antes=$(_retrato "$base/estado/dbx")
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 14 "$DBX_ESTADO" "nao_concluida: $DBX_ERRO"
  assert_contem 'nenhum estado foi removido' "$DBX_ERRO" 'aviso explicito'
  assert_contem 'sem que a revogacao fosse emitida' "$DBX_ERRO" 'erro honesto sobre o token'
  assert_arquivo_ausente "$base/config/dbx/perfis/a.json" 'a credencial ilegivel e removida (declarado)'
  assert_igual "$antes" "$(_retrato "$base/estado/dbx")" "estado intacto"
  assert_arquivo_existe "$base/config/dbx/perfis/b.json" 'b fica'
  assert_nao_contem 'token/revoke' "$(cat "$base/argv" 2>/dev/null)" 'sem revogacao'
}

teste_qpf17_credencial_com_modo_000_nao_remove_estado_nem_apaga_outro() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _cursor "$base" "$(_identidade "$base" b)" cursor-bbb
  chmod 000 "$base/config/dbx/perfis/a.json"
  antes=$(_retrato "$base/estado/dbx")
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 14 "$DBX_ESTADO" "nao_concluida: $DBX_ERRO"
  assert_igual "$antes" "$(_retrato "$base/estado/dbx")" "estado intacto"
  assert_arquivo_existe "$base/config/dbx/perfis/b.json" 'b fica'
}

teste_qpf34_ultimo_perfil_ilegivel_remove_o_estado_total_mas_preserva_trava_do_par() {
  local base
  base=$(_amb)
  _perfil "$base" a
  printf '{quebrado' >"$base/config/dbx/perfis/a.json"
  _cursor "$base" cred-00000000000000000000000000000000 cursor-x
  _outros_estados "$base"
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 14 "$DBX_ESTADO" "$DBX_ERRO"
  assert_arquivo_ausente "$base/estado/dbx/cursor-x" 'remocao total (DIV-253)'
  assert_arquivo_ausente "$base/estado/dbx/memoria-m1" 'memoria'
  assert_arquivo_existe "$base/estado/dbx/trava-par1" 'trava nao viva fica'
}

teste_qpf18_ultimo_perfil_remove_todo_o_estado_da_credencial_mas_nao_a_trava_do_par() {
  local base
  base=$(_amb)
  _perfil "$base" so
  _cursor "$base" "$(_identidade "$base" so)" cursor-so
  _retomada "$base" "$(_identidade "$base" so)" retomada-so
  _outros_estados "$base"
  _rodar "$base" unlink --perfil so --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_arquivo_ausente "$base/config/dbx/perfis/so.json" 'perfil'
  assert_arquivo_ausente "$base/estado/dbx/cursor-so" 'cursor'
  assert_arquivo_ausente "$base/estado/dbx/retomada-so" 'retomada'
  assert_arquivo_ausente "$base/estado/dbx/memoria-m1" 'memoria (ultima credencial)'
}

teste_qpf19_estado_de_identidade_alheia_com_nome_parecido_nao_e_removido() {
  local base ia ib
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  ia=$(_identidade "$base" a)
  ib=$(_identidade "$base" b)
  _cursor "$base" "$ia" cursor-aaa
  # arquivo cujo NOME carrega a identidade de a, mas o cabecalho e de b
  _cursor "$base" "$ib" "cursor-$ia"
  _rodar "$base" unlink --perfil a --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_arquivo_ausente "$base/estado/dbx/cursor-aaa" 'o de a sai'
  assert_arquivo_existe "$base/estado/dbx/cursor-$ia" 'comparacao por cabecalho, nunca por grafia do nome'
}

teste_qpf20_estado_simbolico_nao_e_seguido_nem_removido_alem_do_proprio_link() {
  local base ia
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  ia=$(_identidade "$base" a)
  _cursor "$base" "$ia" cursor-real
  mv "$base/estado/dbx/cursor-real" "$base/valioso"
  ln -s "$base/valioso" "$base/estado/dbx/cursor-link"
  _rodar "$base" unlink --perfil a --confirmar
  assert_arquivo_existe "$base/valioso" 'alvo do link intacto'
  [[ -L $base/estado/dbx/cursor-link ]] || _harness_falhar 'o link nao deve ser removido como estado (so arquivo regular)'
}

teste_qpf21_trava_viva_de_outro_par_recusa_com_7_sem_remover_nada() {
  local base pid host antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _cursor "$base" "$(_identidade "$base" a)" cursor-aaa
  sleep 30 &
  pid=$!
  host=$(env -i PATH="$PATH" bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; . "$1/lib/tmp.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ")
  printf 'dbx-trava\t1\t%s\t%s\t1700000000\tsync\tfim\n' "$pid" "$host" >"$base/estado/dbx/trava-outro"
  chmod 600 "$base/estado/dbx/trava-outro"
  antes=$(_retrato "$base/config/dbx/perfis" "$base/estado/dbx")
  _rodar "$base" unlink --perfil a --confirmar
  kill "$pid" 2>/dev/null
  assert_igual $CONFLITO "$DBX_ESTADO" "trava viva: $DBX_ERRO"
  assert_igual "$antes" "$(_retrato "$base/config/dbx/perfis" "$base/estado/dbx")" 'nada removido, nada revogado'
  assert_nao_contem 'token/revoke' "$(cat "$base/argv" 2>/dev/null)" 'sem revogacao'
}

teste_qpf22_simulacao_do_unlink_nao_altera_disco_nem_chama_a_rede() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  _cursor "$base" "$(_identidade "$base" a)" cursor-aaa
  antes=$(_retrato "$base/config/dbx/perfis" "$base/estado/dbx")
  _rodar "$base" --dry-run unlink --perfil a --confirmar
  assert_igual "$antes" "$(_retrato "$base/config/dbx/perfis" "$base/estado/dbx")" 'disco intacto'
  _sem_rede "$base"
}

teste_qpf23_unlink_sem_confirmar_nao_remove() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _cursor "$base" "$(_identidade "$base" a)" cursor-aaa
  antes=$(_retrato "$base/config/dbx/perfis" "$base/estado/dbx")
  _rodar "$base" unlink --perfil a
  assert_igual "$antes" "$(_retrato "$base/config/dbx/perfis" "$base/estado/dbx")" 'sem --confirmar nada muda'
}

# ---------------------------------------------------------------------------
# dbx perfis
# ---------------------------------------------------------------------------

teste_qpf24_perfis_nao_exibe_segredo_em_nenhuma_saida() {
  local base modo s
  base=$(_amb)
  _padrao "$base" RT-PADRAO-SEGREDO
  _perfil "$base" a RT-A-SEGREDO
  _perfil "$base" b RT-B-SEGREDO
  for modo in "" "--json" "--debug" "--verbose"; do
    # shellcheck disable=SC2086
    _rodar "$base" $modo perfis
    for s in RT-PADRAO-SEGREDO RT-A-SEGREDO RT-B-SEGREDO seg-AKP seg-AK-a seg-AK-b cred-; do
      assert_nao_contem "$s" "$DBX_SAIDA$DBX_ERRO" "perfis $modo"
    done
  done
  _sem_rede "$base"
}

teste_qpf25_perfis_ignora_arquivos_anomalos_sem_travar() {
  local base
  base=$(_amb)
  _perfil "$base" a
  : >"$base/config/dbx/perfis/Maiuscula.json"
  : >"$base/config/dbx/perfis/sem-extensao"
  mkdir "$base/config/dbx/perfis/dir.json"
  ln -s /etc/passwd "$base/config/dbx/perfis/lnk.json"
  _rodar "$base" --json perfis
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'perfil=a' "$DBX_SAIDA" 'a listado'
  assert_nao_contem 'Maiuscula' "$DBX_SAIDA" 'maiuscula nao entra como perfil'
  assert_nao_contem 'passwd' "$DBX_SAIDA$DBX_ERRO" 'link nao seguido'
}

# ---------------------------------------------------------------------------
# Trava por raiz entre perfis
# ---------------------------------------------------------------------------

_segurar() { # <base> <raiz>
  local base=$1 i
  XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" BASE="$base" RAIZ="$DBX_HARNESS_RAIZ" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    dbx_state_trava_raiz_adquirir "$1" 0 || exit 9
    : >"$BASE/segurando"
    while [[ ! -e $BASE/solta ]]; do sleep 0.1; done
  ' _ "$2" </dev/null >/dev/null 2>&1 &
  SEGURANDO=$!
  for ((i = 0; i < 100; i++)); do
    [[ -e $base/segurando ]] && return 0
    sleep 0.1
  done
  _harness_falhar 'nao adquiriu a trava de raiz'
}

_soltar() {
  : >"$1/solta"
  wait "$SEGURANDO" 2>/dev/null
}

teste_qpf26_dois_perfis_na_mesma_raiz_local_o_segundo_sai_7_sem_escrever() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  mkdir -p "$base/dados"
  _segurar "$base" "$base/dados"
  antes=$(_retrato "$base/dados")
  _rodar "$base" --perfil a sync --receber --origem / --destino "$base/dados"
  assert_igual $CONFLITO "$DBX_ESTADO" "perfil a: $DBX_ERRO"
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/dados/../dados/"
  assert_igual $CONFLITO "$DBX_ESTADO" "perfil b, caminho nao canonico: $DBX_ERRO"
  _rodar "$base" sync --receber --origem / --destino "$base/dados"
  _soltar "$base"
  assert_igual "$antes" "$(_retrato "$base/dados")" 'nada escrito'
  assert_nao_contem 'cred-' "$DBX_ERRO" 'sem identidade na mensagem'
}

teste_qpf27_esperar_conclui_depois_que_a_trava_de_raiz_e_solta() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  mkdir -p "$base/dados"
  _segurar "$base" "$base/dados"
  ( sleep 2; : >"$base/solta" ) &
  _rodar "$base" --perfil b sync --receber --esperar 10 --origem / --destino "$base/dados"
  wait "$SEGURANDO" 2>/dev/null
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
}

teste_qpf28_esperar_curto_esgota_e_sai_7() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  mkdir -p "$base/dados"
  _segurar "$base" "$base/dados"
  _rodar "$base" --perfil b sync --receber --esperar 1 --origem / --destino "$base/dados"
  _soltar "$base"
  assert_igual $CONFLITO "$DBX_ESTADO" "$DBX_ERRO"
}

teste_qpf29_raizes_diferentes_nao_se_bloqueiam() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _perfil "$base" b
  mkdir -p "$base/dados" "$base/outra"
  _segurar "$base" "$base/dados"
  _rodar "$base" --perfil b sync --receber --origem / --destino "$base/outra"
  _soltar "$base"
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
}

# ---------------------------------------------------------------------------
# CNF-03: carregar <arquivo> <nome> nao revalida o 2o argumento
# ---------------------------------------------------------------------------

_carregar_direto() { # <base> <arquivo> <nome> — exit e motivo
  env -i PATH="$PATH" HOME="$1" XDG_CONFIG_HOME="$1/config" bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/config.sh"
    dbx_config_carregar "$2" "$3"; rc=$?
    printf "rc=%s motivo=%s" "$rc" "${DBX_CONFIG_MOTIVO:-}"
  ' _ "$DBX_HARNESS_RAIZ" "$2" "$3"
}

teste_qpf30_cnf03_carregar_com_nome_padrao_e_arquivo_de_perfis_pula_a_cadeia() {
  local base r
  base=$(_amb)
  _perfil "$base" a
  chmod 755 "$base/config/dbx/perfis"
  r=$(_carregar_direto "$base" "$base/config/dbx/perfis/a.json" a)
  assert_contem 'rc=3' "$r" "com o nome correto, perfis/ 755 e recusado: $r"
  r=$(_carregar_direto "$base" "$base/config/dbx/perfis/a.json" padrao)
  assert_contem 'rc=3' "$r" "CNF-03: rotulo 'padrao' nao pode pular a verificacao de cadeia de perfis/: $r"
}

teste_qpf31_cnf03_carregar_com_nome_invalido_e_aceito_sem_validar() {
  local base r
  base=$(_amb)
  _perfil "$base" a
  r=$(_carregar_direto "$base" "$base/config/dbx/perfis/a.json" '../x')
  # QA-PF-01 (CNF-03) corrigido no ciclo 2: o 2o argumento e revalidado.
  assert_contem 'rc=2 motivo=perfil_invalido' "$r" "nome hostil recusado: $r"
}

teste_qpf32_cnf03_carregar_com_nome_padrao_segue_symlink_de_perfis() {
  local base r
  base=$(_amb)
  mkdir -p "$base/real" "$base/config/dbx"
  chmod 700 "$base/real" "$base/config/dbx"
  _cred "$base/real/a.json" AK-a rt-ALVO
  ln -s "$base/real" "$base/config/dbx/perfis"
  r=$(_carregar_direto "$base" "$base/config/dbx/perfis/a.json" padrao)
  assert_contem 'rc=3' "$r" "CNF-03: leitura atraves de perfis/ simbolico: $r"
}

teste_qpf33_cnf03_rotulo_padrao_nao_confere_o_diretorio_dbx() {
  local base r
  base=$(_amb)
  _perfil "$base" a
  chmod 777 "$base/config/dbx"
  r=$(_carregar_direto "$base" "$base/config/dbx/perfis/a.json" a)
  assert_contem 'rc=3' "$r" "com o nome correto, dbx/ 777 e recusado: $r"
  r=$(_carregar_direto "$base" "$base/config/dbx/perfis/a.json" padrao)
  # Corrigido (ciclo 2): a cadeia e conferida pelo caminho, nao pelo rotulo.
  assert_contem 'rc=3' "$r" "dbx/ 777 recusado mesmo com rotulo padrao: $r"
  chmod 700 "$base/config/dbx"
}

harness_executar "$@"
