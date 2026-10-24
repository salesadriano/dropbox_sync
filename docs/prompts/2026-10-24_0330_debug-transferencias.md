---
date: 2026-10-24
hora: "0330"
domain: modo --debug nos comandos de transferencia (download, upload, sync)
porte: M
status: aberto
instancia: myPCWin/Desenvolvedor Hydros
registro_de_entrega: "docs/reviews/2026-10-24-0330-registro-debug-transferencias.md"
---

# debug-transferencias

## Prompt 1 — 2026-10-24

> implemente o debug para download, upload e sync

**Intencao:** `--debug` (ou `DBX_DEBUG=1`) passa a produzir, em `download`, `upload` e `sync`, uma trilha util para diagnosticar a execucao, sem expor segredo.

**Estado atual levantado pelo Tech Lead (develop @ `877b708`):**
- `--debug` e opcao global (`lib/cli.sh`, `DBX_CLI_DEBUG`), mas so o `config` emite relatorio proprio (diagnostico do ambiente). O `sync` com `N>1` acrescenta ao resumo a contagem de `429` (`RF-135(d)`, `DIV-258`); `download` e `upload` nao emitem nada proprio.
- Com `--debug` o progresso deixa de usar retorno de carro (`lib/progress.sh:230`, `DIV-287`).
- Restricoes ja vigentes: nenhum segredo em `--debug` (`RF-131`, `RF-86`); identificador de sessao de envio e cursor nunca aparecem em `--debug` (README, `RF-101`, `RF-111`); stdout byte a byte igual com e sem progresso (`RF-145(a)`).
- Na branch ainda nao integrada `feature/teste-de-disponibilidade`, `lib/http.sh` ganhou o `--debug` mascarado da sonda (userinfo, caminho e query cortados; `dbx_errors_redigir`).

**Decisoes do solicitante (AskUserQuestion, 2026-10-24):**
- **Conteudo:** "Chamadas HTTP", "Etapas da transferencia", "Decisoes do sync" e "Resumo no fim" (as quatro): uma linha por chamada (metodo, endpoint sem token nem query, status, duracao, tentativa/retentativa e `Retry-After`, bytes); upload simples ou em sessao, tamanho e offset de cada bloco, retomada encontrada/descartada e por que (nunca o id da sessao); download com faixa/retomada do `.part` e hash conferido; por arquivo do sync, enviar/receber/pular/apagar com o motivo, cursor usado ou reconstruido (nunca o cursor); linha final com totais (chamadas, retentativas, `429`, bytes, tempo).
- **Base da branch:** "Depois da PR de disponibilidade (Recomendado)": a implementacao so comeca depois do merge da PR de `feature/teste-de-disponibilidade` em `develop`; ate la, so a especificacao (BA). Esta branch nasce de `develop` @ `877b708` para o log e a especificacao, e recebe a `develop` atualizada por merge antes do primeiro codigo.
- **Destino:** "So stderr (Recomendado)": nenhum arquivo de log; stdout identico com e sem `--debug`.

**Porte:** M. `scripts/porte.sh` nao existe no projeto. Toca contrato de saida da CLI (stderr de tres comandos), `lib/http` (todas as chamadas) e o risco de segredo em log (gatilhos de M); nao altera arquitetura nem a integracao externa (os mesmos endpoints, nenhuma chamada nova).

**Entrada:** branch principal `develop` @ `877b708`; PRs abertas: #57 (`develop` -> `master`, promocao, sem impacto no escopo); branch nao integrada `feature/teste-de-disponibilidade` (sobreposicao em `lib/http.sh` e `commands/sync.sh`, tratada pela decisao de base acima); worktree `feature/debug-transferencias` em `/home/sales/dropbox_api.worktrees/feature-debug-transferencias`; `alteracoes-externas.sh --inicial` exit 0; `ensure-docs.sh` exit 0.

**Especificacao (Business Analyst, 2026-10-24):** secao 5.21 do escopo (v1.29), `RF-156` a `RF-165`, `TC-DBG-01` a `TC-DBG-35`, `F-51`; `DIV-332` a `DIV-341`.

**Decisoes do solicitante sobre as divergencias (AskUserQuestion, 2026-10-24):**
- **DIV-332:** "Caminho completo (Recomendado)" — caminhos do operador aparecem (relativo a raiz no `sync`, como digitado em `upload`/`download`), saneados e redigidos; README avisa sobre colar o log em chamado publico.
- **DIV-338:** "Resumo unico (Recomendado)" — `debug: resumo` substitui a linha `paralelo` de `RF-135(d)`/`DIV-258` e leva `paralelo=N` e os `429`; `tests/integracao/paralelo_test.sh` acompanha.
- **DIV-339:** "Sem limite (Recomendado)" — um nivel unico, uma linha por decisao, inclusive `pular`.

**Decididas pelo Tech Lead na recomendacao do BA (tecnicas, sem efeito de contrato alem do ja decidido):** `DIV-333` (linhas dos auxiliares em arquivo por item no canal efemero `0700` de `DIV-290`, descarregadas pelo principal na ordem do plano), `DIV-334` (duracao e bytes pelo `-w` do cURL ampliado so com `--debug`), `DIV-335` (host mais o caminho fixo do endpoint da API), `DIV-336` (formato `chave=valor`), `DIV-337` (sonda como categoria `sonda` do mesmo prefixo, sem reescrever seu formato), `DIV-340` (vocabulario fechado de motivos, a conferir contra o codigo pelo Senior Developer), `DIV-341` (resumo tambem em falha e, em melhor esforco, em sinal).
