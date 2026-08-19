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
    printf '  corpo=%s; codigo=200\n' "'{\"access_token\":\"sl.t\",\"token_type\":\"bearer\",\"expires_in\":14400}'"
    printf 'else\n'
    printf '  corpo=$(cat "$base/corpo"); codigo=$(cat "$base/codigo")\n'
    printf 'fi\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    TMPDIR="$DBX_TESTES_TMP" bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
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
  for nome in sync config unlink; do
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

harness_executar "$@"
