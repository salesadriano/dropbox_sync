#!/usr/bin/env bash
# Conferencia pelo PROPRIO descritor, sem /dev/fd/<n> (RF-171(a); TC-FBSD-20;
# DIV-352, decisao final).
#
# No FreeBSD, com `fdescfs` montado sem opcao, `/dev/fd/3` e um dispositivo de
# caracteres e `stat -L` devolve o no do fdescfs, nao o arquivo; sem `fdescfs`,
# `/dev/fd/N` com N>2 nem existe. Por isso nenhum caminho do produto depende de
# `/dev/fd/<n>`: o descritor e conferido por `dbx_atributo_fd` (GNU `stat -L -c
# <fmt> -` e BSD `stat -f <fmt>` sem operando, ambos lendo a entrada padrao
# redirecionada do descritor) e o `.part` e reaberto pelo CAMINHO, com a
# identidade (dev|ino) conferida contra a do descritor original.
#
# O duble de stat BSD devolve, para qualquer operando `/dev/fd/<n>`, um no
# proprio do fdescfs (dispositivo de caracteres, dev/ino fixos): quem ainda
# dependesse do caminho leria a identidade errada.
#
# shellcheck disable=SC2016
# Justificativa: roteiros de processos filhos e amostras da auditoria sao literais.
#
# shellcheck disable=SC2034
# Justificativa: canais de lib/ ajustados pelos casos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"
. "$DBX_HARNESS_RAIZ/lib/progress.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"
. "$DBX_HARNESS_RAIZ/lib/cmd.sh"

CONTA='cred-0123456789abcdef0123456789abcdef'
ASSIN='list_folder;recursive=1;limit=100'
H64='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'

_area() {
  mktemp -d "$DBX_TESTES_TMP/descritor.XXXXXX"
}

# ---------------------------------------------------------------------------
# O duble reproduz o defeito do FreeBSD 15 (sem ele, o resto nao prova nada)
# ---------------------------------------------------------------------------

teste_duplo_devolve_no_do_fdescfs_para_dev_fd() {
  local area fd
  area=$(_area)
  printf 'abcde' >"$area/a"
  exec {fd}<"$area/a"
  dbx_freebsd_ativar
  assert_igual 'Character Device' "$(stat -L -f %HT "/dev/fd/$fd")" '/dev/fd/<n> e dispositivo de caracteres'
  assert_diferente "$(dbx_freebsd_real stat -L -c '%d|%i' -- "$area/a")" "$(stat -L -f '%d|%i' "/dev/fd/$fd")" 'o no do fdescfs nao e o do arquivo'
  exec {fd}<&-
}

teste_duplo_le_a_entrada_padrao_quando_f_nao_tem_operando() {
  local area fd
  area=$(_area)
  printf 'abcde' >"$area/a"
  exec {fd}<"$area/a"
  dbx_freebsd_ativar
  assert_igual 5 "$(stat -f %z <&"$fd")" '`stat -f <fmt>` sem operando e o fstat da entrada padrao'
  exec {fd}<&-
}

# ---------------------------------------------------------------------------
# dbx_atributo_fd
# ---------------------------------------------------------------------------

_confere_atributos_do_descritor() { # <rotulo>
  local area fd esperado
  area=$(_area)
  printf 'abcde' >"$area/a"
  exec {fd}<"$area/a"
  dbx_atributo_fd tipo "$fd"
  assert_igual 0 $? "$1: tipo, status"
  assert_igual regular "$DBX_ATRIBUTO" "$1: arquivo comum"
  dbx_atributo_fd dono "$fd"
  assert_igual "$EUID" "$DBX_ATRIBUTO" "$1: dono"
  dbx_atributo_fd tamanho "$fd"
  assert_igual 5 "$DBX_ATRIBUTO" "$1: tamanho"
  esperado=$(dbx_freebsd_real stat -L -c '%d|%i' -- "$area/a")
  dbx_atributo_fd dev_ino "$fd"
  assert_igual "$esperado" "$DBX_ATRIBUTO" "$1: dev|ino do arquivo, nao do no do fdescfs"
  dbx_atributo_fd dev_ino_tamanho "$fd"
  assert_igual "$esperado|5" "$DBX_ATRIBUTO" "$1: dev|ino|tamanho"
  exec {fd}<&-
  # descritor so de escrita (o `.part` anexado)
  exec {fd}>>"$area/a"
  dbx_atributo_fd tamanho "$fd"
  assert_igual 5 "$DBX_ATRIBUTO" "$1: descritor so de escrita"
  exec {fd}>&-
  # diretorio nao e regular
  exec {fd}<"$area"
  dbx_atributo_fd tipo "$fd"
  assert_igual outro "$DBX_ATRIBUTO" "$1: diretorio e outro"
  exec {fd}<&-
  # descritor invalido falha sem valor
  dbx_atributo_fd tamanho 997 2>/dev/null
  assert_igual 1 $? "$1: descritor fechado falha"
  assert_igual '' "$DBX_ATRIBUTO" "$1: sem valor quando falha"
  dbx_atributo_fd inexistente 0
  assert_igual 2 $? "$1: campo desconhecido"
  dbx_atributo_fd tamanho x
  assert_igual 2 $? "$1: descritor nao numerico"
}

teste_atributo_fd_le_do_proprio_descritor_com_stat_bsd() {
  dbx_freebsd_ativar
  _confere_atributos_do_descritor bsd
  assert_igual '' "$(dbx_freebsd_erros | grep -v 'illegal option -- c')" 'o duble nao recusou nada alem do `-c`'
}

teste_atributo_fd_le_do_proprio_descritor_com_stat_gnu() {
  _confere_atributos_do_descritor gnu
}

# ---------------------------------------------------------------------------
# Barreira do `.part`
# ---------------------------------------------------------------------------

_prepara_part() { # define DIR, NOME, PARTE, DEVINO
  DIR=$(_area)
  NOME='.alvo.dbx-part.AbCdEf'
  PARTE="$DIR/$NOME"
  printf 'abc' >"$PARTE"
  DEVINO=$(dbx_freebsd_real stat -c '%d|%i' -- "$PARTE")
}

teste_barreira_do_part_aceita_o_legitimo_com_stat_bsd() {
  dbx_freebsd_ativar
  _prepara_part
  _dbx_cmd_part_abrir "$DIR" "$NOME" "$DEVINO" 10
  assert_igual 0 $? 'o .part legitimo abre'
  assert_igual 3 "$_DBX_CMD_PART_T" 'tamanho ja gravado'
  printf 'def' >&"$_DBX_CMD_PART_FD"
  _dbx_cmd_part_fechar
  assert_igual abcdef "$(cat -- "$PARTE")" 'a escrita anexa ao mesmo arquivo'
}

teste_barreira_do_part_recusa_tamanho_acima_do_esperado() {
  dbx_freebsd_ativar
  _prepara_part
  _dbx_cmd_part_abrir "$DIR" "$NOME" "$DEVINO" 2
  assert_igual 1 $? 'tamanho acima do esperado reprova'
  assert_igual '' "$_DBX_CMD_PART_FD" 'nenhum descritor fica aberto'
}

teste_barreira_do_part_recusa_troca_do_arquivo_entre_a_abertura_e_o_uso() {
  dbx_freebsd_ativar
  _prepara_part
  local troca="$DIR/intruso"
  eval "$(declare -f dbx_atributo_fd | sed '1s/dbx_atributo_fd/_original_atributo_fd/')"
  # shellcheck disable=SC2317  # a funcao dublada e chamada por lib/cmd
  dbx_atributo_fd() {
    _original_atributo_fd "$@"
    local estado=$?
    if [[ $1 == dev_ino_tamanho ]]; then
      # o nome e trocado depois da conferencia do descritor de leitura
      printf 'intruso' >"$troca"
      mv -f -- "$troca" "$PARTE"
    fi
    return "$estado"
  }
  _dbx_cmd_part_abrir "$DIR" "$NOME" "$DEVINO" 10
  assert_igual 1 $? 'o arquivo trocado reprova'
  assert_igual '' "$_DBX_CMD_PART_FD" 'nenhum descritor de escrita fica aberto'
  assert_igual intruso "$(cat -- "$PARTE")" 'nada foi escrito no arquivo trocado'
}

# ---------------------------------------------------------------------------
# Cursor e leitores de estado com o duble BSD
# ---------------------------------------------------------------------------

_filho() {
  local roteiro=$1
  shift
  FILHO_SAIDA=$(XDG_STATE_HOME="$AREA/xdg" TMPDIR="$AREA/tmp" RAIZ="$DBX_HARNESS_RAIZ" \
    CONTA="$CONTA" ASSIN="$ASSIN" H64="$H64" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    CTX() { dbx_state_cursor_contexto "$CONTA" dbid:CONTA "/home/u/l" /Fotos "$ASSIN"; }
    CORPO() {
      printf "f\tid:a\t0123456789a\t%s\t15\t-\t/Fotos/p/A.txt\0/fotos/p/a.txt\0" "$H64"
    }
    COLETAR() { printf "entrada %s|%s\n" "$3" "$2"; }
'"$roteiro" _ "$@" 2>&1 </dev/null)
}

teste_cursor_grava_e_carrega_com_stat_bsd() {
  AREA=$(_area)
  mkdir -p "$AREA/xdg" "$AREA/tmp"
  dbx_freebsd_ativar
  _filho 'CTX || exit 90; dbx_state_cursor_gravar CURSORSENTINELA1 1700000000 3 1 CORPO; printf "g=%s;\n" "$?"'
  assert_contem 'g=0;' "$FILHO_SAIDA" "gravacao: $FILHO_SAIDA"
  _filho 'CTX; dbx_state_cursor_carregar COLETAR; printf "e=%s cursor=%s\n" "$?" "$DBX_STATE_CURSOR_VALOR"'
  assert_contem 'e=0 cursor=CURSORSENTINELA1' "$FILHO_SAIDA" "carga com o duble BSD: $FILHO_SAIDA"
  assert_contem 'entrada f|/fotos/p/a.txt' "$FILHO_SAIDA" 'entrada entregue (etiqueta e path_lower)'
}

teste_leitor_limitado_e_trava_leem_com_stat_bsd() {
  local area
  area=$(_area)
  printf 'a\0b\0' >"$area/campos"
  dbx_freebsd_ativar
  _dbx_state_ler_limitado "$area/campos" 5
  assert_igual 0 $? 'leitor limitado le o arquivo regular'
  assert_igual 2 "${#_DBX_STATE_CAMPOS[@]}" 'dois campos'
  assert_igual '' "$(dbx_freebsd_erros | grep -v 'illegal option -- c')" 'o duble nao recusou nada alem do `-c`'
}

# ---------------------------------------------------------------------------
# Auditoria: nenhum caminho do produto monta /dev/fd/<variavel>
# ---------------------------------------------------------------------------

# _ocorrencias_de_dev_fd <diretorio...> — linhas de CODIGO (fora de comentario)
# que montam `/dev/fd/$<variavel>`.
_ocorrencias_de_dev_fd() {
  grep -rn '/dev/fd/\$' "$@" 2>/dev/null | grep -v ':[0-9]*:[[:space:]]*#'
}

teste_auditoria_distingue_codigo_de_comentario() {
  local amostra saida
  amostra=$(_area)
  printf '%s\n' '  # nota sobre /dev/fd/$fd' 'x="/dev/fd/$fd"' >"$amostra/a.sh"
  saida=$(_ocorrencias_de_dev_fd "$amostra")
  assert_contem 'a.sh:2:x="/dev/fd/$fd"' "$saida" 'a linha de codigo e achada'
  assert_nao_contem 'nota sobre' "$saida" 'o comentario nao conta'
}

teste_nenhum_caminho_do_produto_depende_de_dev_fd_variavel() {
  local saida
  saida=$(_ocorrencias_de_dev_fd "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$DBX_HARNESS_RAIZ/bin")
  assert_igual '' "$saida" 'RF-171(a): nada de /dev/fd/<n> no runtime'
}

harness_executar "$@"
