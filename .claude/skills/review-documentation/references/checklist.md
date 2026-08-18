# Review Documentation — Checklist Rápido

Checklist de conformidade antes de fechar qualquer registro técnico de entrega.

## Pré-publicação (obrigatório)

### Estrutura do arquivo
- [ ] Nome segue o padrão `YYYY-MM-DD-HHMM-<slug-curto>.md` (ou padrão do projeto)
- [ ] Arquivo salvo no local de review adotado pelo projeto
- [ ] Título objetivo descreve o efeito da mudança, não o ticket interno

### Seções obrigatórias presentes
- [ ] `## Contexto e objetivo` — preenchido com problema real, não apenas "implementar X"
- [ ] `## Escopo técnico e arquivos modificados` — lista de arquivos concreta
- [ ] `## ADR resumido` — decisão, alternativas e trade-offs documentados
- [ ] `## Evidências de validação` — comando executado + resultado, ou declaração explícita de ausência
- [ ] `## Riscos, impacto e rollback` — pelo menos 1 risco e plano de rollback com passos
- [ ] `## Próximos passos recomendados` — pelo menos 1 item acionável
- [ ] `## Diagrama (Mermaid)` — diagrama presente e renderizável

### Qualidade do conteúdo
- [ ] Evidências distinguem o que foi executado do que foi apenas recomendado
- [ ] Rollback descreve passos reais, não "reverter o deploy"
- [ ] Arquivos modificados listados de forma objetiva (sem ambiguidades como "vários arquivos")
- [ ] ADR cita pelo menos 2 alternativas avaliadas

## Por tipo de entrega (seções opcionais)

### Se houver mudança em banco/schema
- [ ] Migrations listadas com nome e direção (up/down)
- [ ] Impacto em auditoria, constraints ou volume documentado
- [ ] Rollback de schema descrito (rollback migration ou estratégia manual)

### Se houver mudança em API/contrato
- [ ] Endpoints afetados listados com método e path
- [ ] Compatibilidade retroativa avaliada (breaking / non-breaking)
- [ ] Payload ou schema de request/response documentado quando alterado

### Se houver mudança em infraestrutura/CI
- [ ] Variáveis de ambiente adicionadas ou alteradas listadas
- [ ] Impacto em pipeline documentado
- [ ] Ambiente alvo da mudança declarado (dev / staging / prod)

### Se houver mudança em testes/QA
- [ ] Suite afetada identificada
- [ ] Cobertura adicionada ou regressão protegida descrita
- [ ] Impacto em CI (tempo, gates, flaky risk) avaliado

### Se for mudança puramente documental
- [ ] Documento refinado identificado
- [ ] Impacto esperado sobre requisitos, QA ou manutenção descrito

## Pós-publicação

- [ ] Review referenciado no PR ou commit correspondente
- [ ] Review referenciado na revisão consolidada do Tech Lead quando aplicável
- [ ] `documentation-sync` acionado se a mudança também afeta docs vivos do repositório
