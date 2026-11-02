# System Design - Linha legada para bash 4.2 e instalador que escolhe a linha (F-102)

## Identificacao

- Projeto: dbx (cliente de linha de comando Dropbox em shell)
- Demanda: `suporte-bash-42` (porte G), log `docs/prompts/2026-11-01_1200_suporte-bash-42.md`
- Requisitos: secao 5.25 de `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md` (F-102, RF-198 em diante, RNF-40) e DP-07 reaberta e resolvida em 2026-11-01
- Decisoes do solicitante (2026-11-01): linha legada separada; versao 2.3.0; validacao do 4.2 pela suite completa em imagem CentOS 7
- Data: 2026-11-01 | Status: Em validacao

## Objetivo do documento

- Problema: o `dbx` exige bash 4.4 (`lib/preflight.sh`, DP-07). RHEL/CentOS 7 e Amazon Linux 2 trazem 4.2.46 e ficam fora. O `install.sh` recusa e nao oferece alternativa.
- Escopo: (A) na linha principal, o instalador escolhe a linha pelo bash do host e o `dbx` orienta a reinstalacao; (B) a linha legada `support/bash-4.2`, com o codigo adaptado ao 4.2.
- Fora: bash abaixo de 4.2 (RHEL 6); sincronizacao automatica entre as linhas (backport e demanda propria).

## Fatos medidos (2026-11-01)

| Fato | Medida |
|---|---|
| Sintaxe no 4.2.53 (`bash -n` em todo `bin/`, `lib/`, `commands/`, `completions/`, instaladores) | limpa: as falhas sao todas em execucao |
| `bin/dbx diagnostico` no CentOS 7 (4.2.46) | morre em `lib/output.sh:207` (`local: -n: invalid option`) |
| `install.sh --version` no CentOS 7 | roda; recusa em `verificar_prerequisitos` (piso 4.4 fixo no instalador) |
| Expansoes `"${x[@]}"` no produto (`set -u` em `bin/dbx`) | 157 |
| Namerefs (`local -n` / `declare -n`, 4.3) | 28 (13 em `lib/sync.sh`) |
| `wait -n` (4.3) | 4: `commands/sync.sh` (2, fallback `\|\| :` vira laco ocupado no 4.2), `lib/transfer_paralelo.sh`, `lib/download_paralelo.sh` |
| `${x@a}` (4.4) | 2, `lib/retencao.sh` |
| curl do CentOS 7 | 7.29.0: aceita todas as opcoes de `lib/http.sh` (`-K -`, `connect-timeout`, `speed-*`, `limit-rate`, `range`, `continue-at`, `max-filesize`, `max-time`, `-w %{...}`, `--stderr`) |
| Imagem `centos:7` | bash 4.2.46, curl 7.29.0, python 2.7, coreutils GNU, `timeout`, `setsid`, `sha256sum` |

## Analise comparativa de abordagens

Eixo 1: onde vive o codigo do 4.2 (decidido pelo solicitante).

| Abordagem | Vantagens | Desvantagens | Veredito |
|---|---|---|---|
| Base unica com piso 4.2 | Um codigo; todo recurso chega ao 4.2 | Restricao permanente sobre a principal; toda PR paga a suite no 4.2 | Recomendada pelo TL, nao escolhida |
| **Linha legada `support/bash-4.2`** (branch de suporte do gitflow, cortada da `develop` depois da parte A) | Principal intocada; risco do porte isolado | Linhas divergem; recurso novo exige backport (RSK) | **Escolhida pelo solicitante** |

Eixo 2: como o instalador sabe qual linha uma fonte atende.

| Abordagem | Veredito |
|---|---|
| Tabela fixa no instalador (canal -> piso) | Descartada: duas verdades; diverge quando o piso mudar |
| **Ler `DBX_PREFLIGHT_BASH_MAIOR/MENOR` do `lib/preflight.sh` da propria fonte** | **Escolhida**: fonte unica, vale para checkout, pacote e clone remoto |
| Executar `bin/dbx --version` da fonte | Descartada: a principal morre no 4.2 antes de responder |

Eixo 3: execucao local com fonte incompativel.

| Abordagem | Veredito |
|---|---|
| Recusar e mostrar o comando | Descartada: o pedido e "realizar a instalacao da versao adequada" |
| **Informar e baixar a linha adequada do repositorio oficial**; sem rede, falhar com o comando manual | **Escolhida** (D3) |

Eixo 4: `wait -n` na legada.

| Abordagem | Veredito |
|---|---|
| `wait` de um PID fixo (o mais antigo) | Descartada: segura o laco pelo filho mais lento |
| **Sondagem dos PIDs com `kill -0` e pausa curta (`sleep 0.05`)**, colhendo com `wait "$pid"` o que terminou | **Escolhida**: preserva a ordem de descarga e o codigo de saida de cada filho; custo de CPU desprezivel |

Eixo 5: nameref na legada.

| Abordagem | Veredito |
|---|---|
| `eval` generico | Descartada: injecao pelo nome da variavel |
| **Nome validado (`^[a-zA-Z_][a-zA-Z0-9_]*$`) + `printf -v` para escalar, `${!ref}` para leitura e `eval` so com o nome validado para atribuicao de vetor** | **Escolhida**; um auxiliar unico em `lib/` para ler e gravar vetor por nome |

## Desenho

### A. Linha principal (`feature/suporte-bash-42` -> `develop`, versao 2.3.0)

1. `install.sh`
   - constantes `CANAL_PRINCIPAL=master`, `CANAL_LEGADO=support/bash-4.2`, piso absoluto 4.2;
   - `escolher_linha <maior> <menor>` -> `principal` (>= 4.4) | `legada` (4.2, 4.3) | `recusa` (< 4.2);
   - `piso_da_fonte <raiz>` -> `maior menor` lidos de `<raiz>/lib/preflight.sh`; ausente ou ilegivel = fonte invalida;
   - `verificar_prerequisitos` troca o piso 4.4 fixo por: recusa abaixo de 4.2, depois define a linha e, sem `--canal`, o canal dela;
   - `obter_raiz_origem`: fonte local cujo piso o bash do host nao atende -> `info` e cai no caminho remoto com o canal da linha; depois de obter qualquer fonte, confere o piso de novo e recusa nomeando o canal certo (cobre `--canal` explicito errado);
   - o arquivo continua rodando no 4.2 (ele e quem decide): sem nameref, `wait -n`, `${x@op}` nem vetor vazio desprotegido;
   - testavel: `DBX_INSTALL_SO_FUNCOES=1` faz o arquivo definir as funcoes e retornar antes de qualquer acao, para os testes unitarios carregarem por `.`.
2. `lib/preflight.sh` e `commands/diagnostico.sh`: piso segue 4.4; a mensagem e o remedio passam a indicar o `install.sh` (pipe do README), que instala a linha para bash 4.2/4.3.
3. `scripts/empacotar.sh --publicar`: `gh release create --target <sha de HEAD>` (hoje a tag nasce no ramo padrao, o que publicaria a legada com o codigo da `master`); versao com sufixo `-bash42` publica com `--latest=false`.
4. `scripts/suite-bash42.sh`: roda `bash tests/run.sh` (ou um filtro) dentro de `centos:7`, com o worktree montado; e o comando da suite completa oficial na legada.
5. README: secao de plataformas e instalacao (linhas, escolha automatica, como atualizar).

### B. Linha legada (`support/bash-4.2`, versao 2.3.0-bash42)

Cortada da `develop` depois do merge da parte A. Trabalho em `feature/porte-bash-42` -> PR para `support/bash-4.2`, nesta ordem (a suite para no primeiro erro, entao o harness vem antes):

1. `scripts/suite-completa.cmd` -> `sh scripts/suite-bash42.sh`; piso 4.2 em `lib/preflight.sh` e no teste; versao `2.3.0-bash42`; auditoria estatica nova (`tests/unit/bash42_auditoria_test.sh`): zero `local -n`/`declare -n`, `wait -n`, `${x@op}` em `bin/`, `lib/`, `commands/`, `completions/`, instaladores e `tests/support/`.
2. Harness e suporte de testes no 4.2.
3. Namerefs pelo auxiliar unico.
4. `wait -n` por sondagem; `${x@a}` por `declare -p`.
5. Vetores vazios: protecao `${x[@]+"${x[@]}"}` onde o vetor pode ser vazio, guiada pela suite no CentOS 7 e por revisao das 157 expansoes.

## Riscos e mitigacao

- Linhas divergem (backport esquecido): notas e README dizem que a legada recebe so backport em demanda; a 2.3.0-bash42 nasce com os mesmos recursos da 2.3.0.
- Vetor vazio desprotegido so falha em execucao: suite completa no CentOS 7 obrigatoria nas PRs da legada; revisao das 157 expansoes no parecer.
- Instalador troca de linha sem o usuario perceber: linha `info` explicita com a versao do bash e a linha escolhida.
- `centos:7` arquivada: imagem fixada por digest no script; ausente, o script falha dizendo como obter.

## Rollback

- Parte A: `git revert` do merge; o instalador volta a recusar abaixo de 4.4.
- Parte B: apagar a release `v2.3.0-bash42` (`gh release delete --cleanup-tag`); o branch de suporte fica sem efeito para quem ja usa 4.4.
