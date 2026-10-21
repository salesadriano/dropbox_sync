# Validacao independente do QA — Retencao e rotacao de backup (fase 6)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: F-10, `dbx reter`/`retain`; porte **G** (validacao independente e adversarial, regra 40)
- Agent: QA Expert; data 2026-10-20; ciclos: 5
- Branch / base: `feature/retencao-b6` sobre `develop` @ `d696c1d`, sem commit
- Registro de entrega: [2026-10-20-2010-registro-retencao-b6.md](2026-10-20-2010-registro-retencao-b6.md)
- Pareceres do desenvolvedor: [TDD](2026-10-20-2010-parecer-tdd-retencao-b6.md) e [conformidade](2026-10-20-2010-parecer-conformidade-retencao-b6.md)
- Fontes do QA: escopo v1.19 e v1.20, secao 5.14 (RF-93..100); memoria `2026-10-20-2010-retencao`; RSK-62..68; pareceres do developer
- Fonte deste documento: relatorio dos cinco ciclos do QA repassado pelo Tech Lead, resumido aqui. As tabelas de achados seguem o relatorio do QA.

## Suite do QA

`tests/integracao/qa_retencao_b6_test.sh`, 60 casos na versao final, duble de `curl` proprio, sem rede real. Qualquer mudanca na suite volta para a aprovacao do solicitante (regra 12).

| Versao | sha256 (prefixo) | Casos | Mudanca |
|---|---|---|---|
| Ciclo 1 | `21fc8c1f...` | 41 | Suite inicial: confirmacao (c00..c03), selecao (s01..s12), `parent_rev` (r01..r03), politica (p01..p08), listagem (l01..l06), delete (d01..d06), sinal (x01, x02) |
| Ciclo 2 | `08cc0440...` | 48 | s13..s18 e l07 novos; o duble ganhou `data.<endpoint>` e `sem_data.<endpoint>` (DIV-160) |
| Ciclo 3 | `d4ca76fe...` | 53 | s19..s23 novos; `qa_s11` ajustado pela DIV-163; o duble ganhou `QA_AMBIENTE` |
| Ciclo 4 | `bb17b865...` | 57 | s24..s27 novos; `qa_s09` e `qa_s20` ajustados pela DIV-166; `_qa_deletes` le em `LC_ALL=C` |
| Ciclo 5 (final) | `cd0178992648fc24132d992c86927c29b418e7cdcf3ac873ae426c591e258cad` | 60 | s28..s30 novos; oito casos ajustados pela DIV-169 (`_qa_arq` com rev `AUTO` e `id` opcional) |

**Aprovacao do solicitante (regra 12):** em 2026-10-20 ("Aprovo"), para a versao final, `cd0178992648fc24132d992c86927c29b418e7cdcf3ac873ae426c591e258cad`, com 60 casos. O log de prompt registra so essa aprovacao.

## Ciclo 1 — REPROVADO

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B6-01 | P0 | Uma listagem 2xx com a mesma entrada repetida (mesmo `path_lower` e `rev`) fazia o `reter --confirmar --manter 1` apagar o unico artefato da pasta, com `parent_rev` vigente, e sair 0. Variante: a duplicata na pagina 2, em outra caixa ASCII. O minimo de 1 e a guarda "nao e o primeiro" comparavam o indice, nao o caminho | Corrigido no ciclo 2 do developer (DIV-158: tres barreiras, listagem, plano e guarda (7) por caminho) |
| QA-B6-02 | P1 | `name` `..` com `path_lower` `/bk/..` passava a conferencia da listagem e so parava na guarda, depois de uma exclusao legitima (`apagados=1`, saida 10). O P0 nao foi violado: `/bk/..` nunca recebeu `delete_v2` | Corrigido no ciclo 2 (DIV-159: recusa na listagem, zero delete) |
| OBS-1 | Observacao | Com `--dias`, o `Date` vinha da 1a pagina e o "agora" era lido depois da ultima: listagem longa podia sair 3 por engano (falha fechada) | Corrigido no ciclo 2 (DIV-160: `Date` da ultima pagina) |

Atacado e sustentado: confirmacao (9 formas sem `--confirmar`, 7 combinacoes com `--dry-run`, 15 grafias vizinhas); selecao (`name` incoerente, `path_lower` fora da pasta, pasta, `deleted`, `symlink`, 20 padroes ardilosos, NFC contra NFD, plano anterior, guarda injetada com 23 linhas, confinamento); `parent_rev` (corpo exato, 9 revs malformados, conflito sem nova tentativa); politica (empate, `--manter` 1 a 6, corte inclusivo, minimo com empate, datas limite, 20 carimbos); listagem (`server_modified`, cursor repetido, `has_more`, 2xx malformado, teto de 1000 paginas, `Date` em varias formas e desvios); delete (`not_found`, 401, 429, rede, 2xx incoerente, 403 e 500, sentinelas de segredo, texto, `--json` e `--null`); sinal (TERM, INT e HUP na listagem e no delete). Todo `_qa_rodar` exige saida em 0..15; nenhum caso pendurou.

Resultado: caso a caso, 38 de 41 (falham `qa_s01`, `qa_s02` e `qa_s03`); `reter` 69/69; `retencao_test` 27/27. shellcheck limpo; RNF-24 sem `grep -c` e com `$(...)` so sobre dados internos.

## Ciclo 2 — REPROVADO

Confirmadas as correcoes de QA-B6-01 (duplicata exata, entre paginas, em caixa ASCII e com outra `.tag`), QA-B6-02 e OBS-1; os 41 casos do ciclo 1 passam.

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B6-03 | P0 | Duplicata que difere so na caixa fora do ASCII (`é.tar`/`É.tar`, mesmo rev) ainda apagava o artefato que fica: as tres barreiras da DIV-158 dobravam so o ASCII | Corrigido no ciclo 3 (DIV-161: chave sem caixa de RF-54 nas tres barreiras; `path_lower` diferente da propria chave sai 10) |
| QA-B6-04 | P1 | A guarda (7) falhava aberta sem a lista de quem fica (argumento omitido, vetor vazio, vetor inexistente). Sem exploracao direta, mas anulava a defesa em profundidade | Corrigido no ciclo 3 (DIV-162: recusa) |

Contornos que nao passaram: duplicata com outra `.tag`, em caixa ASCII entre paginas, nomes com `%` (nunca decodificados), `.`/`..`/barra final em entrada nao candidata.

Resultado: caso a caso, 45 de 48 (falham `qa_s15`, `qa_s17` e `qa_s18`); `reter` 76/76; `retencao_test` 30/30.

## Ciclo 3 — REPROVADO

DIV-163: toda linha do `qa_s11` passa `qa_ficam=(/bk/db-9.tar)`; as linhas de controle provam que a lista nao causa recusa; nenhuma linha removida nem esperado trocado. DIV-161 se sustentou: `path_lower` fora da propria chave sai 10 (`É`, `Ａ`, `ẞ`, `Σ`, `İ`, `Ǆ`); minusculas legitimas sem falso 10; sem a localidade, so ASCII funciona e o resto falha fechada; com `LC_ALL=C` exportado pelo operador, a duplicata ainda sai 10.

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B6-05 | P0 | O mesmo nome em NFC e NFD (`é.tar`, `e`+U+0301), mesmo rev, apagava o artefato que fica. Evidencia de terceiros (maestral, dbxcase) e o blog de engenharia da Dropbox indicam que o servidor compoe os decompostos: NFC e NFD sao o mesmo arquivo | Corrigido no ciclo 4 (DIV-164: marca combinante dos cinco blocos sai 10, falha fechada ampla) |
| QA-B6-06 | P1 | A guarda (7) aprovava lista de quem fica vazia na pratica (`('')`, `('' '')`, `(x y)`) | Corrigido no ciclo 4 (DIV-165: cada elemento precisa ser caminho canonico) |

Resultado: caso a caso, 51 de 53 (falham `qa_s22` e `qa_s23`); `reter` 78/78; `retencao_test` 34/34.

## Ciclo 4 — REPROVADO

DIV-166: `qa_s09` ficou mais forte (o nome NFD agora espera 10 com zero `delete_v2`; o padrao NFD contra nomes NFC segue 0 sem normalizacao); `qa_s20` trocou `i̇` por `ǆ` (U+01C6). DIV-164 e DIV-165 se sustentaram: bordas byte a byte dos cinco blocos (22 pontos x 2 posicoes) e vizinhos de fora passam; a lista de quem fica recusa todo elemento fora do formato canonico.

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B6-07 | P0 | Composicoes canonicas fora dos cinco blocos (`が`/`か`+U+3099, `ぱ`/`は`+U+309A, `한`/jamo conjuntos, `ऩ`/U+0928+U+093C), mesmo rev, apagavam a copia NFD com o rev vigente. Recomendacao do QA: exigir `rev` unico na listagem (opcao 2), mais barata e independente de tabela | Corrigido no ciclo 5 (DIV-167: barreira estrutural por identidade, `id` e `rev` unicos na listagem e comparados pela guarda (7)) |
| QA-B6-08 | P1 | UTF-8 invalido no `path_lower` (overlong, truncado, continuacao solta, 5 bytes, surrogate) passava e recebia `delete_v2`. O que fica nunca foi apagado, mas a listagem e incoerente; o overlong `E0 8C 81` escapava da deteccao por bytes da DIV-164 | Corrigido no ciclo 5 (DIV-168: UTF-8 valido por bytes, 10 sem delete) |

Resultado: caso a caso, 55 de 57 (falham `qa_s25` e `qa_s26`); `reter` 80/80; `retencao_test` 36/36.

## Ciclo 5 — APROVADO, com a OBS-2

DIV-169: `_qa_arq` ganhou rev `AUTO` (rev e id unicos por arquivo) e `id` opcional; `qa_s07`, `qa_s08`, `qa_p01` e `qa_s20` provam o mesmo que antes (`qa_s20` ficou mais forte, com UTF-8 valido nas bordas e 17 candidatos); as chamadas diretas da guarda em `qa_s11`, `qa_s17`, `qa_s18`, `qa_s22` e `qa_s27` passam rev e id alheios a quem fica, com vetores do mesmo tamanho da lista de caminhos. Os casos de duplicata (`s01`, `s02`, `s13`, `s14`, `s15`, `s17`, `s23`, `s26`) seguem com o mesmo rev/id, como uma duplicata real; a variante com rev e id distintos esta em `qa_s30`, onde as barreiras por grafia, sozinhas, seguram as quatro formas.

DIV-167 e DIV-168 sob ataque (se sustentaram):

- Guarda (7) por identidade (`qa_s28`, 20 linhas e 2 controles): recusa rev ou id igual ao de quem fica (inclusive no 2o item), rev ou id vazio, listas de tamanho diferente, elemento vazio, lista vazia, ausente, associativa, escalar, inexistente ou com nome invalido.
- Identidade na listagem (`qa_s29`): arquivo sem id (mesmo fora do padrao), com id vazio, numerico ou `null`, id ou rev repetido (inclusive entre paginas), rev ausente em nao candidato: 10 com zero delete; pasta sem id, ou com `rev` igual ao de um arquivo: sem falso 10. Rev so aceita `[0-9a-f]{9,}`; id e comparado exatamente, como identificador opaco.
- UTF-8 invalido em todas as formas (`qa_s25`, rev/id distintos): overlong de 2, 3 e 4 bytes, truncado de 2, 3 e 4 bytes, continuacao solta e a mais, 5 e 6 bytes, surrogates, acima de U+10FFFF, `F5`, `FE` e `FF`: todas 10 com zero delete.
- P0 dos ciclos 1 a 4: passam todos, inclusive `s26` e `qa_l05`.

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| OBS-2 | Risco residual (nao bloqueia) | Medida ad hoc, fora da suite: com rev E id DISTINTOS, a duplicata NFC/NFD fora dos cinco blocos (`が`, `한`, `ऩ`) ainda sai 0 e manda `delete_v2` para a copia NFD. Explorar exige uma listagem duplamente incoerente: o mesmo arquivo com dois `id` e dois `rev`, sendo vigente o rev da copia que sai; o `id` e estavel por arquivo no `files.stone`. Para fechar, so a lista completa de segundos elementos de composicao (opcao 1 do QA-B6-07). Sem caso falhando, porque contradiria decisao ja tomada | DIV-170: risco residual aceito pelo solicitante em 2026-10-20, registrado no RSK-68 |

Resultado da suite do QA no ciclo 5: 60 de 60, caso a caso e pelo runner. Runner: `qa_retencao_b6` 60, `reter` 84, `retencao` 98 (`retencao_test` mais `qa_retencao_b6`), todos aprovados. shellcheck limpo; RNF-24 sem `grep -c`, com `$(...)` so sobre dados internos (codigos de `lib/errors`, `command -v`, `mktemp` e o pid dentro do duble).

**Veredito do QA: APROVADO, 2026-10-20 (ciclo 5), sem achado P0 ou P1 aberto; OBS-2 aceita como risco residual (DIV-170, RSK-68).**
