#!/usr/bin/env bash
# Testes de lib/preflight.sh — verificacao de ambiente e dependencias.
#
# A classe de erro para dependencia ausente e `configuracao` (3): a proposta de
# um codigo 16 dedicado foi REJEITADA, e a mensagem de `configuracao` foi
# reescrita para nao presumir credencial.

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a "bash -c", que precisa chegar
# sem expansao ao processo filho.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/preflight.sh"

_area() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/preflight.XXXXXX") || return 1
  (cd -P -- "$dir" && pwd -P)
}

# _sem <utilitario...> — cria um PATH em que os utilitarios indicados nao existem
_sem() {
  local -a ausentes=("$@")
  local dir alvo faltante
  dir=$(_area)/bin
  mkdir -p "$dir"
  # `timeout` e os utilitarios usados pela propria sonda precisam existir no
  # PATH reduzido, senao a sonda mede a si mesma em vez do componente.
  for alvo in bash curl sha256sum shasum openssl timeout env head wc mktemp stat \
    readlink find tr grep cat chmod mv rm mkdir dirname basename sed seq awk od; do
    for faltante in "${ausentes[@]}"; do
      [[ $alvo == "$faltante" ]] && continue 2
    done
    local origem
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -sf "$origem" "$dir/$alvo"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Contrato de status
# ---------------------------------------------------------------------------

teste_status_segue_a_taxonomia_de_erro() {
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_PREFLIGHT_ERRO_CONFIGURACAO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_PREFLIGHT_ERRO_USO"
}

teste_ambiente_saudavel_e_aprovado() {
  assert_sucesso dbx_preflight_verificar
  assert_igual '' "$DBX_PREFLIGHT_MOTIVO"
}

# ---------------------------------------------------------------------------
# Dependencias externas: apenas cURL e utilitario de resumo (DP-08)
# ---------------------------------------------------------------------------

teste_curl_ausente_e_recusado_nomeando_o_utilitario() {
  local caminho status saida
  caminho=$(_sem curl)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar 2>&1
    printf "|%s|%s|%s" "$?" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  status=${saida#*|}
  status=${status%%|*}
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$status"
  assert_contem 'curl' "$saida" 'RNF-02 exige nomear o utilitario ausente'
}

teste_utilitario_de_resumo_ausente_e_recusado() {
  local caminho saida
  # Precisa remover TODOS: lib/hash aceita mais de um utilitario de resumo, e
  # deixar um deles no PATH faria a sonda medir outra coisa.
  caminho=$(_sem sha256sum shasum openssl)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar 2>&1
    printf "|%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem "|$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$saida" \
    'sem utilitario de resumo nao ha content_hash, e RF-34 fica inviavel'
}

teste_jq_nao_e_exigido() {
  # DP-08: dependencia externa unica e o cURL. Exigir jq contrariaria a decisao.
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/preflight.sh" |
    grep -nE '(^|[^_a-zA-Z.])jq([^_a-zA-Z]|$)' || true)
  assert_igual '' "$achados" "preflight exige jq: $achados"
}

teste_camada_de_compatibilidade_nao_foi_reintroduzida() {
  # DP-07 fixou Linux; a camada GNU/BSD saiu do desenho. Detectar variante de
  # sistema aqui traria de volta o que a decisao removeu.
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/preflight.sh" |
    grep -nEi '(uname|darwin|bsd|freebsd|macos)' || true)
  assert_igual '' "$achados" "deteccao de plataforma reintroduzida: $achados"
}

# ---------------------------------------------------------------------------
# Piso de bash 4.4 (DP-07, RNF-01 descongelado)
# ---------------------------------------------------------------------------

teste_versao_de_bash_abaixo_do_piso_e_recusada() {
  local saida
  saida=$(timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_versao_de_bash_suficiente 4 1 && printf "aceitou-4.1"
    dbx_preflight_versao_de_bash_suficiente 3 2 && printf "aceitou-3.2"
    dbx_preflight_versao_de_bash_suficiente 4 3 && printf "aceitou-4.3"
    dbx_preflight_versao_de_bash_suficiente 4 4 || printf "recusou-4.4"
    dbx_preflight_versao_de_bash_suficiente 5 3 || printf "recusou-5.3"
    printf "ok"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual 'ok' "$saida" \
    'o piso e 4.4: RHEL 6 com 4.1 fica fora, e 4.3 nao tem nameref'
}

teste_piso_declarado_e_o_verificado() {
  assert_igual '4' "$DBX_PREFLIGHT_BASH_MAIOR"
  assert_igual '4' "$DBX_PREFLIGHT_BASH_MENOR"
}

# ---------------------------------------------------------------------------
# Area temporaria
# ---------------------------------------------------------------------------

teste_area_temporaria_inexistente_e_recusada() {
  local saida
  saida=$(TMPDIR=/caminho/que/nao/existe timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s|%s|%s" "$?" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|" "$saida"
  assert_contem 'temporaria' "$saida" 'o motivo precisa apontar o host, nao a Dropbox'
}

teste_area_temporaria_somente_leitura_e_recusada() {
  local area saida
  area=$(_area)/somente_leitura
  mkdir -p "$area"
  chmod 500 "$area"
  saida=$(TMPDIR="$area" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  chmod 700 "$area"
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$saida" \
    'sem escrita em area temporaria o envio em partes fica inviavel'
}

# ---------------------------------------------------------------------------
# Diretorio de configuracao (RNF-04)
# ---------------------------------------------------------------------------

teste_xdg_invalido_e_recusado() {
  local saida
  saida=$(XDG_CONFIG_HOME='relativo' timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$saida"
}

teste_permissao_da_credencial_e_verificada_no_preflight() {
  # DP-11 exige a verificacao AQUI, e nao apenas na leitura.
  local area saida
  area=$(_area)
  mkdir -p "$area/config/dbx"
  printf '{}' >"$area/config/dbx/credencial.json"
  chmod 644 "$area/config/dbx/credencial.json"
  saida=$(XDG_CONFIG_HOME="$area/config" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s|%s|%s" "$?" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|" "$saida"
  assert_contem 'permissao' "$saida"
}

teste_credencial_ausente_nao_reprova_o_preflight() {
  # Ambiente sem credencial e o estado normal antes da configuracao inicial: o
  # preflight verifica o AMBIENTE, e quem exige credencial e o comando.
  local area
  area=$(_area)
  XDG_CONFIG_HOME="$area/config" assert_sucesso dbx_preflight_verificar
}

# ---------------------------------------------------------------------------
# Diagnostico nao vaza segredo
# ---------------------------------------------------------------------------

teste_diagnostico_do_preflight_nao_ecoa_conteudo_da_credencial() {
  local area saida
  area=$(_area)
  mkdir -p "$area/config/dbx"
  printf '{"refresh_token":"RT9pQrSecretoTotal"}' >"$area/config/dbx/credencial.json"
  chmod 644 "$area/config/dbx/credencial.json"
  saida=$(XDG_CONFIG_HOME="$area/config" dbx_preflight_verificar 2>&1 || true)
  assert_nao_contem 'RT9pQrSecretoTotal' "$saida"
}

# ---------------------------------------------------------------------------
# P3-02 — RNF-02 exige NOMEAR o utilitario ausente, para todos eles
# ---------------------------------------------------------------------------

teste_todo_utilitario_ausente_reprova_e_e_nomeado() {
  local utilitario caminho saida
  for utilitario in mktemp mv rm chmod mkdir stat head wc readlink dirname; do
    caminho=$(_sem "$utilitario")
    saida=$(PATH="$caminho" timeout 30 bash -c '
      . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
      dbx_preflight_verificar >/dev/null 2>&1
      printf "%s|%s" "$?" "$DBX_PREFLIGHT_DETALHE"
    ' _ "$DBX_HARNESS_RAIZ" 2>&1)
    assert_contem "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|" "$saida" \
      "ambiente sem $utilitario foi aprovado pelo preflight"
    assert_contem "$utilitario" "$saida" \
      "RNF-02 exige nomear o utilitario ausente: $utilitario"
  done
}

teste_lista_do_preflight_cobre_o_que_a_biblioteca_invoca() {
  # Pergunta dos gemeos, transformada em auditoria: se a biblioteca passar a
  # invocar um utilitario novo, o preflight precisa passar a exigi-lo, senao
  # volta a aprovar ambiente onde a primeira operacao falha.
  local invocados utilitario nao_exigidos=''
  invocados=$(grep -vhE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ"/lib/*.sh |
    grep -ohE '(^|[^-_a-zA-Z/.])(mktemp|mv|rm|chmod|mkdir|stat|head|wc|readlink|dirname|basename|cat|cp|ln|find|tr|sed|awk|curl)([^-_a-zA-Z]|$)' |
    grep -ohE '(mktemp|mv|rm|chmod|mkdir|stat|head|wc|readlink|dirname|basename|cat|cp|ln|find|tr|sed|awk|curl)' |
    sort -u)
  for utilitario in $invocados; do
    case " $DBX_PREFLIGHT_UTILITARIOS " in
      *" $utilitario "*) ;;
      *) nao_exigidos+=" $utilitario" ;;
    esac
  done
  assert_igual '' "$nao_exigidos" \
    "utilitarios invocados por lib/ e nao exigidos pelo preflight:$nao_exigidos"
}

harness_executar "$@"
