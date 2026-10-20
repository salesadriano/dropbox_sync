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
# shellcheck source=lib/tmp.sh
. "$_dbx_cmd_diretorio/tmp.sh"
# shellcheck source=lib/state.sh
. "$_dbx_cmd_diretorio/state.sh"
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

# dbx_cmd_ler_corpo_silencioso <campo>... — le campos da ultima resposta SEM
# emitir nada: quem chama decide se o diagnostico aparece. O contexto de analise
# e literal (`leitura_silenciosa`): a auditoria de `composicao` proibe nome de
# contexto vindo de variavel.
#
# Conjunto onde incide: TODA leitura de resposta cuja falha NAO aborta o comando
# (hoje a consulta de comparacao do `upload`); a leitura que aborta usa
# `_dbx_cmd_analisar_corpo`. As duas compartilham a mesma redacao do motivo.
# Sucesso: campos em DBX_CMD_CAMPOS, na ordem pedida (ausente = vazio). Falha:
# status 1 com DBX_CMD_FALHA_CLASSE e DBX_CMD_FALHA_MOTIVO. Em ambos os casos o
# documento, o corpo bruto e o contexto de analise sao descartados.
# shellcheck disable=SC2034
# Justificativa: canal publico consumido pelos arquivos de `commands/`.
DBX_CMD_CAMPOS=()
# Chaves repetidas no documento lido (QA-B3-05); quem decide e quem chama.
DBX_CMD_DUPLICADAS=0
dbx_cmd_ler_corpo_silencioso() {
  local campo indice=0
  DBX_CMD_CAMPOS=()
  DBX_CMD_FALHA_CLASSE=''
  DBX_CMD_FALHA_MOTIVO=''
  dbx_json_contexto leitura_silenciosa || {
    DBX_CMD_FALHA_CLASSE='erro_remoto'
    DBX_CMD_FALHA_MOTIVO='contexto de analise indisponivel'
    return 1
  }
  DBX_CMD_DUPLICADAS=0
  if ! dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null; then
    DBX_CMD_FALHA_CLASSE='erro_remoto'
    DBX_CMD_FALHA_MOTIVO="resposta nao interpretavel: ${DBX_JSON_MOTIVO:-sem detalhe}"
  else
    # shellcheck disable=SC2034  # canal publico, lido por commands/lixeira
    DBX_CMD_DUPLICADAS=$DBX_JSON_DUPLICADAS
    local resto
    local -a segmentos
    for campo in "$@"; do
      DBX_CMD_CAMPOS[indice]=''
      # Campo aninhado vem como segmentos separados por espaco (`allocation
      # allocated`); a separacao e por expansao, sem `IFS` nem utilitario.
      segmentos=() resto=$campo
      while [[ $resto == *' '* ]]; do
        segmentos+=("${resto%% *}")
        resto=${resto#* }
      done
      segmentos+=("$resto")
      # shellcheck disable=SC2034  # canal publico lido pelos comandos
      dbx_json_valor "${segmentos[@]}" >/dev/null 2>&1 && DBX_CMD_CAMPOS[indice]=$DBX_JSON_RESULTADO
      indice=$((indice + 1))
    done
  fi
  dbx_json_descartar leitura_silenciosa
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # shellcheck disable=SC2034  # canais publicos alheios, limpos aqui
  DBX_JSON_RESULTADO=''
  # shellcheck disable=SC2034
  DBX_HTTP_CORPO=''
  [[ -z $DBX_CMD_FALHA_CLASSE ]]
}

# _dbx_cmd_caminho_remoto <caminho> [raiz] — PONTO UNICO do caminho remoto
# recebido como argumento (RNF-20(b1..b6), RNF-10(b); F-36, F-37).
#
# Conjunto onde incide: TODO comando que recebe caminho remoto, inclusive o
# destino que o `upload` de diretorio e o `download` de pasta derivam e
# repassam ao `sync`, que passa por aqui de novo. A auditoria de `composicao`
# reprova comando que chame `lib/path` remoto direto ou ignore a recusa.
#
# A raiz e a `raiz_remota` da credencial, ja carregada por `bin/dbx` antes do
# comando e, portanto, antes de qualquer chamada a API e da renovacao do token.
# So `config` passa a raiz explicita (`/`): a raiz que se define nao e confinada
# pela anterior. A recusa emite o diagnostico aqui, com o byte de controle
# citado (`dbx_cmd_caminho_exibivel`) e nunca cru; quem chama so propaga o
# status (`|| return $?`). Classe `caminho_recusado` (13); raiz da credencial
# malformada falha fechado como `configuracao` (3).
#
# A funcao de lib/path IMPRIME o resultado alem de publica-lo no canal; num
# comando isso cai no meio da saida estruturada (RF-28), dai o `>/dev/null`.
_dbx_cmd_caminho_remoto() {
  local caminho=${1-} raiz=${2-${DBX_CONFIG_RAIZ_REMOTA:-}} raiz_exibida
  DBX_CMD_LIDO=''
  if dbx_path_remoto_argumento "$raiz" "$caminho" >/dev/null; then
    # shellcheck disable=SC2153  # canal publico de lib/path, carregada por bin/dbx
    DBX_CMD_LIDO=$DBX_PATH_RESULTADO
    return 0
  fi
  dbx_cmd_caminho_exibivel "${raiz:-/}"
  raiz_exibida=$DBX_CMD_EXIBIDO
  dbx_cmd_caminho_exibivel "$caminho"
  case $DBX_PATH_MOTIVO in
    raiz_invalida)
      dbx_cmd_falhar configuracao \
        "raiz remota da credencial invalida ($raiz_exibida): reconfigure com 'dbx config --raiz'"
      ;;
    controle)
      dbx_cmd_falhar caminho_recusado \
        "caminho remoto recusado, contem caractere de controle: $DBX_CMD_EXIBIDO"
      ;;
    fora_da_raiz)
      dbx_cmd_falhar caminho_recusado \
        "caminho remoto recusado, fora da raiz remota configurada ($raiz_exibida): $DBX_CMD_EXIBIDO"
      ;;
    acima_da_raiz)
      dbx_cmd_falhar caminho_recusado \
        "caminho remoto recusado, sobe acima da raiz da conta: $DBX_CMD_EXIBIDO"
      ;;
    *)
      dbx_cmd_falhar caminho_recusado \
        "caminho remoto recusado, informe um caminho absoluto: $DBX_CMD_EXIBIDO"
      ;;
  esac
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
#
#   Fase 3: `restore` e `permanently_delete` sao o quarto e o quinto pontos. O
#   terceiro argumento `silencioso` nao emite o diagnostico: publica a classe e
#   o motivo em DBX_CMD_FALHA_CLASSE e DBX_CMD_FALHA_MOTIVO e devolve o codigo,
#   para quem relata por item (RF-74) ou traduz a recusa (RF-76(f)(g)). O
#   `in_progress` que sobra das tentativas (DIV-58) e `nao_concluida` nos
#   pontos que passam por AQUI (`delete`, `restore`, `permanently_delete`); o
#   envio de conteudo (`upload`, por lib/transfer) nao passa e mantem `10`.
#
#   Fase 5: o quarto argumento opcional `sim` declara a escrita idempotente
#   para a retentativa de RNF-07 (padrao `nao`). Vale para as rotas de link
#   compartilhado (DIV-119): repetir a criacao recebe `shared_link_already_exists`
#   e cai no reuso (RF-87); repetir a modificacao aplica o mesmo estado; repetir
#   a revogacao recebe `shared_link_not_found` e sai `4` com a explicacao.
_dbx_cmd_escrita_remota() {
  local url=$1 corpo=$2 modo=${3:-} idempotente=${4:-nao} estado
  [[ $idempotente == 'sim' ]] || idempotente='nao'
  DBX_CMD_FALHA_CLASSE=''
  DBX_CMD_FALHA_MOTIVO=''

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    # shellcheck disable=SC2034  # canal publico, consumido pelos comandos
    DBX_CMD_SIMULADO='sim'
    return 0
  fi
  # shellcheck disable=SC2034  # canal publico, consumido pelos comandos
  DBX_CMD_SIMULADO='nao'

  # Escrita nao e idempotente por padrao: repetir as cegas pode aplicar duas
  # vezes. So quem declara `sim` (fase 5) ganha a retentativa.
  dbx_auth_requisitar POST "$url" "$corpo" "$idempotente"
  estado=$?
  corpo=''
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
    in_progress | in_progress/* | in_progress.* | */in_progress | */in_progress/* | */in_progress.*)
      classe='nao_concluida'
      ;;
  esac
  if [[ $modo == 'silencioso' ]]; then
    DBX_CMD_FALHA_CLASSE=$classe
    DBX_CMD_FALHA_MOTIVO="escrita recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return "$(dbx_errors_codigo_saida "$classe")"
  fi
  dbx_cmd_falhar "$classe" \
    "escrita recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
  return $?
}

# dbx_cmd_remoto_confinado <caminho> [pasta] — 0 quando o caminho que a API
# DEVOLVEU (`path_display` de listagem ou de revisao) esta dentro da
# `raiz_remota` ou, com <pasta>, dentro dela (DIV-78), sem emitir nada
# (RNF-20(b); RF-72(b), RF-74(b), RF-75(e)).
#
# O argumento do operador passa pelo ponto unico `_dbx_cmd_caminho_remoto`; o
# caminho que vem da resposta nao e argumento e pode trazer byte de controle
# valido na Dropbox, entao aqui so a normalizacao e a fronteira de componente
# decidem. Caminho relativo, vazio ou que sobe acima da conta: fora (falha
# fechada).
dbx_cmd_remoto_confinado() {
  local caminho=${1-} raiz=${2-${DBX_CONFIG_RAIZ_REMOTA:-/}}
  [[ $caminho == /* ]] || return 1
  [[ -n $raiz ]] || raiz='/'
  dbx_path_remoto_confinar "$raiz" "$caminho" sim >/dev/null 2>&1
}

# dbx_cmd_chave_ascii <caminho> — chave de comparacao em DBX_CMD_CHAVE: o
# caminho com a caixa dobrada SO no ASCII (LC_ALL=C), como o confinamento.
DBX_CMD_CHAVE=''
dbx_cmd_chave_ascii() {
  local LC_ALL=C
  DBX_CMD_CHAVE=${1,,}
}

# dbx_cmd_descendente_estrito <caminho> <pasta> — 0 quando <caminho>, depois
# de normalizado, esta ESTRITAMENTE abaixo de <pasta> por componente (a propria
# pasta, um ancestral ou outra arvore nao sao). Normalizado em DBX_CMD_LIDO e
# a chave em DBX_CMD_CHAVE. Conjunto onde incide: toda descida remota da fase 3
# (QA-B3-06); pasta vazia e a raiz da conta.
dbx_cmd_descendente_estrito() {
  local caminho=${1-} pasta=${2:-/} normal base
  DBX_CMD_LIDO='' DBX_CMD_CHAVE=''
  [[ $caminho == /* ]] || return 1
  dbx_path_remoto_confinar "$pasta" "$caminho" sim >/dev/null 2>&1 || return 1
  normal=$DBX_PATH_RESULTADO
  dbx_path_remoto_normalizar "$pasta" >/dev/null 2>&1 || return 1
  base=$DBX_PATH_RESULTADO
  dbx_cmd_chave_ascii "$base"
  base=$DBX_CMD_CHAVE
  dbx_cmd_chave_ascii "$normal"
  [[ $DBX_CMD_CHAVE != "$base" ]] || return 1
  DBX_CMD_LIDO=$normal
  return 0
}

# ---------------------------------------------------------------------------
# Descida remota com itens apagados (fase 3: RF-74(b), RF-75, RF-76(d))
# ---------------------------------------------------------------------------
#
# Conjunto onde incide: `lixeira` (listagem e contagem do expurgo) e `restaurar`
# de pasta. Um NIVEL por chamada (RNF-28: sem `recursive=true`), `limit`
# explicito (RNF-23), paginacao por cursor e `include_deleted` com
# `include_restorable_info`. Quem desce e o chamador, que decide em quais
# subpastas entrar.

# shellcheck disable=SC2034  # canais publicos, lidos por commands/lixeira e restaurar
declare -ga DBX_CMD_NIVEL_TAGS=() DBX_CMD_NIVEL_NOMES=() DBX_CMD_NIVEL_CAMINHOS=() DBX_CMD_NIVEL_RESTAURAVEIS=()

# dbx_cmd_listar_nivel <caminho_api> <limite> — as entradas diretas da pasta,
# na ordem da API, nos quatro vetores acima (`restauravel`: `sim`, `nao` ou
# vazio quando a API nao informa). Nao emite nada. Falha: status da classe,
# com DBX_CMD_FALHA_CLASSE e DBX_CMD_FALHA_MOTIVO; os canais de lib/http ficam
# como a chamada os deixou (o resumo decide `not_found` e `not_folder`).
dbx_cmd_listar_nivel() {
  local caminho=$1 limite=$2 corpo url estado quantidade indice tag valor restauravel mais cursor
  DBX_CMD_NIVEL_TAGS=() DBX_CMD_NIVEL_NOMES=() DBX_CMD_NIVEL_CAMINHOS=() DBX_CMD_NIVEL_RESTAURAVEIS=()
  DBX_CMD_FALHA_CLASSE='' DBX_CMD_FALHA_MOTIVO=''
  dbx_json_escapar_cadeia "$caminho"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"include_deleted\":true,\"include_restorable_info\":true}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  url='https://api.dropboxapi.com/2/files/list_folder'
  while :; do
    dbx_auth_colecao POST "$url" "$corpo" "$limite"
    estado=$?
    if [[ $estado -ne 0 ]]; then
      DBX_CMD_FALHA_CLASSE=${DBX_HTTP_CLASSE:-erro_remoto}
      DBX_CMD_FALHA_MOTIVO="listagem recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
      dbx_errors_classe_valida "$DBX_CMD_FALHA_CLASSE" || DBX_CMD_FALHA_CLASSE='erro_remoto'
      return "${DBX_ERRORS_CODIGO[$DBX_CMD_FALHA_CLASSE]}"
    fi
    dbx_json_contexto nivel || {
      DBX_CMD_FALHA_CLASSE='erro_remoto' DBX_CMD_FALHA_MOTIVO='contexto de analise indisponivel'
      return "${DBX_ERRORS_CODIGO[erro_remoto]}"
    }
    if ! dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null; then
      DBX_CMD_FALHA_CLASSE='erro_remoto'
      DBX_CMD_FALHA_MOTIVO="resposta nao interpretavel: ${DBX_JSON_MOTIVO:-sem detalhe}"
      dbx_json_descartar nivel
      dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
      return "${DBX_ERRORS_CODIGO[erro_remoto]}"
    fi
    quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
    for ((indice = 0; indice < quantidade; indice++)); do
      tag=''
      dbx_json_valor entries "$indice" '.tag' >/dev/null 2>&1 && tag=$DBX_JSON_RESULTADO
      DBX_CMD_NIVEL_TAGS+=("$tag")
      valor=''
      dbx_json_valor entries "$indice" name >/dev/null 2>&1 && valor=$DBX_JSON_RESULTADO
      DBX_CMD_NIVEL_NOMES+=("$valor")
      valor=''
      dbx_json_valor entries "$indice" path_display >/dev/null 2>&1 && valor=$DBX_JSON_RESULTADO
      DBX_CMD_NIVEL_CAMINHOS+=("$valor")
      restauravel=''
      if dbx_json_valor entries "$indice" is_restorable >/dev/null 2>&1; then
        case $DBX_JSON_RESULTADO in
          true) restauravel='sim' ;;
          false) restauravel='nao' ;;
        esac
      fi
      DBX_CMD_NIVEL_RESTAURAVEIS+=("$restauravel")
    done
    mais='' cursor=''
    dbx_json_valor has_more >/dev/null 2>&1 && mais=$DBX_JSON_RESULTADO
    dbx_json_valor cursor >/dev/null 2>&1 && cursor=$DBX_JSON_RESULTADO
    dbx_json_descartar nivel
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    # shellcheck disable=SC2034  # canais publicos alheios, limpos aqui
    DBX_JSON_RESULTADO=''
    # shellcheck disable=SC2034
    DBX_HTTP_CORPO=''
    [[ $mais == 'true' && -n $cursor ]] || break
    dbx_json_escapar_cadeia "$cursor"
    corpo="{\"cursor\":\"$DBX_JSON_ESCAPADO\"}"
    # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
    DBX_JSON_ESCAPADO=''
    url='https://api.dropboxapi.com/2/files/list_folder/continue'
  done
  return 0
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
  # Registrado em `lib/tmp` desde a criacao: sinal em qualquer ponto encerra o
  # processo (o alvo continua o anterior) e remove o temporario junto com a area
  # da requisicao, que tem o token. Depois do `mv` ele sai do registro.
  dbx_tmp_arquivo "$diretorio/.${nome:0:200}${DBX_CMD_MARCA_RECEBIMENTO}XXXXXX" || {
    DBX_CMD_FALHA_CLASSE='configuracao'
    DBX_CMD_FALHA_MOTIVO="nao foi possivel criar o temporario de recebimento em: $diretorio"
    return "$(dbx_errors_codigo_saida configuracao)"
  }
  temporario=$DBX_TMP_CAMINHO

  dbx_auth_conteudo_receber GET 'https://content.dropboxapi.com/2/files/download' \
    "$argumento" "$temporario"
  estado=$?
  if [[ $estado -ne 0 ]]; then
    dbx_tmp_remover "$temporario"
    return "$estado"
  fi

  dbx_cmd_content_hash_do_resultado
  DBX_CMD_CONTENT_HASH=$DBX_CMD_LIDO
  if [[ -n $DBX_CMD_CONTENT_HASH ]]; then
    obtido=''
    dbx_hash_publicar_arquivo "$temporario" 2>/dev/null && obtido=$DBX_HASH_RESULTADO
    # Resumo local ilegivel nunca e lido como conferido: sem prova, o alvo fica.
    if ! dbx_hash_iguais "$obtido" "$DBX_CMD_CONTENT_HASH"; then
      dbx_tmp_remover "$temporario"
      DBX_CMD_FALHA_CLASSE='integridade'
      DBX_CMD_FALHA_MOTIVO="o conteudo recebido nao confere com o resumo publicado pelo servico; o destino foi preservado: $alvo"
      return "$(dbx_errors_codigo_saida integridade)"
    fi
    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_CMD_INTEGRIDADE='conferida'
  fi

  if _dbx_cmd_alvo_somente_leitura "$alvo"; then
    dbx_tmp_remover "$temporario"
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
    dbx_tmp_remover "$temporario"
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_CMD_FALHA_CLASSE='configuracao'
    # shellcheck disable=SC2034
    DBX_CMD_FALHA_MOTIVO="nao foi possivel substituir o destino: $alvo"
    return "$(dbx_errors_codigo_saida configuracao)"
  }
  dbx_tmp_esquecer "$temporario"
  return 0
}

# ---------------------------------------------------------------------------
# Ciclo comum do `sync` e do `verificar` (RF-69, RNF-35, RNF-36)
# ---------------------------------------------------------------------------

# Area da execucao em curso (`dbx-sync.*`, nome mantido por DIV-42).
DBX_CMD_CICLO_AREA=''

# dbx_cmd_ciclo_iniciar <comando> <raiz_local> <raiz_remota> <espera_s>
#
# UM ciclo para os dois comandos, e nao duas copias (C-1): trava do par,
# depois area temporaria registrada em `lib/tmp`. Chamado depois da validacao
# de argumentos e da recusa de caminho, e ANTES de qualquer chamada a API,
# escrita ou leitura de memoria (RF-69(b)). A liberacao da trava e a remocao da
# area ficam com `lib/tmp`, em toda saida.
#
# Trava ocupada, de outro host, ilegivel ou `.r` presa: recusa `conflito` (7)
# com a mensagem da trava (RF-69(d)). Diretorio de estado alheio ou sem
# escrita: a execucao segue SEM trava e o operador e avisado — a memoria ja
# trata esse diretorio assim (RNF-25(b1)), e recusar faria um artefato que nao
# decide nada travar o comando.
dbx_cmd_ciclo_iniciar() {
  local comando=$1 raiz_local=$2 remoto=$3 espera=$4 chave_local=$2 estado
  DBX_CMD_CICLO_AREA=''
  # A raiz local entra pelo caminho fisico canonico (RF-62), que existe mesmo
  # para a raiz que o `--receber` ainda vai criar.
  dbx_path_local_canonico "$raiz_local" && chave_local=$DBX_PATH_RESULTADO
  dbx_config_identidade
  dbx_state_trava_adquirir "$DBX_CONFIG_IDENTIDADE" "$chave_local" "$remoto" "$comando" "$espera"
  estado=$?
  # DIV-53: quem removeu uma orfa avisa, qualquer que seja o desfecho (ate o
  # conflito, se outra aquisicao venceu o `ln`).
  if [[ -n $DBX_STATE_AVISO ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso "$DBX_STATE_AVISO"
    dbx_output_render_diagnostico >&2
  fi
  # DIV-50: SO o diretorio de estado alheio ou sem escrita (permissao) segue
  # sem trava, com aviso. Uso invalido e qualquer outra falha recusam com o
  # proprio codigo; ocupada (inclusive nome instavel) e conflito.
  case $estado in
    0) ;;
    "$DBX_STATE_ERRO_CONFLITO")
      dbx_cmd_falhar conflito "$DBX_STATE_MOTIVO"
      return $?
      ;;
    "$DBX_STATE_ERRO_PERMISSAO")
      dbx_cmd_iniciar_saida
      dbx_output_diagnostico aviso "sem trava de concorrencia nesta execucao: ${DBX_STATE_MOTIVO:-diretorio de estado inacessivel}"
      dbx_output_render_diagnostico >&2
      ;;
    "$DBX_STATE_ERRO_USO")
      dbx_cmd_falhar uso_invalido "aquisicao da trava recusou os argumentos (defeito interno): ${DBX_STATE_MOTIVO:-uso invalido}"
      return $?
      ;;
    *)
      dbx_cmd_falhar configuracao "nao foi possivel obter a trava de concorrencia: ${DBX_STATE_MOTIVO:-falha local}"
      return $?
      ;;
  esac
  dbx_tmp_area sync || {
    dbx_cmd_falhar configuracao 'nao foi possivel criar area temporaria'
    return $?
  }
  # shellcheck disable=SC2034  # canal publico, lido por commands/sync e commands/verificar
  DBX_CMD_CICLO_AREA=$DBX_TMP_CAMINHO
  return 0
}

# ---------------------------------------------------------------------------
# Espaco livre da conta (RF-66 `espaco`, RF-67)
# ---------------------------------------------------------------------------
#
# Conjunto onde incide: a checagem previa do `upload` e do `sync --enviar`
# (RF-67) e a checagem `espaco` do `diagnostico` (RF-66). A folga e calculada
# AQUI, uma vez; calcula-la em cada comando faria a regra da conta de equipe
# valer para um lado so.

# shellcheck disable=SC2034  # canais publicos, lidos pelos comandos
DBX_CMD_ESPACO_USADO=''
# shellcheck disable=SC2034
DBX_CMD_ESPACO_ALOCADO=''
DBX_CMD_ESPACO_LIVRE=''
# shellcheck disable=SC2034
DBX_CMD_ESPACO_NECESSARIO=''
# shellcheck disable=SC2034
DBX_CMD_ESPACO_VERIFICADO='nao'
DBX_CMD_ESPACO_MOTIVO=''

# _dbx_cmd_inteiro <valor> — 0 quando e inteiro nao negativo.
_dbx_cmd_inteiro() { [[ ${1-} =~ ^[0-9]+$ ]]; }

# dbx_cmd_espaco_consultar — uma chamada `get_space_usage`, sem emitir nada.
#
# Status 0 quando a consulta foi lida; a folga vai em DBX_CMD_ESPACO_LIVRE e
# fica VAZIA quando a alocacao e ausente, de tipo desconhecido ou nao numerica
# (RF-67(c): nao recusa). Conta individual: alocado menos usado. Conta de
# equipe: a menor entre a folga da equipe e, quando ha limite do membro, a do
# membro. DBX_CMD_ESPACO_USADO e DBX_CMD_ESPACO_ALOCADO sao os da folga que
# prevaleceu. Status 1 na falha, com DBX_CMD_FALHA_CLASSE e DBX_CMD_FALHA_MOTIVO.
dbx_cmd_espaco_consultar() {
  DBX_CMD_ESPACO_USADO='' DBX_CMD_ESPACO_ALOCADO='' DBX_CMD_ESPACO_LIVRE=''
  DBX_CMD_FALHA_CLASSE='' DBX_CMD_FALHA_MOTIVO=''
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/users/get_space_usage' 'null' sim >/dev/null 2>&1 || {
    DBX_CMD_FALHA_CLASSE=${DBX_HTTP_CLASSE:-erro_remoto}
    DBX_CMD_FALHA_MOTIVO="consulta de espaco recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return 1
  }
  dbx_cmd_ler_corpo_silencioso used 'allocation .tag' 'allocation allocated' \
    'allocation used' 'allocation user_within_team_space_allocated' || return 1
  local usado=${DBX_CMD_CAMPOS[0]} tag=${DBX_CMD_CAMPOS[1]} alocado=${DBX_CMD_CAMPOS[2]}
  local usado_equipe=${DBX_CMD_CAMPOS[3]} limite_membro=${DBX_CMD_CAMPOS[4]}
  _dbx_cmd_inteiro "$usado" && _dbx_cmd_inteiro "$alocado" || return 0
  local livre
  case $tag in
    individual)
      DBX_CMD_ESPACO_USADO=$usado DBX_CMD_ESPACO_ALOCADO=$alocado
      ;;
    team)
      _dbx_cmd_inteiro "$usado_equipe" || return 0
      DBX_CMD_ESPACO_USADO=$usado_equipe DBX_CMD_ESPACO_ALOCADO=$alocado
      if _dbx_cmd_inteiro "$limite_membro" && [[ $limite_membro -gt 0 ]] &&
        ((limite_membro - usado < alocado - usado_equipe)); then
        DBX_CMD_ESPACO_USADO=$usado DBX_CMD_ESPACO_ALOCADO=$limite_membro
      fi
      ;;
    *) return 0 ;;
  esac
  livre=$((DBX_CMD_ESPACO_ALOCADO - DBX_CMD_ESPACO_USADO))
  [[ $livre -lt 0 ]] && livre=0
  DBX_CMD_ESPACO_LIVRE=$livre
  return 0
}

# _dbx_cmd_avisar <texto> — um aviso em stderr, pelo canal de diagnostico.
_dbx_cmd_avisar() {
  dbx_cmd_iniciar_saida
  dbx_output_diagnostico aviso "$1"
  dbx_output_render_diagnostico
}

# dbx_cmd_espaco_checar <total_em_bytes> [pular] — checagem previa de RF-67.
#
# Status 0 quando o envio pode seguir: cabe (igual a folga cabe), nada a enviar
# (sem consulta), `pular` = `sim` (`--forcar`, sem consulta), folga desconhecida
# ou consulta que falhou — os dois ultimos com UM aviso em stderr (RF-67(c)(g)).
# Status 1 quando nao cabe, com a mensagem em DBX_CMD_ESPACO_MOTIVO. Quem chama
# decide entre recusar (`espaco`, 12) e, em simulacao, so anunciar.
#
# Reinicia o modelo de saida quando avisa: chamar ANTES de montar o resultado.
dbx_cmd_espaco_checar() {
  local total=${1:-0} pular=${2:-nao}
  DBX_CMD_ESPACO_NECESSARIO=$total
  DBX_CMD_ESPACO_VERIFICADO='nao'
  DBX_CMD_ESPACO_LIVRE=''
  DBX_CMD_ESPACO_MOTIVO=''
  if [[ $pular == 'sim' ]]; then
    DBX_CMD_ESPACO_VERIFICADO='pulado'
    return 0
  fi
  _dbx_cmd_inteiro "$total" && [[ $total -gt 0 ]] || return 0
  if ! dbx_cmd_espaco_consultar; then
    _dbx_cmd_avisar "nao foi possivel consultar o espaco livre (${DBX_CMD_FALHA_MOTIVO:-sem detalhe}): o envio segue sem a checagem"
    return 0
  fi
  if [[ -z $DBX_CMD_ESPACO_LIVRE ]]; then
    _dbx_cmd_avisar 'alocacao de espaco da conta nao informada ou nao interpretavel: o envio segue sem a checagem'
    return 0
  fi
  DBX_CMD_ESPACO_VERIFICADO='sim'
  [[ $total -gt $DBX_CMD_ESPACO_LIVRE ]] || return 0
  # shellcheck disable=SC2034  # canal publico, lido por commands/upload e sync
  DBX_CMD_ESPACO_MOTIVO="espaco insuficiente na conta: necessario $total bytes, livre $DBX_CMD_ESPACO_LIVRE bytes, faltam $((total - DBX_CMD_ESPACO_LIVRE)) bytes (use --forcar ou --force para enviar sem esta checagem)"
  return 1
}

# dbx_cmd_espaco_campos — os campos `espaco_*` no resultado em montagem
# (RF-67(i)): acrescimo, contrato inalterado.
dbx_cmd_espaco_campos() {
  dbx_output_campo espaco_necessario "$DBX_CMD_ESPACO_NECESSARIO"
  dbx_output_campo espaco_livre "$DBX_CMD_ESPACO_LIVRE"
  dbx_output_campo espaco_verificado "$DBX_CMD_ESPACO_VERIFICADO"
}

# dbx_cmd_caminho_exibivel <caminho> — forma do caminho que cabe numa linha
# (RNF-10, RF-28), em DBX_CMD_EXIBIDO: com byte de controle ou quebra de linha
# ele sai citado, e a ambiguidade fica visivel em vez de abrir uma segunda
# linha. Sem byte de controle, sai como esta.
#
# Conjunto onde incide: toda emissao de caminho por linha de `sync` e de
# `verificar`; com `--null` o registro carrega qualquer byte e o caminho sai
# integro.
DBX_CMD_EXIBIDO=''
dbx_cmd_caminho_exibivel() {
  if [[ $1 == *[$'\001'-$'\037\177']* ]]; then
    printf -v DBX_CMD_EXIBIDO '%q' "$1"
  else
    # shellcheck disable=SC2034  # canal publico, lido por commands/sync e verificar
    DBX_CMD_EXIBIDO=$1
  fi
}

# dbx_cmd_campo_caminho <chave> <caminho> — campo de caminho no resultado em
# montagem: integro com `--null`, citado por `dbx_cmd_caminho_exibivel` na
# saida por linha (RF-28, RNF-10). Conjunto onde incide: os caminhos que
# `revisoes`, `restaurar` e `lixeira` emitem fora de `_dbx_cmd_metadado_em`.
dbx_cmd_campo_caminho() {
  if [[ ${DBX_CLI_NULO:-nao} == 'sim' ]]; then
    dbx_output_campo "$1" "$2"
  else
    dbx_cmd_caminho_exibivel "$2"
    dbx_output_campo "$1" "$DBX_CMD_EXIBIDO"
  fi
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

# ---------------------------------------------------------------------------
# Filtros (RF-79, RF-81) — ponto unico para `sync`, `verificar` e `download`
# ---------------------------------------------------------------------------

# dbx_cmd_filtros_preparar <vetor_de_caminho> <vetor_de_data_e_tamanho>
#
# Os dois vetores trazem pares `opcao valor` na ordem da linha de comando. Os de
# caminho ACUMULAM (RF-79(a), excecao a RF-64(e)); os de data e tamanho seguem
# RF-64(e), o ultimo valor de cada um vence e so ele e validado. Recusa com uso
# invalido e a mensagem em DBX_CMD_FILTRO_MOTIVO, antes da trava, da memoria, da
# rede e de qualquer escrita (RF-79(j)).
DBX_CMD_FILTRO_MOTIVO=''
# shellcheck disable=SC2034  # DBX_CMD_FILTRO_MOTIVO: canal publico, lido pelos comandos
dbx_cmd_filtros_preparar() {
  local -n _fp_caminho=$1 _fp_meta=$2
  local i opcao tipo
  local -A ultimo=() valores=()
  DBX_CMD_FILTRO_MOTIVO=''
  dbx_filtro_limpar
  for ((i = 0; i + 1 < ${#_fp_caminho[@]}; i += 2)); do
    opcao=${_fp_caminho[i]}
    tipo='incluir'
    [[ $opcao == '--excluir' || $opcao == '--exclude' ]] && tipo='excluir'
    dbx_filtro_adicionar "$tipo" "$opcao" "${_fp_caminho[i + 1]}" || {
      DBX_CMD_FILTRO_MOTIVO=$DBX_FILTRO_MOTIVO
      return "$DBX_CLI_ERRO_USO"
    }
  done
  for ((i = 0; i + 1 < ${#_fp_meta[@]}; i += 2)); do
    opcao=${_fp_meta[i]}
    case $opcao in
      --modificado-desde | --modified-since) tipo=desde ;;
      --modificado-ate | --modified-until) tipo=ate ;;
      --tamanho-min | --min-size) tipo=min ;;
      *) tipo=max ;;
    esac
    ultimo[$tipo]=$opcao
    valores[$tipo]=${_fp_meta[i + 1]}
  done
  local desde='' ate='' min='' max=''
  if [[ -n ${ultimo[desde]+x} ]]; then
    dbx_filtro_validar_data "${ultimo[desde]}" "${valores[desde]}" desde || {
      DBX_CMD_FILTRO_MOTIVO=$DBX_FILTRO_MOTIVO
      return "$DBX_CLI_ERRO_USO"
    }
    # shellcheck disable=SC2153  # canal publico de lib/filtro
    desde=$DBX_FILTRO_DATA
  fi
  if [[ -n ${ultimo[ate]+x} ]]; then
    dbx_filtro_validar_data "${ultimo[ate]}" "${valores[ate]}" ate || {
      DBX_CMD_FILTRO_MOTIVO=$DBX_FILTRO_MOTIVO
      return "$DBX_CLI_ERRO_USO"
    }
    ate=$DBX_FILTRO_DATA
  fi
  for tipo in min max; do
    [[ -n ${ultimo[$tipo]+x} ]] || continue
    dbx_filtro_validar_tamanho "${ultimo[$tipo]}" "${valores[$tipo]}" || {
      DBX_CMD_FILTRO_MOTIVO=$DBX_FILTRO_MOTIVO
      return "$DBX_CLI_ERRO_USO"
    }
    if [[ $tipo == 'min' ]]; then min=$DBX_FILTRO_BYTES; else max=$DBX_FILTRO_BYTES; fi
  done
  dbx_filtro_meta_definir "$desde" "$ate" "$min" "$max" || {
    DBX_CMD_FILTRO_MOTIVO=$DBX_FILTRO_MOTIVO
    return "$DBX_CLI_ERRO_USO"
  }
  return 0
}

# dbx_cmd_campos_de_filtro <filtrados_origem> <filtrados_destino> — RF-80(i)(j).
#
# `filtros sim|nao`, cada padrao ativo pela chave do seu tipo (`excluir`,
# `incluir`), as faixas de data e tamanho e as contagens. Filtrado nunca e
# listado um a um. Acrescimo compativel (RF-35).
dbx_cmd_campos_de_filtro() {
  local i
  if dbx_filtro_ativo || dbx_filtro_meta_ativo; then
    dbx_output_campo filtros sim
  else
    dbx_output_campo filtros nao
  fi
  for i in "${!DBX_FILTRO_PADROES[@]}"; do
    dbx_output_campo "${DBX_FILTRO_TIPOS[i]}" "${DBX_FILTRO_PADROES[i]}"
  done
  [[ -n $DBX_FILTRO_DESDE ]] && dbx_output_campo modificado_desde "$DBX_FILTRO_DESDE"
  [[ -n $DBX_FILTRO_ATE ]] && dbx_output_campo modificado_ate "$DBX_FILTRO_ATE"
  [[ -n $DBX_FILTRO_MIN ]] && dbx_output_campo tamanho_min "$DBX_FILTRO_MIN"
  [[ -n $DBX_FILTRO_MAX ]] && dbx_output_campo tamanho_max "$DBX_FILTRO_MAX"
  dbx_output_campo filtrados_origem "${1:-0}"
  dbx_output_campo filtrados_destino "${2:-0}"
}

# dbx_cmd_avisos_de_filtro — DBX_SYNC_AVISOS em stderr, uma linha cada (DIV-91):
# nao muda stdout nem codigo de saida.
dbx_cmd_avisos_de_filtro() {
  local aviso
  [[ ${#DBX_SYNC_AVISOS[@]} -gt 0 ]] || return 0
  dbx_cmd_iniciar_saida
  for aviso in "${DBX_SYNC_AVISOS[@]}"; do
    dbx_output_diagnostico aviso "$aviso"
  done
  dbx_output_render_diagnostico >&2
  return 0
}

# ---------------------------------------------------------------------------
# Limite de banda (RF-82) — ponto unico para `upload`, `download` e `sync`
# ---------------------------------------------------------------------------

# dbx_cmd_limite_banda <tem_opcao: sim|nao> <opcao_como_digitada> <valor>
#
# A opcao vence: presente, a variavel DBX_LIMITE_BANDA NAO e consultada (DIV-89),
# nem para recusar. Ausente a opcao, a variavel presente e invalida (inclusive
# vazia) recusa com o remedio; nunca e ignorada nem trocada por "sem limite"
# (RF-82(g), RNF-30(c)). O piso deriva da velocidade minima EFETIVA (DIV-88),
# ja validada pela entrada (`dbx_http_validar_ambiente`). Recusa com uso
# invalido e a mensagem em DBX_CMD_LIMITE_MOTIVO, antes de qualquer rede.
DBX_CMD_LIMITE_BANDA=''
DBX_CMD_LIMITE_MOTIVO=''
# shellcheck disable=SC2034  # DBX_CMD_LIMITE_*: canais publicos, lidos pelos comandos
dbx_cmd_limite_banda() {
  local tem_opcao=$1 opcao=$2 valor=${3-} piso
  DBX_CMD_LIMITE_BANDA=''
  DBX_CMD_LIMITE_MOTIVO=''
  piso=$((2 * ${DBX_HTTP_EFETIVO[DBX_HTTP_VELOCIDADE_MINIMA_BPS]:-1024}))
  if [[ $tem_opcao == 'sim' ]]; then
    dbx_cli_validar_taxa "$opcao" "$valor" "$piso" opcao || {
      DBX_CMD_LIMITE_MOTIVO=$DBX_CLI_MOTIVO
      return "$DBX_CLI_ERRO_USO"
    }
  elif [[ -n ${DBX_LIMITE_BANDA+definida} ]]; then
    dbx_cli_validar_taxa DBX_LIMITE_BANDA "$DBX_LIMITE_BANDA" "$piso" variavel || {
      DBX_CMD_LIMITE_MOTIVO=$DBX_CLI_MOTIVO
      return "$DBX_CLI_ERRO_USO"
    }
  else
    dbx_http_limite_banda ''
    return 0
  fi
  # shellcheck disable=SC2034  # canal publico, lido pelos comandos na saida
  DBX_CMD_LIMITE_BANDA=$DBX_CLI_TAXA
  dbx_http_limite_banda "$DBX_CLI_TAXA"
}
