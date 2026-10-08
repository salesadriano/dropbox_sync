# Registro de Entrega — Ajuda Contextual de Comandos e Recomendacao Operacional de Pipefail

> Registro de entrega da demanda pontual (Porte P) conforme regra 41 do protocolo comum e a skill `review-documentation`.

## Identificacao da demanda

| Campo | Valor |
|---|---|
| Demanda | Ajuda contextual por comando em `bin/dbx` e documentacao de `pipefail` para upload via fluxo (`stdin`) |
| Data / Hora | 2026-10-08 07:35 |
| Dominio | CLI / Documentacao Operacional / Requisitos |
| Porte | **P (pontual)** — alteracao localizada em `bin/dbx`, `commands/upload.sh`, testes e docs |
| Instancia | `myNote/Adriano Sales Santos` |
| Branch de trabalho | `fix/ajuda-upload-pipefail` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-08_0735_ajuda-upload-pipefail.md](../prompts/2026-10-08_0735_ajuda-upload-pipefail.md) |
| Pendencias tratadas | `DIV-18`, `RSK-36`, `DP-29` |

---

## Contexto e Motivacao

Na implementacao do upload em partes e entrada padrao (PR #14), foi constatado que, ao consumir fluxo a partir de canos anonimos (`tar czf - /dados | dbx upload - /destino.tgz`), a morte prematura do processo produtor e indistinguivel de EOF dentro do processo leitor (`DIV-18`, `RSK-36`).
A contramedida documentada nos requisitos e riscos e o uso de `set -o pipefail` no shell do operador que encadeia a operacao.

Contudo, essa recomendacao existia apenas em comentarios internos de codigo (`lib/transfer.sh` e `commands/upload.sh`).
O lugar apropriado para instruir o operador e o texto de ajuda do comando (`bin/dbx`), que se encontrava sob revisao aberta durante o PR #13 e por isso nao pode ser alterado naquela rodada.
Com a integracao dos PRs #13, #14 e #15 em `develop`, `bin/dbx` ficou liberado para receber a ajuda contextual e resolver formalmente essa pendencia.

---

## Modificacoes Realizadas

1. **Ponto de entrada (`bin/dbx`):**
   - Suporte ao despacho de ajuda contextual para subcomandos: `dbx help <comando>` e `dbx <comando> --help` / `-h`.
   - Adicionada documentacao detalhada de uso, argumentos e opcoes para cada um dos 9 comandos do MVP (`config`, `unlink`, `sync`, `upload`, `download`, `list`, `delete`, `info`, `space`).
   - Inclusao formal da recomendacao operacional de `set -o pipefail` tanto na ajuda geral (`dbx help`) quanto na ajuda detalhada de `upload` (`dbx help upload` e `dbx upload --help`), atendendo a `RSK-36` / `DIV-18` / `DP-29`.
   - Despacho de ajuda ocorre antes do preflight de credenciais, permitindo consultar ajuda mesmo sem token de autenticacao configurado.

2. **Comando de upload (`commands/upload.sh`):**
   - Atualizado o comentario de cabecalho substituindo a marcacao de pendencia aberta pelo registro formal de pendencia atendida em `bin/dbx`.

3. **Suite de testes (`tests/integracao/comandos_test.sh`):**
   - Adicionado caso de teste integrado `teste_ajuda_geral_e_especifica_recomenda_pipefail_para_upload_por_fluxo`, cobrindo:
     * `dbx help` (ajuda geral sem credencial, com saida contendo `pipefail`);
     * `dbx help upload` (ajuda especifica sem credencial, com recomendacao formal de `set -o pipefail`);
     * `dbx upload --help` (invocacao com flag `--help`, sem credencial, contendo `set -o pipefail`).

4. **Documentacao de Requisitos e Riscos:**
   - `docs/requisitos/escopo-requisitos-e-criterios-de-aceite.md`: `DIV-18` e a linha correspondente na secao 10 (Dependencias de fechamento) marcadas como RESOLVIDAS.
   - `docs/requisitos/riscos-restricoes-e-licenciamento.md`: `RSK-36` atualizado com o registro da mitigacao operacional implementada na ajuda de `bin/dbx`.
   - `docs/requisitos/decisoes-pendentes.md`: `DP-29` atualizado tanto na tabela de verificacao por evidencia observavel quanto no painel de decisoes estruturantes (P1).

---

## Evidencias de Validacao

- **TDD (Fase Vermelha / Verde):**
  - Caso `ajuda_geral_e_especifica_recomenda_pipefail_para_upload_por_fluxo` falhou inicialmente com trecho ausente `[pipefail]`.
  - Apos atualizacao de `bin/dbx`, passou com sucesso (50/50 casos aprovados em `comandos_test.sh`).
- **Analise estatica (`shellcheck`):**
  - Zero apontamentos em modo estrito nos scripts alterados.
- **Deteccao de alteracoes externas (`scripts/alteracoes-externas.sh`):**
  - Zero divergencias.

---

## Parecer do Tech Lead

- **Status:** Aprovado para integracao.
- **Rastreabilidade:** `DIV-18`, `RSK-36`, `DP-29`.
- **Impacto em compatibilidade:** Nenhum; retrocompativel com toda a sintaxe de linha de comando existente.
