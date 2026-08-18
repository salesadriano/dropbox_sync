# <Titulo curto — ex: "Migration: adicionar soft-delete na tabela orders">

> **Tipo:** Persistência / Schema / Migration
> **Registro retroativo:** [sim/não] — se sim, declare o commit e data aqui.

## Contexto e objetivo
Descreva:
- qual tabela, entidade ou modelo foi afetado;
- qual era o problema ou necessidade (consistência, performance, nova funcionalidade, compliance);
- qual é o objetivo técnico desta entrega de dados.

## Escopo técnico e arquivos modificados
- `<migrations/0015_add_deleted_at.py>` — <descrição da migration>
- `<app/models/order.py>` — <campo adicionado/alterado>
- `<app/managers/order_manager.py>` — <filtro de soft-delete adicionado>
- `<tests/models/test_order.py>` — <cenários adicionados>

Mudanças aplicadas:
- `<mudança técnica 1>`
- `<mudança técnica 2>`

## ADR resumido

### Decisão
<Uma frase: o que foi escolhido e por quê.>

### Alternativas consideradas
1. `<alternativa 1>` — <motivo do descarte>
2. `<alternativa 2>` — <motivo do descarte>
3. `<opção escolhida>` — <motivo da preferência>

### Trade-offs
- **Vantagem:** <o que melhora>
- **Custo:** <o que aumenta — consultas, índices, complexidade>
- **Risco residual:** <o que ainda pode falhar>

## Modelo de dados — antes e depois

### Antes
```sql
CREATE TABLE <tabela> (
    id SERIAL PRIMARY KEY,
    <campo_existente> <tipo>,
    ...
);
```

### Depois
```sql
CREATE TABLE <tabela> (
    id SERIAL PRIMARY KEY,
    <campo_existente> <tipo>,
    <campo_novo> <tipo> <restrição>,  -- adicionado
    ...
);
```

Migrations geradas:
| Arquivo | Direção | Operação |
|---------|---------|----------|
| `<migration_name>` | up | `<ALTER TABLE / CREATE INDEX / etc>` |
| `<migration_name>` | down | `<operação de reversão>` |

Índices adicionados/alterados:
- `<nome_indice>` em `<tabela>(<coluna>)` [WHERE <condição>] — <justificativa>

## Impacto em auditoria e integridade
- Constraints afetadas: `<sim/não — quais>`
- Dados históricos impactados: `<sim/não — como foram tratados>`
- Auditoria / trilha de dados: `<impacto se houver>`
- Volume estimado de registros afetados pela migration: `<N linhas>`

## Evidências de validação

Ambiente: <local com Docker / staging>

```bash
# Aplicar migration
<comando de migrate>

# Verificar estrutura
<comando de inspeção do schema>

# Verificar integridade dos dados
<query SQL de verificação>
```

Resultado:
- `<resultado resumido 1>`
- `<resultado resumido 2>`

```bash
# Rollback testado
<comando de rollback>
```
- Resultado do rollback: `<sucesso / falha + detalhe>`

Validação não executada:
- `<o que ficou pendente — ex: plano de execução em prod, teste de carga>`

## Riscos, impacto e rollback

### Riscos
- `<risco 1>` — probabilidade: <baixa/média/alta>
- Risco de lock em tabela durante migration: `<avaliado como: baixo/médio/alto>` — `<justificativa>`

### Impacto
- **Performance de leitura:** <impacto — ex: "queries precisam de filtro WHERE deleted_at IS NULL">
- **Tamanho da tabela:** <impacto em disco estimado>
- **Aplicações dependentes:** <o que precisa ser atualizado>

### Plano de rollback
**Gatilho:** <condição — ex: "erro de constraint em prod após migration">
**Responsável:** DBA / Developer

1. `<passo 1 — ex: executar migration down>`
2. `<passo 2 — ex: verificar integridade>`
3. Validar: `<query ou comando de verificação>`

**Impacto do rollback:** <o que é perdido — ex: "dados inseridos após a migration precisam de avaliação">

## Próximos passos recomendados
1. `<próximo passo 1 — ex: revisar queries que não usam o filtro>`
2. `<próximo passo 2 — ex: DBA validar plano de execução em staging>`

## Diagrama (Mermaid)

```mermaid
erDiagram
    <ENTIDADE> {
        int id PK
        <tipo> <campo_existente>
        <tipo> <campo_novo> "adicionado"
    }

    <ENTIDADE_RELACIONADA> {
        int id PK
        int <entidade>_id FK
    }

    <ENTIDADE> ||--o{ <ENTIDADE_RELACIONADA> : "<relação>"
```
