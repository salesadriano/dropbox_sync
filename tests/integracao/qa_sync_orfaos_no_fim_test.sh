#!/usr/bin/env bash
# QA independente de F-101 (log docs/prompts/2026-11-11_2210_sync-orfaos-no-fim.md):
# no `sync --espelhar` em ciclos (`--bloco 2`) nenhum orfao (arquivo ou pasta) sai
# antes do fim do ultimo ciclo; so sai com todos concluidos, sem travessia parcial
# nem origem vazia recusada; cada candidata e reconferida contra a origem completa.
# Cenario real: pasta movida na origem (`A/2ANA` -> `B/X/2ANA`). Duplo de `curl`
# com remoto em disco (`$base/remote`), proprio do QA; dado sintetico apenas.
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

# Roda de dentro de `$base`, para o nome-isca `$(>PWN)` do caso de injecao cair la.
_rodar() { local base=$1; shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash -c 'cd "$1" || exit 99; printf "%s" "$$" >"$1/pid"; b=$1; shift; exec bash "$@"' _ "$base" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err" </dev/null
  DBX_ESTADO=$?
}
_enviar() { _rodar "$base" "$@" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --bloco 2; }
_receber() { _rodar "$base" "$@" sync --receber --espelhar --confirmar --origem /r --destino "$base/local" --bloco 2; }
# _linha <padrao> <primeira|ultima> — numero da linha do log ('' se nao houve).
_linha() {
  if [[ $2 == 'primeira' ]]; then grep -anE -- "$1" "$base/log" | head -1 | cut -d: -f1
  else grep -anE -- "$1" "$base/log" | tail -1 | cut -d: -f1; fi
}
_existe() { [[ -e $1 ]] && printf 1 || printf 0; }
# Ciclo 1 (A) com o par de arquivos que o remoto ja tem; a copia ANTIGA da pasta
# vive so no destino (`r/A/2ANA`, ramo so do destino); a NOVA vive so na origem
# (`B/X/2ANA`), em ciclo posterior.
_cenario_movida() {
  local base=$1 d
  for d in A B; do mkdir -p "$base/local/$d" "$base/remote/r/$d"; done
  for d in A B; do
    printf '%s1' "$d" >"$base/local/$d/f1.txt"; printf '%s1' "$d" >"$base/remote/r/$d/f1.txt"
    printf '%s2' "$d" >"$base/local/$d/f2.txt"; printf '%s2' "$d" >"$base/remote/r/$d/f2.txt"
  done
  mkdir -p "$base/local/B/X/2ANA" "$base/remote/r/A/2ANA"
  printf 'n1' >"$base/local/B/X/2ANA/n1.txt"; printf 'n2' >"$base/local/B/X/2ANA/n2.txt"
  printf 'o1' >"$base/remote/r/A/2ANA/n1.txt"; printf 'o2' >"$base/remote/r/A/2ANA/n2.txt"
}
_arvore_simples() {
  local base=$1 d
  for d in A B C D; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/local/$d/f1.txt"; printf '%s1' "$d" >"$base/remote/r/$d/f1.txt"
    printf '%s2' "$d" >"$base/local/$d/f2.txt"; printf '%s2' "$d" >"$base/remote/r/$d/f2.txt"
  done
  printf 'orf' >"$base/remote/r/A/orf.txt"
}

teste_pasta_movida_envia_o_caminho_novo_antes_de_excluir_o_antigo() {
  local base envio_novo exclusao
  base=$(_cen)
  _cenario_movida "$base"
  _enviar
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  envio_novo=$(_linha '^(UP|UPB) /r/B/X/2ANA/n2.txt' ultima)
  exclusao=$(_linha 'DELBATCH.*A/2ANA/n1.txt|^DEL .*A/2ANA' primeira)
  assert_diferente '' "$envio_novo" 'o caminho novo foi enviado'
  assert_diferente '' "$exclusao" 'a copia antiga foi excluida'
  [[ $envio_novo -lt $exclusao ]]
  assert_igual 0 "$?" "envio do novo (linha $envio_novo) antes da exclusao do antigo (linha $exclusao)"
  assert_igual 1 "$(_harness_contar 'DELBATCH.*A/2ANA/n1.txt' "$base/log")" 'os arquivos antigos saem por lote'
}

teste_pasta_movida_com_falha_no_ciclo_do_caminho_novo_deixa_as_duas_copias() {
  local base
  base=$(_cen)
  _cenario_movida "$base"
  printf '/r/B' >"$base/falhar_em"
  _enviar
  assert_diferente 0 "$DBX_ESTADO" 'o ciclo do caminho novo falhou'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'nenhuma exclusao: a copia antiga sobra'
  assert_igual 1 "$(_existe "$base/remote/r/A/2ANA/n1.txt")" 'a copia antiga continua no destino'
}

teste_pasta_movida_com_morte_por_sinal_entre_ciclos_nao_exclui_nada() {
  local base
  base=$(_cen)
  _cenario_movida "$base"
  printf '/r/B' >"$base/matar_em"
  _enviar
  assert_diferente 0 "$DBX_ESTADO" 'a execucao morreu por sinal no ciclo do caminho novo'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'nenhuma exclusao antes do fim'
  assert_igual 1 "$(_existe "$base/remote/r/A/2ANA/n1.txt")" 'a copia antiga continua no destino'
}

teste_travessia_parcial_bloqueia_as_candidatas_de_todos_os_ciclos() {
  local base
  base=$(_cen)
  _arvore_simples "$base"
  chmod 000 "$base/local/D"
  _enviar
  chmod 755 "$base/local/D"
  assert_diferente 0 "$(_harness_contar '^travessia_parcial=sim' "$base/out")" 'premissa: a travessia ficou parcial (diretorio D ilegivel)'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" "nenhuma exclusao com travessia parcial; err: $(cat "$base/err")"
  assert_igual 1 "$(_existe "$base/remote/r/A/orf.txt")" 'o orfao do ciclo 1 continua no destino'
}

# Origem local vazia, destino com ramos so do destino em varios ciclos: a recusa
# vale para todos, nada e apagado em nenhum ciclo; com a opcao explicita, so no fim.
teste_origem_vazia_recusada_nao_apaga_candidatas_de_nenhum_ciclo() {
  local base
  base=$(_cen)
  _arvore_simples "$base"
  rm -rf "$base/local" && mkdir -p "$base/local"
  _enviar
  assert_diferente 0 "$DBX_ESTADO" 'origem vazia com algo a apagar e recusada'
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" "nenhuma exclusao na recusa; out: $(cat "$base/out")"
}

teste_origem_vazia_permitida_exclui_em_lote_so_depois_de_ler_o_destino_inteiro() {
  local base ultima_lista exclusao
  base=$(_cen)
  _arvore_simples "$base"
  rm -rf "$base/local" && mkdir -p "$base/local"
  _rodar "$base" sync --enviar --espelhar --confirmar --permitir-origem-vazia --origem "$base/local" --destino /r --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  exclusao=$(_linha 'DELBATCH|^DEL ' primeira)
  ultima_lista=$(_linha "^LIST /r/D" primeira)
  assert_diferente '' "$exclusao" 'com a opcao explicita as exclusoes saem'
  [[ $exclusao -gt $ultima_lista ]]
  assert_igual 0 "$?" "primeira exclusao (linha $exclusao) depois da leitura do destino inteiro (linha $ultima_lista)"
}

teste_filtro_protege_candidata_no_fim_e_o_resto_sai() {
  local base
  base=$(_cen)
  _arvore_simples "$base"
  printf 'bak' >"$base/remote/r/B/velho.bak"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --bloco 2 --excluir '*.bak'
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 1 "$(_harness_contar 'DELBATCH.*A/orf.txt' "$base/log")" 'o orfao nao filtrado sai'
  assert_igual 0 "$(_harness_contar 'velho.bak' "$base/log")" 'o orfao protegido pelo filtro nunca e excluido'
}

teste_candidata_presente_na_origem_em_ciclo_posterior_so_difere_na_caixa() {
  local base
  base=$(_cen)
  _arvore_simples "$base"
  rm -f "$base/remote/r/A/orf.txt"
  printf 'x' >"$base/local/C/Doc.TXT"
  printf '%s|%s\n' '/r/A' '/r/C/doc.txt' >"$base/extra_em"
  _enviar --debug
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 0 "$(_harness_contar 'DEL' "$base/log")" 'a caixa diferente e o mesmo arquivo: nao apaga'
  assert_igual 1 "$(_harness_contar 'decisao=pular motivo=presente-na-origem' "$base/err")" 'o descarte da reconferencia e registrado'
}

teste_recebimento_com_pasta_movida_so_apaga_a_copia_antiga_no_fim() {
  local base d
  base=$(_cen)
  mkdir -p "$base/local/A/2ANA" "$base/remote/r/B/X/2ANA"
  for d in A B; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/remote/r/$d/f1.txt"; printf '%s1' "$d" >"$base/local/$d/f1.txt"
    printf '%s2' "$d" >"$base/remote/r/$d/f2.txt"; printf '%s2' "$d" >"$base/local/$d/f2.txt"
  done
  printf 'o1' >"$base/local/A/2ANA/n1.txt"; printf 'o2' >"$base/local/A/2ANA/n2.txt"
  printf 'n1' >"$base/remote/r/B/X/2ANA/n1.txt"; printf 'n2' >"$base/remote/r/B/X/2ANA/n2.txt"
  _receber
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 1 "$(_existe "$base/local/B/X/2ANA/n1.txt")" 'a copia nova foi recebida'
  assert_igual 0 "$(_existe "$base/local/A/2ANA/n1.txt")" 'a copia antiga foi apagada no fim'
}

teste_recebimento_interrompido_entre_ciclos_mantem_as_duas_copias() {
  local base d
  base=$(_cen)
  mkdir -p "$base/local/A/2ANA" "$base/remote/r/B/X/2ANA"
  for d in A B; do
    mkdir -p "$base/local/$d" "$base/remote/r/$d"
    printf '%s1' "$d" >"$base/remote/r/$d/f1.txt"; printf '%s1' "$d" >"$base/local/$d/f1.txt"
    printf '%s2' "$d" >"$base/remote/r/$d/f2.txt"; printf '%s2' "$d" >"$base/local/$d/f2.txt"
  done
  printf 'o1' >"$base/local/A/2ANA/n1.txt"
  printf 'n1' >"$base/remote/r/B/X/2ANA/n1.txt"
  printf '/r/B' >"$base/falhar_em"
  _receber
  assert_diferente 0 "$DBX_ESTADO" 'o ciclo do caminho novo falhou'
  assert_igual 1 "$(_existe "$base/local/A/2ANA/n1.txt")" 'a copia antiga local continua'
}

teste_simulacao_com_pasta_movida_anuncia_no_fim_e_nao_chama_exclusao() {
  local base
  base=$(_cen)
  _cenario_movida "$base"
  _rodar "$base" --dry-run sync --enviar --espelhar --origem "$base/local" --destino /r --bloco 2
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $(cat "$base/err")"
  assert_igual 1 "$(_harness_contar '^apagaria=A/2ANA/n1.txt' "$base/out")" 'a copia antiga e anunciada'
  assert_igual 0 "$(_harness_contar 'DEL\|^UP' "$base/log")" 'nenhuma exclusao nem escrita na simulacao'
}

# Nome-isca com substituicao de comando (a chave e dobrada para minuscula, e `pwn` o que ela cria): o nome e dado (local ou da Dropbox), nunca codigo.
teste_zz_nome_com_substituicao_de_comando_nao_executa_na_reconferencia() {
  local base
  base=$(_cen)
  _arvore_simples "$base"
  rm -f "$base/remote/r/A/orf.txt"
  printf 'x' >"$base/local/B"/'x$(>pwn).txt'
  printf '%s|%s\n' '/r/A' '/r/B/x$(>pwn).txt' >"$base/extra_em"
  _enviar
  assert_igual 0 "$(_existe "$base/pwn")" "o nome do arquivo foi executado como comando; err: $(cat "$base/err")"
}

harness_executar "$@"
