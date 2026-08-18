#!/usr/bin/env bash
# lib/hash.sh — calculo do `content_hash` da Dropbox.
#
# Camada: dominio. Sem rede, sem configuracao, sem estado persistente.
# Requisitos atendidos: RF-33, RF-34; sustenta RF-07, RF-11, RF-31 e RF-32.
# Depende apenas de lib/errors.sh, tambem de dominio, para nao manter uma
# segunda tabela de codigos de saida.
#
# Algoritmo (PRJ-DEC-08, conforme a especificacao publicada):
#   1. dividir o conteudo em blocos de 4 MiB (4.194.304 bytes);
#   2. aplicar SHA-256 a cada bloco;
#   3. concatenar os resumos em BYTES BRUTOS, nunca em hexadecimal;
#   4. aplicar SHA-256 a concatenacao;
#   5. emitir o resultado em hexadecimal minusculo, 64 caracteres.
#
# Arquivo vazio: a especificacao trata o caso de forma explicita — nao ha bloco
# para um arquivo de tamanho zero, e o passo 3 forma uma cadeia vazia. Logo o
# resultado e o SHA-256 da entrada vazia. Nao e inferencia nossa.
#
# Armadilha: concatenar as representacoes hexadecimais gera um valor bem
# formado e errado, que so apareceria na comparacao com a API. Os testes
# `nao_concatena_resumos_em_hexadecimal_*` existem para pegar exatamente isso.
#
# Desenho da leitura, revisado apos a validacao do QA
# ---------------------------------------------------
# Cada bloco e lido para UM arquivo de buffer reaproveitado, e nao por um cano.
# A escolha nao e estetica:
#
#   a) `head -c N > buffer` expoe o status do leitor diretamente em `$?`. Na
#      versao anterior a leitura passava por um cano e apenas o status do
#      ultimo comando era observado, de modo que EIO, truncamento sob leitura
#      ou produtor morto no meio produziam um `content_hash` bem formado de
#      conteudo incompleto, com status 0. Declarar integridade sobre dado
#      truncado e o pior resultado possivel deste componente.
#   b) o tamanho de cada bloco fica disponivel, o que permite expor o total de
#      bytes lidos, exigido por RF-31, e distinguir fim de fluxo de truncamento.
#   c) o fim da entrada passa a ser detectado por tamanho zero, em vez de por
#      comparacao do resumo do bloco com o resumo da cadeia vazia.
#
# Nao ha nenhum cano em todo o caminho de calculo, portanto nao existe status de
# pipeline a mascarar erro. Custo: uma escrita e uma leitura adicionais por
# bloco, absorvidas pelo cache de paginas e despreziveis diante da transferencia
# de rede que este resumo acompanha. O buffer fica em area criada por `mktemp`,
# com permissao restrita e removida por `trap`, inclusive em interrupcao
# (RNF-05). Quando lib/tmp existir, esta area deve migrar para la.
#
# Contrato de status de saida — alinhado a taxonomia de RF-29, para que um
# status propagado ao orquestrador nunca signifique duas coisas diferentes:
#   0  sucesso
#   1  falha no utilitario de resumo         (classe desconhecido)
#   2  uso invalido, argumento ausente       (classe uso_invalido)
#   3  utilitario SHA-256 ausente ou invalido (classe configuracao)
#   4  origem invalida ou ilegivel           (classe nao_encontrado)

[[ -n ${DBX_HASH_CARREGADO:-} ]] && return 0
DBX_HASH_CARREGADO=1

_dbx_hash_diretorio=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_hash_diretorio/errors.sh"
unset _dbx_hash_diretorio

readonly DBX_HASH_TAMANHO_BLOCO=4194304

DBX_HASH_OK=0
DBX_HASH_ERRO_RESUMO=$(dbx_errors_codigo_saida desconhecido)
DBX_HASH_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_HASH_ERRO_DEPENDENCIA=$(dbx_errors_codigo_saida configuracao)
DBX_HASH_ERRO_ORIGEM=$(dbx_errors_codigo_saida nao_encontrado)
readonly DBX_HASH_OK DBX_HASH_ERRO_RESUMO DBX_HASH_ERRO_USO
readonly DBX_HASH_ERRO_DEPENDENCIA DBX_HASH_ERRO_ORIGEM

# Utilitarios de resumo aceitos. A lista e fechada de proposito: DBX_HASH_BACKEND
# vem do ambiente, e aceitar um valor arbitrario transformaria uma variavel de
# ambiente em escolha de programa a executar.
readonly DBX_HASH_BACKENDS_ACEITOS='sha256sum shasum openssl'

DBX_HASH_BACKEND=${DBX_HASH_BACKEND:-}
DBX_HASH_FORMATO=''

# ---------------------------------------------------------------------------
# Utilitario de resumo
# ---------------------------------------------------------------------------

# dbx_hash_verificar_dependencias — resolve e memoriza o utilitario SHA-256.
# Consumido tambem por lib/preflight quando DP-07 for fechada.
dbx_hash_verificar_dependencias() {
  local candidato
  if [[ -n $DBX_HASH_BACKEND ]]; then
    # Valor vindo do ambiente: precisa estar na lista fechada E existir.
    case " $DBX_HASH_BACKENDS_ACEITOS " in
      *" $DBX_HASH_BACKEND "*)
        command -v "$DBX_HASH_BACKEND" >/dev/null 2>&1 && return "$DBX_HASH_OK"
        ;;
    esac
    return "$DBX_HASH_ERRO_DEPENDENCIA"
  fi
  for candidato in $DBX_HASH_BACKENDS_ACEITOS; do
    if command -v "$candidato" >/dev/null 2>&1; then
      DBX_HASH_BACKEND=$candidato
      return "$DBX_HASH_OK"
    fi
  done
  return "$DBX_HASH_ERRO_DEPENDENCIA"
}

# _dbx_hash_sha256_hex — le a entrada padrao e imprime o SHA-256 em hexadecimal.
_dbx_hash_sha256_hex() {
  local saida
  case $DBX_HASH_BACKEND in
    sha256sum)
      saida=$(sha256sum) || return "$DBX_HASH_ERRO_RESUMO"
      saida=${saida%% *}
      ;;
    shasum)
      saida=$(shasum -a 256) || return "$DBX_HASH_ERRO_RESUMO"
      saida=${saida%% *}
      ;;
    openssl)
      # openssl 1.x imprime "(stdin)= <hex>"; openssl 3.x, "SHA2-256(stdin)= <hex>".
      saida=$(openssl dgst -sha256) || return "$DBX_HASH_ERRO_RESUMO"
      saida=${saida##* }
      ;;
    *)
      return "$DBX_HASH_ERRO_DEPENDENCIA"
      ;;
  esac
  [[ ${#saida} -eq 64 ]] || return "$DBX_HASH_ERRO_RESUMO"
  printf '%s' "$saida"
}

# _dbx_hash_anexar_escapes <resumo_hex_de_64> — acrescenta a DBX_HASH_FORMATO os
# 32 escapes correspondentes ao resumo de UM bloco.
#
# O fatiamento ocorre sempre sobre uma cadeia de 64 caracteres, de tamanho fixo.
# A versao anterior acumulava todos os resumos em uma unica cadeia e so entao
# fatiava, e fatiar em posicao avancada de uma cadeia longa custa proporcional a
# posicao: a conversao era quadratica na quantidade de blocos (medido pelo QA:
# 256 blocos 727 ms, 512 blocos 2.648 ms, 1.024 blocos 10.879 ms). Convertendo
# um bloco por vez, o custo por bloco e constante e o total, linear.
_dbx_hash_anexar_escapes() {
  local hex=$1 indice
  for ((indice = 0; indice < 64; indice += 2)); do
    DBX_HASH_FORMATO+="\\x${hex:indice:2}"
  done
}

# ---------------------------------------------------------------------------
# Nucleo do calculo
# ---------------------------------------------------------------------------

# _dbx_hash_calcular — le a entrada padrao e imprime "<content_hash> <bytes>".
# Deve ser invocada em subshell (o que a substituicao de comando ja garante),
# para que o `trap` de limpeza tenha escopo proprio e nao substitua o do chamador.
_dbx_hash_calcular() {
  local buffer bloco_hex tamanho total=0 final

  dbx_hash_verificar_dependencias || return "$DBX_HASH_ERRO_DEPENDENCIA"

  umask 077
  # DELIBERADAMENTE global, e nao `local`: a acao do `trap` e avaliada quando o
  # subshell encerra, momento em que o escopo da funcao ja nao existe. Com uma
  # variavel local, `$area` expandiria para vazio e a limpeza nao removeria
  # nada, deixando residuo a cada calculo — defeito que o caso
  # `nao_deixa_residuo_temporario` capturou.
  # Area temporaria indisponivel e problema do HOST, nao recurso remoto ausente.
  # Classificar como `nao_encontrado` mandava investigar a Dropbox por falha de
  # disco local.
  DBX_HASH_AREA_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/dbx-hash.XXXXXXXX") ||
    return "$DBX_HASH_ERRO_DEPENDENCIA"
  trap 'rm -rf "$DBX_HASH_AREA_TEMP"' EXIT INT TERM HUP
  buffer="$DBX_HASH_AREA_TEMP/bloco"

  DBX_HASH_FORMATO=''
  while :; do
    # Sem cano: o status abaixo e o do proprio leitor.
    head -c "$DBX_HASH_TAMANHO_BLOCO" >"$buffer" || return "$DBX_HASH_ERRO_RESUMO"
    tamanho=$(wc -c <"$buffer") || return "$DBX_HASH_ERRO_RESUMO"
    tamanho=${tamanho//[^0-9]/}
    [[ -n $tamanho ]] || return "$DBX_HASH_ERRO_RESUMO"
    [[ $tamanho -eq 0 ]] && break

    bloco_hex=$(_dbx_hash_sha256_hex <"$buffer") || return "$DBX_HASH_ERRO_RESUMO"
    _dbx_hash_anexar_escapes "$bloco_hex"
    total=$((total + tamanho))

    # Leitura curta so ocorre no fim da entrada.
    [[ $tamanho -lt $DBX_HASH_TAMANHO_BLOCO ]] && break
  done

  printf '%b' "$DBX_HASH_FORMATO" >"$buffer" || return "$DBX_HASH_ERRO_RESUMO"
  final=$(_dbx_hash_sha256_hex <"$buffer") || return "$DBX_HASH_ERRO_RESUMO"
  [[ ${#final} -eq 64 ]] || return "$DBX_HASH_ERRO_RESUMO"

  printf '%s %s\n' "$final" "$total"
}

# ---------------------------------------------------------------------------
# API publica
# ---------------------------------------------------------------------------

# dbx_hash_conteudo_fluxo_com_tamanho — imprime "<content_hash> <bytes_lidos>".
# A contagem e o que permite ao chamador cumprir o criterio de RF-31 e separar
# fim de fluxo legitimo de truncamento.
dbx_hash_conteudo_fluxo_com_tamanho() {
  local saida status
  saida=$(_dbx_hash_calcular)
  status=$?
  [[ $status -eq 0 ]] || return "$status"
  printf '%s\n' "$saida"
}

# dbx_hash_conteudo_fluxo — imprime apenas o content_hash.
dbx_hash_conteudo_fluxo() {
  local saida status
  saida=$(_dbx_hash_calcular)
  status=$?
  [[ $status -eq 0 ]] || return "$status"
  printf '%s\n' "${saida%% *}"
}

# _dbx_hash_validar_origem <caminho>
_dbx_hash_validar_origem() {
  [[ $# -ge 1 && -n ${1:-} ]] || return "$DBX_HASH_ERRO_USO"
  local caminho=$1
  [[ -e $caminho ]] || return "$DBX_HASH_ERRO_ORIGEM"
  # Diretorio nao e origem valida. Cano, `/dev/stdin` e substituicao de processo
  # sao: exigir arquivo comum aqui inviabilizaria o uso previsto em RF-31.
  [[ ! -d $caminho ]] || return "$DBX_HASH_ERRO_ORIGEM"
  [[ -r $caminho ]] || return "$DBX_HASH_ERRO_ORIGEM"
}

# dbx_hash_conteudo_arquivo <caminho> — content_hash de um arquivo local.
dbx_hash_conteudo_arquivo() {
  _dbx_hash_validar_origem "$@" || return $?
  dbx_hash_conteudo_fluxo <"$1"
}

# dbx_hash_conteudo_arquivo_com_tamanho <caminho>
dbx_hash_conteudo_arquivo_com_tamanho() {
  _dbx_hash_validar_origem "$@" || return $?
  dbx_hash_conteudo_fluxo_com_tamanho <"$1"
}

# dbx_hash_formato_valido <valor> — 0 se for um content_hash bem formado.
dbx_hash_formato_valido() {
  local valor=${1:-}
  [[ $valor =~ ^[0-9a-fA-F]{64}$ ]]
}

# dbx_hash_iguais <a> <b> — 0 iguais, 1 diferentes, 2 entrada malformada.
# A distincao importa em RF-33: um valor malformado nunca pode ser lido como
# "conteudo identico", sob pena de omitir uma transferencia necessaria.
dbx_hash_iguais() {
  local a=${1:-} b=${2:-}
  dbx_hash_formato_valido "$a" || return "$DBX_HASH_ERRO_USO"
  dbx_hash_formato_valido "$b" || return "$DBX_HASH_ERRO_USO"
  [[ ${a,,} == "${b,,}" ]]
}
