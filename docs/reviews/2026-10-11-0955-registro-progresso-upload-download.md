# Registro de Entrega — Feedback Visual Durante Upload e Download de Arquivos

> Registro de entrega formal da demanda (Porte P) conforme regras 40 e 41 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Feedback visual durante upload e download de arquivos (`@tech-lead exiba um feed back visual duranteo upload e durante o download dos arquivos`) |
| Data / Hora | 2026-10-11 09:55 |
| Domínio | CLI / Feedback Visual / Upload / Download / UX |
| Porte | **P (pontual)** — refinamento de canal de feedback visual (`--progresso` / `-p`) sem alteração da saída estruturada (stdout), persistência nem contratos públicos |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/progresso-upload-download` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-11_0955_progresso-upload-download.md](../prompts/2026-10-11_0955_progresso-upload-download.md) |

---

## Contexto e Objetivo

Durante as operações de upload (`dbx upload`) e download (`dbx download`), quando executadas com sinalizador de progresso ativo (`--progresso`, `-p` ou modo padrão automático interativo em TTY), a CLI emitia apenas mensagens estáticas no início e no fim da operação (ex.: `[upload] enviando arquivo via requisicao unica...`, `[download] iniciando recebimento: ...`).

Durante a transmissão real dos dados pela rede, o utilitário `cURL` mantinha-se com a diretiva `silent` forçada em `lib/http.sh`, e seu descritor de erro (`stderr`) era capturado em arquivo temporário interno (`erro_cliente`). Com isso, durante transferências de arquivos médios e grandes, o operador permanecia sem feedback visual contínuo do progresso, gerando sensação de lentidão ou congelamento do processo.

Com este incremento:
1. **Medidor Visual de Transferência em Tempo Real:**
   - Em `lib/http.sh`, quando em modo de conteúdo (`_DBX_HTTP_MODO == 'conteudo'`) e com progresso ativo (`dbx_progress_ativo`), a diretiva `progress-bar` é emitida para o `cURL` (em vez de `silent`), e seu descritor de saída de erro é emitido diretamente para o descritor `stderr` (`2>&2`).
   - O operador passa a acompanhar em tempo real a evolução percentual e barra de blocos do cURL em seu terminal durante a transmissão dos dados.
2. **Silenciamento Rigoroso em Modos Não Interativos:**
   - Quando `--sem-progresso` (`--no-progress`) for informado ou sob redirecionamentos não interativos de stderr sem flag explícita, o cURL permanece estritamente `silent`, evitando poluição de scripts automatizados.
   - Chamadas RPC (`bearer`) e formulários de autenticação permanecem silenciosos e isolados com captura em `erro_cliente`.
3. **Detalhamento de Upload por Requisição Única:**
   - Em `commands/upload.sh`, a mensagem de envio por requisição única passa a informar o tamanho formatado do arquivo local: `[upload] enviando arquivo (<tamanho>) via requisicao unica...`.
4. **Cálculo de Percentual em Sessões em Partes:**
   - Em `lib/transfer.sh`, o tamanho total do arquivo local (`DBX_TRANSFER_TAMANHO`) é fornecido a `dbx_progress_transferencia`, exibindo o acumulado, total e percentual concluído a cada bloco (`[upload] parte X enviada: N MiB / T MiB (P%)`), além de formatação humanizada na mensagem de conclusão de sessão.
5. **Isolamento Absoluto de Descritores (RF-28 e RF-32):**
   - O descritor `stdout` (1) permanece 100% livre de qualquer informação de progresso, garantindo pureza integral de saídas estruturadas (JSON / chave-valor) e de streaming binário via pipe (`dbx download ... - | tar xzf -`).

---

## Escopo Técnico e Arquivos Modificados

| Arquivo | Natureza | Descrição |
|---|---|---|
| `lib/http.sh` | Modificado | Sourcing de `lib/progress.sh`, configuração de `progress-bar` em modo conteúdo ativo e direcionamento da saída visual para `stderr` |
| `lib/transfer.sh` | Modificado | Repasse do tamanho total para `dbx_progress_transferencia` e formatação amigável de bytes no encerramento da sessão em partes |
| `commands/upload.sh` | Modificado | Inclusão de tamanho formatado do arquivo no feedback visual de requisição única |
| `tests/integracao/comandos_test.sh` | Modificado | 4 novos testes unitários e de integração validando ativação de `progress-bar` e silenciamento de `silent` sob controle de flags |
| `docs/prompts/2026-10-11_0955_progresso-upload-download.md` | Novo | Registro cronológico integral do prompt |
| `docs/reviews/2026-10-11-0955-registro-progresso-upload-download.md` | Novo | Registro formal de entrega com pareceres embutidos |

---

## Parecer de Evidências de Testes (Protocolo TDD — Modo Compacto)

- **Identificação:** Demanda `progresso-upload-download` (Porte P).
- **Escopo testado:** `tests/integracao/comandos_test.sh`, `tests/unit/transfer_test.sh`, `tests/unit/http_test.sh`, `tests/unit/progress_test.sh`.
- **Fase RED comprovada:**
  - `download_com_progresso_configura_progress_bar_no_cliente`: reprovado com falha (`trecho ausente: [progress-bar]`).
  - `upload_com_progresso_configura_progress_bar_no_cliente`: reprovado com falha (`trecho ausente: [progress-bar]`).
- **Fase GREEN comprovada:**
  - `teste_upload_com_progresso_configura_progress_bar_no_cliente`: aprovado.
  - `teste_upload_sem_progresso_mantem_cliente_silencioso`: aprovado.
  - `teste_download_com_progresso_configura_progress_bar_no_cliente`: aprovado.
  - `teste_download_sem_progresso_mantem_cliente_silencioso`: aprovado.
  - Regressão completa: 597 casos executados, 597 aprovados, 0 reprovados.
  - Guarda de remoção de testes (`bash scripts/verificar-remocao-de-casos.sh`): aprovada (595 -> 599 casos, nenhuma redução não declarada).
- **Veredito:** **Aprovado**.

---

## Parecer de Conformidade (Protocolo Conformidade — Modo Compacto)

- **Identificação:** Demanda `progresso-upload-download` (Porte P).
- **Diff avaliado:** `git diff lib/http.sh lib/transfer.sh commands/upload.sh tests/integracao/comandos_test.sh`.
- **Checklist:**
  - Carregamento idempotente respeitado via `_dbx_http_diretorio` e `lib/progress.sh`.
  - Nenhuma variável global poluída; variáveis de controle de formatação locais (`str_tam`, `str_total_sessao`).
  - Sem uso de subshells desnecessários nos laços críticos.
  - Ausência de segredos ou credenciais em mensagens de diagnóstico.
  - Conformidade estrita com RF-28 e RF-32: toda saída de progresso direcionada ao descritor 2 (`stderr`).
  - `shellcheck` (0.10.0+): validado sem avisos ou erros em todos os arquivos modificados.
- **Veredito:** **Aprovado**.

---

## Aprovação do Tech Lead

- **Status:** **Aprovado para entrega**.
- **Observações:** Refinamento pontual de UX na CLI cumprindo integralmente a solicitação do operador sem impacto colateral na automação ou em pipelines que consom a saída estruturada.
