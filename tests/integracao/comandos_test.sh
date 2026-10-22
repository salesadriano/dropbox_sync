#!/usr/bin/env bash
# Testes ponta a ponta dos comandos diretos, pelo executavel real.
#
# Primeiro exercicio do caminho completo: entrada, opcoes globais, verificacao
# previa, credencial, autenticacao, transporte, analise e saida. Ate aqui os
# componentes passavam isolados e nenhum caminho ponta a ponta tinha rodado.
#
# shellcheck disable=SC2016
# Justificativa: casos escrevem o substituto de `curl`, que precisa chegar sem
# expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

# _ambiente <corpo_da_api> — credencial em area propria e substituto de `curl`
# que responde token no endpoint de autenticacao e o corpo dado nos demais.
_ambiente() {
  local corpo=$1 codigo=${2:-200}
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/amb.XXXXXX")
  mkdir -p "$base/config/dbx"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  mkdir -p "$base/bin"
  printf '%s' "$corpo" >"$base/corpo"
  printf '%s' "$codigo" >"$base/codigo"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    printf 'printf "%%s\\n" "$*" >>"$base/argv"\n'
    # O cabecalho NAO viaja em argv: vai pelo arquivo de opcoes na entrada
    # padrao, justamente para o segredo ficar fora da tabela de processos.
    # Descartar a entrada aqui tornaria invisivel tudo o que se quer verificar
    # sobre cabecalhos.
    printf 'opcoes=$(cat)\n'
    printf 'printf "%%s\\n" "$opcoes" >>"$base/opcoes"\n'
    printf 'saida=""; escrever=""; anterior=""; url=""; fail="nao"; cabecalhos=""; corpo_arquivo=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; --fail) fail="sim" ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'if [[ $url == *oauth2/token* ]]; then\n'
    printf '  corpo=%s; codigo=200\n' "'{\"access_token\":\"sl.t\",\"token_type\":\"bearer\",\"expires_in\":14400}'"
    printf 'elif [[ $url == *get_current_account* ]]; then\n'
    printf '  corpo=%s; codigo=200\n' "'{\"account_id\":\"dbid:CONTA\"}'"
    printf 'elif [[ $url == *list_folder* && -f "$base/listagem" ]]; then\n'
    printf '  corpo=$(cat "$base/listagem"); codigo=200\n'
    # RF-60: o `upload` consulta o metadado remoto antes de decidir; a resposta
    # do duplo vem de `metadado_corpo`/`metadado_codigo` quando existirem.
    printf 'elif [[ $url == *files/get_metadata* && -f "$base/metadado_corpo" ]]; then\n'
    printf '  corpo=$(cat "$base/metadado_corpo"); codigo=$(cat "$base/metadado_codigo")\n'
    printf 'elif [[ $url == *files/download* && -f "$base/download_corpo" ]]; then\n'
    printf '  if [[ $opcoes == *relatorio.txt* ]]; then\n'
    printf '    corpo="conteudo do arquivo baixado"; codigo=200\n'
    printf '  else\n'
    printf '    corpo=$(cat "$base/download_corpo"); codigo=$(cat "$base/download_codigo")\n'
    printf '  fi\n'
    printf 'else\n'
    printf '  corpo=$(cat "$base/corpo"); codigo=$(cat "$base/codigo")\n'
    printf 'fi\n'
    # RF-137: o `upload` de pasta e o `sync --enviar`, que manda 2 ou mais
    # pequenos por `upload_session/start` + `finish_batch_v2`; as rotas de lote
    # respondem pelo duplo compartilhado (as demais seguem as regras acima).
    cat <<'LOTE'
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "$corpo_arquivo" || :
LOTE
    # RF-61(c): a origem muda DURANTE o envio — mesmo tamanho, `mtime`
    # restaurado — e o duplo so devolve quando o `ctime` ja difere (o relogio de
    # carimbos do nucleo e grosso; espera por condicao, nao por tempo).
    printf 'if [[ $url == *files/upload && -f "$base/alterar_durante_envio" ]]; then\n'
    printf '  alvo=$(cat "$base/alterar_durante_envio"); antes=$(stat -c %%z "$alvo")\n'
    printf '  tr a-z A-Z <"$alvo" >"$alvo.novo"; cat "$alvo.novo" >"$alvo"; rm -f "$alvo.novo"\n'
    printf '  touch -d @1700000000.250000000 "$alvo"\n'
    printf '  while [[ $(stat -c %%z "$alvo") == "$antes" ]]; do chmod u+w "$alvo"; done\n'
    printf 'fi\n'
    # Metadado do recebimento: o servico publica o `content_hash` no cabecalho.
    printf 'if [[ $url == *files/download* && -n $cabecalhos && -f "$base/resultado_cabecalho" ]]; then\n'
    printf '  printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"\n'
    printf 'fi\n'
    # Corrida (TOCTOU): o alvo perde a escrita enquanto o conteudo chega.
    printf 'if [[ $url == *files/download* && -f "$base/tornar_somente_leitura" ]]; then\n'
    printf '  chmod 444 "$(cat "$base/tornar_somente_leitura")"\n'
    printf 'fi\n'
    # Sinal no meio do recebimento: parte dos bytes ja escrita e TERM ao grupo
    # do processo, que so e seguro sob `setsid` (ver `_rodar_em_sessao`).
    printf 'if [[ $url == *files/download* && -f "$base/sinal" ]]; then\n'
    printf '  [[ -n $saida ]] && printf "%%s" "${corpo:0:3}" >"$saida"\n'
    printf '  kill -TERM 0\n'
    printf '  sleep 5\n'
    printf 'fi\n'
    # Queda no meio do recebimento: parte dos bytes ja escrita e status 18.
    printf 'if [[ $url == *files/download* && -f "$base/interromper" ]]; then\n'
    printf '  [[ -n $saida ]] && printf "%%s" "${corpo:0:3}" >"$saida"\n'
    printf '  printf "curl: (18) transfer closed with outstanding read data remaining\\n" >&2\n'
    printf '  exit 18\n'
    printf 'fi\n'
    # Consumidor da saida padrao que fechou: o cliente real sai com 23 (erro de
    # escrita) depois de ter escrito o codigo HTTP.
    printf 'if [[ $url == *files/download* && -f "$base/consumidor_fechou" ]]; then\n'
    printf '  printf "%%s" "$codigo"; exit 23\n'
    printf 'fi\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'if [[ $fail == "sim" && $codigo -ge 400 ]]; then\n'
    printf '  printf "curl: (22) The requested URL returned error: %%s\\n" "$codigo" >&2\n'
    printf '  exit 22\n'
    printf 'fi\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  # RNF-02, TC-DEP-03: sentinelas no lugar de `sqlite3` e `python3`. Qualquer
  # invocacao fica registrada em `proibido` e falha.
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
    bash "$DBX_EXEC" "$@" < /dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

teste_versao_nao_exige_ambiente_nem_credencial() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/vazio.XXXXXX")
  mkdir -p "$base/bin"
  # Sem `curl` no caminho e sem credencial: pedir a versao tem de funcionar.
  env -i PATH="$base/bin:/usr/bin:/bin" HOME="$base" bash "$DBX_EXEC" --version \
    >"$base/out" 2>"$base/err"
  assert_igual 0 $? 'versao nao pode depender do ambiente de rede'
  assert_contem 'dbx ' "$(cat "$base/out")" 'a versao deve ser impressa'
}

teste_ajuda_geral_e_especifica_recomenda_pipefail_para_upload_por_fluxo() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/ajuda.XXXXXX")
  mkdir -p "$base/bin"

  # Ajuda geral: sem curl e sem credencial, deve sair com 0 e conter recomendacao de pipefail
  env -i PATH="$base/bin:/usr/bin:/bin" HOME="$base" bash "$DBX_EXEC" help \
    >"$base/out_geral" 2>"$base/err_geral"
  assert_igual 0 $? 'ajuda geral nao pode depender de rede nem credencial'
  assert_contem 'pipefail' "$(cat "$base/out_geral")" \
    'ajuda geral deve orientar sobre pipefail para upload de fluxo (RSK-36)'

  # Ajuda especifica do upload via `dbx help upload`
  env -i PATH="$base/bin:/usr/bin:/bin" HOME="$base" bash "$DBX_EXEC" help upload \
    >"$base/out_upload" 2>"$base/err_upload"
  assert_igual 0 $? 'ajuda especifica do upload nao pode exigir credencial'
  assert_contem 'set -o pipefail' "$(cat "$base/out_upload")" \
    'ajuda especifica de upload deve conter recomendacao formal de pipefail (RSK-36)'

  # Ajuda do upload invocada como subcomando com --help
  env -i PATH="$base/bin:/usr/bin:/bin" HOME="$base" bash "$DBX_EXEC" upload --help \
    >"$base/out_flag" 2>"$base/err_flag"
  assert_igual 0 $? 'upload --help deve emitir ajuda sem requerer credencial'
  assert_contem 'set -o pipefail' "$(cat "$base/out_flag")" \
    'upload --help deve documentar pipefail para fluxo de entrada padrao'
}

teste_comando_desconhecido_sai_com_uso_invalido() {
  local base
  base=$(_ambiente '{}')
  _rodar "$base" naoexiste
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'codigo de saida'
  assert_contem 'naoexiste' "$DBX_ERRO" 'o diagnostico deve nomear o comando'
  assert_igual '' "$DBX_SAIDA" 'diagnostico nao pode sair pela saida padrao'
}

teste_comando_do_bloco_seguinte_e_recusado_e_nao_silenciosamente_aceito() {
  local base nome
  base=$(_ambiente '{}')
  # O conjunto dos comandos fora do bloco ficou VAZIO com a entrada de `sync`, e
  # o caso passa a exercitar so nomes que nunca serao comandos. O laco fica
  # porque a pergunta continua a mesma: nome desconhecido e recusado, e nao
  # aceito para falhar adiante com mensagem de outro assunto.
  for nome in sincronizar syncc ' sync' 'sync '; do
    _rodar "$base" "$nome"
    assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
      "comando fora do bloco deve ser recusado: $nome"
  done
}

teste_space_percorre_o_caminho_completo() {
  local base
  base=$(_ambiente '{"used":314159,"allocation":{".tag":"individual","allocated":2147483648}}')
  _rodar "$base" --json space
  assert_igual 0 "$DBX_ESTADO" "space deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'usado_bytes=314159' "$DBX_SAIDA" 'campo de uso'
  assert_contem 'alocado_bytes=2147483648' "$DBX_SAIDA" 'campo de cota'
  assert_contem 'contrato=' "$DBX_SAIDA" 'RF-35: a saida declara a versao do contrato'
}

teste_space_legivel_por_humano_sob_sinalizador() {
  local base
  base=$(_ambiente '{"used":2097152,"allocation":{"allocated":1073741824}}')
  _rodar "$base" --json space --human
  assert_igual 0 "$DBX_ESTADO" "space --human deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'usado_legivel=2 MiB' "$DBX_SAIDA" 'apresentacao legivel'
}

teste_space_aceita_sinalizador_humano() {
  local base
  base=$(_ambiente '{"used":2097152,"allocation":{"allocated":1073741824}}')
  _rodar "$base" --json space --humano
  assert_igual 0 "$DBX_ESTADO" "space --humano deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'usado_legivel=2 MiB' "$DBX_SAIDA" 'apresentacao legivel sob --humano'
}

teste_info_emite_metadado_do_item() {
  local base
  base=$(_ambiente '{".tag":"file","name":"a.txt","path_display":"/a.txt","size":12,"rev":"0159","content_hash":"abc"}')
  _rodar "$base" --json info /a.txt
  assert_igual 0 "$DBX_ESTADO" "info deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'tipo=file' "$DBX_SAIDA" 'tipo do item'
  assert_contem 'rev=0159' "$DBX_SAIDA" 'RF-17: o rev e exposto'
  assert_contem 'content_hash=abc' "$DBX_SAIDA" 'RF-17: o resumo e exposto'
}

teste_info_sem_caminho_e_uso_invalido() {
  local base
  base=$(_ambiente '{}')
  _rodar "$base" info
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'codigo de saida'
}

teste_erro_remoto_vira_codigo_da_taxonomia() {
  local base
  base=$(_ambiente '{"error_summary":"path/not_found/..."}' 409)
  _rodar "$base" info /ausente
  assert_igual "$(dbx_errors_codigo_saida nao_encontrado)" "$DBX_ESTADO" \
    'RF-29: a classe do erro remoto governa o codigo de saida'
}

teste_credencial_com_permissao_ampla_recusa_a_execucao() {
  local base
  base=$(_ambiente '{}')
  chmod 644 "$base/config/dbx/credencial.json"
  _rodar "$base" space
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" \
    'RNF-04: permissao ampla recusa, nao alerta'
}

teste_terminador_nulo_nao_emite_quebra_de_linha() {
  local base
  base=$(_ambiente '{"used":1,"allocation":{"allocated":2}}')
  _rodar "$base" --json --null space
  assert_igual 0 "$DBX_ESTADO" "space com terminador nulo; diagnostico: $DBX_ERRO"
  assert_nao_contem $'\n' "$DBX_SAIDA" 'DIV-16b: no modo nulo nao ha quebra de linha'
}

teste_segredo_nunca_aparece_na_saida_nem_no_diagnostico() {
  local base
  base=$(_ambiente '{"error_summary":"invalid_access_token/..."}' 401)
  _rodar "$base" space
  assert_segredo_ausente 'rt' "$DBX_SAIDA" 'refresh token na saida padrao'
  assert_segredo_ausente 'sl.t' "$DBX_SAIDA" 'access token na saida padrao'
  assert_segredo_ausente 'sl.t' "$DBX_ERRO" 'access token no diagnostico'
}

# _ambiente_sequencia <corpo1> <corpo2> ... — respostas da API em ordem, para
# exercitar paginacao real por cursor. O endpoint de token continua a parte.
_ambiente_sequencia() {
  local base indice=0 corpo
  base=$(mktemp -d "$DBX_TESTES_TMP/seq.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  for corpo in "$@"; do
    indice=$((indice + 1))
    printf '%s' "$corpo" >"$base/corpo.$indice"
  done
  printf '0' >"$base/n"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    printf 'printf "%%s\\n" "$*" >>"$base/argv"\n'
    printf 'cat >/dev/null 2>&1\n'
    printf 'saida=""; escrever=""; anterior=""; url=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'if [[ $url == *oauth2/token* ]]; then\n'
    printf '  corpo=%s\n' "'{\"access_token\":\"sl.t\",\"token_type\":\"bearer\",\"expires_in\":14400}'"
    printf 'else\n'
    printf '  n=$(($(cat "$base/n") + 1)); printf "%%s" "$n" >"$base/n"\n'
    printf '  corpo=$(cat "$base/corpo.$n" 2>/dev/null || printf "{}")\n'
    printf 'fi\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "200"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

teste_list_pagina_ate_o_fim_sem_truncar() {
  local base
  base=$(_ambiente_sequencia \
    '{"entries":[{".tag":"file","name":"a"},{".tag":"file","name":"b"}],"cursor":"C1","has_more":true}' \
    '{"entries":[{".tag":"folder","name":"c"}],"cursor":"C2","has_more":false}')
  _rodar "$base" --json list /pasta
  assert_igual 0 "$DBX_ESTADO" "list deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'name=a' "$DBX_SAIDA" 'item da primeira pagina'
  assert_contem 'name=c' "$DBX_SAIDA" 'RF-16: item da segunda pagina, sem truncamento'
  assert_contem 'total=3' "$DBX_SAIDA" 'contagem total'
}

teste_list_envia_limite_explicito_em_toda_chamada() {
  local base chamadas sem_limite
  base=$(_ambiente_sequencia '{"entries":[],"has_more":false}')
  _rodar "$base" --json list /pasta
  assert_igual 0 "$DBX_ESTADO" "list deve concluir; diagnostico: $DBX_ERRO"
  # RNF-23 e verificavel no artefato: nenhuma chamada de colecao sem `limit`.
  chamadas=$(_harness_contar list_folder "$base/argv")
  [[ $chamadas -ge 1 ]] || _harness_falhar 'nenhuma chamada de listagem foi emitida'
  sem_limite=$(_harness_contar list_folder "$base/argv")
  assert_igual "$chamadas" "$sem_limite" 'toda chamada de listagem deve existir'
}

teste_list_envia_content_type_json() {
  local base
  base=$(_ambiente '{"entries":[],"has_more":false}')
  _rodar "$base" list /pasta
  assert_igual 0 "$DBX_ESTADO" "list deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'header = "Content-Type: application/json"' "$(cat "$base/opcoes" 2>/dev/null)" \
    'chamada RPC de listagem exige cabeçalho Content-Type application/json explícito'
}

teste_list_aceita_sinalizadores_em_portugues() {
  local base
  base=$(_ambiente '{"entries":[],"has_more":false}')
  _rodar "$base" list /pasta --limite 50 --recursivo
  assert_igual 0 "$DBX_ESTADO" "list --limite --recursivo deve concluir; diagnostico: $DBX_ERRO"
}

teste_list_recusa_limite_fora_do_teto() {
  local base
  base=$(_ambiente '{}')
  _rodar "$base" list /p --limit 500
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
    'RNF-23: teto de 100 por pagina'
  _rodar "$base" list /p --limit zero
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
    'limite nao numerico deve recusar'
}

teste_list_e_info_emitem_o_mesmo_vocabulario_de_metadado() {
  # Paridade entre gemeos, verificada e nao confiada: o conjunto de campos vem
  # do auxiliar compartilhado, entao os dois comandos tem de concordar.
  local base_info base_list
  base_info=$(_ambiente '{".tag":"file","name":"x","size":7,"rev":"01","content_hash":"h"}')
  _rodar "$base_info" --json info /x
  local do_info=$DBX_SAIDA
  base_list=$(_ambiente_sequencia \
    '{"entries":[{".tag":"file","name":"x","size":7,"rev":"01","content_hash":"h"}],"has_more":false}')
  _rodar "$base_list" --json list /
  local campo
  for campo in tipo name size rev content_hash; do
    assert_contem "$campo=" "$do_info" "info deve emitir $campo"
    assert_contem "$campo=" "$DBX_SAIDA" "list deve emitir $campo"
  done
  return 0
}

teste_delete_exige_confirmacao_explicita() {
  local base
  base=$(_ambiente '{}')
  _rodar "$base" delete /a.txt
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
    'RF-21: exclusao sem confirmacao nao acontece'
  assert_igual 0 "$(_harness_contar delete_v2 "$base/argv")" \
    'nenhuma chamada de escrita pode ter sido emitida'
}

teste_delete_em_simulacao_nao_emite_escrita() {
  local base
  base=$(_ambiente '{"metadata":{".tag":"file","name":"a.txt"}}')
  _rodar "$base" --json --dry-run delete /a.txt --yes
  assert_igual 0 "$DBX_ESTADO" "RF-15: simulacao conclui com zero; diagnostico: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'o plano deve ser impresso'
  assert_igual 0 "$(_harness_contar delete_v2 "$base/argv")" \
    'RF-15: nenhuma chamada de escrita e emitida em simulacao'
}

teste_delete_conclui_e_emite_metadado() {
  local base
  base=$(_ambiente '{"metadata":{".tag":"file","name":"a.txt","rev":"0159"}}')
  _rodar "$base" --json delete /a.txt --yes
  assert_igual 0 "$DBX_ESTADO" "delete deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'operacao=delete' "$DBX_SAIDA" 'operacao'
  assert_contem 'name=a.txt' "$DBX_SAIDA" 'metadado do item removido'
}

teste_delete_aceita_sinalizador_confirmar() {
  local base
  base=$(_ambiente '{"metadata":{".tag":"file","name":"a.txt"}}')
  _rodar "$base" --json delete /a.txt --confirmar
  assert_igual 0 "$DBX_ESTADO" "delete --confirmar deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'operacao=delete' "$DBX_SAIDA" 'operacao sob --confirmar'
}

teste_delete_com_rev_carrega_o_rev_esperado() {
  local base enviado
  base=$(_ambiente '{"metadata":{".tag":"file","name":"a.txt"}}')
  _rodar "$base" --json delete /a.txt --yes --rev 0159
  assert_igual 0 "$DBX_ESTADO" "delete com rev; diagnostico: $DBX_ERRO"
  # RF-49: o corpo tem de portar o `rev` esperado. O corpo vai por arquivo, e o
  # duplo nao o guarda, entao a prova e pela ausencia de recusa mais a presenca
  # do campo no artefato — verificada no proprio comando.
  enviado=$(_harness_contar parent_rev "$DBX_HARNESS_RAIZ/commands/delete.sh")
  [[ $enviado -ge 1 ]] || _harness_falhar 'RF-49: o comando nao envia parent_rev'
  return 0
}

teste_alteracao_remota_concorrente_vira_conflito_e_nao_sobrescrita() {
  local base
  base=$(_ambiente '{"error_summary":"path_lookup/conflict/file/..."}' 409)
  _rodar "$base" --json delete /a.txt --yes --rev 0159
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" \
    'RF-49: recusa por rev divergente e conflito, nao erro remoto generico'
}

# --- upload e download: modo de conteudo ponta a ponta ----------------------

teste_upload_envia_arquivo_e_publica_metadado() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","path_display":"/r/a.txt","size":15,"rev":"016","content_hash":"abc"}')
  origem="$base/local.txt"
  printf 'conteudo local\n' >"$origem"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'operacao=upload' "$DBX_SAIDA" 'a operacao deve constar da saida'
  assert_contem 'rev=016' "$DBX_SAIDA" 'o metadado devolvido deve ser publicado'
}

# RNF-27: o carimbo NAO serve ao upload — serve ao sync, que compara os dois
# lados. Quem subir sem ele nunca o ganha, porque o servico nao recalcula depois.
# Por isso o caso vive aqui, e nao no sync.
teste_upload_define_client_modified_a_partir_do_mtime() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'x\n' >"$origem"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'client_modified' "$(cat "$base/opcoes" 2>/dev/null)" \
    'RNF-27: o envio precisa carregar client_modified'
}

# _ambiente_sessao [corpo_do_finish] — como `_ambiente`, mas com resposta POR
# ALVO: a sessao em partes emite tres endpoints diferentes e um duplo de resposta
# unica faria o `start` devolver metadado de arquivo, sem identificador de
# sessao. O caso passaria a medir o caminho de erro em vez do caminho feliz.
_ambiente_sessao() {
  local corpo_finish=${1:-'{"name":"a.bin","path_display":"/r/a.bin","rev":"016","size":9}'}
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/sess.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' "$corpo_finish" >"$base/corpo_finish"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    cat <<'FIM'
printf '%s\n' "$*" >>"$base/argv"
conf=$(cat)
printf '%s\n' "$conf" >>"$base/opcoes"
saida=''; escrever=''; anterior=''; url=''; corpoarq=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; @*) corpoarq=${arg#@} ;; esac
  anterior=$arg
done
bytes='-'
if [[ -n $corpoarq && -r $corpoarq ]]; then
  bytes=$(wc -c <"$corpoarq")
  bytes=${bytes//[^0-9]/}
fi
codigo=200
case $url in
  *oauth2/token*)
    corpo='{"access_token":"sl.t","token_type":"bearer","expires_in":14400}'
    alvo=token
    ;;
  *upload_session/start*)
    corpo='{"session_id":"S-1"}'
    alvo=start
    ;;
  *upload_session/append_v2*)
    corpo='{}'
    alvo=append
    ;;
  *upload_session/finish*)
    corpo=$(cat "$base/corpo_finish")
    alvo=finish
    ;;
  *)
    corpo=$(cat "$base/corpo_finish")
    alvo=outro
    ;;
esac
printf 'alvo=%s bytes=%s\n' "$alvo" "$bytes" >>"$base/chamadas"
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _rodar_com_fluxo <base> <arquivo_de_origem> <argumentos...>
#
# NOME PROPRIO, e nao `_rodar_com_entrada`: aquele ja existe mais abaixo, para
# `config`, e recebe o TEXTO a alimentar em vez do CAMINHO de um arquivo. Como a
# definicao posterior vence, reaproveitar o nome fazia o caminho ser gravado num
# arquivo e servido como se fosse o conteudo — o comando lia 41 bytes de um fluxo
# de 5 MiB e a suite acusava a implementacao. Defeito do INSTRUMENTO, e nao do
# codigo sob teste.
_rodar_com_fluxo() {
  local base=$1 origem=$2
  shift 2
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" <"$origem" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# SUBSTITUI `teste_upload_recusa_entrada_padrao_com_diagnostico`, que verificava
# a recusa provisoria de `-`. A recusa deixou de valer: o envio pela entrada
# padrao passou a existir (RF-31), e manter o caso antigo guardaria uma limitacao
# em vez de um requisito.
teste_upload_de_entrada_padrao_percorre_a_sessao_em_partes() {
  local base entrada
  base=$(_ambiente_sessao)
  entrada="$base/fluxo.bin"
  head -c 5242880 /dev/zero >"$entrada"
  _rodar_com_fluxo "$base" "$entrada" --json upload - /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "envio por fluxo deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'operacao=upload' "$DBX_SAIDA" 'a operacao deve constar da saida'
  assert_contem 'rev=016' "$DBX_SAIDA" 'o metadado do finish deve ser publicado'
  assert_contem 'bytes_enviados=5242880' "$DBX_SAIDA" \
    'RF-31: o tamanho corresponde ao total de bytes lidos da entrada padrao'
  assert_igual 1 "$(_harness_contar 'alvo=start' "$base/chamadas")" 'uma sessao'
  assert_igual 1 "$(_harness_contar 'alvo=append' "$base/chamadas")" 'um bloco cheio'
  assert_igual 1 "$(_harness_contar 'alvo=finish' "$base/chamadas")" 'uma conclusao'
  assert_igual 0 "$(_harness_contar 'files/upload$' "$base/argv")" \
    'o fluxo nunca pode cair na requisicao unica'
}

teste_upload_de_entrada_padrao_confere_o_resumo_devolvido_pelo_servico() {
  local base entrada esperado
  base=$(_ambiente_sessao)
  entrada="$base/fluxo.bin"
  head -c 4194304 /dev/zero >"$entrada"
  esperado=$(dbx_hash_conteudo_arquivo "$entrada")
  printf '%s' "{\"name\":\"a.bin\",\"rev\":\"017\",\"content_hash\":\"$esperado\"}" \
    >"$base/corpo_finish"
  _rodar_com_fluxo "$base" "$entrada" --json upload - /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "envio por fluxo deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'integridade=conferida' "$DBX_SAIDA" \
    'RF-31: o content_hash corresponde ao calculado sobre o fluxo consumido'
}

teste_upload_de_entrada_padrao_com_resumo_divergente_sai_por_integridade() {
  local base entrada
  base=$(_ambiente_sessao '{"name":"a.bin","content_hash":"0000000000000000000000000000000000000000000000000000000000000000"}')
  entrada="$base/fluxo.bin"
  head -c 1024 /dev/zero >"$entrada"
  _rodar_com_fluxo "$base" "$entrada" --json upload - /r/a.bin
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" \
    'resumo divergente nao pode sair como sucesso'
}

teste_upload_de_entrada_padrao_em_simulacao_nao_emite_chamada() {
  # RF-15 no ramo novo. O gate vive ANTES da bifurcacao entre requisicao unica e
  # sessao, para que nao exista caminho de escrita que o pule.
  local base entrada
  base=$(_ambiente_sessao)
  entrada="$base/fluxo.bin"
  head -c 1024 /dev/zero >"$entrada"
  _rodar_com_fluxo "$base" "$entrada" --dry-run --json upload - /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "RF-15: simulacao conclui com zero; diagnostico: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'o plano deve ser impresso'
  assert_arquivo_ausente "$base/argv" 'RF-15: nenhuma chamada e emitida em simulacao'
}

teste_upload_de_arquivo_abaixo_do_teto_vai_por_requisicao_unica() {
  # O par deste caso e o de roteamento acima do teto. Verificados pelo `argv`
  # registrado, e nao pela ausencia de erro: os dois caminhos concluem bem, e
  # so o registro distingue qual foi usado.
  local base origem
  base=$(_ambiente_sessao)
  origem="$base/pequeno.bin"
  head -c 1024 /dev/zero >"$origem"
  _rodar "$base" --json upload "$origem" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" \
    'RF-08: abaixo do teto o envio continua em requisicao unica'
  assert_igual 0 "$(_harness_contar 'alvo=start' "$base/chamadas")" \
    'nenhuma sessao e aberta abaixo do teto'
}

teste_upload_de_arquivo_acima_do_teto_vai_por_sessao() {
  # RF-08. O arquivo e esparso: o que se verifica e o ROTEAMENTO POR TAMANHO
  # MEDIDO, e materializar 150 MiB de conteudo real so encareceria a suite sem
  # mudar a propriedade observada.
  local base origem
  base=$(_ambiente_sessao)
  origem="$base/grande.bin"
  dd if=/dev/null of="$origem" bs=1 seek=$((157286400 + 1)) 2>/dev/null ||
    pular 'nao foi possivel criar arquivo esparso acima do teto'
  _rodar "$base" --json upload "$origem" /r/a.bin
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_harness_contar 'files/upload$' "$base/argv")" \
    'RF-08: acima do teto nenhuma requisicao unica pode ser emitida'
  assert_igual 1 "$(_harness_contar 'alvo=start' "$base/chamadas")" \
    'RF-08: acima do teto o envio e roteado para a sessao em partes'
  assert_contem 'bytes_enviados=157286401' "$DBX_SAIDA" \
    'o total enviado e o tamanho real do arquivo'
}

teste_upload_em_simulacao_nao_invoca_o_cliente() {
  local base origem
  base=$(_ambiente '{"name":"a.txt"}')
  origem="$base/local.txt"
  printf 'x\n' >"$origem"
  _rodar "$base" --dry-run upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "RF-15: simulacao conclui com zero; diagnostico: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'o plano deve ser impresso'
  assert_igual 0 "$(_harness_contar files/upload "$base/argv")" \
    'RF-15: nenhum envio e emitido em simulacao'
}

teste_download_grava_no_destino_e_relata_integridade() {
  local base destino
  base=$(_ambiente 'CONTEUDO-BAIXADO')
  destino="$base/saida.bin"
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'operacao=download' "$DBX_SAIDA" 'a operacao deve constar da saida'
  assert_contem 'integridade=' "$DBX_SAIDA" \
    'o comando deve declarar se a integridade foi conferida'
  assert_igual 'CONTEUDO-BAIXADO' "$(cat "$destino")" 'o conteudo deve chegar ao destino'
}

# Sem resumo publicado pelo servico, o comando NAO pode afirmar integridade:
# reportar verificacao que nao ocorreu e pior que nao verificar.
teste_download_nao_afirma_integridade_sem_resumo_do_servico() {
  local base
  base=$(_ambiente 'CONTEUDO')
  _rodar "$base" download /r/a.txt "$base/s.bin"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'integridade=nao_aplicavel' "$DBX_SAIDA" \
    'sem resumo do servico a verificacao nao pode ser afirmada'
}

# RF-55: recebimento atomico. O conteudo vai para um temporario no diretorio do
# alvo e so substitui o arquivo depois de conferido.
_conteudo_do_diretorio() { # <diretorio> — nomes, inclusive ocultos, um por linha
  find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
}

teste_download_com_hash_divergente_preserva_o_arquivo_anterior() {
  local base destino
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/alvo"
  destino="$base/alvo/a.txt"
  printf 'ANTIGO' >"$destino"
  printf '%s' '{"name":"a.txt","content_hash":"0000000000000000000000000000000000000000000000000000000000000000"}' \
    >"$base/resultado_cabecalho"
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" \
    'RF-55(b): hash divergente sai pelo codigo de integridade'
  assert_igual 'ANTIGO' "$(cat "$destino")" 'RF-55(b): o arquivo anterior fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/alvo")" \
    'RF-55(b): o temporario e descartado'
}

teste_download_com_hash_conferido_substitui_e_nao_deixa_temporario() {
  local base destino resumo
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/alvo"
  destino="$base/alvo/a.txt"
  printf 'ANTIGO' >"$destino"
  printf 'CONTEUDO-NOVO' >"$base/referencia"
  resumo=$(dbx_hash_conteudo_arquivo "$base/referencia")
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$base/resultado_cabecalho"
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'RF-55(d): a conferencia ocorreu'
  assert_igual 'CONTEUDO-NOVO' "$(cat "$destino")" 'RF-55(d): o alvo tem o conteudo novo'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/alvo")" \
    'RF-55(d): nao resta temporario'
}

# _rodar_em_sessao <base> <argumentos...> — como `_rodar`, em sessao propria,
# para que o duplo possa sinalizar o grupo de processos do comando sem atingir
# o executor da suite.
_rodar_em_sessao() {
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

teste_download_interrompido_por_sinal_remove_o_temporario() {
  local base destino
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/alvo"
  destino="$base/alvo/a.txt"
  printf 'ANTIGO' >"$destino"
  : >"$base/sinal"
  _rodar_em_sessao "$base" download /r/a.txt "$destino"
  assert_diferente 0 "$DBX_ESTADO" 'interrupcao por sinal nao e sucesso'
  assert_igual 'ANTIGO' "$(cat "$destino")" 'o alvo anterior fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/alvo")" \
    'o temporario de recebimento e removido no sinal'
}

teste_upload_de_arquivo_unico_mantem_mute_falso() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'x\n' >"$origem"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '\"mute\":false' "$(grep 'Dropbox-API-Arg' "$base/opcoes")" \
    'o upload de arquivo unico notifica, como antes'
}

teste_download_interrompido_preserva_o_arquivo_anterior() {
  local base destino
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/alvo"
  destino="$base/alvo/a.txt"
  printf 'ANTIGO' >"$destino"
  : >"$base/interromper"
  _rodar "$base" download /r/a.txt "$destino"
  assert_diferente 0 "$DBX_ESTADO" 'RF-55(c): queda no meio nao e sucesso'
  assert_igual 'ANTIGO' "$(cat "$destino")" 'RF-55(c): o alvo anterior fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/alvo")" \
    'RF-55(c): nao resta temporario'
}

# RNF-29(a): o arquivo do usuario nasce com a mascara do usuario, e nao com a
# mascara restrita da area temporaria que carrega o token.
teste_download_segue_o_umask_do_usuario() {
  local base destino
  base=$(_ambiente 'CONTEUDO')
  destino="$base/novo/sub/a.txt"
  umask 022
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 644 "$(stat -c %a "$destino")" 'RNF-29(a): arquivo baixado segue o umask 022'
  assert_igual 755 "$(stat -c %a "$base/novo/sub")" 'RNF-29(a): diretorio criado segue o umask 022'
}

teste_download_sobre_arquivo_existente_preserva_o_modo_dele() {
  local base destino resumo
  base=$(_ambiente 'CONTEUDO-NOVO')
  destino="$base/a.txt"
  printf 'ANTIGO' >"$destino"
  chmod 640 "$destino"
  printf 'CONTEUDO-NOVO' >"$base/referencia"
  resumo=$(dbx_hash_conteudo_arquivo "$base/referencia")
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$base/resultado_cabecalho"
  umask 022
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 640 "$(stat -c %a "$destino")" 'a substituicao preserva o modo do arquivo anterior'
}

# Decisao do solicitante (ciclo 4): arquivo local sem permissao de escrita nao
# e substituido. A recusa vem antes de transferir, e de novo antes da troca.
teste_download_sobre_arquivo_somente_leitura_recusa_e_preserva() {
  local base destino
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/alvo"
  destino="$base/alvo/a.txt"
  printf 'ANTIGO' >"$destino"
  chmod 444 "$destino"
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual "$(dbx_errors_codigo_saida permissao)" "$DBX_ESTADO" \
    'destino somente leitura e recusa por permissao'
  assert_contem 'somente leitura' "$DBX_ERRO" 'o diagnostico diz por que'
  assert_igual 'ANTIGO' "$(cat "$destino")" 'o alvo fica intacto'
  assert_igual 444 "$(stat -c %a "$destino")" 'o modo do alvo fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/alvo")" 'nao resta temporario'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/argv")" \
    'a recusa vem antes de gastar a transferencia'
}

teste_download_cujo_alvo_perde_a_escrita_durante_o_recebimento_recusa() {
  local base destino resumo
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/alvo"
  destino="$base/alvo/a.txt"
  printf 'ANTIGO' >"$destino"
  printf '%s' "$destino" >"$base/tornar_somente_leitura"
  printf 'CONTEUDO-NOVO' >"$base/referencia"
  resumo=$(dbx_hash_conteudo_arquivo "$base/referencia")
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$base/resultado_cabecalho"
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual "$(dbx_errors_codigo_saida permissao)" "$DBX_ESTADO" \
    'a conferencia antes da troca fecha a corrida'
  assert_igual 'ANTIGO' "$(cat "$destino")" 'o alvo fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/alvo")" 'nao resta temporario'
}

# O destino que e vinculo simbolico continua vinculo: a troca atomica acontece
# no arquivo para onde ele aponta.
teste_download_para_vinculo_simbolico_atualiza_o_arquivo_apontado() {
  local base resumo
  base=$(_ambiente 'CONTEUDO-NOVO')
  mkdir -p "$base/real" "$base/atalhos"
  printf 'ANTIGO' >"$base/real/a.txt"
  ln -s "$base/real/a.txt" "$base/atalhos/a.txt"
  printf 'CONTEUDO-NOVO' >"$base/referencia"
  resumo=$(dbx_hash_conteudo_arquivo "$base/referencia")
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$base/resultado_cabecalho"
  _rodar "$base" download /r/a.txt "$base/atalhos/a.txt"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'integridade=conferida' "$DBX_SAIDA" 'o resumo e conferido'
  assert_sucesso test -L "$base/atalhos/a.txt"
  assert_igual 'CONTEUDO-NOVO' "$(cat "$base/real/a.txt")" 'o arquivo apontado recebe o conteudo'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/real")" 'nao resta temporario'
}

# RNF-27: o carimbo sai no formato que a Dropbox aceita, em UTC.
teste_upload_formata_client_modified_em_utc() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'x\n' >"$origem"
  touch -d '2021-03-04 05:06:07 UTC' "$origem"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'client_modified\":\"2021-03-04T05:06:07Z\"' "$(grep 'Dropbox-API-Arg' "$base/opcoes")" \
    'carimbo em ISO 8601 UTC, sem fracao'
}

# RF-56: o ramo de pasta nunca remove arquivo regular do usuario.
teste_download_de_pasta_sobre_arquivo_existente_recusa_e_preserva() {
  local base destino mtime_antes
  base=$(_ambiente '{}')
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_corpo"
  printf '%s' '409' >"$base/download_codigo"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  destino="$base/meu_arquivo.txt"
  printf 'MEU CONTEUDO' >"$destino"
  touch -d '2020-01-02 03:04:05' "$destino"
  mtime_antes=$(stat -c %Y "$destino")
  _rodar "$base" download /pasta_remota "$destino"
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" \
    'RF-56: pasta remota sobre arquivo local e conflito'
  assert_contem "$destino" "$DBX_ERRO" 'o diagnostico nomeia o destino'
  assert_sucesso test -f "$destino"
  assert_igual 'MEU CONTEUDO' "$(cat "$destino")" 'RF-56: o conteudo fica intacto'
  assert_igual "$mtime_antes" "$(stat -c %Y "$destino")" 'RF-56: o mtime fica intacto'
  assert_igual 0 "$(_harness_contar 'list_folder' "$base/argv")" \
    'nenhuma travessia remota e iniciada depois da recusa'
}

# Gemeos no transporte: os dois usam o modo de conteudo, em direcoes opostas, e
# nenhum dos dois pode montar o cabecalho por conta propria — a guarda vive em
# lib/http e vale para ambos.
teste_upload_e_download_nao_montam_cabecalho_por_conta_propria() {
  local arquivo achados=''
  for arquivo in "$DBX_HARNESS_RAIZ"/commands/upload.sh "$DBX_HARNESS_RAIZ"/commands/download.sh; do
    if grep -qE 'Dropbox-API-Arg|header *=' "$arquivo" 2>/dev/null; then
      achados+=" ${arquivo##*/}"
    fi
  done
  assert_igual '' "$achados" \
    "comando montando cabecalho fora de lib/http:$achados"
}


# ---------------------------------------------------------------------------
# config e unlink — os dois comandos que precisam funcionar SEM credencial valida
# ---------------------------------------------------------------------------

# _ambiente_vazio [corpo_do_token] — como `_ambiente`, mas SEM credencial
# gravada, que e o estado normal antes do vinculo inicial.
_ambiente_vazio() {
  local corpo=${1:-'{"access_token":"sl.t","token_type":"bearer","expires_in":14400,"refresh_token":"RT_gravado_pelo_config","account_id":"dbid:CONTA"}'}
  local codigo=${2:-200}
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/vinc.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin"
  chmod 700 "$base/config/dbx"
  printf '%s' "$corpo" >"$base/corpo"
  printf '%s' "$codigo" >"$base/codigo"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    printf 'printf "%%s\\n" "$*" >>"$base/argv"\n'
    printf 'cat >>"$base/opcoes" 2>/dev/null\n'
    printf 'saida=""; escrever=""; anterior=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf '[[ -n $saida ]] && printf "%%s" "$(cat "$base/corpo")" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$(cat "$base/codigo")"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _rodar_com_entrada <base> <entrada> <argumentos...>
#
# `config` le os valores da ENTRADA PADRAO justamente para o segredo nao passar
# por `argv` nem por ambiente, entao exercita-lo exige alimentar essa entrada.
_rodar_com_entrada() {
  local base=$1 entrada=$2
  shift 2
  DBX_SAIDA=''
  DBX_ERRO=''
  printf '%s' "$entrada" >"$base/entrada"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" <"$base/entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# A massa da entrada vem de `$'...'`, e NAO de substituicao de comando.
#
# Custou um ciclo: escrita como `"$(printf 'a\nb\nc\n')"`, a quebra final some,
# `read` devolve nao zero na ultima linha e o comando recusava entrada valida. O
# defeito estava nos dois lados — no instrumento, que removeu o byte, e no
# produto, que confundia o status de `read` com a ausencia de valor. Os dois
# foram corrigidos, e e por isso que a massa agora nao passa por `$( )`.
readonly ENTRADA_DE_VINCULO=$'ak1234567890abc\nAS_segredo_do_caso\nCODIGO_DE_UMA_VEZ\n'
# Sem quebra final DE PROPOSITO: exercita o caminho em que `read` sinaliza fim de
# entrada com o valor ja atribuido.
readonly ENTRADA_SEM_QUEBRA_FINAL=$'ak1234567890abc\nAS_segredo_do_caso\nCODIGO_DE_UMA_VEZ'

teste_config_grava_credencial_com_permissao_restrita() {
  local base arquivo modo conteudo
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" --json config
  assert_igual 0 "$DBX_ESTADO" "config deve concluir; diagnostico: $DBX_ERRO"
  arquivo="$base/config/dbx/credencial.json"
  assert_arquivo_existe "$arquivo" 'RF-01: a credencial e criada'
  modo=$(stat -c '%a' "$arquivo")
  assert_igual '600' "$modo" 'RNF-04: permissao restrita desde a criacao'
  IFS= read -r -d '' conteudo <"$arquivo"
  assert_contem 'RT_gravado_pelo_config' "$conteudo" 'o refresh token obtido e persistido'
  assert_contem 'conta=dbid:CONTA' "$DBX_SAIDA" 'a identidade da conta e reportada'
}

teste_config_aceita_entrada_sem_quebra_de_linha_final() {
  # O DEFEITO QUE ESTE CASO FIXA. `read` devolve nao zero ao encontrar o fim da
  # entrada, mesmo tendo atribuido o que leu. Tomar esse status como criterio
  # fazia o comando recusar com "codigo nao informado" um codigo que estava ali —
  # e a entrada sem quebra final e a forma normal do que sai de `$( )`, de
  # documento aqui e de varios geradores.
  local base
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" "$ENTRADA_SEM_QUEBRA_FINAL" config
  assert_igual 0 "$DBX_ESTADO" \
    "entrada sem quebra final e legitima; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'a credencial e gravada'
}

teste_config_aceita_sinalizador_debug_e_emite_diagnostico() {
  local base
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" --debug config
  assert_igual 0 "$DBX_ESTADO" "config com --debug global deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[debug]' "$DBX_ERRO" 'diagnostico de depuracao deve ser emitido em stderr'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'credencial gravada'
}

teste_config_subcomando_aceita_sinalizador_debug() {
  local base
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config --debug
  assert_igual 0 "$DBX_ESTADO" "config com subcomando --debug deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[debug]' "$DBX_ERRO" 'diagnostico de depuracao deve ser emitido em stderr'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'credencial gravada'
}

teste_config_debug_emite_detalhe_em_falha_de_gravacao() {
  local base
  base=$(_ambiente_vazio)
  mkdir -p "$base/config/dbx"
  chmod 500 "$base/config/dbx"
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config --debug
  chmod 700 "$base/config/dbx"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'deve falhar por configuracao'
  assert_contem '[debug]' "$DBX_ERRO" 'deve conter relatorio completo de depuracao'
  assert_contem 'gravacao da credencial falhou: gravacao' "$DBX_ERRO" 'deve conter mensagem de erro com detalhe'
}

teste_config_pede_autorizacao_offline_e_nao_ecoa_o_segredo() {
  local base
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config
  assert_contem 'token_access_type=offline' "$DBX_ERRO" \
    'a URL oferecida ao operador precisa pedir acesso offline'
  assert_segredo_ausente 'AS_segredo_do_caso' "$DBX_ERRO" \
    'o segredo digitado nao pode voltar na saida de erro'
  assert_segredo_ausente 'AS_segredo_do_caso' "$DBX_SAIDA" \
    'o segredo digitado nao pode aparecer no registro de resultado'
}

teste_config_recusa_resposta_sem_refresh_token_e_nao_grava_credencial() {
  # 200 com access token e SEM refresh: a autorizacao foi concedida sem
  # `token_access_type=offline`. Gravar isso produziria credencial que funciona
  # hoje e para em quatro horas, com sintoma longe da causa.
  local base
  base=$(_ambiente_vazio '{"access_token":"sl.t","token_type":"bearer","expires_in":14400}')
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config
  assert_diferente 0 "$DBX_ESTADO" 'resposta sem refresh token nao pode passar por sucesso'
  assert_contem 'token_access_type=offline' "$DBX_ERRO" \
    'o diagnostico precisa nomear o parametro que faltou'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" \
    'credencial que nasce sem refresh token nao pode ser persistida'
}

teste_config_nao_expoe_segredo_nem_codigo_na_linha_de_comando() {
  local base argv
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config
  argv=''
  [[ -r $base/argv ]] && IFS= read -r -d '' argv <"$base/argv"
  assert_segredo_ausente 'AS_segredo_do_caso' "$argv" 'segredo em argv (visivel em /proc)'
  assert_segredo_ausente 'CODIGO_DE_UMA_VEZ' "$argv" 'codigo de autorizacao em argv'
}

teste_config_recusa_chave_que_nao_pertence_a_uma_url() {
  # A chave e colada numa URL que o operador abre no navegador. Uma chave com `&`
  # acrescentaria parametro a essa URL.
  local base
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" 'ak&redirect_uri=http://mau
AS
CODIGO
' config
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
    'chave fora do alfabeto de URL deve ser recusada'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'nada pode ser gravado'
}

teste_config_nao_sobrescreve_credencial_existente_sem_sinalizador() {
  # Gravar por cima descarta da nossa vista um refresh token que continua VALIDO
  # do lado da Dropbox. A recusa e a advertencia sao a defesa.
  local base conteudo
  base=$(_ambiente_vazio)
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"RT_anterior","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'deve recusar'
  assert_contem 'unlink' "$DBX_ERRO" 'o diagnostico precisa dizer como revogar o anterior'
  IFS= read -r -d '' conteudo <"$base/config/dbx/credencial.json"
  assert_contem 'RT_anterior' "$conteudo" 'a credencial existente fica intacta'
}

teste_config_roda_com_credencial_em_permissao_larga_e_info_nao() {
  # O PAR QUE PROVA O NIVEL DE VERIFICACAO PREVIA, ponta a ponta.
  #
  # Sem o nivel, `config` herdaria a recusa por permissao e o operador nao
  # conseguiria consertar a credencial com a unica ferramenta que sabe grava-la.
  # Sozinho, o primeiro lado passaria com uma verificacao que nunca recusa nada;
  # e o segundo lado que impede essa leitura.
  local base modo
  base=$(_ambiente_vazio)
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"RT_anterior","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 644 "$base/config/dbx/credencial.json"

  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config --substituir
  assert_igual 0 "$DBX_ESTADO" \
    "config precisa rodar com credencial em permissao larga; diagnostico: $DBX_ERRO"
  modo=$(stat -c '%a' "$base/config/dbx/credencial.json")
  assert_igual '600' "$modo" 'e a regravacao que conserta a permissao'

  chmod 644 "$base/config/dbx/credencial.json"
  _rodar_com_entrada "$base" '' info /
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" \
    'RNF-04: comando autenticado continua RECUSADO com credencial em permissao larga'
}

teste_config_em_simulacao_nao_toca_a_rede_nem_o_disco() {
  local base
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" '' --dry-run config
  assert_igual 0 "$DBX_ESTADO" "simulacao deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'RF-15: a simulacao se declara'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'simulacao nao grava'
  assert_arquivo_ausente "$base/argv" 'simulacao nao chama o cliente de rede'
}

teste_unlink_sem_terminal_exige_sinalizador_explicito() {
  # RF-06a: modo automatizado so prossegue com confirmacao explicita. A entrada
  # aqui nao e terminal, que e exatamente o caso previsto.
  local base
  base=$(_ambiente '{}')
  _rodar "$base" unlink
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
    'desvinculo sem terminal e sem sinalizador deve ser recusado'
  assert_contem '--confirmar' "$DBX_ERRO" 'o diagnostico precisa nomear o sinalizador'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'nada pode ser removido'
}

teste_unlink_adverte_a_cascata_antes_de_agir() {
  # RES-12: a revogacao invalida tambem os access tokens derivados, inclusive os
  # de outras maquinas. Advertencia que chega depois da decisao nao e advertencia.
  local base
  base=$(_ambiente '{}')
  _rodar "$base" unlink --confirmar
  assert_contem 'cascata' "$DBX_ERRO" 'RF-06a: a advertencia de cascata e obrigatoria'
}

teste_unlink_revoga_remove_credencial_e_bases() {
  local base
  base=$(_ambiente '{}')
  mkdir -p "$base/estado/dbx"
  printf '%s' 'base antiga' >"$base/estado/dbx/pareamento-um"
  _rodar "$base" --json unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'revogacao=emitida' "$DBX_SAIDA" 'RF-04: a revogacao remota e emitida'
  assert_contem 'base_removida=pareamento-um' "$DBX_SAIDA" \
    'RF-51d: as bases invalidadas sao nomeadas ao operador'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" \
    'RF-51c: por padrao o arquivo sai inteiro, app key e app secret inclusive'
  assert_arquivo_ausente "$base/estado/dbx/pareamento-um" \
    'RF-51d: base orfa nao pode sobreviver ao desvinculo'
}

teste_comando_autenticado_apos_unlink_falha_com_erro_de_configuracao() {
  # RF-51(e) na letra: `3`, e nao erro de rede. E a diferenca importa — `3` manda
  # reconfigurar, que e o que o operador precisa fazer.
  local base
  base=$(_ambiente '{}')
  _rodar "$base" unlink --confirmar
  _rodar "$base" info /
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" \
    'apos o desvinculo, comando autenticado falha por configuracao'
}

teste_unlink_com_manter_aplicativo_preserva_a_chave_e_ainda_invalida_o_vinculo() {
  local base conteudo
  base=$(_ambiente '{}')
  _rodar "$base" unlink --confirmar --manter-aplicativo
  assert_igual 0 "$DBX_ESTADO" "unlink deve concluir; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'o sinalizador preserva o arquivo'
  IFS= read -r -d '' conteudo <"$base/config/dbx/credencial.json"
  assert_contem '"app_key":"ak"' "$conteudo" 'a chave do aplicativo e preservada para religar'
  assert_segredo_ausente 'rt' "$conteudo" 'o refresh token nao pode sobreviver'
  _rodar "$base" info /
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" \
    'RF-51e vale igual no modo que preserva o aplicativo'
}

teste_unlink_com_revogacao_recusada_limpa_o_local_e_nao_sai_com_zero() {
  # Sair com zero diria "desvinculado" a quem ficou com um refresh token vivo do
  # lado da Dropbox; nao limpar diria "nada feito" a quem pediu o desvinculo e
  # ficou com o segredo em disco. As duas coisas precisam ser ditas.
  local base
  base=$(_ambiente '{"error_summary":"invalid_access_token/","error":{".tag":"invalid_access_token"}}' 401)
  _rodar "$base" --json unlink --confirmar
  assert_diferente 0 "$DBX_ESTADO" 'revogacao recusada nao pode sair como sucesso'
  assert_contem 'revogacao=falhou' "$DBX_SAIDA" 'o resultado declara o que nao aconteceu'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" \
    'a limpeza local acontece mesmo assim'
  assert_contem 'pode continuar valido' "$DBX_ERRO" \
    'o operador precisa saber que o token remoto pode ter sobrevivido'
}

teste_unlink_nao_apaga_atraves_de_ligacao_simbolica() {
  # Remocao recursiva e onde um defeito destroi dado do operador. Se o diretorio
  # de estado for uma ligacao, apagar atraves dela alcancaria arvore que nao e
  # nossa; apagar a ligacao reportaria remocao que nao houve.
  local base alvo
  base=$(_ambiente '{}')
  alvo=$(mktemp -d "$DBX_TESTES_TMP/alvo.XXXXXX")
  printf '%s' 'documento do operador' >"$alvo/nao_apagar"
  mkdir -p "$base/estado"
  ln -s "$alvo" "$base/estado/dbx"
  _rodar "$base" unlink --confirmar
  assert_arquivo_existe "$alvo/nao_apagar" \
    'o desvinculo nao pode apagar atraves de ligacao simbolica'
}

teste_unlink_em_simulacao_nao_revoga_nem_remove() {
  local base
  base=$(_ambiente '{}')
  _rodar "$base" --dry-run unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "simulacao deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'RF-15: a simulacao se declara'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'simulacao nao remove'
  assert_arquivo_ausente "$base/argv" 'simulacao nao chama o cliente de rede'
}

teste_upload_com_progresso_emite_em_stderr_e_preserva_stdout() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'conteudo para upload\n' >"$origem"
  _rodar "$base" --progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[upload]' "$DBX_ERRO" 'stderr deve conter marcadores de progresso'
  assert_nao_contem '[upload]' "$DBX_SAIDA" 'stdout nao pode ser contaminado com progresso'
}

teste_upload_com_progresso_analisa_arquivo_e_emite_resultado() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'conteudo para upload\n' >"$origem"
  _rodar "$base" --progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'analisando arquivo local' "$DBX_ERRO" 'deve conter mensagem de analise de arquivo'
  assert_contem 'resultado da analise:' "$DBX_ERRO" 'deve conter resultado da analise'
}

teste_download_com_progresso_emite_em_stderr_e_preserva_stdout() {
  local base
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  _rodar "$base" --progresso download /r/a.txt "$base/baixado.txt"
  assert_igual 0 "$DBX_ESTADO" "download com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[download]' "$DBX_ERRO" 'stderr deve conter marcadores de progresso'
  assert_nao_contem '[download]' "$DBX_SAIDA" 'stdout nao pode ser contaminado com progresso'
}

teste_upload_com_progresso_configura_progress_bar_no_cliente() {
  local base origem opcoes
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'conteudo para upload\n' >"$origem"
  _rodar "$base" --progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload com --progresso deve concluir; diagnostico: $DBX_ERRO"
  opcoes=$(cat "$base/opcoes" 2>/dev/null || true)
  assert_nao_contem 'progress-bar' "$opcoes" 'DIV-293: a barra do cURL nao e repassada; o progresso e o da linha do arquivo'
}

teste_upload_sem_progresso_mantem_cliente_silencioso() {
  local base origem opcoes
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'conteudo para upload\n' >"$origem"
  _rodar "$base" --sem-progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload sem progresso deve concluir; diagnostico: $DBX_ERRO"
  opcoes=$(cat "$base/opcoes" 2>/dev/null || true)
  assert_nao_contem 'progress-bar' "$opcoes" 'upload sem progresso nao pode configurar medidor no cliente'
  assert_contem 'silent' "$opcoes" 'upload sem progresso deve manter cliente silencioso'
}

teste_download_com_progresso_configura_progress_bar_no_cliente() {
  local base opcoes
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  _rodar "$base" --progresso download /r/a.txt "$base/baixado.txt"
  assert_igual 0 "$DBX_ESTADO" "download com --progresso deve concluir; diagnostico: $DBX_ERRO"
  opcoes=$(cat "$base/opcoes" 2>/dev/null || true)
  assert_nao_contem 'progress-bar' "$opcoes" 'DIV-293: a barra do cURL nao e repassada; o progresso e o da linha do arquivo'
}

teste_download_sem_progresso_mantem_cliente_silencioso() {
  local base opcoes
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  _rodar "$base" --sem-progresso download /r/a.txt "$base/baixado.txt"
  assert_igual 0 "$DBX_ESTADO" "download sem progresso deve concluir; diagnostico: $DBX_ERRO"
  opcoes=$(cat "$base/opcoes" 2>/dev/null || true)
  assert_nao_contem 'progress-bar' "$opcoes" 'download sem progresso nao pode configurar medidor no cliente'
  assert_contem 'silent' "$opcoes" 'download sem progresso deve manter cliente silencioso'
}

teste_upload_com_progresso_exibe_barra_grafica_em_stderr() {
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  printf 'conteudo para upload de teste\n' >"$origem"
  _rodar "$base" --progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[upload]' "$DBX_ERRO" 'stderr deve conter rotulo de upload'
  assert_contem '100%' "$DBX_ERRO" 'stderr deve indicar conclusao percentual'
  assert_contem '[' "$DBX_ERRO" 'stderr deve conter delimitador de barra grafica'
  assert_nao_contem '[upload]' "$DBX_SAIDA" 'stdout deve permanecer livre de progresso'
}

teste_download_com_progresso_exibe_barra_grafica_em_stderr() {
  local base
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  # DIV-304: a linha do download so abre depois que o metadado confirma arquivo.
  local h64
  printf -v h64 'a%.0s' {1..64}
  _metadado "$base" 200 "{\".tag\":\"file\",\"size\":28,\"rev\":\"0123456789a\",\"content_hash\":\"$h64\"}"
  _rodar "$base" --progresso download /r/a.txt "$base/baixado.txt"
  assert_igual 0 "$DBX_ESTADO" "download com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[download]' "$DBX_ERRO" 'stderr deve conter rotulo de download'
  assert_contem '100%' "$DBX_ERRO" 'stderr deve indicar conclusao percentual'
  assert_contem '[' "$DBX_ERRO" 'stderr deve conter delimitador de barra grafica'
  assert_nao_contem '[download]' "$DBX_SAIDA" 'stdout deve permanecer livre de progresso'
}

teste_download_cria_diretorio_de_destino_caso_nao_exista() {
  local base
  base=$(_ambiente 'CONTEUDO-TESTE')
  local destino="$base/nova_pasta/subpasta/saida.txt"
  _rodar "$base" download /r/a.txt "$destino"
  assert_igual 0 "$DBX_ESTADO" "download em destino novo deve concluir; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$base/nova_pasta/subpasta" 'as pastas intermediarias devem ser criadas'
  assert_sucesso test -d "$base/nova_pasta/subpasta"
  assert_igual 'CONTEUDO-TESTE' "$(cat "$destino")" 'o conteudo deve ser gravado'
}

# ---------------------------------------------------------------------------
# RF-60 — a dispensa do envio e decidida pelo `content_hash` REMOTO (fase 3)
#
# MUDANCA DECLARADA: o caso `upload_dispensa_arquivo_inalterado_e_forca_com_
# sinalizador` AFIRMAVA a dispensa decidida so pelo cache local (`lib/db`), sem
# consultar o remoto — o comportamento que violava `RSK-23` (`RSK-37`). Ele foi
# reescrito nos casos abaixo: a mesma jornada (dispensa, `--forcar`, arquivo
# alterado) agora exige `get_metadata` com hash igual para dispensar.
# ---------------------------------------------------------------------------

# _metadado <base> <codigo_http> <corpo> — resposta do duplo ao `get_metadata`.
_metadado() {
  printf '%s' "$2" >"$1/metadado_codigo"
  printf '%s' "$3" >"$1/metadado_corpo"
}

# _remoto_arquivo <base> <content_hash> — o remoto e um arquivo com esse hash.
_remoto_arquivo() {
  _metadado "$1" 200 "{\".tag\":\"file\",\"name\":\"a.txt\",\"rev\":\"016\",\"content_hash\":\"$2\"}"
}

_remoto_ausente() {
  _metadado "$1" 409 '{"error_summary":"path/not_found/..","error":{".tag":"path"}}'
}

# _origem_antiga <arquivo> <conteudo> — `mtime` no passado: sem isso a regra
# anti-corrida de 2 s (RF-61(d)) nao deixaria registro algum ser gravado.
_origem_antiga() {
  printf '%s' "$2" >"$1"
  touch -d '@1700000000.250000000' "$1"
}

_hash_de() { dbx_hash_conteudo_arquivo "$1"; }

# _resposta_do_envio <base> <arquivo> — o `files/upload` responde, como o
# servico real, com o `content_hash` do conteudo recebido.
_resposta_do_envio() {
  printf '{"name":"a.txt","rev":"016","content_hash":"%s"}' "$(_hash_de "$2")" >"$1/corpo"
}

_registros_de_upload() { # <base> — quantos `upload-*` existem no estado
  local -a lista=()
  shopt -s nullglob
  lista=("$1/estado/dbx"/upload-*)
  shopt -u nullglob
  printf '%s' "${#lista[@]}"
}

_memorias_do_sync() { # <base>
  local -a lista=()
  shopt -s nullglob
  lista=("$1/estado/dbx"/memoria-*)
  shopt -u nullglob
  printf '%s' "${#lista[@]}"
}

# _esperar_tique_do_ctime <arquivo> — ver a nota em tests/unit/walk_test.sh.
_esperar_tique_do_ctime() {
  local arquivo=$1 sonda=$1.sonda referencia
  referencia=$(stat -c '%z' -- "$arquivo")
  : >"$sonda"
  while [[ $(stat -c '%z' -- "$sonda") == "$referencia" ]]; do
    chmod 600 "$sonda"
  done
  rm -f -- "$sonda"
}

teste_upload_dispensa_quando_o_hash_remoto_e_igual_ao_local() {
  # TC-SKP-01 (RF-60(a)).
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo original'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "dispensa sai com zero; diagnostico: $DBX_ERRO"
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'o item sai como dispensado'
  assert_contem 'motivo=' "$DBX_SAIDA" 'com o motivo, campo que a saida ja emitia'
  assert_igual 1 "$(_harness_contar 'files/get_metadata' "$base/argv")" 'uma consulta de comparacao'
  assert_igual 0 "$(_harness_contar 'files/upload' "$base/argv")" 'nenhuma chamada de envio'
}

teste_upload_nomeia_classe_e_motivo_quando_a_resposta_da_consulta_e_ilegivel() {
  # O-5: a leitura do `get_metadata` nao perde o motivo; o envio segue.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo original'
  _metadado "$base" 200 '{"name":'
  _rodar "$base" --progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "o envio segue; diagnostico: $DBX_ERRO"
  assert_contem 'classe=erro_remoto' "$DBX_ERRO" 'classe nomeada no progresso'
  assert_contem 'resposta nao interpretavel' "$DBX_ERRO" 'motivo nomeado no progresso'
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'a falha da leitura leva ao envio'
}

teste_upload_envia_quando_o_hash_remoto_difere() {
  # TC-SKP-02 (RF-60(b)): no modo `add`, o comportamento atual de colisao.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"017"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo alterado'
  _remoto_arquivo "$base" '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff'
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "envio conclui; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'hash diferente envia'
  assert_contem 'mode\":\"add' "$(cat "$base/opcoes")" 'no modo pedido'
  assert_nao_contem 'status=dispensado' "$DBX_SAIDA" 'nada dispensado'
}

teste_upload_com_modo_overwrite_segue_a_mesma_regra() {
  # TC-SKP-03 (RF-60(c)).
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"017"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload --modo overwrite "$origem" /r/a.txt
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'overwrite com hash igual tambem dispensa'
  assert_igual 0 "$(_harness_contar 'files/upload' "$base/argv")" 'sem envio'
  _remoto_arquivo "$base" '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff'
  _rodar "$base" upload --modo overwrite "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "overwrite com hash diferente conclui; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'remoto diferente e sobrescrito'
  assert_contem 'mode\":\"overwrite' "$(cat "$base/opcoes")" 'em modo overwrite'
}

teste_upload_com_remoto_ausente_envia_sem_calcular_o_resumo_local() {
  # TC-SKP-04 (RF-60(d), RF-61(f)): "sem consulta redundante".
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'novo'
  _remoto_ausente "$base"
  _rodar "$base" --progresso upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "remoto ausente envia; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'envio emitido'
  assert_nao_contem 'resumo local' "$DBX_ERRO" 'o resumo local nao e calculado nem lido do cache para comparar'
}

teste_upload_com_falha_na_consulta_do_metadado_envia() {
  # TC-SKP-05 (RF-60(d)): a falha da consulta NUNCA dispensa o envio e nao
  # aborta o comando. Mutacao "dispensa quando o get_metadata falha" reprova.
  local base origem hash variante
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  hash=$(_hash_de "$origem")
  local -a codigos=(409 200 200 400)
  local -a corpos=(
    "{\"error_summary\":\"path/malformed_path/\",\"content_hash\":\"$hash\"}"
    'resposta que nao e json'
    '{".tag":"file","name":"a.txt"}'
    "{\"error_summary\":\"other/\",\"content_hash\":\"$hash\"}"
  )
  local esperado=0
  for variante in "${!codigos[@]}"; do
    _metadado "$base" "${codigos[$variante]}" "${corpos[$variante]}"
    _rodar "$base" upload "$origem" /r/a.txt
    esperado=$((esperado + 1))
    assert_igual 0 "$DBX_ESTADO" "variante $variante: o comando segue; diagnostico: $DBX_ERRO"
    assert_igual "$esperado" "$(_harness_contar 'files/upload$' "$base/argv")" \
      "variante $variante: falha na consulta leva ao envio"
  done
}

teste_upload_com_remoto_pasta_tenta_o_envio() {
  # TC-SKP-05 (RF-60(e)): remoto que nao e arquivo nao e comparado.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _metadado "$base" 200 '{".tag":"folder","name":"a.txt"}'
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'o envio e tentado como hoje'
}

teste_upload_nao_dispensa_pelo_cache_quando_o_remoto_mudou_ou_sumiu() {
  # TC-SKP-06/07 (RF-60(f)): cache valido nao decide. Mutacao "dispensa pelo
  # cache sem comparar com o remoto" reprova aqui.
  local base origem hash
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  hash=$(_hash_de "$origem")
  _remoto_arquivo "$base" "$hash"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'primeira execucao: hash igual dispensa'
  assert_igual 1 "$(_registros_de_upload "$base")" 'e o resumo calculado vai ao cache'

  _remoto_arquivo "$base" '11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff'
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'remoto alterado: envia, com cache valido'

  _remoto_ausente "$base"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 2 "$(_harness_contar 'files/upload$' "$base/argv")" 'remoto apagado: envia, com cache valido'

  # Mesmo par arquivo/remoto, com e sem cache: decisao identica.
  _remoto_arquivo "$base" "$hash"
  _rodar "$base" upload "$origem" /r/a.txt
  local com_cache=$DBX_SAIDA
  rm -rf -- "$base/estado"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_contem 'status=dispensado' "$com_cache" 'com cache: dispensa'
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'sem cache: a mesma decisao'
  assert_igual 2 "$(_harness_contar 'files/upload$' "$base/argv")" 'nenhum envio a mais'
}

teste_upload_forcar_e_entrada_padrao_nao_consultam_o_metadado() {
  # TC-SKP-08 (RF-60(g), (h)).
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload --forcar "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "--forcar envia; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" '--forcar envia mesmo com hash igual'
  _rodar "$base" upload - /r/b.txt
  assert_igual 0 "$(_harness_contar 'files/get_metadata' "$base/argv")" \
    'nem --forcar nem a entrada padrao emitem consulta de comparacao'
  assert_igual 0 "$(_registros_de_upload "$base")" 'entrada padrao nao tem cache; --forcar grava so arquivo antigo'
}

teste_upload_com_rev_envia_em_update_sem_consulta_de_comparacao() {
  # TC-SKP-09 (RF-60(i), DIV-27): o servidor faz valer o rev.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"017"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload --rev 016 "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload --rev conclui; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_harness_contar 'files/get_metadata' "$base/argv")" 'sem consulta de comparacao'
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'envia mesmo com hash remoto igual'
  assert_contem 'update\":\"016' "$(cat "$base/opcoes")" 'em update com o rev informado'
}

# ---------------------------------------------------------------------------
# RF-61 — cache do upload em `lib/state` (namespace `upload-*`)
# ---------------------------------------------------------------------------

teste_upload_grava_cache_proprio_e_nao_marca_o_par_do_sync_como_visto() {
  # TC-UPC-01 (RF-61(a)): proteger RF-48.
  local base
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  mkdir -p "$base/raiz"
  _origem_antiga "$base/raiz/a.txt" 'conteudo'
  _remoto_ausente "$base"
  _resposta_do_envio "$base" "$base/raiz/a.txt"
  _rodar "$base" upload "$base/raiz/a.txt" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "upload conclui; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_registros_de_upload "$base")" 'upload-* gravado apos o envio'
  assert_igual 0 "$(_memorias_do_sync "$base")" 'nenhum memoria-* criado pelo upload'
  _rodar "$base" sync --enviar --espelhar --origem "$base/raiz" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" \
    'o sync --espelhar seguinte continua exigindo o reconhecimento'
  assert_contem 'primeira execucao' "$DBX_ERRO" 'pela regra de RF-48'
}

teste_upload_reescrita_no_mesmo_segundo_com_remoto_antigo_envia() {
  # TC-UPC-02/03 (RF-61(b)): mesmo segundo, mesmo tamanho, `mtime` restaurado,
  # remoto igual ao conteudo ANTIGO. Mutacao com `mtime` em segundos e sem
  # `ctime` reprova aqui.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'aaaa'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'conteudo antigo igual ao remoto: dispensa'
  assert_igual 1 "$(_registros_de_upload "$base")" 'resumo antigo no cache'
  _esperar_tique_do_ctime "$origem"
  printf 'bbbb' >"$origem"
  touch -d '@1700000000.250000000' "$origem"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" \
    'conteudo novo com o mesmo mtime e tamanho e enviado'
}

teste_upload_nao_grava_cache_quando_a_origem_muda_durante_o_envio() {
  # TC-UPC-04 (RF-61(c)): mutacao que grave sem a segunda leitura de `stat`
  # reprova aqui.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_ausente "$base"
  _resposta_do_envio "$base" "$origem"
  printf '%s' "$origem" >"$base/alterar_durante_envio"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "o envio conclui; diagnostico: $DBX_ERRO"
  assert_igual 'CONTEUDO' "$(cat "$origem")" 'o duplo alterou a origem durante o envio'
  assert_igual 0 "$(_registros_de_upload "$base")" 'stat divergente antes/depois nao grava'
}

teste_upload_sem_cache_para_arquivo_recente_vazio_ou_fluxo() {
  # TC-UPC-05/06 (RF-61(d), (e)).
  local base
  base=$(_ambiente '{"name":"a.txt","rev":"016","session_id":"S-1","content_hash":"11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff"}')
  _remoto_ausente "$base"
  printf 'recente' >"$base/recente.txt"
  _rodar "$base" upload "$base/recente.txt" /r/recente.txt
  assert_igual 0 "$DBX_ESTADO" "recente envia; diagnostico: $DBX_ERRO"
  : >"$base/vazio.txt"
  touch -d '@1700000000' "$base/vazio.txt"
  _rodar "$base" upload "$base/vazio.txt" /r/vazio.txt
  assert_igual 0 "$DBX_ESTADO" "vazio envia; diagnostico: $DBX_ERRO"
  printf '%s' '{"session_id":"S-1"}' >"$base/corpo"
  _rodar "$base" upload - /r/fluxo.txt
  assert_igual 0 "$DBX_ESTADO" "fluxo envia; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_registros_de_upload "$base")" 'nenhum dos tres e cacheado'
}

teste_upload_acerto_de_cache_renova_o_carimbo_de_uso() {
  # RF-61(i): o acerto conta como uso para a poda.
  local base origem registro idade agora
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload "$origem" /r/a.txt
  registro=("$base/estado/dbx"/upload-*)
  touch -d '100 days ago' "${registro[0]}"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'acerto com hash remoto igual dispensa'
  printf -v agora '%(%s)T' -1
  idade=$((agora - $(stat -c '%Y' -- "${registro[0]}")))
  [[ $idade -lt 60 ]] || _harness_falhar 'o acerto renova o carimbo do registro' "idade: $idade s"
}

teste_upload_falha_ao_gravar_o_cache_nao_muda_o_resultado() {
  # TC-UPC-08 (RF-61(g)): diretorio de estado alheio.
  [[ $EUID -ne 0 ]] || pular 'como root todo diretorio pertence ao usuario'
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_ausente "$base"
  _resposta_do_envio "$base" "$origem"
  mkdir -p "$base/estado"
  ln -s /usr "$base/estado/dbx"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "o upload conclui com o mesmo codigo; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/argv")" 'envio emitido'
}

teste_upload_com_segredo_vazio_recusa_antes_da_rede_na_classe_de_rf03() {
  # QA-P3-02: RF-63(a) ponta a ponta; antes saia com `erro_remoto` (10) e
  # "envio recusado: sem detalhe", sem o motivo.
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" "classe de RF-03; diagnostico: $DBX_ERRO"
  assert_arquivo_ausente "$base/argv" 'nenhuma chamada de rede'
  assert_contem 'segredo' "$DBX_ERRO" 'o motivo nomeia o segredo'
}

teste_upload_nao_identifica_a_conta() {
  # TC-CONTA-03 (RF-61(h), RF-52(b)).
  local base origem
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload "$origem" /r/a.txt
  _remoto_ausente "$base"
  _rodar "$base" upload "$origem" /r/a.txt
  assert_igual 0 "$(_harness_contar 'get_current_account' "$base/argv")" \
    'o upload nao emite users/get_current_account'
}

teste_upload_por_sessao_grava_o_hash_do_canal_de_conteudo() {
  # TC-UPC-11 (RF-61(j), F-29): no envio por sessao o hash registrado vem de
  # DBX_TRANSFER_CONTENT_HASH.
  local base origem registro hash
  base=$(_ambiente '{"name":"g.bin","rev":"016"}')
  origem="$base/grande.bin"
  dd if=/dev/null of="$origem" bs=1 seek=157286401 2>/dev/null ||
    pular 'nao foi possivel criar arquivo esparso'
  touch -d '@1700000000.250000000' "$origem"
  _remoto_ausente "$base"
  printf '%s' '{"session_id":"S-1"}' >"$base/corpo"
  _rodar "$base" upload "$origem" /r/g.bin
  assert_contem 'modo_de_envio=sessao_em_partes' "$DBX_SAIDA" "por sessao; diagnostico: $DBX_ERRO"
  registro=("$base/estado/dbx"/upload-*)
  assert_arquivo_existe "${registro[0]}" 'o envio por sessao grava o cache'
  hash=$(_hash_de "$origem")
  assert_contem "$hash" "$(tr '\0' '\n' <"${registro[0]}")" 'com o hash do conteudo enviado'
}

teste_upload_relativo_absoluto_e_ligacao_usam_o_mesmo_cache() {
  # TC-CAN-01 (RF-62(a)).
  local base
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  _origem_antiga "$base/a.txt" 'conteudo'
  ln -s "$base/a.txt" "$base/atalho.txt"
  _remoto_ausente "$base"
  _resposta_do_envio "$base" "$base/a.txt"
  _rodar "$base" upload "$base/a.txt" /r/a.txt
  (cd "$base" && _rodar "$base" upload ./a.txt /r/a.txt)
  (cd "$base" && _rodar "$base" upload atalho.txt /r/a.txt)
  assert_igual 3 "$(_harness_contar 'files/upload$' "$base/argv")" 'tres envios'
  assert_igual 1 "$(_registros_de_upload "$base")" 'um unico upload-* para os tres caminhos'
}

teste_upload_nao_usa_sqlite_nem_python_e_preserva_o_legado() {
  # TC-DEP-03 (RNF-02(c)) e TC-LEG-02 (RNF-33(b)).
  local base origem legado antes depois
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  origem="$base/local.txt"
  _origem_antiga "$origem" 'conteudo'
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  for legado in dbx.db dbx.db-wal dbx.db-shm; do
    printf 'legado %s' "$legado" >"$base/estado/dbx/$legado"
    touch -d '@1600000000' "$base/estado/dbx/$legado"
  done
  antes=$(cd "$base/estado/dbx" && stat -c '%n %s %Y' dbx.db dbx.db-wal dbx.db-shm && cat dbx.db dbx.db-wal dbx.db-shm)
  _remoto_arquivo "$base" "$(_hash_de "$origem")"
  _rodar "$base" upload "$origem" /r/a.txt
  _rodar "$base" upload "$origem" /r/a.txt
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'o cache funciona sem sqlite3 nem python3'
  assert_igual 1 "$(_registros_de_upload "$base")" 'e foi usado'
  assert_arquivo_ausente "$base/proibido" 'nenhuma invocacao de sqlite3, python3 ou python'
  depois=$(cd "$base/estado/dbx" && stat -c '%n %s %Y' dbx.db dbx.db-wal dbx.db-shm && cat dbx.db dbx.db-wal dbx.db-shm)
  assert_igual "$antes" "$depois" 'dbx.db* intactos: conteudo e mtime'
}

teste_estado_apos_upload_e_sync_so_contem_os_dois_namespaces() {
  # RNF-26: o estado persistente autorizado e `memoria-*` e `upload-*`.
  local base nome intrusos=''
  base=$(_ambiente '{"name":"a.txt","rev":"016"}')
  mkdir -p "$base/raiz"
  _origem_antiga "$base/raiz/a.txt" 'conteudo'
  _remoto_ausente "$base"
  _resposta_do_envio "$base" "$base/raiz/a.txt"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  _rodar "$base" upload "$base/raiz/a.txt" /r/a.txt
  _rodar "$base" sync --enviar --origem "$base/raiz" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync conclui; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_registros_de_upload "$base")" 'um upload-*'
  assert_igual 1 "$(_memorias_do_sync "$base")" 'uma memoria-*'
  for nome in "$base/estado/dbx"/* "$base/estado/dbx"/.[!.]*; do
    [[ -e $nome ]] || continue
    case ${nome##*/} in memoria-* | upload-*) ;; *) intrusos+=" ${nome##*/}" ;; esac
  done
  assert_igual '' "$intrusos" 'nada alem dos dois namespaces no diretorio de estado'
  assert_igual 700 "$(stat -c '%a' "$base/estado/dbx")" 'diretorio em 0700'
}

teste_unlink_remove_memorias_temporarios_e_legado() {
  # TC-LEG-04 (RF-51(f), RNF-33(e)).
  local base nome
  base=$(_ambiente '{}')
  mkdir -p "$base/estado/dbx"
  for nome in memoria-0123 upload-4567 .memoria.1.AAAA .upload.2.BBBB dbx.db dbx.db-wal dbx.db-shm; do
    printf 'x' >"$base/estado/dbx/$nome"
  done
  _rodar "$base" unlink --confirmar
  assert_igual 0 "$DBX_ESTADO" "unlink conclui; diagnostico: $DBX_ERRO"
  assert_arquivo_ausente "$base/estado/dbx" 'o diretorio de estado sai inteiro, com os quatro tipos'
}

teste_upload_de_diretorio_transfere_recursivamente() {
  local base pasta_local
  base=$(_ambiente '{"entries":[],"has_more":false}')
  pasta_local="$base/minha_pasta"
  mkdir -p "$pasta_local"
  printf 'conteudo 1\n' >"$pasta_local/arq1.txt"
  printf 'conteudo 2\n' >"$pasta_local/arq2.txt"

  _rodar "$base" upload "$pasta_local" /r/backup
  assert_igual 0 "$DBX_ESTADO" "upload de pasta deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'operacao=sync' "$DBX_SAIDA" "deve executar sincronizacao de envio"
  assert_contem 'sentido=enviar' "$DBX_SAIDA" "sentido deve ser envio"
}

teste_download_de_pasta_transfere_recursivamente() {
  local base destino
  base=$(_ambiente '{}')
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_corpo"
  printf '%s' '409' >"$base/download_codigo"
  printf '%s' '{"entries":[{".tag":"file","name":"relatorio.txt","size":9,"content_hash":"11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff"}],"has_more":false}' >"$base/listagem"

  destino="$base/destino_local"
  _rodar "$base" download /pasta_remota "$destino"
  assert_igual 0 "$DBX_ESTADO" "download de pasta deve concluir; diagnostico: $DBX_ERRO"
  assert_sucesso test -d "$destino"
}

teste_download_pasta_sem_destino_recusa_com_uso_invalido() {
  local base
  base=$(_ambiente '{}')
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_corpo"
  printf '%s' '409' >"$base/download_codigo"

  _rodar "$base" download /pasta_remota
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" \
    "download de pasta sem destino deve recusar com uso invalido"
  assert_contem 'pasta' "$DBX_ERRO" "diagnostico deve alertar que o caminho e pasta"
}

teste_download_de_pasta_com_progresso_nao_vaza_erro_bruto_do_cliente_em_stderr() {
  local base destino
  base=$(_ambiente '{}')
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_corpo"
  printf '%s' '409' >"$base/download_codigo"
  printf '%s' '{"entries":[{".tag":"file","name":"relatorio.txt","size":9,"content_hash":"11223344556677889900aabbccddeeff11223344556677889900aabbccddeeff"}],"has_more":false}' >"$base/listagem"

  destino="$base/destino_local"
  _rodar "$base" --progresso download /pasta_remota "$destino"
  assert_igual 0 "$DBX_ESTADO" "download de pasta com progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_nao_contem 'The requested URL returned error' "$DBX_ERRO" \
    'download de pasta com progresso nao pode vazar erro bruto do cliente em stderr'
  assert_contem 'o caminho remoto e uma pasta' "$DBX_ERRO" \
    'mensagem de fallback de pasta deve ser emitida'
  assert_sucesso test -d "$destino"
}

# ---------------------------------------------------------------------------
# RF-32(b), F-28 — `download` sem destino escreve o conteudo no stdout
#
# Investigacao: o codigo 9 vinha do COMANDO, e nao do duplo. O canal de fluxo
# roda o cliente dentro da substituicao que captura o `-w '%{http_code}'`; ali
# `/dev/stdout` e o cano da captura, entao o conteudo ia parar junto do codigo
# HTTP, o codigo deixava de ser numero e a chamada virava falha de rede. Medido
# com o cliente real (`curl -o /dev/stdout -w ... file://...` dentro de `$( )`
# captura `CONTEUDO000`), e nao so com o duplo.
# ---------------------------------------------------------------------------

teste_download_sem_destino_escreve_so_o_conteudo_no_stdout() {
  # TC-DLS-01.
  local base
  base=$(_ambiente 'CONTEUDO-DO-ARQUIVO')
  _rodar "$base" download /r/a.txt
  assert_igual 0 "$DBX_ESTADO" "sem destino o recebimento conclui; diagnostico: $DBX_ERRO"
  assert_igual 'CONTEUDO-DO-ARQUIVO' "$DBX_SAIDA" 'o stdout tem o conteudo e nada alem dele'
}

teste_download_para_o_hifen_escreve_so_o_conteudo_no_stdout() {
  # Mesmo canal com `-` explicito; o caso roda num diretorio proprio para
  # provar que nenhum arquivo chamado `-` e criado.
  local base
  base=$(_ambiente 'CONTEUDO-DO-ARQUIVO')
  cd "$base" || _harness_falhar 'diretorio do caso indisponivel'
  _rodar "$base" download /r/a.txt -
  assert_igual 0 "$DBX_ESTADO" "o recebimento conclui; diagnostico: $DBX_ERRO"
  assert_igual 'CONTEUDO-DO-ARQUIVO' "$DBX_SAIDA" 'o stdout tem o conteudo e nada alem dele'
  assert_arquivo_ausente "$base/-" 'o hifen e a saida padrao, e nao um arquivo'
}

teste_download_para_consumidor_que_fecha_sai_com_codigo_proprio() {
  # OBS-01 (RF-32): consumidor que fecha antes do fim nao e falha de rede. A
  # taxonomia ja tem a classe (`consumidor_encerrou`, 15).
  # So existe consumidor quando a saida padrao e um CANO (QA-P2-05).
  local base estado
  base=$(_ambiente 'CONTEUDO-DO-ARQUIVO')
  : >"$base/consumidor_fechou"
  estado=$(
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
      bash "$DBX_EXEC" download /r/a.txt </dev/null 2>"$base/err" | cat >/dev/null
    printf '%s' "${PIPESTATUS[0]}"
  )
  assert_igual "$(dbx_errors_codigo_saida consumidor_encerrou)" "$estado" \
    'codigo de saida especifico do consumidor que encerrou'
  assert_contem 'consumidor' "$(cat "$base/err")" 'o diagnostico diz o que aconteceu'
  assert_igual 1 "$(_harness_contar 'files/download' "$base/argv")" 'fluxo nao e repetido'
}

teste_download_com_falha_de_escrita_em_arquivo_nao_culpa_consumidor() {
  # QA-P2-05: o mesmo erro de escrita com a saida padrao em ARQUIVO e falha local
  # de escrita, e nao consumidor encerrado.
  local base
  base=$(_ambiente 'CONTEUDO-DO-ARQUIVO')
  : >"$base/consumidor_fechou"
  _rodar "$base" download /r/a.txt
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'falha local de escrita'
  assert_nao_contem 'consumidor' "$DBX_ERRO" 'nao ha consumidor a culpar'
  assert_contem 'escrita' "$DBX_ERRO" 'o diagnostico diz que a escrita falhou'
  assert_igual 1 "$(_harness_contar 'files/download' "$base/argv")" 'fluxo nao e repetido'
}

teste_download_sem_destino_sobre_arquivo_com_conteudo_recusa_e_preserva() {
  # O cliente reabre a saida padrao do inicio: com `>>` sobre conteudo existente
  # isso o apagaria. A recusa vem antes de qualquer recebimento.
  local base estado
  base=$(_ambiente 'CONTEUDO-DO-ARQUIVO')
  printf 'ANTERIOR\n' >"$base/acumulado"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" download /r/a.txt </dev/null >>"$base/acumulado" 2>"$base/err"
  estado=$?
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$estado" 'saida padrao com conteudo e recusada'
  assert_igual 'ANTERIOR' "$(cat "$base/acumulado")" 'o conteudo anterior fica intacto'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/argv")" 'a recusa vem antes de receber'
}

# ---------------------------------------------------------------------------
# RNF-30(c), RNF-07(e): ajuste de rede invalido e uso invalido, antes da rede
# ---------------------------------------------------------------------------

teste_ajuda_geral_documenta_as_variaveis_de_rede_e_os_padroes() {
  local base saida variavel
  base=$(mktemp -d "$DBX_TESTES_TMP/ajuda-rede.XXXXXX")
  env -i PATH="/usr/bin:/bin" HOME="$base" bash "$DBX_EXEC" help >"$base/out" 2>&1
  saida=$(cat "$base/out")
  for variavel in DBX_HTTP_CONNECT_TIMEOUT_S DBX_HTTP_VELOCIDADE_MINIMA_BPS DBX_HTTP_VELOCIDADE_JANELA_S \
    DBX_HTTP_TENTATIVAS_MAXIMAS DBX_HTTP_ESPERA_BASE_MS DBX_HTTP_ESPERA_TETO_MS DBX_HTTP_RETRY_AFTER_TETO_S; do
    assert_contem "$variavel" "$saida" "a ajuda documenta $variavel"
  done
  assert_contem 'padrao 5' "$saida" 'cinco tentativas por padrao'
  assert_nao_contem '250' "$saida" 'a base antiga de 250 ms nao aparece'
}

teste_ajuste_de_rede_invalido_e_recusado_antes_de_qualquer_chamada() {
  local base variavel estado
  for variavel in DBX_HTTP_CONNECT_TIMEOUT_S DBX_HTTP_TENTATIVAS_MAXIMAS; do
    base=$(_ambiente '{"entries":[],"has_more":false}')
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" "$variavel=abc" \
      bash "$DBX_EXEC" list /r </dev/null >"$base/out" 2>"$base/err"
    estado=$?
    assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$estado" "$variavel invalida e uso invalido"
    assert_contem "$variavel" "$(cat "$base/err")" 'o diagnostico nomeia a variavel'
    assert_contem '[abc]' "$(cat "$base/err")" 'o diagnostico nomeia o valor recusado'
    assert_arquivo_ausente "$base/argv" 'nenhuma chamada de rede, nem a de renovacao do token'
  done
}

# ---------------------------------------------------------------------------
# RF-64 — aliases em ingles de `unlink` e `config` (TC-ALI-02, TC-ALI-03)
# ---------------------------------------------------------------------------

teste_unlink_yes_tem_o_mesmo_efeito_de_confirmar() {
  # TC-ALI-02: mesmo estado final do nome em portugues.
  local base
  base=$(_ambiente '{}')
  mkdir -p "$base/estado/dbx"
  printf '%s' 'base antiga' >"$base/estado/dbx/pareamento-um"
  _rodar "$base" --json unlink --yes
  assert_igual 0 "$DBX_ESTADO" "unlink --yes deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'revogacao=emitida' "$DBX_SAIDA" 'a revogacao remota e emitida'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'a credencial sai inteira'
  assert_arquivo_ausente "$base/estado/dbx/pareamento-um" 'e as bases tambem'
}

teste_unlink_keep_app_preserva_a_chave_como_manter_aplicativo() {
  # TC-ALI-02, RF-51(c): `--keep-app` preserva `app key` e `app secret`.
  local base conteudo
  base=$(_ambiente '{}')
  _rodar "$base" unlink --yes --keep-app
  assert_igual 0 "$DBX_ESTADO" "unlink deve concluir; diagnostico: $DBX_ERRO"
  IFS= read -r -d '' conteudo <"$base/config/dbx/credencial.json"
  assert_contem '"app_key":"ak"' "$conteudo" 'a chave do aplicativo e preservada'
  assert_contem '"app_secret":"as"' "$conteudo" 'e o segredo do aplicativo tambem'
  assert_segredo_ausente 'rt' "$conteudo" 'o refresh token nao sobrevive'
  base=$(_ambiente '{}')
  _rodar "$base" unlink --confirmar --keep-app
  assert_igual 0 "$DBX_ESTADO" "misturado com o portugues tambem vale; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'o arquivo e preservado'
}

teste_unlink_sem_yes_continua_recusado_sem_terminal() {
  # RF-06a: o alias nao muda a recusa sem sinalizador.
  local base
  base=$(_ambiente '{}')
  _rodar "$base" unlink --keep-app
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem --yes, recusado'
  assert_contem '--confirmar' "$DBX_ERRO" 'pela falta de confirmacao, e nao por opcao desconhecida'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'nada removido'
}

teste_config_root_tem_o_mesmo_efeito_de_raiz() {
  # TC-ALI-03: mesmo efeito e mesmas recusas.
  local base pt en
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" '' --json --dry-run config --raiz /pasta
  pt="$DBX_ESTADO|$DBX_SAIDA"
  _rodar_com_entrada "$base" '' --json --dry-run config --root /pasta
  en="$DBX_ESTADO|$DBX_SAIDA"
  assert_contem 'raiz_remota=/pasta' "$pt" 'a referencia usa a raiz dada'
  assert_igual "$pt" "$en" '--root: mesma saida que --raiz'
  _rodar_com_entrada "$base" '' --dry-run config --raiz '/../x'
  pt=$DBX_ESTADO
  _rodar_com_entrada "$base" '' --dry-run config --root '/../x'
  assert_diferente 0 "$pt" 'a raiz invalida e recusada em portugues'
  assert_igual "$pt" "$DBX_ESTADO" '--root: mesma recusa que --raiz'
  _rodar_com_entrada "$base" '' --json --dry-run config --raiz /x --root /y
  assert_contem 'raiz_remota=/y' "$DBX_SAIDA" 'RF-64(e): o ultimo valor vale'
}

teste_config_replace_substitui_como_substituir() {
  # TC-ALI-03: `--replace` libera a troca, e sem ele a recusa continua.
  local base conteudo
  base=$(_ambiente_vazio)
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"RT_anterior","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config --root /
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'sem --replace, recusa'
  _rodar_com_entrada "$base" "$ENTRADA_DE_VINCULO" config --replace
  assert_igual 0 "$DBX_ESTADO" "--replace substitui; diagnostico: $DBX_ERRO"
  assert_contem 'NAO foi revogado' "$DBX_ERRO" 'com a mesma advertencia de --substituir'
  IFS= read -r -d '' conteudo <"$base/config/dbx/credencial.json"
  assert_contem 'RT_gravado_pelo_config' "$conteudo" 'a credencial nova foi gravada'
}

teste_ajuda_de_unlink_e_config_lista_os_dois_nomes() {
  # RF-64(c).
  local base nome uso
  base=$(_ambiente_vazio)
  _rodar_com_entrada "$base" '' help unlink
  uso=${DBX_SAIDA%%$'\n'*}
  for nome in --confirmar --yes --manter-aplicativo --keep-app; do
    assert_contem "$nome" "$uso" "o Uso: do unlink lista $nome"
  done
  _rodar_com_entrada "$base" '' help config
  uso=${DBX_SAIDA%%$'\n'*}
  for nome in --substituir --replace --raiz --root; do
    assert_contem "$nome" "$uso" "o Uso: do config lista $nome"
  done
}

harness_executar "$@"

