#!/usr/bin/env bash
# Suite independente do QA, demanda suporte-freebsd (RF-166 a RF-172, RNF-39,
# TC-FBSD-*).
#
# ADVERSARIA, pelo executavel real (bin/dbx) com os dubles BSD (chmod, stat,
# find, sha256) a frente do PATH e duplo de rede proprio. Cobre o que a suite
# do desenvolvedor nao exercita de ponta a ponta: `config` com chmod BSD,
# transferencias reais, `sync --enviar` repetido (comparado com o mesmo
# roteiro em GNU), credencial/diretorio inseguros recusados igualmente nas duas
# formas, descritor conferido pelo proprio descritor (fdescfs do FreeBSD 15) e ausencia de erro de uso nos dubles.
#
# shellcheck disable=SC2016,SC2031
# Justificativa: o duplo de `curl` e escrito sem expansao; os subshells dos
# cenarios (`$(...)`) nao precisam devolver variavel ao caso.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"

readonly QA_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QA_ENTRADA=$'qaak1234567890abc\nQA_SEGREDO_APP_B13\nQA_CODIGO_B13\n'
readonly QA_SENTINELAS='QA_SEGREDO_APP_B13 QA_CODIGO_B13 QA-RT-B13 QA-TOKEN-B13'

# _qa_cenario — credencial, duplo de `curl` e arvore local; TMPDIR proprio.
_qa_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-b13.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"QA_SEGREDO_APP_B13","refresh_token":"QA-RT-B13","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' 'conteudo remoto b13' >"$base/conteudo_remoto"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    printf 'cat >/dev/null 2>&1\n'
    printf 'saida=""; escrever=""; anterior=""; url=""; fail=nao\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; --fail) fail=sim ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'printf "%%s\\n" "$url" >>"$base/chamadas"\n'
    printf 'codigo=200\n'
    printf 'case $url in\n'
    printf '  *oauth2/token*) corpo=%s ;;\n' "'{\"access_token\":\"sl.QA-TOKEN-B13\",\"refresh_token\":\"QA-RT-B13\",\"expires_in\":14400}'"
    printf '  *get_current_account*) corpo=%s ;;\n' "'{\"account_id\":\"dbid:CONTA\"}'"
    printf '  *list_folder*) corpo=$(cat "$base/listagem") ;;\n'
    printf '  *files/download*) corpo=$(cat "$base/conteudo_remoto") ;;\n'
    printf '  *) corpo=%s ;;\n' "'{\"name\":\"x\",\"path_display\":\"/x\",\".tag\":\"file\",\"rev\":\"1\",\"size\":1}'"
    printf 'esac\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _qa_rodar <base> <entrada> <argumentos...> — saidas em DBX_SAIDA/DBX_ERRO.
_qa_rodar() {
  local base=$1 entrada=$2
  shift 2
  DBX_SAIDA=''
  DBX_ERRO=''
  printf '%s' "$entrada" >"$base/entrada"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    DBX_FREEBSD_REGISTRO="${DBX_FREEBSD_REGISTRO:-}" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    bash "$QA_EXEC" "$@" <"$base/entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _qa_conta <base> <padrao> — linhas de `chamadas` que casam, por while read.
_qa_conta() {
  local n=0 linha
  if [[ -f $1/chamadas ]]; then
    while IFS= read -r linha; do
      [[ $linha == *$2* ]] && n=$((n + 1))
    done <"$1/chamadas"
  fi
  printf '%s' "$n"
}

_qa_modo() { dbx_freebsd_real stat -c %a "$1"; }

_qa_sem_segredo() { # <texto> <rotulo>
  local s
  for s in $QA_SENTINELAS; do
    assert_nao_contem "$s" "$1" "$2: segredo $s nao vaza"
  done
}

_qa_erros_dos_dubles() {
  local erros
  erros=$(dbx_freebsd_erros)
  assert_igual '' "$erros" "$1: nenhum duble registrou erro de uso"
  assert_nao_contem 'chmod: --' "$DBX_ERRO" "$1: sem 'chmod: --'"
  assert_nao_contem 'illegal option' "$DBX_ERRO" "$1: sem 'illegal option'"
  assert_nao_contem '-printf' "$DBX_ERRO" "$1: sem -printf"
}

teste_config_com_chmod_bsd_grava_0600_em_0700_sem_vazar_segredo() {
  local base arquivo
  base=$(_qa_cenario)
  rm -rf "$base/config/dbx"
  dbx_freebsd_ativar
  _qa_rodar "$base" "$QA_ENTRADA" --json config
  assert_igual 0 "$DBX_ESTADO" "config conclui com os dubles BSD: $DBX_ERRO"
  arquivo="$base/config/dbx/credencial.json"
  assert_arquivo_existe "$arquivo" 'a credencial foi criada'
  assert_igual 600 "$(_qa_modo "$arquivo")" 'RF-166: credencial 0600 apos chmod BSD'
  assert_igual 700 "$(_qa_modo "$base/config/dbx")" 'RF-166: diretorio 0700 apos chmod BSD'
  _qa_erros_dos_dubles 'config'
  _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" 'config'
}

teste_upload_e_download_reais_com_dubles_bsd_sem_erro_nem_vazamento() {
  local base conteudo
  base=$(_qa_cenario)
  printf '%s' 'conteudo local b13' >"$base/local/a.txt"
  dbx_freebsd_ativar
  _qa_rodar "$base" '' upload "$base/local/a.txt" /a.txt
  assert_igual 0 "$DBX_ESTADO" "upload conclui: $DBX_ERRO"
  assert_igual 1 "$(_qa_conta "$base" 'files/upload')" 'o upload chegou ao duplo de rede uma vez'
  _qa_erros_dos_dubles 'upload'
  _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" 'upload'
  _qa_rodar "$base" '' download /a.txt "$base/local/b.txt"
  assert_igual 0 "$DBX_ESTADO" "download conclui: $DBX_ERRO"
  conteudo=$(cat "$base/local/b.txt")
  assert_igual 'conteudo remoto b13' "$conteudo" 'o download gravou o corpo remoto'
  _qa_erros_dos_dubles 'download'
  _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" 'download'
}

teste_sync_enviar_repetido_tem_o_mesmo_efeito_em_bsd_e_em_gnu() {
  local gnu bsd gnu1 gnu2 bsd1 bsd2
  gnu=$(_qa_cenario)
  printf '%s' 'sync b13' >"$gnu/local/s.txt"
  _qa_rodar "$gnu" '' sync --enviar --origem "$gnu/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync GNU 1 conclui: $DBX_ERRO"
  gnu1=$(_qa_conta "$gnu" 'files/upload')
  _qa_rodar "$gnu" '' sync --enviar --origem "$gnu/local" --destino /r
  gnu2=$(_qa_conta "$gnu" 'files/upload')

  bsd=$(_qa_cenario)
  printf '%s' 'sync b13' >"$bsd/local/s.txt"
  dbx_freebsd_ativar
  _qa_rodar "$bsd" '' sync --enviar --origem "$bsd/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync BSD 1 conclui: $DBX_ERRO"
  bsd1=$(_qa_conta "$bsd" 'files/upload')
  _qa_erros_dos_dubles 'sync 1'
  _qa_rodar "$bsd" '' sync --enviar --origem "$bsd/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync BSD 2 conclui: $DBX_ERRO"
  bsd2=$(_qa_conta "$bsd" 'files/upload')
  _qa_erros_dos_dubles 'sync 2'
  assert_igual "$gnu1" "$bsd1" 'primeiro envio: mesma contagem de uploads em BSD e GNU'
  assert_igual "$gnu2" "$bsd2" 'segundo envio: identidade estavel, mesma contagem acumulada em BSD e GNU'
  _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" 'sync'
}

# _qa_recusa <base> — roda um comando que exige credencial e devolve o estado.
_qa_recusa() {
  _qa_rodar "$1" '' espaco
}

teste_credencial_4600_e_diretorio_1700_recusados_igualmente_em_gnu_e_bsd() {
  local forma base gnu_estado
  for forma in credencial diretorio; do
    base=$(_qa_cenario)
    if [[ $forma == credencial ]]; then chmod 4600 "$base/config/dbx/credencial.json"; else chmod 1700 "$base/config/dbx"; fi
    _qa_recusa "$base"
    gnu_estado=$DBX_ESTADO
    [[ $gnu_estado -ne 0 ]] || _harness_falhar "GNU aceitou $forma insegura"
    assert_igual 0 "$(_qa_conta "$base" 'oauth2')" "GNU $forma: nenhuma chamada de rede"
    _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" "GNU $forma"

    base=$(_qa_cenario)
    if [[ $forma == credencial ]]; then chmod 4600 "$base/config/dbx/credencial.json"; else chmod 1700 "$base/config/dbx"; fi
    dbx_freebsd_ativar
    _qa_recusa "$base"
    assert_igual "$gnu_estado" "$DBX_ESTADO" "BSD $forma: mesmo codigo de saida que GNU"
    assert_igual 0 "$(_qa_conta "$base" 'oauth2')" "BSD $forma: nenhuma chamada de rede"
    _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" "BSD $forma"
    assert_igual '' "$(dbx_freebsd_erros)" "BSD $forma: dubles sem erro de uso"
  done
}

# ---------------------------------------------------------------------------
# RF-171(a) / TC-FBSD-20 (DIV-352 superada): o descritor e conferido pelo
# proprio descritor, nunca por `/dev/fd/<n>`. Com os dubles BSD a frente do
# PATH, QUALQUER `/dev/fd/<n>` e um no do fdescfs (Character Device, dev|ino
# fixos), como no FreeBSD 15; o produto precisa funcionar assim mesmo.
# ---------------------------------------------------------------------------

# A retomada so vale acima de 150 MiB (dbx_cmd_receber_retomavel).
readonly QA_TAMANHO_REMOTO=$((150 * 1048576 + 5))
readonly QA_CORTE=$((50 * 1048576 + 3))

# _qa_remoto — conteudo remoto esparso com marcas por bloco e o content_hash.
_qa_remoto() {
  local arquivo="$DBX_TESTES_TMP/qa-b13-remoto.bin" i
  if [[ ! -e $arquivo.hash ]]; then
    truncate -s "$QA_TAMANHO_REMOTO" "$arquivo"
    for ((i = 0; i * 4194304 < QA_TAMANHO_REMOTO; i++)); do
      printf 'qa-remoto-%03d' "$i" | dd of="$arquivo" bs=1 seek=$((i * 4194304)) conv=notrunc status=none
    done
    (
      . "$DBX_HARNESS_RAIZ/lib/hash.sh"
      dbx_hash_publicar_arquivo "$arquivo" && printf '%s' "$DBX_HASH_RESULTADO" >"$arquivo.hash"
    )
  fi
  printf '%s' "$arquivo"
}

# _qa_cenario_retomada — _qa_cenario com o duplo de `curl` de download
# retomavel: `corte` (bytes entregues antes de a rede cair, status 18) e
# `continue-at` (anexa a faixa pedida ao destino), como o cliente real.
_qa_cenario_retomada() {
  local base remoto
  base=$(_qa_cenario)
  remoto=$(_qa_remoto)
  ln -sf "$remoto" "$base/remoto.bin"
  cp "$remoto.hash" "$base/hash"
  {
    printf '#!/usr/bin/env bash\nbase=%q\n' "$base"
    cat <<'FIM'
conf=$(cat)
saida=''; escrever=''; anterior=''; url=''; cabecalhos=''
for a in "$@"; do
  case $anterior in -o) saida=$a ;; -w) escrever=$a ;; -D) cabecalhos=$a ;; esac
  case $a in http*) url=$a ;; esac
  anterior=$a
done
inicio=''
while IFS= read -r linha; do
  case $linha in 'continue-at = '*) inicio=${linha#continue-at = } ;; esac
done <<<"$conf"
ep=${url#https://*/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s %s\n' "$ep" "$inicio" >>"$base/chamadas"
tam=$(wc -c <"$base/remoto.bin"); hash=$(<"$base/hash")
meta="\"name\":\"g.iso\",\"rev\":\"0123456789a\",\"size\":$tam,\"content_hash\":\"$hash\""
codigo=200; [[ -n $inicio ]] && codigo=206
case $ep in
  oauth2/token) corpo='{"access_token":"sl.QA-TOKEN-B13","token_type":"bearer","expires_in":14400}' ;;
  files/get_metadata) corpo="{\".tag\":\"file\",\"path_display\":\"/g.iso\",\"id\":\"id:1\",$meta}" ;;
  files/download)
    if [[ -n $cabecalhos ]]; then
      {
        printf 'HTTP/1.1 %s X\r\n' "$codigo"
        [[ -n $inicio ]] && printf 'Content-Range: bytes %s-%s/%s\r\n' "$inicio" "$((tam - 1))" "$tam"
        printf 'Dropbox-API-Result: {%s}\r\n\r\n' "$meta"
      } >"$cabecalhos"
    fi
    if [[ -n $inicio ]]; then
      tail -c +$((inicio + 1)) "$base/remoto.bin" >>"$saida"
    elif [[ -r $base/corte ]]; then
      head -c "$(<"$base/corte")" "$base/remoto.bin" >"$saida"
      rm -f "$base/corte"
      [[ -n $escrever ]] && printf '200'
      exit 18
    else
      cat "$base/remoto.bin" >"$saida"
    fi
    [[ -n $escrever ]] && printf '%s' "$codigo"
    exit 0
    ;;
  *) corpo='{}' ;;
esac
printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '200'
exit 0
FIM
  } >"$base/bin/curl"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/sleep"
  printf '%s' "$base"
}

_qa_partes() { # <base> — `.part` do destino, separados por espaco
  local p lista=''
  for p in "$1"/local/.g.iso.dbx-part.*; do [[ -e $p || -L $p ]] && lista+="$p "; done
  printf '%s' "$lista"
}

_qa_tamanho() { dbx_freebsd_real stat -c %s "$1"; }

_qa_baixar_interrompido() { # <base>
  printf '%s' "$QA_CORTE" >"$1/corte"
  _qa_rodar "$1" '' download /g.iso "$1/local/g.iso"
  assert_igual 9 "$DBX_ESTADO" "a rede cai no meio do download: $DBX_ERRO"
}

teste_premissa_dubles_bsd_fazem_de_qualquer_dev_fd_um_no_do_fdescfs() {
  dbx_freebsd_ativar
  exec 7<"$DBX_HARNESS_RAIZ/bin/dbx"
  assert_igual 'Character Device' "$(stat -f '%HT' /dev/fd/7)" 'o duble reproduz o fdescfs do FreeBSD 15 em /dev/fd/7'
  assert_igual '9999|4242' "$(stat -f '%d|%i' /dev/fd/7)" 'dev|ino do no do fdescfs, nunca os do arquivo'
  exec 7<&-
}

teste_download_retomavel_com_dubles_bsd_funciona_como_no_linux() {
  local gnu bsd part
  gnu=$(_qa_cenario_retomada)
  _qa_baixar_interrompido "$gnu"
  _qa_rodar "$gnu" '' download /g.iso "$gnu/local/g.iso"
  assert_igual 0 "$DBX_ESTADO" "GNU: retomado: $DBX_ERRO"
  cmp -s "$gnu/local/g.iso" "$gnu/remoto.bin" || _harness_falhar 'GNU: o destino deveria ser o remoto inteiro'

  bsd=$(_qa_cenario_retomada)
  dbx_freebsd_ativar
  _qa_baixar_interrompido "$bsd"
  part=$(_qa_partes "$bsd")
  assert_igual "$QA_CORTE" "$(_qa_tamanho "${part% }")" 'BSD: o .part guarda exatamente o que chegou antes da queda'
  _qa_rodar "$bsd" '' download /g.iso "$bsd/local/g.iso"
  assert_igual 0 "$DBX_ESTADO" "BSD: retomado com o /dev/fd do fdescfs: $DBX_ERRO"
  assert_igual 1 "$(_qa_conta "$bsd" "files/download $QA_CORTE")" 'BSD: o pedido de faixa parte do byte onde o .part parou'
  assert_igual "$(_qa_conta "$gnu" 'files/download')" "$(_qa_conta "$bsd" 'files/download')" 'BSD: mesmo numero de downloads que o GNU'
  cmp -s "$bsd/local/g.iso" "$bsd/remoto.bin" || _harness_falhar 'BSD: o destino deveria ser o remoto inteiro'
  assert_igual '' "$(_qa_partes "$bsd")" 'BSD: nenhum .part sobra'
  assert_nao_contem 'descartado' "$DBX_ERRO" 'BSD: a retomada nao foi descartada por falsa divergencia'
  _qa_erros_dos_dubles 'retomada'
  _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" 'retomada'
}

teste_part_trocado_por_outro_inode_com_dubles_bsd_nao_recebe_anexo() {
  local base part
  base=$(_qa_cenario_retomada)
  dbx_freebsd_ativar
  _qa_baixar_interrompido "$base"
  part=$(_qa_partes "$base")
  part=${part% }
  rm -f "$part"
  printf 'arquivo do usuario' >"$part"
  _qa_rodar "$base" '' download /g.iso "$base/local/g.iso"
  assert_igual 0 "$DBX_ESTADO" "recomeca em vez de anexar: $DBX_ERRO"
  assert_igual 'arquivo do usuario' "$(cat "$part")" 'o arquivo trocado fica intacto: nada anexado'
  assert_igual 0 "$(_qa_conta "$base" "files/download $QA_CORTE")" 'nenhum pedido de faixa sobre o .part trocado'
  cmp -s "$base/local/g.iso" "$base/remoto.bin" || _harness_falhar 'o destino e o remoto inteiro, baixado do zero'
  assert_contem 'estado de retomada descartado' "$DBX_ERRO" 'a troca foi detectada e avisada'
}

teste_part_trocado_por_ligacao_com_dubles_bsd_nao_e_seguido() {
  local base part
  base=$(_qa_cenario_retomada)
  dbx_freebsd_ativar
  _qa_baixar_interrompido "$base"
  part=$(_qa_partes "$base")
  part=${part% }
  printf 'alheio' >"$base/alheio"
  rm -f "$part"
  ln -s "$base/alheio" "$part"
  _qa_rodar "$base" '' download /g.iso "$base/local/g.iso"
  assert_igual 0 "$DBX_ESTADO" "recomeca: $DBX_ERRO"
  assert_igual 'alheio' "$(cat "$base/alheio")" 'o alvo da ligacao fica intacto'
  [[ -L $part ]] || _harness_falhar 'a ligacao foi substituida pelo produto'
}

teste_download_para_saida_padrao_com_dubles_bsd_entrega_o_corpo_pelo_descritor() {
  local base
  base=$(_qa_cenario)
  dbx_freebsd_ativar
  _qa_rodar "$base" '' download /a.txt -
  assert_igual 0 "$DBX_ESTADO" "download para stdout conclui: $DBX_ERRO"
  assert_igual 'conteudo remoto b13' "$DBX_SAIDA" 'o corpo remoto sai inteiro pela saida padrao'
  _qa_erros_dos_dubles 'stdout'
  _qa_sem_segredo "$DBX_SAIDA$DBX_ERRO" 'stdout'
}

teste_nenhum_caminho_do_produto_monta_dev_fd_com_variavel() {
  local arquivo linha achados=''
  for arquivo in "$DBX_HARNESS_RAIZ"/bin/* "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh; do
    [[ -f $arquivo ]] || continue
    while IFS= read -r linha; do
      [[ $linha == *'/dev/fd/'* ]] || continue
      [[ $linha =~ ^[[:space:]]*# ]] && continue
      achados+="${arquivo##*/}: $linha"$'\n'
    done <"$arquivo"
  done
  assert_igual '' "$achados" 'RF-171(a): nenhuma linha de codigo monta /dev/fd/<n> (so comentarios)'
}

harness_executar "$@"
