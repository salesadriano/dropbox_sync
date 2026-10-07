# CLAUDE.md — Instrucoes para o Claude Code no projeto dropbox_sync

> Este arquivo orienta o Claude Code (e qualquer agent) ao operar neste repositorio.
> A fonte autoritativa do protocolo e o pacote de agents em [.github/agents/AGENTS.md](.github/agents/AGENTS.md).
> Em caso de conflito, `AGENTS.md` prevalece; este arquivo e o ponto de entrada e o resumo operacional.

## Contexto do projeto

| Campo | Valor |
|---|---|
| Projeto | `dropbox_sync` — CLI em shell script para integracao com Dropbox API v2 |
| Stack | Shell script (Linux `bash` 4.4+ e POSIX `sh`) + `cURL` (unica dependencia de rede) |
| Arquitetura | Camada de dominio e utilitarios em `lib/`, comandos em `commands/`, entrypoint em `bin/` |
| Persistencia | MVP sem estado local persistente; credencial/token em config local (`~/.config/dropbox_sync/`) |
| Testes | Harness proprio com saida TAP 13 em `tests/run.sh` |
| Linter | `shellcheck` (0.10.0+), verificado nos modos posix e bash |

## Antes de atuar (obrigatorio)

Toda solicitacao entra pelo **Tech Lead** (regra 44): a sessao principal assume esse papel, mesmo quando o pedido nao o menciona.

1. Carregar [.github/agents/AGENTS.md](.github/agents/AGENTS.md) como protocolo comum obrigatorio.
2. Ler a memoria **do papel** (regras 1 e 43):
   - **Tech Lead:** [MEMORIA-COMPARTILHADA.md](.github/agents/memoria/MEMORIA-COMPARTILHADA.md), [MEMORIA-PROJETO.md](.github/agents/memoria/MEMORIA-PROJETO.md) (tabelas congeladas) e o indice completo de `sh scripts/memoria-index.sh`.
   - **Demais agents:** apenas `sh scripts/memoria-index.sh --agente <papel>`. O que faltar chega pelo Tech Lead na delegacao (`--agente <papel> --corpo`).
3. Garantir a estrutura documental com `sh scripts/ensure-docs.sh` (regra 45).
4. Confirmar a stack pela entrada `tipo: stack` (`sh scripts/memoria-index.sh --tipo stack`). Gravar outra so se a stack mudar.
5. Acionar [.github/skills/prompt-logger/](.github/skills/prompt-logger/): **um arquivo por demanda** em `docs/prompts/YYYY-MM-DD_HHMM_slug.md`, com cada prompt da mesma demanda anexado integralmente. **Sanitizar antes de persistir**: remover ou mascarar segredos, credenciais, tokens e dados sensiveis.
6. Classificar o **porte** da demanda (regra 40) e registra-lo no log de prompt.
7. **Branch e worktree da demanda** (regra 46): branch principal **`develop`** (entrada `branch-principal`); sincronizar com o remoto, cruzar os PRs abertos com o escopo, criar branch `feature/<slug>` ou `chore/<slug>` a partir de `develop` e entregar via PR.
8. **Intervencao humana** (regra 48): `sh scripts/alteracoes-externas.sh --inicial` ao iniciar; `--detectar` antes de editar e antes de cada gate, handoff, commit e push; `--registrar <arquivos que o agent alterou>` ao fim de cada passo e `--registrar` apos cada commit proprio.

## Porte da demanda (regra 40)

| Porte | Quando | Efeito principal |
|---|---|---|
| **P** pontual | Nenhum gatilho de M ou G; alteracao localizada (ate ~3 arquivos, sem componente novo) | Pareceres compactos embutidos no registro; o originador redige doc e commit |
| **M** padrao | Toca contrato publico, CLI flags, credenciais, erro/retentativa, novo componente ou defeito critico | Pareceres compactos; `documentation-writer` e `commit-writer` obrigatorios |
| **G** estrutural | Altera arquitetura, System Design, integracao externa ou regra transversal do pacote | Tudo completo; pareceres em arquivos proprios; Mermaid e `historico/` |

## Comandos principais do projeto

| Finalidade | Comando |
|---|---|
| Executar suite de testes | `bash tests/run.sh` (ou `bash tests/run.sh < /dev/null`) |
| Teste unitario isolado | `bash tests/run.sh tests/unit/<arquivo>_test.sh` |
| Teste de integracao isolado | `bash tests/run.sh tests/integracao/<arquivo>_test.sh` |
| Linter estatico | `shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh` |
| Guarda de remocao de testes | `bash scripts/verificar-remocao-de-casos.sh` |
| Validacao de memoria | `sh scripts/memoria-index.sh --check` |
| Geracao do indice de memoria | `sh scripts/memoria-index.sh --write` |
| Validacao de links de skills | `sh scripts/validate-skill-links.sh` |
| Deteccao de alteracoes externas | `sh scripts/alteracoes-externas.sh --detectar` |

## Ciclo de desenvolvimento com subagents

Descricao unica em `AGENTS.md`, secao `Ciclo do developer`:

1. Tech Lead classifica o porte.
2. `senior-developer` implementa sob `protocolo-tdd` e emite parecer de evidencias.
3. Executa `protocolo-conformidade` sobre o diff. Reprovacao volta ao developer.
4. Registro de entrega produzido em `docs/reviews/` (`documentation-writer` em M/G).
5. `qa-expert` valida no modo do porte.
6. `commit-writer` redige mensagem semantica apontando para o registro e prompt.
7. Push da branch e Pull Request para `develop`.
8. Tech Lead revisa, fecha e libera o merge.
