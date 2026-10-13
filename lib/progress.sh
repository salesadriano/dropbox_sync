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

  if [[ $total =~ ^[0-9]+$ && $total -gt 0 ]]; then
    local pct=$(( (atual * 100) / total ))
    if [[ $atual -gt 0 && $pct -eq 0 ]]; then
      local centesimos=$(( (atual * 10000) / total ))
      if [[ $centesimos -eq 0 ]]; then
        printf '[%d/%d] %s: %s %s (<0.01%%)\n' "$atual" "$total" "$acao" "$item" "$str_barra" >&2
      else
        printf '[%d/%d] %s: %s %s (0.%02d%%)\n' "$atual" "$total" "$acao" "$item" "$str_barra" "$((centesimos % 100))" >&2
      fi
    else
      printf '[%d/%d] %s: %s %s (%d%%)\n' "$atual" "$total" "$acao" "$item" "$str_barra" "$pct" >&2
    fi
  else
    printf '[%d/%d] %s: %s\n' "$atual" "$total" "$acao" "$item" >&2
  fi
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
