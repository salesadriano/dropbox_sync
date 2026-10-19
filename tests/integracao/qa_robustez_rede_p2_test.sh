#!/usr/bin/env bash
# Suite independente do QA Expert para a fase P2 (robustez de rede), parte
# ponta a ponta pelo `bin/dbx`: RNF-30(c) e RNF-07(e) nos dois canais (fluxo e
# conteudo), RF-32(b) com conteudo binario grande e consumidor que fecha cedo,
# RF-59 com caminho de controle, token colado a prefixo e varias falhas no
# `--json`, e RNF-31 com sinais nos pontos que a suite do developer nao cobre.
#
# Duplo de rede proprio, binario-seguro (o conteudo do download sai por `cat`,
# nunca por `printf %s`, que perderia o byte NUL), e TMPDIR proprio por cenario
# para contar residuos sem olhar o /tmp compartilhado.
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
QA_CONSUMIDOR=$(dbx_errors_codigo_saida consumidor_encerrou)
readonly QA_USO QA_NAO_CONCLUIDA QA_CONSUMIDOR
QA_AMBIENTE=()

# _qa_cenario — credencial, duplo de `curl` e arvore local; TMPDIR proprio.
#
# Controles do duplo, por arquivo em $base:
#   listagem           corpo do list_folder
#   conteudo_remoto    bytes do download, copiados por `cat`
#   resultado_cabecalho  Dropbox-API-Result do download
#   token              access_token devolvido pela renovacao
#   falhar_envio       linhas "<trecho_do_caminho> <codigo> <error_summary>"
#   erro_<alvo>        "<codigo> <error_summary>" para download|delete
#   sinal, sinal_url   envia o sinal ao grupo quando a URL casa
#   erro_oauth_corpo   a renovacao responde 400 com este corpo
#   erro_space_corpo   get_space_usage responde 409 com este corpo
#   falhar_escrita     o download sai com 23 (erro de escrita) sem escrever nada
_qa_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-p2e.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  printf '%s' 'sl.QAtokenPadrao' >"$base/token"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%q\n' "$base"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
printf '%s\n' "$conf" >>"$base/opcoes"
saida=''; escrever=''; ant=''; url=''; cabecalhos=''; fail=nao
for arg in "$@"; do
  case $ant in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; esac
  case $arg in http*) url=$arg ;; --fail) fail=sim ;; esac
  ant=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
codigo=200; corpo=''; binario=nao
case $url in
  *oauth2/token*) corpo="{\"access_token\":\"$(cat "$base/token")\",\"expires_in\":14400}" ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *files/download*) binario=sim ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}' ;;
  *upload_session/append_v2*) corpo='{}' ;;
  # RF-67 (fase 1 do backlog): o envio consulta o espaco antes; com folga
  # folgada, a checagem nao interfere nos cenarios de rede deste arquivo.
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
if [[ $url == *files/upload && -r "$base/falhar_envio" ]]; then
  while read -r trecho cod resumo; do
    if [[ $conf == *"$trecho"* ]]; then
      codigo=$cod
      corpo="{\"error_summary\":\"$resumo\",\"eco\":\"SENTINELAcorpoQA\"}"
      break
    fi
  done <"$base/falhar_envio"
fi
for alvo in download delete; do
  if [[ $url == *"files/$alvo"* && -r "$base/erro_$alvo" ]]; then
    read -r codigo resumo <"$base/erro_$alvo"
    corpo="{\"error_summary\":\"$resumo\",\"eco\":\"SENTINELAcorpoQA\"}"
    binario=nao
  fi
done
if [[ $url == *oauth2/token* && -r "$base/erro_oauth_corpo" ]]; then
  codigo=400; corpo=$(cat "$base/erro_oauth_corpo")
fi
if [[ $url == *get_space_usage* && -r "$base/erro_space_corpo" ]]; then
  codigo=409; corpo=$(cat "$base/erro_space_corpo")
fi
if [[ $url == *files/download* && -r "$base/falhar_escrita" ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 23
fi
if [[ $url == *files/download* && -n $cabecalhos && -r "$base/resultado_cabecalho" ]]; then
  printf 'Dropbox-API-Result: %s\r\n' "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"
fi
if [[ -r "$base/sinal" && $url == *"$(cat "$base/sinal_url")"* ]]; then
  kill -s "$(cat "$base/sinal")" 0
  sleep 5
fi
if [[ $fail == sim && $codigo -ge 400 ]]; then
  [[ -n $escrever ]] && printf '%s' "$codigo"
  exit 22
fi
if [[ -n $saida ]]; then
  if [[ $binario == sim ]]; then
    if ! cat "$base/conteudo_remoto" >"$saida" 2>/dev/null; then
      [[ -n $escrever ]] && printf '%s' "$codigo"
      exit 23
    fi
  else
    printf '%s' "$corpo" >"$saida"
  fi
fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_qa_rodar() { # <base> <argumentos...> — com ambiente extra em QA_AMBIENTE (array)
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${QA_AMBIENTE[@]+"${QA_AMBIENTE[@]}"} \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_rodar_em_sessao() { # <base> <argumentos...> — o duplo pode sinalizar o grupo
  local base=$1
  shift
  DBX_ERRO=''
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_chamadas() { # <base> — quantas chamadas de rede sairam
  if [[ -r $1/chamadas ]]; then
    _harness_contar . "$1/chamadas"
  else
    printf '0'
  fi
}

_qa_linhas_de_falha() { # <texto>
  local linha
  while IFS= read -r linha; do
    [[ $linha == 'falha '* ]] && printf '%s\n' "$linha"
  done <<<"$1"
  return 0
}

_qa_linhas_com() { # <prefixo> <texto> — quantas linhas comecam pelo prefixo
  local linha total=0
  while IFS= read -r linha; do
    [[ $linha == "$1"* ]] && total=$((total + 1))
  done <<<"$2"
  printf '%s' "$total"
}

_qa_entrada() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s}' "$1" "$2" "$3"
}

_qa_resumo() { # <arquivo>
  dbx_hash_conteudo_arquivo "$1"
}

# ---------------------------------------------------------------------------
# RNF-30(c), RNF-07(e) — ajuste invalido recusado antes da rede nos dois canais
# ---------------------------------------------------------------------------

teste_qa_ajuste_invalido_no_download_para_a_saida_padrao_nao_chama_a_rede() {
  local base variavel valor
  for variavel in DBX_HTTP_CONNECT_TIMEOUT_S DBX_HTTP_VELOCIDADE_JANELA_S DBX_HTTP_VELOCIDADE_MINIMA_BPS; do
    for valor in 0 -15 quinze ''; do
      base=$(_qa_cenario)
      QA_AMBIENTE=("$variavel=$valor")
      _qa_rodar "$base" download /r/a.bin -
      assert_igual "$QA_USO" "$DBX_ESTADO" "$variavel=[$valor] no canal de fluxo e uso invalido"
      assert_igual 0 "$(_qa_chamadas "$base")" "$variavel=[$valor]: nenhuma chamada, nem a renovacao"
      assert_igual '' "$DBX_SAIDA" 'a saida padrao (o conteudo) fica vazia'
      assert_contem "$variavel" "$DBX_ERRO" 'o diagnostico nomeia a variavel'
    done
  done
  QA_AMBIENTE=()
}

teste_qa_ajuste_invalido_no_envio_nao_chama_a_rede() {
  local base valor
  for valor in 0 -1 abc ''; do
    base=$(_qa_cenario)
    printf 'x' >"$base/local/a.txt"
    QA_AMBIENTE=("DBX_HTTP_RETRY_AFTER_TETO_S=$valor")
    _qa_rodar "$base" upload "$base/local/a.txt" /r/a.txt
    assert_igual "$QA_USO" "$DBX_ESTADO" "[$valor] no canal de conteudo e uso invalido"
    assert_igual 0 "$(_qa_chamadas "$base")" "[$valor]: nenhuma chamada"
    assert_contem "[$valor]" "$DBX_ERRO" 'o diagnostico nomeia o valor'
  done
  QA_AMBIENTE=()
}

# ---------------------------------------------------------------------------
# RF-32(b) — download para a saida padrao, binario e grande, e consumidor curto
# ---------------------------------------------------------------------------

_qa_conteudo_binario() { # <base> <bytes> — conteudo com NUL garantido
  {
    printf 'A\0B\0\0C'
    head -c "$2" /dev/urandom
    printf '\0\0fim\0'
  } >"$1/conteudo_remoto"
  printf '{"name":"a.bin","content_hash":"%s"}' "$(_qa_resumo "$1/conteudo_remoto")" \
    >"$1/resultado_cabecalho"
}

teste_qa_download_sem_destino_de_binario_grande_com_nul_e_byte_a_byte() {
  local base
  base=$(_qa_cenario)
  _qa_conteudo_binario "$base" 6291456
  _qa_rodar "$base" download /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "sem destino conclui; erro: $DBX_ERRO"
  assert_sucesso cmp -s "$base/conteudo_remoto" "$base/out"
  assert_nao_contem 'integridade' "$(tail -c 200 "$base/out" | tr -d '\0')" \
    'o registro do resultado nao vai colado ao conteudo'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area temporaria resta'
}

teste_qa_download_com_hifen_e_com_json_nao_suja_a_saida_padrao() {
  local base
  base=$(_qa_cenario)
  _qa_conteudo_binario "$base" 1048576
  _qa_rodar "$base" --json download /r/a.bin -
  assert_igual 0 "$DBX_ESTADO" "destino - com --json conclui; erro: $DBX_ERRO"
  assert_sucesso cmp -s "$base/conteudo_remoto" "$base/out"
  assert_contem 'contrato=' "$DBX_ERRO" 'o registro estruturado vai para a saida de erro'
}

teste_qa_download_para_consumidor_que_fecha_cedo_termina_sem_travar() {
  local base estados
  base=$(_qa_cenario)
  _qa_conteudo_binario "$base" 8388608
  estados=$(
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      timeout 60 bash "$DBX_EXEC" download /r/a.bin - </dev/null 2>"$base/err" |
      head -c 16 >"$base/out"
    printf '%s' "${PIPESTATUS[0]}"
  )
  assert_diferente 124 "$estados" 'o comando nao trava quando o consumidor fecha'
  assert_igual "$QA_CONSUMIDOR" "$estados" 'consumidor que fecha cedo sai com o codigo proprio (OBS-01)'
  assert_igual 16 "$(wc -c <"$base/out" | tr -d ' ')" 'o consumidor recebeu o que pediu'
  assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" \
    'fluxo nunca e repetido: bytes ja entregues nao sao reemitidos'
  assert_igual 0 "$(find "$base/tmp" -mindepth 1 -name 'dbx-http*' | wc -l | tr -d ' ')" \
    'nenhuma area HTTP (com token) resta'
}

teste_qa_falha_real_de_escrita_em_arquivo_nao_vira_consumidor_encerrou() {
  # O 23 so e "consumidor encerrou" na saida padrao. Em destino de arquivo e o
  # disco que falhou, e a classe propria nao pode esconder isso.
  local base
  base=$(_qa_cenario)
  : >"$base/falhar_escrita"
  _qa_rodar "$base" download /r/a.bin "$base/local/a.bin"
  assert_diferente 0 "$DBX_ESTADO" 'falha de escrita nao e sucesso'
  assert_diferente "$QA_CONSUMIDOR" "$DBX_ESTADO" 'falha de escrita em arquivo nao e consumidor encerrado'
  assert_nao_contem 'consumidor' "$DBX_ERRO" 'o diagnostico nao culpa o consumidor'
  assert_igual '' "$(find "$base/local" -mindepth 1)" 'nem o destino nem temporario restam'
}

teste_qa_saida_padrao_sem_espaco_falha_sem_repetir() {
  # /dev/full: escrita recusada na saida padrao, sem cano nem consumidor.
  local base estado
  base=$(_qa_cenario)
  _qa_conteudo_binario "$base" 1048576
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    timeout 60 bash "$DBX_EXEC" download /r/a.bin - </dev/null >/dev/full 2>"$base/err"
  estado=$?
  assert_diferente 0 "$estado" 'escrita recusada na saida padrao nao e sucesso'
  assert_diferente 124 "$estado" 'e nao trava'
  assert_diferente "$QA_CONSUMIDOR" "$estado" \
    'saida padrao sem espaco (arquivo ou dispositivo, nao cano) nao e consumidor encerrado'
  assert_nao_contem 'consumidor' "$(cat "$base/err")" 'o diagnostico nao culpa um consumidor que nao existe'
  assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" 'nao repete o fluxo'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area resta'
}

teste_qa_conteudo_baixado_que_contem_o_token_nao_e_alterado() {
  # A mascaracao e do diagnostico, nunca dos dados: um arquivo remoto que traz o
  # valor do token sai byte a byte.
  local base
  base=$(_qa_cenario)
  printf '%s' 'sl.u.QAtokenNoConteudo123' >"$base/token"
  printf 'antes sl.u.QAtokenNoConteudo123 depois QAtokenNoConteudo123\n' >"$base/conteudo_remoto"
  printf '{"name":"a.txt","content_hash":"%s"}' "$(_qa_resumo "$base/conteudo_remoto")" \
    >"$base/resultado_cabecalho"
  _qa_rodar "$base" download /r/a.txt -
  assert_igual 0 "$DBX_ESTADO" "download conclui; erro: $DBX_ERRO"
  assert_sucesso cmp -s "$base/conteudo_remoto" "$base/out"
  _qa_rodar "$base" download /r/a.txt "$base/local/a.txt"
  assert_igual 0 "$DBX_ESTADO" "download para arquivo conclui; erro: $DBX_ERRO"
  assert_sucesso cmp -s "$base/conteudo_remoto" "$base/local/a.txt"
}

# ---------------------------------------------------------------------------
# RF-59 — linhas `falha` e pares do `--json`
# ---------------------------------------------------------------------------

teste_qa_caminho_com_tabulacao_e_escape_sai_citado_em_uma_linha() {
  local base nome linhas
  base=$(_qa_cenario)
  nome=$'t\tab\033[31mvermelho.txt'
  printf 'x' >"$base/local/$nome"
  printf '%s 409 path/conflict/file/..\n' 'vermelho' >"$base/falhar_envio"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  linhas=$(_qa_linhas_de_falha "$DBX_ERRO")
  assert_igual 1 "$(_qa_linhas_de_falha "$DBX_ERRO" | wc -l | tr -d ' ')" 'uma linha de falha'
  assert_nao_contem $'\033' "$DBX_ERRO" 'o byte de escape nunca chega ao terminal'
  assert_nao_contem $'\t' "$linhas" 'a tabulacao sai citada'
  assert_contem 'conflito' "$linhas" 'a classe esta na linha'
}

teste_qa_resumo_com_token_colado_a_prefixo_nao_vaza() {
  # Servidor hostil devolve o PROPRIO token do processo no error_summary, colado
  # a um prefixo do alfabeto de tag (sem delimitador antes do `sl.`).
  local base resumo
  for resumo in 'sl.QAtokenSentinela' 'path/sl.QAtokenSentinela' 'x_sl.QAtokenSentinela' \
    'path-sl.QAtokenSentinela/..'; do
    base=$(_qa_cenario)
    printf '%s' 'sl.QAtokenSentinela' >"$base/token"
    printf 'x' >"$base/local/a.txt"
    printf 'a.txt 409 %s\n' "$resumo" >"$base/falhar_envio"
    _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
    assert_igual 1 "$(_qa_linhas_de_falha "$DBX_ERRO" | wc -l | tr -d ' ')" "a falha foi reportada ($resumo)"
    assert_segredo_ausente 'QAtokenSentinela' "$DBX_SAIDA$DBX_ERRO" "o token nunca aparece ($resumo)"
    assert_segredo_ausente 'SENTINELAcorpoQA' "$DBX_SAIDA$DBX_ERRO" "o corpo bruto nunca aparece ($resumo)"
  done
}

teste_qa_json_com_tres_falhas_de_classes_distintas_mantem_a_ordem() {
  local base esperado obtido linha
  base=$(_qa_cenario)
  printf 'x' >"$base/local/a.txt"
  printf 'x' >"$base/local/b.txt"
  printf 'x' >"$base/local/c.txt"
  printf 'x' >"$base/local/d.txt"
  {
    printf 'a.txt 409 path/conflict/file/..\n'
    printf 'c.txt 507 path/insufficient_space/..\n'
    printf 'd.txt 400 bad_request\n'
  } >"$base/falhar_envio"
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'falha de item e nao concluida'
  assert_contem 'falhas=3' "$DBX_SAIDA" 'a contagem continua um numero'
  obtido=''
  while IFS= read -r linha; do
    [[ $linha == falha_* ]] && obtido+="${linha%%=*}=${linha#*=};"
  done <<<"$DBX_SAIDA"
  esperado=''
  while IFS= read -r linha; do
    linha=${linha#falha }
    esperado+="falha_caminho=${linha%%:*};"
    linha=${linha#*: }
    esperado+="falha_classe=${linha%% *};"
  done < <(_qa_linhas_de_falha "$DBX_ERRO")
  assert_igual "$esperado" "$obtido" 'os pares seguem a ordem e a classe das linhas de falha'
  assert_contem 'falha_caminho=a.txt;' "$obtido" 'o primeiro item falho esta presente'
  assert_nao_contem 'b.txt' "$obtido" 'o item enviado nao vira par'
}

teste_qa_json_com_null_emite_os_pares_terminados_em_nul() {
  local base registros
  base=$(_qa_cenario)
  printf 'x' >"$base/local/"$'linha\nquebrada.txt'
  printf 'quebrada 409 path/conflict/file/..\n' >"$base/falhar_envio"
  _qa_rodar "$base" --json --null sync --enviar --origem "$base/local" --destino /r
  local registro
  registros=0
  while IFS= read -r -d '' registro; do
    [[ $registro == falha_* ]] && registros=$((registros + 1))
  done <"$base/out"
  assert_igual 2 "$registros" 'um par caminho e classe'
  assert_sucesso grep -qz $'^falha_caminho=linha\nquebrada.txt$' "$base/out"
  assert_igual 1 "$(_qa_linhas_de_falha "$DBX_ERRO" | wc -l | tr -d ' ')" \
    'a linha de falha no stderr continua uma so'
}

teste_qa_diagnostico_mascara_token_no_formato_sl_u_pelo_valor() {
  # Formato atual dos tokens curtos da Dropbox: `sl.u.<corpo>`. O servico ecoa o
  # token num error_summary; nenhum pedaco do corpo pode chegar ao stderr.
  local base
  base=$(_qa_cenario)
  printf '%s' 'sl.u.QAcorpoDoTokenNovo42' >"$base/token"
  printf '%s' '{"error_summary":"path/sl.u.QAcorpoDoTokenNovo42 x_sl.u.QAcorpoDoTokenNovo42"}' \
    >"$base/erro_space_corpo"
  _qa_rodar "$base" space
  assert_diferente 0 "$DBX_ESTADO" 'a consulta recusada falha'
  assert_segredo_ausente 'QAcorpoDoTokenNovo42' "$DBX_SAIDA$DBX_ERRO" 'o corpo do token nunca aparece'
}

teste_qa_diagnostico_redige_token_sl_u_alheio_pela_forma_sem_consumir_o_vizinho() {
  # Token que NAO esta em memoria (so a forma o alcanca), com `-` e `_` no corpo
  # e varios pontos; a pontuacao e o texto depois dele ficam.
  local base
  base=$(_qa_cenario)
  printf '%s' '{"error_summary":"path/sl.u.QAalheio-Tok_en.Parte2-x_y. Proxima frase, sl.u.QAoutro_9,depois fim"}' \
    >"$base/erro_space_corpo"
  _qa_rodar "$base" space
  assert_diferente 0 "$DBX_ESTADO" 'a consulta recusada falha'
  assert_segredo_ausente 'QAalheio-Tok_en' "$DBX_SAIDA$DBX_ERRO" 'o corpo do token alheio nunca aparece'
  assert_segredo_ausente 'Parte2-x_y' "$DBX_SAIDA$DBX_ERRO" 'nem o trecho depois do segundo ponto'
  assert_segredo_ausente 'QAoutro_9' "$DBX_SAIDA$DBX_ERRO" 'o segundo token tambem e redigido'
  assert_contem '. Proxima frase,' "$DBX_ERRO" 'o ponto final e o texto seguinte ficam'
  assert_contem ',depois fim' "$DBX_ERRO" 'a virgula e o texto seguinte ficam'
}

teste_qa_diagnostico_mascara_pelo_valor_token_com_metacaracteres_colado_a_prefixo() {
  # So a mascaracao pelo valor alcanca `x_sl.<token>` (a redacao por forma exige
  # delimitador antes de `sl`). O token traz metacaracteres de glob e de regex:
  # precisa sair mascarado literalmente, e o texto parecido ao lado, intacto.
  local base
  base=$(_qa_cenario)
  printf '%s' 'sl.QA*tok[e]n?+$x9' >"$base/token"
  printf '%s' '{"error_summary":"x_sl.QA*tok[e]n?+$x9 vizinho_QAxtokenZ+$x9_fica"}' >"$base/erro_space_corpo"
  _qa_rodar "$base" space
  assert_diferente 0 "$DBX_ESTADO" 'a consulta recusada falha'
  assert_segredo_ausente 'QA*tok[e]n?+$x9' "$DBX_SAIDA$DBX_ERRO" 'o token com metacaracteres nunca aparece'
  assert_contem 'vizinho_QAxtokenZ+$x9_fica' "$DBX_ERRO" 'o padrao nao e glob: o texto vizinho fica'
  assert_igual 1 "$(_qa_linhas_com 'erro=' "$DBX_ERRO")" 'o diagnostico continua uma linha'
}

teste_qa_renovacao_recusada_nao_ecoa_refresh_token_nem_app_secret() {
  # Segredos com metacaracteres de glob e de regex: mascarados literalmente, sem
  # apagar o texto vizinho.
  local base
  base=$(_qa_cenario)
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"QA*sec[r]?t.+$9","refresh_token":"QArefresh_Segredo-77","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  printf '%s' '{"error":"invalid_grant","error_description":"refresh QArefresh_Segredo-77 com segredo QA*sec[r]?t.+$9 recusado"}' \
    >"$base/erro_oauth_corpo"
  _qa_rodar "$base" space
  assert_diferente 0 "$DBX_ESTADO" 'renovacao recusada falha'
  assert_segredo_ausente 'QArefresh_Segredo-77' "$DBX_SAIDA$DBX_ERRO" 'o refresh token nunca aparece'
  assert_segredo_ausente 'QA*sec[r]?t.+$9' "$DBX_SAIDA$DBX_ERRO" 'o app secret nunca aparece'
}

# ---------------------------------------------------------------------------
# RNF-31 — sinais em pontos que a suite do developer nao cobre
# ---------------------------------------------------------------------------

teste_qa_hup_durante_o_recebimento_do_sync_nao_deixa_area() {
  local base
  base=$(_qa_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada /r/a.txt ff 15)" >"$base/listagem"
  printf 'HUP' >"$base/sinal"
  printf 'files/download' >"$base/sinal_url"
  _qa_rodar_em_sessao "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area dbx-sync.* nem dbx-http.*'
  assert_igual '' "$(find "$base/local" -mindepth 1)" 'nenhum temporario de recebimento'
}

teste_qa_int_durante_a_exclusao_do_espelho_nao_deixa_area() {
  local base
  base=$(_qa_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada /r/so-remoto.txt ff 15)" >"$base/listagem"
  printf 'x' >"$base/local/a.txt"
  printf 'INT' >"$base/sinal"
  printf 'files/delete_v2' >"$base/sinal_url"
  _qa_rodar_em_sessao "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_igual 1 "$(_harness_contar 'files/delete_v2' "$base/chamadas")" 'o sinal chegou na exclusao'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area dbx-sync.* nem dbx-http.*'
}

teste_qa_term_durante_a_listagem_do_receber_nao_deixa_area() {
  local base
  base=$(_qa_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada /r/a.txt ff 15)" >"$base/listagem"
  printf 'TERM' >"$base/sinal"
  printf 'list_folder' >"$base/sinal_url"
  _qa_rodar_em_sessao "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" 'o sinal chegou antes de receber'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area dbx-sync.* nem dbx-http.*'
}

teste_qa_sync_com_falha_de_item_nao_deixa_area_e_devolve_os_sinais() {
  local base
  base=$(_qa_cenario)
  printf 'x' >"$base/local/a.txt"
  printf 'a.txt 409 path/conflict/file/..\n' >"$base/falhar_envio"
  _qa_rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$QA_NAO_CONCLUIDA" "$DBX_ESTADO" 'falha de item'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'termino com falha nao deixa area'
}

harness_executar "$@"
