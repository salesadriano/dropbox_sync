#!/usr/bin/env bash
# Testes ponta a ponta da checagem automatica de disponibilidade nos comandos de
# nivel `credencial` (RF-151, RF-152, RF-153; invariantes de RF-154;
# TC-DSP-28..60). O comando exercitado e `space` (uma chamada RPC), por ser o
# mais curto que passa pelo despacho de credencial e pela primeira obtencao de
# token. Duplo de curl e terminal: tests/support/disponibilidade.sh.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
# shellcheck source=tests/support/disponibilidade.sh
. "$DBX_HARNESS_RAIZ/tests/support/disponibilidade.sh"

readonly USO='{"used":1024,"allocation":{".tag":"individual","allocated":2048}}'

_cenario_rpc() {
  local base
  base=$(_cenario)
  printf '%s' "$USO" >"$base/rpc_corpo"
  printf '%s' "$base"
}

_chamadas() {
  local x=''
  [[ -r $1/chamadas ]] && IFS= read -r -d '' x <"$1/chamadas"
  printf '%s' "$x"
}

# TC-DSP-28, 29, 30: caminho feliz sem uma chamada a mais
teste_dsp28_caminho_feliz_so_a_renovacao_e_a_chamada_do_comando() {
  local base chamadas
  base=$(_cenario_rpc)
  _rodar "$base" space
  assert_igual 0 "$DBX_ESTADO" "space ok; erro: $DBX_ERRO"
  chamadas=$(_chamadas "$base")
  assert_igual 2 "$(grep -c . <<<"$chamadas")" "so token e chamada do comando: $chamadas"
  assert_igual 0 "$(_contar "$chamadas" 'gstatic')" 'nenhuma sonda'
  assert_igual 0 "$(_contar "$chamadas" 'content.dropboxapi')" 'nenhum alcance'
  assert_igual 1 "$(_contar "$chamadas" 'oauth2/token')" 'uma renovacao'
  assert_igual '' "$DBX_ERRO" 'stderr vazio'
}

# TC-DSP-31: sem terminal, credencial ausente = comportamento de hoje
teste_dsp31_sem_terminal_credencial_ausente_sai_3_sem_pergunta_sem_sonda_sem_ler_stdin() {
  local base resto
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  printf '%s' "$SENTINELA_STDIN" >"$base/entrada"
  resto=$(
    {
      env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
        TMPDIR="$base/tmp" "$BASH_ABSOLUTO" "$DBX_EXEC" space >"$base/out" 2>"$base/err"
      printf 'ESTADO=%s\n' "$?" >"$base/estado_saida"
      cat
    } <"$base/entrada"
  )
  assert_igual "$SENTINELA_STDIN" "$resto" 'nenhum byte de stdin consumido'
  assert_contem 'ESTADO=3' "$(<"$base/estado_saida")" 'codigo 3'
  assert_contem 'credencial indisponivel' "$(<"$base/err")" 'mensagem de hoje'
  assert_nao_contem '[s/N]' "$(<"$base/err")" 'sem pergunta'
  if [[ -e $base/chamadas ]]; then _harness_falhar 'nenhuma requisicao esperada' "$(<"$base/chamadas")"; fi
}

# TC-DSP-35, 36, 47..: recusa na credencial local
teste_dsp35_terminal_credencial_ausente_pergunta_e_recusa_mantem_3() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" N space
  assert_contem 'Credencial ausente. Configurar agora? [s/N]' "$DBX_SAIDA" 'pergunta'
  assert_contem 'nenhuma alteracao feita' "$DBX_SAIDA" 'recusa'
  assert_contem 'credencial indisponivel' "$DBX_SAIDA" 'remedio de hoje preservado'
  assert_igual 3 "$DBX_ESTADO" 'codigo original'
}

# Achado #8 (conformidade): o portao fecha so quando um ARGUMENTO e exatamente
# `-` ou uma opcao de senha; caminho que apenas contem "stdin" nao o fecha.
teste_dsp35b_caminho_com_stdin_no_nome_nao_fecha_o_portao_da_oferta() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" N revisoes /bkp/stdin.log
  assert_contem 'Credencial ausente. Configurar agora? [s/N]' "$DBX_SAIDA" 'oferta mantida'
  assert_igual 3 "$DBX_ESTADO" 'codigo original'
}

teste_dsp36_terminal_campo_faltando_pergunta_invalida() {
  local base
  base=$(_cenario_rpc)
  printf '{"versao":1,"app_key":"k","app_secret":"s"}' >"$base/config/dbx/credencial.json"
  _rodar_tty "$base" n space
  assert_contem 'Credencial invalida. Configurar agora? [s/N]' "$DBX_SAIDA" 'pergunta invalida'
  assert_igual 3 "$DBX_ESTADO" 'codigo original'
}

# TC-DSP-47: aceite -> config ok -> o comando continua
teste_dsp47_aceite_configura_e_o_comando_continua_no_mesmo_processo() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  printf '{"access_token":"%s","refresh_token":"%s","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$ESCOPOS" >"$base/token"
  DBX_T_EXTRAS=('App key:|kk' 'nao sera exibido|ss' 'Codigo de autorizacao:|cc')
  _rodar_tty "$base" s space
  DBX_T_EXTRAS=()
  assert_igual 0 "$DBX_ESTADO" "comando continuou; saida: $DBX_SAIDA"
  assert_contem 'usado_bytes' "$DBX_SAIDA" 'saida do space apos o config'
  assert_igual 1 "$(_contar "$DBX_SAIDA" 'Configurar agora?')" 'uma oferta so'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'credencial gravada'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" '/2/users/get_space_usage')" 'o comando roda uma unica vez'
}

# TC-DSP-48: config cancelado -> codigo da falha original
teste_dsp48_config_cancelado_mantem_o_codigo_original_e_nada_do_comando_roda() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_EOF=sim _rodar_tty "$base" s space
  assert_igual 3 "$DBX_ESTADO" 'DIV-319: codigo da falha original'
  assert_igual 0 "$(_contar "$(_chamadas "$base")" '/2/users')" 'comando original nao executado'
}

# TC-DSP-32: invalid_grant na primeira obtencao sai pela classe do TOKEN
# (autenticacao, 5), tambem nos comandos de consulta (DIV-327, RF-153(b)).
teste_dsp32_invalid_grant_sem_terminal_sem_oferta_sem_sonda_e_codigo_de_hoje() {
  local base
  base=$(_cenario_rpc)
  printf 400 >"$base/token_codigo"
  printf '{"error":"invalid_grant"}' >"$base/token_corpo"
  _rodar "$base" space
  assert_nao_contem '[s/N]' "$DBX_ERRO" 'sem pergunta'
  assert_igual 0 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'sem sonda'
  assert_igual 5 "$DBX_ESTADO" 'classe do token (DIV-327)'
  assert_contem 'invalid_grant' "$DBX_ERRO" 'motivo da renovacao'
  assert_nao_contem 'codigo 400' "$DBX_ERRO" 'nao a classe da requisicao'
}

teste_dsp32_invalid_grant_no_terminal_pergunta_invalida_e_recusa_mantem_o_codigo() {
  local base
  base=$(_cenario_rpc)
  printf 400 >"$base/token_codigo"
  printf '{"error":"invalid_grant"}' >"$base/token_corpo"
  _rodar_tty "$base" n space
  assert_contem 'Credencial invalida. Configurar agora? [s/N]' "$DBX_SAIDA" 'pergunta'
  assert_contem 'nenhuma alteracao feita' "$DBX_SAIDA" 'recusa'
  assert_igual 5 "$DBX_ESTADO" 'codigo original, o da autenticacao (DIV-319, DIV-327)'
}

# TC-DSP-32 (DIV-327, RF-150(a)): invalid_grant na obtencao do token sai 5 em
# todo comando que chama `dbx_auth_requisitar` direto, nao so em `space`.
teste_dsp32_invalid_grant_sai_5_nos_demais_comandos_de_consulta() {
  local base comando
  for comando in 'revisoes /a.txt' 'restaurar /a.txt' 'lixeira --excluir /a.txt --confirmar-caminho /a.txt'; do
    base=$(_cenario_rpc)
    printf 400 >"$base/token_codigo"
    printf '{"error":"invalid_grant"}' >"$base/token_corpo"
    # shellcheck disable=SC2086  # a tabela e de palavras
    _rodar "$base" $comando
    assert_igual 5 "$DBX_ESTADO" "classe do token em: $comando; erro: $DBX_ERRO"
    assert_contem 'invalid_grant' "$DBX_ERRO" "motivo da renovacao em: $comando"
    assert_nao_contem 'codigo 400' "$DBX_ERRO" "nao a classe da requisicao em: $comando"
  done
}

teste_dsp49_invalid_grant_aceite_configura_renova_e_o_comando_continua() {
  local base
  base=$(_cenario_rpc)
  printf '%s' "$SENTINELA_REFRESH" >"$base/recusar_refresh"
  printf '{"access_token":"%s","refresh_token":"RT_NOVO_sintetico","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$ESCOPOS" >"$base/token"
  DBX_T_EXTRAS=('App key:|kk' 'nao sera exibido|ss' 'Codigo de autorizacao:|cc')
  _rodar_tty "$base" s space
  DBX_T_EXTRAS=()
  assert_igual 0 "$DBX_ESTADO" "comando continuou; saida: $DBX_SAIDA"
  assert_contem 'usado_bytes' "$DBX_SAIDA" 'saida do space'
  assert_igual 1 "$(_contar "$DBX_SAIDA" 'Configurar agora?')" 'uma oferta so (RF-152(h))'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" '/2/users/get_space_usage')" 'comando uma unica vez'
}

# TC-DSP-33: rede na renovacao -> a sonda nomeia a causa; codigo 9
teste_dsp33_falha_de_rede_na_renovacao_sem_internet_nomeia_e_mantem_9() {
  local base
  base=$(_cenario_rpc)
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" space
  assert_igual 9 "$DBX_ESTADO" 'rede'
  assert_contem 'sem acesso a internet' "$DBX_ERRO" 'causa nomeada'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'uma sonda so'
}

teste_dsp33_falha_de_rede_na_renovacao_com_internet_diz_dropbox_inacessivel() {
  local base
  base=$(_cenario_rpc)
  printf falha >"$base/token_codigo"
  _rodar "$base" space
  assert_igual 9 "$DBX_ESTADO" 'rede'
  assert_contem 'Dropbox inacessivel' "$DBX_ERRO" 'causa nomeada'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'uma sonda so'
}

# TC-DSP-34: 5xx -> servico indisponivel, codigo 10, sem sonda
teste_dsp34_5xx_na_renovacao_diz_servico_indisponivel_sem_sonda() {
  local base
  base=$(_cenario_rpc)
  printf 503 >"$base/token_codigo"
  printf '' >"$base/token_corpo"
  _rodar "$base" space
  assert_igual 10 "$DBX_ESTADO" 'erro_remoto'
  assert_contem 'servico Dropbox indisponivel' "$DBX_ERRO" 'causa nomeada'
  assert_igual 0 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'sem sonda'
}

# TC-DSP-33 (DIV-329a): comando que usa dbx_auth_preparar tambem nomeia a causa
teste_dsp33_upload_falha_de_rede_na_renovacao_nomeia_a_causa_no_motivo() {
  local base
  base=$(_cenario_rpc)
  printf conteudo >"$base/arq.txt"
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" upload "$base/arq.txt" /x.txt
  assert_igual 9 "$DBX_ESTADO" 'rede'
  assert_contem 'sem acesso a internet' "$DBX_ERRO" 'causa nomeada no motivo da autenticacao'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'uma sonda so'
}

# TC-DSP-33 (DIV-329b, RF-151(e)): rede no meio da execucao enriquece a mensagem
teste_dsp33_falha_de_rede_na_chamada_do_comando_nomeia_sem_oferta_e_mantem_9() {
  local base
  base=$(_cenario_rpc)
  printf falha >"$base/rpc"
  printf falha >"$base/sonda"
  _rodar_tty "$base" n space
  assert_igual 9 "$DBX_ESTADO" 'rede, codigo inalterado'
  assert_contem 'sem acesso a internet' "$DBX_SAIDA" 'causa nomeada'
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'sem oferta de config depois de efeito'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'uma sonda so'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" '/2/users/get_space_usage')" 'chamada nao repetida'
}

teste_dsp33_falha_de_rede_na_chamada_do_comando_com_internet_diz_dropbox_inacessivel() {
  local base
  base=$(_cenario_rpc)
  printf falha >"$base/rpc"
  _rodar "$base" space
  assert_igual 9 "$DBX_ESTADO" 'rede'
  assert_contem 'Dropbox inacessivel' "$DBX_ERRO" 'causa nomeada'
}

teste_dsp34_5xx_na_chamada_do_comando_diz_servico_indisponivel_sem_sonda() {
  local base
  base=$(_cenario_rpc)
  printf 503 >"$base/rpc"
  _rodar "$base" space
  assert_igual 10 "$DBX_ESTADO" 'erro_remoto, codigo inalterado'
  assert_contem 'servico Dropbox indisponivel' "$DBX_ERRO" 'causa nomeada'
  assert_igual 0 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'sem sonda'
}

# TC-DSP-44: comando que consome stdin nao oferece
teste_dsp44_upload_de_fluxo_nao_oferece_o_config() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - upload - /x.txt
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'upload - nao oferece (DIV-315)'
  assert_igual 3 "$DBX_ESTADO" 'codigo de hoje'
}

# TC-DSP-55, 56: nenhum segredo na saida nem na sonda
teste_dsp55_nenhum_sentinela_na_saida_nem_na_sonda_dos_caminhos_de_falha() {
  local base s
  base=$(_cenario_rpc)
  printf falha >"$base/token_codigo"
  _rodar "$base" --debug space
  for s in "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$SENTINELA_CHAVE" "$SENTINELA_TOKEN"; do
    assert_nao_contem "$s" "$DBX_SAIDA$DBX_ERRO" 'sentinela fora da saida'
    assert_nao_contem "$s" "$(grep 'gstatic' "$base/pedidos")" 'sentinela fora da sonda'
  done
}

_dialogo_config() { DBX_T_EXTRAS=('App key:|kk' 'nao sera exibido|ss' 'Codigo de autorizacao:|cc'); }

_token_de_config() {
  printf '{"access_token":"%s","refresh_token":"%s","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$ESCOPOS" >"$1/token"
}

# TC-DSP-37, 38, 45: portao fechado = nenhuma pergunta
teste_dsp37_stderr_em_arquivo_nao_pergunta() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_REDIR_ERR=sim _rodar_tty "$base" - space
  assert_nao_contem '[s/N]' "$DBX_SAIDA$(<"$base/stderr_arquivo")" 'sem pergunta'
  assert_contem 'credencial indisponivel' "$(<"$base/stderr_arquivo")" 'remedio de hoje'
  assert_igual 3 "$DBX_ESTADO" 'codigo de hoje'
}

teste_dsp38_term_dumb_nao_pergunta() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_TERM=dumb _rodar_tty "$base" - space
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'sem pergunta'
  assert_igual 3 "$DBX_ESTADO" 'codigo de hoje'
}

teste_dsp45_dbx_teste_config_nao_nao_pergunta() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_AMBIENTE=DBX_TESTE_CONFIG=nao _rodar_tty "$base" - space
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'sem pergunta'
  assert_igual 3 "$DBX_ESTADO" 'codigo de hoje'
}

# TC-DSP-39, 50: Enter, n, x e fim de entrada recusam; codigo e remedio originais
teste_dsp39_enter_n_x_e_fim_de_entrada_recusam_com_o_codigo_original() {
  local base resposta
  for resposta in '' n x -; do
    base=$(_cenario_rpc)
    rm -f "$base/config/dbx/credencial.json"
    _rodar_tty "$base" "$resposta" space
    assert_contem '[s/N]' "$DBX_SAIDA" "pergunta (resposta '$resposta')"
    assert_contem 'nenhuma alteracao feita' "$DBX_SAIDA" "recusa (resposta '$resposta')"
    assert_contem 'credencial indisponivel' "$DBX_SAIDA" 'remedio'
    assert_igual 3 "$DBX_ESTADO" "codigo original (resposta '$resposta')"
    assert_arquivo_ausente "$base/config/dbx/credencial.json" 'nada gravado'
  done
}

# TC-DSP-40: s, S e sim com credencial ausente rodam config sem --substituir
teste_dsp40_s_maiusculo_e_sim_aceitam_a_oferta() {
  local base resposta
  for resposta in S sim; do
    base=$(_cenario_rpc)
    rm -f "$base/config/dbx/credencial.json"
    _token_de_config "$base"
    _dialogo_config
    _rodar_tty "$base" "$resposta" space
    DBX_T_EXTRAS=()
    assert_igual 0 "$DBX_ESTADO" "resposta '$resposta'; saida: $DBX_SAIDA"
    assert_arquivo_existe "$base/config/dbx/credencial.json" 'credencial gravada'
  done
}

# TC-DSP-41: arquivo com campo faltando, aceito, roda config --substituir
# (sem --substituir o config recusaria o arquivo existente, DIV-321)
teste_dsp41_arquivo_incompleto_aceito_e_substituido() {
  local base
  base=$(_cenario_rpc)
  printf '{"versao":1,"app_key":"k","app_secret":"s"}' >"$base/config/dbx/credencial.json"
  _token_de_config "$base"
  _dialogo_config
  _rodar_tty "$base" s space
  DBX_T_EXTRAS=()
  assert_contem 'Credencial invalida. Configurar agora? [s/N]' "$DBX_SAIDA" 'pergunta invalida'
  assert_igual 0 "$DBX_ESTADO" "continuou; saida: $DBX_SAIDA"
  assert_contem "$SENTINELA_REFRESH" "$(<"$base/config/dbx/credencial.json")" 'arquivo substituido'
}

# TC-DSP-42: --perfil a propaga ao config; so perfis/a.json e gravado
teste_dsp42_perfil_aceito_grava_so_o_perfil_pedido() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _token_de_config "$base"
  _dialogo_config
  _rodar_tty "$base" s --perfil a space
  DBX_T_EXTRAS=()
  assert_igual 0 "$DBX_ESTADO" "continuou; saida: $DBX_SAIDA"
  assert_arquivo_existe "$base/config/dbx/perfis/a.json" 'perfil a gravado'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'credencial padrao intocada'
  assert_igual 1 "$(find "$base/config/dbx/perfis" -type f | wc -l)" 'nenhum outro perfil'
}

# TC-DSP-43: comando que consome a entrada nao oferece (upload -)
teste_dsp43_upload_de_fluxo_com_terminal_nao_pergunta_nem_le_a_entrada() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - upload - /x.txt
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'sem pergunta'
  assert_igual 3 "$DBX_ESTADO" 'codigo de hoje'
}

# TC-DSP-46: --json em terminal com s; stdout so a saida estruturada do comando
teste_dsp46_json_com_oferta_aceita_stdout_so_o_json() {
  local base saida
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _token_de_config "$base"
  _dialogo_config
  DBX_T_REDIR_OUT=sim _rodar_tty "$base" s --json space
  DBX_T_EXTRAS=()
  saida=$(<"$base/stdout_arquivo")
  assert_contem 'usado_bytes=1024' "$saida" 'saida estruturada do comando (DIV-322)'
  assert_nao_contem '[s/N]' "$saida" 'pergunta fora de stdout'
  assert_nao_contem 'App key' "$saida" 'dialogo do config fora de stdout'
  assert_contem '[s/N]' "$DBX_SAIDA" 'pergunta em stderr'
  assert_contem 'App key' "$DBX_SAIDA" 'dialogo do config em stderr'
  assert_igual 'contrato=1' "${saida%%$'\n'*}" 'stdout comeca pelo contrato estruturado'
}

# TC-DSP-51: Ctrl-C dentro do config = codigo original, nada do comando roda
teste_dsp51_sigint_dentro_do_config_mantem_o_codigo_e_nada_do_comando_roda() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_CTRLC=sim _rodar_tty "$base" s space
  assert_igual 0 "$(_contar "$(_chamadas "$base")" '/2/users')" 'comando original nao executado'
  assert_arquivo_ausente "$base/config/dbx/credencial.json" 'nada gravado'
  # Sob o pty o SIGINT alcanca todo o grupo em primeiro plano: o codigo de saida
  # nao e observavel aqui (o fim de entrada, em dsp48, prova o codigo original).
}

# TC-DSP-52: falha de rede dentro do config preserva a mensagem do config e o codigo original
teste_dsp52_falha_de_rede_no_config_mantem_codigo_e_mensagem_do_config() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  : >"$base/troca_falha"
  _dialogo_config
  _rodar_tty "$base" s space
  DBX_T_EXTRAS=()
  assert_igual 3 "$DBX_ESTADO" "codigo original; saida: $DBX_SAIDA"
  assert_contem 'Codigo de autorizacao' "$DBX_SAIDA" 'dialogo do config'
  assert_contem 'erro' "$DBX_SAIDA" 'mensagem do config'
  assert_igual 0 "$(_contar "$(_chamadas "$base")" '/2/users')" 'comando original nao executado'
}

# TC-DSP-53: config --substituir que falha deixa a credencial anterior integra
teste_dsp53_config_substituir_que_falha_preserva_a_credencial_anterior() {
  local base antes
  base=$(_cenario_rpc)
  printf '%s' "$SENTINELA_REFRESH" >"$base/recusar_refresh"
  : >"$base/troca_falha"
  antes=$(_retrato "$base/config/dbx")
  _dialogo_config
  _rodar_tty "$base" s space
  DBX_T_EXTRAS=()
  assert_igual 5 "$DBX_ESTADO" "codigo original; saida: $DBX_SAIDA"
  assert_igual "$antes" "$(_retrato "$base/config/dbx")" 'credencial anterior byte a byte, sem arquivo parcial'
}

# TC-DSP-54: a oferta roda antes de qualquer trava; o comando adquire a sua depois
teste_dsp54_oferta_aceita_nao_adquire_trava_antes_e_o_comando_adquire_depois() {
  local base troca resto
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _token_de_config "$base"
  mkdir -p "$base/loc"
  : >"$base/loc/a.txt"
  _dialogo_config
  _rodar_tty "$base" s sync --enviar --origem "$base/loc" --destino /rem
  DBX_T_EXTRAS=()
  troca=$(grep 'oauth2/token' "$base/travas" | head -1)
  assert_contem ' 0' "$troca" "config sem trava: $troca"
  resto=$(grep -v 'oauth2/token' "$base/travas" | grep -v ' 0$' || true)
  [[ -n $resto ]] || _harness_falhar 'o sync adquire a sua trava depois do config' "$(<"$base/travas")"
}

# TC-DSP-54 (invalid_grant, DIV-330 C): o config roda sob a trava do par do proprio
# comando (RF-69(b)); a unica trava viva e essa, e o config nao adquire outra
teste_dsp54_invalid_grant_aceito_o_config_roda_sob_a_unica_trava_do_par() {
  local base linha n troca=0
  base=$(_cenario_rpc)
  printf '%s' "$SENTINELA_REFRESH" >"$base/recusar_refresh"
  printf '{"access_token":"%s","refresh_token":"RT_NOVO","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$ESCOPOS" >"$base/token"
  mkdir -p "$base/loc"
  : >"$base/loc/a.txt"
  _dialogo_config
  _rodar_tty "$base" s sync --enviar --origem "$base/loc" --destino /rem
  DBX_T_EXTRAS=()
  assert_contem 'Credencial invalida. Configurar agora? [s/N]' "$DBX_SAIDA" 'oferta por invalid_grant'
  while IFS= read -r linha; do
    n=${linha##* }
    [[ $n -le 1 ]] || _harness_falhar 'no maximo uma trava viva (a do par)' "$linha"
    if [[ $linha == *oauth2/token* ]]; then
      troca=$((troca + 1))
      assert_igual 1 "$n" "token/troca do config sob a trava do par: $linha"
    fi
  done <"$base/travas"
  [[ $troca -ge 2 ]] || _harness_falhar 'renovacao recusada e troca do config vistas' "$(<"$base/travas")"
}

# TC-DSP-18: DNS, conexao, TLS e tempo esgotado contam como "nao responde"
teste_dsp18_falhas_de_dns_conexao_tls_e_tempo_contam_como_nao_responde() {
  local base saida
  for saida in 6 7 35 28; do
    base=$(_cenario_rpc)
    printf falha >"$base/token_codigo"
    printf 'falha:%s' "$saida" >"$base/sonda"
    _rodar "$base" space
    assert_igual 9 "$DBX_ESTADO" "rede (curl $saida)"
    assert_contem 'sem acesso a internet' "$DBX_ERRO" "nao responde (curl $saida)"
  done
}

# TC-DSP-20: a sonda usa o transporte do cURL (proxy do ambiente), sem variavel nova
teste_dsp20_sonda_usa_o_mesmo_transporte_e_nao_le_variavel_de_proxy_nova() {
  local base sonda token fonte
  base=$(_cenario_rpc)
  printf falha >"$base/token_codigo"
  DBX_T_AMBIENTE=HTTPS_PROXY=http://proxy.invalid:3128 _rodar "$base" space
  sonda=$(grep gstatic "$base/proxies")
  token=$(grep oauth2/token "$base/proxies" | head -1)
  assert_contem 'proxy.invalid:3128' "$sonda" 'a sonda herda o proxy do cURL'
  assert_contem 'proxy.invalid:3128' "$token" 'o mesmo ambiente das demais chamadas'
  assert_nao_contem '--proxy' "$(grep gstatic "$base/pedidos")" 'sem opcao de proxy propria'
  assert_nao_contem -- ' -x ' "$(grep gstatic "$base/pedidos")" 'sem opcao -x'
  fonte=$(<"$DBX_HARNESS_RAIZ/lib/disponibilidade.sh")
  [[ $fonte =~ (\$\{?[A-Za-z_]*[Pp][Rr][Oo][Xx][Yy])|([A-Z_]*PROXY[A-Z_]*=) ]] && _harness_falhar 'nenhuma variavel de proxy lida pela camada' "${BASH_REMATCH[0]}"
  return 0
}

# TC-DSP-56: oferta aceita + classificacao: nenhum sentinela em stdout, stderr nem log
teste_dsp56_oferta_e_classificacao_nao_vazam_sentinela_na_saida_nem_no_log() {
  local base s
  base=$(_cenario_rpc)
  printf '%s' "$SENTINELA_REFRESH" >"$base/recusar_refresh"
  printf '{"access_token":"%s","refresh_token":"RT_NOVO","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$ESCOPOS" >"$base/token"
  _dialogo_config
  _rodar_tty "$base" s --debug space
  DBX_T_EXTRAS=()
  for s in "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$SENTINELA_CHAVE" "$SENTINELA_TOKEN"; do
    assert_nao_contem "$s" "$DBX_SAIDA" 'sentinela fora da saida'
    assert_nao_contem "$s" "$(grep -rs -- "$s" "$base/estado" || true)" 'sentinela fora do log'
  done
}

# TC-DSP-57: sonda e servico sem sentinela nem Authorization
teste_dsp57_sonda_e_servico_nao_levam_segredo_nem_cabecalho_de_autorizacao() {
  local base linha
  base=$(_cenario)
  _rodar "$base" testar
  while IFS= read -r linha; do
    case $linha in
      *gstatic* | *api.dropboxapi.com/2/check* | *api.dropboxapi.com* | *content.dropboxapi.com*) ;;
      *) continue ;;
    esac
    [[ $linha == *oauth2/token* ]] && continue
    assert_nao_contem "$SENTINELA_TOKEN" "$linha" 'sem token'
    assert_nao_contem 'Authorization' "$linha" 'sem cabecalho de autorizacao'
    assert_nao_contem "$SENTINELA_REFRESH" "$linha" 'sem refresh token'
  done <"$base/pedidos"
}

# TC-DSP-58: sem terminal, nenhum byte de stdin lido pela camada de disponibilidade
teste_dsp58_sem_terminal_nenhum_byte_de_stdin_nos_caminhos_de_falha() {
  local base resto caso
  for caso in invalid_grant rede_sonda; do
    base=$(_cenario_rpc)
    case $caso in
      invalid_grant) printf 400 >"$base/token_codigo" && printf '{"error":"invalid_grant"}' >"$base/token_corpo" ;;
      rede_sonda) printf falha >"$base/token_codigo" && printf falha >"$base/sonda" ;;
    esac
    printf '%s' "$SENTINELA_STDIN" >"$base/entrada"
    resto=$(
      {
        env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
          TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 "$BASH_ABSOLUTO" "$DBX_EXEC" space >"$base/out" 2>"$base/err"
        cat
      } <"$base/entrada"
    )
    assert_igual "$SENTINELA_STDIN" "$resto" "stdin intacto ($caso)"
    assert_nao_contem '[s/N]' "$(<"$base/err")" 'sem pergunta'
  done
}

# TC-DSP-59: o diagnostico nunca pergunta (`info` nao esta na lista do TC-DSP-34
# e recebe a oferta); a igualdade com o antes e dos testes proprios, verdes.
teste_dsp59_diagnostico_nunca_oferece_o_config() {
  local base
  base=$(_cenario_rpc)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - diagnostico
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'diagnostico sem pergunta'
}

# TC-DSP-60: nenhum processo da sonda sobrevive e lib/tmp fica limpo
teste_dsp60_fim_normal_e_falha_nao_deixam_processo_nem_tmp() {
  local base
  base=$(_cenario_rpc)
  _rodar "$base" testar
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" space
  assert_igual 0 "$(pgrep -f "$base/bin/curl" | wc -l)" 'nenhum processo da sonda'
  assert_igual 0 "$(find "$base/tmp" -mindepth 1 | wc -l)" 'tmp limpo'
}

teste_dsp60_sinal_durante_a_sonda_nao_deixa_processo_nem_tmp() {
  local base pid setsid_abs
  setsid_abs=$(command -v setsid) || pular 'setsid ausente: sem grupo de processos para o sinal'
  base=$(_cenario_rpc)
  printf falha >"$base/token_codigo"
  : >"$base/sonda_lenta"
  # Grupo proprio: o sinal alcanca o comando e a sonda, como o Ctrl-C do terminal.
  "$setsid_abs" env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 "$BASH_ABSOLUTO" "$DBX_EXEC" space >"$base/out" 2>"$base/err" </dev/null &
  pid=$!
  sleep 1
  kill -TERM -- "-$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 0.3
  assert_igual 0 "$(pgrep -f 'sleep 3137' | wc -l)" 'nenhum processo da sonda sobrevive ao sinal'
  assert_igual 0 "$(find "$base/tmp" -mindepth 1 | wc -l)" 'tmp limpo'
  pkill -f 'sleep 3137' 2>/dev/null
  return 0
}

# R2 (rodada 3): sync com paralelo > 1 e URL de sonda invalida; a falha de rede cai na
# etapa de lote (auxiliares). Um aviso so no stderr do comando, sem o valor.
teste_dsp34r_sync_paralelo_com_url_invalida_avisa_uma_vez_na_etapa_de_lote() {
  local base avisos
  base=$(_cenario_rpc)
  mkdir -p "$base/loc"
  printf a >"$base/loc/a.txt"
  printf b >"$base/loc/b.txt"
  printf c >"$base/loc/c.txt"
  printf '{"entries":[],"cursor":"c","has_more":false}' >"$base/rpc_corpo"
  printf falha >"$base/content"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=ftp://SENTINELA_URL_z7.invalido/x' _rodar "$base" sync --enviar --origem "$base/loc" --destino /rem --paralelo 3
  avisos=$(_contar "$DBX_ERRO" 'DBX_TESTE_INTERNET_URL deve comecar')
  assert_igual 1 "$avisos" "exatamente um aviso de URL invalida; estado=$DBX_ESTADO; $DBX_ERRO"
  assert_nao_contem 'SENTINELA_URL_z7' "$DBX_ERRO$DBX_SAIDA" 'o aviso nao traz o valor'
}

# R2 (rodada 3): mesma falha com sonda valida; no maximo uma sonda na execucao
teste_dsp34s_sync_paralelo_com_falha_de_rede_sonda_uma_vez() {
  local base
  base=$(_cenario_rpc)
  mkdir -p "$base/loc"
  printf a >"$base/loc/a.txt"
  printf b >"$base/loc/b.txt"
  printf c >"$base/loc/c.txt"
  printf '{"entries":[],"cursor":"c","has_more":false}' >"$base/rpc_corpo"
  printf falha >"$base/content"
  printf falha >"$base/sonda"
  _rodar "$base" sync --enviar --origem "$base/loc" --destino /rem --paralelo 3
  [[ $(_contar "$(_chamadas "$base")" 'gstatic') -le 1 ]] || _harness_falhar "mais de uma sonda: $(_chamadas "$base")"
}

# DIV-329: a causa nomeada tambem em sync e download
teste_dsp33_sync_falha_de_rede_na_renovacao_nomeia_a_causa() {
  local base
  base=$(_cenario_rpc)
  mkdir -p "$base/loc"
  : >"$base/loc/a.txt"
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" sync --enviar --origem "$base/loc" --destino /rem
  assert_igual 9 "$DBX_ESTADO" 'rede'
  assert_contem 'sem acesso a internet' "$DBX_ERRO" 'causa nomeada no sync'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'uma sonda so'
}

teste_dsp33_download_falha_de_rede_na_renovacao_nomeia_a_causa() {
  local base
  base=$(_cenario_rpc)
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" download /x.txt "$base/destino.txt"
  assert_igual 9 "$DBX_ESTADO" 'rede'
  assert_contem 'sem acesso a internet' "$DBX_ERRO" 'causa nomeada no download'
  assert_igual 1 "$(_contar "$(_chamadas "$base")" 'gstatic')" 'uma sonda so'
}

# TC-DSP-62, 63, 64: ajuda e README (RF-155)
teste_dsp62_ajuda_de_config_e_diagnostico_e_geral_informam_a_oferta() {
  local base
  base=$(_cenario_rpc)
  _rodar "$base" help config
  assert_contem 'DBX_TESTE_CONFIG' "$DBX_SAIDA" 'help config cita a variavel'
  assert_contem '[s/N]' "$DBX_SAIDA" 'help config descreve a pergunta'
  _rodar "$base" help diagnostico
  assert_contem 'nao inicia o config' "$DBX_SAIDA" 'help diagnostico'
  _rodar "$base" help
  assert_contem 'DBX_TESTE_CONFIG' "$DBX_SAIDA" 'ajuda geral informa a oferta dos comandos de credencial'
}

teste_dsp63_readme_descreve_o_teste_a_sonda_e_o_comportamento_sem_terminal() {
  local readme
  readme=$(<"$DBX_HARNESS_RAIZ/README.md")
  assert_contem 'dbx testar' "$readme" 'teste'
  assert_contem 'DBX_TESTE_INTERNET_URL' "$readme" 'sonda e como desligar'
  assert_contem 'DBX_TESTE_CONFIG' "$readme" 'oferta do config'
  assert_contem 'sem terminal' "$readme" 'comportamento sem terminal'
  assert_contem 'gstatic' "$readme" 'o que e enviado e a quem (terceiro)'
}

harness_executar "$@"
