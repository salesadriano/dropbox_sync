#!/usr/bin/env bash
# lib/transfer_paralelo.sh — envio de UM arquivo grande em partes simultaneas
# (F-100, etapa 2a; RF-177 a RF-179, RF-181 a RF-184; DIV-358 a DIV-368).
#
# Camada: orquestracao, irma de `lib/transfer`, que a carrega. So o `upload` de
# arquivo regular acima do limiar com `--paralelo N > 1` chega aqui; N=1, arquivo
# abaixo do limiar e entrada padrao seguem EXATAMENTE o caminho sequencial.
#
# SEQUENCIA (contrato exercitado contra o servico real, RSK-98):
#   start    -> `session_type: concurrent`, corpo vazio
#   append   -> partes de 16 MiB, ate N em voo, FORA DE ORDEM; a ultima leva
#               `close=true`; o reenvio de uma parte ja aceita e idempotente
#   finish   -> `offset` = total, corpo vazio, mais o `commit`
#
# AUXILIARES: o mesmo padrao do `sync` paralelo — cada parte vai a um processo
# auxiliar em grupo proprio (`set -m`), que devolve o resultado por arquivo na
# area da transferencia (`lib/tmp`, 0700); o principal registra em `lib/tmp` a
# acao que derruba o grupo de cada auxiliar vivo em todo termino, sinais inclusive.
# O principal e o UNICO que grava o registro de retomada e que escreve o progresso.
#
# LEITURA DA PARTE: `dd bs=4194304 skip=<parte*4> count=4` pelo CAMINHO (sem
# `/dev/fd`, sem `head -c` sobre descritor compartilhado), com tamanho e
# identidade do arquivo conferidos antes e depois, como o caminho sequencial.
#
# CONTENT_HASH: cada auxiliar resume os blocos de 4 MiB da sua parte; o principal
# combina os resumos NA ORDEM das partes (DIV-363 A). Parte confirmada por uma
# execucao anterior e resumida pelo principal, antes do `finish`.
#
# REGISTRO v2 (RF-181, lib/state): sessao, tipo `concurrent`, tamanho da parte,
# total, identidade e o conjunto de partes CONFIRMADAS em intervalos `a-b`. Parte
# em voo nao e registrada: na retomada e reenviada (DIV-367 A).
#
# `429` (DIV-365 A): cada auxiliar espera o seu `Retry-After` pela retentativa de
# `lib/http`, que ANTES da espera cria a marca `p.<i>` na area do auxiliar
# (DBX_HTTP_MARCA_PAUSA); o principal nao despacha parte nova enquanto houver
# marca (pausa durante o `Retry-After`) e, vista a perda de limite, ate as em voo
# terminarem (pausa compartilhada).

[[ -n ${DBX_TRANSFER_PARALELO_CARREGADO:-} ]] && return 0
DBX_TRANSFER_PARALELO_CARREGADO=1

# Parte de rede da sessao concorrente (DIV-359 A): multiplo de 4 MiB.
readonly DBX_TRANSFER_PARALELO_PARTE=16777216
# Codigo interno (nunca sai do processo): "siga pelo caminho sequencial".
readonly _DBX_TRANSFER_SEQUENCIAL=199

# N pedido pelo comando (`upload`); 1 = caminho sequencial de sempre.
DBX_TRANSFER_PARALELO=1

_DBX_TRANSFER_PAR_PIDS=()
_DBX_TRANSFER_PAR_CONF=()
_DBX_TRANSFER_PAR_PASTA=''
_DBX_TRANSFER_PAR_SESSAO=''
_DBX_TRANSFER_PAR_ORIGEM=''
_DBX_TRANSFER_PAR_TOTAL=0
_DBX_TRANSFER_PAR_PARTES=0
_DBX_TRANSFER_PAR_N=1
_DBX_TRANSFER_PAR_INTERVALOS='-'
_DBX_TRANSFER_PAR_SESSAO_CRUA=''
_DBX_TRANSFER_PAR_CRIADO=''
_DBX_TRANSFER_PAR_CONFIRMADOS=0
_DBX_TRANSFER_PAR_TAG=''
_DBX_TRANSFER_PAR_FALHA_CLASSE=''
_DBX_TRANSFER_PAR_FALHA_MOTIVO=''

# _dbx_transfer_par_resumir <indice> <arquivo_da_parte> — resumos SHA-256 dos
# blocos de 4 MiB da parte, uma linha `<hex> <bytes>` por bloco, em hash.<indice>.
_dbx_transfer_par_resumir() {
  local i=$1 parte=$2 pasta=$_DBX_TRANSFER_PAR_PASTA k=0 bytes hex tam
  local bloco="$pasta/bloco.$i"
  : >"$pasta/hash.$i.parcial"
  tam=$(wc -c <"$parte") || return 1
  tam=${tam//[^0-9]/}
  while ((k * DBX_TRANSFER_TAMANHO_PARTE < tam)); do
    dd if="$parte" of="$bloco" bs="$DBX_TRANSFER_TAMANHO_PARTE" skip="$k" count=1 2>/dev/null || return 1
    bytes=$(wc -c <"$bloco") || return 1
    bytes=${bytes//[^0-9]/}
    hex=$(_dbx_hash_sha256_hex <"$bloco") || return 1
    printf '%s %s\n' "$hex" "$bytes" >>"$pasta/hash.$i.parcial"
    k=$((k + 1))
  done
  rm -f -- "$bloco"
  mv -f -- "$pasta/hash.$i.parcial" "$pasta/hash.$i"
}

# _dbx_transfer_par_extrair <indice> <destino> — a parte por `dd` pelo caminho,
# conferida em tamanho. Falha publica classe e motivo.
_dbx_transfer_par_extrair() {
  local i=$1 destino=$2 esperado tam
  esperado=$_DBX_TRANSFER_PAR_TOTAL
  esperado=$((esperado - i * DBX_TRANSFER_PARALELO_PARTE))
  ((esperado > DBX_TRANSFER_PARALELO_PARTE)) && esperado=$DBX_TRANSFER_PARALELO_PARTE
  dd if="$_DBX_TRANSFER_PAR_ORIGEM" of="$destino" bs="$DBX_TRANSFER_TAMANHO_PARTE" \
    skip=$((i * DBX_TRANSFER_PARALELO_PARTE / DBX_TRANSFER_TAMANHO_PARTE)) \
    count=$((DBX_TRANSFER_PARALELO_PARTE / DBX_TRANSFER_TAMANHO_PARTE)) 2>/dev/null || {
    _dbx_transfer_falhar nao_concluida "falha ao ler a parte $i da origem; nada foi publicado no destino"
    return $?
  }
  tam=$(wc -c <"$destino") || tam=''
  tam=${tam//[^0-9]/}
  if [[ -z $tam || $tam -ne $esperado ]]; then
    _dbx_transfer_falhar nao_concluida \
      "a parte $i da origem tem $tam bytes e eram esperados $esperado: o arquivo mudou durante o envio; nada foi publicado no destino"
    return $?
  fi
  return 0
}

# _dbx_transfer_par_banda — DIV-362 A: o teto total e dividido por N, e cada
# auxiliar leva a sua parte, nunca abaixo do piso de 2 x a velocidade minima.
_dbx_transfer_par_banda() {
  local total=${_DBX_HTTP_LIMITE_BANDA:-} parte piso
  [[ $total =~ ^[0-9]+$ ]] || return 0
  piso=$((2 * ${DBX_HTTP_EFETIVO[DBX_HTTP_VELOCIDADE_MINIMA_BPS]:-1024}))
  parte=$((total / _DBX_TRANSFER_PAR_N))
  ((parte < piso)) && parte=$piso
  dbx_http_limite_banda "$parte"
}

# _dbx_transfer_par_aux <indice> <close> — corpo do auxiliar: extrai, resume e
# envia UMA parte. Resultado em r.<indice>: status, classe, motivo, `429`, tag.
_dbx_transfer_par_aux() {
  local i=$1 fechar=$2 pasta=$_DBX_TRANSFER_PAR_PASTA parte status=0 tag='' antes_429=${DBX_HTTP_LIMITES_429:-0}
  local deslocamento=$((i * DBX_TRANSFER_PARALELO_PARTE)) argumento
  parte="$pasta/parte.$i"
  # shellcheck disable=SC2034  # lido por lib/http, no mesmo processo auxiliar
  DBX_HTTP_MARCA_PAUSA="$pasta/p.$i"
  _dbx_transfer_par_banda
  DBX_TRANSFER_CLASSE='' DBX_TRANSFER_MOTIVO=''
  dbx_debug_linha upload parte="$i" deslocamento="$deslocamento" close="$fechar"
  if _dbx_transfer_par_extrair "$i" "$parte" && _dbx_transfer_par_resumir "$i" "$parte"; then
    argumento="{\"cursor\":{\"session_id\":\"$_DBX_TRANSFER_PAR_SESSAO\",\"offset\":$deslocamento},\"close\":$fechar}"
    if ! _dbx_transfer_emitir "$DBX_TRANSFER_URL_ANEXAR" "$argumento" "$parte" sim; then
      _dbx_transfer_tag_sessao
      tag=$_DBX_TRANSFER_TAG
      _dbx_transfer_falha_de_parte "$deslocamento"
      status=1
    fi
  else
    status=1
  fi
  rm -f -- "$parte"
  dbx_debug_linha upload parte="$i" resultado="$([[ $status -eq 0 ]] && echo ok || echo falha)"
  printf '%s\n%s\n%s\n%s\n%s\n' "$status" "${DBX_TRANSFER_CLASSE:-}" "${DBX_TRANSFER_MOTIVO:-}" \
    "$((${DBX_HTTP_LIMITES_429:-0} - antes_429))" "$tag" >"$pasta/r.$i.parcial" &&
    mv -f -- "$pasta/r.$i.parcial" "$pasta/r.$i"
}

# _dbx_transfer_par_encerrar — acao de `lib/tmp`: derruba o grupo de cada
# auxiliar vivo e o espera (5 s, depois SIGKILL); nenhum processo orfao.
_dbx_transfer_par_encerrar() {
  local pid k vivo
  for pid in ${_DBX_TRANSFER_PAR_PIDS[@]+"${_DBX_TRANSFER_PAR_PIDS[@]}"}; do
    [[ -n $pid ]] || continue
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM -- "$pid" 2>/dev/null || :
  done
  for ((k = 0; k < 50; k++)); do
    vivo='nao'
    for pid in ${_DBX_TRANSFER_PAR_PIDS[@]+"${_DBX_TRANSFER_PAR_PIDS[@]}"}; do
      [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && vivo='sim'
    done
    [[ $vivo == 'sim' ]] || break
    sleep 0.1
  done
  for pid in ${_DBX_TRANSFER_PAR_PIDS[@]+"${_DBX_TRANSFER_PAR_PIDS[@]}"}; do
    [[ -n $pid ]] || continue
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL -- "$pid" 2>/dev/null || :
  done
  _DBX_TRANSFER_PAR_PIDS=()
}

# _dbx_transfer_par_intervalos — conjunto confirmado em `a-b,c-d` (ou `-`).
_dbx_transfer_par_intervalos() {
  local i ini='' fim='' saida=''
  for ((i = 0; i < _DBX_TRANSFER_PAR_PARTES; i++)); do
    if [[ ${_DBX_TRANSFER_PAR_CONF[i]:-} == 1 ]]; then
      [[ -n $ini ]] || ini=$i
      fim=$i
    elif [[ -n $ini ]]; then
      saida+="${saida:+,}$ini-$fim"
      ini=''
    fi
  done
  [[ -n $ini ]] && saida+="${saida:+,}$ini-$fim"
  _DBX_TRANSFER_PAR_INTERVALOS=${saida:--}
}

# _dbx_transfer_par_gravar <identidade> <criado> — registro v2 (RF-181). Falha
# ao gravar nao aborta o envio: segue sem retomada, com aviso.
_dbx_transfer_par_gravar() {
  [[ $DBX_TRANSFER_RETOMADA_ATIVA == 'sim' ]] || return 0
  _dbx_transfer_par_intervalos
  dbx_state_retomada_gravar_partes "$_DBX_TRANSFER_PAR_SESSAO_CRUA" concurrent "$DBX_TRANSFER_PARALELO_PARTE" \
    "$_DBX_TRANSFER_PAR_TOTAL" "$1" "$2" "$_DBX_TRANSFER_PAR_INTERVALOS" >/dev/null 2>&1 && return 0
  _dbx_transfer_ret_desligar 'sem retomada nesta execucao: o registro de retomada nao pode ser gravado'
  return 0
}

# _dbx_transfer_par_bytes_confirmados — bytes das partes confirmadas.
_dbx_transfer_par_bytes_confirmados() {
  local i soma=0 tam
  for ((i = 0; i < _DBX_TRANSFER_PAR_PARTES; i++)); do
    [[ ${_DBX_TRANSFER_PAR_CONF[i]:-} == 1 ]] || continue
    tam=$((_DBX_TRANSFER_PAR_TOTAL - i * DBX_TRANSFER_PARALELO_PARTE))
    ((tam > DBX_TRANSFER_PARALELO_PARTE)) && tam=$DBX_TRANSFER_PARALELO_PARTE
    soma=$((soma + tam))
  done
  _DBX_TRANSFER_PAR_CONFIRMADOS=$soma
}

# _dbx_transfer_par_carregar_conjunto <a-b,c-d> — preenche as partes confirmadas.
_dbx_transfer_par_carregar_conjunto() {
  local item a b i
  _DBX_TRANSFER_PAR_CONF=()
  for item in ${1//,/ }; do
    [[ $item == '-' ]] && continue
    a=$((10#${item%-*})) b=$((10#${item#*-}))
    ((b < _DBX_TRANSFER_PAR_PARTES && a <= b)) || return 1
    for ((i = a; i <= b; i++)); do _DBX_TRANSFER_PAR_CONF[i]=1; done
  done
  return 0
}

# dbx_transfer_sessao_paralela <commit> <origem> — devolve 0, a classe da falha,
# ou _DBX_TRANSFER_SEQUENCIAL quando o envio deve seguir pelo caminho
# sequencial (registro v1 a retomar; servico que recusa a sessao concorrente).
dbx_transfer_sessao_paralela() {
  local commit=${1-} origem=${2-} estado mascara_anterior carregado
  DBX_TRANSFER_CLASSE='' DBX_TRANSFER_MOTIVO='' DBX_TRANSFER_CONTENT_HASH=''
  # shellcheck disable=SC2034  # canais publicos, lidos por commands/upload
  DBX_TRANSFER_BYTES=0 DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'
  DBX_TRANSFER_RETOMADA='nao' DBX_TRANSFER_RETOMADO_DE=0
  _DBX_TRANSFER_RET_REMOVER='nao' _DBX_TRANSFER_RET_PODE_RECOMECAR='nao' _DBX_TRANSFER_RET_PRIMEIRA='nao'
  [[ -n $commit && -n $origem && -f $origem ]] || return "$_DBX_TRANSFER_SEQUENCIAL"
  [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || return "$_DBX_TRANSFER_SEQUENCIAL"

  _DBX_TRANSFER_PAR_ORIGEM=$origem
  _DBX_TRANSFER_PAR_TOTAL=$DBX_TRANSFER_TAMANHO
  _DBX_TRANSFER_PAR_PARTES=$(((DBX_TRANSFER_TAMANHO + DBX_TRANSFER_PARALELO_PARTE - 1) / DBX_TRANSFER_PARALELO_PARTE))
  _DBX_TRANSFER_PAR_N=$DBX_TRANSFER_PARALELO
  ((_DBX_TRANSFER_PAR_N <= _DBX_TRANSFER_PAR_PARTES)) || _DBX_TRANSFER_PAR_N=$_DBX_TRANSFER_PAR_PARTES
  _DBX_TRANSFER_PAR_CONF=()
  _DBX_TRANSFER_PAR_SESSAO_CRUA=''
  _DBX_TRANSFER_PAR_CRIADO=''
  carregado='nao'

  # Registro anterior (RF-181): v1 e do caminho sequencial (DIV-368 A); v2 so
  # serve se o arquivo e a configuracao forem os mesmos.
  if [[ $DBX_TRANSFER_RETOMADA_ATIVA == 'sim' ]]; then
    dbx_state_retomada_carregar
    case $? in
      0)
        if [[ $DBX_STATE_RETOMADA_VERSAO_LIDA -eq 1 ]]; then
          return "$_DBX_TRANSFER_SEQUENCIAL"
        fi
        if [[ ${DBX_STATE_RETOMADA_CAMPOS[4]} == "$DBX_TRANSFER_RETOMADA_IDENTIDADE" &&
          ${DBX_STATE_RETOMADA_CAMPOS[3]} -eq $_DBX_TRANSFER_PAR_TOTAL &&
          ${DBX_STATE_RETOMADA_CAMPOS[2]} -eq $DBX_TRANSFER_PARALELO_PARTE ]] &&
          _dbx_transfer_par_carregar_conjunto "${DBX_STATE_RETOMADA_CAMPOS[6]}"; then
          carregado='sim'
          _DBX_TRANSFER_PAR_SESSAO_CRUA=${DBX_STATE_RETOMADA_CAMPOS[0]}
          _DBX_TRANSFER_PAR_CRIADO=${DBX_STATE_RETOMADA_CAMPOS[5]}
        else
          dbx_state_retomada_remover
          _DBX_TRANSFER_PAR_CONF=()
          dbx_debug_linha upload retomada=descartada motivo=arquivo-alterado
          DBX_TRANSFER_RETOMADA='recomecada'
          _dbx_transfer_avisar 'arquivo local mudou desde a interrupcao; o envio recomeca do zero'
        fi
        ;;
      2)
        _dbx_transfer_avisar "estado de retomada descartado: $DBX_STATE_MOTIVO"
        dbx_debug_linha upload retomada=descartada motivo=estado-invalido
        DBX_TRANSFER_RETOMADA='recomecada'
        ;;
      3)
        dbx_state_retomada_soltar
        DBX_TRANSFER_RETOMADA_ATIVA='nao'
        _dbx_transfer_avisar 'sem retomada nesta execucao: o registro de retomada nao e um arquivo deste usuario'
        dbx_debug_linha upload retomada=descartada motivo=estado-invalido
        ;;
    esac
  fi

  mascara_anterior=$(umask)
  umask 077
  dbx_tmp_area transfer || {
    umask "$mascara_anterior"
    _dbx_transfer_falhar configuracao 'area temporaria indisponivel para o envio em partes'
    return $?
  }
  DBX_TRANSFER_AREA_TEMP=$DBX_TMP_CAMINHO
  _DBX_TRANSFER_PAR_PASTA=$DBX_TRANSFER_AREA_TEMP

  _dbx_transfer_par_conduzir "$commit" "$carregado"
  estado=$?

  if [[ $DBX_TRANSFER_RETOMADA_ATIVA == 'sim' ]]; then
    case $estado:$_DBX_TRANSFER_RET_REMOVER in
      0:*) dbx_state_retomada_remover ;;
      *:sim) dbx_state_retomada_remover ;;
      $_DBX_TRANSFER_SEQUENCIAL:*) ;;
      *) ;; # DIV-364 B: falha de parte preserva o registro para a retomada
    esac
    # Fallback sequencial segue com a trava; qualquer outro termino a solta.
    if [[ $estado -ne $_DBX_TRANSFER_SEQUENCIAL ]]; then
      dbx_state_retomada_soltar
      DBX_TRANSFER_RETOMADA_ATIVA='nao'
    fi
  fi
  _dbx_transfer_remover_area
  umask "$mascara_anterior"
  return $estado
}

# _dbx_transfer_par_conduzir <commit> <carregado> — start (ou retomada), partes
# simultaneas, conferencias, `finish` e resumo.
_dbx_transfer_par_conduzir() {
  local commit=$1 carregado=$2 pasta=$_DBX_TRANSFER_PAR_PASTA
  local total=$_DBX_TRANSFER_PAR_TOTAL partes=$_DBX_TRANSFER_PAR_PARTES n=$_DBX_TRANSFER_PAR_N
  local identidade='' i vivos marcada pausa='nao' falhou='nao' resultado acao_id='' recomecou='nao'
  local st cl mo l429 tag argumento hex bytes pendentes

  dbx_hash_identidade "$_DBX_TRANSFER_PAR_ORIGEM" && identidade=$DBX_HASH_IDENTIDADE
  [[ -n $identidade ]] || {
    _dbx_transfer_falhar nao_concluida 'identidade do arquivo local indeterminada'
    return $?
  }
  : >"$pasta/vazio" || {
    _dbx_transfer_falhar configuracao 'area temporaria nao gravavel'
    return $?
  }
  dbx_hash_acumular_iniciar || {
    _dbx_transfer_falhar configuracao 'utilitario de resumo SHA-256 indisponivel'
    return $?
  }

  while :; do
    if [[ $carregado == 'sim' ]]; then
      _dbx_transfer_par_bytes_confirmados
      # shellcheck disable=SC2034  # canais publicos, lidos por commands/upload
      DBX_TRANSFER_RETOMADA='sim'
      # shellcheck disable=SC2034
      DBX_TRANSFER_RETOMADO_DE=$_DBX_TRANSFER_PAR_CONFIRMADOS
      dbx_debug_linha upload retomada=encontrada deslocamento="$_DBX_TRANSFER_PAR_CONFIRMADOS"
    else
      _DBX_TRANSFER_PAR_CONF=()
      _dbx_transfer_emitir "$DBX_TRANSFER_URL_INICIAR" '{"close":false,"session_type":{".tag":"concurrent"}}' "$pasta/vazio" nao || {
        # DIV-361 B: servico que recusa o tipo concorrente -> sequencial, com aviso.
        if [[ ${DBX_HTTP_CODIGO:-0} =~ ^4[0-9][0-9]$ && ${DBX_HTTP_CODIGO} != 429 ]]; then
          _dbx_transfer_avisar 'o servico recusou a sessao concorrente; o envio segue em sequencia, sem partes simultaneas'
          dbx_debug_linha upload paralelo=recusado motivo=sessao-concorrente
          return "$_DBX_TRANSFER_SEQUENCIAL"
        fi
        _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
          "inicio de sessao recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
        return $?
      }
      _dbx_transfer_ler_campo session_id || {
        _dbx_transfer_falhar erro_remoto 'inicio de sessao sem identificador de sessao'
        return $?
      }
      _DBX_TRANSFER_PAR_SESSAO_CRUA=$DBX_TRANSFER_LIDO
      printf -v _DBX_TRANSFER_PAR_CRIADO '%(%s)T' -1
      _dbx_transfer_par_gravar "$identidade" "$_DBX_TRANSFER_PAR_CRIADO"
    fi
    dbx_json_escapar_cadeia "$_DBX_TRANSFER_PAR_SESSAO_CRUA"
    _DBX_TRANSFER_PAR_SESSAO=$DBX_JSON_ESCAPADO
    # shellcheck disable=SC2034  # canais publicos esvaziados por quem os encheu
    DBX_JSON_ESCAPADO='' DBX_TRANSFER_LIDO=''
    dbx_debug_linha upload paralelo="$n" partes="$partes" parte_tamanho="$DBX_TRANSFER_PARALELO_PARTE"
    _dbx_transfer_par_bytes_confirmados
    dbx_progress_arquivo_avancar "$_DBX_TRANSFER_PAR_CONFIRMADOS"

    _DBX_TRANSFER_PAR_PIDS=()
    _DBX_TRANSFER_PAR_FALHA_CLASSE='' _DBX_TRANSFER_PAR_FALHA_MOTIVO='' _DBX_TRANSFER_PAR_TAG=''
    falhou='nao' pausa='nao'
    dbx_tmp_acao_registrar _dbx_transfer_par_encerrar
    acao_id=$DBX_TMP_ID
    set -m
    while :; do
      # Despacho: ate N em voo, partes pendentes em ordem crescente.
      vivos=0
      for ((i = 0; i < partes; i++)); do [[ ${_DBX_TRANSFER_PAR_CONF[i]:-} == v ]] && vivos=$((vivos + 1)); done
      [[ $pausa == 'sim' && $vivos -eq 0 ]] && pausa='nao'
      # Pausa vigente: algum auxiliar recebeu 429 e ainda nao terminou (DIV-365 A).
      marcada='nao'
      compgen -G "$pasta/p.*" >/dev/null && marcada='sim'
      if [[ $falhou == 'nao' && $pausa == 'nao' && $marcada == 'nao' ]]; then
        for ((i = 0; i < partes && vivos < n; i++)); do
          [[ -z ${_DBX_TRANSFER_PAR_CONF[i]:-} ]] || continue
          local destino_dbg='' fechar=false
          ((i == partes - 1)) && fechar=true
          [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] && destino_dbg="$pasta/dbg.$i"
          DBX_DEBUG_DESTINO=$destino_dbg _dbx_transfer_par_aux "$i" "$fechar" </dev/null >/dev/null 2>&1 &
          _DBX_TRANSFER_PAR_PIDS[i]=$!
          _DBX_TRANSFER_PAR_CONF[i]=v
          vivos=$((vivos + 1))
        done
      fi
      # Coleta do que terminou.
      for ((i = 0; i < partes; i++)); do
        [[ ${_DBX_TRANSFER_PAR_CONF[i]:-} == v ]] || continue
        resultado="$pasta/r.$i"
        if [[ ! -e $resultado ]]; then
          if kill -0 "${_DBX_TRANSFER_PAR_PIDS[i]}" 2>/dev/null; then continue; fi
          sleep 0.05
          [[ -e $resultado ]] || printf '1\nnao_concluida\nauxiliar encerrado sem resultado\n0\n\n' >"$resultado"
        fi
        st=1 cl='' mo='' l429=0 tag=''
        {
          IFS= read -r st
          IFS= read -r cl
          IFS= read -r mo
          IFS= read -r l429
          IFS= read -r tag
        } <"$resultado"
        rm -f -- "$resultado" "$pasta/p.$i"
        _DBX_TRANSFER_PAR_PIDS[i]=''
        [[ $l429 =~ ^[0-9]{1,9}$ ]] || l429=0
        if ((l429 > 0)); then
          dbx_debug_somar_429 "$l429"
          pausa='sim'
        fi
        if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' && -s $pasta/dbg.$i ]]; then
          dbx_debug_descarregar "$pasta/dbg.$i"
        fi
        if [[ $st == '0' ]]; then
          _DBX_TRANSFER_PAR_CONF[i]=1
          _dbx_transfer_par_gravar "$identidade" "$_DBX_TRANSFER_PAR_CRIADO"
          _dbx_transfer_par_bytes_confirmados
          dbx_progress_arquivo_avancar "$_DBX_TRANSFER_PAR_CONFIRMADOS"
        else
          _DBX_TRANSFER_PAR_CONF[i]=''
          if [[ $falhou == 'nao' ]]; then
            falhou='sim'
            _DBX_TRANSFER_PAR_FALHA_CLASSE=${cl:-nao_concluida}
            _DBX_TRANSFER_PAR_FALHA_MOTIVO=$mo
            _DBX_TRANSFER_PAR_TAG=$tag
          fi
        fi
      done
      vivos=0 pendentes=0
      for ((i = 0; i < partes; i++)); do
        [[ ${_DBX_TRANSFER_PAR_CONF[i]:-} == v ]] && vivos=$((vivos + 1))
        [[ -z ${_DBX_TRANSFER_PAR_CONF[i]:-} ]] && pendentes=$((pendentes + 1))
      done
      # Nada em voo e nada a despachar (ou falha definitiva): fim do laco.
      if ((vivos == 0)); then
        if ((pendentes == 0)) || [[ $falhou == 'sim' ]]; then break; fi
      else
        wait -n 2>/dev/null || sleep 0.05
      fi
    done
    wait 2>/dev/null || :
    set +m
    _DBX_TRANSFER_PAR_PIDS=()
    dbx_tmp_acao_cancelar "$acao_id"

    if [[ $falhou == 'sim' ]]; then
      # Sessao expirada na retomada: recomeca do zero, uma vez (DIV-367 A).
      if [[ $carregado == 'sim' && $recomecou == 'nao' &&
        ($_DBX_TRANSFER_PAR_TAG == 'not_found' || $_DBX_TRANSFER_PAR_TAG == 'closed') ]]; then
        recomecou='sim' carregado='nao'
        dbx_state_retomada_remover
        dbx_debug_linha upload retomada=descartada motivo=sessao-expirada
        _dbx_transfer_avisar 'sessao de envio expirada no servidor; recomecando'
        # shellcheck disable=SC2034  # canal publico, lido por commands/upload
        DBX_TRANSFER_RETOMADA='recomecada'
        # shellcheck disable=SC2034
        DBX_TRANSFER_RETOMADO_DE=0
        rm -f -- "$pasta"/r.* "$pasta"/hash.* 2>/dev/null
        continue
      fi
      # DIV-364 B: nada novo despachado, sem `finish`, registro preservado.
      DBX_TRANSFER_CLASSE=$_DBX_TRANSFER_PAR_FALHA_CLASSE
      DBX_TRANSFER_MOTIVO=$_DBX_TRANSFER_PAR_FALHA_MOTIVO
      return "$(dbx_errors_codigo_saida "${DBX_TRANSFER_CLASSE:-nao_concluida}")"
    fi
    break
  done

  # Conferencias antes do `finish`: tamanho e identidade do arquivo, como no
  # caminho sequencial (RF-103(d)).
  if ! dbx_transfer_tamanho_de_arquivo "$_DBX_TRANSFER_PAR_ORIGEM" || [[ $DBX_TRANSFER_TAMANHO -ne $total ]] ||
    ! dbx_hash_identidade "$_DBX_TRANSFER_PAR_ORIGEM" || [[ $DBX_HASH_IDENTIDADE != "$identidade" ]]; then
    _DBX_TRANSFER_RET_REMOVER='sim'
    _dbx_transfer_falhar nao_concluida \
      "o arquivo mudou durante o envio: tinha $total bytes no inicio; nada foi publicado no destino"
    return $?
  fi

  # content_hash (DIV-363 A): resumos dos blocos das partes, em ordem. Parte
  # confirmada em execucao anterior nao tem resumo desta execucao: calcula-se aqui.
  for ((i = 0; i < partes; i++)); do
    if [[ ! -e $pasta/hash.$i ]]; then
      if ! _dbx_transfer_par_extrair "$i" "$pasta/parte.$i" || ! _dbx_transfer_par_resumir "$i" "$pasta/parte.$i"; then
        return "$(dbx_errors_codigo_saida "${DBX_TRANSFER_CLASSE:-nao_concluida}")"
      fi
      rm -f -- "$pasta/parte.$i"
    fi
    while read -r hex bytes; do
      dbx_hash_acumular_resumo "$hex" "$bytes" || {
        _dbx_transfer_falhar integridade 'o resumo local do arquivo enviado nao pode ser calculado; a integridade nao foi conferida'
        return $?
      }
    done <"$pasta/hash.$i"
  done
  dbx_hash_acumular_encerrar "$pasta/trabalho" || {
    _dbx_transfer_falhar integridade 'o resumo local do arquivo enviado nao pode ser calculado; a integridade nao foi conferida'
    return $?
  }
  DBX_TRANSFER_CONTENT_HASH=$DBX_HASH_RESULTADO

  argumento="{\"cursor\":{\"session_id\":\"$_DBX_TRANSFER_PAR_SESSAO\",\"offset\":$total},\"commit\":$commit}"
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_CONCLUIR" "$argumento" "$pasta/vazio" nao || {
    _dbx_transfer_conclusao_recusada
    return $?
  }
  # shellcheck disable=SC2034  # canal publico, lido por commands/upload
  DBX_TRANSFER_BYTES=$total
  if _dbx_transfer_ler_campo content_hash; then
    dbx_transfer_conferir_resumo "$DBX_TRANSFER_CONTENT_HASH" "$DBX_TRANSFER_LIDO" || return $?
  else
    dbx_transfer_conferir_resumo "$DBX_TRANSFER_CONTENT_HASH" || return $?
  fi
  return 0
}
