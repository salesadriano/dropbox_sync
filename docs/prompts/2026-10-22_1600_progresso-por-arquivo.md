---
date: 2026-10-22
hora: "1600"
domain: progresso por arquivo (upload, download e sync)
porte: G
status: aberto
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-22-1600-registro-progresso-por-arquivo.md"
---

# progresso-por-arquivo

## Prompt 1 — 2026-10-22

> a barra de progressão e o percentual ao final da linha devem representar o percentual de conclusão do processamento do arquivo, download ou upload, a linha deve ser exibida no inicio do procssamento do arquivo e devem ser incrementados na medida que as partas do arquivo são processadas

**Intencao:** a barra e o percentual no fim da linha passam a medir o arquivo em curso, nao o processo inteiro. A linha aparece no inicio do processamento do arquivo e avanca a cada parte processada, no upload e no download.

**Estado atual levantado pelo Tech Lead (develop @ `a39a89e`):**
- `dbx_progress_etapa` (`lib/progress.sh`) emite `[i/N] acao: item [barra] (x%)` com `x` = percentual GLOBAL; a barra do item vale 100 por padrao ja no inicio (`pct_item` vazio com `atual > 0`).
- Upload em sessao: uma linha NOVA por parte (`dbx_progress_transferencia 'upload' ... "parte N enviada"`, `lib/transfer.sh`), nao uma linha que avanca.
- Download: requisicao unica; o `sync` descarta o stderr da transferencia (`>/dev/null 2>&1`), o que esconde a barra do cURL.
- Antecedente: o commit `cdac965` (branch `feature/progresso-transferencia-arquivo`, nunca enviada) fazia algo parecido sobre `cec9873`; descartado pelo solicitante em 2026-10-22. Esta demanda e refeita sobre a `develop` atual.

**Decisoes do solicitante (AskUserQuestion, 2026-10-22):**
- **Paralelo (`--paralelo N`, N > 1):** "Uma linha por arquivo ativo" — bloco de ate N linhas redesenhado no terminal.
- **Download:** "Bytes recebidos (Recomendado)" — acompanhar o tamanho do arquivo parcial em disco durante o download, sem mudar a forma de baixar.
- **Sem terminal com `--progresso`:** "Linha a cada parte (Recomendado)" — cada atualizacao vira linha nova, sem retorno de carro.

**Porte:** G. `scripts/porte.sh` nao existe no projeto. Com N > 1 o avanco nasce nos processos auxiliares e so o principal desenha a saida (fase 9): muda o desenho de saida do paralelismo no System Design. Toca `lib/progress`, `lib/transfer`, `lib/http` e `commands/sync`, `upload`, `download`.

**Entrada:** branch principal `develop` @ `a39a89e`; PR aberta: nenhuma (a `chore/atualiza-documentacao` ainda nao foi enviada, so documentacao, sem sobreposicao de codigo); worktree `feature/progresso-por-arquivo` em `/home/sales/dropbox_api.worktrees/feature-progresso-por-arquivo`; `alteracoes-externas.sh --inicial` exit 0.

**Especificacao (Business Analyst):** secao 5.19 do escopo (v1.27), `RF-140` a `RF-147`, `TC-PRG-01` a `TC-PRG-36`, `F-49`.

Divergencias da especificacao (escopo v1.27, secao 5.19, `RF-140` a `RF-147`): `DIV-282` a `DIV-294` resolvidas pelo Tech Lead em 2026-10-22, todas na opcao recomendada pelo BA. As de maior efeito: amostragem do `.part` a 0,25 s com terminal e uma linha a cada 10 pontos percentuais sem terminal (`DIV-282`); barra de 10 celulas (`DIV-283`); `--dry-run` sem linha por arquivo (`DIV-285`); sem terminal com N>1, ordem de chegada com o `[i/N]` (`DIV-289`); o auxiliar informa o avanco por arquivo de status num diretorio temporario `0700`, lido pelo principal (`DIV-290`); retomada comeca no percentual real, nao em 0% (`DIV-294`, desvio declarado do literal).

**Gates e QA:** `protocolo-tdd` reprovado no ciclo 1 (5 maiores) e aprovado com ressalvas no ciclo 2; `protocolo-conformidade` aprovado com ressalvas nos ciclos 1 e 2. Validacao independente do QA aprovada com ressalvas (`QA-B10-01` a `03`). Divergencias da implementacao `DIV-295` a `DIV-306` resolvidas pelo Tech Lead.

**Aceite do solicitante (AskUserQuestion, 2026-10-22):** suite do QA `tests/integracao/qa_progresso_arquivo_b10_test.sh`, 8 casos, sha256 `fab96fad4e4aa1c67b3905c728b7004870031975618c030cba7987fc10ff5956`: "Aceito (Recomendado)".
