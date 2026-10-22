# Faixa do modelo por cliente de IA

A decisao da faixa e a de `faixa-do-modelo.sh`; o mecanismo que a aplica depende do cliente. Sintaxe conferida na documentacao vigente em 16/10/2026 (Context7, regra 30 do `AGENTS.md`) e envelhece: reconferir na adocao e a cada atualizacao do cliente. Identificadores de modelo ficam na tabela do projeto e no `model:` das personas; esta referencia nao os repete.

## Claude Code

Subagents em `.claude/agents/<nome>.md` (ou no diretorio equivalente que o projeto declara), frontmatter YAML.

| Mecanismo | Onde | Como |
|---|---|---|
| `model:` da persona | frontmatter do subagent | alias `haiku`, `sonnet`, `opus` ou `fable`; `inherit` para herdar o modelo da sessao; ou o id completo (mesmos valores de `--model`) |
| parametro por invocacao | chamada da ferramenta `Agent` | `model: "<alias ou id>"`; vale tambem quando o subagent e retomado |
| variavel de ambiente | `CLAUDE_CODE_SUBAGENT_MODEL` | alias ou id para todo subagent sem `model:` |
| hook de criacao | mod com hook `agent.spawn` | pode fixar o modelo e **sobrepoe** o parametro por invocacao |

Ordem de resolucao (da documentacao, v2.1.251 ou posterior): parametro por invocacao, depois `model:` do frontmatter (`inherit` = sessao), depois a variavel de ambiente, depois o modelo da sessao. Dois cuidados:

- Alias de **familia** (`opus`) resolve para o modelo exato da sessao quando a sessao ja e dessa familia, inclusive o sufixo de contexto estendido; para a faixa `maximo` isso e o comportamento desejado (herdar, nunca descer).
- A organizacao pode restringir modelos (`availableModels`); valor bloqueado e substituido e o cliente avisa. `/tasks` mostra o modelo em que cada subagent roda. O subagent herda a configuracao de raciocinio estendido da sessao; nao ha ajuste por subagent.

Mapa das faixas para o alias: `economico` -> `haiku`, `padrao` -> `sonnet`, `maximo` -> `inherit` (ou `opus`/`fable` quando a sessao estiver abaixo da faixa e o projeto quiser subir explicitamente). A tabela do projeto registra qual.

## GitHub Copilot (agentes personalizados `.agent.md`)

O frontmatter do `.agent.md` aceita `model:` com o nome do modelo como aparece no seletor do Copilot (o pacote ja usa essa forma em `commit-writer.agent.md`). Os nomes do seletor e os modelos disponiveis dependem do plano e mudam: a tabela do projeto registra o nome exato por faixa, e a persona de faixa `maximo` **nao fixa** `model:` (herda o da sessao). Parametro por invocacao e hook de criacao: consultar a documentacao vigente antes de adotar; enquanto nao existirem, a faixa fixa-se so pela persona.

## Codex, Cursor e outros

Cada cliente tem (ou nao) um mecanismo de modelo por subagent. Mesmo procedimento: localizar na documentacao vigente onde o modelo de um agent delegado e declarado, mapear as tres faixas para os valores aceitos, registrar na tabela do projeto e na entrada de adocao. Sem mecanismo por subagent, a faixa vale so para a sessao (escolha do operador) e a skill continua util pela conta do `avaliar-troca-de-modelo.sh`, que diz quando **nao** vale a pena abrir outra sessao.

## Com mais de um cliente no mesmo projeto

Uma configuracao por cliente, todas lendo a **mesma** `scripts/tabela-de-modelos.tsv`. A logica (classe, piso, calculo) vive nos scripts e nos Bats; os arquivos de configuracao so aplicam o alias. Divergencia entre clientes (um oferece faixa, outro nao) e registrada na memoria do projeto.
