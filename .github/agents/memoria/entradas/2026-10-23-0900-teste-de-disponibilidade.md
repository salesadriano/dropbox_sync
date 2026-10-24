---
id: 2026-10-23-0900-teste-de-disponibilidade
tipo: decisao
escopo: projeto
titulo: Teste de disponibilidade (internet, servico Dropbox, credencial) no comando testar e automatico, com oferta do config no terminal
data: 2026-10-23
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-23_0900_teste-de-disponibilidade.md
---

Pedido do solicitante em 2026-10-23: testar a disponibilidade da internet, do servico Dropbox e da credencial; sem credencial ou com credencial invalida, iniciar o `config`.

Decisoes do solicitante (AskUserQuestion, 2026-10-23):
- **Onde roda:** "Automatico + comando (Recomendado)". Checagem automatica nos comandos de nivel `credencial`, sem chamada extra no caminho feliz, e comando explicito `dbx testar` (alias `check`); o `diagnostico` continua so leitura.
- **Iniciar config:** "Perguntar no terminal (Recomendado)". `[s/N]` com terminal interativo; sem terminal, codigo e remedio de hoje.
- **Apos config:** "Continuar o comando (Recomendado)".
- **Internet:** "Sonda neutra configuravel (Recomendado)". `DBX_TESTE_INTERNET_URL`, vazia desliga.

Divergencias da especificacao (escopo v1.28, secao 5.20, `RF-148` a `RF-155`): `DIV-307` a `DIV-319` resolvidas pelo Tech Lead em 2026-10-23 na recomendacao do BA, exceto `DIV-309` (B): o `testar` tambem oferece o `config`, sob o mesmo portao, porque o pedido literal manda inicia-lo quando a credencial falta ou e invalida; configurado, refaz as checagens uma vez.

Principios do Tech Lead:
- **Sem terminal, nada muda:** o portao fechado nunca le stdin e mantem codigo e mensagem de hoje (cron e pipe nao travam).
- **A sonda nunca leva segredo** e so roda depois de uma falha de conexao ao Dropbox (ou no `testar`).
- **Oferta so antes de qualquer efeito:** o gancho fica na primeira obtencao de token.

Decisoes do solicitante durante a implementacao (registro de entrega, tarefas 2 a 3; prompt log):
- **DIV-327:** corrigir; falha da renovacao nos comandos de consulta sai pela classe do token (5) e recebe a oferta de config.
- **DIV-328:** manter; qualquer resposta HTTP do Dropbox prova a internet.
- **DIV-329:** estender; causa nomeada tambem em `DBX_AUTH_MOTIVO` e na falha no meio da execucao (RF-151(e)).
- **DIV-330:** opcao C; `config` sob a trava do par; com `invalid_grant` em `sync`/`verificar`, a unica trava viva durante o `config` e a do proprio comando (RF-69(b)); `config` nao adquire trava. `TC-DSP-54` reescrito; sem mudanca de codigo.
- **DIV-331:** opcao A, "Esperar o resultado": quem perde a reserva da sonda espera o resultado do vencedor por no maximo `DBX_DISP_ESPERA_MS` (padrao 12000: o max-time de 10 s da sonda mais 2000 ms de folga, achado N5 da conformidade); sem resultado, causa `indeterminada`.

Aceite da suite do QA: `tests/integracao/qa_disponibilidade_b11_test.sh`, 33 casos, sha256 `ffe3ef0ea7f4cf69d96465d2960828b30597b9735ec88412ca2231e4a3db96ec`. Veredito do QA: ciclo 1 reprovado (QA-DSP-01, gate `json`, massa por `$(printf ...)` em `testar_test.sh`); ciclo 2 aprovado apos a correcao. Aceite do solicitante pela regra 12: concedido em 2026-10-23 ("Aprovo").
