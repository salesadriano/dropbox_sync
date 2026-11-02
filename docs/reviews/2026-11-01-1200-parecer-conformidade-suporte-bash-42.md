# Parecer de Conformidade Arquitetural e de Boas Praticas - suporte-bash-42, PARTE A

## Identificacao

- Demanda: `suporte-bash-42` (porte G), log `docs/prompts/2026-11-01_1200_suporte-bash-42.md`
- Escopo: PARTE A do System Design (linha principal); a PARTE B (linha legada) tera parecer proprio na sua PR
- Base: `origin/develop` @ `ace646d`; diff de `feature/suporte-bash-42` (commit `eccbca0` + alteracoes da PARTE A)
- Responsavel: Tech Lead | Data: 2026-11-01 | Ciclo: 1

## Escopo verificado

| Arquivo | Tipo de alteracao | Camada / modulo | Verificado |
|---|---|---|---|
| `install.sh` | Alterado | Instalacao (fora do runtime) | Sim |
| `bin/dbx` | Alterado | Ponto de entrada | Sim |
| `lib/preflight.sh` | Alterado | Verificacao de ambiente | Sim |
| `commands/diagnostico.sh` | Alterado | Comando | Sim |
| `lib/cmd.sh` | Alterado (2 diretivas de lint) | Utilitario de comando | Sim |
| `scripts/empacotar.sh` | Alterado | Publicacao | Sim |
| `scripts/suite-bash42.sh` | Novo | Infraestrutura de teste | Sim |
| `tests/unit/instalador_linha_test.sh` | Novo | Teste | Sim |
| `tests/unit/preflight_test.sh` | Alterado | Teste | Sim |
| `README.md`, `docs/testes/inventario-de-testes.md` | Alterado | Documentacao | Sim |

## Stack detectada e skills aplicadas

| Skill aplicada | Motivo da selecao | Regras consultadas |
|---|---|---|
| `clean-architecture` | obrigatoria em qualquer stack | `dep-inward-only`, `dep-acyclic-dependencies`, `adapt-gateway-abstraction`, `comp-common-closure` |
| `shellcheck-configuration` / boas praticas de shell | stack bash + POSIX sh | aspas, `set -euo pipefail`, sem `eval`, diretivas com motivo |

## Verificacao arquitetural

| Verificacao | Regra | Resultado | Evidencia |
|---|---|---|---|
| Direcao de dependencia | `dep-inward-only` | Conforme | `bin/dbx` depende de `lib/preflight.sh`; nenhuma biblioteca passa a depender do ponto de entrada |
| Ciclos de dependencia | `dep-acyclic-dependencies` | Conforme | `lib/preflight.sh` carregado antes das demais tem guarda de carga (`DBX_PREFLIGHT_CARREGADO`); a segunda carga por `bin/dbx:769` e `commands/diagnostico.sh` vira retorno imediato |
| Sistema externo isolado | `adapt-gateway-abstraction` | Conforme | download do instalador num ponto unico (`baixar_fonte`, chamado por `FUNCAO_BAIXAR`), substituivel nos testes; a variavel e atribuida no arquivo, nao lida do ambiente |
| Fonte unica de verdade | `comp-common-closure` | Conforme | o piso de cada fonte vem do `lib/preflight.sh` dela (`piso_da_fonte`), sem tabela copiada no instalador |
| Pureza de dominio, entidades, casos de uso | demais regras | Nao aplicavel | sem dominio novo: instalacao, ponto de entrada e publicacao |

## Verificacao da skill de stack

| Verificacao | Resultado | Evidencia |
|---|---|---|
| Lint | Conforme | `LINT_MEMORIA_MB=15360 sh scripts/lint.sh` sem achado; com o teto padrao (12288 MB) o `commands/download.sh` e interrompido por memoria (pico 13,2 GB medido, residuo da `develop`, nao deste diff) |
| `install.sh` roda no bash 4.2 | Conforme | executado inteiro no `centos:7` (4.2.46): escolha da linha, troca de linha na execucao local, recusa de `--canal master`, falha sem rede com o comando manual |
| Sem `eval`; `--canal` entre aspas em `git clone --branch` e na URL | Conforme | `baixar_fonte`; ataque com metacaracteres delegado a suite do QA |
| Diretivas `shellcheck disable` com motivo | Conforme | SC2086 (`$piso` com dois argumentos, intencional), SC2317, SC2153 |
| Nada escrito no destino antes da recusa (RF-202c, DIV-385 A) | Conforme | conferencia de piso em `obter_raiz_origem` antes de `mkdir` em `executar_instalacao`; `trap limpar_origem_temporaria EXIT` antes do download |
| Teste do conteiner sem privilegio | Conforme | `scripts/suite-bash42.sh` com `--user <uid>:<gid>`; como root os testes de permissao seriam falsos verdes |

## Achados

| Severidade | Arquivo:linha | Regra | Achado | Correcao |
|---|---|---|---|---|
| Bloqueante (corrigido no ciclo) | `bin/dbx` | RF-204 | No bash 4.2 a principal morria em `lib/output.sh:207` (`local -n`) antes do preflight; a mensagem de reinstalacao nunca chegava | Piso conferido antes de qualquer biblioteca, com caso de teste estatico (evidencia, Achados) |
| Maior (corrigido no ciclo) | `scripts/suite-bash42.sh` | testes de permissao | Conteiner como root | `--user` e `HOME=/tmp` |
| Menor | `lib/preflight.sh`, `install.sh`, `README.md` | `comp-common-closure` | A URL do `install.sh` aparece em tres lugares (`DBX_PREFLIGHT_COMANDO_INSTALAR`, `comando_manual`, README) | Aceito: o instalador nao carrega `lib/` (roda antes dela existir) e o README e texto; uma mudanca de repositorio ja exige revisar os tres |
| Menor | `install.sh` | contrato de versao | `linha_instalada` deduz a linha pelo sufixo `-bash42` de `DBX_CLI_VERSAO` | Aceito: convencao fixada no RF-198/RF-205; documentada no comentario |

## Veredito

**Aprovado.** Achados bloqueante e maior corrigidos no ciclo 1 pelo Tech Lead; os menores aceitos com motivo.
