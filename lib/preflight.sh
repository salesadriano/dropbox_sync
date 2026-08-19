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
# O NIVEL E PARAMETRO, E NAO SO VOCABULARIO DA ENTRADA — corrigido ao entrar
# `config`.
#
#   `lib/cli` descreve tres niveis e diz por que eles existem: sem eles, o
#   assistente de configuracao ficaria impossivel de usar exatamente quando e
#   necessario, porque a verificacao RECUSA — nao alerta — diante de credencial
#   fora de `0600`. A regra estava escrita la e NAO estava aplicada aqui: esta
#   funcao inspecionava a credencial em qualquer nivel, entao o nivel `ambiente`
#   herdava a recusa que o nivel `credencial` deveria monopolizar.
#
#   Ninguem percebeu porque os seis comandos do bloco anterior declaram todos
#   `credencial` — o conjunto onde a distincao incide estava VAZIO, e regra sem
#   ocorrencia nao se exerce. `config` e `unlink` sao a primeira e a segunda
#   ocorrencia, e sao justamente as que precisam rodar com a credencial quebrada:
#   uma para regravar, outra para remover. Ha caso que planta credencial em
#   `0644` e exige que `config` passe e que `info` seja recusado — sem o par, a
#   volta do defeito nao seria vista.
#
#   Nada se perde no nivel `ambiente`: `lib/config` reverifica dono e permissao
#   no momento em que o segredo sai do disco, que e o ponto que importa.
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

# Resolucao do proprio diretorio SEM utilitario externo. Usar `dirname`
# aqui criava uma dependencia exercitada ANTES de qualquer verificacao:
# sem ele o componente carregava com status 0 mas quebrado — dependencias
# nunca carregadas, constantes de codigo de erro vazias e caminhos de
# falha devolvendo o status do ultimo comando em vez do classificado.
# `${BASH_SOURCE[0]%/*}` e expansao do proprio shell (TL-30).
_dbx_preflight_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_preflight_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_preflight_diretorio=.
_dbx_preflight_diretorio=$(cd -P -- "$_dbx_preflight_diretorio" && pwd -P)
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
readonly DBX_PREFLIGHT_UTILITARIOS='curl mktemp mv rm chmod mkdir stat head wc readlink dirname find cat sleep'

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

# dbx_preflight_credencial <diretorio> — inspecao de METADADO da credencial.
#
# Conjunto onde incide: exclusivamente o nivel `credencial`. Chamar isto no nivel
# `ambiente` e o defeito descrito no topo.
dbx_preflight_credencial() {
  local diretorio=$1 arquivo modo dono modo_diretorio
  arquivo="$diretorio/credencial.json"

  # Credencial ausente e o estado normal antes da configuracao inicial.
  [[ -e $arquivo ]] || return 0

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

  modo_diretorio=$(stat -c '%a' -- "$diretorio" 2>/dev/null)
  [[ $modo_diretorio =~ ^[0-7]00$ ]] ||
    { _dbx_preflight_falhar credencial "permissao do diretorio de configuracao precisa nao ter bits para grupo e outros, encontrada $modo_diretorio"; return $?; }
  dono=$(stat -c '%u' "$arquivo" 2>/dev/null)
  [[ $dono == "$EUID" ]] ||
    { _dbx_preflight_falhar credencial 'a credencial pertence a outro usuario'; return $?; }
  return 0
}

# dbx_preflight_verificar [nivel] — verificacao do ambiente no nivel pedido.
#
# Sem argumento, assume `credencial`, que e o nivel MAIS ESTRITO. Um recuo para o
# nivel mais fraco transformaria omissao de argumento em afrouxamento silencioso
# de verificacao de seguranca.
dbx_preflight_verificar() {
  local nivel=${1:-credencial}
  local utilitario area_temporaria diretorio

  case $nivel in
    ambiente | credencial) ;;
    *) return "$DBX_PREFLIGHT_ERRO_USO" ;;
  esac

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

  if [[ $nivel == 'credencial' ]]; then
    dbx_preflight_credencial "$diretorio" || return $?
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
