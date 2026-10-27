#!/usr/bin/env bash
# Testes de portabilidade do chmod (RF-166, TC-FBSD-01, TC-FBSD-19 parte chmod).
#
# O chmod do FreeBSD trata como MODO o primeiro argumento que nao e opcao, e o
# que vem depois e operando: `chmod 600 -- arquivo` tenta mudar o arquivo `--`.
# Em GNU a forma funciona, entao o defeito so aparece com o duble de
# tests/duplos/freebsd/bin/chmod no PATH. A forma portavel e `chmod -- 600 arq`.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck disable=SC2034
# Justificativa: canais de lib/cli, lib/auth e lib/http ajustados pelos casos.
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
  mktemp -d "$DBX_TESTES_TMP/chmodbsd.XXXXXX"
}

# ---------------------------------------------------------------------------
# O duble imita o BSD (sem ele, os demais casos nao provam nada)
# ---------------------------------------------------------------------------

teste_duplo_de_chmod_trata_dois_hifens_depois_do_modo_como_operando() {
  local area saida estado
  area=$(_area)
  : >"$area/a"
  dbx_freebsd_ativar
  saida=$(chmod 640 -- "$area/a" 2>&1)
  estado=$?
  assert_igual 1 "$estado" 'no BSD o `--` apos o modo e operando e o chmod falha'
  assert_contem 'chmod: --: No such file or directory' "$saida"
  assert_igual 640 "$(dbx_freebsd_real stat -c %a -- "$area/a")" 'os demais operandos validos recebem o modo'
}

teste_duplo_de_chmod_aceita_dois_hifens_antes_do_modo() {
  local area
  area=$(_area)
  : >"$area/a"
  dbx_freebsd_ativar
  chmod -- 640 "$area/a"
  assert_igual 0 $? 'forma portavel'
  assert_igual 640 "$(dbx_freebsd_real stat -c %a -- "$area/a")"
  chmod -R -- 600 "$area/a"
  assert_igual 0 $? 'opcao antes do `--` continua opcao'
  assert_igual 600 "$(dbx_freebsd_real stat -c %a -- "$area/a")"
  assert_igual '' "$(dbx_freebsd_erros)" 'nada registrado como erro'
}

# ---------------------------------------------------------------------------
# TC-FBSD-01 e os demais pontos de chamada, pelo comportamento observavel
# ---------------------------------------------------------------------------

teste_gravacao_da_credencial_conclui_com_chmod_bsd() {
  local area
  area=$(_area)
  XDG_CONFIG_HOME="$area/config"
  export XDG_CONFIG_HOME
  dbx_freebsd_ativar
  dbx_config_gravar 'AK' 'AS' 'RT' '/raiz'
  assert_igual 0 $? "a gravacao da credencial falhou: ${DBX_CONFIG_MOTIVO:-} ${DBX_CONFIG_DETALHE:-}"
  assert_igual 600 "$(dbx_freebsd_real stat -c %a -- "$DBX_CONFIG_RESULTADO")" 'a credencial precisa ficar 0600'
  assert_nao_contem 'chmod: --' "${DBX_CONFIG_DETALHE:-}"
  assert_igual '' "$(dbx_freebsd_erros)" 'nenhum chmod falhou'
}

teste_preparo_do_diretorio_de_estado_conclui_com_chmod_bsd() {
  local area
  area=$(_area)
  mkdir -p "$area/estado"
  chmod 755 "$area/estado"
  dbx_freebsd_ativar
  _dbx_state_preparar_diretorio "$area/estado"
  assert_igual 0 $? 'o preparo do diretorio de estado nao pode falhar no BSD'
  assert_igual 700 "$(dbx_freebsd_real stat -c %a -- "$area/estado")" 'o diretorio de estado precisa ficar 0700'
  assert_igual '' "$(dbx_freebsd_erros)" 'nenhum chmod falhou'
}

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

teste_recebimento_aplica_o_modo_do_alvo_com_chmod_bsd() {
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
  assert_igual 640 "$(dbx_freebsd_real stat -c %a -- "$area/alvo.txt")" 'o modo do alvo precisa ser preservado'
  assert_igual '' "$(dbx_freebsd_erros)" 'o chmod do modo falhou e o produto engoliu o erro'
}

# O ponto de lib/cmd.sh:1049 (`.part` do recebimento retomavel) nao tem teste de
# comportamento proprio: exige estado de retomada, trava e resposta 206. Fica
# coberto pela auditoria estatica abaixo, que cobre os quatro pontos.

# ---------------------------------------------------------------------------
# TC-FBSD-19, parte chmod — auditoria estatica
# ---------------------------------------------------------------------------

# _chmod_com_dois_hifens_apos_o_modo <arquivo...> — `chmod [-opcoes] <modo> --`
# fora de comentario. O padrao reconhece opcoes antes do modo (`chmod -R 755 --`).
_chmod_com_dois_hifens_apos_o_modo() {
  grep -nE '(^|[^A-Za-z0-9_-])chmod([[:space:]]+-[A-Za-z]+)*[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]+--([[:space:]]|$)' "$@" |
    grep -vE '^[^:]*:?[0-9]+:[[:space:]]*#' || true
}

teste_nenhum_chmod_do_produto_poe_dois_hifens_depois_do_modo() {
  local area mutacao achados
  area=$(_area)
  printf '%s\n' 'chmod 600 -- "$a"' >"$area/literal.sh"
  printf '%s\n' 'chmod "$modo" -- "$a" 2>/dev/null || :' >"$area/variavel.sh"
  printf '%s\n' 'chmod -R 755 -- "$d"' >"$area/opcao.sh"
  for mutacao in literal variavel opcao; do
    [[ -n $(_chmod_com_dois_hifens_apos_o_modo "$area/$mutacao.sh") ]] ||
      _harness_falhar "a auditoria nao acusou a forma '$mutacao'"
  done
  printf '%s\n' 'chmod -- 600 "$a"' 'chmod 600 "$a"' 'chmod -R -- 755 "$d"' \
    '  # chmod 600 -- "$a" em comentario' >"$area/limpo.sh"
  assert_igual '' "$(_chmod_com_dois_hifens_apos_o_modo "$area/limpo.sh")" \
    'forma portavel, forma sem separador e comentario nao sao acusados'
  achados=$(_chmod_com_dois_hifens_apos_o_modo "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh \
    "$DBX_HARNESS_RAIZ/bin/dbx" "$DBX_HARNESS_RAIZ/install.sh" "$DBX_HARNESS_RAIZ/uninstall.sh")
  assert_igual '' "$achados" "chmod com \`--\` depois do modo (falha no BSD): $achados"
}

harness_executar "$@"
