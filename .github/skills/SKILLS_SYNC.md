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
| `tdd` | `tdd-test-design` | evita ambiguidade com `protocolo-tdd`, que e o protocolo obrigatorio do pacote |

## Skills grandes

As skills de stack com diretorios internos extensos foram podadas deste repositorio (ver abaixo). Para qualquer skill mantida, vale o item 37 do `../agents/AGENTS.md`: ler o `SKILL.md` primeiro e abrir apenas o arquivo especifico necessario.

## Poda deste projeto

Em 2026-10-19, por decisao do solicitante (memoria `../agents/memoria/entradas/2026-10-19-0829-aliases-poda-e-comentarios.md`), foram removidas deste repositorio as skills de stacks que o `dropbox_sync` (CLI em Bash) nao usa. Nao incluidas neste repositorio; fonte: `ai_team`.

Removidas (31): `accessibility`, `accessibility-compliance`, `accessibility-review`, `best-practices`, `better-auth-best-practices`, `better-auth-organization`, `better-auth-two-factor`, `design-md`, `django-expert`, `django-patterns`, `django-security`, `django-tdd`, `dotnet-clean-architecture`, `fastapi-async-patterns`, `fastapi-expert`, `fastapi-python`, `fastapi-templates`, `fastify-best-practices`, `frontend-design`, `frontend-react-best-practices`, `interface-design`, `laravel-best-practices`, `nestjs-best-practices`, `nodejs-best-practices`, `php-best-practices`, `python-best-practices`, `react-native-best-practices`, `strategy-compare`, `supabase-postgres-best-practices`, `vercel-react-best-practices`, `workers-best-practices`.

Uma sincronizacao futura com o `ai_team` NAO reimporta essas skills: ao sincronizar, preservar a poda e nao copiar esses diretorios nem restaurar as referencias a elas.
