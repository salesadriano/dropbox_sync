---
date: 2026-10-18
hora: "2045"
domain: http / transfer / sync / testes
porte: M
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-18-2045-registro-robustez-de-rede-p2.md"
---

# robustez-de-rede-p2

## Prompt 1 — 2026-10-18 2045

> faça o merge e siga para a próxima etapa

**Intenção:** mesclar a PR #35 (fase P1) e abrir a fase 2 do plano em fases (`2026-10-18-1745-melhorias-em-fases`): robustez de rede.

**Inferências e decisões do solicitante:**
- **Merge da PR #35:** o classificador de permissões bloqueou o `gh pr merge` do agent, e o solicitante fez o merge (`38b6148`, 2026-10-19T01:45Z). O repositório não tem pipeline; o solicitante liberou o merge sabendo disso, com a suíte completa local verde em `6895a9c` (decisão sobre pipeline indisponível, regra do Ciclo do developer, passo 10).
- **Limpeza pós-merge:** `limpar-worktrees.sh --executar` removeu o worktree e a branch local da P1. A branch remota `bugfix/integridade-de-dados-p1` foi mantida.
- **Timeouts:** `connect-timeout` de 15 s; aborta abaixo de 1 KB/s por 60 s seguidos; os dois ajustáveis por variável de ambiente.
- **Retentativas:** 5 tentativas, recuo exponencial com jitter a partir de 1 s e teto de 60 s por espera. O `Retry-After` do servidor prevalece, limitado a 300 s (fecha a DIV-22). O número de tentativas é configurável (RNF-07) e o RF-09 é emendado.
- **Upload retomável:** só dentro da execução e só para arquivo regular, relendo a partir do `correct_offset` informado pela Dropbox. A entrada padrão segue sem retomada; retomar entre execuções continua no F-03.
- **Falhas por item no sync:** uma linha por item no stderr (`falha <caminho>: <classe> <resumo>`), sem mudar o stdout; no `--json`, um campo `falhas` com caminho e classe. Nunca inclui token nem corpo bruto.
- **Escopo complementar da fase 2 (backlog da P1):** F-28 (`download` sem destino), F-30 (runner sem parada no primeiro erro), F-31 (área `dbx-sync` após sinal), QA-05 (mapa de módulos) e o teste de `hash_test` que conta o `/tmp` compartilhado.
- **Porte M:** toca política de erro e retentativa, contrato de saída da CLI e configuração por ambiente; sem mudança de arquitetura. Branch `feature/robustez-de-rede-p2`, a partir de `develop` (`38b6148`); nenhum PR aberto no início.
- **Pontos técnicos deixados em aberto pelo Business Analyst**, decididos pelo Tech Lead em `2026-10-18-2045-detalhes-tecnicos-rede-p2`: as 5 tentativas contam a primeira; a retomada consome uma tentativa; arquivo que muda de tamanho é recusado; `Retry-After` como data HTTP vale como inválido; o F-28 é defeito contra o contrato do próprio comando; `transfer_test` recebe `TMPDIR` privado.
- **Emendas do Tech Lead após a implementação:** o RF-59(b) mantém `falhas` como contagem e acrescenta os pares `falha_caminho`/`falha_classe`; o `correct_offset` do RF-58 fica limitado ao que já foi enviado; a documentação ao usuário passa a refletir 5 tentativas.
- **QA:** reprovou nos ciclos 1 e 2, com dois achados de segurança de vazamento de token (QA-P2-02 e QA-P2-04), e aprovou no ciclo 3. Não houve escalonamento.
- **Regra 12:** o solicitante **aprovou** a suíte do QA da fase 2 (45 casos) em `2026-10-18-2045-aceite-testes-qa-p2`.
