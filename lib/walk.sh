#!/usr/bin/env bash
# lib/walk.sh — travessia local por descida (RNF-28, RF-41a, RF-50).
#
# Camada: adaptadores. Depende de lib/errors.sh e lib/hash.sh (identidade do arquivo), de dominio.
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

# Unica entrada por caminho montado da travessia (auditoria DP-26): roda no
# shell do subshell chamador, entao o `cd` vale para ele. Nenhum outro ponto
# reabre diretorio por caminho; a descida e sempre por nome relativo.
_dbx_walk_entrar_raiz() {
  local raiz=$1
  cd -P -- "$raiz" || return
}
# shellcheck source=lib/errors.sh
. "$_dbx_walk_diretorio/errors.sh"
# shellcheck source=lib/hash.sh
. "$_dbx_walk_diretorio/hash.sh"
# shellcheck source=lib/tmp.sh
. "$_dbx_walk_diretorio/tmp.sh"
# shellcheck source=lib/filtro.sh
. "$_dbx_walk_diretorio/filtro.sh"
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
# RF-80(b): pastas (e entradas que nao sao arquivo comum) fora do escopo que a
# descida PODOU, por caminho relativo. Quem consome as conta como filtradas.
declare -ga DBX_WALK_PODADAS=()
_dbx_walk_filtrar='nao'
_dbx_walk_conjunto=''

# _dbx_walk_descer <profundidade> <prefixo>
#
# Emite um registro por entrada na saida padrao e um motivo por linha no
# descritor 3. Roda SEMPRE dentro do subshell montado por `dbx_walk_local`, para
# que a mudanca de diretorio nao escape para o processo do chamador.
#
# Formato do registro: `tamanho<TAB>identidade<TAB>caminho\0` (identidade sem TAB;
# vazia quando o `stat` nao a oferece).
# O caminho vai POR ULTIMO e o registro termina em byte nulo, porque nome de
# arquivo aceita tabulacao e quebra de linha — e nao aceita nulo. Qualquer outra
# ordem perderia nomes legitimos, que e a classe de defeito ja vista tres vezes
# neste projeto.
_dbx_walk_descer() {
  local profundidade=$1 prefixo=$2
  local nome relativo tamanho identidade

  if [[ $profundidade -gt $DBX_WALK_PROFUNDIDADE_MAXIMA ]]; then
    printf 'profundidade maxima excedida em: %s\n' "${prefixo:-.}" >&3
    return 0
  fi

  for nome in *; do
    relativo="${prefixo}${nome}"

    # RF-80(b): pasta que casa `--excluir` NAO E PERCORRIDA — nem listada, nem
    # inspecionada, nem resumida —, e erro dentro dela (ilegivel, ciclo) nao
    # existe para a execucao. A conferencia vem ANTES da de legibilidade, para
    # a propria pasta excluida ilegivel tambem nao marcar a travessia parcial.
    # Vinculo e entrada que nao e arquivo comum so saem em silencio se ficam
    # fora do escopo tanto como arquivo quanto como pasta: assim o par do outro
    # lado, seja do tipo que for, tambem esta fora, e nada e apagado por eles.
    _dbx_walk_podar_entrada "$relativo" "$nome" && continue

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

    # Uma leitura so: tamanho e identidade, ambos por dbx_atributo (GNU ou BSD;
    # no BSD sem nanossegundos). Se a leitura falha a identidade fica vazia, e
    # quem a consome nao reaproveita resumo algum — mais lento, nunca errado.
    if dbx_hash_identidade "$nome"; then
      tamanho=$DBX_HASH_TAMANHO_ARQUIVO
      identidade=$DBX_HASH_IDENTIDADE
    elif dbx_atributo tamanho "$nome"; then
      tamanho=$DBX_ATRIBUTO
      identidade=''
    else
      printf 'nao foi possivel inspecionar: %s\n' "$relativo" >&3
      continue
    fi

    printf '%s\t%s\t%s\0' "$tamanho" "$identidade" "$relativo"
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
  local raiz=$1 destino=$2 motivos podadas

  DBX_WALK_PARCIAL='nao'
  DBX_WALK_MOTIVO=''
  DBX_WALK_TOTAL=0
  DBX_WALK_PODADAS=()
  _dbx_walk_filtrar='nao'
  dbx_filtro_ativo && _dbx_walk_filtrar='sim'

  [[ -d $raiz ]] || return "$DBX_WALK_ERRO_NAO_ENCONTRADO"
  [[ -r $raiz && -x $raiz ]] || return "$DBX_WALK_ERRO_NAO_ENCONTRADO"

  dbx_tmp_arquivo "${TMPDIR:-/tmp}/dbx-walk.XXXXXXXX" || return "$DBX_WALK_ERRO_USO"
  motivos=$DBX_TMP_CAMINHO
  dbx_tmp_arquivo "${TMPDIR:-/tmp}/dbx-walk.XXXXXXXX" || {
    dbx_tmp_remover "$motivos"
    return "$DBX_WALK_ERRO_USO"
  }
  podadas=$DBX_TMP_CAMINHO

  : >"$destino"
  (
    # `nullglob` para que diretorio vazio nao produza a cadeia literal `*` como
    # se fosse um arquivo chamado asterisco; `dotglob` para que arquivo oculto
    # seja transferido como qualquer outro — omiti-lo faria o destino divergir
    # em silencio. `.` e `..` nao entram por `dotglob`.
    shopt -s nullglob dotglob
    _dbx_walk_entrar_raiz "$raiz" || exit 1
    _dbx_walk_descer 1 ''
  ) >"$destino" 3>"$motivos" 4>"$podadas"

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
  dbx_tmp_remover "$motivos"
  local _podada
  while IFS= read -r -d '' _podada; do
    DBX_WALK_PODADAS+=("$_podada")
  done <"$podadas"
  dbx_tmp_remover "$podadas"

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
#   <nome_do_vetor_de_identidades>
#
# Vetores por NOME, como em lib/output e lib/http: passar por cadeia unica
# perderia nome com quebra de linha, e o nome mantem a procedencia visivel no
# ponto de chamada.
dbx_walk_ler() {
  [[ $# -eq 4 ]] || return "$DBX_WALK_ERRO_USO"
  local arquivo=$1
  local -n _caminhos=$2 _tamanhos=$3 _identidades=$4
  local registro resto
  _caminhos=()
  _tamanhos=()
  _identidades=()
  [[ -r $arquivo ]] || return 0
  while IFS= read -r -d '' registro; do
    _tamanhos+=("${registro%%$'\t'*}")
    resto=${registro#*$'\t'}
    _identidades+=("${resto%%$'\t'*}")
    _caminhos+=("${resto#*$'\t'}")
  done <"$arquivo"
  return 0
}

# ---------------------------------------------------------------------------
# Travessia por diretorio (F-101, RF-187, RF-188(a)) — etapa 2
# ---------------------------------------------------------------------------
#
# Duas passadas, e as DUAS mantem as guardas da descida acima (nome relativo,
# ligacao simbolica = parcial, `\0` nos registros, poda por filtro):
#
#   `dbx_walk_diretorios` enumera so os DIRETORIOS, cada um com a contagem dos
#   seus arquivos diretos no escopo (nada de resumo, nada de `stat`);
#   `dbx_walk_ciclo` le os arquivos diretos de um grupo de diretorios.
#
# Ordem de descoberta; quem planeja os ciclos ordena (DIV-384).

# RF-80(b): poda da entrada fora do escopo do filtro (pasta excluida; vinculo ou
# entrada que nao e arquivo comum fora de qualquer padrao). Status 0 = podada
# (o relativo vai ao fd 4 e o chamador segue para a proxima entrada). Roda no
# diretorio corrente da travessia, com `$2` o nome nele. Unico lugar da regra:
# as tres travessias (`dbx_walk_local`, `_dbx_walk_dirs`, `_dbx_walk_ciclo_dir`).
_dbx_walk_podar_entrada() {
  local relativo=$1 nome=$2
  [[ $_dbx_walk_filtrar == 'sim' ]] || return 1
  if [[ -d $nome && ! -L $nome ]]; then
    if dbx_filtro_pasta_excluida "$relativo"; then
      printf '%s\0' "$relativo" >&4
      return 0
    fi
  elif [[ -L $nome || ! -f $nome ]]; then
    if ! dbx_filtro_classificar "$relativo" nao && ! dbx_filtro_classificar "$relativo" sim; then
      printf '%s\0' "$relativo" >&4
      return 0
    fi
  fi
  return 1
}

# _dbx_walk_dirs <profundidade> <prefixo> — roda no subshell de `dbx_walk_diretorios`.
# Registro: `contagem<TAB>caminho_relativo\0` (raiz com caminho vazio).
_dbx_walk_dirs() {
  local profundidade=$1 prefixo=$2 nome relativo n=0
  local -a subs=()
  if [[ $profundidade -gt $DBX_WALK_PROFUNDIDADE_MAXIMA ]]; then
    printf 'profundidade maxima excedida em: %s\n' "${prefixo:-.}" >&3
    return 0
  fi
  for nome in *; do
    relativo="${prefixo}${nome}"
    _dbx_walk_podar_entrada "$relativo" "$nome" && continue
    if [[ -L $nome ]]; then
      printf 'ligacao simbolica nao percorrida: %s\n' "$relativo" >&3
      continue
    fi
    if [[ -d $nome ]]; then
      subs+=("$nome")
      continue
    fi
    if [[ ! -f $nome ]]; then
      printf 'entrada nao e arquivo comum: %s\n' "$relativo" >&3
      continue
    fi
    # So o que entraria no ciclo conta: fora do escopo de caminho e temporario de
    # recebimento ficam de fora (RF-196(b)).
    if [[ $_dbx_walk_filtrar == 'sim' ]] && ! dbx_filtro_classificar "$relativo" nao; then
      continue
    fi
    [[ -n ${DBX_CMD_MARCA_RECEBIMENTO:-} && $nome == .*"$DBX_CMD_MARCA_RECEBIMENTO"?????? ]] && continue
    n=$((n + 1))
  done
  printf '%s\t%s\0' "$n" "${prefixo%/}"
  for nome in ${subs[@]+"${subs[@]}"}; do
    relativo="${prefixo}${nome}"
    if [[ ! -r $nome || ! -x $nome ]]; then
      printf 'diretorio ilegivel: %s\n' "$relativo" >&3
      continue
    fi
    if ! cd -- "$nome" 2>/dev/null; then
      printf 'nao foi possivel descer em: %s\n' "$relativo" >&3
      continue
    fi
    _dbx_walk_dirs $((profundidade + 1)) "$relativo/"
    if ! cd .. 2>/dev/null; then
      printf 'nao foi possivel retornar de: %s\n' "$relativo" >&3
      return 1
    fi
  done
  return 0
}

# _dbx_walk_motivos <arquivo_de_motivos> — junta os motivos em DBX_WALK_MOTIVO
# (uma linha so, ver a nota de `dbx_walk_local`) e marca a travessia parcial.
_dbx_walk_motivos() {
  local _linha
  [[ -s $1 ]] || return 0
  # shellcheck disable=SC2034  # canais publicos, ver nota no topo
  DBX_WALK_PARCIAL='sim'
  DBX_WALK_MOTIVO=''
  while IFS= read -r _linha; do
    [[ -n $_linha ]] || continue
    DBX_WALK_MOTIVO="${DBX_WALK_MOTIVO}${DBX_WALK_MOTIVO:+; }${_linha}"
  done <"$1"
}

# dbx_walk_diretorios <raiz> <arquivo_de_registros> [<subdiretorio_inicial>]
#
# Enumera os diretorios sob a raiz (ou sob o subdiretorio inicial, para a
# varredura de um ramo so do destino, RF-190(b)). Mesmas marcas de parcialidade
# de `dbx_walk_local`; `DBX_WALK_PODADAS` traz o que o filtro podou.
dbx_walk_diretorios() {
  [[ $# -ge 2 && $# -le 3 ]] || return "$DBX_WALK_ERRO_USO"
  local raiz=$1 destino=$2 inicio=${3:-} motivos podadas
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_WALK_PARCIAL='nao'
  DBX_WALK_MOTIVO=''
  DBX_WALK_TOTAL=0
  DBX_WALK_PODADAS=()
  _dbx_walk_filtrar='nao'
  dbx_filtro_ativo && _dbx_walk_filtrar='sim'
  [[ -d $raiz && -r $raiz && -x $raiz ]] || return "$DBX_WALK_ERRO_NAO_ENCONTRADO"
  dbx_tmp_arquivo "${TMPDIR:-/tmp}/dbx-walk.XXXXXXXX" || return "$DBX_WALK_ERRO_USO"
  motivos=$DBX_TMP_CAMINHO
  dbx_tmp_arquivo "${TMPDIR:-/tmp}/dbx-walk.XXXXXXXX" || {
    dbx_tmp_remover "$motivos"
    return "$DBX_WALK_ERRO_USO"
  }
  podadas=$DBX_TMP_CAMINHO
  : >"$destino"
  (
    shopt -s nullglob dotglob
    _dbx_walk_entrar_raiz "$raiz" || exit 1
    resto=$inicio
    while [[ -n $resto ]]; do
      comp=${resto%%/*}
      if [[ $resto == */* ]]; then resto=${resto#*/}; else resto=''; fi
      if [[ -d $comp && ! -L $comp ]] && cd -- "$comp" 2>/dev/null; then
        :
      else
        printf 'nao foi possivel descer em: %s\n' "$inicio" >&3
        exit 0
      fi
    done
    _dbx_walk_dirs 1 "${inicio:+$inicio/}"
  ) >"$destino" 3>"$motivos" 4>"$podadas"
  _dbx_walk_motivos "$motivos"
  dbx_tmp_remover "$motivos"
  local _podada _reg
  while IFS= read -r -d '' _podada; do
    DBX_WALK_PODADAS+=("$_podada")
  done <"$podadas"
  dbx_tmp_remover "$podadas"
  while IFS= read -r -d '' _reg; do
    DBX_WALK_TOTAL=$((DBX_WALK_TOTAL + 1))
  done <"$destino"
  return 0
}

# _dbx_walk_ciclo_dir <diretorio_relativo> — roda em subshell proprio, herdando
# a raiz como diretorio corrente. Desce por componente (ligacao = parcial) e
# emite os arquivos DIRETOS (`tamanho<TAB>identidade<TAB>caminho\0`, o formato de
# `dbx_walk_local`) no descritor 1 e os subdiretorios no 5. Diretorio que nao
# existe e vazio legitimo (destino ainda nao criado), nunca parcialidade.
_dbx_walk_ciclo_dir() {
  local dir=$1 resto=$1 comp prefixo='' nome relativo tamanho identidade
  local -A _conj_vazio=()
  local -n _conj=${_dbx_walk_conjunto:-_conj_vazio}
  while [[ -n $resto ]]; do
    comp=${resto%%/*}
    if [[ $resto == */* ]]; then resto=${resto#*/}; else resto=''; fi
    if [[ -L $comp ]]; then
      printf 'ligacao simbolica nao percorrida: %s\n' "$dir" >&3
      return 0
    fi
    [[ -d $comp ]] || return 0
    if [[ ! -r $comp || ! -x $comp ]]; then
      printf 'diretorio ilegivel: %s\n' "$dir" >&3
      return 0
    fi
    if ! cd -- "$comp" 2>/dev/null; then
      printf 'nao foi possivel descer em: %s\n' "$dir" >&3
      return 0
    fi
  done
  [[ -n $dir ]] && prefixo="$dir/"
  for nome in *; do
    relativo="${prefixo}${nome}"
    _dbx_walk_podar_entrada "$relativo" "$nome" && continue
    if [[ -L $nome ]]; then
      printf 'ligacao simbolica nao percorrida: %s\n' "$relativo" >&3
      continue
    fi
    if [[ -d $nome ]]; then
      printf '%s\0' "$relativo" >&5
      # Ramo SO DO DESTINO (fora do conjunto de diretorios da origem): lido inteiro
      # aqui, pela descida de sempre, para o ciclo planejar a exclusao dele (RF-190(b)).
      if [[ -n $_dbx_walk_conjunto && -z ${_conj["k:${relativo,,}"]+definido} ]]; then
        if [[ ! -r $nome || ! -x $nome ]]; then
          printf 'diretorio ilegivel: %s\n' "$relativo" >&3
        elif ! (cd -- "$nome" 2>/dev/null && _dbx_walk_descer 2 "$relativo/"); then
          printf 'nao foi possivel ler o ramo: %s\n' "$relativo" >&3
        fi
      fi
      continue
    fi
    if [[ ! -f $nome ]]; then
      printf 'entrada nao e arquivo comum: %s\n' "$relativo" >&3
      continue
    fi
    if dbx_hash_identidade "$nome"; then
      tamanho=$DBX_HASH_TAMANHO_ARQUIVO
      identidade=$DBX_HASH_IDENTIDADE
    elif dbx_atributo tamanho "$nome"; then
      tamanho=$DBX_ATRIBUTO
      identidade=''
    else
      printf 'nao foi possivel inspecionar: %s\n' "$relativo" >&3
      continue
    fi
    printf '%s\t%s\t%s\0' "$tamanho" "$identidade" "$relativo"
  done
  return 0
}

# dbx_walk_ciclo <raiz> <arquivo_de_diretorios> <ini> <fim> <arquivo_de_registros>
#   [<arquivo_de_subdiretorios>]
#
# Os arquivos diretos dos diretorios `ini..fim-1` (fim exclusivo) do arquivo de
# diretorios (`contagem<TAB>caminho\0`, ja na ordem dos ciclos). Os
# subdiretorios vistos vao ao ultimo arquivo (para achar ramos so do destino).
dbx_walk_ciclo() {
  [[ $# -ge 5 && $# -le 7 ]] || return "$DBX_WALK_ERRO_USO"
  _dbx_walk_conjunto=${7:-}
  local raiz=$1 dirs=$2 ini=$3 fim=$4 destino=$5 filhos=${6:-/dev/null} motivos reg i=0 _r
  [[ $ini =~ ^[0-9]+$ && $fim =~ ^[0-9]+$ ]] || return "$DBX_WALK_ERRO_USO"
  # shellcheck disable=SC2034  # canal publico, ver nota no topo
  DBX_WALK_PARCIAL='nao'
  DBX_WALK_MOTIVO=''
  DBX_WALK_TOTAL=0
  DBX_WALK_PODADAS=()
  _dbx_walk_filtrar='nao'
  dbx_filtro_ativo && _dbx_walk_filtrar='sim'
  [[ -d $raiz && -r $raiz && -x $raiz ]] || return "$DBX_WALK_ERRO_NAO_ENCONTRADO"
  dbx_tmp_arquivo "${TMPDIR:-/tmp}/dbx-walk.XXXXXXXX" || return "$DBX_WALK_ERRO_USO"
  motivos=$DBX_TMP_CAMINHO
  : >"$destino"
  [[ $filhos == /dev/null ]] || : >"$filhos"
  (
    shopt -s nullglob dotglob
    _dbx_walk_entrar_raiz "$raiz" || exit 1
    while IFS= read -r -d '' reg; do
      ((i >= fim)) && break
      if ((i >= ini)); then
        (_dbx_walk_ciclo_dir "${reg#*$'\t'}")
      fi
      i=$((i + 1))
    done <"$dirs"
  ) >"$destino" 3>"$motivos" 4>"$motivos.podadas" 5>>"$filhos"
  _dbx_walk_motivos "$motivos"
  dbx_tmp_remover "$motivos"
  while IFS= read -r -d '' _r; do
    DBX_WALK_PODADAS+=("$_r")
  done <"$motivos.podadas"
  rm -f -- "$motivos.podadas"
  while IFS= read -r -d '' _r; do
    DBX_WALK_TOTAL=$((DBX_WALK_TOTAL + 1))
  done <"$destino"
  return 0
}
