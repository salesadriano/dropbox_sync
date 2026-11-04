#!/usr/bin/env bash
# Suite independente do QA: relatorio final do `sync` com tamanho e motivo por
# arquivo (RF-208 a-f; RF-59(b) e (d); demanda `relatorio-com-tamanho-e-motivo`).
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx` e com duplo de `curl`
# proprio. `DBX_QA_EXEC` aponta outro `bin/dbx` (a base, para provar o vermelho).
#
# Foco: fronteiras de unidade ponta a ponta, falha de download com classe e
# motivo, ciclos por bloco, paralelo, simulacao, nome com controle, o par de
# RF-59(b) intacto e a contagem das linhas contra os contadores.
#
# shellcheck disable=SC2016
# Justificativa: o roteiro do duplo de rede chega sem expansao.
#
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

Q_DBX=${DBX_QA_EXEC:-$DBX_HARNESS_RAIZ/bin/dbx}
readonly Q_DBX

# _q_cen — credencial, duplo de rede e arvore local; o cenario fica em `B`.
_q_cen() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-relfinal.XXXXXX")
  mkdir -p "$B/config/dbx" "$B/bin" "$B/local"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$B/config/dbx/credencial.json"
  chmod 700 "$B/config/dbx"
  chmod 600 "$B/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$B/listagem"
  printf '%s' 'conteudo remoto' >"$B/conteudo_remoto"
  : >"$B/chamadas"
  {
    printf '#!/usr/bin/env bash\nbase=%q\nDBX_HARNESS_RAIZ=%q\n' "$B" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida=""; escrever=""; anterior=""; url=""; corpo_arquivo=""; cabecalhos=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *files/download*) corpo=$(cat "$base/conteudo_remoto") ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
LOTE_ECOA_V2=sim
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "$corpo_arquivo" || :
# O download cujo argumento cita a marca falha com 409 (nao ha retentativa).
if [[ $url == *files/download* && -s "$base/download_falha" && $conf == *"$(cat "$base/download_falha")"* ]]; then
  codigo=409; corpo='{"error_summary":"path/not_found/.."}'
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$B/bin/curl"
  chmod +x "$B/bin/curl"
}

# _q_remota <caminho_remoto> <tamanho> — acrescenta uma entrada a listagem.
_q_remota() {
  local atual
  atual=$(cat "$B/listagem")
  atual=${atual#'{"entries":['}
  atual=${atual%'],"has_more":false}'}
  printf '{"entries":[%s%s{".tag":"file","path_display":"%s","content_hash":"ff","size":%s}],"has_more":false}' \
    "$atual" "${atual:+,}" "$1" "$2" >"$B/listagem"
}

_q_rodar() {
  SAIDA='' ERRO=''
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/config" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$DBX_TESTES_TMP" timeout 120 bash "$Q_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  ESTADO=$?
  [[ -r $B/out ]] && IFS= read -r -d '' SAIDA <"$B/out"
  [[ -r $B/err ]] && IFS= read -r -d '' ERRO <"$B/err"
  return 0
}

# _q_n <prefixo> — linhas da saida que comecam por `prefixo=`, em Q_CONT.
_q_n() {
  local linha n=0
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && n=$((n + 1))
  done <<<"$SAIDA"
  Q_CONT=$n
}

# _q_campo <chave> — valor numerico do contador `chave=` da saida, em Q_VAL.
_q_campo() {
  local linha
  Q_VAL=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && Q_VAL=${linha#*=}
  done <<<"$SAIDA"
}

# _q_conferir_contagem — enviado+recebido+falha == enviados+recebidos+falhas.
_q_conferir_contagem() { # <rotulo>
  local linhas contadores
  _q_n enviado
  linhas=$Q_CONT
  _q_n recebido
  linhas=$((linhas + Q_CONT))
  _q_n falha
  linhas=$((linhas + Q_CONT))
  _q_campo enviados
  contadores=$Q_VAL
  _q_campo recebidos
  contadores=$((contadores + Q_VAL))
  _q_campo falhas
  contadores=$((contadores + Q_VAL))
  assert_igual "$contadores" "$linhas" "$1: uma linha por arquivo, igual a enviados+recebidos+falhas"
}

teste_qa_relfinal_fronteiras_de_unidade_ponta_a_ponta_pelo_relatorio() {
  # RF-208(a): decimal (1 KB = 1000 B), uma casa por truncamento, B abaixo de 1000,
  # teto em TB. Tamanho vindo do `size` da listagem, de download que falha.
  local par
  _q_cen
  for par in f999:999 f1000:1000 f1999:1999 f999999:999999 f1000000:1000000 f1gb:1000000000 f1tb:1000000000000 f1000tb:1000000000000000; do
    _q_remota "/r/${par%%:*}.bin" "${par#*:}"
  done
  printf '%s' '.bin' >"$B/download_falha"
  _q_rodar sync --receber --origem /r --destino "$B/local"
  assert_contem 'falha=f999.bin (999 B): ' "$SAIDA" '999 B fica em bytes'
  assert_contem 'falha=f1000.bin (1.0 KB): ' "$SAIDA" '1000 B ja e 1.0 KB'
  assert_contem 'falha=f1999.bin (1.9 KB): ' "$SAIDA" '1999 B trunca para 1.9 KB'
  assert_contem 'falha=f999999.bin (999.9 KB): ' "$SAIDA" '999999 B trunca e nunca vira 1000.0 KB'
  assert_contem 'falha=f1000000.bin (1.0 MB): ' "$SAIDA" '10^6 B e 1.0 MB'
  assert_contem 'falha=f1gb.bin (1.0 GB): ' "$SAIDA" '10^9 B e 1.0 GB'
  assert_contem 'falha=f1tb.bin (1.0 TB): ' "$SAIDA" '10^12 B e 1.0 TB'
  assert_contem 'falha=f1000tb.bin (1000.0 TB): ' "$SAIDA" 'o teto e TB'
  assert_nao_contem 'KiB' "$SAIDA" 'unidade decimal, nunca binaria'
}

teste_qa_relfinal_receber_com_falha_de_download_traz_classe_motivo_e_recebidos() {
  # RF-208(a)(b)(c) no --receber: o que concluiu em recebido_*, o que falhou com
  # tamanho da listagem, classe e motivo; o stderr de RF-59(a) permanece.
  _q_cen
  _q_remota /r/ok1.txt 40
  _q_remota /r/ruim.txt 1000000
  _q_remota /r/ok2.txt 40
  printf '%s' 'ruim.txt' >"$B/download_falha"
  _q_rodar --json sync --receber --origem /r --destino "$B/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$ESTADO" 'falha parcial sai como nao concluida'
  assert_contem 'falha=ruim.txt (1.0 MB): nao_encontrado path/not_found' "$SAIDA" 'tamanho, classe e motivo'
  assert_contem 'recebido=ok1.txt (15 B)' "$SAIDA" 'o que concluiu, com o tamanho gravado'
  assert_contem 'recebido=ok2.txt (15 B)' "$SAIDA" 'o segundo que concluiu'
  assert_contem $'falha_caminho=ruim.txt\nfalha_classe=nao_encontrado\nfalha_motivo=path/not_found' "$SAIDA" 'RF-59(b) intacto e com o motivo'
  assert_contem 'falha_tamanho=1000000' "$SAIDA" 'bytes da falha'
  assert_contem $'recebido_caminho=ok1.txt\nrecebido_tamanho=15' "$SAIDA" 'pares em bytes do concluido'
  assert_contem 'recebido_caminho=ok2.txt' "$SAIDA" 'todos os concluidos'
  assert_contem 'falha ruim.txt: nao_encontrado path/not_found' "$ERRO" 'RF-59(a): stderr permanece'
}

teste_qa_relfinal_ciclos_por_bloco_listam_todos_os_arquivos_na_ordem_de_conclusao() {
  # RF-208(d): --bloco 1 corta por diretorio; o relatorio final traz os arquivos
  # de todos os ciclos, uma linha cada, na ordem em que concluiram.
  local esperado linhas linha
  _q_cen
  mkdir -p "$B/local/d1" "$B/local/d2" "$B/local/d3"
  printf 'um' >"$B/local/d1/a.txt"
  printf 'doze bytes!!' >"$B/local/d2/b.txt"
  printf 'tres' >"$B/local/d3/c.txt"
  printf 'quatro' >"$B/local/d3/d.txt"
  _q_rodar --json sync --enviar --origem "$B/local" --destino /r --bloco 1
  assert_igual 0 "$ESTADO" "envio em ciclos conclui; diagnostico: $ERRO"
  _q_campo ciclos
  [[ $Q_VAL -ge 2 ]] || _harness_falhar "o cenario precisa de 2+ ciclos (ciclos=$Q_VAL)"
  assert_igual 4 "$(
    _q_n enviado
    printf '%s' "$Q_CONT"
  )" 'uma linha enviado= por arquivo, de todos os ciclos'
  linhas=''
  while IFS= read -r linha; do
    [[ $linha == enviado=* ]] && linhas+="$linha;"
  done <<<"$SAIDA"
  esperado='enviado=d1/a.txt (2 B);enviado=d2/b.txt (12 B);enviado=d3/c.txt (4 B);enviado=d3/d.txt (6 B);'
  assert_igual "$esperado" "$linhas" 'ordem de conclusao, diretorio a diretorio'
  assert_contem $'enviado_caminho=d1/a.txt\nenviado_tamanho=2' "$SAIDA" 'estruturado do primeiro ciclo'
  assert_contem $'enviado_caminho=d3/d.txt\nenviado_tamanho=6' "$SAIDA" 'estruturado do ultimo ciclo'
}

teste_qa_relfinal_paralelo_lista_tantas_linhas_quantos_enviados() {
  # RF-208(a) em --paralelo 3: nenhuma linha perdida nem duplicada.
  local i
  _q_cen
  for i in 1 2 3 4 5; do printf '%*s' "$((i * 100))" '' >"$B/local/p$i.txt"; done
  _q_rodar sync --enviar --origem "$B/local" --destino /r --paralelo 3
  assert_igual 0 "$ESTADO" "paralelo conclui; diagnostico: $ERRO"
  _q_campo enviados
  assert_igual 5 "$Q_VAL" 'cenario: 5 enviados'
  _q_n enviado
  assert_igual 5 "$Q_CONT" 'cinco linhas enviado=, nem mais nem menos'
  for i in 1 2 3 4 5; do assert_contem "enviado=p$i.txt ($((i * 100)) B)" "$SAIDA" "p$i com o tamanho"; done
}

teste_qa_relfinal_simulacao_nao_emite_linha_de_arquivo_concluido_nem_falha() {
  # RF-208(e): --dry-run nao transfere, entao nao ha enviado=/recebido=/falha=.
  _q_cen
  printf 'abc' >"$B/local/a.txt"
  # O caminho da ausencia existe: a mesma arvore, sem --dry-run, gera a linha.
  _q_rodar sync --enviar --origem "$B/local" --destino /r
  assert_contem 'enviado=a.txt (3 B)' "$SAIDA" 'controle: sem simulacao a linha existe'
  _q_cen
  printf 'abc' >"$B/local/a.txt"
  _q_rodar --dry-run sync --enviar --origem "$B/local" --destino /r
  assert_igual 0 "$ESTADO" "simulacao de envio conclui; diagnostico: $ERRO"
  _q_n enviado
  assert_igual 0 "$Q_CONT" 'dry-run de envio sem linha enviado='
  _q_n falha
  assert_igual 0 "$Q_CONT" 'dry-run de envio sem linha falha='
  _q_cen
  _q_remota /r/a.txt 5
  _q_rodar --dry-run --json sync --receber --origem /r --destino "$B/local"
  _q_n recebido
  assert_igual 0 "$Q_CONT" 'dry-run de recebimento sem linha recebido='
  assert_nao_contem 'recebido_caminho=' "$SAIDA" 'nem par estruturado'
  assert_nao_contem 'enviado_caminho=' "$SAIDA" 'nem par estruturado de envio'
}

teste_qa_relfinal_nome_com_controle_ou_quebra_de_linha_nao_cria_linha_a_mais() {
  # RF-208 com RF-59(d): o nome hostil sai escapado, uma linha por arquivo.
  local texto
  _q_cen
  printf 'a' >"$B/local/"$'x\ny.txt'
  printf 'b' >"$B/local/"$'t\tz.txt'
  printf 'c' >"$B/local/"$'e\033[31mr.txt'
  printf 'd' >"$B/local/normal.txt"
  _q_rodar sync --enviar --origem "$B/local" --destino /r
  assert_igual 0 "$ESTADO" "envio conclui; diagnostico: $ERRO"
  _q_campo enviados
  assert_igual 4 "$Q_VAL" 'cenario: 4 enviados'
  _q_n enviado
  assert_igual 4 "$Q_CONT" 'a quebra de linha do nome nao vira linha a mais'
  texto=${SAIDA//$'\033'/}
  assert_igual "$SAIDA" "$texto" 'nenhum ESC cru chega ao relatorio'
  assert_nao_contem $'x\ny.txt' "$SAIDA" 'o nome com quebra de linha sai escapado'
}

teste_qa_relfinal_json_sem_falha_nao_traz_motivo_e_com_falha_o_par_fica_colado() {
  # RF-208(c) e RF-59(b): sem falha nenhum falha_*; com falha, falha_caminho
  # seguido de falha_classe e so entao o motivo.
  local anterior linha achou=nao
  _q_cen
  printf 'abc' >"$B/local/a.txt"
  _q_rodar --json sync --enviar --origem "$B/local" --destino /r
  assert_nao_contem 'falha_motivo=' "$SAIDA" 'sem falha, nenhum falha_motivo'
  assert_nao_contem 'falha_tamanho=' "$SAIDA" 'sem falha, nenhum falha_tamanho'
  assert_nao_contem 'falha_caminho=' "$SAIDA" 'sem falha, nenhum falha_caminho'
  assert_contem $'enviado_caminho=a.txt\nenviado_tamanho=3' "$SAIDA" 'o concluido continua em bytes'
  _q_cen
  _q_remota /r/ruim.txt 7
  printf '%s' 'ruim.txt' >"$B/download_falha"
  _q_rodar --json sync --receber --origem /r --destino "$B/local"
  anterior=''
  while IFS= read -r linha; do
    if [[ $anterior == falha_caminho=* && $linha == falha_classe=* ]]; then achou=sim; fi
    anterior=$linha
  done <<<"$SAIDA"
  assert_igual sim "$achou" 'falha_caminho imediatamente seguido de falha_classe'
}

teste_qa_relfinal_linhas_de_arquivo_somam_os_contadores_em_envio_e_recebimento() {
  # RF-208(a)(b): enviado+recebido+falha == enviados+recebidos+falhas, com falha.
  _q_cen
  _q_remota /r/a.txt 10
  _q_remota /r/b.txt 20
  _q_remota /r/ruim.txt 30
  printf '%s' 'ruim.txt' >"$B/download_falha"
  _q_rodar sync --receber --origem /r --destino "$B/local"
  _q_conferir_contagem 'recebimento com falha'
  _q_cen
  printf 'a' >"$B/local/a.txt"
  printf 'bb' >"$B/local/b.txt"
  printf 'ccc' >"$B/local/c.txt"
  _q_rodar --json sync --enviar --origem "$B/local" --destino /r
  _q_conferir_contagem 'envio'
}

harness_executar "$@"
