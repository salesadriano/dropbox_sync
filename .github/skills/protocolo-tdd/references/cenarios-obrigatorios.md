# Cenarios obrigatorios de seguranca, acesso e formularios

Catalogo das Regras 6 e 7 de [`SKILL.md`](../SKILL.md). Abrir apenas quando a alteracao tocar um gatilho de seguranca ou uma interface com entrada de dados. A obrigatoriedade, os gatilhos e a severidade estao na skill; este arquivo detalha **quais cenarios** provam cada regra.

## Regra 6 - Cenarios negativos de seguranca e acesso indevido

Para cada gatilho tocado, a suite deve conter **cenarios negativos** que provem a protecao. Cenario positivo (o usuario certo consegue) nao substitui cenario negativo (o usuario errado nao consegue). Catalogo minimo, por gatilho tocado:

| Gatilho | Cenarios negativos obrigatorios | Camada |
|---|---|---|
| Autenticacao | sem credencial; credencial invalida; token expirado, revogado ou de outro ambiente; sessao encerrada | Integracao |
| Autorizacao | papel sem permissao; permissao de leitura tentando escrever; acao administrativa por usuario comum; escalacao via parametro (`role`, `isAdmin`, `ownerId`) no payload | Integracao e E2E |
| Isolamento por tenant | ID de recurso de outro tenant (IDOR) em leitura, escrita e exclusao; listagem sem vazamento entre tenants; RLS ou filtro aplicado no banco real | Integracao |
| Referencia direta a objeto | recurso de outro usuario por ID sequencial, UUID adivinhado ou slug | Integracao |
| Entrada maliciosa | injecao (SQL, NoSQL, comando, template, LDAP conforme a stack); XSS refletido e armazenado quando houver renderizacao; path traversal em nome de arquivo; payload fora do schema, tipo errado, tamanho excessivo, campo extra ignorado ou rejeitado | Integracao |
| Dado sensivel | resposta nao expoe campo sensivel (hash, token, segredo, PII alem do necessario); log e evidencia nao contem segredo; erro nao vaza stack, query ou caminho interno | Integracao |
| Exposicao de API | metodo HTTP nao previsto rejeitado; CORS nao aceita origem arbitraria; cabecalhos de seguranca presentes quando a stack os define | Integracao |
| Arquivo | tipo, tamanho e nome validados; conteudo executavel rejeitado; download so do proprio recurso | Integracao |
| Rate limit e cota | excesso bloqueado com resposta esperada; limite por usuario nao compartilhado entre usuarios | Integracao |
| Fluxo de negocio sensivel | E2E da jornada com usuario sem permissao e com tenant errado, alem da jornada feliz | E2E |


### Regras de camada e assercao (Regra 6)

- Cenario positivo (o usuario certo consegue) nao substitui cenario negativo (o usuario errado nao consegue).
- Cenario de autorizacao, tenant e IDOR roda contra backend e banco reais (Testcontainers ou base de homologacao), nunca contra mock de autorizacao ou de repositorio.
- Credenciais, tokens e tenants de teste vem do seeder ou sao criados no roteiro; dado sintetico, sem segredo real (Security Handoff).
- Injecao e validacao de entrada podem ter cobertura unitaria na regra de validacao, mas a prova de que a fronteira real rejeita e de integracao.
- Cenario negativo que "passa" porque o endpoint retornou 500 em vez de 401/403/422 nao prova protecao: a assercao e sobre o codigo e o corpo esperados, e sobre a ausencia de efeito colateral (nada persistido, nada vazado).

## Regra 7 - Cenarios de formulario e feedback visual em E2E

Para cada formulario ou grupo de campos tocado, alem da jornada feliz:

| Cenario obrigatorio | O que o teste prova |
|---|---|
| Campos obrigatorios vazios | submeter sem preencher cada campo obrigatorio (um por vez e todos de uma vez) e provar que a submissao e bloqueada, nada e persistido e cada campo faltante e apontado |
| Valor indevido por tipo | texto em campo numerico ou monetario; numero fora do intervalo; data invalida, impossivel ou fora do periodo; e-mail, telefone, documento ou codigo com formato invalido; tamanho acima do limite; caracteres nao permitidos; opcao fora da lista em select ou autocomplete |
| Valor indevido por regra de negocio | combinacao invalida entre campos (data final antes da inicial, valor maior que o saldo, duplicidade de chave) quando a regra existir |
| Feedback visual do erro | a mensagem de erro e visivel sem rolagem forcada, esta associada ao campo que a causou (`data-cy` proprio, `aria-describedby` ou `aria-invalid`, ou o padrao do Design System), diz o que corrigir, e some quando o valor e corrigido |
| Estado do formulario apos erro | o botao de submissao fica desabilitado ou a submissao nao dispara chamada ao backend; os demais valores preenchidos sao preservados; o foco vai para o primeiro campo invalido quando o Design System assim definir |
| Correcao e reenvio | apos corrigir, a submissao acontece e o resultado persiste, na mesma jornada |

### Regras de assercao e feedback (Regra 7)

- O cenario afirma o feedback pelo seletor estavel do erro (`data-cy`/`data-test`), nunca apenas pela ausencia de navegacao ou por texto generico como "erro".
- Mensagens esperadas vem do Design System ou do criterio de aceite, nao do texto que o teste encontrou na tela.
- O bloqueio de submissao no frontend nao substitui o teste de integracao que prova a rejeicao no backend (Regra 6, entrada fora do schema); os dois coexistem, porque a validacao de interface pode ser contornada.
- Quando `accessibility-review` estiver acionada para o fluxo, o feedback de erro entra na verificacao de acessibilidade (anuncio por leitor de tela, contraste, foco).

A obrigatoriedade, os gatilhos e a severidade estao nas Regras 6 e 7 de [`SKILL.md`](../SKILL.md).
