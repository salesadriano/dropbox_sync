# docs/

Estrutura documental exigida pelo protocolo de governanca (`.github/agents/AGENTS.md`, regra 45). Os tres diretorios sao versionados com o projeto e recriados por `sh scripts/ensure-docs.sh` quando faltarem.

| Diretorio | Conteudo | Quem grava |
|---|---|---|
| `prompts/` | trilha de auditoria dos prompts, um arquivo por demanda (`prompt-logger`) | todo agent que recebe solicitacao |
| `reviews/` | registros de entrega (`review-documentation`) e pareceres de gate em arquivo proprio (porte G) | Senior Developer, documentation-writer, Tech Lead |
| `sources/` | material de origem da demanda: especificacoes, documentos, planilhas, links, sanitizados | Business Analyst, Tech Lead |

Nada aqui recebe segredo, credencial, token, cookie, chave, dump de producao ou dado pessoal desnecessario: sanitizar antes de gravar, nunca depois.
