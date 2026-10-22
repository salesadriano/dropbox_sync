#!/usr/bin/env bash
# Suite independente do QA Expert para a fase 10 (progresso por arquivo, F-49;
# RF-140 a RF-147; secao 5.19; DIV-302 e DIV-303 por decisao do Tech Lead).
# Executavel real `bin/dbx`, duplo de `curl` proprio, sem rede e sem conta real.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

# _qa_cenario — credencial, duplo de `curl` e arvore local. Controles por arquivo:
#   listagem        corpo do list_folder
#   meta, meta_cod  corpo e codigo do get_metadata
#   cresce, cresce_mib  o download grava <cresce> passos de <cresce_mib> MiB no .part (0,3 s cada)
_qa_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-b10.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp" "$base/estado"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  {
    printf '#!/usr/bin/env bash\nbase=%q\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida=''; ant=''; url=''; escrever=''; corpo_arquivo=''
for arg in "$@"; do
  case $ant in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  ant=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.QAtokenB10","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *files/download*) corpo=$(cat "$base/conteudo_remoto") ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *get_metadata*) corpo='{".tag":"file","size":15,"rev":"0123456789a"}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
codigo_anterior=$codigo corpo_anterior=$corpo
lote_responder "$url" "$corpo_arquivo" || { codigo=$codigo_anterior; corpo=$corpo_anterior; }
if [[ $url == *get_metadata* && -f "$base/meta" ]]; then corpo=$(cat "$base/meta"); fi
if [[ $url == *get_metadata* && -f "$base/meta_cod" ]]; then
  codigo=$(cat "$base/meta_cod"); corpo='{"error_summary":"other/.."}'
fi
if [[ $url == *files/download && -f "$base/cresce" && -n $saida ]]; then
  : >"$saida"
  for ((n = 0; n < $(cat "$base/cresce"); n++)); do
    head -c $(($(cat "$base/cresce_mib") * 1048576)) /dev/zero | tr '\0' x >>"$saida"
    sleep 0.3
  done
  [[ -n $escrever ]] && printf 200
  exit 0
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _qa_rodar <base> <terminal sim|nao> <argumentos...> — stdin vem de $base/entrada (se existir).
_qa_rodar() {
  local base=$1 terminal=$2 entrada=/dev/null
  shift 2
  [[ -f $base/entrada ]] && entrada=$base/entrada
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_PROGRESS_TERMINAL="$terminal" \
    bash "$DBX_EXEC" "$@" <"$entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_entrada() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","path_lower":"%s","content_hash":"%s","size":%s,"rev":"0a1b2c3d4"}' \
    "$1" "${1,,}" "$2" "$3"
}

_qa_remoto3() { # <base> <tamanho> — a.bin, b.bin, c.bin
  local ea eb ec
  ea=$(_qa_entrada /r/a.bin ff "$2") eb=$(_qa_entrada /r/b.bin ff "$2") ec=$(_qa_entrada /r/c.bin ff "$2")
  printf '{"entries":[%s,%s,%s],"has_more":false}' "$ea" "$eb" "$ec" >"$1/listagem"
}

# _qa_memoria <base> — o cache: "<hash> <nome>" por registro, sem identidade nem caminho do cenario.
_qa_memoria() {
  local f l
  for f in "$1"/estado/dbx/memoria-*; do
    [[ -r $f ]] || continue
    tr '\0' '\n' <"$f" | while IFS= read -r l; do
      if [[ $l == *$'\t'*$'\t'* ]]; then
        printf '%s %s\n' "${l%%$'\t'*}" "${l##*$'\t'}"
      else
        printf 'cab %s\n' "${l//$1/BASE}"
      fi
    done | LC_ALL=C sort
  done
  return 0
}

# _qa_pcts <nome> <texto> — os percentuais das linhas do arquivo, na ordem, um por linha.
_qa_pcts() {
  grep -F -- ": $1 [" <<<"$2" | sed -E 's/^.*\] ([0-9]+)% .*$/\1/'
}

_qa_nao_decresce() { # <lista de numeros, um por linha>
  local anterior=-1 p
  while IFS= read -r p; do
    [[ $p -ge $anterior ]] || return 1
    anterior=$p
  done <<<"$1"
  return 0
}

_qa_linhas() { grep -c . <<<"$1"; } # <texto> — linhas nao vazias
_qa_cem() { grep -c '^100$' <<<"$1"; } # <lista> — quantas amostras valem 100
_qa_ultima() { tail -n 1 <<<"$1"; } # <lista> — a ultima amostra

# --- DIV-302 ----------------------------------------------------------------

teste_qpa01_cache_normalizado_igual_entre_n1_e_n3_no_receber() {
  local a b c ma mb mc
  a=$(_qa_cenario) && b=$(_qa_cenario) && c=$(_qa_cenario)
  _qa_remoto3 "$a" 15 && _qa_remoto3 "$b" 15 && _qa_remoto3 "$c" 15
  _qa_rodar "$a" nao --progresso sync --receber --origem /r --destino "$a/local"
  assert_igual 0 "$DBX_ESTADO" "N=1 deve concluir; diagnostico: $DBX_ERRO"
  _qa_rodar "$b" nao --progresso sync --receber --origem /r --destino "$b/local" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "N=3 deve concluir; diagnostico: $DBX_ERRO"
  _qa_rodar "$c" nao sync --receber --origem /r --destino "$c/local" --paralelo 3
  ma=$(_qa_memoria "$a") mb=$(_qa_memoria "$b") mc=$(_qa_memoria "$c")
  # O arquivo recem-baixado nao entra no cache (anti-corrida de 2 s): o cabecalho (conta, origem,
  # destino) e o que ha para comparar aqui; o conteudo com registros fica no envio (qpa02).
  assert_contem 'cab dbid:CONTA' "$ma" 'DIV-302: a memoria foi gravada'
  assert_igual "$ma" "$mb" 'DIV-302: conteudo do cache com N=3 e progresso igual ao do N=1'
  assert_igual "$ma" "$mc" 'DIV-302: conteudo do cache com N=3 sem progresso igual ao do N=1'
}

teste_qpa02_cache_normalizado_igual_entre_n1_e_n3_no_enviar() {
  local a b i ma mb
  a=$(_qa_cenario) && b=$(_qa_cenario)
  for i in a b c; do
    printf 'dados-%s' "$i" >"$a/local/$i.txt"
    printf 'dados-%s' "$i" >"$b/local/$i.txt"
    touch -d '2020-01-01 00:00:00' "$a/local/$i.txt" "$b/local/$i.txt"
  done
  _qa_rodar "$a" nao --progresso sync --enviar --origem "$a/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "N=1 deve concluir; diagnostico: $DBX_ERRO"
  _qa_rodar "$b" nao --progresso sync --enviar --origem "$b/local" --destino /r --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "N=3 deve concluir; diagnostico: $DBX_ERRO"
  ma=$(_qa_memoria "$a") mb=$(_qa_memoria "$b")
  [[ $(_qa_linhas "$ma") -ge 6 ]] || _harness_falhar "DIV-302: o cache do envio N=1 sem os 3 registros: $ma"
  assert_igual "$ma" "$mb" 'DIV-302: conteudo do cache do envio com N=3 igual ao do N=1'
}

# --- DIV-303 ----------------------------------------------------------------

teste_qpa03_amostragem_sem_terminal_n3_uma_linha_por_decil_com_posicao_certa() {
  local base arq nome pos pcts n anterior p
  base=$(_qa_cenario)
  _qa_remoto3 "$base" 8388608
  printf 8 >"$base/cresce"
  printf 1 >"$base/cresce_mib"
  _qa_rodar "$base" nao --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_nao_contem $'\r' "$DBX_ERRO" 'DIV-303: sem retorno de carro sem terminal'
  assert_nao_contem $'\033' "$DBX_ERRO" 'DIV-303: sem sequencia de controle sem terminal'
  for arq in a:1 b:2 c:3; do
    nome=${arq%%:*}.bin pos=${arq##*:}
    pcts=$(_qa_pcts "$nome" "$DBX_ERRO")
    n=$(_qa_linhas "$pcts")
    [[ $n -ge 4 ]] || _harness_falhar "DIV-303: $nome teve $n linhas, o .part que cresce exige amostras: $DBX_ERRO"
    _qa_nao_decresce "$pcts" || _harness_falhar "RF-140(g): o percentual de $nome diminuiu: ${pcts//$'\n'/ }"
    assert_igual 1 "$(_qa_cem "$pcts")" "RF-140(f): $nome chega a 100 uma unica vez"
    assert_igual 100 "$(_qa_ultima "$pcts")" "RF-140(f): 100 e a ultima linha de $nome"
    anterior=-1
    while IFS= read -r p; do
      [[ $p -eq 100 || $((p / 10)) -gt $anterior ]] || _harness_falhar "DIV-303: $nome teve duas linhas no mesmo decil ($p%): ${pcts//$'\n'/ }"
      anterior=$((p / 10))
    done <<<"$pcts"
    assert_igual "$n" "$(grep -cF -- "[$pos/3] baixando: $nome [" <<<"$DBX_ERRO")" "DIV-303: toda linha de $nome traz [$pos/3]"
  done
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'RNF-38(c): nada resta no temporario depois'
}

# --- stdout byte a byte (RF-145(a)) --------------------------------------------

teste_qpa04_upload_de_stdin_tem_stdout_identico_com_e_sem_progresso() {
  local base
  base=$(_qa_cenario)
  head -c 3000 /dev/zero | tr '\0' 'q' >"$base/entrada"
  _qa_rodar "$base" nao --json upload - /r/pipe.bin
  assert_igual 0 "$DBX_ESTADO" "upload de stdin deve concluir; diagnostico: $DBX_ERRO"
  cp "$base/out" "$base/out.sem"
  [[ -s $base/out.sem ]] || _harness_falhar 'a referencia sem progresso nao pode ser vazia'
  _qa_rodar "$base" nao --json --progresso upload - /r/pipe.bin
  assert_igual 0 "$DBX_ESTADO" "com progresso deve concluir; diagnostico: $DBX_ERRO"
  cmp -s "$base/out.sem" "$base/out" || _harness_falhar 'RF-145(a): stdout de upload - difere com progresso'
  assert_nao_contem 'enviando:' "$DBX_SAIDA" 'stdout livre de progresso'
}

teste_qpa05_download_para_arquivo_tem_stdout_identico_e_conteudo_igual() {
  local base
  base=$(_qa_cenario)
  _qa_rodar "$base" nao --json download /r/a.txt "$base/local/sem.txt"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  cp "$base/out" "$base/out.sem"
  _qa_rodar "$base" sim --json --progresso download /r/a.txt "$base/local/com.txt"
  assert_igual 0 "$DBX_ESTADO" "com progresso deve concluir; diagnostico: $DBX_ERRO"
  cmp -s <(sed "s#sem.txt#X#g" "$base/out.sem") <(sed "s#com.txt#X#g" "$base/out") \
    || _harness_falhar 'RF-145(a): stdout do download difere com progresso'
  cmp -s "$base/local/sem.txt" "$base/local/com.txt" || _harness_falhar 'o arquivo baixado difere com progresso'
}

# --- nome hostil (RF-144) ---------------------------------------------------------

teste_qpa06_nome_com_esc_bel_e_quebra_de_linha_nao_injeta_nada_na_linha() {
  local base outra nome linhas
  base=$(_qa_cenario)
  outra=$(_qa_cenario)
  nome=$'a\033[31mB\aC\nFAKE [9-9] enviando: x.txt'
  printf 'dados' >"$base/local/$nome"
  printf 'dados' >"$outra/local/$nome"
  _qa_rodar "$base" nao --progresso sync --enviar --origem "$base/local" --destino /r
  # Vale para a linha de progresso do arquivo (RF-144). As mensagens `[sync] analis...` do
  # comando, anteriores a este requisito, ecoam o nome cru: achado QA-B10-01.
  linhas=$(grep -a '^\[[0-9]*/[0-9]*\] enviando: ' <<<"$DBX_ERRO")
  assert_igual 2 "$(_qa_linhas "$linhas")" 'RF-144: uma linha de progresso inicial e uma final, sem linha forjada'
  assert_nao_contem $'\033' "$linhas" 'RF-144: ESC do nome nao chega a linha de progresso'
  assert_nao_contem $'\a' "$linhas" 'RF-144: BEL do nome nao chega a linha de progresso'
  assert_contem 'a?[31mB?C?FAKE [9-9] enviando: x.txt [' "$linhas" 'RF-144: controles trocados por ?, nome numa linha so'
  # Com terminal: nenhuma cor do nome chega a linha desenhada no lugar.
  _qa_rodar "$outra" sim --progresso sync --enviar --origem "$outra/local" --destino /r
  linhas=$(tr '\r' '\n' <<<"$DBX_ERRO" | grep -a '^\[[0-9]*/[0-9]*\] enviando: ')
  assert_nao_contem $'\033[31m' "$linhas" 'RF-144: a cor do nome nao chega a linha no terminal'
  assert_nao_contem $'\a' "$linhas" 'RF-144: BEL do nome nao chega a linha no terminal'
}

# --- falha do metadado (RF-146, DIV-304) -----------------------------------------------

teste_qpa07_falha_do_metadado_baixa_sem_linha_e_sem_erro_novo() {
  local base ref_estado ref_saida ref_erro
  base=$(_qa_cenario)
  printf 400 >"$base/meta_cod"
  _qa_rodar "$base" nao download /r/a.txt "$base/local/sem.txt"
  ref_estado=$DBX_ESTADO ref_saida=${DBX_SAIDA//sem.txt/X} ref_erro=${DBX_ERRO//sem.txt/X}
  _qa_rodar "$base" nao --progresso download /r/a.txt "$base/local/com.txt"
  assert_igual "$ref_estado" "$DBX_ESTADO" 'o codigo de saida e o mesmo com a falha do metadado'
  assert_igual "$ref_saida" "${DBX_SAIDA//com.txt/X}" 'stdout igual ao de sem progresso'
  # `[download] iniciando recebimento` e a mensagem de progresso ja existente; o resto tem de ser igual.
  assert_igual "$ref_erro" "$(grep -v '^\[download\] ' <<<"${DBX_ERRO//com.txt/X}")" 'nenhum erro novo no stderr com progresso'
  assert_nao_contem 'baixando:' "$DBX_ERRO" 'sem metadado nao ha linha de arquivo'
  assert_nao_contem ' falhou' "$DBX_ERRO" 'nem sufixo falhou'
}

# --- percentual monotono no N=1 com terminal (RF-140(g)) ------------------------------------

teste_qpa08_download_n1_grande_com_terminal_nunca_diminui_e_termina_em_cem() {
  local base pcts hash64
  base=$(_qa_cenario)
  printf -v hash64 '%64s' ''
  hash64=${hash64// /a}
  printf '{".tag":"file","size":6291456,"rev":"0123456789a","content_hash":"%s"}' "$hash64" >"$base/meta"
  printf 6 >"$base/cresce"
  printf 1 >"$base/cresce_mib"
  _qa_rodar "$base" sim --progresso download /r/a.bin "$base/local/a.bin"
  pcts=$(tr '\r' '\n' <<<"$DBX_ERRO" | grep -F 'baixando: /r/a.bin [' | sed -E 's/^.*\] ([0-9]+)% .*$/\1/')
  [[ $(_qa_linhas "$pcts") -ge 3 ]] || _harness_falhar "esperava varias amostras: $DBX_ERRO"
  _qa_nao_decresce "$pcts" || _harness_falhar "RF-140(g): o percentual diminuiu: ${pcts//$'\n'/ }"
  assert_igual 1 "$(_qa_cem "$pcts")" 'RF-140(f): 100% uma unica vez, na ultima amostra'
  assert_igual 100 "$(_qa_ultima "$pcts")" 'RF-140(f): a ultima amostra e 100%'
  pgrep -f -- "$base" >/dev/null && _harness_falhar 'processo orfao depois do download'
  return 0
}

harness_executar "$@"
