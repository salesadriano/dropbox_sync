# Escopo, Requisitos e Criterios de Aceite — Aplicacao Shell de Integracao com Dropbox

| Campo | Valor |
|---|---|
| Projeto | `dropbox_api` — aplicacao CLI em shell script para integracao com Dropbox |
| Responsavel Business Analyst | Business Analyst (pacote de agents) |
| Data da versao | 2026-08-17 |
| Versao | **v0.7** |
| Status | ✅ **Escopo aprovado. Nenhuma decisao bloqueante.** Ciclo 2 de QA aprovado com ressalva — 223 casos, `shellcheck -x` exit 0. Pendencia de maior urgencia: `DP-20` (titular do copyright), com custo crescente |
| Documentos relacionados | [System Design](../arquitetura/system-design.md) · [Decisoes pendentes](decisoes-pendentes.md) · [Funcionalidades candidatas](funcionalidades-candidatas.md) · [Riscos e licenciamento](riscos-restricoes-e-licenciamento.md) |

> **Aviso de maturidade.** Este documento separa deliberadamente o que e **derivavel com seguranca** a partir da demanda do que **depende de decisao do solicitante**. Requisitos marcados como `Condicional` nao devem entrar em planejamento de implementacao antes da resposta a decisao pendente correspondente. Nenhum requisito foi inventado para preencher lacuna de escopo.

## Registro de versao

| Versao | Mudanca |
|---|---|
| v0.1 | Especificacao inicial |
| v0.2 | DP-01 resolvida (reimplementacao independente); DP-03 resolvida (uso interativo **e** automatizado), promovendo RF-15 e RF-28 a P0 e reforcando RNF-19; DP-04 resolvida (conta pessoal com acesso a Dropbox inteira), movendo RF-06 para fora de escopo e criando RNF-20; contratos da Dropbox API revalidados via Context7, corrigindo unidades, o requisito de multiplo de 4 MiB, a paginacao de busca e as afirmacoes sobre endpoints depreciados; DIV-10 removida por erro factual; DIV-11 a DIV-14 acrescentadas |
| **v0.7** | **`RNF-24` criado (`E3-01`, contexto nomeado)** com a restricao verificavel de nome sempre interno; `RSK-27` (auditoria estatica que so pega a forma obvia) e `RSK-28` (instrumento de observacao interfere na propriedade observada) registrados; secao de vocabulario "separar dado de canal" no System Design. Duas correcoes de registro anterior incorporadas em `DIV-17`. Ciclo 2 de QA aprovado com ressalva |
| **v0.6** | **`DP-05` resolvida** — uma conta so, sem nocao de perfil: `RF-05` e `F-18` saem para o backlog como incremento **aditivo**, e o desenho de `lib/config` fica fechado (um arquivo, um caminho, sem multiplexacao). **`RNF-23` criado** a partir de medicao real: teto de entrada de 256 KiB em `lib/json` torna **obrigatorio o `limit`/`max_results` explicito** em toda chamada de colecao — `RF-16` e `RF-22` emendados. **`RSK-24` encerrado** com aceite reconfirmado, agora fundamentado apenas nos dois argumentos tecnicos validos |
| **v0.5** | **Correcao de registro e tres decisoes novas.** `DP-07` e `DP-08` **ja estavam decididas** pelo solicitante ("so cURL, `bash` 4+, Linux") e nunca haviam sido propagadas: `RNF-01` **descongelado** com piso `bash` **4.4**, `RNF-02` fixado sem `jq`, `RNF-11` elevado a criticidade maxima, `DIV-15` **retirada** e `RSK-25` **encerrado**. `DP-11` resolvida — credencial `0600` sob XDG, sem sobrescrita por ambiente (`RNF-04`). `DIV-16b` resolvida — `--null` com terminador nulo, destravando `lib/output` (`RF-28`, `RNF-22` ampliado aos dois modos). `DP-19` encerrada com desvios consumados registrados. `RES-15` a `RES-17` criadas. Novo risco `RSK-26` (falha de propagacao de decisao) e `RSK-24` reaberto para reavaliacao |
| **v0.4** | **Correcoes devolvidas pelo ciclo de QA da camada de dominio (aprovado com ressalva).** `RNF-20` ampliado para os **dois espacos de nomes**, remoto e local, com resolucao fisica de symlinks, oito vetores de ataque cobertos, raiz `/` sob opt-in e TOCTOU aceito como risco residual (`RSK-24`); `RNF-07` ajustado para a dimensao de idempotencia em `5xx` e `http=0`; `RNF-10` emendado para exigir quebra de linha no conjunto de teste; **`RNF-22` criado** (restricao de entrada de `lib/output` decorrente da redacao de cabecalho sensivel); `RF-31` corrigido quanto ao transito por `$TMPDIR` em blocos; `RF-35` fixa a faixa de codigos de saida em 0..15 e registra a rejeicao do codigo 16; **`RNF-01` congelado** e `DIV-15` aberta por antecipacao de decisao do solicitante; `DIV-16` reclassificada |
| **v0.3** | **DP-02 resolvida — escopo do MVP aprovado.** Secao 5.5 criada com RF-31 a RF-36, formalizando F-01, F-02, F-04 e F-05; secao 5.6 formaliza o Bloco 0 como requisito de base; F-03 e os Blocos 2 e 3 registrados como fora de escopo, o que mantem o MVP **sem estado local persistente** e nao aciona o handoff do DBA; **algoritmo do `content_hash` confirmado**, desbloqueando `lib/hash` e RF-33/RF-34; DIV-14 reduzida a uma pendencia residual; matriz de rastreabilidade estendida |

> ✅ **Escopo do MVP aprovado (`PRJ-DEC-04`).** Bloco 0 integral + F-01 (fluxo `stdin`/`stdout`) + F-02 (incremental por `content_hash`) + F-04 (contrato de automacao) + F-05 (relatorio de execucao). Formalizados nas secoes 5.5 e 5.6. Fundamentacao e backlog em [funcionalidades-candidatas.md](funcionalidades-candidatas.md).
>
> ⚠️ **O MVP nao introduz estado local persistente.** F-03, F-06, F-12 e F-14 — as unicas candidatas que o exigiriam — ficaram fora do escopo. `DP-09` permanece fechada e o handoff do DBA **nao** e acionado nesta versao. Reintroduzir persistencia constitui mudanca de escopo.

---

## 1. Especificacao de caso de uso

### 1.1 Problema de negocio

Operacoes de transferencia e gestao de arquivos no Dropbox precisam ser executadas a partir de ambientes onde **nao ha cliente grafico de sincronizacao nem runtime de aplicacao instalado** — servidores headless, containers, dispositivos embarcados, jobs de backup e pipelines de automacao. Nesses ambientes, o denominador comum disponivel e um shell POSIX e o `cURL`.

A demanda solicita uma aplicacao em shell script que exponha as capacidades da Dropbox API v2 como comandos de linha de comando, tomando como modelo o projeto `Dropbox-Uploader`.

> **Justificativa do investimento (DP-02, parcialmente resolvida).** O solicitante confirmou que a demanda se justifica por **funcionalidades que o `Dropbox-Uploader` nao possui**. O projeto, portanto, **nao** e uma reimplementacao equivalente: e uma ferramenta com escopo funcional maior. O risco de "clone sem valor incremental" esta encerrado.
>
> Permanece em aberto **quais** funcionalidades. A proposta de 22 candidatas, com valor, esforco e dependencias, esta em [funcionalidades-candidatas.md](funcionalidades-candidatas.md), aguardando confirmacao, corte ou acrescimo. Enquanto isso nao for respondido, o MVP nao e definivel.

### 1.2 Usuarios primarios

| Persona | Contexto de uso | Necessidade dominante |
|---|---|---|
| Administrador de sistemas | Servidor Linux headless, sessao SSH | Transferir arquivos sob demanda sem instalar runtime adicional |
| Engenheiro de automacao | `cron`, `systemd timer`, pipeline de CI | Execucao nao assistida, previsivel, com codigo de saida confiavel e sem prompt interativo |
| Operador de rotina de backup | Job agendado noturno | Envio recorrente de artefatos volumosos com retomada e verificacao de integridade |
| Desenvolvedor integrador | Estacao de trabalho | Consultar, publicar e compartilhar arquivos a partir de scripts proprios |

> Personas derivadas do contexto tecnico da demanda e dos ambientes testados declarados pelo projeto de referencia. **Requerem confirmacao do solicitante** (DP-03).

### 1.3 Criterios de sucesso mensuraveis

| ID | Criterio de sucesso | Metrica | Meta proposta |
|---|---|---|---|
| CS-01 | Instalacao e primeiro uso sem dependencia alem de shell e `cURL` | Numero de pacotes adicionais exigidos em instalacao minima de distribuicao suportada | 0 (ou 1, se `jq` for aprovado em DP-08) |
| CS-02 | Execucao nao assistida confiavel | Taxa de sucesso de execucoes agendadas em 30 dias, sem intervencao humana | >= 99% |
| CS-03 | Diagnostico de falha sem inspecao de codigo | Percentual de falhas em que a mensagem de erro identifica causa e acao corretiva | 100% dos codigos de erro mapeados |
| CS-04 | Nao exposicao de segredos | Ocorrencias de credencial em `argv`, log, variavel exportada ou arquivo com permissao ampla | 0 |
| CS-05 | Aderencia a contratos vigentes da Dropbox API v2 | Endpoints depreciados ou retirados em uso | 0 |
| CS-06 | Verificabilidade | Percentual de requisitos com criterio de aceite automatizavel | 100% |

---

## 2. Fronteiras de escopo

### 2.1 Dentro do escopo (derivavel com seguranca)

- Aplicacao de linha de comando escrita em shell script.
- Autenticacao OAuth2 contra a Dropbox API v2 com refresh token e access token de curta duracao.
- Operacoes de arquivos e pastas: envio, recebimento, listagem, metadados, criacao de pasta, mover, copiar, excluir.
- Consulta de informacoes de conta e uso de espaco.
- Tratamento de erro, retentativa e codigos de saida adequados a automacao.
- Documentacao de uso e de implantacao.

### 2.2 Fora do escopo (nesta versao)

- Interface grafica, web ou TUI.
- Sincronizacao **bidirecional** — o `sync` e direcional por `DP-27`, com a origem como autoridade. Sincronizacao continua, tambem fora.
- Daemon residente em memoria.
- Servidor de callback OAuth em `localhost` (o fluxo previsto e por codigo de autorizacao colado manualmente).
- Suporte a provedores de armazenamento alem do Dropbox.
- Criptografia de conteudo do lado do cliente antes do envio. A composicao com ferramentas externas por fluxo continua possivel.
- **Dropbox Business e Team em qualquer forma** — administracao de equipe, impersonacao de membro, espaco de equipe e manipulacao de namespace por `Dropbox-API-Path-Root`. **Definitivo por DP-04**, que fixou conta pessoal.

### 2.3 Escopo condicional

| Capacidade | Depende de |
|---|---|
| Funcionalidades novas propostas (F-01 a F-22) | **DP-02** — bloqueante |
| Perfis e multiplas contas | DP-05 |
| Shell interativo equivalente ao `dropShell.sh` | DP-13 |
| Sincronizacao unidirecional com espelhamento e exclusao remota | DP-09, acoplada a DP-02 |
| Monitoramento de mudancas via longpoll | DP-16 |
| Empacotamento em container e distribuicao | DP-14 |

### 2.3.1 Escopo desbloqueado na v0.2

| Item | Situacao anterior | Situacao atual |
|---|---|---|
| Regime de licenciamento | Bloqueava o inicio do trabalho | **Resolvido.** Reimplementacao independente; sem obrigacao copyleft. Licenca especifica pendente em DP-20 |
| Modo de uso | Indefinido entre interativo e automatizado | **Resolvido.** Ambos. RF-15 e RF-28 promovidos a P0; RNF-19 reforcado |
| Tipo de conta e escopo de acesso | Indefinido | **Resolvido.** Conta pessoal com acesso a Dropbox inteira. RF-06 movido para fora de escopo; RNF-20 criado |

### 2.4 Atores e sistemas externos

```mermaid
flowchart LR
  ADM[Administrador de sistemas] --> CLI[Aplicacao CLI shell]
  AUT[Agendador cron / CI] --> CLI
  DEV[Script de terceiros] --> CLI
  CLI --> API[Dropbox API v2 - api.dropboxapi.com]
  CLI --> CNT[Dropbox Content API - content.dropboxapi.com]
  CLI --> OAU[Dropbox OAuth2 - api.dropbox.com/oauth2/token]
  CLI --> FS[Sistema de arquivos local]
  CLI --> CFG[(Configuracao e cache de token)]
  APP[Aplicativo registrado no Dropbox App Console] -.credenciais.-> CFG
```

---

## 3. Premissas

| ID | Premissa | Consequencia se falsa |
|---|---|---|
| PRE-01 | O solicitante possui ou pode criar um aplicativo no Dropbox App Console com acesso `Scoped Access` | Sem app key/secret nao ha autenticacao possivel; o projeto nao inicia |
| PRE-02 | O ambiente de execucao tem `cURL` com suporte a TLS e cadeia de certificados valida | Toda a integracao falha |
| PRE-03 | O ambiente de execucao dispone de sistema de arquivos gravavel para configuracao e area temporaria | Upload em partes e cache de token ficam inviaveis |
| PRE-04 | A conta Dropbox alvo tem espaco e cota de API compativeis com o volume pretendido | Falhas por `insufficient_space` e HTTP 429 |
| PRE-05 | Nao ha requisito de persistencia em banco de dados | Handoff do DBA passa a ser obrigatorio e o System Design precisa de revisao |
| PRE-06 | Nao ha interface grafica; portanto nao ha Design System aplicavel | A secao obrigatoria de Design System do System Design precisa de handoff do UX Expert |
| PRE-07 | O conteudo transferido nao contem dado pessoal sensivel sujeito a controle regulatorio adicional | Exige requisitos de LGPD, criptografia em repouso e trilha de auditoria (ver DP-10) |

---

## 4. Restricoes

| ID | Restricao | Origem |
|---|---|---|
| RES-01 | A implementacao deve ser em shell script | Imposicao explicita do solicitante |
| RES-02 | **Nao derivar codigo do projeto de referencia.** Por decisao registrada em DP-01, o `Dropbox-Uploader` e referencia conceitual apenas; nenhum trecho de codigo, estrutura interna de funcoes, nome interno de variavel ou texto literal de mensagem pode ser copiado ou adaptado | Decisao do solicitante. Afasta o copyleft GPLv3. Ver [riscos](riscos-restricoes-e-licenciamento.md) |
| RES-03 | O contrato de integracao e definido pela Dropbox e nao e negociavel | Dropbox API v2 |
| RES-04 | Access token de curta duracao; acesso nao assistido exige refresh token obtido com `token_access_type=offline` na URL de autorizacao. A resposta do endpoint de token informa a validade em `expires_in` (exemplo documentado: `14400`, equivalente a 4 horas) | Documentacao Dropbox, revalidada via Context7 |
| RES-05 | `POST /2/files/upload` nao deve ser usado para arquivos maiores que **150 MiB**; acima disso e obrigatorio o fluxo de `upload_session`. Cada requisicao isolada de `append_v2` e de `finish` tambem esta limitada a 150 MiB. O tamanho maximo por sessao e de 2^41 − 2^22 bytes | Documentacao Dropbox, revalidada via Context7 |
| RES-06 | O endpoint vigente de busca e `/2/files/search_v2`, paginado por `/2/files/search/continue_v2`, com teto de **10.000 correspondencias**. A documentacao atual **nao apresenta mais** o endpoint `/2/files/search` sem sufixo | Documentacao Dropbox, revalidada via Context7. O projeto de referencia ainda aponta para o endpoint sem sufixo |
| RES-07 | As operacoes vigentes sao `copy_v2`, `move_v2`, `delete_v2` e `create_folder_v2`, todas retornando envelope com campo `metadata`. A documentacao atual **nao apresenta mais** as variantes sem sufixo | Documentacao Dropbox, revalidada via Context7 |
| RES-08 | Shell nao oferece parser JSON nativo. **Decidido em DP-08: interpretador proprio em shell, sem `jq`.** A unica dependencia externa e `cURL` | Limitacao da linguagem imposta em RES-01; decisao do solicitante |
| RES-15 | **Plataforma Linux e `bash` 4.4 ou superior.** macOS, *BSD, BusyBox `ash` e `sh` POSIX estao fora de escopo; RHEL 6 (`bash` 4.1) fica fora | Decisao do solicitante em DP-07, com o piso refinado tecnicamente |
| RES-16 | **Credencial exclusivamente em arquivo `0600` sob convencao XDG**, sem sobrescrita por variavel de ambiente | Decisao do solicitante em DP-11 |
| RES-17 | ✅ **Resolvido.** O repositorio esta publicado em `github.com:salesadriano/dropbox_sync` sob **licenca MIT**, titular **`Adriano Sales Santos`**, verificado por leitura direta do `LICENSE`. O placeholder que existiu no historico publico e situacao consumada e **inocua** — o commit de correcao e posterior e o estado corrente esta correto | `DP-20` resolvida; `DIV-E` encerrada |
| RES-09 | O projeto alvo nao e repositorio git e nao possui stack instalada | Estado observado em `/home/sales/dropbox_api` |
| RES-10 | Em sessao de envio do tipo **concorrente**, o deslocamento e o tamanho de cada parte **devem** ser multiplos de 4.194.304 bytes (2^22). Em sessao **sequencial** nao ha essa exigencia | Documentacao Dropbox, revalidada via Context7. **Corrige a v0.1**, que tratava o multiplo de 4 MiB como recomendacao geral |
| RES-11 | Chamadas simultaneas de `list_folder` ou `list_folder/continue` para o mesmo usuario pelo mesmo aplicativo produzem erro de limite de taxa; a orientacao e aguardar as requisicoes pendentes antes de iniciar nova chamada | Documentacao Dropbox, revalidada via Context7. Restringe diretamente qualquer estrategia de paralelismo (F-09) |
| RES-12 | A revogacao de token desabilita tambem o refresh token correspondente e todos os demais access tokens derivados dele | Documentacao Dropbox, revalidada via Context7 |
| RES-13 | O acesso concedido ao aplicativo e amplo (`Full Dropbox`), por decisao registrada em DP-04. A limitacao de alcance passa a depender de escopos OAuth minimos e de controles da propria aplicacao | Decisao do solicitante |
| RES-14 | A busca pode retornar resultados duplicados entre paginas ou omitir resultados, por atraso de indexacao. A deduplicacao e responsabilidade do cliente | Documentacao Dropbox, revalidada via Context7 |

---

## 5. Requisitos funcionais

Legenda de prioridade: **P0** essencial ao MVP · **P1** importante · **P2** desejavel.
Legenda de status: **Derivavel** = seguro a partir da demanda · **Condicional** = depende de decisao pendente.

### 5.1 Autenticacao e configuracao

| ID | Requisito | Prior. | Status | Criterio de aceite |
|---|---|---|---|---|
| RF-01 | Assistente de configuracao inicial que orienta o registro do aplicativo, coleta app key, app secret e codigo de autorizacao, troca o codigo por refresh token e persiste a configuracao | P0 | Derivavel | Dado ambiente sem configuracao previa, quando o comando de configuracao e executado e os dados validos sao informados, entao o arquivo de configuracao e criado com permissao `0600`, contendo refresh token, e um comando subsequente de leitura (`info`) retorna codigo de saida `0` |
| RF-02 | Obtencao automatica de access token de curta duracao a partir do refresh token, com cache em memoria durante a execucao e renovacao antes da expiracao | P0 | Derivavel | Dado refresh token valido, quando qualquer comando autenticado e executado, entao ocorre no maximo uma chamada a `oauth2/token` por execucao e o comando conclui com sucesso; dado access token expirado durante a execucao, quando a API responde `401`, entao o token e renovado uma vez e a operacao e repetida com sucesso |
| RF-03 | Validacao da configuracao com mensagem acionavel quando ausente, incompleta ou em formato legado | P0 | Derivavel | Dado arquivo de configuracao ausente ou sem refresh token, quando um comando autenticado e executado, entao a saida indica a causa e o comando corretivo, e o codigo de saida e `3` (erro de configuracao) |
| RF-04 | Desvinculo (`unlink`) que revoga o token junto a Dropbox e remove as credenciais locais | P1 | Derivavel | Dado configuracao valida, quando o desvinculo e executado, entao `POST /2/auth/token/revoke` retorna sucesso, o arquivo de configuracao e removido ou invalidado, e um comando autenticado subsequente falha com codigo `3` |
| ~~RF-05~~ | ~~Suporte a multiplos perfis de credencial na mesma instalacao~~ | — | ❌ **Fora de escopo desta versao (DP-05)** | Removido na v0.6. O solicitante fixou **uma conta so, sem nocao de perfil**: um unico arquivo de credencial, sem `--profile`, sem arquivo por perfil, sem selecao por ambiente. **Justificativa:** acrescentar perfis depois e mudanca **aditiva** — um sinalizador e um caminho alternativo — que nao quebra o contrato publico congelado por RF-35. Custo de adiar baixo; custo de antecipar real (multiplexacao em `lib/config`, mais estados, mais superficie de teste). Mantido no backlog junto com F-18 |
| ~~RF-06~~ | ~~Suporte a contas Dropbox Business/Team, com selecao de namespace e execucao em nome de membro~~ | — | ❌ **Fora de escopo (DP-04)** | Removido na v0.2. O solicitante fixou conta pessoal. Nao havera uso de `Dropbox-API-Path-Root`, de selecao de membro nem de endpoints de equipe |
| RF-06a | Revogacao consciente: a operacao de desvinculo deve advertir que a revogacao invalida tambem o refresh token e todos os access tokens derivados | P1 | Derivavel | Dado modo interativo, quando o desvinculo e solicitado, entao a advertencia e exibida e a confirmacao e exigida; dado modo automatizado, entao a operacao so prossegue com sinalizador explicito de confirmacao (RES-12) |

### 5.2 Transferencia de arquivos

| ID | Requisito | Prior. | Status | Criterio de aceite |
|---|---|---|---|---|
| RF-07 | Envio de arquivo local para caminho remoto usando requisicao unica quando o arquivo nao ultrapassar 150 MiB | P0 | Derivavel | Dado arquivo local de 1 MiB, quando o envio e executado, entao o arquivo existe no destino remoto com tamanho identico, o `content_hash` retornado corresponde ao calculado localmente e o codigo de saida e `0` |
| RF-08 | Envio em partes (`upload_session/start`, `append_v2`, `finish`) para arquivos acima de 150 MiB, com tamanho de parte configuravel e nunca superior a 150 MiB por requisicao | P0 | Derivavel | Dado arquivo de 200 MiB, quando o envio e executado, entao sao emitidas as chamadas de sessao na ordem correta, nenhuma requisicao isolada excede 150 MiB, o arquivo remoto tem o tamanho original e o `content_hash` confere. Dado que a sessao seja do tipo concorrente, entao o deslocamento e o tamanho de cada parte sao multiplos de 4.194.304 bytes (RES-10) |
| RF-09 | Retentativa por parte em falha transitoria durante o envio em partes, sem reiniciar o arquivo inteiro | P0 | Derivavel | Dada falha transitoria simulada em uma parte, quando o envio prossegue, entao apenas a parte afetada e reenviada (ate 3 tentativas) e o resultado final e integro |
| RF-10 | Politica explicita de colisao no destino: sobrescrever, ignorar existente ou renomear automaticamente | P0 | Derivavel | Dado arquivo ja existente no destino, quando o envio e executado com cada politica, entao o resultado corresponde a politica escolhida e e reportado na saida |
| RF-11 | Recebimento de arquivo remoto para caminho local, com verificacao de integridade | P0 | Derivavel | Dado arquivo remoto conhecido, quando o recebimento e executado, entao o arquivo local tem o mesmo tamanho e o `content_hash` calculado localmente corresponde ao valor retornado pela API |
| RF-12 | Envio recursivo de diretorio, preservando a hierarquia, com padroes de exclusao | P1 | Derivavel | Dada arvore local com 3 niveis e um padrao de exclusao, quando o envio recursivo e executado, entao a hierarquia e replicada no destino, os itens excluidos nao sao enviados e a contagem de itens enviados e reportada |
| RF-13 | Recebimento recursivo de pasta remota, preservando a hierarquia | P1 | Derivavel | Dada pasta remota com subpastas, quando o recebimento recursivo e executado, entao a arvore local reproduz a estrutura remota e todos os arquivos passam na verificacao de integridade |
| RF-14 | Envio direto de conteudo a partir de URL (`save_url`), sem transito pelo disco local, com acompanhamento do job assincrono | P2 | **Condicional (DP-06)** | Dada URL publica valida, quando o comando e executado, entao o job e iniciado, o estado e consultado ate a conclusao e o arquivo aparece no destino remoto |
| RF-15 | Modo de simulacao (`dry-run`) que descreve as operacoes sem executar escrita remota ou local | **P0** *(promovido por DP-03)* | Derivavel | Dado qualquer comando de escrita executado em modo de simulacao, quando concluido, entao nenhuma chamada de escrita e emitida a API, o plano de acao e impresso e o codigo de saida e `0` |

### 5.3 Gestao de conteudo remoto

| ID | Requisito | Prior. | Status | Criterio de aceite |
|---|---|---|---|---|
| RF-16 | Listagem de pasta remota com paginacao completa via cursor **e `limit` explicito** | P0 | Derivavel | Dada pasta com mais itens do que uma pagina retorna, quando a listagem e executada, entao todos os itens sao apresentados por meio de `list_folder` e `list_folder/continue`, sem truncamento silencioso. **Acrescentado na v0.6 (RNF-23):** a chamada envia `limit` explicito, dimensionado para manter cada resposta abaixo do teto de 256 KiB do analisador; dada pasta grande o bastante para ultrapassar esse teto em uma unica resposta, entao a operacao conclui por paginacao, e **nao** falha por recusa de analise |
| RF-17 | Consulta de metadados de arquivo ou pasta (tipo, tamanho, data de modificacao, `content_hash`, `rev`) | P0 | Derivavel | Dado caminho remoto existente, quando os metadados sao consultados, entao os campos previstos sao exibidos; dado caminho inexistente, entao a saida indica `path_not_found` e o codigo de saida e `4` |
| RF-18 | Criacao de pasta remota, incluindo caminhos intermediarios | P0 | Derivavel | Dado caminho remoto de 3 niveis inexistente, quando a criacao e executada, entao a pasta final existe e a operacao e idempotente em nova execucao |
| RF-19 | Mover e renomear item remoto | P0 | Derivavel | Dado item remoto existente, quando movido para novo caminho, entao o item passa a existir no destino, deixa de existir na origem e o retorno confirma o novo caminho |
| RF-20 | Copiar item remoto | P1 | Derivavel | Dado item remoto existente, quando copiado, entao origem e destino existem com o mesmo `content_hash` |
| RF-21 | Excluir item remoto, com confirmacao obrigatoria em modo interativo e supressao explicita em modo automatizado | P0 | Derivavel | Dado item remoto existente, quando a exclusao e executada com confirmacao, entao o item deixa de existir; dado modo automatizado sem sinalizador de confirmacao, entao a operacao e recusada com codigo de saida `2` |
| RF-22 | Busca de itens por termo, com paginacao por cursor, **`max_results` explicito** e deduplicacao de resultados | P1 | Derivavel | Dado termo com correspondencias conhecidas, quando a busca e executada, entao os resultados sao obtidos via `/2/files/search_v2` e paginados por `/2/files/search/continue_v2`, nenhuma chamada e feita ao endpoint sem sufixo, itens repetidos entre paginas sao apresentados uma unica vez (RES-14) e o teto de 10.000 correspondencias e comunicado ao usuario quando atingido. **Acrescentado na v0.6 (RNF-23):** a chamada envia `max_results` explicito, dimensionado para manter cada resposta abaixo do teto de 256 KiB do analisador |
| RF-23 | Criacao e consulta de link compartilhado para arquivo ou pasta | P1 | Derivavel | Dado item remoto existente sem link, quando o compartilhamento e solicitado, entao um link e criado e exibido; dado item que ja possui link, entao o link existente e reaproveitado sem erro |
| RF-24 | Monitoramento de alteracoes em pasta remota com espera longa (`longpoll`) e tempo limite configuravel | P2 | **Condicional (DP-16)** | Dada pasta monitorada, quando ocorre alteracao remota, entao o evento e reportado em ate 30 segundos; dado tempo limite atingido sem alteracao, entao o comando encerra com codigo de saida dedicado |

### 5.4 Conta e diagnostico

| ID | Requisito | Prior. | Status | Criterio de aceite |
|---|---|---|---|---|
| RF-25 | Exibicao de informacoes da conta autenticada | P1 | Derivavel | Dado token valido, quando o comando e executado, entao nome, identificador e tipo de conta sao exibidos e o codigo de saida e `0` |
| RF-26 | Exibicao de uso e cota de espaco, com opcao de formato legivel por humano | P1 | Derivavel | Dado token valido, quando o comando e executado, entao espaco usado e alocado sao exibidos em bytes e, sob sinalizador, em unidades legiveis |
| RF-27 | Ajuda de uso por comando e exibicao de versao da aplicacao | P0 | Derivavel | Quando a ajuda e solicitada sem argumentos ou com argumento invalido, entao a sintaxe e a lista de comandos sao exibidas; quando a versao e solicitada, entao a versao semantica e impressa e o codigo de saida e `0` |
| RF-28 | Saida com duas apresentacoes sobre o mesmo modelo de resultado: legivel por humano quando houver terminal associado, e estruturada legivel por maquina quando nao houver ou quando solicitada por sinalizador explicito. **Dois modos de terminador de registro** (v0.5, DIV-16b) | **P0** *(promovido por DP-03)* | Derivavel | Dado comando de consulta executado com terminal associado, quando concluido, entao a saida e formatada para leitura humana; dado o mesmo comando executado sem terminal associado ou com o sinalizador de saida estruturada, entao a saida padrao contem apenas registros parseaveis por script, sem texto decorativo, e todo diagnostico e escrito na saida de erro. O sinalizador explicito prevalece sobre a deteccao automatica em ambos os sentidos. **Terminador:** por padrao, um registro por linha; **com `--null`, o terminador e o byte nulo (`\0`)**, no padrao de `find -print0` e `xargs -0`. Dado nome de arquivo contendo quebra de linha, quando a saida e emitida em modo `--null`, entao o registro e integro e delimitado sem ambiguidade; quando emitida no modo padrao, entao a ambiguidade e sinalizada em vez de produzir registro corrompido silenciosamente (RNF-10) |
| RF-29 | Codigos de saida deterministicos e documentados, distintos por classe de falha | P0 | Derivavel | Dado cada classe de falha (uso invalido, configuracao, nao encontrado, autenticacao, limite de taxa, rede, erro remoto), quando reproduzida, entao o codigo de saida corresponde ao valor documentado e e estavel entre execucoes |
| RF-30 | Registro de diagnostico com niveis de verbosidade, contendo contexto suficiente para abrir chamado junto ao suporte da Dropbox | P1 | Derivavel | Dado nivel de diagnostico elevado, quando ocorre falha de API, entao o log contem endpoint, codigo HTTP, `error_summary` integral e, **quando presente na resposta**, o cabecalho de identificacao de requisicao retornado pela Dropbox; em nenhuma hipotese o log contem segredo. **Nota v0.2:** a existencia do cabecalho `X-Dropbox-Request-Id` nao foi confirmada na documentacao indexada; o requisito foi reescrito para registrar o cabecalho de correlacao caso ele exista, sem depender do nome exato |

### 5.5 Funcionalidades novas aprovadas no MVP

Formalizacao das candidatas aprovadas em `PRJ-DEC-04`. Todas com status **Aprovado** — nenhuma e condicional.

| ID | Requisito | Prior. | Origem | Criterio de aceite |
|---|---|---|---|---|
| RF-31 | Envio de conteudo recebido pela entrada padrao para um caminho remoto, sem exigir arquivo intermediario **do tamanho do conteudo**. Como o tamanho total e desconhecido no inicio, a operacao usa obrigatoriamente sessao em partes, bufferizando uma parte por vez | P0 | F-01 | Dado `tar czf - /dados \| dbx upload - /destino.tgz`, quando o comando conclui, entao o arquivo remoto existe, seu tamanho corresponde ao total de bytes lidos da entrada padrao e seu `content_hash` corresponde ao calculado sobre o fluxo consumido; **o conteudo transita por `$TMPDIR` em blocos de 4 MiB**, com arquivo de bloco em modo `0600` sob area `0700`, e a ocupacao maxima em disco e a de **um bloco**, nunca a do conteudo integral; dado que a origem do fluxo falhe no meio, entao nenhum arquivo parcial e publicado no destino, nenhum residuo permanece em `$TMPDIR` e o codigo de saida indica operacao nao concluida. **Ajustado na v0.4:** a redacao da v0.3 dizia "sem materializar em disco", o que era impreciso; o transito por area temporaria em blocos foi aceito sem ressalva pelo solicitante, revertendo a decisao de desenho anterior. O invariante que importa e o **teto de ocupacao**, nao a ausencia de disco |
| RF-32 | Recebimento de conteudo remoto diretamente para a saida padrao, permitindo composicao com outros processos | P0 | F-01 | Dado `dbx download /origem.tgz - \| tar xzf - -C /restauracao`, quando o comando conclui, entao os bytes escritos na saida padrao correspondem integralmente ao conteudo remoto e o `content_hash` calculado sobre o fluxo emitido confere com o dos metadados remotos; nenhum diagnostico, mensagem ou indicacao de progresso e escrito na saida padrao durante a operacao; dado que o processo consumidor encerre antes do fim, entao a aplicacao termina sem erro nao tratado e com codigo de saida especifico |
| RF-33 | Omissao de transferencia quando o conteudo de origem e destino for identico, decidida por comparacao de `content_hash` e nao por nome, data ou existencia | P0 | F-02 | Dado arquivo local cujo `content_hash` e igual ao do arquivo remoto de mesmo caminho, quando o envio e executado, entao nenhuma chamada de escrita e emitida a API, o item e contabilizado como omitido no relatorio e o codigo de saida e `0`; dado arquivo local com mesmo nome, mesmo tamanho e mesma data de modificacao mas conteudo diferente, entao a transferencia **ocorre**; dado que o item nao exista no destino, entao a transferencia ocorre sem consulta redundante. O comportamento e desativavel por sinalizador explicito que forca a transferencia |
| RF-34 | Calculo local do `content_hash` conforme o algoritmo publicado pela Dropbox | P0 | F-02 | Dado o arquivo de teste oficial publicado pela Dropbox, quando o resumo e calculado localmente, entao o resultado e exatamente `485291fa0ee50c016982abbfa943957bcd231aae0492ccbaa22c58e3997b35e0`; dado arquivo vazio, arquivo menor que um bloco, arquivo de exatamente um bloco e arquivo com multiplos blocos mais resto, entao o valor calculado coincide com o `content_hash` retornado pela API apos o envio de cada um; o resultado tem 64 caracteres hexadecimais |
| RF-35 | Estabilidade e versionamento do contrato de saida estruturada, para que consumidores automatizados nao quebrem em atualizacoes | P0 | F-04 | A saida estruturada declara a versao do contrato; dentro de uma mesma versao principal, campos existentes nao mudam de nome, tipo ou semantica, e apenas acrescimo de campo e permitido; dado consumidor escrito contra a versao corrente, quando uma atualizacao compativel e aplicada, entao o consumidor continua funcionando sem alteracao. **Contrato de codigos de saida fixado na v0.4:** a faixa e **0..15**, aceita como contrato publico; cada codigo esta publicado na documentacao e coberto por teste que reprova se mudar de significado; a coerencia entre classe de erro e politica de retentativa e verificada. **Proposta de codigo 16 (`dependencia_ausente`) rejeitada pelo solicitante:** o problema diagnosticado era precisao de mensagem, nao escassez de codigo, e foi resolvido reescrevendo a mensagem da classe `configuracao` e mapeando falha de area temporaria para ela. Ampliar a faixa sem necessidade real degradaria o contrato publico |
| RF-36 | Relatorio de execucao ao final de operacoes em lote, disponivel nas duas apresentacoes de saida | P1 | F-05 | Dada operacao sobre multiplos itens, quando ela conclui, entao o relatorio informa quantidade de itens transferidos, omitidos por conteudo identico, falhados, total de bytes transferidos, duracao e numero de chamadas emitidas a API; os mesmos dados estao disponiveis na apresentacao estruturada, permitindo que um orquestrador decida alertar por limiar sem analisar texto livre; dado que ao menos um item falhe, entao o codigo de saida reflete a falha ainda que outros itens tenham sido concluidos |

### 5.8 Comando `sync` — direcional, com a origem como autoridade

> ### ⚠️ `DP-27` — MUDANCA DE ESCOPO DECIDIDA PELO SOLICITANTE (2026-08-19)
>
> **Decisao registrada, na forma em que foi dada:** o `sync` recebe **`--origem` e `--destino` como parametros obrigatorios**, e **o estado dos arquivos na origem e que determina o comportamento**. Um dos dois lados e local e o outro e remoto, **nunca os dois do mesmo tipo**: origem local implica destino remoto e operacao base de **envio**; origem remota implica destino local e operacao base de **recebimento**.
>
> **`DP-27a`** — os papeis vem de **sinalizador explicito** (`--origem`, `--destino`), e nao de posicao na linha de comando. O solicitante reviu a escolha por posicao ao ver que ela decide o *papel* e nao diz de que **lado** cada caminho esta.
>
> **`DP-27b`** — a **linha de base persiste**, por decisao do solicitante, mas **rebaixada a memoria auxiliar de desempenho**: ela **nao arbitra** decisao alguma. A decisao le origem e destino agora.
>
> **O QUE ISTO REVOGA.** O `sync` **deixa de ser bidirecional**. Com isso caem, por perda de premissa e nao por preferencia:
>
> - a **matriz de tres estados** de 5.8.2, com suas treze linhas e quatro classes de conflito — nao ha conflito quando um dos lados manda;
> - `DP-21` (ultimo a escrever vence) e `DP-22` (honrar a exclusao), que eram **politicas de arbitragem de conflito**;
> - `RF-39a` e `RF-40a`, que ordenavam vencedor por carimbo de tempo e por recuperabilidade;
> - o argumento de 5.8.1, que derivava a linha de base **por construcao** da bidirecionalidade.
>
> **O QUE ISTO NAO REVOGA, E FICA MAIS IMPORTANTE.** `RF-40` (exclusao desabilitada por padrao), `RF-41` (salvaguardas contra exclusao em massa), `RF-47` (registro nominal de toda perda) e `RF-48` (reconhecimento na primeira execucao com espelhamento). A razao esta em 5.8.1: a protecao que a linha de base dava contra exclusao indevida **desapareceu junto com o papel dela**, e essas quatro passam a ser a defesa inteira.
>
> **`PRJ-DEC-07` continua revogado** para o escopo do `sync`, e `DP-09` continua reaberta — nao pela correcao, que ja nao exige estado, mas pela escolha de `DP-27b`. O handoff do DBA segue acionado, com escopo reduzido: o artefato passou de **arbitro** a **memoria descartavel**, e o custo de perde-lo caiu de "decisao errada" para "trabalho repetido".

> ### 📜 Registro da decisao anterior — `DP-06`, superada por `DP-27`
>
> **O bloco abaixo e preservado, e nao apagado.** Ele registra a escolha vigente ate 2026-08-19 e a razao dela, e e o que torna legivel por que a linha de base existe, por que `PRJ-DEC-07` foi revogado e por que o handoff do DBA foi acionado. Onde ele disser **bidirecional**, leia-se **superado**.
>
> **Mudanca de escopo autorizada.** `DP-06` fixou os comandos do MVP em **`upload`, `download`, `list`, `delete`, `info` e `sync`**, e o solicitante escolheu para o `sync`: **bidirecional**, **remocao de orfaos sob opcao explicita** (promove `F-06` do Bloco 2) e **cursor persistente** (aproxima `F-14`).
>
> **Isto revoga `PRJ-DEC-07` para o escopo do `sync`.** O invariante de ausencia de estado local persistente deixa de valer, `DP-09` esta **reaberta** e o **handoff do DBA foi acionado**. O invariante permanece valido para todos os demais comandos.

#### 5.8.1 A premissa que caiu, e a protecao que caiu junto com ela

A versao anterior desta secao provava que **sincronizacao bidirecional com propagacao de exclusao exige linha de base persistente por construcao**. A prova estava correta, e continua correta: com apenas dois estados observaveis, duas situacoes opostas sao indistinguiveis.

| Observacao | Interpretacao A | Interpretacao B | Acao correta |
|---|---|---|---|
| Ausente no local, presente no remoto | O usuario **apagou** localmente | O arquivo **nunca foi baixado** | Oposta: apagar no remoto **ou** baixar |
| Presente no local, ausente no remoto | O arquivo e **novo** localmente | O usuario **apagou** no remoto | Oposta: enviar **ou** apagar local |

**`DP-27` dissolve a ambiguidade removendo a pergunta, e nao respondendo-a.** Ela so existe porque os dois lados podem originar mudanca. Com a origem como autoridade unica, "ausente na origem" tem **uma leitura so** — nao ha o que arbitrar, e o terceiro estado deixa de ser necessario para decidir.

##### A consequencia que precisa estar escrita, porque nao e obvia

A linha de base **nao era so um desempatador**. Ela era, tambem, **um limitador de exclusao**, e essa segunda funcao desapareceu sem substituto automatico.

Na matriz antiga, exclusao so era possivel quando `B` estava presente: um caminho que a ferramenta **nunca tinha visto** jamais podia ser apagado, porque nao havia registro de que ele um dia existira do outro lado. Isso dava uma garantia estrutural — **primeira execucao nunca apaga nada**.

No modelo direcional essa garantia **nao existe**. "Ausente na origem, presente no destino" e observavel na primeira execucao, sem historico algum, e com espelhamento ligado isso e ordem de exclusao. Uma raiz de origem apontada por engano — diretorio vazio, ponto de montagem que nao subiu, caminho remoto trocado — vira **exclusao integral do destino**, e nada na estrutura do algoritmo impede.

**Por isso `RF-40`, `RF-41`, `RF-47` e `RF-48` deixam de ser defesa em profundidade e passam a ser a defesa unica.** Elas foram escritas como camada redundante sobre uma garantia estrutural que agora nao existe, e precisam ser lidas com esse peso novo. `RF-41(a)` em particular — origem ilegivel ou incompleta **aborta em vez de interpretar ausencia como exclusao** — deixa de ser zelo e vira a barreira principal.

##### O que a linha de base ainda faz, por `DP-27b`

Memoria auxiliar de desempenho, e **nada alem disso**:

- guarda `content_hash` por caminho para dispensar releitura de arquivo grande cujo tamanho e `mtime` nao mudaram;
- **nao participa de decisao alguma**: perdida, corrompida ou ausente, o `sync` decide igual e so trabalha mais;
- por isso o tratamento de corrupcao **inverte** em relacao a `RF-42` original: base ilegivel e **descartada e reconstruida**, e nao motivo de recusa. Recusar execucao por causa de um cache seria transformar artefato descartavel em ponto unico de falha.

**Verificacao que fixa esse contrato:** executar o `sync` duas vezes com a base apagada entre as duas produz **o mesmo conjunto de operacoes** que executa-lo com a base intacta. Se as duas execucoes divergirem, a base esta arbitrando alguma coisa, e `DP-27b` foi violada.

#### 5.8.2 Tabela de decisao direcional

`O` = origem agora · `D` = destino agora. Comparacao de conteudo por `content_hash` (RF-34), nunca por carimbo de tempo (RF-39).

| O | D | Situacao | Acao |
|:--:|:--:|---|---|
| ✔ | — | Existe so na origem | **Transferir** |
| ✔ | ✔, `≠O` | Existe nos dois, conteudo diverge | **Transferir** — a origem prevalece, sempre |
| ✔ | ✔, `=O` | Existe nos dois, conteudo identico | Nenhuma (RF-33) |
| — | ✔ | Existe so no destino | **Apagar no destino — somente com espelhamento habilitado.** Sem espelhamento, nenhuma |
| — | — | Inexistente | Nenhuma |

**Cinco linhas, nenhuma classe de conflito.** A tabela nao tem ramo de arbitragem porque nao ha o que arbitrar: divergencia de conteudo e resolvida por definicao a favor da origem. E o que `DP-27` decidiu, e o custo esta declarado — **alteracao feita no destino e perdida sem aviso previo**, o que torna `RF-47` obrigatorio, e nao desejavel.

**Carimbo de tempo nao aparece em lugar algum desta tabela**, nem como desempate. `RF-39` proibia o carimbo na *deteccao* e `RF-39a` o admitia na *ordenacao*; sem ordenacao, a proibicao passa a ser total, e isso e simplificacao real: a unica etapa do `sync` que dependia de comparar relogios de duas maquinas deixou de existir.

#### 5.8.3 Politica de resolucao de conflito — ~~decidida~~ **sem objeto por `DP-27`**

> **Esta secao inteira perdeu objeto, e fica registrada em vez de apagada.** Ela decidia como arbitrar conflito entre dois lados que podiam ambos originar mudanca. Com `DP-27`, a origem prevalece por definicao e **nao ha conflito para arbitrar**.

| Item | O que decidia | Situacao sob `DP-27` |
|---|---|---|
| `DP-21` — ultimo a escrever vence | Qual lado prevalece em alteracao contra alteracao | **Sem objeto.** A origem prevalece sempre |
| `DP-22` — honrar a exclusao | Exclusao contra alteracao | **Sem objeto.** O estado da origem e a unica leitura |
| `RF-39a` — ordenacao por carimbo | Qual lado e mais recente | **Sem objeto.** Nenhuma etapa ordena lados |
| `RF-40a` — desempate ao lado recuperavel | Conflito de ordenacao indeterminada | **Sem objeto.** Nao ha ordenacao |
| Analise de qualidade do sinal de ordenacao | `rev`, `server_modified`, `client_modified` | **Sem objeto** para o `sync` |

**`DP-24` (sem teto de exclusoes) NAO cai — e fica pior.** Ele transferia integralmente a protecao contra exclusao em massa para `RF-41(a)`. Sob `DP-27`, `RF-41(a)` perdeu o companheiro estrutural que a linha de base fornecia (5.8.1), e passa a ser a **unica** barreira entre uma raiz de origem lida pela metade e a exclusao integral do destino.

##### O que sobrevive da analise, com valor aumentado

**A assimetria de recuperabilidade nao depende de conflito** e continua valendo:

| Lado que perde | Recuperavel? |
|---|---|
| **Remoto sobrescrito** | ✅ **Sim.** A Dropbox mantem historico de revisoes |
| **Local sobrescrito** | ❌ **Nao.** O conteudo anterior deixa de existir |
| **Remoto apagado** | ✅ Recuperavel pelo historico e lixeira |
| **Local apagado** | ❌ **Permanente** |

Consequencia direta sob `DP-27`: **`sync` com origem remota e destino local e o sentido perigoso**, porque toda sobrescrita e toda exclusao cai na coluna nao recuperavel. O sentido inverso erra para o lado do historico da Dropbox. Isso nao muda a decisao — muda o peso de `RF-47` e `RF-48` conforme o sentido, e o relatorio deve tornar o sentido visivel ao operador.

**`F-07` (revisoes e restauracao), no backlog, continua materialmente mais valioso** pelo mesmo motivo.

##### `RNF-27` continua justificado por outro caminho

`client_modified` a partir do `mtime` local foi implementado em `upload` para dar aos dois lados carimbo da mesma origem de relogio, e sustentava a **ordenacao** que agora nao existe. Permanece util por dois motivos independentes: preserva a data real do arquivo para quem o consulta na Dropbox, e e o unico sinal barato que permite a memoria auxiliar de `DP-27b` decidir se pode reaproveitar um `content_hash` sem reler o arquivo.

---

#### 5.8.4 Requisitos

| ID | Requisito | Prior. | Criterio de aceite |
|---|---|---|---|
| RF-37 | **Comando `sync` direcional, com a origem como autoridade** (`DP-27`) | P0 | `--origem` e `--destino` sao **obrigatorios**; a ausencia de qualquer um dos dois e recusada com codigo de uso invalido, e nunca suprida por valor presumido. Dado par de raizes valido, quando o `sync` conclui, entao **toda** a tabela de 5.8.2 foi aplicada item a item e **todo caminho presente na origem existe no destino com `content_hash` coincidente**; dada segunda execucao imediata sem alteracao externa, entao **nenhuma** operacao de escrita e emitida — **idempotencia verificavel**. Dado que a memoria auxiliar (`RF-38`) seja apagada entre duas execucoes, entao o **conjunto de operacoes decididas e identico** ao da execucao com ela intacta — verificacao que fixa `DP-27b` e reprova se a memoria voltar a arbitrar |
| RF-38 | **Memoria auxiliar de desempenho, sem papel na decisao** (`DP-27b`) | P1 *(rebaixado de P0)* | Guarda, por caminho, `content_hash` e os metadados baratos que permitem decidir se ele pode ser reaproveitado sem reler o arquivo — tamanho e `mtime` no lado local, `rev` no lado remoto. **Nao participa de decisao alguma:** dada memoria ausente, corrompida ou obsoleta, o `sync` decide igual e apenas trabalha mais. E vinculada ao **par de raizes** e a **identidade da conta** (RF-52), e a divergencia de qualquer um invalida a memoria em vez de reaproveita-la. Os caminhos registrados obedecem a `RF-50` |
| RF-39 | **Comparacao de conteudo exclusivamente por `content_hash` — carimbo de tempo nunca decide transferencia** | P0 | Dado qualquer caminho, quando o `sync` decide entre transferir e omitir, entao a decisao usa **apenas** `content_hash` (RF-34). Sob `DP-27` a proibicao passou a ser **total**: `RF-39a` admitia carimbo na etapa de ordenacao, e essa etapa deixou de existir. **Verificacao:** mutacao que introduza qualquer carimbo de tempo em qualquer ramo de decisao reprova. Carimbo e tamanho podem ser usados **somente** para decidir se um `content_hash` ja calculado pode ser reaproveitado da memoria auxiliar, nunca para decidir se algo mudou |
| ~~RF-39a~~ | ~~Ordenacao de vencedor em conflito por carimbo de tempo~~ | — | ❌ **SEM OBJETO por `DP-27`.** Ordenava qual lado prevalece em conflito; com a origem como autoridade nao ha conflito e nao ha ordenacao. Fica registrado, e nao apagado, porque a proibicao de carimbo em `RF-39` era **parcial** por causa dele e agora e total — quem ler `RF-39` sem este registro nao entende por que a excecao sumiu |
| ~~RF-40a~~ | ~~Desempate por preferencia ao lado recuperavel~~ | — | ❌ **SEM OBJETO por `DP-27`.** A assimetria de recuperabilidade que o motivava **continua valendo** e migrou para 5.8.3: deixa de orientar desempate e passa a qualificar o **sentido** do `sync`, porque origem remota com destino local poe toda perda na coluna nao recuperavel |
| RF-40 | Propagacao de exclusao **desabilitada por padrao**, habilitada por opcao explicita de espelhamento | P0 | Dado `sync` sem a opcao de espelhamento, quando um caminho existe no destino e **nao existe na origem**, entao ele e **preservado** e o relatorio o registra como divergencia nao propagada; dado `sync` com espelhamento, entao a exclusao ocorre apos as salvaguardas de `RF-41`. **Peso alterado por `DP-27`:** a garantia estrutural de que a primeira execucao nunca apagava nada — que vinha da matriz de tres estados, onde exclusao exigia `B` presente — **deixou de existir** (5.8.1). Este requisito e `RF-41` passam a ser a defesa inteira |
| RF-41 | 🔴 **Salvaguardas contra exclusao em massa — BLOQUEANTE.** Aplicadas **antes** de qualquer exclusao. `DP-24` dispensou o teto, o que torna a alinea **(a)** a unica protecao estrutural contra exclusao em massa | **P0 — bloqueante** | **(a) Travessia parcial e fatal para exclusao — criterio reforcado.** Dado que o percurso local tenha encontrado **qualquer** erro — diretorio ilegivel, ciclo de symlink, falha de `stat`, ponto de montagem ausente, limite de descritores, permissao negada em qualquer nivel —, entao a propagacao de exclusao e **integralmente desabilitada naquela execucao**, ainda que o espelhamento esteja ligado; a execucao prossegue apenas com envio e recebimento; o motivo e o caminho que falhou constam do relatorio; **o codigo de saida difere de `0`**. **A condicao e "qualquer erro", nao "erro na raiz"**: um subdiretorio ilegivel em qualquer profundidade desabilita a exclusao para a execucao inteira, e nao apenas para aquele ramo. **Verificacao obrigatoria:** casos que tornam ilegivel um subdiretorio em profundidade 1, em profundidade N, e que removem o ponto de montagem no meio da travessia — em todos, zero exclusoes emitidas; mutacao que restrinja o efeito ao ramo com erro reprova a suite. **(b) Guarda de origem vazia ou ausente:** dado que a raiz local nao exista, nao seja diretorio, ou esteja vazia enquanto a linha de base registra caminhos, entao a execucao e **recusada integralmente**, sem nenhuma escrita. **(c)** ~~Teto de exclusoes~~ — **dispensado por `DP-24`**. **(d) Exclusoes sao anunciadas antes de executadas:** a lista completa consta do relatorio e da saida estruturada antes da primeira exclusao |
| RF-42 | Ciclo de vida da memoria auxiliar: deteccao de corrupcao e versionamento de formato | P1 *(rebaixado de P0)* | Carrega **versao de formato** e e recusada quando a versao e desconhecida. **`DP-27b` INVERTE o tratamento de corrupcao:** memoria ilegivel ou inconsistente e **descartada e reconstruida**, e **nunca** motivo para recusar a execucao. Recusar um `sync` por causa de um cache transformaria artefato descartavel em ponto unico de falha — o oposto do que a versao anterior deste requisito determinava, quando o artefato ainda arbitrava decisao |
| RF-43 | Distincao estrita entre o **cursor de enumeracao da Dropbox** e a **linha de base de sincronizacao** | P0 | Sao dois artefatos distintos e nao podem ser conflacionados; dado que a Dropbox responda `reset` ao cursor de enumeracao, quando a politica `reiniciar` da taxonomia e aplicada, entao a enumeracao recomeca **e a linha de base permanece intacta**; dado teste que substitua a linha de base pelo cursor de enumeracao, entao a suite reprova |
| RF-44 | Simulacao de `sync` com plano completo de acoes | P0 | Dado `sync` em modo de simulacao, quando concluido, entao o plano lista toda operacao prevista por classe — enviar, receber, apagar local, apagar remoto, conflito — sem emitir **nenhuma** escrita local ou remota, e o codigo de saida e `0`; o plano de simulacao e **identico** ao conjunto de acoes que a execucao real emitiria sobre o mesmo estado |
| RF-45 | Incompatibilidade explicita entre `sync` e transferencia por fluxo | P1 | Dado `--origem` ou `--destino` com valor `-`, entao a operacao e recusada com diagnostico proprio: `sync` opera sobre arvores, e fluxo nao tem arvore. A recusa nomeia qual dos dois sinalizadores trazia o valor |
| RF-46 | Relatorio de `sync` com contadores proprios | P1 | Alem dos contadores de RF-36, o relatorio informa: enviados, recebidos, omitidos por conteudo identico, apagados no local, apagados no remoto, **conflitos por classe**, e caminhos ignorados por erro de travessia; dado qualquer conflito ou divergencia nao resolvida, entao o codigo de saida **difere de `0`** ainda que todas as demais operacoes tenham concluido |
| RF-47 | 🔴 **Registro nominal de toda perda de dado — a perda deixa de ser evitavel, mas nao pode ser invisivel** | **P0** | Dado que o `sync` sobrescreva conteudo por resolucao de conflito ou propague uma exclusao, entao **cada ocorrencia e listada nominalmente** no relatorio e na saida estruturada, com: **caminho**; **lado que perdeu** (local ou remoto); **classe do conflito**; **metodo de ordenacao aplicado** (diferenca contra a base, comparacao direta, ou desempate de RF-40a); e **marcacao de recuperabilidade** — `recuperavel` quando o lado perdedor for o remoto, cujo conteudo permanece no historico de revisoes da Dropbox, e **`permanente`** quando for o local. Dado execucao sem nenhuma perda, entao a secao consta vazia e explicitamente, e nao omitida. **Razao de ser:** `DP-21`, `DP-22` e `DP-24` recusaram as politicas cujo custo era visivel **antes** da acao; este requisito torna o custo visivel **depois**, o que nao contraria nenhuma delas — elas decidem o que fazer, nao o que registrar. Sem isso, uma sobrescrita errada por ordenacao imprecisa e indistinguivel de uma execucao limpa |
| RF-48 | **Reconhecimento obrigatorio na primeira execucao com espelhamento sobre um par de raizes ainda nao visto** | P0 | Dado `sync` com espelhamento sobre par de raizes sem registro anterior, entao a execucao **exige** simulacao previa (RF-44) ou sinalizador explicito de confirmacao; sem um dos dois, e recusada com codigo dedicado. **RAZAO REESCRITA POR `DP-27`, e ela se inverteu.** A versao anterior dizia que sem linha de base **nenhuma exclusao era possivel**, porque a matriz so previa exclusao com `B` presente, e o perigo era sobrescrita por criacao/criacao. Isso **ficou falso**: no modelo direcional, "ausente na origem, presente no destino" e observavel na primeira execucao, sem historico algum, e com espelhamento ligado **e ordem de exclusao integral**. Uma raiz de origem apontada por engano — diretorio vazio, ponto de montagem que nao subiu, caminho remoto trocado — apaga o destino inteiro na primeira execucao. O requisito continua o mesmo; o que mudou e que ele passou de precaucao a barreira |
| RF-50 | 🔴 **Toda decisao usa apenas o que a propria descida verificou** | **P0** | Dado qualquer caminho sobre o qual o `sync` decida transferir, apagar ou registrar, entao ele provem **exclusivamente** da travessia por descida de `RNF-28`, e **nunca** de re-resolucao de caminho a partir de texto, de reconstrucao absoluta ou de reaproveitamento de valor calculado fora da descida. **RAZAO AMPLIADA POR `DP-27`:** o risco composto `RSK-34` descrevia uma travessia escapada gravando caminhos de fora da raiz na linha de base, que a execucao seguinte apagaria como orfaos — **dano diferido**. No modelo direcional o dano deixou de ser diferido e virou **imediato**: a decisao de apagar le a arvore de agora, entao uma travessia escapada apaga no destino, na mesma execucao, caminho que nunca pertenceu ao par de raizes. A regra vale igual e o prazo encurtou. **Verificacao:** dado experimento em que a travessia e induzida a escapar, entao nenhum caminho fora da raiz entra em decisao alguma; mutacao que permita decisao por re-resolucao reprova a suite |
| RF-51 | **`unlink` trata o estado local, e nao apenas o token remoto** | P0 | Dado `unlink` confirmado, entao: **(a)** a revogacao remota e emitida e sua cascata sobre os access tokens derivados e advertida (RF-06a); **(b)** o **refresh token e removido do arquivo de credencial**, que sem ele e inutil; **(c)** por padrao **o arquivo de credencial e removido integralmente**, incluindo `app key` e `app secret`, que sao segredos e cuja permanencia contraria a semantica de "desvincular esta instalacao" — a preservacao de `app key` e `app secret` para relink posterior so ocorre sob sinalizador explicito; **(d)** **toda linha de base de `sync` e invalidada**, com a lista das raizes afetadas informada ao operador; **(e)** comando subsequente que exija autenticacao falha com codigo `3`, e nao com erro de rede |
| RF-52 | 🔴 **A memoria auxiliar e vinculada a identidade da conta, alem do par de raizes** | **P0** | Registra o **identificador da conta** sob a qual foi criada; dado que o identificador corrente **nao coincida**, entao a memoria e **descartada** e a execucao prossegue reconstruindo-a. **RAZAO REESCRITA POR `DP-27b`:** o caminho de destruicao original — base antiga apos troca de conta fazendo a matriz apagar arquivo local — **nao existe mais**, porque a memoria nao decide exclusao. O risco remanescente e outro e e de CORRECAO, nao de destruicao: `content_hash` reaproveitado de outra conta faz o `sync` **omitir uma transferencia que era necessaria**, e a divergencia passa despercebida justamente porque nenhuma operacao e emitida. **Verificacao:** troca de identidade entre duas execucoes descarta a memoria, e o conjunto de operacoes decididas e igual ao de uma execucao sem memoria alguma |
| RF-49 | **Concorrencia otimista na escrita remota usando `rev`** | P1 | Dado que o `sync` decida sobrescrever um arquivo remoto, quando o envio e emitido, entao ele carrega o `rev` esperado, obtido na leitura de estado daquela execucao; dado que o remoto tenha mudado entre a leitura e a escrita, entao a Dropbox **recusa** a escrita e a aplicacao trata o caminho como conflito novo, em vez de sobrescrever cegamente. **Razao:** o `rev` nao resolve ordenacao entre local e remoto — nao ha equivalente local —, mas e monotonico por arquivo no lado remoto e fecha a janela entre ler o estado e escrever sobre ele. Sem isso, uma alteracao remota ocorrida durante a travessia e perdida sem deteccao |
| RF-53 | 🔴 **Contrato dos dois lados: sentido declarado, tipo por consequencia** (`DP-27a`, `DP-28`) | **P0** | **(a)** `--origem` e `--destino` sao obrigatorios e nomeiam o PAPEL; a posicao na linha de comando nao significa nada. **(b)** `--enviar` ou `--receber` e **obrigatorio** e declara o SENTIDO; os dois juntos, ou nenhum, e recusa por uso invalido. **(c)** O tipo de cada lado e **consequencia do sentido, e nunca inferido**: `--enviar` implica origem local e destino remoto; `--receber` implica origem remota e destino local. **(d)** O sentido apurado e **declarado no relatorio antes de qualquer escrita**, inclusive em simulacao. **RAZAO DE `DP-28` TER FECHADO A INFERENCIA:** a versao anterior deste requisito apurava o tipo por existencia no sistema de arquivos e recusava o empate. Isso protegia o caso em que a ferramenta **sabe que nao sabe**, e deixava aberto o caso em que ela **acha que sabe e esta errada** — `--origem /fotos --destino ./fotos` com intencao de receber, onde `/fotos` existe no disco e `./fotos` nao, nao empata, e o `sync` enviaria sobrescrevendo o remoto com a arvore errada, sem nada parecer ambiguo. Com o sentido declarado a classe inteira deixa de existir. **Verificacao:** mutacao que reintroduza qualquer inferencia de tipo a partir do caminho reprova |

| ID | Requisito nao funcional | Categoria | Criterio de aceite |
|---|---|---|---|
| RNF-25 | Integridade e confinamento da linha de base | Seguranca / Confiabilidade | A linha de base e gravada com escrita atomica — arquivo temporario e substituicao — de modo que interrupcao **nunca** deixe base parcial; permissao `0600`; dado que a interrupcao ocorra durante a gravacao, entao a base anterior permanece valida e utilizavel; a base **nao** guarda credencial nem conteudo de arquivo, apenas metadados de caminho |
| RNF-26 | Delimitacao do estado persistente autorizado | Arquitetura | O estado persistente autorizado se limita a: **memoria auxiliar de `content_hash` do `sync`** (`RF-38`) e **cursor de enumeracao**, ambos vinculados ao par de raizes e a identidade da conta (`RF-52`). Qualquer outra escrita persistente — indice auxiliar, arquivo de trava — permanece **fora de escopo** e constitui mudanca de escopo. Verificavel por auditoria dos caminhos de escrita. **Localizacao fixada por `DP-23`:** `$XDG_STATE_HOME` com recuo para `~/.local/state`. **CONTRADICAO RESOLVIDA POR `DP-27b`:** a redacao anterior autorizava a "linha de base de sincronizacao" e proibia nominalmente **cache de resumos** — e `DP-27b` rebaixou a base a exatamente isso. O que a proibicao queria impedir era estado que **decide**; a memoria auxiliar nao decide nada (`RF-38`), e a delimitacao passa a ser essa: **nenhum artefato persistente participa de decisao** |
| RNF-28 | 🔴 **Travessia por descida com nome relativo — mitigacao estrutural de `RSK-24`.** Adotada em `DP-26` | Seguranca | A travessia local desce **um nivel por vez, mantendo o diretorio aberto**, e opera sempre com **nome relativo** — nunca reconstruindo caminho absoluto em texto para reabrir. Em `bash`, `cd` referencia o **inode**, nao o texto; e o equivalente em shell de `openat` com `O_NOFOLLOW` por componente. **Criterio:** dado o experimento de troca por symlink em componente intermediario durante a travessia, quando a implementacao usa caminho absoluto reconstruido, entao o alvo **fora da raiz** e alcancado — comportamento que reprova; quando usa descida com nome relativo, entao **na mesma janela de ataque o alvo sobrevive**. Auditoria estatica: nenhum ponto da travessia reconstroi caminho absoluto para reabrir um componente ja percorrido. ⚠️ **Limite declarado, nao escondido:** protege os componentes **ja percorridos**, e **nao** a troca ocorrida imediatamente antes de descer. E **reducao de superficie, nao eliminacao** — `RSK-24` permanece no registro com probabilidade reduzida, e nao encerrado |
| RNF-27 | **`client_modified` sempre definido no envio** | Corretude | Dado qualquer envio emitido por esta aplicacao, entao ele define `client_modified` a partir do `mtime` do arquivo local. **PROPOSITO REESCRITO POR `DP-27`.** O requisito nasceu para dar aos dois lados carimbos do **mesmo relogio** e sustentar a ordenacao de conflito; essa ordenacao deixou de existir, e o restante do texto original — metodos (2) e (3) de `RF-39a`, escolha de chave de ordenacao — ficou **sem objeto**. O requisito sobrevive por dois motivos independentes da ordenacao: **(a)** preserva a data real do arquivo para quem o consulta pela Dropbox, e **(b)** e o sinal que permite a memoria auxiliar de `RF-38` decidir se pode reaproveitar um `content_hash` sem reler o arquivo. **`server_modified` continua proibido como sinal de decisao** — e o instante de recebimento pela Dropbox, nao o de autoria do conteudo —, e agora a proibicao e mais simples: nenhum carimbo decide coisa alguma (`RF-39`) |

#### 5.8.5 Requisitos existentes afetados

| Requisito | Efeito da entrada do `sync` |
|---|---|
| RF-34 (`content_hash`) | ⬆️ **Criticidade elevada.** Deixa de ser apenas verificacao de integridade e passa a ser a **primitiva de comparacao** de toda a matriz de 5.8.2. Um defeito aqui produz sincronizacao errada, nao apenas alarme falso |
| RF-33 (omissao por conteudo identico) | Reaproveitado como a terceira linha da tabela de 5.8.2: conteudo identico nos dois lados nao produz transferencia |
| RNF-27 (`client_modified` no envio) | ⚠️ **Justificativa trocada por `DP-27`.** Sustentava a ordenacao de conflito, que deixou de existir. Sobrevive por dois motivos independentes: preserva a data real do arquivo do lado remoto, e e o sinal que permite a memoria auxiliar decidir se reaproveita um `content_hash` sem reler |
| `PRJ-DEC-07` / `DP-09` (sem estado local) | Continuam revogado e reaberta — mas por **escolha** (`DP-27b`), e nao mais por necessidade de correcao. O modelo direcional decide sem estado algum |
| RF-16 (listagem) e RNF-23 (paginacao) | O `sync` percorre arvores inteiras; `limit` explicito e paginacao passam a ser caminho quente, nao caso de borda |
| RF-21 (exclusao com confirmacao) | Confirmacao item a item e **inviavel** em lote. O `sync` substitui por RF-40 e RF-41: opt-in de espelhamento, teto, anuncio previo e recusa sob travessia parcial |
| RNF-09 (sem estado parcial) | Precisa de definicao propria: o `sync` e multi-operacao por natureza. Sob `DP-27` a definicao **simplifica**: nao ha estado a manter coerente entre operacoes, porque a memoria auxiliar nao decide nada. "Parcial" passa a significar apenas **conjunto de transferencias concluidas menor que o planejado**, relatado item a item por `RF-36` e `RF-47` |
| RNF-20 (confinamento) | Passa a operar sobre **percurso recursivo**, que era justamente o caso ausente do escopo quando `RSK-24` foi aceito |
| RNF-21 (concorrencia) | `RES-11` proibe listagem simultanea para o mesmo usuario; o `sync` deve respeitar mesmo percorrendo arvores grandes |
| RF-31, RF-32 (fluxo) | Declarados incompativeis com `sync` em RF-45 |

#### 5.8.6 Conjunto final de comandos — `DP-06` e `DP-25`

**Nove comandos no MVP:** `upload`, `download`, `list`, `delete`, `info`, `sync`, **`config`**, **`unlink`** e **`space`**.

`DP-25` confirmou a entrada de `config` (RF-01), `unlink` (RF-04, RF-06a, **RF-51**) e `space` (RF-26). A presuncao registrada na versao anterior — de que `config` permaneceria por necessidade operacional — **foi confirmada em vez de assumida**, conforme a disciplina de `RSK-26`.

**Fora do escopo, mantidos no backlog:** `mkdir` (RF-18), `move` (RF-19), `copy` (RF-20), `search` (RF-22), `share` (RF-23), `saveurl` (RF-14), `monitor` (RF-24).

> **Consequencia da entrada de `unlink` sobre o estado local.** `unlink` revoga o refresh token, e a Dropbox invalida em cascata todos os access derivados (RF-06a, RES-12). Isso deixa **dois artefatos locais orfaos**: a credencial gravada, que fica inutil, e a **linha de base do `sync`**. O tratamento foi especificado em **RF-51**, e a analise revelou um caminho de destruicao de dado que gerou **RF-52** — relink a uma conta diferente com base antiga preservada pode apagar arquivos locais do usuario.

---

### 5.6 Bloco 0 — requisitos de base aprovados

Correcoes de defeitos confirmados no modelo de referencia, aprovadas como base nao negociavel. **Nao sao funcionalidades novas** e nao constituem justificativa do projeto; sao a condicao para que a reimplementacao nao nasca com os mesmos defeitos.

| ID do bloco | Correcao | Requisito que a implementa | Divergencia de origem |
|---|---|---|---|
| B0-01 | Uso exclusivo de endpoints vigentes | RNF-12 | DIV-01, DIV-02 |
| B0-02 | Segredo nunca em `argv` | RNF-03 | DIV-03 |
| B0-03 | Interpretacao robusta de resposta | RNF-11 | DIV-04 |
| B0-04 | Area temporaria segura | RNF-05 | DIV-05 |
| B0-05 | Modularizacao e suite de testes | RNF-13, RNF-14, RNF-16 | DIV-06 |
| B0-06 | Nomes com espacos, acentos e caracteres especiais | RNF-10 | — |

### 5.7 Fora do escopo desta versao

Registrado para impedir reabertura por engano.

| Item | Situacao | Consequencia |
|---|---|---|
| F-03 — retomada de transferencia interrompida | ❌ Backlog | **Unico corte que preserva o MVP sem estado local.** A mitigacao disponivel no escopo e a retentativa por parte dentro da mesma execucao (RF-09), que cobre falha transitoria mas nao queda do processo |
| F-06, F-12, F-14 | ❌ Backlog | Exigiriam estado local persistente. Promover qualquer uma reabre DP-09 e aciona o handoff do DBA |
| F-07 a F-11, F-13, F-15 a F-22 | ❌ Backlog | Sem impacto arquitetural; podem ser incorporadas em versoes futuras |
| RF-06 — Dropbox Business/Team | ❌ Fora de escopo definitivo | Decidido em DP-04 |

---

## 6. Requisitos nao funcionais

| ID | Requisito | Categoria | Criterio de aceite |
|---|---|---|---|
| RNF-01 | ✅ **Descongelado na v0.5.** A aplicacao executa em **Linux** com **`bash` 4.4 ou superior**, com a versao minima verificada em tempo de execucao | Portabilidade | Dado shell abaixo de `bash` 4.4, quando a aplicacao e iniciada, entao ela recusa a execucao com mensagem explicita nomeando a versao encontrada e a exigida; dado `bash` 4.4 ou superior em Linux, entao a suite executa integralmente. **Base:** decisao do solicitante em DP-07 — "so cURL, `bash` 4+, Linux". O numero **4.4 e refinamento tecnico dessa decisao, nao decisao nova**: `declare -A` e `${var,,}` pedem 4.0, `declare -g` pede 4.2, e a harness de teste pede 4.4 por expandir `"${casos[@]}"` com array vazio sob `set -u`. **Consequencia material mantida em registro: RHEL 6 (`bash` 4.1) fica fora.** macOS, *BSD, BusyBox `ash` e `sh` POSIX estao fora de escopo por decorrencia |
| RNF-02 | ✅ **Fixado na v0.5 por DP-08.** A **unica** dependencia externa e `cURL`, alem dos utilitarios de instalacao base. **`jq` nao e dependencia**, e nao ha caminho alternativo condicional que o utilize | Portabilidade | Dado ambiente com apenas `bash` 4.4, `cURL` e coreutils, quando os comandos essenciais sao executados, entao todos concluem com sucesso; dado utilitario obrigatorio ausente, entao a aplicacao falha com mensagem nomeando o utilitario. **Auditoria estatica nao encontra invocacao de `jq` em nenhum ponto do codigo.** O utilitario de resumo SHA-256 exigido por `lib/hash` integra os coreutils e nao constitui dependencia adicional |
| RNF-03 | Nenhum segredo pode trafegar em `argv`, ficar visivel na tabela de processos, ser escrito em log ou exportado para o ambiente de processos filhos | Seguranca | Dado um comando autenticado em execucao, quando a tabela de processos e inspecionada por outro usuario do host, entao nenhum token, senha ou app secret e visivel; a inspecao dos logs em verbosidade maxima nao revela segredos. **Divergencia conhecida: o projeto de referencia viola este requisito** (ver secao 9) |
| RNF-04 | ✅ **Fixado na v0.5 por DP-11.** Credencial persistida em arquivo com permissao `0600`, localizado sob `$XDG_CONFIG_HOME` com recuo para `~/.config`, com `umask` restritivo durante a execucao. **A credencial nao pode ser fornecida por variavel de ambiente** | Seguranca | Dado arquivo de configuracao criado pela aplicacao, quando as permissoes sao verificadas, entao o modo e `0600` e o caminho respeita a convencao XDG; **dado arquivo com permissao mais ampla, entao o preflight recusa a execucao** — nao apenas alerta; dado `$XDG_CONFIG_HOME` definido, entao ele prevalece sobre `~/.config`; dado que a credencial seja oferecida por variavel de ambiente, entao ela **e ignorada**, e nenhum caminho de codigo a le do ambiente. **Contrapartida operacional registrada:** uso em container efemero e em CI exige montagem de arquivo com permissao correta, e nao injecao de variavel |
| RNF-05 | Arquivos temporarios criados com nome imprevisivel, em diretorio controlado, removidos deterministicamente inclusive em interrupcao | Seguranca | Dada interrupcao por sinal durante um envio em partes, quando o processo encerra, entao nenhum arquivo temporario permanece; a criacao usa `mktemp` e nao nome derivado de valor previsivel |
| RNF-06 | Comunicacao exclusivamente por TLS com verificacao de certificado; desativacao da verificacao, se existir, deve ser opcional, nao padrao e emitir alerta | Seguranca | Dado ambiente com certificado invalido, quando um comando e executado sem sinalizador de excecao, entao a operacao falha; com o sinalizador, um alerta e emitido na saida de erro |
| RNF-07 | Politica de retentativa condicionada a **duas dimensoes**: a classe do erro **e** a idempotencia da operacao. Recuo exponencial com variacao aleatoria, respeitando `Retry-After` | Confiabilidade | Dada resposta `429` com `Retry-After: 5`, quando a operacao e repetida, entao a espera e de ao menos 5 segundos; dada resposta `400`, entao nao ha retentativa; dada resposta `401`, entao ha uma renovacao de token e uma repeticao; **dada resposta `5xx` ou falha de transporte (`http=0`) em operacao idempotente, entao ha recuo exponencial e repeticao; dada a mesma condicao em operacao NAO idempotente, entao o resultado e `indeterminado` e nao ha repeticao automatica**; o numero maximo de tentativas e configuravel e documentado. **Ajustado na v0.4:** a redacao original tratava `5xx` como retentavel de forma incondicional, porque foi escrita antes de a dimensao de idempotencia existir. Repetir cegamente uma escrita nao idempotente apos `5xx` pode duplicar efeito ja aplicado no servidor |
| RNF-08 | Mapeamento explicito da semantica de erro da Dropbox para mensagens e codigos de saida da aplicacao | Confiabilidade | Para cada classe (`400`, `401`, `403`, `409`, `429`, `5xx`) existe teste que verifica mensagem e codigo de saida correspondentes, com correspondencia por prefixo do `error_summary` |
| RNF-09 | Operacoes de escrita nao podem deixar estado parcial silencioso no destino | Confiabilidade | Dada interrupcao durante um envio em partes, quando o processo encerra, entao nenhum arquivo truncado e visivel no destino remoto e a saida indica que a operacao nao foi concluida |
| RNF-10 | Tratamento correto de nomes de arquivo com espacos, caracteres unicode, acentuacao, caracteres especiais de shell **e quebra de linha** | Corretude | Dado conjunto de nomes de teste incluindo espacos, acentos, aspas, cifrao e **caractere de nova linha**, quando envio, listagem e recebimento sao executados, entao todos os nomes sao preservados sem corrupcao ou expansao indevida, e nenhum caminho contendo nova linha e silenciosamente truncado ou aceito como valido. Ver DIV-16 quanto a interacao com RF-28 e RF-35 |
| RNF-11 | ⬆️ **Criticidade elevada na v0.5 por DP-08.** O tratamento de resposta JSON — feito por **interpretador proprio em shell** — deve ser resistente a variacao de formatacao, ordem de campos e valores contendo delimitadores | Corretude | Dado corpo JSON com espacamento alterado, ordem de campos diferente, campos aninhados, e valor de texto contendo `"`, `:`, `\`, `{`, `}` e sequencias de escape, quando a resposta e interpretada, entao os campos extraidos permanecem corretos; dado JSON malformado, entao a falha e explicita e nao produz valor errado com status de sucesso. **Divergencia conhecida: extracao por expressao regular, como no projeto de referencia (DIV-04), nao satisfaz este criterio.** DP-08 escolheu a opcao de dependencia zero, que e justamente aquela com maior risco de defeito silencioso — este conjunto de teste deixa de ser desejavel e passa a ser **a principal defesa do componente** |
| RNF-12 | Somente endpoints vigentes da Dropbox API v2 podem ser utilizados; endpoints retirados ou depreciados sao proibidos | Conformidade | Auditoria estatica do codigo nao encontra referencia a `/2/files/search`, `/2/files/copy`, `/2/files/move`, `/2/files/delete` ou `/2/files/create_folder` sem sufixo `_v2` |
| RNF-13 | Analise estatica de shell sem alertas nao suprimidos, com supressoes justificadas individualmente | Qualidade | Execucao de `shellcheck` em todos os arquivos retorna codigo `0`; cada diretiva de supressao possui comentario com justificativa |
| RNF-14 | Suite de testes automatizados cobrindo comandos, tratamento de erro e casos de borda, executavel sem credencial real | Qualidade | A suite executa em ambiente sem rede usando duplo de teste do servico HTTP; a cobertura dos caminhos de erro mapeados em RNF-08 e integral |
| RNF-15 | Documentacao de instalacao, configuracao, comandos, codigos de saida e operacao em ambiente automatizado | Manutenibilidade | Existe `README` cobrindo instalacao, primeiro uso e todos os comandos; a tabela de codigos de saida de RF-29 esta publicada |
| RNF-16 | Estrutura modular com responsabilidades separadas, evitando arquivo unico monolitico | Manutenibilidade | Nenhuma unidade de codigo excede o limite acordado de linhas; autenticacao, transporte HTTP, interpretacao de resposta e comandos residem em unidades distintas com dependencia unidirecional |
| RNF-17 | Licenca definida, coerente com a decisao de licenciamento, com cabecalho de copyright e arquivo de licenca no repositorio | Conformidade legal | Existe arquivo de licenca na raiz; a licenca escolhida e compativel com a decisao registrada em DP-01; nenhuma reclamacao de terceiros pendente |
| RNF-18 | Idioma das mensagens de interface e da documentacao definido e consistente | Usabilidade | Todas as mensagens seguem o idioma definido em DP-15, sem mistura de idiomas na mesma saida |
| RNF-19 | Adaptacao explicita ao contexto de execucao pela deteccao de terminal associado, cobrindo os dois modos de uso confirmados em DP-03 | Operacao | Dado execucao **sem** terminal associado, quando qualquer comando e executado, entao nenhuma solicitacao de entrada bloqueia o processo, nenhuma barra de progresso ou sequencia de controle de terminal e emitida, a saida assume o formato estruturado e operacoes que exigiriam confirmacao falham com codigo `2`; dado execucao **com** terminal associado, entao confirmacoes interativas e indicacao de progresso ficam disponiveis. O comportamento deve ser sobreponivel por sinalizador explicito em ambos os sentidos, para permitir teste automatizado dos dois caminhos |
| RNF-20 | **Menor privilegio e confinamento nos dois espacos de nomes — remoto e local.** Ampliado na v0.4, com a ampliacao aceita pelo solicitante | Seguranca | **(a) Escopos:** o assistente de configuracao orienta a conceder **apenas** os escopos OAuth exigidos pelos comandos habilitados, e o conjunto solicitado e documentado. **(b) Confinamento remoto:** existe opcao de configuracao que restringe o caminho remoto raiz alcancavel, e operacao dirigida a caminho fora dessa raiz e recusada **antes de qualquer chamada a API**. **(c) Confinamento local:** existe raiz local configuravel, e caminho fora dela e recusado **antes de qualquer acesso a disco**; a verificacao usa **resolucao fisica de symlinks**, nao comparacao textual de prefixo. **(d)** Dado symlink absoluto, symlink relativo, symlink para arquivo de sistema, ciclo de symlinks, travessia `..` acima da raiz, caminho absoluto externo, raiz que e ela propria um symlink, e prefixo semelhante porem distinto (`/backups2` contra `/backups`), entao **todos os oito vetores sao recusados**. **(e) Raiz `/`:** so e aceita mediante opt-in explicito; sem ele a operacao **falha fechado**. **(f)** Toda operacao destrutiva exige confirmacao explicita, sem excecao em modo automatizado |
| RNF-21 | Concorrencia segura em relacao aos limites da Dropbox | Confiabilidade | Nao ha chamadas simultaneas de `list_folder` ou `list_folder/continue` para o mesmo usuario dentro de uma execucao (RES-11); caso paralelismo venha a ser habilitado, o limite e configuravel, o valor padrao e `1` e a documentacao registra a relacao entre paralelismo e incidencia de limite de taxa |
| RNF-24 | **Contexto nomeado no analisador de resposta, com nome de origem obrigatoriamente interna.** Novo na v0.7 (`E3-01`) | Corretude / Seguranca | O analisador mantem estado em **contextos nomeados**, de modo que analisar um corpo de erro **nao destrua uma analise em curso** — padrao previsto para a Etapa 3, em que `lib/http` precisa interpretar erro no meio de uma listagem paginada. **Restricao vinculante, verificavel e nao negociavel: o nome do contexto e escolhido pelo projeto e NUNCA deriva de dado externo** — nao pode vir de campo de resposta, caminho de arquivo, argumento de usuario, variavel de ambiente ou qualquer entrada nao controlada. O nome e restrito a **minusculas e sublinhado** (`[a-z_]+`). **Criterios:** dado listagem em curso e corpo de erro analisado em contexto distinto, quando a analise do erro conclui, entao o estado da listagem permanece integro e utilizavel; dado nome de contexto contendo qualquer caractere fora de `[a-z_]`, entao a operacao e recusada; **dada auditoria estatica, entao nenhum ponto do codigo compoe nome de contexto a partir de valor de origem externa**; dada mutacao que permita nome de origem externa, entao a suite reprova. **Razao de ser:** a composicao de chave que fechou `E2-01` so e injetiva porque o espaco de nomes e controlado. Se o nome pudesse vir de fora, a classe do `E2-01` retornaria por outra porta. Isto e **requisito**, nao convencao de estilo |
| RNF-23 | **Teto de entrada do analisador de resposta e paginacao obrigatoria com `limit` explicito.** Novo na v0.6, derivado de medicao real | Confiabilidade / Desempenho | `lib/json` tem **teto de entrada de 256 KiB** — reduzido de 4 MiB por medicao, ja que 4 MiB extrapolava para ~86 s de analise. Consequencia vinculante: **toda chamada que retorne colecao deve enviar `limit` explicito**, dimensionado para manter a resposta abaixo do teto, e paginar por cursor. Dado diretorio remoto com numero de itens suficiente para ultrapassar 256 KiB de resposta, quando a listagem e executada, entao a operacao **conclui com sucesso por paginacao**, e nao falha por recusa de analise; dado que uma chamada de colecao seja emitida **sem** `limit`, entao a auditoria estatica reprova. **Razao de ser:** sem isso, uma pasta grande produziria falha em `lib/json` — um erro de analise interno, sem relacao aparente com o tamanho da pasta — em vez de erro do servico ou de paginacao correta. O modo de falha seria confuso e o diagnostico, enganoso |
| RNF-22 | **Restricao de entrada de `lib/output` decorrente da politica de redacao de segredo.** Novo na v0.4, **ampliado na v0.5 para os dois modos de terminador** | Seguranca / Corretude | A redacao de cabecalho sensivel consome **o restante da linha** — comportamento deliberado, por ser o lado correto do erro em RNF-03. Consequencia vinculante: `lib/output` **nao pode** concatenar campos de diagnostico na mesma linha de um cabecalho sensivel. Dado registro de diagnostico contendo cabecalho sensivel **e** identificador de correlacao de requisicao, quando a saida e emitida, entao o identificador aparece em **linha propria** e sobrevive a redacao; dado que a implementacao os coloque na mesma linha, entao o teste reprova. Preserva RF-30, cuja unica razao de existir e reter esse identificador. **⚠️ Vale nos dois modos de terminador (DIV-16b):** a politica de redacao opera sobre **quebras de linha**, nao sobre terminadores de registro. No modo `--null`, varios registros podem compartilhar a mesma linha fisica, de modo que a concatenacao indevida pode destruir **mais** conteudo do que destruiria no modo padrao. **Exige caso de teste dedicado em cada modo** |

---

## 7. Matriz de rastreabilidade

Rastreabilidade prospectiva: requisito → componente previsto no [System Design](../arquitetura/system-design.md) → tipo de evidencia de teste esperada. Os identificadores de teste serao substituidos por referencias reais quando a suite existir.

| Requisito | Componente previsto | Evidencia de teste esperada |
|---|---|---|
| RF-01, RF-03, RF-04 | `cmd/config`, `lib/config`, `lib/auth` | TC-AUTH-01..03 — configuracao, validacao e revogacao |
| RF-02 | `lib/auth`, `lib/http` | TC-AUTH-04 — renovacao de token e repeticao apos `401` |
| RF-05 | `lib/config` | TC-PROF-01 — isolamento entre perfis |
| ~~RF-06~~ | — | Removido: fora de escopo por DP-04 |
| RF-06a | `cmd/unlink`, `lib/auth` | TC-AUTH-05 — advertencia de revogacao em cascata e exigencia de confirmacao |
| RF-07, RF-10 | `cmd/upload`, `lib/http` | TC-UP-01..03 — envio simples e politicas de colisao |
| RF-08, RF-09 | `cmd/upload`, `lib/transfer` | TC-UP-04..06 — sessao em partes, retentativa e integridade |
| RF-11 | `cmd/download`, `lib/transfer` | TC-DL-01..02 — recebimento e verificacao de `content_hash` |
| RF-12, RF-13 | `cmd/upload`, `cmd/download`, `lib/walk` | TC-REC-01..03 — recursao, hierarquia e exclusoes |
| RF-14 | `cmd/saveurl` | TC-URL-01 — job assincrono ate conclusao |
| RF-15 | `lib/cli`, todos os `cmd/*` de escrita | TC-DRY-01 — ausencia de chamada de escrita |
| RF-16, RF-17 | `cmd/list`, `cmd/stat`, `lib/json` | TC-LS-01..03 — paginacao por cursor e metadados |
| RF-18..RF-21 | `cmd/mkdir`, `cmd/move`, `cmd/copy`, `cmd/delete` | TC-FS-01..05 — operacoes remotas e idempotencia |
| RF-22 | `cmd/search` | TC-SRC-01 — uso de `search_v2` e paginacao |
| RF-23 | `cmd/share` | TC-SHR-01..02 — criacao e reaproveitamento de link |
| RF-24 | `cmd/monitor` | TC-MON-01 — deteccao de alteracao e tempo limite |
| RF-25, RF-26 | `cmd/account` | TC-ACC-01..02 — informacoes de conta e espaco |
| RF-27, RF-28, RF-29 | `lib/cli`, `lib/output`, `lib/errors` | TC-CLI-01..04 — ajuda, saida estruturada e codigos de saida |
| RF-30 | `lib/log` | TC-LOG-01..02 — verbosidade e ausencia de segredo |
| RNF-01, RNF-02 | `bin/dbx`, `lib/preflight` | TC-ENV-01..02 — versao de shell e dependencias |
| RNF-03, RNF-04, RNF-05, RNF-06 | `lib/auth`, `lib/config`, `lib/http`, `lib/tmp` | TC-SEC-01..05 — tabela de processos, permissoes, temporarios e TLS |
| RNF-07, RNF-08, RNF-09 | `lib/http`, `lib/errors`, `lib/transfer` | TC-ERR-01..07 — uma verificacao por classe de erro HTTP |
| RNF-10, RNF-11 | `lib/json`, `lib/path` | TC-ENC-01..02 — nomes especiais e variacao de JSON |
| RNF-12 | Auditoria estatica do repositorio | TC-API-01 — ausencia de endpoint retirado ou depreciado |
| RNF-13, RNF-14, RNF-16 | Pipeline de qualidade | TC-QA-01..03 — analise estatica, suite e limites estruturais |
| RNF-15, RNF-17, RNF-18 | Documentacao e licenca | Revisao documental na aprovacao final |
| RF-31 | `cmd/upload`, `lib/transfer`, `lib/stream` | TC-STR-01..03 — envio por fluxo, ausencia de materializacao em disco, falha da origem no meio |
| RF-32 | `cmd/download`, `lib/transfer`, `lib/stream` | TC-STR-04..06 — recebimento por fluxo, integridade, consumidor encerrando antes do fim |
| RF-33 | `lib/transfer`, `lib/hash` | TC-INC-01..04 — omissao por conteudo identico, transferencia quando o conteudo difere com metadados iguais, ausencia no destino, sinalizador de forcar |
| RF-34 | `lib/hash` | TC-HSH-01..05 — vetor de teste oficial, arquivo vazio, sub-bloco, bloco exato, multiplos blocos com resto |
| RF-35 | `lib/output`, documentacao | TC-CON-01..02 — versao do contrato declarada, estabilidade de campos e codigos entre versoes compativeis |
| RF-36 | `lib/report`, `lib/output` | TC-REP-01..03 — contagens, disponibilidade na apresentacao estruturada, codigo de saida com falha parcial |
| RNF-19 | `lib/cli`, `lib/output` | TC-CLI-05..07 — execucao com e sem terminal associado, e sobreposicao por sinalizador explicito |
| RNF-20 | `lib/config`, `lib/path`, `cmd/config` | TC-SEC-06..08 — escopos minimos documentados, confirmacao obrigatoria em operacao destrutiva; **TC-SEC-09..17 — os oito vetores de confinamento** (symlink absoluto, relativo, para arquivo de sistema, ciclo, `..` acima da raiz, absoluto externo, raiz que e symlink, prefixo semelhante) **e o opt-in da raiz `/`** |
| RNF-22 | `lib/output`, `lib/log` | TC-RED-01..02 — identificador de correlacao em linha propria sobrevive a redacao; reprovacao se concatenado a cabecalho sensivel; **um caso por modo de terminador** |
| RNF-23 | `lib/json`, `lib/http`, `cmd/list`, `cmd/search` | TC-PAG-01..03 — pasta que ultrapassa 256 KiB em resposta unica conclui por paginacao; auditoria estatica reprova chamada de colecao sem `limit`/`max_results` explicito |
| RF-39 | `lib/sync`, `lib/hash` | TC-SYN-01..05 — comparacao so por `content_hash`; mutacao que introduza carimbo em qualquer ramo de decisao reprova |
| ~~RF-39a, RF-40a~~ | — | ❌ Sem objeto por `DP-27`: nao ha conflito a ordenar nem a desempatar |
| RNF-28 | `lib/walk` | TC-TOC-01..03 — experimento de troca por symlink em componente intermediario: reprova com caminho absoluto reconstruido, sobrevive com descida e nome relativo; auditoria confirma ausencia de reconstrucao absoluta |
| RF-50 | `lib/walk`, `lib/sync` | TC-BASE-01..02 — travessia induzida a escapar nao produz caminho para transferir nem para apagar; mutacao que permita decisao por re-resolucao reprova |
| RF-51 | `cmd/unlink`, `lib/config`, `lib/state` | TC-UNL-01..05 — revogacao remota, remocao do refresh token, remocao integral do arquivo por padrao, invalidacao das bases, codigo `3` em comando subsequente |
| RF-52 | `lib/state` | TC-CONTA-01 — troca de identidade de conta entre execucoes descarta a memoria, e o conjunto de operacoes decididas iguala o de execucao sem memoria |
| RF-41 | `lib/sync`, `lib/walk` | TC-DEL-01..06 — subdiretorio ilegivel em profundidade 1 e em profundidade N, ponto de montagem removido durante a travessia, raiz vazia com base povoada; **zero exclusoes em todos**; mutacao que restrinja o efeito ao ramo com erro reprova |
| RF-47 | `lib/sync`, `lib/report`, `lib/output` | TC-PERDA-01..04 — cada sobrescrita e exclusao listada nominalmente com lado perdedor, metodo e marcacao de recuperabilidade; secao vazia explicita quando nao ha perda |
| RF-48 | `cmd/sync`, `lib/state` | TC-INI-01..02 — primeira execucao com espelhamento sem base exige simulacao ou confirmacao |
| RF-49 | `lib/sync`, `lib/http` | TC-REV-01..02 — escrita com `rev` esperado; alteracao remota concorrente vira conflito, nao sobrescrita |
| RF-37, RF-53 | `cmd/sync`, `lib/path` | TC-LADO-01..05 — `--origem`/`--destino` obrigatorios; `--enviar`/`--receber` obrigatorio e mutuamente exclusivo; sentido declarado antes de qualquer escrita; mutacao que infira tipo a partir do caminho reprova |
| RF-38, RF-42 | `lib/state` | TC-MEM-01..03 — memoria apagada entre execucoes nao muda o conjunto de operacoes; memoria corrompida e descartada e reconstruida, e nao recusa a execucao |
| RNF-27 | `lib/transfer`, `lib/http` | TC-CM-01..02 — `client_modified` definido em todo envio; auditoria confirma que `server_modified` nao e chave de ordenacao |
| RNF-24 | `lib/json`, `lib/http` | TC-CTX-01..04 — analise de corpo de erro preserva listagem em curso; nome fora de `[a-z_]` recusado; auditoria estatica reprova nome composto a partir de origem externa; **mutacao que permita nome externo reprova a suite** |
| RNF-21 | `lib/http`, `lib/walk` | TC-ERR-08 — ausencia de chamadas simultaneas de listagem para o mesmo usuario |

---

## 8. Historias de usuario prioritarias

Amostra representativa para refinamento. As demais historias derivam diretamente da secao 5.

### HU-01 — Configurar acesso a conta Dropbox

**Como** administrador de sistemas
**Quero** configurar o acesso a minha conta Dropbox em um servidor sem navegador local
**Para que** eu possa automatizar transferencias sem digitar credenciais a cada execucao

Criterios de aceite:
1. **Dado** um servidor sem configuracao previa, **quando** eu executo o comando de configuracao, **entao** recebo instrucoes numeradas para registrar o aplicativo e uma URL de autorizacao para abrir em outra maquina.
2. **Dado** que informei app key, app secret e o codigo de autorizacao, **quando** a troca por refresh token e concluida, **entao** a configuracao e gravada com permissao `0600` e a operacao confirma sucesso.
3. **Dado** que informei um codigo de autorizacao invalido, **quando** a troca e tentada, **entao** recebo mensagem indicando codigo invalido, nenhum arquivo de configuracao e criado e o codigo de saida e diferente de `0`.
4. **Dado** que a configuracao ja existe, **quando** executo o comando de configuracao novamente, **entao** sou avisado e a configuracao existente nao e sobrescrita sem confirmacao explicita.

Rastreabilidade: RF-01, RF-03, RNF-03, RNF-04, RNF-19.

### HU-02 — Enviar arquivo volumoso em rotina noturna

**Como** operador de rotina de backup
**Quero** enviar arquivos maiores que 150 MB de forma nao assistida
**Para que** o backup diario conclua sem intervencao e sem corromper o destino

Criterios de aceite:
1. **Dado** um arquivo de 2 GB, **quando** o envio e executado, **entao** o fluxo de sessao em partes e utilizado e o arquivo remoto tem tamanho e `content_hash` identicos ao local.
2. **Dado** que uma parte falha por erro transitorio, **quando** a retentativa ocorre, **entao** apenas a parte afetada e reenviada e o resultado final permanece integro.
3. **Dado** que a Dropbox responde `429` com `Retry-After`, **quando** o envio prossegue, **entao** a aplicacao aguarda ao menos o intervalo indicado antes de repetir.
4. **Dado** que o processo e interrompido por sinal, **quando** ele encerra, **entao** nenhum arquivo temporario permanece e o codigo de saida indica operacao nao concluida.
5. **Dado** execucao agendada sem terminal, **quando** o comando roda, **entao** nenhuma solicitacao de entrada bloqueia o processo.

Rastreabilidade: RF-08, RF-09, RNF-05, RNF-07, RNF-09, RNF-19.

### HU-03 — Diagnosticar falha de execucao agendada

**Como** engenheiro de automacao
**Quero** que falhas produzam codigo de saida e mensagem especificos
**Para que** meu orquestrador decida entre repetir, alertar ou abortar sem analisar texto livre

Criterios de aceite:
1. **Dado** refresh token revogado, **quando** um comando autenticado e executado, **entao** a saida indica necessidade de reautenticacao e o codigo de saida corresponde a classe de autenticacao.
2. **Dado** caminho remoto inexistente, **quando** metadados sao consultados, **entao** a saida indica `path_not_found` e o codigo de saida corresponde a classe de recurso nao encontrado.
3. **Dado** limite de taxa atingido apos esgotadas as retentativas, **quando** o comando encerra, **entao** o codigo de saida corresponde a classe de limite de taxa.
4. **Dado** qualquer falha de API em verbosidade elevada, **quando** o log e inspecionado, **entao** ele contem `X-Dropbox-Request-Id` e nenhum segredo.

Rastreabilidade: RF-29, RF-30, RNF-03, RNF-07, RNF-08.

---

## 9. Divergencias identificadas

Registro exigido pelo item 22 do protocolo comum. Divergencias entre a demanda, o modelo de referencia, o contrato vigente da Dropbox e o estado do projeto alvo.

| ID | Divergencia | Evidencia | Impacto | Recomendacao |
|---|---|---|---|---|
| DIV-01 | O modelo de referencia usa `/2/files/search`, endpoint que **nao consta mais** da documentacao vigente da Dropbox; o endpoint atual e `/2/files/search_v2` com paginacao por `/2/files/search/continue_v2` | `dropbox_uploader.sh:65`; revalidacao via Context7 | O comando de busca do modelo aponta para endpoint nao documentado; reproduzir o comportamento herda o defeito | Especificar `search_v2` com paginacao e deduplicacao (RF-22, RES-06, RES-14, RNF-12). **Ajuste de precisao na v0.2:** a v0.1 afirmava retirada em 28/02/2021 com base em fonte secundaria; a documentacao indexada nao traz marcacao de retirada, apenas deixou de documentar o endpoint. A conclusao operacional nao muda |
| DIV-02 | O modelo usa `files/copy`, `files/move`, `files/delete` e `files/create_folder`; as operacoes vigentes sao `copy_v2`, `move_v2`, `delete_v2` e `create_folder_v2` | `dropbox_uploader.sh:52-60`; revalidacao via Context7 | Risco de descontinuidade sem aviso operacional; formatos de retorno distintos | Adotar exclusivamente as variantes `_v2`, que retornam envelope com campo `metadata` (RES-07, RNF-12). **Ajuste de precisao na v0.2:** a documentacao indexada marca explicitamente outros endpoints como depreciados (por exemplo `sharing/create_shared_link` e `sharing/get_shared_links`), mas simplesmente nao documenta mais as variantes de `files` sem sufixo. Portanto a afirmacao correta e "nao documentadas", nao "marcadas como depreciadas" |
| DIV-03 | O modelo passa app secret e refresh token como argumentos de linha de comando ao `cURL`, tornando-os visiveis na tabela de processos do host | `dropbox_uploader.sh:370` e `dropbox_uploader.sh:1619` | Exposicao de credencial a qualquer usuario local do mesmo host; risco alto em servidor multiusuario | Especificar RNF-03 como requisito de seguranca obrigatorio e usar entrada por `stdin` ou arquivo de configuracao do `cURL` |
| DIV-04 | O modelo interpreta respostas JSON por expressao regular com `sed` | `dropbox_uploader.sh:1621` e demais extracoes | Fragilidade diante de variacao de formatacao, ordem de campos e valores contendo delimitadores; fonte provavel de defeito silencioso | Definir estrategia de interpretacao em DP-08 e cobrir com RNF-11 |
| DIV-05 | O modelo cria arquivos temporarios em `/tmp` com sufixo `$RANDOM`, previsivel e sem `mktemp` | `dropbox_uploader.sh:67-69` | Exposicao a corrida e a ataque por link simbolico em diretorio compartilhado | Especificar RNF-05 |
| DIV-06 | O modelo concentra ~35 funcoes em um unico arquivo de 1834 linhas | `dropbox_uploader.sh` | Custo de manutencao e de teste elevado; dificulta cobertura por unidade | Especificar RNF-16 e a decomposicao proposta no System Design |
| DIV-07 | ✅ **Encerrada na v0.2.** O modelo esta sob GNU GPL v3 e o regime de licenciamento do novo projeto era indefinido | `LICENSE` do projeto de referencia | Obrigacao copyleft caso houvesse derivacao de codigo | **Resolvida por DP-01:** reimplementacao independente. Permanece a obrigacao de disciplina de execucao registrada em RES-02, e a escolha da licenca especifica migrou para DP-20 |
| DIV-08 | 🟡 **Parcialmente encerrada na v0.2.** A demanda nao declarava o delta funcional em relacao ao modelo | Prompt original; resposta do solicitante a DP-02 | Sem diferencial, o resultado seria um clone de menor maturidade | **Premissa de valor resolvida:** o solicitante confirmou que ha funcionalidade nova. **Permanece em aberto quais.** Proposta de 22 candidatas em [funcionalidades-candidatas.md](funcionalidades-candidatas.md), aguardando confirmacao |
| DIV-09 | `MEMORIA-PROJETO.md` descreve o pacote de agents de origem, nao este projeto | `.claude/agents-protocol/memoria/MEMORIA-PROJETO.md` | Decisoes herdadas (`PRJ-DEC-01` a `PRJ-DEC-04`) podem ser lidas como historico deste projeto e induzir conclusoes erradas | Nao acumular registros sobre o conteudo herdado; solicitar ao Tech Lead a decisao de reinicializar ou segregar a memoria de projeto. **Em aberto** |
| ~~DIV-10~~ | ❌ **Removida na v0.2 por erro factual do proprio Business Analyst.** A v0.1 registrava que o Context7 MCP nao estaria disponivel no workspace | — | A conclusao estava incorreta: o servidor esta ativo e funcional; as ferramentas MCP sao de carregamento diferido e exigem chamada previa de descoberta antes da invocacao | Os contratos foram revalidados via Context7 sobre `/websites/dropbox_developers_http` e as correcoes estao refletidas em RES-04 a RES-14 e em DIV-11 a DIV-14 |
| DIV-11 | A propria documentacao da Dropbox e internamente inconsistente quanto ao host do endpoint de token: o bloco de referencia indica `api.dropboxapi.com/oauth2/token`, enquanto todos os exemplos executaveis usam `api.dropbox.com/oauth2/token` | Revalidacao via Context7 | Escolha errada pode gerar falha de autenticacao dificil de diagnosticar | Adotar `https://api.dropbox.com/oauth2/token`, que e o host dos exemplos executaveis e coincide com o do modelo de referencia; registrar a inconsistencia no codigo e cobrir por teste de contrato. Observar que a **autorizacao** usa host distinto: `https://www.dropbox.com/oauth2/authorize` |
| DIV-12 | A busca pode retornar resultados duplicados entre paginas ou omitir resultados, por atraso de indexacao, e tem teto de 10.000 correspondencias | Revalidacao via Context7 | Listagem de busca sem deduplicacao produz resultado incorreto; teto silencioso induz o usuario a crer que viu tudo | Especificado em RF-22, RES-06 e RES-14 |
| DIV-13 | **Correcao do proprio artefato.** A v0.1 tratava o tamanho de parte multiplo de 4 MiB como recomendacao geral de desempenho | Revalidacao via Context7 | Premissa de dimensionamento incorreta | O multiplo de 4.194.304 bytes e **obrigatorio apenas em sessao concorrente**; em sessao sequencial nao ha exigencia alem do teto de 150 MiB por requisicao. Corrigido em RES-10, RF-08 e na secao de dimensionamento do System Design |
| **DIV-17** | 🔄 **Duas correcoes de registro anterior, devolvidas pelo ciclo 2 de QA.** Ambas mantem a acao tomada, mas invalidam a justificativa registrada | Medicao do QA no ciclo 2 | Justificativa errada em artefato versionado leva a conclusoes erradas em revisoes futuras, ainda que a acao tenha sido correta | **(a) O `assert_status` com subshell NAO escondia o `E2-09`.** A afirmacao nao se sustenta: o QA mediu por reversao — suite 218/0/2 sob a versao antiga, **zero reprovacoes**. Nenhum caso passava por vacuidade; **a suite tinha sido escrita contornando a limitacao**. A correcao continua certa; a justificativa, nao. Distincao que importa: "o instrumento escondia o defeito" e "a suite foi escrita evitando o terreno onde o instrumento falha" tem implicacoes opostas para confianca na cobertura. **(b) A auditoria estatica declarada como garantia contra a classe do `$( )` estava furada** — casava apenas `=[$]\(`, deixando passar `+=" ... $(...)"`, com **ocorrencia viva em `lib/errors.sh`**. Padrao ampliado e ocorrencia corrigida. Consequencia registrada como `RSK-27`: garantia que so pega a forma obvia de uma classe **da falsa seguranca**, e esta era a defesa declarada contra algo que ja ocorrera **tres vezes** |
| ~~DIV-15~~ | ❌ **RETIRADA na v0.5 — a divergencia nao existia.** A v0.4 acusou a implementacao de antecipar uma decisao do solicitante ao adotar recursos de `bash` 4+. **A acusacao era infundada:** o solicitante **havia decidido** DP-07 e DP-08, respondendo "so cURL, `bash` 4+, Linux" a uma pergunta explicitamente rotulada com essas duas decisoes | Registro da resposta do solicitante | Nenhum sobre o produto. A premissa do Senior Developer estava **correta** desde o inicio, e o codigo escrito era legitimo | **A falha foi do documento, nao da implementacao.** A decisao existia e nunca foi propagada aos artefatos de requisitos; o documento desatualizado passou a ser lido como prova de que nao havia decisao, e sobre essa leitura falsa foram construidos `DIV-15`, o congelamento de `RNF-01` e o risco `RSK-25`. Tudo isso foi desfeito na v0.5. **A retirada e registrada em vez de apagada**, porque a acusacao chegou a constar de artefato versionado. A falha real esta em `RSK-26` |
| **DIV-16** | ✅ **Encerrada na v0.5.** O conflito entre RNF-10 (nomes com quebra de linha) e RF-28/RF-35 (saida orientada a linha) | Ciclo de QA da camada de dominio; decisao do solicitante | Eram **duas coisas distintas sob um rotulo so** | **(a) Defeito de implementacao ativo** — `lib/path` retornava valor errado **com status 0** para caminho contendo nova linha, falha silenciosa, a pior classe. **Corrigido em C2-01/D1 e verificado.** **(b) Divergencia de requisito — ✅ RESOLVIDA por DIV-16b:** saida orientada a linha por padrao, com opcao **`--null`** usando o byte nulo como terminador, no padrao de `find -print0` e `xargs -0`. E o unico byte que nao pode ocorrer em nome de arquivo POSIX, portanto resolve a ambiguidade sem inventar escape proprio, e preserva a legibilidade do modo padrao para uso interativo. **`lib/output` esta destravado.** Atencao registrada em RNF-22: o modo `--null` **nao** dispensa a restricao de nao concatenar diagnostico em linha de cabecalho sensivel |
| DIV-14 | 🟡 **Em grande parte encerrada na v0.3.** Tres contratos nao haviam sido confirmados na v0.2: o algoritmo do `content_hash`, a existencia do cabecalho `X-Dropbox-Request-Id` e os escopos OAuth de quatro endpoints | Verificacao na documentacao oficial da Dropbox | `lib/hash` estava bloqueado, e com ele RF-33, RF-34 e a funcionalidade F-02 | **1. `content_hash` — ✅ CONFIRMADO.** Algoritmo publicado em `dropbox.com/developers/reference/content-hash`: dividir o arquivo em blocos de 4 MiB (4.194.304 bytes); aplicar SHA-256 a cada bloco; concatenar os resumos **em formato binario**, nao hexadecimal; aplicar SHA-256 a concatenacao; emitir em hexadecimal (64 caracteres). Ha vetor de teste oficial, adotado como criterio de aceite em RF-34. **`lib/hash` esta desbloqueado.** **2. `X-Dropbox-Request-Id` — ✅ corroborado**, porem por fonte secundaria (referencia do SDK oficial e orientacao de suporte da Dropbox), nao pela referencia HTTP primaria. RF-30 permanece redigido para nao depender do nome exato, o que torna a diferenca inocua. **3. Escopos OAuth — 🟡 pendencia residual.** Os nomes dos escopos estao confirmados; o mapeamento por endpoint de `files/search_v2`, `sharing/create_shared_link_with_settings`, `users/get_current_account` e `users/get_space_usage` continua nao confirmado. A documentacao declara que o escopo exigido consta da pagina de cada endpoint. **Verificacao residual do Senior Developer, de baixo risco:** um escopo faltante produz `401` explicito na primeira execucao, nao defeito silencioso |

---

## 10. Dependencias de fechamento

| Dependencia | Situacao | Justificativa |
|---|---|---|
| Validacao QA de frontend (`qa-validacao-frontend-template.md`) | **Nao aplicavel** | Nao ha interface grafica no escopo. Reavaliar se DP-13 aprovar shell interativo com requisitos de experiencia relevantes |
| Design System do UX Expert | **Nao aplicavel na forma padrao, porem recomendado** | Nao ha componentes visuais. Com DP-03 confirmando uso interativo por operador humano, a recomendacao de acionar o UX Expert **ganhou peso**: padrao de experiencia de linha de comando cobrindo texto de ajuda, gramatica de comandos, formato das duas apresentacoes de saida exigidas por RF-28, redacao de mensagens de erro com acao corretiva e roteiro do assistente de configuracao |
| Plano de dimensionamento do DBA | ❌ **Nao aplicavel — confirmado na v0.3** | Nao ha banco de dados **nem qualquer estado local persistente**. As quatro candidatas que o exigiriam (F-03, F-06, F-12, F-14) ficaram fora do escopo. `DP-09` permanece fechada. **Nao reabrir sem mudanca formal de escopo** |
| Aprovacao final do Tech Lead (`aprovacao-final-tech-lead-template.md`) | **Aplicavel** | Requerida no fechamento formal da entrega |
| Aprovacao explicita do solicitante sobre os testes de QA | **Aplicavel** | Item 12 do protocolo comum |
| Resposta a DP-02 (quais funcionalidades novas) | ✅ **Resolvida** | Escopo do MVP aprovado. **Nenhuma decisao bloqueante em aberto** |
| Confirmacao dos contratos nao verificados (DIV-14) | 🟡 **Pendencia residual de baixo risco** | `content_hash` **confirmado** com vetor de teste oficial; cabecalho de correlacao corroborado; resta apenas o mapeamento escopo-por-endpoint de quatro chamadas, cuja ausencia produz `401` explicito e nao defeito silencioso |
| Declaracao formal de nao derivacao de codigo | **Aplicavel no fechamento** | Decorre de DP-01 e RES-02. Deve constar da aprovacao final do Tech Lead |
