# Funcionalidades Candidatas — Proposta para Confirmacao do Solicitante

| Campo | Valor |
|---|---|
| Projeto | `dropbox_api` |
| Responsavel | Business Analyst |
| Data | 2026-10-18 *(atualizado em 2026-10-20)* |
| Versao | **v0.16** — fase 8 (2026-10-21; escopo v1.24, secao 5.17): `F-18` (perfis nomeados de credencial) passa a **em andamento, fase 8**, com `RF-120` a `RF-132` e `RNF-37`; `DP-05` reaberta e resolvida; `DIV-236` a `DIV-251` resolvidas em 2026-10-21 (`F-44` criado no backlog). *Anterior:* **v0.15** — fase 7b (2026-10-21; escopo v1.23, secao 5.16): `F-43` criado no backlog (hash esperado da listagem no recebimento do `sync`, `RSK-84`); `DIV-235` aceita. `DIV-221` a `DIV-234` decididas; `F-40` corrigido no enumerador do `sync`, que tambem serve `verificar` e `sync --enviar` (`DIV-233`, mudanca de comportamento: `continue` sem `limit` e guarda de laco); `list` e `dbx_cmd_listar_nivel` seguem em `F-40`. `F-14` "em andamento, fase 7b", formalizado em `RF-110` a `RF-119`; o cursor so acelera a enumeracao **remota** (a travessia local continua completa) e exige um retrato remoto persistido junto do cursor (`DIV-204`); `F-40` corrigido so no caminho do `sync` (`DIV-214` B); `DIV-204` a `DIV-220` decididas em 2026-10-21; `DIV-205`: so `sync --receber` usa o cursor, o download de pasta fica fora (`F-42`). **v0.14** — fase 7a (2026-10-21; escopo v1.22, `DIV-191` a `DIV-202`): `F-42` ganha a varredura de `.part` orfao por padrao de nome, so listando, nunca apagando (`DIV-198`, `RSK-75`). **v0.13** — fase 7a (2026-10-20; escopo v1.21, secao 5.15): `F-03` "em andamento, fase 7a", formalizado em `RF-101` a `RF-109` (porte G; retomada entre execucoes de `upload` e `download` de arquivo acima de 150 MiB; estado `retomada-*` `0600` sem segredo, vinculado a conta, origem e destino; upload so retoma com o arquivo local inalterado e confere o `content_hash` final; download retoma o `.part` por `Range` e confere o `content_hash` antes da troca); divergencias `DIV-171` a `DIV-190` decididas pelo Tech Lead em 2026-10-20 e conciliadas com o parecer do DBA (`C1` a `C6`); `F-42` (retomada no `sync` e em pastas, `DIV-180`) criado no backlog (memoria `2026-10-20-2315-retomada`). **v0.12** — fase 6 (2026-10-20; escopo v1.20): `F-40` (`limit` indevido no `list_folder/continue`, `DIV-150`) e `F-41` (`invalid_grant` na renovacao do token classificado como `2`, e nao `5`, `DIV-151`), defeitos preexistentes achados pelo Senior Developer na fase 6 e mandados ao backlog pelo Tech Lead (memoria `2026-10-20-2010-retencao`). **v0.11** — fase 6 (2026-10-20): `F-10` "em andamento, fase 6", formalizado em `RF-93` a `RF-100` (porte G; `dbx reter`/`retain` com `--padrao`, `--manter N` ou `--dias D`; plano sem `--confirmar`; exclusao para a lixeira por `delete_v2`; minimo de 1 artefato; guarda sem estado); divergencias `DIV-130` a `DIV-147` abertas, com recomendacao (memoria `2026-10-20-2010-retencao`). **v0.10** — fase 5 (2026-10-20): `F-15` e `F-16` "em andamento, fase 5", formalizados em `RF-84` a `RF-92` (porte G; `dbx link-temporario`/`temp-link` e `dbx compartilhar`/`share` com `--listar` e `--revogar`; visibilidade explicita; senha so por terminal ou `--senha-stdin`); divergencias `DIV-104` a `DIV-120` decididas conforme as recomendacoes (`DIV-106` pelo solicitante: `sharing.read` habilitado) (memoria `2026-10-20-1110-compartilhamento`). **v0.9** — fase 4 (2026-10-19): `F-13` e `F-17` "em andamento, fase 4", formalizados em `RF-79` a `RF-83` (porte M; filtros de caminho com sintaxe gitignore, data e tamanho so na origem, limite de banda por `limit-rate`); divergencias `DIV-79` a `DIV-94` decididas pelo Tech Lead conforme as recomendacoes (memoria `2026-10-19-2141-filtros-e-banda`). **v0.8** — fase 3 (2026-10-19): `F-07` e `F-20` "em andamento, fase 3", formalizados em `RF-72` a `RF-78` (porte G; escopo novo `files.permanent_delete`); `F-39` (filtro por data na restauracao de pasta) criado no backlog (`DIV-62`). **v0.7** — fase 2 (2026-10-19): `F-12` e o restante de `F-31` "em andamento, fase 2", formalizados em `RF-69` a `RF-71`, `RNF-35` e `RNF-36`; o `C-1` da fase 1 entra como `RNF-36`. **v0.6** — fase 1b (2026-10-19): `F-36` e `F-37` "em andamento, fase 1b"; `F-38` (raiz local configuravel) criado no backlog. **v0.5** — fase 1 (2026-10-19): `F-11`, `F-19`, `F-21` e `F-22` formalizados em `RF-65` a `RF-68` e marcados "em andamento, fase 1". **v0.4** — pendencias da fase 0 (2026-10-19): `F-23` a `F-33` conferidos contra os registros de `docs/reviews/` e marcados como entregues (PRs #35 a #38), com `F-31` parcial; `F-06` entregue; `F-35` fora; `F-03`, `F-07` a `F-22`, `F-34` planejados por fase (memoria `2026-10-19-1023-plano-do-backlog`). *Registro anterior:* **v0.3** — fase 3 (`DP-34`): `F-25`, `F-26` e `F-29` em andamento com rastreio para `RF-60` a `RF-63` e `RNF-33`; `F-34` (paralelismo e APIs em lote, com medicao previa) e `F-35` (PKCE) criados. *Registro anterior:* **v0.2 — DECIDIDO** |
| Status | ✅ **DP-02 resolvida.** Escopo do MVP aprovado pelo solicitante. Este documento passa de proposta a **registro da decisao e do backlog** |
| Origem | Resposta a DP-02 |
| Documentos relacionados | [Escopo e requisitos](escopo-requisitos-e-criterios-de-aceite.md) · [Decisoes pendentes](decisoes-pendentes.md) · [System Design](../arquitetura/system-design.md) |

---

## ESCOPO APROVADO DO MVP

> **Decisao do solicitante, registrada como `PRJ-DEC-04`.** O escopo do MVP foi aprovado exatamente conforme a recomendacao do Business Analyst.

| Item | Decisao | Requisitos formais gerados |
|---|---|---|
| **Bloco 0 integral** — base endurecida | ✅ **Aprovado** como requisito de base nao negociavel | RNF-03, RNF-05, RNF-10, RNF-11, RNF-12, RNF-13, RNF-14, RNF-16 |
| **F-01** — transferencia por fluxo `stdin`/`stdout` | ✅ **Aprovada** | **RF-31**, **RF-32** |
| **F-02** — transferencia incremental por `content_hash` | ✅ **Aprovada** | **RF-33**, **RF-34** |
| **F-04** — contrato de automacao | ✅ **Aprovada** | RF-15, RF-28, RF-29 (ja existentes, promovidos a P0) + **RF-35** |
| **F-05** — relatorio de execucao | ✅ **Aprovada** | **RF-36** |
| **F-03** — retomada de transferencia interrompida | ❌ **Fora do MVP** | — |
| **Bloco 2 completo** (F-06 a F-14) | ❌ Fora do escopo desta versao | Backlog |
| **Bloco 3 completo** (F-15 a F-22) | ❌ Fora do escopo desta versao | Backlog |

### Consequencia arquitetural decisiva — nao reabrir

> **Nenhuma funcionalidade aprovada exige estado local persistente.**
>
> As quatro candidatas que exigiriam estado entre execucoes eram F-03 (retomada), F-06 (espelhamento), F-12 (trava de concorrencia) e F-14 (deteccao por cursor). **Todas ficaram fora do MVP.**
>
> Portanto, nesta versao:
> - **`DP-09` permanece fechada.** Nao ha decisao pendente sobre semantica de sincronizacao ou estado local.
> - **O handoff do DBA NAO e acionado.** A secao "Plano de dimensionamento e expansao do banco" do System Design permanece formalmente **nao aplicavel**, e nao por omissao: por ausencia de qualquer mecanismo de persistencia alem do arquivo de configuracao.
> - **Nao existe componente de estado local no System Design.** Qualquer proposta futura de introduzi-lo constitui **mudanca de escopo** e exige nova decisao do solicitante.
>
> Este bloco existe para impedir que o tema seja reaberto por engano em revisoes posteriores.

---

## Como usar este documento

Na v0.1 este era um instrumento de decisao. Com DP-02 resolvida, ele passa a cumprir duas funcoes: **registrar a fundamentacao do escopo aprovado** e **preservar o backlog** de candidatas nao selecionadas, com a analise ja feita, para que uma eventual segunda fase nao precise refazer o trabalho.

A analise original de cada candidata foi mantida integralmente abaixo, com a marcacao de decisao acrescentada.

### Distincao fundamental: novo versus correcao

| Categoria | Definicao | Entra no escopo? |
|---|---|---|
| **Bloco 0 — Base endurecida** | Coisas que o `Dropbox-Uploader` **ja faz, mas faz mal ou de forma quebrada**. Nao sao funcionalidades novas. | **Sim, como requisito de base nao negociavel.** Nao contam como justificativa do projeto, mas sem elas a reimplementacao nasce com os mesmos defeitos do modelo. Ja estao especificadas como RF/RNF |
| **Blocos 1 a 3 — Funcionalidade nova** | Capacidades que o `Dropbox-Uploader` **nao entrega de forma alguma**. | **A confirmar pelo solicitante.** Sao a resposta candidata a DP-02 |

> Endurecimento **nao foi** o motivo declarado pelo solicitante. Ele esta no Bloco 0 porque e consequencia inevitavel de reimplementar, nao porque justifique o projeto.

### Legenda

| Campo | Valores |
|---|---|
| **Valor** | Alto · Medio · Baixo — beneficio percebido pelo usuario final |
| **Esforco** | P (pequeno, ate ~1 unidade de trabalho) · M (medio) · G (grande, exige componente proprio e estado persistente) |
| **Estado local** | Sim = exige persistir estado entre execucoes; reativa DP-09 e pode exigir handoff do DBA |

---

## Bloco 0 — Base endurecida ✅ APROVADO INTEGRALMENTE

Correcoes de defeitos confirmados no modelo de referencia. **Aprovadas como requisito de base nao negociavel**, e nao como diferencial: o solicitante nao declarou endurecimento como motivacao, mas estas correcoes sao consequencia inevitavel de reimplementar sem herdar os defeitos do modelo.

| ID | Correcao | Defeito no modelo | Requisito |
|---|---|---|---|
| B0-01 | Uso exclusivo de endpoints vigentes da Dropbox API v2 | O comando de busca do modelo aponta para endpoint retirado e esta quebrado; quatro operacoes usam variantes depreciadas (DIV-01, DIV-02) | RNF-12 |
| B0-02 | Segredo nunca em `argv` | App secret e refresh token visiveis na tabela de processos a qualquer usuario local (DIV-03) | RNF-03 |
| B0-03 | Interpretacao robusta de resposta | Extracao por expressao regular, fragil a variacao de formatacao e a valores com delimitadores (DIV-04) | RNF-11 |
| B0-04 | Area temporaria segura | Nome previsivel em diretorio compartilhado, sem `mktemp` (DIV-05) | RNF-05 |
| B0-05 | Modularizacao e suite de testes | 1834 linhas em arquivo unico, praticamente nao testavel por unidade (DIV-06) | RNF-13, RNF-14, RNF-16 |
| B0-06 | Tratamento correto de nomes com espacos, acentos e caracteres especiais | Fonte recorrente de defeito em scripts shell | RNF-10 |

**Decisao:** ✅ aceito integralmente. E o piso de qualidade da reimplementacao.

---

## Bloco 1 — Nucleo do diferencial ✅ APROVADO, EXCETO F-03

Estas cinco candidatas foram escolhidas porque, juntas, mudam a **classe** da ferramenta: de "cliente de comandos avulsos" para "componente confiavel de automacao". Elas respondem diretamente a DP-03 (uso interativo **e** automatizado) e sao as que o `Dropbox-Uploader` mais claramente nao entrega.

### F-01 — Transferencia por fluxo (`stdin` / `stdout`) ✅ **APROVADA — RF-31, RF-32**

**O que e:** enviar conteudo recebido pela entrada padrao e receber conteudo na saida padrao, sem exigir arquivo intermediario em disco.

```
tar czf - /var/lib/app | dbx upload - /backups/app-$(date +%F).tgz
dbx download /backups/app-2026-08-17.tgz - | tar xzf - -C /restore
tar czf - /dados | gpg -c | dbx upload - /backups/dados.tgz.gpg
```

**Por que importa:** hoje, para enviar um backup comprimido, e obrigatorio materializar o arquivo em disco antes. Em host com pouco espaco livre, ou com backup maior que a area disponivel, isso simplesmente inviabiliza a rotina. A transferencia por fluxo tambem permite compor com compressao e criptografia sem que a ferramenta precise implementar nenhuma das duas.

| Aspecto | Avaliacao |
|---|---|
| Valor | **Alto** — remove uma restricao dura de infraestrutura |
| Esforco | **M** — o tamanho e desconhecido de antemao, portanto exige sempre sessao em partes com bufferizacao por parte |
| Estado local | Nao |
| Desbloqueia | Backup sem disco intermediario; composicao com `tar`, `gzip`, `gpg`, `mysqldump`, `pg_dump`; uso em container efemero |
| Existe no modelo? | **Nao.** O modelo exige caminho de arquivo local |

---

### F-02 — Transferencia incremental por `content_hash` ✅ **APROVADA — RF-33, RF-34**

**O que e:** antes de transferir, comparar o resumo de conteudo do arquivo local com o do arquivo remoto; se forem identicos, ignorar. A comparacao e por **conteudo**, nao por nome nem por data.

**Por que importa:** o modelo oferece apenas "ignorar se ja existe", decidido por presenca de nome. Isso e insuficiente em dois sentidos opostos: ignora arquivos que mudaram (perda de dado) e reenvia arquivos identicos quando a opcao nao e usada (desperdicio de banda e de cota de API). Em uma rotina diaria sobre uma arvore estavel, a diferenca e de ordem de grandeza no tempo e no numero de chamadas.

| Aspecto | Avaliacao |
|---|---|
| Valor | **Alto** — reduz banda, tempo de janela e risco de limite de taxa |
| Esforco | **M** — depende do calculo local do `content_hash`, que e um algoritmo definido pela Dropbox |
| Estado local | Nao na forma basica (consulta os metadados remotos). Sim, se houver cache local de resumos para evitar releitura dos arquivos |
| Desbloqueia | F-06, F-11, F-14; viabiliza rotinas frequentes sobre arvores grandes |
| Existe no modelo? | **Nao.** O modelo nao calcula nem compara resumo de conteudo |

---

### F-03 — Retomada de transferencia interrompida 🔧 **EM ANDAMENTO, FASE 7a — `RF-101` a `RF-109`**

> **Atualizacao de 2026-10-20 (fase 7a; memoria `2026-10-20-2315-retomada`):** o solicitante promoveu `F-03` do backlog para a fase 7a, cobrindo **upload e download**. Upload: guarda a sessao e o deslocamento, so retoma se o arquivo local nao mudou e confere o `content_hash` final. Download: retoma um `.part` por `Range` e confere o `content_hash` antes de trocar o destino. Formalizado na secao 5.15 do escopo (v1.21); `DP-09` reaberta e o DBA acionado; o cursor (`F-14`) fica na fase 7b. A historia abaixo e preservada como registro da decisao original.


> **Decisao do solicitante.** Mantida como backlog. Foi a unica candidata do Bloco 1 nao aprovada, e a decisao tem consequencia arquitetural direta: **era a unica funcionalidade aprovavel do MVP que exigiria estado local persistente**. Com ela fora, o MVP nao introduz persistencia alguma e o handoff do DBA nao e acionado.
>
> **Atualizacao de 2026-10-18 (`DP-33`, `RF-58`):** a retomada **na mesma execucao** (reler a partir do `correct_offset` diante de `incorrect_offset`) entrou na fase 2 e **nao e `F-03`**: nao persiste `session_id` nem deslocamento. A retomada **entre execucoes**, que exige estado local, continua fora de escopo.
>
> Reavaliar se DP-12 revelar arquivos de varios gigabytes ou rede instavel. Enquanto isso, a mitigacao disponivel e a retentativa por parte dentro de uma mesma execucao (RF-09), que ja esta no escopo e cobre falha transitoria sem cobrir queda do processo.

**O que e:** persistir o identificador de sessao e o deslocamento ja enviado, de modo que uma nova execucao continue de onde parou em vez de reiniciar o arquivo.

**Por que importa:** em arquivo de vários gigabytes sobre link instavel, uma queda proxima do fim hoje custa o reenvio integral. Se a janela de rotina for menor que o tempo de reenvio, a rotina nunca converge.

| Aspecto | Avaliacao |
|---|---|
| Valor | **Alto** em ambientes com arquivos grandes ou rede instavel; **Baixo** se os arquivos forem pequenos |
| Esforco | **M** — a Dropbox suporta a retomada da sessao; o custo esta no arquivo de estado e na validacao de coerencia (arquivo local nao pode ter mudado desde a interrupcao) |
| Estado local | **Sim** |
| Desbloqueia | Transferencia confiavel de arquivos muito grandes; rotinas com janela apertada |
| Existe no modelo? | **Nao.** O modelo repete a parte que falhou, mas perde a sessao inteira se o processo terminar |
| Pergunta ao solicitante | Qual o tamanho tipico e maximo dos arquivos? Se forem todos pequenos, esta candidata pode ser cortada (relacionado a DP-12) |

---

### F-04 — Contrato de automacao: saida estruturada, codigos de saida semanticos e simulacao ✅ **APROVADA — RF-15, RF-28, RF-29, RF-35**

**O que e:** tres capacidades que so fazem sentido juntas.

1. **Saida estruturada** (`--json` ou formato tabular estavel) para comandos de consulta, sem texto decorativo, com diagnostico separado na saida de erro.
2. **Codigos de saida distintos por classe de falha** — uso invalido, configuracao ausente, recurso nao encontrado, falha de autenticacao, limite de taxa, falha de rede, erro remoto.
3. **Modo de simulacao** (`--dry-run`), que descreve o que seria feito sem executar escrita.

**Por que importa:** o modelo imprime texto voltado a leitura humana e praticamente nao diferencia codigos de saida. Um orquestrador nao consegue distinguir "token revogado, avise um humano" de "limite de taxa, tente de novo em uma hora" sem recorrer a analise de texto livre, que quebra a cada mudanca de mensagem. Com DP-03 resolvida como **uso interativo e automatizado**, este item deixa de ser conveniencia e passa a ser requisito estrutural.

| Aspecto | Avaliacao |
|---|---|
| Valor | **Alto** — e a diferenca entre "roda no cron" e "e operavel no cron" |
| Esforco | **P a M** — barato se decidido no inicio; caro se adaptado depois |
| Estado local | Nao |
| Desbloqueia | Integracao com qualquer orquestrador; alertas confiaveis; uso em CI; F-05 |
| Existe no modelo? | **Nao.** Ha apenas modo silencioso |
| Observacao | Ja especificado como RF-15, RF-28 e RF-29. Listado aqui porque, com DP-03 resolvida, ele deixa de ser suporte e passa a ser diferencial declarado |

---

### F-05 — Relatorio de execucao ✅ **APROVADA — RF-36**

**O que e:** ao final de uma operacao em lote, emitir um sumario: itens enviados, ignorados por já estarem identicos, falhados, bytes transferidos, duracao e numero de chamadas a API. Disponivel em formato legivel e em formato estruturado.

**Por que importa:** hoje, saber se a rotina noturna funcionou exige ler o log inteiro. Com o sumario, o orquestrador decide alertar com base em um numero, e o operador tem evidencia objetiva do que aconteceu.

| Aspecto | Avaliacao |
|---|---|
| Valor | **Medio a Alto** — baixo custo, alto ganho operacional |
| Esforco | **P** |
| Estado local | Nao |
| Desbloqueia | Alertas por limiar; auditoria de execucao; medicao para o dimensionamento |
| Existe no modelo? | **Nao** |

---

### Resumo do Bloco 1

| ID | Funcionalidade | Valor | Esforco | Estado local |
|---|---|---|---|---|
| F-01 | Transferencia por fluxo (`stdin`/`stdout`) | Alto | M | Nao |
| F-02 | Transferencia incremental por `content_hash` | Alto | M | Nao (basica) |
| F-03 | Retomada de transferencia interrompida | Alto* | M | **Sim** |
| F-04 | Contrato de automacao (saida, codigos, simulacao) | Alto | P–M | Nao |
| F-05 | Relatorio de execucao | Medio–Alto | P | Nao |

\* condicionado ao tamanho real dos arquivos (DP-12), ainda em aberto.

**Decisao final do Bloco 1:** F-01, F-02, F-04 e F-05 aprovadas (RF-31 a RF-36); **F-03 fora do MVP**, mantida como backlog.

---

## Bloco 2 — ❌ FORA DO ESCOPO DESTA VERSAO — backlog preservado

> **Decisao do solicitante: nenhuma candidata do Bloco 2 entra no MVP.** A analise e preservada integralmente para que uma eventual segunda fase nao precise refaze-la.
>
> **Atencao para F-06, F-12 e F-14:** as tres exigem estado local persistente. Promover qualquer uma delas em versao futura reabre `DP-09` e aciona o handoff do DBA. Isso **nao** se aplica a esta versao.

| ID | Funcionalidade | O que e | Valor | Esforco | Estado local | Existe no modelo? |
|---|---|---|---|---|---|---|
| F-06 | **Espelhamento com remocao de orfaos** | Fazer o destino refletir exatamente a origem, inclusive removendo no remoto o que foi apagado localmente. Com protecao obrigatoria: simulacao previa e confirmacao explicita para exclusoes | Alto | G | Sim | **Nao.** O modelo so faz envio aditivo; nao e sincronizacao |
| F-07 | **Revisoes e restauracao** | Listar versoes anteriores de um arquivo e restaurar uma versao especifica | Alto | P | Nao | **Nao.** Capacidade da API totalmente inexplorada pelo modelo |
| F-08 | **Operacoes em lote** | Usar os endpoints de lote da Dropbox para excluir, mover e copiar muitos itens em poucas chamadas, em vez de uma chamada por item | Medio–Alto | M | Nao | **Nao.** O modelo opera item a item |
| F-09 | **Paralelismo controlado** | Executar N transferencias simultaneas, com limite configuravel | Medio | M | Nao | **Nao.** O modelo e estritamente sequencial |
| F-10 | **Retencao e rotacao de backup** | Politica declarativa no destino: manter os ultimos N artefatos ou os dos ultimos D dias, purgando o excedente | Alto | M | Nao | **Nao.** Hoje exige script proprio em volta da ferramenta |
| F-11 | **Comando de verificacao** | Comparar arvore local e remota por `content_hash` e reportar divergencias **sem transferir nada** | Medio–Alto | P | Nao | **Nao** |
| F-12 | **Trava de execucao concorrente** | Impedir que duas execucoes da mesma rotina se sobreponham | Medio | P | Sim (arquivo de trava) | **Nao** |
| F-13 | **Filtros avancados** | Selecionar por data de modificacao, faixa de tamanho e padroes de inclusao, alem da exclusao ja existente | Medio | P–M | Nao | **Parcial.** O modelo tem apenas exclusao por padrao |
| F-14 | **Deteccao de mudancas por cursor** | Guardar o cursor de listagem e, na execucao seguinte, obter apenas o que mudou no remoto, sem varrer a arvore inteira | Alto em arvores grandes | M | Sim | **Nao.** O modelo usa o cursor apenas dentro de uma execucao. **Atualizacao de 2026-10-21 (fase 7b; memoria `2026-10-21-0713-cursor`):** em andamento so no `sync --receber` (download de pasta fora, `F-42`); so a arvore remota deixa de ser varrida, a travessia local segue completa; o registro guarda cursor mais retrato remoto; exclusao local so apos confirmacao do servidor (escopo 5.16) |

---

## Bloco 3 — ❌ FORA DO ESCOPO DESTA VERSAO — backlog preservado

> **Decisao do solicitante: nenhuma candidata do Bloco 3 entra no MVP.** Nenhuma delas exige estado local persistente, portanto podem ser incorporadas em versoes futuras sem impacto arquitetural relevante.

| ID | Funcionalidade | Valor | Esforco | Observacao |
|---|---|---|---|---|
| F-15 | Link temporario de download direto | Medio | P | Gera URL de acesso direto para consumo por outra ferramenta ou outra maquina, sem passar pela CLI. *(v0.10: em andamento, fase 5, `RF-84`)* |
| F-16 | Link compartilhado com expiracao, senha ou restricao de audiencia | Medio | P | Recursos dependem do plano Dropbox contratado (DP-18). *(v0.10: em andamento, fase 5; restricao de plano tratada como `permissao` `6` em `RF-90(b)`; `DP-18` resolvida pela decisao de 2026-10-20, `DIV-116`)* |
| F-17 | Limitacao de banda | Medio | P | Evita saturar o enlace em horario comercial |
| F-18 | Perfis nomeados de credencial | Medio | P | Ja especificado como RF-05. Ergonomia superior ao caminho de arquivo do modelo. **Atualizacao de 2026-10-21 (fase 8; memoria `2026-10-21-1735-perfis`): em andamento, fase 8, porte G; reabre a `DP-05` (uma conta so), que o solicitante resolveu em favor de perfis nomeados:** `--perfil`/`--profile` e `DBX_PERFIL`, `credencial.json` como perfil `padrao`, `perfis/<nome>.json`, `dbx perfis`, `unlink --perfil`, `config --perfil`; `RF-120` a `RF-132` e `RNF-37` (escopo 5.17); o estado segue separado pela identidade da credencial, com as ressalvas de `DIV-236`; trava por raiz local canonica no `sync --receber` (`RF-132`) |
| F-19 | Autocompletar de shell | Baixo | P | Melhora o uso interativo, agora confirmado em DP-03 |
| F-20 | Lixeira: listar, restaurar e excluir permanentemente | Medio | P–M | Capacidade da API inexplorada pelo modelo |
| F-21 | Verificacao previa de espaco disponivel | Baixo–Medio | P | Falha cedo em vez de no meio de uma transferencia longa |
| F-22 | Comando de diagnostico de ambiente | Baixo | P | Verifica dependencias, credencial, conectividade e escopos concedidos, e reporta o que falta |

---

## Analise de dependencias — situacao apos a decisao

Quatro candidatas exigiam **estado local persistente entre execucoes**: F-03, F-06, F-12 e F-14. **Nenhuma delas entrou no MVP.**

```mermaid
flowchart TD
  subgraph MVP["MVP aprovado - sem estado local"]
    F01[F-01 fluxo stdin/stdout]
    F02[F-02 incremental por content_hash]
    F04[F-04 contrato de automacao]
    F05[F-05 relatorio de execucao]
    B0[Bloco 0 base endurecida]
    F04 --> F05
    F02 -.usa.-> HASH[lib/hash - content_hash]
    F01 -.usa.-> SESS[upload_session sempre<br/>tamanho desconhecido]
  end

  subgraph BACKLOG["Backlog - fora desta versao"]
    F03[F-03 retomada]
    F06[F-06 espelhamento]
    F12[F-12 trava de concorrencia]
    F14[F-14 deteccao por cursor]
  end

  EST[(Estado local persistente)] -.exigido por.-> F03
  EST -.exigido por.-> F06
  EST -.exigido por.-> F12
  EST -.exigido por.-> F14
  EST -.reabriria.-> DP09{DP-09 e handoff do DBA}

  MVP ==>|nao depende de| EST

  style MVP fill:#e8f5e9
  style BACKLOG fill:#f5f5f5
  style EST stroke-dasharray: 5 5
  style DP09 stroke-dasharray: 5 5
```

**Conclusao registrada:** o MVP nao possui componente de persistencia alem do arquivo de configuracao. `DP-09` permanece fechada e o handoff do DBA nao e acionado. Reintroduzir estado local em qualquer momento constitui mudanca de escopo.

Duas dependencias tecnicas do MVP merecem destaque:

| Dependencia | Origem | Situacao |
|---|---|---|
| `lib/hash` — algoritmo do `content_hash` | F-02 (RF-33, RF-34) | ✅ **Confirmado.** Ver DIV-14 no documento de requisitos |
| Sessao de envio em partes obrigatoria, mesmo para conteudo pequeno | F-01 (RF-31) — o tamanho e desconhecido de antemao em um fluxo | Especificado em RF-31 |

---

## Fundamentacao da recomendacao — acatada integralmente

**Proposta apresentada:** Bloco 0 integral + F-01, F-02, F-04 e F-05. **Decisao do solicitante: aprovada exatamente como proposta.**

Justificativa registrada: as quatro nao exigem estado local persistente, o que mantem a arquitetura simples e o risco baixo, e juntas produzem uma afirmacao de valor defensavel — *"envia backups por fluxo sem disco intermediario, nao reenvia o que ja esta identico, e reporta o resultado de forma que um orquestrador consiga agir"*. Nenhuma dessas tres coisas o `Dropbox-Uploader` faz.

**Sobre F-03:** a recomendacao era decidir por dado, nao por opiniao, uma vez que o valor depende do tamanho real dos arquivos (DP-12, ainda em aberto). O solicitante optou por deixa-la fora do MVP. A consequencia positiva e relevante: **e o unico corte que preserva o MVP livre de persistencia local**.

**Gatilhos de reavaliacao do backlog**, preservados para uso futuro:

| Se o caso de uso evoluir para... | Promover | Reabre DP-09? |
|---|---|---|
| Arquivos de varios gigabytes ou rede instavel | F-03 | **Sim** |
| Backup com politica de retencao | F-10 | Nao |
| Manter uma arvore remota espelhada | F-06 + F-14 | **Sim** |
| Recuperacao de arquivos sobrescritos ou apagados | F-07 + F-20 | Nao |
| Muitos arquivos pequenos com janela apertada | F-08 (+ F-09 com cautela, ver RES-11) | Nao |
| Auditoria periodica sem transferir | F-11 | Nao |

---

## Registro da decisao

| ID | Funcionalidade | Decisao | Requisitos gerados |
|---|---|:--:|---|
| Bloco 0 | Base endurecida | ✅ Aprovado | RNF-03, 05, 10, 11, 12, 13, 14, 16 |
| F-01 | Transferencia por fluxo (`stdin`/`stdout`) | ✅ Aprovada | RF-31, RF-32 |
| F-02 | Transferencia incremental por `content_hash` | ✅ Aprovada | RF-33, RF-34 |
| F-03 | Retomada de transferencia interrompida | 🔧 Em andamento, fase 7a | `RF-101`, `RF-102`, `RF-103`, `RF-104`, `RF-105`, `RF-106`, `RF-107`, `RF-108`, `RF-109` |
| F-04 | Contrato de automacao | ✅ Aprovada | RF-15, RF-28, RF-29, RF-35 |
| F-05 | Relatorio de execucao | ✅ Aprovada | RF-36 |
| F-06 | Espelhamento com remocao de orfaos | ✅ Entregue (`sync --espelhar`, `DP-06`/`DP-27`) | `RF-37`..`RF-48` |
| F-07 | Revisoes e restauracao | 🔧 Em andamento, fase 3 | `RF-72`, `RF-73`, `RF-78` |
| F-08 | Operacoes em lote | 🚧 Em andamento, fase 9 (exclusao e envio em lote; metadados retirados, `F-46`) | — |
| F-09 | Paralelismo controlado | 🚧 Em andamento, fase 9 (`--paralelo`, so transferencias do `sync`) | — |
| F-10 | Retencao e rotacao de backup | 🔧 Em andamento, fase 6 | `RF-93`, `RF-94`, `RF-95`, `RF-96`, `RF-97`, `RF-98`, `RF-99`, `RF-100` |
| F-11 | Comando de verificacao | 🔧 Em andamento, fase 1 | `RF-65` |
| F-12 | Trava de execucao concorrente | 🔧 Em andamento, fase 2 | `RF-69`, `RF-70`, `RF-71` |
| F-13 | Filtros avancados | 🔧 Em andamento, fase 4 | `RF-79`, `RF-80`, `RF-81`, `RF-83` |
| F-14 | Deteccao de mudancas por cursor | 🔧 Em andamento, fase 7b | `RF-110` a `RF-119` |
| F-15 | Link temporario de download | 🔧 Em andamento, fase 5 | `RF-84`, `RF-90`, `RF-92` |
| F-16 | Link compartilhado com expiracao ou senha | 🔧 Em andamento, fase 5 | `RF-85`, `RF-86`, `RF-87`, `RF-88`, `RF-89`, `RF-90`, `RF-91`, `RF-92` |
| F-17 | Limitacao de banda | 🔧 Em andamento, fase 4 | `RF-82`, `RF-83` |
| F-18 | Perfis nomeados de credencial | 🔧 Em andamento, fase 8 | `RF-05` (reativado), `RF-120` a `RF-132`, `RNF-37` |
| F-19 | Autocompletar de shell | 🔧 Em andamento, fase 1 | `RF-68` |
| F-20 | Lixeira: listar, restaurar, excluir permanentemente | 🔧 Em andamento, fase 3 | `RF-73(e)`, `RF-74`, `RF-75`, `RF-76`, `RF-77`, `RF-78` |
| F-21 | Verificacao previa de espaco | 🔧 Em andamento, fase 1 | `RF-67` |
| F-22 | Comando de diagnostico de ambiente | 🔧 Em andamento, fase 1 | `RF-66` |

**Nenhum acrescimo foi solicitado alem das candidatas propostas.**

**Pergunta que permanece aberta e independente desta decisao:** qual o tamanho tipico e maximo dos arquivos transferidos, quantos arquivos por execucao e com que frequencia (DP-12)? Necessaria para o dimensionamento e para eventual reavaliacao de F-03.


---

## Backlog derivado da analise de melhorias (2026-10-18)

> Origem: `docs/sources/2026-10-18-analise-melhorias.md`. Decisao do solicitante: quatro demandas em ordem de prioridade, cada uma com branch e PR proprios (memoria `2026-10-18-1745-melhorias-em-fases`). Itens abaixo sao **correcao ou endurecimento de comportamento existente**, nao funcionalidades novas.

| ID | Item | Fase | Estado | Requisitos / riscos |
|---|---|---|---|---|
| F-23 | Integridade de dados no `sync`/`download`: caixa de caminho, recebimento atomico com hash, `download` sem `rm`, `sync --enviar` por sessao com `client_modified`, `umask` e area temporaria | **P1** | ✅ **Entregue** na PR #35 (fase 1, `RF-54`..`RF-57`, `RNF-29`) | `RF-54`..`RF-57`, `RNF-29`, `DP-31`, `RSK-39` |
| F-24 | Robustez de rede: timeout (`connect-timeout`, `speed-limit`), `Retry-After`, 5 tentativas com base 1 s e teto 60 s, upload por sessao retomavel, falhas por arquivo no `sync` | **P2** | ✅ **Entregue** na PR #36 (fase 2): `RNF-30`, `RNF-07`/`Retry-After` (`DIV-22` encerrada), `RF-58`, `RF-59` | `RNF-30`, `RNF-07` (emendado; `DIV-22` encerrada, `RSK-38`), `RF-09` (emendado), `RF-58`, `RF-59`, `RF-36`, `DP-33` |
| F-25 | Cache e SQL: gravacao em lote numa transacao, escolha de um unico cache (`lib/state` x `lib/db`), chave canonica (`realpath`), SQL com validacao/parametros, erros do fallback Python visiveis; PKCE (S256) ou `client_secret` obrigatorio | **P3+P4** | ✅ **Entregue** na PR #37 (fase 3): cache unico em `lib/state`, `lib/db` removido (itens de SQL sem objeto), `RF-62`, `RF-63`. PKCE nao entregue: `F-35`, **fora por decisao do solicitante** | `RF-38`, `RF-42`, `RF-61`, `RF-62`, `RF-63`, `RNF-02`, `RNF-26`, `RNF-33` |
| F-26 | Skip do upload condicionado ao `content_hash` remoto (`get_metadata`); cache apenas otimiza o hash | **Fase 3 (junto de P3+P4)** | ✅ **Entregue** na PR #37 (fase 3): `RF-60`, `RSK-37` encerrado | `DP-32`, `RF-33`, `RF-60`, `RSK-23`, `RSK-37` |
| F-27 | Documentacao e manutencao: contradicao "sem estado local / cURL unica dependencia", `sqlite3`/`python3` no `preflight`, comentarios longos para registros/ADRs, aliases em ingles no `sync`, testes faltantes | **P5** | ✅ **Entregue** na PR #38 (fase 4): `RF-64` (aliases em ingles), `RNF-34` (coerencia doc x codigo), poda do pacote, comentarios enxutos; `sqlite3`/`python3` e testes diretos de `lib/state`/`lib/cmd` ja absorvidos pela PR #37 | `RNF-02`, `RNF-26`, `DP-15` |
| F-28 | **Achado QA-01(a), anterior a P1:** `dbx download <remoto>` sem destino (saida para o terminal) sai com codigo 9 no duplo de teste, no HEAD e na branch; confirmar se o defeito e do duplo ou do comando | **P2** | ✅ **Entregue** na PR #36 (fase 2): causa era o canal de fluxo do `lib/http`, nao o duplo; `RF-32(b)` | `RF-11`, `RF-32(b)` |
| F-29 | **Achado QA-01(b), anterior a P1:** `commands/upload.sh` le `DBX_TRANSFER_HASH`, variavel inexistente; o canal correto e `DBX_TRANSFER_CONTENT_HASH`, entao o upload por sessao pode deixar de gravar o hash no cache | **Fase 3 (P3+P4)** | ✅ **Entregue** na PR #37 (fase 3): `RF-61(j)` | `RF-08`, `RF-38`, `RF-61`, `DP-32`, `DP-34` |
| F-30 | **Achado QA-01(c), anterior a P1:** `tests/run.sh` nao para no primeiro erro, como exige a Regra 9 de `protocolo-tdd` | **P2** | ✅ **Entregue** na PR #36 (fase 2): `RNF-32(a)` | `RNF-32(a)`, protocolo de testes |
| F-31 | **Achado QA-01(d):** sinal durante `sync --receber` deixa `dbx-sync.XXXX` (listagens e revs, sem token) em `TMPDIR`; depende do `lib/tmp` (trap `EXIT` unico com areas registradas) | **P2/estrutural** | 🟡 **Parcial**, PR #36 (fase 2): `RNF-31` entregue (canal `DBX_HTTP_TRATADOR_EXTERNO`, area do `sync` limpa em `INT`/`TERM`/`HUP`). **Restante: 🔧 em andamento, fase 2** (formalizado em `RNF-35` e `RNF-36`, v1.12), junto da trava (`F-12`), por decisao do Tech Lead: `lib/tmp` com `OBS-02` (`TERM` durante `oauth2/token` deixa `dbx-http.*`), `OBS-03` (janela entre `mktemp` e o registro da area) e `OBS-04` (stdout em socket que fecha cedo) | `RNF-29(c)` (escopo atual cobre so a area HTTP), `RF-54`..`RF-57` |
| F-33 | **Achado da P1:** o teste `nao_deixa_residuo_temporario` de `tests/unit/hash_test.sh` conta o `/tmp` compartilhado e falha por ruido alheio; usar `TMPDIR` privado. Junto: `QA-05`, mapa de modulos em `docs/testes/mapa-modulos.md` (dono: QA Expert) | **P2** | ✅ **Entregue** nas PRs #36 (fase 2) e #37 (fase 3): `RNF-32(b)`, `RNF-32(c)`, mapa de modulos (`QA-05`); a ressalva do mapa foi fechada na #37 com os testes diretos `tests/unit/state_test.sh` e `tests/unit/cmd_test.sh` (`RNF-32(d)`) | `RNF-32(b)`, `RNF-32(c)` |
| F-32 | **Achado QA-01(e):** a comparacao sem caixa fora do ASCII depende de `C.UTF-8` no host; documentar a dependencia ou tornar a comparacao independente de locale | **P5** | ✅ **Entregue** na PR #38 (fase 4): `RF-54(e)`..`(g)`, `DIV-32` (`C.UTF-8` so na comparacao, com aviso unico) | `RF-54` |
| F-34 | **Paralelismo limitado e APIs em lote** (achado P3.3; ex.: `get_metadata` e envios em lote, varias transferencias simultaneas com limite). **Adiado por decisao do solicitante (`DP-34`)**; so entra com **medicao previa**: tempo de `sync`/`upload` sequencial em volume representativo (`DP-12`) e taxa de `429` observada, para comparar com a versao paralela | **Fase 9 do plano de 2026-10-19** | 🚧 Em andamento, fase 9 (com `F-08` e `F-09`), bancada `RF-138`, medicao antes e depois, escopo secao 5.18 (`RF-133` a `RF-139`) | `F-09`, `RNF-21` (padrao `1`, limite configuravel), `RES-11`, `RSK-22` |
| F-35 | **PKCE como alternativa futura ao `client_secret`** (`code_challenge` S256 na autorizacao e `code_verifier` na troca), para aplicativo publico sem segredo. **Nao implementado** por decisao do solicitante (`DP-34`); hoje o segredo e obrigatorio (`RF-63`) | **Fora** | ❌ Fora por decisao do solicitante (2026-10-19) | `RF-01`, `RF-63`, `RNF-03` |
| F-36 | **Achado O-1 do QA da fase 1, anterior a ela - severidade ALTA (confinamento):** o campo `raiz_remota` da credencial nunca e aplicado por nenhum comando; quem configurou o `dbx` (`config --raiz`) esperando confinamento a uma pasta do Dropbox nao o tem. **Viola `RNF-20(b)`** (operacao fora da raiz remota recusada antes de qualquer chamada a API) e o que `config --raiz` promete. **Status: em andamento, fase 1b** (decisao do solicitante de 2026-10-19): aplicado a todo comando com caminho remoto, `RNF-20(b1..b6)`, `TC-SEC-18..27`. |
| F-37 | **Achado O-2 do QA da fase 1, anterior a ela - severidade MEDIA:** caminho remoto com quebra de linha e aceito como argumento. **Contraria `RNF-10`** (nenhum caminho contendo nova linha pode ser aceito como valido) e, por consequencia, a saida orientada a linha (`RNF-22`, `RF-28`). **Status: em andamento, fase 1b** (decisao do solicitante de 2026-10-19): recusa `caminho_recusado`/`13`, `RNF-10(b)`, `TC-SEC-28..29`. |
| F-38 | **Raiz local configuravel** (`RNF-20(c)`): opcao de configuracao que restringe o caminho local alcancavel, com recusa antes de qualquer acesso a disco e resolucao fisica de symlinks. **Nao implementado**, por decisao do solicitante de 2026-10-19. **Nota:** o `sync` e o `walk` ja nao seguem symlink para fora da raiz da operacao; isso reduz o risco mas nao substitui a raiz local configuravel | **Backlog** | ⏳ Nao iniciado (adiado na fase 1b) | `RNF-20(c)`, `RSK-24`, `RSK-19` |
| F-39 | **Filtro por data na restauracao de pasta apagada** (`DIV-62`): opcao como `--apagados-desde DATA` em `dbx restaurar <pasta>`, que restaura so os arquivos apagados a partir da data (por `server_deleted` de `list_revisions`, ja consultado por item), para nao ressuscitar arquivos apagados de proposito antes da pasta. Na fase 3 a restauracao traz tudo o que estiver apagado sob a pasta e mostra `apagado_em` | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-19) | `RF-74`, `DIV-62` |
| F-40 | **Achado do Senior Developer na fase 6, anterior a ela (`DIV-150`):** `dbx_http_colecao` (`lib/http`) envia `limit` no corpo de `files/list_folder/continue`, mas o endpoint so aceita `cursor`; o defeito alcanca os usos do ajudante de colecao em `lib/sync`, `commands/list` e `dbx_cmd_listar_nivel`. Corrigir para que o `continue` leve **so** o `cursor`, com teste de contrato do corpo em cada uso. **7b (`DIV-214` B, `DIV-233`):** corrigido no enumerador do `sync`, que tambem atende `verificar` e `sync --enviar` (mudanca de comportamento: `continue` sem `limit` e guarda de laco, cursor repetido ou mais de 20.000 paginas sai `10`); `list` e `dbx_cmd_listar_nivel` seguem aqui. O `reter` (fase 6) ja manda so o cursor | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-20: defeito preexistente, fora do escopo da fase 6) | `RNF-23`, `RF-94(b)`, `DIV-150` |
| F-41 | **Achado do Senior Developer na fase 6, anterior a ela (`DIV-151`):** falha na renovacao do token (`invalid_grant`, credencial revogada ou expirada) e classificada como `uso_invalido` `2`, e nao `autenticacao` `5`, em `_dbx_cmd_escrita_remota` e `_dbx_cmd_consultar` (`lib/cmd`). Corrigir a classificacao no ponto comum, com teste por comando afetado. O `reter` (fase 6) contorna o defeito | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-20: defeito preexistente, fora do escopo da fase 6) | `RF-35`, `RF-98(d)`, `DIV-151` |
| F-42 | **Retomada entre execucoes no `sync` e em pastas** (`DIV-180`): estender a retomada de `F-03` (`RF-101` a `RF-109`) ao `sync --enviar`, ao `sync --receber`, ao `upload` de pasta e ao `download` de pasta, hoje sem retomada. Exige decidir a chave por arquivo dentro do par, a convivencia com a trava de par (`RF-69`) e com a memoria do `sync` (`RF-38`), o teto de registros e o tratamento dos `.part` que o `sync --receber` ja ignora. **Inclui (`DIV-198`, `RSK-75`):** varredura de `.part` orfao por padrao de nome (`.*.dbx-part.??????`) no diretorio do alvo, **so listando, nunca apagando**, para os que ficam sem registro depois da poda de um registro ilegivel | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-20: fora da fase 7a) | `F-03`, `RF-102(b)`, `RF-69`, `RF-38`, `DIV-180`, `DIV-198`, `RSK-75` |
| F-43 | **O `sync` deve passar o `content_hash` da listagem ao passo de recebimento como valor esperado** (achado `O2` do QA na 7b, anterior a ela, reproduzido na base `a6b5376`): hoje `dbx_cmd_receber_arquivo` so confere contra o cabecalho `Dropbox-API-Result`; sem o cabecalho, um conteudo cujo hash diverge do da listagem e aceito. A API real sempre envia o cabecalho | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-21) | `RF-55`, `RF-34`, `RSK-84` |
| F-44 | **`memoria-*` do `sync` chaveada por `account_id` colide entre apps de tipo diferente na mesma conta** (risco `R2` do parecer do DBA na fase 8, `DIV-251`): dois perfis da mesma conta com apps de tipo diferente compartilham o "visto" de `RF-48`. Corrigir (memoria v3, com `cred-` no cabecalho) faz **todos** os pares voltarem a "nao visto" e pedir de novo o reconhecimento do `--espelhar` | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-21; fora da fase 8) | `RF-48`, `RF-52`, `RSK-91` |
| F-45 | **Completar o valor de `--perfil` no `completions/dbx.bash` sem violar `TC-CPL-04`** (o script nao pode conter `XDG_`, `HOME`, credencial nem state; hoje so a opcao e completada) | **Backlog** | ⏳ Nao iniciado (decisao do Tech Lead, 2026-10-21) | `DIV-246`, `DIV-255`, `TC-CPL-04` |
| F-46 | **Metadados em lote (`get_metadata`) para a confirmacao das exclusoes do cursor** (`lib/sync.sh`, `sync --receber`). **Inviavel na API atual:** nao ha `files/get_metadata` em lote e `sharing/get_file_metadata/batch` nao traz `rev` nem `content_hash`. Retirado da fase 9 por decisao do solicitante (2026-10-21); a confirmacao segue item a item com o teto atual | **Backlog** | ⏳ Inviavel hoje; reavaliar se a API mudar | `F-08`, `F-14`, `RF-110` a `RF-119` |
| F-47 | **Conferir `content_hash` no envio unitario de pequenos (`files/upload`)** em `upload` e `sync --enviar`, comparando o resumo devolvido com o local e falhando com `integridade` (`11`), como o caminho por sessao e o lote ja fazem (`DIV-278`). Achado no fechamento da fase 9 (`DIV-280`, 2026-10-22) | **Backlog** | ⏳ A priorizar | `RF-55`, `F-08`, `DIV-175` |
| F-48 | **Suite independente do sistema de arquivos do `TMPDIR`.** `tests/unit/retomada_estado_test.sh` caso `c2_descarte_por_cabecalho_leva_o_part_pela_barreira` passa com `/tmp` em tmpfs e reprova com `TMPDIR` em disco (ext4), tambem na `develop` @ `334394e`. Achado na fase 9 (2026-10-22), quando o tmpfs de 7,9 GB encheu durante a suite completa | **Backlog** | ⏳ A priorizar | `RF-101`, `RNF-35` |
