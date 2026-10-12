# Registro de Entrega — Feedback Visual e Gráfico Durante Upload e Download de Arquivos

> Registro de entrega formal da demanda (Porte P) conforme regras 40 e 41 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Feedback visual e gráfico durante upload e download de arquivos (`@tech-lead durante o processo de upload ou download dos arquivos deve ser exibido feed back gráfico demonstrando progressão do processo`) |
| Data / Hora de início | 2026-10-11 09:55 |
| Data / Hora de refinamento | 2026-10-12 10:45 |
| Domínio | CLI / Feedback Visual / Feedback Gráfico / Upload / Download / UX |
| Porte | **P (pontual)** — refinamento de canal de feedback visual e gráfico (`--progresso` / `-p`) sem alteração da saída estruturada (stdout), persistência nem contratos públicos |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/progresso-upload-download` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-11_0955_progresso-upload-download.md](../prompts/2026-10-11_0955_progresso-upload-download.md) |

---

## Contexto e Objetivo

Durante as operações de upload (`dbx upload`) e download (`dbx download`), quando executadas com sinalizador de progresso ativo (`--progresso`, `-p` ou modo padrão automático interativo em TTY), o operador necessita de acompanhamento visual e gráfico claro e contínuo da progressão do processo.

Na entrega inicial do Prompt 1, a diretiva `progress-bar` foi habilitada no `cURL` para o modo de conteúdo e o repasse de tamanho total foi adicionado em `lib/transfer.sh`. No Prompt 2, o operador refinou explicitamente o requisito:
> `@tech-lead durante o processo de upload ou download dos arquivos deve ser exibido feed back gráfico demonstrando progressão do processo`

E no Prompt 3, o operador reportou a anomalia visual com captura de tela:
> `inicio do processo retorna erro, verifique`
> *(`[download] iniciando recebimento: /ASJ/ASJASS -> ... (0%)` seguido por `#=#=-#  #  curl: (22) The requested URL returned error: 409`)*

Com este ciclo de refinamentos e correções:
1. **Gerador de Barra Gráfica de Progresso (`dbx_progress_barra_gerar`):**
   - Em `lib/progress.sh`, introduzida a função `dbx_progress_barra_gerar <percentual> [largura] [var_destino]`, que desenha uma barra gráfica proporcional delimitada por colchetes (ex.: `[██████████░░░░░░░░░░]`).
   - Suporte inteligente à codificação do terminal: utiliza blocos cheios (`█`) e sombreados (`░`) quando em ambiente UTF-8, com fallback seguro para caracteres ASCII (`#` e `-`) sob locales restritos (RNF-19).
2. **Função de Barra Gráfica Formatada (`dbx_progress_barra`):**
   - Em `lib/progress.sh`, `dbx_progress_barra <rotulo> <atuais> <totais> [detalhe]` emite barra gráfica acompanhada do percentual numérico e dos tamanhos formatados (`[upload] [██████████░░░░░░░░░░]  50%  5 MiB / 10 MiB (detalhe)`) exclusivamente em `stderr`.
3. **Barra Gráfica em Transferências e Etapas:**
   - Em `lib/progress.sh`:
     - `dbx_progress_transferencia` passa a incorporar a barra gráfica proporcional junto aos bytes e percentual (`[upload] parte 1 enviada: 4 MiB / 12 MiB (33%) [██████░░░░░░░░░░░░]`), garantindo compatibilidade estrita com asserções existentes e acrescentando representação visual.
     - `dbx_progress_etapa` passa a calcular percentual e emitir a barra gráfica para lotes e etapas com total conhecido (`[4/10] recebendo: arquivo.zip [██████░░░░░░░░░] (40%)`).
4. **Feedback Gráfico nos Comandos `upload` e `download`:**
   - Em `commands/upload.sh`, os marcos de início (0%) e conclusão (100%) em requisições únicas e na conclusão geral de envio passam a exibir a barra gráfica correspondente.
   - Em `commands/download.sh`, os marcos de início (0%) e conclusão de recebimento (100%), acompanhados do tamanho baixado, passam a exibir a barra gráfica correspondente.
   - Em `lib/transfer.sh`, a conclusão de sessão em partes passa a exibir barra gráfica concluída (100%).
5. **Encapsulamento Estrito do Transporte e Eliminação de Vazamento de Erros cURL (Prompt 3):**
   - Em `lib/http.sh`, unificada a execução do `cURL` para direcionar a saída de erro SEMPRE para `"$area/erro_cliente"`, eliminando o redirecionamento `2>&2` desprotegido.
   - Impede que erros internos de transporte (`curl: (22) The requested URL returned error: 409`) ou caracteres de inicialização de barra do cliente (`#=#=-#  #`) vazem para a tela do operador durante chamadas especulativas (como o download de pasta em `commands/download.sh`).
   - Garante a alimentação correta e sanitizada de `DBX_HTTP_DIAGNOSTICO` por `dbx_errors_redigir`.
   - Em `commands/download.sh`, o fallback para download recursivo de pastas repassa explicitamente os sinalizadores de progresso (`--progresso` / `--sem-progresso`) ao motor `sync.sh`.
6. **Silenciamento Rigoroso em Modos Não Interativos (RNF-19):**
   - Quando `--sem-progresso` (`--no-progress`) for informado ou sob redirecionamentos não interativos de stderr sem flag explícita, a aplicação permanece estritamente silenciosa.
7. **Isolamento Absoluto de Descritores (RF-28 e RF-32):**
   - O descritor `stdout` (1) permanece 100% livre de qualquer informação de progresso, garantindo pureza integral de saídas estruturadas (JSON / chave-valor) e de streaming binário via pipe (`dbx download ... - | tar xzf -`). Todo feedback gráfico e textual trafega exclusivamente pelo descritor `stderr` (2).

---

## Escopo Técnico e Arquivos Modificados

| Arquivo | Natureza | Descrição |
|---|---|---|
| `lib/progress.sh` | Modificado | Implementação de `dbx_progress_barra_gerar`, `dbx_progress_barra` e incorporação de barra gráfica em `dbx_progress_transferencia` e `dbx_progress_etapa` |
| `commands/upload.sh` | Modificado | Exibição de barra gráfica inicial (0%) e conclusão (100%) no envio por requisição única e finalização |
| `commands/download.sh` | Modificado | Exibição de barra gráfica inicial (0%) e conclusão (100%) com tamanho formatado; repasse de sinalizador de progresso no fallback para sync |
| `lib/transfer.sh` | Modificado | Exibição de barra gráfica na conclusão da sessão em partes |
| `lib/http.sh` | Modificado | Encapsulamento estrito do stderr do cURL em `erro_cliente`, eliminando vazamento de erro 409 e caracteres de barra no terminal |
| `tests/unit/progress_test.sh` | Modificado | Novos testes cobrindo geração de barra em 0%, 100%, intermediários, limites, emissão em `stderr` e presença gráfica |
| `tests/integracao/comandos_test.sh` | Modificado | Novos testes validando barra gráfica em upload/download e teste comprovando ausência de vazamento de erro cURL no download de pasta |
| `docs/prompts/2026-10-11_0955_progresso-upload-download.md` | Modificado | Registro cronológico integral dos Prompts 1, 2 e 3 |
| `docs/reviews/2026-10-11-0955-registro-progresso-upload-download.md` | Modificado | Registro formal de entrega atualizado com pareceres embutidos |

---

## Parecer de Evidências de Testes (Protocolo TDD — Modo Compacto)

- **Identificação:** Demanda `progresso-upload-download` (Porte P — Prompts 2 e 3).
- **Escopo testado:** `tests/unit/progress_test.sh`, `tests/integracao/comandos_test.sh`, `tests/unit/transfer_test.sh`, `tests/unit/http_test.sh`, `tests/unit/hash_test.sh`.
- **Fase RED comprovada:**
  - `tests/unit/progress_test.sh`:
    - `teste_barra_gerar_percentual_zero_e_cem`: reprovado (`dbx_progress_barra_gerar: command not found`).
    - `teste_barra_grafica_emite_em_stderr_e_preserva_stdout`: reprovado (`dbx_progress_barra: command not found`).
    - `teste_etapa_inclui_barra_grafica_em_stderr`: reprovado (`trecho ausente: [(40%)]`).
  - `tests/integracao/comandos_test.sh`:
    - `teste_download_com_progresso_exibe_barra_grafica_em_stderr`: reprovado (`trecho ausente: [100%]`).
    - `teste_upload_com_progresso_exibe_barra_grafica_em_stderr`: reprovado (`trecho ausente: [100%]`).
    - `teste_download_de_pasta_com_progresso_nao_vaza_erro_bruto_do_cliente_em_stderr`: reprovado (`trecho proibido presente: [The requested URL returned error]`, evidenciando o vazamento `curl: (22) The requested URL returned error: 409`).
- **Fase GREEN comprovada:**
  - `teste_barra_gerar_percentual_zero_e_cem`: aprovado.
  - `teste_barra_gerar_valores_intermediarios_e_limites`: aprovado.
  - `teste_barra_grafica_emite_em_stderr_e_preserva_stdout`: aprovado.
  - `teste_transferencia_inclui_barra_grafica_em_stderr`: aprovado.
  - `teste_etapa_inclui_barra_grafica_em_stderr`: aprovado.
  - `teste_upload_com_progresso_exibe_barra_grafica_em_stderr`: aprovado.
  - `teste_download_com_progresso_exibe_barra_grafica_em_stderr`: aprovado.
  - `teste_download_de_pasta_com_progresso_nao_vaza_erro_bruto_do_cliente_em_stderr`: aprovado.
  - Regressão completa: 605 casos executados, 605 aprovados, 0 reprovados, 2 pulados.
  - Guarda de remoção de testes (`bash scripts/verificar-remocao-de-casos.sh`): aprovada (606 -> 607 casos, nenhuma redução não declarada).
- **Veredito:** **Aprovado**.

---

## Parecer de Conformidade (Protocolo Conformidade — Modo Compacto)

- **Identificação:** Demanda `progresso-upload-download` (Porte P — Prompts 2 e 3).
- **Diff avaliado:** `git diff lib/progress.sh commands/upload.sh commands/download.sh lib/transfer.sh lib/http.sh tests/unit/progress_test.sh tests/integracao/comandos_test.sh`.
- **Checklist:**
  - Prefixo de funções públicas (`dbx_progress_`) e variáveis globais (`DBX_PROGRESS_`) estritamente respeitado.
  - Todas as variáveis locais protegidas com `local` para evitar vazamento de escopo.
  - Ausência de comandos externos no cálculo de barras (`bash` arithmetics puros).
  - Sem uso de subshells desnecessários nos laços críticos.
  - Ausência de segredos ou credenciais em mensagens de diagnóstico ou progresso.
  - Conformidade estrita com RF-28 e RF-32: toda saída de progresso direcionada ao descritor 2 (`stderr`).
  - Encapsulamento estrito do cURL: saída de erro tratada via buffer interno (`erro_cliente`), sem poluição do terminal do usuário com erros brutos do cliente.
  - `shellcheck` (0.10.0+): validado sem avisos ou erros em todos os arquivos modificados e no projeto completo (`shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh`).
- **Veredito:** **Aprovado**.

---

## Aprovação do Tech Lead

- **Status:** **Aprovado para entrega**.
- **Observações:** A demanda do operador foi integralmente atendida com a introdução do feedback gráfico (barra de progresso proporcional e percentual em colchetes) para todas as modalidades de upload e download, eliminação completa do vazamento de erro do cURL sob fallback de download de pasta, isolamento estrito de canais de saída e estabilidade total da suíte.
