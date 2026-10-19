# Parecer do DBA — Arquivo de trava no diretorio de estado (fase 2, RF-69 a RF-71)

| Campo | Valor |
|---|---|
| Modulo | `lib/state` (cria e remove a trava, `DIV-41`), `lib/tmp` (guarda a liberacao), `commands/sync`, `commands/verificar`, `commands/diagnostico`, `commands/unlink` |
| Responsavel | DBA, por delegacao do Tech Lead (regra 44); porte M |
| Data | 2026-10-19 |
| Memoria transposta | `2026-10-19-1419-trava-de-concorrencia` (citada por id, regra 43) |
| Log de prompt | [2026-10-19_1419_backlog-fase-2-trava-e-tmp.md](../prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md) |
| Destinatarios | Business Analyst (handoff, regra 26) e Tech Lead |
| Parecer anterior | [2026-10-18-2243-parecer-dba-cache-unico.md](2026-10-18-2243-parecer-dba-cache-unico.md) |

## 1. Criacao exclusiva

| Opcao | Atomica | Ve conteudo parcial | Veredito |
|---|---|---|---|
| `set -C` (`noclobber`) | sim (`O_EXCL`) para arquivo comum | **sim**: o arquivo nasce vazio e o conteudo chega depois | recusada para a trava final; serve so ao `alteracoes-externas.sh`, que tolera a janela com a regra "sem pid e com mais de 1 min" |
| `mkdir` | nao no uutils coreutils sob concorrencia (ja registrado em `scripts/alteracoes-externas.sh`) | nao | **recusada** |
| temporario completo + `ln` | sim (`link(2)` falha com `EEXIST`) | **nao**: o nome da trava so existe com o conteudo inteiro | **recomendada** (e o que `RF-69(g)` pede) |

Receita: `mktemp` em `$dir/.trava.$$.XXXXXXXX` (0600, mesmo diretorio, mesmo sistema de arquivos), gravar o conteudo completo, `ln -- temp trava-<resumo>`, apagar o temporario em qualquer desfecho. Duas travas do `ln`: **(a)** se `trava-<resumo>` for um **diretorio**, `ln` cria o elo *dentro* dele e retorna sucesso; por isso o codigo de saida do `ln` nao basta, e o sucesso e `[[ $temp -ef $trava ]]` (mesmo inode) apos o `ln`. **(b)** recusar de saida `-L` e `-d` no nome da trava. O `ln` e utilitario POSIX e ja esta no `lib/preflight` (conferir; senao entra na lista, `RNF-34`).

## 2. Conteudo e leitura segura

Uma linha, campos separados por TAB, terminada por campo-fim: `dbx-trava<TAB>1<TAB>pid<TAB>host_id<TAB>inicio_epoch<TAB>comando<TAB>fim`. A versao permite recusar formato futuro; o campo-fim detecta truncamento (a publicacao por `ln` ja evita parcial, mas edicao manual e disco cheio existem).

Leitura: nunca `source`, nunca `eval`, nunca `read` sem limite.
- So aceita `-f`, `! -L`, `-O` (dono = usuario), tamanho <= 512 bytes; le com `IFS= read -r -n 512` uma unica linha.
- Valida por campo: `pid` so digitos, de 2 a 7 casas (**`kill -0 0` e `kill -0 -1` atingem grupos de processos**, entao 0, 1 e negativos sao invalidos); `host_id` em `[A-Za-z0-9._:-]{1,255}`; `inicio` so digitos; `comando` em `{sync, verificar}`; versao `1`; campo-fim presente; numero exato de campos.
- Qualquer falha e **ilegivel** (`DIV-40`): nunca retomada, nunca apagada. A mensagem imprime so campos ja validados; o conteudo cru nunca vai a terminal (sequencia de escape em stderr).
- `host_id` = `hostname` + `boot_id` (`/proc/sys/kernel/random/boot_id`) + inode do namespace de pid (`/proc/self/ns/pid`), quando existirem. Sem isso, dois containers com o mesmo hostname e diretorio de estado compartilhado fariam o `kill -0` mentir e a retomada derrubaria trava viva. Boot_id diferente no mesmo host prova orfandade (reinicio).
- Reuso de pid: pid vivo mas de outro programa parece trava viva. Falha para o lado seguro (nao retoma); o remedio e manual, e o `diagnostico` ja o diz. Nao comparar `mtime` (relogio) para decidir vida.

## 3. Retomada de orfa sem corrida

`rm` seguido de criacao **tem corrida**: A e B leem a mesma orfa; A apaga e cria a sua; B (que ja decidiu) apaga a trava **viva de A** e cria a sua. Dois donos. `mv` por nome sobre a orfa tem o mesmo defeito (move o que estiver no nome naquele instante).

**Recomendacao:** serializar a retomada com uma segunda trava exclusiva, `trava-<resumo>.r`, criada pela mesma receita `ln`. Quem a obtem (1) **le de novo** a trava e confirma que ainda e a mesma orfa (mesmo pid, `host_id`, inicio); (2) apaga a orfa; (3) cria a nova por `ln`; (4) apaga a `.r`. Quem nao obtem a `.r` trata como trava ocupada (a `.r` dura milissegundos; com `--esperar` basta a sondagem seguinte). Se (1) mostrar outra identidade, solta a `.r` e volta ao inicio. Fica um unico residuo, aceito e documentado: processo morto *dentro* da janela de retomada deixa `.r` orfa; ela **nao** e retomada sozinha (evita recursao), aparece no `diagnostico` como `ilegivel`/`orfa` com remedio manual. `flock(1)` foi descartado: nao esta na lista de utilitarios, e nao e confiavel em NFS.

## 4. Interacao com a memoria do par

Ordem obrigatoria: **trava, leitura de `memoria-*`, gravacao atomica (`_dbx_state_gravar_arquivo`: `mktemp` + `mv`), liberacao.** Ler antes de travar permitiria que dois processos partissem da mesma memoria e o ultimo `mv` apagasse a gravacao do outro (atualizacao perdida; a gravacao atomica protege o arquivo, nao a sequencia). Liberar so depois do `mv`, e sempre conferindo pid e inicio gravados antes do `rm` (`RF-69(c)`).

Morte entre a gravacao e a liberacao (`SIGKILL`, queda de energia): a memoria esta integra (o `mv` e atomico: ou a antiga ou a nova inteira) e a trava fica orfa; a proxima execucao a retoma com aviso (mesmo host) e segue. Nenhum dado se perde, porque a memoria nao decide (`RF-38`, `DP-27b`). Morte durante a gravacao deixa `.memoria.*`, ja varrido apos 1 dia. **Acrescentar** `.trava.*` a esse `find` de `_dbx_state_preparar_diretorio` (mesma regra `-mtime +0`); sem isso o temporario da trava vaza.

## 5. Diretorio de estado em NFS

`link(2)` e atomico em NFS v3/v4, mas a resposta pode se perder e ser retransmitida: o `ln` **retorna `EEXIST` embora tenha criado o elo**, e o processo acha que perdeu e ninguem detem a trava (ou, pior, cache de atributos faz a checagem ver estado velho). Mitigacao classica: o criterio de sucesso e o **inode do temporario igual ao da trava** (`-ef`), nunca o status do `ln`; o nome do temporario embute `host_id` e pid para ser unico entre maquinas. Alem disso o `kill -0` nao atravessa hosts: por isso a trava de **outro host nunca e retomada** (decisao ja tomada, correta). Relogio nao entra em nenhuma decisao. Detectar NFS (`stat -f -c %T`, quando existir) e **avisar** no `diagnostico`, sem bloquear; o padrao `$XDG_STATE_HOME` e local. Garantia de exclusao entre hosts em NFS e declarada como **melhor esforco**.

## 6. Poda e `unlink`

A poda de `RF-61` (`_dbx_state_podar_upload`) so enumera e apaga por `upload-*`; `trava-*` e `trava-*.r` nunca casam. Manter assim por teste (diretorio com mais de 10.000 `upload-*` antigos, uma trava viva e uma orfa: ambas intactas) e **nunca** podar trava por idade. A limpeza de temporarios apaga so `.memoria.*`, `.upload.*`, `.trava.*`.

`unlink` com trava viva (`DIV-44`): recusa com `7` se existir trava `viva` (mesmo host, pid existente) de qualquer par; trava `orfa` nao impede e **nao e apagada** pelo `unlink`; `outro-host` e `ilegivel` geram aviso e seguem (a memoria so e descartavel). Limite conhecido: o `unlink` nao trava, entao um `sync` pode iniciar logo depois da checagem; o pior caso e a memoria ser regravada, sem efeito sobre decisao.

## 7. Handoff ao Business Analyst (regra 26)

Virar criterio de aceite, com caso de teste:
1. Sucesso de criacao = inode do temporario igual ao da trava (`TC-TRV`: alvo diretorio e alvo ligacao simbolica recusados).
2. Formato `dbx-trava`/versao 1/campo-fim; matriz de hostil: vazio, truncado, sem campo-fim, pid `0`, `1`, `-1`, `99999999`, host com escape, arquivo > 512 bytes, ligacao simbolica, dono alheio; todos `ilegivel`, nenhum apagado, nenhum byte cru em stderr.
3. `host_id` com boot_id e namespace de pid; boot_id diferente = orfa.
4. Retomada serializada por `trava-*.r`: 2 e 20 retomadores da mesma orfa, exatamente um adquire; `.r` orfa nao retomada.
5. Ordem trava, leitura, gravacao, liberacao (dobro de ordem); morte entre gravacao e liberacao deixa memoria valida e trava retomavel.
6. `RNF-25(c)`: `.trava.*` entra na varredura de temporarios com mais de 1 dia.
7. Poda e `unlink` nunca removem trava; `unlink` recusa so com trava viva.
8. NFS: criterio `-ef`, aviso no `diagnostico`, garantia entre hosts declarada como melhor esforco (novo risco no registro de riscos).
9. `RNF-26` emendado: a trava e a unica escrita nova, de `lib/state`, com 0600/0700.

## Parecer

**Aprovado com as condicoes dos itens 1 a 7.** Sem migracao de schema: o arquivo e transitorio e `DBX_STATE_VERSAO` nao muda. Rollback: remover o `trava-*` ocioso nao altera resultado algum (`RF-69(i)`).
