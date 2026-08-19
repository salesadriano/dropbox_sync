#!/usr/bin/env bash
# cabecalho_test.sh — casos adversariais da RECUSA de valor de cabecalho HTTP.
#
# ESCRITOS ANTES DA IMPLEMENTACAO, pelo QA, a pedido do Senior Developer.
# Enquanto a recusa nao existir, este arquivo REPROVA — e esse e o estado
# esperado nesta fase. Quem implementa nao escreveu estes casos; quem escreveu
# nao implementa.
#
# A PROPRIEDADE FIXADA
#   NOS recusamos valor de cabecalho contendo CR, LF ou byte de controle, com
#   erro explicito, ANTES de qualquer coisa chegar ao cliente HTTP.
#   Nunca "o cliente descarta". Ver a secao MEDICAO: um caso escrito contra o
#   comportamento do cliente teria passado e congelado uma conclusao errada.
#
# CONTRATO PROPOSTO (nomes negociaveis; propriedades nao)
#   dbx_http_cabecalho_valido <valor>
#     status 0                     -> pode ser emitido
#     status $DBX_HTTP_ERRO_USO    -> recusado
#     DBX_HTTP_MOTIVO_CABECALHO    -> causa legivel, SEM ecoar o valor cru
#   DBX_HTTP_LIMITE_CABECALHO      -> teto de bytes do valor
#   O ponto de emissao do modo de conteudo recusa ANTES de invocar o cliente.
#
# MEDICAO QUE FUNDAMENTA ESTES CASOS
# (servidor local proprio; instrumento validado com caso de resposta conhecida
# ANTES de medir, porque nesta area ja houve tres conclusoes falsas por
# instrumento quebrado)
#
#   Valor emitido                   parser estrito(CRLF)  parser tolerante(CR ou LF)
#   "antes<LF>X-Injetado: sim"      nao injeta            nao injeta
#   "antes<CRLF>X-Injetado: sim"    nao injeta            INJETA
#   "antes<CR>X-Injetado: sim"      nao injeta            INJETA
#
#   O cliente medido REMOVE o LF e deixa o CR passar CRU na conexao. Portanto:
#   (a) a reproducao original — "o servidor recebe X-Injetado" por LF — NAO se
#       confirma neste cliente; concluir dai que estamos protegidos seria a
#       quarta conclusao falsa desta area, e a mais cara;
#   (b) o vetor real e o CR SOZINHO, que sobrevive intacto e e tratado como
#       terminador de linha por receptores tolerantes — classe conhecida de
#       contrabando de requisicao;
#   (c) isso e o comportamento de UMA versao de UM cliente. A defesa nao pode
#       depender dele, e ha caso dedicado exatamente a essa independencia.
#
#   TETO DE TAMANHO, medido pelo caminho real (arquivo de opcoes, sem ARG_MAX):
#      8.000 / 65.000 / 100.000 bytes -> chegam integros
#        300.000 bytes                -> chega TRUNCADO (225.920)
#      1.000.000 bytes                -> cabecalho DESCARTADO por inteiro
#   Nos tres casos o cliente sai com 0 e a resposta e 200: truncagem e descarte
#   sao SILENCIOSOS. Para um cabecalho que carrega os parametros da operacao,
#   truncar significa operar com parametro parcial sem sinal algum. Por isso o
#   teto precisa ser nosso, e a violacao precisa ser recusa, nao truncagem.
#
# FORA DE ESCOPO DESTE ARQUIVO
#   Se a API exigir cabecalho em ASCII puro, isso e regra de CODIFICACAO e
#   pertence ao codificador JSON, nao a guarda de seguranca. Estes casos exigem
#   que texto acentuado seja ACEITO pela guarda: recusa-lo tornaria a ferramenta
#   inutil para nomes normais, que e o defeito espelho do vazamento.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"

_area() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/cabecalho.XXXXXX") || return 1
  (cd -P -- "$dir" && pwd -P)
}

# _exige_contrato — falha com mensagem util enquanto a implementacao nao existe.
_exige_contrato() {
  declare -F dbx_http_cabecalho_valido >/dev/null && return 0
  _harness_falhar 'a guarda de cabecalho ainda nao existe' \
    'esperado: dbx_http_cabecalho_valido <valor>; status 0 aceita, status de uso invalido recusa' \
    'estes casos foram escritos antes da implementacao, de proposito'
}

# _recusa <rotulo> <valor> — exige recusa, sem nunca imprimir o valor cru.
_recusa() {
  local rotulo=$1 valor=$2 status
  _exige_contrato
  dbx_http_cabecalho_valido "$valor" >/dev/null 2>&1
  status=$?
  [[ $status -ne 0 ]] || _harness_falhar "valor perigoso foi ACEITO: $rotulo" \
    "comprimento do valor: ${#valor}" \
    'a recusa e nossa; nunca depender de o cliente sanitizar'
  [[ $status -eq $DBX_HTTP_ERRO_USO ]] || _harness_falhar \
    "recusa com status fora do contrato: $rotulo" \
    "esperado: $DBX_HTTP_ERRO_USO" "obtido: $status"
}

# _aceita <rotulo> <valor> — exige aceitacao. Falso positivo tambem e defeito.
_aceita() {
  local rotulo=$1 valor=$2 status
  _exige_contrato
  dbx_http_cabecalho_valido "$valor" >/dev/null 2>&1
  status=$?
  [[ $status -eq 0 ]] || _harness_falhar "valor legitimo foi RECUSADO: $rotulo" \
    "status: $status" 'recusar nome normal torna a ferramenta inutil'
}

# ---------------------------------------------------------------------------
# 1. Terminadores de linha, nas tres posicoes
# ---------------------------------------------------------------------------

teste_recusa_cr_lf_e_crlf_em_qualquer_posicao() {
  local nome seq pos valor
  local -A sequencias=([CR]='\r' [LF]='\n' [CRLF]='\r\n' [LFCR]='\n\r')
  for nome in CR LF CRLF LFCR; do
    # O vetor guarda FORMATOS com escapes, e o formato e o dado do caso. Usar
    # '%s' aqui emitiria a sequencia literal em vez do byte que se quer testar.
    # shellcheck disable=SC2059
    printf -v seq "${sequencias[$nome]}"
    for pos in inicio meio fim; do
      case $pos in
        inicio) valor="${seq}X-Injetado: sim" ;;
        meio) valor="antes${seq}X-Injetado: sim" ;;
        fim) valor="antes${seq}" ;;
      esac
      _recusa "$nome no $pos" "$valor"
    done
  done
}

teste_recusa_terminador_repetido_e_corpo_forjado() {
  # Fim de cabecalhos seguido de corpo: a forma classica de contrabando.
  local duplo
  printf -v duplo '\r\n\r\n'
  _recusa 'CRLF duplo com corpo forjado' "antes${duplo}corpo-forjado"
  printf -v duplo '\n\n'
  _recusa 'LF duplo com corpo forjado' "antes${duplo}corpo-forjado"
}

# ---------------------------------------------------------------------------
# 2. Bytes de controle
# ---------------------------------------------------------------------------

teste_recusa_todo_byte_de_controle() {
  # 0x00 nao e testavel por variavel de shell, que nao carrega o byte nulo.
  # A rota por escape unicode esta coberta no caso proprio, abaixo.
  local codigo byte _octal
  for codigo in $(seq 1 31) 127; do
    # RSK-28: dois `printf -v` em vez de substituicao de comando. A regra vale para
    # quem escreve o caso, e a auditoria apanhou esta linha na primeira execucao.
    printf -v _octal '%03o' "$codigo"
    printf -v byte '%b' "\\$_octal"
    _recusa "byte de controle $codigo" "antes${byte}depois"
  done
}

teste_recusa_byte_de_controle_isolado_sem_texto_ao_redor() {
  local byte
  printf -v byte '%b' '\013'
  _recusa 'byte de controle sozinho' "$byte"
}

# ---------------------------------------------------------------------------
# 3. Rotas de contorno da guarda
# ---------------------------------------------------------------------------

teste_recusa_cr_produzido_por_escape_unicode_do_analisador() {
  # O valor chega como JSON e e DECODIFICADO por lib/json antes de virar
  # cabecalho. Uma guarda aplicada ao texto JSON, e nao ao valor decodificado,
  # deixaria passar: no JSON nao ha CR cru, ha a sequencia de escape unicode.
  local decodificado
  dbx_json_contexto cabecalho
  dbx_json_analisar '{"nome":"antes
X-Injetado: sim"}' ||
    _harness_falhar 'a montagem do caso falhou ao analisar o JSON'
  dbx_json_valor nome >/dev/null
  decodificado=$DBX_JSON_RESULTADO
  dbx_json_descartar cabecalho
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  _recusa 'CR vindo de escape unicode decodificado' "$decodificado"
}

teste_recusa_utf8_sobrelongo_de_cr_e_de_lf() {
  # Forma sobrelonga: nao e CR nem LF na conexao, mas decodificador permissivo
  # a jusante pode normaliza-la para o caractere de controle.
  local sobrelongo
  printf -v sobrelongo '%b' '\300\215'
  _recusa 'UTF-8 sobrelongo de CR' "antes${sobrelongo}depois"
  printf -v sobrelongo '%b' '\300\212'
  _recusa 'UTF-8 sobrelongo de LF' "antes${sobrelongo}depois"
}

# ---------------------------------------------------------------------------
# 4. Discriminacao — falso positivo e o defeito espelho
# ---------------------------------------------------------------------------

teste_aceita_nome_de_arquivo_legitimo() {
  _aceita 'texto comum com espacos' 'relatorio de dezembro - versao final.pdf'
  _aceita 'acentuacao e cedilha' 'cotacao de orcamento do servico.txt'
  _aceita 'espacos multiplos' 'a    b'
  # shellcheck disable=SC2016  # o cifrao e a crase sao o dado do caso, nao expansao
  _aceita 'metacaracteres de shell' 'arquivo $VAR `cmd` "aspas" (1).txt'
  _aceita 'chaves e colchetes' '{"json":"no nome"}.txt'
  _aceita 'dois-pontos, que separa nome de valor' 'as 10:30 - ata.txt'
  _aceita 'utf-8 de quatro bytes' 'ferias-2026.jpg'
  _aceita 'til e barra invertida' 'a~b\c.txt'
  _aceita 'valor vazio' ''
}

teste_aceita_sequencia_percentual_literal() {
  # `%0A` sao tres caracteres imprimiveis. Recusa-lo seria barrar um nome de
  # arquivo perfeitamente legitimo por parecer perigoso.
  _aceita 'percentual literal maiusculo' 'antes%0Adepois'
  _aceita 'percentual literal minusculo' 'antes%0ddepois'
  _aceita 'percentual duplamente codificado' 'antes%250Adepois'
}

teste_motivo_da_recusa_nao_ecoa_o_valor_recusado() {
  # O diagnostico da recusa nao pode carregar o proprio CR para dentro de um
  # registro: seria transportar o vetor do ponto onde foi barrado ate o log.
  local perigoso
  _exige_contrato
  printf -v perigoso 'antes\rX-Injetado: sim'
  dbx_http_cabecalho_valido "$perigoso" >/dev/null 2>&1
  [[ -n ${DBX_HTTP_MOTIVO_CABECALHO:-} ]] ||
    _harness_falhar 'a recusa precisa publicar um motivo legivel'
  case $DBX_HTTP_MOTIVO_CABECALHO in
    *$'\r'* | *$'\n'*)
      _harness_falhar 'o motivo da recusa carrega o proprio terminador de linha' \
        'o diagnostico levaria o vetor para dentro do registro'
      ;;
  esac
  assert_nao_contem 'X-Injetado' "$DBX_HTTP_MOTIVO_CABECALHO" \
    'o motivo nao deve ecoar o conteudo injetado'
}

# ---------------------------------------------------------------------------
# 5. Teto de tamanho — medido, nao arbitrado
# ---------------------------------------------------------------------------

teste_teto_de_cabecalho_existe_e_e_conservador() {
  _exige_contrato
  [[ -n ${DBX_HTTP_LIMITE_CABECALHO:-} ]] ||
    _harness_falhar 'nao ha teto declarado para o valor de cabecalho' \
      'medido: 300.000 bytes chegam truncados e 1.000.000 sao descartados, ambos em silencio'
  [[ $DBX_HTTP_LIMITE_CABECALHO -le 65536 ]] ||
    _harness_falhar 'teto acima da faixa medida como segura' \
      "declarado: $DBX_HTTP_LIMITE_CABECALHO" \
      'integro ate 100.000 bytes; truncagem silenciosa a partir dai'
}

teste_recusa_valor_acima_do_teto() {
  local grande
  _exige_contrato
  printf -v grande 'a%.0s' $(seq 1 $((DBX_HTTP_LIMITE_CABECALHO + 1)))
  _recusa 'valor um byte acima do teto' "$grande"
}

teste_aceita_valor_no_teto() {
  local no_limite
  _exige_contrato
  printf -v no_limite 'a%.0s' $(seq 1 "$DBX_HTTP_LIMITE_CABECALHO")
  _aceita 'valor exatamente no teto' "$no_limite"
}

# ---------------------------------------------------------------------------
# 6. A guarda vive no PONTO DE EMISSAO, e nao apenas na funcao isolada
# ---------------------------------------------------------------------------

# _duplo_registrando — cliente substituto que registra CADA invocacao e repassa
# o valor SEM sanitizar. Cliente permissivo e o cenario correto aqui: a nossa
# garantia nao pode depender da bondade do cliente.
# Todo o corpo emite TEXTO de um script que sera executado depois: os cifroes
# sao do duplo gerado, nao desta funcao, e expandem na execucao dele.
# shellcheck disable=SC2016
_duplo_registrando() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/duplo.XXXXXX")
  : >"$dir/invocacoes"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    printf 'printf "1\\n" >>"$dir/invocacoes"\n'
    printf 'cat >"$dir/entrada" 2>/dev/null\n'
    printf 'a=""; s=""; c=""; w=""\n'
    printf 'for x in "$@"; do case $a in -o) s=$x ;; -D) c=$x ;; -w) w=$x ;; esac; a=$x; done\n'
    printf '[[ -n $s ]] && printf "{}" >"$s"\n'
    printf '[[ -n $c ]] && : >"$c"\n'
    printf '[[ -n $w ]] && printf "200"\n'
    printf 'exit 0\n'
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

_emissor() {
  # O modo de conteudo ainda nao existe. Quando existir, este e o ponto que
  # precisa recusar. Enquanto nao existir, o caso reprova com mensagem util.
  declare -F dbx_http_conteudo >/dev/null && return 0
  _harness_falhar 'o ponto de emissao do modo de conteudo ainda nao existe' \
    'esperado: funcao que emita Dropbox-API-Arg e recuse valor inseguro ANTES de invocar o cliente'
}

teste_emissao_recusa_antes_de_invocar_o_cliente() {
  local dir perigoso invocacoes status
  _emissor
  dir=$(_duplo_registrando)
  printf -v perigoso '{"path":"/a\rAuthorization: Bearer outro"}'
  (
    # O escopo local ao subshell e o objetivo: o duplo so vale dentro do
    # parenteses, e a suite segue com o PATH real depois dele.
    # shellcheck disable=SC2030,SC2031
    PATH="$dir:$PATH"
    dbx_http_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
      TOKEN "$perigoso" /dev/null nao >/dev/null 2>&1
  )
  status=$?
  # `grep -c` imprime 0 E sai com 1 quando nao ha correspondencia, entao o
  # fallback disparava ALEM da saida, produzindo "0\n0". Falhava exatamente no
  # caso que importa: o de cliente nao invocado. `wc -l` sai 0 e imprime 0.
  invocacoes=$(wc -l <"$dir/invocacoes" 2>/dev/null || printf 0)
  invocacoes=${invocacoes// /}
  assert_igual 0 "$invocacoes" \
    'o cliente NAO pode ser invocado com valor de cabecalho inseguro'
  [[ $status -ne 0 ]] ||
    _harness_falhar 'a emissao com valor inseguro devolveu sucesso'
}

teste_emissao_aceita_valor_legitimo_e_invoca_o_cliente() {
  # Discriminacao no MESMO ponto: sem isto, uma implementacao que recusasse
  # tudo passaria no caso anterior.
  local dir invocacoes
  _emissor
  dir=$(_duplo_registrando)
  (
    # O escopo local ao subshell e o objetivo: o duplo so vale dentro do
    # parenteses, e a suite segue com o PATH real depois dele.
    # shellcheck disable=SC2030,SC2031
    PATH="$dir:$PATH"
    dbx_http_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
      TOKEN '{"path":"/relatorio de dezembro.pdf"}' /dev/null nao >/dev/null 2>&1
  )
  # `grep -c` imprime 0 E sai com 1 quando nao ha correspondencia, entao o
  # fallback disparava ALEM da saida, produzindo "0\n0". Falhava exatamente no
  # caso que importa: o de cliente nao invocado. `wc -l` sai 0 e imprime 0.
  invocacoes=$(wc -l <"$dir/invocacoes" 2>/dev/null || printf 0)
  invocacoes=${invocacoes// /}
  [[ $invocacoes -ge 1 ]] ||
    _harness_falhar 'valor legitimo nao chegou ao cliente' \
      'recusar nome normal torna a ferramenta inutil'
}

teste_a_garantia_nao_depende_do_comportamento_do_cliente() {
  # O substituto acima repassa o valor SEM sanitizar. Se a nossa protecao
  # dependesse de o cliente limpar, este caso passaria a falhar no dia em que o
  # cliente mudasse de versao — e a suite so descobriria em producao.
  local dir entrada _arg_com_cr
  # RSK-28: massa por printf -v, nunca por substituicao de comando.
  printf -v _arg_com_cr '{"path":"/a\rX-Injetado: sim"}'
  _emissor
  dir=$(_duplo_registrando)
  (
    # O escopo local ao subshell e o objetivo: o duplo so vale dentro do
    # parenteses, e a suite segue com o PATH real depois dele.
    # shellcheck disable=SC2030,SC2031
    PATH="$dir:$PATH"
    dbx_http_conteudo POST 'https://content.dropboxapi.com/2/files/upload' \
      TOKEN "$_arg_com_cr" /dev/null nao >/dev/null 2>&1
  )
  entrada=$(cat "$dir/entrada" 2>/dev/null || printf '')
  assert_nao_contem 'X-Injetado' "$entrada" \
    'nada com terminador de linha pode alcancar o cliente, ainda que ele fosse sanitizar'
}

# ---------------------------------------------------------------------------
# 7. Caminho completo: nome de arquivo real ate o ponto de emissao
# ---------------------------------------------------------------------------

teste_nome_de_arquivo_real_com_cr_nao_produz_cabecalho_inseguro() {
  # A guarda tem de valer no caminho INTEIRO, e nao so na funcao isolada: o
  # valor nasce de um nome de arquivo do usuario e atravessa lib/path e o
  # codificador antes de virar cabecalho.
  #
  # Duas saidas sao aceitaveis: o codificador escapou o CR, e ai a guarda
  # aceita; ou nao escapou, e ai a guarda recusa. O que NAO e aceitavel e um
  # valor com CR cru ser dado como bom.
  local area nome caminho arg
  area=$(_area)
  printf -v nome 'relatorio\rAuthorization: Bearer outro.txt'
  printf 'conteudo' >"$area/$nome" 2>/dev/null ||
    pular 'o sistema de arquivos nao aceitou nome com CR'
  dbx_path_local_confinar "$area" "$nome" >/dev/null ||
    _harness_falhar 'o confinamento recusou um nome que existe dentro da raiz'
  caminho=$DBX_PATH_RESULTADO
  dbx_json_escapar_cadeia "${caminho##*/}"
  arg="{\"path\":\"/$DBX_JSON_ESCAPADO\"}"
  _exige_contrato
  if dbx_http_cabecalho_valido "$arg" >/dev/null 2>&1; then
    case $arg in
      *$'\r'* | *$'\n'*)
        _harness_falhar 'valor aceito ainda contendo terminador de linha cru' \
          'o codificador nao escapou e a guarda nao recusou'
        ;;
    esac
  fi
}

teste_nome_de_arquivo_real_legitimo_atravessa_o_caminho_completo() {
  local area nome arg
  area=$(_area)
  nome='relatorio de dezembro (versao final).pdf'
  printf 'conteudo' >"$area/$nome"
  dbx_path_local_confinar "$area" "$nome" >/dev/null ||
    _harness_falhar 'o confinamento recusou um nome legitimo'
  dbx_json_escapar_cadeia "${DBX_PATH_RESULTADO##*/}"
  arg="{\"path\":\"/$DBX_JSON_ESCAPADO\"}"
  _aceita 'nome legitimo apos lib/path e codificador' "$arg"
}

harness_executar "$@"
