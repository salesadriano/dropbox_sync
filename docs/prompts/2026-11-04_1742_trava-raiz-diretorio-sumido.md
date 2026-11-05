# Corrida entre quem solta a trava de raiz e quem espera por ela (pft03)

**Branch:** `feature/trava-raiz-diretorio-sumido` (sobre `origin/develop` @ `7d974bc`) e `feature/trava-raiz-diretorio-sumido-bash42` (sobre `origin/support/bash-4.2` @ `35b556f`), uma PR por linha.
**Porte:** M previsto (defeito de concorrencia na trava, caminho de erro); `sh scripts/porte.sh` medido sobre o diff no fechamento.
**Issues:** nenhuma.

## Prompt 1 — 2026-11-04

> abra a demanda do pft03 nas duas linhas

**Intencao principal:** eliminar a causa da falha intermitente de `pft03_espera_cobre_a_trava_e_conclui_quando_a_primeira_termina` (`tests/unit/state_trava_raiz_test.sh`), que derrubou a suite completa legada quatro vezes nas demandas DIV-395 e release 2.3.4, nas duas linhas.

**Inferencias adotadas:**
- Nao e falta de folga: quem espera sai com 6 (`permissao`), nao com 7 (`conflito`). Sonda do Tech Lead no conteiner `centos:7` sob carga, 15 repeticoes do cenario do teste: 4 sairam `6|diretorio de estado sem escrita: <xdg>/dbx`. Corrida entre o detentor, que ao soltar desfaz o diretorio de estado que criou (`_dbx_state_trava_raiz_desfazer_diretorio`), e quem espera, que o recria a cada sondagem (`_dbx_state_trava_raiz_garantir_diretorio`).
- Na linha principal (bash 5.3 do host) o mesmo arquivo passou 10 de 10 sob carga, mas a logica e a mesma: a correcao vai as duas linhas, como pedido.
- Efeito em producao: com `--esperar N`, quando o diretorio de estado nasce na execucao que detem a trava, quem espera pode desistir com um erro de permissao enganoso em vez de adquirir a trava.
- O teste `pft03` nao tem a folga alterada; a demanda prova a corrida por um caso deterministico e corrige o codigo.

## Prompt 2 — 2026-11-04

> accept the sha, both lines

**Intencao principal:** aceite (regra 12) da suite do QA `qa_trava_raiz_diretorio_sumido_test.sh`, sha256 `ccf0339924721ba1b6d5f088a542a5e4574a790c44916fee3243af1e21ab85d9`, nas duas linhas.

**Inferencias adotadas:** o arquivo e identico nas duas linhas e passa no bash 4.2.46 real; o aceite vale para ambas.
