---
date: 2026-10-23
hora: "0900"
domain: teste de disponibilidade (internet, servico Dropbox e credencial) com inicio do config
porte: M
status: aberto
instancia: myPCWin/Desenvolvedor Hydros
registro_de_entrega: "docs/reviews/2026-10-23-0900-registro-teste-de-disponibilidade.md"
---

# teste-de-disponibilidade

## Prompt 1 — 2026-10-23

> implemente teste de disponibilidade do acesso a internet e de acesso a o dropbox, seja a disponibilidade do serviços, sejam as credenciais adequadas, caso não hajam credenciais ou as credenciais sejam inválidas inicie o config

**Intencao:** antes de operar, o `dbx` distingue tres causas de falha (sem internet, servico Dropbox indisponivel ou inacessivel, credencial ausente ou invalida) e, na ultima, conduz o operador ao `dbx config`.

**Estado atual levantado pelo Tech Lead (develop @ `877b708`):**
- `dbx diagnostico` (`commands/diagnostico.sh`) ja checa credencial, renovacao do token, `check/user`, escopos e espaco, mas e so leitura por contrato (nunca aplica remedio) e nao separa "sem internet" de "Dropbox inacessivel".
- Comandos de nivel `credencial` (`bin/dbx`) falham com codigo 3 (credencial ausente ou inutilizavel) ou 5 (autenticacao) e sugerem `dbx config`; nenhum inicia o config.
- `dbx config` le da entrada padrao e pergunta pela saida de erro; funciona sem terminal.

**Decisoes do solicitante (AskUserQuestion, 2026-10-23):**
- **Onde roda:** "Automatico + comando (Recomendado)" — todo comando que exige credencial testa antes de agir, sem chamada extra quando tudo esta bem (aproveita a renovacao do token), e ha um comando novo explicito (ex.: `dbx testar`, alias `check`); o `diagnostico` continua so leitura.
- **Iniciar config:** "Perguntar no terminal (Recomendado)" — com terminal interativo pergunta `Configurar agora? [s/N]` e, se sim, roda `dbx config` (ou `--substituir`); sem terminal nao inicia e sai com o codigo atual e o remedio.
- **Apos config:** "Continuar o comando (Recomendado)" — configurado com sucesso, o comando original segue com a credencial nova.
- **Internet:** "Sonda neutra configuravel (Recomendado)" — falhando a conexao ao Dropbox, testa um endereco neutro (padrao ex.: `https://www.gstatic.com/generate_204`, trocavel por `DBX_TESTE_INTERNET_URL`, vazio desliga); responde -> "Dropbox inacessivel"; nao responde -> "sem acesso a internet"; 5xx/503 da API -> "servico Dropbox indisponivel".

**Porte:** M. `scripts/porte.sh` nao existe no projeto. Toca credencial, despacho da CLI (`bin/dbx`), classificacao de erro de rede e um comando novo (gatilhos de M); nao altera arquitetura nem a integracao externa (os mesmos endpoints, mais uma sonda opcional).

**Entrada:** branch principal `develop` @ `877b708`; PR aberta: #57 (`develop` -> `master`, promocao, sem impacto no escopo: seguir sem dependencia); worktree `feature/teste-de-disponibilidade` em `/home/sales/dropbox_api.worktrees/feature-teste-de-disponibilidade`; `alteracoes-externas.sh --detectar` no checkout principal exit 0 (o bloco do `CLAUDE.md` e do plugin, alinhado no inicio da sessao); `--inicial` no worktree exit 0.

**Especificacao (Business Analyst):** secao 5.20 do escopo (v1.28), `RF-148` a `RF-155`, `TC-DSP-01` a `TC-DSP-64`, `F-50`.

**Divergencias da especificacao:** `DIV-307` a `DIV-319` resolvidas pelo Tech Lead em 2026-10-23 na recomendacao do BA, exceto `DIV-309` decidida B (o `testar` tambem oferece o `config`, porque o pedido literal manda inicia-lo); propagada a `RF-148(h)` e `TC-DSP-09`, `TC-DSP-10`, `TC-DSP-10b`. Memoria `2026-10-23-0900-teste-de-disponibilidade`.

**Intervencao humana (regra 48, AskUserQuestion, 2026-10-23):** arquivo nao rastreado `docs/prompts/2026-08-19_004_publicacao-google-play-console.md` no worktree, nao criado pelos agents: "Autorizo apagar" (aceite `2026-10-23-0900-aceite-remocao-arquivo-alheio`); removido.

**DIV-327 (AskUserQuestion, 2026-10-23):** `space`, `info` e `list` saem 2 em `invalid_grant`: "Corrigir agora (Recomendado)" — sai 5 e recebe a oferta do `config`.

## Prompt 2 — 2026-10-23

> a ultima sessão foi encerrada

**Intencao:** retomar esta demanda, interrompida com a sessao anterior (sem commit), do ponto em que parou.

**Estado na retomada (Tech Lead):** tarefas 1 e 2 entregues pelo Senior Developer no worktree, sem commit; DIV-327 decidida "Corrigir agora", ainda nao implementada (`lib/cmd.sh` intacto); DIV-328 e DIV-329 pendentes de decisao; lint de `bin/dbx` e de `tests/integracao/composicao_test.sh` sem resultado lido; gates de conformidade e QA, documentacao, commit e PR por fazer. `alteracoes-externas.sh --detectar` no worktree exit 0.

**Decisoes do solicitante (AskUserQuestion, 2026-10-23, retomada):**
- **DIV-328:** "Qualquer resposta (Recomendado)" — qualquer resposta HTTP do Dropbox (inclusive 5xx e 429) prova a internet; 5xx relata "servico Dropbox indisponivel".
- **DIV-329:** "Estender a todos (Recomendado)" — causa nomeada tambem em `DBX_AUTH_MOTIVO` (comandos via `dbx_auth_preparar`) e na falha de rede no meio da execucao (RF-151(e)).

**Lint na retomada:** `tests/integracao/composicao_test.sh` limpo (rc 0); `bin/dbx` interrompido (saida 1, teto de 12288 MB?) no worktree; linha de base na `develop` em execucao.
- **DIV-330 (AskUserQuestion, 2026-10-23):** "Config sob a trava (Recomendado)" — com `invalid_grant` em `sync`/`verificar`, o `config` roda sob a trava do par do proprio comando; `TC-DSP-54` reescrito, `RF-69(b)` inalterado, sem mudanca de codigo.
- **Gate de conformidade, rodada 1 (2026-10-23):** REPROVADO (5 importantes, 6 menores); devolvido ao Senior Developer em tarefas 5, 5a, 5b e 5c (a tarefa 5 parou no limite de turnos: teto de 70 chamadas no briefing, acima do limite de 40).
- **DIV-331 (AskUserQuestion, 2026-10-23):** "Esperar o resultado (Recomendado)" — auxiliar que perde a reserva da sonda espera o resultado do vencedor por no maximo o tempo limite da sonda; sem resultado, causa `indeterminada`; codigo inalterado.
- **Gate de conformidade:** rodadas 2 a 4 REPROVADAS (N1, R1 e R4a bloqueantes, todos de vazamento ou de stdout), rodada 5 APROVADA em 2026-10-23; R3, R4b e R5a ficam como recomendacao.
- **QA:** ciclo 1 REPROVADO (QA-DSP-01, auditoria `json` em `testar_test.sh`), ciclo 2 APROVADO.
- **Aceite da suite do QA (regra 12, AskUserQuestion, 2026-10-23):** "Aprovo (Recomendado)" — `tests/integracao/qa_disponibilidade_b11_test.sh`, 33 casos, sha256 `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`.
