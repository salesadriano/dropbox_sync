#!/usr/bin/env bash
# run.sh — executa a suite de testes da camada de dominio.
#
#   ./tests/run.sh                  executa tudo que nao depende de rede
#   ./tests/run.sh hash             executa apenas os arquivos cujo nome contem "hash"
#   DBX_TESTES_REDE=1 ./tests/run.sh    habilita os casos que baixam o vetor oficial
#
# Percorre `tests/unit/` e `tests/integracao/`. A segunda existe porque a suite
# chegou a 237 casos sem nenhum que cruzasse componentes, e foi exatamente ai
# que o QF-01 se escondeu: cada componente correto, o defeito so em cadeia.
#
# A suite nao exige credencial, nao toca a Dropbox e, por padrao, nao usa rede
# (RNF-14). Todo artefato temporario e criado sob um diretorio proprio removido
# ao final, preservando a invariante de ausencia de estado local (PRJ-DEC-07).
#
# Integridade do agregado
# -----------------------
# Os totais NAO sao extraidos da saida padrao dos testes. Cada arquivo de teste
# grava seus tres contadores em um arquivo proprio, indicado por
# DBX_HARNESS_RESUMO, e este executor os le com validacao estrita de inteiros.
# Nao ha `eval` em nenhum ponto: a versao anterior avaliava uma linha vinda do
# stdout dos testes, o que permitia execucao de comando arbitrario e forja dos
# totais, e portanto invalidava a suite como evidencia.
#
# Um filtro que nao corresponda a nenhum arquivo REPROVA. Aprovar sem executar
# nada faria um job de CI com nome de suite errado passar verde.

set -u

RAIZ=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
export DBX_HARNESS_RAIZ=$RAIZ

filtro=${1:-}

DBX_TESTES_TMP=$(mktemp -d "${TMPDIR:-/tmp}/dbx-testes.XXXXXXXX") || exit 1
export DBX_TESTES_TMP
trap 'rm -rf "$DBX_TESTES_TMP"' EXIT INT TERM

total_ok=0
total_nao_ok=0
total_pulados=0
arquivos_falhos=0
arquivos_executados=0
problemas_de_integridade=0

for arquivo in "$RAIZ"/tests/unit/*_test.sh "$RAIZ"/tests/integracao/*_test.sh; do
  [[ -e $arquivo ]] || continue
  nome=$(basename -- "$arquivo")
  if [[ -n $filtro && $nome != *"$filtro"* ]]; then
    continue
  fi
  arquivos_executados=$((arquivos_executados + 1))
  printf '\n# ===== %s =====\n' "$nome"

  resumo_arquivo="$DBX_TESTES_TMP/resumo.$arquivos_executados"
  : >"$resumo_arquivo"

  DBX_HARNESS_RESUMO="$resumo_arquivo" bash "$arquivo"
  status=$?

  if [[ ! -s $resumo_arquivo ]]; then
    printf '# INTEGRIDADE: %s terminou sem gravar o agregado (status %d)\n' "$nome" "$status"
    problemas_de_integridade=$((problemas_de_integridade + 1))
    arquivos_falhos=$((arquivos_falhos + 1))
    continue
  fi

  linha=$(tr -d '\n' <"$resumo_arquivo")
  if [[ $linha =~ ^([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
    total_ok=$((total_ok + BASH_REMATCH[1]))
    total_nao_ok=$((total_nao_ok + BASH_REMATCH[2]))
    total_pulados=$((total_pulados + BASH_REMATCH[3]))
  else
    printf '# INTEGRIDADE: agregado malformado em %s: [%s]\n' "$nome" "$linha"
    problemas_de_integridade=$((problemas_de_integridade + 1))
    arquivos_falhos=$((arquivos_falhos + 1))
    continue
  fi

  [[ $status -ne 0 ]] && arquivos_falhos=$((arquivos_falhos + 1))
done

printf '\n# =========================================\n'
printf '# arquivos executados : %d\n' "$arquivos_executados"
printf '# casos aprovados     : %d\n' "$total_ok"
printf '# casos reprovados    : %d\n' "$total_nao_ok"
printf '# casos pulados       : %d\n' "$total_pulados"

if [[ $arquivos_executados -eq 0 ]]; then
  if [[ -n $filtro ]]; then
    printf '# resultado           : REPROVADA (o filtro "%s" nao corresponde a nenhum arquivo)\n' "$filtro"
  else
    printf '# resultado           : REPROVADA (nenhum arquivo de teste encontrado)\n'
  fi
  exit 1
fi

if [[ $problemas_de_integridade -gt 0 ]]; then
  printf '# resultado           : REPROVADA (%d falha(s) de integridade do agregado)\n' "$problemas_de_integridade"
  exit 1
fi

if [[ $arquivos_falhos -eq 0 ]]; then
  printf '# resultado           : APROVADA\n'
  exit 0
fi
printf '# resultado           : REPROVADA (%d arquivo(s) com falha)\n' "$arquivos_falhos"
exit 1
