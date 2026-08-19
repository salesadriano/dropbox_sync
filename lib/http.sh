#!/usr/bin/env bash
# lib/http.sh — ponto UNICO de saida de rede.
#
# Camada: adaptadores. Depende de lib/errors.sh (dominio) e de lib/json.sh.
#
# Concentrar toda a rede aqui e o que permite auditar num so lugar a circulacao
# do segredo, a politica de retentativa e o mapeamento de erro. Ha caso de teste
# que reprova se qualquer outro componente invocar o cliente.
#
# CONTRATO EXIGIDO DO CLIENTE HTTP, declarado porque a suite o substitui:
#   -K -            le opcoes da entrada padrao (e por onde o segredo passa)
#   -o <arquivo>    grava o corpo da resposta
#   -D <arquivo>    grava os cabecalhos da resposta
#   -w '%{http_code}'  imprime o codigo HTTP na saida padrao
#   --data-binary @<arquivo>  envia o corpo a partir de arquivo
#   status de saida diferente de zero quando NAO houve resposta HTTP
# Qualquer substituto de teste precisa honrar exatamente isto; divergir faria a
# suite validar uma ficcao.
#
# RNF-03 — o segredo NUNCA vai em argv. Ele viaja pela entrada padrao, em
# arquivo de opcoes lido pelo cliente, porque a tabela de processos e legivel
# por qualquer usuario do host. O corpo da requisicao vai por arquivo
# temporario, justamente para deixar a entrada padrao livre para o segredo.
#
# RSK-23 — nao ha estado local persistente. Nenhum cursor e guardado "para
# retomar": a camada de adaptadores e exatamente onde esse cache pareceria
# inofensivo.

[[ -n ${DBX_HTTP_CARREGADO:-} ]] && return 0
DBX_HTTP_CARREGADO=1

_dbx_http_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_http_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_http_diretorio=.
_dbx_http_diretorio=$(cd -P -- "$_dbx_http_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_http_diretorio/errors.sh"
# shellcheck source=lib/json.sh
. "$_dbx_http_diretorio/json.sh"
unset _dbx_http_diretorio

DBX_HTTP_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_HTTP_ERRO_REDE=$(dbx_errors_codigo_saida rede)
readonly DBX_HTTP_ERRO_USO DBX_HTTP_ERRO_REDE

# RNF-23: teto de itens por pagina. O teto de entrada de lib/json e 256 KiB, o
# que comporta cerca de 537 entradas tipicas, enquanto uma listagem sem limite
# pode devolver 2.000 — quase quatro vezes o teto. Cem entradas dao cerca de
# 49 KiB por pagina, com folga larga.
readonly DBX_HTTP_LIMITE_MAXIMO=100
# Piso da reducao: abaixo disto, insistir nao ajuda e a falha precisa aparecer.
readonly DBX_HTTP_LIMITE_MINIMO=5
readonly DBX_HTTP_TENTATIVAS_MAXIMAS=3
# Teto do valor de cabecalho. Medido: integro ate ~100.000 bytes, truncagem
# silenciosa a partir dai e descarte em 1.000.000 — as tres sem aviso do cliente.
# 8 KiB fica uma ordem de grandeza abaixo da primeira falha observada, e cobre
# com folga um caminho remoto da Dropbox codificado em JSON.
readonly DBX_HTTP_LIMITE_CABECALHO=8192

DBX_HTTP_ESPERA_BASE_MS=${DBX_HTTP_ESPERA_BASE_MS:-250}
DBX_HTTP_AREA_TEMP=''

# Modo de autorizacao da chamada corrente e nome do vetor de campos do modo
# formulario. Internos: nao fazem parte do contrato publico do componente.
_DBX_HTTP_MODO='bearer'
# Canal do corpo da chamada corrente. Interno.
_DBX_HTTP_CANAL='padrao'
_DBX_HTTP_DESTINO=''
_DBX_HTTP_ARG=''
_DBX_HTTP_ARQUIVO_CORPO=''
_DBX_HTTP_TOKEN=''
_DBX_HTTP_CAMPOS_NOME=''

# Status do cliente que denuncia defeito NOSSO, e nao da rede; e a mensagem que
# o cliente emitiu, ja redigida. Canais publicos.
DBX_HTTP_DEFEITO_CLIENTE=''
DBX_HTTP_DIAGNOSTICO=''

# shellcheck disable=SC2034  # canais publicos, lidos pelo chamador e pela suite
# Motivo da ultima recusa de cabecalho. Descreve a CAUSA, nunca o valor: ecoar o
# valor levaria o proprio terminador para dentro do registro, transportando o
# vetor do ponto onde foi barrado ate o log.
DBX_HTTP_MOTIVO_CABECALHO=''
# shellcheck disable=SC2034
DBX_HTTP_CODIGO=''
# shellcheck disable=SC2034
DBX_HTTP_CORPO=''
# shellcheck disable=SC2034
DBX_HTTP_RESUMO_DE_ERRO=''
# shellcheck disable=SC2034
DBX_HTTP_CLASSE=''
# shellcheck disable=SC2034
DBX_HTTP_POLITICA=''
# shellcheck disable=SC2034
DBX_HTTP_CORRELACAO=''

_dbx_http_limpar() {
  DBX_HTTP_CODIGO=''
  DBX_HTTP_CORPO=''
  DBX_HTTP_RESUMO_DE_ERRO=''
  DBX_HTTP_CLASSE=''
  DBX_HTTP_POLITICA=''
  DBX_HTTP_CORRELACAO=''
}

# _dbx_http_esperar <tentativa> — recuo exponencial com variacao.
_dbx_http_esperar() {
  local tentativa=$1 milissegundos
  milissegundos=$((DBX_HTTP_ESPERA_BASE_MS * (1 << (tentativa - 1))))
  # Variacao aleatoria para nao sincronizar varios hosts na mesma janela.
  milissegundos=$((milissegundos + RANDOM % (DBX_HTTP_ESPERA_BASE_MS + 1)))
  sleep "$((milissegundos / 1000)).$(printf '%03d' $((milissegundos % 1000)))"
}

# _dbx_http_correlacao_de <arquivo_de_cabecalhos>
#
# O identificador de correlacao e capturado nos DOIS caminhos, sucesso e erro:
# perde-lo apenas no de erro seria a assimetria que RF-30 nao tolera, ja que e
# no erro que ele serve.
_dbx_http_correlacao_de() {
  local arquivo=$1 linha nome valor
  DBX_HTTP_CORRELACAO=''
  [[ -r $arquivo ]] || return 0
  while IFS= read -r linha; do
    linha=${linha%$'\r'}
    nome=${linha%%:*}
    [[ $nome == "$linha" ]] && continue
    valor=${linha#*:}
    valor=${valor# }
    case ${nome,,} in
      x-dropbox-request-id | x-request-id | x-server-response)
        # shellcheck disable=SC2034  # canal publico, ver nota no topo
        DBX_HTTP_CORRELACAO=$valor
        return 0
        ;;
    esac
  done <"$arquivo"
  return 0
}

# _dbx_http_interpretar_erro <corpo> — extrai o resumo de erro do corpo.
#
# Interpreta em CONTEXTO NOMEADO proprio: usar o contexto padrao destruiria uma
# listagem em curso, que e precisamente o modo de falha que o contexto nomeado
# existe para impedir. O nome e literal — derivar de tag do erro produziria
# colisao com perda de documento entre duas respostas de mesma tag.
_dbx_http_interpretar_erro() {
  local corpo=$1
  DBX_HTTP_RESUMO_DE_ERRO=''
  [[ -n $corpo ]] || return 0
  dbx_json_contexto http_erro || return 0
  if dbx_json_analisar "$corpo"; then
    if dbx_json_valor error_summary >/dev/null; then
      DBX_HTTP_RESUMO_DE_ERRO=$DBX_JSON_RESULTADO
    fi
  fi
  dbx_json_descartar http_erro
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # Um servico que ecoe a requisicao no corpo de erro poe credencial no canal
  # escalar do analisador; o resumo ja foi copiado, e o canal nao precisa reter.
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_RESULTADO=''
  return 0
}

# _dbx_http_opcoes — emite as linhas de configuracao lidas por `curl -K -`.
#
# Tudo que e sensivel sai por AQUI, isto e, pela entrada padrao: nem token nem
# campo de formulario aparecem em `argv`, que e legivel por qualquer processo em
# `/proc/<pid>/cmdline` (RNF-03).
#
# O modo `formulario` existe para a troca de refresh token por token curto: o
# segredo vai em campos `data-urlencode`, tambem pela entrada padrao, e nao por
# arquivo de corpo. Escrever o refresh token em arquivo temporario criaria uma
# janela de credencial em disco que nenhuma permissao elimina — melhor nao
# existir a superficie do que protege-la.
_dbx_http_opcoes() {
  printf 'silent\n'
  printf 'show-error\n'
  case $_DBX_HTTP_MODO in
    formulario)
      printf 'header = "Content-Type: application/x-www-form-urlencoded"\n'
      local -n _campos=$_DBX_HTTP_CAMPOS_NOME
      local campo escapado
      for campo in "${_campos[@]}"; do
        escapado=${campo//\\/\\\\}
        escapado=${escapado//\"/\\\"}
        printf 'data-urlencode = "%s"\n' "$escapado"
      done
      ;;
    conteudo)
      printf 'header = "Authorization: Bearer %s"\n' "$_DBX_HTTP_TOKEN"
      printf 'header = "Content-Type: application/octet-stream"\n'
      # O valor vai dentro de cadeia entre aspas no arquivo de configuracao: uma
      # aspa crua ENCERRA a cadeia e o resto do JSON e descartado em silencio.
      # Medido: `{"path":"/a.txt"}` chegava ao servidor como `{`. Mesmo escape ja
      # aplicado ao modo formulario — a disciplina existia no gemeo e nao aqui.
      local _arg_escapado=${_DBX_HTTP_ARG//\\/\\\\}
      _arg_escapado=${_arg_escapado//\"/\\\"}
      printf 'header = "Dropbox-API-Arg: %s"\n' "$_arg_escapado"
      ;;
    *)
      printf 'header = "Authorization: Bearer %s"\n' "$_DBX_HTTP_TOKEN"
      ;;
  esac
}

# dbx_http_cabecalho_valido <valor> — status 0 aceita, uso invalido recusa.
#
# A recusa e NOSSA. Medido contra o cliente real: um valor com `\n` ou `\r\n` NAO
# e descartado — o cliente transmite, o servidor interpreta o que vem depois da
# quebra como cabecalho proprio, e o cliente sai com status 0 sem aviso. Como a
# origem do valor e nome de arquivo do usuario, isso e injecao de cabecalho HTTP
# com entrada controlada.
#
# Por isso a garantia nao pode ser "o cliente sanitiza": um caso escrito contra o
# comportamento do cliente teria passado e codificado a conclusao falsa.
#
# Conjunto onde incide: todo valor que va para um cabecalho — hoje o argumento do
# modo de conteudo, e qualquer outro que venha a existir.
dbx_http_cabecalho_valido() {
  local valor=${1-} indice byte
  DBX_HTTP_MOTIVO_CABECALHO=''

  if [[ ${#valor} -gt $DBX_HTTP_LIMITE_CABECALHO ]]; then
    printf -v DBX_HTTP_MOTIVO_CABECALHO \
      'valor de cabecalho excede o teto: %s bytes, maximo %s' \
      "${#valor}" "$DBX_HTTP_LIMITE_CABECALHO"
    return "$DBX_HTTP_ERRO_USO"
  fi

  # Byte de controle de 0x01 a 0x1f, mais 0x7f. O NUL nao entra na faixa porque
  # cadeia de shell nao o carrega — nao e omissao, e impossibilidade do canal.
  if [[ $valor == *[$'\001'-$'\037\177']* ]]; then
    # A posicao e o codigo bastam para diagnosticar. O valor NAO entra no motivo:
    # ele carrega o proprio terminador, e o motivo vai para registro em disco.
    for ((indice = 0; indice < ${#valor}; indice++)); do
      byte=${valor:indice:1}
      if [[ $byte == [$'\001'-$'\037\177'] ]]; then
        printf -v DBX_HTTP_MOTIVO_CABECALHO \
          'byte de controle 0x%02x na posicao %s do valor de cabecalho' \
          "'$byte" "$indice"
        return "$DBX_HTTP_ERRO_USO"
      fi
    done
  fi

  # UTF-8 sobrelongo de CR e LF: sequencia invalida que alguns decodificadores
  # mapeiam de volta para o caractere, contornando a verificacao acima.
  local sobrelongo
  for sobrelongo in $'\300\215' $'\300\212' $'\340\200\215' $'\340\200\212'; do
    if [[ $valor == *"$sobrelongo"* ]]; then
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_MOTIVO_CABECALHO='sequencia UTF-8 sobrelonga de terminador no valor de cabecalho'
      return "$DBX_HTTP_ERRO_USO"
    fi
  done

  return 0
}

# dbx_http_conteudo <metodo> <url> <token> <arg_json> <arquivo> <idempotente>
#
# Modo de conteudo da Dropbox: parametros em `Dropbox-API-Arg`, corpo binario.
# A validacao ocorre ANTES de qualquer invocacao do cliente — valor inseguro e
# recusado sem que o cliente chegue a ser chamado.
dbx_http_conteudo() {
  [[ $# -ge 6 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 arg=$4 arquivo=$5 idempotente=$6
  [[ -n $metodo && -n $url && -n $token ]] || return "$DBX_HTTP_ERRO_USO"

  dbx_http_cabecalho_valido "$arg" || return "$DBX_HTTP_ERRO_USO"

  _DBX_HTTP_MODO=conteudo
  _DBX_HTTP_CANAL=padrao
  _DBX_HTTP_TOKEN=$token
  _DBX_HTTP_ARG=$arg
  _DBX_HTTP_ARQUIVO_CORPO=$arquivo
  _DBX_HTTP_DESTINO=''
  _dbx_http_executar "$metodo" "$url" '' "$idempotente"
}

# dbx_http_conteudo_receber <metodo> <url> <token> <arg_json> <destino>
#
# Recebimento em fluxo: o corpo vai direto para <destino> — arquivo ou descritor,
# tipicamente `/dev/stdout` — sem materializar copia intermediaria. Nao ha teto de
# tamanho, por decisao de emitir e validar em paralelo.
#
# NAO e idempotente para efeito de retentativa: o canal e de fluxo, e o laco so
# repete quando nada foi emitido. Ver a nota no laco.
dbx_http_conteudo_receber() {
  [[ $# -ge 5 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 arg=$4 destino=$5
  [[ -n $metodo && -n $url && -n $token && -n $destino ]] || return "$DBX_HTTP_ERRO_USO"

  dbx_http_cabecalho_valido "$arg" || return "$DBX_HTTP_ERRO_USO"

  _DBX_HTTP_MODO=conteudo
  _DBX_HTTP_CANAL=fluxo
  _DBX_HTTP_TOKEN=$token
  _DBX_HTTP_ARG=$arg
  _DBX_HTTP_ARQUIVO_CORPO=''
  _DBX_HTTP_DESTINO=$destino
  _dbx_http_executar "$metodo" "$url" '' sim
}

# dbx_http_requisitar <metodo> <url> <token> <corpo> <idempotente>
dbx_http_requisitar() {
  [[ $# -ge 5 ]] || return "$DBX_HTTP_ERRO_USO"
  _DBX_HTTP_MODO=bearer
  _DBX_HTTP_CANAL=padrao
  _DBX_HTTP_TOKEN=$3
  _dbx_http_executar "$1" "$2" "$4" "$5"
}

# dbx_http_formulario <url> <nome_do_vetor_de_campos>
#
# O vetor e passado por NOME, como em lib/output: campo com quebra de linha ou
# aspas nao sobreviveria a uma passagem por cadeia unica, e o nome mantem a
# procedencia visivel no ponto de chamada.
dbx_http_formulario() {
  [[ $# -ge 2 ]] || return "$DBX_HTTP_ERRO_USO"
  [[ -n $1 && -n $2 ]] || return "$DBX_HTTP_ERRO_USO"
  _DBX_HTTP_MODO=formulario
  _DBX_HTTP_CANAL=padrao
  _DBX_HTTP_CAMPOS_NOME=$2
  # Sem corpo em arquivo: os campos vao pela entrada padrao.
  # Nao idempotente: uma troca de token repetida as cegas nao e desejavel.
  _dbx_http_executar POST "$1" '' nao
}

_dbx_http_executar() {
  local metodo=$1 url=$2 corpo=$3 idempotente=$4
  local tentativa=1 estado codigo politica

  case $idempotente in
    sim | nao) ;;
    *) return "$DBX_HTTP_ERRO_USO" ;;
  esac
  [[ -n $metodo && -n $url ]] || return "$DBX_HTTP_ERRO_USO"

  _dbx_http_limpar

  umask 077
  # DELIBERADAMENTE global, e nao `local`: a acao do `trap` e avaliada quando a
  # funcao retorna, momento em que o escopo local ja nao existe — com variavel
  # local a expansao viraria vazia e nada seria removido. E o mesmo defeito ja
  # corrigido em lib/hash, repetido aqui: a disciplina existia num componente e
  # nao no gemeo.
  DBX_HTTP_AREA_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/dbx-http.XXXXXXXX") ||
    return "$DBX_HTTP_ERRO_REDE"
  local area=$DBX_HTTP_AREA_TEMP
  # A limpeza vale tambem para sinal interceptavel: o corpo pode conter dado do
  # usuario e as opcoes contem o segredo.
  trap 'rm -rf -- "$DBX_HTTP_AREA_TEMP"' RETURN

  [[ -n $corpo ]] && printf '%s' "$corpo" >"$area/requisicao"

  while :; do
    : >"$area/resposta"
    : >"$area/cabecalhos"
    : >"$area/erro_cliente"
    # A redirecao do stderr fica DENTRO da substituicao: aplicada do lado de
    # fora, a substituicao ja teria sido expandida com o stderr original e a
    # mensagem do cliente se perderia. Foi o que aconteceu na primeira versao —
    # o canal existia e chegava sempre vazio.
    codigo=$(
      {
        _dbx_http_opcoes | if [[ $_DBX_HTTP_CANAL == 'fluxo' ]]; then
        # `--fail` e o que impede a resposta de ERRO de sair como se fosse o
        # conteudo do arquivo. Medido: sem ele, um 409 sai pela saida padrao com
        # status ZERO — um erro que se parece com exito, com nome de arquivo
        # correto e um JSON dentro. Com ele, zero bytes emitidos e status 22.
        curl -K - --fail -X "$metodo" \
          -o "$_DBX_HTTP_DESTINO" -D "$area/cabecalhos" -w '%{http_code}' "$url"
      elif [[ -n $_DBX_HTTP_ARQUIVO_CORPO ]]; then
        curl -K - -X "$metodo" --data-binary "@$_DBX_HTTP_ARQUIVO_CORPO" \
          -o "$area/resposta" -D "$area/cabecalhos" -w '%{http_code}' "$url"
      elif [[ -n $corpo ]]; then
        curl -K - -X "$metodo" --data-binary "@$area/requisicao" \
          -o "$area/resposta" -D "$area/cabecalhos" -w '%{http_code}' "$url"
      else
        curl -K - -X "$metodo" \
          -o "$area/resposta" -D "$area/cabecalhos" -w '%{http_code}' "$url"
      fi
      } 2>"$area/erro_cliente"
    )
    estado=$?

    # DEFEITO NOSSO NAO PODE CHEGAR AO OPERADOR COMO PROBLEMA DE REDE.
    #
    # Antes, qualquer status nao zero do cliente virava `codigo=0` e era
    # classificado como falha de rede, entao opcao mal formada ou arquivo de
    # corpo ilegivel — defeitos do PROPRIO PROGRAMA — chegavam ao operador como
    # "verifique conectividade, DNS, proxy e TLS", mandando investigar a rede
    # alheia por bug nosso.
    #
    # Estes status do cliente sao emitidos ANTES de qualquer tentativa de
    # conversa com o servidor e nao dependem da rede:
    #   2  falha de inicializacao, inclusive arquivo de opcoes mal formado
    #   3  URL mal formada
    #   26 erro de leitura do arquivo indicado ao corpo
    #   43 argumento interno invalido
    # O stderr do cliente deixou de ser descartado: pedir `show-error` e jogar a
    # mensagem fora era pedir diagnostico para nao le-lo.
    DBX_HTTP_DEFEITO_CLIENTE=''
    if [[ $estado -eq 22 ]]; then
      # `--fail` no canal de fluxo: HOUVE resposta HTTP e o codigo e conhecido; o
      # cliente apenas se recusou a emitir o corpo de erro como se fosse conteudo.
      # Tratar como falha de rede mandaria o operador investigar DNS e TLS diante
      # de um 404 perfeitamente informativo.
      :
    elif [[ $estado -ne 0 ]]; then
      # Sem resposta HTTP: codigo zero, e nao um codigo inventado.
      codigo=0
      case $estado in
        2 | 3 | 26 | 43) DBX_HTTP_DEFEITO_CLIENTE=$estado ;;
      esac
    fi
    [[ $codigo =~ ^[0-9]+$ ]] || codigo=0

    DBX_HTTP_DIAGNOSTICO=''
    if [[ -s $area/erro_cliente ]]; then
      local bruto=''
      IFS= read -r -d '' bruto <"$area/erro_cliente"
      # Redigido antes de publicar: as opcoes que o cliente reclama podem conter
      # o segredo, e este canal e lido por quem depura.
      dbx_errors_redigir "$bruto" >/dev/null
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_DIAGNOSTICO=$DBX_ERRORS_REDIGIDO
    fi

    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_HTTP_CODIGO=$codigo
    # Leitura byte a byte, e nao por substituicao de comando, que removeria
    # quebras de linha finais do corpo. A auditoria estatica nao alcanca este
    # caso — o utilitario de copia nao tem prefixo do projeto —, mas a classe e
    # a mesma de D1, C2-01 e E2-04.
    #
    # LIMITE DECLARADO: este canal e para corpo TEXTUAL. Conteudo binario, como
    # o de um recebimento de arquivo, nao pode transitar por variavel de shell,
    # que nao carrega o byte nulo; quando `download` existir, precisara de canal
    # por arquivo ou descritor.
    DBX_HTTP_CORPO=''
    [[ -r $area/resposta ]] && IFS= read -r -d '' DBX_HTTP_CORPO <"$area/resposta"

    _dbx_http_correlacao_de "$area/cabecalhos"

    DBX_HTTP_RESUMO_DE_ERRO=''
    if [[ $codigo -eq 0 || $codigo -ge 400 ]]; then
      _dbx_http_interpretar_erro "$DBX_HTTP_CORPO"
    fi

    # A decisao de repetir CONSULTA a taxonomia; reimplementa-la por codigo HTTP
    # foi defeito real, em que classe e politica se contradiziam.
    DBX_HTTP_CLASSE=$(dbx_errors_classificar "$codigo" "$DBX_HTTP_RESUMO_DE_ERRO")
    politica=$(dbx_errors_politica_retentativa "$codigo" "$DBX_HTTP_RESUMO_DE_ERRO" "$idempotente")
    # shellcheck disable=SC2034  # canal publico, ver nota no topo
    DBX_HTTP_POLITICA=$politica

    if [[ -n $DBX_HTTP_DEFEITO_CLIENTE ]]; then
      # Erro de uso do proprio programa: nao e retentavel e nao e da rede.
      DBX_HTTP_CLASSE='uso_invalido'
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_POLITICA='nenhuma'
      break
    fi

    case $politica in
      recuo_exponencial | respeitar_retry_after)
        [[ $tentativa -lt $DBX_HTTP_TENTATIVAS_MAXIMAS ]] || break
        # RETENTATIVA E PROPRIEDADE DO CANAL, NAO DO TRANSPORTE.
        #
        # No canal de fluxo os bytes ja foram entregues ao consumidor e nao
        # voltam: repetir entregaria o inicio do conteudo duas vezes — corrupcao
        # produzida pela nossa propria politica de confiabilidade, e
        # indistinguivel de conteudo legitimo do lado de fora.
        #
        # Repetir so e seguro quando NADA foi emitido. Medido contra o cliente
        # real: sob `--fail`, uma recusa HTTP emite zero bytes (status 22), e
        # conexao recusada tambem (status 7). Ja o erro de escrita (23) significa
        # que houve transferencia — e ai nao se repete.
        if [[ $_DBX_HTTP_CANAL == 'fluxo' && $estado -ne 22 && $estado -ne 7 ]]; then
          break
        fi
        _dbx_http_esperar "$tentativa"
        tentativa=$((tentativa + 1))
        continue
        ;;
      *)
        break
        ;;
    esac
  done

  # DIAGNOSTICO DO CANAL DE FLUXO: reemissao sem fluxo para obter o corpo do erro.
  #
  # `--fail` impede o corpo de erro de sair como se fosse conteudo — sem ele um
  # 409 vira arquivo local com JSON dentro — mas o preco e ficarmos sem o
  # `error_summary`, e a classificacao cai em `desconhecido` diante de um 404
  # perfeitamente informativo.
  #
  # A reemissao ocorre so no caminho de erro; o caminho feliz nao paga nada.
  # `--fail-with-body` devolveria o corpo, mas pela saida padrao — resolveria o
  # diagnostico reintroduzindo exatamente o problema.
  #
  # LIMITE DECLARADO: o corpo vem de uma requisicao POSTERIOR. Se o recurso mudou
  # entre as duas, o diagnostico descreve outro instante. Diagnostico que descreve
  # outro momento e pior que diagnostico ausente, entao a divergencia fica
  # registrada em vez de silenciada.
  if [[ $_DBX_HTTP_CANAL == 'fluxo' && $DBX_HTTP_CLASSE != 'sucesso' && -n $DBX_HTTP_CODIGO && $DBX_HTTP_CODIGO != '0' ]]; then
    local _canal_original=$_DBX_HTTP_CANAL _destino_original=$_DBX_HTTP_DESTINO
    local _codigo_observado=$DBX_HTTP_CODIGO
    _DBX_HTTP_CANAL=padrao
    _DBX_HTTP_DESTINO=''
    # Nao idempotente: a reemissao existe para diagnosticar, nunca para repetir a
    # operacao. Uma retentativa aqui seria uma segunda tentativa disfarcada.
    _dbx_http_executar "$metodo" "$url" '' nao >/dev/null 2>&1 || true
    _DBX_HTTP_CANAL=$_canal_original
    _DBX_HTTP_DESTINO=$_destino_original
    if [[ $DBX_HTTP_CODIGO != "$_codigo_observado" ]]; then
      # shellcheck disable=SC2034  # canal publico, ver nota no topo
      DBX_HTTP_DIAGNOSTICO="diagnostico obtido em reemissao posterior; o codigo mudou de ${_codigo_observado} para ${DBX_HTTP_CODIGO} entre as duas requisicoes"
    fi
  fi

  [[ $DBX_HTTP_CLASSE == 'sucesso' ]] && return 0
  dbx_errors_codigo_saida "$DBX_HTTP_CLASSE" >/dev/null
  return "$(dbx_errors_codigo_saida "$DBX_HTTP_CLASSE")"
}

# dbx_http_colecao <metodo> <url> <token> <corpo> <limite>
#
# RNF-23: toda chamada que retorne colecao exige limite EXPLICITO. Sem ele, uma
# pasta grande produz corpo acima do teto do analisador e a operacao falha por
# recusa de analise, e nao por erro do servico.
#
# Ao receber `tamanho` como motivo, o limite e REDUZIDO e a chamada repetida —
# abortar deixaria a operacao impossivel para pastas grandes, quando bastava
# pedir menos por pagina.
dbx_http_colecao() {
  [[ $# -ge 5 ]] || return "$DBX_HTTP_ERRO_USO"
  local metodo=$1 url=$2 token=$3 corpo=$4 limite=$5
  local estado corpo_com_limite

  [[ $limite =~ ^[0-9]+$ ]] || return "$DBX_HTTP_ERRO_USO"
  [[ $limite -ge 1 && $limite -le $DBX_HTTP_LIMITE_MAXIMO ]] || return "$DBX_HTTP_ERRO_USO"

  while :; do
    if [[ $corpo == '{'* ]]; then
      corpo_com_limite="{\"limit\":$limite,${corpo#\{}"
    else
      corpo_com_limite="{\"limit\":$limite}"
    fi

    dbx_http_requisitar "$metodo" "$url" "$token" "$corpo_com_limite" sim
    estado=$?

    # O corpo veio bem, mas o analisador recusou por tamanho: peca menos.
    if [[ $estado -eq 0 ]]; then
      dbx_json_contexto http_colecao || return "$DBX_HTTP_ERRO_USO"
      if dbx_json_analisar "$DBX_HTTP_CORPO"; then
        dbx_json_descartar http_colecao
        dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
        return 0
      fi
      local motivo=$DBX_JSON_MOTIVO
      dbx_json_descartar http_colecao
      dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
      if [[ $motivo == 'tamanho' && $limite -gt $DBX_HTTP_LIMITE_MINIMO ]]; then
        limite=$((limite / 2))
        [[ $limite -lt $DBX_HTTP_LIMITE_MINIMO ]] && limite=$DBX_HTTP_LIMITE_MINIMO
        continue
      fi
      return "$(dbx_errors_codigo_saida erro_remoto)"
    fi
    return "$estado"
  done
}
