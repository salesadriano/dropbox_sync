#!/usr/bin/env bats
# Suite independente do QA Expert para specs-nao-executadas.sh.
# Complementa specs-nao-executadas.bats: ANSI na linha de falha e no (Run Starting); mesmo nome em subpasta nos
# dois clientes; cliente sem diretorio no meio da lista; virgula sobrando; --saida absoluto; GITHUB_STEP_SUMMARY
# em diretorio inexistente; CRLF; nome de spec com espaco.
# Validacao: docs/reviews/2026-10-15-0914-skills-dos-mods-validacao-qa.md

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../specs-nao-executadas.sh"
  RAIZ="$BATS_TEST_TMPDIR/raiz"
  mkdir -p "$RAIZ/campo/cypress/e2e/sub" "$RAIZ/comando/cypress/e2e/sub"
  for s in a b sub/c; do : > "$RAIZ/campo/cypress/e2e/$s.cy.ts"; done
  for s in x sub/c; do : > "$RAIZ/comando/cypress/e2e/$s.cy.ts"; done
  LOG="$BATS_TEST_TMPDIR/testes.log"
  SAIDA="$BATS_TEST_TMPDIR/saida.txt"
  unset GITHUB_STEP_SUMMARY RUNNER_TEMP
}

corrida() { printf '\n  (Run Starting)\n\n'; }
rodando() { printf '  Running:  %s  (%s of %s)\n' "$1" "$2" "$3"; }
passou() { printf '    \342\234\223 %s (12ms)\n' "$1"; }
falhou() { printf '    %s) %s\n' "$1" "$2"; }
pendente() { printf '    - %s\n' "$1"; }

@test "QA: ANSI em (Run Starting), na linha de falha e na pendente nao atrapalha a classificacao" {
  {
    printf '\n  \033[1m(Run Starting)\033[22m\n\n'
    printf '  Running:  \033[90ma.cy.ts\033[39m  \033[90m(1 of 3)\033[39m\n'; printf '    \033[31m1) \033[39mum\n'
    rodando b.cy.ts 2 3; printf '    \033[36m- dois\033[39m\n'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts' "$SAIDA"
  grep -qx 'campo nao executadas: b.cy.ts,sub/c.cy.ts' "$SAIDA"
}

@test "QA: spec de mesmo caminho em subpasta nos dois clientes: cada corrida classifica so a sua" {
  {
    corrida; rodando sub/c.cy.ts 1 1; passou 'um'
    corrida; rodando sub/c.cy.ts 1 1; falhou 1 'um'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo,comando
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -qx 'campo falhou: nenhuma' "$SAIDA"
  grep -qx 'comando falhou: sub/c.cy.ts' "$SAIDA"
  grep -qx 'comando nao executadas: x.cy.ts' "$SAIDA"
}

@test "QA: LIMITE: cliente sem diretorio no meio de --clientes consome uma corrida do log (a seguinte vai para o proximo)" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; corrida; rodando x.cy.ts 1 1; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo,fantasma,comando
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -q 'fantasma: diretorio fantasma/cypress/e2e ausente' "$SAIDA"
  grep -qx 'comando falhou: nenhuma' "$SAIDA"
  grep -qx 'comando nao executadas: sub/c.cy.ts,x.cy.ts' "$SAIDA"
}

@test "QA: virgula sobrando e espacos em --clientes: itens vazios sao pulados sem consumir corrida" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; corrida; rodando x.cy.ts 1 1; passou 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes ',campo,,comando,'
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 1' "$SAIDA"
  grep -qx 'comando executadas: 1' "$SAIDA"
  [ "$(grep -cE '^[a-z]+ executadas:' "$SAIDA")" -eq 2 ]
}

@test "QA: --saida absoluto fora da raiz e criado la, com o diretorio" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$BATS_TEST_TMPDIR/fora/sub/x.txt" --clientes campo
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/fora/sub/x.txt" ]
  [ ! -e "$RAIZ/diagnostico-e2e" ]
}

@test "QA: GITHUB_STEP_SUMMARY apontando para diretorio inexistente nao derruba o passo: arquivo de saida escrito e exit 0" {
  export GITHUB_STEP_SUMMARY="$BATS_TEST_TMPDIR/nao-existe/resumo.md"
  { corrida; rodando a.cy.ts 1 1; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: a.cy.ts' "$SAIDA"
}

@test "QA: --saida em caminho sem permissao de escrita: exit diferente de 0 e nenhuma linha de contrato impressa como se fosse ok" {
  [ "$(id -u)" -ne 0 ] || skip "root ignora permissoes"
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 555 "$BATS_TEST_TMPDIR/ro"
  { corrida; rodando a.cy.ts 1 1; passou 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$BATS_TEST_TMPDIR/ro/x.txt" --clientes campo
  chmod 755 "$BATS_TEST_TMPDIR/ro"
  [ "$status" -ne 0 ]
  [[ "$output" != *"campo executadas: 1"* ]]
}

@test "QA: LIMITE: log com CRLF nao casa 'Running:' e tudo fica como nao executado (sem erro)" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; } | sed 's/$/\r/' > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo executadas: 0' "$SAIDA"
  grep -qx 'campo nao executadas: a.cy.ts,b.cy.ts,sub/c.cy.ts' "$SAIDA"
}

@test "QA: nome de spec com espaco no disco e no log e tratado como um unico arquivo" {
  : > "$RAIZ/campo/cypress/e2e/com espaco.cy.ts"
  { corrida; rodando 'com espaco.cy.ts' 1 1; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  # ACHADO QA-SK (aberto ate correcao): o nome e quebrado em "com" e "espaco.cy.ts" pelo for sem aspas.
  grep -qx 'campo falhou: com espaco.cy.ts' "$SAIDA"
  ! grep -qE '^campo (nao executadas|reexecutar): .*(^|,)com(,|$)' "$SAIDA"
}

@test "QA: LIMITE: spec impressa com ./ na frente no log (Running: ./a.cy.ts) nao casa e fica como nao executada" {
  { corrida; printf '  Running:  ./a.cy.ts  (1 of 1)\n'; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: nenhuma' "$SAIDA"
  grep '^campo nao executadas:' "$SAIDA" | grep -q 'a.cy.ts'
}

@test "QA: log so com a falha no resumo final, sem check nem pendente, na segunda corrida: so o segundo cliente e marcado" {
  {
    corrida; rodando a.cy.ts 1 1; passou 'um'
    corrida; rodando x.cy.ts 1 1; printf '\n  1 failing\n\n  1) x\n'
  } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo,comando
  [ "$status" -eq 0 ]
  grep -qx 'campo falhou: nenhuma' "$SAIDA"
  grep -qx 'comando falhou: x.cy.ts' "$SAIDA"
}

@test "QA: SEGURANCA: nome de spec com \cifrao-parenteses no log nao e expandido" {
  MARCA="$BATS_TEST_TMPDIR/marca"
  { corrida; printf '  Running:  $(touch %s).cy.ts  (1 of 1)\n' "$MARCA"; falhou 1 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  [ ! -e "$MARCA" ]
}

@test "QA: o contrato de saida tem exatamente quatro linhas por cliente, na ordem, e as linhas # so no inicio" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; corrida; rodando x.cy.ts 1 1; passou 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo,comando
  [ "$status" -eq 0 ]
  corpo=$(grep -v '^#' "$SAIDA" | sed -E 's/^([a-z]+) (executadas|falhou|nao executadas|reexecutar):.*/\1 \2/' | tr '\n' '|')
  [ "$corpo" = "campo executadas|campo falhou|campo nao executadas|campo reexecutar|comando executadas|comando falhou|comando nao executadas|comando reexecutar|" ]
  [ "$(head -n 1 "$SAIDA" | cut -c1-1)" = "#" ]
}

@test "QA: a saida no terminal e identica ao arquivo (cat no fim)" {
  { corrida; rodando a.cy.ts 1 1; passou 'um'; } > "$LOG"
  run sh "$SCRIPT" --log "$LOG" --raiz "$RAIZ" --saida "$SAIDA" --clientes campo
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$SAIDA")" ]
}
