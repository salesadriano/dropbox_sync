# Skills Sync

Processo de ingestao de skills externas para o catalogo versionado do pacote.

## Diretorios

| Diretorio | Papel | Versionado |
|---|---|---|
| `.agents/skills/` | area de staging usada pelo instalador de skills; conteudo upstream cru | nao |
| `.github/skills/` | catalogo canonico do pacote, referenciado pelos agents como `../skills/<skill>/` | sim |
| `skills-lock.json` | procedencia de cada skill instalada: origem, caminho upstream, hash e nome no catalogo | sim |

Os agents leem **apenas** `.github/skills/`. Nada em `.agents/skills/` e consultado em execucao.

## Fluxo de ingestao

1. Instalar a skill upstream, que aparece em `.agents/skills/<nome-upstream>/` e e registrada em `skills-lock.json`.
2. Comparar com o catalogo existente antes de copiar:
   - se nao existir equivalente, e uma adicao;
   - se existir equivalente e o upstream for uma revisao mais nova da mesma skill, e uma atualizacao;
   - se existir equivalente com escopo diferente (por exemplo, uma versao especifica de stack), criar uma skill separada e **nao** sobrescrever a existente.
3. Copiar para `.github/skills/<nome-no-catalogo>/`.
4. Normalizar conforme a secao abaixo.
5. Registrar o nome final em `skills-lock.json` no campo `catalogName`.
6. Atualizar `SKILL_HIERARCHY.md`, `../agents/AGENTS.md`, as personas afetadas e o `README.md`.

## Normalizacao obrigatoria

Toda skill que entra em `.github/skills/` deve atender ao seguinte:

1. **Frontmatter** com `name` igual ao nome do diretorio e `description` que declare explicitamente o limite de escopo, no formato "use para X; prefira `outra-skill` para Y".
2. **Secao `## Security Handoff`** logo apos o titulo, apontando para `security-best-practices` e `api-security-best-practices` e proibindo segredos em exemplos, fixtures, diagramas, logs e artefatos gerados.
3. **Secao `## Scope Boundary`** quando existir skill vizinha que possa ser confundida, com link relativo para o `SKILL.md` da vizinha.
4. **Sem referencia pendente**: qualquer mencao a skill inexistente neste pacote deve ser removida ou redirecionada para a skill equivalente do catalogo.
5. **Sem artefato de runtime do instalador**: `tile.json`, `agents/openai.yaml` e equivalentes nao entram no catalogo.
6. **Parada no primeiro erro nos blocos de teste**: todo comando de execucao de testes, configuracao de runner, script de `package.json` e exemplo de pipeline da skill traz a parada no primeiro erro da Regra 9 de `protocolo-tdd` (mecanica por ferramenta em `protocolo-tdd/references/interrupcao-no-primeiro-erro.md`). Default upstream que roda a suite inteira sem parada e ajustado na ingestao, nunca mantido. Exemplo de pipeline segue tambem a ordem da Regra 8: preparo (checkout, dependencias e runner com versoes fixadas, ambiente, gates rapidos), logo em seguida os testes, e build, publicacao ou deploy so depois deles.
7. **Precedencia do pacote**: quando o conteudo upstream conflitar com uma regra obrigatoria do pacote, a regra do pacote prevalece e o conflito deve estar escrito na propria skill. Exemplo: `tdd-test-design` sugere "prefira um banco de teste", mas `protocolo-tdd` exige banco real via Testcontainers e proibe mock da camada de dados.

## Renomeacoes ja aplicadas

| Nome upstream | Nome no catalogo | Motivo |
|---|---|---|
| `clean-architecture` (dotnet-claude-kit) | `dotnet-clean-architecture` | colidia com a skill agnostica a linguagem, que continua sendo o padrao do pacote |
| `organization-best-practices` | `better-auth-organization` | o nome upstream sugere organizacao generica; a skill e do plugin `organization()` do Better Auth |
| `two-factor-authentication-best-practices` | `better-auth-two-factor` | mesmo motivo: e o plugin `twoFactor()` do Better Auth, nao MFA generico |
| `tdd` | `tdd-test-design` | evita ambiguidade com `protocolo-tdd`, que e o protocolo obrigatorio do pacote |

## Skills grandes

`fastify-best-practices`, `supabase-postgres-best-practices` e `react-native-best-practices` trazem diretorios internos extensos. Vale o item 37 do `../agents/AGENTS.md`: ler o `SKILL.md` primeiro e abrir apenas o arquivo especifico necessario.

- `react-native-best-practices`: usar `POWER.md` como indice de selecao. O diretorio `references/images/` contem apenas capturas de profiling e nao precisa ser lido.
- `supabase-postgres-best-practices`: usar a tabela de prefixos (`query-`, `conn-`, `security-`, `schema-`, `lock-`, `data-`, `monitor-`, `advanced-`).
- `fastify-best-practices`: usar a ordem de leitura recomendada no `SKILL.md`.
