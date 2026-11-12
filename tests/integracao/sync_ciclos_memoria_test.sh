#!/usr/bin/env bash
# F-101: memoria do sync gravada ao fim de CADA ciclo (RF-38(b) emendado, log
# docs/prompts/2026-11-11_1827_sync-ciclos-exclusao-indevida.md). Duplo de
# `curl` com remoto em disco (`$base/remote`); dado sintetico apenas.
#
# shellcheck disable=SC2016
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

_cen() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/rep.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/remote/r"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"; chmod 600 "$base/config/dbx/credencial.json"
  { printf '#!/usr/bin/env bash\nbase=%s\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"; cat <<'FIM'
conf=$(cat 2>/dev/null)
saida=""; escrever=""; anterior=""; url=""; corpo_arquivo=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
pathof() { grep -o '"path":"[^"]*"' "$1" | head -1 | sed 's/"path":"//; s/"$//'; }
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_space_usage*) corpo='{"used":1,"allocation":{".tag":"individual","allocated":999999999}}' ;;
  *list_folder/get_latest_cursor*) corpo='{"cursor":"CURSOR-RAIZ-1"}' ;;
  *list_folder/continue*) corpo='{"entries":[],"has_more":false,"cursor":"C2"}' ;;
  *list_folder*)
    p=$(pathof "$corpo_arquivo"); printf 'LIST %s\n' "$p" >>"$base/log"
    if [[ -f $base/matar_em && $p == "$(cat "$base/matar_em")" ]]; then kill -KILL "$(cat "$base/pid")"; sleep 1; fi
    if [[ -f $base/mutar_em && $p == "$(cat "$base/mutar_em")" && ! -e $base/remote/r/B/novo.txt ]]; then printf zz >"$base/remote/r/B/novo.txt"; fi
    itens=''
    if [[ -d $base/remote$p ]]; then
      for e in "$base/remote$p"/*; do
        [[ -e $e ]] || continue
        n=${e##*/}
        if [[ -d $e ]]; then it="{\".tag\":\"folder\",\"id\":\"id:D$n\",\"path_display\":\"$p/$n\",\"path_lower\":\"${p,,}/${n,,}\"}"
        else it="{\".tag\":\"file\",\"id\":\"id:F$n\",\"path_display\":\"$p/$n\",\"path_lower\":\"${p,,}/${n,,}\",\"content_hash\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"size\":3,\"rev\":\"015f00000000a1b2\"}"; fi
        itens+=${itens:+,}$it
      done
    fi
    corpo="{\"entries\":[$itens],\"has_more\":false,\"cursor\":\"C1\"}" ;;
  *files/download*) p=$(tr -d '\\' <<<"$conf" | grep -o '"path": *"[^"]*"' | head -1 | sed 's/"path": *"//; s/"$//'); printf 'DOWN %s\n' "$p" >>"$base/log"; corpo=$(cat "$base/remote$p") ;;
  *files/upload*) p=$(tr -d '\\' <<<"$conf" | grep -o '"path": *"[^"]*"' | head -1 | sed 's/"path": *"//; s/"$//'); printf 'UP %s\n' "$p" >>"$base/log"; [[ -n $p ]] || printf "CONF[%s] ARGS[%s]\n" "$conf" "$*" >>"$base/log"
    mkdir -p "$(dirname "$base/remote$p")"; cp "$corpo_arquivo" "$base/remote$p" 2>/dev/null || : >"$base/remote$p"
    corpo="{\"name\":\"x\",\"rev\":\"015f00000000a1b3\",\"path_display\":\"$p\"}" ;;
  *create_folder_batch*) corpo='{".tag":"complete","entries":[]}'
    while IFS= read -r p; do mkdir -p "$base/remote$p"; done < <(grep -o '"path":"[^"]*"' "$corpo_arquivo" | sed 's/"path":"//; s/"$//') ;;
  *create_folder*) p=$(pathof "$corpo_arquivo"); mkdir -p "$base/remote$p"; corpo='{"metadata":{}}' ;;
  *delete_batch/check*) corpo='{".tag":"complete","entries":[]}' ;;
  *delete_batch*) printf 'DELBATCH %s\n' "$(cat "$corpo_arquivo")" >>"$base/log"; corpo='{".tag":"async_job_id","async_job_id":"J"}' ;;
  *delete*) printf 'DEL %s\n' "$(cat "$corpo_arquivo")" >>"$base/log"; corpo='{}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
case $url in *finish_batch_v2*) while IFS= read -r p; do printf 'UPB %s\n' "$p" >>"$base/log"; mkdir -p "$(dirname "$base/remote$p")"; printf zz >"$base/remote$p"; done < <(grep -o '"path": *"[^"]*"' "$corpo_arquivo" | sed 's/"path": *"//; s/"$//') ;; esac
case $url in *create_folder_batch*|*delete_batch*|*upload_session/start*|*finish_batch_v2*) LOTE_ECOA_V2=sim; . "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"; lote_responder "$url" "$corpo_arquivo" || : ;; esac
[[ -n $saida ]] && printf "%s" "$corpo" >"$saida"
[[ -n $escrever ]] && printf "%s" "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}


_rodar() { local base=$1; shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash -c 'printf "%s" "$$" >"$1/pid"; b=$1; shift; exec bash "$@"' _ "$base" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" </dev/null
  DBX_ESTADO=$?
}

# A, B, C, D: dois arquivos cada; --bloco 2 => um diretorio por ciclo.
_arvore() {
  local base=$1 d
  for d in A B C D; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/local/$d/f1.txt"
    printf '%s2' "$d" >"$base/local/$d/f2.txt"
  done
}
_memoria() { local m; for m in "$1"/estado/dbx/memoria-*; do [[ -f $m ]] && { printf '%s' "$m"; return 0; }; done; return 0; }
_enviar() { _rodar "$1" --progresso sync --enviar --espelhar --confirmar --origem "$1/local" --destino /r --bloco 2; }

teste_memoria_por_ciclo_sobrevive_a_interrupcao_com_carregadas() {
  local base m depois
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "primeira execucao: $(cat "$base/err")"
  m=$(_memoria "$base")
  [[ -n $m ]] || { assert_igual 'memoria' 'ausente' 'memoria gravada na execucao completa'; return; }
  assert_nao_contem 'A/novo.txt' "$(tr '\0' '\n' <"$m")" 'arquivo novo ainda nao esta na memoria'
  printf 'novo' >"$base/local/A/novo.txt"
  rm -f "$base/local/D/f1.txt"
  printf '/r/C' >"$base/matar_em"
  _enviar "$base"
  assert_diferente 0 "$DBX_ESTADO" 'a execucao foi interrompida no ciclo 3'
  depois=$(tr '\0' '\n' <"$(_memoria "$base")")
  assert_contem 'A/novo.txt' "$depois" 'entrada do ciclo 1 (A) gravada ao fim do ciclo'
  assert_contem 'C/f1.txt' "$depois" 'carregada do diretorio nao processado (C) mantida'
  assert_contem 'D/f1.txt' "$depois" 'carregada de D mantida: so a gravacao final remove o que sumiu'
}

teste_execucao_completa_grava_so_as_visitadas() {
  local base depois
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  rm -f "$base/local/D/f1.txt"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  depois=$(tr '\0' '\n' <"$(_memoria "$base")")
  assert_nao_contem 'D/f1.txt' "$depois" 'arquivo apagado na origem sai da memoria na gravacao final'
  assert_contem 'D/f2.txt' "$depois" 'os visitados permanecem'
}

teste_travessia_parcial_nao_grava_nem_por_ciclo() {
  local base
  base=$(_cen)
  _arvore "$base"
  chmod 000 "$base/local/D"
  _enviar "$base"
  chmod 755 "$base/local/D"
  assert_igual '' "$(_memoria "$base")" 'travessia parcial: nenhum memoria-* (nem por ciclo, nem no fim)'
}

teste_simulacao_nao_grava_memoria() {
  local base
  base=$(_cen)
  _arvore "$base"
  _rodar "$base" --dry-run sync --enviar --espelhar --origem "$base/local" --destino /r --bloco 2
  assert_igual '' "$(_memoria "$base")" 'simulacao nao grava memoria por ciclo'
}

teste_linha_de_progresso_do_ciclo_sem_sufixo_nao() {
  local base
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  assert_contem '[sync] ciclo 1: diretorios 1 a 2' "$(cat "$base/err")" 'linha de progresso presente'
  assert_nao_contem 'nao' "$(grep -a '\[sync\] ciclo' "$base/err")" 'sem o sufixo nao (variavel morta removida)'
}

teste_espelhar_em_varios_ciclos_com_remoto_mutavel_nao_apaga_nada() {
  local base
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  : >"$base/log"
  printf '/r/C' >"$base/mutar_em"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_nao_contem 'DEL' "$(cat "$base/log")" 'nenhuma exclusao remota'
  assert_igual '' "$(grep -aE '[1-9][0-9]* a apagar|^apagar=|^apagados=[1-9]' "$base/err" "$base/out")" 'nada marcado a apagar de ciclo anterior'
}

harness_executar "$@"
