#!/usr/bin/env bash
# Perfis nomeados de credencial, pelo executavel real (F-18, fase 8): selecao,
# preflight, `config`, `perfis`, `diagnostico`, segredo e regressao.
# RF-120..RF-123, RF-126..RF-131; TC-PFS, TC-PFN, TC-PFC, TC-PFG, TC-PFL, TC-PFD,
# TC-PFA, TC-PFR. O `unlink` e o estado ficam em `perfis_unlink_test.sh` e a
# trava de raiz em `perfis_trava_raiz_test.sh`.
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

# _amb — area propria com duplo de `curl`; sem credencial alguma.
_amb() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/pf.XXXXXX")
  mkdir -p "$base/bin" "$base/config" "$base/estado"
  chmod 700 "$base/config"
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
    printf '  corpo=%s\n' "'{\"access_token\":\"sl.t\",\"token_type\":\"bearer\",\"expires_in\":14400,\"refresh_token\":\"rt-novo\",\"scope\":\"account_info.read files.metadata.read files.content.read files.content.write\",\"account_id\":\"dbid:CONTA\"}'"
    printf 'elif [[ $url == *get_current_account* ]]; then corpo=%s\n' "'{\"account_id\":\"dbid:CONTA\"}'"
    printf 'elif [[ $url == *get_space_usage* ]]; then corpo=%s\n' "'{\"used\":1,\"allocation\":{\".tag\":\"individual\",\"allocated\":1000}}'"
    printf 'elif [[ $url == *check/user* ]]; then corpo=%s\n' "'{\"result\":\"dbx\"}'"
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

# _cred <arquivo> <app_key> <refresh> [secret]
_cred() {
  mkdir -p "${1%/*}"
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$2" "${4:-seg-$2}" "$3" >"$1"
  chmod 600 "$1"
}

_padrao() { # <base> [refresh]
  mkdir -p "$1/config/dbx"
  chmod 700 "$1/config/dbx"
  _cred "$1/config/dbx/credencial.json" AKP "${2:-rt-padrao}"
}

_perfil() { # <base> <nome> [refresh] [app_key]
  mkdir -p "$1/config/dbx/perfis"
  chmod 700 "$1/config/dbx" "$1/config/dbx/perfis"
  _cred "$1/config/dbx/perfis/$2.json" "${4:-AK-$2}" "${3:-rt-$2}"
}

# _rodar <base> <args...> — stdin de /dev/null, ou do arquivo em $DBX_STDIN.
_rodar() {
  local base=$1 entrada=${DBX_STDIN:-/dev/null} extra=()
  shift
  read -ra extra <<<"${DBX_ENV_EXTRA:-}"
  DBX_SAIDA='' DBX_ERRO=''
  rm -f "$base/argv" "$base/opcoes"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" "${extra[@]}" \
    bash "$DBX_EXEC" "$@" <"$entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_retrato() { # <diretorio> — modo, tamanho e conteudo de cada entrada, para comparar
  local f
  [[ -e $1 ]] || { printf 'AUSENTE'; return 0; }
  for f in "$1" "$1"/* "$1"/.[!.]*; do
    [[ -e $f || -L $f ]] || continue
    printf '%s %s ' "$f" "$(stat -c '%a' "$f")"
    [[ -f $f ]] && printf '%s' "$(cksum <"$f")"
    printf '\n'
  done
}

readonly USO=2 CONFIG=3

# ---------------------------------------------------------------------------
# TC-PFS: selecao e precedencia
# ---------------------------------------------------------------------------

teste_pfs01_opcao_vence_a_variavel() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  _perfil "$base" b
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" --perfil b space
  assert_igual 0 "$DBX_ESTADO" "space: $DBX_ERRO"
  assert_contem 'rt-b' "$(cat "$base/opcoes")" 'a requisicao leva o refresh token de b'
  assert_nao_contem 'rt-a' "$(cat "$base/opcoes")" 'nao o de a'
  assert_nao_contem 'rt-padrao' "$(cat "$base/opcoes")" 'nem o do padrao'
}

teste_pfs02_so_a_variavel_usa_o_perfil_dela() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" space
  assert_igual 0 "$DBX_ESTADO" "space: $DBX_ERRO"
  assert_contem 'rt-a' "$(cat "$base/opcoes")" 'refresh de a'
  assert_nao_contem 'rt-padrao' "$(cat "$base/opcoes")" 'nao o do padrao'
}

teste_pfs03_a_pfs05_sem_selecao_vazio_e_alias() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  _rodar "$base" space
  assert_contem 'rt-padrao' "$(cat "$base/opcoes")" 'sem selecao: padrao'
  DBX_ENV_EXTRA='DBX_PERFIL=' _rodar "$base" space
  assert_igual 0 "$DBX_ESTADO" 'DBX_PERFIL vazio'
  assert_contem 'rt-padrao' "$(cat "$base/opcoes")" 'vazio equivale a nao definida'
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'vazio nao avisa'
  _rodar "$base" --profile a space
  assert_contem 'rt-a' "$(cat "$base/opcoes")" '--profile equivale a --perfil'
}

teste_pfs06_a_pfs08_uso_invalido_da_opcao() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  _rodar "$base" --perfil
  assert_igual $USO "$DBX_ESTADO" '--perfil sem valor'
  _rodar "$base" --perfil a --perfil a space
  assert_igual $USO "$DBX_ESTADO" 'repetida igual'
  _rodar "$base" --perfil a --profile a space
  assert_igual $USO "$DBX_ESTADO" 'repetida com alias'
  _rodar "$base" space --perfil a
  assert_igual $USO "$DBX_ESTADO" 'depois do subcomando em space: opcao desconhecida'
  assert_arquivo_ausente "$base/argv" 'nenhuma requisicao'
  _rodar "$base" --perfil a config --perfil a
  assert_igual $USO "$DBX_ESTADO" 'antes e depois de config'
}

# ---------------------------------------------------------------------------
# TC-PFN: nome invalido nunca toca disco nem rede
# ---------------------------------------------------------------------------

teste_pfn02_a_pfn08_nome_invalido_sai_2_sem_efeito() {
  local base nome antes depois n33
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  antes=$(_retrato "$base/config")
  printf -v n33 '%033d' 1
  for nome in "$n33" '../x' 'a/b' 'A' 'á' 'a b' '-a' '_a' '' $'a\nb'; do
    _rodar "$base" --perfil "$nome" space
    assert_igual $USO "$DBX_ESTADO" "nome [${nome//[^[:print:]]/?}] sai 2"
    assert_arquivo_ausente "$base/argv" 'o curl nao foi chamado'
    depois=$(_retrato "$base/config")
    assert_igual "$antes" "$depois" 'diretorio de configuracao byte a byte igual'
  done
  local n32=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  _rodar "$base" --perfil "$n32" help
  assert_igual 0 "$DBX_ESTADO" '32 caracteres validos (help curto-circuita)'
}

teste_pfn_nome_invalido_em_config_nao_cria_nada() {
  local base
  base=$(_amb)
  _rodar "$base" config --perfil 'Ab'
  assert_igual $USO "$DBX_ESTADO" 'config --perfil invalido'
  [[ ! -e $base/config/dbx ]] || _harness_falhar 'criou diretorio'
  _rodar "$base" unlink --perfil '../x' --confirmar
  assert_igual $USO "$DBX_ESTADO" 'unlink --perfil invalido'
}

teste_pfn09_pfd11_variavel_invalida_sai_2_sem_ecoar_e_sem_aviso() {
  local base
  base=$(_amb)
  _padrao "$base"
  DBX_ENV_EXTRA='DBX_PERFIL=SEGREDO-DO-OPERADOR' _rodar "$base" space
  assert_igual $USO "$DBX_ESTADO" 'invalida e usada'
  assert_segredo_ausente 'SEGREDO-DO-OPERADOR' "$DBX_ERRO$DBX_SAIDA" 'o valor nao e ecoado'
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'sem aviso'
  assert_arquivo_ausente "$base/argv" 'sem rede'
}

teste_pfn10_help_version_e_completar_nao_leem_a_variavel() {
  local base
  base=$(_amb)
  DBX_ENV_EXTRA='DBX_PERFIL=Invalida' _rodar "$base" help
  assert_igual 0 "$DBX_ESTADO" 'help'
  DBX_ENV_EXTRA='DBX_PERFIL=Invalida' _rodar "$base" --version
  assert_igual 0 "$DBX_ESTADO" 'version'
  DBX_ENV_EXTRA='DBX_PERFIL=Invalida' _rodar "$base" completar bash
  assert_igual 0 "$DBX_ESTADO" 'completar'
  _rodar "$base" --perfil Ab completar bash
  assert_igual $USO "$DBX_ESTADO" 'opcao invalida vale para qualquer comando'
  _rodar "$base" --perfil ok help
  assert_igual 0 "$DBX_ESTADO" 'perfil valido e help'
  _rodar "$base" --help --perfil Ab
  assert_igual 0 "$DBX_ESTADO" 'help antes do nome invalido'
}

# ---------------------------------------------------------------------------
# TC-PFC: caminho, ausencia sem recuo, preflight
# ---------------------------------------------------------------------------

teste_pfc03_perfil_ausente_sai_3_sem_rede_e_sem_recuo() {
  local base antes
  base=$(_amb)
  _padrao "$base"
  antes=$(_retrato "$base/config")
  _rodar "$base" --perfil ausente space
  assert_igual $CONFIG "$DBX_ESTADO" 'ausente'
  assert_contem 'ausente' "$DBX_ERRO" 'o motivo'
  assert_contem 'dbx config --perfil ausente' "$DBX_ERRO" 'o remedio nomeia o perfil'
  assert_arquivo_ausente "$base/argv" 'sem rede'
  assert_igual "$antes" "$(_retrato "$base/config")" 'padrao intocado'
}

teste_pfc04_a_pfc09_perfil_inseguro_sai_3() {
  local base d
  base=$(_amb)
  _perfil "$base" x
  d="$base/config/dbx/perfis"
  chmod 644 "$d/x.json"
  _rodar "$base" --perfil x space
  assert_igual $CONFIG "$DBX_ESTADO" 'arquivo 0644'
  chmod 600 "$d/x.json"
  chmod 755 "$d"
  _rodar "$base" --perfil x space
  assert_igual $CONFIG "$DBX_ESTADO" 'perfis/ 0755'
  chmod 700 "$d"
  chmod 755 "$base/config/dbx"
  _rodar "$base" --perfil x space
  assert_igual $CONFIG "$DBX_ESTADO" 'dbx/ 0755'
  chmod 700 "$base/config/dbx"
  _rodar "$base" --perfil x space
  assert_igual 0 "$DBX_ESTADO" "restabelecido: $DBX_ERRO"
  assert_arquivo_ausente "$base/argv.nao" 'controle'
}

teste_pfc07_pfc08_ligacoes_simbolicas_recusadas_sem_ler() {
  local base alvo
  base=$(_amb)
  _padrao "$base"
  alvo="$base/atacante"
  mkdir -p "$alvo"
  chmod 700 "$alvo"
  _cred "$alvo/a.json" ATK rt-atacante
  ln -s "$alvo" "$base/config/dbx/perfis"
  _rodar "$base" --perfil a space
  assert_igual $CONFIG "$DBX_ESTADO" 'perfis/ simbolico'
  assert_arquivo_ausente "$base/argv" 'nada lido, sem rede'
  rm "$base/config/dbx/perfis"
  _perfil "$base" real
  ln -s /nao/existe "$base/config/dbx/perfis/pend.json"
  _rodar "$base" --perfil pend space
  assert_igual $CONFIG "$DBX_ESTADO" 'arquivo simbolico pendente'
}

teste_pfc10_preflight_inspeciona_o_arquivo_do_perfil() {
  local base
  base=$(_amb)
  _padrao "$base"
  chmod 644 "$base/config/dbx/credencial.json"
  _perfil "$base" ok
  _rodar "$base" --perfil ok space
  assert_igual 0 "$DBX_ESTADO" "padrao 0644 nao reprova --perfil ok: $DBX_ERRO"
  _rodar "$base" space
  assert_igual $CONFIG "$DBX_ESTADO" 'o padrao 0644 reprova sem selecao'
  chmod 600 "$base/config/dbx/credencial.json"
  chmod 644 "$base/config/dbx/perfis/ok.json"
  _rodar "$base" --perfil ok space
  assert_igual $CONFIG "$DBX_ESTADO" 'o perfil 0644 reprova'
}

teste_pfc14_so_config_cria_perfis() {
  local base
  base=$(_amb)
  _padrao "$base"
  _rodar "$base" perfis
  _rodar "$base" diagnostico
  _rodar "$base" --perfil x info /
  _rodar "$base" --perfil x unlink --confirmar
  _rodar "$base" unlink --dry-run --confirmar
  [[ ! -e $base/config/dbx/perfis ]] || _harness_falhar 'perfis/ foi criado por comando que nao e config --perfil'
}

# ---------------------------------------------------------------------------
# TC-PFG: config --perfil
# ---------------------------------------------------------------------------

_entrada_config() { # <base> — chave, segredo, codigo
  printf 'AKNOVO\nSEGREDO-NOVO\nCODIGO-1\n' >"$1/stdin"
}

teste_pfg01_cria_perfis_0700_e_arquivo_0600_sem_tocar_o_padrao() {
  local base
  base=$(_amb)
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" config --perfil trabalho
  assert_igual 0 "$DBX_ESTADO" "config: $DBX_ERRO"
  assert_igual 700 "$(stat -c %a "$base/config/dbx/perfis")" 'perfis/'
  assert_igual 600 "$(stat -c %a "$base/config/dbx/perfis/trabalho.json")" 'arquivo'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'o padrao nao existe'
  assert_contem 'perfil=trabalho' "$DBX_SAIDA" 'campo perfil'
  _rodar "$base" --perfil trabalho info /
  assert_igual 0 "$DBX_ESTADO" "o perfil funciona: $DBX_ERRO"
  assert_contem 'rt-novo' "$(cat "$base/opcoes")" 'usa o refresh do perfil'
}

teste_pfg02_pfg03_perfil_existente_exige_substituir_e_nomeia() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" --perfil a config
  assert_igual $CONFIG "$DBX_ESTADO" 'sem --substituir'
  assert_contem 'perfil a' "$DBX_ERRO" 'nomeia o perfil'
  assert_contem 'perfis/a.json' "$DBX_ERRO" 'e o caminho'
  assert_contem 'NAO revoga' "$DBX_ERRO" 'e diz que nao revoga'
  DBX_STDIN="$base/stdin" _rodar "$base" --perfil a config --substituir
  assert_igual 0 "$DBX_ESTADO" "com --substituir: $DBX_ERRO"
  assert_contem 'perfil a foi substituida' "$DBX_ERRO" 'aviso nomeando o perfil'
  assert_contem 'rt-novo' "$(cat "$base/config/dbx/perfis/a.json")" 'arquivo trocado'
}

teste_pfg04_pfg05_destino_inseguro_recusa_antes_de_perguntar() {
  local base antes
  base=$(_amb)
  _perfil "$base" a
  chmod 755 "$base/config/dbx/perfis"
  antes=$(_retrato "$base/config/dbx")
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" config --perfil novo
  assert_igual $CONFIG "$DBX_ESTADO" 'perfis/ 0755'
  assert_nao_contem 'App key' "$DBX_ERRO" 'nenhuma pergunta feita'
  local lido esperado=$'AKNOVO\nSEGREDO-NOVO\nCODIGO-1\n'
  IFS= read -r -d '' lido <"$base/stdin"
  assert_igual "$esperado" "$lido" 'entrada intacta (nenhuma pergunta consumiu)'
  assert_igual "$antes" "$(_retrato "$base/config/dbx")" 'diretorio inalterado'
  assert_contem 'chmod 700' "$DBX_ERRO" 'remedio'
  chmod 700 "$base/config/dbx/perfis"
  ln -s /nao/existe "$base/config/dbx/perfis/novo.json"
  DBX_STDIN="$base/stdin" _rodar "$base" config --perfil novo
  assert_igual $CONFIG "$DBX_ESTADO" 'alvo simbolico pendente'
  assert_nao_contem 'App key' "$DBX_ERRO" 'antes de perguntar'
}

teste_pfg06_perfil_padrao_grava_credencial_json() {
  local base
  base=$(_amb)
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" config --perfil padrao
  assert_igual 0 "$DBX_ESTADO" "config: $DBX_ERRO"
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'grava o padrao'
  [[ ! -e $base/config/dbx/perfis ]] || _harness_falhar 'perfis/ nao deve existir'
  assert_contem 'perfil=padrao' "$DBX_SAIDA" 'campo perfil (selecao explicita)'
}

teste_pfg07_raiz_e_propria_de_cada_perfil() {
  local base
  base=$(_amb)
  _padrao "$base"
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" config --perfil a --raiz /pasta-a
  assert_igual 0 "$DBX_ESTADO" "config: $DBX_ERRO"
  assert_contem '"raiz_remota":"/pasta-a"' "$(cat "$base/config/dbx/perfis/a.json")" 'raiz do perfil'
  assert_contem '"raiz_remota":"/"' "$(cat "$base/config/dbx/credencial.json")" 'padrao intacto'
}

teste_pfg08_dry_run_nao_cria_nada_e_mostra_o_perfil() {
  local base
  base=$(_amb)
  _rodar "$base" --dry-run config --perfil novo
  assert_igual 0 "$DBX_ESTADO" "dry-run: $DBX_ERRO"
  assert_contem 'perfil=novo' "$DBX_SAIDA" 'a simulacao traz o perfil'
  assert_contem 'perfis/novo.json' "$DBX_SAIDA" 'e o caminho'
  [[ ! -e $base/config ]] || [[ -z $(ls -A "$base/config") ]] || _harness_falhar 'dry-run criou algo'
}

teste_pfg09_pfr01_sem_selecao_a_saida_de_config_e_a_de_hoje() {
  local base
  base=$(_amb)
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" config
  assert_igual 0 "$DBX_ESTADO" "config: $DBX_ERRO"
  assert_nao_contem 'perfil' "$DBX_SAIDA" 'sem selecao nao ha campo perfil'
  assert_contem 'credencial=' "$DBX_SAIDA" 'campos de hoje'
}

teste_pfg10_pfg11_debug_mostra_perfil_e_nunca_segredo() {
  local base
  base=$(_amb)
  _entrada_config "$base"
  DBX_STDIN="$base/stdin" _rodar "$base" --debug config --perfil dbg
  assert_igual 0 "$DBX_ESTADO" "config: $DBX_ERRO"
  assert_contem 'Perfil: dbg' "$DBX_ERRO" 'o debug mostra o perfil'
  assert_contem 'perfis/dbg.json' "$DBX_ERRO" 'e o caminho'
  assert_segredo_ausente 'SEGREDO-NOVO' "$DBX_ERRO$DBX_SAIDA" 'segredo fora da saida'
  assert_segredo_ausente 'SEGREDO-NOVO' "$(cat "$base/argv")" 'segredo fora de argv'
}

# ---------------------------------------------------------------------------
# TC-PFL: dbx perfis
# ---------------------------------------------------------------------------

teste_pfl01_pfl04_lista_ordem_total_e_ativo() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" b
  _perfil "$base" a
  _cred "$base/config/dbx/perfis/c.json" AKC ''
  _rodar "$base" perfis
  assert_igual 0 "$DBX_ESTADO" "perfis: $DBX_ERRO"
  assert_contem 'total=4' "$DBX_SAIDA" 'quatro perfis'
  assert_contem 'perfil=c' "$DBX_SAIDA" 'c listado'
  assert_arquivo_ausente "$base/argv" 'sem rede'
  _rodar "$base" --json perfis
  local ordem
  ordem=$(grep -E '^perfil=' <<<"$DBX_SAIDA" | tr '\n' ' ')
  assert_igual 'perfil=padrao perfil=a perfil=b perfil=c ' "$ordem" 'padrao primeiro, depois bytes'
  assert_contem 'credencial=incompleta' "$DBX_SAIDA" 'c sem refresh'
  _rodar "$base" --json --perfil b perfis
  assert_igual 1 "$(grep -c 'ativo=sim' <<<"$DBX_SAIDA")" 'um ativo'
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" --json perfis
  assert_contem 'ativo=sim' "$DBX_SAIDA" 'ativo pela variavel'
  _rodar "$base" --json perfis
  assert_igual 'sim' "$(awk '/^perfil=padrao/{f=1} f&&/^ativo=/{sub("ativo=","");print;exit}' <<<"$DBX_SAIDA")" 'sem selecao o ativo e o padrao'
}

teste_pfl02_pfl03_sem_credencial_total_zero_e_padrao_so_se_existir() {
  local base
  base=$(_amb)
  _rodar "$base" --json perfis
  assert_igual 0 "$DBX_ESTADO" 'sem nada'
  assert_contem 'total=0' "$DBX_SAIDA" 'total 0'
  _perfil "$base" a
  _rodar "$base" --json perfis
  assert_nao_contem 'perfil=padrao' "$DBX_SAIDA" 'padrao so com credencial.json'
}

teste_pfl06_nenhum_segredo_nem_identidade_em_nenhum_modo() {
  local base modo saida
  base=$(_amb)
  _padrao "$base" RT-SENT-PADRAO
  _perfil "$base" a RT-SENT-A AK-SENT-A
  _perfil "$base" b RT-SENT-B AK-SENT-B
  for modo in '' '--json' '--null' '--debug'; do
    # shellcheck disable=SC2086
    _rodar "$base" $modo perfis
    assert_igual 0 "$DBX_ESTADO" "perfis $modo: $DBX_ERRO"
    saida=$DBX_SAIDA$DBX_ERRO
    for s in RT-SENT-PADRAO RT-SENT-A RT-SENT-B AK-SENT-A AK-SENT-B seg-AKP seg-AK-a seg-AK-b cred-; do
      assert_segredo_ausente "$s" "$saida" "perfis $modo vazou $s"
    done
  done
}

teste_pfl07_somente_leitura_sem_criar_diretorio() {
  local base antes
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  antes=$(_retrato "$base/config/dbx")
  _rodar "$base" perfis
  assert_igual 0 "$DBX_ESTADO" "perfis: $DBX_ERRO"
  assert_contem 'total=2' "$DBX_SAIDA" 'listou os dois perfis'
  assert_igual "$antes" "$(_retrato "$base/config/dbx")" 'diretorios byte a byte iguais'
  assert_arquivo_ausente "$base/argv" 'curl nao chamado'
  [[ ! -e $base/estado/dbx ]] || _harness_falhar 'criou estado'
}

teste_pfl08_entradas_anomalas_geram_um_aviso() {
  local base d
  base=$(_amb)
  _perfil "$base" ok
  d="$base/config/dbx/perfis"
  _cred "$d/Foo.json" AK rt
  _cred "$d/padrao.json" AK rt
  mkdir "$d/sub.json"
  printf x >"$d/.credencial.1.XXXX"
  _rodar "$base" --json perfis
  assert_igual 0 "$DBX_ESTADO" 'perfis'
  assert_igual 1 "$(grep -c '^perfil=' <<<"$DBX_SAIDA")" 'so o valido vira registro'
  assert_contem '3 entrada(s) ignorada(s) em perfis/' "$DBX_ERRO" 'aviso de uma linha'
  assert_nao_contem '.credencial' "$DBX_ERRO" 'temporario oculto em silencio'
}

teste_pfl09_pfl10_codigos() {
  local base
  base=$(_amb)
  _perfil "$base" a
  chmod 644 "$base/config/dbx/perfis/a.json"
  _rodar "$base" --json perfis
  assert_igual 0 "$DBX_ESTADO" 'perfil quebrado nao muda o 0'
  assert_contem 'credencial=permissao' "$DBX_SAIDA" 'veredito'
  _rodar "$base" perfis x
  assert_igual $USO "$DBX_ESTADO" 'posicional'
  _rodar "$base" perfis --x
  assert_igual $USO "$DBX_ESTADO" 'opcao desconhecida'
  _rodar "$base" perfis --perfil a
  assert_igual $USO "$DBX_ESTADO" '--perfil depois de perfis'
  _rodar "$base" --perfil Ab perfis
  assert_igual $USO "$DBX_ESTADO" 'nome invalido'
}

teste_pfl11_alias_e_ajuda_equivalem() {
  local base ajuda
  base=$(_amb)
  _rodar "$base" help perfis
  ajuda=$DBX_SAIDA
  assert_contem 'perfis' "$ajuda" 'ajuda'
  _rodar "$base" help profiles
  assert_igual "$ajuda" "$DBX_SAIDA" 'help profiles'
  _rodar "$base" perfis --help
  assert_igual "$ajuda" "$DBX_SAIDA" 'perfis --help'
  _perfil "$base" a
  _rodar "$base" --json profiles
  assert_contem 'perfil=a' "$DBX_SAIDA" 'alias profiles'
}

# ---------------------------------------------------------------------------
# TC-PFD: diagnostico e aviso do ambiente
# ---------------------------------------------------------------------------

teste_pfd01_pfd02_diagnostico_com_selecao_traz_a_linha_perfil() {
  local base
  base=$(_amb)
  _perfil "$base" a
  _rodar "$base" --json --perfil a diagnostico
  assert_contem 'perfil=ok: a (origem: opcao)' "$DBX_SAIDA" 'linha perfil'
  assert_contem 'perfis/a.json' "$DBX_SAIDA" 'credencial aponta o arquivo do perfil'
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" --json diagnostico
  assert_contem '(origem: ambiente)' "$DBX_SAIDA" 'origem ambiente'
  rm -f "$base/config/dbx/perfis/a.json"
  _rodar "$base" --json --perfil a diagnostico
  assert_igual $CONFIG "$DBX_ESTADO" 'perfil ausente: 3'
  assert_contem 'dbx config --perfil a' "$DBX_SAIDA" 'remedio com --perfil'
}

teste_pfd03_pfr_diagnostico_sem_selecao_e_igual_a_base() {
  local base
  base=$(_amb)
  _padrao "$base"
  _rodar "$base" --json diagnostico
  assert_nao_contem 'perfil=' "$DBX_SAIDA" 'sem linha perfil'
  assert_contem 'ok=' "$DBX_SAIDA" 'contagens'
  local sem_selecao=$DBX_SAIDA
  _rodar "$base" --json --perfil padrao diagnostico
  assert_contem 'perfil=ok: padrao (origem: opcao)' "$DBX_SAIDA" 'padrao explicito e selecao explicita (DIV-254)'
  assert_contem 'ok=' "$sem_selecao" 'controle'
}

teste_pfd05_perfis_inseguro_aponta_chmod_700() {
  local base
  base=$(_amb)
  _perfil "$base" a
  chmod 755 "$base/config/dbx/perfis"
  _rodar "$base" --json --perfil a diagnostico
  assert_contem "chmod 700 $base/config/dbx/perfis" "$DBX_SAIDA" 'remedio'
  assert_igual $CONFIG "$DBX_ESTADO" 'falha'
}

teste_pfd08_info_nao_muda_com_selecao() {
  local base sem com
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  _rodar "$base" --json info /
  sem=$DBX_SAIDA
  _rodar "$base" --json --perfil a info /
  com=$DBX_SAIDA
  assert_igual "$sem" "$com" 'info identico (DIV-245)'
}

teste_pfd09_pfd10_aviso_so_quando_o_perfil_vem_do_ambiente() {
  local base
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" --json space
  assert_contem 'aviso: perfil ativo a (DBX_PERFIL)' "$DBX_ERRO" 'aviso em stderr'
  assert_nao_contem 'aviso: perfil' "$DBX_SAIDA" 'stdout intocado'
  assert_igual 0 "$DBX_ESTADO" 'codigo igual'
  _rodar "$base" --perfil a space
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'opcao nao avisa'
  _rodar "$base" space
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'padrao implicito nao avisa'
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" help
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'help'
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" --version
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'version'
  DBX_ENV_EXTRA='DBX_PERFIL=a' _rodar "$base" completar bash
  assert_nao_contem 'aviso: perfil ativo' "$DBX_ERRO" 'completar'
}

# ---------------------------------------------------------------------------
# TC-PFS-09..14: segredo e codigos
# ---------------------------------------------------------------------------

teste_pfs09_a_pfs11_nenhuma_saida_traz_credencial_sentinela() {
  local base cmd modo saida s
  base=$(_amb)
  _padrao "$base" RT-SENT-PADRAO
  _perfil "$base" a RT-SENT-A AK-SENT-A
  _perfil "$base" b RT-SENT-B AK-SENT-B
  for modo in '' '--json' '--null' '--debug'; do
    for cmd in 'space' 'info /' 'diagnostico' 'perfis' '--perfil a space' '--perfil b info /' '--perfil ausente space' 'unlink --perfil a --dry-run --confirmar'; do
      # shellcheck disable=SC2086
      _rodar "$base" $modo $cmd
      case $cmd in perfis | '--perfil a space' | '--perfil b info /') assert_igual 0 "$DBX_ESTADO" "[$modo $cmd] deve concluir: $DBX_ERRO" ;; esac
      saida=$DBX_SAIDA$DBX_ERRO
      for s in RT-SENT-PADRAO RT-SENT-A RT-SENT-B AK-SENT-A AK-SENT-B seg-AKP seg-AK-a seg-AK-b; do
        assert_segredo_ausente "$s" "$saida" "[$modo $cmd] vazou $s"
      done
    done
  done
}

teste_pfs13_perfil_inexistente_ou_invalido_nunca_chama_a_rede() {
  local base
  base=$(_amb)
  _padrao "$base"
  _rodar "$base" --perfil nao-existe space
  assert_igual 3 "$DBX_ESTADO" 'inexistente: 3'
  assert_arquivo_ausente "$base/argv" 'inexistente'
  _rodar "$base" --perfil NAO space
  assert_igual 2 "$DBX_ESTADO" 'invalido: 2'
  assert_arquivo_ausente "$base/argv" 'invalido'
}

teste_pfs14_nenhum_codigo_novo() {
  local base codigo
  base=$(_amb)
  _padrao "$base"
  for codigo in "--perfil Ab space" "--perfil ausente space" "perfis" "--perfil a --perfil a space"; do
    # shellcheck disable=SC2086
    _rodar "$base" $codigo
    [[ $codigo == perfis ]] && assert_igual 0 "$DBX_ESTADO" 'perfis conclui'
    [[ $DBX_ESTADO -ge 0 && $DBX_ESTADO -le 15 ]] || _harness_falhar "codigo fora de 0..15: $DBX_ESTADO"
  done
}

# ---------------------------------------------------------------------------
# TC-PFA: ajuda
# ---------------------------------------------------------------------------

teste_pfa01_a_pfa03_ajuda_lista_perfis_a_opcao_e_a_variavel() {
  local base
  base=$(_amb)
  _rodar "$base" help
  assert_contem 'perfis ' "$DBX_SAIDA" 'comando perfis'
  assert_contem '--perfil --profile' "$DBX_SAIDA" 'opcao global'
  assert_contem 'DBX_PERFIL' "$DBX_SAIDA" 'variavel'
  assert_contem 'nunca segredo' "$DBX_SAIDA" 'so o nome'
  _rodar "$base" help config
  assert_contem '--perfil, --profile' "$DBX_SAIDA" 'help config'
  _rodar "$base" help unlink
  assert_contem '--perfil, --profile' "$DBX_SAIDA" 'help unlink'
}

# ---------------------------------------------------------------------------
# TC-PFR: regressao sem selecao e sem perfis/
# ---------------------------------------------------------------------------

teste_pfr01_pfr04_sem_selecao_nada_muda() {
  local base base2 a b
  base=$(_amb)
  base2=$(_amb)
  _padrao "$base"
  _padrao "$base2"
  _rodar "$base" --json space
  a=$DBX_SAIDA
  DBX_ENV_EXTRA='DBX_PERFIL=' _rodar "$base2" --json space
  b=$DBX_SAIDA
  assert_igual "$a" "$b" 'DBX_PERFIL vazio = sem selecao'
  assert_igual "$(grep -o 'https://[^ ]*' "$base/argv")" "$(grep -o 'https://[^ ]*' "$base2/argv")" 'mesmas chamadas'
  [[ ! -e $base/config/dbx/perfis ]] || _harness_falhar 'perfis/ criado sem pedido'
}

teste_pfr05_perfil_padrao_e_omitir_a_selecao_exceto_o_campo_perfil() {
  local base a b
  base=$(_amb)
  _padrao "$base"
  _rodar "$base" --json space
  a=$DBX_SAIDA
  _rodar "$base" --json --perfil padrao space
  b=$DBX_SAIDA
  assert_igual "$a" "$b" 'space igual'
}

teste_pfr06_credencial_json_nunca_e_movida_nem_regravada() {
  local base antes
  base=$(_amb)
  _padrao "$base"
  _perfil "$base" a
  antes=$(_retrato "$base/config/dbx/credencial.json")
  _rodar "$base" perfis
  _rodar "$base" --perfil a space
  _rodar "$base" --perfil a diagnostico
  assert_igual "$antes" "$(_retrato "$base/config/dbx/credencial.json")" 'padrao intocado'
  [[ -f $base/config/dbx/credencial.json ]] || _harness_falhar 'sumiu'
}

harness_executar "$@"
