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

_dbx_sync_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_sync_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_sync_diretorio=.
_dbx_sync_diretorio=$(cd -P -- "$_dbx_sync_diretorio" && pwd -P)
# shellcheck source=lib/progress.sh
. "$_dbx_sync_diretorio/progress.sh"
# shellcheck source=lib/filtro.sh
. "$_dbx_sync_diretorio/filtro.sh"
unset _dbx_sync_diretorio

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
# Caminho do item da origem como o DESTINO o grafa: a grafia que ja existe do
# outro lado quando o par existe, ou a da origem quando o item e novo. E por ele
# que a escrita acontece — gravar com a grafia da origem num destino que
# diferencia caixa criaria uma segunda copia ao lado da existente.
declare -gA DBX_SYNC_ALVO=()
# shellcheck disable=SC2034  # canal publico de _dbx_sync_chave
DBX_SYNC_CHAVE=''

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

# Localidade da comparacao sem caixa (RF-54(e)): a MESMA de `lib/filtro`, que e
# dono da chave (padrao de filtro e caminho passam pela mesma dobra, RF-79(h)).
DBX_SYNC_LOCALIDADE=$DBX_FILTRO_LOCALIDADE
readonly DBX_SYNC_LOCALIDADE

# _dbx_sync_chave <caminho> — chave de comparacao em DBX_SYNC_CHAVE (RF-54).
#
# A Dropbox nao diferencia caixa, entao dois caminhos que so diferem nela sao o
# MESMO arquivo. A dobra e a de `dbx_filtro_chave` (lib/filtro): a localidade
# UTF-8 fixada SO dentro dela, em `LC_ALL` local (DIV-32), sem vazar para
# nenhuma medida em bytes do resto do processo. Uma copia aqui seria o codigo
# gemeo de RNF-36, e o filtro poderia dobrar diferente da comparacao.
_dbx_sync_chave() {
  dbx_filtro_chave "$1"
  DBX_SYNC_CHAVE=$DBX_FILTRO_CHAVE
}

# ---------------------------------------------------------------------------
# Escopo filtrado (RF-80)
# ---------------------------------------------------------------------------

# Itens filtrados do lado corrente, contados uma vez cada pela chave sem caixa:
# pasta excluida conta 1 e o conteudo dela nao conta (RF-80(i)). Zerado por
# `dbx_sync_filtrados_zerar` antes de cada lado; o total em DBX_SYNC_FILTRADOS.
declare -gA DBX_SYNC_FILTRADOS_CHAVES=()
DBX_SYNC_FILTRADOS=0

dbx_sync_filtrados_zerar() {
  DBX_SYNC_FILTRADOS_CHAVES=()
  DBX_SYNC_FILTRADOS=0
}

_dbx_sync_contar_filtrado() {
  _dbx_sync_chave "$1"
  # RF-161(b)(c): o item filtrado e "pulado" com `motivo=filtrado`, uma vez por
  # chave. So o `sync` liga (DBX_SYNC_DEBUG_DECISAO); `verificar` usa o mesmo
  # predicado e nao emite decisao.
  [[ ${DBX_SYNC_DEBUG_DECISAO:-nao} == 'sim' && -z ${DBX_SYNC_FILTRADOS_CHAVES[$DBX_SYNC_CHAVE]+definido} ]] &&
    dbx_debug_linha sync decisao=pular motivo=filtrado item="$1"
  DBX_SYNC_FILTRADOS_CHAVES[$DBX_SYNC_CHAVE]=1
  # shellcheck disable=SC2034  # canal publico, lido por commands/sync e verificar
  DBX_SYNC_FILTRADOS=${#DBX_SYNC_FILTRADOS_CHAVES[@]}
}

# dbx_sync_no_escopo <origem|destino> <relativo> <arquivo|pasta>
#
# PREDICADO UNICO do escopo de caminho, para os dois lados e as duas pontas
# (local e remota): o mesmo padrao vale nas duas pontas, sobre o mesmo caminho
# relativo (RF-79(b)). 0 no escopo; 1 filtrado, e o item que conta e contado.
#
# Pasta so e filtrada por `--excluir`: com `--incluir`, toda pasta nao excluida
# e percorrida para alcancar o arquivo incluido em qualquer profundidade
# (RF-80(c)), e a pasta existe so pelo arquivo que contem.
dbx_sync_no_escopo() {
  [[ $# -eq 3 && ($1 == 'origem' || $1 == 'destino') ]] || return "$DBX_SYNC_ERRO_USO"
  if [[ $3 == 'pasta' ]]; then
    dbx_filtro_classificar "$2" sim && return 0
    [[ $DBX_FILTRO_RAZAO == 'excluido' ]] || return 0
  else
    dbx_filtro_classificar "$2" nao && return 0
  fi
  _dbx_sync_contar_filtrado "$DBX_FILTRO_FILTRADO"
  return 1
}

# dbx_sync_filtrar_caminhos <origem|destino> <vetor_caminhos> <vetor_tamanhos>
#   <vetor_identidades> — retira da arvore LOCAL o que esta fora do escopo de
# caminho e conta, junto com as pastas e entradas que a descida podou
# (`DBX_WALK_PODADAS`, RF-80(b)). Sem padrao de caminho, nao mexe em nada.
dbx_sync_filtrar_caminhos() {
  [[ $# -eq 4 ]] || return "$DBX_SYNC_ERRO_USO"
  local lado=$1
  local -n _fc_c=$2 _fc_t=$3 _fc_i=$4
  dbx_filtro_ativo || return 0
  local podada indice
  # A poda roda no subshell da travessia, onde a marca de "padrao casou" se
  # perde; reclassificar aqui a refaz e conta a pasta como 1.
  for podada in ${DBX_WALK_PODADAS[@]+"${DBX_WALK_PODADAS[@]}"}; do
    if ! dbx_sync_no_escopo "$lado" "$podada" pasta; then continue; fi
    dbx_sync_no_escopo "$lado" "$podada" arquivo || :
  done
  local -a c=() t=() i=()
  for indice in "${!_fc_c[@]}"; do
    dbx_sync_no_escopo "$lado" "${_fc_c[$indice]}" arquivo || continue
    c+=("${_fc_c[$indice]}") t+=("${_fc_t[$indice]}") i+=("${_fc_i[$indice]}")
  done
  _fc_c=(${c[@]+"${c[@]}"}) _fc_t=(${t[@]+"${t[@]}"}) _fc_i=(${i[@]+"${i[@]}"})
  return 0
}

# dbx_sync_filtrar_meta <vetor_caminhos> <vetor_tamanhos> <vetor_identidades>
#
# RF-81(c): data e tamanho, so na origem LOCAL. A data e o `mtime` da identidade
# lida pela travessia (segundo campo da identidade, mtime em segundos), convertido
# em UTC sem utilitario; sem identidade (leitura falhou), o arquivo nao passa num
# filtro de data.
dbx_sync_filtrar_meta() {
  [[ $# -eq 3 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _fm_c=$1 _fm_t=$2 _fm_i=$3
  dbx_filtro_meta_ativo || return 0
  local indice
  local -a c=() t=() i=()
  for indice in "${!_fm_c[@]}"; do
    dbx_filtro_carimbo_de_epoca "${_fm_i[$indice]%%|*}" || :
    if ! dbx_filtro_meta_passa "$DBX_FILTRO_CARIMBO" "${_fm_t[$indice]}"; then
      _dbx_sync_contar_filtrado "${_fm_c[$indice]}"
      continue
    fi
    c+=("${_fm_c[$indice]}") t+=("${_fm_t[$indice]}") i+=("${_fm_i[$indice]}")
  done
  _fm_c=(${c[@]+"${c[@]}"}) _fm_t=(${t[@]+"${t[@]}"}) _fm_i=(${i[@]+"${i[@]}"})
  return 0
}

# Avisos de filtro mal escrito (DIV-91), em DBX_SYNC_AVISOS, uma frase cada.
declare -ga DBX_SYNC_AVISOS=()

# dbx_sync_avisos_de_filtro <arquivos_da_origem_antes> <arquivos_da_origem_depois>
dbx_sync_avisos_de_filtro() {
  local antes=${1:-0} depois=${2:-0} padrao
  DBX_SYNC_AVISOS=()
  dbx_filtro_avisos
  for padrao in ${DBX_FILTRO_SEM_CASAMENTO[@]+"${DBX_FILTRO_SEM_CASAMENTO[@]}"}; do
    dbx_filtro_citar "$padrao"
    DBX_SYNC_AVISOS+=("padrao $DBX_FILTRO_CITADO nao casou nenhum item")
  done
  if { dbx_filtro_ativo || dbx_filtro_meta_ativo; } && [[ $antes -gt 0 && $depois -eq 0 ]]; then
    DBX_SYNC_AVISOS+=('nenhum item da origem passou pelos filtros')
  fi
  return 0
}

# dbx_sync_localidade_disponivel — 0 quando a comparacao sem caixa vale fora do
# ASCII; senao 1, com o aviso de RF-54(f) em DBX_SYNC_MOTIVO.
#
# Pergunta a propria comparacao, e nao `locale -a`: o que importa e a conversao
# funcionar, e assim nao ha utilitario nem captura a mais.
dbx_sync_localidade_disponivel() {
  _dbx_sync_chave $'\xc3\x89'
  [[ $DBX_SYNC_CHAVE == $'\xc3\xa9' ]] && return 0
  # shellcheck disable=SC2034  # canal publico, lido por commands/sync
  DBX_SYNC_MOTIVO="localidade $DBX_SYNC_LOCALIDADE ausente: a comparacao sem caixa de caminhos vale so no ASCII (nomes que so diferem na caixa de letras acentuadas contam como distintos)"
  return 1
}

# dbx_sync_colisao_de_caixa <nome_do_vetor> — 1 quando dois caminhos do vetor
# so diferem na caixa; o par vai nomeado em DBX_SYNC_MOTIVO.
#
# Do lado local isso e possivel e do remoto nao: `a.txt` e `A.txt` viram um
# arquivo so na Dropbox, e enviar os dois faria o segundo sobrescrever o
# primeiro sem aviso; receber escolheria um deles por acaso.
dbx_sync_colisao_de_caixa() {
  [[ $# -eq 1 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _caminhos=$1
  local -A _vistos=()
  local caminho
  for caminho in ${_caminhos[@]+"${_caminhos[@]}"}; do
    _dbx_sync_chave "$caminho"
    if [[ -n ${_vistos[$DBX_SYNC_CHAVE]+definido} ]]; then
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_SYNC_MOTIVO="colisao de caixa na arvore local: '${_vistos[$DBX_SYNC_CHAVE]}' e '$caminho' sao o mesmo caminho na Dropbox"
      return 1
    fi
    _vistos[$DBX_SYNC_CHAVE]=$caminho
  done
  return 0
}

# dbx_sync_sem_temporarios <vetor_caminhos> <vetor_tamanhos> <vetor_mtimes>
#
# Retira da arvore local os temporarios de recebimento (`.<nome>.dbx-part.XXXXXX`)
# que um processo interrompido sem tratador deixou: contados como arquivo, um
# `--enviar` os publicaria e um `--receber --espelhar` os planejaria apagar.
dbx_sync_sem_temporarios() {
  [[ $# -eq 3 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _c=$1 _t=$2 _m=$3
  local -a c=() t=() m=()
  local indice nome
  for indice in "${!_c[@]}"; do
    nome=${_c[$indice]##*/}
    [[ $nome == .*"$DBX_CMD_MARCA_RECEBIMENTO"?????? ]] && continue
    c+=("${_c[$indice]}") t+=("${_t[$indice]}") m+=("${_m[$indice]}")
  done
  _c=(${c[@]+"${c[@]}"}) _t=(${t[@]+"${t[@]}"}) _m=(${m[@]+"${m[@]}"})
  return 0
}

# dbx_sync_enumerar_remoto <raiz_api> <arquivo> [arquivo_de_revs] [lado]
#
# Emite `resumo<TAB>tamanho<TAB>caminho\0`, no mesmo formato de `lib/walk`, para
# que quem consome nao precise saber de que lado veio a listagem.
#
# O `rev` vai para arquivo PROPRIO, em `rev<TAB>caminho\0`: e o valor que o
# envio leva como concorrencia otimista (RF-49), lido nesta mesma execucao, e
# mante-lo fora do registro preserva a paridade de formato com `lib/walk`.
#
# Raiz remota INEXISTENTE nao e erro: e arvore vazia. A distincao importa porque
# `--enviar` para um destino que ainda nao existe e o caso normal da primeira
# execucao, e recusar ali obrigaria o operador a criar a pasta a mao.
#
# Fase 7b (DIV-g): e a varredura completa (`dbx_sync_listar_completo`, a tabela
# sem filtro) seguida da emissao com o escopo filtrado
# (`dbx_sync_tabela_emitir`). A pasta excluida conta 1 (DIV-82, RF-80(i)); na
# `origem`, data e tamanho tambem filtram (RF-81). Em DBX_SYNC_REMOTOS_ANTES
# fica quantos arquivos a listagem trouxe antes de qualquer filtro.
DBX_SYNC_REMOTOS_ANTES=0
dbx_sync_enumerar_remoto() {
  [[ $# -ge 2 && $# -le 4 ]] || return "$DBX_SYNC_ERRO_USO"
  DBX_SYNC_REMOTOS_ANTES=0
  : >"$2"
  [[ -n ${3:-} ]] && : >"$3"
  dbx_sync_listar_completo "$1" "${4:-}" || return $?
  dbx_sync_tabela_emitir "$@"
}

# ---------------------------------------------------------------------------
# Tabela remota sem filtro (fase 7b, DIV-g; RF-112, RF-115)
# ---------------------------------------------------------------------------
#
# A enumeracao remota monta PRIMEIRO a tabela inteira, sem filtro, e so depois
# emite o escopo (`dbx_sync_tabela_emitir`). E a mesma tabela que vira o
# retrato do `cursor-*` e que recebe o delta do `list_folder/continue`: assim a
# varredura completa e a incremental passam pelo MESMO filtro, pelas mesmas
# contagens e pelo mesmo planejador, e o plano so pode diferir se a tabela
# diferir (RF-112(d)).
#
# Chave: `path_lower` do servidor. Valor, o registro do retrato (lib/state):
#   tag<TAB>id<TAB>rev<TAB>content_hash<TAB>tamanho<TAB>server_modified<TAB>path_display
# com `f` ou `d` e `-` no que falta. As entradas sao aplicadas na ordem, pela
# receita do servico (Context7, `list_folder`, DIV-219): `file` substitui o que
# houver e remove os filhos; `folder` substitui arquivo e mantem os filhos;
# `deleted` remove o caminho e os filhos, e e ignorada quando desconhecida.

# Assinatura da listagem (C2): os argumentos do `list_folder` deste codigo.
# Mudou o codigo, mudou a assinatura, e o registro anterior e descartado.
# shellcheck disable=SC2034  # constante publica, lida por commands/sync
readonly DBX_SYNC_ASSINATURA_LISTAGEM='list_folder;recursive=1;include_deleted=0;include_mounted_folders=1;include_non_downloadable_files=1;limit=100'
# Guardas de laco (DIV-h, C11): cursor repetido ou mais paginas que isto. O
# teto cobre o retrato maximo (1.000.000 de entradas em paginas de 100) com
# folga, para nao recusar arvore que a versao anterior listava (DIV-224).
readonly DBX_SYNC_TETO_PAGINAS=20000
# Confirmacoes de exclusao por execucao (DIV-209): acima, varredura completa.
readonly DBX_SYNC_TETO_CONFIRMACOES=50

declare -gA DBX_SYNC_TAB=()
declare -ga DBX_SYNC_TAB_ORDEM=()
declare -gA DBX_SYNC_TAB_NA_ORDEM=()
# `sim` enquanto toda entrada couber no formato do retrato (C4): `id`, `rev`,
# `path_lower`, caminho confinado. Uma entrada fora disso so impede GRAVAR o
# retrato; a varredura segue como sempre.
DBX_SYNC_TAB_PERSISTIVEL='sim'
# Cursor da ultima pagina desta execucao. Identificador operacional sensivel
# (C10): nunca em mensagem, progresso nem saida.
DBX_SYNC_CURSOR_NOVO=''
# Delta: entradas lidas, raizes apagadas (chave -> registro antigo), motivo
# do abandono do incremental e confirmacoes feitas.
DBX_SYNC_DELTA_MUDANCAS=0
declare -gA DBX_SYNC_DELTA_APAGADAS=()
DBX_SYNC_CURSOR_MOTIVO=''
DBX_SYNC_CONFIRMADAS=0
DBX_SYNC_CONTRADICAO=''

dbx_sync_tabela_zerar() {
  DBX_SYNC_TAB=()
  DBX_SYNC_TAB_ORDEM=()
  DBX_SYNC_TAB_NA_ORDEM=()
  DBX_SYNC_TAB_PERSISTIVEL='sim'
  DBX_SYNC_CURSOR_NOVO=''
  DBX_SYNC_DELTA_MUDANCAS=0
  DBX_SYNC_DELTA_APAGADAS=()
  return 0
}

# _dbx_sync_tab_remover <path_lower> — remove a chave e, se era pasta, todo
# descendente (`path_lower` iniciado por `<chave>/`). Arquivo nao tem filhos:
# a varredura dos descendentes so corre para pasta.
_dbx_sync_tab_remover() {
  local pl=$1 outra
  local registro=${DBX_SYNC_TAB[$pl]-}
  unset 'DBX_SYNC_TAB[$pl]'
  [[ $registro == d$'\t'* ]] || return 0
  for outra in "${!DBX_SYNC_TAB[@]}"; do
    [[ $outra == "$pl/"* ]] && unset 'DBX_SYNC_TAB[$outra]'
  done
  return 0
}

_dbx_sync_tab_inserir() {
  local pl=$1
  DBX_SYNC_TAB[$pl]=$2
  if [[ -z ${DBX_SYNC_TAB_NA_ORDEM[$pl]+definido} ]]; then
    DBX_SYNC_TAB_NA_ORDEM[$pl]=1
    DBX_SYNC_TAB_ORDEM+=("$pl")
  fi
}

# _dbx_sync_relativo_seguro <raiz> <caminho> — `dbx_sync_relativo` mais a
# forma de cada componente: sem vazio, `.`, `..` nem byte de controle. E o
# confinamento que o estado e o delta precisam passar (RF-50, RF-112(e)).
_dbx_sync_relativo_seguro() {
  dbx_sync_relativo "$1" "$2" || return 1
  local LC_ALL=C
  [[ $DBX_SYNC_LIDO != *[[:cntrl:]]* && /$DBX_SYNC_LIDO/ != *//* && /$DBX_SYNC_LIDO/ != */./* &&
    /$DBX_SYNC_LIDO/ != */../* ]]
}

# _dbx_sync_entrada <raiz> <indice> <modo> [lado] — aplica a entrada <indice>
# da pagina corrente a tabela. <modo> `completa`: a resposta viva, que vale como
# hoje (entrada incoerente so impede gravar o retrato). <modo> `delta`: entrada
# incoerente devolve 1 e o incremental e abandonado (RF-112(e)).
#
# A data remota (RF-39, RF-81) so e LIDA quando ela delimita o escopo: lado
# `origem` com filtro de data ou tamanho. Fora disso o retrato a guarda como
# `-`, e o incremental com filtro de data exige a data em toda entrada
# (`dbx_sync_tabela_datada`), senao volta a varredura completa.
_dbx_sync_entrada() {
  local raiz=$1 indice=$2 modo=$3 lado=${4:-}
  local tag='' exibido='' baixo='' id='' rev='' resumo='' tamanho='' carimbo='' coerente='sim'
  _dbx_cmd_campo entries "$indice" '.tag' && tag=$DBX_CMD_LIDO
  _dbx_cmd_campo entries "$indice" path_display && exibido=$DBX_CMD_LIDO
  _dbx_cmd_campo entries "$indice" path_lower && baixo=$DBX_CMD_LIDO
  # QA-B7B-02: o `list_folder` recursivo devolve a PROPRIA pasta listada
  # (Context7: listar /Homework/math traz /homework/math). Reconhecida pela
  # estrutura — `path_lower` igual a raiz pedida, sem caixa —, ela nao e conteudo:
  # a pasta e ignorada, e a raiz apagada (ou virando arquivo) no delta e
  # incoerente. Qualquer outra entrada fora da raiz segue o confinamento abaixo.
  if [[ -n $raiz && -n $baixo && ${baixo,,} == "${raiz,,}" ]]; then
    [[ $tag == 'folder' ]] && return 0
    [[ $modo == 'delta' ]] && return 1
    DBX_SYNC_TAB_PERSISTIVEL='nao'
    return 0
  fi
  case $tag in
    deleted)
      DBX_SYNC_DELTA_MUDANCAS=$((DBX_SYNC_DELTA_MUDANCAS + 1))
      # `path_lower` nulo (item nao montado): sem chave, sem como aplicar.
      if [[ -z $baixo ]]; then
        [[ $modo == 'delta' ]] && return 1
        DBX_SYNC_TAB_PERSISTIVEL='nao'
        return 0
      fi
      if [[ -n ${DBX_SYNC_TAB[$baixo]+definido} ]]; then
        [[ $modo == 'delta' ]] && DBX_SYNC_DELTA_APAGADAS[$baixo]=${DBX_SYNC_TAB[$baixo]}
        _dbx_sync_tab_remover "$baixo"
      fi
      return 0
      ;;
    file | folder) ;;
    *)
      [[ $modo == 'delta' ]] && return 1
      return 0
      ;;
  esac
  DBX_SYNC_DELTA_MUDANCAS=$((DBX_SYNC_DELTA_MUDANCAS + 1))
  _dbx_cmd_campo entries "$indice" id && id=$DBX_CMD_LIDO
  [[ -n $exibido ]] || coerente='nao'
  if [[ -z $baixo ]]; then
    coerente='nao'
    # Sem `path_lower` (resposta fora do contrato, ou duplo de teste antigo),
    # a chave sem caixa da comparacao (RF-54) serve a tabela desta execucao.
    if [[ -n $exibido ]]; then
      _dbx_sync_chave "$exibido"
      baixo=$DBX_SYNC_CHAVE
    fi
  fi
  [[ -n $baixo ]] || {
    [[ $modo == 'delta' ]] && return 1
    DBX_SYNC_TAB_PERSISTIVEL='nao'
    return 0
  }
  [[ $id =~ ^id:[A-Za-z0-9_-]{1,64}$ ]] || coerente='nao'
  [[ $baixo == /* ]] || coerente='nao'
  # QA-B7B-03 (RF-112(e), RF-115(h)): o `path_lower` vindo do servico, que vira a
  # chave do retrato, passa pelo MESMO confinamento do `path_display`.
  if [[ $coerente == 'sim' ]] && ! _dbx_sync_relativo_seguro "$raiz" "$baixo"; then
    coerente='nao'
  fi
  if [[ $tag == 'file' ]]; then
    _dbx_cmd_campo entries "$indice" rev && rev=$DBX_CMD_LIDO
    _dbx_cmd_campo entries "$indice" content_hash && resumo=$DBX_CMD_LIDO
    _dbx_cmd_campo entries "$indice" size && tamanho=$DBX_CMD_LIDO
    [[ $rev =~ ^[0-9a-f]{9,64}$ ]] || coerente='nao'
    [[ $resumo =~ ^[0-9a-f]{64}$ ]] || {
      [[ -z $resumo ]] || coerente='nao'
    }
    [[ $tamanho =~ ^[0-9]{1,18}$ ]] || coerente='nao'
    if [[ $lado == 'origem' ]] && dbx_filtro_meta_ativo; then
      _dbx_cmd_campo entries "$indice" "$DBX_FILTRO_CAMPO_DATA_REMOTA" && carimbo=$DBX_CMD_LIDO
      [[ -z $carimbo || $carimbo =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || coerente='nao'
    fi
  fi
  if [[ -n $exibido ]] && ! _dbx_sync_relativo_seguro "$raiz" "$exibido"; then
    coerente='nao'
  fi
  if [[ $coerente != 'sim' ]]; then
    [[ $modo == 'delta' ]] && return 1
    DBX_SYNC_TAB_PERSISTIVEL='nao'
  fi
  local registro
  if [[ $tag == 'file' ]]; then
    printf -v registro 'f\t%s\t%s\t%s\t%s\t%s\t%s' "${id:--}" "${rev:--}" "${resumo:--}" "${tamanho:-0}" \
      "${carimbo:--}" "$exibido"
    # Arquivo substitui o que houver e remove os filhos (pasta que virou
    # arquivo).
    [[ -n ${DBX_SYNC_TAB[$baixo]+definido} ]] && _dbx_sync_tab_remover "$baixo"
  else
    printf -v registro 'd\t%s\t-\t-\t0\t-\t%s' "${id:--}" "$exibido"
    # Pasta substitui arquivo; os filhos de uma pasta ficam.
    [[ ${DBX_SYNC_TAB[$baixo]-} == f$'\t'* ]] && unset 'DBX_SYNC_TAB[$baixo]'
  fi
  _dbx_sync_tab_inserir "$baixo" "$registro"
  return 0
}

# _dbx_sync_pagina_seguinte <cursor_anterior> — le `has_more` e `cursor` da
# pagina corrente. 0 ha proxima (cursor em DBX_SYNC_CURSOR_NOVO); 1 ultima
# pagina (cursor em DBX_SYNC_CURSOR_NOVO, talvez vazio); 2 laco: `has_more`
# sem cursor novo, ou o MESMO cursor de novo (DIV-h).
_dbx_sync_pagina_seguinte() {
  local anterior=$1 mais=''
  DBX_SYNC_CURSOR_NOVO=''
  _dbx_cmd_campo has_more && mais=$DBX_CMD_LIDO
  _dbx_cmd_campo cursor && DBX_SYNC_CURSOR_NOVO=$DBX_CMD_LIDO
  DBX_CMD_LIDO=''
  [[ $mais == 'true' ]] || return 1
  [[ -n $DBX_SYNC_CURSOR_NOVO && $DBX_SYNC_CURSOR_NOVO != "$anterior" ]] || return 2
  return 0
}

# _dbx_sync_corpo_continue <cursor> — corpo do `continue` SO com o cursor
# (F-40 no sync, DIV-214 B): o cursor ja carrega o limite da listagem. O canal
# do escapador fica limpo assim que o documento e montado (C10).
_DBX_SYNC_CORPO=''
_dbx_sync_corpo_continue() {
  dbx_json_escapar_cadeia "$1"
  _DBX_SYNC_CORPO="{\"cursor\":\"$DBX_JSON_ESCAPADO\"}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
}

# dbx_sync_listar_completo <raiz_api> [lado] — a varredura completa: `list_folder`
# recursivo com limite (RNF-23) e `continue` so com o cursor, montando a tabela
# sem filtro. Raiz remota inexistente e tabela vazia, como sempre. Status de
# hoje: 0, ou o codigo da classe do erro (motivo em DBX_SYNC_MOTIVO); laco de
# paginas (DIV-h) e `erro_remoto`.
dbx_sync_listar_completo() {
  [[ $# -ge 1 && $# -le 2 ]] || return "$DBX_SYNC_ERRO_USO"
  local raiz=$1 lado=${2:-} corpo url estado quantidade indice pagina=1 anterior='' codigo
  dbx_sync_tabela_zerar
  dbx_json_escapar_cadeia "$raiz"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"recursive\":true}"
  # O canal do escapador e ALHEIO e fica limpo assim que o documento e montado.
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  url='https://api.dropboxapi.com/2/files/list_folder'

  while :; do
    if [[ $pagina -eq 1 ]]; then
      dbx_auth_colecao POST "$url" "$corpo" "$DBX_SYNC_LIMITE_PAGINA"
    else
      dbx_auth_requisitar POST "$url" "$_DBX_SYNC_CORPO" sim
    fi
    estado=$?
    _DBX_SYNC_CORPO=''
    if [[ $estado -ne 0 ]]; then
      if [[ $pagina -eq 1 ]]; then
        case ${DBX_HTTP_RESUMO_DE_ERRO:-} in
          *not_found*)
            DBX_SYNC_MOTIVO='raiz remota ainda nao existe: tratada como vazia'
            dbx_progress_mensagem "[sync] consultando remoto: raiz remota ainda nao existe (tratada como vazia)"
            # shellcheck disable=SC2034  # canal publico, lido por commands/sync
            DBX_SYNC_TAB_PERSISTIVEL='nao'
            return 0
            ;;
        esac
      fi
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_SYNC_MOTIVO="enumeracao remota recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
      # Recuo para `erro_remoto` quando a classe vem vazia: `return` com cadeia
      # vazia e erro de sintaxe do proprio shell.
      codigo=$(dbx_errors_codigo_saida "${DBX_HTTP_CLASSE:-erro_remoto}")
      return "$codigo"
    fi

    _dbx_cmd_analisar_corpo || return $?
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
    for ((indice = 0; indice < quantidade; indice++)); do
      _dbx_sync_entrada "$raiz" "$indice" completa "$lado"
    done

    _dbx_sync_pagina_seguinte "$anterior"
    estado=$?
    _dbx_cmd_encerrar_consulta
    [[ $estado -eq 1 ]] && break
    if [[ $estado -eq 2 || $pagina -ge $DBX_SYNC_TETO_PAGINAS ]]; then
      DBX_SYNC_CURSOR_NOVO=''
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_SYNC_MOTIVO="enumeracao remota nao terminou: cursor repetido ou mais de $DBX_SYNC_TETO_PAGINAS paginas"
      return "$(dbx_errors_codigo_saida erro_remoto)"
    fi
    anterior=$DBX_SYNC_CURSOR_NOVO
    pagina=$((pagina + 1))
    dbx_progress_mensagem "[sync] consultando remoto: obtendo proxima pagina (pagina $pagina)..."
    _dbx_sync_corpo_continue "$anterior"
    url='https://api.dropboxapi.com/2/files/list_folder/continue'
  done
  return 0
}

# dbx_sync_listar_delta <raiz_api> <cursor> [lado] — o incremental (RF-112(a)):
# `continue` a partir do cursor gravado, pagina por pagina, aplicando o delta
# a tabela ja carregada do retrato.
#
#   0  delta aplicado; cursor da ultima pagina em DBX_SYNC_CURSOR_NOVO
#   1  abandonar o incremental (motivo em DBX_SYNC_CURSOR_MOTIVO: `reset`,
#      `descartado` ou `transitorio`): quem chama faz a varredura completa na
#      MESMA execucao (RF-113(a)(b)); nunca falha por causa do estado
#   2  falha que a varredura completa tambem teria: autenticacao e permissao
#      (401, 403) mantem a classe (DBX_HTTP_CLASSE), RF-113(b)
dbx_sync_listar_delta() {
  [[ $# -ge 2 && $# -le 3 ]] || return "$DBX_SYNC_ERRO_USO"
  local raiz=$1 anterior=$2 lado=${3:-} estado quantidade indice pagina=0
  DBX_SYNC_CURSOR_MOTIVO=''
  DBX_SYNC_DELTA_MUDANCAS=0
  DBX_SYNC_DELTA_APAGADAS=()
  DBX_SYNC_CURSOR_NOVO=''
  while :; do
    pagina=$((pagina + 1))
    if [[ $pagina -gt $DBX_SYNC_TETO_PAGINAS ]]; then
      DBX_SYNC_CURSOR_MOTIVO='descartado'
      return 1
    fi
    _dbx_sync_corpo_continue "$anterior"
    dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/list_folder/continue' "$_DBX_SYNC_CORPO" sim
    estado=$?
    _DBX_SYNC_CORPO=''
    if [[ $estado -ne 0 ]]; then
      case ${DBX_HTTP_CODIGO:-0} in
        401 | 403)
          DBX_SYNC_MOTIVO="consulta de mudancas recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
          return 2
          ;;
        409)
          # `reset`: cursor invalidado ou expirado (Context7, DIV-219). Outro
          # 409 (`path`: a raiz do cursor sumiu) tambem descarta.
          DBX_SYNC_CURSOR_MOTIVO='descartado'
          [[ ${DBX_HTTP_RESUMO_DO_SERVICO:-} == reset* || ${DBX_HTTP_RESUMO_DE_ERRO:-} == reset* ]] &&
            DBX_SYNC_CURSOR_MOTIVO='reset'
          ;;
        4[0-9][0-9]) DBX_SYNC_CURSOR_MOTIVO='descartado' ;;
        # 429, 5xx e rede depois das retentativas de lib/http.
        *) DBX_SYNC_CURSOR_MOTIVO='transitorio' ;;
      esac
      [[ ${DBX_HTTP_CODIGO:-0} == 429 ]] && DBX_SYNC_CURSOR_MOTIVO='transitorio'
      return 1
    fi
    # Resposta malformada ou acima do teto do analisador: abandona sem emitir
    # nada (a varredura completa e a resposta, nao uma falha).
    if ! dbx_json_contexto comando || ! dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null ||
      [[ ${DBX_JSON_DUPLICADAS:-0} -ne 0 ]]; then
      _dbx_cmd_encerrar_consulta
      DBX_SYNC_CURSOR_MOTIVO='descartado'
      return 1
    fi
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=-1
    if [[ $quantidade -lt 0 ]]; then
      _dbx_cmd_encerrar_consulta
      DBX_SYNC_CURSOR_MOTIVO='descartado'
      return 1
    fi
    for ((indice = 0; indice < quantidade; indice++)); do
      if ! _dbx_sync_entrada "$raiz" "$indice" delta "$lado"; then
        _dbx_cmd_encerrar_consulta
        DBX_SYNC_CURSOR_MOTIVO='descartado'
        return 1
      fi
    done
    _dbx_sync_pagina_seguinte "$anterior"
    estado=$?
    _dbx_cmd_encerrar_consulta
    if [[ $estado -eq 2 ]]; then
      DBX_SYNC_CURSOR_NOVO=''
      DBX_SYNC_CURSOR_MOTIVO='descartado'
      return 1
    fi
    [[ $estado -eq 1 ]] && break
    anterior=$DBX_SYNC_CURSOR_NOVO
  done
  # shellcheck disable=SC2154  # constante de lib/state, carregada por commands/sync
  if [[ ${#DBX_SYNC_CURSOR_NOVO} -gt 8192 || ! $DBX_SYNC_CURSOR_NOVO =~ $DBX_STATE_CURSOR_RE_CURSOR ]]; then
    DBX_SYNC_CURSOR_NOVO=''
    DBX_SYNC_CURSOR_MOTIVO='descartado'
    return 1
  fi
  _dbx_sync_ids_unicos || {
    DBX_SYNC_CURSOR_MOTIVO='descartado'
    return 1
  }
  return 0
}

# _dbx_sync_ids_unicos — 0 quando nenhum `id` de arquivo aparece em dois
# caminhos da tabela reconstruida (RF-112(e), RF-115(g)): movimento cujo
# `deleted` do antigo nao veio, ou duas `file` para a mesma chave.
_dbx_sync_ids_unicos() {
  local pl registro id
  local -A vistos=()
  for pl in "${!DBX_SYNC_TAB[@]}"; do
    registro=${DBX_SYNC_TAB[$pl]}
    [[ $registro == f$'\t'* ]] || continue
    id=${registro#*$'\t'}
    id=${id%%$'\t'*}
    [[ -z ${vistos[$id]+definido} ]] || return 1
    vistos[$id]=1
  done
  return 0
}

# dbx_sync_retrato_entrada <registro> <path_lower> <tag> <id> <path_display>
#
# Funcao de entrada do leitor de `cursor-*` (lib/state): todo caminho do
# retrato passa pelo MESMO confinamento da listagem viva (C4, RF-50): o estado
# nao introduz caminho que a resposta do servico nao introduziria. `path_lower`
# repetido descarta. Precisa de DBX_SYNC_RETRATO_RAIZ.
DBX_SYNC_RETRATO_RAIZ=''
dbx_sync_retrato_entrada() {
  local registro=$1 baixo=$2
  [[ -z ${DBX_SYNC_TAB[$baixo]+definido} ]] || return 1
  _dbx_sync_relativo_seguro "$DBX_SYNC_RETRATO_RAIZ" "$5" || return 1
  _dbx_sync_relativo_seguro "$DBX_SYNC_RETRATO_RAIZ" "$baixo" || return 1
  _dbx_sync_tab_inserir "$baixo" "$registro"
  return 0
}

# dbx_sync_tabela_contar — entradas da tabela em DBX_SYNC_LIDO.
dbx_sync_tabela_contar() {
  # shellcheck disable=SC2034  # canal publico
  DBX_SYNC_LIDO=${#DBX_SYNC_TAB[@]}
}

# dbx_sync_tabela_arquivos — arquivos da tabela em DBX_SYNC_LIDO.
dbx_sync_tabela_arquivos() {
  local pl total=0
  for pl in "${!DBX_SYNC_TAB[@]}"; do
    [[ ${DBX_SYNC_TAB[$pl]} == f$'\t'* ]] && total=$((total + 1))
  done
  # shellcheck disable=SC2034  # canal publico
  DBX_SYNC_LIDO=$total
}

# dbx_sync_tabela_datada — 0 quando nenhum filtro de DATA esta ativo ou todo
# arquivo da tabela tem a data remota; senao o incremental nao pode aplicar o
# filtro as entradas vindas do retrato e volta a varredura completa.
dbx_sync_tabela_datada() {
  local pl registro
  [[ -n ${DBX_FILTRO_DESDE:-}${DBX_FILTRO_ATE:-} ]] || return 0
  for pl in "${!DBX_SYNC_TAB[@]}"; do
    registro=${DBX_SYNC_TAB[$pl]}
    [[ $registro == f$'\t'* ]] || continue
    registro=${registro#*$'\t'*$'\t'*$'\t'*$'\t'*$'\t'}
    [[ ${registro%%$'\t'*} != '-' ]] || return 1
  done
  return 0
}

# dbx_sync_tabela_corpo — o corpo do retrato, na ordem da tabela, dois campos
# NUL por entrada (funcao de corpo de `dbx_state_cursor_gravar`).
dbx_sync_tabela_corpo() {
  local pl
  for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
    [[ -n ${DBX_SYNC_TAB[$pl]+definido} ]] || continue
    printf '%s\0%s\0' "${DBX_SYNC_TAB[$pl]}" "$pl"
  done
}

# dbx_sync_tabela_emitir <raiz_api> <arquivo> [arquivo_de_revs] [lado]
#
# Emite a tabela no formato de sempre (`resumo<TAB>tamanho<TAB>caminho\0`, e o
# `rev` em arquivo proprio), aplicando o escopo filtrado DEPOIS da montagem
# (DIV-g): pasta excluida conta 1 (RF-80(i)); data (`server_modified`, DIV-84) e
# tamanho so na origem (RF-81). Em DBX_SYNC_REMOTOS_ANTES, os arquivos antes de
# qualquer filtro. E o MESMO codigo na varredura completa e na incremental.
dbx_sync_tabela_emitir() {
  [[ $# -ge 2 && $# -le 4 ]] || return "$DBX_SYNC_ERRO_USO"
  local raiz=$1 destino=$2 revs=${3:-} lado=${4:-}
  local pl registro tag id rev resumo tamanho carimbo exibido caminho total=0
  DBX_SYNC_REMOTOS_ANTES=0
  : >"$destino"
  [[ -n $revs ]] && : >"$revs"
  for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
    [[ -n ${DBX_SYNC_TAB[$pl]+definido} ]] || continue
    registro=${DBX_SYNC_TAB[$pl]}
    tag=${registro%%$'\t'*} registro=${registro#*$'\t'}
    id=${registro%%$'\t'*} registro=${registro#*$'\t'}
    rev=${registro%%$'\t'*} registro=${registro#*$'\t'}
    resumo=${registro%%$'\t'*} registro=${registro#*$'\t'}
    tamanho=${registro%%$'\t'*} registro=${registro#*$'\t'}
    carimbo=${registro%%$'\t'*}
    exibido=${registro#*$'\t'}
    [[ $rev == '-' ]] && rev=''
    [[ $resumo == '-' ]] && resumo=''
    [[ $carimbo == '-' ]] && carimbo=''
    # Pasta nao e transferivel e nao entra na tabela de transferencia. Ver o
    # limite declarado no topo. A pasta EXCLUIDA conta 1 (RF-80(i)).
    if [[ $tag == 'd' ]]; then
      if [[ -n $lado ]] && dbx_filtro_ativo && dbx_sync_relativo "$raiz" "$exibido"; then
        dbx_sync_no_escopo "$lado" "$DBX_SYNC_LIDO" pasta || :
      fi
      continue
    fi
    dbx_sync_relativo "$raiz" "$exibido" || continue
    caminho=$DBX_SYNC_LIDO
    DBX_SYNC_REMOTOS_ANTES=$((DBX_SYNC_REMOTOS_ANTES + 1))
    if [[ -n $lado ]]; then
      dbx_sync_no_escopo "$lado" "$caminho" arquivo || continue
    fi
    if [[ $lado == 'origem' ]] && dbx_filtro_meta_ativo; then
      if ! dbx_filtro_meta_passa "$carimbo" "$tamanho"; then
        _dbx_sync_contar_filtrado "$caminho"
        continue
      fi
    fi
    printf '%s\t%s\t%s\0' "$resumo" "$tamanho" "$caminho" >>"$destino"
    [[ -n $revs && -n $rev ]] && printf '%s\t%s\0' "$rev" "$caminho" >>"$revs"
    total=$((total + 1))
    dbx_progress_mensagem "[sync] consultando remoto ($total): $caminho"
  done
  return 0
}

# dbx_sync_confirmar_exclusoes <raiz_api> <vetor_de_candidatas>
#
# RF-114 (decisao do solicitante; C5): no modo incremental, TODA candidata a
# exclusao — `deleted` do delta ou ausencia no retrato — so vale depois de o
# servidor confirmar, NESTA execucao e ANTES do plano, que o caminho nao existe.
# A candidata sob uma raiz apagada do delta e coberta pela confirmacao da raiz
# (RF-114(c)); as demais, uma a uma. Mais de 50 alvos: nenhuma chamada, e a
# varredura completa (DIV-209).
#
# So `path/not_found` do `get_metadata` confirma (P2: e o servidor que resolve o
# caminho, sem caixa). Qualquer metadado presente e CONTRADICAO e nunca apaga;
# o `id` e o `rev` do retrato so classificam o aviso (P2).
#
#   0  todas confirmadas (quantas em DBX_SYNC_CONFIRMADAS)
#   1  contradicao, resposta duvidosa ou excesso: varredura completa (motivo em
#      DBX_SYNC_CURSOR_MOTIVO, classificacao em DBX_SYNC_CONTRADICAO)
#   2  falha de transporte, limite de taxa, 5xx, autenticacao: a fase de
#      enumeracao falha com a classe de hoje (DBX_HTTP_CLASSE), nenhum plano
dbx_sync_confirmar_exclusoes() {
  [[ $# -eq 2 ]] || return "$DBX_SYNC_ERRO_USO"
  local raiz=$1 candidata alvo pl raiz_apagada relativa registro id_antigo id_novo
  local -n _cf_candidatas=$2
  local -A raizes=() alvos=() do_retrato=()
  local -a ordem=()
  DBX_SYNC_CONFIRMADAS=0
  DBX_SYNC_CONTRADICAO=''
  DBX_SYNC_CURSOR_MOTIVO=''
  # Raizes apagadas do delta, pela chave sem caixa do caminho relativo. A que
  # voltou a existir no mapa final (apagada e recriada) nao cobre ninguem.
  for pl in "${!DBX_SYNC_DELTA_APAGADAS[@]}"; do
    [[ -n ${DBX_SYNC_TAB[$pl]+definido} ]] && continue
    registro=${DBX_SYNC_DELTA_APAGADAS[$pl]}
    dbx_sync_relativo "$raiz" "${registro##*$'\t'}" || continue
    relativa=$DBX_SYNC_LIDO
    _dbx_sync_chave "$relativa"
    raizes[$DBX_SYNC_CHAVE]=$relativa
    do_retrato[$relativa]=$registro
  done
  for candidata in ${_cf_candidatas[@]+"${_cf_candidatas[@]}"}; do
    alvo=$candidata
    _dbx_sync_chave "$candidata"
    pl=$DBX_SYNC_CHAVE
    for raiz_apagada in "${!raizes[@]}"; do
      if [[ $pl == "$raiz_apagada" || $pl == "$raiz_apagada/"* ]]; then
        alvo=${raizes[$raiz_apagada]}
        break
      fi
    done
    if [[ -z ${alvos[$alvo]+definido} ]]; then
      alvos[$alvo]=1
      ordem+=("$alvo")
    fi
  done
  if [[ ${#ordem[@]} -gt $DBX_SYNC_TETO_CONFIRMACOES ]]; then
    DBX_SYNC_CURSOR_MOTIVO='descartado'
    DBX_SYNC_CONTRADICAO="mais de $DBX_SYNC_TETO_CONFIRMACOES exclusoes a confirmar"
    return 1
  fi
  for alvo in ${ordem[@]+"${ordem[@]}"}; do
    dbx_json_escapar_cadeia "$raiz/$alvo"
    dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/get_metadata' \
      "{\"path\":\"$DBX_JSON_ESCAPADO\"}" sim
    local estado=$?
    # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
    DBX_JSON_ESCAPADO=''
    if [[ $estado -eq 0 ]]; then
      # Presenca NUNCA produz exclusao. O `id` so classifica o aviso.
      id_novo=''
      dbx_cmd_ler_corpo_silencioso id && id_novo=${DBX_CMD_CAMPOS[0]}
      registro=${do_retrato[$alvo]:-}
      id_antigo=''
      if [[ -n $registro ]]; then
        id_antigo=${registro#*$'\t'}
        id_antigo=${id_antigo%%$'\t'*}
      fi
      DBX_SYNC_CONTRADICAO='o item ainda existe no servidor'
      [[ -n $id_antigo && -n $id_novo && $id_novo != "$id_antigo" ]] &&
        DBX_SYNC_CONTRADICAO='o item foi recriado no servidor com outro id'
      DBX_SYNC_CURSOR_MOTIVO='contradicao'
      return 1
    fi
    case ${DBX_HTTP_CODIGO:-0} in
      409)
        if [[ ${DBX_HTTP_RESUMO_DO_SERVICO:-} == path/not_found* ]]; then
          DBX_SYNC_CONFIRMADAS=$((DBX_SYNC_CONFIRMADAS + 1))
          continue
        fi
        # Outro 409 nao prova a ausencia: em duvida, varredura completa.
        DBX_SYNC_CONTRADICAO='o servidor nao confirmou a exclusao'
        DBX_SYNC_CURSOR_MOTIVO='contradicao'
        return 1
        ;;
      400 | 404)
        # shellcheck disable=SC2034  # canais publicos, lidos por commands/sync
        DBX_SYNC_CONTRADICAO='o servidor nao confirmou a exclusao'
        # shellcheck disable=SC2034
        DBX_SYNC_CURSOR_MOTIVO='contradicao'
        return 1
        ;;
    esac
    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_SYNC_MOTIVO="confirmacao de exclusao no servidor falhou: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return 2
  done
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

# dbx_sync_ler_revs <arquivo> <nome_do_mapa> — `rev` por caminho remoto.
dbx_sync_ler_revs() {
  [[ $# -eq 2 ]] || return "$DBX_SYNC_ERRO_USO"
  local arquivo=$1
  local -n _revs=$2
  local registro
  _revs=()
  [[ -r $arquivo ]] || return 0
  while IFS= read -r -d '' registro; do
    [[ $registro == *$'\t'* ]] || continue
    _revs["${registro#*$'\t'}"]=${registro%%$'\t'*}
  done <"$arquivo"
  return 0
}

# dbx_sync_planejar <vetor_origem> <mapa_origem> <vetor_destino> <mapa_destino>
#
# Aplica a tabela de 5.8.2. Nao emite escrita alguma: separar decidir de executar
# e o que permite a `RF-44` imprimir o plano completo e a `RF-41(d)` anunciar
# toda exclusao ANTES da primeira delas.
#
# Os lados sao casados pela chave sem caixa (RF-54): um par que so difere na
# caixa e um arquivo so, decidido pelo resumo, e nunca vira "transferir" de um
# lado e "apagar" do outro.
dbx_sync_planejar() {
  [[ $# -eq 4 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _ordem_o=$1 _mapa_o=$2 _ordem_d=$3 _mapa_d=$4
  local caminho par resumo_o resumo_d
  local -A _destino_por_chave=() _chaves_da_origem=()

  DBX_SYNC_TRANSFERIR=()
  DBX_SYNC_APAGAR=()
  DBX_SYNC_IDENTICOS=()
  DBX_SYNC_ALVO=()

  for caminho in ${_ordem_d[@]+"${_ordem_d[@]}"}; do
    _dbx_sync_chave "$caminho"
    _destino_por_chave[$DBX_SYNC_CHAVE]=$caminho
  done

  for caminho in ${_ordem_o[@]+"${_ordem_o[@]}"}; do
    resumo_o=${_mapa_o[$caminho]:-}
    _dbx_sync_chave "$caminho"
    _chaves_da_origem[$DBX_SYNC_CHAVE]=1
    if [[ -z ${_destino_por_chave[$DBX_SYNC_CHAVE]+definido} ]]; then
      DBX_SYNC_ALVO[$caminho]=$caminho
      DBX_SYNC_TRANSFERIR+=("$caminho")
      continue
    fi
    par=${_destino_por_chave[$DBX_SYNC_CHAVE]}
    # shellcheck disable=SC2034  # canal publico, lido por commands/sync
    DBX_SYNC_ALVO[$caminho]=$par
    resumo_d=${_mapa_d[$par]:-}
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
    _dbx_sync_chave "$caminho"
    [[ -z ${_chaves_da_origem[$DBX_SYNC_CHAVE]+definido} ]] && DBX_SYNC_APAGAR+=("$caminho")
  done
  return 0
}

# ---------------------------------------------------------------------------
# Comparacao do `verificar` (RF-65)
# ---------------------------------------------------------------------------

# Canais publicos de `dbx_sync_comparar`, paralelos e na ordem da chave sem
# caixa: caminho, estado (`igual`, `diferente`, `so_origem`, `so_destino`) e
# motivo (`conteudo` ou `tipo` no `diferente`; vazio nos demais).
declare -ga DBX_SYNC_COMPARADOS_CAMINHOS=()
declare -ga DBX_SYNC_COMPARADOS_ESTADOS=()
declare -ga DBX_SYNC_COMPARADOS_MOTIVOS=()
declare -ga DBX_SYNC_ORDEM=()

# _dbx_sync_pastas_de <caminho> <nome_do_mapa> — acrescenta ao mapa a chave de
# cada pasta que o caminho atravessa (`a/b/c` da `a` e `a/b`). A pasta existe
# para a comparacao so quando contem arquivo: e o mesmo limite do topo, so
# arquivos sao comparados.
_dbx_sync_pastas_de() {
  local caminho=$1 prefixo=''
  local -n _pastas=$2
  while [[ $caminho == */* ]]; do
    prefixo+=${prefixo:+/}${caminho%%/*}
    caminho=${caminho#*/}
    _dbx_sync_chave "$prefixo"
    # shellcheck disable=SC2004  # `_pastas` e nameref para mapa associativo:
    # o `$` e necessario, a chave e texto e nao expressao aritmetica.
    _pastas[$DBX_SYNC_CHAVE]=1
  done
}

# _dbx_sync_ordenar_por_chave <nome_do_vetor_de_chaves> — indices do vetor em
# DBX_SYNC_ORDEM, pela chave em bytes (`LC_ALL=C` local), de forma estavel.
#
# Intercalacao de baixo para cima, so com recursos do shell: `sort` seria um
# utilitario fora do preflight, e `[[ < ]]` sem localidade fixa compararia por
# colacao, que muda de maquina para maquina.
_dbx_sync_ordenar_por_chave() {
  local -n _chaves=$1
  { local LC_ALL=C; } 2>/dev/null
  local total=${#_chaves[@]} largura inicio meio fim a b k
  local -a ordem=() auxiliar=()
  for ((k = 0; k < total; k++)); do ordem[k]=$k; done
  for ((largura = 1; largura < total; largura *= 2)); do
    for ((inicio = 0; inicio < total; inicio += 2 * largura)); do
      meio=$((inicio + largura))
      ((meio > total)) && meio=$total
      fim=$((inicio + 2 * largura))
      ((fim > total)) && fim=$total
      a=$inicio b=$meio k=$inicio
      while ((a < meio && b < fim)); do
        if [[ ${_chaves[ordem[b]]} < ${_chaves[ordem[a]]} ]]; then
          auxiliar[k]=${ordem[b]} b=$((b + 1))
        else
          auxiliar[k]=${ordem[a]} a=$((a + 1))
        fi
        k=$((k + 1))
      done
      while ((a < meio)); do auxiliar[k]=${ordem[a]} a=$((a + 1)) k=$((k + 1)); done
      while ((b < fim)); do auxiliar[k]=${ordem[b]} b=$((b + 1)) k=$((k + 1)); done
    done
    ordem=("${auxiliar[@]}")
  done
  DBX_SYNC_ORDEM=(${ordem[@]+"${ordem[@]}"})
}

# dbx_sync_ordem_sem_caixa <nome_do_vetor_de_caminhos> — indices do vetor em
# DBX_SYNC_ORDEM, pela MESMA chave sem caixa do `verificar` (RF-54). Ponto de
# uso fora daqui: a ordem dos itens da restauracao de pasta (RF-74(d)).
dbx_sync_ordem_sem_caixa() {
  [[ $# -eq 1 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _osc_caminhos=$1
  local -a chaves=()
  local caminho
  for caminho in ${_osc_caminhos[@]+"${_osc_caminhos[@]}"}; do
    _dbx_sync_chave "$caminho"
    chaves+=("$DBX_SYNC_CHAVE")
  done
  _dbx_sync_ordenar_por_chave chaves
}

# dbx_sync_comparar <vetor_origem> <mapa_origem> <vetor_destino> <mapa_destino>
#
# A MESMA tabela do `sync` (`dbx_sync_planejar`), lida como relatorio: o que o
# `sync` transferiria e `diferente` (o par existe) ou `so_origem`; o que ele
# omitiria e `igual`; o que ele apagaria com espelhamento e `so_destino`. Usar o
# planejador, e nao uma segunda comparacao, e o que garante que `verificar` e
# `sync --dry-run` enxerguem a mesma arvore (RF-65(a)).
#
# Arquivo num lado e pasta no outro e `diferente` com motivo `tipo`; o arquivo
# de dentro da pasta continua listado no proprio estado.
dbx_sync_comparar() {
  [[ $# -eq 4 ]] || return "$DBX_SYNC_ERRO_USO"
  local -n _cmp_ordem_o=$1 _cmp_ordem_d=$3 _cmp_mapa_d=$4
  local caminho par indice
  local -A _cmp_pastas_o=() _cmp_pastas_d=()
  local -a caminhos=() estados=() motivos=() chaves=()

  dbx_sync_planejar "$@" || return $?
  for caminho in ${_cmp_ordem_o[@]+"${_cmp_ordem_o[@]}"}; do
    _dbx_sync_pastas_de "$caminho" _cmp_pastas_o
  done
  for caminho in ${_cmp_ordem_d[@]+"${_cmp_ordem_d[@]}"}; do
    _dbx_sync_pastas_de "$caminho" _cmp_pastas_d
  done

  for caminho in ${DBX_SYNC_IDENTICOS[@]+"${DBX_SYNC_IDENTICOS[@]}"}; do
    caminhos+=("$caminho") estados+=(igual) motivos+=('')
  done
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    par=${DBX_SYNC_ALVO[$caminho]:-$caminho}
    _dbx_sync_chave "$caminho"
    if [[ -n ${_cmp_mapa_d[$par]+definido} ]]; then
      caminhos+=("$caminho") estados+=(diferente) motivos+=(conteudo)
    elif [[ -n ${_cmp_pastas_d[$DBX_SYNC_CHAVE]+definido} ]]; then
      caminhos+=("$caminho") estados+=(diferente) motivos+=(tipo)
    else
      caminhos+=("$caminho") estados+=(so_origem) motivos+=('')
    fi
  done
  for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    _dbx_sync_chave "$caminho"
    if [[ -n ${_cmp_pastas_o[$DBX_SYNC_CHAVE]+definido} ]]; then
      caminhos+=("$caminho") estados+=(diferente) motivos+=(tipo)
    else
      caminhos+=("$caminho") estados+=(so_destino) motivos+=('')
    fi
  done

  for caminho in ${caminhos[@]+"${caminhos[@]}"}; do
    _dbx_sync_chave "$caminho"
    chaves+=("$DBX_SYNC_CHAVE")
  done
  _dbx_sync_ordenar_por_chave chaves
  DBX_SYNC_COMPARADOS_CAMINHOS=()
  DBX_SYNC_COMPARADOS_ESTADOS=()
  DBX_SYNC_COMPARADOS_MOTIVOS=()
  for indice in ${DBX_SYNC_ORDEM[@]+"${DBX_SYNC_ORDEM[@]}"}; do
    DBX_SYNC_COMPARADOS_CAMINHOS+=("${caminhos[indice]}")
    DBX_SYNC_COMPARADOS_ESTADOS+=("${estados[indice]}")
    DBX_SYNC_COMPARADOS_MOTIVOS+=("${motivos[indice]}")
  done
  return 0
}
