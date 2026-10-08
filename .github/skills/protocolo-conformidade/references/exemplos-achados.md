# Exemplos de Achados e Calibragem de Severidade

Use estes exemplos para redigir achados acionaveis e calibrar severidade. Todo achado cita a skill e o identificador da regra. Achado sem regra de referencia nao pode ser bloqueante.

## Estrutura de um achado

| Campo | Conteudo |
|---|---|
| Arquivo:linha | localizacao exata no diff |
| Achado | o que esta errado, em uma frase |
| Regra violada | `skill / identificador` |
| Correcao esperada | acao objetiva, nao um principio generico |
| Severidade | Bloqueante, Maior ou Menor |

## Bloqueantes

### Dominio importando infraestrutura

- **Achado:** a entidade `Order` importa o client do ORM para carregar itens.
- **Regra:** `clean-architecture / frame-domain-purity`, `dep-no-framework-imports`.
- **Correcao:** remover o import, declarar a porta no dominio e implementar o acesso na infraestrutura; o caso de uso passa a orquestrar a carga.
- **Por que bloqueia:** inverte a direcao de dependencia e amarra a regra de negocio ao ORM.

### Regra de negocio no controller

- **Achado:** o endpoint calcula desconto e monta o total antes de chamar o servico.
- **Regra:** `clean-architecture / adapt-controller-thin`, `usecase-orchestrates-not-implements`.
- **Correcao:** mover o calculo para a entidade ou para o caso de uso; o endpoint apenas traduz HTTP para o caso de uso e de volta.

### Transacao fora do caso de uso

- **Achado:** o repositorio abre e confirma a transacao internamente, por operacao.
- **Regra:** `clean-architecture / usecase-transaction-boundary`.
- **Correcao:** a fronteira transacional volta para o caso de uso; o repositorio participa da transacao em curso.

### Segredo introduzido no diff

- **Achado:** connection string com senha literal no arquivo de configuracao versionado.
- **Regra:** `security-best-practices`, item de secret handling.
- **Correcao:** mover para variavel de ambiente ou secret manager, rotacionar o valor exposto e remover do historico se ja commitado.
- **Observacao:** achado de seguranca nunca e encerrado por justificativa.

### Consulta sem indice em caminho quente

- **Achado:** nova consulta filtra por coluna sem indice em tabela grande, dentro de um endpoint de listagem.
- **Regra:** `supabase-postgres-best-practices / query-missing-indexes`.
- **Correcao:** criar o indice na migration da propria entrega e validar o plano com `EXPLAIN ANALYZE`.

### RLS ausente em tabela multi-tenant

- **Achado:** a nova tabela guarda dado por tenant e nao habilitou Row Level Security.
- **Regra:** `supabase-postgres-best-practices / security-rls-basics`.
- **Correcao:** habilitar RLS, escrever a policy de isolamento e cobrir com teste que prove que um tenant nao le a linha do outro.

### Escapando o escaping do framework

- **Achado:** valor vindo de query string interpolado em `dangerouslySetInnerHTML`.
- **Regra:** `security-best-practices`, prevencao de XSS.
- **Correcao:** usar renderizacao de texto ou sanitizar antes de injetar; reservar o padrao a conteudo estatico controlado pelo servidor.

## Maiores

### Reimplementacao de componente existente

- **Achado:** criado `formatCurrency` novo, com `src/shared/format/money.ts` ja disponivel e equivalente.
- **Regra:** `clean-architecture / comp-common-reuse` e consistencia com o projeto.
- **Correcao:** reutilizar o utilitario existente ou justificar tecnicamente por que ele nao atende.

### Modelo anemico

- **Achado:** a entidade so tem getters e setters; toda a regra ficou no servico.
- **Regra:** `clean-architecture / entity-rich-not-anemic`.
- **Correcao:** mover invariantes e transicoes de estado para a entidade, deixando o servico como orquestrador.

### Estrutura de framework atravessando fronteira

- **Achado:** o objeto `Request` do framework e passado para o caso de uso.
- **Regra:** `clean-architecture / dep-data-crossing-boundaries`.
- **Correcao:** extrair um comando ou DTO simples no adaptador e passar apenas ele.

### Divergencia com padrao consolidado

- **Achado:** o novo modulo trata erro com retorno de `null`, enquanto o restante do projeto usa excecoes tipadas.
- **Regra:** consistencia com o repositorio, alem da regra de erro da skill da stack.
- **Correcao:** alinhar ao padrao existente ou registrar decisao explicita de mudanca de padrao no System Design.

### N+1 introduzido

- **Achado:** a listagem carrega os itens de cada pedido dentro do laco.
- **Regra:** `supabase-postgres-best-practices / data-n-plus-one`, ou a regra equivalente da skill da stack.
- **Correcao:** carregar em lote com join, `IN` ou eager loading.

## Menores

- Nome que nao segue o vocabulario de dominio ja usado no codigo.
- Arquivo que cresceu alem do padrao do projeto e comporta divisao.
- Comentario descrevendo o que o codigo ja diz, sem explicar a decisao.
- Ordem de membros divergente da convencao da stack.

Menores nao reprovam. Registrar como recomendacao e seguir.

## Erros comuns ao redigir o parecer

| Evitar | Preferir |
|---|---|
| "Nao segue Clean Architecture" | "`src/domain/order.ts:42` importa o client do ORM, violando `frame-domain-purity`" |
| "Melhorar a qualidade do codigo" | "Extrair o calculo de total para `Order.total()` e deixar o handler apenas orquestrando" |
| Marcar como bloqueante sem citar regra | Citar `skill / identificador` ou rebaixar a severidade |
| Reprovar por preferencia de estilo | Registrar como menor e seguir |
| Repetir achado ja justificado e aceito | Referenciar a justificativa registrada no parecer anterior |
