# Validacao independente do QA: suporte-bash-42, PARTE A (linha principal)

- Papel: QA Expert | Data: 2026-11-01 | Porte: G | Ciclo: 1 | Log: `docs/prompts/2026-11-01_1200_suporte-bash-42.md`
- Base: worktree `feature/suporte-bash-42` sobre `origin/develop` @ ace646d (commit eccbca0 + alteracoes nao commitadas)

## Escopo

Diff auditado: `install.sh`, `bin/dbx` (piso antes das bibliotecas), `lib/preflight.sh`, `commands/diagnostico.sh`, `scripts/empacotar.sh`, `scripts/suite-bash42.sh`. Requisitos: RF-201 a RF-205, TC-B42-09..22, DIV-385, DIV-389. Gatilho da Regra 6 de `protocolo-tdd`: download e escrita de arquivo a partir de `--canal`. Nao coberto aqui: RF-206 no CentOS 7 (prova do developer e parte B), E2E e banco (projeto CLI, nao aplicavel).

## Suite e sha256

`tests/integracao/qa_instalador_linha_b22_test.sh`: 17 casos, sha256 `46ce2a6cb21eb1a2cedd6fb6ea8766e601ec7d04c82d48985d3e6fad91f0902b`. Harness proprio, `harness_executar "$@"` no fim, contagem so por `_harness_contar`, sem rede (`git` e `gh` falsos no PATH, `FUNCAO_BAIXAR` substituida). Inventario: secao e linha de indice em `docs/testes/inventario-de-testes.md`; `--check`: 113 arquivos, 2870 casos, 0 divergencias (o arquivo entrou no indice do git por `git add -N`, sem commit).

| Ataque | Casos | Resultado |
|---|---|---|
| (1) `--canal` hostil (`;`, `$()`, crase, espaco, `&&`, pipe, aspas, `--upload-pack=`, `..`, vazio) | 3 | nada executado; canal chega ao git como um argumento apos `--branch`; destino, HOME e TMPDIR intactos |
| (2) rebaixamento e promocao com credencial e estado 0600 | 4 | aviso `TROCA DE LINHA`; mesmo sha256 e modo 0600; nada novo no HOME; sem aviso na mesma linha ou em instalacao nova |
| (3) fonte local sem preflight, modo 000, piso malformado; fonte baixada sem piso ou com piso acima do host | 5 | recusada antes de qualquer escrita, nomeando o canal certo |
| (4) `escolher_linha` 0.0, 3.99, 4.0..4.5, 4.10, 5.0, 10.0 e recusa 4.1 | 2 | conforme RF-201a |
| (5) `empacotar.sh` com `gh` falso em copia | 3 | legada: `--latest=false` e `--target <sha do HEAD>`; principal: so `--target`; release existente: upload e edit, sem create |

## Execucao (comandos reais, no worktree)

| Comando | Aprovados | Falhos |
|---|---|---|
| `bash tests/run.sh qa_instalador_linha_b22` | 17 | 0 |
| `bash tests/run.sh instalador_linha` | 34 | 0 |
| `bash tests/run.sh preflight` | 38 | 0 |
| `bash tests/run.sh json` (auditoria estatica, com a suite presente) | 62 | 0 |
| `bash tests/run.sh harness` (idem) | 23 | 0 |

A primeira rodada do `json` reprovou a suite do QA (substituicao de comando montando massa fixa); corrigido por sha256 literais e reexecutado verde. `shellcheck -x` da suite: 0 achados. Parada no primeiro erro conferida (as falhas intermediarias interromperam o runner). Suite completa nao rodada (fora do escopo desta etapa).

## Mutantes (aplicados e revertidos; sha256 de `install.sh` e `scripts/empacotar.sh` identico ao de antes)

| Mutante | Morto por |
|---|---|
| M1 comparacao 4.4 invertida em `escolher_linha` | dev e QA |
| M2 conferencia do piso apos o download removida | dev e QA (na 1a rodada so o dev: lacuna do QA, fechada com o caso de piso acima do host) |
| M3 `--latest=false` removido | dev e QA |
| M4 `--target` removido | dev e QA |
| M5 aviso de troca invertido | dev e QA |
| M6 recusa abaixo de 4.2 removida | dev e QA |

## Achados

- Menor: `comando_manual` (`install.sh`) imprime o `--canal` do proprio usuario sem aspas na mensagem de falha sem rede (observado: `... --canal x; echo PWN`). O instalador nao executa nada, mas o comando sugerido, se colado, executa o trecho. Recomendacao: citar com `printf %q` ou so sugerir o comando quando o canal casa `^[A-Za-z0-9._/-]+$`. Nao bloqueia: o texto vem de quem digitou o canal.
- Menor: versao `X-bash42-rc1` ou `X-bash420` nao casa `*-bash42` em `scripts/empacotar.sh` e seria publicada como Latest. Hoje nao existe; documentar que o sufixo e exatamente `-bash42`.
- Menor: `--target "$(git rev-parse HEAD)"` exige o commit no remoto; com HEAD nao enviado o `gh` falha. Documentar na rotina de release (publicar depois do push).
- Menor: o ramo de release existente (`gh release edit`) nao reaplica `--latest=false`; uma release legada criada a mao como Latest nao e corrigida.
- Ressalva herdada: TC-B42-18 (credencial e estado intactos) estava so por inspecao; agora provado pela suite do QA.
- Nenhum achado bloqueante ou maior. Nenhuma divergencia entre RF-201..205, implementacao e evidencia.

## Veredito

**Aprovado com ressalvas** para a PARTE A (linha principal), sob os achados menores acima e sujeito ao aceite explicito do solicitante da suite `qa_instalador_linha_b22` (sha256 acima). Ciclos de reprovacao: 0. Parte B (linha legada `support/bash-4.2`, RF-206 e RF-207) fora deste veredito.

## Ciclo 2 (apos as correcoes do Tech Lead aos achados menores)

- Correcoes verificadas: `--canal` fora de `^[A-Za-z0-9._/-]+$` ou iniciado por `-` e recusado na leitura das opcoes; sufixo da legada casa `-bash42($|[-.+])`; `gh release edit` recebe `--latest=false`. Os quatro achados menores ficam encerrados.
- Suite ajustada (17 casos, sha256 `46ce2a6cb21eb1a2cedd6fb6ea8766e601ec7d04c82d48985d3e6fad91f0902b`): o caso de canais hostis agora exige status 1, "Canal invalido", git nao chamado e nada escrito (9 canais, incluindo `-x`); o caso `..` segue passando (chega ao git e falha sem rede); `-bash42-rc1` entra no caso da release da legada; o ramo de release existente exige `edit` com `--latest=false`.
- Execucao: qa_instalador_linha_b22 17/17, json 62/62, harness 23/23, instalador_linha 36/36; shellcheck 0 achados.
- Inventario: linhas da suite do QA conferidas; o `--check` ainda acusa 3 divergencias fora da suite do QA, em `tests/unit/instalador_linha_test.sh` (casos novos do dev/TL sem linha: `teste_canal_com_trecho_de_shell_e_recusado_antes_de_qualquer_acao`, `teste_linha_instalada_reconhece_so_o_sufixo_bash42_exato`) e uma contagem a ajustar.
- Veredito do ciclo 2: **Aprovado**, sujeito ao aceite do solicitante do novo sha256.
