#!/usr/bin/env bash
# lib/atributos.sh — leitura UNICA de atributos de arquivo (RF-167, F-52).
#
# Camada: adaptadores. Nao depende de nenhum outro modulo; so do `stat`, que o
# preflight ja exige.
#
# POR QUE UM PONTO SO
#
#   O `stat` do GNU le por `-c <formato>`; o do FreeBSD, por `-f <formato>`, e no
#   GNU `-f` e "estado do sistema de arquivos" e SUCEDE com saida errada. Por isso
#   a forma GNU vem sempre primeiro, numa sonda unica sobre este proprio arquivo
#   antes da primeira leitura; a BSD so e adotada quando o utilitario RECUSA a
#   primeira (portabilidade por capacidade, nunca por nome de sistema). Falha de
#   leitura no alvo nao decide a forma.
#   Nenhum outro arquivo do produto chama `stat` com `-c` ou `-f`.
#
# USO
#
#   dbx_atributo [-L] <campo> <arquivo>
#
#   Publica o valor em DBX_ATRIBUTO (sem subshell, de modo que o formato
#   aprendido na primeira leitura vale para as seguintes: uma chamada por
#   atributo). Status 0 com o valor; 1 quando a leitura falha, com DBX_ATRIBUTO
#   vazio — quem chama decide o que fazer, nunca assume `0` nem vazio (RF-167(e));
#   2 em uso invalido. `-L` segue elo simbolico (e /dev/fd/N).
#
#   dbx_atributo_fd <campo> <fd>
#
#   Os mesmos campos, mais `tipo` (regular|outro), lidos do PROPRIO descritor
#   aberto, sem montar `/dev/fd/<n>` (que no FreeBSD nao e o arquivo, ou nem
#   existe): GNU `stat -L -c <fmt> -` e BSD `stat -f <fmt>` sem operando, ambos
#   sobre a entrada padrao redirecionada do descritor. `dbx_fd_regular_proprio
#   <fd>` confere regular + dono = EUID.
#
#   Campos: modo (octal) | modo_simbolico | dono (uid) | grupo (gid) | tamanho |
#   mtime (segundos) | dev | ino | dev_ino (`d|i`) | dev_ino_tamanho (`d|i|s`) |
#   identidade | fs_tipo.
#
# IDENTIDADE
#
#   `tamanho<TAB>mtime|mtime-com-ns|ctime-com-ns|dev|ino|tamanho`. No GNU os
#   nanossegundos vem do texto de `%y`/`%z` (exato, ver lib/hash). RECUO BSD: o
#   `stat` basico do BSD nao traz nanossegundos, entao os dois campos de tempo
#   saem em segundos com fracao `.000000000`. A cadeia continua estavel entre
#   duas leituras do mesmo arquivo e muda quando tamanho, dispositivo, inode,
#   mtime ou ctime (em segundos) mudam; a unica perda e distinguir reescrita no
#   mesmo segundo com o mesmo tamanho e o mesmo inode.
#
# fs_tipo
#
#   `stat -f -c %T` so existe no GNU. No BSD nao ha forma portavel: a leitura
#   falha e o diagnostico diz "nao verificado" (I-64).

[[ -n ${DBX_ATRIBUTOS_CARREGADO:-} ]] && return 0
DBX_ATRIBUTOS_CARREGADO=1

DBX_ATRIBUTO=''
# Forma que o utilitario aceitou: vazio (ainda nao aprendida), gnu ou bsd.
_dbx_atributos_forma=''
# Formatos do campo em leitura, preenchidos por _dbx_atributos_formatos.
_dbx_atributos_formato_gnu=''
_dbx_atributos_formato_bsd=''

# _dbx_atributos_formatos <campo> — define os dois formatos; 1 se o campo e desconhecido.
_dbx_atributos_formatos() {
  local tab=$'\t'
  case $1 in
    modo) _dbx_atributos_formato_gnu='%a' _dbx_atributos_formato_bsd='%Mp%03Lp' ;;
    modo_simbolico) _dbx_atributos_formato_gnu='%A' _dbx_atributos_formato_bsd='%Sp' ;;
    modo_exibicao) _dbx_atributos_formato_gnu='%a (%A)' _dbx_atributos_formato_bsd='%Mp%03Lp (%Sp)' ;;
    dono_grupo) _dbx_atributos_formato_gnu='%u:%g' _dbx_atributos_formato_bsd='%u:%g' ;;
    dono) _dbx_atributos_formato_gnu='%u' _dbx_atributos_formato_bsd='%u' ;;
    grupo) _dbx_atributos_formato_gnu='%g' _dbx_atributos_formato_bsd='%g' ;;
    tamanho) _dbx_atributos_formato_gnu='%s' _dbx_atributos_formato_bsd='%z' ;;
    mtime) _dbx_atributos_formato_gnu='%Y' _dbx_atributos_formato_bsd='%m' ;;
    dev) _dbx_atributos_formato_gnu='%d' _dbx_atributos_formato_bsd='%d' ;;
    ino) _dbx_atributos_formato_gnu='%i' _dbx_atributos_formato_bsd='%i' ;;
    dev_ino) _dbx_atributos_formato_gnu='%d|%i' _dbx_atributos_formato_bsd='%d|%i' ;;
    dev_ino_tamanho) _dbx_atributos_formato_gnu='%d|%i|%s' _dbx_atributos_formato_bsd='%d|%i|%z' ;;
    tipo) _dbx_atributos_formato_gnu='%F' _dbx_atributos_formato_bsd='%HT' ;;
    identidade)
      _dbx_atributos_formato_gnu="%s${tab}%Y|%y|%z|%d|%i|%s"
      _dbx_atributos_formato_bsd="%z${tab}%m|%m.000000000|%c.000000000|%d|%i|%z"
      ;;
    *) return 1 ;;
  esac
}

# dbx_atributo [-L] <campo> <arquivo> — ver o cabecalho do modulo.
dbx_atributo() {
  local seguir=() leitura=''
  DBX_ATRIBUTO=''
  if [[ ${1:-} == -L ]]; then
    seguir=(-L)
    shift
  fi
  [[ $# -eq 2 ]] || return 2
  if [[ $1 == fs_tipo ]]; then
    # Sem forma BSD: tenta so a GNU e falha no BSD ("nao verificado").
    # Captura (e nao `read < <()`) para o status do stat decidir: o BSD ainda
    # imprime algo para o operando valido ao recusar os demais.
    leitura=$(stat -f -c %T -- "$2" 2>/dev/null) || return 1
    DBX_ATRIBUTO=$leitura
    return 0
  fi
  _dbx_atributos_formatos "$1" || return 2
  _dbx_atributos_aprender_forma || return 1
  # Captura, e nao `read < <()`: a substituicao de processo nao espera o `stat`
  # terminar nem devolve o status dele, e quem chama confere o arquivo logo em
  # seguida (barreira de inode do `.part`).
  if [[ $_dbx_atributos_forma == gnu ]]; then
    leitura=$(stat "${seguir[@]}" -c "$_dbx_atributos_formato_gnu" -- "$2" 2>/dev/null) || return 1
  else
    leitura=$(stat "${seguir[@]}" -f "$_dbx_atributos_formato_bsd" -- "$2" 2>/dev/null) || return 1
    _dbx_atributos_normalizar_modo "$1"
  fi
  # shellcheck disable=SC2034  # canal publico, lido pelo chamador
  DBX_ATRIBUTO=$leitura
  return 0
}

# _dbx_atributos_normalizar_modo <campo> — `%Mp%03Lp` traz o digito
# suid/sgid/sticky e tres digitos de permissao (o `%Lp` do BSD sai sem zeros a
# esquerda: 0044 seria "44"); o GNU nao escreve zeros a esquerda. Age sobre
# `leitura` de quem chama (escopo dinamico).
_dbx_atributos_normalizar_modo() {
  if [[ $1 == modo || $1 == modo_exibicao ]]; then
    leitura=${leitura#"${leitura%%[!0]*}"}
    [[ $leitura == [0-9]* ]] || leitura=0$leitura
  fi
}

# dbx_atributo_fd <campo> <fd> — como dbx_atributo, mas do PROPRIO descritor
# aberto <fd> (nao de um caminho), sem jamais montar `/dev/fd/<n>`: no FreeBSD
# esse caminho nao existe sem `fdescfs` e, com ele, aponta o no do fdescfs e nao
# o arquivo (RF-171(a), DIV-352). O GNU le por `stat -L -c <fmt> -` e o BSD por
# `stat -f <fmt>` SEM operando, que le a entrada padrao (fstat do descritor 0);
# nos dois, a entrada padrao do utilitario e o descritor. Funciona tambem com
# descritor so de escrita. Mais um campo, `tipo`: `regular` ou `outro`.
dbx_atributo_fd() {
  local leitura=''
  DBX_ATRIBUTO=''
  [[ $# -eq 2 && $2 =~ ^[0-9]+$ ]] || return 2
  _dbx_atributos_formatos "$1" || return 2
  _dbx_atributos_aprender_forma || return 1
  # A redirecao do erro vem ANTES da do descritor, para um descritor fechado nao
  # escrever a mensagem do shell.
  if [[ $_dbx_atributos_forma == gnu ]]; then
    leitura=$(stat -L -c "$_dbx_atributos_formato_gnu" - 2>/dev/null <&"$2") || return 1
  else
    leitura=$(stat -f "$_dbx_atributos_formato_bsd" 2>/dev/null <&"$2") || return 1
    _dbx_atributos_normalizar_modo "$1"
  fi
  if [[ $1 == tipo ]]; then
    leitura=${leitura,,}
    case $leitura in
      regular*) leitura=regular ;;
      *) leitura=outro ;;
    esac
  fi
  # shellcheck disable=SC2034  # canal publico, lido pelo chamador
  DBX_ATRIBUTO=$leitura
  return 0
}

# dbx_fd_regular_proprio <fd> — 0 quando o descritor e de arquivo regular do
# usuario (a conferencia que o produto fazia por `[[ -f /dev/fd/N && -O ... ]]`).
dbx_fd_regular_proprio() {
  dbx_atributo_fd tipo "$1" || return 1
  [[ $DBX_ATRIBUTO == regular ]] || return 1
  dbx_atributo_fd dono "$1" || return 1
  [[ $DBX_ATRIBUTO == "$EUID" ]]
}

# _dbx_atributos_aprender_forma — sonda UNICA sobre um caminho garantido (este
# proprio arquivo) antes da primeira leitura: a falha no alvo (ausente, sem
# permissao) nunca decide a forma. 1 se nenhuma das duas formas funciona.
_dbx_atributos_aprender_forma() {
  [[ -n $_dbx_atributos_forma ]] && return 0
  if stat -c %a -- "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    _dbx_atributos_forma=gnu
  elif stat -f %Lp -- "${BASH_SOURCE[0]}" >/dev/null 2>&1; then
    _dbx_atributos_forma=bsd
  else
    return 1
  fi
}
