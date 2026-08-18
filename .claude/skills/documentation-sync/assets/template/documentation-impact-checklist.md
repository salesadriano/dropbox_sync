# Checklist de Impacto Documental

Use este checklist apos cada implementacao ou bug fix.

## 1. Resumo da entrega
- Tipo da mudanca:
- Modulos afetados:
- Arquivos principais alterados:
- Ha impacto funcional? Sim ou nao.
- Ha impacto operacional ou de setup? Sim ou nao.
- Ha impacto em QA, evidencias ou cobertura? Sim ou nao.

## 2. Revisao obrigatoria
- [ ] README.md
- [ ] Documentacao principal do produto ou da solucao
- [ ] PRD, escopo, user stories ou casos de uso, quando existirem
- [ ] System Design, ARD, ADR ou diagramas arquiteturais, quando existirem
- [ ] Documentacao de QA, matriz de testes e rastreabilidade, quando existir
- [ ] Documentacao de UX ou Design System, quando existir
- [ ] Documentacao operacional, deploy ou runbooks, quando existir
- [ ] Registro tecnico, review de entrega ou changelog equivalente, quando existir

## 3. Perguntas de decisao
- A implementacao mudou comportamento observavel do sistema?
- A implementacao mudou endpoints, payloads, permissoes ou contratos?
- A implementacao mudou arquitetura, componentes, filas, workers ou deploy?
- A implementacao mudou requisitos formais, criterios de aceite ou dependencias de fechamento?
- A implementacao criou ou removeu evidencias de teste?
- Existe documento afirmando algo que deixou de ser verdadeiro?

## 4. Atualizacoes necessarias
- Documento:
  Motivo da alteracao:
- Documento:
  Motivo da alteracao:
- Documento:
  Motivo da alteracao:

## 5. Sem impacto documental
Se nenhum documento precisou ser alterado, registrar explicitamente:

"A revisao documental completa foi executada. Nao houve impacto material em setup, escopo, casos de uso, QA, matriz de rastreabilidade ou operacao que justificasse alteracao adicional de documentacao."

## 6. Registro final
- [ ] Registro tecnico, review ou artefato equivalente criado ou atualizado quando aplicavel
- [ ] Evidencias tecnicas e de teste coerentes com a documentacao
- [ ] Nenhuma afirmacao documental sem lastro no codigo ou nos testes