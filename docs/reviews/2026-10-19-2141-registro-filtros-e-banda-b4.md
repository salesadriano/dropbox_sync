# Fase 4 do backlog (B4): filtros de caminho, data e tamanho (F-13) e limite de banda (F-17)

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Fase 4 do plano do backlog, retomada depois do merge da PR #44: filtros avancados (F-13: `--excluir`/`--incluir` gitignore, `--modificado-desde`/`--modificado-ate`, `--tamanho-min`/`--tamanho-max`) e limite de banda (F-17: `--limite-banda`/`--bwlimit` e `DBX_LIMITE_BANDA`). RF-79 a RF-83. |
| Porte | M. Toca contrato publico da CLI (flags novas, variavel de ambiente, campos de saida) e a exclusao do `--espelhar`, critica para a seguranca dos dados. Sem gatilho de G: nenhuma integracao externa nova, schema ou mudanca de arquitetura; so o modulo de dominio puro `lib/filtro` (DIV-94). |
| Log de prompt | [docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md](../prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md) |
| Branch / base | `feature/filtros-e-banda-b4` sobre `develop` @ `4d54729` |
| Agents | Business Analyst (requisitos, System Design); Senior Developer (implementacao, sob `protocolo-tdd` e `protocolo-conformidade`, 2 ciclos); QA Expert (validacao independente, 21 casos, 2 ciclos); Tech Lead (decisoes, fechamento). |
| Data | 2026-10-19 a 2026-10-20 |

## 2. Causa ou decisao

Decisao do solicitante (F-13, F-17), na memoria [2026-10-19-2141-filtros-e-banda](../../.github/agents/memoria/entradas/2026-10-19-2141-filtros-e-banda.md): filtros gitignore sem caixa sobre o caminho relativo, exclusao vence inclusao; com `--espelhar`, item filtrado fica fora do escopo nos dois lados, nunca transferido nem apagado; data e tamanho so na origem e recusados com `--espelhar`; limite de banda pelo `--limit-rate` do cURL, opcao vence a variavel.

- DIV-79 a DIV-94 (BA): aceitas como recomendadas. Destaques: DIV-81 (origem toda filtrada conta como vazia, vale a recusa do RF-41), DIV-82 (entradas sob pasta remota excluida descartadas), DIV-87/88 (sem unidade e B/s; piso 2048 B/s pelo RNF-30), DIV-92 (filtros fora da identidade da memoria), DIV-94 (`lib/filtro.sh` puro).
- DIV-95 a DIV-102 (Senior Developer): aceitas. DIV-96 (`server_modified` em `lib/filtro`, so escopo, RF-39 intacto), DIV-97 (malformados extras), DIV-98 (nomes e posicao dos campos), DIV-99 (nome nao UTF-8 comparado por bytes), DIV-100 (sem data nao passa filtro de data), DIV-101 (simbolico e especial so saem em silencio fora do escopo como arquivo e como pasta), DIV-102 (`download --dry-run` sem consulta do tipo).
- DIV-103 (ciclo 2, revisada pelo Tech Lead): na comparacao por bytes, `--incluir` impreciso (conjunto negado, conjunto com membro fora do ASCII, `?`) nao casa; `--excluir` impreciso casa a mais (protege).
- Duas barreiras independentes contra exclusao de filtrado (RF-80(d)): o predicado unico `dbx_sync_no_escopo` e a guarda sem estado `_dbx_cmd_sync_protegido`, que le so os padroes da linha de comando. Mutantes provam que cada uma sozinha basta.

Defeito anterior corrigido (DIV-95, RSK-56): `lib/http` nao limpava `_DBX_HTTP_ARQUIVO_CORPO` nos modos `bearer` e `formulario`, e o `delete_v2` depois de um envio (`sync --enviar --espelhar`) ou uma renovacao de token levava o arquivo enviado como corpo. Correcao unica e evidente em `dbx_http_requisitar`/`dbx_http_formulario`, com teste de regressao (`teste_div95_*`, QA-B4-E10).

## 3. Arquivos

Levantado com `git diff --numstat` e `git status --short`; arquivos novos contados por `wc -l`.

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/filtro.sh` | Novo (dominio puro: padrao, caixa, bytes, data, tamanho) | +737/-0 |
| `lib/sync.sh` | Alterado (chave via `lib/filtro`, `dbx_sync_no_escopo`, descarte remoto, contagem) | +151/-19 |
| `lib/cmd.sh` | Alterado (preparo de filtros, campos, avisos, limite de banda) | +145/-0 |
| `lib/walk.sh` | Alterado (poda de pasta excluida) | +42/-2 |
| `lib/cli.sh` | Alterado (`dbx_cli_validar_taxa`) | +34/-0 |
| `lib/http.sh` | Alterado (`dbx_http_limite_banda`; correcao DIV-95) | +28/-0 |
| `commands/sync.sh` | Alterado | +111/-3 |
| `commands/download.sh` | Alterado | +102/-20 |
| `commands/verificar.sh` | Alterado | +51/-2 |
| `commands/upload.sh` | Alterado | +20/-0 |
| `bin/dbx` | Alterado (ajuda) | +95/-6 |
| `completions/dbx.bash` | Alterado | +11/-6 |
| `tests/unit/filtro_test.sh` | Novo | +463/-0 |
| `tests/integracao/filtros_test.sh` | Novo | +822/-0 |
| `tests/integracao/banda_test.sh` | Novo | +327/-0 |
| `tests/integracao/filtros_ajuda_test.sh` | Novo | +130/-0 |
| `tests/integracao/qa_filtros_banda_b4_test.sh` | Novo (QA) | +867/-0 |
| `README.md` | Alterado (Filtros, Limite de banda, ressalva NFC/NFD) | +52/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (BA, v1.17) | +58/-3 |
| `docs/requisitos/funcionalidades-candidatas.md` | Alterado (BA, v0.9) | +3/-3 |
| `docs/requisitos/riscos-restricoes-e-licenciamento.md` | Alterado (BA, v0.9, RSK-56) | +4/-1 |
| `docs/arquitetura/system-design.md` | Alterado (BA, v1.12) | +31/-1 |
| `docs/testes/mapa-modulos.md` | Alterado (`lib/filtro`, testes novos, `qa_recuperacao_b3`, 12 `qa_*`) | +23/-9 |
| `.github/agents/memoria/entradas/2026-10-19-2141-filtros-e-banda.md` | Novo (decisao) | documental |
| `docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md` | Novo (log de prompt) | documental |

Total de linhas de codigo (producao e teste, sem documentacao): **4194** (4136 adicionadas, 58 removidas), somando `lib/`, `commands/`, `bin/`, `completions/` e `tests/`.

## 4. Testes rodados

Selecao pelo mapa de modulos sobre os itens afetados, com parada no primeiro erro. Contagens literais dos pareceres; duracao nao informada nas execucoes por filtro.

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| Suite inteira, ciclo 1 (47 arquivos, 2 pulados) | `lib/`, `commands/`, `bin/` | `bash tests/run.sh` | 1378 | 1376 | 0 | nao informada |
| `filtro_test`, `filtros_test`, `filtros_ajuda`, `qa_filtros_banda_b4` (ciclo 2) | `lib/filtro.sh`, `lib/sync.sh`, `commands/` | `bash tests/run.sh filtro` | 92 (34+33+4+21) | 92 | 0 | nao informada |
| `banda` (ciclo 2) | `lib/http.sh`, `lib/cli.sh` | `bash tests/run.sh banda` | 34 | 34 | 0 | nao informada |
| Selecao do mapa (ciclo 2): `sync` 91, `walk` 13, `http` 53, `cmd` 23, `cli` 17, `verificar` 17, `composicao` 28, `json` 62, `tmp` 39, `completar` 17, `comandos` 119, `qa_` 247 | `lib/*.sh`, `commands/*.sh`, auditorias | `bash tests/run.sh <filtro>` | 726 | 726 | 0 | nao informada |

- Casos novos do developer: 80 no ciclo 1 (`filtro_test` 31, `filtros_test` 32, `banda_test` 13, `filtros_ajuda` 4), mais os do ciclo 2 (QA-B4-01, DIV-103). Suite do QA: 21 casos. Nenhum teste existente alterado ou removido.
- Red observado: os 80 casos do ciclo 1, rodados um a um contra copia de `4d54729` (`git archive`), 80/80 vermelhos; seis que passavam na base foram endurecidos antes do codigo. Ciclo 2: `teste_qa_b4_01_*`, assercoes novas de `flt04`, DOC-03 de ajuda/README e `teste_div103_*` (unidade e ponta a ponta) vermelhos antes da correcao.
- Parada no primeiro erro (Regra 9): atendida pelo runner (`Bail out!`); a 1a passada de `json` do QA parou na auditoria de substituicao de comando no E16, corrigida e reexecutada.
- Barreiras estaticas: `shellcheck` limpo em `lib/*.sh commands/*.sh bin/* scripts/*.sh` e nos testes novos; `bash scripts/verificar-remocao-de-casos.sh`: nenhuma reducao.
- Testes de seguranca e acesso (Regra 6):
  - Prova pelo registro de chamadas do duplo de `curl` e dos duplos de `rm`/`date`: zero `delete_v2` e zero `rm` sobre item filtrado, com o item no escopo apagado (TC-FES-07..10, QA-B4-E01/E02/E05/E06).
  - Padrao e dado: sem `eval` nem glob contra o disco; `$(...)`, crase, `;`, `$HOME`, `~` nada executam (TC-FLT-16, QA-B4-E11).
  - Taxa validada antes de rede ou escrita; 26 taxas hostis saem 2; o texto nunca chega ao `argv` nem a configuracao do cURL (TC-BND-04, QA-B4-B02/B03).
  - Limites de 64 padroes e 1024 bytes por padrao, contados em bytes (QA-B4-E12); nomes nao UTF-8 e caixa trocada (QA-B4-E03, E13 a E16).
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: projeto e CLI em shell, sem formulario.
- Suite completa local no push para a PR de `develop` (Regra 8), pelo comando oficial `sh scripts/suite-completa.sh`: **APROVADA**: 48 arquivos, 1401 aprovados, 0 reprovados e 2 pulados (vetor oficial sem rede); 657 s; sha testado `0830c2c`, registrado e conferido com `--conferir` em 2026-10-20T10:47:13Z.

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer, nesta ordem.

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 1: nenhum bloqueante; lacunas nao bloqueantes: TC-BND-13 em modo humano (sem `tty`) nao exercitado; poda da descida sem mutante proprio (coberta por TC-FES-04/08 e pela guarda). Mutantes d5 (TC-FES-11) mortos. Ciclo 2: nenhum. | Ciclo 1 Aprovado; ciclo 2 Aprovado |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; `security-best-practices` (entrada de usuario, exclusao, segredo); Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Ciclo 1: nenhum bloqueante; `lib/filtro` depende so de `lib/errors`; predicado de escopo unico (RNF-36); nenhuma `$(...)` nova em `lib/` (RNF-24); `LC_ALL` so em `local`; nenhum codigo de saida novo; DIV-95 (alta, `lib/http.sh`) achado e corrigido com regressao. Ciclo 2: nenhum. | Ciclo 1 Aprovado; ciclo 2 Aprovado |

- Ciclo: 2. Status dos achados do QA: QA-B4-01 corrigido (mesma dobra no padrao e no caminho na queda para bytes; `?` e conjunto negado casam sequencia UTF-8 ou um byte); QA-B4-02 corrigido (`]` inicial e membro); QA-B4-03 corrigido (ajuda e README citam NFC/NFD); QA-B4-04 corrigido (mapa). DIV-103 introduzida e aceita.
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes de cada passo e gate.

## 6. QA

- Validacao independente do QA Expert em [tests/integracao/qa_filtros_banda_b4_test.sh](../../tests/integracao/qa_filtros_banda_b4_test.sh), 21 casos, sha256 `5f8978afe165a914e673f6ee319dc56249005dcc303c575c0e9894dc38d9a1b0`. Mutantes m1 a m12 em copias da arvore; cada barreira do RF-80(d) sozinha basta (m1b, m1c).
- Ciclo 1: **Reprovado** (suite de 16 casos, sha256 `965a25de...21b9`).
  - QA-B4-01 (Alta, P0): `--excluir` nao protegia nome local nao UTF-8 com caractere fora do ASCII no padrao ou no nome; `--receber --espelhar` apagava o item (QA-B4-E03).
  - QA-B4-02 (Baixa): `[]a]` recusado como conjunto vazio, contra o gitignore.
  - QA-B4-03 (Baixa): ajuda e README sem a ressalva NFC/NFD junto da garantia do `--espelhar`.
  - QA-B4-04 (Info): mapa de modulos sem `qa_recuperacao_b3` e com contagem de `qa_*` defasada.
- Ciclo 2: **Aprovado**. Suite intacta do ciclo 1 passou 16/16 antes dos acrescimos; 5 casos novos (E13, E14, E15, E16, A02). Mutantes m9 a m12 mortos. Observacoes sem acao: INFO-01 (`[]-a]` recusado, coerente com DIV-97, lado seguro) e INFO-02 (padrao com byte nao UTF-8 aceito; sugestao ao BA declarar ou recusar).
- Execucao do QA no ciclo 2: `bash tests/run.sh filtro` aprovada (`qa_filtros_banda_b4` 21/21); selecao do mapa aprovada; `shellcheck -x` limpo; nenhuma reducao de casos.
- Veredito do QA: **Aprovado**, 2026-10-20 (ciclo 2).

## 7. Riscos e rollback

- Riscos residuais:
  - Sem normalizacao Unicode: `--excluir` em NFC nao protege nome em NFD (RF-79(h)), declarado na ajuda e no README.
  - INFO-02: padrao com byte nao UTF-8 pode casar a menos contra nome valido. Owner BA, sem prazo.
  - TC-BND-13 em modo humano (terminal) nao exercitado.
- Impacto: contrato. Flags novas `--excluir`, `--incluir`, `--modificado-desde`, `--modificado-ate`, `--tamanho-min`, `--tamanho-max` (`sync`, `verificar`, `download` de pasta) e `--limite-banda`/`--bwlimit` (`upload`, `download`, `sync`); variavel `DBX_LIMITE_BANDA`; campos de saida novos (DIV-98), so acrescimo; nenhum codigo de saida novo. Correcao DIV-95 muda o corpo das chamadas JSON depois de um envio. Sem schema nem dependencia nova.
- Rollback: `git revert 0830c2c` basta; filtros e limite sao por execucao e ficam fora da identidade da memoria (DIV-92), sem migracao de dado nem de credencial.

## 8. Links e aceites

- Entradas de memoria: `2026-10-19-2141-filtros-e-banda`.
- Documentacao sincronizada: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) v1.17, [funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md) v0.9, [riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md) v0.9 (RSK-56), [system-design.md](../arquitetura/system-design.md) v1.12, [mapa-modulos.md](../testes/mapa-modulos.md), `README.md`.
- Commit(s): `0830c2c` - `feat(filtros): filtros de caminho, data e tamanho e limite de banda`; mais o commit deste preenchimento.
- PR: [#45](https://github.com/salesadriano/dropbox_sync/pull/45) para `develop`.
- Tech Lead: aceite em 2026-10-20, depois da suite completa verde em `0830c2c`, do QA aprovado no ciclo 2 e da aprovacao do solicitante (regra 12). O merge fica com o solicitante.
- Solicitante: aceite dos `qa-*` por sha256 (regra 12), 2026-10-20 ("Aprovo"): `tests/integracao/qa_filtros_banda_b4_test.sh` (21 casos, `5f8978afe165a914e673f6ee319dc56249005dcc303c575c0e9894dc38d9a1b0`).
