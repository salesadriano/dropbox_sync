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
# RF-208: motivo e tamanho (bytes, ou vazio) de cada falha, e caminho e tamanho
# de cada arquivo concluido, na ordem em que ocorreram, para o relatorio final.
DBX_CMD_SYNC_FALHAS_MOTIVOS=()
DBX_CMD_SYNC_FALHAS_TAMANHOS=()
DBX_CMD_SYNC_OK_CAMINHOS=()
DBX_CMD_SYNC_OK_TAMANHOS=()
# RF-214(e): arquivos apagados no lugar de pasta (linha `apagado` do relatorio).
DBX_CMD_SYNC_APAGADOS_PASTA=()
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
  # DIV-278: falha de integridade traz o motivo da conferencia, o mesmo que o
  # envio em lote usa para o mesmo item.
  if [[ ${DBX_CMD_SYNC_FALHA_CLASSE:-} == 'integridade' && -n ${DBX_TRANSFER_MOTIVO:-} ]]; then
    dbx_errors_redigir "$DBX_TRANSFER_MOTIVO" >/dev/null
    DBX_CMD_SYNC_RESUMO_FALHA=${DBX_ERRORS_REDIGIDO:0:120}
    return 0
  fi
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
  local caminho=$1 antes=$2
  _dbx_cmd_sync_resumo_da_falha "$antes"
  _dbx_cmd_sync_falha_emitir "$caminho"
}

# _dbx_cmd_sync_falha_emitir <caminho> — registra a falha do item com a classe em
# DBX_CMD_SYNC_FALHA_CLASSE e o resumo em DBX_CMD_SYNC_RESUMO_FALHA, e emite a
# linha. Ponto unico: o caminho sequencial e o descarregamento ordenado do
# paralelo (DIV-257) produzem a MESMA linha.
_dbx_cmd_sync_falha_emitir() {
  local caminho=$1 classe=${DBX_CMD_SYNC_FALHA_CLASSE:-erro_remoto}
  DBX_CMD_SYNC_FALHAS_CAMINHOS+=("$caminho")
  DBX_CMD_SYNC_FALHAS_CLASSES+=("$classe")
  DBX_CMD_SYNC_FALHAS_MOTIVOS+=("${DBX_CMD_SYNC_RESUMO_FALHA:-falha local}")
  _dbx_cmd_sync_tamanho_do_item "$caminho"
  DBX_CMD_SYNC_FALHAS_TAMANHOS+=("$DBX_CMD_SYNC_TAMANHO_ITEM")
  _dbx_cmd_sync_exibir "$caminho"
  # QA-P2-02 (b): defesa em profundidade, a mesma do diagnostico — todo segredo
  # em memoria e mascarado pelo valor na linha inteira, antes de sair.
  local linha
  printf -v linha 'falha %s: %s %s' "$DBX_CMD_SYNC_EXIBIDO" "$classe" "$DBX_CMD_SYNC_RESUMO_FALHA"
  dbx_output_mascarar_segredos "$linha"
  printf '%s\n' "$DBX_OUTPUT_MASCARADO" >&2
}

# _dbx_cmd_sync_tamanho_do_item <caminho> — RF-208: bytes do item para o
# relatorio, em DBX_CMD_SYNC_TAMANHO_ITEM (vazio quando desconhecido). No envio,
# o tamanho lido na analise local (`tam_item`, escopo dinamico do executor); no
# recebimento, o arquivo gravado no local e, sem ele, o `size` da listagem.
DBX_CMD_SYNC_TAMANHO_ITEM=''
_dbx_cmd_sync_tamanho_do_item() {
  local alvo
  DBX_CMD_SYNC_TAMANHO_ITEM=''
  if [[ ${sentido:-} == 'enviar' ]]; then
    DBX_CMD_SYNC_TAMANHO_ITEM=${tam_item[$1]:-}
  elif [[ ${sentido:-} == 'receber' ]]; then
    alvo=${DBX_SYNC_ALVO[$1]:-$1}
    if [[ -n ${raiz_local:-} && -f $raiz_local/$alvo ]] && dbx_transfer_tamanho_de_arquivo "$raiz_local/$alvo"; then
      DBX_CMD_SYNC_TAMANHO_ITEM=$DBX_TRANSFER_TAMANHO
    else
      DBX_CMD_SYNC_TAMANHO_ITEM=${mapa_tam_remoto[$1]:-}
    fi
  fi
  [[ $DBX_CMD_SYNC_TAMANHO_ITEM =~ ^[0-9]+$ ]] || DBX_CMD_SYNC_TAMANHO_ITEM=''
}

# _dbx_cmd_sync_concluido <caminho> — RF-208: registra o arquivo concluido, com
# o tamanho, para o relatorio final. Ponto unico dos quatro caminhos de sucesso
# (lote, sequencial de envio, sequencial de recebimento e paralelo).
_dbx_cmd_sync_concluido() {
  _dbx_cmd_sync_tamanho_do_item "$1"
  DBX_CMD_SYNC_OK_CAMINHOS+=("$1")
  DBX_CMD_SYNC_OK_TAMANHOS+=("$DBX_CMD_SYNC_TAMANHO_ITEM")
}

# _dbx_cmd_sync_relatorio_itens <legivel|estruturado> — RF-208: as linhas por
# arquivo do relatorio final. `legivel` sai SEMPRE, nos dois modos de saida (sem
# terminal, caso do nohup, a saida ja e `chave=valor`): `enviado|recebido=<caminho>
# (<tamanho>)` e `falha=<caminho> (<tamanho>): <classe> <motivo>`, antes dos
# contadores. `estruturado` so com --json: `falha_motivo`/`falha_tamanho` entram
# no par de RF-59(b) (quem chama) e cada concluido vira `<acao>_caminho`/
# `<acao>_tamanho` em bytes, para o consumidor automatizado.
# Caminho exibido pela regra de RF-59(d) (sem --null); motivo mascarado pelo
# valor, como a linha de stderr (QA-P2-02).
_dbx_cmd_sync_relatorio_itens() {
  local forma=$1 acao=enviado indice valor tam texto
  [[ ${sentido:-} == 'receber' ]] && acao=recebido
  for indice in "${!DBX_CMD_SYNC_OK_CAMINHOS[@]}"; do
    valor=${DBX_CMD_SYNC_OK_CAMINHOS[indice]}
    tam=${DBX_CMD_SYNC_OK_TAMANHOS[indice]}
    if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
      _dbx_cmd_sync_exibir "$valor"
      valor=$DBX_CMD_SYNC_EXIBIDO
    fi
    if [[ $forma == 'estruturado' ]]; then
      dbx_output_campo "${acao}_caminho" "$valor"
      dbx_output_campo "${acao}_tamanho" "$tam"
      continue
    fi
    dbx_output_tamanho_humano "$tam" texto
    dbx_output_campo "$acao" "$valor${texto:+ ($texto)}"
  done
  # RF-214(e): o arquivo apagado no lugar da pasta, com o motivo.
  for indice in "${!DBX_CMD_SYNC_APAGADOS_PASTA[@]}"; do
    valor=${DBX_CMD_SYNC_APAGADOS_PASTA[indice]}
    if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
      _dbx_cmd_sync_exibir "$valor"
      valor=$DBX_CMD_SYNC_EXIBIDO
    fi
    if [[ $forma == 'estruturado' ]]; then
      dbx_output_campo apagado_caminho "$valor"
      dbx_output_campo apagado_motivo 'arquivo no lugar da pasta'
    else
      dbx_output_campo apagado "$valor (arquivo no lugar da pasta)"
    fi
  done
  [[ $forma == 'legivel' ]] || return 0
  for indice in "${!DBX_CMD_SYNC_FALHAS_CAMINHOS[@]}"; do
    valor=${DBX_CMD_SYNC_FALHAS_CAMINHOS[indice]}
    if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
      _dbx_cmd_sync_exibir "$valor"
      valor=$DBX_CMD_SYNC_EXIBIDO
    fi
    dbx_output_tamanho_humano "${DBX_CMD_SYNC_FALHAS_TAMANHOS[indice]-}" texto
    dbx_output_mascarar_segredos "${DBX_CMD_SYNC_FALHAS_MOTIVOS[indice]-}"
    dbx_output_campo falha "$valor${texto:+ ($texto)}: ${DBX_CMD_SYNC_FALHAS_CLASSES[indice]} $DBX_OUTPUT_MASCARADO"
  done
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
  # shellcheck source=lib/lote.sh
  . "$DBX_CLI_RAIZ/lib/lote.sh"
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

# ---------------------------------------------------------------------------
# Paralelismo controlado das transferencias (fase 9, F-09; RF-133 a RF-135)
# ---------------------------------------------------------------------------
#
# SO AS TRANSFERENCIAS DE ARQUIVO DO PLANO (envio e recebimento) rodam em
# processos auxiliares. A listagem (`list_folder`, `continue`) e a confirmacao
# de exclusao acontecem ANTES do plano, no processo principal, e nunca
# concorrem com transferencia (RES-11, RNF-21). Exclusoes, memoria, cursor,
# trava, saida e resumo ficam no principal (RF-135(a)).
#
# CONTRATO DO AUXILIAR: executa UM item (`_dbx_cmd_sync_enviar` ou
# `_dbx_cmd_sync_receber`) e devolve o resultado num arquivo da area do ciclo,
# escrito por inteiro e renomeado (a existencia do arquivo e o "terminei"). Ele
# NAO chama nada de `lib/state`, nao imprime e nao toca em trava, cursor,
# memoria nem registro de retomada (o `sync` nunca liga a retomada, RF-102);
# a auditoria estatica de `tests/integracao/paralelo_test.sh` confere isso.
#
# SAIDA EM ORDEM DO PLANO (DIV-257): o principal descarrega o resultado de
# cada item na ORDEM DO PLANO, so quando o item e todos os anteriores
# terminaram; as linhas de falha e o progresso saem do principal, iguais as de
# N=1. `429` nao reduz N (DIV-258): cada auxiliar respeita `Retry-After` pela
# retentativa de `lib/http`, e a contagem entra no resumo de `--debug`.

DBX_CMD_SYNC_PARALELO=1
DBX_CMD_SYNC_PARALELO_ORIGEM='padrao'
DBX_CMD_SYNC_LIMITES_429=0
# Pids dos auxiliares ainda nao descarregados (um por indice do plano).
_DBX_CMD_SYNC_AUX_PIDS=()

# _dbx_cmd_sync_paralelo_resolver <tem_opcao> <opcao_como_digitada> <valor>
#
# RF-133(b)(c): a opcao vence, e presente a variavel NAO e lida; sem opcao, a
# variavel presente e invalida (inclusive vazia) e uso invalido nomeando-a.
# Quando outro comando chama o `sync` (CHAMADOR), a variavel e ignorada: o N
# chega como opcao, ja resolvido pelo chamador (RF-176). Resultado em DBX_CMD_SYNC_PARALELO e DBX_CMD_SYNC_PARALELO_ORIGEM;
# o motivo da recusa, em DBX_CLI_MOTIVO.
_dbx_cmd_sync_paralelo_resolver() {
  local tem_opcao=$1 nome_opcao=$2 valor=${3-}
  DBX_CMD_SYNC_PARALELO=1
  DBX_CMD_SYNC_PARALELO_ORIGEM='padrao'
  # RF-175/RF-176: com CHAMADOR (`upload`/`download` de pasta) o N chega ja
  # resolvido, como opcao; a variavel nao e relida aqui.
  if [[ $tem_opcao == 'sim' || -z ${DBX_CMD_SYNC_CHAMADOR:-} ]]; then
    dbx_cmd_paralelo "$tem_opcao" "$nome_opcao" "$valor" || return $?
    DBX_CMD_SYNC_PARALELO=$DBX_CMD_PARALELO
    # shellcheck disable=SC2034  # canal publico, lido pelos testes e pelo debug
    DBX_CMD_SYNC_PARALELO_ORIGEM=$DBX_CMD_PARALELO_ORIGEM
  fi
  # RF-162: campo extra do resumo de --debug (a lib nao conhece o comando).
  ((DBX_CMD_SYNC_PARALELO > 1)) && dbx_debug_resumo_campo paralelo "$DBX_CMD_SYNC_PARALELO"
  return 0
}

DBX_CMD_SYNC_BLOCO=${DBX_CLI_BLOCO_PADRAO:-50000}
DBX_CMD_SYNC_BLOCO_ORIGEM='padrao'

# _dbx_cmd_sync_bloco_resolver <tem_opcao> <opcao_como_digitada> <valor>
#
# RF-186/RF-175: como o resolvedor de `--paralelo`. Quando outro comando chama o
# `sync` (CHAMADOR), a variavel e ignorada: o N chega como opcao, ja resolvido
# pelo chamador. Resultado em DBX_CMD_SYNC_BLOCO e DBX_CMD_SYNC_BLOCO_ORIGEM.
_dbx_cmd_sync_bloco_resolver() {
  local tem_opcao=$1 nome_opcao=$2 valor=${3-}
  DBX_CMD_SYNC_BLOCO=${DBX_CLI_BLOCO_PADRAO:-50000}
  DBX_CMD_SYNC_BLOCO_ORIGEM='padrao'
  if [[ $tem_opcao == 'sim' || -z ${DBX_CMD_SYNC_CHAMADOR:-} ]]; then
    dbx_cmd_bloco "$tem_opcao" "$nome_opcao" "$valor" || return $?
    DBX_CMD_SYNC_BLOCO=$DBX_CMD_BLOCO
    # shellcheck disable=SC2034  # canal publico, lido pelos testes e pelo resumo
    DBX_CMD_SYNC_BLOCO_ORIGEM=$DBX_CMD_BLOCO_ORIGEM
  fi
  return 0
}

# _dbx_cmd_sync_banda_por_transferencia <taxa_total> <n> — DIV-261: a taxa
# dada e o teto TOTAL, dividido por N, e cada transferencia leva a sua parte.
# A parte nunca fica abaixo do piso de `dbx_cmd_limite_banda` (2 x a velocidade
# minima efetiva): abaixo dele o corte de RNF-30 abortaria a transferencia.
_dbx_cmd_sync_banda_por_transferencia() {
  local total=$1 n=$2 parte piso
  piso=$((2 * ${DBX_HTTP_EFETIVO[DBX_HTTP_VELOCIDADE_MINIMA_BPS]:-1024}))
  parte=$((total / n))
  ((parte < piso)) && parte=$piso
  dbx_http_limite_banda "$parte"
}

# _dbx_cmd_sync_aux_item <resultado> <sentido> <caminho> <alvo> <rev>
#
# Corpo do processo auxiliar (roda em subshell, em segundo plano). Devolve em
# <resultado> quatro linhas: status (0 ou 1), classe da falha, resumo da falha
# (so o texto curto saneado de RF-59(c)) e quantos `429` ele observou.
_dbx_cmd_sync_aux_item() {
  local resultado=$1 sentido=$2 caminho=$3 alvo=$4 rev=$5 canal=${6-} posicao=${7-}
  local antes=${DBX_HTTP_REQUISICOES:-0} antes_429=${DBX_HTTP_LIMITES_429:-0}
  local status=0 tam_prg=''
  # DIV-290: o avanco vai ao principal por arquivo de status; o auxiliar nao escreve em stderr.
  if [[ -n $canal ]]; then
    dbx_progress_canal_definir "$canal"
    if [[ $sentido == 'enviar' ]]; then
      _dbx_cmd_sync_prg_iniciar "$posicao" "$total_ops" enviando "$caminho" "$raiz_local/$caminho"
    else
      _dbx_cmd_sync_prg_iniciar "$posicao" "$total_ops" baixando "$caminho" '' "${mapa_tam_remoto[$caminho]:-}"
    fi
  fi
  if [[ $sentido == 'enviar' ]]; then
    _dbx_cmd_sync_enviar "$raiz_local/$caminho" "$remoto/$alvo" "$rev" "$caminho" || status=1
  else
    _dbx_cmd_sync_receber "$remoto/$caminho" "$raiz_local" "$alvo" || status=1
  fi
  if [[ -n $canal ]]; then
    if [[ $status -ne 0 ]]; then
      dbx_progress_arquivo_falhar
    else
      if [[ $sentido != 'enviar' && -f $raiz_local/$alvo ]]; then dbx_progress_tamanho_de "$raiz_local/$alvo" tam_prg || tam_prg=''; fi
      dbx_progress_arquivo_concluir "$tam_prg"
    fi
  fi
  DBX_CMD_SYNC_RESUMO_FALHA=''
  [[ $status -eq 0 ]] || _dbx_cmd_sync_resumo_da_falha "$antes"
  printf '%s\n%s\n%s\n%s\n' "$status" "${DBX_CMD_SYNC_FALHA_CLASSE:-}" \
    "$DBX_CMD_SYNC_RESUMO_FALHA" "$((${DBX_HTTP_LIMITES_429:-0} - antes_429))" >"$resultado.parte" &&
    mv -f -- "$resultado.parte" "$resultado"
}

# _dbx_cmd_sync_aux_encerrar — acao de `lib/tmp`, em todo termino do principal,
# inclusive por sinal (RF-134(c)): derruba o grupo de cada auxiliar vivo e espera
# que cada um limpe o que e seu (o `.part` do recebimento esta no registro de
# `lib/tmp` dele). O que resistir 5 s leva SIGKILL.
_dbx_cmd_sync_aux_encerrar() {
  local pid indice vivo
  for pid in ${_DBX_CMD_SYNC_AUX_PIDS[@]+"${_DBX_CMD_SYNC_AUX_PIDS[@]}"}; do
    [[ -n $pid ]] || continue
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM -- "$pid" 2>/dev/null || :
  done
  for ((indice = 0; indice < 50; indice++)); do
    vivo='nao'
    for pid in ${_DBX_CMD_SYNC_AUX_PIDS[@]+"${_DBX_CMD_SYNC_AUX_PIDS[@]}"}; do
      [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && vivo='sim'
    done
    [[ $vivo == 'sim' ]] || break
    sleep 0.1
  done
  for pid in ${_DBX_CMD_SYNC_AUX_PIDS[@]+"${_DBX_CMD_SYNC_AUX_PIDS[@]}"}; do
    [[ -n $pid ]] || continue
    kill -KILL -- "-$pid" 2>/dev/null || kill -KILL -- "$pid" 2>/dev/null || :
  done
  # O membro do grupo que recebeu o SIGKILL ainda aparece por um instante; sair
  # antes dele deixava processo vivo apos o termino (mesma correcao de
  # `_dbx_transfer_par_encerrar`). Espera o grupo sumir, ate 1 s.
  for ((indice = 0; indice < 20; indice++)); do
    vivo='nao'
    for pid in ${_DBX_CMD_SYNC_AUX_PIDS[@]+"${_DBX_CMD_SYNC_AUX_PIDS[@]}"}; do
      [[ -n $pid ]] && kill -0 -- "-$pid" 2>/dev/null && vivo='sim'
    done
    [[ $vivo == 'sim' ]] || break
    sleep 0.05
  done
  _DBX_CMD_SYNC_AUX_PIDS=()
}

# _dbx_cmd_sync_transferir_paralelo — executa DBX_SYNC_TRANSFERIR com ate
# `paralelo` auxiliares. Variaveis do executor lidas e atualizadas por escopo
# dinamico: area, paralelo, sentido, raiz_local, remoto, mapa_remoto, mapa_revs,
# total_ops, op_atual, enviados, recebidos, falhas.
_dbx_cmd_sync_transferir_paralelo() {
  local total=${#DBX_SYNC_TRANSFERIR[@]} lancados=0 descarregados=0 vivos indice pid
  local caminho alvo rev antes status classe resumo limites resultado acao_id=''
  local -a itens=(${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}) pids=()
  local pasta="$area/paralelo" base_op=$op_atual canal='' tam_blc=''
  # A pasta fica na area do ciclo (lib/tmp a remove em todo termino).
  mkdir -m 0700 -- "$pasta" 2>/dev/null || :
  # RF-143: bloco de linhas, uma por arquivo ativo; so com progresso ativo.
  dbx_progress_bloco_iniciar "$pasta"
  _DBX_CMD_SYNC_AUX_PIDS=()
  dbx_tmp_acao_registrar _dbx_cmd_sync_aux_encerrar
  acao_id=$DBX_TMP_ID
  # Controle de tarefas so enquanto lanca: cada auxiliar nasce em grupo proprio,
  # o que permite derruba-lo inteiro (subshell, curl) e o isola do SIGINT do
  # terminal, que o principal trata e propaga (RF-134(c)).
  set -m
  while ((descarregados < total)); do
    # Lanca ate encher as vagas, na ordem do plano.
    vivos=0
    for pid in ${pids[@]+"${pids[@]}"}; do
      [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && vivos=$((vivos + 1))
    done
    while ((lancados < total && vivos < paralelo)); do
      caminho=${itens[lancados]}
      if dbx_progress_bloco_ativo; then
        tam_blc=''
        if [[ $sentido == 'enviar' ]]; then
          if [[ -f $raiz_local/$caminho ]]; then dbx_progress_tamanho_de "$raiz_local/$caminho" tam_blc || tam_blc=''; fi
          dbx_progress_bloco_abrir "$lancados" "$((base_op + lancados + 1))" "$total_ops" enviando "$caminho" "$tam_blc"
        else
          dbx_progress_bloco_abrir "$lancados" "$((base_op + lancados + 1))" "$total_ops" baixando "$caminho" "${mapa_tam_remoto[$caminho]:-}"
        fi
        canal="$pasta/st.$lancados"
      else
        canal=''
      fi
      # RF-137: pequeno ja resolvido pelo lote nao vai a auxiliar; o resultado
      # entra na fila de descarga na mesma forma e na mesma ordem.
      if [[ $sentido == 'enviar' ]] && _dbx_cmd_sync_lote_resolvido "$caminho"; then
        printf '%s\n%s\n%s\n0\n' "$_DBX_CMD_SYNC_LOTE_ITEM_STATUS" "$DBX_CMD_SYNC_FALHA_CLASSE" \
          "$DBX_CMD_SYNC_RESUMO_FALHA" >"$pasta/$lancados"
        pids[lancados]=''
        lancados=$((lancados + 1))
        continue
      fi
      alvo=${DBX_SYNC_ALVO[$caminho]:-$caminho}
      rev=''
      if [[ $sentido == 'enviar' && -n ${mapa_remoto[$alvo]+definido} ]]; then
        rev=${mapa_revs[$alvo]:-}
      fi
      # RF-158: com --debug o auxiliar grava as linhas `debug:` em arquivo do item
      # (canal 0700); o principal as descarrega na ordem do plano.
      local destino_dbg=''
      [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] && destino_dbg="$pasta/dbg.$lancados"
      DBX_DEBUG_DESTINO=$destino_dbg _dbx_cmd_sync_aux_item "$pasta/$lancados" "$sentido" "$caminho" "$alvo" "$rev" \
        "$canal" "$((base_op + lancados + 1))" </dev/null >/dev/null 2>&1 &
      pids[lancados]=$!
      _DBX_CMD_SYNC_AUX_PIDS[lancados]=$!
      lancados=$((lancados + 1))
      vivos=$((vivos + 1))
    done
    # Descarrega, em ordem, o que ja terminou.
    while ((descarregados < total)); do
      resultado="$pasta/$descarregados"
      if [[ ! -e $resultado ]]; then
        # Sem resultado: o auxiliar ainda corre, ou morreu sem entrega (por
        # exemplo SIGKILL externo), caso em que o item e falha local.
        pid=${pids[descarregados]-}
        if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
          break
        fi
        [[ -n $pid ]] || break
        sleep 0.05
        [[ -e $resultado ]] || printf '1\nnao_concluida\nfalha local\n0\n' >"$resultado"
      fi
      status=1 classe='' resumo='' limites=0
      {
        IFS= read -r status
        IFS= read -r classe
        IFS= read -r resumo
        IFS= read -r limites
      } <"$resultado"
      [[ $limites =~ ^[0-9]{1,9}$ ]] || limites=0
      DBX_CMD_SYNC_LIMITES_429=$((DBX_CMD_SYNC_LIMITES_429 + limites))
      dbx_debug_somar_429 "$limites"
      caminho=${itens[descarregados]}
      if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' && -s $pasta/dbg.$descarregados ]]; then
        dbx_progress_bloco_pausar
        dbx_debug_descarregar "$pasta/dbg.$descarregados"
      fi
      op_atual=$((op_atual + 1))
      if dbx_progress_bloco_ativo; then
        dbx_progress_bloco_fechar "$descarregados" "$status"
      elif [[ $sentido == 'enviar' ]]; then
        dbx_progress_etapa "$op_atual" "$total_ops" 'enviando' "$caminho"
      else
        dbx_progress_etapa "$op_atual" "$total_ops" 'recebendo' "$caminho"
      fi
      if [[ $status == '0' ]]; then
        if [[ $sentido == 'enviar' ]]; then enviados=$((enviados + 1)); else recebidos=$((recebidos + 1)); fi
        _dbx_cmd_sync_concluido "$caminho"
      else
        falhas=$((falhas + 1))
        DBX_CMD_SYNC_FALHA_CLASSE=${classe:-erro_remoto}
        DBX_CMD_SYNC_RESUMO_FALHA=${resumo:-falha local}
        dbx_progress_bloco_pausar
        _dbx_cmd_sync_falha_emitir "$caminho"
        _dbx_cmd_sync_falha_do_plano_incremental
      fi
      _DBX_CMD_SYNC_AUX_PIDS[descarregados]=''
      rm -f -- "$resultado"
      descarregados=$((descarregados + 1))
    done
    ((descarregados < total)) || break
    if dbx_progress_bloco_ativo; then
      dbx_progress_bloco_tick
      sleep 0.2
    else
      # So os VIVOS ainda nao descarregados: a descarga e em ordem, e um filho
      # posterior ja terminado so sai depois do primeiro; passa-lo faria o
      # aguardo voltar de imediato a cada volta (laco ocupado ate o primeiro
      # terminar). Com todos mortos a lista fica vazia e o aguardo retorna.
      local -a _vp=()
      local _pv
      for _pv in ${pids[@]+"${pids[@]:descarregados:lancados-descarregados}"}; do
        [[ -n $_pv ]] && kill -0 "$_pv" 2>/dev/null && _vp+=("$_pv")
      done
      dbx_par_aguardar_algum ${_vp[@]+"${_vp[@]}"}
    fi
  done
  dbx_progress_bloco_encerrar
  wait 2>/dev/null || :
  dbx_disp_emitir_aviso_pendente
  set +m
  _DBX_CMD_SYNC_AUX_PIDS=()
  dbx_tmp_acao_cancelar "$acao_id"
}

# ---------------------------------------------------------------------------
# Envio em lote de arquivos pequenos (fase 9, F-08; RF-137)
# ---------------------------------------------------------------------------
#
# No `--enviar`, os arquivos do plano ate o limiar (`DBX_TRANSFER_LIMIAR_LOTE`,
# DIV-256) que forem 2 ou mais (DIV-272) saem em tres etapas, ANTES do laco do
# plano: (1) `upload_session/start` com os bytes e `close=true`, um por arquivo,
# nos auxiliares do F-09 quando ha `--paralelo` (DIV-264); (2) `finish_batch_v2`
# no processo principal, em serie, em grupos de ate 250 (DIV-270); (3) o laco do
# plano consome o resultado de cada pequeno NA ORDEM DO PLANO (DIV-257,
# DIV-274), com o mesmo progresso, contagem e linha de falha do envio unitario.
# Arquivo ja igual nunca esta no plano (RF-137(e)). O cache e o resumo local,
# gravado no planejamento (DIV-271); nenhum estado de lote entre execucoes
# (DIV-263): interrompido antes do `finish`, as sessoes abandonadas nao tem
# efeito e o proximo `sync` reenvia. Os arquivos de resultado dos auxiliares
# ficam na area do ciclo, que `lib/tmp` remove em todo termino.
declare -gA _DBX_CMD_SYNC_LOTE_POS=()
declare -ga _DBX_CMD_SYNC_LOTE_ITENS=() _DBX_CMD_SYNC_LOTE_STATUS=() \
  _DBX_CMD_SYNC_LOTE_CLASSE=() _DBX_CMD_SYNC_LOTE_RESUMO=() \
  _DBX_CMD_SYNC_LOTE_SESSAO=() _DBX_CMD_SYNC_LOTE_DESLOC=()
_DBX_CMD_SYNC_LOTE_ITEM_STATUS=0

# _dbx_cmd_sync_aux_iniciar <resultado> <caminho> — `start` de UM pequeno; roda
# no principal (N=1) ou em auxiliar. Devolve em <resultado> seis linhas: status,
# classe, resumo, `429` observados, sessao e deslocamento. Como o auxiliar do
# envio unitario, nao toca em `lib/state`, trava, cursor nem saida.
_dbx_cmd_sync_aux_iniciar() {
  local resultado=$1 caminho=$2
  local antes=${DBX_HTTP_REQUISICOES:-0} antes_429=${DBX_HTTP_LIMITES_429:-0}
  local status=0 classe=''
  dbx_transfer_iniciar_pequeno "$raiz_local/$caminho" "${mapa_local[$caminho]:-}" >/dev/null 2>&1 || {
    status=1
    classe=${DBX_TRANSFER_CLASSE:-erro_remoto}
  }
  DBX_CMD_SYNC_RESUMO_FALHA=''
  [[ $status -eq 0 ]] || _dbx_cmd_sync_resumo_da_falha "$antes"
  printf '%s\n%s\n%s\n%s\n%s\n%s\n' "$status" "$classe" "$DBX_CMD_SYNC_RESUMO_FALHA" \
    "$((${DBX_HTTP_LIMITES_429:-0} - antes_429))" "${DBX_TRANSFER_SESSAO:-}" \
    "${DBX_TRANSFER_DESLOCAMENTO:-0}" >"$resultado.parte" &&
    mv -f -- "$resultado.parte" "$resultado"
}

# _dbx_cmd_sync_lote_iniciar — etapa (1): `start` de cada pequeno, com ate
# `paralelo` simultaneos, e leitura dos resultados na ordem. Variaveis do
# executor (escopo dinamico): area, paralelo, raiz_local.
_dbx_cmd_sync_lote_iniciar() {
  local total=${#_DBX_CMD_SYNC_LOTE_ITENS[@]} k lancados=0 vivos pid
  local pasta="$area/lote" acao_id='' status classe resumo limites sessao desloc
  local -a pids=()
  mkdir -p -- "$pasta" 2>/dev/null || :
  if ((paralelo > 1)); then
    _DBX_CMD_SYNC_AUX_PIDS=()
    dbx_tmp_acao_registrar _dbx_cmd_sync_aux_encerrar
    acao_id=$DBX_TMP_ID
    set -m
    while :; do
      vivos=0
      local _vp=()
      for pid in ${pids[@]+"${pids[@]}"}; do
        kill -0 "$pid" 2>/dev/null && vivos=$((vivos + 1)) && _vp+=("$pid")
      done
      pids=(${_vp[@]+"${_vp[@]}"})
      while ((lancados < total && vivos < paralelo)); do
        local destino_dbg=''
        [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] && destino_dbg="$pasta/dbg.$lancados"
        DBX_DEBUG_DESTINO=$destino_dbg _dbx_cmd_sync_aux_iniciar "$pasta/$lancados" "${_DBX_CMD_SYNC_LOTE_ITENS[lancados]}" \
          </dev/null >/dev/null 2>&1 &
        pids+=("$!")
        _DBX_CMD_SYNC_AUX_PIDS[lancados]=$!
        lancados=$((lancados + 1))
        vivos=$((vivos + 1))
      done
      ((vivos > 0)) || break
      dbx_par_aguardar_algum ${pids[@]+"${pids[@]}"}
    done
    wait 2>/dev/null || :
    set +m
    _DBX_CMD_SYNC_AUX_PIDS=()
    dbx_tmp_acao_cancelar "$acao_id"
    dbx_disp_emitir_aviso_pendente
    # RF-158: linhas dos auxiliares do lote, na ordem do plano.
    for ((k = 0; k < total; k++)); do
      dbx_debug_descarregar "$pasta/dbg.$k"
    done
  else
    for ((k = 0; k < total; k++)); do
      _dbx_cmd_sync_aux_iniciar "$pasta/$k" "${_DBX_CMD_SYNC_LOTE_ITENS[k]}" </dev/null
    done
  fi
  for ((k = 0; k < total; k++)); do
    status=1 classe='nao_concluida' resumo='falha local' limites=0 sessao='' desloc=0
    if [[ -e $pasta/$k ]]; then
      {
        IFS= read -r status
        IFS= read -r classe
        IFS= read -r resumo
        IFS= read -r limites
        IFS= read -r sessao
        IFS= read -r desloc
      } <"$pasta/$k"
    fi
    [[ $limites =~ ^[0-9]{1,9}$ ]] || limites=0
    [[ $desloc =~ ^[0-9]{1,18}$ ]] || desloc=0
    DBX_CMD_SYNC_LIMITES_429=$((DBX_CMD_SYNC_LIMITES_429 + limites))
    dbx_debug_somar_429 "$limites"
    if [[ $status == '0' && -n $sessao ]]; then
      _DBX_CMD_SYNC_LOTE_STATUS[k]=0
    else
      _DBX_CMD_SYNC_LOTE_STATUS[k]=1
      _DBX_CMD_SYNC_LOTE_CLASSE[k]=${classe:-erro_remoto}
      _DBX_CMD_SYNC_LOTE_RESUMO[k]=${resumo:-falha local}
    fi
    _DBX_CMD_SYNC_LOTE_SESSAO[k]=$sessao
    _DBX_CMD_SYNC_LOTE_DESLOC[k]=$desloc
  done
}

# _dbx_cmd_sync_lote_concluir — etapa (2): `finish_batch_v2` das sessoes abertas,
# no principal e em serie, em grupos de DBX_LOTE_ENVIO_MAXIMO. Falha de uma
# entrada e falha so daquele item (RF-137(c)). Variaveis do executor: remoto,
# raiz_local, mapa_remoto, mapa_revs.
_dbx_cmd_sync_lote_concluir() {
  local k j n=0 ini fim caminho alvo rev
  local -a mapa_j=()
  DBX_LOTE_SESSOES=() DBX_LOTE_DESLOCAMENTOS=() DBX_LOTE_COMMITS=()
  DBX_LOTE_ENVIO_RESULTADO=() DBX_LOTE_ENVIO_CLASSE=() DBX_LOTE_ENVIO_MOTIVO=()
  DBX_LOTE_ENVIO_HASH=() DBX_LOTE_ENVIO_HASH_DEVOLVIDO=()
  for k in ${_DBX_CMD_SYNC_LOTE_ITENS[@]+"${!_DBX_CMD_SYNC_LOTE_ITENS[@]}"}; do
    [[ ${_DBX_CMD_SYNC_LOTE_STATUS[k]} == 0 ]] || continue
    caminho=${_DBX_CMD_SYNC_LOTE_ITENS[k]}
    alvo=${DBX_SYNC_ALVO[$caminho]:-$caminho}
    rev=''
    [[ -n ${mapa_remoto[$alvo]+definido} ]] && rev=${mapa_revs[$alvo]:-}
    dbx_transfer_objeto_de_publicacao "$remoto/$alvo" add "$rev" "$raiz_local/$caminho" true
    DBX_LOTE_SESSOES[n]=${_DBX_CMD_SYNC_LOTE_SESSAO[k]}
    DBX_LOTE_DESLOCAMENTOS[n]=${_DBX_CMD_SYNC_LOTE_DESLOC[k]}
    DBX_LOTE_COMMITS[n]=$DBX_TRANSFER_COMMIT
    mapa_j[n]=$k
    n=$((n + 1))
  done
  for ((ini = 0; ini < n; ini += DBX_LOTE_ENVIO_MAXIMO)); do
    fim=$((ini + DBX_LOTE_ENVIO_MAXIMO))
    ((fim > n)) && fim=$n
    dbx_lote_concluir_envio "$ini" "$fim"
  done
  for ((j = 0; j < n; j++)); do
    k=${mapa_j[j]}
    if [[ ${DBX_LOTE_ENVIO_RESULTADO[j]:-} == 'ok' ]]; then
      # DIV-278: a mesma conferencia do envio unitario, com o resumo local do
      # planejamento. Divergente falha SO este item, com `integridade` (11).
      caminho=${_DBX_CMD_SYNC_LOTE_ITENS[k]}
      if [[ ${DBX_LOTE_ENVIO_HASH_DEVOLVIDO[j]:-nao} == 'sim' ]]; then
        dbx_transfer_conferir_resumo "${mapa_local[$caminho]:-}" "${DBX_LOTE_ENVIO_HASH[j]:-}"
      else
        dbx_transfer_conferir_resumo "${mapa_local[$caminho]:-}"
      fi || {
        DBX_LOTE_ENVIO_RESULTADO[j]='falhou'
        DBX_LOTE_ENVIO_CLASSE[j]=${DBX_TRANSFER_CLASSE:-integridade}
        DBX_LOTE_ENVIO_MOTIVO[j]=$DBX_TRANSFER_MOTIVO
      }
    fi
    if [[ ${DBX_LOTE_ENVIO_RESULTADO[j]:-} == 'ok' ]]; then
      _DBX_CMD_SYNC_LOTE_STATUS[k]=0
      continue
    fi
    _DBX_CMD_SYNC_LOTE_STATUS[k]=1
    _DBX_CMD_SYNC_LOTE_CLASSE[k]=${DBX_LOTE_ENVIO_CLASSE[j]:-erro_remoto}
    dbx_errors_redigir "${DBX_LOTE_ENVIO_MOTIVO[j]:-item nao confirmado pelo lote}" >/dev/null
    _DBX_CMD_SYNC_LOTE_RESUMO[k]=${DBX_ERRORS_REDIGIDO:0:120}
  done
  DBX_LOTE_SESSOES=() DBX_LOTE_COMMITS=() DBX_LOTE_ENVIO_HASH=() DBX_LOTE_ENVIO_HASH_DEVOLVIDO=()
}

# _dbx_cmd_sync_lote_envio — etapas (1) e (2) para os pequenos do plano. So no
# `--enviar` real e com 2 ou mais pequenos (DIV-272); do contrario nao faz nada e
# o plano segue pelo caminho unitario. Variaveis do executor: sentido, raiz_local.
_dbx_cmd_sync_lote_envio() {
  local caminho k
  _DBX_CMD_SYNC_LOTE_POS=()
  _DBX_CMD_SYNC_LOTE_ITENS=() _DBX_CMD_SYNC_LOTE_STATUS=() _DBX_CMD_SYNC_LOTE_CLASSE=()
  _DBX_CMD_SYNC_LOTE_RESUMO=() _DBX_CMD_SYNC_LOTE_SESSAO=() _DBX_CMD_SYNC_LOTE_DESLOC=()
  [[ $sentido == 'enviar' && ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || return 0
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    dbx_transfer_tamanho_de_arquivo "$raiz_local/$caminho" || continue
    dbx_transfer_pequeno_para_lote "$DBX_TRANSFER_TAMANHO" && _DBX_CMD_SYNC_LOTE_ITENS+=("$caminho")
  done
  if ((${#_DBX_CMD_SYNC_LOTE_ITENS[@]} < 2)); then
    _DBX_CMD_SYNC_LOTE_ITENS=()
    return 0
  fi
  # RF-159(a): a modalidade `lote` de cada pequeno, antes da primeira chamada de
  # conteudo (a do `start`).
  if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]]; then
    for caminho in ${_DBX_CMD_SYNC_LOTE_ITENS[@]+"${_DBX_CMD_SYNC_LOTE_ITENS[@]}"}; do
      dbx_transfer_tamanho_de_arquivo "$raiz_local/$caminho" || :
      dbx_debug_linha upload modalidade=lote arquivo="$caminho" bytes="$DBX_TRANSFER_TAMANHO"
    done
  fi
  _dbx_cmd_sync_lote_iniciar
  _dbx_cmd_sync_lote_concluir
  for k in ${_DBX_CMD_SYNC_LOTE_ITENS[@]+"${!_DBX_CMD_SYNC_LOTE_ITENS[@]}"}; do
    _DBX_CMD_SYNC_LOTE_POS[${_DBX_CMD_SYNC_LOTE_ITENS[k]}]=$k
    # RF-159(d): resultado final de cada pequeno, na ordem do plano.
    if [[ ${_DBX_CMD_SYNC_LOTE_STATUS[k]} == 0 ]]; then
      dbx_debug_linha upload resultado=ok arquivo="${_DBX_CMD_SYNC_LOTE_ITENS[k]}"
    else
      dbx_debug_linha upload resultado=falha arquivo="${_DBX_CMD_SYNC_LOTE_ITENS[k]}" classe="${_DBX_CMD_SYNC_LOTE_CLASSE[k]:-erro_remoto}"
    fi
  done
}

# _dbx_cmd_sync_debug_decisoes — RF-161(a)(b)(c): uma linha `debug: sync
# decisao=...` por item do plano, ANTES de qualquer transferencia (as linhas de
# cada item, dos auxiliares inclusive, saem depois, RF-158(b)). So le o plano:
# nao muda lista, cache nem ordem (RF-163(b)). Variaveis do executor: sentido,
# espelhar, mapa_remoto, mapa_local. Itens filtrados saem em lib/sync
# (`_dbx_sync_contar_filtrado`), no ponto em que o filtro os retira.
_dbx_cmd_sync_debug_decisoes() {
  [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] || return 0
  local caminho alvo motivo
  for caminho in ${DBX_SYNC_IDENTICOS[@]+"${DBX_SYNC_IDENTICOS[@]}"}; do
    dbx_debug_linha sync decisao=pular motivo=content-hash-igual item="$caminho"
  done
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    alvo=${DBX_SYNC_ALVO[$caminho]:-$caminho}
    motivo=ausente-no-destino
    if [[ $sentido == 'enviar' && -n ${mapa_remoto[$alvo]+definido} ]]; then
      motivo=content-hash-diferente
    elif [[ $sentido == 'receber' && -n ${mapa_local[$alvo]+definido} ]]; then
      motivo=content-hash-diferente
    fi
    dbx_debug_linha sync decisao="$sentido" motivo="$motivo" item="$caminho"
  done
  # RF-161(c): o que so existe no destino tambem tem linha (DIV-345).
  for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    if [[ $espelhar != 'sim' ]]; then
      dbx_debug_linha sync decisao=pular motivo=so-no-destino item="$caminho"
    elif _dbx_cmd_sync_protegido "$caminho"; then
      dbx_debug_linha sync decisao=pular motivo=protegido item="$caminho"
    else
      dbx_debug_linha sync decisao=apagar motivo=espelho-apaga-orfao item="$caminho"
    fi
  done
}

# _dbx_cmd_sync_lote_resolvido <caminho> — 0 quando o item foi resolvido pelo
# lote; publica o status (0 ou 1), a classe e o resumo da falha.
_dbx_cmd_sync_lote_resolvido() {
  local k=${_DBX_CMD_SYNC_LOTE_POS[$1]-}
  [[ -n $k ]] || return 1
  DBX_CMD_SYNC_FALHA_CLASSE=''
  DBX_CMD_SYNC_RESUMO_FALHA=''
  _DBX_CMD_SYNC_LOTE_ITEM_STATUS=${_DBX_CMD_SYNC_LOTE_STATUS[k]}
  if [[ $_DBX_CMD_SYNC_LOTE_ITEM_STATUS != 0 ]]; then
    DBX_CMD_SYNC_FALHA_CLASSE=${_DBX_CMD_SYNC_LOTE_CLASSE[k]:-erro_remoto}
    DBX_CMD_SYNC_RESUMO_FALHA=${_DBX_CMD_SYNC_LOTE_RESUMO[k]:-falha local}
  fi
  return 0
}

# _dbx_cmd_sync_falha_do_plano_incremental — RF-111(g), C6: item do plano
# incremental que o servidor nao tem (ou que conflita no caminho) e retrato com
# entrada fantasma: o registro sai, e a execucao seguinte faz a varredura
# completa. So o `--receber`; chamado depois de registrada a falha do item.
_dbx_cmd_sync_falha_do_plano_incremental() {
  [[ $sentido == 'receber' ]] || return 0
  if [[ $DBX_CMD_SYNC_VARREDURA == 'incremental' &&
    ($DBX_CMD_SYNC_FALHA_CLASSE == 'nao_encontrado' || $DBX_CMD_SYNC_FALHA_CLASSE == 'conflito') ]]; then
    dbx_state_cursor_remover
    DBX_CMD_SYNC_CURSOR_GRAVA='nao'
  fi
}

dbx_cmd_sync_executar() {
  _dbx_cmd_sync_carregar_dependencias

  local origem='' destino='' sentido='' espelhar='nao' confirmado='nao' permitir_origem_vazia='nao'
  local tem_origem='nao' tem_destino='nao' forcar='nao' espera=0 opcao_espera='' valor_espera=''
  local tem_limite='nao' opcao_limite='' valor_limite='' opcao
  local tem_paralelo='nao' opcao_paralelo='' valor_paralelo=''
  local tem_bloco='nao' opcao_bloco='' valor_bloco=''
  # RF-118 (fase 7b): cursor de listagem so no `--receber`.
  local sem_cursor='nao' varredura_forcada='nao'
  # RF-161: liga a linha de decisao dos itens filtrados em lib/sync.
  DBX_SYNC_DEBUG_DECISAO='sim'
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
      # RF-133: transferencias simultaneas; o ultimo valor vence, validado
      # depois do laco, antes de qualquer rede ou estado.
      --paralelo | --parallel)
        opcao_paralelo=$1
        shift
        valor_paralelo=${1-}
        tem_paralelo='sim'
        ;;
      # RF-186: arquivos por ciclo; o ultimo valor vence, validado depois do laco.
      --bloco | --batch)
        opcao_bloco=$1
        shift
        valor_bloco=${1-}
        tem_bloco='sim'
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
  # RF-133: antes de qualquer rede ou estado. `paralelo` e o N EFETIVO desta
  # execucao: 1 em simulacao (RF-134(e)) e quando o `sync` e chamado por outro
  # comando (`download`/`upload` de pasta repassam o N, RF-176).
  local paralelo=1
  _dbx_cmd_sync_paralelo_resolver "$tem_paralelo" "$opcao_paralelo" "$valor_paralelo" || {
    dbx_cmd_falhar uso_invalido "$DBX_CLI_MOTIVO"
    return $?
  }
  paralelo=$DBX_CMD_SYNC_PARALELO
  # RF-186: mesma regra, antes de rede e estado; o valor so e consumido pelos ciclos (etapa 2).
  _dbx_cmd_sync_bloco_resolver "$tem_bloco" "$opcao_bloco" "$valor_bloco" || {
    dbx_cmd_falhar uso_invalido "$DBX_CLI_MOTIVO"
    return $?
  }
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && paralelo=1
  # DIV-261: o limite de banda e o TETO TOTAL; cada transferencia leva a sua
  # parte, nunca abaixo do piso que evita o corte por velocidade minima.
  if [[ $paralelo -gt 1 && -n $DBX_CMD_LIMITE_BANDA ]]; then
    _dbx_cmd_sync_banda_por_transferencia "$DBX_CMD_LIMITE_BANDA" "$paralelo"
  fi

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

  # RF-132 (fase 8): o `--receber` (e o `download` de pasta, que o executa)
  # trava tambem a raiz local pela identidade fisica, depois da trava do par e
  # antes de qualquer escrita DENTRO dela. A raiz so tem identidade depois de
  # existir; a criacao do diretorio vazio acima e o unico passo anterior (DIV-252).
  if [[ $sentido == 'receber' ]]; then
    dbx_cmd_ciclo_trava_raiz "$raiz_local" || return $?
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

  # RF-48: reconhecimento obrigatorio na primeira execucao COM espelhamento.
  if [[ $espelhar == 'sim' && $DBX_STATE_VISTO != 'sim' && $confirmado != 'sim' &&
    ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      'primeira execucao com --espelhar sobre este par de raizes: rode antes com --dry-run para ver o plano, ou confirme com --confirmar'
    return $?
  fi

  local area registros_locais registros_remotos
  DBX_CMD_SYNC_FALHAS_CAMINHOS=()
  DBX_CMD_SYNC_FALHAS_CLASSES=()
  DBX_CMD_SYNC_FALHAS_MOTIVOS=()
  DBX_CMD_SYNC_FALHAS_TAMANHOS=()
  DBX_CMD_SYNC_OK_CAMINHOS=()
  DBX_CMD_SYNC_OK_TAMANHOS=()
  DBX_CMD_SYNC_APAGADOS_PASTA=()
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

  # RF-110/F-14: o cursor e preparado ANTES da coleta, porque decide o modo.
  _dbx_cmd_sync_cursor_zerar
  if [[ $sentido == 'receber' && ${DBX_CMD_SYNC_CHAMADOR:-} != 'download' ]]; then
    DBX_CMD_SYNC_CURSOR_CAMPOS='sim'
    _dbx_cmd_sync_cursor_preparar "$conta" "$local_canonico" "$remoto" "$lado_remoto" "$sem_cursor" \
      "$varredura_forcada" || return $?
  fi

  # F-101 (RF-187/188): varredura completa em ciclos cortados por diretorio.
  # Etapa 3a (RF-192): toda execucao sem cursor valido roda em ciclos, inclusive a
  # que grava cursor e retrato; so o delta com cursor valido segue sem ciclos.
  local modo_ciclos='nao'
  if [[ $DBX_CMD_SYNC_VARREDURA != 'incremental' ]]; then
    modo_ciclos='sim'
  fi
  local dirs_arq="$area/dirs" vazia_global='nao' podadas_dirs=0 total_origem=0 extras_arquivos=0 retidos_total=0
  local so_destino='nao' ciclo ci_ini ci_fim ciclo_i=0 ciclo_falho=0 codigo_parada=0
  local enviados=0 recebidos=0 apagados=0 falhas=0 alvo rev antes
  local omitidos_total=0 fo_total=0 fd_total=0 antes_total=0 depois_total=0 kk
  local -a dirs_v=() cont_v=() ciclos=('0-0') fila_remota=()
  local remoto_fim='nao' formacao_falhou=0
  local pend_ativo='nao' pend_dir='' pend_arquivos=0
  local -a pend_filhos=() pend_chaves=() pend_regs=()
  local -A chaves_dirs=()
  local estado_remoto=0 rodada
  # RF-216: pastas orfas candidatas e contagem (resumo/--json: Tarefa 6)
  local -a pastas_orfas=()
  local -A pastas_vistas=()
  local pastas_apagadas=0 pastas_mantidas=0 pastas_bloqueio='nao' filhos_locais=/dev/null
  # RF-218: contadores de pasta (criadas, falhas) e, em simulacao (RF-217), o
  # plano de pastas do ciclo (`chave<TAB>valor`), as exclusoes de pasta
  # anunciadas e as pastas do destino remoto observadas nesta execucao.
  local pastas_criadas=0 pastas_falhou=0
  local -a plano_pastas=() pastas_apagaria=()
  local -A pastas_destino_vistas=()
  # RF-217(c)(d), so em simulacao: o que esta execucao planejou apagar (arquivos),
  # o que ela observou no destino remoto (`tipo<TAB>relativo`), as pastas ja
  # anunciadas como `apagaria` e a recusa por espaco (nenhum plano de pastas).
  local -A apagar_planejado=() pastas_apagaria_set=()
  local -a observados_destino=()
  local pastas_recusa='nao'
  [[ $sentido == 'receber' ]] && filhos_locais="$area/filhos_locais"
  local -a ordem_remota=()
  # shellcheck disable=SC2034  # preenchido e lido por referencia de nome nas funcoes de lib/sync
  local -A mapa_remoto=() mapa_revs=() mapa_tam_remoto=()
  DBX_CMD_SYNC_LIMITES_429=0
  if [[ $modo_ciclos == 'sim' ]]; then
    # RF-192: o cursor da raiz e pedido ANTES do ciclo 1; o que mudar durante a
    # varredura chega no proximo delta.
    _dbx_cmd_sync_retrato_iniciar "$remoto"
    _dbx_cmd_sync_diretorios_enumerar || return $?
  fi
  # F-103, RF-210(a)(g): no --enviar (e no `upload` de pasta, que chega aqui) a
  # arvore remota inteira e criada uma unica vez, dentro do laco, DEPOIS das
  # recusas do plano do ciclo 1 (origem vazia, espaco) e da simulacao, e antes do
  # primeiro envio. Pastas que falham ficam em `pastas_falhas` (relativo local ->
  # pasta remota que falhou), lido por ciclo.
  local -A pastas_falhas=()
  local pastas_arvore_criada='nao'

    while _dbx_cmd_sync_ciclo_proximo; do
      ciclo_i=$((ciclo_i + 1))
      [[ $modo_ciclos == 'sim' ]] &&
        dbx_progress_mensagem "[sync] ciclo $ciclo_i: diretorios $((ci_ini + 1)) a $ci_fim${so_destino/sim/ (ramo so do destino)}"
      caminhos_locais=() tamanhos=() identidades=() ordem_local=() ordem_remota=()
      mapa_local=() mapa_remoto=() mapa_revs=() mapa_tam_remoto=()
      locais_antes=0 filtrados_local=0 filtrados_remoto=0

  if [[ $sentido == 'receber' && ! -d $raiz_local ]] || [[ $so_destino == 'sim' && $sentido == 'enviar' ]]; then
    # Em simulacao com destino local inexistente, nao ha itens locais
    : >"$registros_locais"
  else
    dbx_progress_mensagem "[sync] analisando arquivos locais em: $raiz_local"
    if [[ $modo_ciclos == 'sim' ]]; then
      dbx_walk_ciclo "$raiz_local" "$dirs_arq" "$ci_ini" "$ci_fim" "$registros_locais" "$filhos_locais" \
        "$([[ $sentido == 'receber' ]] && printf chaves_dirs)" || {
        dbx_cmd_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
        return $?
      }
      # A poda do lado origem local ja foi contada na enumeracao dos diretorios.
      [[ $sentido == 'enviar' ]] && DBX_WALK_PODADAS=()
      if [[ $DBX_WALK_PARCIAL == 'sim' ]]; then
        parcial='sim'
        motivo_parcial="${motivo_parcial}${motivo_parcial:+; }$DBX_WALK_MOTIVO"
      fi
      [[ $sentido == 'receber' ]] && _dbx_cmd_sync_pastas_orfas_locais "$filhos_locais"
    else
      dbx_walk_local "$raiz_local" "$registros_locais" || {
        dbx_cmd_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
        return $?
      }
      parcial=$DBX_WALK_PARCIAL motivo_parcial=$DBX_WALK_MOTIVO
    fi

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
      codigo_parada=$?
        if [[ $modo_ciclos != 'sim' || $ciclo_i -eq 1 ]]; then return "$codigo_parada"; fi
        ciclo_falho=$ciclo_i
        break
    fi
    # RF-81(c): data e tamanho so na origem, e so em arquivo.
    [[ $sentido == 'enviar' ]] && dbx_sync_filtrar_meta caminhos_locais tamanhos identidades
    filtrados_local=$DBX_SYNC_FILTRADOS
    [[ $modo_ciclos == 'sim' && $ciclo_i -eq 1 && $sentido == 'enviar' ]] && filtrados_local=$((filtrados_local + podadas_dirs))
    local indice
    local total_locais=${#caminhos_locais[@]}
    for indice in ${caminhos_locais[@]+"${!caminhos_locais[@]}"}; do
      if _dbx_cmd_sync_resumo_local "$raiz_local" "${caminhos_locais[$indice]}" \
        "${identidades[$indice]}"; then
        ordem_local+=("${caminhos_locais[$indice]}")
        # shellcheck disable=SC2034  # lido por referencia de nome em lib/sync
        mapa_local["${caminhos_locais[$indice]}"]=$DBX_CMD_SYNC_RESUMO
        local nome_seguro=''
        dbx_progress_neutralizar "${caminhos_locais[$indice]}" nome_seguro
        dbx_progress_mensagem "[sync] analisando local ($((indice + 1))/$total_locais): $nome_seguro -> ${DBX_CMD_SYNC_ORIGEM_RESUMO:-ok}"
      else
        # Arquivo ilegivel e travessia parcial: some da origem sem ter sido
        # apagado, e com espelhamento isso viraria exclusao do par no destino.
        falhas_de_resumo=$((falhas_de_resumo + 1))
        parcial='sim'
        # Mesmo motivo do canal de `lib/walk`: uma linha so. Quebra de linha aqui
        # derrubaria o registro do plano inteiro, e justamente na execucao em que
        # ele mais importa.
        motivo_parcial="${motivo_parcial}${motivo_parcial:+; }nao foi possivel calcular o resumo de: ${caminhos_locais[$indice]}"
        local nome_seguro=''
        dbx_progress_neutralizar "${caminhos_locais[$indice]}" nome_seguro
        dbx_progress_mensagem "[sync] analisando local ($((indice + 1))/$total_locais): $nome_seguro -> ${DBX_CMD_SYNC_ORIGEM_RESUMO:-falha na leitura}"
      fi
    done
    dbx_progress_mensagem "[sync] arquivos locais analisados: ${#ordem_local[@]} arquivo(s)"
  fi

      dbx_progress_mensagem "[sync] consultando arquivos remotos em: $remoto"
      if [[ $modo_ciclos == 'sim' ]]; then
        dbx_sync_filtrados_zerar
        estado_remoto=$formacao_falhou
        if [[ $sentido == 'enviar' ]]; then
          dbx_sync_tabela_zerar
          DBX_SYNC_PASTAS_OCUPADAS=()
          for ((kk = ci_ini; kk < ci_fim; kk++)); do
            dbx_sync_listar_diretorio "$remoto" "$remoto${dirs_v[kk]:+/${dirs_v[kk]}}" "$lado_remoto" || estado_remoto=$?
            [[ $estado_remoto -eq 0 ]] || break
          done
          # DIV-394: UM aviso por pasta ocupada, sempre (a mensagem de progresso
          # so sai com -p). Sob `--espelhar` o arquivo homonimo e orfao e sai no
          # plano; os envios para dentro da pasta podem falhar por item neste
          # ciclo (`path/conflict/file`) e completam na execucao seguinte.
          local ocupada
          for ocupada in ${DBX_SYNC_PASTAS_OCUPADAS[@]+"${DBX_SYNC_PASTAS_OCUPADAS[@]}"}; do
            dbx_cmd_avisar "$ocupada e um arquivo na Dropbox, nao uma pasta: tratado como pasta vazia; com --espelhar o arquivo e apagado como orfao e os envios para dentro dela podem falhar nesta execucao e completar na seguinte"
          done
        fi
        if [[ $estado_remoto -eq 0 && $sentido == 'enviar' ]]; then
          _dbx_cmd_sync_ramos_destino_remotos || estado_remoto=$?
          [[ $estado_remoto -eq 0 ]] && _dbx_cmd_sync_pastas_orfas_remotas
        fi
        if [[ $estado_remoto -ne 0 ]]; then
          dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" "${DBX_SYNC_MOTIVO:-enumeracao remota falhou}"
          codigo_parada=$estado_remoto
          if [[ $ciclo_i -eq 1 ]]; then return "$codigo_parada"; fi
          ciclo_falho=$ciclo_i
          break
        fi
        dbx_sync_tabela_emitir "$remoto" "$registros_remotos" "$revs_remotos" "$lado_remoto"
        _dbx_cmd_sync_retrato_acumular
        filtrados_remoto=$DBX_SYNC_FILTRADOS
        dbx_sync_ler_resumos "$registros_remotos" ordem_remota mapa_remoto
        dbx_sync_ler_revs "$revs_remotos" mapa_revs
        # RF-208: o `size` da listagem alimenta o relatorio final, com ou sem -p.
        if [[ $sentido == 'receber' ]]; then
          _dbx_cmd_sync_ler_tamanhos "$registros_remotos" mapa_tam_remoto
        fi
        dbx_progress_mensagem "[sync] arquivos remotos consultados: ${#ordem_remota[@]} arquivo(s)"
        if [[ $sentido == 'enviar' ]]; then
          dbx_sync_planejar ordem_local mapa_local ordem_remota mapa_remoto
        else
          dbx_sync_planejar ordem_remota mapa_remoto ordem_local mapa_local
        fi
        _dbx_cmd_sync_sem_protegidos
        _dbx_cmd_sync_reter_nao_ascii
        # RF-190(b): o ramo so do destino e lido inteiro NO ciclo que o encontra.
      else
  # QA-P3-03: o status e capturado ANTES do teste. Lido dentro de `if ! …`, ele
    # e o da negacao (0), e uma enumeracao que falhou terminava o `sync` com sucesso.
    # Duas rodadas no maximo: a segunda so existe quando a confirmacao de
    # exclusao (RF-114) devolve a execucao a varredura completa.
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
      # DIV-297: o total do recebimento vem do `size` da listagem, sem chamada nova.
      # RF-208: o `size` da listagem alimenta o relatorio final, com ou sem -p.
      if [[ $sentido == 'receber' ]]; then
        _dbx_cmd_sync_ler_tamanhos "$registros_remotos" mapa_tam_remoto
      fi
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
      _dbx_cmd_sync_reter_nao_ascii

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
      fi

  # RF-161(d): a decisao do cursor desta execucao, com o motivo do vocabulario de
  # DBX_CMD_SYNC_CURSOR_MOTIVO; nunca o valor do cursor. `usado` nao tem motivo.
  if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' && $DBX_CMD_SYNC_CURSOR_CAMPOS == 'sim' && $ciclo_i -eq 1 ]]; then
    case ${DBX_CMD_SYNC_CURSOR_MOTIVO:-} in
      '') dbx_debug_linha sync cursor=usado ;;
      desligado) dbx_debug_linha sync cursor=desligado motivo=desligado ;;
      forcada) dbx_debug_linha sync cursor=forcado motivo=forcada ;;
      *) dbx_debug_linha sync cursor=reconstruido motivo="$DBX_CMD_SYNC_CURSOR_MOTIVO" ;;
    esac
  fi

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
  # DIV-378 C: em ciclos, "vazia" e a resposta da sonda anterior ao ciclo 1.
  [[ $modo_ciclos == 'sim' ]] && vazia=$vazia_global
  fo_total=$((fo_total + filtrados_origem))
  fd_total=$((fd_total + filtrados_destino))

  # DIV-91: filtro mal escrito avisa em stderr, sem mudar stdout nem codigo.
  antes_total=$((antes_total + origem_antes))
  depois_total=$((depois_total + origem_depois))
  if [[ $modo_ciclos != 'sim' ]]; then
    dbx_sync_avisos_de_filtro "$origem_antes" "$origem_depois"
    dbx_cmd_avisos_de_filtro
  fi

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
  # Ramo so do destino com arquivo conta como "algo a apagar" (RF-191): sem isso a
  # origem vazia apagaria o conteudo desses ramos sem a recusa.
  if [[ $espelhar == 'sim' && $vazia == 'sim' && $((${#DBX_SYNC_APAGAR[@]} + extras_arquivos + ${#pastas_orfas[@]})) -gt 0 &&
    $permitir_origem_vazia != 'sim' ]]; then
    recusa_origem_vazia='sim'
    pastas_bloqueio='sim'
    a_apagar_recusado=$((${#DBX_SYNC_APAGAR[@]} + extras_arquivos + ${#pastas_orfas[@]}))
    [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && recusaria='origem vazia'
    DBX_SYNC_APAGAR=()
    extras_arquivos=0
  fi

  if dbx_progress_ativo; then
    local total_analisados=$(( ${#DBX_SYNC_TRANSFERIR[@]} + ${#DBX_SYNC_IDENTICOS[@]} + ${#DBX_SYNC_APAGAR[@]} ))
    local idx_analise=0
    local acao_transferir='a enviar'
    [[ $sentido == 'receber' ]] && acao_transferir='a receber'
    dbx_progress_mensagem "[sync] analisando diferencas e comparando origem e destino ($total_analisados arquivo(s) no total)..."

    for caminho in ${DBX_SYNC_IDENTICOS[@]+"${DBX_SYNC_IDENTICOS[@]}"}; do
      idx_analise=$((idx_analise + 1))
      local nome_seguro=''
      dbx_progress_neutralizar "$caminho" nome_seguro
      dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $nome_seguro -> identico (dispensado)"
    done

    for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
      idx_analise=$((idx_analise + 1))
      local tipo_item='novo' par=${DBX_SYNC_ALVO[$caminho]:-$caminho}
      if [[ $sentido == 'enviar' && -n ${mapa_remoto[$par]+definido} ]]; then
        tipo_item='modificado'
      elif [[ $sentido == 'receber' && -n ${mapa_local[$par]+definido} ]]; then
        tipo_item='modificado'
      fi
      local nome_seguro=''
      dbx_progress_neutralizar "$caminho" nome_seguro
      dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $nome_seguro -> $tipo_item ($acao_transferir)"
    done

    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      idx_analise=$((idx_analise + 1))
      if [[ $espelhar == 'sim' ]]; then
        local nome_seguro=''
        dbx_progress_neutralizar "$caminho" nome_seguro
        dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $nome_seguro -> ausente na origem (a apagar)"
      else
        local nome_seguro=''
        dbx_progress_neutralizar "$caminho" nome_seguro
        dbx_progress_mensagem "[sync] analise [$idx_analise/$total_analisados]: $nome_seguro -> apenas no destino (mantido)"
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
    extras_arquivos=0
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
    for item in ${caminhos_locais[@]+"${!caminhos_locais[@]}"}; do
      tamanho_local["${caminhos_locais[$item]}"]=${tamanhos[$item]}
    done
    for item in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
      total_bytes=$((total_bytes + ${tamanho_local[$item]:-0}))
    done
    if ! dbx_cmd_espaco_checar "$total_bytes" "$forcar"; then
      if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
        recusaria_espaco=$DBX_CMD_ESPACO_MOTIVO
        pastas_recusa='sim'
      else
        recusa_espaco='sim'
      fi
    fi
  fi

  # RF-217(d): depois da checagem de espaco, para a recusa por espaco tambem
  # calar o plano de pastas.
  _dbx_cmd_sync_pastas_plano_simular

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
  # RF-217(a): `apagaria`/`criaria pasta` do ciclo antes dos arquivos do ciclo.
  for caminho in ${plano_pastas[@]+"${plano_pastas[@]}"}; do
    dbx_output_campo "${caminho%%$'\t'*}" "${caminho#*$'\t'}"
  done
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
    codigo_parada=$?
        if [[ $modo_ciclos != 'sim' || $ciclo_i -eq 1 ]]; then return "$codigo_parada"; fi
        ciclo_falho=$ciclo_i
        break
  fi

  # RF-67(d): com o plano ja emitido e antes de qualquer escrita.
  if [[ $recusa_espaco == 'sim' ]]; then
    dbx_cmd_falhar espaco "$DBX_CMD_ESPACO_MOTIVO"
    codigo_parada=$?
        if [[ $modo_ciclos != 'sim' || $ciclo_i -eq 1 ]]; then return "$codigo_parada"; fi
        ciclo_falho=$ciclo_i
        break
  fi

  # RF-161: as decisoes saem tambem na simulacao (o plano e o mesmo).
  _dbx_cmd_sync_debug_decisoes

  omitidos_total=$((omitidos_total + ${#DBX_SYNC_IDENTICOS[@]}))
  # Em simulacao o ciclo termina aqui, sem escrita; o `simulado` sai ao fim.
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    continue
  fi

  # RF-208: tamanho de cada arquivo local da analise, por caminho, para o
  # relatorio final (lido por `_dbx_cmd_sync_tamanho_do_item`, escopo dinamico).
  local -A tam_item=()
  local item_tam
  if [[ $sentido == 'enviar' ]]; then
    for item_tam in "${!caminhos_locais[@]}"; do
      tam_item["${caminhos_locais[$item_tam]}"]=${tamanhos[$item_tam]}
    done
    if [[ $pastas_arvore_criada != 'sim' ]]; then
      pastas_arvore_criada='sim'
      _dbx_cmd_sync_pastas_criar || {
        codigo_parada=$?
        if [[ $modo_ciclos != 'sim' || $ciclo_i -eq 1 ]]; then
          return "$codigo_parada"
        fi
        ciclo_falho=$ciclo_i
        break
      }
    fi
    _dbx_cmd_sync_pastas_falhas_aplicar
  elif [[ $modo_ciclos == 'sim' ]]; then
    # F-103, RF-211(a): no --receber (e no `download` de pasta) as pastas do
    # CICLO sao criadas aqui, depois das recusas e da simulacao, antes da
    # primeira transferencia do ciclo. Sem ciclos (delta incremental, RF-212) o
    # comportamento segue o de antes: o pai nasce na gravacao de cada arquivo.
    _dbx_cmd_sync_pastas_receber_criar || {
      codigo_parada=$?
      if [[ $ciclo_i -eq 1 ]]; then
        return "$codigo_parada"
      fi
      ciclo_falho=$ciclo_i
      break
    }
    _dbx_cmd_sync_pastas_falhas_aplicar
  elif [[ $sentido == 'receber' ]]; then
    # F-103, RF-212(a)(b): sem ciclos (delta com cursor valido) as pastas vem da
    # tabela (retrato + delta), sem nenhum `list_folder` por diretorio.
    _dbx_cmd_sync_pastas_delta_criar || {
      codigo_parada=$?
      return "$codigo_parada"
    }
    _dbx_cmd_sync_pastas_falhas_aplicar
  fi
  local total_ops=0
  [[ ${#DBX_SYNC_TRANSFERIR[@]} -gt 0 ]] && total_ops=$((total_ops + ${#DBX_SYNC_TRANSFERIR[@]}))
  if [[ $espelhar == 'sim' && ${#DBX_SYNC_APAGAR[@]} -gt 0 ]]; then
    total_ops=$((total_ops + ${#DBX_SYNC_APAGAR[@]}))
  fi

  local op_atual=0
  # RF-133(d): com N=1 (ou um item so) e o laco de sempre, sem auxiliar. Com
  # N>1 as transferencias do plano vao aos auxiliares e o laco abaixo fica sem
  # itens; as exclusoes, depois, seguem no principal.
  local -a transferir_aqui=(${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"})
  # RF-137: pequenos do plano em lote (start, finish_batch_v2); o laco abaixo e o
  # paralelo so consomem o resultado, na ordem do plano.
  # RF-149(g), DIV-331 (R2): a sonda de disponibilidade e uma por execucao, tambem
  # entre os auxiliares da etapa de lote e da transferencia (a marca fica na area
  # do ciclo, herdada por eles); semeada antes de qualquer auxiliar.
  [[ $ciclo_i -eq 1 ]] && dbx_disp_compartilhar_sonda "$area"
  _dbx_cmd_sync_lote_envio
  if [[ $paralelo -gt 1 && ${#DBX_SYNC_TRANSFERIR[@]} -gt 1 ]]; then
    _dbx_cmd_sync_transferir_paralelo
    transferir_aqui=()
  fi
  for caminho in ${transferir_aqui[@]+"${transferir_aqui[@]}"}; do
    op_atual=$((op_atual + 1))
    if [[ $sentido == 'enviar' ]] && _dbx_cmd_sync_lote_resolvido "$caminho"; then
      _dbx_cmd_sync_prg_iniciar "$op_atual" "$total_ops" enviando "$caminho" "$raiz_local/$caminho"
      if [[ $_DBX_CMD_SYNC_LOTE_ITEM_STATUS == 0 ]]; then
        dbx_progress_arquivo_concluir
        enviados=$((enviados + 1))
        _dbx_cmd_sync_concluido "$caminho"
      else
        dbx_progress_arquivo_falhar
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falha_emitir "$caminho"
      fi
      continue
    fi
    # A escrita usa a grafia que o destino ja tem (RF-54(d)).
    alvo=${DBX_SYNC_ALVO[$caminho]:-$caminho}
    antes=${DBX_HTTP_REQUISICOES:-0}
    if [[ $sentido == 'enviar' ]]; then
      _dbx_cmd_sync_prg_iniciar "$op_atual" "$total_ops" enviando "$caminho" "$raiz_local/$caminho"
      rev=''
      [[ -n ${mapa_remoto[$alvo]+definido} ]] && rev=${mapa_revs[$alvo]:-}
      if _dbx_cmd_sync_enviar "$raiz_local/$caminho" "$remoto/$alvo" "$rev" "$caminho"; then
        dbx_progress_arquivo_concluir
        enviados=$((enviados + 1))
        _dbx_cmd_sync_concluido "$caminho"
      else
        dbx_progress_arquivo_falhar
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falhou "$caminho" "$antes"
        _dbx_cmd_sync_parada_sistemica && break
      fi
    else
      _dbx_cmd_sync_prg_iniciar "$op_atual" "$total_ops" baixando "$caminho" '' "${mapa_tam_remoto[$caminho]:-}"
      if _dbx_cmd_sync_receber "$remoto/$caminho" "$raiz_local" "$alvo"; then
        local tam_prg=''
        if dbx_progress_ativo && [[ -f $raiz_local/$alvo ]]; then dbx_progress_tamanho_de "$raiz_local/$alvo" tam_prg || tam_prg=''; fi
        dbx_progress_arquivo_concluir "$tam_prg"
        recebidos=$((recebidos + 1))
        _dbx_cmd_sync_concluido "$caminho"
      else
        dbx_progress_arquivo_falhar
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falhou "$caminho" "$antes"
        _dbx_cmd_sync_falha_do_plano_incremental
        _dbx_cmd_sync_parada_sistemica && break
      fi
    fi
  done

  # QA-B42-01: UM aviso por execucao, com o total dos ciclos.
  if [[ $retidos_total -gt 0 ]]; then
    dbx_cmd_avisar "$retidos_total caminho(s) fora do ASCII mantido(s) sem apagar: $DBX_SYNC_LOCALIDADE ausente, a comparacao sem caixa so vale no ASCII e o par poderia ser o mesmo arquivo na Dropbox; nada foi apagado por isso"
  fi

  if [[ $ciclo_falho -gt 0 ]]; then
    : # RF-193: falha sistemica nesta execucao em ciclos: nenhuma exclusao
  elif [[ $espelhar == 'sim' && $sentido == 'enviar' ]]; then
    # RF-136: exclusao remota em lote (delete_batch + check), nunca delete_v2 em
    # laco. As guardas ja agiram; a lista abaixo so perde, outra vez, o que o
    # escopo dos filtros protege (RF-80(d), sem estado).
    _dbx_cmd_sync_apagar_remoto_em_lote "$remoto"
  elif [[ $espelhar == 'sim' ]]; then
    for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      # RF-80(d), no ponto da escrita: a mesma conta sem estado, de novo.
      _dbx_cmd_sync_protegido "$caminho" && continue
      op_atual=$((op_atual + 1))
      dbx_progress_etapa "$op_atual" "$total_ops" 'apagando' "$caminho"
      antes=${DBX_HTTP_REQUISICOES:-0}
      if _dbx_cmd_sync_apagar_local "$raiz_local" "$caminho"; then
        apagados=$((apagados + 1))
      else
        falhas=$((falhas + 1))
        _dbx_cmd_sync_falhou "$caminho" "$antes"
      fi
    done
  fi
    # RF-216(g): ciclo sem exclusao liberada, falho ou parcial bloqueia as pastas.
    [[ $espelhar == 'sim' && $exclusao_desabilitada == 'nao' && $recusa_origem_vazia == 'nao' &&
      $ciclo_falho -eq 0 && $parcial != 'sim' ]] || pastas_bloqueio='sim'
    [[ $ciclo_falho -gt 0 ]] && break
    done
  # RF-215(c), RF-216: pastas orfas so depois das exclusoes de arquivo de TODOS os ciclos.
  _dbx_cmd_sync_pastas_orfas_apagar

  if [[ $modo_ciclos == 'sim' ]]; then
    dbx_sync_avisos_de_filtro "$antes_total" "$depois_total"
    dbx_cmd_avisos_de_filtro
  fi
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' && $ciclo_falho -eq 0 ]]; then
    dbx_cmd_iniciar_saida
    # RF-217(a): exclusoes de pasta depois das de arquivo de todos os ciclos.
    for caminho in ${pastas_apagaria[@]+"${pastas_apagaria[@]}"}; do
      dbx_output_campo apagaria "$caminho"
    done
    _dbx_cmd_sync_pastas_campos
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi
  dbx_debug_resumo_campo bloco "$DBX_CMD_SYNC_BLOCO"
  dbx_debug_resumo_campo ciclos "$ciclo_i"
  local filtrados_origem=$fo_total filtrados_destino=$fd_total

  dbx_progress_mensagem "[sync] sincronizacao concluida: $enviados enviados, $recebidos recebidos, $apagados apagados, $omitidos_total omitidos"

  # RF-135(d), DIV-258, DIV-338 A: a linha `paralelo` deixou de existir; o N e os
  # `429` (principal e auxiliares) vao na linha `debug: resumo` (RF-162), emitida
  # no termino do processo por lib/debug (`dbx_debug_resumo_armar`).

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
  # Em ciclos (RF-192), o retrato e o acumulado dos ciclos e o cursor, o pedido
  # antes do ciclo 1; tudo ou nada: ciclo falho ou leitura parcial nao grava.
  if [[ $ciclo_falho -eq 0 && $DBX_CMD_SYNC_CURSOR_GRAVA == 'sim' && $falhas -eq 0 && $parcial != 'sim' &&
    ! ($espelhar == 'sim' && ($memoria_descartada == 'sim' || -z $conta)) ]]; then
    if [[ $modo_ciclos != 'sim' ]]; then
      _dbx_cmd_sync_cursor_gravar
    elif _dbx_cmd_sync_retrato_restaurar; then
      _dbx_cmd_sync_cursor_gravar
    fi
  fi
  dbx_cmd_iniciar_saida
  # RF-208(a,b): os arquivos (concluidos e falhos), com tamanho legivel, vem
  # antes dos contadores em qualquer modo; com --json os pares em bytes vem
  # depois dos de RF-59(b).
  _dbx_cmd_sync_relatorio_itens legivel
  dbx_output_campo operacao sync
  dbx_output_campo enviados "$enviados"
  dbx_output_campo recebidos "$recebidos"
  dbx_output_campo apagados "$apagados"
  dbx_output_campo omitidos "$omitidos_total"
  dbx_output_campo falhas "$falhas"
  # RF-59(b): no `--json`, cada falha vira o par `falha_caminho`/`falha_classe`,
  # na ordem das linhas de falha. Acrescimo compativel (RF-35): `falhas`, a
  # contagem, continua como era, e sem `--json` a saida padrao nao muda.
  local indice valor
  if [[ ${DBX_CLI_ESTRUTURADA:-nao} == 'sim' ]]; then
    for indice in ${DBX_CMD_SYNC_FALHAS_CAMINHOS[@]+"${!DBX_CMD_SYNC_FALHAS_CAMINHOS[@]}"}; do
      valor=${DBX_CMD_SYNC_FALHAS_CAMINHOS[indice]}
      # Com `--null` o registro carrega qualquer byte; por linha, vale a mesma
      # citacao da linha de falha.
      if [[ ${DBX_CLI_NULO:-nao} != 'sim' ]]; then
        _dbx_cmd_sync_exibir "$valor"
        valor=$DBX_CMD_SYNC_EXIBIDO
      fi
      dbx_output_campo falha_caminho "$valor"
      dbx_output_campo falha_classe "${DBX_CMD_SYNC_FALHAS_CLASSES[indice]}"
      # RF-208(c): motivo (mascarado pelo valor, como a linha de stderr) e bytes.
      dbx_output_mascarar_segredos "${DBX_CMD_SYNC_FALHAS_MOTIVOS[indice]-}"
      dbx_output_campo falha_motivo "$DBX_OUTPUT_MASCARADO"
      dbx_output_campo falha_tamanho "${DBX_CMD_SYNC_FALHAS_TAMANHOS[indice]-}"
    done
    _dbx_cmd_sync_relatorio_itens estruturado
  fi
  # RF-218(a): contadores de pasta depois dos pares de falha (RF-59(b)), que
  # seguem logo apos `falhas`; os campos antigos ficam onde estavam.
  _dbx_cmd_sync_pastas_campos
  if [[ ${DBX_CLI_ESTRUTURADA:-nao} == 'sim' || $ciclo_i -gt 1 ]]; then
    dbx_output_campo ciclos "$ciclo_i"
    dbx_output_campo bloco "$DBX_CMD_SYNC_BLOCO"
    dbx_output_campo bloco_origem "$DBX_CMD_SYNC_BLOCO_ORIGEM"
  fi
  if [[ $ciclo_falho -gt 0 ]]; then
    dbx_output_campo ciclos_concluidos "$((ciclo_falho - 1))"
    dbx_output_campo ciclo_falho "$ciclo_falho"
    # Em fluxo (remota) o total de ciclos nao e conhecido: sao os diretorios
    # pendentes na fila, nunca listados, que ficam sem tentar.
    if [[ $modo_ciclos == 'sim' && $sentido == 'receber' ]]; then
      dbx_output_campo ciclos_nao_tentados "${#fila_remota[@]}"
    else
      dbx_output_campo ciclos_nao_tentados "$(( ${#ciclos[@]} - ciclo_falho ))"
    fi
  fi
  # RF-80(j), RF-82(i): acrescimo compativel ao resumo (RF-35).
  dbx_cmd_campos_de_filtro "$filtrados_origem" "$filtrados_destino"
  dbx_output_campo limite_banda "$DBX_CMD_LIMITE_BANDA"
  dbx_output_render

  # RF-41(a) exige codigo diferente de zero quando a travessia foi parcial, ainda
  # que nada tenha falhado: o operador precisa saber que o resultado nao e o
  # espelho completo que pediu.
  # RF-193: a parada por enumeracao ou espaco ja disse a classe e o motivo.
  [[ $ciclo_falho -gt 0 ]] && return "$codigo_parada"
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

# _dbx_cmd_sync_reter_nao_ascii — falha fechada (QA-B42-01): so com `--espelhar`,
# tira do plano de exclusao o caminho fora do ASCII quando a localidade falta, e
# soma o que reteve em `retidos_total` (variavel do executor) para o aviso unico.
_dbx_cmd_sync_reter_nao_ascii() {
  [[ $espelhar == 'sim' ]] || return 0
  dbx_sync_reter_nao_ascii
  retidos_total=$((retidos_total + DBX_SYNC_RETIDOS))
}

# _dbx_cmd_sync_ler_tamanhos <arquivo> <nome_do_mapa> — `size` por caminho remoto,
# lido da tabela `resumo<TAB>tamanho<TAB>caminho\0` ja montada pela listagem.
_dbx_cmd_sync_ler_tamanhos() {
  local arquivo=$1 reg tam
  dbx_ref_limpar "$2" || return 2
  [[ -r $arquivo ]] || return 0
  while IFS= read -r -d '' reg; do
    tam=${reg#*$'\t'}
    tam=${tam%%$'\t'*}
    [[ $tam =~ ^[0-9]+$ ]] || continue
    reg=${reg#*$'\t'}
    dbx_ref_definir "$2" "${reg#*$'\t'}" "$tam"
  done <"$arquivo"
  return 0
}

# _dbx_cmd_sync_prg_iniciar <i> <n> <acao> <item> <arquivo_local|''> — abre a
# linha do arquivo (RF-140); o tamanho so e lido com o progresso ativo (RF-145(c)).
_dbx_cmd_sync_prg_iniciar() {
  local total=${6-}
  if [[ -z $total && -n $5 ]] && dbx_progress_ativo && dbx_transfer_tamanho_de_arquivo "$5"; then
    total=$DBX_TRANSFER_TAMANHO
  fi
  dbx_progress_arquivo_iniciar "$1" "$2" "$3" "$4" "$total"
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
  # RF-164(b), DIV-332: no sync a depuracao nomeia o item relativo a raiz.
  local DBX_TRANSFER_DEBUG_ITEM=${4:-}
  DBX_CMD_SYNC_FALHA_CLASSE=''
  dbx_transfer_objeto_de_publicacao "$destino" add "$rev" "$origem" true
  # RF-144(e): com progresso ativo o stderr da transferencia deixa de ser descartado.
  if dbx_progress_ativo; then
    dbx_transfer_enviar_arquivo "$origem" "$DBX_TRANSFER_COMMIT" sync >/dev/null && return 0
  else
    dbx_transfer_enviar_arquivo "$origem" "$DBX_TRANSFER_COMMIT" sync >/dev/null 2>&1 && return 0
  fi
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
  if dbx_progress_ativo; then
    dbx_cmd_receber_arquivo "$remoto" "$raiz/$relativo" >/dev/null && return 0
  else
    dbx_cmd_receber_arquivo "$remoto" "$raiz/$relativo" >/dev/null 2>&1 && return 0
  fi
  DBX_CMD_SYNC_FALHA_CLASSE=${DBX_CMD_FALHA_CLASSE:-${DBX_HTTP_CLASSE:-erro_remoto}}
  return 1
}

# _dbx_cmd_sync_aviso_exclusao_em_curso — DIV-275: mensagem de interrupcao do
# `sync` com exclusao em lote em curso.
_dbx_cmd_sync_aviso_exclusao_em_curso() {
  printf '%s\n' 'sync interrompido durante a exclusao em lote: a exclusao em curso pode ter sido concluida no servidor (os itens vao para a lixeira); a proxima execucao os ve como ausentes' >&2
}

# _dbx_cmd_sync_apagar_remoto_em_lote <remoto> — RF-136: exclui no destino
# remoto a lista DBX_SYNC_APAGAR (menos o protegido pelos filtros, RF-80(d)) por
# `delete_batch`. Cada item e identificado pelo caminho canonico do destino e, se
# a listagem desta execucao trouxe, pelo `rev` (`parent_rev`). Saida e relatorio
# por item iguais aos do `delete_v2` de antes: so `success` confirmado conta; o
# resto e falha do item, com a mesma linha `falha <caminho>: <classe> <resumo>`.
# Variaveis do executor (escopo dinamico): op_atual, total_ops, apagados, falhas,
# mapa_revs.
_dbx_cmd_sync_apagar_remoto_em_lote() {
  local raiz=$1 caminho i
  local -a alvos=()
  DBX_LOTE_CAMINHOS=() DBX_LOTE_REVS=()
  for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    _dbx_cmd_sync_protegido "$caminho" && continue
    # shellcheck disable=SC2190  # falso positivo: alvos e indexado (local -a)
    alvos+=("$caminho")
    DBX_LOTE_CAMINHOS+=("$raiz/$caminho")
    DBX_LOTE_REVS+=("${mapa_revs[$caminho]:-}")
  done
  [[ ${#alvos[@]} -gt 0 ]] || return 0
  DBX_LOTE_GANCHO_FATIA=''
  # DIV-275: interrompido com a exclusao em curso, a fatia pode ja ter sido
  # concluida no servidor sem que este processo a conte. A acao roda so no
  # termino por sinal (ou saida) DENTRO da janela; fora dela e cancelada.
  dbx_tmp_acao_registrar _dbx_cmd_sync_aviso_exclusao_em_curso
  local acao_exclusao=$DBX_TMP_ID
  dbx_lote_excluir
  dbx_tmp_acao_cancelar "$acao_exclusao"
  for i in ${alvos[@]+"${!alvos[@]}"}; do
    caminho=${alvos[i]}
    op_atual=$((op_atual + 1))
    dbx_progress_etapa "$op_atual" "$total_ops" 'apagando' "$caminho"
    if [[ ${DBX_LOTE_RESULTADO[i]} == 'ok' ]]; then
      apagados=$((apagados + 1))
      continue
    fi
    falhas=$((falhas + 1))
    DBX_CMD_SYNC_FALHA_CLASSE=${DBX_LOTE_CLASSE[i]:-nao_concluida}
    dbx_errors_redigir "${DBX_LOTE_MOTIVO[i]:-item nao confirmado pelo lote}" >/dev/null
    DBX_CMD_SYNC_RESUMO_FALHA=${DBX_ERRORS_REDIGIDO:0:120}
    _dbx_cmd_sync_falha_emitir "$caminho"
  done
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

# F-101, RF-192: o retrato de uma varredura em ciclos. `_iniciar` zera o
# acumulado e pede o cursor da raiz (`get_latest_cursor`, mesmos argumentos da
# listagem completa) so quando a execucao pode gravar; `_acumular` junta a tabela
# de cada ciclo (a tabela corrente e zerada no ciclo seguinte); `_restaurar`
# devolve o acumulado a tabela com o cursor, para `_dbx_cmd_sync_cursor_gravar`.
# Sem cursor obtido, nada e gravado: o cursor so acelera.
declare -gA _DBX_CMD_SYNC_RETRATO=()
_DBX_CMD_SYNC_RETRATO_ORDEM=()
_DBX_CMD_SYNC_RETRATO_PERSISTIVEL='sim'
_DBX_CMD_SYNC_RETRATO_CURSOR=''
_dbx_cmd_sync_retrato_iniciar() {
  _DBX_CMD_SYNC_RETRATO=()
  _DBX_CMD_SYNC_RETRATO_ORDEM=()
  _DBX_CMD_SYNC_RETRATO_PERSISTIVEL='sim'
  _DBX_CMD_SYNC_RETRATO_CURSOR=''
  [[ $DBX_CMD_SYNC_CURSOR_GRAVA == 'sim' ]] || return 0
  dbx_sync_cursor_ultimo "$1" || {
    dbx_progress_mensagem '[sync] cursor da raiz indisponivel: o registro de listagem nao sera gravado'
    return 0
  }
  _DBX_CMD_SYNC_RETRATO_CURSOR=$DBX_SYNC_CURSOR_ULTIMO
  DBX_SYNC_CURSOR_ULTIMO=''
}

_dbx_cmd_sync_retrato_acumular() {
  [[ $DBX_CMD_SYNC_CURSOR_GRAVA == 'sim' && -n $_DBX_CMD_SYNC_RETRATO_CURSOR ]] || return 0
  local pl
  [[ $DBX_SYNC_TAB_PERSISTIVEL == 'sim' ]] || _DBX_CMD_SYNC_RETRATO_PERSISTIVEL='nao'
  for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
    [[ -n ${DBX_SYNC_TAB[$pl]+definido} ]] || continue
    [[ -n ${_DBX_CMD_SYNC_RETRATO[$pl]+definido} ]] || _DBX_CMD_SYNC_RETRATO_ORDEM+=("$pl")
    _DBX_CMD_SYNC_RETRATO[$pl]=${DBX_SYNC_TAB[$pl]}
  done
}

_dbx_cmd_sync_retrato_restaurar() {
  [[ -n $_DBX_CMD_SYNC_RETRATO_CURSOR ]] || return 1
  local pl
  dbx_sync_tabela_zerar
  for pl in ${_DBX_CMD_SYNC_RETRATO_ORDEM[@]+"${_DBX_CMD_SYNC_RETRATO_ORDEM[@]}"}; do
    _dbx_sync_tab_inserir "$pl" "${_DBX_CMD_SYNC_RETRATO[$pl]}"
  done
  DBX_SYNC_TAB_PERSISTIVEL=$_DBX_CMD_SYNC_RETRATO_PERSISTIVEL
  DBX_SYNC_CURSOR_NOVO=$_DBX_CMD_SYNC_RETRATO_CURSOR
  _DBX_CMD_SYNC_RETRATO=()
  _DBX_CMD_SYNC_RETRATO_ORDEM=()
  return 0
}

# _dbx_cmd_sync_cursor_gravar — grava cursor e retrato (C6): cursor da ultima
# pagina, tabela sem filtro desta execucao, carimbo e contagem de incrementais.
# Tabela fora do formato ou cursor fora da regex: nao persiste, sem aviso (a
# proxima execucao faz a varredura completa). Falha de escrita: um aviso, o
# mesmo resultado e o mesmo codigo (RF-111(g)).
_dbx_cmd_sync_cursor_gravar() {
  local completa incrementais agora
  [[ $DBX_SYNC_TAB_PERSISTIVEL == 'sim' && ${#DBX_SYNC_CURSOR_NOVO} -le 8192 &&
    $DBX_SYNC_CURSOR_NOVO =~ $DBX_STATE_CURSOR_RE_CURSOR ]] || return 0
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

# _dbx_cmd_sync_pastas_do_escopo — F-103, RF-209(a)(b)(c): diretorios locais do
# escopo de caminho (relativos), em `pastas_escopo`. Em ciclos, os da enumeracao
# previa (`dirs_v`); sem ciclos (delta incremental, que percorre so arquivos em
# `dbx_walk_local`), a mesma travessia de diretorios da enumeracao, sem tocar em
# `parcial` (a leitura parcial continua sendo a da travessia de arquivos).
# Filtros de data e tamanho nao podam diretorio; o de caminho sim (lib/walk).
# Executor: modo_ciclos, dirs_v, raiz_local, area (le); pastas_escopo (escreve).
_dbx_cmd_sync_pastas_do_escopo() {
  local reg
  pastas_escopo=()
  if [[ $modo_ciclos == 'sim' ]]; then
    pastas_escopo=(${dirs_v[@]+"${dirs_v[@]}"})
    return 0
  fi
  dbx_walk_diretorios "$raiz_local" "$area/pastas_escopo" || {
    dbx_cmd_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
    return $?
  }
  while IFS= read -r -d '' reg; do
    pastas_escopo+=("${reg#*$'\t'}")
  done <"$area/pastas_escopo"
  return 0
}

# _dbx_cmd_sync_pastas_criar — F-103, RF-210(a)(e), RF-213(a)(b): cria pelo lote
# (`dbx_lote_criar_pastas`) toda pasta do escopo sob o destino remoto, antes do
# ciclo 1. A raiz do destino fica de fora (RF-209(e)). Simulacao: nenhuma
# chamada. Falha sistemica: para pelo caminho de falha do comando, antes de
# qualquer transferencia e sem exclusao. Falha de item: a pasta e avisada e
# registrada em `pastas_falhas`; os arquivos sob ela falham por ciclo
# (`_dbx_cmd_sync_pastas_falhas_aplicar`). Nao marca leitura parcial (RF-213(c)).
# Variaveis do executor: sentido, modo_ciclos, dirs_v, raiz_local, remoto, area,
# espelhar (le); pastas_falhas, pastas_criadas, pastas_escopo, falhas, apagados
# (escreve).
_dbx_cmd_sync_pastas_criar() {
  local k res status=0
  local -a pastas_escopo=() relativos=()
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && return 0
  _dbx_cmd_sync_pastas_do_escopo || return $?
  DBX_LOTE_PASTAS=()
  for k in "${!pastas_escopo[@]}"; do
    [[ -n ${pastas_escopo[k]} ]] || continue
    relativos+=("${pastas_escopo[k]}")
    DBX_LOTE_PASTAS+=("$remoto/${pastas_escopo[k]}")
  done
  # RF-214(a): sem --espelhar (ou com guarda que nao passa), `path/conflict/file`
  # volta do lote como falha de item e nada e apagado.
  dbx_lote_criar_pastas || status=$?
  if [[ $status -eq $DBX_LOTE_PASTAS_FALHA_SISTEMICA ]]; then
    dbx_cmd_falhar "${DBX_LOTE_PASTAS_CLASSE:-erro_remoto}" "${DBX_LOTE_PASTAS_MOTIVO:-criacao de pastas falhou}"
    return $?
  fi
  # RF-214(b)-(e): com --espelhar, o arquivo do destino que ocupa o caminho de
  # uma pasta da origem e apagado (guardas em `_ocupantes_apagar`) e a pasta e
  # submetida de novo, na mesma execucao.
  if [[ $status -ne 0 ]]; then
    _dbx_cmd_sync_pastas_ocupantes_apagar ${relativos[@]+"${relativos[@]}"} || return $?
  fi
  for k in "${!relativos[@]}"; do
    res=${DBX_LOTE_PASTAS_RESULTADO[k]:-}
    [[ $res == 'criada' ]] && pastas_criadas=$((pastas_criadas + 1))
    [[ $res == falha$'\t'* ]] || continue
    res=${res#*$'\t'}
    if [[ $res == 'pasta de destino nao criada: '* ]]; then
      pastas_falhas["${relativos[k]}"]=${res#pasta de destino nao criada: }
    else
      pastas_falhas["${relativos[k]}"]=${DBX_LOTE_PASTAS[k]}
      dbx_cmd_avisar "pasta nao criada: $res"
      _dbx_cmd_sync_pasta_falha_contar "${relativos[k]}" "$res"
    fi
  done
  return 0
}

# _dbx_cmd_sync_apagar_retirar <relativo> — RF-214(b): o item apagado pela
# exclusao antecipada sai de DBX_SYNC_APAGAR (sem dupla exclusao nem contagem).
_dbx_cmd_sync_apagar_retirar() {
  local c
  local -a manter=()
  for c in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    [[ $c == "$1" ]] || manter+=("$c")
  done
  DBX_SYNC_APAGAR=(${manter[@]+"${manter[@]}"})
}

# _dbx_cmd_sync_exclusao_antecipada_permitida <relativo> — RF-214(c)(3)(4)(5): os
# MESMOS predicados da exclusao comum, reavaliados no momento: --espelhar, sem
# exclusao desabilitada (travessia parcial, conta nao identificada, memoria
# descartada), sem recusa de origem vazia, e o destino nao filtrado (RF-80(d)).
# Variavel ausente conta como nao liberada. O reconhecimento da primeira
# execucao (--confirmar, RF-48) ja foi exigido antes do plano.
_dbx_cmd_sync_exclusao_antecipada_permitida() {
  [[ ${espelhar:-nao} == 'sim' && ${exclusao_desabilitada:-sim} == 'nao' && ${recusa_origem_vazia:-sim} == 'nao' ]] || return 1
  _dbx_cmd_sync_protegido "$1" && return 1
  return 0
}

# _dbx_cmd_sync_ocupante_remoto_ler <pai> <alvo> — RF-214(c)(1)(6): lista o pai
# por inteiro (todas as paginas, nao recursivo) e le o item de caminho <alvo>.
# Status 0 so quando a listagem terminou e o item e um `file` com `rev`; o rev
# fica em _DBX_SYNC_OCUPANTE_REV. Qualquer outra coisa (erro, laco, ausente,
# pasta, sem rev) e status 1.
_DBX_SYNC_OCUPANTE_REV=''
_dbx_cmd_sync_ocupante_remoto_ler() {
  local pai=$1 alvo=${2,,} corpo url estado quantidade i cam tag rev pagina=1 anterior='' achou='nao' tag_achada='' rev_achado=''
  _DBX_SYNC_OCUPANTE_REV=''
  dbx_json_escapar_cadeia "$pai"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"recursive\":false}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  url='https://api.dropboxapi.com/2/files/list_folder'
  while :; do
    if [[ $pagina -eq 1 ]]; then
      dbx_auth_colecao POST "$url" "$corpo" "$DBX_SYNC_LIMITE_PAGINA"
    else
      dbx_auth_requisitar POST "$url" "$_DBX_SYNC_CORPO" sim
    fi
    estado=$?
    _DBX_SYNC_CORPO=''
    [[ $estado -eq 0 ]] || return 1
    _dbx_cmd_analisar_corpo || return 1
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
    for ((i = 0; i < quantidade; i++)); do
      cam='' tag='' rev=''
      _dbx_cmd_campo entries "$i" path_lower && cam=$DBX_CMD_LIDO
      [[ ${cam,,} == "$alvo" ]] || continue
      _dbx_cmd_campo entries "$i" '.tag' && tag=$DBX_CMD_LIDO
      _dbx_cmd_campo entries "$i" rev && rev=$DBX_CMD_LIDO
      achou='sim' tag_achada=$tag rev_achado=$rev
    done
    _dbx_sync_pagina_seguinte "$anterior"
    estado=$?
    _dbx_cmd_encerrar_consulta
    [[ $estado -eq 1 ]] && break
    if [[ $estado -eq 2 || $pagina -ge $DBX_SYNC_TETO_PAGINAS ]]; then
      DBX_SYNC_CURSOR_NOVO=''
      return 1
    fi
    anterior=$DBX_SYNC_CURSOR_NOVO
    pagina=$((pagina + 1))
    _dbx_sync_corpo_continue "$anterior"
    url='https://api.dropboxapi.com/2/files/list_folder/continue'
  done
  [[ $achou == 'sim' && $tag_achada == 'file' && -n $rev_achado ]] || return 1
  _DBX_SYNC_OCUPANTE_REV=$rev_achado
  return 0
}

# _dbx_cmd_sync_ocupante_remoto_apagar <caminho remoto> — RF-214(c)(1)(6): le o
# item no pai listado nesta execucao e o apaga por `files/delete_v2` com
# `parent_rev` igual ao rev lido (para a lixeira; nunca delete_batch nem
# permanently_delete). Status 0 so com o servidor confirmando.
_dbx_cmd_sync_ocupante_remoto_apagar() {
  local alvo=$1 pai corpo
  pai=${alvo%/*}
  _dbx_cmd_sync_ocupante_remoto_ler "$pai" "$alvo" || return 1
  dbx_json_escapar_cadeia "$alvo"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\""
  dbx_json_escapar_cadeia "$_DBX_SYNC_OCUPANTE_REV"
  corpo+=",\"parent_rev\":\"$DBX_JSON_ESCAPADO\"}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  _dbx_cmd_escrita_remota 'https://api.dropboxapi.com/2/files/delete_v2' "$corpo" || return 1
  _dbx_cmd_encerrar_consulta
  return 0
}

# _dbx_cmd_sync_pastas_ocupantes_apagar <relativos das pastas, na ordem de
# DBX_LOTE_PASTAS> — RF-214(b)-(e), envio: para cada pasta que o lote devolveu
# com `arquivo no lugar da pasta` e passa nas guardas, apaga o arquivo do destino
# e submete de novo a pasta e as descendentes que dela dependiam. O resultado do
# reenvio substitui o das posicoes. Guarda que nao passa ou exclusao que falha:
# o resultado de falha de item (RF-214(a)) fica como estava e a pasta nao e criada
# (RF-214(d)). Falha sistemica no reenvio para pelo caminho de falha do comando.
# Executor: espelhar, apagados, exclusao_desabilitada, recusa_origem_vazia.
_dbx_cmd_sync_pastas_ocupantes_apagar() {
  local -a rels=("$@") reenvio=() cheia=(${DBX_LOTE_PASTAS[@]+"${DBX_LOTE_PASTAS[@]}"}) velhos=(${DBX_LOTE_PASTAS_RESULTADO[@]+"${DBX_LOTE_PASTAS_RESULTADO[@]}"})
  local k j cam res status=0
  local -A liberada=()
  for k in "${!cheia[@]}"; do
    res=${velhos[k]:-}
    [[ $res == "falha"$'\t'"arquivo no lugar da pasta: ${cheia[k]}" ]] || continue
    cam=${cheia[k]}
    _dbx_cmd_sync_exclusao_antecipada_permitida "${rels[k]}" || continue
    if _dbx_cmd_sync_ocupante_remoto_apagar "$cam"; then
      apagados=$((apagados + 1))
      _dbx_cmd_sync_apagar_retirar "${rels[k]}"
      dbx_cmd_avisar "apagado: ${rels[k]} (arquivo no lugar da pasta)"
      DBX_CMD_SYNC_APAGADOS_PASTA+=("${rels[k]}")
      liberada[$cam]=1
    else
      dbx_cmd_avisar "arquivo no lugar da pasta nao apagado: $cam"
    fi
  done
  [[ ${#liberada[@]} -gt 0 ]] || return 0
  local -a posicoes=()
  for k in "${!cheia[@]}"; do
    res=${velhos[k]:-}
    for j in "${!liberada[@]}"; do
      if [[ ${cheia[k]} == "$j" || $res == "falha"$'\t'"pasta de destino nao criada: $j" ]]; then
        posicoes+=("$k")
        reenvio+=("${cheia[k]}")
        break
      fi
    done
  done
  DBX_LOTE_PASTAS=(${reenvio[@]+"${reenvio[@]}"})
  dbx_lote_criar_pastas || status=$?
  local -a novos=(${DBX_LOTE_PASTAS_RESULTADO[@]+"${DBX_LOTE_PASTAS_RESULTADO[@]}"})
  DBX_LOTE_PASTAS=(${cheia[@]+"${cheia[@]}"})
  DBX_LOTE_PASTAS_RESULTADO=(${velhos[@]+"${velhos[@]}"})
  if [[ $status -eq $DBX_LOTE_PASTAS_FALHA_SISTEMICA ]]; then
    dbx_cmd_falhar "${DBX_LOTE_PASTAS_CLASSE:-erro_remoto}" "${DBX_LOTE_PASTAS_MOTIVO:-criacao de pastas falhou}"
    return $?
  fi
  for k in "${!posicoes[@]}"; do
    DBX_LOTE_PASTAS_RESULTADO[posicoes[k]]=${novos[k]:-}
  done
  return 0
}

# _dbx_cmd_sync_pasta_falha_contar <relativo> <motivo> — RF-213(a): a pasta que
# nao foi criada conta ela mesma como falha de item (mesmo sem arquivos sob ela),
# com a classe do sentido e o caminho da pasta, como os arquivos. Executor:
# sentido (le), falhas e pastas_falhou (escreve).
_dbx_cmd_sync_pasta_falha_contar() {
  falhas=$((falhas + 1))
  pastas_falhou=$((pastas_falhou + 1))
  if [[ $sentido == 'enviar' ]]; then DBX_CMD_SYNC_FALHA_CLASSE='erro_remoto'; else DBX_CMD_SYNC_FALHA_CLASSE='configuracao'; fi
  DBX_CMD_SYNC_RESUMO_FALHA=$2
  _dbx_cmd_sync_falha_emitir "$1"
}

# _dbx_cmd_sync_pasta_local_ocupada_remover <relativo> <caminho local> —
# RF-214(b)(c)(7), recebimento: com as guardas da exclusao antecipada, remove o
# arquivo regular ou a ligacao simbolica (`rm -f`, nunca -r, nunca o alvo da
# ligacao) que ocupa o caminho de uma pasta remota observada nesta execucao.
# Diretorio nunca. Status 0 so quando o caminho ficou livre. Executor: apagados
# (escreve), espelhar e demais predicados da exclusao antecipada (le),
# DBX_CMD_SYNC_APAGADOS_PASTA (escreve).
_dbx_cmd_sync_pasta_local_ocupada_remover() {
  _dbx_cmd_sync_exclusao_antecipada_permitida "$1" || return 1
  if [[ -L $2 ]]; then :; elif [[ -f $2 && ! -d $2 ]]; then :; else return 1; fi
  rm -f -- "$2" 2>/dev/null || return 1
  [[ -e $2 || -L $2 ]] && return 1
  apagados=$((apagados + 1))
  _dbx_cmd_sync_apagar_retirar "$1"
  dbx_cmd_avisar "apagado: $1 (arquivo no lugar da pasta)"
  DBX_CMD_SYNC_APAGADOS_PASTA+=("$1")
  return 0
}

# _dbx_cmd_sync_pasta_remota_observada <relativo> — RF-214(a), DIV-401: status 0
# so quando um `get_metadata` DESTA execucao devolve `.tag == folder` para o
# caminho remoto. Retrato, cursor e tabela nao valem; erro, ausencia ou arquivo
# sao status 1 (nada e apagado). Executor: remoto.
_dbx_cmd_sync_pasta_remota_observada() {
  dbx_json_escapar_cadeia "$remoto/$1"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/get_metadata' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\"}" sim
  local estado=$?
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  [[ $estado -eq 0 ]] || return 1
  dbx_cmd_ler_corpo_silencioso '.tag' || return 1
  [[ ${DBX_CMD_CAMPOS[0]-} == 'folder' ]]
}

# _dbx_cmd_sync_pasta_local_criar <relativo> <ocupante:sim|confirmar> — RF-211,
# RF-213, RF-214: cria uma pasta local (`mkdir` NAO recursivo). Herda a falha do
# ancestral; o arquivo ou a ligacao que ocupa o caminho so e apagado quando a
# pasta remota foi observada nesta execucao: `sim` (o chamador ja a observou, a
# travessia dos ciclos) ou `confirmar` (delta: exige antes que `--espelhar` e as
# guardas permitam e que `get_metadata` confirme a pasta, sem rede fora disso).
# Caso contrario o ocupante fica intacto e a pasta falha com motivo. Devolve 0
# (inclusive falha de item) ou o codigo da falha sistemica (ENOSPC, EROFS,
# cota). Executor: raiz_local, pastas_falhas, pastas_criadas, falhas, apagados,
# sentido, remoto.
_dbx_cmd_sync_pasta_local_criar() {
  local rel=$1 cam="$raiz_local/$1" acima=$1 herdada='' erro
  while [[ $acima == */* ]]; do
    acima=${acima%/*}
    if [[ -n ${pastas_falhas[$acima]+x} ]]; then
      herdada=${pastas_falhas[$acima]}
      break
    fi
  done
  if [[ -n $herdada ]]; then
    pastas_falhas["$rel"]=$herdada
    return 0
  fi
  # RF-214(b)-(e): o arquivo (ou ligacao) que ocupa o caminho e apagado ANTES da
  # criacao; diretorio nunca.
  if [[ -L $cam || ( -e $cam && ! -d $cam ) ]]; then
    if [[ $2 == 'sim' ]] ||
      { [[ $2 == 'confirmar' ]] && _dbx_cmd_sync_exclusao_antecipada_permitida "$rel" &&
        _dbx_cmd_sync_pasta_remota_observada "$rel"; }; then
      _dbx_cmd_sync_pasta_local_ocupada_remover "$rel" "$cam"
    fi
  fi
  if [[ -L $cam || ( -e $cam && ! -d $cam ) ]]; then
    pastas_falhas["$rel"]=$cam
    dbx_cmd_avisar "pasta nao criada: arquivo no lugar da pasta: $cam"
    _dbx_cmd_sync_pasta_falha_contar "$rel" "arquivo no lugar da pasta: $cam"
    return 0
  fi
  [[ -d $cam ]] && return 0
  [[ -d $raiz_local ]] || mkdir -p -- "$raiz_local" 2>/dev/null
  if ! erro=$(mkdir -- "$cam" 2>&1); then
    dbx_debug_linha pasta operacao=mkdir resultado=falha caminho="$rel"
    case $erro in
      *'No space left'* | *'Read-only file system'* | *'Disk quota'*)
        dbx_cmd_falhar configuracao "sem espaco ou destino somente leitura para criar pastas: $cam"
        return $?
        ;;
    esac
    pastas_falhas["$rel"]=$cam
    dbx_cmd_avisar "pasta nao criada: nao foi possivel criar $cam"
    _dbx_cmd_sync_pasta_falha_contar "$rel" "nao foi possivel criar $cam"
  else
    dbx_debug_linha pasta operacao=mkdir resultado=ok caminho="$rel"
    pastas_criadas=$((pastas_criadas + 1))
  fi
  return 0
}

# _dbx_cmd_sync_pastas_receber_criar — F-103, RF-211(a)-(e), RF-213(a)(b),
# RF-214(a): cria no destino local as pastas do ciclo (`dirs_v[ci_ini..ci_fim)`,
# que ja respeitam filtro de caminho e confinamento), pai antes de filho, com
# `mkdir` NAO recursivo. Pasta ja existente e sucesso. Caminho existente que nao
# e diretorio, ou e ligacao simbolica (nunca seguida), e falha de item: avisa
# `arquivo no lugar da pasta: <caminho>` e registra em `pastas_falhas` (relativo
# -> caminho local), herdado pelos descendentes; nada e apagado. EACCES e falha de
# item; ENOSPC e EROFS sao sistemicos (devolve o codigo da falha). A raiz do
# destino fica de fora. Simulacao: nada e criado. Executor: dirs_v, ci_ini, ci_fim,
# raiz_local, pastas_falhas, pastas_criadas, falhas, apagados, sentido.
_dbx_cmd_sync_pastas_receber_criar() {
  local k rel
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && return 0
  for ((k = ci_ini; k < ci_fim; k++)); do
    rel=${dirs_v[k]}
    [[ -n $rel ]] || continue
    # A travessia remota dos ciclos e desta execucao: a pasta foi observada agora.
    _dbx_cmd_sync_pasta_local_criar "$rel" sim || return $?
  done
  return 0
}

# _dbx_cmd_sync_pastas_delta_criar — F-103, RF-212(a)(b)(c)(d), so no
# recebimento sem ciclos (delta com cursor valido): cria localmente toda pasta
# `d` da tabela (a entrada `folder` do delta e a pasta do retrato ausente
# localmente), pai antes de filho, `mkdir` NAO recursivo, no escopo dos filtros.
# So criacao: `deleted` de pasta no delta nunca remove nada aqui (a pasta so sai
# por RF-216) e nenhuma chamada de rede e feita, salvo a confirmacao do ocupante
# local (`get_metadata`, so com arquivo no lugar da pasta e --espelhar). Falha de
# item e sistemica como em `_dbx_cmd_sync_pastas_receber_criar`. Simulacao: nada
# e criado. Executor: DBX_SYNC_TAB, remoto, raiz_local, pastas_falhas,
# pastas_criadas, falhas, apagados, sentido, espelhar.
_dbx_cmd_sync_pastas_delta_criar() {
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && return 0
  local pl registro exibido rel k profundidade maxima=0 sem_barras
  local -a rels=()
  for pl in "${!DBX_SYNC_TAB[@]}"; do
    registro=${DBX_SYNC_TAB[$pl]}
    [[ $registro == d$'\t'* ]] || continue
    exibido=$registro
    for k in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
    dbx_sync_relativo "$remoto" "$exibido" || continue
    rel=$DBX_SYNC_LIDO
    [[ -n $rel && $rel != *$'\n'* ]] || continue
    dbx_filtro_ativo && dbx_filtro_pasta_excluida "$rel" && continue
    rels+=("$rel")
    sem_barras=${rel//[^\/]/}
    ((${#sem_barras} > maxima)) && maxima=${#sem_barras}
  done
  for ((profundidade = 0; profundidade <= maxima; profundidade++)); do
    for rel in ${rels[@]+"${rels[@]}"}; do
      sem_barras=${rel//[^\/]/}
      ((${#sem_barras} == profundidade)) || continue
      # RF-214, DIV-401: a tabela mistura o retrato gravado (memoria) com o delta;
      # o ocupante so e apagado se a pasta remota for confirmada nesta execucao.
      _dbx_cmd_sync_pasta_local_criar "$rel" confirmar || return $?
    done
  done
  return 0
}

# _dbx_cmd_sync_pastas_falhas_aplicar — RF-213(a), os dois sentidos: tira do plano
# do ciclo cada arquivo cuja pasta (em qualquer profundidade, pela pasta pai, que
# ja herda a falha do ancestral) nao foi criada, e o registra como falha de item
# com motivo `pasta de destino nao criada: <pasta>` (RF-208). Executor: falhas,
# pastas_falhas.
_dbx_cmd_sync_pastas_falhas_aplicar() {
  [[ ${#pastas_falhas[@]} -gt 0 ]] || return 0
  local caminho pai
  local -a restam=()
  for caminho in ${DBX_SYNC_TRANSFERIR[@]+"${DBX_SYNC_TRANSFERIR[@]}"}; do
    pai=''
    [[ $caminho == */* ]] && pai=${caminho%/*}
    if [[ -n $pai && -n ${pastas_falhas[$pai]+x} ]]; then
      falhas=$((falhas + 1))
      # Envio: a pasta e remota (erro_remoto); recebimento: e local (configuracao).
      if [[ $sentido == 'enviar' ]]; then DBX_CMD_SYNC_FALHA_CLASSE='erro_remoto'; else DBX_CMD_SYNC_FALHA_CLASSE='configuracao'; fi
      DBX_CMD_SYNC_RESUMO_FALHA="pasta de destino nao criada: ${pastas_falhas[$pai]}"
      _dbx_cmd_sync_falha_emitir "$caminho"
    else
      restam+=("$caminho")
    fi
  done
  DBX_SYNC_TRANSFERIR=(${restam[@]+"${restam[@]}"})
  # DIV-400: nada sob a pasta que falhou (nem o proprio caminho dela) e apagado.
  local acima
  restam=()
  for caminho in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    acima=$caminho
    while :; do
      [[ -n ${pastas_falhas[$acima]+x} ]] && break
      [[ $acima == */* ]] || { acima=''; break; }
      acima=${acima%/*}
    done
    [[ -n $acima ]] || restam+=("$caminho")
  done
  DBX_SYNC_APAGAR=(${restam[@]+"${restam[@]}"})
}

# _dbx_cmd_sync_pastas_plano_simular — F-103, RF-217(a)(c)(d), RF-214(e), so em
# simulacao e em ciclos: monta em `plano_pastas` (`chave<TAB>valor`) o anuncio do
# ciclo, na ordem real: por pasta do ciclo, `apagaria` do arquivo que a ocupa
# (permanece em DBX_SYNC_APAGAR, como no plano real, e conta em `apagados`) e
# `criaria pasta`. Regra de `criaria pasta`: no envio, toda pasta do ciclo ainda
# nao observada como existente no destino nesta execucao (registro `d` das
# listagens remotas ja lidas, acumuladas em `pastas_destino_vistas`; nenhuma
# chamada nova); no recebimento, a que nao e diretorio local agora (`-d`).
# Contadores contam o anunciado. Recusa de origem vazia (`recusaria`) nao anuncia.
# Executor: modo_ciclos, sentido, remoto, dirs_v, ci_ini, ci_fim, raiz_local,
# recusaria, pastas_criadas, apagados, DBX_SYNC_TAB_ORDEM, DBX_SYNC_APAGAR.
_dbx_cmd_sync_pastas_plano_simular() {
  plano_pastas=()
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' && $modo_ciclos == 'sim' ]] || return 0
  local k j pl registro exibido rel ocupada existe
  # RF-217(c): o que esta execucao planeja apagar, acumulado dos ciclos.
  for j in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
    apagar_planejado["k:${j,,}"]=1
  done
  # RF-217(d): recusa (origem vazia ou espaco) nao anuncia plano de pastas.
  [[ -z $recusaria && $pastas_recusa == 'nao' ]] || return 0
  if [[ $sentido == 'enviar' ]]; then
    for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
      registro=${DBX_SYNC_TAB[$pl]-}
      [[ $registro == d$'\t'* ]] || continue
      exibido=$registro
      for j in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
      dbx_sync_relativo "$remoto" "$exibido" || continue
      pastas_destino_vistas["k:${DBX_SYNC_LIDO,,}"]=1
    done
  fi
  for ((k = ci_ini; k < ci_fim; k++)); do
    rel=${dirs_v[k]}
    [[ -n $rel ]] || continue
    ocupada='nao'
    for j in ${DBX_SYNC_APAGAR[@]+"${DBX_SYNC_APAGAR[@]}"}; do
      [[ ${j,,} == "${rel,,}" ]] && ocupada='sim'
    done
    if [[ $sentido == 'enviar' ]]; then
      existe='nao'
      [[ -n ${pastas_destino_vistas["k:${rel,,}"]+definido} ]] && existe='sim'
    else
      existe='nao'
      [[ -d $raiz_local/$rel && ! -L $raiz_local/$rel ]] && existe='sim'
      [[ $ocupada == 'sim' && ! -e $raiz_local/$rel && ! -L $raiz_local/$rel ]] && ocupada='nao'
    fi
    if [[ $ocupada == 'sim' ]] && _dbx_cmd_sync_exclusao_antecipada_permitida "$rel"; then
      apagados=$((apagados + 1))
      plano_pastas+=("apagaria"$'\t'"$rel (arquivo no lugar da pasta)")
      existe='nao'
    fi
    if [[ $existe == 'nao' ]]; then
      pastas_criadas=$((pastas_criadas + 1))
      plano_pastas+=("criaria"$'\t'"pasta $rel")
    fi
  done
  return 0
}

# _dbx_cmd_sync_pastas_campos — RF-218(a): os quatro contadores de pasta, agregados
# dos ciclos (em simulacao, o anunciado), logo depois de `falhas`. Executor:
# pastas_criadas, pastas_apagadas, pastas_mantidas, pastas_falhou (le).
_dbx_cmd_sync_pastas_campos() {
  dbx_output_campo pastas_criadas "$pastas_criadas"
  dbx_output_campo pastas_apagadas "$pastas_apagadas"
  dbx_output_campo pastas_mantidas "$pastas_mantidas"
  dbx_output_campo pastas_falhas "$pastas_falhou"
}

# _dbx_cmd_sync_diretorios_enumerar — F-101, RF-188, DIV-378 C: antes do ciclo 1,
# enumera os DIRETORIOS da origem (local: travessia por diretorio; remota: descida
# por `list_folder` nao recursivo), ordena (DIV-384), planeja os ciclos e responde
# "ha ao menos um arquivo no escopo" pela soma das contagens. So nomes e
# contagens ficam em memoria. Variaveis do executor (escopo dinamico): dirs_v,
# cont_v, ciclos, chaves_dirs, dirs_arq, vazia_global, total_origem, podadas_dirs,
# parcial, motivo_parcial.
_dbx_cmd_sync_diretorios_enumerar() {
  local reg k
  local -a brutos=() cbrutos=()
  if [[ $sentido == 'enviar' ]]; then
    dbx_progress_mensagem "[sync] enumerando diretorios locais em: $raiz_local"
    dbx_walk_diretorios "$raiz_local" "$area/dirs_brutos" || {
      dbx_cmd_falhar nao_encontrado "nao foi possivel percorrer a raiz local: $raiz_local"
      return $?
    }
    parcial=$DBX_WALK_PARCIAL
    motivo_parcial=$DBX_WALK_MOTIVO
    podadas_dirs=${#DBX_WALK_PODADAS[@]}
    while IFS= read -r -d '' reg; do
      cbrutos+=("${reg%%$'\t'*}")
      brutos+=("${reg#*$'\t'}")
    done <"$area/dirs_brutos"
  else
    # RF-188(b), RF-189: a origem remota NAO e enumerada antes do ciclo 1. Os
    # ciclos se formam em fluxo (`_dbx_cmd_sync_ciclo_remoto_formar`): cada
    # diretorio e listado uma vez, no ciclo que o consome.
    fila_remota=('')
    remoto_fim='nao'
    dirs_v=()
    cont_v=()
    : >"$dirs_arq"
    return 0
  fi
  dbx_sync_ordem_sem_caixa brutos
  dirs_v=()
  cont_v=()
  {
    for k in ${DBX_SYNC_ORDEM[@]+"${DBX_SYNC_ORDEM[@]}"}; do
      dirs_v+=("${brutos[k]}")
      cont_v+=("${cbrutos[k]}")
      printf '%s\t%s\0' "${cbrutos[k]}" "${brutos[k]}"
      chaves_dirs["k:${brutos[k],,}"]=1
      total_origem=$((total_origem + cbrutos[k]))
    done
  } >"$dirs_arq"
  [[ $total_origem -eq 0 ]] && vazia_global='sim'
  dbx_sync_blocos_planejar dirs_v cont_v "$DBX_CMD_SYNC_BLOCO" || {
    dbx_cmd_falhar uso_invalido 'nao foi possivel planejar os ciclos'
    return $?
  }
  ciclos=(${DBX_SYNC_BLOCOS_CICLOS[@]+"${DBX_SYNC_BLOCOS_CICLOS[@]}"})
  return 0
}

# _dbx_cmd_sync_ciclo_remoto_formar — F-101, RF-188(b), RF-189: forma o PROXIMO
# ciclo de uma origem remota em fluxo. Descida em profundidade com filhos
# ordenados (DIV-384); cada diretorio e listado UMA vez (nunca recursivo) e suas
# entradas ficam na tabela do ciclo. O ciclo fecha quando os arquivos diretos
# somam N ou mais (o diretorio que cruza N entra inteiro) ou a arvore esgota. A
# fila guarda so caminhos. A sonda de origem vazia (DIV-378 C) se resolve aqui,
# no ciclo 1, antes de qualquer exclusao. Variaveis do executor: fila_remota,
# remoto_fim, dirs_v, cont_v, dirs_arq, chaves_dirs, total_origem, vazia_global,
# ciclo, ci_ini, ci_fim, formacao_falhou.
_dbx_cmd_sync_ciclo_remoto_formar() {
  local acumulado=0 dir desde total i pl registro tag exibido rel pai arquivos k estado ordem
  local -a filhos=() ordenados=()
  formacao_falhou=0
  ci_ini=${#dirs_v[@]}
  dbx_sync_tabela_zerar
  while ((${#fila_remota[@]} > 0)) || [[ $pend_ativo == 'sim' ]]; do
    if [[ $pend_ativo == 'sim' ]]; then
      # RF-187(c): o diretorio guardado do ciclo anterior ja foi listado e
      # contado; so restaura a tabela e segue, sem listar de novo.
      dir=$pend_dir
      arquivos=$pend_arquivos
      filhos=(${pend_filhos[@]+"${pend_filhos[@]}"})
      for ((i = 0; i < ${#pend_chaves[@]}; i++)); do
        pl=${pend_chaves[i]}
        DBX_SYNC_TAB[$pl]=${pend_regs[i]}
        DBX_SYNC_TAB_ORDEM+=("$pl")
        DBX_SYNC_TAB_NA_ORDEM[$pl]=1
      done
      pend_ativo='nao'
      pend_filhos=()
      pend_chaves=()
      pend_regs=()
      total=0
      desde=0
    else
      dir=${fila_remota[0]}
      if ((${#fila_remota[@]} > 1)); then fila_remota=("${fila_remota[@]:1}"); else fila_remota=(); fi
      desde=${#DBX_SYNC_TAB_ORDEM[@]}
      estado=0
      dbx_sync_listar_diretorio "$remoto" "$remoto${dir:+/$dir}" "$lado_remoto" || estado=$?
      if [[ $estado -ne 0 ]]; then
        formacao_falhou=$estado
        break
      fi
      total=${#DBX_SYNC_TAB_ORDEM[@]}
      arquivos=0
      filhos=()
    fi
    for ((i = desde; i < total; i++)); do
      pl=${DBX_SYNC_TAB_ORDEM[i]}
      registro=${DBX_SYNC_TAB[$pl]-}
      [[ -n $registro ]] || continue
      tag=${registro%%$'\t'*}
      exibido=$registro
      for k in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
      dbx_sync_relativo "$remoto" "$exibido" || continue
      rel=$DBX_SYNC_LIDO
      pai=''
      [[ $rel == */* ]] && pai=${rel%/*}
      [[ ${pai,,} == "${dir,,}" ]] || continue
      if [[ $tag == 'd' ]]; then
        dbx_filtro_ativo && dbx_filtro_pasta_excluida "$rel" && continue
        [[ -n ${chaves_dirs["k:${rel,,}"]+definido} ]] && continue
        chaves_dirs["k:${rel,,}"]=1
        filhos+=("$rel")
      else
        dbx_filtro_ativo && ! dbx_filtro_classificar "$rel" nao && continue
        arquivos=$((arquivos + 1))
      fi
    done
    if ((arquivos > DBX_CMD_SYNC_BLOCO && acumulado > 0)); then
      # RF-187(c): diretorio com mais de N arquivos forma ciclo sozinho. Guarda
      # o diretorio listado e seus registros e fecha o ciclo corrente sem ele.
      pend_ativo='sim'
      pend_dir=$dir
      pend_arquivos=$arquivos
      pend_filhos=(${filhos[@]+"${filhos[@]}"})
      pend_chaves=()
      pend_regs=()
      for ((i = desde; i < total; i++)); do
        pl=${DBX_SYNC_TAB_ORDEM[i]}
        pend_chaves+=("$pl")
        pend_regs+=("${DBX_SYNC_TAB[$pl]-}")
        unset "DBX_SYNC_TAB[$pl]" "DBX_SYNC_TAB_NA_ORDEM[$pl]"
      done
      DBX_SYNC_TAB_ORDEM=("${DBX_SYNC_TAB_ORDEM[@]:0:desde}")
      break
    fi
    chaves_dirs["k:${dir,,}"]=1
    dirs_v+=("$dir")
    cont_v+=("$arquivos")
    printf '%s\t%s\0' "$arquivos" "$dir" >>"$dirs_arq"
    total_origem=$((total_origem + arquivos))
    acumulado=$((acumulado + arquivos))
    if ((${#filhos[@]} > 0)); then
      dbx_sync_ordem_sem_caixa filhos
      ordenados=()
      for ordem in ${DBX_SYNC_ORDEM[@]+"${DBX_SYNC_ORDEM[@]}"}; do ordenados+=("${filhos[ordem]}"); done
      fila_remota=(${ordenados[@]+"${ordenados[@]}"} ${fila_remota[@]+"${fila_remota[@]}"})
    fi
    ((acumulado >= DBX_CMD_SYNC_BLOCO)) && break
  done
  ci_fim=${#dirs_v[@]}
  ciclo="$ci_ini-$ci_fim"
  if ((formacao_falhou != 0)) || { ((${#fila_remota[@]} == 0)) && [[ $pend_ativo != 'sim' ]]; }; then remoto_fim='sim'; fi
  if ((ciclo_i == 0 && formacao_falhou == 0)); then
    [[ $total_origem -eq 0 ]] && vazia_global='sim'
  fi
  return 0
}

# _dbx_cmd_sync_parada_sistemica — RF-193, DIV-380 C: em ciclos, falha de
# transferencia que vale para todos os arquivos (autenticacao, permissao, ou
# limite_taxa/rede com as tentativas esgotadas pela camada http) para a execucao
# com o relatorio de ciclos; falha so do arquivo segue. Variaveis do executor:
# modo_ciclos, ciclo_i, ciclo_falho, codigo_parada. Status 0 quando parou.
_dbx_cmd_sync_parada_sistemica() {
  [[ $modo_ciclos == 'sim' ]] || return 1
  case ${DBX_CMD_SYNC_FALHA_CLASSE:-} in
    autenticacao | permissao | limite_taxa | rede) ;;
    *) return 1 ;;
  esac
  # So a falha vinda do servidor e sistemica; erro de escrita local e do arquivo.
  [[ ${DBX_HTTP_CLASSE:-} == "$DBX_CMD_SYNC_FALHA_CLASSE" ]] || return 1
  ciclo_falho=$ciclo_i
  codigo_parada=$(dbx_errors_codigo_saida "$DBX_CMD_SYNC_FALHA_CLASSE")
  return 0
}

# _dbx_cmd_sync_ciclo_proximo — entrega o proximo ciclo em `ciclo`, `ci_ini` e
# `ci_fim`, ou devolve 1 quando acabaram. Remota em ciclos: forma em fluxo;
# demais: o plano da enumeracao previa (ou o ciclo unico).
_dbx_cmd_sync_ciclo_proximo() {
  if [[ $modo_ciclos == 'sim' && $sentido == 'receber' ]]; then
    [[ $remoto_fim == 'sim' ]] && return 1
    _dbx_cmd_sync_ciclo_remoto_formar
    return 0
  fi
  ((ciclo_i < ${#ciclos[@]})) || return 1
  ciclo=${ciclos[ciclo_i]}
  ci_ini=${ciclo%-*}
  ci_fim=${ciclo#*-}
  return 0
}

# --- RF-216: exclusao de pasta orfa no --espelhar (F-103; DESTRUTIVA) -----------
#
# Fonte da lista (so o que ESTA execucao leu, RF-216(i)): envio = registros `d`
# da tabela do ciclo que a descida do destino remoto listou por inteiro e que a
# origem nao tem (RF-190(b)); recebimento = subdiretorios vistos pela travessia
# local do ciclo que a origem nao tem, mais o que ha sob eles no disco. A decisao
# de apagar sai do que se leu AGORA: o remoto e relido imediatamente antes e o
# local so cede a `rmdir` nao recursivo.

# _dbx_cmd_sync_pastas_orfas_registrar <relativo> — RF-216(a)(f): guarda a pasta
# candidata (sem repeticao, sem nome com quebra de linha). Pasta excluida por
# RF-80 nunca entra. Executor: pastas_orfas, pastas_vistas.
_dbx_cmd_sync_pastas_orfas_registrar() {
  local rel=$1
  [[ -n $rel && $rel != *$'\n'* ]] || return 0
  [[ -n ${pastas_vistas["k:${rel,,}"]+definido} ]] && return 0
  dbx_filtro_ativo && dbx_filtro_pasta_excluida "$rel" && return 0
  pastas_vistas["k:${rel,,}"]=1
  pastas_orfas+=("$rel")
}

# _dbx_cmd_sync_pastas_orfas_remotas — RF-216(b)(h), envio: candidatas do ciclo.
# A tabela so tem pastas de diretorios listados por inteiro (ciclo e ramos so do
# destino; erro de pagina derruba o ciclo antes daqui). Executor: chaves_dirs, remoto.
_dbx_cmd_sync_pastas_orfas_remotas() {
  local pl registro exibido rel k
  for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
    registro=${DBX_SYNC_TAB[$pl]-}
    [[ $registro == d$'\t'* ]] || continue
    exibido=$registro
    for k in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
    dbx_sync_relativo "$remoto" "$exibido" || continue
    rel=$DBX_SYNC_LIDO
    [[ -n ${chaves_dirs["k:${rel,,}"]+definido} ]] && continue
    _dbx_cmd_sync_pastas_orfas_registrar "$rel"
  done
  _dbx_cmd_sync_observados_acumular
  return 0
}

# _dbx_cmd_sync_observados_acumular — RF-217(c), so em simulacao: guarda, do que
# a tabela do ciclo observou no destino remoto, `tipo<TAB>relativo` de cada item
# (filtrado inclusive), para saber se uma pasta orfa ficaria vazia. Nada vem de
# memoria, retrato ou cursor. Executor: observados_destino, DBX_SYNC_TAB, remoto.
_dbx_cmd_sync_observados_acumular() {
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' && ${espelhar:-nao} == 'sim' ]] || return 0
  local pl registro exibido k tipo
  for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
    registro=${DBX_SYNC_TAB[$pl]-}
    [[ -n $registro ]] || continue
    tipo=f
    [[ $registro == d$'\t'* ]] && tipo=d
    exibido=$registro
    for k in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
    dbx_sync_relativo "$remoto" "$exibido" || continue
    observados_destino+=("$tipo"$'\t'"$DBX_SYNC_LIDO")
  done
  return 0
}

# _dbx_cmd_sync_pasta_orfa_ficara_vazia <relativo> — RF-217(c): status 0 quando
# todo item observado sob a pasta nesta execucao (remoto: tabela dos ciclos;
# local: leitura do disco agora, sem seguir ligacao) esta nas exclusoes
# planejadas (arquivo) ou ja anunciado como pasta a apagar (subpasta, filhos
# antes do pai). Item filtrado nunca entra no plano e, portanto, bloqueia.
# Executor: observados_destino, apagar_planejado, pastas_apagaria_set.
_dbx_cmd_sync_pasta_orfa_ficara_vazia() {
  local prefixo=${1,,}/ item tipo rel
  if [[ $sentido == 'enviar' ]]; then
    [[ ${#observados_destino[@]} -gt 0 ]] || return 0
    for item in ${observados_destino[@]+"${observados_destino[@]}"}; do
      tipo=${item%%$'\t'*}
      rel=${item#*$'\t'}
      [[ ${rel,,} == "$prefixo"* ]] || continue
      if [[ $tipo == 'd' ]]; then
        [[ -n ${pastas_apagaria_set["k:${rel,,}"]+definido} ]] || return 1
      else
        [[ -n ${apagar_planejado["k:${rel,,}"]+definido} ]] || return 1
      fi
    done
    return 0
  fi
  while IFS= read -r -d '' item; do
    rel=${item#"$raiz_local"/}
    if [[ -d $item && ! -L $item ]]; then
      [[ -n ${pastas_apagaria_set["k:${rel,,}"]+definido} ]] || return 1
    else
      [[ -n ${apagar_planejado["k:${rel,,}"]+definido} ]] || return 1
    fi
  done < <(find -P "$raiz_local/$1" -mindepth 1 -print0 2>/dev/null)
  return 0
}

# _dbx_cmd_sync_pastas_cobertas_pela_origem — RF-216(a): preenche o mapa
# `cobertas` do chamador (`k:<ancestral minusculo>`) com cada pasta que a origem remota cobre por algum
# item da tabela (Dropbox ignora a caixa; mesma chave de `chaves_dirs`). Pasta
# local com item da origem sob ela nunca e orfa. Executor: cobertas, DBX_SYNC_TAB, remoto.
_dbx_cmd_sync_pastas_cobertas_pela_origem() {
  local pl registro exibido rel k
  for pl in ${DBX_SYNC_TAB_ORDEM[@]+"${DBX_SYNC_TAB_ORDEM[@]}"}; do
    registro=${DBX_SYNC_TAB[$pl]-}
    [[ -n $registro ]] || continue
    exibido=$registro
    for k in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
    dbx_sync_relativo "$remoto" "$exibido" || continue
    rel=$DBX_SYNC_LIDO
    while [[ $rel == */* ]]; do
      rel=${rel%/*}
      [[ -n ${cobertas["k:${rel,,}"]+definido} ]] && break
      cobertas["k:${rel,,}"]=1
    done
  done
  return 0
}

# _dbx_cmd_sync_pastas_orfas_locais <arquivo de subdiretorios> — RF-216(b)(h),
# recebimento: subdiretorio do ciclo ausente da origem, e as pastas sob ele (lidas
# agora do disco, sem seguir ligacao). Executor: chaves_dirs, raiz_local.
_dbx_cmd_sync_pastas_orfas_locais() {
  local arq=$1 reg sub
  local -A cobertas=()
  [[ -r $arq ]] || return 0
  _dbx_cmd_sync_pastas_cobertas_pela_origem
  while IFS= read -r -d '' reg; do
    [[ -n ${chaves_dirs["k:${reg,,}"]+definido} ]] && continue
    # A origem lista algum item sob a pasta: ela existe la (sem caixa).
    [[ -n ${cobertas["k:${reg,,}"]+definido} ]] && continue
    [[ -d $raiz_local/$reg && ! -L $raiz_local/$reg ]] || continue
    while IFS= read -r -d '' sub; do
      _dbx_cmd_sync_pastas_orfas_registrar "${sub#"$raiz_local"/}"
    done < <(find -P "$raiz_local/$reg" -type d -print0 2>/dev/null)
  done <"$arq"
  return 0
}

# _dbx_cmd_sync_pastas_orfas_remota_vazia <pasta remota> — RF-216(e): lista a
# pasta (nao recursivo, todas as paginas) NESTA execucao. 0 = zero entradas;
# 2 = tem entrada; 1 = erro ou listagem incerta (nao apagar).
_dbx_cmd_sync_pastas_orfas_remota_vazia() {
  local corpo url estado quantidade pagina=1 anterior=''
  dbx_json_escapar_cadeia "$1"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"recursive\":false}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  url='https://api.dropboxapi.com/2/files/list_folder'
  while :; do
    if [[ $pagina -eq 1 ]]; then
      dbx_auth_colecao POST "$url" "$corpo" "$DBX_SYNC_LIMITE_PAGINA"
    else
      dbx_auth_requisitar POST "$url" "$_DBX_SYNC_CORPO" sim
    fi
    estado=$?
    _DBX_SYNC_CORPO=''
    [[ $estado -eq 0 ]] || return 1
    _dbx_cmd_analisar_corpo || return 1
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=1
    if [[ ! $quantidade =~ ^[0-9]+$ || $quantidade -gt 0 ]]; then
      _dbx_cmd_encerrar_consulta
      return 2
    fi
    _dbx_sync_pagina_seguinte "$anterior"
    estado=$?
    _dbx_cmd_encerrar_consulta
    [[ $estado -eq 1 ]] && return 0
    if [[ $estado -eq 2 || $pagina -ge $DBX_SYNC_TETO_PAGINAS ]]; then
      DBX_SYNC_CURSOR_NOVO=''
      return 1
    fi
    anterior=$DBX_SYNC_CURSOR_NOVO
    pagina=$((pagina + 1))
    _dbx_sync_corpo_continue "$anterior"
    url='https://api.dropboxapi.com/2/files/list_folder/continue'
  done
}

# _dbx_cmd_sync_pastas_orfas_apagar_remota <relativo> — RF-216(e), DIV-402: a
# releitura confirma pasta vazia; so entao `delete_v2` da PROPRIA pasta (lixeira),
# uma por chamada. Define _DBX_CMD_SYNC_PASTA_MOTIVO e devolve 0 quando apagou.
# Executor: remoto (le); nada do escopo dinamico e escrito.
_DBX_CMD_SYNC_PASTA_MOTIVO=''
_dbx_cmd_sync_pastas_orfas_apagar_remota() {
  local caminho="$remoto/$1" estado corpo
  _dbx_cmd_sync_pastas_orfas_remota_vazia "$caminho"
  estado=$?
  if [[ $estado -eq 2 ]]; then _DBX_CMD_SYNC_PASTA_MOTIVO='nao vazia na releitura'; return 1; fi
  if [[ $estado -ne 0 ]]; then _DBX_CMD_SYNC_PASTA_MOTIVO='releitura falhou'; return 1; fi
  dbx_json_escapar_cadeia "$caminho"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\"}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  if ! _dbx_cmd_escrita_remota 'https://api.dropboxapi.com/2/files/delete_v2' "$corpo"; then
    _DBX_CMD_SYNC_PASTA_MOTIVO='exclusao nao confirmada'
    return 1
  fi
  _dbx_cmd_encerrar_consulta
  return 0
}

# _dbx_cmd_sync_pastas_orfas_apagar_local <relativo> — RF-216(d): `rmdir` nao
# recursivo; ligacao simbolica no caminho (ou na propria pasta) = mantida.
# Executor: raiz_local (le); nada do escopo dinamico e escrito.
_dbx_cmd_sync_pastas_orfas_apagar_local() {
  local rel=$1 acumulado=$raiz_local resto=$1 comp
  [[ -n $rel && -n $raiz_local ]] || { _DBX_CMD_SYNC_PASTA_MOTIVO='caminho vazio'; return 1; }
  while [[ -n $resto ]]; do
    comp=${resto%%/*}
    if [[ $resto == */* ]]; then resto=${resto#*/}; else resto=''; fi
    acumulado="$acumulado/$comp"
    if [[ -L $acumulado ]]; then _DBX_CMD_SYNC_PASTA_MOTIVO='ligacao simbolica'; return 1; fi
  done
  if [[ ! -d $acumulado ]]; then _DBX_CMD_SYNC_PASTA_MOTIVO='nao e pasta'; return 1; fi
  if ! rmdir -- "${acumulado:?}" 2>/dev/null; then
    dbx_debug_linha pasta operacao=rmdir resultado=falha caminho="$rel"
    _DBX_CMD_SYNC_PASTA_MOTIVO='nao vazia (ENOTEMPTY) ou nao removivel'
    return 1
  fi
  dbx_debug_linha pasta operacao=rmdir resultado=ok caminho="$rel"
  return 0
}

# _dbx_cmd_sync_pastas_orfas_apagar — RF-216(b)(c)(g): depois de TODOS os ciclos
# e de suas exclusoes de arquivo (RF-215(c)), filhos antes do pai. Nao age com
# bloqueio (origem vazia, leitura parcial, ciclo falho, exclusao desabilitada),
# ou sem --espelhar; em simulacao so anuncia (RF-217). A raiz nunca e candidata (RF-216(j)). Executor:
# pastas_orfas, pastas_bloqueio, pastas_apagadas, pastas_mantidas, ciclo_falho, parcial.
_dbx_cmd_sync_pastas_orfas_apagar() {
  [[ ${espelhar:-nao} == 'sim' && $pastas_bloqueio == 'nao' &&
    $ciclo_falho -eq 0 && $parcial != 'sim' && ${#pastas_orfas[@]} -gt 0 &&
    $pastas_recusa == 'nao' ]] || return 0
  local rel profundidade maxima=0 sem_barras
  for rel in ${pastas_orfas[@]+"${pastas_orfas[@]}"}; do
    sem_barras=${rel//[^\/]/}
    ((${#sem_barras} > maxima)) && maxima=${#sem_barras}
  done
  for ((profundidade = maxima; profundidade >= 0; profundidade--)); do
    for rel in ${pastas_orfas[@]+"${pastas_orfas[@]}"}; do
      sem_barras=${rel//[^\/]/}
      ((${#sem_barras} == profundidade)) || continue
      _DBX_CMD_SYNC_PASTA_MOTIVO=''
      # RF-217(a)(c), simulacao: anuncia `apagaria pasta`, sem releitura nem escrita.
      if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
        if _dbx_cmd_sync_exclusao_antecipada_permitida "$rel" &&
          _dbx_cmd_sync_pasta_orfa_ficara_vazia "$rel"; then
          pastas_apagadas=$((pastas_apagadas + 1))
          pastas_apagaria+=("pasta $rel")
          pastas_apagaria_set["k:${rel,,}"]=1
        fi
        continue
      fi
      if ! _dbx_cmd_sync_exclusao_antecipada_permitida "$rel"; then
        _DBX_CMD_SYNC_PASTA_MOTIVO='fora do escopo ou exclusao desabilitada'
      elif [[ $sentido == 'enviar' ]]; then
        _dbx_cmd_sync_pastas_orfas_apagar_remota "$rel" && _DBX_CMD_SYNC_PASTA_MOTIVO='ok'
      else
        _dbx_cmd_sync_pastas_orfas_apagar_local "$rel" && _DBX_CMD_SYNC_PASTA_MOTIVO='ok'
      fi
      if [[ $_DBX_CMD_SYNC_PASTA_MOTIVO == 'ok' ]]; then
        pastas_apagadas=$((pastas_apagadas + 1))
        dbx_cmd_avisar "pasta apagada: $rel"
      else
        pastas_mantidas=$((pastas_mantidas + 1))
        dbx_cmd_avisar "pasta mantida: $rel ($_DBX_CMD_SYNC_PASTA_MOTIVO)"
      fi
    done
  done
  return 0
}

# _dbx_cmd_sync_ramos_destino_remotos — RF-190(b): pasta FILHA de um diretorio do
# ciclo que existe so no destino remoto (nao esta no conjunto de diretorios da
# origem) e lida inteira, descendo de pasta em pasta (nunca recursivo), NO ciclo
# que a encontra: o plano do ciclo ve o ramo todo e a exclusao dele so sai com o
# pai lido por inteiro nos dois lados. Custo: o ramo so do destino e lido sem
# corte por N. Variaveis do executor: ci_ini, ci_fim, dirs_v, chaves_dirs.
_dbx_cmd_sync_ramos_destino_remotos() {
  local -A pais=() visitados=()
  local -a fila=()
  local k pl registro exibido rel pai dir total desde=0
  for ((k = ci_ini; k < ci_fim; k++)); do
    pais["k:${dirs_v[k],,}"]=1
  done
  while :; do
    total=${#DBX_SYNC_TAB_ORDEM[@]}
    for ((; desde < total; desde++)); do
      pl=${DBX_SYNC_TAB_ORDEM[desde]}
      registro=${DBX_SYNC_TAB[$pl]-}
      [[ $registro == d$'\t'* ]] || continue
      exibido=$registro
      for k in 1 2 3 4 5 6; do exibido=${exibido#*$'\t'}; done
      dbx_sync_relativo "$remoto" "$exibido" || continue
      rel=$DBX_SYNC_LIDO
      pai=''
      [[ $rel == */* ]] && pai=${rel%/*}
      [[ -n ${pais["k:${pai,,}"]+definido} ]] || continue
      [[ -n ${visitados["k:${rel,,}"]+definido} ]] && continue
      [[ -n ${chaves_dirs["k:${rel,,}"]+definido} ]] && continue
      dbx_filtro_ativo && dbx_filtro_pasta_excluida "$rel" && continue
      visitados["k:${rel,,}"]=1
      pais["k:${rel,,}"]=1
      fila+=("$rel")
    done
    [[ ${#fila[@]} -gt 0 ]] || break
    dir=${fila[0]}
    fila=("${fila[@]:1}")
    dbx_sync_listar_diretorio "$remoto" "$remoto/$dir" "$lado_remoto" || return $?
  done
  return 0
}
