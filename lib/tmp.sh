#!/usr/bin/env bash
# lib/tmp.sh — registro UNICO de areas temporarias e de acoes de liberacao do
# processo (RNF-35, RNF-36; restante de F-31: OBS-02, OBS-03).
#
# Camada: adaptadores. Depende so de lib/errors.sh.
#
# POR QUE UM DONO SO
#
#   `trap` e estado unico do processo: o ultimo armado vence. Com cada modulo
#   armando o seu (hash, transfer, recebimento, sync, verificar), o tratador de
#   fora so rodava se o de dentro lembrasse de entrega-lo, e sinal fora das
#   janelas deixava area para tras. Aqui ha UM tratador por sinal, armado uma
#   vez por processo, que percorre um registro: quem precisa de limpeza
#   registra o que e seu, e ninguem mais chama `trap`.
#
# ORDEM DA LIMPEZA (RNF-35(d))
#
#   Acoes primeiro, em ordem inversa a do registro; depois as areas, tambem em
#   ordem inversa. A acao de quem chamou (liberar a trava, por exemplo) ainda ve
#   as areas que registrou.
#
# SEM JANELA ENTRE CRIACAO E REGISTRO (OBS-03)
#
#   Criacao e registro rodam em secao critica: sinal que chega nela e ANOTADO e
#   entregue no fim da secao, quando a area ja esta no registro. O `$( )` da
#   criacao termina inteiro antes de o tratador rodar (o shell espera o filho).
#   A liberacao inteira tambem e secao critica: sinal durante ela nao a
#   interrompe (RNF-35(h)).
#
# SUBSHELL
#
#   Subshell nao herda tratador, mas herda o registro. Cada entrada guarda o
#   `BASHPID` de quem a registrou, e o tratador de um processo so limpa as
#   suas: o calculo de resumo, que roda em `$( )`, nao apaga a area nem libera a
#   trava de quem o chamou.
#
# CODIGO DE SAIDA
#
#   Termino normal preserva o codigo original (o tratador de `EXIT` nao chama
#   `exit`). Termino por sinal sai com `nao_concluida` (14, RNF-31).

[[ -n ${DBX_TMP_CARREGADO:-} ]] && return 0
DBX_TMP_CARREGADO=1

_dbx_tmp_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_tmp_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_tmp_diretorio=.
# shellcheck source=lib/errors.sh
. "$_dbx_tmp_diretorio/errors.sh"
unset _dbx_tmp_diretorio

DBX_TMP_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_TMP_ERRO_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
DBX_TMP_ERRO_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
readonly DBX_TMP_ERRO_USO DBX_TMP_ERRO_NAO_CONCLUIDA DBX_TMP_ERRO_CONFIGURACAO

# Canais publicos: caminho criado pela ultima chamada e identificador da ultima
# acao registrada.
DBX_TMP_CAMINHO=''
DBX_TMP_ID=''

# Registro. Vetores esparsos de mesmo indice; a entrada sai com `unset`.
_dbx_tmp_dono=()
_dbx_tmp_tipo=()
_dbx_tmp_alvo=()
_dbx_tmp_argumento=()
_dbx_tmp_proximo=0
# `BASHPID` que armou os tratadores e que ja finalizou.
_dbx_tmp_armado=''
_dbx_tmp_finalizado=''
# Secao critica: `BASHPID` dentro dela e sinal anotado para depois.
_dbx_tmp_critico=''
_dbx_tmp_profundidade=0
_dbx_tmp_pendente=''

# ---------------------------------------------------------------------------
# Tratadores
# ---------------------------------------------------------------------------

# _dbx_tmp_armar — arma os tratadores deste processo, uma vez.
_dbx_tmp_armar() {
  [[ $_dbx_tmp_armado == "$BASHPID" ]] && return 0
  trap '_dbx_tmp_sinal INT' INT
  trap '_dbx_tmp_sinal TERM' TERM
  trap '_dbx_tmp_sinal HUP' HUP
  trap '_dbx_tmp_saida' EXIT
  _dbx_tmp_armado=$BASHPID
  _dbx_tmp_finalizado=''
}

# _dbx_tmp_critico_inicio — entra na secao critica; aninha por contagem, e o
# estado herdado por subshell nao vale para ela.
_dbx_tmp_critico_inicio() {
  if [[ $_dbx_tmp_critico != "$BASHPID" ]]; then
    _dbx_tmp_critico=$BASHPID
    _dbx_tmp_profundidade=0
    _dbx_tmp_pendente=''
  fi
  _dbx_tmp_profundidade=$((_dbx_tmp_profundidade + 1))
}

# _dbx_tmp_critico_fim — sai da secao critica e, na mais externa, entrega o
# sinal anotado nela.
_dbx_tmp_critico_fim() {
  [[ $_dbx_tmp_critico == "$BASHPID" ]] || return 0
  _dbx_tmp_profundidade=$((_dbx_tmp_profundidade - 1))
  [[ $_dbx_tmp_profundidade -gt 0 ]] && return 0
  _dbx_tmp_critico=''
  if [[ -n $_dbx_tmp_pendente ]]; then
    local sinal=$_dbx_tmp_pendente
    _dbx_tmp_pendente=''
    _dbx_tmp_sinal "$sinal"
  fi
  return 0
}

# _dbx_tmp_sinal <nome> — INT, TERM e HUP. Na secao critica, so anota.
_dbx_tmp_sinal() {
  if [[ $_dbx_tmp_critico == "$BASHPID" ]]; then
    _dbx_tmp_pendente=$1
    return 0
  fi
  _dbx_tmp_finalizar
  exit "$DBX_TMP_ERRO_NAO_CONCLUIDA"
}

# _dbx_tmp_saida — EXIT. Sem `exit`: o codigo original fica.
_dbx_tmp_saida() {
  _dbx_tmp_finalizar
}

# _dbx_tmp_finalizar — acoes e depois areas deste processo, em ordem inversa,
# uma vez. A secao critica cobre a liberacao inteira; o sinal anotado nela e
# descartado, porque o processo ja esta terminando.
_dbx_tmp_finalizar() {
  [[ $_dbx_tmp_finalizado == "$BASHPID" ]] && return 0
  _dbx_tmp_finalizado=$BASHPID
  _dbx_tmp_critico=$BASHPID
  _dbx_tmp_profundidade=1
  local indice tipo
  local -a indices=("${!_dbx_tmp_tipo[@]}")
  for tipo in acao area; do
    for ((indice = ${#indices[@]} - 1; indice >= 0; indice--)); do
      _dbx_tmp_processar "${indices[indice]}" "$tipo"
    done
  done
  _dbx_tmp_pendente=''
  return 0
}

# _dbx_tmp_processar <indice> <tipo> — executa ou remove uma entrada deste
# processo e a tira do registro ANTES, para nunca repeti-la.
_dbx_tmp_processar() {
  local indice=$1 tipo=$2 alvo argumento
  [[ ${_dbx_tmp_tipo[indice]:-} == "$tipo" && ${_dbx_tmp_dono[indice]:-} == "$BASHPID" ]] || return 0
  alvo=${_dbx_tmp_alvo[indice]}
  argumento=${_dbx_tmp_argumento[indice]}
  _dbx_tmp_tirar "$indice"
  if [[ $tipo == 'acao' ]]; then
    "$alvo" "$argumento" || :
  else
    rm -rf -- "$alvo" 2>/dev/null || :
  fi
}

_dbx_tmp_tirar() {
  unset "_dbx_tmp_dono[$1]" "_dbx_tmp_tipo[$1]" "_dbx_tmp_alvo[$1]" "_dbx_tmp_argumento[$1]"
}

# _dbx_tmp_registrar <tipo> <alvo> <argumento> — chamado dentro da secao critica.
_dbx_tmp_registrar() {
  local indice=$_dbx_tmp_proximo
  _dbx_tmp_proximo=$((indice + 1))
  _dbx_tmp_dono[indice]=$BASHPID
  _dbx_tmp_alvo[indice]=$2
  _dbx_tmp_argumento[indice]=$3
  # O tipo por ultimo: e por ele que a limpeza reconhece a entrada.
  _dbx_tmp_tipo[indice]=$1
  DBX_TMP_ID=$indice
}

# ---------------------------------------------------------------------------
# API publica
# ---------------------------------------------------------------------------

# dbx_tmp_area <rotulo> — cria `${TMPDIR:-/tmp}/dbx-<rotulo>.XXXXXXXX` (0700,
# nome imprevisivel) e a registra. Caminho em DBX_TMP_CAMINHO.
dbx_tmp_area() {
  DBX_TMP_CAMINHO=''
  [[ $# -eq 1 && $1 =~ ^[a-z]{1,32}$ ]] || return "$DBX_TMP_ERRO_USO"
  _dbx_tmp_criar -d "${TMPDIR:-/tmp}/dbx-$1.XXXXXXXX"
}

# dbx_tmp_arquivo <modelo> — cria arquivo 0600 pelo modelo de `mktemp` (que
# termina em X) e o registra. Serve a gravacao atomica no MESMO diretorio do
# destino: o temporario sai em qualquer termino, e quem o renomeia chama
# `dbx_tmp_esquecer`. Caminho em DBX_TMP_CAMINHO.
dbx_tmp_arquivo() {
  DBX_TMP_CAMINHO=''
  [[ $# -eq 1 && $1 == *XXX ]] || return "$DBX_TMP_ERRO_USO"
  _dbx_tmp_criar -f "$1"
}

# _dbx_tmp_criar <-d|-f> <modelo>
#
# A captura de `mktemp` tem alfabeto fechado no que acrescenta (o modelo vem de
# quem chama e termina em X), e a perda da quebra final nao altera o nome.
_dbx_tmp_criar() {
  local -a opcao=()
  local caminho
  [[ $1 == '-d' ]] && opcao=(-d)
  _dbx_tmp_armar
  _dbx_tmp_critico_inicio
  caminho=$(mktemp "${opcao[@]}" -- "$2" 2>/dev/null) || {
    _dbx_tmp_critico_fim
    return "$DBX_TMP_ERRO_CONFIGURACAO"
  }
  _dbx_tmp_registrar area "$caminho" ''
  # shellcheck disable=SC2034  # canal publico, lido por quem cria a area
  DBX_TMP_CAMINHO=$caminho
  _dbx_tmp_critico_fim
  return 0
}

# dbx_tmp_esquecer <caminho> — tira do registro sem apagar (o arquivo foi
# renomeado para o destino, ou passou a ser de outro dono).
dbx_tmp_esquecer() {
  local indice
  _dbx_tmp_critico_inicio
  for indice in "${!_dbx_tmp_tipo[@]}"; do
    [[ ${_dbx_tmp_tipo[indice]} == 'area' && ${_dbx_tmp_dono[indice]} == "$BASHPID" &&
      ${_dbx_tmp_alvo[indice]} == "$1" ]] && _dbx_tmp_tirar "$indice"
  done
  _dbx_tmp_critico_fim
}

# dbx_tmp_remover <caminho> — apaga e tira do registro.
dbx_tmp_remover() {
  [[ -n ${1:-} ]] || return 0
  _dbx_tmp_critico_inicio
  rm -rf -- "$1" 2>/dev/null
  dbx_tmp_esquecer "$1"
  _dbx_tmp_critico_fim
}

# dbx_tmp_acao_registrar <funcao> [argumento] — acao executada em todo termino
# do processo, inclusive por sinal. So nome de FUNCAO existente: texto nunca
# vira codigo executado no sinal. Identificador em DBX_TMP_ID.
dbx_tmp_acao_registrar() {
  # shellcheck disable=SC2034  # canal publico, lido por quem registra
  DBX_TMP_ID=''
  [[ $# -ge 1 && $# -le 2 && $1 =~ ^_?dbx_[a-z0-9_]+$|^[a-z][a-z0-9_]*$ ]] ||
    return "$DBX_TMP_ERRO_USO"
  declare -F -- "$1" >/dev/null || return "$DBX_TMP_ERRO_USO"
  _dbx_tmp_armar
  _dbx_tmp_critico_inicio
  _dbx_tmp_registrar acao "$1" "${2-}"
  _dbx_tmp_critico_fim
  return 0
}

# dbx_tmp_acao_cancelar <id> — a acao ja foi executada por quem a registrou.
dbx_tmp_acao_cancelar() {
  [[ ${1:-} =~ ^[0-9]+$ && ${_dbx_tmp_tipo[$1]:-} == 'acao' && ${_dbx_tmp_dono[$1]} == "$BASHPID" ]] ||
    return 0
  _dbx_tmp_critico_inicio
  _dbx_tmp_tirar "$1"
  _dbx_tmp_critico_fim
}

# dbx_tmp_critico_inicio / dbx_tmp_critico_fim — secao em que INT, TERM e HUP
# ficam anotados e so sao entregues no fim. Para quem precisa criar recurso e
# registrar a acao que o libera sem janela entre os dois (a trava, em
# lib/state). Nao aninha.
dbx_tmp_critico_inicio() {
  _dbx_tmp_armar
  _dbx_tmp_critico_inicio
}
dbx_tmp_critico_fim() { _dbx_tmp_critico_fim; }

# dbx_tmp_armar — arma os tratadores deste processo sem registrar nada. Para
# quem precisa que INT, TERM e HUP terminem com `nao_concluida` (14) antes de
# criar a primeira area: a leitura da senha do `compartilhar` (RF-86(b)), que
# vem antes de qualquer rede.
dbx_tmp_armar() { _dbx_tmp_armar; }
