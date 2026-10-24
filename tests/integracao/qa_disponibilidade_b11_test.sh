#!/usr/bin/env bash
# Suite independente do QA Expert para a fase 11 (teste de disponibilidade,
# RF-148..155), ciclo 1: classificacao das causas e codigos de saida, oferta do
# config (so com terminal; nunca em stdin consumido), ausencia de segredo em
# qualquer canal, stdout limpo em --json/--null com --debug, caminho feliz sem
# requisicao extra e sync paralelo (uma sonda, um aviso).
#
# Reusa so o duplo de curl e o pty de tests/support/disponibilidade.sh; os
# cenarios, valores e sentinelas de URL sao proprios do QA.
#
# shellcheck disable=SC2016
# Justificativa: scripts auxiliares sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
# shellcheck source=tests/support/disponibilidade.sh
. "$DBX_HARNESS_RAIZ/tests/support/disponibilidade.sh"

QA_REDE=$(dbx_errors_codigo_saida rede)
QA_REMOTO=$(dbx_errors_codigo_saida erro_remoto)
QA_CONFIG=$(dbx_errors_codigo_saida configuracao)
QA_AUTENT=$(dbx_errors_codigo_saida autenticacao)
QA_LIMITE=$(dbx_errors_codigo_saida limite_taxa)
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly QA_REDE QA_REMOTO QA_CONFIG QA_AUTENT QA_LIMITE QA_USO
QA_PW='QA_SENHA_na_url_8k3j2h'
QA_TK='QA_TOKEN_na_url_5m4n3b'

_qa_cenario() {
  local base
  base=$(_cenario)
  printf '{"used":1,"allocation":{".tag":"individual","allocated":2}}' >"$base/rpc_corpo"
  printf '%s' "$base"
}

_qa_n() { # <base> <trecho> — chamadas ao duplo que casam
  local n
  n=$(grep -F -c -- "$2" "$1/chamadas" 2>/dev/null)
  printf '%s' "${n:-0}"
}

# ---------------------------------------------------------------- classificacao

# TC-DSP-22: a sonda responder 5xx/4xx/3xx e "internet ok" (RF-149(c))
teste_qa_sonda_com_qualquer_status_http_conta_como_internet() {
  local base codigo
  for codigo in 200 301 403 503; do
    base=$(_qa_cenario)
    printf '%s' "$codigo" >"$base/sonda"
    _rodar "$base" testar
    assert_igual 0 "$DBX_ESTADO" "sonda $codigo: erro: $DBX_ERRO"
    assert_nao_contem 'internet=falha' "$DBX_SAIDA" "sonda $codigo conta como resposta (aviso, DIV-311)"
    assert_contem 'servico=ok' "$DBX_SAIDA" "sonda $codigo nao impede as demais checagens"
  done
}

# RF-150(a): api 503 = servico indisponivel (10), nao rede
teste_qa_api_503_e_servico_indisponivel_dez() {
  local base
  base=$(_qa_cenario)
  printf 503 >"$base/api"
  _rodar "$base" testar
  assert_igual "$QA_REMOTO" "$DBX_ESTADO" "503 = erro_remoto; saida: $DBX_SAIDA"
  assert_contem 'servico=falha' "$DBX_SAIDA" 'servico falha'
  assert_contem 'internet=ok' "$DBX_SAIDA" 'a internet esta ok'
}

# RF-150(a): 429 continua limite_taxa (8)
teste_qa_api_429_continua_limite_de_taxa() {
  local base
  base=$(_qa_cenario)
  printf 429 >"$base/api"
  _rodar "$base" testar
  assert_igual "$QA_LIMITE" "$DBX_ESTADO" "429 = limite_taxa; saida: $DBX_SAIDA"
}

# DIV-308/320: so o host de conteudo cai
teste_qa_content_503_falha_so_o_servico_conteudo() {
  local base
  base=$(_qa_cenario)
  printf 503 >"$base/content"
  _rodar "$base" testar
  assert_igual "$QA_REMOTO" "$DBX_ESTADO" "saida: $DBX_SAIDA"
  assert_contem 'servico=ok' "$DBX_SAIDA" 'api ok'
  assert_contem 'servico_conteudo=falha' "$DBX_SAIDA" 'conteudo falha'
}

# RF-150(a): Dropbox inacessivel (sonda ok, api sem resposta) = rede 9, id servico
teste_qa_dropbox_inacessivel_com_internet_ok_sai_nove_e_nomeia_o_servico() {
  local base
  base=$(_qa_cenario)
  printf falha >"$base/api"
  _rodar "$base" testar
  assert_igual "$QA_REDE" "$DBX_ESTADO" "saida: $DBX_SAIDA"
  assert_contem 'internet=ok' "$DBX_SAIDA" 'internet ok'
  assert_contem 'servico=falha' "$DBX_SAIDA" 'servico falha'
  assert_nao_contem 'sem acesso a internet' "$(_linha servico)" 'nao culpa a internet'
}

# RF-150(b): sonda desligada, rede cai: mensagem que nao distingue, zero sonda
teste_qa_sonda_desligada_nao_faz_requisicao_e_nao_distingue_a_causa() {
  local base
  base=$(_qa_cenario)
  printf falha >"$base/token_codigo"
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=' _rodar "$base" space
  assert_igual "$QA_REDE" "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_igual 0 "$(_qa_n "$base" gstatic)" 'sonda desligada: nenhuma requisicao a sonda'
  assert_contem 'sonda desligada' "$DBX_ERRO" 'mensagem informa a sonda desligada'
}

# RF-151(d): renovacao sem resposta + sem internet: exit 9 e a causa e a internet
teste_qa_automatico_sem_internet_nomeia_internet_com_uma_so_sonda() {
  local base
  base=$(_qa_cenario)
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" space
  assert_igual "$QA_REDE" "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_contem 'internet' "$DBX_ERRO" 'nomeia a internet'
  assert_igual 1 "$(_qa_n "$base" gstatic)" 'uma sonda'
}

# RF-151(d)/RF-150(a): internet ok mas o Dropbox nao responde: nomeia o Dropbox
teste_qa_automatico_dropbox_inacessivel_nao_culpa_a_internet() {
  local base
  base=$(_qa_cenario)
  printf falha >"$base/token_codigo"
  _rodar "$base" space
  assert_igual "$QA_REDE" "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_nao_contem 'sem acesso a internet' "$DBX_ERRO" 'a sonda respondeu: a internet existe'
  assert_contem 'Dropbox' "$DBX_ERRO" 'nomeia o Dropbox'
}

# RF-151(d): renovacao 503 = 10 e classificacao com no maximo uma sonda
teste_qa_automatico_renovacao_503_sai_dez() {
  local base
  base=$(_qa_cenario)
  printf 503 >"$base/token_codigo"
  printf '{}' >"$base/token_corpo"
  _rodar "$base" space
  assert_igual "$QA_REMOTO" "$DBX_ESTADO" "saida: $DBX_ERRO"
  [[ $(_qa_n "$base" gstatic) -le 1 ]] || _harness_falhar 'no maximo uma sonda' "$(<"$base/chamadas")"
}

# RF-151(e): falha 503 NO MEIO (token ja obtido) nao oferece config e mantem o codigo
teste_qa_falha_no_meio_com_terminal_nao_oferece_config() {
  local base
  base=$(_qa_cenario)
  printf 503 >"$base/rpc"
  _rodar_tty "$base" - space
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'a oferta so existe antes de qualquer efeito'
  assert_igual "$QA_REMOTO" "$DBX_ESTADO" "saida: $DBX_SAIDA"
}

# ------------------------------------------------------------------ oferta/config

# RF-152(a): sem terminal e com bytes em stdin: nenhum byte consumido, codigo de hoje
teste_qa_sem_terminal_nunca_consome_stdin_credencial_ausente() {
  local base resto
  base=$(_qa_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf '#!%s\n' "$BASH_ABSOLUTO" >"$base/rodar.sh"
  cat >>"$base/rodar.sh" <<'FIM'
"$1" "$2" upload - /x.txt 2>"$3/err"
printf 'ESTADO=%s\n' "$?"
cat
FIM
  printf '%s' "$SENTINELA_STDIN" >"$base/entrada"
  resto=$(env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" "$BASH_ABSOLUTO" "$base/rodar.sh" "$BASH_ABSOLUTO" "$DBX_EXEC" "$base" <"$base/entrada")
  assert_contem "ESTADO=$QA_CONFIG" "$resto" 'codigo de hoje (3)'
  assert_contem "$SENTINELA_STDIN" "$resto" 'stdin intacto depois do comando'
  assert_nao_contem '[s/N]' "$(<"$base/err")" 'nenhuma pergunta'
}

# RF-152(a): sem terminal e credencial recusada: codigo 5, sem pergunta, sem config
teste_qa_sem_terminal_invalid_grant_sai_cinco_sem_pergunta() {
  local base
  base=$(_qa_cenario)
  printf 400 >"$base/token_codigo"
  printf '{"error":"invalid_grant"}' >"$base/token_corpo"
  _rodar "$base" space
  assert_igual "$QA_AUTENT" "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_nao_contem '[s/N]' "$DBX_ERRO" 'sem pergunta'
  assert_contem 'autorize de novo' "$DBX_ERRO" 'remedio de hoje (mensagem do preflight atual)'
}

# RF-152(c): so s/S/sim aceitam; qualquer outra coisa (inclusive y e yes) recusa
teste_qa_resposta_diferente_de_s_recusa_sem_alterar_nada() {
  local base resposta antes
  for resposta in '' n N y yes nao 0 ' '; do
    base=$(_qa_cenario)
    rm -f "$base/config/dbx/credencial.json"
    antes=$(_retrato "$base/config")
    _rodar_tty "$base" "$resposta" space
    assert_igual "$QA_CONFIG" "$DBX_ESTADO" "resposta [$resposta]: recusa sai 3; saida: $DBX_SAIDA"
    assert_contem 'Credencial ausente. Configurar agora? [s/N]' "$DBX_SAIDA" 'pergunta'
    assert_contem 'nenhuma alteracao' "$DBX_SAIDA" "resposta [$resposta]: informa que nada mudou"
    assert_igual "$antes" "$(_retrato "$base/config")" "resposta [$resposta]: nada gravado"
    assert_igual 0 "$(_qa_n "$base" oauth2)" "resposta [$resposta]: o config nao rodou"
  done
}

# RF-153(c): recusa de credencial invalida mantem o arquivo byte a byte; sai 5
teste_qa_recusa_com_credencial_recusada_mantem_o_arquivo_e_sai_cinco() {
  local base antes
  base=$(_qa_cenario)
  printf 400 >"$base/token_codigo"
  printf '{"error":"invalid_grant"}' >"$base/token_corpo"
  antes=$(_retrato "$base/config")
  _rodar_tty "$base" n space
  assert_igual "$QA_AUTENT" "$DBX_ESTADO" "saida: $DBX_SAIDA"
  assert_contem 'Credencial invalida. Configurar agora? [s/N]' "$DBX_SAIDA" 'pergunta de credencial invalida'
  assert_igual "$antes" "$(_retrato "$base/config")" 'arquivo intacto'
}

# RF-152(b): --json com terminal e recusa: stdout (arquivo) vazio, pergunta so em stderr
teste_qa_json_com_terminal_recusa_deixa_stdout_vazio() {
  local base
  base=$(_qa_cenario)
  rm -f "$base/config/dbx/credencial.json"
  DBX_T_REDIR_OUT=sim _rodar_tty "$base" n --json space
  assert_igual "$QA_CONFIG" "$DBX_ESTADO" "saida: $DBX_SAIDA"
  if [[ -s $base/stdout_arquivo ]]; then _harness_falhar 'stdout deveria estar vazio' "$(<"$base/stdout_arquivo")"; fi
  assert_contem '[s/N]' "$DBX_SAIDA" 'a pergunta aparece no terminal (stderr)'
}

# RF-152(a): --dry-run nunca pergunta
teste_qa_dry_run_com_terminal_nao_oferece() {
  local base
  base=$(_qa_cenario)
  rm -f "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - --dry-run space
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'dry-run nao pergunta'
  assert_igual "$QA_CONFIG" "$DBX_ESTADO" 'codigo de hoje'
}

# RF-150(d): arquivo com permissao aberta e recusa de preflight, sem oferta
teste_qa_permissao_aberta_nao_oferece_o_config() {
  local base
  base=$(_qa_cenario)
  chmod 644 "$base/config/dbx/credencial.json"
  _rodar_tty "$base" - space
  assert_nao_contem '[s/N]' "$DBX_SAIDA" 'permissao nao e falta de dado'
  assert_igual "$QA_CONFIG" "$DBX_ESTADO" "saida: $DBX_SAIDA"
}

# RF-151(f): comandos de fora nao recebem a oferta
teste_qa_comandos_de_fora_nao_oferecem() {
  local base cmd
  for cmd in diagnostico testar perfis completar; do
    base=$(_qa_cenario)
    rm -f "$base/config/dbx/credencial.json"
    _rodar_tty "$base" - "$cmd"
    # `testar` tem a sua propria oferta (DIV-309 B): so ele pode perguntar.
    if [[ $cmd != testar ]]; then assert_nao_contem '[s/N]' "$DBX_SAIDA" "$cmd nao oferece"; fi
  done
}

# RF-153(a) com 'sim' por extenso: aceita e o comando original continua
teste_qa_resposta_sim_por_extenso_aceita_e_o_comando_continua() {
  local base
  base=$(_qa_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf '{"access_token":"%s","refresh_token":"%s","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$ESCOPOS" >"$base/token"
  DBX_T_EXTRAS=('App key:|kk' 'nao sera exibido|ss' 'Codigo de autorizacao:|cc')
  _rodar_tty "$base" sim space
  DBX_T_EXTRAS=()
  assert_igual 0 "$DBX_ESTADO" "o comando continua apos o config; saida: $DBX_SAIDA"
  assert_igual 1 "$(_qa_n "$base" get_space_usage)" 'o comando original rodou uma vez'
}

# ----------------------------------------------------------------------- segredos

# RF-154(a): nenhum sentinela, nem senha ou token embutidos na URL da sonda, em
# testar/automatico, com e sem --debug, nos tres caminhos de falha
teste_qa_nenhum_segredo_em_nenhum_canal_nem_na_url_da_sonda() {
  local base url alvo s variante
  url="https://qa_usuario:${QA_PW}@sonda.invalid/p?token=${QA_TK}"
  for variante in 'testar' '--debug testar' '--debug space' '--json --debug testar'; do
    for alvo in ok sonda_cai token_cai; do
      base=$(_qa_cenario)
      case $alvo in
        sonda_cai) printf falha >"$base/sonda" ;;
        token_cai) printf falha >"$base/token_codigo" ;;
      esac
      # shellcheck disable=SC2086
      DBX_T_AMBIENTE="DBX_TESTE_INTERNET_URL=$url" _rodar "$base" $variante
      for s in "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$SENTINELA_CHAVE" "$SENTINELA_TOKEN" "$QA_PW" "$QA_TK"; do
        assert_segredo_ausente "$s" "$DBX_SAIDA$DBX_ERRO" "[$variante/$alvo] segredo fora de stdout e stderr"
      done
    done
  done
}

# RF-149(e)/RF-154(b): a sonda e a de servico nao levam credencial nem cabecalho
teste_qa_requisicoes_sem_token_nao_carregam_credencial() {
  local base linha s
  base=$(_qa_cenario)
  _rodar "$base" --debug testar
  while IFS= read -r linha; do
    case $linha in
      *oauth2/token*) continue ;;
    esac
    for s in "$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$SENTINELA_SEGREDO" "$SENTINELA_CHAVE"; do
      assert_segredo_ausente "$s" "$linha" 'sonda e servico sem credencial'
    done
    case ${linha,,} in *authorization*) _harness_falhar 'sonda/servico enviou Authorization' "$linha" ;; esac
  done <"$base/pedidos"
}

# ------------------------------------------------------------------- stdout limpo

# RF-154(d): --debug nunca polui stdout; --json e --null identicos com e sem --debug
teste_qa_json_e_null_com_debug_tem_o_mesmo_stdout() {
  local base sem com modo caso
  for caso in ok falha; do
    for modo in --json --null; do
      base=$(_qa_cenario)
      [[ $caso == falha ]] && printf falha >"$base/api"
      _rodar "$base" "$modo" testar
      sem=$DBX_SAIDA
      _rodar "$base" "$modo" --debug testar
      com=$DBX_SAIDA
      assert_igual "$sem" "$com" "[$caso $modo] stdout identico com --debug"
    done
  done
}

# RF-154(d): o caminho automatico com --json/--null nao muda stdout por causa do --debug
teste_qa_automatico_json_com_debug_stdout_igual() {
  local base sem com
  base=$(_qa_cenario)
  _rodar "$base" --json space
  sem=$DBX_SAIDA
  _rodar "$base" --json --debug space
  com=$DBX_SAIDA
  assert_igual "$sem" "$com" 'stdout identico'
  assert_igual 0 "$DBX_ESTADO" "saida: $DBX_ERRO"
}

# --null: registros separados por NUL e nenhum texto de diagnostico no stdout
teste_qa_null_so_tem_registros_do_contrato() {
  local base bytes
  base=$(_qa_cenario)
  _rodar "$base" --null --debug testar
  bytes=$(tr -d '\0' <"$base/out" | wc -c)
  [[ $bytes -gt 0 ]] || _harness_falhar 'stdout vazio' "$DBX_ERRO"
  assert_nao_contem 'dbx: ' "$(tr '\0' '\n' <"$base/out")" 'mensagens vao a stderr'
}

# ------------------------------------------------------------------- caminho feliz

# RF-151(g): tudo ok = so renovacao e a chamada do comando; sem sonda, api ou content
teste_qa_caminho_feliz_nao_faz_requisicao_extra() {
  local base
  base=$(_qa_cenario)
  _rodar "$base" space
  assert_igual 0 "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_igual 0 "$(_qa_n "$base" gstatic)" 'nenhuma sonda'
  assert_igual 0 "$(_qa_n "$base" content.dropboxapi)" 'nenhum content'
  assert_igual 2 "$(wc -l <"$base/chamadas")" "so renovacao + get_space_usage: $(<"$base/chamadas")"
  [[ -z $DBX_ERRO ]] || _harness_falhar 'stderr deveria estar vazio' "$DBX_ERRO"
}

# RF-151(g): o mesmo vale com URL da sonda invalida no caminho feliz (nada a sondar)
teste_qa_caminho_feliz_com_url_invalida_continua_sem_sonda() {
  local base
  base=$(_qa_cenario)
  DBX_T_AMBIENTE='DBX_TESTE_INTERNET_URL=http://x.invalid' _rodar "$base" space
  assert_igual 0 "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_igual 2 "$(wc -l <"$base/chamadas")" 'duas requisicoes'
}

# ---------------------------------------------------------------- sonda e sync

_qa_sync() { # <base> — arvore local com varios arquivos
  mkdir -p "$1/loc"
  local i
  for i in 1 2 3 4 5 6; do printf 'a%s' "$i" >"$1/loc/f$i.txt"; done
}

# RF-149(g): sync --enviar --paralelo com a rede caida: uma sonda so
teste_qa_sync_paralelo_com_rede_caida_faz_uma_sonda() {
  local base
  base=$(_qa_cenario)
  _qa_sync "$base"
  printf falha >"$base/token_codigo"
  printf falha >"$base/sonda"
  _rodar "$base" sync --enviar --paralelo 4 --origem "$base/loc" --destino /rem
  assert_igual "$QA_REDE" "$DBX_ESTADO" "saida: $DBX_ERRO"
  assert_igual 1 "$(_qa_n "$base" gstatic)" "uma sonda por execucao: $(<"$base/chamadas")"
}

# RF-149(b)/DIV-310: aviso de URL invalida uma vez, no automatico, sem o valor
teste_qa_sync_paralelo_url_invalida_avisa_uma_vez_sem_o_valor() {
  local base n
  base=$(_qa_cenario)
  _qa_sync "$base"
  printf falha >"$base/token_codigo"
  DBX_T_AMBIENTE="DBX_TESTE_INTERNET_URL=http://${QA_PW}.invalid/x" \
    _rodar "$base" sync --enviar --paralelo 4 --origem "$base/loc" --destino /rem
  assert_igual "$QA_REDE" "$DBX_ESTADO" "o aviso nao quebra o comando; saida: $DBX_ERRO"
  n=$(_contar "$DBX_ERRO" 'DBX_TESTE_INTERNET_URL deve comecar')
  assert_igual 1 "$n" "um aviso por execucao: $DBX_ERRO"
  assert_segredo_ausente "$QA_PW" "$DBX_ERRO" 'aviso sem o valor'
  assert_igual 0 "$(_qa_n "$base" invalid)" 'sonda desligada: nenhuma requisicao'
}

# RF-149(b)/DIV-310: no testar explicito a URL invalida e recusa (2), sem requisicao
teste_qa_testar_url_invalida_sai_dois_sem_requisicao() {
  local variante base
  for variante in 'http://x.invalid' 'ftp://x.invalid' 'HTTPS://x.invalid' 'https://' 'gstatic.com'; do
    base=$(_qa_cenario)
    DBX_T_AMBIENTE="DBX_TESTE_INTERNET_URL=$variante" _rodar "$base" testar
    assert_igual "$QA_USO" "$DBX_ESTADO" "[$variante] uso_invalido; saida: $DBX_ERRO"
    assert_arquivo_ausente "$base/chamadas" "[$variante] nenhuma requisicao"
  done
}

# RF-149(e)/RNF-30: a URL da sonda com aspas e quebra de linha nao injeta opcao de curl
teste_qa_url_da_sonda_nao_injeta_opcao_no_curl() {
  local base url
  base=$(_qa_cenario)
  url=$'https://x.invalid/"\noutput = "'"$base"$'/pwned"\n#'
  DBX_T_AMBIENTE="DBX_TESTE_INTERNET_URL=$url" _rodar "$base" testar
  assert_arquivo_ausente "$base/pwned" 'a URL nao virou diretiva de curl'
  assert_nao_contem '; output = ' "$(<"$base/pedidos")" 'diretiva injetada no arquivo de opcoes'
}

# RF-148(c): campo vazio ("") conta como ausente e sai nomeado, sem valor
teste_qa_campo_vazio_e_nomeado_sem_valor() {
  local base
  base=$(_qa_cenario)
  printf '{"versao":1,"app_key":"%s","app_secret":"","refresh_token":"%s","raiz_remota":"/"}' \
    "$SENTINELA_CHAVE" "$SENTINELA_REFRESH" >"$base/config/dbx/credencial.json"
  _rodar "$base" testar
  assert_igual "$QA_CONFIG" "$DBX_ESTADO" "saida: $DBX_SAIDA"
  assert_contem 'app secret' "$(_linha credencial)" 'nomeia o campo vazio'
  assert_nao_contem 'app key' "$(_linha credencial)" 'nao acusa campo presente'
  assert_segredo_ausente "$SENTINELA_REFRESH" "$(_todo_o_rastro "$base")" 'sem valor'
}

# RF-152(c): S maiusculo aceita
teste_qa_resposta_s_maiusculo_aceita() {
  local base
  base=$(_qa_cenario)
  rm -f "$base/config/dbx/credencial.json"
  printf '{"access_token":"%s","refresh_token":"%s","account_id":"dbid:SINTETICO","expires_in":14400,"scope":"%s"}' \
    "$SENTINELA_TOKEN" "$SENTINELA_REFRESH" "$ESCOPOS" >"$base/token"
  DBX_T_EXTRAS=('App key:|kk' 'nao sera exibido|ss' 'Codigo de autorizacao:|cc')
  _rodar_tty "$base" S space
  DBX_T_EXTRAS=()
  assert_igual 0 "$DBX_ESTADO" "S aceita; saida: $DBX_SAIDA"
}

# RF-154(f): nenhum arquivo temporario sobrevive em sucesso, falha de rede e recusa
teste_qa_nenhum_temporario_sobrevive() {
  local base caso
  for caso in ok sonda_cai token_cai invalid_grant; do
    base=$(_qa_cenario)
    case $caso in
      sonda_cai) printf falha >"$base/sonda" ;;
      token_cai) printf falha >"$base/token_codigo" ;;
      invalid_grant) printf 400 >"$base/token_codigo" && printf '{"error":"invalid_grant"}' >"$base/token_corpo" ;;
    esac
    _rodar "$base" testar
    _rodar "$base" space
    assert_igual '' "$(find "$base/tmp" -mindepth 1 2>/dev/null)" "[$caso] TMPDIR vazio"
  done
}

harness_executar "$@"
