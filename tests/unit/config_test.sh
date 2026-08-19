#!/usr/bin/env bash
# Testes de lib/config.sh — leitura e escrita do arquivo de credencial.
#
# E a UNICA escrita persistente prevista em todo o projeto (PRJ-DEC-07). O
# arquivo guarda segredo, entao nenhuma funcao pode ecoa-lo em diagnostico.

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a "bash -c", que precisa chegar
# sem expansao ao processo filho.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"

_area() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/config.XXXXXX") || return 1
  (cd -P -- "$dir" && pwd -P)
}

_com_xdg() { # <area> — define XDG e devolve o caminho esperado do arquivo
  XDG_CONFIG_HOME="$1/config"
  export XDG_CONFIG_HOME
}

# ---------------------------------------------------------------------------
# Localizacao (RNF-04, DP-11): XDG com fallback, sem sobrescrita por ambiente
# ---------------------------------------------------------------------------

teste_caminho_segue_xdg_config_home() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_caminho
  assert_igual "$area/config/dbx/credencial.json" "$DBX_CONFIG_RESULTADO"
}

teste_fallback_e_config_no_diretorio_do_usuario() {
  local area
  area=$(_area)
  unset XDG_CONFIG_HOME
  HOME="$area" dbx_config_caminho
  assert_igual "$area/.config/dbx/credencial.json" "$DBX_CONFIG_RESULTADO"
}

teste_xdg_relativo_e_recusado() {
  # XDG exige caminho absoluto; relativo torna a localizacao dependente do
  # diretorio corrente, o que muda o alvo entre invocacoes.
  XDG_CONFIG_HOME='relativo/config' assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_caminho
}

teste_nenhuma_variavel_de_ambiente_sobrescreve_a_credencial() {
  # DP-11: a proibicao e deliberada e remove o vetor de leitura do ambiente do
  # processo. Nenhum nome de variavel pode injetar segredo.
  local area alvo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/raiz'
  alvo=$DBX_CONFIG_RESULTADO
  DBX_REFRESH_TOKEN='INJETADO' DBX_TOKEN='INJETADO' DBX_APP_SECRET='INJETADO' \
    dbx_config_carregar
  assert_igual 'RT' "$DBX_CONFIG_REFRESH_TOKEN" 'o valor precisa vir do arquivo, nunca do ambiente'
  assert_arquivo_existe "$alvo"
}

# ---------------------------------------------------------------------------
# Invariante de DP-05: nenhuma funcao recebe identificador de conta ou perfil
# ---------------------------------------------------------------------------

teste_nenhuma_funcao_recebe_identificador_de_perfil() {
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/config.sh" |
    grep -nEi '(perfil|profile|conta|account)' || true)
  assert_igual '' "$achados" \
    "DP-05 fixou uma conta so; nocao de perfil nao pode existir no componente: $achados"
}

# ---------------------------------------------------------------------------
# Gravacao atomica e permissao (RNF-04)
# ---------------------------------------------------------------------------

teste_gravacao_cria_arquivo_com_permissao_restrita() {
  local area modo
  area=$(_area)
  _com_xdg "$area"
  assert_sucesso dbx_config_gravar 'AK' 'AS' 'RT' '/raiz'
  modo=$(stat -c '%a' "$DBX_CONFIG_RESULTADO")
  assert_igual '600' "$modo" 'a credencial precisa nascer 0600 (RNF-04)'
  modo=$(stat -c '%a' "$(dirname "$DBX_CONFIG_RESULTADO")")
  assert_igual '700' "$modo" 'o diretorio tambem nao pode ser legivel por terceiros'
}

teste_gravacao_cria_diretorio_pai_ausente() {
  local area
  area=$(_area)
  _com_xdg "$area"
  assert_sucesso dbx_config_gravar 'AK' 'AS' 'RT' '/raiz'
  assert_arquivo_existe "$area/config/dbx/credencial.json"
}

teste_gravacao_e_atomica_e_nao_deixa_residuo() {
  local area restos
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/raiz'
  # Procura QUALQUER arquivo alem da credencial. A versao anterior procurava
  # por nome contendo "tmp" e nao casava com o temporario real, entao a mutacao
  # que troca a renomeacao atomica por copia passava despercebida.
  restos=$(find "$area/config/dbx" -mindepth 1 ! -name 'credencial.json' 2>/dev/null)
  assert_igual '' "$restos" 'gravacao atomica nao pode deixar arquivo intermediario'
}

teste_falha_de_gravacao_preserva_o_arquivo_anterior() {
  # Se a escrita falhar no meio, a credencial que ja funcionava nao pode ser
  # destruida: o usuario ficaria sem acesso e sem forma de voltar.
  local area conteudo_antes
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT-BOM' '/raiz'
  conteudo_antes=$(cat "$DBX_CONFIG_RESULTADO")
  chmod 500 "$(dirname "$DBX_CONFIG_RESULTADO")"
  dbx_config_gravar 'AK2' 'AS2' 'RT-NOVO' '/raiz2' 2>/dev/null
  chmod 700 "$(dirname "$DBX_CONFIG_RESULTADO")"
  assert_igual "$conteudo_antes" "$(cat "$DBX_CONFIG_RESULTADO")" \
    'gravacao malsucedida nao pode corromper a credencial existente'
}

# ---------------------------------------------------------------------------
# Leitura e viagem de ida e volta
# ---------------------------------------------------------------------------

teste_ida_e_volta_preserva_os_campos() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'chave-app' 'segredo-app' 'token-refresh' '/backups'
  assert_sucesso dbx_config_carregar
  assert_igual 'chave-app' "$DBX_CONFIG_APP_KEY"
  assert_igual 'segredo-app' "$DBX_CONFIG_APP_SECRET"
  assert_igual 'token-refresh' "$DBX_CONFIG_REFRESH_TOKEN"
  assert_igual '/backups' "$DBX_CONFIG_RAIZ_REMOTA"
}

teste_raiz_remota_com_caractere_adversarial_sobrevive() {
  # A raiz e um caminho da Dropbox e pode conter quebra de linha, aspas e
  # barra invertida. Formato de linha simples perderia isso em silencio.
  local area raiz
  raiz=$'/pasta com "aspas"\ne quebra\\barra'
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' "$raiz"
  dbx_config_carregar
  assert_igual "$raiz" "$DBX_CONFIG_RAIZ_REMOTA" 'a raiz precisa voltar byte a byte'
}

teste_segredo_com_caractere_adversarial_sobrevive() {
  local area segredo
  segredo=$'seg"redo\\com/escapes'
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' "$segredo" 'RT' '/r'
  dbx_config_carregar
  assert_igual "$segredo" "$DBX_CONFIG_APP_SECRET"
}

# ---------------------------------------------------------------------------
# Falhas: ausencia, permissao frouxa, corrupcao
# ---------------------------------------------------------------------------

teste_arquivo_inexistente_e_erro_de_configuracao() {
  local area
  area=$(_area)
  _com_xdg "$area"
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
}

teste_permissao_frouxa_e_recusada() {
  local area modo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  # 0700 NAO entra: nao ha bits para grupo nem outros, entao nao e frouxa.
  for modo in 644 640 604 660 606 666 402 601; do
    chmod "$modo" "$DBX_CONFIG_RESULTADO"
    assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
  done
  chmod 600 "$DBX_CONFIG_RESULTADO"
  assert_sucesso dbx_config_carregar
}

teste_conteudo_malformado_de_edicao_manual_e_recusado() {
  local area ruim
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  for ruim in '{"app_key":"AK"' 'nao e json' '' '{}' '{"app_key":"AK","app_secret":"AS"}' \
    '[1,2,3]' '{"app_key":123,"app_secret":"AS","refresh_token":"RT","raiz_remota":"/r"}'; do
    printf '%s' "$ruim" >"$DBX_CONFIG_RESULTADO"
    chmod 600 "$DBX_CONFIG_RESULTADO"
    assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
  done
}

teste_arquivo_truncado_e_recusado() {
  local area conteudo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  conteudo=$(cat "$DBX_CONFIG_RESULTADO")
  printf '%s' "${conteudo:0:$((${#conteudo} / 2))}" >"$DBX_CONFIG_RESULTADO"
  chmod 600 "$DBX_CONFIG_RESULTADO"
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
}

teste_falha_de_leitura_nao_deixa_credencial_residual() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT-ANTIGO' '/r'
  dbx_config_carregar
  printf '%s' 'corrompido' >"$DBX_CONFIG_RESULTADO"
  chmod 600 "$DBX_CONFIG_RESULTADO"
  dbx_config_carregar 2>/dev/null
  assert_igual '' "$DBX_CONFIG_REFRESH_TOKEN" \
    'credencial de carga anterior nao pode sobreviver a uma falha'
}

# ---------------------------------------------------------------------------
# Segredo nunca em diagnostico (RNF-03)
# ---------------------------------------------------------------------------

teste_nenhuma_falha_ecoa_o_segredo() {
  local area saida
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS9pQrSecretoTotal' 'RT9pQrSecretoTotal' '/r'
  chmod 644 "$DBX_CONFIG_RESULTADO"
  saida=$(dbx_config_carregar 2>&1 || true)
  assert_nao_contem 'AS9pQrSecretoTotal' "$saida"
  assert_nao_contem 'RT9pQrSecretoTotal' "$saida"
}

teste_formato_do_arquivo_e_coberto_pela_redacao() {
  # Verificacao de composicao: o formato escolhido precisa ser redigivel pela
  # taxonomia ja existente, senao um corpo de diagnostico que cite o arquivo
  # vazaria o segredo.
  local area conteudo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK9pQr' 'AS9pQrSecreto' 'RT9pQrSecreto' '/r'
  conteudo=$(cat "$DBX_CONFIG_RESULTADO")
  dbx_errors_redigir "$conteudo" >/dev/null
  assert_nao_contem 'AS9pQrSecreto' "$DBX_ERRORS_REDIGIDO"
  assert_nao_contem 'RT9pQrSecreto' "$DBX_ERRORS_REDIGIDO"
  assert_nao_contem 'AK9pQr' "$DBX_ERRORS_REDIGIDO"
}

teste_carregar_usa_contexto_proprio_e_nao_destroi_documento_em_curso() {
  # Composicao: lib/config le por lib/json. Usar o contexto padrao destruiria
  # uma listagem em curso — exatamente o que o contexto nomeado existe para
  # impedir.
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  dbx_json_contexto padrao
  dbx_json_analisar '{"entries":[{"name":"a.txt"}],"cursor":"XYZ"}'
  dbx_config_carregar
  dbx_json_valor cursor >/dev/null
  assert_igual 'XYZ' "$DBX_JSON_RESULTADO" 'a listagem em curso precisa sobreviver'
}

# ---------------------------------------------------------------------------
# P3-01 — interrupcao nao pode deixar o segredo em orfao
# ---------------------------------------------------------------------------

teste_interrupcao_nao_deixa_orfao_com_segredo() {
  local area orfaos
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  # Simula o residuo que um SIGKILL deixaria: temporario de processo ja morto.
  printf '{"refresh_token":"RT-VAZADO"}' >"$area/config/dbx/.credencial.999999.AbCdEfGh"
  chmod 600 "$area/config/dbx/.credencial.999999.AbCdEfGh"
  dbx_config_gravar 'AK2' 'AS2' 'RT2' '/r2'
  orfaos=$(find "$area/config/dbx" -mindepth 1 ! -name 'credencial.json' 2>/dev/null)
  assert_igual '' "$orfaos" \
    'temporario de processo morto contem o segredo e precisa ser removido'
}

teste_orfao_com_identificador_de_processo_vivo_e_removido_por_idade() {
  # A varredura por processo e PROBABILISTICA: basta nomear o temporario com o
  # identificador de um processo vivo qualquer para ele sobreviver, e com
  # reciclagem de identificadores o orfao vira permanente (R2-03).
  local area antigo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  antigo="$area/config/dbx/.credencial.$$.AnTiGo01"
  printf '{"refresh_token":"RT-VAZADO"}' >"$antigo"
  touch -d '2 hours ago' "$antigo"
  _dbx_config_varrer_orfaos "$area/config/dbx"
  assert_arquivo_ausente "$antigo" \
    'temporario antigo e orfao mesmo que o identificador pertenca a processo vivo'
}

teste_varredura_nao_remove_temporario_de_processo_vivo() {
  # A varredura nao pode quebrar gravacao concorrente: 10 gravacoes simultaneas
  # ja foram verificadas sem orfaos, e apagar o temporario alheio destruiria
  # justamente essa propriedade.
  local area vivo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  vivo="$area/config/dbx/.credencial.$$.ZzZzZzZz"
  printf 'em andamento' >"$vivo"
  _dbx_config_varrer_orfaos "$area/config/dbx"
  assert_arquivo_existe "$vivo" \
    'temporario de processo vivo pertence a uma gravacao em andamento'
  rm -f "$vivo"
}

# ---------------------------------------------------------------------------
# P3-03 e P3-04 — permissao mais restritiva e permissao do diretorio
# ---------------------------------------------------------------------------

teste_permissao_mais_restritiva_que_0600_e_aceita() {
  # Mesmo principio ja aplicado ao diretorio: nao desfazer escolha mais
  # restritiva do operador.
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  chmod 400 "$DBX_CONFIG_RESULTADO"
  assert_sucesso dbx_config_carregar
  assert_igual 'RT' "$DBX_CONFIG_REFRESH_TOKEN"
}

teste_permissao_sem_leitura_para_o_dono_e_recusada() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  chmod 200 "$DBX_CONFIG_RESULTADO"
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
  chmod 600 "$DBX_CONFIG_RESULTADO"
}

teste_diretorio_acessivel_a_terceiros_e_recusado() {
  local area modo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  for modo in 777 755 750 707 701; do
    chmod "$modo" "$area/config/dbx"
    assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
  done
  chmod 700 "$area/config/dbx"
  assert_sucesso dbx_config_carregar
}


# ---------------------------------------------------------------------------
# Cadeia vazia e campo incompleto (RF-51e)
# ---------------------------------------------------------------------------

teste_refresh_token_vazio_e_credencial_incompleta() {
  # Descoberto ao implementar `unlink --manter-aplicativo`: o arquivo resultante
  # passava como credencial VALIDA e a recusa so aparecia em `dbx_auth_renovar`,
  # como `uso_invalido` (2). RF-51(e) exige `3`, e a diferenca e operacional:
  # `2` manda revisar a linha de comando, `3` manda reconfigurar.
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' '' '/r'
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
}

teste_app_key_vazia_e_credencial_incompleta() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar '' 'AS' 'RT' '/r'
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
}

teste_segredo_opcional_nao_torna_a_credencial_incompleta() {
  # Aplicativo sem segredo e legitimo, e `dbx_auth_renovar` ja o trata como
  # opcional. Sem este caso, a regra acima poderia ser endurecida ate proibir
  # configuracao valida sem que nada reprovasse.
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' '' 'RT' ''
  assert_sucesso dbx_config_carregar
}

teste_nenhum_modo_de_falha_deixa_o_refresh_token_num_canal_global() {
  # ESCOPO: os modos de falha de leitura que existem, e nao um deles.
  #
  # HONESTIDADE SOBRE O QUE ESTE CASO PROVA. Ele NAO discrimina a ausencia da
  # limpeza: medido, nenhum destes modos deixaria o segredo no canal mesmo sem
  # ela, porque `refresh_token` e o terceiro campo e o quarto sobrescreve o
  # canal. A propriedade valia POR ORDEM DE CAMPO. Quem protege a propriedade e
  # a auditoria de saida unica, logo abaixo; este caso e a verificacao de dado
  # que a acompanha, e vale pelo que verifica: hoje nao vaza.
  local area corpo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  for corpo in \
    '{"versao":1,"app_key":"AK","app_secret":"AS","refresh_token":"RT_segredo_do_caso"}' \
    '{"versao":1,"app_key":"AK","app_secret":"AS","refresh_token":"RT_segredo_do_caso","raiz_remota":7}' \
    '{"versao":1,"app_key":"AK","app_secret":"AS","refresh_token":"RT_segredo_do_caso","raiz_remota":null}' \
    '{"versao":1,"app_key":"","app_secret":"AS","refresh_token":"RT_segredo_do_caso","raiz_remota":"/r"}'; do
    printf '%s' "$corpo" >"$DBX_CONFIG_RESULTADO"
    chmod 600 "$DBX_CONFIG_RESULTADO"
    dbx_config_carregar 2>/dev/null
    assert_segredo_ausente 'RT_segredo_do_caso' "${DBX_JSON_RESULTADO:-}" \
      'refresh token nao pode sobreviver no canal do analisador apos falha de leitura'
    assert_segredo_ausente 'RT_segredo_do_caso' "${DBX_CONFIG_REFRESH_TOKEN:-}" \
      'refresh token nao pode sobreviver no canal do componente apos falha de leitura'
  done
}

_saidas_do_bloco_de_analise() { # <arquivo>
  # Conta os pontos que devolvem o contexto do analisador. Com saida unica ha
  # exatamente um, dentro do encerrador; qualquer outro e um caminho novo que
  # nao passa pela limpeza.
  _harness_contar 'dbx_json_descartar config' "$1"
}

teste_o_bloco_de_analise_tem_saida_unica() {
  # RSK-27: a propriedade acima nao e garantida por dado, e sim por estrutura.
  # Esta e a auditoria que a garante, e o par de discriminacao esta no caso
  # seguinte.
  local saidas
  saidas=$(_saidas_do_bloco_de_analise "$DBX_HARNESS_RAIZ/lib/config.sh")
  assert_igual 1 "$saidas" \
    'o bloco de analise precisa ter uma saida so, para a limpeza nao depender de qual campo falhou'
}

teste_a_auditoria_de_saida_unica_detecta_caminho_novo() {
  local amostra saidas
  amostra=$(mktemp "$DBX_TESTES_TMP/saida.XXXXXX")
  {
    printf '%s\n' 'f() {'
    printf '%s\n' '  dbx_json_descartar config'
    printf '%s\n' '  if ! algo; then'
    printf '%s\n' '    dbx_json_descartar config'
    printf '%s\n' '  fi'
    printf '%s\n' '}'
  } >"$amostra"
  saidas=$(_saidas_do_bloco_de_analise "$amostra")
  rm -f "$amostra"
  assert_igual 2 "$saidas" \
    'saida acrescentada fora do encerrador precisa ser vista pela auditoria'
}

# ---------------------------------------------------------------------------
# Remocao (RF-51 b, c)
# ---------------------------------------------------------------------------

teste_remocao_integral_apaga_o_arquivo() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  assert_sucesso dbx_config_remover integral
  assert_arquivo_ausente "$DBX_CONFIG_RESULTADO" 'a remocao integral apaga o arquivo'
}

teste_remocao_integral_leva_junto_temporario_orfao() {
  # O temporario abandonado por interrupcao CONTEM O SEGREDO. Remover so o
  # arquivo final deixaria em disco exatamente o que o desvinculo elimina.
  local area diretorio orfao restos
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  diretorio=${DBX_CONFIG_RESULTADO%/*}
  orfao="$diretorio/.credencial.999999.ABCDEFGH"
  printf '%s' '{"refresh_token":"RT"}' >"$orfao"
  dbx_config_remover integral
  # Sem substituicao de comando na montagem da massa: o vetor recebe a expansao
  # do proprio shell e a cadeia e montada por `printf -v`.
  local -a achados=("$diretorio"/.credencial.*)
  printf -v restos '%s ' "${achados[@]}"
  assert_nao_contem 'ABCDEFGH' "$restos" 'temporario orfao precisa sair junto'
}

teste_remocao_de_aplicativo_preserva_a_chave_e_invalida_o_vinculo() {
  local area conteudo
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK_preservada' 'AS_preservado' 'RT_a_descartar' '/r'
  dbx_config_carregar
  assert_sucesso dbx_config_remover aplicativo
  assert_arquivo_existe "$DBX_CONFIG_RESULTADO" 'o modo aplicativo mantem o arquivo'
  IFS= read -r -d '' conteudo <"$DBX_CONFIG_RESULTADO"
  assert_contem 'AK_preservada' "$conteudo" 'a chave do aplicativo e preservada'
  assert_segredo_ausente 'RT_a_descartar' "$conteudo" \
    'o refresh token nao pode sobreviver ao desvinculo'
  # E o ponto de RF-51(e): o que sobra NAO e credencial utilizavel.
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_carregar
}

teste_remocao_de_aplicativo_sem_credencial_carregada_e_recusada() {
  local area
  area=$(_area)
  _com_xdg "$area"
  dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  _dbx_config_limpar_credencial
  assert_status "$DBX_CONFIG_ERRO_CONFIGURACAO" dbx_config_remover aplicativo
}

teste_modo_de_remocao_fora_do_vocabulario_e_recusado() {
  local area
  area=$(_area)
  _com_xdg "$area"
  assert_status "$DBX_CONFIG_ERRO_USO" dbx_config_remover quase_integral
}

# ---------------------------------------------------------------------------
# Caminho do estado (DP-23) — separado da configuracao de proposito
# ---------------------------------------------------------------------------

teste_caminho_de_estado_usa_xdg_state_e_nao_o_de_configuracao() {
  local area
  area=$(_area)
  _com_xdg "$area"
  XDG_STATE_HOME="$area/estado" dbx_config_caminho_de_estado
  assert_igual "$area/estado/dbx" "$DBX_CONFIG_RESULTADO" 'DP-23: estado sob XDG_STATE_HOME'
  # A separacao e o ponto: descartar estado nao pode arrastar credencial.
  dbx_config_caminho
  assert_diferente "$area/estado/dbx" "${DBX_CONFIG_RESULTADO%/*}" \
    'estado e configuracao nao podem morar no mesmo diretorio'
}

teste_caminho_de_estado_recusa_base_relativa() {
  XDG_STATE_HOME='estado/relativo' dbx_config_caminho_de_estado
  assert_igual "$DBX_CONFIG_ERRO_CONFIGURACAO" $? \
    'base relativa mudaria o alvo conforme o diretorio corrente'
}

harness_executar "$@"
