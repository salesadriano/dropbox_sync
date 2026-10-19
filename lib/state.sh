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
# shellcheck source=lib/tmp.sh
. "$_dbx_state_diretorio/tmp.sh"
unset _dbx_state_diretorio

DBX_STATE_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_STATE_ERRO_PERMISSAO=$(dbx_errors_codigo_saida permissao)
DBX_STATE_ERRO_CONFLITO=$(dbx_errors_codigo_saida conflito)
readonly DBX_STATE_ERRO_USO DBX_STATE_ERRO_PERMISSAO DBX_STATE_ERRO_CONFLITO

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
  # RF-69(o): `.trava.*` entra na mesma regra; `trava-*` nunca e varrido.
  find "$diretorio" -maxdepth 1 -type f \( -name '.memoria.*' -o -name '.upload.*' -o -name '.trava.*' \) \
    -mtime +0 -exec rm -f -- {} + 2>/dev/null
  return 0
}

# _dbx_state_gravar_arquivo <arquivo> <prefixo_temporario> <funcao_de_conteudo>
#
# Gravacao atomica UNICA, para os dois namespaces (RNF-25(a)): temporario no
# MESMO diretorio, criado em 0600 e registrado por `lib/tmp`, e renomeacao.
# Falha em qualquer etapa preserva o arquivo anterior; sinal remove o
# temporario.
_dbx_state_gravar_arquivo() {
  local arquivo=$1 prefixo=$2 conteudo=$3 temporario
  # Estado hostil: diretorio no lugar do registro. `mv` moveria o temporario
  # para dentro dele e devolveria sucesso.
  [[ -d $arquivo ]] && return 1
  dbx_tmp_arquivo "${arquivo%/*}/$prefixo.$$.XXXXXXXX" || return 1
  temporario=$DBX_TMP_CAMINHO
  "$conteudo" >"$temporario" 2>/dev/null || {
    dbx_tmp_remover "$temporario"
    return 1
  }
  mv -f -- "$temporario" "$arquivo" 2>/dev/null || {
    dbx_tmp_remover "$temporario"
    return 1
  }
  dbx_tmp_esquecer "$temporario"
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

# ---------------------------------------------------------------------------
# Trava de concorrencia: `trava-*` (RF-69; parecer do DBA de 2026-10-19)
# ---------------------------------------------------------------------------
#
# UM `sync` OU `verificar` POR VEZ PARA O MESMO PAR. Estado TRANSITORIO que nao
# decide nada (RNF-26 emendado): so impede a execucao concorrente. Quem cria e
# remove e este componente (DIV-41); `lib/tmp` so guarda a acao de liberar.
#
# CRIACAO EXCLUSIVA SEM CONTEUDO PARCIAL (RF-69(g)(j))
#
#   A linha inteira e gravada num temporario do MESMO diretorio e publicada por
#   `ln`, que falha se o nome existe: ninguem ve a trava vazia. O SUCESSO E O
#   INODE (`-ef`), nunca o codigo do `ln`: com um diretorio no nome o `ln` cria
#   o elo DENTRO dele e devolve zero, e em NFS a resposta perdida faz o `ln`
#   devolver erro tendo criado o elo. `noclobber` mostraria o arquivo vazio, e
#   `mkdir` nao e atomico no uutils.
#
# RETOMADA SERIALIZADA (RF-69(m))
#
#   Apagar a orfa e criar a nova tem corrida: dois retomadores leem a mesma
#   orfa, e o segundo apagaria a trava VIVA do primeiro. Por isso a retomada
#   passa por uma segunda trava exclusiva, `trava-<resumo>.r`: quem a obtem le
#   de novo, confirma a mesma orfa, apaga, cria a sua e solta a `.r`. A `.r` que
#   sobra de um processo morto nessa janela nunca e retomada sozinha.
#
# LEITURA HOSTIL (RF-69(k))
#
#   Nada do arquivo e executado nem ecoado: uma linha, no maximo 512 bytes, lida
#   por descritor, com cada campo validado. Qualquer falha e "ilegivel", e trava
#   ilegivel nunca e apagada nem retomada. Pid de 2 a 7 digitos sem zero a
#   esquerda: `kill -0 0` e `kill -0 -1` alcancam grupos de processos.
#
# MESMO HOST (RF-69(l))
#
#   Nome do host e namespace de pid iguais. Dois containers com o mesmo nome e o
#   estado compartilhado nao podem fazer o `kill -0` de um mentir sobre o outro.
#   `boot_id` diferente no mesmo host prova que houve reinicio: orfa. Relogio e
#   `mtime` nunca decidem.
#
# DIRETORIO DE ESTADO
#
#   Ausente, ele (e o que faltar acima dele) e criado em 0700 e REMOVIDO na
#   liberacao, por `rmdir`, se continuar vazio: o `verificar` e a simulacao
#   terminam com tudo como estava (RF-69(e)). Existente, o modo nao e tocado
#   aqui, pelo mesmo motivo; quem grava memoria o corrige (RNF-25(b1)).

readonly DBX_STATE_TRAVA_LIMITE=512
readonly DBX_STATE_TRAVA_SEM_CONTA='sem-conta'

# shellcheck disable=SC2034  # canais publicos, lidos pelos comandos e pela suite
DBX_STATE_HOST_ID=''
DBX_STATE_HOST_NOME=''
DBX_STATE_HOST_BOOT=''
DBX_STATE_HOST_NS=''
# Trava detida por este processo e aviso de orfa retomada.
DBX_STATE_TRAVA=''
DBX_STATE_AVISO=''
# Campos da ultima trava lida (so validados) e o estado apurado.
DBX_STATE_TRAVA_PID=''
DBX_STATE_TRAVA_HOST=''
DBX_STATE_TRAVA_INICIO=''
DBX_STATE_TRAVA_COMANDO=''
DBX_STATE_TRAVA_ESTADO=''
# Listagem para o `diagnostico` e o `unlink` (RF-71, RF-69(h2)).
DBX_STATE_TRAVAS_ARQUIVO=()
DBX_STATE_TRAVAS_ESTADO=()
DBX_STATE_TRAVAS_PID=()
DBX_STATE_TRAVAS_HOST=()
DBX_STATE_TRAVAS_INICIO=()
DBX_STATE_TRAVAS_COMANDO=()

_dbx_state_trava_inicio=''
_dbx_state_trava_acao=''
_dbx_state_trava_criados=()

# dbx_state_host_id — identidade do host, uma vez por processo: nome (do shell,
# com recuo para o kernel), `boot_id` e inode do namespace de pid, cada um
# quando existir (`x` quando nao). Nenhum utilitario fora do preflight.
dbx_state_host_id() {
  [[ -n $DBX_STATE_HOST_ID ]] && return 0
  local nome=${HOSTNAME:-} boot='' ns=''
  if [[ -z $nome && -r /proc/sys/kernel/hostname ]]; then
    IFS= read -r nome </proc/sys/kernel/hostname || :
  fi
  nome=${nome//[!A-Za-z0-9._-]/_}
  nome=${nome:0:64}
  [[ -n $nome ]] || nome=x
  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    IFS= read -r boot </proc/sys/kernel/random/boot_id || :
  fi
  [[ $boot =~ ^[A-Za-z0-9-]{1,64}$ ]] || boot=x
  [[ -e /proc/self/ns/pid ]] && ns=$(stat -L -c %i -- /proc/self/ns/pid 2>/dev/null)
  [[ $ns =~ ^[0-9]{1,20}$ ]] || ns=x
  DBX_STATE_HOST_NOME=$nome
  DBX_STATE_HOST_BOOT=$boot
  DBX_STATE_HOST_NS=$ns
  DBX_STATE_HOST_ID="$nome:$boot:$ns"
}

# _dbx_state_minusculas_ascii <texto> — so A-Z viram a-z; o resto fica byte a
# byte. Em DBX_STATE_RESULTADO, sem captura.
_dbx_state_minusculas_ascii() {
  local LC_ALL=C
  DBX_STATE_RESULTADO=${1,,}
}

# dbx_state_trava_caminho <identidade> <raiz_local_canonica> <raiz_remota>
#
# Chave do par SEM ORDEM entre os sentidos (DIV-38): entra a raiz local e a
# remota, nunca a origem e o destino; a remota sem caixa. Identidade vazia vira
# o marcador `sem-conta` (DIV-40). Nome por resumo, sem dado externo cru.
dbx_state_trava_caminho() {
  [[ $# -eq 3 ]] || return "$DBX_STATE_ERRO_USO"
  local base resumo remoto
  _dbx_state_base || return $?
  base=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  # Dobra de caixa SO no ASCII, sob `C` (QA-B2-03, como RNF-20(b4) na fase 1b):
  # a mesma grafia gera a mesma chave no agendador (`C`) e no terminal
  # (`C.UTF-8`); `${x,,}` na localidade do usuario dobraria `Ç` so numa delas.
  _dbx_state_minusculas_ascii "$3"
  remoto=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  resumo=$(printf 'trava\n%s\n%s\n%s' "${1:-$DBX_STATE_TRAVA_SEM_CONTA}" "$2" "$remoto" |
    dbx_hash_conteudo_fluxo) || return $?
  DBX_STATE_RESULTADO="$base/trava-${resumo:0:32}"
  return 0
}

# dbx_state_trava_ler <arquivo> — 0 legivel (campos em DBX_STATE_TRAVA_*),
# 1 ilegivel, 2 ausente.
dbx_state_trava_ler() { _dbx_state_trava_ler "$1"; }

_dbx_state_trava_ler() {
  local arquivo=$1 linha='' resto fd estado=1 LC_ALL=C
  local -a campos=()
  DBX_STATE_TRAVA_PID='' DBX_STATE_TRAVA_HOST='' DBX_STATE_TRAVA_INICIO='' DBX_STATE_TRAVA_COMANDO=''
  [[ -L $arquivo ]] && return 1
  [[ -e $arquivo ]] || return 2
  # Um descritor so: o que e conferido e o que e lido sao o mesmo arquivo,
  # ainda que o nome seja trocado ou apagado no meio. Sem utilitario externo:
  # o `diagnostico` le a trava so com o shell (RF-66(e)).
  # A redirecao do erro fica no GRUPO: em `exec` puro ela valeria para o resto
  # do processo e calaria todo diagnostico dali em diante.
  { exec {fd}<"$arquivo"; } 2>/dev/null || {
    [[ -e $arquivo || -L $arquivo ]] && return 1
    return 2
  }
  if [[ -f /dev/fd/$fd && -O /dev/fd/$fd ]]; then
    # A leitura tem de chegar ao FIM DO ARQUIVO (status diferente de zero) em
    # ate 513 bytes: se ela para antes, achou um nulo (o delimitador) ou o
    # limite, e ha bytes que a linha nao contem (QA-B2-01). Depois disso, a
    # linha termina no unico `\n`: qualquer byte apos ele torna a trava ilegivel.
    IFS= read -r -d '' -n "$((DBX_STATE_TRAVA_LIMITE + 1))" linha <&"$fd" || estado=0
  fi
  exec {fd}<&-
  [[ $estado -eq 0 && ${#linha} -le $DBX_STATE_TRAVA_LIMITE && $linha == *$'\n' ]] || return 1
  linha=${linha%$'\n'}
  [[ $linha == *$'\n'* ]] && return 1
  resto=$linha
  while [[ $resto == *$'\t'* ]]; do
    campos+=("${resto%%$'\t'*}")
    resto=${resto#*$'\t'}
  done
  campos+=("$resto")
  [[ ${#campos[@]} -eq 7 && ${campos[0]} == 'dbx-trava' && ${campos[1]} == '1' && ${campos[6]} == 'fim' ]] ||
    return 1
  [[ ${campos[2]} =~ ^[1-9][0-9]{1,6}$ ]] || return 1
  [[ ${campos[3]} =~ ^[A-Za-z0-9._:-]{1,255}$ ]] || return 1
  [[ ${campos[4]} =~ ^[0-9]{1,19}$ ]] || return 1
  [[ ${campos[5]} == 'sync' || ${campos[5]} == 'verificar' ]] || return 1
  DBX_STATE_TRAVA_PID=${campos[2]}
  DBX_STATE_TRAVA_HOST=${campos[3]}
  DBX_STATE_TRAVA_INICIO=${campos[4]}
  DBX_STATE_TRAVA_COMANDO=${campos[5]}
  return 0
}

# _dbx_state_trava_classificar — estado da trava lida: viva, orfa, outro-host.
# Permissao negada no `kill -0` conta como viva (o processo existe).
_dbx_state_trava_classificar() {
  local host=$DBX_STATE_TRAVA_HOST nome resto boot ns
  dbx_state_host_id
  DBX_STATE_TRAVA_ESTADO='outro-host'
  [[ $host == *:*:* ]] || return 0
  nome=${host%%:*}
  resto=${host#*:}
  boot=${resto%%:*}
  ns=${resto#*:}
  [[ $ns == *:* || $nome != "$DBX_STATE_HOST_NOME" || $ns != "$DBX_STATE_HOST_NS" ]] && return 0
  if [[ $boot != "$DBX_STATE_HOST_BOOT" ]]; then
    DBX_STATE_TRAVA_ESTADO='orfa'
  elif kill -0 "$DBX_STATE_TRAVA_PID" 2>/dev/null || [[ -e /proc/$DBX_STATE_TRAVA_PID ]]; then
    DBX_STATE_TRAVA_ESTADO='viva'
  else
    DBX_STATE_TRAVA_ESTADO='orfa'
  fi
  return 0
}

# _dbx_state_trava_quem — "o <comando> pid <pid> no host <nome>, iniciado em
# <ISO UTC>", so com campos validados, em DBX_STATE_RESULTADO.
_dbx_state_trava_quem() {
  # Exportada: o `printf` do shell so honra o fuso que esta no ambiente.
  local -x TZ=UTC
  local iso
  printf -v iso '%(%Y-%m-%dT%H:%M:%SZ)T' "$DBX_STATE_TRAVA_INICIO"
  DBX_STATE_RESULTADO="o $DBX_STATE_TRAVA_COMANDO pid $DBX_STATE_TRAVA_PID no host ${DBX_STATE_TRAVA_HOST%%:*}, iniciado em $iso"
}

# _dbx_state_trava_publicar <destino> <comando> — receita de RF-69(j). 0
# publicada, 1 sem temporario, 2 nome ocupado (ou `ln` sem elo).
_dbx_state_trava_publicar() {
  local destino=$1 temporario resultado=2
  dbx_tmp_arquivo "${destino%/*}/.trava.$$.${DBX_STATE_HOST_ID//:/.}.XXXXXXXX" || return 1
  temporario=$DBX_TMP_CAMINHO
  if ! printf 'dbx-trava\t1\t%s\t%s\t%s\t%s\tfim\n' "$$" "$DBX_STATE_HOST_ID" \
    "$_dbx_state_trava_inicio" "$2" >"$temporario" 2>/dev/null; then
    dbx_tmp_remover "$temporario"
    return 1
  fi
  ln -- "$temporario" "$destino" 2>/dev/null
  if [[ $temporario -ef $destino ]]; then
    resultado=0
  elif [[ -d $destino && ! -L $destino && ${destino}/${temporario##*/} -ef $temporario ]]; then
    # Diretorio surgido no nome entre a checagem e o `ln`: o elo foi parar
    # dentro dele, e e nosso.
    rm -f -- "${destino}/${temporario##*/}"
  fi
  dbx_tmp_remover "$temporario"
  return "$resultado"
}

# _dbx_state_trava_ocupada <arquivo> <resultado_da_leitura> — monta a recusa.
_dbx_state_trava_ocupada() {
  local arquivo=$1
  if [[ $2 -ne 0 ]]; then
    DBX_STATE_MOTIVO="trava ilegivel: $arquivo nunca e retomada nem apagada automaticamente; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com: rm $arquivo"
  elif [[ $DBX_STATE_TRAVA_ESTADO == 'outro-host' ]]; then
    _dbx_state_trava_quem
    DBX_STATE_MOTIVO="trava de outro host: $DBX_STATE_RESULTADO, detem este par e nunca e retomada automaticamente; confirme que essa execucao terminou e remova a trava com: rm $arquivo"
  else
    _dbx_state_trava_quem
    DBX_STATE_MOTIVO="trava ocupada: $DBX_STATE_RESULTADO, esta trabalhando neste par; rode de novo depois ou use --esperar N (--wait N) para aguardar ate N segundos"
  fi
  DBX_STATE_RESULTADO=''
  return "$DBX_STATE_ERRO_CONFLITO"
}

# _dbx_state_trava_tentar <arquivo> <comando> — uma sondagem, em secao critica
# de `lib/tmp`: entre a publicacao e o registro da liberacao nenhum sinal
# encerra o processo. 0 adquirida, conflito, 1 falha local, 3 tentar de novo.
_dbx_state_trava_tentar() {
  local estado
  dbx_tmp_critico_inicio
  _dbx_state_trava_sondar "$@"
  estado=$?
  dbx_tmp_critico_fim
  return "$estado"
}

_dbx_state_trava_sondar() {
  local arquivo=$1 comando=$2 leitura
  if [[ -L $arquivo || -d $arquivo ]]; then
    _dbx_state_trava_ocupada "$arquivo" 1
    return $?
  fi
  _dbx_state_trava_publicar "$arquivo" "$comando"
  case $? in
    0)
      _dbx_state_trava_detida "$arquivo"
      return 0
      ;;
    1)
      _dbx_state_trava_sem_escrita "$arquivo"
      return $?
      ;;
  esac
  _dbx_state_trava_ler "$arquivo"
  leitura=$?
  [[ $leitura -eq 2 ]] && return 3
  [[ $leitura -eq 0 ]] && _dbx_state_trava_classificar
  if [[ $leitura -eq 0 && $DBX_STATE_TRAVA_ESTADO == 'orfa' ]]; then
    _dbx_state_trava_retomar "$arquivo" "$comando"
    return $?
  fi
  _dbx_state_trava_ocupada "$arquivo" "$leitura"
}

# _dbx_state_trava_sem_escrita <arquivo> — nao deu para criar o temporario
# (DIV-50): a trava que JA existe ainda decide. Viva, de outro host ou
# ilegivel: conflito, como em qualquer diretorio. Ausente ou orfa (que ninguem
# consegue retomar ali): permissao, e o comando segue sem trava, com aviso.
_dbx_state_trava_sem_escrita() {
  local arquivo=$1 leitura
  _dbx_state_trava_ler "$arquivo"
  leitura=$?
  [[ $leitura -eq 0 ]] && _dbx_state_trava_classificar
  if [[ $leitura -eq 1 || ($leitura -eq 0 && $DBX_STATE_TRAVA_ESTADO != 'orfa') ]]; then
    _dbx_state_trava_ocupada "$arquivo" "$leitura"
    return $?
  fi
  DBX_STATE_MOTIVO="diretorio de estado sem escrita: ${arquivo%/*}"
  return "$DBX_STATE_ERRO_PERMISSAO"
}

# _dbx_state_trava_detida <arquivo> — a trava e deste processo: a liberacao
# entra no registro de `lib/tmp` (RNF-35(h)).
_dbx_state_trava_detida() {
  DBX_STATE_TRAVA=$1
  dbx_tmp_acao_registrar _dbx_state_trava_soltar "$1"
  _dbx_state_trava_acao=$DBX_TMP_ID
}

# _dbx_state_trava_retomar <arquivo> <comando> — RF-69(m), com a orfa ja lida.
_dbx_state_trava_retomar() {
  local arquivo=$1 comando=$2 r="$1.r" leitura
  local pid=$DBX_STATE_TRAVA_PID host=$DBX_STATE_TRAVA_HOST inicio=$DBX_STATE_TRAVA_INICIO
  local boot_atual
  _dbx_state_trava_quem
  local quem=$DBX_STATE_RESULTADO
  dbx_state_host_id
  boot_atual=$DBX_STATE_HOST_BOOT

  if [[ -L $r || -d $r ]]; then
    DBX_STATE_MOTIVO="retomada de trava interrompida: $r nunca e retomada automaticamente; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com: rm $r"
    return "$DBX_STATE_ERRO_CONFLITO"
  fi
  _dbx_state_trava_publicar "$r" "$comando"
  case $? in
    1)
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: ${arquivo%/*}"
      return "$DBX_STATE_ERRO_PERMISSAO"
      ;;
    2)
      _dbx_state_trava_ler "$r"
      leitura=$?
      [[ $leitura -eq 2 ]] && return 3
      [[ $leitura -eq 0 ]] && _dbx_state_trava_classificar
      if [[ $leitura -eq 0 && $DBX_STATE_TRAVA_ESTADO == 'viva' ]]; then
        _dbx_state_trava_quem
        DBX_STATE_MOTIVO="trava ocupada: $DBX_STATE_RESULTADO, esta retomando a trava deste par; rode de novo depois ou use --esperar N (--wait N) para aguardar ate N segundos"
      else
        DBX_STATE_MOTIVO="retomada de trava interrompida: $r nunca e retomada automaticamente; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com: rm $r"
      fi
      DBX_STATE_RESULTADO=''
      return "$DBX_STATE_ERRO_CONFLITO"
      ;;
  esac

  # Com a `.r`: a orfa precisa ser a MESMA da primeira leitura.
  _dbx_state_trava_ler "$arquivo"
  leitura=$?
  if [[ $leitura -ne 0 || $DBX_STATE_TRAVA_PID != "$pid" || $DBX_STATE_TRAVA_HOST != "$host" ||
    $DBX_STATE_TRAVA_INICIO != "$inicio" ]]; then
    rm -f -- "$r"
    return 3
  fi
  # Receita de RF-69(m): apaga a orfa e cria a nova por (j). Entre o `rm` e o
  # `ln` o nome fica livre, e uma aquisicao comum pode entrar; a exclusao vale
  # (um so detem a trava). DIV-53: por isso o aviso e de quem APAGOU a orfa,
  # dado aqui, antes do `ln`, e mantido ainda que este processo perca o `ln` e
  # saia com conflito: um aviso por orfa removida, que nao afirma quem ficou
  # com a trava.
  rm -f -- "$arquivo"
  if [[ ${host#*:} != "$boot_atual:"* ]]; then
    DBX_STATE_AVISO="trava orfa de pid $pid removida ($quem; nao terminou neste boot do host, houve reinicio)"
  else
    DBX_STATE_AVISO="trava orfa de pid $pid removida ($quem; terminou sem libera-la)"
  fi
  _dbx_state_trava_publicar "$arquivo" "$comando"
  leitura=$?
  rm -f -- "$r"
  case $leitura in
    0) ;;
    1)
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: ${arquivo%/*}"
      return "$DBX_STATE_ERRO_PERMISSAO"
      ;;
    *) return 3 ;;
  esac
  _dbx_state_trava_detida "$arquivo"
  return 0
}

# _dbx_state_trava_soltar <arquivo> — acao de liberacao: apaga SO a propria
# (pid, host e inicio gravados) e remove o diretorio que a aquisicao criou, se
# ficou vazio.
_dbx_state_trava_soltar() {
  local arquivo=$1
  if _dbx_state_trava_ler "$arquivo" && [[ $DBX_STATE_TRAVA_PID == "$$" &&
    $DBX_STATE_TRAVA_HOST == "$DBX_STATE_HOST_ID" && $DBX_STATE_TRAVA_INICIO == "$_dbx_state_trava_inicio" ]]; then
    rm -f -- "$arquivo"
  fi
  [[ $DBX_STATE_TRAVA == "$arquivo" ]] && DBX_STATE_TRAVA=''
  _dbx_state_trava_desfazer_diretorio
  return 0
}

_dbx_state_trava_desfazer_diretorio() {
  local indice
  for ((indice = ${#_dbx_state_trava_criados[@]} - 1; indice >= 0; indice--)); do
    rmdir -- "${_dbx_state_trava_criados[indice]}" 2>/dev/null || break
  done
  _dbx_state_trava_criados=()
}

# _dbx_state_trava_diretorio <dir> — garante o diretorio, guardando o que criou.
_dbx_state_trava_diretorio() {
  local diretorio=$1 acima=$1
  local -a faltam=()
  _dbx_state_trava_criados=()
  while [[ -n $acima && ! -e $acima && ! -L $acima ]]; do
    faltam=("$acima" "${faltam[@]}")
    acima=${acima%/*}
  done
  if [[ ${#faltam[@]} -gt 0 ]]; then
    # shellcheck disable=SC2174  # deliberado: cada componente criado aqui nasce 0700
    mkdir -p -m 700 -- "$diretorio" 2>/dev/null || {
      DBX_STATE_MOTIVO="diretorio de estado sem escrita: $diretorio"
      return "$DBX_STATE_ERRO_PERMISSAO"
    }
    _dbx_state_trava_criados=("${faltam[@]}")
  fi
  if ! _dbx_state_diretorio_confiavel "$diretorio"; then
    DBX_STATE_MOTIVO='diretorio de estado pertence a outro usuario'
    return "$DBX_STATE_ERRO_PERMISSAO"
  fi
  return 0
}

# dbx_state_trava_adquirir <identidade> <raiz_local_canonica> <raiz_remota>
#   <comando> <espera_s>
#
#   0          adquirida (DBX_STATE_TRAVA; DBX_STATE_AVISO se retomou orfa)
#   conflito   ocupada, de outro host, ilegivel, `.r` presa ou nome instavel
#              (DBX_STATE_MOTIVO)
#   permissao  diretorio de estado alheio ou sem escrita (DIV-48/DIV-50: quem
#              chama segue sem trava, com aviso)
#   outro      uso invalido ou falha local, com o proprio codigo
#
# Com espera, sonda a cada 1 s (`sleep`, sem rede e sem memoria) ate N
# sondagens. Uma trava por processo.
dbx_state_trava_adquirir() {
  [[ $# -eq 5 && ($4 == 'sync' || $4 == 'verificar') && $5 =~ ^[0-9]{1,4}$ ]] ||
    return "$DBX_STATE_ERRO_USO"
  [[ -z $DBX_STATE_TRAVA ]] || return "$DBX_STATE_ERRO_USO"
  local comando=$4 espera=$((10#$5)) arquivo estado sondagens=0 repeticoes=0
  DBX_STATE_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, lido por lib/cmd
  DBX_STATE_AVISO=''
  dbx_state_trava_caminho "$1" "$2" "$3" || {
    DBX_STATE_MOTIVO='nao foi possivel determinar o diretorio de estado'
    return 1
  }
  arquivo=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  _dbx_state_trava_diretorio "${arquivo%/*}" || return $?
  dbx_state_host_id
  printf -v _dbx_state_trava_inicio '%(%s)T' -1

  while :; do
    _dbx_state_trava_tentar "$arquivo" "$comando"
    estado=$?
    [[ $estado -eq 0 ]] && return 0
    if [[ $estado -eq 3 ]]; then
      # O nome sumiu ou a orfa mudou entre as leituras: de novo, na hora.
      repeticoes=$((repeticoes + 1))
      [[ $repeticoes -lt 50 ]] && continue
      # DIV-50: esgotado, recusa como ocupada; nunca segue sem trava.
      DBX_STATE_MOTIVO="trava instavel: o nome mudou a cada tentativa de obte-la; rode de novo depois ou use --esperar N (--wait N)"
      estado=$DBX_STATE_ERRO_CONFLITO
    fi
    if [[ $estado -ne $DBX_STATE_ERRO_CONFLITO || $sondagens -ge $espera ]]; then
      [[ $estado -eq $DBX_STATE_ERRO_CONFLITO && $espera -gt 0 ]] &&
        DBX_STATE_MOTIVO="esperou $espera s; $DBX_STATE_MOTIVO"
      _dbx_state_trava_desfazer_diretorio
      return "$estado"
    fi
    sleep 1
    sondagens=$((sondagens + 1))
    repeticoes=0
  done
}

# dbx_state_trava_liberar — libera agora a trava deste processo (idempotente).
dbx_state_trava_liberar() {
  [[ -n $DBX_STATE_TRAVA ]] || return 0
  dbx_tmp_acao_cancelar "$_dbx_state_trava_acao"
  _dbx_state_trava_acao=''
  _dbx_state_trava_soltar "$DBX_STATE_TRAVA"
}

# dbx_state_trava_descrever <indice> — "o <comando> pid <pid> no host <nome>,
# iniciado em <ISO UTC>" da entrada da listagem, em DBX_STATE_RESULTADO; vazio
# para a ilegivel. So campos validados.
dbx_state_trava_descrever() {
  DBX_STATE_RESULTADO=''
  [[ ${1:-} =~ ^[0-9]+$ && -n ${DBX_STATE_TRAVAS_PID[$1]:-} ]] || return 0
  DBX_STATE_TRAVA_PID=${DBX_STATE_TRAVAS_PID[$1]}
  DBX_STATE_TRAVA_HOST=${DBX_STATE_TRAVAS_HOST[$1]}
  DBX_STATE_TRAVA_INICIO=${DBX_STATE_TRAVAS_INICIO[$1]}
  DBX_STATE_TRAVA_COMANDO=${DBX_STATE_TRAVAS_COMANDO[$1]}
  _dbx_state_trava_quem
}

# dbx_state_trava_examinar <arquivo> — le e classifica UMA trava: estado em
# DBX_STATE_TRAVA_ESTADO (`viva`, `orfa`, `outro-host`, `ilegivel` ou
# `ausente`) e a identidade "pid|host|inicio" em DBX_STATE_RESULTADO (vazia
# para ilegivel e ausente). So le.
dbx_state_trava_examinar() {
  DBX_STATE_RESULTADO=''
  _dbx_state_trava_ler "$1"
  case $? in
    0)
      _dbx_state_trava_classificar
      DBX_STATE_RESULTADO="$DBX_STATE_TRAVA_PID|$DBX_STATE_TRAVA_HOST|$DBX_STATE_TRAVA_INICIO"
      ;;
    2) DBX_STATE_TRAVA_ESTADO='ausente' ;;
    *) DBX_STATE_TRAVA_ESTADO='ilegivel' ;;
  esac
  return 0
}

# dbx_state_travas_listar — uma entrada por `trava-*` (inclusive `.r`) do
# diretorio de estado, com o estado apurado. So le: nao cria o diretorio, nao
# remove e nao retoma nada (RF-71).
dbx_state_travas_listar() {
  local diretorio arquivo tinha_nullglob='nao'
  local -a arquivos=()
  DBX_STATE_TRAVAS_ARQUIVO=() DBX_STATE_TRAVAS_ESTADO=() DBX_STATE_TRAVAS_PID=()
  DBX_STATE_TRAVAS_HOST=() DBX_STATE_TRAVAS_INICIO=() DBX_STATE_TRAVAS_COMANDO=()
  _dbx_state_base || return 0
  diretorio=$DBX_STATE_RESULTADO
  DBX_STATE_RESULTADO=''
  _dbx_state_diretorio_confiavel "$diretorio" || return 0
  shopt -q nullglob && tinha_nullglob='sim'
  shopt -s nullglob
  arquivos=("$diretorio"/trava-*)
  [[ $tinha_nullglob == 'sim' ]] || shopt -u nullglob
  for arquivo in ${arquivos[@]+"${arquivos[@]}"}; do
    _dbx_state_trava_ler "$arquivo"
    case $? in
      2) continue ;;
      0) _dbx_state_trava_classificar ;;
      *) DBX_STATE_TRAVA_ESTADO='ilegivel' ;;
    esac
    DBX_STATE_TRAVAS_ARQUIVO+=("$arquivo")
    DBX_STATE_TRAVAS_ESTADO+=("$DBX_STATE_TRAVA_ESTADO")
    DBX_STATE_TRAVAS_PID+=("$DBX_STATE_TRAVA_PID")
    DBX_STATE_TRAVAS_HOST+=("$DBX_STATE_TRAVA_HOST")
    DBX_STATE_TRAVAS_INICIO+=("$DBX_STATE_TRAVA_INICIO")
    DBX_STATE_TRAVAS_COMANDO+=("$DBX_STATE_TRAVA_COMANDO")
  done
  return 0
}
