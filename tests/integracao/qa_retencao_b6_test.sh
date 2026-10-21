#!/usr/bin/env bash
# Suite independente do QA, fase 6 do backlog: retencao e rotacao de backup
# (`dbx reter`/`retain`; F-10, RF-93..RF-100; DIV-130..DIV-157; RSK-62..66).
#
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx`, com duplo de `curl`
# proprio (independente do de `reter_test`). Os focos sao os P0:
#
#   - nenhum `delete_v2` sem `--confirmar`, ou com `--dry-run`, em qualquer
#     ordem, alias ou repeticao de opcao;
#   - nenhum `delete_v2` fora da listagem desta execucao, fora da pasta, fora do
#     padrao, de pasta ou de nao-arquivo, nem do item que fica (entradas
#     duplicadas, `name` incoerente, `..`, padroes ardilosos);
#   - `parent_rev` sempre, igual ao `rev` listado;
#   - sempre fica >= 1; `--manter N` exato com empates; `--dias D` com o corte
#     exato (funcao pura, com o "agora" fixado);
#   - zero `delete_v2` com listagem suspeita (`server_modified`, cursor, pagina
#     malformada, `Date`);
#   - falhas do `delete_v2`, segredo, saidas e sinal.
#
# Duplo de `curl`: regras em `$B/regras`, uma por linha,
# `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>resposta<TAB>uma` (padroes do
# shell); a primeira que casa responde. Na resposta, `@PATH@` vira o `path` do
# pedido e `@N@` um contador (cursores sempre novos). Codigo `REDE` simula
# falha de conexao; `SINAL:<NOME>:<codigo>` manda o sinal ao `dbx` e responde.
# O cabecalho `Date` sai com o instante corrente, ou com o texto de `$B/data`,
# ou nao sai com `$B/sem_data`; `data.<endpoint>` e `sem_data.<endpoint>`
# (barras trocadas por `_`) valem so para aquele endpoint. Toda chamada vai para `$B/chamadas` como
# `endpoint<TAB>corpo`; o argv para `$B/argv`. Sem regra: 400 e `SEM_REGRA`.
#
# Auditoria RNF-24: nenhum `$(...)` captura bytes externos (saida do programa,
# arquivo, registro); tudo e lido com `read`. Nenhum `grep -c` sobre arquivo.
#
# shellcheck disable=SC2016
# Justificativa: o duplo e os roteiros sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/retencao.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_CONFIG=$(dbx_errors_codigo_saida configuracao)
QA_REMOTO=$(dbx_errors_codigo_saida erro_remoto)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
QA_RECUSADO=$(dbx_errors_codigo_saida caminho_recusado)
readonly QA_USO QA_CONFIG QA_REMOTO QA_NAO_CONCLUIDA QA_RECUSADO
QA_BASH=$(command -v bash)
readonly QA_BASH
readonly QA_TOKEN='sl.QA6SENTINELAtoken9z'
readonly QA_REFRESH='QA6SENTINELArefresh8y'
readonly QA_SEGREDO='QA6SENTINELAsegredo7x'

B=''
QA_ESTADO=''
QA_SAIDA=''
QA_ERRO=''
QA_N=0
QA_CONTAGEM=0
QA_TEXTO=''
QA_ARQ=''
QA_LISTA=''
QA_APAGADOS=''
# Variaveis extras para o ambiente do `dbx` (NOME=valor), por caso.
declare -a QA_AMBIENTE=()

# _qa_cenario [raiz_remota] — credencial, duplo de `curl` e `sleep`, TMPDIR e
# estado privados.
_qa_cenario() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-b6.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado" "$B/trab"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"%s","refresh_token":"%s","raiz_remota":"%s"}' \
    "$QA_SEGREDO" "$QA_REFRESH" "${1:-/}" >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  QA_N=0
  {
    printf '#!%s\nQA=%q\nTOKEN=%q\n' "$QA_BASH" "$B" "$QA_TOKEN"
    cat <<'FIM'
export LC_ALL=C TZ=UTC0
cat >/dev/null
o=''; w=''; ant=''; url=''; dados=''; cab=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; -D) cab=$a ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
printf '%s\n' "$*" >>"$QA/argv"
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
ep=${url#https://api.dropboxapi.com/2/}
[[ $url == *oauth2/token* ]] && ep='oauth2/token'
printf '%s\t%s\n' "$ep" "$pedido" >>"$QA/chamadas"
cod=400 corpo='{"error_summary":"sem_regra/"}' achou=nao n=0
while IFS=$'\t' read -r rep rfi rco rar rvz; do
  n=$((n + 1))
  [[ -n $rep ]] || continue
  # shellcheck disable=SC2053
  [[ $ep == $rep && $pedido == $rfi ]] || continue
  if [[ $rvz == uma ]]; then
    mkdir "$QA/usada.$n" 2>/dev/null || continue
  fi
  achou=sim cod=$rco corpo=''
  [[ -r $QA/resp/$rar ]] && IFS= read -r -d '' corpo <"$QA/resp/$rar"
  break
done <"$QA/regras"
if [[ $achou == nao ]]; then
  if [[ $ep == oauth2/token ]]; then
    cod=200 corpo="{\"access_token\":\"$TOKEN\",\"token_type\":\"bearer\",\"expires_in\":14400}"
  else
    printf 'SEM_REGRA\t%s\n' "$ep" >>"$QA/chamadas"
  fi
fi
if [[ $corpo == *@N@* ]]; then
  k=0
  [[ -r $QA/contador ]] && read -r k <"$QA/contador"
  k=$((k + 1))
  printf '%s\n' "$k" >"$QA/contador"
  corpo=${corpo//@N@/$k}
fi
if [[ $corpo == *@PATH@* && $pedido =~ \"path\":\"([^\"]*)\" ]]; then
  corpo=${corpo//@PATH@/${BASH_REMATCH[1]}}
fi
case $cod in
  REDE) printf 'curl: (7) Failed to connect\n' >&2; exit 7 ;;
  SINAL:*)
    s=${cod#SINAL:}; cod=${s#*:}; s=${s%%:*}
    printf 'SINAL\t%s\n' "$s" >>"$QA/chamadas"
    kill -"$s" "$(<"$QA/pid")"
    ;;
esac
if [[ -n $cab ]]; then
  {
    printf 'HTTP/1.1 %s X\r\n' "$cod"
    sufixo=${ep//\//_}
    if [[ ! -e $QA/sem_data && ! -e $QA/sem_data.$sufixo ]]; then
      if [[ -r $QA/data.$sufixo ]]; then
        IFS= read -r d <"$QA/data.$sufixo"
      elif [[ -r $QA/data ]]; then
        IFS= read -r d <"$QA/data"
      else
        printf -v d '%(%a, %d %b %Y %H:%M:%S GMT)T' -1
      fi
      printf 'Date: %s\r\n' "$d"
    fi
    printf '\r\n'
  } >"$cab"
fi
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexit 0\n' "$QA_BASH" "$B/esperas" >"$B/bin/sleep"
  chmod +x "$B/bin/curl" "$B/bin/sleep"
}

# _qa_regra <endpoint> <filtro> <codigo> <corpo> [uma]
_qa_regra() {
  QA_N=$((QA_N + 1))
  printf '%s' "$4" >"$B/resp/r$QA_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$QA_N" "${5:-}" >>"$B/regras"
}

# _qa_rodar <argumentos...> — sem terminal, com teto de tempo; o codigo de
# saida e SEMPRE um de 0..15 (124/137 do teto = pendura, reprova).
_qa_rodar() {
  (
    cd "$B/trab" || exit 99
    env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
      TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      ${QA_AMBIENTE[@]+"${QA_AMBIENTE[@]}"} \
      timeout -k 2 "${QA_TETO:-60}" setsid -w "$QA_BASH" -c 'printf "%s" "$$" >"$1/pid"; shift; exec "$0" "$@"' \
      "$QA_BASH" "$B" "$QA_DBX" "$@" </dev/null >"$B/out" 2>"$B/err"
  )
  QA_ESTADO=$?
  # NUL (modo --null) vira quebra de linha: nenhum byte depois do primeiro NUL
  # escapa das assercoes.
  local pedaco
  local -a pedacos=()
  QA_SAIDA='' QA_ERRO=''
  mapfile -d '' pedacos <"$B/out"
  for pedaco in ${pedacos[@]+"${pedacos[@]}"}; do QA_SAIDA+="${pedaco%$'\0'}"$'\n'; done
  mapfile -d '' pedacos <"$B/err"
  for pedaco in ${pedacos[@]+"${pedacos[@]}"}; do QA_ERRO+="${pedaco%$'\0'}"$'\n'; done
  if ((QA_ESTADO < 0 || QA_ESTADO > 15)); then
    _harness_falhar 'codigo de saida fora de 0..15 (124/137: pendurou)' "obtido: [$QA_ESTADO]" "argv: [$*]" "stderr: [${QA_ERRO:0:300}]"
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

# _qa_deletes — os `path` de cada `delete_v2`, na ordem, separados por espaco,
# em QA_APAGADOS; os corpos inteiros em QA_LISTA (um por linha).
_qa_deletes() {
  local linha ep corpo
  # Em bytes: o `path` pode trazer UTF-8 invalido (QA-B6-S25).
  local LC_ALL=C
  QA_APAGADOS='' QA_LISTA=''
  [[ -f $B/chamadas ]] || return 0
  while IFS=$'\t' read -r ep corpo || [[ -n $ep ]]; do
    [[ $ep == files/delete_v2 ]] || continue
    QA_LISTA+="$corpo"$'\n'
    if [[ $corpo =~ \"path\":\"([^\"]*)\" ]]; then
      QA_APAGADOS+="${BASH_REMATCH[1]} "
    else
      QA_APAGADOS+="?SEM_PATH? "
    fi
  done <"$B/chamadas"
  QA_APAGADOS=${QA_APAGADOS% }
  return 0
}

_qa_zero_delete() { # <descricao>
  _qa_deletes
  assert_igual '' "$QA_APAGADOS" "zero delete_v2: $1"
}

_qa_sem_chamada() { assert_arquivo_ausente "$B/chamadas" "nenhuma chamada, nem renovacao: $1"; }

_qa_tmp_vazio() { # <descricao>
  local entrada lista=''
  for entrada in "$B"/tmp/* "$B"/tmp/.[!.]*; do
    [[ -e $entrada ]] && lista+=" ${entrada##*/}"
  done
  assert_igual '' "$lista" "TMPDIR vazio: $1"
}

# _qa_identidade <vetor_ficam> — DIV-167, DIV-169: QA_G_REVS e QA_G_IDS com o
# MESMO tamanho do vetor de caminhos de quem fica (1 quando o nome nao e vetor
# do chamador), com rev e id alheios a quem sai (`e00000000a1`, `id:qa-sai`).
# Assim as chamadas diretas da guarda isolam a condicao que cada caso prova.
declare -ga QA_G_REVS=() QA_G_IDS=()
_qa_identidade() {
  local n=1 k
  if [[ ${1-} =~ ^qa_[a-z0-9_]+$|^fica_[a-z]$ ]] && declare -p -- "$1" >/dev/null 2>&1; then
    local -n _qa_id_ref=$1
    [[ ${_qa_id_ref@a} == *[aA]* ]] && n=${#_qa_id_ref[@]}
  fi
  ((n > 0)) || n=1
  QA_G_REVS=() QA_G_IDS=()
  # shellcheck disable=SC2034  # lidos pela guarda por nome (nameref)
  for ((k = 0; k < n; k++)); do
    printf -v 'QA_G_REVS[k]' 'f%010x' "$k"
    QA_G_IDS[k]="id:qa-fica-$k"
  done
}

# _qa_arq <name> <server_modified> <rev|AUTO> [path_lower] [id] — entrada
# `file` em QA_ARQ. O `id` padrao e `id:<rev>`: duas entradas com o mesmo rev
# sao o MESMO arquivo (mesmo id e rev, como uma duplicata real). `AUTO` gera
# rev e id unicos (DIV-167, DIV-169: arquivos distintos nunca os repetem).
QA_SEQ_REV=0
_qa_arq() {
  local pl=${4-} rev=$3 id=${5-}
  if [[ $rev == AUTO ]]; then
    QA_SEQ_REV=$((QA_SEQ_REV + 1))
    printf -v rev 'a%010x' "$QA_SEQ_REV"
  fi
  [[ -n $id ]] || id="id:$rev"
  if [[ -z $pl ]]; then
    local LC_ALL=C.UTF-8
    pl="/bk/${1,,}"
  fi
  printf -v QA_ARQ '{".tag":"file","name":"%s","path_lower":"%s","path_display":"/Bk/%s","id":"%s","client_modified":"2026-01-01T00:00:00Z","server_modified":"%s","rev":"%s","size":10,"content_hash":"h"}' \
    "$1" "$pl" "$1" "$id" "$2" "$rev"
}

# _qa_lista <arquivo...> — pagina unica com as entradas de QA_LISTA (ja JSON).
_qa_pagina_unica() {
  _qa_regra files/list_folder '*' 200 "{\"entries\":[$1],\"cursor\":\"c0\",\"has_more\":false}"
}

_qa_apagar_ok() {
  _qa_regra files/delete_v2 '*' 200 '{"metadata":{".tag":"file","name":"x","path_lower":"@PATH@","rev":"0123456789a"}}'
}

# Cinco artefatos, do mais velho (1) ao mais novo (5), fora de ordem.
QA_CINCO=''
_qa_cinco() {
  local n lista=''
  for n in 3 1 5 2 4; do
    _qa_arq "db-$n.tar" "2026-10-0${n}T00:00:00Z" "00000000${n}a"
    lista+="${lista:+,}$QA_ARQ"
  done
  QA_CINCO=$lista
}
_qa_cinco
readonly QA_CINCO

# ===========================================================================
# C — barreira de confirmacao (RF-96, P0)
# ===========================================================================

# QA-B6-C00 — controle positivo: sem ele, todo "zero delete_v2" desta suite
# poderia ser o duplo que nao responde.
teste_qa_c00_controle_positivo_do_duplo() {
  local forma
  for forma in --confirmar --yes -y; do
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 "$forma"
    _qa_estado 0 "controle positivo com $forma"
    _qa_deletes
    assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' "$QA_APAGADOS" "$forma: os tres mais velhos, do mais velho ao mais novo"
    assert_contem 'modo=confirmado' "$QA_SAIDA" "$forma: modo confirmado"
    assert_contem 'apagados=3' "$QA_SAIDA" "$forma: resumo"
    _qa_contar permanently_delete
    assert_igual 0 "$QA_CONTAGEM" "$forma: nunca permanently_delete (RF-97(f))"
    _qa_contar delete_batch
    assert_igual 0 "$QA_CONTAGEM" "$forma: nunca delete_batch (RF-97(f))"
    _qa_contar SEM_REGRA
    assert_igual 0 "$QA_CONTAGEM" "$forma: nenhuma chamada fora do roteiro"
  done
}

# QA-B6-C01 — sem --confirmar: zero delete_v2 em qualquer ordem, alias e
# politica; o valor de opcao que parece --confirmar nao confirma.
teste_qa_c01_sem_confirmar_nenhum_delete_em_qualquer_ordem() {
  local forma
  local -a args
  set -f
  for forma in \
    'reter /bk --padrao db-*.tar --manter 1' \
    'retain --keep 1 --pattern db-*.tar /bk' \
    'reter --manter 1 /bk --padrao db-*.tar' \
    'reter /bk --dias 1 --padrao db-*.tar' \
    '--json reter /bk --padrao db-*.tar --days 1' \
    '--null retain /bk --pattern db-*.tar --keep 1' \
    'reter /bk --padrao --confirmar --manter 1' \
    'reter /bk --padrao -y --manter 1' \
    'reter /bk --padrao --yes --keep 1'; do
    read -ra args <<<"$forma"
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar "${args[@]}"
    _qa_estado 0 "plano: $forma"
    _qa_zero_delete "$forma"
    assert_contem 'modo=plano' "$QA_SAIDA" "modo plano: $forma"
    assert_contem 'nada foi apagado' "$QA_ERRO" "aviso em stderr: $forma"
  done
}

# QA-B6-C02 — --dry-run vence --confirmar e seus aliases, repetidos e em
# qualquer ordem.
teste_qa_c02_dry_run_vence_confirmar_em_toda_combinacao() {
  local forma
  local -a args
  set -f
  for forma in \
    '--dry-run reter /bk --padrao db-*.tar --manter 1 --confirmar' \
    '--dry-run reter /bk --padrao db-*.tar --manter 1 --yes' \
    '--dry-run reter /bk --padrao db-*.tar --manter 1 -y' \
    '--dry-run reter -y --confirmar --yes /bk --padrao db-*.tar --manter 1' \
    '--json --dry-run --null retain --confirmar /bk --keep 1 --pattern db-*.tar' \
    '--dry-run --dry-run reter /bk --padrao db-*.tar --dias 1 --confirmar' \
    '--debug --dry-run reter --yes --yes /bk --padrao db-*.tar --manter 1'; do
    read -ra args <<<"$forma"
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar "${args[@]}"
    _qa_estado 0 "simulado: $forma"
    _qa_zero_delete "$forma"
    assert_contem 'simulado' "$QA_SAIDA" "modo simulado: $forma"
    assert_contem 'nada foi apagado' "$QA_ERRO" "aviso de simulacao: $forma"
  done
}

# QA-B6-C03 — grafias proximas de --confirmar nao confirmam nem chegam a rede:
# 2 com zero chamadas (nem a renovacao).
teste_qa_c03_grafias_vizinhas_sao_2_sem_rede() {
  local op
  for op in --confirm --Confirmar -Y --confirmar=sim --yes=1 -yy -- -n --force --dry-run \
    --confirmar-caminho -y1 --sim --CONFIRMAR; do
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 "$op"
    _qa_estado "$QA_USO" "grafia recusada: [$op]"
    _qa_sem_chamada "[$op]"
  done
  _qa_cenario
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter --yes
  _qa_estado "$QA_USO" '--manter consome --yes como valor: invalido'
  _qa_sem_chamada '--manter --yes'
}

# ===========================================================================
# S — selecao: nada fora da listagem, da pasta, do padrao, nem pasta (P0)
# ===========================================================================

# QA-B6-S01 — ACHADO: a mesma entrada (mesmo path_lower e rev) duas vezes na
# listagem. Com --manter 1, uma copia "fica" e a outra "sai": o delete_v2 vai
# para o UNICO arquivo, com o parent_rev vigente, e o servico o apaga. O
# minimo de 1 (RF-95(e)) e a guarda (6) olham o indice, nao o caminho.
teste_qa_s01_entrada_duplicada_nunca_apaga_o_que_fica() {
  local e5
  _qa_arq db-5.tar 2026-10-05T00:00:00Z 00000000005a
  e5=$QA_ARQ
  _qa_cenario
  _qa_pagina_unica "$e5,$e5"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_contar '"path":"/bk/db-5.tar"'
  assert_igual 0 "$QA_CONTAGEM" 'P0: o unico artefato (listado duas vezes) nunca e apagado'
  _qa_estado "$QA_REMOTO" 'listagem com path_lower repetido e incoerente: 10'
}

# QA-B6-S02 — ACHADO (mesma raiz): a duplicata vem em outra pagina, com outro
# server_modified e o name em outra caixa (mesma chave): o mais novo "fica" e a
# copia velha do MESMO caminho "sai".
teste_qa_s02_duplicata_entre_paginas_e_em_outra_caixa() {
  local e5 e5b
  _qa_arq db-5.tar 2026-10-05T00:00:00Z 00000000005a
  e5=$QA_ARQ
  _qa_arq DB-5.TAR 2026-10-01T00:00:00Z 00000000005a /bk/db-5.tar
  e5b=$QA_ARQ
  _qa_cenario
  _qa_regra files/list_folder '*' 200 "{\"entries\":[$e5],\"cursor\":\"c1\",\"has_more\":true}"
  _qa_regra files/list_folder/continue '*"c1"*' 200 "{\"entries\":[$e5b],\"cursor\":\"c2\",\"has_more\":false}"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_contar '"path":"/bk/db-5.tar"'
  assert_igual 0 "$QA_CONTAGEM" 'P0: o caminho do que fica nunca recebe delete_v2'
  _qa_estado "$QA_REMOTO" 'duplicata entre paginas: 10'
}

# QA-B6-S03 — `..` e `.` como name (resposta incoerente). P0: nunca vira
# delete_v2. RF-94(g): a execucao inteira sai 10 com ZERO delete_v2.
teste_qa_s03_ponto_e_ponto_ponto_como_nome() {
  local nome e1 e3 e4 ex
  for nome in .. .; do
    _qa_arq a-1.tar 2026-10-01T00:00:00Z 00000000001a
    e1=$QA_ARQ
    _qa_arq "$nome" 2026-10-02T00:00:00Z 00000000002a "/bk/$nome"
    ex=$QA_ARQ
    _qa_arq a-3.tar 2026-10-03T00:00:00Z 00000000003a
    e3=$QA_ARQ
    _qa_arq a-4.tar 2026-10-04T00:00:00Z 00000000004a
    e4=$QA_ARQ
    _qa_cenario
    _qa_pagina_unica "$e1,$ex,$e3,$e4"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao '*' --manter 1 --confirmar
    _qa_contar "\"path\":\"/bk/$nome\""
    assert_igual 0 "$QA_CONTAGEM" "P0: [$nome] nunca recebe delete_v2"
    _qa_estado "$QA_REMOTO" "[$nome] e listagem incoerente"
    _qa_zero_delete "RF-94(g): [$nome] derruba a execucao antes de qualquer exclusao"
  done
}

# QA-B6-S04 — name incoerente com path_lower: 10, zero delete_v2.
teste_qa_s04_name_incoerente_com_path_lower() {
  local par nome pl
  for par in 'db-0.tar|/bk/precioso.doc' 'db-0.tar|/bk/db-0.tar.bak' 'db-0.tar|/bk/db-00.tar' \
    'db-0.tar|/bk/xdb-0.tar' 'db-0.tar|/bk/db-0.ta'; do
    nome=${par%%|*} pl=${par#*|}
    _qa_arq "$nome" 2020-01-01T00:00:00Z 00000000000a "$pl"
    _qa_cenario
    _qa_pagina_unica "$QA_ARQ,$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "name [$nome] com path_lower [$pl]"
    _qa_zero_delete "[$pl]"
  done
}

# QA-B6-S05 — path_lower fora da pasta (outra, subpasta, prefixo, `//`,
# relativo, `..`): 10, zero delete_v2, mesmo sendo o mais velho.
teste_qa_s05_path_lower_fora_da_pasta() {
  local pl
  for pl in /outra/db-0.tar /bk/sub/db-0.tar /bkx/db-0.tar /bk//db-0.tar bk/db-0.tar \
    /bk/../db-0.tar /bk/./db-0.tar /db-0.tar /b/k/db-0.tar; do
    _qa_arq db-0.tar 2020-01-01T00:00:00Z 00000000000a "$pl"
    _qa_cenario
    _qa_pagina_unica "$QA_ARQ,$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "path_lower [$pl]"
    _qa_zero_delete "[$pl]"
  done
}

# QA-B6-S06 — pasta, apagado, tag em outra caixa e tag desconhecida com nome
# que casa o padrao: nunca apagados, so contados em `ignorados`.
teste_qa_s06_nao_arquivo_nunca_e_apagado() {
  local extras
  extras='{".tag":"folder","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":"id:p"}'
  extras+=',{".tag":"deleted","name":"db-00.tar","path_lower":"/bk/db-00.tar","path_display":"/Bk/db-00.tar"}'
  extras+=',{".tag":"File","name":"db-000.tar","path_lower":"/bk/db-000.tar","path_display":"/Bk/db-000.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000b"}'
  extras+=',{".tag":"symlink","name":"db-0000.tar","path_lower":"/bk/db-0000.tar","path_display":"/Bk/db-0000.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000c"}'
  _qa_cenario
  _qa_pagina_unica "$extras,$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado 0 'nao-arquivos ignorados'
  _qa_deletes
  assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar /bk/db-4.tar' "$QA_APAGADOS" 'so os arquivos que casam'
  assert_contem 'ignorados=4' "$QA_SAIDA" 'quatro ignorados'
  assert_contem 'candidatos=5' "$QA_SAIDA" 'cinco candidatos'
}

# QA-B6-S07 — fora do padrao nunca e apagado, mesmo sendo o mais velho.
teste_qa_s07_fora_do_padrao_nunca_e_apagado() {
  local nome lista=''
  for nome in db-0.tar.bak xdb-0.tar db-0.tarx 'db-0.tar ' db-0.TAR.gz; do
    _qa_arq "$nome" 2019-01-01T00:00:00Z AUTO
    lista+="$QA_ARQ,"
  done
  _qa_cenario
  _qa_pagina_unica "$lista$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'DB-*.TAR' --manter 2 --confirmar
  _qa_estado 0 'padrao em outra caixa casa sem caixa'
  _qa_deletes
  assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' "$QA_APAGADOS" 'so os que casam o nome inteiro'
  assert_contem 'fora_do_padrao=5' "$QA_SAIDA" 'cinco fora do padrao'
}

# _qa_nomes_do_plano — os `name` do plano (modo --null, bytes intactos) em
# QA_NOMES, separados por `|`, em ordem lexica de bytes.
QA_NOMES=''
_qa_nomes_do_plano() {
  local campo
  local -a campos=() nomes=()
  mapfile -d '' campos <"$B/out"
  for campo in ${campos[@]+"${campos[@]}"}; do
    campo=${campo%$'\0'}
    [[ $campo == name=* ]] && nomes+=("${campo#name=}")
  done
  # ordenacao por insercao, LC_ALL=C (sem utilitario externo)
  local -a ord=()
  local x i j
  for x in ${nomes[@]+"${nomes[@]}"}; do
    i=${#ord[@]}
    while ((i > 0)); do
      j=$((i - 1))
      local LC_ALL=C
      [[ ${ord[j]} > $x ]] || break
      ord[i]=${ord[j]}
      i=$j
    done
    ord[i]=$x
  done
  QA_NOMES=''
  for x in ${ord[@]+"${ord[@]}"}; do QA_NOMES+="$x|"; done
}

# QA-B6-S08 — padroes ardilosos: o glob nunca vira regex mais larga (meta de
# ERE, escape, conjunto, `**`). Plano (sem --confirmar), --null.
teste_qa_s08_padroes_ardilosos_nao_alargam_o_casamento() {
  local caso padrao nomes esperado nome lista
  local -a ns
  for caso in \
    'a.tar#aXtar;A.TAR;ab.tar#A.TAR|' \
    'a+#a+;aa;a#a+|' \
    '(a|b)#(a|b);a;b#(a|b)|' \
    'a|b#a|b;a;b#a|b|' \
    '^a$#^a$;a#^a$|' \
    '\*#*;x;ab#*|' \
    '?.tar#x.tar;.tar;xy.tar#x.tar|' \
    '[ab].tar#a.tar;b.tar;c.tar;[ab].tar#a.tar|b.tar|' \
    '[!a]*#a1;b1;!x#!x|b1|' \
    '**#x;y#x|y|' \
    'a\?#a?;ab#a?|' \
    '{a,b}#{a,b};a#{a,b}|' \
    'a.*#a.tar;a.;ab#a.|a.tar|' \
    '[.]tar#.tar;xtar#.tar|' \
    '[a-c]#B;d;-;a#B|a|' \
    '[^a]#a;b#b|' \
    'x[]]y#x]y;xay#x]y|' \
    '.*#.hidden;x#.hidden|' \
    '*.tar#.tar;a.tar;tar#.tar|a.tar|' \
    'a[.]b#a.b;axb#a.b|'; do
    padrao=${caso%%#*} nomes=${caso#*#} esperado=${nomes#*#} nomes=${nomes%%#*}
    IFS=';' read -ra ns <<<"$nomes"
    lista=''
    for nome in "${ns[@]}"; do
      _qa_arq "$nome" 2026-10-01T00:00:00Z AUTO
      lista+="${lista:+,}$QA_ARQ"
    done
    _qa_cenario
    _qa_pagina_unica "$lista"
    _qa_rodar --null reter /bk --padrao "$padrao" --manter 1
    _qa_estado 0 "padrao [$padrao]"
    _qa_nomes_do_plano
    assert_igual "$esperado" "$QA_NOMES" "candidatos do padrao [$padrao] sobre [$nomes]"
    _qa_zero_delete "plano [$padrao]"
  done
}

# QA-B6-S09 — NFC e NFD nunca se confundem no casamento, e (DIV-164, DIV-166)
# nome NFD na listagem nunca e apagado: a execucao inteira sai 10. Duas
# metades: (a) nome NFD com padrao NFC que o casaria se houvesse normalizacao:
# 10 e zero delete_v2, mesmo sendo o mais velho; (b) padrao NFD contra nome
# NFC: sem normalizacao, nada casa (0, candidatos 0).
teste_qa_s09_nfc_nao_casa_nfd() {
  local nfd=$'e\xcc\x81-1.tar' nfc_padrao=$'\xc3\xa9-*.tar' nfd_padrao=$'e\xcc\x81-*.tar'
  local e2
  _qa_arq $'\xc3\xa9-2.tar' 2026-10-02T00:00:00Z 0000000002a
  e2=$QA_ARQ
  _qa_arq "$nfd" 2026-10-01T00:00:00Z 0000000001a "/bk/$nfd"
  _qa_cenario
  _qa_pagina_unica "$QA_ARQ,$e2"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao "$nfc_padrao" --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'nome NFD na listagem e incoerente (DIV-164)'
  _qa_zero_delete 'NFD'
  _qa_arq $'\xc3\xa9-1.tar' 2026-10-01T00:00:00Z 0000000001a
  _qa_cenario
  _qa_pagina_unica "$QA_ARQ,$e2"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao "$nfd_padrao" --manter 1 --confirmar
  _qa_estado 0 'padrao NFD contra nomes NFC'
  assert_contem 'candidatos=0' "$QA_SAIDA" 'sem normalizacao: o padrao NFD nao casa NFC'
  _qa_zero_delete 'padrao NFD'
}

# QA-B6-S10 — a autorizacao e so a listagem DESTA execucao: um plano anterior
# (outra listagem) nao vaza para a seguinte.
teste_qa_s10_plano_anterior_nao_autoriza_nada() {
  local e4 e5
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1
  _qa_estado 0 'plano da primeira execucao'
  _qa_arq db-4.tar 2026-10-04T00:00:00Z 00000000004a
  e4=$QA_ARQ
  _qa_arq db-5.tar 2026-10-05T00:00:00Z 00000000005a
  e5=$QA_ARQ
  : >"$B/regras"
  rm -f "$B/chamadas"
  _qa_pagina_unica "$e4,$e5"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado 0 'segunda execucao'
  _qa_deletes
  assert_igual '/bk/db-4.tar' "$QA_APAGADOS" 'so o que a segunda listagem autoriza'
}

# QA-B6-S11 — guarda por item injetada direto (segunda barreira, RF-97(b)).
teste_qa_s11_guarda_por_item_recusa_cada_condicao() {
  local linha tag pl nome pasta raiz acao prim esperado obtido
  # DIV-163: a lista de quem fica e sempre passada (DIV-162 recusa sem ela). O
  # caminho dela difere do de toda linha, e as linhas de controle (0) provam
  # que ela nao e o motivo de nenhuma recusa: cada condicao recusa sozinha.
  # shellcheck disable=SC2034  # lido pela guarda por nome
  local -a qa_ficam=(/bk/db-9.tar)
  # DIV-169: rev e id de quem sai e de quem fica sempre alheios entre si, para
  # que a identidade (DIV-167) nunca seja o motivo da recusa de uma linha.
  _qa_identidade qa_ficam
  dbx_filtro_nome_preparar --padrao 'db-*.tar' || _harness_falhar 'preparo do padrao'
  while IFS='|' read -r tag pl nome pasta raiz acao prim esperado; do
    [[ -n $tag ]] || continue
    obtido=0
    dbx_retencao_guarda "$tag" "$pl" "$nome" "$pasta" "$raiz" "$acao" "$prim" qa_ficam \
      e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
    assert_igual "$esperado" "$obtido" "guarda [$tag|$pl|$nome|$pasta|$raiz|$acao|$prim]"
  done <<'TABELA'
file|/bk/db-1.tar|db-1.tar|/bk|/|sai|nao|0
file|/bk/db-1.tar|DB-1.TAR|/BK|/|sai|nao|0
file|/db-1.tar|db-1.tar||/|sai|nao|0
folder|/bk/db-1.tar|db-1.tar|/bk|/|sai|nao|1
File|/bk/db-1.tar|db-1.tar|/bk|/|sai|nao|1
|/bk/db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|/bk/sub/db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|/bkx/db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|/bk//db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|/bk/./db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|/bk/../db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|bk/db-1.tar|db-1.tar|/bk|/|sai|nao|1
file|/bk/db-1.tar/|db-1.tar|/bk|/|sai|nao|1
file|/bk/db-1.tar|db-2.tar|/bk|/|sai|nao|1
file|/bk/db-1.tar|x/db-1.tar|/bk|/|sai|nao|1
file|/bk/x.doc|x.doc|/bk|/|sai|nao|1
file|/bk/db-1.tar|db-1.tar|/bk|/outra|sai|nao|1
file|/bk/db-1.tar|db-1.tar|/bk|/bkx|sai|nao|1
file|/bk/db-1.tar|db-1.tar|/bk|/|fica|nao|1
file|/bk/db-1.tar|db-1.tar|/bk|/|sai|sim|1
file|/bk/db-1.tar|db-1.tar|/bk|/|sai||1
TABELA
  dbx_filtro_nome_preparar --padrao '*' || _harness_falhar 'preparo do padrao amplo'
  for nome in .. .; do
    obtido=0
    dbx_retencao_guarda file "/bk/$nome" "$nome" /bk / sai nao qa_ficam e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
    assert_igual 1 "$obtido" "guarda recusa [$nome]"
  done
}

# QA-B6-S12 — confinamento do argumento (RF-97(a)): fora da raiz remota, `..`
# acima dela ou byte de controle: 13 com ZERO chamadas, mesmo com --confirmar.
teste_qa_s12_pasta_fora_da_raiz_e_13_sem_chamada() {
  local pasta
  for pasta in / /bkx /BKX /bk/../x /bk/../../bk2 $'/bk\n' $'/bk/a\rb' /outra; do
    _qa_cenario /bk
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter "$pasta" --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_RECUSADO" "pasta [$pasta] com raiz /bk"
    _qa_sem_chamada "pasta [$pasta]"
  done
}

# ===========================================================================
# R — parent_rev (RF-97(c), P0)
# ===========================================================================

# QA-B6-R01 — corpo exato de cada delete_v2: path_lower e parent_rev listados.
teste_qa_r01_corpo_exato_com_parent_rev_listado() {
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  _qa_estado 0 'confirmado'
  _qa_deletes
  assert_igual '{"path":"/bk/db-1.tar","parent_rev":"000000001a"}
{"path":"/bk/db-2.tar","parent_rev":"000000002a"}
{"path":"/bk/db-3.tar","parent_rev":"000000003a"}
' "$QA_LISTA" 'cada delete_v2 com o path_lower e o rev da listagem, nada mais'
}

# QA-B6-R02 — rev malformado num candidato: 10, zero delete_v2.
teste_qa_r02_rev_malformado_e_10_sem_delete() {
  local rev entrada
  for rev in '"ABCDEF0123"' '"12345678"' '"0123456789g"' '""' '123456789' 'null' '"0123456789 "' '["0123456789"]'; do
    entrada="{\".tag\":\"file\",\"name\":\"db-0.tar\",\"path_lower\":\"/bk/db-0.tar\",\"path_display\":\"/Bk/db-0.tar\",\"server_modified\":\"2020-01-01T00:00:00Z\",\"rev\":$rev,\"size\":1}"
    _qa_cenario
    _qa_pagina_unica "$entrada,$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "rev [$rev]"
    _qa_zero_delete "rev [$rev]"
  done
  entrada='{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","size":1}'
  _qa_cenario
  _qa_pagina_unica "$entrada,$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'rev ausente'
  _qa_zero_delete 'rev ausente'
}

# QA-B6-R03 — parent_rev divergente (conflito): falha do item, segue, 14; o
# item nunca e repetido sem parent_rev.
teste_qa_r03_conflito_segue_e_nunca_repete_sem_parent_rev() {
  local corpo
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO"
  _qa_regra files/delete_v2 '*"/bk/db-2.tar"*' 409 '{"error_summary":"path_write/conflict/file/..","error":{".tag":"path_write"}}'
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  _qa_estado "$QA_NAO_CONCLUIDA" 'conflito e falha de item'
  _qa_deletes
  assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' "$QA_APAGADOS" 'segue com os demais, sem repetir o do conflito'
  while IFS= read -r corpo; do
    [[ -z $corpo || $corpo == *'"parent_rev":"00000000'[1-3]'a"}' ]] ||
      _harness_falhar 'delete_v2 sem o parent_rev listado' "[$corpo]"
  done <<<"$QA_LISTA"
  assert_contem 'motivo=conflito' "$QA_SAIDA" 'motivo do item'
  assert_contem 'falhas=1' "$QA_SAIDA" 'uma falha'
  assert_contem 'apagados=2' "$QA_SAIDA" 'dois apagados'
}

# ===========================================================================
# P — politica: minimo de 1, --manter exato, --dias exato (P0)
# ===========================================================================

# QA-B6-P01 — empate de server_modified: o maior nome sem caixa e o mais novo.
teste_qa_p01_empate_pelo_nome_sem_caixa() {
  local nome lista=''
  for nome in b.tar A.tar c.tar B2.tar a1.tar; do
    _qa_arq "$nome" 2026-10-05T00:00:00Z AUTO
    lista+="${lista:+,}$QA_ARQ"
  done
  _qa_cenario
  _qa_pagina_unica "$lista"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao '*.tar' --manter 2 --confirmar
  _qa_estado 0 'empate'
  _qa_deletes
  assert_igual '/bk/a.tar /bk/a1.tar /bk/b.tar' "$QA_APAGADOS" 'ficam c.tar e B2.tar; saem do menor nome ao maior'
}

# QA-B6-P02 — --manter N de 1 a 6 sobre 5: sai exatamente max(0, 5-N), e o
# mais novo nunca.
teste_qa_p02_manter_n_exato() {
  local n esperado
  for n in 1 2 3 4 5 6; do
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter "$n" --confirmar
    _qa_estado 0 "--manter $n"
    _qa_deletes
    case $n in
      1) esperado='/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar /bk/db-4.tar' ;;
      2) esperado='/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' ;;
      3) esperado='/bk/db-1.tar /bk/db-2.tar' ;;
      4) esperado='/bk/db-1.tar' ;;
      *) esperado='' ;;
    esac
    assert_igual "$esperado" "$QA_APAGADOS" "--manter $n"
    assert_contem "ficam=$((n > 5 ? 5 : n))" "$QA_SAIDA" "ficam com --manter $n"
  done
}

# _qa_plano <dias> <agora> <sm...> — dbx_retencao_planejar com o "agora" fixo;
# a acao de cada indice em QA_TEXTO (`i=acao ...`).
_qa_plano() {
  local dias=$1 agora=$2 i
  shift 2
  local -a sm=("$@") chave=() pl=()
  for i in "${!sm[@]}"; do
    chave[i]="n$i" pl[i]="/bk/n$i"
  done
  dbx_retencao_planejar dias "$dias" "$agora" sm chave pl || _harness_falhar "planejar recusou: $DBX_RETENCAO_MOTIVO"
  QA_TEXTO=''
  for i in "${!sm[@]}"; do QA_TEXTO+="$i=${DBX_RETENCAO_ACAO[i]} "; done
  QA_TEXTO=${QA_TEXTO% }
}

# QA-B6-P03 — --dias: corte inclusivo ao segundo, futuro fica (funcao pura).
teste_qa_p03_dias_corte_exato() {
  _qa_plano 7 1792497600 2026-10-13T12:00:00Z 2026-10-13T11:59:59Z 2027-01-01T00:00:00Z \
    2026-10-20T12:00:00Z 2020-01-01T00:00:00Z 2026-10-13T12:00:01Z
  assert_igual '2026-10-13T12:00:00Z' "$DBX_RETENCAO_CORTE" 'corte = agora - 7 x 86400'
  assert_igual '2026-10-20T12:00:00Z' "$DBX_RETENCAO_AGORA" 'agora'
  assert_igual '0=fica 1=sai 2=fica 3=fica 4=sai 5=fica' "$QA_TEXTO" 'corte inclusivo'
  assert_igual 'nao' "$DBX_RETENCAO_MINIMO" 'sem o minimo'
  assert_igual 4 "$DBX_RETENCAO_FICAM" 'ficam'
  assert_igual 2 "$DBX_RETENCAO_SAEM" 'saem'
}

# QA-B6-P04 — todos fora do corte: so o mais novo fica (empate pelo nome).
teste_qa_p04_minimo_de_um_com_empate() {
  _qa_plano 1 1792497600 2020-01-01T00:00:00Z 2021-01-01T00:00:00Z 2021-01-01T00:00:00Z 2019-01-01T00:00:00Z
  assert_igual '0=sai 1=sai 2=fica 3=sai' "$QA_TEXTO" 'fica o mais novo; empate, o maior nome (n2 > n1)'
  assert_igual 'sim' "$DBX_RETENCAO_MINIMO" 'mantido pelo minimo'
  assert_igual 1 "$DBX_RETENCAO_FICAM" 'um fica'
  _qa_plano 1 1792497600 2020-01-01T00:00:00Z
  assert_igual '0=fica' "$QA_TEXTO" 'um so candidato nunca sai'
}

# QA-B6-P05 — o carimbo do corte em datas limite (antes de 1970, bissexto,
# 2100 nao bissexto).
teste_qa_p05_carimbo_do_corte_em_datas_limite() {
  _qa_plano 36500 1792497600 2026-10-20T00:00:00Z
  assert_igual '1926-11-14T12:00:00Z' "$DBX_RETENCAO_CORTE" '--dias 36500'
  _qa_plano 1 1709251200 2024-03-01T00:00:00Z
  assert_igual '2024-02-29T00:00:00Z' "$DBX_RETENCAO_CORTE" 'bissexto'
  _qa_plano 1 4107542400 2100-03-01T00:00:00Z
  assert_igual '2100-02-28T00:00:00Z' "$DBX_RETENCAO_CORTE" '2100 nao e bissexto'
}

# QA-B6-P06 — validade do server_modified (funcao pura).
teste_qa_p06_carimbo_valido_so_na_forma_normalizada() {
  local c
  for c in 2024-02-29T23:59:59Z 2000-02-29T00:00:00Z 2026-12-31T23:59:59Z; do
    dbx_retencao_carimbo_valido "$c" || _harness_falhar "carimbo valido recusado: [$c]"
  done
  for c in 2023-02-29T00:00:00Z 2100-02-29T00:00:00Z 2026-13-01T00:00:00Z 2026-00-10T00:00:00Z \
    2026-10-00T00:00:00Z 2026-04-31T00:00:00Z 2026-10-01T24:00:00Z 2026-10-01T23:60:00Z \
    2026-10-01T23:59:60Z 2026-10-01T00:00:00.5Z 2026-10-01T00:00:00z 2026-10-01T00:00:00+00:00 \
    ' 2026-10-01T00:00:00Z' $'2026-10-01T00:00:00Z\n' 2026-10-01 '' 26-10-01T00:00:00Z; do
    if dbx_retencao_carimbo_valido "$c"; then
      _harness_falhar "carimbo invalido aceito: [$c]"
    fi
  done
}

# QA-B6-P07 — --dias com um so candidato muito velho: fica, com o aviso, e
# nenhum delete_v2 mesmo com --confirmar.
teste_qa_p07_dias_com_tudo_velho_mantem_o_mais_novo() {
  local lista
  _qa_arq db-1.tar 2001-01-01T00:00:00Z 0000000001a
  lista=$QA_ARQ
  _qa_arq db-2.tar 2002-01-01T00:00:00Z 0000000002a
  lista+=",$QA_ARQ"
  _qa_cenario
  _qa_pagina_unica "$lista"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
  _qa_estado 0 'tudo velho'
  _qa_deletes
  assert_igual '/bk/db-1.tar' "$QA_APAGADOS" 'o mais novo fica'
  assert_contem 'mantido_pelo_minimo=sim' "$QA_SAIDA" 'marca do minimo'
  assert_contem 'o mais novo foi mantido' "$QA_ERRO" 'aviso'
}

# QA-B6-P08 — --dias pelo executavel, com o relogio real e margem de um dia.
teste_qa_p08_dias_pelo_executavel() {
  local lista='' d sm n=0
  local TZ=UTC0
  export TZ
  for d in 2 6 8 30; do
    n=$((n + 1))
    printf -v sm '%(%Y-%m-%dT%H:%M:%SZ)T' $((EPOCHSECONDS - d * 86400))
    _qa_arq "db-$d.tar" "$sm" "000000000${n}a"
    lista+="${lista:+,}$QA_ARQ"
  done
  _qa_cenario
  _qa_pagina_unica "$lista"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --dias 7 --confirmar
  _qa_estado 0 '--dias 7'
  _qa_deletes
  assert_igual '/bk/db-30.tar /bk/db-8.tar' "$QA_APAGADOS" 'saem so os de mais de 7 dias, do mais velho ao mais novo'
}

# ===========================================================================
# L — listagem invalida: zero delete_v2 (P0)
# ===========================================================================

# QA-B6-L01 — server_modified invalido em qualquer candidato.
teste_qa_l01_server_modified_invalido_e_10_sem_delete() {
  local sm entrada
  for sm in '"2026-10-01T00:00:00.5Z"' '"2026-10-01T00:00:00+00:00"' '"2026-02-30T00:00:00Z"' \
    '"2026-02-29T00:00:00Z"' '"2026-10-01T24:00:00Z"' '"2026-10-01 00:00:00Z"' '""' '1791000000' 'null' \
    '"2026-10-01T00:00:00Z\n"' '"9999-99-99T99:99:99Z"'; do
    entrada="{\".tag\":\"file\",\"name\":\"db-9.tar\",\"path_lower\":\"/bk/db-9.tar\",\"path_display\":\"/Bk/db-9.tar\",\"server_modified\":$sm,\"rev\":\"0000000009a\",\"size\":1}"
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO,$entrada"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "server_modified [$sm]"
    _qa_zero_delete "server_modified [$sm]"
  done
  entrada='{".tag":"file","name":"db-9.tar","path_lower":"/bk/db-9.tar","path_display":"/Bk/db-9.tar","rev":"0000000009a","size":1}'
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO,$entrada"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'server_modified ausente'
  _qa_zero_delete 'server_modified ausente'
}

# QA-B6-L02 — cursor repetido NAO consecutivo (c1 -> c2 -> c1), com entradas
# em todas as paginas.
teste_qa_l02_cursor_repetido_nao_consecutivo() {
  local e1 e2 e3
  _qa_arq db-1.tar 2026-10-01T00:00:00Z 0000000001a
  e1=$QA_ARQ
  _qa_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a
  e2=$QA_ARQ
  _qa_arq db-3.tar 2026-10-03T00:00:00Z 0000000003a
  e3=$QA_ARQ
  _qa_cenario
  _qa_regra files/list_folder '*' 200 "{\"entries\":[$e1],\"cursor\":\"c1\",\"has_more\":true}"
  _qa_regra files/list_folder/continue '*"c1"*' 200 "{\"entries\":[$e2],\"cursor\":\"c2\",\"has_more\":true}"
  _qa_regra files/list_folder/continue '*"c2"*' 200 "{\"entries\":[$e3],\"cursor\":\"c1\",\"has_more\":true}"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'cursor repetido'
  _qa_zero_delete 'cursor repetido'
}

# QA-B6-L03 — has_more/cursor incoerentes.
teste_qa_l03_has_more_e_cursor_incoerentes() {
  local fim
  for fim in '"has_more":true' '"cursor":"","has_more":true' '"cursor":5,"has_more":true' \
    '"cursor":"c1","has_more":"true"' '"cursor":"c1","has_more":null' '"cursor":"c1"' \
    '"cursor":"c1","has_more":1' '"cursor":null,"has_more":true'; do
    _qa_cenario
    _qa_regra files/list_folder '*' 200 "{\"entries\":[$QA_CINCO],$fim}"
    _qa_regra files/list_folder/continue '*' 200 '{"entries":[],"cursor":"cz","has_more":false}'
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "pagina com [$fim]"
    _qa_zero_delete "[$fim]"
  done
}

# QA-B6-L04 — 2xx malformado na listagem (primeira ou segunda pagina).
teste_qa_l04_pagina_2xx_malformada() {
  local corpo pagina
  for pagina in 1 2; do
    for corpo in 'nao e json' '[]' '{"entries":null,"cursor":"c","has_more":false}' \
      '{"entries":["x"],"cursor":"c","has_more":false}' \
      '{"entries":[{".tag":"file","name":"db-0.tar","name":"db-9.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000a"}],"cursor":"c","has_more":false}' \
      '{"entries":[],"entries":[],"cursor":"c","has_more":false}' \
      '{"entries":[],"cursor":"c","has_more":false} x' \
      '{"entries":[{".tag":7,"name":"db-0.tar","path_lower":"/bk/db-0.tar"}],"cursor":"c","has_more":false}' \
      '{"entries":[],"cursor":"c","has_more":fals' ''; do
      _qa_cenario
      if ((pagina == 1)); then
        _qa_regra files/list_folder '*' 200 "$corpo"
      else
        _qa_regra files/list_folder '*' 200 "{\"entries\":[$QA_CINCO],\"cursor\":\"c1\",\"has_more\":true}"
        _qa_regra files/list_folder/continue '*' 200 "$corpo"
      fi
      _qa_apagar_ok
      _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
      _qa_estado "$QA_REMOTO" "pagina $pagina: [$corpo]"
      _qa_zero_delete "pagina $pagina: [$corpo]"
    done
  done
}

# QA-B6-L05 — teto de 1000 paginas (cursores sempre novos, paginas vazias).
teste_qa_l05_teto_de_paginas() {
  _qa_cenario
  _qa_regra files/list_folder '*' 200 "{\"entries\":[$QA_CINCO],\"cursor\":\"c0\",\"has_more\":true}"
  _qa_regra files/list_folder/continue '*' 200 '{"entries":[],"cursor":"k@N@","has_more":true}'
  _qa_apagar_ok
  QA_TETO=600 _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'teto'
  _qa_zero_delete 'teto'
  _qa_contar files/list_folder/continue
  assert_igual 999 "$QA_CONTAGEM" '1000 paginas lidas, nenhuma a mais'
}

# QA-B6-L06 — Date ausente, malformado ou divergente com --dias: zero delete_v2.
teste_qa_l06_date_com_dias() {
  local caso texto esperado
  local LC_ALL=C TZ=UTC0
  export TZ
  for caso in 'AUSENTE|10' 'Tue, 20 Oct 2026 12:00:00 UTC|10' 'Tuesday, 20-Oct-26 12:00:00 GMT|10' \
    'Tue Oct 20 12:00:00 2026|10' 'lixo|10' 'Tue, 20 oct 2026 12:00:00 GMT|10' \
    'Tue, 31 Feb 2026 12:00:00 GMT|10' 'Tue, 20 Oct 2026 25:00:00 GMT|10' \
    '+400|3' '-400|3' '+86400|3' '+60|0' '-60|0'; do
    texto=${caso%|*} esperado=${caso##*|}
    _qa_cenario
    case $texto in
      AUSENTE) : >"$B/sem_data" ;;
      [+-]*) printf '%(%a, %d %b %Y %H:%M:%S GMT)T\n' $((EPOCHSECONDS + texto)) >"$B/data" ;;
      *) printf '%s\n' "$texto" >"$B/data" ;;
    esac
    _qa_pagina_unica "$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
    case $esperado in
      0) _qa_estado 0 "Date [$texto]" ;;
      3) _qa_estado "$QA_CONFIG" "Date [$texto]" ;;
      *) _qa_estado "$QA_REMOTO" "Date [$texto]" ;;
    esac
    if [[ $esperado != 0 ]]; then
      _qa_zero_delete "Date [$texto]"
    fi
  done
}

# ===========================================================================
# D — falhas do delete_v2, segredo e saidas
# ===========================================================================

# QA-B6-D01 — not_found conta em ja_ausentes e nao muda o codigo.
teste_qa_d01_not_found_e_ja_ausente() {
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO"
  _qa_regra files/delete_v2 '*"/bk/db-2.tar"*' 409 '{"error_summary":"path_lookup/not_found/..","error":{".tag":"path_lookup"}}'
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  _qa_estado 0 'not_found nao e falha'
  _qa_deletes
  assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' "$QA_APAGADOS" 'segue'
  assert_contem 'ja_ausentes=1' "$QA_SAIDA" 'conta'
  assert_contem 'acao=ja_ausente' "$QA_SAIDA" 'linha do item'
  assert_contem 'apagados=2' "$QA_SAIDA" 'apagados'
}

# QA-B6-D02 — 5, 8 e 9 esgotados param antes do proximo e saem 14.
teste_qa_d02_autenticacao_taxa_e_rede_param() {
  local caso cod corpo
  for caso in '401|{"error_summary":"invalid_access_token/..","error":{".tag":"invalid_access_token"}}' \
    '429|{"error_summary":"too_many_requests/..","error":{"reason":{".tag":"too_many_requests"}}}' \
    'REDE|x'; do
    cod=${caso%%|*} corpo=${caso#*|}
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_regra files/delete_v2 '*"/bk/db-2.tar"*' "$cod" "$corpo"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_NAO_CONCLUIDA" "$cod para"
    _qa_contar '"/bk/db-3.tar"'
    assert_igual 0 "$QA_CONTAGEM" "$cod: nenhum delete_v2 depois da parada"
    _qa_contar '"/bk/db-4.tar"'
    assert_igual 0 "$QA_CONTAGEM" "$cod: nenhum delete_v2 depois da parada"
    assert_contem 'nao_tentados=2' "$QA_SAIDA" "$cod: os restantes nao tentados"
    assert_contem 'apagados=1' "$QA_SAIDA" "$cod: o que ja foi"
  done
}

# QA-B6-D03 — resposta 2xx incoerente do delete_v2: 10 e para antes do proximo.
teste_qa_d03_resposta_2xx_incoerente_para() {
  local corpo
  for corpo in '{"metadata":{".tag":"file","path_lower":"/bk/db-9.tar"}}' \
    '{"metadata":{".tag":"folder","path_lower":"@PATH@"}}' '{}' '{"metadata":null}' \
    '{"metadata":{".tag":"file","path_lower":"@PATH@","path_lower":"@PATH@"}}' 'nao json' '' \
    '{"metadata":{".tag":"file","path_lower":"/BK/DB-2.TAR"}}' '{"metadata":{"path_lower":"@PATH@"}}' \
    '{"metadata":{".tag":"file","path_lower":"@PATH@"},"metadata":{".tag":"file","path_lower":"@PATH@"}}'; do
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_regra files/delete_v2 '*"/bk/db-2.tar"*' 200 "$corpo"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "resposta [$corpo]"
    _qa_deletes
    assert_igual '/bk/db-1.tar /bk/db-2.tar' "$QA_APAGADOS" "para antes do proximo: [$corpo]"
    assert_contem 'apagados=1' "$QA_SAIDA" "resumo do que ja foi: [$corpo]"
  done
}

# QA-B6-D04 — permissao e 5xx esgotado sao falhas do item: segue, 14.
teste_qa_d04_falha_do_item_segue() {
  local caso cod corpo
  for caso in '403|{"error_summary":"path_write/no_write_permission/..","error":{".tag":"path_write"}}' \
    '500|erro interno'; do
    cod=${caso%%|*} corpo=${caso#*|}
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_regra files/delete_v2 '*"/bk/db-2.tar"*' "$cod" "$corpo"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_NAO_CONCLUIDA" "$cod: falha de item"
    _qa_contar '"/bk/db-4.tar"'
    assert_igual 1 "$QA_CONTAGEM" "$cod: segue ate o ultimo que sai"
    assert_contem 'falhas=1' "$QA_SAIDA" "$cod: uma falha"
    assert_contem 'apagados=3' "$QA_SAIDA" "$cod: tres apagados"
  done
}

# QA-B6-D05 — nenhum segredo em stdout, stderr nem no argv do curl, com
# --debug, nos caminhos de falha.
teste_qa_d05_sem_segredo_com_debug_e_falhas() {
  local canal s
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO"
  _qa_regra files/delete_v2 '*"/bk/db-1.tar"*' 409 "{\"error_summary\":\"path_write/no_write_permission/$QA_TOKEN\"}"
  _qa_regra files/delete_v2 '*"/bk/db-2.tar"*' 200 "{\"metadata\":{\".tag\":\"file\",\"path_lower\":\"/x/$QA_TOKEN\"}}"
  _qa_apagar_ok
  _qa_rodar --debug reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'resposta incoerente no segundo'
  _qa_ler_argv
  for s in "$QA_TOKEN" "$QA_REFRESH" "$QA_SEGREDO"; do
    for canal in "$QA_SAIDA" "$QA_ERRO" "$QA_TEXTO"; do
      assert_segredo_ausente "$s" "$canal" 'segredo fora de stdout, stderr e argv'
    done
  done
}

_qa_ler_argv() {
  QA_TEXTO=''
  [[ -r $B/argv ]] && IFS= read -r -d '' QA_TEXTO <"$B/argv"
  return 0
}

# QA-B6-D06 — texto, --json e --null descrevem o mesmo plano; resumo
# aritmeticamente coerente.
teste_qa_d06_saidas_coerentes() {
  local modo texto='' json='' nulo='' campo
  local -a campos=()
  for modo in texto json null; do
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    case $modo in
      texto) _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 ;;
      json) _qa_rodar --json reter /bk --padrao 'db-*.tar' --manter 2 ;;
      null) _qa_rodar --null reter /bk --padrao 'db-*.tar' --manter 2 ;;
    esac
    _qa_estado 0 "$modo"
    mapfile -d '' campos <"$B/out"
    local resumo=''
    for campo in ${campos[@]+"${campos[@]}"}; do
      local linha
      while IFS= read -r linha; do
        case $linha in acao=* | candidatos=* | ficam=* | saem=*) resumo+="$linha;" ;; esac
      done <<<"${campo%$'\0'}"
    done
    case $modo in texto) texto=$resumo ;; json) json=$resumo ;; null) nulo=$resumo ;; esac
  done
  assert_igual 'acao=fica;acao=fica;acao=sai;acao=sai;acao=sai;candidatos=5;ficam=2;saem=3;' "$texto" 'texto'
  assert_igual "$texto" "$json" '--json com o mesmo plano'
  assert_igual "$texto" "$nulo" '--null com o mesmo plano'
}

# ===========================================================================
# X — sinal
# ===========================================================================

# QA-B6-X01 — sinal durante a listagem com --confirmar: zero delete_v2.
teste_qa_x01_sinal_na_listagem_nada_apaga() {
  local sinal
  for sinal in TERM INT HUP; do
    _qa_cenario
    _qa_regra files/list_folder '*' 200 "{\"entries\":[$QA_CINCO],\"cursor\":\"c1\",\"has_more\":true}"
    _qa_regra files/list_folder/continue '*' "SINAL:$sinal:200" '{"entries":[],"cursor":"c2","has_more":false}'
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_zero_delete "$sinal na listagem"
    _qa_estado "$QA_NAO_CONCLUIDA" "$sinal na listagem sai 14 (RF-98(h))"
    _qa_tmp_vazio "$sinal na listagem"
  done
}

# QA-B6-X02 — sinal durante o primeiro delete_v2: 14, nenhum outro.
teste_qa_x02_sinal_no_delete_para_e_sai_14() {
  local sinal
  for sinal in TERM INT HUP; do
    _qa_cenario
    _qa_pagina_unica "$QA_CINCO"
    _qa_regra files/delete_v2 '*"/bk/db-1.tar"*' "SINAL:$sinal:200" '{"metadata":{".tag":"file","path_lower":"@PATH@"}}'
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_NAO_CONCLUIDA" "$sinal no delete"
    _qa_deletes
    assert_igual '/bk/db-1.tar' "$QA_APAGADOS" "$sinal: nenhum delete_v2 depois"
    assert_contem 'interrompido' "$QA_ERRO" "$sinal: resumo parcial"
    _qa_tmp_vazio "$sinal no delete"
  done
}

# ===========================================================================
# Ciclo 2 — tentativas de contornar DIV-158, DIV-159 e DIV-160
# ===========================================================================

# QA-B6-S13 — duplicata com outra `.tag` (pasta, apagado, tag desconhecida),
# antes ou depois do arquivo: 10, zero delete_v2 (DIV-158: qualquer `.tag`).
teste_qa_s13_duplicata_com_outra_tag() {
  local outra ordem e5 lista
  _qa_arq db-5.tar 2026-10-05T00:00:00Z 0000000005a
  e5=$QA_ARQ
  for outra in \
    '{".tag":"folder","name":"db-1.tar","path_lower":"/bk/db-1.tar","path_display":"/Bk/db-1.tar","id":"id:p"}' \
    '{".tag":"deleted","name":"db-1.tar","path_lower":"/bk/db-1.tar","path_display":"/Bk/db-1.tar"}' \
    '{".tag":"symlink","name":"db-1.tar","path_lower":"/bk/db-1.tar","path_display":"/Bk/db-1.tar"}'; do
    for ordem in antes depois; do
      if [[ $ordem == antes ]]; then lista="$outra,$QA_CINCO"; else lista="$QA_CINCO,$outra"; fi
      _qa_cenario
      _qa_pagina_unica "$lista"
      _qa_apagar_ok
      _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
      _qa_estado "$QA_REMOTO" "duplicata [$outra] $ordem"
      _qa_zero_delete "duplicata [$outra] $ordem"
    done
  done
  : "$e5"
}

# QA-B6-S14 — duplicata que difere so na caixa ASCII do path_lower, em
# paginas diferentes: 10, zero delete_v2.
teste_qa_s14_duplicata_em_caixa_ascii_entre_paginas() {
  local a b
  _qa_arq db-5.tar 2026-10-05T00:00:00Z 0000000005a
  a=$QA_ARQ
  _qa_arq db-5.tar 2026-10-01T00:00:00Z 0000000005a /bk/DB-5.TAR
  b=$QA_ARQ
  _qa_cenario
  _qa_regra files/list_folder '*' 200 "{\"entries\":[$a],\"cursor\":\"c1\",\"has_more\":true}"
  _qa_regra files/list_folder/continue '*' 200 "{\"entries\":[$b],\"cursor\":\"c2\",\"has_more\":false}"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'duplicata em caixa ASCII'
  _qa_zero_delete 'duplicata em caixa ASCII'
}

# QA-B6-S15 — ACHADO (ciclo 2): duplicata que difere so na caixa NAO ASCII.
# `/bk/é.tar` e `/bk/É.tar` sao o MESMO arquivo na Dropbox (sem caixa), com o
# mesmo rev; o `path_lower` com maiuscula ja e incoerente (nao e minusculo).
# As tres barreiras de DIV-158 dobram so o ASCII, e a copia "velha" sai.
teste_qa_s15_duplicata_em_caixa_nao_ascii() {
  local a b
  _qa_arq $'\xc3\xa9.tar' 2026-10-05T00:00:00Z 0000000005a $'/bk/\xc3\xa9.tar'
  a=$QA_ARQ
  _qa_arq $'\xc3\x89.tar' 2026-10-01T00:00:00Z 0000000005a $'/bk/\xc3\x89.tar'
  b=$QA_ARQ
  _qa_cenario
  _qa_pagina_unica "$a,$b"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
  _qa_zero_delete 'P0: o mesmo arquivo em outra caixa nao ASCII nunca e apagado'
  _qa_estado "$QA_REMOTO" 'path_lower fora da minuscula e incoerente: 10'
}

# QA-B6-S16 — DIV-159: path_lower nao normalizado em entrada que NAO e
# candidata (pasta, fora do padrao) tambem derruba; `%2e%2e` e nome literal.
teste_qa_s16_normalizacao_em_toda_entrada_e_porcento_literal() {
  local outra e
  for outra in \
    '{".tag":"folder","name":"..","path_lower":"/bk/..","path_display":"/Bk/..","id":"id:p"}' \
    '{".tag":"file","name":".","path_lower":"/bk/.","path_display":"/Bk/.","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000a"}' \
    '{".tag":"folder","name":"x","path_lower":"/bk/x/","path_display":"/Bk/x/","id":"id:p"}'; do
    _qa_cenario
    _qa_pagina_unica "$outra,$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "nao normalizado [$outra]"
    _qa_zero_delete "nao normalizado [$outra]"
  done
  _qa_arq '%2e%2e' 2020-01-01T00:00:00Z 0000000000a /bk/%2e%2e
  e=$QA_ARQ
  _qa_arq '%2fdb' 2020-01-02T00:00:00Z 0000000000b /bk/%2fdb
  e+=",$QA_ARQ"
  _qa_cenario
  _qa_pagina_unica "$e,$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao '*' --manter 5 --confirmar
  _qa_estado 0 'percent e literal'
  _qa_deletes
  assert_igual '/bk/%2e%2e /bk/%2fdb' "$QA_APAGADOS" 'o % nunca e decodificado: apaga o nome literal, na pasta'
}

# QA-B6-S17 — guarda (7) injetada: compara caminho, inclusive sem caixa (ASCII
# e fora dele: a Dropbox nao diferencia caixa).
teste_qa_s17_guarda_7_compara_caminho_e_falha_fechada() {
  local obtido
  # shellcheck disable=SC2034  # vetores lidos pela guarda por nome (nameref)
  local -a fica_a=(/bk/db-5.tar) fica_b=(/BK/DB-1.TAR) fica_c=(/bk/db-9.tar) fica_v=() fica_u=($'/bk/\xc3\x89.tar')
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'preparo do padrao'
  _qa_identidade fica_c
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao fica_c e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 0 "$obtido" 'controle: caminho diferente dos que ficam passa'
  obtido=0
  dbx_retencao_guarda file /bk/db-5.tar db-5.tar /bk / sai nao fica_a e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'mesmo caminho de quem fica: recusa'
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao fica_b e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'mesmo caminho em outra caixa ASCII: recusa'
  obtido=0
  dbx_retencao_guarda file $'/bk/\xc3\xa9.tar' $'\xc3\xa9.tar' /bk / sai nao fica_u e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'mesmo caminho em outra caixa nao ASCII: recusa'
  : "${fica_v[@]}"
}

# QA-B6-S18 — ACHADO (ciclo 2): a guarda (7) falha ABERTA. Sem a lista de quem
# fica (argumento omitido, vetor vazio ou nome de vetor inexistente), ela
# aprova; com pelo menos 1 candidato, sempre ha quem fique (RF-95(e)), entao
# lista vazia e incoerencia, nao "nenhum fica".
teste_qa_s18_guarda_sem_a_lista_de_quem_fica_falha_fechada() {
  local obtido
  local -a fica_v=()
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'preparo do padrao'
  # Listas de rev/id bem formadas (tamanho 1): a recusa vem da lista de
  # caminhos de quem fica, que e o que este caso prova.
  _qa_identidade qa_um_so
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao '' e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'guarda chamada sem a lista: falha fechada'
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao fica_v e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'lista de quem fica vazia: recusa'
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao qa_vetor_inexistente e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'nome de vetor inexistente: recusa'
}

# QA-B6-L07 — DIV-160: o Date conferido e o da ULTIMA pagina.
teste_qa_l07_date_da_ultima_pagina() {
  local caso p1 p2 esperado
  local LC_ALL=C TZ=UTC0
  export TZ
  for caso in 'lixo|AGORA|0' 'AUSENTE|AGORA|0' 'AGORA|AUSENTE|10' 'AGORA|lixo|10' 'AGORA|+400|3' '+400|AGORA|0'; do
    IFS='|' read -r p1 p2 esperado <<<"$caso"
    _qa_cenario
    _qa_data_de files_list_folder "$p1"
    _qa_data_de files_list_folder_continue "$p2"
    _qa_regra files/list_folder '*' 200 "{\"entries\":[$QA_CINCO],\"cursor\":\"c1\",\"has_more\":true}"
    _qa_regra files/list_folder/continue '*' 200 '{"entries":[],"cursor":"c2","has_more":false}'
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
    case $esperado in
      0) _qa_estado 0 "Date [$p1] e [$p2]" ;;
      3) _qa_estado "$QA_CONFIG" "Date [$p1] e [$p2]" ;;
      *) _qa_estado "$QA_REMOTO" "Date [$p1] e [$p2]" ;;
    esac
    [[ $esperado == 0 ]] || _qa_zero_delete "Date [$p1] e [$p2]"
  done
}

# ===========================================================================
# Ciclo 3 — DIV-161 (chave Unicode), DIV-162 (guarda (7) fechada), NFC/NFD
# ===========================================================================

# QA-B6-S19 — path_lower que nao e a propria chave (maiuscula fora do ASCII,
# largura total, sharp s maiusculo, sigma, I com ponto, digrafo), em entrada
# que nem e candidata: 10, zero delete_v2.
teste_qa_s19_path_lower_fora_da_minuscula_unicode_e_10() {
  local c
  for c in $'\xc3\x89' $'\xef\xbc\xa1' $'\xe1\xba\x9e' $'\xce\xa3' $'\xc4\xb0' $'\xc7\x84'; do
    _qa_arq "$c.tar" 2019-01-01T00:00:00Z 0000000000a "/bk/$c.tar"
    _qa_cenario
    _qa_pagina_unica "$QA_ARQ,$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "path_lower [/bk/$c.tar] fora da minuscula"
    _qa_zero_delete "[$c]"
  done
}

# QA-B6-S20 — minusculas legitimas fora do ASCII (sharp s, sigma final e
# medial, ligadura, largura total, e acentuado precomposto, digrafo dz com
# caron) nao dao falso 10: o custo de DIV-161 nao recai sobre nome valido.
# DIV-166: o `i` com ponto COMBINANTE (U+0307) saiu, porque DIV-164 o recusa;
# entrou `ǆ` (U+01C6), minuscula precomposta sem marca combinante.
# Ciclo 5 (DIV-168): UTF-8 valido de 4 bytes (emoji U+1F600, U+10FFFF e
# U+10000) e de 3 bytes no limite (U+FFFD, U+E000) nao dao falso 10; DIV-169:
# rev e id unicos por arquivo (AUTO).
teste_qa_s20_minusculas_unicode_legitimas_sem_falso_10() {
  local c lista=''
  for c in $'\xc3\x9f' $'\xcf\x82' $'\xcf\x83' $'\xef\xac\x81' $'\xef\xbd\x81' $'\xc3\xa9' $'\xc7\x86' \
    $'\xf0\x9f\x98\x80' $'\xf4\x8f\xbf\xbf' $'\xf0\x90\x80\x80' $'\xef\xbf\xbd' $'\xee\x80\x80'; do
    _qa_arq "$c.tar" 2019-01-01T00:00:00Z AUTO "/bk/$c.tar"
    lista+="$QA_ARQ,"
  done
  _qa_cenario
  _qa_pagina_unica "$lista$QA_CINCO"
  _qa_rodar reter /bk --padrao '*.tar' --manter 1
  _qa_estado 0 'nomes Unicode legitimos'
  assert_contem 'candidatos=17' "$QA_SAIDA" 'todos candidatos, nenhum colide'
}

# QA-B6-S21 — sem a localidade C.UTF-8 (nome inexistente) ou com o operador em
# LC_ALL=C: ASCII segue funcionando; fora do ASCII falha fechada (10) em
# qualquer entrada; a duplicata nao ASCII nunca e apagada.
teste_qa_s21_falha_fechada_sem_localidade_e_com_lc_all_c() {
  local a b pasta_e
  _qa_arq $'\xc3\xa9.tar' 2026-10-05T00:00:00Z 0000000005a $'/bk/\xc3\xa9.tar'
  a=$QA_ARQ
  _qa_arq $'\xc3\x89.tar' 2026-10-01T00:00:00Z 0000000005a $'/bk/\xc3\x89.tar'
  b=$QA_ARQ
  pasta_e=$'{".tag":"folder","name":"\xc3\xa9","path_lower":"/bk/\xc3\xa9","path_display":"/Bk/\xc3\xa9","id":"id:p"}'

  QA_AMBIENTE=(DBX_SYNC_LOCALIDADE=xx_XX.UTF-8)
  _qa_cenario
  _qa_pagina_unica "$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  _qa_estado 0 'sem localidade, so ASCII: funciona'
  _qa_deletes
  assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' "$QA_APAGADOS" 'sem localidade, ASCII'
  _qa_cenario
  _qa_pagina_unica "$pasta_e,$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  _qa_estado "$QA_REMOTO" 'sem localidade, pasta fora do ASCII: falha fechada'
  _qa_zero_delete 'sem localidade, pasta fora do ASCII'
  _qa_cenario
  _qa_pagina_unica "$a,$b"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
  _qa_zero_delete 'sem localidade, duplicata nao ASCII'

  QA_AMBIENTE=(LC_ALL=C LANG=C)
  _qa_cenario
  _qa_pagina_unica "$a,$b"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'LC_ALL=C: duplicata nao ASCII e 10'
  _qa_zero_delete 'LC_ALL=C, duplicata nao ASCII'
  _qa_arq $'\xc3\xa9-1.tar' 2026-10-01T00:00:00Z 0000000001a $'/bk/\xc3\xa9-1.tar'
  a=$QA_ARQ
  _qa_arq $'\xc3\xa9-2.tar' 2026-10-02T00:00:00Z 0000000002a $'/bk/\xc3\xa9-2.tar'
  _qa_cenario
  _qa_pagina_unica "$a,$QA_ARQ"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao $'\xc3\x89-*.tar' --manter 1 --confirmar
  _qa_estado 0 'LC_ALL=C do operador nao tira a localidade interna'
  _qa_deletes
  assert_igual $'/bk/\xc3\xa9-1.tar' "$QA_APAGADOS" 'LC_ALL=C: casa sem caixa e apaga o mais velho'
  QA_AMBIENTE=()
}

# QA-B6-S22 — guarda (7) com vetores malformados: recusa sempre (DIV-162).
# ACHADO (ciclo 3): vetor so com cadeias vazias, ou com elementos que nao sao
# caminho absoluto, e "lista vazia" disfarcada e ainda aprova.
teste_qa_s22_guarda_7_com_vetor_malformado() {
  local nome obtido
  # shellcheck disable=SC2034  # lidos pela guarda por nome
  local -a qa_v_vazio1=('') qa_v_vazio2=('' '') qa_v_lixo=(x y) qa_v_ok=(/bk/db-9.tar)
  # shellcheck disable=SC2034
  local -A qa_v_assoc=([a]=/bk/db-9.tar)
  # shellcheck disable=SC2034
  local qa_v_escalar=/bk/db-9.tar
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'preparo do padrao'
  _qa_identidade qa_v_ok
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao qa_v_ok e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 0 "$obtido" 'controle: vetor bem formado aprova'
  for nome in qa_v_vazio1 qa_v_vazio2 qa_v_lixo qa_v_assoc qa_v_escalar _rf_ficam alvo outro vetor_ficam \
    'qa_v_ok[0]' '1qa' 'qa v' '' 'qa_v_ok;x' '$qa_v_ok'; do
    _qa_identidade "$nome"
    obtido=0
    dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao "$nome" e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS 2>/dev/null || obtido=1
    assert_igual 1 "$obtido" "guarda (7) recusa o vetor [$nome]"
  done
}

# QA-B6-S23 — ACHADO (ciclo 3): o mesmo nome em NFC e em NFD. O servidor da
# Dropbox compoe os caracteres decompostos ao normalizar o caminho (evidencia
# de terceiros: maestral.utils.path.normalize, "Replicates the path
# normalization performed by Dropbox servers ... decomposed characters are
# converted to composed characters"): e o MESMO arquivo. Um `path_lower` em
# NFD ja e incoerente; com o mesmo rev, a copia "velha" apagaria o que fica.
teste_qa_s23_duplicata_nfc_e_nfd() {
  local a b
  _qa_arq $'\xc3\xa9.tar' 2026-10-05T00:00:00Z 0000000005a $'/bk/\xc3\xa9.tar'
  a=$QA_ARQ
  _qa_arq $'e\xcc\x81.tar' 2026-10-01T00:00:00Z 0000000005a $'/bk/e\xcc\x81.tar'
  b=$QA_ARQ
  _qa_cenario
  _qa_pagina_unica "$a,$b"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
  _qa_zero_delete 'P0: o mesmo arquivo em NFD nunca e apagado'
  _qa_estado "$QA_REMOTO" 'NFC e NFD do mesmo nome: 10'
}

# ===========================================================================
# Ciclo 4 — DIV-164 (marca combinante), DIV-165 (elementos da lista)
# ===========================================================================

# QA-B6-S24 — bordas dos cinco blocos (primeiro e ultimo ponto de codigo de
# cada um recusam; os vizinhos de fora passam), por bytes UTF-8.
teste_qa_s24_bordas_dos_blocos_combinantes() {
  local par cp bytes esperado obtido
  for par in \
    '0300:\xcc\x80:1' '036F:\xcd\xaf:1' '02FF:\xcb\xbf:0' '0370:\xcd\xb0:0' \
    '1AB0:\xe1\xaa\xb0:1' '1AFF:\xe1\xab\xbf:1' '1AAF:\xe1\xaa\xaf:0' '1B00:\xe1\xac\x80:0' \
    '1DC0:\xe1\xb7\x80:1' '1DFF:\xe1\xb7\xbf:1' '1DBF:\xe1\xb6\xbf:0' '1E00:\xe1\xb8\x80:0' \
    '20D0:\xe2\x83\x90:1' '20FF:\xe2\x83\xbf:1' '20CF:\xe2\x83\x8f:0' '2100:\xe2\x84\x80:0' \
    'FE20:\xef\xb8\xa0:1' 'FE2F:\xef\xb8\xaf:1' 'FE1F:\xef\xb8\x9f:0' 'FE30:\xef\xb8\xb0:0' \
    '0301:\xcc\x81:1' '0345:\xcd\x85:1'; do
    IFS=':' read -r cp bytes esperado <<<"$par"
    printf -v bytes '%b' "$bytes"
    # obtido 1 = a funcao achou marca (status 1); 0 = sem marca.
    obtido=0
    dbx_retencao_sem_combinante "/bk/a${bytes}b.tar" || obtido=1
    assert_igual "$esperado" "$obtido" "U+$cp no meio do nome (1 = tem marca)"
    obtido=0
    dbx_retencao_sem_combinante "/bk/a${bytes}" || obtido=1
    assert_igual "$esperado" "$obtido" "U+$cp no fim do caminho"
  done
}

# QA-B6-S25 — UTF-8 invalido, truncado ou overlong no path_lower: a resposta
# nao e de servidor coerente (JSON exige UTF-8 valido). Pelo menos nunca vira
# delete_v2 que colida com o que fica; o esperado e 10 com zero delete_v2.
# ACHADO (ciclo 4, P1): o overlong `e`+E0 8C 81 (U+0301 em 3 bytes) passa por
# DIV-164 (que olha so a forma canonica CC 81) e recebe delete_v2.
teste_qa_s25_utf8_invalido_no_path_lower() {
  local bytes nome a aceitos=''
  _qa_arq $'\xc3\xa9.tar' 2026-10-05T00:00:00Z 0000000005a $'/bk/\xc3\xa9.tar'
  a=$QA_ARQ
  # Ciclo 5: rev e id DISTINTOS do que fica (AUTO), para medir a barreira de
  # UTF-8 (DIV-168) sozinha, sem a de identidade (DIV-167); e todas as formas:
  # overlong de 2, 3 e 4 bytes, surrogate, acima de U+10FFFF, 5 e 6 bytes,
  # F5-FF, truncado de 2, 3 e 4 bytes e continuacao solta.
  for bytes in '\xe0\x8c\x81' '\xc0\x81' '\xc1\xbf' '\xf0\x80\x80\x80' '\xcc' '\x81' '\xbf' \
    '\xf8\x88\x80\x80\x80' '\xfc\x84\x80\x80\x80\x80' '\xed\xa0\x80' '\xed\xbf\xbf' \
    '\xf4\x90\x80\x80' '\xf5\x80\x80\x80' '\xfe' '\xff' '\xe3\x81' '\xf0\x9f\x98' '\xc3\xa9\x80'; do
    printf -v nome 'e%b.tar' "$bytes"
    _qa_arq "$nome" 2026-10-01T00:00:00Z AUTO "/bk/$nome"
    _qa_cenario
    _qa_pagina_unica "$a,$QA_ARQ"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
    _qa_contar $'"path":"/bk/\xc3\xa9.tar"'
    assert_igual 0 "$QA_CONTAGEM" "P0: o que fica nunca e apagado [$bytes]"
    _qa_deletes
    [[ -z $QA_APAGADOS && $QA_ESTADO == "$QA_REMOTO" ]] || aceitos+="[$bytes]=$QA_ESTADO "
  done
  assert_igual '' "$aceitos" 'UTF-8 invalido no path_lower: 10 com zero delete_v2 em todas as formas'
}

# QA-B6-S26 — ACHADO (ciclo 4): composicoes canonicas FORA dos cinco blocos.
# NFC compoe tambem kana + dakuten (U+3099/U+309A), jamo hangul conjuntos
# (U+1100-11FF) e marcas indicas (ex. U+093C): `が` e `か`+U+3099, `한` e
# U+1112 U+1161 U+11AB, `ऩ` e U+0928 U+093C sao o MESMO arquivo para o
# servidor que compoe (mesma evidencia de QA-B6-05). Nomes japoneses vindos do
# macOS chegam em NFD com frequencia. Com o mesmo rev, a copia "velha" sai.
teste_qa_s26_composicao_canonica_fora_dos_blocos() {
  local par nfc nfd a b aceitos=''
  for par in '\xe3\x81\x8c:\xe3\x81\x8b\xe3\x82\x99' \
    '\xe3\x81\xb1:\xe3\x81\xaf\xe3\x82\x9a' \
    '\xed\x95\x9c:\xe1\x84\x92\xe1\x85\xa1\xe1\x86\xab' \
    '\xe0\xa4\xa9:\xe0\xa4\xa8\xe0\xa4\xbc'; do
    printf -v nfc '%b' "${par%%:*}"
    printf -v nfd '%b' "${par#*:}"
    _qa_arq "$nfc.tar" 2026-10-05T00:00:00Z 0000000005a "/bk/$nfc.tar"
    a=$QA_ARQ
    _qa_arq "$nfd.tar" 2026-10-01T00:00:00Z 0000000005a "/bk/$nfd.tar"
    b=$QA_ARQ
    _qa_cenario
    _qa_pagina_unica "$a,$b"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
    _qa_deletes
    [[ -z $QA_APAGADOS && $QA_ESTADO == "$QA_REMOTO" ]] || aceitos+="[$nfc]=$QA_ESTADO:$QA_APAGADOS "
  done
  assert_igual '' "$aceitos" 'P0: o mesmo arquivo em NFD nunca e apagado; NFC e NFD saem 10'
}

# QA-B6-S27 — guarda (7), DIV-165: todo elemento da lista de quem fica e
# caminho canonico; qualquer elemento fora disso recusa.
teste_qa_s27_guarda_7_elementos_malformados() {
  local el obtido
  local -a qa_v=()
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'preparo do padrao'
  # shellcheck disable=SC2034  # lido pela guarda por nome
  qa_v=(/bk/db-9.tar)
  _qa_identidade qa_v
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao qa_v e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 0 "$obtido" 'controle'
  for el in '' ' ' x bk/db-9.tar / /bk/ /bk//db-9.tar /bk/./db-9.tar /bk/../db-9.tar \
    /BK/db-9.tar $'/bk/\xc3\x89.tar' $'/bk/e\xcc\x81.tar' $'/bk/\xef\xb8\xa0' '/bk/db-9.tar/'; do
    # shellcheck disable=SC2034
    qa_v=(/bk/db-9.tar "$el")
    _qa_identidade qa_v
    obtido=0
    dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao qa_v e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
    assert_igual 1 "$obtido" "elemento malformado [$el] na lista recusa"
  done
  # Lista com o PROPRIO caminho que sai, em NFC, enquanto quem sai e o mesmo
  # nome: recusa (controle da comparacao).
  # shellcheck disable=SC2034
  qa_v=($'/bk/\xc3\xa9.tar')
  _qa_identidade qa_v
  obtido=0
  dbx_retencao_guarda file $'/bk/\xc3\xa9.tar' $'\xc3\xa9.tar' /bk / sai nao qa_v e00000000a1 id:qa-sai QA_G_REVS QA_G_IDS || obtido=1
  assert_igual 1 "$obtido" 'o mesmo caminho na lista recusa'
}

# ===========================================================================
# Ciclo 5 — DIV-167 (id e rev unicos; guarda (7) por identidade), DIV-168
# ===========================================================================

# QA-B6-S28 — guarda (7) por identidade, injetada: rev ou id de quem sai igual
# ao de quem fica recusa; listas de rev/id ausentes, vazias, com elemento
# vazio, que nao sao vetor ou de tamanho diferente da de caminhos recusam.
teste_qa_s28_guarda_7_identidade() {
  local obtido caso
  # shellcheck disable=SC2034  # lidos pela guarda por nome
  local -a qa_c=(/bk/db-9.tar) qa_c2=(/bk/db-8.tar /bk/db-9.tar) qa_r=(f00000000aa) qa_i=(id:fica)
  # shellcheck disable=SC2034
  local -a qa_r2=(f00000000aa f00000000bb) qa_i2=(id:fica id:fica2) qa_rv=('') qa_iv=('') qa_r0=() qa_i0=()
  # shellcheck disable=SC2034
  local -A qa_ra=([0]=f00000000aa)
  # shellcheck disable=SC2034
  local qa_rs=f00000000aa
  dbx_filtro_nome_preparar --padrao '*.tar' || _harness_falhar 'preparo do padrao'
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao qa_c e00000000a1 id:sai qa_r qa_i || obtido=1
  assert_igual 0 "$obtido" 'controle: identidades alheias aprovam'
  obtido=0
  dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao qa_c2 e00000000a1 id:sai qa_r2 qa_i2 || obtido=1
  assert_igual 0 "$obtido" 'controle: duas que ficam, tamanhos iguais'
  while IFS='|' read -r caso cam rev id revs ids; do
    [[ -n $caso ]] || continue
    obtido=0
    dbx_retencao_guarda file /bk/db-1.tar db-1.tar /bk / sai nao "$cam" "$rev" "$id" "$revs" "$ids" 2>/dev/null || obtido=1
    assert_igual 1 "$obtido" "guarda (7) por identidade recusa: $caso"
  done <<'TABELA'
rev de quem sai igual ao de quem fica|qa_c|f00000000aa|id:sai|qa_r|qa_i
id de quem sai igual ao de quem fica|qa_c|e00000000a1|id:fica|qa_r|qa_i
rev igual ao segundo que fica|qa_c2|f00000000bb|id:sai|qa_r2|qa_i2
id igual ao segundo que fica|qa_c2|e00000000a1|id:fica2|qa_r2|qa_i2
rev de quem sai vazio|qa_c|||qa_r|qa_i
id de quem sai vazio|qa_c|e00000000a1||qa_r|qa_i
revs maior que caminhos|qa_c|e00000000a1|id:sai|qa_r2|qa_i
ids maior que caminhos|qa_c|e00000000a1|id:sai|qa_r|qa_i2
revs menor que caminhos|qa_c2|e00000000a1|id:sai|qa_r|qa_i2
ids menor que caminhos|qa_c2|e00000000a1|id:sai|qa_r2|qa_i
revs com elemento vazio|qa_c|e00000000a1|id:sai|qa_rv|qa_i
ids com elemento vazio|qa_c|e00000000a1|id:sai|qa_r|qa_iv
revs vazio|qa_c|e00000000a1|id:sai|qa_r0|qa_i
ids vazio|qa_c|e00000000a1|id:sai|qa_r|qa_i0
revs ausente|qa_c|e00000000a1|id:sai||qa_i
ids ausente|qa_c|e00000000a1|id:sai|qa_r|
revs associativo|qa_c|e00000000a1|id:sai|qa_ra|qa_i
revs escalar|qa_c|e00000000a1|id:sai|qa_rs|qa_i
revs inexistente|qa_c|e00000000a1|id:sai|qa_nao_existe|qa_i
revs com nome invalido|qa_c|e00000000a1|id:sai|qa_r[0]|qa_i
TABELA
}

# QA-B6-S29 — DIV-167 na listagem: arquivo sem id (mesmo fora do padrao), id
# vazio ou nao textual, id repetido e rev repetido (inclusive entre paginas)
# saem 10 sem delete; pasta sem id e pasta com o rev de um arquivo nao dao
# falso 10.
teste_qa_s29_identidade_na_listagem() {
  local caso entrada e1
  _qa_arq db-1.tar 2026-10-01T00:00:00Z 0000000001a
  e1=$QA_ARQ
  for caso in \
    '{".tag":"file","name":"x.doc","path_lower":"/bk/x.doc","path_display":"/Bk/x.doc","server_modified":"2020-01-01T00:00:00Z","rev":"0000000077a","size":1}' \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":"","server_modified":"2020-01-01T00:00:00Z","rev":"0000000077a","size":1}' \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":7,"server_modified":"2020-01-01T00:00:00Z","rev":"0000000077a","size":1}' \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":null,"server_modified":"2020-01-01T00:00:00Z","rev":"0000000077a","size":1}' \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":"id:000000005a","server_modified":"2020-01-01T00:00:00Z","rev":"0000000077a","size":1}' \
    '{".tag":"file","name":"x.doc","path_lower":"/bk/x.doc","path_display":"/Bk/x.doc","id":"id:outro","server_modified":"2020-01-01T00:00:00Z","rev":"000000005a","size":1}' \
    '{".tag":"file","name":"x.doc","path_lower":"/bk/x.doc","path_display":"/Bk/x.doc","id":"id:outro","server_modified":"2020-01-01T00:00:00Z","size":1}'; do
    _qa_cenario
    _qa_pagina_unica "$caso,$QA_CINCO"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    _qa_estado "$QA_REMOTO" "identidade [$caso]"
    _qa_zero_delete "identidade [$caso]"
  done
  # rev repetido entre paginas, em arquivos de nomes diferentes
  _qa_arq db-9.tar 2026-10-09T00:00:00Z 0000000001a /bk/db-9.tar id:outro9
  _qa_cenario
  _qa_regra files/list_folder '*' 200 "{\"entries\":[$e1],\"cursor\":\"c1\",\"has_more\":true}"
  _qa_regra files/list_folder/continue '*' 200 "{\"entries\":[$QA_ARQ],\"cursor\":\"c2\",\"has_more\":false}"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  _qa_estado "$QA_REMOTO" 'rev repetido entre paginas'
  _qa_zero_delete 'rev repetido entre paginas'
  # sem falso 10: pasta sem id; pasta com "rev" igual ao de um arquivo
  entrada='{".tag":"folder","name":"p1","path_lower":"/bk/p1","path_display":"/Bk/p1"}'
  entrada+=',{".tag":"folder","name":"p2","path_lower":"/bk/p2","path_display":"/Bk/p2","id":"id:p2","rev":"000000001a"}'
  _qa_cenario
  _qa_pagina_unica "$entrada,$QA_CINCO"
  _qa_apagar_ok
  _qa_rodar reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  _qa_estado 0 'pastas sem id ou com rev de arquivo nao derrubam'
  _qa_deletes
  assert_igual '/bk/db-1.tar /bk/db-2.tar /bk/db-3.tar' "$QA_APAGADOS" 'segue apagando o que sai'
}

# QA-B6-S30 — DIV-169: as duplicatas dos ciclos 1 a 3 com rev e id DISTINTOS,
# para medir as barreiras por grafia sozinhas (sem a identidade de DIV-167):
# mesmo caminho, caixa ASCII, caixa nao ASCII, NFD nos cinco blocos, e o mesmo
# caminho com outra `.tag`. Todas: 10 e zero delete_v2.
teste_qa_s30_duplicatas_com_identidades_distintas() {
  local par p1 p2 a b aceitos=''
  for par in \
    '/bk/db-5.tar|/bk/db-5.tar' \
    '/bk/db-5.tar|/bk/DB-5.TAR' \
    $'/bk/\xc3\xa9.tar|/bk/\xc3\x89.tar' \
    $'/bk/\xc3\xa9.tar|/bk/e\xcc\x81.tar'; do
    p1=${par%%|*} p2=${par#*|}
    _qa_arq "${p1##*/}" 2026-10-05T00:00:00Z 000000000aa "$p1" id:fica
    a=$QA_ARQ
    _qa_arq "${p2##*/}" 2026-10-01T00:00:00Z 000000000bb "$p2" id:sai
    b=$QA_ARQ
    _qa_cenario
    _qa_pagina_unica "$a,$b"
    _qa_apagar_ok
    _qa_rodar reter /bk --padrao '*.tar' --manter 1 --confirmar
    _qa_deletes
    [[ -z $QA_APAGADOS && $QA_ESTADO == "$QA_REMOTO" ]] || aceitos+="[$par]=$QA_ESTADO:$QA_APAGADOS "
  done
  assert_igual '' "$aceitos" 'barreiras por grafia, sozinhas, seguram as duplicatas dos ciclos 1 a 3'
}

# _qa_data_de <sufixo> <AGORA|AUSENTE|+-segundos|texto>
_qa_data_de() {
  case $2 in
    AGORA) ;;
    AUSENTE) : >"$B/sem_data.$1" ;;
    [+-][0-9]*) printf '%(%a, %d %b %Y %H:%M:%S GMT)T\n' $((EPOCHSECONDS + $2)) >"$B/data.$1" ;;
    *) printf '%s\n' "$2" >"$B/data.$1" ;;
  esac
}

harness_executar "$@"
