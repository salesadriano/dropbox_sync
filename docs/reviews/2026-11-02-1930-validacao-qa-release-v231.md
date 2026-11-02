# Validacao QA (porte M) - release-v231

Papel: QA Expert. Data: 2026-11-02. Linhas: principal (`chore/release-v231`) e legada (`chore/release-v231-bash42`).

## Escopo
1. Teto de memoria do lint em `commands/download.sh`.
2. QA-B42-03: sonda `_localidade_disponivel` em `tests/support/localidade.sh` (linha legada).
3. Versao 2.3.1 / 2.3.1-bash42 e notas de release (consistencia).

## Itens verificados
1. Lint: `sh scripts/lint.sh commands/download.sh` na linha principal saiu 0. O diff e so o comentario do segundo `. sync.sh` (linha 273) para `source=/dev/null`. O primeiro source (linha 53) continua seguido, entao os simbolos de `commands/sync.sh` seguem cobertos no arquivo; o lint verde, sem SC2154, confirma que nenhum simbolo perdeu cobertura. Efeito colateral aceito: o segundo source nao e seguido, e o conteudo e o mesmo arquivo.
2. Sonda (legada): o corpo compartilhado e identico aos 8 corpos removidos com `${BASH:-bash}`. O 9o corpo removido (`diagnostico_test.sh`) usava `"$BASH_ABSOLUTO"` no lugar de `${BASH:-bash}`: ver achado M-1. Nove copias removidas, 9 arquivos passam a fazer source (retencao_test, filtro_test, qa_filtros_banda_b4, reter, sync, qa_retencao_b6, diagnostico, qa_debug_transferencias_b12, filtros). `progresso_linha_test.sh` nao foi tocado e mantem sonda propria (conta caracteres, nao dobra caixa), como previsto. `bash scripts/verificar-remocao-de-casos.sh`: 2909 -> 2909 casos, nenhuma reducao. Os diffs das tres suites QA (qa_debug_transferencias_b12, qa_filtros_banda_b4, qa_retencao_b6) contem apenas a remocao da funcao e dos comentarios dela e a linha de source (mais a movimentacao do bloco de source, sem tocar em assert).
3. Versao: `lib/cli.sh`, `install.sh` e README em 2.3.1-bash42 na legada (principal confere em 2.3.1, ver diff acima); notas `docs/releases/v2.3.1.md` e `v2.3.1-bash42.md` coerentes entre si e com a mudanca (nove copias = nove removidas). Sem inconsistencia.

## Achados
- Menor M-1: `diagnostico_test.sh` usava `$BASH_ABSOLUTO` na sonda; a compartilhada usa `${BASH:-bash}`. Equivalentes sob o runner (que executa com bash), sem risco observado; registrar que a mudanca nao e estritamente identica nesse arquivo.
- Menor M-2: na linha principal o lint do `commands/download.sh` fica com um source nao seguido; se o segundo source passar a usar simbolos que so ele define, o lint nao detecta. Hoje e o mesmo arquivo.
- Nenhum achado bloqueante ou maior.

## Limites
Nao reexecutei testes (o Tech Lead ja executou os 9 arquivos, diagnostico na principal e o CentOS 7); limitei-me a leitura de diff, verificar-remocao e lint.

## Veredito: Aprovado

sha256 das tres suites QA alteradas (linha legada):
- tests/integracao/qa_debug_transferencias_b12_test.sh: 4021027bd57c99cb1ab920a48650313f5bc0e4cd205b841856dc00a31c17ef4c
- tests/integracao/qa_filtros_banda_b4_test.sh: cfb707a2c555024fe121850e71d0c62729c805d5f4aec89147dc9017ae51d589
- tests/integracao/qa_retencao_b6_test.sh: 6a9d2e1a662884bf26b90ce067dc4ff0a0cba9511289187f0e55bf37563417a6
