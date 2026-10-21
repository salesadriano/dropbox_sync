#!/usr/bin/env bash
# lib/retencao.sh — politica de retencao e guarda por item do `reter` (fase 6,
# F-10; RF-93(e)(f), RF-95, RF-97(b); DIV-130 a DIV-147).
#
# Camada: dominio. PURO: sem rede, sem disco, sem estado e sem relogio. O
# "agora" do `--dias` e argumento (DIV-134: quem le o relogio e o confere com o
# `Date` da listagem e `commands/reter.sh`), entao mesma entrada, mesmo plano
# (RF-95(g), RF-96(d)). Depende de lib/errors, lib/path (comparacao de caminho
# remoto) e lib/filtro (casamento do nome, chave sem caixa, carimbo).
#
# DECISOES DO SOLICITANTE (memoria 2026-10-20-2010-retencao): os mais novos sao
# os de `server_modified` mais recente; em empate, vale o nome (o maior, sem
# caixa, DIV-144); sempre fica pelo menos 1 artefato. A guarda destrutiva nao
# depende de estado local: tudo o que ela recebe veio da listagem da MESMA
# execucao.
#
# Linhas marcadas `MUTACAO:<nome>` sao as que os casos de mutacao removem ou
# trocam (retencao_test, reter_test): cada uma e a unica barreira do seu P0
# nesta camada, e a marca deixa a prova de que o caso a protege.

# shellcheck disable=SC2034
# Justificativa: os `DBX_RETENCAO_*` sao canais publicos, lidos por
# commands/reter e pela suite; a analise estatica nao cruza arquivos.

[[ -n ${DBX_RETENCAO_CARREGADO:-} ]] && return 0
DBX_RETENCAO_CARREGADO=1

_dbx_retencao_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_retencao_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_retencao_diretorio=.
_dbx_retencao_diretorio=$(cd -P -- "$_dbx_retencao_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_retencao_diretorio/errors.sh"
# shellcheck source=lib/path.sh
. "$_dbx_retencao_diretorio/path.sh"
# shellcheck source=lib/filtro.sh
. "$_dbx_retencao_diretorio/filtro.sh"
unset _dbx_retencao_diretorio

DBX_RETENCAO_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_RETENCAO_ERRO_USO

# Tetos de RF-93(e)(f).
readonly DBX_RETENCAO_MANTER_MAXIMO=999999
readonly DBX_RETENCAO_DIAS_MAXIMO=36500

DBX_RETENCAO_MOTIVO=''
DBX_RETENCAO_VALOR=''
DBX_RETENCAO_EPOCA=''
DBX_RETENCAO_CORTE=''
DBX_RETENCAO_AGORA=''
DBX_RETENCAO_MINIMO='nao'
DBX_RETENCAO_FICAM=0
DBX_RETENCAO_SAEM=0
# Indices dos candidatos do mais novo ao mais velho, e a acao de cada indice.
declare -ga DBX_RETENCAO_ORDEM=()
declare -ga DBX_RETENCAO_ACAO=()

# ---------------------------------------------------------------------------
# Opcoes (RF-93(e)(f))
# ---------------------------------------------------------------------------

# dbx_retencao_validar_manter <opcao_como_digitada> <valor> — 1 a 999999, so
# digitos, sem zero a esquerda. Valor em DBX_RETENCAO_VALOR; recusa com uso
# invalido e DBX_RETENCAO_MOTIVO.
dbx_retencao_validar_manter() {
  local opcao=${1-} valor=${2-}
  { local LC_ALL=C; } 2>/dev/null
  DBX_RETENCAO_VALOR='' DBX_RETENCAO_MOTIVO=''
  if [[ $valor == '0' ]]; then
    # A frase e a da decisao do solicitante; o alias digitado vem na frente.
    DBX_RETENCAO_MOTIVO='--manter 0 apagaria todos; o minimo e 1'
    [[ $opcao == '--manter' ]] || DBX_RETENCAO_MOTIVO="$opcao 0: $DBX_RETENCAO_MOTIVO"
    return "$DBX_RETENCAO_ERRO_USO"
  fi
  if [[ $valor =~ ^[1-9][0-9]{0,5}$ ]] && ((valor <= DBX_RETENCAO_MANTER_MAXIMO)); then
    DBX_RETENCAO_VALOR=$valor
    return 0
  fi
  dbx_filtro_citar "$valor"
  DBX_RETENCAO_MOTIVO="valor invalido para $opcao: $DBX_FILTRO_CITADO; use inteiro de 1 a $DBX_RETENCAO_MANTER_MAXIMO, sem sinal nem zero a esquerda"
  return "$DBX_RETENCAO_ERRO_USO"
}

# dbx_retencao_validar_dias <opcao_como_digitada> <valor> — 1 a 36500.
dbx_retencao_validar_dias() {
  local opcao=${1-} valor=${2-}
  { local LC_ALL=C; } 2>/dev/null
  DBX_RETENCAO_VALOR='' DBX_RETENCAO_MOTIVO=''
  if [[ $valor =~ ^[1-9][0-9]{0,4}$ ]] && ((valor <= DBX_RETENCAO_DIAS_MAXIMO)); then
    DBX_RETENCAO_VALOR=$valor
    return 0
  fi
  dbx_filtro_citar "$valor"
  DBX_RETENCAO_MOTIVO="valor invalido para $opcao: $DBX_FILTRO_CITADO; use inteiro de 1 a $DBX_RETENCAO_DIAS_MAXIMO (dias), sem sinal, sufixo nem zero a esquerda"
  return "$DBX_RETENCAO_ERRO_USO"
}

# ---------------------------------------------------------------------------
# Datas (RF-95(b), DIV-134) — aritmetica do shell, sem `date`
# ---------------------------------------------------------------------------

# _dbx_retencao_dias_no_mes <ano> <mes> — em _dbx_retencao_n.
_dbx_retencao_n=0
_dbx_retencao_dias_no_mes() {
  case $2 in
    1 | 3 | 5 | 7 | 8 | 10 | 12) _dbx_retencao_n=31 ;;
    4 | 6 | 9 | 11) _dbx_retencao_n=30 ;;
    *)
      _dbx_retencao_n=28
      if (($1 % 4 == 0 && ($1 % 100 != 0 || $1 % 400 == 0))); then _dbx_retencao_n=29; fi
      ;;
  esac
}

# _dbx_retencao_epoca_de <ano> <mes> <dia> <h> <m> <s> — segundos desde 1970 em
# DBX_RETENCAO_EPOCA (algoritmo civil inverso do de lib/filtro). Ja validados.
_dbx_retencao_epoca_de() {
  local ano=$1 mes=$2 dia=$3
  ((mes <= 2)) && ano=$((ano - 1))
  local era=$(((ano >= 0 ? ano : ano - 399) / 400))
  local yoe=$((ano - era * 400))
  local mp=$((mes > 2 ? mes - 3 : mes + 9))
  local doy=$(((153 * mp + 2) / 5 + dia - 1))
  local doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  local dias=$((era * 146097 + doe - 719468))
  DBX_RETENCAO_EPOCA=$((dias * 86400 + $4 * 3600 + $5 * 60 + $6))
}

# _dbx_retencao_carimbo_de <segundos> — `AAAA-MM-DDTHH:MM:SSZ` em
# _dbx_retencao_k, inclusive ANTES de 1970: `--dias 36500` poe o corte em
# 1926, e o carimbo de lib/filtro so cobre segundos nao negativos. Divisao com
# arredondamento para baixo; anos de 1 a 9999.
_dbx_retencao_carimbo_de() {
  local s=$1 dias resto
  dias=$((s / 86400)) resto=$((s % 86400))
  ((resto < 0)) && dias=$((dias - 1)) resto=$((resto + 86400))
  local z=$((dias + 719468))
  local era=$(((z >= 0 ? z : z - 146096) / 146097))
  local doe=$((z - era * 146097))
  local yoe=$(((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365))
  local ano=$((yoe + era * 400))
  local doy=$((doe - (365 * yoe + yoe / 4 - yoe / 100)))
  local mp=$(((5 * doy + 2) / 153))
  local dia=$((doy - (153 * mp + 2) / 5 + 1))
  local mes=$((mp < 10 ? mp + 3 : mp - 9))
  ((mes <= 2)) && ano=$((ano + 1))
  printf -v _dbx_retencao_k '%04d-%02d-%02dT%02d:%02d:%02dZ' \
    "$ano" "$mes" "$dia" $((resto / 3600)) $((resto % 3600 / 60)) $((resto % 60))
}

# dbx_retencao_carimbo_valido <texto> — 0 so para `AAAA-MM-DDTHH:MM:SSZ` com
# data e hora existentes (RF-95(b), DIV-145). E o formato normalizado que a
# comparacao textual de RF-95(a)(d) exige.
dbx_retencao_carimbo_valido() {
  { local LC_ALL=C; } 2>/dev/null
  [[ ${1-} =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$ ]] || return 1
  local ano=$((10#${BASH_REMATCH[1]})) mes=$((10#${BASH_REMATCH[2]})) dia=$((10#${BASH_REMATCH[3]}))
  ((mes >= 1 && mes <= 12 && dia >= 1)) || return 1
  _dbx_retencao_dias_no_mes "$ano" "$mes"
  ((dia <= _dbx_retencao_n && 10#${BASH_REMATCH[4]} <= 23 && 10#${BASH_REMATCH[5]} <= 59 &&
    10#${BASH_REMATCH[6]} <= 59))
}

# dbx_retencao_epoca_http <texto> — o `Date` da resposta (IMF-fixdate de
# RFC 9110, `Tue, 20 Oct 2026 12:00:00 GMT`) em DBX_RETENCAO_EPOCA. As formas
# obsoletas (RFC 850 e asctime) nao sao aceitas: o servico usa a fixa, e um
# relogio que nao se le nao confere nada (DIV-134: ausente ou malformado, 10).
dbx_retencao_epoca_http() {
  { local LC_ALL=C; } 2>/dev/null
  DBX_RETENCAO_EPOCA=''
  [[ ${1-} =~ ^(Mon|Tue|Wed|Thu|Fri|Sat|Sun),\ ([0-9]{2})\ ([A-Z][a-z]{2})\ ([0-9]{4})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})\ GMT$ ]] ||
    return 1
  local mes
  case ${BASH_REMATCH[3]} in
    Jan) mes=01 ;; Feb) mes=02 ;; Mar) mes=03 ;; Apr) mes=04 ;; May) mes=05 ;; Jun) mes=06 ;;
    Jul) mes=07 ;; Aug) mes=08 ;; Sep) mes=09 ;; Oct) mes=10 ;; Nov) mes=11 ;; Dec) mes=12 ;;
    *) return 1 ;;
  esac
  local carimbo="${BASH_REMATCH[4]}-$mes-${BASH_REMATCH[2]}T${BASH_REMATCH[5]}:${BASH_REMATCH[6]}:${BASH_REMATCH[7]}Z"
  local -a partes=("${BASH_REMATCH[@]}")
  dbx_retencao_carimbo_valido "$carimbo" || return 1
  _dbx_retencao_epoca_de $((10#${partes[4]})) $((10#$mes)) $((10#${partes[2]})) \
    $((10#${partes[5]})) $((10#${partes[6]})) $((10#${partes[7]}))
  return 0
}

# ---------------------------------------------------------------------------
# Politica (RF-95)
# ---------------------------------------------------------------------------

# _dbx_retencao_mais_novo <a> <b> — 0 quando o candidato <a> vem antes de <b>
# na ordem de RF-95(a): `server_modified` maior; empate, chave sem caixa maior
# (DIV-144); empate, bytes de `path_lower` maiores. Comparacao em bytes.
# Le os vetores `_rp_sm`, `_rp_chave` e `_rp_pl` do chamador.
_dbx_retencao_mais_novo() {
  local LC_ALL=C
  [[ ${_rp_sm[$1]} > ${_rp_sm[$2]} ]] && return 0
  [[ ${_rp_sm[$1]} == "${_rp_sm[$2]}" ]] || return 1
  [[ ${_rp_chave[$1]} > ${_rp_chave[$2]} ]] && return 0
  [[ ${_rp_chave[$1]} == "${_rp_chave[$2]}" ]] || return 1
  [[ ${_rp_pl[$1]} > ${_rp_pl[$2]} ]]
}

# _dbx_retencao_manter_o_primeiro <indice> — RF-95(e): o primeiro da ordem
# passa de `sai` para `fica`, com a marca do minimo.
_dbx_retencao_manter_o_primeiro() {
  DBX_RETENCAO_ACAO[$1]='fica'
  DBX_RETENCAO_FICAM=$((DBX_RETENCAO_FICAM + 1))
  DBX_RETENCAO_SAEM=$((DBX_RETENCAO_SAEM - 1))
  DBX_RETENCAO_MINIMO='sim'
}

# _dbx_retencao_carimbos_validos — todo `_rp_sm` do chamador e carimbo valido;
# senao, status 1 com o candidato em DBX_RETENCAO_MOTIVO.
_dbx_retencao_carimbos_validos() {
  local i
  for i in "${!_rp_sm[@]}"; do
    dbx_retencao_carimbo_valido "${_rp_sm[i]}" && continue
    DBX_RETENCAO_MOTIVO="server_modified invalido no candidato $i"
    return 1
  done
  return 0
}

# _dbx_retencao_caminhos_unicos — DIV-158, DIV-161: nenhum `_rp_pl` do chamador
# se repete pela chave sem caixa de RF-54 (Unicode; a Dropbox nao diferencia
# caixa, inclusive fora do ASCII). Um caminho listado
# duas vezes faria o minimo e o "mantem os N" valerem por indice, e a copia que
# "sai" seria o MESMO arquivo da que fica.
_dbx_retencao_caminhos_unicos() {
  local i
  local -A vistos=()
  for i in "${!_rp_pl[@]}"; do
    dbx_retencao_chave "${_rp_pl[i]}" || {
      DBX_RETENCAO_MOTIVO="caminho fora do ASCII sem a chave sem caixa de RF-54 (localidade C.UTF-8 indisponivel) no candidato $i"
      return 1
    }
    if [[ -n ${vistos[$DBX_RETENCAO_CHAVE]+x} ]]; then
      DBX_RETENCAO_MOTIVO="path_lower repetido nos candidatos ${vistos[$DBX_RETENCAO_CHAVE]} e $i"
      return 1
    fi
    vistos[$DBX_RETENCAO_CHAVE]=$i
  done
  return 0
}

# dbx_retencao_planejar <manter|dias> <valor> <agora_epoca> <vetor_sm>
#   <vetor_chave> <vetor_path_lower>
#
# Os vetores (por NOME) sao paralelos, um indice por candidato: o
# `server_modified`, a chave sem caixa do `name` (RF-54) e o `path_lower`.
# Publica DBX_RETENCAO_ORDEM (indices do mais novo ao mais velho),
# DBX_RETENCAO_ACAO (`fica`/`sai` por indice), DBX_RETENCAO_FICAM,
# DBX_RETENCAO_SAEM, DBX_RETENCAO_MINIMO e, com `dias`, DBX_RETENCAO_CORTE e
# DBX_RETENCAO_AGORA (carimbos UTC). Status 1, com DBX_RETENCAO_MOTIVO, quando
# algum `server_modified` e invalido (DIV-145: ordem indefinida nao decide
# exclusao) ou a politica e desconhecida; nada e publicado como plano.
dbx_retencao_planejar() {
  local politica=${1-} valor=${2-} agora=${3-}
  local -n _rp_sm=$4 _rp_chave=$5 _rp_pl=$6
  local i pos atual total=${#_rp_sm[@]}
  DBX_RETENCAO_ORDEM=() DBX_RETENCAO_ACAO=()
  DBX_RETENCAO_FICAM=0 DBX_RETENCAO_SAEM=0 DBX_RETENCAO_MINIMO='nao'
  DBX_RETENCAO_CORTE='' DBX_RETENCAO_AGORA='' DBX_RETENCAO_MOTIVO=''
  valor=$2 # MUTACAO:valor
  case $politica in
    manter) [[ $valor =~ ^[0-9]+$ ]] || { DBX_RETENCAO_MOTIVO='valor de --manter invalido'; return 1; } ;;
    dias)
      [[ $valor =~ ^[0-9]+$ && $agora =~ ^[0-9]{1,12}$ ]] ||
        { DBX_RETENCAO_MOTIVO='valor de --dias ou relogio invalido'; return 1; }
      _dbx_retencao_carimbo_de $((agora - valor * 86400))
      DBX_RETENCAO_CORTE=$_dbx_retencao_k
      _dbx_retencao_carimbo_de "$agora"
      DBX_RETENCAO_AGORA=$_dbx_retencao_k
      ;;
    *) DBX_RETENCAO_MOTIVO="politica desconhecida: $politica"; return 1 ;;
  esac
  _dbx_retencao_carimbos_validos || { DBX_RETENCAO_CORTE='' DBX_RETENCAO_AGORA=''; return 1; } # MUTACAO:carimbo
  _dbx_retencao_caminhos_unicos || { DBX_RETENCAO_CORTE='' DBX_RETENCAO_AGORA=''; return 1; } # MUTACAO:unico
  # Insercao ordenada: as pastas de backup tem dezenas de artefatos, e a
  # ordem total (com o desempate por path_lower) torna o plano deterministico.
  local -a ordem=()
  for ((i = 0; i < total; i++)); do
    pos=${#ordem[@]}
    while ((pos > 0)); do
      atual=${ordem[pos - 1]}
      _dbx_retencao_mais_novo "$i" "$atual" || break
      ordem[pos]=$atual
      pos=$((pos - 1))
    done
    ordem[pos]=$i
  done
  local fica posicao=0
  for i in ${ordem[@]+"${ordem[@]}"}; do
    fica='nao'
    if [[ $politica == 'manter' ]]; then
      ((posicao < valor)) && fica='sim'
    else
      local LC_ALL=C
      [[ ! ${_rp_sm[i]} < $DBX_RETENCAO_CORTE ]] && fica='sim'
    fi
    if [[ $fica == 'sim' ]]; then
      DBX_RETENCAO_ACAO[i]='fica'
      DBX_RETENCAO_FICAM=$((DBX_RETENCAO_FICAM + 1))
    else
      DBX_RETENCAO_ACAO[i]='sai'
      DBX_RETENCAO_SAEM=$((DBX_RETENCAO_SAEM + 1))
    fi
    posicao=$((posicao + 1))
  done
  # RF-95(e): com pelo menos 1 candidato, o primeiro da ordem SEMPRE fica.
  ((total > 0)) && [[ ${DBX_RETENCAO_ACAO[${ordem[0]}]} == 'sai' ]] && _dbx_retencao_manter_o_primeiro "${ordem[0]}" # MUTACAO:minimo
  DBX_RETENCAO_ORDEM=(${ordem[@]+"${ordem[@]}"})
  return 0
}

# ---------------------------------------------------------------------------
# Guarda por item (RF-97(b)) — a segunda barreira, no ponto do `delete_v2`
# ---------------------------------------------------------------------------

# dbx_retencao_caminho_normalizado <path_lower> — DIV-159: absoluto, sem barra
# final, sem `//` e sem segmento `.` ou `..`. Regra unica da conferencia da
# listagem (commands/reter) e da lista de quem fica na guarda (7).
dbx_retencao_caminho_normalizado() {
  local caminho=${1-} resto segmento
  [[ $caminho == /?* && $caminho != */ ]] || return 1
  resto=${caminho#/}
  while [[ -n $resto ]]; do
    segmento=${resto%%/*}
    [[ -n $segmento && $segmento != '.' && $segmento != '..' ]] || return 1
    [[ $resto == */* ]] || break
    resto=${resto#*/}
  done
  return 0
}

# dbx_retencao_sem_combinante <texto> — DIV-164: 0 quando o texto NAO tem marca
# combinante dos blocos U+0300-036F, U+1AB0-1AFF, U+1DC0-1DFF, U+20D0-20FF e
# U+FE20-FE2F. Detecta pelos BYTES UTF-8, sob `LC_ALL=C`, sem depender da
# localidade. O servidor compoe os decompostos ao normalizar: um `path_lower`
# com essas marcas e o mesmo arquivo de outro em NFC (falha fechada ampla).
dbx_retencao_sem_combinante() {
  local LC_ALL=C texto=${1-}
  [[ $texto == *$'\xcc'[$'\x80'-$'\xbf']* ]] && return 1
  [[ $texto == *$'\xcd'[$'\x80'-$'\xaf']* ]] && return 1
  [[ $texto == *$'\xe1\xaa'[$'\xb0'-$'\xbf']* ]] && return 1
  [[ $texto == *$'\xe1\xab'[$'\x80'-$'\xbf']* ]] && return 1
  [[ $texto == *$'\xe1\xb7'[$'\x80'-$'\xbf']* ]] && return 1
  [[ $texto == *$'\xe2\x83'[$'\x90'-$'\xbf']* ]] && return 1
  [[ $texto == *$'\xef\xb8'[$'\xa0'-$'\xaf']* ]] && return 1
  return 0
}

# DIV-168: UTF-8 valido, por bytes (RFC 3629): sem overlong (C0, C1, E0 80-9F,
# F0 80-8F), sem surrogate (ED A0-BF), sem acima de U+10FFFF (F4 90+, F5-FF),
# sem sequencia truncada nem continuacao solta. A regex e montada uma vez.
_dbx_retencao_utf8_rx='^([\x01-\x7f]|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|[\xe1-\xec\xee\xef][\x80-\xbf][\x80-\xbf]|\xed[\x80-\x9f][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf][\x80-\xbf]|[\xf1-\xf3][\x80-\xbf][\x80-\xbf][\x80-\xbf]|\xf4[\x80-\x8f][\x80-\xbf][\x80-\xbf])*$'
printf -v _dbx_retencao_utf8_rx '%b' "$_dbx_retencao_utf8_rx"

# dbx_retencao_utf8_valido <texto> — 0 quando o texto e UTF-8 valido. Compara
# sob `LC_ALL=C`, byte a byte, sem depender da localidade.
dbx_retencao_utf8_valido() {
  local LC_ALL=C
  [[ ${1-} =~ $_dbx_retencao_utf8_rx ]]
}

# dbx_retencao_caminho_canonico <path_lower> — o caminho que a conferencia da
# listagem aceita: normalizado, sem marca combinante e igual a sua chave de
# RF-54. Usada na lista de quem fica da guarda (7) (DIV-165).
dbx_retencao_caminho_canonico() {
  dbx_retencao_caminho_normalizado "${1-}" || return 1
  dbx_retencao_sem_combinante "$1" || return 1
  dbx_retencao_chave "$1" || return 1
  [[ $DBX_RETENCAO_CHAVE == "$1" ]]
}

# dbx_retencao_chave <texto> — DIV-161: a chave sem caixa de RF-54 em
# DBX_RETENCAO_CHAVE, pela funcao unica de lib/filtro (`dbx_filtro_chave`).
# Sem a localidade UTF-8, essa chave so dobra o ASCII: texto fora do ASCII
# fica SEM chave confiavel e o status e 1 (falha fechada). Usada na unicidade
# da listagem e do plano e na guarda (7).
DBX_RETENCAO_CHAVE=''
dbx_retencao_chave() {
  DBX_RETENCAO_CHAVE=''
  _dbx_retencao_so_ascii "${1-}" || _dbx_retencao_localidade_util || return 1 # MUTACAO:localidade
  dbx_filtro_chave "${1-}"; DBX_RETENCAO_CHAVE=$DBX_FILTRO_CHAVE # MUTACAO:unicode
  return 0
}

_dbx_retencao_so_ascii() {
  local LC_ALL=C
  [[ $1 != *[$'\x80'-$'\xff']* ]]
}

# _dbx_retencao_localidade_util — 0 quando a dobra de lib/filtro alcanca fora
# do ASCII (E acentuado vira e acentuado), isto e, a localidade existe.
_dbx_retencao_localidade_util() {
  dbx_filtro_chave $'\xc3\x89'
  [[ $DBX_FILTRO_CHAVE == $'\xc3\xa9' ]]
}

# _dbx_retencao_ascii <texto> — caixa dobrada so no ASCII, em _dbx_retencao_k.
_dbx_retencao_k=''
_dbx_retencao_ascii() {
  local LC_ALL=C
  _dbx_retencao_k=${1,,}
}

# dbx_retencao_pai_igual <path_lower> <pasta> — 0 quando o pai de
# <path_lower> (tudo antes do ultimo `/`) e a <pasta> (normalizada, vazia para
# a raiz da conta), com a caixa dobrada SO no ASCII sob `LC_ALL=C`: fora do
# ASCII, igualdade exata (DIV-137, como DIV-118). Falha fechada.
dbx_retencao_pai_igual() {
  local caminho=${1-} pasta=${2-} pai
  [[ $caminho == /?* ]] || return 1
  pai=${caminho%/*}
  _dbx_retencao_ascii "$pai"
  pai=$_dbx_retencao_k
  _dbx_retencao_ascii "$pasta"
  [[ $pai == "$_dbx_retencao_k" ]]
}

# dbx_retencao_nome_coerente <name> <path_lower> — 0 quando o ultimo componente
# de <path_lower> e o <name> tem a mesma chave sem caixa de RF-54 (DIV-137): o
# padrao avalia o `name` e o `delete_v2` apaga o `path_lower`.
dbx_retencao_nome_coerente() {
  local nome=${1-} caminho=${2-} chave
  [[ -n $nome && $nome != */* && $caminho == /* ]] || return 1
  dbx_filtro_chave "$nome"
  chave=$DBX_FILTRO_CHAVE
  dbx_filtro_chave "${caminho##*/}"
  [[ $chave == "$DBX_FILTRO_CHAVE" ]]
}

# _dbx_retencao_identidade_fora <rev> <id> <vetor_revs> <vetor_ids>
#   <vetor_ficam> — DIV-167: 0 quando o `rev` (o `parent_rev` do delete) e o
# `id` de quem sai diferem dos de TODOS os que ficam. Falha fechada: rev ou id
# vazio, vetor ausente, inexistente, que nao e vetor, vazio, com elemento vazio
# ou de tamanho diferente da lista de caminhos de quem fica.
_dbx_retencao_identidade_fora() {
  local rev=${1-} id=${2-} nome
  [[ -n $rev && -n $id ]] || return 1
  for nome in "${3-}" "${4-}" "${5-}"; do
    [[ $nome =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  done
  local -n _ri_revs=$3 _ri_ids=$4 _ri_cam=$5
  [[ -n ${_ri_revs[*]+x} && ${_ri_revs@a} == *a* && -n ${_ri_ids[*]+x} && ${_ri_ids@a} == *a* ]] || return 1
  [[ ${#_ri_revs[@]} -eq ${#_ri_cam[@]} && ${#_ri_ids[@]} -eq ${#_ri_cam[@]} ]] || return 1
  local outro
  for outro in "${_ri_revs[@]}"; do
    [[ -n $outro && $outro != "$rev" ]] || return 1
  done
  for outro in "${_ri_ids[@]}"; do
    [[ -n $outro && $outro != "$id" ]] || return 1
  done
  return 0
}

# _dbx_retencao_fora_dos_que_ficam <path_lower> <vetor_ficam> — 0 quando o
# caminho difere, pela chave de RF-54, de todos os do vetor (por nome). Falha
# fechada: vetor ausente, inexistente ou vazio, ou chave indisponivel, recusa.
_dbx_retencao_fora_dos_que_ficam() {
  [[ ${2-} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1 # MUTACAO:lista
  local -n _rf_ficam=$2
  # DIV-162: vetor inexistente, que nao e vetor, ou vazio nao e "nenhum fica":
  # com pelo menos 1 candidato, sempre ha quem fique (RF-95(e)).
  [[ -n ${_rf_ficam[*]+x} && ${_rf_ficam@a} == *a* ]] || return 1 # MUTACAO:lista
  local alvo outro
  dbx_retencao_chave "$1" || return 1
  alvo=$DBX_RETENCAO_CHAVE
  for outro in "${_rf_ficam[@]}"; do
    dbx_retencao_caminho_canonico "$outro" || return 1 # MUTACAO:formato
    dbx_retencao_chave "$outro" || return 1
    [[ $DBX_RETENCAO_CHAVE == "$alvo" ]] && return 1
  done
  return 0
}

# dbx_retencao_guarda <tag> <path_lower> <name> <pasta> <raiz_remota> <acao>
#   <e_primeiro: sim|nao> <vetor_ficam> <rev> <id> <vetor_revs_ficam>
#   <vetor_ids_ficam>
#
# 0 SO quando todas as condicoes de RF-97(b) valem, com dados da listagem desta
# execucao: (1) arquivo; (2) filho direto da pasta; (3) `name` coerente com o
# `path_lower`; (4) o `name` casa o padrao preparado em lib/filtro; (5) dentro
# da `raiz_remota`; (6) pertence ao que sai e nao e o primeiro da ordem; (7)
# DIV-158, DIV-161, DIV-162: o CAMINHO nao e o de nenhum item que fica
# (<vetor_ficam>, por nome, com os `path_lower` do que fica, comparados pela
# chave de RF-54; sem o vetor, ou vazio, recusa; DIV-165: todo elemento e
# caminho canonico). DIV-164: marca combinante no caminho recusa. DIV-167: o
# `rev` (`parent_rev`) e o `id` de quem sai diferem dos de todos que ficam
# (barreira estrutural, que independe da grafia).
# Status 1 com DBX_RETENCAO_MOTIVO (a condicao, sem citar o item).
dbx_retencao_guarda() {
  local tag=${1-} caminho=${2-} nome=${3-} pasta=${4-} raiz=${5:-/} acao=${6-} primeiro=${7:-sim} vetor_ficam=${8-}
  local rev_sai=${9-} id_sai=${10-} vetor_revs=${11-} vetor_ids=${12-}
  DBX_RETENCAO_MOTIVO=''
  [[ $tag == 'file' ]] || { DBX_RETENCAO_MOTIVO='o item nao e arquivo'; return 1; }
  dbx_retencao_pai_igual "$caminho" "$pasta" || { DBX_RETENCAO_MOTIVO='o item nao e filho direto da pasta'; return 1; }
  dbx_retencao_nome_coerente "$nome" "$caminho" || { DBX_RETENCAO_MOTIVO='name incoerente com path_lower'; return 1; }
  dbx_filtro_nome_casa "$nome" || { DBX_RETENCAO_MOTIVO='o item nao casa o padrao'; return 1; }
  dbx_retencao_sem_combinante "$caminho" || { DBX_RETENCAO_MOTIVO='path_lower com marca combinante (decomposto)'; return 1; } # MUTACAO:combinante_guarda
  if ! dbx_path_remoto_confinar "$raiz" "$caminho" sim >/dev/null 2>&1 ||
    [[ $DBX_PATH_RESULTADO != "$caminho" ]]; then
    DBX_RETENCAO_MOTIVO='o item esta fora da raiz remota'
    return 1
  fi
  [[ $acao == 'sai' ]] || { DBX_RETENCAO_MOTIVO='o item nao esta no conjunto que sai'; return 1; }
  [[ $primeiro == 'nao' ]] || { DBX_RETENCAO_MOTIVO='o item e o mais novo, que sempre fica'; return 1; } # MUTACAO:primeiro
  _dbx_retencao_fora_dos_que_ficam "$caminho" "$vetor_ficam" || { DBX_RETENCAO_MOTIVO='o item tem o mesmo caminho de um que fica'; return 1; } # MUTACAO:fica
  _dbx_retencao_identidade_fora "$rev_sai" "$id_sai" "$vetor_revs" "$vetor_ids" "$vetor_ficam" || { DBX_RETENCAO_MOTIVO='o item tem o rev ou o id de um que fica (ou faltam as listas de rev e id)'; return 1; } # MUTACAO:identidade_guarda
  return 0
}
