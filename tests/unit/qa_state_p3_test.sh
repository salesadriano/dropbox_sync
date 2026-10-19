#!/usr/bin/env bash
# Suite independente do QA Expert — fase 3, nivel de modulo.
#
# Estado hostil sobre `lib/state` (RNF-25, RF-42, RF-61(a)), a fronteira da
# regra anti-corrida (RF-61(d)), a recusa do segredo na biblioteca (RF-63(a)) e
# a ausencia de regressao da P3.4 (`lib/errors`, `lib/http`) por tabela de
# referencia colhida do HEAD `007f3ec` (830 combinacoes identicas; ver o parecer
# do QA). Massa propria do QA; cada caso monta o seu `XDG_STATE_HOME`.
#
# shellcheck disable=SC2034
# Justificativa: canais lidos por referencia de nome nas bibliotecas.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"

readonly QA_H1='1111111111111111111111111111111111111111111111111111111111111111'
readonly QA_H2='2222222222222222222222222222222222222222222222222222222222222222'

_qa_area() {
  AREA=$(mktemp -d "$DBX_TESTES_TMP/qa_state.XXXXXX")
  export XDG_STATE_HOME="$AREA/xdg"
  ESTADO="$XDG_STATE_HOME/dbx"
}

_qa_antigo() { # <arquivo> <conteudo>
  printf '%s' "$2" >"$1"
  touch -d '@1700000000.250000000' "$1"
}

_qa_identidade() { # <arquivo> — publica IDENT
  dbx_hash_identidade "$1" || _harness_falhar "sem identidade para $1"
  IDENT=$DBX_HASH_IDENTIDADE
}

# ---------------------------------------------------------------------------
# Estado hostil
# ---------------------------------------------------------------------------

teste_qa_state_caminho_com_tab_e_quebra_de_linha_volta_intacto() {
  _qa_area
  _qa_antigo "$AREA/a.txt" 'conteudo'
  _qa_identidade "$AREA/a.txt"
  local estranho=$'pasta\tcom tab/linha\nnova.txt'
  dbx_state_carregar dbid:Q /o /d
  dbx_state_registrar "$estranho" "$QA_H1" "$IDENT" "$IDENT"
  assert_igual 0 $? 'registra caminho com TAB e quebra de linha'
  dbx_state_gravar dbid:Q /o /d sim
  dbx_state_carregar dbid:Q /o /d
  assert_igual 1 "${#DBX_STATE_ENTRADA[@]}" 'uma unica entrada, sem fragmentos'
  dbx_state_consultar "$estranho" "$IDENT"
  assert_igual "$QA_H1" "$DBX_STATE_HASH" 'o caminho volta intacto e reaproveita'
}

teste_qa_state_nul_no_meio_do_registro_nao_cria_entrada_espuria() {
  _qa_area
  _qa_antigo "$AREA/a.txt" 'conteudo'
  _qa_identidade "$AREA/a.txt"
  dbx_state_gravar dbid:Q /o /d
  dbx_state_caminho dbid:Q /o /d
  # Um NUL a mais parte o registro: a cauda nao tem campos e nao vira entrada.
  printf '2\0dbid:Q\0/o\0/d\0%s\t%s\tdir\0../../etc/passwd\0%s\t%s\0' \
    "$QA_H1" "$IDENT" "$QA_H2" "$IDENT" >"$DBX_STATE_RESULTADO"
  dbx_state_carregar dbid:Q /o /d
  assert_igual 1 "${#DBX_STATE_ENTRADA[@]}" 'so o registro completo entra'
  assert_igual '' "${DBX_STATE_ENTRADA[../../etc/passwd]:-}" 'a cauda partida nao e entrada'
}

teste_qa_state_registro_de_outro_namespace_e_rejeitado() {
  _qa_area
  _qa_antigo "$AREA/a.txt" 'conteudo'
  _qa_identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$QA_H1" "$IDENT" "$IDENT"
  dbx_state_upload_caminho /c/a.txt
  local registro_upload=$DBX_STATE_RESULTADO
  dbx_state_carregar dbid:Q /o /d
  dbx_state_registrar a.txt "$QA_H2" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:Q /o /d
  dbx_state_caminho dbid:Q /o /d
  local memoria=$DBX_STATE_RESULTADO
  # Conteudo do upload no nome da memoria: descartado (cabecalho nao casa).
  cp -- "$registro_upload" "$AREA/upload.bak"
  cp -- "$memoria" "$AREA/memoria.bak"
  cp -- "$AREA/upload.bak" "$memoria"
  dbx_state_carregar dbid:Q /o /d
  assert_igual 0 "${#DBX_STATE_ENTRADA[@]}" 'registro do upload nao vale como memoria'
  # Conteudo da memoria no nome do upload: rejeitado.
  cp -- "$AREA/memoria.bak" "$registro_upload"
  dbx_state_upload_consultar /c/a.txt "$IDENT"
  assert_igual 1 $? 'memoria do sync nao vale como registro do upload'
  # Registro valido de outra chave copiado para esta: rejeitado.
  dbx_state_upload_gravar /c/b.txt "$QA_H2" "$IDENT" "$IDENT"
  dbx_state_upload_caminho /c/b.txt
  cp -- "$DBX_STATE_RESULTADO" "$registro_upload"
  dbx_state_upload_consultar /c/a.txt "$IDENT"
  assert_igual 1 $? 'registro de outra chave nao e reaproveitado'
}

teste_qa_state_registro_como_ligacao_simbolica_nao_e_escrito_atraves() {
  _qa_area
  _qa_antigo "$AREA/a.txt" 'conteudo'
  _qa_identidade "$AREA/a.txt"
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  printf 'alvo do usuario' >"$AREA/alvo"
  dbx_state_upload_caminho /c/a.txt
  local registro=$DBX_STATE_RESULTADO
  ln -s "$AREA/alvo" "$registro"
  dbx_state_upload_gravar /c/a.txt "$QA_H1" "$IDENT" "$IDENT"
  assert_igual 'alvo do usuario' "$(cat "$AREA/alvo")" 'a gravacao nao escreve atraves da ligacao'
  [[ -f $registro && ! -L $registro ]] || _harness_falhar 'o registro vira arquivo regular'
  # Ligacao para arquivo de outro dono: nada e lido dela.
  if [[ -e /etc/passwd && ! -O /etc/passwd ]]; then
    rm -f -- "$registro"
    ln -s /etc/passwd "$registro"
    dbx_state_upload_consultar /c/a.txt "$IDENT"
    assert_igual 1 $? 'registro que aponta para arquivo alheio nao e lido'
    dbx_state_caminho dbid:Q /o /d
    ln -s /etc/passwd "$DBX_STATE_RESULTADO"
    dbx_state_carregar dbid:Q /o /d
    assert_igual 'nao' "$DBX_STATE_VISTO" 'memoria que aponta para arquivo alheio nao prova execucao'
  fi
}

teste_qa_state_diretorio_alheio_gravavel_devolve_permissao() {
  [[ $(id -u) -ne 0 ]] || pular 'nao se aplica a root'
  [[ -d /tmp && ! -O /tmp && -w /tmp ]] || pular '/tmp nao e alheio e gravavel aqui'
  _qa_area
  _qa_antigo "$AREA/a.txt" 'conteudo'
  _qa_identidade "$AREA/a.txt"
  mkdir -p "$XDG_STATE_HOME"
  ln -s /tmp "$ESTADO"
  local modo estado permissao
  modo=$(stat -c '%a' /tmp)
  permissao=$(dbx_errors_codigo_saida permissao)
  dbx_state_upload_gravar "/qa/p3/$$/a.txt" "$QA_H1" "$IDENT" "$IDENT"
  estado=$?
  assert_igual "$permissao" "$estado" 'upload: classe permissao'
  dbx_state_gravar dbid:Q "/qa/p3/$$" /d
  estado=$?
  assert_igual "$permissao" "$estado" 'sync: classe permissao'
  assert_igual "$modo" "$(stat -c '%a' /tmp)" 'modo do diretorio alheio intacto'
  dbx_state_upload_caminho "/qa/p3/$$/a.txt"
  assert_arquivo_ausente "$DBX_STATE_RESULTADO" 'nenhum registro no diretorio alheio'
}

# ---------------------------------------------------------------------------
# Regra anti-corrida na fronteira (RF-61(d))
# ---------------------------------------------------------------------------

teste_qa_state_anti_corrida_na_fronteira_de_dois_segundos() {
  local agora inicio identidade
  # Comeca no inicio de um segundo (espera por condicao), para que o relogio nao
  # vire entre a leitura de `agora` e a decisao.
  printf -v inicio '%(%s)T' -1
  printf -v agora '%(%s)T' -1
  while [[ $agora == "$inicio" ]]; do printf -v agora '%(%s)T' -1; done
  identidade="$((agora - 2))|t|t|1|2|10"
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 0 $? 'mtime ha 2 s registra'
  identidade="$((agora - 1))|t|t|1|2|10"
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 1 $? 'mtime ha 1 s nao registra'
  identidade="$((agora + 60))|t|t|1|2|10"
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 1 $? 'mtime no futuro nao registra'
  identidade="$((agora - 100))|t|t|1|2|0"
  dbx_state_registravel "$identidade" "$identidade"
  assert_igual 1 $? 'tamanho zero nao registra'
  dbx_state_registravel "$((agora - 100))|t|t|1|2" "$((agora - 100))|t|t|1|2"
  assert_igual 1 $? 'identidade com cinco campos nao registra'
}

# ---------------------------------------------------------------------------
# RF-63(a) na biblioteca
# ---------------------------------------------------------------------------

# _qa_duplo_rede — `curl` que so registra; publica DUPLO.
_qa_duplo_rede() {
  DUPLO=$(mktemp -d "$DBX_TESTES_TMP/qa_rede.XXXXXX")
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexit 0\n' "$DUPLO/argv" >"$DUPLO/curl"
  chmod +x "$DUPLO/curl"
}

teste_qa_auth_sem_segredo_recusa_antes_da_rede_na_classe_de_rf03() {
  # RF-63(a): "mesma classe e codigo de saida de RF-03" — configuracao.
  local esperado estado
  esperado=$(dbx_errors_codigo_saida configuracao)
  _qa_duplo_rede
  DBX_CONFIG_APP_KEY=ak DBX_CONFIG_APP_SECRET='' DBX_CONFIG_REFRESH_TOKEN=rt_qa_p3
  dbx_auth_esquecer
  PATH=$DUPLO:$PATH dbx_auth_renovar
  estado=$?
  assert_arquivo_ausente "$DUPLO/argv" 'renovacao: nenhuma chamada de rede'
  assert_igual "$esperado" "$estado" 'renovacao: classe e codigo de RF-03'
  PATH=$DUPLO:$PATH dbx_auth_trocar_codigo ak '' CODIGO_QA
  estado=$?
  assert_arquivo_ausente "$DUPLO/argv" 'troca: nenhuma chamada de rede'
  assert_igual "$esperado" "$estado" 'troca: classe e codigo de RF-03'
}

# ---------------------------------------------------------------------------
# P3.4 — classe, politica e codigo de saida iguais aos do HEAD
# ---------------------------------------------------------------------------

teste_qa_p34_classe_politica_e_codigo_iguais_a_referencia() {
  # http|resumo|idempotente|classe|politica — colhidos do HEAD 007f3ec.
  local -a tabela=(
    '0||sim|rede|recuo_exponencial'
    '200||sim|sucesso|nenhuma'
    '400|path/rate_limit/|nao|limite_taxa|respeitar_retry_after'
    '401|expired_access_token/|sim|autenticacao|renovar_token_uma_vez'
    '408||nao|desconhecido|recuo_exponencial'
    '409|path/not_found/..|nao|nao_encontrado|nenhuma'
    '409|too_many_write_operations/..|sim|limite_taxa|respeitar_retry_after'
    '409|reset/..|nao|nao_concluida|reiniciar'
    '409|incorrect_offset/..|nao|nao_concluida|retomar'
    '500||sim|erro_remoto|recuo_exponencial'
    '500||nao|erro_remoto|indeterminado'
  )
  local linha http resumo idem classe politica saida
  for linha in "${tabela[@]}"; do
    IFS='|' read -r http resumo idem classe politica <<<"$linha"
    saida=$(dbx_errors_classificar "$http" "$resumo")
    assert_igual "$classe" "$saida" "classe pela saida: $linha"
    dbx_errors_classificar "$http" "$resumo" >/dev/null
    assert_igual "$classe" "$DBX_ERRORS_CLASSE" "classe pelo canal: $linha"
    saida=$(dbx_errors_politica_retentativa "$http" "$resumo" "$idem")
    assert_igual "$politica" "$saida" "politica pela saida: $linha"
    dbx_errors_politica_retentativa "$http" "$resumo" "$idem" >/dev/null
    assert_igual "$politica" "$DBX_ERRORS_POLITICA" "politica pelo canal: $linha"
  done
  dbx_errors_classificar abc '' >/dev/null
  assert_igual "$DBX_ERRORS_STATUS_USO" $? 'codigo HTTP invalido: status de uso'
  dbx_errors_politica_retentativa 500 '' talvez >/dev/null
  assert_igual "$DBX_ERRORS_STATUS_USO" $? 'idempotencia invalida: status de uso'
  local par
  for par in sucesso:0 rede:9 erro_remoto:10 uso_invalido:2 configuracao:3 autenticacao:5 \
    permissao:6 limite_taxa:8 nao_encontrado:4 conflito:7 desconhecido:1 nao_concluida:14; do
    assert_igual "${par#*:}" "$(dbx_errors_codigo_saida "${par%%:*}")" "codigo de saida: $par"
  done
}

harness_executar "$@"
