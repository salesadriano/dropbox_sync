#!/usr/bin/env bash
# cmd.sh — servicos comuns aos comandos.
#
# EXISTE POR CAUSA DA FAMILIA DE GEMEOS. Sete ocorrencias ate aqui, quatro entre
# arquivos, todas com a mesma forma: a regra estava escrita e aplicada a um dos
# lugares onde incidia. Os comandos deste bloco tem paridades obvias — `upload`
# com `download`, `delete` com `upload` na concorrencia otimista, `list` com
# `info` na leitura de metadado. Em vez de escrever a regra em cada um e torcer
# para lembrar do vizinho, o que e paritario mora AQUI e e chamado pelos dois.
#
# Cada auxiliar declara qual e o conjunto de lugares onde incide, conforme a
# regra adotada no fechamento da Etapa 3: regra de disciplina sem conjunto
# enumerado protege o lugar onde foi escrita e nenhum outro.

[[ -n ${DBX_CMD_CARREGADO:-} ]] && return 0
DBX_CMD_CARREGADO=1

_dbx_cmd_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_cmd_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_cmd_diretorio=.
_dbx_cmd_diretorio=$(cd -P -- "$_dbx_cmd_diretorio" && pwd -P)
# shellcheck source=lib/hash.sh
. "$_dbx_cmd_diretorio/hash.sh"
unset _dbx_cmd_diretorio

# shellcheck disable=SC2034
# Justificativa: canal publico consumido pelos arquivos de `commands/`.
DBX_CMD_LIDO=''
# shellcheck disable=SC2034
# Justificativa: canal publico consumido pelos arquivos de `commands/`.
DBX_CMD_SIMULADO='nao'
# Marca do temporario de recebimento: `.<nome>.dbx-part.XXXXXX`. E por ela que o
# `sync` reconhece um temporario orfao e o deixa fora da arvore local.
readonly DBX_CMD_MARCA_RECEBIMENTO='.dbx-part.'
# Temporario em curso, global para o tratador de sinal o alcancar.
DBX_CMD_TEMPORARIO_RECEBIMENTO=''
# shellcheck disable=SC2034
# Justificativa: canais publicos de `dbx_cmd_receber_arquivo`, lidos pelos comandos.
DBX_CMD_INTEGRIDADE='nao_aplicavel'
# shellcheck disable=SC2034
DBX_CMD_CONTENT_HASH=''
# shellcheck disable=SC2034
DBX_CMD_FALHA_CLASSE=''
# shellcheck disable=SC2034
DBX_CMD_FALHA_MOTIVO=''

# SINCRONIZACAO DO RAMO DE VALIDACAO EM FLUXO — medido, nao suposto.
#
# A decisao de emitir e validar em paralelo poe o veredito DEPOIS do ultimo
# byte. O idioma obvio para isso nao serve:
#
#   tee >(dbx_hash_conteudo_fluxo_com_tamanho >arquivo) ... ; wait
#
# `wait` NAO espera substituicao de processo. Medido duas vezes, de forma
# independente: o arquivo esta VAZIO logo apos o `wait` e so aparece cerca de
# 600 ms depois. Processo em segundo plano com `wait $pid` devolve correto de
# imediato.
#
# A consequencia especifica, que e o motivo de isto estar escrito: um download
# PERFEITO produziria resumo vazio, divergencia falsa e codigo de integridade
# (11) — de forma intermitente e dependente de carga, ou seja, diagnosticado
# como corrupcao onde nao ha nenhuma. E o tipo de defeito que o diario de
# reprovacoes existe para capturar depois, e que sai mais barato nao criar.
#
# Conjunto onde incide: TODO caminho que valide conteudo enquanto o emite —
# `download` agora, e o recebimento recursivo e o `sync` depois.

# dbx_cmd_falhar <classe> <texto> — diagnostico redigido e codigo da taxonomia.
# Conjunto onde incide: TODO caminho de recusa de TODO comando.
dbx_cmd_falhar() {
  local classe=$1 texto=$2
  dbx_cmd_iniciar_saida
  dbx_output_diagnostico erro "$texto"
  dbx_output_render_diagnostico >&2
  return "$(dbx_errors_codigo_saida "$classe")"
}

# dbx_cmd_iniciar_saida — aplica as opcoes globais ao modelo de resultado.
# Conjunto onde incide: TODA emissao, de resultado ou de diagnostico.
dbx_cmd_iniciar_saida() {
  dbx_output_iniciar
  [[ ${DBX_CLI_ESTRUTURADA:-nao} == 'sim' ]] && dbx_output_modo estruturada
  [[ ${DBX_CLI_NULO:-nao} == 'sim' ]] && dbx_output_terminador nulo
  return 0
}

# _dbx_cmd_consultar <url> <corpo> — chamada autenticada de leitura.
#
# Conjunto onde incide: todo comando que consulta sem escrever. Comando de
# ESCRITA nao usa este auxiliar, porque precisa passar por `_dbx_cmd_simulacao`
# antes — separar os dois evita que uma escrita herde por engano um caminho que
# nao verifica o modo de simulacao (RF-15).
_dbx_cmd_consultar() {
  local url=$1 corpo=$2 estado
  dbx_auth_requisitar POST "$url" "$corpo" sim
  estado=$?
  [[ $estado -eq 0 ]] || {
    # O resumo de erro vem do servico e vai para o canal de diagnostico, que
    # redige; o corpo bruto nunca e publicado.
    dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "chamada recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  _dbx_cmd_analisar_corpo
  return $?
}

# _dbx_cmd_analisar_corpo — poe o corpo da ultima resposta em contexto proprio.
#
# Conjunto onde incide: TODA leitura de resposta, seja de chamada simples ou de
# colecao. `dbx_http_colecao` DESCARTA o documento antes de retornar — ele
# analisa so para decidir se precisa reduzir o limite. Quem quiser ler os campos
# analisa de novo. Eu havia escrito o contrario num comentario de `list`, e a
# listagem saia vazia.
_dbx_cmd_analisar_corpo() {
  dbx_json_contexto comando || {
    dbx_cmd_falhar erro_remoto 'contexto de analise indisponivel'
    return $?
  }
  if ! dbx_json_analisar "$DBX_HTTP_CORPO"; then
    local motivo=$DBX_JSON_MOTIVO
    dbx_json_descartar comando
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    dbx_cmd_falhar erro_remoto "resposta nao interpretavel: $motivo"
    return $?
  fi
  return 0
}

# _dbx_cmd_caminho_remoto <caminho> — normaliza sem poluir a saida padrao.
#
# Conjunto onde incide: TODO comando que recebe caminho remoto. A funcao de
# lib/path IMPRIME o resultado alem de publica-lo no canal; num comando isso cai
# no meio da saida estruturada e quebra o consumidor automatizado (RF-28).
_dbx_cmd_caminho_remoto() {
  dbx_path_remoto_para_api "$1" >/dev/null || return $?
  # shellcheck disable=SC2153  # canal publico de lib/path, carregada por bin/dbx
  DBX_CMD_LIDO=$DBX_PATH_RESULTADO
  return 0
}

# _dbx_cmd_encerrar_consulta — descarta o documento e os canais adjacentes.
# Conjunto onde incide: toda saida de `_dbx_cmd_consultar` bem sucedida.
_dbx_cmd_encerrar_consulta() {
  dbx_json_descartar comando
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # shellcheck disable=SC2034  # canais publicos alheios, limpos aqui
  DBX_JSON_RESULTADO=''
  # shellcheck disable=SC2034  # canais publicos alheios, limpos aqui
  DBX_HTTP_CORPO=''
  return 0
}

# _dbx_cmd_campo <segmentos...> — le um campo do documento corrente.
_dbx_cmd_campo() {
  DBX_CMD_LIDO=''
  dbx_json_valor "$@" >/dev/null || return 1
  DBX_CMD_LIDO=$DBX_JSON_RESULTADO
  return 0
}

# _dbx_cmd_metadado_em <segmentos...> — emite os campos de metadado de um item.
#
# Conjunto onde incide: `info` sobre a raiz do documento e `list` sobre cada
# entrada. Escrever a leitura duas vezes faria a proxima correcao valer para um
# lado so, que e exatamente a forma das sete ocorrencias anteriores.
_dbx_cmd_metadado_em() {
  local campo
  _dbx_cmd_campo "$@" '.tag' && dbx_output_campo tipo "$DBX_CMD_LIDO"
  for campo in name path_display size rev content_hash client_modified server_modified; do
    if _dbx_cmd_campo "$@" "$campo"; then
      dbx_output_campo "$campo" "$DBX_CMD_LIDO"
    fi
  done
  return 0
}

# _dbx_cmd_escrita_remota <url> <corpo> — unico caminho de ESCRITA remota.
#
# CONJUNTO ONDE INCIDE: os TRES pontos de escrita do produto — `delete`,
# `upload` e, adiante, `sync`. Nasce generico de proposito: escrever isto como
# auxiliar de dois e descobrir o terceiro depois e a forma exata das oito
# ocorrencias da familia de gemeos. Quem acrescentar um quarto ponto de escrita
# passa por aqui ou nao passa pela disciplina.
#
# Tres garantias, todas aqui e em nenhum outro lugar:
#
#   RF-15  simulacao: nenhuma chamada de escrita e emitida, o plano e impresso
#          e o codigo de saida e zero. A verificacao vem ANTES da chamada, e
#          nao dentro dela, para que nao exista caminho de escrita que a pule.
#
#   RF-49  concorrencia otimista: quando o chamador informa o `rev` esperado,
#          ele viaja no corpo. A Dropbox recusa se o remoto mudou desde a
#          leitura daquela execucao, e a recusa vira CONFLITO (codigo 7) em vez
#          de sobrescrita cega. Sem isso, "mudou no meio" e indistinguivel de
#          "deu certo".
#
#   O corpo de erro alimenta a taxonomia, e nunca a apresentacao de resultado.
_dbx_cmd_escrita_remota() {
  local url=$1 corpo=$2 estado

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    # shellcheck disable=SC2034  # canal publico, consumido pelos comandos
    DBX_CMD_SIMULADO='sim'
    return 0
  fi
  # shellcheck disable=SC2034  # canal publico, consumido pelos comandos
  DBX_CMD_SIMULADO='nao'

  # Escrita nao e idempotente: repetir as cegas pode aplicar duas vezes.
  dbx_auth_requisitar POST "$url" "$corpo" nao
  estado=$?
  [[ $estado -eq 0 ]] && {
    _dbx_cmd_analisar_corpo
    return $?
  }

  local classe=${DBX_HTTP_CLASSE:-erro_remoto}
  # PERGUNTA EM ABERTO, e ela e o motivo desta linha existir.
  #
  # `dbx_errors_classificar` NAO classifica por status: classifica pela TAG do
  # resumo. Medido:
  #
  #   409 + conflict/file/...        -> conflito
  #   409 + (vazio)                  -> desconhecido
  #   409 + too_many_write_operations-> limite_taxa
  #   500 + conflict/y               -> erro_remoto
  #
  # Ou seja, a taxonomia e este `case` olham O MESMO SINAL — a tag — e por isso
  # um cobre o outro quando a tag e `conflict`. Eu havia registrado que a
  # taxonomia classificava por `409`; era falso, e a correcao muda o cenario que
  # torna esta linha necessaria.
  #
  # O cenario discriminante nao e "recusa sem 409"; e recusa por `rev`
  # divergente COM 409 e tag DIFERENTE de `conflict` — caso em que sem este
  # mapeamento a classe sairia `desconhecido` e a concorrencia otimista perderia
  # a unica informacao que produz.
  #
  # A pergunta precisa, para a verificacao contra o servico real: QUAL E A TAG
  # EXATA que a Dropbox devolve ao recusar escrita por `rev` divergente? Se for
  # `conflict`, esta linha e redundante e sai. Se for outra, e a unica coisa que
  # produz a classificacao certa, e ganha caso que a exercita. Nao ha caso hoje
  # que a discrimine, e inventar um status para a fazer parecer necessaria seria
  # fabricar contrato.
  case ${DBX_HTTP_RESUMO_DE_ERRO:-} in
    *conflict*) classe='conflito' ;;
  esac
  dbx_cmd_falhar "$classe" \
    "escrita recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
  return $?
}

# dbx_cmd_content_hash_do_resultado — le o `content_hash` que o servico publicou
# no cabecalho `Dropbox-API-Result` da ultima resposta. Resultado em
# DBX_CMD_LIDO; vazio quando o servico nao o publicou.
dbx_cmd_content_hash_do_resultado() {
  DBX_CMD_LIDO=''
  [[ -n ${DBX_HTTP_RESULTADO_CABECALHO:-} ]] || return 0
  dbx_json_contexto resultado >/dev/null 2>&1 || return 0
  if dbx_json_analisar "$DBX_HTTP_RESULTADO_CABECALHO" >/dev/null 2>&1 &&
    dbx_json_valor content_hash >/dev/null 2>&1; then
    DBX_CMD_LIDO=$DBX_JSON_RESULTADO
  fi
  dbx_json_descartar resultado >/dev/null 2>&1
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR" >/dev/null 2>&1
  return 0
}

# _dbx_cmd_recebimento_interrompido — tratador de INT, TERM e HUP do recebimento.
#
# Encerra o PROCESSO: o alvo continua o anterior, e seguir depois de um sinal
# trataria como concluido um recebimento que nao terminou. `exit` nao passa
# pela limpeza de `_dbx_http_executar`, entao a area dela sai daqui tambem.
_dbx_cmd_recebimento_interrompido() {
  [[ -n $DBX_CMD_TEMPORARIO_RECEBIMENTO ]] && rm -f -- "$DBX_CMD_TEMPORARIO_RECEBIMENTO"
  [[ -n ${DBX_HTTP_AREA_TEMP:-} ]] && rm -rf -- "$DBX_HTTP_AREA_TEMP"
  exit "$(dbx_errors_codigo_saida nao_concluida)"
}

# _dbx_cmd_alvo_somente_leitura <alvo> — 0 quando o alvo e arquivo existente sem
# escrita para o usuario; publica a recusa nos canais de falha local.
_dbx_cmd_alvo_somente_leitura() {
  [[ -f $1 && ! -w $1 ]] || return 1
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_CMD_FALHA_CLASSE='permissao'
  # shellcheck disable=SC2034
  DBX_CMD_FALHA_MOTIVO="destino somente leitura, nao substituido: $1"
  return 0
}

# dbx_cmd_receber_arquivo <caminho_remoto_api> <alvo> — recebimento atomico
# (RF-55).
#
# Conjunto onde incide: TODO recebimento gravado em arquivo — `download` com
# destino e `sync --receber`. Saida padrao continua em fluxo e nao passa aqui.
#
# O conteudo vai para um temporario no MESMO diretorio do alvo, para que a
# troca seja um `rename` atomico no mesmo sistema de arquivos; o alvo so e
# substituido depois de o `content_hash` local conferir com o publicado. Queda
# de rede ou resumo divergente descartam o temporario e deixam o alvo como
# estava. Sem resumo publicado nao ha o que conferir, e a integridade fica
# `nao_aplicavel` em vez de afirmada.
#
# Arquivo existente sem escrita para o usuario NAO e substituido (decisao do
# solicitante): a renomeacao contornaria a protecao que ele pos no arquivo. A
# recusa e `permissao` — e falta de permissao de escrita, e nao divergencia de
# tipo ou de versao, que e o que `conflito` descreve. Confere-se antes de
# transferir, para nao gastar a transferencia, e de novo antes da troca, porque
# o modo pode mudar enquanto o conteudo chega.
#
# O modo do arquivo novo e o do alvo que ele substitui, ou o do `umask` do
# chamador quando o alvo nao existe: `mktemp` cria em 0600, e deixar assim
# trocaria a permissao do arquivo do usuario a cada recebimento.
#
# Alvo que existe e nao e arquivo regular (diretorio, dispositivo, cano) recebe
# em fluxo direto: renomear por cima dele substituiria o proprio no.
#
# Canais: DBX_CMD_INTEGRIDADE (`conferida` ou `nao_aplicavel`), DBX_CMD_CONTENT_HASH,
# e, na falha local, DBX_CMD_FALHA_CLASSE e DBX_CMD_FALHA_MOTIVO. Falha de
# transporte deixa os dois ultimos vazios e os canais de lib/http intactos.
dbx_cmd_receber_arquivo() {
  local remoto=$1 alvo=$2
  local argumento diretorio nome temporario modo estado obtido
  DBX_CMD_INTEGRIDADE='nao_aplicavel'
  DBX_CMD_CONTENT_HASH=''
  DBX_CMD_FALHA_CLASSE=''
  DBX_CMD_FALHA_MOTIVO=''

  dbx_json_escapar_cadeia "$remoto"
  argumento="{\"path\":\"$DBX_JSON_ESCAPADO\"}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''

  if [[ -L $alvo ]]; then
    # Leitura ate o byte nulo, como em `lib/path`: `$( )` cortaria as quebras de
    # linha finais do caminho e resolveria outro arquivo.
    IFS= read -r -d '' alvo < <(readlink -f -- "$2" && printf '\0') || {
      DBX_CMD_FALHA_CLASSE='configuracao'
      DBX_CMD_FALHA_MOTIVO="vinculo simbolico de destino nao resolvido: $2"
      return "$(dbx_errors_codigo_saida configuracao)"
    }
    alvo=${alvo%$'\n'} # readlink acrescenta exatamente uma quebra de linha
  fi

  if [[ -e $alvo && ! -f $alvo ]]; then
    dbx_auth_conteudo_receber GET 'https://content.dropboxapi.com/2/files/download' \
      "$argumento" "$alvo"
    return $?
  fi

  _dbx_cmd_alvo_somente_leitura "$alvo" && return "$(dbx_errors_codigo_saida permissao)"

  diretorio=${alvo%/*}
  [[ $diretorio == "$alvo" ]] && diretorio=.
  [[ -z $diretorio ]] && diretorio=/
  nome=${alvo##*/}
  # O nome do temporario precisa caber no limite de 255 bytes por componente.
  temporario=$(mktemp -- "$diretorio/.${nome:0:200}${DBX_CMD_MARCA_RECEBIMENTO}XXXXXX" 2>/dev/null) || {
    DBX_CMD_FALHA_CLASSE='configuracao'
    DBX_CMD_FALHA_MOTIVO="nao foi possivel criar o temporario de recebimento em: $diretorio"
    return "$(dbx_errors_codigo_saida configuracao)"
  }

  # Sinal durante a escrita encerra o processo sem passar pelo retorno abaixo;
  # o tratador remove o temporario e a area da requisicao, que tem o token.
  DBX_CMD_TEMPORARIO_RECEBIMENTO=$temporario
  trap '_dbx_cmd_recebimento_interrompido' INT TERM HUP
  dbx_auth_conteudo_receber GET 'https://content.dropboxapi.com/2/files/download' \
    "$argumento" "$temporario"
  estado=$?
  # LIMITE DECLARADO, o mesmo de `dbx_transfer_sessao`: remove os tratadores
  # em vez de restaurar os do chamador; hoje nenhum caminho arma INT, TERM ou HUP
  # antes de receber.
  trap - INT TERM HUP
  DBX_CMD_TEMPORARIO_RECEBIMENTO=''
  if [[ $estado -ne 0 ]]; then
    rm -f -- "$temporario"
    return "$estado"
  fi

  dbx_cmd_content_hash_do_resultado
  DBX_CMD_CONTENT_HASH=$DBX_CMD_LIDO
  if [[ -n $DBX_CMD_CONTENT_HASH ]]; then
    obtido=''
    dbx_hash_publicar_arquivo "$temporario" 2>/dev/null && obtido=$DBX_HASH_RESULTADO
    # Resumo local ilegivel nunca e lido como conferido: sem prova, o alvo fica.
    if ! dbx_hash_iguais "$obtido" "$DBX_CMD_CONTENT_HASH"; then
      rm -f -- "$temporario"
      DBX_CMD_FALHA_CLASSE='integridade'
      DBX_CMD_FALHA_MOTIVO="o conteudo recebido nao confere com o resumo publicado pelo servico; o destino foi preservado: $alvo"
      return "$(dbx_errors_codigo_saida integridade)"
    fi
    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_CMD_INTEGRIDADE='conferida'
  fi

  if _dbx_cmd_alvo_somente_leitura "$alvo"; then
    rm -f -- "$temporario"
    return "$(dbx_errors_codigo_saida permissao)"
  fi
  # O modo entra so na troca: aplicado antes, um alvo 0444 deixaria o
  # temporario sem escrita e a falha pareceria divergencia de conteudo.
  if [[ -f $alvo ]]; then
    modo=$(stat -c %a -- "$alvo" 2>/dev/null) || modo=''
  fi
  [[ -n ${modo:-} ]] || printf -v modo '%o' $((0666 & ~$(umask)))
  chmod "$modo" -- "$temporario" 2>/dev/null || :
  mv -f -- "$temporario" "$alvo" 2>/dev/null || {
    rm -f -- "$temporario"
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_CMD_FALHA_CLASSE='configuracao'
    # shellcheck disable=SC2034
    DBX_CMD_FALHA_MOTIVO="nao foi possivel substituir o destino: $alvo"
    return "$(dbx_errors_codigo_saida configuracao)"
  }
  return 0
}

# dbx_cmd_bytes_legiveis <n> — apresentacao humana, sem utilitario externo.
dbx_cmd_bytes_legiveis() {
  local valor=${1:-0} unidade=0
  local -a nomes=(B KiB MiB GiB TiB PiB)
  [[ $valor =~ ^[0-9]+$ ]] || {
    printf '%s' "$valor"
    return 0
  }
  while [[ $valor -ge 1024 && $unidade -lt 5 ]]; do
    valor=$((valor / 1024))
    unidade=$((unidade + 1))
  done
  printf '%s %s' "$valor" "${nomes[unidade]}"
}
