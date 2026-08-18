#!/usr/bin/env bash
# lib/output.sh — modelo de resultado unico com duas apresentacoes.
#
# Camada: adaptadores. Depende de lib/errors.sh, de dominio, e de nada mais.
#
# Invariante arquitetural: NENHUM comando imprime. Os comandos alimentam um
# modelo de resultado e este componente escolhe a apresentacao. Sem essa
# disciplina, a apresentacao menos usada diverge com o tempo e o publico
# automatizado herda uma saida que ninguem exercita.
#
# Requisitos: RF-28 (duas apresentacoes sobre o mesmo modelo), RF-35 (contrato
# congelado e versionado), RNF-19 (deteccao de terminal, sobreponivel nos dois
# sentidos) e RNF-22 (restricao de linha, abaixo).
#
# RNF-22 — restricao dura, e a razao de o diagnostico ter canal proprio
# ------------------------------------------------------------------------
# A redacao de cabecalho sensivel em `dbx_errors_redigir` consome o restante da
# LINHA. Isso e deliberado: sob RNF-03, errar para o lado de redigir demais e o
# lado certo. A consequencia vinculante e que este componente **nao pode**
# concatenar campo de diagnostico na mesma linha de um cabecalho sensivel — o
# identificador de correlacao de requisicao, unica razao de existir de RF-30,
# seria levado junto pela redacao.
#
# Por isso cada par de diagnostico ocupa registro proprio, e a restricao vale
# TAMBEM no modo de terminador nulo: o terminador nulo delimita registro, mas a
# redacao continua operando por linha, e as duas fronteiras podem nao coincidir.
#
# Terminador (DIV-16b): por padrao a saida e por linhas; sob `--null` o
# terminador passa a ser o byte nulo, no mesmo padrao de `find -print0` e
# `xargs -0`. E o que torna representavel um nome contendo quebra de linha, que
# RNF-10 exige preservar e que uma saida por linhas nao consegue delimitar.
#
# Sem estado entre execucoes (PRJ-DEC-07): o modelo vive em memoria e e
# descartado por `dbx_output_iniciar`. Este componente nao escreve em disco.

[[ -n ${DBX_OUTPUT_CARREGADO:-} ]] && return 0
DBX_OUTPUT_CARREGADO=1

_dbx_output_diretorio=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_output_diretorio/errors.sh"
# shellcheck source=lib/path.sh
. "$_dbx_output_diretorio/path.sh"
unset _dbx_output_diretorio

# Versao principal do contrato de saida estruturada. Congelada por RF-35:
# dentro dela, campo existente nao muda de nome, tipo ou semantica, e so
# acrescimo e permitido.
readonly DBX_OUTPUT_VERSAO_CONTRATO=1

DBX_OUTPUT_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_OUTPUT_ERRO_USO

# Cabecalhos cujo valor a redacao consome ate o fim da linha. Mantido em sincronia
# conceitual com a lista de chaves sensiveis de lib/errors; aqui a finalidade e
# outra: decidir isolamento de registro, e nao mascarar.
readonly DBX_OUTPUT_CABECALHOS_SENSIVEIS='authorization cookie set_cookie proxy_authorization'

DBX_OUTPUT_MODO=''
DBX_OUTPUT_TERMINADOR='linha'
declare -ga DBX_OUTPUT_CHAVES=()
declare -ga DBX_OUTPUT_VALORES=()
declare -ga DBX_OUTPUT_DIAG_CHAVES=()
declare -ga DBX_OUTPUT_DIAG_VALORES=()

# ---------------------------------------------------------------------------
# Ciclo de vida do modelo
# ---------------------------------------------------------------------------

# dbx_output_iniciar — descarta o resultado anterior e detecta o contexto.
dbx_output_iniciar() {
  DBX_OUTPUT_CHAVES=()
  DBX_OUTPUT_VALORES=()
  DBX_OUTPUT_DIAG_CHAVES=()
  DBX_OUTPUT_DIAG_VALORES=()
  DBX_OUTPUT_TERMINADOR='linha'
  # Deteccao de terminal associado a saida padrao. Sobreponivel nos dois
  # sentidos por `dbx_output_modo`, sem o que o caminho legivel por humano
  # ficaria impossivel de exercitar em teste automatizado, que roda sem
  # terminal — e o caminho menos testado seria o mais visivel ao usuario.
  if [[ -t 1 ]]; then
    DBX_OUTPUT_MODO='humana'
  else
    DBX_OUTPUT_MODO='estruturada'
  fi
}

# dbx_output_modo <humana|estruturada>
dbx_output_modo() {
  case ${1:-} in
    humana | estruturada) DBX_OUTPUT_MODO=$1 ;;
    *) return "$DBX_OUTPUT_ERRO_USO" ;;
  esac
}

# dbx_output_terminador <linha|nulo>
dbx_output_terminador() {
  case ${1:-} in
    linha | nulo) DBX_OUTPUT_TERMINADOR=$1 ;;
    *) return "$DBX_OUTPUT_ERRO_USO" ;;
  esac
}

# _dbx_output_chave_valida <chave> — a chave compoe a gramatica do registro:
# nao pode ser vazia nem conter o separador de par ou quebra de linha, sob pena
# de o consumidor ler campo onde nao ha (E2-13).
_dbx_output_chave_valida() {
  local chave=${1-}
  [[ -n $chave ]] || return 1
  [[ $chave != *=* ]] || return 1
  dbx_path_seguro_para_linha "$chave"
}

# dbx_output_campo <chave> <valor> — alimenta o modelo de resultado.
dbx_output_campo() {
  [[ $# -ge 2 ]] || return "$DBX_OUTPUT_ERRO_USO"
  _dbx_output_chave_valida "${1-}" || return "$DBX_OUTPUT_ERRO_USO"
  DBX_OUTPUT_CHAVES+=("$1")
  DBX_OUTPUT_VALORES+=("$2")
}

# dbx_output_diagnostico <chave> <valor> — canal separado, saida de erro.
#
# A redacao e aplicada AQUI, por valor, no momento de alimentar o modelo, e nao
# sobre o fluxo ja renderizado. Assim a protecao nao depende de alguem a jusante
# lembrar de redigir, e cada valor e mascarado dentro da propria fronteira —
# o que torna desnecessario qualquer isolamento extra de linha na renderizacao.
dbx_output_diagnostico() {
  [[ $# -ge 2 ]] || return "$DBX_OUTPUT_ERRO_USO"
  _dbx_output_chave_valida "${1-}" || return "$DBX_OUTPUT_ERRO_USO"
  dbx_errors_redigir "${2-}" >/dev/null
  DBX_OUTPUT_DIAG_CHAVES+=("$1")
  DBX_OUTPUT_DIAG_VALORES+=("$DBX_ERRORS_REDIGIDO")
}

# ---------------------------------------------------------------------------
# Renderizacao
# ---------------------------------------------------------------------------

_dbx_output_terminar() {
  if [[ $DBX_OUTPUT_TERMINADOR == 'nulo' ]]; then
    printf '\0'
  else
    printf '\n'
  fi
}

# _dbx_output_validar_para_linha — em modo linha, um valor contendo quebra de
# linha, retorno de carro ou tabulacao parte o registro e o consumidor le campos
# onde nao ha. A corrupcao anterior era SILENCIOSA: a funcao que existe para
# detectar isso, `dbx_path_seguro_para_linha`, nao era usada (E2-05).
#
# A recusa e fechada e ocorre ANTES de qualquer emissao, para nao deixar saida
# parcial. A acao corretiva e o modo de terminador nulo.
_dbx_output_validar_para_linha() {
  local indice total=${#DBX_OUTPUT_CHAVES[@]}
  [[ $DBX_OUTPUT_TERMINADOR == 'linha' ]] || return 0
  for ((indice = 0; indice < total; indice++)); do
    if ! dbx_path_seguro_para_linha "${DBX_OUTPUT_VALORES[indice]}"; then
      return "$DBX_OUTPUT_ERRO_USO"
    fi
  done
  return 0
}

# dbx_output_render — resultado na saida padrao, na apresentacao selecionada.
dbx_output_render() {
  local indice total=${#DBX_OUTPUT_CHAVES[@]}

  _dbx_output_validar_para_linha || return "$DBX_OUTPUT_ERRO_USO"

  if [[ $DBX_OUTPUT_MODO == 'estruturada' ]]; then
    printf 'contrato=%s' "$DBX_OUTPUT_VERSAO_CONTRATO"
    _dbx_output_terminar
    for ((indice = 0; indice < total; indice++)); do
      printf '%s=%s' "${DBX_OUTPUT_CHAVES[indice]}" "${DBX_OUTPUT_VALORES[indice]}"
      _dbx_output_terminar
    done
    return 0
  fi

  for ((indice = 0; indice < total; indice++)); do
    printf '%s: %s' "${DBX_OUTPUT_CHAVES[indice]}" "${DBX_OUTPUT_VALORES[indice]}"
    _dbx_output_terminar
  done
}

# _dbx_output_e_sensivel <chave>
_dbx_output_e_sensivel() {
  local chave=${1,,}
  chave=${chave//-/_}
  case " $DBX_OUTPUT_CABECALHOS_SENSIVEIS " in
    *" $chave "*) return 0 ;;
  esac
  return 1
}

# dbx_output_render_diagnostico — diagnostico, um par por registro (RNF-22).
#
# A separacao por registro nao e estetica: um cabecalho sensivel na mesma linha
# de outro campo faria a redacao levar embora o campo vizinho. Como a redacao
# opera por linha inclusive no modo de terminador nulo, cada par sensivel recebe
# ainda uma quebra de linha propria, garantindo que a fronteira de redacao
# coincida com a fronteira do registro nos dois modos.
dbx_output_render_diagnostico() {
  local indice total=${#DBX_OUTPUT_DIAG_CHAVES[@]} chave valor

  # RF-28: diagnostico pertence a saida de ERRO. Emitindo na saida padrao, ele
  # se mistura ao resultado e quebra o consumidor automatizado, que le a saida
  # padrao esperando apenas registros do modelo.
  {
    for ((indice = 0; indice < total; indice++)); do
      chave=${DBX_OUTPUT_DIAG_CHAVES[indice]}
      valor=${DBX_OUTPUT_DIAG_VALORES[indice]}
      if [[ $DBX_OUTPUT_MODO == 'estruturada' ]]; then
        printf '%s=%s' "$chave" "$valor"
      else
        printf '%s: %s' "$chave" "$valor"
      fi
      # Registro uniforme nos dois modos (E2-12). O isolamento extra de linha
      # deixou de ser necessario porque a redacao passou a ser aplicada por
      # valor, ao alimentar o modelo, e nao sobre o fluxo renderizado.
      _dbx_output_terminar
    done
  } >&2
}
