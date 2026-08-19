#!/usr/bin/env bash
# lib/walk.sh — travessia local por descida (RNF-28, RF-41a, RF-50).
#
# Camada: adaptadores. Depende de lib/errors.sh, de dominio.
#
# POR QUE DESCIDA COM NOME RELATIVO, E NAO CAMINHO MONTADO EM TEXTO
#
#   `cd -- "$nome"` referencia o INODE do diretorio; reabrir por caminho
#   absoluto reconstruido referencia o TEXTO, e entre uma leitura e a seguinte o
#   texto pode passar a designar outra coisa. E o equivalente em shell de
#   `openat` com `O_NOFOLLOW` por componente, e foi adotado em `DP-26` depois de
#   o escape ter sido reproduzido contra o codigo real.
#
#   LIMITE DECLARADO, e ele nao esta escondido: protege os componentes JA
#   percorridos, e nao a troca ocorrida imediatamente antes de descer. E reducao
#   de superficie, nao eliminacao — `RSK-24` continua no registro com
#   probabilidade reduzida.
#
# TRAVESSIA PARCIAL E FATAL PARA EXCLUSAO (RF-41a)
#
#   Qualquer coisa que impeca de enxergar um ramo inteiro — diretorio ilegivel,
#   `stat` que falha, profundidade excedida, ligacao simbolica que nao se segue —
#   marca a travessia como PARCIAL. Quem consome decide o que fazer, e `lib/sync`
#   desabilita exclusao na execucao inteira, e nao apenas naquele ramo.
#
#   A razao de a marca ser da TRAVESSIA e nao do ramo: um ramo invisivel produz
#   exatamente a mesma observacao que um ramo apagado — "nao esta na origem" —, e
#   com espelhamento ligado a segunda leitura apaga o destino. Nao ha como
#   distinguir as duas depois; so da para nao decidir.
#
# LIGACAO SIMBOLICA NAO E SEGUIDA, e isso conta como parcial.
#
#   Segui-la sairia da raiz por construcao, que e o que `RNF-20` proibe. Pula-la
#   em silencio seria pior que recusar: o conteudo do outro lado do vinculo
#   sumiria da origem sem sumir do destino, e com espelhamento isso vira
#   exclusao. Entao ela e pulada E marcada, e o operador ve por que a exclusao
#   foi desabilitada. Custo aceito: arvore com vinculos nunca espelha exclusao.

[[ -n ${DBX_WALK_CARREGADO:-} ]] && return 0
DBX_WALK_CARREGADO=1

_dbx_walk_diretorio=${BASH_SOURCE[0]%/*}
[[ $_dbx_walk_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_walk_diretorio=.
_dbx_walk_diretorio=$(cd -P -- "$_dbx_walk_diretorio" && pwd -P)
# shellcheck source=lib/errors.sh
. "$_dbx_walk_diretorio/errors.sh"
unset _dbx_walk_diretorio

DBX_WALK_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
DBX_WALK_ERRO_NAO_ENCONTRADO=$(dbx_errors_codigo_saida nao_encontrado)
readonly DBX_WALK_ERRO_USO DBX_WALK_ERRO_NAO_ENCONTRADO

# Teto de profundidade. Existe porque montagem circular e vinculo rigido de
# diretorio — raro, mas possivel em sistemas de arquivos que o permitam —
# produziriam recursao sem fim, e uma travessia que nao termina e pior que uma
# que recusa: consome descritores ate derrubar o processo, sem diagnostico.
readonly DBX_WALK_PROFUNDIDADE_MAXIMA=64

# shellcheck disable=SC2034  # canais publicos, consumidos por lib/sync e pela suite
DBX_WALK_PARCIAL='nao'
DBX_WALK_MOTIVO=''
DBX_WALK_TOTAL=0

# _dbx_walk_descer <profundidade> <prefixo>
#
# Emite um registro por entrada na saida padrao e um motivo por linha no
# descritor 3. Roda SEMPRE dentro do subshell montado por `dbx_walk_local`, para
# que a mudanca de diretorio nao escape para o processo do chamador.
#
# Formato do registro: `tamanho<TAB>mtime<TAB>caminho\0`.
# O caminho vai POR ULTIMO e o registro termina em byte nulo, porque nome de
# arquivo aceita tabulacao e quebra de linha — e nao aceita nulo. Qualquer outra
# ordem perderia nomes legitimos, que e a classe de defeito ja vista tres vezes
# neste projeto.
_dbx_walk_descer() {
  local profundidade=$1 prefixo=$2
  local nome relativo tamanho mtime

  if [[ $profundidade -gt $DBX_WALK_PROFUNDIDADE_MAXIMA ]]; then
    printf 'profundidade maxima excedida em: %s\n' "${prefixo:-.}" >&3
    return 0
  fi

  for nome in *; do
    relativo="${prefixo}${nome}"

    # A ordem importa: `-L` antes de `-d`, porque uma ligacao PARA diretorio
    # satisfaz `-d` e seria percorrida.
    if [[ -L $nome ]]; then
      printf 'ligacao simbolica nao percorrida: %s\n' "$relativo" >&3
      continue
    fi

    if [[ -d $nome ]]; then
      if [[ ! -r $nome || ! -x $nome ]]; then
        printf 'diretorio ilegivel: %s\n' "$relativo" >&3
        continue
      fi
      # A descida e a volta sao o par que sustenta a garantia. `cd ..` nao
      # reconstroi texto: sobe pelo vinculo do proprio diretorio aberto.
      if ! cd -- "$nome" 2>/dev/null; then
        printf 'nao foi possivel descer em: %s\n' "$relativo" >&3
        continue
      fi
      _dbx_walk_descer $((profundidade + 1)) "$relativo/"
      if ! cd .. 2>/dev/null; then
        # Perder o caminho de volta invalida TUDO o que viria depois, e nao so
        # este ramo: a travessia continuaria emitindo caminhos relativos a um
        # diretorio que nao e o que o prefixo diz. Abortar e a unica saida
        # honesta.
        printf 'nao foi possivel retornar de: %s\n' "$relativo" >&3
        return 1
      fi
      continue
    fi

    if [[ ! -f $nome ]]; then
      # Soquete, dispositivo, fila nomeada: nao ha o que transferir, e omitir em
      # silencio faria o destino perder o par sem que ninguem soubesse.
      printf 'entrada nao e arquivo comum: %s\n' "$relativo" >&3
      continue
    fi

    if ! tamanho=$(stat -c '%s' -- "$nome" 2>/dev/null) ||
      ! mtime=$(stat -c '%Y' -- "$nome" 2>/dev/null); then
      printf 'nao foi possivel inspecionar: %s\n' "$relativo" >&3
      continue
    fi

    printf '%s\t%s\t%s\0' "$tamanho" "$mtime" "$relativo"
  done
  return 0
}

# dbx_walk_local <raiz> <arquivo_de_registros>
#
# A travessia inteira roda em SUBSHELL. Sem isso, `cd` vazaria para o processo do
# chamador e todo caminho relativo posterior — inclusive os de outros comandos —
# passaria a significar outra coisa. O custo e ter de devolver os dados por
# arquivo, e nao por variavel, o que e barato perto de corromper o diretorio
# corrente de quem chamou.
dbx_walk_local() {
  [[ $# -eq 2 ]] || return "$DBX_WALK_ERRO_USO"
  local raiz=$1 destino=$2 motivos

  DBX_WALK_PARCIAL='nao'
  DBX_WALK_MOTIVO=''
  DBX_WALK_TOTAL=0

  [[ -d $raiz ]] || return "$DBX_WALK_ERRO_NAO_ENCONTRADO"
  [[ -r $raiz && -x $raiz ]] || return "$DBX_WALK_ERRO_NAO_ENCONTRADO"

  motivos=$(mktemp "${TMPDIR:-/tmp}/dbx-walk.XXXXXXXX") || return "$DBX_WALK_ERRO_USO"

  : >"$destino"
  (
    # `nullglob` para que diretorio vazio nao produza a cadeia literal `*` como
    # se fosse um arquivo chamado asterisco; `dotglob` para que arquivo oculto
    # seja transferido como qualquer outro — omiti-lo faria o destino divergir
    # em silencio. `.` e `..` nao entram por `dotglob`.
    shopt -s nullglob dotglob
    cd -P -- "$raiz" || exit 1
    _dbx_walk_descer 1 ''
  ) >"$destino" 3>"$motivos"

  if [[ -s $motivos ]]; then
    # shellcheck disable=SC2034  # canais publicos, ver nota no topo
    DBX_WALK_PARCIAL='sim'
    # O MOTIVO SAI EM UMA LINHA SO, e isto nao e cosmetica.
    #
    # Cada motivo e escrito com quebra de linha ao fim, e ler o arquivo inteiro
    # trazia essas quebras para dentro do canal. `lib/output` recusa registro com
    # quebra de linha em modo de linha — corretamente, por `RNF-10`: melhor
    # sinalizar a ambiguidade que emitir registro corrompido. So que a recusa
    # derruba o REGISTRO INTEIRO, e o registro inteiro e o plano do `sync`.
    #
    # O sintoma foi exatamente o que se espera de uma falha em cascata: com
    # travessia parcial — que e quando o operador MAIS precisa do plano — a saida
    # vinha sem plano nenhum, e nada dizia que faltava. O componente que recusa
    # esta certo; quem o alimentava e que nao podia entregar quebra de linha.
    local _linha
    DBX_WALK_MOTIVO=''
    while IFS= read -r _linha; do
      [[ -n $_linha ]] || continue
      DBX_WALK_MOTIVO="${DBX_WALK_MOTIVO}${DBX_WALK_MOTIVO:+; }${_linha}"
    done <"$motivos"
  fi
  rm -f -- "$motivos" 2>/dev/null

  # Contagem por registro, e nao por linha: o separador e o byte nulo justamente
  # porque nome de arquivo carrega quebra de linha, e contar linhas devolveria
  # numero maior que o real sem ninguem notar.
  DBX_WALK_TOTAL=0
  local _resto
  while IFS= read -r -d '' _resto; do
    DBX_WALK_TOTAL=$((DBX_WALK_TOTAL + 1))
  done <"$destino"
  return 0
}

# dbx_walk_ler <arquivo> <nome_do_vetor_de_caminhos> <nome_do_vetor_de_tamanhos>
#   <nome_do_vetor_de_mtimes>
#
# Vetores por NOME, como em lib/output e lib/http: passar por cadeia unica
# perderia nome com quebra de linha, e o nome mantem a procedencia visivel no
# ponto de chamada.
dbx_walk_ler() {
  [[ $# -eq 4 ]] || return "$DBX_WALK_ERRO_USO"
  local arquivo=$1
  local -n _caminhos=$2 _tamanhos=$3 _mtimes=$4
  local registro resto
  _caminhos=()
  _tamanhos=()
  _mtimes=()
  [[ -r $arquivo ]] || return 0
  while IFS= read -r -d '' registro; do
    _tamanhos+=("${registro%%$'\t'*}")
    resto=${registro#*$'\t'}
    _mtimes+=("${resto%%$'\t'*}")
    _caminhos+=("${resto#*$'\t'}")
  done <"$arquivo"
  return 0
}
