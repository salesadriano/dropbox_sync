#!/usr/bin/env bash
# Testes do resumo SHA-256 por capacidade e dos utilitarios da base do FreeBSD
# (RF-169; TC-FBSD-04, 05, 06, 07 e 10).
#
# A base do FreeBSD nao traz `sha256sum` nem `shasum`: traz `sha256` e `openssl`.
# Cada caso monta um PATH RESTRITO (diretorio de links so com o necessario) e roda
# o componente num bash filho com `env -i`, de modo que o utilitario ausente de
# fato nao exista. Os vetores sao os literais de hash_test.sh, nao recalculados.
#
# shellcheck disable=SC2016
# Justificativa: os dubles e os programas filhos sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly ESPERADO_VAZIO=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly ESPERADO_UM_BYTE=1cd6ef71e6e0ff46ad2609d403dc3fee244417089aa4461245a4e4fe23a55e42

_area() {
  mktemp -d "$DBX_TESTES_TMP/resumo.XXXXXX"
}

# _caminho <area> [utilitario_extra...] — diretorio de links com a base comum e
# SEM nenhum utilitario de resumo; os extras sao acrescentados pelo chamador.
_caminho() {
  local dir=$1/bin alvo origem
  mkdir -p "$dir"
  for alvo in bash env head wc mktemp stat readlink find tr grep cat chmod mv rm mkdir \
    dirname basename sed seq awk od tail df sleep ln rmdir curl; do
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -sf "$origem" "$dir/$alvo"
  done
  printf '%s' "$dir"
}

# _hash_em <path> <arquivo> — "<content_hash> <bytes>" calculado so com <path>.
_hash_em() {
  env -i PATH="$1" "$BASH" -c '
    . "$1/lib/hash.sh" || exit 1
    dbx_hash_conteudo_arquivo_com_tamanho "$2"
  ' _ "$DBX_HARNESS_RAIZ" "$2" 2>&1
}

# _ausentes_em <path> — preflight sem parada, so com <path>: "<status>|<ausentes>".
_ausentes_em() {
  env -i PATH="$1" "$BASH" -c '
    . "$1/lib/errors.sh"; . "$1/lib/hash.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_ausentes
    estado=$?
    printf "%s|%s" "$estado" "${DBX_PREFLIGHT_AUSENTES[*]}"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1
}

# _openssl_de <caminho> — saida crua do `openssl` do PATH restrito para o byte `A`,
# so para conferir a premissa do formato.
_openssl_de() { printf 'A' | "$1/openssl" dgst -sha256; }

# ---------------------------------------------------------------------------
# TC-FBSD-04: so `sha256` (sem sha256sum, shasum nem openssl)
# ---------------------------------------------------------------------------

teste_so_sha256_da_base_confere_o_content_hash_e_passa_no_preflight() {
  local area caminho
  area=$(_area)
  caminho=$(_caminho "$area")
  ln -s "$DBX_FREEBSD_DUPLOS/sha256" "$caminho/sha256"
  : >"$area/vazio"
  printf 'A' >"$area/um"
  assert_igual "$ESPERADO_VAZIO 0" "$(_hash_em "$caminho" "$area/vazio")" 'RF-169: arquivo vazio com sha256 -q'
  assert_igual "$ESPERADO_UM_BYTE 1" "$(_hash_em "$caminho" "$area/um")" 'RF-169: um byte com sha256 -q'
  assert_igual '0|' "$(_ausentes_em "$caminho")" 'RF-169(b): host so com sha256 passa no preflight'
}

# ---------------------------------------------------------------------------
# TC-FBSD-05: so `openssl`, nos dois formatos de saida
# ---------------------------------------------------------------------------

teste_so_openssl_confere_o_content_hash_no_formato_do_openssl_3() {
  local area caminho
  area=$(_area)
  caminho=$(_caminho "$area")
  ln -s "$(command -v openssl)" "$caminho/openssl"
  printf 'A' >"$area/um"
  assert_contem 'SHA2-256(stdin)=' "$(_openssl_de "$caminho")" \
    'premissa: o openssl do host usa o formato 3.x; senao o caso nao prova esse formato'
  assert_igual "$ESPERADO_UM_BYTE 1" "$(_hash_em "$caminho" "$area/um")" 'RF-169(c): SHA2-256(stdin)= hex'
  assert_igual '0|' "$(_ausentes_em "$caminho")" 'RF-169(b): host so com openssl passa no preflight'
}

teste_so_openssl_confere_o_content_hash_no_formato_do_openssl_1() {
  local area caminho real
  area=$(_area)
  caminho=$(_caminho "$area")
  real=$(command -v openssl)
  {
    printf '#!%s\n' "$BASH"
    printf 'saida=$(%s dgst -sha256) || exit 1\n' "$real"
    printf 'printf "(stdin)= %%s\\n" "${saida##* }"\n'
  } >"$caminho/openssl"
  chmod +x "$caminho/openssl"
  assert_contem '(stdin)= ' "$(_openssl_de "$caminho")" 'premissa: o duble usa o formato 1.x'
  printf 'A' >"$area/um"
  : >"$area/vazio"
  assert_igual "$ESPERADO_UM_BYTE 1" "$(_hash_em "$caminho" "$area/um")" 'RF-169(c): (stdin)= hex'
  assert_igual "$ESPERADO_VAZIO 0" "$(_hash_em "$caminho" "$area/vazio")" 'RF-169(c): vazio em (stdin)= hex'
}

# ---------------------------------------------------------------------------
# TC-FBSD-06: nenhum dos quatro
# ---------------------------------------------------------------------------

teste_sem_nenhum_utilitario_de_resumo_o_preflight_recusa_com_codigo_3_nomeando_o_resumo() {
  local area caminho saida
  area=$(_area)
  caminho=$(_caminho "$area")
  saida=$(env -i PATH="$caminho" "$BASH" -c '
    . "$1/lib/errors.sh"; . "$1/lib/hash.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    estado=$?
    printf "%s|%s|%s" "$estado" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual 3 "${saida%%|*}" 'RF-169: codigo de saida de configuracao'
  assert_contem 'SHA-256' "$saida" 'a recusa nomeia o utilitario de resumo'
  assert_contem 'sha256sum' "$(_ausentes_em "$caminho")" 'a inspecao sem parada nomeia o resumo ausente'
}

# ---------------------------------------------------------------------------
# TC-FBSD-07: wc com largura 8 (BSD preenche com espacos a esquerda)
# ---------------------------------------------------------------------------

teste_tamanho_de_bloco_e_inteiro_limpo_com_wc_de_largura_8() {
  local area caminho real
  area=$(_area)
  caminho=$(_caminho "$area")
  ln -s "$(command -v sha256sum)" "$caminho/sha256sum"
  real=$(command -v wc)
  rm -f -- "$caminho/wc"
  {
    printf '#!%s\n' "$BASH"
    printf 'n=$(%s "$@") || exit 1\n' "$real"
    printf 'printf "%%8d\\n" "${n//[^0-9]/}"\n'
  } >"$caminho/wc"
  chmod +x "$caminho/wc"
  assert_igual '       1' "$("$caminho/wc" -c <<<'')" 'premissa: o duble preenche com espacos a esquerda'
  printf 'A' >"$area/um"
  assert_igual "$ESPERADO_UM_BYTE 1" "$(_hash_em "$caminho" "$area/um")" \
    'I-07: bytes lidos sem espacos, e o content_hash confere'
}

# ---------------------------------------------------------------------------
# TC-FBSD-10: mktemp que recusa opcao longa; modelo com seis X (I-10)
# ---------------------------------------------------------------------------

# _tmp_em <path> <modelo> — "<status>" de dbx_tmp_arquivo com o modelo dado.
_tmp_em() {
  env -i PATH="$1" TMPDIR="$3" "$BASH" -c '
    . "$1/lib/tmp.sh" || exit 1
    dbx_tmp_arquivo "$2"
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" "$2" 2>&1
}

teste_tmp_cria_area_e_arquivo_com_mktemp_sem_opcao_longa_e_exige_seis_x() {
  local area caminho real uso
  area=$(_area)
  caminho=$(_caminho "$area")
  real=$(command -v mktemp)
  rm -f -- "$caminho/mktemp"
  {
    printf '#!%s\n' "$BASH"
    printf 'for a in "$@"; do\n'
    printf '  case $a in --?*) printf "mktemp: illegal option -- -\\n" >&2; exit 1 ;; esac\n'
    printf 'done\n'
    printf 'exec %s "$@"\n' "$real"
  } >"$caminho/mktemp"
  chmod +x "$caminho/mktemp"
  uso=$(env -i PATH="$caminho" "$BASH" -c '. "$1/lib/errors.sh"; dbx_errors_codigo_saida uso_invalido' _ "$DBX_HARNESS_RAIZ")
  assert_igual 0 "$(_tmp_em "$caminho" "$area/a.XXXXXX" "$area")" 'seis X: o arquivo e criado'
  assert_igual "$uso" "$(_tmp_em "$caminho" "$area/b.XXX" "$area")" 'tres X: recusado como uso invalido (I-10)'
  assert_igual "$uso" "$(_tmp_em "$caminho" "$area/c.XXXXX" "$area")" 'cinco X: recusado como uso invalido (I-10)'
  assert_igual 0 "$(env -i PATH="$caminho" TMPDIR="$area" "$BASH" -c '
    . "$1/lib/tmp.sh" || exit 1
    dbx_tmp_area teste
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)" 'a area temporaria tambem conclui sem opcao longa'
}

harness_executar "$@"
