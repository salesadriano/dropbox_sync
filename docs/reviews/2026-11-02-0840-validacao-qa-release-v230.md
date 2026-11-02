# Validacao do QA — release-v230 (backport a linha principal, porte M)

Branch `feature/falha-fechada-sem-localidade` (origin/develop @ 12a5086, bash >= 4.4). Papel: QA Expert. Validacao seletiva pelos modulos atingidos (Regra 8 de protocolo-tdd); sem suite completa.

## Veredito: APROVADO (sem achados bloqueantes ou maiores)

## 1. Escopo do que veio
`git diff --name-only`: commands/sync.sh, lib/filtro.sh, lib/json.sh, lib/sync.sh, docs (requisitos, inventario), testes (sync_test, filtro_test, qa_docs_aliases_p4, qa_exclusao_sem_localidade_b42 nova). Nao ha lib/ref.sh, piso, versao nem harness do 4.2. Vieram somente as duas correcoes (QA-B42-01 e tokenizador em pedacos). Conforme.

## 2. Falha fechada sem localidade (QA-B42-01 / RF-54(f2) / DIV-391)
- Verde na arvore: qa_exclusao_sem_localidade 6/6; qa_docs_aliases_p4 16/16; filtro 93/93; sync_test* 97/97. O sync_test inclui `com_localidade_o_espelhar_fora_do_ascii_nao_muda` (comportamento anterior preservado), `sem_localidade_caminho_ascii_so_no_destino_continua_sendo_apagado`, ramo de pasta e aviso unico.
- Vermelho: copia em scratchpad com lib/filtro.sh, lib/sync.sh e commands/sync.sh de HEAD. `qa_b42_enviar_espelhar_remoto_nao_ascii_nao_e_apagado` reprova ("nenhum delete de caminho nao ASCII"). O harness para no primeiro erro (Regra 9), entao os outros 5 casos ficaram nao executados na copia vermelha.
- Com localidade presente o --espelhar apaga como antes (caso acima).

## 3. json em pedacos de 4096 (equivalencia)
Casos novos em tests/unit/json_test.sh, com esperado por literais (nao pela propria analise):
- `qa_rel230_03_fronteira_4096_escape_e_multibyte_no_valor`: cargas `\n`, `é`, `é`, `\"`, `\\`, `{[,:]}` com inicio nos indices 4094 a 4098; valores `a` e `b` posterior exatos.
- `qa_rel230_03_fronteira_4096_delimitador_estrutural`: `[`, `,`, `{` e chave multibyte nas mesmas posicoes.
- `qa_rel230_03_documento_longo_com_muitos_pedacos`: mais de 20000 caracteres, varios pedacos.
- `qa_rel230_03_controle_cru_depois_da_4096_continua_recusado`: \001, \037, \177 em 4095, 4096, 4097, 4100, 9000, 12288 recusados com motivo `controle`; tab e quebra crus seguem tolerados.

Resultado: json 66/66 na arvore. Os 4 casos novos tambem passam com o lib/json.sh de HEAD (equivalencia byte a byte). Mutantes na copia: pedaco de 4095 (morto) e controle checado so no primeiro pedaco (morto).
Inventario atualizado (contagem 62 para 66 e 4 linhas novas).

## 4. sha256
- tests/integracao/qa_exclusao_sem_localidade_b42_test.sh: 7654cd1a2c966e00aa6d51519962bf3195c2ce76df62b56db809ba4c91e0d033 (confere com o briefing)
- tests/unit/json_test.sh (alterada, +4 casos qa_rel230_03): 183c16f23d3e1c5ac312c45d6c5b9f5e514ff9d4709610b44e3528453851db4e

## Observacoes
- Aceite do solicitante (regra 12) sobre os 4 casos novos de json pendente; a suite b42 ja foi aceita na linha legada.
- Suite completa nao executada (fora do escopo da demanda).
