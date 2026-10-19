# Fase 1b do backlog: confinamento remoto (F-36) e controle no caminho remoto (F-37)

## 1. Pedido e porte

| Campo | Valor |
|---|---|
| Pedido | Fase 1b do plano do backlog, extra, decidida pelo solicitante depois de um achado do QA da fase 1: aplicar a `raiz_remota` (F-36) e recusar byte de controle em caminho remoto (F-37). Requisitos RNF-20(b1..b8), RNF-10(b), RNF-20(e), RF-16, RSK-19, TC-SEC-18..33. |
| Porte | M. Defeito de seguranca (fuga da raiz remota configurada, escrita e exclusao fora do confinamento) que toca contrato publico (codigo de saida 13 em mais comandos, `list` sem argumento), credencial e entrada de usuario. Sem gatilho de G: nenhuma arquitetura nem integracao externa nova (analise de tres abordagens no parecer do Senior Developer). |
| Log de prompt | [docs/prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md](../prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md) |
| Branch / base | `bugfix/confinamento-remoto-b1b` sobre `develop` @ `c1c1f88` |
| Agents | Business Analyst (requisitos v1.11); Senior Developer (implementacao, sob `protocolo-tdd` e `protocolo-conformidade`); QA Expert (validacao independente, 13 casos); Tech Lead (decisoes, fechamento). |
| Data | 2026-10-19 |

## 2. Causa ou decisao

Causa raiz: `_dbx_cmd_caminho_remoto` (`lib/cmd.sh`), por onde os oito comandos ja passavam, chamava so `dbx_path_remoto_para_api`, que normaliza e nunca le `DBX_CONFIG_RAIZ_REMOTA`; nada olhava byte de controle. A credencial ja estava carregada antes do comando, mas ninguem a consultava.

Decisoes na memoria [2026-10-19-1243-confinamento-remoto](../../.github/agents/memoria/entradas/2026-10-19-1243-confinamento-remoto.md), entre elas: a dobra de caixa so ASCII, a raiz `/` sem opt-in e a classe `caminho_recusado` (13).

Abordagens consideradas (parecer do Senior Developer, obrigatorio em defeito de alta criticidade):

- **A, escolhida:** ponto unico em `_dbx_cmd_caminho_remoto`, apoiado em politica de dominio nova `dbx_path_remoto_argumento <raiz> <caminho>` em `lib/path`. Recusa antes de qualquer rede, cobre o destino derivado (`upload` de diretorio, `download` de pasta) e permite auditoria estatica de comandos futuros. Custo: alterar as oito chamadas para `|| return $?`.
- **B, rejeitada:** pre-validacao em `bin/dbx`. Teria de conhecer a gramatica de cada comando e o destino derivado escaparia.
- **C, rejeitada:** guarda no transporte. Recusaria depois da renovacao do token (viola RNF-20(b2)), acoplaria transporte e dominio e erraria em `upload_session/finish`.

Modelo: o caminho digitado e absoluto na conta e recusado fora da raiz; relativo segue recusado (13). Controle no caminho: 13, citado com `%q`, nunca o byte cru. Raiz da credencial malformada: `configuracao` (3), falha fechada.

Comportamentos aceitos pelo Tech Lead:

- `list` sem argumento lista a `raiz_remota` configurada (com raiz `/`, nada muda).
- Raiz malformada sai com 3.
- Destino derivado de nome local com `\n` e recusado.
- Caminho legitimo com acento em outra caixa, fora do ASCII (`/AÇÃO/x` contra `/Ação`), e recusado: limite aceito, falha fechada (RNF-20(b4), TC-SEC-33).

Requisitos: [escopo-requisitos-e-criterios-de-aceite](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [funcionalidades-candidatas](../requisitos/funcionalidades-candidatas.md), [riscos-restricoes-e-licenciamento](../requisitos/riscos-restricoes-e-licenciamento.md).

## 3. Arquivos

Levantado com `git status --short` e `git diff --numstat c1c1f88`; arquivos novos contados por `wc -l`.

| Arquivo | Alteracao | Linhas (+/-) |
|---|---|---|
| `lib/path.sh` | Alterado (`dbx_path_remoto_argumento`, canal `DBX_PATH_MOTIVO`, dobra so ASCII sob `LC_ALL=C`) | +83/-3 |
| `lib/cmd.sh` | Alterado (`_dbx_cmd_caminho_remoto` le a raiz, diagnostico unico) | +49/-8 |
| `commands/config.sh` | Alterado (raiz explicita `/`) | +2/-4 |
| `commands/delete.sh` | Alterado | +1/-4 |
| `commands/download.sh` | Alterado | +1/-4 |
| `commands/info.sh` | Alterado | +1/-4 |
| `commands/list.sh` | Alterado (sem argumento lista a raiz) | +3/-5 |
| `commands/sync.sh` | Alterado | +1/-4 |
| `commands/upload.sh` | Alterado | +1/-4 |
| `commands/verificar.sh` | Alterado | +1/-4 |
| `tests/unit/path_test.sh` | Alterado | +149/-0 |
| `tests/unit/cmd_test.sh` | Alterado | +74/-0 |
| `tests/integracao/composicao_test.sh` | Alterado (auditoria e prova de discriminacao) | +82/-0 |
| `tests/integracao/confinamento_remoto_test.sh` | Novo | +286/-0 |
| `tests/integracao/qa_confinamento_remoto_b1b_test.sh` | Novo (QA) | +412/-0 |
| `tests/integracao/qa_consulta_diagnostico_b1_test.sh` | Alterado (QA da fase 1, so o comentario obsoleto, reaprovado) | +2/-2 |
| `docs/testes/mapa-modulos.md` | Alterado | +16/-15 |
| `docs/arquitetura/system-design.md` | Alterado (BA) | +1/-0 |
| `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` | Alterado (BA) | +5/-4 |
| `docs/requisitos/funcionalidades-candidatas.md` | Alterado (BA) | +4/-3 |
| `docs/requisitos/riscos-restricoes-e-licenciamento.md` | Alterado (BA) | +1/-1 |
| `.github/agents/memoria/entradas/2026-10-19-1243-confinamento-remoto.md` | Novo (decisao) | documental |
| `.github/agents/memoria/entradas/2026-10-19-1243-aceite-testes-qa-b1b-parcial.md` | Novo (aceite) | documental |
| `.github/agents/memoria/entradas/2026-10-19-1243-aceite-testes-qa-b1b.md` | Novo (aceite) | documental |
| `docs/prompts/2026-10-19_1243_backlog-fase-1b-confinamento-remoto.md` | Novo (log de prompt) | documental |

Total de linhas de codigo (producao e teste, sem documentacao): **1194** (1148 adicionadas, 46 removidas), somando `lib/`, `commands/` e `tests/`.

## 4. Testes rodados

Selecao por arquivo de teste, so dos itens afetados (Regra 8 de `protocolo-tdd`), pelo comando `bash tests/run.sh <filtro>`, um por vez, com parada no primeiro erro. Contagens literais da ultima selecao completa e sem interrupcao do Senior Developer, ciclo 1 (parecer, secao 2).

| Arquivo de teste | Item afetado que o justifica | Comando | Total | Aprovados | Falhos | Duracao |
|---|---|---|---|---|---|---|
| `json_test.sh` | auditoria de `lib/*.sh` | `bash tests/run.sh json` | 60 | 60 | 0 | 1,3 s |
| `http_test.sh` | auditoria de `lib/*.sh` | `bash tests/run.sh http` | 53 | 53 | 0 | 36,5 s |
| `preflight_test.sh` | auditoria de `lib/*.sh` | `bash tests/run.sh preflight` | 34 | 34 | 0 | 3,6 s |
| `composicao_test.sh` | `commands/*.sh` | `bash tests/run.sh composicao` | 27 | 27 | 0 | 6,0 s |
| `path_test.sh` | `lib/path.sh` | `bash tests/run.sh path` | 56 | 56 | 0 | 0,6 s |
| `output_test.sh` | `lib/*.sh` | `bash tests/run.sh output` | 31 | 31 | 0 | 0,3 s |
| `cli_test.sh` | `lib/cli.sh` | `bash tests/run.sh cli` | 17 | 17 | 0 | 0,2 s |
| `cabecalho_test.sh` | `lib/*.sh` | `bash tests/run.sh cabecalho` | 17 | 17 | 0 | 0,2 s |
| `cmd_test.sh` | `lib/cmd.sh` | `bash tests/run.sh cmd_test` | 23 | 23 | 0 | 0,7 s |
| `confinamento_remoto_test.sh` | `lib/path.sh`, `lib/cmd.sh`, 8 comandos | `bash tests/run.sh confinamento_remoto` | 10 | 10 | 0 | 14,1 s |
| `comandos_test.sh` | `commands/*.sh` | `bash tests/run.sh comandos` | 119 | 119 | 0 | 21,3 s |
| `sync_test` e `sync_plano_test` | `commands/sync.sh` | `bash tests/run.sh sync` | 91 | 91 | 0 | 34,0 s |
| `espaco_test.sh` | `commands/upload.sh`, `commands/sync.sh` | `bash tests/run.sh espaco` | 13 | 13 | 0 | 4,0 s |
| `verificar_test.sh` | `commands/verificar.sh` | `bash tests/run.sh verificar` | 17 | 17 | 0 | 3,3 s |
| `diagnostico_test` (2 arquivos) | `lib/cmd.sh`, `lib/preflight.sh` | `bash tests/run.sh diagnostico` | 35 | 35 | 0 | 15,6 s |
| `completar_test.sh` | `lib/*.sh` | `bash tests/run.sh completar` | 16 | 16 | 0 | 1,4 s |
| 8 arquivos `qa_*` | suites de QA das fases anteriores e da 1b | `bash tests/run.sh qa_` | 160 | 160 | 0 | 59,7 s |
| **Total, 17 execucoes, 26 arquivos** | | | **779** | **779** | **0** | **~203 s** |

- Lacuna: a tabela e do ciclo 1 do developer, com 0 pulados. No ciclo 2 so a suite inteira foi informada (abaixo), sem a selecao por filtro refeita.
- Execucao do developer no ciclo 2 (`bash tests/run.sh`): 37 arquivos, **1095 aprovados, 0 reprovados, 2 pulados** (preexistentes), 4 min 19 s, verde.
- Execucao do QA no ciclo 2 (`bash tests/run.sh`): 37 arquivos, **1098 aprovados, 0 reprovados, 2 pulados**, APROVADA. A duracao nao veio na delegacao.
- Red observado:
  - `path_test` (+9 `arg_*`): funcao inexistente.
  - `cmd_test` (+6 `caminho_remoto_*`): controle aceito, esperado 13 e obtido 0.
  - `confinamento_remoto_test`: contra a base, `upload [/fora]` saiu 0; depois da lib, ainda vermelho por diagnostico emitido 2 vezes.
  - `composicao_test` (+2): as 8 chamadas acusadas como "recusa nao propagada" contra a base.
  - Ordem raiz/caminho: esperado 3, obtido 2 (`dbx_path_remoto_argumento raiz raiz`) e esperado 3, obtido 13 (`list` sem argumento).
  - Ciclo 2: `[C.UTF-8] /RAİZ`, esperado 13, obtido 0, em `path_test` (`arg_caixa_fora_do_ascii_nunca_escapa_em_nenhuma_localidade`) e em `confinamento_remoto_test` (`sec26_...`, `[C.UTF-8] delete` saiu 0); o red do QA-B1B-02 e o caso `qa_b1b_raiz_com_controle_list_sem_argumento_sai_3` do QA.
- Parada no primeiro erro (Regra 9): atendida pelo runner (`Bail out!`). Interrupcoes corrigidas e reexecutadas do inicio: auditoria `json` acusou `$(printf %q)` no teste novo (trocado por `printf -v`); no ciclo 2, a auditoria do `preflight` acusou `{ local LC_ALL=C; } 2>/dev/null` e o `for letra` como comandos externos (trocados por `local LC_ALL=C` simples e `local letra`).
- Barreiras estaticas: `shellcheck` 0.10 limpo nos arquivos alterados ou novos, nos dois ciclos. Guarda `bash scripts/verificar-remocao-de-casos.sh`: 1066 para 1085 casos, sem reducao (1083 no ciclo 1).
- Testes de seguranca e acesso (Regra 6), contra o executavel real e o duplo de `curl`:
  - Fora da raiz `/raiz`: `/fora`, `/raizX`, `/raiz2/a`, `/RAIZX/a`, `/raiz/../fora`, `/raiz/..` e `/` (inclui o destino derivado de `upload dir /`) saem 13, sem nenhuma chamada, nem a renovacao do token, em upload (arquivo, `-`, diretorio), download, list, delete, info, sync e verificar nos dois sentidos.
  - Dentro da raiz, com caixa e `..` interno (`/Raiz/a`, `/RAIZ/x/../a`): aceito e enviado.
  - Controle (`\n`, `\r`, `\t`, `\001`, `\037`, `\177`) em toda forma e com raiz `/raiz` e `/`: 13, sem o byte cru no diagnostico (TC-SEC-28, TC-SEC-29).
  - Raiz `/` ou vazia: nada muda; `..` acima da conta e relativo seguem 13.
  - Raiz malformada (`raiz`, `/..`, com controle): 3, sem rede, inclusive `list` sem argumento.
  - Dobra de caixa (ciclo 2): U+0130, U+0131, U+017F, Kelvin U+212A, `ß`, `ẞ`, `ﬁ`, sosias de `/`, `.` e `R`, NFC e NFD recusados com 13 sob `C`, `C.UTF-8` e so `LANG=C.UTF-8`; a localidade nao vaza para o processo.
- Validacao de formularios em E2E (Regra 7): Nao aplicavel: projeto e CLI em shell, sem formulario.
- Suite completa local no push para a PR de `develop` (Regra 8): **PENDENTE**.

## 5. Gates

Parecer combinado dos dois gates locais, executados pelo Senior Developer, nesta ordem. Pareceres completos no material do Senior Developer (ciclos 1 e 2).

| Gate | Skills aplicadas | Achados (severidade, arquivo:linha, regra, correcao) | Veredito |
|---|---|---|---|
| `protocolo-tdd` | Regras 1 a 9; Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | nenhum | Aprovado |
| `protocolo-conformidade` | `clean-architecture` + `shellcheck-configuration`; `security-best-practices` (entrada de usuario e confinamento); Checklist aplicado integralmente; itens nao conformes ou nao aplicaveis listados em Achados | C-1 (maior, `lib/path.sh`, ordem raiz/caminho): `list` sem argumento com raiz malformada saia 13 e nao 3; corrigido no ciclo 1. C-2 (ciclo 1 menor, ciclo 2 bloqueante, `lib/path.sh`, `_dbx_path_dentro_de`): dobra de caixa dependente da localidade; era o QA-B1B-01; corrigido. C-3 (menor, `lib/path.sh`): `SC2034` sobre a funcao inteira para o canal publico `DBX_PATH_MOTIVO`, mesmo padrao do projeto; mantido. | Aprovado |

- Ciclo: 2. Status dos achados do QA no ciclo 1: QA-B1B-01 corrigido; QA-B1B-02 corrigido. C-1 corrigido; C-2 corrigido; C-3 justificado.
- `sh scripts/alteracoes-externas.sh --detectar`: limpo (exit 0) antes de cada passo e gate; `--registrar` apos cada passo.

## 6. QA

- Validacao independente do QA Expert em [tests/integracao/qa_confinamento_remoto_b1b_test.sh](../../tests/integracao/qa_confinamento_remoto_b1b_test.sh), 13 casos (10 no ciclo 1, mais 3 no ciclo 2), sha256 `235b95e2fa46f9a40d7498c8031d6b856cf7bca14f212b29aa77fa0937830c62`. Massa e duplo de `curl` proprios; em toda recusa o diario do duplo nao existe, nem `oauth2/token`.
- Revisao de teste aprovado em fase anterior (regra 12): `tests/integracao/qa_consulta_diagnostico_b1_test.sh`, so o comentario da linha ~241 ("raiz_remota nao e aplicada", obsoleto), sha256 `d19becd400b6fa0d30705969bf815737eb7ed89b25d330c6902ce1e5fd37fb11` (antes `9bf94d63...7ed8`). `docs/testes/mapa-modulos.md`, sha256 `166ad18ea59c7c27318ce573eaa7fa5d9f4ef1a072452e9be05a3090001e250d`.
- Ciclo 1: **Reprovado** (2 achados). QA-B1B-01 (alta, seguranca, RNF-20(b2)(b4), `lib/path.sh:150-151`): a comparacao sem caixa usava `${alvo,,}` na localidade do operador; com `raiz_remota=/Raiz`, `dbx delete --yes /RAİZ/fora` (U+0130) era recusado sob `LC_ALL=C` e saia 0 sob `C.UTF-8`, emitindo `oauth2/token` e `files/delete_v2` em pasta irma da raiz. QA-B1B-02 (media, RNF-20(b8), TC-SEC-31): `list` sem argumento com raiz contendo controle saia 13 e nao 3, porque o controle do caminho era checado antes da validade da raiz. Suite do ciclo 1: 30 arquivos, 885 aprovados, 2 pulados, 1 reprovado, parada em `qa_confinamento_remoto_b1b_test.sh`. Mutantes M1 a M6 mortos (6/6).
- Ciclo 2: **Aprovado**. Dobra so de A-Z sob `local LC_ALL=C`, fora do ASCII exige os mesmos bytes; raiz validada antes do argumento. Ataque refeito em `upload`, `delete`, `list`, `sync --enviar` e `verificar --receber` sob `LC_ALL=C`, `LC_ALL=C.UTF-8` e so `LANG=C.UTF-8`. Casos novos: `dobra_especial_nao_casa_com_a_raiz_em_nenhuma_localidade`, `raiz_com_acento_identica_ou_so_ascii_em_outra_caixa_e_aceita`, `dobra_ascii_nao_vaza_localidade_para_o_processo`; `caixa_unicode_nao_escapa_em_nenhuma_localidade` ganhou a variante `LANG=C.UTF-8`.
- Mutantes: ciclo 2, 8 de 8 mortos (M0 original aprova; M1 a M6 mortos; M7b, `${,,}` sem nenhum `LC_ALL=C`, morto; M8, `LC_ALL=C` global sem `local`, morto). M7 (volta ao `${,,}` so em `_dbx_path_dentro_de`) e equivalente: o `local LC_ALL=C` do chamador cobre a comparacao por escopo dinamico, defesa em duas camadas.
- Execucao: ver a secao 4 (37 arquivos, 1098 aprovados, 0 reprovados, 2 pulados; guarda de remocao de 1066 para 1085 casos).
- Veredito do QA: **Aprovado**, 2026-10-19 (ciclo 2).

## 7. Riscos e rollback

- Riscos residuais:
  - F-38 (raiz local configuravel): ressalva, backlog. Owner Tech Lead, sem prazo definido.
  - Limite aceito (RNF-20(b4), TC-SEC-33): caminho legitimo com acento em outra caixa fora do ASCII e recusado (falha fechada); ha falso-negativo e nenhum falso-positivo.
  - Localidades `en_US.UTF-8` e `tr_TR.UTF-8` nao existem no host (so `C`, `C.utf8` e `POSIX`): os testes de dobra foram pulados nelas, sem simulacao. A cobertura real e `C` e `C.UTF-8`; a defesa nao depende da localidade, porque a dobra e por tabela fixa A-Z.
  - C-3: `SC2034` sobre a funcao inteira, mesmo padrao do projeto.
- Licao do ciclo (honesta, do Tech Lead): o Senior Developer apontou o risco de localidade ja no ciclo 1 (C-2, item 5 do parecer) e o Tech Lead o classificou por engano como o risco antigo F-32, sem notar que a comparacao passara a ser barreira de seguranca. A classificacao anterior valia quando a dobra so servia a comparacao do `sync`; com o confinamento, um erro de dobra e escape. O QA reproduziu o achado como escape (QA-B1B-01) e a correcao veio no ciclo 2. Regra a reter: ao reaproveitar uma funcao preexistente como barreira de seguranca, reavaliar as ressalvas antigas dela como achados de seguranca, e tratar como bloqueante qualquer dependencia de localidade em comparacao de fronteira.
- Impacto: contrato. Com `raiz_remota` diferente de `/`, caminhos fora dela passam a ser recusados em todos os comandos que recebem caminho remoto (`upload`, `download`, `list`, `delete`, `info`, `sync`, `verificar`, `config --raiz`), com codigo 13 e antes de qualquer rede; `list` sem argumento lista a raiz configurada; byte de controle em caminho remoto e recusado (13); raiz malformada na credencial sai 3; a mensagem do `config --raiz` mudou. Sem schema, sem dependencia nova, sem pipeline. Nomes de itens vindos da arvore no `sync` seguem preservados (RNF-10(a)).
- Rollback: `git revert <sha>` basta. Nao ha migracao de dado nem de credencial.

## 8. Links e aceites

- Entradas de memoria: `2026-10-19-1243-confinamento-remoto`, `2026-10-19-1243-aceite-testes-qa-b1b-parcial`, `2026-10-19-1243-aceite-testes-qa-b1b`.
- Documentacao sincronizada: [escopo-requisitos-e-criterios-de-aceite.md](../requisitos/escopo-requisitos-e-criterios-de-aceite.md), [funcionalidades-candidatas.md](../requisitos/funcionalidades-candidatas.md), [riscos-restricoes-e-licenciamento.md](../requisitos/riscos-restricoes-e-licenciamento.md), [system-design.md](../arquitetura/system-design.md), [mapa-modulos.md](../testes/mapa-modulos.md).
- Commit(s): PENDENTE
- PR: PENDENTE
- Tech Lead: **Aprovado com ressalvas — Tech Lead, 2026-10-19**, valida so com a suite completa local verde.
- Solicitante: aceite dos `qa-*` registrado em [2026-10-19-1243-aceite-testes-qa-b1b-parcial](../../.github/agents/memoria/entradas/2026-10-19-1243-aceite-testes-qa-b1b-parcial.md) (`qa_consulta_diagnostico_b1_test.sh`, comentario) e [2026-10-19-1243-aceite-testes-qa-b1b](../../.github/agents/memoria/entradas/2026-10-19-1243-aceite-testes-qa-b1b.md) (suite nova, `qa_confinamento_remoto_b1b_test.sh`, sha256 `235b95e2...0c62`).
