---
date: 2026-10-11
hora: "0955"
domain: cli / progresso / upload / download / ux
porte: P
status: concluido
instancia: myPCWin/Adriano Sales Santos
registro_de_entrega: "docs/reviews/2026-10-11-0955-registro-progresso-upload-download.md"
---

# Log de Prompt — Feedback Visual Durante Upload e Download de Arquivos

> Registro cronológico integral de prompts e decisões da demanda conforme regra 2 e regra 40 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Feedback visual durante o upload e download de arquivos (`@tech-lead exiba um feed back visual duranteo upload e durante o download dos arquivos`) |
| Data / Hora de início | 2026-10-11 09:55 |
| Porte | **P (pontual)** — refinamento de canal de feedback visual (`--progresso` / `-p`) sem alteração da saída estruturada (stdout), persistência nem contrato público |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/progresso-upload-download` |
| Branch principal | `develop` |

---

## Prompt 1 (Entrada do Operador)

```
@tech-lead exiba um feed back visual duranteo upload e durante o download dos arquivos
```

### Análise do Tech Lead

1. **Situação Atual:**
   - Durante comandos `upload` e `download`, as mensagens iniciais e finais são emitidas via `dbx_progress_mensagem` (ex.: `[upload] iniciando envio: ...`, `[upload] enviando arquivo via requisicao unica...`, `[download] iniciando recebimento: ...`), porém durante a transferência em si (chamadas a `dbx_auth_conteudo` e `dbx_auth_conteudo_receber`), o utilitário `cURL` opera com opção `silent` incondicionalmente forçada em `lib/http.sh` (`_dbx_http_opcoes`), e seu descritor de erro (`stderr`) é capturado em arquivo temporário interno (`erro_cliente`).
   - Consequentemente, para arquivos médios e grandes (tanto em requisição única quanto em partes ou download direto), o operador fica sem qualquer feedback visual dinâmico em tempo real enquanto os bytes trafegam pela rede, gerando percepção de bloqueio ou congelamento da ferramenta.
   - Em envios em partes (`lib/transfer.sh`), o tamanho total do arquivo não era repassado a `dbx_progress_transferencia` (passava `0`), omitindo o percentual e tamanho total do arquivo durante a progressão das partes.

2. **Solução Técnica Adotada:**
   - Em `lib/http.sh`:
     - Sourcing idempotente de `lib/progress.sh`.
     - Em `_dbx_http_opcoes`: quando o modo for `conteudo` (`_DBX_HTTP_MODO == 'conteudo'`, transferência de corpo de arquivos em upload/download) e `dbx_progress_ativo` retornar verdadeiro, emitir `progress-bar` para o cURL em vez de `silent`.
     - Em `_dbx_http_executar`: quando `_DBX_HTTP_MODO == 'conteudo'` e `dbx_progress_ativo`, direcionar o stderr do cURL (onde o medidor visual de transferência em tempo real é desenhado) diretamente para o descritor stderr (2) sem intermediários, permitindo que a barra de progresso visual (`progress-bar`) seja exibida dinamicamente no terminal do operador.
     - Quando `dbx_progress_ativo` estiver desativado (`--sem-progresso` ou execução não interativa sem terminal), manter o cURL estritamente `silent`.
     - Em todos os demais modos (`bearer` para RPCs, `formulario` para tokens), preservar rigorosamente o comportamento anterior com captura isolada em `erro_cliente`.
   - Em `lib/transfer.sh`:
     - Em `_dbx_transfer_conduzir`: repassar o tamanho total do arquivo (`DBX_TRANSFER_TAMANHO`) para `dbx_progress_transferencia`, exibindo bytes acumulados, total e percentual concluído a cada parte enviada, além de formatar amigavelmente a mensagem de conclusão de sessão.
   - Em `commands/upload.sh`:
     - Indicar o tamanho formatado do arquivo antes de iniciar o envio por requisição única.
   - **Isolamento Estrito de Canais (RF-28 e RF-32):**
     - O descritor `stdout` (1) permanece 100% puro e isolado para saídas estruturadas (JSON / chave-valor) e fluxos binários em pipes (`dbx download ... - | tar xzf -`). Todo feedback visual trafega exclusivamente pelo descritor `stderr` (2).
   - Testes automatizados cobrindo a configuração de `progress-bar` sob `--progresso` e `silent` sob `--sem-progresso`, bem como preservação estrita de `stdout`.
