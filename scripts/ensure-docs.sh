#!/usr/bin/env sh
# Garante a estrutura documental exigida pelo protocolo de governanca (AGENTS.md, regra 45):
#   docs/prompts/   trilha de auditoria dos prompts (prompt-logger)
#   docs/reviews/   registros de entrega (review-documentation) e pareceres de gate em arquivo proprio
#   docs/sources/   material de origem da demanda, sanitizado
# Cria o que faltar, com README explicando o uso; nunca apaga nem sobrescreve.
# Uso: sh scripts/ensure-docs.sh [raiz-do-projeto]   (padrao: raiz do repositorio onde o script esta)

set -eu

root=${1:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
created=0

ensure() {
  d="$root/docs/$1"; readme="$d/README.md"
  [ -d "$d" ] || { mkdir -p "$d"; created=1; echo "criado: docs/$1/"; }
  [ -f "$readme" ] || { printf '%s\n' "$2" > "$readme"; created=1; echo "criado: docs/$1/README.md"; }
}

[ -d "$root/docs" ] || { mkdir -p "$root/docs"; created=1; echo "criado: docs/"; }
[ -f "$root/docs/README.md" ] || { cat > "$root/docs/README.md" <<'MD'
# docs/

Estrutura documental exigida pelo protocolo de governanca (`.github/agents/AGENTS.md`, regra 45). Os tres diretorios sao versionados com o projeto e recriados por `sh scripts/ensure-docs.sh` quando faltarem.

| Diretorio | Conteudo | Quem grava |
|---|---|---|
| `prompts/` | trilha de auditoria dos prompts, um arquivo por demanda (`prompt-logger`) | todo agent que recebe solicitacao |
| `reviews/` | registros de entrega (`review-documentation`) e pareceres de gate em arquivo proprio (porte G) | Senior Developer, documentation-writer, Tech Lead |
| `sources/` | material de origem da demanda: especificacoes, documentos, planilhas, links, sanitizados | Business Analyst, Tech Lead |

Nada aqui recebe segredo, credencial, token, cookie, chave, dump de producao ou dado pessoal desnecessario: sanitizar antes de gravar, nunca depois.
MD
created=1; echo "criado: docs/README.md"; }

ensure prompts "# docs/prompts/

Trilha de auditoria dos prompts recebidos, um arquivo por demanda, nome \`YYYY-MM-DD_HHMM_slug.md\`, conforme a skill \`prompt-logger\` e a regra 2 do protocolo comum. Sanitizar antes de gravar: este diretorio e versionado."

ensure reviews "# docs/reviews/

Registros de entrega produzidos conforme a skill \`review-documentation\` (regra 41 do protocolo comum), nome \`YYYY-MM-DD-HHMM-slug.md\`, um por demanda com codigo. Em porte G, os pareceres de gate (\`evidencia-testes\`, \`parecer-conformidade\`) e os fechamentos do Tech Lead ficam aqui em arquivos proprios, referenciados pelo registro. Sanitizar evidencias copiadas de ambientes reais."

ensure sources "# docs/sources/

Material de origem da demanda: especificacoes, documentos, planilhas, transcricoes e links fornecidos pelo solicitante ou coletados pelo Business Analyst. Um subdiretorio por demanda (\`YYYY-MM-DD-slug/\`). Arquivo grande ou binario entra por link, nao por copia. Conteudo sensivel e sanitizado antes de gravar; o que nao puder ser sanitizado fica fora do repositorio e e referenciado por localizacao."

[ "$created" -eq 1 ] || echo "estrutura docs/ completa"
