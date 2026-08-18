#!/usr/bin/env bash
# Testes de lib/output.sh — modelo de resultado unico, duas apresentacoes.
# RF-28 (saida estruturada parseavel), RF-35 (contrato congelado),
# RNF-19 (deteccao de terminal, sobreponivel), RNF-22 (restricao de linha).

# shellcheck disable=SC2016
# Justificativa: casos usam cifrao e chaves como dado de teste e entregam
# script literal a "bash -c", que precisa chegar sem expansao.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"

_iniciar() {
  dbx_output_iniciar
  dbx_output_modo estruturada
}

# ---------------------------------------------------------------------------
# Contrato de automacao (RF-35)
# ---------------------------------------------------------------------------

teste_versao_do_contrato_e_declarada_e_congelada() {
  assert_igual 1 "$DBX_OUTPUT_VERSAO_CONTRATO" \
    'a versao principal do contrato de saida e parte do acordo com o consumidor'
  _iniciar
  dbx_output_campo tipo arquivo
  assert_contem 'contrato=1' "$(dbx_output_render)" \
    'a saida estruturada declara a versao do contrato'
}

teste_apresentacoes_derivam_do_mesmo_modelo() {
  local estruturada humana
  _iniciar
  dbx_output_campo caminho /a/b.txt
  dbx_output_campo tamanho 1024
  estruturada=$(dbx_output_render)
  dbx_output_modo humana
  humana=$(dbx_output_render)
  assert_contem '/a/b.txt' "$estruturada"
  assert_contem '/a/b.txt' "$humana"
  assert_diferente "$estruturada" "$humana" 'as duas apresentacoes nao podem ser identicas'
}

teste_saida_estruturada_nao_tem_texto_decorativo() {
  local saida linha
  _iniciar
  dbx_output_campo caminho /a.txt
  saida=$(dbx_output_render)
  while IFS= read -r linha; do
    [[ -z $linha ]] && continue
    if [[ $linha != *=* ]]; then
      _harness_falhar "linha nao parseavel na apresentacao estruturada: [$linha]"
    fi
  done <<<"$saida"
}

# ---------------------------------------------------------------------------
# RNF-19 — deteccao de terminal, sobreponivel nos dois sentidos
# ---------------------------------------------------------------------------

teste_sem_terminal_assume_apresentacao_estruturada() {
  local saida
  saida=$(timeout 20 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/output.sh"
    dbx_output_iniciar; dbx_output_campo k v; dbx_output_render
  ' _ "$DBX_HARNESS_RAIZ" </dev/null 2>/dev/null)
  assert_contem 'contrato=1' "$saida" \
    'sem terminal associado a apresentacao padrao e a estruturada'
}

teste_sinalizador_explicito_prevalece_nos_dois_sentidos() {
  local saida
  _iniciar
  dbx_output_modo humana
  dbx_output_campo k v
  saida=$(dbx_output_render)
  assert_nao_contem 'contrato=1' "$saida" 'o sinalizador humano prevalece sem terminal'

  dbx_output_modo estruturada
  saida=$(dbx_output_render)
  assert_contem 'contrato=1' "$saida" 'e o inverso tambem'
}

teste_modo_invalido_e_recusado() {
  _iniciar
  assert_status 2 dbx_output_modo talvez
}

# ---------------------------------------------------------------------------
# DIV-16b — modo `--null`, padrao `find -print0` / `xargs -0`
# ---------------------------------------------------------------------------

teste_modo_nulo_usa_terminador_nulo() {
  local bytes
  _iniciar
  dbx_output_terminador nulo
  dbx_output_campo caminho /a.txt
  bytes=$(dbx_output_render | od -An -c | tr -s ' ')
  assert_contem '\0' "$bytes" 'o terminador precisa ser o byte nulo'
}

teste_nome_com_quebra_de_linha_sobrevive_no_modo_nulo() {
  # E a razao de existir do modo: em saida por linhas, o nome se parte em dois
  # registros e o consumidor le dois itens onde ha um.
  local caminho contagem
  caminho="/pasta/nome"$'\n'"quebrado.txt"
  _iniciar
  dbx_output_terminador nulo
  dbx_output_campo caminho "$caminho"
  contagem=$(dbx_output_render | tr -cd '\0' | wc -c)
  assert_igual 2 "$contagem" 'um registro por campo, mesmo com quebra de linha no valor'
}

teste_nome_com_espaco_e_controle_no_modo_nulo() {
  local saida
  _iniciar
  dbx_output_terminador nulo
  dbx_output_campo caminho '/pasta/com espaco e $cifrao.txt'
  saida=$(dbx_output_render | tr '\0' '\n')
  assert_contem 'com espaco e $cifrao.txt' "$saida"
}

teste_modo_nulo_e_ortogonal_a_deteccao_de_terminal() {
  # O terminador e escolha de formato; a apresentacao e escolha de publico.
  _iniciar
  dbx_output_terminador nulo
  dbx_output_modo humana
  dbx_output_campo k v
  assert_sucesso dbx_output_render
}

teste_terminador_invalido_e_recusado() {
  _iniciar
  assert_status 2 dbx_output_terminador outro
}

# ---------------------------------------------------------------------------
# RNF-22 — restricao dura: diagnostico nunca na linha de cabecalho sensivel
# ---------------------------------------------------------------------------

teste_identificador_de_requisicao_fica_em_linha_propria() {
  # TC-RED-01: o identificador precisa sobreviver a redacao do cabecalho.
  local saida
  _iniciar
  dbx_output_diagnostico 'Authorization' 'Bearer sl.TokenSecretoAbc'
  dbx_output_diagnostico 'X-Dropbox-Request-Id' 'req-abc-123'
  saida=$(dbx_output_render_diagnostico 2>&1)
  saida=$(dbx_errors_redigir "$saida")
  assert_nao_contem 'sl.TokenSecretoAbc' "$saida" 'o segredo precisa ser redigido'
  assert_contem 'req-abc-123' "$saida" \
    'o identificador de correlacao precisa sobreviver a redacao (RF-30, RNF-22)'
}

teste_diagnostico_nunca_concatena_na_linha_do_cabecalho() {
  # TC-RED-02: verificacao estrutural, independente da redacao.
  local saida linha sensiveis=0
  _iniciar
  dbx_output_diagnostico 'Authorization' 'Bearer sl.Token'
  dbx_output_diagnostico 'X-Dropbox-Request-Id' 'req-1'
  dbx_output_diagnostico 'Cookie' 'sessao=abc'
  dbx_output_diagnostico 'endpoint' '/2/files/get_metadata'
  saida=$(dbx_output_render_diagnostico 2>&1)
  while IFS= read -r linha; do
    [[ -z $linha ]] && continue
    if [[ $linha == *[Aa]uthorization* || $linha == *[Cc]ookie* ]]; then
      sensiveis=$((sensiveis + 1))
      if [[ $linha == *equest* || $linha == *endpoint* ]]; then
        _harness_falhar "campo de diagnostico concatenado a cabecalho sensivel: [$linha]"
      fi
    fi
  done <<<"$saida"
  [[ $sensiveis -ge 2 ]] || _harness_falhar 'os cabecalhos sensiveis nao foram emitidos'
}

teste_restricao_de_linha_vale_tambem_no_modo_nulo() {
  # O terminador nulo nao dispensa a restricao. A verificacao e feita sobre a
  # saida COMO ELA SAI, sem converter o terminador antes: converter criaria a
  # propria fronteira que o caso precisa verificar que o componente produz —
  # vicio que o QA encontrou no irmao deste caso (P5a).
  local saida registro sensivel=0
  _iniciar
  dbx_output_terminador nulo
  dbx_output_diagnostico 'Authorization' 'Bearer sl.Token'
  dbx_output_diagnostico 'X-Dropbox-Request-Id' 'req-2'
  saida=$(dbx_output_render_diagnostico 2>&1 | tr '\0' '\n')
  while IFS= read -r registro; do
    [[ -z $registro ]] && continue
    if [[ $registro == *[Aa]uthorization* ]]; then
      sensivel=1
      if [[ $registro == *equest* ]]; then
        _harness_falhar "diagnostico concatenado ao cabecalho sensivel no modo nulo: [$registro]"
      fi
    fi
  done <<<"$saida"
  [[ $sensivel -eq 1 ]] || _harness_falhar 'o cabecalho sensivel nao foi emitido'
}

teste_identificador_sobrevive_no_modo_nulo() {
  # Verificacao por BYTES, em arquivo, e nao por variavel: o `bash` nao carrega
  # o byte nulo em variavel, e capturar a saida em `$( )` juntaria os registros,
  # destruindo justamente a fronteira sob teste.
  #
  # A redacao ja foi aplicada por valor ao alimentar o modelo, entao nao ha
  # segunda passada sobre o fluxo renderizado.
  local arquivo
  arquivo="${DBX_TESTES_TMP:-/tmp}/dbx-diag.$$"
  _iniciar
  dbx_output_terminador nulo
  dbx_output_diagnostico 'Authorization' 'Bearer sl.TokenSecretoAbc'
  dbx_output_diagnostico 'X-Dropbox-Request-Id' 'req-abc-999'
  dbx_output_render_diagnostico 2>"$arquivo"
  if ! grep -qa 'req-abc-999' "$arquivo"; then
    rm -f "$arquivo"
    _harness_falhar 'o identificador de correlacao nao sobreviveu (RF-30, RNF-22)'
  fi
  if grep -qa 'sl.TokenSecretoAbc' "$arquivo"; then
    rm -f "$arquivo"
    _harness_falhar 'o segredo vazou na saida de diagnostico'
  fi
  rm -f "$arquivo"
}

teste_redacao_e_aplicada_ao_alimentar_o_modelo() {
  # A protecao nao pode depender de alguem a jusante lembrar de redigir.
  _iniciar
  dbx_output_diagnostico 'Authorization' 'Bearer sl.TokenSecretoAbc'
  assert_nao_contem 'sl.TokenSecretoAbc' "${DBX_OUTPUT_DIAG_VALORES[0]}" \
    'o valor precisa entrar no modelo ja mascarado'
  assert_contem 'REDIGIDO' "${DBX_OUTPUT_DIAG_VALORES[0]}"
}

# ---------------------------------------------------------------------------
# Separacao de canais e ausencia de estado
# ---------------------------------------------------------------------------

teste_diagnostico_nao_vai_para_a_saida_padrao() {
  local padrao
  _iniciar
  dbx_output_campo k v
  dbx_output_diagnostico 'endpoint' '/2/x'
  padrao=$(dbx_output_render)
  assert_nao_contem 'endpoint' "$padrao" \
    'diagnostico pertence a saida de erro, nao a saida padrao (RF-28)'
}

teste_iniciar_descarta_o_resultado_anterior() {
  _iniciar
  dbx_output_campo antigo valor
  dbx_output_iniciar
  dbx_output_modo estruturada
  dbx_output_campo novo valor
  assert_nao_contem 'antigo' "$(dbx_output_render)" \
    'resultado residual entre execucoes seria estado nao declarado'
}

teste_nao_escreve_em_disco() {
  # PRJ-DEC-07: a camada de adaptadores e onde um cache conveniente
  # reintroduziria estado local persistente.
  local alvo="$DBX_HARNESS_RAIZ/lib/output.sh" codigo
  codigo=$(grep -vE '^[[:space:]]*#' "$alvo")
  if printf '%s\n' "$codigo" | grep -qE '(^|[^_a-zA-Z])(mktemp|tee)([^_a-zA-Z]|$)'; then
    _harness_falhar 'lib/output.sh cria artefato em disco'
  fi
  if printf '%s\n' "$codigo" | grep -qE '>[[:space:]]*"?\$(HOME|XDG)'; then
    _harness_falhar 'lib/output.sh escreve no diretorio do usuario'
  fi
}

# ---------------------------------------------------------------------------
# E2-05 — modo linha nao pode corromper registro em silencio
# ---------------------------------------------------------------------------

teste_valor_com_quebra_de_linha_e_recusado_em_modo_linha() {
  # A corrupcao era silenciosa: um registro virava dois e o consumidor lia campo
  # onde nao ha. A recusa e fechada e acontece ANTES de qualquer emissao.
  _iniciar
  dbx_output_campo caminho "/pasta/nome"$'\n'"quebrado.txt"
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_render
}

teste_recusa_em_modo_linha_nao_emite_saida_parcial() {
  local saida
  _iniciar
  dbx_output_campo primeiro ok
  dbx_output_campo segundo "com"$'\n'"quebra"
  saida=$(dbx_output_render 2>/dev/null || true)
  assert_nao_contem 'primeiro' "$saida" \
    'nenhum registro pode sair antes de a validacao reprovar'
}

teste_mesmo_valor_e_aceito_em_modo_nulo() {
  # A acao corretiva da recusa e o terminador nulo; ele precisa funcionar.
  _iniciar
  dbx_output_terminador nulo
  dbx_output_campo caminho "/pasta/nome"$'\n'"quebrado.txt"
  assert_sucesso dbx_output_render
}

teste_tabulacao_e_retorno_de_carro_tambem_sao_recusados_em_modo_linha() {
  _iniciar
  dbx_output_campo k "com"$'\t'"tabulacao"
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_render
  _iniciar
  dbx_output_campo k "com"$'\r'"retorno"
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_render
}

# ---------------------------------------------------------------------------
# E2-06 — diagnostico na saida de erro (RF-28, prioridade P0)
# ---------------------------------------------------------------------------

teste_diagnostico_sai_na_saida_de_erro_e_nao_na_padrao() {
  local padrao erro
  _iniciar
  dbx_output_diagnostico 'endpoint' '/2/files/get_metadata'
  padrao=$(dbx_output_render_diagnostico 2>/dev/null)
  erro=$(dbx_output_render_diagnostico 2>&1 >/dev/null)
  assert_igual '' "$padrao" 'a saida padrao precisa ficar limpa para o consumidor'
  assert_contem 'endpoint' "$erro" 'o diagnostico pertence a saida de erro'
}

# ---------------------------------------------------------------------------
# E2-13 — a chave compoe a gramatica do registro e precisa ser validada
# ---------------------------------------------------------------------------

teste_chave_invalida_e_recusada() {
  _iniciar
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_campo '' valor
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_campo 'com=igual' valor
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_campo "com"$'\n'"quebra" valor
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_diagnostico 'com=igual' valor
  assert_sucesso dbx_output_campo 'chave_valida' valor
}

# ---------------------------------------------------------------------------
# E2-07 — listas de cabecalho sensivel precisam concordar entre componentes
# ---------------------------------------------------------------------------

teste_todo_cabecalho_isolado_aqui_e_redigido_pela_taxonomia() {
  local cabecalho saida
  for cabecalho in $DBX_OUTPUT_CABECALHOS_SENSIVEIS; do
    dbx_errors_redigir "$cabecalho: valor9pQrSecreto" >/dev/null
    assert_nao_contem 'valor9pQrSecreto' "$DBX_ERRORS_REDIGIDO" \
      "cabecalho isolado por lib/output mas nao redigido por lib/errors: $cabecalho"
  done
}

# ---------------------------------------------------------------------------
# E3-07 — o instrumento de teste nao pode interferir na propriedade observada
#
# `assert_status` desvia a saida para arquivo em vez de capturar com `$( )`.
# Substituicao de comando cria subshell, e funcao que mantem estado global teria
# esse estado descartado. A correcao estava certa e nao estava pinada: reverte-la
# nao reprovava nada. Este caso pina a propriedade.
# ---------------------------------------------------------------------------

teste_assert_status_nao_descarta_estado_da_funcao_observada() {
  _dbx_sonda_estado=''
  # shellcheck disable=SC2317  # invocada indiretamente por assert_status
  _dbx_sonda() {
    _dbx_sonda_estado='definido'
    return 7
  }
  assert_status 7 _dbx_sonda
  assert_igual 'definido' "$_dbx_sonda_estado" \
    'o instrumento nao pode rodar a funcao observada em subshell'
  unset -f _dbx_sonda
}

harness_executar "$@"
