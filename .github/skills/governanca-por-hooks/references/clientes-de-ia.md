# Hooks e permissoes por cliente de IA

O principio da skill nao depende do cliente: regra que o cliente consegue garantir sai da prosa. O mecanismo depende. Esta referencia diz, por cliente, onde a configuracao vive, qual evento corresponde a cada script e o que fazer quando nao ha hook. A sintaxe foi conferida na documentacao vigente em 15/10/2026 e envelhece: reconferir (Context7, regra 30 do `AGENTS.md`) na adocao e a cada atualizacao do cliente.

## Claude Code

Configuracao versionada em `.claude/settings.json` na raiz do projeto (o `.claude/settings.local.json` e do operador e nao e versionado). Exemplo completo: [settings-claude-code.exemplo.json](settings-claude-code.exemplo.json).

| Script | Evento | Como |
|---|---|---|
| `resumo-de-estado.sh` | `SessionStart` | `hooks.SessionStart[].hooks[]` com `type: "command"`, `command: "sh \"$CLAUDE_PROJECT_DIR\"/scripts/resumo-de-estado.sh"`, `timeout: 30`. A saida vai ao contexto da sessao. |
| `guarda-de-comandos.sh` | `PreToolUse` com `matcher: "Bash"` | o cliente envia em stdin um JSON com `tool_input.command` e `cwd`; exit 2 bloqueia o comando e devolve o stderr ao agent; exit 0 libera. |

- `$CLAUDE_PROJECT_DIR` e a raiz do projeto, mesmo quando o agent esta em subdiretorio ou num worktree de subagent.
- `timeout` em segundos; o resumo chama `gh pr list` e, sem rede, pode esperar ate o timeout. Nunca falha a sessao.
- Permissoes: `permissions.allow` com regras `Bash(<prefixo> *)` (a forma `Bash(<prefixo>:*)` e a notacao anterior de prefixo, com o mesmo efeito). `deny` e `ask` sao avaliados antes de `allow`. Exemplo: `"Bash(gh pr merge *)"`, `"Bash(gh run rerun *)"`.
- Hook `type: "prompt"` (avaliacao por modelo) existe e **nao** substitui o guarda: a regra do protocolo e deterministica e precisa de teste.

## GitHub Copilot (VS Code e agente de codificacao)

O ponto de entrada das instrucoes e `.github/copilot-instructions.md` e `.github/instructions/*.instructions.md`. Para hooks de inicio de sessao e de pre-comando, e para permissoes versionadas, **consultar a documentacao vigente do Copilot antes de adotar**: o suporte varia entre o chat no editor, o agente de codificacao e a CLI, e muda entre versoes. Enquanto o cliente usado no projeto nao oferecer o evento, vale a secao *Sem hook* abaixo.

## Cursor, Codex e outros

`.cursor/rules/` e `AGENTS.md` na raiz sao arquivos de instrucao; cada cliente tem (ou nao) o seu mecanismo de hook e de permissao. O mesmo procedimento: consultar a documentacao vigente, mapear cada script ao evento equivalente (inicio de sessao; antes de executar comando de shell), conferir o contrato de entrada (como o comando chega ao hook) e de saida (qual exit bloqueia). Se o contrato de entrada for outro (variavel de ambiente em vez de JSON em stdin, por exemplo), escrever um adaptador de poucas linhas que monte o JSON e chame o guarda, com Bats proprio; nao duplicar a logica do guarda.

## Sem hook

Quando o cliente nao oferece o evento:

1. a regra **continua em prosa** no arquivo de instrucoes; a marca `garantido por hook` nao e escrita;
2. o que for verificavel por script entra na pipeline, no gate rapido antes da suite (Regra 8 de `protocolo-tdd`): o verificador de `instrucoes-do-projeto`, o `--check` da memoria, o `conferir-copias.sh` de `superficie-de-contrato`;
3. o resumo de estado pode ser executado a mao no inicio da demanda (`sh scripts/resumo-de-estado.sh`) e a persona do Tech Lead do projeto o cita como primeiro passo;
4. o guarda pode ser chamado por um wrapper de shell do operador (alias que o invoca antes de `git push`), fora do escopo desta skill e sem a garantia do hook.

O registro de adocao diz qual cliente, quais eventos existem e o que ficou em prosa por falta deles.

## Com mais de um cliente no mesmo projeto

Um arquivo de configuracao por cliente, os dois apontando para os **mesmos** scripts em `scripts/`. A logica vive nos scripts e nos Bats; os arquivos de configuracao so os invocam. Divergencia entre clientes (um bloqueia, outro nao) e registrada na memoria do projeto, porque muda o que a prosa precisa continuar dizendo.
