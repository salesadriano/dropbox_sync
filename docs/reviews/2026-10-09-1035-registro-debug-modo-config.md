# Registro de Entrega — Modo de Depuracao (--debug) em Config e Diagnostico Operacional Completo

> Registro de entrega da demanda conforme regra 41 do protocolo comum e a skill `review-documentation`.

## Identificacao da demanda

| Campo | Valor |
|---|---|
| Demanda | Implementacao de modo de depuracao (`--debug` / `DBX_DEBUG=1`) em `dbx config` e globalmente, captura de erro operacional do SO e diagnostico completo |
| Data / Hora | 2026-10-09 10:35 |
| Dominio | Config / CLI / Diagnostico Operacional |
| Porte | **M (Padrao)** — toca CLI flags, persistencia de credenciais e diagnostico operacional |
| Instancia | `prod/root` |
| Branch de trabalho | `feature/config-debug-diagnostico` |
| Branch principal | `develop` |
| Log de prompt | [2026-10-09_1035_debug-modo-config-diagnostico.md](../prompts/2026-10-09_1035_debug-modo-config-diagnostico.md) |

---

## Contexto e Causa Raiz

Em ambiente de producao executando como `root`, o operador executou `dbx config` e obteve a falha:
```
erro: gravacao da credencial falhou: gravacao
```

### Analise Arquitetural e Causa Raiz
1. **Ocultamento do erro do SO por `2>/dev/null`:**
   Em `lib/config.sh` (`dbx_config_gravar`), a criacao do arquivo temporario via `mktemp "$diretorio/.credencial.$$.XXXXXXXX" 2>/dev/null` e a execucao do subshell atômico redirecionavam `stderr` para `/dev/null`.
   Qualquer causa do sistema operacional (`Read-only file system`, `Permission denied`, `No space left on device`, restricoes de SELinux, etc.) era descartada silenciosamente e mapeada para o motivo opaco `gravacao`.
2. **Execucao como `root` em containers ou servidores endurecidos:**
   Em ambientes como containers Docker/Kubernetes com `readOnlyRootFilesystem: true`, o diretorio `/root` e montado em modo somente-leitura. Sem um diagnostico detalhado do ambiente, o operador nao tinha visibilidade imediata de qual chamada do SO havia falhado nem do estado das permissoes, montagens e espaco em disco.
3. **Ausencia de modo de depuracao na interface CLI:**
   O `dbx` nao possuia flag `--debug` nem canal de depuracao no comando `config` para inspecionar permissao, proprietario, montagem, filesystem e caminho resolvido antes e durante a persistencia.

---

## Modificacoes Realizadas

1. **Interpretador de Linha de Comando (`lib/cli.sh`):**
   - Declarado o canal publico `DBX_CLI_DEBUG='nao'`.
   - Adicionado reconhecimento da opcao global `--debug` e suporte a variavel de ambiente `DBX_DEBUG=1`.
2. **Modulo de Configuracao (`lib/config.sh`):**
   - Declarado o canal publico `DBX_CONFIG_DETALHE=''`.
   - Em `_dbx_config_falhar()`, adicionado suporte ao segundo parametro para reter a mensagem descritiva do erro.
   - Em `dbx_config_gravar()`, capturada a saida de erro de `mktemp` e do subshell de escrita/renomeacao, registrando o erro exato do SO em `DBX_CONFIG_DETALHE`.
3. **Comando Config (`commands/config.sh`):**
   - Reconhecimento do argumento `--debug` no subcomando `dbx config --debug`.
   - Integracao com `DBX_CLI_DEBUG` e `DBX_DEBUG`.
   - Implementada a rotina de diagnostico `_dbx_cmd_config_diagnosticar [diretorio] [arquivo]` na camada de comandos (mantendo `lib/` 100% aderente as invariantes de zero dependencias externas e auditorias de captura do preflight/json), emitindo relatorio estruturado em `stderr` com:
     - PID, EUID, UID e usuario
     - `$HOME` e `$XDG_CONFIG_HOME`
     - Status de existencia, tipo, permissoes (`stat`), dono (`stat`) e gravabilidade (`test -w`) do diretorio e do arquivo
     - Espaco em disco e inodes livres (`df -h`, `df -i`)
     - Pontos de montagem relevantes e modo (`mount`)
     - Status de SELinux (`getenforce`) e atributos de sistema de arquivos (`lsattr`)
     - **Invariante de seguranca mantida:** nenhum segredo, token ou conteudo de credencial e ecoado nos diagnosticos.
   - Exibicao de diagnostico inicial e diagnostico completo no caminho de falha.
   - Enriquecimento da mensagem de erro com `$DBX_CONFIG_DETALHE`.
4. **Ponto de Entrada e Ajuda (`bin/dbx`):**
   - Atualizada a mensagem de ajuda de `dbx config` documentando `[--debug]`.
   - Atualizada a listagem de opcoes globais na ajuda geral.
5. **Documentacao (`README.md`):**
   - Exemplos documentados com `dbx config --debug` e `--debug` global.
   - Atualizacao do badge de testes e contagem oficial para 591 aprovados (593 casos no total).
   - Adicionada subsecao completa de "Diagnostico e Solucao de Problemas em Ambientes Restritos (Root / Containers)", cobrindo:
     - Diagnostico detalhado com `--debug` e `DBX_DEBUG=1`.
     - Redirecionamento de configuracao via `export XDG_CONFIG_HOME="/caminho/gravavel/config"` em sistemas de arquivos read-only.
     - Alerta sobre o consumo unico do codigo OAuth2 pelo Dropbox (necessidade de gerar novo codigo se a etapa de gravacao local falhar).
6. **Auditoria de Canais Publicos (`tests/integracao/composicao_test.sh`):**
   - Canal `DBX_CONFIG_DETALHE` incluido na lista de canais publicos de configuracao permitidos.
7. **Suite de Testes:**
   - `tests/unit/cli_test.sh`: teste unitario para `--debug` global (`teste_opcao_debug_reconhecida_globalmente`).
   - `tests/unit/config_test.sh`: teste unitario para captura de erro do SO em falha de gravacao (`teste_falha_de_gravacao_registra_detalhe_operacional`).
   - `tests/integracao/comandos_test.sh`: 3 testes integrados para `dbx --debug config`, `dbx config --debug` e emissao de relatorio de depuracao em falha de escrita.

---

## Evidencias de Validacao

- **TDD:**
  - Fase vermelha (RED) confirmada isoladamente nos testes unitarios e integrados antes da implementacao.
  - Fase verde (GREEN) confirmada em todos os componentes apos os ajustes.
- **Suite de testes completa (`tests/run.sh`):**
  - 20 arquivos executados, 591 casos aprovados, 0 reprovados, 2 pulados.
- **Guarda de remocao de testes (`scripts/verificar-remocao-de-casos.sh`):**
  - 588 -> 593 casos (+5 novos casos, 0 reducoes). Exit 0.
- **Linter Estatico (`shellcheck`):**
  - Exit 0 em todos os arquivos modificados.
- **Deteccao de alteracoes externas (`scripts/alteracoes-externas.sh`):**
  - Executado e registrado.

---

## Parecer do Tech Lead

- **Status:** Aprovado para integracao em `develop`.
- **Diagnostico para o Operador:** Com a flag `--debug` (ou `DBX_DEBUG=1`), o operador em producao podera identificar imediatamente a restricao exata do SO (ex: filesystem read-only, permissoes ou NFS root_squash) que bloqueia a persistencia.
