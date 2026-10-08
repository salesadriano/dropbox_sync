# ADR Patterns — Referência Rápida

Padrões de preenchimento do `## ADR resumido` para os cenários mais comuns de entrega técnica.

## Estrutura base

```markdown
## ADR resumido

### Decisão
<Uma frase direta descrevendo o que foi escolhido e por quê.>

### Alternativas consideradas
1. `<alternativa-1>` — <por que foi descartada>
2. `<alternativa-2>` — <por que foi descartada>
3. `<opção escolhida>` — <por que foi preferida>

### Trade-offs
- **Vantagem:** <o que a decisão resolve ou melhora>
- **Custo:** <o que a decisão sacrifica ou aumenta>
- **Risco residual:** <o que ainda pode falhar ou precisar de revisão>
```

## Padrões por cenário

### Refatoração de código

```markdown
### Decisão
Extrair `UserPermissionService` de `UserController` para eliminar violação de SRP e facilitar testes unitários isolados.

### Alternativas consideradas
1. `Manter lógica no controller` — descartado: acoplamento impede mock isolado no QA
2. `Mover para middleware` — descartado: responsabilidade de negócio não pertence à camada HTTP
3. `Extrair para service dedicado` — escolhido: alinha a Clean Architecture e permite injeção de dependência

### Trade-offs
- **Vantagem:** testabilidade isolada, reutilização em outros controllers
- **Custo:** novo arquivo, ajuste de injeção de dependência no módulo
- **Risco residual:** outros controllers que dependem do mesmo padrão precisam ser migrados no futuro
```

### Mudança de schema/migration

```markdown
### Decisão
Adicionar coluna `deleted_at TIMESTAMP NULL` à tabela `orders` para implementar soft-delete em vez de hard-delete.

### Alternativas consideradas
1. `Hard-delete` — descartado: auditoria exige histórico de pedidos cancelados
2. `Tabela separada orders_archive` — descartado: complexidade de JOIN e sincronização
3. `Soft-delete com deleted_at` — escolhido: solução padrão, suporte nativo em ORMs, reversível

### Trade-offs
- **Vantagem:** histórico preservado, rollback trivial (setar NULL)
- **Custo:** queries precisam de filtro `WHERE deleted_at IS NULL` explícito
- **Risco residual:** índices existentes precisam ser revisados para incluir o filtro
```

### Mudança de autenticação/segurança

```markdown
### Decisão
Substituir JWT com segredo simétrico (HS256) por par de chaves assimétricas (RS256) para permitir validação por serviços sem compartilhar o segredo.

### Alternativas consideradas
1. `Manter HS256` — descartado: serviços consumidores precisariam do segredo, ampliando superfície de vazamento
2. `Tokens opacos com introspecção` — descartado: latência adicional por chamada de rede por request
3. `RS256 com chave pública distribuída` — escolhido: verificação local, segredo nunca sai do serviço emissor

### Trade-offs
- **Vantagem:** isolamento de segredo, validação offline nos consumidores
- **Custo:** rotação de chaves mais complexa, necessidade de JWKS endpoint
- **Risco residual:** tokens emitidos com HS256 precisam ser invalidados; janela de coexistência
```

### Mudança de infraestrutura/CI

```markdown
### Decisão
Migrar step de build de `npm run build` direto no CI para imagem Docker multi-stage, eliminando dependência do ambiente de CI para compilação.

### Alternativas consideradas
1. `Build direto no runner` — descartado: comportamento diverge entre CI e produção
2. `Cache de node_modules no runner` — descartado: não resolve divergência de ambiente de SO
3. `Multi-stage Docker build` — escolhido: imagem reproduzível, sem dependência de estado do runner

### Trade-offs
- **Vantagem:** builds reproduzíveis, eliminação de "funciona no CI mas não na prod"
- **Custo:** tempo de build inicial maior; cache de Docker layer precisa de configuração
- **Risco residual:** imagens de base precisam de pinagem de versão para evitar drift
```

### Mudança puramente documental

```markdown
### Decisão
Consolidar três documentos de onboarding dispersos em um único `ONBOARD.md` estruturado com âncoras por perfil (developer, QA, devops).

### Alternativas consideradas
1. `Manter documentos separados` — descartado: duplicação de contexto, links quebrados entre docs
2. `Wiki externa` — descartado: fora do versionamento do repositório, desincroniza com o código
3. `ONBOARD.md unificado` — escolhido: colocado na raiz, versionado com o projeto, seções por perfil

### Trade-offs
- **Vantagem:** entrada única, sem contradições entre docs; atualizável junto com o código
- **Custo:** arquivo único mais longo; requer manutenção ativa a cada mudança de fluxo
- **Risco residual:** links externos para os docs antigos precisam ser atualizados
```

## Regras de qualidade do ADR

| Critério | Aceitável | Evitar |
|---|---|---|
| Decisão | Uma frase com escolha + motivo | "Foi decidido implementar X" (sem motivo) |
| Alternativas | ≥ 2 com motivo de descarte | "Opção A, Opção B" (sem justificativa) |
| Trade-offs | Vantagem, custo e risco residual | "É a melhor solução" (sem custo) |
| Scope | Específico à mudança documentada | ADR genérico sobre arquitetura global |
