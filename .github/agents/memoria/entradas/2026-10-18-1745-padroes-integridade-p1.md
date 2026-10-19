---
id: 2026-10-18-1745-padroes-integridade-p1
tipo: decisao
escopo: projeto
titulo: Comportamentos de integridade de dados no sync e no download (fase P1)
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/reviews/2026-10-18-1745-registro-integridade-de-dados-p1.md
---

Decididos pelo solicitante em 2026-10-18:
- O sync compara caminhos sem diferenciar caixa, como o Dropbox. Colisão de caixa local (`a.txt` e `A.txt`) é recusada antes de qualquer escrita.
- O recebimento (`download` e `sync --receber`) grava em um temporário no mesmo diretório, confere o `content_hash` e só então substitui o arquivo de forma atômica. Se o hash divergir, o arquivo antigo é mantido, o temporário é descartado e o comando falha.
- O `download` de uma pasta nunca apaga um arquivo regular existente no destino.
- Um arquivo local existente sem permissão de escrita (ex.: 0444) não é substituído pelo recebimento: o comando falha com diagnóstico claro e o arquivo fica intacto. No `sync --receber`, isso conta como falha do item.
- Arquivos baixados seguem o umask do usuário; só a área temporária com o token fica em 077, e o umask do processo é preservado.
- `sync --enviar` mantém "origem vence" (DP-27) entre execuções, usa sessão acima de 150 MiB e envia `client_modified`, como o `upload`. Na mesma rodada o solicitante revisou o padrão "sem rev" e manteve o RF-49 (DIV-23): a sobrescrita leva o `rev` da listagem e uma mudança remota concorrente vira falha do item, sem sobrescrever.
- O RNF-04 foi emendado (DIV-24): `0600` na criação da credencial e da área temporária, sem alterar o umask do processo.
