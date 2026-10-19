#!/usr/bin/env bash
# Suite independente do QA Expert — fase 4 (aliases, origem vazia pelo plano,
# localidade da comparacao e coerencia da documentacao).
#
# Porte G: validacao independente sobre os itens afetados (RF-64, RF-41(b) com
# O-1 e DIV-30, RF-54(e)(f)(g), RNF-34). Os cenarios sao do QA, com massa e
# duplos proprios; nenhum reaproveita caso do Senior Developer. Onde o
# Senior Developer comparou o PLANO da simulacao, este arquivo compara o
# ESTADO resultante da execucao real (RF-64(b)), sobre a mesma arvore
# restaurada de uma fotografia, para que so o nome da opcao varie.
#
# Precedencia e origem dos dados: cada caso monta o proprio cenario (credencial
# sintetica, duplo de `curl`, arvore local); a primeira execucao de um caso e o
# "seeder" das seguintes. A limpeza e a da area do executor, ao fim do roteiro.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os trechos de `bash -c` sao literais.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QA_E_MAIUSCULO=$'\xc3\x89'
readonly QA_E_MINUSCULO=$'\xc3\xa9'
# Token sintetico reconhecivel: nao pode aparecer em saida nenhuma (RNF-03).
readonly QA_TOKEN='rt_QA_P4_sigiloso'
readonly QA_SEGREDO='as_QA_P4_sigiloso'

# _qa_cenario — credencial, duplo de rede e arvore local. Publica BASE.
#
# O duplo registra cada URL em `chamadas` e a configuracao recebida em `opcoes`.
# Arquivos de controle em BASE mudam a resposta:
#   listagem           corpo do `list_folder`
#   listagem_codigo    codigo do `list_folder` (com corpo de erro)
_qa_cenario() {
  BASE=$(mktemp -d "$DBX_TESTES_TMP/qa_p4.XXXXXX")
  mkdir -p "$BASE/config/dbx" "$BASE/bin" "$BASE/local"
  printf '{"versao":1,"app_key":"ak","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$QA_SEGREDO" "$QA_TOKEN" >"$BASE/config/dbx/credencial.json"
  chmod 700 "$BASE/config/dbx"
  chmod 600 "$BASE/config/dbx/credencial.json"
  {
    printf '#!/usr/bin/env bash\nbase=%q\n' "$BASE"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
printf '%s\n' "$conf" >>"$base/opcoes"
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:QAP4"}' ;;
  *list_folder*)
    if [[ -f $base/listagem ]]; then corpo=$(cat "$base/listagem")
    else corpo='{"entries":[],"has_more":false}'; fi
    if [[ -f $base/listagem_codigo ]]; then
      codigo=$(cat "$base/listagem_codigo"); corpo='{"error_summary":"path/not_found/.."}'
    fi ;;
  *files/get_metadata*) codigo=409; corpo='{"error_summary":"path/not_found/.."}' ;;
  *files/download*) corpo='conteudo remoto' ;;
  *files/upload) corpo='{"name":"a.txt","rev":"0a1"}' ;;
  *token/revoke*) corpo='null' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$BASE/bin/curl"
  chmod +x "$BASE/bin/curl"
  : >"$BASE/chamadas"
}

# _qa_rodar [NOME=valor...] -- <argumentos...> — `bin/dbx` em ambiente minimo,
# com atribuicoes extras antes do `--`.
_qa_rodar() {
  local -a extra=()
  while [[ $# -gt 0 && $1 != -- ]]; do
    extra+=("$1")
    shift
  done
  shift
  SAIDA='' ERRO=''
  env -i PATH="$BASE/bin:$PATH" HOME="$BASE" XDG_CONFIG_HOME="$BASE/config" \
    XDG_STATE_HOME="$BASE/estado" TMPDIR="$DBX_TESTES_TMP" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    ${extra[@]+"${extra[@]}"} \
    bash "$DBX_EXEC" "$@" </dev/null >"$BASE/out" 2>"$BASE/err"
  ESTADO=$?
  IFS= read -r -d '' SAIDA <"$BASE/out"
  IFS= read -r -d '' ERRO <"$BASE/err"
  return 0
}

_qa_contar() { _harness_contar "$1" "$BASE/chamadas"; } # <padrao>
_qa_exclusoes() { _qa_contar 'files/delete_v2'; }
_qa_escritas() { _qa_contar 'files/upload\|files/delete_v2\|upload_session\|create_folder'; }
_qa_rede() { _qa_contar 'http'; }

_qa_hash() { dbx_hash_conteudo_arquivo "$1"; }

_qa_listagem() { # <entrada...>
  local IFS=,
  printf '{"entries":[%s],"has_more":false}' "$*" >"$BASE/listagem"
}

_qa_entrada() { # <caminho_display> <caminho_lower> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","path_lower":"%s","content_hash":"%s","size":%s,"rev":"0a1"}' \
    "$1" "$2" "$3" "$4"
}

# _qa_fotografar / _qa_restaurar — a mesma arvore (mesmo caminho absoluto) para
# duas execucoes que so diferem no nome da opcao.
_qa_fotografar() {
  rm -rf -- "$BASE.foto"
  cp -a -- "$BASE" "$BASE.foto"
}
_qa_restaurar() {
  rm -rf -- "$BASE"
  cp -a -- "$BASE.foto" "$BASE"
}

# _qa_estado_final — tudo o que uma execucao deixa: codigo, stdout, URLs
# chamadas, arvore local com conteudo, credencial e memoria do `sync`.
_qa_estado_final() {
  printf 'codigo=%s\n--saida--\n%s\n--chamadas--\n' "$ESTADO" "$SAIDA"
  cat -- "$BASE/chamadas"
  printf -- '--arvore--\n'
  (cd -- "$BASE" && find local config estado -print 2>/dev/null | LC_ALL=C sort)
  printf -- '--conteudo--\n'
  (cd -- "$BASE" && find local config estado -type f -print0 2>/dev/null |
    LC_ALL=C sort -z | xargs -0 -r cksum --)
}

_qa_localidade_utf8_existe() {
  [[ $(env -i LC_ALL=C bash -c 'f() { local LC_ALL=C.UTF-8; printf %s "${1,,}"; }; f "$1"' _ \
    "$QA_E_MAIUSCULO" 2>/dev/null) == "$QA_E_MINUSCULO" ]]
}

# ===========================================================================
# 1. ALIASES — RF-64 (TC-ALI-01..03)
# ===========================================================================

teste_qa_p4_alias_sync_execucao_real_em_ingles_misto_e_portugues_deixa_o_mesmo_estado() {
  # RF-64(b)(d): efeito, saida estruturada, chamadas, memoria e arvore
  # identicos, na execucao REAL com espelhamento, nos dois sentidos.
  local pt en misto
  _qa_cenario
  printf 'novo' >"$BASE/local/novo.txt"
  printf 'igual' >"$BASE/local/igual.txt"
  _qa_listagem "$(_qa_entrada /r/orfao.txt /r/orfao.txt ff 1)" \
    "$(_qa_entrada /r/igual.txt /r/igual.txt "$(_qa_hash "$BASE/local/igual.txt")" 5)"
  _qa_fotografar
  _qa_rodar -- --json sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$ESTADO" "enviar em portugues conclui; diagnostico: $ERRO"
  assert_igual 1 "$(_qa_exclusoes)" 'o portugues apaga o orfao'
  pt=$(_qa_estado_final)
  _qa_restaurar
  _qa_rodar -- --json sync --push --source "$BASE/local" --dest /r --mirror --yes
  en=$(_qa_estado_final)
  _qa_restaurar
  _qa_rodar -- --json sync --mirror --dest /r --yes --push --origem "$BASE/local"
  misto=$(_qa_estado_final)
  assert_igual "$pt" "$en" 'enviar: estado final em ingles igual ao portugues'
  assert_igual "$pt" "$misto" 'enviar: estado final misto (outra ordem) igual ao portugues'

  _qa_cenario
  printf 'meu' >"$BASE/local/so_local.txt"
  _qa_listagem "$(_qa_entrada /r/remoto.txt /r/remoto.txt ff 15)"
  _qa_fotografar
  _qa_rodar -- --json sync --receber --origem /r --destino "$BASE/local" --espelhar --confirmar
  assert_igual 0 "$ESTADO" "receber em portugues conclui; diagnostico: $ERRO"
  assert_arquivo_ausente "$BASE/local/so_local.txt" 'o portugues apaga o que nao existe na origem'
  pt=$(_qa_estado_final)
  _qa_restaurar
  _qa_rodar -- --json sync --pull --source /r --dest "$BASE/local" --mirror --yes
  en=$(_qa_estado_final)
  assert_igual "$pt" "$en" 'receber: estado final em ingles igual ao portugues'
}

teste_qa_p4_alias_formas_nao_aceitas_recusam_como_o_portugues_sem_rede() {
  # Nao ha forma `--opcao=valor` nem abreviacao: o alias nao abre nenhuma.
  # Cada forma e recusada como uso invalido, igual a forma em portugues, e
  # nenhuma chamada de rede sai.
  local uso forma
  uso=$(dbx_errors_codigo_saida uso_invalido)
  _qa_cenario
  printf 'x' >"$BASE/local/x.txt"
  for forma in "--source=$BASE/local" "--origem=$BASE/local"; do
    : >"$BASE/chamadas"
    _qa_rodar -- sync --push "$forma" --dest /r
    assert_igual "$uso" "$ESTADO" "$forma: uso invalido"
    assert_contem 'opcao nao reconhecida' "$ERRO" "$forma: recusada como opcao desconhecida"
    assert_igual 0 "$(_qa_rede)" "$forma: nenhuma chamada de rede"
  done
  for forma in --pu --pul --pus --sour --sourc --de --des --mirr --ye --allow-empty --allow-empty-sourc \
    --PUSH --Pull --YES --keep-app --replace --root; do
    : >"$BASE/chamadas"
    _qa_rodar -- sync --enviar --origem "$BASE/local" --destino /r "$forma"
    assert_igual "$uso" "$ESTADO" "sync $forma: uso invalido"
    assert_igual 0 "$(_qa_rede)" "sync $forma: nenhuma chamada de rede"
  done
  # Opcao com valor sem o valor: mesma recusa pelos dois nomes.
  local pt
  _qa_rodar -- sync --enviar --destino /r --origem
  pt=$ESTADO
  _qa_rodar -- sync --enviar --destino /r --source
  assert_igual "$uso" "$pt" '--origem sem valor: uso invalido'
  assert_igual "$pt" "$ESTADO" '--source sem valor: mesma recusa'
  _qa_rodar -- sync --enviar --origem "$BASE/local" --destino
  pt=$ESTADO
  _qa_rodar -- sync --enviar --origem "$BASE/local" --dest
  assert_igual "$pt" "$ESTADO" '--dest sem valor: mesma recusa de --destino'
  # Aliases de outro comando nao valem aqui, nem os do sync nos outros.
  _qa_rodar -- unlink --push
  assert_igual "$uso" "$ESTADO" 'unlink --push: uso invalido'
  _qa_rodar -- unlink --mirror
  assert_igual "$uso" "$ESTADO" 'unlink --mirror: uso invalido'
  _qa_rodar -- config --yes
  assert_igual "$uso" "$ESTADO" 'config --yes: uso invalido'
  assert_arquivo_existe "$BASE/config/dbx/credencial.json" 'nenhuma recusa tocou a credencial'
}

teste_qa_p4_alias_repeticao_pelos_dois_nomes_segue_a_regra_do_portugues() {
  # RF-64(e), DIV-31: segundo sentido recusado em qualquer combinacao de nomes;
  # opcao sem valor idempotente; opcao com valor vale o ultimo.
  local uso par ref obtido
  uso=$(dbx_errors_codigo_saida uso_invalido)
  _qa_cenario
  printf 'novo' >"$BASE/local/novo.txt"
  _qa_listagem "$(_qa_entrada /r/orfao.txt /r/orfao.txt ff 1)"
  for par in '--push --enviar' '--pull --pull' '--push --push' '--receber --pull' '--push --receber' \
    '--pull --enviar' '--enviar --pull'; do
    : >"$BASE/chamadas"
    # shellcheck disable=SC2086  # o par se divide de proposito em duas opcoes
    _qa_rodar -- sync $par --origem "$BASE/local" --destino /r
    assert_igual "$uso" "$ESTADO" "$par: segundo sentido e uso invalido"
    assert_contem 'mutuamente exclusiv' "$ERRO" "$par: pela regra do sentido"
    assert_igual 0 "$(_qa_rede)" "$par: nada sai para a rede"
  done
  _qa_rodar -- --json --dry-run sync --enviar --origem "$BASE/local" --destino /r --espelhar --confirmar
  ref="$ESTADO|$SAIDA"
  assert_contem 'apagar=orfao.txt' "$ref" 'a referencia lista a exclusao'
  _qa_rodar -- --json --dry-run sync --push --origem "$BASE/local" --dest /r --mirror --espelhar --mirror \
    --yes --confirmar --yes
  obtido="$ESTADO|$SAIDA"
  assert_igual "$ref" "$obtido" 'opcoes sem valor repetidas pelos dois nomes sao idempotentes'
  _qa_rodar -- --json --dry-run sync --push --source /nao/existe --origem "$BASE/local" \
    --destino /outro --dest /r --mirror --yes
  assert_igual "$ref" "$ESTADO|$SAIDA" 'com valor: o ultimo vale, em qualquer ordem de nomes'
}

teste_qa_p4_alias_unlink_ingles_misto_e_repetido_deixam_o_estado_do_portugues() {
  # TC-ALI-02: mesmo codigo, mesma saida, mesma credencial e mesmo estado.
  local pt variante
  _qa_cenario
  mkdir -p "$BASE/estado/dbx"
  printf 'base' >"$BASE/estado/dbx/memoria-qa"
  _qa_fotografar
  _qa_rodar -- --json unlink --confirmar --manter-aplicativo
  assert_igual 0 "$ESTADO" "unlink em portugues conclui; diagnostico: $ERRO"
  assert_contem '"app_key":"ak"' "$(cat "$BASE/config/dbx/credencial.json")" 'a chave fica'
  pt=$(_qa_estado_final)
  for variante in '--yes --keep-app' '--keep-app --yes' '--yes --manter-aplicativo' \
    '--keep-app --confirmar' '--yes --yes --keep-app --keep-app' '--confirmar --yes --manter-aplicativo --keep-app'; do
    _qa_restaurar
    # shellcheck disable=SC2086
    _qa_rodar -- --json unlink $variante
    assert_igual "$pt" "$(_qa_estado_final)" "unlink $variante: mesmo estado que o portugues"
  done
  _qa_restaurar
  _qa_rodar -- --json unlink --confirmar
  pt=$(_qa_estado_final)
  _qa_restaurar
  _qa_rodar -- --json unlink --yes
  assert_igual "$pt" "$(_qa_estado_final)" 'unlink --yes sem keep-app: mesmo estado que --confirmar'
  assert_arquivo_ausente "$BASE/config/dbx/credencial.json" 'e a credencial sai inteira'
  assert_segredo_ausente "$QA_TOKEN" "$SAIDA$ERRO" 'o token nao aparece em saida nenhuma'
}

teste_qa_p4_alias_config_recusas_e_ultimo_valor_iguais_ao_portugues() {
  # TC-ALI-03: recusa sem valor, forma com `=`, credencial existente, raiz
  # invalida e repeticao — o alias se comporta como o nome em portugues.
  local pt en
  _qa_cenario
  # Credencial existente sem substituir: a recusa e a mesma.
  _qa_rodar -- config --raiz /a
  pt="$ESTADO"
  _qa_rodar -- config --root /a
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$pt" 'portugues: credencial existente recusada'
  assert_igual "$pt" "$ESTADO" '--root: mesma recusa'
  assert_contem '--replace' "$ERRO" 'a recusa cita o alias'
  rm -f -- "$BASE/config/dbx/credencial.json"
  local caso
  for caso in '--raiz|--root' '--raiz=/x|--root=/x' '--raiz /../x|--root /../x'; do
    # shellcheck disable=SC2086
    _qa_rodar -- --json --dry-run config ${caso%|*}
    pt="$ESTADO|$SAIDA"
    # shellcheck disable=SC2086
    _qa_rodar -- --json --dry-run config ${caso#*|}
    en="$ESTADO|$SAIDA"
    assert_diferente 0 "${pt%%|*}" "${caso%|*}: recusada"
    assert_igual "$pt" "$en" "${caso#*|}: mesma recusa e mesma saida de ${caso%|*}"
  done
  _qa_rodar -- --json --dry-run config --root /um --raiz /dois --root /tres
  assert_igual 0 "$ESTADO" "repeticao conclui; diagnostico: $ERRO"
  assert_contem 'raiz_remota=/tres' "$SAIDA" 'o ultimo valor vale'
  pt="$SAIDA"
  _qa_rodar -- --json --dry-run config --replace --substituir --replace --raiz /tres
  assert_igual 0 "$ESTADO" "--replace repetido e idempotente; diagnostico: $ERRO"
  assert_igual "$pt" "$SAIDA" 'mesma referencia com ou sem --replace repetido'
}

teste_qa_p4_alias_ajuda_e_readme_documentam_os_onze_pares() {
  # RF-64(c): cada par na mesma linha da ajuda do comando e do README.
  local -a pares=(
    'sync|--origem|--source' 'sync|--destino|--dest' 'sync|--enviar|--push' 'sync|--receber|--pull'
    'sync|--espelhar|--mirror' 'sync|--confirmar|--yes' 'sync|--permitir-origem-vazia|--allow-empty-source'
    'unlink|--confirmar|--yes' 'unlink|--manter-aplicativo|--keep-app'
    'config|--substituir|--replace' 'config|--raiz|--root'
  )
  local par comando pt en readme
  IFS= read -r -d '' readme <"$DBX_HARNESS_RAIZ/README.md"
  _qa_cenario
  for par in "${pares[@]}"; do
    IFS='|' read -r comando pt en <<<"$par"
    _qa_rodar -- help "$comando"
    assert_igual 0 "$ESTADO" "help $comando sai com 0"
    assert_igual 1 "$(_harness_contar "^  ${pt}, ${en}\( \|\$\)" "$BASE/out")" \
      "help $comando: linha de opcao com $pt e $en juntos"
    assert_contem "$en" "${SAIDA%%$'\n'*}" "help $comando: o Uso: lista $en"
    assert_contem "$pt" "${SAIDA%%$'\n'*}" "help $comando: o Uso: lista $pt"
    assert_contem "$en" "$readme" "README documenta $en"
  done
}

# ===========================================================================
# 2. ORIGEM VAZIA PELO PLANO — RF-41(b), O-1, DIV-30 (TC-DEL-13)
# ===========================================================================

teste_qa_p4_guarda_pull_mirror_yes_sem_memoria_recusa_pelo_plano_e_so_allow_libera() {
  # Par nunca visto, origem remota vazia, destino local povoado.
  local recusa
  recusa=$(dbx_errors_codigo_saida nao_concluida)
  _qa_cenario
  printf 'um' >"$BASE/local/um.txt"
  printf 'dois' >"$BASE/local/dois.txt"
  _qa_rodar -- --json sync --pull --source /r --dest "$BASE/local" --mirror --yes
  assert_igual "$recusa" "$ESTADO" "origem remota vazia: recusa; diagnostico: $ERRO"
  assert_contem 'recusada=origem vazia' "$SAIDA" 'a recusa sai pelo plano'
  assert_nao_contem 'memoria' "$ERRO" 'a mensagem nao cita a memoria'
  assert_contem 'allow-empty-source' "$ERRO" 'e cita a saida pelo alias'
  assert_arquivo_existe "$BASE/local/um.txt" 'local intacto'
  assert_arquivo_existe "$BASE/local/dois.txt" 'local intacto'
  assert_igual 0 "$(_qa_escritas)" 'nenhuma escrita remota'
  _qa_rodar -- --json --dry-run sync --pull --source /r --dest "$BASE/local" --mirror --yes
  assert_igual 0 "$ESTADO" 'simulacao sai com 0'
  assert_contem 'recusaria=origem vazia' "$SAIDA" 'simulacao anuncia a recusa'
  assert_arquivo_existe "$BASE/local/um.txt" 'simulacao nao apaga'
  _qa_rodar -- --json sync --pull --source /r --dest "$BASE/local" --mirror --yes --allow-empty-source
  assert_igual 0 "$ESTADO" "--allow-empty-source libera; diagnostico: $ERRO"
  assert_arquivo_ausente "$BASE/local/um.txt" 'e o destino e espelhado'
  assert_arquivo_ausente "$BASE/local/dois.txt" 'e o destino e espelhado'

  # O mesmo no `--push`: par nunca visto, raiz local vazia, remoto povoado. Aqui
  # a memoria e a linha de base ficam vazias, e so a guarda pelo plano protege.
  _qa_cenario
  _qa_listagem "$(_qa_entrada /r/a.txt /r/a.txt ff 1)" "$(_qa_entrada /r/b.txt /r/b.txt ee 1)"
  _qa_rodar -- --json sync --push --source "$BASE/local" --dest /r --mirror --yes
  assert_igual "$recusa" "$ESTADO" "push: origem local vazia sem memoria recusa; diagnostico: $ERRO"
  assert_contem 'recusada=origem vazia' "$SAIDA" 'push: a recusa sai pelo plano'
  assert_igual 0 "$(_qa_escritas)" 'push: nenhuma escrita remota'
}

teste_qa_p4_guarda_sem_espelhar_origem_vazia_nao_escreve_nada_e_sai_zero() {
  # DIV-30: sem `--espelhar` nada seria apagado; com memoria povoada a guarda
  # antiga recusava. Agora e operacao vazia, sem escrita alguma.
  local antes
  _qa_cenario
  printf 'aaaa' >"$BASE/local/a.txt"
  _qa_listagem "$(_qa_entrada /r/a.txt /r/a.txt "$(_qa_hash "$BASE/local/a.txt")" 4)"
  _qa_rodar -- sync --push --source "$BASE/local" --dest /r --mirror --yes
  assert_igual 0 "$ESTADO" "semeadura; diagnostico: $ERRO"
  rm -f -- "$BASE/local/a.txt"
  : >"$BASE/chamadas"
  _qa_rodar -- --json sync --push --source "$BASE/local" --dest /r --yes
  assert_igual 0 "$ESTADO" "enviar sem --mirror: operacao vazia; diagnostico: $ERRO"
  assert_igual 0 "$(_qa_escritas)" 'enviar: nenhuma escrita remota'
  assert_nao_contem 'recusad' "$SAIDA" 'enviar: nenhuma recusa no plano'

  _qa_cenario
  printf 'cccc' >"$BASE/local/c.txt"
  _qa_listagem "$(_qa_entrada /r/c.txt /r/c.txt "$(_qa_hash "$BASE/local/c.txt")" 4)"
  _qa_rodar -- sync --pull --source /r --dest "$BASE/local" --mirror --yes
  assert_igual 0 "$ESTADO" "semeadura receber; diagnostico: $ERRO"
  _qa_listagem
  antes=$(stat -c '%n %s %Y' -- "$BASE/local"/*)
  : >"$BASE/chamadas"
  _qa_rodar -- --json sync --pull --source /r --dest "$BASE/local"
  assert_igual 0 "$ESTADO" "receber sem --mirror: operacao vazia; diagnostico: $ERRO"
  assert_igual "$antes" "$(stat -c '%n %s %Y' -- "$BASE/local"/*)" 'receber: destino local intocado'
  assert_igual 0 "$(_qa_contar 'files/download')" 'receber: nada baixado'
  assert_igual 0 "$(_qa_escritas)" 'receber: nenhuma escrita remota'
}

teste_qa_p4_guarda_raiz_ausente_ou_arquivo_segue_recusada_sem_espelhar() {
  # A remocao da guarda antiga nao transforma raiz invalida em origem vazia.
  local alvo
  _qa_cenario
  printf 'x' >"$BASE/arquivo_solto"
  for alvo in "$BASE/nao_existe" "$BASE/arquivo_solto"; do
    : >"$BASE/chamadas"
    _qa_rodar -- sync --push --source "$alvo" --dest /r
    assert_diferente 0 "$ESTADO" "$alvo sem --mirror: recusada"
    assert_igual 0 "$(_qa_escritas)" "$alvo: nenhuma escrita"
  done
  # Raiz REMOTA inexistente no `--pull` e, por projeto, origem vazia (a listagem
  # `path/not_found` e tratada como vazia): com `--mirror --yes` a recusa e a
  # de origem vazia, pelo plano, e o destino local fica.
  printf '409' >"$BASE/listagem_codigo"
  printf 'meu' >"$BASE/local/meu.txt"
  _qa_rodar -- --json sync --pull --source /nao_existe --dest "$BASE/local" --mirror --yes
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" 'raiz remota inexistente: recusa 14'
  assert_contem 'recusada=origem vazia' "$SAIDA" 'pelo plano, como origem vazia'
  assert_arquivo_existe "$BASE/local/meu.txt" 'e o destino local fica'
}

# ===========================================================================
# 3. LOCALIDADE DA COMPARACAO — RF-54(e)(f)(g) (TC-CX-04, TC-CX-05)
# ===========================================================================

teste_qa_p4_localidade_receber_espelhado_com_lc_all_c_nao_duplica_nem_apaga() {
  # TC-CX-04 no sentido que o Senior Developer nao exercitou: `É` local e `é`
  # remoto com o mesmo conteudo, `--pull --mirror` sob `LC_ALL=C`.
  _qa_localidade_utf8_existe || pular 'localidade C.UTF-8 ausente nesta maquina (TC-CX-05 cobre a ausencia)'
  local nome_local="${QA_E_MAIUSCULO}x.txt" nome_remoto="${QA_E_MINUSCULO}x.txt"
  _qa_cenario
  printf 'mesmo' >"$BASE/local/$nome_local"
  _qa_listagem "$(_qa_entrada "/r/$nome_remoto" "/r/$nome_remoto" "$(_qa_hash "$BASE/local/$nome_local")" 5)"
  _qa_rodar LC_ALL=C LANG=C -- --json sync --pull --source /r --dest "$BASE/local" --mirror --yes
  assert_igual 0 "$ESTADO" "sync conclui; diagnostico: $ERRO"
  assert_arquivo_existe "$BASE/local/$nome_local" 'o arquivo local nao e apagado'
  assert_arquivo_ausente "$BASE/local/$nome_remoto" 'nem duplicado com a grafia remota'
  assert_igual 0 "$(_qa_contar 'files/download')" 'conteudo igual: nada baixado'
  assert_nao_contem 'C.UTF-8' "$ERRO" 'sem aviso com a localidade presente'
}

teste_qa_p4_localidade_fixacao_nao_vaza_para_o_processo_sob_c_e_sob_utf8() {
  # RF-54(e), DIV-32: depois da comparacao, `LC_ALL` do processo volta ao que
  # era (inclusive ausente), e a medida de `${#x}` e o escape de `lib/json` sao
  # os mesmos de antes dela, sob `LC_ALL=C` e sob `LANG=C.UTF-8`.
  _qa_localidade_utf8_existe || pular 'localidade C.UTF-8 ausente nesta maquina'
  local programa saida
  programa='
    . "$1/lib/errors.sh"; . "$1/lib/progress.sh"; . "$1/lib/json.sh"; . "$1/lib/sync.sh"
    nome=$2
    lc_antes=${LC_ALL-AUSENTE}
    medida_antes=${#nome}
    dbx_json_escapar_cadeia "$nome"; json_antes=$DBX_JSON_ESCAPADO
    _dbx_sync_chave "$nome"
    dbx_sync_localidade_disponivel; disponivel=$?
    medida_depois=${#nome}
    fatia=${nome:0:1}
    dbx_json_escapar_cadeia "$nome"
    printf "%s|%s|%s|%s|%s|%s|%s" "$lc_antes" "${LC_ALL-AUSENTE}" "$medida_antes" "$medida_depois" \
      "${#fatia}" "$disponivel" "$([[ $json_antes == "$DBX_JSON_ESCAPADO" ]] && echo json_igual)"'
  saida=$(env -i LC_ALL=C bash -c "$programa" _ "$DBX_HARNESS_RAIZ" "${QA_E_MAIUSCULO}${QA_E_MINUSCULO}.t")
  assert_igual 'C|C|6|6|1|0|json_igual' "$saida" 'sob LC_ALL=C: LC_ALL intacto, bytes antes e depois'
  saida=$(env -i LANG=C.UTF-8 bash -c "$programa" _ "$DBX_HARNESS_RAIZ" "${QA_E_MAIUSCULO}${QA_E_MINUSCULO}.t")
  assert_igual 'AUSENTE|AUSENTE|4|4|1|0|json_igual' "$saida" \
    'sob LANG=C.UTF-8: LC_ALL segue ausente, caracteres antes e depois'
}

teste_qa_p4_localidade_valor_fora_do_alfabeto_cai_no_padrao_e_c_puro_avisa() {
  # Recomendacao do parecer TDD: `DBX_SYNC_LOCALIDADE` fora do alfabeto vale o
  # padrao (sem aviso, `É`/`é` um caminho); um nome valido que nao converte
  # (`C`, que existe mas e so ASCII) avisa uma vez.
  _qa_localidade_utf8_existe || pular 'localidade C.UTF-8 ausente nesta maquina'
  local valor nome_local="${QA_E_MAIUSCULO}.txt" nome_remoto="${QA_E_MINUSCULO}.txt"
  _qa_cenario
  printf 'mesmo' >"$BASE/local/$nome_local"
  _qa_listagem "$(_qa_entrada "/r/$nome_remoto" "/r/$nome_remoto" "$(_qa_hash "$BASE/local/$nome_local")" 5)"
  for valor in 'C.UTF-8;x' '../C.UTF-8' 'C UTF-8' '$(id)' $'C.UTF-8\nx' ''; do
    _qa_rodar "DBX_SYNC_LOCALIDADE=$valor" LC_ALL=C -- --json --dry-run sync --push --source "$BASE/local" \
      --dest /r --mirror --yes
    assert_igual 0 "$ESTADO" "[$valor]: conclui; diagnostico: $ERRO"
    assert_nao_contem 'comparacao sem caixa' "$ERRO" "[$valor]: fora do alfabeto vale o padrao, sem aviso"
    assert_nao_contem 'aviso=' "$ERRO" "[$valor]: nenhum aviso de outra forma"
    assert_contem 'identicos=1' "$SAIDA" "[$valor]: e o par acentuado e um caminho"
  done
  _qa_rodar DBX_SYNC_LOCALIDADE=C -- --json --dry-run sync --push --source "$BASE/local" --dest /r --mirror --yes
  assert_igual 0 "$ESTADO" "[C]: o aviso nao recusa; diagnostico: $ERRO"
  assert_igual 1 "$(_harness_contar 'comparacao sem caixa' "$BASE/err")" '[C]: um aviso'
  assert_contem "apagar=$nome_remoto" "$SAIDA" '[C]: so ASCII, o par vira dois caminhos'
}

teste_qa_p4_localidade_ausente_aviso_unico_fora_do_stdout_sem_segredo() {
  # TC-CX-05, RF-54(f), RNF-03: muitos arquivos, execucao real, `--json` e
  # `--progresso` — o aviso sai uma vez, so em stderr, sem segredo; codigo e
  # stdout iguais aos da execucao com a localidade.
  local i com sem
  _qa_cenario
  for i in 1 2 3 4 5 6; do printf '%s' "$i" >"$BASE/local/a$i.txt"; done
  mkdir -p "$BASE/local/sub"
  printf 'z' >"$BASE/local/sub/Z.txt"
  _qa_fotografar
  _qa_rodar -- --json sync --push --source "$BASE/local" --dest /r --mirror --yes --progresso
  sem="$ESTADO|$SAIDA|$(cat "$BASE/chamadas")"
  _qa_restaurar
  _qa_rodar DBX_SYNC_LOCALIDADE=qa_QA.inexistente -- --json sync --push --source "$BASE/local" --dest /r \
    --mirror --yes --progresso
  com="$ESTADO|$SAIDA|$(cat "$BASE/chamadas")"
  assert_igual 0 "$ESTADO" "o aviso nao recusa; diagnostico: $ERRO"
  assert_igual 1 "$(_harness_contar 'comparacao sem caixa' "$BASE/err")" 'um aviso por execucao'
  assert_contem 'qa_QA.inexistente' "$ERRO" 'o aviso nomeia a localidade ausente'
  assert_igual "$sem" "$com" 'codigo, stdout e chamadas iguais aos da execucao sem aviso'
  assert_segredo_ausente "$QA_TOKEN" "$ERRO" 'o aviso nao leva o token'
  assert_segredo_ausente "$QA_SEGREDO" "$ERRO" 'nem o segredo do aplicativo'
  # O aviso vem depois da leitura das opcoes: uso invalido segue com o seu codigo.
  _qa_rodar DBX_SYNC_LOCALIDADE=qa_QA.inexistente -- sync --push --pull --source "$BASE/local" --dest /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$ESTADO" 'uso invalido continua uso invalido'
  # RF-54(g): os outros comandos nao avisam.
  _qa_rodar DBX_SYNC_LOCALIDADE=qa_QA.inexistente -- upload "$BASE/local/a1.txt" /r/a1.txt
  assert_nao_contem 'comparacao sem caixa' "$ERRO" 'upload nao avisa'
}

teste_qa_p4_localidade_nao_muda_bytes_enviados_a_rede() {
  # RF-54(e): cabecalhos e corpo do envio de um arquivo de nome multibyte saem
  # com os mesmos bytes sob `LC_ALL=C` e sob a execucao padrao — a fixacao
  # dentro da comparacao nao muda tamanho, limite nem escape.
  _qa_localidade_utf8_existe || pular 'localidade C.UTF-8 ausente nesta maquina'
  local nome="${QA_E_MAIUSCULO}${QA_E_MINUSCULO}ção.txt" c padrao
  _qa_cenario
  printf 'conteúdo multibyte ÉÉÉ' >"$BASE/local/$nome"
  _qa_fotografar
  _qa_rodar LC_ALL=C -- --json sync --push --source "$BASE/local" --dest /r --mirror --yes
  assert_igual 0 "$ESTADO" "LC_ALL=C: conclui; diagnostico: $ERRO"
  c="$SAIDA|$(cat "$BASE/opcoes")"
  _qa_restaurar
  _qa_rodar DBX_SYNC_LOCALIDADE=qa_QA.inexistente LC_ALL=C -- --json sync --push --source "$BASE/local" \
    --dest /r --mirror --yes
  padrao="$SAIDA|$(cat "$BASE/opcoes")"
  assert_igual "$c" "$padrao" 'com e sem a comparacao fora do ASCII, os mesmos bytes saem'
  assert_contem "\\\"path\\\":\\\"/r/$nome\\\"" "$c" 'o envio leva o nome multibyte intacto no cabecalho'
}

# ===========================================================================
# 4. DOCUMENTACAO — RNF-34 (TC-DOC-01)
# ===========================================================================

teste_qa_p4_doc_readme_lista_os_utilitarios_do_preflight_e_nao_tem_frase_revogada() {
  local linha readme preflight arquivo frase
  linha=$(grep -m1 'Utilit.rios da instala' "$DBX_HARNESS_RAIZ/README.md")
  readme=$(grep -oE '`[a-z0-9]+`' <<<"$linha" | tr -d '`' |
    grep -vxE 'sha256sum|shasum|openssl' | LC_ALL=C sort | tr '\n' ' ')
  preflight=$(bash -c '. "$1/lib/errors.sh"; . "$1/lib/preflight.sh"; printf "%s" "$DBX_PREFLIGHT_UTILITARIOS"' \
    _ "$DBX_HARNESS_RAIZ" | tr ' ' '\n' | grep -vx curl | LC_ALL=C sort | tr '\n' ' ')
  assert_diferente '' "$readme" 'o README tem a lista de utilitarios'
  assert_igual "$preflight" "$readme" 'README e preflight listam os mesmos utilitarios'
  assert_contem 'sha256sum' "$linha" 'a familia de resumo SHA-256 esta no README'
  assert_contem 'openssl' "$linha" 'inclusive o recuo para openssl, aceito pelo preflight'
  local conteudo achado r=$DBX_HARNESS_RAIZ auditados=0
  for arquivo in "$r/README.md" "$r"/lib/*.sh "$r"/commands/*.sh "$r/bin/dbx" "$r/install.sh"; do
    [[ -f $arquivo ]] || continue
    auditados=$((auditados + 1))
    IFS= read -r -d '' conteudo <"$arquivo"
    conteudo=${conteudo,,}
    for frase in 'estado local persistente' 'nao ha estado local' 'não há estado local' \
      'sem dependencias externas' 'sem dependências externas' 'exclusivamente com `bash`' \
      'sqlite3 ou' 'python3 ou' 'unica escrita persistente' 'única escrita persistente'; do
      achado=ausente
      [[ $conteudo == *"$frase"* ]] && achado=presente
      assert_igual ausente "$achado" "${arquivo#"$r"/} nao contem [$frase] (RNF-34)"
    done
  done
  assert_diferente 0 "$auditados" 'a auditoria de texto leu arquivos'
  assert_contem 'nao persiste' "$(head -40 "$DBX_HARNESS_RAIZ/lib/http.sh")" \
    'o cabecalho de lib/http diz o porque atual'
}

teste_qa_p4_doc_system_design_marca_a_decisao_revogada_na_propria_linha() {
  # RNF-34(f): a linha da tabela de decisoes "Ausencia deliberada de estado
  # local persistente (v0.3)" precisa trazer a marca de revogacao NELA, e nao
  # so na secao historica, porque a tabela e lida linha a linha.
  local linha
  linha=$(grep -m1 'Ausencia deliberada de estado local persistente' \
    "$DBX_HARNESS_RAIZ/docs/arquitetura/system-design.md")
  assert_diferente '' "$linha" 'a linha da decisao v0.3 existe na tabela'
  assert_igual 1 "$(grep -ciE 'revogad|historic|substituid|superad' <<<"$linha")" \
    'a propria linha marca a decisao como revogada'
}

harness_executar "$@"
