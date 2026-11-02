# Parecer de Conformidade Arquitetural e de Boas Praticas - suporte-bash-42, PARTE B

## Identificacao

- Demanda: `suporte-bash-42` (porte G), log `docs/prompts/2026-11-01_1200_suporte-bash-42.md`
- Escopo: PARTE B do System Design (linha legada `support/bash-4.2`, versao `2.3.0-bash42`)
- Base: `26f2452` (PARTE A); diff de `feature/porte-bash-42`
- Responsavel: Tech Lead | Data: 2026-11-02 | Ciclo: 1

## Escopo verificado

| Arquivo | Alteracao | Verificado |
|---|---|---|
| `lib/ref.sh` (novo) | Acesso a vetor pelo nome sem nameref; `eval` so com o nome validado, chave e valor sempre como `$2`/`$3` | Sim (linha a linha) |
| `lib/errors.sh` | Carrega `lib/ref.sh`; mascaramento por `dbx_ref_*`; tabelas globais declaradas e atribuidas em separado (bug do 4.2) | Sim |
| `lib/sync.sh`, `lib/walk.sh`, `lib/cmd.sh`, `lib/http.sh`, `lib/output.sh`, `lib/retencao.sh`, `lib/compartilhamento.sh`, `commands/unlink.sh`, `commands/reter.sh`, `commands/sync.sh` | 28 namerefs trocados pelo auxiliar; `${x@a}` por `compgen -A arrayvar` + prefixo de `declare -p` lido por `read` | Sim |
| `lib/transfer_paralelo.sh`, `lib/download_paralelo.sh`, `commands/sync.sh` | `wait -n` por `dbx_par_aguardar_algum` (sondagem `kill -0`, pausa 0,05 s) | Sim, com correcao no ciclo (abaixo) |
| todo `bin/`, `lib/`, `commands/`, `completions/` | 114 expansoes `"${v[@]}"` protegidas com `${v[@]+...}` (mecanico) | Sim (por auditoria e mapa completo) |
| `lib/json.sh`, `lib/http.sh`, `lib/errors.sh` | `readonly X=(...)` e `declare -gA X=(...)` separados de declaracao e atribuicao | Sim |
| `lib/cli.sh`, `lib/tmp.sh` | Eco religado apos sinal durante `read -s` no 4.2 (`stty` opcional) | Sim |
| `lib/hash.sh` | Acumulador linear no 4.2 | Sim |
| `lib/http.sh` | Corpo ilegivel recusado com 26 antes do cliente | Sim |
| `lib/filtro.sh`, `lib/sync.sh`, `commands/sync.sh` | Falha fechada sem a localidade (`QA-B42-01`, `RF-54(f2)`, `DIV-391`) | Sim |
| `lib/preflight.sh`, `lib/cli.sh`, `install.sh`, `scripts/suite-completa.cmd` | Piso 4.2, versao `2.3.0-bash42`, suite oficial no CentOS 7 | Sim |
| `tests/` | Harness e suites no 4.2; auditoria nova; pulos de ambiente | Sim (por amostragem e pelo QA) |

## Verificacao arquitetural

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Conforme | `lib/ref.sh` nao depende de nada; e carregado pela raiz (`lib/errors.sh`) |
| Ciclos | `dep-acyclic-dependencies` | Conforme | guarda de carga `DBX_REF_CARREGADO` |
| Fonte unica | `comp-common-closure` | Conforme | um auxiliar de vetor por nome; um auxiliar de espera (`dbx_par_aguardar_algum`) para os tres chamadores; uma sonda de localidade ativa no filtro |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme | `stty` so em `lib/tmp.sh` (finalizador), condicionado a `command -v`; excecao justificada na auditoria do preflight |

## Verificacao da skill de stack

| Verificacao | Resultado | Evidencia |
|---|---|---|
| Lint | Conforme | `LINT_MEMORIA_MB=15360 sh scripts/lint.sh` sem achado (dois achados deste diff corrigidos: SC2124 em `lib/errors.sh`, SC2015 em `lib/retencao.sh`) |
| Injecao por nome de arquivo | Conforme | `lib/ref.sh` nunca interpola chave/valor em texto avaliado; 8 casos adversariais (`tests/unit/ref_test.sh`) e roteiro adversarial do QA no 4.2 |
| Guarda destrutiva falha fechada | Conforme apos o ciclo | `QA-B42-01` corrigido; suite do QA `qa_exclusao_sem_localidade_b42` (6 casos) |
| Auditoria estatica do 4.2 | Conforme | `tests/unit/bash42_auditoria_test.sh`, 7 casos ativos |
| Senha e segredo | Conforme | senha do link lida por `${!nome}` com nome validado; nunca em argumento, log ou texto avaliado |

## Achados

| Severidade | Arquivo | Achado | Correcao |
|---|---|---|---|
| Maior (corrigido) | `lib/transfer_paralelo.sh` | O auxiliar ignorava PID morto na entrada; segurava a gravacao do prefixo pelo filho mais lento (intermitencia de `qa_paralelo_download_b20`) | Retorna quando qualquer PID nao esta vivo, como `wait -n` |
| Maior (corrigido) | `commands/sync.sh` | Descarga em ordem passava ao auxiliar filhos ja mortos e nao descarregados: laco ocupado ate o primeiro terminar | Passa so os vivos |
| Bloqueante (corrigido, QA) | `lib/filtro.sh`, `lib/sync.sh` | `QA-B42-01`: exclusao sem a localidade | `RF-54(f2)` |
| Menor | `lib/retencao.sh` | `read < <(declare -p)` cria processo por chamada | Aceito: a captura `$(...)` e proibida pela auditoria de RNF-24 e o custo e por candidato a exclusao |
| Menor | `lib/sync.sh` | Funcoes de filtro copiam o vetor uma vez e regravam por `dbx_ref_anexar` (um `eval` por elemento) | Aceito: linear; mapas grandes sao lidos por elemento, sem copia |
| Menor | testes | `_localidade_disponivel` duplicada em 9 arquivos (`QA-B42-03`) | Acompanhamento |

## Limites declarados da linha legada

- Comparacao sem caixa fora do ASCII exige a dobra Unicode, que o bash 4.2 nao faz (nem com `en_US.UTF-8`): sem `C.UTF-8`, vale so no ASCII, com aviso e falha fechada (`RF-54(f)(f2)`).
- Casos que provam a dobra Unicode positiva pulam no CentOS 7 (convencao da suite); a prova roda no host.

## Veredito

**Aprovado.** Achados maiores e o bloqueante do QA corrigidos no ciclo; menores aceitos com motivo.
