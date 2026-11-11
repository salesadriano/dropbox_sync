# Template - Inventario de testes do projeto

Um unico arquivo versionado por projeto, em `docs/testes/inventario-de-testes.md`, elaborado e mantido pelo QA Expert (regra 51 do `AGENTS.md`; mecanica em `ai-team:protocolo-tdd`). Escrito para o **analista humano**: diz, para cada teste do projeto, onde ele esta, o que prova, por que existe (as regras de origem) e como roda-lo. Complementa o mapa de modulos (Regra 8 de `protocolo-tdd`), que diz **o que rodar**; o inventario diz **o que cada teste prova e de onde veio**. Nao repete parecer, saida de execucao nem registro de entrega: aponta para eles.

Regras de preenchimento:

- **Um bloco por arquivo de teste**, com titulo `## <caminho do arquivo>` (caminho relativo a raiz, entre crases), a lista de campos fixos abaixo e a tabela de casos. A ordem dos blocos segue a do *Resumo*.
- **Uma linha por caso de teste.** A coluna *Caso* traz o **nome exato** do teste como declarado no arquivo (o texto do `@test`, `it(...)`, `test(...)`, `def test_...`, `func Test...`), sem crases, com `|` escrito como `\|`. E por esse nome que `sh scripts/inventario-de-testes.sh --check` casa a linha com o teste.
- **Campos fixos obrigatorios** em todo bloco: *Alvo*, *Modulo*, *Camada*, *Autoria*, *Regras de origem*, *Comando*. *Aceite do solicitante* e obrigatorio quando a autoria e do QA; *Dados e precondicoes* quando houver estado, seeder, container ou servico. Campo sem valor nao leva placeholder: `Nao aplicavel: <motivo>`.
- **Regras de origem** sao rastreaveis, nunca descritivas: regra do `AGENTS.md` (`AGENTS.md 48`), regra de skill (`protocolo-tdd Regra 9`), entrada de memoria (id, com link), requisito ou criterio de aceite (id e documento), issue (`#n`) e o log de prompt da demanda que criou o teste. A coluna *Regra especifica* da tabela so e preenchida quando o caso tem origem propria alem das do bloco.
- **Condicao de execucao** (4a coluna, opcional) so e preenchida em caso condicional (pula sem rede externa, sem root, sem servico, sem variavel): `<condicao> -> <onde ela e satisfeita>`, com o lado direito apontando o lugar verificavel em que o caso de fato roda (ex.: `rede externa -> job e2e-rede da pipeline`; `root -> passo manual registrado em docs/testes/<arquivo>.md`). Vazia, o caso e incondicional. Tabela sem a coluna continua valida: todos os casos dela sao incondicionais. `--check` acusa `CONDICAO` quando a coluna esta preenchida sem ` -> ` ou com o lado direito vazio; caso condicional sem lugar em que rode nao e cobertura.
- **Camada** admite, alem de unitario, integracao, E2E, contrato e fumaca, a camada `meta`: caso que testa a propria suite ou o harness (mutante que prova discriminacao, teste do runner ou do helper de teste). Casos `meta` ficam **fora da piramide 70/20/10**, porque nao sao cobertura do produto; o parecer de testes os conta a parte. O script nao valida o valor de *Camada*.
- **O que verifica** e uma frase de comportamento observavel para quem nao le o codigo: condicao, acao e resultado esperado (ex.: "push para a PR sem suite registrada para o HEAD e bloqueado com exit 2"). Nao repete o nome do caso.
- Linguagem: portugues do Brasil (regra 31), sem segredo, credencial nem dado pessoal (regra 2).

---

# Inventario de testes - <projeto>

Atualizado em: <AAAA-MM-DD>, demanda `<slug>` (`docs/prompts/<arquivo>.md`), por QA Expert.
Conferencia: `sh scripts/inventario-de-testes.sh --check` -> <n arquivos, n casos, 0 divergencias>.
Comando da suite completa: `<comando oficial>` (Regra 8 de `protocolo-tdd`). Mapa de modulos: `<caminho>` ou `Nao aplicavel: <motivo>`.

## Como ler

<Duas a cinco linhas para o analista humano: o que e cada camada no projeto, o que distingue teste do Senior Developer (TDD) e suite independente do QA, onde ficam os aceites e como rodar um arquivo isolado.>

## Resumo

| Arquivo | Alvo | Modulo | Camada | Autoria | Casos | Regras de origem principais |
|---|---|---|---|---|---|---|
| `<caminho do teste>` | `<arquivo ou funcionalidade>` | <modulo> | <unitario \| integracao \| E2E \| contrato \| fumaca \| meta> | <Senior Developer \| QA Expert> | <n> | <AGENTS.md n; entrada ...> |

## `<caminho do teste>`

- **Alvo:** `<arquivo, funcao, rota ou fluxo exercitado>`
- **Modulo:** <identificador do mapa de modulos>
- **Camada:** <unitario | integracao | E2E | contrato | fumaca | meta (fora da piramide)>
- **Autoria:** <Senior Developer (TDD da demanda `<slug>`) | QA Expert (suite independente da demanda `<slug>`)>
- **Regras de origem:** <AGENTS.md n; protocolo-tdd Regra n; [entrada](../../.github/agents/memoria/entradas/<id>.md); requisito RF-n; #n; log `docs/prompts/<arquivo>.md`>
- **Aceite do solicitante:** <[entrada de aceite](...) com sha256 `<hash>` | Nao aplicavel: teste do Senior Developer>
- **Dados e precondicoes:** <seeder, fixture, container, repositorio descartavel, variaveis; ou Nao aplicavel: <motivo>>
- **Comando:** `<comando que roda so este arquivo, com parada no primeiro erro>`
- **Observacoes:** <limites conhecidos, flaky tratado, dependencia de ferramenta; omitir se nada houver>

| Caso | O que verifica | Regra especifica | Condicao de execucao |
|---|---|---|---|
| <nome exato do teste> | <condicao, acao e resultado esperado> | <so quando diferente das do bloco> | <vazio se incondicional; senao `<condicao> -> <onde ela e satisfeita>`> |
