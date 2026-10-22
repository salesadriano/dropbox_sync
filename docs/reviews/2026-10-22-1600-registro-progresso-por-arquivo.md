# Registro de entrega: progresso por arquivo (fase 10, F-49)

## Identificacao

| Campo | Valor |
|---|---|
| Porte | **G** (muda a saida de progresso nos tres comandos de transferencia e o desenho de saida do paralelismo da fase 9; toca o System Design) |
| Log de prompt | [2026-10-22_1600_progresso-por-arquivo.md](../prompts/2026-10-22_1600_progresso-por-arquivo.md) |
| Memoria de decisao | `.github/agents/memoria/entradas/2026-10-22-1600-progresso-por-arquivo.md` |
| Requisitos | Secao 5.19 do [escopo](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) (v1.27): `RF-140` a `RF-147`, `TC-PRG-01` a `TC-PRG-36`, `F-49`; divergencias `DIV-282` a `DIV-306` (secao 9) |
| Branch / base | `feature/progresso-por-arquivo` sobre `develop` @ `a39a89e` (fase 9 mesclada, PR #52) |
| Issues vinculadas | nenhuma |
| Agents | Business Analyst (especificacao); Senior Developer (implementacao e ajuste final); QA Expert (validacao independente); Tech Lead (decisoes DIV e aceites); Documentation Writer (este registro e o System Design) |
| Data | 2026-10-22 |
| Status | aberto: aguardando ajuste final do Senior Developer (QA-B10-01 e QA-B10-02), reexecucao e commit |

## Contexto e objetivo

O percentual e a barra no fim da linha do `upload` e do `download` (e do `sync`, que mostrava o percentual do plano inteiro) passam a medir o arquivo em curso. A linha aparece no inicio do processamento do arquivo e avanca a cada parte processada. Com `--paralelo N` (N > 1), o terminal mostra um bloco de ate N linhas, uma por arquivo ativo. Sem terminal com `--progresso`, cada atualizacao vira linha nova.

Antecedente: o commit `cdac965` (branch `feature/progresso-transferencia-arquivo`, nunca enviada) tentou algo parecido sobre `cec9873`. O solicitante o descartou em 2026-10-22; esta demanda foi refeita sobre a `develop` atual.

## Decisao

Decisoes do solicitante (AskUserQuestion, 2026-10-22): bloco de N linhas com paralelo; download por bytes recebidos do `.part`; sem terminal, linha a cada parte.

Decisoes do Tech Lead: as DIV-282 a DIV-294 foram resolvidas na opcao recomendada pelo BA. As de maior efeito:

- amostragem do `.part` a 0,25 s com terminal e uma linha a cada 10 pontos percentuais sem terminal (`DIV-282`);
- barra de 10 celulas (`DIV-283`); `--dry-run` sem linha por arquivo (`DIV-285`);
- sem terminal com N > 1, ordem de chegada com o `[i/N]` (`DIV-289`);
- o auxiliar informa o avanco por arquivo num diretorio temporario `0700`, lido pelo principal (`DIV-290`);
- retomada comeca no percentual real, nao em 0% (`DIV-294`, desvio declarado do literal do BA).

As DIV-295 a DIV-306 surgiram na implementacao e foram resolvidas pelo Tech Lead em 2026-10-22 (ver a secao 9 do escopo). Destaques: `apagando` no `sync` fica fora do `RF-140` (`DIV-296`); total com `size` da listagem no `sync --receber` (`DIV-297`); `TC-PRG-15` mantido como regressao (`DIV-299`); espera de 0,2 s no paralelo aceita e documentada (`DIV-301`); casos de QA para cache entre N=1 e N>1 e para amostragem com `.part` sintetico (`DIV-302`, `DIV-303`); percentual da linha de falha e o ultimo atingido (`DIV-305`); `.tag=file` como unico criterio para abrir a linha do download (`DIV-306`).

### ADR resumido

- **Decisao:** o avanco nasce no processo que faz a transferencia. Em N = 1 o principal desenha a linha. Em N > 1 cada auxiliar grava o status do seu item em arquivo proprio (diretorio `0700`, nome unico por escritor, `mv`), e so o principal desenha.
- **Alternativas (opcoes A/B das DIVs, escopo secao 9):** amostragem fixa versus evento por parte (`DIV-282`); espera por sinal versus sondagem de 0,2 s (`DIV-301`); cache comparado so pelo nome ou pelo conteudo (`DIV-302`).
- **Trade-offs:** a sondagem custa ate 0,2 s de resposta a sinal, aceita com progresso ativo. O observador do `.part` custa uma leitura de tamanho a cada 0,25 s, restrita ao progresso ativo. O status em arquivo mantem a regra RF-135(a) (so o principal escreve em stderr) sem canal compartilhado.
- **Restricao verificada:** a regra "so o processo principal escreve saida no paralelo" (`RF-135(a)`) continua valida; o auxiliar tem stderr em `/dev/null`.

## Escopo tecnico e arquivos modificados

Conferencia de arquivos por `git status --short` na worktree em 2026-10-22. Contagens por arquivo: `git diff --stat` (a medir pelo Tech Lead; so `lib/progress.sh` esta medido: +461/-16, conforme parecer de conformidade).

Codigo alterado:
- `lib/progress.sh`
- `lib/transfer.sh`
- `lib/cmd.sh`
- `lib/http.sh` (barra do cURL retirada da saida)
- `commands/sync.sh`
- `commands/upload.sh`
- `commands/download.sh`
- `bin/dbx` (ajuda)
- `README.md`

Testes e documentacao alterados:
- `tests/unit/progress_test.sh` (8 asserções trocadas para negativas, ver parecer de TDD secao 6)
- `tests/integracao/comandos_test.sh` (2 asserções: `progress-bar` ausente, `DIV-293`)
- `tests/integracao/retomada_download_test.sh`
- `tests/integracao/progresso_arquivo_test.sh` (novo)
- `tests/integracao/qa_progresso_arquivo_b10_test.sh` (novo; suite do QA, sha256 `fab96fad4e4aa1c67b3905c728b7004870031975618c030cba7987fc10ff5956`)
- `tests/unit/progresso_linha_test.sh` (novo)
- `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (secao 5.19, DIV-282 a DIV-306)
- `docs/requisitos/funcionalidades-candidatas.md`
- `docs/arquitetura/system-design.md` (secao "Progresso por arquivo (fase 10, v1.20)")
- `docs/reviews/2026-10-22-1600-*` (pareceres, validacao e este registro)
- `docs/prompts/2026-10-22_1600_progresso-por-arquivo.md`
- `.github/agents/memoria/entradas/2026-10-22-1600-progresso-por-arquivo.md`

Em andamento, fora deste registro ate a conclusao: ajuste final do Senior Developer em `commands/sync.sh` e nos testes (QA-B10-01 e QA-B10-02).

## Diagrama (Mermaid)

O diagrama do fluxo de progresso esta na secao "Progresso por arquivo (fase 10, v1.20)" do System Design: [system-design.md](../arquitetura/system-design.md).

## Evidencias de validacao

### Gates

| Gate | Ciclo | Situacao | Parecer |
|---|---|---|---|
| `protocolo-tdd` | 2 | Aprovado com ressalvas (ciclo 1 reprovado com 5 maiores) | [parecer de evidencias de testes](2026-10-22-1600-parecer-tdd-progresso-por-arquivo.md) |
| `protocolo-conformidade` | 2 | Aprovado com ressalvas (residuais 5, 7, 9 e 10) | [parecer de conformidade](2026-10-22-1600-parecer-conformidade-progresso-por-arquivo.md) |

### Validacao independente do QA

Veredito: aprovado com ressalvas. Suite nova `tests/integracao/qa_progresso_arquivo_b10_test.sh`, 8 casos, sem alteracao de codigo do produto. Detalhe em [validacao do QA](2026-10-22-1600-validacao-qa-progresso-por-arquivo.md).

| Achado do QA | Severidade | Situacao |
|---|---|---|
| QA-B10-01 | Menor (pre-existente, fora do diff): mensagens `[sync] analisando local` e `[sync] analise [i/N]` ecoam o nome cru | Em ajuste final do Senior Developer. Pendente de reexecucao |
| QA-B10-02 | Maior (processo): auditoria `json` caso 42 reprova por `$(printf` nos testes do developer | **Pendente.** Bloqueia a pipeline; corrigir antes do push para a PR |
| QA-B10-03 | Menor (limitacao): recebimento nao prova igualdade de conteudo na memoria (`lib/state.sh:88`) | Aceito como risco residual baixo (ver secao de riscos) |

### Testes rodados

Contagens literais dos pareceres e da validacao do QA. Quem as produziu esta indicado; nao foram reexecutadas por este registro.

| Comando | Resultado | Fonte |
|---|---|---|
| `bash tests/run.sh qa_progresso_arquivo_b10 < /dev/null` | aprovados 8, reprovados 0, pulados 0 | validacao do QA |
| `bash tests/run.sh progresso_ < /dev/null` (progress_test, progresso_arquivo_test, qa_progresso_arquivo_b10, progresso_linha) | aprovados 61, reprovados 0, pulados 0 | validacao do QA |
| `bash tests/run.sh progresso_ < /dev/null` (ciclo 2, sem mutacao) | 48 aprovados (30 + 18), 0 reprovados | parecer de TDD, ciclo 2 |
| `bash tests/run.sh retomada_download` (ciclo 2, sem mutacao) | 28 aprovados, 0 reprovados | parecer de TDD, ciclo 2 |
| `bash tests/run.sh progresso` (ciclo 1, sem mutacao) | 36 aprovados (17 + 19), 0 reprovados | parecer de TDD, ciclo 1 |
| `bash tests/run.sh qa_desempenho` | aprovados 15, reprovados 0, pulados 0 | validacao do QA |
| `bash tests/run.sh harness` | aprovados 22, reprovados 0, pulados 0 | validacao do QA |
| `bash tests/run.sh json` | aprovados 41, reprovados 1 (caso 42, QA-B10-02), 20 nao executados pela parada no primeiro erro | validacao do QA |
| Ajuste final (QA-B10-01 e 02), Senior Developer, um por vez: `progresso_` / `sync_test` / `json` / `harness` / `retomada_download` / `comandos` | 62 / 85 / 62 / 22 / 28 / 119 aprovados, 0 reprovados em todos | hand-back do Senior Developer, ajuste final |
| `sh scripts/lint.sh` no ajuste final: `lib/progress.sh`, `commands/sync.sh`, `commands/download.sh`, `tests/unit/progresso_linha_test.sh`, `tests/integracao/progresso_arquivo_test.sh`, `tests/integracao/comandos_test.sh` | exit 0 em todos | hand-back do Senior Developer, ajuste final |
| Contagens declaradas pelo Senior Developer no log (nao reexecutadas pelo gate): `progress_test` 16, `comandos` 119, `sync` 85, `paralelo` 14, `lote` 32, `tmp` 16, `qa_` 490 | declarado | parecer de TDD, secao 1 |
| `sh scripts/lint.sh tests/integracao/qa_progresso_arquivo_b10_test.sh` | sem avisos | validacao do QA |
| `sh scripts/lint.sh` nos arquivos de codigo alterados (`lib/progress.sh`, `commands/download.sh`, `commands/sync.sh`) | sem saida de erro | parecer de conformidade, ciclo 2 |
| **Suite completa local (`sh scripts/suite-completa.sh`)** | **(a medir)** | pendente: so depois do ajuste final, no HEAD do commit |

Ressalva "a" do gate de TDD, fechada antes da PR: TC-PRG-05, 18, 24, 26 e 36 ganharam caso proprio em `tests/integracao/progresso_arquivo_test.sh` (os cinco passaram de primeira, caracterizacao).

Validacao do red: o red de TDD foi comprovado por mutacao para M1 a M4 (ciclo 2): M1 e M4 mortas em `progresso_` e `retomada_download`; M2 e M3 mortas no ciclo 1. A etapa 1 teve 11 de 12 casos escritos depois do codigo (desvio declarado, nao reincidente).

## Riscos, impacto e rollback

### Riscos residuais

- **Conformidade (residuais, risco aceito pelo Tech Lead):**
  - achado 5: `lib/progress.sh` concentra linha unica e bloco N>1 (`comp-common-closure`), ~650 linhas;
  - achado 7: observador herda descritores; sobra o `sleep` filho por ate 0,25 s;
  - achado 9: nome com byte 0x9B em locale de bytes (C/POSIX) nao e neutralizado;
  - achado 10: espera por sondagem de 0,2 s com bloco ativo (`DIV-301`).
- **Conformidade (residual de 4):** `dbx_progress_transferencia` sem chamador de producao (codigo de teste).
- **TDD, achado 9 (menor, corrigido):** `TC-PRG-35` usa `git archive a39a89e` e agora e pulado com mensagem explicita quando o commit nao existe no clone (copia sem `.git`, CI com checkout raso). O ramo do pulo nao foi exercitado, porque o commit existe aqui.
- **QA-B10-03 (menor):** o arquivo recem-baixado nao entra na memoria do `sync --receber` (`lib/state.sh:88`); a igualdade de conteudo com `hash nome` so e provada no envio.
- **QA-B10-01 e QA-B10-02:** corrigidos no ajuste final. QA-B10-02: `$(printf` trocado por `printf -v` e expansao de parametro nos testes; a auditoria `json` pegou tambem `dbx_progress_tamanho_de` chamado por substituicao de comando, que passou a devolver por variavel. QA-B10-01: `dbx_progress_neutralizar` em `lib/progress.sh`, usada pelas seis mensagens de analise do `sync`. As duas correcoes tocaram codigo de producao depois da validacao do QA; a suite do QA continua verde (`progresso_` 62/0).
- **`DIV-301`:** espera de 0,2 s no laco do paralelo; um sinal pode esperar ate 0,2 s. Aceito e documentado.
- **Custo de download:** com progresso ativo e `--sem-retomada`, o download faz uma chamada `get_metadata` a mais (`DIV-304`, restrita ao progresso ativo). Se o metadado falhar, o arquivo e baixado sem linha de progresso (degradacao silenciosa aceita).

### Impacto

- Contrato externo: nenhum endpoint novo. `stdout` nao muda (`RF-145(a)`, `TC-PRG-25`).
- Codigos de saida: nenhum novo.
- Estado: nenhum estado persistente novo. Os arquivos temporarios de status ficam no diretorio da area do ciclo, removida por `lib/tmp`.
- Dependencia de ambiente: `TC-PRG-35` compara com o commit `a39a89e` e e pulado quando ele nao existe.

### Rollback

- `git revert -m 1 <merge>` da fase em `develop` (hash do merge a preencher no fechamento).
- Sem migracao de dado e sem estado persistente novo.
- Apos o revert, a linha volta a mostrar o percentual do plano, e o paralelismo volta sem bloco de N linhas.

## Proximos passos

1. Suite completa local (`sh scripts/suite-completa.sh`) no HEAD final; anotar a linha em "Testes rodados".
2. Commit com os arquivos desta entrega; corpo com as linhas `Registro:` e `Prompt:`; push e PR para `develop`.
3. Apos o merge: `sh scripts/limpar-worktrees.sh`.

## Aceites

- **Solicitante:** suite do QA `tests/integracao/qa_progresso_arquivo_b10_test.sh`, 8 casos, sha256 `fab96fad4e4aa1c67b3905c728b7004870031975618c030cba7987fc10ff5956`: "Aceito (Recomendado)", 2026-10-22. A aceitacao vale para o sha acima: se a suite mudar, o aceite precisa ser refeito.
- **Senior Developer:** pendente (ajuste final de QA-B10-01 e 02).
- **QA Expert:** aprovado com ressalvas ([validacao](2026-10-22-1600-validacao-qa-progresso-por-arquivo.md)).
- **Tech Lead:** decisoes DIV-282 a DIV-306 registradas no escopo. Revisao consolidada e aprovacao final: pendente, condicionadas ao ajuste final, a reexecucao, a suite completa e ao commit.
- **Commit e PR:** pendente. Este registro nao faz commit.
