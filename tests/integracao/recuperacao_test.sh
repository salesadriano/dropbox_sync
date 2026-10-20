#!/usr/bin/env bash
# Testes ponta a ponta da fase 3 do backlog: revisoes, restauracao e lixeira
# (F-07, F-20; RF-72 a RF-78; TC-RVS, TC-RST, TC-RPA, TC-LIX, TC-EXP, TC-DOC-02).
#
# O DUPLO DE `curl` RESPONDE POR REGRA, NAO POR ENDPOINT FIXO. Cada caso grava em
# `regras` linhas `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>arquivo[<TAB>uma]`;
# a primeira regra cujo endpoint e filtro (padroes do shell) casam responde. Com
# `uma`, a regra vale uma vez so (retentativa e reexecucao). Toda chamada fica em
# `chamadas`, uma por linha (`endpoint corpo`), e e por ela que os casos provam
# que um endpoint NAO foi chamado. Chamada sem regra responde 400 e fica marcada
# `SEM_REGRA`, para que um caso nunca passe por acidente.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly SENTINELA_REFRESH='RT_SENTINELA_refresh_5u6v7w'
readonly SENTINELA_SEGREDO='AS_SENTINELA_segredo_8x9y0z'
readonly SENTINELA_CHAVE='AK_SENTINELA_chave_1q2w3e'
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_4r5t6y'

# _ambiente [raiz_remota] — credencial, duplo de `curl` e arquivo de regras.
_ambiente() {
  local raiz=${1:-/} base
  base=$(mktemp -d "$DBX_TESTES_TMP/recuperacao.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/respostas"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"%s"}' \
    "$SENTINELA_CHAVE" "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$raiz" \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  : >"$base/regras"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%q\n' "$base"
    printf 'token=%q\n' "$SENTINELA_TOKEN"
  } >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
opcoes=$(cat)
saida=''; escrever=''; anterior=''; url=''; dados=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) dados=${arg#@} ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
endpoint=${url#https://api.dropboxapi.com/2/}
codigo=400 corpo='{"error_summary":"sem_regra/"}'
if [[ $url == *oauth2/token* ]]; then
  printf 'oauth2/token\n' >>"$base/chamadas"
  codigo=200
  corpo="{\"access_token\":\"$token\",\"token_type\":\"bearer\",\"expires_in\":14400}"
else
  printf '%s %s\n' "$endpoint" "$pedido" >>"$base/chamadas"
  achou=nao n=0
  while IFS=$'\t' read -r ep filtro cod arq vez; do
    n=$((n + 1))
    [[ -n $ep ]] || continue
    # shellcheck disable=SC2053
    [[ $endpoint == $ep && $pedido == $filtro ]] || continue
    if [[ $vez == uma ]]; then
      [[ -e $base/usada.$n ]] && continue
      : >"$base/usada.$n"
    fi
    achou=sim codigo=$cod corpo=''
    [[ -n $arq && -r $base/respostas/$arq ]] && IFS= read -r -d '' corpo <"$base/respostas/$arq"
    break
  done <"$base/regras"
  [[ $achou == sim ]] || printf 'SEM_REGRA %s\n' "$endpoint" >>"$base/chamadas"
fi
case $codigo in
  TERM) kill -TERM 0; sleep 5; exit 1 ;;
  REDE) printf 'curl: (7) Failed to connect\n' >&2; exit 7 ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_seq=0
# _regra <base> <endpoint> <filtro> <codigo> <corpo> [uma]
_regra() {
  local base=$1 ep=$2 filtro=$3 codigo=$4 corpo=$5 vez=${6:-}
  _seq=$((_seq + 1))
  printf '%s' "$corpo" >"$base/respostas/r$_seq"
  printf '%s\t%s\t%s\t%s\t%s\n' "$ep" "$filtro" "$codigo" "r$_seq" "$vez" >>"$base/regras"
}

# _regra_antes — como `_regra`, mas na frente das existentes (vence as gerais).
_regra_antes() {
  local base=$1
  shift
  mv "$base/regras" "$base/regras.ant"
  : >"$base/regras"
  _regra "$base" "$@"
  cat "$base/regras.ant" >>"$base/regras"
  rm -f "$base/regras.ant"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _rodar_tty <base> <resposta> <argumentos...> — stdin num terminal (script(1)).
_rodar_tty() {
  local base=$1 resposta=$2 linha arg
  shift 2
  command -v script >/dev/null 2>&1 || pular 'script(1) ausente: sem terminal para o caso'
  printf -v linha 'bash %q' "$DBX_EXEC"
  for arg in "$@"; do printf -v arg ' %q' "$arg" && linha+=$arg; done
  printf '%s\n' "$resposta" | env -i PATH="$base/bin:$PATH" HOME="$base" \
    XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    script -qec "$linha" /dev/null >"$base/out" 2>&1
  DBX_ESTADO=$?
  DBX_SAIDA=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  return 0
}

_chamadas() { _harness_contar "$2" "$1/chamadas"; } # <base> <trecho>

# _saida_nula <base> — a saida padrao com o byte nulo trocado por `|`: variavel
# de shell nao carrega o nulo, e a leitura comum pararia no primeiro registro.
_saida_nula() { tr '\0' '|' <"$1/out"; }

_nenhuma_chamada() { # <base> <descricao>
  assert_arquivo_ausente "$1/chamadas" "$2"
}

# Massa: tres revisoes de /docs/a.txt, da mais recente para a mais antiga.
_entrada_rev() { # <rev> <server_modified> [caminho]
  printf '{"name":"a.txt","path_display":"%s","rev":"%s","size":3,"server_modified":"%s","client_modified":"%s","content_hash":"h%s"}' \
    "${3:-/docs/a.txt}" "$1" "$2" "$2" "$1"
}
REV_C=0000000c3 REV_B=0000000b2 REV_A=0000000a1
REVS_VIVO="{\"is_deleted\":false,\"entries\":[$(_entrada_rev $REV_C 2026-10-05T10:00:00Z),$(_entrada_rev $REV_B 2026-10-01T12:00:00Z),$(_entrada_rev $REV_A 2026-09-20T08:00:00Z)],\"has_more\":false}"
REVS_APAGADO="{\"is_deleted\":true,\"server_deleted\":\"2026-10-06T09:00:00Z\",\"entries\":[$(_entrada_rev $REV_C 2026-10-05T10:00:00Z),$(_entrada_rev $REV_B 2026-10-01T12:00:00Z)],\"has_more\":false}"
META_VIVO='{".tag":"file","name":"a.txt","path_display":"/docs/a.txt","rev":"0000000c3"}'
META_APAGADO='{".tag":"deleted","name":"a.txt","path_display":"/docs/a.txt"}'
RESTAURADO='{"name":"a.txt","path_display":"/docs/a.txt","rev":"0000000d4","size":3,"server_modified":"2026-10-19T10:00:00Z","content_hash":"hd4"}'
F_A='*"path":"/docs/a.txt"*'

_arquivo_vivo() { # <base>
  _regra "$1" files/get_metadata "$F_A" 200 "$META_VIVO"
  _regra "$1" files/list_revisions "$F_A" 200 "$REVS_VIVO"
  _regra "$1" files/restore "$F_A" 200 "$RESTAURADO"
}

# ===========================================================================
# TC-RVS — dbx revisoes (RF-72)
# ===========================================================================

teste_rvs01_lista_tres_revisoes_da_mais_recente_com_campos_de_info() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_revisions "$F_A" 200 "$REVS_VIVO"
  _rodar "$base" revisoes /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "revisoes sai 0; erro: $DBX_ERRO"
  assert_contem $'rev=0000000c3\ncontent_hash=h0000000c3\nclient_modified=2026-10-05T10:00:00Z\nserver_modified=2026-10-05T10:00:00Z' \
    "$DBX_SAIDA" 'campos de info, na ordem de _dbx_cmd_metadado_em'
  [[ $DBX_SAIDA == *"rev=$REV_C"*"rev=$REV_B"*"rev=$REV_A"* ]] ||
    _harness_falhar 'ordem decrescente' "$DBX_SAIDA"
  assert_contem $'apagado=nao' "$DBX_SAIDA" 'apagado'
  assert_contem $'mais=nao' "$DBX_SAIDA" 'mais'
  assert_contem $'total=3' "$DBX_SAIDA" 'total'
  _rodar "$base" revisions /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'o alias revisions e o mesmo comando'
}

teste_rvs02_limite_fora_da_faixa_e_uso_invalido_sem_rede() {
  local base valor
  base=$(_ambiente)
  for valor in 0 101 abc ''; do
    _rodar "$base" revisoes --limite "$valor" /docs/a.txt
    assert_igual 2 "$DBX_ESTADO" "limite [$valor] e uso invalido"
    assert_contem 'limite invalido' "$DBX_ERRO" 'nomeia o limite'
  done
  _rodar "$base" revisoes --limit
  assert_igual 2 "$DBX_ESTADO" '--limit sem valor'
  _rodar "$base" revisoes
  assert_igual 2 "$DBX_ESTADO" 'sem caminho'
  _rodar "$base" revisoes /a /b
  assert_igual 2 "$DBX_ESTADO" 'dois caminhos'
  _nenhuma_chamada "$base" 'nenhuma chamada antes de validar'
}

teste_rvs03_limite_explicito_no_corpo_padrao_dez() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_revisions "$F_A" 200 "$REVS_VIVO"
  _rodar "$base" revisoes /docs/a.txt
  assert_igual 1 "$(_chamadas "$base" '"limit":10[,}]')" 'limite padrao 10 explicito'
  assert_igual 1 "$(_chamadas "$base" '"mode":"path"')" 'modo path por padrao'
  _rodar "$base" revisoes --limit 100 /docs/a.txt
  assert_igual 1 "$(_chamadas "$base" '"limit":100')" 'limite dado repassado'
  assert_igual 2 "$(_chamadas "$base" 'files/list_revisions')" 'uma chamada por execucao, sem paginar'
}

teste_rvs04_por_id_envia_modo_id_e_omite_revisao_fora_da_raiz() {
  local base revs
  base=$(_ambiente /docs)
  revs="{\"is_deleted\":false,\"entries\":[$(_entrada_rev $REV_C 2026-10-05T10:00:00Z),$(_entrada_rev $REV_B 2026-10-01T12:00:00Z /fora/a.txt)],\"has_more\":false}"
  _regra "$base" files/list_revisions "$F_A" 200 "$revs"
  _rodar "$base" revisoes --by-id /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "por id sai 0: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '"mode":"id"')" 'modo id no corpo'
  assert_nao_contem '/fora/a.txt' "$DBX_SAIDA" 'revisao fora da raiz nao e listada'
  assert_contem 'omitidas=1' "$DBX_SAIDA" 'diz quantas foram omitidas'
  assert_contem 'total=1' "$DBX_SAIDA" 'total so das listadas'
}

teste_rvs05_fora_da_raiz_e_caminho_recusado_sem_chamada() {
  local base
  base=$(_ambiente /docs)
  _rodar "$base" revisoes /outra/a.txt
  assert_igual 13 "$DBX_ESTADO" 'fora da raiz'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_rvs06_arquivo_apagado_lista_com_apagado_sim_e_data() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_revisions "$F_A" 200 "$REVS_APAGADO"
  _rodar "$base" revisoes /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'apagado lista'
  assert_contem 'apagado=sim' "$DBX_SAIDA" 'apagado sim'
  assert_contem 'apagado_em=2026-10-06T09:00:00Z' "$DBX_SAIDA" 'data da exclusao'
  assert_contem 'total=2' "$DBX_SAIDA" 'revisoes anteriores listadas'
}

teste_rvs07_pasta_e_uso_invalido_com_orientacao_e_inexistente_e_4() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_revisions '*"/pasta"*' 409 '{"error_summary":"path/not_file/."}'
  _regra "$base" files/list_revisions '*"/nada"*' 409 '{"error_summary":"path/not_found/."}'
  _rodar "$base" revisoes /pasta
  assert_igual 2 "$DBX_ESTADO" 'pasta e uso invalido'
  assert_contem 'revisoes existem so para arquivos' "$DBX_ERRO" 'mensagem'
  assert_contem 'dbx restaurar' "$DBX_ERRO" 'orienta para pasta apagada'
  _rodar "$base" revisoes /nada
  assert_igual 4 "$DBX_ESTADO" 'inexistente'
}

teste_rvs08_null_preserva_nome_com_quebra_e_so_leitura() {
  local base revs
  base=$(_ambiente)
  revs='{"is_deleted":false,"entries":[{"name":"a\nb.txt","path_display":"/docs/a\nb.txt","rev":"0000000c3","size":1}],"has_more":false}'
  _regra "$base" files/list_revisions '*' 200 "$revs"
  _rodar "$base" --json --null revisoes /docs/x.txt
  assert_igual 0 "$DBX_ESTADO" "null sai 0: $DBX_ERRO"
  assert_contem 'contrato=1|' "$(_saida_nula "$base")" 'versao de contrato'
  assert_contem $'|path_display=/docs/a\nb.txt|' "$(_saida_nula "$base")" 'nome integro com --null'
  assert_igual 0 "$(_chamadas "$base" 'files/restore\|files/delete\|files/upload\|permanently')" 'nenhum endpoint de escrita'
}

# ===========================================================================
# TC-RST — dbx restaurar <arquivo> (RF-73)
# ===========================================================================

teste_rst01_rev_valido_restaura_e_mostra_como_desfazer() {
  local base
  base=$(_ambiente)
  _arquivo_vivo "$base"
  _rodar "$base" restaurar --rev "$REV_B" /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "restaurar sai 0: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" "files/restore .*\"rev\":\"$REV_B\"")" 'restore com o rev'
  assert_igual 1 "$(_chamadas "$base" 'files/restore .*"path":"/docs/a.txt"')" 'restore com o caminho'
  assert_contem 'operacao=restaurar' "$DBX_SAIDA" 'operacao'
  assert_contem "rev_escolhida=$REV_B" "$DBX_SAIDA" 'rev escolhida'
  assert_contem "rev_substituida=$REV_C" "$DBX_SAIDA" 'rev substituida'
  assert_contem 'estava_apagado=nao' "$DBX_SAIDA" 'estava apagado'
  assert_contem "para_desfazer=dbx restaurar /docs/a.txt --rev $REV_C" "$DBX_SAIDA" 'como desfazer'
  assert_contem 'rev=0000000d4' "$DBX_SAIDA" 'metadados do FileMetadata devolvido'
  _rodar "$base" restore --rev "$REV_B" /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'o alias restore e o mesmo comando'
}

teste_rst02_rev_malformado_e_uso_invalido_sem_rede() {
  local base valor
  base=$(_ambiente)
  for valor in 0000000c 0000000C3 00000zz00 '' $'0000000c3\n'; do
    _rodar "$base" restaurar --rev "$valor" /docs/a.txt
    assert_igual 2 "$DBX_ESTADO" "rev [$valor] recusado"
  done
  assert_contem '--rev' "$DBX_ERRO" 'nomeia a opcao'
  _nenhuma_chamada "$base" 'sem rede'
}

teste_rst03_rev_e_antes_de_juntos_sao_uso_invalido() {
  local base
  base=$(_ambiente)
  _rodar "$base" restaurar --rev "$REV_B" --antes-de 2026-10-01 /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'mutuamente exclusivos'
  _rodar "$base" restaurar --before 2026-10-01 --rev "$REV_B" /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'em qualquer ordem'
  assert_contem 'mutuamente exclusivos' "$DBX_ERRO" 'mensagem'
  _nenhuma_chamada "$base" 'sem rede'
}

teste_rst04_arquivo_vivo_sem_selecao_e_uso_invalido() {
  local base
  base=$(_ambiente)
  _arquivo_vivo "$base"
  _rodar "$base" restaurar /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'vivo sem selecao'
  assert_contem 'informe --rev ou --antes-de' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'nenhum restore'
}

teste_rst05_rev_de_outro_arquivo_e_2_sem_restore_atravessando_paginas() {
  local base pagina1 pagina2
  base=$(_ambiente)
  pagina1="{\"is_deleted\":false,\"entries\":[$(_entrada_rev $REV_C 2026-10-05T10:00:00Z)],\"has_more\":true}"
  pagina2="{\"is_deleted\":false,\"entries\":[$(_entrada_rev $REV_B 2026-10-01T12:00:00Z)],\"has_more\":false}"
  _regra "$base" files/get_metadata "$F_A" 200 "$META_VIVO"
  _regra "$base" files/list_revisions "*\"before_rev\":\"$REV_C\"*" 200 "$pagina2"
  _regra "$base" files/list_revisions "$F_A" 200 "$pagina1"
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar --rev 0000000ff /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" 'rev de outro arquivo e uso invalido (QA-B3-01)'
  assert_contem 'nao pertence a /docs/a.txt' "$DBX_ERRO" 'mensagem'
  assert_igual 2 "$(_chamadas "$base" files/list_revisions)" 'percorreu as duas paginas'
  assert_igual 2 "$(_chamadas "$base" '"limit":100')" 'paginas com limit 100'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
}

teste_rst06_antes_de_escolhe_a_mais_recente_ate_o_fim_do_dia_atravessando_pagina() {
  local base pagina1 pagina2
  base=$(_ambiente)
  pagina1="{\"is_deleted\":false,\"entries\":[$(_entrada_rev $REV_C 2026-10-05T10:00:00Z)],\"has_more\":true}"
  pagina2="{\"is_deleted\":false,\"entries\":[$(_entrada_rev $REV_B 2026-10-01T23:59:59Z),$(_entrada_rev $REV_A 2026-09-20T08:00:00Z)],\"has_more\":false}"
  _regra "$base" files/get_metadata "$F_A" 200 "$META_VIVO"
  _regra "$base" files/list_revisions "*\"before_rev\":\"$REV_C\"*" 200 "$pagina2"
  _regra "$base" files/list_revisions "$F_A" 200 "$pagina1"
  _regra "$base" files/restore "$F_A" 200 "$RESTAURADO"
  _rodar "$base" restaurar --antes-de 2026-10-01 /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "antes-de sai 0: $DBX_ERRO"
  assert_contem "rev_escolhida=$REV_B" "$DBX_SAIDA" 'inclusive ate 23:59:59Z'
  assert_igual 1 "$(_chamadas "$base" "files/restore .*$REV_B")" 'restore da escolhida'
  _rodar "$base" restaurar --before 2026-10-01T23:59:58Z /docs/a.txt
  assert_contem "rev_escolhida=$REV_A" "$DBX_SAIDA" 'carimbo exato e comparado'
}

teste_rst07_antes_de_anterior_a_toda_revisao_e_4() {
  local base
  base=$(_ambiente)
  _arquivo_vivo "$base"
  _rodar "$base" restaurar --antes-de 2020-01-01 /docs/a.txt
  assert_igual 4 "$DBX_ESTADO" 'nenhuma revisao ate a data'
  assert_contem 'nenhuma revisao ate 2020-01-01' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
}

teste_rst08_datas_invalidas_sao_uso_invalido_sem_rede() {
  local base valor
  base=$(_ambiente)
  for valor in 2026-13-01 2026-02-30 2026-10-01T10:00:00-03:00 2026-10-01T24:00:00Z ontem '' 2026-1-1; do
    _rodar "$base" restaurar --antes-de "$valor" /docs/a.txt
    assert_igual 2 "$DBX_ESTADO" "data [$valor] recusada"
  done
  _rodar "$base" restaurar --antes-de 2023-02-29 /docs/a.txt
  assert_igual 2 "$DBX_ESTADO" '29 de fevereiro fora de ano bissexto'
  _nenhuma_chamada "$base" 'sem rede'
  _regra "$base" files/get_metadata '*' 409 '{"error_summary":"path/not_found/."}'
  _rodar "$base" restaurar --antes-de 2024-02-29 /nada
  assert_igual 4 "$DBX_ESTADO" '29 de fevereiro de ano bissexto e aceito'
}

teste_rst09_arquivo_apagado_sem_selecao_restaura_a_ultima() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_metadata "$F_A" 200 "$META_APAGADO"
  _regra "$base" files/list_revisions "$F_A" 200 "$REVS_APAGADO"
  _regra "$base" files/restore "$F_A" 200 "$RESTAURADO"
  _rodar "$base" restaurar /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" "apagado sai 0: $DBX_ERRO"
  assert_contem 'estava_apagado=sim' "$DBX_SAIDA" 'estava apagado'
  assert_contem $'rev_substituida=\n' "$DBX_SAIDA" 'rev substituida vazio'
  assert_contem "rev_escolhida=$REV_C" "$DBX_SAIDA" 'ultima revisao'
  assert_igual 1 "$(_chamadas "$base" "files/restore .*$REV_C")" 'restore da ultima'
  assert_igual 1 "$(_chamadas "$base" 'files/get_metadata .*"include_deleted":true')" 'get_metadata com include_deleted'
}

teste_rst10_rev_igual_ao_vigente_e_ja_atual_sem_restore() {
  local base
  base=$(_ambiente)
  _arquivo_vivo "$base"
  _rodar "$base" restaurar --rev "$REV_C" /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'ja atual sai 0'
  assert_contem 'situacao=ja_atual' "$DBX_SAIDA" 'situacao'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
}

teste_rst11_dry_run_so_le() {
  local base
  base=$(_ambiente)
  _arquivo_vivo "$base"
  _rodar "$base" --dry-run restaurar --rev "$REV_A" /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'simulacao sai 0'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulado'
  assert_contem "rev_escolhida=$REV_A" "$DBX_SAIDA" 'escolhida'
  assert_contem "rev_substituida=$REV_C" "$DBX_SAIDA" 'substituida'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
}

teste_rst12_fora_da_raiz_e_13_sem_chamada() {
  local base
  base=$(_ambiente /docs)
  _rodar "$base" restaurar --rev "$REV_B" /outra/a.txt
  assert_igual 13 "$DBX_ESTADO" 'fora da raiz'
  _rodar "$base" restaurar --rev "$REV_B" /docs/../outra/a.txt
  assert_igual 13 "$DBX_ESTADO" 'subida para fora da raiz'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_rst13_erros_do_restore_pela_taxonomia() {
  local base resumo esperado par
  for par in 'path/invalid_revision/.=4' 'path_write/conflict/file/.=7' \
    'path_write/insufficient_space/.=12' 'path_write/no_write_permission/.=6' \
    'path_write/team_folder/.=6' 'path_lookup/locked/.=7' 'in_progress/.=14'; do
    resumo=${par%=*} esperado=${par##*=}
    base=$(_ambiente)
    _regra "$base" files/get_metadata "$F_A" 200 "$META_VIVO"
    _regra "$base" files/list_revisions "$F_A" 200 "$REVS_VIVO"
    _regra "$base" files/restore '*' 409 "{\"error_summary\":\"$resumo\"}"
    _rodar "$base" restaurar --rev "$REV_B" /docs/a.txt
    assert_igual "$esperado" "$DBX_ESTADO" "restore recusado com $resumo"
  done
  # in_progress e repetido (DIV-58) antes de virar 14.
  assert_igual 2 "$(_chamadas "$base" files/restore)" 'in_progress repetido ate o teto de tentativas'
}

teste_rst14_json_e_null_coerentes_com_info() {
  local base
  base=$(_ambiente)
  _arquivo_vivo "$base"
  _rodar "$base" --json --null restaurar --rev "$REV_B" /docs/a.txt
  assert_igual 0 "$DBX_ESTADO" 'json null'
  assert_contem 'contrato=1|operacao=restaurar|caminho=/docs/a.txt|' "$(_saida_nula "$base")" 'registros com terminador nulo'
  assert_contem '|path_display=/docs/a.txt|' "$(_saida_nula "$base")" 'metadados com os nomes de info'
}

teste_rst_raiz_e_pasta_viva_sao_uso_invalido() {
  local base
  base=$(_ambiente)
  _rodar "$base" restaurar /
  assert_igual 2 "$DBX_ESTADO" 'a raiz nao e alvo'
  _nenhuma_chamada "$base" 'raiz recusada sem rede'
  _regra "$base" files/get_metadata '*' 200 '{".tag":"folder","name":"p","path_display":"/p"}'
  _rodar "$base" restaurar /p
  assert_igual 2 "$DBX_ESTADO" 'pasta viva'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
  _regra_antes "$base" files/get_metadata '*"/nada"*' 409 '{"error_summary":"path/not_found/."}'
  _rodar "$base" restaurar /nada
  assert_igual 4 "$DBX_ESTADO" 'inexistente'
}

# ===========================================================================
# TC-RPA — dbx restaurar <pasta apagada> (RF-74)
# ===========================================================================

# Pasta apagada /p com: x.txt (apagado), sub/ (pasta apagada) com y.txt e
# z.txt (apagados), viva.txt (vivo, nao tocado) e w/ (pasta viva) vazia.
_pasta_apagada() { # <base>
  local base=$1
  _regra "$base" files/get_metadata '*"path":"/p"*' 200 '{".tag":"deleted","name":"p","path_display":"/p"}'
  _regra "$base" files/list_revisions '*"path":"/p"*' 409 '{"error_summary":"path/not_file/."}'
  _regra "$base" files/list_revisions '*"path":"/p/sub"*' 409 '{"error_summary":"path/not_file/."}'
  _regra "$base" files/list_folder '*"path":"/p"*' 200 \
    '{"entries":[{".tag":"deleted","name":"x.txt","path_display":"/p/x.txt"},{".tag":"deleted","name":"sub","path_display":"/p/sub"},{".tag":"file","name":"viva.txt","path_display":"/p/viva.txt","rev":"0000000aa"},{".tag":"folder","name":"w","path_display":"/p/w"}],"has_more":false}'
  _regra "$base" files/list_folder '*"path":"/p/sub"*' 200 \
    '{"entries":[{".tag":"deleted","name":"z.txt","path_display":"/p/sub/z.txt"},{".tag":"deleted","name":"Y.txt","path_display":"/p/sub/Y.txt"}],"has_more":false}'
  _regra "$base" files/list_folder '*"path":"/p/w"*' 200 '{"entries":[],"has_more":false}'
  local item
  for item in /p/x.txt /p/sub/Y.txt /p/sub/z.txt; do
    _regra "$base" files/list_revisions "*\"path\":\"$item\"*" 200 \
      "{\"is_deleted\":true,\"server_deleted\":\"2026-10-10T00:00:00Z\",\"entries\":[$(_entrada_rev 0000000e5 2026-10-09T00:00:00Z "$item")],\"has_more\":false}"
  done
}

teste_rpa01_tres_arquivos_em_dois_niveis() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 0 "$DBX_ESTADO" "pasta restaurada: $DBX_ERRO"
  assert_igual 3 "$(_chamadas "$base" files/restore)" 'tres restore'
  assert_igual 3 "$(_chamadas "$base" 'files/list_revisions .*\.txt".*"limit":1[,}]')" 'list_revisions limit 1 por arquivo'
  assert_contem 'restaurados=3' "$DBX_SAIDA" 'resumo'
  assert_contem 'falhas=0' "$DBX_SAIDA" 'sem falhas'
  assert_contem 'total=3' "$DBX_SAIDA" 'total'
  [[ $DBX_SAIDA == *'item=/p/sub/Y.txt'*'item=/p/sub/z.txt'*'item=/p/x.txt'* ]] ||
    _harness_falhar 'ordem pela chave sem caixa' "$DBX_SAIDA"
}

teste_rpa02_sem_recursive_e_com_limit_em_toda_listagem() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 3 "$(_chamadas "$base" 'files/list_folder ')" 'tres listagens, um nivel por vez'
  assert_igual 0 "$(_chamadas "$base" '"recursive":true')" 'sem recursive=true'
  assert_igual 3 "$(_chamadas "$base" 'files/list_folder .*"limit":[0-9]')" 'limit explicito'
  assert_igual 3 "$(_chamadas "$base" 'files/list_folder .*"include_deleted":true')" 'include_deleted'
}

teste_rpa03_item_vivo_nao_e_tocado() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 0 "$DBX_ESTADO" 'restaurada'
  assert_igual 0 "$(_chamadas "$base" 'viva.txt')" 'nenhuma chamada sobre o item vivo'
  assert_nao_contem 'viva.txt' "$DBX_SAIDA" 'o vivo nao e item'
}

teste_rpa04_falha_de_item_segue_e_sai_14() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _regra "$base" files/restore '*"/p/sub/Y.txt"*' 409 '{"error_summary":"path/invalid_revision/."}'
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 14 "$DBX_ESTADO" 'falha de item sai 14'
  assert_igual 3 "$(_chamadas "$base" files/restore)" 'os demais seguem'
  assert_contem 'restaurados=2' "$DBX_SAIDA" 'dois restaurados'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'uma falha'
  assert_contem 'falha=/p/sub/Y.txt: nao_encontrado' "$DBX_SAIDA" 'linha do item com o motivo'
}

teste_rpa05_travessia_parcial_sai_14_com_o_que_faltou() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"path":"/p/sub"*' REDE ''
  _pasta_apagada "$base"
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 14 "$DBX_ESTADO" 'travessia parcial sai 14'
  assert_igual 1 "$(_chamadas "$base" files/restore)" 'restaura o que foi percorrido'
  assert_contem 'pasta_nao_percorrida=/p/sub: rede' "$DBX_SAIDA" 'diz o que faltou'
}

teste_rpa06_dry_run_lista_sem_restore() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _rodar "$base" --dry-run restaurar /p
  assert_igual 0 "$DBX_ESTADO" 'simulacao sai 0'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
  assert_contem $'item=/p/x.txt\nrev=0000000e5\napagado_em=2026-10-10T00:00:00Z\nresultado=simulado' \
    "$DBX_SAIDA" 'item com rev e apagado_em'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'resumo simulado'
}

teste_rpa07_reexecucao_restaura_so_o_que_falta() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  # Segunda execucao: x.txt e sub/Y.txt ja voltaram (vivos); so z.txt segue apagado.
  _rodar "$base" restaurar /p
  assert_igual 0 "$DBX_ESTADO" 'primeira execucao'
  rm -f "$base/chamadas"
  _regra_antes "$base" files/list_folder '*"path":"/p/sub"*' 200 \
    '{"entries":[{".tag":"deleted","name":"z.txt","path_display":"/p/sub/z.txt"},{".tag":"file","name":"Y.txt","path_display":"/p/sub/Y.txt"}],"has_more":false}'
  _regra_antes "$base" files/list_folder '*"path":"/p"*' 200 \
    '{"entries":[{".tag":"file","name":"x.txt","path_display":"/p/x.txt"},{".tag":"folder","name":"sub","path_display":"/p/sub"}],"has_more":false}'
  _rodar "$base" restaurar /p
  assert_igual 0 "$DBX_ESTADO" 'reexecucao'
  assert_igual 1 "$(_chamadas "$base" files/restore)" 'so o que segue apagado'
  assert_igual 1 "$(_chamadas "$base" 'files/restore .*/p/sub/z.txt')" 'o que faltava'
  assert_igual 0 "$(_chamadas "$base" 'files/restore .*/p/x.txt')" 'o restaurado nao e tocado'
}

teste_rpa08_rev_ou_antes_de_com_pasta_e_uso_invalido() {
  local base
  base=$(_ambiente)
  _pasta_apagada "$base"
  _rodar "$base" restaurar --rev "$REV_B" /p
  assert_igual 2 "$DBX_ESTADO" '--rev com pasta'
  _rodar "$base" restaurar --antes-de 2026-10-01 /p
  assert_igual 2 "$DBX_ESTADO" '--antes-de com pasta'
  assert_contem 'pasta nao tem revisao' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_chamadas "$base" files/restore)" 'zero restore'
}

teste_rpa09_item_fora_da_raiz_nunca_e_restaurado() {
  local base
  base=$(_ambiente /p)
  _pasta_apagada "$base"
  _regra_antes "$base" files/list_folder '*"path":"/p/w"*' 200 \
    '{"entries":[{".tag":"deleted","name":"e.txt","path_display":"/fora/e.txt"}],"has_more":false}'
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 0 "$(_chamadas "$base" '/fora/e.txt')" 'nenhuma chamada com o caminho de fora'
  assert_igual 14 "$DBX_ESTADO" 'o item recusado conta como falha'
  assert_contem 'falha=/fora/e.txt: caminho_recusado' "$DBX_SAIDA" 'motivo'
}

teste_rpa_div78_item_fora_da_pasta_pedida_e_falha_mesmo_dentro_da_raiz() {
  local base
  base=$(_ambiente /)
  _pasta_apagada "$base"
  _regra_antes "$base" files/list_folder '*"path":"/p/w"*' 200 \
    '{"entries":[{".tag":"deleted","name":"o.txt","path_display":"/outra/o.txt"},{".tag":"deleted","name":"q.txt","path_display":"/P/w/../../pq/q.txt"},{".tag":"deleted","name":"r.txt","path_display":"/p2/r.txt"}],"has_more":false}'
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  _rodar "$base" restaurar /p
  assert_igual 14 "$DBX_ESTADO" 'item fora da pasta pedida leva a 14'
  assert_igual 0 "$(_chamadas "$base" '/outra/o.txt\|pq/q.txt\|/p2/r.txt')" 'nunca sondado nem restaurado'
  assert_igual 3 "$(_chamadas "$base" files/restore)" 'so os de dentro da pasta'
  assert_contem 'falhas=3' "$DBX_SAIDA" 'tres falhas'
  assert_contem 'falha=/outra/o.txt: caminho_recusado' "$DBX_SAIDA" 'motivo'
}

teste_rpa10_term_no_meio_sai_14_com_resumo_parcial_e_tmpdir_limpo() {
  local base tmp
  base=$(_ambiente)
  tmp=$(mktemp -d "$DBX_TESTES_TMP/tmpdir.XXXXXX")
  _pasta_apagada "$base"
  _regra "$base" files/restore '*"/p/sub/z.txt"*' TERM ''
  _regra "$base" files/restore '*' 200 "$RESTAURADO"
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$tmp" bash "$DBX_EXEC" restaurar /p \
    </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  assert_igual 14 "$DBX_ESTADO" 'sinal sai 14'
  assert_contem 'restauracao interrompida' "$(cat "$base/err")" 'resumo parcial em stderr'
  assert_contem 'restaurados=1' "$(cat "$base/err")" 'o que ja voltou'
  assert_igual '' "$(find "$tmp" -mindepth 1 -print -quit)" 'TMPDIR sem residuo'
}

# ===========================================================================
# TC-LIX — dbx lixeira (RF-75)
# ===========================================================================

LISTA_RAIZ='{"entries":[{".tag":"deleted","name":"a.txt","path_display":"/a.txt","is_restorable":true},{".tag":"file","name":"b.txt","path_display":"/b.txt"},{".tag":"deleted","name":"c","path_display":"/c","is_restorable":false},{".tag":"folder","name":"d","path_display":"/d"},{".tag":"deleted","name":"e","path_display":"/e"}],"has_more":false}'

teste_lix01_so_apagados_com_restauravel() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*' 200 "$LISTA_RAIZ"
  _rodar "$base" lixeira /
  assert_igual 0 "$DBX_ESTADO" "lixeira sai 0: $DBX_ERRO"
  assert_contem $'tipo=apagado\nname=a.txt\npath_display=/a.txt\nrestauravel=sim' "$DBX_SAIDA" 'item restauravel'
  assert_contem $'path_display=/c\nrestauravel=nao' "$DBX_SAIDA" 'nao restauravel'
  assert_contem $'path_display=/e\nrestauravel=\n' "$DBX_SAIDA" 'sem informacao fica vazio'
  assert_nao_contem 'b.txt' "$DBX_SAIDA" 'vivo nao aparece'
  assert_contem 'total=3' "$DBX_SAIDA" 'total'
  _rodar "$base" trash /
  assert_igual 0 "$DBX_ESTADO" 'o alias trash e o mesmo comando'
}

teste_lix02_sem_argumento_usa_a_raiz_remota() {
  local base
  base=$(_ambiente /docs)
  _regra "$base" files/list_folder '*' 200 '{"entries":[],"has_more":false}'
  _rodar "$base" lixeira
  assert_igual 0 "$DBX_ESTADO" 'sem argumento'
  assert_igual 1 "$(_chamadas "$base" 'files/list_folder .*"path":"/docs"')" 'lista a raiz remota'
}

teste_lix03_recursivo_desce_um_nivel_por_vez() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"path":"/d"*' 200 \
    '{"entries":[{".tag":"deleted","name":"f.txt","path_display":"/d/f.txt"}],"has_more":true,"cursor":"CUR1"}'
  _regra "$base" files/list_folder/continue '*CUR1*' 200 \
    '{"entries":[{".tag":"deleted","name":"g.txt","path_display":"/d/g.txt"}],"has_more":false}'
  _regra "$base" files/list_folder '*' 200 "$LISTA_RAIZ"
  _rodar "$base" lixeira -R /
  assert_igual 0 "$DBX_ESTADO" "recursivo: $DBX_ERRO"
  assert_contem 'path_display=/d/f.txt' "$DBX_SAIDA" 'desce na pasta viva'
  assert_contem 'path_display=/d/g.txt' "$DBX_SAIDA" 'pagina por cursor'
  assert_contem 'total=5' "$DBX_SAIDA" 'total'
  assert_igual 0 "$(_chamadas "$base" '"recursive":true')" 'sem recursive=true'
  _rodar "$base" lixeira --recursive /
  assert_igual 0 "$DBX_ESTADO" '--recursive'
}

teste_lix04_include_deleted_e_limit_explicito() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*' 200 "$LISTA_RAIZ"
  _rodar "$base" lixeira --limite 7 /
  assert_igual 1 "$(_chamadas "$base" 'files/list_folder .*"limit":7')" 'limit explicito'
  assert_igual 1 "$(_chamadas "$base" '"include_deleted":true')" 'include_deleted'
  assert_igual 1 "$(_chamadas "$base" '"include_restorable_info":true')" 'include_restorable_info'
  _rodar "$base" lixeira --limit 0 /
  assert_igual 2 "$DBX_ESTADO" 'limite fora da faixa'
}

teste_lix05_lixeira_vazia_sai_0_com_total_0() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*' 200 '{"entries":[{".tag":"file","name":"b","path_display":"/b"}],"has_more":false}'
  _rodar "$base" lixeira /
  assert_igual 0 "$DBX_ESTADO" 'vazia'
  assert_igual $'contrato=1\ntotal=0\n' "$DBX_SAIDA" 'so o total'
}

teste_lix06_fora_da_raiz_arquivo_e_inexistente() {
  local base
  base=$(_ambiente /docs)
  _rodar "$base" lixeira /outra
  assert_igual 13 "$DBX_ESTADO" 'fora da raiz'
  _nenhuma_chamada "$base" 'sem chamada'
  _regra "$base" files/list_folder '*"/docs/arq"*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/list_folder '*"/docs/nada"*' 409 '{"error_summary":"path/not_found/."}'
  _rodar "$base" lixeira /docs/arq
  assert_igual 2 "$DBX_ESTADO" 'arquivo'
  _rodar "$base" lixeira /docs/nada
  assert_igual 4 "$DBX_ESTADO" 'inexistente'
}

teste_lix07_json_null_e_nenhuma_escrita() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*' 200 "$LISTA_RAIZ"
  _rodar "$base" --json --null lixeira /
  assert_igual 0 "$DBX_ESTADO" 'json null'
  assert_contem 'contrato=1|tipo=apagado|name=a.txt|' "$(_saida_nula "$base")" 'registros nulos'
  assert_igual 0 "$(_chamadas "$base" 'files/restore\|files/delete\|files/upload\|permanently')" 'nenhuma escrita'
}

# ===========================================================================
# TC-EXP — dbx lixeira --excluir (RF-76; DIV-54, DIV-55)
# ===========================================================================

APAGADO_X='{".tag":"deleted","name":"x.txt","path_display":"/x.txt","path_lower":"/x.txt"}'

_exclusao() { # <base> [metadado]
  _regra "$1" files/get_metadata '*"path":"/x.txt"*' 200 "${2:-$APAGADO_X}"
  _regra "$1" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$1" files/permanently_delete '*"path":"/x.txt"*' 200 'null'
}

teste_exp01_item_apagado_confirmado_e_expurgado() {
  local base
  base=$(_ambiente)
  _exclusao "$base"
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 0 "$DBX_ESTADO" "expurgo: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" 'files/get_metadata .*"include_deleted":true')" 'guarda pela API'
  assert_igual 1 "$(_chamadas "$base" files/permanently_delete)" 'expurgo chamado'
  assert_contem $'operacao=excluir_permanente\ncaminho=/x.txt\nresultado=expurgado' "$DBX_SAIDA" 'saida'
  local ordem
  ordem=$(grep -n 'files/' "$base/chamadas" | grep -E 'get_metadata|permanently' | cut -d: -f2 | cut -d' ' -f1 | tr '\n' ' ')
  assert_igual 'files/get_metadata files/permanently_delete ' "$ordem" 'checagem antes do expurgo'
  _rodar "$base" trash --purge /x.txt --confirmar-caminho /x.txt
  assert_igual 0 "$DBX_ESTADO" 'aliases trash e --purge'
}

teste_exp02_item_vivo_e_recusado_sem_chamada_destrutiva() {
  local base
  base=$(_ambiente)
  _exclusao "$base" '{".tag":"file","name":"x.txt","path_display":"/x.txt","rev":"0000000c3"}'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 2 "$DBX_ESTADO" 'item vivo'
  assert_contem 'dbx delete' "$DBX_ERRO" 'orienta a apagar antes'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero chamada destrutiva'
  : >"$base/regras"
  _exclusao "$base" '{".tag":"folder","name":"x.txt","path_display":"/x.txt"}'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 2 "$DBX_ESTADO" 'pasta viva'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero chamada destrutiva'
}

teste_exp03_inexistente_e_4() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 409 '{"error_summary":"path/not_found/."}'
  _regra "$base" files/permanently_delete '*' 200 'null'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 4 "$DBX_ESTADO" 'inexistente'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero chamada destrutiva'
}

teste_exp04_sem_confirmacao_e_sem_terminal_e_2_sem_nenhuma_chamada() {
  local base
  base=$(_ambiente)
  _exclusao "$base"
  _rodar "$base" lixeira --excluir /x.txt
  assert_igual 2 "$DBX_ESTADO" 'sem confirmacao e sem terminal'
  assert_contem '--confirmar-caminho' "$DBX_ERRO" 'diz como confirmar'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /y.txt
  assert_igual 2 "$DBX_ESTADO" 'confirmacao diferente do alvo'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho ''
  assert_igual 2 "$DBX_ESTADO" 'confirmacao vazia'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /X.TXT
  assert_igual 2 "$DBX_ESTADO" 'confirmacao identica, inclusive na caixa'
  _nenhuma_chamada "$base" 'zero chamadas, nem a renovacao do token'
}

teste_exp05_com_terminal_o_operador_digita_o_caminho() {
  local base
  base=$(_ambiente)
  _exclusao "$base"
  _rodar_tty "$base" /x.txt lixeira --excluir /x.txt
  assert_igual 0 "$DBX_ESTADO" "caminho digitado certo executa: $DBX_SAIDA"
  assert_igual 1 "$(_chamadas "$base" permanently_delete)" 'expurgado'
  rm -f "$base/chamadas"
  _rodar_tty "$base" /y.txt lixeira --excluir /x.txt
  assert_igual 14 "$DBX_ESTADO" 'caminho errado sai 14'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero chamada destrutiva'
  rm -f "$base/chamadas"
  # Complemento da DIV-55: com terminal e --confirmar-caminho identico, sem pergunta.
  _rodar_tty "$base" /errado lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 0 "$DBX_ESTADO" 'confirmacao por opcao dispensa a pergunta'
  assert_igual 1 "$(_chamadas "$base" permanently_delete)" 'expurgado sem pergunta'
}

teste_exp06_yes_y_e_confirmar_nao_existem_aqui() {
  local base opcao
  base=$(_ambiente)
  _exclusao "$base"
  for opcao in -y --yes --confirmar; do
    _rodar "$base" lixeira --excluir /x.txt "$opcao"
    assert_igual 2 "$DBX_ESTADO" "$opcao recusado"
    assert_contem "opcao nao reconhecida: $opcao" "$DBX_ERRO" 'como opcao nao reconhecida'
  done
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_exp07_dry_run_sem_expurgo_e_sem_pergunta() {
  local base
  base=$(_ambiente)
  _exclusao "$base"
  _rodar "$base" --dry-run lixeira --excluir /x.txt
  assert_igual 0 "$DBX_ESTADO" "simulacao: $DBX_ERRO"
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulado'
  assert_igual 1 "$(_chamadas "$base" get_metadata)" 'a guarda le'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero expurgo'
}

teste_exp08_conta_pessoal_e_permissao_com_remedio() {
  local base corpo
  for corpo in 'Error in call to API function "files/permanently_delete": This API function is only available to Dropbox Business' \
    '{"error_summary":"invalid_account_type/."}'; do
    base=$(_ambiente)
    _regra "$base" files/get_metadata '*' 200 "$APAGADO_X"
    _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
    _regra "$base" files/permanently_delete '*' 400 "$corpo"
    _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_igual 6 "$DBX_ESTADO" "conta pessoal: $corpo"
    assert_contem 'so existe em contas Dropbox Business' "$DBX_ERRO" 'mensagem'
    assert_contem 'dbx delete' "$DBX_ERRO" 'remedio'
  done
}

teste_exp09_escopo_ausente_e_autenticacao_com_remedio() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 "$APAGADO_X"
  _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/permanently_delete '*' 401 \
    '{"error_summary":"missing_scope/..","error":{".tag":"missing_scope","required_scope":"files.permanent_delete"}}'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 5 "$DBX_ESTADO" 'escopo ausente'
  assert_contem 'files.permanent_delete' "$DBX_ERRO" 'nomeia o escopo'
  assert_contem 'App Console' "$DBX_ERRO" 'remedio do console'
  assert_contem 'dbx unlink' "$DBX_ERRO" 'reautorizar: unlink (DIV-56)'
  assert_contem 'dbx config' "$DBX_ERRO" 'seguido de config'
}

teste_exp10_fora_da_raiz_e_a_propria_raiz() {
  local base alvo
  base=$(_ambiente /docs)
  _rodar "$base" lixeira --excluir /outra/x --confirmar-caminho /outra/x
  assert_igual 13 "$DBX_ESTADO" 'fora da raiz'
  for alvo in /docs /DOCS /docs/ /docs/sub/..; do
    _rodar "$base" lixeira --excluir "$alvo" --confirmar-caminho "$alvo"
    assert_igual 2 "$DBX_ESTADO" "a propria raiz: $alvo"
  done
  assert_contem 'alvo e a raiz' "$DBX_ERRO" 'mensagem'
  _nenhuma_chamada "$base" 'zero chamadas'
  base=$(_ambiente /)
  _rodar "$base" lixeira --excluir / --confirmar-caminho /
  assert_igual 2 "$DBX_ESTADO" 'a raiz da conta'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_exp11_excluir_com_pasta_posicional_e_2() {
  local base
  base=$(_ambiente)
  _rodar "$base" lixeira /p --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 2 "$DBX_ESTADO" 'pasta posicional junto'
  assert_contem 'nao aceita pasta' "$DBX_ERRO" 'mensagem'
  _rodar "$base" lixeira --excluir /x.txt --excluir /y.txt --confirmar-caminho /x.txt
  assert_igual 2 "$DBX_ESTADO" 'dois alvos'
  _rodar "$base" lixeira --confirmar-caminho /x.txt
  assert_igual 2 "$DBX_ESTADO" 'confirmacao sem exclusao'
  _rodar "$base" lixeira --excluir
  assert_igual 2 "$DBX_ESTADO" '--excluir sem valor'
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_exp12_aviso_de_irreversibilidade_em_stderr() {
  local base
  base=$(_ambiente)
  _exclusao "$base"
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_contem 'exclusao PERMANENTE e irreversivel: /x.txt nao podera ser restaurado' "$DBX_ERRO" 'aviso'
  assert_nao_contem 'PERMANENTE' "$DBX_SAIDA" 'aviso fora da saida padrao'
}

teste_exp13_too_many_write_operations_e_repetido() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 "$APAGADO_X"
  _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/permanently_delete '*' 429 '{"error_summary":"too_many_write_operations/."}' uma
  _regra "$base" files/permanently_delete '*' 200 'null'
  _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 0 "$DBX_ESTADO" "retentativa de RNF-07: $DBX_ERRO"
  assert_igual 2 "$(_chamadas "$base" permanently_delete)" 'duas tentativas'
}

teste_exp14_sentinelas_ausentes_de_toda_saida() {
  local base sentinela
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 "$APAGADO_X"
  _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/permanently_delete '*' 409 '{"error_summary":"path_write/too_many_files/."}'
  _rodar "$base" --debug lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual 14 "$DBX_ESTADO" 'too_many_files sai 14 (DIV-58)'
  assert_contem 'o item continua na lixeira' "$DBX_ERRO" 'falha do expurgo diz o estado'
  for sentinela in "$SENTINELA_REFRESH" "$SENTINELA_SEGREDO" "$SENTINELA_CHAVE" "$SENTINELA_TOKEN"; do
    assert_segredo_ausente "$sentinela" "$DBX_SAIDA$DBX_ERRO" 'nenhum segredo em saida alguma'
  done
}

teste_exp_pasta_apagada_avisa_a_contagem() {
  local base
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 '{".tag":"deleted","name":"p","path_display":"/p","path_lower":"/p"}'
  _regra "$base" files/list_folder '*"path":"/p"*' 200 \
    '{"entries":[{".tag":"deleted","name":"a","path_display":"/p/a"},{".tag":"deleted","name":"b","path_display":"/p/b"}],"has_more":false}'
  _regra "$base" files/permanently_delete '*' 200 'null'
  _rodar "$base" --dry-run lixeira --excluir /p
  assert_igual 0 "$DBX_ESTADO" 'pasta simulada'
  assert_contem '2 item(ns) apagado(s)' "$DBX_ERRO" 'contagem no aviso'
}

# QA-B3-02 (seguranca): a guarda so autoriza com `path_lower` presente e igual
# ao alvo normalizado, dobrado so no ASCII; senao 10, sem expurgo.
teste_exp_guarda_exige_path_lower_do_proprio_alvo() {
  local base meta
  for meta in '{".tag":"deleted","path_display":"/outra/y.txt"}' \
    '{".tag":"deleted","path_display":"/x.txt"}' \
    '{".tag":"deleted","path_display":"/x.txt","path_lower":""}' \
    '{".tag":"deleted","path_display":"/x.txt","path_lower":"/outra/y.txt"}' \
    '{".tag":"deleted","path_display":"/x.txt","path_lower":"/x.txt/y"}'; do
    base=$(_ambiente)
    _exclusao "$base" "$meta"
    _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_igual 10 "$DBX_ESTADO" "guarda recusa: $meta"
    assert_igual 0 "$(_chamadas "$base" permanently_delete)" "zero expurgo: $meta"
  done
  # Caixa diferente so no ASCII: o mesmo item, passa.
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 '{".tag":"deleted","path_display":"/Docs/X.txt","path_lower":"/docs/x.txt"}'
  _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/permanently_delete '*' 200 'null'
  _rodar "$base" lixeira --excluir /Docs/X.txt --confirmar-caminho /Docs/X.txt
  assert_igual 0 "$DBX_ESTADO" "caixa ASCII passa: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" permanently_delete)" 'expurgado'
  # Caixa diferente fora do ASCII: recusa, e a mensagem nao leva byte de controle cru.
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 '{".tag":"deleted","path_display":"/\u00c9.txt","path_lower":"/\u00e9.txt\u001b"}'
  _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/permanently_delete '*' 200 'null'
  _rodar "$base" lixeira --excluir $'/\xc3\x89.txt' --confirmar-caminho $'/\xc3\x89.txt'
  assert_igual 10 "$DBX_ESTADO" 'caixa nao ASCII recusa'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero expurgo'
  assert_nao_contem $'\e' "$DBX_ERRO" 'sem byte de controle cru'
  base=$(_ambiente)
  _regra "$base" files/get_metadata '*' 200 '{".tag":"deleted","path_display":"/\u00c9.txt","path_lower":"/\u00e9.txt"}'
  _regra "$base" files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _regra "$base" files/permanently_delete '*' 200 'null'
  _rodar "$base" lixeira --excluir $'/\xc3\x89.txt' --confirmar-caminho $'/\xc3\x89.txt'
  assert_igual 10 "$DBX_ESTADO" 'caixa nao ASCII sem controle tambem recusa'
  assert_igual 0 "$(_chamadas "$base" permanently_delete)" 'zero expurgo'
}

# QA-B3-04 e QA-B3-05: U+0000 e campo duplicado na resposta da guarda nunca
# autorizam o expurgo; saem 10.
teste_exp_guarda_recusa_u0000_e_campo_duplicado() {
  local base meta
  for meta in '{".tag":"deleted","path_lower":"/x.txt\u0000"}' \
    '{".tag":"deleted","path_lower":"/outra","path_lower":"/x.txt"}' \
    '{".tag":"deleted","path_lower":"/x.txt","path_lower":"/outra"}' \
    '{".tag":"file",".tag":"deleted","path_lower":"/x.txt"}' \
    '{".tag":"deleted",".tag":"file","path_lower":"/x.txt"}' \
    '{".tag":"deleted","path_lower":"/x.txt","path_lower":"/x.txt"}'; do
    base=$(_ambiente)
    _exclusao "$base" "$meta"
    _rodar "$base" lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_igual 10 "$DBX_ESTADO" "guarda recusa: $meta"
    assert_igual 0 "$(_chamadas "$base" permanently_delete)" "zero expurgo: $meta"
  done
}

# _rodar_com_teto <base> <argumentos...> — como `_rodar`, com teto de 20 s.
_rodar_com_teto() {
  local base=$1
  shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    timeout 20 bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  return 0
}

# QA-B3-06: listagem que devolve a propria pasta, um ancestral ou a mesma
# subpasta em outra grafia nao prende a descida.
teste_rpa_qa_b3_06_descida_com_ciclo_termina_e_lista_cada_pasta_uma_vez() {
  local base entrada
  for entrada in '{".tag":"folder","name":"p","path_display":"/p"}' \
    '{".tag":"deleted","name":"p","path_display":"/P/"}' \
    '{".tag":"folder","name":"w","path_display":"/P/W"},{".tag":"folder","name":"w","path_display":"/p/w/"}'; do
    base=$(_ambiente)
    _pasta_apagada "$base"
    _regra_antes "$base" files/list_folder '*"path":"/p/w"*' 200 \
      '{"entries":[{".tag":"folder","name":"w","path_display":"/p/w"},{".tag":"folder","name":"p","path_display":"/p"}],"has_more":false}'
    _regra_antes "$base" files/list_folder '*"path":"/p"*' 200 \
      "{\"entries\":[{\".tag\":\"deleted\",\"name\":\"x.txt\",\"path_display\":\"/p/x.txt\"},{\".tag\":\"folder\",\"name\":\"w\",\"path_display\":\"/p/w\"},$entrada],\"has_more\":false}"
    _regra "$base" files/restore '*' 200 "$RESTAURADO"
    _rodar_com_teto "$base" restaurar /p
    assert_diferente 124 "$DBX_ESTADO" "descida termina com [$entrada]"
    assert_igual 0 "$DBX_ESTADO" "sem falha com [$entrada]: $DBX_SAIDA"
    assert_igual 1 "$(_chamadas "$base" 'files/list_folder {"limit":100,"path":"/p",')" "/p listada uma vez [$entrada]"
    assert_igual 1 "$(_chamadas "$base" 'files/list_folder .*"path":"/p/w"')" "/p/w listada uma vez [$entrada]"
    assert_igual 1 "$(_chamadas "$base" files/restore)" "x.txt restaurado uma vez [$entrada]"
  done
}

teste_lix_qa_b3_06_recursiva_com_ciclo_termina() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*' 200 \
    '{"entries":[{".tag":"folder","name":"d","path_display":"/d"},{".tag":"folder","name":"D","path_display":"/D/"},{".tag":"folder","name":"e","path_display":"/d/e"},{".tag":"folder","name":"raiz","path_display":"/"},{".tag":"deleted","name":"a","path_display":"/d/a"}],"has_more":false}'
  _rodar_com_teto "$base" lixeira -R /d
  assert_diferente 124 "$DBX_ESTADO" 'lixeira -R termina'
  assert_igual 0 "$DBX_ESTADO" 'sai 0'
  assert_igual 2 "$(_chamadas "$base" files/list_folder)" 'so /d e /d/e, cada uma uma vez'
}

# ===========================================================================
# TC-DOC-02 — ajuda e README (RF-78)
# ===========================================================================

teste_doc02_readme_e_ajuda_citam_escopo_business_e_remedio() {
  local readme ajuda comando texto
  IFS= read -r -d '' readme <"$DBX_HARNESS_RAIZ/README.md" || :
  ajuda=$(env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help lixeira 2>&1)
  for texto in 'files.permanent_delete' 'Dropbox Business' 'dbx unlink' 'App Console'; do
    assert_contem "$texto" "$readme" "README cita: $texto"
    assert_contem "$texto" "$ajuda" "dbx help lixeira cita: $texto"
  done
  assert_contem 'a exclusao permanente e irreversivel e so existe em Dropbox Business' "$ajuda" 'frase de RF-78'
  for comando in revisoes revisions restaurar restore lixeira trash; do
    assert_contem "Uso: dbx " "$(env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help "$comando" 2>&1)" \
      "ajuda especifica de $comando"
  done
  assert_contem 'dbx restaurar <caminho> --rev' \
    "$(env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help restaurar 2>&1)" 'como desfazer'
  ajuda=$(env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help 2>&1)
  for comando in 'revisoes' 'alias: revisions' 'restaurar' 'alias: restore' 'lixeira' 'alias: trash'; do
    assert_contem "$comando" "$ajuda" "dbx help lista $comando"
  done
}

harness_executar "$@"
