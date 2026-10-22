#!/usr/bin/env bash
# lib/compartilhamento.sh — regras do link compartilhado (RF-85 a RF-89;
# DIV-104 a DIV-120; componente de DIV-117).
#
# Camada: dominio. Depende de lib/errors.sh, lib/path.sh, lib/json.sh (escape)
# e lib/filtro.sh (validacao de data, a mesma de `--modificado-ate` e de
# `restaurar --antes-de`). PURO: sem rede, sem disco e sem estado. Tudo o que
# decide ANTES da rede mora aqui — visibilidade, `--expira`, URL do
# `--revogar`, senha — junto com a montagem do corpo, a comparacao entre o
# estado efetivo e o pedido e o filtro de confinamento por `path_lower`.
#
# A SENHA (RF-86, DIV-110) passa por aqui so como argumento de funcao ou por
# NOME de variavel do chamador, nunca por canal publico: o escape de lib/json
# publica em DBX_JSON_ESCAPADO, que e esvaziado na mesma funcao. Nenhuma
# mensagem cita a senha nem trecho dela.
#
# DATAS sem utilitario `date` (RNF-02): o relogio e o `printf '%(...)T'` do
# proprio shell, em UTC por `TZ` local da funcao. Os carimbos tem formato fixo
# `AAAA-MM-DDTHH:MM:SSZ`, e por isso a comparacao e a de texto sob `LC_ALL=C`.

[[ -n ${DBX_COMPARTILHAMENTO_CARREGADO:-} ]] && return 0
DBX_COMPARTILHAMENTO_CARREGADO=1

_dbx_compartilhamento_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_compartilhamento_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_compartilhamento_diretorio=.
_dbx_compartilhamento_diretorio=$(cd -P -- "$_dbx_compartilhamento_diretorio" && pwd -P)
# shellcheck source=lib/filtro.sh
. "$_dbx_compartilhamento_diretorio/filtro.sh"
unset _dbx_compartilhamento_diretorio

DBX_COMPARTILHAMENTO_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_COMPARTILHAMENTO_ERRO_USO

# Validade do link temporario (RF-84(f)): quatro horas, fixada pelo servico.
# shellcheck disable=SC2034  # lida por commands/link_temporario
readonly DBX_COMPARTILHAMENTO_VALIDADE_TEMPORARIO=14400
# RF-85(e): margem minima no futuro, tetos das duracoes, teto da senha e da URL.
readonly DBX_COMPARTILHAMENTO_MARGEM_S=60
readonly DBX_COMPARTILHAMENTO_HORAS_MAXIMAS=8760
readonly DBX_COMPARTILHAMENTO_DIAS_MAXIMOS=3650
readonly DBX_COMPARTILHAMENTO_SENHA_MAXIMA=1024
readonly DBX_COMPARTILHAMENTO_URL_MAXIMA=2048
# RF-89(b): esquema, host exato e prefixo do caminho do link compartilhado.
readonly DBX_COMPARTILHAMENTO_FORMATO_URL='^https://(www[.])?dropbox[.]com/(s|sh|scl/fi|scl/fo)/[^/]'

# Canais publicos, lidos pelos comandos.
# shellcheck disable=SC2034
DBX_COMPARTILHAMENTO_MOTIVO=''
# shellcheck disable=SC2034
DBX_COMPARTILHAMENTO_EXPIRA=''
# shellcheck disable=SC2034
DBX_COMPARTILHAMENTO_CARIMBO=''
# shellcheck disable=SC2034
DBX_COMPARTILHAMENTO_ESPERADA=''
# shellcheck disable=SC2034
DBX_COMPARTILHAMENTO_EXPOSICAO=''

# dbx_compartilhamento_carimbo <segundos_desde_1970> — UTC em
# DBX_COMPARTILHAMENTO_CARIMBO, pelo relogio do proprio shell.
dbx_compartilhamento_carimbo() {
  local TZ=UTC
  DBX_COMPARTILHAMENTO_CARIMBO=''
  [[ ${1-} =~ ^[0-9]{1,12}$ ]] || return 1
  printf -v DBX_COMPARTILHAMENTO_CARIMBO '%(%Y-%m-%dT%H:%M:%SZ)T' "$((10#$1))"
}

# dbx_compartilhamento_agora — segundos desde 1970 em DBX_COMPARTILHAMENTO_AGORA.
DBX_COMPARTILHAMENTO_AGORA=''
dbx_compartilhamento_agora() {
  printf -v DBX_COMPARTILHAMENTO_AGORA '%(%s)T' -1
}

# dbx_compartilhamento_validar_expira <opcao> <valor> — RF-85(e), DIV-113.
#
# `AAAA-MM-DD` (fim do dia UTC, como RF-73(d)), `AAAA-MM-DDTHH:MM:SSZ` ou
# duracao `<N>h` (1..8760) / `<N>d` (1..3650), N sem zero a esquerda, somada ao
# relogio em UTC. O resultado precisa ser posterior a agora mais 60 s. Carimbo
# normalizado em DBX_COMPARTILHAMENTO_EXPIRA; recusa com uso invalido.
dbx_compartilhamento_validar_expira() {
  local opcao=$1 valor=${2-} citado
  local LC_ALL=C
  DBX_COMPARTILHAMENTO_EXPIRA=''
  DBX_COMPARTILHAMENTO_MOTIVO=''
  DBX_COMPARTILHAMENTO_CARIMBO=''
  dbx_compartilhamento_agora
  if [[ $valor =~ ^([1-9][0-9]{0,3})([hd])$ ]]; then
    local quantidade=$((10#${BASH_REMATCH[1]})) unidade=${BASH_REMATCH[2]}
    if [[ $unidade == 'h' ]] && ((quantidade <= DBX_COMPARTILHAMENTO_HORAS_MAXIMAS)); then
      dbx_compartilhamento_carimbo $((DBX_COMPARTILHAMENTO_AGORA + quantidade * 3600))
    elif [[ $unidade == 'd' ]] && ((quantidade <= DBX_COMPARTILHAMENTO_DIAS_MAXIMOS)); then
      dbx_compartilhamento_carimbo $((DBX_COMPARTILHAMENTO_AGORA + quantidade * 86400))
    fi
  elif [[ $valor =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)?$ ]] &&
    dbx_filtro_validar_data "$opcao" "$valor" ate; then
    DBX_COMPARTILHAMENTO_CARIMBO=$DBX_FILTRO_DATA
  else
    DBX_COMPARTILHAMENTO_CARIMBO=''
  fi
  if [[ -z $DBX_COMPARTILHAMENTO_CARIMBO ]]; then
    citado=${valor:0:64}
    [[ $citado == *[$'\001'-$'\037\177']* ]] && printf -v citado '%q' "$citado"
    DBX_COMPARTILHAMENTO_MOTIVO="valor invalido para $opcao: [$citado]; use AAAA-MM-DD (fim do dia UTC), AAAA-MM-DDTHH:MM:SSZ (UTC) ou duracao <N>h (1 a $DBX_COMPARTILHAMENTO_HORAS_MAXIMAS) ou <N>d (1 a $DBX_COMPARTILHAMENTO_DIAS_MAXIMOS)"
    return "$DBX_COMPARTILHAMENTO_ERRO_USO"
  fi
  local carimbo=$DBX_COMPARTILHAMENTO_CARIMBO
  dbx_compartilhamento_carimbo $((DBX_COMPARTILHAMENTO_AGORA + DBX_COMPARTILHAMENTO_MARGEM_S))
  if [[ ! $carimbo > $DBX_COMPARTILHAMENTO_CARIMBO ]]; then
    DBX_COMPARTILHAMENTO_MOTIVO="a expiracao precisa estar no futuro: $opcao $carimbo nao e posterior a agora mais ${DBX_COMPARTILHAMENTO_MARGEM_S} s ($DBX_COMPARTILHAMENTO_CARIMBO)"
    return "$DBX_COMPARTILHAMENTO_ERRO_USO"
  fi
  # shellcheck disable=SC2034  # canal publico, lido por commands/compartilhar
  DBX_COMPARTILHAMENTO_EXPIRA=$carimbo
  return 0
}

# _dbx_compartilhamento_utf8 <texto> — 0 quando os bytes sao UTF-8 valido
# (sem sobrelongo nem substituto), byte a byte sob `LC_ALL=C`. O texto ja tem
# no maximo 1024 bytes quando chega aqui.
_dbx_compartilhamento_utf8() {
  local LC_ALL=C
  local texto=$1 indice=0 total byte falta=0 minimo=0 maximo=0
  total=${#texto}
  while ((indice < total)); do
    printf -v byte '%d' "'${texto:indice:1}"
    ((byte < 0)) && byte=$((byte + 256))
    if ((falta > 0)); then
      ((byte >= minimo && byte <= maximo)) || return 1
      minimo=128 maximo=191 falta=$((falta - 1))
    elif ((byte < 128)); then
      :
    elif ((byte >= 194 && byte <= 223)); then
      falta=1 minimo=128 maximo=191
    elif ((byte == 224)); then
      falta=2 minimo=160 maximo=191
    elif ((byte == 237)); then
      falta=2 minimo=128 maximo=159
    elif ((byte >= 225 && byte <= 239)); then
      falta=2 minimo=128 maximo=191
    elif ((byte == 240)); then
      falta=3 minimo=144 maximo=191
    elif ((byte >= 241 && byte <= 243)); then
      falta=3 minimo=128 maximo=191
    elif ((byte == 244)); then
      falta=3 minimo=128 maximo=143
    else
      return 1
    fi
    indice=$((indice + 1))
  done
  ((falta == 0))
}

# dbx_compartilhamento_validar_senha <senha> — RF-86(d), DIV-109. Vazia, com
# byte de controle (inclusive `\r` de fim de linha CRLF, sem remocao
# silenciosa), acima de 1024 bytes ou fora do UTF-8: uso invalido. O motivo
# nunca cita a senha.
dbx_compartilhamento_validar_senha() {
  local LC_ALL=C
  local senha=${1-}
  DBX_COMPARTILHAMENTO_MOTIVO=''
  if [[ -z $senha ]]; then
    DBX_COMPARTILHAMENTO_MOTIVO='senha vazia recusada'
  elif [[ $senha == *[$'\001'-$'\037\177']* ]]; then
    DBX_COMPARTILHAMENTO_MOTIVO='a senha contem caractere de controle (fim de linha CRLF?); nada foi enviado'
  elif ((${#senha} > DBX_COMPARTILHAMENTO_SENHA_MAXIMA)); then
    DBX_COMPARTILHAMENTO_MOTIVO="a senha excede $DBX_COMPARTILHAMENTO_SENHA_MAXIMA bytes"
  elif ! _dbx_compartilhamento_utf8 "$senha"; then
    DBX_COMPARTILHAMENTO_MOTIVO='a senha nao e texto UTF-8 valido'
  fi
  senha=''
  [[ -z $DBX_COMPARTILHAMENTO_MOTIVO ]] || return "$DBX_COMPARTILHAMENTO_ERRO_USO"
  return 0
}

# dbx_compartilhamento_validar_url <url> — RF-89(b), DIV-114: `https`, host
# EXATAMENTE `www.dropbox.com` ou `dropbox.com` (sem porta nem `@`), caminho
# iniciado por `/s/`, `/sh/`, `/scl/fi/` ou `/scl/fo/`, sem espaco nem byte de
# controle, ate 2048 bytes. O motivo cita so esquema e host.
dbx_compartilhamento_validar_url() {
  local LC_ALL=C
  local url=${1-} esquema host
  DBX_COMPARTILHAMENTO_MOTIVO=''
  if [[ ${#url} -le $DBX_COMPARTILHAMENTO_URL_MAXIMA && $url != *[[:space:]]* &&
    $url != *[$'\001'-$'\037\177']* &&
    $url =~ $DBX_COMPARTILHAMENTO_FORMATO_URL ]]; then
    return 0
  fi
  # QA-B5-04, QA-B5-11: so se cita o que casa o formato de esquema e de host;
  # credencial embutida (com `@`, `/`, espaco ou `%`) nunca sai.
  esquema=${url%%://*}
  [[ $esquema == "$url" ]] && esquema=''
  host=${url#*://}
  [[ $host == "$url" ]] && host=''
  local credencial=''
  [[ $url == *://*@* ]] && credencial=', com credencial embutida (omitida)'
  host=${host%%/*}
  [[ $esquema =~ ^[a-z]{1,16}$ ]] || esquema='(omitido)'
  [[ ${#host} -le 255 && $host =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || host='(omitido)'
  if [[ $esquema == 'https' && ${host,,} == 'dl.dropboxusercontent.com' ]]; then
    DBX_COMPARTILHAMENTO_MOTIVO='link temporario nao pode ser revogado; ele expira em 4 horas'
  else
    DBX_COMPARTILHAMENTO_MOTIVO="url de link compartilhado invalida (esquema [$esquema], host [$host]$credencial); use o link https de www.dropbox.com com caminho iniciado por s, sh, scl/fi ou scl/fo, sem espaco, ate $DBX_COMPARTILHAMENTO_URL_MAXIMA bytes"
  fi
  return "$DBX_COMPARTILHAMENTO_ERRO_USO"
}

# dbx_compartilhamento_visibilidade_esperada <publico|equipe|senha> — valor de
# `link_permissions.resolved_visibility` (ResolvedVisibility, `sharing.stone`)
# que corresponde ao pedido, em DBX_COMPARTILHAMENTO_ESPERADA.
dbx_compartilhamento_visibilidade_esperada() {
  case ${1-} in
    publico) DBX_COMPARTILHAMENTO_ESPERADA='public' ;;
    equipe) DBX_COMPARTILHAMENTO_ESPERADA='team_only' ;;
    senha) DBX_COMPARTILHAMENTO_ESPERADA='password' ;;
    *)
      # shellcheck disable=SC2034  # canal publico, lido por commands/compartilhar
      DBX_COMPARTILHAMENTO_ESPERADA=''
      return "$DBX_COMPARTILHAMENTO_ERRO_USO"
      ;;
  esac
}

# dbx_compartilhamento_corpo <variavel_destino> <path|url> <alvo> <modo> <expira> [variavel_senha]
#
# Corpo de `create_shared_link_with_settings` (`path`) ou de
# `modify_shared_link_settings` (`url`), em DBX_... do chamador (por nome).
# RF-85(c), DIV-112: `--publico` -> `audience public`; `--equipe` -> `audience
# team`; `--senha` -> `audience public` + `require_password true` +
# `link_password`. `requested_visibility`, `audience: password`, `access` e
# `allow_download` nunca sao enviados. `expires` so quando pedido.
#
# A senha e lida pelo NOME da variavel do chamador e serializada pelo escape de
# lib/json; o canal de escape e esvaziado aqui (RF-86(e)).
dbx_compartilhamento_corpo() {
  local -n _dbx_cc_destino=$1
  local _dbx_cc_chave=$2 _dbx_cc_alvo=$3 _dbx_cc_modo=$4 _dbx_cc_expira=${5-} _dbx_cc_nome=${6-}
  local _dbx_cc_settings
  case $_dbx_cc_chave in path | url) ;; *) return "$DBX_COMPARTILHAMENTO_ERRO_USO" ;; esac
  case $_dbx_cc_modo in
    publico) _dbx_cc_settings='"audience":"public","require_password":false' ;;
    equipe) _dbx_cc_settings='"audience":"team","require_password":false' ;;
    senha)
      [[ $_dbx_cc_nome =~ ^[a-z_][a-z0-9_]*$ ]] || return "$DBX_COMPARTILHAMENTO_ERRO_USO"
      local -n _dbx_cc_senha=$_dbx_cc_nome
      dbx_json_escapar_cadeia "$_dbx_cc_senha"
      _dbx_cc_settings="\"audience\":\"public\",\"require_password\":true,\"link_password\":\"$DBX_JSON_ESCAPADO\""
      # shellcheck disable=SC2034  # canal publico de lib/json, esvaziado aqui
      DBX_JSON_ESCAPADO=''
      ;;
    *) return "$DBX_COMPARTILHAMENTO_ERRO_USO" ;;
  esac
  [[ -n $_dbx_cc_expira ]] && _dbx_cc_settings+=",\"expires\":\"$_dbx_cc_expira\""
  dbx_json_escapar_cadeia "$_dbx_cc_alvo"
  _dbx_cc_destino="{\"$_dbx_cc_chave\":\"$DBX_JSON_ESCAPADO\",\"settings\":{$_dbx_cc_settings}}"
  DBX_JSON_ESCAPADO=''
  _dbx_cc_settings=''
  return 0
}

# dbx_compartilhamento_corpo_simples <variavel_destino> <chave> <valor> — `{"<chave>":"<valor>"}`
# escapado: o `path` do link temporario e da listagem do alvo, a `url` da
# guarda e da revogacao. A chave e literal do chamador.
dbx_compartilhamento_corpo_simples() {
  local -n _dbx_cs_destino=$1
  [[ $2 =~ ^[a-z_]+$ ]] || return "$DBX_COMPARTILHAMENTO_ERRO_USO"
  dbx_json_escapar_cadeia "${3-}"
  _dbx_cs_destino="{\"$2\":\"$DBX_JSON_ESCAPADO\"}"
  DBX_JSON_ESCAPADO=''
  return 0
}

# dbx_compartilhamento_confinado <path_lower> <raiz> [pasta] — RF-88(c),
# RF-89(c), DIV-114, DIV-118: 0 so quando o caminho que a API devolveu esta
# PRESENTE, e absoluto e esta dentro da raiz (e, com <pasta>, dela), por
# componente, com a caixa dobrada so no ASCII. Ausente nunca e confinado,
# nem com a raiz `/` (falha fechada).
dbx_compartilhamento_confinado() {
  local caminho=${1-} raiz=${2:-/} pasta=${3-}
  [[ -n $caminho && $caminho == /* ]] || return 1
  dbx_path_remoto_confinar "$raiz" "$caminho" sim >/dev/null 2>&1 || return 1
  [[ -z $pasta ]] && return 0
  dbx_path_remoto_confinar "$pasta" "$caminho" sim >/dev/null 2>&1
}

# dbx_compartilhamento_mesmo_caminho <a> <b> — 0 quando sao o mesmo caminho com
# a caixa dobrada so no ASCII (RF-87(a)); fora do ASCII, igualdade exata.
dbx_compartilhamento_mesmo_caminho() {
  local LC_ALL=C
  local a=${1-} b=${2-}
  [[ -n $a && ${a,,} == "${b,,}" ]]
}

# _dbx_compartilhamento_abertura <visibilidade> — ordem de exposicao: quanto
# maior, mais gente alcanca o link.
_dbx_compartilhamento_abertura() {
  case ${1-} in
    public) _dbx_compartilhamento_nivel=4 ;;
    password) _dbx_compartilhamento_nivel=3 ;;
    team_only) _dbx_compartilhamento_nivel=2 ;;
    team_and_password | shared_folder_only) _dbx_compartilhamento_nivel=1 ;;
    *) _dbx_compartilhamento_nivel=0 ;;
  esac
}

# dbx_compartilhamento_exposicao <antes_vis> <antes_senha> <antes_expira> <depois_vis> <depois_senha> <depois_expira>
#
# RF-87(e): o que ficou MAIS exposto, em DBX_COMPARTILHAMENTO_EXPOSICAO
# (`campo antes -> depois`, separados por `; `), vazio quando nada abriu.
# Expiracao vazia e "nunca expira", a mais aberta.
dbx_compartilhamento_exposicao() {
  local LC_ALL=C
  local antes_vis=$1 antes_senha=$2 antes_expira=$3 depois_vis=$4 depois_senha=$5 depois_expira=$6
  local _dbx_compartilhamento_nivel nivel_antes texto=''
  _dbx_compartilhamento_abertura "$antes_vis"
  nivel_antes=$_dbx_compartilhamento_nivel
  _dbx_compartilhamento_abertura "$depois_vis"
  ((_dbx_compartilhamento_nivel > nivel_antes)) && texto+="visibilidade $antes_vis -> $depois_vis"
  [[ $antes_senha == 'sim' && $depois_senha == 'nao' ]] && texto+="${texto:+; }senha sim -> nao"
  if [[ -n $antes_expira ]] && [[ -z $depois_expira || $depois_expira > $antes_expira ]]; then
    texto+="${texto:+; }expira $antes_expira -> ${depois_expira:-nunca}"
  fi
  # shellcheck disable=SC2034  # canal publico, lido por commands/compartilhar
  DBX_COMPARTILHAMENTO_EXPOSICAO=$texto
}
