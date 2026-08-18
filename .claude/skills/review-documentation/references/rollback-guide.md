# Rollback Guide — Referência Rápida

Padrões de documentação do `## Plano de rollback` por tipo de entrega.

## Regra base

Um rollback documentado deve sempre conter:
1. **Gatilho** — qual condição ativa o rollback
2. **Responsável** — quem executa (dev, ops, automação)
3. **Passos** — sequência explícita e reversível
4. **Validação** — como confirmar que o rollback foi bem-sucedido
5. **Impacto** — o que é perdido ou afetado pelo rollback

---

## Por tipo de entrega

### Código / API

```markdown
### Plano de rollback
**Gatilho:** taxa de erro 5xx > 1% por 5 minutos após o deploy, ou falha crítica em validação de smoke.
**Responsável:** Developer / SRE de plantão.

1. Reverter para a tag/release anterior no repositório:
   ```bash
   git revert <commit-hash> --no-edit
   git push origin main
   ```
2. Acionar re-deploy da versão anterior no ambiente afetado.
3. Validar: smoke test nos endpoints críticos deve retornar 200.
4. Registrar incidente com hash do commit problemático e sintoma observado.

**Impacto do rollback:** funcionalidade X indisponível até nova release.
```

### Schema / Migration

```markdown
### Plano de rollback
**Gatilho:** erro de constraint em produção após migration, ou degradação de performance detectada no plano de execução.
**Responsável:** DBA / Developer.

1. Executar migration de rollback (down):
   ```bash
   # Django
   python manage.py migrate app_name <migration_anterior>

   # Flyway
   flyway -target=<versao_anterior> migrate

   # Liquibase
   liquibase rollbackCount 1
   ```
2. Validar integridade das tabelas afetadas:
   ```sql
   SELECT COUNT(*) FROM <tabela> WHERE <condicao_afetada>;
   ```
3. Confirmar que aplicação opera normalmente com schema anterior.
4. Documentar o bloqueador na issue/PR para análise antes de nova tentativa.

**Impacto do rollback:** dados inseridos após a migration (se houver) precisam de avaliação individual.
Soft-delete com `deleted_at`: setar `NULL` onde aplicável.
```

### Variável de ambiente / Secret

```markdown
### Plano de rollback
**Gatilho:** falha de autenticação ou comportamento inesperado após rotação de secret.
**Responsável:** Developer / DevOps.

1. Restaurar o valor anterior da variável no gerenciador de secrets (Vault, AWS Secrets Manager, etc.).
2. Reiniciar o serviço para forçar reload das variáveis:
   ```bash
   kubectl rollout restart deployment/<nome-do-deployment>
   # ou equivalente no ambiente
   ```
3. Validar: log de autenticação deve mostrar sucesso sem erro de credencial.
4. Investigar causa da falha antes de nova rotação.

**Impacto do rollback:** tokens gerados com o secret novo podem ser inválidos — usuários com sessão ativa podem precisar reautenticar.
```

### Infraestrutura / CI

```markdown
### Plano de rollback
**Gatilho:** pipeline quebrado, deploy falhando ou degradação de performance no ambiente após mudança de infraestrutura.
**Responsável:** DevOps / Developer.

1. Reverter o arquivo de configuração para o estado anterior:
   ```bash
   git revert <commit-hash-da-mudanca-de-infra> --no-edit
   git push origin main
   ```
2. Re-aplicar infraestrutura com IaC (Terraform, Pulumi, etc.):
   ```bash
   terraform apply -var-file=<env>.tfvars
   ```
3. Validar: pipeline deve completar sem erro; smoke test no ambiente alvo.
4. Registrar o que causou a falha para ajuste na próxima iteração.

**Impacto do rollback:** configurações específicas do ambiente novo perdidas; nova janela de manutenção necessária.
```

### Feature Flag / Configuração de produto

```markdown
### Plano de rollback
**Gatilho:** comportamento inesperado reportado por usuários ou monitoramento após ativação da flag.
**Responsável:** Developer / Product.

1. Desativar a feature flag no painel ou arquivo de configuração.
2. Verificar que o comportamento anterior foi restaurado sem necessidade de redeploy.
3. Analisar logs e métricas do período de ativação para identificar causa.
4. Documentar o que foi observado antes de reativar.

**Impacto do rollback:** funcionalidade indisponível para todos os usuários (ou segmento alvo) até nova ativação.
```

### Mudança documental

```markdown
### Plano de rollback
**Gatilho:** documento publicado com informação incorreta ou inconsistente com a implementação real.
**Responsável:** Developer / Tech Lead.

1. Identificar a versão anterior do documento no histórico git:
   ```bash
   git log --oneline -- docs/<arquivo>.md
   git show <commit-hash>:docs/<arquivo>.md > docs/<arquivo>.md
   ```
2. Commitar a restauração com mensagem explicando o motivo.
3. Notificar stakeholders afetados caso o documento tenha sido compartilhado externamente.

**Impacto do rollback:** informação corrigida pode demorar para alcançar consumidores externos do documento.
```

---

## Anti-padrões de rollback a evitar

| Anti-padrão | Problema | Alternativa |
|---|---|---|
| "Reverter o deploy" | Vago, sem passos concretos | Listar comandos exatos |
| Rollback sem validação | Não confirma sucesso | Definir smoke test ou query de verificação |
| Sem gatilho definido | Rollback nunca é acionado (ou acionado tarde) | Definir métrica e threshold explícitos |
| Rollback que apaga dados | Irreversível — piora o incidente | Preferir soft-delete ou backup explícito antes |
| Responsável genérico "time" | Ninguém age — accountability difusa | Nomear papel específico (dev, SRE, DBA) |
