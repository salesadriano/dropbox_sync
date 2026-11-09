#!/usr/bin/env bash
# install.sh — Script de instalacao oficial do dropbox_sync (dbx) para Linux e FreeBSD.
#
# Uso:
#   bash install.sh [opcoes]
#   curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/master/install.sh | bash
#
# Opcoes:
#   --user, -u          Instala no diretorio do usuario (~/.local) [padrao para usuarios normais]
#   --system, -s        Instala em nivel de sistema (/usr/local) [padrao para root]
#   --prefix <dir>      Define prefixo customizado de instalacao
#   --uninstall         Remove uma instalacao existente do dbx
#   --canal <ref>       Define o branch ou tag a baixar (padrao: o da linha que o bash do host suporta)
#   --help, -h          Exibe esta mensagem de ajuda
#   --version, -v       Exibe versao do instalador
#
# Duas linhas de produto (RF-198, RF-201): a principal (canal master, bash 4.4+) e
# a legada (canal support/bash-4.2, bash 4.2 e 4.3). O instalador escolhe pelo
# BASH_VERSINFO do host; atualizar e rodar o instalador de novo. Este arquivo
# precisa rodar em bash 4.2: sem nameref, `wait -n`, `${x@op}` nem vetor vazio
# sob `set -u`.
#
set -euo pipefail

VERSAO_INSTALADOR="2.4.0"
REPO_URL="https://github.com/salesadriano/dropbox_sync.git"
CANAL_PRINCIPAL="master"
CANAL_LEGADO="support/bash-4.2"
# Piso absoluto do produto (RNF-40): abaixo dele nenhuma linha roda. O piso de
# cada fonte NAO e copiado aqui: vem do lib/preflight.sh da propria fonte.
PISO_ABSOLUTO_MAIOR=4
PISO_ABSOLUTO_MENOR=2
LINHA=""
CANAL_EXPLICITO=""
# Unico ponto de download; os testes apontam para um duplo.
FUNCAO_BAIXAR=baixar_fonte
HOST_MAIOR=${BASH_VERSINFO[0]}
HOST_MENOR=${BASH_VERSINFO[1]}

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
Instalador do dropbox_sync (dbx) v${VERSAO_INSTALADOR} para Linux e FreeBSD

Uso:
  ./install.sh [opcoes]

Opcoes:
  --user, -u          Instalar no diretorio do usuario (~/.local) [padrao para nao-root]
  --system, -s        Instalar em nivel de sistema (/usr/local) [requer root/sudo]
  --prefix <DIR>      Instalar com prefixo customizado (<DIR>/bin e <DIR>/share/dropbox_sync)
  --uninstall         Desinstalar o dbx e seus componentes instalados
  --canal <REF>       Branch ou tag remota a utilizar (padrao: o da linha que o bash do host suporta)
  --help, -h          Exibir esta mensagem de ajuda
  --version, -v       Exibir versao do instalador

Exemplos:
  ./install.sh                    # Instalacao padrao no espaco do usuario
  sudo ./install.sh --system      # Instalacao global para todos os usuarios
  ./install.sh --prefix /opt/dbx  # Instalacao em prefixo dedicado
EOF
}

# sugerir_instalacao <pacote> — sugestao pelo gerenciador que EXISTE no host
# (capacidade, `command -v`; DIV-357). Neutra quando nenhum e conhecido.
sugerir_instalacao() {
  if command -v pkg >/dev/null 2>&1; then
    printf 'Instale com: pkg install %s' "$1"
  elif command -v apt >/dev/null 2>&1; then
    printf 'Instale com: apt install %s' "$1"
  else
    printf 'Instale o pacote "%s" pelo gerenciador de pacotes do seu sistema.' "$1"
  fi
}

# escolher_linha <maior> <menor> -> principal (>= 4.4) | legada (4.2, 4.3) | recusa (< 4.2)
escolher_linha() {
  local maior=$1 menor=$2
  if [[ $maior -lt $PISO_ABSOLUTO_MAIOR || ($maior -eq $PISO_ABSOLUTO_MAIOR && $menor -lt $PISO_ABSOLUTO_MENOR) ]]; then
    printf 'recusa'
  elif [[ $maior -gt 4 || ($maior -eq 4 && $menor -ge 4) ]]; then
    printf 'principal'
  else
    printf 'legada'
  fi
}

canal_da_linha() {
  if [[ $1 == legada ]]; then printf '%s' "$CANAL_LEGADO"; else printf '%s' "$CANAL_PRINCIPAL"; fi
}

# piso_da_fonte <raiz> -> "<maior> <menor>" lidos de <raiz>/lib/preflight.sh;
# ausente ou ilegivel = fonte invalida (status 1).
piso_da_fonte() {
  local arq="$1/lib/preflight.sh" maior menor
  [[ -r $arq ]] || return 1
  maior=$(sed -n 's/^readonly DBX_PREFLIGHT_BASH_MAIOR=\([0-9][0-9]*\)$/\1/p' "$arq" | head -n 1)
  menor=$(sed -n 's/^readonly DBX_PREFLIGHT_BASH_MENOR=\([0-9][0-9]*\)$/\1/p' "$arq" | head -n 1)
  [[ -n $maior && -n $menor ]] || return 1
  printf '%s %s' "$maior" "$menor"
}

# piso_atende_ao_host <maior> <menor>: o bash do host serve a fonte com esse piso?
piso_atende_ao_host() {
  [[ $HOST_MAIOR -gt $1 || ($HOST_MAIOR -eq $1 && $HOST_MENOR -ge $2) ]]
}

comando_manual() {
  printf 'curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/%s/install.sh | bash -s -- --canal %s' "$1" "$1"
}

# linha_instalada <dir_share> -> principal | legada | (vazio se nao ha instalacao)
linha_instalada() {
  local arq="$1/lib/cli.sh" versao
  [[ -r $arq ]] || return 0
  versao=$(sed -n "s/^readonly DBX_CLI_VERSAO='\([^']*\)'.*/\1/p" "$arq" | head -n 1)
  [[ -n $versao ]] || return 0
  if [[ $versao =~ -bash42($|[-.+]) ]]; then printf 'legada'; else printf 'principal'; fi
}

# RF-203c e DIV-389: troca de linha sobre instalacao existente e avisada, sem recusa.
avisar_troca_de_linha() {
  local anterior
  anterior=$(linha_instalada "$DIR_SHARE")
  [[ -n $anterior && $anterior != "$LINHA" ]] || return 0
  if [[ $LINHA == legada ]]; then
    aviso "TROCA DE LINHA: a instalacao existente e da linha principal e sera substituida pela linha legada (bash ${HOST_MAIOR}.${HOST_MENOR}). Recursos novos da principal deixam de estar disponiveis; atualize o bash para 4.4+ e rode o instalador de novo para voltar a principal."
  else
    aviso "TROCA DE LINHA: a instalacao existente e da linha legada e sera substituida pela linha principal (bash ${HOST_MAIOR}.${HOST_MENOR}). Credencial, configuracao e estado sao mantidos."
  fi
}

# 1. Verificacao de pre-requisitos de ambiente (Linux e FreeBSD)
verificar_prerequisitos() {
  info "Verificando pre-requisitos do sistema..."

  # Linha de produto pelo bash do host (RF-201)
  LINHA=$(escolher_linha "$HOST_MAIOR" "$HOST_MENOR")
  if [[ $LINHA == recusa ]]; then
    erro "Bash ${PISO_ABSOLUTO_MAIOR}.${PISO_ABSOLUTO_MENOR} ou superior e necessario. Versao detectada: ${HOST_MAIOR}.${HOST_MENOR}. $(sugerir_instalacao bash)"
  fi
  [[ -n $CANAL_EXPLICITO ]] || CANAL=$(canal_da_linha "$LINHA")
  info "Linha ${LINHA} (canal ${CANAL}): bash ${HOST_MAIOR}.${HOST_MENOR} detectado."

  # cURL
  if ! command -v curl >/dev/null 2>&1; then
    erro "cURL nao encontrado. $(sugerir_instalacao curl)"
  fi

  # Coreutils necessarios
  local cmd
  for cmd in mkdir rm cp chmod mktemp stat; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      erro "Utilitario obrigatorio '$cmd' nao encontrado no PATH."
    fi
  done

  # Algoritmo de hash (sha256sum, shasum, sha256 ou openssl)
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1 &&
    ! command -v sha256 >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
    erro "Utilitario de integridade (sha256sum, shasum, sha256 ou openssl) nao encontrado. $(sugerir_instalacao openssl)"
  fi

  ok "Pre-requisitos validados com sucesso."
}

# baixar_fonte <canal>: obtem a fonte do repositorio oficial e define RAIZ_ORIGEM
# e ORIGEM_TEMPORARIA; falha (status 1) sem rede. Unico ponto de download: os
# testes o substituem.
baixar_fonte() {
  local canal=$1 area_tmp
  area_tmp=$(mktemp -d "${TMPDIR:-/tmp}/dbx-install.XXXXXXXX")
  ORIGEM_TEMPORARIA="$area_tmp"
  if command -v git >/dev/null 2>&1; then
    info "Clonando versao '${canal}'..."
    git clone --depth 1 --branch "$canal" "$REPO_URL" "$area_tmp/repo" >/dev/null 2>&1 || return 1
    RAIZ_ORIGEM="$area_tmp/repo"
  else
    info "Baixando arquivo do repositorio via cURL..."
    curl -fsSL "https://github.com/salesadriano/dropbox_sync/archive/${canal}.tar.gz" -o "$area_tmp/fonte.tar.gz" || return 1
    tar -xzf "$area_tmp/fonte.tar.gz" -C "$area_tmp" || return 1
    local dir_extraido
    dir_extraido=$(find "$area_tmp" -maxdepth 1 -type d -name "dropbox_sync*" | head -n 1)
    [[ -n $dir_extraido && -f "$dir_extraido/bin/dbx" ]] || return 1
    RAIZ_ORIGEM="$dir_extraido"
  fi
}

# 2. Localizacao da fonte dos arquivos. <dir_script> e o diretorio do proprio
# install.sh (vazio quando executado via pipe).
obter_raiz_origem() {
  local dir_script=${1-} piso=""
  RAIZ_ORIGEM=""
  ORIGEM_TEMPORARIA=""

  if [[ -n $dir_script && -f "$dir_script/bin/dbx" && -d "$dir_script/lib" && -d "$dir_script/commands" ]]; then
    # Executado a partir do repositorio ou pacote descompactado
    if [[ -z $CANAL_EXPLICITO ]]; then
      # shellcheck disable=SC2086  # intencional: $piso e "<maior> <menor>", dois argumentos
      if piso=$(piso_da_fonte "$dir_script") && ! piso_atende_ao_host $piso; then
        info "A fonte local exige bash ${piso% *}.${piso#* } e o host tem ${HOST_MAIOR}.${HOST_MENOR}; obtendo a linha ${LINHA} (canal ${CANAL}) do repositorio oficial."
      else
        RAIZ_ORIGEM="$dir_script"
      fi
    fi
  fi

  if [[ -z $RAIZ_ORIGEM ]]; then
    info "Obtendo arquivos do repositorio oficial (canal ${CANAL})..."
    "$FUNCAO_BAIXAR" "$CANAL" || {
      limpar_origem_temporaria
      erro "Nao foi possivel obter o canal '${CANAL}' (sem rede?). Nada foi instalado. Comando manual: $(comando_manual "$CANAL")"
    }
  fi

  # Confere o piso da fonte obtida antes de qualquer escrita (RF-202c, DIV-385 A)
  piso=$(piso_da_fonte "$RAIZ_ORIGEM") || {
    limpar_origem_temporaria
    erro "Fonte invalida: lib/preflight.sh ausente ou sem o piso de bash."
  }
  # shellcheck disable=SC2086  # intencional: $piso e "<maior> <menor>", dois argumentos
  if ! piso_atende_ao_host $piso; then
    limpar_origem_temporaria
    erro "A fonte do canal '${CANAL}' exige bash ${piso% *}.${piso#* } e o host tem ${HOST_MAIOR}.${HOST_MENOR}. Use o canal $(canal_da_linha "$LINHA"): $(comando_manual "$(canal_da_linha "$LINHA")")"
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

  # RF-68(d): so o arquivo do dbx; o diretorio e de todos os programas.
  if [[ -f "$DIR_COMPLETAR/dbx" ]]; then
    rm -f -- "$DIR_COMPLETAR/dbx"
    ok "Removido autocompletar do bash: $DIR_COMPLETAR/dbx"
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
  local dir_script
  dir_script=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || echo "")
  trap limpar_origem_temporaria EXIT
  obter_raiz_origem "$dir_script"
  avisar_troca_de_linha

  info "Instalando dropbox_sync (dbx) em:"
  printf "     Executavel : %s/dbx\n" "$DIR_BIN"
  printf "     Arquivos   : %s\n" "$DIR_SHARE"

  # Criar diretorios necessarios
  mkdir -p -- "$DIR_BIN" "$DIR_SHARE" || {
    erro "Permissao negada ao criar diretorios de instalacao. Execute com sudo para instalacao de sistema."
  }

  # Copiar arquivos de biblioteca, comandos e binario
  mkdir -p -- "$DIR_SHARE/bin" "$DIR_SHARE/lib" "$DIR_SHARE/commands" "$DIR_SHARE/completions"
  cp -p "$RAIZ_ORIGEM/bin/dbx" "$DIR_SHARE/bin/dbx"
  cp -p "$RAIZ_ORIGEM/lib/"*.sh "$DIR_SHARE/lib/"
  cp -p "$RAIZ_ORIGEM/commands/"*.sh "$DIR_SHARE/commands/"
  # RF-68: `dbx completar bash` le a copia instalada.
  cp -p "$RAIZ_ORIGEM/completions/dbx.bash" "$DIR_SHARE/completions/dbx.bash"
  chmod 644 "$DIR_SHARE/completions/dbx.bash"

  # RF-68(d): autocompletar onde o bash-completion procura, sem sudo no modo
  # usuario e sem tocar em arquivo de inicializacao do shell. A copia
  # sobrescreve no lugar: rodar duas vezes da o mesmo resultado.
  mkdir -p -- "$DIR_COMPLETAR"
  cp -- "$RAIZ_ORIGEM/completions/dbx.bash" "$DIR_COMPLETAR/dbx"
  chmod 644 "$DIR_COMPLETAR/dbx"

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
CANAL="$CANAL_PRINCIPAL"

# Carga para testes unitarios: so as funcoes, nenhuma acao.
if [[ ${DBX_INSTALL_SO_FUNCOES:-} == 1 ]]; then
  # shellcheck disable=SC2317  # `exit` vale quando o arquivo e executado, nao carregado
  return 0 2>/dev/null || exit 0
fi

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
      # So nome de ref (branch ou tag): o canal vai a URL, ao git e ao comando
      # manual sugerido ao usuario, que nao pode carregar trecho de shell.
      [[ $CANAL =~ ^[A-Za-z0-9._/-]+$ && $CANAL != -* ]] || erro "Canal invalido: use so letras, digitos, ponto, hifen, sublinhado e barra (branch ou tag)."
      CANAL_EXPLICITO="$CANAL"
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
# Autocompletar (RF-68(d)): irmao de `dropbox_sync` sob o mesmo `share`, ou
# seja ~/.local/share/bash-completion/completions no modo usuario,
# <DIR>/share/bash-completion/completions com --prefix e
# /usr/local/share/bash-completion/completions com --system.
DIR_COMPLETAR="${DIR_SHARE%/dropbox_sync}/bash-completion/completions"

if [[ $DESINSTALAR == "sim" ]]; then
  executar_desinstalacao
else
  executar_instalacao
fi
