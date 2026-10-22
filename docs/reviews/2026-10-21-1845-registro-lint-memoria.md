# Lint sem estouro de memoria (scripts/lint.sh)

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "sim, edite o wslconfig e abra a demanda do lint". Origem: a sessao anterior travou a maquina; o journal do boot anterior mostra OOM do shellcheck em 2026-10-21 16:34 (anon-rss 18623392 kB) e 17:05 (10015920 kB), e falha de alocacao do kernel as 17:51. |
| Porte | M - comecou P e subiu para M porque `git diff --numstat` de producao e teste somava 84 linhas na primeira versao (scripts/lint.sh 39, scripts/tests/lint.bats 45), acima de 50. Sem contrato, CLI do produto, schema, auth, segredo, fronteira, pipeline (nao ha `.github/workflows`) ou dependencia. `scripts/porte.sh` nao existe no projeto nem no plugin 1.0.6; porte medido pelos criterios de `fluxo-p.md`. |
| Log de prompt | `docs/prompts/2026-10-21_1845_lint-sem-estouro-de-memoria.md` |
| Branch / base | `chore/lint-memoria` sobre `origin/develop` @ `dd129fb` |
| Agents | Implementacao pelo Tech Lead (iniciada no fluxo P e mantida apos subir para M; desvio registrado: em M seria senior-developer). Validacao independente: qa-expert. Registro: documentation-writer. Commit: commit-writer. |
| Data | 2026-10-21 |

## 2. Causa ou decisao

Causa: o lint documentado (`shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh`) roda num processo unico; com `external-sources=true` no `.shellcheckrc` cada arquivo reanalisa a cadeia de `source`. Picos medidos por arquivo: `commands/download.sh` 8992516 KB / 49,2 s; `commands/upload.sh` 6268488 KB / 24,2 s; `bin/dbx` 4539828 KB / 28,1 s; `commands/sync.sh` 3236480 KB / 12,3 s; `lib/cmd.sh` 1237600 KB / 5,0 s. O `.wslconfig` dava 24 GB ao WSL num host de 31,8 GB, o que congelou o Windows.

Decisao do solicitante (AskUserQuestion: "Completo, sequencial (Recomendado)"). Abordagens:

- (a) Completo sequencial com teto de 12 GB: 142 s, pico 9,2 GB, 0 achados. Escolhida.
- (b) Rapido sem seguir `source` + `--completo` opcional: 9,16 s, pico 238240 KB, mas 1 falso positivo SC2034 em `commands/upload.sh:84` (DBX_CLI_PROGRESSO) e perda das checagens entre arquivos.
- (c) So rapido: perde SC2034/SC2154 entre arquivos de vez.

Fora do repositorio (nao entra no diff): `C:\Users\Sales\.wslconfig` passou de `memory=24GB` para `memory=16GB` e `swap=8GB`; backup `.wslconfig.bak-2026-10-21`; vale apos `wsl --shutdown` pelo solicitante.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `scripts/lint.sh` | Novo. Um shellcheck por arquivo via `xargs -0 -n 1 -P`; `LINT_PARALELO` padrao 1; `LINT_MEMORIA_MB` padrao 12288; teto por `systemd-run --user -p MemoryMax -p MemorySwapMax=0` ou `ulimit -v` (`LINT_SEM_SYSTEMD=1` ou sem systemd); saida 0/1/2; saida 1 sem texto acusada como "interrompido" pelo teto; `LINT_PARALELO`/`LINT_MEMORIA_MB` nao inteiros ou 0 saem com 2. | +44/-0 |
| `scripts/tests/lint.bats` | Novo (testes do desenvolvedor, 4 casos, shellcheck duble) | +45/-0 |
| `scripts/tests/qa-lint.bats` | Novo (suite do QA, 10 casos) | +93/-0 |
| `CLAUDE.md` | Alterado: linha do linter trocada por `sh scripts/lint.sh` | +1/-1 |
| `README.md` | Alterado: linha do linter trocada por `sh scripts/lint.sh` | +1/-1 |
| `.github/agents/memoria/entradas/2026-10-21-1845-lint-sequencial.md` | Novo (decisao) | documentacao |
| `docs/prompts/2026-10-21_1845_lint-sem-estouro-de-memoria.md` | Novo | documentacao |

Total de linhas de codigo (producao e teste, sem documentacao): **182** (44 + 45 + 93).


## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `scripts/tests/lint.bats` | `scripts/lint.sh` | `npx --yes bats@1.13.0 --abort scripts/tests/lint.bats` | 4 | 4 | 0 | 0,79 s |
| `scripts/tests/qa-lint.bats` | `scripts/lint.sh` | `npx --yes bats@1.13.0 scripts/tests/qa-lint.bats` | 10 | 9 | 0 | 1,08 s (1 skip) |

- `qa-lint.bats`: 1 skip (caso 10: shellcheck real fora de `/usr/bin`; o binario esta em `~/.local/bin`).
- Red observado: (1) mutando a condicao de saida vazia em `lint.sh`, o caso 3 de `lint.bats` falhou; (2) antes da correcao do QA, `qa-lint.bats` casos 1, 2 e 5 falharam (nome com espaco, nome com aspas, `LINT_PARALELO=0`).
- Parada no primeiro erro (Regra 9): `bats --abort`.
- Barreiras estaticas: `sh scripts/lint.sh scripts/lint.sh` exit 0. Execucao completa real `LINT_PARALELO=1 LINT_MEMORIA_MB=12288 sh scripts/lint.sh`: 141,67 s, exit 0, pico usado 9235 MB (amostra de `free -m` por segundo). Teto: `LINT_MEMORIA_MB=500 sh scripts/lint.sh bin/dbx` -> "lint: bin/dbx interrompido (saida 1; teto de 500 MB?)", exit 1.
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: ferramenta de desenvolvimento, sem entrada de usuario do produto.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: ferramenta de desenvolvimento, sem formulario.
- Suite completa local no push para a PR (Regra 8): Ainda nao houve push para a PR

## 5. Gates

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | Ciclo 1: achados do QA (secao 6), corrigidos no ciclo 2. Ciclo 2: nenhum. | Aprovado (ciclo 2) |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; `Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados` | Nota: SC3045 suprimido com justificativa no fallback `ulimit -v` (dash e bash aceitam). | Aprovado |

- Ciclo: 2; achados do ciclo 1 (secao 6) corrigidos.
- `sh scripts/alteracoes-externas.sh --detectar`: exit 0 antes do gate e apos registrar. A linha de base da worktree foi criada tarde (o `--inicial` rodou primeiro no checkout principal) e os arquivos do Tech Lead foram registrados com `--registrar`.

## 6. QA

Validacao independente (porte M), qa-expert.

- Ciclo 1: Aprovado com ressalvas.
  - Maior, `scripts/lint.sh:38`: `printf '%s\n' | xargs` partia nomes com espaco e quebrava com aspas.
  - Maior, `scripts/lint.sh:38`: `LINT_PARALELO=0` virava `xargs -P 0` (paralelismo ilimitado).
  - Menor: `lint.bats` nao cobria esses casos (coberto em `qa-lint.bats`).
  - Sem achado: valores nao numericos falham, arquivo inexistente sai 1, saida 2 com texto preservada, achado num arquivo nao impede os demais, execucao sem argumentos de outro diretorio.
- Ciclo 2 (correcao pelo Tech Lead): `printf '%s\0' | xargs -0` e validacao por `case` de inteiros >= 1. Reexecucao: `qa-lint.bats` 10 total, 9 ok, 0 falhos, 1 skip.
- Arquivo do QA: `scripts/tests/qa-lint.bats`, sha256 `8203f5b0117d3e5a7c239173698f2021f3056bf6c80d488d620cd9c60d92a0e9`.
- Veredito do QA: Aprovado com ressalvas, 2026-10-21; ressalvas corrigidas no ciclo 2.

## 7. Riscos e rollback

- Riscos residuais:
  - O protocolo-conformidade de pacote (`.github/skills/protocolo-conformidade/references/comandos-locais.md:91`) ainda sugere `git diff --name-only -- '*.sh' | xargs -r shellcheck` (processo unico). E skill do pacote upstream ai_team; pendencia do Tech Lead para o pacote, nao editada aqui.
  - A execucao completa leva cerca de 142 s.
- Impacto: Nenhum contrato, CLI do produto ou pipeline; muda so o comando de lint documentado.
- Rollback: `git revert <sha>`.

## 8. Links e aceites

- Entradas de memoria: `2026-10-21-1845-lint-sequencial`
- Documentacao sincronizada: `CLAUDE.md`, `README.md`
- Commit(s): `pendente`
- PR: `pendente`
- Tech Lead: **Aprovado**, 2026-10-21
- Solicitante: "Aprovo" (AskUserQuestion, 2026-10-21) a `scripts/tests/qa-lint.bats`, sha256 `8203f5b0117d3e5a7c239173698f2021f3056bf6c80d488d620cd9c60d92a0e9`.
