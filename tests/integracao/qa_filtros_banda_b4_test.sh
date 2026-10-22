#!/usr/bin/env bash
# Suite independente do QA, fase 4 do backlog: filtros de caminho, data e
# tamanho (F-13; RF-79..RF-81) e limite de banda (F-17; RF-82; DIV-79..DIV-102).
#
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx`, com duplo de `curl`
# e de `rm` proprios (independentes dos da suite do developer). O foco e P0,
# RF-80(d): com `--espelhar`, item filtrado NUNCA e apagado, nem no remoto
# (`delete_v2`) nem no local (`rm`), em nenhuma direcao. A prova e o REGISTRO
# DE CHAMADAS do duplo e o disco, nunca o relatorio do proprio `sync`. Todo caso
# de protecao traz tambem um item NO ESCOPO que precisa ser apagado: assim o
# caso reprova tanto quem apaga demais quanto quem desliga o espelho.
#
# Duplo de `curl`: regras em `$B/regras`, uma por linha,
# `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>resposta[<TAB>uma]` (padroes do
# shell); a primeira que casa responde. Toda chamada vai para `$B/chamadas` como
# `endpoint<TAB>limit-rate<TAB>corpo` (limit-rate `-` quando a configuracao
# lida por `-K -` nao o traz; no modo de conteudo, o `Dropbox-API-Arg` no lugar
# do corpo, que e o proprio arquivo); o `argv` vai para `$B/argv`. Chamada sem regra
# responde 400 e fica marcada `SEM_REGRA`.
#
# Auditoria RNF-24: nenhum `$(...)` captura bytes externos (saida do programa,
# arquivo, registro); tudo e lido com `read`. Nenhum `grep -c` sobre arquivo.
#
# shellcheck disable=SC2016
# Justificativa: o duplo e os padroes sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly QA_USO QA_NAO_CONCLUIDA
QA_RM_REAL=$(command -v rm)
readonly QA_RM_REAL
readonly QA_H0=0000000000000000000000000000000000000000000000000000000000000000

B=''
QA_ESTADO=''
QA_SAIDA=''
QA_ERRO=''
QA_N=0
QA_CONTAGEM=0
QA_HASH=''
QA_E=''
QA_LISTA=''
declare -a QA_AMBIENTE=()

# _qa_cenario — credencial, duplos de `curl` e `rm`, arvore local vazia em $B/l.
_qa_cenario() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-b4.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado" "$B/l"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  QA_N=0
  QA_AMBIENTE=()
  {
    printf '#!%s\nQA=%q\nDBX_HARNESS_RAIZ=%q\n' "$BASH" "$B" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=''
IFS= read -r -d '' conf
o=''; w=''; ant=''; url=''; dados=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
printf '%s\n' "$*" >>"$QA/argv"
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
limite=-
[[ $conf =~ (^|$'\n')limit-rate\ =\ ([^$'\n']*) ]] && limite=${BASH_REMATCH[2]}
ep=${url#https://api.dropboxapi.com/2/}
ep=${ep#https://content.dropboxapi.com/2/}
cod=400 corpo='{"error_summary":"sem_regra/"}'
if [[ $url == *oauth2/token* ]]; then
  printf 'oauth2/token\t%s\t%s\n' "$limite" "$pedido" >>"$QA/chamadas"
  cod=200 corpo='{"access_token":"sl.t","token_type":"bearer","expires_in":14400}'
else
  registro=$pedido
  [[ $conf =~ Dropbox-API-Arg:\ ([^$'\n']*) ]] && registro=${BASH_REMATCH[1]}
  printf '%s\t%s\t%s\n' "$ep" "$limite" "$registro" >>"$QA/chamadas"
  achou=nao n=0
  # Rotas de lote (RF-136): o duplo compartilhado responde antes das regras; cada
  # item confirmado ecoa `files/delete_v2<TAB>limite<TAB>corpo` (3 campos).
  base=$QA LOTE_ECOA_V2=sim LOTE_ECOA_CAMPO=$limite
  . "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
  if lote_responder "$url" "$dados"; then
    achou=sim cod=$codigo
  else
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
  fi
  [[ $achou == sim ]] || printf 'SEM_REGRA %s\n' "$ep" >>"$QA/chamadas"
fi
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  # `rm` que registra cada chamada (NUL entre argumentos) e delega ao real.
  printf '#!%s\nprintf "%%s\\0" "$@" >>%q\nprintf "\\n" >>%q\nexec %q "$@"\n' \
    "$BASH" "$B/rm.log" "$B/rm.log" "$QA_RM_REAL" >"$B/bin/rm"
  chmod +x "$B/bin/curl" "$B/bin/rm"
}

# _qa_regra <endpoint> <filtro> <codigo> <corpo> [uma]
_qa_regra() {
  QA_N=$((QA_N + 1))
  printf '%s' "$4" >"$B/resp/r$QA_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$QA_N" "${5:-}" >>"$B/regras"
}

# _qa_basicas — conta, espaco, envio, exclusao e download respondem 200.
_qa_basicas() {
  _qa_regra users/get_current_account '*' 200 '{"account_id":"dbid:QA-B4"}'
  _qa_regra users/get_space_usage '*' 200 '{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}'
  _qa_regra files/upload '*' 200 '{"name":"x","path_display":"/r/x","rev":"1","size":1}'
  _qa_regra files/delete_v2 '*' 200 '{"metadata":{".tag":"file","name":"x"}}'
  _qa_regra files/get_metadata '*' 200 '{".tag":"folder","name":"r","path_display":"/r"}'
}

# _qa_rodar <argumentos...> — o codigo de saida e SEMPRE um de 0..15.
_qa_rodar() {
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    ${QA_AMBIENTE[@]+"${QA_AMBIENTE[@]}"} \
    bash "$QA_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  QA_SAIDA='' QA_ERRO=''
  IFS= read -r -d '' QA_SAIDA <"$B/out"
  IFS= read -r -d '' QA_ERRO <"$B/err"
  if ((QA_ESTADO < 0 || QA_ESTADO > 15)); then
    _harness_falhar 'codigo de saida fora de 0..15' "obtido: [$QA_ESTADO]" "argv: [$*]"
  fi
  return 0
}

_qa_estado() { # <esperado> <descricao>
  assert_igual "$1" "$QA_ESTADO" "$2 (stderr: ${QA_ERRO:0:400})"
}

# _qa_contar <trecho> — linhas de `chamadas` que contem o trecho.
_qa_contar() {
  local linha total=0
  if [[ -f $B/chamadas ]]; then
    while IFS= read -r linha || [[ -n $linha ]]; do
      [[ $linha == *"$1"* ]] && total=$((total + 1))
    done <"$B/chamadas"
  fi
  QA_CONTAGEM=$total
}

# _qa_coletar <endpoint> — corpos das chamadas ao endpoint, ordenados e unidos
# por `|`, em QA_LISTA. A ordem nao importa para o espelho.
_qa_coletar() {
  local linha ep lr corpo
  local -a itens=()
  if [[ -f $B/chamadas ]]; then
    while IFS=$'\t' read -r ep lr corpo || [[ -n $ep ]]; do
      [[ $ep == "$1" ]] && itens+=("$corpo")
    done <"$B/chamadas"
  fi
  QA_LISTA=''
  local i j t n=${#itens[@]}
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      if [[ ${itens[j]} < ${itens[i]} ]]; then t=${itens[i]} itens[i]=${itens[j]} itens[j]=$t; fi
    done
  done
  for linha in ${itens[@]+"${itens[@]}"}; do QA_LISTA+="${QA_LISTA:+|}$linha"; done
  : "$lr"
}

# _qa_deletes_sao <esperado> <descricao> — os delete_v2 exatos (ordenados, `|`).
_qa_deletes_sao() {
  _qa_coletar files/delete_v2
  assert_igual "$1" "$QA_LISTA" "$2"
}

_qa_sem_chamada() { assert_arquivo_ausente "$B/chamadas" "nenhuma chamada, nem renovacao: $1"; }

# _qa_rm_tocou <trecho> — 0 se algum `rm` registrado tem argumento com o trecho.
_qa_rm_tocou() {
  local arg
  [[ -f $B/rm.log ]] || return 1
  while IFS= read -r -d '' arg; do
    [[ $arg == *"$1"* ]] && return 0
  done <"$B/rm.log"
  return 1
}

# _qa_hash <conteudo> — content_hash em QA_HASH, pela biblioteca do projeto,
# lido de arquivo (sem `$(...)`).
_qa_hash() {
  printf '%s' "$1" >"$B/tmp/qa-hash.in"
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; dbx_hash_conteudo_arquivo "$2"' _ \
    "$DBX_HARNESS_RAIZ" "$B/tmp/qa-hash.in" >"$B/tmp/qa-hash.out"
  QA_HASH=''
  IFS= read -r QA_HASH <"$B/tmp/qa-hash.out" || :
}

# _qa_local <relativo> [conteudo] — arquivo local antigo.
_qa_local() {
  local alvo="$B/l/$1"
  mkdir -p -- "${alvo%/*}"
  printf '%s' "${2:-x}" >"$alvo"
  touch -d '@1700000000' -- "$alvo"
}

# _qa_arq <relativo> [hash] [server_modified] [size] — entrada de arquivo sob /r em QA_E.
_qa_arq() {
  printf -v QA_E '{".tag":"file","name":"%s","path_display":"/r/%s","content_hash":"%s","size":%s,"rev":"0000001","server_modified":"%s","client_modified":"2026-01-01T00:00:00Z"}' \
    "${1##*/}" "$1" "${2:-$QA_H0}" "${4:-1}" "${3:-2026-10-05T00:00:00Z}"
}

_qa_pasta() {
  printf -v QA_E '{".tag":"folder","name":"%s","path_display":"/r/%s"}' "${1##*/}" "$1"
}

# _qa_listagem <endpoint> <has_more> <cursor> <entradas...>
_qa_listagem() {
  local ep=$1 mais=$2 cursor=$3 juntas
  shift 3
  juntas=$(IFS=,; printf '%s' "$*")
  _qa_regra "$ep" '*' 200 "{\"entries\":[$juntas],\"has_more\":$mais,\"cursor\":\"$cursor\"}"
}

# _qa_remoto <entradas...> — listagem de pagina unica.
_qa_remoto() { _qa_listagem files/list_folder false '' "$@"; }

# ===========================================================================
# P0 — RF-80(d): item filtrado nunca e apagado
# ===========================================================================

# QA-B4-E01 — `--enviar --espelhar`: filtro de pasta com caixa diferente entre
# os lados (`fotos/` x `FOTOS/`), `/build` ancorado na raiz (em caixa trocada),
# `**/tmp` (pasta e arquivo em qualquer nivel) e `*.log` contra `Rel.LOG`.
# Zero `delete_v2` sobre filtrado; e o que esta no escopo (inclusive o
# `sub/Build/z` que a ancora NAO alcanca) e apagado.
teste_qa_e01_enviar_espelhar_filtro_de_pasta_ancorado_e_caixa() {
  local -a ent=()
  _qa_cenario
  _qa_basicas
  _qa_local keep.txt
  _qa_local fotos/a.jpg
  _qa_local build/x
  _qa_local a/b/tmp/t1
  _qa_pasta FOTOS && ent+=("$QA_E")
  _qa_arq FOTOS/a.jpg && ent+=("$QA_E")
  _qa_arq FOTOS/b.jpg && ent+=("$QA_E")
  _qa_arq Build/old && ent+=("$QA_E")
  _qa_arq sub/Build/z && ent+=("$QA_E")
  _qa_arq x/y/TMP/q && ent+=("$QA_E")
  _qa_arq q/tmp && ent+=("$QA_E")
  _qa_arq Rel.LOG && ent+=("$QA_E")
  _qa_arq solto.txt && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r \
    --excluir 'fotos/' --excluir '/BUILD' --exclude '**/tmp' --excluir '*.log'
  _qa_estado 0 'conclui'
  _qa_deletes_sao '{"path":"/r/solto.txt"}|{"path":"/r/sub/Build/z"}' \
    'so os itens no escopo sao apagados; nenhum filtrado'
  _qa_coletar files/upload
  assert_contem 'keep.txt' "$QA_LISTA" 'o que esta no escopo e enviado'
  assert_nao_contem 'a.jpg' "$QA_LISTA" 'pasta excluida nao e enviada'
  assert_nao_contem 'build/x' "$QA_LISTA" 'ancorado nao e enviado'
  assert_nao_contem 't1' "$QA_LISTA" '**/tmp nao e enviado'
}

# QA-B4-E02 — `--receber --espelhar`: filtrado LOCAL fica no disco, sem `rm`,
# com inclusao que deixa itens fora, exclusao que vence a inclusao em caixa
# diferente, `privado/**` e `/raiz.txt` ancorado. O no escopo sem par sai.
teste_qa_e02_receber_espelhar_filtrado_local_intacto() {
  local -a ent=()
  local f
  _qa_cenario
  _qa_basicas
  _qa_hash 'igual'
  _qa_local mantido.txt 'igual'
  _qa_local CACHE/a.txt 'cache do operador'
  _qa_local foto.jpg 'foto do operador'
  _qa_local privado/segredo.txt 'segredo'
  _qa_local raiz.txt 'raiz'
  _qa_local x/raiz.txt 'some'
  _qa_local solto.txt 'some'
  _qa_arq mantido.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --receber --espelhar --confirmar --origem /r --destino "$B/l" \
    --incluir '*.TXT' --excluir 'cache/' --excluir 'privado/**' --excluir '/raiz.txt'
  _qa_estado 0 'conclui'
  for f in CACHE/a.txt foto.jpg privado/segredo.txt raiz.txt mantido.txt; do
    assert_arquivo_existe "$B/l/$f" "filtrado (ou identico) fica: $f"
  done
  local lido=''
  IFS= read -r -d '' lido <"$B/l/CACHE/a.txt" || :
  assert_igual 'cache do operador' "$lido" 'mesmos bytes'
  assert_arquivo_ausente "$B/l/solto.txt" 'no escopo sem par e apagado (o espelho funciona)'
  assert_arquivo_ausente "$B/l/x/raiz.txt" 'a ancora /raiz.txt nao alcanca x/raiz.txt'
  for f in CACHE foto privado/ /raiz.txt mantido; do
    if [[ $f == /raiz.txt ]]; then
      _qa_rm_tocou "$B/l/raiz.txt" && _harness_falhar 'rm sobre /raiz.txt filtrado'
    else
      _qa_rm_tocou "$f" && _harness_falhar "rm sobre filtrado: $f"
    fi
  done
  return 0
}

# QA-B4-E03 — DIV-99 com caractere NAO ASCII: nome local com byte invalido em
# UTF-8 em algum ponto do caminho. `--excluir 'Éfoto.jpg'` (a MESMA grafia do
# arquivo) e `--excluir '?eu.txt'` precisam proteger `lixo\xff/Éfoto.jpg` e
# `lixo\xff/éeu.txt` no `--receber --espelhar`, e o `--enviar` nao os envia.
teste_qa_e03_div99_nome_nao_utf8_com_caractere_nao_ascii_e_protegido() {
  local -a ent=()
  local pasta=$'lixo\xff'
  _qa_cenario
  _qa_basicas
  _qa_hash 'igual'
  _qa_local mantido.txt 'igual'
  _qa_local "$pasta/Éfoto.jpg" 'foto'
  _qa_local "$pasta/éeu.txt" 'eu'
  _qa_local "$pasta/solto.bin" 'some'
  _qa_arq mantido.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --receber --espelhar --confirmar --origem /r --destino "$B/l" \
    --excluir 'Éfoto.jpg' --excluir '?eu.txt'
  _qa_estado 0 'conclui'
  assert_arquivo_existe "$B/l/$pasta/Éfoto.jpg" 'DIV-99: mesma grafia, byte invalido no ancestral'
  assert_arquivo_existe "$B/l/$pasta/éeu.txt" 'DIV-99: ? casa UM caractere, nao um byte'
  assert_arquivo_ausente "$B/l/$pasta/solto.bin" 'o no escopo sai (o espelho funciona)'
}

# QA-B4-E04 — DIV-81 nos dois sentidos: origem com arquivos, todos filtrados,
# e item no escopo a apagar: 14, zero exclusao, mensagem "origem vazia depois
# dos filtros"; `--dry-run` anuncia `recusaria` com 0. Sem item no escopo a
# apagar, nao recusa e nao apaga nada.
teste_qa_e04_origem_toda_filtrada_e_vazia_para_a_guarda() {
  local -a ent=()
  _qa_cenario
  _qa_basicas
  _qa_local a.txt
  _qa_arq x.pdf && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r --incluir '*.pdf'
  _qa_estado "$QA_NAO_CONCLUIDA" 'enviar: recusa integral'
  assert_contem 'origem vazia depois dos filtros' "$QA_ERRO" 'mensagem'
  _qa_deletes_sao '' 'enviar: nenhum delete_v2'
  _qa_rodar --dry-run sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r --incluir '*.pdf'
  _qa_estado 0 'dry-run sai 0'
  assert_contem 'recusaria' "$QA_SAIDA" 'dry-run anuncia a recusa'
  _qa_deletes_sao '' 'dry-run: nenhum delete_v2'

  _qa_cenario
  _qa_basicas
  _qa_local x.pdf 'pdf do operador'
  _qa_arq a.txt && _qa_remoto "$QA_E"
  _qa_rodar sync --receber --espelhar --confirmar --origem /r --destino "$B/l" --incluir '*.pdf'
  _qa_estado "$QA_NAO_CONCLUIDA" 'receber: recusa integral'
  assert_arquivo_existe "$B/l/x.pdf" 'receber: o pdf local fica'
  _qa_rm_tocou x.pdf && _harness_falhar 'receber: rm sobre x.pdf'

  _qa_cenario
  _qa_basicas
  _qa_local a.txt
  _qa_arq z.txt && _qa_remoto "$QA_E"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r --incluir '*.pdf'
  _qa_estado 0 'origem toda filtrada SEM item no escopo a apagar nao recusa'
  _qa_deletes_sao '' 'z.txt e filtrado no destino: nao e apagado'
}

# QA-B4-E05 — RF-80(d4) com memoria que CONHECE o item: par sincronizado sem
# filtro; `b/` some da origem; com `--excluir 'b/'` e com `--excluir 'B/**'`
# nada sob `b/` e apagado. Sem o filtro, volta ao escopo e sai.
teste_qa_e05_filtro_novo_com_memoria_que_conhece_o_item() {
  local -a ent=()
  _qa_cenario
  _qa_basicas
  _qa_hash 'A'
  _qa_local a.txt 'A'
  _qa_arq a.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_hash 'B1'
  _qa_local b/1.txt 'B1'
  _qa_arq b/1.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r
  _qa_estado 0 'primeira execucao sem filtro'
  _qa_deletes_sao '' 'nada a apagar na primeira'
  "$QA_RM_REAL" -rf -- "$B/l/b"
  _qa_rodar sync --enviar --espelhar --origem "$B/l" --destino /r --excluir 'b/'
  _qa_estado 0 'com b/ excluida'
  _qa_deletes_sao '' 'filtro novo nao apaga o que deixou de fora'
  _qa_rodar sync --enviar --espelhar --origem "$B/l" --destino /r --excluir 'B/**'
  _qa_estado 0 'com B/** excluido'
  _qa_deletes_sao '' 'B/** (caixa trocada) tambem protege'
  _qa_rodar sync --enviar --espelhar --origem "$B/l" --destino /r
  _qa_estado 0 'sem filtro'
  _qa_deletes_sao '{"path":"/r/b/1.txt"}' 'remover o filtro devolve o item ao escopo'
}

# QA-B4-E06 — DIV-82 com paginacao: a pasta excluida e o conteudo dela chegam
# so na SEGUNDA pagina (`list_folder/continue`). Nada sob ela e apagado; a
# pasta conta 1 em filtrados_destino.
teste_qa_e06_pasta_excluida_na_segunda_pagina_da_listagem() {
  local -a p1=() p2=()
  _qa_cenario
  _qa_basicas
  _qa_hash 'K'
  _qa_local keep.txt 'K'
  _qa_arq keep.txt "$QA_HASH" && p1+=("$QA_E")
  _qa_listagem files/list_folder true 'C1' "${p1[@]}"
  _qa_pasta Velho && p2+=("$QA_E")
  _qa_arq Velho/a && p2+=("$QA_E")
  _qa_arq Velho/sub/b && p2+=("$QA_E")
  _qa_arq solto && p2+=("$QA_E")
  _qa_listagem files/list_folder/continue false 'C2' "${p2[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r --excluir 'velho/'
  _qa_estado 0 'conclui'
  _qa_contar files/list_folder/continue
  assert_igual 1 "$QA_CONTAGEM" 'a segunda pagina foi pedida'
  _qa_deletes_sao '{"path":"/r/solto"}' 'so o no escopo da segunda pagina sai'
  assert_contem 'filtrados_destino' "$QA_SAIDA" 'contagem no resumo'
  [[ $QA_SAIDA =~ filtrados_destino[^0-9]*1([^0-9]|$) ]] ||
    _harness_falhar 'pasta excluida conta 1 em filtrados_destino' "saida: [${QA_SAIDA:0:600}]"
}

# QA-B4-E07 — DIV-101: vinculo simbolico e fifo fora do escopo como arquivo E
# como pasta saem em silencio (sem travessia parcial) e o par remoto nao e
# apagado. Filtro so de pasta (`lnk/`) nao tira o vinculo do escopo: a
# travessia fica parcial e NENHUMA exclusao acontece.
teste_qa_e07_vinculo_e_especial_filtrados_e_so_pasta() {
  local -a ent=()
  command -v mkfifo >/dev/null 2>&1 || pular 'mkfifo ausente'
  _qa_cenario
  _qa_basicas
  _qa_hash 'K'
  _qa_local keep.txt 'K'
  ln -s /etc "$B/l/lnk"
  mkfifo "$B/l/fila"
  _qa_arq keep.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_arq lnk && ent+=("$QA_E")
  _qa_arq fila/x && ent+=("$QA_E")
  _qa_arq solto && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r \
    --excluir lnk --excluir fila
  _qa_estado 0 'filtrados como arquivo e pasta: sem parcial'
  _qa_deletes_sao '{"path":"/r/solto"}' 'pares de vinculo e fifo ficam; solto sai'
  : >"$B/chamadas"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r \
    --excluir 'lnk/' --excluir fila
  assert_diferente 0 "$QA_ESTADO" 'vinculo no escopo como arquivo: travessia parcial'
  _qa_deletes_sao '' 'travessia parcial desabilita toda exclusao'
}

# QA-B4-E08 — RF-81(b): data ou tamanho com `--espelhar`/`--mirror`, nos dois
# sentidos e em qualquer ordem: 2, sem rede, sem trava nem memoria, sem criar
# o destino local; mesmo com valor invalido junto.
teste_qa_e08_data_e_tamanho_com_espelhar_saem_2_antes_de_tudo() {
  local par
  local -a pares=('--modificado-desde 2026-01-01' '--modified-until 2026-01-01'
    '--tamanho-min 1' '--max-size 1K' '--tamanho-max lixo')
  _qa_cenario
  _qa_basicas
  "$QA_RM_REAL" -rf -- "$B/estado"
  for par in "${pares[@]}"; do
    # shellcheck disable=SC2086  # o par e opcao e valor, separados de proposito
    _qa_rodar sync --enviar $par --espelhar --origem "$B/l" --destino /r
    _qa_estado "$QA_USO" "enviar [$par]"
    # shellcheck disable=SC2086
    _qa_rodar sync --mirror --receber --origem /r --destino "$B/novo" $par
    _qa_estado "$QA_USO" "receber [$par]"
    assert_arquivo_ausente "$B/novo" "destino nao criado [$par]"
  done
  _qa_sem_chamada 'data e tamanho com espelhar'
  assert_arquivo_ausente "$B/estado" 'nem trava nem memoria'
}

# QA-B4-E09 — DIV-96 / RF-39: `server_modified` so decide ESCOPO. Sem filtro de
# data, um `server_modified` novo com o mesmo resumo nao baixa nada; com filtro,
# o que esta na faixa e tem o mesmo resumo tambem nao baixa, e o que esta fora
# da faixa nao e baixado mesmo diferente. No codigo, o campo so e lido no
# predicado de escopo da origem.
teste_qa_e09_server_modified_nunca_decide_transferencia() {
  local -a ent=()
  local linha n=0 guarda=0
  _qa_cenario
  _qa_basicas
  _qa_regra files/download '*' 200 'NAO DEVIA BAIXAR'
  _qa_hash 'igual'
  _qa_local igual.txt 'igual'
  _qa_arq igual.txt "$QA_HASH" '2099-12-31T23:59:59Z' && ent+=("$QA_E")
  _qa_arq antigo.txt "$QA_H0" '2020-01-01T00:00:00Z' && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --receber --origem /r --destino "$B/l" --modificado-desde 2026-01-01
  _qa_estado 0 'conclui'
  _qa_contar files/download
  assert_igual 0 "$QA_CONTAGEM" 'nada baixado: igual pelo resumo; antigo fora da faixa'
  assert_arquivo_ausente "$B/l/antigo.txt" 'fora da faixa nao vem'
  # Auditoria: em lib/sync.sh o campo da data remota aparece numa linha so,
  # e essa linha esta no bloco guardado por `lado == origem` e filtro ativo.
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == *"[[ \$lado == 'origem' ]] && dbx_filtro_meta_ativo"* ]] && guarda=1
    if [[ $linha == *DBX_FILTRO_CAMPO_DATA_REMOTA* || $linha == *server_modified* ]] &&
      [[ $linha != *'#'* ]]; then
      n=$((n + 1))
      assert_igual 1 "$guarda" "uso do campo fora da guarda de escopo: [$linha]"
    fi
  done <"$DBX_HARNESS_RAIZ/lib/sync.sh"
  assert_igual 1 "$n" 'um unico ponto de leitura do campo em lib/sync.sh'
}

# QA-B4-E10 — DIV-95: depois de um envio, o `delete_v2` leva o proprio JSON e
# nenhuma chamada de metadado leva o conteudo enviado; idem a renovacao de
# token que segue um envio recusado por token expirado.
teste_qa_e10_corpo_do_envio_nao_vaza_para_chamadas_seguintes() {
  local ep lr corpo
  _qa_cenario
  _qa_regra users/get_current_account '*' 200 '{"account_id":"dbid:QA-B4"}'
  _qa_regra users/get_space_usage '*' 200 '{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}'
  _qa_regra files/upload '*' 401 '{"error_summary":"expired_access_token/","error":{".tag":"expired_access_token"}}' uma
  _qa_regra files/upload '*' 200 '{"name":"x","path_display":"/r/x","rev":"1","size":1}'
  _qa_regra files/delete_v2 '*' 200 '{"metadata":{".tag":"file","name":"x"}}'
  _qa_local a.txt 'QA-CONTEUDO-B4-ENVIADO'
  _qa_arq solto && _qa_remoto "$QA_E"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r
  _qa_estado 0 'conclui'
  _qa_deletes_sao '{"path":"/r/solto"}' 'delete_v2 com o proprio JSON'
  local houve_envio='nao' renovou_depois='nao'
  while IFS=$'\t' read -r ep lr corpo || [[ -n $ep ]]; do
    [[ $ep == files/upload* ]] && houve_envio='sim' && continue
    [[ $ep == oauth2/token && $houve_envio == 'sim' ]] && renovou_depois='sim'
    assert_nao_contem 'QA-CONTEUDO-B4-ENVIADO' "$corpo" "conteudo vazou para [$ep]"
  done <"$B/chamadas"
  assert_igual sim "$renovou_depois" 'houve renovacao de token DEPOIS de um envio'
  : "$lr"
}

# QA-B4-E11 — RF-79(l): o padrao e dado. Substituicao de comando, crase, `;`,
# `$VAR`, `~` nada executam; metacaractere de regex e literal: `(a|b)` protege
# so o item `(a|b)`, e o `a` (no escopo) e apagado.
teste_qa_e11_padrao_e_dado_nunca_codigo_nem_regex() {
  local -a ent=()
  _qa_cenario
  _qa_basicas
  _qa_hash 'K'
  _qa_local keep.txt 'K'
  _qa_arq keep.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_arq '(a|b)' && ent+=("$QA_E")
  _qa_arq a && ent+=("$QA_E")
  _qa_arq 'x.y' && ent+=("$QA_E")
  _qa_arq 'xzy' && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r \
    --excluir '(a|b)' --excluir 'x.y' --excluir "\$(touch $B/PWN1)" --excluir "\`touch $B/PWN2\`" \
    --excluir "q;touch $B/PWN3" --excluir '$HOME' --excluir '~' --excluir 'a{1}'
  _qa_estado 0 'conclui'
  assert_arquivo_ausente "$B/PWN1" 'sem substituicao de comando'
  assert_arquivo_ausente "$B/PWN2" 'sem crase'
  assert_arquivo_ausente "$B/PWN3" 'sem ;'
  _qa_deletes_sao '{"path":"/r/a"}|{"path":"/r/xzy"}' \
    'regex nao vale: (a|b) e x.y so protegem a si mesmos'
}

# QA-B4-E12 — DIV-80: 64 padroes passam e 65 saem 2 sem rede; 1024 BYTES passam
# e 1025 saem 2, contados em bytes mesmo sob localidade UTF-8 (512 `é` passam,
# 513 nao).
teste_qa_e12_limites_de_padroes_em_quantidade_e_bytes() {
  local -a args=()
  local i p
  _qa_cenario
  _qa_basicas
  _qa_local keep.txt
  _qa_remoto
  for ((i = 1; i <= 64; i++)); do args+=(--excluir "p$i"); done
  _qa_rodar --dry-run sync --enviar --origem "$B/l" --destino /r "${args[@]}"
  _qa_estado 0 '64 padroes'
  : >"$B/chamadas"
  "$QA_RM_REAL" -f -- "$B/chamadas"
  _qa_rodar --dry-run sync --enviar --origem "$B/l" --destino /r "${args[@]}" --incluir p65
  _qa_estado "$QA_USO" '65 padroes (soma das duas opcoes)'
  _qa_sem_chamada '65 padroes'
  printf -v p '%*s' 1024 ''
  p=${p// /a}
  _qa_rodar --dry-run sync --enviar --origem "$B/l" --destino /r --excluir "$p"
  _qa_estado 0 '1024 bytes'
  "$QA_RM_REAL" -f -- "$B/chamadas"
  _qa_rodar --dry-run sync --enviar --origem "$B/l" --destino /r --excluir "${p}a"
  _qa_estado "$QA_USO" '1025 bytes'
  _qa_sem_chamada '1025 bytes'
  printf -v p '%*s' 512 ''
  p=${p// /é}
  QA_AMBIENTE=(LC_ALL=C.UTF-8)
  _qa_rodar --dry-run sync --enviar --origem "$B/l" --destino /r --excluir "$p"
  _qa_estado 0 '512 x é = 1024 bytes'
  "$QA_RM_REAL" -f -- "$B/chamadas"
  _qa_rodar --dry-run sync --enviar --origem "$B/l" --destino /r --excluir "${p}é"
  _qa_estado "$QA_USO" '513 x é = 1026 bytes (conta bytes, nao caracteres)'
  _qa_sem_chamada '513 x é'
}

# ===========================================================================
# Ciclo 2 — QA-B4-01 corrigido (DIV-99), DIV-103, QA-B4-02 e QA-B4-03
# ===========================================================================

# QA-B4-E13 — QA-B4-01 em variacoes, `--receber --espelhar`: nomes nao UTF-8
# em varios niveis, `**` com pasta nao ASCII, pasta ancorada nao ASCII em
# caixa trocada, NFD com caixa trocada, `?` e `[é]` contra caractere
# multibyte e `a/**/b` atravessando componente invalido. Tudo filtrado fica,
# sem `rm`; o que a ancora NAO alcanca e o solto nao UTF-8 no escopo saem.
teste_qa_e13_div99_variacoes_niveis_curingas_ancora_e_nfd() {
  local -a ent=() fica=()
  local f
  local nfd=$'CAFE\xcc\x81.TXT'
  _qa_cenario
  _qa_basicas
  _qa_hash 'igual'
  _qa_local mantido.txt 'igual'
  fica=($'n\xfe/sub/AÇÃO/f' $'ÜBER/x\xff.txt' $'d\xff/'"$nfd" $'a\xff/b\xfe/É/c'
    $'q\xff/éx' $'s\xff/Éy' $'w/\xff/Ñ/b')
  for f in "${fica[@]}"; do _qa_local "$f" 'do operador'; done
  _qa_local $'y/ÜBER/x\xff.txt' 'some'
  _qa_local $'v\xff/solto.bin' 'some'
  _qa_arq mantido.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --receber --espelhar --confirmar --origem /r --destino "$B/l" \
    --excluir '**/ação/' --excluir '/über/' --excluir $'cafe\xcc\x81.txt' --excluir 'é/' \
    --excluir '?x' --excluir '[é]y' --excluir 'w/**/b'
  _qa_estado 0 'conclui'
  for f in "${fica[@]}"; do
    assert_arquivo_existe "$B/l/$f" "filtrado nao UTF-8 fica: ${f@Q}"
  done
  assert_arquivo_ausente "$B/l/y/ÜBER/x"$'\xff'.txt 'a ancora /über/ nao alcanca y/ÜBER'
  assert_arquivo_ausente "$B/l/v"$'\xff'/solto.bin 'o nao UTF-8 no escopo sai (o espelho funciona)'
  _qa_rm_tocou 'AÇÃO' && _harness_falhar 'rm sobre **/ação/'
  _qa_rm_tocou "$nfd" && _harness_falhar 'rm sobre o NFD filtrado'
  return 0
}

# QA-B4-E14 — QA-B4-01 no `--enviar --espelhar`: o filtrado local nao UTF-8
# nao e enviado, e o par remoto (UTF-8) da pasta excluida nao e apagado.
teste_qa_e14_div99_enviar_nao_envia_nem_apaga_filtrado() {
  local -a ent=()
  _qa_cenario
  _qa_basicas
  _qa_hash 'K'
  _qa_local keep.txt 'K'
  _qa_local $'lixo\xff/Éfoto.jpg' 'foto'
  _qa_local $'ÜBER/z\xfe.txt' 'z'
  _qa_arq keep.txt "$QA_HASH" && ent+=("$QA_E")
  _qa_arq 'über/remoto.txt' && ent+=("$QA_E")
  _qa_arq 'solto' && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --enviar --espelhar --confirmar --origem "$B/l" --destino /r \
    --excluir 'éFOTO.jpg' --excluir '/Über/'
  _qa_estado 0 'conclui'
  _qa_coletar files/upload
  assert_nao_contem 'foto' "$QA_LISTA" 'filtrado nao UTF-8 nao e enviado'
  assert_nao_contem 'BER/' "$QA_LISTA" 'conteudo da pasta excluida nao e enviado'
  _qa_deletes_sao '{"path":"/r/solto"}' 'par remoto da pasta excluida fica; solto sai'
}

# QA-B4-E15 — DIV-103 revisada: no nome local nao UTF-8, `--incluir` IMPRECISO
# (`[!é]*`, `[é]*`, `?x*`, `?/`) nunca poe o item no escopo do
# `--receber --espelhar` (ele fica, sem `rm`); `--incluir` PRECISO (literal nao
# ASCII com `*`, `*.dat`, conjunto so ASCII) continua casando, e o item no
# escopo sem par no remoto sai.
teste_qa_e15_div103_incluir_impreciso_nunca_apaga_nome_nao_utf8() {
  local -a ent=() fica=() sai=()
  local f
  _qa_cenario
  _qa_basicas
  _qa_hash 'igual'
  _qa_local mantido.dat 'igual'
  fica=($'\xffq.bin' $'é\xff.bin' $'éx\xff.bin' $'é/\xff.bin')
  sai=($'Ée\xff.txt' $'z\xff.dat' $'b\xff.k')
  for f in "${fica[@]}" "${sai[@]}"; do _qa_local "$f" 'do operador'; done
  _qa_arq mantido.dat "$QA_HASH" && ent+=("$QA_E")
  _qa_remoto "${ent[@]}"
  _qa_rodar sync --receber --espelhar --confirmar --origem /r --destino "$B/l" \
    --incluir '[!é]*' --incluir '[é]*' --incluir '?x*' --incluir '?/' \
    --incluir 'ée*' --incluir '*.dat' --incluir '[a-c]*.k'
  _qa_estado 0 'conclui'
  for f in "${fica[@]}"; do
    assert_arquivo_existe "$B/l/$f" "inclusao imprecisa nao poe no escopo: ${f@Q}"
    _qa_rm_tocou "$f" && _harness_falhar "rm sobre ${f@Q}"
  done
  for f in "${sai[@]}"; do
    assert_arquivo_ausente "$B/l/$f" "inclusao precisa casa e o espelho apaga: ${f@Q}"
  done
  assert_arquivo_existe "$B/l/mantido.dat" 'identico fica'
}

# QA-B4-E16 — QA-B4-02 e a leitura de QA-B4-01 (3a reproducao), pela
# biblioteca em processo isolado: `[]a]`, `[!]a]`, `[^]]` como no gitignore;
# `[]`, `[!]` e `[^]` recusados (2); `ü/` NAO casa a pasta `Ü\xfe` (outro
# nome), e casa `Ü/\xfea` (a pasta `Ü`).
teste_qa_e16_conjunto_com_fecha_literal_e_leitura_da_pasta() {
  local linha obtido=''
  _qa_cenario
  bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/filtro.sh"
    t() {
      dbx_filtro_limpar
      if ! dbx_filtro_adicionar excluir --excluir "$1"; then printf "%s|recusa\n" "$1"; return; fi
      if dbx_filtro_classificar "$2" nao; then printf "%s|%s|escopo\n" "$1" "$2"
      else printf "%s|%s|filtrado\n" "$1" "$2"; fi
    }
    t "[]a]" "]"; t "[]a]" "a"; t "[]a]" "b"
    t "[!]a]" "b"; t "[!]a]" "]"; t "[!]a]" "a"
    t "[^]]" "x"; t "[^]]" "]"
    t "[]" x; t "[!]" x; t "[^]" x
    t "ü/" "$2"
    t "ü/" "$3"
  ' _ "$DBX_HARNESS_RAIZ" $'Ü\xfe/a' $'Ü/\xfea' >"$B/tmp/e16" 2>&1
  while IFS= read -r linha || [[ -n $linha ]]; do obtido+="${linha}"$'\n'; done <"$B/tmp/e16"
  local esperado
  esperado='[]a]|]|filtrado
[]a]|a|filtrado
[]a]|b|escopo
[!]a]|b|filtrado
[!]a]|]|escopo
[!]a]|a|escopo
[^]]|x|filtrado
[^]]|]|escopo
[]|recusa
[!]|recusa
[^]|recusa
ü/|Ü'$'\xfe''/a|escopo
ü/|Ü/'$'\xfe''a|filtrado
'
  assert_igual "$esperado" "$obtido" 'conjuntos com ] literal e leitura de ü/'
}

# QA-B4-A02 — QA-B4-03: a ressalva de NFC/NFD esta na ajuda de sync,
# verificar e download, e no README.
teste_qa_a02_ressalva_nfc_nfd_na_ajuda_e_no_readme() {
  local cmd linha achou='nao'
  _qa_cenario
  for cmd in sync verificar download; do
    _qa_rodar help "$cmd"
    _qa_estado 0 "help $cmd"
    assert_contem 'NFC' "$QA_SAIDA" "ajuda de $cmd cita NFC"
    assert_contem 'NFD' "$QA_SAIDA" "ajuda de $cmd cita NFD"
  done
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha == *NFC* && $linha == *NFD* && $linha == *--excluir* ]] && achou='sim'
  done <"$DBX_HARNESS_RAIZ/README.md"
  assert_igual sim "$achou" 'README traz a ressalva NFC/NFD junto do --excluir'
}

# ===========================================================================
# Limite de banda (RF-82)
# ===========================================================================

# QA-B4-B01 — o limite vai so as requisicoes de CONTEUDO, como inteiro de
# bytes/s (numero sem unidade e B/s; `2k` e o piso exato); renovacao, conta e
# espaco nunca o levam; nada de `limit-rate` no `argv`.
teste_qa_b01_limite_so_no_conteudo_e_em_bytes() {
  local valor esperado ep lr corpo arg
  _qa_cenario
  _qa_basicas
  _qa_local a.txt 'abc'
  for valor in 5000 2k 3K 1m; do
    case $valor in 5000) esperado=5000 ;; 2k) esperado=2048 ;; 3K) esperado=3072 ;; 1m) esperado=1048576 ;; esac
    "$QA_RM_REAL" -f -- "$B/chamadas" "$B/argv"
    _qa_rodar upload --bwlimit "$valor" "$B/l/a.txt" /r/a.txt
    _qa_estado 0 "upload com [$valor]"
    _qa_contar files/upload
    assert_diferente 0 "$QA_CONTAGEM" "houve envio [$valor]"
    while IFS=$'\t' read -r ep lr corpo || [[ -n $ep ]]; do
      if [[ $ep == files/upload* ]]; then
        assert_igual "$esperado" "$lr" "conteudo leva o inteiro de bytes [$valor]"
      elif [[ $ep != SEM_REGRA* ]]; then
        assert_igual - "$lr" "metadado/controle sem limite: [$ep]"
      fi
    done <"$B/chamadas"
    while IFS= read -r arg || [[ -n $arg ]]; do
      assert_nao_contem 'limit-rate' "$arg" 'nunca no argv'
    done <"$B/argv"
  done
  : "$corpo"
}

# QA-B4-B02 — formato estrito e piso: todo valor invalido sai 2 sem chamada
# alguma, inclusive tentativa de injetar linha na configuracao do cURL.
teste_qa_b02_taxa_invalida_ou_hostil_sai_2_sem_rede() {
  local v
  local -a ruins=(0 0K 2047 1k 1K -2048 +2048 02048 2048B 2KB 2KiB 1T 1.5M 2e3 0x800 ' 2048'
    '2048 ' '' 1000000000 $'4096\nurl = "http://qa.invalid/"' '4096" -o /tmp/qa'
    '4096;id' '$(id)' '１０２４K' 'K' 'M2')
  _qa_cenario
  _qa_basicas
  _qa_local a.txt
  for v in "${ruins[@]}"; do
    _qa_rodar upload --limite-banda "$v" "$B/l/a.txt" /r/a.txt
    _qa_estado "$QA_USO" "upload [${v@Q}]"
    assert_nao_contem $'\n url' "$QA_ERRO" 'sem quebra crua na mensagem'
    _qa_rodar sync --enviar --origem "$B/l" --destino /r --bwlimit "$v"
    _qa_estado "$QA_USO" "sync [${v@Q}]"
    _qa_rodar download /r/a.txt "$B/baixado" --limite-banda "$v"
    _qa_estado "$QA_USO" "download [${v@Q}]"
  done
  _qa_sem_chamada 'taxas invalidas'
  assert_arquivo_ausente "$B/baixado" 'nada escrito'
}

# QA-B4-B03 — a opcao vence a variavel (nem a consulta); variavel vazia ou
# invalida sem a opcao sai 2 sem rede; variavel valida vira o limite; comandos
# sem conteudo ignoram a variavel; `verificar` recusa a opcao.
teste_qa_b03_variavel_e_opcao() {
  local ep lr corpo
  _qa_cenario
  _qa_basicas
  _qa_local a.txt 'abc'
  QA_AMBIENTE=(DBX_LIMITE_BANDA='lixo; rm -rf /')
  _qa_rodar upload --limite-banda 4096 "$B/l/a.txt" /r/a.txt
  _qa_estado 0 'a opcao vence a variavel invalida'
  "$QA_RM_REAL" -f -- "$B/chamadas"
  _qa_rodar upload "$B/l/a.txt" /r/a.txt
  _qa_estado "$QA_USO" 'variavel invalida sem a opcao'
  assert_contem 'DBX_LIMITE_BANDA' "$QA_ERRO" 'nomeia a variavel'
  _qa_sem_chamada 'variavel invalida'
  QA_AMBIENTE=(DBX_LIMITE_BANDA=)
  _qa_rodar sync --enviar --origem "$B/l" --destino /r
  _qa_estado "$QA_USO" 'variavel vazia nao vira "sem limite"'
  _qa_sem_chamada 'variavel vazia'
  QA_AMBIENTE=(DBX_LIMITE_BANDA=8K)
  _qa_rodar upload "$B/l/a.txt" /r/a.txt
  _qa_estado 0 'variavel valida'
  while IFS=$'\t' read -r ep lr corpo || [[ -n $ep ]]; do
    [[ $ep == files/upload* ]] && assert_igual 8192 "$lr" 'a variavel vira o limite'
  done <"$B/chamadas"
  QA_AMBIENTE=(DBX_LIMITE_BANDA=lixo)
  _qa_regra files/list_folder '*' 200 '{"entries":[],"has_more":false}'
  _qa_rodar list /r
  _qa_estado 0 'list ignora a variavel'
  _qa_rodar verificar --enviar --origem "$B/l" --destino /r --bwlimit 4096
  _qa_estado "$QA_USO" 'verificar recusa a opcao'
  : "$corpo"
}

# ===========================================================================
# Auditoria RNF-24 desta suite
# ===========================================================================

# QA-B4-A01 — esta suite nao captura bytes externos com substituicao de
# comando, nem usa `grep -c` sobre arquivo.
teste_qa_a01_suite_sem_captura_de_bytes_externos() {
  local linha g='grep' abre='$('
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha =~ ^[[:space:]]*# ]] && continue
    [[ $linha == *"$g -c"* ]] && _harness_falhar 'contagem por grep na suite' "[$linha]"
    [[ $linha == *"${abre}cat "* || $linha == *"${abre}<"* || $linha == *"${abre}_qa_"* ]] &&
      _harness_falhar 'captura de bytes externos' "[$linha]"
  done <"$DBX_HARNESS_RAIZ/tests/integracao/qa_filtros_banda_b4_test.sh"
  return 0
}

harness_executar "$@"
