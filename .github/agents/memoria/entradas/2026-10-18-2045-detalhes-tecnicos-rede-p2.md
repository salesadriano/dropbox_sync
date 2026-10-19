---
id: 2026-10-18-2045-detalhes-tecnicos-rede-p2
tipo: decisao
escopo: projeto
titulo: Detalhes tecnicos da fase 2 deixados em aberto pelo Business Analyst
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-18_2045_robustez-de-rede-p2.md
---

Decisões técnicas do Tech Lead, todas dentro das decisões do solicitante (`2026-10-18-2045-padroes-rede-p2`):
- As 5 tentativas contam a primeira.
- Cada retomada por `incorrect_offset` consome uma tentativa.
- Arquivo que muda de tamanho durante o envio é recusado.
- `Retry-After` em formato de data HTTP vale como inválido e cai no recuo normal.
- O teto de 300 s sobre o `Retry-After` é decisão do solicitante e prevalece sobre a letra anterior do RNF-07.
- O F-28 é defeito contra o contrato documentado no próprio `commands/download.sh` ("sem destino, o conteúdo sai pela saída padrão").
- `transfer_test` (~397) recebe `TMPDIR` privado dentro do RNF-32, como `http_test` e `hash_test`.
- RF-59(b): o `--json` mantém `falhas` como contagem (já é contrato) e acrescenta um par `falha_caminho`/`falha_classe` por item, na ordem dos itens.
- RF-58: o `correct_offset` aceito fica restrito a `0 <= N <= bytes já enviados com sucesso` (além de `<= tamanho`); valor acima do enviado é recusado sem `finish` (servidor hostil, RSK-40).
- RNF-32(a): o runner para no primeiro arquivo e no primeiro caso (`Bail out!`) e não tem opção de rodar tudo.
