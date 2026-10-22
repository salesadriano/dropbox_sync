#!/usr/bin/env bash
# lib/progress.sh — controle, formatacao e emissao de progresso em tempo real.
#
# CANAL DE SAIDA ESTREITO (RF-28, RF-32):
#   Toda informacao de progresso e emitida EXCLUSIVAMENTE pelo descritor stderr (2).
#   A saida padrao (stdout, descritor 1) e estritamente preservada para o modelo
#   estruturado (JSON, chave-valor, terminador nulo) ou para o fluxo de conteudo
#   binario (ex.: download para stdout).
#
# SOBRECARGA E DETECCAO DE TERMINAL (RNF-19):
#   --progresso / --progress / -p forca ativacao (DBX_CLI_PROGRESSO='sim').
#   --sem-progresso / --no-progress forca desativacao (DBX_CLI_PROGRESSO='nao').
#   Modo padrao ('auto'): ativo se stderr for terminal ([ -t 2 ]), inativo caso
#   contrario, garantindo silencio em scripts e pipes sem custo desnecessario.

[[ -n ${DBX_PROGRESS_CARREGADO:-} ]] && return 0
DBX_PROGRESS_CARREGADO=1

# dbx_progress_ativo — verifica se a emissao de progresso esta habilitada.
dbx_progress_ativo() {
  case ${DBX_CLI_PROGRESSO:-auto} in
    sim) return 0 ;;
    nao) return 1 ;;
    auto | *)
      if [[ -t 2 ]]; then
        return 0
      fi
      return 1
      ;;
  esac
}

DBX_PROGRESS_FORMATADO=''
DBX_PROGRESS_BARRA=''

# dbx_progress_formatar_bytes <n> [var_destino] — formatacao humana em KiB/MiB/GiB sem comandos externos.
dbx_progress_formatar_bytes() {
  local valor=${1:-0} unidade=0
  local -a nomes=(B KiB MiB GiB TiB PiB)
  if [[ ! $valor =~ ^[0-9]+$ ]]; then
    DBX_PROGRESS_FORMATADO="$valor"
  else
    while [[ $valor -ge 1024 && $unidade -lt 5 ]]; do
      valor=$((valor / 1024))
      unidade=$((unidade + 1))
    done
    DBX_PROGRESS_FORMATADO="$valor ${nomes[unidade]}"
  fi

  if [[ $# -ge 2 && -n $2 ]]; then
    printf -v "$2" '%s' "$DBX_PROGRESS_FORMATADO"
  else
    printf '%s' "$DBX_PROGRESS_FORMATADO"
  fi
}

# dbx_progress_barra_gerar <percentual> [largura] [var_destino] —
# constroi barra grafica proporcional delimitada por colchetes.
dbx_progress_barra_gerar() {
  local pct=${1:-0} largura=${2:-20}
  if [[ ! $pct =~ ^-?[0-9]+$ ]]; then
    pct=0
  fi
  if [[ ! $largura =~ ^[0-9]+$ || $largura -le 0 ]]; then
    largura=20
  fi

  if [[ $pct -lt 0 ]]; then
    pct=0
  elif [[ $pct -gt 100 ]]; then
    pct=100
  fi

  local preenchido=$(( (pct * largura) / 100 ))
  local vazio=$(( largura - preenchido ))
  local bloco_cheio='#' bloco_vazio='-'

  # Deteccao de suporte UTF-8 para exibicao rica em terminal compativel
  if [[ ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} =~ [Uu][Tt][Ff]-?8 ]]; then
    bloco_cheio='█'
    bloco_vazio='░'
  fi

  local str_p='' str_v='' i
  for ((i = 0; i < preenchido; i++)); do
    str_p+="$bloco_cheio"
  done
  for ((i = 0; i < vazio; i++)); do
    str_v+="$bloco_vazio"
  done

  DBX_PROGRESS_BARRA="[${str_p}${str_v}]"
  if [[ $# -ge 3 && -n $3 ]]; then
    printf -v "$3" '%s' "$DBX_PROGRESS_BARRA"
  else
    printf '%s' "$DBX_PROGRESS_BARRA"
  fi
}

# dbx_progress_mensagem <texto> — emite mensagem de progresso em stderr.
dbx_progress_mensagem() {
  dbx_progress_ativo || return 0
  printf '%s\n' "$1" >&2
}

# dbx_progress_barra <rotulo> <bytes_atuais> [bytes_totais] [detalhe] —
# emite barra de progresso grafica formatada em stderr.
dbx_progress_barra() {
  dbx_progress_ativo || return 0
  local rotulo=${1:-progresso} atuais=${2:-0} totais=${3:-0} detalhe=${4:-}
  local str_atuais='' str_totais='' str_barra=''
  dbx_progress_formatar_bytes "$atuais" str_atuais
  if [[ $totais =~ ^[0-9]+$ && $totais -gt 0 ]]; then
    dbx_progress_formatar_bytes "$totais" str_totais
    local pct=$(( (atuais * 100) / totais ))
    dbx_progress_barra_gerar "$pct" 20 str_barra
    local str_pct=''
    if [[ $atuais -gt 0 && $pct -eq 0 ]]; then
      local centesimos=$(( (atuais * 10000) / totais ))
      if [[ $centesimos -eq 0 ]]; then
        str_pct='<0.01%'
      else
        str_pct=$(printf '0.%02d%%' "$((centesimos % 100))")
      fi
    else
      str_pct=$(printf '%3d%%' "$pct")
    fi
    if [[ -n $detalhe ]]; then
      printf '[%s] %s %s %s / %s (%s)\n' "$rotulo" "$str_barra" "$str_pct" "$str_atuais" "$str_totais" "$detalhe" >&2
    else
      printf '[%s] %s %s %s / %s\n' "$rotulo" "$str_barra" "$str_pct" "$str_atuais" "$str_totais" >&2
    fi
  else
    if [[ -n $detalhe ]]; then
      printf '[%s] %s (%s)\n' "$rotulo" "$str_atuais" "$detalhe" >&2
    else
      printf '[%s] %s\n' "$rotulo" "$str_atuais" >&2
    fi
  fi
}

# dbx_progress_etapa <atual> <total> <acao> <item> [pct_item] — emite marcador de etapa ordenada com barra grafica.
# A barra grafica exibe o progresso do arquivo/item atual (0% a 100%).
# O percentual entre parenteses continua exibindo o progresso do processo global (atual/total).
dbx_progress_etapa() {
  dbx_progress_ativo || return 0
  local atual=${1:-0} total=${2:-0} acao=${3:-processando} item=${4:-}
  local pct_item=${5:-}

  if [[ -n $pct_item && $pct_item =~ ^-?[0-9]+$ ]]; then
    :
  elif [[ $atual -eq 0 ]]; then
    pct_item=0
  else
    pct_item=100
  fi

  local str_barra=''
  dbx_progress_barra_gerar "$pct_item" 15 str_barra
  # RF-147(b): o contador do plano fica em [i/N]; o percentual global saiu da linha.
  printf '[%d/%d] %s: %s %s\n' "$atual" "$total" "$acao" "$item" "$str_barra" >&2
}

# dbx_progress_transferencia <rotulo> <bytes_atuais> [bytes_totais] [detalhe] —
# emite progresso com bytes, percentual e barra grafica.
dbx_progress_transferencia() {
  dbx_progress_ativo || return 0
  local rotulo=${1:-transferencia} atuais=${2:-0} totais=${3:-0} detalhe=${4:-}
  local str_atuais='' str_totais='' str_barra=''
  dbx_progress_formatar_bytes "$atuais" str_atuais
  if [[ $totais =~ ^[0-9]+$ && $totais -gt 0 ]]; then
    dbx_progress_formatar_bytes "$totais" str_totais
    local pct=$(( (atuais * 100) / totais ))
    dbx_progress_barra_gerar "$pct" 20 str_barra
    local str_pct=''
    if [[ $atuais -gt 0 && $pct -eq 0 ]]; then
      local centesimos=$(( (atuais * 10000) / totais ))
      if [[ $centesimos -eq 0 ]]; then
        str_pct='<0.01%'
      else
        str_pct=$(printf '0.%02d%%' "$((centesimos % 100))")
      fi
    else
      str_pct="${pct}%"
    fi
    if [[ -n $detalhe ]]; then
      printf '[%s] %s: %s / %s (%s) %s\n' "$rotulo" "$detalhe" "$str_atuais" "$str_totais" "$str_pct" "$str_barra" >&2
    else
      printf '[%s] %s / %s (%s) %s\n' "$rotulo" "$str_atuais" "$str_totais" "$str_pct" "$str_barra" >&2
    fi
  else
    if [[ -n $detalhe ]]; then
      printf '[%s] %s: %s\n' "$rotulo" "$detalhe" "$str_atuais" >&2
    else
      printf '[%s] %s\n' "$rotulo" "$str_atuais" >&2
    fi
  fi
}

# ---------------------------------------------------------------------------
# Progresso por arquivo (F-49; RF-140 a RF-147)
# ---------------------------------------------------------------------------
# Uma linha por arquivo: `[i/N] acao: item [barra] pct% feitos / total`. Com
# terminal ela e reescrita no lugar (`\r`); sem terminal cada atualizacao e uma
# linha nova (RF-142). Barra e percentual medem so o arquivo em curso. Tudo sai
# em stderr e nada roda com o progresso inativo (RF-145(c)).
#
# Semente de teste: DBX_PROGRESS_TERMINAL=sim|nao forca a deteccao de terminal.

_DBX_PRG_ATIVO='nao'
_DBX_PRG_ABERTO='nao'
_DBX_PRG_CONCLUIDO='nao'
_DBX_PRG_CAB=''
_DBX_PRG_ITEM=''
_DBX_PRG_TOTAL=''
_DBX_PRG_FEITOS=0
_DBX_PRG_ULTIMA=''
_DBX_PRG_LINHA=''
_DBX_PRG_OBS_PID=''
_DBX_PRG_ACAO_REGISTRADA='nao'
_DBX_PRG_CANAL=''
_DBX_PRG_ESTADO='ativo'

# _dbx_progress_terminal — desenho no lugar: stderr e terminal e TERM entende (DIV-292).
_dbx_progress_terminal() {
  case ${DBX_PROGRESS_TERMINAL:-auto} in
    sim) return 0 ;;
    nao) return 1 ;;
  esac
  # DIV-287: com --debug as linhas de depuracao quebrariam o retorno de carro.
  [[ -t 2 && ${TERM:-dumb} != 'dumb' && ${DBX_CLI_DEBUG:-nao} != 'sim' ]]
}

# _dbx_progress_arquivo_montar <item> <com_bytes> <sufixo> — monta _DBX_PRG_LINHA.
_dbx_progress_arquivo_montar() {
  local item=$1 com_bytes=$2 sufixo=$3 feitos=$_DBX_PRG_FEITOS total=$_DBX_PRG_TOTAL
  local f='' t='' barra='' pct=0
  if [[ $total =~ ^[0-9]+$ ]]; then
    if [[ $feitos -gt $total ]]; then feitos=$total; fi
    if [[ $total -gt 0 ]]; then pct=$((feitos * 100 / total)); fi
    if [[ $_DBX_PRG_CONCLUIDO == 'sim' ]]; then
      pct=100
    elif [[ $pct -gt 99 ]]; then
      pct=99
    fi
    dbx_progress_barra_gerar "$pct" 10 barra
    dbx_progress_formatar_bytes "$feitos" f
    dbx_progress_formatar_bytes "$total" t
    if [[ $com_bytes == 'sim' ]]; then
      _DBX_PRG_LINHA="${_DBX_PRG_CAB}${item} ${barra} ${pct}% ${f} / ${t}${sufixo}"
    else
      _DBX_PRG_LINHA="${_DBX_PRG_CAB}${item} ${barra} ${pct}%${sufixo}"
    fi
  else
    dbx_progress_formatar_bytes "$feitos" f
    _DBX_PRG_LINHA="${_DBX_PRG_CAB}${item} ${f}${sufixo}"
  fi
}

# _dbx_progress_arquivo_linha [sufixo] — _DBX_PRG_LINHA pronta; no terminal o
# item e truncado pelo meio, preservando a extensao (DIV-284).
_dbx_progress_arquivo_linha() {
  local sufixo=${1:-} item=$_DBX_PRG_ITEM com_bytes='sim' cols fixo disp ext='' cabeca
  if _dbx_progress_terminal; then
    cols=${COLUMNS:-80}
    [[ $cols =~ ^[0-9]+$ ]] || cols=80
    if [[ $cols -lt 40 ]]; then com_bytes='nao'; fi
    _dbx_progress_arquivo_montar "$item" "$com_bytes" "$sufixo"
    if [[ ${#_DBX_PRG_LINHA} -ge $cols ]]; then
      _dbx_progress_arquivo_montar '' "$com_bytes" "$sufixo"
      fixo=${#_DBX_PRG_LINHA}
      disp=$((cols - fixo - 1))
      if [[ $disp -ge 8 && ${#item} -gt $disp ]]; then
        if [[ $item =~ (\.[A-Za-z0-9]{1,8})$ ]]; then ext=${BASH_REMATCH[1]}; fi
        cabeca=$((disp - 3 - ${#ext}))
        if [[ $cabeca -lt 1 ]]; then cabeca=1; fi
        item="${item:0:cabeca}...${ext}"
      fi
    fi
  fi
  _dbx_progress_arquivo_montar "$item" "$com_bytes" "$sufixo"
}

# _dbx_progress_arquivo_emitir — escreve _DBX_PRG_LINHA (no lugar ou em linha nova).
_dbx_progress_arquivo_emitir() {
  [[ $_DBX_PRG_LINHA != "$_DBX_PRG_ULTIMA" ]] || return 0
  if [[ -n $_DBX_PRG_CANAL ]]; then
    _dbx_progress_canal_gravar || :
    _DBX_PRG_ULTIMA=$_DBX_PRG_LINHA
    return 0
  fi
  if _dbx_progress_terminal; then
    printf '\r%s\033[K' "$_DBX_PRG_LINHA" >&2
    _DBX_PRG_ABERTO='sim'
  else
    printf '%s\n' "$_DBX_PRG_LINHA" >&2
  fi
  _DBX_PRG_ULTIMA=$_DBX_PRG_LINHA
}

# _dbx_progress_arquivo_fechar — termina a linha em curso com quebra de linha.
_dbx_progress_arquivo_fechar() {
  if [[ $_DBX_PRG_ABERTO == 'sim' ]]; then
    printf '\n' >&2
    _DBX_PRG_ABERTO='nao'
  fi
}

# _dbx_progress_arquivo_sinal — acao de lib/tmp: no fim do processo, por sinal ou
# nao, nenhum observador sobrevive e a linha em curso e terminada (RF-142(e)).
_dbx_progress_arquivo_sinal() {
  dbx_progress_arquivo_encerrar
}

# dbx_progress_arquivo_iniciar <i> <n> <acao> <item> [total] [feitos] — abre a
# linha do arquivo, antes do primeiro byte. `feitos` > 0 numa retomada (DIV-294).
dbx_progress_arquivo_iniciar() {
  _DBX_PRG_ATIVO='nao'
  dbx_progress_ativo || return 0
  # DIV-285: simulacao nao transfere byte; nenhuma linha por arquivo.
  [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || return 0
  local item=${4-}
  dbx_progress_neutralizar "$item" item
  _DBX_PRG_ATIVO='sim'
  _DBX_PRG_CONCLUIDO='nao'
  _DBX_PRG_ESTADO='ativo'
  _DBX_PRG_CAB="[${1:-1}/${2:-1}] ${3:-processando}: "
  _DBX_PRG_ITEM=$item
  _DBX_PRG_TOTAL=${5-}
  _DBX_PRG_FEITOS=${6:-0}
  [[ $_DBX_PRG_FEITOS =~ ^[0-9]+$ ]] || _DBX_PRG_FEITOS=0
  _DBX_PRG_ULTIMA=''
  if [[ $_DBX_PRG_ACAO_REGISTRADA == 'nao' && -z $_DBX_PRG_CANAL ]] && declare -F dbx_tmp_acao_registrar >/dev/null; then
    dbx_tmp_acao_registrar _dbx_progress_arquivo_sinal 2>/dev/null || true
    _DBX_PRG_ACAO_REGISTRADA='sim'
  fi
  # DIV-294: no download a primeira linha espera o ponto de partida do `.part`
  # (a retomada nao passa por 0%); `avancar` a emite.
  [[ ${7-} != 'adiar' ]] || return 0
  _dbx_progress_arquivo_linha ''
  _dbx_progress_arquivo_emitir
  return 0
}

# dbx_progress_arquivo_avancar <feitos> [silencioso] — o percentual nunca diminui (RF-140(g)).
dbx_progress_arquivo_avancar() {
  [[ $_DBX_PRG_ATIVO == 'sim' ]] || return 0
  local feitos=${1:-0}
  [[ $feitos =~ ^[0-9]+$ ]] || return 0
  if [[ $feitos -gt $_DBX_PRG_FEITOS ]]; then _DBX_PRG_FEITOS=$feitos; fi
  [[ ${2:-} != 'silencioso' ]] || return 0
  _dbx_progress_arquivo_linha ''
  _dbx_progress_arquivo_emitir
  return 0
}

# dbx_progress_arquivo_concluir [tamanho_final] — 100% so aqui (RF-140(f)); fecha
# a linha. `tamanho_final` supre o total quando os metadados nao o trouxeram.
dbx_progress_arquivo_concluir() {
  [[ $_DBX_PRG_ATIVO == 'sim' ]] || return 0
  _dbx_progress_observador_parar
  if [[ ! $_DBX_PRG_TOTAL =~ ^[0-9]+$ && ${1:-} =~ ^[0-9]+$ ]]; then _DBX_PRG_TOTAL=$1; fi
  _DBX_PRG_CONCLUIDO='sim'
  _DBX_PRG_ESTADO='concluido'
  if [[ $_DBX_PRG_TOTAL =~ ^[0-9]+$ ]]; then _DBX_PRG_FEITOS=$_DBX_PRG_TOTAL; fi
  _dbx_progress_arquivo_linha ''
  _dbx_progress_arquivo_emitir
  _dbx_progress_arquivo_fechar
  _DBX_PRG_ATIVO='nao'
  return 0
}

# dbx_progress_arquivo_falhar — fica no ultimo percentual, com o sufixo ` falhou` (RF-146).
dbx_progress_arquivo_falhar() {
  [[ $_DBX_PRG_ATIVO == 'sim' ]] || return 0
  _dbx_progress_observador_parar
  _DBX_PRG_ESTADO='falhou'
  _dbx_progress_arquivo_linha ' falhou'
  _dbx_progress_arquivo_emitir
  _dbx_progress_arquivo_fechar
  _DBX_PRG_ATIVO='nao'
  return 0
}

# dbx_progress_arquivo_descartar — o item nao era um arquivo (o remoto e pasta):
# para o observador e apaga a linha em curso no terminal, sem ` falhou`.
dbx_progress_arquivo_descartar() {
  [[ $_DBX_PRG_ATIVO == 'sim' ]] || return 0
  _dbx_progress_observador_parar
  if [[ $_DBX_PRG_ABERTO == 'sim' ]]; then
    printf '\r\033[K' >&2
    _DBX_PRG_ABERTO='nao'
  fi
  _DBX_PRG_ATIVO='nao'
  return 0
}

# dbx_progress_arquivo_encerrar — fim por sinal ou saida: para o observador e termina a linha.
dbx_progress_arquivo_encerrar() {
  _dbx_progress_observador_parar
  _dbx_progress_arquivo_fechar
  _DBX_PRG_ATIVO='nao'
  return 0
}

# _dbx_progress_observador <arquivo> — amostra o tamanho do `.part` (DIV-282):
# 0,25 s no terminal; sem terminal, uma linha a cada 10 pontos percentuais.
_dbx_progress_observador() {
  local arq=$1 tam bucket=0 b principal=$$
  while :; do
    sleep 0.25
    kill -0 "$principal" 2>/dev/null || exit 0
    dbx_progress_tamanho_de "$arq" tam || tam=''
    [[ $tam =~ ^[0-9]+$ ]] || continue
    if [[ -n $_DBX_PRG_CANAL ]] || _dbx_progress_terminal; then
      dbx_progress_arquivo_avancar "$tam"
    elif [[ $_DBX_PRG_TOTAL =~ ^[0-9]+$ && $_DBX_PRG_TOTAL -gt 0 ]]; then
      b=$((tam * 100 / _DBX_PRG_TOTAL / 10))
      if [[ $b -gt $bucket ]]; then
        bucket=$b
        dbx_progress_arquivo_avancar "$tam"
      fi
    fi
  done
}

# _dbx_progress_observador_parar — mata e recolhe o observador, se houver.
_dbx_progress_observador_parar() {
  local pid=$_DBX_PRG_OBS_PID
  [[ -n $pid ]] || return 0
  _DBX_PRG_OBS_PID=''
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  return 0
}

# dbx_progress_arquivo_observar <arquivo> — observador do `.part` (so com progresso
# ativo e arquivo de 1 MiB ou mais; abaixo disso nao ha amostra).
dbx_progress_arquivo_observar() {
  [[ $_DBX_PRG_ATIVO == 'sim' && -z $_DBX_PRG_OBS_PID ]] || return 0
  if [[ $_DBX_PRG_TOTAL =~ ^[0-9]+$ ]]; then
    [[ $_DBX_PRG_TOTAL -ge 1048576 ]] || return 0
  else
    [[ -n $_DBX_PRG_CANAL ]] || _dbx_progress_terminal || return 0
  fi
  _dbx_progress_observador "$1" &
  _DBX_PRG_OBS_PID=$!
  return 0
}

# dbx_progress_arquivo_observar_parar [arquivo] — para o observador e registra, sem
# emitir, o tamanho final do `.part` (para o estado de uma falha).
dbx_progress_arquivo_observar_parar() {
  [[ $_DBX_PRG_ATIVO == 'sim' ]] || return 0
  _dbx_progress_observador_parar
  local tam
  if [[ -n ${1:-} ]]; then
    dbx_progress_tamanho_de "$1" tam || tam=''
    dbx_progress_arquivo_avancar "$tam" silencioso
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Bloco de linhas com N > 1 (F-49; RF-143; DIV-289, DIV-290)
# ---------------------------------------------------------------------------
# Os auxiliares so transferem: cada um informa o avanco do seu arquivo num
# arquivo de status (`st.<indice>` na area do ciclo, escrita atomica), e SO o
# processo principal escreve em stderr. Com terminal ele redesenha o bloco no
# lugar (ESC[nA e retorno de carro); a linha final de cada arquivo fica acima do
# bloco. Sem terminal, uma linha nova por atualizacao, na ordem de chegada.

_DBX_PRG_BL_ATIVO='nao'
_DBX_PRG_BL_DIR=''
_DBX_PRG_BL_DESENHADAS=0
_DBX_PRG_BL_ASSINATURA=''
_DBX_PRG_BL_ACAO_ID=''
declare -ga _DBX_PRG_BL_ATIVOS=()
declare -gA _DBX_PRG_BL_CAB=() _DBX_PRG_BL_ITEM=() _DBX_PRG_BL_TOTAL=() \
  _DBX_PRG_BL_FEITOS=() _DBX_PRG_BL_ESTADO=() _DBX_PRG_BL_BUCKET=() _DBX_PRG_BL_VISTO=()

# _dbx_progress_canal_gravar — lado do auxiliar: status do arquivo em curso.
# Temporario unico por escritor (`.$BASHPID`): o auxiliar e o observador dele
# nunca dividem o mesmo nome, entao o `mv` nunca leva meia escrita do outro.
_dbx_progress_canal_gravar() {
  local tmp="$_DBX_PRG_CANAL.$BASHPID.parte"
  printf '%s\n%s\n%s\n' "$_DBX_PRG_FEITOS" "$_DBX_PRG_TOTAL" "$_DBX_PRG_ESTADO" \
    >"$tmp" 2>/dev/null && mv -f -- "$tmp" "$_DBX_PRG_CANAL" 2>/dev/null
}

# dbx_progress_neutralizar <texto> [var_destino] — troca por `?` os caracteres de
# controle (ESC, BEL, quebra de linha) de um nome vindo do disco ou do servico antes
# de ele ir a stderr; sem destino, escreve o resultado em stdout.
dbx_progress_neutralizar() {
  local t=${1-}
  t=${t//[[:cntrl:]]/?}
  if [[ -n ${2-} ]]; then printf -v "$2" '%s' "$t"; else printf '%s' "$t"; fi
}

# dbx_progress_tamanho_de <arquivo> <var> — tamanho em bytes (GNU `stat -c`, com o
# fallback BSD `stat -f`, como em commands/config.sh); devolve em <var> e falha se ilegivel.
dbx_progress_tamanho_de() {
  local t=''
  IFS= read -r t < <(stat -c %s -- "$1" 2>/dev/null || stat -f %z -- "$1" 2>/dev/null)
  [[ $t =~ ^[0-9]+$ ]] || return 1
  printf -v "$2" '%s' "$t"
}

# dbx_progress_canal_definir <arquivo> — liga o auxiliar ao canal de status do principal.
dbx_progress_canal_definir() {
  _DBX_PRG_CANAL=${1-}
  return 0
}

dbx_progress_bloco_ativo() { [[ $_DBX_PRG_BL_ATIVO == 'sim' ]]; }

# dbx_progress_bloco_iniciar <diretorio_de_status> — so com progresso ativo.
dbx_progress_bloco_iniciar() {
  _DBX_PRG_BL_ATIVO='nao'
  dbx_progress_ativo || return 0
  [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || return 0
  _DBX_PRG_BL_ATIVO='sim'
  _DBX_PRG_BL_DIR=$1
  _DBX_PRG_BL_DESENHADAS=0
  _DBX_PRG_BL_ASSINATURA=''
  _DBX_PRG_BL_ATIVOS=()
  _DBX_PRG_BL_CAB=() _DBX_PRG_BL_ITEM=() _DBX_PRG_BL_TOTAL=() _DBX_PRG_BL_FEITOS=()
  _DBX_PRG_BL_ESTADO=() _DBX_PRG_BL_BUCKET=() _DBX_PRG_BL_VISTO=()
  if declare -F dbx_tmp_acao_registrar >/dev/null; then
    dbx_tmp_acao_registrar _dbx_progress_bloco_sinal 2>/dev/null || true
    _DBX_PRG_BL_ACAO_ID=${DBX_TMP_ID:-}
  fi
  return 0
}

# _dbx_progress_bloco_sinal — acao de lib/tmp: cada linha do bloco termina em
# quebra de linha, entao o cursor ja esta no inicio de uma linha livre; so para o desenho.
_dbx_progress_bloco_sinal() {
  _DBX_PRG_BL_ATIVO='nao'
  _DBX_PRG_BL_DESENHADAS=0
}

# dbx_progress_bloco_abrir <indice> <i> <n> <acao> <item> [total]
dbx_progress_bloco_abrir() {
  dbx_progress_bloco_ativo || return 0
  local idx=$1 item=${5-}
  dbx_progress_neutralizar "$item" item
  _DBX_PRG_BL_CAB[$idx]="[${2:-1}/${3:-1}] ${4:-processando}: "
  _DBX_PRG_BL_ITEM[$idx]=$item
  _DBX_PRG_BL_TOTAL[$idx]=${6-}
  _DBX_PRG_BL_FEITOS[$idx]=0
  _DBX_PRG_BL_ESTADO[$idx]='ativo'
  _DBX_PRG_BL_BUCKET[$idx]=-1
  _DBX_PRG_BL_VISTO[$idx]='nao'
  _DBX_PRG_BL_ATIVOS+=("$idx")
  return 0
}

# _dbx_progress_bloco_ler <indice> — atualiza o slot pelo arquivo de status.
_dbx_progress_bloco_ler() {
  local idx=$1 arq="$_DBX_PRG_BL_DIR/st.$1" f='' t='' e=''
  [[ -r $arq ]] || return 1
  { IFS= read -r f; IFS= read -r t; IFS= read -r e; } <"$arq" 2>/dev/null || :
  [[ $f =~ ^[0-9]+$ ]] || return 1
  if [[ $f -gt ${_DBX_PRG_BL_FEITOS[$idx]} ]]; then _DBX_PRG_BL_FEITOS[$idx]=$f; fi
  if [[ $t =~ ^[0-9]+$ ]]; then _DBX_PRG_BL_TOTAL[$idx]=$t; fi
  if [[ ${_DBX_PRG_BL_ESTADO[$idx]} == 'ativo' && ( $e == 'concluido' || $e == 'falhou' ) ]]; then
    _DBX_PRG_BL_ESTADO[$idx]=$e
  fi
  _DBX_PRG_BL_VISTO[$idx]='sim'
  return 0
}

# _dbx_progress_bloco_linha <indice> — monta _DBX_PRG_LINHA do slot.
_dbx_progress_bloco_linha() {
  local idx=$1 sufixo=''
  _DBX_PRG_CAB=${_DBX_PRG_BL_CAB[$idx]}
  _DBX_PRG_ITEM=${_DBX_PRG_BL_ITEM[$idx]}
  _DBX_PRG_TOTAL=${_DBX_PRG_BL_TOTAL[$idx]}
  _DBX_PRG_FEITOS=${_DBX_PRG_BL_FEITOS[$idx]}
  _DBX_PRG_CONCLUIDO='nao'
  case ${_DBX_PRG_BL_ESTADO[$idx]} in
    concluido)
      _DBX_PRG_CONCLUIDO='sim'
      if [[ $_DBX_PRG_TOTAL =~ ^[0-9]+$ ]]; then _DBX_PRG_FEITOS=$_DBX_PRG_TOTAL; fi
      ;;
    falhou) sufixo=' falhou' ;;
  esac
  _dbx_progress_arquivo_linha "$sufixo"
}

# dbx_progress_bloco_tick — le os status e escreve o que mudou.
dbx_progress_bloco_tick() {
  dbx_progress_bloco_ativo || return 0
  local idx b out_final='' out_ativo='' assinatura=''
  local -a finais=() mantidos=()
  if _dbx_progress_terminal; then
    for idx in ${_DBX_PRG_BL_ATIVOS[@]+"${_DBX_PRG_BL_ATIVOS[@]}"}; do
      _dbx_progress_bloco_ler "$idx" || :
      _dbx_progress_bloco_linha "$idx"
      if [[ ${_DBX_PRG_BL_ESTADO[$idx]} == 'ativo' ]]; then
        mantidos+=("$idx")
        out_ativo+=$'\r'"$_DBX_PRG_LINHA"$'\033[K\n'
      else
        finais+=("$idx")
        out_final+=$'\r'"$_DBX_PRG_LINHA"$'\033[K\n'
      fi
    done
    assinatura="$out_final|$out_ativo"
    if [[ ${#finais[@]} -gt 0 || $assinatura != "$_DBX_PRG_BL_ASSINATURA" ]]; then
      _DBX_PRG_BL_ASSINATURA=$assinatura
      out_final+=$out_ativo
      if [[ $_DBX_PRG_BL_DESENHADAS -gt 0 ]]; then out_final=$'\033['"$_DBX_PRG_BL_DESENHADAS"'A'"$out_final"; fi
      # Cada linha termina em quebra de linha e as finais ocupam o lugar das ativas:
      # o bloco nunca encolhe aqui, entao nao ha o que apagar abaixo dele.
      printf '%s' "$out_final" >&2
      _DBX_PRG_BL_DESENHADAS=${#mantidos[@]}
    fi
  else
    for idx in ${_DBX_PRG_BL_ATIVOS[@]+"${_DBX_PRG_BL_ATIVOS[@]}"}; do
      _dbx_progress_bloco_ler "$idx" || :
      if [[ ${_DBX_PRG_BL_ESTADO[$idx]} != 'ativo' ]]; then
        _dbx_progress_bloco_linha "$idx"
        printf '%s\n' "$_DBX_PRG_LINHA" >&2
        finais+=("$idx")
        continue
      fi
      mantidos+=("$idx")
      [[ ${_DBX_PRG_BL_VISTO[$idx]} == 'sim' ]] || continue
      b=0
      if [[ ${_DBX_PRG_BL_TOTAL[$idx]} =~ ^[0-9]+$ && ${_DBX_PRG_BL_TOTAL[$idx]} -gt 0 ]]; then
        b=$((${_DBX_PRG_BL_FEITOS[$idx]} * 100 / ${_DBX_PRG_BL_TOTAL[$idx]} / 10))
      fi
      if [[ ${_DBX_PRG_BL_BUCKET[$idx]} -lt 0 || $b -gt ${_DBX_PRG_BL_BUCKET[$idx]} ]]; then
        _DBX_PRG_BL_BUCKET[$idx]=$b
        _dbx_progress_bloco_linha "$idx"
        printf '%s\n' "$_DBX_PRG_LINHA" >&2
      fi
    done
  fi
  for idx in ${finais[@]+"${finais[@]}"}; do _DBX_PRG_BL_ESTADO[$idx]='emitido'; done
  _DBX_PRG_BL_ATIVOS=(${mantidos[@]+"${mantidos[@]}"})
  return 0
}

# dbx_progress_bloco_fechar <indice> <status> — o resultado do auxiliar chegou:
# o status do processo manda se o arquivo ainda nao disse o fim.
dbx_progress_bloco_fechar() {
  dbx_progress_bloco_ativo || return 0
  local idx=$1
  [[ -n ${_DBX_PRG_BL_ESTADO[$idx]+x} ]] || return 0
  [[ ${_DBX_PRG_BL_ESTADO[$idx]} != 'emitido' ]] || return 0
  _dbx_progress_bloco_ler "$idx" || :
  if [[ ${_DBX_PRG_BL_ESTADO[$idx]} == 'ativo' ]]; then
    if [[ ${2:-1} == '0' ]]; then _DBX_PRG_BL_ESTADO[$idx]='concluido'; else _DBX_PRG_BL_ESTADO[$idx]='falhou'; fi
  fi
  dbx_progress_bloco_tick
}

# dbx_progress_bloco_pausar — apaga o bloco desenhado para que outra mensagem em
# stderr nao o desalinhe; o proximo tick o redesenha abaixo dela.
dbx_progress_bloco_pausar() {
  dbx_progress_bloco_ativo || return 0
  if _dbx_progress_terminal && [[ $_DBX_PRG_BL_DESENHADAS -gt 0 ]]; then
    printf '\033[%dA\033[J' "$_DBX_PRG_BL_DESENHADAS" >&2
  fi
  _DBX_PRG_BL_DESENHADAS=0
  _DBX_PRG_BL_ASSINATURA=''
  return 0
}

# dbx_progress_bloco_encerrar — fim do paralelo: nenhum resto de bloco na tela.
dbx_progress_bloco_encerrar() {
  dbx_progress_bloco_ativo || return 0
  dbx_progress_bloco_tick
  dbx_progress_bloco_pausar
  _DBX_PRG_BL_ATIVO='nao'
  if [[ -n $_DBX_PRG_BL_ACAO_ID ]] && declare -F dbx_tmp_acao_cancelar >/dev/null; then
    dbx_tmp_acao_cancelar "$_DBX_PRG_BL_ACAO_ID" 2>/dev/null || true
  fi
  _DBX_PRG_BL_ACAO_ID=''
  return 0
}
