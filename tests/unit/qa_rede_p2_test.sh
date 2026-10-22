#!/usr/bin/env bash
# Suite independente do QA Expert para a fase P2 (robustez de rede), parte
# unitaria: `lib/http` (RNF-07, RNF-30), `lib/transfer` (RF-09, RF-58) e o
# executor da suite (RNF-32(a)).
#
# Independente da suite do Senior Developer: duplo de `curl` e de `sleep`
# proprios, respostas roteirizadas POR CHAMADA (status, cabecalhos e corpo
# diferentes a cada tentativa), e as bordas que a suite de desenvolvimento nao
# fixa — limites exatos 300/301 do `Retry-After`, cabecalho repetido, espacos,
# `Retry-After` de uma tentativa que nao vaza para a seguinte, `correct_offset`
# igual ao enviado e igual ao enviado mais um, retomadas em partes distintas,
# origem que encolhe na retomada e cresce sem retomada, e o executor diante de
# arquivo que morre sem agregado.
#
# shellcheck disable=SC2016
# Justificativa: os substitutos de `curl` e `sleep` sao escritos sem expansao.
#
# shellcheck disable=SC2094
# Justificativa: a massa e redirecionada para a entrada padrao E passada como
# nome, que e exatamente o contrato de `dbx_transfer_sessao` com origem (RF-58).
#
# shellcheck disable=SC2034
# Justificativa: `DBX_AUTH_TOKEN` e `DBX_AUTH_EXPIRA_EM` sao canais de OUTRO
# componente, definidos aqui para o caso nao renovar credencial.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"
. "$DBX_HARNESS_RAIZ/lib/transfer.sh"

DBX_AUTH_TOKEN='sl.QAtokenP2'
DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))

readonly QA_COMMIT='{"path":"/r/qa.bin","mode":"add","autorename":false,"mute":false}'
readonly QA_PARTE=4194304
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly QA_NAO_CONCLUIDA

# TMPDIR proprio por caso: a contagem de residuo nunca olha o /tmp compartilhado.
preparar_caso() {
  TMPDIR=$(mktemp -d "$DBX_TESTES_TMP/qa-p2-tmp.XXXXXX") || return 1
  export TMPDIR
}

# _qa_duplo — substituto de `curl` com resposta roteirizada por chamada, e de
# `sleep` que so registra. Devolve o diretorio de controle.
#
# Por chamada, a resposta vem de `<alvo>.<n>.<campo>` ou, sem ele, de
# `<alvo>.<campo>`, com <alvo> em start|append|finish|outro, <n> a ordem da
# chamada a esse alvo e <campo> em `st` (status), `hd` (cabecalhos, um por
# linha) e `co` (corpo). Controles adicionais:
#   montar             grava cada corpo aceito no offset do cursor em `remoto`
#   encolher           "<alvo>:<n> <arquivo> <bytes>" trunca a origem nessa chamada
#   crescer            "<alvo>:<n> <arquivo>" acrescenta um byte nessa chamada
#   voltar             "<offset> <a> <b>": todo append nesse offset recebe
#                      incorrect_offset, alternando correct_offset a e b
_qa_duplo() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/qa-p2-duplo.XXXXXX")
  printf '%s' '{"session_id":"S-QA"}' >"$dir/start.co"
  printf '%s' '{}' >"$dir/append.co"
  printf '%s' '{"name":"qa.bin","rev":"1"}' >"$dir/finish.co"
  printf '%s' '{"ok":true}' >"$dir/outro.co"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%q\n' "$dir"
    printf 'raiz=%q\n' "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat)
url=''; saida=''; escrever=''; cabecalhos=''; corpoarq=''; ant=''
for a in "$@"; do
  case $ant in -o) saida=$a ;; -w) escrever=$a ;; -D) cabecalhos=$a ;; esac
  case $a in http*) url=$a ;; @*) corpoarq=${a#@} ;; esac
  ant=$a
done
case $url in
  *upload_session/start*) alvo=start ;;
  *upload_session/append_v2*) alvo=append ;;
  *upload_session/finish*) alvo=finish ;;
  *) alvo=outro ;;
esac
argapi=''
while IFS= read -r linha; do
  case $linha in
    *Dropbox-API-Arg:*)
      argapi=${linha#*Dropbox-API-Arg: }
      argapi=${argapi%\"}
      argapi=${argapi//\\\"/\"}
      ;;
  esac
done <<<"$conf"
vez=0
[[ -r "$dir/n_$alvo" ]] && read -r vez <"$dir/n_$alvo"
vez=$((vez + 1))
printf '%s' "$vez" >"$dir/n_$alvo"
bytes=-
[[ -n $corpoarq && -r $corpoarq ]] && bytes=$(wc -c <"$corpoarq") && bytes=${bytes//[^0-9]/}
desl=''
[[ $argapi =~ \"offset\":([0-9]+) ]] && desl=${BASH_REMATCH[1]}
printf '%s %s desl=%s bytes=%s\n' "$alvo" "$vez" "$desl" "$bytes" >>"$dir/chamadas"
campo() { # <campo>
  if [[ -r "$dir/$alvo.$vez.$1" ]]; then cat "$dir/$alvo.$vez.$1"
  elif [[ -r "$dir/$alvo.$1" ]]; then cat "$dir/$alvo.$1"
  fi
}
codigo=$(campo st)
codigo=${codigo:-200}
forcado=''
if [[ $alvo == append && -r "$dir/voltar" ]]; then
  read -r alvo_desl off_a off_b <"$dir/voltar"
  if [[ $desl == "$alvo_desl" ]]; then
    n_volta=0
    [[ -r "$dir/n_volta" ]] && read -r n_volta <"$dir/n_volta"
    n_volta=$((n_volta + 1))
    printf '%s' "$n_volta" >"$dir/n_volta"
    off=$off_a
    ((n_volta % 2 == 0)) && off=$off_b
    codigo=409
    forcado="{\"error_summary\":\"incorrect_offset/..\",\"error\":{\".tag\":\"incorrect_offset\",\"correct_offset\":$off}}"
  fi
fi
[[ -n $cabecalhos ]] && campo hd | while IFS= read -r h; do printf '%s\r\n' "$h"; done >"$cabecalhos"
if [[ -r "$dir/montar" && -n $desl && -n $corpoarq && $codigo == 200 ]] && [[ $alvo == append || $alvo == finish ]]; then
  [[ -e "$dir/remoto" ]] || : >"$dir/remoto"
  head -c "$desl" "$dir/remoto" >"$dir/remoto.novo"
  cat "$corpoarq" >>"$dir/remoto.novo"
  mv "$dir/remoto.novo" "$dir/remoto"
fi
if [[ -r "$dir/encolher" ]]; then
  read -r gatilho arquivo tamanho <"$dir/encolher"
  [[ $gatilho == "$alvo:$vez" ]] && truncate -s "$tamanho" "$arquivo"
fi
if [[ -r "$dir/crescer" ]]; then
  read -r gatilho arquivo <"$dir/crescer"
  [[ $gatilho == "$alvo:$vez" ]] && printf 'Q' >>"$arquivo"
fi
if [[ $alvo == finish && -r "$dir/montar" && $codigo == 200 ]]; then
  resumo=$(TMPDIR=$dir bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; dbx_hash_conteudo_arquivo "$2"' \
    _ "$raiz" "$dir/remoto")
  printf '{"name":"qa.bin","rev":"1","content_hash":"%s"}' "$resumo" >"$dir/finish.co"
fi
if [[ -n $saida && -n $forcado ]]; then
  printf '%s' "$forcado" >"$saida"
elif [[ -n $saida ]]; then
  campo co >"$saida"
fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$dir/curl"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$1" >>%q\n' "$dir/esperas"
  } >"$dir/sleep"
  chmod +x "$dir/curl" "$dir/sleep"
  printf '%s' "$dir"
}

# _qa_esperas_ms <dir> — cada espera registrada, em ms, uma por linha.
_qa_esperas_ms() {
  local valor
  [[ -r $1/esperas ]] || return 0
  while IFS= read -r valor; do
    if [[ $valor =~ ^([0-9]+)\.([0-9]{3})$ ]]; then
      printf '%s\n' "$((10#${BASH_REMATCH[1]} * 1000 + 10#${BASH_REMATCH[2]}))"
    else
      printf 'FORMATO[%s]\n' "$valor"
    fi
  done <"$1/esperas"
}

# _qa_requisitar <dir> [tentativas] — uma chamada idempotente pelo duplo.
_qa_requisitar() {
  local dir=$1 tentativas=${2:-2}
  DBX_HTTP_TENTATIVAS_MAXIMAS=$tentativas PATH="$dir:$PATH" \
    dbx_http_requisitar POST 'https://api.dropboxapi.com/2/users/get_space_usage' 'tok' '' sim
}

# _qa_429 <dir> <cabecalhos...> — a chamada 1 responde 429 com os cabecalhos.
_qa_429() {
  local dir=$1
  shift
  printf '429\n' >"$dir/outro.1.st"
  printf '%s' '{"error_summary":"too_many_requests/.."}' >"$dir/outro.1.co"
  printf '%s\n' "$@" >"$dir/outro.1.hd"
}

_qa_massa() { # <bytes> — conteudo variado, para releitura no lugar errado nao passar
  local caminho
  caminho=$(mktemp "$DBX_TESTES_TMP/qa-p2-massa.XXXXXX")
  head -c "$1" /dev/urandom >"$caminho"
  printf '%s' "$caminho"
}

_qa_incorrect_offset() { # <dir> <chamada_do_append> <correct_offset>
  printf '409\n' >"$1/append.$2.st"
  printf '{"error_summary":"incorrect_offset/..","error":{".tag":"incorrect_offset","correct_offset":%s}}' \
    "$3" >"$1/append.$2.co"
}

_qa_deslocamentos() { # <dir> <alvo> — offsets enviados a esse alvo, um por linha
  local alvo vez desl resto
  while read -r alvo vez desl resto; do
    [[ $alvo == "$2" ]] && printf '%s\n' "${desl#desl=}"
  done <"$1/chamadas"
  return 0
}

# ---------------------------------------------------------------------------
# RNF-07 — Retry-After: limites exatos e formas que a suite do developer nao fixa
# ---------------------------------------------------------------------------

teste_qa_retry_after_no_limite_exato_de_300_vale_300() {
  local dir
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 300'
  _qa_requisitar "$dir"
  assert_igual 300000 "$(_qa_esperas_ms "$dir")" 'Retry-After: 300 e o proprio teto'
}

teste_qa_retry_after_301_e_limitado_a_300() {
  local dir
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 301'
  _qa_requisitar "$dir"
  assert_igual 300000 "$(_qa_esperas_ms "$dir")" 'um segundo acima do teto vira o teto'
}

teste_qa_retry_after_com_espacos_e_zero_a_esquerda_vale_em_decimal() {
  local dir
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After:    7   '
  _qa_requisitar "$dir"
  assert_igual 7000 "$(_qa_esperas_ms "$dir")" 'espacos em volta do valor nao invalidam'
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 010'
  _qa_requisitar "$dir"
  assert_igual 10000 "$(_qa_esperas_ms "$dir")" '010 e dez segundos, nunca octal'
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 09'
  _qa_requisitar "$dir"
  assert_igual 9000 "$(_qa_esperas_ms "$dir")" '09 e nove segundos, nunca erro de octal'
}

teste_qa_retry_after_repetido_vale_um_dos_valores_e_nunca_a_juncao() {
  local dir ms
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 3' 'Retry-After: 9'
  _qa_requisitar "$dir"
  ms=$(_qa_esperas_ms "$dir")
  [[ $ms == 3000 || $ms == 9000 ]] ||
    _harness_falhar 'cabecalho repetido vale um dos valores informados' "obtido: [$ms]"
}

teste_qa_retry_after_ausente_em_429_cai_no_recuo_de_base_um_segundo() {
  local dir ms
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'X-Dropbox-Request-Id: qa-1'
  _qa_requisitar "$dir"
  ms=$(_qa_esperas_ms "$dir")
  [[ $ms =~ ^[0-9]+$ && $ms -ge 1000 && $ms -le 2000 ]] ||
    _harness_falhar '429 sem Retry-After deve esperar o recuo de 1 a 2 s' "obtido: [$ms]"
  assert_igual 2 "$(_harness_contar '^outro' "$dir/chamadas")" 'e repete'
}

teste_qa_retry_after_negativo_ou_com_digitos_separados_nao_vale() {
  local dir valor ms
  for valor in '-300' '+5' '5 0' '0x10' '1e2'; do
    dir=$(_qa_duplo)
    _qa_429 "$dir" "Retry-After: $valor"
    _qa_requisitar "$dir"
    ms=$(_qa_esperas_ms "$dir")
    [[ $ms =~ ^[0-9]+$ && $ms -ge 1000 && $ms -le 2000 ]] ||
      _harness_falhar "Retry-After [$valor] e invalido e deve cair no recuo de 1 a 2 s" "obtido: [$ms]"
  done
}

teste_qa_retry_after_de_uma_tentativa_nao_vaza_para_a_seguinte() {
  # Tentativa 1: 429 com Retry-After 120. Tentativa 2: 503 SEM o cabecalho. A
  # segunda espera e o recuo, e nao os 120 s da resposta anterior.
  local dir segunda
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 120'
  printf '503\n' >"$dir/outro.st"
  printf '%s' '{"error_summary":"internal_error/.."}' >"$dir/outro.co"
  _qa_requisitar "$dir" 3
  assert_igual 120000 "$(_qa_esperas_ms "$dir" | head -n 1)" 'a primeira espera e a pedida'
  segunda=$(_qa_esperas_ms "$dir" | sed -n 2p)
  [[ $segunda =~ ^[0-9]+$ && $segunda -ge 2000 && $segunda -le 3000 ]] ||
    _harness_falhar 'a segunda espera e o recuo da tentativa 2 (2 a 3 s)' "obtido: [$segunda]"
}

teste_qa_retry_after_em_falha_de_transporte_seguinte_nao_e_reaproveitado() {
  # Tentativa 2 sem resposta (http=0): nao ha cabecalho, e o Retry-After da
  # tentativa 1 nao pode ser reaproveitado.
  local dir segunda
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 120'
  printf '000\n' >"$dir/outro.st"
  : >"$dir/outro.co"
  _qa_requisitar "$dir" 3
  segunda=$(_qa_esperas_ms "$dir" | sed -n 2p)
  [[ $segunda =~ ^[0-9]+$ && $segunda -le 3000 ]] ||
    _harness_falhar 'apos falha de transporte vale o recuo, nao o Retry-After antigo' "obtido: [$segunda]"
}

teste_qa_tentativas_igual_a_1_com_429_nao_espera_nem_repete() {
  local dir
  dir=$(_qa_duplo)
  _qa_429 "$dir" 'Retry-After: 5'
  _qa_requisitar "$dir" 1
  assert_igual 1 "$(_harness_contar '^outro' "$dir/chamadas")" 'uma tentativa so'
  assert_arquivo_ausente "$dir/esperas" 'sem repeticao, nenhuma espera, nem a pedida'
}

teste_qa_ajuste_com_espaco_sinal_ou_dez_digitos_e_recusado_antes_da_rede() {
  local dir valor
  dir=$(_qa_duplo)
  for valor in ' 5' '5 ' '+5' '1000000000' $'5\n' '0x5' '５'; do
    (
      export DBX_HTTP_CONNECT_TIMEOUT_S="$valor"
      _qa_requisitar "$dir" 2
      assert_igual "$DBX_HTTP_ERRO_USO" "$?" "[$valor] e uso invalido"
      assert_nao_contem $'\n' "$DBX_HTTP_MOTIVO_AMBIENTE" 'o motivo cabe numa linha'
    ) || exit 1
  done
  assert_arquivo_ausente "$dir/chamadas" 'nenhuma chamada com ajuste invalido'
  (
    export DBX_HTTP_TENTATIVAS_MAXIMAS=999999999
    _qa_requisitar "$dir" 999999999
  ) || exit 1
  assert_igual 1 "$(_harness_contar '^outro' "$dir/chamadas")" 'nove digitos e o maior valido'
}

# ---------------------------------------------------------------------------
# RF-58 — limites de `correct_offset` e retomadas
# ---------------------------------------------------------------------------

teste_qa_offset_igual_ao_enviado_reenvia_so_a_parte_recusada() {
  # 3 partes de 4 MiB + resto; na 2a, o servico diz ter exatamente o que ja foi
  # confirmado (4 MiB): a parte e reenviada de 4 MiB, nada antes dela.
  local dir massa
  dir=$(_qa_duplo)
  : >"$dir/montar"
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  _qa_incorrect_offset "$dir" 2 "$QA_PARTE"
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual 0 $? "offset igual ao enviado e aceito; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_igual $'0\n4194304\n4194304' "$(_qa_deslocamentos "$dir" append)" \
    'a parte recusada e reenviada do mesmo deslocamento'
  assert_sucesso cmp -s "$massa" "$dir/remoto"
  assert_igual 'conferida' "$DBX_TRANSFER_INTEGRIDADE" 'o resumo final confere'
}

teste_qa_offset_um_byte_acima_do_enviado_e_recusado() {
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  _qa_incorrect_offset "$dir" 2 $((QA_PARTE + 1))
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'enviado+1 e recusado'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
  assert_igual 2 "$(_harness_contar '^append' "$dir/chamadas")" 'nenhuma releitura'
  assert_contem "$((QA_PARTE + 1))" "$DBX_TRANSFER_MOTIVO" 'o valor recusado e nomeado'
  assert_igual '' "$(find "$TMPDIR" -mindepth 1)" 'nenhum residuo em TMPDIR'
}

teste_qa_offset_igual_ao_tamanho_do_arquivo_e_recusado() {
  local dir massa tamanho=$((QA_PARTE * 2 + 1000))
  dir=$(_qa_duplo)
  massa=$(_qa_massa "$tamanho")
  _qa_incorrect_offset "$dir" 1 "$tamanho"
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'offset = tamanho, sem nada confirmado, e recusado'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
}

teste_qa_retomadas_em_partes_distintas_contam_por_parte() {
  # RF-58(e): "cada retomada consome uma das tentativas DA PARTE" (RF-09: 5
  # tentativas por parte). Com 2 tentativas, cada parte pode retomar uma vez:
  # uma retomada na parte 1 e outra na parte 2 nao esgotam nenhuma delas.
  local dir massa
  dir=$(_qa_duplo)
  : >"$dir/montar"
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  _qa_incorrect_offset "$dir" 1 0
  _qa_incorrect_offset "$dir" 3 "$QA_PARTE"
  DBX_HTTP_TENTATIVAS_MAXIMAS=2 PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual 0 $? "uma retomada por parte cabe em 2 tentativas por parte; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_sucesso cmp -s "$massa" "$dir/remoto"
}

teste_qa_servidor_que_sempre_volta_ao_inicio_na_mesma_parte_esgota_as_tentativas() {
  # Voltar e reaceitar o mesmo trecho nao e progresso: o contador por parte nao
  # pode zerar, senao o laco nunca termina.
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  printf '%s 0 0\n' "$QA_PARTE" >"$dir/voltar"
  DBX_HTTP_TENTATIVAS_MAXIMAS=3 PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'esgota as tentativas da parte'
  assert_igual 3 "$(cat "$dir/n_volta")" \
    'tres recusas no mesmo offset: a primeira tentativa e duas retomadas'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
}

teste_qa_servidor_que_alterna_offsets_na_mesma_parte_esgota_as_tentativas() {
  # Na 3a parte o servico alterna 0 e 4 MiB: cada volta reaceita trechos ja
  # confirmados, nenhum passa do maior ja visto, e o laco termina.
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE * 3 + 1000)))
  printf '%s 0 %s\n' $((QA_PARTE * 2)) "$QA_PARTE" >"$dir/voltar"
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'alternancia sem progresso esgota as tentativas'
  assert_igual 5 "$(cat "$dir/n_volta")" 'cinco recusas no offset da 3a parte (padrao 5)'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
}

teste_qa_origem_que_encolhe_antes_da_retomada_e_recusada() {
  # Na 2a parte o servico pede releitura de 0, e a origem encolheu para 1 MiB.
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  _qa_incorrect_offset "$dir" 2 0
  printf 'append:2 %s %s\n' "$massa" 1048576 >"$dir/encolher"
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'origem encolhida e recusada'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
  assert_igual '' "$(find "$TMPDIR" -mindepth 1)" 'nenhum residuo em TMPDIR'
}

teste_qa_origem_que_cresce_na_ultima_parte_sem_retomada_e_recusada() {
  # Sem `incorrect_offset`: o arquivo ganha um byte durante o 2o append e a
  # leitura seguinte ve o byte novo. Recusado antes do `finish`.
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  printf 'append:2 %s\n' "$massa" >"$dir/crescer"
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'origem que cresceu e recusada'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
  assert_contem 'tamanho' "$DBX_TRANSFER_MOTIVO" 'o diagnostico diz que o tamanho mudou'
}

teste_qa_origem_que_encolhe_sem_retomada_e_recusada() {
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE * 2 + 1000)))
  printf 'append:1 %s %s\n' "$massa" $((QA_PARTE + 10)) >"$dir/encolher"
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'origem que encolheu e recusada'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
}

teste_qa_entrada_padrao_em_cano_nao_retoma_mesmo_com_offset_zero() {
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE + 1000)))
  _qa_incorrect_offset "$dir" 1 0
  PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" < <(cat "$massa")
  assert_igual "$QA_NAO_CONCLUIDA" $? 'cano nao e posicionavel'
  assert_igual 1 "$(_harness_contar '^append' "$dir/chamadas")" 'nenhuma releitura'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
}

teste_qa_parte_esgotada_com_tentativas_igual_a_1_nao_repete() {
  local dir massa
  dir=$(_qa_duplo)
  massa=$(_qa_massa $((QA_PARTE + 1000)))
  printf '503\n' >"$dir/append.st"
  printf '%s' '{"error_summary":"internal_error/.."}' >"$dir/append.co"
  DBX_HTTP_TENTATIVAS_MAXIMAS=1 PATH="$dir:$PATH" dbx_transfer_sessao "$QA_COMMIT" "$massa" <"$massa"
  assert_igual "$QA_NAO_CONCLUIDA" $? 'esgotada e nao concluida'
  assert_igual 1 "$(_harness_contar '^append' "$dir/chamadas")" 'uma tentativa so'
  assert_arquivo_ausente "$dir/esperas" 'nenhuma espera'
  assert_igual 0 "$(_harness_contar '^finish' "$dir/chamadas")" 'nada publicado'
}

# ---------------------------------------------------------------------------
# RNF-32(a) — executor e arcabouco diante de agregado ausente e plano parcial
# ---------------------------------------------------------------------------

_qa_suite() { # imprime a raiz de uma arvore com o executor e o arcabouco reais
  local raiz
  raiz=$(mktemp -d "$DBX_TESTES_TMP/qa-suite.XXXXXX")
  mkdir -p "$raiz/tests/unit" "$raiz/tests/support" "$raiz/tests/integracao"
  cp "$DBX_HARNESS_RAIZ/tests/run.sh" "$raiz/tests/run.sh"
  cp "$DBX_HARNESS_RAIZ/tests/support/harness.sh" "$raiz/tests/support/harness.sh"
  printf '%s' "$raiz"
}

_qa_rodar_suite() { # <raiz> [filtro]
  local raiz=$1
  shift
  env -u DBX_TESTES_TMP -u DBX_HARNESS_RESUMO -u DBX_HARNESS_ARQUIVO \
    -u DBX_HARNESS_ARQ_PULAR DBX_HARNESS_RAIZ="$raiz" \
    DBX_HARNESS_DIARIO="$raiz/diario.log" MARCA="$raiz" TMPDIR="$raiz" \
    bash "$raiz/tests/run.sh" "$@" >"$raiz/saida" 2>&1
  QA_ESTADO=$?
  QA_LIDO=$(cat "$raiz/saida")
}

teste_qa_executor_para_em_arquivo_que_morre_sem_agregado() {
  local raiz
  raiz=$(_qa_suite)
  printf 'exit 0\n' >"$raiz/tests/unit/a_test.sh"
  cat >"$raiz/tests/unit/b_test.sh" <<'FIM'
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
teste_b() { : >"$MARCA/b_rodou"; }
harness_executar "$@"
FIM
  _qa_rodar_suite "$raiz"
  assert_igual 1 "$QA_ESTADO" 'agregado ausente reprova mesmo com status zero'
  assert_contem 'INTEGRIDADE' "$QA_LIDO" 'a falha de integridade e nomeada'
  assert_contem 'interrompida em     : a_test.sh' "$QA_LIDO" 'e e o primeiro erro'
  assert_arquivo_ausente "$raiz/b_rodou" 'o arquivo seguinte nao roda'
  assert_nao_contem 'APROVADA' "$QA_LIDO" 'nunca aprova'
}

teste_qa_executor_nao_mascara_integridade_atras_de_bail_out() {
  # O primeiro arquivo da Bail out! (agregado 0 1 0); o problema de integridade
  # vem de agregado forjado no MESMO arquivo, que nao pode ser lido como valido.
  local raiz
  raiz=$(_qa_suite)
  cat >"$raiz/tests/unit/a_test.sh" <<'FIM'
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
teste_m1() { _harness_falhar 'fabricada'; }
teste_m2() { : >"$MARCA/m2_rodou"; }
harness_executar "$@"
printf 'nove nove nove\n' >"$DBX_HARNESS_RESUMO"
FIM
  _qa_rodar_suite "$raiz"
  assert_igual 1 "$QA_ESTADO" 'reprova'
  assert_contem 'Bail out!' "$QA_LIDO" 'o arcabouco declarou a parada'
  assert_contem 'agregado malformado' "$QA_LIDO" 'o agregado forjado nao e aceito'
  assert_arquivo_ausente "$raiz/m2_rodou" 'o caso seguinte nao rodou'
}

teste_qa_ultimo_caso_reprovado_nao_emite_bail_out_e_reprova() {
  local raiz
  raiz=$(_qa_suite)
  cat >"$raiz/tests/unit/a_test.sh" <<'FIM'
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
teste_u1() { :; }
teste_u2() { pular 'pulado de proposito'; }
teste_u3() { _harness_falhar 'fabricada'; }
harness_executar "$@"
FIM
  _qa_rodar_suite "$raiz"
  assert_igual 1 "$QA_ESTADO" 'reprova'
  assert_contem '# SKIP' "$QA_LIDO" 'caso pulado nao interrompe'
  assert_contem 'not ok 3 - u3' "$QA_LIDO" 'o ultimo caso rodou e reprovou'
  assert_nao_contem 'Bail out!' "$QA_LIDO" 'sem caso restante nao ha Bail out'
  assert_contem 'casos reprovados    : 1' "$QA_LIDO" 'o total de reprovados vem do agregado'
}

teste_qa_filtro_de_caso_sem_correspondencia_reprova_o_arquivo() {
  local raiz
  raiz=$(_qa_suite)
  cat >"$raiz/tests/unit/a_test.sh" <<'FIM'
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
teste_f1() { :; }
harness_executar "$@"
FIM
  DBX_HARNESS_RAIZ=$raiz DBX_TESTES_TMP=$raiz DBX_HARNESS_RESUMO="$raiz/resumo" \
    bash "$raiz/tests/unit/a_test.sh" nao_existe >"$raiz/saida" 2>&1
  assert_diferente 0 "$?" 'filtro de caso sem correspondencia reprova'
  assert_igual '0 1 0' "$(cat "$raiz/resumo")" 'e o agregado registra a reprovacao'
}

harness_executar "$@"
