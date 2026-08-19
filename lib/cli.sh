#!/usr/bin/env bash
# cli.sh — interpretacao de opcoes globais e despacho para os comandos.
#
# ONDE VIVE UM COMANDO — decisao de desenho, com custo
#
#   Adotado: ponto de entrada unico (`bin/dbx`) com despacho por subcomando, UM
#   ARQUIVO POR COMANDO em `commands/`, carregado sob demanda.
#
#   Alternativas comparadas, considerando que serao NOVE comandos e que o
#   `sync` e maior que os outros oito somados:
#
#   (a) Um executavel por comando (`dbx-upload`, `dbx-list`, ...). Dispensa
#       despacho, mas espalha nove executaveis no caminho de busca, duplica a
#       interpretacao de opcoes globais em nove lugares — nove copias de uma
#       regra e nove lugares para ela divergir — e nao resolve o tamanho do
#       `sync`.
#
#   (b) Executavel unico com todos os comandos dentro. E exatamente o que o
#       modelo de referencia faz em 1834 linhas, e o que `RNF-16` e `DIV-06`
#       recusam: impede teste por unidade e concentra risco de regressao. Com o
#       `sync` dentro, um unico arquivo passaria de metade do projeto.
#
#   (c) ESCOLHIDO. Entrada fina, um arquivo por comando, carga sob demanda. O
#       custo do despacho e uma tabela; em troca, o custo de partida deixa de
#       crescer com a quantidade de comandos — so o comando pedido e lido, e o
#       `sync` nao e pago por quem roda `space`. Cada comando vira uma unidade
#       auditavel isolada, o que e a condicao para a guarda de remocao de casos
#       e para as auditorias por arquivo continuarem funcionando.
#
#   Sub-decisao que muda a seguranca, e nao so o estilo: o despacho NAO compoe o
#   caminho a partir do nome recebido. `commands/$1.sh` derivaria caminho de
#   arquivo — e portanto codigo executado — de origem externa. E a mesma classe
#   que `RNF-24` proibe no analisador, com consequencia pior: ali o pior caso e
#   colisao de contexto, aqui e execucao de codigo arbitrario. A tabela e de
#   nomes LITERAIS, e ha auditoria que reprova a composicao.
#
# QUANDO A VERIFICACAO PREVIA RODA
#
#   Nao em todo comando, e nao so nos que tocam rede: CADA COMANDO DECLARA o que
#   precisa, e a entrada roda exatamente as verificacoes declaradas.
#
#   O que decide e o custo do falso negativo. `RNF-04` manda a verificacao
#   RECUSAR a execucao quando a credencial nao esta em `0600` — recusa, nao
#   alerta. Se essa verificacao rodasse em todo comando, o assistente de
#   configuracao ficaria impossivel de usar exatamente quando e necessario: o
#   usuario nao poderia consertar a credencial com a ferramenta que se recusa a
#   rodar porque a credencial esta errada. Impasse fechado, criado por zelo.
#   Pelo mesmo motivo, pedir ajuda ou versao nao pode exigir cliente de rede
#   instalado.
#
#   Vocabulario fechado de tres niveis, verificado por auditoria que enumera os
#   arquivos de comando — a regra so vale se alguem percorre o conjunto onde ela
#   incide, e o conjunto vem dos arquivos, nao de lista mantida a mao:
#     nenhum      ajuda e versao: nao tocam ambiente nem credencial
#     ambiente    piso de shell e utilitarios obrigatorios
#     credencial  ambiente mais permissao do arquivo de credencial
#
#   O nivel `ambiente` ficou SEM NENHUMA OCORRENCIA enquanto os seis comandos do
#   bloco anterior declaravam todos `credencial`, e nesse periodo o impasse
#   descrito acima continuava existindo dentro de `lib/preflight`, que inspecionava
#   a credencial em qualquer nivel. `config` e `unlink` sao as duas primeiras
#   ocorrencias, e sao exatamente as que precisam rodar com a credencial quebrada:
#   uma para regravar, outra para remover. Vocabulario declarado nao vale nada
#   enquanto ninguem o exerce.

# shellcheck disable=SC2034
# Justificativa: as variaveis abaixo sao os canais publicos consumidos por
# `bin/dbx` e pelos comandos. A analise estatica nao cruza arquivos e as ve como
# escrita sem leitura; a leitura esta na entrada e em `commands/`.

[[ -n ${DBX_CLI_CARREGADO:-} ]] && return 0
DBX_CLI_CARREGADO=1

DBX_CLI_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)

readonly DBX_CLI_VERSAO='0.1.0'

DBX_CLI_COMANDO=''
DBX_CLI_ARGS=()
DBX_CLI_ESTRUTURADA='nao'
DBX_CLI_NULO='nao'
DBX_CLI_SIMULACAO='nao'
DBX_CLI_MOTIVO=''

# dbx_cli_comando_valido <nome> — tabela FECHADA de nomes literais.
#
# Bloco corrente: oito comandos. `sync` fica de fora deliberadamente e e recusado
# como qualquer outro nome desconhecido, em vez de aceito e falhando adiante.
dbx_cli_comando_valido() {
  case ${1-} in
    upload | download | list | delete | info | space) return 0 ;;
    config | unlink) return 0 ;;
    help | version) return 0 ;;
  esac
  return 1
}

# _dbx_cli_arquivo_do_comando <nome> — caminho LITERAL, nunca composto.
#
# Cada ramo escreve o caminho por extenso. Repeticao aqui e o preco de nao
# derivar caminho de execucao do que veio de fora; a auditoria estatica reprova
# qualquer tentativa de encurtar isto por interpolacao.
_dbx_cli_arquivo_do_comando() {
  local raiz=$DBX_CLI_RAIZ
  case ${1-} in
    upload) printf '%s' "$raiz/commands/upload.sh" ;;
    download) printf '%s' "$raiz/commands/download.sh" ;;
    list) printf '%s' "$raiz/commands/list.sh" ;;
    delete) printf '%s' "$raiz/commands/delete.sh" ;;
    info) printf '%s' "$raiz/commands/info.sh" ;;
    space) printf '%s' "$raiz/commands/space.sh" ;;
    config) printf '%s' "$raiz/commands/config.sh" ;;
    unlink) printf '%s' "$raiz/commands/unlink.sh" ;;
    *) return 1 ;;
  esac
}

# dbx_cli_requisito_interno <nome> — requisito dos comandos que nao tem arquivo.
dbx_cli_requisito_interno() {
  case ${1-} in
    help | version) printf 'nenhum' ;;
    *) return 1 ;;
  esac
}

_dbx_cli_recusar() {
  DBX_CLI_MOTIVO=$1
  return "$DBX_CLI_ERRO_USO"
}

# dbx_cli_analisar <argumentos...>
#
# Opcao global so e reconhecida ANTES do subcomando. Depois dele, todo argumento
# pertence ao comando — um comando pode ter opcao de mesmo nome, e consumi-la
# aqui entregaria lista incompleta a quem sabe interpreta-la.
dbx_cli_analisar() {
  DBX_CLI_COMANDO=''
  DBX_CLI_ARGS=()
  DBX_CLI_ESTRUTURADA='nao'
  DBX_CLI_NULO='nao'
  DBX_CLI_SIMULACAO='nao'
  DBX_CLI_MOTIVO=''

  while [[ $# -gt 0 ]]; do
    case $1 in
      --json) DBX_CLI_ESTRUTURADA='sim' ;;
      --null) DBX_CLI_NULO='sim' ;;
      --dry-run) DBX_CLI_SIMULACAO='sim' ;;
      --help | -h)
        DBX_CLI_COMANDO='help'
        return 0
        ;;
      --version | -V)
        DBX_CLI_COMANDO='version'
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        # `&&` aqui seria defeito: a funcao devolve status NAO ZERO, entao o
        # curto-circuito pularia o proprio `return` e a analise seguiria.
        _dbx_cli_recusar "opcao global desconhecida: $1"
        return $?
        ;;
      *)
        dbx_cli_comando_valido "$1" || {
          _dbx_cli_recusar "comando desconhecido: $1"
          return $?
        }
        DBX_CLI_COMANDO=$1
        shift
        DBX_CLI_ARGS=("$@")
        return 0
        ;;
    esac
    shift
  done

  _dbx_cli_recusar 'nenhum comando informado'
  return $?
}
