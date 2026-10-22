---
date: 2026-10-21
hora: "1735"
domain: perfis nomeados de credencial
porte: G
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-21-1735-registro-perfis-b8.md"
---

# backlog-fase-8-perfis

## Prompt 1 — 2026-10-21 (depois do merge da PR #49)

> gh pr merge 49 --merge

**Intenção:** o solicitante mesclou a PR #49, que fecha a fase 7b (F-14). O trabalho segue a instrução "analise e implemente os itens no backlog", agora na fase 8 do plano (`2026-10-19-1023-plano-do-backlog`): F-18, perfis nomeados de credencial. A fase reabre a `DP-05`, em que o solicitante havia fixado "uma conta só, sem noção de perfil".

**Decisões do solicitante (AskUserQuestion, 2026-10-21), todas na opção recomendada:**
- **Seleção:** "Opção + variável (Recomendado)". `--perfil NOME` (alias `--profile`) em todos os comandos e `DBX_PERFIL` no ambiente; a opção vence a variável. A variável carrega só o nome, nunca segredo, e a `DP-11` continua valendo.
- **Compatibilidade:** "Atual vira o padrão (Recomendado)". O `credencial.json` atual segue como perfil `padrao`, sem mudança para quem não usa perfil; os demais ficam em `perfis/<nome>.json`, 0600.
- **Gestão:** "Listar e remover (Recomendado)". `dbx perfis` lista nomes e se a credencial está completa, sem segredo; remover é `unlink --perfil NOME`; criar é `config --perfil NOME`.
- **Nomes:** "Restrito e minúsculo (Recomendado)". `[a-z0-9_-]`, 1 a 32 caracteres, começando por letra ou dígito; fora disso, saída 2.

**Porte G:** reabre `DP-05`, altera o desenho fechado de `lib/config` (credencial, segredo) e o System Design. Branch `feature/perfis-b8`, a partir de `develop` (`dd129fb`); nenhum PR aberto.

## Prompt 2 — 2026-10-21 (detector de alterações externas)

**Decisão do solicitante (AskUserQuestion):** "Sim, registre (Recomendado)". A correção que o Tech Lead fez na entrada `2026-10-21-1735-perfis`, vinda do parecer do DBA, ficou sem registro logo depois da edição. O detector acusou o arquivo, e o solicitante confirmou que a alteração é do agent. O arquivo foi registrado com `--registrar`.

## Prompt 3 — 2026-10-21 (nova sessão)

> continue a fase 8 de perfis

**Intenção:** retomar a fase 8 no worktree `feature/perfis-b8`. Ela parou com a implementação do Senior Developer quase completa: faltam o vermelho contra a base, os mutantes das guardas, as rodadas finais, o mapa de módulos, o parecer e o handback. Faltam também a conformidade, o QA, o registro, o commit e a PR.

**Porte:** G, mantido. `scripts/porte.sh` não existe neste projeto (saída: `cannot open scripts/porte.sh`). O porte segue a classificação do Prompt 1, porque a fase reabre a `DP-05` e mexe em credencial e no System Design.

**Detector (regra 48):** `--detectar` no worktree e no checkout principal saiu sem divergências.

**Decisão do Tech Lead, DIV-255 C:** o valor de `--perfil` não é completado no autocompletar. Só a opção é completada. Com isso o `TC-CPL-04` fica intacto: o script não lê arquivo do dbx nem caminho de configuração. A `DIV-246` fica parcialmente atendida, e a completação do valor vai para o backlog como `F-45`. A alternativa de chamar `dbx perfis` no autocompletar foi descartada, porque ela lê as credenciais a cada TAB.

## Prompt 4 — 2026-10-21 (nova sessão, depois de duas quedas)

> the last session was down twice

**Intenção:** duas sessões caíram durante a fase 8. Na segunda, o Senior Developer parou no limite de 40 turnos sem handback. O trabalho estava intacto e sem commit no worktree: 18 arquivos alterados (+1329/−88) e 9 novos. As 241 casos dos testes da fase passaram.

**Decisão do solicitante (AskUserQuestion):** "Checkpoint, then resume (Recommended)". Commit WIP local `915cb52` em `feature/perfis-b8`, sem push. A retomada segue em tarefas curtas, para que nenhum subagent chegue ao teto de turnos.

**Porte:** G, mantido.

## Prompt 5 — 2026-10-21 (nova sessão, depois da correção do lint)

> retome a fase 8 dos perfis

**Intenção:** retomar a fase 8 a partir do checkpoint `915cb52`. A causa das duas quedas foi o `shellcheck` em processo único (OOM de 18 GB, journal de 2026-10-21 16:34 e 17:05), corrigida na PR #50 (`scripts/lint.sh`, memória `2026-10-21-1845-lint-sequencial`). A `develop` (`ebb0d67`) entra na branch por merge para que os gates usem `sh scripts/lint.sh`.

**Decisão do solicitante (AskUserQuestion):** "Sim, registre e siga (Recomendado)". O bloco Prompt 4 deste log e o parecer TDD parcial (`docs/reviews/2026-10-21-1735-parecer-tdd-perfis-b8.md`) foram deixados pelos agents da sessão que caiu e foram registrados com `--registrar`.

**Porte:** G, mantido (`scripts/porte.sh` continua inexistente).

**Lint da fase (Tech Lead):** `sh scripts/lint.sh` nos arquivos shell da fase, 208,94 s, exit 1: 10 achados (lib/cli.sh 3, testes 7). `bin/dbx` foi morto pelo teto de 12 GB.

**Decisão do solicitante (AskUserQuestion):** "Subir o teto do bin/dbx". Medição com 14 GB: morto em duas rodadas seguidas. Uma passagem isolada em 26 s não se repetiu. Com o WSL em 16 GB, o caminho não cabe, e a pergunta voltou ao solicitante.

**Decisão do solicitante (AskUserQuestion):** "Cortar o source dos comandos (Recomendado)", com medição antes de aplicar. Ao conferir, o carregamento de `commands/*.sh` no `bin/dbx` já tinha `source=/dev/null`. A opção recomendada não mudava nada, e o Tech Lead devia ter conferido antes de oferecê-la. A bisseção em cópia descartável apontou `lib/cli.sh`: o `_dbx_cli_carregar_config`, novo na fase, segue `json.sh` e `config.sh`, que o `bin/dbx` já segue. Com só essas duas diretivas trocadas por `source=/dev/null`, os resultados foram:
- `bin/dbx`: 4747908 KB, 29,53 s, 0 achados;
- `lib/cli.sh`: 31520 KB, 0,20 s, 0 achados. Os SC2178/SC2128 eram efeito da reanálise.

É o mesmo propósito da opção escolhida, que é cortar source redundante medindo antes, aplicado ao arquivo certo. A correção foi delegada ao Senior Developer.

## Prompt 6 — 2026-10-21 (aprovação da suíte do QA)

**Decisão do solicitante (AskUserQuestion):** "Aprovo". A suíte do QA da fase 8 é `tests/integracao/qa_perfis_b8_test.sh`, com 34 casos e sha256 `9e6617c358b02608124dfd721e711226f5c5ca3e2b47b1da7ef44515b05932d7`, na versão do ciclo 2.
