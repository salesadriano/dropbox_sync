#!/usr/bin/env bash
# Suite independente do QA, fase 3 do backlog: revisoes, restauracao e lixeira
# com exclusao permanente (F-07, F-20; RF-72..RF-78; DIV-54..DIV-77).
#
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx`, com duplo de `curl`
# proprio (independente do da suite do developer). O foco e a exclusao
# permanente, irreversivel: em todo caso de recusa a prova e o registro de
# chamadas do duplo, que NUNCA pode conter `files/permanently_delete` (e, nas
# recusas anteriores a rede, nao pode conter chamada alguma, nem a renovacao do
# token). A guarda nao pode depender de estado local (memoria
# `guarda-de-seguranca-sem-estado`): os casos rodam com `XDG_STATE_HOME` vazio.
#
# Duplo de `curl`: regras em `$B/regras`, uma por linha,
# `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>resposta[<TAB>uma]` (padroes do
# shell); a primeira que casa responde. Codigos especiais: `REDE` (falha de
# conexao), `TERM` (sinal ao grupo do processo). Toda chamada vai para
# `$B/chamadas` como `endpoint corpo`; chamada sem regra responde 400 e fica
# marcada `SEM_REGRA`.
#
# shellcheck disable=SC2016
# Justificativa: o duplo e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_NAO_ENCONTRADO=$(dbx_errors_codigo_saida nao_encontrado)
QA_CAMINHO=$(dbx_errors_codigo_saida caminho_recusado)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly QA_USO QA_NAO_ENCONTRADO QA_CAMINHO QA_NAO_CONCLUIDA
readonly QA_SENT_SEGREDO='QA-SEGREDO-B3x' QA_SENT_RT='QA-RT-B3x' QA_SENT_TOKEN='QA-TOKEN-B3x' QA_SENT_CHAVE='QA-CHAVE-B3x'

B=''
QA_ESTADO=''
QA_SAIDA=''
QA_ERRO=''
QA_N=0

# _qa_cenario [raiz_remota] — credencial com sentinelas e duplo de rede em $B.
_qa_cenario() {
  local raiz=${1:-/}
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-b3.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"%s"}' \
    "$QA_SENT_CHAVE" "$QA_SENT_SEGREDO" "$QA_SENT_RT" "$raiz" >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  {
    printf '#!%s\nQA=%q\nTOKEN=%q\n' "$BASH" "$B" "$QA_SENT_TOKEN"
    cat <<'FIM'
cat >/dev/null 2>&1
o=''; w=''; ant=''; url=''; dados=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
ep=${url#https://api.dropboxapi.com/2/}
ep=${ep#https://content.dropboxapi.com/2/}
cod=400 corpo='{"error_summary":"sem_regra/"}'
if [[ $url == *oauth2/token* ]]; then
  printf 'oauth2/token\n' >>"$QA/chamadas"
  cod=200 corpo="{\"access_token\":\"$TOKEN\",\"token_type\":\"bearer\",\"expires_in\":14400}"
else
  printf '%s %s\n' "$ep" "$pedido" >>"$QA/chamadas"
  achou=nao n=0
  while IFS=$'\t' read -r rep rfi rco rar rvz; do
    n=$((n + 1))
    [[ -n $rep ]] || continue
    # shellcheck disable=SC2053
    [[ $ep == $rep && $pedido == $rfi ]] || continue
    if [[ $rvz == uma ]]; then
      [[ -e $QA/usada.$n ]] && continue
      : >"$QA/usada.$n"
    fi
    achou=sim cod=$rco corpo=''
    [[ -r $QA/resp/$rar ]] && IFS= read -r -d '' corpo <"$QA/resp/$rar"
    break
  done <"$QA/regras"
  [[ $achou == sim ]] || printf 'SEM_REGRA %s\n' "$ep" >>"$QA/chamadas"
fi
case $cod in
  TERM) kill -TERM 0; sleep 5; exit 1 ;;
  REDE) printf 'curl: (7) Failed to connect\n' >&2; exit 7 ;;
esac
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  chmod +x "$B/bin/curl"
}

# _qa_regra <endpoint> <filtro> <codigo> <corpo> [uma]
_qa_regra() {
  QA_N=$((QA_N + 1))
  printf '%s' "$4" >"$B/resp/r$QA_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$QA_N" "${5:-}" >>"$B/regras"
}

# _qa_rodar <entrada> <argumentos...> — stdin vem do arquivo <entrada>.
_qa_rodar_com() {
  local entrada=$1
  shift
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    bash "$QA_DBX" "$@" <"$entrada" >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  QA_SAIDA='' QA_ERRO=''
  IFS= read -r -d '' QA_SAIDA <"$B/out"
  IFS= read -r -d '' QA_ERRO <"$B/err"
  return 0
}
_qa_rodar() { _qa_rodar_com /dev/null "$@"; }

# _qa_rodar_tty <arquivo_de_entrada> <argumentos...> — stdin num terminal real.
_qa_rodar_tty() {
  local entrada=$1 linha arg
  shift
  command -v script >/dev/null 2>&1 || pular 'script(1) ausente'
  printf -v linha 'bash %q' "$QA_DBX"
  for arg in "$@"; do printf -v arg ' %q' "$arg" && linha+=$arg; done
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" timeout 20 script -qec "$linha" /dev/null <"$entrada" >"$B/out" 2>&1
  QA_ESTADO=$?
  QA_SAIDA=''
  IFS= read -r -d '' QA_SAIDA <"$B/out"
  return 0
}

# _qa_contar <trecho> — linhas de `chamadas` que contem o trecho, por leitura do shell.
_qa_contar() {
  local linha total=0
  if [[ -f $B/chamadas ]]; then
    while IFS= read -r linha || [[ -n $linha ]]; do
      [[ $linha == *"$1"* ]] && total=$((total + 1))
    done <"$B/chamadas"
  fi
  QA_CONTAGEM=$total
}

_qa_sem_expurgo() { # <descricao>
  _qa_contar permanently_delete
  assert_igual 0 "$QA_CONTAGEM" "NENHUM permanently_delete: $1"
}

_qa_sem_chamada() { # <descricao>
  assert_arquivo_ausente "$B/chamadas" "nenhuma chamada, nem renovacao de token: $1"
}

_qa_estado_em() { # <descricao> <codigos aceitos...>
  local descricao=$1 codigo
  shift
  for codigo in "$@"; do
    [[ $QA_ESTADO == "$codigo" ]] && return 0
  done
  _harness_falhar "$descricao" "esperado um de: [$*]" "obtido: [$QA_ESTADO]" "stderr: [$QA_ERRO]"
}

_qa_apagado() { # <path_display> — DeletedMetadata como a API o devolve:
  # `path_lower` e o `path_display` em minusculas (QA-B3-02).
  local LC_ALL=C
  QA_META="{\".tag\":\"deleted\",\"name\":\"x\",\"path_lower\":\"${1,,}\",\"path_display\":\"$1\"}"
}

# Massa padrao do expurgo: /x.txt apagado; o expurgo responderia 200.
_qa_expurgo_padrao() {
  _qa_apagado /x.txt
  _qa_regra files/get_metadata '*' 200 "$QA_META"
  _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _qa_regra files/permanently_delete '*' 200 'null'
}

# ===========================================================================
# Exclusao permanente: o ITEM (RF-76(b)(c), DIV-54)
# ===========================================================================

# QA-B3-E01 — RF-76(c), DIV-54: item vivo, pasta viva com filhos, tag
# desconhecida e corpo sem tag nunca chegam ao expurgo. A massa traz o
# `path_lower` do proprio alvo, para que a decisao seja so a da tag.
teste_qa_e01_item_vivo_ou_tag_estranha_nunca_e_expurgado() {
  local meta
  for meta in '{".tag":"file","name":"x.txt","path_lower":"/x.txt","path_display":"/x.txt","rev":"0000000c3"}' \
    '{".tag":"folder","name":"x.txt","path_lower":"/x.txt","path_display":"/x.txt"}' \
    '{".tag":"Deleted","name":"x.txt","path_lower":"/x.txt","path_display":"/x.txt"}' \
    '{".tag":"deleted ","name":"x.txt","path_lower":"/x.txt","path_display":"/x.txt"}' \
    '{"name":"x.txt","path_lower":"/x.txt","path_display":"/x.txt"}' \
    '[{".tag":"deleted"}]' \
    'nao e json'; do
    _qa_cenario
    _qa_regra files/get_metadata '*' 200 "$meta"
    _qa_regra files/list_folder '*' 200 \
      '{"entries":[{".tag":"file","name":"f","path_display":"/x.txt/f"}],"has_more":false}'
    _qa_regra files/permanently_delete '*' 200 'null'
    _qa_rodar lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_diferente 0 "$QA_ESTADO" "metadado [$meta] nao autoriza o expurgo"
    _qa_sem_expurgo "metadado [$meta]"
  done
}

# QA-B3-E02 — RF-76(b): a raiz da conta e a propria raiz remota, em qualquer
# grafia, sao recusadas sem nenhuma chamada.
teste_qa_e02_raiz_em_qualquer_grafia_e_recusada_sem_rede() {
  local alvo
  _qa_cenario /proj
  _qa_expurgo_padrao
  for alvo in /proj /PROJ /Proj/ /proj/. /proj//. //proj /proj/sub/.. /proj/./ /; do
    _qa_rodar lixeira --excluir "$alvo" --confirmar-caminho "$alvo"
    _qa_estado_em "raiz remota [$alvo]" "$QA_USO" "$QA_CAMINHO"
  done
  _qa_sem_chamada 'raiz remota em toda grafia'
  _qa_cenario /
  _qa_expurgo_padrao
  for alvo in / // /. /./ /a/.. . ''; do
    _qa_rodar lixeira --excluir "$alvo" --confirmar-caminho "$alvo"
    _qa_estado_em "raiz da conta [$alvo]" "$QA_USO" "$QA_CAMINHO"
  done
  _qa_sem_chamada 'raiz da conta em toda grafia'
}

# QA-B3-E03 — RF-76(b), RNF-20(b): fora da raiz remota (subida, prefixo
# enganoso, caixa Unicode, bytes de controle, relativo) sai antes da rede.
teste_qa_e03_fora_da_raiz_e_bytes_hostis_sem_rede() {
  local alvo
  local -a alvos=(/proj/../x /projeto/x /proj2/x /outra/proj/x ../x x.txt ./x
    $'/proj/a\nb' $'/proj/a\tb' $'/proj/a\rb' $'/proj/\e[31mx' $'/proj/a\x7fb')
  _qa_cenario /proj
  _qa_expurgo_padrao
  for alvo in "${alvos[@]}"; do
    _qa_rodar lixeira --excluir "$alvo" --confirmar-caminho "$alvo"
    _qa_estado_em "alvo hostil [${alvo@Q}]" "$QA_USO" "$QA_CAMINHO"
    assert_nao_contem $'\e' "$QA_ERRO" "sem ESC cru no diagnostico [${alvo@Q}]"
  done
  _qa_sem_chamada 'alvos fora da raiz ou com controle'
  # Caixa fora do ASCII: raiz /Ação; /AÇÃO nao e a mesma pasta para o
  # confinamento ASCII e precisa ser recusada (nunca tratada como dentro).
  _qa_cenario /Ação
  _qa_expurgo_padrao
  for alvo in /AÇÃO /AÇÃO/x /ação/../x; do
    _qa_rodar lixeira --excluir "$alvo" --confirmar-caminho "$alvo"
    _qa_estado_em "caixa Unicode [$alvo]" "$QA_USO" "$QA_CAMINHO"
  done
  _qa_sem_chamada 'caixa Unicode'
}

# ===========================================================================
# Exclusao permanente: a CONFIRMACAO (RF-76(d), DIV-55, DIV-73)
# ===========================================================================

# QA-B3-E04 — DIV-55/DIV-73: --confirmar-caminho divergente por caixa, barra
# final, barra dupla, normalizacao Unicode (NFD x NFC), espaco ou quebra de
# linha, ou vazio vindo de variavel: 2 sem chamada alguma.
teste_qa_e04_confirmacao_divergente_e_2_sem_rede() {
  local valor vazio=''
  local -a valores=(/X.txt /x.TXT /x.txt/ //x.txt/ /x.txt/. ' /x.txt' '/x.txt ' $'/x.txt\n' /y.txt x.txt "$vazio")
  _qa_cenario
  _qa_expurgo_padrao
  for valor in "${valores[@]}"; do
    _qa_rodar lixeira --excluir /x.txt --confirmar-caminho "$valor"
    assert_igual "$QA_USO" "$QA_ESTADO" "confirmacao divergente [${valor@Q}]"
  done
  # NFC no alvo, NFD na confirmacao (e vice-versa).
  _qa_rodar lixeira --excluir $'/caf\xc3\xa9' --confirmar-caminho $'/cafe\xcc\x81'
  assert_igual "$QA_USO" "$QA_ESTADO" 'NFC x NFD'
  _qa_rodar lixeira --excluir $'/cafe\xcc\x81' --confirmar-caminho $'/caf\xc3\xa9'
  assert_igual "$QA_USO" "$QA_ESTADO" 'NFD x NFC'
  # Confirmacao antes de --excluir, e a ultima confirmacao vale.
  _qa_rodar lixeira --confirmar-caminho /x.txt --confirmar-caminho /y.txt --excluir /x.txt
  assert_igual "$QA_USO" "$QA_ESTADO" 'a ultima confirmacao diverge'
  # A confirmacao igual a raiz nao abre o alvo.
  _qa_rodar lixeira --excluir /x.txt --confirmar-caminho /
  assert_igual "$QA_USO" "$QA_ESTADO" 'confirmacao com a raiz'
  _qa_sem_chamada 'confirmacao divergente'
}

# QA-B3-E05 — DIV-55: nao ha --yes, -y, --confirmar, nem forma com `=`.
teste_qa_e05_atalhos_de_confirmacao_nao_existem() {
  local opcao
  _qa_cenario
  _qa_expurgo_padrao
  for opcao in --yes -y --confirmar --sim -f --force --confirmar-caminho=/x.txt --excluir=/x.txt; do
    _qa_rodar lixeira --excluir /x.txt "$opcao"
    assert_igual "$QA_USO" "$QA_ESTADO" "atalho [$opcao]"
  done
  _qa_rodar lixeira --yes --excluir /x.txt
  assert_igual "$QA_USO" "$QA_ESTADO" '--yes antes de --excluir'
  _qa_sem_chamada 'atalhos de confirmacao'
}

# QA-B3-E06 — DIV-55, RNF-19: stdin que NAO e terminal, mesmo trazendo o
# caminho certo, nao substitui --confirmar-caminho: 2 sem rede.
teste_qa_e06_stdin_nao_terminal_com_dados_nao_confirma() {
  _qa_cenario
  _qa_expurgo_padrao
  printf '/x.txt\n/x.txt\n' >"$B/entrada"
  _qa_rodar_com "$B/entrada" lixeira --excluir /x.txt
  assert_igual "$QA_USO" "$QA_ESTADO" 'pipe com o caminho certo'
  assert_contem '--confirmar-caminho' "$QA_ERRO" 'orienta a confirmacao por opcao'
  _qa_sem_chamada 'stdin nao terminal'
}

# QA-B3-E07 — DIV-55: com terminal, resposta errada, so caixa diferente, com
# espaco, vazia ou EOF: 14 e nenhum expurgo.
teste_qa_e07_terminal_resposta_errada_vazia_ou_eof_e_14() {
  local resposta
  _qa_cenario
  _qa_expurgo_padrao
  for resposta in /X.txt '/x.txt ' /x.txt/ /y.txt '' sim y; do
    printf '%s\n' "$resposta" >"$B/entrada"
    rm -f "$B/chamadas"
    _qa_rodar_tty "$B/entrada" lixeira --excluir /x.txt
    assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "resposta [$resposta] no terminal: $QA_SAIDA"
    _qa_sem_expurgo "resposta [$resposta]"
  done
  : >"$B/entrada"
  rm -f "$B/chamadas"
  _qa_rodar_tty "$B/entrada" lixeira --excluir /x.txt
  _qa_estado_em "EOF no terminal: $QA_SAIDA" "$QA_NAO_CONCLUIDA" 124
  _qa_sem_expurgo 'EOF no terminal'
}

# ===========================================================================
# Exclusao permanente: a API (RF-76(c)(f)(g)(i), DIV-54, DIV-56..58, DIV-75)
# ===========================================================================

# QA-B3-E08 — DIV-54, QA-B3-02 (decisao do ciclo 2): o DeletedMetadata tem de
# trazer `path_lower` presente e igual ao alvo (dobra so ASCII); senao 10
# (erro_remoto) e nenhum expurgo. Variantes: outro caminho, ausente, so
# `path_display` certo, aninhado, vazio, nulo, `/` final, `.`/`..`, barra
# dupla, controle, NUL escapado, relativo, arranjo e caixa Unicode diferente.
teste_qa_e08_deleted_de_outro_caminho_nao_autoriza() {
  local pl meta
  local -a variantes=('"path_lower":"/outra/y.txt","path_display":"/outra/y.txt"'
    '"path_display":"/x.txt"'
    '"path_lower":"/outra/y.txt","path_display":"/x.txt"'
    '"meta":{"path_lower":"/x.txt"},"path_display":"/x.txt"'
    '"path_lower":"","path_display":"/x.txt"'
    '"path_lower":null,"path_display":"/x.txt"'
    '"path_lower":"/x.txt/"'
    '"path_lower":"/x.txt/."'
    '"path_lower":"/a/../x.txt"'
    '"path_lower":"//x.txt"'
    '"path_lower":"/x.txt\n"'
    '"path_lower":"/x.txt\u0000"'
    '"path_lower":"/x.txt\u0000/outra"'
    '"path_lower":"/x.txt\u001b"'
    '"path_lower":"x.txt"'
    '"path_lower":["/x.txt"]')
  for pl in "${variantes[@]}"; do
    meta="{\".tag\":\"deleted\",\"name\":\"x.txt\",$pl}"
    _qa_cenario
    _qa_regra files/get_metadata '*' 200 "$meta"
    _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
    _qa_regra files/permanently_delete '*' 200 'null'
    _qa_rodar lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_igual 10 "$QA_ESTADO" "guarda com [$pl] sai 10"
    assert_nao_contem $'\e' "$QA_ERRO" "sem ESC cru no diagnostico [$pl]"
    _qa_sem_expurgo "guarda com [$pl]"
  done
  # Caixa fora do ASCII: alvo /ÇA.txt; a API dobra para /ça.txt, a guarda so
  # dobra ASCII e recusa (lado seguro da decisao).
  _qa_cenario
  _qa_regra files/get_metadata '*' 200 '{".tag":"deleted","name":"x","path_lower":"/ça.txt","path_display":"/ÇA.txt"}'
  _qa_regra files/permanently_delete '*' 200 'null'
  _qa_rodar lixeira --excluir /ÇA.txt --confirmar-caminho /ÇA.txt
  assert_igual 10 "$QA_ESTADO" 'caixa Unicode divergente sai 10'
  _qa_sem_expurgo 'caixa Unicode'
}

# QA-B3-E13 — QA-B3-02: formas equivalentes aceitas e ambiguidade recusada.
# `\/` e o mesmo texto em JSON e a caixa ASCII dobra: expurga o alvo pedido.
# Campo duplicado (`path_lower` ou `.tag`) nunca pode levar ao expurgo quando
# alguma das leituras atribui a resposta a outro caminho ou a item vivo.
teste_qa_e13_guarda_formas_equivalentes_e_campo_duplicado() {
  local meta
  for meta in '{".tag":"deleted","name":"x","path_lower":"\/d\/x.txt"}' \
    '{".tag":"deleted","name":"X","path_lower":"/d/x.txt","path_display":"/D/X.txt"}'; do
    _qa_cenario
    _qa_regra files/get_metadata '*' 200 "$meta"
    _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
    _qa_regra files/permanently_delete '*' 200 'null'
    _qa_rodar lixeira --excluir /D/X.txt --confirmar-caminho /D/X.txt
    assert_igual 0 "$QA_ESTADO" "forma equivalente [$meta]: $QA_ERRO"
    _qa_contar 'files/permanently_delete {"path":"/D/X.txt"}'
    assert_igual 1 "$QA_CONTAGEM" 'expurgo no alvo pedido'
  done
  for meta in '{".tag":"deleted","path_lower":"/outra","path_lower":"/x.txt"}' \
    '{".tag":"deleted","path_lower":"/x.txt","path_lower":"/outra"}' \
    '{".tag":"file",".tag":"deleted","path_lower":"/x.txt"}' \
    '{".tag":"deleted",".tag":"file","path_lower":"/x.txt"}'; do
    _qa_cenario
    _qa_regra files/get_metadata '*' 200 "$meta"
    _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
    _qa_regra files/permanently_delete '*' 200 'null'
    _qa_rodar lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_diferente 0 "$QA_ESTADO" "campo duplicado [$meta]"
    _qa_sem_expurgo "campo duplicado [$meta]"
  done
}

# QA-B3-E09 — RF-76(c): erro, 5xx, falha de rede, 401 e corpo vazio na guarda
# saem pela classe, sem expurgo.
teste_qa_e09_guarda_com_erro_da_api_nunca_expurga() {
  local caso cod corpo esperado
  for caso in '409|{"error_summary":"path/not_found/."}|4' \
    '500|{"error_summary":"internal_error/"}|10' \
    '503|indisponivel|10' \
    'REDE||9' \
    '401|{"error_summary":"invalid_access_token/"}|5' \
    '409|{"error_summary":"path/malformed_path/."}|' \
    '200||10'; do
    IFS='|' read -r cod corpo esperado <<<"$caso"
    _qa_cenario
    _qa_regra files/get_metadata '*' "$cod" "$corpo"
    _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
    _qa_regra files/permanently_delete '*' 200 'null'
    _qa_rodar lixeira --excluir /x.txt --confirmar-caminho /x.txt
    assert_diferente 0 "$QA_ESTADO" "guarda [$cod]"
    [[ -z $esperado ]] || assert_igual "$esperado" "$QA_ESTADO" "classe da guarda [$cod $corpo]"
    _qa_sem_expurgo "guarda [$cod]"
  done
}

# QA-B3-E10 — RF-76(e): --dry-run nunca expurga, nem sobre item vivo, e nao
# pergunta; item vivo continua 2.
teste_qa_e10_dry_run_nunca_expurga() {
  _qa_cenario
  _qa_expurgo_padrao
  _qa_rodar --dry-run lixeira --excluir /x.txt
  assert_igual 0 "$QA_ESTADO" "simulacao: $QA_ERRO"
  _qa_sem_expurgo 'dry-run de item apagado'
  _qa_cenario
  _qa_regra files/get_metadata '*' 200 '{".tag":"file","name":"x.txt","path_display":"/x.txt","rev":"0000000c3"}'
  _qa_regra files/permanently_delete '*' 200 'null'
  _qa_rodar --dry-run lixeira --excluir /x.txt
  assert_igual "$QA_USO" "$QA_ESTADO" 'dry-run de item vivo e 2'
  _qa_sem_expurgo 'dry-run de item vivo'
}

# QA-B3-E11 — DIV-58/DIV-75: in_progress no expurgo e retentado e, esgotado,
# sai 14 dizendo que o item continua na lixeira.
teste_qa_e11_in_progress_no_expurgo_e_14_apos_retentar() {
  _qa_cenario
  _qa_apagado /x.txt
  _qa_regra files/get_metadata '*' 200 "$QA_META"
  _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _qa_regra files/permanently_delete '*' 409 '{"error_summary":"in_progress/.."}'
  _qa_rodar lixeira --excluir /x.txt --confirmar-caminho /x.txt
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" 'in_progress esgotado'
  _qa_contar permanently_delete
  assert_igual 2 "$QA_CONTAGEM" 'retentado (2 tentativas)'
  assert_contem 'continua na lixeira' "$QA_ERRO" 'diz o estado do item'
}

# QA-B3-E12 — RF-76(c)(k): o corpo do get_metadata e o do expurgo levam o MESMO
# caminho normalizado; nenhum segredo nas saidas, nem com --debug.
teste_qa_e12_mesmo_alvo_na_guarda_e_no_expurgo_sem_segredo() {
  local sentinela linha guarda='' expurgo=''
  _qa_cenario /proj
  _qa_apagado /proj/d/x.txt
  _qa_regra files/get_metadata '*' 200 "$QA_META"
  _qa_regra files/list_folder '*' 409 '{"error_summary":"path/not_folder/."}'
  _qa_regra files/permanently_delete '*' 200 'null'
  _qa_rodar --debug lixeira --excluir /proj//d/./x.txt --confirmar-caminho /proj/d/x.txt
  assert_igual 0 "$QA_ESTADO" "forma normalizada confirma (DIV-73): $QA_ERRO"
  while IFS= read -r linha; do
    case $linha in
      files/get_metadata*) guarda=${linha#* } ;;
      files/permanently_delete*) expurgo=${linha#* } ;;
    esac
  done <"$B/chamadas"
  assert_contem '"path":"/proj/d/x.txt"' "$guarda" 'guarda no alvo normalizado'
  assert_igual '{"path":"/proj/d/x.txt"}' "$expurgo" 'expurgo no mesmo alvo'
  for sentinela in "$QA_SENT_SEGREDO" "$QA_SENT_RT" "$QA_SENT_TOKEN" "$QA_SENT_CHAVE"; do
    assert_segredo_ausente "$sentinela" "$QA_SAIDA$QA_ERRO" 'sem segredo'
  done
}

# ===========================================================================
# restaurar (RF-73, RF-74; DIV-59..62, DIV-66, DIV-72, DIV-74)
# ===========================================================================

_qa_rev() { # <rev> <server_modified> <caminho> -> QA_ENTRADA
  QA_ENTRADA="{\"name\":\"a.txt\",\"path_display\":\"$3\",\"rev\":\"$1\",\"size\":1,\"server_modified\":\"$2\",\"client_modified\":\"$2\",\"content_hash\":\"h$1\"}"
}
QA_RESTAURADO='{"name":"a.txt","path_display":"/a.txt","rev":"0000000ff","size":1,"server_modified":"2026-10-19T10:00:00Z","content_hash":"hff"}'

_qa_arquivo_vivo() { # revisoes c3 (vigente), b2 (2026-10-01T12:00:00Z), a1
  local c b a
  _qa_regra files/get_metadata '*"/a.txt"*' 200 '{".tag":"file","name":"a.txt","path_display":"/a.txt","rev":"0000000c3"}'
  _qa_rev 0000000c3 2026-10-05T10:00:00Z /a.txt
  c=$QA_ENTRADA
  _qa_rev 0000000b2 2026-10-01T12:00:00Z /a.txt
  b=$QA_ENTRADA
  _qa_rev 0000000a1 2026-09-20T08:00:00Z /a.txt
  a=$QA_ENTRADA
  _qa_regra files/list_revisions '*"/a.txt"*' 200 "{\"is_deleted\":false,\"entries\":[$c,$b,$a],\"has_more\":false}"
  _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
}

# QA-B3-R01 — DIV-59, RF-73(c)(j): rev que nao consta do historico do caminho
# sai 2 (uso_invalido) e nunca chama restore.
teste_qa_r01_rev_de_outro_arquivo_e_2_sem_restore() {
  _qa_cenario
  _qa_arquivo_vivo
  _qa_rodar restaurar /a.txt --rev 0000000e9
  _qa_contar files/restore
  assert_igual 0 "$QA_CONTAGEM" 'nenhum restore com rev alheio'
  assert_igual "$QA_USO" "$QA_ESTADO" "rev fora do historico sai 2 (DIV-59): $QA_ERRO"
}

# QA-B3-R02 — RF-73(b): rev malformado ou com injecao JSON: 2 sem rede.
teste_qa_r02_rev_malformado_ou_injecao_sem_rede() {
  local rev
  local -a revs=(00000000 0000000C3 0000000g3 '0000000c3 ' $'0000000c3\n' '0000000c3","path":"/b.txt'
    "0000000c3\\" '-0000000c3' '' 'ffffffffff"}' $'0000000c3\t')
  _qa_cenario
  _qa_arquivo_vivo
  for rev in "${revs[@]}"; do
    _qa_rodar restaurar /a.txt --rev "$rev"
    assert_igual "$QA_USO" "$QA_ESTADO" "rev [${rev@Q}]"
    assert_nao_contem $'\n0000000c3\n' "$QA_ERRO" 'sem quebra crua'
  done
  _qa_sem_chamada 'rev invalido'
}

# QA-B3-R03 — DIV-60: --antes-de nos limites (inclusivo ao segundo, fim do dia
# UTC, bissexto) e formas invalidas sem rede.
teste_qa_r03_antes_de_limites_e_formas_invalidas() {
  local data
  _qa_cenario
  _qa_arquivo_vivo
  for data in 2026-02-29 2026-10-01T24:00:00Z 2026-10-01T23:60:00Z 2026-10-01T23:59:60Z 2026-1-01 \
    2026-10-01T10:00:00z 2026-10-01T10:00:00+00:00 '2026-10-01 ' 2026-10-01T10:00Z 2026-00-10 2026-10-00 \
    2026-04-31 +2026-10-01 20261001 ''; do
    _qa_rodar restaurar /a.txt --antes-de "$data"
    assert_igual "$QA_USO" "$QA_ESTADO" "data invalida [$data]"
  done
  _qa_sem_chamada 'datas invalidas'
  _qa_rodar restaurar /a.txt --antes-de 2026-10-01T12:00:00Z
  assert_igual 0 "$QA_ESTADO" "limite exato e inclusivo: $QA_ERRO"
  assert_contem 'rev_escolhida=0000000b2' "$QA_SAIDA" 'escolhe b2 no segundo exato'
  _qa_rodar restaurar /a.txt --antes-de 2026-10-01T11:59:59Z
  assert_contem 'rev_escolhida=0000000a1' "$QA_SAIDA" 'um segundo antes, a1'
  _qa_rodar restaurar /a.txt --antes-de 2026-09-30
  assert_contem 'rev_escolhida=0000000a1' "$QA_SAIDA" 'fim do dia anterior, a1'
  _qa_rodar restaurar /a.txt --antes-de 2024-02-29
  assert_igual "$QA_NAO_ENCONTRADO" "$QA_ESTADO" 'bissexto valido, sem revisao ate a data: 4'
}

# QA-B3-R04 — DIV-66: rev vigente (por --rev ou escolhido por --antes-de) e
# ja_atual, 0, sem restore.
teste_qa_r04_vigente_e_ja_atual_sem_restore() {
  _qa_cenario
  _qa_arquivo_vivo
  _qa_rodar restaurar /a.txt --rev 0000000c3
  assert_igual 0 "$QA_ESTADO" 'rev vigente'
  assert_contem 'situacao=ja_atual' "$QA_SAIDA" 'ja_atual'
  _qa_rodar restaurar /a.txt --antes-de 2030-01-01
  assert_contem 'situacao=ja_atual' "$QA_SAIDA" '--antes-de no futuro escolhe a vigente'
  _qa_contar files/restore
  assert_igual 0 "$QA_CONTAGEM" 'nenhum restore'
}

# Pasta apagada /p: a.txt e b.txt apagados; o item hostil entra por _qa_regra
# antes destas regras.
_qa_pasta() { # <entradas extras do list_folder>
  local extra=${1:-} item
  _qa_regra files/get_metadata '*"path":"/p"*' 200 '{".tag":"deleted","name":"p","path_display":"/p"}'
  _qa_regra files/list_revisions '*"path":"/p"*' 409 '{"error_summary":"path/not_file/."}'
  _qa_regra files/list_folder '*"path":"/p"*' 200 \
    "{\"entries\":[{\".tag\":\"deleted\",\"name\":\"b.txt\",\"path_display\":\"/p/b.txt\"},{\".tag\":\"deleted\",\"name\":\"a.txt\",\"path_display\":\"/p/a.txt\"}$extra],\"has_more\":false}"
  for item in /p/a.txt /p/b.txt; do
    _qa_rev 0000000e5 2026-10-09T00:00:00Z "$item"
    _qa_regra files/list_revisions "*\"path\":\"$item\"*" 200 \
      "{\"is_deleted\":true,\"server_deleted\":\"2026-10-10T00:00:00Z\",\"entries\":[$QA_ENTRADA],\"has_more\":false}"
  done
}

# QA-B3-R05 — RF-74(b), DIV-74: itens que a API devolve fora da raiz (subida,
# outra arvore, controle) nunca sao sondados nem restaurados; contam como
# falha e a saida e 14 com a lista.
teste_qa_r05_item_hostil_fora_da_raiz_e_falha_14() {
  _qa_cenario /p
  _qa_pasta ',{".tag":"deleted","name":"e","path_display":"/p/../fora/e.txt"},{".tag":"deleted","name":"f","path_display":"/P2/f.txt"},{".tag":"deleted","name":"g","path_display":"p/g.txt"}'
  _qa_regra files/list_revisions '*' 200 '{"is_deleted":true,"entries":[{"rev":"0000000e5","server_modified":"2026-10-09T00:00:00Z"}],"has_more":false}'
  _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
  _qa_rodar restaurar /p
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "item fora da raiz leva a 14: $QA_ERRO"
  _qa_contar fora
  assert_igual 0 "$QA_CONTAGEM" 'nenhuma chamada com /fora'
  _qa_contar /P2/
  assert_igual 0 "$QA_CONTAGEM" 'nenhuma chamada com /P2'
  _qa_contar '"path":"p/g.txt"'
  assert_igual 0 "$QA_CONTAGEM" 'nenhuma chamada com caminho relativo'
  _qa_contar files/restore
  assert_igual 2 "$QA_CONTAGEM" 'so os dois itens confinados'
  assert_contem 'falhas=3' "$QA_SAIDA" 'tres falhas no resumo'
  assert_contem 'caminho_recusado' "$QA_SAIDA" 'motivo'
}

# QA-B3-R06 — RF-74(g): falha parcial (um restore recusado) segue, sai 14 e
# nomeia o item; a ordem e a da chave sem caixa (a antes de b).
teste_qa_r06_falha_parcial_e_14_com_a_lista() {
  local linha ordem=''
  _qa_cenario
  _qa_pasta
  _qa_regra files/restore '*"/p/a.txt"*' 409 '{"error_summary":"path_write/conflict/file/.."}'
  _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
  _qa_rodar restaurar /p
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" 'falha parcial'
  assert_contem 'falha=/p/a.txt: conflito' "$QA_SAIDA" 'lista o item'
  assert_contem 'restaurados=1' "$QA_SAIDA" 'o outro voltou'
  while IFS= read -r linha; do
    [[ $linha == files/restore* ]] && ordem+="${linha#*\"path\":\"}"
  done <"$B/chamadas"
  [[ $ordem == /p/a.txt*/p/b.txt* ]] || _harness_falhar 'ordem sem caixa' "$ordem"
}

# QA-B3-R07 — RF-74(e): --dry-run nao faz escrita alguma e sai 0, mesmo com
# item hostil.
teste_qa_r07_dry_run_de_pasta_sem_escrita() {
  local linha
  _qa_cenario /p
  _qa_pasta ',{".tag":"deleted","name":"e","path_display":"/fora/e.txt"}'
  _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
  _qa_rodar --dry-run restaurar /p
  assert_igual 0 "$QA_ESTADO" "dry-run sai 0: $QA_ERRO"
  while IFS= read -r linha; do
    case ${linha%% *} in
      files/get_metadata | files/list_folder | files/list_folder/continue | files/list_revisions | oauth2/token) ;;
      *) _harness_falhar 'dry-run so le' "$linha" ;;
    esac
  done <"$B/chamadas"
  assert_contem 'simulado=sim' "$QA_SAIDA" 'anuncia a simulacao'
}

# QA-B3-R08 — RF-74(j), RNF-35: TERM no meio do restore: 14 e TMPDIR sem
# residuo dbx-*.
teste_qa_r08_term_no_meio_sem_residuo() {
  local residuo
  command -v setsid >/dev/null 2>&1 || pular 'setsid ausente'
  _qa_cenario
  _qa_pasta
  _qa_regra files/restore '*"/p/b.txt"*' TERM ''
  _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
  setsid -w env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" bash "$QA_DBX" restaurar /p </dev/null >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" 'sinal sai 14'
  residuo=''
  for residuo in "$B"/tmp/dbx-* "$B"/tmp/*; do
    [[ -e $residuo ]] && _harness_falhar 'residuo no TMPDIR' "$residuo"
  done
  IFS= read -r -d '' QA_ERRO <"$B/err"
  assert_contem 'faltaram: /p/b.txt' "$QA_ERRO" 'resumo parcial diz o que faltou'
}

# QA-B3-R09 — DIV-78: na restauracao de /p, item que a API devolve fora da
# pasta pedida (prefixo enganoso /p-x e /pasta, irmao /q, subida /p/../q,
# pasta viva irma /q) nunca e sondado nem restaurado e conta como falha (14);
# /P/c.txt e a mesma pasta sem caixa ASCII e volta.
teste_qa_r09_item_fora_da_pasta_pedida_e_falha_14() {
  local trecho
  _qa_cenario
  _qa_pasta ',{".tag":"deleted","name":"e","path_display":"/p-x/e.txt"},{".tag":"deleted","name":"f","path_display":"/pasta/f.txt"},{".tag":"deleted","name":"g","path_display":"/q/g.txt"},{".tag":"deleted","name":"h","path_display":"/p/../q/h.txt"},{".tag":"folder","name":"i","path_display":"/q"},{".tag":"deleted","name":"c","path_display":"/P/c.txt"}'
  _qa_rev 0000000e5 2026-10-09T00:00:00Z /P/c.txt
  _qa_regra files/list_revisions '*"path":"/P/c.txt"*' 200 \
    "{\"is_deleted\":true,\"entries\":[$QA_ENTRADA],\"has_more\":false}"
  _qa_regra files/list_revisions '*' 200 '{"is_deleted":true,"entries":[{"rev":"0000000e5","server_modified":"2026-10-09T00:00:00Z"}],"has_more":false}'
  _qa_regra files/list_folder '*"path":"/q"*' 200 '{"entries":[{".tag":"deleted","name":"z","path_display":"/q/z.txt"}],"has_more":false}'
  _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
  _qa_rodar restaurar /p
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "item fora da pasta pedida leva a 14: $QA_ERRO"
  for trecho in /p-x/ /pasta/ /q/ '"path":"/q"'; do
    _qa_contar "$trecho"
    assert_igual 0 "$QA_CONTAGEM" "nenhuma chamada com [$trecho]"
  done
  _qa_contar files/restore
  assert_igual 3 "$QA_CONTAGEM" 'so a.txt, b.txt e /P/c.txt'
  assert_contem 'falhas=5' "$QA_SAIDA" 'cinco recusas no resumo'
}

# QA-B3-R10 — RF-74(b), RNF-28 (resposta hostil): listagem que devolve a
# propria pasta (viva ou apagada, em outra grafia) como entrada nao pode
# prender a descida.
teste_qa_r10_pasta_que_contem_a_si_mesma_termina() {
  local entrada
  for entrada in '{".tag":"folder","name":"p","path_display":"/p"}' \
    '{".tag":"deleted","name":"p","path_display":"/p"}' \
    '{".tag":"folder","name":"p","path_display":"/P/"}'; do
    _qa_cenario
    _qa_pasta ",$entrada"
    _qa_regra files/restore '*' 200 "$QA_RESTAURADO"
    env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
      TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout 20 bash "$QA_DBX" restaurar /p </dev/null >"$B/out" 2>"$B/err"
    QA_ESTADO=$?
    assert_diferente 124 "$QA_ESTADO" "descida termina com [$entrada]"
    # O corpo da listagem comeca por "limit" (RNF-23).
    _qa_contar 'files/list_folder {"limit":100,"path":"/p",'
    [[ $QA_CONTAGEM -le 1 ]] || _harness_falhar "a propria pasta listada $QA_CONTAGEM vezes" "$entrada"
  done
}

# QA-B3-L03 — RF-75(c), RNF-28 (resposta hostil): `lixeira -R` cuja pasta viva
# devolve a si mesma termina.
teste_qa_l03_lixeira_recursiva_com_ciclo_termina() {
  _qa_cenario
  _qa_regra files/list_folder '*' 200 \
    '{"entries":[{".tag":"folder","name":"d","path_display":"/d"},{".tag":"deleted","name":"a","path_display":"/d/a"}],"has_more":false}'
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" timeout 20 bash "$QA_DBX" lixeira -R /d </dev/null >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  assert_diferente 124 "$QA_ESTADO" 'lixeira -R termina com pasta que contem a si mesma'
}

# ===========================================================================
# lixeira: listagem (RF-75)
# ===========================================================================

# QA-B3-L01 — RF-75(b): paginacao por cursor; os itens das duas paginas.
teste_qa_l01_paginacao_por_cursor() {
  _qa_cenario
  _qa_regra files/list_folder/continue '*"cursor":"CUR-1"*' 200 \
    '{"entries":[{".tag":"deleted","name":"b","path_display":"/b"}],"cursor":"CUR-2","has_more":false}'
  _qa_regra files/list_folder '*' 200 \
    '{"entries":[{".tag":"deleted","name":"a","path_display":"/a"}],"cursor":"CUR-1","has_more":true}'
  _qa_rodar lixeira /
  assert_igual 0 "$QA_ESTADO" "paginacao: $QA_ERRO"
  assert_contem 'path_display=/a' "$QA_SAIDA" 'pagina 1'
  assert_contem 'path_display=/b' "$QA_SAIDA" 'pagina 2'
  assert_contem 'total=2' "$QA_SAIDA" 'total'
  _qa_contar files/list_folder/continue
  assert_igual 1 "$QA_CONTAGEM" 'um continue'
}

# QA-B3-L02 — RF-75(d), RNF-10: nomes hostis (quebra, ESC, CR, aspas, barra
# invertida) sem byte cru no texto nem no --json (contrato chave=valor de
# lib/output, uma linha por par) e --null sem erro; itens
# fora da raiz omitidos.
teste_qa_l02_nomes_hostis_e_json_valido() {
  local lista
  lista='{"entries":[{".tag":"deleted","name":"a\nb","path_display":"/a\nb"},{".tag":"deleted","name":"\u001b[31mx","path_display":"/\u001b[31mx"},{".tag":"deleted","name":"q\"\\r\r","path_display":"/q\"\\r\r"},{".tag":"deleted","name":"z","path_display":"/../fora/z"}],"has_more":false}'
  _qa_cenario
  _qa_regra files/list_folder '*' 200 "$lista"
  _qa_rodar lixeira /
  assert_igual 0 "$QA_ESTADO" "texto: $QA_ERRO"
  assert_nao_contem $'\e' "$QA_SAIDA" 'sem ESC cru no texto'
  assert_nao_contem $'\r' "$QA_SAIDA" 'sem CR cru no texto'
  assert_nao_contem $'a\nb' "$QA_SAIDA" 'sem quebra crua no nome'
  assert_nao_contem 'fora' "$QA_SAIDA" 'item fora da raiz omitido'
  assert_contem 'total=3' "$QA_SAIDA" 'tres itens confinados'
  _qa_rodar --json lixeira /
  assert_igual 0 "$QA_ESTADO" "json: $QA_ERRO"
  assert_nao_contem $'\e' "$QA_SAIDA" 'sem ESC cru na saida estruturada'
  assert_nao_contem $'\r' "$QA_SAIDA" 'sem CR cru na saida estruturada'
  assert_contem 'contrato=1' "$QA_SAIDA" 'versao de contrato (RF-35)'
  # Contrato estruturado do projeto (lib/output): um par chave=valor por linha;
  # nenhuma linha forjada por nome hostil.
  local linha pares=0
  while IFS= read -r linha; do
    [[ $linha =~ ^[a-z_]+= ]] || _harness_falhar 'linha fora do contrato chave=valor' "$linha"
    pares=$((pares + 1))
  done <"$B/out"
  assert_igual 17 "$pares" 'tres registros de item (contrato + 4 campos) e o total (contrato + total)'
  _qa_rodar --null lixeira /
  assert_igual 0 "$QA_ESTADO" "null: $QA_ERRO"
  QA_SAIDA=$(tr '\0' '|' <"$B/out")
  assert_contem $'|name=a\nb|' "$QA_SAIDA" 'nome com quebra integro sob --null (RNF-10)'
  # Sob --null o nome sai integro por contrato (RF-28, como `list --null`).
  assert_contem $'|name=\e[31mx|' "$QA_SAIDA" 'nome integro sob --null, como list'
}

# ===========================================================================
# DIV-75: in_progress nos pontos de escrita existentes
# ===========================================================================

# QA-B3-D01 — DIV-58/DIV-75: delete com in_progress e retentado e sai 14.
teste_qa_d01_delete_in_progress_retenta_e_sai_14() {
  _qa_cenario
  _qa_regra files/delete_v2 '*' 409 '{"error_summary":"in_progress/.."}'
  _qa_rodar delete /x.txt --yes
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "delete in_progress: $QA_ERRO"
  _qa_contar files/delete_v2
  assert_igual 2 "$QA_CONTAGEM" 'retentado'
}

# QA-B3-D02 — DIV-75: restore de arquivo com in_progress (uma vez) se recupera
# na retentativa; persistente sai 14.
teste_qa_d02_restore_in_progress_recupera_ou_sai_14() {
  _qa_cenario
  _qa_regra files/restore '*' 409 '{"error_summary":"in_progress/"}' uma
  _qa_arquivo_vivo
  _qa_rodar restaurar /a.txt --rev 0000000b2
  assert_igual 0 "$QA_ESTADO" "recupera na retentativa: $QA_ERRO"
  _qa_cenario
  _qa_regra files/restore '*' 409 '{"error_summary":"in_progress/"}'
  _qa_arquivo_vivo
  _qa_rodar restaurar /a.txt --rev 0000000b2
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" 'persistente sai 14'
}

# QA-B3-D03 — DIV-75 (regressao) e decisao QA-B3-03: o upload retenta o
# in_progress e, esgotado, mantem 10 (erro_remoto); a DIV-75 vale so para
# delete, restore e expurgo.
teste_qa_d03_upload_in_progress_nao_sai_0() {
  _qa_cenario
  printf 'abc' >"$B/local.txt"
  _qa_regra files/upload '*' 409 '{"error_summary":"in_progress/"}'
  _qa_rodar upload "$B/local.txt" /local.txt
  assert_igual 10 "$QA_ESTADO" 'upload com in_progress mantem 10 (QA-B3-03)'
  _qa_contar files/upload
  assert_igual 2 "$QA_CONTAGEM" 'in_progress retentado no upload'
}

# QA-B3-D04 — DIV-75 (regressao): sync que envia e recebe in_progress no
# upload retenta, conta a falha do item e sai 14 (RF-59, RF-36), nunca 0.
teste_qa_d04_sync_in_progress_no_envio_sai_14() {
  _qa_cenario
  mkdir -p "$B/local"
  printf 'abc' >"$B/local/a.txt"
  _qa_regra files/list_folder '*' 200 '{"entries":[],"cursor":"c","has_more":false}'
  _qa_regra files/upload '*' 409 '{"error_summary":"in_progress/"}'
  _qa_rodar sync --enviar --origem "$B/local" --destino /r
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "sync com in_progress no envio: $QA_ERRO"
  _qa_contar files/upload
  assert_igual 2 "$QA_CONTAGEM" 'in_progress retentado no sync'
}

harness_executar "$@"
