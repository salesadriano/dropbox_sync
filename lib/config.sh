#!/usr/bin/env bash
# lib/config.sh — leitura e gravacao do arquivo de credencial.
#
# Camada: adaptadores. Depende de lib/errors.sh (dominio) e de lib/json.sh.
#
# ESTA E A UNICA ESCRITA PERSISTENTE DE TODO O PROJETO (PRJ-DEC-07). Nao ha
# cache, indice, cursor nem arquivo de trava, e RSK-23 existe para vigiar
# exatamente esta camada, onde um cache pareceria inofensivo.
#
# Formato: JSON. Justificativa da escolha, contra as alternativas:
#
#   1. REAPROVEITA O INTERPRETADOR EXISTENTE. Um segundo caminho de
#      interpretacao seria justamente a fragilidade que `lib/json` existe para
#      eliminar, e o argumento ja foi usado para descartar um extrator dedicado
#      de corpo de erro. Vale igual aqui. RNF-11 foi elevado a defesa principal
#      da interpretacao, e o analisador ja e o componente mais exercitado do
#      projeto.
#   2. SUPORTA CONTEUDO ARBITRARIO. A raiz remota e um caminho da Dropbox e pode
#      conter aspas, barra invertida e quebra de linha. Formato de linha
#      `chave=valor` perderia esses bytes em silencio — a mesma classe de
#      defeito de D1, C2-01 e E2-04. O par escapar/decodificar resolve por
#      construcao.
#   3. PERMANECE EDITAVEL A MAO, o que o requisito pressupoe ao exigir que
#      conteudo malformado de edicao manual seja recusado.
#
# A leitura usa CONTEXTO NOMEADO proprio. Usar o contexto padrao destruiria uma
# listagem em curso — exatamente o modo de falha que o contexto nomeado existe
# para impedir. O nome e literal, portanto passa pela auditoria de procedencia
# de RNF-24.
#
# DP-05 fixou UMA CONTA SO: nao ha nocao de perfil, e nenhuma funcao deste
# componente recebe identificador de conta. Ha auditoria estatica na suite.
#
# DP-11 proibe sobrescrita da credencial por variavel de ambiente, para remover
# o vetor de leitura do ambiente do processo. `XDG_CONFIG_HOME` continua valendo
# porque define LOCALIZACAO, e nao segredo.

[[ -n ${DBX_CONFIG_CARREGADO:-} ]] && return 0
DBX_CONFIG_CARREGADO=1

_dbx_config_diretorio=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_config_diretorio/errors.sh"
# shellcheck source=lib/json.sh
. "$_dbx_config_diretorio/json.sh"
unset _dbx_config_diretorio

DBX_CONFIG_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_CONFIG_ERRO_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
readonly DBX_CONFIG_ERRO_USO DBX_CONFIG_ERRO_CONFIGURACAO

readonly DBX_CONFIG_ARQUIVO='credencial.json'
readonly DBX_CONFIG_VERSAO=1

# shellcheck disable=SC2034  # canais publicos: sao lidos pelo chamador e pela
# suite, e o analisador nao enxerga o uso porque ele ocorre em outro arquivo.
DBX_CONFIG_RESULTADO=''
DBX_CONFIG_MOTIVO=''
DBX_CONFIG_APP_KEY=''
DBX_CONFIG_APP_SECRET=''
DBX_CONFIG_REFRESH_TOKEN=''
DBX_CONFIG_RAIZ_REMOTA=''

_dbx_config_limpar_credencial() {
  DBX_CONFIG_APP_KEY=''
  DBX_CONFIG_APP_SECRET=''
  DBX_CONFIG_REFRESH_TOKEN=''
  DBX_CONFIG_RAIZ_REMOTA=''
}

_dbx_config_falhar() {
  DBX_CONFIG_MOTIVO=$1
  _dbx_config_limpar_credencial
  return "$DBX_CONFIG_ERRO_CONFIGURACAO"
}

# dbx_config_caminho — caminho do arquivo, em DBX_CONFIG_RESULTADO.
dbx_config_caminho() {
  local base=${XDG_CONFIG_HOME:-}
  DBX_CONFIG_RESULTADO=''
  if [[ -z $base ]]; then
    [[ -n ${HOME:-} && $HOME == /* ]] ||
      { _dbx_config_falhar ambiente; return $?; }
    base="$HOME/.config"
  fi
  [[ $base == /* ]] || { _dbx_config_falhar ambiente; return $?; }
  DBX_CONFIG_RESULTADO="$base/dbx/$DBX_CONFIG_ARQUIVO"
}

# dbx_config_gravar <app_key> <app_secret> <refresh_token> <raiz_remota>
#
# Gravacao atomica: escreve num temporario do MESMO diretorio, com permissao
# restrita desde a criacao, e so entao renomeia. Renomear dentro do mesmo
# sistema de arquivos e atomico, entao um leitor concorrente ve o arquivo antigo
# ou o novo, nunca um pela metade. Se qualquer etapa falhar, o arquivo anterior
# permanece intacto — perder a credencial que funcionava deixaria o usuario sem
# acesso e sem forma de voltar.
dbx_config_gravar() {
  [[ $# -eq 4 ]] || return "$DBX_CONFIG_ERRO_USO"
  local app_key=$1 app_secret=$2 refresh_token=$3 raiz=$4
  local diretorio temporario corpo

  dbx_config_caminho || return $?
  diretorio=$(dirname -- "$DBX_CONFIG_RESULTADO")

  # `umask` restritivo cobre a janela entre criar e ajustar a permissao.
  local mascara_anterior
  mascara_anterior=$(umask)
  umask 077

  # A permissao do diretorio e ajustada apenas quando NOS o criamos. Forcar 700
  # a cada gravacao desfaria em silencio uma permissao que o operador tenha
  # escolhido deliberadamente — inclusive uma mais restritiva.
  if [[ ! -d $diretorio ]]; then
    mkdir -p -- "$diretorio" 2>/dev/null || {
      umask "$mascara_anterior"
      _dbx_config_falhar diretorio
      return $?
    }
    chmod 700 -- "$diretorio" 2>/dev/null
  fi

  corpo='{'
  corpo+="\"versao\":$DBX_CONFIG_VERSAO"
  dbx_json_escapar_cadeia "$app_key"
  corpo+=",\"app_key\":\"$DBX_JSON_ESCAPADO\""
  dbx_json_escapar_cadeia "$app_secret"
  corpo+=",\"app_secret\":\"$DBX_JSON_ESCAPADO\""
  dbx_json_escapar_cadeia "$refresh_token"
  corpo+=",\"refresh_token\":\"$DBX_JSON_ESCAPADO\""
  dbx_json_escapar_cadeia "$raiz"
  corpo+=",\"raiz_remota\":\"$DBX_JSON_ESCAPADO\""
  corpo+='}'

  temporario=$(mktemp "$diretorio/.credencial.XXXXXXXX" 2>/dev/null) || {
    umask "$mascara_anterior"
    _dbx_config_falhar gravacao
    return $?
  }
  if ! printf '%s\n' "$corpo" >"$temporario" 2>/dev/null ||
    ! chmod 600 -- "$temporario" 2>/dev/null ||
    ! mv -f -- "$temporario" "$DBX_CONFIG_RESULTADO" 2>/dev/null; then
    rm -f -- "$temporario" 2>/dev/null
    umask "$mascara_anterior"
    _dbx_config_falhar gravacao
    return $?
  fi

  umask "$mascara_anterior"
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_CONFIG_MOTIVO=''
  return 0
}

# dbx_config_carregar — le e valida a credencial.
dbx_config_carregar() {
  local arquivo modo dono conteudo campo

  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_CONFIG_MOTIVO=''
  _dbx_config_limpar_credencial

  dbx_config_caminho || return $?
  arquivo=$DBX_CONFIG_RESULTADO

  [[ -f $arquivo ]] || { _dbx_config_falhar ausente; return $?; }

  # A permissao e verificada tambem aqui, e nao apenas no preflight: entre um e
  # outro o arquivo pode ter mudado, e a leitura e o ponto em que o segredo
  # efetivamente sai do disco.
  modo=$(stat -c '%a' -- "$arquivo" 2>/dev/null) ||
    { _dbx_config_falhar inspecao; return $?; }
  [[ $modo == '600' ]] || { _dbx_config_falhar permissao; return $?; }
  dono=$(stat -c '%u' -- "$arquivo" 2>/dev/null)
  [[ $dono == "$EUID" ]] || { _dbx_config_falhar dono; return $?; }

  IFS= read -r -d '' conteudo <"$arquivo"
  [[ -n $conteudo ]] || { _dbx_config_falhar vazio; return $?; }

  # Contexto proprio: interpretar no contexto padrao destruiria um documento em
  # curso, como uma listagem paginada.
  # Nome LITERAL, e nao constante: a auditoria de procedencia de RNF-24 so
  # aceita literal do alfabeto permitido ou a variavel de restauracao publicada
  # pelo proprio analisador. Passar por uma constante, ainda que somente de
  # leitura, exigiria da auditoria um raciocinio que ela nao pode fazer — e
  # afrouxa-la para acomodar este componente enfraqueceria a garantia inteira.
  dbx_json_contexto config || { _dbx_config_falhar contexto; return $?; }

  if ! dbx_json_analisar "$conteudo"; then
    dbx_json_descartar config
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    _dbx_config_falhar malformado
    return $?
  fi

  for campo in app_key app_secret refresh_token raiz_remota; do
    if ! dbx_json_valor "$campo" >/dev/null || [[ $(dbx_json_tipo "$campo") != 'cadeia' ]]; then
      dbx_json_descartar config
      dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
      _dbx_config_falhar incompleto
      return $?
    fi
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    case $campo in
      app_key) DBX_CONFIG_APP_KEY=$DBX_JSON_RESULTADO ;;
      app_secret) DBX_CONFIG_APP_SECRET=$DBX_JSON_RESULTADO ;;
      refresh_token) DBX_CONFIG_REFRESH_TOKEN=$DBX_JSON_RESULTADO ;;
      raiz_remota) DBX_CONFIG_RAIZ_REMOTA=$DBX_JSON_RESULTADO ;;
    esac
  done

  # O documento e descartado assim que os campos sao extraidos: manter o segredo
  # tambem na arvore do analisador ampliaria sem necessidade a superficie em que
  # ele existe em memoria.
  dbx_json_descartar config
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  return 0
}
