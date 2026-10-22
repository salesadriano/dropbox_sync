# Parecer de Conformidade — Perfis nomeados de credencial, F-18 (fase 8)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: perfis nomeados de credencial (F-18, RF-120 a RF-132, DIV-236 a DIV-255); porte **G**; reabre a DP-05
- Agent responsavel pela alteracao e pela verificacao: Senior Developer (gate local); validacao independente a cargo do QA Expert
- Data: 2026-10-21; ciclo 1
- Branch / base: `feature/perfis-b8` sobre `dd129fb` (inclui o WIP `915cb52` e a arvore sem commit)
- Memoria da fase (criterio): `.github/agents/memoria/entradas/2026-10-21-1735-perfis.md`
- Parecer TDD (aprovado): [2026-10-21-1735-parecer-tdd-perfis-b8.md](2026-10-21-1735-parecer-tdd-perfis-b8.md)

## Escopo verificado

Diff: `git diff dd129fb -- . ':!scripts' ':!CLAUDE.md' ':!README.md' ':!docs/reviews/2026-10-21-1845*' ':!docs/prompts/2026-10-21_1845*' ':!.github/agents/memoria/entradas/2026-10-21-1845*'` (exclui o que veio da develop pelo merge `cee7b04`). 27 arquivos.

Lido por completo ou nos trechos de risco: `lib/config.sh`, `commands/unlink.sh`, `lib/state.sh` (trava por raiz), `lib/cli.sh`, `bin/dbx` (ponto de aplicacao), `commands/perfis.sh`, `lib/cmd.sh` (`dbx_cmd_ciclo_trava_raiz`), `lib/preflight.sh`. Nao lidos linha a linha: testes novos (cobertos pelo parecer TDD), `completions/dbx.bash`, `commands/config.sh` e `commands/diagnostico.sh` (so as linhas que citam o perfil), documentos.

## Stack e skills

Bash 4.4+ (shell). Aplicadas: `clean-architecture` (camadas), `shellcheck-configuration` (diretivas), `security-best-practices` (nome como dado de caminho, 0600/0700, sigilo). `lint` verde nos 20 arquivos shell da fase (`sh scripts/lint.sh`, exit 0, 71,22 s), registrado pelo Tech Lead; nao reexecutado aqui.

## Verificacoes

| Foco | Resultado |
|---|---|
| Nome validado antes de disco (RNF-37) | Conforme. `dbx_config_perfil_validar` e o ponto unico (regex com alfabeto explicito, `LC_ALL=C`, sem tocar disco); `dbx_config_caminho_de_perfil` valida antes de compor; `dbx_config_perfil_selecionar` nao fixa nome invalido. Em `bin/dbx` a selecao roda antes de preflight, rede e disco; `help` e `version` saem antes e `completar` e excluido |
| Caminho com nome nao validado | Nenhum. `perfis_listar` filtra pela mesma regex e recompoe por `caminho_de_perfil`; `unlink` e `diagnostico` usam `dbx_config_caminho`; `carregar <arquivo> <nome>` so recebe arquivo composto por `caminho_de_perfil` (ver CNF-03) |
| Modos 0600/0700 | Conforme. `umask 077` na gravacao, `chmod 700` nos diretorios criados por nos, `chmod 600` no temporario; `_dbx_config_verificar_cadeia completo` exige dono e `[0-7]00` em `dbx/` e `perfis/` e recusa simbolico (inclusive pendente) |
| Inexistente nao recua ao `padrao` | Conforme. `DBX_CONFIG_PERFIL_PADRAO` so e usado como valor de omissao em `dbx_config_caminho`, `unlink` (rotulo) e `perfis` (marca de ativo); perfil explicito ausente cai em `ausente`/exit 3 antes da advertencia e da rede (`unlink.sh` linhas 322 a 331) |
| `perfis/padrao.json` reservado | Conforme. `caminho_de_perfil padrao` devolve `credencial.json`, e `perfis_listar` ignora `padrao.json` em `perfis/` como entrada anomala |
| `DBX_PERFIL` sem segredo | Conforme. Valor invalido do ambiente nunca e ecoado (mensagem fixa); o aviso `perfil ativo X (DBX_PERFIL)` imprime so nome ja validado; vazio vale como nao definido |
| `unlink` seletivo (DIV-236/237/238) | Conforme. Remocao so por `cred-` do cabecalho (`DBX_STATE_RETOMADAS_CRED`/`CURSORES_CRED`), nunca por grafia; so arquivo regular, nao simbolico e do usuario (`-f`, `! -L`, `-O`); nao toca `memoria-*`, `upload-*`, `trava-*` do par/raiz nem faz `rmdir`; `.part` pela barreira de identidade; trava da retomada so se orfa e inalterada |
| Credencial ilegivel | Conforme. `ident` vazio com outros perfis restantes: aviso e nenhum estado removido; sem outros: remocao total (DIV-253, deliberado) |
| Identidade compartilhada (DIV-237) | Conforme. Nao revoga, so remove o arquivo, nomeia o outro perfil, mantem estado; nao comparaveis contados e avisados |
| Trava viva | Conforme. `_dbx_cmd_unlink_recusar_se_trava_viva` roda antes da advertencia, depois da revogacao e a terceira vez dentro da remocao; sai `conflito` (7); mensagem avisa que a trava nao identifica o perfil (DIV-247) |
| Guarda nao depende de estado do sync | Conforme. O `unlink` decide pela credencial e pelas travas lidas na hora, nao por memoria do sync; reconferencia de identidade apos a revogacao (C8 do DBA) |
| Trava por raiz (DIV-250, RF-132) | Conforme. Chave `dev:inode` por `stat -L`, sem grafia, perfil, conta ou credencial na chave nem no conteudo; mesmo registro e mesma aquisicao atomica da trava do par, nome `trava-*` (tratada por `unlink`/`diagnostico`); `--esperar` usa o que sobra do mesmo teto (`DBX_CMD_CICLO_ESPERA_S`), nunca o dobro; ocupada sai 7; so solta a propria (pid, host, inicio) e desfaz so o diretorio que criou |
| `lib/cli` e `bin/dbx` | Conforme. Opcao > variavel > `padrao`; repeticao (mesmo igual) sai 2 antes de validar; `--perfil` depois do subcomando so em `config` e `unlink`, `--help` vence, valor de `--raiz` e pulado; `lib/cli` valida via `dbx_config_perfil_validar` (sem regex paralela) |
| Diretivas `source=/dev/null` (`_dbx_cli_carregar_config`) | O comentario justifica (seguir `json.sh` e `config.sh` de novo a partir de `lib/cli` explode a memoria do `shellcheck`, e `bin/dbx` ja os segue). Aceito; ver CNF-02 |
| `commands/perfis.sh` | Conforme. Imprime nome, veredito, `ativo` e caminho; nunca valor de campo nem `cred-`; leitura de um perfil por vez com canais esvaziados (`_dbx_config_limpar_credencial`); entradas anomalas so entram em aviso escapado e limitado a 5; exit 0 mesmo com perfil quebrado |
| Camadas | Conforme. `lib/` nao referencia `commands/` (so o despacho de `lib/cli` monta o caminho do arquivo do comando, como antes); `lib/state` nao conhece perfil, so recebe `cred-`; `lib/config` e a unica a tratar nome; `commands/unlink` orquestra e delega a leitura de estado a `lib/state` |

## Achados

| ID | Severidade | Arquivo:linha | Achado | Regra | Correcao sugerida |
|---|---|---|---|---|---|
| CNF-01 | Menor | `lib/state.sh:1114` | `stat -L -c '%d:%i'` e so GNU, sem o ramo `stat -f` que `lib/config.sh` usa nos modos | `best-practices` (portabilidade), padrao do projeto | Aceitavel: o resto de `lib/state.sh` (linhas 668, 1611, 2089) ja usa `stat -c` sem ramo BSD. Registrar como limite de plataforma, nao corrigir nesta fase |
| CNF-02 | Menor | `lib/cli.sh` (`_dbx_cli_carregar_config`) | A diretiva `source=/dev/null` vale so para o proximo comando; a segunda linha `. lib/config.sh` nao tem diretiva propria. O lint esta verde (`external-sources=true`), entao nao ha defeito observavel, mas o comentario sugere que as duas sao cobertas | `shellcheck-configuration` | Repetir a diretiva acima de cada `.` ou deixar o comentario explicito sobre qual linha cobre. Nao verificado com `shellcheck` direto (proibido no briefing) |
| CNF-03 | Menor | `lib/config.sh` (`dbx_config_carregar <arquivo> <nome>`) | O 2o argumento nao e revalidado nem conferido contra `arquivo`; passar `padrao` com arquivo de `perfis/` pularia as verificacoes de cadeia | `dep-interface-ownership`, defesa em profundidade (RNF-37) | Hoje so `perfis` e `unlink` chamam (via `caminho_de_perfil`), e a auditoria estatica da suite restringe os chamadores. Sugerido: chamar `dbx_config_perfil_validar "$nome"` no ramo de 2 argumentos |
| CNF-04 | Menor | `lib/cmd.sh` (`dbx_cmd_ciclo_trava_raiz`) | Falha de permissao ao obter a trava de raiz segue sem a trava, com aviso (como a do par) | RF-132, DIV-250 | Aceito por simetria com a trava do par e porque a trava de raiz e protecao de concorrencia, nao a guarda destrutiva (essa independe dela). Registrar no registro de entrega |
| CNF-05 | Informativo | `lib/config.sh` (`perfis_listar`) | `credencial.json` simbolico pendente nao entra como `padrao` (`-e`), logo nao conta como "outra credencial" no `unlink` de perfil | DIV-238 | Sem efeito destrutivo observado (credencial pendente nao e utilizavel); nenhuma acao |

Nenhum achado bloqueante ou maior.

## Nao coberto

- Testes novos e `completions/dbx.bash` nao lidos linha a linha; `commands/config.sh` e `commands/diagnostico.sh` so nos trechos que citam o perfil.
- Nenhuma execucao de `shellcheck`, lint ou suite (proibidas no briefing); o lint verde foi aceito do Tech Lead.
- Comportamento em macOS/BSD nao avaliado (CNF-01).

## Veredito

**Aprovado com ressalvas** (4 menores e 1 informativo; nenhum bloqueante nem maior). Libera o handoff ao QA. As ressalvas CNF-02 e CNF-03 sao sugestoes de baixo custo; CNF-01, CNF-04 e CNF-05 apenas registradas.

## Nota do Tech Lead (2026-10-21)

- CNF-02 **nao procede**: em `lib/cli.sh` (`_dbx_cli_carregar_config`), cada `.` tem a propria linha `# shellcheck source=/dev/null` (json.sh e config.sh). O achado partiu de uma leitura que viu so a primeira diretiva. Status: descartado.
- CNF-03 segue para a validacao do QA como ponto de risco (nome de perfil e caminho), com decisao de correcao conforme o resultado.
