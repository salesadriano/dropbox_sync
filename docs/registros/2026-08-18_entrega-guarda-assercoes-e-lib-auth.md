# Registro Tecnico de Entrega — Guarda de Remocao, Assercoes do Arcabouco e `lib/auth`

## Identificacao

| Campo | Valor |
|---|---|
| Incremento | guarda de remocao de casos, endurecimento das assercoes, `lib/auth` |
| Branch | `feature/http`, a partir de `develop` |
| Papel | Senior Developer |
| Data | 2026-08-18 |
| Estado | QA aprovou com ressalva; `QH-01`, `QH-02` e `QH-03` tratados |

## Escopo entregue

- `scripts/verificar-remocao-de-casos.sh` — ferramenta de desenvolvimento, fora da suite.
- `assert_segredo_ausente` em `tests/support/harness.sh` e cobertura de todas as assercoes nos dois sentidos.
- `lib/auth.sh` — troca de refresh token por access token de curta duracao.
- Modo formulario em `lib/http`, discriminacao de defeito proprio versus falha de rede, e limpeza de canais publicos alheios.

## Decisoes tecnicas

### GUARDA DE REMOCAO — Onde vive, e por que nao na suite

Tres lugares avaliados:

| Lugar | Custo |
|---|---|
| Caso da suite | acopla a suite ao `git`, que passaria pela auditoria de comandos externos e viraria pre-requisito **de execucao do produto** — falso, e dependencia de desenvolvimento. A suite falharia num export sem `.git` por ausencia de ferramenta, indistinguivel de regressao |
| Verificacao no executor | mesmo custo, sem vantagem |
| **Fora da suite** | **escolhido** — sem acoplamento, e permite a referencia correta |

### REFERENCIA — Maximo ao longo da branch, e nao `HEAD` nem so a base

Contra `HEAD`, a guarda so enxerga remocao ainda nao commitada: a remocao acidental de 22 casos teria passado se tivesse sido commitada antes da conferencia. So contra a base tambem nao basta — arquivo criado na propria branch tem zero na base, e casos adicionados e removidos dentro da mesma branch ficam invisiveis. O maximo observado na base ou em qualquer commit da branch fecha os dois vaos com uma regra so, e continua derivado do artefato.

### DECLARACAO DE REMOCAO INTENCIONAL — Trailer de commit

`Remocao-de-casos: <arquivo> <quantidade>`. A declaracao vive no historico, artefato que registra a mudanca e que o revisor le no PR, em vez de num arquivo de excecoes mantido a mao.

### LIMITACAO REGISTRADA, E NAO DISFARCADA

Contagem detecta **remocao**, nao **esvaziamento**. Trocar o corpo de um caso por `:` mantem a contagem e a suite verdes. A guarda reduz o ponto cego; nao o fecha.

### DEFEITO NA PROPRIA GUARDA, ENCONTRADO PELA PROVA DE DISCRIMINACAO

Apagar um arquivo inteiro nao era detectado: o pathspec era um glob do shell, expandido contra a arvore de trabalho antes de `git` ver. O arquivo apagado sumia da lista que deveria acusa-lo — o universo derivava do lado mutavel. E a mesma classe que as auditorias perseguem, cometida dentro da ferramenta feita para detecta-la.

### ASSERCAO QUE VAZAVA AO FALHAR

`assert_nao_contem <segredo> ...` imprime a agulha exatamente quando falha, isto e, exatamente quando ha algo a registrar — e desde que o diario grava diagnostico em disco, isso e deposito de credencial.

`assert_segredo_ausente` mascara por substituicao da agulha **literal**, e nao por redacao: a redacao reconhece FORMAS e por construcao nao alcanca um valor cru sem forma reconhecivel, que e o formato de um segredo fabricado em teste. Ficam posicao, comprimento, quantidade de ocorrencias e o texto com as ocorrencias marcadas — omitir o contexto produziria mensagem inutil, defeito equivalente ao vazamento.

### O PIOR PONTO CEGO DO PROJETO: ASSERCAO QUE PARA DE VERIFICAR

Medido por mutacao: trocar o corpo de `assert_nao_contem` por `return 0` deixava a bateria **inteira** verde. Assercao negativa so e usada para afirmar ausencia, entao neutraliza-la nunca quebra nada — apenas para de verificar. Nao exige remover nada, e por isso a guarda de remocao nao o alcanca.

Cobertura acrescentada nos dois sentidos para todas as assercoes. `assert_igual` exigiu quebrar auto-referencia: verificada com ela mesma, neutralizada aprovava tambem a propria verificacao. A primitiva `_harness_falhar` e verificada sem assercao alguma.

### `lib/auth` — DOIS FATOS DE CONTRATO, UM CONFIRMADO E UM RECUSADO

| Afirmacao | Verificacao | Consequencia |
|---|---|---|
| A Dropbox **nao rotaciona** o refresh token | confirmada em fonte primaria | renovacao concorrente e idempotente: sem trava, sem estado novo, `PRJ-DEC-07` e `RSK-23` preservados sem esforco |
| O cursor de paginacao sobreviveria a renovacao | **nao se sustenta**: a documentacao e silenciosa | o componente **nao promete** continuidade de cursor; quem for dono do laco trata `reset` como caminho previsto, com a politica `reiniciar` ja existente |

A segunda afirmacao foi minha, e a retiro. O criterio que me fez recusar assumir a rotacao vale igualmente aqui.

### SUPERFICIES DO SEGREDO — Eliminadas, e nao protegidas

O corpo da troca nao usa arquivo temporario: os campos vao como `data-urlencode` pela mesma entrada padrao que ja leva o cabecalho. Nao existir a superficie e melhor que proteger a superficie. `client_secret` no corpo evita autenticacao basica, que exigiria `base64` — utilitario externo novo, que teria de entrar no preflight por conveniencia que o protocolo dispensa.

## Defeitos proprios registrados

| Defeito | Como apareceu | Tratamento |
|---|---|---|
| `return "$(_dbx_auth_falhar ...)"` em cinco pontos | subshell descartava o motivo e devolvia cadeia vazia | `{ ...; return $?; }`; e o `C2-01`, ja corrigido em `lib/json` e reintroduzido por mim |
| Laco infinito na contagem de ocorrencias com agulha vazia | mutacao travou a bateria | terminacao estrutural: o laco para se a remocao do prefixo nao encurtar |
| Mutacao atingindo a funcao errada | `assert_nao_contem` tem a mesma linha literal de guarda e vem antes no arquivo | ancora unica; familia de gemeos atrapalhando o proprio instrumento |
| Prova de nao-laco que nao discriminava | com duplo que falha tambem na renovacao, remover a garantia nao muda nada | duplo que responde conforme o destino, com teto de chamadas |

## Ressalvas do QA e tratamento

### `QH-01` — O canal adjacente

`lib/auth` descartava o contexto JSON proprio **exatamente para o segredo nao permanecer**, e nao fazia o equivalente para `DBX_HTTP_CORPO`, canal publico declarado que retinha o access token apos renovar e, contra servico que ecoe a requisicao, o refresh token e o segredo do aplicativo. O cabecalho afirmava que o refresh nunca chega ao diario: verdadeiro para o canal considerado, falso para o vizinho. **Sexta ocorrencia da familia de gemeos, terceira entre arquivos.**

Tratado com `_dbx_auth_limpar_transporte`, limpando **apenas** no caminho de renovacao — no caminho de requisicao comum o corpo e o dado util, e apaga-lo seria zelo transformado em defeito.

#### Auditoria derivada, porque a classe nao tem forma

As auditorias existentes comparam forma sintatica; o `QH-01` e a **ausencia** de uma limpeza sobre um recurso que nenhuma auditoria enumerava. A auditoria nova deriva os dois conjuntos do artefato: o que e segredo vem da tabela de chaves sensiveis de `lib/errors`, a mesma que governa a redacao; os prefixos vem dos arquivos de `lib/`; os canais alheios vem das referencias no texto. Mantido a mao so o conjunto de EXCECOES, cada uma com motivo estrutural.

Refinamento necessario: a exigencia recai sobre quem **preencheu** o canal, e nao sobre quem apenas o le como entrada — sem isso, a regra mandaria `lib/auth` apagar `DBX_CONFIG_REFRESH_TOKEN`, que precisa sobreviver a proxima renovacao.

Na primeira execucao a auditoria encontrou **tres ocorrencias reais alem da que a motivou**, duas delas em `lib/config`, componente aprovado ha varios ciclos: `DBX_JSON_RESULTADO` retinha o refresh token apos carregar a credencial, e `DBX_JSON_ESCAPADO` retinha a cadeia escapada do segredo apos montar o documento. O comentario que justifica descartar a arvore do analisador ja estava escrito no arquivo — e aplicado a um dos dois lugares.

### `QH-02` — Mitigacao afirmada sem existir

O cabecalho prometia caso de contrato contra o `curl` real, habilitado por variavel de ambiente. Nao havia nenhum. Risco declarado como mitigado sem a mitigacao existir e pior que risco declarado em aberto, porque quem le para de procurar.

Medido, o que o duplo nao cobria: ele consome o arquivo de opcoes sem nunca o interpretar.

| Situacao | `curl` real | duplo |
|---|---|---|
| opcoes mal formadas | exit 2 | exit 0, `200` |
| corpo ilegivel | exit 26 | exit 0, `200` |

Cinco casos de contrato acrescentados, exercitando o `curl` real contra `127.0.0.1:1`, que recusa conexao de imediato. **Nao usam rede e por isso rodam sempre**, e nao sob variavel de ambiente: mitigacao que so roda quando alguem lembra de liga-la tende a nao rodar. Dois deles alimentam o cliente real com as opcoes que **nos** geramos, incluindo campo com aspas e barra invertida, o que poe o escape sob teste.

### `QH-03` — Defeito nosso chegando como diagnostico de rede

`2>/dev/null` mais `estado != 0 -> codigo=0` fazia opcao invalida e corpo ilegivel — defeitos do proprio programa — chegarem ao operador como problema de conectividade, mandando investigar rede alheia. Pedir `show-error` e descartar o stderr na linha seguinte era pedir diagnostico para nao le-lo.

Status do cliente emitidos antes de qualquer conversa com o servidor (2, 3, 26, 43) passam a produzir classe `uso_invalido` e politica `nenhuma`. A mensagem do cliente e publicada em `DBX_HTTP_DIAGNOSTICO`, **redigida antes**, porque a opcao de que o cliente reclama pode conter o segredo.

Defeito proprio nesta correcao: a redirecao do stderr aplicada FORA da substituicao de comando nao captura nada, porque a substituicao ja foi expandida com o stderr original. O canal existia e chegava sempre vazio; o caso de teste o apanhou.

#### Por que a classificacao NAO se apoia na presenca do `-w`

Chegou a ser considerado um discriminador mais barato: `curl` so escreveria o `%{http_code}` quando houvesse resposta, entao ausencia de saida denunciaria defeito nosso. **Nao e confiavel — e o motivo so apareceu porque tres partes mediram de forma independente e discordaram.**

URL mal formada nao tem comportamento unico. Medido em `curl 8.18.0`:

| URL | Status | Saida de `-w` |
|---|---|---|
| `http://` (sem host) | 3 | `000` |
| `:::` (esquema invalido) | 3 | `000` |
| `http://[::1` (colchete nao fechado) | 3 | **vazia** |
| `htp://x` (esquema desconhecido) | 1 | `000` |
| URL vazia | 2 | vazia |
| `http://127.0.0.1:1/` (conexao recusada) | 7 | `000` |

A presenca do `-w` varia **dentro de um mesmo codigo de saida**, conforme a forma da URL. Nenhuma das tres medicoes estava errada: cada uma observou uma forma diferente, e o desacordo era o dado.

Consequencia: a classificacao usa o **status do cliente**, que e estavel por familia de causa, e nao a presenca da saida do `-w`. Os casos de contrato registram o `-w` observado como fato medido, mas o componente nao depende dele.

## Evidencias

| Verificacao | Resultado |
|---|---|
| `shellcheck -x` e sem `-x` | exit 0 nos dois modos |
| Bateria integral | 382 aprovados, 0 reprovados, 2 pulados (rede) |
| Guarda de remocao | exit 0 |
| Residuo em disco apos a bateria | zero |

### Discriminacao provada

| Guarda ou auditoria | Prova negativa | Prova positiva |
|---|---|---|
| Remocao de casos | arvore limpa: exit 0 | arquivo apagado, casos removidos de arquivo da base e de arquivo nascido na branch, declaracao menor que a remocao: exit 1 |
| Assercoes do arcabouco | bateria verde | neutralizar qualquer uma das oito assercoes e a primitiva de falha: detectado |
| Canal publico alheio | apos as correcoes: verde | remover a limpeza de `lib/auth`: duas ocorrencias acusadas |
| `lib/auth` | 24 casos verdes | seis mutacoes de seguranca e ciclo de vida: todas detectadas |

## Consequencia adotada: regra de disciplina nasce com o conjunto onde incide

As tres ocorrencias de gemeos deste incremento tem forma comum: **o raciocinio estava escrito no proprio arquivo** e aplicado a um dos dois lugares onde incidia. Nao e falta de saber, e falta de percorrer o conjunto. Leitura e sequencial e ancorada no trecho; enumeracao e transversal e ancorada no conjunto, e a segunda nao emerge da primeira por esforco.

A auditoria de canais publicos nao contem **nenhum conhecimento** que os comentarios ja nao tivessem. Contem a lista completa dos lugares. Auditoria funciona por enumerar, nao por saber mais.

Vale simetricamente para a validacao independente: sonda que pergunta *"o segredo escapa?"* se responde por amostra e passa; a pergunta que encontra a classe e *"todo canal que recebeu segredo foi limpo?"*, que so se responde por varredura. Foi por isso que `lib/config` atravessou varios ciclos com duas ocorrencias vivas.

**Regra adotada para o projeto:** toda regra de disciplina escrita em comentario nasce com a pergunta *"qual e o conjunto de lugares onde isto incide, e quem o enumera?"*. Sem resposta, a regra protege o lugar onde foi escrita e nenhum outro.

## Pendencias

- Continuidade de cursor apos renovacao permanece **nao estabelecida** por fonte. O desenho nao depende dela.
- A guarda nao detecta esvaziamento de caso.
