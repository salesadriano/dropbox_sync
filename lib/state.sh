#!/usr/bin/env bash
# lib/state.sh — cache unico de `content_hash` (RF-38, RF-42, RF-52, RF-61, RF-62).
#
# Camada: adaptadores. Depende de lib/errors.sh, lib/hash.sh (a
# definicao unica da identidade do arquivo) e de `dbx_config_caminho_de_estado`
# (lib/config.sh, carregada por quem chama).
#
# ESTE COMPONENTE NAO DECIDE NADA, e isso e a propriedade central, nao um detalhe
# de implementacao.
#
#   `DP-27b` rebaixou a linha de base a memoria de desempenho. Ela guarda
#   `content_hash` ja calculado para dispensar reler arquivo cuja identidade nao
#   mudou — e so. Perdida, corrompida ou obsoleta, o `sync` e o `upload` decidem
#   igual e apenas trabalham mais. No `upload`, quem decide dispensar o envio e
#   a comparacao com o `content_hash` REMOTO (RF-60); o cache so poupa o calculo
#   do lado local.
#
# DOIS NAMESPACES, NUNCA MISTURADOS (fase 3, `DP-34`)
#
#   `memoria-<resumo>`  memoria do `sync`, uma por tripla (conta, origem, destino).
#                       A EXISTENCIA dela responde a `RF-48` ("par ja visto").
#   `upload-<resumo>`   cache do `upload` de arquivo, um por caminho canonico da
#                       origem (RF-62), SEM conta (RF-52(b)): guarda so dado local.
#
#   O `upload` nunca cria nem le `memoria-*`: se criasse, um par de raizes nunca
#   sincronizado passaria por "ja visto" e o reconhecimento de `RF-48` seria
#   dispensado. O `lib/db` (SQLite) saiu nesta fase; este e o UNICO cache.
#
# IDENTIDADE FORTE (RF-38(e), RF-61(b) a (d))
#
#   Reaproveitar exige que a identidade inteira coincida (`mtime` e `ctime` com
#   nanossegundos, dispositivo, inode e tamanho; formato em `lib/hash`). Registrar
#   exige mais: `stat` antes e depois do calculo identicos e `mtime` com pelo
#   menos 2 s de idade — a regra anti-corrida do "racy git", porque um arquivo
#   reescrito no mesmo instante do registro pode manter a identidade.
#
# POR QUE A CORRUPCAO DESCARTA EM VEZ DE RECUSAR (`RF-42`, invertido por `DP-27b`)
#
#   Recusar um comando por causa de um cache transformaria artefato descartavel
#   em ponto unico de falha. Qualquer anomalia — versao desconhecida, registro
#   truncado, conta divergente, campo malformado — resulta em cache VAZIO e
#   execucao normal.
#
# DIRETORIO DE ESTADO (RNF-25(b), (b1), (c))
#
#   Criado em 0700. Existente e do usuario: corrigido para 0700 na gravacao.
#   De outro dono: nada e lido dele e nada e escrito nele; a gravacao devolve o
#   codigo da classe `permissao`. Um diretorio alheio poderia plantar resumos
#   com a identidade de um arquivo do usuario e fazer o `sync` omitir envio.
#
# FORMATO, e por que nao e JSON
#
#   Registros terminados em byte nulo, com o caminho por ultimo. `lib/json` monta
#   a arvore inteira em memoria, e uma raiz com dezenas de milhares de arquivos
#   pagaria isso a cada execucao para ler um cache que existe para economizar
#   trabalho. Nome de arquivo nao aceita nulo, entao o formato suporta qualquer
#   nome sem escape.
#
# O NOME DO ARQUIVO E DERIVADO POR RESUMO, e nao montado com os caminhos.
#
#   Raizes e origens vem do operador e conteriam barra, `..` e quebra de linha.
#   Compor nome de arquivo a partir delas seria derivar caminho de escrita de
#   origem externa. O resumo identifica sem carregar nada do texto original.

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
DBX_STATE_ERRO_PERMISSAO=$(dbx_errors_codigo_saida permissao)
readonly DBX_STATE_ERRO_USO DBX_STATE_ERRO_PERMISSAO

# Versao 2: identidade forte no lugar de tamanho e `mtime`. A memoria de versao
# 1 e descartada na carga (versao desconhecida), e o par continua "visto".
readonly DBX_STATE_VERSAO=2
# Idade minima do `mtime`, em segundos, para um registro ser gravado.
readonly DBX_STATE_ANTI_CORRIDA_S=2
# Poda do upload (RF-61(i)): acima do teto, sai o que nao e usado ha mais de N dias.
readonly DBX_STATE_TETO_UPLOAD=10000
readonly DBX_STATE_DIAS_SEM_USO=90
# Marca de caminho presente sem resumo reaproveitavel (ver `dbx_state_registrar`).
readonly DBX_STATE_SEM_RESUMO='-'

# shellcheck disable=SC2034  # canais publicos, consumidos pelos comandos e pela suite
DBX_STATE_RESULTADO=''
DBX_STATE_HASH=''
DBX_STATE_MOTIVO=''
DBX_STATE_VISTO='nao'
# QA-P3-01: a memoria EXISTIA e foi descartada na carga (versao anterior,
# truncada, cabecalho divergente). O par continua "visto" (RF-48), mas a linha
# de base sumiu e a guarda de RF-41(b) nao tem com o que comparar: quem consome
# desabilita a exclusao naquela execucao.
DBX_STATE_DESCARTADA='nao'

declare -gA DBX_STATE_ENTRADA=()
# Caminhos consultados ou registrados nesta execucao (RF-38(b)).
declare -gA DBX_STATE_VISITADA=()

_dbx_state_limpar() {
  DBX_STATE_ENTRADA=()
  DBX_STATE_VISITADA=()
  DBX_STATE_HASH=''
  return 0
}

# ---------------------------------------------------------------------------
# Diretorio de estado
# ---------------------------------------------------------------------------

# _dbx_state_base — diretorio de estado em DBX_STATE_RESULTADO.
_dbx_state_base() {
  DBX_STATE_RESULTADO=''
  dbx_config_caminho_de_estado || return $?
  DBX_STATE_RESULTADO=$DBX_CONFIG_RESULTADO
  return 0
}

# _dbx_state_diretorio_confiavel <dir> — 0 quando o diretorio existe e pertence
# ao usuario. `-O` segue ligacao simbolica: um `dbx` que aponta para diretorio
# alheio e tratado como alheio.
_dbx_state_diretorio_confiavel() {
  [[ -d $1 && -O $1 ]]
}

# _dbx_state_preparar_diretorio <dir> — garante o diretorio para gravacao.
#
# Inexistente: criado em 0700, independente do `umask` (o `-m` vale para o
# ultimo componente; os intermediarios sao do XDG, nao deste componente).
# Existente e do usuario: modo corrigido para 0700. Alheio: codigo de
# `permissao`, sem tocar em nada. Temporarios orfaos com mais de 1 dia saem.
_dbx_state_preparar_diretorio() {
  local diretorio=$1
  if [[ ! -e $diretorio && ! -L $diretorio ]]; then
    # shellcheck disable=SC2174  # deliberado: so o ultimo componente e deste modulo
    mkdir -p -m 700 -- "$diretorio" 2>/dev/null || return 1
  fi
  if ! _dbx_state_diretorio_confiavel "$diretorio"; then
    # shellcheck disable=SC2034  # canal publico
    DBX_STATE_MOTIVO='diretorio de estado pertence a outro usuario: memoria nao gravada'
    return "$DBX_STATE_ERRO_PERMISSAO"
  fi
  chmod 700 -- "$diretorio" 2>/dev/null || return 1
  # RNF-25(c): `-mtime +0` e "mais de 24 h". Os recentes podem ser gravacao
  # concorrente de outro processo e ficam.
  find "$diretorio" -maxdepth 1 -type f \( -name '.memoria.*' -o -name '.upload.*' \) \
    -mtime +0 -exec rm -f -- {} + 2>/dev/null
  return 0
}

# _dbx_state_gravar_arquivo <arquivo> <prefixo_temporario> <funcao_de_conteudo>
#
# Gravacao atomica UNICA, para os dois namespaces (RNF-25(a)): temporario no
# MESMO diretorio, criado em 0600 por `mktemp`, e renomeacao. Falha em qualquer
# etapa preserva o arquivo anterior.
_dbx_state_gravar_arquivo() {
  local arquivo=$1 prefixo=$2 conteudo=$3 temporario
  # Estado hostil: diretorio no lugar do registro. `mv` moveria o temporario
  # para dentro dele e devolveria sucesso.
  [[ -d $arquivo ]] && return 1
  temporario=$(mktemp "${arquivo%/*}/$prefixo.$$.XXXXXXXX" 2>/dev/null) || return 1
  "$conteudo" >"$temporario" 2>/dev/null || {
    rm -f -- "$temporario" 2>/dev/null
    return 1
  }
  mv -f -- "$temporario" "$arquivo" 2>/dev/null || {
    rm -f -- "$temporario" 2>/dev/null
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Identidade (formato e definicao em lib/hash)
# ---------------------------------------------------------------------------

# _dbx_state_identidade_valida <identidade> — seis campos, os numericos numericos.
_dbx_state_identidade_valida() {
  [[ $1 =~ ^[0-9]+\|[^|]+\|[^|]+\|[0-9]+\|[0-9]+\|[0-9]+$ ]]
}

# dbx_state_registravel <identidade_antes> <identidade_depois>
#
# 0 quando um resumo calculado entre as duas leituras pode ser registrado:
# leituras identicas e bem formadas (RF-61(c)), tamanho maior que zero (RF-61(e):
# arquivo vazio e fila nomeada ficam fora) e `mtime` com pelo menos 2 s de idade
# no relogio de agora (RF-61(d)).
dbx_state_registravel() {
  [[ $# -eq 2 ]] || return "$DBX_STATE_ERRO_USO"
  local antes=$1 depois=$2 agora mtime
  [[ -n $antes && $antes == "$depois" ]] || return 1
  _dbx_state_identidade_valida "$antes" || return 1
  [[ ${antes##*|} -gt 0 ]] || return 1
  printf -v agora '%(%s)T' -1
  mtime=${antes%%|*}
  [[ $((agora - mtime)) -ge $DBX_STATE_ANTI_CORRIDA_S ]] || return 1
  return 0
}

# ---------------------------------------------------------------------------
# Namespace do sync: `memoria-*`
# ---------------------------------------------------------------------------

# dbx_state_caminho <conta> <origem> <destino> — arquivo da memoria, por resumo.
dbx_state_caminho() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  # A tripla inteira entra no resumo: `RF-52` exige que a identidade da conta
  # participe, e nao so o par de raizes. `dbx_hash_conteudo_fluxo` e usado aqui
  # apenas como funcao de resumo — nao ha nada de remoto nisto.
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
  local arquivo registro resumo resto identidade

  _dbx_state_limpar
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_VISTO='nao'
  DBX_STATE_DESCARTADA='nao'

  dbx_state_caminho "$conta" "$origem" "$destino" || {
    DBX_STATE_MOTIVO='nao foi possivel determinar o caminho da memoria'
    return 0
  }
  arquivo=$DBX_STATE_RESULTADO
  # Diretorio alheio nao e lido nem prova execucao anterior.
  _dbx_state_diretorio_confiavel "${arquivo%/*}" || return 0
  [[ -e $arquivo || -L $arquivo ]] || return 0
  # Arquivo (ou alvo de ligacao) de outro dono nao e lido nem prova execucao
  # anterior: pode ter sido plantado.
  [[ -O $arquivo ]] || return 0
  # QA-P3-07: memoria do usuario que EXISTE e nao pode ser usada — ilegivel ou
  # que nao e arquivo regular — nao e memoria AUSENTE: o par ja foi visto e a
  # linha de base sumiu. Conta como descartada.
  if [[ ! -f $arquivo || ! -r $arquivo ]]; then
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_STATE_VISTO='sim'
    DBX_STATE_DESCARTADA='sim'
    DBX_STATE_MOTIVO='memoria ilegivel: descartada'
    return 0
  fi

  # `VISTO` responde a pergunta de `RF-48` — este par de raizes ja foi
  # sincronizado antes? —, e ela e sobre a EXISTENCIA do arquivo, nao sobre o
  # conteudo dele. Memoria corrompida ainda prova execucao anterior.
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_STATE_VISTO='sim'
  # Ate a carga chegar ao fim valida, a memoria conta como descartada: todo
  # ramo de descarte abaixo a deixa assim, e so o retorno final a limpa.
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_DESCARTADA='sim'

  local -a cabecalho=()
  local contados=0
  while IFS= read -r -d '' registro; do
    if [[ $contados -lt 4 ]]; then
      cabecalho+=("$registro")
      contados=$((contados + 1))
      continue
    fi
    # Resumo, identidade e o caminho, que leva TUDO o que sobra: ele pode conter
    # tabulacao e quebra de linha. Registro malformado e ignorado, e nao aborta
    # a carga: cache que nao acerta apenas trabalha mais.
    [[ $registro == *$'\t'*$'\t'* ]] || continue
    resumo=${registro%%$'\t'*}
    resto=${registro#*$'\t'}
    identidade=${resto%%$'\t'*}
    if [[ $resumo != "$DBX_STATE_SEM_RESUMO" || $identidade != "$DBX_STATE_SEM_RESUMO" ]]; then
      dbx_hash_formato_valido "$resumo" || continue
      _dbx_state_identidade_valida "$identidade" || continue
    fi
    DBX_STATE_ENTRADA["${resto#*$'\t'}"]="$resumo"$'\t'"$identidade"
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
  # `RF-52` e a unica regra do componente cuja violacao nao produz sintoma.
  if [[ ${cabecalho[1]} != "$conta" || ${cabecalho[2]} != "$origem" || ${cabecalho[3]} != "$destino" ]]; then
    _dbx_state_limpar
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_STATE_MOTIVO='memoria de outra conta ou de outro par de raizes: descartada'
    return 0
  fi
  # shellcheck disable=SC2034  # canal publico, lido por commands/sync
  DBX_STATE_DESCARTADA='nao'
  return 0
}

# dbx_state_consultar <caminho> <identidade>
#
# Publica DBX_STATE_HASH e devolve zero quando o resumo guardado pode ser
# reaproveitado: a identidade guardada e a atual sao identicas. Toda consulta
# marca o caminho como visitado; entrada que nao casa sai do mapa, porque ja nao
# descreve o arquivo.
dbx_state_consultar() {
  [[ $# -eq 2 ]] || return "$DBX_STATE_ERRO_USO"
  local caminho=$1 identidade=$2 entrada
  DBX_STATE_HASH=''
  DBX_STATE_VISITADA["$caminho"]=1
  entrada=${DBX_STATE_ENTRADA[$caminho]:-}
  [[ -n $entrada ]] || return 1
  if [[ -z $identidade || ${entrada#*$'\t'} != "$identidade" ]]; then
    unset 'DBX_STATE_ENTRADA[$caminho]'
    return 1
  fi
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_STATE_HASH=${entrada%%$'\t'*}
  return 0
}

# dbx_state_registrar <caminho> <resumo> <identidade_antes> <identidade_depois>
#
# Registra no mapa em memoria so o que `dbx_state_registravel` admite. Status 1
# quando nao registra — o que nao e erro: o resumo continua valido para esta
# execucao, so nao e guardado para a proxima.
#
# O caminho entra na memoria mesmo quando o resumo nao e admissivel, com a marca
# `-` no lugar do resumo e da identidade: nada e reaproveitado dele, mas a
# memoria continua registrando que o caminho existia. E isso que `RF-41(b)` le
# para recusar a origem que ficou vazia — sem a marca, uma arvore de arquivos
# recem-criados (todos dentro da janela anti-corrida) deixaria a memoria vazia
# e a recusa nunca dispararia.
dbx_state_registrar() {
  [[ $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  DBX_STATE_VISITADA["$1"]=1
  if dbx_hash_formato_valido "$2" && dbx_state_registravel "$3" "$4"; then
    DBX_STATE_ENTRADA["$1"]="$2"$'\t'"$3"
    return 0
  fi
  DBX_STATE_ENTRADA["$1"]="$DBX_STATE_SEM_RESUMO"$'\t'"$DBX_STATE_SEM_RESUMO"
  return 1
}

# Conteudo da memoria do sync, para `_dbx_state_gravar_arquivo`.
_DBX_STATE_CABECALHO=()
_DBX_STATE_SO_VISITADAS='nao'
_dbx_state_conteudo_memoria() {
  local caminho
  printf '%s\0' "$DBX_STATE_VERSAO" "${_DBX_STATE_CABECALHO[@]}"
  for caminho in "${!DBX_STATE_ENTRADA[@]}"; do
    if [[ $_DBX_STATE_SO_VISITADAS == 'sim' && -z ${DBX_STATE_VISITADA[$caminho]:-} ]]; then
      continue
    fi
    printf '%s\t%s\0' "${DBX_STATE_ENTRADA[$caminho]}" "$caminho"
  done
}

# dbx_state_gravar <conta> <origem> <destino> [travessia_completa]
#
# Com `sim` no quarto argumento (travessia completa), so as entradas visitadas
# nesta execucao sao gravadas: arquivo apagado na origem sai da memoria
# (RF-38(b)). Com travessia parcial, NADA e gravado (RF-38(b) emendado, RF-41(f)):
# quem chama nao deve invocar esta funcao nesse caso. O unico chamador passa
# sempre `sim`; o ramo sem `sim` (mapa carregado mais os novos) e legado, sem
# chamador, e nao e o contrato. Falha de gravacao NAO e falha da execucao;
# diretorio alheio devolve o codigo de `permissao` para quem quiser avisar.
dbx_state_gravar() {
  [[ $# -eq 3 || $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  local conta=$1 origem=$2 destino=$3 arquivo estado

  dbx_state_caminho "$conta" "$origem" "$destino" || return 1
  arquivo=$DBX_STATE_RESULTADO
  _dbx_state_preparar_diretorio "${arquivo%/*}"
  estado=$?
  [[ $estado -eq 0 ]] || return "$estado"

  _DBX_STATE_CABECALHO=("$conta" "$origem" "$destino")
  _DBX_STATE_SO_VISITADAS=${4:-nao}
  _dbx_state_gravar_arquivo "$arquivo" .memoria _dbx_state_conteudo_memoria
}

# ---------------------------------------------------------------------------
# Namespace do upload: `upload-*` (RF-61)
# ---------------------------------------------------------------------------

# dbx_state_upload_caminho <chave_canonica> — arquivo do cache, por resumo.
#
# A chave e o caminho fisico canonico da origem (RF-62(a)), resolvido por quem
# chama. Sem conta: o registro guarda so dado local (RF-52(b)).
dbx_state_upload_caminho() {
  [[ $# -eq 1 && -n $1 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  resumo=$(printf 'upload\n%s' "$1" | dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/upload-${resumo:0:32}"
  return 0
}

# dbx_state_upload_consultar <chave_canonica> <identidade>
#
# Publica DBX_STATE_HASH e devolve zero quando ha registro valido com a mesma
# identidade. Qualquer anomalia — arquivo ausente, alheio, versao, tipo ou chave
# divergentes, numero de campos, resumo ou identidade malformados — e status 1,
# nunca falha do comando (RF-42).
dbx_state_upload_consultar() {
  [[ $# -eq 2 ]] || return "$DBX_STATE_ERRO_USO"
  local chave=$1 identidade=$2 arquivo registro
  DBX_STATE_HASH=''
  dbx_state_upload_caminho "$chave" || return 1
  arquivo=$DBX_STATE_RESULTADO
  _dbx_state_diretorio_confiavel "${arquivo%/*}" || return 1
  [[ -f $arquivo && -r $arquivo && -O $arquivo ]] || return 1

  local -a campos=()
  while IFS= read -r -d '' registro; do
    campos+=("$registro")
    [[ ${#campos[@]} -le 4 ]] || return 1
  done <"$arquivo"
  [[ ${#campos[@]} -eq 4 ]] || return 1
  [[ ${campos[0]} == "$DBX_STATE_VERSAO" && ${campos[1]} == 'upload' && ${campos[2]} == "$chave" ]] ||
    return 1
  registro=${campos[3]}
  [[ $registro == *$'\t'* ]] || return 1
  dbx_hash_formato_valido "${registro%%$'\t'*}" || return 1
  _dbx_state_identidade_valida "${registro#*$'\t'}" || return 1
  [[ -n $identidade && ${registro#*$'\t'} == "$identidade" ]] || return 1
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_STATE_HASH=${registro%%$'\t'*}
  return 0
}

# Conteudo do registro do upload, para `_dbx_state_gravar_arquivo`.
_DBX_STATE_REGISTRO_UPLOAD=()
_dbx_state_conteudo_upload() {
  printf '%s\0%s\0%s\0%s\t%s\0' "$DBX_STATE_VERSAO" upload "${_DBX_STATE_REGISTRO_UPLOAD[@]}"
}

# _dbx_state_podar_upload <diretorio> — RF-61(i). Conta os registros JA
# existentes (antes da gravacao corrente) sem processo externo; so acima do
# teto o diretorio e varrido para remover os nao usados ha mais de 90 dias.
_dbx_state_podar_upload() {
  local diretorio=$1
  local -a registros=()
  local tinha_nullglob='nao'
  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  registros=("$diretorio"/upload-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  [[ ${#registros[@]} -gt $DBX_STATE_TETO_UPLOAD ]] || return 0
  find "$diretorio" -maxdepth 1 -type f -name 'upload-*' \
    -mtime "+$DBX_STATE_DIAS_SEM_USO" -exec rm -f -- {} + 2>/dev/null
  return 0
}

# dbx_state_upload_gravar <chave_canonica> <resumo> <identidade_antes> <identidade_depois>
#
# Uma gravacao por `upload` (RF-61(g)): apos o envio bem-sucedido, ou apos a
# dispensa — inclusive quando o resumo veio do proprio cache, porque o acerto
# conta como uso e a regravacao renova o carimbo que a poda le. Status 1 quando
# o registro nao e admissivel ou a gravacao falha; codigo de `permissao` para
# diretorio alheio. Nenhum desses muda o resultado do `upload`.
dbx_state_upload_gravar() {
  [[ $# -eq 4 ]] || return "$DBX_STATE_ERRO_USO"
  local chave=$1 resumo=$2 arquivo estado
  dbx_hash_formato_valido "$resumo" || return 1
  dbx_state_registravel "$3" "$4" || return 1
  dbx_state_upload_caminho "$chave" || return 1
  arquivo=$DBX_STATE_RESULTADO
  _dbx_state_preparar_diretorio "${arquivo%/*}"
  estado=$?
  [[ $estado -eq 0 ]] || return "$estado"
  _dbx_state_podar_upload "${arquivo%/*}"

  _DBX_STATE_REGISTRO_UPLOAD=("$chave" "$resumo" "$3")
  _dbx_state_gravar_arquivo "$arquivo" .upload _dbx_state_conteudo_upload
}
