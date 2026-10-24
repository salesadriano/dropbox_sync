#!/usr/bin/env bash
# Testes ponta a ponta do `dbx testar` (RF-148, TC-DSP-01..12) e dos invariantes
# de sonda, classificacao e seguranca que valem para ele (RF-149, RF-150,
# RF-154; TC-DSP-13..25, 55, 57, 58). A checagem automatica nos demais comandos
# (RF-151) nao esta aqui.
#
# O duplo de `curl` honra o contrato de lib/http (opcoes por `-K -`) e GRAVA as
# opcoes lidas, para a suite provar o que a sonda envia. Terminal interativo:
# script(1), como o teste do compartilhar.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

# shellcheck source=tests/support/disponibilidade.sh
. "$DBX_HARNESS_RAIZ/tests/support/disponibilidade.sh"

# TC-DSP-01, TC-DSP-02
teste_dsp01_tudo_disponivel_quatro_linhas_ok_e_alias_check() {
  local base
  base=$(_cenario)
  _rodar "$base" testar
  assert_igual 0 "$DBX_ESTADO" "tudo ok sai com 0; erro: $DBX_ERRO"
  assert_contem 'internet=ok' "$DBX_SAIDA" 'internet'
  assert_contem 'credencial=ok' "$DBX_SAIDA" 'credencial'
  assert_contem 'servico=ok' "$DBX_SAIDA" 'servico (api)'
  assert_contem 'servico_conteudo=ok' "$DBX_SAIDA" 'servico_conteudo (DIV-320)'
  assert_contem $'ok=4\navisos=0\nfalhas=0' "$DBX_SAIDA" 'contagens'
  local primeira=$DBX_SAIDA
  _rodar "$base" check
  assert_igual 0 "$DBX_ESTADO" 'alias check'
  assert_igual "$primeira" "$DBX_SAIDA" 'check e identico a testar'
}

# TC-DSP-03, TC-DSP-22
teste_dsp03_sem_credencial_e_sem_rede_primeira_falha_e_a_internet() {
  local base
  base=$(_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf falha >"$base/sonda"
  printf falha >"$base/api"
  printf falha >"$base/content"
  _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida rede)" "$DBX_ESTADO" 'primeira falha: internet, rede = 9'
  assert_contem 'internet=falha: sem acesso a internet' "$DBX_SAIDA" 'sem internet'
  assert_contem 'servico=falha: api.dropboxapi.com: sem acesso a internet' "$DBX_SAIDA" 'servico roda e falha (DIV-326)'
  assert_contem 'credencial=falha: credencial ausente' "$DBX_SAIDA" 'parte local da credencial roda sempre'
  assert_contem 'dbx config' "$(_linha credencial)" 'remedio da credencial'
}

# DIV-326: sonda sem resposta com o Dropbox respondendo e aviso, nao falha
teste_div326_sonda_inacessivel_com_dropbox_respondendo_e_aviso() {
  local base
  base=$(_cenario)
  printf falha >"$base/sonda"
  _rodar "$base" testar
  assert_igual 0 "$DBX_ESTADO" "aviso nao conta como falha; erro: $DBX_ERRO"
  assert_contem 'internet=aviso: a sonda nao respondeu, mas o Dropbox responde' "$DBX_SAIDA" 'internet aviso'
  assert_contem 'servico=ok' "$DBX_SAIDA" 'servico roda'
  assert_contem 'servico_conteudo=ok' "$DBX_SAIDA" 'servico_conteudo roda'
  assert_contem 'credencial=ok' "$DBX_SAIDA" 'credencial roda'
  assert_contem $'ok=3\navisos=1\nfalhas=0' "$DBX_SAIDA" 'contagens'
}

# TC-DSP-04
teste_dsp04_campo_faltando_e_nomeado_sem_valor_e_sai_3() {
  local base
  base=$(_cenario)
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","raiz_remota":"/"}' "$SENTINELA_CHAVE" "$SENTINELA_SEGREDO" \
    >"$base/config/dbx/credencial.json"
  _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'configuracao = 3'
  assert_contem 'refresh token' "$(_linha credencial)" 'campo nomeado'
  assert_contem 'dbx config --substituir' "$(_linha credencial)" 'remedio'
  assert_nao_contem "$SENTINELA_SEGREDO" "$(_todo_o_rastro "$base")" 'sem valor'
}

# TC-DSP-05
teste_dsp05_invalid_grant_sai_5() {
  local base
  base=$(_cenario)
  printf 400 >"$base/token_codigo"
  printf '{"error":"invalid_grant"}' >"$base/token_corpo"
  _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida autenticacao)" "$DBX_ESTADO" 'autenticacao = 5'
  assert_contem 'credencial=falha' "$DBX_SAIDA" 'credencial recusada'
  assert_contem 'dbx config --substituir' "$(_linha credencial)" 'remedio'
}

# TC-DSP-06
teste_dsp06_perfil_explicito_aponta_o_arquivo_e_o_remedio() {
  local base
  base=$(_cenario)
  mkdir -p "$base/config/dbx/perfis"
  chmod 700 "$base/config/dbx/perfis"
  printf '{"versao":1,"app_key":"k"}' >"$base/config/dbx/perfis/a.json"
  chmod 600 "$base/config/dbx/perfis/a.json"
  _rodar "$base" --perfil a testar
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'perfil incompleto = 3'
  assert_contem 'perfis/a.json' "$(_linha credencial)" 'aponta o arquivo do perfil'
  assert_contem '--perfil a' "$(_linha credencial)" 'remedio leva o perfil'
}

# TC-DSP-07
teste_dsp07_json_traz_os_mesmos_campos_e_so_json() {
  local base
  base=$(_cenario)
  _rodar "$base" --json testar
  assert_igual 0 "$DBX_ESTADO" 'json'
  # A apresentacao estruturada do projeto e a de `contrato=` + `chave=valor`.
  assert_contem 'contrato=' "$DBX_SAIDA" 'contrato declarado'
  assert_contem 'internet=ok' "$DBX_SAIDA" 'campo'
  assert_contem 'falhas=0' "$DBX_SAIDA" 'falhas'
  assert_contem 'avisos=0' "$DBX_SAIDA" 'avisos'
  if [[ -s $base/err ]]; then _harness_falhar 'stderr deveria estar vazio no caminho feliz' "$DBX_ERRO"; fi
}

# TC-DSP-08, TC-DSP-09, TC-DSP-11
teste_dsp08_so_sonda_dois_hosts_sem_token_e_uma_renovacao_e_nada_em_disco() {
  local base antes depois um
  base=$(_cenario)
  antes=$(_retrato "$base/config")
  _rodar "$base" testar
  assert_igual 1 "$(_contar "$(<"$base/chamadas")" 'oauth2/token')" 'uma renovacao'
  assert_igual 0 "$(_contar "$(<"$base/chamadas")" 'check/user')" 'nenhum check/user'
  assert_igual 1 "$(_contar "$(<"$base/chamadas")" 'gstatic.com')" 'uma sonda'
  assert_igual 4 "$(wc -l <"$base/chamadas")" 'sonda, api, content e renovacao: quatro requisicoes'
  depois=$(_retrato "$base/config")
  assert_igual "$antes" "$depois" 'credencial intacta'
  if [[ -e $base/estado ]]; then _harness_falhar 'estado criado' "$(ls -R "$base/estado")"; fi
  um=$DBX_SAIDA
  _rodar "$base" --dry-run testar
  assert_igual "$um" "$DBX_SAIDA" 'dry-run e o mesmo resultado'
}

# TC-DSP-12, TC-DSP-24
teste_dsp12_duas_falhas_o_codigo_e_o_da_primeira_e_5xx_nao_dispara_nova_sonda() {
  local base
  base=$(_cenario)
  printf 503 >"$base/api"
  _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida erro_remoto)" "$DBX_ESTADO" 'servico 503 = erro_remoto 10'
  assert_contem 'servico Dropbox indisponivel' "$(_linha servico)" 'mensagem'
  assert_contem 'credencial=falha: nao executada' "$DBX_SAIDA" 'credencial remota nao executada'
  assert_igual 1 "$(_contar "$(<"$base/chamadas")" 'gstatic.com')" 'uma sonda so'
}

# TC-DSP-23
teste_dsp23_sonda_responde_e_dropbox_nao_e_rede_9_servico() {
  local base
  base=$(_cenario)
  printf falha >"$base/api"
  _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida rede)" "$DBX_ESTADO" 'rede = 9'
  assert_contem 'Dropbox inacessivel' "$(_linha servico)" 'mensagem'
  assert_contem 'internet=ok' "$DBX_SAIDA" 'internet ok'
}

# TC-DSP-25
teste_dsp25_429_e_limite_taxa_nao_indisponibilidade() {
  local base
  base=$(_cenario)
  printf 429 >"$base/api"
  _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida limite_taxa)" "$DBX_ESTADO" 'limite_taxa = 8'
  assert_nao_contem 'indisponivel' "$DBX_SAIDA" 'nao e indisponibilidade'
}

# TC-DSP-13, TC-DSP-14, TC-DSP-17, TC-DSP-19
teste_dsp13_url_padrao_e_configurada_e_qualquer_status_responde() {
  local base status
  base=$(_cenario)
  _rodar "$base" testar
  assert_contem 'https://www.gstatic.com/generate_204' "$(<"$base/chamadas")" 'URL padrao'
  rm -f "$base/chamadas" "$base/pedidos"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=https://exemplo.test/ping' _rodar "$base" testar
  assert_contem 'https://exemplo.test/ping' "$(<"$base/chamadas")" 'URL configurada'
  for status in 200 302 404 503; do
    printf '%s' "$status" >"$base/sonda"
    DBX_T_AMBIENTE='' _rodar "$base" testar
    assert_contem 'internet=' "$DBX_SAIDA" "status $status responde"
    assert_nao_contem 'internet=falha' "$DBX_SAIDA" "status $status conta como responde"
  done
  printf 204 >"$base/sonda"
  rm -f "$base/pedidos"
  DBX_T_AMBIENTE='' _rodar "$base" testar
  local pedido
  pedido=$(grep 'gstatic' "$base/pedidos")
  assert_contem 'connect-timeout = 5' "$pedido" 'conexao 5 s'
  assert_contem 'max-time = 10' "$pedido" 'total 10 s'
  assert_nao_contem 'Authorization' "$pedido" 'sem Authorization'
  assert_nao_contem 'Cookie' "$pedido" 'sem Cookie'
  assert_nao_contem '--data' "$pedido" 'sem corpo'
  assert_nao_contem ' -L' "$pedido" 'sem seguir redirecionamento'
  assert_nao_contem 'retry' "$pedido" 'sem repeticao'
}

# TC-DSP-15, TC-DSP-16
teste_dsp15_sonda_vazia_desliga_e_http_e_recusada_no_testar() {
  local base
  base=$(_cenario)
  printf falha >"$base/api"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=' _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida rede)" "$DBX_ESTADO" 'rede = 9'
  assert_nao_contem 'gstatic' "$(<"$base/chamadas")" 'nenhuma sonda'
  assert_contem 'sonda desligada' "$DBX_SAIDA" 'mensagem nao distingue as causas'
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=http://x.test/segredo_do_valor' _rodar "$base" testar
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'testar explicito recusa com 2 (DIV-310)'
  assert_nao_contem 'segredo_do_valor' "$(_todo_o_rastro "$base")" 'o valor nao e ecoado'
}

# TC-DSP-55, TC-DSP-57
teste_dsp55_nenhum_sentinela_na_saida_nem_na_requisicao() {
  local base modo
  base=$(_cenario)
  for modo in '' --json --null --debug; do
    rm -f "$base/pedidos"
    _rodar "$base" ${modo:+"$modo"} testar
    for s in "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$SENTINELA_CHAVE" "$SENTINELA_TOKEN"; do
      assert_nao_contem "$s" "$(_todo_o_rastro "$base" | grep -v 'oauth2/token')" "sentinela fora da saida e das requisicoes sem token ($modo)"
    done
    assert_nao_contem "$SENTINELA_TOKEN" "$DBX_SAIDA$DBX_ERRO" "token fora da saida ($modo)"
  done
  assert_nao_contem 'Authorization' "$(grep -v 'oauth2/token' "$base/pedidos")" 'sonda e servico sem Authorization'
}

# TC-DSP-10, TC-DSP-58 — portao fechado: nenhum byte de stdin lido
teste_dsp58_sem_terminal_nao_pergunta_e_nao_le_stdin() {
  local base resto
  base=$(_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf '%s' "$SENTINELA_STDIN" >"$base/entrada"
  resto=$(
    {
      env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
        TMPDIR="$base/tmp" "$BASH_ABSOLUTO" "$DBX_EXEC" testar >"$base/out" 2>"$base/err"
      cat
    } <"$base/entrada"
  )
  assert_igual "$SENTINELA_STDIN" "$resto" 'nenhum byte de stdin consumido'
  assert_nao_contem '[s/N]' "$(<"$base/err")" 'sem pergunta'
}

teste_dsp10_terminal_credencial_ausente_pergunta_e_recusa_mantem_3() {
  local base resposta
  for resposta in N '' talvez; do
    base=$(_cenario)
    rm -f "$base/config/dbx/credencial.json"
    _rodar_tty "$base" "$resposta" testar
    assert_contem 'Credencial ausente. Configurar agora? [s/N]' "$DBX_SAIDA" "pergunta (resposta [$resposta])"
    assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'recusa mantem 3'
    assert_contem 'nenhuma alteracao feita' "$DBX_SAIDA" 'mensagem de recusa'
    if [[ -e $base/config/dbx/credencial.json ]]; then _harness_falhar 'credencial criada na recusa' ''; fi
  done
}

teste_dsp10_terminal_fim_de_entrada_vale_recusa() {
  local base
  base=$(_cenario)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - testar
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'fim de entrada = recusa'
}

teste_dsp10_terminal_credencial_incompleta_pergunta_invalida() {
  local base
  base=$(_cenario)
  printf '{"versao":1,"app_key":"k","app_secret":"s"}' >"$base/config/dbx/credencial.json"
  _rodar_tty "$base" n testar
  assert_contem 'Credencial invalida. Configurar agora? [s/N]' "$DBX_SAIDA" 'arquivo existente = invalida'
}

teste_dsp10_aceite_inicia_o_config_e_o_cancelamento_mantem_o_codigo_da_falha() {
  local base
  base=$(_cenario)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_EOF=sim _rodar_tty "$base" s testar
  # fim de entrada logo depois do `s`: o config nao recebe a chave e falha.
  assert_contem 'Configurar agora?' "$DBX_SAIDA" 'pergunta'
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'config falho mantem o codigo da primeira falha (DIV-319)'
  assert_igual 1 "$(_contar "$DBX_SAIDA" 'Configurar agora?')" 'uma oferta so'
}

teste_dsp10_aceite_com_config_bem_sucedido_refaz_as_checagens_e_sai_0() {
  local base
  base=$(_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf '{"access_token":"%s","refresh_token":"%s","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$ESCOPOS" >"$base/token"
  DBX_T_EXTRAS=('App key:|kk' 'nao sera exibido|ss' 'Codigo de autorizacao:|cc')
  _rodar_tty "$base" s testar
  DBX_T_EXTRAS=()
  assert_igual 0 "$DBX_ESTADO" "config ok e checagens refeitas: codigo da segunda rodada; saida: $DBX_SAIDA"
  assert_contem 'credencial: ok' "$DBX_SAIDA" 'segunda rodada com credencial ok'
  assert_igual 1 "$(_contar "$DBX_SAIDA" 'Configurar agora?')" 'uma oferta so'
  assert_arquivo_existe "$base/config/dbx/credencial.json" 'credencial gravada pelo config'
}

teste_dsp10_dumb_e_dbx_teste_config_nao_fecham_o_portao() {
  local base
  base=$(_cenario)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_AMBIENTE='DBX_TESTE_CONFIG=nao' _rodar_tty "$base" - testar
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'DBX_TESTE_CONFIG=nao desliga a oferta'
  DBX_T_AMBIENTE='' _rodar_tty "$base" - --dry-run testar
  assert_nao_contem '[s/N]' "$DBX_SAIDA" '--dry-run fecha o portao'
}

teste_dsp26_permissao_larga_nao_recebe_oferta() {
  local base
  base=$(_cenario)
  chmod 644 "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - testar
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'sem oferta para permissao (RF-150(d))'
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'recusa de hoje'
}

# Achado #1 (conformidade): o remedio acompanha o motivo da recusa
teste_dsp26b_remedio_da_recusa_acompanha_o_motivo() {
  local base arq
  base=$(_cenario)
  chmod 644 "$base/config/dbx/credencial.json"
  _rodar "$base" testar
  assert_contem "chmod 600 $base/config/dbx/credencial.json" "$(_linha credencial)" 'permissao: chmod 600 no arquivo'

  base=$(_cenario)
  mkdir -p "$base/config/dbx/perfis"
  chmod 755 "$base/config/dbx/perfis"
  printf '{"versao":1,"app_key":"k"}' >"$base/config/dbx/perfis/a.json"
  chmod 600 "$base/config/dbx/perfis/a.json"
  _rodar "$base" --perfil a testar
  assert_contem "chmod 700 $base/config/dbx/perfis" "$(_linha credencial)" 'permissao_diretorio: chmod 700 no diretorio'
  assert_nao_contem 'chmod 600' "$(_linha credencial)" 'permissao_diretorio: nao sugere 600'
  assert_nao_contem 'permissao_diretorio_diretorio' "$(_linha credencial)" 'permissao_diretorio: sem texto quebrado'

  base=$(_cenario)
  mkdir -p "$base/config/dbx/perfis"
  chmod 700 "$base/config/dbx/perfis"
  arq=$base/alvo.json
  printf '{"versao":1,"app_key":"k"}' >"$arq"
  chmod 600 "$arq"
  ln -s "$arq" "$base/config/dbx/perfis/a.json"
  _rodar "$base" --perfil a testar
  assert_contem 'ligacao_simbolica' "$(_linha credencial)" 'motivo nomeado'
  assert_contem 'remova a ligacao simbolica' "$(_linha credencial)" 'ligacao_simbolica: remedio textual'
  assert_contem "remova a ligacao simbolica em $base/config/dbx/perfis/a.json " "$(_linha credencial)" 'ligacao no arquivo: aponta o arquivo'

  base=$(_cenario)
  mkdir -p "$base/real" "$base/config/dbx"
  chmod 700 "$base/real"
  printf '{"versao":1,"app_key":"k"}' >"$base/real/a.json"
  chmod 600 "$base/real/a.json"
  ln -s "$base/real" "$base/config/dbx/perfis"
  _rodar "$base" --perfil a testar
  assert_contem "remova a ligacao simbolica em $base/config/dbx/perfis " "$(_linha credencial)" 'ligacao no diretorio perfis: aponta perfis, nao o pai'
}

# Achado #10a: com a internet em falha, a credencial "nao executada" nomeia a internet
teste_dsp03b_credencial_nao_executada_nomeia_a_falta_de_internet() {
  local base
  base=$(_cenario)
  printf falha >"$base/sonda"
  printf falha >"$base/api"
  printf falha >"$base/content"
  _rodar "$base" testar
  assert_contem 'nao executada: sem acesso a internet' "$(_linha credencial)" 'causa nomeia a internet'
  assert_nao_contem 'servico Dropbox com falha' "$(_linha credencial)" 'nao culpa o servico'
  printf 204 >"$base/sonda"
  printf 503 >"$base/api"
  _rodar "$base" testar
  assert_contem 'servico Dropbox com falha' "$(_linha credencial)" 'servico com falha continua nomeado'
}

# N3 (rodada 2): sonda responde e o Dropbox esta mudo -> a causa nomeia o Dropbox
teste_dsp03c_credencial_nao_executada_nomeia_dropbox_inacessivel() {
  local base
  base=$(_cenario)
  printf 204 >"$base/sonda"
  printf falha >"$base/api"
  printf falha >"$base/content"
  _rodar "$base" testar
  assert_contem 'nao executada: Dropbox inacessivel' "$(_linha credencial)" 'causa nomeia o Dropbox'
  assert_nao_contem 'sem acesso a internet' "$(_linha credencial)" 'nao culpa a internet'
  assert_nao_contem 'servico Dropbox com falha' "$(_linha credencial)" 'nao usa a causa generica'
}

# N1 (rodada 2): o --debug da sonda nunca mostra userinfo, caminho ou query da URL
teste_dsp55c_debug_da_sonda_nao_vaza_userinfo() {
  local base
  base=$(_cenario)
  printf 503 >"$base/sonda"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=https://u:USERINFO_SENTINELA_z9@proxy.ex:8443/p?q=1' _rodar "$base" --debug testar
  assert_contem 'proxy.ex' "$DBX_ERRO" 'debug traz o host'
  assert_contem '503' "$DBX_ERRO" 'debug traz o status'
  assert_nao_contem 'USERINFO_SENTINELA_z9' "$DBX_ERRO$DBX_SAIDA" 'sem a senha'
  assert_nao_contem 'u:' "$(grep 'sonda GET' <<<"$DBX_ERRO")" 'sem o usuario'
  assert_nao_contem '8443/' "$(grep 'sonda GET' <<<"$DBX_ERRO")" 'sem caminho'
  assert_nao_contem 'q=1' "$DBX_ERRO$DBX_SAIDA" 'sem query'
}

# R1 (rodada 3): a linha de debug da sonda vai so a stderr; stdout fica intacto
teste_dsp55d_debug_da_sonda_nao_polui_stdout() {
  local base
  base=$(_cenario)
  printf 503 >"$base/sonda"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=https://exemplo.test/ping' _rodar "$base" --debug testar
  assert_contem 'sonda GET' "$DBX_ERRO" 'a linha de debug esta em stderr'
  assert_nao_contem 'debug:' "$DBX_SAIDA" 'stdout sem a linha de debug'
  assert_nao_contem 'sonda GET' "$DBX_SAIDA" 'stdout sem a requisicao da sonda'
}

# R4 (rodada 3): senha com /, ? ou # sem encoding nunca vaza pedaco algum
teste_dsp55e_debug_da_sonda_nao_vaza_senha_com_delimitador() {
  local base url
  for url in 'https://u:pasENT/ss@host.ex/' 'https://u:pxSENT?a@host.ex/' 'https://u:pySENT#a@host.ex/' 'https://u:p@zzSENT@host.ex/'; do
    base=$(_cenario)
    printf 503 >"$base/sonda"
    DBX_T_AMBIENTE="DBX_TESTE_INTERNET_URL=$url" _rodar "$base" --debug testar
    assert_nao_contem 'SENT' "$DBX_ERRO$DBX_SAIDA" "nenhum pedaco da senha: $url"
    assert_nao_contem 'u:p' "$DBX_ERRO$DBX_SAIDA" "sem usuario:senha: $url"
  done
}

# Achado #7: --debug registra o status e a requisicao mascarada da sonda (RF-149(c)(f))
teste_dsp55b_debug_da_sonda_traz_status_sem_segredo_nem_parametro() {
  local base
  base=$(_cenario)
  printf 503 >"$base/sonda"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=https://exemplo.test/ping?chave=PARAM_SENTINELA_q1' _rodar "$base" --debug testar
  assert_contem 'sonda' "$DBX_ERRO" 'debug fala da sonda'
  assert_contem '503' "$DBX_ERRO" 'debug traz o status recebido'
  assert_contem 'exemplo.test' "$DBX_ERRO" 'debug traz o host'
  assert_nao_contem 'PARAM_SENTINELA_q1' "$DBX_ERRO$DBX_SAIDA" 'sem parametro de URL'
  assert_nao_contem "$SENTINELA_SEGREDO" "$DBX_ERRO" 'sem segredo'
  assert_nao_contem "$SENTINELA_REFRESH" "$DBX_ERRO" 'sem refresh token'
  _rodar "$base" testar
  assert_nao_contem 'sonda' "$DBX_ERRO" 'sem --debug, stderr calado'
}

harness_executar "$@"
