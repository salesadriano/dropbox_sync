# Release v2.2.0

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "make release and publish": publicar a release com o que entrou na `develop` desde a `v2.1.0` |
| Porte | P - so constantes de versao (2 linhas de codigo) e notas; sem contrato, schema, auth, segredo, dependencia ou pipeline novos; o empacotador e o da v2.1.0 |
| Log de prompt | `docs/prompts/2026-10-31_2330_release-v220.md` |
| Branch / base | `chore/release-v220` sobre `origin/develop` @ `23a742b` |
| Agents | Tech Lead (Fluxo P) |
| Data | 2026-10-31 |

## 2. Causa ou decisao

Versao **2.2.0** (semver menor): sync, upload e download em blocos por diretorio (#70) e recurso novo compativel; a area temporaria por arquivo de teste (#71) resolve o problema conhecido da v2.1.0; #68 (protocolo) nao toca o produto. `lib/cli.sh`, `install.sh` e `README.md` passam a `2.2.0`; notas em `docs/releases/v2.2.0.md`, lidas por `scripts/empacotar.sh --publicar`. Publicacao depois dos merges `chore/release-v220` -> `develop` -> `master`, como na v2.1.0.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh` | Alterado (versao) | +1/-1 |
| `install.sh` | Alterado (versao) | +1/-1 |
| `README.md` | Alterado (nome do pacote) | +2/-2 |
| `docs/releases/v2.2.0.md` | Novo | - |
| `docs/prompts/2026-10-31_2330_release-v220.md` | Novo | - |

Total de linhas de codigo (producao e teste, sem documentacao): **2**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| empacotamento local | versao e pacote | `bash scripts/empacotar.sh` | 1 | 1 | 0 | - |

- Saida literal: `[ok] Teste de execucao do pacote: dbx 2.2.0 (aprovado)`; `bash install.sh --version` -> `install.sh versao 2.2.0`; `bash bin/dbx --version` -> `dbx 2.2.0`.
- Red observado: Nao aplicavel: mudanca de dado (versao); nenhum caso da suite fixa a versao (`grep -rl 2.1.0 tests` vazio).
- Parada no primeiro erro (Regra 9): `tests/run.sh` para na primeira falha.
- Barreiras estaticas do modulo tocado: nenhuma string `2.1.0` restante em `lib/`, `commands/`, `bin/`, `install.sh`, `uninstall.sh`, `scripts/`, `README.md`.
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: sem rota, segredo ou entrada nova.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI.
- Suite completa local no push para a PR (Regra 8): `sh scripts/suite-completa.sh` sobre o commit da release; resultado no corpo da PR.

## 5. Gates

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; checklist aplicado integralmente; itens nao aplicaveis listados na secao 4 | nenhum | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell; checklist aplicado integralmente | nenhum: so constantes de versao e notas | Aprovado |

- Ciclo: 1
- `sh scripts/alteracoes-externas.sh --detectar`: limpo antes do commit.

## 6. QA

- QA: amostragem 1 de 5 - nao validada (Fluxo P).
- Veredito do QA: Nao aplicavel (amostragem nao sorteada), 2026-10-31.

## 7. Riscos e rollback

- Riscos residuais: a tag `v2.2.0` nasce no HEAD da `master` no `gh release create`; publicar so depois do merge de `develop` -> `master` com este commit (owner: Tech Lead). O push da branch e as PRs podem depender do solicitante enquanto a guarda de push do plugin avaliar o checkout principal.
- Impacto: versao do `dbx --version` e do `install.sh`; nenhum contrato novo.
- Rollback: reverter o merge; se ja publicada, `gh release delete v2.2.0 --cleanup-tag`.

## 8. Links e aceites

- Entradas de memoria: Nenhuma: sem decisao duravel.
- Documentacao sincronizada: `README.md`, `docs/releases/v2.2.0.md`.
- Commit(s): ver historico da branch.
- PR: a abrir.
- Tech Lead: **Aprovado**, 2026-10-31 - condicionado a suite completa oficial verde sobre o commit.
- Solicitante: Nao aplicavel: sem arquivo do QA.
