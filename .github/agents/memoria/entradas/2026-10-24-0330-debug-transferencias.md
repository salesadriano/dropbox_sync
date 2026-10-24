---
id: 2026-10-24-0330-debug-transferencias
tipo: decisao
escopo: projeto
titulo: Depuracao (--debug) de download, upload e sync - chamadas HTTP, etapas, decisoes do sync e resumo, so em stderr
data: 2026-10-24
dono: Tech Lead
instancia: myPCWin/Desenvolvedor Hydros
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-24_0330_debug-transferencias.md
---

Pedido do solicitante em 2026-10-24: implementar o `--debug` (e `DBX_DEBUG=1`) de `download`, `upload` e `sync`. Especificacao na secao 5.21 do escopo (v1.29), `RF-156` a `RF-165`, `TC-DBG-01` a `TC-DBG-35`, `F-51`.

Decisoes do solicitante (AskUserQuestion, 2026-10-24):
- Conteudo: as quatro partes (chamadas HTTP por tentativa; etapas de upload e download, nunca o id da sessao; decisoes do sync com motivo, nunca o cursor; resumo no fim).
- Destino: so stderr; stdout, codigo de saida, cache e numero de requisicoes identicos com e sem `--debug`.
- Base: a implementacao comeca so depois do merge da PR de `feature/teste-de-disponibilidade`; a branch recebe a `develop` atualizada por merge antes do primeiro codigo.
- DIV-332 A (caminhos completos do operador, saneados e redigidos), DIV-338 A (resumo unico substitui a linha `paralelo` de `RF-135(d)`), DIV-339 A (sem limite de volume).

Decididas pelo Tech Lead na recomendacao do BA: DIV-333, 334, 335, 336, 337, 340 e 341 (opcao A em todas; detalhe na secao 9 do escopo).
