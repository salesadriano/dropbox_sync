---
id: 2026-10-22-1600-progresso-por-arquivo
tipo: decisao
escopo: projeto
titulo: Progresso por arquivo - barra e percentual do arquivo em curso, linha desde o inicio, avanco por parte; bloco de linhas com paralelo
data: 2026-10-22
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, ux-expert
status: ativa
ref: docs/prompts/2026-10-22_1600_progresso-por-arquivo.md
---

Pedido do solicitante em 2026-10-22: a barra e o percentual no fim da linha medem o arquivo em curso (upload ou download), a linha aparece no inicio do processamento do arquivo e avanca a cada parte processada.

Decisoes do solicitante (AskUserQuestion, 2026-10-22):
- **Paralelo (N > 1):** "Uma linha por arquivo ativo". Bloco de ate N linhas redesenhado no terminal.
- **Download:** "Bytes recebidos (Recomendado)". O avanco vem do tamanho do arquivo parcial em disco durante o download; a forma de baixar nao muda.
- **Sem terminal com `--progresso`:** "Linha a cada parte (Recomendado)". Cada atualizacao e uma linha nova, sem retorno de carro.

Principios do Tech Lead:
- **Progresso nunca muda resultado:** stdout, codigo de saida, cache e plano sao os mesmos com e sem progresso (RF-28, RF-32); todo progresso sai so em stderr.
- **So o processo principal desenha** (fase 9, RF-135(a)): o auxiliar so informa o avanco.
- **Sem progresso, custo zero:** com o progresso inativo nenhum acompanhamento de tamanho roda.

Divergencias da especificacao (escopo v1.27, secao 5.19, `RF-140` a `RF-147`): `DIV-282` a `DIV-294` resolvidas pelo Tech Lead em 2026-10-22, todas na opcao recomendada pelo BA. As de maior efeito: amostragem do `.part` a 0,25 s com terminal e uma linha a cada 10 pontos percentuais sem terminal (`DIV-282`); barra de 10 celulas (`DIV-283`); `--dry-run` sem linha por arquivo (`DIV-285`); sem terminal com N>1, ordem de chegada com o `[i/N]` (`DIV-289`); o auxiliar informa o avanco por arquivo de status num diretorio temporario `0700`, lido pelo principal (`DIV-290`); retomada comeca no percentual real, nao em 0% (`DIV-294`, desvio declarado do literal).
