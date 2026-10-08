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
#
# PROPRIEDADE PRETENDIDA, e nao acidental: quem controla o ambiente pode apontar
# `XDG_CONFIG_HOME` para um diretorio proprio, mas as verificacoes de dono e de
# permissao recusam a credencial plantada. O ataque degrada para NEGACAO DE
# SERVICO, e nao substituicao de credencial. Isso fica registrado como intencao
# porque, se constasse apenas como efeito colateral, um afrouxamento futuro da
# verificacao de dono removeria a protecao sem que a ligacao fosse percebida.
#
# FRONTEIRA DE CONFIANCA: o usuario do sistema. Contra o proprio usuario a
# substituicao sempre sera possivel, porque ele pode escrever o arquivo real sem
# recorrer a variavel alguma. O que estas verificacoes impedem e a substituicao
# por OUTRO usuario e o desvio por ambiente.

[[ -n ${DBX_CONFIG_CARREGADO:-} ]] && return 0
DBX_CONFIG_CARREGADO=1

# Resolucao do proprio diretorio SEM utilitario externo. Usar `dirname`
# aqui criava uma dependencia exercitada ANTES de qualquer verificacao:
# sem ele o componente carregava com status 0 mas quebrado — dependencias
# nunca carregadas, constantes de codigo de erro vazias e caminhos de
# falha devolvendo o status do ultimo comando em vez do classificado.
# `${BASH_SOURCE[0]%/*}` e expansao do proprio shell (TL-30).
_dbx_config_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_config_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_config_diretorio=.
_dbx_config_diretorio=$(cd -P -- "$_dbx_config_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_config_diretorio/errors.sh"
# shellcheck source=lib/json.sh
. "$_dbx_config_diretorio/json.sh"
unset _dbx_config_diretorio

DBX_CONFIG_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_CONFIG_ERRO_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
readonly DBX_CONFIG_ERRO_USO DBX_CONFIG_ERRO_CONFIGURACAO

readonly DBX_CONFIG_ARQUIVO='credencial.json'
# Minutos a partir dos quais um temporario e considerado orfao mesmo com
# processo vivo. Gravacao legitima e instantanea; a folga e larga de proposito.
readonly DBX_CONFIG_IDADE_ORFAO=5
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

# _dbx_config_varrer_orfaos <diretorio>
#
# Remove temporarios deixados por interrupcao. Um `SIGKILL` durante a gravacao
# nao pode ser interceptado, entao o temporario — que CONTEM O SEGREDO, com
# permissao 0600 — sobrevivia indefinidamente num arquivo oculto que nenhum
# caminho de codigo removia. Isso contradizia a invariante de escrita unica e
# derrotava a rotacao de credencial, porque o token antigo permanecia em disco.
#
# O nome do temporario carrega o identificador do processo que o criou, e so os
# de processos MORTOS sao removidos. Sem isso, a varredura apagaria o
# temporario de uma gravacao concorrente em andamento.
_dbx_config_varrer_orfaos() {
  local diretorio=$1 orfao processo
  [[ -d $diretorio ]] || return 0
  for orfao in "$diretorio"/.credencial.*; do
    [[ -e $orfao ]] || continue
    processo=${orfao##*/.credencial.}
    processo=${processo%%.*}
    # Criterio duplo. So o processo nao basta: um temporario nomeado com o
    # identificador de um processo VIVO qualquer sobrevive indefinidamente, e a
    # reciclagem de identificadores torna o orfao permanente — a varredura era
    # probabilistica (R2-03). A idade cobre esse caso sem quebrar a
    # concorrencia, porque nenhuma gravacao legitima leva minutos.
    if [[ $processo =~ ^[0-9]+$ ]] && kill -0 "$processo" 2>/dev/null; then
      # Processo vivo: so remove se for antigo demais para ser uma gravacao em
      # andamento.
      [[ -n $(find "$orfao" -mmin +"$DBX_CONFIG_IDADE_ORFAO" 2>/dev/null) ]] || continue
    fi
    rm -f -- "$orfao" 2>/dev/null
  done
  return 0
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

# dbx_config_caminho_de_estado — diretorio do estado, em DBX_CONFIG_RESULTADO.
#
# NAO E CONFIGURACAO, e por isso nao mora junto da credencial: DP-23 poe a linha
# de base sob `$XDG_STATE_HOME`, com recuo para `~/.local/state`, porque estado e
# descartavel e reconstruivel enquanto credencial nao e. Misturar os dois faria
# um backup de configuracao arrastar estado, e um descarte de estado arrastar
# credencial.
#
# A funcao mora aqui, e nao em quem a usa, por uma razao ja aprendida: `unlink`
# precisa do caminho para invalidar as bases (RF-51d) e `lib/state` vai precisar
# do mesmo caminho para cria-las. Duas contas do mesmo caminho divergem, e a
# divergencia so aparece no dia em que uma delas apaga o lugar errado. Quem
# escrever `lib/state` chama esta funcao em vez de recalcular.
dbx_config_caminho_de_estado() {
  local base=${XDG_STATE_HOME:-}
  DBX_CONFIG_RESULTADO=''
  if [[ -z $base ]]; then
    [[ -n ${HOME:-} && $HOME == /* ]] ||
      { _dbx_config_falhar ambiente; return $?; }
    base="$HOME/.local/state"
  fi
  [[ $base == /* ]] || { _dbx_config_falhar ambiente; return $?; }
  DBX_CONFIG_RESULTADO="$base/dbx"
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
  # Expansao do proprio shell, e nao captura: `$(dirname ...)` removeria uma
  # quebra de linha final do caminho, que e a mesma classe de C2-01 — la a raiz
  # `algo\n` passou a designar o diretorio irmao `algo`.
  diretorio=${DBX_CONFIG_RESULTADO%/*}

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
  # A cadeia escapada do segredo nao pode sobreviver a montagem do documento.
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  corpo+='}'

  _dbx_config_varrer_orfaos "$diretorio"

  temporario=$(mktemp "$diretorio/.credencial.$$.XXXXXXXX" 2>/dev/null) || {
    umask "$mascara_anterior"
    _dbx_config_falhar gravacao
    return $?
  }
  # A escrita ocorre em subshell com `trap` proprio, para que sinal
  # interceptavel durante a gravacao remova o temporario sem alterar os `trap`
  # do processo chamador. `SIGKILL` continua fora de alcance por definicao, e e
  # a varredura de orfaos que cobre esse caso.
  if ! (
    trap 'rm -f -- "$1" 2>/dev/null' EXIT INT TERM HUP
    set -- "$temporario"
    printf '%s\n' "$corpo" >"$1" &&
      chmod 600 -- "$1" &&
      mv -f -- "$1" "$DBX_CONFIG_RESULTADO"
  ) 2>/dev/null; then
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

# _dbx_config_encerrar_analise [motivo] — saida UNICA do bloco de analise.
#
# Conjunto onde incide: TODA saida do bloco de analise de `dbx_config_carregar`,
# de exito ou de falha. Antes havia tres saidas escrevendo a mesma sequencia, e a
# limpeza do canal escalar do analisador estava em UMA delas — a de exito.
#
# O QUE FOI MEDIDO, e o que nao foi. Eu havia escrito aqui que uma falha no
# quarto campo deixava o refresh token publicado numa variavel global. FUI
# VERIFICAR E E FALSO: `dbx_json_valor` limpa o proprio resultado quando a
# consulta falha, e quando ela tem exito o valor publicado e o do campo
# consultado. Como `refresh_token` e o TERCEIRO campo e `raiz_remota` o quarto,
# nenhum modo de falha atual deixa o segredo no canal — medidos os tres:
# campo ausente devolve vazio, tipo numero devolve o numero, tipo nulo devolve
# vazio.
#
# A refatoracao continua justificada, por outro motivo e mais fraco: a
# propriedade valia POR ORDEM DE CAMPO, e nao por construcao. Bastava acrescentar
# um quinto campo depois de `raiz_remota`, ou trocar a ordem do laco, para que a
# falha passasse a ocorrer com o segredo como ultimo valor lido — e nada
# reprovaria. Com saida unica, a limpeza deixa de depender de onde o campo esta
# na lista. Ha auditoria estatica que reprova o retorno das saidas multiplas,
# porque e ela, e nao um caso de dado, que protege esta propriedade.
_dbx_config_encerrar_analise() {
  dbx_json_descartar config
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_RESULTADO=''
  [[ -n ${1:-} ]] || return 0
  _dbx_config_falhar "$1"
  return $?
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
  # Aceita QUALQUER modo sem bits para grupo e outros, e nao apenas 0600: 0400
  # e mais restritiva e recusa-la desfaria a escolha do operador — o mesmo
  # principio ja aplicado ao diretorio, que nao estava aplicado ao arquivo
  # (P3-03). Exige-se leitura para o dono, sem a qual a operacao nao ocorre.
  [[ $modo =~ ^[4567]00$ ]] || { _dbx_config_falhar permissao; return $?; }

  # A permissao do DIRETORIO tambem e verificada: um diretorio 0777 permite
  # substituir o arquivo por outro, e nenhum dos dois caminhos olhava para ele
  # (P3-04).
  local modo_diretorio
  modo_diretorio=$(stat -c '%a' -- "${arquivo%/*}" 2>/dev/null) ||
    { _dbx_config_falhar inspecao; return $?; }
  [[ $modo_diretorio =~ ^[0-7]00$ ]] ||
    { _dbx_config_falhar permissao_diretorio; return $?; }
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
    _dbx_config_encerrar_analise malformado
    return $?
  fi

  for campo in app_key app_secret refresh_token raiz_remota; do
    if ! dbx_json_valor "$campo" >/dev/null || [[ $(dbx_json_tipo "$campo") != 'cadeia' ]]; then
      _dbx_config_encerrar_analise incompleto
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

  # CADEIA VAZIA E CAMPO INCOMPLETO, e nao campo presente.
  #
  # Descoberto ao implementar `unlink --manter-aplicativo`, que preserva `app
  # key` e `app secret` e apaga so o refresh token: o resultado passava por
  # aqui como credencial VALIDA, e a recusa aparecia so em `dbx_auth_renovar`,
  # como `uso_invalido` (2). RF-51(e) exige `3` — erro de CONFIGURACAO — para o
  # comando autenticado seguinte, e a diferenca nao e cosmetica: `2` manda
  # revisar a linha de comando, `3` manda reconfigurar, que e o que o operador
  # de fato precisa fazer.
  #
  # `app_secret` fica de fora da exigencia porque aplicativo sem segredo e
  # legitimo, e `dbx_auth_renovar` ja o trata como opcional. `raiz_remota`
  # tambem: vazio e a raiz da conta na representacao da API.
  if [[ -z $DBX_CONFIG_APP_KEY || -z $DBX_CONFIG_REFRESH_TOKEN ]]; then
    _dbx_config_encerrar_analise incompleto
    return $?
  fi

  # O documento e descartado assim que os campos sao extraidos: manter o segredo
  # tambem na arvore do analisador ampliaria sem necessidade a superficie em que
  # ele existe em memoria. O mesmo vale para o canal escalar, e por isso as duas
  # limpezas moram no encerramento unico.
  _dbx_config_encerrar_analise
  return 0
}

# dbx_config_remover <modo> — desfaz a persistencia da credencial (RF-51 b, c).
#
#   integral    remove o arquivo inteiro, `app key` e `app secret` inclusive.
#               E o PADRAO por decisao de RF-51(c): os dois sao segredos, e
#               manter segredo de uma instalacao que se acabou de desvincular
#               contradiz o proprio verbo.
#   aplicativo  preserva `app key` e `app secret` e apaga so o refresh token.
#               So ocorre sob sinalizador explicito, para religar depois sem
#               voltar ao console do desenvolvedor.
#
# O modo `aplicativo` REESCREVE pelo mesmo caminho atomico da gravacao normal, em
# vez de editar o arquivo no lugar: edicao no lugar teria uma janela em que o
# arquivo esta pela metade, e a substituicao atomica ja resolve isso desde a
# primeira versao deste componente.
dbx_config_remover() {
  local modo=${1:-integral}

  dbx_config_caminho || return $?
  local arquivo=$DBX_CONFIG_RESULTADO

  case $modo in
    integral)
      # A varredura de orfaos entra aqui tambem: um temporario abandonado
      # CONTEM O SEGREDO, e remover so o arquivo final deixaria em disco
      # justamente o que o desvinculo existe para eliminar.
      _dbx_config_varrer_orfaos "${arquivo%/*}"
      if [[ -e $arquivo ]] && ! rm -f -- "$arquivo" 2>/dev/null; then
        _dbx_config_falhar remocao
        return $?
      fi
      _dbx_config_limpar_credencial
      return 0
      ;;
    aplicativo)
      # Exige credencial ja carregada: sem `app key` em memoria nao ha o que
      # preservar, e regravar com campo vazio produziria arquivo que este
      # componente recusa a ler — falha adiante, no lugar errado.
      [[ -n $DBX_CONFIG_APP_KEY ]] || {
        _dbx_config_falhar sem_aplicativo
        return $?
      }
      dbx_config_gravar "$DBX_CONFIG_APP_KEY" "$DBX_CONFIG_APP_SECRET" '' \
        "$DBX_CONFIG_RAIZ_REMOTA" || return $?
      _dbx_config_limpar_credencial
      return 0
      ;;
    *) return "$DBX_CONFIG_ERRO_USO" ;;
  esac
}
