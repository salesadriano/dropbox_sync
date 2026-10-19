#!/usr/bin/env bash
# verificar — compara a arvore local e a remota por `content_hash`, so leitura
# (RF-65, F-11). Alias em ingles: `verify`.
#
# MESMO MODELO DE ARGUMENTOS E MESMO PLANEJADOR DO `sync`
#
#   Os papeis (`--origem`, `--destino`) e o sentido (`--enviar`, `--receber`)
#   sao os do `sync` (RF-53), e a comparacao e a tabela de `dbx_sync_planejar`
#   lida como relatorio (`dbx_sync_comparar`, em `lib/sync`). Assim `verificar`
#   e `sync --dry-run` enxergam a mesma arvore: enumeracao remota, travessia
#   local por descida, chave sem caixa, colisao de caixa e temporarios de
#   recebimento sao os mesmos componentes, e nao copias.
#
# SO LEITURA, POR CONSTRUCAO
#
#   Nao ha escrita remota nem local: as unicas chamadas sao a renovacao do
#   token e a listagem (`list_folder` e `list_folder/continue`); a memoria de
#   `lib/state` nao e carregada nem gravada, entao o diretorio de estado fica
#   identico e nenhuma memoria pode decidir o resultado (RF-65(b)); a raiz local
#   ausente no `--receber` e arvore vazia e nao e criada. A unica area criada e
#   a temporaria `dbx-sync.*` de RNF-31, removida em toda saida.

dbx_cmd_verificar_requisitos() { printf 'credencial'; }

# Area temporaria da execucao (RNF-31). Global porque o tratador de sinal roda
# fora do escopo da funcao.
DBX_CMD_VERIFICAR_AREA=''

_dbx_cmd_verificar_interrompido() {
  [[ -n $DBX_CMD_VERIFICAR_AREA ]] && rm -rf -- "$DBX_CMD_VERIFICAR_AREA"
  DBX_CMD_VERIFICAR_AREA=''
  DBX_HTTP_TRATADOR_EXTERNO=''
  dbx_http_interrompido
}

_dbx_cmd_verificar_encerrar_area() {
  [[ -n $DBX_CMD_VERIFICAR_AREA ]] && rm -rf -- "$DBX_CMD_VERIFICAR_AREA"
  DBX_CMD_VERIFICAR_AREA=''
  DBX_HTTP_TRATADOR_EXTERNO=''
  dbx_http_sinais_devolver
}

# _dbx_cmd_verificar_falhar <classe> <texto> — encerra a area e recusa.
_dbx_cmd_verificar_falhar() {
  _dbx_cmd_verificar_encerrar_area
  dbx_cmd_falhar "$1" "$2"
}

dbx_cmd_verificar_executar() {
  # shellcheck source=lib/walk.sh
  . "$DBX_CLI_RAIZ/lib/walk.sh"
  # shellcheck source=lib/sync.sh
  . "$DBX_CLI_RAIZ/lib/sync.sh"

  local origem='' destino='' sentido='' tem_origem='nao' tem_destino='nao'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --origem | --source)
        shift
        origem=${1-}
        tem_origem='sim'
        ;;
      --destino | --dest)
        shift
        destino=${1-}
        tem_destino='sim'
        ;;
      --enviar | --push | --receber | --pull)
        [[ -z $sentido ]] || {
          dbx_cmd_falhar uso_invalido '--enviar e --receber sao mutuamente exclusivos'
          return $?
        }
        sentido='enviar'
        [[ $1 == '--receber' || $1 == '--pull' ]] && sentido='receber'
        ;;
      --progresso | --progress | -p)
        # shellcheck disable=SC2034 # variavel global consumida por lib/progress.sh
        DBX_CLI_PROGRESSO='sim'
        ;;
      --sem-progresso | --no-progress)
        # shellcheck disable=SC2034 # variavel global consumida por lib/progress.sh
        DBX_CLI_PROGRESSO='nao'
        ;;
      # RF-65(a): opcoes do `sync` que aqui nao tem o que espelhar, confirmar
      # ou forcar. Aceita-las em silencio faria o operador crer que valeram.
      --espelhar | --mirror | --confirmar | --yes | --permitir-origem-vazia | \
        --allow-empty-source | --forcar | --force)
        dbx_cmd_falhar uso_invalido "opcao do sync sem efeito no verificar, que so le: $1"
        return $?
        ;;
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
    dbx_cmd_falhar uso_invalido '--origem (--source) e obrigatorio'
    return $?
  }
  [[ $tem_destino == 'sim' && -n $destino ]] || {
    dbx_cmd_falhar uso_invalido '--destino (--dest) e obrigatorio'
    return $?
  }
  [[ -n $sentido ]] || {
    dbx_cmd_falhar uso_invalido \
      'informe o sentido: --enviar ou --push (origem local, destino remoto), --receber ou --pull (origem remota, destino local)'
    return $?
  }
  local lado
  for lado in origem destino; do
    if [[ ${!lado} == '-' ]]; then
      dbx_cmd_falhar uso_invalido "verificar opera sobre arvores e nao aceita fluxo: --$lado recebeu '-'"
      return $?
    fi
  done

  if ! dbx_sync_localidade_disponivel; then
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso "$DBX_SYNC_MOTIVO"
    dbx_output_render_diagnostico >&2
  fi

  local raiz_local=$origem raiz_remota=$destino
  if [[ $sentido == 'receber' ]]; then
    raiz_local=$destino
    raiz_remota=$origem
  fi

  # RNF-20: o caminho remoto e recusado antes de qualquer chamada e de qualquer
  # acesso a disco.
  local remoto
  _dbx_cmd_caminho_remoto "$raiz_remota" || return $?
  remoto=$DBX_CMD_LIDO

  local local_ausente='nao'
  if [[ ! -d $raiz_local ]]; then
    if [[ $sentido == 'enviar' ]]; then
      dbx_cmd_falhar nao_encontrado "raiz local inexistente ou nao e diretorio: $raiz_local"
      return $?
    fi
    [[ -e $raiz_local ]] && {
      dbx_cmd_falhar nao_encontrado "raiz local nao e diretorio: $raiz_local"
      return $?
    }
    local_ausente='sim'
  fi

  # shellcheck disable=SC2034  # canal de lib/http, lido por dbx_http_sinais_devolver
  DBX_HTTP_TRATADOR_EXTERNO=_dbx_cmd_verificar_interrompido
  dbx_http_sinais_devolver
  DBX_CMD_VERIFICAR_AREA=$(mktemp -d "${TMPDIR:-/tmp}/dbx-sync.XXXXXXXX") || {
    _dbx_cmd_verificar_falhar configuracao 'nao foi possivel criar area temporaria'
    return $?
  }

  # Travessia local e colisao de caixa ANTES de qualquer acesso remoto
  # (RF-54(c)): o relatorio de uma arvore assim nao tem leitura unica.
  local parcial='nao' motivo_parcial=''
  # shellcheck disable=SC2034  # preenchidos e filtrados por nome (lib/walk, lib/sync)
  local -a caminhos_locais=() tamanhos=() identidades=()
  if [[ $local_ausente == 'sim' ]]; then
    : >"$DBX_CMD_VERIFICAR_AREA/local"
  else
    dbx_progress_mensagem "[verificar] analisando arquivos locais em: $raiz_local"
    dbx_walk_local "$raiz_local" "$DBX_CMD_VERIFICAR_AREA/local" || {
      _dbx_cmd_verificar_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
      return $?
    }
    parcial=$DBX_WALK_PARCIAL motivo_parcial=$DBX_WALK_MOTIVO
    dbx_walk_ler "$DBX_CMD_VERIFICAR_AREA/local" caminhos_locais tamanhos identidades
    dbx_sync_sem_temporarios caminhos_locais tamanhos identidades
    if ! dbx_sync_colisao_de_caixa caminhos_locais; then
      _dbx_cmd_verificar_falhar conflito "$DBX_SYNC_MOTIVO"
      return $?
    fi
  fi

  dbx_auth_preparar || {
    _dbx_cmd_verificar_falhar "$DBX_AUTH_CLASSE" "${DBX_AUTH_MOTIVO:-nao foi possivel obter o token de acesso}"
    return $?
  }
  dbx_progress_mensagem "[verificar] consultando arquivos remotos em: $remoto"
  local estado_remoto=0
  dbx_sync_enumerar_remoto "$remoto" "$DBX_CMD_VERIFICAR_AREA/remoto" || estado_remoto=$?
  if [[ $estado_remoto -ne 0 ]]; then
    _dbx_cmd_verificar_encerrar_area
    dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" "${DBX_SYNC_MOTIVO:-enumeracao remota falhou}"
    return "$estado_remoto"
  fi
  # shellcheck disable=SC2034  # vetor e mapa lidos por referencia de nome em lib/sync
  local -a ordem_remota=()
  # shellcheck disable=SC2034  # idem
  local -A mapa_remoto=()
  dbx_sync_ler_resumos "$DBX_CMD_VERIFICAR_AREA/remoto" ordem_remota mapa_remoto

  # Resumo local sempre calculado: a memoria nao e consultada (RF-65(b)).
  local -a ordem_local=()
  # shellcheck disable=SC2034  # lido por referencia de nome em lib/sync
  local -A mapa_local=()
  local indice
  for indice in "${!caminhos_locais[@]}"; do
    if dbx_hash_publicar_arquivo "$raiz_local/${caminhos_locais[$indice]}" 2>/dev/null &&
      [[ -n $DBX_HASH_RESULTADO ]]; then
      ordem_local+=("${caminhos_locais[$indice]}")
      # shellcheck disable=SC2034  # lido por referencia de nome em lib/sync
      mapa_local["${caminhos_locais[$indice]}"]=$DBX_HASH_RESULTADO
    else
      parcial='sim'
      motivo_parcial="${motivo_parcial}${motivo_parcial:+; }nao foi possivel calcular o resumo de: ${caminhos_locais[$indice]}"
    fi
  done
  _dbx_cmd_verificar_encerrar_area

  if [[ $sentido == 'enviar' ]]; then
    dbx_sync_comparar ordem_local mapa_local ordem_remota mapa_remoto
  else
    dbx_sync_comparar ordem_remota mapa_remoto ordem_local mapa_local
  fi

  local -A contagem=([igual]=0 [diferente]=0 [so_origem]=0 [so_destino]=0)
  local estado valor
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao verificar
  dbx_output_campo sentido "$sentido"
  dbx_output_campo origem "$origem"
  dbx_output_campo destino "$destino"
  dbx_output_campo travessia_parcial "$parcial"
  for indice in "${!DBX_SYNC_COMPARADOS_CAMINHOS[@]}"; do
    estado=${DBX_SYNC_COMPARADOS_ESTADOS[indice]}
    valor=${DBX_SYNC_COMPARADOS_CAMINHOS[indice]}
    contagem[$estado]=$((contagem[$estado] + 1))
    if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
      dbx_cmd_caminho_exibivel "$valor"
      valor=$DBX_CMD_EXIBIDO
    fi
    dbx_output_campo "$estado" "$valor"
    [[ $estado == 'diferente' ]] && dbx_output_campo motivo "${DBX_SYNC_COMPARADOS_MOTIVOS[indice]}"
  done
  [[ -n $motivo_parcial ]] && dbx_output_campo motivo_parcial "$motivo_parcial"
  dbx_output_campo iguais "${contagem[igual]}"
  dbx_output_campo diferentes "${contagem[diferente]}"
  dbx_output_campo so_origem "${contagem[so_origem]}"
  dbx_output_campo so_destino "${contagem[so_destino]}"
  dbx_output_campo total "${#DBX_SYNC_COMPARADOS_CAMINHOS[@]}"
  dbx_output_render

  # RF-65(e): relatorio parcial nao afirma igualdade nem divergencia completa.
  if [[ $parcial == 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      'a travessia local foi parcial: o relatorio nao cobre a arvore inteira'
    return $?
  fi
  local divergentes=$((contagem[diferente] + contagem[so_origem] + contagem[so_destino]))
  if [[ $divergentes -gt 0 ]]; then
    # DIV-34: mensagem propria; nada foi transferido.
    dbx_cmd_falhar integridade \
      "divergencia encontrada: ${contagem[diferente]} diferente(s), ${contagem[so_origem]} so na origem, ${contagem[so_destino]} so no destino"
    return $?
  fi
  return 0
}
