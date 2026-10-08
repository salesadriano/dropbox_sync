#!/usr/bin/env bash
# lib/sync.sh — enumeracao remota e tabela de decisao direcional (DP-27).
#
# Camada: aplicacao. Depende de lib/auth, lib/json, lib/cmd e lib/hash.
#
# A TABELA TEM CINCO LINHAS E NENHUM RAMO DE ARBITRAGEM (5.8.2)
#
#   | origem | destino        | acao                                   |
#   |   ✔    | —              | transferir                             |
#   |   ✔    | ✔, resumo ≠    | transferir — a origem prevalece        |
#   |   ✔    | ✔, resumo =    | nenhuma (RF-33)                        |
#   |   —    | ✔              | apagar, SO com espelhamento (RF-40)    |
#   |   —    | —              | nenhuma                                |
#
#   Nao ha conflito porque nao ha dois lados mandando. `DP-27` decidiu assim, e o
#   custo esta declarado: alteracao feita no destino e perdida sem aviso previo,
#   o que torna `RF-47` obrigatorio.
#
# CARIMBO DE TEMPO NAO APARECE EM DECISAO ALGUMA (RF-39)
#
#   Nem para comparar, nem para desempatar — nao ha desempate. `mtime` e usado
#   somente para decidir se um resumo JA CALCULADO pode ser reaproveitado da
#   memoria auxiliar, e essa e a unica ocorrencia dele em todo o componente.
#
# SO ARQUIVOS. LIMITE DECLARADO.
#
#   Diretorio vazio nao e criado nem removido. A Dropbox tem pastas, o sistema de
#   arquivos local tem diretorios, e os dois so coincidem quando ha conteudo:
#   enviar um arquivo cria as pastas intermediarias sozinho, e apagar o ultimo
#   arquivo de uma pasta remota a remove. Sincronizar diretorio vazio exigiria
#   `create_folder` e `delete` de pasta com semantica propria de recursao, que e
#   escopo que ninguem pediu — e fingir que se sincroniza seria pior.

[[ -n ${DBX_SYNC_CARREGADO:-} ]] && return 0
DBX_SYNC_CARREGADO=1

DBX_SYNC_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_SYNC_ERRO_USO

readonly DBX_SYNC_LIMITE_PAGINA=100

# shellcheck disable=SC2034  # canais publicos, consumidos por commands/sync e pela suite
DBX_SYNC_MOTIVO=''
# shellcheck disable=SC2034  # canal publico
DBX_SYNC_LIDO=''
declare -ga DBX_SYNC_TRANSFERIR=()
declare -ga DBX_SYNC_APAGAR=()
declare -ga DBX_SYNC_IDENTICOS=()

# dbx_sync_relativo <raiz_api> <caminho_absoluto>
#
# A Dropbox preserva a grafia mas compara sem distinguir caixa: a raiz que o
# operador digitou pode voltar com outra caixa em `path_display`. O prefixo e
# conferido em caixa baixa e o resto e recortado por POSICAO, nao por casamento
# de texto — assim a grafia devolvida pelo servico e preservada e a comparacao
# nao depende de a caixa coincidir.
dbx_sync_relativo() {
  local raiz=$1 caminho=$2
  DBX_SYNC_LIDO=''
  [[ -n $caminho ]] || return 1
  if [[ -z $raiz ]]; then
    DBX_SYNC_LIDO=${caminho#/}
    return 0
  fi
  local raiz_baixa=${raiz,,} caminho_baixo=${caminho,,}
  [[ $caminho_baixo == "$raiz_baixa/"* ]] || return 1
  DBX_SYNC_LIDO=${caminho:$((${#raiz} + 1))}
  [[ -n $DBX_SYNC_LIDO ]]
}

# dbx_sync_enumerar_remoto <raiz_api> <arquivo>
#
# Emite `resumo<TAB>tamanho<TAB>caminho\0`, no mesmo formato de `lib/walk`, para
# que quem consome nao precise saber de que lado veio a listagem.
#
# Raiz remota INEXISTENTE nao e erro: e arvore vazia. A distincao importa porque
# `--enviar` para um destino que ainda nao existe e o caso normal da primeira
# execucao, e recusar ali obrigaria o operador a criar a pasta a mao.
dbx_sync_enumerar_remoto() {
  [[ $# -eq 2 ]] || return "$DBX_SYNC_ERRO_USO"
  local raiz=$1 destino=$2
  local corpo url estado quantidade indice tag caminho resumo tamanho

  : >"$destino"
  dbx_json_escapar_cadeia "$raiz"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"recursive\":true}"
  # O canal do escapador e ALHEIO e fica limpo assim que o documento e montado.
  # Aqui ele carrega um caminho, e nao segredo — mas a disciplina e de quem
  # PREENCHE o canal, e nao de quem julga o conteudo dele caso a caso. Julgar
  # caso a caso e como uma limpeza deixa de ser feita no dia em que o valor muda.
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  url='https://api.dropboxapi.com/2/files/list_folder'

  while :; do
    dbx_auth_colecao POST "$url" "$corpo" "$DBX_SYNC_LIMITE_PAGINA"
    estado=$?
    if [[ $estado -ne 0 ]]; then
      case ${DBX_HTTP_RESUMO_DE_ERRO:-} in
        *not_found*)
          DBX_SYNC_MOTIVO='raiz remota ainda nao existe: tratada como vazia'
          return 0
          ;;
      esac
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_SYNC_MOTIVO="enumeracao remota recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
      # Recuo para `erro_remoto` quando a classe vem vazia: `return` com cadeia
      # vazia e erro de sintaxe do proprio shell, e a falha do transporte viraria
      # falha nossa no meio do diagnostico dela.
      local codigo
      codigo=$(dbx_errors_codigo_saida "${DBX_HTTP_CLASSE:-erro_remoto}")
      return "$codigo"
    fi

    _dbx_cmd_analisar_corpo || return $?
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
    for ((indice = 0; indice < quantidade; indice++)); do
      tag=''
      _dbx_cmd_campo entries "$indice" '.tag' && tag=$DBX_CMD_LIDO
      # Pasta nao e transferivel e nao entra na tabela. Ver o limite declarado no
      # topo: enviar arquivo cria as intermediarias sozinho.
      [[ $tag == 'file' ]] || continue
      caminho=''
      _dbx_cmd_campo entries "$indice" path_display && caminho=$DBX_CMD_LIDO
      dbx_sync_relativo "$raiz" "$caminho" || continue
      caminho=$DBX_SYNC_LIDO
      resumo=''
      _dbx_cmd_campo entries "$indice" content_hash && resumo=$DBX_CMD_LIDO
      tamanho=0
      _dbx_cmd_campo entries "$indice" size && tamanho=$DBX_CMD_LIDO
      printf '%s\t%s\t%s\0' "$resumo" "$tamanho" "$caminho" >>"$destino"
    done

    local mais='' cursor=''
    _dbx_cmd_campo has_more && mais=$DBX_CMD_LIDO
    _dbx_cmd_campo cursor && cursor=$DBX_CMD_LIDO
    [[ $mais == 'true' && -n $cursor ]] || break
    _dbx_cmd_encerrar_consulta
    dbx_json_escapar_cadeia "$cursor"
    corpo="{\"cursor\":\"$DBX_JSON_ESCAPADO\"}"
    # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
    DBX_JSON_ESCAPADO=''
    url='https://api.dropboxapi.com/2/files/list_folder/continue'
  done

  _dbx_cmd_encerrar_consulta
  return 0
}

# dbx_sync_ler_resumos <arquivo> <nome_do_vetor_de_caminhos> <nome_do_mapa>
dbx_sync_ler_resumos() {
  [[ $# -eq 3 ]] || return "$DBX_SYNC_ERRO_USO"
  local arquivo=$1
  local -n _ordem=$2 _mapa=$3
  local registro resto
  _ordem=()
  _mapa=()
  [[ -r $arquivo ]] || return 0
  while IFS= read -r -d '' registro; do
    [[ $registro == *$'\t'*$'\t'* ]] || continue
    resto=${registro#*$'\t'}
    _ordem+=("${resto#*$'\t'}")
    _mapa["${resto#*$'\t'}"]=${registro%%$'\t'*}
  done <"$arquivo"
  return 0
}

# dbx_sync_planejar <vetor_origem> <mapa_origem> <vetor_destino> <mapa_destino>
#
# Aplica a tabela de 5.8.2. Nao emite escrita alguma: separar decidir de executar
# e o que permite a `RF-44` imprimir o plano completo e a `RF-41(d)` anunciar
# toda exclusao ANTES da primeira delas.
dbx_sync_planejar() {
  [[ $# -eq 4 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _ordem_o=$1 _mapa_o=$2 _ordem_d=$3 _mapa_d=$4
  local caminho resumo_o resumo_d

  DBX_SYNC_TRANSFERIR=()
  DBX_SYNC_APAGAR=()
  DBX_SYNC_IDENTICOS=()

  for caminho in ${_ordem_o[@]+"${_ordem_o[@]}"}; do
    resumo_o=${_mapa_o[$caminho]:-}
    if [[ -z ${_mapa_d[$caminho]+definido} ]]; then
      DBX_SYNC_TRANSFERIR+=("$caminho")
      continue
    fi
    resumo_d=${_mapa_d[$caminho]:-}
    # `dbx_hash_iguais` distingue "diferentes" de "malformado", e a distincao
    # decide: resumo ilegivel NAO pode ser lido como conteudo identico, sob pena
    # de omitir uma transferencia necessaria — que e a falha sem sintoma.
    dbx_hash_iguais "$resumo_o" "$resumo_d"
    case $? in
      0) DBX_SYNC_IDENTICOS+=("$caminho") ;;
      *) DBX_SYNC_TRANSFERIR+=("$caminho") ;;
    esac
  done

  for caminho in ${_ordem_d[@]+"${_ordem_d[@]}"}; do
    [[ -z ${_mapa_o[$caminho]+definido} ]] && DBX_SYNC_APAGAR+=("$caminho")
  done
  return 0
}
