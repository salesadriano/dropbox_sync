# Parecer de UX: relatorio final do `sync` com tamanho e motivo (RF-208)

Demanda `relatorio-com-tamanho-e-motivo` | Porte M | Papel: ux-expert | 2026-11-03
Base: RF-208, README (relatorio final por arquivo), secao 2 do registro e os casos `teste_relatorio_final_*` (leitura; a saida real nao foi executada por mim).

## Veredito: Aprovado com ressalvas (nenhum bloqueante)

## Achados

- Maior 1: `enviado=` / `falha=` ficam a uma letra de `enviados=` / `falhas=` (contadores). Um `grep falha` ou `grep enviado` no log mistura item e contador, e o olho do operador confunde as duas familias. Mitigar com nome distinto ou ao menos documentar o grep ancorado (`^falha=`).
- Maior 2: caminho com espaco ou `)` antes de ` (<tamanho>)` torna a linha ambigua para script que a parseie por regex (`enviado=a (b).txt (4 B)`). RF-59(c) garante uma linha so, nao a delimitacao. Quem automatiza deve usar `--json` (bytes); registrar isso no README como contrato: a linha legivel e para humano, nao para parse.
- Menor 1: unidades decimais (KB/MB) no relatorio contra KiB/MiB na barra de progresso. Coerente em destinos diferentes (progresso vai a stderr e e efemero; relatorio e permanente), e o RF-208(c) ja declara a diferenca. Risco real: o mesmo arquivo aparece como "1.0 MiB" no progresso e "1.1 MB" no relatorio. Basta uma frase no README; nao mudar.
- Menor 2: ordem itens-antes-dos-contadores e boa para o log de `nohup` (quem faz `tail` ve o total por ultimo e o detalhe logo acima). Em lote grande o bloco empurra os contadores para longe do inicio; aceitavel, pois os contadores seguem como ultimo bloco.
- Menor 3: `falha=` no stdout e `falha ...` no stderr duplicam a informacao quando os dois fluxos vao ao mesmo log (`nohup > log 2>&1`). E redundancia intencional (RF-59 permanece), mas o operador vera cada falha duas vezes com formatos diferentes. Aceitar; apontar no README que o stdout e o resumo final consolidado.
- Menor 4: no terminal a forma e `chave: valor`, sem terminal `chave=valor`; o `--json` tambem emite `enviado=...` legivel junto aos pares em bytes. Consistente com o restante do dbx e sem regressao.
- Acessibilidade: positivo. Sem cor, sem caractere especial, sem simbolo como unico indicador; a falha e dita por texto (`falha`, classe, motivo), compativel com leitor de tela e log em texto puro. Tamanho desconhecido omite o parenteses, sem placeholder enganoso; ponto decimal fixo (`12.4`), estavel para quem busca no log.

## Recomendacoes

1. Documentar no README que a linha legivel nao e interface de parse e que o contrato para script e o `--json` em bytes. (nao muda contrato)
2. Documentar o grep ancorado `^falha=` / `^enviado=` e a diferenca para os contadores. (nao muda contrato)
3. Uma frase no README sobre decimal (relatorio) contra binario (barra de progresso). (nao muda contrato)
4. Avaliar, em versao futura, renomear a linha de item (ex.: `arquivo_enviado=`) para eliminar o quase-homonimo. (MUDARIA CONTRATO: texto e, se refletido, nomes no `--json`; nao recomendado agora)
5. Considerar `--json` com tamanho tambem em campo legivel, sem necessidade: manter apenas bytes. (sem acao)

## Divergencias com requisitos/DS

Nenhuma. Nao ha componente visual; Design System e Storybook nao se aplicam a esta saida de CLI.
