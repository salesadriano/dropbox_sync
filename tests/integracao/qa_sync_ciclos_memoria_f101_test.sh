#!/usr/bin/env bash
# QA independente de F-101 (memoria do sync por ciclo; log
# docs/prompts/2026-11-11_1827_sync-ciclos-exclusao-indevida.md). Duble de `curl`
# proprio (remoto em disco, `falhar_em` = listagem recusada com 403); dado sintetico.
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
if [[ -f $base/falhar_em && $url == *list_folder* && $url != *list_folder/* && $p == "$(cat "$base/falhar_em")" ]]; then
  codigo=403; corpo='{"error_summary":"no_permission/..","error":{".tag":"no_permission"}}'
fi
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

# A, B, C, D com dois arquivos cada; --bloco 2 => um diretorio por ciclo.
_arvore() {
  local base=$1 d
  for d in A B C D; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/local/$d/f1.txt"
    printf '%s2' "$d" >"$base/local/$d/f2.txt"
  done
}
_arvore_remota() {
  local base=$1 d
  for d in A B C D; do
    mkdir -p "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/remote/r/$d/f1.txt"
    printf '%s2' "$d" >"$base/remote/r/$d/f2.txt"
  done
}
_memoria() { local m; for m in "$1"/estado/dbx/memoria-*; do [[ -f $m ]] && { printf '%s' "$m"; return 0; }; done; return 0; }
_conteudo_memoria() { local m; m=$(_memoria "$1"); [[ -n $m ]] && tr '\0' '\n' <"$m"; return 0; }
_cursores() { local c; for c in "$1"/estado/dbx/cursor-*; do [[ -f $c ]] && cksum <"$c"; done; return 0; }
_enviar() { _rodar "$1" --progresso sync --enviar --espelhar --confirmar --origem "$1/local" --destino /r --bloco 2; }
_receber() { local base=$1; shift; _rodar "$base" --progresso sync --receber --origem /r --destino "$base/local" --bloco 2 "$@"; }

teste_qa_ciclo_falho_preserva_o_ciclo_1_e_nao_grava_o_ciclo_falho() {
  local base antes depois
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "primeira execucao: $(cat "$base/err")"
  printf 'novo' >"$base/local/A/novo.txt"
  printf 'novo' >"$base/local/B/novo.txt"
  rm -f "$base/local/D/f1.txt"
  printf '/r/B' >"$base/falhar_em"
  _enviar "$base"
  assert_diferente 0 "$DBX_ESTADO" 'falha sistemica no ciclo 2 sai diferente de zero'
  depois=$(_conteudo_memoria "$base")
  assert_contem 'A/novo.txt' "$depois" 'ciclo 1 concluido esta na memoria'
  assert_nao_contem 'B/novo.txt' "$depois" 'o ciclo falho nao grava o que viu'
  assert_contem 'B/f1.txt' "$depois" 'carregada do diretorio do ciclo falho mantida'
  assert_contem 'D/f1.txt' "$depois" 'ciclo falho nao e gravacao final: nada sai da memoria'
  assert_nao_contem 'DEL' "$(cat "$base/log")" 'nenhuma exclusao remota apos a falha (D nao observado)'
}

teste_qa_memoria_interrompida_e_inteira_sem_temporario_e_a_execucao_seguinte_a_aproveita() {
  local base m
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  printf 'novo' >"$base/local/A/novo.txt"
  rm -f "$base/local/D/f1.txt"
  printf '/r/C' >"$base/matar_em"
  _enviar "$base"
  assert_diferente 0 "$DBX_ESTADO" 'interrompida no ciclo 3'
  m=$(_memoria "$base")
  assert_igual 1 "$(find "$base/estado/dbx" -maxdepth 1 -name 'memoria-*' | wc -l)" 'um unico arquivo de memoria'
  assert_igual '' "$(find "$base/estado/dbx" -maxdepth 1 -name '.memoria.*')" 'nenhum temporario de escrita deixado'
  rm -f "$base/matar_em"; : >"$base/log"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "a execucao seguinte completa: $(cat "$base/err")"
  assert_contem 'D/f1.txt' "$(cat "$base/log")" 'a memoria por ciclo manteve o D/f1 conhecido: a exclusao legitima acontece depois'
  assert_nao_contem 'D/f1.txt' "$(_conteudo_memoria "$base")" 'a gravacao final remove o que sumiu da origem'
}

teste_qa_receber_em_ciclos_grava_a_memoria_por_ciclo_e_a_interrupcao_nao_grava_cursor() {
  local base cursor_antes depois
  base=$(_cen)
  _arvore_remota "$base"
  _receber "$base" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "primeiro recebimento: $(cat "$base/err")"
  # A memoria guarda o que ja existia no destino ao listar: so a segunda
  # execucao completa a povoa com os quatro diretorios.
  _receber "$base" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "segundo recebimento: $(cat "$base/err")"
  assert_contem 'D/f2.txt' "$(_conteudo_memoria "$base")" 'memoria povoada pelo recebimento completo'
  cursor_antes=$(_cursores "$base")
  printf 'novo' >"$base/remote/r/A/novo.txt"
  printf '/r/C' >"$base/matar_em"
  _receber "$base" --espelhar --confirmar
  assert_diferente 0 "$DBX_ESTADO" 'recebimento interrompido no ciclo 3'
  depois=$(_conteudo_memoria "$base")
  assert_contem 'A/f1.txt' "$depois" 'recebimento: o ciclo 1 esta na memoria'
  assert_contem 'C/f1.txt' "$depois" 'recebimento: carregada do ciclo interrompido (C) mantida'
  assert_contem 'D/f2.txt' "$depois" 'recebimento: carregada de D, ainda nao processado, mantida'
  assert_igual "$cursor_antes" "$(_cursores "$base")" 'a interrupcao nao cria nem altera cursor-* (so a execucao integral o grava)'
}

teste_qa_estado_sem_permissao_avisa_uma_vez_em_varios_ciclos_e_nao_falha() {
  [[ $(id -u) -ne 0 ]] || pular 'como root todo diretorio pertence ao usuario'
  local base antes
  base=$(_cen)
  _arvore "$base"
  mkdir -p "$base/estado"
  ln -s /usr "$base/estado/dbx"
  antes=$(stat -c '%a %Y' /usr)
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "falha de memoria nao e falha da execucao: $(cat "$base/err")"
  assert_igual 1 "$(grep -ac 'memoria nao gravada' "$base/err")" 'o aviso de memoria nao gravada aparece uma unica vez em quatro ciclos mais a gravacao final'
  assert_igual "$antes" "$(stat -c '%a %Y' /usr)" 'o diretorio alheio nao foi tocado'
}

teste_qa_espelhar_receber_com_remoto_mutavel_nao_apaga_arquivo_de_ciclo_anterior() {
  local base d n
  base=$(_cen)
  _arvore_remota "$base"
  _receber "$base"
  assert_igual 0 "$DBX_ESTADO" "primeiro recebimento: $(cat "$base/err")"
  printf '/r/C' >"$base/mutar_em"
  _receber "$base" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  n=0
  for d in A B C D; do [[ -f $base/local/$d/f1.txt && -f $base/local/$d/f2.txt ]] && n=$((n + 1)); done
  assert_igual 4 "$n" 'nenhum arquivo local foi apagado'
  assert_igual '' "$(grep -aE '[1-9][0-9]* a apagar|^apagar=|^apagados=[1-9]' "$base/err" "$base/out")" 'nada marcado a apagar'
}

teste_qa_ciclos_sem_falha_mantem_a_gravacao_final_mesmo_apos_uma_execucao_falha() {
  local base
  base=$(_cen)
  _arvore "$base"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "primeira execucao: $(cat "$base/err")"
  rm -f "$base/local/D/f1.txt"
  printf '/r/B' >"$base/falhar_em"
  _enviar "$base"
  assert_diferente 0 "$DBX_ESTADO" 'ciclo 2 falha'
  assert_contem 'D/f1.txt' "$(_conteudo_memoria "$base")" 'apos a falha a memoria ainda conhece D/f1'
  rm -f "$base/falhar_em"; : >"$base/log"
  _enviar "$base"
  assert_igual 0 "$DBX_ESTADO" "execucao sem falha: $(cat "$base/err")"
  assert_contem 'D/f1.txt' "$(cat "$base/log")" 'a execucao concluida apaga no remoto o arquivo removido da origem'
  assert_nao_contem 'D/f1.txt' "$(_conteudo_memoria "$base")" 'a gravacao final (so visitadas) roda em ciclos sem falha'
  assert_contem 'D/f2.txt' "$(_conteudo_memoria "$base")" 'o que segue existindo permanece na memoria'
}

harness_executar "$@"
