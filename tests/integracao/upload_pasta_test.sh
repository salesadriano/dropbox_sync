#!/usr/bin/env bash
# Testes ponta a ponta do `upload` de ARQUIVO para destino que e pasta: o arquivo
# deve ser gravado em `<pasta>/<nome>` (barra final, ou pasta que ja existe), e
# nao falhar com `path/conflict/folder` no fim do envio.
#
# O duplo de `curl` responde `get_metadata` por caminho (tabela `metas`) e registra
# cada consulta, cada rota e o cabecalho de cada requisicao.
#
# shellcheck disable=SC2016
# Justificativa: casos escrevem o substituto de `curl`, sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

# _ambiente_pasta [raiz_remota] — credencial e `curl` duplo. `metas`: linhas
# `<caminho>|<json>`; caminho ausente da tabela responde 409 not_found.
_ambiente_pasta() {
  local raiz=${1:-/} base
  base=$(mktemp -d "$DBX_TESTES_TMP/pasta.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"%s"}' "$raiz" \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  : >"$base/metas"
  {
    printf '#!/usr/bin/env bash\nbase=%s\n' "$base"
    cat <<'FIM'
printf '%s\n' "$*" >>"$base/argv"
conf=$(cat)
printf '%s\n' "$conf" >>"$base/opcoes"
saida=''; escrever=''; anterior=''; url=''; corpoarq=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; @*) corpoarq=${arg#@} ;; esac
  anterior=$arg
done
codigo=200
case $url in
  *oauth2/token*)
    corpo='{"access_token":"sl.t","token_type":"bearer","expires_in":14400}'; alvo=token ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}'; alvo=conta ;;
  *get_space_usage*) corpo='{"used":1,"allocation":{".tag":"individual","allocated":1000000000000}}'; alvo=espaco ;;
  *files/get_metadata*)
    alvo=meta
    caminho=$(sed -n 's/.*"path":"\([^"]*\)".*/\1/p' "$corpoarq")
    printf '%s\n' "$caminho" >>"$base/consultas"
    corpo='{"error_summary":"path/not_found/..","error":{".tag":"path","path":{".tag":"not_found"}}}'
    codigo=409
    while IFS='|' read -r p j; do
      if [[ $p == "$caminho" ]]; then corpo=$j; codigo=200; fi
    done <"$base/metas"
    ;;
  *upload_session/start*) corpo='{"session_id":"S-1"}'; alvo=start ;;
  *upload_session/append_v2*) corpo='{}'; alvo=append ;;
  *upload_session/finish*) corpo='{"name":"x","path_display":"/x","rev":"016","size":9}'; alvo=finish ;;
  *files/upload*) corpo='{"name":"x","path_display":"/x","rev":"016","size":9}'; alvo=upload ;;
  *) corpo='{}'; alvo=outro ;;
esac
printf 'alvo=%s\n' "$alvo" >>"$base/chamadas"
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
if [[ $codigo -ge 400 && " $* " == *" --fail "* ]]; then exit 22; fi
exit 0
FIM
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
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _rodar_fluxo <base> <entrada> <argumentos...> — com entrada padrao.
_rodar_fluxo() {
  local base=$1 entrada=$2
  shift 2
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" <<<"$entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_pasta() { printf '%s|%s\n' "$2" '{".tag":"folder","name":"p","path_display":"/p"}' >>"$1/metas"; }

_origem_pequena() { # <base> -> caminho
  printf 'conteudo\n' >"$1/nossoerp.bak.zip"
  printf '%s' "$1/nossoerp.bak.zip"
}

_origem_grande() { # <base> -> caminho (esparso, acima do teto de 150 MiB)
  dd if=/dev/null of="$1/nossoerp.bak.zip" bs=1 seek=$((157286400 + 1)) 2>/dev/null || return 1
  printf '%s' "$1/nossoerp.bak.zip"
}

teste_pasta_existente_grava_em_pasta_e_nome_por_requisicao_unica() {
  local base origem
  base=$(_ambiente_pasta)
  _pasta "$base" '/ASJ/backup nosso'
  origem=$(_origem_pequena "$base")
  _rodar "$base" --json upload "$origem" '/ASJ/backup nosso'
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'alvo=upload$' "$base/chamadas")" 'uma requisicao unica'
  assert_contem 'path\":\"/ASJ/backup nosso/nossoerp.bak.zip\"' "$(cat "$base/opcoes")" \
    'o Dropbox-API-Arg deve levar o caminho final <pasta>/<nome>'
}

teste_pasta_existente_grava_em_pasta_e_nome_por_sessao() {
  local base origem
  base=$(_ambiente_pasta)
  _pasta "$base" /pasta
  origem=$(_origem_grande "$base") || pular 'nao foi possivel criar arquivo esparso'
  _rodar "$base" --json upload "$origem" /pasta
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'alvo=finish' "$base/chamadas")" 'sessao concluida'
  assert_contem 'path\":\"/pasta/nossoerp.bak.zip\"' "$(cat "$base/opcoes")" \
    'o commit da sessao deve levar o caminho final'
}

teste_barra_final_grava_em_pasta_sem_consulta_extra() {
  local base origem
  base=$(_ambiente_pasta)
  origem=$(_origem_pequena "$base")
  _rodar "$base" --json upload "$origem" /nova/
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'path\":\"/nova/nossoerp.bak.zip\"' "$(cat "$base/opcoes")" 'caminho final'
  assert_igual 1 "$(_harness_contar '' "$base/consultas")" \
    'uma so consulta (a pre-checagem do caminho final), nenhuma para o tipo'
  assert_igual '/nova/nossoerp.bak.zip' "$(head -n1 "$base/consultas")" 'a consulta e do caminho final'
}

teste_barra_sozinha_grava_na_raiz() {
  local base origem
  base=$(_ambiente_pasta)
  origem=$(_origem_pequena "$base")
  _rodar "$base" --json upload "$origem" /
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'path\":\"/nossoerp.bak.zip\"' "$(cat "$base/opcoes")" 'caminho final na raiz'
}

teste_arquivo_identico_na_pasta_e_dispensado() {
  local base origem hash
  base=$(_ambiente_pasta)
  _pasta "$base" /pasta
  origem=$(_origem_pequena "$base")
  dbx_hash_publicar_arquivo "$origem" || return 1
  hash=$DBX_HASH_RESULTADO
  printf '%s|{".tag":"file","name":"nossoerp.bak.zip","content_hash":"%s"}\n' \
    /pasta/nossoerp.bak.zip "$hash" >>"$base/metas"
  _rodar "$base" --json upload "$origem" /pasta
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'status=dispensado' "$DBX_SAIDA" 'conteudo identico no caminho final dispensa o envio'
  assert_contem 'caminho=/pasta/nossoerp.bak.zip' "$DBX_SAIDA" 'caminho final na saida'
  assert_igual 0 "$(_harness_contar 'alvo=upload' "$base/chamadas")" 'nada enviado'
  assert_igual 2 "$(_harness_contar '' "$base/consultas")" 'uma consulta da pasta e uma do arquivo final'
}

teste_forcar_com_pasta_resolve_com_consulta_so_de_tipo() {
  local base origem
  base=$(_ambiente_pasta)
  _pasta "$base" /pasta
  origem=$(_origem_pequena "$base")
  _rodar "$base" --json upload --forcar "$origem" /pasta
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'path\":\"/pasta/nossoerp.bak.zip\"' "$(cat "$base/opcoes")" 'caminho final'
  assert_igual 1 "$(_harness_contar '' "$base/consultas")" 'uma so consulta, do destino informado'
}

teste_entrada_padrao_com_pasta_existente_recusa_sem_escrita() {
  local base
  base=$(_ambiente_pasta)
  _pasta "$base" /pasta
  _rodar_fluxo "$base" dados upload - /pasta
  assert_igual 2 "$DBX_ESTADO" 'entrada padrao para pasta existente e uso invalido'
  assert_contem 'entrada padrao' "$DBX_ERRO" 'a mensagem cita a entrada padrao'
  assert_igual 0 "$(_harness_contar 'alvo=start\|alvo=upload\|alvo=append\|alvo=finish' "$base/chamadas")" \
    'nenhuma escrita remota'
}

teste_entrada_padrao_com_barra_final_recusa_antes_da_rede() {
  local base
  base=$(_ambiente_pasta)
  _rodar_fluxo "$base" dados upload - /pasta/
  assert_igual 2 "$DBX_ESTADO" 'entrada padrao para destino com barra final e uso invalido'
  assert_contem 'entrada padrao' "$DBX_ERRO" 'a mensagem cita a entrada padrao'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
}

teste_destino_inexistente_sem_barra_mantem_o_caminho_informado() {
  local base origem
  base=$(_ambiente_pasta)
  origem=$(_origem_pequena "$base")
  _rodar "$base" --json upload "$origem" /nao/existe.bak
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'path\":\"/nao/existe.bak\"' "$(cat "$base/opcoes")" 'caminho como informado'
  assert_igual 1 "$(_harness_contar '' "$base/consultas")" 'sem consulta extra'
}

teste_destino_que_e_arquivo_mantem_o_caminho_informado() {
  local base origem
  base=$(_ambiente_pasta)
  printf '%s|%s\n' /a.bak '{".tag":"file","name":"a.bak","content_hash":"x"}' >>"$base/metas"
  origem=$(_origem_pequena "$base")
  _rodar "$base" --json upload "$origem" /a.bak
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'path\":\"/a.bak\"' "$(cat "$base/opcoes")" 'arquivo existente: sobrescrita como hoje'
}

teste_dry_run_com_barra_final_reporta_caminho_final_sem_escrita() {
  local base origem
  base=$(_ambiente_pasta)
  origem=$(_origem_pequena "$base")
  _rodar "$base" --dry-run --json upload "$origem" /nova/
  assert_igual 0 "$DBX_ESTADO" "dry-run deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'caminho=/nova/nossoerp.bak.zip' "$DBX_SAIDA" 'caminho final no plano'
  assert_igual 0 "$(_harness_contar 'alvo=upload\|alvo=start' "$base/chamadas")" 'nenhuma escrita'
}

teste_dry_run_com_pasta_existente_reporta_caminho_final_sem_chamada_extra() {
  local base origem
  base=$(_ambiente_pasta)
  _pasta "$base" /pasta
  origem=$(_origem_pequena "$base")
  _rodar "$base" --dry-run --json upload "$origem" /pasta
  assert_igual 0 "$DBX_ESTADO" "dry-run deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'caminho=/pasta/nossoerp.bak.zip' "$DBX_SAIDA" 'caminho final no plano'
  assert_igual 1 "$(_harness_contar '' "$base/consultas")" 'a mesma consulta que o dry-run ja fazia'
}

teste_nome_com_caracteres_especiais_fica_dentro_da_pasta_e_da_raiz() {
  local base origem
  base=$(_ambiente_pasta /raiz)
  _pasta "$base" /raiz/pasta
  origem="$base/..nome com espaco & ;x.zip"
  printf 'c\n' >"$origem"
  _rodar "$base" --json upload "$origem" /raiz/pasta
  assert_igual 0 "$DBX_ESTADO" "upload deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'path\":\"/raiz/pasta/..nome com espaco & ;x.zip\"' "$(cat "$base/opcoes")" \
    'o nome e um componente so, sob a pasta e a raiz'
}

harness_executar "$@"
