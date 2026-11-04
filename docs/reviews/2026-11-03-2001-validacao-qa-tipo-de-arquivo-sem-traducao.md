# Validacao do QA: tipo de arquivo sem traducao (DIV-395)

- Demanda: `tipo-de-arquivo-sem-traducao` | Porte: M | Log: `docs/prompts/2026-11-03_2001_tipo-de-arquivo-sem-traducao.md`
- Base: branch `feature/tipo-de-arquivo-sem-traducao` (correcao `60fe6d7`) sobre `origin/develop` @ `fc3ba8f`.
- Papel: QA Expert. Registro do Tech Lead: `docs/reviews/2026-11-03-2001-registro-tipo-de-arquivo-sem-traducao.md`.

## 1. Veredito

**Aprovado, sujeito ao aceite do solicitante da suite `qa_*`.** Nenhum defeito do produto na correcao. Nenhum achado bloqueante ou maior.

## 2. Suite independente

- `tests/integracao/qa_tipo_sem_traducao_test.sh`, 6 casos, pelo `bin/dbx` real, com `stat` duble que traduz `%F` fora de C ("arquivo comum", "diretorio") e duble de `curl`; `LANG=pt_BR.UTF-8` com e sem `LC_ALL` exportado.
- sha256: `83bff6c50d1ea8741c20b567cc2da06d9dcbf5989f1d00aabe106bc0c6b0b2c1` (para o aceite, regra 12).
- Cobertura: trava orfa retomada (saida 0, aviso); trava viva dita "trava ocupada" com o pid (saida 7, sem "ilegivel", sem pedir rm, sem chamada a API, trava preservada); `LC_ALL` exportado (viva e orfa); `diagnostico` com `trava=ok: viva`; cursor gravado e continuado na segunda execucao (`list_folder/continue`); controle negativo: trava com lixo continua "ilegivel" e nao e apagada.
- Mapa de contencao: `nenhum`. Os 4 casos do Senior Developer sao unitarios (funcao); os do QA passam pelo binario, com outras assertivas.
- Consumidores de `dbx_atributo_fd tipo` alem da trava: `_dbx_state_ler_limitado` (state.sh:250), `_dbx_state_cursor_abrir` (state.sh:2081, coberto aqui) e `_dbx_cmd_part_abrir` (cmd.sh:765, retomada de download, nao coberto pelo binario: ver pendencia).

## 3. Vermelho contra a base

`git archive origin/develop bin lib commands` em diretorio temporario, `DBX_QA_EXEC=<tmp>/bin/dbx`, um caso por vez: **5 de 6 reprovam** sem a correcao. O sexto (controle de lixo ilegivel) e **verde na base de proposito**: prova que a correcao nao torna legivel o que e ilegivel. Observacao: o caso do `LC_ALL` exportado tambem fica **verde na base** pelo binario, porque `_dbx_state_trava_ler` e `_dbx_state_cursor_abrir` declaram `local LC_ALL=C`, que herda o atributo exportado e protege o `stat`; ele e guarda de regressao, e o vermelho dessa condicao esta no caso unitario do Senior Developer (`dbx_atributo tipo` por caminho). Entao, dos casos de defeito: 5 de 5; do total: 5 de 6 (um e controle e outro e guarda).

## 4. Achados e varredura de utilitarios com saida textual

| Sev. | Achado | Recomendacao |
|---|---|---|
| Informativo | `commands/config.sh:120` e `:122`: `df -h` e `df -i` (`tail -n 1`) e `:128`: `mount | grep -E " on ..."`, so impressos no `[debug]`; nada interpreta o texto. `mount` usa " on " literal, nao traduzido. | Nenhuma; manter. |
| Informativo | `getenforce` (config.sh:133) e impresso, nao interpretado. | Nenhuma. |
| Informativo | Sem `date`, `sort`, `ls`, `ps`, `id` ou `locale` na saida textual interpretada em `lib/`, `commands/` e `bin/`; `wc -c` (numerico), `curl -w %{http_code}` (numerico), `find -printf %l` (bin/dbx:58) sao independentes de traducao; hostname vem de /proc. | Nenhuma. |
| Informativo | Os demais usos de `stat` (`lib/atributos.sh:106,116,118,153,155,184,186`) estao sob `LC_ALL=C`. Fora do modulo nenhum `stat -c/-f` (regra do cabecalho do arquivo). | Nenhuma. |

## 5. Execucao seletiva (contagens literais)

- `bash tests/run.sh qa_tipo_sem_traducao_test.sh < /dev/null`: ok=6 nao_ok=0
- `bash tests/run.sh json_test.sh < /dev/null`: ok=66 nao_ok=0 (com a suite escrita)
- `bash tests/run.sh harness_test.sh < /dev/null`: ok=23 nao_ok=0
- `bash tests/run.sh atributos_portavel_test.sh < /dev/null`: ok=15 nao_ok=0
- `sh scripts/lint.sh tests/integracao/qa_tipo_sem_traducao_test.sh`: sem aviso
- Suite completa: nao executada (fora do escopo).

## 6. Inventario

Linha no Resumo e secao da suite nova (aceite pendente, com sha256); `atributos_portavel_test.sh` 11 -> 15 (4 casos DIV-395 e autoria atualizada); conferencia do cabecalho. `sh scripts/inventario-de-testes.sh --check`: `arquivos: 119 | casos: 2939 | divergencias: 0` (o arquivo novo esta marcado `git add -N` porque a descoberta usa `git ls-files`; sem commit).

## 7. Recomendacao

Levar ao solicitante o aceite da suite pelo sha256 da secao 2. Ciclos de reprovacao no QA: 0. Pendencia opcional: caso pelo binario para `_dbx_cmd_part_abrir` (retomada de download) em pt_BR.
