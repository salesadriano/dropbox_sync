#!/usr/bin/env bats
# Testes de scripts/memoria-extrato.sh: extrato por papel e assunto, com teto de bytes e lista do que ficou de fora.

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/raiz/scripts" "$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
  cp "$BATS_TEST_DIRNAME/../memoria-extrato.sh" "$BATS_TEST_TMPDIR/raiz/scripts/"
  SCRIPT="$BATS_TEST_TMPDIR/raiz/scripts/memoria-extrato.sh"
  DIR="$BATS_TEST_TMPDIR/raiz/.github/agents/memoria/entradas"
}

entrada() {  # $1 nome, $2 tipo, $3 escopo, $4 agentes, $5 status, $6 titulo, $7 corpo
  cat > "$DIR/$1.md" <<EOF
---
id: $1
tipo: $2
escopo: $3
titulo: $6
data: 2026-10-01
dono: Tech Lead
agentes: $4
status: $5
---

$7
EOF
}

@test "filtra por papel: entra o proprio papel e todos, nao os outros" {
  entrada 2026-10-01-1000-a decisao projeto "qa-expert" ativa "Turno" "corpo a"
  entrada 2026-10-01-1001-b decisao projeto "dba" ativa "Indice" "corpo b"
  entrada 2026-10-01-1002-c decisao pacote "todos" ativa "Regra" "corpo c"
  run sh "$SCRIPT" --papel qa-expert
  [ "$status" -eq 0 ]
  [[ "$output" == *"## 2026-10-01-1000-a"* ]]
  [[ "$output" != *"## 2026-10-01-1001-b"* ]]
  [[ "$output" == *"## 2026-10-01-1002-c"* ]]
  [[ "$output" == *"extrato: 2 de 2 entradas pertinentes"* ]]
  run sh "$SCRIPT" --papel tech-lead
  [[ "$output" == *"extrato: 3 de 3 entradas pertinentes"* ]]
}

@test "ordena por relevancia aos termos: titulo pesa mais que corpo" {
  entrada 2026-10-01-1000-a decisao projeto "qa-expert" ativa "Alocacao no segundo turno" "nada"
  entrada 2026-10-02-1000-b decisao projeto "qa-expert" ativa "Outra coisa" "fala de turno no corpo"
  entrada 2026-10-03-1000-c decisao projeto "qa-expert" ativa "Nada a ver" "nada"
  run sh "$SCRIPT" --papel qa-expert --termos "TURNO alocacao"
  primeiro=$(printf '%s\n' "$output" | grep '^## ' | sed -n 1p)
  segundo=$(printf '%s\n' "$output" | grep '^## ' | sed -n 2p)
  [ "$primeiro" = "## 2026-10-01-1000-a" ]
  [ "$segundo" = "## 2026-10-02-1000-b" ]
}

@test "teto de bytes e de entradas corta e lista as omitidas por id" {
  for i in 1 2 3 4; do entrada "2026-10-0$i-1000-e$i" decisao projeto "dba" ativa "Entrada $i" "$(printf 'x%.0s' $(seq 1 300))"; done
  run sh "$SCRIPT" --papel dba --max-bytes 900
  [[ "$output" == *"extrato: 2 de 4 entradas pertinentes"* ]]
  [[ "$output" == *"omitidas: 2026-10-02-1000-e2 2026-10-01-1000-e1"* ]]
  run sh "$SCRIPT" --papel dba --max-entradas 1
  [[ "$output" == *"extrato: 1 de 4 entradas pertinentes"* ]]
}

@test "ignora entradas nao ativas e respeita --desde; o corpo e impresso com a cabeca" {
  entrada 2026-10-01-1000-a decisao projeto "dba" encerrada "Encerrada" "x"
  entrada 2026-10-02-1000-b decisao projeto "dba" ativa "Antiga" "corpo antigo"
  entrada 2026-10-09-1000-c aceite projeto "dba" ativa "Recente" "corpo recente"
  run sh "$SCRIPT" --papel dba --desde 2026-10-05
  [[ "$output" == *"extrato: 1 de 1 entradas pertinentes"* ]]
  [[ "$output" == *"- tipo: aceite | escopo: projeto | agentes: dba"* ]]
  [[ "$output" == *"corpo recente"* ]]
  [[ "$output" != *"Encerrada"* ]]
}

@test "papel invalido ou ausente sai com 2; sem entradas pertinentes imprime extrato vazio" {
  run sh "$SCRIPT" --papel chefe
  [ "$status" -eq 2 ]
  run sh "$SCRIPT"
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --papel dba
  [ "$status" -eq 0 ]
  [ "$output" = "extrato: 0 de 0 entradas pertinentes, 0 bytes | omitidas: nenhuma" ]
}

@test "--entradas le outro diretorio; decisao de pacote ganha +1 e, empatadas, a mais nova vem primeiro" {
  DIR="$BATS_TEST_TMPDIR/alternativo"; mkdir -p "$DIR"
  entrada 2026-10-01-1000-pacote decisao pacote "dba" ativa "Antiga de pacote" "x"
  entrada 2026-10-02-1000-projeto-velha aceite projeto "dba" ativa "Projeto velha" "x"
  entrada 2026-10-03-1000-projeto-nova aceite projeto "dba" ativa "Projeto nova" "x"
  run sh "$SCRIPT" --papel dba
  [ "$status" -eq 0 ]
  [ "$output" = "extrato: 0 de 0 entradas pertinentes, 0 bytes | omitidas: nenhuma" ]
  run sh "$SCRIPT" --papel dba --entradas "$DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"extrato: 3 de 3 entradas pertinentes"* ]]
  ordem=$(printf '%s\n' "$output" | grep '^## ' | tr '\n' ' ')
  [ "$ordem" = "## 2026-10-01-1000-pacote ## 2026-10-03-1000-projeto-nova ## 2026-10-02-1000-projeto-velha " ]
}

# ---------- pendentes (auditoria 2026-11-08, secao 7) ----------

@test "pendente: agentes com virgula sem espaco casam como a forma com espaco e dba nao casa dba-x" {
  skip "pendente: provar 'agentes: qa-expert,dba' e 'todos,dba' casando, e papel prefixo de outro token nao casando"
}
