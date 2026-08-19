#!/usr/bin/env bash
# sync — sincronizacao direcional, com a origem como autoridade (DP-27, DP-28).
#
# CONTRATO DOS LADOS (RF-53)
#
#   `--origem` e `--destino` nomeiam o PAPEL; `--enviar` ou `--receber` declara o
#   SENTIDO; o TIPO de cada lado e consequencia, e nunca inferido.
#
#   `DP-28` fechou a inferencia depois de o custo dela ficar visivel. A versao
#   anterior apurava o tipo por existencia no sistema de arquivos e recusava o
#   empate — o que protege o caso em que a ferramenta SABE QUE NAO SABE e deixa
#   aberto o caso em que ela ACHA QUE SABE E ESTA ERRADA: com `/fotos` existindo
#   no disco e `./fotos` ainda nao, a intencao de receber viraria envio, sem nada
#   parecer ambiguo, sobrescrevendo o remoto com a arvore errada.
#
# AS QUATRO BARREIRAS QUE VIRARAM A DEFESA INTEIRA (RSK-35)
#
#   A matriz de tres estados garantia estruturalmente que a primeira execucao
#   nunca apagava nada, porque exclusao exigia linha de base presente. No modelo
#   direcional isso deixou de valer: "ausente na origem, presente no destino" e
#   observavel sem historico algum. Restaram `RF-40` (espelhamento desligado por
#   padrao), `RF-41` (travessia parcial desabilita exclusao; origem vazia recusa),
#   `RF-48` (reconhecimento na primeira execucao) e `RF-47` (registro nominal de
#   toda perda). Nenhuma delas e zelo; sao a unica coisa entre uma raiz apontada
#   por engano e o destino apagado.
#
# LIMITE DECLARADO NA TRANSFERENCIA
#
#   A travessia obedece a `RNF-28` e desce por nome relativo. A transferencia,
#   porem, ABRE O ARQUIVO POR CAMINHO COMPOSTO — manter um descritor aberto por
#   arquivo estouraria o limite do processo em qualquer arvore real. A janela de
#   `RSK-24` volta a existir para o CONTEUDO transferido, e nao para o alcance:
#   os componentes ja foram verificados pela descida, entao o que uma troca
#   consegue e fazer o `sync` enviar outro conteudo, nao sair da raiz.

dbx_cmd_sync_requisitos() { printf 'credencial'; }

_dbx_cmd_sync_carregar_dependencias() {
  # shellcheck source=lib/walk.sh
  . "$DBX_CLI_RAIZ/lib/walk.sh"
  # shellcheck source=lib/state.sh
  . "$DBX_CLI_RAIZ/lib/state.sh"
  # shellcheck source=lib/sync.sh
  . "$DBX_CLI_RAIZ/lib/sync.sh"
}

# _dbx_cmd_sync_conta — identificador da conta corrente, para RF-52.
#
# Sem ele a memoria auxiliar nao pode ser vinculada a conta, e memoria de outra
# conta faz o `sync` OMITIR transferencia necessaria — falha que nao aparece em
# relatorio, porque omissao nao emite operacao. Falha aqui NAO impede o `sync`:
# sem identidade, a execucao segue sem memoria alguma, que e o comportamento
# correto e apenas mais lento.
_dbx_cmd_sync_conta() {
  DBX_CMD_SYNC_CONTA=''
  _dbx_cmd_consultar 'https://api.dropboxapi.com/2/users/get_current_account' 'null' >/dev/null 2>&1 || return 1
  _dbx_cmd_campo account_id && DBX_CMD_SYNC_CONTA=$DBX_CMD_LIDO
  _dbx_cmd_encerrar_consulta
  [[ -n $DBX_CMD_SYNC_CONTA ]]
}

# _dbx_cmd_sync_resumo_local <raiz> <relativo> <tamanho> <mtime>
#
# Consulta a memoria antes de reler o arquivo. Quando reler, registra — e o
# registro so acontece aqui, num lugar so, para que nenhum caminho de calculo
# deixe de alimentar a memoria e nenhum caminho a alimente com valor que nao
# calculou.
_dbx_cmd_sync_resumo_local() {
  local raiz=$1 relativo=$2 tamanho=$3 mtime=$4
  DBX_CMD_SYNC_RESUMO=''
  if dbx_state_consultar "$relativo" "$tamanho" "$mtime"; then
    DBX_CMD_SYNC_RESUMO=$DBX_STATE_HASH
    return 0
  fi
  DBX_CMD_SYNC_RESUMO=$(dbx_hash_conteudo_arquivo "$raiz/$relativo" 2>/dev/null) || return 1
  [[ -n $DBX_CMD_SYNC_RESUMO ]] || return 1
  dbx_state_registrar "$relativo" "$DBX_CMD_SYNC_RESUMO" "$tamanho" "$mtime"
  return 0
}

dbx_cmd_sync_executar() {
  _dbx_cmd_sync_carregar_dependencias

  local origem='' destino='' sentido='' espelhar='nao' confirmado='nao'
  local tem_origem='nao' tem_destino='nao'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --origem)
        shift
        origem=${1-}
        tem_origem='sim'
        ;;
      --destino)
        shift
        destino=${1-}
        tem_destino='sim'
        ;;
      --enviar)
        [[ -z $sentido ]] || {
          dbx_cmd_falhar uso_invalido '--enviar e --receber sao mutuamente exclusivos'
          return $?
        }
        sentido='enviar'
        ;;
      --receber)
        [[ -z $sentido ]] || {
          dbx_cmd_falhar uso_invalido '--enviar e --receber sao mutuamente exclusivos'
          return $?
        }
        sentido='receber'
        ;;
      --espelhar) espelhar='sim' ;;
      --confirmar) confirmado='sim' ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        dbx_cmd_falhar uso_invalido "argumento inesperado: $1 (use --origem e --destino)"
        return $?
        ;;
    esac
    shift
  done

  [[ $tem_origem == 'sim' && -n $origem ]] || {
    dbx_cmd_falhar uso_invalido '--origem e obrigatorio'
    return $?
  }
  [[ $tem_destino == 'sim' && -n $destino ]] || {
    dbx_cmd_falhar uso_invalido '--destino e obrigatorio'
    return $?
  }
  [[ -n $sentido ]] || {
    dbx_cmd_falhar uso_invalido \
      'informe o sentido: --enviar (origem local para destino remoto) ou --receber (origem remota para destino local)'
    return $?
  }

  # RF-45: fluxo nao tem arvore. A recusa nomeia qual sinalizador trazia o valor.
  local lado
  for lado in origem destino; do
    if [[ ${!lado} == '-' ]]; then
      dbx_cmd_falhar uso_invalido \
        "sync opera sobre arvores e nao aceita fluxo: --$lado recebeu '-'"
      return $?
    fi
  done

  # RF-53(c): o tipo e CONSEQUENCIA do sentido. Nao ha inspecao de caminho aqui,
  # e a auditoria estatica reprova se voltar a haver.
  local raiz_local raiz_remota
  if [[ $sentido == 'enviar' ]]; then
    raiz_local=$origem
    raiz_remota=$destino
  else
    raiz_local=$destino
    raiz_remota=$origem
  fi

  local remoto
  _dbx_cmd_caminho_remoto "$raiz_remota" || {
    dbx_cmd_falhar caminho_recusado "caminho remoto recusado: $raiz_remota"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  # O local precisa existir porque nao se percorre o que nao existe — e nao para
  # decidir tipo, que ja veio do sentido.
  [[ -d $raiz_local ]] || {
    dbx_cmd_falhar nao_encontrado "raiz local inexistente ou nao e diretorio: $raiz_local"
    return $?
  }

  local conta=''
  _dbx_cmd_sync_conta && conta=$DBX_CMD_SYNC_CONTA
  dbx_state_carregar "${conta:-sem-identidade}" "$origem" "$destino"
  local visto=$DBX_STATE_VISTO

  # RF-48: reconhecimento obrigatorio na primeira execucao COM espelhamento.
  if [[ $espelhar == 'sim' && $visto != 'sim' && $confirmado != 'sim' &&
    ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      'primeira execucao com --espelhar sobre este par de raizes: rode antes com --dry-run para ver o plano, ou confirme com --confirmar'
    return $?
  fi

  local area registros_locais registros_remotos
  area=$(mktemp -d "${TMPDIR:-/tmp}/dbx-sync.XXXXXXXX") || {
    dbx_cmd_falhar configuracao 'nao foi possivel criar area temporaria'
    return $?
  }
  registros_locais="$area/local"
  registros_remotos="$area/remoto"

  dbx_walk_local "$raiz_local" "$registros_locais" || {
    rm -rf -- "$area"
    dbx_cmd_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
    return $?
  }
  local parcial=$DBX_WALK_PARCIAL motivo_parcial=$DBX_WALK_MOTIVO

  if ! dbx_sync_enumerar_remoto "$remoto" "$registros_remotos"; then
    local estado_remoto=$?
    rm -rf -- "$area"
    dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" "${DBX_SYNC_MOTIVO:-enumeracao remota falhou}"
    return "$estado_remoto"
  fi

  local -a caminhos_locais=() tamanhos=() mtimes=()
  dbx_walk_ler "$registros_locais" caminhos_locais tamanhos mtimes
  local -a ordem_remota=()
  # shellcheck disable=SC2034  # preenchido e lido por referencia de nome nas
  # funcoes de lib/sync; a analise estatica nao segue nameref entre arquivos.
  local -A mapa_remoto=()
  dbx_sync_ler_resumos "$registros_remotos" ordem_remota mapa_remoto

  # RF-41(b): origem vazia com memoria povoada e recusa integral, sem escrita
  # alguma. Uma raiz que ficou vazia por engano — ponto de montagem que nao
  # subiu, disco trocado — e indistinguivel de uma raiz esvaziada de proposito, e
  # com espelhamento a segunda leitura apaga o destino inteiro.
  local vazia='nao'
  if [[ $sentido == 'enviar' ]]; then
    [[ ${#caminhos_locais[@]} -eq 0 ]] && vazia='sim'
  else
    [[ ${#ordem_remota[@]} -eq 0 ]] && vazia='sim'
  fi
  if [[ $vazia == 'sim' && ${#DBX_STATE_ENTRADA[@]} -gt 0 ]]; then
    rm -rf -- "$area"
    dbx_cmd_falhar nao_concluida \
      'a origem esta vazia e a memoria registra caminhos de execucao anterior: execucao recusada integralmente'
    return $?
  fi

  # Resumo de cada arquivo local, com reaproveitamento pela memoria.
  local -a ordem_local=()
  # shellcheck disable=SC2034  # ver nota acima: passado por nome a lib/sync
  local -A mapa_local=()
  local indice falhas_de_resumo=0
  for indice in "${!caminhos_locais[@]}"; do
    if _dbx_cmd_sync_resumo_local "$raiz_local" "${caminhos_locais[$indice]}" \
      "${tamanhos[$indice]}" "${mtimes[$indice]}"; then
      ordem_local+=("${caminhos_locais[$indice]}")
      # shellcheck disable=SC2034  # lido por referencia de nome em lib/sync
      mapa_local["${caminhos_locais[$indice]}"]=$DBX_CMD_SYNC_RESUMO
    else
      # Arquivo ilegivel e travessia parcial: some da origem sem ter sido
      # apagado, e com espelhamento isso viraria exclusao do par no destino.
      falhas_de_resumo=$((falhas_de_resumo + 1))
      parcial='sim'
      # Mesmo motivo do canal de `lib/walk`: uma linha so. Quebra de linha aqui
      # derrubaria o registro do plano inteiro, e justamente na execucao em que
      # ele mais importa.
      motivo_parcial="${motivo_parcial}${motivo_parcial:+; }nao foi possivel calcular o resumo de: ${caminhos_locais[$indice]}"
    fi
  done

  if [[ $sentido == 'enviar' ]]; then
    dbx_sync_planejar ordem_local mapa_local ordem_remota mapa_remoto
  else
    dbx_sync_planejar ordem_remota mapa_remoto ordem_local mapa_local
  fi

  # RF-41(a): travessia parcial desabilita exclusao NA EXECUCAO INTEIRA, e nao
  # apenas no ramo que falhou. Um ramo invisivel produz exatamente a mesma
  # observacao que um ramo apagado, e nao ha como distinguir depois.
  local exclusao_desabilitada='nao'
  if [[ $espelhar == 'sim' && $parcial == 'sim' ]]; then
    exclusao_desabilitada='sim'
    DBX_SYNC_APAGAR=()
  fi

  local total_transferir=${#DBX_SYNC_TRANSFERIR[@]}
  local total_apagar=0
  [[ $espelhar == 'sim' ]] && total_apagar=${#DBX_SYNC_APAGAR[@]}

  # RF-41(d) e RF-47: o plano inteiro, com toda exclusao nomeada, sai ANTES da
  # primeira escrita. Em simulacao a saida e a mesma — e o que torna `--dry-run`
  # uma previa fiel, e nao um relatorio diferente.
  local caminho
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao sync
  dbx_output_campo sentido "$sentido"
  dbx_output_campo origem "$origem"
  dbx_output_campo destino "$destino"
  dbx_output_campo espelhar "$espelhar"
  dbx_output_campo travessia_parcial "$parcial"
  [[ $exclusao_desabilitada == 'sim' ]] &&
    dbx_output_campo exclusao_desabilitada 'travessia parcial'
  dbx_output_campo a_transferir "$total_transferir"
  dbx_output_campo a_apagar "$total_apagar"
  dbx_output_campo identicos "${#DBX_SYNC_IDENTICOS[@]}"
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    dbx_output_campo transferir "$caminho"
  done
  if [[ $espelhar == 'sim' ]]; then
    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      dbx_output_campo apagar "$caminho"
    done
  else
    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      dbx_output_campo apenas_no_destino "$caminho"
    done
  fi
  [[ -n $motivo_parcial ]] && dbx_output_campo motivo_parcial "$motivo_parcial"
  [[ -n ${DBX_STATE_MOTIVO:-} ]] && dbx_output_campo memoria "$DBX_STATE_MOTIVO"
  dbx_output_render

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo simulado sim
    dbx_output_render
    rm -rf -- "$area"
    return 0
  fi

  local enviados=0 recebidos=0 apagados=0 falhas=0
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    if [[ $sentido == 'enviar' ]]; then
      _dbx_cmd_sync_enviar "$raiz_local" "$remoto" "$caminho" && enviados=$((enviados + 1)) ||
        falhas=$((falhas + 1))
    else
      _dbx_cmd_sync_receber "$raiz_local" "$remoto" "$caminho" && recebidos=$((recebidos + 1)) ||
        falhas=$((falhas + 1))
    fi
  done

  if [[ $espelhar == 'sim' ]]; then
    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      if [[ $sentido == 'enviar' ]]; then
        _dbx_cmd_sync_apagar_remoto "$remoto" "$caminho" && apagados=$((apagados + 1)) ||
          falhas=$((falhas + 1))
      else
        _dbx_cmd_sync_apagar_local "$raiz_local" "$caminho" && apagados=$((apagados + 1)) ||
          falhas=$((falhas + 1))
      fi
    done
  fi

  # A memoria e gravada mesmo com falha parcial: os resumos calculados continuam
  # validos, e joga-los fora so faria a proxima execucao reler tudo.
  dbx_state_gravar "${conta:-sem-identidade}" "$origem" "$destino" || :

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao sync
  dbx_output_campo enviados "$enviados"
  dbx_output_campo recebidos "$recebidos"
  dbx_output_campo apagados "$apagados"
  dbx_output_campo omitidos "${#DBX_SYNC_IDENTICOS[@]}"
  dbx_output_campo falhas "$falhas"
  dbx_output_render
  rm -rf -- "$area"

  # RF-41(a) exige codigo diferente de zero quando a travessia foi parcial, ainda
  # que nada tenha falhado: o operador precisa saber que o resultado nao e o
  # espelho completo que pediu.
  if [[ $falhas -gt 0 ]]; then
    dbx_cmd_falhar nao_concluida "$falhas operacao(oes) nao concluida(s)"
    return $?
  fi
  if [[ $parcial == 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      'a travessia local foi parcial: a sincronizacao nao cobre a arvore inteira'
    return $?
  fi
  return 0
}

_dbx_cmd_sync_enviar() {
  local raiz=$1 remoto=$2 relativo=$3
  dbx_json_escapar_cadeia "$remoto/$relativo"
  local argumento="{\"path\":\"$DBX_JSON_ESCAPADO\",\"mode\":\"overwrite\",\"autorename\":false,\"mute\":true}"
  dbx_auth_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
    "$argumento" "$raiz/$relativo" nao >/dev/null 2>&1
}

_dbx_cmd_sync_receber() {
  local raiz=$1 remoto=$2 relativo=$3
  local alvo="$raiz/$relativo" pasta=${relativo%/*}
  [[ $pasta == "$relativo" ]] || mkdir -p -- "$raiz/$pasta" 2>/dev/null || return 1
  dbx_json_escapar_cadeia "$remoto/$relativo"
  local argumento="{\"path\":\"$DBX_JSON_ESCAPADO\"}"
  dbx_auth_conteudo_receber GET 'https://content.dropboxapi.com/2/files/download' \
    "$argumento" "$alvo" >/dev/null 2>&1
}

_dbx_cmd_sync_apagar_remoto() {
  local remoto=$1 relativo=$2
  dbx_json_escapar_cadeia "$remoto/$relativo"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/delete_v2' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\"}" nao >/dev/null 2>&1
}

_dbx_cmd_sync_apagar_local() {
  local raiz=$1 relativo=$2
  rm -f -- "$raiz/$relativo" 2>/dev/null
}
