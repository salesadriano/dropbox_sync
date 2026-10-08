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
    printf 'cat >>"$base/opcoes" 2>/dev/null\n'
    printf 'saida=""; escrever=""; anterior=""; url=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac\n'
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
    printf '  *) corpo=%s ;;\n' "'{\"name\":\"x\",\"rev\":\"1\"}'"
    printf 'esac\n'
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
  plano_com=$(printf '%s\n' "$DBX_SAIDA" | grep '^transferir=' | sort)
  rm -rf "$base/estado"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  plano_sem=$(printf '%s\n' "$DBX_SAIDA" | grep '^transferir=' | sort)
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

harness_executar "$@"
