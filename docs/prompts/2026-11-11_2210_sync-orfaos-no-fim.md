# Sync em ciclos: orfaos apagados so ao fim da execucao

**Branch:** `feature/sync-orfaos-no-fim` (de `origin/develop` @ `03b225f`), worktree `../dropbox_api.worktrees/feature-sync-orfaos-no-fim`
**Porte:** M. `sh scripts/porte.sh` na entrada (arvore sem diff): `porte: P`. Reclassificado para M pelo Tech Lead porque muda o comportamento destrutivo do `--espelhar` (exclusao no destino) e reabre a ressalva da demanda `sync-ciclos-exclusao-indevida`.
**Instancia:** myPCWin/Adriano Sales Santos
**Issues:** nenhuma. **PRs abertas na entrada:** nenhuma. Release 2.4.1 em preparo (`chore/release-v241` e `feature/sync-ciclos-exclusao-indevida-bash42`), suspensa por decisao abaixo.

## Prompt 1 — 2026-11-11 22:05

> DBX_BLOCO=1000 dbx --debug sync --enviar  -p --origem /mnt/e/arquivos1 --destino /Amac/arquivos1 --espelhar --confirmar
>
> [saida colada, resumida: 13 linhas `debug: sync decisao=apagar motivo=espelho-apaga-orfao item=PREFEITURAS/2020/ACRELÂNDIA/2ANA_03042024/ARQ_ENG/ARQ_MORTO/COMPLEMENTARES/...` (arquivos `.json`, `.docx`, `.gif` e um item sem extensao `.../Relatórios/Hidráulico/N0-TERREO`), seguidas de `debug: http POST api.dropboxapi.com/2/files/creat`]
>
> ajuste o processo para só apagar os orfãos quando o processo concluir

**Sanitizacao:** a saida colada foi resumida (nomes de pasta de cliente mantidos so no primeiro nivel ja citado); nenhum segredo.

**Intencao:** (1) no `sync` em ciclos com `--espelhar`, adiar toda exclusao de orfao (arquivo e pasta) para depois do ultimo ciclo; (2) a saida e a evidencia da ressalva aberta da demanda `sync-ciclos-exclusao-indevida`.

**Leitura do Tech Lead:** todos os itens marcados tem caractere fora do ASCII no caminho (`Â`, `á`, `ó`, `ç`). Hipotese principal: divergencia de chave entre o nome local e o remoto (forma Unicode NFC/NFD ou caixa fora do ASCII), que faz `_dbx_cmd_sync_ramos_destino_remotos` (RF-190(b)) tratar a pasta remota como ramo so do destino e o plano marcar o conteudo como orfao. Nao confirmada: a origem nao esta nesta maquina; diagnostico pedido ao solicitante.

**Decisoes do solicitante (AskUserQuestion, 2026-11-11):**
- Regra: "Sim, assim (Recomendado)" — orfaos (arquivos e pastas) so sao apagados depois de todos os ciclos concluidos sem falha; antes de apagar, cada candidato e reconferido contra o conjunto completo da origem; execucao interrompida ou com ciclo falho nao apaga nada.
- Release: "Segurar e incluir (Recomendado)" — a 2.4.1 so sai com esta correcao nas duas linhas; suites da release interrompidas.

## Prompt 2 — 2026-11-11 (diagnostico pedido pelo Tech Lead)

> [saida colada, resumida: `ls /mnt/e/arquivos1/PREFEITURAS/2020 | grep -ai acrel | od -c` -> `A C R E L Â N D I A` (NFC, 2 bytes); `dbx list /Amac/arquivos1/PREFEITURAS/2020 | grep -ai acrel | od -c` -> `name=ACRELÂNDIA` (mesmos bytes), `path_display=/amac/arquivos1/PREFEITURAS/2020/A...`]

**Leitura do Tech Lead:** nome identico em bytes nos dois lados; a hipotese NFC/NFD caiu no primeiro nivel. O `path_display` traz a raiz em caixa diferente (`/amac` x `/Amac`). Causa provavel medida: as chaves de diretorio do sync (`chaves_dirs`, `pais`, `visitados`, `dbx_sync_relativo`) dobram a caixa com `${x,,}` na localidade do processo, e o plano dobra com `dbx_filtro_chave` (C.UTF-8 fixo). Sob `LC_ALL=C`, `Á` nao dobra: uma pasta com caixa diferente so num caractere acentuado vira "ramo so do destino" (RF-190(b)) e o conteudo, cujo par local esta noutro ciclo, sai como orfao. Correcao da dobra incluida no escopo da demanda; confirmacao pedida ao solicitante (localidade e nomes do nivel mais fundo).

## Prompt 3 — 2026-11-11 (diagnostico)

> [saida colada, resumida: `locale` -> `LANG=C.UTF-8`, `LC_CTYPE="C.UTF-8"`; `ls ".../COMPLEMENTARES/PROJ_COMP_REF_ESC_RITA_BOCA"` na origem local -> `No such file or directory`; `dbx list` da mesma pasta no destino -> `Arquivos de impressão`, `Arquivos diversos`, `Arquivos exportados`, `Hidráulico`, `Revisões`, `_DADOS_`, `logo.gif`, `Lista de Materiais.docx`]

**Leitura do Tech Lead:** localidade UTF-8: a dobra por localidade nao explica o relato (fica como robustez na demanda). A pasta `PROJ_COMP_REF_ESC_RITA_BOCA` existe no destino e NAO existe na origem local: os itens marcados podem ser orfaos reais (conteudo so do destino), e nao arquivos de ciclo anterior. Pedido ao solicitante o nivel mais fundo que existe na origem.

## Prompt 4 — 2026-11-11 (diagnostico)

> [saida colada, resumida: nivel mais fundo existente na origem local: `/mnt/e/arquivos1/PREFEITURAS/2020/ACRELÂNDIA` com `DIVERSOS`, `DOC_INSTITUCIONAL`, `FNDE`, `FUNASA`, `MAPA`, `MDR`, `M_CIDADANIA`, `M_DEFESA`, `M_TURISMO`, `OFÍCIOS`, `SUDAM`, `TRANF_ESPEC` (sem `2ANA_03042024`); no destino, `.../ARQ_MORTO/COMPLEMENTARES` tem `REV00`, `ESTRUTURAL`, `PROJ_COMP_REF_ESC_RITA_BOCA`, `PROJ_COMP_REF_ESC_RITA_BOCA_S_AR`, `HIDRAULICO`, `SANITARIO` e arquivos `.dwg`/`.bak`]

**Leitura do Tech Lead:** a pasta `ACRELÂNDIA/2ANA_03042024` nao existe na origem local; existe so no destino. Os itens do relato sao orfaos reais pela regra do `--espelhar`, e nao arquivos de ciclo anterior marcados por engano. A ressalva da demanda `sync-ciclos-exclusao-indevida` fica explicada por este diagnostico. A regra pedida (exclusao so no fim, com reconferencia contra a origem completa) segue como decidida.

## Prompt 5 — 2026-11-11 (diagnostico)

> [saida colada: `find /mnt/e/arquivos1 -type d -name '2ANA_03042024'` -> `/mnt/e/arquivos1/PREFEITURAS/2020/ACRELÂNDIA/FNDE/REFOR_ESC_RITA_BOCALOM/2ANA_03042024`]

**Leitura do Tech Lead:** a pasta foi movida na origem de `ACRELÂNDIA/2ANA_03042024` para `ACRELÂNDIA/FNDE/REFOR_ESC_RITA_BOCALOM/2ANA_03042024`. Com a exclusao por ciclo, a copia antiga sai num ciclo anterior (`2ANA...` vem antes de `FNDE` na ordem) e a nova so chega num ciclo posterior: entre os dois, o conteudo nao existe no destino, e uma interrupcao nesse intervalo o deixa ausente. E o cenario que a regra pedida (exclusao so no fim) resolve. Mover no servidor em vez de apagar e reenviar fica fora do escopo (candidata a funcionalidade).

**Aceite dos testes do QA (AskUserQuestion, 2026-11-11):** "Aceito a suite" — `tests/integracao/qa_sync_orfaos_no_fim_test.sh`, sha256 `d4a02858cc1663350b976b187ed35c01bac098cf5a1d2d70c6ad2f843c1c61eb`; entrada `2026-11-11-2210-aceite-testes-qa-sync-orfaos-no-fim`.
