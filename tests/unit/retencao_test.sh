#!/usr/bin/env bash
# Testes diretos de lib/retencao.sh e do casamento de nome avulso de
# lib/filtro.sh (fase 6, F-10; RF-93(e)(f)(g)(h)(j), RF-95, RF-97(b); TC-RTA-05..07,
# TC-RTP-01..12, TC-RTG-03..05 e TC-RTG-09 por unidade).
#
# `lib/retencao` e puro: sem rede, sem disco, sem estado e sem relogio. O
# "agora" e um argumento, entao a politica de `--dias` e provada aqui com o
# relogio fixado (TC-RTP-07, "duble do relogio"). Os casos ponta a ponta
# (`reter_test`) so provam a ligacao com a listagem e o `delete_v2`.
#
# Mutantes: copias de lib/retencao.sh com uma linha marcada removida precisam
# reprovar o caso que as protege (minimo de 1, guarda do primeiro da ordem).
#
# shellcheck disable=SC2016,SC1003,SC2031
# Justificativa: padroes com `$(...)`, crase e `$HOME` precisam chegar literais;
# os casos rodam em subshell do arcabouco (SC2031 e falso positivo).
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/filtro.sh"
. "$DBX_HARNESS_RAIZ/lib/retencao.sh"

USO=$(dbx_errors_codigo_saida uso_invalido)
readonly USO

# DIV-167: rev e id de quem fica, alheios ao item que sai, para as chamadas da
# guarda que provam OUTRA condicao (os vetores precisam existir no processo).
_ids_teste() {
  # shellcheck disable=SC2034  # lidos pela guarda por nome (nameref)
  declare -ga _rv=(0000000009f) _iv=(id:outro)
}
export -f _ids_teste
_ids_teste

# Agora fixado: 2026-10-20T12:00:00Z.
readonly AGORA=1792497600

# ---------------------------------------------------------------------------
# TC-RTA-05, TC-RTA-06 — --manter e --dias
# ---------------------------------------------------------------------------

teste_rta05_manter_aceita_1_a_999999_e_recusa_o_resto() {
  local valor
  for valor in 1 7 999999; do
    dbx_retencao_validar_manter --manter "$valor" || _harness_falhar "--manter $valor recusado: $DBX_RETENCAO_MOTIVO"
    assert_igual "$valor" "$DBX_RETENCAO_VALOR" "valor de --manter $valor"
  done
  dbx_retencao_validar_manter --manter 0
  assert_igual "$USO" "$?" '--manter 0'
  assert_contem '--manter 0 apagaria todos; o minimo e 1' "$DBX_RETENCAO_MOTIVO" 'mensagem do minimo'
  for valor in -1 +1 01 1.5 abc '' ' 1' 1000000 $'1\n'; do
    dbx_retencao_validar_manter --keep "$valor"
    assert_igual "$USO" "$?" "--keep [$valor] recusado"
    assert_contem '--keep' "$DBX_RETENCAO_MOTIVO" 'a recusa nomeia a opcao como digitada'
  done
}

teste_rta06_dias_aceita_1_a_36500_e_recusa_o_resto() {
  local valor
  for valor in 1 7 36500; do
    dbx_retencao_validar_dias --dias "$valor" || _harness_falhar "--dias $valor recusado"
    assert_igual "$valor" "$DBX_RETENCAO_VALOR" "valor de --dias $valor"
  done
  for valor in 0 36501 01 7d '' -1 1.5 99999; do
    dbx_retencao_validar_dias --days "$valor"
    assert_igual "$USO" "$?" "--days [$valor] recusado"
  done
}

# ---------------------------------------------------------------------------
# RF-95(b) — carimbo de server_modified
# ---------------------------------------------------------------------------

teste_rtp05_carimbo_valido_so_na_forma_exata_e_com_data_existente() {
  local c
  for c in 2026-10-20T10:00:00Z 2024-02-29T23:59:59Z 1970-01-01T00:00:00Z; do
    dbx_retencao_carimbo_valido "$c" || _harness_falhar "carimbo valido recusado: $c"
  done
  for c in '' 2026-10-20T10:00:00.5Z 2026-10-20T10:00:00+03:00 2026-02-30T00:00:00Z \
    2025-02-29T00:00:00Z 2026-13-01T00:00:00Z 2026-10-20T24:00:00Z 2026-10-20T10:60:00Z \
    '2026-10-20 10:00:00Z' 2026-10-20T10:00:00z 2026-10-20 $'2026-10-20T10:00:00Z\n' \
    ' 2026-10-20T10:00:00Z'; do
    dbx_retencao_carimbo_valido "$c" && _harness_falhar "carimbo invalido aceito: [$c]"
  done
  return 0
}

# ---------------------------------------------------------------------------
# DIV-134 — data HTTP do cabecalho Date
# ---------------------------------------------------------------------------

teste_div134_data_http_vira_segundos_desde_1970() {
  dbx_retencao_epoca_http 'Tue, 20 Oct 2026 12:00:00 GMT' || _harness_falhar 'IMF-fixdate recusada'
  assert_igual "$AGORA" "$DBX_RETENCAO_EPOCA" 'segundos de 2026-10-20T12:00:00Z'
  dbx_retencao_epoca_http 'Thu, 01 Jan 1970 00:00:00 GMT' || _harness_falhar 'epoca zero'
  assert_igual 0 "$DBX_RETENCAO_EPOCA" 'epoca zero'
  dbx_retencao_epoca_http 'Thu, 29 Feb 2024 23:59:59 GMT' || _harness_falhar 'bissexto'
  dbx_filtro_carimbo_de_epoca "$DBX_RETENCAO_EPOCA"
  assert_igual 2024-02-29T23:59:59Z "$DBX_FILTRO_CARIMBO" 'volta e ida pelo carimbo de lib/filtro'
  local d
  for d in '' 'Tue, 20 Oct 2026 12:00:00' 'Tue, 20 Oct 2026 12:00:00 UTC' \
    'Tuesday, 20-Oct-26 12:00:00 GMT' 'Tue Oct 20 12:00:00 2026' 'Tue, 30 Feb 2026 12:00:00 GMT' \
    'Tue, 20 Xyz 2026 12:00:00 GMT' 'Tue, 20 Oct 2026 25:00:00 GMT' $'Tue, 20 Oct 2026 12:00:00 GMT\n'; do
    dbx_retencao_epoca_http "$d" && _harness_falhar "data HTTP invalida aceita: [$d]"
  done
  return 0
}

teste_div134_lib_http_expoe_o_cabecalho_date() {
  (
    . "$DBX_HARNESS_RAIZ/lib/http.sh"
    local area
    area=$(mktemp -d "$DBX_TESTES_TMP/cab.XXXXXX")
    printf 'HTTP/1.1 200 OK\r\nX-Dropbox-Request-Id: abc\r\ndate:  Tue, 20 Oct 2026 12:00:00 GMT \r\nRetry-After: 3\r\n\r\n' >"$area/c"
    _dbx_http_correlacao_de "$area/c"
    assert_igual 'Tue, 20 Oct 2026 12:00:00 GMT' "$DBX_HTTP_DATA" 'Date aparado, sem CR'
    assert_igual abc "$DBX_HTTP_CORRELACAO" 'correlacao intacta'
    assert_igual 3 "$DBX_HTTP_RETRY_AFTER" 'Retry-After intacto'
    printf 'HTTP/1.1 200 OK\r\n\r\n' >"$area/c"
    _dbx_http_correlacao_de "$area/c"
    assert_igual '' "$DBX_HTTP_DATA" 'resposta sem Date nao herda o da anterior'
  )
}

# ---------------------------------------------------------------------------
# TC-RTA-07 — o --padrao como glob de nome avulso (lib/filtro, RNF-36)
# ---------------------------------------------------------------------------

_casa() { # <padrao> <nome> — sim|nao
  dbx_filtro_nome_preparar --padrao "$1" || _harness_falhar "padrao recusado: [$1] $DBX_FILTRO_MOTIVO"
  if dbx_filtro_nome_casa "$2"; then printf sim; else printf nao; fi
}

teste_rta07_padrao_com_barra_ou_malformado_e_recusado_citado() {
  local p
  for p in 'a/*.tar' '*/' '/x' 'a\/b' '!x' '[' '[]' '[z-a]' '[[:alpha:]]' 'x\' $'a\x01b' $'a\nb' ''; do
    dbx_filtro_nome_preparar --padrao "$p"
    assert_igual "$USO" "$?" "padrao [$p] recusado"
    assert_contem '--padrao' "$DBX_FILTRO_MOTIVO" 'a recusa nomeia a opcao'
    [[ $DBX_FILTRO_MOTIVO == *[$'\001'-$'\037']* ]] && _harness_falhar 'byte cru na recusa' "$DBX_FILTRO_MOTIVO"
  done
  local longo
  printf -v longo '%1025s' ''
  longo=${longo// /a}
  dbx_filtro_nome_preparar --pattern "$longo"
  assert_igual "$USO" "$?" '1025 bytes'
  dbx_filtro_nome_preparar --pattern 'a/b'
  assert_contem 'o padrao casa so o nome' "$DBX_FILTRO_MOTIVO" 'motivo proprio da barra'
  for p in '[]a]*' '**.tar' '\*' 'db-*.tar.gz' '?' "${longo:1}"; do
    dbx_filtro_nome_preparar --padrao "$p" || _harness_falhar "padrao valido recusado: [$p] $DBX_FILTRO_MOTIVO"
  done
  return 0
}

teste_rta07_casa_o_nome_inteiro_sem_caixa_e_sem_normalizacao() {
  assert_igual sim "$(_casa 'db-*.tar.gz' db-2026.tar.gz)" 'curinga'
  assert_igual nao "$(_casa 'db-*.tar.gz' db-2026.tar.gz.bak)" 'ancorado no fim'
  assert_igual nao "$(_casa 'db-*.tar.gz' xdb-2026.tar.gz)" 'ancorado no inicio'
  assert_igual sim "$(_casa '*.TAR.GZ' db.tar.gz)" 'sem caixa'
  assert_igual sim "$(_casa '**.tar' a.tar)" '** sem barra vale *'
  assert_igual sim "$(_casa ']a' ']a')" '] literal'
  assert_igual sim "$(_casa '[]a]*' ']x')" '] logo depois de ['
  assert_igual sim "$(_casa '\*' '*')" 'escape'
  assert_igual nao "$(_casa '\*' 'a')" 'escape e literal'
  assert_igual nao "$(_casa '*' 'a/b')" 'nome com barra nunca casa'
  assert_igual nao "$(_casa '*' '')" 'nome vazio nunca casa'
  assert_igual sim "$(_casa $'\xc3\x89*' $'\xc3\xa9a.tar')" 'E acentuado sem caixa (C.UTF-8)'
  assert_igual sim "$(LC_ALL=C _casa $'\xc3\x89*' $'\xc3\xa9a.tar')" 'inclusive sob LC_ALL=C do processo'
  assert_igual nao "$(_casa $'e\xcc\x81*' $'\xc3\xa9a.tar')" 'NFD nao casa NFC'
}

teste_rta09_padrao_e_dado_nunca_codigo() {
  local p area
  area=$(mktemp -d "$DBX_TESTES_TMP/inj.XXXXXX")
  for p in '$(touch S)' '`touch S`' ';touch S' '$HOME' '~'; do
    (cd "$area" && dbx_filtro_nome_preparar --padrao "$p" && dbx_filtro_nome_casa "$p") ||
      _harness_falhar "o padrao [$p] nao casou a si mesmo como texto"
    (cd "$area" && dbx_filtro_nome_preparar --padrao "$p" && dbx_filtro_nome_casa x) &&
      _harness_falhar "o padrao [$p] casou outro texto"
  done
  assert_arquivo_ausente "$area/S" 'nada executado'
}

teste_rtc07_padrao_amplo_e_o_sem_caractere_literal() {
  local p
  for p in '*' '?*' '**' '[a-z]*' '???'; do
    dbx_filtro_nome_preparar --padrao "$p" || _harness_falhar "recusado [$p]"
    assert_igual sim "$DBX_FILTRO_AMPLO" "amplo: [$p]"
  done
  for p in 'db-*.tar' '\*' '*.gz' 'a'; do
    dbx_filtro_nome_preparar --padrao "$p" || _harness_falhar "recusado [$p]"
    assert_igual nao "$DBX_FILTRO_AMPLO" "nao amplo: [$p]"
  done
}

teste_rta07_nome_avulso_nao_mexe_nos_filtros_de_caminho() {
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir '*.log' || _harness_falhar 'excluir'
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'padrao'
  assert_igual 1 "${#DBX_FILTRO_PADROES[@]}" 'os filtros de caminho ficam como estavam'
  dbx_filtro_classificar a.log nao && _harness_falhar 'o --excluir continua valendo'
  return 0
}

# ---------------------------------------------------------------------------
# TC-RTP — a politica pura
# ---------------------------------------------------------------------------

# _planejar <politica> <valor> <agora> <sm|nome>... — imprime "nome:acao" na
# ordem do plano e o minimo no fim.
_planejar() {
  local politica=$1 valor=$2 agora=$3 item i
  shift 3
  local -a sm=() chave=() pl=() nome=()
  for item in "$@"; do
    sm+=("${item%%|*}")
    nome+=("${item#*|}")
    dbx_filtro_chave "${item#*|}"
    chave+=("$DBX_FILTRO_CHAVE")
    pl+=("/b/$DBX_FILTRO_CHAVE")
  done
  dbx_retencao_planejar "$politica" "$valor" "$agora" sm chave pl || {
    printf 'FALHOU'
    return 0
  }
  for i in "${DBX_RETENCAO_ORDEM[@]}"; do
    printf '%s:%s ' "${nome[i]}" "${DBX_RETENCAO_ACAO[i]}"
  done
  printf 'minimo=%s' "$DBX_RETENCAO_MINIMO"
}

teste_rtp01_manter_dois_dos_cinco_mais_novos() {
  assert_igual 'e:fica d:fica c:sai b:sai a:sai minimo=nao' \
    "$(_planejar manter 2 "$AGORA" 2026-10-01T00:00:00Z\|a 2026-10-02T00:00:00Z\|b \
      2026-10-03T00:00:00Z\|c 2026-10-04T00:00:00Z\|d 2026-10-05T00:00:00Z\|e)" 'cinco, manter 2'
  local -a sm=(2026-10-01T00:00:00Z 2026-10-05T00:00:00Z 2026-10-03T00:00:00Z) chave=(a e c) pl=(/b/a /b/e /b/c)
  dbx_retencao_planejar manter 2 "$AGORA" sm chave pl || _harness_falhar 'planejar'
  assert_igual 2 "$DBX_RETENCAO_FICAM" 'ficam'
  assert_igual 1 "$DBX_RETENCAO_SAEM" 'saem'
  assert_igual '1 2 0' "${DBX_RETENCAO_ORDEM[*]}" 'ordem do mais novo ao mais velho'
}

teste_rtp02_ordem_de_entrada_nao_muda_o_plano() {
  local a b
  a=$(_planejar manter 2 "$AGORA" 2026-10-03T00:00:00Z\|c 2026-10-05T00:00:00Z\|e 2026-10-01T00:00:00Z\|a \
    2026-10-04T00:00:00Z\|d 2026-10-02T00:00:00Z\|b)
  b=$(_planejar manter 2 "$AGORA" 2026-10-01T00:00:00Z\|a 2026-10-02T00:00:00Z\|b 2026-10-03T00:00:00Z\|c \
    2026-10-04T00:00:00Z\|d 2026-10-05T00:00:00Z\|e)
  assert_igual "$b" "$a" 'mesmo plano em qualquer ordem'
}

teste_rtp03_empate_fica_antes_o_maior_nome_sem_caixa() {
  assert_igual 'b-2026-10-20:fica B-2026-10-19:sai minimo=nao' \
    "$(_planejar manter 1 "$AGORA" 2026-10-20T00:00:00Z\|B-2026-10-19 2026-10-20T00:00:00Z\|b-2026-10-20)" \
    'empate de server_modified: maior nome sem caixa'
  # Chaves iguais (nomes que so diferem fora da dobra nao existem no ASCII;
  # aqui a mesma chave em dois caminhos): bytes de path_lower, decrescente.
  local -a sm=(2026-10-20T00:00:00Z 2026-10-20T00:00:00Z) chave=(x x) pl=(/b/x1 /b/x2)
  dbx_retencao_planejar manter 1 "$AGORA" sm chave pl || _harness_falhar 'planejar'
  assert_igual '1 0' "${DBX_RETENCAO_ORDEM[*]}" 'desempate pelos bytes de path_lower'
}

teste_rtp05_carimbo_invalido_derruba_o_plano() {
  local -a sm=(2026-10-20T00:00:00Z 2026-02-30T00:00:00Z) chave=(a b) pl=(/b/a /b/b)
  dbx_retencao_planejar manter 1 "$AGORA" sm chave pl && _harness_falhar 'plano com carimbo invalido'
  assert_contem 'server_modified' "$DBX_RETENCAO_MOTIVO" 'motivo'
  return 0
}

teste_rtp06_manter_maior_ou_igual_aos_candidatos_nada_sai() {
  assert_igual 'b:fica a:fica minimo=nao' \
    "$(_planejar manter 5 "$AGORA" 2026-10-01T00:00:00Z\|a 2026-10-02T00:00:00Z\|b)" 'manter 5 com 2'
  assert_igual 'b:fica a:fica minimo=nao' \
    "$(_planejar manter 2 "$AGORA" 2026-10-01T00:00:00Z\|a 2026-10-02T00:00:00Z\|b)" 'manter 2 com 2'
}

teste_rtp07_dias_corte_inclusivo_ao_segundo() {
  # agora 2026-10-20T12:00:00Z, --dias 7: corte 2026-10-13T12:00:00Z.
  assert_igual 'c:fica b:fica a:sai minimo=nao' \
    "$(_planejar dias 7 "$AGORA" 2026-10-13T11:59:59Z\|a 2026-10-13T12:00:00Z\|b 2026-10-20T11:00:00Z\|c)" \
    'igual ao corte fica, corte menos 1 s sai'
  local -a sm=(2026-10-13T12:00:00Z) chave=(a) pl=(/b/a)
  dbx_retencao_planejar dias 7 "$AGORA" sm chave pl || _harness_falhar 'planejar'
  assert_igual 2026-10-13T12:00:00Z "$DBX_RETENCAO_CORTE" 'corte publicado'
  assert_igual 2026-10-20T12:00:00Z "$DBX_RETENCAO_AGORA" 'agora publicado'
  dbx_retencao_planejar dias 36500 "$AGORA" sm chave pl || _harness_falhar '--dias 36500 com corte antes de 1970'
  assert_igual 1926-11-14T12:00:00Z "$DBX_RETENCAO_CORTE" 'corte anterior a 1970'
  assert_igual fica "${DBX_RETENCAO_ACAO[0]}" 'dentro do corte'
}

teste_rtp08_dias_com_todos_velhos_mantem_o_mais_novo() {
  assert_igual 'c:fica b:sai a:sai minimo=sim' \
    "$(_planejar dias 1 "$AGORA" 2026-01-01T00:00:00Z\|a 2026-01-02T00:00:00Z\|b 2026-01-03T00:00:00Z\|c)" \
    'so o mais novo fica, pelo minimo'
}

teste_rtp09_dias_com_todos_dentro_e_futuro_fica() {
  assert_igual 'b:fica a:fica minimo=nao' \
    "$(_planejar dias 30 "$AGORA" 2026-10-19T00:00:00Z\|a 2027-01-01T00:00:00Z\|b)" 'todos dentro, futuro fica'
}

teste_rtp10_um_so_candidato_nunca_sai() {
  assert_igual 'a:fica minimo=nao' "$(_planejar manter 1 "$AGORA" 2026-10-01T00:00:00Z\|a)" 'manter 1'
  assert_igual 'a:fica minimo=sim' "$(_planejar dias 1 "$AGORA" 2001-10-01T00:00:00Z\|a)" 'dias 1, antigo'
}

teste_rtp11_zero_candidatos_plano_vazio() {
  local -a sm=() chave=() pl=()
  dbx_retencao_planejar manter 1 "$AGORA" sm chave pl || _harness_falhar 'plano vazio falhou'
  assert_igual 0 "${#DBX_RETENCAO_ORDEM[@]}" 'nada na ordem'
  assert_igual 0 "$DBX_RETENCAO_FICAM" 'ficam 0'
  assert_igual 0 "$DBX_RETENCAO_SAEM" 'saem 0'
  assert_igual nao "$DBX_RETENCAO_MINIMO" 'sem minimo'
}

# _lib_mutante <marca> — diretorio com lib/errors, path, filtro e uma copia de
# lib/retencao sem as linhas marcadas `MUTACAO:<marca>`.
_lib_mutante() {
  local dir arquivo
  dir=$(mktemp -d "$DBX_TESTES_TMP/lib.XXXXXX")
  for arquivo in errors path filtro; do
    cp "$DBX_HARNESS_RAIZ/lib/$arquivo.sh" "$dir/"
  done
  grep -v "MUTACAO:$1\$" "$DBX_HARNESS_RAIZ/lib/retencao.sh" >"$dir/retencao.sh"
  cmp -s "$dir/retencao.sh" "$DBX_HARNESS_RAIZ/lib/retencao.sh" && _harness_falhar "a marca MUTACAO:$1 nao existe na lib"
  printf '%s' "$dir"
}

# _lib_mutante_troca <marca> <sed> — como `_lib_mutante`, trocando a linha.
_lib_mutante_troca() {
  local dir arquivo
  dir=$(mktemp -d "$DBX_TESTES_TMP/lib.XXXXXX")
  for arquivo in errors path filtro; do
    cp "$DBX_HARNESS_RAIZ/lib/$arquivo.sh" "$dir/"
  done
  sed -e "$2" "$DBX_HARNESS_RAIZ/lib/retencao.sh" >"$dir/retencao.sh"
  cmp -s "$dir/retencao.sh" "$DBX_HARNESS_RAIZ/lib/retencao.sh" && _harness_falhar "a marca MUTACAO:$1 nao existe na lib"
  printf '%s' "$dir"
}

# _em_processo <dir_da_lib> <funcao> — a funcao (exportada) num bash novo que
# carrega so a lib do diretorio: nada da lib ja carregada neste processo vale.
_em_processo() {
  AGORA_T=$AGORA bash -c '. "$1/retencao.sh" || exit 90; _ids_teste; "$2"' _ "$1" "$2"
}

# _propriedade_corpo — 0 quando as invariantes de RF-95(e) valem em 200
# listagens geradas (1 a 50 candidatos, com empates, as duas politicas).
_propriedade_corpo() {
  (
    RANDOM=4242
    local rodada n i politica valor ficam saem primeiro dia
    local -a sm chave pl
    for ((rodada = 0; rodada < 200; rodada++)); do
      n=$((RANDOM % 50 + 1))
      sm=() chave=() pl=()
      for ((i = 0; i < n; i++)); do
        dia=$((RANDOM % 9 + 1))
        sm+=("2026-10-0${dia}T00:00:00Z")
        chave+=("n$((RANDOM % 7))")
        pl+=("/b/p$i")
      done
      if ((RANDOM % 2)); then politica=manter valor=$((RANDOM % 60 + 1)); else politica=dias valor=$((RANDOM % 30 + 1)); fi
      dbx_retencao_planejar "$politica" "$valor" "$AGORA_T" sm chave pl || exit 1
      [[ ${#DBX_RETENCAO_ORDEM[@]} -eq $n ]] || exit 2
      ficam=0 saem=0
      for i in "${DBX_RETENCAO_ORDEM[@]}"; do
        case ${DBX_RETENCAO_ACAO[i]} in fica) ficam=$((ficam + 1)) ;; sai) saem=$((saem + 1)) ;; *) exit 3 ;; esac
      done
      ((ficam + saem == n)) || exit 4
      ((ficam >= 1)) || exit 5
      primeiro=${DBX_RETENCAO_ORDEM[0]}
      [[ ${DBX_RETENCAO_ACAO[primeiro]} == fica ]] || exit 6
      if [[ $politica == manter ]]; then
        ((ficam == (valor < n ? valor : n))) || exit 7
      fi
      ((ficam == DBX_RETENCAO_FICAM && saem == DBX_RETENCAO_SAEM)) || exit 8
      # A ordem e decrescente por (server_modified, chave, path_lower).
      for ((i = 1; i < n; i++)); do
        local a=${DBX_RETENCAO_ORDEM[i - 1]} b=${DBX_RETENCAO_ORDEM[i]}
        local LC_ALL=C
        [[ ${sm[a]} > ${sm[b]} || (${sm[a]} == "${sm[b]}" && (${chave[a]} > ${chave[b]} ||
          (${chave[a]} == "${chave[b]}" && ${pl[a]} > ${pl[b]}))) ]] || exit 9
      done
    done
    exit 0
  )
}

export -f _propriedade_corpo

teste_rtp12_propriedade_sobre_listagens_geradas() {
  _em_processo "$DBX_HARNESS_RAIZ/lib" _propriedade_corpo
  assert_igual 0 "$?" 'invariantes da politica'
}

teste_rtp12_mutante_sem_o_minimo_reprova() {
  local dir
  dir=$(_lib_mutante minimo)
  _em_processo "$dir" _propriedade_corpo
  assert_igual 5 "$?" 'o mutante sem o minimo de 1 reprova a propriedade (ficam 0)'
}

# ---------------------------------------------------------------------------
# TC-RTG-03..05, TC-RTG-09 — a guarda por item, injetada direto
# ---------------------------------------------------------------------------

_guarda() { # <tag> <path_lower> <name> <pasta> <raiz> <acao> <e_primeiro> — sim|nao
  # DIV-162: a guarda exige a lista de quem fica; aqui, um caminho alheio.
  local -a _fica_outro=(/outra/fica.bin)
  if dbx_retencao_guarda "$@" _fica_outro 0000000001a id:sai _rv _iv; then printf sim; else printf nao; fi
}

teste_rtg03_guarda_recusa_item_incoerente() {
  dbx_filtro_nome_preparar --padrao 'db-*.tar' || _harness_falhar 'padrao'
  assert_igual sim "$(_guarda file /bk/db-1.tar db-1.tar /bk / sai nao)" 'item coerente passa'
  assert_igual sim "$(_guarda file /bk/db-1.tar DB-1.TAR /Bk /BK sai nao)" 'caixa ASCII dobrada'
  assert_igual nao "$(_guarda folder /bk/db-1.tar db-1.tar /bk / sai nao)" 'pasta'
  assert_igual nao "$(_guarda deleted /bk/db-1.tar db-1.tar /bk / sai nao)" 'apagado'
  assert_igual nao "$(_guarda '' /bk/db-1.tar db-1.tar /bk / sai nao)" 'sem tag'
  assert_igual nao "$(_guarda file /bk/sub/db-1.tar db-1.tar /bk / sai nao)" 'neto'
  assert_igual nao "$(_guarda file /bkx/db-1.tar db-1.tar /bk / sai nao)" 'irma'
  assert_igual nao "$(_guarda file /outra/db-1.tar db-1.tar /bk / sai nao)" 'outra arvore'
  assert_igual nao "$(_guarda file db-1.tar db-1.tar '' / sai nao)" 'relativo'
  assert_igual nao "$(_guarda file '' db-1.tar /bk / sai nao)" 'sem path_lower'
  assert_igual nao "$(_guarda file /bk/nota.txt nota.txt /bk / sai nao)" 'fora do padrao'
  assert_igual nao "$(_guarda file /bk/db-1.tar db-1.tar /bk /outra sai nao)" 'fora da raiz'
  assert_igual nao "$(_guarda file /bk/db-1.tar db-1.tar /bk / fica nao)" 'item que fica'
  assert_igual nao "$(_guarda file /bk/db-1.tar db-1.tar /bk / sai sim)" 'o primeiro da ordem'
  assert_igual nao "$(_guarda file /bk/../db-1.tar db-1.tar /bk / sai nao)" 'componente ..'
  assert_igual nao "$(_guarda file $'/bk/db-1.tar\n' $'db-1.tar\n' /bk / sai nao)" 'nao casa o padrao'
  assert_igual sim "$(_guarda file /db-1.tar db-1.tar '' / sai nao)" 'a raiz da conta como pasta'
}

teste_rtg04_fora_do_ascii_a_pasta_falha_fechada() {
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'padrao'
  assert_igual sim "$(_guarda file $'/b\xc3\xa4ck/a.tar' a.tar $'/B\xc3\xa4ck' / sai nao)" 'so ASCII difere'
  assert_igual nao "$(_guarda file $'/b\xc3\xa4ck/a.tar' a.tar $'/B\xc3\x84CK' / sai nao)" \
    'letra fora do ASCII com dobra diferente: falha fechada'
}

teste_rtg05_name_tem_de_ser_o_ultimo_componente_pela_chave() {
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'padrao'
  assert_igual nao "$(_guarda file /bk/a.tar b.tar /bk / sai nao)" 'name diferente'
  assert_igual sim "$(_guarda file $'/bk/\xc3\xa9.tar' $'\xc3\x89.TAR' /bk / sai nao)" 'mesma chave sem caixa'
}

# _guarda_do_primeiro — 0 quando a guarda recusa o primeiro da ordem.
_guarda_do_primeiro() {
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  # shellcheck disable=SC2034  # lido pela guarda por nome (nameref)
  local -a outro=(/bk/b.tar)
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao outro 0000000001a id:sai _rv _iv || exit 8
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai sim outro 0000000001a id:sai _rv _iv && exit 1
  exit 0
}
export -f _guarda_do_primeiro

teste_rtg09_mutante_sem_a_guarda_do_primeiro_reprova() {
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_do_primeiro
  assert_igual 0 "$?" 'a lib recusa o primeiro da ordem'
  _em_processo "$(_lib_mutante primeiro)" _guarda_do_primeiro
  assert_igual 1 "$?" 'o mutante deixa o primeiro da ordem passar e o caso o pega'
}

# DIV-158: a guarda compara CAMINHO com os que ficam, nao indice.
teste_div158_guarda_recusa_caminho_igual_ao_de_quem_fica() {
  local -a ficam=(/bk/db-5.tar)
  dbx_filtro_nome_preparar --padrao 'db-*.tar' || _harness_falhar 'padrao'
  dbx_retencao_guarda file /bk/db-5.tar db-5.tar /bk / sai nao ficam 0000000001a id:sai _rv _iv && _harness_falhar 'caminho igual ao que fica passou'
  assert_contem 'mesmo caminho' "$DBX_RETENCAO_MOTIVO" 'motivo'
  dbx_retencao_guarda file /bk/DB-5.TAR DB-5.TAR /bk / sai nao ficam 0000000001a id:sai _rv _iv && _harness_falhar 'caixa ASCII dobrada passou'
  dbx_retencao_guarda file /bk/db-4.tar db-4.tar /bk / sai nao ficam 0000000001a id:sai _rv _iv || _harness_falhar 'caminho diferente recusado'
  return 0
}

# DIV-158: o plano recusa path_lower repetido (caixa ASCII dobrada).
teste_div158_plano_recusa_caminho_repetido() {
  local -a sm=(2026-10-05T00:00:00Z 2026-10-01T00:00:00Z) chave=(db-5.tar db-5.tar) pl=(/bk/db-5.tar /BK/DB-5.TAR)
  dbx_retencao_planejar manter 1 "$AGORA" sm chave pl && _harness_falhar 'plano com caminho repetido'
  assert_contem 'path_lower repetido' "$DBX_RETENCAO_MOTIVO" 'motivo'
  return 0
}

_guarda_por_caminho() {
  local -a ficam=(/bk/a.tar)
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao ficam 0000000001a id:sai _rv _iv && exit 1
  exit 0
}
export -f _guarda_por_caminho

_plano_unico() {
  local -a sm=(2026-10-05T00:00:00Z 2026-10-01T00:00:00Z) chave=(a a) pl=(/bk/a /bk/a)
  dbx_retencao_planejar manter 1 "$AGORA_T" sm chave pl && exit 1
  exit 0
}
export -f _plano_unico

teste_div158_mutantes_da_lib_reprovam() {
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_por_caminho
  assert_igual 0 "$?" 'a lib recusa'
  _em_processo "$(_lib_mutante fica)" _guarda_por_caminho
  assert_igual 1 "$?" 'sem a guarda por caminho, o caso pega'
  _em_processo "$DBX_HARNESS_RAIZ/lib" _plano_unico
  assert_igual 0 "$?" 'o plano recusa'
  _em_processo "$(_lib_mutante unico)" _plano_unico
  assert_igual 1 "$?" 'sem a conferencia de unicidade, o caso pega'
}

# ---------------------------------------------------------------------------
# Ciclo 2 do QA (DIV-161, DIV-162)
# ---------------------------------------------------------------------------

# DIV-161: a chave de comparacao de caminho e a de RF-54 (Unicode sem caixa).
teste_div161_chave_unicode_de_rf54() {
  dbx_retencao_chave $'/bk/\xc3\x89.TAR' || _harness_falhar 'chave recusada com C.UTF-8'
  assert_igual $'/bk/\xc3\xa9.tar' "$DBX_RETENCAO_CHAVE" 'E acentuado dobrado'
  dbx_retencao_chave /BK/A.TAR || _harness_falhar 'ASCII'
  assert_igual /bk/a.tar "$DBX_RETENCAO_CHAVE" 'ASCII dobrado'
}

teste_div161_plano_recusa_duplicata_em_caixa_nao_ascii() {
  local -a sm=(2026-10-05T00:00:00Z 2026-10-01T00:00:00Z) chave=(x x) pl=($'/bk/\xc3\xa9.tar' $'/bk/\xc3\x89.tar')
  dbx_retencao_planejar manter 1 "$AGORA" sm chave pl && _harness_falhar 'plano com o mesmo caminho em outra caixa'
  assert_contem 'path_lower repetido' "$DBX_RETENCAO_MOTIVO" 'motivo'
  return 0
}

# Sem a localidade: so o ASCII tem chave; fora dele, falha fechada.
_sem_localidade() {
  dbx_retencao_chave /BK/A.TAR || exit 2
  [[ $DBX_RETENCAO_CHAVE == /bk/a.tar ]] || exit 3
  dbx_retencao_chave $'/bk/\xc3\xa9.tar' && exit 1
  local -a ficam=(/bk/b.tar)
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file $'/bk/\xc3\xa9.tar' $'\xc3\xa9.tar' /bk / sai nao ficam 0000000001a id:sai _rv _iv && exit 4
  exit 0
}
export -f _sem_localidade

teste_div161_sem_localidade_fora_do_ascii_falha_fechada() {
  # LC_ALL=C no processo: a localidade inexistente nao cai num UTF-8 herdado.
  LC_ALL=C DBX_SYNC_LOCALIDADE=xx_INEXISTENTE.UTF-8 _em_processo "$DBX_HARNESS_RAIZ/lib" _sem_localidade
  assert_igual 0 "$?" 'sem C.UTF-8: ASCII com chave, fora do ASCII recusado'
}

_guarda_unicode() {
  local -a ficam=($'/bk/\xc3\x89.tar')
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file $'/bk/\xc3\xa9.tar' $'\xc3\xa9.tar' /bk / sai nao ficam 0000000001a id:sai _rv _iv && exit 1
  exit 0
}
export -f _guarda_unicode

_guarda_sem_lista() {
  # shellcheck disable=SC2034  # lido pela guarda por nome (nameref)
  local -a vazio=()
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao && exit 1
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao vazio 0000000001a id:sai _rv _iv && exit 1
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao nao_existe_este_vetor 0000000001a id:sai _rv _iv && exit 1
  exit 0
}
export -f _guarda_sem_lista

teste_div161_div162_mutantes_da_lib_reprovam() {
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_unicode
  assert_igual 0 "$?" 'a lib compara pela chave Unicode'
  _em_processo "$(_lib_mutante_troca unicode 's/^\(.*\)# MUTACAO:unicode$/  _dbx_retencao_ascii "$1"; DBX_RETENCAO_CHAVE=$_dbx_retencao_k/')" _guarda_unicode
  assert_igual 1 "$?" 'a dobra so ASCII deixa o mesmo arquivo em outra caixa passar e o caso pega'
  LC_ALL=C DBX_SYNC_LOCALIDADE=xx_INEXISTENTE.UTF-8 _em_processo "$(_lib_mutante localidade)" _sem_localidade
  assert_diferente 0 "$?" 'sem a conferencia da localidade, o caso pega'
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_sem_lista
  assert_igual 0 "$?" 'a guarda falha fechada sem a lista'
  # Com DIV-167, a comparacao de rev/id tambem recusa a lista de caminhos ausente
  # (tamanhos diferentes); o mutante tira as duas para isolar a recusa da lista.
  _em_processo "$(_lib_mutante_troca lista '/# MUTACAO:\(lista\|identidade_guarda\)$/d')" _guarda_sem_lista
  assert_igual 1 "$?" 'sem a recusa da lista ausente, o caso pega'
}

# ---------------------------------------------------------------------------
# Ciclo 3 do QA (DIV-164, DIV-165)
# ---------------------------------------------------------------------------

# DIV-164: marca combinante dos cinco blocos, por bytes, sem localidade.
teste_div164_marca_combinante_por_bytes() {
  local t
  for t in $'e\xcc\x81' $'a\xcc\x80' $'a\xcd\xaf' $'a\xe1\xaa\xb0' $'a\xe1\xab\xbf' $'a\xe1\xb7\x80' \
    $'a\xe1\xb7\xbf' $'a\xe2\x83\x90' $'a\xe2\x83\xbf' $'a\xef\xb8\xa0' $'a\xef\xb8\xaf'; do
    dbx_retencao_sem_combinante "/bk/$t.tar" && _harness_falhar "marca combinante nao detectada: [$t]"
    (LC_ALL=C; dbx_retencao_sem_combinante "/bk/$t.tar") && _harness_falhar 'sob LC_ALL=C tambem'
  done
  for t in $'\xc3\xa9' $'a\xcd\xb0' $'a\xe1\xaa\xaf' $'a\xe2\x83\x8f' $'a\xef\xb8\xb0' $'\xd6\xb0' abc; do
    dbx_retencao_sem_combinante "/bk/$t.tar" || _harness_falhar "falso positivo: [$t]"
  done
  return 0
}

# DIV-165: cada elemento da lista de quem fica e caminho canonico.
_guarda_lista_canonica() {
  local nome
  # shellcheck disable=SC2034  # lidos pela guarda por nome (nameref)
  local -a ok=(/bk/b.tar) v1=('') v2=('' '') lixo=(x y) rel=(bk/b.tar) dupla=(/bk//b.tar) ponto=(/bk/./b.tar) \
    barra=(/bk/b.tar/) maiuscula=(/bk/B.TAR) nfd=($'/bk/e\xcc\x81.tar') misto=(/bk/b.tar '')
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao ok 0000000001a id:sai _rv _iv || exit 8
  for nome in v1 v2 lixo rel dupla ponto barra maiuscula nfd misto; do
    dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao "$nome" 0000000001a id:sai _rv _iv && exit 1
  done
  exit 0
}
export -f _guarda_lista_canonica

# DIV-164: a guarda recusa marca combinante em quem sai.
_guarda_sai_combinante() {
  # shellcheck disable=SC2034  # lido pela guarda por nome (nameref)
  local -a ok=(/bk/b.tar)
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file $'/bk/e\xcc\x81.tar' $'e\xcc\x81.tar' /bk / sai nao ok 0000000001a id:sai _rv _iv && exit 1
  exit 0
}
export -f _guarda_sai_combinante

teste_div164_div165_guarda_e_mutantes() {
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_lista_canonica
  assert_igual 0 "$?" 'a guarda recusa lista com elemento fora do formato'
  _em_processo "$(_lib_mutante formato)" _guarda_lista_canonica
  assert_igual 1 "$?" 'sem a conferencia de formato da lista, o caso pega'
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_sai_combinante
  assert_igual 0 "$?" 'a guarda recusa marca combinante em quem sai'
  _em_processo "$(_lib_mutante combinante_guarda)" _guarda_sai_combinante
  assert_igual 1 "$?" 'sem a conferencia na guarda, o caso pega'
}

# ---------------------------------------------------------------------------
# Ciclo 4 do QA (DIV-167, DIV-168)
# ---------------------------------------------------------------------------

teste_div168_utf8_valido_por_bytes() {
  local t
  for t in abc $'\xc3\xa9' $'\xe3\x81\x8c' $'\xf0\x9f\x98\x80' $'\xef\xbf\xbf' $'\xf4\x8f\xbf\xbf' $'\xed\x9f\xbf' ''; do
    dbx_retencao_utf8_valido "/bk/$t.tar" || _harness_falhar "valido recusado: [$t]"
    (LC_ALL=C.UTF-8; dbx_retencao_utf8_valido "/bk/$t.tar") || _harness_falhar "valido recusado sob C.UTF-8: [$t]"
  done
  for t in $'\xe0\x8c\x81' $'\xc0\x81' $'\xc1\xbf' $'\xcc' $'\x81' $'\xf8\x88\x80\x80\x80' $'\xfc\x84\x80\x80\x80\x80' \
    $'\xed\xa0\x80' $'\xed\xbf\xbf' $'\xf5\x80\x80\x80' $'\xff' $'\xf0\x80\x80\x80' $'\xf4\x90\x80\x80' $'\xe2\x82'; do
    dbx_retencao_utf8_valido "/bk/$t.tar" && _harness_falhar "invalido aceito: [$t]"
    (LC_ALL=C.UTF-8; dbx_retencao_utf8_valido "/bk/$t.tar") && _harness_falhar "invalido aceito sob C.UTF-8: [$t]"
  done
  return 0
}

# DIV-167: a guarda (7) recusa rev ou id de quem sai igual ao de quem fica, e
# recusa sem as listas de rev e id (ou vazias, ou de tamanho diferente).
_guarda_identidade() {
  # shellcheck disable=SC2034  # lidos pela guarda por nome (nameref)
  local -a fp=(/bk/b.tar) fr=(0000000005a) fid=(id:b) vazio=() dois=(0000000005a 0000000006a)
  dbx_filtro_nome_preparar --padrao '*.tar' || exit 9
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a id:a fr fid || exit 8
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000005a id:a fr fid && exit 1
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a id:b fr fid && exit 2
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp && exit 3
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a id:a vazio fid && exit 4
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a id:a fr vazio && exit 5
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp '' id:a fr fid && exit 6
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a '' fr fid && exit 7
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a id:a dois fid && exit 10
  dbx_retencao_guarda file /bk/a.tar a.tar /bk / sai nao fp 0000000001a id:a nao_existe fid && exit 11
  exit 0
}
export -f _guarda_identidade

teste_div167_guarda_por_rev_e_id_e_mutante() {
  _em_processo "$DBX_HARNESS_RAIZ/lib" _guarda_identidade
  assert_igual 0 "$?" 'a guarda compara rev e id e falha fechada sem as listas'
  _em_processo "$(_lib_mutante identidade_guarda)" _guarda_identidade
  assert_igual 1 "$?" 'sem a comparacao de rev e id, o caso pega'
}

teste_rtg12_lib_retencao_nao_cita_rota_destrutiva_nem_rede() {
  local texto
  texto=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/retencao.sh")
  assert_nao_contem 'permanently_delete' "$texto" 'sem exclusao permanente'
  assert_nao_contem 'delete_batch' "$texto" 'sem lote'
  assert_nao_contem 'dbx_http_' "$texto" 'sem rede'
  assert_nao_contem 'dbx_auth_' "$texto" 'sem rede'
  assert_nao_contem 'dbx_state_' "$texto" 'sem estado'
  assert_nao_contem '%(%s)T' "$texto" 'sem relogio: o agora e argumento'
}

harness_executar "$@"
