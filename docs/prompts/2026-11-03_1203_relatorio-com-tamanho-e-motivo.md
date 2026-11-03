# Relatorio final do `sync` com o tamanho de cada arquivo transferido e o motivo de cada falha

**Branch:** `feature/relatorio-com-tamanho-e-motivo` (de `origin/develop` @ `6c29d28`)
**Porte:** M. `sh scripts/porte.sh` (sem diff na abertura): `porte: P`; classificado M pelo gatilho nao mensuravel: contrato publico de saida do `sync` (RF-35, RF-36, RF-46, RF-59) e `commands/*.sh`.
**Issues:** nenhuma.
**PRs abertas no inicio:** #86 (`feature/arquivo-remoto-no-lugar-da-pasta`, toca `commands/sync.sh` na enumeracao remota, outra regiao do arquivo; sem dependencia, integracao textual trivial no merge).

## Prompt 1 — 2026-11-03 12:03

> no relatorio final, ao lado dos arquivos transferidos, inclua o tamanho dos arquivos, em MB, GB ou TB conforme o caso, nos caso de erro deve tambem apresentar o motivo da falhar

**Intencao principal:** o relatorio ao fim do `sync` passa a listar cada arquivo transferido com o seu tamanho em unidade legivel (KB, MB, GB ou TB, conforme a ordem de grandeza) e cada arquivo que falhou com o motivo da falha.

**Situacao atual (Tech Lead):** a lista por arquivo sai ANTES da execucao (plano, `transferir: <caminho>`, RF-41(d)), sem tamanho; ao fim saem so contadores (`enviados`, `recebidos`, `apagados`, `omitidos`, `falhas`, RF-36/RF-46); a falha por item vai so para stderr (`falha <caminho>: <classe> <resumo>`, RF-59(a)) e, no `--json`, viram `falha_caminho`/`falha_classe` sem o resumo.

**Inferencias adotadas (acrescimo compativel, RF-35):**
- Saida legivel: antes dos contadores, uma linha por arquivo concluido, `enviado: <caminho> (<tamanho>)` ou `recebido: <caminho> (<tamanho>)`, e uma por falha, `falha: <caminho> (<tamanho>): <classe> <resumo>`; tamanho omitido quando desconhecido.
- Tamanho em unidades decimais (1 KB = 1000 B), uma casa decimal a partir de KB (`12.4 MB`, `1.5 GB`, `2.0 TB`), bytes inteiros abaixo de 1 KB; o solicitante pediu MB, GB e TB, KB entra para arquivos pequenos.
- Saida estruturada (`--json`): nenhum campo existente muda; `falha_caminho`/`falha_classe` ganham `falha_motivo` (o resumo) e `falha_tamanho` (bytes, quando conhecido); apos eles, por arquivo concluido, `enviado_caminho`/`enviado_tamanho` ou `recebido_caminho`/`recebido_tamanho` (bytes).
- A linha `falha ...` em stderr (RF-59(a)) permanece como esta.
- Escopo: comando `sync` (o da producao). `upload`/`download` de pasta nao mudam nesta demanda.

**Achado durante a implementacao (Tech Lead):** sem terminal na saida padrao (o `nohup` da producao) o `dbx` ja emite o relatorio na forma `chave=valor` mesmo sem `--json`, e os pares `falha_caminho`/`falha_classe` de `RF-59(b)` so saem com `--json`. Por isso as linhas por arquivo (`enviado=`, `recebido=`, `falha=`) com tamanho legivel saem **em qualquer modo**, antes dos contadores, e os campos em bytes (`falha_motivo`, `falha_tamanho`, `enviado_caminho`/`enviado_tamanho`) ficam restritos ao `--json`. Requisito `RF-208` (v1.39; v1.38 reservada a PR #86).

## Prompt 2 — 2026-11-03

> accept the sha, legacy line too

**Decisao do solicitante:** aceite da suite do QA `tests/integracao/qa_relatorio_final_test.sh` (sha256 `675f9aff24809b54a0135a7d52fa24515be9c3731004822a4b418c7200ca881e`), regra 12; entrada de memoria `2026-11-03-1203-aceite-testes-qa-relatorio-com-tamanho-e-motivo`. A funcionalidade entra tambem na linha legada `support/bash-4.2`: branch `feature/relatorio-com-tamanho-e-motivo-bash42` sobre `origin/support/bash-4.2`, por cherry-pick dos commits da principal.

**Ajuste apos o aceite (Tech Lead):** a rodada de todas as suites do QA (`bash tests/run.sh qa_`) reprovou 1 caso de `tests/integracao/qa_robustez_rede_p2_test.sh` (ja aceita em 2026-10-27), que contava exatamente dois registros `falha_*` por item no `--json`; um segundo caso da mesma suite esperava a sequencia exata dos pares. Os dois casos passaram a esperar o bloco de quatro registros do `RF-208(d)`. Reaprovacao pendente do solicitante (regra 12), sha256 `b6ce38a8dccdcc650781bfe642798ded7827a9e7d6406f6682be21b1caa92477`.

## Prompt 3 — 2026-11-03

> accept the sha

**Decisao do solicitante:** reaprovacao da suite `tests/integracao/qa_robustez_rede_p2_test.sh` (sha256 `b6ce38a8dccdcc650781bfe642798ded7827a9e7d6406f6682be21b1caa92477`), regra 12; entrada de memoria `2026-11-03-1203-reaceite-testes-qa-robustez-rede-p2`.
