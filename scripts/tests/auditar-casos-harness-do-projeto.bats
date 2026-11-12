#!/usr/bin/env bats
# Autoria: Tech Lead (adocao do protocolo 1.3.1); red comprovado contra o auditar-casos.sh do modelo.
# Adaptacoes do projeto em scripts/auditar-casos.sh (adaptador shell, harness proprio em tests/support/harness.sh):
# `_harness_falhar` conta como assercao direta; o braco de `case` e as atribuicoes `VAR=valor` no inicio do segmento
# sao ignorados antes de reconhecer a assercao. Os negativos provam que a adaptacao nao cala caso inerte de verdade.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../auditar-casos.sh"
  RAIZ="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$RAIZ"
  mkdir -p "$RAIZ/scripts" "$RAIZ/tests"
  printf 'tests/*_test.sh\tshell\n' > "$RAIZ/scripts/auditar-casos.txt"
}

arquivo() {
  cat > "$RAIZ/$1"
  git -C "$RAIZ" add -A
}

roda() {
  run sh -c "cd '$RAIZ' && sh '$SCRIPT'"
}

@test "projeto: cond || _harness_falhar dentro de laco conta como assercao" {
  arquivo tests/a_test.sh <<'EOF'
teste_laco() {
  local n
  for n in a b; do
    valido "$n" ||
      _harness_falhar "recusado: $n"
  done
  return 0
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"bloqueantes: 0"* ]]
}

@test "projeto: _harness_falhar num braco de case conta como assercao" {
  arquivo tests/a_test.sh <<'EOF'
teste_case() {
  local p
  p=$(politica)
  case $p in
    nenhuma | retomar) ;;
    *) _harness_falhar "fora do contrato: $p" ;;
  esac
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"bloqueantes: 0"* ]]
}

@test "projeto: assercao prefixada por VAR=valor (com e sem aspas, com espaco no valor) conta" {
  arquivo tests/a_test.sh <<'EOF'
teste_sem_aspas() {
  XDG_CONFIG_HOME=relativo/config assert_status 1 dbx_config_caminho
}
teste_aspas_simples() {
  A='x y' B=z assert_sucesso dbx_preflight_verificar
}
teste_aspas_duplas() {
  XDG_CONFIG_HOME="$area/config" assert_sucesso dbx_preflight_verificar
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 3 | bloqueantes: 0"* ]]
}

@test "projeto: helper com assercao chamado com VAR=valor na frente conta (transitiva)" {
  arquivo tests/a_test.sh <<'EOF'
_matriz() {
  assert_igual 0 "$(executa "$@")"
}
teste_verificar() {
  QA_ESTADO='estado=' _matriz verificar '' verificar --enviar
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"casos: 1 | bloqueantes: 0"* ]]
}

@test "projeto (negativo): VAR=valor seguido de comando sem assercao continua SEM-ASSERCAO" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  XDG_CONFIG_HOME=/tmp/x dbx_config_caminho
  true
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a_test.sh :: teste_inerte :: linha 1"* ]]
}

@test "projeto (negativo): braco de case sem assercao continua SEM-ASSERCAO" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte_case() {
  case $x in
    a) echo a ;;
    *) echo outro ;;
  esac
}
EOF
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a_test.sh :: teste_inerte_case :: linha 1"* ]]
}

@test "projeto (negativo): _harness_falhar so conta no adaptador shell, nao no bats" {
  printf '*.bats\tbats\n' > "$RAIZ/scripts/auditar-casos.txt"
  printf '@test "x" {\n  valido || _harness_falhar "y"\n}\n' > "$RAIZ/tests/a.bats"
  git -C "$RAIZ" add -A
  roda
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a.bats :: x"* ]]
}
