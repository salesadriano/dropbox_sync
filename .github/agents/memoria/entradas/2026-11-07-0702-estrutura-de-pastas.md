---
id: 2026-11-07-0702-estrutura-de-pastas
tipo: decisao
escopo: projeto
titulo: Estrutura de pastas criada antes da transferencia nos dois destinos, pastas vazias incluidas, por ciclo no sentido remoto para local, e espelhamento apaga pasta orfa
data: 2026-11-07
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-11-07_0702_estrutura-de-pastas-antes-da-transferencia.md
---

Pedido do solicitante em 2026-11-07: em `sync`, `upload` de pasta e `download` de pasta, criar toda a estrutura de pastas no destino (local por `mkdir`, remoto pela API) antes de iniciar a transferencia dos arquivos.

Decisoes do solicitante (AskUserQuestion, 2026-11-07): pastas vazias da origem que passam no filtro sao criadas (revoga o limite "SO ARQUIVOS" de `lib/sync`); no sentido remoto para local, em ciclos, a criacao e por ciclo, antes das transferencias de cada ciclo; com `--espelhar`, pasta do destino ausente na origem e apagada; vale para `develop` e `support/bash-4.2`, uma PR por linha.

Decisao do solicitante sobre `DIV-401` (AskUserQuestion, 2026-11-07): com `--espelhar`, arquivo do destino no lugar de pasta da origem e apagado antes da fase de criacao, e a pasta nasce na mesma execucao (substitui `DIV-394` para esse caso), sob as guardas de `RF-214(c)`.

Decisao do Tech Lead: no sentido local para remoto a travessia local ja precede o ciclo 1, entao a estrutura remota inteira e criada antes do primeiro arquivo. A exclusao de pasta orfa herda as guardas do espelhamento e nao pode depender da memoria do sync (feedback de guarda sem estado). Especificacao: secao 5.26 do escopo (v1.42), `F-103`, `RF-209` a `RF-219`, `TC-ARV-01..32`, `DIV-397` a `DIV-405` (recomendacoes do BA aceitas pelo Tech Lead; `DIV-398` conferida via Context7).

## Refinamento do Tech Lead (2026-11-07, apos o mapeamento de impacto da Tarefa 2)

- A criacao da arvore remota no `--enviar`/`upload` passa para **depois** das recusas do plano do ciclo 1 (origem vazia, espaco) e ocorre uma unica vez, no primeiro ciclo que passa por elas, antes da primeira transferencia. Motivo: `qa_cache_unico_p3` mostrou que criar pasta antes da recusa da origem vazia e escrita remota numa execucao recusada (RF-41(d)). Registrado como `RF-210(g)` e `TC-ARV-05b`.
- RF-214(b), forma da exclusao antecipada: no `--enviar` o conflito `path/conflict/file` e detectado pela criacao; com `--espelhar` e as guardas de RF-214(c), o pai e listado por inteiro na mesma execucao, o arquivo sai por `delete_v2` com `parent_rev` e a pasta e resubmetida. No `--receber`, `lstat` local imediatamente antes do `mkdir` do ciclo. Motivo: no envio o remoto so e lido por ciclo, e a guarda (1) exige observacao nesta execucao.
- RF-214(c)(7): ligacao simbolica local no caminho de uma pasta vira falha de item, porque a ligacao ja torna a travessia parcial e (4) desliga a exclusao. RF-214(c)(4) no envio em ciclos e avaliada no ciclo 1; o alvo vem de observacao positiva (pasta na origem), que leitura parcial nao fabrica.
- RF-216: pastas orfas sao apagadas uma vez, depois de todos os ciclos (bloqueio em qualquer ciclo bloqueia todas). Origem vazia com so pasta orfa no destino agora e recusada (14) — mudanca observavel aceita por RF-216(g).
- Decisao do solicitante (2026-11-08): excecao ao RF-136 — `delete_v2` so em `_dbx_cmd_sync_ocupante_remoto_apagar` e `_dbx_cmd_sync_pastas_orfas_apagar_remota`; auditorias conferem a funcao de cada ocorrencia (RF-136(f)).

- Teto do lint (decisao do solicitante, 2026-11-08): o `commands/sync.sh` cresceu de 2504 para 3359 linhas e levou o `shellcheck` de `commands/download.sh`, que o segue por `source`, de 11,4 GB para 12,8 GB de pico, acima do teto de 12288 MB. O solicitante escolheu subir o teto, preservando a analise cruzada, em vez de `source=/dev/null`. O padrao de `LINT_MEMORIA_MB` passa a 14336 (14 GB), com o mesmo valor no CLAUDE.md. A linha support/bash-4.2 ja media 13,2 GB e sera medida de novo na PR dela.
