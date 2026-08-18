#!/usr/bin/env bash
# lib/path.sh — normalizacao de caminho e confinamento de raiz.
#
# Camada: dominio. Nao acessa rede, nao le configuracao e nao imprime
# diagnostico. Depende apenas de lib/errors.sh, tambem de dominio, para nao
# duplicar a tabela de codigos de saida (fonte unica exigida por RF-35).
#
# Requisitos atendidos:
#   RNF-10 — nomes com espacos, acentuacao, metacaracteres de shell e quebras
#            de linha atravessam a normalizacao sem corrupcao nem expansao.
#   RNF-20 — caminho fora da raiz permitida e recusado ANTES de qualquer chamada
#            de rede. Com acesso amplo a conta (PRJ-DEC-03), este componente e o
#            unico confinamento que resta; por isso ele falha fechado.
#
# Dois espacos de nomes distintos, com regras deliberadamente diferentes:
#
#   remoto — a Dropbox nao possui links simbolicos do lado do servidor, logo a
#            resolucao de `..` e puramente LEXICAL. A comparacao de confinamento
#            ignora caixa, porque o servico resolve caminho sem diferenciar
#            maiusculas de minusculas: comparar de forma sensivel recusaria um
#            caminho que o servico considera dentro da raiz.
#
#   local  — o sistema de arquivos possui links simbolicos, logo a resolucao e
#            FISICA, componente a componente, seguindo os links antes de aplicar
#            `..`. A comparacao e sensivel a caixa, como o sistema de arquivos.
#
# Abordagens avaliadas para o confinamento:
#   (a) comparacao textual de prefixo (`[[ $p == $raiz* ]]`). Rejeitada: aceita
#       `/backups2` como se estivesse dentro de `/backups`. Ha teste dedicado.
#   (b) delegar a `realpath --relative-to` ou a `readlink -f`. Rejeitada para o
#       espaco remoto (nao ha sistema de arquivos) e evitada no local por
#       depender de extensoes GNU (RSK-09) e por nao tratar destino inexistente.
#   (c) ESCOLHIDA — resolucao propria com pilha de componentes e comparacao com
#       FRONTEIRA (`igual a raiz` ou `raiz seguida de barra`), com resolucao
#       fisica de links no espaco local e resolucao lexical no remoto.

[[ -n ${DBX_PATH_CARREGADO:-} ]] && return 0
DBX_PATH_CARREGADO=1

_dbx_path_diretorio=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_path_diretorio/errors.sh"
unset _dbx_path_diretorio

# Os status devolvidos sao os proprios codigos de saida da taxonomia, para que a
# recusa chegue ao orquestrador com o valor documentado em RF-29.
DBX_PATH_USO_INVALIDO=$(dbx_errors_codigo_saida uso_invalido)
DBX_PATH_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
DBX_PATH_RECUSADO=$(dbx_errors_codigo_saida caminho_recusado)
readonly DBX_PATH_USO_INVALIDO DBX_PATH_CONFIGURACAO DBX_PATH_RECUSADO

# Teto de indirecao de links simbolicos, para encerrar ciclos.
readonly DBX_PATH_MAX_LINKS=40

# Canal de resultado byte a byte.
#
# A substituicao de comando do shell remove TODAS as quebras de linha finais.
# Como quebra de linha e um byte valido em nome de arquivo e em caminho da
# Dropbox (RNF-10), qualquer funcao que devolva caminho por `$( )` corrompe
# silenciosamente o nome de `arquivo\n` para `arquivo`, que e outro arquivo.
# O risco nao e cosmetico: em recebimento, sobrescreve alvo diferente do pedido.
#
# Por isso as funcoes publicas deste componente:
#   1. gravam o resultado exato em DBX_PATH_RESULTADO;
#   2. tambem imprimem o valor, por conveniencia de uso interativo.
#
# Quem precisa do valor exato le a variavel; quem usa `$( )` aceita a perda de
# quebras finais. As funcoes internas nunca usam `$( )` entre si.
DBX_PATH_RESULTADO=''

# ---------------------------------------------------------------------------
# Normalizacao lexical (espaco remoto)
# ---------------------------------------------------------------------------

# _dbx_path_normalizar_lexical <caminho_absoluto>
# Percorre os componentes com expansao de parametro, sem `read -a`, `sed` ou
# substituicao de comando, para nao esbarrar em nomes com quebra de linha.
# Grava o resultado em DBX_PATH_RESULTADO em vez de imprimir, para que o
# chamador nao precise capturar com `$( )` e perder quebras finais.
# Status: 0 sucesso; DBX_PATH_RECUSADO se `..` tentar subir acima da raiz.
_dbx_path_normalizar_lexical() {
  local resto=${1#/} componente
  local acumulado=''
  DBX_PATH_RESULTADO=''
  while [[ -n $resto ]]; do
    if [[ $resto == */* ]]; then
      componente=${resto%%/*}
      resto=${resto#*/}
    else
      componente=$resto
      resto=''
    fi
    case $componente in
      '' | '.')
        continue
        ;;
      '..')
        # Subir acima da raiz e sempre tentativa de evasao, nunca caminho valido.
        [[ -n $acumulado ]] || return "$DBX_PATH_RECUSADO"
        acumulado=${acumulado%/*}
        ;;
      *)
        acumulado+="/$componente"
        ;;
    esac
  done
  DBX_PATH_RESULTADO=${acumulado:-/}
}

# dbx_path_remoto_normalizar <caminho> — caminho remoto absoluto normalizado.
# Resultado exato em DBX_PATH_RESULTADO; a impressao e conveniencia.
dbx_path_remoto_normalizar() {
  local caminho=${1-} status
  DBX_PATH_RESULTADO=''
  [[ $# -ge 1 && -n $caminho ]] || return "$DBX_PATH_USO_INVALIDO"
  [[ $caminho == /* ]] || return "$DBX_PATH_USO_INVALIDO"
  _dbx_path_normalizar_lexical "$caminho"
  status=$?
  if [[ $status -ne 0 ]]; then
    DBX_PATH_RESULTADO=''
    return "$status"
  fi
  printf '%s\n' "$DBX_PATH_RESULTADO"
}

# dbx_path_remoto_para_api <caminho> — a Dropbox representa a raiz da conta como
# cadeia vazia, e nao como "/".
dbx_path_remoto_para_api() {
  local status
  dbx_path_remoto_normalizar "${1-}" >/dev/null
  status=$?
  [[ $status -eq 0 ]] || return "$status"
  [[ $DBX_PATH_RESULTADO == '/' ]] && DBX_PATH_RESULTADO=''
  printf '%s\n' "$DBX_PATH_RESULTADO"
}

# _dbx_path_dentro_de <caminho> <raiz> [sensivel_a_caixa]
# Comparacao com fronteira de componente: `/backups2` nao esta em `/backups`.
_dbx_path_dentro_de() {
  local alvo=$1 raiz=$2 sensivel=${3:-sim}
  if [[ $sensivel == 'nao' ]]; then
    alvo=${alvo,,}
    raiz=${raiz,,}
  fi
  # Raiz "/" contem todo caminho absoluto pela propria regra de fronteira; nao
  # ha curto-circuito. Quem decide se essa raiz e admissivel sao as funcoes
  # publicas, que exigem opcao explicita para ela.
  [[ $alvo == "$raiz" ]] && return 0
  [[ $raiz == '/' && $alvo == /* ]] && return 0
  [[ $alvo == "$raiz"/* ]] && return 0
  return 1
}

# _dbx_path_raiz_total_autorizada <raiz_normalizada> <opcao>
# Status 0 quando a raiz e admissivel; DBX_PATH_CONFIGURACAO quando a raiz "/"
# foi pedida sem autorizacao explicita; DBX_PATH_USO_INVALIDO se a opcao tiver
# valor invalido.
#
# Operar sobre a conta inteira e uma decisao consciente, nao um padrao
# silencioso: com acesso amplo concedido ao aplicativo (PRJ-DEC-03), a raiz "/"
# desliga a unica protecao que resta em RNF-20, e nada no uso revelaria isso.
_dbx_path_raiz_total_autorizada() {
  local raiz=$1 opcao=${2:-nao}
  case $opcao in
    sim | nao) ;;
    *) return "$DBX_PATH_USO_INVALIDO" ;;
  esac
  [[ $raiz == '/' && $opcao != 'sim' ]] && return "$DBX_PATH_CONFIGURACAO"
  return 0
}

# dbx_path_remoto_confinar <raiz_permitida> <caminho> [raiz_total]
#
# Caminho relativo e ancorado na raiz. Raiz ausente ou malformada NUNCA e lida
# como "sem restricao": a falha e fechada, porque o modo de falha aberto e o
# pior resultado possivel para RNF-20.
#
# `raiz_total` vale `sim` ou `nao` (padrao `nao`) e autoriza exclusivamente a
# raiz "/", isto e, operar sobre a conta inteira sem confinamento. A opcao nao
# afrouxa nada quando a raiz e restrita, e nao desliga a normalizacao: `..`
# acima da raiz continua recusado mesmo com ela ligada.
dbx_path_remoto_confinar() {
  local raiz=${1-} caminho=${2-} raiz_total=${3:-nao} raiz_norm alvo alvo_norm status

  DBX_PATH_RESULTADO=''
  [[ -n $raiz && $raiz == /* ]] || return "$DBX_PATH_CONFIGURACAO"
  _dbx_path_normalizar_lexical "$raiz" || return "$DBX_PATH_CONFIGURACAO"
  raiz_norm=$DBX_PATH_RESULTADO
  DBX_PATH_RESULTADO=''
  # O status precisa ser capturado ANTES de qualquer negacao: depois de `if !`,
  # `$?` e o status do proprio `!`, e nao o do comando testado.
  _dbx_path_raiz_total_autorizada "$raiz_norm" "$raiz_total"
  status=$?
  if [[ $status -ne 0 ]]; then
    DBX_PATH_RESULTADO=''
    return "$status"
  fi

  DBX_PATH_RESULTADO=''
  [[ $# -ge 2 && -n $caminho ]] || return "$DBX_PATH_USO_INVALIDO"

  if [[ $caminho == /* ]]; then
    alvo=$caminho
  else
    alvo="$raiz_norm/$caminho"
  fi

  _dbx_path_normalizar_lexical "$alvo"
  status=$?
  alvo_norm=$DBX_PATH_RESULTADO
  if [[ $status -ne 0 ]]; then
    DBX_PATH_RESULTADO=''
    return "$DBX_PATH_RECUSADO"
  fi

  if ! _dbx_path_dentro_de "$alvo_norm" "$raiz_norm" nao; then
    DBX_PATH_RESULTADO=''
    return "$DBX_PATH_RECUSADO"
  fi
  DBX_PATH_RESULTADO=$alvo_norm
  printf '%s\n' "$alvo_norm"
}

# ---------------------------------------------------------------------------
# Resolucao fisica (espaco local)
# ---------------------------------------------------------------------------

# _dbx_path_resolver_fisico <caminho_absoluto>
# Resolve componente a componente, seguindo links simbolicos ANTES de aplicar
# `..`. Componentes ainda inexistentes sao aceitos e tratados lexicalmente, o
# que e o caso do destino de um recebimento de arquivo.
_dbx_path_resolver_fisico() {
  local resto=${1#/} componente candidato alvo
  local acumulado='' saltos=0
  DBX_PATH_RESULTADO=''
  while [[ -n $resto ]]; do
    if [[ $resto == */* ]]; then
      componente=${resto%%/*}
      resto=${resto#*/}
    else
      componente=$resto
      resto=''
    fi
    case $componente in
      '' | '.')
        continue
        ;;
      '..')
        [[ -n $acumulado ]] || return "$DBX_PATH_RECUSADO"
        acumulado=${acumulado%/*}
        continue
        ;;
    esac

    candidato="$acumulado/$componente"
    if [[ -L $candidato ]]; then
      saltos=$((saltos + 1))
      [[ $saltos -le $DBX_PATH_MAX_LINKS ]] || return "$DBX_PATH_RECUSADO"
      # `$( )` remove quebras finais tambem aqui: um alvo de link terminado em
      # quebra de linha seria resolvido para outro caminho. Le-se o valor exato
      # com `read -r -d ''`, que so para no byte nulo.
      IFS= read -r -d '' alvo < <(readlink -- "$candidato" && printf '\0') ||
        return "$DBX_PATH_RECUSADO"
      alvo=${alvo%$'\n'} # readlink acrescenta exatamente uma quebra de linha
      if [[ $alvo == /* ]]; then
        acumulado=''
        resto="${alvo#/}${resto:+/$resto}"
      else
        resto="${alvo}${resto:+/$resto}"
      fi
      continue
    fi
    acumulado=$candidato
  done
  DBX_PATH_RESULTADO=${acumulado:-/}
}

# dbx_path_local_confinar <raiz_local> <caminho> [raiz_total]
#
# `raiz_total` tem o mesmo significado do confinamento remoto: autoriza
# exclusivamente a raiz "/".
# Devolve o caminho fisico ja resolvido, ou recusa. A raiz precisa existir: uma
# raiz inexistente e erro de configuracao, nao permissao implicita.
dbx_path_local_confinar() {
  local raiz=${1-} caminho=${2-} raiz_total=${3:-nao} raiz_fis alvo status

  DBX_PATH_RESULTADO=''
  [[ -n $raiz && $raiz == /* ]] || return "$DBX_PATH_CONFIGURACAO"
  [[ -d $raiz ]] || return "$DBX_PATH_CONFIGURACAO"

  # A raiz e resolvida pelo MESMO resolvedor fisico do alvo, sem substituicao de
  # comando. Usar `$(cd -P … && pwd -P)` aqui era uma evasao de confinamento: a
  # captura removia a quebra de linha final e a raiz `algo\n` passava a designar
  # o diretorio irmao `algo`. A falha era aberta nas duas direcoes — alcancava
  # arquivo fora da raiz configurada e desviava gravacao para dentro da vizinha.
  # O comentario anterior alegava que tal raiz seria "configuracao invalida",
  # mas nada no codigo verificava isso.
  _dbx_path_resolver_fisico "$raiz" || return "$DBX_PATH_CONFIGURACAO"
  raiz_fis=$DBX_PATH_RESULTADO
  DBX_PATH_RESULTADO=''
  [[ -n $raiz_fis && -d $raiz_fis ]] || return "$DBX_PATH_CONFIGURACAO"

  # O status precisa ser capturado ANTES de qualquer negacao: depois de `if !`,
  # `$?` e o status do proprio `!`, e nao o do comando testado.
  _dbx_path_raiz_total_autorizada "$raiz_fis" "$raiz_total"
  status=$?
  if [[ $status -ne 0 ]]; then
    DBX_PATH_RESULTADO=''
    return "$status"
  fi

  [[ $# -ge 2 && -n $caminho ]] || return "$DBX_PATH_USO_INVALIDO"
  [[ $caminho == /* ]] || caminho="$raiz_fis/$caminho"

  _dbx_path_resolver_fisico "$caminho"
  status=$?
  alvo=$DBX_PATH_RESULTADO
  if [[ $status -ne 0 ]]; then
    DBX_PATH_RESULTADO=''
    return "$DBX_PATH_RECUSADO"
  fi

  if ! _dbx_path_dentro_de "$alvo" "$raiz_fis" sim; then
    DBX_PATH_RESULTADO=''
    return "$DBX_PATH_RECUSADO"
  fi
  DBX_PATH_RESULTADO=$alvo
  printf '%s\n' "$alvo"
}

# ---------------------------------------------------------------------------
# Apoio ao contrato de saida
# ---------------------------------------------------------------------------

# dbx_path_seguro_para_linha <caminho>
# 0 quando o caminho pode ser emitido em uma saida orientada a linha sem
# escape. Quebra de linha, retorno de carro e tabulacao sao nomes validos no
# sistema de arquivos e na Dropbox, mas quebram um registro de uma linha so:
# quem emite (lib/output) precisa saber disso antes de imprimir (RF-28, RF-35).
dbx_path_seguro_para_linha() {
  local caminho=${1-}
  [[ $caminho == *$'\n'* ]] && return 1
  [[ $caminho == *$'\r'* ]] && return 1
  [[ $caminho == *$'\t'* ]] && return 1
  return 0
}
