---
id: 2026-10-18-2243-cache-do-upload
tipo: decisao
escopo: projeto
titulo: Cache do upload no lib/state sem vinculo a conta, com poda e identidade forte do arquivo
data: 2026-10-18
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, dba
status: ativa
ref: docs/reviews/2026-10-18-2243-parecer-dba-cache-unico.md
---

Decididos pelo solicitante em 2026-10-18:
- O cache do upload não se vincula à conta: o RF-52 é emendado para o upload, porque esse cache guarda só dado local e a proteção entre contas vem da comparação com o `content_hash` remoto.
- Poda: acima de 10 mil entradas, remover as não usadas há mais de 90 dias.

Recomendações do parecer do DBA aceitas pelo Tech Lead:
- O upload usa namespace próprio no `lib/state`, separado do sync (RF-48), sem cache para entrada padrão, origem não regular e arquivo vazio.
- A identidade do arquivo usa inode, dispositivo e `mtime`/`ctime` em nanossegundos, com `stat` antes e depois do hash e a regra anti-corrida de 2 s.
- O diretório de estado é criado em 0700.
- O sync grava só as entradas visitadas e, se não obtiver a conta, segue sem memória em vez de usar `sem-identidade`.
- O `dbx.db*` legado fica intacto e documentado, sem migração.

Divergências do Business Analyst decididas pelo Tech Lead:
- **DIV-26:** a memória do sync também usa a identidade forte do arquivo.
- **DIV-27:** com `upload --rev` não há skip; o envio segue e o servidor faz valer o rev.
- **DIV-28 (revista):** sem identidade de conta não há linha de base, e a guarda de origem vazia do RF-41(b) não protege. Por isso, sem identidade de conta, a propagação de exclusões fica **desabilitada naquela execução**, com a mesma semântica do RF-41(a): envio e recebimento seguem e o código de saída difere de 0. O `--confirmar` não reabilita. A decisão anterior (pedir reconhecimento) deixava uma rotina com `--confirmar` sobre origem vazia apagar o destino.
- **DIV-29:** a gravação corrige para 0700 o diretório de estado existente, quando ele pertence ao usuário.
- **RF-61(i):** um acerto de cache conta como uso e renova o carimbo.
- **QA-P3-01 (bloqueante):** uma memória que existe mas é descartada na carga (versão antiga, truncada ou corrompida) desabilita a propagação de exclusões naquela execução, com o motivo no relatório e saída diferente de 0, como no RF-41(e). A memória é regravada em v2 depois de uma travessia completa. Isso protege toda instalação existente na primeira execução após a troca de formato, sem recusar a execução (DP-27b).
