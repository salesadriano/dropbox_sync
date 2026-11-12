#!/usr/bin/env bats
# Autoria: QA Expert (validacao independente da adocao do protocolo 1.3.1).
# Procura brechas nas adaptacoes do projeto em scripts/auditar-casos.sh (adaptador shell): a adaptacao nao pode calar
# caso inerte. Cada caso e um caso inerte de verdade e deve continuar acusado como BLOQUEANTE SEM-ASSERCAO.

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

inerte() {
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOQUEANTE SEM-ASSERCAO tests/a_test.sh :: teste_inerte :: linha "* ]]
}

@test "qa: VAR=x echo (comando sem assercao com prefixo) continua inerte" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  VAR=x echo ok
}
EOF
  roda
  inerte
}

@test "qa: braco de case com comando neutro (foo) true ;;) continua inerte" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  case $1 in
    foo) true ;;
    *) : ;;
  esac
}
EOF
  roda
  inerte
}

@test "qa: braco de case cujo padrao parece assercao (grep) / test) nao conta" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  case $1 in
    grep) echo x ;;
    assert_igual) echo y ;;
  esac
}
EOF
  roda
  inerte
}

@test "qa: _harness_falhar dentro de string nao conta" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  echo "_harness_falhar nunca chamado"
}
EOF
  roda
  inerte
}

@test "qa: _harness_falhar em comentario nao conta" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  echo ok # _harness_falhar "x"
}
EOF
  roda
  inerte
}

@test "qa: funcao de nome parecido (_harness_falhar_x) nao conta como a primitiva" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  _harness_falhar_x "y"
}
EOF
  roda
  inerte
}

@test "qa: _harness_falhar dentro de substituicao x=\$(...) nao conta" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  x=$(_harness_falhar "y")
}
EOF
  roda
  inerte
}

@test "qa: VAR=valor antes de comando neutro dentro de braco de case continua inerte" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  case $1 in
    *) A=1 B="x y" echo feito ;;
  esac
}
EOF
  roda
  inerte
}

@test "qa: helper sem assercao chamado com VAR=valor nao vira assercao transitiva" {
  arquivo tests/a_test.sh <<'EOF'
_prepara() {
  A=1 echo preparo
}
teste_inerte() {
  Z=1 _prepara
}
EOF
  roda
  inerte
}

@test "qa: atribuicao pura VAR=valor (sem comando) continua inerte" {
  arquivo tests/a_test.sh <<'EOF'
teste_inerte() {
  RESULTADO=ok
}
EOF
  roda
  inerte
}

@test "qa (positivo): VAR=valor antes de _harness_falhar e assercao" {
  arquivo tests/a_test.sh <<'EOF'
teste_ok() {
  valido x || LANG=C _harness_falhar "recusado"
}
EOF
  roda
  [ "$status" -eq 0 ]
  [[ "$output" == *"bloqueantes: 0"* ]]
}
