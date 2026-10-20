#!/usr/bin/env bash
# Testes diretos de lib/compartilhamento.sh (fase 5; RF-85 a RF-89; DIV-104 a
# DIV-120), da leitura sem eco de lib/cli (DIV-117) e das tags e da chave
# sensivel novas de lib/errors (RF-90(a), DIV-111; TC-SHE-01, TC-SNH-11).
#
# `lib/compartilhamento` e puro: sem rede e sem estado. As validacoes que
# decidem antes da rede (visibilidade, `--expira`, URL, senha) e a montagem do
# corpo sao provadas aqui, por unidade; `tests/integracao/compartilhar_test`
# prova a ligacao com os comandos e o duble de `curl`.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/cli.sh"
. "$DBX_HARNESS_RAIZ/lib/compartilhamento.sh"

USO=$(dbx_errors_codigo_saida uso_invalido)
readonly USO
readonly SENHA_SENTINELA='SENHA_SENTINELA_q7w8e9'

_agora() { printf -v AGORA '%(%s)T' -1; }
_carimbo() { # <epoca> — UTC, pelo proprio shell
  local TZ=UTC
  printf -v CARIMBO '%(%Y-%m-%dT%H:%M:%SZ)T' "$1"
}

# ===========================================================================
# --expira (RF-85(e), DIV-113)
# ===========================================================================

teste_cmp05_expira_datas_e_duracoes_validas_viram_expires_normalizado() {
  dbx_compartilhamento_validar_expira --expira 2099-12-31 ||
    _harness_falhar "data recusada: $DBX_COMPARTILHAMENTO_MOTIVO"
  assert_igual 2099-12-31T23:59:59Z "$DBX_COMPARTILHAMENTO_EXPIRA" 'dia sozinho vale o fim do dia UTC'
  dbx_compartilhamento_validar_expira --expires 2099-12-31T10:00:00Z ||
    _harness_falhar 'carimbo recusado'
  assert_igual 2099-12-31T10:00:00Z "$DBX_COMPARTILHAMENTO_EXPIRA" 'carimbo UTC como veio'
  local antes depois
  _agora
  antes=$AGORA
  dbx_compartilhamento_validar_expira --expira 7d || _harness_falhar 'duracao 7d recusada'
  _agora
  depois=$AGORA
  _carimbo $((antes + 7 * 86400))
  local minimo=$CARIMBO
  _carimbo $((depois + 7 * 86400))
  [[ ! $DBX_COMPARTILHAMENTO_EXPIRA < $minimo && ! $DBX_COMPARTILHAMENTO_EXPIRA > $CARIMBO ]] ||
    _harness_falhar '7d = agora + 7 dias, em UTC' "$minimo <= $DBX_COMPARTILHAMENTO_EXPIRA <= $CARIMBO"
  dbx_compartilhamento_validar_expira --expira 48h || _harness_falhar 'duracao 48h recusada'
  _carimbo $((antes + 48 * 3600))
  [[ ! $DBX_COMPARTILHAMENTO_EXPIRA < $CARIMBO ]] || _harness_falhar '48h = agora + 48 horas'
  dbx_compartilhamento_validar_expira --expira 8760h || _harness_falhar 'teto de horas aceito'
  dbx_compartilhamento_validar_expira --expira 3650d || _harness_falhar 'teto de dias aceito'
}

teste_cmp06_expira_invalidas_sao_uso_invalido() {
  local valor estado
  for valor in 2099-02-30 2099-13-01 '2099-12-31T10:00:00+03:00' '2099-12-31T10:00:00.5Z' \
    0d 07d 3651d 8761h 0h 1w 1D '' '-1d' '+1d' ' 1d' 'amanha' '2099-12-31 ' $'1d\n'; do
    dbx_compartilhamento_validar_expira --expira "$valor"
    estado=$?
    assert_igual "$USO" "$estado" "--expira [$valor] e uso invalido"
    assert_contem '--expira' "$DBX_COMPARTILHAMENTO_MOTIVO" 'a mensagem nomeia a opcao'
    assert_igual '' "$DBX_COMPARTILHAMENTO_EXPIRA" 'nada normalizado na recusa'
  done
}

teste_cmp07_expira_no_passado_ou_a_menos_de_60s_e_recusada() {
  local estado
  dbx_compartilhamento_validar_expira --expira 2000-01-01
  estado=$?
  assert_igual "$USO" "$estado" 'passado'
  assert_contem 'a expiracao precisa estar no futuro' "$DBX_COMPARTILHAMENTO_MOTIVO" 'mensagem'
  _agora
  _carimbo $((AGORA + 30))
  dbx_compartilhamento_validar_expira --expira "$CARIMBO"
  estado=$?
  assert_igual "$USO" "$estado" 'menos de 60 s no futuro'
  _carimbo $((AGORA + 600))
  dbx_compartilhamento_validar_expira --expira "$CARIMBO" || _harness_falhar 'dez minutos no futuro e aceito'
}

# ===========================================================================
# Senha (RF-86(d), DIV-109)
# ===========================================================================

teste_snh05_06_senha_vazia_controle_longa_ou_utf8_invalido_sao_recusadas_sem_citar() {
  local valor estado longa
  printf -v longa '%*s' 1025 ''
  longa=${longa// /a}
  for valor in '' "${SENHA_SENTINELA}"$'\r' "${SENHA_SENTINELA}"$'\001' "${SENHA_SENTINELA}"$'\177' \
    "${SENHA_SENTINELA}"$'\t' "$longa" "${SENHA_SENTINELA}"$'\xc3' "${SENHA_SENTINELA}"$'\xed\xa0\x80'; do
    dbx_compartilhamento_validar_senha "$valor"
    estado=$?
    assert_igual "$USO" "$estado" "senha recusada (${#valor} bytes)"
    assert_diferente '' "$DBX_COMPARTILHAMENTO_MOTIVO" 'com motivo'
    assert_segredo_ausente "$SENHA_SENTINELA" "$DBX_COMPARTILHAMENTO_MOTIVO" 'o motivo nao cita a senha'
  done
  dbx_compartilhamento_validar_senha ''
  assert_contem 'senha vazia recusada' "$DBX_COMPARTILHAMENTO_MOTIVO" 'vazia'
  dbx_compartilhamento_validar_senha "x"$'\r'
  assert_contem 'CRLF' "$DBX_COMPARTILHAMENTO_MOTIVO" 'o CRLF e nomeado'
}

teste_snh14_senha_com_aspa_barra_espaco_e_acento_e_aceita() {
  local longa
  dbx_compartilhamento_validar_senha 'a"b\c d ação 😀' || _harness_falhar "recusada: $DBX_COMPARTILHAMENTO_MOTIVO"
  printf -v longa '%*s' 1024 ''
  dbx_compartilhamento_validar_senha "${longa// /a}" || _harness_falhar '1024 bytes e o teto, aceito'
  # 1024 bytes em caracteres de dois bytes: 512 caracteres.
  longa=${longa:0:512}
  dbx_compartilhamento_validar_senha "${longa// /ç}" || _harness_falhar 'medido em bytes, nao em caracteres'
  longa="${longa// /ç}a"
  dbx_compartilhamento_validar_senha "$longa" && _harness_falhar '1025 bytes recusado mesmo com acento'
  return 0
}

# ===========================================================================
# Corpo e settings (RF-85(c), RF-86(e), DIV-112)
# ===========================================================================

teste_cmp02_03_corpo_publico_e_equipe_usam_audience_sem_campo_depreciado() {
  local corpo=''
  dbx_compartilhamento_corpo corpo path /docs/a.txt publico ''
  assert_igual '{"path":"/docs/a.txt","settings":{"audience":"public","require_password":false}}' "$corpo" 'publico'
  dbx_compartilhamento_corpo corpo path /docs/a.txt equipe 2099-12-31T23:59:59Z
  assert_igual '{"path":"/docs/a.txt","settings":{"audience":"team","require_password":false,"expires":"2099-12-31T23:59:59Z"}}' \
    "$corpo" 'equipe com expiracao'
  assert_nao_contem 'requested_visibility' "$corpo" 'nunca o campo depreciado'
  dbx_compartilhamento_corpo corpo url 'https://www.dropbox.com/s/x/a"b' publico ''
  assert_contem '"url":"https://www.dropbox.com/s/x/a\"b"' "$corpo" 'alvo por url, escapado'
}

teste_snh14_corpo_com_senha_e_json_valido_com_o_valor_identico() {
  local corpo='' senha="${SENHA_SENTINELA}"' a"b\c ação'
  dbx_compartilhamento_corpo corpo path /docs/a.txt senha '' senha
  assert_contem '"audience":"public","require_password":true,"link_password":' "$corpo" 'senha mapeada'
  assert_igual '' "${DBX_JSON_ESCAPADO:-}" 'o canal de escape nao retem a senha'
  dbx_json_contexto teste_senha
  dbx_json_analisar "$corpo" || _harness_falhar "corpo nao e JSON valido: $DBX_JSON_MOTIVO"
  dbx_json_valor settings link_password >/dev/null || _harness_falhar 'sem link_password'
  [[ $DBX_JSON_RESULTADO == "$senha" ]] || _harness_falhar 'o valor serializado difere da senha'
  dbx_json_descartar teste_senha
  DBX_JSON_RESULTADO=''
}

teste_visibilidade_esperada_e_a_resolvida_da_api() {
  dbx_compartilhamento_visibilidade_esperada publico
  assert_igual public "$DBX_COMPARTILHAMENTO_ESPERADA" 'publico'
  dbx_compartilhamento_visibilidade_esperada equipe
  assert_igual team_only "$DBX_COMPARTILHAMENTO_ESPERADA" 'equipe (ResolvedVisibility.team_only)'
  dbx_compartilhamento_visibilidade_esperada senha
  assert_igual password "$DBX_COMPARTILHAMENTO_ESPERADA" 'senha'
}

teste_lex10_exposicao_ampliada_e_detectada() {
  dbx_compartilhamento_exposicao team_only nao '' public nao ''
  assert_contem 'visibilidade team_only -> public' "$DBX_COMPARTILHAMENTO_EXPOSICAO" 'equipe para publico'
  dbx_compartilhamento_exposicao password sim '' public nao ''
  assert_contem 'senha sim -> nao' "$DBX_COMPARTILHAMENTO_EXPOSICAO" 'sem senha'
  dbx_compartilhamento_exposicao public nao 2099-01-01T00:00:00Z public nao 2099-06-01T00:00:00Z
  assert_contem 'expira 2099-01-01T00:00:00Z -> 2099-06-01T00:00:00Z' "$DBX_COMPARTILHAMENTO_EXPOSICAO" 'mais tarde'
  dbx_compartilhamento_exposicao public nao 2099-06-01T00:00:00Z public nao 2099-01-01T00:00:00Z
  assert_igual '' "$DBX_COMPARTILHAMENTO_EXPOSICAO" 'mais cedo reduz'
  dbx_compartilhamento_exposicao public nao '' team_only nao ''
  assert_igual '' "$DBX_COMPARTILHAMENTO_EXPOSICAO" 'publico para equipe reduz'
}

# ===========================================================================
# URL do --revogar (RF-89(b), DIV-114)
# ===========================================================================

teste_rvg06_urls_validas_sao_aceitas() {
  local url
  for url in 'https://www.dropbox.com/s/abc123/a.txt?dl=0' 'https://dropbox.com/sh/abc/def' \
    'https://www.dropbox.com/scl/fi/xyz/a.txt?rlkey=k&dl=0' 'https://www.dropbox.com/scl/fo/xyz/k'; do
    dbx_compartilhamento_validar_url "$url" || _harness_falhar "url valida recusada: $url ($DBX_COMPARTILHAMENTO_MOTIVO)"
  done
}

teste_rvg06_07_urls_invalidas_e_link_temporario_sao_recusados() {
  local url estado longa
  printf -v longa '%*s' 2040 ''
  for url in 'http://www.dropbox.com/s/abc' 'https://www.dropbox.com.evil/s/abc' 'https://evil.com/s/abc' \
    'https://user@www.dropbox.com/s/abc' 'https://www.dropbox.com:443/s/abc' 'https://www.dropbox.com/s/a b' \
    $'https://www.dropbox.com/s/a\nb' 'https://www.dropbox.com/x/abc' 'https://www.dropbox.com/' '' \
    "https://www.dropbox.com/s/${longa// /a}" 'ftp://www.dropbox.com/s/abc' 'https://WWW.DROPBOX.COM/s/abc'; do
    dbx_compartilhamento_validar_url "$url"
    estado=$?
    assert_igual "$USO" "$estado" "url recusada: [$url]"
    assert_nao_contem '/s/' "$DBX_COMPARTILHAMENTO_MOTIVO" 'a mensagem cita so esquema e host'
  done
  dbx_compartilhamento_validar_url 'https://dl.dropboxusercontent.com/apitl/1/AAA'
  estado=$?
  assert_igual "$USO" "$estado" 'link temporario'
  assert_contem 'link temporario nao pode ser revogado; ele expira em 4 horas' "$DBX_COMPARTILHAMENTO_MOTIVO" 'mensagem'
}

# ===========================================================================
# Confinamento por path_lower (RF-88(c), RF-89(c), DIV-118)
# ===========================================================================

teste_lst04_05_rvg12_confinamento_por_componente_e_dobra_so_ascii() {
  dbx_compartilhamento_confinado /raiz/a /raiz || _harness_falhar '/raiz/a dentro de /raiz'
  dbx_compartilhamento_confinado /raiz /raiz || _harness_falhar 'a propria raiz esta dentro'
  dbx_compartilhamento_confinado /raizx/a /raiz && _harness_falhar '/raizX fora de /raiz'
  dbx_compartilhamento_confinado /raiz/a /Raiz || _harness_falhar 'caixa ASCII dobrada'
  dbx_compartilhamento_confinado '/ação/x' '/AÇÃO' && _harness_falhar 'caixa fora do ASCII: falha fechada'
  dbx_compartilhamento_confinado '' / && _harness_falhar 'path_lower ausente nunca e confinado, nem com raiz /'
  dbx_compartilhamento_confinado 'relativo/a' / && _harness_falhar 'relativo e fora'
  dbx_compartilhamento_confinado /raiz/ab/x /raiz /raiz/a && _harness_falhar '/raiz/ab nao esta em /raiz/a'
  dbx_compartilhamento_confinado /raiz/a/x /raiz /raiz/A || _harness_falhar 'descendente da pasta pedida'
  dbx_compartilhamento_confinado /x / || _harness_falhar 'raiz / aceita caminho presente'
  return 0
}

teste_lex03_mesmo_caminho_dobra_so_ascii() {
  dbx_compartilhamento_mesmo_caminho /Docs/A.txt /docs/a.txt || _harness_falhar 'ASCII sem caixa'
  dbx_compartilhamento_mesmo_caminho /docs /docs/a.txt && _harness_falhar 'ancestral nao e o mesmo'
  dbx_compartilhamento_mesmo_caminho '/É' '/é' && _harness_falhar 'fora do ASCII: igualdade exata'
  return 0
}

# ===========================================================================
# lib/errors (RF-90(a), DIV-111)
# ===========================================================================

teste_she01_cada_tag_nova_cai_na_classe_da_tabela_com_e_sem_qualificador() {
  local par tag classe obtida
  for par in not_authorized=permissao invalid_settings=uso_invalido shared_link_not_found=nao_encontrado \
    shared_link_access_denied=permissao shared_link_malformed=uso_invalido unsupported_link_type=uso_invalido \
    unsupported_file=uso_invalido not_allowed=permissao email_not_verified=permissao banned_member=permissao \
    too_many_shared_folders=permissao shared_link_already_exists=conflito unsupported_parameter_field=uso_invalido; do
    tag=${par%%=*} classe=${par#*=}
    obtida=$(dbx_errors_classificar 409 "$tag/..")
    assert_igual "$classe" "$obtida" "tag $tag"
    obtida=$(dbx_errors_classificar 409 "settings_error/$tag/.")
    assert_igual "$classe" "$obtida" "settings_error/$tag"
  done
  assert_igual nao_concluida "$(dbx_errors_classificar 409 'reset/..')" 'reset da listagem'
  assert_igual uso_invalido "$(dbx_errors_classificar 409 'path/not_file/..')" 'pasta no link temporario'
}

teste_snh11_link_password_e_mascarado_pela_redacao() {
  dbx_errors_redigir "{\"link_password\":\"$SENHA_SENTINELA\",\"require_password\":true}" >/dev/null
  assert_segredo_ausente "$SENHA_SENTINELA" "$DBX_ERRORS_REDIGIDO" 'link_password mascarado'
  assert_contem 'require_password' "$DBX_ERRORS_REDIGIDO" 'o booleano nao e segredo'
}

# ===========================================================================
# lib/cli: leitura sem eco em ponto unico (DIV-117)
# ===========================================================================

teste_cli_ler_oculto_preenche_a_variavel_do_chamador_e_pergunta_em_stderr() {
  local valor='' erro
  erro="$DBX_TESTES_TMP/ler_oculto.$$"
  dbx_cli_ler_oculto 'senha do link: ' valor <<<"$SENHA_SENTINELA" 2>"$erro"
  assert_igual "$SENHA_SENTINELA" "$valor" 'valor na variavel nomeada'
  assert_contem 'senha do link:' "$(<"$erro")" 'pergunta em stderr'
  assert_segredo_ausente "$SENHA_SENTINELA" "$(<"$erro")" 'sem eco do valor'
  rm -f "$erro"
}

harness_executar "$@"
