#!/usr/bin/env bash
# lib/config.sh — leitura e gravacao do arquivo de credencial.
#
# Camada: adaptadores. Depende de lib/errors.sh (dominio) e de lib/json.sh.
#
# A CREDENCIAL E O UNICO ARQUIVO QUE GUARDA SEGREDO. O outro estado em disco e
# a memoria de hash de `lib/state` (RF-38, RF-61), que nao guarda segredo
# algum. Esta camada nao guarda cursor, indice nem arquivo de trava: RSK-23
# vigia exatamente aqui, onde um cache pareceria inofensivo.
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
# PERFIS NOMEADOS (fase 8, F-18; DP-05 reaberta pelo solicitante em 2026-10-21):
# `credencial.json` e o perfil `padrao`; os demais ficam em `perfis/<nome>.json`.
# O nome do perfil e DADO DE CAMINHO (RNF-37): uma funcao o valida
# (`dbx_config_perfil_validar`) e uma o compoe em caminho
# (`dbx_config_caminho_de_perfil`, que valida antes). So uma lista fechada de
# funcoes deste componente lida com nome de perfil, e NENHUMA outra camada
# recebe perfil ou conta; ha auditoria estatica com mutacao na suite (RSK-90).
# Perfil inexistente NUNCA recua para o `padrao`.
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
# shellcheck source=lib/tmp.sh
. "$_dbx_config_diretorio/tmp.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_config_diretorio/hash.sh"
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
DBX_CONFIG_DETALHE=''
DBX_CONFIG_APP_KEY=''
DBX_CONFIG_APP_SECRET=''
DBX_CONFIG_REFRESH_TOKEN=''
DBX_CONFIG_RAIZ_REMOTA=''
# Resumo local da credencial, por `dbx_config_identidade`.
DBX_CONFIG_IDENTIDADE=''

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
  DBX_CONFIG_DETALHE=${2:-}
  _dbx_config_limpar_credencial
  return "$DBX_CONFIG_ERRO_CONFIGURACAO"
}

# ---------------------------------------------------------------------------
# Perfis nomeados (fase 8). Lista fechada das funcoes que lidam com nome:
#   dbx_config_perfil_validar, dbx_config_perfil_selecionar,
#   dbx_config_perfil_do_ambiente, dbx_config_perfil_nomeado,
#   dbx_config_caminho_de_perfil, dbx_config_verificar_destino,
#   dbx_config_identidade_de_perfil, dbx_config_perfis_listar
# (mais os auxiliares `_dbx_config_verificar_cadeia` e o `dbx_config_caminho`,
# que apenas repassa a selecao).
# ---------------------------------------------------------------------------

readonly DBX_CONFIG_PERFIL_PADRAO='padrao'
readonly DBX_CONFIG_DIRETORIO_PERFIS='perfis'
# Alfabeto por caracteres EXPLICITOS (nada de intervalo dependente de
# localidade): 1 a 32 caracteres, o primeiro letra minuscula ou digito.
readonly DBX_CONFIG_PERFIL_RE='^[abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789_-]{0,31}$'

# Selecao corrente. Vazia: nenhuma selecao (o `padrao` implicito).
DBX_CONFIG_PERFIL=''
# `opcao` ou `ambiente` quando houve selecao explicita; vazia sem selecao.
DBX_CONFIG_PERFIL_ORIGEM=''
DBX_CONFIG_PERFIS_NOME=()
DBX_CONFIG_PERFIS_CREDENCIAL=()
DBX_CONFIG_PERFIS_ARQUIVO=()
DBX_CONFIG_PERFIS_IGNORADAS=()

# dbx_config_perfil_validar <nome> [opcao|ambiente] — PONTO UNICO da validacao
# (RF-121, RNF-37): comprimento e alfabeto, sem lista de nomes proibidos e sem
# tocar disco. 0 valido; senao `uso_invalido` (2) com a mensagem em
# DBX_CONFIG_DETALHE. O valor vindo do ambiente NUNCA e ecoado (RF-121(e)).
dbx_config_perfil_validar() {
  local nome=${1-} origem=${2:-opcao} exibido LC_ALL=C
  DBX_CONFIG_MOTIVO=''
  DBX_CONFIG_DETALHE=''
  [[ $nome =~ $DBX_CONFIG_PERFIL_RE ]] && return 0
  DBX_CONFIG_MOTIVO='perfil_invalido'
  if [[ $origem == 'ambiente' ]]; then
    DBX_CONFIG_DETALHE='variavel de ambiente DBX_PERFIL invalida; use 1 a 32 caracteres de a-z, 0-9, _ e -, comecando por letra ou digito, ou remova-a (unset DBX_PERFIL)'
  else
    exibido=${nome:0:64}
    [[ $exibido == *[$'\001'-$'\037\177']* ]] && printf -v exibido '%q' "$exibido"
    DBX_CONFIG_DETALHE="nome de perfil invalido: [$exibido]; use 1 a 32 caracteres de a-z, 0-9, _ e -, comecando por letra ou digito"
  fi
  return "$DBX_CONFIG_ERRO_USO"
}

# dbx_config_perfil_selecionar <nome> <opcao|ambiente> — valida e fixa a
# selecao. Nome invalido nao fica selecionado.
dbx_config_perfil_selecionar() {
  dbx_config_perfil_validar "${1-}" "${2:-opcao}" || return $?
  DBX_CONFIG_PERFIL=$1
  DBX_CONFIG_PERFIL_ORIGEM=${2:-opcao}
  return 0
}

# dbx_config_perfil_do_ambiente — `DBX_PERFIL` (so o NOME; DP-11): vazia vale
# como nao definida, a opcao ja selecionada vence, e o valor so e validado
# quando usado (RF-120(c)(d), DIV-240).
dbx_config_perfil_do_ambiente() {
  [[ -z $DBX_CONFIG_PERFIL_ORIGEM && -n ${DBX_PERFIL:-} ]] || return 0
  dbx_config_perfil_selecionar "$DBX_PERFIL" ambiente
}

# dbx_config_perfil_nomeado — 0 quando o perfil selecionado NAO e o `padrao`.
dbx_config_perfil_nomeado() {
  [[ -n $DBX_CONFIG_PERFIL && $DBX_CONFIG_PERFIL != "$DBX_CONFIG_PERFIL_PADRAO" ]]
}

# _dbx_config_diretorio_base — `<base>/dbx` em DBX_CONFIG_RESULTADO.
_dbx_config_diretorio_base() {
  local base=${XDG_CONFIG_HOME:-}
  DBX_CONFIG_RESULTADO=''
  if [[ -z $base ]]; then
    [[ -n ${HOME:-} && $HOME == /* ]] ||
      { _dbx_config_falhar ambiente; return $?; }
    base="$HOME/.config"
  fi
  [[ $base == /* ]] || { _dbx_config_falhar ambiente; return $?; }
  DBX_CONFIG_RESULTADO="$base/dbx"
}

# dbx_config_caminho_de_perfil <nome> — PONTO UNICO de composicao de caminho a
# partir de nome (RNF-37). Valida ANTES; o `padrao` e o `credencial.json` de
# sempre, e `perfis/padrao.json` e reservado (nunca composto).
dbx_config_caminho_de_perfil() {
  local nome=${1-}
  DBX_CONFIG_RESULTADO=''
  dbx_config_perfil_validar "$nome" || return $?
  _dbx_config_diretorio_base || return $?
  if [[ $nome == "$DBX_CONFIG_PERFIL_PADRAO" ]]; then
    DBX_CONFIG_RESULTADO="$DBX_CONFIG_RESULTADO/$DBX_CONFIG_ARQUIVO"
  else
    DBX_CONFIG_RESULTADO="$DBX_CONFIG_RESULTADO/$DBX_CONFIG_DIRETORIO_PERFIS/$nome.json"
  fi
}

# dbx_config_mensagem_de_indisponibilidade — texto de "credencial indisponivel"
# para o ponto de entrada, a partir de DBX_CONFIG_MOTIVO. Sem perfil nomeado, o
# texto de sempre; com ele, nomeia o perfil e o remedio (RF-122(b)). Nunca traz
# conteudo do arquivo.
dbx_config_mensagem_de_indisponibilidade() {
  local texto="credencial indisponivel: $DBX_CONFIG_MOTIVO"
  if dbx_config_perfil_nomeado; then
    texto="perfil $DBX_CONFIG_PERFIL: $texto"
    [[ -n $DBX_CONFIG_DETALHE ]] && texto+=" ($DBX_CONFIG_DETALHE)"
    [[ $DBX_CONFIG_MOTIVO == 'ausente' ]] && texto+="; crie-o com: dbx config --perfil $DBX_CONFIG_PERFIL"
  fi
  printf '%s' "$texto"
}

# dbx_config_caminho — caminho do arquivo do perfil selecionado (o `padrao`
# sem selecao), em DBX_CONFIG_RESULTADO.
dbx_config_caminho() {
  dbx_config_caminho_de_perfil "${DBX_CONFIG_PERFIL:-$DBX_CONFIG_PERFIL_PADRAO}"
}

_dbx_config_dono_e_modo_do_diretorio_ok() {
  local diretorio=$1 modo dono
  modo=$(stat -c '%a' -- "$diretorio" 2>/dev/null || stat -f '%Lp' "$diretorio" 2>/dev/null) || return 1
  dono=$(stat -c '%u' -- "$diretorio" 2>/dev/null || stat -f '%u' "$diretorio" 2>/dev/null) || return 1
  [[ $modo =~ ^[0-7]00$ && $dono == "$EUID" ]]
}

# _dbx_config_verificar_cadeia <arquivo> <simbolicos|completo> — verificacoes
# de PERFIL nomeado (RF-122(c), C2 do DBA): `dbx/`, `perfis/` e o arquivo nao
# sao ligacao simbolica (inclusive pendente) e, em `completo`, os dois
# diretorios tem modo sem bits para grupo e outros e dono do usuario.
_dbx_config_verificar_cadeia() {
  local arquivo=$1 nivel=$2 perfis base dir
  perfis=${arquivo%/*}
  base=${perfis%/*}
  if [[ -L $base || -L $perfis || -L $arquivo ]]; then
    _dbx_config_falhar ligacao_simbolica
    return $?
  fi
  [[ $nivel == 'completo' ]] || return 0
  for dir in "$base" "$perfis"; do
    [[ -e $dir ]] || continue
    _dbx_config_dono_e_modo_do_diretorio_ok "$dir" ||
      { _dbx_config_falhar permissao_diretorio "$dir"; return $?; }
  done
  return 0
}

# _dbx_config_verificar_cadeia_sem_arquivo <arquivo> — so `dbx/` e `perfis/`
# simbolicos: a remocao do proprio arquivo simbolico e segura (`rm` o remove sem
# segui-lo), mas nunca atraves de diretorio simbolico.
_dbx_config_verificar_cadeia_sem_arquivo() {
  local perfis=${1%/*}
  if [[ -L $perfis || -L ${perfis%/*} ]]; then
    _dbx_config_falhar ligacao_simbolica
    return $?
  fi
  return 0
}

# _dbx_config_varrer_perfis <diretorio> — varredura de orfaos em `perfis/`, so
# quando e diretorio de verdade (nunca atraves de ligacao simbolica).
_dbx_config_varrer_perfis() {
  [[ -d $1 && ! -L $1 ]] || return 0
  _dbx_config_varrer_orfaos "$1"
}

# dbx_config_verificar_destino — recusa ANTES de perguntar (RF-123(b), DIV-244)
# quando o destino do perfil selecionado e inseguro. No `padrao`, nada novo.
dbx_config_verificar_destino() {
  DBX_CONFIG_MOTIVO=''
  dbx_config_perfil_nomeado || return 0
  dbx_config_caminho || return $?
  _dbx_config_verificar_cadeia "$DBX_CONFIG_RESULTADO" completo
}

# dbx_config_identidade_de_perfil <nome> — identidade `cred-` de OUTRO perfil,
# em DBX_CONFIG_IDENTIDADE, sem deixar segredo nos canais (RF-122(f)). Perfil
# nao comparavel (ilegivel, inseguro, incompleto): status de configuracao e
# identidade vazia.
dbx_config_identidade_de_perfil() {
  local estado
  DBX_CONFIG_IDENTIDADE=''
  dbx_config_caminho_de_perfil "${1-}" || return $?
  dbx_config_carregar "$DBX_CONFIG_RESULTADO" "$1"
  estado=$?
  if [[ $estado -eq 0 ]]; then
    dbx_config_identidade
    [[ -n $DBX_CONFIG_IDENTIDADE ]] || estado=$DBX_CONFIG_ERRO_CONFIGURACAO
  fi
  _dbx_config_limpar_credencial
  return "$estado"
}

# dbx_config_perfis_listar — `padrao` (so se `credencial.json` existir) e cada
# `perfis/<nome>.json` de nome valido, nesta ordem e depois em ordem de bytes,
# com o veredito da credencial, sem segredo (RF-126, DIV-242, DIV-243). Nao
# cria nada. Entradas anomalas vao para DBX_CONFIG_PERFIS_IGNORADAS; ocultas
# (inclusive `.credencial.*`) sao ignoradas em silencio.
dbx_config_perfis_listar() {
  local LC_ALL=C diretorio base entrada nome arquivo veredito estado i j tmp
  local -a nomes=() validos=()
  DBX_CONFIG_PERFIS_NOME=() DBX_CONFIG_PERFIS_CREDENCIAL=() DBX_CONFIG_PERFIS_ARQUIVO=()
  DBX_CONFIG_PERFIS_IGNORADAS=()
  _dbx_config_diretorio_base || return $?
  base=$DBX_CONFIG_RESULTADO
  diretorio="$base/$DBX_CONFIG_DIRETORIO_PERFIS"

  [[ -e $base/$DBX_CONFIG_ARQUIVO ]] && nomes+=("$DBX_CONFIG_PERFIL_PADRAO")
  if [[ -L $diretorio ]]; then
    DBX_CONFIG_PERFIS_IGNORADAS+=("$DBX_CONFIG_DIRETORIO_PERFIS (ligacao simbolica)")
  elif [[ -d $diretorio ]]; then
    for entrada in "$diretorio"/*; do
      [[ -e $entrada || -L $entrada ]] || continue
      nome=${entrada##*/}
      if [[ $nome == *.json && ${nome%.json} != "$DBX_CONFIG_PERFIL_PADRAO" &&
        ${nome%.json} =~ $DBX_CONFIG_PERFIL_RE && (-L $entrada || -f $entrada) ]]; then
        validos+=("${nome%.json}")
      else
        DBX_CONFIG_PERFIS_IGNORADAS+=("$nome")
      fi
    done
    # Ordem de bytes sob LC_ALL=C, por insercao (sem utilitario externo).
    for ((i = 1; i < ${#validos[@]}; i++)); do
      tmp=${validos[i]}
      for ((j = i - 1; j >= 0; j--)); do
        [[ ${validos[j]} > $tmp ]] || break
        validos[j + 1]=${validos[j]}
      done
      validos[j + 1]=$tmp
    done
    nomes+=(${validos[@]+"${validos[@]}"})
  fi

  for nome in ${nomes[@]+"${nomes[@]}"}; do
    dbx_config_caminho_de_perfil "$nome" || continue
    arquivo=$DBX_CONFIG_RESULTADO
    dbx_config_carregar "$arquivo" "$nome"
    estado=$?
    veredito=completa
    if [[ $estado -ne 0 ]]; then
      case $DBX_CONFIG_MOTIVO in
        incompleto) veredito=incompleta ;;
        permissao | permissao_diretorio | dono) veredito=permissao ;;
        ligacao_simbolica) veredito=ligacao_simbolica ;;
        *) veredito=ilegivel ;;
      esac
    elif [[ -z $DBX_CONFIG_APP_SECRET ]]; then
      veredito=incompleta
    fi
    _dbx_config_limpar_credencial
    DBX_CONFIG_MOTIVO=''
    DBX_CONFIG_PERFIS_NOME+=("$nome")
    DBX_CONFIG_PERFIS_CREDENCIAL+=("$veredito")
    DBX_CONFIG_PERFIS_ARQUIVO+=("$arquivo")
  done
  return 0
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

# dbx_config_identidade — identificador LOCAL da conta vinculada, para a chave da
# trava de concorrencia (RF-69(a)), em DBX_CONFIG_IDENTIDADE.
#
# Por que nao o `account_id` (RF-52): ele so vem da API, e a trava precisa ser
# adquirida antes de qualquer chamada (RF-69(d)), antes da colisao de caixa do
# `verificar` (RF-65(c)) e sem mudar o conjunto de chamadas dele (RF-65(b)). O
# refresh token pertence a UMA conta e a um aplicativo: o resumo dele separa
# contas sem sair da maquina. O segredo so atravessa um cano ate o resumo; o
# que sai e hexadecimal truncado, do qual o token nao se recupera. Sem
# credencial carregada, vazio (a trava usa o marcador `sem-conta`).
dbx_config_identidade() {
  local resumo
  DBX_CONFIG_IDENTIDADE=''
  [[ -n $DBX_CONFIG_REFRESH_TOKEN ]] || return 0
  resumo=$(printf 'identidade\n%s\n%s' "$DBX_CONFIG_APP_KEY" "$DBX_CONFIG_REFRESH_TOKEN" |
    dbx_hash_conteudo_fluxo 2>/dev/null) || return 0
  # shellcheck disable=SC2034  # canal publico, lido por lib/cmd
  [[ $resumo =~ ^[0-9a-f]{64}$ ]] && DBX_CONFIG_IDENTIDADE="cred-${resumo:0:32}"
  return 0
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
  # Perfil nomeado: destino inseguro recusa ANTES de qualquer escrita (RF-123(b)).
  dbx_config_verificar_destino || return $?
  local base_nova='nao'
  [[ -d ${diretorio%/*} ]] || base_nova='sim'

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
    chmod 700 "$diretorio" 2>/dev/null
    # `dbx/` criado por este mkdir -p so existe se NOS o criamos.
    if dbx_config_perfil_nomeado && [[ $base_nova == 'sim' ]]; then
      chmod 700 "${diretorio%/*}" 2>/dev/null
    fi
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

  # O temporario e registrado em `lib/tmp` desde a criacao (RNF-35): sinal
  # interceptavel durante a gravacao o remove, sem `trap` proprio. `SIGKILL`
  # continua fora de alcance por definicao, e e a varredura de orfaos que cobre
  # esse caso.
  dbx_tmp_arquivo "$diretorio/.credencial.$$.XXXXXXXX" || {
    umask "$mascara_anterior"
    _dbx_config_falhar gravacao "nao foi possivel criar o arquivo temporario em: $diretorio"
    return $?
  }
  temporario=$DBX_TMP_CAMINHO
  # Canal alheio lido por componente que lida com o segredo: esvaziado aqui.
  DBX_TMP_CAMINHO=''

  local saida_gravacao
  if ! saida_gravacao=$(
    printf '%s\n' "$corpo" >"$temporario" &&
      chmod 600 -- "$temporario" &&
      mv -f -- "$temporario" "$DBX_CONFIG_RESULTADO"
  ) 2>&1; then
    dbx_tmp_remover "$temporario"
    umask "$mascara_anterior"
    _dbx_config_falhar gravacao "${saida_gravacao:-falha ao gravar ou mover credencial}"
    return $?
  fi
  dbx_tmp_esquecer "$temporario"

  umask "$mascara_anterior"
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_CONFIG_MOTIVO=''
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_CONFIG_DETALHE=''
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
  local arquivo nome modo dono conteudo campo

  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_CONFIG_MOTIVO=''
  _dbx_config_limpar_credencial
  # Sem argumento, o perfil selecionado. Com `<arquivo> <nome>`, OUTRO perfil
  # (so `perfis` e `unlink`, um por vez; a lista fechada de RNF-37): as mesmas
  # verificacoes, nomeado: recusa ligacao simbolica e confere `dbx/` e `perfis/`.
  if [[ $# -eq 2 ]]; then
    arquivo=$1
    nome=$2
    # O nome e dado de caminho: validado antes de qualquer acesso a disco.
    dbx_config_perfil_validar "$nome" || return $?
  else
    dbx_config_caminho || return $?
    arquivo=$DBX_CONFIG_RESULTADO
    nome=${DBX_CONFIG_PERFIL:-$DBX_CONFIG_PERFIL_PADRAO}
  fi
  # A cadeia a conferir decorre do CAMINHO real (arquivo em `perfis/`), nunca do
  # rotulo: um rotulo `padrao` sobre arquivo de perfil nao desliga a conferencia.
  local nomeado=nao
  [[ ${arquivo%/*} == */perfis || ${arquivo%/*} == perfis ]] && nomeado=sim
  if [[ $nomeado == 'sim' || $nome != "$DBX_CONFIG_PERFIL_PADRAO" ]]; then
    _dbx_config_verificar_cadeia "$arquivo" simbolicos || return $?
  fi

  [[ -f $arquivo ]] || { _dbx_config_falhar ausente; return $?; }

  # A permissao e verificada tambem aqui, e nao apenas no preflight: entre um e
  # outro o arquivo pode ter mudado, e a leitura e o ponto em que o segredo
  # efetivamente sai do disco.
  modo=$(stat -c '%a' -- "$arquivo" 2>/dev/null || stat -f '%Lp' "$arquivo" 2>/dev/null) ||
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
  if [[ $nomeado == 'sim' || $nome != "$DBX_CONFIG_PERFIL_PADRAO" ]]; then
    _dbx_config_verificar_cadeia "$arquivo" completo || return $?
  else
    modo_diretorio=$(stat -c '%a' -- "${arquivo%/*}" 2>/dev/null || stat -f '%Lp' "${arquivo%/*}" 2>/dev/null) ||
      { _dbx_config_falhar inspecao; return $?; }
    [[ $modo_diretorio =~ ^[0-7]00$ ]] ||
      { _dbx_config_falhar permissao_diretorio; return $?; }
  fi
  dono=$(stat -c '%u' -- "$arquivo" 2>/dev/null || stat -f '%u' "$arquivo" 2>/dev/null)
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
  # `app_secret` VAZIO passa por aqui de proposito, e nao por ser opcional:
  # desde RF-63 (fase 3) o segredo e obrigatorio, e quem recusa a falta dele e
  # `lib/auth`, antes da rede, com a mesma classe deste ramo (`configuracao`) e
  # um motivo que nomeia o segredo — recusar aqui perderia esse motivo.
  # `raiz_remota` vazia e legitima: e a raiz da conta na representacao da API.
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
      # Perfil nomeado: nunca remove atraves de `dbx/` ou `perfis/` simbolicos.
      if dbx_config_perfil_nomeado; then
        _dbx_config_verificar_cadeia_sem_arquivo "$arquivo" || return $?
      fi
      _dbx_config_varrer_orfaos "${arquivo%/*}"
      # Orfaos de `perfis/` tambem saem no `unlink` do `padrao` (RF-122(e)).
      dbx_config_perfil_nomeado ||
        _dbx_config_varrer_perfis "${arquivo%/*}/$DBX_CONFIG_DIRETORIO_PERFIS"
      if { [[ -e $arquivo ]] || { dbx_config_perfil_nomeado && [[ -L $arquivo ]]; }; } && ! rm -f -- "$arquivo" 2>/dev/null; then
        _dbx_config_falhar remocao
        return $?
      fi
      # `perfis/` vazio depois da remocao do ultimo perfil sai (RF-124(i)).
      dbx_config_perfil_nomeado && rmdir -- "${arquivo%/*}" 2>/dev/null
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
