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

# RF-59: falhas por item, na ordem em que ocorreram, e a classe da ultima.
DBX_CMD_SYNC_FALHAS_CAMINHOS=()
DBX_CMD_SYNC_FALHAS_CLASSES=()
DBX_CMD_SYNC_FALHA_CLASSE=''
DBX_CMD_SYNC_EXIBIDO=''
DBX_CMD_SYNC_RESUMO_FALHA=''

# _dbx_cmd_sync_exibir <caminho> — forma do caminho que cabe numa linha
# (RNF-10, RF-28): com byte de controle ou quebra de linha ele sai citado, e a
# ambiguidade fica visivel em vez de abrir uma segunda linha — que poderia ate
# comecar com `falha `. Sem byte de controle, sai como esta.
_dbx_cmd_sync_exibir() {
  dbx_cmd_caminho_exibivel "$1"
  DBX_CMD_SYNC_EXIBIDO=$DBX_CMD_EXIBIDO
}

# _dbx_cmd_sync_resumo_da_falha <requisicoes_antes_do_item>
#
# RF-59(c): o resumo e texto CURTO derivado do prefixo do `error_summary` e
# nunca do corpo bruto, nem de canal que possa trazer token. So conta o que o
# servico respondeu A ESTE ITEM: se nenhuma requisicao saiu durante ele, os
# canais de `lib/http` descrevem o item anterior e a falha e local.
_dbx_cmd_sync_resumo_da_falha() {
  local antes=$1 marca
  DBX_CMD_SYNC_RESUMO_FALHA='falha local'
  [[ ${DBX_HTTP_REQUISICOES:-0} -gt $antes ]] || return 0
  if [[ ${DBX_HTTP_CODIGO:-0} == 0 ]]; then
    DBX_CMD_SYNC_RESUMO_FALHA='sem resposta do servico'
    return 0
  fi
  # So o prefixo no alfabeto de tag da Dropbox — minusculas, `_` e `/` —, sem
  # o qualificador final. QA-P2-02 (a): ponto, digito, maiuscula e hifen ficam
  # FORA, porque com eles o prefixo montava um token (`x_sl.<token>` passava
  # inteiro e a redacao, que espera delimitador antes de `sl.`, nao o via).
  marca=${DBX_HTTP_RESUMO_DO_SERVICO:-}
  marca=${marca%%[!a-z_/]*}
  marca=${marca:0:80}
  while [[ $marca == */ ]]; do marca=${marca%/}; done
  if [[ -n $marca ]]; then
    dbx_errors_redigir "$marca" >/dev/null
    DBX_CMD_SYNC_RESUMO_FALHA=$DBX_ERRORS_REDIGIDO
  elif [[ $DBX_HTTP_CODIGO -ge 400 ]]; then
    DBX_CMD_SYNC_RESUMO_FALHA="HTTP $DBX_HTTP_CODIGO"
  fi
  return 0
}

# _dbx_cmd_sync_falhou <caminho> <requisicoes_antes_do_item> — registra a falha
# do item (classe em DBX_CMD_SYNC_FALHA_CLASSE) e emite a linha dele no stderr.
#
# RF-59(a): uma linha por item, `falha <caminho>: <classe> <resumo>`. A saida
# das operacoes continua descartada: ela e o que poderia trazer corpo bruto, e a
# linha montada aqui so tem o que foi saneado.
_dbx_cmd_sync_falhou() {
  local caminho=$1 antes=$2 classe=${DBX_CMD_SYNC_FALHA_CLASSE:-erro_remoto}
  DBX_CMD_SYNC_FALHAS_CAMINHOS+=("$caminho")
  DBX_CMD_SYNC_FALHAS_CLASSES+=("$classe")
  _dbx_cmd_sync_resumo_da_falha "$antes"
  _dbx_cmd_sync_exibir "$caminho"
  # QA-P2-02 (b): defesa em profundidade, a mesma do diagnostico — todo segredo
  # em memoria e mascarado pelo valor na linha inteira, antes de sair.
  local linha
  printf -v linha 'falha %s: %s %s' "$DBX_CMD_SYNC_EXIBIDO" "$classe" "$DBX_CMD_SYNC_RESUMO_FALHA"
  dbx_output_mascarar_segredos "$linha"
  printf '%s\n' "$DBX_OUTPUT_MASCARADO" >&2
}

_dbx_cmd_sync_carregar_dependencias() {
  # shellcheck source=lib/walk.sh
  . "$DBX_CLI_RAIZ/lib/walk.sh"
  # shellcheck source=lib/state.sh
  . "$DBX_CLI_RAIZ/lib/state.sh"
  # shellcheck source=lib/sync.sh
  . "$DBX_CLI_RAIZ/lib/sync.sh"
  # shellcheck source=lib/transfer.sh
  . "$DBX_CLI_RAIZ/lib/transfer.sh"
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

# _dbx_cmd_sync_resumo_local <raiz> <relativo> <identidade>
#
# Consulta a memoria antes de reler o arquivo. A identidade e a da travessia
# (lib/walk), lida ANTES do calculo; a segunda leitura e feita aqui, DEPOIS, e
# `lib/state` so registra se as duas coincidem (RF-38(e)). O registro so
# acontece aqui, num lugar so, para que nenhum caminho de calculo deixe de
# alimentar a memoria e nenhum a alimente com valor que nao calculou. A memoria
# em `lib/state` e o UNICO cache (RF-38(a)): nao ha segundo nivel.
_dbx_cmd_sync_resumo_local() {
  local raiz=$1 relativo=$2 identidade=$3 depois=''
  DBX_CMD_SYNC_RESUMO=''
  DBX_CMD_SYNC_ORIGEM_RESUMO=''
  if dbx_state_consultar "$relativo" "$identidade"; then
    DBX_CMD_SYNC_RESUMO=$DBX_STATE_HASH
    DBX_CMD_SYNC_ORIGEM_RESUMO='em cache (memoria)'
    return 0
  fi
  dbx_hash_publicar_arquivo "$raiz/$relativo" 2>/dev/null || {
    DBX_CMD_SYNC_ORIGEM_RESUMO='falha na leitura'
    return 1
  }
  DBX_CMD_SYNC_RESUMO=$DBX_HASH_RESULTADO
  [[ -n $DBX_CMD_SYNC_RESUMO ]] || {
    DBX_CMD_SYNC_ORIGEM_RESUMO='hash vazio'
    return 1
  }
  dbx_hash_identidade "$raiz/$relativo" && depois=$DBX_HASH_IDENTIDADE
  dbx_state_registrar "$relativo" "$DBX_CMD_SYNC_RESUMO" "$identidade" "$depois" || :
  DBX_CMD_SYNC_ORIGEM_RESUMO='hash calculado'
  return 0
}

dbx_cmd_sync_executar() {
  _dbx_cmd_sync_carregar_dependencias

  local origem='' destino='' sentido='' espelhar='nao' confirmado='nao' permitir_origem_vazia='nao'
  local tem_origem='nao' tem_destino='nao' forcar='nao' espera=0 opcao_espera='' valor_espera=''
  local tem_limite='nao' opcao_limite='' valor_limite='' opcao
  # RF-118 (fase 7b): cursor de listagem so no `--receber`.
  local sem_cursor='nao' varredura_forcada='nao'
  local -a filtros_caminho=() filtros_meta=()
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      # RF-79: repetiveis, cada ocorrencia ACRESCENTA um padrao (excecao a
      # RF-64(e)); validados depois do laco, antes da trava (RF-79(j)).
      --excluir | --exclude | --incluir | --include)
        opcao=$1
        shift
        filtros_caminho+=("$opcao" "${1-}")
        ;;
      # RF-81: data e tamanho, so na origem; o ultimo valor de cada um vence.
      --modificado-desde | --modified-since | --modificado-ate | --modified-until)
        opcao=$1
        shift
        filtros_meta+=("$opcao" "${1-}")
        ;;
      --tamanho-min | --min-size | --tamanho-max | --max-size)
        opcao=$1
        shift
        filtros_meta+=("$opcao" "${1-}")
        ;;
      # RF-82: limite de banda das requisicoes de conteudo; o ultimo vence.
      --limite-banda | --bwlimit)
        opcao_limite=$1
        shift
        valor_limite=${1-}
        tem_limite='sim'
        ;;
      # RF-64: o alias em ingles e a MESMA opcao, com o mesmo efeito, as mesmas
      # recusas e a mesma regra de repeticao (RF-64(e)).
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
      --enviar | --push)
        [[ -z $sentido ]] || {
          dbx_cmd_falhar uso_invalido '--enviar e --receber sao mutuamente exclusivos'
          return $?
        }
        sentido='enviar'
        ;;
      --receber | --pull)
        [[ -z $sentido ]] || {
          dbx_cmd_falhar uso_invalido '--enviar e --receber sao mutuamente exclusivos'
          return $?
        }
        sentido='receber'
        ;;
      --espelhar | --mirror) espelhar='sim' ;;
      --confirmar | --yes) confirmado='sim' ;;
      --permitir-origem-vazia | --allow-empty-source) permitir_origem_vazia='sim' ;;
      # RF-67(e), DIV-33: so pula a checagem de espaco; a decisao por
      # `content_hash` (RF-39) nao muda.
      --forcar | --force) forcar='sim' ;;
      # RF-118(a)(b), DIV-207 B: o cursor so acelera; estas so mudam o custo.
      --sem-cursor | --no-cursor) sem_cursor='sim' ;;
      --varredura-completa | --full-scan) varredura_forcada='sim' ;;
      # RF-70: espera pela trava do par; validada depois do laco (ultimo vence).
      --esperar | --wait)
        opcao_espera=$1
        shift
        valor_espera=${1-}
        ;;
      --progresso | --progress | -p)
        # shellcheck disable=SC2034 # variavel global consumida por lib/progress.sh
        DBX_CLI_PROGRESSO='sim'
        ;;
      --sem-progresso | --no-progress)
        # shellcheck disable=SC2034 # variavel global consumida por lib/progress.sh
        DBX_CLI_PROGRESSO='nao'
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
      'informe o sentido: --enviar ou --push (origem local para destino remoto), --receber ou --pull (origem remota para destino local)'
    return $?
  }
  # RF-118(b)(c): juntas, ou fora do `--receber`, sao uso invalido, antes de
  # qualquer leitura de estado.
  if [[ $sem_cursor == 'sim' && $varredura_forcada == 'sim' ]]; then
    dbx_cmd_falhar uso_invalido \
      '--sem-cursor (--no-cursor) e --varredura-completa (--full-scan) sao mutuamente exclusivos'
    return $?
  fi
  if [[ ($sem_cursor == 'sim' || $varredura_forcada == 'sim') && $sentido != 'receber' ]]; then
    dbx_cmd_falhar uso_invalido \
      '--sem-cursor (--no-cursor) e --varredura-completa (--full-scan) so valem com --receber'
    return $?
  fi
  if [[ -n $opcao_espera ]]; then
    dbx_cli_validar_espera "$opcao_espera" "$valor_espera" || {
      dbx_cmd_falhar uso_invalido "$DBX_CLI_MOTIVO"
      return $?
    }
    espera=$((10#$valor_espera))
  fi
  if [[ $forcar == 'sim' && $sentido == 'receber' ]]; then
    dbx_cmd_falhar uso_invalido \
      '--forcar (--force) so vale com --enviar: ele pula a checagem de espaco da conta, que o --receber nao faz'
    return $?
  fi
  # RF-81(b): data e tamanho avaliam so a origem; com espelhamento, o item do
  # destino sem par na origem filtrada seria APAGADO. Recusa antes de tudo.
  if [[ $espelhar == 'sim' && ${#filtros_meta[@]} -gt 0 ]]; then
    dbx_cmd_falhar uso_invalido \
      'filtros de data e tamanho avaliam so a origem e fariam o espelhamento apagar no destino; use --excluir/--incluir'
    return $?
  fi
  dbx_cmd_filtros_preparar filtros_caminho filtros_meta || {
    dbx_cmd_falhar uso_invalido "$DBX_CMD_FILTRO_MOTIVO"
    return $?
  }
  dbx_cmd_limite_banda "$tem_limite" "$opcao_limite" "$valor_limite" || {
    dbx_cmd_falhar uso_invalido "$DBX_CMD_LIMITE_MOTIVO"
    return $?
  }

  # RF-54(f)(g): sem a localidade da comparacao, `É` e `é` viram caminhos
  # distintos. O operador e avisado uma vez, so no `sync` (o unico comando que
  # compara sem caixa), e a execucao segue: o aviso nao muda codigo nem stdout.
  if ! dbx_sync_localidade_disponivel; then
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso "$DBX_SYNC_MOTIVO"
    dbx_output_render_diagnostico >&2
  fi

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
  _dbx_cmd_caminho_remoto "$raiz_remota" || return $?
  remoto=$DBX_CMD_LIDO

  # No sentido 'enviar', a origem local deve preexistir para poder ser transferida.
  if [[ $sentido != 'receber' && ! -d $raiz_local ]]; then
    dbx_cmd_falhar nao_encontrado "raiz local inexistente ou nao e diretorio: $raiz_local"
    return $?
  fi

  # RF-69(b): trava do par e area temporaria, pelo ciclo comum ao `verificar`
  # (RNF-36), DEPOIS da validacao e da recusa de caminho e ANTES de qualquer
  # chamada a API, escrita ou leitura de memoria.
  dbx_cmd_ciclo_iniciar sync "$raiz_local" "$remoto" "$espera" || return $?

  # No sentido 'receber', o destino local e criado caso ainda nao exista (se nao
  # for simulacao) — ja sob a trava, porque e escrita.
  if [[ $sentido == 'receber' && ! -d $raiz_local && ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    mkdir -p -- "$raiz_local" 2>/dev/null || {
      dbx_cmd_falhar configuracao "nao foi possivel criar o diretorio de destino: $raiz_local"
      return $?
    }
  fi

  # RF-62(c): a raiz local entra na identidade da memoria ja canonizada, para
  # `./x` e `/abs/x` designarem a mesma memoria e o mesmo "par visto" (RF-48).
  # So a CHAVE muda: a travessia, o plano e a saida usam as raizes como dadas.
  local chave_origem=$origem chave_destino=$destino local_canonico=''
  if dbx_path_local_canonico "$raiz_local"; then
    # shellcheck disable=SC2153  # canal publico de lib/path, carregada por bin/dbx
    local_canonico=$DBX_PATH_RESULTADO
    # shellcheck disable=SC2153  # canal publico de lib/path, carregada por bin/dbx
    if [[ $sentido == 'enviar' ]]; then
      chave_origem=$DBX_PATH_RESULTADO
    else
      chave_destino=$DBX_PATH_RESULTADO
    fi
  fi

  # RF-52(a): sem identidade de conta, sem memoria — nem leitura nem gravacao,
  # e nunca um identificador substituto. Consequencia aceita (DIV-28): o par
  # conta como nunca visto, e `--espelhar` pede reconhecimento.
  # RF-63(a), QA-P3-02: a identificacao da conta falha em silencio por desenho;
  # credencial incompleta precisa ser recusada antes, com a classe e o motivo.
  # Gemeo de `commands/upload.sh` (mesmo conjunto, ver `dbx_auth_preparar`).
  dbx_auth_preparar || {
    dbx_cmd_falhar "$DBX_AUTH_CLASSE" "${DBX_AUTH_MOTIVO:-nao foi possivel obter o token de acesso}"
    return $?
  }
  local conta=''
  _dbx_cmd_sync_conta && conta=$DBX_CMD_SYNC_CONTA
  if [[ -n $conta ]]; then
    dbx_state_carregar "$conta" "$chave_origem" "$chave_destino"
  fi
  local visto=$DBX_STATE_VISTO

  # RF-48: reconhecimento obrigatorio na primeira execucao COM espelhamento.
  if [[ $espelhar == 'sim' && $visto != 'sim' && $confirmado != 'sim' &&
    ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      'primeira execucao com --espelhar sobre este par de raizes: rode antes com --dry-run para ver o plano, ou confirme com --confirmar'
    return $?
  fi

  local area registros_locais registros_remotos
  DBX_CMD_SYNC_FALHAS_CAMINHOS=()
  DBX_CMD_SYNC_FALHAS_CLASSES=()
  # A area e do ciclo comum, registrada em `lib/tmp`: sai em toda saida,
  # inclusive por sinal (RNF-35), sem limpeza por porta de saida.
  area=$DBX_CMD_CICLO_AREA
  registros_locais="$area/local"
  registros_remotos="$area/remoto"
  local revs_remotos="$area/revs"

  local parcial='nao' motivo_parcial=''
  # shellcheck disable=SC2034  # `tamanhos` e preenchido e filtrado por nome (lib/walk, lib/sync)
  local -a caminhos_locais=() tamanhos=() identidades=()
  # Resumo de cada arquivo local, com reaproveitamento pela memoria.
  local -a ordem_local=()
  # shellcheck disable=SC2034  # ver nota acima: passado por nome a lib/sync
  local -A mapa_local=()
  local falhas_de_resumo=0
  # RF-80: o lado de cada ponta, para o predicado unico do escopo
  # (`dbx_sync_no_escopo`), e as contagens de filtrados por lado.
  local lado_local='destino' lado_remoto='origem' filtrados_local=0 filtrados_remoto=0 locais_antes=0
  if [[ $sentido == 'enviar' ]]; then
    lado_local='origem'
    lado_remoto='destino'
  fi

  if [[ $sentido == 'receber' && ! -d $raiz_local ]]; then
    # Em simulacao com destino local inexistente, nao ha itens locais
    : >"$registros_locais"
  else
    dbx_progress_mensagem "[sync] analisando arquivos locais em: $raiz_local"
    dbx_walk_local "$raiz_local" "$registros_locais" || {
        dbx_cmd_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
      return $?
    }
    parcial=$DBX_WALK_PARCIAL motivo_parcial=$DBX_WALK_MOTIVO

    dbx_walk_ler "$registros_locais" caminhos_locais tamanhos identidades
    dbx_sync_sem_temporarios caminhos_locais tamanhos identidades
    locais_antes=${#caminhos_locais[@]}
    # RF-80(a): o escopo de caminho vale nos DOIS lados, com os mesmos padroes.
    dbx_sync_filtrados_zerar
    dbx_sync_filtrar_caminhos "$lado_local" caminhos_locais tamanhos identidades
    # RF-54(c): colisao de caixa e recusa integral, antes de qualquer escrita e
    # tambem em simulacao — o plano de uma arvore assim nao tem leitura unica.
    # Verificada no escopo de CAMINHO, antes de data e tamanho (DIV-93).
    if ! dbx_sync_colisao_de_caixa caminhos_locais; then
        dbx_cmd_falhar conflito "$DBX_SYNC_MOTIVO"
      return $?
    fi
    # RF-81(c): data e tamanho so na origem, e so em arquivo.
    [[ $sentido == 'enviar' ]] && dbx_sync_filtrar_meta caminhos_locais tamanhos identidades
    filtrados_local=$DBX_SYNC_FILTRADOS
    local indice
    local total_locais=${#caminhos_locais[@]}
    for indice in "${!caminhos_locais[@]}"; do
      if _dbx_cmd_sync_resumo_local "$raiz_local" "${caminhos_locais[$indice]}" \
        "${identidades[$indice]}"; then
        ordem_local+=("${caminhos_locais[$indice]}")
        # shellcheck disable=SC2034  # lido por referencia de nome em lib/sync
        mapa_local["${caminhos_locais[$indice]}"]=$DBX_CMD_SYNC_RESUMO
        dbx_progress_mensagem "[sync] analisando local ($((indice + 1))/$total_locais): ${caminhos_locais[$indice]} -> ${DBX_CMD_SYNC_ORIGEM_RESUMO:-ok}"
      else
        # Arquivo ilegivel e travessia parcial: some da origem sem ter sido
        # apagado, e com espelhamento isso viraria exclusao do par no destino.
        falhas_de_resumo=$((falhas_de_resumo + 1))
        parcial='sim'
        # Mesmo motivo do canal de `lib/walk`: uma linha so. Quebra de linha aqui
        # derrubaria o registro do plano inteiro, e justamente na execucao em que
        # ele mais importa.
        motivo_parcial="${motivo_parcial}${motivo_parcial:+; }nao foi possivel calcular o resumo de: ${caminhos_locais[$indice]}"
        dbx_progress_mensagem "[sync] analisando local ($((indice + 1))/$total_locais): ${caminhos_locais[$indice]} -> ${DBX_CMD_SYNC_ORIGEM_RESUMO:-falha na leitura}"
      fi
    done
    dbx_progress_mensagem "[sync] arquivos locais analisados: ${#ordem_local[@]} arquivo(s)"
  fi

  dbx_progress_mensagem "[sync] consultando arquivos remotos em: $remoto"
  # Fase 7b (F-14): no `--receber` do proprio `sync` (nunca no `download` de
  # pasta, DIV-205, nem no `--enviar`), o cursor de listagem pode substituir a
  # varredura remota completa pelo retrato mais o delta. Tudo daqui ate o plano
  # e o MESMO codigo nos dois modos (RF-112(d)).
  _dbx_cmd_sync_cursor_zerar
  if [[ $sentido == 'receber' && ${DBX_CMD_SYNC_CHAMADOR:-} != 'download' ]]; then
    DBX_CMD_SYNC_CURSOR_CAMPOS='sim'
    _dbx_cmd_sync_cursor_preparar "$conta" "$local_canonico" "$remoto" "$lado_remoto" "$sem_cursor" \
      "$varredura_forcada" || return $?
  fi

  # QA-P3-03: o status e capturado ANTES do teste. Lido dentro de `if ! …`, ele
  # e o da negacao (0), e uma enumeracao que falhou terminava o `sync` com sucesso.
  # Duas rodadas no maximo: a segunda so existe quando a confirmacao de
  # exclusao (RF-114) devolve a execucao a varredura completa.
  local estado_remoto=0 rodada
  local -a ordem_remota=()
  # shellcheck disable=SC2034  # preenchido e lido por referencia de nome nas
  # funcoes de lib/sync; a analise estatica nao segue nameref entre arquivos.
  local -A mapa_remoto=() mapa_revs=()
  for rodada in 1 2; do
    [[ $rodada -eq 1 ]] || dbx_progress_mensagem '[sync] consultando arquivos remotos de novo (varredura completa)'
    dbx_sync_filtrados_zerar
    if [[ $DBX_CMD_SYNC_VARREDURA != 'incremental' ]]; then
      estado_remoto=0
      dbx_sync_listar_completo "$remoto" "$lado_remoto" || estado_remoto=$?
      if [[ $estado_remoto -ne 0 ]]; then
        dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" "${DBX_SYNC_MOTIVO:-enumeracao remota falhou}"
        return "$estado_remoto"
      fi
    fi
    # DIV-g: o escopo filtrado e aplicado DEPOIS da tabela inteira.
    dbx_sync_tabela_emitir "$remoto" "$registros_remotos" "$revs_remotos" "$lado_remoto"
    filtrados_remoto=$DBX_SYNC_FILTRADOS
    dbx_sync_ler_resumos "$registros_remotos" ordem_remota mapa_remoto
    dbx_sync_ler_revs "$revs_remotos" mapa_revs
    dbx_progress_mensagem "[sync] arquivos remotos consultados: ${#ordem_remota[@]} arquivo(s)"

    if [[ $sentido == 'enviar' ]]; then
      dbx_sync_planejar ordem_local mapa_local ordem_remota mapa_remoto
    else
      dbx_sync_planejar ordem_remota mapa_remoto ordem_local mapa_local
    fi

    # RF-80(d): item filtrado NUNCA e apagado. O destino ja chega ao plano so com
    # o escopo; esta e a segunda barreira, SEM ESTADO: refaz a conta pelos
    # padroes desta linha de comando, e nada da memoria entra nela.
    _dbx_cmd_sync_sem_protegidos

    # RF-114 (decisao do solicitante; C5): no modo incremental, TODA candidata a
    # exclusao — `deleted` do delta ou ausencia no retrato — e confirmada no
    # servidor nesta execucao, ANTES do plano, com ou sem `--espelhar` (DIV-218)
    # e tambem na simulacao. O cursor sozinho nunca apaga nada.
    [[ $DBX_CMD_SYNC_VARREDURA == 'incremental' && ${#DBX_SYNC_APAGAR[@]} -gt 0 ]] || break
    dbx_sync_confirmar_exclusoes "$remoto" DBX_SYNC_APAGAR
    case $? in
      0)
        DBX_CMD_SYNC_CURSOR_CONFIRMADAS=$DBX_SYNC_CONFIRMADAS
        break
        ;;
      1)
        dbx_cmd_avisar "exclusao nao confirmada pelo servidor (${DBX_SYNC_CONTRADICAO:-resposta duvidosa}): nada sera apagado por ela; varredura completa nesta execucao"
        _dbx_cmd_sync_cursor_abandonar "${DBX_SYNC_CURSOR_MOTIVO:-contradicao}"
        ;;
      *)
        # RF-114(b): falha de transporte na confirmacao e falha da fase de
        # enumeracao, com a classe de hoje: nenhum plano, nada apagado, e o
        # registro fica como estava.
        dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" "${DBX_SYNC_MOTIVO:-confirmacao de exclusao falhou}"
        return $?
        ;;
    esac
  done

  # RF-41(b): origem vazia — no `--enviar`, raiz local sem arquivo; no
  # `--receber`, listagem remota sem arquivo. Uma raiz que ficou vazia por
  # engano (ponto de montagem que nao subiu) e indistinguivel de uma esvaziada
  # de proposito.
  # RF-80(e), DIV-81: a origem e contada NO ESCOPO — origem com arquivos, todos
  # filtrados, e vazia para a guarda.
  local vazia='nao' origem_antes origem_depois filtrados_origem filtrados_destino
  if [[ $sentido == 'enviar' ]]; then
    [[ ${#caminhos_locais[@]} -eq 0 ]] && vazia='sim'
    origem_antes=$locais_antes origem_depois=${#caminhos_locais[@]}
    filtrados_origem=$filtrados_local filtrados_destino=$filtrados_remoto
  else
    [[ ${#ordem_remota[@]} -eq 0 ]] && vazia='sim'
    origem_antes=$DBX_SYNC_REMOTOS_ANTES origem_depois=${#ordem_remota[@]}
    filtrados_origem=$filtrados_remoto filtrados_destino=$filtrados_local
  fi

  # DIV-91: filtro mal escrito avisa em stderr, sem mudar stdout nem codigo.
  dbx_sync_avisos_de_filtro "$origem_antes" "$origem_depois"
  dbx_cmd_avisos_de_filtro

  # RF-41(b) com O-1 (memorias `2026-10-18-2243-guarda-origem-vazia` e
  # `2026-10-19-0829-aliases-poda-e-comentarios`): com espelhamento, origem vazia
  # e algo a apagar no destino e recusa integral, nos dois sentidos, sem
  # depender da memoria — que pode faltar, estar descartada ou ilegivel. Sem
  # `--espelhar` nada seria apagado e a origem vazia e operacao vazia (DIV-30).
  # So `--permitir-origem-vazia` libera; `--confirmar` reconhece a primeira
  # execucao (RF-48), nao uma origem vazia.
  #
  # A recusa sai DEPOIS do plano e ANTES de qualquer escrita (RF-41(d)): o plano
  # registra `recusada=origem vazia`, sem listar exclusao, e a execucao para ali.
  # Em SIMULACAO (RF-44, sai com 0) o plano anuncia `recusaria`.
  local recusa_origem_vazia='nao' a_apagar_recusado=0 recusaria=''
  if [[ $espelhar == 'sim' && $vazia == 'sim' && ${#DBX_SYNC_APAGAR[@]} -gt 0 &&
    $permitir_origem_vazia != 'sim' ]]; then
    recusa_origem_vazia='sim'
    a_apagar_recusado=${#DBX_SYNC_APAGAR[@]}
    [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && recusaria='origem vazia'
    DBX_SYNC_APAGAR=()
  fi

  if dbx_progress_ativo; then
    local total_analisados=$(( ${#DBX_SYNC_TRANSFERIR[@]} + ${#DBX_SYNC_IDENTICOS[@]} + ${#DBX_SYNC_APAGAR[@]} ))
    local idx_analise=0
    local acao_transferir='a enviar'
    [[ $sentido == 'receber' ]] && acao_transferir='a receber'
    dbx_progress_mensagem "[sync] analisando diferencas e comparando origem e destino ($total_analisados arquivo(s) no total)..."

    for caminho in ${DBX_SYNC_IDENTICOS[@]+"${DBX_SYNC_IDENTICOS[@]}"}; do
      idx_analise=$((idx_analise + 1))
      dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $caminho -> identico (dispensado)"
    done

    for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
      idx_analise=$((idx_analise + 1))
      local tipo_item='novo' par=${DBX_SYNC_ALVO[$caminho]:-$caminho}
      if [[ $sentido == 'enviar' && -n ${mapa_remoto[$par]+definido} ]]; then
        tipo_item='modificado'
      elif [[ $sentido == 'receber' && -n ${mapa_local[$par]+definido} ]]; then
        tipo_item='modificado'
      fi
      dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $caminho -> $tipo_item ($acao_transferir)"
    done

    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      idx_analise=$((idx_analise + 1))
      if [[ $espelhar == 'sim' ]]; then
        dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $caminho -> ausente na origem (a apagar)"
      else
        dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $caminho -> apenas no destino (mantido)"
      fi
    done
    dbx_progress_mensagem "[sync] resultado da analise: ${#DBX_SYNC_TRANSFERIR[@]} a transferir, ${#DBX_SYNC_APAGAR[@]} a apagar, ${#DBX_SYNC_IDENTICOS[@]} inalterado(s)"
  fi

  # RF-41(a): travessia parcial desabilita exclusao NA EXECUCAO INTEIRA, e nao
  # apenas no ramo que falhou. Um ramo invisivel produz exatamente a mesma
  # observacao que um ramo apagado, e nao ha como distinguir depois.
  #
  # RF-52(a) com RF-41(e) (DIV-28): sem identidade de conta nao ha memoria nem
  # linha de base. A origem vazia ja e recusada acima; esta guarda cobre a
  # origem PARCIAL (nao vazia) sem base. A exclusao fica desabilitada com a
  # MESMA semantica da travessia parcial, nos dois sentidos, e `--confirmar` NAO
  # a reabilita: ele reconhece a primeira execucao (RF-48), nao substitui a
  # memoria que falta.
  local exclusao_desabilitada='nao' motivo_exclusao=''
  if [[ $espelhar == 'sim' && $parcial == 'sim' ]]; then
    motivo_exclusao='travessia parcial'
  fi
  if [[ $espelhar == 'sim' && -z $conta ]]; then
    motivo_exclusao="${motivo_exclusao}${motivo_exclusao:+; }conta nao identificada"
  fi
  # RF-41(f): memoria que existia e foi descartada na carga deixa o par "visto"
  # sem linha de base. Mesma semantica: exclusao desabilitada nesta execucao; a
  # memoria e regravada em v2 no fim, e a execucao seguinte volta ao normal.
  local memoria_descartada=${DBX_STATE_DESCARTADA:-nao}
  if [[ $espelhar == 'sim' && $memoria_descartada == 'sim' ]]; then
    motivo_exclusao="${motivo_exclusao}${motivo_exclusao:+; }memoria descartada"
  fi
  if [[ -n $motivo_exclusao ]]; then
    exclusao_desabilitada='sim'
    DBX_SYNC_APAGAR=()
  fi

  local total_transferir=${#DBX_SYNC_TRANSFERIR[@]}
  local total_apagar=0
  [[ $espelhar == 'sim' ]] && total_apagar=${#DBX_SYNC_APAGAR[@]}

  # RF-67: checagem previa de espaco, so no `--enviar`, depois das guardas de
  # RF-41 e RF-48 e do plano, antes da primeira acao. O total e a soma da parte
  # "transferir" (omitidos e exclusoes fora), e a sobrescrita conta o arquivo
  # novo inteiro. Em simulacao, so o anuncio `recusaria`.
  local recusa_espaco='nao' recusaria_espaco=''
  if [[ $sentido == 'enviar' && $recusa_origem_vazia != 'sim' ]]; then
    local -A tamanho_local=()
    local item total_bytes=0
    for item in "${!caminhos_locais[@]}"; do
      tamanho_local["${caminhos_locais[$item]}"]=${tamanhos[$item]}
    done
    for item in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
      total_bytes=$((total_bytes + ${tamanho_local[$item]:-0}))
    done
    if ! dbx_cmd_espaco_checar "$total_bytes" "$forcar"; then
      if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
        recusaria_espaco=$DBX_CMD_ESPACO_MOTIVO
      else
        recusa_espaco='sim'
      fi
    fi
  fi

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
  dbx_cmd_campos_de_filtro "$filtrados_origem" "$filtrados_destino"
  dbx_output_campo limite_banda "$DBX_CMD_LIMITE_BANDA"
  # RF-118(d): acrescimo compativel, so no `sync --receber`; nunca o cursor.
  if [[ $DBX_CMD_SYNC_CURSOR_CAMPOS == 'sim' ]]; then
    dbx_output_campo varredura "$DBX_CMD_SYNC_VARREDURA"
    [[ $DBX_CMD_SYNC_VARREDURA == 'completa' ]] &&
      dbx_output_campo cursor_motivo "$DBX_CMD_SYNC_CURSOR_MOTIVO"
    dbx_output_campo cursor_mudancas "$DBX_CMD_SYNC_CURSOR_MUDANCAS"
    dbx_output_campo cursor_confirmadas "$DBX_CMD_SYNC_CURSOR_CONFIRMADAS"
  fi
  [[ $exclusao_desabilitada == 'sim' ]] &&
    dbx_output_campo exclusao_desabilitada "$motivo_exclusao"
  if [[ -n $recusaria ]]; then
    dbx_output_campo recusaria "$recusaria (a execucao real seria recusada; use --permitir-origem-vazia para apagar)"
  elif [[ $recusa_origem_vazia == 'sim' ]]; then
    dbx_output_campo recusada 'origem vazia'
  fi
  dbx_output_campo a_transferir "$total_transferir"
  dbx_output_campo a_apagar "$total_apagar"
  dbx_output_campo identicos "${#DBX_SYNC_IDENTICOS[@]}"
  if [[ $sentido == 'enviar' ]]; then
    dbx_cmd_espaco_campos
    [[ -n $recusaria_espaco ]] &&
      dbx_output_campo recusaria "$recusaria_espaco (a execucao real seria recusada)"
  fi
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

  # RF-41(b) emendado: a recusa da origem vazia acontece aqui, com o plano ja
  # emitido e antes de qualquer escrita.
  if [[ $recusa_origem_vazia == 'sim' && ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    local vazia_texto='a origem esta vazia'
    if dbx_filtro_ativo; then
      dbx_filtro_descrever
      vazia_texto="origem vazia depois dos filtros ($DBX_FILTRO_DESCRICAO)"
    fi
    dbx_cmd_falhar nao_concluida \
      "$vazia_texto e o espelhamento apagaria $a_apagar_recusado item(ns) no destino: execucao recusada integralmente (se a origem foi esvaziada de proposito, use --permitir-origem-vazia ou --allow-empty-source; --confirmar ou --yes nao basta)"
    return $?
  fi

  # RF-67(d): com o plano ja emitido e antes de qualquer escrita.
  if [[ $recusa_espaco == 'sim' ]]; then
    dbx_cmd_falhar espaco "$DBX_CMD_ESPACO_MOTIVO"
    return $?
  fi

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  local total_ops=0
  [[ ${#DBX_SYNC_TRANSFERIR[@]} -gt 0 ]] && total_ops=$((total_ops + ${#DBX_SYNC_TRANSFERIR[@]}))
  if [[ $espelhar == 'sim' && ${#DBX_SYNC_APAGAR[@]} -gt 0 ]]; then
    total_ops=$((total_ops + ${#DBX_SYNC_APAGAR[@]}))
  fi

  local op_atual=0 alvo rev antes apagar raiz_do_destino
  local enviados=0 recebidos=0 apagados=0 falhas=0
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    op_atual=$((op_atual + 1))
    # A escrita usa a grafia que o destino ja tem (RF-54(d)).
    alvo=${DBX_SYNC_ALVO[$caminho]:-$caminho}
    antes=${DBX_HTTP_REQUISICOES:-0}
    if [[ $sentido == 'enviar' ]]; then
      dbx_progress_etapa "$op_atual" "$total_ops" 'enviando' "$caminho"
      rev=''
      [[ -n ${mapa_remoto[$alvo]+definido} ]] && rev=${mapa_revs[$alvo]:-}
      if _dbx_cmd_sync_enviar "$raiz_local/$caminho" "$remoto/$alvo" "$rev"; then
        enviados=$((enviados + 1))
      else
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falhou "$caminho" "$antes"
      fi
    else
      dbx_progress_etapa "$op_atual" "$total_ops" 'recebendo' "$caminho"
      if _dbx_cmd_sync_receber "$remoto/$caminho" "$raiz_local" "$alvo"; then
        recebidos=$((recebidos + 1))
      else
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falhou "$caminho" "$antes"
        # RF-111(g), C6: item do plano incremental que o servidor nao tem (ou
        # que conflita no caminho) e retrato com entrada fantasma: o registro
        # sai, e a execucao seguinte faz a varredura completa.
        if [[ $DBX_CMD_SYNC_VARREDURA == 'incremental' &&
          ($DBX_CMD_SYNC_FALHA_CLASSE == 'nao_encontrado' || $DBX_CMD_SYNC_FALHA_CLASSE == 'conflito') ]]; then
          dbx_state_cursor_remover
          DBX_CMD_SYNC_CURSOR_GRAVA='nao'
        fi
      fi
    fi
  done

  if [[ $espelhar == 'sim' ]]; then
    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      # RF-80(d), no ponto da escrita: a mesma conta sem estado, de novo.
      _dbx_cmd_sync_protegido "$caminho" && continue
      op_atual=$((op_atual + 1))
      dbx_progress_etapa "$op_atual" "$total_ops" 'apagando' "$caminho"
      antes=${DBX_HTTP_REQUISICOES:-0}
      apagar=_dbx_cmd_sync_apagar_local
      raiz_do_destino=$raiz_local
      if [[ $sentido == 'enviar' ]]; then
        apagar=_dbx_cmd_sync_apagar_remoto
        raiz_do_destino=$remoto
      fi
      if "$apagar" "$raiz_do_destino" "$caminho"; then
        apagados=$((apagados + 1))
      else
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falhou "$caminho" "$antes"
      fi
    done
  fi

  dbx_progress_mensagem "[sync] sincronizacao concluida: $enviados enviados, $recebidos recebidos, $apagados apagados, ${#DBX_SYNC_IDENTICOS[@]} omitidos"

  # A memoria e gravada mesmo com falha parcial de transferencia: os resumos
  # calculados continuam validos. Grava so as entradas visitadas (RF-38(b)).
  # Sem conta, nada (RF-52(a)).
  # Diretorio de estado alheio nao muda o resultado; o operador e avisado.
  #
  # QA-P3-06 (ciclo 4): a memoria so e regravada depois de uma travessia
  # COMPLETA. Com travessia parcial nada e gravado: regravar uma memoria
  # descartada so com o que se viu deixaria uma base sem os ramos invisiveis, e
  # a execucao seguinte a leria como valida.
  if [[ -n $conta && $parcial != 'sim' ]]; then
    dbx_state_gravar "$conta" "$chave_origem" "$chave_destino" sim
    if [[ $? -eq $DBX_STATE_ERRO_PERMISSAO ]]; then
      dbx_cmd_iniciar_saida
      dbx_output_diagnostico aviso "$DBX_STATE_MOTIVO"
      dbx_output_render_diagnostico >&2
    fi
  fi

  # RF-111(g), C6: o cursor e gravado UMA vez, depois da memoria, sob a trava,
  # so quando a execucao vai terminar com 0. Falha ao gravar preserva o
  # registro anterior (consistente, apenas mais antigo).
  if [[ $DBX_CMD_SYNC_CURSOR_GRAVA == 'sim' && $falhas -eq 0 && $parcial != 'sim' &&
    ! ($espelhar == 'sim' && ($memoria_descartada == 'sim' || -z $conta)) ]]; then
    _dbx_cmd_sync_cursor_gravar
  fi

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao sync
  dbx_output_campo enviados "$enviados"
  dbx_output_campo recebidos "$recebidos"
  dbx_output_campo apagados "$apagados"
  dbx_output_campo omitidos "${#DBX_SYNC_IDENTICOS[@]}"
  dbx_output_campo falhas "$falhas"
  # RF-59(b): no `--json`, cada falha vira o par `falha_caminho`/`falha_classe`,
  # na ordem das linhas de falha. Acrescimo compativel (RF-35): `falhas`, a
  # contagem, continua como era, e sem `--json` a saida padrao nao muda.
  local indice valor
  if [[ ${DBX_CLI_ESTRUTURADA:-nao} == 'sim' ]]; then
    for indice in "${!DBX_CMD_SYNC_FALHAS_CAMINHOS[@]}"; do
      valor=${DBX_CMD_SYNC_FALHAS_CAMINHOS[indice]}
      # Com `--null` o registro carrega qualquer byte; por linha, vale a mesma
      # citacao da linha de falha.
      if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
        _dbx_cmd_sync_exibir "$valor"
        valor=$DBX_CMD_SYNC_EXIBIDO
      fi
      dbx_output_campo falha_caminho "$valor"
      dbx_output_campo falha_classe "${DBX_CMD_SYNC_FALHAS_CLASSES[indice]}"
    done
  fi
  # RF-80(j), RF-82(i): acrescimo compativel ao resumo (RF-35).
  dbx_cmd_campos_de_filtro "$filtrados_origem" "$filtrados_destino"
  dbx_output_campo limite_banda "$DBX_CMD_LIMITE_BANDA"
  dbx_output_render

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
  if [[ $espelhar == 'sim' && -z $conta ]]; then
    dbx_cmd_falhar nao_concluida \
      'a identificacao da conta falhou: as exclusoes do espelhamento foram desabilitadas nesta execucao (--confirmar nao as reabilita)'
    return $?
  fi
  if [[ $espelhar == 'sim' && $memoria_descartada == 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      "a memoria deste par foi descartada (${DBX_STATE_MOTIVO:-ilegivel}): as exclusoes foram desabilitadas nesta execucao; a memoria foi refeita e a proxima execucao volta a propaga-las"
    return $?
  fi
  return 0
}

# _dbx_cmd_sync_protegido <caminho_do_destino> — 0 quando o item esta FORA do
# escopo dos filtros desta execucao e por isso NUNCA pode ser apagado (RF-80(d)).
#
# Guarda sem estado (memoria `guarda-de-seguranca-sem-estado`): le so os padroes
# da linha de comando, nunca a memoria do sync, a trava ou qualquer arquivo.
_dbx_cmd_sync_protegido() {
  dbx_filtro_ativo || return 1
  dbx_filtro_classificar "$1" nao && return 1
  return 0
}

# _dbx_cmd_sync_sem_protegidos — tira do plano de exclusao todo item protegido.
_dbx_cmd_sync_sem_protegidos() {
  local caminho
  local -a manter=()
  for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    _dbx_cmd_sync_protegido "$caminho" && continue
    manter+=("$caminho")
  done
  DBX_SYNC_APAGAR=(${manter[@]+"${manter[@]}"})
}

# _dbx_cmd_sync_enviar <arquivo_local> <caminho_remoto> <rev>
#
# Mesmo caminho do `upload` (RF-57): objeto de publicacao e roteamento por
# tamanho vem de `lib/transfer`. Com `rev` o envio e `update` sobre ele (RF-49):
# mudanca remota desde a listagem desta execucao e recusada como conflito e o
# item conta como falha, sem sobrescrever. Sem `rev` o arquivo e novo, e vai em
# `add` — se alguem o criou nesse intervalo, a recusa tambem protege.
#
# As quatro operacoes de item publicam a classe da falha em
# DBX_CMD_SYNC_FALHA_CLASSE (RF-59); a saida delas continua descartada.
_dbx_cmd_sync_enviar() {
  local origem=$1 destino=$2 rev=$3
  DBX_CMD_SYNC_FALHA_CLASSE=''
  dbx_transfer_objeto_de_publicacao "$destino" add "$rev" "$origem" true
  dbx_transfer_enviar_arquivo "$origem" "$DBX_TRANSFER_COMMIT" sync >/dev/null 2>&1 && return 0
  DBX_CMD_SYNC_FALHA_CLASSE=${DBX_TRANSFER_CLASSE:-erro_remoto}
  return 1
}

# _dbx_cmd_sync_receber <caminho_remoto> <raiz_local> <relativo_local>
#
# Recebimento atomico com conferencia de resumo (RF-55(e)), o mesmo do
# `download`. Falha local publica a propria classe; a de transporte vem de
# `lib/http`.
_dbx_cmd_sync_receber() {
  local remoto=$1 raiz=$2 relativo=$3
  local pasta=${relativo%/*}
  DBX_CMD_SYNC_FALHA_CLASSE='configuracao'
  [[ $pasta == "$relativo" ]] || mkdir -p -- "$raiz/$pasta" 2>/dev/null || return 1
  DBX_CMD_SYNC_FALHA_CLASSE=''
  dbx_cmd_receber_arquivo "$remoto" "$raiz/$relativo" >/dev/null 2>&1 && return 0
  DBX_CMD_SYNC_FALHA_CLASSE=${DBX_CMD_FALHA_CLASSE:-${DBX_HTTP_CLASSE:-erro_remoto}}
  return 1
}

_dbx_cmd_sync_apagar_remoto() {
  local remoto=$1 relativo=$2
  DBX_CMD_SYNC_FALHA_CLASSE=''
  dbx_json_escapar_cadeia "$remoto/$relativo"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/delete_v2' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\"}" nao >/dev/null 2>&1 && return 0
  DBX_CMD_SYNC_FALHA_CLASSE=${DBX_HTTP_CLASSE:-erro_remoto}
  return 1
}

# Sem permissao de escrita no diretorio e o caso comum de `rm` recusar aqui.
_dbx_cmd_sync_apagar_local() {
  local raiz=$1 relativo=$2
  DBX_CMD_SYNC_FALHA_CLASSE=''
  rm -f -- "$raiz/$relativo" 2>/dev/null && return 0
  DBX_CMD_SYNC_FALHA_CLASSE='permissao'
  return 1
}

# ---------------------------------------------------------------------------
# Cursor de listagem entre execucoes (fase 7b, F-14; RF-110 a RF-119)
# ---------------------------------------------------------------------------
#
# O ESTADO SO ACELERA (decisao do solicitante). O registro `cursor-*` (lib/state)
# troca a varredura remota completa pelo retrato mais o delta; qualquer duvida —
# sem registro, registro invalido, `reset`, erro transitorio, laco, contradicao,
# varredura periodica vencida — volta a varredura completa NA MESMA execucao, sem
# falhar e com o codigo de uma execucao sem estado (RF-113). Nenhuma exclusao
# nasce do registro sem confirmacao no servidor (RF-114). O cursor nunca aparece
# em saida, aviso, progresso nem diagnostico (C10).

# Canais desta execucao (zerados a cada `sync`).
DBX_CMD_SYNC_CURSOR_CAMPOS='nao'
DBX_CMD_SYNC_VARREDURA='completa'
DBX_CMD_SYNC_CURSOR_MOTIVO=''
DBX_CMD_SYNC_CURSOR_GRAVA='nao'
DBX_CMD_SYNC_CURSOR_MUDANCAS=0
DBX_CMD_SYNC_CURSOR_CONFIRMADAS=0
DBX_CMD_SYNC_CURSOR_COMPLETA_EM=''
DBX_CMD_SYNC_CURSOR_INCREMENTAIS=0

_dbx_cmd_sync_cursor_zerar() {
  DBX_CMD_SYNC_CURSOR_CAMPOS='nao'
  DBX_CMD_SYNC_VARREDURA='completa'
  DBX_CMD_SYNC_CURSOR_MOTIVO=''
  DBX_CMD_SYNC_CURSOR_GRAVA='nao'
  DBX_CMD_SYNC_CURSOR_MUDANCAS=0
  DBX_CMD_SYNC_CURSOR_CONFIRMADAS=0
  DBX_CMD_SYNC_CURSOR_COMPLETA_EM=''
  DBX_CMD_SYNC_CURSOR_INCREMENTAIS=0
  dbx_sync_tabela_zerar
}

# _dbx_cmd_sync_cursor_abandonar <motivo> — volta a varredura completa nesta
# execucao: a tabela do retrato sai e o registro e apagado (nunca em simulacao,
# RF-117(a)). `memoria-*` nunca e tocada (RF-43, C9).
_dbx_cmd_sync_cursor_abandonar() {
  DBX_CMD_SYNC_VARREDURA='completa'
  DBX_CMD_SYNC_CURSOR_MOTIVO=$1
  DBX_CMD_SYNC_CURSOR_MUDANCAS=0
  DBX_CMD_SYNC_CURSOR_CONFIRMADAS=0
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] || dbx_state_cursor_remover
  dbx_sync_tabela_zerar
}

# _dbx_cmd_sync_cursor_preparar <conta> <local_canonico> <remoto> <lado>
#   <sem_cursor> <varredura_forcada>
#
# Decide o modo da enumeracao remota. No incremental, deixa a tabela de
# `lib/sync` montada (retrato mais delta) e DBX_CMD_SYNC_VARREDURA=incremental;
# em todos os outros casos, a varredura completa com o motivo de RF-118(d).
# Status diferente de zero so quando a varredura completa tambem falharia pela
# mesma causa: 401/403 no `continue` (RF-113(b)).
_dbx_cmd_sync_cursor_preparar() {
  local conta=$1 local_=$2 remoto=$3 lado=$4 sem_cursor=$5 forcada=$6 apagar='sim' cursor retrato
  if [[ $sem_cursor == 'sim' ]]; then
    # RF-118(a): nao le, nao grava, nao apaga.
    DBX_CMD_SYNC_CURSOR_MOTIVO='desligado'
    return 0
  fi
  DBX_CMD_SYNC_CURSOR_MOTIVO='sem-registro'
  [[ $forcada == 'sim' ]] && DBX_CMD_SYNC_CURSOR_MOTIVO='forcada'
  # C2, C7: sem `cred-`, sem `account_id`, sem raiz local canonica ou sem a
  # trava do par (DIV-48), nao ha cursor: nem leitura nem gravacao.
  [[ -n ${DBX_CONFIG_IDENTIDADE:-} && -n $conta && -n $local_ ]] || return 0
  if [[ -z ${DBX_STATE_TRAVA:-} ]]; then
    dbx_cmd_avisar 'registro de listagem nao usado nesta execucao: sem a trava do par (varredura completa)'
    return 0
  fi
  dbx_state_cursor_contexto "$DBX_CONFIG_IDENTIDADE" "$conta" "$local_" "$remoto" \
    "$DBX_SYNC_ASSINATURA_LISTAGEM" || return 0
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && apagar='nao'
  [[ $apagar == 'sim' ]] && DBX_CMD_SYNC_CURSOR_GRAVA='sim'
  # RF-118(b): a forcada nao le o registro e o regrava ao fim.
  [[ $forcada == 'sim' ]] && return 0

  dbx_sync_tabela_zerar
  # shellcheck disable=SC2034  # canal publico de lib/sync, lido pela funcao de entrada
  DBX_SYNC_RETRATO_RAIZ=$remoto
  dbx_state_cursor_carregar dbx_sync_retrato_entrada "$apagar"
  case $? in
    0) ;;
    1)
      dbx_sync_tabela_zerar
      return 0
      ;;
    2)
      dbx_sync_tabela_zerar
      DBX_CMD_SYNC_CURSOR_MOTIVO='descartado'
      dbx_cmd_avisar "${DBX_STATE_MOTIVO:-registro de listagem invalido}: descartado, varredura completa"
      return 0
      ;;
    3)
      # Ligacao simbolica, nao regular ou de outro dono: nao e lido nem
      # substituido (RF-111(h)).
      dbx_sync_tabela_zerar
      DBX_CMD_SYNC_CURSOR_MOTIVO='descartado'
      DBX_CMD_SYNC_CURSOR_GRAVA='nao'
      dbx_cmd_avisar 'registro de listagem inacessivel (ligacao, nao regular ou de outro dono): nao lido nem substituido, varredura completa'
      return 0
      ;;
    *)
      dbx_sync_tabela_zerar
      return 0
      ;;
  esac
  cursor=$DBX_STATE_CURSOR_VALOR
  DBX_STATE_CURSOR_VALOR=''
  DBX_CMD_SYNC_CURSOR_COMPLETA_EM=$DBX_STATE_CURSOR_COMPLETA_EM
  DBX_CMD_SYNC_CURSOR_INCREMENTAIS=$DBX_STATE_CURSOR_INCREMENTAIS_DESDE
  # C8, DIV-208: a varredura periodica obrigatoria. O relogio so decide fazer
  # MAIS trabalho; o registro sera regravado com os contadores zerados.
  if dbx_state_cursor_vencido "$DBX_CMD_SYNC_CURSOR_COMPLETA_EM" "$DBX_CMD_SYNC_CURSOR_INCREMENTAIS"; then
    dbx_sync_tabela_zerar
    DBX_CMD_SYNC_CURSOR_MOTIVO='periodica'
    dbx_cmd_avisar 'varredura completa periodica (a ultima tem mais de 7 dias, 100 execucoes incrementais, ou o relogio voltou)'
    return 0
  fi
  dbx_sync_tabela_arquivos
  retrato=$DBX_SYNC_LIDO
  dbx_progress_mensagem '[sync] consultando mudancas remotas desde a ultima execucao...'
  dbx_sync_listar_delta "$remoto" "$cursor" "$lado"
  case $? in
    0) ;;
    1)
      case $DBX_SYNC_CURSOR_MOTIVO in
        reset) dbx_cmd_avisar 'o servidor invalidou o registro de listagem (reset): varredura completa' ;;
        transitorio) dbx_cmd_avisar 'mudancas remotas indisponiveis (rede, limite de taxa ou erro do servico): varredura completa' ;;
        *) dbx_cmd_avisar 'mudancas remotas incoerentes ou sem fim: registro de listagem descartado, varredura completa' ;;
      esac
      _dbx_cmd_sync_cursor_abandonar "${DBX_SYNC_CURSOR_MOTIVO:-descartado}"
      return 0
      ;;
    *)
      dbx_sync_tabela_zerar
      dbx_cmd_falhar "${DBX_HTTP_CLASSE:-autenticacao}" "${DBX_SYNC_MOTIVO:-consulta de mudancas recusada}"
      return $?
      ;;
  esac
  # RF-116(c): mapa reconstruido sem arquivo a partir de retrato com arquivo vai
  # a varredura completa ANTES da guarda de origem vazia (RF-41(b)).
  dbx_sync_tabela_arquivos
  if [[ $retrato -gt 0 && $DBX_SYNC_LIDO -eq 0 ]]; then
    dbx_cmd_avisar 'as mudancas remotas esvaziariam a origem: varredura completa para conferir'
    _dbx_cmd_sync_cursor_abandonar descartado
    return 0
  fi
  # RF-81 sobre o retrato: o filtro de data so vale com a data de toda entrada.
  if ! dbx_sync_tabela_datada; then
    _dbx_cmd_sync_cursor_abandonar descartado
    return 0
  fi
  DBX_CMD_SYNC_VARREDURA='incremental'
  DBX_CMD_SYNC_CURSOR_MOTIVO=''
  DBX_CMD_SYNC_CURSOR_MUDANCAS=$DBX_SYNC_DELTA_MUDANCAS
  return 0
}

# _dbx_cmd_sync_cursor_gravar — grava cursor e retrato (C6): cursor da ultima
# pagina, tabela sem filtro desta execucao, carimbo e contagem de incrementais.
# Tabela fora do formato ou cursor fora da regex: nao persiste, sem aviso (a
# proxima execucao faz a varredura completa). Falha de escrita: um aviso, o
# mesmo resultado e o mesmo codigo (RF-111(g)).
_dbx_cmd_sync_cursor_gravar() {
  local completa incrementais agora
  [[ $DBX_SYNC_TAB_PERSISTIVEL == 'sim' && $DBX_SYNC_CURSOR_NOVO =~ $DBX_STATE_CURSOR_RE_CURSOR ]] || return 0
  dbx_sync_tabela_contar
  [[ $DBX_SYNC_LIDO -le $DBX_STATE_CURSOR_ENTRADAS ]] || return 0
  printf -v agora '%(%s)T' -1
  if [[ $DBX_CMD_SYNC_VARREDURA == 'incremental' ]]; then
    completa=$DBX_CMD_SYNC_CURSOR_COMPLETA_EM
    incrementais=$((DBX_CMD_SYNC_CURSOR_INCREMENTAIS + 1))
  else
    completa=$agora
    incrementais=0
  fi
  if ! dbx_state_cursor_gravar "$DBX_SYNC_CURSOR_NOVO" "$completa" "$incrementais" "$DBX_SYNC_LIDO" \
    dbx_sync_tabela_corpo; then
    dbx_cmd_avisar 'registro de listagem nao gravado: a proxima execucao faz a varredura completa'
  fi
  DBX_SYNC_CURSOR_NOVO=''
  return 0
}
