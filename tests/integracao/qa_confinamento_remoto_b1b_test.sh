#!/usr/bin/env bash
# Suite independente do QA, fase 1b do backlog: confinamento remoto (F-36,
# RNF-20(b1..b8), TC-SEC-18..32) e caminho remoto com controle (F-37, RNF-10(b)).
#
# Escrita como ADVERSARIO, pelo executavel real e por um duplo de `curl` proprio
# (independente do da suite do developer). A prova de "antes de qualquer chamada"
# e o diario do duplo: em toda recusa ele NAO existe, nem para `oauth2/token`.
# Vetores: travessia, prefixo, caixa (inclusive Unicode e localidade), relativo,
# id/rev/ns no lugar de caminho, sosias Unicode de `/` e `.`, `%2F` literal,
# espaco final, byte de controle em cada posicao, destino DERIVADO do `upload`
# de diretorio, raiz `/`, raiz malformada e `list` sem argumento.
#
# shellcheck disable=SC2016,SC2088
# Justificativa: o duplo de `curl` e escrito sem expansao; `~/x` e vetor literal.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_RECUSADO=$(dbx_errors_codigo_saida caminho_recusado)
QA_CONFIGURACAO=$(dbx_errors_codigo_saida configuracao)
readonly QA_RECUSADO QA_CONFIGURACAO

# Toda forma de comando com caminho remoto, inclusive as que DERIVAM o destino.
readonly QA_FORMAS='upload upload_fluxo upload_dir download download_pasta list delete info sync_enviar sync_receber verificar_enviar verificar_receber'

QA_BASE=''
QA_ESTADO=''
QA_SAIDA=''
QA_ERRO=''

# _qa_cenario <raiz_remota> — credencial com a raiz dada, duplo de rede que anota
# cada URL em `diario` e todo argumento/corpo em `corpo`.
_qa_cenario() {
  QA_BASE=$(mktemp -d "$DBX_TESTES_TMP/qa-b1b.XXXXXX")
  mkdir -p "$QA_BASE/cfg/dbx" "$QA_BASE/bin" "$QA_BASE/arvore/sub" "$QA_BASE/tmp"
  local raiz_json=$1
  raiz_json=${raiz_json//\\/\\\\}
  raiz_json=${raiz_json//$'\n'/\\n}
  raiz_json=${raiz_json//$'\033'/\\u001b}
  printf '{"versao":1,"app_key":"k","app_secret":"s","refresh_token":"r","raiz_remota":"%s"}' "$raiz_json" \
    >"$QA_BASE/cfg/dbx/credencial.json"
  chmod 700 "$QA_BASE/cfg/dbx"
  chmod 600 "$QA_BASE/cfg/dbx/credencial.json"
  printf 'x' >"$QA_BASE/arvore/um.txt"
  printf 'y' >"$QA_BASE/arvore/sub/dois.txt"
  printf '#!/usr/bin/env bash\nQA=%q\n' "$QA_BASE" >"$QA_BASE/bin/curl"
  cat >>"$QA_BASE/bin/curl" <<'FIM'
printf '%s\n' "$*" >>"$QA/corpo"
cat >>"$QA/corpo" 2>/dev/null
o=''; w=''; ant=''; url=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; esac
  case $a in http*) url=$a ;; @*) cat -- "${a#@}" >>"$QA/corpo" 2>/dev/null ;; esac
  ant=$a
done
printf '%s\n' "$url" >>"$QA/diario"
c=200
case $url in
  *oauth2/token*) r='{"access_token":"sl.qa","expires_in":14400}' ;;
  *list_folder*) r='{"entries":[],"cursor":"c","has_more":false}' ;;
  *upload_session/start*) r='{"session_id":"s"}' ;;
  *get_space_usage*) r='{"used":1,"allocation":{".tag":"individual","allocated":99999999}}' ;;
  *get_metadata*) c=409; r='{"error_summary":"path/not_found/"}' ;;
  *files/download*)
    if [[ -f $QA/eh_pasta ]]; then c=409; r='{"error_summary":"path/not_file/"}'; else r='x'; fi ;;
  *) r='{"name":"um.txt","path_display":"/q",".tag":"file","size":1}' ;;
esac
[[ -n $o ]] && printf '%s' "$r" >"$o"
[[ -n $w ]] && printf '%s' "$c"
exit 0
FIM
  chmod +x "$QA_BASE/bin/curl"
}

# _qa_dbx [LC_ALL=<loc>|LANG=<loc>]... <args...> — roda o executavel real em ambiente limpo.
_qa_dbx() {
  # A localidade NAO e apagada: o padrao e `LANG=C.UTF-8`, a do host; um
  # prefixo `LC_ALL=` ou `LANG=` a sobrepoe (ciclo 2).
  local -a loc=(LANG=C.UTF-8)
  while [[ ${1-} == LC_ALL=* || ${1-} == LANG=* ]]; do
    loc+=("$1")
    shift
  done
  rm -f "$QA_BASE/diario" "$QA_BASE/corpo"
  rm -rf "$QA_BASE/rec" "$QA_BASE/baixado"
  env -i PATH="$QA_BASE/bin:$PATH" HOME="$QA_BASE" XDG_CONFIG_HOME="$QA_BASE/cfg" \
    XDG_STATE_HOME="$QA_BASE/estado" TMPDIR="$QA_BASE/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    ${loc[@]+"${loc[@]}"} bash "$QA_DBX" "$@" <<<'fluxo' >"$QA_BASE/out" 2>"$QA_BASE/err"
  QA_ESTADO=$?
  IFS= read -r -d '' QA_SAIDA <"$QA_BASE/out"
  IFS= read -r -d '' QA_ERRO <"$QA_BASE/err"
  return 0
}

# _qa_forma [LC_ALL=<loc>|LANG=<loc>]... <forma> <remoto>
_qa_forma() {
  local -a loc=()
  while [[ ${1-} == LC_ALL=* || ${1-} == LANG=* ]]; do
    loc+=("$1")
    shift
  done
  local forma=$1 r=$2 b=$QA_BASE
  rm -f "$b/eh_pasta"
  [[ $forma == download_pasta ]] && : >"$b/eh_pasta"
  case $forma in
    upload) _qa_dbx "${loc[@]}" upload "$b/arvore/um.txt" "$r" ;;
    upload_fluxo) _qa_dbx "${loc[@]}" upload - "$r" ;;
    upload_dir) _qa_dbx "${loc[@]}" upload "$b/arvore" "$r" ;;
    download) _qa_dbx "${loc[@]}" download "$r" "$b/baixado" ;;
    download_pasta) _qa_dbx "${loc[@]}" download "$r" "$b/rec" ;;
    list) _qa_dbx "${loc[@]}" list "$r" ;;
    delete) _qa_dbx "${loc[@]}" delete --yes "$r" ;;
    info) _qa_dbx "${loc[@]}" info "$r" ;;
    sync_enviar) _qa_dbx "${loc[@]}" sync --enviar --origem "$b/arvore" --destino "$r" ;;
    sync_receber) _qa_dbx "${loc[@]}" sync --receber --origem "$r" --destino "$b/rec" ;;
    verificar_enviar) _qa_dbx "${loc[@]}" verificar --enviar --origem "$b/arvore" --destino "$r" ;;
    verificar_receber) _qa_dbx "${loc[@]}" verificar --receber --origem "$r" --destino "$b/arvore" ;;
    *) _harness_falhar "forma desconhecida: $forma" ;;
  esac
}

# _qa_recusa <rotulo> [codigo] — recusa sem NENHUMA chamada e sem efeito local.
_qa_recusa() {
  local rotulo=$1 codigo=${2:-$QA_RECUSADO}
  assert_igual "$codigo" "$QA_ESTADO" "$rotulo: codigo; erro: $QA_ERRO"
  assert_arquivo_ausente "$QA_BASE/diario" "$rotulo: nenhuma chamada, nem oauth2/token; diario: $(cat "$QA_BASE/diario" 2>/dev/null)"
  assert_igual '' "$QA_SAIDA" "$rotulo: nada na saida padrao"
  assert_arquivo_ausente "$QA_BASE/rec" "$rotulo: nenhum destino local criado"
  assert_arquivo_ausente "$QA_BASE/baixado" "$rotulo: nenhum arquivo baixado"
}

# _qa_aceito <rotulo> <trecho> — passou do confinamento e o trecho chegou a API.
_qa_aceito() {
  local rotulo=$1 trecho=$2
  assert_diferente "$QA_RECUSADO" "$QA_ESTADO" "$rotulo: nao recusado; erro: $QA_ERRO"
  assert_diferente "$QA_CONFIGURACAO" "$QA_ESTADO" "$rotulo: nao e configuracao; erro: $QA_ERRO"
  assert_arquivo_existe "$QA_BASE/diario" "$rotulo: chegou a API"
  assert_contem "$trecho" "$(cat "$QA_BASE/corpo" 2>/dev/null)" "$rotulo: caminho enviado; erro: $QA_ERRO"
}

# ---------------------------------------------------------------------------
# Fuga por travessia, prefixo, caixa ASCII, relativo, id/rev/ns, sosias Unicode
# ---------------------------------------------------------------------------

teste_qa_b1b_fuga_de_raiz_recusada_em_toda_forma_sem_chamada() {
  _qa_cenario /Raiz
  local forma r
  local -a vetores=(
    /fora /RaizX /raiz/../fora /Raiz/./../fora /Raiz//../fora //fora /RAIZX /RAIZX/a
    / /Raiz/.. /Raiz/sub/../../fora '/Raiz /x' '/ Raiz/x' '/Raiz%2F..%2Ffora' '/Raiz%2Fx'
    'Raiz/x' './Raiz/x' '~/x' 'id:a4ayc_80_OEAAAAAAAAAXw' 'rev:a1c10ce0dd78' 'ns:1234' 'ns:1234/Raiz/x'
    $'/Raiz∕..∕fora' $'/Raiz／..／fora' $'/Raiz⁄x' '/Raiz\..\fora' $'/Raiz․/x'
    $'/Raíz/x' $'/Ｒaiz/x'
  )
  for forma in $QA_FORMAS; do
    for r in "${vetores[@]}"; do
      _qa_forma "$forma" "$r"
      _qa_recusa "$forma [$r]"
    done
  done
}

teste_qa_b1b_dentro_da_raiz_aceito_e_enviado_literal() {
  # Nomes estranhos DENTRO da raiz sao nomes, nao separadores: sao aceitos e o
  # caminho chega a API com o prefixo da raiz (confinado), sem decodificacao.
  _qa_cenario /Raiz
  local forma par r trecho
  local -a pares=(
    '/RAIZ/x|/RAIZ/x' '/raiz/x|/raiz/x' '/Raiz/a/../b|/Raiz/b' '/Raiz/./b//c|/Raiz/b/c'
    '/Raiz/x |/Raiz/x '
    '/Raiz/..%2F..%2Ffora|/Raiz/..%2F..%2Ffora'
    $'/Raiz/x∕..∕..∕fora|/Raiz/x∕..∕..∕fora'
    $'/Raiz/．．/fora|/Raiz/．．/fora'
    '/Raiz/id:abc|/Raiz/id:abc'
  )
  for forma in $QA_FORMAS; do
    for par in "${pares[@]}"; do
      r=${par%%|*}
      trecho=${par#*|}
      _qa_forma "$forma" "$r"
      _qa_aceito "$forma [$r]" "$trecho"
    done
  done
}

# ---------------------------------------------------------------------------
# Caixa Unicode e localidade: a decisao de seguranca nao pode depender do locale
# ---------------------------------------------------------------------------

teste_qa_b1b_caixa_unicode_nao_escapa_em_nenhuma_localidade() {
  # `İ` (U+0130) tem minuscula simples `i` na glibc (towlower), mas a dobra de
  # caixa Unicode completa e `i` + U+0307: `/RAİZ` NAO e `/Raiz`. Se a
  # comparacao sem caixa usa a localidade do operador, a MESMA credencial e o
  # MESMO argumento recusam sob `C` e passam sob UTF-8, e o caminho enviado e
  # `/RAİZ/fora`, uma pasta irma da raiz. Falha fechada exige recusa nas duas.
  locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$' || pular 'localidade C.UTF-8 indisponivel'
  _qa_cenario /Raiz
  local forma loc r
  for loc in LC_ALL=C LC_ALL=C.UTF-8 LANG=C.UTF-8; do
    for r in $'/RAİZ/fora' $'/Raİz/fora'; do
      for forma in upload delete sync_enviar list; do
        _qa_forma "$loc" "$forma" "$r"
        _qa_recusa "$loc $forma [$r]"
      done
    done
  done
}

# Ciclo 2 (QA-B1B-01 corrigido; RNF-20(b4), TC-SEC-33): dobra SO de A-Z.
# Cada par e `raiz|argumento`. Nenhuma dobra especial da glibc ou do Unicode
# (`ſ`->s, Kelvin->k, `ı`, `ß`/`ẞ`, ligadura, largura total, NFC/NFD) pode
# fazer um nome nao ASCII casar com a raiz. Raiz com acento: identico e so-ASCII
# em outra caixa sao aceitos; acento em outra caixa e recusado (limite aceito).
readonly QA_LOCALIDADES='LC_ALL=C LC_ALL=C.UTF-8 LANG=C.UTF-8'

teste_qa_b1b_dobra_especial_nao_casa_com_a_raiz_em_nenhuma_localidade() {
  locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$' || pular 'localidade C.UTF-8 indisponivel'
  local par raiz r loc forma nfc=$'/A\u00e7\u00e3o' nfd=$'/Ac\u0327a\u0303o'
  local -a pares=(
    $'/Sala|/\u017fala/x' $'/SALA|/\u017fALA/x' $'/Kit|/\u212ait/x' $'/kit|/\u212aIT/x'
    $'/Raiz|/Ra\u0131z/x' $'/RAIZ|/RA\u0131Z/x' $'/Raiz|/RA\u0130Z/x'
    $'/Strasse|/Stra\u00dfe/x' $'/Strasse|/STRA\u1e9eE/x' $'/Stra\u00dfe|/STRASSE/x' $'/Stra\u00dfe|/STRA\u1e9eE/x'
    $'/fi|/\ufb01/x' $'/Raiz|/Raiz\uff0fx' $'/Raiz|/Raiz\uff0e/x' $'/Raiz|/\uff32aiz/x'
    "$nfc|$nfd/x" "$nfd|$nfc/x" $'/A\u00e7\u00e3o|/A\u00c7\u00c3O/x' $'/A\u00e7\u00e3o|/ACAO/x'
  )
  for par in "${pares[@]}"; do
    raiz=${par%%|*}
    r=${par#*|}
    _qa_cenario "$raiz"
    for loc in $QA_LOCALIDADES; do
      for forma in upload delete list sync_enviar verificar_receber; do
        _qa_forma "$loc" "$forma" "$r"
        _qa_recusa "$loc $forma raiz [$raiz] [$r]"
      done
    done
  done
}

teste_qa_b1b_raiz_com_acento_identica_ou_so_ascii_em_outra_caixa_e_aceita() {
  locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$' || pular 'localidade C.UTF-8 indisponivel'
  local par raiz r loc forma nfd=$'/Ac\u0327a\u0303o'
  local -a pares=(
    $'/A\u00e7\u00e3o|/A\u00e7\u00e3o/x' $'/A\u00e7\u00e3o|/a\u00e7\u00e3o/x' $'/A\u00e7\u00e3o|/A\u00e7\u00e3O/x'
    "$nfd|$nfd/x" $'/Stra\u00dfe|/STRA\u00dfE/x' $'/Raiz|/RAIZ/\uff0e\uff0e\uff0f\uff0e\uff0e\uff0ffora'
    $'/Kit|/KIT/\u212a'
  )
  for par in "${pares[@]}"; do
    raiz=${par%%|*}
    r=${par#*|}
    _qa_cenario "$raiz"
    for loc in $QA_LOCALIDADES; do
      for forma in upload delete list sync_enviar verificar_receber; do
        _qa_forma "$loc" "$forma" "$r"
        # O argumento vai a API com a grafia do operador, byte a byte.
        _qa_aceito "$loc $forma raiz [$raiz] [$r]" "${r%/x}"
      done
    done
  done
}

teste_qa_b1b_dobra_ascii_nao_vaza_localidade_para_o_processo() {
  # `local LC_ALL=C` no confinamento tem de se desfazer no retorno: depois dele
  # o processo segue UTF-8 (a dobra do `sync`, `${#x}` e a escolha de glifo de
  # lib/progress, que le a VARIAVEL). Com LC_ALL ausente, segue ausente.
  locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$' || pular 'localidade C.UTF-8 indisponivel'
  local loc saida esperado
  for loc in LC_ALL=C.UTF-8 LANG=C.UTF-8; do
    saida=$(env -i PATH="$PATH" "$loc" bash -c '
      . "$1/lib/path.sh"
      . "$1/lib/sync.sh" 2>/dev/null || exit 9
      antes=${LC_ALL-ausente}
      dbx_path_remoto_argumento /Raiz /RAIZ/x >/dev/null
      dbx_path_remoto_argumento /Raiz $'"'"'/RAİZ/x'"'"' >/dev/null
      dbx_path_remoto_argumento $'"'"'/Ra
'"'"' /x >/dev/null
      dbx_path_remoto_confinar /Raiz /RAIZ/y >/dev/null
      x=$'"'"'İÉ'"'"'
      _dbx_sync_chave "$x"
      printf "%s|%s|%s|%s" "$antes" "${LC_ALL-ausente}" "${#x}" "${x,,}|$DBX_SYNC_CHAVE"
    ' _ "$DBX_HARNESS_RAIZ")
    esperado='ausente|ausente'
    [[ $loc == LC_ALL=* ]] && esperado="${loc#LC_ALL=}|${loc#LC_ALL=}"
    assert_igual "$esperado|2|"$'i\u00e9|i\u00e9' "$saida" \
      "$loc: LC_ALL intacta e o processo segue UTF-8 (antes|depois|tamanho|minuscula|chave do sync)"
  done
}

# ---------------------------------------------------------------------------
# Byte de controle em cada posicao (F-37), inclusive no destino DERIVADO
# ---------------------------------------------------------------------------

teste_qa_b1b_controle_em_cada_posicao_recusado_sem_byte_cru() {
  _qa_cenario /Raiz
  local b r forma visivel
  for b in $'\n' $'\r' $'\t' $'\001' $'\033' $'\037' $'\177'; do
    printf -v visivel '%q' "$b"
    for r in "${b}/Raiz/x" "/${b}Raiz/x" "/Raiz${b}/x" "/Raiz/${b}x" "/Raiz/a${b}b" "/Raiz/x${b}"; do
      for forma in info delete; do
        _qa_forma "$forma" "$r"
        _qa_recusa "$forma $visivel [${r//$b/<b>}]"
        assert_contem 'controle' "$QA_ERRO" "$forma $visivel: motivo nomeado"
        assert_nao_contem "$b" "${QA_ERRO%$'\n'}" "$forma $visivel: byte cru nao vai ao diagnostico"
      done
    done
  done
  for forma in $QA_FORMAS; do
    for b in $'\n' $'\033'; do
      _qa_forma "$forma" "/Raiz/x${b}"
      _qa_recusa "$forma [fim com controle]"
    done
  done
}

teste_qa_b1b_destino_derivado_do_upload_de_diretorio_e_reconfinado() {
  _qa_cenario /Raiz
  # TC-SEC-32: nome local com `\n` vira destino remoto derivado: recusado.
  mkdir -p "$QA_BASE/arvore/a"$'\n'"b"
  printf 'z' >"$QA_BASE/arvore/a"$'\n'"b/z.txt"
  _qa_dbx upload "$QA_BASE/arvore/a"$'\n'"b" /Raiz/
  _qa_recusa 'diretorio com \n derivado'
  # Nome local `..` (origem `arvore/..`) deriva `/Raiz/..`: sairia da raiz.
  _qa_dbx upload "$QA_BASE/arvore/.." /Raiz/
  _qa_recusa 'diretorio .. derivado sob /Raiz'
  _qa_cenario /
  _qa_dbx upload "$QA_BASE/arvore/.." /
  _qa_recusa 'diretorio .. derivado sob a raiz da conta'
  # Controle: o derivado legitimo e aceito e fica dentro da raiz.
  _qa_cenario /Raiz
  _qa_dbx upload "$QA_BASE/arvore" /raiz/
  _qa_aceito 'derivado legitimo' '/raiz/arvore'
}

teste_qa_b1b_simulacao_tambem_recusa_fora_da_raiz() {
  _qa_cenario /Raiz
  local forma
  for forma in upload delete download sync_enviar; do
    case $forma in
      upload) _qa_dbx --dry-run upload "$QA_BASE/arvore/um.txt" /fora ;;
      delete) _qa_dbx --dry-run delete --yes /fora ;;
      download) _qa_dbx --dry-run download /fora "$QA_BASE/baixado" ;;
      sync_enviar) _qa_dbx --dry-run sync --enviar --origem "$QA_BASE/arvore" --destino /fora ;;
    esac
    _qa_recusa "--dry-run $forma"
  done
}

# ---------------------------------------------------------------------------
# Raiz `/` (nada muda), raiz malformada (3), `list` sem argumento
# ---------------------------------------------------------------------------

teste_qa_b1b_raiz_da_conta_nada_muda() {
  local raiz forma
  for raiz in / ''; do
    _qa_cenario "$raiz"
    for forma in upload download list delete info sync_enviar sync_receber verificar_enviar verificar_receber; do
      _qa_forma "$forma" /Fora/Raiz/../y
      _qa_aceito "raiz [$raiz] $forma" '/Fora/y'
    done
    _qa_dbx list
    assert_igual 0 "$QA_ESTADO" "raiz [$raiz] list sem argumento; erro: $QA_ERRO"
    assert_contem '"path":""' "$(cat "$QA_BASE/corpo")" "raiz [$raiz]: list sem argumento envia a raiz da conta"
    _qa_dbx info /../x
    _qa_recusa "raiz [$raiz] .. acima da conta"
    _qa_dbx info 'id:abc'
    _qa_recusa "raiz [$raiz] id: no lugar de caminho"
  done
}

teste_qa_b1b_list_sem_argumento_lista_a_raiz_configurada() {
  local raiz esperado
  for raiz in /Raiz /Raiz/ //Raiz/./sub/.. /RAIZ; do
    _qa_cenario "$raiz"
    _qa_dbx list
    esperado=/Raiz
    [[ $raiz == /RAIZ ]] && esperado=/RAIZ
    assert_igual 0 "$QA_ESTADO" "list sem argumento [$raiz]; erro: $QA_ERRO"
    assert_contem "\"path\":\"$esperado\"" "$(cat "$QA_BASE/corpo")" "list sem argumento [$raiz] lista a raiz normalizada"
    _qa_dbx list ''
    assert_contem "\"path\":\"$esperado\"" "$(cat "$QA_BASE/corpo" 2>/dev/null)" "list '' [$raiz] nao vira a conta"
  done
}

teste_qa_b1b_raiz_malformada_falha_fechado_com_3() {
  local raiz forma
  for raiz in Raiz /.. /Raiz/../.. $'/Raiz\n' $'/Ra\033iz' 'id:abc' './Raiz'; do
    _qa_cenario "$raiz"
    for forma in upload list delete info sync_receber verificar_enviar; do
      _qa_forma "$forma" /Raiz/x
      _qa_recusa "raiz [${raiz//[$'\n\033']/<c>}] $forma" "$QA_CONFIGURACAO"
    done
    assert_nao_contem $'\033' "$QA_ERRO" 'byte cru da raiz nao vai ao diagnostico'
    [[ $raiz == *[$'\n\033']* ]] && continue # caso proprio abaixo
    _qa_dbx list
    _qa_recusa "raiz [$raiz] list sem argumento" "$QA_CONFIGURACAO"
  done
}

teste_qa_b1b_raiz_com_controle_list_sem_argumento_sai_3() {
  # TC-SEC-31 / RNF-20(b8): raiz com controle e malformada (3) tambem no `list`
  # sem argumento, que usa a propria raiz como caminho.
  local raiz
  for raiz in $'/Raiz\n' $'/Ra\033iz'; do
    _qa_cenario "$raiz"
    _qa_dbx list
    _qa_recusa "raiz [${raiz//[$'\n\033']/<c>}] list sem argumento" "$QA_CONFIGURACAO"
    assert_nao_contem $'\033' "$QA_ERRO" 'byte cru da raiz nao vai ao diagnostico'
  done
}

harness_executar "$@"
