#!/usr/bin/env bats
# Testes de specs-nao-executadas.sh: deriva do log do Cypress o que falhou e o que nao rodou.
# Portados do projeto de origem (casos do autor e os do QA, aceitos la), com os parametros daqui:
# `--clientes` e explicito nos casos com dois clientes, porque o padrao do pacote e `.`.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../specs-nao-executadas.sh"
  RAIZ="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$RAIZ/campo/cypress/e2e/sub" "$RAIZ/comando/cypress/e2e"
  for s in a b sub/c; do : > "$RAIZ/campo/cypress/e2e/$s.cy.ts"; done
  for s in x y z; do : > "$RAIZ/comando/cypress/e2e/$s.cy.ts"; done
  LOG="$BATS_TEST_TMPDIR/testes.log"
  SAIDA="$BATS_TEST_TMPDIR/saida.txt"
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/resumo.md"
  unset RUNNER_TEMP
  DOIS="--clientes campo,comando"
}

corrida() { printf '\n  (Run Starting)\n\n'; }
rodando() { printf '  Running:  %s  (%s of %s)\n' "$1" "$2" "$3"; }
passou() { printf '    \342\234\223 %s (12ms)\n' "$1"; }
falhou() { printf '    %s) %s\n' "$1" "$2"; }
pendente() { printf '    - %s\n' "$1"; }

@test "campo: falha no meio, specs seguintes so pendentes (fail-fast) ficam como nao executadas; comando nem comecou" {
  {
    corrida
    rodando a.cy.ts 1 3; passou 'um'; passou 'dois'
    rodando b.cy.ts 2 3; passou 'tres'; falhou 1 'quatro'
    rodando c.cy.ts 3 3; pendente 'cinco'; pendente 'seis'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -qx 'campo falhou: b.cy.ts' "$SAIDA"
  grep -qx 'campo nao executadas: sub/c.cy.ts' "$SAIDA"
  grep -qx 'campo reexecutar: b.cy.ts,sub/c.cy.ts' "$SAIDA"
  grep -qx 'comando executadas: 0' "$SAIDA"
  grep -qx 'comando falhou: nenhuma' "$SAIDA"
  grep -qx 'comando nao executadas: x.cy.ts,y.cy.ts,z.cy.ts' "$SAIDA"
  grep -qx 'comando reexecutar: x.cy.ts,y.cy.ts,z.cy.ts' "$SAIDA"
}

@test "campo inteiro verde e comando falha na primeira: a segunda corrida e atribuida ao segundo cliente" {
  {
    corrida
    rodando a.cy.ts 1 3; passou 'um'
    rodando b.cy.ts 2 3; passou 'dois'
    rodando c.cy.ts 3 3; passou 'tres'
    printf '  (Run Finished)\n'
    corrida
    rodando x.cy.ts 1 3; falhou 1 '"before each" hook'
    rodando y.cy.ts 2 3; pendente 'a'
    rodando z.cy.ts 3 3; pendente 'b'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 3' "$SAIDA"
  grep -qx 'campo reexecutar: nenhuma' "$SAIDA"
  grep -qx 'comando falhou: x.cy.ts' "$SAIDA"
  grep -qx 'comando reexecutar: x.cy.ts,y.cy.ts,z.cy.ts' "$SAIDA"
}

@test "spec que falhou e tambem tem testes verdes conta como falhou, nao como executada" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; falhou 1 'dois'; passou 'tres'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts' "$SAIDA"
  grep -qx 'campo executadas: 0' "$SAIDA"
}

@test "codigos de cor do terminal nao atrapalham a leitura" {
  { corrida; printf '  Running:  \033[90ma.cy.ts\033[39m  \033[90m(1 of 1)\033[39m\n'; printf '    \033[32m\342\234\223\033[39m um\n'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -qx 'campo nao executadas: b.cy.ts,sub/c.cy.ts' "$SAIDA"
}

@test "sem log: tudo nao executado, e isso fica dito" {
  run sh "$SCRIPT" --log "$BATS_TEST_TMPDIR/nao-existe.log" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  grep -q 'log ausente ou vazio' "$SAIDA"
  grep -qx 'campo nao executadas: a.cy.ts,b.cy.ts,sub/c.cy.ts' "$SAIDA"
  grep -qx 'comando nao executadas: x.cy.ts,y.cy.ts,z.cy.ts' "$SAIDA"
}

@test "publica no resumo da execucao, com o comando do disparo parcial e o workflow padrao, e acrescenta sem apagar" {
  echo 'linha anterior' > "$GITHUB_STEP_SUMMARY"
  { corrida; rodando a.cy.ts 1 1; falhou 1 'x'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$GITHUB_STEP_SUMMARY")" = 'linha anterior' ]
  grep -q '## Specs do E2E que nao rodaram' "$GITHUB_STEP_SUMMARY"
  grep -q 'gh workflow run e2e-parcial.yml' "$GITHUB_STEP_SUMMARY"
  grep -q 'branch de release' "$GITHUB_STEP_SUMMARY"
  grep -q 'campo reexecutar: a.cy.ts,b.cy.ts,sub/c.cy.ts' "$GITHUB_STEP_SUMMARY"
  ! grep -q 'master' "$GITHUB_STEP_SUMMARY"
  ! grep -q 'web-campo' "$GITHUB_STEP_SUMMARY"
}

@test "--workflow troca o nome no comando do resumo" {
  { corrida; rodando a.cy.ts 1 1; falhou 1 'x'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo --workflow reexecutar.yml
  [ "$status" -eq 0 ]
  grep -q 'gh workflow run reexecutar.yml' "$GITHUB_STEP_SUMMARY"
  ! grep -q 'e2e-parcial.yml' "$GITHUB_STEP_SUMMARY"
}

@test "sem GITHUB_STEP_SUMMARY escreve so o arquivo e nao falha" {
  unset GITHUB_STEP_SUMMARY
  { corrida; rodando a.cy.ts 1 1; passou 'x'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  [ -s "$SAIDA" ]
}

@test "a saida relativa nasce dentro da raiz, com o diretorio criado" {
  { corrida; rodando a.cy.ts 1 1; passou 'x'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --clientes campo
  [ "$status" -eq 0 ]
  [ -s "$RAIZ/diagnostico-e2e/specs-nao-executadas.txt" ]
}

@test "argumento sem valor e argumento desconhecido recusam com 2" {
  run sh "$SCRIPT" --log
  [ "$status" -eq 2 ]
  run sh "$SCRIPT" --x
  [ "$status" -eq 2 ]
}

@test "cliente sem diretorio de specs e dito, nao inventado" {
  { corrida; rodando a.cy.ts 1 1; passou 'x'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo,outro
  [ "$status" -eq 0 ]
  grep -q 'outro: diretorio outro/cypress/e2e ausente' "$SAIDA"
}

# Parametros proprios do pacote.

@test "--clientes padrao e '.': um unico cliente na raiz" {
  mkdir -p "$RAIZ/cypress/e2e"; : > "$RAIZ/cypress/e2e/unico.cy.ts"; : > "$RAIZ/cypress/e2e/outro.cy.ts"
  { corrida; rodando unico.cy.ts 1 2; passou 'um'; rodando outro.cy.ts 2 2; falhou 1 'dois'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA"
  [ "$status" -eq 0 ]
  grep -qx '. executadas: 1' "$SAIDA"
  grep -qx '. falhou: outro.cy.ts' "$SAIDA"
  grep -qx '. reexecutar: outro.cy.ts' "$SAIDA"
  ! grep -q '^campo' "$SAIDA"
}

@test "--specs e --extensao diferentes dos padroes" {
  mkdir -p "$RAIZ/campo/tests/e2e"; : > "$RAIZ/campo/tests/e2e/um.spec.js"; : > "$RAIZ/campo/tests/e2e/dois.spec.js"
  : > "$RAIZ/campo/tests/e2e/ignorado.cy.ts"
  { corrida; rodando um.spec.js 1 2; passou 'a'; rodando dois.spec.js 2 2; pendente 'b'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo --specs tests/e2e --extensao .spec.js
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -qx 'campo nao executadas: dois.spec.js' "$SAIDA"
  ! grep -q 'ignorado' "$SAIDA"
  grep -q 'relativas a `tests/e2e/`' "$GITHUB_STEP_SUMMARY"
}

@test "--specs sem o diretorio no cliente e dito com o subdiretorio pedido" {
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo --specs tests/e2e
  [ "$status" -eq 0 ]
  grep -q 'campo: diretorio campo/tests/e2e ausente' "$SAIDA"
}

@test "spec com espaco no nome e um unico arquivo nas quatro linhas do contrato (QA-SK-2)" {
  : > "$RAIZ/campo/cypress/e2e/com espaco.cy.ts"
  { corrida; rodando 'com espaco.cy.ts' 1 2; falhou 1 'um'; rodando a.cy.ts 2 2; pendente 'dois'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: com espaco.cy.ts' "$SAIDA"
  grep -qx 'campo nao executadas: a.cy.ts,b.cy.ts,sub/c.cy.ts' "$SAIDA"
  grep -qx 'campo reexecutar: com espaco.cy.ts,a.cy.ts,b.cy.ts,sub/c.cy.ts' "$SAIDA"
}

@test "GITHUB_STEP_SUMMARY em diretorio inexistente nao derruba o script: aviso em stderr, arquivo escrito e exit 0 (QA-SK-3)" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/nao-existe/resumo.md"
  { corrida; rodando a.cy.ts 1 1; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts' "$SAIDA"
  [[ "$output" == *"AVISO: nao foi possivel escrever em GITHUB_STEP_SUMMARY"* ]]
  [ ! -e "$GITHUB_STEP_SUMMARY" ]
}

# Cenarios do QA do projeto de origem (qa-specs-nao-executadas.bats), aceitos la.

qa_arvore() {
  rm -rf "$RAIZ"; mkdir -p "$RAIZ/campo/cypress/e2e" "$RAIZ/comando/cypress/e2e"
  for s in a sub-a saude; do : > "$RAIZ/campo/cypress/e2e/$s.cy.ts"; done
  for s in saude x; do : > "$RAIZ/comando/cypress/e2e/$s.cy.ts"; done
  unset GITHUB_STEP_SUMMARY
}

@test "QA: mesmo nome nos dois clientes: cada corrida classifica so o seu cliente" {
  qa_arvore
  {
    corrida; rodando saude.cy.ts 1 3; passou 'um'; rodando a.cy.ts 2 3; passou 'dois'
    rodando sub-a.cy.ts 3 3; passou 'tres'
    corrida; rodando saude.cy.ts 1 2; falhou 1 'um'; rodando x.cy.ts 2 2; pendente 'dois'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 3' "$SAIDA"
  grep -qx 'campo reexecutar: nenhuma' "$SAIDA"
  grep -qx 'comando falhou: saude.cy.ts' "$SAIDA"
  grep -qx 'comando nao executadas: x.cy.ts' "$SAIDA"
}

@test "QA: nome que e sufixo de outro nao herda o estado dele (a.cy.ts falhou, sub-a.cy.ts passou)" {
  qa_arvore
  { corrida; rodando a.cy.ts 1 2; falhou 1 'um'; rodando sub-a.cy.ts 2 2; passou 'dois'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts' "$SAIDA"
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -qx 'campo nao executadas: saude.cy.ts' "$SAIDA"
}

@test "QA: spec em subpasta impressa com o caminho relativo casa pelo caminho, e a de mesmo nome na raiz nao a herda" {
  qa_arvore
  mkdir -p "$RAIZ/campo/cypress/e2e/sub"; : > "$RAIZ/campo/cypress/e2e/sub/a.cy.ts"
  { corrida; rodando sub/a.cy.ts 1 2; falhou 1 'um'; rodando a.cy.ts 2 2; passou 'dois'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: sub/a.cy.ts' "$SAIDA"
  grep -qx 'campo executadas: 1' "$SAIDA"
}

@test "QA: LIMITE CONHECIDO: spec em subpasta com o mesmo nome de uma da raiz herda o estado da raiz quando so a raiz aparece no log" {
  qa_arvore
  mkdir -p "$RAIZ/campo/cypress/e2e/sub"; : > "$RAIZ/campo/cypress/e2e/sub/a.cy.ts"
  { corrida; rodando a.cy.ts 1 1; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts,sub/a.cy.ts' "$SAIDA"
}

@test "QA: log so com (Run Starting), sem nenhum Running: tudo nao executado, sem dizer que o log falta" {
  qa_arvore
  { corrida; printf '  Cypress:        15.18.1\n'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  ! grep -q 'log ausente ou vazio' "$SAIDA"
  grep -qx 'campo executadas: 0' "$SAIDA"
  grep -qx 'campo reexecutar: a.cy.ts,saude.cy.ts,sub-a.cy.ts' "$SAIDA"
  grep -qx 'comando reexecutar: saude.cy.ts,x.cy.ts' "$SAIDA"
}

@test "QA: log existente e vazio e tratado como ausente" {
  qa_arvore
  : > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  grep -q 'log ausente ou vazio' "$SAIDA"
}

@test "QA: ordem dos clientes invertida em --clientes atribui a primeira corrida ao primeiro nome dado" {
  qa_arvore
  { corrida; rodando saude.cy.ts 1 1; falhou 1 'um'; corrida; rodando a.cy.ts 1 1; passou 'dois'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes comando,campo
  [ "$status" -eq 0 ]
  grep -qx 'comando falhou: saude.cy.ts' "$SAIDA"
  grep -qx 'campo falhou: nenhuma' "$SAIDA"
  grep -qx 'campo executadas: 1' "$SAIDA"
  [ "$(grep -n '^comando executadas' "$SAIDA" | cut -d: -f1)" -lt "$(grep -n '^campo executadas' "$SAIDA" | cut -d: -f1)" ]
}

@test "QA: corrida unica do segundo cliente so e lida certo quando --clientes diz que a primeira corrida e dele" {
  qa_arvore
  { corrida; rodando saude.cy.ts 1 1; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes comando
  [ "$status" -eq 0 ]
  grep -qx 'comando falhou: saude.cy.ts' "$SAIDA"
  ! grep -q '^campo' "$SAIDA"
}

@test "QA: Running: truncada, sem (k of N), nunca vira executada: a spec fica em reexecutar" {
  qa_arvore
  { corrida; rodando a.cy.ts 1 2; passou 'um'; printf '  Running:  saude.cy.ts\n'; passou 'dois'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep '^campo reexecutar:' "$SAIDA" | grep -q 'saude.cy.ts'
  ! grep -qx 'campo executadas: 2' "$SAIDA"
}

@test "QA: Running: de spec que nao existe no disco e ignorada sem erro, e as do disco ficam como nao executadas" {
  qa_arvore
  { corrida; rodando fantasma.cy.ts 1 1; passou 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  ! grep -q 'fantasma' "$SAIDA"
  grep -qx 'campo executadas: 0' "$SAIDA"
  grep -qx 'campo nao executadas: a.cy.ts,saude.cy.ts,sub-a.cy.ts' "$SAIDA"
}

@test "QA: mais corridas no log do que clientes: a terceira e ignorada, nao atribuida a ninguem" {
  qa_arvore
  {
    corrida; rodando a.cy.ts 1 1; passou 'um'
    corrida; rodando x.cy.ts 1 1; passou 'dois'
    corrida; rodando saude.cy.ts 1 1; falhou 1 'tres'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" $DOIS
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: nenhuma' "$SAIDA"
  grep -qx 'comando falhou: nenhuma' "$SAIDA"
  grep -qx 'comando executadas: 1' "$SAIDA"
}

@test "QA: falha so no resumo final do Cypress (N) sob o ultimo Running:) ainda conta como falhou" {
  qa_arvore
  {
    corrida; rodando a.cy.ts 1 1; passou 'um'
    printf '\n  1 failing\n\n  1) suite\n       caso:\n     AssertionError\n'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts' "$SAIDA"
}

@test "QA: a tabela final do Cypress (por spec) nao e lida como teste executado" {
  qa_arvore
  { corrida; rodando a.cy.ts 1 1; printf '  \342\224\202 \342\234\224  a.cy.ts   00:01   1   1   -   -   - \342\224\202\n'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 0' "$SAIDA"
  grep '^campo nao executadas:' "$SAIDA" | grep -q 'a.cy.ts'
}

@test "roda sob dash" {
  command -v dash >/dev/null 2>&1 || skip "dash nao instalado"
  { corrida; rodando a.cy.ts 1 1; passou 'x'; } > "$LOG"
  run dash "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
}
