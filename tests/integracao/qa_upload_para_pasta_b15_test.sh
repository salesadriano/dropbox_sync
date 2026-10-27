#!/usr/bin/env bash
# Suite independente do QA Expert para `upload` de arquivo para pasta (RF-174 e a
# emenda de RF-60(g)(h)), ciclo 1. Derivada dos criterios, nao da suite do
# developer. Pelo `bin/dbx`, com duplo de `curl` proprio (prefixo qp_) que:
#  - responde get_metadata por caminho (tabela `metas`; ausente = 409 not_found);
#  - registra cada rota em `chamadas`, cada caminho consultado em `consultas` e o
#    que foi enviado (Dropbox-API-Arg do upload e do finish) em `opcoes`.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly QP_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QP_ESCRITA='alvo=start\|alvo=upload\|alvo=append\|alvo=finish'

_qp_cenario() { # [raiz_remota]
  local raiz=${1:-/} base
  base=$(mktemp -d "$DBX_TESTES_TMP/qppasta.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/tmp" "$base/loc"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"%s"}' "$raiz" \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  : >"$base/metas"
  {
    printf '#!/usr/bin/env bash\nbase=%s\n' "$base"
    cat <<'FIM'
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
  *oauth2/token*) corpo='{"access_token":"sl.t","token_type":"bearer","expires_in":14400}'; alvo=token ;;
  *get_current_account*) corpo='{"account_id":"dbid:C"}'; alvo=conta ;;
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

_qp_rodar() { # <base> <stdin> <argumentos...>
  local base=$1 entrada=$2
  shift 2
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$QP_EXEC" "$@" <"$entrada" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  QP_OUT='' QP_ERR='' QP_ENV=''
  IFS= read -r -d '' QP_OUT <"$base/out"
  IFS= read -r -d '' QP_ERR <"$base/err"
  [[ -r $base/opcoes ]] && IFS= read -r -d '' QP_ENV <"$base/opcoes"
  return 0
}

_qp_pasta() { printf '%s|{".tag":"folder","name":"p"}\n' "$2" >>"$1/metas"; }
_qp_arquivo_remoto() { # <base> <caminho> <hash>
  printf '%s|{".tag":"file","name":"n","content_hash":"%s"}\n' "$2" "$3" >>"$1/metas"
}
_qp_origem() { # <base> <nome> -> caminho
  printf 'conteudo qa\n' >"$1/loc/$2"
  printf '%s' "$1/loc/$2"
}
_qp_grande() { # <base> <nome> -> caminho esparso acima de 150 MiB (sessao)
  dd if=/dev/null of="$1/loc/$2" bs=1 seek=$((157286400 + 1)) 2>/dev/null || return 1
  printf '%s' "$1/loc/$2"
}
_qp_n() { _harness_contar "$@"; }

teste_qa_pasta_existente_upload_simples_envia_para_pasta_e_nome() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_igual 1 "$(_qp_n 'alvo=upload' "$base/chamadas")" 'um envio simples'
  assert_contem 'path\":\"/dados/rel.pdf\"' "$QP_ENV" 'Dropbox-API-Arg com <pasta>/<nome>'
  assert_nao_contem 'path\":\"/dados\"' "$QP_ENV" 'nao envia ao caminho da pasta'
}

teste_qa_pasta_existente_upload_por_sessao_finish_em_pasta_e_nome() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_grande "$base" grande.bin) || pular 'sem arquivo esparso'
  _qp_rodar "$base" /dev/null --json upload "$o" /dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_igual 1 "$(_qp_n 'alvo=finish' "$base/chamadas")" 'sessao concluida'
  assert_contem 'path\":\"/dados/grande.bin\"' "$QP_ENV" 'commit da sessao com <pasta>/<nome>'
  assert_nao_contem 'path\":\"/dados\"' "$QP_ENV" 'commit nao aponta para a pasta'
}

teste_qa_barra_final_sem_pasta_existir_nao_consulta_o_tipo() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /nao/existe/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/nao/existe/rel.pdf\"' "$QP_ENV" 'alvo <destino>/<nome>'
  assert_nao_contem '/nao/existe"' "$(cat "$base/consultas" 2>/dev/null)" 'nenhuma consulta do tipo da pasta'
}

teste_qa_barra_final_em_pasta_existente_nao_duplica_barra() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /dados/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/dados/rel.pdf\"' "$QP_ENV" 'um unico separador'
  assert_nao_contem '//rel.pdf' "$QP_ENV" 'sem barra dupla no caminho enviado'
}

teste_qa_destino_raiz_envia_para_raiz_com_o_nome() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/rel.pdf\"' "$QP_ENV" 'arquivo na raiz'
  assert_nao_contem '//rel.pdf' "$QP_ENV" 'sem barra dupla'
}

teste_qa_nome_com_espaco_e_unicode_vai_inteiro_para_a_pasta() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" 'relatório ção final.txt')
  _qp_rodar "$base" /dev/null --json upload "$o" /dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/dados/relatório ção final.txt\"' "$QP_ENV" 'nome preservado sob a pasta'
}

teste_qa_nome_com_aspas_fica_escapado_e_sob_a_pasta() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" 'a"b.txt') || return 1
  _qp_rodar "$base" /dev/null --json upload "$o" /dados/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/dados/a\\\"b.txt\"' "$QP_ENV" 'aspas escapadas no JSON, nome sob /dados'
  assert_igual 1 "$(_qp_n 'alvo=upload' "$base/chamadas")" 'um envio, sem corromper o argumento'
}

teste_qa_nome_com_pontos_duplos_nao_e_componente_e_nao_escapa() {
  local base o n
  base=$(_qp_cenario)
  for n in '..x' 'a..b' 'x..' '...'; do
    : >"$base/opcoes"
    o=$(_qp_origem "$base" "$n")
    _qp_rodar "$base" /dev/null --json upload "$o" /dados/
    assert_igual 0 "$DBX_ESTADO" "nome $n; diagnostico: $QP_ERR"
    assert_contem "path\\\":\\\"/dados/$n\\\"" "$QP_ENV" "nome $n fica literal sob /dados"
  done
}

teste_qa_confinamento_com_raiz_remota_prefixa_pasta_e_nome() {
  local base o
  base=$(_qp_cenario /raiz)
  _qp_pasta "$base" /raiz/dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /raiz/dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/raiz/dados/rel.pdf\"' "$QP_ENV" 'raiz + pasta + nome'
  assert_contem '/raiz/dados' "$(cat "$base/consultas")" 'a consulta de tipo ja e confinada'
}

teste_qa_confinamento_destino_barra_final_com_raiz_remota() {
  local base o
  base=$(_qp_cenario /raiz)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /raiz/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/raiz/rel.pdf\"' "$QP_ENV" 'destino /raiz/ grava na raiz_remota'
}

teste_qa_confinamento_destino_que_escapa_da_raiz_nunca_grava_fora() {
  local base o p
  base=$(_qp_cenario /raiz)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /../fora/
  while IFS= read -r p; do
    [[ $p == /raiz/* || $p == /raiz ]] || _harness_falhar "caminho fora da raiz_remota: $p" "$QP_ENV"
  done < <(grep -o 'path\\":\\"[^\\]*' <<<"$QP_ENV" | sed 's/path\\":\\"//')
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'destino que escapa nao escreve'
  assert_diferente 0 "$DBX_ESTADO" 'recusado'
}

teste_qa_confinamento_nome_nao_escapa_com_raiz_remota() {
  local base o
  base=$(_qp_cenario /raiz)
  o=$(_qp_origem "$base" '..x')
  _qp_rodar "$base" /dev/null --json upload "$o" /raiz/dados/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/raiz/dados/..x\"' "$QP_ENV" 'nome com .. fica sob a raiz'
}

teste_qa_arquivo_identico_na_pasta_e_dispensado_sem_envio() {
  local base o hash
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  hash=$(dbx_hash_conteudo_arquivo "$o")
  _qp_arquivo_remoto "$base" /dados/rel.pdf "$hash"
  _qp_rodar "$base" /dev/null --json upload "$o" /dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'dispensado' "$QP_OUT" 'status dispensado'
  assert_contem '/dados/rel.pdf' "$QP_OUT" 'caminho final na saida'
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'nenhuma escrita'
}

teste_qa_arquivo_diferente_na_pasta_e_enviado() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_arquivo_remoto "$base" /dados/rel.pdf 0000000000000000000000000000000000000000000000000000000000000000
  _qp_rodar "$base" /dev/null --json upload "$o" /dados
  assert_igual 1 "$(_qp_n 'alvo=upload' "$base/chamadas")" 'hash diferente: envia'
}

teste_qa_forcar_com_pasta_faz_exatamente_uma_consulta_de_tipo() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload --forcar "$o" /dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_igual 1 "$(_qp_n '' "$base/consultas")" 'uma consulta so'
  assert_igual '/dados' "$(head -n1 "$base/consultas")" 'consulta do destino informado'
  assert_contem 'path\":\"/dados/rel.pdf\"' "$QP_ENV" 'envio ao caminho final'
}

teste_qa_forcar_com_barra_final_nao_consulta() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload --forcar "$o" /dados/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_igual 0 "$(_qp_n '' "$base/consultas")" 'sem consulta'
  assert_contem 'path\":\"/dados/rel.pdf\"' "$QP_ENV" 'caminho final'
}

teste_qa_forcar_destino_arquivo_mantem_o_caminho() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_arquivo_remoto "$base" /dados/antigo.pdf 0000
  _qp_rodar "$base" /dev/null --json upload --forcar "$o" /dados/antigo.pdf
  assert_contem 'path\":\"/dados/antigo.pdf\"' "$QP_ENV" 'destino arquivo: como informado'
  assert_igual 1 "$(_qp_n '' "$base/consultas")" 'ainda uma consulta de tipo'
}

teste_qa_stdin_para_pasta_existente_recusa_com_2_sem_escrita() {
  local base in
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  in="$base/in"
  printf 'dados' >"$in"
  _qp_rodar "$base" "$in" upload - /dados
  assert_igual 2 "$DBX_ESTADO" 'uso invalido'
  assert_igual 1 "$(_qp_n '' "$base/consultas")" 'exatamente uma consulta de tipo'
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'nenhuma escrita'
  assert_contem 'entrada padr' "$QP_ERR" 'mensagem orienta o nome no destino'
}

teste_qa_stdin_com_barra_final_recusa_com_2_sem_escrita() {
  local base in
  base=$(_qp_cenario)
  in="$base/in"
  printf 'dados' >"$in"
  _qp_rodar "$base" "$in" upload - /dados/
  assert_igual 2 "$DBX_ESTADO" 'uso invalido'
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'nenhuma escrita'
}

teste_qa_stdin_com_nome_no_destino_continua_funcionando() {
  local base in
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  in="$base/in"
  printf 'dados' >"$in"
  _qp_rodar "$base" "$in" --json upload - /dados/nome.txt
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/dados/nome.txt\"' "$QP_ENV" 'caminho informado'
  assert_igual 1 "$(_qp_n '' "$base/consultas")" 'uma consulta de tipo (destino-arquivo inexistente)'
}

teste_qa_rev_com_pasta_nao_consulta_e_usa_o_caminho_informado() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload --rev 0123456789 "$o" /dados
  assert_igual 0 "$(_qp_n '' "$base/consultas")" 'sem nenhuma consulta'
  assert_contem 'path\":\"/dados\"' "$QP_ENV" 'caminho como informado'
  assert_nao_contem '/dados/rel.pdf' "$QP_ENV" 'nao resolve para a pasta'
}

teste_qa_dry_run_com_barra_final_reporta_caminho_final_sem_escrita() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --dry-run --json upload "$o" /novo/
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem '/novo/rel.pdf' "$QP_OUT" 'plano com o caminho final'
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'nenhuma escrita'
}

teste_qa_dry_run_com_pasta_existente_reporta_caminho_final_sem_escrita() {
  local base o
  base=$(_qp_cenario)
  _qp_pasta "$base" /dados
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --dry-run --json upload "$o" /dados
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem '/dados/rel.pdf' "$QP_OUT" 'plano com o caminho final'
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'nenhuma escrita'
}

teste_qa_destino_inexistente_sem_barra_mantem_comportamento_anterior() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_rodar "$base" /dev/null --json upload "$o" /novo/arquivo.pdf
  assert_igual 0 "$DBX_ESTADO" "diagnostico: $QP_ERR"
  assert_contem 'path\":\"/novo/arquivo.pdf\"' "$QP_ENV" 'o destino e o nome do arquivo remoto'
}

teste_qa_destino_arquivo_diferente_mantem_comportamento_anterior_e_envia() {
  local base o
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  _qp_arquivo_remoto "$base" /dados/outro.pdf 0000000000000000000000000000000000000000000000000000000000000000
  _qp_rodar "$base" /dev/null --json upload "$o" /dados/outro.pdf
  assert_contem 'path\":\"/dados/outro.pdf\"' "$QP_ENV" 'sem tratar o arquivo como pasta'
  assert_nao_contem '/dados/outro.pdf/rel.pdf' "$QP_ENV" 'nao grava dentro do arquivo'
}

teste_qa_destino_arquivo_identico_continua_dispensado() {
  local base o hash
  base=$(_qp_cenario)
  o=$(_qp_origem "$base" rel.pdf)
  hash=$(dbx_hash_conteudo_arquivo "$o")
  _qp_arquivo_remoto "$base" /dados/outro.pdf "$hash"
  _qp_rodar "$base" /dev/null --json upload "$o" /dados/outro.pdf
  assert_contem 'dispensado' "$QP_OUT" 'RF-60(a) preservado'
  assert_igual 0 "$(_qp_n "$QP_ESCRITA" "$base/chamadas")" 'nenhuma escrita'
}

harness_executar "$@"
