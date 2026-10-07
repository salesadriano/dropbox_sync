# Limpeza da memoria compartilhada para baseline estrutural

## Objetivo

Reduzir `memoria/MEMORIA-COMPARTILHADA.md` para um formato duravel, curto e util para futuras execucoes dos agents, mantendo apenas decisoes estruturais e referencias necessarias para operacao do pacote.

## Criterios aplicados

- Manter apenas regras permanentes de persistencia.
- Manter somente decisoes com valor estrutural futuro.
- Consolidar decisoes repetidas em grupos unicos de governanca.
- Remover backlog historico concluido e substitui-lo por estado sintetico do baseline.
- Remover evidencias detalhadas de validacao ja preservadas neste diretorio de historico.
- Preservar ownerships criticos, artefatos padrao e riscos recorrentes.
- Manter um fluxo Mermaid apenas no nivel estrutural do pacote.

## Estruturas preservadas na memoria principal

- Contexto do pacote e estado da baseline.
- Regras de persistencia e uso da memoria.
- Decisoes estruturais ativas.
- Ownerships criticos por tema.
- Artefatos padrao permanentes.
- Estado atual do backlog estrutural.
- Riscos permanentes.
- Referencia cruzada para este historico.

## Estruturas removidas da memoria principal

- Ledger completo de DEC-001 a DEC-050 em granularidade cronologica.
- Backlog detalhado BL-001 a BL-053, pois estava integralmente concluido.
- Tabela extensa de evidencias de validacao por alteracao.
- Handoffs operacionais ja encerrados da linha de trabalho anterior.

## Resultado

A memoria principal passa a funcionar como baseline de consulta rapida para os agents, enquanto a cronologia detalhada e as evidencias permanecem rastreaveis em `memoria/historico/`.

## Impacto esperado

- Menor custo de leitura antes de novas execucoes.
- Menor redundancia entre memoria principal e historico.
- Preservacao das decisoes que continuam relevantes para qualquer projeto futuro que reutilize este pacote.
