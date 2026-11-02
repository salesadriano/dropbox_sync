#!/usr/bin/env bash
# Auditoria de compatibilidade com bash 4.2 (linha legada support/bash-4.2;
# RF-199..RF-201, TC-B42-*): o codigo entregue nao pode usar construcoes de
# bash 4.3+ — nameref (`local -n`/`declare -n`), `wait -n` e transformacao
# `${nome@op}`. Linhas de comentario sao ignoradas.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

# _arquivos_do_codigo — lista os arquivos auditados, um por linha.
_arquivos_do_codigo() {
  local raiz=$DBX_HARNESS_RAIZ
  find "$raiz/bin" "$raiz/lib" "$raiz/commands" "$raiz/completions" "$raiz/tests/support" \
    -type f 2>/dev/null
  find "$raiz" -maxdepth 1 -type f \( -name '*.sh' \)
}

# _achados <regex-ere> — linhas de codigo (nao comentario) que casam; arquivo:linha:texto.
_achados() {
  local arquivo
  while IFS= read -r arquivo; do
    grep -nE -- "$1" "$arquivo" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|${arquivo#"$DBX_HARNESS_RAIZ"/}:|"
  done < <(_arquivos_do_codigo)
}

teste_a_auditoria_enxerga_os_arquivos_do_codigo() {
  local lista
  lista=$(_arquivos_do_codigo)
  assert_contem '/lib/cli.sh' "$lista"
  assert_contem '/install.sh' "$lista"
  assert_contem '/tests/support/harness.sh' "$lista"
}

teste_a_auditoria_acusa_as_formas_proibidas() {
  local forma
  for forma in 'local -n ref=$1' 'declare -n ref=x' 'wait -n' 'x=${v@Q}' 'x=${v[0]@a}'; do
    printf '%s\n' "$forma" | grep -qE -- '(local|declare)[[:space:]]+-[A-Za-z]*n\b|wait[[:space:]]+-n\b|\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?@[A-Za-z]\}' ||
      _harness_falhar "a regex nao acusou '$forma'"
  done
}

teste_nao_ha_nameref_no_codigo() {
  local achados
  achados=$(_achados '(local|declare)[[:space:]]+-[A-Za-z]*n([[:space:]]|$)')
  assert_igual '' "$achados" "nameref (bash 4.3+) encontrado: $achados"
}

teste_nao_ha_wait_n_no_codigo() {
  local achados
  achados=$(_achados '(^|[;&|({[:space:]])wait[[:space:]]+-[A-Za-z]*n([[:space:]]|$)')
  assert_igual '' "$achados" "wait -n (bash 4.3+) encontrado: $achados"
}

teste_nao_ha_transformacao_de_expansao_no_codigo() {
  local achados
  achados=$(_achados '\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?@[A-Za-z]\}')
  assert_igual '' "$achados" "expansao \${nome@op} (bash 4.4+) encontrada: $achados"
}

# bash 4.2: `readonly X=(...)` e `declare -g... X=(valores)` dentro de funcao
# nao criam o global (o primeiro cria local; o segundo nada). As bibliotecas
# sao carregadas dentro de funcoes de bin/dbx, entao o vetor ficava vazio e o
# analisador de JSON recusava toda credencial. Forma aceita: declarar (ou
# `X=(...)`) e marcar depois. `declare -gA X=()` vazio funciona e e permitido.
teste_nao_ha_vetor_global_com_valores_na_declaracao() {
  local raiz=$DBX_HARNESS_RAIZ arquivo achados='' saida
  local regex='^[[:space:]]*(readonly([[:space:]]+-[A-Za-z]+)*|declare[[:space:]]+-[A-Za-z]*g[A-Za-z]*)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=\(([^)]|$)'
  while IFS= read -r arquivo; do
    saida=$(grep -nE -- "$regex" "$arquivo" 2>/dev/null | sed "s|^|${arquivo#"$raiz"/}:|")
    [[ -n $saida ]] && achados+=$saida$'\n'
  done < <(
    find "$raiz/bin" "$raiz/lib" "$raiz/commands" "$raiz/completions" "$raiz/tests/support" -type f 2>/dev/null
    find "$raiz" -maxdepth 1 -type f -name 'install.sh'
  )
  assert_igual '' "$achados" "vetor global com valores na declaracao: $achados"
}

teste_nao_ha_construcao_de_bash_4_3_ou_superior_no_codigo_nem_nos_testes() {
  local raiz=$DBX_HARNESS_RAIZ arquivo achados='' saida
  local regex='(mapfile|readarray)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-d|\[-[0-9]+\]\}|EPOCHSECONDS|(^|[^[:alnum:]_-])local[[:space:]]+-([[:space:]]|$)|inherit_errexit|\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?@[A-Za-z]\}'
  while IFS= read -r arquivo; do
    [[ $arquivo == */tests/unit/bash42_auditoria_test.sh ]] && continue
    saida=$(grep -nE -- "$regex" "$arquivo" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|${arquivo#"$raiz"/}:|")
    [[ -n $saida ]] && achados+=$saida$'\n'
  done < <(
    find "$raiz/bin" "$raiz/lib" "$raiz/commands" "$raiz/completions" "$raiz/tests" -type f 2>/dev/null
    find "$raiz" -maxdepth 1 -type f -name 'install.sh'
  )
  assert_igual '' "$achados" "construcao de bash 4.3+ encontrada: $achados"
}

harness_executar "$@"
