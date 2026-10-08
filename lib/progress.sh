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

# dbx_progress_mensagem <texto> — emite mensagem de progresso em stderr.
dbx_progress_mensagem() {
  dbx_progress_ativo || return 0
  printf '%s\n' "$1" >&2
}

# dbx_progress_etapa <atual> <total> <acao> <item> — emite marcador de etapa ordenada.
dbx_progress_etapa() {
  dbx_progress_ativo || return 0
  local atual=${1:-0} total=${2:-0} acao=${3:-processando} item=${4:-}
  printf '[%d/%d] %s: %s\n' "$atual" "$total" "$acao" "$item" >&2
}

# dbx_progress_transferencia <rotulo> <bytes_atuais> [bytes_totais] [detalhe] —
# emite progresso com bytes e percentual.
dbx_progress_transferencia() {
  dbx_progress_ativo || return 0
  local rotulo=${1:-transferencia} atuais=${2:-0} totais=${3:-0} detalhe=${4:-}
  local str_atuais='' str_totais=''
  dbx_progress_formatar_bytes "$atuais" str_atuais
  if [[ $totais =~ ^[0-9]+$ && $totais -gt 0 ]]; then
    dbx_progress_formatar_bytes "$totais" str_totais
    local pct=$(( (atuais * 100) / totais ))
    if [[ -n $detalhe ]]; then
      printf '[%s] %s: %s / %s (%d%%)\n' "$rotulo" "$detalhe" "$str_atuais" "$str_totais" "$pct" >&2
    else
      printf '[%s] %s / %s (%d%%)\n' "$rotulo" "$str_atuais" "$str_totais" "$pct" >&2
    fi
  else
    if [[ -n $detalhe ]]; then
      printf '[%s] %s: %s\n' "$rotulo" "$detalhe" "$str_atuais" >&2
    else
      printf '[%s] %s\n' "$rotulo" "$str_atuais" >&2
    fi
  fi
}
