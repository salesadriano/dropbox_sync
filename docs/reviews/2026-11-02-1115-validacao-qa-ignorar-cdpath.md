# Validacao independente do QA: ignorar-cdpath (porte M, defeito em producao)

Data: 2026-11-02 | Papel: QA Expert | Escopo: `bin/dbx` (`unset CDPATH` apos `set -u`) e `tests/integracao/sync_test.sh`.

## Veredito: APROVADO (sem achado bloqueante nem maior; 1 ressalva informativa e 1 investigacao parcial)

## Suite independente
`tests/integracao/qa_cdpath_test.sh` (8 casos, verde: `bash tests/run.sh qa_cdpath` -> 8 aprovados, 0 reprovados).
sha256 `57be5d41d9c76c6a76561d6b75d08b2e28deb8abab75814d2a3419424fb1326d` (arquivo novo: o Tech Lead ja o encontra com `git add -N`, feito aqui).

Metodo: cada comando roda sem CDPATH (linha de base) e com CDPATH=`.`, `<isca>`, `<isca>:.`, `<isca>:`, `:<isca>`, onde `<isca>` tem `sub/`, `sub/deep/` e `local/sub/` homonimos com arquivos `iscaso*`. O desfecho (codigo de saida, URLs e caminhos remotos tocados, arvores local, destino e isca com tamanho e cksum) tem de ser identico ao da base, a isca nunca e lida nem alterada e o stderr nao pode ter erro de sintaxe. Casos: upload de pasta, upload de pasta `--paralelo 2`, download de pasta, verificar (enviar e receber), sync enviar `--espelhar --confirmar` (simples, `--bloco 1`, `--paralelo 2`), sync receber `--espelhar --confirmar` (simples, `--bloco 1`, `--paralelo 2`).
Prova absoluta no caso mais perigoso (receber + espelhar, CDPATH=`<isca>:.`): o excedente do destino (`dest/sub/extra.txt`, `dest/sub/deep/b.txt`) e apagado; `dest/a.txt` e o recebido `dest/remoto.txt` existem; a arvore local de origem e a isca ficam intactas (nada fora do destino apagado, nada do remoto apagado por engano).

Vermelho contra `bin/dbx` de HEAD (copia em `/tmp/claude-1000/-home-sales-dropbox-api/2ff24614-40ea-4758-b4ef-217243293a08/scratchpad/red`): `sync_enviar_em_blocos_e_paralelo` reprova ("CDPATH=[.] tem o mesmo desfecho da linha de base"); `download_de_pasta` passa nos dois. O runner para no primeiro erro (Regra 9), entao os demais casos nao rodaram em vermelho: so o primeiro vermelho esta provado por execucao; o efeito nos demais vem da mesma causa (`cd` relativo em `lib/walk.sh`).

## Achados
- Menor (informativo): `download` de pasta e insensivel ao defeito (passa com e sem a correcao); mantido como guarda de regressao, sem valor de vermelho.
- Menor: o vermelho por caso nao foi isolado individualmente (parada no primeiro erro); registrado como limitacao.
- Observacao: o teste novo do `sync_test.sh` ja estava no inventario; nada a acrescentar.
- Nao executavel nesta rodada: Cypress/E2E nao se aplica (CLI shell); sem gatilho de formulario.

## Investigacao de outras variaveis de ambiente (so reporte, fora do escopo)
Metodo: `QA_EXTRA='VAR=valor'` aplicado so nas execucoes hostis; a divergencia da linha de base e o criterio.
- `GLOBIGNORE=*`: sem diferenca (APROVADA).
- `BASH_ENV=<arquivo com shopt -s dotglob nullglob; set -f>`: ALTERA o desfecho (sync enviar em blocos reprova contra a base). `bin/dbx` executado com `bash` le `BASH_ENV` antes do script, e o `set -f`/dotglob muda a expansao de globs da biblioteca. Neutralizavel com `unset BASH_ENV` e `set +f`? Nao: ja e tarde em `bin/dbx` (o arquivo e lido antes); so um re-exec com `env -u BASH_ENV` no shebang/launcher resolveria. Risco real baixo (so em ambiente deliberadamente hostil), recomendo registro como risco.
- `ENV`, `IFS`, `POSIXLY_CORRECT`, `SHELLOPTS` (noglob, xtrace, errexit, nounset), `BASHOPTS` (dotglob, nullglob, failglob, nocaseglob): NAO CONCLUIDO: a sondagem excedeu o teto de chamadas e o tempo (cada sonda reexecuta a suite de ~40 s). Reproduzir com `QA_EXTRA='SHELLOPTS=noglob' bash tests/run.sh qa_cdpath` (o suporte ja esta na suite). Pelo desenho (`env -i` do bash nao herda IFS; `SHELLOPTS`/`BASHOPTS` exportados sao lidos pelo bash na partida), SHELLOPTS=errexit/nounset/xtrace e BASHOPTS com glob sao os candidatos mais provaveis a quebrar.

## Inventario
`docs/testes/inventario-de-testes.md` atualizado (linha de resumo e secao da suite, contagem 115 arquivos, 2896 casos); `sh scripts/inventario-de-testes.sh --check` -> 0 divergencias.

## Recomendacao ao Tech Lead
Aprovar a correcao; levar a suite `qa_cdpath_test.sh` ao aceite do solicitante (regra 12); abrir item de risco para BASH_ENV/SHELLOPTS/BASHOPTS e decidir se vale endurecer o launcher.

## Ciclo 2: reexec limpo de BASH_ENV, ENV, SHELLOPTS e BASHOPTS (bin/dbx)

Veredito do ciclo 2: APROVADO, com 1 ressalva menor. sha256 vigente da suite `qa_cdpath_test.sh`: `57be5d41d9c76c6a76561d6b75d08b2e28deb8abab75814d2a3419424fb1326d`.

1. Sem laco: o reexec so ocorre com `DBX_AMBIENTE_LIMPO` vazia e a marca e removida depois (`unset`), entao ha no maximo 1 `exec`. Marca herdada do operador: nao reexecuta, e o ambiente hostil continua valendo (a protecao e desligada por quem exporta a marca). Sem laco e sem erro; aceitavel como escolha explicita do operador, mas e um desvio registrado (ressalva menor, documentar). Se `env` nao estiver no PATH o reexec falha com 127 (so em PATH sabotado).
2. Argumentos: `sync --enviar --origem '<dir com espaco, [ ] e *>' --destino '/d est'` com BASH_ENV+SHELLOPTS=noglob+BASHOPTS=failglob produz saida identica a do ambiente limpo; `"$@"` repassa vazio, `--` e quebra de linha por construcao (a prova por execucao desses tres ficou so no nivel do erro de opcao global, que para no primeiro argumento invalido: limitacao).
3. Stdin e saida: `upload - /r/x.bin` com pipe, e `compartilhar --senha-stdin`, tem o mesmo estado e as mesmas chamadas de rede com e sem BASH_ENV; o segredo nao aparece nos argumentos do `curl`; codigo de saida (2 em comando desconhecido) preservado.
4. Invocacao: `$0` por vinculo simbolico absoluto, por `./dbx`, por `bash dbx` no diretorio do vinculo e via PATH, todos com BASH_ENV hostil, conduzem ao mesmo resultado esperado (nenhum erro de reexec).
5. QA_EXTRA da suite (BASH_ENV, ENV, SHELLOPTS=noglob/xtrace/errexit/nounset, BASHOPTS=dotglob/nullglob/failglob/nocaseglob): os 10 resultados sao APROVADA, desfecho identico a linha de base. Fecha a investigacao que estava incompleta no ciclo 1; `IFS` nao e herdado por `env -i` e `POSIXLY_CORRECT` nao foi sondado (fora da lista do ciclo 2).
6. Custo: com ambiente limpo o bloco so avalia expansoes e `compgen -e` (embutido) e nao faz `exec`; o `strace` nao existe no host, entao a contagem de processos nao foi medida, so lida no codigo.

Inventario: caso `teste_bash_env_e_opcoes_exportadas_nao_mudam_o_plano` do sync_test acrescentado, sha da suite atualizado; `--check` conferido (ver resultado no hand-back).

> Nota do Tech Lead (2026-11-02): ressalva do item 1 tratada. A marca `DBX_AMBIENTE_LIMPO` saiu; o processo reexecutado nasce sem `BASH_ENV`, `ENV`, `SHELLOPTS` e `BASHOPTS` e por isso nao recomeca, e nenhuma variavel do operador desliga a protecao.
