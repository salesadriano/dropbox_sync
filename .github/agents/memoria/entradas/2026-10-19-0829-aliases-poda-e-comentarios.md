---
id: 2026-10-19-0829-aliases-poda-e-comentarios
tipo: decisao
escopo: projeto
titulo: Aliases em ingles rsync/git, poda das skills fora da stack e comentarios enxutos em lib/http e lib/transfer
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, documentation-writer
status: ativa
ref: docs/prompts/2026-10-19_0829_docs-e-aliases-p4.md
---

Decididos pelo solicitante em 2026-10-19 (fase 4):
- **Aliases em inglês** (os nomes em português continuam valendo):
  - `sync`: `--source`, `--dest`, `--push`, `--pull`, `--mirror`, `--yes`, `--allow-empty-source`;
  - `unlink`: `--yes`, `--keep-app`;
  - `config`: `--replace`, `--root`.
- **Poda do pacote:** as skills de stacks que o projeto não usa saem deste repositório. O `ai_team` continua sendo a fonte, e uma sincronização futura com o `ai_team` deve repetir a poda, sem reimportar essas skills.
- **Comentários:** `lib/http.sh` e `lib/transfer.sh` ficam só com o porquê atual; o histórico vai para `docs/registros`.

Decisões do Tech Lead:
- **F-32:** a localidade `C.UTF-8` é fixada somente dentro da comparação sem caixa, nunca no processo inteiro, para nenhuma contagem em bytes mudar (DIV-32). Sem a localidade, a comparação vale no ASCII e o `sync` avisa uma vez.
- **DIV-30:** a guarda antiga de origem vazia sai (O-1). Sem `--espelhar`, uma origem vazia é operação vazia com saída 0; uma raiz inexistente continua recusada.
- **DIV-31:** repetir `--enviar`/`--receber`, mesmo pelo alias, continua sendo uso inválido.
- `DBX_SYNC_LOCALIDADE` é aceita como apoio de teste, como `DBX_HASH_BACKEND`, validada por alfabeto fechado e sem efeito quando a localidade existe. As ferramentas opcionais do `config --debug` (`mount`, `grep`, `getenforce`, `lsattr`) ficam fora do preflight e aparecem no README como opcionais.
