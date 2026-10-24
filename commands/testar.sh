#!/usr/bin/env bash
# testar — teste explicito de disponibilidade: internet, servico Dropbox e
# credencial (RF-148, F-50). Alias em ingles: `check`.
#
# NIVEL `nenhum`, como o `diagnostico`: precisa rodar sem credencial e reportar
# a falta. So le: a sonda, uma requisicao sem token a cada host Dropbox
# (api e content, DIV-308 B) e UMA renovacao de token; nenhum `check/user`,
# nada criado nem regravado (RF-148(d)). Quando a credencial esta ausente,
# incompleta ou recusada e o portao de RF-152 esta aberto, oferece o `config`
# (RF-148(h), DIV-309 B) e, configurado, refaz as checagens uma vez.
#
# Cada checagem e `ok`, `aviso` ou `falha`; a que depende de outra que falhou sai
# `falha` "nao executada" com o remedio da causa. Codigo de saida: 0 sem falha;
# senao a classe da PRIMEIRA falha na ordem internet, servico, credencial
# (RF-148(f)), sem codigo novo (RF-150).

dbx_cmd_testar_requisitos() { printf 'nenhum'; }

DBX_CMD_TESTAR_IDS=()
DBX_CMD_TESTAR_RESULTADOS=()
DBX_CMD_TESTAR_TEXTOS=()
DBX_CMD_TESTAR_PRIMEIRA='' # classe da primeira falha
DBX_CMD_TESTAR_OFERTA=''   # ausente | invalida: o que a oferta de config diria

# _dbx_cmd_testar_linha <id> <resultado> <mensagem> [remedio] [classe]
_dbx_cmd_testar_linha() {
  local texto="$2: $3"
  [[ -n ${4:-} ]] && texto+="; remedio: $4"
  DBX_CMD_TESTAR_IDS+=("$1")
  DBX_CMD_TESTAR_RESULTADOS+=("$2")
  DBX_CMD_TESTAR_TEXTOS+=("$texto")
  [[ $2 == 'falha' && -z $DBX_CMD_TESTAR_PRIMEIRA ]] && DBX_CMD_TESTAR_PRIMEIRA=${5:-configuracao}
  return 0
}

# _dbx_cmd_testar_servico <id> <rotulo> <alcance> — uma linha `servico` a partir do
# alcance ja medido (DIV-320: a do host de conteudo tem id proprio,
# `servico_conteudo`).
_dbx_cmd_testar_servico() {
  local id=$1 rotulo=$2
  case $3 in
    ok) _dbx_cmd_testar_linha "$id" ok "$rotulo responde" ;;
    limite_taxa)
      dbx_disp_mensagem limite_taxa
      _dbx_cmd_testar_linha "$id" falha "$rotulo: $DBX_DISP_MENSAGEM" "$DBX_DISP_REMEDIO" "$DBX_DISP_CLASSE"
      ;;
    indisponivel)
      dbx_disp_mensagem dropbox_indisponivel
      _dbx_cmd_testar_linha "$id" falha "$rotulo: $DBX_DISP_MENSAGEM" "$DBX_DISP_REMEDIO" "$DBX_DISP_CLASSE"
      ;;
    *)
      # Sem resposta: a internet decide a causa (sonda ja feita, memoizada).
      dbx_disp_nomear_falha rede
      _dbx_cmd_testar_linha "$id" falha "$rotulo: $DBX_DISP_MENSAGEM" "$DBX_DISP_REMEDIO" "$DBX_DISP_CLASSE"
      ;;
  esac
}

# _dbx_cmd_testar_faltantes <arquivo> — nomes (nunca valores) dos campos
# obrigatorios ausentes ou vazios de um arquivo que `dbx_config_carregar`
# recusou como incompleto. Testa a PRESENCA de cadeia nao vazia por nome; o
# conteudo lido nao e guardado alem desta funcao.
_dbx_cmd_testar_faltantes() {
  local conteudo='' rotulo campo
  IFS= read -r -d '' conteudo <"$1" 2>/dev/null
  DBX_CMD_LIDO=''
  for campo in app_key:'app key' app_secret:'app secret' refresh_token:'refresh token'; do
    rotulo=${campo#*:}
    [[ $conteudo =~ \"${campo%%:*}\"[[:space:]]*:[[:space:]]*\"[^\"] ]] || DBX_CMD_LIDO+="${DBX_CMD_LIDO:+, }$rotulo"
  done
  conteudo=''
}

# _dbx_cmd_testar_credencial <rede_ok> <causa_remota> — a parte local roda
# sempre; a remota (renovacao) so com internet e servico em ok.
_dbx_cmd_testar_credencial() {
  local remota_ok=$1 causa=$2 arquivo='' faltam='' remedio_recusa='' alvo_ligacao='' remedio_inicial='dbx config' remedio_substituir='dbx config --substituir'
  DBX_CMD_TESTAR_OFERTA=''
  if dbx_config_perfil_nomeado; then
    remedio_inicial="dbx config --perfil $DBX_CONFIG_PERFIL"
    remedio_substituir="dbx config --perfil $DBX_CONFIG_PERFIL --substituir"
  fi
  dbx_config_caminho && arquivo=$DBX_CONFIG_RESULTADO
  if ! dbx_config_carregar; then
    case $DBX_CONFIG_MOTIVO in
      ausente)
        DBX_CMD_TESTAR_OFERTA='ausente'
        _dbx_cmd_testar_linha credencial falha "credencial ausente: $arquivo" "$remedio_inicial" configuracao
        ;;
      permissao | permissao_diretorio | ligacao_simbolica)
        # RF-150(d): recusa de preflight, sem oferta. O remedio acompanha o motivo.
        case $DBX_CONFIG_MOTIVO in
          permissao) remedio_recusa="chmod 600 $arquivo" ;;
          permissao_diretorio) remedio_recusa="chmod 700 ${DBX_CONFIG_DETALHE:-${arquivo%/*}}" ;;
          *)
            # A ligacao pode estar no diretorio base, em `perfis/` ou no proprio arquivo.
            alvo_ligacao=${DBX_CONFIG_DETALHE:-}
            if [[ -z $alvo_ligacao ]]; then
              for alvo_ligacao in "${arquivo%/*/*}" "${arquivo%/*}" "$arquivo"; do
                [[ -L $alvo_ligacao ]] && break
              done
            fi
            remedio_recusa="remova a ligacao simbolica em $alvo_ligacao e rode $remedio_inicial"
            ;;
        esac
        _dbx_cmd_testar_linha credencial falha "credencial recusada (${DBX_CONFIG_MOTIVO}): $arquivo" \
          "$remedio_recusa" configuracao
        ;;
      incompleto)
        DBX_CMD_TESTAR_OFERTA='invalida'
        _dbx_cmd_testar_faltantes "$arquivo"
        _dbx_cmd_testar_linha credencial falha "campo obrigatorio ausente ou vazio ($arquivo): ${DBX_CMD_LIDO:-app key, app secret ou refresh token}" \
          "$remedio_substituir" configuracao
        ;;
      *)
        DBX_CMD_TESTAR_OFERTA='invalida'
        _dbx_cmd_testar_linha credencial falha "credencial inutilizavel (${DBX_CONFIG_MOTIVO:-ilegivel}): $arquivo" \
          "$remedio_substituir" configuracao
        ;;
    esac
    return 0
  fi
  [[ -n $DBX_CONFIG_APP_KEY ]] || faltam+="${faltam:+, }app key"
  [[ -n $DBX_CONFIG_APP_SECRET ]] || faltam+="${faltam:+, }app secret"
  [[ -n $DBX_CONFIG_REFRESH_TOKEN ]] || faltam+="${faltam:+, }refresh token"
  if [[ -n $faltam ]]; then
    DBX_CMD_TESTAR_OFERTA='invalida'
    _dbx_cmd_testar_linha credencial falha "campo obrigatorio ausente ou vazio ($arquivo): $faltam" \
      "$remedio_substituir" configuracao
    return 0
  fi
  if [[ $remota_ok != 'sim' ]]; then
    _dbx_cmd_testar_linha credencial falha "nao executada: $causa; campos locais presentes em $arquivo" \
      'resolva a causa acima e rode de novo' rede
    return 0
  fi
  if dbx_auth_preparar; then
    _dbx_cmd_testar_linha credencial ok "$arquivo: campos presentes e renovacao do token aceita"
    return 0
  fi
  if [[ ${DBX_AUTH_CLASSE:-} == 'autenticacao' ]]; then
    DBX_CMD_TESTAR_OFERTA='invalida'
    _dbx_cmd_testar_linha credencial falha "renovacao do token recusada (${DBX_AUTH_MOTIVO:-sem detalhe})" \
      "$remedio_substituir" autenticacao
  else
    _dbx_cmd_testar_linha credencial falha "renovacao do token falhou (${DBX_AUTH_MOTIVO:-sem detalhe})" \
      'rode de novo mais tarde; se persistir, rode com --debug' "${DBX_AUTH_CLASSE:-erro_remoto}"
  fi
  return 0
}

DBX_CMD_TESTAR_ALCANCE_API=''
DBX_CMD_TESTAR_ALCANCE_CONTEUDO=''

# _dbx_cmd_testar_medir_alcances — um alcance por host, medido uma vez por rodada.
_dbx_cmd_testar_medir_alcances() {
  [[ -n $DBX_CMD_TESTAR_ALCANCE_API ]] && return 0
  dbx_disp_alcance "$DBX_DISP_URL_API"
  DBX_CMD_TESTAR_ALCANCE_API=$DBX_DISP_ALCANCE
  dbx_disp_alcance "$DBX_DISP_URL_CONTEUDO"
  DBX_CMD_TESTAR_ALCANCE_CONTEUDO=$DBX_DISP_ALCANCE
}

_dbx_cmd_testar_servicos() {
  _dbx_cmd_testar_medir_alcances
  _dbx_cmd_testar_servico servico 'api.dropboxapi.com' "$DBX_CMD_TESTAR_ALCANCE_API"
  _dbx_cmd_testar_servico servico_conteudo 'content.dropboxapi.com' "$DBX_CMD_TESTAR_ALCANCE_CONTEUDO"
}

# _dbx_cmd_testar_resultado_de <id> — resultado da linha pelo id, nao pela posicao.
_dbx_cmd_testar_resultado_de() {
  local i
  for i in "${!DBX_CMD_TESTAR_IDS[@]}"; do
    [[ ${DBX_CMD_TESTAR_IDS[i]} == "$1" ]] && { printf '%s' "${DBX_CMD_TESTAR_RESULTADOS[i]}"; return 0; }
  done
  return 1
}

# _dbx_cmd_testar_rodada — as quatro checagens, na ordem de RF-148(b).
_dbx_cmd_testar_rodada() {
  local remota_ok='nao' causa=''
  DBX_CMD_TESTAR_ALCANCE_API='' DBX_CMD_TESTAR_ALCANCE_CONTEUDO=''
  DBX_CMD_TESTAR_IDS=() DBX_CMD_TESTAR_RESULTADOS=() DBX_CMD_TESTAR_TEXTOS=() DBX_CMD_TESTAR_PRIMEIRA=''
  if ! command -v curl >/dev/null 2>&1; then
    _dbx_cmd_testar_linha internet falha 'nao executada: utilitario curl ausente' 'instale o utilitario curl' configuracao
    causa='utilitario curl ausente'
  else
    dbx_disp_internet
    case $DBX_DISP_INTERNET in
      responde)
        if [[ $DBX_DISP_INTERNET_STATUS == '204' ]]; then
          _dbx_cmd_testar_linha internet ok 'a sonda respondeu (status 204)'
        else
          _dbx_cmd_testar_linha internet aviso "a sonda respondeu com status $DBX_DISP_INTERNET_STATUS, nao 204 (portal cativo ou proxy?)"
        fi
        ;;
      desligada) _dbx_cmd_testar_linha internet aviso 'sonda desligada (DBX_TESTE_INTERNET_URL vazia)' ;;
      *)
        # DIV-326: a sonda sem resposta so vira falha se o Dropbox tambem nao
        # responder; servico e servico_conteudo rodam sempre.
        _dbx_cmd_testar_medir_alcances
        if [[ $DBX_CMD_TESTAR_ALCANCE_API != 'sem_resposta' || $DBX_CMD_TESTAR_ALCANCE_CONTEUDO != 'sem_resposta' ]]; then
          _dbx_cmd_testar_linha internet aviso 'a sonda nao respondeu, mas o Dropbox responde'
        else
          dbx_disp_mensagem sem_internet
          _dbx_cmd_testar_linha internet falha "$DBX_DISP_MENSAGEM" "$DBX_DISP_REMEDIO" "$DBX_DISP_CLASSE"
        fi
        ;;
    esac
  fi
  if [[ -n $causa ]]; then
    _dbx_cmd_testar_linha servico falha "nao executada: $causa" 'resolva a causa acima e rode de novo' rede
    _dbx_cmd_testar_linha servico_conteudo falha "nao executada: $causa" 'resolva a causa acima e rode de novo' rede
  else
    _dbx_cmd_testar_servicos
    if [[ $(_dbx_cmd_testar_resultado_de servico) == 'ok' ]]; then
      remota_ok='sim'
    elif [[ $DBX_CMD_TESTAR_ALCANCE_API == 'sem_resposta' && $DBX_CMD_TESTAR_ALCANCE_CONTEUDO == 'sem_resposta' ]]; then
      dbx_disp_nomear_falha rede
      causa=$DBX_DISP_MENSAGEM
    else
      causa='servico Dropbox com falha'
    fi
  fi
  _dbx_cmd_testar_credencial "$remota_ok" "$causa"
}

dbx_cmd_testar_executar() {
  dbx_carregar_camada_de_credencial
  # shellcheck source=lib/disponibilidade.sh
  . "$DBX_CLI_RAIZ/lib/disponibilidade.sh"

  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      *)
        dbx_cmd_falhar uso_invalido "argumento nao reconhecido: $1"
        return $?
        ;;
    esac
    shift
  done

  # DIV-310: no `testar` explicito, URL de sonda invalida e recusa (2); o valor
  # nunca e citado.
  dbx_disp_sonda_configurar
  if [[ $DBX_DISP_SONDA_ESTADO == 'invalida' ]]; then
    dbx_cmd_falhar uso_invalido 'DBX_TESTE_INTERNET_URL invalida: precisa comecar por https://; defina https://... ou deixe vazia para desligar a sonda'
    return $?
  fi

  _dbx_cmd_testar_rodada
  # RF-148(h): oferta sob o portao de RF-152; configurado, refaz uma vez.
  if [[ -n $DBX_CMD_TESTAR_OFERTA ]] && dbx_disp_oferecer_config "$DBX_CMD_TESTAR_OFERTA"; then
    _dbx_cmd_testar_rodada
  fi

  local indice texto ok=0 avisos=0 falhas=0
  dbx_cmd_iniciar_saida
  for indice in "${!DBX_CMD_TESTAR_IDS[@]}"; do
    case ${DBX_CMD_TESTAR_RESULTADOS[indice]} in
      ok) ok=$((ok + 1)) ;;
      aviso) avisos=$((avisos + 1)) ;;
      *) falhas=$((falhas + 1)) ;;
    esac
    dbx_output_mascarar_segredos "${DBX_CMD_TESTAR_TEXTOS[indice]}"
    texto=$DBX_OUTPUT_MASCARADO
    if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
      dbx_cmd_caminho_exibivel "$texto"
      texto=$DBX_CMD_EXIBIDO
    fi
    dbx_output_campo "${DBX_CMD_TESTAR_IDS[indice]}" "$texto"
  done
  dbx_output_campo ok "$ok"
  dbx_output_campo avisos "$avisos"
  dbx_output_campo falhas "$falhas"
  dbx_output_render

  if [[ $falhas -gt 0 ]]; then
    dbx_cmd_falhar "$DBX_CMD_TESTAR_PRIMEIRA" "o teste encontrou $falhas falha(s); siga o remedio de cada linha"
    return $?
  fi
  return 0
}
