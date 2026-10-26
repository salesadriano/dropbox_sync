# Remocao das copias locais que o plugin ai-team fornece

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | "remove os agents locais e skills duplicados" |
| Porte | M - governanca do pacote (personas, skills, hooks do cliente de IA) sem mudar regra nem codigo de runtime |
| Log de prompt | `docs/prompts/2026-10-24_2118_remover-duplicados-do-plugin.md` |
| Branch / base | `chore/remover-duplicados-do-plugin` sobre `origin/develop` @ `6df321e` |
| Agents | Tech Lead (remocao, dependencias, verificacao), `ai-team:documentation-writer` (reescrita das referencias), `ai-team:qa-expert` (validacao) |
| Data | 2026-10-24 |

## 2. Causa ou decisao

O plugin `ai-team` 1.0.8 ja fornece as oito personas (sete como `ai-team:<papel>`, o Tech Lead como `/ai-team:tech-lead`), 16 das 25 skills de `.github/skills/`, o comando `execucao-enxuta` e os hooks de governanca. As copias do projeto eram versoes anteriores, sem conteudo proprio (so pastas `scripts/tests` de bats do pacote), e os dois hooks de `.claude/settings.json` rodavam em duplicidade com os do plugin (o resumo de estado aparecia duas vezes no inicio da sessao).

- Saem: `.github/agents/*.agent.md` (8), `.github/prompts/execucao-enxuta.prompt.md`, as 16 skills duplicadas e os 2 hooks (pelo `migrar-para-o-plugin.sh --executar` do proprio plugin).
- Ficam: `AGENTS.md`, `memoria/`, `templates/` e as 9 skills do projeto (`bats-testing-patterns`, `clean-architecture`, `e2e-reexecucao-parcial`, `prd-generator`, `shellcheck-configuration`, `superficie-de-contrato`, `testing-strategy`, `use-case-specification`, `user-story-writing`).
- `scripts/suite-completa.sh` delegava a `.github/skills/governanca-por-hooks/scripts/suite-completa.sh`; passa a ser a propria implementacao (copia identica da do plugin), que o despachante `hooks/executar.sh` do plugin ja prefere.
- Referencias as skills e personas removidas viram `ai-team:<nome>`; `memoria/historico/`, a entrada `2026-10-18-1715-adocao-modelo.md` e `docs/` ficam como estao (registros historicos).
- Alternativa descartada: manter as copias como fallback. Elas envelhecem (ja divergiam do plugin) e o catalogo mostrava cada persona duas vezes.

## 3. Arquivos

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `.github/agents/*.agent.md` (8), `.github/prompts/execucao-enxuta.prompt.md` | Removido | - |
| `.github/skills/<16 skills>/` (75 arquivos) | Removido | - |
| `.claude/settings.json` | Alterado (2 hooks de governanca removidos) | -25 |
| `scripts/suite-completa.sh` | Alterado (de atalho para implementacao) | +82/-5 |
| `scripts/tests/suite-completa-wrapper.bats` | Alterado (comentario) | +1/-1 |
| `.github/agents/AGENTS.md`, `templates/` (4), `memoria/MEMORIA-PROJETO.md` (so caminho), `CLAUDE.md` | Alterado (referencias) | - |
| `.github/skills/SKILL_HIERARCHY.md`, `SKILLS_SYNC.md`, 5 `SKILL.md` do projeto | Alterado (origem plugin x projeto, referencias) | - |

Total de linhas de codigo de runtime: **0**.

## 4. Testes rodados

| Verificacao | Comando | Resultado |
|---|---|---|
| Links das skills locais | `sh scripts/validate-skill-links.sh` | `All local skill references are valid.` |
| Drift do arquivo de instrucoes | `sh scripts/verificar-instrucoes-do-projeto.sh` | `sem drift` (a, b, c, d ok) |
| Memoria | `sh scripts/memoria-index.sh --check` | `entradas validas: 42` (2 avisos preexistentes de `agentes: todos`) |
| Bats dos scripts do projeto | `npx --yes bats@1.13.0 scripts/tests/` | 450 casos, 449 ok, 1 falha preexistente (abaixo) |
| Referencias restantes as skills removidas | varredura por `grep` fora de `historico/` e `docs/` | so a entrada historica `2026-10-18-1715-adocao-modelo.md`, mantida |

- Falha preexistente: `suite-completa-wrapper.bats` caso 3 (`scripts/suite-completa.cmd traz o mesmo comando do passo 5 do main.yml`) procura `.github/workflows/main.yml`, que nao existe na `develop` nem nesta branch; fora do escopo desta demanda.
- Red observado: Nao aplicavel: remocao e reescrita de referencias, sem comportamento novo.
- Suite completa do produto: ver a linha registrada por `sh scripts/suite-completa.sh` antes do push.

## 5. Gates

| Gate | Skills aplicadas | Achados | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9 | Nao aplicavel ao runtime; verificacoes da secao 4 | Aprovado |
| `protocolo-conformidade` | `clean-architecture` (camadas do pacote: plugin fornece, projeto guarda protocolo, memoria, templates e skills proprias) | `AGENTS.md` reescrito pelo documentation-writer conferido por `git diff --word-diff`: so referencias e uma frase de contexto | Aprovado |

- Ciclo: 1.
- `sh scripts/alteracoes-externas.sh --detectar`: limpo antes do commit.

## 6. QA

Validacao independente (`ai-team:qa-expert`, ciclo 1), sem arquivo `qa-*` (nao ha comportamento novo; a validacao e por inspecao e pelos validadores do projeto):

- Nada removido era unico do projeto: `diff -rq` da arvore anterior (`HEAD~1`) contra o plugin; os unicos arquivos so locais eram `scripts/tests/*.bats` de `governanca-por-hooks`, `instrucoes-do-projeto` e `selecao-de-modelo` (testes do pacote). Onde diferiam, a copia local era a mais antiga. As sete personas existem em `agents/` do plugin, o Tech Lead em `personas/tech-lead.agent.md` e o prompt em `commands/execucao-enxuta.md` (so existencia, sem comparar conteudo).
- Nada que o projeto executa depende do removido: `grep` sem ocorrencia em scripts, tests, `.claude`, runtime, `install.sh`, `CLAUDE.md`, `AGENTS.md` e templates; `scripts/suite-completa.sh` identico ao do plugin; `--mostrar` responde com exit 0.
- Hooks: `.claude/settings.json` valido; `hooks/hooks.json` do plugin cobre `resumo-de-estado` (SessionStart) e `guarda-de-comandos` com `scripts/guarda-de-comandos.txt` do projeto, que existe.
- Referencias: os dois validadores sem erro; amostra de cinco `ai-team:<x>` confere com as skills do plugin.
- Achado informativo: o bloco `ai-team:roteamento` nao existe no `CLAUDE.md` versionado. E esperado: o plugin o escreve no inicio da sessao (`alinhar-instrucoes.sh`) e ele fica sem commit no checkout principal; fora do escopo.
- Veredito do QA: Aprovado, 2026-10-24.

## 7. Riscos e rollback

- Riscos residuais: quem usar o repositorio sem o plugin `ai-team` instalado perde as personas e as 16 skills (owner: solicitante; o `CLAUDE.md` ja manda instalar o plugin pelo bloco de roteamento). Ferramentas que liam `.github/agents/*.agent.md` (por exemplo GitHub Copilot) deixam de ver as personas.
- Impacto: nenhum no produto (`lib/`, `commands/`, `bin/` intocados).
- Rollback: reverter o merge.

## 8. Encerramento

Pendente: QA, suite completa, PR para `develop` e merge do solicitante.
