#!/usr/bin/env bash
# lib/preflight.sh — verificacao de ambiente e dependencias.
#
# Camada: adaptadores. Depende de lib/errors.sh, de dominio.
#
# Verifica o AMBIENTE, e nao a autorizacao: credencial ausente e o estado normal
# antes da configuracao inicial e NAO reprova aqui. Quem exige credencial e o
# comando que precisa dela. O que o preflight verifica sobre a credencial e a
# permissao do arquivo, quando ele existe (DP-11, RNF-04).
#
# Classe de erro para dependencia ausente: `configuracao` (3). A proposta de um
# codigo dedicado foi rejeitada — o problema era precisao de mensagem, nao
# escassez de codigos —, e a mensagem de `configuracao` foi reescrita para nao
# presumir credencial.
#
# NAO ha camada de compatibilidade GNU/BSD: DP-07 fixou Linux, e detectar
# variante de sistema aqui traria de volta o que a decisao removeu.

[[ -n ${DBX_PREFLIGHT_CARREGADO:-} ]] && return 0
DBX_PREFLIGHT_CARREGADO=1

_dbx_preflight_diretorio=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_preflight_diretorio/errors.sh"
unset _dbx_preflight_diretorio

DBX_PREFLIGHT_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_PREFLIGHT_ERRO_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
readonly DBX_PREFLIGHT_ERRO_USO DBX_PREFLIGHT_ERRO_CONFIGURACAO

# Piso tecnico (DP-07). 4.2 seria exigido por `declare -g`; 4.3 por nameref;
# 4.4 pela expansao de vetor vazio sob `set -u`, usada na propria suite. O piso
# real e portanto 4.4, e a consequencia material e que RHEL 6, com 4.1, fica
# fora.
readonly DBX_PREFLIGHT_BASH_MAIOR=4
readonly DBX_PREFLIGHT_BASH_MENOR=4

# Dependencia externa unica do PROJETO e o cURL (DP-08). A lista abaixo, porem,
# e a dos utilitarios efetivamente invocados pela biblioteca — os de instalacao
# base admitidos por RNF-02 — porque RNF-02 exige NOMEAR o que falta, e um
# preflight que aprova ambiente onde a primeira operacao ja falha e pior do que
# nao existir: cria confianca falsa e empurra o diagnostico para um ponto mais
# obscuro. Ha caso de teste que reprova se a biblioteca passar a invocar um
# utilitario ausente desta lista.
readonly DBX_PREFLIGHT_UTILITARIOS='curl mktemp mv rm chmod mkdir stat head wc readlink dirname find'

DBX_PREFLIGHT_MOTIVO=''
DBX_PREFLIGHT_DETALHE=''

_dbx_preflight_falhar() {
  DBX_PREFLIGHT_MOTIVO=$1
  DBX_PREFLIGHT_DETALHE=$2
  return "$DBX_PREFLIGHT_ERRO_CONFIGURACAO"
}

# dbx_preflight_versao_de_bash_suficiente <maior> <menor>
dbx_preflight_versao_de_bash_suficiente() {
  local maior=${1-} menor=${2-}
  [[ $maior =~ ^[0-9]+$ && $menor =~ ^[0-9]+$ ]] || return "$DBX_PREFLIGHT_ERRO_USO"
  [[ $maior -gt $DBX_PREFLIGHT_BASH_MAIOR ]] && return 0
  [[ $maior -eq $DBX_PREFLIGHT_BASH_MAIOR && $menor -ge $DBX_PREFLIGHT_BASH_MENOR ]]
}

# dbx_preflight_diretorio_de_configuracao — XDG com fallback, em DBX_PREFLIGHT_DETALHE.
dbx_preflight_diretorio_de_configuracao() {
  local base=${XDG_CONFIG_HOME:-}
  if [[ -z $base ]]; then
    [[ -n ${HOME:-} && $HOME == /* ]] ||
      { _dbx_preflight_falhar configuracao 'HOME ausente ou nao absoluto'; return $?; }
    base="$HOME/.config"
  fi
  # XDG exige caminho absoluto: relativo tornaria a localizacao dependente do
  # diretorio corrente, mudando o alvo entre invocacoes.
  [[ $base == /* ]] ||
    { _dbx_preflight_falhar configuracao 'XDG_CONFIG_HOME precisa ser caminho absoluto'; return $?; }
  DBX_PREFLIGHT_DETALHE="$base/dbx"
}

# dbx_preflight_verificar — verificacao completa do ambiente.
dbx_preflight_verificar() {
  local utilitario area_temporaria diretorio arquivo modo dono

  DBX_PREFLIGHT_MOTIVO=''
  DBX_PREFLIGHT_DETALHE=''

  dbx_preflight_versao_de_bash_suficiente "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" ||
    { _dbx_preflight_falhar bash "shell abaixo do piso ${DBX_PREFLIGHT_BASH_MAIOR}.${DBX_PREFLIGHT_BASH_MENOR}"; return $?; }

  for utilitario in $DBX_PREFLIGHT_UTILITARIOS; do
    command -v "$utilitario" >/dev/null 2>&1 ||
      { _dbx_preflight_falhar dependencia "utilitario obrigatorio ausente: $utilitario"; return $?; }
  done

  # Resumo SHA-256: `lib/hash` aceita mais de um utilitario, entao a verificacao
  # pergunta ao proprio componente em vez de repetir a lista aqui.
  if declare -F dbx_hash_verificar_dependencias >/dev/null; then
    dbx_hash_verificar_dependencias ||
      { _dbx_preflight_falhar dependencia 'nenhum utilitario de resumo SHA-256 disponivel'; return $?; }
  else
    command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
      command -v openssl >/dev/null 2>&1 ||
      { _dbx_preflight_falhar dependencia 'nenhum utilitario de resumo SHA-256 disponivel'; return $?; }
  fi

  area_temporaria=${TMPDIR:-/tmp}
  [[ -d $area_temporaria ]] ||
    { _dbx_preflight_falhar temporaria "area temporaria inexistente: $area_temporaria"; return $?; }
  [[ -w $area_temporaria ]] ||
    { _dbx_preflight_falhar temporaria "area temporaria sem permissao de escrita: $area_temporaria"; return $?; }

  dbx_preflight_diretorio_de_configuracao || return $?
  diretorio=$DBX_PREFLIGHT_DETALHE
  arquivo="$diretorio/credencial.json"

  # Credencial ausente e o estado normal antes da configuracao inicial.
  if [[ -e $arquivo ]]; then
    [[ -f $arquivo ]] ||
      { _dbx_preflight_falhar credencial 'o caminho da credencial nao e arquivo comum'; return $?; }
    modo=$(stat -c '%a' "$arquivo" 2>/dev/null) ||
      { _dbx_preflight_falhar credencial 'nao foi possivel inspecionar a credencial'; return $?; }
    # Mesma regra do caminho gemeo em lib/config: qualquer modo sem bits para
    # grupo e outros e aceito, porque recusar 0400 desfaria uma escolha MAIS
    # restritiva do operador. Manter as duas verificacoes identicas e o que
    # impede que uma delas vire porta de entrada.
    [[ $modo =~ ^[4567]00$ ]] ||
      { _dbx_preflight_falhar credencial "permissao da credencial precisa nao ter bits para grupo e outros, encontrada $modo"; return $?; }

    local modo_diretorio
    modo_diretorio=$(stat -c '%a' -- "$diretorio" 2>/dev/null)
    [[ $modo_diretorio =~ ^[0-7]00$ ]] ||
      { _dbx_preflight_falhar credencial "permissao do diretorio de configuracao precisa nao ter bits para grupo e outros, encontrada $modo_diretorio"; return $?; }
    dono=$(stat -c '%u' "$arquivo" 2>/dev/null)
    [[ $dono == "$EUID" ]] ||
      { _dbx_preflight_falhar credencial 'a credencial pertence a outro usuario'; return $?; }
  fi

  DBX_PREFLIGHT_DETALHE=''
  return 0
}

# dbx_preflight_mensagem — diagnostico acionavel, sem qualquer conteudo do
# arquivo de credencial: o preflight inspeciona metadados, nunca o conteudo.
dbx_preflight_mensagem() {
  [[ -n $DBX_PREFLIGHT_MOTIVO ]] || return 1
  dbx_errors_mensagem configuracao "$DBX_PREFLIGHT_DETALHE"
}
