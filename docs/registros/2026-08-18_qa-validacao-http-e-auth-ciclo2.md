# Parecer de Validacao Independente — QA Expert — `lib/http` e `lib/auth` — Ciclo 2

## Identificacao

| Campo | Valor |
|---|---|
| Projeto | `dropbox_api` — CLI em shell para a Dropbox API v2 |
| Escopo | Correcoes de `QH-01`, `QH-02` e `QH-03`; auditoria de canais publicos e as tres ocorrencias que ela achou |
| Ciclo anterior | [ciclo 1](2026-08-18_qa-validacao-http-e-auth.md) — APROVADO COM RESSALVA |
| Data | 2026-08-18 |
| Gate | `TL-08` |
| Branch | `feature/http`, seis commits |
| **Decisao** | **APROVADO** — sem ressalva |

---

## 1. Decisao

**APROVADO.** Nao encontrei defeito novo. Tudo que ataquei se sustentou, incluindo a fronteira que mais me preocupava — as alteracoes em `lib/config`, componente aprovado ha varios ciclos.

Ha **uma correcao ao registro**, nao ao codigo, e uma retificacao minha.

---

## 2. Regressao em `lib/config` — nao ha

Era o risco principal: limpar `DBX_JSON_ESCAPADO` cedo demais esvaziaria o documento gravado, e limpar `DBX_JSON_RESULTADO` cedo demais esvaziaria os campos lidos. Verifiquei a ordem no codigo — a limpeza da cadeia escapada vem **depois** das quatro concatenacoes, e a do resultado **depois** do laco de campos — e confirmei por ida e volta com valores adversariais:

| Valor | Ida e volta |
|---|---|
| simples · aspas e barra invertida · quebra de linha · **quebra final** | ok |
| **separador interno `0x1f`** · UTF-8 de 4 bytes · vazio | ok |

Nos sete casos, `raiz_remota`, `refresh_token` e `app_secret` voltam identicos.

E os canais adjacentes ficam de fato limpos, sem colateral no canal proprio:

```
DBX_JSON_RESULTADO  []        DBX_JSON_ESCAPADO  []        DBX_JSON_VALORES  []
DBX_CONFIG_REFRESH_TOKEN preservado: sim
```

As duas ocorrencias em `lib/config` eram reais e a correcao nao custou nada do que dependia daqueles valores.

---

## 3. Seletividade do `QH-01` — correta nas tres fronteiras

Era o ponto onde zelo viraria defeito. Ataquei as tres:

| Fronteira | Resultado |
|---|---|
| Apos `dbx_auth_renovar` | `DBX_HTTP_CORPO` **vazio**; access token ausente |
| Apos `dbx_auth_requisitar` | corpo **preservado**; o chamador le o cursor |
| **`requisitar` que renova no meio do caminho** | resposta **pos-renovacao preservada**, e o access token da renovacao **nao** sobrevive nela |

A terceira e a que importa: e onde uma limpeza mal posicionada apagaria a resposta que o chamador pediu, ou deixaria o token da renovacao no corpo final. Nenhuma das duas acontece.

---

## 4. `QH-03` — classificacao verificada ponta a ponta

Com cliente simulado devolvendo cada status:

| `curl` exit | status | classe | `DBX_HTTP_DEFEITO_CLIENTE` | diagnostico |
|---|---|---|---|---|
| **7** (conexao recusada) | 9 | **`rede`** | vazio | presente |
| **2** (opcao invalida) | 2 | **`uso_invalido`** | `2` | presente |
| **3** (URL malformada) | 2 | `uso_invalido` | `3` | presente |
| **26** (corpo ilegivel) | 2 | `uso_invalido` | `26` | presente |
| **43** | 2 | `uso_invalido` | `43` | presente |

Defeito nosso deixou de ser diagnosticado como problema de rede, e o `stderr` do cliente — que antes era descartado — chega ao canal de diagnostico. Confirma tambem a correcao do segundo defeito autodeclarado: a redirecao passou para dentro da substituicao de comando.

---

## 5. Uma correcao ao registro, e uma retificacao minha

### A tabela tem uma celula errada

Medi os quatro contra `curl` real:

| Situacao | exit | `-w` |
|---|---|---|
| conexao recusada | 7 | `000` |
| **URL malformada** | **3** | **vazio** |
| corpo ilegivel | 26 | vazio |
| opcoes malformadas | 2 | vazio |

O registro afirma `000` para URL malformada; **ela nao imprime nada**. Sem efeito sobre o comportamento, porque a classificacao e por status e `3` esta na lista de defeito de qualquer modo. Vale corrigir porque a tabela sera lida como referencia.

### O meu discriminador estava invertido, e reconheco

Escrevi que *"`curl` so imprime o `-w` quando houve resposta; codigo vazio com estado nao zero e transporte"*. A polaridade esta **ao contrario**: vazio e **defeito nosso**, e `000` e transporte. A correcao esta certa e foi obtida do jeito certo — medindo, e nao assumindo.

Registro, para o acervo e nao para reabrir a decisao, que o **discriminador** (vazio versus nao vazio) separa corretamente os quatro casos, apenas com a polaridade invertida em relacao ao que escrevi. Classificar por status, como foi feito, e escolha defensavel e mais explicita: nao depende de uma propriedade do cliente que a tabela acima mostra ser facil de descrever errado. Fica como esta.

---

## 6. O refinamento da regra de canais — **correto e necessario**

A regra que propus dizia: para cada canal publico que recebe valor derivado de credencial, exigir limpeza no componente que o preencheu. O refinamento aplicado — a obrigacao recai sobre quem **preencheu**, nao sobre quem le como entrada — e correto, e sem ele a regra se autodestruiria: mandaria `lib/auth` apagar `DBX_CONFIG_REFRESH_TOKEN`, que precisa sobreviver a proxima renovacao. Verifiquei que sobrevive.

Procurei buraco e nao achei. O caso que abriria um seria um componente ler canal alheio, copiar o segredo para canal proprio e escapar da obrigacao — mas ai a regra alcanca a copia, porque quem preencheu o canal proprio foi ele. Se a copia ficar em variavel `local`, morre com o quadro. O refinamento estreita a regra exatamente onde ela era larga demais, sem abrir superficie.

---

## 7. Sobre a observacao do autor — **concordo, e ela me inclui**

> *"Nao e falta de saber, e falta de enumerar os lugares onde o que se sabe se aplica."*

Concordo, e a evidencia desta rodada e mais forte do que a formulacao sugere. Em `lib/config`, **o comentario que justifica descartar a arvore do analisador ja estava escrito no arquivo**, e o escalar vizinho nao recebeu o mesmo tratamento. O conhecimento nao estava ausente nem remoto: estava na mesma tela, a poucas linhas.

Isso muda o significado da familia de gemeos, e sustento a mudanca:

- **Nao e lapso de atencao.** Atencao maior nao resolve, porque o que falta nao e perceber a regra — e percorrer o conjunto de lugares onde ela incide.
- **E limite estrutural da revisao por leitura.** Leitura e sequencial e ancorada no trecho; enumeracao e transversal e ancorada no conjunto. Sao operacoes diferentes, e a segunda nao emerge da primeira por esforco.
- **As auditorias funcionam por enumerar, nao por saber mais.** A auditoria de canais nao contem nenhum conhecimento que os comentarios ja nao tivessem. Ela contem a **lista completa dos lugares**.

Registro que isso **me inclui diretamente**: aprovei `lib/config` ao longo de varios ciclos e nao encontrei as duas ocorrencias. Minhas sondas eram orientadas a segredo — *o segredo escapa?* — e nao a enumeracao — *todo canal que recebeu segredo foi limpo?*. A primeira pergunta se responde por amostra e passa; a segunda so se responde por varredura. Mesmo limite, do lado de quem valida.

Consequencia pratica que sugiro registrar: **toda regra de disciplina que o projeto escrever em comentario deveria nascer com a pergunta "qual e o conjunto de lugares onde isto incide, e quem o enumera?"**. Sem resposta a essa pergunta, a regra protege o lugar onde foi escrita e nenhum outro.

---

## 8. Linha de base

| Item | Resultado |
|---|---|
| `shellcheck -x` | exit **0** |
| Suite | **382 / 0 / 2** |
| `bash -n` | limpo |
| Arvore | nenhum arquivo alterado por esta validacao |

`QH-02` fechado: os casos de contrato contra o cliente real usam `127.0.0.1:1`, que recusa conexao de imediato e portanto **nao depende de rede** — rodam sempre, e nao apenas no modo de rede. A escolha e melhor do que a que eu havia recomendado, que teria deixado a mitigacao fora da execucao padrao.

---

## 9. Divida de processo

Os quatro registros pendentes foram consolidados em dois, **escritos pelo proprio autor**. Endosso a recusa de delegar: ha precedente no projeto de registro delegado ter fabricado um fato, e um registro que descreve defeitos proprios, limitacao de esvaziamento e uma retratacao de contrato e exatamente o tipo de texto em que a fabricacao passa despercebida. A divida esta paga.

---

## 10. Fechamento

**Pronto para o fechamento do Tech Lead.** Nada bloqueia.

A registrar:

1. `QH-01`, `QH-02` e `QH-03` fechados e verificados de forma independente.
2. Tres ocorrencias adicionais achadas pela auditoria derivada, duas em componente ja aprovado — **sem regressao** apos as limpezas.
3. Seletividade do `QH-01` correta nas tres fronteiras, incluindo renovacao no meio da requisicao.
4. Refinamento da regra de canais: correto, necessario e sem buraco identificavel.
5. Correcao da tabela de status: URL malformada nao imprime `000`.
6. Retificacao do QA: o discriminador proposto no ciclo 1 estava invertido.
7. Reformulacao da familia de gemeos como **limite estrutural da revisao por leitura**, com a pergunta de enumeracao proposta na secao 7.

---

## 11. Desvios de protocolo

| Desvio | Justificativa |
|---|---|
| Cypress (item 13) | Nao aplicavel: nao ha interface web ou grafica |
| `qa-validacao-frontend-template.md` (itens 17 e 19) | Nao aplicavel: nao ha Design System nem handoff do UX Expert |
| `prompt-logger` (item 2) | Nao acionado, por instrucao do coordenador |

Nenhum arquivo de codigo, teste ou requisito foi alterado; sondas ocorreram em copias descartaveis fora do repositorio. Sem commit, sem push, nada instalado.
