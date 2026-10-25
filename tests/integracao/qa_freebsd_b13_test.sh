#!/usr/bin/env bash
# Suite independente do QA, demanda suporte-freebsd (RF-166 a RF-172, RNF-39,
# TC-FBSD-*).
#
# ADVERSARIA, pelo executavel real (bin/dbx) com os dubles BSD (chmod, stat,
# find, sha256) a frente do PATH e duplo de rede proprio. Cobre o que a suite
# do desenvolvedor nao exercita de ponta a ponta: `config` com chmod BSD,
# transferencias reais, `sync --enviar` repetido (comparado com o mesmo
# roteiro em GNU), credencial/diretorio inseguros recusados igualmente nas duas
# formas, preflight de /dev/fd e ausencia de erro de uso nos dubles.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e escrito sem expansao.
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

_qa_descritores() { # [diretorio]
  env -i PATH="$PATH" "$BASH" -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    if [[ $# -ge 2 ]]; then dbx_preflight_descritores "$2"; else dbx_preflight_descritores; fi
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" "$@" 2>/dev/null
}

teste_preflight_de_descritores_com_dubles_bsd_recusa_sem_fdescfs_e_passa_com()  {
  local vazio
  dbx_freebsd_ativar
  vazio=$(mktemp -d "$DBX_TESTES_TMP/qa-devfd.XXXXXX")
  assert_igual 0 "$(_qa_descritores)" '/dev/fd real com os dubles BSD passa'
  assert_igual 3 "$(_qa_descritores "$vazio")" 'diretorio sem descritores e recusado com 3'
  assert_igual 3 "$(_qa_descritores /nao/existe/qa-b13)" 'diretorio inexistente e recusado com 3'
  assert_igual '' "$(dbx_freebsd_erros)" 'a sonda nao gerou erro de uso nos dubles'
}

harness_executar "$@"
