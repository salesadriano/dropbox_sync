---
date: 2026-10-24
hora: "1153"
domain: suporte a FreeBSD (reabre DP-07), a partir da falha do chmod na gravacao da credencial
porte: G
status: aberto
instancia: myPCWin/Desenvolvedor Hydros
registro_de_entrega: "docs/reviews/2026-10-24-1153-registro-suporte-freebsd.md"
---

# suporte-freebsd

## Prompt 1 — 2026-10-24

> how fix
>
> (colagem da saida de `dbx --debug config`, sanitizada; client_id, URL de autorizacao e codigo de autorizacao removidos)
>
> ```
> chmod: --: No such file or directory
> [debug] === DIAGNOSTICO OPERACIONAL DE CONFIGURACAO ===
> [debug] Processo: PID=<pid> EUID=0 UID=0 USER=root
> [debug] Alvo da credencial: /root/.config/dbx/credencial.json
> [debug] Diretorio existe: sim (tipo: dir, perm: 700 (drwx------), dono: 0:0, gravavel: sim)
> [debug] Arquivo existe: sim (perm: 644 (-rw-r--r--), dono: 0:0)
> [debug] Montagens relevantes:
> /dev/da0p2 on / (ufs, local, soft-updates, journaled soft-updates)
> erro: gravacao da credencial falhou: gravacao (falha ao gravar ou mover credencial)
> ```

**Intencao:** fazer o `dbx config` (e o resto da CLI) funcionar no FreeBSD do solicitante (UFS, root).

**Causa levantada pelo Tech Lead:** o `chmod` do FreeBSD usa `getopt` sem permutacao: em `chmod 600 -- arq` o `--` vem depois do primeiro operando e vira nome de arquivo. Mesmo padrao em `lib/config.sh:525` (credencial), `lib/state.sh:153` (memoria do sync), `lib/cmd.sh:663` e `:1049` (modo do arquivo baixado, falha engolida). Alem disso ha ~40 usos de construcoes GNU em `lib/`, `commands/` e `bin/` (`stat -c`, `sed -i`, entre outras). `DP-07` fixou "So cURL, bash 4+, Linux" e `tests/unit/preflight_test.sh` impede reintroduzir camada BSD.

**Decisao do solicitante (AskUserQuestion, 2026-10-24):** "Suportar FreeBSD": reabre a `DP-07`; auditoria de todos os usos GNU, alternativa portavel e testes.

**Porte:** G. `scripts/porte.sh` nao existe no projeto. Altera regra de plataforma (decisao de arquitetura `DP-07`), toca credencial, estado e transferencias em todo o runtime.

**Seguranca:** a colagem trazia o `client_id` do app e um codigo de autorizacao de uso unico; nenhum dos dois foi persistido.

**Decisoes do solicitante sobre as DIV da secao 5.22 (AskUserQuestion, 2026-10-24):**
- DIV-352 "Preflight recusa (Recomendado)"; DIV-353 "Degradar e documentar (Recomendado)"; DIV-354 "Aceitar sha256 e openssl (Recomendado)"; DIV-355 "Duble + voce no FreeBSD (Recomendado)"; DIV-357 "Mensagens neutras + pkg (Recomendado)".
- DIV-356 "Liberar deteccao" (contra a recomendacao): o Tech Lead complementa com ponto unico de deteccao, `dbx_preflight_plataforma`.

## Prompt 2 — 2026-10-24

> (colagem da saida de `bash bin/dbx diagnostico` no FreeBSD do solicitante, passo 2 do roteiro; sanitizada, sem segredo)
> `dependencias: ok ... resumo SHA-256 via sha256sum`; `credencial: falha: a credencial tem permissao para grupo ou outros: /root/.config/dbx/credencial.json; remedio: chmod 600 ...`; `estado: ok: ainda nao criado`; `trava: ok: sem travas`; `saida=3`.

**Leitura do Tech Lead:** o modo `644` da credencial e o arquivo gravado pela tentativa de `dbx config` anterior a correcao (`chmod` falhou depois da escrita); o diagnostico o leu corretamente pelo `stat` do FreeBSD (`dbx_atributo`), o que ja confirma parte do RF-167 no sistema real. O FreeBSD do solicitante tem `sha256sum`. A linha "tipo do sistema de arquivos nao verificado" nao aparece porque o diretorio de estado ainda nao existe. Proximo passo: `chmod 600` (ou refazer o `dbx config`) e seguir o roteiro.

## Prompt 3 — 2026-10-24

> (colagem: passo 2 do roteiro e o teste de /dev/fd no FreeBSD 15.1-RELEASE-p3 do solicitante; sem segredo)
> Com `fdescfs` montado, `dbx space` ainda recusa com a instrucao do fdescfs. Sem opcao: `/dev/fd/3` e `Character Device`, `stat -L` da `1493237509|6`, `/etc/passwd` da `95|6572838`. Com `-o linrdlnk`: `/dev/fd/3 -> /etc/passwd`, mas `stat -L` da `1493237510|6|Symbolic Link` (o no do fdescfs, nao o arquivo).

**Leitura do Tech Lead:** no FreeBSD, nenhuma forma do `fdescfs` faz o `stat -L /dev/fd/<n>` externo devolver o `dev:ino` do arquivo, que e o que o produto usa (barreira do `.part`, cursor, preflight). A premissa da `DIV-352` (montar o fdescfs resolve) nao vale. Alternativa verificada no Linux: ler os atributos pelo proprio descritor (`stat -L -c <fmt> - <&N` no GNU; `stat -f <fmt>` sem operando no BSD) e, onde o produto reabre o arquivo por `/dev/fd/<n>` para escrita, abrir pelo caminho e conferir o `dev:ino` do novo descritor. Decisao levada ao solicitante.

**Decisao do solicitante (AskUserQuestion, 2026-10-24):** "Conferir pelo descritor (Recomendado)": substitui a DIV-352 C; atributos lidos do proprio descritor, reabertura por `/dev/fd` trocada por abertura pelo caminho com conferencia do `dev:ino`, sem exigir `fdescfs`.

**Decisao do solicitante (AskUserQuestion, 2026-10-25):** "Versionar o bloco (Recomendado)": o bloco `ai-team:roteamento` que o plugin escreve no `CLAUDE.md` e versionado nesta branch, para a suite oficial nao registrar a arvore como suja.

## Prompt 4 — 2026-10-25

> (colagem: saida de `bash bin/dbx config` no FreeBSD do solicitante, com a branch atualizada; sanitizada, identificador da conta mascarado)
> `aviso: a credencial anterior foi substituida; o refresh token antigo NAO foi revogado e segue valido na Dropbox`; `operacao: config`; `credencial: /root/.config/dbx/credencial.json`; `raiz_remota:` (vazia); `conta: dbid:****`.

**Leitura do Tech Lead:** o `dbx config` conclui no FreeBSD real, sem o `chmod: --: No such file or directory` que abriu a demanda (RF-166 confirmado no sistema real). O aviso de token nao revogado e o comportamento previsto ao substituir uma credencial existente. Falta conferir o modo `-rw-------` e seguir os passos 5, 6 e a secao 7 do roteiro.

## Prompt 5 — 2026-10-25

> `-rw-------  1 root wheel 172 Oct 25 19:21 /root/.config/dbx/credencial.json`

**Leitura do Tech Lead:** credencial gravada com modo `600` pelo `chmod -- 600` no FreeBSD real (RF-166 e TC-FBSD-01 confirmados no sistema do solicitante). Seguem os passos 5, 6 e a secao 7 do roteiro.

## Prompt 6 — 2026-10-26

> (colagens: passo 5 do roteiro no FreeBSD do solicitante; sem segredo)
> 1. `upload` de pasta: item 247/524 falha com `conflito path/conflict/file_ancestor`; o solicitante nota que o destino deveria ser `/ASJ/BRASIMAQBRA/UniNFe/...` e nao `VLG Dropbox/Usuario BKP/ASJ/...`.
> 2. `upload` de pasta com `nossoerp.bak.zip` (412689845 bytes, em `/mnt/e`): bloco 99 com `tamanho=18509`, `falha nossoerp.bak.zip: nao_concluida falha local`, saida 14.
> 3. `upload` do arquivo sozinho: `erro: envio em partes nao concluido: o arquivo mudou de tamanho durante o envio: tinha 412689845 bytes no inicio e foram lidos 411060301`; `ls -l` antes e depois: 412689845 bytes, mesma data.

**Leitura do Tech Lead:**
- (1) Uso: a origem era a pasta acima de `VLG Dropbox`; `dbx upload <pasta>/ASJ /ASJ` resolve. O `file_ancestor` fica restrito a arvore errada. O README nao explica a regra da barra final do destino (achado de documentacao, oferecido ao solicitante).
- (3) Defeito de portabilidade: o arquivo nao mudou, faltaram 1629544 bytes na leitura. `lib/transfer.sh` le cada parte com `head -c N <&fd` sobre o MESMO descritor; o `head` do FreeBSD le por stdio com leitura antecipada e consome do descritor mais do que imprime, entao o deslocamento avanca alem de N a cada parte. A conferencia de tamanho recusou a publicacao (nada corrompido foi enviado). O mesmo padrao esta em `lib/hash.sh` (`content_hash` do arquivo inteiro), `lib/transfer.sh` (reposicionamento e reabertura da retomada) e `lib/state.sh` (prefixo da retomada). O GNU `head -c` nao le alem de N, por isso a suite no Linux nao viu.
- (2) Achado: o `sync` troca o motivo de falha local pelo texto "falha local" (RF-59(c) so repassa o motivo na classe `integridade`); o motivo real so apareceu no envio unitario.
- Encaminhamento: leitura exata de N bytes por um ponto unico, sem leitura antecipada, com duble do `head` do FreeBSD que reproduz o consumo excedente (red medido), dentro desta demanda.

**Decisoes do solicitante (AskUserQuestion, 2026-10-26):** "Aprovo (Recomendado)" para `qa_leitura_exata_b14_test.sh` (sha256 `c7de4ca5…76c920b8`); "Reaprovo (Recomendado)" para `qa_consulta_diagnostico_b1` (`9a0dab8d…e661920a`) e `qa_debug_transferencias_b12` (`fa2d971d…e2fca987`).

## Prompt 7 — 2026-10-26

> (colagem: `dbx --debug upload` de `nossoerp.bak.zip` com a correcao RF-173 no FreeBSD; sem segredo) bloco 99 com `tamanho=1648053` (total 412689845, igual ao arquivo); `upload_session/finish` 409 `path/conflict/folder/`; `erro: envio em partes nao concluido: conclusao da sessao recusada: path/conflict/folder/`.

**Leitura do Tech Lead:** RF-173 confirmado no FreeBSD real: as 99 partes somam o tamanho do arquivo. A recusa e do destino: o caminho remoto passado ja e uma PASTA no Dropbox (upload de arquivo exige o caminho completo do arquivo). Achado de produto, fora do escopo FreeBSD: a pre-checagem `get_metadata` (RF-60) ve a pasta e segue, e a recusa so chega no `finish`, depois de enviar 393 MiB; destino com `/` no fim tambem nao recebe o nome do arquivo no envio de arquivo (so no de pasta). Oferecido ao solicitante como demanda separada.

## Prompt 8 — 2026-10-26

> (colagem: `dbx --debug upload` com destino `/ASJ/ASJEP/backup/nossoerp bkp` (pasta), interrompido com Ctrl+C duas vezes; sem segredo) `aviso: sem retomada nesta execucao: o registro de retomada nao pode ser gravado`; a segunda execucao recomeca do bloco 1 (`retomada=descartada motivo=estado-ausente`).

**Leitura do Tech Lead:** (1) o destino continua sendo pasta: a recusa viria no `finish`. (2) Defeito no FreeBSD real: `dbx_state_retomada_gravar` falha na primeira gravacao (logo apos o `start`); os dubles nao reproduzem (qa_leitura_exata_b14 retoma sob eles). Causa nao identificada pela leitura do codigo; sonda sem rede e sem credencial (conta ficticia) enviada ao solicitante para apontar a etapa. Hipotese residual: formato do `session_id` real (`^[A-Za-z0-9:_-]{1,256}$` em `_dbx_state_retomada_formato`).

## Prompt 9 — 2026-10-26

> (colagem: `dbx --debug download -p "/ASJ/ASJEP/backup/nossoerp bkp" /tmp/test` no FreeBSD; sem segredo) `get_metadata` 200; dois `GET files/download` com 409; `[download] o caminho remoto e uma pasta: recebendo conteudo recursivamente...`; `sync --receber` interno lista 4 arquivos e imprime o plano (`a_transferir: 4`). A colagem termina no plano.

**Leitura do Tech Lead:** a listagem e o plano no FreeBSD estao corretos; a colagem para antes das transferencias (execucao em andamento ou saida cortada). Achado menor, fora do escopo FreeBSD: o `download` tenta `files/download` duas vezes (409) depois de o `get_metadata` ja ter dito que o caminho e pasta.

## Prompt 10 — 2026-10-26

> (colagem: `dbx verificar --receber --origem "/ASJ/ASJEP/backup/nossoerp bkp" --destino "/tmp/test/nossoerp bkp"` no FreeBSD; sem segredo) `iguais: 4`, `diferentes: 0`, `so_origem: 0`, `so_destino: 0`, `total: 4` (inclui `nossoerp.bak.zip`, 388 MiB).

**Leitura do Tech Lead:** o download de pasta terminou e o `content_hash` local de arquivos de varios blocos confere com o remoto no FreeBSD real: `RF-173` confirmado no calculo do resumo (antes da correcao, o `head -c` do FreeBSD daria resumo errado acima de 4 MiB). Pendentes: sonda da retomada, passo 6 e secao 7.

## Prompt 11 — 2026-10-26

> (colagem: `dbx --debug download -p ".../nossoerp.bak.zip" /tmp/test/n.zip` no FreeBSD, interrompido apos 39 s em 0%, e reexecutado; sem segredo) `retomada=nenhuma`; depois `retomada=encontrada faixa=0- part_bytes=0`; progresso parado em 0 B / 335 MiB.

**Leitura do Tech Lead:** defeito da propria demanda (T5, destino `fd:` em `lib/http.sh`), em qualquer plataforma: o `--stderr <arquivo>` do curl reabre o stderr do processo, e o `-o /dev/stderr` passa a escrever no arquivo de mensagens, nao no `.part`. Medido com o curl real 8.18 no Linux (scratchpad `teste-curl-fd.sh`: `.part` 0 bytes, conteudo no arquivo de erros). A suite usa curl duble e nao via. Correcao: `--no-show-error` no lugar de `--stderr` no modo `fd:`, com teste que usa o curl real e URL `file://`. O registro de retomada do DOWNLOAD e gravado no FreeBSD (o do upload nao: sonda pendente).
