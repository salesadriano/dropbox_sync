# Ambiente do shell do operador neutralizado: CDPATH, BASH_ENV, ENV, SHELLOPTS e BASHOPTS

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "in prod i recive the error below" (`sync --enviar ... --espelhar --confirmar` com erro aritmetico em `commands/sync.sh` durante "enumerando diretorios locais") |
| Porte | M - defeito em producao e guarda destrutiva (enumeracao da arvore errada sob `--espelhar`); 24 linhas de produto |
| Log de prompt | `docs/prompts/2026-11-02_1115_ignorar-cdpath.md` |
| Issues | nenhuma |
| Branch / base | `feature/ignorar-cdpath` sobre `origin/develop` @ `0c80a1e`; a mesma correcao na linha legada em `chore/release-v230-bash42` |
| Agents | Tech Lead (implementacao, correcao minima e urgente), QA Expert (2 ciclos) |
| Data | 2026-11-02 |

## 2. Causa ou decisao

- Causa (reproduzida): `CDPATH` exportado no ambiente de producao. O `cd` de nome relativo da travessia (`lib/walk.sh`) passa pelo `CDPATH`: com `CDPATH=.`, imprime o destino no stdout, que e a lista de diretorios `n<TAB>caminho\0` (o registro corrompido virou o operando do erro aritmetico); com `CDPATH` apontando outra arvore, entra na pasta homonima de la, e a enumeracao le a arvore errada.
- O QA achou a mesma classe em `BASH_ENV`/`ENV` (arquivo executado pelo bash antes do `dbx`) e em `SHELLOPTS`/`BASHOPTS` exportados (`set -f`, `noclobber`, opcoes de glob).
- Decisao: `unset CDPATH` na partida de `bin/dbx`; com `BASH_ENV`/`ENV` definidos ou `SHELLOPTS`/`BASHOPTS` exportados (`compgen -e`, sem processo), o `dbx` recomeca uma vez com `env -u` das cinco variaveis. Sem marca contra laco: o processo novo nasce sem elas. Alternativa descartada: `cd -- "./$nome"` em cada `cd` (deixaria de fora `BASH_ENV` e opcoes do shell, e qualquer `cd` novo reabriria o defeito). Solicitante decidiu corrigir tudo nesta release (`DIV-392`).

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `bin/dbx` | Alterado: recomeco limpo e `unset CDPATH` | +24/-0 |
| `tests/integracao/sync_test.sh` | Alterado: `teste_cdpath_do_ambiente_nao_suja_nem_desvia_a_enumeracao`, `teste_bash_env_e_opcoes_exportadas_nao_mudam_o_plano` | +47/-0 |
| `tests/integracao/qa_cdpath_test.sh` | Novo (suite do QA, 8 casos, sha256 `57be5d41...326d`, aceita) | novo |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | v1.36, `DIV-392` | doc |
| `docs/testes/inventario-de-testes.md` | 115 arquivos, 2897 casos, 0 divergencias (legada: 117, 2909, 0) | doc |

## 4. Testes rodados

| Arquivo de teste | Item | Host (bash 5.3) | CentOS 7 (bash 4.2) |
|---|---|---|---|
| `sync_test.sh` | `bin/dbx` | APROVADA | APROVADA |
| `qa_cdpath_test.sh` | `bin/dbx` | APROVADA (8/8) | APROVADA |
| `cli_test`, `preflight_test`, `comandos_test`, `perfis_test`, `disponibilidade_automatica_test`, `debug_ajuda_progresso_test` | ponto de entrada | APROVADA | `preflight_test`, `bash42_auditoria`: APROVADA |

- Red observado: `teste_cdpath_*` reproduziu o erro de producao ("arithmetic syntax error ... local/sub\n1") antes da correcao; `teste_bash_env_*` reprovou sem o recomeco (`noclobber` do `BASH_ENV` quebrou `lib/hash.sh`); a suite do QA reprova contra `bin/dbx` de `HEAD`.
- QA, ciclo 2: com `QA_EXTRA` = `BASH_ENV`, `ENV`, `SHELLOPTS=noglob|xtrace|errexit|nounset`, `BASHOPTS=dotglob|nullglob|failglob|nocaseglob`, desfecho identico a linha de base; argumentos com espaco e glob, stdin (`upload -`, `--senha-stdin`) e codigo de saida preservados; vinculo simbolico e caminho relativo funcionam.
- Lint: `shellcheck -x -s bash bin/dbx` sem aviso.
- Suite completa local: resultado no corpo da PR de cada linha.

## 5. Gates

| Gate | Achados | Veredito |
|---|---|---|
| `protocolo-tdd` | nenhum | Aprovado |
| `protocolo-conformidade` | nenhum; correcao no ponto unico de entrada, antes de qualquer biblioteca | Aprovado |

## 6. QA

`docs/reviews/2026-11-02-1115-validacao-qa-ignorar-cdpath.md`: ciclo 1 aprovado (sem bloqueante ou maior); ciclo 2 aprovado com ressalva menor (marca herdada desligaria a protecao), tratada: a marca saiu.

## 7. Riscos e rollback

- Operador que dependa de `BASH_ENV` para preparar o `dbx` deixa de te-lo aplicado (por desenho).
- Contorno em versoes anteriores: `env -u CDPATH -u BASH_ENV dbx ...`.
- Rollback: `git revert` do commit.
