# Validacao do QA: relatorio com tamanho e motivo (RF-208)

- Demanda: `relatorio-com-tamanho-e-motivo` | Porte: M | Log: `docs/prompts/2026-11-03_1203_relatorio-com-tamanho-e-motivo.md`
- Base: branch `feature/relatorio-com-tamanho-e-motivo` (implementacao `a509422`) sobre `origin/develop` @ `6c29d28`.
- Papel: QA Expert. Registro do Tech Lead: `docs/reviews/2026-11-03-1203-registro-relatorio-com-tamanho-e-motivo.md`.

## 1. Veredito

**Aprovado, sujeito ao aceite do solicitante da suite `qa_*`.** Nenhum defeito do produto encontrado em RF-208 (a-e). Nenhum achado bloqueante ou maior.

## 2. Suite independente

- `tests/integracao/qa_relatorio_final_test.sh`, 8 casos, duble de `curl` proprio (com `tests/support/lote_duplo.sh`), pelo `bin/dbx` real.
- sha256: `675f9aff24809b54a0135a7d52fa24515be9c3731004822a4b418c7200ca881e` (para o aceite, regra 12).
- Cobertura: fronteiras 999 B, 1000 B, 1999, 999999, 10^6, 10^9, 10^12 e 10^15 pelo relatorio; `--receber` com download falho (classe, motivo, `recebido_*`); `--bloco 1` em 3 diretorios (ordem de conclusao); `--paralelo 3` com 5 arquivos; `--dry-run` de envio e recebimento; nomes com quebra de linha, tabulacao e ESC; `--json` sem falha e o par `falha_caminho`/`falha_classe` colado; soma das linhas igual aos contadores.
- Mapa de contencao: `nenhum`. Os 4 casos do Senior Developer cobrem o caminho feliz de uma forma; os do QA usam arvores, falhas e fronteiras proprias, sem superconjunto de assertivas.
- Auditoria de casos inertes: a ausencia sob `--dry-run` tem controle positivo no mesmo caso (sem simulacao a linha existe), evitando assercao de ausencia sobre caminho que ninguem cria.

## 3. Vermelho contra a base

`git archive origin/develop bin lib commands` em diretorio temporario e `DBX_QA_EXEC=<tmp>/bin/dbx`, um caso por vez: **8 de 8 reprovam** sem a implementacao. Uma primeira medicao deu 1 caso verde (simulacao); foi corrigido com o controle acima e a medicao refeita deu 8/8.

## 4. Achados

| Sev. | Achado | Recomendacao |
|---|---|---|
| Informativo | O tamanho e **truncado**, nao arredondado: 999999 B sai `999.9 KB` e 1999 B sai `1.9 KB`; nunca aparece `1000.0 KB`. O teto em TB admite `1000.0 TB`. Comportamento coerente, travado pela suite. | Dizer "truncado" no RF-208/README, se o solicitante quiser a regra explicita. |
| Informativo | `tests/unit/json_test.sh` (caso `massa_adversarial_nao_e_construida_por_substituicao_de_comando`) reprova suite com `$(printf ...)` na massa; a primeira versao da suite caiu nele e foi corrigida (`$'...'`). | Nenhuma; a guarda funcionou. |
| Informativo | Contagem do briefing: `grep -c '^teste_' tests/integracao/sync_test.sh` = 96, e o inventario tem 90 + 4 = 94, com `--check` sem divergencia; o runner, com o filtro `sync_test.sh`, executou 2 arquivos (8 + 96 = 104). | Tech Lead confirmar a origem da diferenca de 2. |

## 5. Execucao seletiva (contagens literais)

- `bash tests/run.sh qa_relatorio_final_test.sh < /dev/null`: ok=8 nao_ok=0
- `bash tests/run.sh json_test.sh < /dev/null`: ok=66 nao_ok=0 (depois da suite escrita)
- `bash tests/run.sh harness_test.sh < /dev/null`: ok=23 nao_ok=0
- `bash tests/run.sh sync_test.sh < /dev/null`: 2 arquivos, 8 + 96 = 104 aprovados, 0 reprovados
- `bash tests/run.sh output_test.sh < /dev/null`: ok=32 nao_ok=0
- `shellcheck -x -s bash tests/integracao/qa_relatorio_final_test.sh`: sem aviso
- Suite completa: nao executada (fora do escopo da demanda).

## 6. Inventario

`docs/testes/inventario-de-testes.md`: linha no Resumo e secao da suite nova (aceite pendente, com sha256); 4 linhas `teste_relatorio_final_*` no `sync_test.sh` (90 -> 94); 1 linha no `output_test.sh` (31 -> 32); cabecalho e conferencia atualizados.
`sh scripts/inventario-de-testes.sh --check`: `arquivos: 117 | casos: 2921 | divergencias: 0`.

## 7. Recomendacao

Levar ao solicitante o aceite da suite pelo sha256 da secao 2. Liberar a demanda ao fechamento do Tech Lead. Ciclos de reprovacao no QA: 0.
