# Parecer de Conformidade Arquitetural e de Boas Práticas — Aliases, origem vazia pelo plano, localidade e documentação (fase 4)

## Identificação

- Projeto ou produto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Agent responsável pela alteração: Senior Developer (delegação do Tech Lead, regra 44); a poda de comentários de `lib/http.sh` e `lib/transfer.sh` foi executada por um fork do próprio Senior Developer, sob o mesmo gate
- Agent responsável pela verificação: Senior Developer (gate local, regra 16)
- Data da verificação: 2026-10-19
- Ciclo de verificação: 1
- Tipo de alteração: Implementação nova (aliases RF-64, aviso de localidade RF-54(f)(g)) + Correção (O-1/DIV-30) + Refatoração (comentários, O-6, SC2034) + Documentação (RNF-34)
- Execução: local, sem pipeline
- Porte da demanda: **G** (confirmado; altera contrato público de CLI e regra transversal do `sync`)
- Modo do parecer: Completo
- Branch / worktree: `feature/docs-e-aliases-p4` em `/home/sales/dropbox_api.worktrees/feature-docs-e-aliases-p4`, base `6b00bcd`
- Log de prompt: [2026-10-19_0829_docs-e-aliases-p4.md](../prompts/2026-10-19_0829_docs-e-aliases-p4.md)
- Memória transposta (por id, regra 43): `2026-10-19-0829-aliases-poda-e-comentarios` (F-32, DIV-30 a DIV-32), `2026-10-18-1745-selecao-inclui-auditorias-lib`
- Parecer de testes: [2026-10-19-0829-parecer-tdd-docs-e-aliases.md](2026-10-19-0829-parecer-tdd-docs-e-aliases.md)

## Escopo verificado

- Comando usado para levantar o diff: `git status --short`, `git diff --stat -- lib bin commands tests README.md`, `git diff`
- Base de comparação: `HEAD` = `6b00bcd` (sem commit da demanda; diff só na árvore de trabalho). Arquivos de `.github/skills/`, `docs/requisitos/` e `docs/arquitetura/` estão no worktree por outros agentes e ficam fora deste parecer.

| Arquivo | Tipo de alteração | Camada / módulo | Verificado |
|---|---|---|---|
| `commands/sync.sh` | Alterado | comando `sync` (aplicação) | Sim |
| `commands/unlink.sh` | Alterado | comando `unlink` | Sim |
| `commands/config.sh` | Alterado | comando `config` | Sim |
| `bin/dbx` | Alterado | entrada, ajuda | Sim |
| `lib/sync.sh` | Alterado | aplicação, comparação sem caixa | Sim |
| `lib/preflight.sh` | Alterado | verificação prévia | Sim |
| `lib/output.sh` | Alterado (comentário) | apresentação | Sim |
| `lib/http.sh` | Alterado (só comentários) | adaptador de rede | Sim |
| `lib/transfer.sh` | Alterado (só comentários) | transferência | Sim |
| `README.md` | Alterado | documentação do operador | Sim |
| `docs/registros/2026-10-19-historico-comentarios-http-transfer.md` | Novo | registro histórico | Sim |
| `tests/integracao/sync_test.sh` | Alterado | suíte | Sim |
| `tests/integracao/comandos_test.sh` | Alterado | suíte | Sim |
| `tests/integracao/composicao_test.sh` | Alterado | suíte | Sim |
| `tests/unit/preflight_test.sh` | Alterado | suíte | Sim |
| `tests/unit/progress_test.sh` | Alterado (diretiva) | suíte | Sim |

- Arquivos alterados e não verificados, com motivo: nenhum do escopo desta demanda.

## Stack detectada e skills aplicadas

- Stack detectada: Shell script (bash 4.4+) + cURL (entrada `tipo: stack` `2026-10-07-1256-stack`)
- Evidência da detecção: shebangs `#!/usr/bin/env bash` em `bin/`, `lib/`, `commands/`; nenhum manifesto de outra stack

| Skill aplicada | Motivo da seleção | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatória em qualquer stack | `dep-inward-only`, `adapt-controller-thin`, `comp-common-closure`, `usecase-explicit-dependencies` |
| `shellcheck-configuration` | skill de stack para shell | Package precedence 1 a 5; supressão com motivo na linha anterior |

- Skills consideradas e descartadas, com motivo: `security-best-practices`/`api-security-best-practices` — o diff não toca autenticação, segredo, sessão nem exposição de API; a única entrada nova vinda do ambiente (`DBX_SYNC_LOCALIDADE`) é validada por alfabeto fechado e só alimenta `LC_ALL` local à função de comparação (ver Segurança).

## Verificação arquitetural

| Verificação | Regra | Resultado | Evidência |
|---|---|---|---|
| Direção de dependência | `dep-inward-only` | Conforme | `commands/sync.sh` chama `dbx_sync_localidade_disponivel` de `lib/sync`; `lib/sync` não passou a depender de `commands/` nem de `lib/output` (o aviso é emitido pelo comando, a lib só publica o motivo em `DBX_SYNC_MOTIVO`) |
| Propriedade da interface | `dep-interface-ownership` | Conforme | O canal `DBX_SYNC_MOTIVO` já era o canal público de motivo de `lib/sync` |
| Pureza de domínio | `frame-domain-purity` | Não aplicável | Nenhuma lib de domínio (`errors`, `hash`, `path`) alterada |
| Dados na fronteira | `dep-data-crossing-boundaries` | Conforme | Só tipos simples (cadeia, status) |
| Ciclos de dependência | `dep-acyclic-dependencies` | Conforme | Nenhum `source` novo |
| Modelo rico | `entity-rich-not-anemic` | Não aplicável | Sem entidades |
| Invariantes na entidade | `entity-encapsulate-invariants` | Não aplicável | Sem entidades |
| Entidade sem persistência | `entity-no-persistence-awareness` | Não aplicável | Sem entidades |
| Caso de uso orquestra | `usecase-orchestrates-not-implements` | Conforme | A regra de comparação sem caixa e a detecção da localidade ficam em `lib/sync`; o comando só orquestra (decide avisar) |
| Sem lógica de apresentação no caso de uso | `usecase-no-presentation-logic` | Conforme | A formatação do aviso passa por `lib/output` (`dbx_output_diagnostico`), como o aviso de estado já existente |
| Dependências explícitas | `usecase-explicit-dependencies` | Conforme | Localidade em constante `readonly` documentada; sem singleton oculto novo |
| Fronteira transacional | `usecase-transaction-boundary` | Conforme | A recusa por origem vazia continua depois do plano e antes de qualquer escrita (RF-41(d)); a remoção da guarda antiga não criou caminho de escrita antes do plano |
| Controller fino | `adapt-controller-thin` | Conforme | Aliases são padrões a mais nos `case` existentes, sem ramo novo |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme | `lib/http` intacto em código (prova abaixo) |
| Coesão e estrutura do domínio | `comp-common-closure`, `comp-screaming-architecture` | Conforme | Ajuda (`bin/dbx`), parsing (`commands/`) e README mudaram juntos para o mesmo contrato |

## Verificação da skill de stack

| Regra verificada | Skill | Resultado | Evidência |
|---|---|---|---|
| Dialeto segue o shebang (bash) | `shellcheck-configuration` 1 | Conforme | Arquivos alterados são bash; nenhum `shell=` forçado |
| Lint local de todo script alterado | `shellcheck-configuration` 3 | Conforme | `shellcheck` 0.10.0 em `lib/sync.sh lib/preflight.sh lib/output.sh lib/http.sh lib/transfer.sh commands/sync.sh commands/unlink.sh commands/config.sh bin/dbx` e nos 5 testes alterados: exit 0 |
| Supressão com motivo, só na linha | `shellcheck-configuration` 4 | Conforme | Uma diretiva nova `SC2034` em `lib/sync.sh` (canal público lido por `commands/sync`) e uma em `tests/unit/progress_test.sh` (global consumida por `lib/progress.sh`), ambas com motivo na própria diretiva, como o padrão do projeto |
| Expansões citadas, sem `eval` | `shellcheck-configuration` 2/Security | Conforme | `local LC_ALL=$DBX_SYNC_LOCALIDADE` é atribuição (sem divisão de palavra); valor restrito a `^[A-Za-z0-9_.@-]+$` |
| Nenhuma captura nova em `lib/` com byte externo (RNF-24) | projeto | Conforme | A detecção da localidade pergunta à própria conversão (`${x,,}` sobre `É`), sem `$(...)` nem `locale -a`; auditorias `json`, `http`, `preflight`, `composicao` verdes |
| Todo comando externo de `lib/` exigido pelo preflight | projeto (RNF-02) | Conforme | Nenhum utilitário novo em `lib/`; `tail` e `df`, usados por `commands/config.sh`, entraram na lista |

## Verificação de segurança acionada

- O diff toca autenticação, autorização, segredos, dados sensíveis, sessão/cookies, CSP/CORS ou exposição de API?: Não
- Skills aplicadas: nenhuma obrigatória; verificação manual abaixo pela entrada nova de ambiente

| Item | Resultado | Evidência |
|---|---|---|
| Ausência de segredo no diff | Conforme | Nenhum token/segredo em código, teste ou registro; o aviso de localidade não carrega dado do operador além do nome da localidade validado |
| Validação de entrada nas novas fronteiras | Conforme | `DBX_SYNC_LOCALIDADE` (ambiente) validada por alfabeto fechado, `readonly`; valor fora do alfabeto volta ao padrão; efeito máximo de valor hostil: comparação no ASCII com aviso (mesmo efeito da localidade ausente) |
| Autorização verificada nos novos acessos | Não aplicável | Nenhum acesso novo |
| Isolamento por tenant | Não aplicável | — |

## Consistência com o projeto

| Item | Resultado | Observações |
|---|---|---|
| Segue padrão já adotado em módulos equivalentes | Conforme | Aliases no mesmo estilo de `--progresso \| --progress \| -p` e de `delete --confirmar \| --yes`; variável de ambiente validada no estilo de `DBX_HASH_BACKEND`; aviso no estilo do aviso de estado do próprio `sync` |
| Não reimplementa componente existente | Conforme | Reutiliza `_dbx_sync_chave` para detectar a localidade |
| Coerente com System Design / ARD | Conforme, com ressalva | A linha v0.3 da tabela de decisões do System Design (RNF-34(f)) é do Business Analyst e ficou fora deste diff, conforme a delegação |
| Coerente com decisões nas memórias do pacote | Conforme | F-32 (fixação só na comparação), DIV-30 (sem `--espelhar`, saída 0), DIV-31 (repetição de sentido segue recusada, mesma mensagem) |
| Vocabulário de domínio preservado | Conforme | Nomes em português mantidos; aliases só acrescentam |

Busca textual de TC-DOC-01 repetida sobre o estado final (`grep -rniE 'estado local|sem estado|n[aã]o h[aá] estado|[uú]nica depend[eê]ncia|sem depend[eê]ncias|sqlite3|python3|lib/db' README.md lib commands bin install.sh`): 13 ocorrências, nenhuma contrária a RF-38, RF-61, RNF-02, RNF-26 ou RNF-33 — `lib/hash` ("sem estado persistente", verdadeiro para o componente), `lib/auth` ("sem estado novo"), `lib/output` (reescrito), `lib/state` (o único cache), `unlink`/`bin/dbx` ("remove estado local", que é o que o comando faz), README (dependência única = cURL; parágrafo do legado SQLite; `--dry-run` sem alterar estado).

Prova de "só comentários" em `lib/http.sh` e `lib/transfer.sh` (item 4 da delegação):

```
git diff -w --unified=0 -- lib/http.sh lib/transfer.sh | grep -E '^[+-]' \
  | grep -vE '^(\+\+\+|---) ' | grep -vE '^[+-][[:space:]]*(#|$)' | wc -l
0
```

Linhas de comentário: `lib/http.sh` 334 → 310; `lib/transfer.sh` 450 → 368. O histórico retirado está em [2026-10-19-historico-comentarios-http-transfer.md](../registros/2026-10-19-historico-comentarios-http-transfer.md), uma seção por função (21 seções).

## Ferramentas locais executadas

| Ferramenta | Comando | Resultado | Disponível no projeto |
|---|---|---|---|
| Linter | `shellcheck` 0.10.0 sobre os 9 arquivos de produto e os 5 de teste alterados | 0 achados (exit 0) | Sim |
| Sintaxe | `bash -n lib/http.sh lib/transfer.sh` (pelo fork) | ok | Sim |
| Type checker | — | Não aplicável à stack | Não |
| Análise de ciclos | inspeção dos `source` do diff | nenhum `source` novo | Não (manual) |

- Limitações por ausência de ferramenta: nenhuma que afete o veredito.

## Achados

| # | Arquivo:linha | Achado | Regra violada | Correção esperada | Severidade | Status |
|---|---|---|---|---|---|---|
| 1 | `lib/sync.sh:88` | `DBX_SYNC_LOCALIDADE` é lida do ambiente só para a suíte simular a ausência (TC-CX-05); passa a ser uma variável de ambiente não documentada para o operador | `comp-common-closure` (contrato implícito) | Aceitar como seam de teste (padrão de `DBX_HASH_BACKEND`), ou o Tech Lead decide documentá-la; registrar a decisão | Menor | Aberto, para decisão do Tech Lead |
| 2 | `commands/config.sh:114-140` | O diagnóstico de `--debug` invoca também `mount`, `grep`, `getenforce` e `lsattr`, protegidos por `command -v`; RNF-34(c)/TC-DOC-01 citam só `df` e `tail`. Ficaram documentados no README como opcionais, fora do preflight | RNF-02 (lista igual ao que o código invoca) | Tech Lead/BA confirmam que opcionais protegidos por `command -v` ficam fora da lista do preflight | Menor | Aberto, para decisão do Tech Lead |

- Total de bloqueantes: 0
- Total de maiores: 0
- Total de menores: 2

## Achados do ciclo anterior

Não aplicável: ciclo 1.

## Veredito

- Resultado: **Aprovado**
- Justificativa objetiva: nenhum achado bloqueante nem maior; arquitetura preservada (comparação e detecção em `lib/sync`, decisão de avisar no comando, apresentação por `lib/output`); `shellcheck` limpo; código de `lib/http.sh` e `lib/transfer.sh` intacto, provado pelo diff filtrado e pela suíte.
- Ressalvas registradas, com owner e prazo: achados 1 e 2 são menores e ficam como pontos de decisão do Tech Lead antes do commit.
- Handoff liberado?: Sim
- Próximo passo do ciclo do developer: registro de entrega pelo `documentation-writer` e validação independente do QA Expert.

## Devolução ao agent

Não aplicável: aprovado.

## Registro

- Decisões duráveis candidatas a memória (cabe ao Tech Lead): seam `DBX_SYNC_LOCALIDADE` (achado 1); critério de opcionais fora do preflight (achado 2).
- Referenciado pelo registro de entrega da demanda.

---

## Ciclo 2 (2026-10-19) — QA-P4-01

- Diff do ciclo: `lib/config.sh` (cabeçalho) e `lib/auth.sh` (bloco "O ACCESS TOKEN VIVE SÓ EM MEMÓRIA"), só comentário. Prova: `git diff -w --unified=0 -- lib/config.sh lib/auth.sh`, filtrado para linhas que não são comentário, dá 0 linhas. `shellcheck lib/config.sh lib/auth.sh`: exit 0.
- Consistência (RNF-34, RF-38, RF-61): o texto agora diz o porquê atual — a credencial é o único arquivo com segredo, e `lib/state` guarda só a memória de hash. A busca `unica escrita|nao ha cache|sem estado local` em `lib/`, `commands/`, `bin/`, README e `install.sh` não encontra mais nada.
- Fora do diff, por delegação: QA-P4-02 (System Design) é do Business Analyst.

| # do ciclo anterior | Achado | Status atual | Evidência da correção |
|---|---|---|---|
| QA-P4-01 | Afirmação de "única escrita persistente" contradiz RF-38/RF-61 | Corrigido | Caso 7 do QA verde; suíte 935/0/2 |
| 1 | Seam `DBX_SYNC_LOCALIDADE` | Aberto, para decisão do Tech Lead | — |
| 2 | Opcionais do `config --debug` fora do preflight | Aberto, para decisão do Tech Lead | — |

- Veredito do ciclo 2: **Aprovado**.
