#!/usr/bin/env bash
# Testes ponta a ponta do `sync` direcional (DP-27, DP-28, RF-37..RF-53).
#
# O QUE ESTE ARQUIVO PRECISA PROVAR, e por que ele e o mais adversarial da suite:
# `RSK-35` registra que a matriz de tres estados garantia ESTRUTURALMENTE que a
# primeira execucao nunca apagava nada, e que essa garantia caiu com `DP-27`.
# Sobraram quatro barreiras — RF-40, RF-41, RF-47 e RF-48 — e elas nao tem
# suporte estrutural nenhum: se qualquer uma falhar, o sintoma e a arvore do
# operador apagada.
#
# shellcheck disable=SC2016
# Justificativa: casos escrevem o substituto de `curl`, que precisa chegar sem
# expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

# _cenario <json_do_list_folder> — monta credencial, duplo de rede e arvore local.
#
# O duplo registra CADA URL chamada em `$base/chamadas`, que e o que permite
# afirmar "zero exclusoes emitidas" olhando o que saiu, e nao o que o relatorio
# diz ter feito.
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
    printf 'base=%s\n' "$base"
    printf 'conf=$(cat 2>/dev/null)\n'
    printf 'printf "%%s\\n" "$conf" >>"$base/opcoes"\n'
    printf 'saida=""; escrever=""; anterior=""; url=""; cabecalhos=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; esac\n'
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
    # Conflito de rev (RF-49): o envio cujo argumento cita o caminho marcado e
    # recusado como a Dropbox recusa, com 409 e tag `conflict`.
    printf 'if [[ $url == *files/upload && -f "$base/upload_conflito" && $conf == *"$(cat "$base/upload_conflito")"* ]]; then\n'
    printf '  codigo=409; corpo=%s\n' "'{\"error_summary\":\"path/conflict/file/..\"}'"
    printf 'fi\n'
    printf 'if [[ $url == *files/download* && -n $cabecalhos && -f "$base/resultado_cabecalho" ]]; then\n'
    printf '  printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"\n'
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

_escritas() { # <base> — quantas chamadas de escrita remota sairam
  _harness_contar 'files/upload\|files/delete_v2' "$1/chamadas"
}

_exclusoes() { # <base>
  _harness_contar 'files/delete_v2' "$1/chamadas"
}

_entrada_remota() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s}' "$1" "$2" "$3"
}

_entrada_remota_com_rev() { # <caminho> <hash> <tamanho> <rev>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s,"rev":"%s"}' \
    "$1" "$2" "$3" "$4"
}

_resumo_de() { # <arquivo>
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$1'"
}

_conteudo_do_diretorio() { # <diretorio> — nomes, inclusive ocultos, um por linha
  find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
}

readonly RESUMO_ZERADO=0000000000000000000000000000000000000000000000000000000000000000

# ---------------------------------------------------------------------------
# Contrato dos lados (RF-53, DP-28)
# ---------------------------------------------------------------------------

teste_origem_e_destino_sao_obrigatorios() {
  local base
  base=$(_cenario)
  _rodar "$base" sync --enviar --destino /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem --origem'
  assert_contem '--origem' "$DBX_ERRO" 'o diagnostico nomeia o que falta'
  _rodar "$base" sync --enviar --origem "$base/local"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem --destino'
  assert_contem '--destino' "$DBX_ERRO" 'o diagnostico nomeia o que falta'
}

teste_sentido_e_obrigatorio_e_mutuamente_exclusivo() {
  # DP-28 adotou a leitura OBRIGATORIA. Na leitura opcional a inferencia
  # continuaria decidindo nos casos que nao empatam — que sao justamente os que
  # invertem o sentido em silencio.
  local base
  base=$(_cenario)
  _rodar "$base" sync --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem sentido declarado'
  assert_contem '--enviar' "$DBX_ERRO" 'o diagnostico oferece as duas opcoes'
  assert_contem '--receber' "$DBX_ERRO" 'o diagnostico oferece as duas opcoes'
  _rodar "$base" sync --origem "$base/local" --destino /r --enviar --receber
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'os dois juntos'
  assert_contem 'mutuamente exclusiv' "$DBX_ERRO" 'a recusa diz por que'
}

teste_o_tipo_de_cada_lado_nunca_e_inferido_do_caminho() {
  # RF-53(c) com verificacao estatica: `DP-28` fechou a inferencia, e reintroduzi
  # -la nao produziria sintoma em teste de dado — produziria o `sync` enviando
  # quando o operador pediu receber.
  local achados
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/commands/sync.sh" 'sem o arquivo a auditoria seria vacua'
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/sync.sh" |
    grep -nE '\[\[[^]]*-(d|e|f)[[:space:]]+"?\$\{?(origem|destino)\}?"?' || true)
  assert_igual '' "$achados" "inspecao de caminho para decidir tipo: $achados"
  # Prova de discriminacao: o reconhecedor precisa reagir a forma que proibe.
  local amostra='  if [[ -d $origem ]]; then sentido=enviar; fi'
  grep -qE '\[\[[^]]*-(d|e|f)[[:space:]]+"?\$\{?(origem|destino)\}?"?' <<<"$amostra" ||
    _harness_falhar 'o reconhecedor nao detecta a inferencia que deveria proibir'
  local inocente='  [[ -d $raiz_local ]] || return 1'
  grep -qE '\[\[[^]]*-(d|e|f)[[:space:]]+"?\$\{?(origem|destino)\}?"?' <<<"$inocente" &&
    _harness_falhar 'o reconhecedor acusa a verificacao legitima da raiz local'
  return 0
}

teste_fluxo_e_recusado_nos_dois_lados() {
  local base
  base=$(_cenario)
  _rodar "$base" sync --enviar --origem - --destino /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'origem em fluxo'
  assert_contem '--origem' "$DBX_ERRO" 'RF-45: a recusa nomeia o sinalizador'
  _rodar "$base" sync --enviar --origem "$base/local" --destino -
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'destino em fluxo'
  assert_contem '--destino' "$DBX_ERRO" 'RF-45: a recusa nomeia o sinalizador'
}

teste_carimbo_de_tempo_nao_participa_de_decisao() {
  # RF-39 sob DP-27: a proibicao passou a ser TOTAL, porque a etapa de ordenacao
  # deixou de existir. `mtime` so pode aparecer para decidir reaproveitamento de
  # resumo ja calculado, e isso mora em lib/state.
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/sync.sh" |
    grep -nE 'mtime|client_modified|server_modified' || true)
  assert_igual '' "$achados" "carimbo de tempo em lib/sync: $achados"
}

# ---------------------------------------------------------------------------
# Tabela de decisao (5.8.2)
# ---------------------------------------------------------------------------

teste_transfere_o_que_so_existe_na_origem_e_omite_identico() {
  local base resumo
  base=$(_cenario '{"entries":[],"has_more":false}')
  printf 'um' >"$base/local/um.txt"
  printf 'dois' >"$base/local/dois.txt"
  # O resumo do arquivo que ja existe do outro lado precisa ser o real, senao a
  # linha "conteudo identico" nunca seria exercitada.
  resumo=$(bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$base/local/um.txt'")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/um.txt' "$resumo" 2)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=dois.txt' "$DBX_SAIDA" 'ausente no destino: transferir'
  assert_nao_contem 'transferir=um.txt' "$DBX_SAIDA" 'RF-33: conteudo identico nao transfere'
  assert_contem 'identicos=1' "$DBX_SAIDA" 'o contador de omitidos declara a omissao'
}

teste_conteudo_divergente_transfere_com_a_origem_prevalecendo() {
  local base
  base=$(_cenario)
  printf 'novo conteudo' >"$base/local/x.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/x.txt' '0000000000000000000000000000000000000000000000000000000000000000' 5)" \
    >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem 'transferir=x.txt' "$DBX_SAIDA" 'divergencia resolve a favor da origem'
}

teste_resumo_remoto_malformado_nunca_e_lido_como_identico() {
  # A falha aqui nao teria sintoma: omitir transferencia nao emite operacao, e o
  # relatorio diria que esta tudo sincronizado.
  local base
  base=$(_cenario)
  printf 'conteudo' >"$base/local/y.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/y.txt' 'nao-e-resumo' 8)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem 'transferir=y.txt' "$DBX_SAIDA" 'resumo ilegivel obriga a transferir'
}

# ---------------------------------------------------------------------------
# As quatro barreiras que sobraram (RSK-35)
# ---------------------------------------------------------------------------

teste_sem_espelhar_nenhuma_exclusao_e_emitida() {
  # RF-40: o padrao e preservar. O caminho so no destino e reportado como
  # divergencia nao propagada, e nao apagado.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/fica.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'apenas_no_destino=orfao.txt' "$DBX_SAIDA" 'a divergencia e reportada'
  assert_igual 0 "$(_exclusoes "$base")" 'RF-40: zero exclusoes sem espelhamento'
}

teste_travessia_parcial_desabilita_exclusao_na_execucao_inteira() {
  # RF-41(a). O ramo ilegivel esta em PROFUNDIDADE, e o efeito precisa alcancar a
  # execucao toda — inclusive o orfao que nao tem relacao com o ramo que falhou.
  # Mutacao que restrinja o efeito ao ramo com erro reprova aqui.
  local base
  base=$(_cenario)
  mkdir -p "$base/local/sub/fundo"
  printf 'a' >"$base/local/raiz.txt"
  printf 'b' >"$base/local/sub/fundo/dentro.txt"
  chmod 000 "$base/local/sub/fundo"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  chmod 755 "$base/local/sub/fundo"
  assert_igual 0 "$(_exclusoes "$base")" 'RF-41a: zero exclusoes com travessia parcial'
  assert_contem 'exclusao_desabilitada=' "$DBX_SAIDA" 'o relatorio declara por que nao apagou'
  assert_diferente 0 "$DBX_ESTADO" 'RF-41a: o codigo de saida difere de zero'
}

teste_vinculo_simbolico_tambem_desabilita_exclusao() {
  # O ramo do outro lado do vinculo e invisivel para a origem, e invisivel
  # produz a mesma observacao que apagado.
  local base fora
  base=$(_cenario)
  fora=$(mktemp -d "$DBX_TESTES_TMP/fora.XXXXXX")
  printf 'a' >"$base/local/fica.txt"
  ln -s "$fora" "$base/local/atalho"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_exclusoes "$base")" 'vinculo pulado tambem desabilita exclusao'
}

teste_origem_vazia_com_memoria_povoada_recusa_integralmente() {
  # RF-41(b). Uma raiz que ficou vazia por engano — ponto de montagem que nao
  # subiu — e indistinguivel de uma esvaziada de proposito.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/um.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "primeira execucao deve concluir; diagnostico: $DBX_ERRO"
  rm -f "$base/local/um.txt"
  : >"$base/chamadas"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_diferente 0 "$DBX_ESTADO" 'origem vazia com memoria povoada e recusa'
  assert_igual 0 "$(_escritas "$base")" 'RF-41b: recusa INTEGRAL, sem nenhuma escrita'
}

teste_primeira_execucao_com_espelhamento_exige_reconhecimento() {
  # RF-48, com a razao invertida por DP-27: nao e mais que "sem base nada pode
  # ser apagado" — e que sem base TUDO pode.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/um.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_diferente 0 "$DBX_ESTADO" 'primeira execucao com espelhamento sem reconhecimento'
  assert_contem '--dry-run' "$DBX_ERRO" 'o diagnostico oferece a simulacao'
  assert_contem '--confirmar' "$DBX_ERRO" 'o diagnostico oferece a confirmacao'
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita antes do reconhecimento'
}

teste_exclusoes_sao_anunciadas_antes_de_executadas() {
  # RF-41(d) e RF-47: a lista completa sai antes da primeira exclusao, e o
  # registro e NOMINAL.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/fica.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sai.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_contem 'apagar=sai.txt' "$DBX_SAIDA" 'RF-47: a perda e registrada nominalmente'
  assert_contem 'a_apagar=1' "$DBX_SAIDA" 'o total sai antes da execucao'
  assert_igual 1 "$(_exclusoes "$base")" 'com espelhamento e travessia sa, a exclusao ocorre'
}

# ---------------------------------------------------------------------------
# Simulacao, idempotencia e a memoria que nao decide (DP-27b)
# ---------------------------------------------------------------------------

teste_simulacao_imprime_o_plano_e_nao_escreve() {
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/um.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sai.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json --dry-run sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual 0 "$DBX_ESTADO" "RF-44: a simulacao deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=um.txt' "$DBX_SAIDA" 'o plano lista a transferencia'
  assert_contem 'apagar=sai.txt' "$DBX_SAIDA" 'o plano lista a exclusao'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'a simulacao se declara'
  assert_igual 0 "$(_escritas "$base")" 'RF-15: simulacao nao emite escrita'
}

teste_segunda_execucao_sem_alteracao_nao_emite_escrita() {
  # Idempotencia verificavel (RF-37). Sem ela, um `sync` periodico reenviaria a
  # arvore inteira a cada execucao.
  local base resumo
  base=$(_cenario)
  printf 'um' >"$base/local/um.txt"
  resumo=$(bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$base/local/um.txt'")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/um.txt' "$resumo" 2)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  : >"$base/chamadas"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "segunda execucao deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita quando nada mudou'
}

teste_apagar_a_memoria_nao_muda_o_conjunto_de_operacoes() {
  # A VERIFICACAO QUE FIXA DP-27b, e ela e o par de mutacao de RSK-23: se a
  # memoria voltar a arbitrar, os dois planos divergem. Sem este caso, um cache
  # que decide passaria despercebido — porque cache que decide errado OMITE
  # operacao, e omissao nao aparece em relatorio.
  local base plano_com plano_sem
  base=$(_cenario)
  printf 'um' >"$base/local/um.txt"
  printf 'dois' >"$base/local/dois.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  plano_com=$(grep '^transferir=' <<<"$DBX_SAIDA" | sort)
  rm -rf "$base/estado"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  plano_sem=$(grep '^transferir=' <<<"$DBX_SAIDA" | sort)
  assert_igual "$plano_com" "$plano_sem" \
    'memoria apagada nao pode mudar o conjunto de operacoes decididas'
}

teste_recebimento_grava_no_local_e_cria_as_pastas_intermediarias() {
  local base
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sub/fundo/a.txt' 'ff' 3)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'sentido=receber' "$DBX_SAIDA" 'o sentido apurado e declarado'
  assert_arquivo_existe "$base/local/sub/fundo/a.txt" 'as pastas intermediarias sao criadas'
}

teste_recebimento_cria_diretorio_de_destino_caso_nao_exista() {
  local base
  base=$(_cenario)
  local destino_novo="$base/local/nova_pasta/subpasta"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 3)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$destino_novo"
  assert_igual 0 "$DBX_ESTADO" "recebimento com destino novo deve concluir; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$destino_novo" 'o diretorio raiz de destino inexistente deve ser criado'
  assert_sucesso test -d "$destino_novo"
  assert_arquivo_existe "$destino_novo/a.txt" 'o arquivo deve ser gravado dentro do novo destino'
}

teste_sync_com_progresso_emite_em_stderr_e_preserva_stdout() {
  local base
  base=$(_cenario)
  printf 'conteudo' >"$base/local/a.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[sync' "$DBX_ERRO" 'stderr deve conter marcadores de progresso do sync'
  assert_nao_contem '[sync' "$DBX_SAIDA" 'stdout nao pode ser contaminado com progresso'
}

teste_sync_com_progresso_lista_arquivos_e_resultados_da_analise() {
  local base
  base=$(_cenario)
  printf 'conteudo 1' >"$base/local/arq1.txt"
  printf 'conteudo 2' >"$base/local/arq2.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'analisando local (1/2): arq' "$DBX_ERRO" 'deve listar analise de arquivo local'
  assert_contem 'analise [' "$DBX_ERRO" 'deve listar resultado da analise'
  assert_contem 'novo (a enviar)' "$DBX_ERRO" 'resultado deve classificar arquivo novo'
}

teste_sync_com_progresso_exibe_andamento_da_consulta_remota() {
  local base
  base=$(_cenario)
  printf 'conteudo 1' >"$base/local/arq1.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_entrada_remota '/r/rem1.txt' 'hash1' 10)" \
    "$(_entrada_remota '/r/rem2.txt' 'hash2' 20)" \
    >"$base/listagem"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'consultando arquivos remotos em: /r' "$DBX_ERRO" 'deve anunciar inicio da consulta remota'
  assert_contem 'consultando remoto (1): rem1.txt' "$DBX_ERRO" 'deve exibir progresso do primeiro arquivo remoto'
  assert_contem 'consultando remoto (2): rem2.txt' "$DBX_ERRO" 'deve exibir progresso do segundo arquivo remoto'
  assert_contem 'arquivos remotos consultados: 2 arquivo(s)' "$DBX_ERRO" 'deve exibir total de arquivos remotos consultados'
  assert_nao_contem 'consultando remoto' "$DBX_SAIDA" 'stdout nao pode conter mensagens de progresso'
}

teste_sync_com_progresso_exibe_andamento_da_analise_local() {
  local base
  base=$(_cenario)
  printf 'conteudo 1' >"$base/local/arq1.txt"
  printf 'conteudo 2' >"$base/local/arq2.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'analisando arquivos locais em: ' "$DBX_ERRO" 'deve anunciar inicio da analise local'
  assert_contem 'analisando local (1/2): arq' "$DBX_ERRO" 'deve exibir andamento do primeiro arquivo local'
  assert_contem 'analisando local (2/2): arq' "$DBX_ERRO" 'deve exibir andamento do segundo arquivo local'
  assert_contem 'arquivos locais analisados: 2 arquivo(s)' "$DBX_ERRO" 'deve exibir total de arquivos locais analisados'
  assert_nao_contem 'analisando local' "$DBX_SAIDA" 'stdout nao pode conter mensagens de progresso'
}

# ---------------------------------------------------------------------------
# Caixa de caminho (RF-54, DP-31): a Dropbox nao diferencia caixa
# ---------------------------------------------------------------------------

teste_caixa_diferente_e_o_mesmo_arquivo_e_espelhar_nao_apaga_o_enviado() {
  # TC-CX-01 e TC-CX-02. Antes, o par virava "transferir" + "apagar", e o
  # `delete_v2` removia o arquivo que acabara de ser enviado.
  local base
  base=$(_cenario)
  mkdir -p "$base/local/Docs"
  printf 'novo' >"$base/local/Docs/Foto.JPG"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/docs/foto.jpg' "$RESUMO_ZERADO" 4)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=Docs/Foto.JPG' "$DBX_SAIDA" 'o conteudo divergente e enviado'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'RF-54(a): o par nao entra no plano de exclusao'
  assert_nao_contem 'apagar=docs/foto.jpg' "$DBX_SAIDA" 'RF-54(a): nenhum apagar para o mesmo arquivo'
  assert_igual 0 "$(_exclusoes "$base")" 'RF-54(b): nenhuma exclusao remota atinge o enviado'
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/chamadas")" 'um unico envio'
  assert_contem '/r/docs/foto.jpg' "$(cat "$base/opcoes")" \
    'a escrita usa a grafia que o destino ja tem'
}

teste_caixa_diferente_com_conteudo_identico_e_omitido() {
  local base resumo
  base=$(_cenario)
  printf 'igual' >"$base/local/LEIA.txt"
  resumo=$(_resumo_de "$base/local/LEIA.txt")
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/leia.TXT' "$resumo" 5)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'identicos=1' "$DBX_SAIDA" 'o mesmo arquivo com conteudo igual e omitido'
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita para arquivo identico'
}

teste_colisao_de_caixa_local_e_recusada_antes_de_qualquer_escrita() {
  # TC-CX-03: `a.txt` e `A.txt` sao o MESMO caminho na Dropbox. Enviar os dois
  # faria um sobrescrever o outro em silencio.
  local base modo
  base=$(_cenario)
  printf 'minusculo' >"$base/local/a.txt"
  printf 'MAIUSCULO' >"$base/local/A.txt"
  for modo in --dry-run --json; do
    : >"$base/chamadas"
    _rodar "$base" --json "$modo" sync --enviar --origem "$base/local" --destino /r
    assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" \
      "RF-54(c): colisao de caixa recusada ($modo)"
    assert_contem 'a.txt' "$DBX_ERRO" 'o diagnostico nomeia um dos caminhos'
    assert_contem 'A.txt' "$DBX_ERRO" 'o diagnostico nomeia o outro caminho'
    assert_igual 0 "$(_escritas "$base")" 'RF-54(c): nenhuma escrita remota'
    assert_nao_contem 'transferir=' "$DBX_SAIDA" 'nenhum plano e emitido'
  done
}

teste_colisao_de_caixa_no_destino_local_recusa_o_recebimento() {
  local base
  base=$(_cenario)
  printf 'minusculo' >"$base/local/a.txt"
  printf 'MAIUSCULO' >"$base/local/A.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 3)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" 'RF-54(c): recusa tambem no recebimento'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" 'nenhum recebimento emitido'
  assert_igual 'minusculo' "$(cat "$base/local/a.txt")" 'o local fica intacto'
  assert_igual 'MAIUSCULO' "$(cat "$base/local/A.txt")" 'o local fica intacto'
}

teste_recebimento_com_caixa_diferente_grava_no_arquivo_local_existente() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/docs"
  printf 'antigo' >"$base/local/docs/foto.jpg"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/Docs/Foto.JPG' "$RESUMO_ZERADO" 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 'conteudo remoto' "$(cat "$base/local/docs/foto.jpg")" 'o arquivo local existente e atualizado'
  assert_arquivo_ausente "$base/local/Docs" 'nenhuma copia com a grafia remota e criada'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'RF-54: o mesmo arquivo nao e apagado no local'
}

# ---------------------------------------------------------------------------
# Recebimento atomico no sync (RF-55(e)) e umask (RNF-29)
# ---------------------------------------------------------------------------

teste_recebimento_com_hash_divergente_preserva_o_arquivo_local() {
  local base
  base=$(_cenario)
  printf 'antigo' >"$base/local/a.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf '{"name":"a.txt","content_hash":"%s"}' "$RESUMO_ZERADO" >"$base/resultado_cabecalho"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" \
    'RF-55(e): divergencia conta como falha do item'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'a falha e contada'
  assert_igual 'antigo' "$(cat "$base/local/a.txt")" 'RF-55(b): o arquivo anterior fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/local")" 'RF-55(b): sem temporario'
}

teste_recebimento_com_hash_conferido_substitui_sem_temporario() {
  local base resumo
  base=$(_cenario)
  printf 'antigo' >"$base/local/a.txt"
  printf 'conteudo remoto' >"$base/referencia"
  resumo=$(_resumo_de "$base/referencia")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$base/resultado_cabecalho"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 'conteudo remoto' "$(cat "$base/local/a.txt")" 'RF-55(d): conteudo novo'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/local")" 'RF-55(d): sem temporario'
}

teste_recebimento_segue_o_umask_do_usuario() {
  local base
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sub/a.txt' ff 15)" >"$base/listagem"
  umask 022
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 755 "$(stat -c %a "$base/local/sub")" 'RNF-29(a): diretorio criado segue o umask'
  assert_igual 644 "$(stat -c %a "$base/local/sub/a.txt")" 'RNF-29(a): arquivo recebido segue o umask'
}

# ---------------------------------------------------------------------------
# Envio pelo caminho do upload (RF-57) com concorrencia otimista (RF-49)
# ---------------------------------------------------------------------------

teste_envio_define_client_modified() {
  local base
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'client_modified' "$(cat "$base/opcoes")" 'RF-57(b): o envio carrega client_modified'
}

teste_envio_sobre_arquivo_existente_carrega_o_rev_da_listagem() {
  # TC-REV-01: o rev lido NAQUELA execucao viaja com a escrita; arquivo novo
  # vai em modo add, sem renomeacao automatica.
  local base opcoes
  base=$(_cenario)
  printf 'novo conteudo' >"$base/local/x.txt"
  printf 'arquivo novo' >"$base/local/y.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota_com_rev '/r/x.txt' "$RESUMO_ZERADO" 5 015abc)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  # O argumento viaja com as aspas escapadas no arquivo de opcoes do cliente.
  opcoes=$(grep 'Dropbox-API-Arg' "$base/opcoes")
  assert_contem '\"update\":\"015abc\"' "$(grep '/r/x.txt' <<<"$opcoes")" 'RF-49: o envio carrega o rev esperado'
  assert_contem '\"mode\":\"add\"' "$(grep '/r/y.txt' <<<"$opcoes")" 'arquivo novo vai em modo add'
  assert_contem '\"autorename\":false' "$(grep '/r/y.txt' <<<"$opcoes")" 'sem renomeacao automatica'
  assert_nao_contem 'overwrite' "$opcoes" 'o envio nunca sobrescreve as cegas'
}

teste_conflito_de_rev_nao_sobrescreve_e_conta_como_falha() {
  # TC-REV-02: mudanca remota concorrente. O item falha, os demais seguem e o
  # codigo de saida e o de operacao nao concluida.
  local base
  base=$(_cenario)
  printf 'novo conteudo' >"$base/local/x.txt"
  printf 'arquivo novo' >"$base/local/y.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota_com_rev '/r/x.txt' "$RESUMO_ZERADO" 5 015abc)" >"$base/listagem"
  printf '/r/x.txt' >"$base/upload_conflito"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" \
    'RF-49: conflito sai como operacao nao concluida'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'o item em conflito conta como falha'
  assert_contem 'enviados=1' "$DBX_SAIDA" 'os demais itens seguem'
  assert_igual 2 "$(_harness_contar 'files/upload$' "$base/chamadas")" 'uma tentativa por item, sem repeticao'
}

teste_envio_acima_do_teto_vai_por_sessao_com_rev() {
  # TC-SYE-01. Arquivo esparso: o que se verifica e o roteamento por tamanho
  # medido, sem materializar 150 MiB de conteudo.
  local base
  base=$(_cenario)
  dd if=/dev/null of="$base/local/grande.bin" bs=1 seek=$((157286400 + 1)) 2>/dev/null ||
    pular 'nao foi possivel criar arquivo esparso acima do teto'
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota_com_rev '/r/grande.bin' "$RESUMO_ZERADO" 3 R9)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_harness_contar 'files/upload$' "$base/chamadas")" \
    'RF-57(a): nenhuma requisicao unica acima do teto'
  assert_igual 1 "$(_harness_contar 'upload_session/start' "$base/chamadas")" 'RF-57(a): uma sessao'
  assert_igual 1 "$(_harness_contar 'upload_session/finish' "$base/chamadas")" 'RF-57(a): uma conclusao'
  assert_contem '\"update\":\"R9\"' "$(grep 'grande.bin' "$base/opcoes")" \
    'RF-49: o finish da sessao carrega o rev esperado'
}

teste_envio_do_sync_mantem_mute_verdadeiro() {
  local base
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '\"mute\":true' "$(grep 'Dropbox-API-Arg' "$base/opcoes")" \
    'o sync envia sem notificar, como antes'
}

# ---------------------------------------------------------------------------
# Temporario de recebimento orfao (`.<nome>.dbx-part.XXXXXX`)
# ---------------------------------------------------------------------------

teste_temporario_de_recebimento_nao_e_enviado_nem_entra_no_plano() {
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  mkdir -p "$base/local/sub"
  printf 'parcial' >"$base/local/sub/.b.txt.dbx-part.Ab12Cd"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'a_transferir=1' "$DBX_SAIDA" 'so o arquivo real entra no plano'
  assert_nao_contem 'dbx-part' "$DBX_SAIDA" 'o temporario nao aparece no plano'
  assert_nao_contem 'dbx-part' "$(cat "$base/opcoes")" 'o temporario nunca e enviado'
}

teste_temporario_de_recebimento_nao_entra_na_exclusao_local() {
  local base
  base=$(_cenario)
  printf 'parcial' >"$base/local/.x.txt.dbx-part.Zz99Yy"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'o temporario nao conta como arquivo local'
  assert_nao_contem 'dbx-part' "$DBX_SAIDA" 'o temporario nao aparece no plano'
  assert_contem 'apagados=0' "$DBX_SAIDA" 'nada e apagado'
}

teste_recebimento_sobre_arquivo_somente_leitura_falha_o_item_e_segue() {
  local base
  base=$(_cenario)
  printf 'antigo' >"$base/local/a.txt"
  chmod 444 "$base/local/a.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_entrada_remota '/r/a.txt' ff 15)" "$(_entrada_remota '/r/b.txt' ff 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'o item recusado torna a execucao nao concluida'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'o arquivo somente leitura conta como falha'
  assert_contem 'recebidos=1' "$DBX_SAIDA" 'os demais itens seguem'
  assert_igual 'antigo' "$(cat "$base/local/a.txt")" 'o arquivo fica intacto'
  assert_igual 444 "$(stat -c %a "$base/local/a.txt")" 'o modo fica intacto'
  assert_igual $'a.txt\nb.txt' "$(_conteudo_do_diretorio "$base/local")" 'nao resta temporario'
}

harness_executar "$@"
