#!/usr/bin/env bash
# lib/transfer.sh — envio em partes por sessao (RF-08, RF-09, RF-31).
#
# Camada: orquestracao. Fica entre `commands/upload` e o transporte: decide
# QUANDO ha sessao, conduz a sequencia e conta os bytes; nao monta cabecalho,
# nao fala com o cliente de rede e nao decide o que publicar — o objeto de
# publicacao (`commit`) chega pronto do comando.
#
# Depende de lib/errors, lib/json, lib/hash e lib/auth. Nao e carregado por
# `bin/dbx`: `commands/upload` o carrega sob demanda, no unico caminho que o usa.
#
# ---------------------------------------------------------------------------
# SEQUENCIA
# ---------------------------------------------------------------------------
#   start  -> corpo VAZIO, sessao SEQUENCIAL (o tipo omitido e o padrao)
#   append -> um por parte CHEIA, com o deslocamento acumulado no cursor
#   finish -> ultimo bloco (possivelmente vazio) mais o `commit`
#
# O deslocamento e a chave de deduplicacao do servico: o contrato documenta
# `offset` como "the amount of data that has been uploaded so far", e existe
# para que uma retentativa nao perca nem duplique dado. Por isso a retentativa
# repete a MESMA requisicao com o MESMO deslocamento — e nao um deslocamento
# recalculado.
#
# PROCEDENCIA DO CONTRATO: o desenho acima segue o `files.stone` publicado pela
# Dropbox (repositorio `dropbox-api-spec`, ramo `main`). E contrato DOCUMENTADO,
# lido, NAO exercitado contra o servico real. Onde o texto e ambiguo, este
# componente escolhe a alternativa que falha fechada, e a ambiguidade fica
# escrita ao lado da escolha.
#
# ---------------------------------------------------------------------------
# TAMANHO DE PARTE FIXO — LACUNA DE RF-08 DECLARADA
# ---------------------------------------------------------------------------
# RF-08 pede tamanho de parte CONFIGURAVEL. Esta entrega NAO o torna
# configuravel, e a lacuna fica declarada aqui em vez de silenciada.
#
# Motivo: nesta implementacao o tamanho da parte e a MESMA grandeza que o
# tamanho do bloco do `content_hash`. Uma parte de tamanho diferente do bloco
# faria a cadeia de resumos ser montada sobre fatias que nao sao blocos, e o
# resultado seria um `content_hash` bem formado e errado — divergencia que so
# apareceria na comparacao com o servico. Tornar o valor configuravel sem antes
# SEPARAR as duas nocoes (fatia de rede e bloco de resumo) quebraria a cadeia em
# silencio, que e a pior forma de errar.
#
# Ha ainda uma razao de requisito: para a entrada padrao, o teto de ocupacao de
# RF-31 e exatamente UM BLOCO. Enquanto parte e bloco forem a mesma grandeza, o
# teto e uma consequencia estrutural e nao uma promessa a vigiar.
#
# Trabalho futuro declarado: separar `parte de rede` de `bloco de resumo`,
# permitindo parte multipla do bloco, e so entao expor o valor.
#
# ---------------------------------------------------------------------------
# TETO DE OCUPACAO EM DISCO (RF-31)
# ---------------------------------------------------------------------------
# Um unico arquivo de bloco, reaproveitado a cada volta, em area propria criada
# com `mktemp -d` sob `umask 077`. A ocupacao nao acompanha o tamanho do
# conteudo: ela e a de uma parte, seja o fluxo de 8 MiB ou de 800 GiB.
#
# LIMITE DECLARADO, herdado de lib/hash: no encerramento o mesmo arquivo recebe
# a CADEIA de resumos, que tem 32 bytes por bloco. Logo o pico real e o maior
# entre uma parte e 32 x N. Ultrapassar uma parte exigiria 131.072 blocos, isto
# e 512 GiB de conteudo. Nao e "sempre uma parte"; e uma parte ate essa marca.
#
# ---------------------------------------------------------------------------
# LEITURA SEM CANO
# ---------------------------------------------------------------------------
# `head -c N >arquivo`, com o status observado diretamente, e `wc -c <arquivo`
# para o tamanho. O motivo esta medido em lib/hash: por cano, apenas o status do
# ultimo comando e observavel, e EIO, truncamento sob leitura ou produtor morto
# no meio produziam resumo bem formado de conteudo INCOMPLETO com status 0.
# Declarar integridade sobre dado truncado e o pior resultado possivel.
#
# LIMITE QUE ESTE COMPONENTE NAO COBRE, E QUE NAO ADIANTA FINGIR QUE COBRE:
# quando a origem e um cano anonimo, PRODUTOR QUE MORRE NO MEIO E
# INDISTINGUIVEL DE FIM DE FLUXO LEGITIMO. O cano fecha e nos vemos EOF nos dois
# casos; o status de saida do produtor pertence ao shell do operador e nunca
# chega a este processo. Portanto o criterio de RF-31 "dado que a origem do
# fluxo falhe no meio, entao nenhum arquivo parcial e publicado" e cumprido para
# FALHA DE LEITURA — status nao zero do leitor, que aqui e observavel e aborta a
# sessao — e NAO para produtor que encerrou mal depois de escrever um prefixo.
# Nesse segundo caso publicamos o prefixo como se fosse o arquivo inteiro.
#
# MEDIDO, e nao suposto: com um produtor que escreve 5.000.000 bytes e sai com
# status 3, o comando publica os 5.000.000 bytes e sai com ZERO. Com
# `set -o pipefail` no shell do operador, o encadeamento devolve 3 — a falha
# reaparece, mas do lado de quem tem a informacao. Por isso a recomendacao ao
# operador e essa, e nao uma promessa nossa que nao podemos cumprir.
#
# ---------------------------------------------------------------------------
# INTEGRIDADE PONTA A PONTA, E O QUE NAO SE ENVIA POR PARTE
# ---------------------------------------------------------------------------
# O `content_hash` e acumulado localmente parte a parte e comparado com o que o
# `finish` devolve no metadado. Divergencia e classe `integridade`.
#
# NAO enviamos `content_hash` por parte no `append`, embora o campo exista no
# argumento. Motivo: a interpretacao exata do campo por chamada — se e o resumo
# daquela parte, do acumulado, ou do arquivo final — nao pode ser validada fora
# do servico, e errar significaria quebrar TODO envio em partes de um jeito que
# a suite nao apanha, porque o duplo aceitaria qualquer valor. A comparacao
# contra o `content_hash` do `finish` da a mesma garantia de ponta a ponta sem
# arriscar contrato. Melhoria futura declarada: enviar por parte depois de
# verificar o campo contra o servico real.
#
# ---------------------------------------------------------------------------
# NADA PARCIAL PUBLICADO
# ---------------------------------------------------------------------------
# O arquivo so existe no destino quando o `finish` retorna. Qualquer falha antes
# disso encerra sem `finish`, e a sessao abandonada expira sozinha no servico —
# nao ha chamada de aborto de sessao no contrato, e inventar uma seria fabricar
# API. O que se perde e cota de sessao aberta, nao dado do operador.

[[ -n ${DBX_TRANSFER_CARREGADO:-} ]] && return 0
DBX_TRANSFER_CARREGADO=1

_dbx_transfer_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_transfer_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_transfer_diretorio=.
_dbx_transfer_diretorio=$(cd -P -- "$_dbx_transfer_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_transfer_diretorio/errors.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_transfer_diretorio/hash.sh"
# shellcheck source=lib/progress.sh
. "$_dbx_transfer_diretorio/progress.sh"
unset _dbx_transfer_diretorio

# Parte de 4 MiB — a MESMA grandeza do bloco do `content_hash`. A igualdade e
# verificada em teste: separa-las sem separar as nocoes quebraria a cadeia.
readonly DBX_TRANSFER_TAMANHO_PARTE=4194304
# Teto por requisicao publicado pela Dropbox. Acima dele o servico devolve
# `payload_too_large`. E tambem o limiar de roteamento de RF-08: arquivo local
# maior que isto nao cabe em requisicao unica.
readonly DBX_TRANSFER_LIMITE_REQUISICAO=157286400

readonly DBX_TRANSFER_URL_INICIAR='https://content.dropboxapi.com/2/files/upload_session/start'
readonly DBX_TRANSFER_URL_ANEXAR='https://content.dropboxapi.com/2/files/upload_session/append_v2'
readonly DBX_TRANSFER_URL_CONCLUIR='https://content.dropboxapi.com/2/files/upload_session/finish'

DBX_TRANSFER_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_TRANSFER_ERRO_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly DBX_TRANSFER_ERRO_USO DBX_TRANSFER_ERRO_NAO_CONCLUIDA

# Canais publicos, consumidos por `commands/upload` e pela suite.
# shellcheck disable=SC2034
# Justificativa: classe da taxonomia da ultima falha, lida pelo comando.
DBX_TRANSFER_CLASSE=''
# shellcheck disable=SC2034
# Justificativa: diagnostico ja redigido da ultima falha, lido pelo comando.
DBX_TRANSFER_MOTIVO=''
# shellcheck disable=SC2034
# Justificativa: `content_hash` acumulado localmente, lido pelo comando.
DBX_TRANSFER_CONTENT_HASH=''
# shellcheck disable=SC2034
# Justificativa: total de bytes lidos da origem, exigido por RF-31.
DBX_TRANSFER_BYTES=0
# shellcheck disable=SC2034
# Justificativa: `conferida` ou `nao_aplicavel`; o comando publica o valor.
DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'
# shellcheck disable=SC2034
# Justificativa: tamanho medido por `dbx_transfer_tamanho_de_arquivo`.
DBX_TRANSFER_TAMANHO=0
DBX_TRANSFER_LIDO=''

# DELIBERADAMENTE global, e nao `local`: a acao do `trap` e avaliada quando o
# escopo da funcao ja nao existe. Com variavel local a expansao viraria vazia e
# a limpeza nao removeria nada — defeito ja corrigido em lib/hash e em lib/http,
# e que voltaria aqui se a disciplina fosse reescrita em vez de reusada.
DBX_TRANSFER_AREA_TEMP=''

# ---------------------------------------------------------------------------
# Roteamento por tamanho (RF-08)
# ---------------------------------------------------------------------------

# dbx_transfer_precisa_de_sessao <bytes> — 0 quando o conteudo nao cabe em uma
# requisicao unica.
#
# Predicado PURO, sobre numero. O tamanho e medido por quem tem o arquivo; aqui
# so se compara, para que o limiar tenha um unico dono e um caso de teste possa
# exercitar a fronteira sem materializar 150 MiB.
dbx_transfer_precisa_de_sessao() {
  local bytes=${1-}
  [[ $bytes =~ ^[0-9]+$ ]] || return "$DBX_TRANSFER_ERRO_USO"
  [[ $bytes -gt $DBX_TRANSFER_LIMITE_REQUISICAO ]]
}

# dbx_transfer_tamanho_de_arquivo <caminho> — publica o tamanho em
# DBX_TRANSFER_TAMANHO.
#
# MEDIDO, nunca declarado: o roteamento decide sobre o arquivo que existe agora,
# e nao sobre o que o chamador supoe.
dbx_transfer_tamanho_de_arquivo() {
  local caminho=${1-} bytes
  DBX_TRANSFER_TAMANHO=0
  [[ -n $caminho && -r $caminho ]] || return "$DBX_TRANSFER_ERRO_USO"
  bytes=$(wc -c <"$caminho") || return "$DBX_TRANSFER_ERRO_USO"
  bytes=${bytes//[^0-9]/}
  [[ -n $bytes ]] || return "$DBX_TRANSFER_ERRO_USO"
  # shellcheck disable=SC2034
  # Justificativa: canal publico lido por `commands/upload` para decidir o
  # roteamento. A analise estatica nao cruza arquivos.
  DBX_TRANSFER_TAMANHO=$bytes
  return 0
}

# ---------------------------------------------------------------------------
# Diagnostico e leitura de resposta
# ---------------------------------------------------------------------------

# _dbx_transfer_falhar <classe> <motivo> — publica classe e motivo redigido.
#
# Chamada SEMPRE em `{ ...; return $?; }`, nunca em `return "$(...)"`: a segunda
# forma roda em subshell e a publicacao se perderia junto com ele. E o defeito
# C2-01, ja pago duas vezes neste projeto.
_dbx_transfer_falhar() {
  local classe=$1 motivo=$2
  dbx_errors_redigir "$motivo" >/dev/null
  DBX_TRANSFER_CLASSE=$classe
  DBX_TRANSFER_MOTIVO=$DBX_ERRORS_REDIGIDO
  return "$(dbx_errors_codigo_saida "$classe")"
}

# _dbx_transfer_ler_campo <segmentos...> — le um campo do corpo da ultima
# resposta em CONTEXTO NOMEADO PROPRIO.
#
# Contexto proprio, e nome literal: usar o contexto do comando destruiria a
# analise que ele mantem, e derivar o nome de dado externo e o defeito que a
# auditoria de contexto nomeado existe para impedir. O corpo bruto permanece em
# DBX_HTTP_CORPO para quem quiser reanalisa-lo — e o que `commands/upload` faz
# com o metadado do `finish`.
_dbx_transfer_ler_campo() {
  local estado=1
  DBX_TRANSFER_LIDO=''
  [[ -n ${DBX_HTTP_CORPO:-} ]] || return 1
  dbx_json_contexto transferencia || return 1
  if dbx_json_analisar "$DBX_HTTP_CORPO"; then
    if dbx_json_valor "$@" >/dev/null; then
      DBX_TRANSFER_LIDO=$DBX_JSON_RESULTADO
      estado=0
    fi
  fi
  dbx_json_descartar transferencia
  # A restauracao usa o canal DIRETAMENTE, e nao uma copia local. Nao e estilo:
  # a auditoria de procedencia de contexto so aceita nome literal ou este canal,
  # justamente porque um nome vindo de variavel qualquer poderia ter procedencia
  # externa — e nome de contexto derivado de dado remoto faz dois corpos de erro
  # colidirem no mesmo contexto, destruindo o primeiro. Guardar numa local
  # escaparia da auditoria sem mudar o risco, que e o pior dos dois mundos.
  # Seguro aqui: nada entre a selecao e esta linha troca de contexto.
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # shellcheck disable=SC2034  # canal publico alheio, limpo por quem o encheu
  DBX_JSON_RESULTADO=''
  return $estado
}

# _dbx_transfer_deslocamento_correto — le `correct_offset` do corpo de erro.
#
# DUAS FORMAS ACEITAS, e a razao esta escrita porque nao foi medida: o contrato
# declara `incorrect_offset` como membro de uniao carregando
# `UploadSessionOffsetError{correct_offset}`, mas a serializacao exata da carga
# de uniao — achatada no objeto `error` ou aninhada sob a tag — nao foi
# verificada contra o servico. Aceitar as duas formas nao cria risco: se nenhuma
# estiver presente, a funcao falha e a sessao aborta fechada.
_dbx_transfer_deslocamento_correto() {
  _dbx_transfer_ler_campo error correct_offset && return 0
  _dbx_transfer_ler_campo error incorrect_offset correct_offset && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Ciclo de vida da area temporaria
# ---------------------------------------------------------------------------

_dbx_transfer_remover_area() {
  [[ -n ${DBX_TRANSFER_AREA_TEMP:-} ]] && rm -rf -- "$DBX_TRANSFER_AREA_TEMP"
  DBX_TRANSFER_AREA_TEMP=''
  return 0
}

# _dbx_transfer_interrompida — sinal no meio da sessao.
#
# Encerra o PROCESSO, e nao apenas a funcao: sem `finish` nada foi publicado, a
# sessao abandonada expira sozinha e continuar depois de um sinal produziria
# envio parcial travestido de sucesso. O codigo e o de operacao nao concluida,
# que e literalmente o que aconteceu.
#
# ---------------------------------------------------------------------------
# PALIATIVO DECLARADO: esta funcao remove tambem a area de `lib/http`
# ---------------------------------------------------------------------------
# Isto VIOLA a disciplina "quem enche o canal de outro componente o esvazia", e a
# violacao esta escrita aqui em vez de escondida.
#
# O defeito: `lib/http` limpa a propria area com `trap ... RETURN`, que dispara
# SO no retorno normal da funcao. Esta funcao faz `exit`, e `exit` nao dispara
# `RETURN` — medido: `f(){ trap "echo X" RETURN; exit 7; }; f` nao imprime nada,
# enquanto o controle com `return 0` imprime. Sem esta linha, uma interrupcao no
# meio de um `append` deixava `dbx-http.XXXX/{erro_cliente,cabecalhos,resposta}`
# em `$TMPDIR`, com corpo do usuario dentro.
#
# POR QUE NAO A CORRECAO OBVIA: fazer `lib/http` armar `EXIT INT TERM HUP`
# resolveria a limpeza dele e QUEBRARIA a nossa. `trap` e global ao shell, e
# `dbx_transfer_sessao` ja arma `EXIT` para remover a PROPRIA area — o segundo
# `trap` atropelaria o primeiro. Trocaria um vazamento por uma regressao de
# limpeza, que e negocio pior.
#
# CORRECAO ESTRUTURAL, nao feita aqui: o componente `lib/tmp`, dono UNICO de area
# temporaria, ja no backlog do projeto. Enquanto ele nao existir, tres
# componentes criam area sob `$TMPDIR` com tres ciclos de vida diferentes, e
# qualquer arranjo entre eles e paliativo.
#
# RECORTE QUE PERMANECE, e que o caso de teste declara em vez de esconder: isto
# cobre o caminho em que ESTE tratador roda. Sinal que chegue fora dessa janela —
# antes de o `trap` ser armado, depois de `trap -`, ou durante um `upload` por
# requisicao unica, que nao passa pelo transfer — continua vazando por
# `lib/http`. Pendencia aberta.
_dbx_transfer_interrompida() {
  _dbx_transfer_remover_area
  [[ -n ${DBX_HTTP_AREA_TEMP:-} ]] && rm -rf -- "$DBX_HTTP_AREA_TEMP"
  DBX_HTTP_AREA_TEMP=''
  exit "$DBX_TRANSFER_ERRO_NAO_CONCLUIDA"
}

# ---------------------------------------------------------------------------
# Emissao
# ---------------------------------------------------------------------------

# _dbx_transfer_emitir <url> <argumento> <arquivo_de_corpo> <idempotente>
#
# A entrada padrao da chamada e desviada de `/dev/null` DE PROPOSITO: a entrada
# padrao desta funcao e o FLUXO DE DADOS do operador, e qualquer comando da
# cadeia de autenticacao que a lesse consumiria bytes do conteudo. O prejuizo
# seria silencioso — o arquivo remoto sairia menor, com resumo coerente com o
# que sobrou.
_dbx_transfer_emitir() {
  local url=$1 argumento=$2 corpo=$3 idempotente=$4
  dbx_auth_conteudo POST "$url" "$argumento" "$corpo" "$idempotente" </dev/null
}

# _dbx_transfer_anexar <sessao_json> <deslocamento> <tamanho> <arquivo_de_corpo>
#
# RF-09 em duas camadas, e a segunda e a que importa:
#
#   1. `idempotente=sim` deixa lib/http repetir a MESMA requisicao, com o MESMO
#      deslocamento e o MESMO corpo, ate tres vezes. Repetir uma parte nao
#      reinicia o arquivo — e o que RF-09 pede.
#
#   2. RECONCILIACAO DE DESLOCAMENTO. Se o servico recusa com `incorrect_offset`
#      e informa um `correct_offset` igual ao FIM desta parte, entao esta parte
#      ja foi aceita numa tentativa anterior cuja resposta se perdeu: insistir
#      duplicaria conteudo. Tratamos como progresso e avancamos.
#
# A PROPRIEDADE QUE IMPORTA: a reconciliacao torna a retentativa correta
# INDEPENDENTEMENTE de a primeira tentativa ter chegado ou nao. O contrato
# documentado confirma o desenho — `incorrect_offset` e descrito exatamente como
# o caso da resposta perdida —, mas o desenho nao depende dessa confirmacao: ele
# depende apenas de o servico dizer onde acha que esta.
#
# Qualquer outro valor de `correct_offset` significa discordancia real sobre o
# que ja chegou. Nao ha reposicionamento possivel: a entrada padrao nao e
# posicionavel e reler nao e opcao. Abortamos, e o diagnostico diz os dois
# numeros para que a divergencia seja diagnosticavel sem adivinhacao.
#
# ---------------------------------------------------------------------------
# QUEM RECONHECE A CONDICAO DE SESSAO: `lib/errors.sh`, E SO ELE
# ---------------------------------------------------------------------------
# Esta funcao NAO reconhece a tag por conta propria. Ela le a POLITICA que
# `lib/http` publica em `DBX_HTTP_POLITICA`, e essa politica vem inteira da
# taxonomia — que casa prefixo em FRONTEIRA DE COMPONENTE
# (`_dbx_errors_prefixo_casa`) e remove qualificadores de uniao um a um.
#
# A versao anterior decidia DE NOVO, com glob de substring
# (`*incorrect_offset*`), e a regra passou a ter dois donos. Eles ja divergiam,
# e a divergencia foi MEDIDA com `error_summary=path/conflict/incorrect_offset_like`:
#   taxonomia -> classe `conflito`, politica `nenhuma`
#   transfer  -> ramo de deslocamento, abortando com "por deslocamento
#                incorreto"
# Falha fechada nas duas, mas com DIAGNOSTICO ERRADO: mandava investigar
# deslocamento diante de um conflito de caminho. E a familia de gemeos que este
# projeto ja pagou oito vezes, na sua forma mais barata de evitar — bastava
# consultar quem ja sabia.
#
# `reiniciar` (tag `reset`) tambem passa a ter tratamento PROPRIO. Antes caia no
# ramo generico: falha fechada, sem dizer que a causa era invalidacao da sessao.
# Reiniciar exige reler a origem desde o inicio, e com entrada padrao isso e
# impossivel — entao a resposta correta e abortar dizendo exatamente isso, e nao
# tentar um reinicio que publicaria conteudo embaralhado.
_dbx_transfer_anexar() {
  local sessao=$1 deslocamento=$2 tamanho=$3 corpo=$4
  local argumento esperado=$((deslocamento + tamanho)) correto

  argumento="{\"cursor\":{\"session_id\":\"$sessao\",\"offset\":$deslocamento},\"close\":false}"
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_ANEXAR" "$argumento" "$corpo" sim && return 0

  case ${DBX_HTTP_POLITICA:-} in
    retomar)
      if _dbx_transfer_deslocamento_correto; then
        correto=$DBX_TRANSFER_LIDO
        if [[ $correto =~ ^[0-9]+$ && $correto -eq $esperado ]]; then
          return 0
        fi
        {
          _dbx_transfer_falhar nao_concluida \
            "deslocamento divergente na parte que comeca em $deslocamento: apos esta parte o deslocamento seria $esperado e o servico informou $correto; a entrada padrao nao e posicionavel e reler nao e opcao"
          return $?
        }
      fi
      {
        _dbx_transfer_falhar nao_concluida \
          "o servico recusou a parte que comeca em $deslocamento por deslocamento incorreto e nao informou o deslocamento correto"
        return $?
      }
      ;;
    reiniciar)
      {
        _dbx_transfer_falhar nao_concluida \
          "o servico invalidou a sessao na parte que comeca em $deslocamento e exige reiniciar o envio desde o inicio; a entrada padrao nao e posicionavel e reler nao e opcao, entao nada foi publicado no destino"
        return $?
      }
      ;;
  esac

  {
    _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "parte que comeca em $deslocamento recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
}

# ---------------------------------------------------------------------------
# Sessao
# ---------------------------------------------------------------------------

# dbx_transfer_sessao <argumento_de_commit> — le a ENTRADA PADRAO e publica.
#
# Ha um unico laco de sessao, e ele nao sabe de onde vem o fluxo: para a entrada
# padrao o chamador nao redireciona nada, e para arquivo local acima do teto o
# chamador redireciona a entrada do arquivo. Dois lacos — um para fluxo, outro
# para arquivo — seriam a nona ocorrencia da familia de gemeos, com a proxima
# correcao de deslocamento valendo para um lado so.
#
# O `argumento_de_commit` chega PRONTO do comando: e o mesmo objeto que a
# requisicao unica envia a `files/upload`. Monta-lo aqui criaria a segunda copia
# da regra de publicacao.
dbx_transfer_sessao() {
  local commit=${1-} estado

  [[ -n $commit ]] || {
    _dbx_transfer_falhar uso_invalido 'envio em partes sem objeto de publicacao'
    return $?
  }

  # RF-15, SEGUNDA LINHA DE DEFESA. O gate de simulacao vive no comando, ANTES
  # da bifurcacao entre requisicao unica e sessao, e portanto domina os dois
  # ramos. Esta guarda existe para o chamador FUTURO que esquecer: falha
  # fechada, e nao emissao silenciosa. Nao e duplicacao da regra — e recusa de
  # executar sem ela.
  [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]] || {
    _dbx_transfer_falhar uso_invalido \
      'sessao em partes alcancada em modo de simulacao: nenhuma escrita e emitida'
    return $?
  }

  # shellcheck disable=SC2034
  # Justificativa: classe da taxonomia, lida por `commands/upload` para redigir
  # o diagnostico e escolher o codigo de saida.
  DBX_TRANSFER_CLASSE=''
  # shellcheck disable=SC2034
  # Justificativa: motivo ja redigido, lido por `commands/upload`.
  DBX_TRANSFER_MOTIVO=''
  DBX_TRANSFER_CONTENT_HASH=''
  # shellcheck disable=SC2034
  # Justificativa: total de bytes, publicado na saida do comando (RF-31).
  DBX_TRANSFER_BYTES=0
  # shellcheck disable=SC2034
  # Justificativa: veredito de integridade, publicado na saida do comando.
  DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'

  # `umask` SALVA E RESTAURADA, e nao apenas endurecida. A mascara e estado do
  # PROCESSO, nao da funcao: deixa-la em 077 na volta altera a permissao padrao
  # de tudo que o chamador criar depois — medido antes desta correcao, 0022 na
  # entrada e 0077 na saida.
  #
  # Nenhum consumidor de hoje observa a diferenca, e o valor deixado era o mais
  # restritivo. Ainda assim e a forma exata da familia de gemeos que este projeto
  # ja pagou oito vezes: `lib/config.sh` faz o par salvar/restaurar
  # (`mascara_anterior`) e o irmao NOVO nao fazia. A disciplina so vale se nao
  # tiver excecao negociada caso a caso.
  local mascara_anterior
  mascara_anterior=$(umask)
  umask 077
  DBX_TRANSFER_AREA_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/dbx-transfer.XXXXXXXX") || {
    umask "$mascara_anterior"
    _dbx_transfer_falhar configuracao 'area temporaria indisponivel para o envio em partes'
    return $?
  }
  # Area temporaria indisponivel e problema do HOST, e nao recurso remoto
  # ausente: classificar como `nao_encontrado` mandaria investigar a Dropbox por
  # falha de disco local.
  trap '_dbx_transfer_interrompida' INT TERM HUP
  trap '_dbx_transfer_remover_area' EXIT

  # Ponto UNICO de limpeza no caminho normal: o corpo da sessao pode sair por
  # muitas portas, e uma limpeza por porta seria a forma de esquecer uma.
  _dbx_transfer_conduzir "$commit"
  estado=$?
  _dbx_transfer_remover_area
  # Os tratadores valem SO enquanto a sessao existe. Deixa-los armados faria um
  # sinal recebido depois — durante a apresentacao do resultado, por exemplo —
  # encerrar com "operacao nao concluida" um envio que ja concluiu.
  #
  # LIMITE DECLARADO: isto REMOVE os tratadores, e nao restaura os que o
  # chamador porventura tivesse. Hoje ninguem no produto arma INT, TERM, HUP ou
  # EXIT antes daqui; quando alguem armar, esta linha precisa virar salvar e
  # restaurar, e nao ser apagada.
  trap - INT TERM HUP EXIT
  # Ao lado do `trap -`, e pelo mesmo motivo: os dois sao estado do processo
  # emprestado pela sessao, e a sessao os devolve.
  umask "$mascara_anterior"
  return $estado
}

_dbx_transfer_conduzir() {
  local commit=$1
  local bloco="$DBX_TRANSFER_AREA_TEMP/parte"
  local sessao deslocamento=0 tamanho=0 argumento remoto parte=1

  : >"$bloco" || {
    _dbx_transfer_falhar configuracao 'area temporaria nao gravavel'
    return $?
  }

  dbx_hash_acumular_iniciar || {
    _dbx_transfer_falhar configuracao 'utilitario de resumo SHA-256 indisponivel'
    return $?
  }

  # Inicio com corpo VAZIO. Em sessao sequencial e permitido mandar dado ja no
  # inicio, mas nao mandar mantem UMA forma de enviar parte — a do `append` — em
  # vez de duas, e a regra de deslocamento fica com um dono so.
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_INICIAR" '{"close":false}' "$bloco" nao || {
    _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "inicio de sessao recusado: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  _dbx_transfer_ler_campo session_id || {
    _dbx_transfer_falhar erro_remoto 'inicio de sessao sem identificador de sessao'
    return $?
  }
  dbx_json_escapar_cadeia "$DBX_TRANSFER_LIDO"
  sessao=$DBX_JSON_ESCAPADO
  # Canal publico ALHEIO, esvaziado por quem o encheu. O identificador de sessao
  # nao e credencial, mas a disciplina nao e "so limpe o que for segredo": e
  # "quem enche o canal de outro componente o esvazia", e ela so vale se nao
  # tiver excecoes negociadas caso a caso.
  # shellcheck disable=SC2034  # canal publico alheio, limpo por quem o encheu
  DBX_JSON_ESCAPADO=''

  while :; do
    # Sem cano: o status abaixo e o do proprio leitor. Falha de leitura aborta a
    # sessao ANTES de qualquer `finish`, e portanto nada e publicado.
    head -c "$DBX_TRANSFER_TAMANHO_PARTE" >"$bloco" || {
      _dbx_transfer_falhar nao_concluida \
        "falha ao ler a origem no deslocamento $deslocamento; nada foi publicado no destino"
      return $?
    }
    tamanho=$(wc -c <"$bloco") || {
      _dbx_transfer_falhar nao_concluida 'tamanho do bloco lido indeterminado'
      return $?
    }
    tamanho=${tamanho//[^0-9]/}
    [[ -n $tamanho ]] || {
      _dbx_transfer_falhar nao_concluida 'tamanho do bloco lido indeterminado'
      return $?
    }

    if [[ $tamanho -gt 0 ]]; then
      dbx_hash_acumular_bloco "$bloco" || {
        _dbx_transfer_falhar nao_concluida \
          "resumo do bloco no deslocamento $deslocamento nao pode ser calculado"
        return $?
      }
    fi

    # Leitura curta so ocorre no fim da entrada: este e o ultimo bloco e ele vai
    # no `finish`, mesmo quando tem zero bytes.
    [[ $tamanho -lt $DBX_TRANSFER_TAMANHO_PARTE ]] && break

    _dbx_transfer_anexar "$sessao" "$deslocamento" "$tamanho" "$bloco" || return $?
    deslocamento=$((deslocamento + tamanho))
    dbx_progress_transferencia 'upload' "$deslocamento" 0 "parte $parte enviada"
    parte=$((parte + 1))
  done

  dbx_progress_mensagem "[upload] concluindo sessao em partes ($((deslocamento + tamanho)) bytes)..."

  argumento="{\"cursor\":{\"session_id\":\"$sessao\",\"offset\":$deslocamento},\"commit\":$commit}"
  _dbx_transfer_emitir "$DBX_TRANSFER_URL_CONCLUIR" "$argumento" "$bloco" nao || {
    _dbx_transfer_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "conclusao da sessao recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  # shellcheck disable=SC2034
  # Justificativa: total de bytes lidos da origem, publicado pelo comando (RF-31).
  DBX_TRANSFER_BYTES=$((deslocamento + tamanho))

  # O bloco ja foi enviado: o arquivo vira area de trabalho da cadeia de
  # resumos. Reaproveitar em vez de criar um segundo arquivo e o que mantem o
  # teto de ocupacao.
  dbx_hash_acumular_encerrar "$bloco" || {
    _dbx_transfer_falhar integridade \
      'o resumo local do conteudo enviado nao pode ser calculado; a integridade nao foi conferida'
    return $?
  }
  DBX_TRANSFER_CONTENT_HASH=$DBX_HASH_RESULTADO

  if _dbx_transfer_ler_campo content_hash; then
    remoto=$DBX_TRANSFER_LIDO
    if dbx_hash_iguais "$DBX_TRANSFER_CONTENT_HASH" "$remoto"; then
      DBX_TRANSFER_INTEGRIDADE='conferida'
    else
      # O arquivo EXISTE no destino: o `finish` retornou. O que nao se pode
      # fazer e chamar isto de sucesso — quem consome a saida decidiria manter
      # um arquivo que nao confere.
      {
        _dbx_transfer_falhar integridade \
          'o resumo devolvido pelo servico nao confere com o resumo do conteudo enviado; nao considere o item integro'
        return $?
      }
    fi
  else
    # Sem resumo publicado pelo servico a verificacao NAO ocorreu. Afirmar
    # conferencia que nao houve e pior que nao conferir.
    # shellcheck disable=SC2034
    # Justificativa: veredito publicado pelo comando; sem leitor neste arquivo.
    DBX_TRANSFER_INTEGRIDADE='nao_aplicavel'
  fi

  return 0
}
