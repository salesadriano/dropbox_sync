# Parecer de Conformidade — Cursor de listagem no `sync --receber`, F-14 (fase 7b)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: cursor de listagem com instantâneo remoto persistido no `sync --receber` (F-14, RF-110 a RF-119, escopo v1.23, seção 5.16); porte **G**
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local, regra 14); validacao independente a cargo do QA Expert
- Data: 2026-10-21 (ciclo 1 e ciclo 2)
- Ciclos: 2
- Branch / base: `feature/cursor-b7b` sobre `develop` @ `a6b5376`, sem commit
- Log de prompt: [2026-10-21_0713_backlog-fase-7b-cursor.md](../prompts/2026-10-21_0713_backlog-fase-7b-cursor.md)
- Registro de entrega: [2026-10-21-0713-registro-cursor-b7b.md](2026-10-21-0713-registro-cursor-b7b.md)
- Também: [2026-10-21-0713-parecer-tdd-cursor-b7b.md](2026-10-21-0713-parecer-tdd-cursor-b7b.md)
- Validação do QA: [2026-10-21-0713-validacao-qa-cursor-b7b.md](2026-10-21-0713-validacao-qa-cursor-b7b.md)

## Gate — protocolo-conformidade

**Parecer (ciclo 1): APROVADO com ressalvas para o handoff ao QA.** Ciclo 2: correções sem achado novo registrado pelo SD; veredito do Tech Lead: **aprovado** (2026-10-21).

Diff lido por arquivo (`git diff` contra `a6b5376`). Stack shell (bash 4.4+), `shellcheck` limpo nos arquivos de código e nos testes novos.

### Verificações (ciclo 1)

| Regra | Verificação |
|---|---|
| O estado só acelera (P1) | A tabela reconstruída é a mesma que a completa: `instantâneo ⊕ delta` e a receita do serviço (`file`, `folder`, `deleted`); exclusão só com `path/not_found` na mesma execução (`dbx_sync_confirmar_exclusoes`); plano recalculado de "remoto atual completo × local atual completo"; cursor gravado só com código final 0 |
| Estado inválido nunca faz falhar (P2) | Leitor em fluxo com limites (campo de 8 KiB, 1.000.000 entradas, 512 MiB), regex por campo, rodapé sha256 conferido sobre o mesmo inode, `path_lower` e `path_display` confinados; qualquer anomalia descarta e faz varredura completa na mesma execução, sem falha |
| Exclusão sem confirmação (P0, C5) | Candidatos do modo incremental (delta `deleted` e ausência no instantâneo) confirmados antes do plano, também sem `--espelhar` e na simulação; contradição descarta; acima de 50 → completa |
| Reuso da 7a | Gravação atômica única (`_dbx_state_gravar_arquivo`, com gancho de rodapé opcional), leitor por descritor só de arquivo regular do usuário, poda no mesmo molde, trava do par sem trava nova |
| Sigilo (C10) | Cursor só em `DBX_STATE_CURSOR_VALOR` (limpo após o uso), `DBX_SYNC_CURSOR_NOVO` (limpo após gravar) e no arquivo 0600; `DBX_JSON_ESCAPADO` limpo após montar o corpo; avisos nunca citam o valor nem a palavra |
| Camadas | Formato e leitura em `lib/state`; tabela, delta e confirmação em `lib/sync`; orquestração e saída em `commands/sync`. `lib/state` não conhece a tabela: recebe função de entrada e função de corpo |
| Guarda sem estado preservada | `_dbx_cmd_sync_protegido` e as guardas de RF-41/48 rodam sobre a tabela reconstruída; nenhuma remoção local depende do registro sem `path/not_found` |
| `memoria-*` e `cursor-*` separados (RF-43, C9) | Nenhum descarte de um toca o outro; existência de `cursor-*` não vale como "par visto" (RF-48) |
| `DBX_STATE_VERSAO` | Inalterada; namespace novo com magia `dbx-cursor` versão 1 |
| shellcheck | Limpo em `lib/*.sh`, `commands/*.sh`, `bin/*` e nos três testes novos |

### Achados (ciclo 1)

| ID | Severidade | Achado | Tratamento |
|---|---|---|---|
| CNF-01 | Menor | `lib/sync` lê a constante `DBX_STATE_CURSOR_RE_CURSOR` de `lib/state` (acoplamento de leitura; `lib/sync` não carrega `lib/state`) | Aceito: só o caminho do delta, sempre chamado por `commands/sync`, que carrega os dois; `shellcheck disable=SC2154` comentado |
| CNF-02 | Menor | `commands/download` usa variável `local` de escopo dinâmico (`DBX_CMD_SYNC_CHAMADOR`) para desligar o cursor no `sync` interno | Aceito: não vira opção pública (nenhuma flag escondida na CLI) e se desfaz ao fim da chamada |
| CNF-03 | Menor | `commands/sync.sh` cresceu (laço de duas rodadas e cinco funções); `dbx_cmd_sync_executar` já era longa | Registrado; extração do bloco remoto para função própria fica como sugestão |
| CNF-04 | Informativo | `verificar` e `--enviar` passam a usar a tabela e o `continue` sem `limit` (mesmo enumerador) | DIV-233, aceita como mudança de comportamento na PR |

**Veredito ciclo 1: aprovado com ressalvas** para o handoff ao QA. As divergências com efeito de conformidade estão na seção abaixo.

## Ciclo 2 (QA-B7B-01, QA-B7B-02, QA-B7B-03 e O1)

Correções em `lib/state.sh`, `lib/sync.sh` e `commands/diagnostico.sh`, conforme o [parecer TDD](2026-10-21-0713-parecer-tdd-cursor-b7b.md), seção 8. Verificação de conformidade:

- **Camadas:** a correção de QA-B7B-01 ficou no contexto e no cabeçalho de `lib/state`, sem rede e sem decisão de comando. A correção de QA-B7B-02 e de QA-B7B-03 ficou em `lib/sync`, na mesma função de entrada da tabela.
- **Gêmeos:** a regra de confinamento de `path_lower` usa `_dbx_sync_relativo_seguro`, a mesma do `path_display`; nenhuma validação nova paralela.
- **Sigilo (C10):** nenhuma saída nova. O remédio do `diagnostico` (O1) não cita o valor do cursor.
- **Códigos de saída:** sem código novo.
- **shellcheck:** limpo nos arquivos de código e nos testes novos.

Sem achado novo registrado pelo SD no ciclo 2. **Veredito do Tech Lead (2026-10-21): ciclo 2 aprovado.** As correções de QA-B7B-01..03 e O1 têm vermelho antes e verde depois, 10 mutantes barrados e seleção verde.

## Divergências com efeito de conformidade

- **DIV-224:** teto de 20.000 páginas e cursor repetido na varredura completa saem 10 (violação do contrato do servidor, como no `reter`). Mudança de comportamento na PR.
- **DIV-226:** divergência de hash no `sync` sai 14, classe `integridade` (igual ao `sync` sem cursor). Mudança de texto no TC-CUS-03.
- **DIV-233:** `verificar` e `--enviar` usam `continue` sem `limit` e guarda de laço. Mudança de comportamento na PR.
- **DIV-235:** comparação de caixa usa a localidade do processo; efeito é de custo, nunca de exclusão. Registrada junto da RF-54(f).
- **DIV-205 (alterada pelo TL):** download de pasta não usa o cursor; o `download` recusa `--sem-cursor` e `--varredura-completa` com 2.
- **O2 (fora da 7b):** o `sync` aceita conteúdo cujo hash diverge da listagem quando falta `Dropbox-API-Result`. Defeito anterior à 7b, reproduzido na base `a6b5376`; F-43 e RSK-84. A 7b não tocou `lib/cmd.sh` nem `lib/http.sh`, o que foi confirmado por `git diff --stat`.

## Achados consolidados

| ID | Ciclo | Severidade | Situação |
|---|---|---|---|
| CNF-01 | 1 | Menor | Aceito |
| CNF-02 | 1 | Menor | Aceito |
| CNF-03 | 1 | Menor | Registrado; extração como sugestão |
| CNF-04 | 1 | Informativo | DIV-233, aceita |
| O2 | 2 | Defeito anterior à 7b | F-43, RSK-84 |
