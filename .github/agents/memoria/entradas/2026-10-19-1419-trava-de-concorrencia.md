---
id: 2026-10-19-1419-trava-de-concorrencia
tipo: decisao
escopo: projeto
titulo: Trava por par de sync, recusa imediata com --esperar, retomada de trava orfa no mesmo host
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst, dba
status: ativa
ref: docs/prompts/2026-10-19_1419_backlog-fase-2-trava-e-tmp.md
---

Decididos pelo solicitante em 2026-10-19 (fase 2, F-12):
- **Alcance:** uma trava por par de `sync`/`verificar` (conta × origem × destino). Pares diferentes rodam em paralelo; comandos avulsos não travam.
- **Trava ocupada:** recusa na hora, dizendo o pid e o início da execução que tem a trava. `--esperar N` (alias `--wait`) espera até N segundos.
- **Trava órfã:** é retomada com aviso quando o pid morreu no mesmo host. Trava de outro host nunca é retomada sozinha; o `dbx diagnostico` a mostra e diz como liberar.

A fase também entrega o `lib/tmp` (restante do F-31) e o C-1 da fase 1.

Divergências do BA decididas pelo Tech Lead:
- **DIV-38:** a chave do par é sem ordem; `--enviar A B` e `--receber B A` se excluem.
- **DIV-39:** o arquivo de trava é exceção explícita à proibição de escrita no `verificar` e na simulação; é transitório e sai no fim, então o diretório de estado termina igual.
- **DIV-40:** marcador `sem-conta` aceito; trava ilegível nunca é retomada e o `diagnostico` mostra o remédio.
- **DIV-41:** o `lib/state` cria e remove a trava; o `lib/tmp` só registra a liberação.
- **DIV-42:** o System Design reflete o `lib/tmp` real; o RNF-29(d) é emendado para tratadores compostos; os nomes `dbx-sync.*` ficam.
- **DIV-43:** trava ocupada usa `conflito`/7, com mensagem própria.
- **DIV-44:** o `unlink` recusa com 7 se houver trava de execução viva no mesmo host.
- **DIV-45:** o `unlink` mantém as travas não vivas e avisa sobre cada uma, conforme o parecer do DBA; o RF-51(f) ganha a ressalva.
- **DIV-46:** o `host_id` usa `$HOSTNAME`, com recuo para `/proc/sys/kernel/hostname`. A `.r` órfã é `orfa`, mas nunca é retomada automaticamente.
- Se a aquisição criou o diretório de estado, a liberação o remove com `rmdir` quando ele fica vazio (RF-69(e)).
- **DIV-47:** a parte "conta" da chave é um resumo local da credencial, não o `account_id`, porque obtê-lo exige rede e quebraria o RF-69(d) e o RF-65(b)/(c). Custo aceito: duas credenciais da mesma conta no mesmo diretório de estado não se excluem.
- **DIV-48:** diretório de estado de outro usuário ou sem escrita: a execução segue sem trava, com uma linha de aviso (coerente com o TC-EST-04, que já segue sem memória nesse caso).
- **DIV-49:** o `download` de pasta roda um `sync` por dentro, então também pega a trava do par.
- **DIV-50 (QA-B2-06 e BA):** só estado alheio ou sem escrita segue sem trava. Qualquer outro erro da aquisição falha com o próprio código. Se houver trava viva e legível num diretório sem escrita, a execução recusa com 7. Repetições esgotadas recusam com 7, nunca seguem sem trava.
- **DIV-51 (QA-B2-04):** stdout em socket vivo funciona normalmente. O código 15 só vale quando o consumidor de fato encerrou.
- **DIV-52 (QA-B2-05):** o `mkdir -p` do destino no `download` de pasta antes da trava fica aceito: é fora do estado e já está descrito no RF-69(h).
- **DIV-53 (casos 02×03 do QA):** a receita do DBA para retomar trava órfã fica como está (apaga a órfã, depois `ln`). O aviso passa a ser dado por quem apaga a órfã, mesmo que depois perca o `ln` para outra aquisição e saia com 7. Garantia: exatamente um vencedor e exatamente um aviso de órfã por órfã removida.
