---
id: 2026-10-19-1828-recuperacao-e-lixeira
tipo: decisao
escopo: projeto
titulo: Revisoes, restauracao e lixeira com exclusao permanente; restauracao recursiva de pasta
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, dba
status: ativa
ref: docs/prompts/2026-10-19_1828_backlog-fase-3-recuperacao.md
---

Decidido pelo solicitante em 2026-10-19 (fase 3, F-07 e F-20):
- **Comandos:**
  - `dbx revisoes <arq>` (alias `revisions`): lista as versões de um arquivo.
  - `dbx restaurar <arq>` (alias `restore`), com `--rev R` ou `--antes-de DATA`: restaura uma versão, inclusive de item apagado.
  - `dbx lixeira [pasta]` (alias `trash`): lista os itens apagados.
- **Exclusão permanente:** entra nesta fase.
  - É irreversível e só existe em contas Dropbox Business.
  - Exige o escopo novo `files.permanent_delete`, que o solicitante habilita no App Console antes de reautorizar.
  - A fase é porte G.
- **Pasta apagada:** é restaurada de forma recursiva, arquivo por arquivo, na última revisão, com `--dry-run` e resumo. Falha parcial sai 14 e diz o que faltou.
- **Restaurar sobre arquivo existente:** é permitido direto, porque a versão atual vira revisão anterior. A saída mostra a revisão substituída, para que a operação possa ser desfeita.

Divergências do BA decididas pelo Tech Lead:
- **DIV-54:** a exclusão permanente só aceita item já apagado (`get_metadata` com `include_deleted` devolvendo `DeletedMetadata`); senão sai 2. A janela entre a checagem e a chamada é risco residual declarado.
- **DIV-55:** `dbx lixeira --excluir <caminho>` (alias `--purge`). Com terminal, o operador digita o caminho exato. Sem terminal, exige `--confirmar-caminho <caminho>` idêntico ao alvo. Não há `--yes` nem `-y`, porque a operação é irreversível e o script tem de repetir o alvo. Sem confirmação válida sai 2 antes de qualquer chamada; resposta errada no terminal sai 14.
- **DIV-56:** o remédio para escopo ausente é `dbx unlink` seguido de `dbx config`.
- **DIV-57:** conta pessoal (400 sem JSON ou `invalid_account_type`) sai 6 com remédio. A resposta real não é exercitada nos testes, que não têm rede.
- **DIV-58:** mapeamento aceito: `invalid_revision`→4; `invalid_before_rev`, `before_rev_not_supported` e `unsupported_content_type`→2; `locked`→7; `team_folder`, `operation_suppressed` e `access_restricted`→6; `in_progress`→10 com retentativa, depois 14; `too_many_files`→14.
- **DIV-59:** o `rev` precisa constar do histórico do próprio caminho; senão sai 2.
- **DIV-60:** `--antes-de` compara `server_modified`. Aceita `AAAA-MM-DD` (fim do dia UTC, inclusivo) ou `AAAA-MM-DDTHH:MM:SSZ`.
- **DIV-61:** arquivo apagado sem `--rev` restaura a última revisão; arquivo vivo sem seleção sai 2.
- **DIV-62:** a pasta apagada traz tudo o que estiver apagado sob ela, mostrando `apagado_em`. O `--dry-run` lista o que voltaria. Um filtro por data fica no backlog.
- **DIV-63:** os três comandos não pegam a trava. Restaurar ou apagar em definitivo não conflita com o `sync` de forma destrutiva.
- **DIV-64 a DIV-69:** aceitas como recomendadas. Lixeira sem tipo nem data; listagem de pasta apagada validada como suposição; `rev` vigente vira `ja_atual` e sai 0 sem chamar `restore`; escopo opcional como `ok` informativo no `diagnostico`; System Design corrigido; prazos de retenção só citados na mensagem.
- **DIV-55 (complemento):** com terminal e `--confirmar-caminho` idêntico ao alvo, a pergunta é dispensada; o caminho já foi repetido.
- **DIV-70 a DIV-77 (SD) aceitas.** O escopo opcional fica na linha `escopos`. `lixeira -R` desce só em pastas vivas. `restaurar` sobre pasta viva sai 2. A confirmação aceita o argumento literal ou a forma normalizada, sempre com caixa exata. Na pasta, item fora da raiz ou sem revisão conta como falha (14), e `--dry-run` sai 0. `in_progress` vira 14 depois das retentativas em todo ponto de escrita. A contagem do aviso de pasta cobre um nível. DIV-76: o BA alinha o texto do escopo à DIV-55/56.
- **QA-B3-01:** `rev` fora do histórico sai 2, como manda a DIV-59; o `rst05` do SD é corrigido junto.
- **QA-B3-02 (segurança, corrigir; regra 17):** a guarda do expurgo exige que o `DeletedMetadata` seja do próprio alvo. A comparação é do `path_lower` com o alvo normalizado, os dois com caixa dobrada só no ASCII sob `LC_ALL=C`, como na fase 1b. Se divergir, inclusive por caixa não ASCII, recusa com 10, sem expurgo. Falha fechada.
- **QA-B3-03:** a DIV-75 vale para os pontos de escrita de `_dbx_cmd_escrita_remota`. O upload, por `lib/transfer`, retenta e mantém 10.
- **DIV-78 (observação do QA):** na restauração de pasta, item devolvido fora da pasta pedida, mesmo dentro da `raiz_remota`, nunca é restaurado e conta como falha (14).
- **QA-B3-04:** `lib/json` recusa como `malformado`, em todo documento, U+0000 (`\u0000`), `\ud800`/`\udc00` sozinhos e escape incompleto.
- **QA-B3-05:** a guarda do expurgo recusa com 10 um documento com qualquer chave repetida, em qualquer nível. No `lib/json` a recusa não é global, porque o E2-08 e o E3-03 aprovados fixam que a última chave vence; o QA avaliou que isso não é explorável nos outros consumidores.
- **QA-B3-06:** a descida (restauração de pasta e `lixeira -R`) só enfileira descendente estrito e mantém um conjunto de pastas visitadas sem caixa; pasta repetida é ignorada.
- **Ciclo 3 do QA aprovado.** Duas observações aceitas como risco baixo: o corte do corpo HTTP no primeiro NUL cru não dá poder extra, e a fila da descida é quadrática (cerca de 6 s em 4000 pastas). A fila por índice vai para a fase 9 (desempenho).
