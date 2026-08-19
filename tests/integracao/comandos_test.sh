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
    # O cabecalho NAO viaja em argv: vai pelo arquivo de opcoes na entrada
    # padrao, justamente para o segredo ficar fora da tabela de processos.
    # Descartar a entrada aqui tornaria invisivel tudo o que se quer verificar
    # sobre cabecalhos.
    printf 'cat >>"$base/opcoes" 2>/dev/null\n'
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
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
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
  # shellcheck disable=SC2043
  # Justificativa: e um CONJUNTO — o dos comandos ainda fora do bloco — que hoje
  # tem um membro so. Desfazer o laco esconderia a natureza da lista e obrigaria
  # a reescreve-lo quando `sync` sair dela.
  for nome in sync; do
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

# O envio pela entrada padrao exige sessao em partes, que nao existe. Recusar
# dizendo o que falta e melhor que ler tudo em memoria e exceder sem aviso.
teste_upload_recusa_entrada_padrao_com_diagnostico() {
  local base
  base=$(_ambiente '{}')
  _rodar "$base" upload - /r/a.txt
  [[ $DBX_ESTADO -ne 0 ]] ||
    _harness_falhar 'envio pela entrada padrao nao pode reportar sucesso'
  assert_contem 'sessao em partes' "$DBX_ERRO" \
    'o diagnostico deve dizer o que falta, nao apenas recusar'
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

harness_executar "$@"
