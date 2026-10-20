# System Design — Aplicacao Shell de Integracao com Dropbox

> Elaborado a partir de `.claude/agents-protocol/templates/system-design-template.md`.

## Identificacao

- Projeto ou produto: `dropbox_api` — aplicacao de linha de comando em shell script para integracao com a Dropbox API v2
- Responsavel Business Analyst: Business Analyst (pacote de agents)
- Responsavel tecnico principal: a definir pelo Tech Lead
- Data da versao: 2026-10-19 (**v1.12**)
- Status: 🔴 **`lib/stream` era componente planejado e NAO se materializou** (`DIV-20`); `RF-31` roda em `lib/transfer` + `lib/hash`. **Tamanho de parte FIXO em 4.194.304 bytes** (`DIV-19`, `DP-30`). **Limite de plataforma registrado em `RSK-36` / `DIV-18`.** **Todas as decisoes do `sync` fechadas.** Quinze comandos na fase 3 (`DIV-68`: o "nove" era anterior as fases 1 e 3); `RSK-24` com mitigacao estrutural em vez de aceite. Nenhuma decisao do solicitante em aberto para o `sync`

Documentos relacionados: [Escopo e requisitos](../requisitos/escopo-requisitos-e-criterios-de-aceite.md) · [Decisoes pendentes](../requisitos/decisoes-pendentes.md) · [Funcionalidades candidatas](../requisitos/funcionalidades-candidatas.md) · [Riscos e licenciamento](../requisitos/riscos-restricoes-e-licenciamento.md)

### Registro de versao

| Versao | Mudanca |
|---|---|
| v0.1 | Proposta arquitetural inicial |
| **v1.12** | **Filtros e limite de banda (fase 4, 2026-10-19; `F-13`, `F-17`; `RF-79` a `RF-83`; porte M; em andamento).** Componente novo **`lib/filtro`** (decidido, `DIV-94`), puro, consumido por `lib/walk` e `lib/sync`; limite de banda como opcao `limit-rate` de `lib/http` so no modo de conteudo; secao "Filtros e limite de banda", com diagrama da avaliacao de escopo. Sem estado persistente novo e sem codigo de saida novo. |
| **v1.11** | **Revisoes, restauracao e lixeira (fase 3, 2026-10-19; `F-07`, `F-20`; `RF-72` a `RF-78`; porte G; em andamento).** Comandos `commands/revisoes.sh`, `commands/restaurar.sh` e `commands/lixeira.sh` (secao "Revisoes, restauracao e lixeira"), com diagramas da restauracao (arquivo e pasta recursiva) e da exclusao permanente; integracoes `list_revisions`, `restore`, `list_folder`/`get_metadata` com `include_deleted` e `permanently_delete`, confirmadas contra `files.stone` (ramo `main`); escopo opcional `files.permanent_delete`. Nenhum componente novo em `lib/`, nenhum estado persistente, nenhum codigo de saida novo. Status corrigido (`DIV-68`). `DIV-54` a `DIV-69` decididas pelo Tech Lead (exclusao permanente sem terminal so com `--confirmar-caminho` identico ao alvo; unica opcao de confirmacao; nenhum dos tres comandos trava). `DIV-70` a `DIV-77` (parecer do Senior Developer): escopo opcional dentro da linha `escopos`; `lixeira -R` so em pastas vivas; `restaurar` sobre pasta viva sai `2`; confirmacao literal ou normalizada, caixa exata; item de pasta fora da raiz ou sem revisao e falha (`14`), `--dry-run` sai `0`; `in_progress` vira `14` apos retentativas; aviso de pasta conta um nivel. Ciclo de QA: guarda do expurgo pelo `path_lower` do proprio alvo (dobra so ASCII sob `LC_ALL=C`) e sem chave repetida, senao `10` (`QA-B3-02`, `QA-B3-05`); `in_progress` vira `14` em `_dbx_cmd_escrita_remota` (`delete`, `restore`, expurgo) e o `upload` mantem `10` (`QA-B3-03`); `lib/json` recusa `\u0000`, substituto isolado e escape incompleto (`QA-B3-04`); descida so por descendente estrito com pastas visitadas (`QA-B3-06`); item fora da pasta pedida e falha (`DIV-78`). Riscos baixos aceitos: corte do corpo HTTP no primeiro NUL cru; fila quadratica da descida (fase 9). Versao anterior preservada nesta tabela (a regra de `historico/` do `AGENTS.md` vale para memoria, nao para este documento). |
| **v1.10** | **Fase 2 implementada (2026-10-19).** `lib/tmp` descrito como existe: um tratador por sinal (`EXIT`, `INT`, `TERM`, `HUP`) armado uma vez por processo; lista de acoes e lista de areas, por processo (subshell nao limpa as do pai); acoes em ordem inversa e depois areas; criacao e registro com sinais retidos; sinal durante a limpeza nao a interrompe; saida `14` em sinal; removida a descricao de gancho/canal de sinal por modulo. Trava em `lib/state` na ordem trava, leitura, `mv`, liberacao. `DIV-47` (conta da chave = resumo local da credencial; `RSK-50`), `DIV-48` (estado alheio ou sem escrita segue sem trava, com aviso) e `DIV-49` (`download` de pasta trava). Diagrama de sequencia ajustado: o tratador e armado pela aquisicao. |
| **v1.9** | **Trava de concorrencia e `lib/tmp` (fase 2, 2026-10-19; `F-12`, restante de `F-31`; `RF-69` a `RF-71`, `RNF-35`, `RNF-36`; em andamento).** `lib/tmp` entra como registro unico de areas e de acoes de limpeza (a linha anterior o dava como existente: `DIV-42`); a trava por (conta x origem x destino) entra no ciclo do `sync` e do `verificar` (secao "Trava de concorrencia e area temporaria unica"), com diagrama de aquisicao e liberacao; `RNF-26` autoriza o arquivo de trava como estado transitorio que nao decide. Classe de erro da trava ocupada: `conflito`/`7`, **confirmada** (`DIV-43`); sem codigo novo. `DIV-38` a `DIV-44` **resolvidas pelo Tech Lead**: chave sem ordem entre sentidos, trava como unica escrita permitida no `verificar` e na simulacao (diretorio de estado byte a byte igual), `lib/state` cria e remove a trava, `RNF-29(d)` emendado, nomes `dbx-sync.*` mantidos, `unlink` recusa com `7` diante de trava viva. |
| **v1.8** | **Fase 1b (2026-10-19; `F-36`, `F-37`).** `lib/path` aplica a `raiz_remota` a todo comando com caminho remoto (`RNF-20(b1..b6)`: componente, sem caixa, `..` normalizado, `caminho_recusado`/`13` antes da API) e recusa caminho remoto com controle (`RNF-10(b)`); raiz local configuravel (`RNF-20(c)`) fica fora, em `F-38`. |
| **v1.7** | **Consulta, diagnostico, espaco e autocompletar (fase 1, 2026-10-19; `RF-65` a `RF-68`; em andamento).** Tres comandos novos na tabela de comandos (`verificar`, `diagnostico`, `completar`), a checagem previa de espaco em `upload` e `sync --enviar`, `completions/dbx.bash` e a nota do preflight contornado pelo `diagnostico` (secao "Comandos de consulta, diagnostico e autocompletar"). Nenhum componente de `lib/` entra; sem estado persistente novo (`RNF-26` intacto); sem classe de erro nova. |
| **v1.6** | **Aliases em ingles, localidade da comparacao e guarda de origem vazia pelo plano (fase 4, 2026-10-19, `DP-35`).** Nenhum componente entra ou sai. `commands/sync`, `commands/unlink` e `commands/config` aceitam os aliases em ingles de `RF-64` (nomes em portugues mantidos); `C.UTF-8` e fixada so dentro da comparacao sem caixa de `lib/sync`, nunca no processo, quando a localidade existe, e o `sync` avisa, sem recusar, quando ela falta (`RF-54(e)(f)(g)`, `F-32`); a guarda de origem vazia do `sync --receber` sai do caminho anterior ao plano (`RF-41(b)`, `O-1`). Novos: secao "Aliases e localidade (fase 4)". Contradicoes remanescentes entre documentacao e codigo listadas em `RNF-34`. `DIV-30` a `DIV-32` resolvidas pelo Tech Lead no mesmo dia |
| **v1.5** | **Cache unico e segredo obrigatorio (fase 3, 2026-10-18, `DP-34`).** 🔴 **`lib/db` REMOVIDO** da arquitetura (SQLite via `sqlite3`/`python3`; nunca havia constado deste documento, `DIV-25`): `lib/state` passa a ser o **unico** cache de `content_hash`, com **dois namespaces** — `memoria-*` do `sync` e `upload-*` do `upload` (`RF-61`), chave pelo caminho fisico canonico (`RF-62`). O `upload` so dispensa o envio com `content_hash` **remoto** igual ao local (`RF-60`); o cache so poupa o calculo local. `sqlite3`/`python3` saem (`RNF-02`); o `dbx.db*` legado fica inerte e documentado (`RNF-33`). **PKCE deixa de constar como disponivel**: `client_secret` obrigatorio tambem na biblioteca (`RF-63`; PKCE em `F-35`). **Handoff do DBA consolidado** na secao "Plano de dimensionamento e expansao do banco" (regra 26). Novos: secao "Estado local unico (fase 3)", decisoes de arquitetura, riscos `RSK-42` a `RSK-45` e diagramas "Estado local: componentes" e "Ciclo de leitura e escrita do cache". **Mesma data, decisoes do Tech Lead:** `DIV-26` a `DIV-29` resolvidas (identidade forte tambem na memoria do `sync`; sem skip com `--rev`; falha segura sem conta documentada, REVISTA para desabilitar a propagacao de exclusao sem identidade de conta (`RF-41(e)`, `--confirmar` nao reabilita); diretorio de estado corrigido para `0700` ou recusa como `permissao`). Linha "Natureza do dado" do plano do banco atualizada para o formato v2 da `memoria-*` e do `upload-*`. Achado `QA-P3-01`: memoria existente descartada na carga desabilita a exclusao na execucao (`RF-41(f)`, `RSK-46`). **Decisao do solicitante apos `QA-P3-05..07`:** no `--espelhar`, origem vazia com algo a apagar e sempre recusada (codigo `14`), independente da memoria, nos dois sentidos; so a opcao nova `--permitir-origem-vazia` dispensa (`RF-41(b)` reescrito, `RF-53(e)`); `RF-41(e)` e `(f)` ficam como defesa em profundidade |
| **v1.4** | **Robustez de rede (fase P2, 2026-10-18).** Registrado o comportamento decidido para `lib/http` (timeouts, recuo, `Retry-After`), `lib/transfer` (retomada na mesma execucao) e `commands/sync` (falhas por item), na secao "Robustez de rede (P2)". Sem novo componente; sem estado persistente novo (`RNF-26` intacto). `DIV-22` encerrada |
| **v1.3** | **Integridade de dados (fase P1, 2026-10-18).** Registrado o comportamento decidido para `lib/sync`, `commands/download`, `lib/transfer` e `lib/http` (secao "Integridade de dados no recebimento e no `sync`"). Sem novo componente; backlog das fases P2 a P5 em `F-23`..`F-27` |
| **v1.2** | **Correcoes devolvidas pela implementacao de `RF-31`/`RF-08`/`RF-09` (2026-08-19).** 🔴 **`lib/stream` reclassificado como PLANEJADO E NAO MATERIALIZADO** (`DIV-20`): verificado por leitura direta de `lib/`, o arquivo nunca foi criado; `RF-31` ficou em `lib/transfer` + `lib/hash` (API incremental), e `RF-32` segue nao implementado, com o componente **em aberto**. A linha da tabela e o no do diagrama sao **riscados, nao removidos**. **Dimensionamento corrigido:** a celula de estrategia por tamanho de arquivo afirmava tamanho de parte **configuravel** com faixa sugerida de 8 a 32 MiB — **falso em relacao ao implementado e nunca medido**; a parte esta **fixa em 4.194.304 bytes** (`DIV-19`), e o estagio "ajuste fino" do plano de expansao passa a constar como **indisponivel**. **Contrato de conteudo revalidado** contra `files.stone` do ramo **`main`**, incluindo `offset` e `incorrect_offset` como base documentada da retentativa por parte, e a **validade de 7 dias da sessao** (`RES-18`); ⚠️ `DIV-21` registra que o ramo `master` esta **desatualizado** (48 horas, sem `session_type`). **Criterio de aceite de transferencia por fluxo qualificado** por `DIV-18`/`RSK-36`. *(A numeracao salta de v1.1 para v1.2 sem v1.1.x intermediaria; nao ha versao omitida neste registro.)* |
| v0.2 | Incorpora DP-01 (reimplementacao independente), DP-03 (uso interativo **e** automatizado, exigindo camada de saida com duas apresentacoes) e DP-04 (conta pessoal com acesso amplo, exigindo menor privilegio e confinamento de raiz). Contratos de integracao **revalidados via Context7** sobre `/websites/dropbox_developers_http`, corrigindo hosts, unidades, o requisito de multiplo de 4 MiB, a paginacao de busca e a restricao de concorrencia em listagem. Nota de nao verificacao do Context7 removida por erro factual |

| **v0.3** | **Escopo do MVP fechado (DP-02).** Componentes `lib/stream` e `lib/report` criados para F-01 e F-05; `lib/hash` **desbloqueado** pela confirmacao do algoritmo do `content_hash`; `lib/transfer` estendido para omissao por conteudo identico (F-02). Registro explicito de que **nenhum componente de estado local persistente entra nesta versao**, mantendo `DP-09` fechada e o handoff do DBA nao acionado. `RSK-20` encerrado, `RSK-21` rebaixado, `RSK-23` criado |

| **v0.4** | **Correcoes devolvidas pelo ciclo de QA da camada de dominio (aprovado com ressalva).** Camada de **Orquestracao** criada, corrigindo tres inconsistencias da tabela de camadas (DIV-A): `lib/errors` deixa de depender de `lib/json`, `lib/transfer` sai do dominio, `lib/hash` entra nele. `RNF-20` ampliado para nomear **os dois espacos de nomes**, remoto e local, com TOCTOU registrado como risco residual aceito (`RSK-24`) e raiz `/` exigindo opt-in explicito. `RNF-07` ajustado para a dimensao de idempotencia. Requisito de entrada de `lib/output` acrescentado (redacao de cabecalho sensivel consome a linha). Dados reais de dimensionamento incorporados. `DP-07` **permanece aberta**; a premissa que a dava por fechada foi refutada (DIV-B) |

| **v1.1** | **`DP-27` muda a semantica do `sync`: DIRECIONAL, com a origem como autoridade.** `--origem` e `--destino` obrigatorios, um lado local e outro remoto. A matriz de tres estados e as quatro classes de conflito **perdem objeto**, e com elas `DP-21`, `DP-22`, `RF-39a` e `RF-40a`. A linha de base sobrevive por `DP-27b`, **rebaixada a memoria de desempenho que nao arbitra nada** — o que inverte o tratamento de corrupcao (`RF-42`) de recusar para descartar e reconstruir. **Consequencia registrada em `RSK-35`:** a base tambem era limitador de exclusao, e essa funcao caiu sem substituto — `RF-40`, `RF-41`, `RF-47` e `RF-48` passam de camada redundante a defesa unica. `DP-28` fica aberta |
| **v1.0** | **`DP-26` e `DP-25` resolvidas.** `RSK-24` **deixa de ser risco aceito**: adotada **travessia por descida com nome relativo** (`RNF-28`), equivalente em shell de `openat`/`O_NOFOLLOW` por componente, verificada experimentalmente. **Correcao conceitual:** `RF-41(a)` **nao** compensa `RSK-24` — dispara em **erro** de travessia, e TOCTOU bem-sucedido nao gera erro; eixos ortogonais, arvore **incompleta** contra arvore **completa e errada**. Risco composto `RSK-34` registrado e `RF-50` fixa que a base **so grava o que a descida verificou**. `DP-25` inclui `config`, `unlink` e `space` — **nove comandos**; `RF-51` trata o estado local no `unlink` e `RF-52` vincula a base a **identidade da conta**, fechando um caminho de destruicao de dado por relink a conta diferente |
| **v0.9** | **Politica de conflito decidida: `DP-21` ultimo a escrever vence · `DP-22` honrar a exclusao · `DP-24` sem teto · `DP-23` base sob `$XDG_STATE_HOME`, corrompida recusa.** Decisoes tomadas contra a recomendacao do Business Analyst, com custo apresentado e aceito; recomendacao e razao registradas para revisao futura. **Desenho ajustado para minimizar o custo dentro da decisao:** incerteza **confinada a ordenacao** (`RF-39` proibe carimbo de tempo na deteccao); qualidade do sinal elevada (`RF-39a`, `RNF-27` — diferencas contra a base cancelam offset de relogio, `client_modified` substitui `server_modified`); desempate prefere o **lado recuperavel** (`RF-40a`); perda **nominal e visivel depois da acao** (`RF-47`); reconhecimento obrigatorio na primeira execucao (`RF-48`); concorrencia otimista por `rev` (`RF-49`). **`RF-41(a)` elevada a bloqueante** — unica protecao restante contra exclusao em massa. `RSK-33` criado (assimetria de recuperabilidade) |
| **v0.8** | **`DP-06` resolvida com `sync` bidirecional — maior mudanca de escopo do projeto.** `PRJ-DEC-07` **revogado no escopo do `sync`**; `DP-09` reaberta; **handoff do DBA acionado**. Componentes novos: **`lib/state`** (linha de base e cursor, unico autorizado a escrever estado alem de `lib/config`) e **`lib/sync`** (matriz de tres estados, conflitos, salvaguardas). Requisitos `RF-37` a `RF-46`, `RNF-25` e `RNF-26`. Riscos criticos novos: `RSK-29` a `RSK-32`; **`RSK-24` reescalado** de Medio/Baixa para Alto/Media, porque o percurso recursivo que seu aceite pressupunha inexistente agora existe e apaga. Cinco decisoes bloqueantes: `DP-21` a `DP-24` e `DP-26` |
| **v0.7** | **`RNF-24` criado (`E3-01`)**: contexto nomeado em `lib/json`, permitindo analisar corpo de erro sem destruir analise em curso — com o nome **sempre de origem interna**, restricao que preserva a injetividade que fechou `E2-01`. **Vocabulario do projeto ampliado**: secao "separar dado de canal" na visao geral, e classe *"instrumento de observacao interfere na propriedade observada"* registrada como `RSK-28`. `RSK-27` criado a partir de auditoria estatica furada. Ciclo 2 de QA aprovado com ressalva — 223 casos, `shellcheck -x` exit 0 |
| **v0.6** | **`DP-05` fecha o desenho de `lib/config`** — um arquivo, um caminho, sem multiplexacao; `RF-05` sai para o backlog como incremento aditivo. **`RNF-23` acopla `lib/http` a `lib/json`:** o teto de entrada de 256 KiB do analisador, fixado por medicao, torna obrigatorio o `limit`/`max_results` explicito em toda chamada de colecao. **`RSK-24` encerrado** com aceite reconfirmado sob `DP-07` ja resolvida |
| **v0.5** | **Correcao de registro e tres decisoes novas.** `DP-07` (Linux, `bash` 4.4) e `DP-08` (apenas `cURL`, JSON proprio) **ja estavam decididas** e foram enfim propagadas: `lib/preflight` e `lib/json` destravados, e a **camada de compatibilidade GNU/BSD eliminada do desenho**. `DP-11` fixa credencial `0600` sob XDG sem sobrescrita por ambiente, destravando `lib/config`. `DIV-16b` adota `--null` com terminador nulo, destravando `lib/output`. `RSK-24` **reaberto**: com Linux confirmado, `/proc/self/fd` deixa de ser inadmissivel por portabilidade. `DIV-15` retirada e `RSK-25` encerrado |

> **Condicao de validade.** Nao ha decisao bloqueante pendente. As pendencias remanescentes sao estruturantes (DP-07, DP-08, DP-11, DP-20) e afetam componentes especificos, nao a arquitetura geral — ver a secao "O que o Senior Developer precisa para comecar" em [decisoes-pendentes.md](../requisitos/decisoes-pendentes.md). As secoes de dimensionamento contem premissas provisorias explicitamente marcadas, a substituir pelos numeros reais quando DP-12 for respondida.

### 🔄 v0.8 — o invariante de ausencia de estado foi REVOGADO para o `sync`

> **Mudanca de escopo autorizada por `DP-06`.** O solicitante escolheu `sync` **bidirecional**, com **propagacao de exclusao sob opcao explicita** e **cursor persistente**. Isso promove `F-06` do Bloco 2 e **revoga `PRJ-DEC-07` no escopo do `sync`**.
>
> **O bloco abaixo e preservado, nao apagado.** Ele registra uma decisao que era correta para o escopo vigente a epoca, e a razao continua rastreavel. O que mudou foi o escopo, nao a qualidade da decisao.
>
> **Situacao atual:**
>
> | Escopo | Estado persistente |
> |---|---|
> | `download`, `list`, `delete`, `info` | ❌ **Nenhum.** O invariante original continua valendo integralmente |
> | `upload` *(v1.5)* | ✅ **So a memoria auxiliar do hash local** (`upload-*`, `RF-61`), que **nao decide**: a dispensa do envio exige `content_hash` remoto igual (`RF-60`). Apagar o cache nao muda decisao alguma (`RNF-26`) |
> | `sync` | ✅ **Autorizado e delimitado** por `RNF-26`: linha de base de sincronizacao e cursor de enumeracao, vinculados ao par de raizes. Nada alem disso |
>
> **Consequencias formais:** `DP-09` **reaberta** · **handoff do DBA acionado** · `RSK-23` reescrito de "nao criar estado" para "nao exceder o estado autorizado" · `RSK-24` reescalado, porque o percurso recursivo que seu aceite pressupunha inexistente agora existe e apaga.
>
> **⚠️ ATUALIZADO POR `DP-27` (v1.1).** O paragrafo abaixo era a justificativa de correcao para o estado persistente, e ela **caiu junto com a bidirecionalidade**. O `sync` direcional decide lendo origem e destino agora, **sem terceiro estado**. A linha de base permanece por escolha do solicitante (`DP-27b`), como memoria de desempenho: perdida ou corrompida, o `sync` decide igual e so trabalha mais. O texto original fica registrado porque o raciocinio continua valido para o escopo que o motivou.
>
> ~~**Por que o estado e requisito derivado, e nao otimizacao:** sincronizacao bidirecional com propagacao de exclusao exige linha de base **por construcao**. Com apenas dois estados observaveis, "o usuario apagou este arquivo" e "este arquivo nunca foi baixado" sao indistinguiveis, e as acoes corretas sao opostas. O cursor **nao torna o `sync` mais rapido — torna-o correto**. Detalhamento na secao 5.8.1 dos requisitos.~~

---

### ⚠️ Invariante da v0.3 — preservado como registro historico, valido fora do `sync`

> **O MVP nao possui estado local persistente.** A unica escrita persistente da aplicacao e o arquivo de configuracao com a credencial. Nao ha cursor, catalogo de arquivos, cache de resumos, indice nem arquivo de trava.
>
> Isso e consequencia direta da decisao de escopo: as quatro funcionalidades que exigiriam persistencia — F-03 (retomada), F-06 (espelhamento), F-12 (trava de concorrencia) e F-14 (deteccao por cursor) — ficaram todas fora do MVP.
>
> **Consequencias formais:** `DP-09` permanece fechada · o handoff do DBA **nao** e acionado · a secao "Plano de dimensionamento e expansao do banco" e nao aplicavel por ausencia de mecanismo, e nao por omissao.
>
> Introduzir qualquer forma de estado persistente constitui **mudanca de escopo** e exige nova decisao do solicitante. Risco associado: `RSK-23`.

---

## Objetivo do documento

- **Problema de negocio enderecado:** executar operacoes de transferencia e gestao de arquivos no Dropbox a partir de ambientes headless, containers e jobs agendados, onde o denominador comum disponivel e um shell e o `cURL`, sem exigir cliente grafico de sincronizacao nem runtime de aplicacao.
- **Escopo contemplado:** aplicacao CLI em shell script; autenticacao OAuth2 com refresh token; operacoes de arquivos e pastas; consulta de conta e espaco; tratamento de erro e retentativa; codigos de saida deterministicos; documentacao de uso e implantacao. **Funcionalidades novas aprovadas no MVP:** transferencia por fluxo `stdin`/`stdout` (RF-31, RF-32); omissao de transferencia por conteudo identico via `content_hash` (RF-33, RF-34); contrato de automacao com saida estruturada versionada, codigos de saida semanticos e simulacao (RF-15, RF-28, RF-29, RF-35); relatorio de execucao (RF-36); e o Bloco 0 de base endurecida.
- **Escopo fora:** interface grafica, web ou TUI; sincronizacao **bidirecional** com resolucao de conflito — o `sync` e direcional por `DP-27`; processo residente; servidor de callback OAuth local; outros provedores de armazenamento; criptografia de conteudo do lado do cliente; **Dropbox Business e Team em qualquer forma** — administracao de equipe, impersonacao de membro, espaco de equipe e manipulacao de namespace por `Dropbox-API-Path-Root`, agora definitivo por DP-04.
- **Premissas:** PRE-01 a PRE-07 do documento de requisitos. Destaque: existe aplicativo registrado no Dropbox App Console; `cURL` com TLS disponivel; sem banco de dados; sem interface grafica.
- **Restricoes:** RES-01 a RES-14 do documento de requisitos. Destaque: implementacao obrigatoria em shell; **proibicao de derivar codigo do modelo de referencia** (RES-02, decorrente de DP-01); limite de 150 MiB por requisicao de envio; endpoints ausentes da documentacao vigente proibidos; multiplo de 4.194.304 bytes obrigatorio apenas em sessao concorrente; proibicao de chamadas simultaneas de listagem para o mesmo usuario; acesso amplo (`Full Dropbox`) concedido ao aplicativo; ausencia de interpretador JSON nativo no shell.

---

## Visao geral da solucao

### Resumo executivo da arquitetura

Aplicacao monoprocesso, sem estado residente, invocada por comando e encerrada ao final de cada operacao. Um binario de entrada (`bin/dbx`) interpreta argumentos, seleciona um caso de uso em `commands/` e delega o acesso externo a uma camada de adaptadores em `lib/`. Toda a comunicacao com a Dropbox passa por um unico ponto (`lib/http`), o que concentra autenticacao, retentativa, mapeamento de erro e observabilidade em um lugar auditavel.

A decisao arquitetural central e a **decomposicao modular**, em contraste direto com o modelo de referencia, que concentra cerca de 35 funcoes em um unico arquivo de 1834 linhas. A separacao permite teste por unidade, substituicao do cliente HTTP por duplo de teste e verificacao independente de seguranca no ponto onde os segredos circulam.

### Estrutura recorrente do projeto: separar dado de canal

Registro incorporado ao vocabulario do projeto na v0.7, a partir de classe nomeada pelo QA. A maior parte dos defeitos graves deste projeto pertence a **uma unica familia**: dado transitando em banda com o canal que o transporta.

| Manifestacao | Dado | Canal | Tratamento |
|---|---|---|---|
| Segredo destruindo o identificador de correlacao | Diagnostico | Linha de texto | `RNF-22` — nao concatenar diagnostico a cabecalho sensivel |
| Nome com quebra de linha em saida orientada a linha | Nome de arquivo | Registro por linha | `DIV-16b` — terminador `\0` opcional |
| Colisao de chave composta | Identificador | Chave composta | `E2-01` — composicao injetiva |
| Nome de contexto de origem externa | Identificador | Espaco de nomes | **`RNF-24`** — nome sempre interno, `[a-z_]+` |
| `$( )` consumindo bytes de controle | Conteudo | Substituicao de comando | Eliminacao de `$( )` no componente de caminho |

**Corolario adotado como criterio de projeto:** a mesma familia aparece do lado de quem **observa**, e nao so de quem transporta — e a classe *"instrumento de observacao interfere na propriedade observada"* (`RSK-28`), com quatro instancias documentadas. Ao introduzir instrumento de verificacao, medicao ou transporte, perguntar o que ele **altera** no objeto observado; preferir **canal proprio a canal compartilhado**; e desconfiar de silencio, porque nas instancias mais custosas o instrumento nao errou o valor — **deixou de reportar**.

---

A v0.3 acrescenta a **ausencia deliberada de persistencia** como terceira caracteristica estrutural: a aplicacao nao guarda nada entre execucoes alem da credencial. Isso simplifica o desenho de forma relevante — nao ha consistencia de estado a recuperar apos interrupcao, nao ha migracao de formato de estado, nao ha crescimento a dimensionar — e e o que permite manter a secao de banco de dados formalmente nao aplicavel.

Duas decisoes da v0.2 alteram o desenho:

1. **Camada de saida com duas apresentacoes (DP-03).** Com uso confirmado tanto interativo quanto automatizado, `lib/output` deixa de ser um formatador e passa a manter **um modelo de resultado unico com duas renderizacoes**: legivel por humano e estruturada por maquina. A selecao ocorre por deteccao de terminal associado, sobreponivel por sinalizador explicito em ambos os sentidos. Consequencia de projeto: **nenhum comando pode emitir texto diretamente**; todos devolvem um resultado estruturado que a camada de saida renderiza. Sem essa disciplina, a segunda apresentacao nunca fica consistente.
2. **Menor privilegio sobre acesso amplo (DP-04).** O aplicativo opera com acesso a Dropbox inteira, o que remove qualquer confinamento imposto pela plataforma. O confinamento passa a ser responsabilidade da aplicacao: escopos OAuth minimos e uma raiz remota configuravel, validada em `lib/path` **antes** de qualquer chamada de rede.

Aplicacao pragmatica de Clean Architecture ao contexto de shell:

| Camada | Conteudo | Regra de dependencia |
|---|---|---|
| Entrada | `bin/dbx` | Depende de `lib/cli` e do despacho para `commands/` |
| Casos de uso | `commands/*` | Dependem de `lib/*`; nunca invocam `cURL` diretamente |
| **Orquestracao** | `lib/transfer`, `lib/walk`, `lib/report` | Coordenam dominio e adaptadores. **Podem** depender de adaptadores; nunca dependem de `commands/*` |
| Adaptadores | `lib/http`, `lib/auth`, `lib/json`, `lib/config`, `lib/output`, `lib/log`, `lib/tmp` e ~~`lib/stream`~~ | Dependem de utilitarios do sistema; nunca dependem de `commands/*`. ⚠️ **`lib/stream` e componente PLANEJADO que NAO se materializou** (v1.2, `DIV-20`): `RF-31` foi implementado em `lib/transfer` + `lib/hash`, e `RF-32` ainda nao foi implementado |
| Dominio | `lib/path`, `lib/errors`, `lib/hash` (regras de caminho e confinamento, taxonomia de erro, calculo de resumo) | **Sem dependencia de adaptadores nem de orquestracao.** Puramente logico e testavel isoladamente |

A dependencia e unidirecional, do topo para a base. Nenhuma funcao de `lib/` conhece o comando que a invocou.

> **Correcao da v0.4 (DIV-A).** A tabela de camadas da v0.3 continha tres inconsistencias com o restante do documento, todas devolvidas pelo ciclo de QA:
>
> 1. **`lib/errors` nao depende de `lib/json`.** A tabela de componentes atribuia essa dependencia, contradizendo a classificacao de dominio. A **implementacao resolveu corretamente pela inversao**: `lib/errors` recebe a classe e o resumo de erro ja extraidos, sem interpretar JSON. Ha teste que reprova se `lib/errors` referenciar `jq`, `lib/json` ou qualquer adaptador. A dependencia foi removida da tabela de componentes.
> 2. **`lib/transfer` nao e dominio.** Depende de `lib/http`, que e adaptador de rede — a classificacao anterior tornaria a violacao de camada estrutural, e nasceria junto com F-01 e F-02 na Etapa 2. Reclassificado para a camada de **Orquestracao**, criada nesta versao para nomear com honestidade o que `lib/transfer`, `lib/walk` e `lib/report` sempre fizeram: coordenar dominio e adaptadores. O diagrama de componentes ja o posicionava fora do dominio; a tabela e que estava errada.
> 3. **`lib/hash` estava ausente** da tabela de camadas, embora presente no subgrafo de dominio do diagrama. Acrescentado ao dominio, onde de fato pertence: calculo puro, sem dependencia externa.
>
> Nenhuma das tres exigiu mudanca de codigo. Eram defeitos **do documento**, e o diagrama de componentes ja refletia o desenho correto.

### Principais capacidades do sistema

1. Configuracao assistida e autenticacao OAuth2 com refresh token e access token de curta duracao.
2. Envio de arquivos com selecao automatica entre requisicao unica e sessao em partes conforme o limite de 150 MB.
3. Recebimento de arquivos e pastas com verificacao de integridade por `content_hash`.
4. Gestao de conteudo remoto: listagem paginada, metadados, criacao de pasta, mover, copiar, excluir, buscar e compartilhar.
5. Consulta de informacoes de conta e uso de espaco.
6. Operacao nao assistida: codigos de saida deterministicos, saida estruturada, ausencia de bloqueio interativo e diagnostico com identificador de requisicao.

### Principais riscos arquiteturais

| Risco | Consequencia arquitetural |
|---|---|
| **Interpretador JSON proprio (RES-08, DP-08)** | ⬆️ **Risco elevado na v0.5.** DP-08 escolheu dependencia zero, que e a opcao de maior risco de defeito silencioso — foi a origem do defeito `DIV-04` no modelo de referencia. Concentra-se inteiramente em `lib/json`, e a defesa e o conjunto de teste adversarial de RNF-11. Nao ha caminho alternativo com `jq` para servir de contraprova |
| Circulacao de segredos em processo cujo `argv` e legivel por outros usuarios do host | Concentrado em `lib/auth` e `lib/http`; exige contrato interno que proiba passagem de segredo por argumento |
| ~~Divergencia de utilitarios entre plataformas (GNU versus BSD)~~ | ✅ **Eliminado na v0.5.** DP-07 fixou Linux, entao `stat`, `sed`, `date` e `base64` podem assumir sintaxe GNU. **A camada de compatibilidade deixa de ser necessaria** — trabalho removido do plano |
| Acoplamento a contratos externos sujeitos a descontinuidade | Mitigado pela concentracao em `lib/http` e por uma tabela unica de endpoints |
| Operacoes de escrita longas passiveis de interrupcao | Exige politica de limpeza deterministica e de nao publicacao de estado parcial no destino |

---

## Componentes e responsabilidades

| Componente | Responsabilidade | Entradas | Saidas | Dependencias | Observacoes |
|---|---|---|---|---|---|
| `bin/dbx` | Ponto de entrada unico. Verificacao previa de ambiente, interpretacao de opcoes globais e despacho para o comando | Argumentos de linha de comando, variaveis de ambiente | Codigo de saida do processo | `lib/preflight`, `lib/cli` | Deve permanecer fino; sem regra de negocio |
| `lib/preflight` | Verificar versao minima de shell, presenca dos utilitarios obrigatorios e **a permissao do arquivo de credencial** | Ambiente de execucao | Sucesso ou falha nomeando o item ausente ou a permissao incorreta | Utilitarios do sistema | ✅ **Destravado na v0.5.** Piso `bash` **4.4** (DP-07); dependencia externa unica de `cURL` (DP-08); **recusa a execucao** se o arquivo de credencial nao estiver em `0600` (DP-11) — recusa, nao alerta. Atende RNF-01, RNF-02 e RNF-04 |
| `lib/cli` | Interpretacao de opcoes, validacao de aridade, ajuda de uso, modo de simulacao e deteccao de terminal interativo | Argumentos | Estrutura de invocacao normalizada | `lib/output` | Atende RF-15, RF-27 e RNF-19 |
| `lib/config` | Localizar, validar e carregar **a** credencial; aplicar e verificar permissoes restritas; carregar as raizes permitidas | Nenhum seletor | Credenciais em memoria, raizes permitidas | Sistema de arquivos | ✅ **Desenho INTEGRALMENTE fechado na v0.6: um arquivo, um caminho, sem multiplexacao.** Arquivo `0600` sob `$XDG_CONFIG_HOME` com recuo para `~/.config` (DP-11); **sem nocao de perfil e sem seletor** (DP-05); **credencial nao pode vir de variavel de ambiente**, e nenhum caminho de codigo a le do ambiente. Atende RF-03, RNF-04, RNF-20. Verificavel: nenhuma funcao do componente recebe identificador de conta ou de perfil |
| `lib/auth` | Trocar codigo de autorizacao por refresh token; obter e renovar access token; revogar token | Credenciais, codigo de autorizacao | Access token em memoria com prazo de validade | `lib/http`, `lib/config` | **Unico componente autorizado a manipular segredo.** Atende RF-01, RF-02, RF-04, RNF-03. **v1.5 (`RF-63`):** renovacao e troca de codigo **exigem** `client_secret` e recusam antes da rede quando ele falta; nao ha ramo sem segredo nem PKCE (`F-35`) |
| `lib/http` | Unico ponto de saida de rede. Montagem de requisicao, injecao de credencial fora do `argv`, retentativa com recuo, captura de codigo HTTP e do cabecalho de correlacao. **Enviar `limit`/`max_results` explicito em toda chamada de colecao e paginar por cursor** | Endpoint, cabecalhos, corpo, arquivo | Corpo de resposta, codigo HTTP, metadados de diagnostico | `cURL`, `lib/errors`, `lib/log` | Concentra RNF-03, RNF-06, RNF-07, RNF-08 e **RNF-23**. **Acoplamento novo na v0.6:** o teto de 256 KiB de `lib/json` e uma restricao **de projeto** sobre `lib/http`, nao um detalhe interno do analisador. Sem `limit` explicito, pasta grande falharia por recusa de analise — erro interno sem relacao aparente com o tamanho da pasta — em vez de paginar corretamente |
| `lib/errors` | Taxonomia de erro: traduzir codigo HTTP e resumo de erro **ja extraido** em classe de erro, mensagem acionavel e codigo de saida | Codigo HTTP, resumo de erro em texto, indicador de idempotencia da operacao | Classe de erro e codigo de saida | **Nenhuma.** Componente de dominio puro | Correspondencia por prefixo do resumo de erro, conforme orientacao da Dropbox. Atende RF-29 e RNF-08. **Corrigido na v0.4 (DIV-A.1):** a v0.3 atribuia dependencia de `lib/json`, contradizendo a classificacao de dominio. A extracao do campo e responsabilidade de quem chama; `lib/errors` recebe texto. Ha teste que reprova se o componente referenciar `jq`, `lib/json` ou qualquer adaptador |
| `lib/json` | Extrair campos de resposta de forma resistente a variacao de formatacao e a valores com delimitadores, **dentro de um teto de entrada de 256 KiB**, mantendo estado em **contextos nomeados** | Corpo de resposta ate 256 KiB, nome de contexto de origem interna | Valores de campo | Nenhuma dependencia externa | ✅ **Entregue.** DP-08 fixou **interpretador proprio em shell, sem `jq`**. Atende RNF-11, RNF-23 e **RNF-24**. **Teto de 256 KiB** fixado por medicao (4 MiB extrapolava para ~86 s): fronteira explicita em vez de degradacao aparecendo como travamento. **Contexto nomeado (v0.7, `E3-01`):** permite analisar corpo de erro **sem destruir uma analise em curso** — padrao previsto para a Etapa 3, quando `lib/http` interpretar erro no meio de listagem paginada. ~50 linhas, **sem mudanca de assinatura** das funcoes publicas. ⚠️ **O nome do contexto e escolhido pelo projeto e nunca deriva de dado externo**, restrito a `[a-z_]+`: a composicao de chave que fechou `E2-01` so e injetiva porque o espaco de nomes e controlado |
| `lib/transfer` | **Orquestracao** da transferencia: decidir entre requisicao unica e sessao em partes, dimensionar partes, coordenar retentativa por parte, verificar `content_hash` e **decidir a omissao quando origem e destino tiverem conteudo identico** | Caminho local ou fluxo, caminho remoto, politicas | Resultado da transferencia | `lib/http`, `lib/tmp`, `lib/hash` ~~, `lib/stream`~~ | Nucleo de RF-07 a RF-11, RF-31, RF-33, RNF-09. **Atualizado na v1.2 com a entrega de 2026-08-19:** a dependencia de `lib/stream` **cai — o componente nao existe** (`DIV-20`); `lib/transfer` absorveu o caminho de fluxo de `RF-31` e consome a **API incremental** de `lib/hash`. ⚠️ **Tamanho de parte FIXO em 4.194.304 bytes** (`readonly DBX_TRANSFER_TAMANHO_PARTE`), roteamento por sessao acima de 157.286.400 bytes: a **parte de rede e a mesma grandeza que o bloco do `content_hash`**, e e essa coincidencia que torna o teto de ocupacao de `RF-31` **consequencia estrutural** em vez de promessa a vigiar. Separar as duas grandezas e o trabalho que fecharia a lacuna de `RF-08` (`DIV-19`, `DP-30`). ⚠️ **Limite declarado (`DIV-18`, `RSK-36`):** produtor de cano anonimo que morre no meio e indistinguivel de fim de fluxo legitimo, e **nao ha mitigacao dentro do processo**. A decisao de omissao compara `content_hash`, **nunca** nome, tamanho ou data. **Reclassificado na v0.4 (DIV-A.2):** a v0.3 o listava como dominio, o que era incompativel com a dependencia de `lib/http`. Pertence a camada de Orquestracao |
| ~~`lib/stream`~~ | 🔴 **COMPONENTE PLANEJADO QUE NAO SE MATERIALIZOU (v1.2, `DIV-20`).** Previsto na v0.3 para adaptar entrada e saida padrao a transferencia | — | — | — | **Verificado por leitura direta de `lib/` em 2026-08-19: o arquivo nao existe e nunca foi criado.** A responsabilidade que ele nomeava para **`RF-31`** ficou em **`lib/transfer`** (laco de sessao, buffer de um bloco, area temporaria) e em **`lib/hash`** (API incremental `dbx_hash_acumular_iniciar` / `_bloco` / `_encerrar`). **`RF-32` nao foi implementado**, e onde alojar o caminho de saida por fluxo permanece **decisao de desenho em aberto** — o precedente de `RF-31` sugere `lib/transfer`, mas isso e do Senior Developer sob o Tech Lead e **nao esta decidido aqui**. **A linha e mantida riscada, e nao removida:** um componente previsto que nao nasceu e informacao de rastreabilidade |
| `lib/state` | **Novo na v0.8.** Persistir e recuperar a **linha de base de sincronizacao** e o **cursor de enumeracao**, vinculados ao par de raizes **e a identidade da conta**; versionar o formato, verificar integridade e gravar de forma atomica | Par de raizes, identidade da conta, estado convergido **verificado pela descida** | Linha de base carregada ou recusa explicita | Sistema de arquivos | Atende RF-38, RF-42, RF-43, **RF-50**, **RF-52**, RNF-25, RNF-26. 🔴 **`RF-50` (v1.0):** grava **apenas** caminhos que a propria descida de `lib/walk` verificou — **nunca por re-resolucao de texto**. Sem essa regra, uma travessia que escapasse gravaria caminhos de fora da raiz, que na execucao seguinte virariam orfaos e seriam apagados **com o atacante ja ausente** (`RSK-34`): a janela de ataque e transitoria, a consequencia e persistente. 🔴 **`RF-52`:** base vinculada a **identidade da conta**; relink a conta diferente com base preservada faria caminhos ausentes no novo remoto casarem a linha "apagado no remoto" da matriz e **apagarem arquivos locais do usuario**. **Unico componente autorizado a escrever estado persistente** alem de `lib/config`. Escrita atomica por arquivo temporario e substituicao; permissao `0600`; **nao guarda credencial nem conteudo de arquivo**. ⚠️ **Separa estritamente linha de base e cursor de enumeracao** — a Dropbox invalida o segundo com `reset`, e aplicar isso ao primeiro apagaria a memoria do que foi sincronizado (`RSK-32`). 🔄 **v1.5 (`DP-34`): cache UNICO de `content_hash`, com dois namespaces** no diretorio `$XDG_STATE_HOME/dbx` (criado em `0700`, `RNF-25(b)`): **`memoria-<resumo>`** do `sync` (um arquivo por conta, raiz local canonica e raiz remota; grava so as entradas visitadas em travessia completa, `RF-38(b)`; sem conta, nao le nem grava, `RF-52(a)`) e **`upload-<resumo>`** do `upload` (um arquivo por origem canonica, registro unico com `content_hash`, tamanho, `mtime`/`ctime` em ns, dispositivo e inode; sem vinculo a conta; poda acima de 10.000 arquivos dos nao usados ha 90 dias; `RF-61`, `RF-62`). O `upload` **nunca** toca `memoria-*` (protecao de `RF-48`, `RSK-45`). Formato NUL versionado, carga em array associativo (consulta O(1)), gravacao unica por `mktemp` no mesmo diretorio e `mv`; corrupcao descarta e reconstroi (`RF-42`). **Nenhuma dependencia externa**: so `stat`, `readlink`, `find`, `mktemp` e `mv`, ja no `lib/preflight` |
| ~~`lib/db`~~ | 🔴 **REMOVIDO NA v1.5 (`DP-34`).** Cache de metadados e historico de operacoes em SQLite (`dbx.db`, modo WAL), via `sqlite3` ou recuo para `python3`, introduzido em 2026-10-08 **sem passar por este documento nem pelo `RNF-26`** (`DIV-25`) | — | — | — | Saiu por decisao do solicitante: dependencia contraria a `RNF-02`, estado fora de `RNF-26`, e o skip do `upload` apoiado nele decidia so pelo lado local (`RSK-37`). Custo medido pelo DBA: ~10 ms por processo, de 4 a 6 processos por `upload` e 1 a 2 por arquivo no `sync` (100–200 s de processos com 10 mil arquivos, contra ~0,2 s do `lib/state`). O `dbx.db*` existente fica **inerte**: nada o le, escreve, migra ou apaga (`RNF-33`). **A linha fica riscada, e nao removida**, pelo mesmo motivo de `lib/stream` |
| `lib/sync` | **Novo na v0.8. Orquestracao.** Aplicar a matriz de decisao de tres estados, classificar conflitos, ordenar vencedores, decidir propagacao de exclusao e aplicar as salvaguardas | Raizes, linha de base, opcoes | Plano de acoes e resultado | `lib/state`, `lib/transfer`, `lib/walk`, `lib/hash`, `lib/http`, `lib/report` | Atende RF-37, RF-39, RF-39a, RF-40, RF-40a, RF-41, RF-44, RF-46, RF-47, RF-48. **Separacao interna obrigatoria (v0.9):** a **deteccao** de conflito usa exclusivamente `content_hash` contra a linha de base — **nenhum carimbo de tempo**, com mutacao que reprova se vazar; carimbo participa **somente** da **ordenacao**, e essa e a unica etapa declaradamente sujeita a erro. **Nenhuma exclusao e emitida antes de `RF-41` ser avaliada**, e `RF-41(a)` e a unica protecao estrutural restante apos `DP-24` dispensar o teto. O plano de simulacao (RF-44) e **identico** ao conjunto de acoes da execucao real sobre o mesmo estado |
| `lib/report` | Acumular contagens e metricas da execucao e produzir o relatorio final | Eventos de resultado por item | Estrutura de relatorio | `lib/output` | **Novo na v0.3.** Atende RF-36. Acumula **em memoria durante a execucao**; nao persiste entre execucoes, preservando a invariante de ausencia de estado local |
| `lib/hash` | Calcular o `content_hash` da Dropbox para verificacao de integridade e para a decisao de omissao por conteudo identico | Arquivo local ou fluxo | Valor de resumo em 64 caracteres hexadecimais | Utilitario de resumo SHA-256 do sistema | ✅ **Algoritmo confirmado na v0.3, componente desbloqueado.** Procedimento oficial: dividir em blocos de 4 MiB (4.194.304 bytes) · aplicar SHA-256 a cada bloco · concatenar os resumos **em formato binario**, nao hexadecimal · aplicar SHA-256 a concatenacao · emitir em hexadecimal. Ha vetor de teste oficial, adotado como criterio de aceite em RF-34. Load-bearing para RF-07, RF-11, RF-33 e RF-34. **Ponto de atencao de implementacao:** a concatenacao e de bytes brutos; concatenar as representacoes hexadecimais produz resultado errado que so aparece na comparacao com a API |
| `lib/tmp` | ✅ **ENTREGUE NA FASE 2 (v1.10; `DIV-42`).** **Registro unico** de areas temporarias e de acoes de limpeza do processo, e **unico dono de `trap`** (e de `mktemp` para areas). **Tratadores:** um por sinal (`EXIT`, `INT`, `TERM`, `HUP`), **armados uma vez por processo** na primeira criacao ou registro; nenhum modulo chama `trap`, de modo que nenhum tratador sobrescreve outro. **Registro:** lista de **acoes** de limpeza (funcao nomeada mais um argumento, como a liberacao da trava) e lista de **areas** (diretorios e arquivos `0700`/`0600`, `umask` preservado), cada entrada com o `BASHPID` de quem a registrou: **subshell herda o registro mas nao o tratador, e o tratador de um processo so limpa as entradas dele** (o resumo calculado em `$( )` nao apaga a area nem libera a trava de quem o chamou). **Ordem da limpeza:** primeiro as acoes, em ordem inversa ao registro; depois as areas, tambem em ordem inversa; cada entrada sai do registro antes de executar, para nunca repetir. **Criacao + registro com sinais retidos:** a criacao da area e o seu registro ocorrem numa secao critica em que `INT`, `TERM` e `HUP` sao apenas anotados e entregues no fim, ja com a area registrada (sem janela, `OBS-03`); a mesma secao e exposta a `lib/state` para criar a trava e registrar a sua liberacao sem janela. **Sinal durante a limpeza** nao a interrompe (a limpeza inteira e secao critica; o sinal anotado e descartado). **Codigo de saida:** termino normal preserva o original (o tratador de `EXIT` nao chama `exit`); termino por sinal sai com `nao_concluida` (**14**, `RNF-31`). Nao ha mais canal de sinal proprio por modulo. Os nomes de area (`dbx-sync.*`) nao mudam | Pedido de area ou arquivo temporario; acao a registrar; cancelamento ou esquecimento | Caminho temporario; limpeza garantida em todo termino | `mktemp`, `trap`, `rm` | Atende `RNF-05`, `RNF-29(c)`, `RNF-31`, **`RNF-35`** e **`RNF-36`**. Cobre `OBS-02`, `OBS-03` e `OBS-04`. Depende so de `lib/errors` |
| `lib/walk` | Percorrer arvore local ou remota aplicando padroes de inclusao e exclusao, **por descida um nivel por vez com nome relativo** | Caminho raiz, padroes | Sequencia de itens verificados pela propria descida | `lib/path` | Suporta RF-12, RF-13 e o percurso do `sync`. 🔴 **`RNF-28` (v1.0):** desce mantendo o diretorio aberto e opera sempre com **nome relativo**; em `bash`, `cd` referencia o **inode**, nao o texto — equivalente em shell de `openat` com `O_NOFOLLOW` por componente. **Nunca reconstroi caminho absoluto em texto para reabrir componente ja percorrido.** Verificado experimentalmente: com caminho absoluto reconstruido o ataque de troca por symlink alcanca alvo fora da raiz; com descida, na mesma janela, o alvo sobrevive. ⚠️ **Limite declarado:** protege os componentes **ja percorridos**, nao a troca imediatamente antes de descer — reducao de superficie, nao eliminacao |
| `lib/filtro` | 🔧 **Novo na v1.12 (fase 4; decidido, `DIV-94`).** Validar e compilar os padroes de `--excluir`/`--incluir` (sintaxe gitignore com os desvios de `DIV-79`), as faixas de data e tamanho e a taxa de banda; decidir se um caminho relativo (e, para data e tamanho, seus atributos) esta no escopo, pela chave sem caixa de `RF-54` | Padroes, faixas, caminho relativo, tipo (pasta ou arquivo), `mtime`/`server_modified`, tamanho | Valido/malformado (`2`); dentro/fora do escopo; "nao desca nesta pasta"; contagem de casamentos por padrao (avisos de `RF-80(m)`) | `lib/sync` (funcao de chave sem caixa) | **Puro:** sem rede, sem disco, sem estado, sem `eval` nem expansao de nome de arquivo (`RF-79(l)`). **Por que modulo novo:** o casamento tem de ser **o mesmo** no percurso local (`lib/walk`) e na enumeracao remota (`lib/sync`); em cada lado seria codigo gemeo (`RNF-36`), e a regra que protege o espelhamento (`RF-80(d)`) depende de os dois lados casarem igual. Testavel por unidade, entra no mapa de modulos (`RF-83`). **Alternativa** (filtro dentro de `lib/walk`, como a linha acima ja previa): rejeitada porque `lib/walk` nao enumera o remoto |
| `lib/path` | Normalizar caminho, tratar raiz, separadores, codificacao e caracteres especiais; **recusar caminho fora da raiz permitida nos dois espacos de nomes** — remoto, antes de qualquer chamada de rede, e local, antes de qualquer acesso a disco | Caminho informado, raiz remota permitida, raiz local permitida, opt-in de raiz `/` | Caminho normalizado ou recusa | — | Componente de dominio puro. Atende RNF-10 e RNF-20. **Ampliado na v0.4, com aceite do solicitante:** o confinamento local usa **resolucao fisica de symlinks**, nao comparacao textual de prefixo; oito vetores de ataque foram exercitados e resistidos (symlink absoluto, relativo, para arquivo de sistema, ciclo, `..` acima da raiz, absoluto externo, raiz que e ela propria symlink, prefixo semelhante `/backups2` contra `/backups`); a raiz `/` exige **opt-in explicito** e, sem ele, **falha fechado**. Risco residual TOCTOU aceito e documentado em `RSK-24`. Medicao: profundidade 5.000 em 0,88 s |
| `lib/output` | Manter o modelo de resultado unico e renderiza-lo em **duas apresentacoes** — legivel por humano e estruturada por maquina — e em **dois terminadores de registro**: linha por padrao, byte nulo com `--null`. Selecionar a apresentacao por deteccao de terminal associado, sobreponivel por sinalizador. Separar saida padrao de saida de erro | Resultado estruturado do comando | Texto renderizado | `lib/cli` para o contexto de execucao | ✅ **Destravado na v0.5** por DIV-16b. Atende RF-28, RNF-19 e RNF-22. **Nenhum comando emite texto diretamente** — regra verificavel por analise estatica. ⚠️ **RNF-22 vale nos dois modos:** a redacao de cabecalho sensivel opera sobre **quebras de linha**, nao sobre terminadores de registro; em `--null` varios registros compartilham a mesma linha fisica, de modo que concatenar diagnostico a cabecalho sensivel pode destruir **mais** conteudo que no modo padrao. Caso de teste dedicado por modo |
| `lib/log` | Registro de diagnostico por nivel, com filtro obrigatorio de segredo | Eventos internos | Registro na saida de erro ou destino configurado | — | Atende RF-30. Politica de retencao depende de DP-10 |
| `commands/*` | Um caso de uso por comando (*v1.11: mais `revisoes`, `restaurar` e `lixeira`, secao "Revisoes, restauracao e lixeira"; a lista abaixo e a do desenho inicial e inclui comandos nunca criados, `DIV-68`; os existentes estao em `commands/`*) (*v1.7: mais `verificar`, `diagnostico` e `completar`; tabela na secao "Comandos de consulta, diagnostico e autocompletar"*): `config`, `upload`, `download`, `list`, `stat`, `mkdir`, `move`, `copy`, `delete`, `search`, `share`, `account`, `unlink` e condicionais `saveurl` e `monitor` | Invocacao normalizada | Resultado e codigo de saida | `lib/*` | Nao invocam `cURL` diretamente. Regra verificavel por analise estatica |
| `tests/` | Suite automatizada executavel sem credencial real, com duplo de teste do servico HTTP | — | Relatorio de execucao | Arcabouco a definir pelo Senior Developer | Atende RNF-14 |

### Comandos de consulta, diagnostico e autocompletar *(v1.7, fase 1, em andamento)*

Tabela de comandos acrescida (`RF-65` a `RF-68`; as fontes de cada decisao estao em [Escopo e requisitos](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), secao 5.9):

| Comando | Alias | Requisito de ambiente declarado | Papel | Escrita | Codigos de saida proprios |
|---|---|---|---|---|---|
| `verificar` | `verify` | `credencial` | Compara arvore local e remota por `content_hash`, com os argumentos e as guardas do `sync` (`RF-65`; `F-11`). Reusa `lib/sync` (chave sem caixa, planejamento) e `lib/walk` | **Nenhuma**, nem estado de `lib/state` (a memoria so e lida e nao decide) | `0` igual; `11` (`integridade`) diverge; `14` travessia parcial; demais, a classe do erro |
| `diagnostico` | `doctor` | **`nenhum`** (ver nota abaixo) | Sete checagens com remedio: dependencias, credencial, conectividade (`check/user`), escopos, espaco, localidade, diretorio de estado (`RF-66`; `F-22`) | **Nenhuma** (nao cria nem corrige nada) | `0` sem falha; `3` (`configuracao`) com ao menos uma falha |
| `completar` | `completion` | `nenhum` | `dbx completar bash` imprime `completions/dbx.bash` (`RF-68`; `F-19`) | **Nenhuma** | `0`; `2` sem argumento ou shell nao suportado |

> **Preflight contornado pelo `diagnostico` (e pelo `completar`).** `bin/dbx` executa o preflight **bloqueante** (`lib/preflight`, para no primeiro problema e responde com a classe `configuracao`) para os comandos que declaram `ambiente` ou `credencial`. O `diagnostico` existe para **diagnosticar** exatamente o que o preflight recusa, entao declara `nenhum` e faz sua **propria inspecao, que nao para no primeiro item**: reporta cada utilitario ausente, a permissao da credencial e o resto, e sai com `3` se houver falha. Consequencias de desenho: (1) o comando so usa recursos do proprio shell ate emitir o relatorio, sem utilitario externo (mesma razao de `lib/preflight`, `TL-30`); (2) a inspecao reaproveita a **mesma lista** `DBX_PREFLIGHT_UTILITARIOS`, para nunca discordar do preflight (`DIV-36`, encerrada: `tail` e `df` ja constam da lista); (3) o contorno vale **so** para este comando, e os demais continuam recusados pelo preflight (regressao testada, `TC-DIA-04`); (4) `diagnostico` nao e rota para executar operacao com ambiente quebrado: ele nao escreve, local ou remotamente.

**Checagem previa de espaco (`RF-67`, `F-21`).** Etapa nova do `upload` e do `sync --enviar`, **depois** do plano e das guardas de `RF-41` e `RF-48` e **antes** da primeira acao: uma consulta `get_space_usage`, comparacao do total a transferir com a folga, e recusa `espaco` (`12`) sem escrita quando nao cabe. `--forcar` pula a etapa; `--dry-run` so avisa; falha da consulta so avisa; `upload -` nao e checado. Sobrescrita conta o total novo (criterio conservador). Diagrama:

```mermaid
flowchart TD
  A[Plano calculado e guardas RF-41 e RF-48 aprovadas] --> B{--forcar, entrada padrao ou total zero?}
  B -->|Sim| G[Executa sem consultar]
  B -->|Nao| C[get_space_usage, uma vez]
  C -->|Falhou| W[Aviso em stderr] --> G
  C -->|Folga obtida| D{Total a transferir maior que a folga?}
  D -->|Nao| G
  D -->|Sim, execucao real| R[Recusa, classe espaco, codigo 12, nenhuma escrita]
  D -->|Sim, --dry-run| P[Plano avisa que recusaria, codigo 0]
```

**Autocompletar (`RF-68`, `F-19`).** `completions/dbx.bash` e artefato estatico versionado, sem chamada de rede, sem leitura de credencial ou estado. O `install.sh` o grava em `~/.local/share/bash-completion/completions/dbx` (modo usuario, sem sudo); `dbx completar bash` o imprime a partir da arvore de instalacao. Deve acompanhar as ajudas de `bin/dbx` (teste de desvio `TC-CPL-02`) e entrar no pacote de `scripts/empacotar.sh`.

### Revisoes, restauracao e lixeira *(v1.11, fase 3, em andamento)*

Decisao do solicitante (`DP-37`, memoria `2026-10-19-1828-recuperacao-e-lixeira`); requisitos `RF-72` a `RF-78` ([Escopo e requisitos](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), secao 5.11); divergencias `DIV-54` a `DIV-69`. Tres comandos novos, **nenhum componente novo em `lib/`**, **nenhum estado persistente** (`RNF-26` intacto) e **nenhum codigo de saida novo**. As tags de erro novas entram em `lib/errors` como mapeamento a classes existentes (`DIV-58`).

| Comando | Alias | Requisito de ambiente | Papel | Endpoints | Escrita | Codigos proprios |
|---|---|---|---|---|---|---|
| `commands/revisoes.sh` | `revisions` | `credencial` | Lista revisoes de um arquivo (`RF-72`) | `list_revisions` (modo `path` ou `id`, `limit` 1..100) | Nenhuma | `0`; `2` pasta ou uso; `4` |
| `commands/restaurar.sh` | `restore` | `credencial` | Restaura arquivo por `--rev` ou `--antes-de`, inclusive apagado (`RF-73`); pasta apagada recursiva, arquivo por arquivo (`RF-74`) | `get_metadata` (`include_deleted`), `list_revisions` (paginado por `before_rev`), `list_folder`/`continue` (`include_deleted`), `restore` | Remota (`restore`) | `0`; `14` falha parcial na pasta; demais pela classe |
| `commands/lixeira.sh` | `trash` | `credencial` | Lista apagados (`RF-75`); `--excluir`/`--purge` expurga com confirmacao (`RF-76`, forma decidida em `DIV-55`) | `list_folder`/`continue` (`include_deleted`, `include_restorable_info`), `get_metadata`, `permanently_delete` | Remota irreversivel (so `--excluir`) | `0`; `2` item vivo ou sem confirmacao; `5` escopo; `6` conta pessoal; `14` caminho digitado errado |

**Reuso, sem codigo gemeo (`RNF-36`):** emissao de metadados por `_dbx_cmd_metadado_em` (mesmos campos de `info`/`list`); toda escrita remota por `_dbx_cmd_escrita_remota` (simulacao, mapeamento de erro; `in_progress` retentado e depois `14`, `QA-B3-03`); `lib/json` recusa `\u0000`, substituto UTF-16 isolado e escape incompleto como `malformado` (`QA-B3-04`); confinamento por `lib/path` (`RNF-20(b1..b6)`) antes de qualquer chamada; descida remota um nivel por vez pelo mesmo percurso do `sync` (`RNF-28`); relatorio por item como `RF-59`; areas e sinal por `lib/tmp`. **Trava:** os tres comandos nao travam nem consultam a trava (decidido, `DIV-63`). **Escopo novo:** `files.permanent_delete`, **opcional**; so `lixeira --excluir` o exige, e o `diagnostico` o mostra como opcional (`RF-77`).

Fluxo de restauracao (arquivo e pasta):

```mermaid
flowchart TD
  A[dbx restaurar caminho] --> B{Argumentos validos? rev hexadecimal com 9 ou mais; --rev e --antes-de exclusivos; data UTC}
  B -->|Nao| X2[Recusa uso_invalido 2, sem rede]
  B -->|Sim| C{Dentro da raiz_remota?}
  C -->|Nao| X13[Recusa caminho_recusado 13, sem rede]
  C -->|Sim| D[get_metadata include_deleted]
  D -->|Nao existe| X4[nao_encontrado 4]
  D -->|Arquivo vivo ou apagado| E[list_revisions modo path, paginado por before_rev]
  E --> F{Revisao escolhida: --rev no historico, ou mais recente ate a data, ou ultima se apagado}
  F -->|Nenhuma| X4
  F -->|Igual a vigente| J[ja_atual, codigo 0, sem restore]
  F -->|Encontrada| G{--dry-run?}
  G -->|Sim| S[Anuncia rev_escolhida e rev_substituida, codigo 0]
  G -->|Nao| H[restore path e rev] --> I[Saida com rev_substituida e comando para desfazer, codigo 0]
  D -->|Pasta viva| X2v[uso_invalido 2, sem escrita]
  D -->|Pasta apagada| P[Descida um nivel por vez com list_folder include_deleted]
  P --> Q[Para cada arquivo apagado: list_revisions limit 1 e restore; fora da raiz, fora da pasta pedida ou sem revisao conta como falha; so descendente estrito, pastas visitadas sem caixa; in_progress retentado e depois 14]
  Q --> R{Alguma falha de item ou travessia parcial?}
  R -->|Nao| R0[Resumo, codigo 0]
  R -->|Sim| R14[Resumo com o que faltou, nao_concluida 14]
```

Fluxo da exclusao permanente:

```mermaid
flowchart TD
  A[dbx lixeira --excluir caminho] --> B{Uso valido e alvo diferente da raiz?}
  B -->|Nao| X2[uso_invalido 2]
  B -->|Sim| C{Dentro da raiz_remota?}
  C -->|Nao| X13[caminho_recusado 13, sem rede]
  C -->|Sim| K{--confirmar-caminho identico ao alvo, terminal ou --dry-run?}
  K -->|Sem opcao e sem terminal| X2b[uso_invalido 2, sem chamada a API]
  K -->|Ok| D[get_metadata include_deleted]
  D -->|Item vivo| XV[uso_invalido 2: apague antes com dbx delete]
  D -->|Inexistente| X4[nao_encontrado 4]
  D -->|DeletedMetadata| GA{path_lower presente e igual ao alvo, dobra so ASCII, sem chave repetida?}
  GA -->|Nao| X10[erro_remoto 10, sem expurgo]
  GA -->|Sim| W[Aviso de irreversibilidade em stderr; pasta: contagem do primeiro nivel]
  W --> G{--dry-run?}
  G -->|Sim| S[Anuncia o que seria expurgado, codigo 0]
  G -->|Nao| T{Confirmado? --confirmar-caminho ou caminho digitado igual ao literal ou ao normalizado, caixa exata}
  T -->|Digitado diferente| X14[nao_concluida 14, nada feito]
  T -->|Sim| P[permanently_delete]
  P -->|Sucesso| OK[expurgado, codigo 0]
  P -->|Conta pessoal| X6[permissao 6, remedio: dbx delete]
  P -->|missing_scope| X5[autenticacao 5, remedio: App Console, dbx unlink e dbx config]
```

### Filtros e limite de banda *(v1.12, fase 4, em andamento)*

Decisao do solicitante (memoria `2026-10-19-2141-filtros-e-banda`); requisitos `RF-79` a `RF-83` ([Escopo e requisitos](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), secao 5.12); divergencias `DIV-79` a `DIV-94` decididas pelo Tech Lead conforme as recomendacoes (memoria `2026-10-19-2141-filtros-e-banda`). **Um componente novo (`lib/filtro`, `DIV-94`)**, **nenhum estado persistente novo** (filtros fora da memoria e da chave da trava), **nenhum codigo de saida novo**.

| Ponto | Onde | Desenho |
|---|---|---|
| Validacao | `lib/cli` chama `lib/filtro` | Padroes, datas, tamanhos e taxa validados **antes** da trava, da memoria e da rede (`2`) |
| Percurso local | `lib/walk` | Pergunta a `lib/filtro` antes de descer: pasta excluida nao e aberta (`RF-80(b)`); erro dentro dela nao chega a `RF-41(a)` |
| Enumeracao remota | `lib/sync` | `list_folder` recursivo continua; entradas fora do escopo descartadas (`DIV-82`) |
| Plano | `lib/sync` | Escopo aplicado **aos dois lados** antes da tabela de decisao: filtrado nunca vira "apagar" (`RF-80(d)`); guarda de origem vazia sobre o escopo (`RF-80(e)`) |
| Data e tamanho | `lib/filtro`, depois do escopo de caminho | So arquivos da origem; recusados com `--espelhar` (`RF-81(b)`) |
| Banda | `lib/http` (`_dbx_http_opcoes`) | `limit-rate = <inteiro>` so com `_DBX_HTTP_MODO=conteudo`, por requisicao (`RF-82(d)(e)(f)`); piso de 2 x `speed-limit` (`DIV-88`) |
| Saida | `lib/output` | `filtros`, `filtrados_origem`, `filtrados_destino`, `limite_banda` como acrescimo (`RF-35`) |

```mermaid
flowchart TD
  A[Caminho relativo e tipo] --> B{Ele ou pasta ancestral casa --excluir?}
  B -->|Sim| F[Filtrado nos dois lados: nao transfere, nao apaga; pasta nao e percorrida]
  B -->|Nao| C{Ha --incluir?}
  C -->|Nao| D{Arquivo da origem com data ou tamanho fora da faixa?}
  C -->|Sim| E{Ele ou pasta ancestral casa --incluir?}
  E -->|Nao, e pasta| P[Percorrida implicitamente]
  E -->|Nao, e arquivo| F
  E -->|Sim| D
  D -->|Sim| G[Filtrado so na origem: nao transfere; recusado com --espelhar]
  D -->|Nao| H[No escopo: entra na tabela de decisao]
```

---

## Integracoes e contratos

Endpoints vigentes da Dropbox API v2. **Endpoints retirados e depreciados sao proibidos por RNF-12.**

| Integracao | Tipo | Origem | Destino | Contrato ou protocolo | Risco principal |
|---|---|---|---|---|---|
| Autorizacao do usuario | Navegador externo (fora do processo) | Operador humano | `https://www.dropbox.com/oauth2/authorize` | Fluxo de codigo de autorizacao com `token_access_type=offline`, que e o que determina a emissao do refresh token de longa duracao. ~~PKCE disponivel por `code_challenge` e `code_challenge_method`, dispensando o segredo do aplicativo na troca~~ **(v1.5, `DP-34`):** a plataforma oferece PKCE, mas **esta aplicacao nao o implementa**; o `client_secret` e obrigatorio no `config` e na biblioteca (`RF-63`). PKCE fica no backlog como alternativa futura (`F-35`) | Passo manual; codigo de autorizacao expira rapidamente. **Host distinto do de API** |
| Emissao e renovacao de token | HTTPS `POST` | `lib/auth` | `https://api.dropbox.com/oauth2/token` | `grant_type=authorization_code` e `grant_type=refresh_token`. Autenticacao do aplicativo por **HTTP Basic ou por parametros no corpo**, ambos suportados. Resposta traz `access_token`, `token_type`, `expires_in` (exemplo documentado: `14400`) e `scope` | Exposicao de segredo se enviado por `argv` (RSK-03). **Inconsistencia documental:** o bloco de referencia indica `api.dropboxapi.com`; todos os exemplos executaveis usam `api.dropbox.com`. Ver DIV-11 |
| Revogacao de token | HTTPS `POST` | `lib/auth` | `https://api.dropboxapi.com/2/auth/token/revoke` | Sem corpo; autenticado por token | **Efeito em cascata:** invalida tambem o refresh token e todos os access tokens dele derivados (RES-12). Exige advertencia e confirmacao (RF-06a) |
| Metadados e operacoes de arquivos | HTTPS `POST` JSON | `lib/http` | `https://api.dropboxapi.com/2/files/*` | `get_metadata`, `list_folder`, `list_folder/continue`, `create_folder_v2`, `move_v2`, `copy_v2`, `delete_v2`. As variantes `_v2` retornam envelope com campo `metadata` | Uso inadvertido de variante ausente da documentacao vigente (RSK-04). **Chamadas simultaneas de listagem para o mesmo usuario produzem erro de limite de taxa** (RES-11, RSK-22) |
| Busca | HTTPS `POST` JSON | `commands/search` | `https://api.dropboxapi.com/2/files/search_v2` e `search/continue_v2` | Corpo com `query`, `options` (`path`, `max_results`, `file_status`, `filename_only`) e `match_field_options`. Paginacao por `cursor`, com `has_more` | Teto de **10.000 correspondencias**; resultados podem vir duplicados entre paginas ou ser omitidos por atraso de indexacao — deduplicacao e responsabilidade do cliente (RES-14, DIV-12) |
| Conteudo de arquivos | HTTPS `POST` binario | `lib/transfer` | `https://content.dropboxapi.com/2/files/*` | `upload`, `upload_session/start`, `upload_session/append_v2`, `upload_session/finish`, `download`. Parametros no cabecalho `Dropbox-API-Arg` com `Content-Type: application/octet-stream`. `start` aceita `session_type` (sequencial ou concorrente) e `close`; `finish` recebe `cursor` (`session_id` e `offset`) e `commit`. ✅ **Revalidado em 2026-08-19 contra `dropbox/dropbox-api-spec`, `files.stone`, ramo `main`** — contrato **documentado e lido, NAO exercitado** contra o servico real. **`UploadSessionCursor.offset`** e documentado como *"The amount of data that has been uploaded so far. We use this to make sure upload data isn't lost or duplicated in the event of a network error"*, e **`UploadSessionAppendError.incorrect_offset`** carrega `correct_offset` e cobre o caso em que *"a previous request was received and processed successfully but the client did not receive the response, e.g. due to a network error"*: **a retentativa por parte e suportada, e o deslocamento no cursor e a chave de deduplicacao** | **150 MiB** por requisicao, inclusive nas de sessao; maximo de 2^41 − 2^22 bytes por sessao; **a sessao vale no maximo 7 dias, apos o que o `session_id` devolve `not_found`** (`RES-18`); corrupcao em interrupcao. ⚠️ **Procedencia (`DIV-21`): consultar o ramo `main`.** O `master` do mesmo repositorio diz **48 horas** e **nao tem `session_type`** — quem revalidar por ele obtera numero errado e concluira que a distincao sequencial/concorrente nao existe, distincao da qual `RES-10` depende |
| Compartilhamento | HTTPS `POST` JSON | `lib/http` | `https://api.dropboxapi.com/2/sharing/*` | `create_shared_link_with_settings`, `list_shared_links`. **Nao usar** `create_shared_link` nem `get_shared_links`, explicitamente marcados como depreciados na documentacao | Conflito quando o link ja existe; recursos avancados dependem do plano contratado (DP-18) |
| Conta e espaco | HTTPS `POST` JSON | `lib/http` | `https://api.dropboxapi.com/2/users/*` | `get_current_account`, `get_space_usage` | Baixo |
| Revisoes, restauracao e lixeira *(v1.11)* | HTTPS `POST` JSON | `commands/revisoes`, `commands/restaurar`, `commands/lixeira` via `lib/http` | `https://api.dropboxapi.com/2/files/*` | `list_revisions` (`path`, `mode` `path`/`id`, `limit` 1..100, `before_rev` so no modo `path`; `ListRevisionsError`), `restore` (`path`, `rev` `[0-9a-f]{9,}`; `RestoreError`: `invalid_revision`, `in_progress`), `list_folder`/`get_metadata` com `include_deleted` (`DeletedMetadata`, sem tipo nem data), `permanently_delete` (`DeleteArg`; `DeleteError`; **so Dropbox Business**; apaga antes se o item estiver vivo). Lido em `files.stone`, ramo `main`, 2026-10-19; nao exercitado | Expurgo de item vivo (`DIV-54`, `RSK-51`); `rev` de outro arquivo (`DIV-59`); custo da restauracao recursiva (`RSK-53`); resposta em conta pessoal nao documentada (`DIV-57`) |
| Monitoramento por espera longa | HTTPS `POST` JSON | `commands/monitor` | `https://notify.dropboxapi.com/2/files/list_folder/longpoll` | Requisicao nao autenticada com cursor; tempo limite configuravel | Condicional a DP-16; consumo de conexao prolongada |
| Importacao por URL | HTTPS `POST` JSON | `commands/saveurl` | `https://api.dropboxapi.com/2/files/save_url` e `save_url/check_job_status` | Job assincrono com consulta de estado | Condicional a DP-06 |

### Escopos OAuth

Com acesso amplo concedido ao aplicativo (DP-04), o unico controle de granularidade restante e o conjunto de escopos. **Solicitar apenas o necessario** (RNF-20).

| Capacidade | Escopo | Verificacao |
|---|---|---|
| Recebimento de conteudo | `files.content.read` | Confirmado na documentacao |
| Envio de conteudo | `files.content.write` | Confirmado na documentacao |
| Metadados e listagem | `files.metadata.read` | Confirmado na documentacao |
| Compartilhamento — leitura | `sharing.read` | Confirmado para endpoints de sharing |
| Compartilhamento — escrita | `sharing.write` | Confirmado para endpoints de sharing |
| Informacoes de conta | `account_info.read` | Confirmado na documentacao |
| Exclusao permanente *(v1.11, opcional)* | `files.permanent_delete` | Confirmado em `files.stone` (`route permanently_delete`). So `lixeira --excluir`; habilitar no App Console, `dbx unlink` e `dbx config` (`DIV-56`). `list_revisions` usa `files.metadata.read` e `restore` usa `files.content.write`, ja exigidos |

> **Nao confirmado (DIV-14).** Os escopos especificos de `files/search_v2`, `sharing/create_shared_link_with_settings`, `users/get_current_account` e `users/get_space_usage` nao foram localizados na documentacao indexada. Devem ser confirmados diretamente em `developers.dropbox.com` antes de fixar o procedimento de configuracao, e nao presumidos por analogia.

### Semantica de erro adotada

| Codigo HTTP | Significado na Dropbox | Comportamento da aplicacao |
|---|---|---|
| `400` | Requisicao malformada ou endpoint indisponivel para o tipo de aplicativo | Falha imediata, **sem retentativa** |
| `401` | Token invalido, expirado ou sem escopo | Uma renovacao de token e uma repeticao; nova falha encerra com codigo de autenticacao |
| `403` | Acesso negado por plano, limite de conta ou politica | Falha; retentativa apenas com recuo exponencial se explicitamente habilitada |
| `409` | Erro especifico do endpoint (por exemplo `path_not_found`, `conflict`) | Mapeado por prefixo do `error_summary` para mensagem e codigo de saida especificos; sem retentativa |
| `429` | Limite de taxa por excesso de requisicoes ou por escritas simultaneas demais | Retentativa respeitando `Retry-After`, com recuo exponencial e variacao aleatoria. **Quando a causa for concorrencia de listagem para o mesmo usuario, retentativa cega agrava o problema**: a orientacao documentada e aguardar as requisicoes pendentes concluirem (RES-11) |
| `5xx` | Falha do lado da Dropbox | Retentativa com recuo exponencial, ate o limite configurado |

O corpo de erro segue o formato `{"error":{".tag":"<tag>"},"error_summary":"<tag>/..."}`. O mapeamento em `lib/errors` deve usar **correspondencia por prefixo** do `error_summary`, nunca igualdade exata, conforme orientacao da propria Dropbox. Exemplos de tags relevantes: `rate_limit`, `transient_error`, `content_hash_mismatch`, `no_permission`, `reset`.

> **Nota de verificacao (v0.2).** Os contratos desta secao foram revalidados via **Context7 MCP**, fonte preferencial definida no item 28 do protocolo comum, sobre a biblioteca `/websites/dropbox_developers_http`. A nota da v0.1 que registrava indisponibilidade do Context7 estava incorreta e foi removida junto com DIV-10 e RSK-17.
>
> **Permanecem nao confirmados por esta fonte (DIV-14):** o algoritmo de calculo do `content_hash`, a existencia do cabecalho `X-Dropbox-Request-Id` e os escopos de quatro endpoints. Devem ser verificados diretamente em `developers.dropbox.com` antes da implementacao.

---

## Arquitetura de desenvolvimento

- **Ambientes necessarios:** estacao de desenvolvimento **Linux** com `bash` 4.4 ou superior, `cURL` e coreutils; container de referencia reproduzindo a distribuicao minima suportada; aplicativo Dropbox dedicado a testes, separado do de producao, preferencialmente com acesso restrito a pasta do aplicativo.
- **Dependencias locais:** `cURL` **como unica dependencia de execucao**; analisador estatico de shell (`shellcheck`); arcabouco de teste de shell. **`jq` nao e dependencia** (DP-08) e nao deve ser introduzido nem como conveniencia de desenvolvimento em codigo de producao.
- **Versionamento:** repositorio publicado em `github.com:salesadriano/dropbox_sync`. Gitflow ativo — `develop` derivado de `master`, trabalho em `feature/*`, Conventional Commits a partir deste ponto. O commit inicial e anterior a adocao da convencao e **nao sera reescrito**.
- **Servicos de apoio:** servidor HTTP local usado como duplo de teste do servico Dropbox, permitindo a suite executar sem rede e sem credencial real; conta Dropbox de teste apenas para verificacao de contrato ponta a ponta, executada fora do fluxo padrao.
- **Observacoes de setup:**
  - O diretorio alvo **ainda nao e repositorio git** e nao possui stack instalada. A inicializacao do versionamento e o fluxo Gitflow dependem de DP-19.
  - Testes E2E com Cypress, previstos como padrao no item 13 do protocolo comum, **nao sao aplicaveis**: nao ha interface web ou grafica. A validacao ponta a ponta equivalente e a execucao dos comandos contra o duplo de teste HTTP e, quando autorizado, contra a conta de teste real. Este desvio deve ser registrado pelo QA Expert.
  - Nenhuma credencial real pode ser versionada nem exigida pela suite padrao.

---

## Arquitetura de producao

- **Topologia:** nao ha servidor nem servico exposto. A aplicacao e um artefato de script instalado no host que precisa da integracao, executado sob demanda pelo operador ou por agendador. Nao ha componente compartilhado entre hosts alem do proprio aplicativo registrado no Dropbox App Console, cuja cota de chamadas e comum a todas as instalacoes que o utilizam.
- **Componentes implantados:** artefato executavel instalado em diretorio de binarios do sistema; bibliotecas em diretorio de suporte; arquivo de configuracao por usuario com permissao restrita; unidade de agendamento (`cron` ou `systemd timer`) quando houver rotina nao assistida. *(v1.5)* Por usuario, o diretorio de estado `$XDG_STATE_HOME/dbx` (`0700`) com as memorias descartaveis de `lib/state`; nenhum banco de dados nem dependencia alem de `cURL` e coreutils.
- **Observabilidade:** saida de diagnostico por nivel na saida de erro; registro do `X-Dropbox-Request-Id` em falhas de API para suporte junto a Dropbox; codigo de saida como sinal primario para o orquestrador. Integracao com `syslog`, `journald` ou coletor centralizado depende de DP-10. Nao ha metricas nem rastreamento distribuido no escopo.
- **Alta disponibilidade e resiliencia:** nao aplicavel no sentido de servico, por ausencia de processo residente. A resiliencia relevante e a da execucao individual: retentativa com recuo, sessao de envio em partes com retentativa por parte, ausencia de estado parcial publicado no destino e limpeza deterministica de temporarios. A indisponibilidade da Dropbox e absorvida pela politica de retentativa e, esgotada, reportada por codigo de saida ao orquestrador.
- **Politica de rollback:** substituicao do artefato pela versao anterior, que e uma operacao de arquivo. O formato do arquivo de configuracao deve ser versionado e retrocompativel dentro de uma mesma linha principal; mudanca incompativel exige migracao explicita e aviso na atualizacao. Operacoes ja executadas contra a Dropbox **nao sao revertidas pelo rollback do artefato**; reversao de conteudo, quando necessaria, depende do historico de versoes da propria Dropbox.

---

## Implantacao

### Desenvolvimento

1. **Preparar o repositorio:** inicializar o versionamento conforme DP-19, publicar o arquivo de licenca decidido em DP-01 antes do primeiro commit de codigo, e registrar os cabecalhos de copyright.
2. **Preparar o ambiente:** instalar `cURL`, analisador estatico, arcabouco de teste e o interpretador JSON aprovado em DP-08; validar a versao minima de shell definida em DP-07.
3. **Registrar aplicativo de teste:** criar aplicativo dedicado no Dropbox App Console com `Scoped Access`, tipo de acesso conforme DP-04, e conceder somente os escopos exigidos pelos comandos do MVP.
4. **Configurar credencial local:** executar o comando de configuracao apontando para um arquivo de perfil de teste, fora da arvore versionada.
5. **Validacoes apos implantacao:** analisador estatico sem alertas nao suprimidos; suite automatizada integralmente aprovada sem rede e sem credencial real; auditoria estatica confirmando ausencia de endpoint retirado ou depreciado; verificacao de que nenhum segredo aparece na tabela de processos durante a execucao de um comando autenticado.

### Producao

1. **Registrar aplicativo de producao:** aplicativo proprio, distinto do de teste, com acesso a Dropbox inteira conforme DP-04 e com o **menor conjunto de escopos** suficiente para os comandos habilitados (RNF-20). Registrar o conjunto concedido na documentacao operacional. Avaliar a recomendacao de manter um aplicativo separado, com acesso restrito a pasta do aplicativo, para as rotinas nao assistidas que nao precisem alcancar toda a conta (RSK-19).
2. **Instalar o artefato:** copiar executavel e bibliotecas para os diretorios de destino com permissao de leitura e execucao, e sem permissao de escrita para usuarios comuns.
3. **Provisionar a credencial:** executar o comando de configuracao com o usuario que efetivamente executara a rotina; confirmar permissao `0600` no arquivo resultante; definir a **raiz remota permitida** para a rotina, limitando o alcance mesmo com acesso amplo concedido (RNF-20). Para execucao agendada, a configuracao deve pertencer ao mesmo usuario do agendamento e o caminho do arquivo deve ser informado explicitamente, pois o diretorio pessoal nem sempre e resolvido corretamente no ambiente do agendador.
4. **Configurar a rotina:** criar a unidade de agendamento com caminho absoluto do executavel, caminho absoluto da configuracao, modo silencioso e tratamento do codigo de saida pelo orquestrador.
5. **Validacoes apos implantacao:** executar comando de leitura de conta e confirmar codigo de saida `0`; executar um ciclo completo de envio e recebimento com verificacao de `content_hash` em area de teste remota; executar uma operacao em modo de simulacao e confirmar ausencia de escrita; confirmar que o registro de diagnostico nao contem segredo; confirmar que uma execucao sem terminal associado nao bloqueia aguardando entrada.
6. **Atualizacao a partir de versao com `lib/db` (v1.5):** nenhuma migracao. O `dbx.db*` antigo fica inerte no diretorio de estado e contem caminhos absolutos de arquivos enviados; removê-lo a mao com `rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/dbx/dbx.db"*`, ou deixar que o `unlink` o remova (`RNF-33`, `RF-51(f)`). O primeiro `upload`/`sync` apos a atualizacao recalcula os hashes. A memoria `1` de cada par espelhado e descartada: essa primeira execucao **nao propaga exclusoes e sai com codigo diferente de `0`** (`RF-41(f)`, `RSK-46`); a seguinte volta ao normal. Avisar nas notas da versao para rotinas agendadas. Origem vazia com algo a apagar no destino e recusada sempre (codigo `14`, `RF-41(b)`); rotina que precise esvaziar o destino de proposito usa `--permitir-origem-vazia`. O `install.sh` deixa de recomendar `sqlite3`.

---

## Dimensionamento da aplicacao

> **Premissas provisorias.** Os numeros abaixo sao estimativas de trabalho ate a resposta de DP-12. Devem ser substituidos pelos valores reais informados pelo solicitante e revisados com o retorno dos testes de exaustao do QA Expert.

- **Premissas de carga:** execucao por invocacao, sem processo residente; concorrencia padrao de uma transferencia por vez; um aplicativo Dropbox registrado compartilhado por todos os hosts; rotina agendada com periodicidade diaria ou horaria.
- **Volume esperado:** a confirmar em DP-12. Faixa de trabalho adotada provisoriamente: arquivos individuais de alguns megabytes a alguns gigabytes; dezenas a poucas centenas de arquivos por execucao; ate poucas dezenas de hosts consumidores do mesmo aplicativo registrado.

### Medicoes reais da camada de dominio (v0.4)

Obtidas pelo QA e pelo Tech Lead apos a correcao do defeito de complexidade quadratica. Substituem estimativa por dado e **calibram DP-12**, que segue aberta apenas quanto aos volumes de negocio.

| Grandeza | Medido | Leitura arquitetural |
|---|---|---|
| Vazao do `content_hash` | ~320 MB/s estavel | 100 GiB em ~5,4 min, contra ~2 h antes da correcao. **Remove o `content_hash` da lista de gargalos**: deixa de ser fator limitante mesmo em arquivos muito grandes, e viabiliza RF-33 sem penalidade proibitiva |
| Memoria do `content_hash` | Plana em ~8.000 KiB, **independente do tamanho do arquivo** | Confirma que o resumo opera em fluxo, bloco a bloco. Nao ha limite superior de tamanho imposto por memoria, o que era um risco em aberto para F-01 e F-02 |
| `lib/path` | Profundidade 5.000 em 0,88 s | Confinamento com resolucao fisica de symlinks nao e gargalo em arvores realistas |
| Redacao de erro | ~n^1.5 — 4 KiB em 0,02 s; 256 KiB em 4,56 s | Aceitavel para mensagens de erro reais, que sao pequenas; degrada em corpo de erro anomalo. Teto de entrada reduzido para 16 KiB no acabamento do ciclo, com pior caso de 0,10 s |
| Analise de JSON (`lib/json`) | Teto de entrada fixado em **256 KiB**; 4 MiB extrapolava para ~86 s | **Restricao de projeto, nao limitacao acidental.** Gera `RNF-23`: toda chamada de colecao envia `limit`/`max_results` explicito e pagina por cursor. Sem isso, pasta grande falharia por recusa de analise em vez de erro de servico ou paginacao — modo de falha confuso e diagnostico enganoso |

> **Consequencia para o plano de expansao:** o gargalo dominante permanece **externo** — limite de taxa da Dropbox e banda de rede —, nao interno a aplicacao. A lista de gargalos conhecidos abaixo permanece valida, com o `content_hash` rebaixado de gargalo a custo administravel.
- **Estrategia de escala:**

| Dimensao | Estrategia |
|---|---|
| Tamanho de arquivo | Selecao automatica entre requisicao unica (ate 150 MiB) e sessao em partes. 🔴 **CORRECAO DA v1.2 — a afirmacao anterior desta celula esta OBSOLETA e era, a partir de 2026-08-19, FALSA em relacao ao implementado.** Ela dizia *"Tamanho de parte configuravel, com teto de 150 MiB por requisicao; valor inicial sugerido entre 8 MiB e 32 MiB, ajustavel por medicao"*. **O implementado fixa a parte em 4.194.304 bytes, sem caminho de configuracao**, e a faixa de 8 a 32 MiB **nunca foi medida** — era estimativa de trabalho anterior a qualquer dado. **Razao da fixacao:** parte de rede e bloco do `content_hash` sao hoje a mesma grandeza, e diverge-las produziria um `content_hash` bem formado e errado (`DIV-19`). O roteamento por tamanho usa **157.286.400 bytes**. Se a parte configuravel volta a ser requisito e `DP-30`. **Correcao da v0.2 (RES-10, DIV-13):** o multiplo de 4.194.304 bytes e **obrigatorio apenas em sessao concorrente**, nao uma recomendacao geral de desempenho. Em sessao sequencial nao ha essa restricao |
| Quantidade de arquivos | Percurso incremental com listagem paginada por cursor, evitando materializar a arvore inteira em memoria |
| Volume agregado | Distribuicao temporal das rotinas entre hosts para nao concentrar chamadas na mesma janela; a cota da Dropbox e por aplicativo e por usuario |
| Concorrencia | **Padrao sequencial, valor `1`.** A documentacao registra que chamadas simultaneas de `list_folder` ou `list_folder/continue` para o mesmo usuario pelo mesmo aplicativo produzem erro de limite de taxa por construcao, e que a orientacao e aguardar as pendentes concluirem (RES-11). Portanto o paralelismo, se habilitado, deve ser limitado, configuravel e nunca aplicado a listagem do mesmo usuario (RNF-21, RSK-22) |
| Falha transitoria | Recuo exponencial com variacao aleatoria, respeitando `Retry-After`, com numero maximo de tentativas configuravel |

- **Gargalos conhecidos:**

| Gargalo | Natureza | Consequencia |
|---|---|---|
| Limite de taxa da Dropbox por aplicativo e por usuario | Externo, nao contornavel | Respostas `429`; e o teto real de escala do sistema. Agravado por concorrencia de listagem para o mesmo usuario (RES-11) |
| Banda de rede do host | Infraestrutura | Determina o tempo de janela das rotinas |
| Espaco livre na area temporaria | Infraestrutura | Limita o tamanho de parte utilizavel na sessao de envio |
| Custo de processo por operacao em shell | Arquitetural | Cada invocacao de utilitario externo cria um processo; percursos com muitos arquivos pequenos degradam de forma perceptivel |
| ~~Calculo de `content_hash`~~ | Processamento | ✅ **Rebaixado na v0.4 por medicao.** ~320 MB/s com memoria plana em ~8 MiB: 100 GiB em ~5,4 min. Deixa de ser gargalo e passa a custo administravel |
| Redacao de conteudo sensivel em mensagens grandes | Processamento | Complexidade ~n^1.5: 4 KiB em 0,02 s, 256 KiB em 4,56 s. Irrelevante em mensagens de erro reais; vigiar se corpos de erro grandes passarem a ser submetidos a redacao |
| Ausencia de interpretador JSON nativo | Arquitetural | Custo por resposta processada; agravado se a estrategia escolhida em DP-08 for propria em shell |

- **Plano de expansao:**

| Estagio | Gatilho observavel | Acao |
|---|---|---|
| Inicial | Operacao dentro do previsto | Execucao sequencial, tamanho de parte padrao, retentativa padrao |
| Ajuste fino | Janela de rotina se aproximando do limite aceitavel | ⚠️ **Indisponivel na v1.2.** A acao prevista era "elevar o tamanho de parte conforme espaco temporario disponivel; medir ganho real antes de fixar" — **e ela nao pode ser executada hoje**, porque a parte esta fixa em 4.194.304 bytes (`DIV-19`). Executa-la exige antes separar `parte de rede` de `bloco de resumo` e reabrir `DP-30`. **Registrado como indisponivel em vez de mantido como se fosse acionavel** |
| Distribuicao temporal | Incidencia recorrente de `429` | Escalonar horarios de execucao entre hosts e reduzir concorrencia |
| Segmentacao de aplicativo | `429` persistente mesmo com distribuicao temporal | Avaliar registro de aplicativos Dropbox distintos por dominio de uso, respeitando os termos da Dropbox |
| Revisao arquitetural | Volume incompativel com processo por invocacao em shell | Reavaliar a restricao RES-01 com o solicitante; e o limite estrutural da solucao |

> **Pendencia obrigatoria.** Esta secao deve ser reaberta apos os testes de exaustao do QA Expert, com os limites reais observados de tamanho de parte, taxa de `429`, tempo de rotina e consumo de area temporaria, conforme a responsabilidade do Business Analyst prevista no protocolo.

---

## Plano de dimensionamento e expansao do banco

> 🔴 **HANDOFF DO DBA ACIONADO NA v0.8.** O gatilho registrado nas versoes anteriores era exatamente este: promover `F-03`, `F-06`, `F-12` ou `F-14` reintroduz estado persistente. **`F-06` entrou por `DP-06`.** Esta secao deixa de ser nao aplicavel e passa a exigir o handoff formal previsto no item 24 do protocolo comum, usando `.claude/agents-protocol/templates/plano-dimensionamento-expansao-banco-template.md` — ainda que o mecanismo seja armazenamento em arquivo, e nao banco relacional.

> ✅ **v1.5 — HANDOFF DO DBA RECEBIDO E CONSOLIDADO (regra 26).** Os itens abaixo do bloco "Registro da v0.8" ficam como historico; o plano vigente e este.

- **Fonte do handoff do DBA:** [parecer do DBA — cache unico de `content_hash` em `lib/state` (fase 3)](../reviews/2026-10-18-2243-parecer-dba-cache-unico.md), aprovado com ressalvas; ressalvas bloqueantes atendidas por `RF-61(a)` e (b) e pela decisao do solicitante sobre `RF-52` (`DP-34`).
- **Natureza do dado (formato v2, `DBX_STATE_VERSAO=2` em `lib/state.sh`):** nao ha banco. Dois tipos de arquivo de campos terminados em NUL sob `$XDG_STATE_HOME/dbx`, nomeados pelo resumo da chave (nenhum texto de caminho no nome):
  - **`memoria-<resumo>`** (`sync`, uma por tripla conta + raiz local canonica + raiz remota): cabecalho de 4 campos — `2`, conta, origem, destino — seguido de um registro por caminho visitado, `content_hash<TAB>identidade<TAB>caminho_relativo` (caminho por ultimo, por aceitar qualquer byte exceto NUL).
  - **`upload-<resumo>`** (`upload`, um por origem canonica, sem conta): `2`, `upload`, caminho canonico e um unico registro `content_hash<TAB>identidade`.
  - **Identidade** (definicao unica em `lib/hash`, `DBX_HASH_FORMATO_IDENTIDADE`): saida de `stat -c '%Y|%y|%z|%d|%i|%s'` — `mtime` em segundos, `mtime` e `ctime` em texto com nanossegundos, dispositivo, inode e tamanho (`RF-38(e)`, `RF-61(b)`); comparada como cadeia.
  - Memoria de versao `1` (tamanho e `mtime` em segundos) e descartada na carga como versao desconhecida; o arquivo continua existindo, entao o par segue "visto" para `RF-48`; por isso a primeira execucao com memoria descartada nao propaga exclusao e sai com codigo diferente de `0` (`RF-41(f)`, `RSK-46`), regravando a memoria em v2. Corrupcao, cabecalho divergente ou campo invalido descartam e reconstroem (`RF-42`). Tamanho estimado pelo formato (nao medido na v2): cerca de 170 B de hash e identidade mais o caminho relativo, por caminho, na `memoria-*`; um bloco de disco por `upload-*`. Tudo descartavel e reconstruivel: perda custa so recalculo. *(Redacao anterior, que descrevia a `memoria-*` com "hash, tamanho, `mtime`, caminho", superada pela v2; divergencia apontada no [parecer de conformidade](../reviews/2026-10-18-2243-parecer-conformidade-cache-unico.md).)*
- **Premissas de crescimento:** `memoria-*` cresce com o numero de arquivos da raiz, **nao** com o historico, porque so as entradas visitadas sao regravadas (`RF-38(b)`); `upload-*` cresce com o numero de origens distintas e e podado acima de **10.000** arquivos, removendo os nao usados ha **90 dias** (`RF-61(i)`).
- **Medicoes do DBA (WSL2, bash):**

| Entradas no arquivo NUL | Tamanho | Carga para o mapa | Regravacao |
|---|---|---|---|
| 1 | 117 B | < 1 ms | < 1 ms |
| 1.000 | 105 KB | 16 ms | 3 ms |
| 10.000 | 1,06 MB | 174 ms | 38 ms |
| 50.000 | 5,3 MB | 913 ms | 233 ms |

- **Estrategia de capacidade:** indice desnecessario (array associativo em memoria, consulta O(1)); gravacao em lote unica por execucao; `upload` com custo constante abaixo de 5 ms por arquivo de um registro. **Gatilho de revisao:** raiz com mais de ~100 mil arquivos (carga ~2 s) — avaliar `mapfile -d ''` no lugar do laco `read` ou particionar a memoria do `sync` por subdiretorio de primeiro nivel.
- **Concorrencia:** `upload` x `upload` de origens diferentes nao disputa arquivo; da mesma origem, grava o mesmo valor; `upload` x `sync` usam namespaces diferentes; dois `sync` do mesmo par: ultimo `mv` vence, sem trava (`RNF-25(d)`).
- **Riscos de persistencia:** hash obsoleto reaproveitado (`RSK-42`), precisao de `stat` (`RSK-43`), legado `dbx.db*` esquecido (`RSK-44`), `upload` tocando a memoria do `sync` (`RSK-45`); a memoria do `sync` usa a mesma identidade forte (`RF-38(e)`, `DIV-26` resolvida).
- **Nao aplicavel:** replica, backup, sharding e monitoracao operacional — cache local por usuario, descartavel, sem servidor e sem telemetria no produto.

**Registro da v0.8 (historico):**

- **Fonte do handoff do DBA:** ⏳ **acionado, aguardando elaboracao.** O Business Analyst incorporara o plano a esta secao quando recebido.
- **Natureza do dado a dimensionar:** **linha de base de sincronizacao** — um registro por caminho rastreado, contendo ao menos `content_hash` (64 caracteres) e identificador de revisao remota, mais o caminho. Ordem de grandeza estimada: **algumas centenas de bytes por caminho**. Para 100 mil arquivos, dezenas de megabytes. Cresce **linearmente com a quantidade de caminhos sincronizados**, nao com o volume de dados transferidos.
- **Questoes que o plano do DBA precisa responder:** politica de crescimento e eventual compactacao; comportamento com centenas de milhares de caminhos em um interpretador em shell sem indice; custo de leitura integral a cada execucao contra leitura incremental; recuperacao de consistencia apos interrupcao, ja parcialmente coberta pela escrita atomica de `RNF-25`; e se o formato deve ser textual delimitado — coerente com a ausencia de dependencias de `DP-08` — ou outro.
- **Premissas de crescimento fora do `sync`:** para `upload`, `download`, `list`, `delete` e `info` a situacao anterior permanece — a persistencia se limita ao arquivo de configuracao (centenas de bytes, sem crescimento), cache de token **em memoria**, acumulador de relatorio **em memoria**, e area temporaria transitoria removida ao final.
- **Estrategia de capacidade:** nao aplicavel. O crescimento de dados relevante ocorre no lado da Dropbox, cuja capacidade e governada pelo plano contratado e nao pela aplicacao.
- **Riscos de persistencia:** limitados a permissao indevida no arquivo de credencial (RNF-04), residuo de arquivo temporario em interrupcao (RNF-05) e esgotamento de espaco na area temporaria durante envio em partes.
- **Acoes recomendadas:**
  1. **Acionar o DBA** para o plano de dimensionamento e expansao da linha de base, respondendo as questoes listadas acima.
  2. **Criterio de aceite arquitetural, atualizado:** a implementacao nao deve produzir escrita persistente **alem do delimitado em `RNF-26`** — linha de base e cursor de enumeracao, sob `lib/state`. Verificavel por auditoria dos caminhos de escrita. Para os demais comandos, o criterio anterior de ausencia total de residuo permanece.
  3. **Fechar `DP-23`** antes de implementar `lib/state`: localizacao da base (recomendacao: `$XDG_STATE_HOME` com recuo para `~/.local/state`, por ser **estado** e nao configuracao) e comportamento diante de base corrompida.

---

## Secao obrigatoria - Referencia ao Design System

- **Existe frontend ou interface relevante?:** **Nao.** A aplicacao e uma interface de linha de comando, sem componentes visuais, sem renderizacao web e sem interface grafica.
- **Documento de Design System referenciado:** nao aplicavel nesta versao. Nao existe Design System no projeto e nao ha handoff do UX Expert.
- **Responsavel UX:** nao designado.
- **Link ou referencia de Figma:** nao aplicavel.
- **Link ou referencia de Storybook.js:** nao aplicavel. Storybook.js pressupoe componentes de interface, inexistentes neste escopo.
- **Evidencias visuais disponiveis:** nao aplicavel.
- **Divergencias conhecidas entre System Design e Design System:** nenhuma, por inexistencia de Design System.
- **Plano de tratamento das divergencias:**
  1. Registrar formalmente a nao aplicabilidade, conforme exigencia de justificativa explicita de desvio do item 16 do protocolo comum.
  2. **Recomendacao do Business Analyst, com peso elevado na v0.2.** DP-03 confirmou que ha uso interativo por operador humano, e nao apenas automacao. Alem disso, RF-28 passou a exigir **duas apresentacoes de saida sobre o mesmo modelo de resultado**, o que e uma decisao de experiencia, nao apenas de formato. Recomenda-se acionar o UX Expert para definir um padrao de experiencia de linha de comando cobrindo: estrutura e tom do texto de ajuda; gramatica de comandos e opcoes; **especificacao das duas apresentacoes exigidas por RF-28 e do criterio de selecao entre elas**; redacao das mensagens de erro com acao corretiva; indicacao de progresso em operacoes longas, apenas quando houver terminal associado; e roteiro do assistente de configuracao, que agora precisa orientar tambem a concessao de escopos minimos (RNF-20). Esse padrao ocuparia, no ciclo de governanca, o lugar funcional que o Design System ocupa em fluxos com interface.
  3. Reabrir esta secao integralmente se DP-13 aprovar o shell interativo, que introduz estado de sessao, navegacao e afordancias proprias. Com uso interativo agora confirmado, DP-13 deixou de ser hipotetica.
  4. Enquanto esta secao permanecer como nao aplicavel, a validacao de frontend por `.claude/agents-protocol/templates/qa-validacao-frontend-template.md` tambem nao se aplica, e esse desvio deve ser justificado pelo QA Expert no registro de validacao.

---

## Criterios de aceite e rastreabilidade

- **Requisitos cobertos:** RF-01 a RF-30 e RNF-01 a RNF-19, especificados em [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md). Requisitos marcados como condicionais (RF-05, RF-06, RF-14, RF-24) permanecem fora do aceite ate a resposta das decisoes pendentes correspondentes.
- **Criterios de aceite por capacidade:**

| Capacidade | Criterio de aceite arquitetural |
|---|---|
| Autenticacao | Toda emissao, renovacao e revogacao de token ocorre exclusivamente em `lib/auth`; nenhum outro componente le ou escreve segredo; nenhum segredo aparece em `argv`, log ou variavel exportada |
| Acesso a rede | Nenhum componente fora de `lib/http` invoca o cliente HTTP; verificavel por analise estatica do repositorio |
| Contratos externos | Nenhuma referencia a `/2/files/search`, `/2/files/copy`, `/2/files/move`, `/2/files/delete` ou `/2/files/create_folder` sem sufixo `_v2` |
| Transferencia | Arquivo acima de 150 MB usa obrigatoriamente sessao em partes; toda transferencia concluida tem `content_hash` verificado; interrupcao nao deixa arquivo truncado no destino nem residuo temporario |
| Tratamento de erro | Cada classe HTTP mapeada possui verificacao dedicada, com mensagem e codigo de saida estaveis; `400` nunca sofre retentativa; `429` respeita `Retry-After` |
| Modularidade | Dependencia unidirecional das camadas; nenhum comando depende de outro comando; nenhuma unidade de `lib/` depende de `commands/` |
| Automacao | Execucao sem terminal associado nao bloqueia, nao emite sequencia de controle de terminal e assume saida estruturada parseavel; codigos de saida deterministicos entre execucoes |
| Duplo modo de uso | Nenhum comando emite texto diretamente; toda saida passa por `lib/output`. Ambas as apresentacoes sao exercitadas na suite por sobreposicao explicita do sinalizador |
| Menor privilegio | O conjunto de escopos OAuth solicitado esta documentado e limitado aos comandos habilitados; caminho remoto fora da raiz configurada e recusado antes de qualquer chamada de rede |
| Nao derivacao | Declaracao formal de que nenhum trecho de codigo, estrutura de funcoes, nome interno ou mensagem literal do `Dropbox-Uploader` foi incorporado (RES-02) |
| **Estado local delimitado** *(reescrito na v1.5; antes "Ausencia de estado local")* | Nenhuma escrita persistente fora do arquivo de configuracao e do diretorio de estado; neste, so `lib/state` escreve, e so `memoria-*` e `upload-*` (`RNF-26`). Nenhum artefato persistente decide: apagar o diretorio de estado nao muda nenhuma operacao decidida por `sync` ou `upload` (`RF-37`, `RF-60(f)`, `RSK-23`). Nenhuma invocacao de `sqlite3`/`python3` (`RNF-02`). Verificado por auditoria dos caminhos de escrita e por teste de residuo apos execucao completa e apos interrupcao por sinal. **Fase 2 (v1.9):** o arquivo de trava (`trava-*`, `RF-69`) entra como **estado transitorio que nao decide nada** (`RNF-26` emendado); existe so durante um `sync` ou `verificar` e e removido em todo caminho de saida |
| **Transferencia por fluxo** | Envio a partir da entrada padrao nao materializa o conteudo integral em disco, mantendo no maximo uma parte em buffer; recebimento para a saida padrao nao emite diagnostico na saida padrao (RF-31, RF-32). 🔴 **Qualificado na v1.2 (`DIV-18`):** o criterio "interrupcao nao deixa arquivo truncado no destino" vale para **falha de leitura**, verificavel e verificada. **NAO vale para produtor de cano anonimo que morre depois de escrever um prefixo** — caso **indistinguivel de fim de fluxo legitimo dentro do processo**, sem mitigacao interna, medido e registrado em `RSK-36`. Um aceite que declare este criterio integralmente cumprido estaria declarando o que nao foi verificado, porque **nao e verificavel** |
| **Integridade e omissao** | O `content_hash` calculado localmente coincide com o vetor de teste oficial e com o retornado pela API em arquivos de tamanhos limitrofes; a omissao por conteudo identico nunca se baseia em nome, tamanho ou data (RF-33, RF-34) |
| Qualidade | Analise estatica sem alerta nao suprimido; suite automatizada aprovada sem rede e sem credencial real |
| Conformidade legal | Arquivo de licenca presente e coerente com a decisao registrada em DP-01 |

- **Evidencias de validacao esperadas:** relatorio de analise estatica; relatorio de execucao da suite automatizada; evidencia de auditoria de endpoints; evidencia de inspecao da tabela de processos durante comando autenticado; evidencia de verificacao de `content_hash` em envio e recebimento; matriz de codigos de saida verificada por classe de erro; relatorio de teste de exaustao com os limites observados de tamanho de parte, taxa de `429` e duracao de rotina.
- **Dependencias de QA, UX e DBA:**

| Papel | Dependencia | Situacao |
|---|---|---|
| QA Expert | Validacao independente da implementacao; testes de exaustao alimentando a secao de dimensionamento; justificativa formal do desvio de Cypress e do desvio do template de validacao de frontend | Aplicavel |
| UX Expert | Design System no formato padrao | **Nao aplicavel.** Recomendado, com peso elevado apos DP-03, um padrao de experiencia de linha de comando que especifique as duas apresentacoes exigidas por RF-28 |
| DBA | Plano de dimensionamento e expansao do banco | ✅ **Recebido na v1.5** ([parecer](../reviews/2026-10-18-2243-parecer-dba-cache-unico.md)) e consolidado na secao propria. *Redacao anterior, superada por `DP-06`:* nao aplicavel por ora |
| Senior Developer | Confirmacao dos contratos nao verificados em DIV-14 antes da implementacao | **Aplicavel** |
| Tech Lead | Aprovacao final por `.claude/agents-protocol/templates/aprovacao-final-tech-lead-template.md`, incluindo a declaracao de nao derivacao; decisao sobre a contaminacao da memoria de projeto (DIV-09) | Aplicavel |
| Solicitante | Resposta a DP-02 (quais funcionalidades novas); aprovacao explicita dos testes de QA | **Bloqueante** |

---

### Integridade de dados no recebimento e no `sync` (P1, 2026-10-18)

Decisoes do solicitante (`DP-31`), sem novo componente:

- **`lib/sync`**: a chave de comparacao dos mapas local/remoto e o caminho em minusculas (`path_lower` no remoto); a grafia original e mantida so para exibicao e escrita. Colisao de caixa na arvore local e detectada na fase de planejamento e recusada antes de qualquer escrita (`RF-54`).
- **Recebimento (`commands/download`, `commands/sync --receber`)**: escrita em temporario no mesmo diretorio do alvo (mesmo sistema de arquivos, para a renomeacao ser atomica), conferencia de `content_hash` e `mv` atomico; falha descarta o temporario e preserva o alvo (`RF-55`). `download` de pasta recusa destino que seja arquivo regular (`RF-56`).
- **Envio (`sync --enviar`)**: reutiliza o helper de publicacao e o roteamento por tamanho do `upload` (requisicao unica ate 150 MiB, sessao acima), com `client_modified`; sobrescreve em modo `update` com o `rev` da listagem da execucao e usa `add` para arquivo novo; recusa da Dropbox vira falha do item, sem sobrescrever (`RF-57`, `RF-49`); a origem vence entre execucoes (`DP-27`; `DIV-23` resolvida).
- **`lib/http`**: `umask 077` restrito a criacao da area temporaria com o token; `umask` do processo preservado; area temporaria de cada requisicao removida sempre, inclusive na reemissao diagnostica, sem gancho armado apos o retorno (`RNF-29`; `RNF-04` emendado, `DIV-24` resolvida). Na fase 2 (v1.10) a gestao de areas passou a `lib/tmp`, registro unico com um tratador por sinal.
- **Fora da P1 (registrado, nao implementado)**: skip do upload condicionado ao `content_hash` remoto, com o cache de `lib/db`/`lib/state` reduzido a otimizacao de calculo de hash (`DP-32`, `F-26`); politica `Retry-After` de `lib/http` (`DIV-22`, tratada na fase P2; ver secao seguinte).

### Robustez de rede (P2, 2026-10-18)

- **`lib/http`, timeouts (`RNF-30`)**: toda requisicao leva `--connect-timeout` (padrao 15 s) e corte por velocidade minima (`--speed-limit` 1024 B/s por `--speed-time` 60 s), ajustaveis por `DBX_HTTP_CONNECT_TIMEOUT_S`, `DBX_HTTP_VELOCIDADE_MINIMA_BPS` e `DBX_HTTP_VELOCIDADE_JANELA_S`; valor invalido e recusado como uso invalido (codigo `2`) antes da rede. Timeout (`cURL` 28) e falha transitoria de rede.
- **`lib/http`, retentativa (`RNF-07`)**: `DBX_HTTP_TENTATIVAS_MAXIMAS` deixa de ser constante e passa a ser configuravel (padrao 5); `DBX_HTTP_ESPERA_BASE_MS` passa de 250 para 1000 ms; novos `DBX_HTTP_ESPERA_TETO_MS` (60000) e `DBX_HTTP_RETRY_AFTER_TETO_S` (300). O `Retry-After` e lido do cabecalho de resposta (mesmo ponto de captura do identificador de correlacao) e substitui o recuo calculado. A tabela de semantica de erro acima continua valida para `429` e `5xx`.
- **`lib/transfer`, retomada (`RF-58`)**: diante de `incorrect_offset`, so para arquivo regular, o laco de sessao relê a partir do `correct_offset` validado em `[0, min(tamanho, bytes ja enviados)]`; sessao e deslocamento ficam na memoria do processo. A entrada padrao nao retoma. `F-03` segue fora.
- **`commands/sync` e `lib/output` (`RF-59`)**: cada item falho emite `falha <caminho>: <classe> <resumo>` no stderr; o `--json` mantem `falhas` (contagem) e ganha o par `falha_caminho`/`falha_classe` por item. Sem segredo nem corpo bruto.
- **Sinais e suite (`RNF-31`, `RNF-32`)**: a area `dbx-sync.*` e removida em `EXIT`, `INT`, `TERM` e `HUP` pelo tratador unico de `lib/tmp` (v1.10, `F-31`; saida `14` em sinal); `tests/run.sh` para no primeiro erro; mapa de modulos em `docs/testes/mapa-modulos.md`.

### Aliases e localidade (fase 4, 2026-10-19)

Decisoes do solicitante e do Tech Lead (`DP-35`); nenhum componente novo, so contrato de borda e ambiente de execucao.

- **Aliases em ingles (`RF-64`)**: cada comando (`commands/sync`, `commands/unlink`, `commands/config`) reconhece os dois nomes de uma opcao **no mesmo ramo do analisador de argumentos**, de modo que alias e nome em portugues sao a mesma opcao por construcao — mesmo efeito, mesmas recusas e a mesma regra de repeticao (ultimo valor vence nas opcoes com valor; opcao sem valor idempotente; segundo sentido de `--enviar`/`--receber` recusado). Um alias tratado em ramo separado e o desenho que o `TC-ALI-01..03` existe para reprovar. A ajuda em `bin/dbx` lista os dois nomes. Pares: `sync` (`--origem`/`--source`, `--destino`/`--dest`, `--enviar`/`--push`, `--receber`/`--pull`, `--espelhar`/`--mirror`, `--confirmar`/`--yes`, `--permitir-origem-vazia`/`--allow-empty-source`), `unlink` (`--confirmar`/`--yes`, `--manter-aplicativo`/`--keep-app`) e `config` (`--substituir`/`--replace`, `--raiz`/`--root`).
- **Localidade da comparacao sem caixa (`RF-54(e)(f)`, `F-32`)**: `C.UTF-8` e fixada **somente dentro de `_dbx_sync_chave`** (`lib/sync`, unico ponto da chave), **nunca no processo**, quando a localidade existe; a fixacao local vale sobre `LC_ALL` do ambiente e nenhuma contagem em bytes muda fora dela (`DIV-32`). Sem a localidade, a comparacao vale so no ASCII e o `sync` (so ele) emite um aviso em stderr, uma vez por execucao, sem recusar e sem alterar codigo de saida nem saida padrao.
- **`commands/sync`, guarda de origem vazia (`RF-41(b)`, `O-1`)**: a recusa acontece **depois** do plano e antes de qualquer escrita, nos dois sentidos, e o plano traz `recusada=origem vazia`; a guarda anterior ao plano, que citava a memoria, sai. Sem `--espelhar`, origem vazia e operacao vazia com saida `0`; raiz inexistente segue recusada (`DIV-30`). A simulacao segue anunciando `recusaria=origem vazia` com codigo `0`.
- **Fora desta fase**: poda das skills fora da stack e enxugamento de comentarios em `lib/http` e `lib/transfer` nao alteram arquitetura; o historico vai para `docs/registros`.

### Trava de concorrencia e area temporaria unica (fase 2, 2026-10-19; implementada)

Decisao do solicitante (`DP-36`, memoria `2026-10-19-1419-trava-de-concorrencia`); requisitos `RF-69` a `RF-71`, `RNF-35`, `RNF-36`. Componentes: **`lib/tmp`** (registro unico de areas e de acoes de limpeza; ver a linha do componente), **`lib/state`** (cria e remove o arquivo de trava no diretorio de estado, `DIV-41`, decidido) e `commands/sync` e `commands/verificar`, que passam a usar a **mesma** funcao de abertura e de encerramento (`RNF-36`).

- **Onde entra no ciclo do `sync` e do `verificar`:** depois da validacao de argumentos e das recusas de caminho (que nao escrevem nem leem memoria) e **antes** de qualquer leitura de memoria, escrita ou area de dados. Sai em todo caminho: termino normal, falha, recusa por guarda, `INT`, `TERM`, `HUP`.
- **Chave:** conta x origem canonica x destino, **sem ordem entre os sentidos** (`RF-69(a)`, `DIV-38`); a parte "conta" e um **resumo local da credencial** (`cred-` mais 32 hex de `APP_KEY` e `REFRESH_TOKEN`; `DIV-47`), nao o `account_id`, que exigiria rede e quebraria `RF-69(d)`, `RF-65(b)` e `RF-65(c)`; duas credenciais da mesma conta no mesmo diretorio de estado nao se excluem (`RSK-50`); sem credencial, marcador `sem-conta`. Arquivo `trava-<resumo>`, `0600`, no diretorio de estado `0700`. Conteudo: pid, host, inicio e comando; **nunca** segredo.
- **Aquisicao:** gravar em temporario do mesmo diretorio e publicar por operacao atomica que falha se o destino existe, de modo que ninguem ve trava vazia ou parcial e so um processo vence a corrida.
- **Ocupada:** recusa imediata (`conflito`/`7`, proposta), com pid, host e inicio; com `--esperar N`, sondagem de 1 s ate N s. **Orfa** (mesmo host, pid sem processo): retomada com aviso, tambem de forma exclusiva. **Outro host ou ilegivel:** nunca retomada; o `diagnostico` mostra e diz o remedio (`RF-71`).
- **Handoff do DBA incorporado** ([parecer](../reviews/2026-10-19-1419-parecer-dba-trava.md), regra 26; aprovado com condicoes; sem migracao, `DBX_STATE_VERSAO` nao muda): criacao por `mktemp` em `.trava.*` mais `ln`, com sucesso aferido pelo mesmo inode (`-ef`) e recusa de trava que seja diretorio ou ligacao simbolica; conteudo em linha unica (`dbx-trava`, versao 1, pid, `host_id`, inicio, comando, `fim`; ate 512 bytes) lido sem `source`, `eval` nem `read` sem limite, e qualquer falha de validacao e trava **ilegivel**, nunca retomada nem apagada; `host_id` = nome do host (`$HOSTNAME`, recuo `/proc/sys/kernel/hostname`) + `boot_id` + namespace de pid; `unlink` recusa com `7` diante de trava viva e mantem as nao vivas, com aviso; retomada de orfa serializada por `trava-*.r`; ordem **trava, leitura de `memoria-*`, `mv`, liberacao**; `.trava.*` varrido apos 1 dia como `.memoria.*` e `.upload.*`; poda por idade nunca atinge trava; NFS como melhor esforco, com aviso no `diagnostico` (`RSK-49`); `ln` entra na lista do preflight (`RNF-34(g)`). Requisitos: `RF-69(j)` a `(q)`, `TC-TRV-21..36`.
- **Liberacao:** `lib/state` cria a trava e registra em `lib/tmp` a acao de liberar **dentro da mesma secao critica** (sinais retidos), sem janela entre criar e registrar; a acao roda no tratador unico de `EXIT`, `INT`, `TERM` e `HUP`, **antes** da remocao das areas (acoes primeiro, em ordem inversa; depois areas), e confere o dono (pid e inicio) antes de apagar. A trava nao e uma area: so a acao a libera.
- **Ordem em `lib/state` (RF-69(n)):** **trava, leitura de `memoria-*`, gravacao atomica (`mktemp` mais `mv`), liberacao**. A gravacao atomica usa `dbx_tmp_arquivo` no diretorio de estado e `dbx_tmp_esquecer` depois do `mv`; a liberacao so ocorre depois do `mv`.
- **Diretorio de estado alheio ou sem escrita (`DIV-48`):** a execucao segue **sem trava**, com uma linha de aviso em stderr; nao recusa (coerente com `TC-EST-04`).
- **`download` de pasta (`DIV-49`):** executa um `sync --receber` por dentro (`commands/download`) e por isso passa pelo mesmo ciclo e pega a trava do par; `download` de arquivo e os demais comandos avulsos nao travam.
- **Ciclo unico (`RNF-36`, `C-1`):** `dbx_cmd_ciclo_iniciar` (`lib/cmd`) executa, nesta ordem, resumo local da credencial, trava, area temporaria `sync`; `sync` e `verificar` nao tem codigo gemeo.

```mermaid
sequenceDiagram
  autonumber
  participant C as commands/sync ou verificar
  participant T as lib/tmp
  participant S as lib/state
  participant D as diretorio de estado
  C->>C: valida argumentos e caminho (2 ou 13 saem sem travar)
  C->>S: adquirir trava (chave, esperar N)
  S->>T: arma o tratador unico (EXIT, INT, TERM, HUP), uma vez por processo
  S->>D: secao critica: grava temporario, publica de forma exclusiva e registra a liberacao
  alt publicada
    S-->>C: adquirida
    C->>T: registrar a area temporaria (secao critica)
    C->>C: le memoria, planeja, executa
  else ocupada
    S->>D: le pid, host, inicio
    alt mesmo host e pid morto
      S->>D: retoma de forma exclusiva e avisa
      S-->>C: adquirida
    else pid vivo, outro host ou ilegivel
      S-->>C: ocupada (espera ate N s, sondando a cada 1 s)
      C-->>C: recusa com conflito/7, nada lido nem escrito
    end
  end
  Note over C,T: termino normal, falha ou sinal
  T->>S: acoes em ordem inversa: libera a propria trava (confere o dono)
  T->>T: depois remove as areas, em ordem inversa (sinal na limpeza nao a interrompe; sinal sai com 14)
```

> **Leitura do diagrama.** A trava e adquirida depois do tratador e antes de tudo o que le ou escreve, e a liberacao e uma acao do mesmo registro das areas: um sinal em qualquer ponto cai no mesmo caminho de saida. O tratador e armado na primeira aquisicao, pois e a trava quem registra a primeira acao. `SIGKILL` nao e capturavel e deixa a trava orfa, que o proximo processo do mesmo host retoma. **Decidido pelo Tech Lead:** `DIV-38` (chave sem ordem de sentido), `DIV-39` (a trava e a unica escrita permitida na simulacao e no `verificar`; o diretorio de estado termina byte a byte igual, e se a trava teve de cria-lo a liberacao o remove, vazio), `DIV-41` (`lib/state` escreve), `DIV-43` (classe `7`) e `DIV-44` (`unlink` recusa com `7` se ha trava viva no mesmo host). O parecer do DBA sai em `docs/reviews/`.

### Estado local unico (fase 3, 2026-10-18)

Decisoes do solicitante (`DP-34`) e recomendacoes do DBA aceitas pelo Tech Lead; um componente sai (`lib/db`), nenhum entra.

- **`lib/state`, cache unico**: unico cache de `content_hash`, com os namespaces `memoria-*` (`sync`) e `upload-*` (`upload`), detalhados na tabela de componentes e no diagrama "Estado local: componentes". O `sync` deixa de consultar e gravar um segundo nivel em `lib/db`.
- **`commands/upload`, dispensa do envio (`RF-60`)**: `get_metadata` no destino; remoto ausente envia sem calcular o hash para comparar; remoto arquivo com hash igual dispensa; diferente envia conforme o modo; falha da consulta envia; pasta remota mantem a colisao atual; `--forcar` e entrada padrao nao consultam. O cache entra **so** para obter o hash local sem reler o arquivo, e so com identidade forte (`RF-61(b)` a (d)).
- **Chave canonica (`RF-62`)**: caminho fisico absoluto com ligacoes resolvidas para a origem do `upload` e para a raiz local do `sync`; o texto do caminho nunca entra no nome do arquivo de cache e o caminho canonizado nunca entra em decisao.
- **`lib/auth` (`RF-63`)**: `client_secret` obrigatorio; o ramo sem segredo sai; PKCE fora (`F-35`).
- **`lib/sync` e `commands/sync`, guardas de exclusao do `--espelhar`**: a guarda de origem vazia deixa de depender da linha de base — origem vazia (raiz local no `--enviar`, listagem remota no `--receber`) com algo a apagar e recusada sem escrita, codigo `14`, e so `--permitir-origem-vazia` a dispensa (`RF-41(b)`, `RF-53(e)`; decisao do solicitante apos `QA-P3-05..07`). Para origem parcial, a exclusao fica desabilitada na execucao quando a conta nao e identificada (`RF-41(e)`) ou quando a memoria existente e descartada ou ilegivel (`RF-41(f)`), com regravacao em v2 so apos travessia completa. A memoria deixou de ser defesa contra exclusao em massa: a recusa olha o que seria apagado agora.
- **Fora desta fase**: paralelismo limitado e APIs em lote (`F-34`, com medicao previa). **Resolvidas pelo Tech Lead em 2026-10-18**: `DIV-26` (identidade forte tambem no `sync`, `RF-38(e)`), `DIV-27` (sem skip com `--rev`, `RF-60(i)`), `DIV-28` (sem conta, a propagacao de exclusao fica desabilitada na execucao, como em `RF-41(a)`; `--confirmar` nao reabilita; saida diferente de `0`; efeito descrito na ajuda e no `README` — `RF-41(e)`; revisao da decisao anterior "pede reconhecimento"), `DIV-29` (diretorio do usuario corrigido para `0700`, de outro dono recusado como `permissao`, `RNF-25(b1)`).

## Decisoes e trade-offs

| Decisao | Alternativas consideradas | Justificativa | Impacto |
|---|---|---|---|
| Arquitetura modular com camadas e dependencia unidirecional | (a) Arquivo unico monolitico, como o modelo de referencia; (b) modular | O monolito de 1834 linhas do modelo impede teste por unidade, dificulta auditoria de seguranca no ponto onde os segredos circulam e concentra risco de regressao. A modularizacao e a condicao para satisfazer RNF-13, RNF-14 e RNF-16 | Mais arquivos e um mecanismo de carregamento; empacotamento em arquivo unico, se exigido por DP-14, passa a demandar uma etapa de composicao |
| Ponto unico de saida de rede em `lib/http` | (a) Cada comando invoca o cliente HTTP; (b) ponto unico | Concentra autenticacao, retentativa, mapeamento de erro e filtro de segredo em um lugar auditavel; permite substituir a rede por duplo de teste sem alterar comandos | Todos os comandos dependem de um componente critico; exige cobertura de teste rigorosa nesse ponto |
| Segredo nunca em `argv` | (a) Padrao do modelo, credencial como argumento do cliente HTTP; (b) entrada por `stdin` ou arquivo de configuracao do cliente | O padrao do modelo expoe app secret e refresh token a qualquer usuario local do host (DIV-03, RSK-03); inaceitavel em servidor multiusuario | Codigo de transporte mais elaborado; ganho direto de seguranca verificavel por teste |
| Uso exclusivo de endpoints vigentes | (a) Paridade com o modelo; (b) apenas endpoints vigentes | O modelo referencia endpoint ja retirado, cujo comando correspondente esta quebrado, e quatro endpoints depreciados (DIV-01, DIV-02) | Ligeira divergencia de formato de resposta em relacao ao modelo; elimina defeito herdado |
| Verificacao de integridade por `content_hash` | (a) Confiar no codigo HTTP de sucesso; (b) comparar tamanho; (c) verificar `content_hash` | Unica forma de detectar corrupcao ponta a ponta e de habilitar deduplicacao futura sem reenvio | Custo de leitura integral e de resumo por blocos; relevante em arquivos muito grandes |
| Estrategia de interpretacao de JSON | (a) Expressao regular, como o modelo; (b) exigir `jq`; (c) `jq` com recuo para implementacao propria | **Decisao adiada para DP-08.** A opcao do modelo e demonstradamente fragil (DIV-04); a escolha entre as demais depende da politica de dependencias do solicitante | Bloqueia o desenho final de `lib/json`; nao bloqueia as demais camadas, pois o contrato interno do componente ja esta definido |
| Escopo do MVP | (a) Paridade completa com o modelo; (b) subconjunto essencial | **Decisao adiada para DP-06.** Paridade sem necessidade declarada infla escopo (RSK-15) | Determina o volume da primeira entrega |
| **Camada de saida com duas apresentacoes** *(v0.2)* | (a) Uma saida so, para humano; (b) uma saida so, estruturada; (c) duas apresentacoes sobre um modelo de resultado unico | DP-03 confirmou uso interativo **e** automatizado. Uma saida unica penaliza um dos dois publicos: texto decorativo quebra scripts, e saida estruturada pura degrada o uso interativo. A alternativa de manter dois caminhos de impressao independentes diverge com o tempo | Todos os comandos passam a devolver resultado estruturado em vez de imprimir. Custo de disciplina no inicio, verificavel por analise estatica; sem isso, a segunda apresentacao nunca fica consistente |
| **Confinamento de raiz remota na aplicacao** *(v0.2)* | (a) Confiar no confinamento da plataforma; (b) validar a raiz permitida na aplicacao | DP-04 fixou acesso amplo, o que **remove** o confinamento que a opcao de pasta do aplicativo daria. Sem controle proprio, uma rotina automatizada com caminho mal formado alcanca qualquer area da conta (RSK-19) | `lib/path` ganha responsabilidade de dominio: recusar caminho fora da raiz **antes** de qualquer chamada de rede. Custo baixo, reducao direta do raio de dano |
| **Ordem de precedencia entre deteccao de contexto e sinalizador explicito** *(v0.2)* | (a) Deteccao de terminal sempre decide; (b) sinalizador explicito sempre prevalece | Sem a sobreposicao explicita, o caminho de saida para humano fica impossivel de exercitar em teste automatizado, que roda sem terminal associado — e justamente o caminho menos testado seria o mais visivel ao usuario | O sinalizador prevalece nos dois sentidos. Permite cobrir ambas as apresentacoes na suite (RNF-19) |
| **Sessao em partes obrigatoria para transferencia por fluxo** *(v0.3)* | (a) Bufferizar o fluxo inteiro em disco e decidir depois entre requisicao unica e sessao; (b) usar sessao sempre | Bufferizar o fluxo inteiro anula o proposito de F-01, que existe justamente para nao exigir espaco em disco equivalente ao conteudo. A sessao aceita conteudo de tamanho desconhecido e admite conteudo pequeno sem prejuizo | Toda transferencia por fluxo emite ao menos `start` e `finish`, mesmo para poucos bytes — custo de duas chamadas extras em troca da remocao de uma restricao dura de infraestrutura |
| **Ausencia deliberada de estado local persistente** *(v0.3)* — 🔴 **REVOGADA (registro historico):** revogada para o `sync` por `DP-06` (v0.8) e `DP-27b`, e superada pelo cache unico de `lib/state` (`RF-38`, `RF-61`, `RNF-26`); vale so como registro historico, fora do `sync` e do `upload` (ver "Invariante da v0.3"). Texto original preservado abaixo | (a) Introduzir cache de resumos e cursores desde o inicio, antecipando funcionalidades futuras; (b) nao persistir nada alem da credencial | O escopo aprovado nao exige persistencia. Antecipa-la introduziria consistencia a recuperar apos interrupcao, migracao de formato e crescimento a dimensionar — custo real, em troca de beneficio hipotetico. A decisao mantem a secao de banco formalmente nao aplicavel | Cada execucao consulta os metadados remotos de que precisa. Custo: chamadas repetidas entre execucoes que um cache evitaria. Aceito conscientemente; e o gatilho de reabertura se DP-12 revelar volumes que tornem esse custo relevante |
| **Omissao por conteudo, nao por metadados** *(v0.3)* | (a) Comparar nome, tamanho e data, como o modelo; (b) comparar `content_hash` | Comparacao por metadados erra nos dois sentidos: ignora arquivo alterado que manteve tamanho e data (perda de dado) e retransmite arquivo identico cuja data mudou (desperdicio). A comparacao por conteudo e exata | Exige leitura integral e resumo do arquivo local. Custo de processamento em troca de correcao e de reducao de banda. Relevante em arquivos muito grandes, onde o resumo local pode custar mais que o envio em rede rapida — mitigado pelo sinalizador de forcar transferencia |
| **Cache unico de `content_hash` em `lib/state`; `lib/db` removido** *(v1.5, `DP-34`)* | (a) Manter os dois caches (`lib/state` + `lib/db`); (b) so `lib/db` (SQLite); (c) so `lib/state` (arquivo NUL) | (a) duplicava o mesmo dado com chaves diferentes e custava 100–200 s de processos em 10 mil arquivos; (b) traz `sqlite3`/`python3`, contra `RNF-02`, e estado fora de `RNF-26`; (c) nao tem dependencia, ja era o estado autorizado e mede ~0,2 s em 10 mil entradas | Remove um componente e uma dependencia; o `upload` ganha namespace proprio; o `dbx.db*` legado fica inerte e documentado, sem migracao (`RNF-33`) |
| **Cache do `upload` sem vinculo a conta** *(v1.5, `DP-34`)* | (a) Vincular a conta, com `get_current_account` por `upload`; (b) emendar `RF-52`: vinculo so para memoria com dado derivado do remoto; (c) persistir o `account_id` na credencial | O registro so guarda dado local; a protecao entre contas vem do hash remoto da conta corrente (`RF-60`). (a) custa uma requisicao por `upload`; (c) muda o formato da credencial | Sem requisicao extra; `RF-52(b)` registra a razao; o `unlink` continua apagando tudo |
| **Identidade forte do arquivo no cache do `upload`** *(v1.5)* | (a) Tamanho e `mtime` em segundos, como antes; (b) tamanho, `mtime`/`ctime` em ns, dispositivo, inode, `stat` antes e depois e regra anti-corrida de 2 s | Com (a), reescrita no mesmo segundo e mesmo tamanho reaproveita hash obsoleto e, contra um remoto com o conteudo antigo, dispensa envio necessario (`RSK-42`) | Custo de um `stat` extra por arquivo; *(decisao do Tech Lead, `DIV-26`)* a memoria do `sync` adota tambem (b) (`RF-38(e)`) |
| **`client_secret` obrigatorio, sem PKCE** *(v1.5, `DP-34`)* | (a) PKCE S256 sem segredo; (b) segredo obrigatorio em todo caminho | O `config` ja exigia o segredo; o ramo sem segredo da biblioteca era caminho morto e nao testado. PKCE fica como alternativa futura (`F-35`) | Um unico fluxo de autenticacao; `RNF-03` intacto |
| Ausencia de processo residente | (a) Daemon com estado; (b) execucao por invocacao | Execucao por invocacao e compativel com agendadores, containers efemeros e ambientes headless, e elimina a superficie de um servico em execucao continua | Sem deteccao de mudanca em tempo real, exceto pelo comando de monitoramento condicional |

---

## Riscos e mitigacoes

Detalhamento completo em [riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md). Sintese dos riscos com impacto arquitetural:

| Risco | Impacto | Probabilidade | Mitigacao | Owner |
|---|---|---|---|---|
| ✅ Obrigacao copyleft GPLv3 por derivacao de codigo (RSK-01) | Alto | **Baixa** — mitigado por DP-01 | Reimplementacao independente. Risco residual de disciplina, endereçado por RES-02 e pela declaracao formal de nao derivacao no fechamento | Senior Developer, verificado pelo Tech Lead |
| **Escopo funcional indefinido apesar da premissa de valor resolvida (RSK-20)** | Alto | Alta ate DP-02 ser fechada | Proposta de 22 candidatas com valor, esforco e dependencias, em folha de resposta. Recomendacao de fixar de quatro a seis no primeiro ciclo | Solicitante |
| **Raio de exposicao ampliado pelo acesso a Dropbox inteira (RSK-19)** | Alto | Media | RNF-20: escopos minimos, confinamento de raiz em `lib/path` e confirmacao obrigatoria em operacao destrutiva. DP-11 ganha peso: o refresh token e o unico controle entre um usuario local e a conta inteira | Solicitante e Senior Developer |
| **Contrato nao confirmado tratado como certo (RSK-21)** | Medio | Media | DIV-14: confirmar `content_hash`, cabecalho de correlacao e escopos de quatro endpoints em `developers.dropbox.com` antes de implementar. `lib/hash` e load-bearing | Senior Developer |
| **Paralelismo elevando incidencia de limite de taxa (RSK-22)** | Medio | Alta se F-09 for confirmada sem cuidado | RNF-21: padrao sequencial, sem chamadas simultaneas de listagem para o mesmo usuario (RES-11). Retentativa cega agrava | Senior Developer |
| Vazamento de credencial pela tabela de processos (RSK-03) | Alto | Alta se o padrao do modelo for replicado | `lib/auth` e `lib/http` como unicos manipuladores de segredo; proibicao de segredo em `argv`; teste de inspecao de processo | Senior Developer |
| Uso de endpoint retirado ou depreciado (RSK-04) | Alto | Alta se o modelo for copiado | Tabela unica de endpoints em `lib/http`; auditoria estatica como criterio de aceite | Senior Developer |
| Defeito silencioso de interpretacao de resposta (RSK-05) | Alto | Media | Decisao em DP-08; contrato de `lib/json` com testes de JSON adversarial | Senior Developer |
| Corrupcao de arquivo em envio interrompido (RSK-06) | Alto | Media | Sessao em partes com retentativa por parte, verificacao de `content_hash` e limpeza por `trap` | Senior Developer |
| Bloqueio por limite de taxa (RSK-07) | Medio | Media | Recuo exponencial com `Retry-After`; distribuicao temporal entre hosts; plano de expansao | Senior Developer |
| Divergencia entre utilitarios GNU e BSD (RSK-09) | Medio | Media se macOS/BSD entrarem no escopo | DP-07; camada de compatibilidade isolando chamadas de sistema; matriz de teste por plataforma | Senior Developer |
| Corrupcao de nomes com caracteres especiais (RSK-10) | Medio | Media | `lib/path` como componente de dominio testavel; conjunto de nomes adversariais na suite | Senior Developer |
| Manutencao de codigo shell extenso (RSK-14) | Medio | Alta sem modularizacao | RNF-13, RNF-14 e RNF-16 como criterio de aceite arquitetural | Tech Lead |
| ✅ Skip do `upload` decidido so pelo cache (RSK-37) *(v1.5)* | Alto | Encerrado pela fase 3 | `RF-60`: dispensa so com hash remoto igual; evidencia do QA em `TC-SKP` | Tech Lead |
| Hash local obsoleto reaproveitado (RSK-42) *(v1.5)* | Alto | Baixa | Identidade forte de `RF-61(b)` a (d) no `upload` e de `RF-38(e)` no `sync` | Senior Developer |
| Precisao de `stat` no coreutils minimo (RSK-43) *(v1.5)* | Medio | Media | Teste no ambiente minimo; recuo textual; sem precisao, nao grava cache | Senior Developer |
| `upload` tocando a memoria do `sync` (RSK-45) *(v1.5)* | Alto | Baixa | Namespace `upload-*`; teste de que o `upload` nao cria `memoria-*` | Senior Developer, QA |

---

## Diagramas Mermaid

### Contexto (C4 nivel 1)

```mermaid
flowchart TD
  ADM[Administrador de sistemas]
  AUT[Agendador cron ou pipeline de CI]
  DEV[Script de terceiros]

  SYS[Aplicacao CLI de integracao com Dropbox<br/>shell script + cURL]

  DBX[(Dropbox API v2<br/>arquivos, compartilhamento, conta)]
  OAU[(Dropbox OAuth2<br/>emissao e renovacao de token)]
  FS[(Sistema de arquivos local)]
  CFG[(Configuracao e credencial do usuario)]

  ADM --> SYS
  AUT --> SYS
  DEV --> SYS

  SYS -->|HTTPS| DBX
  SYS -->|HTTPS| OAU
  SYS -->|leitura e escrita| FS
  SYS -->|leitura restrita 0600| CFG
```

### Containers e componentes (C4 niveis 2 e 3)

```mermaid
flowchart TD
  subgraph ENTRADA[Entrada]
    BIN[bin/dbx<br/>ponto de entrada e despacho]
    PRE[lib/preflight<br/>versao de shell e dependencias]
    CLIP[lib/cli<br/>opcoes, ajuda, simulacao]
  end

  subgraph CASOS[Casos de uso - commands]
    CFGC[config e unlink]
    UPC[upload]
    DLC[download]
    LSC[list e stat]
    FSC[mkdir, move, copy, delete]
    SRC[search e share]
    ACC[account e space]
  end

  subgraph ORQ[Orquestracao - v0.4]
    TRF[lib/transfer<br/>partes, retentativa,<br/>omissao por conteudo identico]
    WALK[lib/walk<br/>percurso de arvore]
    REP[lib/report<br/>relatorio em memoria]
  end

  subgraph ADAPT[Adaptadores - lib]
    AUTH[lib/auth<br/>unico manipulador de segredo]
    HTTP[lib/http<br/>unico ponto de saida de rede]
    JSONP[lib/json<br/>estrategia definida em DP-08]
    CONF[lib/config<br/>perfis e permissoes]
    STRM[lib/stream<br/>PLANEJADO - NAO MATERIALIZADO<br/>v1.2 DIV-20]
    TMP[lib/tmp<br/>temporarios e limpeza]
    OUT[lib/output]
    LOG[lib/log<br/>filtro de segredo]
  end

  subgraph DOMINIO[Dominio - sem dependencia de adaptadores]
    PATH[lib/path<br/>normalizacao e confinamento<br/>remoto e local]
    ERR[lib/errors<br/>taxonomia e codigos de saida<br/>NAO depende de lib/json]
    HASH[lib/hash<br/>content_hash por blocos de 4 MiB]
  end

  EXT[(Dropbox API v2)]

  BIN --> PRE
  BIN --> CLIP
  CLIP --> CASOS

  CFGC --> AUTH
  CFGC --> CONF
  UPC --> TRF
  DLC --> TRF
  UPC --> WALK
  DLC --> WALK
  LSC --> HTTP
  FSC --> HTTP
  SRC --> HTTP
  ACC --> HTTP

  TRF --> HTTP
  TRF --> TMP
  TRF --> HASH
  TRF -.RF-31 assumido por lib/transfer.-x STRM
  STRM -.-> TMP
  TRF --> REP
  REP --> OUT
  AUTH --> HTTP
  AUTH --> CONF
  HTTP --> AUTH
  HTTP --> JSONP
  HTTP -->|codigo HTTP + resumo ja extraido| ERR
  HTTP --> LOG
  HTTP --> EXT

  WALK --> PATH
  CASOS --> PATH
  CONF --> PATH
  CASOS --> OUT
  ERR --> OUT
  CLIP --> OUT
```

> **Leitura do diagrama.**
> **(1)** Todos os casos de uso convergem para `lib/output`, unico emissor de saida, que mantem as duas apresentacoes exigidas por RF-28 *(v0.2)*.
> **(2)** `lib/config` alimenta `lib/path` com a raiz permitida, e todo caso de uso normaliza o caminho por `lib/path` antes de qualquer chamada de rede ou acesso a disco, implementando o confinamento de RNF-20 *(v0.2, ampliado na v0.4)*.
> **(3)** A camada de **Orquestracao** torna explicito o que a tabela da v0.3 escondia: `lib/transfer`, `lib/walk` e `lib/report` coordenam dominio e adaptadores, e por isso **podem** depender de `lib/http`. Nao sao dominio *(v0.4, DIV-A.2)*.
> **(4)** A seta de `lib/http` para `lib/errors` carrega **codigo HTTP e resumo de erro ja extraido em texto**, nunca o corpo JSON bruto. E o que preserva `lib/errors` como dominio puro e o que a inversao implementada garante *(v0.4, DIV-A.1)*.
> **(5)** 🔴 **`lib/stream` esta desenhado desde a v0.3 e NAO FOI CRIADO** *(v1.2, `DIV-20`)*. A aresta ate ele aparece **cortada** para registrar o fato em vez de apaga-lo: `RF-31` foi implementado dentro de **`lib/transfer`** (laco de sessao, buffer de um bloco, area temporaria por `mktemp -d`) e de **`lib/hash`** (API incremental de resumo). `RF-32` — recebimento para a saida padrao — **nao foi implementado**, e onde ele vai morar continua em aberto. **O no e mantido no diagrama, e nao removido**, porque um componente planejado que nao se materializou e informacao; apaga-lo faria a proxima leitura concluir que ele nunca foi previsto.

### Estado local: componentes (v1.5)

```mermaid
flowchart LR
  subgraph CMDS[Casos de uso]
    UP[commands/upload<br/>arquivo]
    UPD[commands/upload<br/>diretorio]
    SY[commands/sync]
    UN[commands/unlink]
  end

  subgraph ST[lib/state - cache unico de content_hash]
    NSY[namespace memoria-*<br/>por conta + raiz local canonica + raiz remota<br/>so entradas visitadas]
    NUP[namespace upload-*<br/>por origem canonica, sem conta<br/>identidade forte, poda 10 mil / 90 dias]
  end

  DIR[(XDG_STATE_HOME/dbx<br/>diretorio 0700, arquivos 0600)]
  LEG[(dbx.db, -wal, -shm<br/>legado inerte)]
  DB[lib/db<br/>REMOVIDO v1.5]
  HTTP[lib/http]
  EXT[(Dropbox API v2)]

  UP -->|hash local, so com remoto existente| NUP
  UP -->|get_metadata: content_hash remoto decide| HTTP
  UPD -->|delega| SY
  SY -->|sem conta: nao le nem grava| NSY
  SY -->|get_current_account| HTTP
  HTTP --> EXT
  NSY --> DIR
  NUP --> DIR
  UN -->|remove o diretorio inteiro| DIR
  LEG -.fica no diretorio e nada o le nem escreve.-> DIR
  UP -.-x DB
  SY -.-x DB

  style DB stroke-dasharray: 5 5
  style LEG stroke-dasharray: 5 5
```

> **Leitura do diagrama.** O `upload` de arquivo e o `sync` escrevem em namespaces separados do mesmo componente; o `upload` nunca toca `memoria-*`, que e de onde `RF-48` deriva "par visto". O `upload` de diretorio delega ao `sync`. O `lib/db` aparece cortado para registrar a remocao, e o `dbx.db*` como legado inerte que so o `unlink` remove.

### Ciclo de leitura e escrita do cache (v1.5, do parecer do DBA)

```mermaid
flowchart TD
  subgraph Upload["upload de arquivo (RF-60, RF-61)"]
    U0{"--forcar, origem '-', nao regular ou vazia?"} -->|sim| UE[envia sem cache e sem comparar]
    U0 -->|nao| U1[get_metadata remoto]
    U1 -->|not_found ou falha da consulta| UE2[envia sem precisar do hash local]
    U1 -->|pasta| UC[comportamento atual de colisao]
    U1 -->|arquivo| U2[stat antes e carga do upload-resumo da origem canonica]
    U2 -->|identidade casa| U3[hash do cache]
    U2 -->|nao casa, corrompido ou ausente| U4[calcula hash e stat depois]
    U3 --> U5{hash local = hash remoto?}
    U4 --> U5
    U5 -->|sim| U6[dispensa o envio]
    U5 -->|nao| U7[envia conforme o modo]
    U4 -->|stat estavel e mtime a mais de 2 s| U8[grava upload-* atomico por mktemp + mv<br/>poda se houver mais de 10 mil]
  end
  subgraph Sync["sync (RF-38, RF-52)"]
    S0{conta identificada?} -->|nao| SN[segue sem memoria]
    S0 -->|sim| S1[carrega memoria-resumo da tripla e descarta se invalida]
    S1 --> S2[travessia: consulta o mapa em memoria]
    S2 -->|casa| S3[reaproveita hash]
    S2 -->|nao casa| S4[calcula e registra no mapa]
    S3 --> S5[decide comparando origem e destino]
    S4 --> S5
    S5 --> S6[grava uma vez no fim: so entradas visitadas se a travessia foi completa]
  end
```

### Selecao da apresentacao de saida

```mermaid
flowchart TD
    A([Comando produz resultado estruturado]) --> B{Sinalizador explicito de formato?}
    B -->|Sim| C[Usar a apresentacao solicitada]
    B -->|Nao| D{Terminal associado a saida padrao?}
    D -->|Sim| E[Apresentacao legivel por humano<br/>progresso e confirmacoes disponiveis]
    D -->|Nao| F[Apresentacao estruturada<br/>sem sequencia de controle de terminal]
    C --> G[Diagnostico sempre na saida de erro]
    E --> G
    F --> G
    G --> H([Codigo de saida por classe de falha])
```

### Fluxo de autenticacao e execucao de comando

```mermaid
sequenceDiagram
    participant OP as Operador ou agendador
    participant CLI as bin/dbx
    participant CF as lib/config
    participant AU as lib/auth
    participant HT as lib/http
    participant DX as Dropbox API v2

    OP->>CLI: comando + opcoes
    CLI->>CF: carregar perfil
    alt configuracao ausente ou invalida
        CF-->>CLI: erro de configuracao
        CLI-->>OP: mensagem acionavel + codigo de saida 3
    else configuracao valida
        CF-->>AU: app key, app secret, refresh token
        AU->>DX: POST oauth2/token (grant_type=refresh_token)
        DX-->>AU: access token de curta duracao + prazo
        CLI->>HT: requisicao do caso de uso
        HT->>DX: chamada autenticada
        alt 429 ou 5xx
            DX-->>HT: erro transitorio (Retry-After)
            HT->>HT: recuo exponencial com variacao
            HT->>DX: nova tentativa
        else 401
            DX-->>HT: token invalido
            HT->>AU: renovar token uma vez
            HT->>DX: repetir chamada
        else 400 ou 409
            DX-->>HT: erro definitivo
            HT-->>CLI: classe de erro mapeada
        end
        DX-->>HT: resposta
        HT-->>CLI: dados + X-Dropbox-Request-Id
        CLI-->>OP: saida formatada + codigo de saida
    end
```

### Decisao de estrategia de envio

```mermaid
flowchart TD
    A([Envio solicitado]) --> B{Arquivo existe e e legivel?}
    B -->|Nao| BX[Falha: recurso local ausente]
    B -->|Sim| C{Tamanho >= 150 MB?}
    C -->|Nao| D[POST files/upload em requisicao unica]
    C -->|Sim| E[upload_session/start]
    E --> F[append_v2 por parte<br/>multiplo de 4 MB]
    F --> G{Parte falhou?}
    G -->|Sim, transitoria| H[Recuo e reenvio da parte<br/>ate 5 tentativas, base 1 s, teto 60 s;<br/>Retry-After prevalece, ate 300 s]
    H --> F
    G -->|Nao| I{Ultima parte?}
    I -->|Nao| F
    I -->|Sim| J[upload_session/finish]
    D --> K[Verificar content_hash]
    J --> K
    K --> L{Confere?}
    L -->|Nao| M[Falha de integridade<br/>codigo de saida dedicado]
    L -->|Sim| N([Sucesso - codigo de saida 0])
```

### Implantacao e vinculacao com Design System

```mermaid
flowchart LR
  BA[Business Analyst] --> SD[System Design]
  UX[UX Expert] -.nao aplicavel<br/>sem interface grafica.-> DS[Design System]
  DS -.-> SD
  UXC[UX Expert - recomendado] -->|padrao de experiencia de CLI| SD
  DBA[DBA] -->|plano do estado local<br/>handoff v1.5, regra 26| SD
  SD --> QA[Validacao QA<br/>desvio de Cypress justificado]
  QA --> TL[Aceite do Tech Lead]
  SOL[Solicitante] -->|decisoes pendentes P0| SD
  SOL -->|aprovacao dos testes| TL

  style DS stroke-dasharray: 5 5
```

---

## Proximos passos

1. ⚠️ **Fechar `DP-20` — titular do copyright.** O `LICENSE` ja foi publicado com o titular em espaco reservado, e o placeholder esta no historico publico. E a **unica pendencia do projeto com custo crescente**: formalizar encarece a cada commit e a cada contribuidor.
2. **Executar a Etapa 2**, agora quase integralmente destravada: `lib/output` (DIV-16b), `lib/json` (DP-08), `lib/preflight` (DP-07 e DP-11), `lib/config` (DP-11), alem de `lib/http`, `lib/auth` e `lib/tmp`. Sequencia completa em [decisoes-pendentes.md](../requisitos/decisoes-pendentes.md).
3. ✅ **`RSK-24` encerrado.** A reavaliacao ocorreu **com `DP-07` ja resolvida**, e o solicitante reconfirmou o aceite com base apenas nos dois argumentos tecnicos validos. O argumento de portabilidade nao integra mais a fundamentacao.
4. ✅ **`DP-05` resolvida.** Uma conta so, sem perfis. `lib/config` tem desenho fechado.
5. **Ao implementar `lib/http`, tratar `RNF-23` como restricao de projeto**, e nao como detalhe do analisador: `limit`/`max_results` explicito em toda chamada de colecao, dimensionado ao teto de 256 KiB.
5. Confirmar a pendencia residual de DIV-14 — escopo OAuth exigido por `files/search_v2`, `sharing/create_shared_link_with_settings`, `users/get_current_account` e `users/get_space_usage` — durante a implementacao. Baixo risco: ausencia produz `401` explicito.
6. Substituir as premissas provisorias da secao de dimensionamento pelos valores reais de DP-12.
7. Reabrir a secao de dimensionamento com os limites observados nos testes de exaustao do QA Expert.
8. Acionar o UX Expert para o padrao de experiencia de linha de comando, incluindo a especificacao das duas apresentacoes exigidas por RF-28, e reabrir integralmente a secao de Design System caso DP-13 aprove o shell interativo.
9. **Vigiar a invariante de ausencia de estado local durante a implementacao** (RSK-23). O DBA so e acionado se uma funcionalidade do backlog que exija persistencia for promovida. *(v1.5)* O invariante vigente e "nenhum artefato persistente decide" (`RNF-26`); `DIV-26` a `DIV-29` resolvidas pelo Tech Lead em 2026-10-18.
10. Atualizar este documento a cada mudanca de arquitetura, implantacao, capacidade ou integracao.
