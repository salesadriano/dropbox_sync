#!/usr/bin/env bash
# Suite independente do QA Expert para a fase 9 (desempenho): F-09 (paralelismo no
# sync), RF-136 (exclusao em lote so no `sync --espelhar`; o `reter` segue item a
# item, DIV-269) e RF-137 (envio em lote de pequenos com conferencia de
# `content_hash`, DIV-278), mais RF-138 (bancada, sem rede, sem segredo nos logs).
# Executavel real `bin/dbx`, duplo de `curl` proprio (delegando as rotas de lote ao
# duplo compartilhado), sem rede real e sem conta real.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly QA_USO QA_NAO_CONCLUIDA
QA_AMBIENTE=()

# _qa_cenario — credencial, duplo de `curl` e arvore local. Controles por arquivo:
#   listagem  corpo do list_folder (padrao: vazio)
#   lote/*    ver tests/support/lote_duplo.sh
_qa_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-b9.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp" "$base/estado"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%q\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
printf '%s\n' "$conf" >>"$base/opcoes"
saida=''; ant=''; url=''; escrever=''; corpo_arquivo=''
for arg in "$@"; do
  case $ant in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  ant=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200; corpo=''
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.QAtokenB9","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
codigo_anterior=$codigo corpo_anterior=$corpo
lote_responder "$url" "$corpo_arquivo" || { codigo=$codigo_anterior; corpo=$corpo_anterior; }
if [[ -n $corpo_arquivo && -r $corpo_arquivo ]]; then
  { printf '%s\t' "$url"; cat "$corpo_arquivo"; printf '\n'; } >>"$base/corpos"
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_qa_rodar() { # <base> <argumentos...> — ambiente extra em QA_AMBIENTE
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${QA_AMBIENTE[@]+"${QA_AMBIENTE[@]}"} \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_n() { # <padrao> <base> — chamadas de rede cuja URL casa o padrao (0 se nao ha arquivo)
  [[ -r $2/chamadas ]] || { printf '0'; return 0; }
  _harness_contar "$1" "$2/chamadas"
}

_qa_entrada() { # <caminho> <hash> <tamanho> [rev]
  printf '{".tag":"file","path_display":"%s","path_lower":"%s","content_hash":"%s","size":%s,"rev":"%s"}' \
    "$1" "${1,,}" "$2" "$3" "${4:-0a1b2c3d4}"
}

_qa_hash_n() { printf '%064d' "$1"; }

_qa_norm() { # <base> <texto> — tira o diretorio do cenario do texto
  printf '%s' "${2//$1/BASE}"
}

_qa_memoria() { # <base> — o cache (memoria): "<hash> <nome>" por registro, ordenado.
  # A identidade (ctime, inode) varia por cenario e fica de fora; o hash fica.
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

_qa_publicado() { # <base> — resumo do conteudo publicado pelo lote (caminho + sha)
  [[ -d $1/enviado ]] || return 0
  (cd "$1/enviado" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(sha256sum <"$f" | cut -c1-64)"
  done)
}

_qa_remotos() { # <base> <n> [prefixo] — n arquivos so no remoto, com rev
  local i lista=''
  for ((i = 1; i <= $2; i++)); do
    lista+="${lista:+,}$(_qa_entrada "/r/${3:-so}$i.txt" "$(_qa_hash_n "$i")" 5 "rev$i")"
  done
  printf '{"entries":[%s],"has_more":false}' "$lista" >"$1/listagem"
}

_qa_locais() { # <base> <n> — n pequenos, um deles em subpasta e outro com espaco
  local i
  mkdir -p "$1/local/sub dir"
  for ((i = 1; i <= $2; i++)); do printf 'conteudo %s' "$i" >"$1/local/f$i.txt"; done
  printf 'com espaco' >"$1/local/sub dir/a b.txt"
  # Identidade registravel pelo cache (anti-corrida: mtime com mais de 2 s).
  find "$1/local" -type f -exec touch -d '2020-01-01 00:00:00 UTC' {} +
}

_qa_espelho() { # <base> [extras...] — sync --enviar --espelhar com 1 local
  local base=$1
  shift
  printf 'x' >"$base/local/fica.txt"
  _qa_rodar "$base" "$@" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
}

# ---------------------------------------------------------------------------
# F-09 / RF-133 / RF-134 — equivalencia N=1 contra N>1
# ---------------------------------------------------------------------------

teste_qdb01_envio_de_pequenos_e_equivalente_com_n_1_2_4_e_8() {
  local base n ref_out ref_err ref_mem ref_pub ref_est out err
  for n in 1 2 4 8; do
    base=$(_qa_cenario)
    _qa_locais "$base" 12
    _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo "$n"
    out=$(_qa_norm "$base" "$DBX_SAIDA")
    err=$(_qa_norm "$base" "$DBX_ERRO")
    assert_igual 0 "$DBX_ESTADO" "N=$n conclui; diagnostico: $DBX_ERRO"
    assert_contem 'enviados=13' "$DBX_SAIDA" "N=$n envia os 13 arquivos"
    assert_igual 13 "$(_qa_n 'upload_session/start' "$base")" "N=$n: um start por arquivo"
    assert_igual 0 "$(_qa_n 'files/upload$' "$base")" "N=$n: nenhum files/upload unitario"
    if [[ $n == 1 ]]; then
      ref_out=$out ref_err=$err ref_est=$DBX_ESTADO
      ref_mem=$(_qa_memoria "$base") ref_pub=$(_qa_publicado "$base")
      assert_diferente '' "$ref_mem" 'o cache de referencia nao e vazio'
      assert_contem 'f1.txt' "$ref_mem" 'f1 registrado no cache'
      assert_diferente '' "$ref_pub" 'a publicacao de referencia nao e vazia'
    else
      assert_igual "$ref_est" "$DBX_ESTADO" "N=$n: mesmo codigo de saida"
      assert_igual "$ref_out" "$out" "N=$n: mesma saida padrao, na ordem do plano"
      assert_igual "$ref_err" "$err" "N=$n: mesmo erro padrao"
      assert_igual "$ref_mem" "$(_qa_memoria "$base")" "N=$n: mesmo cache byte a byte (ordenado)"
      assert_igual "$ref_pub" "$(_qa_publicado "$base")" "N=$n: mesmos arquivos e bytes publicados"
    fi
  done
}

teste_qdb02_falha_por_item_e_igual_em_n_1_e_n_4_e_nao_entra_no_cache() {
  local base n ref_out ref_err ref_mem ref_est
  for n in 1 4; do
    base=$(_qa_cenario)
    _qa_locais "$base" 10
    mkdir -p "$base/lote/envio_falha"
    : >"$base/lote/envio_falha/f3.txt"
    : >"$base/lote/envio_falha/f7.txt"
    printf 'conteudo 5' >"$base/lote/start_falha_marca"
    _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo "$n"
    assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" "N=$n: falha de item e nao concluida"
    assert_contem 'enviados=8' "$DBX_SAIDA" "N=$n: os demais 8 seguem"
    assert_contem 'falhas=3' "$DBX_SAIDA" "N=$n: tres itens falhos"
    assert_igual 1 "$(grep -c 'f3.txt' <<<"$DBX_ERRO")" "N=$n: f3 aparece uma vez no erro"
    assert_igual 1 "$(grep -c 'f5.txt' <<<"$DBX_ERRO")" "N=$n: f5 (start recusado) aparece uma vez"
    if [[ $n == 1 ]]; then
      ref_out=$(_qa_norm "$base" "$DBX_SAIDA") ref_err=$(_qa_norm "$base" "$DBX_ERRO")
      ref_mem=$(_qa_memoria "$base") ref_est=$DBX_ESTADO
    else
      assert_igual "$ref_est" "$DBX_ESTADO" 'mesmo codigo com N=4'
      assert_igual "$ref_out" "$(_qa_norm "$base" "$DBX_SAIDA")" 'mesma saida com N=4'
      assert_igual "$ref_err" "$(_qa_norm "$base" "$DBX_ERRO")" 'mesmo erro com N=4, mesma ordem'
      assert_igual "$ref_mem" "$(_qa_memoria "$base")" 'mesmo cache com N=4'
    fi
  done
}

teste_qdb03_paralelo_invalido_sai_2_antes_da_rede_e_a_opcao_vence_o_ambiente() {
  local base v
  for v in 0 9 -1 '' abc 08 +2 ' 2' 1.5 100; do
    base=$(_qa_cenario)
    printf 'x' >"$base/local/a.txt"
    QA_AMBIENTE=()
    _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo "$v"
    assert_igual "$QA_USO" "$DBX_ESTADO" "opcao '$v' recusada com 2"
    assert_igual 0 "$(_qa_n . "$base")" "opcao '$v': nenhuma chamada de rede"
    assert_igual 0 "$(find "$base/estado" -type f | wc -l | tr -d ' ')" "opcao '$v': nada gravado em estado"
  done
  base=$(_qa_cenario)
  printf 'x' >"$base/local/a.txt"
  QA_AMBIENTE=(DBX_PARALELO=99)
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$QA_USO" "$DBX_ESTADO" 'variavel invalida sozinha: 2'
  assert_contem 'DBX_PARALELO' "$DBX_ERRO" 'o erro nomeia a origem (ambiente)'
  assert_igual 0 "$(_qa_n . "$base")" 'variavel invalida: nenhuma chamada de rede'
  base=$(_qa_cenario)
  printf 'x' >"$base/local/a.txt"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo 2
  QA_AMBIENTE=()
  assert_igual 0 "$DBX_ESTADO" 'a opcao valida vence a variavel invalida'
  base=$(_qa_cenario)
  QA_AMBIENTE=(DBX_PARALELO=4)
  _qa_rodar "$base" --paralelo 2 espaco
  QA_AMBIENTE=()
  assert_igual "$QA_USO" "$DBX_ESTADO" '--paralelo fora do sync e recusada com 2'
}

teste_qdb04_dry_run_com_paralelo_nao_usa_rede_de_escrita() {
  local base ruim
  base=$(_qa_cenario)
  _qa_locais "$base" 6
  _qa_remotos "$base" 3
  _qa_rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --paralelo 4 --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" 'dry-run conclui'
  ruim=$(_qa_n 'upload|delete|finish_batch|upload_session' "$base")
  assert_igual 0 "$ruim" 'dry-run: nenhuma chamada de escrita (upload, start, finish, delete)'
  assert_igual 0 "$([[ -d $base/lote ]] && find "$base/lote" -name chamadas | wc -l | tr -d ' ' || printf 0)" 'dry-run: nenhuma rota de lote'
  assert_igual 0 "$(find "$base/estado" -name 'memoria-*' | wc -l | tr -d ' ')" 'dry-run: cache nao gravado'
}

# ---------------------------------------------------------------------------
# RF-136 — exclusao em lote no `sync --espelhar`
# ---------------------------------------------------------------------------

teste_qdb05_espelhar_exclui_em_um_lote_com_parent_rev_e_sem_delete_v2() {
  local base corpo
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  _qa_espelho "$base"
  assert_igual 0 "$DBX_ESTADO" "espelho conclui; diagnostico: $DBX_ERRO"
  assert_contem 'apagados=3' "$DBX_SAIDA" 'tres confirmados pelo check'
  assert_igual 1 "$(_qa_n 'files/delete_batch$' "$base")" 'um unico delete_batch'
  assert_igual 1 "$(_qa_n 'delete_batch/check' "$base")" 'uma conferencia'
  assert_igual 0 "$(_qa_n 'files/delete_v2' "$base")" 'nenhum delete_v2 em loop'
  corpo=$(grep -F $'delete_batch\t' "$base/lote/chamadas")
  assert_contem '"/r/so1.txt"' "$corpo" 'caminho 1 no lote'
  assert_contem '"/r/so3.txt"' "$corpo" 'caminho 3 no lote'
  assert_contem 'rev1' "$corpo" 'o rev listado viaja (parent_rev) para o item 1'
  assert_contem 'rev3' "$corpo" 'o rev listado viaja (parent_rev) para o item 3'
  assert_contem 'parent_rev' "$corpo" 'campo parent_rev presente'
  assert_nao_contem 'fica.txt' "$corpo" 'o arquivo que existe na origem nunca entra no lote'
}

teste_qdb06_guardas_agem_antes_de_montar_o_lote() {
  local base
  # (i) sem --confirmar na primeira execucao do espelho
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  printf 'x' >"$base/local/fica.txt"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_nao_contem 'apagados=3' "$DBX_SAIDA" 'sem --confirmar nada e apagado'
  assert_igual 0 "$(_qa_n 'delete' "$base")" "sem --confirmar: nenhuma exclusao (estado $DBX_ESTADO)"
  # (ii) origem vazia sem permissao explicita
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_diferente 0 "$DBX_ESTADO" 'origem vazia sem permissao: nao conclui com 0'
  assert_igual 0 "$(_qa_n 'delete' "$base")" 'origem vazia: nenhuma exclusao'
  # (iii) dry-run
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  _qa_espelho "$base" --dry-run
  assert_igual 0 "$(_qa_n 'delete' "$base")" 'dry-run: nenhuma exclusao'
  # (iv) filtro --excluir protege o que casa
  base=$(_qa_cenario)
  printf '{"entries":[%s,%s],"has_more":false}' "$(_qa_entrada /r/a.log "$(_qa_hash_n 1)" 5 ra)" \
    "$(_qa_entrada /r/b.txt "$(_qa_hash_n 2)" 5 rb)" >"$base/listagem"
  printf 'x' >"$base/local/fica.txt"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "filtro + espelho conclui; $DBX_ERRO"
  assert_nao_contem 'a.log' "$(grep -F $'delete_batch\t' "$base/lote/chamadas")" 'o excluido pelo filtro nunca entra no lote'
  assert_contem 'b.txt' "$(grep -F $'delete_batch\t' "$base/lote/chamadas")" 'o nao filtrado entra'
  # (v) nada a apagar: nenhuma rota de lote
  base=$(_qa_cenario)
  printf 'x' >"$base/local/fica.txt"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_qa_n 'delete' "$base")" 'sem excedente remoto: nenhuma chamada de exclusao'
}

teste_qdb07_item_nao_confirmado_nunca_conta_como_apagado() {
  local base
  # entrada com falha por item
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  mkdir -p "$base/lote/excluir_falha"
  printf 'outro' >"$base/lote/excluir_falha/so2.txt"
  _qa_espelho "$base"
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'entrada com erro: falha de item'
  assert_contem 'apagados=2' "$DBX_SAIDA" 'so as 2 confirmadas contam'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'a nao confirmada e falha'
  assert_contem 'so2.txt' "$DBX_ERRO" 'a falha nomeia o item'
  # check devolve failed: fatia inteira falha, sem repetir a exclusao
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  mkdir -p "$base/lote"
  printf 'failed\n' >"$base/lote/fila_check"
  _qa_espelho "$base"
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'check failed: nao concluida'
  assert_contem 'apagados=0' "$DBX_SAIDA" 'check failed: zero apagados'
  assert_contem 'falhas=3' "$DBX_SAIDA" 'check failed: fatia inteira falha'
  assert_igual 1 "$(_qa_n 'files/delete_batch$' "$base")" 'check failed: o lote nao e relancado'
  # lote recusado
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  mkdir -p "$base/lote"
  printf '400' >"$base/lote/lancar_codigo"
  _qa_espelho "$base"
  assert_diferente 0 "$DBX_ESTADO" 'delete_batch recusado: nao conclui com 0'
  assert_contem 'apagados=0' "$DBX_SAIDA" 'delete_batch recusado: zero apagados'
  # check devolve menos entradas que o enviado: o que falta e falha
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  mkdir -p "$base/lote"
  printf '1' >"$base/lote/entradas_max"
  _qa_espelho "$base"
  assert_contem 'apagados=1' "$DBX_SAIDA" 'entradas ausentes no check nao contam como apagadas'
  assert_contem 'falhas=2' "$DBX_SAIDA" 'entradas ausentes viram falha de item'
  # in_progress e reconsultado ate completar
  base=$(_qa_cenario)
  _qa_remotos "$base" 3
  mkdir -p "$base/lote"
  printf 'in_progress\ncomplete\n' >"$base/lote/fila_check"
  _qa_espelho "$base"
  assert_igual 0 "$DBX_ESTADO" "in_progress e depois complete conclui; $DBX_ERRO"
  assert_contem 'apagados=3' "$DBX_SAIDA" 'apos in_progress, os 3 confirmados'
  assert_igual 2 "$(_qa_n 'delete_batch/check' "$base")" 'duas consultas'
  assert_igual 1 "$(_qa_n 'files/delete_batch$' "$base")" 'um unico lancamento'
}

teste_qdb08_lote_de_exclusao_vai_em_fatias_de_250() {
  local base linhas n1 n2
  base=$(_qa_cenario)
  _qa_remotos "$base" 251
  _qa_espelho "$base"
  assert_igual 0 "$DBX_ESTADO" "251 exclusoes concluem; $DBX_ERRO"
  assert_contem 'apagados=251' "$DBX_SAIDA" 'todos confirmados'
  assert_igual 2 "$(_qa_n 'files/delete_batch$' "$base")" 'duas fatias'
  linhas=$(grep -F $'delete_batch\t' "$base/lote/chamadas")
  n1=$(sed -n 1p <<<"$linhas" | grep -o '"path"' | wc -l | tr -d ' ')
  n2=$(sed -n 2p <<<"$linhas" | grep -o '"path"' | wc -l | tr -d ' ')
  assert_igual 250 "$n1" 'primeira fatia com 250'
  assert_igual 1 "$n2" 'segunda fatia com 1'
}

# ---------------------------------------------------------------------------
# DIV-269 — o `reter` continua item a item
# ---------------------------------------------------------------------------

teste_qdb09_reter_nunca_usa_rota_de_lote_e_o_sync_nao_tem_delete_v2() {
  local base i lista=''
  local sem_comentario="$DBX_TESTES_TMP/qdb09-sync.$$"
  assert_igual 0 "$(_harness_contar 'delete_batch\|lote' "$DBX_HARNESS_RAIZ/commands/reter.sh")" 'reter.sh nao referencia lote'
  grep -v '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/sync.sh" >"$sem_comentario"
  assert_igual 0 "$(_harness_contar 'delete_v2\|dbx_transfer_excluir\|files/delete\b' "$sem_comentario")" 'sync.sh nao tem delete_v2 por item (fora de comentario)'
  rm -f "$sem_comentario"
  base=$(_qa_cenario)
  for i in 1 2 3; do
    lista+="${lista:+,}{\".tag\":\"file\",\"id\":\"id:b$i\",\"name\":\"b$i.tar\",\"path_display\":\"/bk/b$i.tar\",\"path_lower\":\"/bk/b$i.tar\",\"size\":1,\"rev\":\"0a1b2c3d$i\",\"server_modified\":\"2026-01-0${i}T00:00:00Z\",\"content_hash\":\"$(_qa_hash_n "$i")\"}"
  done
  printf '{"entries":[%s],"has_more":false}' "$lista" >"$base/listagem"
  _qa_rodar "$base" reter /bk --padrao 'b*.tar' --manter 1 --confirmar
  assert_diferente 0 "$(_qa_n 'files/delete_v2' "$base")" 'reter: a exclusao segue por delete_v2, item a item'
  assert_igual 0 "$(_qa_n 'delete_batch' "$base")" 'reter: nenhuma chamada delete_batch'
  assert_igual 0 "$(_qa_n 'upload_session' "$base")" 'reter: nenhuma rota de sessao'
  assert_igual 0 "$([[ -d $base/lote ]] && find "$base/lote" -name chamadas | wc -l | tr -d ' ' || printf 0)" 'reter: o duplo de lote nunca foi acionado'
}

# ---------------------------------------------------------------------------
# RF-137 / DIV-278 — envio em lote de pequenos com conferencia de integridade
# ---------------------------------------------------------------------------

teste_qdb10_hash_divergente_no_lote_falha_so_o_item_com_integridade() {
  local base codigo_int bom
  codigo_int=$(dbx_errors_codigo_saida integridade)
  base=$(_qa_cenario)
  printf 'conteudo 1' >"$base/local/f1.txt"
  printf 'conteudo 2' >"$base/local/f2.txt"
  printf 'conteudo 3' >"$base/local/f3.txt"
  bom=$(dbx_hash_conteudo_arquivo "$base/local/f1.txt")
  mkdir -p "$base/lote/envio_hash"
  printf '%s' "$bom" >"$base/lote/envio_hash/f1.txt"
  printf '%064d' 0 >"$base/lote/envio_hash/f2.txt"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'falha de item (RF-29): o processo sai nao concluida'
  assert_contem 'falha f2.txt: integridade' "$DBX_ERRO" "a classe do item e integridade ($codigo_int)"
  assert_contem 'enviados=2' "$DBX_SAIDA" 'so f1 e f3 contam'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'so f2 falha'
  assert_contem 'f2.txt' "$DBX_ERRO" 'a falha nomeia f2'
  assert_nao_contem 'f1.txt' "$DBX_ERRO" 'f1 (hash igual) nao falha'
  assert_nao_contem 'f3.txt' "$DBX_ERRO" 'f3 (sem hash devolvido) nao falha'
}

teste_qdb11_start_leva_o_content_hash_local() {
  local base h1 h2
  base=$(_qa_cenario)
  printf 'conteudo 1' >"$base/local/f1.txt"
  printf 'conteudo 2' >"$base/local/f2.txt"
  h1=$(dbx_hash_conteudo_arquivo "$base/local/f1.txt")
  h2=$(dbx_hash_conteudo_arquivo "$base/local/f2.txt")
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "envio conclui; $DBX_ERRO"
  assert_contem "$h1" "$(grep 'Dropbox-API-Arg' "$base/opcoes")" 'o start de f1 leva o content_hash local'
  assert_contem "$h2" "$(grep 'Dropbox-API-Arg' "$base/opcoes")" 'o start de f2 leva o content_hash local'
}

teste_qdb12_falha_do_finish_inteiro_nao_grava_cache_e_start_recusado_falha_so_o_item() {
  local base
  base=$(_qa_cenario)
  _qa_locais "$base" 4
  mkdir -p "$base/lote"
  printf '400' >"$base/lote/finish_codigo"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'finish recusado: nao conclui com 0'
  assert_contem 'enviados=0' "$DBX_SAIDA" 'finish recusado: nenhum enviado'
  base=$(_qa_cenario)
  _qa_locais "$base" 4
  mkdir -p "$base/lote"
  printf 'conteudo 2' >"$base/lote/start_falha_marca"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_contem 'enviados=4' "$DBX_SAIDA" 'start recusado de um: os outros 4 seguem'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'start recusado de um: uma falha'
}

teste_qdb13_identico_nunca_entra_no_lote_e_acima_do_limiar_segue_o_caminho_unitario() {
  local base h
  base=$(_qa_cenario)
  printf 'conteudo 1' >"$base/local/f1.txt"
  printf 'conteudo 2' >"$base/local/f2.txt"
  printf 'conteudo 3' >"$base/local/f3.txt"
  h=$(dbx_hash_conteudo_arquivo "$base/local/f1.txt")
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada /r/f1.txt "$h" 10 rv)" >"$base/listagem"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_contem 'identicos=1' "$DBX_SAIDA" 'f1 ja igual'
  assert_igual 2 "$(_qa_n 'upload_session/start' "$base")" 'so os 2 diferentes viram start'
  assert_nao_contem '/r/f1.txt' "$(grep -F $'finish_batch\t' "$base/lote/chamadas")" 'o identico nao entra no finish'
  base=$(_qa_cenario)
  head -c 2097152 </dev/zero >"$base/local/g1.bin"
  head -c 2097152 </dev/zero | tr '\0' 'x' >"$base/local/g2.bin"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_igual 0 "$(_qa_n 'finish_batch' "$base")" 'acima de 1 MiB: fora do lote'
  assert_igual 2 "$(_qa_n 'files/upload$' "$base")" 'acima de 1 MiB: files/upload unitario'
}

# ---------------------------------------------------------------------------
# RF-138 — nenhum segredo nos logs da bancada (sem rede)
# ---------------------------------------------------------------------------

_qa_bancada() { # roda `medir` com dbx e curl falsos; imprime o diretorio dos logs
  local tmp
  tmp=$(mktemp -d "$DBX_TESTES_TMP/qa-bancada.XXXXXX")
  mkdir -p "$tmp/bin"
  cat >"$tmp/dbx" <<DUBLE
#!/usr/bin/env bash
case "\$1" in
  list) exit 4 ;;
  delete | upload) exit 0 ;;
esac
printf 'linha1 sl.SEGREDOQAABCDEFGHIJ e Bearer SEGREDOBEARERQA\n'
printf 'resposta {"access_token":"sl.SEGREDOJSONABCDEFGH","expires_in":14400}\n'
printf 'Authorization: Basic U0VHUkVET0JBU0lDUUE=\n' >&2
printf 'refresh_token=SEGREDOREFRESHQA app_secret=SEGREDOAPPQA\n' >&2
exit 0
DUBLE
  printf '#!/usr/bin/env bash\nprintf 200\n' >"$tmp/bin/curl"
  chmod +x "$tmp/dbx" "$tmp/bin/curl"
  BANCADA_PEQUENOS=3 BANCADA_MEDIOS=1 BANCADA_GRANDES=1 BANCADA_GRANDE_MB=1 \
    bash "$DBX_HARNESS_RAIZ/scripts/bancada.sh" gerar "$tmp/v" >/dev/null 2>&1
  PATH="$tmp/bin:$PATH" DBX_BIN="$tmp/dbx" bash "$DBX_HARNESS_RAIZ/scripts/bancada.sh" medir "$tmp/v" \
    --remoto /dbx-bancada-qa --saida "$tmp/s.tsv" --confirmo-conta-real >"$tmp/stdout" 2>"$tmp/stderr"
  printf '%s' "$tmp"
}

teste_qdb14_bancada_nao_deixa_segredo_de_formato_conhecido_nos_logs() {
  local tmp f todo=''
  tmp=$(_qa_bancada)
  for f in "$tmp"/s.tsv*; do todo+=$(<"$f")$'\n'; done
  todo+=$(<"$tmp/stdout")$'\n'$(<"$tmp/stderr")
  assert_contem 'linha1' "$todo" 'os logs existem e trazem a saida das etapas'
  assert_nao_contem 'SEGREDOQAABCDEFGHIJ' "$todo" 'token sl. redigido'
  assert_nao_contem 'SEGREDOBEARERQA' "$todo" 'Bearer redigido'
  assert_nao_contem 'SEGREDOJSONABCDEFGH' "$todo" 'access_token em JSON redigido'
}

teste_qdb15_bancada_redige_basic_e_chaves_de_credencial() {
  # ACHADO QA-B9-01 (Menor), corrigido na fase 9 por decisao do solicitante (2026-10-22):
  # `Authorization: Basic <b64>` e `refresh_token=`/`app_secret=` sem prefixo tambem saem
  # redigidos dos logs da bancada (RNF-03). Antes da correcao este caso caracterizava a lacuna.
  local tmp todo=''
  tmp=$(_qa_bancada)
  for f in "$tmp"/s.tsv*; do todo+=$(<"$f")$'\n'; done
  assert_nao_contem 'U0VHUkVET0JBU0lDUUE=' "$todo" 'o segmento Basic em base64 nao sobrevive ao log'
  assert_nao_contem 'SEGREDOREFRESHQA' "$todo" 'refresh_token sem prefixo nao sobrevive ao log'
  assert_nao_contem 'SEGREDOAPPQA' "$todo" 'app_secret sem prefixo nao sobrevive ao log'
  assert_contem '[REDIGIDO]' "$todo" 'a redacao deixa marca no log'
}

harness_executar "$@"
