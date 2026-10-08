#!/usr/bin/env bash
# lib/state.sh — memoria auxiliar de desempenho do `sync` (RF-38, RF-42, RF-52).
#
# Camada: adaptadores. Depende de lib/errors.sh, lib/hash.sh e lib/config.sh.
#
# ESTE COMPONENTE NAO DECIDE NADA, e isso e a propriedade central, nao um detalhe
# de implementacao.
#
#   `DP-27b` rebaixou a linha de base a memoria de desempenho. Ela guarda
#   `content_hash` ja calculado para dispensar reler arquivo grande cujo tamanho
#   e `mtime` nao mudaram — e so. Perdida, corrompida ou obsoleta, o `sync`
#   decide igual e apenas trabalha mais.
#
#   `RF-37` fixa a verificacao que prova isso: apagar a memoria entre duas
#   execucoes NAO pode mudar o conjunto de operacoes decididas. `RSK-23` foi
#   reescrito para vigiar exatamente essa propriedade, e a vigilancia e por caso,
#   e nao por leitura de codigo.
#
# POR QUE A CORRUPCAO DESCARTA EM VEZ DE RECUSAR (`RF-42`, invertido por `DP-27b`)
#
#   A versao anterior do requisito mandava recusar a execucao diante de base
#   corrompida, e estava certa enquanto a base arbitrava decisao. Agora seria o
#   contrario do que se quer: recusar um `sync` por causa de um cache
#   transformaria artefato descartavel em ponto unico de falha. Qualquer anomalia
#   — versao desconhecida, registro truncado, conta divergente — resulta em
#   memoria VAZIA e execucao normal.
#
# FORMATO, e por que nao e JSON
#
#   Registros terminados em byte nulo, com o caminho por ultimo. `lib/json` e o
#   interpretador do projeto e seria a escolha natural, mas ele monta a arvore
#   inteira em memoria: uma raiz com dezenas de milhares de arquivos pagaria isso
#   a cada execucao para ler um cache que existe justamente para economizar
#   trabalho. Nome de arquivo aceita tabulacao e quebra de linha e nao aceita
#   nulo, entao o formato suporta qualquer nome sem escape — que e a razao de
#   `lib/config` ter escolhido JSON, e aqui se resolve pelo separador.
#
# O NOME DO ARQUIVO E DERIVADO POR RESUMO, e nao montado com os caminhos.
#
#   As raizes vem do operador e conteriam barra, `..` e quebra de linha. Compor
#   nome de arquivo a partir delas seria derivar caminho de escrita de origem
#   externa — a mesma classe que a tabela literal de `lib/cli` recusa. O resumo
#   da tripla identifica sem carregar nada do texto original.

[[ -n ${DBX_STATE_CARREGADO:-} ]] && return 0
DBX_STATE_CARREGADO=1

_dbx_state_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_state_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_state_diretorio=.
_dbx_state_diretorio=$(cd -P -- "$_dbx_state_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_state_diretorio/errors.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_state_diretorio/hash.sh"
unset _dbx_state_diretorio

DBX_STATE_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_STATE_ERRO_USO

readonly DBX_STATE_VERSAO=1

# shellcheck disable=SC2034  # canais publicos, consumidos por lib/sync e pela suite
DBX_STATE_RESULTADO=''
DBX_STATE_HASH=''
DBX_STATE_MOTIVO=''
DBX_STATE_VISTO='nao'

declare -gA DBX_STATE_ENTRADA=()

_dbx_state_limpar() {
  DBX_STATE_ENTRADA=()
  DBX_STATE_HASH=''
  return 0
}

# dbx_state_caminho <conta> <origem> <destino> — arquivo da memoria, por resumo.
dbx_state_caminho() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo
  DBX_STATE_RESULTADO=''
  dbx_config_caminho_de_estado || return $?
  base=$DBX_CONFIG_RESULTADO
  # A tripla inteira entra no resumo: `RF-52` exige que a identidade da conta
  # participe, e nao so o par de raizes. Trocar de conta passa a designar outro
  # arquivo, e nao a reaproveitar o mesmo com verificacao por dentro — o que
  # tornaria a garantia dependente de a verificacao ser executada.
  # `dbx_hash_conteudo_fluxo` calcula o `content_hash` da Dropbox, que aqui e
  # usado apenas como funcao de resumo — nao ha nada de remoto nisto. Reaproveitar
  # o componente existente evita um segundo caminho de resumo no projeto, que e o
  # mesmo argumento que manteve `lib/json` como interpretador unico.
  resumo=$(printf '%s\n%s\n%s' "$1" "$2" "$3" | dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/memoria-${resumo:0:32}"
  return 0
}

# dbx_state_carregar <conta> <origem> <destino>
#
# NUNCA falha por causa do conteudo. Devolve zero com memoria vazia diante de
# qualquer anomalia, e publica o motivo para o relatorio.
dbx_state_carregar() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local conta=$1 origem=$2 destino=$3
  local arquivo campo registro resto

  _dbx_state_limpar
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_VISTO='nao'

  dbx_state_caminho "$conta" "$origem" "$destino" || {
    DBX_STATE_MOTIVO='nao foi possivel determinar o caminho da memoria'
    return 0
  }
  arquivo=$DBX_STATE_RESULTADO
  [[ -f $arquivo && -r $arquivo ]] || return 0

  # `VISTO` responde a pergunta de `RF-48` — este par de raizes ja foi
  # sincronizado antes? —, e ela e sobre a EXISTENCIA do arquivo, nao sobre o
  # conteudo dele. Uma memoria corrompida ainda prova que houve execucao
  # anterior, e tratar corrupcao como "nunca visto" faria o reconhecimento
  # obrigatorio ser pedido de novo a quem ja o deu.
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_STATE_VISTO='sim'

  local -a cabecalho=()
  local contados=0
  while IFS= read -r -d '' registro; do
    if [[ $contados -lt 4 ]]; then
      cabecalho+=("$registro")
      contados=$((contados + 1))
      continue
    fi
    # TRES campos e depois o caminho, e o caminho leva TUDO o que sobra: ele
    # pode conter tabulacao e quebra de linha. Uma versao anterior deste laco
    # cortava so dois campos, e a entrada entrava na tabela com chave errada e
    # valor incompleto — a consulta seguinte nunca casava, o cache nunca era
    # aproveitado, e nada reprovava, porque cache que nao acerta apenas trabalha
    # mais. Sintoma nenhum: exatamente o modo de falha que este componente tem.
    [[ $registro == *$'\t'*$'\t'*$'\t'* ]] || continue
    campo=${registro%%$'\t'*}
    resto=${registro#*$'\t'}
    local _tamanho=${resto%%$'\t'*}
    resto=${resto#*$'\t'}
    local _mtime=${resto%%$'\t'*}
    DBX_STATE_ENTRADA["${resto#*$'\t'}"]="$campo"$'\t'"$_tamanho"$'\t'"$_mtime"
  done <"$arquivo"

  if [[ ${#cabecalho[@]} -ne 4 ]]; then
    _dbx_state_limpar
    DBX_STATE_MOTIVO='memoria truncada: descartada'
    return 0
  fi
  if [[ ${cabecalho[0]} != "$DBX_STATE_VERSAO" ]]; then
    _dbx_state_limpar
    DBX_STATE_MOTIVO="versao de memoria desconhecida (${cabecalho[0]}): descartada"
    return 0
  fi
  # Verificacao redundante com o resumo do nome, e deliberadamente redundante:
  # `RF-52` e a unica regra do componente cuja violacao nao produz sintoma —
  # resumo reaproveitado de outra conta faz o `sync` OMITIR transferencia
  # necessaria, e omissao nao aparece em relatorio de operacoes.
  if [[ ${cabecalho[1]} != "$conta" || ${cabecalho[2]} != "$origem" || ${cabecalho[3]} != "$destino" ]]; then
    _dbx_state_limpar
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_STATE_MOTIVO='memoria de outra conta ou de outro par de raizes: descartada'
    return 0
  fi
  return 0
}

# dbx_state_consultar <caminho> <tamanho> <mtime>
#
# Publica DBX_STATE_HASH e devolve zero quando o resumo guardado pode ser
# reaproveitado. Tamanho E `mtime` precisam coincidir: `mtime` sozinho nao
# distingue reescrita no mesmo segundo, e tamanho sozinho nao ve troca de
# conteudo do mesmo tamanho.
dbx_state_consultar() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local caminho=$1 tamanho=$2 mtime=$3 entrada
  DBX_STATE_HASH=''
  entrada=${DBX_STATE_ENTRADA[$caminho]:-}
  [[ -n $entrada ]] || return 1
  local guardado_hash=${entrada%%$'\t'*} guardado_resto=${entrada#*$'\t'}
  [[ $guardado_resto == "$tamanho"$'\t'"$mtime" ]] || return 1
  [[ -n $guardado_hash ]] || return 1
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_STATE_HASH=$guardado_hash
  return 0
}

# dbx_state_registrar <caminho> <resumo> <tamanho> <mtime>
dbx_state_registrar() {
  [[ $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  DBX_STATE_ENTRADA["$1"]="$2"$'\t'"$3"$'\t'"$4"
  return 0
}

# dbx_state_gravar <conta> <origem> <destino>
#
# Gravacao atomica pelo mesmo padrao de `lib/config`: temporario no MESMO
# diretorio e renomeacao. Falha de gravacao NAO e falha da execucao — perder o
# cache custa trabalho na proxima vez, e nada mais.
dbx_state_gravar() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local conta=$1 origem=$2 destino=$3 arquivo diretorio temporario caminho

  dbx_state_caminho "$conta" "$origem" "$destino" || return 1
  arquivo=$DBX_STATE_RESULTADO
  diretorio=${arquivo%/*}
  [[ -d $diretorio ]] || mkdir -p -- "$diretorio" 2>/dev/null || return 1

  temporario=$(mktemp "$diretorio/.memoria.$$.XXXXXXXX" 2>/dev/null) || return 1
  {
    printf '%s\0%s\0%s\0%s\0' "$DBX_STATE_VERSAO" "$conta" "$origem" "$destino"
    for caminho in "${!DBX_STATE_ENTRADA[@]}"; do
      printf '%s\t%s\0' "${DBX_STATE_ENTRADA[$caminho]}" "$caminho"
    done
  } >"$temporario" 2>/dev/null || {
    rm -f -- "$temporario" 2>/dev/null
    return 1
  }
  mv -f -- "$temporario" "$arquivo" 2>/dev/null || {
    rm -f -- "$temporario" 2>/dev/null
    return 1
  }
  return 0
}
