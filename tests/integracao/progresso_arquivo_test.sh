#!/usr/bin/env bash
# Progresso por arquivo ponta a ponta (F-49; RF-140 a RF-147; TC-PRG-02, 06 a 10,
# 13 a 15, 21 a 23, 25, 28, 31 a 35), pelo executavel real e com o duplo de `curl`
# de tests/integracao/sync_test.sh.
#
# shellcheck disable=SC2016,SC2119,SC2120
# Justificativa: o duplo de `curl` precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

printf -v H64A 'a%.0s' {1..64}
printf -v H64B 'b%.0s' {1..64}
readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

_cenario() {
  local listagem=${1:-'{"entries":[],"has_more":false}'}
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/sync.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' "$listagem" >"$base/listagem"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    printf 'conf=$(cat 2>/dev/null)\n'
    printf 'printf "%%s\\n" "$conf" >>"$base/opcoes"\n'
    printf 'saida=""; escrever=""; anterior=""; url=""; cabecalhos=""; corpo_arquivo=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'printf "%%s\\n" "$url" >>"$base/chamadas"\n'
    printf 'codigo=200\n'
    printf 'case $url in\n'
    printf '  *oauth2/token*) corpo=%s ;;\n' "'{\"access_token\":\"sl.t\",\"expires_in\":14400}'"
    printf '  *get_current_account*) corpo=%s ;;\n' "'{\"account_id\":\"dbid:CONTA\"}'"
    printf '  *list_folder*) corpo=$(cat "$base/listagem") ;;\n'
    printf '  *files/download*) corpo=$(cat "$base/conteudo_remoto") ;;\n'
    printf '  *upload_session/start*) corpo=%s ;;\n' "'{\"session_id\":\"S-1\"}'"
    printf '  *upload_session/append_v2*) corpo=%s ;;\n' "'{}'"
    printf '  *) corpo=%s ;;\n' "'{\"name\":\"x\",\"rev\":\"1\"}'"
    printf 'esac\n'
    # RF-136: o lote de exclusao do `--espelhar` (delete_batch + check) responde
    # aqui; cada item confirmado e ecoado em `chamadas` como `files/delete_v2`.
    cat <<'LOTE'
LOTE_ECOA_V2=sim
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "$corpo_arquivo" || :
LOTE
    # Conflito de rev (RF-49): o envio cujo argumento cita o caminho marcado e
    # recusado como a Dropbox recusa, com 409 e tag `conflict`.
    printf 'if [[ $url == *files/upload && -f "$base/upload_conflito" && $conf == *"$(cat "$base/upload_conflito")"* ]]; then\n'
    printf '  codigo=409; corpo=%s\n' "'{\"error_summary\":\"path/conflict/file/..\"}'"
    printf 'fi\n'
    printf 'if [[ $url == *files/download* && -n $cabecalhos && -f "$base/resultado_cabecalho" ]]; then\n'
    printf '  printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"\n'
    printf 'fi\n'
    # RF-59: token e erros por tipo de item; RNF-31: sinal ao grupo do processo
    # quando a URL casa, so seguro sob `setsid` (ver `_rodar_em_sessao`).
    cat <<'FIM'
if [[ $url == *oauth2/token* && -f "$base/token" ]]; then
  corpo="{\"access_token\":\"$(cat "$base/token")\",\"expires_in\":14400}"
fi
# RF-52(a): a identificacao da conta falha, sem retentativa (400).
if [[ $url == *get_current_account* && -f "$base/conta_falha" ]]; then
  codigo=400; corpo='{"error_summary":"other/"}'
fi
# QA-P3-03: a enumeracao remota responde com o codigo e o corpo dados.
if [[ $url == *list_folder* && -f "$base/listagem_codigo" ]]; then
  codigo=$(cat "$base/listagem_codigo")
fi
for tipo in upload:files/upload download:files/download delete:files/delete_v2; do
  if [[ $url == *"${tipo#*:}" && -f "$base/${tipo%%:*}_erro" ]]; then
    codigo=$(cat "$base/${tipo%%:*}_erro")
    corpo=$(cat "$base/erro_corpo")
  fi
done
# RF-137: dois ou mais pequenos vao por `upload_session/start` (lote); o erro de
# envio dado e o mesmo nessa rota, para o item falhar com a mesma classe e resumo.
if [[ $url == *upload_session/start && -f "$base/upload_erro" ]]; then
  codigo=$(cat "$base/upload_erro")
  corpo=$(cat "$base/erro_corpo")
fi
# TC-PRG-05: o que ja estava em stderr quando chegou a primeira requisicao de conteudo.
if [[ $url == *files/download* || $url == *files/upload ]]; then
  [[ -f "$base/err_na_requisicao" ]] || cp "$base/err" "$base/err_na_requisicao" 2>/dev/null
fi
# TC-PRG-18: para onde aponta o fd 2 de quem chamou o curl (o auxiliar tem /dev/null).
if [[ $url == *files/download* && -f "$base/audita_fd2" ]]; then
  # lib/http redireciona o stderr do curl a um arquivo proprio; sobe ate o primeiro
  # ancestral cujo fd 2 nao e esse arquivo.
  pai=$PPID
  while :; do
    alvo_fd2=$(readlink "/proc/$pai/fd/2")
    [[ $alvo_fd2 == */erro_cliente ]] || break
    pai=$(awk '{print $4}' "/proc/$pai/stat")
  done
  printf '%s\n' "$alvo_fd2" >>"$base/fd2"
fi
# TC-PRG-24: o download do caminho dado vem como pasta (409 not_file).
if [[ $url == *files/download* && -f "$base/download_pasta" && $conf == *"$(cat "$base/download_pasta")"* ]]; then
  codigo=409; corpo='{"error_summary":"path/not_file/.."}'
fi
# TC-PRG-07: o N-esimo append_v2 recusa (N em append_falha).
if [[ $url == *upload_session/append_v2 && -f "$base/append_falha" ]]; then
  printf x >>"$base/appends"
  if [[ $(wc -c <"$base/appends") -eq $(cat "$base/append_falha") ]]; then
    codigo=400; corpo='{"error_summary":"other/.."}'
  fi
fi
# Ciclo 2: metadados, falha so de um arquivo e .part que cresce no download.
if [[ $url == *get_metadata* && -f "$base/meta" ]]; then corpo=$(cat "$base/meta"); fi
if [[ $url == *files/download && -f "$base/download_erro_so" && $conf == *"$(cat "$base/download_erro_so")"* ]]; then
  codigo=404; corpo='{"error_summary":"path/not_found/.."}'
fi
if [[ $url == *files/download && -f "$base/cresce" && -n $saida ]]; then
  : >"$saida"
  for ((n = 0; n < $(cat "$base/cresce"); n++)); do
    head -c 1048576 /dev/zero | tr '\0' x >>"$saida"
    sleep 0.3
  done
  [[ -n $escrever ]] && printf 200
  exit 0
fi
# Progresso em bloco (F-49, RF-143): atraso no download e espia do canal de status.
if [[ -f "$base/atraso" && $url == *files/download* ]]; then
  if [[ -f "$base/espia" ]]; then
    : >>"$base/espia_saida"
    for f in $(find "$TMPDIR" -path '*/paralelo/st.*' -type f ! -name '*.parte' 2>/dev/null); do
      printf '%s %s\n' "$f" "$(stat -c %a "$(dirname "$f")")" >>"$base/espia_saida"
    done
  fi
  sleep "$(cat "$base/atraso")"
fi
if [[ -f "$base/sinal" && $url == *"$(cat "$base/sinal_url")"* ]]; then
  [[ -f "$base/sinal_espera" ]] && sleep "$(cat "$base/sinal_espera")"
  if [[ -f "$base/sinal_sessao" ]]; then
    kill -s "$(cat "$base/sinal")" -- "-$(awk '{print $6}' /proc/$$/stat)"
  else
    kill -s "$(cat "$base/sinal")" 0
  fi
  sleep 5
fi
FIM
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  # RNF-02, TC-DEP-03: sentinelas no lugar de `sqlite3` e `python3`.
  local proibido
  for proibido in sqlite3 python3 python; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>%q\nexit 1\n' \
      "$proibido" "$base/proibido" >"$base/bin/$proibido"
    chmod +x "$base/bin/$proibido"
  done
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_entrada_remota() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s}' "$1" "$2" "$3"
}

# _prg_local <base> <nome> <bytes> — arquivo local sintetico.
_prg_local() {
  head -c "$3" /dev/zero | tr '\0' 'x' >"$1/local/$2"
}

# O ambiente de teste roda com `env -i`: sem locale UTF-8 a barra usa `#` e `-`,
# entao os casos olham o percentual e os bytes, que independem do locale.

teste_sync_enviar_mostra_linha_do_arquivo_de_0_a_100() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "envio deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[1/1] enviando: a.txt [' "$DBX_ERRO" 'TC-PRG-23: [i/N] e acao'
  assert_contem '0% 0 B / 15 B' "$DBX_ERRO" 'RF-141(a): inicia em 0%'
  assert_contem '100% 15 B / 15 B' "$DBX_ERRO" 'RF-140(f): termina em 100%'
  assert_nao_contem $'\r' "$DBX_ERRO" 'RF-142(b): sem retorno de carro sem terminal'
}

teste_sync_enviar_em_lote_mostra_posicao_no_plano() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 10
  _prg_local "$base" b.txt 20
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "envio deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[1/2] enviando: a.txt [' "$DBX_ERRO" 'TC-PRG-02: primeiro do plano'
  assert_contem '[2/2] enviando: b.txt [' "$DBX_ERRO" 'TC-PRG-02: segundo do plano'
  assert_contem '100% 20 B / 20 B' "$DBX_ERRO" 'DIV-291: o lote chega a 100% ao confirmar'
}

teste_sync_receber_mostra_linha_com_total_da_listagem() {
  local base
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 15)" >"$base/listagem"
  _rodar "$base" --progresso sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[1/1] baixando: a.txt [' "$DBX_ERRO" 'TC-PRG-23: baixando com [i/N]'
  assert_contem '0% 0 B / 15 B' "$DBX_ERRO" 'DIV-297: total da listagem, em 0%'
  assert_contem '100% 15 B / 15 B' "$DBX_ERRO" 'RF-140(f): 100% ao concluir'
}

teste_sync_stdout_igual_com_e_sem_progresso() {
  local base_a base_b saida_a saida_b estado_a
  base_a=$(_cenario)
  base_b=$(_cenario)
  _prg_local "$base_a" a.txt 15
  _prg_local "$base_b" a.txt 15
  _rodar "$base_a" --json sync --enviar --origem "$base_a/local" --destino /r
  saida_a=${DBX_SAIDA//"$base_a"/BASE}
  estado_a=$DBX_ESTADO
  _rodar "$base_b" --progresso --json sync --enviar --origem "$base_b/local" --destino /r
  saida_b=${DBX_SAIDA//"$base_b"/BASE}
  assert_igual "$saida_a" "$saida_b" 'RF-145(a): stdout igual com e sem progresso'
  assert_igual "$estado_a" "$DBX_ESTADO" 'RF-145(b): codigo de saida igual'
}

teste_sync_sem_progresso_e_sem_terminal_nao_emite_linha_de_arquivo() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "envio deve concluir; diagnostico: $DBX_ERRO"
  assert_nao_contem 'enviando:' "$DBX_ERRO" 'TC-PRG-14: nenhuma linha de progresso'
}

teste_sync_dry_run_nao_emite_linha_por_arquivo() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  _rodar "$base" --progresso --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_nao_contem 'enviando: a.txt' "$DBX_ERRO" 'DIV-285: simulacao sem linha por arquivo'
}

teste_sync_enviar_com_falha_deixa_ultimo_percentual_e_falhou() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  printf '409' >"$base/upload_erro"
  printf '%s' '{"error_summary":"path/conflict/file/.."}' >"$base/erro_corpo"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_contem '[1/1] enviando: a.txt [' "$DBX_ERRO" 'TC-PRG-32: a linha existe'
  assert_contem ' falhou' "$DBX_ERRO" 'RF-146(b): sufixo falhou'
  assert_nao_contem '100% 15 B / 15 B' "$DBX_ERRO" 'RF-146(a): nunca forja 100%'
  assert_status 0 test "$DBX_ESTADO" -ne 0
}

teste_upload_simples_tem_so_zero_e_cem() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  _rodar "$base" --progresso upload "$base/local/a.txt" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem "[1/1] enviando: $base/local/a.txt [" "$DBX_ERRO" 'TC-PRG-21: linha do upload'
  assert_contem '0% 0 B / 15 B' "$DBX_ERRO" 'TC-PRG-08: 0%'
  assert_contem '100% 15 B / 15 B' "$DBX_ERRO" 'TC-PRG-08: 100%'
  assert_igual 2 "$(grep -c 'enviando:' "$base/err")" 'TC-PRG-08: sem valor intermediario'
}

teste_upload_com_falha_termina_a_linha_com_falhou() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  printf '409' >"$base/upload_erro"
  printf '%s' '{"error_summary":"path/conflict/file/.."}' >"$base/erro_corpo"
  _rodar "$base" --progresso upload "$base/local/a.txt" /r/a.txt
  assert_contem ' falhou' "$DBX_ERRO" 'TC-PRG-31: sufixo falhou'
  assert_status 0 test "$DBX_ESTADO" -ne 0
}

teste_upload_em_sessao_avanca_por_parte_sem_linha_de_parte() {
  local base
  base=$(_cenario)
  truncate -s 151M "$base/local/grande.bin"
  _rodar "$base" --progresso upload "$base/local/grande.bin" /r/grande.bin
  assert_igual 0 "$DBX_ESTADO" "upload em sessao deve concluir; diagnostico: $DBX_ERRO"
  assert_nao_contem 'enviada' "$DBX_ERRO" 'TC-PRG-34: sem linha de parte'
  assert_contem '0% 0 B / 151 MiB' "$DBX_ERRO" 'TC-PRG-06: inicia em 0%'
  assert_contem '100% 151 MiB / 151 MiB' "$DBX_ERRO" 'TC-PRG-06: termina em 100%'
  [[ $(grep -c 'enviando:' "$base/err") -ge 4 ]] || assert_igual 'varias linhas' 'poucas' 'TC-PRG-13: uma linha por parte'
  local linha pct_ant=-1
  while IFS= read -r linha; do
    [[ $linha =~ \ ([0-9]+)%\  ]] || continue
    [[ ${BASH_REMATCH[1]} -ge $pct_ant ]] || _harness_falhar "RF-140(g): o percentual diminuiu: $linha"
    pct_ant=${BASH_REMATCH[1]}
  done < <(grep 'enviando:' "$base/err")
}

teste_download_mostra_linha_e_conclui_em_cem() {
  local base
  base=$(_cenario)
  _meta_arquivo "$base"
  _rodar "$base" --progresso download /r/a.txt "$base/local/b.txt"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[1/1] baixando: /r/a.txt' "$DBX_ERRO" 'TC-PRG-21: linha do download'
  assert_contem '100% 15 B / 15 B' "$DBX_ERRO" 'RF-141(e): 100% so ao concluir'
  assert_nao_contem 'baixando:' "$DBX_SAIDA" 'stdout livre de progresso'
}

teste_download_para_stdout_nao_emite_progresso() {
  local base
  base=$(_cenario)
  _rodar "$base" --progresso download /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_nao_contem 'baixando:' "$DBX_ERRO" 'TC-PRG-22: sem linha para stdout'
  assert_igual 'conteudo remoto' "$DBX_SAIDA" 'TC-PRG-22: stdout so o conteudo'
}


# ---------------------------------------------------------------------------
# Paralelo (N > 1): bloco de linhas, canal de status e sinal (RF-143, RF-142(e);
# TC-PRG-14 a 20; DIV-289, DIV-290)
# ---------------------------------------------------------------------------

_remoto3() { # <base>
  printf '{"entries":[%s,%s,%s],"has_more":false}' "$(_entrada_remota /r/a.txt ff 15)" \
    "$(_entrada_remota /r/b.txt ff 15)" "$(_entrada_remota /r/c.txt ff 15)" >"$1/listagem"
}

# _rodar_t <base> <sim|nao> <argumentos...> — com a semente de terminal.
_rodar_t() {
  local base=$1 terminal=$2
  shift 2
  mkdir -p "$base/tmp"
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_PROGRESS_TERMINAL="$terminal" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _rodar_sessao_t — sessao propria, para o sinal ao grupo nao alcancar a suite.
_rodar_sessao_t() {
  local base=$1 terminal=$2
  shift 2
  mkdir -p "$base/tmp"
  DBX_SAIDA=''
  DBX_ERRO=''
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_PROGRESS_TERMINAL="$terminal" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_contar() { # <trecho> <texto>
  local resto=${2//"$1"/}
  printf '%s' "$((( ${#2} - ${#resto} ) / ${#1}))"
}

teste_paralelo_terminal_redesenha_bloco_e_deixa_linhas_finais() {
  local base ultimo
  base=$(_cenario)
  _remoto3 "$base"
  printf 1 >"$base/atraso"
  _rodar_t "$base" sim --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_contem $'\033[3A' "$DBX_ERRO" 'RF-143(a): o bloco de 3 linhas e redesenhado subindo o cursor'
  assert_contem $'\r[1/3] baixando: a.txt [' "$DBX_ERRO" 'RF-143(a): linha do primeiro com retorno de carro'
  assert_contem '[3/3] baixando: c.txt [' "${DBX_ERRO%%100% 15 B*}" 'RF-143(a): os tres ativos antes do primeiro 100%'
  assert_igual 3 "$(_contar '100% 15 B / 15 B' "$DBX_ERRO")" 'RF-143(b): uma linha final por arquivo'
  ultimo=${DBX_ERRO##*$'\033['[0-9]A}
  assert_nao_contem ' 0% 0 B / 15 B' "$ultimo" 'RF-143(c): nenhum resto de bloco ativo na tela'
}

teste_paralelo_sem_terminal_uma_linha_nova_por_atualizacao_com_posicao() {
  local base
  base=$(_cenario)
  _remoto3 "$base"
  printf 1 >"$base/atraso"
  _rodar_t "$base" nao --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_nao_contem $'\r' "$DBX_ERRO" 'DIV-289: sem retorno de carro sem terminal'
  assert_nao_contem $'\033' "$DBX_ERRO" 'DIV-289: sem sequencia de controle sem terminal'
  assert_igual 3 "$(_contar ' 0% 0 B / 15 B' "$DBX_ERRO")" 'DIV-289: uma linha inicial por arquivo, com [i/N]'
  assert_contem '[2/3] baixando: b.txt [' "$DBX_ERRO" 'DIV-289: o [i/N] acompanha a linha'
  assert_igual 3 "$(_contar '100% 15 B / 15 B' "$DBX_ERRO")" 'DIV-289: uma linha final por arquivo'
}

teste_paralelo_stdout_estado_e_cache_iguais_a_n1_e_a_sem_progresso() {
  local a b c ref saida estado
  a=$(_cenario) && b=$(_cenario) && c=$(_cenario)
  _remoto3 "$a" && _remoto3 "$b" && _remoto3 "$c"
  _rodar_t "$a" nao --json sync --receber --origem /r --destino "$a/local"
  ref=${DBX_SAIDA//"$a"/BASE}
  estado=$DBX_ESTADO
  _rodar_t "$b" nao --json sync --receber --origem /r --destino "$b/local" --paralelo 3
  assert_igual "$ref" "${DBX_SAIDA//"$b"/BASE}" 'RF-145(a): stdout de N=3 igual ao de N=1'
  assert_igual "$estado" "$DBX_ESTADO" 'RF-145(b): codigo de saida igual'
  _rodar_t "$c" sim --progresso --json sync --receber --origem /r --destino "$c/local" --paralelo 3
  assert_igual "$ref" "${DBX_SAIDA//"$c"/BASE}" 'RF-145(a): stdout de N=3 com progresso igual ao de N=1'
  assert_igual "$estado" "$DBX_ESTADO" 'RF-145(b): codigo de saida igual com progresso'
  # O nome do arquivo de memoria leva um resumo do caminho do caso; o formato e comparado sem ele.
  assert_igual "$(find "$a/estado" -type f -printf '%P\n' | sed 's/-[0-9a-f]\{32\}$//' | sort)" \
    "$(find "$c/estado" -type f -printf '%P\n' | sed 's/-[0-9a-f]\{32\}$//' | sort)" \
    'RF-139: o cache gravado e o mesmo com e sem progresso'
}

teste_paralelo_canal_de_status_so_com_progresso_ativo_e_em_diretorio_privado() {
  local base
  base=$(_cenario)
  _remoto3 "$base"
  printf 1 >"$base/atraso"
  : >"$base/espia"
  _rodar_t "$base" nao sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual '' "$(cat "$base/espia_saida")" 'RF-145(c): progresso inativo nao cria arquivo de status'
  rm -rf "$base/local" "$base/espia_saida"
  _rodar_t "$base" nao --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_contem '/paralelo/st.' "$(cat "$base/espia_saida")" 'DIV-290: um arquivo de status por item na area do ciclo'
  assert_contem ' 700' "$(cat "$base/espia_saida")" 'DIV-290: diretorio do canal com modo 0700'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'RNF-38(c): nada resta no temporario depois'
}

teste_paralelo_falha_fecha_a_linha_com_falhou_e_nao_deixa_orfaos() {
  local base
  base=$(_cenario)
  _remoto3 "$base"
  printf 404 >"$base/download_erro"
  printf '%s' '{"error_summary":"path/not_found/.."}' >"$base/erro_corpo"
  _rodar_t "$base" nao --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_diferente 0 "$DBX_ESTADO" 'falha do arquivo e falha do comando'
  assert_igual 3 "$(_contar ' falhou' "$DBX_ERRO" )" 'RF-146: cada linha de falha termina em falhou'
  assert_contem 'baixando: a.txt [' "$DBX_ERRO" 'a linha da falha mantem o [i/N]'
  pgrep -f -- "$base" >/dev/null && _harness_falhar 'processo orfao depois da falha'
  return 0
}

teste_int_com_n1_fecha_a_linha_com_quebra_de_linha() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  printf INT >"$base/sinal"
  printf files/upload >"$base/sinal_url"
  _rodar_sessao_t "$base" sim --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_contem '[1/1] enviando: a.txt [' "$DBX_ERRO" 'TC-PRG-15: a linha foi aberta'
  [[ $DBX_ERRO == *$'\n' ]] || _harness_falhar 'TC-PRG-15: a linha em curso nao terminou em quebra de linha'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area resta'
}

teste_int_com_n3_fecha_o_bloco_e_nao_deixa_orfaos() {
  local base
  base=$(_cenario)
  _remoto3 "$base"
  printf INT >"$base/sinal"
  printf files/download >"$base/sinal_url"
  printf 1 >"$base/sinal_espera"
  : >"$base/sinal_sessao"
  _rodar_sessao_t "$base" sim --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_contem '[3/3] baixando: c.txt [' "$DBX_ERRO" 'TC-PRG-15: o bloco foi desenhado'
  [[ $DBX_ERRO == *$'\n'* && ${DBX_ERRO: -1} == $'\n' ]] || _harness_falhar 'TC-PRG-15: o bloco nao terminou em quebra de linha'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area resta'
  pgrep -f -- "$base" >/dev/null && _harness_falhar 'processo orfao depois do sinal'
  return 0
}


# ---------------------------------------------------------------------------
# Ciclo 2: download (pasta, falha, .part que cresce), segredo, falha parcial e
# equivalencia com a base (TC-PRG-10, 28, 33, 35; DIV-294)
# ---------------------------------------------------------------------------

teste_download_de_pasta_com_progresso_nao_imprime_falhou() {
  local base
  base=$(_cenario)
  printf 409 >"$base/download_erro"
  printf '%s' '{"error_summary":"path/not_file/.."}' >"$base/erro_corpo"
  _rodar_t "$base" sim --progresso download /r "$base/local/"
  assert_nao_contem ' falhou' "$DBX_ERRO" 'o remoto e pasta: a linha de arquivo nao falhou'
}

teste_download_com_falha_do_servidor_termina_em_falhou_sem_cem() {
  local base
  base=$(_cenario)
  printf 404 >"$base/download_erro"
  printf '%s' '{"error_summary":"path/not_found/.."}' >"$base/erro_corpo"
  _meta_arquivo "$base"
  _rodar_t "$base" nao --progresso download /r/a.txt "$base/local/a.txt"
  assert_diferente 0 "$DBX_ESTADO" 'falha do servidor e falha do comando'
  assert_contem ' falhou' "$DBX_ERRO" 'RF-146: a linha termina em falhou'
  assert_nao_contem '100%' "$DBX_ERRO" 'RF-140(f): sem 100% numa falha'
}

_meta_grande() { # <base> — metadados de arquivo de 8 MiB
  printf '{".tag":"file","size":8388608,"rev":"0123456789a","content_hash":"%s"}' \
    "$H64A" >"$1/meta"
  printf 8 >"$1/cresce"
}

teste_download_grande_amostra_o_part_e_chega_a_cem_ao_fim_sem_orfaos() {
  local base ultima
  base=$(_cenario)
  _meta_grande "$base"
  _rodar_t "$base" nao --progresso download /r/a.txt "$base/local/a.txt"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  [[ $(_contar 'baixando: ' "$DBX_ERRO") -ge 4 ]] || _harness_falhar "TC-PRG-10: o observador do .part nao amostrou: $DBX_ERRO"
  ultima=${DBX_ERRO##*baixando: }
  assert_contem '100% 8 MiB / 8 MiB' "$ultima" 'TC-PRG-10: termina em 100%'
  assert_igual 1 "$(_contar '100% 8 MiB / 8 MiB' "$DBX_ERRO")" 'TC-PRG-10: 100% uma unica vez, no fim'
  pgrep -f -- "$base" >/dev/null && _harness_falhar 'processo orfao depois do download'
  return 0
}

teste_download_grande_com_hash_divergente_nao_chega_a_cem() {
  local base
  base=$(_cenario)
  _meta_grande "$base"
  printf '{"name":"a.txt","content_hash":"%s"}' "$H64B" >"$base/resultado_cabecalho"
  _rodar_t "$base" nao --progresso download /r/a.txt "$base/local/a.txt"
  assert_diferente 0 "$DBX_ESTADO" 'hash divergente e falha'
  assert_nao_contem '100%' "$DBX_ERRO" 'TC-PRG-10: o 100% so vem apos a conferencia do content_hash'
  assert_contem ' falhou' "$DBX_ERRO" 'a linha termina em falhou'
  pgrep -f -- "$base" >/dev/null && _harness_falhar 'processo orfao depois da falha'
  return 0
}

teste_nenhum_segredo_aparece_na_saida_de_progresso() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  printf 'SENTINELA-ACESSO-9Z' >"$base/token"
  sed -i 's/"rt"/"SENTINELA-REFRESH-9Z"/' "$base/config/dbx/credencial.json"
  _rodar_t "$base" sim --progresso sync --enviar --origem "$base/local" --destino /r
  assert_contem '[1/1] enviando: a.txt [' "$DBX_ERRO" 'a linha foi emitida'
  assert_nao_contem 'SENTINELA' "$DBX_ERRO" 'TC-PRG-28: nenhum token em stderr (envio)'
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/b.txt' 'ff' 15)" >"$base/listagem"
  _rodar_t "$base" sim --progresso sync --receber --origem /r --destino "$base/local2"
  assert_contem 'baixando: b.txt [' "$DBX_ERRO" 'a linha foi emitida'
  assert_nao_contem 'SENTINELA' "$DBX_ERRO" 'TC-PRG-28: nenhum token em stderr (recebimento)'
}

teste_paralelo_falha_de_um_arquivo_nao_derruba_os_demais_e_iguala_n1() {
  local base1 base3 estado1
  base1=$(_cenario) && base3=$(_cenario)
  _remoto3 "$base1" && _remoto3 "$base3"
  printf b.txt >"$base1/download_erro_so"
  printf b.txt >"$base3/download_erro_so"
  _rodar_t "$base1" nao --progresso sync --receber --origem /r --destino "$base1/local"
  estado1=$DBX_ESTADO
  _rodar_t "$base3" nao --progresso sync --receber --origem /r --destino "$base3/local" --paralelo 3
  assert_diferente 0 "$DBX_ESTADO" 'a falha de um arquivo e falha do comando'
  assert_igual "$estado1" "$DBX_ESTADO" 'TC-PRG-33: codigo de saida igual ao de N=1'
  assert_igual 1 "$(_contar ' falhou' "$DBX_ERRO")" 'TC-PRG-33: so a linha do arquivo que falhou termina em falhou'
  assert_contem 'baixando: b.txt ' "$DBX_ERRO" 'a linha de b.txt existe'
  assert_igual 2 "$(_contar '100% 15 B / 15 B' "$DBX_ERRO")" 'TC-PRG-33: os demais concluem em 100%'
}

_rodar_com() { # <executavel> <base> <argumentos...>
  local exe=$1 base=$2
  shift 2
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$exe" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

teste_sync_sem_progresso_e_sem_terminal_tem_stderr_igual_ao_da_base() {
  local a b ref
  git -C "$DBX_HARNESS_RAIZ" cat-file -e 'a39a89e^{commit}' 2>/dev/null || {
    pular 'o commit a39a89e nao existe neste clone: TC-PRG-35 compara o stderr com ele'
  }
  a=$(_cenario) && b=$(_cenario)
  mkdir -p "$a/baseline"
  git -C "$DBX_HARNESS_RAIZ" archive a39a89e | tar -x -C "$a/baseline" || _harness_falhar 'nao foi possivel extrair a base a39a89e'
  _prg_local "$a" a.txt 15 && _prg_local "$a" b.txt 20
  _prg_local "$b" a.txt 15 && _prg_local "$b" b.txt 20
  _rodar_com "$a/baseline/bin/dbx" "$a" sync --enviar --origem "$a/local" --destino /r
  ref=${DBX_ERRO//"$a"/BASE}
  _rodar_com "$DBX_EXEC" "$b" sync --enviar --origem "$b/local" --destino /r
  assert_igual "$ref" "${DBX_ERRO//"$b"/BASE}" 'TC-PRG-35: stderr identico ao da base a39a89e'
}

_meta_arquivo() { # <base> — metadados de um arquivo de 15 bytes (a linha do download so abre com eles)
  printf '{".tag":"file","size":15,"rev":"0123456789a","content_hash":"%s"}' \
    "$H64A" >"$1/meta"
}

teste_download_de_pasta_sem_terminal_nao_emite_linha_de_arquivo() {
  local base
  base=$(_cenario)
  printf 409 >"$base/download_erro"
  printf '%s' '{"error_summary":"path/not_file/.."}' >"$base/erro_corpo"
  _rodar_t "$base" nao --progresso download /r "$base/local/"
  assert_nao_contem 'baixando:' "$DBX_ERRO" 'DIV-304: pasta nao abre linha de arquivo'
  assert_nao_contem ' falhou' "$DBX_ERRO" 'DIV-304: nem falhou'
}

teste_upload_em_sessao_com_erro_na_parte_2_para_no_percentual_da_parte_1() {
  local base ultima anterior
  local -a linhas=()
  base=$(_cenario)
  truncate -s 151M "$base/local/grande.bin"
  printf 2 >"$base/append_falha"
  _rodar "$base" --progresso upload "$base/local/grande.bin" /r/grande.bin
  assert_diferente 0 "$DBX_ESTADO" 'a parte recusada e falha do comando'
  assert_nao_contem '100%' "$DBX_ERRO" 'TC-PRG-07: sem 100% numa falha'
  mapfile -t linhas < <(grep 'enviando:' "$base/err")
  ultima=${linhas[-1]}
  anterior=${linhas[-2]}
  assert_contem ' falhou' "$ultima" 'TC-PRG-07: a ultima linha termina em falhou'
  assert_nao_contem ' 0% ' "$ultima" 'TC-PRG-07: a parte 1 ja tinha avancado'
  assert_igual "$anterior" "${ultima% falhou}" 'RF-141(b): a falha fica no maior percentual emitido (o da parte 1)'
}

teste_lote_com_uma_entrada_em_erro_no_finish_falha_so_a_linha_dela() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 10 && _prg_local "$base" b.txt 10 && _prg_local "$base" c.txt 10
  mkdir -p "$base/lote/envio_falha"
  : >"$base/lote/envio_falha/b.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'a entrada recusada e falha do comando'
  assert_igual 2 "$(_contar '100% 10 B / 10 B' "$DBX_ERRO")" 'TC-PRG-09: duas chegam a 100%'
  assert_igual 1 "$(_contar ' falhou' "$DBX_ERRO")" 'TC-PRG-09: so uma termina em falhou'
  assert_contem '0% 0 B / 10 B falhou' "$DBX_ERRO" 'TC-PRG-09: a recusada fica em 0% com falhou'
}

teste_download_com_metadado_de_hash_invalido_abre_a_linha_do_arquivo() {
  local base
  base=$(_cenario)
  printf '{".tag":"file","size":15,"rev":"0123456789a","content_hash":"fora-do-formato"}' >"$base/meta"
  _rodar_t "$base" nao --progresso download /r/a.txt "$base/local/a.txt"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[1/1] baixando: /r/a.txt' "$DBX_ERRO" 'DIV-306: .tag=file e o unico criterio para abrir a linha'
  assert_contem '100%' "$DBX_ERRO" 'a linha conclui'
}

teste_linha_zero_sai_antes_da_primeira_requisicao_de_conteudo() {
  local base
  base=$(_cenario)
  _prg_local "$base" a.txt 15
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_contem '0% 0 B / 15 B' "$(cat "$base/err_na_requisicao")" 'TC-PRG-05: 0% antes do envio do conteudo'
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 15)" >"$base/listagem"
  _rodar "$base" --progresso sync --receber --origem /r --destino "$base/local"
  assert_contem '0% 0 B / 15 B' "$(cat "$base/err_na_requisicao")" 'TC-PRG-05: 0% antes do download do conteudo'
}

teste_com_paralelo_so_o_processo_principal_escreve_em_stderr() {
  local base
  base=$(_cenario)
  _remoto3 "$base"
  : >"$base/audita_fd2"
  _rodar_t "$base" nao --progresso sync --receber --origem /r --destino "$base/local" --paralelo 3
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 3 "$(grep -c . "$base/fd2")" 'TC-PRG-18: tres downloads auditados'
  assert_igual '' "$(grep -vx '/dev/null' "$base/fd2")" 'TC-PRG-18/RF-135(a): o fd 2 dos auxiliares nao e o stderr do principal'
}

teste_upload_e_download_de_pasta_mostram_a_linha_por_arquivo_via_sync() {
  local base outro
  base=$(_cenario)
  _prg_local "$base" a.txt 15 && _prg_local "$base" b.txt 20
  _rodar_t "$base" nao --progresso upload "$base/local" /r
  assert_contem '[1/2] enviando: a.txt [' "$DBX_ERRO" 'TC-PRG-24: upload de pasta, primeiro arquivo'
  assert_contem '[2/2] enviando: b.txt [' "$DBX_ERRO" 'TC-PRG-24: upload de pasta, segundo arquivo'
  outro=$(_cenario)
  printf '{"entries":[%s,%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 15)" "$(_entrada_remota '/r/b.txt' 'ff' 20)" >"$outro/listagem"
  # No config do curl o argumento vem escapado: o fim do caminho e `\"}`.
  printf '%s' '/r\"}' >"$outro/download_pasta"
  _rodar_t "$outro" nao --progresso download /r "$outro/local/"
  assert_contem '[1/2] baixando: a.txt [' "$DBX_ERRO" 'TC-PRG-24: download de pasta, primeiro arquivo'
  assert_contem '[2/2] baixando: b.txt [' "$DBX_ERRO" 'TC-PRG-24: download de pasta, segundo arquivo'
}

teste_codigo_de_saida_cache_e_plano_iguais_com_e_sem_progresso() {
  local a b plano_a plano_b real_a real_b estado_a
  a=$(_cenario) && b=$(_cenario)
  _prg_local "$a" a.txt 15 && _prg_local "$a" b.txt 20
  _prg_local "$b" a.txt 15 && _prg_local "$b" b.txt 20
  _rodar_t "$a" nao --json --dry-run sync --enviar --origem "$a/local" --destino /r
  plano_a=${DBX_SAIDA//"$a"/BASE}
  _rodar_t "$a" nao --json sync --enviar --origem "$a/local" --destino /r
  real_a=${DBX_SAIDA//"$a"/BASE}
  estado_a=$DBX_ESTADO
  _rodar_t "$b" sim --progresso --json --dry-run sync --enviar --origem "$b/local" --destino /r
  plano_b=${DBX_SAIDA//"$b"/BASE}
  _rodar_t "$b" sim --progresso --json sync --enviar --origem "$b/local" --destino /r
  real_b=${DBX_SAIDA//"$b"/BASE}
  assert_igual "$plano_a" "$plano_b" 'TC-PRG-26: o plano e o mesmo'
  assert_igual "$real_a" "$real_b" 'TC-PRG-26: a saida e a mesma'
  assert_igual "$estado_a" "$DBX_ESTADO" 'TC-PRG-26: o codigo de saida e o mesmo'
  assert_igual "$(find "$a/estado" -type f -printf '%P\n' | sed 's/-[0-9a-f]\{32\}$//' | sort)" \
    "$(find "$b/estado" -type f -printf '%P\n' | sed 's/-[0-9a-f]\{32\}$//' | sort)" 'TC-PRG-26: o cache e o mesmo'
}

teste_ajuda_e_readme_descrevem_o_progresso_com_e_sem_terminal() {
  local base cmd texto
  base=$(_cenario)
  for cmd in upload download sync; do
    _rodar_t "$base" nao help "$cmd"
    texto="$DBX_SAIDA$DBX_ERRO"
    assert_contem '--progresso' "$texto" "TC-PRG-36: help $cmd cita --progresso"
    assert_contem 'terminal' "$texto" "TC-PRG-36: help $cmd descreve o comportamento com e sem terminal"
  done
  texto=$(cat "$DBX_HARNESS_RAIZ/README.md")
  assert_contem '--progresso' "$texto" 'TC-PRG-36: README cita --progresso'
  assert_contem '[i/N]' "$texto" 'TC-PRG-36: README descreve o formato da linha'
}

teste_mensagens_de_analise_do_sync_neutralizam_controles_no_nome() {
  local base nome
  base=$(_cenario)
  printf -v nome 'a\033[31m\ab.txt'
  _prg_local "$base" "$nome" 15
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_contem '[sync] analise [1/1]: a?[31m?b.txt' "$DBX_ERRO" 'QA-B10-01: a mensagem de analise mostra o nome com controles trocados por ?'
  assert_nao_contem $'\033' "$DBX_ERRO" 'QA-B10-01: nenhum ESC cru em stderr'
  assert_nao_contem $'\a' "$DBX_ERRO" 'QA-B10-01: nenhum BEL cru em stderr'
}
harness_executar "$@"
