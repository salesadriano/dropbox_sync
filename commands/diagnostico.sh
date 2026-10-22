#!/usr/bin/env bash
# diagnostico — checa o ambiente e diz o remedio (RF-66, F-22). Alias em
# ingles: `doctor`.
#
# CONTORNA O PREFLIGHT, E SO ELE
#
#   O requisito declarado e `nenhum`: o preflight bloqueante para no primeiro
#   item e com uma mensagem unica, e este comando existe justamente para listar
#   TUDO o que falta, com o remedio de cada coisa. A lista de utilitarios e a do
#   proprio preflight (`dbx_preflight_ausentes`), perguntada sem parada e so
#   com recursos do shell. Checagem que depende de outra que falhou nao some:
#   sai como `falha` "nao executada", com o remedio da causa.
#
# NUNCA IMPRIME SEGREDO E NAO MUDA NADA
#
#   A credencial e verificada por NOME de campo, nunca por valor; toda linha
#   passa pela mascaracao por valor de `lib/output` antes de sair. As unicas
#   chamadas sao a renovacao do token, `check/user` e `get_space_usage`. Nada e
#   criado, corrigido ou regravado: o remedio e sugerido, nunca aplicado.

dbx_cmd_diagnostico_requisitos() { printf 'nenhum'; }

# Escopos exigidos pelos comandos habilitados (DIV-35, memoria
# 2026-10-19-1050-consulta-e-diagnostico).
readonly DBX_CMD_DIAGNOSTICO_ESCOPOS='account_info.read files.metadata.read files.content.read files.content.write'
# RF-77: so `dbx lixeira --excluir` o usa; nunca reprova o diagnostico.
readonly DBX_CMD_DIAGNOSTICO_OPCIONAL='files.permanent_delete'
# RF-91: so `dbx compartilhar` os usa; informados na mesma linha, nunca reprovam.
readonly DBX_CMD_DIAGNOSTICO_COMPARTILHAMENTO='sharing.write sharing.read'

DBX_CMD_DIAG_IDS=()
DBX_CMD_DIAG_RESULTADOS=()
DBX_CMD_DIAG_TEXTOS=()

# _dbx_cmd_diag <id> <resultado> <mensagem> [remedio] — acumula uma linha.
_dbx_cmd_diag() {
  local texto="$2: $3"
  [[ -n ${4:-} ]] && texto+="; remedio: $4"
  DBX_CMD_DIAG_IDS+=("$1")
  DBX_CMD_DIAG_RESULTADOS+=("$2")
  DBX_CMD_DIAG_TEXTOS+=("$texto")
}

_dbx_cmd_diag_tem() { command -v "$1" >/dev/null 2>&1; }

# _dbx_cmd_diag_remedio_da_classe <classe> — remedio da falha de rede ou token.
_dbx_cmd_diag_remedio_da_classe() {
  case ${1:-} in
    autenticacao | configuracao | uso_invalido) DBX_CMD_LIDO='dbx config --substituir' ;;
    rede) DBX_CMD_LIDO='verifique a conexao de rede, o proxy e o DNS' ;;
    limite_taxa) DBX_CMD_LIDO='aguarde alguns minutos e rode de novo' ;;
    *) DBX_CMD_LIDO='rode de novo mais tarde; se persistir, rode com --debug' ;;
  esac
}

# _dbx_cmd_diag_cursores — checagem `cursor` (fase 7b, RF-117(e), DIV-220): uma
# linha por registro de cursor de listagem, com raiz remota, raiz local,
# entradas do retrato, idade da ultima varredura completa e estado `valido`,
# `vencido` (a proxima execucao faz a varredura completa) ou `ilegivel`. So o
# CABECALHO e lido (C4), de registro de qualquer tamanho; nada e criado nem
# removido; nunca `falha`; nenhum byte do cursor (C10). Sem registros, nenhuma
# linha.
_dbx_cmd_diag_cursores() {
  local indice arquivo texto
  dbx_state_cursor_listar
  for indice in "${!DBX_STATE_CURSORES_ARQUIVO[@]}"; do
    arquivo=${DBX_STATE_CURSORES_ARQUIVO[indice]}
    if [[ ${DBX_STATE_CURSORES_ESTADO[indice]} == 'ilegivel' ]]; then
      _dbx_cmd_diag cursor aviso "ilegivel: $arquivo" \
        "remova $arquivo com rm; enquanto ele estiver ali, o sync --receber deste par faz a varredura completa"
      continue
    fi
    # Remoto vazio e a raiz `/` da credencial (QA-B7B-01).
    texto="${DBX_STATE_CURSORES_REMOTO[indice]:-/} ->${DBX_STATE_CURSORES_LOCAL[indice]}"
    texto+=", ${DBX_STATE_CURSORES_ENTRADAS[indice]} entrada(s) no retrato"
    texto+=", ultima varredura completa ha ${DBX_STATE_CURSORES_IDADE[indice]} dia(s): $arquivo"
    _dbx_cmd_diag cursor ok "${DBX_STATE_CURSORES_ESTADO[indice]}: $texto"
  done
  return 0
}

# _dbx_cmd_diag_retomadas — checagem `retomada` (fase 7a, RF-107(d)): uma
# linha por registro de retomada, com sentido, caminhos, bytes confirmados ou
# recebidos, idade e estado. So le, pelo leitor limitado de `lib/state`: nada e
# criado nem removido, e o resultado e `ok` (pendente) ou `aviso` (orfa,
# ilegivel), nunca `falha`. Nenhum `session_id` (C6). Sem registros, nenhuma
# linha (DIV-197: as contagens do diagnostico sem estado ficam as de hoje).
_dbx_cmd_diag_retomadas() {
  local indice arquivo sentido texto bytes
  dbx_state_retomada_listar
  for indice in "${!DBX_STATE_RETOMADAS_ARQUIVO[@]}"; do
    arquivo=${DBX_STATE_RETOMADAS_ARQUIVO[indice]}
    sentido=${DBX_STATE_RETOMADAS_SENTIDO[indice]}
    if [[ ${DBX_STATE_RETOMADAS_ESTADO[indice]} == 'ilegivel' ]]; then
      _dbx_cmd_diag retomada aviso "ilegivel: $arquivo" \
        "remova $arquivo com rm; a proxima transferencia recomeca do zero"
      continue
    fi
    bytes="${DBX_STATE_RETOMADAS_BYTES[indice]} bytes confirmados"
    [[ $sentido == 'download' ]] && bytes="${DBX_STATE_RETOMADAS_BYTES[indice]} bytes recebidos"
    if [[ $sentido == 'upload' ]]; then
      texto="upload ${DBX_STATE_RETOMADAS_LOCAL[indice]} -> ${DBX_STATE_RETOMADAS_REMOTO[indice]}"
    else
      texto="download ${DBX_STATE_RETOMADAS_REMOTO[indice]} -> ${DBX_STATE_RETOMADAS_LOCAL[indice]}"
    fi
    texto+=", $bytes, ha ${DBX_STATE_RETOMADAS_IDADE[indice]} dia(s): $arquivo"
    if [[ ${DBX_STATE_RETOMADAS_ESTADO[indice]} == 'orfa' ]]; then
      _dbx_cmd_diag retomada aviso "orfa: $texto" \
        'sai na proxima gravacao de retomada; ou repita a transferencia, ou use --sem-retomada'
    else
      _dbx_cmd_diag retomada ok "pendente: $texto"
    fi
  done
  return 0
}

# _dbx_cmd_diag_travas <diretorio_de_estado> — checagem `trava` (RF-71) e o
# aviso de diretorio de estado em NFS (RF-69(q)).
_dbx_cmd_diag_travas() {
  local estado=$1 indice arquivo quem tipo
  dbx_state_travas_listar
  if [[ ${#DBX_STATE_TRAVAS_ARQUIVO[@]} -eq 0 ]]; then
    _dbx_cmd_diag trava ok 'sem travas'
  fi
  for indice in "${!DBX_STATE_TRAVAS_ARQUIVO[@]}"; do
    arquivo=${DBX_STATE_TRAVAS_ARQUIVO[indice]}
    dbx_state_trava_descrever "$indice"
    quem=$DBX_STATE_RESULTADO
    case ${DBX_STATE_TRAVAS_ESTADO[indice]} in
      viva)
        _dbx_cmd_diag trava ok "viva: $quem: $arquivo"
        ;;
      orfa)
        if [[ $arquivo == *.r ]]; then
          _dbx_cmd_diag trava aviso "orfa: retomada interrompida ($quem), nunca retomada automaticamente: $arquivo" \
            "confirme que nenhum sync ou verificar deste par esta em curso e remova $arquivo com rm"
        else
          _dbx_cmd_diag trava aviso "orfa: $quem, terminou sem liberar: $arquivo" \
            "sera retomada na proxima execucao; ou remova $arquivo"
        fi
        ;;
      outro-host)
        _dbx_cmd_diag trava aviso "outro-host: $quem: $arquivo" \
          "confirme que a execucao em ${DBX_STATE_TRAVAS_HOST[indice]%%:*} (pid ${DBX_STATE_TRAVAS_PID[indice]}) terminou e remova $arquivo com rm"
        ;;
      *)
        _dbx_cmd_diag trava aviso "ilegivel: $arquivo" \
          "confirme que nenhum sync ou verificar deste par esta em curso e remova $arquivo com rm"
        ;;
    esac
  done
  # Exclusao entre hosts em NFS e melhor esforco (RSK-49): avisa, nunca bloqueia.
  # Sem `stat -f`, nao ha o que dizer.
  [[ -n $estado && -d $estado ]] && _dbx_cmd_diag_tem stat || return 0
  tipo=$(stat -f -c %T -- "$estado" 2>/dev/null) || return 0
  if [[ ${tipo,,} == nfs* ]]; then
    _dbx_cmd_diag trava aviso "o diretorio de estado esta em NFS ($tipo): a exclusao da trava entre hosts e melhor esforco: $estado" \
      'aponte XDG_STATE_HOME para um disco local'
  fi
  return 0
}

dbx_cmd_diagnostico_executar() {
  dbx_carregar_camada_de_credencial
  # shellcheck source=lib/preflight.sh
  . "$DBX_CLI_RAIZ/lib/preflight.sh"
  # shellcheck source=lib/sync.sh
  . "$DBX_CLI_RAIZ/lib/sync.sh"

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
  DBX_CMD_DIAG_IDS=() DBX_CMD_DIAG_RESULTADOS=() DBX_CMD_DIAG_TEXTOS=()

  # 1. dependencias — cada ausente nomeado, uma linha por item.
  local dependencias_ok='sim' utilitario remedio_dependencias=''
  if ! dbx_preflight_versao_de_bash_suficiente "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"; then
    dependencias_ok='nao'
    _dbx_cmd_diag dependencias falha "bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} abaixo do piso 4.4" \
      'atualize o bash para 4.4 ou superior'
  fi
  if ! dbx_preflight_ausentes; then
    dependencias_ok='nao'
    for utilitario in "${DBX_PREFLIGHT_AUSENTES[@]}"; do
      case $utilitario in
        # Limite aceito do D-1: pelo vinculo de instalacao o ponto de entrada
        # le o alvo com readlink, recua para find e, sem os dois, recusa com 3.
        readlink | find)
          _dbx_cmd_diag dependencias falha \
            "utilitario ausente: $utilitario (o dbx chamado pelo vinculo de instalacao resolve o alvo com readlink, ou find na falta dele; sem os dois, recusa com codigo 3)" \
            "instale o utilitario $utilitario"
          ;;
        *) _dbx_cmd_diag dependencias falha "utilitario ausente: $utilitario" "instale o utilitario $utilitario" ;;
      esac
    done
    remedio_dependencias="instale o utilitario ${DBX_PREFLIGHT_AUSENTES[0]}"
    _dbx_cmd_diag_tem curl || remedio_dependencias='instale o utilitario curl'
  fi
  [[ $dependencias_ok == 'sim' ]] &&
    _dbx_cmd_diag dependencias ok "bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}, curl e utilitarios presentes (vinculo de instalacao resolvido por readlink, ou find na falta dele)"
  [[ -n $remedio_dependencias ]] || remedio_dependencias='atualize o bash para 4.4 ou superior'

  # 2. credencial — por nome de campo, nunca por valor.
  # Fase 8 (RF-127): com selecao explicita, a linha `perfil`; com perfil nomeado,
  # os remedios dizem `--perfil <nome>`. Sem selecao, a saida e a de hoje.
  local credencial_ok='nao' remedio_credencial='dbx config' remedio_config_inicial='dbx config' remedio_substituir='dbx config --substituir' arquivo=''
  if dbx_config_perfil_nomeado; then
    remedio_credencial="dbx config --perfil $DBX_CONFIG_PERFIL"; remedio_config_inicial=$remedio_credencial
    remedio_substituir="dbx config --perfil $DBX_CONFIG_PERFIL --substituir"
  fi
  dbx_config_caminho && arquivo=$DBX_CONFIG_RESULTADO
  if [[ -n $DBX_CONFIG_PERFIL_ORIGEM ]]; then
    _dbx_cmd_diag perfil ok "$DBX_CONFIG_PERFIL (origem: $DBX_CONFIG_PERFIL_ORIGEM): $arquivo"
  fi
  # O-4, RF-66(e): sem `stat` nenhum utilitario e chamado; o shell confere
  # existencia e dono (`-O`), e o modo, que so o `stat` le, fica como aviso.
  if ! _dbx_cmd_diag_tem stat; then
    remedio_credencial='instale o utilitario stat'
    if [[ -z $arquivo || ! -e $arquivo ]]; then
      remedio_credencial="${remedio_config_inicial}"
      _dbx_cmd_diag credencial falha "credencial ausente: $arquivo" "$remedio_credencial"
    elif [[ ! -O $arquivo ]]; then
      remedio_credencial=$remedio_substituir
      _dbx_cmd_diag credencial falha "a credencial pertence a outro usuario: $arquivo" "$remedio_credencial"
    else
      _dbx_cmd_diag credencial aviso "permissao nao conferida (utilitario ausente: stat): $arquivo" \
        "$remedio_credencial"
    fi
  elif dbx_config_carregar; then
    local faltam=''
    [[ -n $DBX_CONFIG_APP_KEY ]] || faltam+="${faltam:+, }app key"
    [[ -n $DBX_CONFIG_APP_SECRET ]] || faltam+="${faltam:+, }app secret"
    [[ -n $DBX_CONFIG_REFRESH_TOKEN ]] || faltam+="${faltam:+, }refresh token"
    if [[ -n $faltam ]]; then
      remedio_credencial=$remedio_substituir
      _dbx_cmd_diag credencial falha "campo obrigatorio ausente ou vazio: $faltam" "$remedio_credencial"
    else
      credencial_ok='sim'
      _dbx_cmd_diag credencial ok "$arquivo com permissao restrita e campos app key, app secret e refresh token"
    fi
  else
    case $DBX_CONFIG_MOTIVO in
      ausente)
        _dbx_cmd_diag credencial falha "credencial ausente: $arquivo" "$remedio_credencial"
        ;;
      permissao)
        remedio_credencial="chmod 600 $arquivo"
        _dbx_cmd_diag credencial falha "a credencial tem permissao para grupo ou outros: $arquivo" "$remedio_credencial"
        ;;
      permissao_diretorio)
        local dir_inseguro=${DBX_CONFIG_DETALHE:-${arquivo%/*}}
        remedio_credencial="chmod 700 $dir_inseguro"
        _dbx_cmd_diag credencial falha "o diretorio de configuracao tem permissao para grupo ou outros: $dir_inseguro" "$remedio_credencial"
        ;;
      ligacao_simbolica)
        remedio_credencial="remova a ligacao simbolica e rode $remedio_config_inicial"
        _dbx_cmd_diag credencial falha "o perfil, perfis ou dbx e ligacao simbolica (recusada, nunca seguida): $arquivo" "$remedio_credencial"
        ;;
      *)
        remedio_credencial=$remedio_substituir
        _dbx_cmd_diag credencial falha "credencial inutilizavel (${DBX_CONFIG_MOTIVO:-ilegivel}): $arquivo" "$remedio_credencial"
        ;;
    esac
  fi

  # 3. conectividade — renovacao e uma chamada barata que nao exige escopo.
  local renovou='nao' causa='' remedio_causa=''
  if [[ $dependencias_ok != 'sim' ]]; then
    causa='dependencias ausentes' remedio_causa=$remedio_dependencias
  elif [[ $credencial_ok != 'sim' ]]; then
    causa='credencial indisponivel' remedio_causa=$remedio_credencial
  fi
  if [[ -n $causa ]]; then
    _dbx_cmd_diag conectividade falha "nao executada: $causa" "$remedio_causa"
  elif ! dbx_auth_preparar; then
    _dbx_cmd_diag_remedio_da_classe "$DBX_AUTH_CLASSE"
    causa='renovacao do token falhou' remedio_causa=$DBX_CMD_LIDO
    _dbx_cmd_diag conectividade falha "renovacao do token falhou: ${DBX_AUTH_MOTIVO:-sem detalhe}" "$remedio_causa"
  else
    renovou='sim'
    if dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/check/user' '{"query":"dbx"}' sim \
      >/dev/null 2>&1; then
      _dbx_cmd_diag conectividade ok 'check/user respondeu com o token renovado'
    else
      _dbx_cmd_diag_remedio_da_classe "${DBX_HTTP_CLASSE:-}"
      _dbx_cmd_diag conectividade falha \
        "check/user recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}" "$DBX_CMD_LIDO"
    fi
  fi

  # 4. escopos — os declarados pela renovacao contra os exigidos.
  if [[ $renovou != 'sim' ]]; then
    _dbx_cmd_diag escopos falha "nao executada: $causa" "$remedio_causa"
  elif [[ ${DBX_AUTH_ESCOPOS_INFORMADOS:-nao} != 'sim' ]]; then
    _dbx_cmd_diag escopos aviso 'escopos nao informados pela resposta de renovacao' \
      "confira no console do aplicativo os escopos $DBX_CMD_DIAGNOSTICO_ESCOPOS"
  else
    local escopo faltantes=''
    for escopo in $DBX_CMD_DIAGNOSTICO_ESCOPOS; do
      [[ " $DBX_AUTH_ESCOPOS " == *" $escopo "* ]] || faltantes+="${faltantes:+ }$escopo"
    done
    # RF-77 (DIV-67): o escopo OPCIONAL vai na mesma linha, informativo; o
    # conjunto exigido e o resultado da linha nao mudam (DIV-70).
    local opcional="opcional ausente: $DBX_CMD_DIAGNOSTICO_OPCIONAL (dbx lixeira --excluir indisponivel)"
    local remedio_opcional="para a exclusao permanente, habilite $DBX_CMD_DIAGNOSTICO_OPCIONAL no App Console do aplicativo e reautorize com dbx unlink seguido de dbx config"
    if [[ " $DBX_AUTH_ESCOPOS " == *" $DBX_CMD_DIAGNOSTICO_OPCIONAL "* ]]; then
      opcional="opcional $DBX_CMD_DIAGNOSTICO_OPCIONAL concedido: exclusao permanente habilitada"
      remedio_opcional=''
    fi
    # RF-91 (fase 5): `sharing.write` e `sharing.read`, do mesmo jeito.
    local ausentes_compartilhamento=''
    for escopo in $DBX_CMD_DIAGNOSTICO_COMPARTILHAMENTO; do
      [[ " $DBX_AUTH_ESCOPOS " == *" $escopo "* ]] || ausentes_compartilhamento+="${ausentes_compartilhamento:+ }$escopo"
    done
    if [[ -z $ausentes_compartilhamento ]]; then
      opcional+='; opcionais sharing.write e sharing.read concedidos (dbx compartilhar habilitado)'
    else
      [[ " $ausentes_compartilhamento " == *' sharing.write '* ]] &&
        opcional+='; opcional sharing.write ausente: dbx compartilhar criar, modificar e --revogar indisponivel'
      [[ " $ausentes_compartilhamento " == *' sharing.read '* ]] &&
        opcional+='; opcional sharing.read ausente: dbx compartilhar --listar, reuso de link existente e --revogar indisponivel'
      remedio_opcional+="${remedio_opcional:+; }para o compartilhamento, habilite $ausentes_compartilhamento no App Console do aplicativo e reautorize com dbx unlink seguido de dbx config"
    fi
    if [[ -n $faltantes ]]; then
      _dbx_cmd_diag escopos falha "escopo(s) faltante(s): $faltantes; $opcional" \
        "habilite $faltantes no console do aplicativo e rode dbx config --substituir"
    else
      _dbx_cmd_diag escopos ok "escopos exigidos concedidos; $opcional" "$remedio_opcional"
    fi
  fi

  # 5. espaco — mesma folga da checagem previa de RF-67.
  if [[ $renovou != 'sim' ]]; then
    _dbx_cmd_diag espaco falha "nao executada: $causa" "$remedio_causa"
  elif ! dbx_cmd_espaco_consultar; then
    _dbx_cmd_diag_remedio_da_classe "$DBX_CMD_FALHA_CLASSE"
    _dbx_cmd_diag espaco falha "${DBX_CMD_FALHA_MOTIVO:-consulta de espaco falhou}" "$DBX_CMD_LIDO"
  elif [[ -z $DBX_CMD_ESPACO_LIVRE ]]; then
    _dbx_cmd_diag espaco aviso 'alocacao de espaco nao informada ou nao interpretavel'
  else
    local usado=$DBX_CMD_ESPACO_USADO alocado=$DBX_CMD_ESPACO_ALOCADO percentual=100
    [[ $alocado -gt 0 ]] && percentual=$((usado * 100 / alocado))
    local resumo="usado $usado de $alocado bytes ($percentual%), livre $DBX_CMD_ESPACO_LIVRE bytes"
    if [[ $DBX_CMD_ESPACO_LIVRE -eq 0 ]]; then
      _dbx_cmd_diag espaco falha "sem espaco livre: $resumo" 'libere espaco na conta ou amplie a cota'
    elif ((usado * 100 >= alocado * 90)); then
      _dbx_cmd_diag espaco aviso "uso acima de 90%: $resumo" 'libere espaco na conta ou amplie a cota'
    else
      _dbx_cmd_diag espaco ok "$resumo"
    fi
  fi

  # 6. localidade — a mesma sondagem do `sync` (RF-54(e)(f)).
  if dbx_sync_localidade_disponivel; then
    _dbx_cmd_diag localidade ok "localidade $DBX_SYNC_LOCALIDADE disponivel"
  else
    _dbx_cmd_diag localidade aviso "$DBX_SYNC_MOTIVO" "instale a localidade $DBX_SYNC_LOCALIDADE"
  fi

  # 7. estado — diretorio de `lib/state`, nunca criado aqui.
  local estado=''
  dbx_config_caminho_de_estado && estado=$DBX_CONFIG_RESULTADO
  if [[ -z $estado ]]; then
    _dbx_cmd_diag estado falha 'nao foi possivel determinar o diretorio de estado' \
      'defina HOME ou XDG_STATE_HOME com caminho absoluto'
  elif [[ ! -e $estado ]]; then
    _dbx_cmd_diag estado ok "ainda nao criado: $estado"
  elif [[ ! -d $estado ]]; then
    _dbx_cmd_diag estado falha "o caminho de estado nao e diretorio: $estado" "remova ou renomeie $estado"
  elif [[ ! -O $estado ]]; then
    _dbx_cmd_diag estado falha "o diretorio de estado pertence a outro usuario: $estado" \
      "remova $estado; ele e refeito na proxima execucao"
  elif ! _dbx_cmd_diag_tem stat; then
    _dbx_cmd_diag estado aviso "permissao nao conferida (utilitario ausente: stat): $estado" \
      'instale o utilitario stat'
  else
    local modo dono
    modo=$(stat -c '%a' -- "$estado" 2>/dev/null) || modo=''
    dono=$(stat -c '%u' -- "$estado" 2>/dev/null) || dono=''
    if [[ $dono != "$EUID" ]]; then
      _dbx_cmd_diag estado falha "o diretorio de estado pertence a outro usuario: $estado" \
        "remova $estado; ele e refeito na proxima execucao"
    elif [[ $modo != '700' ]]; then
      _dbx_cmd_diag estado falha "permissao $modo no diretorio de estado, esperada 700: $estado" "chmod 700 $estado"
    else
      _dbx_cmd_diag estado ok "$estado com permissao 700"
    fi
  fi

  # 8. trava — uma linha por `trava-*`, so lendo (RF-71): nada e criado,
  # removido ou retomado, e trava nunca leva a `falha`.
  _dbx_cmd_diag_travas "$estado"

  # 9. retomada (fase 7a, RF-107(d)) — uma linha por `retomada-*`, so lendo.
  _dbx_cmd_diag_retomadas

  # 10. cursor (fase 7b, RF-117(e)) — uma linha por `cursor-*`, so o cabecalho.
  _dbx_cmd_diag_cursores

  local indice texto ok=0 avisos=0 falhas=0
  dbx_cmd_iniciar_saida
  for indice in "${!DBX_CMD_DIAG_IDS[@]}"; do
    case ${DBX_CMD_DIAG_RESULTADOS[indice]} in
      ok) ok=$((ok + 1)) ;;
      aviso) avisos=$((avisos + 1)) ;;
      *) falhas=$((falhas + 1)) ;;
    esac
    # Defesa em profundidade: todo segredo em memoria e mascarado pelo valor.
    dbx_output_mascarar_segredos "${DBX_CMD_DIAG_TEXTOS[indice]}"
    texto=$DBX_OUTPUT_MASCARADO
    if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
      dbx_cmd_caminho_exibivel "$texto"
      texto=$DBX_CMD_EXIBIDO
    fi
    dbx_output_campo "${DBX_CMD_DIAG_IDS[indice]}" "$texto"
  done
  dbx_output_campo ok "$ok"
  dbx_output_campo avisos "$avisos"
  dbx_output_campo falhas "$falhas"
  dbx_output_render

  # RF-66(d): aviso nao reprova; uma falha basta para `configuracao`.
  if [[ $falhas -gt 0 ]]; then
    dbx_cmd_falhar configuracao "o diagnostico encontrou $falhas falha(s); siga o remedio de cada linha"
    return $?
  fi
  return 0
}
