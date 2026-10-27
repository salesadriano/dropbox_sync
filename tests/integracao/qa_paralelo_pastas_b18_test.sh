#!/usr/bin/env bash
# Suite independente do QA: --paralelo/--parallel e DBX_PARALELO em `upload` e
# `download` (RF-175, RF-176; DIV-372/373/374 opcao A).
#
# Escrita como adversario, pelo executavel real `bin/dbx`, com duplo de `curl`
# proprio. Simultaneidade provada pelo duplo: cada transferencia mantem uma marca
# em $B/vivos durante o `sleep` e o pico de marcas e registrado em $B/picos; nao
# depende de tempo de parede. Bytes conferidos por `cmp` contra o conteudo de
# origem (gerado pela suite com valores proprios), nunca contra a saida do dbx.
#
# shellcheck disable=SC2016
# Justificativa: o duplo e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly QA_USO

B=''
QA_ESTADO=0
QA_SAIDA=''
QA_ERRO=''
declare -a QA_AMBIENTE=()

# _qa_cenario — credencial, duplo de rede. Controles por arquivo em $B:
# `remoto/<caminho>` (conteudo do download), `falha/<nome>` (409), `atraso/<nome>`.
_qa_cenario() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-b18.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/tmp" "$B/remoto" "$B/falha" "$B/atraso" "$B/vivos" "$B/enviado" "$B/l"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' >"$B/cfg/dbx/credencial.json"
  chmod 700 "$B/cfg/dbx"
  chmod 600 "$B/cfg/dbx/credencial.json"
  printf '{"entries":[],"has_more":false}' >"$B/listagem"
  QA_AMBIENTE=()
  {
    printf '#!%s\nb=%q\n' "$BASH" "$B"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' esc='' ant='' url='' dados=''
for a in "$@"; do
  case $ant in -o) saida=$a ;; -w) esc=$a ;; --data-binary) dados=${a#@} ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
printf '%s\n' "$url" >>"$b/chamadas"
cod=200 caminho=''
re='path\\":\\"([^\\"]*)\\"'
[[ $conf =~ $re ]] && caminho=${BASH_REMATCH[1]}
nome=${caminho##*/}
transf() {
  : >"$b/vivos/$$"
  find "$b/vivos" -type f | wc -l >>"$b/picos"
  sleep "$(cat "$b/atraso/$nome" 2>/dev/null || echo 0.3)"
  rm -f "$b/vivos/$$"
}
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:X"}' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *list_folder*) corpo=$(<"$b/listagem") ;;
  *files/download)
    transf
    corpo=$(<"$b/remoto$caminho")
    if [[ -e $b/falha/$nome ]]; then cod=409; corpo='{"error_summary":"path/not_found/.."}'; fi
    ;;
  *files/upload)
    transf
    mkdir -p "$b/enviado${caminho%/*}"
    [[ -n $dados ]] && cp "$dados" "$b/enviado$caminho"
    if [[ -e $b/falha/$nome ]]; then cod=409; corpo='{"error_summary":"path/conflict/file/.."}'
    else corpo='{"name":"x","rev":"1"}'; fi
    ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $esc ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  chmod +x "$B/bin/curl"
}

_qa_rodar() {
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" ${QA_AMBIENTE[@]+"${QA_AMBIENTE[@]}"} \
    bash "$QA_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  QA_SAIDA='' QA_ERRO=''
  IFS= read -r -d '' QA_SAIDA <"$B/out"
  IFS= read -r -d '' QA_ERRO <"$B/err"
  return 0
}

# _qa_zerar [receber] — volta ao estado inicial (conserva remoto e origem local)
_qa_zerar() {
  rm -rf "$B/estado" "$B/enviado" "$B/picos" "$B/chamadas" "$B/vivos"
  mkdir -p "$B/enviado" "$B/vivos"
  [[ ${1-} == 'receber' ]] && rm -rf "$B/l"
  return 0
}

_qa_pico() {
  local m=0 n
  [[ -r $B/picos ]] || { printf 0; return 0; }
  while IFS= read -r n; do ((n > m)) && m=$n; done <"$B/picos"
  printf '%s' "$m"
}

# _qa_conteudo <i> — bytes de origem do arquivo i (distintos por arquivo)
_qa_conteudo() { printf 'qa18-arquivo-%s-%s' "$1" "$((($1 * 7919) % 1000))"; }

# _qa_remoto <n> — n arquivos em /r/d<i%3>/f<i>.bin
_qa_remoto() {
  local i c lista=''
  for ((i = 1; i <= $1; i++)); do
    c="/r/d$((i % 3))/f$i.bin"
    mkdir -p "$B/remoto${c%/*}"
    _qa_conteudo "$i" >"$B/remoto$c"
    lista+="${lista:+,}{\".tag\":\"file\",\"path_display\":\"$c\",\"size\":20}"
  done
  printf '{"entries":[%s],"has_more":false}' "$lista" >"$B/listagem"
}

# _qa_local <n> — n arquivos em $B/l, acima de 1 MiB (envio unitario, nao em lote)
_qa_local() {
  local i f
  for ((i = 1; i <= $1; i++)); do
    mkdir -p "$B/l/d$((i % 3))"
    f="$B/l/d$((i % 3))/f$i.bin"
    _qa_conteudo "$i" >"$f"
    head -c 1048577 /dev/zero >>"$f"
    touch -d '2020-01-01 00:00:00' "$f"
  done
}

# _qa_baixado <raiz> <i> — onde o produto pos o arquivo i (a raiz do destino varia: com ou sem /r)
_qa_baixado() {
  local f
  f=$(find "$1" -path "*/d$(($2 % 3))/f$2.bin" -type f 2>/dev/null | head -n 1)
  printf '%s' "$f"
}

_qa_confere_baixados() { # <n> <raiz>
  local i f
  for ((i = 1; i <= $1; i++)); do
    f=$(_qa_baixado "$2" "$i")
    [[ -f $f ]] || _harness_falhar "arquivo ausente: d$((i % 3))/f$i.bin sob $2"
    _qa_conteudo "$i" | cmp -s - "$f" || _harness_falhar "bytes diferentes: $f"
  done
}

# _qa_enviado <i> — caminho do arquivo i no destino do envio (/r ou /r/l, conforme o produto monta)
_qa_enviado() {
  local f="$B/enviado/r/d$(($1 % 3))/f$1.bin"
  [[ -f $f ]] || f="$B/enviado/r/l/d$(($1 % 3))/f$1.bin"
  printf '%s' "$f"
}

_qa_confere_enviados() { # <n>
  local i f
  for ((i = 1; i <= $1; i++)); do
    f=$(_qa_enviado "$i")
    [[ -f $f ]] || _harness_falhar "nao enviado: f$i"
    cmp -s "$B/l/d$((i % 3))/f$i.bin" "$f" || _harness_falhar "bytes diferentes no envio: f$i"
  done
}

_qa_resumo() { # estado + stdout + stderr com o diretorio normalizado
  printf '%s|%s|%s' "$QA_ESTADO" "${QA_SAIDA//$B/BASE}" "${QA_ERRO//$B/BASE}"
}

# ---------------------------------------------------------------------------

teste_qpb01_validacao_nas_duas_formas_e_nos_dois_comandos_antes_da_rede() {
  _qa_cenario
  printf 'abc' >"$B/arq"
  _qa_remoto 2
  local op v
  for op in --paralelo --parallel; do
    for v in 0 9 -1 01 '' ' 2' 8x; do
      _qa_rodar upload "$op" "$v" "$B/arq" /r/a
      assert_igual "$QA_USO" "$QA_ESTADO" "upload $op [$v]"
      assert_contem "$op" "$QA_ERRO" "upload nomeia $op [$v]"
      _qa_rodar upload "$op" "$v" "$B/l" /r
      assert_igual "$QA_USO" "$QA_ESTADO" "upload pasta $op [$v]"
      _qa_rodar download "$op" "$v" /r "$B/saida"
      assert_igual "$QA_USO" "$QA_ESTADO" "download $op [$v]"
      assert_contem "$op" "$QA_ERRO" "download nomeia $op [$v]"
    done
    _qa_rodar download "$op"
    assert_igual "$QA_USO" "$QA_ESTADO" "download $op sem valor"
  done
  for v in 0 9 -1 01 '' ' 2'; do
    QA_AMBIENTE=("DBX_PARALELO=$v")
    _qa_rodar upload "$B/arq" /r/a
    assert_igual "$QA_USO" "$QA_ESTADO" "upload variavel [$v]"
    assert_contem DBX_PARALELO "$QA_ERRO" "upload nomeia variavel [$v]"
    _qa_rodar download /r "$B/saida"
    assert_igual "$QA_USO" "$QA_ESTADO" "download variavel [$v]"
    assert_contem DBX_PARALELO "$QA_ERRO" "download nomeia variavel [$v]"
  done
  assert_arquivo_ausente "$B/chamadas" 'nenhuma chamada de rede'
  assert_arquivo_ausente "$B/estado" 'nenhum estado'
  assert_arquivo_ausente "$B/saida" 'nenhum destino criado'
}

teste_qpb02_precedencia_opcao_sobre_variavel_e_ultima_opcao_vence() {
  _qa_cenario
  _qa_remoto 8
  _qa_local 8
  QA_AMBIENTE=(DBX_PARALELO=zzz)
  _qa_rodar download --paralelo 4 / "$B/saida"
  assert_igual 0 "$QA_ESTADO" "opcao vence variavel invalida (download): $QA_ERRO"
  _qa_zerar
  _qa_rodar upload --forcar --paralelo 4 "$B/l" /r
  assert_igual 0 "$QA_ESTADO" "opcao vence variavel invalida (upload): $QA_ERRO"
  _qa_zerar
  QA_AMBIENTE=()
  _qa_rodar download --paralelo 9 --parallel 4 / "$B/saida9"
  assert_igual 0 "$QA_ESTADO" "ultima opcao vence: $QA_ERRO"
  [[ $(_qa_pico) -gt 1 ]] || _harness_falhar "ultima opcao (4) nao paralelizou: pico $(_qa_pico)"
  _qa_zerar
  _qa_rodar download --paralelo 4 --paralelo 9 / "$B/saida2"
  assert_igual "$QA_USO" "$QA_ESTADO" 'a ultima (9) invalida recusa'
  QA_AMBIENTE=(DBX_PARALELO=4)
  _qa_zerar
  _qa_rodar download --paralelo 1 / "$B/saida3"
  assert_igual 0 "$QA_ESTADO" "$QA_ERRO"
  assert_igual 1 "$(_qa_pico)" 'opcao 1 vence variavel 4 (download)'
  _qa_zerar
  _qa_rodar upload --forcar --paralelo 1 "$B/l" /r
  assert_igual 0 "$QA_ESTADO" "$QA_ERRO"
  assert_igual 1 "$(_qa_pico)" 'opcao 1 vence variavel 4 (upload)'
}

teste_qpb03_download_de_pasta_n4_simultaneo_bytes_e_resumo_iguais_ao_n1() {
  _qa_cenario
  _qa_remoto 10
  _qa_rodar download / "$B/l"
  assert_igual 0 "$QA_ESTADO" "N=1: $QA_ERRO"
  assert_igual 1 "$(_qa_pico)" 'N=1 sequencial'
  local um
  um=$(_qa_resumo)
  _qa_confere_baixados 10 "$B/l"
  _qa_zerar receber
  _qa_rodar download --paralelo 4 / "$B/l"
  assert_igual 0 "$QA_ESTADO" "N=4: $QA_ERRO"
  [[ $(_qa_pico) -gt 1 ]] || _harness_falhar "N=4 sem simultaneidade: pico $(_qa_pico)"
  [[ $(_qa_pico) -le 4 ]] || _harness_falhar "pico acima de 4: $(_qa_pico)"
  _qa_confere_baixados 10 "$B/l"
  assert_igual "$um" "$(_qa_resumo)" 'resumo, saida e codigo iguais ao N=1'
  _qa_zerar receber
  QA_AMBIENTE=(DBX_PARALELO=4)
  _qa_rodar download / "$B/l"
  [[ $(_qa_pico) -gt 1 ]] || _harness_falhar "variavel sem simultaneidade: pico $(_qa_pico)"
  _qa_confere_baixados 10 "$B/l"
}

teste_qpb04_upload_de_pasta_n4_simultaneo_bytes_e_resumo_iguais_ao_n1() {
  _qa_cenario
  _qa_local 10
  _qa_rodar upload --forcar "$B/l" /r
  assert_igual 0 "$QA_ESTADO" "N=1: $QA_ERRO"
  assert_igual 1 "$(_qa_pico)" 'N=1 sequencial'
  local um
  um=$(_qa_resumo)
  _qa_confere_enviados 10
  _qa_zerar
  _qa_rodar upload --forcar --paralelo 4 "$B/l" /r
  assert_igual 0 "$QA_ESTADO" "N=4: $QA_ERRO"
  [[ $(_qa_pico) -gt 1 ]] || _harness_falhar "N=4 sem simultaneidade: pico $(_qa_pico)"
  [[ $(_qa_pico) -le 4 ]] || _harness_falhar "pico acima de 4: $(_qa_pico)"
  _qa_confere_enviados 10
  assert_igual "$um" "$(_qa_resumo)" 'resumo, saida e codigo iguais ao N=1'
  _qa_zerar
  QA_AMBIENTE=(DBX_PARALELO=4)
  _qa_rodar upload --forcar "$B/l" /r
  [[ $(_qa_pico) -gt 1 ]] || _harness_falhar "variavel sem simultaneidade: pico $(_qa_pico)"
  _qa_confere_enviados 10
}

teste_qpb05_falha_de_um_item_com_n4_nao_derruba_os_outros_e_mantem_o_codigo() {
  _qa_cenario
  _qa_remoto 9
  : >"$B/falha/f5.bin"
  _qa_rodar download / "$B/l"
  local cod_um=$QA_ESTADO um i
  um=$(_qa_resumo)
  assert_diferente 0 "$cod_um" 'a falha do item aparece no codigo (N=1)'
  _qa_zerar receber
  _qa_rodar download --paralelo 4 / "$B/l"
  assert_igual "$cod_um" "$QA_ESTADO" 'download: mesmo codigo do N=1'
  assert_igual "$um" "$(_qa_resumo)" 'download: mesmo resumo do N=1'
  for i in 1 2 3 4 6 7 8 9; do
    _qa_conteudo "$i" | cmp -s - "$(_qa_baixado "$B/l" "$i")" || _harness_falhar "download: f$i perdido pela falha de f5"
  done
  [[ -z $(_qa_baixado "$B/l" 5) ]] || _harness_falhar 'download: o item falho nao deveria existir'

  _qa_cenario
  _qa_local 9
  : >"$B/falha/f5.bin"
  _qa_rodar upload --forcar "$B/l" /r
  cod_um=$QA_ESTADO
  um=$(_qa_resumo)
  assert_diferente 0 "$cod_um" 'a falha do item aparece no codigo (upload N=1)'
  _qa_zerar
  _qa_rodar upload --forcar --paralelo 4 "$B/l" /r
  assert_igual "$cod_um" "$QA_ESTADO" 'upload: mesmo codigo do N=1'
  assert_igual "$um" "$(_qa_resumo)" 'upload: mesmo resumo do N=1'
  for i in 1 2 3 4 6 7 8 9; do
    cmp -s "$B/l/d$((i % 3))/f$i.bin" "$(_qa_enviado "$i")" || _harness_falhar "upload: f$i perdido pela falha de f5"
  done
}

teste_qpb06_dry_run_com_n_aceita_valida_e_nao_transfere() {
  _qa_cenario
  _qa_remoto 4
  _qa_local 4
  _qa_rodar --dry-run upload --paralelo 4 "$B/l" /r
  assert_igual 0 "$QA_ESTADO" "upload: $QA_ERRO"
  _qa_rodar --dry-run download --parallel 4 /r "$B/saida"
  assert_igual 0 "$QA_ESTADO" "download: $QA_ERRO"
  QA_AMBIENTE=(DBX_PARALELO=4)
  _qa_rodar --dry-run upload "$B/l" /r
  assert_igual 0 "$QA_ESTADO" 'variavel valida em dry-run'
  QA_AMBIENTE=()
  _qa_rodar --dry-run upload --paralelo 9 "$B/l" /r
  assert_igual "$QA_USO" "$QA_ESTADO" 'dry-run valida N (upload)'
  _qa_rodar --dry-run download --paralelo 0 /r "$B/saida"
  assert_igual "$QA_USO" "$QA_ESTADO" 'dry-run valida N (download)'
  assert_igual 0 "$(_qa_pico)" 'nenhuma transferencia'
  assert_arquivo_ausente "$B/saida" 'nenhum arquivo criado'
  [[ -z $(find "$B/enviado" -type f) ]] || _harness_falhar 'nada enviado em dry-run'
  _qa_rodar --dry-run upload "$B/l" /r
  local sem=$QA_SAIDA
  _qa_rodar --dry-run upload --paralelo 4 "$B/l" /r
  assert_igual "$sem" "$QA_SAIDA" 'dry-run com N identico a sem N'
}

teste_qpb07_stdin_e_stdout_recusam_a_opcao_e_ignoram_a_variavel() {
  _qa_cenario
  _qa_remoto 2
  local op
  for op in --paralelo --parallel; do
    _qa_rodar upload "$op" 2 - /r/a
    assert_igual "$QA_USO" "$QA_ESTADO" "upload stdin $op"
    _qa_rodar download "$op" 2 /r/d2/f2.bin -
    assert_igual "$QA_USO" "$QA_ESTADO" "download stdout $op"
    _qa_rodar download "$op" 2 /r/d2/f2.bin
    assert_igual "$QA_USO" "$QA_ESTADO" "download sem destino $op"
    _qa_rodar download "$op" 1 /r/d2/f2.bin -
    assert_igual "$QA_USO" "$QA_ESTADO" "download stdout $op 1 (ate o 1 recusa)"
  done
  assert_arquivo_ausente "$B/chamadas" 'recusa antes da rede'
  QA_AMBIENTE=(DBX_PARALELO=99)
  _qa_rodar download /r/d2/f2.bin -
  assert_igual 0 "$QA_ESTADO" "stdout ignora variavel invalida: $QA_ERRO"
  assert_igual "$(_qa_conteudo 2)" "$QA_SAIDA" 'bytes na saida padrao'
  QA_AMBIENTE=(DBX_PARALELO=4)
  _qa_rodar download /r/d2/f2.bin -
  assert_igual 0 "$QA_ESTADO" 'stdout ignora variavel valida'
  assert_igual "$(_qa_conteudo 2)" "$QA_SAIDA" 'bytes na saida padrao com variavel valida'
}

teste_qpb08_arquivo_unico_aceita_e_segue_sequencial() {
  _qa_cenario
  _qa_remoto 2
  _qa_local 1
  _qa_rodar upload --forcar --paralelo 4 "$B/l/d1/f1.bin" /r/f1.bin
  assert_igual 0 "$QA_ESTADO" "upload: $QA_ERRO"
  assert_igual 1 "$(_qa_pico)" 'arquivo unico sequencial'
  _qa_zerar
  _qa_rodar download --paralelo 4 /r/d2/f2.bin "$B/um.bin"
  assert_igual 0 "$QA_ESTADO" "download: $QA_ERRO"
  _qa_conteudo 2 | cmp -s - "$B/um.bin" || _harness_falhar 'bytes do arquivo unico'
}

teste_qpb09_comandos_sem_suporte_recusam_a_opcao_e_ignoram_a_variavel() {
  _qa_cenario
  local c
  for c in list info delete; do
    _qa_rodar "$c" --paralelo 2 /x
    assert_igual "$QA_USO" "$QA_ESTADO" "$c com --paralelo"
    _qa_rodar "$c" --parallel 2 /x
    assert_igual "$QA_USO" "$QA_ESTADO" "$c com --parallel"
  done
  QA_AMBIENTE=(DBX_PARALELO=99)
  _qa_rodar list /
  assert_diferente "$QA_USO" "$QA_ESTADO" "list ignora a variavel invalida: $QA_ERRO"
  _qa_rodar info /x
  assert_diferente "$QA_USO" "$QA_ESTADO" "info ignora a variavel invalida: $QA_ERRO"
}

teste_qpb10_diagnostico_mostra_o_n_efetivo_da_variavel() {
  _qa_cenario
  QA_AMBIENTE=(DBX_PARALELO=3)
  _qa_rodar diagnostico
  assert_contem 'paralelo' "$QA_SAIDA$QA_ERRO" 'diagnostico cita paralelo'
  assert_contem '3 (origem: ambiente' "$QA_SAIDA$QA_ERRO" 'diagnostico mostra o N e a origem'
  QA_AMBIENTE=()
  _qa_rodar diagnostico
  assert_nao_contem 'DBX_PARALELO' "$QA_SAIDA$QA_ERRO" 'sem a variavel, saida de sempre'
}

harness_executar "$@"
