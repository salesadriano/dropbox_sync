#!/usr/bin/env bash
# uninstall.sh — Script de desinstalacao do dropbox_sync (dbx).
#
# Uso:
#   ./uninstall.sh [opcoes]
#
# Opcoes:
#   --user, -u          Desinstalar do diretorio do usuario (~/.local) [padrao para nao-root]
#   --system, -s        Desinstalar do nivel de sistema (/usr/local) [requer root/sudo]
#   --prefix <dir>      Prefixo customizado onde o dbx foi instalado
#   --purge             Remove tambem as credenciais e historico em ~/.config/dropbox_sync/
#   --help, -h          Exibe esta ajuda
#
set -euo pipefail

# Cores e formatacao
if [[ -t 1 ]]; then
  VERDE='\033[0;32m'
  AMARELO='\033[1;33m'
  VERMELHO='\033[0;31m'
  AZUL='\033[0;34m'
  SEM_COR='\033[0m'
else
  VERDE='' AMARELO='' VERMELHO='' AZUL='' SEM_COR=''
fi

info()  { printf "%b==>%b %s\n" "$AZUL" "$SEM_COR" "$*"; }
ok()    { printf "%b[ok]%b %s\n" "$VERDE" "$SEM_COR" "$*"; }
aviso() { printf "%b[aviso]%b %s\n" "$AMARELO" "$SEM_COR" "$*" >&2; }
erro()  { printf "%b[erro]%b %s\n" "$VERMELHO" "$SEM_COR" "$*" >&2; exit 1; }

MODO_ESCOLHIDO=""
PREFIXO_CUSTOMIZADO=""
EXPURGAR="nao"

while [[ $# -gt 0 ]]; do
  case ${1-} in
    --user | -u) MODO_ESCOLHIDO="user" ;;
    --system | -s) MODO_ESCOLHIDO="system" ;;
    --prefix)
      shift
      PREFIXO_CUSTOMIZADO="${1-}"
      [[ -n $PREFIXO_CUSTOMIZADO ]] || erro "Informe o diretorio para --prefix."
      ;;
    --purge) EXPURGAR="sim" ;;
    --help | -h)
      cat <<EOF
Desinstalador do dropbox_sync (dbx)

Uso:
  ./uninstall.sh [opcoes]

Opcoes:
  --user, -u      Desinstalar do espaco do usuario (~/.local)
  --system, -s    Desinstalar do nivel de sistema (/usr/local)
  --prefix <DIR>  Desinstalar de prefixo customizado
  --purge         Remover tambem o diretorio de configuracao e credenciais (~/.config/dropbox_sync/)
  --help, -h      Exibir esta ajuda
EOF
      exit 0
      ;;
    *) erro "Opcao nao reconhecida: $1" ;;
  esac
  shift
done

if [[ -n $PREFIXO_CUSTOMIZADO ]]; then
  DIR_BIN="${PREFIXO_CUSTOMIZADO}/bin"
  DIR_SHARE="${PREFIXO_CUSTOMIZADO}/share/dropbox_sync"
elif [[ $MODO_ESCOLHIDO == "system" ]] || [[ -z $MODO_ESCOLHIDO && $(id -u) -eq 0 ]]; then
  DIR_BIN="/usr/local/bin"
  DIR_SHARE="/usr/local/share/dropbox_sync"
else
  DIR_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
  DIR_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/dropbox_sync"
fi

info "Removendo instalacao do dbx..."

removido='nao'
if [[ -L "$DIR_BIN/dbx" || -f "$DIR_BIN/dbx" ]]; then
  rm -f -- "$DIR_BIN/dbx"
  ok "Removido: $DIR_BIN/dbx"
  removido='sim'
fi

if [[ -d "$DIR_SHARE" ]]; then
  rm -rf -- "$DIR_SHARE"
  ok "Removido: $DIR_SHARE"
  removido='sim'
fi

if [[ $EXPURGAR == "sim" ]]; then
  DIR_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dropbox_sync"
  if [[ -d "$DIR_CONFIG" ]]; then
    rm -rf -- "$DIR_CONFIG"
    ok "Removido diretorio de credenciais e configuracao: $DIR_CONFIG"
  fi
else
  info "Credenciais mantidas em ~/.config/dropbox_sync/ (use --purge para remover)."
fi

if [[ $removido == 'sim' ]]; then
  ok "dropbox_sync (dbx) foi desinstalado com sucesso."
else
  aviso "Nenhum binario ou arquivo do dbx foi encontrado em $DIR_BIN ou $DIR_SHARE."
fi
