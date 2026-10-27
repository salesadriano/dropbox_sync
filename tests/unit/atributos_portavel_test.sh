#!/usr/bin/env bash
# Testes da leitura portavel de atributos de arquivo (RF-167; TC-FBSD-02, 11 e
# 19 parte stat).
#
# O stat do FreeBSD nao tem `-c`; ali `-f` e o formato. Em GNU o defeito so
# aparece com o duble de tests/duplos/freebsd/bin/stat no PATH, que rejeita `-c`.
# O produto le atributos por UM auxiliar (dbx_atributo, lib/atributos.sh), que
# tenta `stat -c` e, se o utilitario recusar, `stat -f`.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e as amostras da auditoria sao literais.
#
# shellcheck disable=SC2034
# Justificativa: canais de lib/auth e lib/http ajustados pelos casos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"
. "$DBX_HARNESS_RAIZ/lib/progress.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"
. "$DBX_HARNESS_RAIZ/lib/cmd.sh"

_area() {
  mktemp -d "$DBX_TESTES_TMP/atributos.XXXXXX"
}

# ---------------------------------------------------------------------------
# O duble imita o BSD (sem ele, os demais casos nao provam nada)
# ---------------------------------------------------------------------------

teste_duplo_de_stat_rejeita_c_e_aceita_f() {
  local area saida estado
  area=$(_area)
  printf 'abcde' >"$area/a"
  dbx_freebsd_ativar
  saida=$(stat -c %s -- "$area/a" 2>&1)
  estado=$?
  assert_igual 1 "$estado" 'no BSD `-c` e opcao ilegal'
  assert_contem 'stat: illegal option -- c' "$saida"
  assert_igual 5 "$(stat -f %z -- "$area/a")" '`-f %z` e o tamanho'
  assert_igual 5 "$(stat -L -f %z "$area/a")" '`-L` e aceito, `--` e opcional'
}

# ---------------------------------------------------------------------------
# dbx_atributo, com o stat do BSD e com o do GNU
# ---------------------------------------------------------------------------

teste_atributo_le_modo_dono_tamanho_e_mtime_com_stat_bsd() {
  local area
  area=$(_area)
  printf 'abcde' >"$area/a"
  chmod 640 "$area/a"
  touch -d @1700000000 "$area/a"
  dbx_freebsd_ativar
  dbx_atributo modo "$area/a"
  assert_igual 0 $? 'modo'
  assert_igual 640 "$DBX_ATRIBUTO"
  dbx_atributo dono "$area/a"
  assert_igual "$(id -u)" "$DBX_ATRIBUTO" 'dono'
  dbx_atributo tamanho "$area/a"
  assert_igual 5 "$DBX_ATRIBUTO" 'tamanho'
  dbx_atributo mtime "$area/a"
  assert_igual 1700000000 "$DBX_ATRIBUTO" 'mtime em segundos'
  dbx_atributo dev_ino "$area/a"
  assert_igual "$(dbx_freebsd_real stat -c '%d|%i' -- "$area/a")" "$DBX_ATRIBUTO" 'dev|ino'
  assert_igual '' "$(dbx_freebsd_erros | grep -v 'illegal option -- c')" 'so o `-c` recusado e registrado'
}

teste_atributo_le_do_mesmo_modo_com_stat_gnu() {
  local area
  area=$(_area)
  printf 'abcde' >"$area/a"
  chmod 600 "$area/a"
  dbx_atributo modo "$area/a"
  assert_igual 600 "$DBX_ATRIBUTO"
  dbx_atributo tamanho "$area/a"
  assert_igual 5 "$DBX_ATRIBUTO"
}

teste_modo_mantem_suid_e_sticky_e_coincide_nas_duas_formas() {
  local area
  area=$(_area)
  : >"$area/a"
  chmod 4600 "$area/a"
  mkdir -m 700 "$area/d"
  chmod 1700 "$area/d"
  dbx_atributo modo "$area/a"
  assert_igual 4600 "$DBX_ATRIBUTO" 'GNU: suid preservado'
  dbx_atributo modo "$area/d"
  assert_igual 1700 "$DBX_ATRIBUTO" 'GNU: sticky preservado'
  dbx_freebsd_ativar
  _dbx_atributos_forma=''
  dbx_atributo modo "$area/a"
  assert_igual 4600 "$DBX_ATRIBUTO" 'BSD: suid preservado, igual ao GNU'
  dbx_atributo modo "$area/d"
  assert_igual 1700 "$DBX_ATRIBUTO" 'BSD: sticky preservado, igual ao GNU'
  # O `%Lp` do BSD sai sem zeros a esquerda: sem largura fixa, 4044 viraria 444.
  chmod 4044 "$area/a"
  dbx_atributo modo "$area/a"
  assert_igual 4044 "$DBX_ATRIBUTO" 'BSD: digito especial com permissao de zero a esquerda'
  chmod 600 "$area/a"
  dbx_atributo modo "$area/a"
  assert_igual 600 "$DBX_ATRIBUTO" 'BSD: zeros a esquerda normalizados'
  chmod 000 "$area/a"
  dbx_atributo modo "$area/a"
  assert_igual 0 "$DBX_ATRIBUTO" 'BSD: modo 000 vira 0, como o %a do GNU'
  chmod 600 "$area/a"
}

# _stat_contador <dir> — stat no PATH que registra cada chamada e delega ao real.
_stat_contador() {
  mkdir -p "$1/bin"
  printf '%s\n' '#!/usr/bin/env bash' \
    "printf '%s\\n' \"\$*\" >>\"$1/chamadas\"" \
    'exec /usr/bin/stat "$@"' >"$1/bin/stat"
  chmod +x "$1/bin/stat"
}

teste_forma_aprendida_por_sonda_unica_uma_leitura_uma_chamada() {
  local area chamadas linha
  area=$(_area)
  : >"$area/a"
  : >"$area/chamadas"
  _stat_contador "$area"
  local PATH=$area/bin:$PATH
  _dbx_atributos_forma=''
  dbx_atributo modo "$area/nao-existe"
  assert_igual 1 $? 'arquivo ausente falha'
  mapfile -t chamadas <"$area/chamadas"
  for linha in "${chamadas[@]}"; do
    [[ $linha == -f\ * ]] && _harness_falhar "RF-167(d): arquivo ausente no GNU disparou a forma -f: $linha"
  done
  : >"$area/chamadas"
  dbx_atributo modo "$area/a"
  mapfile -t chamadas <"$area/chamadas"
  assert_igual 1 "${#chamadas[@]}" 'forma aprendida: uma leitura, uma chamada'
  : >"$area/chamadas"
  dbx_atributo modo "$area/nao-existe"
  mapfile -t chamadas <"$area/chamadas"
  assert_igual 1 "${#chamadas[@]}" 'forma aprendida: arquivo ausente, uma chamada'
}

teste_atributo_falha_sem_assumir_valor_quando_o_arquivo_nao_existe() {
  local area
  area=$(_area)
  dbx_freebsd_ativar
  DBX_ATRIBUTO=sobra
  dbx_atributo tamanho "$area/nao-existe"
  assert_igual 1 $? 'RF-167(e): falha de leitura e falha, nunca 0'
  assert_igual '' "$DBX_ATRIBUTO" 'o canal nao guarda valor de leitura anterior'
}

teste_atributo_de_tipo_do_sistema_de_arquivos_e_nao_verificado_no_bsd() {
  local area
  area=$(_area)
  dbx_freebsd_ativar
  dbx_atributo fs_tipo "$area"
  assert_igual 1 $? 'sem `stat -f -c %T` nao ha forma portavel (I-64): falha, e o chamador diz "nao verificado"'
}

# ---------------------------------------------------------------------------
# TC-FBSD-02: identidade e reaproveitamento do resumo
# ---------------------------------------------------------------------------

teste_identidade_do_arquivo_vem_preenchida_e_estavel_com_stat_bsd() {
  local area primeira
  area=$(_area)
  printf 'abcde' >"$area/a"
  dbx_freebsd_ativar
  dbx_hash_identidade "$area/a"
  assert_igual 0 $? 'RF-167(c): a identidade nao pode falhar no BSD'
  assert_igual 5 "$DBX_HASH_TAMANHO_ARQUIVO"
  [[ -n $DBX_HASH_IDENTIDADE ]] || _harness_falhar 'identidade vazia'
  assert_contem "|5" "$DBX_HASH_IDENTIDADE" 'o tamanho fecha a cadeia'
  primeira=$DBX_HASH_IDENTIDADE
  dbx_hash_identidade "$area/a"
  assert_igual "$primeira" "$DBX_HASH_IDENTIDADE" 'duas leituras do mesmo arquivo dao a mesma identidade'
  printf 'abcdefg' >"$area/a"
  dbx_hash_identidade "$area/a"
  [[ $DBX_HASH_IDENTIDADE != "$primeira" ]] || _harness_falhar 'a identidade nao mudou apos reescrever'
  assert_igual 7 "$DBX_HASH_TAMANHO_ARQUIVO"
}

# ---------------------------------------------------------------------------
# TC-FBSD-11: o modo do alvo e preservado na substituicao
# ---------------------------------------------------------------------------

# _duplo_de_recebimento <conteudo> <content_hash> — substituto de `curl` que
# entrega o conteudo em `-o` e o resumo no cabecalho `-D`.
_duplo_de_recebimento() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duplo.XXXXXX")
  printf '%s' "$1" >"$dir/corpo"
  printf '{"name":"a","content_hash":"%s"}' "$2" >"$dir/resultado"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'cat >/dev/null\n'
    printf 'saida=""; cabecalhos=""; escrever=""; anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -D) cabecalhos=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $saida ]] && cat "$dir/corpo" >"$saida"\n'
    printf '[[ -n $cabecalhos ]] && printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$dir/resultado")" >"$cabecalhos"\n'
    printf '[[ -n $escrever ]] && printf 200\n'
    printf 'exit 0\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

_hash_de_texto() { printf '%s' "$1" | dbx_hash_conteudo_fluxo; }

teste_recebimento_preserva_o_modo_do_alvo_com_stat_bsd() {
  local area dir
  area=$(_area)
  printf 'antigo' >"$area/alvo.txt"
  chmod 640 "$area/alvo.txt"
  dir=$(_duplo_de_recebimento 'novo conteudo' "$(_hash_de_texto 'novo conteudo')")
  DBX_AUTH_TOKEN='sl.token_de_teste'
  DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
  dbx_freebsd_ativar
  TMPDIR=$area PATH=$dir:$PATH dbx_cmd_receber_arquivo /r/a.txt "$area/alvo.txt"
  assert_igual 0 $? 'recebimento conferido conclui'
  assert_igual 'novo conteudo' "$(cat "$area/alvo.txt")"
  assert_igual 640 "$(dbx_freebsd_real stat -c %a -- "$area/alvo.txt")" \
    'sem o modo lido, o alvo perde o 0640 (I-19)'
}

# ---------------------------------------------------------------------------
# TC-FBSD-14: a idade do registro de retomada vem do mtime lido
# ---------------------------------------------------------------------------

teste_listagem_de_retomada_calcula_a_idade_pelo_mtime_com_stat_bsd() {
  local area
  area=$(_area)
  mkdir -p "$area/estado"
  mkdir -m 700 "$area/estado/dbx"
  printf 'ruim' >"$area/estado/dbx/retomada-0000000000000000000000000000000f"
  touch -d '9 days ago' "$area/estado/dbx/retomada-0000000000000000000000000000000f"
  XDG_STATE_HOME="$area/estado"
  export XDG_STATE_HOME
  dbx_freebsd_ativar
  dbx_state_retomada_listar
  assert_igual 1 "${#DBX_STATE_RETOMADAS_IDADE[@]}" 'um registro listado'
  assert_igual 9 "${DBX_STATE_RETOMADAS_IDADE[0]}" 'sem o mtime lido, a idade cai para 0 (I-40)'
}

# ---------------------------------------------------------------------------
# TC-FBSD-19, parte stat: auditoria estatica
# ---------------------------------------------------------------------------

# _stat_com_formato_fora_do_auxiliar <arquivo...> — `stat [-opcoes] -c|-f`
# fora de comentario de linha inteira.
_stat_com_formato_fora_do_auxiliar() {
  grep -nE '(^|[^A-Za-z0-9_])stat([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[cf]([[:space:]]|$)' "$@" |
    grep -vE '^[^:]*:?[0-9]+:[[:space:]]*#' || true
}

teste_nenhum_stat_com_formato_fora_do_auxiliar() {
  local area mutacao achados arquivo
  area=$(_area)
  printf '%s\n' 'x=$(stat -c %a -- "$a")' >"$area/gnu.sh"
  printf '%s\n' 'x=$(stat -f %Lp "$a")' >"$area/bsd.sh"
  printf '%s\n' 'x=$(stat -L -c %s -- "$a")' >"$area/opcao.sh"
  printf '%s\n' 't=$(stat -f -c %T -- "$a")' >"$area/fs.sh"
  for mutacao in gnu bsd opcao fs; do
    [[ -n $(_stat_com_formato_fora_do_auxiliar "$area/$mutacao.sh") ]] ||
      _harness_falhar "a auditoria nao acusou a forma '$mutacao'"
  done
  printf '%s\n' 'dbx_atributo modo "$a"' '  # stat -c %a em comentario' 'stat_total=3' >"$area/limpo.sh"
  assert_igual '' "$(_stat_com_formato_fora_do_auxiliar "$area/limpo.sh")" \
    'chamada ao auxiliar, comentario e nome parecido nao sao acusados'
  achados=''
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh \
    "$DBX_HARNESS_RAIZ/bin/dbx" "$DBX_HARNESS_RAIZ/install.sh" "$DBX_HARNESS_RAIZ/uninstall.sh"; do
    [[ ${arquivo##*/} == atributos.sh ]] && continue
    achados+=$(_stat_com_formato_fora_do_auxiliar "$arquivo")
  done
  assert_igual '' "$achados" "stat com -c/-f fora de lib/atributos.sh: $achados"
}

harness_executar "$@"
