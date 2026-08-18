# 2026-08-18 — Fechamento do incremento 1 da Etapa 2 (`lib/json` + `lib/output`)

Registro de historico da memoria de projeto. Detalhamento completo em
`docs/registros/2026-08-18_revisao-consolidada-etapa-2-incremento-1.md` e
`docs/registros/2026-08-18_aprovacao-final-etapa-2-incremento-1.md`.

## Decisao

**APROVADO COM RESSALVAS** (`PRJ-DEC-36`, `TL-11`). Um gate bloqueia a Etapa 3: `PRJ-DEC-38`.

## Ciclos de QA

| Ciclo | Decisao | Achados |
|---|---|---|
| 1 | REPROVADO | 13 defeitos, 2 de severidade ALTA (`E2-01`, `E2-02`) |
| 2 | APROVADO COM RESSALVA | `E3-01` a `E3-07` |
| 3 | APROVADO COM RESSALVA | `E4-01` a `E4-04` |

Uma reprovacao contra o limite de tres. **Sem escalonamento ao solicitante.**

## Verificacao independente do Tech Lead

| Verificacao | Resultado |
|---|---|
| `bash tests/run.sh` | 237 aprovados / 0 reprovados / 2 pulados |
| `shellcheck -x` sobre `lib/`, `tests/` | exit 0 |
| Arvore git | limpa; `HEAD` = `origin/feature/camada-dominio-e-adaptadores` (`bf3ff0d`); 0 commits nao publicados |
| Bytes de controle em 15 documentos | zero |
| `E2-01` / `E2-02` | fechados por construcao; segmento contendo o separador nao colide |
| Contexto nomeado | ponta a ponta; `cursor` e `entries 1 name` preservados; 9 nomes invalidos recusados |
| `E4-01` | nos estaveis em 8 ao longo de 5 reanalises com lixo; faixa fechada em todos os desfechos |
| Coerencia classe x politica | 10 pares, nenhuma contradicao |

### Mutacoes proprias

| ID | Mutacao | Suite | Leitura |
|---|---|---|---|
| M1 | remove o registro de `FIM` da faixa de nos | 4 reprovacoes | ciclo de vida pinado; condicao 2 do QA cumprida |
| M2 | afrouxa a guarda de nome de contexto | 3 reprovacoes | criterio 4 de `RNF-24` cumprido **para a guarda** |
| M3 | sitio de chamada compondo o nome a partir de `error.tag` da resposta | **237/0/2, shellcheck 0** | **nada detecta** — origem do gate `PRJ-DEC-38` |

## Decisoes registradas

`PRJ-DEC-36` a `PRJ-DEC-43`, correspondendo aos gates `TL-10` a `TL-20`.

Destaques:

- `TL-10` — condicao de `TL-01` satisfeita; aceite dos codigos 5 a 15 confirmado em definitivo.
- `TL-12` — `RNF-24` criterio 3 declarado NAO VERIFICADO; gate bloqueante para a Etapa 3.
- `TL-14` — `RSK-25` encerrado, `DIV-15` retirada, **retratacao formal em favor do Senior Developer**, e `TL-09` refundado sobre `RSK-26`.
- `TL-16` — `DIV-17` nao vira gate; fica o criterio de que sondagem direta, e nao contagem de casos, dimensiona confianca.
- `TL-17` — checkpoint de propagacao de decisao instituido. **Transversal ao pacote: pendente de entrada em `MEMORIA-COMPARTILHADA.md`, nao alterada por restricao do solicitante.**
- `TL-19` — colisao de identificadores e bloco duplicado corrigidos nesta propria memoria.

## Correcao estrutural aplicada a esta memoria

- `PRJ-DEC-22`, `PRJ-DEC-23` e `PRJ-DEC-24` designavam **dois conjuntos distintos** de decisoes. O conjunto do fechamento da Etapa 1 foi renumerado para `PRJ-DEC-33`, `PRJ-DEC-34` e `PRJ-DEC-35`.
- As oito linhas de `PRJ-DEC-25` a `PRJ-DEC-27` apareciam **duas vezes byte a byte**. Duplicata removida.
- Estado apos a correcao: 43 decisoes, identificadores unicos e contiguos de `PRJ-DEC-01` a `PRJ-DEC-43`.

## Bloqueios que dependem exclusivamente do solicitante

| Item | Estado em 2026-08-18 |
|---|---|
| `DP-20` | 🔴 **ABERTO** — titular do copyright; `LICENSE` publicado com espaco reservado no historico publico |
| `DEC-STR-07` | 🔴 **ABERTO** — aprovacao formal sobre os testes do QA, com o template proprio |
| `TL-17` em `MEMORIA-COMPARTILHADA.md` | ✅ **RESOLVIDO como desvio** — autorizacao **NEGADA**. `TL-09` e `TL-17` valem so neste projeto (`PRJ-DEC-41`) |
| PR de entrega | ✅ **RESOLVIDO** — PR [#1](https://github.com/salesadriano/dropbox_sync/pull/1) aberto com label `review` (`PRJ-DEC-44`) |

## Respostas do solicitante ao fechamento (2026-08-18)

### `MEMORIA-COMPARTILHADA.md` — autorizacao NEGADA

`TL-09` e `TL-17` ficam registrados **apenas neste projeto**. Motivo concreto: o arquivo veio do pacote `ai_team` e e usado tambem em
`/home/sales/diad` e `/home/sales/comprac_app`; alterar a copia local nao propaga e criaria divergencia entre copias do mesmo pacote.

**Desvio ao item 32 do protocolo comum registrado em `PRJ-DEC-41`.** A regra transversal existe e vale aqui, **sem** a contrapartida na memoria geral.
**Rastreabilidade obrigatoria:** se o pacote for um dia sincronizado a partir da origem, `TL-09` e `TL-17` precisam reaparecer como candidatas a memoria geral.

### PR aberto — item 25 atendido com desvio justificado

PR [#1](https://github.com/salesadriano/dropbox_sync/pull/1), `feature/camada-dominio-e-adaptadores` -> `develop`, label `review`, estado OPEN.
Convencao semantica de commits e nomenclatura Gitflow atendidas. **Review request nativa nao atribuida:** repositorio de colaborador unico,
sem revisor distinto do autor a designar — **desvio justificado, nao pendencia** (`PRJ-DEC-44`).

**Divergencia de contagem esclarecida pelo Tech Lead:** o corpo do PR declara doze commits semanticos e o PR expoe **onze**.
Os doze existem e sao todos semanticos, mas o duodecimo — `2b3698f docs: fechamento do incremento 1 da Etapa 2`, que versiona os artefatos
deste fechamento — **existe apenas no repositorio local e nao foi publicado**. `origin/feature/camada-dominio-e-adaptadores` continua em `bf3ff0d`.

> **Consequencia operacional:** o PR descreve o fechamento mas **ainda nao contem os documentos de fechamento**.
> Antes do merge, o solicitante precisa publicar `2b3698f` e o commit das correcoes posteriores desta rodada.

### Licao de processo registrada (`PRJ-DEC-45`)

**Entregar estado ja verificado transfere o ponto cego junto.** O relato de que `RNF-24` estava satisfeito era verdadeiro para a guarda de alfabeto
e falso para a procedencia; so apareceu porque o Tech Lead escreveu a mutacao que o criterio 3 descreve (M3) em vez de aceitar que o criterio 4 a cobria.
Confirmado depois pelo coordenador de forma independente: `path`, `conflict`, `too_many_write_operations`, `incorrect_offset` e `restricted_content`
passam todas pela guarda, e a unica auditoria estatica existente busca captura por `$( )`, que **nao alcanca** `dbx_json_contexto "$tag"`.
**Irma de `RSK-27`:** la o instrumento cobre so a forma obvia da classe; aqui o relato cobre so a parte obvia do criterio.

```mermaid
flowchart LR
  A[Incremento entregue] --> B[QA ciclo 1 REPROVADO]
  B --> C[QA ciclo 2 APROVADO COM RESSALVA]
  C --> D[QA ciclo 3 APROVADO COM RESSALVA]
  D --> E[Tech Lead reexecuta e muta]
  E --> F[Aprovado com ressalvas]
  F --> G[Gate PRJ-DEC-38 bloqueia Etapa 3]
```
