#!/usr/bin/env bash
# F-101 (log docs/prompts/2026-11-11_2210_sync-orfaos-no-fim.md): no `sync
# --espelhar` nenhum orfao e apagado durante os ciclos; todas as exclusoes saem
# DEPOIS do ultimo ciclo, so com todos os ciclos concluidos, e cada candidata e
# reconferida contra o conjunto completo da origem desta execucao. Duplo de
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
# resolver <caminho> — a Dropbox ignora a caixa: o arquivo `alias` (`de=para`) faz o
# duplo responder por `para` quando o caminho pedido e `de` (REPLY_P).
resolver() { local r=$1 de para; if [[ -f $base/alias ]]; then while IFS== read -r de para; do if [[ $r == "$de" || $r == "$de"/* ]]; then r=$para${r#"$de"}; break; fi; done <"$base/alias"; fi; REPLY_P=$r; }
pathof() { grep -o '"path":"[^"]*"' "$1" | head -1 | sed 's/"path":"//; s/"$//'; }
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *get_space_usage*) corpo='{"used":1,"allocation":{".tag":"individual","allocated":999999999}}' ;;
  *list_folder/get_latest_cursor*) corpo='{"cursor":"CURSOR-RAIZ-1"}' ;;
  *list_folder/continue*) corpo='{"entries":[],"has_more":false,"cursor":"C2"}' ;;
  *list_folder*)
    p=$(pathof "$corpo_arquivo")
    resolver "$p"; pr=$REPLY_P
    if [[ -e $base/local/A/orf.txt ]]; then pres=sim; else pres=nao; fi
    printf 'LIST %s orfao=%s\n' "$p" "$pres" >>"$base/log"
    if [[ -f $base/matar_em && $p == "$(cat "$base/matar_em")" ]]; then kill -KILL "$(cat "$base/pid")"; sleep 1; fi
    itens=''
    if [[ -f $base/falhar_em && $p == "$(cat "$base/falhar_em")" ]]; then
      codigo=403
    elif [[ -d $base/remote$pr ]]; then
      for e in "$base/remote$pr"/*; do
        [[ -e $e ]] || continue
        n=${e##*/}
        if [[ -d $e ]]; then it="{\".tag\":\"folder\",\"id\":\"id:D$n\",\"path_display\":\"$pr/$n\",\"path_lower\":\"${pr,,}/${n,,}\"}"
        else it="{\".tag\":\"file\",\"id\":\"id:F$n\",\"path_display\":\"$pr/$n\",\"path_lower\":\"${pr,,}/${n,,}\",\"content_hash\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"size\":3,\"rev\":\"015f00000000a1b2\"}"; fi
        itens+=${itens:+,}$it
      done
    fi
    if [[ -f $base/extra_em ]] && IFS='|' read -r pe ee <"$base/extra_em" && [[ $p == "$pe" ]]; then
      itens+=${itens:+,}"{\".tag\":\"file\",\"id\":\"id:FX\",\"path_display\":\"$ee\",\"path_lower\":\"${ee,,}\",\"content_hash\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"size\":3,\"rev\":\"015f00000000a1b2\"}"
    fi
    corpo="{\"entries\":[$itens],\"has_more\":false,\"cursor\":\"C1\"}"
    [[ $codigo == 403 ]] && corpo='{"error_summary":"no_permission/.","error":{".tag":"no_permission"}}' ;;
  *files/download*) p=$(tr -d '\\' <<<"$conf" | grep -o '"path": *"[^"]*"' | head -1 | sed 's/"path": *"//; s/"$//'); printf 'DOWN %s\n' "$p" >>"$base/log"; corpo=$(cat "$base/remote$p") ;;
  *files/upload*) p=$(tr -d '\\' <<<"$conf" | grep -o '"path": *"[^"]*"' | head -1 | sed 's/"path": *"//; s/"$//'); printf 'UP %s\n' "$p" >>"$base/log"
    mkdir -p "$(dirname "$base/remote$p")"; cp "$corpo_arquivo" "$base/remote$p" 2>/dev/null || : >"$base/remote$p"
    corpo="{\"name\":\"x\",\"rev\":\"015f00000000a1b3\",\"path_display\":\"$p\"}" ;;
  *create_folder_batch*) corpo='{".tag":"complete","entries":[]}'
    while IFS= read -r p; do resolver "$p"; mkdir -p "$base/remote$REPLY_P"; done < <(grep -o '"path":"[^"]*"' "$corpo_arquivo" | sed 's/"path":"//; s/"$//') ;;
  *create_folder*) p=$(pathof "$corpo_arquivo"); mkdir -p "$base/remote$p"; corpo='{"metadata":{}}' ;;
  *delete_batch/check*) corpo='{".tag":"complete","entries":[]}' ;;
  *delete_batch*) printf 'DELBATCH %s\n' "$(cat "$corpo_arquivo")" >>"$base/log"; corpo='{".tag":"async_job_id","async_job_id":"J"}' ;;
  *delete*) printf 'DEL %s\n' "$(cat "$corpo_arquivo")" >>"$base/log"; corpo='{}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
case $url in *finish_batch_v2*) while IFS= read -r p; do printf 'UPB %s\n' "$p" >>"$base/log"; resolver "$p"; mkdir -p "$(dirname "$base/remote$REPLY_P")"; printf zz >"$base/remote$REPLY_P"; done < <(grep -o '"path": *"[^"]*"' "$corpo_arquivo" | sed 's/"path": *"//; s/"$//') ;; esac
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

# A, B, C, D: dois arquivos cada; --bloco 2 => um diretorio por ciclo. O orfao
# real do destino (`orf.txt`) fica em A, o diretorio do ciclo 1.
_arvore_envio() {
  local base=$1 d
  for d in A B C D; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/local/$d/f1.txt"
    printf '%s2' "$d" >"$base/local/$d/f2.txt"
  done
  printf 'orf' >"$base/remote/r/A/orf.txt"
}
# Mesma arvore no sentido inverso: a origem e o remoto, o orfao e local.
_arvore_recebimento() {
  local base=$1 d
  for d in A B C D; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/remote/r/$d/f1.txt"
    printf '%s2' "$d" >"$base/remote/r/$d/f2.txt"
  done
  printf 'orf' >"$base/local/A/orf.txt"
}
_enviar() { _rodar "$base" "$@" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --bloco 2; }
_receber() { _rodar "$base" "$@" sync --receber --espelhar --confirmar --origem /r --destino "$base/local" --bloco 2; }
# _linha <padrao> <primeira|ultima> — numero da linha do log da chamada ('' se nao houve).
_linha() {
  if [[ $2 == 'primeira' ]]; then grep -anE -- "$1" "$base/log" | head -1 | cut -d: -f1
  else grep -anE -- "$1" "$base/log" | tail -1 | cut -d: -f1; fi
}

# A listagem do ciclo 1 (`/r/A`) devolve tambem `/r/B/x.txt`, que a origem so tem
# no ciclo 2 (B): candidata no ciclo 1, presente na origem completa.
teste_candidato_de_ciclo_anterior_presente_em_ciclo_posterior_nao_e_apagado() {
  local base
  base=$(_cen)
  _arvore_envio "$base"
  rm -f "$base/remote/r/A/orf.txt"
  printf 'x' >"$base/local/B/x.txt"
  printf '%s|%s\n' '/r/A' '/r/B/x.txt' >"$base/extra_em"
  _enviar --debug
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 0 "$(_harness_contar 'DELBATCH' "$base/log")" 'nenhuma exclusao em lote: a candidata esta num ciclo posterior da origem'
  assert_igual 0 "$(_harness_contar '^DEL ' "$base/log")" 'nenhuma exclusao unitaria'
  assert_igual 1 "$(_harness_contar 'decisao=apagar motivo=espelho-apaga-orfao item=B/x.txt' "$base/err")" 'a decisao do ciclo continua registrada'
  assert_igual 1 "$(_harness_contar 'decisao=pular motivo=presente-na-origem item=B/x.txt' "$base/err")" 'a reconferencia registra o descarte'
}

teste_orfao_real_so_e_apagado_depois_do_ultimo_ciclo() {
  local base ultimo_ciclo ultima_transferencia exclusao
  base=$(_cen)
  _arvore_envio "$base"
  _enviar
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  exclusao=$(_linha 'DELBATCH' primeira)
  assert_igual 1 "$(_harness_contar 'DELBATCH.*A/orf.txt' "$base/log")" 'o orfao do ciclo 1 foi excluido'
  ultimo_ciclo=$(_linha '^LIST /r/D' ultima)
  ultima_transferencia=$(_linha '^(UP|UPB) ' ultima)
  [[ $exclusao -gt $ultimo_ciclo && $exclusao -gt $ultima_transferencia ]]
  assert_igual 0 "$?" "exclusao (linha $exclusao) depois do ultimo ciclo ($ultimo_ciclo) e da ultima transferencia ($ultima_transferencia)"
}

teste_ciclo_falho_nao_apaga_orfao() {
  local base
  base=$(_cen)
  _arvore_envio "$base"
  printf '/r/C' >"$base/falhar_em"
  _enviar
  assert_diferente 0 "$DBX_ESTADO" 'o ciclo 3 falhou'
  assert_contem 'ciclo_falho=3' "$(cat "$base/out")" 'o relatorio aponta o ciclo falho'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'nenhuma exclusao de orfao com ciclo falho'
  assert_igual 1 "$(_harness_contar '^LIST /r/A' "$base/log")" 'o ciclo 1 chegou a ver o orfao'
  assert_igual 1 "$([[ -e $base/remote/r/A/orf.txt ]] && echo 1 || echo 0)" 'o orfao continua no destino'
}

teste_execucao_interrompida_nao_apaga_orfao() {
  local base
  base=$(_cen)
  _arvore_envio "$base"
  printf '/r/C' >"$base/matar_em"
  _enviar
  assert_diferente 0 "$DBX_ESTADO" 'a execucao foi interrompida no ciclo 3'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'nenhuma exclusao antes do fim'
}

teste_simulacao_lista_apagaria_no_fim_sem_escrever() {
  local base saida
  base=$(_cen)
  _arvore_envio "$base"
  _rodar "$base" --dry-run sync --enviar --espelhar --origem "$base/local" --destino /r --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  saida=$(cat "$base/out")
  assert_contem 'apagaria=A/orf.txt' "$saida" 'o orfao e anunciado no fim'
  assert_contem 'simulado=sim' "$saida" 'resumo da simulacao'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'a simulacao nao exclui'
  assert_igual 1 "$(_harness_contar '^apagaria=A/orf.txt' "$base/out")" 'uma so linha apagaria para o orfao'
}

teste_recebimento_apaga_orfao_local_so_depois_do_ultimo_ciclo() {
  local base ultimo
  base=$(_cen)
  _arvore_recebimento "$base"
  _receber
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  ultimo=$(_linha '^LIST /r/D' ultima)
  assert_contem "orfao=sim" "$(sed -n "${ultimo}p" "$base/log")" 'durante o ultimo ciclo o orfao local ainda existe'
  assert_igual 0 "$([[ -e $base/local/A/orf.txt ]] && echo 1 || echo 0)" 'depois do ultimo ciclo o orfao local foi apagado'
  assert_igual 1 "$([[ -e $base/local/D/f2.txt ]] && echo 1 || echo 0)" 'o que a origem tem foi recebido'
}

teste_recebimento_ciclo_falho_nao_apaga_orfao_local() {
  local base
  base=$(_cen)
  _arvore_recebimento "$base"
  printf '/r/C' >"$base/falhar_em"
  _receber
  assert_diferente 0 "$DBX_ESTADO" 'o ciclo 3 falhou'
  assert_igual 1 "$([[ -e $base/local/A/orf.txt ]] && echo 1 || echo 0)" 'o orfao local continua'
}

teste_recebimento_simulacao_lista_apagaria_no_fim() {
  local base
  base=$(_cen)
  _arvore_recebimento "$base"
  _rodar "$base" --dry-run sync --receber --espelhar --origem /r --destino "$base/local" --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 1 "$(_harness_contar '^apagaria=A/orf.txt' "$base/out")" 'o orfao local e anunciado no fim'
  assert_igual 1 "$([[ -e $base/local/A/orf.txt ]] && echo 1 || echo 0)" 'a simulacao nao apaga'
}

teste_pasta_orfa_continua_sendo_apagada_no_fim() {
  local base ultima_transferencia exclusao
  base=$(_cen)
  _arvore_envio "$base"
  mkdir -p "$base/remote/r/P"
  _enviar
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  exclusao=$(_linha '^DEL .*/r/P' primeira)
  ultima_transferencia=$(_linha '^(UP|UPB) ' ultima)
  assert_igual 1 "$(_harness_contar '^DEL .*/r/P' "$base/log")" 'a pasta orfa foi excluida'
  [[ -n $exclusao && $exclusao -gt $ultima_transferencia ]]
  assert_igual 0 "$?" "pasta orfa (linha $exclusao) depois da ultima transferencia ($ultima_transferencia)"
  assert_igual 1 "$(_harness_contar 'DELBATCH.*A/orf.txt' "$base/log")" 'o arquivo orfao tambem saiu'
  assert_igual 1 "$([[ $(_linha 'DELBATCH' primeira) -lt $exclusao ]] && echo 1 || echo 0)" 'arquivos antes das pastas'
}

# A pasta so difere na caixa fora do ASCII (local `HIDRÁULICO`, remoto `Hidráulico`), o
# `dbx` roda sob `LC_ALL=C` (o ambiente do duplo nao fixa localidade) e o par esta
# em OUTRO ciclo: a chave de diretorio tem a mesma dobra da de arquivo, a pasta
# remota nao vira ramo so do destino e nada e apagado nem reenviado em duplicata.
teste_pasta_com_caixa_diferente_fora_do_ascii_nao_vira_ramo_so_do_destino() {
  local base
  base=$(_cen)
  mkdir -p "$base/local/HIDRÁULICO" "$base/local/ZZ" "$base/remote/r/Hidráulico"
  printf 'r1' >"$base/local/r1.txt"; printf 'r2' >"$base/local/r2.txt"
  printf 'h1' >"$base/local/HIDRÁULICO/f1.txt"; printf 'h2' >"$base/local/HIDRÁULICO/f2.txt"
  printf 'z1' >"$base/local/ZZ/f1.txt"; printf 'z2' >"$base/local/ZZ/f2.txt"
  printf 'h1' >"$base/remote/r/Hidráulico/f1.txt"; printf 'h2' >"$base/remote/r/Hidráulico/f2.txt"
  printf '%s=%s\n' '/r/HIDRÁULICO' '/r/Hidráulico' >"$base/alias"
  _enviar
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'nada apagado'
  assert_igual 0 "$(_harness_contar '^LIST /r/Hidráulico' "$base/log")" 'a pasta remota nao foi lida como ramo so do destino'
  assert_igual 0 "$(_harness_contar 'pasta mantida\|pasta apagada' "$base/err")" 'nem candidata a pasta orfa'
  assert_igual 0 "$(_harness_contar '^UPB /r/HIDRÁULICO' "$base/log")" 'nenhum envio em duplicata com a grafia local'
  assert_igual 0 "$([[ -e $base/remote/r/HIDRÁULICO ]] && echo 1 || echo 0)" 'nenhuma pasta duplicada no destino'
}

harness_executar "$@"
