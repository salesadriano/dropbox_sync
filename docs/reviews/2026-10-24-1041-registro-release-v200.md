# Release v2.0.0: versao, instalador, notas e publicacao

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "atualize o release": publicar a release nova com o que entrou na `master` desde a `v1.2.0` |
| Porte | M - toca o script de publicacao (pipeline de distribuicao) e a versao exposta por `dbx --version` e `install.sh --version`; nao altera arquitetura, schema nem integracao externa |
| Log de prompt | `docs/prompts/2026-10-24_1041_release-v200.md` |
| Branch / base | `chore/release-v200` sobre `origin/develop` @ `261fecb` |
| Agents | Tech Lead (implementacao e registro), `qa-expert` (validacao independente) |
| Data | 2026-10-24 |

## 2. Causa ou decisao

- **Versao 2.0.0** (decisao do solicitante): `9407c9a refactor(state)!` declara `BREAKING CHANGE`; por semver a versao principal sobe. `lib/cli.sh` dizia `1.3.0` (checkpoint `915cb52`) e `install.sh`/`README.md` ainda `1.2.0`; os tres passam a `2.0.0`.
- **Notas em `docs/releases/v<versao>.md`**: `scripts/empacotar.sh --publicar` tinha titulo e corpo da v1.2.0 fixos no script e publicaria notas velhas em qualquer versao. Agora le o arquivo da versao (primeira linha `# <titulo>`), recusa antes de empacotar se ele faltar ou o titulo vier vazio, e, quando a release ja existe, atualiza titulo e notas alem dos artefatos. Alternativa descartada: reescrever o texto fixo no script a cada versao (o defeito volta na proxima).
- **Publicacao** (decisao do solicitante): depois dos merges `chore/release-v200` -> `develop` e `develop` -> `master`, o Tech Lead roda `bash scripts/empacotar.sh --publicar` na `master` sem nova confirmacao.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/cli.sh` | Alterado (`DBX_CLI_VERSAO='2.0.0'`) | +1/-1 |
| `install.sh` | Alterado (`VERSAO_INSTALADOR="2.0.0"`) | +1/-1 |
| `scripts/empacotar.sh` | Alterado (notas por arquivo, checagem antecipada, `gh release edit`) | +15/-14 |
| `README.md` | Alterado (nome do tarball) | +2/-2 |
| `docs/releases/v2.0.0.md` | Novo (notas da release) | +35 |
| `docs/prompts/2026-10-24_1041_release-v200.md` | Novo | - |
| `docs/reviews/2026-10-24-1041-registro-release-v200.md` | Novo | - |

Total de linhas de codigo (producao e teste, sem documentacao): **34**.

## 4. Testes rodados

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| empacotamento local | `scripts/empacotar.sh`, `lib/cli.sh` | `bash scripts/empacotar.sh` | 1 | 1 | 0 | - |

- Saida literal do empacotamento: `[ok] Teste de execucao do pacote: dbx 2.0.0 (aprovado)`; `bash install.sh --version` -> `install.sh versao 2.0.0`.
- Red observado: Nao aplicavel: nenhum caso da suite fixa a versao nem exercita `scripts/empacotar.sh`; a mudanca e de dado (versao) e do caminho `--publicar`, que publica no GitHub e so roda na liberacao.
- Parada no primeiro erro (Regra 9): `tests/run.sh` para na primeira falha (harness do projeto).
- Barreiras estaticas: `sh scripts/lint.sh` sobre `scripts/empacotar.sh`, `install.sh` e `lib/cli.sh`: sem apontamento.
- Testes de seguranca e acesso (Regra 6): Nao aplicavel: nenhuma rota, credencial ou entrada de usuario tocada.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: CLI sem formulario.
- Suite completa local no push para a PR (Regra 8): ver a linha registrada por `sh scripts/suite-completa.sh` antes do push.

## 5. Gates

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; checklist aplicado integralmente; itens nao aplicaveis listados na secao 4 | nenhum | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + boas praticas de shell (`shellcheck`); checklist aplicado integralmente | nenhum: mudanca restrita a script de distribuicao e constantes de versao, sem camada nova | Aprovado |

- Ciclo: 1.
- `sh scripts/alteracoes-externas.sh --detectar`: limpo apos `--registrar` de cada arquivo editado.

## 6. QA

Validacao independente (`qa-expert`, ciclo 1), sem arquivo `qa-*` (nao ha codigo novo testavel alem do empacotador, exercitado direto):

- Cenarios: empacotamento local (`dbx 2.0.0 (aprovado)`), `install.sh --version` e `dbx --version` (`2.0.0`), lint dos tres scripts, busca de versao velha fora de docs historicos (nenhuma), fidelidade das notas contra `git log v1.2.0..HEAD`, ajuda do `dbx` e o `BREAKING CHANGE` de `9407c9a` (as quatro incompatibilidades conferem).
- Achados (todos menores) e destino:
  1. `docs/releases/v2.0.0.md:5`, remocao do `dbx.db` pelo `unlink` imprecisa: corrigido (o `unlink` remove o diretorio de estado inteiro, `commands/unlink.sh:72-104`).
  2. Faltavam `fix(sync)` e `fix(path)`: corrigido (secao *Correcoes*).
  3. Sem `gh`, `--publicar` avisa e sai 0: comportamento anterior, mantido; a publicacao e conferida por `gh release view` depois de rodar.
  4. Release existente so recebia artefatos: corrigido (`gh release edit` com titulo e notas).
  5. Notas checadas so depois do pacote e titulo vazio aceito: corrigido (checagem antes de empacotar, titulo vazio recusado).
- Veredito do QA: Aprovado com ressalvas, 2026-10-24; ressalvas 1, 2, 4 e 5 corrigidas, 3 justificada.

## 7. Riscos e rollback

- Riscos residuais: a tag `v2.0.0` nasce no HEAD da `master` no momento do `gh release create`; publicar so depois do merge de `develop` -> `master` com este commit (owner: Tech Lead).
- Impacto: versao exposta por `dbx --version` e `install.sh --version` passa a `2.0.0`; nenhum contrato de saida, schema ou dependencia novo.
- Rollback: reverter o merge; se a release ja tiver sido publicada, `gh release delete v2.0.0 --cleanup-tag`.

## 8. Encerramento

Pendente: PR para `develop`, merge do solicitante, PR `develop` -> `master`, publicacao da release.
