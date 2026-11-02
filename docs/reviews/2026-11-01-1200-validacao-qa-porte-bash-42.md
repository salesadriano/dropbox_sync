# Validacao independente do QA: suporte-bash-42, PARTE B (porte para bash 4.2)

- Papel: QA Expert | Data: 2026-11-02 | Porte: G | Ciclo: 1 | Log: `docs/prompts/2026-11-01_1200_suporte-bash-42.md`
- Base: worktree `feature/porte-bash-42` sobre 26f2452 (PARTE A) + alteracoes nao commitadas
- Ambientes: host (bash 5) e CentOS 7 (bash 4.2.46, imagem fixada por digest) por `sh scripts/suite-bash42.sh`

## Veredito ciclo 1: REPROVADO (ver "Ciclo 2" ao fim: APROVADO)

A porta funciona e os itens 1, 2, 3, 5 e 6 da validacao passam. O bloqueio e um **caminho de perda de dados no CentOS 7 / bash 4.2 sem `C.UTF-8`, escondido por um pulo de teste** (QA-B42-01, item 4). A degradacao do produto nessa condicao **nao falha fechada**, ao contrario do que o pulo afirma (RF-54(f), RF-80 "item filtrado nunca e apagado").

## Achados

### QA-B42-01 (Bloqueante, Regra 6 de `protocolo-tdd` e RF-80): `--incluir` impreciso apaga nome local nao UTF-8 sem `C.UTF-8`

- Reproducao (CentOS 7, bash 4.2.46): copia de `tests/integracao/filtros_test.sh` com apenas o pulo do caso `div103_receber_espelhar_incluir_impreciso_nao_apaga_nome_nao_utf8` trocado por `:`. Arvore local com `lixo\xff.bin` (ausente no remoto) e `z.txt`; remoto com `k.txt`. Comando: `sync --receber --espelhar --confirmar --origem /r --destino <local> --incluir $'[!\xc3\xa9]*'`.
- Esperado (DIV-103): o nome nao UTF-8 fica fora do escopo e nao e apagado. Obtido: **`lixo\xff.bin` foi apagado** (`assert_arquivo_existe`: "caminho ausente").
- Mesma causa no nivel de biblioteca: `tests/unit/filtro_test.sh::div103_incluir_impreciso_em_bytes_nunca_casa_a_mais` sem o pulo retorna `dentro` onde se espera `fora`.
- Causa: `dbx_filtro_classificar` (`lib/filtro.sh`, ~l.537) decide "byte invalido" por `[[ $caminho =~ ^.*$ ]]` sob a localidade fixada. Sem `C.UTF-8`, o shell cai em `C`, todo byte e valido, o modo `bytes` (que torna os padroes imprecisos nao casantes no `--incluir`) nunca e ativado e o conjunto negado casa o nome. Nao e exclusivo do 4.2: vale para qualquer host sem `C.UTF-8`; a PARTE B so o tornou visivel ao rodar a suite onde a localidade falta, e o pulo o encobriu.
- Pulos que escondem o defeito (pulam por `_localidade_disponivel || pular`): `filtros_test::div103_receber_espelhar_incluir_impreciso_nao_apaga_nome_nao_utf8`, `filtro_test::div103_incluir_impreciso_em_bytes_nunca_casa_a_mais` e `qa_filtros_banda_b4::teste_qa_e03_div99_nome_nao_utf8_com_caractere_nao_ascii_e_protegido`. Outros pulos de `qa_retencao_b6` (`s09`, `s20`, `s21`) e de `retencao_test`/`reter_test` nao foram reexecutados sem pulo por limite de chamadas (ver "Nao verificado").
- Correcao esperada (Senior Developer): ou o produto detecta a localidade ausente e **trata todo nome nao ASCII como nao UTF-8 verificavel** (modo bytes, `--incluir` impreciso nao casa), ou o `sync --espelhar` com filtro **recusa** (`10`) quando a localidade falta e ha nome fora do ASCII; em ambos os casos o caso pulado deve **passar** no CentOS (sem pulo) ou ser substituido por equivalente que prove o mesmo no 4.2. Pulo e legitimo so para o que exige a dobra Unicode, nunca para o que prova "nada apagado".
- Nota ao Tech Lead: e achado de classe (um pulo mascarando falha de seguranca de dados). Revisar todos os pulos de localidade com o criterio "o caso afirma ausencia de efeito destrutivo?".

### QA-B42-02 (Menor): `lib/ref.sh` recusa chave vazia em vetor associativo

`dbx_ref_obter`/`dbx_ref_existe`/`dbx_ref_remover`/`dbx_ref_definir` com chave `''` dao `bad array subscript` (identico no bash 5 e no 4.2; limite do shell, nao regressao do nameref anterior, que tinha o mesmo comportamento). Chaves do produto sao caminhos nao vazios. Recomendacao: documentar o contrato em `lib/ref.sh`.

### QA-B42-03 (Menor): sonda `_localidade_disponivel` copiada em 9 arquivos de teste

Funcao identica duplicada (`filtros_test`, `sync_test`, `filtro_test`, `progresso_linha_test`, `retencao_test`, `reter_test`, `qa_retencao_b6`, `qa_filtros_banda_b4`, `qa_debug_transferencias_b12`). Divergencia futura entre copias reabre o QA-B42-01. Mover para `tests/support/`.

## Resultado por item

1. **`lib/ref.sh`: sem injecao.** Script adversarial proprio (rodado no host e no CentOS 4.2.46, mesmo resultado): chaves `$(touch M)`, `` `touch M` ``, `a]=$(...);b[`, `x'; touch $M; '`, `$((0))`, `*`, `@`, `a b`, `\`, `"`, `]`, `[`, `a[$(...)]`; valores com `$()` e crase; nomes invalidos (`A;touch $M`, `A[0]`, vazio, `1a`, `a b`, `$(...)`, `A$(...)`, `a-b`) devolvem 2 sem tocar em nada. Marca nunca criada nos dois ambientes; ida e volta (definir, obter, existe, remover) exata, salvo chave vazia (QA-B42-02). Vetor indexado com subscrito nao numerico da erro aritmetico sem executar o comando (contrato documentado no cabecalho: so indice gerado pelo codigo). Script em `/tmp/claude-1000/-home-sales-dropbox-api/2ff24614-40ea-4758-b4ef-217243293a08/scratchpad/adv.sh` (nao versionado).
2. **`dbx_par_aguardar_algum`: correto.** No CentOS 4.2.46: lista vazia e lista so de vazios retornam 0 sem laco; PID morto na entrada retorna de imediato e o codigo de saida (7) e preservado pelo `wait` seguinte; PID vivo e aguardado (3 s); PID ja colhido retorna 0 (nao pendura); 30 filhos com codigos 1..4,0 colhidos um a um sem perda (30 codigos corretos); morto sem `wait` e detectado (bash colhe o zumbi, `kill -0` falha). Chamadores: `commands/sync.sh` (fatia `descarregados:lancados-descarregados` exclui os consumidos; no lote, `pids` e podado dos mortos a cada volta, entao nao ha laco ocupado), `lib/transfer_paralelo.sh` e `lib/download_paralelo.sh` (lista so dos `v` em voo). Risco residual aceito: reciclagem de PID dentro do mesmo processo exigiria esgotar o espaco de PIDs durante a espera; nao reproduzivel.
3. **Eco do terminal e corpo ilegivel no CentOS: verde.** `http_test` 72 aprovados / 0 reprovados / 2 pulados; `perfis_test` 40/0/0; `reter_test` 78/0/6 (os 6 pulos sao de localidade). Pulos de `http_test` nao eram de localidade; nao investigados alem da contagem.
4. **Pulos de localidade: REPROVADO por amostragem.** Amostra: 5 pulos de `filtros_test`, `filtro_test`, `qa_filtros_banda_b4` e `qa_retencao_b6` conferidos pela leitura e, para os de filtro, reexecutados sem pulo no CentOS. A sonda so pula quando `C.UTF-8` falta ou o bash nao dobra caixa fora do ASCII (condicao correta), **mas** 2 casos da amostra expoem falha aberta (QA-B42-01). Nao verificado: ver abaixo.
5. **Suites `qa_*` alteradas (20): nenhum assert removido ou enfraquecido.** Das linhas removidas com assert, todas sao `${x@Q}` trocado por forma equivalente na mensagem (a mensagem, nao a comparacao), mais o ajuste de contagem de `_qa_linhas_de_falha`. As demais mudancas: `${v[@]}` -> `${v[@]+...}`, construcoes incompativeis, harness e pulos de localidade. Pulos novos sao o risco do QA-B42-01. Hashes abaixo.
6. **Gates mecanicos.** `bash scripts/verificar-remocao-de-casos.sh`: 2872 -> 2873 casos, "nenhuma reducao nao declarada". `sh scripts/inventario-de-testes.sh --check`: 115 arquivos, 2888 casos, 0 divergencias.

## Suites `qa_*` -> sha256 (arvore de trabalho atual, para o aceite do solicitante)

| Suite | sha256 |
|---|---|
| qa_cache_unico_p3_test.sh | 9bcba5854dd58dd9638ab9f8b9f192941f6864f3a10e762599bcdd944c6bd054 |
| qa_compartilhamento_b5_test.sh | 9379eff75d96f3c796c4225b03b643e1747d2d9b6d9c45c3827c85081c6d274a |
| qa_confinamento_remoto_b1b_test.sh | a124134826f79467a7afbf75c4ba24242daa037b8d73f65d383b2b947e88e2a6 |
| qa_consulta_diagnostico_b1_test.sh | 45ebf4dc751a3d30ada66e4e92fab297e55e53d057846fe28b8dd90827154312 |
| qa_cursor_b7b_test.sh | e762c6837d92258d6ffe9b0145b5c727f2c2daf458155e8d83307061b3436588 |
| qa_debug_transferencias_b12_test.sh | 12ba9c02cc5909f3e54e8dbd540808c7f4dc7d6a4f2140604a15b0441ec50a14 |
| qa_docs_aliases_p4_test.sh | 74c8dceff3c1557fc25e7b83f808651f0b8f0ee5ece0d03f4baa789c89cbae91 |
| qa_filtros_banda_b4_test.sh | cb09104cad84bb330a72448f7d092119f526329be732e3d46d984b867ed63dbd (ciclo 2; era 6759e6cc...) |
| qa_freebsd_b13_test.sh | 06206b91b87f2107604b95f917ea03bd82b5a5d4bf046b202581611cd662adf3 |
| qa_instalador_linha_b22_test.sh | 59486514e44cd4cc64778e6dab1311947cc09c27225a215ce73495fd1f2b4e98 |
| qa_leitura_exata_b14_test.sh | 34be413186db1773750ce5f46a59397b5220c4a9acb78585f7f27b4aa1e3f52e |
| qa_paralelo_upload_b19_test.sh | 9ea24e3e6fb231d968e2d12f1c402d4fa26b94050295f7d780ebfc66f3a1ecd4 |
| qa_perfis_b8_test.sh | 2aa733ce1f590f551fb92a3f68f6ecd529721c0eea61e0257898006f06136df4 |
| qa_recuperacao_b3_test.sh | 3d9ccd0b7a6cb3f2e309098dec8172ab67d3f5a28f27a3ec26655ded042ecd02 |
| qa_regex_portavel_b17_test.sh | f4f82122bea265da7efaeed4d8b7d4f8de7a8a809a432824ef624bc7ea1ce18d |
| qa_retencao_b6_test.sh | 0c0a8a2870cc2b397d75b1d971b4aa3953a704134bba2396906401eb11c4f611 |
| qa_retomada_b7a_test.sh | 6215eeec64face1d759d0da64db4509b8644f0fb31038ee52e363f8df8d096dd |
| qa_robustez_rede_p2_test.sh | 110d26b7c7063a5a3bee64ecefab0a5f282e8a6a0c644d605ea2faada126b6a8 |
| qa_sync_blocos_b21_test.sh | e2fcbcd6cdeae90d59ecb23171615ba898cc025586af7c54d872f818526c72b6 |
| qa_trava_tmp_b2_test.sh | 4e414ac5d52218976ff921bd5b6649100f79556dc6699efc6b12cdb31d9e12ba |

Estes hashes nao devem ser aceitos pelo solicitante antes da correcao do QA-B42-01: `qa_filtros_banda_b4`, `qa_retencao_b6` e `qa_debug_transferencias_b12` mudarao se os pulos forem trocados por prova no 4.2. Testes criados por este QA: nenhum arquivo versionado (copias temporarias sem pulo foram removidas); inventario inalterado.

## Nao verificado (limite de 30 chamadas)

- Pulos de `qa_retencao_b6` (`s09`, `s20`, `s21`), `retencao_test`, `reter_test`, `sync_test`, `qa_debug_transferencias_b12` e `progresso_linha_test` reexecutados sem pulo no CentOS: apenas lidos por amostragem. `s21` e o caso "falha fechada sem localidade" e deve ser o primeiro a ser reexecutado sem pulo. O Tech Lead deve pedir a reexecucao sem pulo de todos antes de reaprovar.
- Pulos de `http_test` (2) e testes de terminal (`stty sane`, fifo) so conferidos pelo resultado verde.
- Nao repetida a suite completa dos 115 arquivos (instrucao).

## Divergencias

Nenhuma entre PRD/ARD e a implementacao alem do QA-B42-01 (RF-54(f) e RF-80 x comportamento sem `C.UTF-8`; severidade bloqueante para o aceite, recomendacao acima). Ciclos de reprovacao desta implementacao: 1.

## Ciclo 2 (2026-11-02): QA-B42-01 corrigido. Veredito: APROVADO COM RESSALVAS

### Revalidacao adversarial no CentOS 7 (bash 4.2.46, sem C.UTF-8)

- Suite nova do QA `tests/integracao/qa_exclusao_sem_localidade_b42_test.sh`: 6 casos, 6 aprovados, 0 pulados. Cobre `--receber --espelhar` com `--incluir '[!a]*'` (o cenario de perda do ciclo 1), `--incluir` preciso nao ASCII (literal, `?`, prefixo), `--excluir` com acento (prefixo, conjunto, `?`), ramo de pasta (`pasta\xff/`, `pastaé/sub/`, `ascii/é.txt`) com `--incluir '*'` e `'[!a]*/'`, sem filtro, e `--enviar --espelhar` com remoto so nao ASCII. Nomes: byte invalido `\xff`, UTF-8 acentuado, euro, emoji, caixa alta e baixa. Em todos, nada com byte nao ASCII e apagado. Vermelho contra `lib/filtro.sh`, `lib/sync.sh` e `commands/sync.sh` do ciclo 1 (copia em scratchpad, reprovou no CentOS).
- Inventario: bloco e linha de indice acrescentados em `docs/testes/inventario-de-testes.md`; o arquivo e untracked (so `git ls-files` e descoberto), logo o `--check` so o enxerga depois que o Tech Lead o incluir no indice (`git add`): precisa rodar `sh scripts/inventario-de-testes.sh --check` de novo ao commitar. Hoje: 115 arquivos, 2893 casos, 0 divergencias (sem o arquivo novo). `verificar-remocao-de-casos.sh`: 2872 -> 2878, nenhuma reducao.

### Pulos de localidade restantes, pelo criterio "o caso afirma ausencia de efeito destrutivo?"

Reexecutei sem pulo no CentOS os que o nome sugere protecao: `qa_filtros_banda_b4` e03, e13, e15 (com as asserts `assert_arquivo_ausente`, positivas, neutralizadas na copia): 20 aprovados; as asserts de preservacao passam. As falhas que restam nesses casos sao so do sentido seguro (arquivo mantido onde o caso esperava apaga-lo). e16: unica divergencia e `ü/` com `Þ/a` classificado `filtrado` em vez de `escopo` (fica fora do escopo, nao e apagado). `sync_test` `caixa_fora_do_ascii_e_um_caminho...` sem pulo: as asserts `a_apagar=0` e `_exclusoes==0` passam; falha so em `/r/éa.txt` (escrita com a grafia do destino, positivo); `..._conteudo_igual_e_omitida` falha em `identicos=1` (positivo). `retencao`/`reter`/`qa_retencao_b6` s09, s20, s21, rtg04: o produto devolve 10 com "nada foi apagado"; os casos esperavam 0 (positivo), e a prova de nada apagado ja vem do proprio codigo 10. Mutantes (`div161/162/164/165/167/168`) precisam da dobra para discriminar. `progresso_linha` e `qa_debug_b12` 3/16: formato de saida, sem efeito destrutivo (a falha do b12 e a linha de aviso, sem exclusao). Nenhum pulo restante esconde efeito destrutivo.

### Ressalvas (nao bloqueiam)

- QA-B42-03 (menor): `_localidade_disponivel` duplicada em 9 arquivos; acompanhamento do Tech Lead.
- A retencao em `dbx_sync_reter_nao_ascii` e ampla: sem localidade, todo caminho nao ASCII sai do plano de exclusao do `--espelhar`, mesmo quando o espelho o apagaria legitimamente. Aviso unico informa a contagem. Falha no sentido seguro, aceita (RF-54(f2), DIV-391).
- Os casos que exigem a dobra Unicode seguem sem prova no 4.2 sem localidade; so se provam em host com `C.UTF-8`.

### sha256 do ciclo 2

Unica suite `qa_*` pre-existente alterada no ciclo 2: `qa_filtros_banda_b4_test.sh` = `cb09104cad84bb330a72448f7d092119f526329be732e3d46d984b867ed63dbd` (diff verificado: so pulos removidos e protecao `${v[@]+...}`; nenhuma assert removida). Suite nova: `qa_exclusao_sem_localidade_b42_test.sh` = `649577d9dd49cda804016b18d931ff6ca55b5b44168da0360d7f631e9e816c3b`. As demais 19 suites alteradas mantem o sha256 da tabela acima (reconferido: identicos).

> Nota do Tech Lead (2026-11-02): `qa_exclusao_sem_localidade_b42_test.sh` recebeu do TL so a simulacao da ausencia (`DBX_SYNC_LOCALIDADE=xx_XX.UTF-8` em `_rodar`), para valer tambem no host com `C.UTF-8`; nenhum assert mudou. Verde no host e no CentOS 7. sha256 atualizado acima.
