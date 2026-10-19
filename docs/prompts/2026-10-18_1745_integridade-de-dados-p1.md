---
date: 2026-10-18
hora: "1745"
domain: sync / download / http
porte: M
status: em-andamento
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-18-1745-registro-integridade-de-dados-p1.md"
---

# integridade-de-dados-p1

## Prompt 1 — 2026-10-18 1745

> @tech-lead trate os problemas apontados em /home/sales/.gemini/antigravity-ide/brain/34917df5-612d-4ede-92ca-c45742149148/analise_melhorias.md

**Intenção:** tratar as melhorias apontadas por uma análise externa do projeto. Cópia sanitizada do material de origem em [docs/sources/2026-10-18-analise-melhorias.md](../sources/2026-10-18-analise-melhorias.md) (links absolutos trocados por relativos; nenhum segredo).

**Inferências e decisões do solicitante (respostas às perguntas do Tech Lead):**
- **Regra 48:** o commit `c492085` na `develop`, sem linha `Prompt:`, foi declarado intencional; aceite em `2026-10-18-1745-aceite-commit-c492085`. O commit só altera o registro de entrega do PR #34, sem código, e não entra nesta demanda.
- **Escopo em fases**, uma demanda por bloco com branch, gates e PR próprios: (1) P1 integridade de dados, esta demanda; (2) P2 rede; (3) P3+P4 cache, SQL, skip do upload, PKCE; (4) P5 documentação e aliases. Os itens de P2 a P5 ficam fora desta demanda.
- **Padrões da fase P1, aceitos:** colisão de caixa local é recusada antes de qualquer escrita; divergência de hash no download mantém o arquivo antigo, descarta o temporário e falha; arquivos baixados seguem o umask do usuário e só a área temporária com o token fica em 077; `sync --enviar` mantém "origem vence" (DP-27), sem condicionar ao rev, mas usa sessão acima de 150 MiB e envia `client_modified`.
- **Skip do upload (fase 3):** condicionar ao `content_hash` remoto (`get_metadata`); o cache vira só otimização de hash, respeitando o RSK-23.
- **Porte M:** defeitos de alta criticidade com risco de perda ou corrupção de dados, sem mudança de arquitetura. Branch `bugfix/integridade-de-dados-p1`, a partir de `develop`; nenhum PR aberto no início.
- **Verificação prévia:** o Tech Lead conferiu as afirmações da análise contra o código antes de planejar. P1.1, P1.2, P1.4, P1.5 e P1.6 foram confirmados; P1.3 foi confirmado com correção (o `download` confere o hash, mas só depois de sobrescrever).

### Decisões complementares — 2026-10-18 (mesma rodada, após o Business Analyst apontar divergências)
- **DIV-23:** o padrão "sync --enviar sem rev" contradizia o RF-49, aprovado, que o Tech Lead não havia considerado ao formular a pergunta. O solicitante **manteve o RF-49**: a sobrescrita leva o `rev` da listagem e uma mudança remota concorrente vira falha do item, sem sobrescrever; a origem continua vencendo entre execuções (DP-27).
- **DIV-24:** o solicitante aprovou **emendar o RNF-04**: `0600` na criação da credencial e da área temporária com o token, sem alterar o umask do processo.
- **Alvo somente leitura:** o recebimento atômico passaria a substituir um arquivo local 0444, que antes falhava por acidente. O solicitante decidiu **recusar**: o arquivo fica intacto e o comando falha com diagnóstico claro.
- **Regra 12:** o solicitante **aprovou** a suíte independente do QA (`tests/integracao/qa_integridade_p1_test.sh`); o ajuste do caso do alvo 0444 exige reaprovação.
- **Regra 12 (reaprovação):** o solicitante reaprovou a suíte do QA com 23 casos, após o ajuste do alvo somente leitura.
- **Suíte completa vermelha em `d4ef8a1`:** a auditoria RNF-24 (`json_test`) reprovou. A correção veio no ciclo 5 e a regra de seleção ficou em `2026-10-18-1745-selecao-inclui-auditorias-lib`.
- **Regra 12 (2ª reaprovação):** o solicitante reaprovou a suíte do QA com 27 casos.
