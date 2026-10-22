#!/usr/bin/env bash
# Testes das operacoes em lote da fase 9 (F-08; RF-136, RF-137; TC-LOT-*, TC-LOU-*):
# exclusao em lote no `sync --espelhar` (o `reter` fica item a item, DIV-269) e
# envio em lote de pequenos no `sync --enviar`.
#
# O duplo de `curl` delega as rotas de lote a `tests/support/lote_duplo.sh` (ver o
# cabecalho dele para os controles). `sleep` e duble que so registra a espera em
# `$base/dormiu`, para provar o recuo (1 s dobrando ate 10 s, teto 120 s) sem esperar.
#
# shellcheck disable=SC2016
# Justificativa: o duplo precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly NAO_CONCLUIDA=14

_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/lote.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp" "$base/enviado" "$base/lote" "$base/lote/excluir_falha" "$base/lote/envio_falha" "$base/lote/envio_hash"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  {
    printf '#!%s\nbase=%q\nDBX_HARNESS_RAIZ=%q\n' "$BASH" "$base" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url='' corpo_arquivo=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
if [[ -r "$base/sinal" && $url == *"$(cat "$base/sinal_url")"* ]]; then kill -s "$(cat "$base/sinal")" 0; fi
codigo=200
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
if [[ $url == *upload_session/start* ]]; then printf '%s\n' "$conf" >>"$base/lote/confs"; fi
if lote_responder "$url" "$corpo_arquivo"; then
  :
else
  case $url in
    *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
    *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
    *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
    *list_folder*) corpo=$(<"$base/listagem") ;;
    *files/upload)
      re='path\\":\\"([^\\"]*)\\"'
      [[ $conf =~ $re ]] && destino=${BASH_REMATCH[1]}
      mkdir -p "$base/enviado${destino%/*}"
      cp "$corpo_arquivo" "$base/enviado$destino" 2>/dev/null
      corpo='{"name":"x","rev":"1"}'
      # lou09: o envio unitario recusa o que o lote recusa (mesma classe e resumo).
      if [[ -f $base/lote/envio_falha/${destino##*/} ]]; then
        rm -f "$base/enviado$destino"
        codigo=409
        corpo='{"error_summary":"path/conflict/file/.."}'
      fi
      ;;
    *delete_v2*)
      # ecoa o alvo (o `reter` confere o item, RF-97)
      alvo=''
      [[ -r $corpo_arquivo ]] && re='"path":"([^"]*)"' && [[ $(<"$corpo_arquivo") =~ $re ]] && alvo=${BASH_REMATCH[1]}
      corpo="{\"metadata\":{\".tag\":\"file\",\"name\":\"x\",\"path_lower\":\"$alvo\",\"rev\":\"0123456789\"}}"
      printf 'DELETE_V2\n' >>"$base/chamadas"
      ;;
    *) corpo='{"name":"x","rev":"1"}' ;;
  esac
fi
if [[ -n $saida ]]; then printf '%s' "$corpo" >"$saida" 2>/dev/null || exit 23; fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  # Espera fracionaria (o atraso do `start` do lou07 e a vigia dos auxiliares) e
  # real e nao entra no registro; so o recuo inteiro do `check` e simulado.
  printf '#!%s\ncase $1 in *.*) exec %q "$1" ;; esac\nprintf "%%s\\n" "$1" >>%q\n' \
    "$BASH" "$(command -v sleep)" "$base/dormiu" >"$base/bin/sleep"
  chmod +x "$base/bin/sleep"
  printf '%s' "$base"
}

# _remoto <base> <nome>... — arquivos remotos em /r (sem equivalente local)
_remoto() {
  local base=$1 nome lista='' rev=${REV:-}
  shift
  for nome in "$@"; do
    lista+="${lista:+,}{\".tag\":\"file\",\"path_display\":\"/r/$nome\",\"size\":10${rev:+,\"rev\":\"$rev\"}}"
  done
  printf '{"entries":[%s],"has_more":false}' "$lista" >"$base/listagem"
}

_extras() { # <n> — n nomes x1.txt..xn.txt
  local i
  for ((i = 1; i <= $1; i++)); do printf 'x%s.txt ' "$i"; done
}

_local() { # <base> <nome>... — arquivos locais pequenos, com conteudo proprio
  local base=$1 nome
  shift
  for nome in "$@"; do
    [[ $nome == */* ]] && mkdir -p "$base/local/${nome%/*}"
    printf 'conteudo de %s' "$nome" >"$base/local/$nome"
    touch -d '2020-01-01 00:00:00' "$base/local/$nome"
  done
}

_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_AMBIENTE[@]+"${DBX_T_AMBIENTE[@]}"} \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_n() { # <base> <rota> — chamadas de lote da rota
  local n=0 l
  [[ -r $1/lote/chamadas ]] || { printf 0; return 0; }
  while IFS= read -r l; do [[ $l == "$2"$'\t'* ]] && n=$((n + 1)); done <"$1/lote/chamadas"
  printf '%s' "$n"
}

_entradas() { # <base> <rota> <k> — numero de "path" no corpo da k-esima chamada da rota
  local k=0 l tot
  while IFS= read -r l; do
    [[ $l == "$2"$'\t'* ]] || continue
    k=$((k + 1))
    if ((k == $3)); then
      tot=${l//[^p]/}
      l=${l//\"path\":/@}
      tot=${l//[^@]/}
      printf '%s' "${#tot}"
      return 0
    fi
  done <"$1/lote/chamadas"
  printf 0
}

_dormido() { # <base> — soma e sequencia das esperas
  local soma=0 s seq=''
  [[ -r $1/dormiu ]] || { printf '0|'; return 0; }
  while IFS= read -r s; do soma=$((soma + s)); seq+="${seq:+,}$s"; done <"$1/dormiu"
  printf '%s|%s' "$soma" "$seq"
}

_espelhar() { # <base> [args...] — envia /local para /r espelhando
  local base=$1
  shift
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r "$@"
}

# ---------------------------------------------------------------------------
# RF-136: exclusao em lote no sync --espelhar
# ---------------------------------------------------------------------------

teste_lot01_espelhar_apaga_em_um_lote_e_nunca_por_delete_v2() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 3)
  _espelhar "$base"
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 1 "$(_n "$base" delete_batch)" 'um unico delete_batch'
  assert_igual 3 "$(_entradas "$base" delete_batch 1)" 'com as tres exclusoes'
  assert_igual 1 "$(_n "$base" check)" 'um check'
  assert_nao_contem DELETE_V2 "$(<"$base/chamadas")" 'nenhum delete_v2'
  assert_contem 'apagados=3' "$DBX_SAIDA"
}

teste_lot02_fatias_de_250() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 600)
  _espelhar "$base"
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 3 "$(_n "$base" delete_batch)" 'tres fatias'
  assert_igual 250 "$(_entradas "$base" delete_batch 1)" 'fatia 1'
  assert_igual 250 "$(_entradas "$base" delete_batch 2)" 'fatia 2'
  assert_igual 100 "$(_entradas "$base" delete_batch 3)" 'fatia 3'
  assert_igual 3 "$(_n "$base" check)" 'um check por fatia'
  assert_contem 'apagados=600' "$DBX_SAIDA"
}

teste_lot03_item_com_erro_no_check_e_falha_do_item_e_so_dele() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 3)
  printf 'outro' >"$base/lote/excluir_falha/x2.txt"
  _espelhar "$base"
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'nao_concluida'
  assert_contem 'falha x2.txt:' "$DBX_ERRO" 'linha do item que falhou'
  assert_nao_contem 'falha x1.txt' "$DBX_ERRO" 'as outras nao falham'
  assert_contem 'apagados=2' "$DBX_SAIDA"
  assert_contem 'falhas=1' "$DBX_SAIDA"
  assert_igual 1 "$(_n "$base" delete_batch)" 'nenhuma nova exclusao'
}

teste_lot04_entrada_ausente_no_complete_e_falha_nunca_sucesso() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 3)
  printf '2' >"$base/lote/entradas_max"
  _espelhar "$base"
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'nao_concluida'
  assert_contem 'apagados=2' "$DBX_SAIDA" 'so as confirmadas contam'
  assert_contem 'falha x3.txt:' "$DBX_ERRO" 'a nao confirmada e falha'
}

teste_lot05_in_progress_recua_1_2_4_e_volta_a_consultar() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  _remoto "$base" fica.txt x1.txt
  printf 'in_progress\nin_progress\nin_progress\ncomplete\n' >"$base/lote/fila_check"
  _espelhar "$base"
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual '7|1,2,4' "$(_dormido "$base")" 'recuo 1 s dobrando'
  assert_igual 4 "$(_n "$base" check)" 'quatro consultas'
  assert_igual 1 "$(_n "$base" delete_batch)" 'sem repetir a exclusao'
}

teste_lot06_recuo_limitado_a_10s_e_teto_de_120s_e_falha_da_fatia_inteira() {
  local base soma
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 3)
  local i
  for ((i = 0; i < 40; i++)); do printf 'in_progress\n'; done >"$base/lote/fila_check"
  _espelhar "$base"
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'estouro do teto'
  soma=$(_dormido "$base")
  soma=${soma%%|*}
  [[ $soma -le 120 && $soma -ge 100 ]] || _harness_falhar "espera total fora de 100..120: $soma"
  assert_contem '1,2,4,8,10,10' "$(_dormido "$base")" 'recuo teto 10 s'
  assert_contem 'falhas=3' "$DBX_SAIDA" 'a fatia inteira falha'
  assert_contem 'apagados=0' "$DBX_SAIDA"
  assert_igual 1 "$(_n "$base" delete_batch)" 'sem nova exclusao'
}

teste_lot07_check_failed_e_falha_da_fatia_inteira_sem_repetir() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 3)
  printf 'failed\n' >"$base/lote/fila_check"
  _espelhar "$base"
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'nao_concluida'
  assert_contem 'falhas=3' "$DBX_SAIDA"
  assert_igual 1 "$(_n "$base" delete_batch)" 'delete_batch uma vez'
  assert_igual 1 "$(_n "$base" check)" 'um check'
}

teste_lot08_guardas_agem_antes_do_lote() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  # shellcheck disable=SC2046
  _remoto "$base" fica.txt $(_extras 3)
  # sem --confirmar na primeira execucao: reconhecimento recusa
  _rodar "$base" sync --enviar --espelhar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'sem reconhecimento'
  assert_igual 0 "$(_n "$base" delete_batch)" 'nenhum lote sem reconhecimento'
  # dry-run
  _espelhar "$base" --dry-run
  assert_igual 0 "$(_n "$base" delete_batch)" 'nenhum lote em --dry-run'
  # origem vazia
  rm -f "$base/local/fica.txt"
  _espelhar "$base"
  assert_diferente 0 "$DBX_ESTADO" 'origem vazia recusada'
  assert_igual 0 "$(_n "$base" delete_batch)" 'nenhum lote com origem vazia'
}

teste_lot09_filtrado_nunca_entra_no_lote() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  _remoto "$base" fica.txt a.log b.txt
  _espelhar "$base" --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 1 "$(_entradas "$base" delete_batch 1)" 'so o b.txt'
  assert_nao_contem 'a.log' "$(<"$base/lote/chamadas")" 'o filtrado nunca vai ao lote'
}

teste_lot09b_protegido_fora_do_escopo_nunca_entra_no_corpo_do_delete_batch() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  _remoto "$base" fica.txt a.log b.txt c.log
  _espelhar "$base" --incluir '*.txt'
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 1 "$(_entradas "$base" delete_batch 1)" 'so o b.txt, dentro do escopo'
  assert_contem '/r/b.txt' "$(<"$base/lote/chamadas")" 'o do escopo vai'
  assert_nao_contem '.log' "$(<"$base/lote/chamadas")" 'o protegido (RF-80(d)) nunca vai ao lote'
}

teste_lot10_parent_rev_quando_o_rev_e_conhecido() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  REV=abcdef0123456789 _remoto "$base" fica.txt x1.txt
  _espelhar "$base"
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_contem '"parent_rev":"abcdef0123456789"' "$(<"$base/lote/chamadas")" 'rev da listagem'
}

teste_lot11_sem_delete_v2_em_laco_no_espelhar() {
  if grep -v '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/sync.sh" | grep -q 'delete_v2'; then
    _harness_falhar 'commands/sync.sh ainda chama delete_v2'
  fi
  assert_igual 0 0 'estatico'
}

# ---------------------------------------------------------------------------
# RF-136(e), DIV-269: o reter NAO usa lote
# ---------------------------------------------------------------------------

_reter_listagem() { # <base> <n> — n artefatos a1..an, a1 o mais velho
  local base=$1 n=$2 i lista='' hora rev
  for ((i = 1; i <= n; i++)); do
    printf -v rev '%04x' "$i"
    printf -v hora '2026-01-01T00:%02d:%02dZ' $((i / 60)) $((i % 60))
    lista+="${lista:+,}{\".tag\":\"file\",\"name\":\"a$i.bak\",\"path_lower\":\"/b/a$i.bak\",\"path_display\":\"/b/a$i.bak\",\"id\":\"id:$i\",\"rev\":\"00000000${rev}aaaa\",\"server_modified\":\"$hora\",\"client_modified\":\"$hora\",\"size\":1,\"content_hash\":\"h$i\"}"
  done
  printf '{"entries":[%s],"has_more":false}' "$lista" >"$base/listagem"
}

teste_lot12_reter_segue_com_delete_v2_por_item_e_sem_delete_batch() {
  local base
  base=$(_cenario)
  _reter_listagem "$base" 5
  _rodar "$base" reter /b --padrao '*.bak' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 0 "$(_n "$base" delete_batch)" 'reter nao usa delete_batch'
  assert_igual 0 "$(_n "$base" check)" 'nem o check do lote'
  assert_igual 3 "$(_harness_contar '^DELETE_V2$' "$base/chamadas")" 'um delete_v2 por item'
  assert_contem 'apagados=3' "$DBX_SAIDA"
  assert_igual 3 "$(_harness_contar '^acao=apagado' "$base/out")" 'uma linha por item'
  if grep -v '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/reter.sh" | grep -q 'delete_batch\|dbx_lote_'; then
    _harness_falhar 'commands/reter.sh referencia o lote'
  fi
}

teste_lot14_reter_sem_confirmar_nao_chama_o_lote() {
  local base
  base=$(_cenario)
  _reter_listagem "$base" 4
  _rodar "$base" reter /b --padrao '*.bak' --manter 1
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 0 "$(_n "$base" delete_batch)" 'so o plano'
}

teste_lot15_reter_ignora_os_controles_do_lote_e_confirma_item_a_item() {
  local base
  base=$(_cenario)
  _reter_listagem "$base" 4
  printf '1' >"$base/lote/entradas_max"
  _rodar "$base" reter /b --padrao '*.bak' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_contem 'apagados=3' "$DBX_SAIDA" 'o limite do lote nao alcanca o reter'
  assert_igual 0 "$(_n "$base" delete_batch)" 'sem delete_batch'
  assert_igual 3 "$(_harness_contar '^DELETE_V2$' "$base/chamadas")" 'delete_v2 por item'
}

# ---------------------------------------------------------------------------
# RF-137: envio em lote de pequenos
# ---------------------------------------------------------------------------

teste_lou01_pequenos_vao_em_sessoes_e_um_finish_batch() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt d.txt e.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 5 "$(_n "$base" start)" 'um start por arquivo'
  assert_igual 1 "$(_n "$base" finish_batch)" 'um finish_batch'
  assert_igual 5 "$(_entradas "$base" finish_batch 1)" 'cinco entradas'
  assert_contem 'close\":true' "$(<"$base/lote/confs")" 'close=true em cada sessao (a configuracao do curl escapa as aspas)'
  assert_igual 5 "$(_harness_contar 'close\\":true' "$base/lote/confs")" 'close=true em TODAS as sessoes'
  assert_igual 0 "$(_harness_contar '/files/upload$' "$base/chamadas")" 'nenhum upload unitario (a rota termina em files/upload)'
  assert_igual 'conteudo de c.txt' "$(<"$base/enviado/r/c.txt")" 'conteudo publicado'
  assert_contem 'enviados=5' "$DBX_SAIDA"
}

teste_lou02_acima_do_limiar_segue_o_caminho_atual_e_a_fronteira_e_1_mib() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt
  head -c 1048576 /dev/zero >"$base/local/exato.bin"
  head -c 1048577 /dev/zero >"$base/local/acima.bin"
  touch -d '2020-01-01' "$base/local/exato.bin" "$base/local/acima.bin"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 3 "$(_entradas "$base" finish_batch 1)" 'a, b e o de exatamente 1 MiB'
  assert_igual 1 "$(_harness_contar '/files/upload$' "$base/chamadas")" 'o maior segue o upload unitario (as chamadas guardam so a URL)'
  [[ -f $base/enviado/r/acima.bin ]] || _harness_falhar 'acima do limiar nao foi enviado pelo caminho atual'
}

teste_lou03_falha_por_entrada_e_so_do_item() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt
  : >"$base/lote/envio_falha/b.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'nao_concluida'
  assert_contem 'falha b.txt: conflito' "$DBX_ERRO" 'mesma classe do upload unitario'
  assert_nao_contem 'falha a.txt' "$DBX_ERRO"
  assert_contem 'enviados=2' "$DBX_SAIDA"
  [[ -f $base/enviado/r/a.txt && -f $base/enviado/r/c.txt && ! -f $base/enviado/r/b.txt ]] ||
    _harness_falhar 'publicacao parcial incorreta'
}

teste_lou04_falha_do_lote_inteiro_falha_todos_e_nao_grava_retomada() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt
  printf '500' >"$base/lote/finish_codigo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'nao_concluida'
  assert_contem 'falhas=3' "$DBX_SAIDA"
  assert_contem 'enviados=0' "$DBX_SAIDA"
  if [[ -d $base/estado ]] && find "$base/estado" -name '*retomada*' | grep -q .; then
    _harness_falhar 'arquivo pequeno nao cria registro de retomada'
  fi
}

teste_lou05_grupos_de_ate_250_em_serie() {
  local base i
  base=$(_cenario)
  mkdir -p "$base/local"
  for ((i = 1; i <= 600; i++)); do printf 'c%s' "$i" >"$base/local/f$i.txt"; done
  touch -d '2020-01-01' "$base/local"/f*.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 3 "$(_n "$base" finish_batch)" 'tres grupos'
  assert_igual 250 "$(_entradas "$base" finish_batch 1)" 'grupo 1'
  assert_igual 100 "$(_entradas "$base" finish_batch 3)" 'grupo 3'
  assert_contem 'enviados=600' "$DBX_SAIDA"
}

teste_lou06_arquivo_ja_igual_nao_entra_no_lote() {
  local base hash
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt
  dbx_hash_publicar_arquivo "$base/local/b.txt"
  hash=$DBX_HASH_RESULTADO
  printf '{"entries":[{".tag":"file","path_display":"/r/b.txt","content_hash":"%s","size":17,"rev":"abcdef0123456789"}],"has_more":false}' \
    "$hash" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 2 "$(_entradas "$base" finish_batch 1)" 'so a e c'
  assert_contem 'omitidos=1' "$DBX_SAIDA"
}

teste_lou07_com_paralelo_os_starts_correm_juntos_e_o_finish_e_um_so_e_igual_a_n1() {
  local base um pico
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt d.txt e.txt f.txt
  printf '0.3' >"$base/lote/start_atraso"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "N=1; $DBX_ERRO"
  um=$(cd "$base/enviado" && find . -type f -exec sh -c 'for f; do printf "%s=" "$f"; cat "$f"; done' _ {} + | sort)
  pico=$(sort -n "$base/lote/pico" | tail -1)
  assert_igual 1 "$pico" 'N=1 sem simultaneidade'
  rm -rf "$base/enviado" "$base/lote/pico" "$base/lote/chamadas" "$base/estado"
  mkdir -p "$base/enviado"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo 4
  assert_igual 0 "$DBX_ESTADO" "N=4; $DBX_ERRO"
  assert_igual "$um" "$(cd "$base/enviado" && find . -type f -exec sh -c 'for f; do printf "%s=" "$f"; cat "$f"; done' _ {} + | sort)" 'mesmo resultado'
  pico=$(sort -n "$base/lote/pico" | tail -1)
  [[ $pico -gt 1 ]] || _harness_falhar "starts nao correram juntos: pico $pico"
  assert_igual 1 "$(_n "$base" finish_batch)" 'finish_batch so no processo principal, uma vez'
}

teste_lou08_dry_run_nao_chama_o_lote_e_um_unico_pequeno_segue_o_upload_unitario() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 0 "$(_n "$base" start)" 'dry-run sem start'
  rm -f "$base/local/b.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "saida; $DBX_ERRO"
  assert_igual 0 "$(_n "$base" finish_batch)" 'um pequeno so: caminho unitario'
  assert_igual 1 "$(_harness_contar '/files/upload$' "$base/chamadas")" 'o pequeno isolado vai por files/upload'
}

# RF-137(g): o resultado do lote e o do envio unitario, para N=1 e N=4: arquivos,
# codigo de saida, contagens e linha de falha por item. O baseline unitario e o
# `sync` de UM arquivo por vez (um pequeno isolado segue o caminho unitario,
# DIV-272); o falho e o mesmo nos dois (conflito).
_equivalencia_arvore() { # <base> — "caminho=conteudo" ordenado do publicado
  (cd "$1/enviado" 2>/dev/null && find . -type f -exec sh -c 'for f; do printf "%s=" "$f"; cat "$f"; printf "\n"; done' _ {} + | sort)
}

teste_lou09_resultado_do_lote_e_igual_ao_do_envio_unitario_para_n1_e_n4() {
  local base unitario_arvore unitario_estado unitario_falhas lote_falhas n f
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt d.txt
  : >"$base/lote/envio_falha/b.txt"
  # baseline unitario: um arquivo por execucao
  mkdir -p "$base/um"
  for f in a.txt b.txt c.txt d.txt; do
    rm -rf "$base/um" && mkdir -p "$base/um"
    cp -p "$base/local/$f" "$base/um/$f"
    _rodar "$base" sync --enviar --origem "$base/um" --destino /r
    [[ $f == b.txt ]] && unitario_estado=$DBX_ESTADO
    unitario_falhas+=$(grep '^falha ' "$base/err")
  done
  assert_igual 0 "$(_n "$base" finish_batch)" 'o baseline nao usa lote'
  assert_igual "$NAO_CONCLUIDA" "$unitario_estado" 'baseline: o conflito e nao_concluida'
  unitario_arvore=$(_equivalencia_arvore "$base")
  assert_contem 'falha b.txt: conflito' "$unitario_falhas" 'baseline: a linha do item'
  for n in 1 4; do
    rm -rf "$base/enviado" "$base/estado" "$base/lote/chamadas"
    mkdir -p "$base/enviado"
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo "$n"
    assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" "N=$n: mesmo codigo de saida"
    assert_igual 1 "$(_n "$base" finish_batch)" "N=$n: foi pelo lote"
    assert_igual "$unitario_arvore" "$(_equivalencia_arvore "$base")" "N=$n: mesmos arquivos publicados"
    lote_falhas=$(grep '^falha ' "$base/err")
    assert_igual "$unitario_falhas" "$lote_falhas" "N=$n: mesma linha de falha por item"
    assert_contem 'enviados=3' "$DBX_SAIDA" "N=$n: contagem"
    assert_contem 'falhas=1' "$DBX_SAIDA" "N=$n: contagem"
  done
}

# ---------------------------------------------------------------------------
# DIV-278: integridade do envio em lote igual a do envio unitario
# ---------------------------------------------------------------------------

_rodar_em_sessao() { # <base> <argumentos...> — o duplo pode sinalizar o grupo
  local base=$1
  shift
  DBX_ERRO=''
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_devolver_hash() { # <base> <nome>... — o duplo devolve o resumo correto de cada arquivo
  local base=$1 nome
  shift
  for nome in "$@"; do
    dbx_hash_publicar_arquivo "$base/local/$nome"
    printf '%s' "$DBX_HASH_RESULTADO" >"$base/lote/envio_hash/$nome"
  done
}

_unitario() { # <local> [<devolvido>] — o que o envio unitario por sessao decide
  ( . "$DBX_HARNESS_RAIZ/lib/transfer.sh"
    dbx_transfer_conferir_resumo "$@"
    printf '%s|%s|%s|%s' "$?" "$DBX_TRANSFER_CLASSE" "$DBX_TRANSFER_INTEGRIDADE" "$DBX_TRANSFER_MOTIVO" )
}

teste_lou10_hash_divergente_falha_so_a_entrada_com_integridade_igual_ao_unitario() {
  local base ruim unitario
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt
  _devolver_hash "$base" a.txt c.txt
  printf -v ruim 'f%.0s' {1..64}
  printf '%s' "$ruim" >"$base/lote/envio_hash/b.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 1 "$(_n "$base" finish_batch)" 'foi pelo lote'
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" "so o item falha; $DBX_ERRO"
  assert_contem 'falha b.txt: integridade ' "$DBX_ERRO" 'classe do item'
  assert_nao_contem 'falha a.txt' "$DBX_ERRO"
  assert_nao_contem 'falha c.txt' "$DBX_ERRO"
  assert_contem 'enviados=2' "$DBX_SAIDA"
  assert_contem 'falhas=1' "$DBX_SAIDA"
  # equivalencia com a decisao unitaria para o mesmo par de resumos
  dbx_hash_publicar_arquivo "$base/local/b.txt"
  unitario=$(_unitario "$DBX_HASH_RESULTADO" "$ruim")
  assert_igual "11|integridade|nao_aplicavel|o resumo devolvido pelo servico nao confere com o resumo do conteudo enviado; nao considere o item integro" "$unitario" 'decisao unitaria'
  assert_contem "falha b.txt: integridade ${unitario#11|integridade|nao_aplicavel|}" "$DBX_ERRO" 'mesmo motivo na linha do lote'
  unitario=$(_unitario "$DBX_HASH_RESULTADO" "$DBX_HASH_RESULTADO")
  assert_igual '0||conferida|' "$unitario" 'iguais: conferida'
}

teste_lou11_hash_ausente_nao_conferida_como_no_unitario() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt
  _devolver_hash "$base" a.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sem resumo devolvido nao e falha; $DBX_ERRO"
  assert_contem 'enviados=3' "$DBX_SAIDA"
  assert_igual '0||nao_aplicavel|' "$(_unitario aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)" 'unitario: nao conferida'
}

teste_lou12_o_corpo_do_start_leva_content_hash() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  dbx_hash_publicar_arquivo "$base/local/a.txt"
  assert_contem "content_hash\\\":\\\"$DBX_HASH_RESULTADO" "$(<"$base/lote/confs")" 'start de a.txt'
  dbx_hash_publicar_arquivo "$base/local/b.txt"
  assert_contem "content_hash\\\":\\\"$DBX_HASH_RESULTADO" "$(<"$base/lote/confs")" 'start de b.txt'
}

# ---------------------------------------------------------------------------
# RF-137: sinal, falha de start sob --paralelo e plano misto
# ---------------------------------------------------------------------------

teste_lou13_sinal_no_meio_do_lote_de_envio_sem_estado_nem_processo() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt
  printf 'INT' >"$base/sinal"
  printf 'upload_session/finish_batch_v2' >"$base/sinal_url"
  _rodar_em_sessao "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 14 "$DBX_ESTADO" 'interrompido e nao_concluida'
  assert_igual 1 "$(_harness_contar 'finish_batch_v2' "$base/chamadas")" 'o sinal chegou no finish'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area temporaria'
  if [[ -d $base/estado ]] && find "$base/estado" -name '*retomada*' | grep -q .; then
    _harness_falhar 'o lote nao grava estado de retomada'
  fi
  assert_igual 0 "$(pgrep -f -- "$base" | wc -l)" 'nenhum processo vivo'
}

teste_lou14_paralelo_4_com_falha_de_start_de_um_item_falha_so_ele() {
  local base
  base=$(_cenario)
  _local "$base" a.txt b.txt c.txt d.txt e.txt
  printf 'conteudo de c.txt' >"$base/lote/start_falha_marca"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo 4
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" "falha de item; $DBX_ERRO"
  assert_contem 'falha c.txt: ' "$DBX_ERRO" 'o item do start recusado'
  assert_contem 'enviados=4' "$DBX_SAIDA"
  assert_contem 'falhas=1' "$DBX_SAIDA"
  assert_igual 4 "$(_entradas "$base" finish_batch 1)" 'so quatro sessoes no finish'
  [[ -f $base/enviado/r/a.txt && -f $base/enviado/r/e.txt && ! -f $base/enviado/r/c.txt ]] ||
    _harness_falhar 'publicacao parcial incorreta'
}

teste_lou15_plano_misto_n4_igual_a_n1() {
  local base arvore_um estado_um n
  base=$(_cenario)
  _local "$base" p1.txt p2.txt p3.txt p4.txt
  head -c 1048577 /dev/zero >"$base/local/g1.bin"
  head -c 1048578 /dev/zero >"$base/local/g2.bin"
  touch -d '2020-01-01' "$base/local/g1.bin" "$base/local/g2.bin"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "N=1; $DBX_ERRO"
  arvore_um=$(_equivalencia_arvore "$base")
  estado_um=$(find "$base/estado" -type f 2>/dev/null | wc -l)
  assert_igual 1 "$(_n "$base" finish_batch)" 'N=1: os quatro pequenos em um finish'
  assert_igual 4 "$(_entradas "$base" finish_batch 1)" 'N=1: so os pequenos'
  assert_contem 'enviados=6' "$DBX_SAIDA" 'N=1'
  # shellcheck disable=SC2043  # um N so por custo; o laco aceita outros
  for n in 4; do
    rm -rf "$base/enviado" "$base/estado" "$base/lote/chamadas"
    mkdir -p "$base/enviado"
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --paralelo "$n"
    assert_igual 0 "$DBX_ESTADO" "N=$n; $DBX_ERRO"
    assert_igual "$arvore_um" "$(_equivalencia_arvore "$base")" "N=$n: mesmos arquivos"
    assert_igual "$estado_um" "$(find "$base/estado" -type f 2>/dev/null | wc -l)" "N=$n: mesmo cache"
    assert_igual 4 "$(_entradas "$base" finish_batch 1)" "N=$n: so os pequenos no lote"
    assert_contem 'enviados=6' "$DBX_SAIDA" "N=$n"
  done
}

teste_lot12_interrupcao_na_conferencia_diz_que_a_exclusao_pode_ter_sido_concluida() {
  local base
  base=$(_cenario)
  _local "$base" fica.txt
  _remoto "$base" fica.txt x1.txt
  printf 'INT' >"$base/sinal"
  printf 'delete_batch/check' >"$base/sinal_url"
  _rodar_em_sessao "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 14 "$DBX_ESTADO" 'interrompido'
  assert_contem 'pode ter sido concluida no servidor' "$DBX_ERRO" 'DIV-275'
}

# lot13: a SEGUNDA barreira da guarda destrutiva (RF-80(d)), provada no ponto do
# lote. O plano ja tira o item protegido (`_dbx_cmd_sync_sem_protegidos`); aqui o
# plano "falhou" (DBX_SYNC_APAGAR traz o protegido) e a montagem do lote precisa
# barra-lo sozinha. Chamada direta, em subshell, com `dbx_lote_excluir` trocado
# por um duplo que registra o que receberia (o corpo do `delete_batch` e feito
# dos DBX_LOTE_CAMINHOS); nada de rede.
# shellcheck disable=SC2317,SC2031,SC2034
# Justificativa: o duplo de `dbx_lote_excluir` e chamado pela funcao sob teste; o
# subshell isola as libs carregadas; DBX_LOTE_RESULTADO e lido por commands/sync.
teste_lot13_montagem_do_lote_barra_o_protegido_mesmo_se_o_plano_falhar() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/lote13.XXXXXX")
  (
    . "$DBX_HARNESS_RAIZ/lib/filtro.sh"
    . "$DBX_HARNESS_RAIZ/lib/tmp.sh"
    . "$DBX_HARNESS_RAIZ/lib/progress.sh"
    . "$DBX_HARNESS_RAIZ/lib/lote.sh"
    . "$DBX_HARNESS_RAIZ/commands/sync.sh"
    dbx_lote_excluir() { printf '%s\n' "${DBX_LOTE_CAMINHOS[@]}" >"$base/recebido"; DBX_LOTE_RESULTADO=(); local i; for i in "${!DBX_LOTE_CAMINHOS[@]}"; do DBX_LOTE_RESULTADO[i]=ok; done; }
    dbx_progress_etapa() { :; }
    dbx_filtro_limpar
    dbx_filtro_adicionar excluir --excluir 'protegido/*' || exit 90
    declare -A mapa_revs=()
    op_atual=0 total_ops=2 apagados=0 falhas=0
    DBX_SYNC_APAGAR=(protegido/a.txt livre.txt)
    _dbx_cmd_sync_apagar_remoto_em_lote /r
    printf '%s %s\n' "$apagados" "$falhas" >"$base/contagem"
  )
  assert_igual 0 "$?" 'subshell do lote'
  assert_igual 1 "$(_harness_contar '' "$base/recebido")" 'so um item chega ao lote'
  assert_igual '/r/livre.txt' "$(<"$base/recebido")" 'o protegido nunca entra no corpo'
  assert_igual '1 0' "$(<"$base/contagem")" 'so o livre conta como apagado'
}

harness_executar "$@"
