#!/usr/bin/env bash
# Testes ponta a ponta da retomada de DOWNLOAD entre execucoes (fase 7a, F-03;
# RF-102, RF-104, RF-105, RF-106, RF-107, RF-108; TC-RMD-01..15, TC-RMO-01, 02,
# 04, 05, TC-RMC-01, 06, TC-RML-05..07, TC-RMS-06; DIV-176 a DIV-178, DIV-183,
# DIV-185).
#
# O DUPLO DE `curl` SEGUE O CONTRATO DO CLIENTE REAL para pedido de faixa,
# medido com curl 8.18 contra um servidor local (log da fase 7a): com
# `continue-at = N` na configuracao, ele pede `Range: bytes=N-` e ANEXA ao
# destino; uma resposta `200`, ou `206` cujo inicio nao e N, e recusada com
# status 33 SEM escrever nada (o codigo vai pelo `-w`); `416` sai com status 0
# e nada escrito; `206` com o total errado e anexado (quem confere o total e o
# `dbx`). Sem `continue-at`, o destino e truncado e escrito do inicio.
#
# Controles em arquivos de $base: `modo` (`200`, `inicio`, `total`, `rev`,
# `errado`, `errado_sempre`), `corte` (bytes entregues antes de falhar a rede,
# status 18) e `sinal` (manda o sinal ao `dbx` depois de entregar `corte`
# bytes). O conteudo remoto e `remoto.bin`, a revisao e `rev`. Cada chamada fica
# em `chamadas` (`endpoint argumento continue-at`).
#
# shellcheck disable=SC2016,SC2031
# Justificativa: o duplo de `curl` chega sem expansao; os subshells que geram
# a massa sao de proposito (nada deles volta ao caso).
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly PARTE=4194304
readonly TAMANHO=$((157286400 + 5))
readonly REV1='0123456789a'
readonly REV2='0123456789b'

# _fixture_remota <versao> — conteudo remoto esparso de 150 MiB + 5 com marcas
# por bloco; a versao 2 difere num byte. Gerado uma vez, com o content_hash.
_fixture_remota() {
  local versao=$1 arquivo="$DBX_TESTES_TMP/retomada-down-$1.bin" i
  if [[ ! -e $arquivo ]]; then
    truncate -s "$TAMANHO" "$arquivo"
    for ((i = 0; i * PARTE < TAMANHO; i++)); do
      printf 'remoto-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * PARTE)) conv=notrunc status=none
    done
    [[ $versao == 2 ]] && printf 'V2' | dd of="$arquivo" bs=1 seek=$((5 * PARTE + 100)) conv=notrunc status=none
    (
      . "$DBX_HARNESS_RAIZ/lib/hash.sh"
      dbx_hash_publicar_arquivo "$arquivo" && printf '%s' "$DBX_HASH_RESULTADO" >"$arquivo.hash"
    )
  fi
  printf '%s' "$arquivo"
}

_ambiente() {
  local base remoto
  base=$(mktemp -d "$DBX_TESTES_TMP/rdown.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/trabalho"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  _versao_remota "$base" 1
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\n' "$base"
  } >"$base/bin/curl"
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
erro() { codigo=409; resposta="{\"error_summary\":\"$1\"}"; }
cabecalho() {
  [[ -n $cabecalhos ]] || return 0
  {
    printf 'HTTP/1.1 %s X\r\n' "$codigo"
    [[ -n $faixa ]] && printf 'Content-Range: %s\r\n' "$faixa"
    [[ -n $resultado ]] && printf 'Dropbox-API-Result: %s\r\n' "$resultado"
    printf '\r\n'
  } >"$cabecalhos"
}
case $ep in
  oauth2/token) resposta='{"access_token":"sl.tokenD","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata)
    if [[ -e $base/pasta ]]; then
      resposta='{".tag":"folder","name":"grande.iso","path_display":"/Grande.iso","id":"id:9"}'
    elif [[ -e $base/sumiu ]]; then
      erro 'path/not_found/'
    else
      resposta="{\".tag\":\"file\",\"name\":\"grande.iso\",\"path_display\":\"/Grande.iso\",\"id\":\"id:1\",\"rev\":\"$rev\",\"size\":$tam,\"content_hash\":\"$hash\"}"
    fi
    ;;
  files/download)
    [[ $arg =~ \"path\":\"([^\"]*)\" ]] && caminho=${BASH_REMATCH[1]}
    if [[ -e $base/pasta ]]; then
      erro 'path/not_file/'
    elif [[ -e $base/sumiu || ($caminho == rev:* && ${caminho#rev:} != "$rev") ]]; then
      erro 'path/not_found/'
    else
      rres=$rev
      [[ $modo == rev ]] && rres='fffffffffff'
      resultado="{\"name\":\"grande.iso\",\"rev\":\"$rres\",\"size\":$tam,\"content_hash\":\"$hash\"}"
      if [[ -n $inicio ]]; then
        if [[ $inicio -ge $tam ]]; then
          codigo=416; faixa="bytes */$tam"; resultado=''
          cabecalho; [[ -n $escrever ]] && printf '%s' "$codigo"; exit 0
        fi
        case $modo in
          200) codigo=200; cabecalho; [[ -n $escrever ]] && printf '%s' 200; exit 33 ;;
          inicio) codigo=206; faixa="bytes $((inicio + 1))-$((tam - 1))/$tam"; cabecalho; [[ -n $escrever ]] && printf '%s' 206; exit 33 ;;
          total) codigo=206; faixa="bytes $inicio-$((tam - 1))/$((tam + 1))" ;;
          *) codigo=206; faixa="bytes $inicio-$((tam - 1))/$tam" ;;
        esac
        cabecalho
        tail -c +$((inicio + 1)) "$base/remoto.bin" >>"$saida"
      else
        cabecalho
        if [[ -r $base/corte ]]; then
          head -c "$(<"$base/corte")" "$base/remoto.bin" >"$saida"
          rm -f "$base/corte"
          if [[ -r $base/sinal ]]; then
            kill -s "$(<"$base/sinal")" "$(<"$base/pid")"; rm -f "$base/sinal"; sleep 5
          fi
          [[ -n $escrever ]] && printf '%s' 200
          exit 18
        fi
        if [[ $modo == errado || $modo == errado_sempre ]]; then
          { head -c 1000 "$base/remoto.bin"; printf 'X'; tail -c +1002 "$base/remoto.bin"; } >"$saida"
          [[ $modo == errado ]] && rm -f "$base/modo"
        else
          cat "$base/remoto.bin" >"$saida"
        fi
      fi
      [[ -n $escrever ]] && printf '%s' "$codigo"
      exit 0
    fi
    ;;
  *) erro 'sem_regra/' ;;
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

# _versao_remota <base> <1|2> — o conteudo, a revisao e o resumo publicados.
_versao_remota() {
  local remoto
  remoto=$(_fixture_remota "$2")
  ln -sf "$remoto" "$1/remoto.bin"
  cp "$remoto.hash" "$1/hash"
  if [[ $2 == 1 ]]; then printf '%s' "$REV1" >"$1/rev"; else printf '%s' "$REV2" >"$1/rev"; fi
}

_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="${DBX_T_PATH:+$DBX_T_PATH:}$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${DBX_T_TETO:-120}" setsid -w bash -c 'umask "${1:-022}"; shift; printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "${DBX_T_UMASK:-022}" "$base" "${DBX_T_EXEC:-$DBX_EXEC_PADRAO}" "$@" </dev/null >"$base/out" 2>"$base/err"
  ) 2>/dev/null
  DBX_ESTADO=$?
  [[ $DBX_ESTADO -ne 124 && $DBX_ESTADO -ne 137 ]] || _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_down() { _rodar "$1" download "${@:2}" /Grande.iso grande.iso; } # <base> [opcoes...]
_conta() { _harness_contar "$2" "$1/chamadas"; }
_registros() {
  local r n=0
  for r in "$1"/estado/dbx/retomada-*; do [[ -e $r ]] && n=$((n + 1)); done
  printf '%s' "$n"
}
_parts() { # <base> — `.part` no diretorio do alvo
  local p lista=''
  for p in "$1"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p || -L $p ]] && lista+="${p##*/} "; done
  printf '%s' "$lista"
}
_part_registrado() { # <base> — caminho do `.part` (o unico)
  local p
  for p in "$1"/trabalho/.grande.iso.dbx-part.*; do printf '%s' "$p"; done
}
_alvo_igual_ao_remoto() { cmp -s "$1/trabalho/grande.iso" "$1/remoto.bin"; }
_copia_mutante() {
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/mutante.XXXXXX")
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$copia/"
  while [[ $# -ge 2 ]]; do
    cp "$copia/$1" "$copia/$1.orig"
    sed -e "$2" "$copia/$1.orig" >"$copia/$1"
    cmp -s "$copia/$1" "$copia/$1.orig" && _harness_falhar "a mutacao nao alterou $1: $2"
    rm -f "$copia/$1.orig"
    shift 2
  done
  printf '%s' "$copia/bin/dbx"
}

# _interrompido <base> [bytes] — primeira execucao: a rede cai depois de
# <bytes> (padrao 50 MiB + 3) com o alvo anterior no lugar.
_interrompido() {
  printf '%s' "${2:-$((50 * 1048576 + 3))}" >"$1/corte"
  _down "$1"
  assert_igual 9 "$DBX_ESTADO" "rede: $DBX_ERRO"
  assert_igual 1 "$(_registros "$1")" 'registro gravado'
  [[ -n $(_parts "$1") ]] || _harness_falhar 'o .part deveria ficar'
}

# ---------------------------------------------------------------------------
# RF-104: interrupcao e retomada (TC-RMD-01, 02, 12)
# ---------------------------------------------------------------------------

teste_rmd01_rmd02_interrompido_e_retomado_por_range_com_rev_fixa() {
  local base part
  base=$(_ambiente)
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  chmod 640 "$base/trabalho/grande.iso"
  _interrompido "$base"
  part=$(_part_registrado "$base")
  assert_igual 600 "$(stat -c %a "$part")" '.part 0600'
  assert_igual "$((50 * 1048576 + 3))" "$(stat -c %s "$part")" 'bytes recebidos no .part'
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'alvo anterior intacto'
  assert_igual 640 "$(stat -c %a "$base/trabalho/grande.iso")" 'modo intacto'
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  assert_igual 1 "$(_conta "$base" "^files/download .*\"path\":\"rev:$REV1\".* $((50 * 1048576 + 3))\$")" 'Range: bytes=T- sobre rev:<rev>'
  assert_igual 0 "$(_conta "$base" '^files/download .*"path":"/Grande.iso"')" 'nunca sem rev'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo deveria ser o remoto inteiro'
  assert_igual 640 "$(stat -c %a "$base/trabalho/grande.iso")" 'TC-RMD-12: modo do alvo substituido'
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'conferida'
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'retomada'
  assert_contem "retomado_de=$((50 * 1048576 + 3))" "$DBX_SAIDA" 'retomado_de = T'
  assert_igual '' "$(_parts "$base")" '.part removido'
  assert_igual 0 "$(_registros "$base")" 'registro removido depois do mv'
}

teste_rmd12_alvo_novo_tem_o_modo_do_umask() {
  local base
  base=$(_ambiente)
  DBX_T_UMASK=027 _down "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_igual 640 "$(stat -c %a "$base/trabalho/grande.iso")" 'modo pelo umask'
  assert_contem 'retomada=nao' "$DBX_SAIDA" 'sem registro previo'
}

# ---------------------------------------------------------------------------
# RF-104(b)(e): remoto mudou e barreira (TC-RMD-03..06, 11, 13, 14)
# ---------------------------------------------------------------------------

teste_rmd03_rmd04_rev_mudou_apaga_o_part_pela_barreira_e_baixa_a_nova() {
  local base part
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  _versao_remota "$base" 2
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'o arquivo remoto mudou desde a interrupcao' "$DBX_ERRO" 'aviso'
  assert_arquivo_ausente "$part" 'o .part antigo saiu pela barreira'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e a revisao nova'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
  assert_igual 0 "$(_conta "$base" "rev:$REV1\".* [0-9]")" 'nenhum Range sobre a revisao antiga'
}

_troca_part() { # <base> <como> — troca o .part registrado
  local part
  part=$(_part_registrado "$1")
  case $2 in
    ligacao)
      printf 'alheio' >"$1/alheio"
      rm -f "$part"
      ln -s "$1/alheio" "$part"
      ;;
    inode)
      rm -f "$part"
      printf 'arquivo do usuario' >"$part"
      ;;
  esac
  printf '%s' "$part"
}

teste_rmd05_rmd06_part_trocado_por_ligacao_ou_outro_inode_nao_e_tocado() {
  local base part como
  for como in ligacao inode; do
    base=$(_ambiente)
    _interrompido "$base"
    part=$(_troca_part "$base" "$como")
    _down "$base"
    assert_igual 0 "$DBX_ESTADO" "$como: $DBX_ERRO"
    assert_contem 'estado de retomada descartado' "$DBX_ERRO" "$como: aviso"
    if [[ $como == ligacao ]]; then
      [[ -L $part ]] || _harness_falhar 'a ligacao foi tocada'
      assert_igual 'alheio' "$(cat "$base/alheio")" 'o alvo da ligacao intacto'
    else
      assert_igual 'arquivo do usuario' "$(cat "$part")" 'o arquivo de outro inode intacto'
    fi
    _alvo_igual_ao_remoto "$base" || _harness_falhar "$como: o alvo e o remoto"
    assert_contem 'retomada=recomecada' "$DBX_SAIDA" "$como: .part novo"
    assert_igual 0 "$(_registros "$base")" "$como: registro removido"
  done
}

teste_rmd05_mutante_sem_a_barreira_de_inode_anexa_ao_arquivo_do_usuario() {
  local base part mutante
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_troca_part "$base" inode)
  mutante=$(_copia_mutante lib/state.sh 's/^  \[\[ \$atual == "\$devino" \]\]$/  :/' \
    lib/cmd.sh 's/if \[\[ \${info%|\*} != "\$devino" || /if [[ /;s/ || \[\[ \$DBX_ATRIBUTO != "\$devino" \]\]; then$/; then/')
  DBX_T_EXEC=$mutante _down "$base"
  [[ $(stat -c %s "$part" 2>/dev/null) != 18 ]] ||
    _harness_falhar 'sem a barreira, o mutante deveria tocar o arquivo do usuario'
}

teste_rmd11_arquivo_do_usuario_com_nome_parecido_fica_intacto() {
  local base intruso
  base=$(_ambiente)
  intruso="$base/trabalho/.grande.iso.dbx-part.ABC123"
  printf 'meu' >"$intruso"
  _interrompido "$base"
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  printf 'errado_sempre' >"$base/modo"
  _versao_remota "$base" 2
  _down "$base"
  assert_igual 11 "$DBX_ESTADO" 'divergencia'
  assert_igual 'meu' "$(cat "$intruso")" 'o arquivo nao registrado fica intacto em todo desfecho'
}

teste_rmd13_part_maior_que_o_esperado_nao_e_usado() {
  local base part
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  truncate -s $((TAMANHO + 10)) "$part"
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'do zero'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
}

teste_rmd14_nome_trocado_entre_a_conferencia_e_a_abertura_nada_anexa() {
  local base part real
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  real=$(command -v stat)
  mkdir -p "$base/troca"
  # Duplo de `stat`: na conferencia pelo NOME do .part, responde e, em seguida,
  # troca o arquivo por outro (outro inode) antes de o `dbx` abri-lo.
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\npart=%q\nmarca=%q\n' "$real" "$part" "$base/troca/feito"
    printf '%s\n' '"$real" "$@"; e=$?' \
      'ultimo=${!#}' \
      'if [[ ! -e $marca && ${ultimo##*/} == "${part##*/}" ]]; then : >"$marca"; mv -f "$part" "$part.orig"; printf "trocado" >"$part"; fi' \
      'exit $e'
  } >"$base/troca/stat"
  chmod +x "$base/troca/stat"
  DBX_T_PATH="$base/troca" _down "$base"
  assert_arquivo_existe "$base/troca/feito" 'a troca aconteceu'
  assert_igual 'trocado' "$(cat "$part")" 'nada anexado ao arquivo trocado'
  assert_igual 0 "$DBX_ESTADO" "segue com .part novo: $DBX_ERRO"
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
}

teste_rmd14_mutante_sem_a_conferencia_pelo_descritor_anexa_ao_trocado() {
  local base part real mutante
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  real=$(command -v stat)
  mkdir -p "$base/troca"
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\npart=%q\nmarca=%q\n' "$real" "$part" "$base/troca/feito"
    printf '%s\n' '"$real" "$@"; e=$?' \
      'ultimo=${!#}' \
      'if [[ ! -e $marca && ${ultimo##*/} == "${part##*/}" ]]; then : >"$marca"; mv -f "$part" "$part.orig"; printf "trocado" >"$part"; fi' \
      'exit $e'
  } >"$base/troca/stat"
  chmod +x "$base/troca/stat"
  mutante=$(_copia_mutante lib/cmd.sh 's/if \[\[ \${info%|\*} != "\$devino" || /if [[ /;s/ || \[\[ \$DBX_ATRIBUTO != "\$devino" \]\]; then$/; then/')
  DBX_T_EXEC=$mutante DBX_T_PATH="$base/troca" _down "$base"
  assert_arquivo_existe "$base/troca/feito" 'a troca aconteceu'
  [[ $(head -c 7 "$part") == 'trocado' && $(stat -c %s "$part") -gt 7 ]] ||
    _harness_falhar 'o mutante deveria anexar ao arquivo trocado'
}

# ---------------------------------------------------------------------------
# RF-104(d): resposta a faixa (TC-RMD-07..09; DIV-176)
# ---------------------------------------------------------------------------

teste_rmd07_200_a_um_pedido_de_faixa_nunca_e_anexado() {
  local base
  base=$(_ambiente)
  _interrompido "$base"
  printf '200' >"$base/modo"
  _down "$base"
  rm -f "$base/modo"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'faixa ignorada: o servico respondeu 200' "$DBX_ERRO" 'aviso'
  assert_igual 3 "$(_conta "$base" '^files/download ')" 'o interrompido, a faixa recusada e um download do zero'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
  assert_contem 'retomada=recomecada' "$DBX_SAIDA" 'recomecada'
  assert_igual '' "$(_parts "$base")" 'nenhum .part sobra'
}

teste_rmd08_206_de_outro_inicio_outro_total_ou_outra_rev_recomeca() {
  local base modo
  for modo in inicio total rev; do
    base=$(_ambiente)
    _interrompido "$base"
    printf '%s' "$modo" >"$base/modo"
    _down "$base"
    rm -f "$base/modo"
    assert_igual 0 "$DBX_ESTADO" "$modo: $DBX_ERRO"
    assert_contem 'faixa ignorada' "$DBX_ERRO" "$modo: aviso"
    _alvo_igual_ao_remoto "$base" || _harness_falhar "$modo: o alvo e o remoto"
    assert_contem 'retomada=recomecada' "$DBX_SAIDA" "$modo: recomecada"
  done
}

teste_rmd08_mutante_que_nao_confere_o_content_range_aceita_o_total_errado() {
  local base mutante
  base=$(_ambiente)
  _interrompido "$base"
  printf 'total' >"$base/modo"
  mutante=$(_copia_mutante lib/cmd.sh 's/\${DBX_HTTP_FAIXA_CABECALHO:-} == "bytes \$inicio-\$((tamanho - 1))\/\$tamanho"/-n x/')
  DBX_T_EXEC=$mutante _down "$base"
  assert_contem 'retomada=sim' "$DBX_SAIDA" 'o mutante anexa um 206 de total errado'
}

teste_rmd09_416_com_o_part_completo_confere_e_troca_sem_corpo() {
  local base part
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  cp "$base/remoto.bin" "$part"
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "416: $DBX_ERRO"
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
  assert_contem "retomado_de=$TAMANHO" "$DBX_SAIDA" 'retomado do fim'
}

# ---------------------------------------------------------------------------
# RF-104(f): conferencia antes da troca (TC-RMD-10; DIV-183)
# ---------------------------------------------------------------------------

teste_rmd10_hash_divergente_recomeca_uma_vez_e_de_novo_sai_11_sem_trocar() {
  local base
  base=$(_ambiente)
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  # Divergencia na primeira, certo na segunda: um recomeco, sucesso.
  printf 'errado' >"$base/modo"
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "um recomeco: $DBX_ERRO"
  assert_contem 'nao confere com o content_hash' "$DBX_ERRO" 'aviso'
  assert_igual 2 "$(_conta "$base" '^files/download ')" 'dois downloads'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
  # Divergindo sempre: 11 e o alvo anterior fica.
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf 'errado_sempre' >"$base/modo"
  _down "$base"
  assert_igual 11 "$DBX_ESTADO" 'integridade'
  assert_igual 'alvo anterior' "$(cat "$base/trabalho/grande.iso")" 'nada trocado'
  assert_igual '' "$(_parts "$base")" 'nenhum .part sobra'
  assert_igual 0 "$(_registros "$base")" 'nenhum registro sobra'
}

teste_rmd10_mutante_que_troca_antes_do_hash_reprova() {
  local base mutante
  base=$(_ambiente)
  printf 'alvo anterior' >"$base/trabalho/grande.iso"
  printf 'errado_sempre' >"$base/modo"
  mutante=$(_copia_mutante lib/cmd.sh '/^  # RF-104(f): o `.part` INTEIRO, pela barreira, contra o resumo esperado e o$/i\
  mv -f -- "$part" "$alvo"')
  DBX_T_EXEC=$mutante _down "$base"
  assert_diferente 'alvo anterior' "$(head -c 13 "$base/trabalho/grande.iso" | tr -d '\0')" 'o mutante troca o alvo sem conferir'
}

# ---------------------------------------------------------------------------
# RF-104(a), RF-106: sinal antes e depois de gravar o registro (TC-RMD-15)
# ---------------------------------------------------------------------------

teste_rmd15_sinal_depois_do_registro_deixa_o_part_e_antes_remove() {
  local base real
  base=$(_ambiente)
  printf '%s' $((10 * 1048576)) >"$base/corte"
  printf 'TERM' >"$base/sinal"
  _down "$base"
  assert_igual 14 "$DBX_ESTADO" 'sinal'
  [[ -n $(_parts "$base") ]] || _harness_falhar 'depois de gravado, o .part fica'
  assert_igual 1 "$(_registros "$base")" 'o registro fica'
  local trava n=0
  for trava in "$base"/estado/dbx/trava-*; do [[ -e $trava ]] && n=$((n + 1)); done
  assert_igual 0 "$n" 'trava liberada'
  # Registro que nao pode ser gravado: o .part continua de lib/tmp e sai.
  base=$(_ambiente)
  real=$(command -v mktemp)
  mkdir -p "$base/mk"
  {
    printf '#!%s\n' "$BASH"
    printf 'real=%q\n' "$real"
    printf '%s\n' 'for a in "$@"; do [[ $a == */.retomada.* ]] && exit 1; done' 'exec "$real" "$@"'
  } >"$base/mk/mktemp"
  chmod +x "$base/mk/mktemp"
  printf '%s' $((10 * 1048576)) >"$base/corte"
  printf 'TERM' >"$base/sinal"
  DBX_T_PATH="$base/mk" _down "$base"
  assert_igual 14 "$DBX_ESTADO" 'sinal'
  assert_igual '' "$(_parts "$base")" 'sem registro, o .part sai como hoje'
  assert_contem 'o registro de retomada nao pode ser gravado' "$DBX_ERRO" 'aviso'
}

# ---------------------------------------------------------------------------
# RF-102: alcance (TC-RMO-01, 02, 04, 05)
# ---------------------------------------------------------------------------

teste_rmo01_rmo02_rmo04_fora_do_alcance_e_recusas_antes_do_part() {
  local base
  base=$(_ambiente)
  truncate -s 157286400 "$base/exato.bin"
  ln -sf "$base/exato.bin" "$base/remoto.bin"
  (
    . "$DBX_HARNESS_RAIZ/lib/hash.sh"
    dbx_hash_publicar_arquivo "$base/exato.bin" && printf '%s' "$DBX_HASH_RESULTADO" >"$base/hash"
  )
  _down "$base"
  assert_igual 0 "$DBX_ESTADO" "150 MiB exatos: $DBX_ERRO"
  assert_nao_contem 'retomada' "$DBX_SAIDA" 'saida de hoje'
  _rodar "$base" download /Grande.iso
  assert_igual 0 "$(_registros "$base")" 'nenhum registro (arquivo exato e saida padrao)'
  # Destino somente leitura: recusa antes de ler registro ou criar .part.
  base=$(_ambiente)
  printf 'protegido' >"$base/trabalho/grande.iso"
  chmod 444 "$base/trabalho/grande.iso"
  _down "$base"
  assert_igual 6 "$DBX_ESTADO" 'somente leitura'
  assert_igual '' "$(_parts "$base")" 'nenhum .part'
  assert_arquivo_ausente "$base/estado/dbx" 'nenhum estado lido nem criado'
  # Pasta remota sobre arquivo local: RF-56, antes de qualquer .part.
  base=$(_ambiente)
  printf 'arquivo' >"$base/trabalho/grande.iso"
  : >"$base/pasta"
  _down "$base"
  assert_igual 7 "$DBX_ESTADO" 'pasta sobre arquivo'
  assert_igual '' "$(_parts "$base")" 'nenhum .part'
  assert_igual 0 "$(_registros "$base")" 'nenhum registro'
}

teste_rmo05_sem_retomada_recebe_como_antes_e_nao_toca_o_registro() {
  local base antes part
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  antes=$(cat "$base"/estado/dbx/retomada-* | od -An -tx1 | tr -d ' \n')
  local metadados
  metadados=$(_conta "$base" '^files/get_metadata ')
  _down "$base" --no-resume
  assert_igual 0 "$DBX_ESTADO" "como antes: $DBX_ERRO"
  assert_nao_contem 'retomada' "$DBX_SAIDA" 'saida de antes'
  assert_igual "$metadados" "$(_conta "$base" '^files/get_metadata ')" 'sem get_metadata, como antes'
  assert_igual "$antes" "$(cat "$base"/estado/dbx/retomada-* | od -An -tx1 | tr -d ' \n')" 'registro intacto'
  assert_arquivo_existe "$part" 'o .part do registro intacto'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
}

# ---------------------------------------------------------------------------
# RF-106(c): falha definitiva e remoto que sumiu (TC-RMS-06)
# ---------------------------------------------------------------------------

teste_rms06_remoto_que_sumiu_limpa_registro_e_part_e_sai_4() {
  local base part
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  : >"$base/sumiu"
  _down "$base"
  assert_igual 4 "$DBX_ESTADO" 'remoto inexistente'
  assert_igual 0 "$(_registros "$base")" 'registro removido'
  assert_arquivo_ausente "$part" '.part removido pela barreira'
}

# ---------------------------------------------------------------------------
# RF-105: concorrencia (TC-RMC-01, 06)
# ---------------------------------------------------------------------------

teste_rmc01_dois_downloads_simultaneos_um_retoma() {
  local base copia i
  base=$(_ambiente)
  _interrompido "$base"
  copia=$(mktemp -d "$DBX_TESTES_TMP/rmcd.XXXXXX")
  (
    cd "$base/trabalho" || exit 99
    for i in 1 2; do
      env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
        TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
        timeout -k 2 120 bash -c 'while [[ ! -e $1 ]]; do :; done; shift; printf "%s" "$$" >"$1/pid"; exec bash "$2" download /Grande.iso grande.iso' _ \
        "$copia/largada" "$base" "$DBX_EXEC_PADRAO" </dev/null >"$copia/out$i" 2>"$copia/err$i" &
    done
    : >"$copia/largada"
    wait
  ) 2>/dev/null
  local s1 s2 sim=0 nao=0
  s1=$(cat "$copia/out1" "$copia/err1")
  s2=$(cat "$copia/out2" "$copia/err2")
  [[ $s1 == *'retomada=sim'* ]] && sim=$((sim + 1))
  [[ $s2 == *'retomada=sim'* ]] && sim=$((sim + 1))
  [[ $s1 == *'retomada=nao'* ]] && nao=$((nao + 1))
  [[ $s2 == *'retomada=nao'* ]] && nao=$((nao + 1))
  assert_igual '1 1' "$sim $nao" 'um retoma, o outro usa um .part novo'
  assert_contem 'trava do registro ocupada' "$s1$s2" 'aviso com a trava'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
  assert_igual '' "$(_parts "$base")" 'nenhum .part sobra'
}

# ---------------------------------------------------------------------------
# RF-107: unlink e diagnostico (TC-RML-05..07, TC-RMC-06)
# ---------------------------------------------------------------------------

teste_rml06_rml07_rmc06_diagnostico_lista_so_le_e_nao_cria() {
  local base
  base=$(_ambiente)
  _rodar "$base" diagnostico
  assert_arquivo_ausente "$base/estado/dbx" 'sem diretorio de estado: nao o cria'
  assert_nao_contem 'retomada=' "$DBX_SAIDA" 'sem registros, sem linha'
  _interrompido "$base"
  printf 'ruim' >"$base/estado/dbx/retomada-ffffffffffffffffffffffffffffffff"
  local antes
  antes=$(cd "$base/estado" && find . -type f -exec sha256sum {} + | sort)
  _rodar "$base" diagnostico
  assert_contem 'retomada=ok: pendente: download /Grande.iso -> ' "$DBX_SAIDA" 'pendente'
  assert_contem "$((50 * 1048576 + 3)) bytes recebidos" "$DBX_SAIDA" 'bytes recebidos'
  assert_contem 'retomada=aviso: ilegivel: ' "$DBX_SAIDA" 'ilegivel'
  assert_igual "$antes" "$(cd "$base/estado" && find . -type f -exec sha256sum {} + | sort)" 'nada removido nem criado'
  # TC-RMC-06: trava de registro viva aparece com o comando retomada.
  local r host
  for r in "$base"/estado/dbx/retomada-*; do
    [[ $r == *ffffffff* ]] && continue
    host=$(XDG_STATE_HOME="$base/estado" bash -c '. "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf %s "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ")
    printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' "$$" "$host" 1700000000 >"${r%/*}/trava-${r##*/retomada-}"
  done
  _rodar "$base" diagnostico
  assert_contem 'trava=ok: viva: o retomada pid' "$DBX_SAIDA" 'trava de registro com comando retomada'
}

teste_rml05_unlink_apaga_o_part_que_passa_e_lista_o_que_nao_passa() {
  local base p1 p2 nome2
  base=$(_ambiente)
  _interrompido "$base"
  p1=$(_part_registrado "$base")
  # Segundo registro de download, de outro alvo, cujo .part foi trocado.
  mkdir -p "$base/trabalho/outro"
  printf '%s' 1048576 >"$base/corte"
  _rodar "$base" download /Grande.iso outro/grande.iso
  assert_igual 9 "$DBX_ESTADO" 'segundo alvo interrompido'
  for nome2 in "$base"/trabalho/outro/.grande.iso.dbx-part.*; do p2=$nome2; done
  rm -f "$p2"
  printf 'trocado' >"$p2"
  _rodar "$base" unlink --confirmar
  assert_arquivo_ausente "$p1" 'o .part que passa a barreira sai'
  assert_igual 'trocado' "$(cat "$p2")" 'o que nao passa fica'
  assert_contem '1 arquivo(s) parcial(is)' "$DBX_ERRO" 'diz quantos'
  assert_contem "parcial mantido: $p2" "$DBX_ERRO" 'lista o caminho'
  assert_arquivo_ausente "$base/estado/dbx" 'nenhum retomada-* resta'
}

teste_rml05_unlink_com_trava_de_registro_viva_recusa_sem_apagar() {
  local base part r host
  base=$(_ambiente)
  _interrompido "$base"
  part=$(_part_registrado "$base")
  host=$(XDG_STATE_HOME="$base/estado" bash -c '. "$1/lib/errors.sh"; . "$1/lib/json.sh"; . "$1/lib/config.sh"; . "$1/lib/state.sh"; dbx_state_host_id; printf %s "$DBX_STATE_HOST_ID"' _ "$DBX_HARNESS_RAIZ")
  for r in "$base"/estado/dbx/retomada-*; do
    printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' "$$" "$host" 1700000000 >"${r%/*}/trava-${r##*/retomada-}"
  done
  _rodar "$base" unlink --confirmar
  assert_igual 7 "$DBX_ESTADO" 'trava viva: conflito'
  assert_arquivo_existe "$part" 'nada apagado'
  assert_igual 1 "$(_registros "$base")" 'registro intacto'
}

# Ciclo 2 do QA (QA-B7A-02): registro descartado pelo cabecalho (o remoto
# dado com outra caixa cai na mesma chave) nao deixa `.part` invisivel.
teste_c2_registro_de_outro_remoto_descartado_leva_o_part_pela_barreira() {
  local base p orfaos=''
  base=$(_ambiente)
  _interrompido "$base"
  _rodar "$base" download /grande.ISO grande.iso
  assert_igual 0 "$DBX_ESTADO" "conclui: $DBX_ERRO"
  assert_contem 'estado de retomada descartado' "$DBX_ERRO" 'aviso'
  _alvo_igual_ao_remoto "$base" || _harness_falhar 'o alvo e o remoto'
  for p in "$base"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p ]] && orfaos+=" ${p##*/}"; done
  assert_igual '' "$orfaos" 'nenhum .part orfao'
  assert_igual 0 "$(_registros "$base")" 'nenhum registro'
}

teste_c2_mutante_que_descarta_sem_a_barreira_deixa_o_orfao() {
  local base p orfaos='' mutante
  base=$(_ambiente)
  _interrompido "$base"
  mutante=$(_copia_mutante lib/state.sh 's/^    _dbx_state_retomada_descartar_part "\${c\[@\]}"$/    :/')
  DBX_T_EXEC=$mutante _rodar "$base" download /grande.ISO grande.iso
  for p in "$base"/trabalho/.grande.iso.dbx-part.*; do [[ -e $p ]] && orfaos+=" ${p##*/}"; done
  [[ -n $orfaos ]] || _harness_falhar 'sem a barreira no descarte, o mutante deixa o .part orfao'
}

# Ciclo 2 do QA (QA-B7A-01): `retomada-*` que e FIFO nao pendura o
# `diagnostico` nem o `unlink`.
teste_c2_fifo_no_estado_nao_pendura_diagnostico_nem_unlink() {
  local base
  base=$(_ambiente)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  mkfifo -m 600 "$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef"
  DBX_T_TETO=20 _rodar "$base" diagnostico
  assert_contem 'retomada=aviso: ilegivel' "$DBX_SAIDA" 'a FIFO aparece como ilegivel'
  [[ -p $base/estado/dbx/retomada-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'diagnostico so le'
  # O duplo nao revoga token (o unlink sai com a classe da revogacao): o que
  # importa aqui e que ele termina e remove o estado, sem pendurar.
  DBX_T_TETO=20 _rodar "$base" unlink --confirmar
  assert_arquivo_ausente "$base/estado/dbx" "unlink conclui e remove o estado: $DBX_ERRO"
}

teste_c2_mutante_sem_a_conferencia_de_arquivo_regular_pendura() {
  local base mutante
  base=$(_ambiente)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  mkfifo -m 600 "$base/estado/dbx/retomada-0123456789abcdef0123456789abcdef"
  mutante=$(_copia_mutante lib/state.sh 's/^  \[\[ -f \$arquivo \]\] || return 1  # nao regular$/  :/')
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
      TMPDIR="$base/tmp" timeout -k 2 5 bash "$mutante" diagnostico </dev/null >/dev/null 2>&1
  )
  assert_igual 124 "$?" 'sem a conferencia, o mutante pendura na FIFO'
}


teste_prg_download_retomado_comeca_no_percentual_do_part() {
  local base primeira
  base=$(_ambiente)
  _interrompido "$base"
  # O ambiente troca `sleep` por um no-op, o que faria o observador do .part
  # amostrar antes de `avancar`; aqui o `sleep` e o real, para provar que a
  # primeira linha vem do avanco ao inicio da retomada e nao de uma amostra.
  mkdir -p "$base/realsleep"
  printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v sleep)" >"$base/realsleep/sleep"
  chmod +x "$base/realsleep/sleep"
  DBX_T_PATH="$base/realsleep" _rodar "$base" --progresso download /Grande.iso grande.iso
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  primeira=${DBX_ERRO#*baixando: }
  primeira=${primeira%%$'\n'*}
  assert_nao_contem ' 0% ' "$primeira" 'DIV-294: a primeira linha nao volta a 0%'
  assert_contem ' 33% ' "$primeira" 'DIV-294: a primeira linha mostra o que o .part ja tem'
}
# ---------------------------------------------------------------------------
# --debug: etapas do download retomavel (RF-160; TC-DBG-13..15)
# ---------------------------------------------------------------------------

teste_tc_dbg_13_retomada_do_part_traz_a_faixa_e_part_bytes_no_plano_e_na_linha_http() {
  local base
  base=$(_ambiente)
  _interrompido "$base"
  _rodar "$base" --debug download /Grande.iso grande.iso
  assert_igual 0 "$DBX_ESTADO" "retomado: $DBX_ERRO"
  assert_contem "retomada=encontrada faixa=$((50 * 1048576 + 3))- part_bytes=$((50 * 1048576 + 3))" "$DBX_ERRO"
  assert_contem "faixa=$((50 * 1048576 + 3))-" "$DBX_ERRO"
  assert_contem 'debug: download hash=ok' "$DBX_ERRO"
}

teste_tc_dbg_14_servidor_que_ignora_a_faixa_reinicia_com_motivo() {
  local base
  base=$(_ambiente)
  _interrompido "$base"
  printf '200' >"$base/modo"
  _rodar "$base" --debug download /Grande.iso grande.iso
  rm -f "$base/modo"
  assert_igual 0 "$DBX_ESTADO" "do zero: $DBX_ERRO"
  assert_contem 'debug: download retomada=descartada motivo=servidor-ignorou-faixa' "$DBX_ERRO"
}

teste_tc_dbg_15_hash_divergente_aparece_antes_do_erro_11() {
  local base
  base=$(_ambiente)
  printf 'errado_sempre' >"$base/modo"
  _rodar "$base" --debug download /Grande.iso grande.iso
  assert_igual 11 "$DBX_ESTADO" 'integridade'
  assert_contem 'debug: download hash=divergente bytes=' "$DBX_ERRO"
  assert_contem 'nao confere com o content_hash' "$DBX_ERRO"
}

teste_tc_dbg_13_rev_mudou_descarta_com_motivo_hash_remoto_mudou() {
  local base
  base=$(_ambiente)
  _interrompido "$base"
  _versao_remota "$base" 2
  _rodar "$base" --debug download /Grande.iso grande.iso
  assert_contem 'retomada=descartada motivo=hash-remoto-mudou' "$DBX_ERRO"
}

harness_executar "$@"
