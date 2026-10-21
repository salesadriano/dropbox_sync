#!/usr/bin/env bash
# Suite independente do QA, fase 7a do backlog: retomada entre execucoes
# (F-03; RF-101..RF-109; DIV-171..DIV-202; condicoes C1..C6 do DBA).
#
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx`, com duplos de `curl`
# proprios (independentes dos de `retomada_upload_test` e
# `retomada_download_test`). Os focos sao os P0:
#
#   - upload: arquivo local que mudou entre as execucoes (sufixo com `stat`
#     forjado, truncado, outro inode, ligacao fisica) nunca retoma sobre o
#     prefixo antigo; o que se publica e sempre o conteudo local corrente;
#   - `correct_offset` fora de {confirmado, confirmado + parte em voo}: recomeca
#     do zero, sem corromper e sem anexar nada a sessao antiga;
#   - download: so `206` coerente e anexado; o destino so muda com o `.part`
#     inteiro conferido; `rev:` fixo; `.part` trocado (FIFO, diretorio, ligacao
#     fisica para arquivo do usuario, ligacao simbolica) nunca e seguido,
#     anexado nem apagado;
#   - estado invalido (outro nome, outro host, injecao de NUL e quebra de linha,
#     acima de 16 KiB, FIFO, diretorio, ligacao) descartado sem falhar;
#     `upload-*` gigante tratado como ausente (C3);
#   - trava de registro ilegivel: segue sem retomada, sem tocar em nada (C2);
#   - `session_id` fora de argv, ambiente, saidas e arquivos (C6); registro
#     0600 com `umask 000`;
#   - `--dry-run`, `--sem-retomada`, sinal e diretorio de estado inutilizavel;
#   - `diagnostico` e `unlink` nunca penduram nem apagam o que nao passa a
#     barreira.
#
# DUPLO DE UPLOAD: servidor de sessao com estado em `sess/<id>`; o `finish`
# publica o `content_hash` calculado sobre as partes de fato recebidas, em
# `publicado`. Roteiro em `roteiro`: `<endpoint> <ordinal> <acao>`, com o
# ordinal contado por endpoint desde o inicio do caso. Acoes: `SINAL:<NOME>`,
# `ACEITA_E_KILL` (processa e `kill -9`), `OFFSET:<valor cru>` (recusa com
# `incorrect_offset` e esse `correct_offset`, sem aspas), `NOT_FOUND`. Cada
# chamada registra o argv em `argv` e o ambiente em `ambiente`.
#
# DUPLO DE DOWNLOAD: contrato do cliente real para faixa (log da fase 7a):
# `continue-at = N` pede `Range: bytes=N-` e ANEXA; `200` ou `206` de outro
# inicio sai 33 sem escrever; `416` sai 0 sem escrever. Controles: `modo`
# (`rev`: `Dropbox-API-Result` com outra revisao; `errado_sempre`: corpo com
# um byte trocado), `corte` (bytes entregues antes de `exit 18`, valendo para
# pedido inteiro ou de faixa) e `sinal` (sinal ao `dbx` depois do corte).
#
# shellcheck disable=SC2016
# Justificativa: os duplos de `curl` sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QA_PARTE=4194304
readonly QA_TAMANHO=$((157286400 + 3))
readonly QA_SESSAO='QA7SESSAOsentinela'
readonly QA_REV1='0123456789a'
readonly QA_REV2='0123456789b'

DBX_ESTADO=''
DBX_SAIDA=''
DBX_ERRO=''

# ---------------------------------------------------------------------------
# Comum
# ---------------------------------------------------------------------------

# _qa_hash_para <arquivo> <saida> — content_hash do arquivo, calculado pela
# biblioteca em subshell, gravado em <saida> (lido depois com `read`).
_qa_hash_para() {
  (
    . "$DBX_HARNESS_RAIZ/lib/hash.sh"
    dbx_hash_publicar_arquivo "$1" && printf '%s' "$DBX_HASH_RESULTADO" >"$2"
  )
}

_qa_ler() { # <arquivo> — primeira linha, sem `$(...)` sobre bytes externos
  local v=''
  [[ -r $1 ]] && IFS= read -r v <"$1"
  printf '%s' "$v"
}

_qa_credencial() { # <base>
  mkdir -p "$1/config/dbx"
  chmod 700 "$1/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$1/config/dbx/credencial.json"
  chmod 600 "$1/config/dbx/credencial.json"
}

# _qa_rodar <base> <argumentos...> — sem terminal, com teto, em grupo proprio.
# `QA_EXEC` troca o executavel (copia mutante, usada so na auditoria do QA).
_qa_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="${QA_PATH:+$QA_PATH:}$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${QA_TETO:-120}" setsid -w bash -c 'umask "$1"; shift; printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "${QA_UMASK:-022}" "$base" "${QA_EXEC:-$QA_DBX}" "$@" </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  if [[ $DBX_ESTADO -eq 137 && -e $base/morto ]]; then
    rm -f "$base/morto"
  elif [[ $DBX_ESTADO -eq 124 || $DBX_ESTADO -eq 137 ]]; then
    _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  fi
  # Com `--null` a saida tem NUL: cada campo entra, separado por quebra de
  # linha, para as assercoes verem a saida INTEIRA.
  local campo
  DBX_SAIDA='' DBX_ERRO=''
  while IFS= read -r -d '' campo || [[ -n $campo ]]; do DBX_SAIDA+=$campo$'\n'; done <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_registros() { # <base> — quantos `retomada-*`
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r || -L $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}

_qa_registro() { # <base> — caminho do (unico) `retomada-*`
  local r
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && printf '%s' "$r"; done
}

# _qa_campos_ler <registro> — campos em QA_C.
QA_C=()
_qa_campos_ler() {
  local f
  QA_C=()
  while IFS= read -r -d '' f; do QA_C+=("$f"); done <"$1"
}
_qa_campos_gravar() { printf '%s\0' "${QA_C[@]}" >"$1"; }

_qa_impressao() { # <arquivo> — conteudo e metadados que nao podem mudar
  local h
  h=$(sha256sum <"$1")
  stat -c '%i %s %a %Y' -- "$1"
  printf '%s\n' "${h%% *}"
}

# ---------------------------------------------------------------------------
# Upload: ambiente e duplo
# ---------------------------------------------------------------------------

_qa_fixture_up() {
  local arquivo="$DBX_TESTES_TMP/qa7-up.bin" i
  if [[ ! -e $arquivo ]]; then
    truncate -s "$QA_TAMANHO" "$arquivo"
    for ((i = 0; i * QA_PARTE < QA_TAMANHO; i++)); do
      printf 'qa-up-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * QA_PARTE)) conv=notrunc status=none
    done
  fi
  printf '%s' "$arquivo"
}

_qa_up_ambiente() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa7u.XXXXXX")
  mkdir -p "$base/bin" "$base/tmp" "$base/trabalho" "$base/sess"
  _qa_credencial "$base"
  cp --sparse=always "$(_qa_fixture_up)" "$base/trabalho/grande.iso"
  touch -d '1 hour ago' "$base/trabalho/grande.iso"
  : >"$base/roteiro"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\nsentinela=%q\n' "$base" "$QA_SESSAO"
  } >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
export LC_ALL=C
conf=$(cat)
printf '%s\n' "$*" >>"$base/argv"
env >>"$base/ambiente"
saida=''; escrever=''; anterior=''; url=''; dados=''; cabecalhos=''; falhar=nao
for a in "$@"; do
  case $anterior in -o) saida=$a ;; -w) escrever=$a ;; --data-binary) dados=${a#@} ;; -D) cabecalhos=$a ;; esac
  case $a in http*) url=$a ;; --fail) falhar=sim ;; esac
  anterior=$a
done
arg=''
while IFS= read -r linha; do
  case $linha in 'header = "Dropbox-API-Arg: '*)
    arg=${linha#'header = "Dropbox-API-Arg: '}; arg=${arg%\"}; arg=${arg//\\\"/\"}; arg=${arg//\\\\/\\} ;;
  esac
done <<<"$conf"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\n' "$ep" >>"$base/ordinais"
n=0
while IFS= read -r l; do [[ $l == "$ep" ]] && n=$((n + 1)); done <"$base/ordinais"
printf '%s %s\n' "$ep" "$arg" >>"$base/chamadas"
acao=''
while read -r e k a; do [[ $e == "$ep" && $k == "$n" ]] && acao=$a; done <"$base/roteiro"
pid=$(<"$base/pid")
case $acao in
  SINAL:*) kill -s "${acao#SINAL:}" "$pid"; sleep 5; exit 7 ;;
esac
codigo=200 resposta='{}'
erro() { codigo=409; resposta="{\"error_summary\":\"$1\",\"error\":{\".tag\":\"${1%%/*}\"}}"; }
sid=''; off=''
[[ $arg =~ \"session_id\":\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
[[ $arg =~ \"offset\":([0-9]+) ]] && off=${BASH_REMATCH[1]}
recebe() {
  local tam h
  tam=$(wc -c <"$dados")
  if [[ $tam -gt 0 ]]; then
    h=$(sha256sum <"$dados"); h=${h%% *}
    printf '%s\n' "$h" >>"$base/sess/$sid/blocos"
  fi
  printf '%s %s %s\n' "$sid" "$off" "$tam" >>"$base/anexos"
  printf '%s' "$((off + tam))" >"$base/sess/$sid/offset"
}
case $ep in
  oauth2/token) resposta='{"access_token":"sl.QA7token","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata)
    if [[ -r $base/publicado ]]; then
      resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"0123456789a\",\"size\":$(<"$base/publicado_tamanho"),\"content_hash\":\"$(<"$base/publicado")\"}"
    else
      erro 'path/not_found/'
    fi
    ;;
  users/get_space_usage) resposta='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  files/upload_session/start)
    sid="$sentinela-$n"
    mkdir -p "$base/sess/$sid"
    printf 0 >"$base/sess/$sid/offset"
    : >"$base/sess/$sid/blocos"
    resposta="{\"session_id\":\"$sid\"}"
    ;;
  files/upload_session/append_v2)
    if [[ ! -d $base/sess/$sid ]]; then erro 'not_found/'
    elif [[ -e $base/sess/$sid/fechada ]]; then erro 'closed/'
    else
      case $acao in
        NOT_FOUND) erro 'not_found/' ;;
        OFFSET:*) codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":${acao#OFFSET:}}}" ;;
        *)
          srv=$(<"$base/sess/$sid/offset")
          if [[ $off != "$srv" ]]; then
            codigo=409; resposta="{\"error_summary\":\"incorrect_offset/\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}"
          else
            recebe
          fi
          ;;
      esac
    fi
    ;;
  files/upload_session/finish)
    if [[ ! -d $base/sess/$sid ]]; then erro 'lookup_failed/not_found/'
    elif [[ -e $base/sess/$sid/fechada ]]; then erro 'lookup_failed/closed/'
    else
      srv=$(<"$base/sess/$sid/offset")
      if [[ $off != "$srv" ]]; then
        codigo=409; resposta="{\"error_summary\":\"lookup_failed/incorrect_offset/\",\"error\":{\".tag\":\"lookup_failed\",\"lookup_failed\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$srv}}}"
      else
        recebe
        : >"$base/sess/$sid/fechada"
        : >"$base/cadeia"
        while IFS= read -r h; do
          esc=''
          for ((i = 0; i < 64; i += 2)); do esc+="\\x${h:i:2}"; done
          printf '%b' "$esc" >>"$base/cadeia"
        done <"$base/sess/$sid/blocos"
        ch=$(sha256sum <"$base/cadeia"); ch=${ch%% *}
        printf '%s' "$ch" >"$base/publicado"
        printf '%s' "$(<"$base/sess/$sid/offset")" >"$base/publicado_tamanho"
        printf '%s\n' "$sid" >>"$base/finalizadas"
        resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"0123456789a\",\"size\":1,\"content_hash\":\"$ch\",\"server_modified\":\"2026-01-01T00:00:00Z\",\"client_modified\":\"2026-01-01T00:00:00Z\"}"
      fi
    fi
    ;;
  *) erro 'sem_regra/' ;;
esac
[[ $acao == ACEITA_E_KILL ]] && { : >"$base/morto"; kill -9 "$pid"; exit 7; }
[[ -n $cabecalhos ]] && printf 'HTTP/1.1 %s X\r\n\r\n' "$codigo" >"$cabecalhos"
if [[ $falhar == sim && $codigo -ge 400 ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 22
fi
[[ -n $saida ]] && printf '%s' "$resposta" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/sleep"
  printf '%s' "$base"
}

_qa_up() { _qa_rodar "$1" upload "${@:2}" grande.iso /Grande.iso; }
_qa_roteiro() { printf '%s %s %s\n' "$2" "$3" "$4" >>"$1/roteiro"; }
_qa_conta() { _harness_contar "$2" "$1/chamadas"; }
_qa_offsets_de() { # <base> <sessao>
  local s o t lista=''
  [[ -r $1/anexos ]] || return 0
  while read -r s o t; do [[ $s == "$2" ]] && lista+="$o "; done <"$1/anexos"
  printf '%s' "$lista"
}

# _qa_up_parada <base> <k> — TERM no k-esimo `append_v2`: k-1 partes confirmadas.
_qa_up_parada() {
  _qa_roteiro "$1" files/upload_session/append_v2 "$2" SINAL:TERM
  _qa_up "$1"
  assert_igual 14 "$DBX_ESTADO" "sinal: 14 ($DBX_ERRO)"
  assert_igual 1 "$(_qa_registros "$1")" 'registro fica'
}

# _qa_up_perdida <base> <k> — a k-esima parte chega e a resposta se perde.
_qa_up_perdida() {
  _qa_roteiro "$1" files/upload_session/append_v2 "$2" ACEITA_E_KILL
  _qa_up "$1"
  assert_igual 1 "$(_qa_registros "$1")" 'registro deixado pelo kill -9'
}

# _qa_up_publicado_e_o_local <base> — o que o servidor publicou e o conteudo
# local CORRENTE, byte a byte (pelo content_hash), e a saida declara conferida.
_qa_up_publicado_e_o_local() {
  _qa_hash_para "$1/trabalho/grande.iso" "$1/hash_local"
  assert_igual "$(_qa_ler "$1/hash_local")" "$(_qa_ler "$1/publicado")" 'o publicado e o arquivo local corrente'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'conferida'
}

# _qa_stat_forjado <base> — `stat` que devolve a identidade de AGORA da origem.
_qa_stat_forjado() {
  local base=$1 real
  real=$(command -v stat)
  mkdir -p "$base/forja"
  stat -c "%s"$'\t''%Y|%y|%z|%d|%i|%s' -- "$base/trabalho/grande.iso" >"$base/forja/identidade"
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\nalvo=%q\nforja=%q\n' "$real" "$base/trabalho/grande.iso" "$base/forja/identidade"
    printf '%s\n' 'ultimo=${!#}'
    printf '%s\n' 'if [[ ${ultimo##*/} == "${alvo##*/}" && $* == *"%Y|%y|%z|%d|%i|%s"* ]]; then cat "$forja"; exit 0; fi'
    printf '%s\n' 'exec "$real" "$@"'
  } >"$base/forja/stat"
  chmod +x "$base/forja/stat"
}

_qa_byte() { printf '%s' "$3" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none; }

# ---------------------------------------------------------------------------
# Upload: o arquivo local mudou (P0-1, C1)
# ---------------------------------------------------------------------------

teste_qa_u01_sufixo_alterado_com_stat_forjado_publica_o_conteudo_corrente() {
  local base
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  _qa_stat_forjado "$base"
  # Byte alterado no SUFIXO (nunca enviado): a retomada pode seguir, mas o
  # publicado tem de ser o arquivo de agora, nunca uma mistura.
  _qa_byte "$base/trabalho/grande.iso" $((20 * QA_PARTE + 5)) 'Q'
  QA_PATH="$base/forja" _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u02_parte_em_voo_alterada_com_stat_forjado_recomeca_sem_misturar() {
  local base
  base=$(_qa_up_ambiente)
  _qa_up_perdida "$base" 4
  _qa_stat_forjado "$base"
  # A parte 4 (em voo, ja no servidor) muda localmente: o servidor diz
  # confirmado + voo, e o SHA relido nao confere.
  _qa_byte "$base/trabalho/grande.iso" $((3 * QA_PARTE + 11)) 'Q'
  QA_PATH="$base/forja" _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "recomeca: $DBX_ERRO"
  assert_igual 2 "$(_qa_conta "$base" '^files/upload_session/start ')" 'sessao nova'
  assert_igual 0 "$(_qa_conta "$base" "^files/upload_session/finish .*$QA_SESSAO-1\"")" 'a sessao antiga nunca e concluida'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u03_truncado_recomeca_e_a_sessao_antiga_nao_recebe_nada() {
  local base
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  truncate -s $((QA_TAMANHO - 1)) "$base/trabalho/grande.iso"
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" 'nada mais na sessao antiga'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u04_outro_inode_com_o_mesmo_conteudo_recomeca() {
  local base
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  cp --sparse=always "$base/trabalho/grande.iso" "$base/trabalho/copia"
  touch -r "$base/trabalho/grande.iso" "$base/trabalho/copia"
  mv -f "$base/trabalho/copia" "$base/trabalho/grande.iso"
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_igual 2 "$(_qa_conta "$base" '^files/upload_session/start ')" 'outro inode: sessao nova'
  assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" 'nada mais na sessao antiga'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u05_ligacao_fisica_nao_herda_o_registro_e_muda_o_ctime() {
  local base
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  ln "$base/trabalho/grande.iso" "$base/trabalho/elo.iso"
  # Pelo outro nome: outra chave, nenhum uso do registro de grande.iso.
  _qa_rodar "$base" upload elo.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "pelo elo: $DBX_ERRO"
  assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" 'o elo nao usa a sessao de grande.iso'
  _qa_up_publicado_e_o_local "$base"
  # Pelo nome original: o elo mudou o ctime; recomeca, nunca anexa a sessao antiga.
  rm -f "$base/publicado"
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "pelo nome original: $DBX_ERRO"
  assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" 'sessao antiga intocada'
  _qa_up_publicado_e_o_local "$base"
}

# ---------------------------------------------------------------------------
# Upload: deslocamento do servidor (P0-2, DIV-172 B)
# ---------------------------------------------------------------------------

teste_qa_u06_correct_offset_fora_do_aceito_nunca_corrompe() {
  local base valor confirmado=$((3 * QA_PARTE)) n=0
  # Registro: confirmado 12 MiB, parte em voo de 4 MiB (servidor em 16 MiB).
  for valor in $((confirmado + 2 * QA_PARTE)) $((confirmado - QA_PARTE)) $((confirmado + QA_PARTE - 1)) \
    $((confirmado + QA_PARTE + 1)) $((QA_TAMANHO + 1)) 99999999999999999999 '-4194304' '"99"' 'null' '1.6777216e7'; do
    n=$((n + 1))
    base=$(_qa_up_ambiente)
    _qa_up_perdida "$base" 4
    # O 5o append e o primeiro da execucao retomada.
    _qa_roteiro "$base" files/upload_session/append_v2 5 "OFFSET:$valor"
    _qa_up "$base"
    assert_igual 0 "$DBX_ESTADO" "correct_offset [$valor]: recomeca do zero sem falhar ($DBX_ERRO)"
    assert_igual 2 "$(_qa_conta "$base" '^files/upload_session/start ')" "correct_offset [$valor]: sessao nova"
    assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) $((3 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" \
      "correct_offset [$valor]: nada anexado a sessao antiga depois da recusa"
    assert_contem 'retomada=recomecada' "$DBX_SAIDA" "correct_offset [$valor]: recomecada"
    _qa_up_publicado_e_o_local "$base"
  done
  assert_igual 10 "$n" 'dez valores atacados'
}

teste_qa_u07_not_found_na_retomada_recomeca_e_o_resultado_e_o_local() {
  local base
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 6
  _qa_roteiro "$base" files/upload_session/append_v2 6 NOT_FOUND
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "not_found de sessao nao e 4: $DBX_ERRO"
  assert_nao_contem "$QA_SESSAO" "$DBX_SAIDA$DBX_ERRO" 'session_id fora do aviso de sessao expirada'
  _qa_up_publicado_e_o_local "$base"
}

# ---------------------------------------------------------------------------
# Upload: estado invalido descartado (P0-5)
# ---------------------------------------------------------------------------

teste_qa_u08_registro_copiado_para_o_nome_de_outra_transferencia_e_descartado() {
  local base reg_a reg_b r
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  reg_a=$(_qa_registro "$base")
  # Outra transferencia (outro arquivo, mesmo tamanho, conteudo diferente).
  cp --sparse=always "$base/trabalho/grande.iso" "$base/trabalho/outro.iso"
  _qa_byte "$base/trabalho/outro.iso" 0 'O'
  _qa_roteiro "$base" files/upload_session/append_v2 5 SINAL:TERM
  _qa_rodar "$base" upload outro.iso /Outro.iso
  assert_igual 14 "$DBX_ESTADO" "outro interrompido: $DBX_ERRO"
  reg_b=''
  for r in "$base"/estado/dbx/retomada-*; do [[ $r != "$reg_a" ]] && reg_b=$r; done
  [[ -n $reg_b ]] || _harness_falhar 'o registro da segunda transferencia deveria existir'
  # O registro de A vai para o nome de B.
  cp -f "$reg_a" "$reg_b"
  rm -f "$base/publicado"
  _qa_rodar "$base" upload outro.iso /Outro.iso
  assert_igual 0 "$DBX_ESTADO" "B conclui: $DBX_ERRO"
  assert_contem 'estado de retomada descartado' "$DBX_ERRO" 'o cabecalho de A nao autentica B'
  assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" 'a sessao de A nao recebe bytes de B'
  _qa_hash_para "$base/trabalho/outro.iso" "$base/hash_b"
  assert_igual "$(_qa_ler "$base/hash_b")" "$(_qa_ler "$base/publicado")" 'B publicado e B'
  # A continua retomavel e correto.
  rm -f "$base/publicado"
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "A retoma: $DBX_ERRO"
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'A retomado'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u09_injecao_de_nul_e_quebra_de_linha_e_outro_host_sao_descartados() {
  local base reg forma
  for forma in local_lf remoto_nul host sessao_aspas confirmado_desalinhado identidade_lf; do
    base=$(_qa_up_ambiente)
    _qa_up_parada "$base" 4
    reg=$(_qa_registro "$base")
    _qa_campos_ler "$reg"
    case $forma in
      local_lf) QA_C[14]+=$'\n' ;;
      remoto_nul) QA_C[5]=$'/Grande.iso\x01'; QA_C=("${QA_C[@]:0:6}" 'x' "${QA_C[@]:6}") ;;
      host) QA_C[4]='outro-host' ;;
      sessao_aspas) QA_C[6]='abc","offset":0,"x":"' ;;
      confirmado_desalinhado) QA_C[7]=$((3 * QA_PARTE + 1)) ;;
      identidade_lf) QA_C[11]+=$'\n' ;;
    esac
    _qa_campos_gravar "$reg"
    _qa_up "$base"
    assert_igual 0 "$DBX_ESTADO" "$forma: conclui do zero ($DBX_ERRO)"
    assert_contem 'estado de retomada descartado' "$DBX_ERRO" "$forma: aviso"
    assert_igual 0 "$(_qa_conta "$base" 'offset\":0,\"x')" "$forma: nada injetado no argumento"
    assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" "$forma: sessao antiga intocada"
    _qa_up_publicado_e_o_local "$base"
  done
}

teste_qa_u10_registro_acima_de_16_kib_e_gigante_sem_nul_sao_descartados_rapido() {
  local base reg inicio fim enchimento
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  reg=$(_qa_registro "$base")
  _qa_campos_ler "$reg"
  printf -v enchimento '%17000s' ''
  QA_C[5]+=$enchimento
  _qa_campos_gravar "$reg"
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "acima de 16 KiB: $DBX_ERRO"
  assert_contem 'estado de retomada descartado' "$DBX_ERRO" 'aviso'
  _qa_up_publicado_e_o_local "$base"
  # 64 MiB sem NUL no lugar do registro: descartado sem ler tudo.
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  reg=$(_qa_registro "$base")
  yes 'lixo-sem-nul' | head -c 67108864 >"$reg"
  inicio=$SECONDS
  _qa_up "$base"
  fim=$SECONDS
  assert_igual 0 "$DBX_ESTADO" "64 MiB sem NUL: $DBX_ERRO"
  [[ $((fim - inicio)) -lt 60 ]] || _harness_falhar 'o leitor limitado deveria parar em 16 KiB' "$((fim - inicio)) s"
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u11_upload_cache_gigante_e_tratado_como_ausente_c3() {
  local base u n=0
  base=$(_qa_up_ambiente)
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "primeiro envio: $DBX_ERRO"
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "dispensa: $DBX_ERRO"
  assert_contem 'dispensado' "$DBX_SAIDA" 'dispensado'
  for u in "$base"/estado/dbx/upload-*; do
    [[ -f $u ]] || continue
    n=$((n + 1))
    yes 'cache-sem-nul' | head -c 33554432 >"$u"
  done
  [[ $n -gt 0 ]] || _harness_falhar 'a dispensa deveria ter gravado upload-*'
  QA_TETO=60 _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "cache gigante: $DBX_ERRO"
  assert_contem 'dispensado' "$DBX_SAIDA" 'o resumo e recalculado e a dispensa vale'
  assert_igual 1 "$(_qa_conta "$base" '^files/upload_session/start ')" 'nenhuma sessao nova'
}

teste_qa_u12_registro_fifo_diretorio_e_ligacao_nao_penduram_nem_sao_tocados() {
  local base reg forma
  for forma in fifo diretorio ligacao; do
    base=$(_qa_up_ambiente)
    _qa_up_parada "$base" 4
    reg=$(_qa_registro "$base")
    rm -f "$reg"
    case $forma in
      fifo) mkfifo -m 600 "$reg" ;;
      diretorio) mkdir -m 700 "$reg" ;;
      ligacao)
        printf 'do usuario\n' >"$base/alheio.txt"
        ln -s "$base/alheio.txt" "$reg"
        ;;
    esac
    QA_TETO=60 _qa_up "$base"
    assert_igual 0 "$DBX_ESTADO" "$forma: conclui sem retomada ($DBX_ERRO)"
    case $forma in
      fifo) [[ -p $reg ]] || _harness_falhar 'a FIFO nao pode ser apagada nem trocada' ;;
      diretorio) [[ -d $reg && ! -L $reg ]] || _harness_falhar 'o diretorio nao pode ser apagado' ;;
      ligacao)
        [[ -L $reg ]] || _harness_falhar 'a ligacao nao pode ser apagada nem trocada'
        assert_igual 'do usuario' "$(_qa_ler "$base/alheio.txt")" 'o alvo da ligacao fica intacto'
        ;;
    esac
    _qa_up_publicado_e_o_local "$base"
  done
}

# ---------------------------------------------------------------------------
# Upload: trava, C6, permissoes, simulacao, sinal, diretorio inutilizavel
# ---------------------------------------------------------------------------

teste_qa_u13_trava_de_registro_ilegivel_segue_sem_retomada_sem_tocar_em_nada() {
  local base reg trava antes_reg antes_trava
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  reg=$(_qa_registro "$base")
  trava="${reg%/*}/trava-${reg##*/retomada-}"
  printf 'lixo de trava\n' >"$trava"
  chmod 600 "$trava"
  antes_reg=$(_qa_impressao "$reg")
  antes_trava=$(_qa_impressao "$trava")
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "segue sem retomada: $DBX_ERRO"
  assert_contem 'sem retomada nesta execucao' "$DBX_ERRO" 'aviso de trava'
  assert_igual "$antes_reg" "$(_qa_impressao "$reg")" 'registro alheio intocado'
  assert_igual "$antes_trava" "$(_qa_impressao "$trava")" 'trava ilegivel intocada'
  assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" 'sessao do registro intocada'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u14_session_id_fora_de_argv_ambiente_saidas_e_arquivos() {
  local base f modo vazou=''
  base=$(_qa_up_ambiente)
  _qa_roteiro "$base" files/upload_session/append_v2 4 SINAL:TERM
  _qa_rodar "$base" --debug upload --progresso grande.iso /Grande.iso
  assert_nao_contem "$QA_SESSAO" "$DBX_SAIDA$DBX_ERRO" 'interrompido com --debug e progresso'
  _qa_roteiro "$base" files/upload_session/append_v2 4 OFFSET:1
  _qa_rodar "$base" --debug upload --progresso grande.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "recomecado: $DBX_ERRO"
  assert_nao_contem "$QA_SESSAO" "$DBX_SAIDA$DBX_ERRO" 'recomeco por deslocamento com --debug'
  _qa_roteiro "$base" files/upload_session/append_v2 6 SINAL:INT
  rm -f "$base/publicado"
  _qa_rodar "$base" upload grande.iso /Grande.iso
  for modo in '' --json --null --debug; do
    _qa_rodar "$base" ${modo:+"$modo"} diagnostico
    assert_nao_contem "$QA_SESSAO" "$DBX_SAIDA$DBX_ERRO" "diagnostico ${modo:-texto}"
  done
  for modo in --json --null; do
    rm -f "$base/publicado"
    _qa_rodar "$base" "$modo" upload grande.iso /Grande.iso
    assert_nao_contem "$QA_SESSAO" "$DBX_SAIDA$DBX_ERRO" "upload $modo"
  done
  assert_nao_contem "$QA_SESSAO" "$(tr '\0' '\n' <"$base/argv")" 'session_id fora do argv do curl'
  assert_nao_contem "$QA_SESSAO" "$(tr '\0' '\n' <"$base/ambiente")" 'session_id fora do ambiente do curl'
  # Nenhum arquivo do usuario, temporario ou de estado alem do registro.
  while IFS= read -r -d '' f; do
    case $f in
      "$base"/sess/* | "$base"/chamadas | "$base"/anexos | "$base"/finalizadas | "$base"/estado/dbx/retomada-*) continue ;;
    esac
    grep -q -a -- "$QA_SESSAO" "$f" 2>/dev/null && vazou+=" $f"
  done < <(find "$base" -type f ! -name curl -print0)
  assert_igual '' "$vazou" 'session_id em arquivo fora do registro'
}

teste_qa_u15_umask_000_registro_0600_diretorio_0700_e_sem_temporario() {
  local base reg t
  base=$(_qa_up_ambiente)
  _qa_roteiro "$base" files/upload_session/append_v2 4 SINAL:TERM
  QA_UMASK=000 _qa_up "$base"
  assert_igual 14 "$DBX_ESTADO" "interrompido: $DBX_ERRO"
  reg=$(_qa_registro "$base")
  assert_igual 600 "$(stat -c %a "$reg")" 'registro 0600 com umask 000'
  assert_igual 700 "$(stat -c %a "$base/estado/dbx")" 'diretorio 0700 com umask 000'
  for t in "$base"/estado/dbx/.retomada.* "$base"/estado/dbx/trava-*; do
    [[ -e $t ]] && _harness_falhar 'temporario ou trava sobrou depois do sinal' "$t"
  done
  QA_UMASK=000 _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u16_dry_run_e_sem_retomada_nao_leem_nem_gravam_estado() {
  local base reg antes antes_dir opcao
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  reg=$(_qa_registro "$base")
  antes=$(_qa_impressao "$reg")
  antes_dir=$(ls -la --time-style=+%s "$base/estado/dbx")
  for opcao in '--dry-run upload' '--dry-run upload --sem-retomada' '--dry-run upload --no-resume' '--dry-run --json upload'; do
    # shellcheck disable=SC2086  # a opcao e a palavra do comando, de proposito
    _qa_rodar "$base" $opcao grande.iso /Grande.iso
    assert_igual 0 "$DBX_ESTADO" "[$opcao]: $DBX_ERRO"
    assert_igual "$antes" "$(_qa_impressao "$reg")" "[$opcao]: registro intocado"
    assert_igual "$antes_dir" "$(ls -la --time-style=+%s "$base/estado/dbx")" "[$opcao]: diretorio de estado igual"
  done
  assert_igual 1 "$(_qa_conta "$base" '^files/upload_session/start ')" 'simulacao sem sessao'
  _qa_rodar "$base" upload --sem-retomada grande.iso /Grande.iso
  assert_igual 0 "$DBX_ESTADO" "sem retomada: $DBX_ERRO"
  assert_igual "$antes" "$(_qa_impressao "$reg")" '--sem-retomada nao le, nao grava, nao apaga'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u17_sinal_na_execucao_retomada_avanca_o_registro_e_a_seguinte_conclui() {
  local base reg
  base=$(_qa_up_ambiente)
  _qa_up_parada "$base" 4
  _qa_roteiro "$base" files/upload_session/append_v2 9 SINAL:INT
  _qa_up "$base"
  assert_igual 14 "$DBX_ESTADO" "INT na retomada: $DBX_ERRO"
  reg=$(_qa_registro "$base")
  _qa_campos_ler "$reg"
  assert_igual $((7 * QA_PARTE)) "${QA_C[7]}" 'confirmado avancou para o que o servidor confirmou'
  _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "terceira execucao: $DBX_ERRO"
  assert_contem "retomado_de=$((7 * QA_PARTE))" "$DBX_SAIDA" 'retomado do novo confirmado'
  assert_igual 1 "$(_qa_conta "$base" '^files/upload_session/start ')" 'uma sessao so'
  _qa_up_publicado_e_o_local "$base"
}

teste_qa_u18_diretorio_de_estado_inutilizavel_segue_sem_retomada() {
  local base forma
  for forma in arquivo ligacao_quebrada; do
    base=$(_qa_up_ambiente)
    mkdir -p "$base/estado"
    case $forma in
      arquivo) printf 'nao e diretorio\n' >"$base/estado/dbx" ;;
      ligacao_quebrada) ln -s "$base/nao-existe" "$base/estado/dbx" ;;
    esac
    _qa_up "$base"
    assert_igual 0 "$DBX_ESTADO" "$forma: codigo normal ($DBX_ERRO)"
    case $forma in
      arquivo) assert_igual 'nao e diretorio' "$(_qa_ler "$base/estado/dbx")" 'arquivo intocado' ;;
      ligacao_quebrada) [[ -L $base/estado/dbx && ! -e $base/nao-existe ]] || _harness_falhar 'a ligacao nao pode ser seguida' ;;
    esac
    _qa_up_publicado_e_o_local "$base"
  done
}

# ---------------------------------------------------------------------------
# Download: ambiente e duplo
# ---------------------------------------------------------------------------

_qa_fixture_down() { # <versao>
  local versao=$1 arquivo="$DBX_TESTES_TMP/qa7-down-$1.bin" i
  if [[ ! -e $arquivo ]]; then
    truncate -s "$QA_TAMANHO" "$arquivo"
    for ((i = 0; i * QA_PARTE < QA_TAMANHO; i++)); do
      printf 'qa-down-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * QA_PARTE)) conv=notrunc status=none
    done
    [[ $versao == 2 ]] && printf 'V2' | dd of="$arquivo" bs=1 seek=$((QA_TAMANHO - 7)) conv=notrunc status=none
    _qa_hash_para "$arquivo" "$arquivo.hash"
  fi
  printf '%s' "$arquivo"
}

_qa_versao() { # <base> <1|2>
  local remoto
  remoto=$(_qa_fixture_down "$2")
  ln -sf "$remoto" "$1/remoto.bin"
  cp "$remoto.hash" "$1/hash"
  if [[ $2 == 1 ]]; then printf '%s' "$QA_REV1" >"$1/rev"; else printf '%s' "$QA_REV2" >"$1/rev"; fi
}

_qa_down_ambiente() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa7d.XXXXXX")
  mkdir -p "$base/bin" "$base/tmp" "$base/trabalho"
  _qa_credencial "$base"
  _qa_versao "$base" 1
  printf '#!%s\nbase=%q\n' "$BASH" "$base" >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
export LC_ALL=C
conf=$(cat)
saida=''; escrever=''; anterior=''; url=''; dados=''; cabecalhos=''; falhar=nao
for a in "$@"; do
  case $anterior in -o) saida=$a ;; -w) escrever=$a ;; --data-binary) dados=${a#@} ;; -D) cabecalhos=$a ;; esac
  case $a in http*) url=$a ;; --fail) falhar=sim ;; esac
  anterior=$a
done
arg='' inicio=''
while IFS= read -r linha; do
  case $linha in
    'header = "Dropbox-API-Arg: '*) arg=${linha#'header = "Dropbox-API-Arg: '}; arg=${arg%\"}; arg=${arg//\\\"/\"} ;;
    'continue-at = '*) inicio=${linha#continue-at = } ;;
  esac
done <<<"$conf"
corpo=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' corpo <"$dados"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s %s%s %s\n' "$ep" "$arg" "$corpo" "$inicio" >>"$base/chamadas"
rev=$(<"$base/rev"); hash=$(<"$base/hash"); tam=$(wc -c <"$base/remoto.bin")
modo=''; [[ -r $base/modo ]] && modo=$(<"$base/modo")
codigo=200 resposta='{}' faixa='' resultado=''
erro_download() { codigo=409; resposta="{\"error_summary\":\"$1\"}"; }
cabecalho() {
  [[ -n $cabecalhos ]] || return 0
  {
    printf 'HTTP/1.1 %s X\r\n' "$codigo"
    [[ -n $faixa ]] && printf 'Content-Range: %s\r\n' "$faixa"
    [[ -n $resultado ]] && printf 'Dropbox-API-Result: %s\r\n' "$resultado"
    printf '\r\n'
  } >"$cabecalhos"
}
# corpo <inicio> — entrega do inicio ao fim, ou ate `corte` bytes (rede cai).
# fonte — o conteudo remoto servido (com um byte trocado em `errado_sempre`).
fonte() {
  if [[ $modo == errado_sempre ]]; then
    { head -c 1000 "$base/remoto.bin"; printf 'X'; tail -c +1002 "$base/remoto.bin"; }
  else
    cat "$base/remoto.bin"
  fi
}
corpo() {
  local de=$1
  if [[ -r $base/corte ]]; then
    fonte | tail -c +$((de + 1)) | head -c "$(<"$base/corte")" >>"$saida"
    rm -f "$base/corte"
    if [[ -r $base/sinal ]]; then
      kill -s "$(<"$base/sinal")" "$(<"$base/pid")"; rm -f "$base/sinal"; sleep 5
    fi
    [[ -n $escrever ]] && printf '%s' "$codigo"
    exit 18
  fi
  fonte | tail -c +$((de + 1)) >>"$saida"
}
case $ep in
  oauth2/token) resposta='{"access_token":"sl.QA7tokenD","token_type":"bearer","expires_in":14400}' ;;
  auth/token/revoke) resposta='null' ;;
  files/get_metadata)
    resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"$rev\",\"size\":$tam,\"content_hash\":\"$hash\"}"
    ;;
  files/download)
    [[ $arg =~ \"path\":\"([^\"]*)\" ]] && caminho=${BASH_REMATCH[1]}
    if [[ $caminho == rev:* && ${caminho#rev:} != "$rev" ]]; then
      erro_download 'path/not_found/'
    else
      rres=$rev
      [[ $modo == rev ]] && rres='fffffffffff'
      resultado="{\"name\":\"grande.iso\",\"rev\":\"$rres\",\"size\":$tam,\"content_hash\":\"$hash\"}"
      if [[ -n $inicio ]]; then
        if [[ $inicio -ge $tam ]]; then
          codigo=416; faixa="bytes */$tam"; resultado=''
          cabecalho; [[ -n $escrever ]] && printf '%s' "$codigo"; exit 0
        fi
        codigo=206; faixa="bytes $inicio-$((tam - 1))/$tam"
        cabecalho
        corpo "$inicio"
      else
        cabecalho
        : >"$saida"
        corpo 0
      fi
      [[ -n $escrever ]] && printf '%s' "$codigo"
      exit 0
    fi
    ;;
  *) erro_download 'sem_regra/' ;;
esac
cabecalho
if [[ $falhar == sim && $codigo -ge 400 ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 22
fi
[[ -n $saida ]] && printf '%s' "$resposta" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  printf '#!%s\nexit 0\n' "$BASH" >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/sleep"
  printf '%s' "$base"
}

_qa_down() { _qa_rodar "$1" download "${@:2}" /Grande.iso grande.iso; }
_qa_parts() { # <base> — nomes dos `.part` (e do que ocupa o lugar) no diretorio do alvo
  local p lista=''
  for p in "$1"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p || -L $p ]] && lista+="${p##*/} "; done
  printf '%s' "$lista"
}
_qa_part() { # <base> — o (primeiro) `.part`
  local p
  for p in "$1"/trabalho/.grande.iso.dbx-part.*; do
    [[ -e $p || -L $p ]] && { printf '%s' "$p"; return 0; }
  done
}
_qa_alvo_e_o_remoto() {
  cmp -s "$1/trabalho/grande.iso" "$1/remoto.bin" || _harness_falhar "${2:-o destino deveria ser o remoto}"
}

# _qa_down_cortado <base> [bytes] — a rede cai depois de <bytes>.
_qa_down_cortado() {
  printf '%s' "${2:-$((40 * 1048576 + 7))}" >"$1/corte"
  _qa_down "$1"
  assert_igual 9 "$DBX_ESTADO" "rede: $DBX_ERRO"
  assert_igual 1 "$(_qa_registros "$1")" 'registro gravado'
  [[ -n $(_qa_part "$1") ]] || _harness_falhar 'o .part deveria ficar'
}

# ---------------------------------------------------------------------------
# Download: barreira do `.part` (P0-4)
# ---------------------------------------------------------------------------

teste_qa_d01_part_trocado_por_fifo_ou_diretorio_nao_pendura_nem_e_tocado() {
  local base part forma
  for forma in fifo diretorio; do
    base=$(_qa_down_ambiente)
    _qa_down_cortado "$base"
    part=$(_qa_part "$base")
    rm -f "$part"
    case $forma in
      fifo) mkfifo -m 600 "$part" ;;
      diretorio) mkdir -m 700 "$part" ;;
    esac
    QA_TETO=60 _qa_down "$base"
    assert_igual 0 "$DBX_ESTADO" "$forma: conclui com .part novo ($DBX_ERRO)"
    _qa_alvo_e_o_remoto "$base" "$forma: destino correto"
    case $forma in
      fifo) [[ -p $part ]] || _harness_falhar 'a FIFO no lugar do .part nao pode ser apagada' ;;
      diretorio) [[ -d $part ]] || _harness_falhar 'o diretorio no lugar do .part nao pode ser apagado' ;;
    esac
    assert_igual 0 "$(_qa_registros "$base")" "$forma: registro removido no sucesso"
    # unlink: nao apaga e nao pendura.
    QA_TETO=60 _qa_rodar "$base" unlink --confirmar
    case $forma in
      fifo) [[ -p $part ]] || _harness_falhar 'unlink apagou a FIFO' ;;
      diretorio) [[ -d $part ]] || _harness_falhar 'unlink apagou o diretorio' ;;
    esac
  done
}

teste_qa_d02_part_trocado_por_ligacao_fisica_a_arquivo_do_usuario_fica_intacto() {
  local base part antes
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  part=$(_qa_part "$base")
  mkdir -p "$base/pessoal"
  head -c 1000 /dev/urandom >"$base/pessoal/diario.txt"
  antes=$(_qa_impressao "$base/pessoal/diario.txt")
  rm -f "$part"
  ln "$base/pessoal/diario.txt" "$part"
  _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base"
  assert_igual "$antes" "$(_qa_impressao "$base/pessoal/diario.txt")" 'o arquivo do usuario nao recebe bytes'
  [[ -e $part ]] || _harness_falhar 'o elo no lugar do .part nao pode ser apagado'
  _qa_rodar "$base" unlink --confirmar
  assert_igual "$antes" "$(_qa_impressao "$base/pessoal/diario.txt")" 'unlink nao toca no arquivo do usuario'
}

teste_qa_d03_part_ligacao_simbolica_para_fora_e_listada_pelo_unlink_sem_apagar() {
  local base part antes
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  part=$(_qa_part "$base")
  mkdir -p "$base/pessoal"
  printf 'conteudo do usuario\n' >"$base/pessoal/doc.txt"
  antes=$(_qa_impressao "$base/pessoal/doc.txt")
  rm -f "$part"
  ln -s "$base/pessoal/doc.txt" "$part"
  _qa_rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink: $DBX_ERRO"
  [[ -L $part ]] || _harness_falhar 'a ligacao nao pode ser apagada'
  assert_igual "$antes" "$(_qa_impressao "$base/pessoal/doc.txt")" 'o alvo da ligacao intacto'
  assert_contem '1 arquivo(s) parcial(is)' "$DBX_ERRO" 'quantos'
  assert_contem "${part##*/}" "$DBX_ERRO" 'lista o caminho'
}

teste_qa_d04_unlink_com_nome_de_part_com_quebra_de_linha_cita_sem_byte_cru() {
  local base reg
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  reg=$(_qa_registro "$base")
  _qa_campos_ler "$reg"
  # Registro (legivel) aponta um `.part` cujo nome tem quebra de linha e ESC;
  # existe um arquivo do usuario com esse nome, de outro inode.
  QA_C[9]=$'.x\nfalha=FORJADA\e[31m.dbx-part.ABCDEF'
  _qa_campos_gravar "$reg"
  printf 'do usuario\n' >"$base/trabalho/${QA_C[9]}"
  _qa_rodar "$base" unlink --confirmar
  [[ -e $base/trabalho/${QA_C[9]} ]] || _harness_falhar 'o arquivo do usuario com nome no padrao nao pode ser apagado'
  assert_nao_contem $'\nfalha=FORJADA' "$DBX_ERRO" 'nenhuma quebra de linha crua na listagem'
  assert_nao_contem $'\e[31m' "$DBX_ERRO" 'nenhum ESC cru na listagem'
}

# ---------------------------------------------------------------------------
# Download: resposta e conferencia (P0-3)
# ---------------------------------------------------------------------------

teste_qa_d05_part_adulterado_no_prefixo_recomeca_e_nunca_troca_com_divergencia() {
  local base part antes
  base=$(_qa_down_ambiente)
  printf 'alvo anterior\n' >"$base/trabalho/grande.iso"
  _qa_down_cortado "$base"
  part=$(_qa_part "$base")
  _qa_byte "$part" 77 'Z'
  _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "recomeca uma vez e conclui: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base" 'o destino e o remoto, nunca o .part adulterado'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
  [[ -z $(_qa_parts "$base") ]] || _harness_falhar 'sem .part residual' "$(_qa_parts "$base")"
  # Remoto que sempre diverge do content_hash: 11, destino intacto.
  base=$(_qa_down_ambiente)
  printf 'alvo anterior\n' >"$base/trabalho/grande.iso"
  antes=$(_qa_impressao "$base/trabalho/grande.iso")
  printf 'errado_sempre' >"$base/modo"
  _qa_down_cortado "$base"
  _qa_down "$base"
  assert_igual 11 "$DBX_ESTADO" "divergencia persistente: $DBX_ERRO"
  assert_igual "$antes" "$(_qa_impressao "$base/trabalho/grande.iso")" 'destino intacto'
}

teste_qa_d06_206_com_rev_diferente_no_resultado_nunca_e_usado() {
  local base antes
  base=$(_qa_down_ambiente)
  printf 'alvo anterior\n' >"$base/trabalho/grande.iso"
  antes=$(_qa_impressao "$base/trabalho/grande.iso")
  _qa_down_cortado "$base"
  printf 'rev' >"$base/modo"
  _qa_down "$base"
  # Recomeco do zero pelo recebimento de hoje: ele tambem ve a rev errada.
  [[ $DBX_ESTADO -ne 0 ]] || _qa_alvo_e_o_remoto "$base" 'sucesso so com o conteudo certo'
  if [[ $DBX_ESTADO -ne 0 ]]; then
    assert_igual "$antes" "$(_qa_impressao "$base/trabalho/grande.iso")" 'falha deixa o destino intacto'
  fi
  assert_igual 1 "$(_qa_conta "$base" "^files/download .*rev:$QA_REV1.* $((40 * 1048576 + 7))\$")" 'uma faixa pedida'
}

teste_qa_d07_varias_quedas_durante_a_faixa_cada_uma_continua_do_tamanho_do_part() {
  local base part
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base" 1000003
  part=$(_qa_part "$base")
  printf '%s' 30000001 >"$base/corte"
  _qa_down "$base"
  assert_igual 9 "$DBX_ESTADO" "segunda queda: $DBX_ERRO"
  assert_igual $((1000003 + 30000001)) "$(stat -c %s "$part")" 'o .part cresceu so com o recebido'
  printf '%s' 7 >"$base/corte"
  _qa_down "$base"
  assert_igual 9 "$DBX_ESTADO" "terceira queda: $DBX_ERRO"
  _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base"
  assert_contem "retomado_de=$((1000003 + 30000001 + 7))" "$DBX_SAIDA" 'do tamanho do .part'
  assert_igual 1 "$(_qa_conta "$base" "^files/download .* 1000003\$")" 'faixa 1'
  assert_igual 1 "$(_qa_conta "$base" "^files/download .* $((1000003 + 30000001))\$")" 'faixa 2'
  assert_igual 1 "$(_qa_conta "$base" "^files/download .* $((1000003 + 30000001 + 7))\$")" 'faixa 3'
  assert_igual 0 "$(_qa_conta "$base" '^files/download {"path":"/')" 'nunca sem rev:'
}

teste_qa_d08_remoto_trocado_de_mesmo_tamanho_nunca_mistura_revisoes() {
  local base
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  _qa_versao "$base" 2
  _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base" 'o destino e inteiro da revisao 2'
  assert_igual 0 "$(_qa_conta "$base" "^files/download .*rev:$QA_REV2.* [0-9][0-9]*\$")" 'nenhuma faixa da revisao nova sobre o .part antigo'
  [[ -z $(_qa_parts "$base") ]] || _harness_falhar 'o .part antigo sai pela barreira' "$(_qa_parts "$base")"
}

# ---------------------------------------------------------------------------
# Download: simulacao, opcao, sinal, diretorio de estado, estado invalido
# ---------------------------------------------------------------------------

teste_qa_d09_dry_run_e_sem_retomada_nao_tocam_registro_nem_part() {
  local base reg part antes_reg antes_part opcao
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  reg=$(_qa_registro "$base")
  part=$(_qa_part "$base")
  antes_reg=$(_qa_impressao "$reg")
  antes_part=$(_qa_impressao "$part")
  : >"$base/chamadas"
  for opcao in '--dry-run download' '--dry-run --json download' '--dry-run download --sem-retomada'; do
    # shellcheck disable=SC2086
    _qa_rodar "$base" $opcao /Grande.iso grande.iso
    assert_igual 0 "$DBX_ESTADO" "[$opcao]: $DBX_ERRO"
  done
  assert_igual 0 "$(_qa_conta "$base" '^files/')" 'simulacao sem chamada de arquivo'
  for opcao in --sem-retomada --no-resume; do
    rm -f "$base/trabalho/grande.iso"
    _qa_down "$base" "$opcao"
    assert_igual 0 "$DBX_ESTADO" "[$opcao]: $DBX_ERRO"
    _qa_alvo_e_o_remoto "$base"
  done
  assert_igual "$antes_reg" "$(_qa_impressao "$reg")" 'registro intocado'
  assert_igual "$antes_part" "$(_qa_impressao "$part")" '.part intocado'
  assert_igual 0 "$(_qa_conta "$base" '^files/download .* [0-9][0-9]*$')" 'nenhuma faixa pedida'
  [[ ! -e $base/estado/dbx/trava-${reg##*/retomada-} ]] || _harness_falhar 'trava de registro criada'
}

teste_qa_d10_sinal_durante_a_faixa_preserva_part_e_registro() {
  local base part tamanho
  base=$(_qa_down_ambiente)
  printf 'alvo anterior\n' >"$base/trabalho/grande.iso"
  _qa_down_cortado "$base"
  part=$(_qa_part "$base")
  printf '%s' 5000000 >"$base/corte"
  printf 'TERM' >"$base/sinal"
  _qa_down "$base"
  assert_igual 14 "$DBX_ESTADO" "sinal: $DBX_ERRO"
  assert_igual 'alvo anterior' "$(_qa_ler "$base/trabalho/grande.iso")" 'destino intacto'
  assert_igual 1 "$(_qa_registros "$base")" 'registro preservado'
  [[ -f $part ]] || _harness_falhar '.part preservado'
  tamanho=$(stat -c %s "$part")
  _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  assert_contem "retomado_de=$tamanho" "$DBX_SAIDA" 'continua do .part'
  _qa_alvo_e_o_remoto "$base"
}

teste_qa_d11_diretorio_de_estado_inutilizavel_recebe_sem_residuo() {
  local base
  base=$(_qa_down_ambiente)
  mkdir -p "$base/estado"
  printf 'nao e diretorio\n' >"$base/estado/dbx"
  _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "codigo normal: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base"
  [[ -z $(_qa_parts "$base") ]] || _harness_falhar 'sem .part residual' "$(_qa_parts "$base")"
  assert_igual 'nao e diretorio' "$(_qa_ler "$base/estado/dbx")" 'arquivo intocado'
}

teste_qa_d12_registro_de_download_copiado_para_outro_alvo_nao_anexa_ao_part_alheio() {
  local base reg_a reg_b r part_a antes
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  reg_a=$(_qa_registro "$base")
  part_a=$(_qa_part "$base")
  antes=$(_qa_impressao "$part_a")
  printf '%s' $((1048576 + 1)) >"$base/corte"
  _qa_rodar "$base" download /Grande.iso outro.iso
  assert_igual 9 "$DBX_ESTADO" "outro interrompido: $DBX_ERRO"
  reg_b=''
  for r in "$base"/estado/dbx/retomada-*; do [[ $r != "$reg_a" ]] && reg_b=$r; done
  [[ -n $reg_b ]] || _harness_falhar 'registro do segundo alvo'
  cp -f "$reg_a" "$reg_b"
  _qa_rodar "$base" download /Grande.iso outro.iso
  assert_igual 0 "$DBX_ESTADO" "outro conclui: $DBX_ERRO"
  cmp -s "$base/trabalho/outro.iso" "$base/remoto.bin" || _harness_falhar 'outro.iso correto'
  assert_igual "$antes" "$(_qa_impressao "$part_a")" 'o .part de grande.iso nao recebe bytes de outro alvo'
}

# QA-B7A-02 (P2): o registro LEGIVEL descartado por cabecalho divergente (aqui,
# o mesmo remoto com outra caixa) sai sem o `.part` que ele descreve passar
# pela barreira. O `.part` fica no disco, de 40 MiB a GB, e some do
# `diagnostico` e do `unlink` (o registro que o listaria foi apagado).
teste_qa_d13_registro_descartado_por_cabecalho_nao_deixa_part_invisivel() {
  local base p orfaos=''
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  _qa_rodar "$base" download /grande.ISO grande.iso
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base"
  for p in "$base"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p ]] && orfaos+=" ${p##*/}"; done
  assert_igual 0 "$(_qa_registros "$base")" 'nenhum registro sobra'
  assert_igual '' "$orfaos" 'QA-B7A-02: .part sem registro, invisivel ao diagnostico e ao unlink'
}

# ---------------------------------------------------------------------------
# Diagnostico e unlink diante de `retomada-*` hostil
# ---------------------------------------------------------------------------

# QA-B7A-01 (P1): `dbx_state_retomada_listar` abre cada `retomada-*` pelo leitor
# limitado sem conferir antes que e arquivo regular; a abertura de uma FIFO
# bloqueia para sempre. `diagnostico` e `unlink --confirmar` (este depois de
# revogar o token e apagar a credencial) penduram.
teste_qa_l01_fifo_retomada_nao_pendura_diagnostico() {
  local base
  base=$(_qa_down_ambiente)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  mkfifo -m 600 "$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef"
  QA_TETO=20 _qa_rodar "$base" diagnostico
  assert_contem 'retomada' "$DBX_SAIDA" 'a FIFO aparece como ilegivel'
  [[ -p $base/estado/dbx/retomada-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'diagnostico so le'
}

teste_qa_l02_fifo_retomada_nao_pendura_unlink() {
  local base
  base=$(_qa_down_ambiente)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  mkfifo -m 600 "$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef"
  QA_TETO=20 _qa_rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink conclui: $DBX_ERRO"
}

teste_qa_l03_diagnostico_cita_caminhos_hostis_e_nao_vaza_sessao() {
  local base modo zeros
  base=$(_qa_down_ambiente)
  printf -v zeros '%064d' 0
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  printf '%s\0' dbx-retomada 1 upload cred-0123456789abcdef0123456789abcdef qahost $'/R\nok=FORJADO' \
    "$QA_SESSAO" "$QA_PARTE" 0 - "$QA_TAMANHO" \
    '1|2026-01-01 00:00:00.000000000 +0000|2026-01-01 00:00:00.000000000 +0000|1|2|157286403' 1 \
    "$zeros" $'/tmp/x\nfalha=FORJADA\e[31m.iso' >"$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef"
  chmod 600 "$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef"
  for modo in '' --json --null; do
    _qa_rodar "$base" ${modo:+"$modo"} diagnostico
    assert_nao_contem "$QA_SESSAO" "$DBX_SAIDA$DBX_ERRO" "session_id fora do diagnostico ${modo:-texto}"
    assert_contem 'retomada' "$DBX_SAIDA" "linha retomada ${modo:-texto}"
  done
  _qa_rodar "$base" diagnostico
  assert_nao_contem $'\nfalha=FORJADA' "$DBX_SAIDA" 'texto: quebra de linha citada'
  assert_nao_contem $'\e[31m' "$DBX_SAIDA" 'texto: ESC citado'
  _qa_rodar "$base" --json diagnostico
  assert_nao_contem $'\e[31m' "$DBX_SAIDA" 'json: ESC citado'
}

# ---------------------------------------------------------------------------
# Ciclo 2: reataque das correcoes de QA-B7A-01 e QA-B7A-02
# ---------------------------------------------------------------------------

# _qa_socket <caminho> — socket de dominio local (so com python3; sem ele, nada).
_qa_socket() {
  command -v python3 >/dev/null 2>&1 || return 0
  python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])' "$1"
}

# Entradas hostis em TODOS os namespaces do diretorio de estado: FIFO e
# socket em `retomada-*`, `trava-*`, `upload-*` e `memoria-*`, e ligacao
# simbolica para FIFO. Nenhum comando que le estado pode pendurar nem apagar
# o que nao e dele.
_qa_estado_hostil() { # <base>
  local d="$1/estado/dbx" fifo="$1/fora.fifo"
  mkdir -p "$d"
  chmod 700 "$d"
  mkfifo -m 600 "$d/retomada-0123456789abcdef0123456789abcdef"
  mkfifo -m 600 "$d/trava-0123456789abcdef0123456789abcdef"
  mkfifo -m 600 "$d/upload-0123456789abcdef0123456789abcdef"
  mkfifo -m 600 "$d/memoria-0123456789abcdef0123456789abcdef"
  mkfifo -m 600 "$fifo"
  ln -s "$fifo" "$d/retomada-11111111111111111111111111111111"
  ln -s "$fifo" "$d/trava-11111111111111111111111111111111"
  _qa_socket "$d/retomada-22222222222222222222222222222222"
  _qa_socket "$d/trava-22222222222222222222222222222222"
}

teste_qa_l04_entradas_nao_regulares_em_todo_namespace_nao_penduram_diagnostico() {
  local base
  base=$(_qa_down_ambiente)
  _qa_estado_hostil "$base"
  QA_TETO=30 _qa_rodar "$base" diagnostico
  [[ $DBX_ESTADO -le 15 ]] || _harness_falhar "codigo fora de 0..15: $DBX_ESTADO"
  assert_contem 'retomada' "$DBX_SAIDA" 'as entradas aparecem como ilegiveis'
  [[ -p $base/estado/dbx/retomada-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'diagnostico so le'
  [[ -p $base/estado/dbx/trava-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'diagnostico so le (trava)'
}

teste_qa_l05_entradas_nao_regulares_nao_penduram_unlink_e_o_fora_fica() {
  local base
  base=$(_qa_down_ambiente)
  _qa_estado_hostil "$base"
  QA_TETO=30 _qa_rodar "$base" unlink --confirmar
  [[ $DBX_ESTADO -le 15 ]] || _harness_falhar "codigo fora de 0..15: $DBX_ESTADO"
  [[ -p $base/fora.fifo ]] || _harness_falhar 'a FIFO fora do estado, alvo de ligacao, nao pode ser tocada'
}

teste_qa_l06_entradas_nao_regulares_nao_penduram_upload_download_nem_poda() {
  local base
  base=$(_qa_up_ambiente)
  _qa_estado_hostil "$base"
  # Registro com mais de 8 dias no mesmo diretorio: a primeira gravacao poda.
  touch -d '10 days ago' "$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef" 2>/dev/null || :
  QA_TETO=60 _qa_up "$base"
  assert_igual 0 "$DBX_ESTADO" "upload: $DBX_ERRO"
  _qa_up_publicado_e_o_local "$base"
  [[ -p $base/estado/dbx/retomada-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'a poda nao apaga nao regular'
  [[ -p $base/estado/dbx/upload-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'upload-* nao regular intocado'
  base=$(_qa_down_ambiente)
  _qa_estado_hostil "$base"
  QA_TETO=60 _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "download: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base"
}

teste_qa_u19_trava_do_registro_fifo_ou_ligacao_para_fifo_segue_sem_retomada() {
  local base reg trava forma
  for forma in fifo ligacao; do
    base=$(_qa_up_ambiente)
    _qa_up_parada "$base" 4
    reg=$(_qa_registro "$base")
    trava="${reg%/*}/trava-${reg##*/retomada-}"
    case $forma in
      fifo) mkfifo -m 600 "$trava" ;;
      ligacao)
        mkfifo -m 600 "$base/fora.fifo"
        ln -s "$base/fora.fifo" "$trava"
        ;;
    esac
    QA_TETO=60 _qa_up "$base"
    assert_igual 0 "$DBX_ESTADO" "$forma: segue sem retomada ($DBX_ERRO)"
    assert_contem 'sem retomada nesta execucao' "$DBX_ERRO" "$forma: aviso"
    [[ -p $trava || -L $trava ]] || _harness_falhar "$forma: a trava nao regular nao pode ser apagada"
    assert_igual "0 $QA_PARTE $((2 * QA_PARTE)) " "$(_qa_offsets_de "$base" "$QA_SESSAO-1")" "$forma: sessao intocada"
    _qa_up_publicado_e_o_local "$base"
  done
}

teste_qa_d14_trava_do_registro_fifo_no_download_nao_pendura_nem_toca_o_part() {
  local base reg part antes
  base=$(_qa_down_ambiente)
  _qa_down_cortado "$base"
  reg=$(_qa_registro "$base")
  part=$(_qa_part "$base")
  antes=$(_qa_impressao "$part")
  mkfifo -m 600 "${reg%/*}/trava-${reg##*/retomada-}"
  QA_TETO=60 _qa_down "$base"
  assert_igual 0 "$DBX_ESTADO" "segue sem retomada: $DBX_ERRO"
  _qa_alvo_e_o_remoto "$base"
  assert_igual "$antes" "$(_qa_impressao "$part")" 'o .part do registro travado nao e tocado'
}

# O alvo por outra grafia do MESMO arquivo (diretorio pai por ligacao
# simbolica, `..` no caminho) e o mesmo alvo canonico: retoma, e nenhum
# `.part` sobra.
teste_qa_d15_mesmo_alvo_por_ligacao_no_pai_ou_caminho_relativo_retoma_sem_orfao() {
  local base destino p orfaos
  for destino in elo/grande.iso real/../real/grande.iso ./real//grande.iso; do
    base=$(_qa_down_ambiente)
    mkdir -p "$base/trabalho/real"
    ln -s real "$base/trabalho/elo"
    printf '%s' $((40 * 1048576 + 7)) >"$base/corte"
    _qa_rodar "$base" download /Grande.iso real/grande.iso
    assert_igual 9 "$DBX_ESTADO" "$destino: interrompido ($DBX_ERRO)"
    _qa_rodar "$base" download /Grande.iso "$destino"
    assert_igual 0 "$DBX_ESTADO" "$destino: conclui ($DBX_ERRO)"
    cmp -s "$base/trabalho/real/grande.iso" "$base/remoto.bin" || _harness_falhar "$destino: destino correto"
    assert_contem 'retomada=sim' "$DBX_SAIDA" "$destino: mesmo alvo canonico retoma"
    orfaos=''
    for p in "$base"/trabalho/real/.grande.iso.dbx-part.*; do [[ -e $p ]] && orfaos+=" ${p##*/}"; done
    assert_igual '' "$orfaos" "$destino: nenhum .part sobra"
    assert_igual 0 "$(_qa_registros "$base")" "$destino: nenhum registro sobra"
  done
}

# QA-B7A-02 reatacado: o descarte por cabecalho (outro host, outra caixa do
# remoto) leva o `.part` legitimo a barreira; o arquivo do usuario no lugar do
# `.part` (outro inode) fica; e um registro LEGIVEL de outro alvo plantado na
# chave nunca faz apagar o `.part` desse outro alvo.
teste_qa_d16_descarte_por_cabecalho_so_apaga_pela_barreira_e_so_do_proprio_alvo() {
  local base reg part antes forma
  for forma in host caixa usuario outro_alvo; do
    base=$(_qa_down_ambiente)
    _qa_down_cortado "$base"
    reg=$(_qa_registro "$base")
    part=$(_qa_part "$base")
    _qa_campos_ler "$reg"
    case $forma in
      host | usuario) QA_C[4]='outro-host' ;;
      caixa) QA_C[5]='/GRANDE.iso' ;;
      outro_alvo)
        # O registro passa a descrever outro alvo (mesmo diretorio): o `.part`
        # e dele, legitimo, e esta execucao nao pode apaga-lo.
        QA_C[12]="${QA_C[12]%/*}/outro.iso"
        ;;
    esac
    _qa_campos_gravar "$reg"
    if [[ $forma == usuario ]]; then
      rm -f "$part"
      printf 'do usuario\n' >"$part"
    fi
    antes=$(_qa_impressao "$part")
    _qa_down "$base"
    assert_igual 0 "$DBX_ESTADO" "$forma: conclui ($DBX_ERRO)"
    _qa_alvo_e_o_remoto "$base" "$forma: destino correto"
    case $forma in
      host | caixa) [[ ! -e $part ]] || _harness_falhar "$forma: o .part do registro descartado sai pela barreira" ;;
      usuario | outro_alvo) assert_igual "$antes" "$(_qa_impressao "$part")" "$forma: o arquivo que nao e deste alvo fica intacto" ;;
    esac
  done
}

harness_executar "$@"
