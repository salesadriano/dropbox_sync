#!/usr/bin/env bash
# harness.sh — arcabouco minimo de teste para shell, com saida em formato TAP 13.
#
# Motivo de existir: `bats` e `shunit2` nao estao instalados neste ambiente e a
# instalacao de pacotes exige sinalizacao previa ao solicitante. O formato de
# saida adotado e TAP 13 justamente para que a troca por `bats` no futuro nao
# altere o contrato de relatorio consumido pelo QA.
#
# Uso em um arquivo de teste:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/../support/harness.sh"
#   teste_algum_comportamento() { assert_igual esperado obtido "descricao"; }
#   harness_executar "$@"
#
# Cada funcao com prefixo `teste_` e executada em subshell proprio, o que impede
# vazamento de estado entre casos.

set -u

DBX_HARNESS_RAIZ=${DBX_HARNESS_RAIZ:-$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}
export DBX_HARNESS_RAIZ

# ---------------------------------------------------------------------------
# Assercoes. Toda assercao que falha encerra o caso de teste corrente.
# ---------------------------------------------------------------------------

_harness_falhar() {
  printf '# FALHA: %s\n' "$1" >&2
  shift
  local linha
  for linha in "$@"; do
    printf '#   %s\n' "$linha" >&2
  done
  exit 1
}

assert_igual() {
  local esperado=$1 obtido=$2 descricao=${3:-valores devem ser iguais}
  [[ $esperado == "$obtido" ]] && return 0
  _harness_falhar "$descricao" "esperado: [$esperado]" "obtido:   [$obtido]"
}

assert_diferente() {
  local proibido=$1 obtido=$2 descricao=${3:-valores devem ser diferentes}
  [[ $proibido != "$obtido" ]] && return 0
  _harness_falhar "$descricao" "valor proibido foi obtido: [$obtido]"
}

assert_contem() {
  local agulha=$1 palheiro=$2 descricao=${3:-texto deve conter trecho}
  [[ $palheiro == *"$agulha"* ]] && return 0
  _harness_falhar "$descricao" "trecho ausente: [$agulha]" "texto:          [$palheiro]"
}

assert_nao_contem() {
  local agulha=$1 palheiro=$2 descricao=${3:-texto nao deve conter trecho}
  [[ $palheiro != *"$agulha"* ]] && return 0
  _harness_falhar "$descricao" "trecho proibido presente: [$agulha]" "texto: [$palheiro]"
}

# assert_status <esperado> <comando...>
assert_status() {
  local esperado=$1
  shift
  local saida obtido
  saida=$("$@" 2>&1)
  obtido=$?
  [[ $esperado == "$obtido" ]] && return 0
  _harness_falhar "status de saida divergente ao executar: $*" \
    "esperado: $esperado" "obtido:   $obtido" "saida:    ${saida//$'\n'/ | }"
}

assert_sucesso() { assert_status 0 "$@"; }

assert_arquivo_existe() {
  local caminho=$1 descricao=${2:-arquivo deve existir}
  [[ -e $caminho ]] && return 0
  _harness_falhar "$descricao" "caminho ausente: [$caminho]"
}

assert_arquivo_ausente() {
  local caminho=$1 descricao=${2:-arquivo nao deve existir}
  [[ ! -e $caminho ]] && return 0
  _harness_falhar "$descricao" "caminho presente indevidamente: [$caminho]"
}

# _agora_ms — relogio monotonico em milissegundos, para medir custo relativo.
_agora_ms() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local partes=${EPOCHREALTIME/,/.}
    printf '%s' "$(((${partes%.*} * 1000) + (10#${partes#*.} / 1000)))"
    return 0
  fi
  printf '%s' "$((SECONDS * 1000))"
}

# pular <motivo> — marca o caso como nao executado, sem falhar a suite.
pular() {
  printf '%s\n' "${1:-sem motivo declarado}" >"${DBX_HARNESS_ARQ_PULAR:-/dev/null}"
  exit 77
}

# ---------------------------------------------------------------------------
# Execucao
# ---------------------------------------------------------------------------

harness_executar() {
  local filtro=${1:-}
  local -a casos=()
  local nome
  while IFS= read -r nome; do
    casos+=("$nome")
  done < <(declare -F | awk '{print $3}' | grep '^teste_' | sort)

  if [[ -n $filtro ]]; then
    local -a filtrados=()
    for nome in "${casos[@]}"; do
      [[ $nome == *"$filtro"* ]] && filtrados+=("$nome")
    done
    casos=("${filtrados[@]:-}")
    [[ -z ${casos[0]:-} ]] && casos=()
  fi

  local total=${#casos[@]}
  printf 'TAP version 13\n'
  printf '1..%d\n' "$total"

  # Filtro que nao corresponde a nenhum caso REPROVA. Aprovar sem executar nada
  # faz um job de integracao com nome errado passar verde — a mesma falha que o
  # executor tinha, um nivel abaixo e alcancavel por invocacao direta.
  if [[ $total -eq 0 ]]; then
    if [[ -n $filtro ]]; then
      printf '# FALHA: o filtro "%s" nao corresponde a nenhum caso deste arquivo\n' "$filtro" >&2
    else
      printf '# FALHA: nenhum caso de teste encontrado neste arquivo\n' >&2
    fi
    printf '# resumo ok=0 nao_ok=1 pulados=0\n'
    [[ -n ${DBX_HARNESS_RESUMO:-} ]] && printf '0 1 0\n' >"$DBX_HARNESS_RESUMO"
    return 1
  fi

  local indice=0 ok=0 nao_ok=0 pulados=0 status motivo
  # Area controlada da suite, e nao `mktemp` puro: um temporario fora de
  # $DBX_TESTES_TMP escapa da limpeza do executor.
  DBX_HARNESS_ARQ_PULAR=$(mktemp "${DBX_TESTES_TMP:-${TMPDIR:-/tmp}}/dbx-harness.XXXXXX") || return 1
  export DBX_HARNESS_ARQ_PULAR
  trap 'rm -f "$DBX_HARNESS_ARQ_PULAR"' EXIT

  for nome in "${casos[@]}"; do
    indice=$((indice + 1))
    : >"$DBX_HARNESS_ARQ_PULAR"
    (
      set -u
      if declare -F preparar_caso >/dev/null; then preparar_caso; fi
      "$nome"
    )
    status=$?
    case $status in
      0)
        ok=$((ok + 1))
        printf 'ok %d - %s\n' "$indice" "${nome#teste_}"
        ;;
      77)
        pulados=$((pulados + 1))
        motivo=$(cat "$DBX_HARNESS_ARQ_PULAR" 2>/dev/null)
        printf 'ok %d - %s # SKIP %s\n' "$indice" "${nome#teste_}" "$motivo"
        ;;
      *)
        nao_ok=$((nao_ok + 1))
        printf 'not ok %d - %s\n' "$indice" "${nome#teste_}"
        ;;
    esac
  done

  # A linha abaixo e informativa, destinada a leitura humana. Ela NAO e a fonte
  # do agregado: o executor le os totais de $DBX_HARNESS_RESUMO, um canal
  # separado da saida padrao dos testes. Sem essa separacao, o agregado seria
  # apenas texto que os proprios testes emitem, e portanto forjavel.
  printf '# resumo ok=%d nao_ok=%d pulados=%d\n' "$ok" "$nao_ok" "$pulados"
  if [[ -n ${DBX_HARNESS_RESUMO:-} ]]; then
    printf '%d %d %d\n' "$ok" "$nao_ok" "$pulados" >"$DBX_HARNESS_RESUMO"
  fi
  [[ $nao_ok -eq 0 ]]
}
