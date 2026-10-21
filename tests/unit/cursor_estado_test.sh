#!/usr/bin/env bash
# Testes do registro `cursor-*` em lib/state.sh (fase 7b, F-14; RF-111,
# RF-113(d), RF-117(e)(f); parecer do DBA, C1, C2, C4, C8, C10, C11).
#
# O ESTADO SO ACELERA. Cada caso prova a metade que cabe a lib/state: o registro
# que nao serve sai (e so ele, e nunca em simulacao), o leitor nunca le alem do
# formato nem abre o que nao e arquivo regular do usuario, e o retrato so chega
# a quem chama depois de o rodape conferir.
#
# Cada caso roda num `bash` proprio com lib/state carregada e com
# `XDG_STATE_HOME` e `TMPDIR` privados (`_filho`, como em retomada_estado_test).
#
# shellcheck disable=SC2016,SC2097,SC2098
# Justificativa: os roteiros dos processos filhos chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

CONTA='cred-0123456789abcdef0123456789abcdef'
ASSIN='list_folder;recursive=1;limit=100'
H64='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'

_area() {
  AREA=$(mktemp -d "$DBX_TESTES_TMP/cursor-estado.XXXXXX")
  mkdir -p "$AREA/xdg" "$AREA/tmp"
  ESTADO="$AREA/xdg/dbx"
}

_filho() {
  local roteiro=$1
  shift
  FILHO_SAIDA=$(XDG_STATE_HOME="$AREA/xdg" TMPDIR="$AREA/tmp" AREA="$AREA" RAIZ="$DBX_HARNESS_RAIZ" \
    CONTA="$CONTA" ASSIN="$ASSIN" H64="$H64" bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    CTX() { dbx_state_cursor_contexto "$CONTA" dbid:CONTA "/home/u/l" /Fotos "$ASSIN"; }
    CORPO() {
      printf "d\tid:p\t-\t-\t0\t-\t/Fotos/p\0/fotos/p\0"
      printf "f\tid:a\t0123456789a\t%s\t15\t-\t/Fotos/p/A.txt\0/fotos/p/a.txt\0" "$H64"
    }
    COLETAR() { printf "entrada %s|%s|%s|%s\n" "$3" "$4" "$5" "$2"; return "${FALHAR_ENTRADA:-0}"; }
    UMA() { printf "f\tid:a\t0123456789a\t%s\t15\t-\t/a.txt\0/a.txt\0" "$H64"; }
'"$roteiro" _ "$@" 2>&1 </dev/null)
  FILHO_ESTADO=$?
  : "$FILHO_ESTADO"
}

_gravar_valido() {
  _filho 'CTX || exit 90; dbx_state_cursor_gravar CURSORSENTINELA1 1700000000 3 2 CORPO; printf "g=%s;\n" "$?"'
  assert_contem 'g=0;' "$FILHO_SAIDA" "gravacao valida: $FILHO_SAIDA"
  local -a f=("$ESTADO"/cursor-*)
  REG=${f[0]}
  [[ -f $REG ]] || _harness_falhar 'registro nao criado'
}

teste_contexto_exige_cred_e_account_id() {
  _area
  _filho 'dbx_state_cursor_contexto "" dbid:X /l /r "$ASSIN"; printf "a=%s;\n" "$?"
dbx_state_cursor_contexto "$CONTA" "" /l /r "$ASSIN"; printf "b=%s;\n" "$?"
dbx_state_cursor_contexto "$CONTA" "conta sem prefixo" /l /r "$ASSIN"; printf "c=%s arq=[%s]\n" "$?" "$DBX_STATE_CURSOR_ARQUIVO"'
  local uso
  uso=$(dbx_errors_codigo_saida uso_invalido)
  assert_contem "a=$uso;" "$FILHO_SAIDA" 'sem cred-: sem contexto'
  assert_contem "b=$uso;" "$FILHO_SAIDA" 'sem account_id: sem contexto'
  assert_contem "c=$uso arq=[]" "$FILHO_SAIDA" 'account_id fora do formato: sem contexto'
  [[ -e $ESTADO ]] && _harness_falhar 'o contexto nao cria nada'
  return 0
}

teste_chave_por_conta_raizes_e_assinatura_com_nul() {
  _area
  _filho 'n() { dbx_state_cursor_contexto "$@" || exit 9; printf "%s\n" "${DBX_STATE_CURSOR_ARQUIVO##*/}"; }
n "$CONTA" dbid:A /l /Fotos "$ASSIN"
n "$CONTA" dbid:OUTRA /l /Fotos "$ASSIN"
n "$CONTA" dbid:A /l /fotos "$ASSIN"
n cred-ffffffffffffffffffffffffffffffff dbid:A /l /Fotos "$ASSIN"
n "$CONTA" dbid:A /l2 /Fotos "$ASSIN"
n "$CONTA" dbid:A /l /Outra "$ASSIN"
n "$CONTA" dbid:A /l /Fotos "list_folder;limit=50"
n "$CONTA" dbid:A $'"'"'a\nb'"'"' c "$ASSIN"
n "$CONTA" dbid:A a $'"'"'b\nc'"'"' "$ASSIN"'
  local -a l=()
  mapfile -t l <<<"$FILHO_SAIDA"
  assert_igual 9 "${#l[@]}" "nove chaves: $FILHO_SAIDA"
  [[ ${l[0]} =~ ^cursor-[0-9a-f]{32}$ ]] || _harness_falhar "nome por resumo: ${l[0]}"
  assert_igual "${l[0]}" "${l[1]}" 'o account_id fica no cabecalho, nao na chave (C2)'
  assert_igual "${l[0]}" "${l[2]}" 'remoto dobrado so no ASCII: mesma chave'
  assert_diferente "${l[0]}" "${l[3]}" 'outra credencial, outra chave'
  assert_diferente "${l[0]}" "${l[4]}" 'outra raiz local, outra chave'
  assert_diferente "${l[0]}" "${l[5]}" 'outra raiz remota, outra chave'
  assert_diferente "${l[0]}" "${l[6]}" 'outra assinatura, outra chave'
  assert_diferente "${l[7]}" "${l[8]}" 'separador NUL: os pares nao colidem'
}

teste_gravacao_e_carga_entregam_o_retrato_depois_do_rodape() {
  _area
  _gravar_valido
  assert_igual 600 "$(stat -c %a -- "$REG")" 'registro 0600'
  assert_igual 700 "$(stat -c %a -- "$ESTADO")" 'diretorio 0700'
  _filho 'CTX; dbx_state_cursor_carregar COLETAR; e=$?
printf "e=%s cursor=%s completa=%s incr=%s n=%s\n" "$e" "$DBX_STATE_CURSOR_VALOR" "$DBX_STATE_CURSOR_COMPLETA_EM" "$DBX_STATE_CURSOR_INCREMENTAIS_DESDE" "$DBX_STATE_CURSOR_N"'
  assert_contem 'e=0 cursor=CURSORSENTINELA1 completa=1700000000 incr=3 n=2' "$FILHO_SAIDA" "carga: $FILHO_SAIDA"
  assert_contem 'entrada d|id:p|/Fotos/p|/fotos/p' "$FILHO_SAIDA" 'pasta entregue'
  assert_contem "entrada f|id:a|/Fotos/p/A.txt|/fotos/p/a.txt" "$FILHO_SAIDA" 'arquivo entregue'
  local -a temporarios=("$ESTADO"/.cursor.*)
  [[ -e ${temporarios[0]} ]] && _harness_falhar 'temporario residual'
  return 0
}

teste_gravacao_recusa_cursor_fora_da_regex_e_teto() {
  _area
  _filho 'CTX
dbx_state_cursor_gravar "com espaco" 1 0 2 CORPO; printf "a=%s;\n" "$?"
printf -v grande "%8193s" ""; grande=${grande// /A}
dbx_state_cursor_gravar "$grande" 1 0 2 CORPO; printf "b=%s;\n" "$?"
dbx_state_cursor_gravar C1 1 0 1000001 CORPO; printf "c=%s;\n" "$?"'
  assert_contem 'a=1;' "$FILHO_SAIDA" 'cursor com espaco nao persiste'
  assert_contem 'b=1;' "$FILHO_SAIDA" 'cursor acima de 8 KiB nao persiste'
  assert_contem 'c=1;' "$FILHO_SAIDA" 'mais de 1.000.000 de entradas nao persiste'
  local -a f=("$ESTADO"/cursor-*)
  [[ -e ${f[0]} ]] && _harness_falhar 'nada gravado'
  return 0
}

_corromper() { # <caso> — sobre o registro valido REG
  local -a c=()
  mapfile -d '' -t c <"$REG"
  case $1 in
    vazio) : >"$REG" ;;
    truncado) head -c 120 -- "$REG" >"$AREA/t" && cat "$AREA/t" >"$REG" ;;
    sha) c[${#c[@]} - 1]=$H64 && printf '%s\0' "${c[@]}" >"$REG" ;;
    sem_rodape) unset 'c[${#c[@]}-1]' 'c[${#c[@]}-1]' && printf '%s\0' "${c[@]}" >"$REG" ;;
    lixo_depois) printf 'x' >>"$REG" ;;
    sem_nul) printf '%s' 'dbx-cursor sem nul' >"$REG" ;;
  esac
}

teste_registro_corrompido_e_descartado_e_apagado_so_fora_da_simulacao() {
  local caso
  for caso in vazio truncado sha sem_rodape lixo_depois sem_nul; do
    _area
    _gravar_valido
    _corromper "$caso"
    _filho 'CTX; dbx_state_cursor_carregar COLETAR nao; printf "e=%s; motivo=%s\n" "$?" "$DBX_STATE_MOTIVO"'
    assert_contem 'e=2;' "$FILHO_SAIDA" "$caso: descartado"
    assert_contem 'motivo=registro de listagem' "$FILHO_SAIDA" "$caso: motivo de uma linha"
    assert_nao_contem 'CURSORSENTINELA' "$FILHO_SAIDA" "$caso: o motivo nao cita o cursor"
    assert_arquivo_existe "$REG" "$caso: simulacao nao apaga (RF-117(a))"
    _filho 'CTX; dbx_state_cursor_carregar COLETAR; printf "e=%s cursor=[%s]\n" "$?" "$DBX_STATE_CURSOR_VALOR"'
    assert_contem 'e=2 cursor=[]' "$FILHO_SAIDA" "$caso: descartado, sem cabecalho publicado"
    assert_arquivo_ausente "$REG" "$caso: apagado"
  done
}

teste_rodape_e_conferido_antes_do_uso_mutante() {
  # Mutacao do rodape: um byte trocado no corpo com rodape antigo reprova.
  _area
  _gravar_valido
  local -a c=()
  mapfile -d '' -t c <"$REG"
  c[13]=/fotos/p/b.txt
  printf '%s\0' "${c[@]}" >"$REG"
  _filho 'CTX; dbx_state_cursor_carregar COLETAR; printf "e=%s motivo=%s\n" "$?" "$DBX_STATE_MOTIVO"'
  assert_contem 'e=2 motivo=registro de listagem com rodape de integridade divergente' "$FILHO_SAIDA" 'sha256 divergente'
}

teste_cabecalho_divergente_e_descartado() {
  local indice valor
  for indice in 0 1 2 3 4 5 6; do
    _area
    _gravar_valido
    local -a c=()
    mapfile -d '' -t c <"$REG"
    unset 'c[${#c[@]}-1]' 'c[${#c[@]}-1]'
    c=("${c[@]}")
    case $indice in
      0) valor=dbx-retomada ;;
      1) valor=2 ;;
      2) valor=cred-ffffffffffffffffffffffffffffffff ;;
      3) valor=dbid:OUTRA ;;
      4) valor='list_folder;outra' ;;
      5) valor=/fotos ;;
      6) valor=/home/u/outra ;;
    esac
    c[indice]=$valor
    printf '%s\0' "${c[@]}" >"$REG"
    local resumo
    resumo=$(sha256sum <"$REG")
    printf 'fim\0%s\0' "${resumo%% *}" >>"$REG"
    _filho 'CTX; dbx_state_cursor_carregar COLETAR; printf "e=%s;\n" "$?"'
    assert_contem 'e=2;' "$FILHO_SAIDA" "campo $indice divergente: descartado"
    assert_nao_contem 'entrada' "$FILHO_SAIDA" "campo $indice: nenhuma entrada entregue"
  done
}

teste_funcao_de_entrada_que_recusa_descarta() {
  _area
  _gravar_valido
  _filho 'CTX; FALHAR_ENTRADA=1 dbx_state_cursor_carregar COLETAR; printf "e=%s motivo=%s\n" "$?" "$DBX_STATE_MOTIVO"'
  assert_contem 'e=2 motivo=registro de listagem com caminho fora da raiz ou repetido' "$FILHO_SAIDA" 'recusa do chamador'
}

teste_intocavel_nao_e_lido_nem_apagado() {
  local caso
  for caso in fifo ligacao diretorio; do
    _area
    _gravar_valido
    rm -f -- "$REG"
    case $caso in
      fifo) mkfifo "$REG" ;;
      ligacao) printf 'alvo' >"$AREA/alvo" && ln -s "$AREA/alvo" "$REG" ;;
      diretorio) mkdir "$REG" ;;
    esac
    _filho 'CTX; dbx_state_cursor_carregar COLETAR; printf "e=%s;\n" "$?"
dbx_state_cursor_gravar C2 1 0 2 CORPO; printf "g=%s;\n" "$?"'
    assert_contem 'e=3;' "$FILHO_SAIDA" "$caso: intocavel"
    assert_contem 'g=1;' "$FILHO_SAIDA" "$caso: nao grava por cima"
    [[ -e $REG || -L $REG ]] || _harness_falhar "$caso: apagado"
  done
}

teste_vencido_sete_dias_cem_incrementais_e_relogio() {
  _area
  _filho 'a=1700000000
dbx_state_cursor_vencido $((a - 604800 - 60)) 0 $a; printf "a=%s;\n" "$?"
dbx_state_cursor_vencido $((a - 604800 + 3600)) 0 $a; printf "b=%s;\n" "$?"
dbx_state_cursor_vencido $((a + 301)) 0 $a; printf "c=%s;\n" "$?"
dbx_state_cursor_vencido $((a + 299)) 0 $a; printf "d=%s;\n" "$?"
dbx_state_cursor_vencido $a 100 $a; printf "e=%s;\n" "$?"
dbx_state_cursor_vencido $a 99 $a; printf "f=%s;\n" "$?"
dbx_state_cursor_vencido x 0 $a; printf "g=%s;\n" "$?"'
  assert_contem 'a=0;' "$FILHO_SAIDA" '7 dias e 1 minuto: vencido'
  assert_contem 'b=1;' "$FILHO_SAIDA" '6 dias e 23 h: valido'
  assert_contem 'c=0;' "$FILHO_SAIDA" 'relogio voltou mais de 5 min: vencido'
  assert_contem 'd=1;' "$FILHO_SAIDA" 'menos de 5 min: valido'
  assert_contem 'e=0;' "$FILHO_SAIDA" '100 incrementais: vencido'
  assert_contem 'f=1;' "$FILHO_SAIDA" '99: valido'
  assert_contem 'g=0;' "$FILHO_SAIDA" 'carimbo malformado: em duvida, completa'
}

teste_listagem_le_so_o_cabecalho_e_nao_cria_nada() {
  _area
  _filho 'dbx_state_cursor_listar; printf "n=%s\n" "${#DBX_STATE_CURSORES_ARQUIVO[@]}"'
  assert_contem 'n=0' "$FILHO_SAIDA" 'sem diretorio: nenhuma entrada'
  [[ -e $ESTADO ]] && _harness_falhar 'a listagem nao cria o diretorio'
  _gravar_valido
  printf 'lixo' >"$ESTADO/cursor-ffffffffffffffffffffffffffffffff"
  _filho 'dbx_state_cursor_listar
for i in "${!DBX_STATE_CURSORES_ARQUIVO[@]}"; do
  printf "%s|%s|%s|%s\n" "${DBX_STATE_CURSORES_ESTADO[i]}" "${DBX_STATE_CURSORES_REMOTO[i]}" "${DBX_STATE_CURSORES_LOCAL[i]}" "${DBX_STATE_CURSORES_ENTRADAS[i]}"
done'
  assert_contem 'vencido|/Fotos|/home/u/l|2' "$FILHO_SAIDA" 'completa de 2023: vencido'
  assert_contem 'ilegivel|||0' "$FILHO_SAIDA" 'lixo: ilegivel'
  assert_nao_contem 'CURSORSENTINELA' "$FILHO_SAIDA" 'o cursor nunca sai da listagem (C10)'
  assert_arquivo_existe "$ESTADO/cursor-ffffffffffffffffffffffffffffffff" 'nada removido'
}

teste_poda_oito_dias_e_teto_cem_so_cursor() {
  local i agora nome
  printf -v agora '%(%s)T' -1
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  for ((i = 0; i < 100; i++)); do
    printf -v nome '%s/cursor-%032x' "$ESTADO" "$i"
    printf 'x' >"$nome"
    touch -d "@$((agora - 3600 - i))" "$nome"
  done
  printf 'x' >"$ESTADO/cursor-velho"
  touch -d "@$((agora - 9 * 86400))" "$ESTADO/cursor-velho"
  printf 'x' >"$ESTADO/cursor-7dias"
  touch -d "@$((agora - 7 * 86400))" "$ESTADO/cursor-7dias"
  for i in memoria-a upload-a retomada-a trava-a; do
    printf 'x' >"$ESTADO/$i"
    touch -d "@$((agora - 30 * 86400))" "$ESTADO/$i"
  done
  _gravar_valido
  local -a restantes=("$ESTADO"/cursor-*)
  assert_igual 100 "${#restantes[@]}" 'teto de 100, contando o corrente'
  assert_arquivo_ausente "$ESTADO/cursor-velho" 'mais de 8 dias sai'
  assert_arquivo_existe "$REG" 'o corrente nunca sai'
  for i in memoria-a upload-a retomada-a trava-a; do
    assert_arquivo_existe "$ESTADO/$i" "$i nunca podado"
  done
}

teste_qa_b7b_01_raiz_remota_vazia_e_chave_valida() {
  # A raiz `/` da credencial chega como "" (caminho da API). Ela e uma raiz
  # valida: o contexto existe, a chave difere da de qualquer subpasta e o
  # registro faz a volta inteira.
  _area
  _filho 'dbx_state_cursor_contexto "$CONTA" dbid:CONTA /home/u/l "" "$ASSIN"; printf "c=%s;\n" "$?"
printf "arq=%s\n" "${DBX_STATE_CURSOR_ARQUIVO##*/}"
dbx_state_cursor_gravar CURSORSENTINELA1 1700000000 0 1 UMA; printf "g=%s;\n" "$?"
dbx_state_cursor_carregar COLETAR; printf "e=%s; remoto=[%s]\n" "$?" "$DBX_STATE_CURSOR_REMOTO"
dbx_state_cursor_contexto "$CONTA" dbid:CONTA /home/u/l /x "$ASSIN"; printf "outra=%s\n" "${DBX_STATE_CURSOR_ARQUIVO##*/}"'
  assert_contem 'c=0;' "$FILHO_SAIDA" "raiz vazia: contexto valido (QA-B7B-01): $FILHO_SAIDA"
  assert_contem 'g=0;' "$FILHO_SAIDA" 'grava'
  assert_contem 'e=0; remoto=[]' "$FILHO_SAIDA" 'carrega, com o remoto vazio reconferido'
  assert_contem 'entrada f|id:a|/a.txt|/a.txt' "$FILHO_SAIDA" 'retrato entregue'
  local a b
  a=$(grep '^arq=' <<<"$FILHO_SAIDA")
  b=$(grep '^outra=' <<<"$FILHO_SAIDA")
  [[ ${a#arq=} =~ ^cursor-[0-9a-f]{32}$ && ${a#arq=} != "${b#outra=}" ]] || _harness_falhar "chaves: $a $b"
  _filho 'dbx_state_cursor_listar; printf "%s|%s\n" "${DBX_STATE_CURSORES_ESTADO[0]}" "${DBX_STATE_CURSORES_REMOTO[0]}"'
  assert_contem 'vencido|' "$FILHO_SAIDA" 'listagem le o cabecalho com remoto vazio'
}

harness_executar "$@"
