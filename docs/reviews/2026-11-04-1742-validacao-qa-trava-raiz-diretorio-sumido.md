# Validacao do QA: espera pela trava de raiz com o diretorio de estado sumido (DIV-396)

- Demanda: `trava-raiz-diretorio-sumido` | Porte: M | Log: `docs/prompts/2026-11-04_1742_trava-raiz-diretorio-sumido.md`
- Base: `feature/trava-raiz-diretorio-sumido` sobre `origin/develop` @ `7d974bc`; a mesma suite na linha legada.
- Papel: QA Expert (suite e casos), com o fechamento das medicoes pelo Tech Lead, porque o QA parou no limite de chamadas. Registro: `docs/reviews/2026-11-04-1742-registro-trava-raiz-diretorio-sumido.md`.

## 1. Veredito

**Aprovado, sujeito ao aceite do solicitante da suite `qa_*`.** Nenhum defeito na correcao. Um achado menor (motivo antigo apos sucesso) foi corrigido na mesma demanda.

## 2. Suite independente

- `tests/integracao/qa_trava_raiz_diretorio_sumido_test.sh`, 6 casos, pelas funcoes publicas de `lib/state.sh`, com detentor real em outro processo. Um duble de `mktemp` no `PATH` de quem espera solta o detentor no ponto exato (depois da conferencia do diretorio e antes de gravar o temporario da trava). Nao depende de carga nem de espera longa.
- Pelo `bin/dbx` a corrida nao se reproduz de forma deterministica: o `sync` de quem espera grava a propria trava de par no mesmo diretorio, e na CLI "sem escrita" vira aviso. O defeito e da funcao, e a suite a exercita direto.
- sha256: `ccf0339924721ba1b6d5f088a542a5e4574a790c44916fee3243af1e21ab85d9` (aceito pelo solicitante no prompt 2, regra 12).
- Cobertura: espera conclui com o diretorio apagado na janela (0, trava presente, 3 sondagens); quem recriou remove ao soltar; diretorio alheio permanece; diretorio 0500 continua 6 "sem escrita"; diretorio de outro dono continua 6 e intacto; diretorio que some a cada sondagem para no limite (51 sondagens), sai 6 e desfaz o que recriou.
- Mapa de contencao: o caso 1 do QA cobre o mesmo cenario de `pft_espera_adquire_quando_o_detentor_remove_o_diretorio_depois_da_checagem` por outro ponto de injecao (`mktemp` em vez de redefinir a sondagem) e com mais assertivas; os demais nao se sobrepoem. Nenhum caso removido.
- Limite: o caso do diretorio de outro dono redefine `_dbx_state_diretorio_confiavel` no roteiro do filho (sem root nao ha como criar diretorio alheio); o caso 0500 nao vale como root.

## 3. Vermelho contra a base

`git archive 7d974bc` em diretorio temporario, um caso por vez: **3 de 6 reprovam** (espera com diretorio apagado, quem recriou remove ao soltar, limite de repeticoes); os 3 de guarda passam na base de proposito.

## 4. Achados

| Sev. | Achado | Destino |
|---|---|---|
| Menor | Apos adquirir depois de uma sondagem que falhou, `DBX_STATE_MOTIVO` ainda trazia "diretorio de estado sem escrita". Hoje so e lido em falha, mas e uma armadilha. | Corrigido: o laco limpa o motivo ao adquirir. |

## 5. Execucao seletiva (contagens literais)

- `bash tests/run.sh qa_trava_raiz_diretorio_sumido_test.sh`: 6/0; no bash 4.2.46 real (`sh scripts/suite-bash42.sh`): 6/0.
- `bash tests/run.sh json_test.sh`: 66/0; `harness_test.sh`: 23/0; `composicao_test.sh`: 28/0.
- `sh scripts/lint.sh` sobre a suite: sem aviso (variaveis do filho exportadas, SC2097/SC2098).

## 6. Inventario

Secao da suite nova (aceite pendente), `state_trava_raiz_test.sh` 9 -> 12. `sh scripts/inventario-de-testes.sh --check`: 120 arquivos, 2948 casos, 0 divergencias (linha legada: 122, 2960, 0).

## 7. Recomendacao

Levar ao solicitante o aceite da suite pelo sha256 da secao 2. Ciclos de reprovacao no QA: 0.
