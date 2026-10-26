#!/usr/bin/env bash
# Testes ponta a ponta do `dbx diagnostico` (RF-66, TC-DIA-01..10).
#
# O comando contorna o preflight bloqueante e inspeciona tudo sem parar no
# primeiro item. Alem do relatorio, estes casos provam a seguranca (Regra 6):
# nenhum valor de credencial ou de token aparece em saida alguma, nada no
# ambiente muda e so os tres endpoints de leitura sao chamados.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly ESCOPOS='account_info.read files.metadata.read files.content.read files.content.write'
readonly SENTINELA_REFRESH='RT_SENTINELA_refresh_9f8e7d'
readonly SENTINELA_SEGREDO='AS_SENTINELA_segredo_1a2b3c'
readonly SENTINELA_CHAVE='AK_SENTINELA_chave_4d5e6f'
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_7g8h9i'

BASH_ABSOLUTO=$(command -v bash)
readonly BASH_ABSOLUTO

# _credencial <base> <app_secret> — grava a credencial com os sentinelas.
_credencial() {
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"/"}' \
    "$SENTINELA_CHAVE" "$2" "$SENTINELA_REFRESH" >"$1/config/dbx/credencial.json"
  chmod 600 "$1/config/dbx/credencial.json"
}

# _cenario — credencial valida, duplo de rede saudavel e um `bin` com todos os
# utilitarios (por vinculo), para que os casos possam tirar um deles.
_cenario() {
  local base alvo origem
  base=$(mktemp -d "$DBX_TESTES_TMP/diagnostico.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp"
  chmod 700 "$base/config/dbx"
  _credencial "$base" "$SENTINELA_SEGREDO"
  printf '{"access_token":"%s","expires_in":14400,"scope":"%s"}' "$SENTINELA_TOKEN" "$ESCOPOS" \
    >"$base/token"
  printf '%s' '{"used":100,"allocation":{".tag":"individual","allocated":1000}}' >"$base/espaco"
  for alvo in curl mktemp mv rm chmod mkdir stat head dd wc readlink dirname find cat sleep tail df ln rmdir \
    sha256sum; do
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -s "$origem" "$base/bin/$alvo"
  done
  rm -f "$base/bin/curl"
  cat >"$base/bin/curl" <<FIM
#!$BASH_ABSOLUTO
base=$base
FIM
  cat >>"$base/bin/curl" <<'FIM'
read -r -d '' _conf
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
[[ -f $base/curl_saida ]] && exit "$(cat "$base/curl_saida")"
codigo=200
case $url in
  *oauth2/token*) corpo=$(cat "$base/token") ;;
  *check/user*) corpo='{"result":"dbx"}' ;;
  *get_space_usage*) corpo=$(cat "$base/espaco") ;;
  *) corpo='{}' ;;
esac
if [[ $url == *check/user* && -f $base/check_codigo ]]; then
  codigo=$(cat "$base/check_codigo"); corpo='{"error_summary":"invalid_access_token/"}'
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...> — PATH so com o `bin` do cenario
  local base=$1
  shift
  env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    ${DBX_LOCALIDADE_DE_TESTE:+DBX_SYNC_LOCALIDADE=$DBX_LOCALIDADE_DE_TESTE} \
    "$BASH_ABSOLUTO" "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA=''
  DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_linha() { # <id> — as linhas da checagem na saida
  local linha saida=''
  while IFS= read -r linha; do
    [[ $linha == "$1="* ]] && saida+="$linha"$'\n'
  done <<<"$DBX_SAIDA"
  printf '%s' "${saida%$'\n'}"
}

_localidade_disponivel() {
  LC_ALL=C.UTF-8 "$BASH_ABSOLUTO" -c 'x=$'"'"'\xc3\x89'"'"'; [[ ${x,,} == $'"'"'\xc3\xa9'"'"' ]]' 2>/dev/null
}

_retrato() { # <diretorio>
  [[ -e $1 ]] || {
    printf 'ausente\n'
    return 0
  }
  find "$1" -printf '%P %m %s\n' | sort
  find "$1" -type f -exec cksum {} + | sort
}

# ---------------------------------------------------------------------------
# TC-DIA-01 — ambiente sao
# ---------------------------------------------------------------------------

teste_dia01_ambiente_sao_tem_todas_as_checagens_ok() {
  _localidade_disponivel || pular 'localidade C.UTF-8 ausente nesta maquina'
  local base id
  base=$(_cenario)
  _rodar "$base" diagnostico
  assert_igual 0 "$DBX_ESTADO" "ambiente sao sai com 0; diagnostico: $DBX_ERRO"
  # RF-66(a) emendado por RF-71 (v1.12): a checagem `trava` e a oitava.
  for id in dependencias credencial conectividade escopos espaco localidade estado trava; do
    assert_contem "$id=ok" "$DBX_SAIDA" "checagem $id ok"
  done
  assert_contem $'ok=8\navisos=0\nfalhas=0' "$DBX_SAIDA" 'contagens'
  _rodar "$base" doctor
  assert_igual 0 "$DBX_ESTADO" 'o alias doctor e o mesmo comando'
}

# ---------------------------------------------------------------------------
# TC-DIA-02, TC-DIA-03, TC-DIA-04 — contorno do preflight
# ---------------------------------------------------------------------------

teste_dia02_sem_stat_mktemp_readlink_roda_e_lista_cada_ausente() {
  local base mensagem_do_preflight
  base=$(_cenario)
  rm -f "$base/bin/stat" "$base/bin/mktemp" "$base/bin/readlink"
  _rodar "$base" info /x
  mensagem_do_preflight=$DBX_ERRO
  _rodar "$base" diagnostico
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'falha sai com 3'
  assert_contem 'dependencias=falha: utilitario ausente: mktemp' "$DBX_SAIDA" 'mktemp nomeado'
  assert_contem 'dependencias=falha: utilitario ausente: stat' "$DBX_SAIDA" 'stat nomeado'
  assert_contem 'dependencias=falha: utilitario ausente: readlink' "$DBX_SAIDA" 'readlink nomeado'
  assert_contem 'remedio: instale o utilitario stat' "$DBX_SAIDA" 'remedio acionavel'
  assert_nao_contem "$mensagem_do_preflight" "$DBX_ERRO" 'sem a mensagem unica do preflight'
  # O-4 (QA, RF-66(e)): sem `stat` nenhum utilitario e chamado ate o relatorio;
  # a permissao nao conferida e aviso, nunca omissao.
  assert_contem 'credencial=aviso: permissao nao conferida' "$DBX_SAIDA" 'credencial sem stat e aviso'
  assert_contem 'remedio: instale o utilitario stat' "$(_linha credencial)" 'remedio da causa'
}

teste_dia02_sem_stat_o_estado_existente_e_aviso_e_dono_e_conferido_pelo_shell() {
  local base
  base=$(_cenario)
  mkdir -p "$base/estado/dbx"
  chmod 755 "$base/estado/dbx"
  rm -f "$base/bin/stat"
  _rodar "$base" diagnostico
  assert_contem 'estado=aviso: permissao nao conferida' "$DBX_SAIDA" 'sem stat o modo nao e lido'
  assert_contem 'remedio: instale o utilitario stat' "$(_linha estado)" 'remedio da causa'
}

teste_dia03_sem_curl_as_checagens_de_rede_falham_como_nao_executadas() {
  local base id
  base=$(_cenario)
  rm -f "$base/bin/curl"
  _rodar "$base" diagnostico
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'falha sai com 3'
  assert_contem 'dependencias=falha: utilitario ausente: curl' "$DBX_SAIDA" 'curl nomeado'
  for id in conectividade escopos espaco; do
    assert_contem "$id=falha: nao executada" "$(_linha "$id")" "$id nao e omitida"
  done
  assert_contem 'remedio: instale o utilitario curl' "$(_linha conectividade)" 'remedio da causa'
}

teste_dia02_pelo_vinculo_sem_dirname_nem_readlink_ainda_roda() {
  # D-1 (QA): o ponto de entrada resolve a raiz so com o shell; pelo vinculo,
  # sem `readlink`, le o alvo por `find`.
  local base
  base=$(_cenario)
  rm -f "$base/bin/dirname" "$base/bin/readlink"
  mkdir -p "$base/instalado"
  ln -s "$DBX_EXEC" "$base/instalado/dbx"
  env -i PATH="$base/bin" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
    TMPDIR="$base/tmp" "$BASH_ABSOLUTO" "$base/instalado/dbx" diagnostico >"$base/out" 2>"$base/err"
  local estado=$?
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$estado" "roda e reprova pelas dependencias: $(cat "$base/err")"
  assert_contem 'dependencias=falha: utilitario ausente: dirname' "$(cat "$base/out")" 'dirname nomeado'
  assert_contem 'dependencias=falha: utilitario ausente: readlink' "$(cat "$base/out")" 'readlink nomeado'
  assert_contem 'ou find na falta dele; sem os dois, recusa com codigo 3' "$(cat "$base/out")" \
    'a linha de dependencias declara o limite do vinculo (decisao do Tech Lead)'
}

teste_dia04_info_continua_recusado_pelo_preflight_no_mesmo_ambiente() {
  local base
  base=$(_cenario)
  rm -f "$base/bin/stat" "$base/bin/mktemp" "$base/bin/readlink"
  _rodar "$base" info /x
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'o preflight recusa'
  assert_contem 'utilitario obrigatorio ausente' "$DBX_ERRO" 'mensagem do preflight'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada'
}

# ---------------------------------------------------------------------------
# TC-DIA-05 — credencial
# ---------------------------------------------------------------------------

teste_dia05_credencial_ausente_larga_ou_incompleta_tem_remedio_proprio() {
  local base arquivo
  base=$(_cenario)
  arquivo="$base/config/dbx/credencial.json"
  rm -f "$arquivo"
  _rodar "$base" diagnostico
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'falha sai com 3'
  assert_contem 'credencial=falha' "$DBX_SAIDA" 'ausente e falha'
  assert_contem 'remedio: dbx config' "$(_linha credencial)" 'remedio: configurar'
  assert_contem 'conectividade=falha: nao executada' "$DBX_SAIDA" 'a dependente aparece'
  _credencial "$base" "$SENTINELA_SEGREDO"
  chmod 644 "$arquivo"
  _rodar "$base" diagnostico
  assert_contem "remedio: chmod 600 $arquivo" "$(_linha credencial)" 'permissao larga: chmod'
  _credencial "$base" ''
  _rodar "$base" diagnostico
  assert_contem 'app secret' "$(_linha credencial)" 'campo faltante nomeado'
  assert_contem 'remedio: dbx config --substituir' "$(_linha credencial)" 'remedio: reconfigurar'
}

# ---------------------------------------------------------------------------
# TC-DIA-06, TC-DIA-07, TC-DIA-08 — conectividade, escopos e espaco
# ---------------------------------------------------------------------------

teste_dia06_check_user_rejeitado_ou_rede_indisponivel_falha_a_conectividade() {
  local base
  base=$(_cenario)
  printf '401' >"$base/check_codigo"
  _rodar "$base" diagnostico
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'falha sai com 3'
  assert_contem 'conectividade=falha' "$DBX_SAIDA" 'check/user rejeitado'
  rm -f "$base/check_codigo"
  printf '6' >"$base/curl_saida"
  _rodar "$base" diagnostico
  assert_contem 'conectividade=falha' "$DBX_SAIDA" 'rede indisponivel'
  assert_contem 'escopos=falha: nao executada' "$DBX_SAIDA" 'escopos depende da renovacao'
}

teste_dia07_escopo_faltante_e_nomeado_e_sem_campo_e_aviso() {
  local base
  base=$(_cenario)
  printf '{"access_token":"%s","expires_in":14400,"scope":"account_info.read files.metadata.read files.content.read"}' \
    "$SENTINELA_TOKEN" >"$base/token"
  _rodar "$base" diagnostico
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'escopo faltante e falha'
  assert_contem 'escopos=falha' "$DBX_SAIDA" 'falha'
  assert_contem 'files.content.write' "$(_linha escopos)" 'o faltante e nomeado'
  printf '{"access_token":"%s","expires_in":14400}' "$SENTINELA_TOKEN" >"$base/token"
  DBX_LOCALIDADE_DE_TESTE=''
  _rodar "$base" diagnostico
  assert_contem 'escopos=aviso: escopos nao informados' "$DBX_SAIDA" 'sem o campo e aviso'
  assert_nao_contem '=falha' "$DBX_SAIDA" 'aviso nao vira falha'
  assert_igual 0 "$DBX_ESTADO" 'aviso sem falha sai com 0'
}

teste_dia08_espaco_a_noventa_por_cento_avisa_e_cheio_falha() {
  local base
  base=$(_cenario)
  printf '%s' '{"used":900,"allocation":{".tag":"individual","allocated":1000}}' >"$base/espaco"
  _rodar "$base" diagnostico
  assert_contem 'espaco=aviso' "$DBX_SAIDA" '90% e aviso'
  printf '%s' '{"used":1000,"allocation":{".tag":"individual","allocated":1000}}' >"$base/espaco"
  _rodar "$base" diagnostico
  assert_contem 'espaco=falha' "$DBX_SAIDA" 'cheio e falha'
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" 'falha sai com 3'
  printf '%s' '{"used":1}' >"$base/espaco"
  _rodar "$base" diagnostico
  assert_contem 'espaco=aviso' "$DBX_SAIDA" 'sem alocacao e aviso'
}

# ---------------------------------------------------------------------------
# TC-DIA-09 — localidade e diretorio de estado
# ---------------------------------------------------------------------------

teste_dia09_localidade_ausente_avisa_e_estado_largo_falha() {
  local base
  base=$(_cenario)
  DBX_LOCALIDADE_DE_TESTE='xx_INEXISTENTE.UTF-8'
  _rodar "$base" diagnostico
  assert_contem 'localidade=aviso' "$DBX_SAIDA" 'sem a localidade, aviso'
  assert_contem 'estado=ok' "$DBX_SAIDA" 'estado ausente e ok'
  assert_contem 'ainda nao criado' "$(_linha estado)" 'e o motivo'
  mkdir -p "$base/estado/dbx"
  chmod 755 "$base/estado/dbx"
  _rodar "$base" diagnostico
  assert_contem 'estado=falha' "$DBX_SAIDA" 'estado 0755 e falha'
  assert_contem "remedio: chmod 700 $base/estado/dbx" "$(_linha estado)" 'remedio sugerido'
  assert_igual 755 "$(stat -c %a "$base/estado/dbx")" 'o remedio nunca e aplicado'
}

# ---------------------------------------------------------------------------
# TC-DIA-10 — seguranca: nada vaza, nada muda, so leitura (Regra 6)
# ---------------------------------------------------------------------------

teste_dia10_nenhum_sentinela_aparece_em_saida_alguma() {
  local base sentinela apresentacao texto
  base=$(_cenario)
  for apresentacao in '' --json '--json --null' --debug; do
    # shellcheck disable=SC2086  # a apresentacao e uma lista de opcoes
    _rodar "$base" $apresentacao diagnostico
    texto="$DBX_SAIDA$DBX_ERRO"
    for sentinela in "$SENTINELA_REFRESH" "$SENTINELA_SEGREDO" "$SENTINELA_TOKEN" "$SENTINELA_CHAVE"; do
      assert_segredo_ausente "$sentinela" "$texto" "sentinela em [$apresentacao]"
    done
  done
  # A falha de renovacao tambem nao ecoa o corpo.
  printf '{"error":"invalid_grant","refresh_token":"%s"}' "$SENTINELA_REFRESH" >"$base/token"
  _rodar "$base" --debug diagnostico
  assert_segredo_ausente "$SENTINELA_REFRESH" "$DBX_SAIDA$DBX_ERRO" 'corpo ecoado na falha'
}

teste_dia10_ambiente_identico_e_so_tres_endpoints_de_leitura() {
  local base antes_config chamada
  base=$(_cenario)
  antes_config=$(_retrato "$base/config")
  _rodar "$base" diagnostico
  assert_igual "$antes_config" "$(_retrato "$base/config")" 'a credencial nao e regravada'
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'o estado nao e criado'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhum temporario sobra'
  while IFS= read -r chamada; do
    case $chamada in
      *oauth2/token | *2/check/user | *users/get_space_usage) ;;
      *) _harness_falhar "chamada fora das tres de leitura: $chamada" ;;
    esac
  done <"$base/chamadas"
}

teste_dia10_argumento_desconhecido_e_uso_invalido() {
  local base
  base=$(_cenario)
  _rodar "$base" diagnostico --qualquer
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'argumento recusado'
}

# ---------------------------------------------------------------------------
# TC-DIA-15, TC-DIA-16 (RF-77, DIV-67) — escopo opcional files.permanent_delete
# na propria linha `escopos` (DIV-70: sem checagem nova, contagens intactas).
# ---------------------------------------------------------------------------

teste_dia15_escopo_opcional_concedido_e_ok_habilitada() {
  local base
  base=$(_cenario)
  printf '{"access_token":"%s","expires_in":14400,"scope":"%s files.permanent_delete"}' \
    "$SENTINELA_TOKEN" "$ESCOPOS" >"$base/token"
  _rodar "$base" diagnostico
  assert_contem 'escopos=ok' "$(_linha escopos)" 'continua ok'
  assert_contem 'exclusao permanente habilitada' "$(_linha escopos)" 'opcional concedido'
  assert_nao_contem 'opcional ausente' "$(_linha escopos)" 'sem remedio'
}

teste_dia16_escopo_opcional_ausente_e_ok_informativo_sem_mudar_o_codigo() {
  local base
  base=$(_cenario)
  _rodar "$base" diagnostico
  assert_contem 'escopos=ok' "$(_linha escopos)" 'ausente continua ok (DIV-67)'
  assert_contem 'opcional ausente: files.permanent_delete' "$(_linha escopos)" 'informa'
  assert_contem 'dbx lixeira --excluir indisponivel' "$(_linha escopos)" 'o que fica indisponivel'
  assert_contem 'dbx unlink' "$(_linha escopos)" 'remedio de RF-76(g) (DIV-56)'
  assert_nao_contem 'escopos=aviso' "$DBX_SAIDA" 'nao vira aviso'
  _localidade_disponivel && assert_igual 0 "$DBX_ESTADO" 'codigo inalterado sem outras falhas'
  return 0
}

# TC-FBSD-15 (RF-167, I-65) — com o stat do BSD (rejeita `-c`) o diretorio de
# estado 0700 do proprio usuario nao pode virar "permissao incorreta" falsa.
# O PATH do cenario so tem o `bin` dele, entao o duble entra como invocacao
# explicita do bash: o `env bash` do shebang nao existe ali.
teste_fbsd15_estado_0700_com_stat_bsd_nao_reporta_permissao_falsa() {
  local base
  base=$(_cenario)
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  rm -f -- "$base/bin/stat"
  printf '#!%s\nexec %s %s "$@"\n' "$BASH_ABSOLUTO" "$BASH_ABSOLUTO" \
    "$DBX_HARNESS_RAIZ/tests/duplos/freebsd/bin/stat" >"$base/bin/stat"
  chmod +x "$base/bin/stat"
  _rodar "$base" diagnostico
  assert_contem 'estado=ok' "$DBX_SAIDA" "estado 0700 e ok com o stat BSD: $(_linha estado)"
  assert_contem 'com permissao 700' "$(_linha estado)" 'o modo foi lido, nao assumido vazio'
}

harness_executar "$@"
