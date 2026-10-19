# Pendencias tecnicas do backlog, fase 0: O-5, RSK-43 e status do backlog

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "analise e implemente os itens no backlog" (fase 0 do plano em dez fases: pendencias tecnicas). |
| Porte | M. Manutencao e testes, sem contrato novo. Toca o erro do `upload` (progresso passa a informar classe e motivo), o que o gatilho de M cobre. |
| Log de prompt | [docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md](../prompts/2026-10-19_1023_backlog-fase-0-pendencias.md) |
| Branch / base | `chore/pendencias-backlog-p0` sobre `develop` @ `73769c8` (ancestral verificado) |
| Agents | Business Analyst (status F-23 a F-33, emendas RF-38(b) e RF-48); Senior Developer (implementacao, sob `protocolo-tdd` e `protocolo-conformidade`); QA Expert (validacao independente, 10 casos); Tech Lead (decisoes O-QA-2, O-QA-3 e O-7, fechamento). |
| Data | 2026-10-19 |

## 2. Causa ou decisao

- **O-5, leitura do corpo de resposta.** A leitura silenciosa foi movida para `dbx_cmd_ler_corpo_silencioso` em [lib/cmd.sh](../../lib/cmd.sh), e `commands/upload.sh` passa a apenas orquestrar. Unica abordagem, por ser a correcao do achado 2 da fase 3 (leitura paralela a `_dbx_cmd_analisar_corpo` no comando).
- **RSK-43, parser de `gnustat`.** Testado com o GNU coreutils 9.7 como `gnustat`; o formato e igual ao do uutils (fracao, fuso `%y`, `%z`). O duplo registra as chamadas, o que prova que `lib/hash` passou pelo `gnustat`. Parser sem correcao.
- **O-QA-2 mantido** (o RF-48 reconhece a primeira execucao antes do plano). **O-QA-3 documentado** em [SKILLS_SYNC.md](../../.github/skills/SKILLS_SYNC.md), porque o `historico/` e imutavel. **O-7 mantem o comportamento seguro**, com emenda ao RF-38(b): travessia parcial nao grava estado.
- **Backlog.** F-23 a F-33 com status atualizado; F-06 entregue (existe como `sync --espelhar`); F-31 parcial, com o restante (`lib/tmp`, OBS-02 a OBS-04) na fase 2; F-35 (PKCE) fora.
- **Plano.** Dez fases sequenciais na memoria [2026-10-19-1023-plano-do-backlog](../../.github/agents/memoria/entradas/2026-10-19-1023-plano-do-backlog.md). O plano anterior, `2026-10-18-1745-melhorias-em-fases`, foi encerrado.

Requisitos: [escopo-requisitos-e-criterios-de-aceite](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) (RF-38(b), RF-48), [funcionalidades-candidatas](../requisitos/funcionalidades-candidatas.md) (F-06, F-23 a F-33, F-35).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `commands/upload.sh` | Alterado | +24/-17 |
| `lib/cmd.sh` | Alterado | +44/-0 |
| `lib/state.sh` | Alterado (comentario de `dbx_state_gravar`) | +7/-5 |
| `tests/integracao/comandos_test.sh` | Alterado | +14/-0 |
| `tests/unit/cmd_test.sh` | Alterado | +30/-0 |
| `tests/unit/identidade_gnustat_test.sh` | Novo | +170/-0 |
| `tests/integracao/qa_pendencias_p0_test.sh` | Novo (QA) | +188/-0 |
| `.github/skills/SKILLS_SYNC.md` | Alterado (nota O-QA-3) | +2/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (BA) | +4/-3 |
| `docs/requisitos/funcionalidades-candidatas.md` | Alterado (BA) | +32/-32 |
| `docs/testes/mapa-modulos.md` | Alterado | +6/-5 |
| `.github/agents/memoria/entradas/2026-10-18-1745-melhorias-em-fases.md` | Alterado (plano anterior encerrado) | +1/-1 |
| `.github/agents/memoria/entradas/2026-10-19-1023-plano-do-backlog.md` | Novo (decisao) | documental |
| `.github/agents/memoria/entradas/2026-10-19-1023-aceite-testes-qa-p0.md` | Novo (aceite) | documental |
| `docs/prompts/2026-10-19_1023_backlog-fase-0-pendencias.md` | Novo (log de prompt) | documental |

Total de linhas de codigo (producao e teste, sem documentacao): **499** (477 adicionadas, 22 removidas), somando os arquivos de `commands/`, `lib/` e `tests/`.

## 4. Testes rodados

Selecao por arquivo de teste, so dos itens afetados (Regra 8 de `protocolo-tdd`). Contagens literais do runner informadas na delegacao; `n/i` = nao informado na delegacao (lacuna).

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `tests/unit/cmd_test.sh` | [lib/cmd.sh](../../lib/cmd.sh) (O-5) | `bash tests/run.sh tests/unit/cmd_test.sh` | 10 | 10 | 0 | n/i |
| `tests/integracao/comandos_test.sh` | [commands/upload.sh](../../commands/upload.sh) (O-5) | `bash tests/run.sh tests/integracao/comandos_test.sh` | 119 | 119 | 0 | n/i |
| `tests/unit/identidade_gnustat_test.sh` | `lib/hash.sh`, `lib/state.sh`, `lib/walk.sh` (RSK-43) | `bash tests/run.sh tests/unit/identidade_gnustat_test.sh` | 7 | 7 | 0 | n/i |
| `tests/integracao/qa_pendencias_p0_test.sh` | Validacao independente (QA) | `bash tests/run.sh tests/integracao/qa_pendencias_p0_test.sh` | 10 | 10 | 0 | n/i |
| `json_test`, `http_test`, `preflight_test`, `composicao_test`, `cli_test`, `state_test`, `qa_cache_unico`, `qa_robustez`, `qa_integridade`, `qa_docs_aliases` | Auditorias de `lib/*.sh` e suites das fases anteriores | n/i | n/i | n/i | n/i | n/i |

- Lacuna: os pareceres dizem que as suites acima estao verdes, mas as contagens literais e as duracoes nao vieram na delegacao. Colar a saida do runner antes do fechamento.
- Red observado: O-5 unidade, 2 casos novos de `cmd_test` reprovaram (`dbx_cmd_ler_corpo_silencioso` inexistente); O-5 integracao, caso 113 de `comandos_test` reprovou (progresso sem classe e motivo); RSK-43, sem red (formato GNU igual ao uutils, caso de guarda).
- Parada no primeiro erro (regra 9): n/i na delegacao.
- Barreiras estaticas: `shellcheck` limpo segundo o developer e o QA; comando e saida literais n/i.
- Testes de seguranca e acesso (regra 6): token em corpo de erro (truncado e 5xx) ausente de stdout e stderr; hash malformado sem envio e com diagnostico nomeado; corpo vazio, JSON truncado, campo ausente e destino pasta, cada um com classe e motivo no progresso.
- Validacao de formularios em E2E (regra 7): Nao aplicavel: projeto e CLI em shell, sem formulario.
- Suite completa local no push para a PR de `develop` (regra 8): PENDENTE

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer, nesta ordem.

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Nenhum achado de codigo. Pendencia de mapa (registrar `identidade_gnustat` e a leitura de `lib/cmd`): atendida, `docs/testes/mapa-modulos.md` alterado e conferido pelo QA. | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + skill de stack (nome n/i); Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | Nenhum achado. Leitura silenciosa em `lib/cmd`, o comando so orquestra. Capturas novas em `lib/` com byte externo: nenhuma. Contexto de analise literal (auditoria de `composicao`). Comportamento observavel inalterado, salvo o progresso com classe e motivo. | Aprovado |

- Ciclo: 1. O red intermediario (auditoria de `composicao` sobre o nome de contexto vindo de variavel e a forma `if ! dbx_json_contexto x;`) foi corrigido no mesmo ciclo, com contexto literal `leitura_silenciosa`.
- `sh scripts/alteracoes-externas.sh --detectar` antes de cada gate: n/i na delegacao. Sem acusacao na execucao do registro.

## 6. QA

- Validacao independente do QA Expert sobre os itens afetados, 10 casos. Arquivo [tests/integracao/qa_pendencias_p0_test.sh](../../tests/integracao/qa_pendencias_p0_test.sh), 188 linhas, sha256 `fdbb69c4e4465640d06e38b2fb57c8604c491d6ee03eefbcdbbac5a83fa39af1`. Resultado: 10 aprovados, 0 falhos.
- Cenarios proprios: O-5 (corpo vazio, JSON truncado, campo ausente, hash malformado, 5xx, destino pasta); token em corpo de erro; auxiliar em processo isolado; controle com hash remoto igual; RSK-43 com mutante do duplo.
- Documentacao conferida pelo QA: status F-23 a F-33, F-06 e F-31 parcial contra `docs/reviews/*` e a memoria do plano; RF-38(b) contra `commands/sync.sh` (linha 665); RF-48 contra `commands/sync.sh` (linha 343, antes da guarda de origem vazia, linha 464).
- Mutantes: m1 (sem `dbx_errors_redigir`, caso do token), m2 (classe vazia, corpo vazio), m3 (`exit 1` no lugar de `return 1`, envio nao segue), m4 (motivo vazio, hash malformado). Todos mortos.
- Achados:
  - QA-P0-01 (baixo): o comentario de `dbx_state_gravar` em [lib/state.sh](../../lib/state.sh) descrevia o ramo sem `sim` como "mapa carregado mais os novos", contra a emenda do RF-38(b). Status: **corrigido** no ciclo do developer, so em comentario (`git diff -w` confirma; state, json e composicao verdes).
- Veredito do QA: **Aprovado**, 2026-10-19.

## 7. Riscos e rollback

- Riscos residuais:
  - F-31 parcial: sinal durante `sync --receber` deixa `dbx-sync.XXXX` em `TMPDIR`; o restante (`lib/tmp`, OBS-02 a OBS-04) fica para a fase 2 do plano. Owner Senior Developer.
- Impacto: `upload` passa a informar classe e motivo no progresso quando a resposta do envio falha (RF-60(d)). Saida padrao e codigo de saida inalterados. RF-38(b) e RF-48 emendados (documental). Sem schema, sem migracao, sem dependencia nova.
- Rollback: `git revert <sha>` basta (sha do commit: PENDENTE). Nao ha migracao de dado.

## 8. Links e aceites

- Entradas de memoria: `2026-10-19-1023-plano-do-backlog`, `2026-10-19-1023-aceite-testes-qa-p0`; plano anterior `2026-10-18-1745-melhorias-em-fases` encerrado.
- Documentacao sincronizada: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md), [SKILLS_SYNC.md](../../.github/skills/SKILLS_SYNC.md), [mapa-modulos.md](../testes/mapa-modulos.md).
- Commit(s): PENDENTE
- PR: PENDENTE
- Tech Lead: **Aprovado — Tech Lead, 2026-10-19**, valida so com a suite completa local verde.
- Solicitante: aceite dos `qa-*` registrado em [2026-10-19-1023-aceite-testes-qa-p0](../../.github/agents/memoria/entradas/2026-10-19-1023-aceite-testes-qa-p0.md) (10 casos, sha256 `fdbb69c4…39af1`).
