# Comandos Locais de Verificacao

Tudo aqui roda na maquina do agent, sobre o repositorio de trabalho. Nenhum comando depende de pipeline, CI ou servico remoto.

Regra de seguranca: revisar cada comando antes de executar, preferir ferramentas ja declaradas no projeto e nunca canalizar script remoto para shell.

## 1. Levantar o escopo do diff

```bash
git status --short                      # o que esta modificado, incluindo nao rastreado
git diff --stat                         # dimensao da alteracao
git diff --name-only                    # arquivos alterados nao commitados
git diff --cached --name-only           # arquivos em stage
git diff                                # conteudo para leitura
git diff --cached                       # conteudo em stage
```

Alteracao ja commitada na branch de trabalho:

```bash
git merge-base HEAD <base>              # descobrir o ponto de divergencia
git diff --name-only <base>...HEAD
git diff <base>...HEAD
```

Filtrar por tipo de arquivo, para direcionar a skill de stack:

```bash
git diff --name-only | grep -E '\.(ts|tsx|js|jsx)$'
git diff --name-only | grep -E '\.(py)$'
git diff --name-only | grep -E '\.(php)$'
git diff --name-only | grep -E '\.(cs)$'
git diff --name-only | grep -E '\.(sql)$|migrations?/'
git diff --name-only | grep -E '\.(sh|bats)$'
```

## 2. Sinais rapidos de violacao arquitetural

Estes comandos apontam candidatos a achado. O resultado nunca e conclusivo sozinho: confirmar lendo o codigo.

Import de framework ou infraestrutura dentro da camada de dominio:

```bash
# ajustar o caminho de dominio ao layout real do projeto
grep -rnE "^\s*(import|from|using)\b" --include=*.{ts,js,py,cs,php,go,java} src/domain/ \
  | grep -iE "express|fastify|nest|django|flask|fastapi|sqlalchemy|prisma|typeorm|sequelize|mongoose|axios|entityframework|microsoft\.entityframework|eloquent|illuminate"
```

Acesso direto a dados fora da camada de infraestrutura:

```bash
grep -rnE "(SELECT |INSERT INTO|UPDATE .* SET|DELETE FROM|createConnection|getRepository|\.query\(|\.raw\()" \
  --include=*.{ts,js,py,cs,php} src/ | grep -v -E "infra|infrastructure|persistence|repositor"
```

Regra de negocio no controller/endpoint:

```bash
grep -rnE "class .*Controller|@(Get|Post|Put|Patch|Delete)\(|app\.(get|post|put|patch|delete)\(|def (get|post|put|patch|delete)" \
  --include=*.{ts,js,py,cs,php} src/ -A 30 | grep -nE "if |for |while |calculate|compute|total|desconto|discount"
```

Segredo introduzido pelo diff:

```bash
git diff | grep -nE "^\+.*(password|passwd|secret|token|api[_-]?key|private[_-]?key|BEGIN [A-Z ]*PRIVATE KEY)\s*[:=]"
```

## 3. Ciclos de dependencia

Escolher o que ja existir no projeto; nao instalar ferramenta nova sem aprovacao.

```bash
npx madge --circular src/                 # JS/TS, se madge estiver disponivel
npx dpdm --no-warning --no-tree src/      # alternativa JS/TS
python -m pydeps <pacote> --show-cycles   # Python, se pydeps estiver disponivel
dotnet list package --include-transitive  # .NET, visao de dependencias
```

Sem ferramenta disponivel, mapear manualmente os imports dos arquivos alterados e verificar se algum modulo interno passou a importar quem o importa.

## 4. Verificadores ja declarados pelo projeto

Executar apenas o que o projeto ja define em `package.json`, `pyproject.toml`, `composer.json`, `Makefile` ou equivalente:

```bash
npm run lint && npm run typecheck        # ou o script equivalente do projeto
ruff check . && mypy .                   # Python, se configurados
composer run-script phpstan              # PHP, se configurado
dotnet build -warnaserror                # .NET
git diff --name-only -- '*.sh' | xargs -r shellcheck   # shell, dialeto pelo shebang (shellcheck-configuration)
sh -n <script>                           # shell, sintaxe; sempre disponivel, inclusive sem shellcheck
```

Resultado de linter e type checker entra no parecer como evidencia de apoio, nunca como substituto da leitura do diff. Ferramenta ausente vira limitacao registrada, nao dispensa a verificacao.

## 5. Consistencia com o que ja existe

```bash
git log --oneline -10 -- <arquivo>       # historico do arquivo alterado
git log -S"<simbolo>" --oneline          # onde o simbolo foi introduzido ou removido
grep -rn "<nome-do-componente>" src/     # ja existe implementacao equivalente?
```
