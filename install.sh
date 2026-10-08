#!/usr/bin/env bash
# install.sh — Script de instalacao oficial do dropbox_sync (dbx) para Linux.
#
# Uso:
#   bash install.sh [opcoes]
#   curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/develop/install.sh | bash
#
# Opcoes:
#   --user, -u          Instala no diretorio do usuario (~/.local) [padrao para usuarios normais]
#   --system, -s        Instala em nivel de sistema (/usr/local) [padrao para root]
#   --prefix <dir>      Define prefixo customizado de instalacao
#   --uninstall         Remove uma instalacao existente do dbx
#   --canal <ref>       Define o branch ou tag a baixar se executado via pipe (padrao: develop)
#   --help, -h          Exibe esta mensagem de ajuda
#   --version, -v       Exibe versao do instalador
#
set -euo pipefail

VERSAO_INSTALADOR="1.1.0"
REPO_URL="https://github.com/salesadriano/dropbox_sync.git"
CANAL_PADRAO="develop"

# Cores e formatacao
if [[ -t 1 ]]; then
  VERDE='\033[0;32m'
  AMARELO='\033[1;33m'
  VERMELHO='\033[0;31m'
  AZUL='\033[0;34m'
  NEGRITO='\033[1m'
  SEM_COR='\033[0m'
else
  VERDE='' AMARELO='' VERMELHO='' AZUL='' NEGRITO='' SEM_COR=''
fi

info()  { printf "%b==>%b %s\n" "$AZUL" "$SEM_COR" "$*"; }
ok()    { printf "%b[ok]%b %s\n" "$VERDE" "$SEM_COR" "$*"; }
aviso() { printf "%b[aviso]%b %s\n" "$AMARELO" "$SEM_COR" "$*" >&2; }
erro()  { printf "%b[erro]%b %s\n" "$VERMELHO" "$SEM_COR" "$*" >&2; exit 1; }

exibir_ajuda() {
  cat <<EOF
Instalador do dropbox_sync (dbx) v${VERSAO_INSTALADOR} para Linux

Uso:
  ./install.sh [opcoes]

Opcoes:
  --user, -u          Instalar no diretorio do usuario (~/.local) [padrao para nao-root]
  --system, -s        Instalar em nivel de sistema (/usr/local) [requer root/sudo]
  --prefix <DIR>      Instalar com prefixo customizado (<DIR>/bin e <DIR>/share/dropbox_sync)
  --uninstall         Desinstalar o dbx e seus componentes instalados
  --canal <REF>       Branch ou tag remota a utilizar em execucao remota via pipe (padrao: ${CANAL_PADRAO})
  --help, -h          Exibir esta mensagem de ajuda
  --version, -v       Exibir versao do instalador

Exemplos:
  ./install.sh                    # Instalacao padrao no espaco do usuario
  sudo ./install.sh --system      # Instalacao global para todos os usuarios
  ./install.sh --prefix /opt/dbx  # Instalacao em prefixo dedicado
EOF
}

# 1. Verificacao de pre-requisitos de ambiente Linux
verificar_prerequisitos() {
  info "Verificando pre-requisitos do sistema..."

  # Bash 4.4+
  if [[ ${BASH_VERSINFO[0]} -lt 4 || (${BASH_VERSINFO[0]} -eq 4 && ${BASH_VERSINFO[1]} -lt 4) ]]; then
    erro "GNU Bash 4.4 ou superior e necessario. Versao detectada: ${BASH_VERSION}."
  fi

  # cURL
  if ! command -v curl >/dev/null 2>&1; then
    erro "cURL nao encontrado. Instale com: sudo apt install curl (ou equivalente da sua distribuicao)."
  fi

  # Coreutils necessarios
  local cmd
  for cmd in mkdir rm cp chmod mktemp stat; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      erro "Utilitario obrigatorio '$cmd' nao encontrado no PATH."
    fi
  done

  # Algoritmo de hash (sha256sum ou shasum)
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    erro "Utilitario de integridade sha256sum ou shasum nao encontrado."
  fi

  # SQLite3 (recomendado para cache local de alto desempenho)
  if command -v sqlite3 >/dev/null 2>&1; then
    ok "sqlite3 detectado: cache de metadados e operacoes de alta performance ativo."
  else
    aviso "sqlite3 nao detectado. A ferramenta funciona normalmente, mas instalar sqlite3 acelerara analises locais repetidas."
  fi

  ok "Pre-requisitos validados com sucesso."
}

# 2. Localizacao da fonte dos arquivos
obter_raiz_origem() {
  local dir_script
  dir_script=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || echo "")

  if [[ -n $dir_script && -f "$dir_script/bin/dbx" && -d "$dir_script/lib" && -d "$dir_script/commands" ]]; then
    # Executado diretamente a partir do repositorio ou pacote descompactado
    RAIZ_ORIGEM="$dir_script"
    ORIGEM_TEMPORARIA=""
  else
    # Executado via pipe (ex: curl ... | bash) ou arquivo isolado
    info "Origem local completa nao detectada; obtendo arquivos do repositorio oficial..."
    local area_tmp
    area_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dbx-install.XXXXXXXX")
    ORIGEM_TEMPORARIA="$area_tmp"

    if command -v git >/dev/null 2>&1; then
      info "Clonando versao '${CANAL}'..."
      git clone --depth 1 --branch "$CANAL" "$REPO_URL" "$area_tmp/repo" >/dev/null 2>&1 || {
        rm -rf -- "$area_tmp"
        erro "Nao foi possivel clonar o repositorio via git."
      }
      RAIZ_ORIGEM="$area_tmp/repo"
    else
      info "Baixando arquivo do repositorio via cURL..."
      local tarball_url="https://github.com/salesadriano/dropbox_sync/archive/refs/heads/${CANAL}.tar.gz"
      curl -fsSL "$tarball_url" -o "$area_tmp/fonte.tar.gz" || {
        rm -rf -- "$area_tmp"
        erro "Nao foi possivel baixar o pacote fonte de: $tarball_url"
      }
      tar -xzf "$area_tmp/fonte.tar.gz" -C "$area_tmp"
      local dir_extraido
      dir_extraido=$(find "$area_tmp" -maxdepth 1 -type d -name "dropbox_sync*" | head -n 1)
      [[ -n $dir_extraido && -f "$dir_extraido/bin/dbx" ]] || {
        rm -rf -- "$area_tmp"
        erro "Estrutura do pacote baixado e invalida."
      }
      RAIZ_ORIGEM="$dir_extraido"
    fi
  fi
}

limpar_origem_temporaria() {
  if [[ -n ${ORIGEM_TEMPORARIA:-} && -d $ORIGEM_TEMPORARIA ]]; then
    rm -rf -- "$ORIGEM_TEMPORARIA"
  fi
}

# 3. Rotina de desinstalacao
executar_desinstalacao() {
  info "Executando desinstalacao do dbx..."
  local alvo_bin="$DIR_BIN/dbx"
  local alvo_share="$DIR_SHARE"

  local removido='nao'
  if [[ -L $alvo_bin || -f $alvo_bin ]]; then
    rm -f -- "$alvo_bin"
    ok "Removido executavel/link: $alvo_bin"
    removido='sim'
  fi

  if [[ -d $alvo_share ]]; then
    rm -rf -- "$alvo_share"
    ok "Removido diretorio de dados e bibliotecas: $alvo_share"
    removido='sim'
  fi

  if [[ $removido == 'sim' ]]; then
    ok "dropbox_sync (dbx) foi desinstalado com sucesso."
    info "Nota: Suas credenciais e historico local em ~/.config/dropbox_sync/ foram preservados."
  else
    aviso "Nenhuma instalacao ativa encontrada em $DIR_BIN ou $DIR_SHARE."
  fi
}

# 4. Rotina principal de instalacao
executar_instalacao() {
  verificar_prerequisitos
  obter_raiz_origem
  trap limpar_origem_temporaria EXIT

  info "Instalando dropbox_sync (dbx) em:"
  printf "     Executavel : %s/dbx\n" "$DIR_BIN"
  printf "     Arquivos   : %s\n" "$DIR_SHARE"

  # Criar diretorios necessarios
  mkdir -p -- "$DIR_BIN" "$DIR_SHARE" || {
    erro "Permissao negada ao criar diretorios de instalacao. Execute com sudo para instalacao de sistema."
  }

  # Copiar arquivos de biblioteca, comandos e binario
  mkdir -p -- "$DIR_SHARE/bin" "$DIR_SHARE/lib" "$DIR_SHARE/commands"
  cp -p "$RAIZ_ORIGEM/bin/dbx" "$DIR_SHARE/bin/dbx"
  cp -p "$RAIZ_ORIGEM/lib/"*.sh "$DIR_SHARE/lib/"
  cp -p "$RAIZ_ORIGEM/commands/"*.sh "$DIR_SHARE/commands/"

  # Copiar documentacao e licenca se presentes
  [[ -f "$RAIZ_ORIGEM/README.md" ]] && cp -p "$RAIZ_ORIGEM/README.md" "$DIR_SHARE/"
  [[ -f "$RAIZ_ORIGEM/LICENSE" ]] && cp -p "$RAIZ_ORIGEM/LICENSE" "$DIR_SHARE/"

  # Copiar o desinstalador se presente
  if [[ -f "$RAIZ_ORIGEM/uninstall.sh" ]]; then
    cp -p "$RAIZ_ORIGEM/uninstall.sh" "$DIR_SHARE/"
    chmod 755 "$DIR_SHARE/uninstall.sh"
  fi

  # Garantir permissoes adequadas
  chmod 755 "$DIR_SHARE/bin/dbx"
  chmod 644 "$DIR_SHARE/lib/"*.sh "$DIR_SHARE/commands/"*.sh

  # Criar link simbolico no diretorio bin
  ln -sf "$DIR_SHARE/bin/dbx" "$DIR_BIN/dbx"
  chmod 755 "$DIR_BIN/dbx"

  ok "Instalacao de arquivos concluida."

  # Teste rapido de execucao
  local versao_executada
  if versao_executada=$("$DIR_BIN/dbx" --version 2>/dev/null); then
    ok "Validacao de execucao: ${versao_executada}"
  else
    aviso "O executavel foi instalado mas nao respondeu corretamente a --version."
  fi

  # Verificacao do PATH
  local path_corrente=":${PATH}:"
  if [[ $path_corrente == *":${DIR_BIN}:"* ]]; then
    printf '\n%b%bTudo pronto!%b\n' "$VERDE" "$NEGRITO" "$SEM_COR"
    printf "O comando '%b%s%b' ja esta no seu PATH.\n" "$NEGRITO" "dbx" "$SEM_COR"
    printf 'Execute: %bdbx help%b para iniciar.\n\n' "$NEGRITO" "$SEM_COR"
  else
    printf '\n%b%bAtencao:%b O diretorio %b%s%b nao esta no seu PATH atual.\n' \
      "$AMARELO" "$NEGRITO" "$SEM_COR" "$NEGRITO" "$DIR_BIN" "$SEM_COR"
    printf "Para disponibilizar o comando 'dbx' globalmente no seu terminal, adicione a linha abaixo ao seu %b~/.bashrc%b ou %b~/.profile%b:\n\n" \
      "$NEGRITO" "$SEM_COR" "$NEGRITO" "$SEM_COR"
    # shellcheck disable=SC2016  # intencional: instrucao textual ao operador para exportar $PATH
    printf '    %bexport PATH="%s:$PATH"%b\n\n' "$NEGRITO" "$DIR_BIN" "$SEM_COR"
    printf 'E recarregue com: %bsource ~/.bashrc%b\n\n' "$NEGRITO" "$SEM_COR"
  fi
}

# Processamento de argumentos
MODO_ESCOLHIDO=""
PREFIXO_CUSTOMIZADO=""
DESINSTALAR="nao"
CANAL="$CANAL_PADRAO"

while [[ $# -gt 0 ]]; do
  case ${1-} in
    --user | -u)
      MODO_ESCOLHIDO="user"
      ;;
    --system | -s)
      MODO_ESCOLHIDO="system"
      ;;
    --prefix)
      shift
      PREFIXO_CUSTOMIZADO="${1-}"
      [[ -n $PREFIXO_CUSTOMIZADO ]] || erro "Informe o diretorio para --prefix."
      ;;
    --canal)
      shift
      CANAL="${1-}"
      [[ -n $CANAL ]] || erro "Informe o branch/tag para --canal."
      ;;
    --uninstall)
      DESINSTALAR="sim"
      ;;
    --version | -v)
      printf 'install.sh versao %s\n' "$VERSAO_INSTALADOR"
      exit 0
      ;;
    --help | -h)
      exibir_ajuda
      exit 0
      ;;
    *)
      erro "Opcao nao reconhecida: $1. Use --help para ver as opcoes validas."
      ;;
  esac
  shift
done

# Definicao dos caminhos de destino
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

if [[ $DESINSTALAR == "sim" ]]; then
  executar_desinstalacao
else
  executar_instalacao
fi
