#!/usr/bin/env bash
# Testes ponta a ponta da fase 6 do backlog: retencao e rotacao de backup
# (F-10; RF-93 a RF-100; TC-RTA, TC-RTS, TC-RTP, TC-RTC, TC-RTG, TC-RTX, TC-RTO,
# TC-CPL-11, TC-DOC-05, TC-TST-09; DIV-130 a DIV-147).
#
# O DUPLO DE `curl` RESPONDE POR REGRA, como o de `compartilhar_test`: linhas
# `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>arquivo<TAB>uma<TAB>cabecalho` em
# `regras`; a primeira que casa responde, e chamada sem regra responde 400 e fica
# marcada `SEM_REGRA`. Cada chamada fica em `chamadas` (`endpoint corpo`), e e
# por esse registro que os P0 sao provados: nenhum `delete_v2` sem
# `--confirmar`, nenhum fora da listagem, todo com `parent_rev`, o primeiro da
# ordem nunca, e zero com listagem suspeita.
#
# Alem do de `compartilhar_test`, este duplo: escreve os cabecalhos (`-D`) com o
# `Date` do instante (ou o de `data`, ou nenhum com `sem_data`) e o cabecalho
# extra da regra; troca `@PATH@` pelo `path` do pedido (a resposta do
# `delete_v2` ecoa o alvo) e `@N@` pelo numero da chamada; o codigo
# `SINAL:<NOME>:<codigo>` manda o sinal ao `dbx` (pid em `pid`) e responde; a
# marca `uma` e atomica (`mkdir`), para as execucoes simultaneas. O `sleep` e
# duble que so registra a espera (Retry-After).
#
# shellcheck disable=SC2016,SC1003
# Justificativa: o duplo de `curl` e os roteiros chegam sem expansao; padroes
# com barra invertida final precisam chegar literais.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/filtro.sh"

readonly DBX_EXEC_PADRAO="$DBX_HARNESS_RAIZ/bin/dbx"
readonly SENTINELA_REFRESH='RT_SENTINELA_refresh_r6t7'
readonly SENTINELA_SEGREDO='AS_SENTINELA_segredo_r8t9'
readonly SENTINELA_CHAVE='AK_SENTINELA_chave_r0t1'
readonly SENTINELA_TOKEN='sl.SENTINELA_token_curto_r2t3'

# _ambiente [raiz_remota] — credencial, duplos de `curl`, `date` e `sleep`.
_ambiente() {
  local raiz=${1:-/} base
  base=$(mktemp -d "$DBX_TESTES_TMP/reter.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/respostas" "$base/tmp" "$base/trabalho"
  chmod 700 "$base/config/dbx"
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s","raiz_remota":"%s"}' \
    "$SENTINELA_CHAVE" "$SENTINELA_SEGREDO" "$SENTINELA_REFRESH" "$raiz" \
    >"$base/config/dbx/credencial.json"
  chmod 600 "$base/config/dbx/credencial.json"
  : >"$base/regras"
  {
    printf '#!%s\n' "$BASH"
    printf 'base=%q\n' "$base"
    printf 'token=%q\n' "$SENTINELA_TOKEN"
  } >"$base/bin/curl"
  cat >>"$base/bin/curl" <<'FIM'
export TZ=UTC0 LC_ALL=C
cat >/dev/null
saida=''; escrever=''; anterior=''; url=''; dados=''; cabecalhos=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) dados=${arg#@} ;; -D) cabecalhos=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
endpoint=${url#https://api.dropboxapi.com/2/}
[[ $url == *oauth2/token* ]] && endpoint='oauth2/token'
codigo=400 corpo='{"error_summary":"sem_regra/"}' extra=''
printf '%s %s\n' "$endpoint" "$pedido" >>"$base/chamadas"
achou=nao n=0
while IFS=$'\t' read -r ep filtro cod arq vez cab; do
  n=$((n + 1))
  [[ -n $ep ]] || continue
  # shellcheck disable=SC2053
  [[ $endpoint == $ep && $pedido == $filtro ]] || continue
  if [[ $vez == uma ]]; then
    mkdir "$base/usada.$n" 2>/dev/null || continue
  fi
  achou=sim codigo=$cod corpo='' extra=$cab
  [[ -n $arq && -r $base/respostas/$arq ]] && IFS= read -r -d '' corpo <"$base/respostas/$arq"
  if [[ $corpo == *@N@* ]]; then
    total=0
    while IFS= read -r _l; do total=$((total + 1)); done <"$base/chamadas"
    corpo=${corpo//@N@/$total}
  fi
  if [[ $corpo == *@PATH@* && $pedido =~ \"path\":\"([^\"]*)\" ]]; then
    corpo=${corpo//@PATH@/${BASH_REMATCH[1]}}
  fi
  break
done <"$base/regras"
if [[ $achou == nao ]]; then
  if [[ $endpoint == oauth2/token ]]; then
    codigo=200
    corpo="{\"access_token\":\"$token\",\"token_type\":\"bearer\",\"expires_in\":14400}"
  else
    printf 'SEM_REGRA %s\n' "$endpoint" >>"$base/chamadas"
  fi
fi
case $codigo in
  REDE) printf 'curl: (7) Failed to connect\n' >&2; exit 7 ;;
  SINAL:*)
    sinal=${codigo#SINAL:}; codigo=${sinal#*:}; sinal=${sinal%%:*}
    printf 'SINAL %s\n' "$sinal" >>"$base/chamadas"
    kill -"$sinal" "$(<"$base/pid")"
    ;;
esac
if [[ -n $cabecalhos ]]; then
  {
    printf 'HTTP/1.1 %s X\r\n' "$codigo"
    if [[ ! -e $base/sem_data && $extra != Date:* ]]; then
      if [[ -r $base/data ]]; then
        IFS= read -r d <"$base/data"
      else
        printf -v d '%(%a, %d %b %Y %H:%M:%S GMT)T' -1
      fi
      printf 'Date: %s\r\n' "$d"
    fi
    [[ -n $extra ]] && printf '%s\r\n' "$extra"
    printf '\r\n'
  } >"$cabecalhos"
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  # RF-95(d): o relogio vem do `printf` do shell, nunca do utilitario `date`.
  printf '#!%s\nprintf "date %%s\\n" "$*" >>%q\nexit 1\n' "$BASH" "$base/proibido" >"$base/bin/date"
  printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexit 0\n' "$BASH" "$base/esperas" >"$base/bin/sleep"
  chmod +x "$base/bin/curl" "$base/bin/date" "$base/bin/sleep"
  printf '%s' "$base"
}

_seq=0
_regra() { # <base> <endpoint> <filtro> <codigo> <corpo> [uma] [cabecalho]
  local base=$1 ep=$2 filtro=$3 codigo=$4 corpo=$5 vez=${6:-} cab=${7:-}
  _seq=$((_seq + 1))
  printf '%s' "$corpo" >"$base/respostas/r$_seq"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ep" "$filtro" "$codigo" "r$_seq" "$vez" "$cab" >>"$base/regras"
}

# _rodar <base> <argumentos...> — sem terminal, com teto de tempo; `DBX_T_EXEC`
# troca o produto (copia mutante).
_rodar() {
  local base=$1
  shift
  (
    cd "$base/trabalho" || exit 99
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_LC:+LC_ALL="$DBX_T_LC"} ${DBX_T_LOC:+DBX_SYNC_LOCALIDADE="$DBX_T_LOC"} \
      DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
      timeout -k 2 "${DBX_T_TETO:-60}" setsid -w bash -c 'printf "%s" "$$" >"$1/pid"; shift; exec bash "$@"' _ \
      "$base" "${DBX_T_EXEC:-$DBX_EXEC_PADRAO}" "$@" </dev/null >"$base/out" 2>"$base/err"
  )
  DBX_ESTADO=$?
  [[ $DBX_ESTADO -ne 124 && $DBX_ESTADO -ne 137 ]] || _harness_falhar "o comando pendurou ($DBX_ESTADO): $*"
  DBX_SAIDA='' DBX_ERRO=''
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_chamadas() { _harness_contar "$2" "$1/chamadas"; } # <base> <trecho>
_deletes() { _harness_contar '^files/delete_v2 ' "$1/chamadas"; }
_nenhuma_chamada() { assert_arquivo_ausente "$1/chamadas" "$2"; }

# _residuo <base> — entradas que sobraram no TMPDIR privado.
_residuo() {
  local entrada lista=''
  for entrada in "$1"/tmp/* "$1"/tmp/.[!.]*; do
    [[ -e $entrada ]] && lista+=" ${entrada##*/}"
  done
  printf '%s' "$lista"
}

# _copia_mutante <sed>... — copia do produto com cada edicao aplicada a um
# arquivo: argumentos em pares `<arquivo relativo> <expressao sed>`.
_copia_mutante() {
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/mutante.XXXXXX")
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$copia/"
  while [[ $# -ge 2 ]]; do
    cp "$copia/$1" "$copia/$1.orig"
    sed -e "$2" "$copia/$1.orig" >"$copia/$1"
    cmp -s "$copia/$1" "$copia/$1.orig" && _harness_falhar "a mutacao nao alterou $1: $2"
    rm -f "$copia/$1.orig"
    shift 2
  done
  printf '%s' "$copia/bin/dbx"
}

# ---------------------------------------------------------------------------
# Massa
# ---------------------------------------------------------------------------

# _arq <name> <server_modified> <rev> [pasta_lower] [pasta_display] [extra]
_arq() {
  local nome=$1 sm=$2 rev=$3 pl=${4-/bk} pd=${5-/Bk} extra=${6:-} chave
  dbx_filtro_chave "$nome"
  chave=$DBX_FILTRO_CHAVE
  printf '{".tag":"file","name":"%s","path_lower":"%s/%s","path_display":"%s/%s","id":"id:%s","client_modified":"2026-01-01T00:00:00Z","server_modified":"%s","rev":"%s","size":10,"content_hash":"h"%s}' \
    "$nome" "$pl" "$chave" "$pd" "$nome" "$rev" "$sm" "$rev" "$extra"
}
_pasta() { # <name> [pasta_lower]
  printf '{".tag":"folder","name":"%s","path_lower":"%s/%s","path_display":"/Bk/%s","id":"id:p%s"}' \
    "$1" "${2-/bk}" "$1" "$1" "$1"
}
# _listagem <base> <entradas_json> [filtro] — uma pagina de list_folder.
_listagem() {
  _regra "$1" files/list_folder "${3:-*\"path\":\"/bk\"*}" 200 "{\"entries\":[$2],\"cursor\":\"c0\",\"has_more\":false}"
}
_apagar_ok() { # <base> — todo delete_v2 sem regra propria apaga e ecoa o alvo
  _regra "$1" files/delete_v2 '*' 200 '{"metadata":{".tag":"file","name":"x","path_lower":"@PATH@","rev":"0123456789"}}'
}

# Cinco artefatos de backup, do mais velho (1) ao mais novo (5), fora de ordem.
CINCO=$(
  _arq db-3.tar 2026-10-03T00:00:00Z 0000000003a
  printf ,
  _arq db-1.tar 2026-10-01T00:00:00Z 0000000001a
  printf ,
  _arq db-5.tar 2026-10-05T00:00:00Z 0000000005a
  printf ,
  _arq db-2.tar 2026-10-02T00:00:00Z 0000000002a
  printf ,
  _arq db-4.tar 2026-10-04T00:00:00Z 0000000004a
)
readonly CINCO

# _ordem_dos_deletes <base> — os nomes apagados, na ordem das chamadas.
_ordem_dos_deletes() {
  local linha lista=''
  while IFS= read -r linha; do
    [[ $linha == 'files/delete_v2 '* && $linha =~ \"path\":\"/bk/([^\"]*)\" ]] && lista+="${BASH_REMATCH[1]} "
  done <"$1/chamadas"
  printf '%s' "${lista% }"
}

# _carimbo_ha <segundos> — server_modified de agora menos <segundos>.
_carimbo_ha() {
  dbx_filtro_carimbo_de_epoca $((EPOCHSECONDS - $1))
  printf '%s' "$DBX_FILTRO_CARIMBO"
}

# ===========================================================================
# TC-RTA — forma, opcoes e validacao antes da rede (RF-93)
# ===========================================================================

teste_rta01_forma_minima_e_aliases_dao_o_mesmo_plano() {
  local base plano
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 3
  assert_igual 0 "$DBX_ESTADO" "forma minima com --manter: $DBX_ERRO"
  plano=$DBX_SAIDA
  _rodar "$base" retain /bk --pattern 'db-*.tar' --keep 3
  assert_igual 0 "$DBX_ESTADO" 'alias retain, --pattern, --keep'
  assert_igual "$plano" "$DBX_SAIDA" 'plano identico pelos aliases'
  _rodar "$base" reter --padrao 'db-*.tar' /bk --keep 3
  assert_igual "$plano" "$DBX_SAIDA" 'plano identico com a pasta depois'
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 7
  assert_igual 0 "$DBX_ESTADO" "forma minima com --dias: $DBX_ERRO"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --days 7
  assert_igual 0 "$DBX_ESTADO" '--days'
  _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 3 --yes
  assert_igual 0 "$DBX_ESTADO" '--yes aceito'
  _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 3 -y
  assert_igual 0 "$DBX_ESTADO" '-y aceito'
  assert_igual 0 "$(_deletes "$base")" 'nada apagado'
}

teste_rta02_pasta_ausente_dupla_ou_relativa_e_uso_invalido_sem_rede() {
  local base
  base=$(_ambiente)
  _rodar "$base" reter --padrao '*.tar' --manter 1
  assert_igual 2 "$DBX_ESTADO" 'sem pasta'
  _rodar "$base" reter /a /b --padrao '*.tar' --manter 1
  assert_igual 2 "$DBX_ESTADO" 'duas pastas'
  _rodar "$base" reter bk --padrao '*.tar' --manter 1
  assert_igual 2 "$DBX_ESTADO" 'relativa'
  _nenhuma_chamada "$base" 'zero invocacoes do duble'
}

teste_rta03_padrao_ausente_vazio_ou_repetido_e_uso_invalido() {
  local base
  base=$(_ambiente)
  _rodar "$base" reter /bk --manter 1
  assert_igual 2 "$DBX_ESTADO" 'sem --padrao'
  _rodar "$base" reter /bk --padrao '' --manter 1
  assert_igual 2 "$DBX_ESTADO" '--padrao vazio'
  _rodar "$base" reter /bk --padrao '*.tar' --pattern '*.gz' --manter 1
  assert_igual 2 "$DBX_ESTADO" '--padrao repetido'
  assert_contem 'repetid' "$DBX_ERRO" 'a recusa diz que repetiu'
  _rodar "$base" reter /bk --manter 1 --padrao
  assert_igual 2 "$DBX_ESTADO" '--padrao sem valor'
  _nenhuma_chamada "$base" 'sem rede'
}

teste_rta04_politica_ausente_dupla_ou_repetida_e_uso_invalido() {
  local base
  base=$(_ambiente)
  _rodar "$base" reter /bk --padrao '*.tar'
  assert_igual 2 "$DBX_ESTADO" 'nenhuma politica'
  assert_contem 'informe --manter N ou --dias D' "$DBX_ERRO" 'mensagem'
  _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --dias 2
  assert_igual 2 "$DBX_ESTADO" 'as duas'
  assert_contem 'informe --manter N ou --dias D' "$DBX_ERRO" 'mensagem'
  _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --keep 2
  assert_igual 2 "$DBX_ESTADO" '--manter repetido'
  _rodar "$base" reter /bk --padrao '*.tar' --dias 1 --days 2
  assert_igual 2 "$DBX_ESTADO" '--dias repetido'
  _nenhuma_chamada "$base" 'sem rede'
}

teste_rta05_rta06_valores_fora_da_faixa_sem_rede_e_limites_aceitos() {
  local base valor
  base=$(_ambiente)
  _rodar "$base" reter /bk --padrao '*.tar' --manter 0
  assert_igual 2 "$DBX_ESTADO" '--manter 0'
  assert_contem '--manter 0 apagaria todos; o minimo e 1' "$DBX_ERRO" 'mensagem do minimo'
  for valor in -1 +1 01 1.5 abc '' 1000000; do
    _rodar "$base" reter /bk --padrao '*.tar' --manter "$valor"
    assert_igual 2 "$DBX_ESTADO" "--manter [$valor]"
  done
  for valor in 0 36501 01 7d ''; do
    _rodar "$base" reter /bk --padrao '*.tar' --dias "$valor"
    assert_igual 2 "$DBX_ESTADO" "--dias [$valor]"
  done
  _nenhuma_chamada "$base" 'toda recusa sem rede'
  _listagem "$base" "$CINCO"
  for valor in 1 999999; do
    _rodar "$base" reter /bk --padrao '*.tar' --manter "$valor"
    assert_igual 0 "$DBX_ESTADO" "--manter $valor aceito"
  done
  for valor in 1 36500; do
    _rodar "$base" reter /bk --padrao '*.tar' --dias "$valor"
    assert_igual 0 "$DBX_ESTADO" "--dias $valor aceito: $DBX_ERRO"
  done
}

teste_rta07_padrao_malformado_e_2_citado_e_aceitos() {
  local base p longo
  base=$(_ambiente)
  printf -v longo '%1025s' ''
  longo=${longo// /a}
  for p in 'a/*.tar' '*/' '!x' '[' '[]' '[z-a]' '[[:alpha:]]' 'x\' $'a\x01b' "$longo"; do
    _rodar "$base" reter /bk --padrao "$p" --manter 1
    assert_igual 2 "$DBX_ESTADO" "padrao [$p]"
    [[ $DBX_ERRO == *$'\x01'* ]] && _harness_falhar 'byte cru na recusa' "$DBX_ERRO"
  done
  _nenhuma_chamada "$base" 'sem rede'
  _listagem "$base" "$CINCO"
  for p in '[]a]*' '**.tar' '\*'; do
    _rodar "$base" reter /bk --padrao "$p" --manter 1
    assert_igual 0 "$DBX_ESTADO" "padrao aceito [$p]: $DBX_ERRO"
  done
}

teste_rta08_opcoes_de_outros_comandos_sao_recusadas() {
  local base op
  base=$(_ambiente)
  for op in '--excluir x' '--incluir x' --recursivo '--limite-banda 1M' '--rev 0123456789' --dry-run --padrao=x; do
    # shellcheck disable=SC2086
    _rodar "$base" reter /bk --padrao '*.tar' --manter 1 $op
    assert_igual 2 "$DBX_ESTADO" "opcao recusada: $op"
  done
  _nenhuma_chamada "$base" 'sem rede'
}

teste_rta09_padrao_e_dado_nunca_codigo() {
  local base p
  base=$(_ambiente)
  _listagem "$base" "$(_arq 'a.tar' 2026-10-01T00:00:00Z 0000000001a)"
  for p in '$(touch S)' '`touch S`' ';touch S' '$HOME' '~'; do
    _rodar "$base" reter /bk --padrao "$p" --manter 1
    assert_igual 0 "$DBX_ESTADO" "padrao como texto [$p]: $DBX_ERRO"
    assert_contem 'candidatos=0' "$DBX_SAIDA" "nada casa [$p]"
  done
  assert_arquivo_ausente "$base/trabalho/S" 'nada executado'
  assert_arquivo_ausente "$base/S" 'nada executado'
}

teste_rta10_uso_vem_antes_do_confinamento_e_toda_recusa_e_sem_rede() {
  local base
  base=$(_ambiente /bk)
  _rodar "$base" reter /fora --padrao 'a/b' --manter 1
  assert_igual 2 "$DBX_ESTADO" 'uso antes do confinamento'
  _rodar "$base" reter /fora --padrao '*.tar' --manter 0
  assert_igual 2 "$DBX_ESTADO" 'valor antes do confinamento'
  _rodar "$base" reter /fora --padrao '*.tar' --manter 1
  assert_igual 13 "$DBX_ESTADO" 'confinamento depois'
  _nenhuma_chamada "$base" 'zero chamadas'
}

# ===========================================================================
# TC-RTS — selecao e listagem (RF-94)
# ===========================================================================

teste_rts01_corpo_da_listagem_e_um_nivel_so() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO,$(_pasta velho)"
  _rodar "$base" reter /bk --padrao '*.tar' --manter 1
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '^files/list_folder {"limit":[0-9]*,"path":"/bk","recursive":false,"include_deleted":false}$')" \
    'recursive false, include_deleted false e limit explicito'
  assert_igual 1 "$(_chamadas "$base" '^files/list_folder')" 'uma listagem, nenhuma de subpasta'
}

teste_rts02_arquivos_de_subpasta_nunca_sao_candidatos() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk/velho"*' 200 \
    "{\"entries\":[$(_arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /bk/velho /Bk/velho)],\"cursor\":\"x\",\"has_more\":false}"
  _listagem "$base" "$(_pasta velho),$(_arq db-1.tar 2026-10-01T00:00:00Z 0000000001a),$(_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 0 "$(_chamadas "$base" '/bk/velho')" 'a subpasta nunca e listada nem apagada'
  assert_igual 'db-1.tar' "$(_ordem_dos_deletes "$base")" 'so o nivel de cima'
}

teste_rts03_pasta_apagado_e_tag_desconhecida_sao_ignorados() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$(_pasta backup-1.tar),{\".tag\":\"deleted\",\"name\":\"backup-0.tar\",\"path_lower\":\"/bk/backup-0.tar\"},{\".tag\":\"estranha\",\"name\":\"backup-9.tar\",\"path_lower\":\"/bk/backup-9.tar\"},$(_arq backup-2.tar 2026-10-02T00:00:00Z 0000000002a),$(_arq backup-3.tar 2026-10-03T00:00:00Z 0000000003a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'backup-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'ignorados=3' "$DBX_SAIDA" 'tres ignorados'
  assert_contem 'candidatos=2' "$DBX_SAIDA" 'so os arquivos'
  assert_igual 'backup-2.tar' "$(_ordem_dos_deletes "$base")" 'pasta, apagado e tag desconhecida nunca apagados'
}

teste_rts04_tres_paginas_e_nenhum_delete_antes_da_ultima() {
  local base linha visto_delete=nao lista_depois=nao
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$(_arq db-1.tar 2026-10-01T00:00:00Z 0000000001a)],\"cursor\":\"c1\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*"c1"*' 200 "{\"entries\":[$(_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a)],\"cursor\":\"c2\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*"c2"*' 200 "{\"entries\":[$(_arq db-3.tar 2026-10-03T00:00:00Z 0000000003a)],\"cursor\":\"c3\",\"has_more\":false}"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 2 "$(_chamadas "$base" '^files/list_folder/continue {"cursor":"c[12]"}$')" 'segue o cursor, so com o cursor'
  while IFS= read -r linha; do
    [[ $linha == files/delete_v2* ]] && visto_delete=sim
    [[ $visto_delete == sim && $linha == files/list_folder* ]] && lista_depois=sim
  done <"$base/chamadas"
  assert_igual nao "$lista_depois" 'nenhum delete antes da ultima pagina'
  assert_igual 'db-1.tar db-2.tar' "$(_ordem_dos_deletes "$base")" 'plano sobre as tres paginas'
}

teste_rts05_falha_na_pagina_2_sai_pela_classe_sem_delete() {
  local base caso codigo esperado tag
  for caso in '500:10:x' '429:8:too_many_requests' 'REDE:9:x' '401:5:invalid_access_token'; do
    codigo=${caso%%:*} esperado=${caso#*:} tag=${caso##*:}
    esperado=${esperado%%:*}
    base=$(_ambiente)
    _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$CINCO],\"cursor\":\"c1\",\"has_more\":true}"
    _regra "$base" files/list_folder/continue '*' "$codigo" "{\"error_summary\":\"$tag/..\"}"
    _apagar_ok "$base"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    assert_igual "$esperado" "$DBX_ESTADO" "falha $codigo na pagina 2"
    assert_igual 0 "$(_deletes "$base")" "zero delete_v2 com $codigo"
  done
}

teste_rts06_reset_no_continue_sai_14_sem_delete() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$CINCO],\"cursor\":\"c1\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*' 409 '{"error_summary":"reset/..","error":{".tag":"reset"}}'
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 14 "$DBX_ESTADO" 'reset'
  assert_contem 'a pasta mudou durante a listagem; repita' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

teste_rts07_cursor_repetido_e_pagina_vazia() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$CINCO],\"cursor\":\"c1\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*' 200 '{"entries":[],"cursor":"c1","has_more":true}'
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 10 "$DBX_ESTADO" 'cursor repetido'
  assert_contem 'paginacao nao avanca' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'

  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$CINCO],\"cursor\":\"c1\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*"c1"*' 200 '{"entries":[],"cursor":"c2","has_more":true}'
  _regra "$base" files/list_folder/continue '*"c2"*' 200 '{"entries":[],"cursor":"c3","has_more":false}'
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  assert_igual 0 "$DBX_ESTADO" "pagina vazia com has_more verdadeiro e aceita: $DBX_ERRO"
  assert_contem 'candidatos=5' "$DBX_SAIDA" 'a listagem chega ao fim'
}

teste_rts07_teto_de_1000_paginas() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$CINCO],\"cursor\":\"c0\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*' 200 '{"entries":[],"cursor":"c@N@","has_more":true}'
  _apagar_ok "$base"
  DBX_T_TETO=600 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 10 "$DBX_ESTADO" '1001 paginas'
  assert_contem 'listagem nao terminou em 1000 paginas' "$DBX_ERRO" 'mensagem do teto'
  assert_igual 999 "$(_chamadas "$base" '^files/list_folder/continue ')" 'exatamente 1000 paginas lidas'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

teste_rts08_pagina_malformada_ou_com_chave_repetida_e_10() {
  local base corpo
  for corpo in '{"entries":[' \
    "{\"entries\":[$CINCO],\"cursor\":\"c0\",\"has_more\":false,\"has_more\":true}" \
    "{\"entries\":[{\".tag\":\"file\",\"name\":\"db-0.tar\",\"path_lower\":\"/bk/db-0.tar\",\"path_lower\":\"/bk/db-9.tar\",\"path_display\":\"/Bk/db-0.tar\",\"server_modified\":\"2026-01-01T00:00:00Z\",\"rev\":\"0000000000a\"},$CINCO],\"cursor\":\"c0\",\"has_more\":false}" \
    '{"entries":{},"cursor":"c0","has_more":false}' \
    "{\"entries\":[$CINCO],\"cursor\":\"c0\"}"; do
    base=$(_ambiente)
    _regra "$base" files/list_folder '*' 200 "$corpo"
    _apagar_ok "$base"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    assert_igual 10 "$DBX_ESTADO" "pagina suspeita: ${corpo:0:60}"
    assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
  done
}

# _incoerentes — uma entrada incoerente por linha (RF-94(g), DIV-147).
_incoerentes() {
  _arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /bk/sub /Bk/sub
  printf '\n'
  _arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /bkx /Bkx
  printf '\n'
  _arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /outra /Outra
  printf '\n'
  printf '{".tag":"file","name":"db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000a"}\n'
  printf '{".tag":"file","name":"db/0.tar","path_lower":"/bk/db/0.tar","path_display":"/Bk/db/0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000a"}\n'
  printf '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z"}\n'
  printf '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000a"}\n'
  printf '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000a"}\n'
  printf '{".tag":"file","name":"","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000a"}\n'
  printf '{".tag":"folder","name":"sub","path_lower":"/outra/sub"}\n'
  printf '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":12345678901}\n'
}

# _rts09 <produto> — 0 quando TODA entrada incoerente derruba a execucao com
# 10 e zero delete_v2; imprime o primeiro caso que escapou.
_rts09() {
  local entrada base
  while IFS= read -r entrada; do
    base=$(_ambiente)
    _listagem "$base" "$entrada,$CINCO"
    _apagar_ok "$base"
    DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    if [[ $DBX_ESTADO -ne 10 || $(_deletes "$base") -ne 0 ]]; then
      printf '%s -> %s, %s delete(s)' "$entrada" "$DBX_ESTADO" "$(_deletes "$base")"
      return 1
    fi
  done < <(_incoerentes)
  return 0
}

teste_rts09_listagem_incoerente_derruba_a_execucao_inteira() {
  local escapou
  escapou=$(_rts09 "$DBX_EXEC_PADRAO") || _harness_falhar 'entrada incoerente nao derrubou a execucao' "$escapou"
  return 0
}

teste_rts09_mutante_que_pula_o_item_incoerente_reprova() {
  local mutante escapou
  mutante=$(_copia_mutante commands/reter.sh 's/^\(.*\)|| return 1 *# MUTACAO:coerencia$/\1|| continue/')
  escapou=$(_rts09 "$mutante") && _harness_falhar 'o mutante que pula o item passou no caso'
  assert_contem 'delete(s)' "$escapou" 'o caso apontou a entrada que escapou'
}

teste_rts10_sem_caixa_e_licao_da_fase_4() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$(_arq nota.txt 2000-01-01T00:00:00Z 0000000000a),$(_arq a.TAR 2026-10-01T00:00:00Z 0000000001a),$(_arq $'\xc3\xa9a.tar' 2026-10-02T00:00:00Z 0000000002a)"
  _apagar_ok "$base"
  DBX_T_LC=C _rodar "$base" reter /bk --padrao $'*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'fora_do_padrao=1' "$DBX_SAIDA" 'nota.txt fora do padrao'
  assert_igual 'a.tar' "$(_ordem_dos_deletes "$base")" 'nota.txt, o mais velho, nunca apagado'
  base=$(_ambiente)
  _listagem "$base" "$(_arq $'\xc3\xa9a.tar' 2026-10-02T00:00:00Z 0000000002a),$(_arq $'\xc3\xa9b.tar' 2026-10-03T00:00:00Z 0000000003a)"
  DBX_T_LC=C _rodar "$base" reter /bk --padrao $'\xc3\x89*' --manter 1
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'candidatos=2' "$DBX_SAIDA" 'E* casa e acentuado sob LC_ALL=C'
}

teste_rts11_pasta_inexistente_e_4_e_arquivo_e_2() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/nada"*' 409 '{"error_summary":"path/not_found/..","error":{".tag":"path"}}'
  _regra "$base" files/list_folder '*"/arq.tar"*' 409 '{"error_summary":"path/not_folder/..","error":{".tag":"path"}}'
  _apagar_ok "$base"
  _rodar "$base" reter /nada --padrao '*.tar' --manter 1 --confirmar
  assert_igual 4 "$DBX_ESTADO" 'inexistente'
  _rodar "$base" reter /arq.tar --padrao '*.tar' --manter 1 --confirmar
  assert_igual 2 "$DBX_ESTADO" 'arquivo'
  assert_contem 'reter opera sobre uma pasta de artefatos' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

# _retrato <dir> — conteudo e mtime de tudo abaixo do diretorio.
_retrato() {
  [[ -d $1 ]] || {
    printf 'ausente'
    return 0
  }
  find "$1" -mindepth 1 -printf '%P %s %T@ %m\n' | LC_ALL=C sort
}

teste_rts12_diretorio_de_estado_intocado_nos_tres_modos() {
  local base antes opcoes
  base=$(_ambiente)
  mkdir -p "$base/estado/dbx"
  printf 'memoria de outro sync\n' >"$base/estado/dbx/memoria"
  antes=$(_retrato "$base/estado")
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  for opcoes in '' --dry-run; do
    # shellcheck disable=SC2086
    _rodar "$base" $opcoes reter /bk --padrao 'db-*.tar' --manter 2
    assert_igual 0 "$DBX_ESTADO" "modo [$opcoes]"
  done
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "confirmado: $DBX_ERRO"
  assert_igual "$antes" "$(_retrato "$base/estado")" 'estado identico, conteudo e mtime'
}

# ===========================================================================
# TC-RTP — politica (RF-95), ponta a ponta
# ===========================================================================

teste_rtp01_rtx01_manter_2_de_5_apaga_3_do_mais_velho_ao_mais_novo() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 'db-1.tar db-2.tar db-3.tar' "$(_ordem_dos_deletes "$base")" 'tres, do mais velho ao mais novo'
  assert_contem 'apagados=3' "$DBX_SAIDA" 'resumo'
  assert_contem 'ficam=2' "$DBX_SAIDA" 'ficam'
}

teste_rtp04_client_modified_e_size_nao_participam() {
  local base
  base=$(_ambiente)
  _listagem "$base" "{\".tag\":\"file\",\"name\":\"db-1.tar\",\"path_lower\":\"/bk/db-1.tar\",\"path_display\":\"/Bk/db-1.tar\",\"id\":\"id:1\",\"client_modified\":\"2030-01-01T00:00:00Z\",\"server_modified\":\"2026-10-01T00:00:00Z\",\"rev\":\"0000000001a\",\"size\":999},{\".tag\":\"file\",\"name\":\"db-2.tar\",\"path_lower\":\"/bk/db-2.tar\",\"path_display\":\"/Bk/db-2.tar\",\"id\":\"id:2\",\"client_modified\":\"2000-01-01T00:00:00Z\",\"server_modified\":\"2026-10-02T00:00:00Z\",\"rev\":\"0000000002a\",\"size\":1}"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 'db-1.tar' "$(_ordem_dos_deletes "$base")" 'server_modified decide'
}

teste_rtp05_server_modified_invalido_em_um_candidato_e_10_sem_delete() {
  local base sm
  for sm in '' 2026-10-20T10:00:00.5Z 2026-10-20T10:00:00+03:00 2026-02-30T00:00:00Z; do
    base=$(_ambiente)
    _listagem "$base" "$CINCO,$(_arq db-9.tar "$sm" 0000000009a)"
    _apagar_ok "$base"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    assert_igual 10 "$DBX_ESTADO" "server_modified [$sm]"
    assert_contem 'server_modified' "$DBX_ERRO" 'a mensagem nomeia o campo'
    assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
  done
  base=$(_ambiente)
  _listagem "$base" "$CINCO,{\".tag\":\"file\",\"name\":\"nota.txt\",\"path_lower\":\"/bk/nota.txt\",\"path_display\":\"/Bk/nota.txt\",\"id\":\"id:nota\",\"rev\":\"0000000009f\"}"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 4 --confirmar
  assert_igual 0 "$DBX_ESTADO" "defeito fora do padrao nao afeta: $DBX_ERRO"
  assert_igual 'db-1.tar' "$(_ordem_dos_deletes "$base")" 'plano normal'
}

teste_rtp07_rtp08_dias_com_o_relogio_real() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$(_arq db-1.tar "$(_carimbo_ha $((10 * 86400)))" 0000000001a),$(_arq db-2.tar "$(_carimbo_ha $((7 * 86400 - 600)))" 0000000002a),$(_arq db-3.tar "$(_carimbo_ha 60)" 0000000003a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 7 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 'db-1.tar' "$(_ordem_dos_deletes "$base")" 'so o mais velho que o corte'
  [[ $DBX_SAIDA =~ corte=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ]] || _harness_falhar 'corte' "$DBX_SAIDA"
  assert_igual 0 "$(_harness_contar '' "$base/proibido")" 'nenhum date'

  base=$(_ambiente)
  _listagem "$base" "$(_arq db-1.tar 2020-01-01T00:00:00Z 0000000001a),$(_arq db-2.tar 2020-01-02T00:00:00Z 0000000002a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 'db-1.tar' "$(_ordem_dos_deletes "$base")" 'o mais novo fica pelo minimo'
  assert_contem 'mantido_pelo_minimo=sim' "$DBX_SAIDA" 'minimo'
  assert_contem 'nenhum artefato dentro de 1 dias; o mais novo foi mantido: db-2.tar' "$DBX_ERRO" 'aviso com o nome'
}

teste_rtp11_zero_candidatos_sai_0_com_aviso() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$(_pasta x),$(_arq nota.txt 2026-10-01T00:00:00Z 0000000001a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'candidatos=0' "$DBX_SAIDA" 'candidatos 0'
  assert_contem "o padrao 'db-*.tar' nao casou nenhum arquivo em /bk" "$DBX_ERRO" 'aviso'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

# ===========================================================================
# TC-RTC — plano, --confirmar e --dry-run (RF-96)
# ===========================================================================

_conjunto_sai() { # <saida> — nomes com acao sai ou apagado, na ordem
  local linha acao='' lista=''
  while IFS= read -r linha; do
    [[ $linha == 'acao='* ]] && acao=${linha#acao=}
    if [[ $linha == 'name='* ]]; then
      [[ $acao == sai || $acao == apagado ]] && lista+="${linha#name=} "
      acao=''
    fi
  done <<<"$1"
  printf '%s' "${lista% }"
}

teste_rtc01_rtc02_rtc03_sem_confirmar_e_com_dry_run_nada_e_apagado() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  assert_igual 0 "$DBX_ESTADO" 'plano'
  assert_contem 'modo=plano' "$DBX_SAIDA" 'modo plano'
  assert_contem 'acao=fica' "$DBX_SAIDA" 'fica'
  assert_contem 'acao=sai' "$DBX_SAIDA" 'sai'
  assert_contem 'nada foi apagado; para aplicar, repita com --confirmar' "$DBX_ERRO" 'aviso'
  assert_igual 1 "$(_chamadas "$base" '^oauth2/token')" 'renovacao'
  _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 2
  assert_igual 0 "$DBX_ESTADO" 'simulado'
  assert_contem 'modo=simulado' "$DBX_SAIDA" 'modo simulado'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'simulado sim'
  _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" '--dry-run vence --confirmar'
  assert_contem 'modo=simulado' "$DBX_SAIDA" 'simulado'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2 nos tres'
}

teste_rtc01_mutantes_da_confirmacao_reprovam() {
  local base mutante
  mutante=$(_copia_mutante commands/reter.sh 's/^\(.*\)# MUTACAO:confirmar$/  confirmar=sim/')
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  assert_diferente 0 "$(_deletes "$base")" 'o mutante apaga sem --confirmar e o registro o pega'
  # Sem a leitura do --dry-run no comando, o ponto unico de escrita de lib/cmd
  # ainda nao emite o delete_v2 (segunda barreira, RF-15).
  mutante=$(_copia_mutante commands/reter.sh 's/^\(.*\)# MUTACAO:simulacao$/  :/')
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$(_deletes "$base")" 'lib/cmd barra a escrita simulada'
  mutante=$(_copia_mutante commands/reter.sh 's/^\(.*\)# MUTACAO:simulacao$/  :/' \
    lib/cmd.sh "s/^  if \[\[ \\\${DBX_CLI_SIMULACAO:-nao} == 'sim' \]\]; then$/  if false; then/")
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_diferente 0 "$(_deletes "$base")" 'sem as duas barreiras, o registro pega o delete simulado'
}

teste_rtc04_um_so_plano_nos_tres_modos() {
  local base plano simulado
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  plano=$(_conjunto_sai "$DBX_SAIDA")
  _rodar "$base" --dry-run reter /bk --padrao 'db-*.tar' --manter 2
  simulado=$(_conjunto_sai "$DBX_SAIDA")
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 'db-3.tar db-2.tar db-1.tar' "$plano" 'o plano'
  assert_igual "$plano" "$simulado" 'simulado igual'
  assert_igual "$plano" "$(_conjunto_sai "$DBX_SAIDA")" 'confirmado igual'
  assert_igual 'db-1.tar db-2.tar db-3.tar' "$(_ordem_dos_deletes "$base")" 'apaga exatamente esse conjunto'
}

teste_rtc05_com_terminal_nao_pergunta() {
  local base
  command -v script >/dev/null 2>&1 || pular 'script(1) ausente: sem terminal para o caso'
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  local exec_citado
  printf -v exec_citado '%q' "$DBX_EXEC_PADRAO"
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    timeout -k 2 30 script -qec "bash $exec_citado reter /bk --padrao 'db-*.tar' --manter 2 --confirmar" /dev/null \
    </dev/null >"$base/out" 2>&1
  assert_igual 0 "$?" 'nao bloqueia nem pergunta'
  assert_igual 3 "$(_deletes "$base")" 'apagou com o --confirmar'
}

teste_rtc06_linhas_na_ordem_e_fora_do_padrao_so_contado() {
  local base nomes='' linha
  base=$(_ambiente)
  _listagem "$base" "$CINCO,$(_pasta pastinha),$(_arq nota.txt 2026-01-01T00:00:00Z 0000000000a)"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  while IFS= read -r linha; do
    [[ $linha == 'name='* ]] && nomes+="${linha#name=} "
  done <<<"$DBX_SAIDA"
  assert_igual 'db-5.tar db-4.tar db-3.tar db-2.tar db-1.tar ' "$nomes" 'do mais novo ao mais velho, so candidatos'
  assert_contem 'fora_do_padrao=1' "$DBX_SAIDA" 'contado'
  assert_contem 'ignorados=1' "$DBX_SAIDA" 'pasta contada'
  assert_contem 'listados=7' "$DBX_SAIDA" 'total da pasta'
}

teste_rtc07_padrao_amplo_avisa_nos_tres_modos() {
  local base p opcoes
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  for p in '*' '?*'; do
    for opcoes in '' --dry-run; do
      # shellcheck disable=SC2086
      _rodar "$base" $opcoes reter /bk --padrao "$p" --manter 5
      assert_contem "o padrao '$p' casa todo arquivo da pasta" "$DBX_ERRO" "aviso [$p] [$opcoes]"
    done
    _rodar "$base" reter /bk --padrao "$p" --manter 5 --confirmar
    assert_contem "o padrao '$p' casa todo arquivo da pasta" "$DBX_ERRO" "aviso [$p] confirmado"
  done
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 5
  assert_nao_contem 'casa todo arquivo' "$DBX_ERRO" 'padrao com literal sem aviso'
}

teste_rtc08_nenhum_plano_gravado_em_disco() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual '' "$(_residuo "$base")" 'TMPDIR vazio'
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'nenhum diretorio de estado criado'
  assert_igual '' "$(_retrato "$base/trabalho")" 'nada no diretorio de trabalho'
}

# ===========================================================================
# TC-RTG — guarda sem estado (RF-97)
# ===========================================================================

teste_rtg01_fora_da_raiz_e_controle_sao_13_sem_chamada() {
  local base caminho
  base=$(_ambiente /bk)
  for caminho in /outra /bk/../fora $'/bk/a\nb' $'/bk/a\rb'; do
    _rodar "$base" reter "$caminho" --padrao '*.tar' --manter 1 --confirmar
    assert_igual 13 "$DBX_ESTADO" "recusado: [$caminho]"
  done
  _nenhuma_chamada "$base" 'zero chamadas'
}

teste_rtg02_a_raiz_remota_e_a_raiz_da_conta_sao_alvo() {
  local base
  base=$(_ambiente /bk)
  _listagem "$base" "$CINCO"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1
  assert_igual 0 "$DBX_ESTADO" "a propria raiz_remota: $DBX_ERRO"
  base=$(_ambiente /)
  _listagem "$base" "$(_arq db-1.tar 2026-10-01T00:00:00Z 0000000001a '' ''),$(_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a '' '')" '*"path":""*'
  _apagar_ok "$base"
  _rodar "$base" reter / --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "a raiz da conta com raiz_remota /: $DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '^files/delete_v2 {"path":"/db-1.tar","parent_rev":"0000000001a"}$')" 'so o nivel de cima'
}

teste_rtg03_mutante_sem_a_conferencia_da_listagem_ainda_e_barrado_pela_guarda() {
  local mutante base entrada
  mutante=$(_copia_mutante commands/reter.sh '/# MUTACAO:coerencia$/d')
  for entrada in "$(_arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /bk/sub /Bk/sub)" \
    "$(_arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /outra /Outra)"; do
    base=$(_ambiente)
    _listagem "$base" "$entrada,$CINCO"
    _apagar_ok "$base"
    DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    assert_igual 10 "$DBX_ESTADO" 'a guarda no ponto do delete_v2 barra'
    assert_igual 0 "$(_deletes "$base")" 'o item incoerente e o primeiro a sair; nada apagado'
  done
  # Sem as duas barreiras, o registro de chamadas acusa.
  mutante=$(_copia_mutante commands/reter.sh '/# MUTACAO:coerencia$/d' commands/reter.sh '/# MUTACAO:guarda$/d')
  base=$(_ambiente)
  _listagem "$base" "$(_arq db-0.tar 2020-01-01T00:00:00Z 0000000000a /outra /Outra),$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_diferente 0 "$(_chamadas "$base" '"path":"/outra/')" 'sem barreira, o delete fora da pasta aparece'
}

teste_rtg04_pasta_fora_do_ascii_com_dobra_diferente_falha_fechada() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*' 200 "{\"entries\":[$(_arq db-1.tar 2026-10-01T00:00:00Z 0000000001a $'/b\xc3\xa4ck' $'/B\xc3\xa4ck'),$(_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a $'/b\xc3\xa4ck' $'/B\xc3\xa4ck')],\"cursor\":\"c\",\"has_more\":false}"
  _apagar_ok "$base"
  _rodar "$base" reter $'/B\xc3\x84CK' --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 10 "$DBX_ESTADO" 'falha fechada'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
  _rodar "$base" reter $'/B\xc3\xa4CK' --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" "so o ASCII difere: $DBX_ERRO"
}

teste_rtg05_name_diferente_do_path_lower_e_10() {
  local base
  base=$(_ambiente)
  _listagem "$base" "{\".tag\":\"file\",\"name\":\"db-0.tar\",\"path_lower\":\"/bk/outro.bin\",\"path_display\":\"/Bk/outro.bin\",\"server_modified\":\"2020-01-01T00:00:00Z\",\"rev\":\"0000000000a\"},$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 10 "$DBX_ESTADO" 'incoerente'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

teste_rtg06_rtg11_todo_delete_leva_path_lower_e_parent_rev_listados() {
  local base linha sem=0
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  for linha in '{"path":"/bk/db-1.tar","parent_rev":"0000000001a"}' \
    '{"path":"/bk/db-2.tar","parent_rev":"0000000002a"}' '{"path":"/bk/db-3.tar","parent_rev":"0000000003a"}'; do
    assert_igual 1 "$(_chamadas "$base" "^files/delete_v2 ${linha//[/\\[}\$")" "corpo exato: $linha"
  done
  while IFS= read -r linha; do
    [[ $linha == files/delete_v2* && $linha != *'"parent_rev":"'* ]] && sem=$((sem + 1))
  done <"$base/chamadas"
  assert_igual 0 "$sem" 'nenhum delete_v2 sem parent_rev'
}

teste_rtg06_mutante_sem_parent_rev_reprova() {
  local mutante base
  mutante=$(_copia_mutante commands/reter.sh 's/,\\"parent_rev\\":\\"\$[A-Za-z_]*\\"//')
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$(_chamadas "$base" 'parent_rev')" 'o mutante apaga sem parent_rev'
  assert_diferente 0 "$(_deletes "$base")" 'e o registro mostra o delete sem a guarda otimista'
}

teste_rtg07_parent_rev_divergente_e_conflito_e_os_demais_seguem() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' 409 '{"error_summary":"path_write/conflict/file/..","error":{".tag":"path_write"}}'
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 14 "$DBX_ESTADO" 'falha parcial'
  assert_igual 'db-1.tar db-2.tar db-3.tar' "$(_ordem_dos_deletes "$base")" 'os demais seguem, sem nova tentativa'
  assert_contem 'motivo=conflito' "$DBX_SAIDA" 'motivo'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'falhas'
  assert_igual 0 "$(_chamadas "$base" '^files/delete_v2 {"path":"/bk/db-2.tar"}')" 'nunca sem parent_rev'
}

teste_rtg08_estado_envenenado_nao_muda_o_plano_nem_os_deletes() {
  local vazio envenenado
  vazio=$(_ambiente)
  envenenado=$(_ambiente)
  mkdir -p "$envenenado/estado/dbx/sync"
  printf '/bk/db-5.tar\n/bk/db-4.tar\n' >"$envenenado/estado/dbx/plano-reter"
  printf '{"/bk/db-5.tar":"x"}' >"$envenenado/estado/dbx/sync/memoria.json"
  for base in "$vazio" "$envenenado"; do
    _listagem "$base" "$CINCO"
    _apagar_ok "$base"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
    assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  done
  assert_igual "$(_ordem_dos_deletes "$vazio")" "$(_ordem_dos_deletes "$envenenado")" 'deletes identicos'
}

teste_rtg09_mutante_que_zera_o_n_nunca_apaga_o_primeiro() {
  local mutante base
  mutante=$(_copia_mutante lib/retencao.sh 's/^\(.*\)# MUTACAO:valor$/  valor=0/')
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 3 --confirmar
  assert_igual 0 "$(_chamadas "$base" 'db-5.tar')" 'o primeiro da ordem nunca chega ao delete_v2'
  # Sem o minimo, a guarda do primeiro ainda barra.
  mutante=$(_copia_mutante lib/retencao.sh 's/^\(.*\)# MUTACAO:valor$/  valor=0/' lib/retencao.sh '/# MUTACAO:minimo$/d')
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 3 --confirmar
  assert_igual 0 "$(_chamadas "$base" 'db-5.tar')" 'sem o minimo, a guarda barra o primeiro'
  assert_igual 10 "$DBX_ESTADO" 'e para com 10'
}

teste_rtg10_resposta_2xx_incoerente_do_delete_para_antes_do_proximo() {
  local base corpo
  for corpo in '{}' '{"metadata":{".tag":"file","path_lower":"/bk/outro.tar"}}' \
    '{"metadata":{".tag":"folder","path_lower":"@PATH@"}}' 'nao json' \
    '{"metadata":{".tag":"file","path_lower":"@PATH@","path_lower":"@PATH@"}}'; do
    base=$(_ambiente)
    _listagem "$base" "$CINCO"
    _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' 200 "$corpo"
    _apagar_ok "$base"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
    assert_igual 10 "$DBX_ESTADO" "resposta [$corpo]"
    assert_igual 'db-1.tar db-2.tar' "$(_ordem_dos_deletes "$base")" 'para antes do proximo'
    assert_contem 'apagados=1' "$DBX_SAIDA" 'resumo com o que ja foi apagado'
    assert_contem 'nao_tentados=1' "$DBX_SAIDA" 'e o que ficou'
  done
}

teste_rtg12_auditoria_estatica_sem_rota_destrutiva_alheia() {
  local texto
  texto=$(grep -vhE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/reter.sh" "$DBX_HARNESS_RAIZ/lib/retencao.sh")
  assert_nao_contem 'permanently_delete' "$texto" 'sem exclusao permanente'
  assert_nao_contem 'delete_batch' "$texto" 'sem lote'
  assert_nao_contem 'dbx_state_' "$texto" 'sem lib/state'
  assert_nao_contem 'dbx_cmd_ciclo_iniciar' "$texto" 'sem trava'
}

# ===========================================================================
# TC-RTX — execucao confirmada (RF-98)
# ===========================================================================

teste_rtx02_permissao_no_segundo_segue_e_sai_14() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' 409 '{"error_summary":"path_write/no_write_permission/.."}'
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 14 "$DBX_ESTADO" 'falha parcial'
  assert_igual 'db-1.tar db-2.tar db-3.tar' "$(_ordem_dos_deletes "$base")" 'segue'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'falhas'
  assert_contem 'motivo=permissao' "$DBX_SAIDA" 'classe'
  assert_contem 'apagados=2' "$DBX_SAIDA" 'apagados'
}

teste_rtx03_autenticacao_taxa_e_rede_esgotados_param() {
  local base caso codigo corpo
  for caso in '401|{"error_summary":"invalid_access_token/.."}' '429|{"error_summary":"too_many_requests/.."}' 'REDE|x'; do
    codigo=${caso%%|*} corpo=${caso#*|}
    base=$(_ambiente)
    _listagem "$base" "$CINCO"
    _regra "$base" files/delete_v2 '*' "$codigo" "$corpo"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
    assert_igual 14 "$DBX_ESTADO" "parada por $codigo"
    assert_contem 'nao_tentados=2' "$DBX_SAIDA" 'os restantes'
    assert_igual 0 "$(_chamadas "$base" 'db-2.tar')" 'nada depois da parada'
  done
}

teste_rtx04_rtx05_ja_ausente_e_retentativa() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _regra "$base" files/delete_v2 '*"/bk/db-1.tar"*' 409 '{"error_summary":"path_lookup/not_found/.."}'
  _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' 503 'indisponivel' uma
  _regra "$base" files/delete_v2 '*"/bk/db-3.tar"*' REDE x uma
  _regra "$base" files/delete_v2 '*"/bk/db-3.tar"*' 409 '{"error_summary":"path_lookup/not_found/.."}'
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "ja ausente nao e falha: $DBX_ERRO"
  assert_contem 'ja_ausentes=2' "$DBX_SAIDA" 'not_found direto e depois da resposta perdida'
  assert_contem 'apagados=1' "$DBX_SAIDA" '503 e depois sucesso'
  assert_contem 'falhas=0' "$DBX_SAIDA" 'sem falha'
  assert_igual 2 "$(_chamadas "$base" 'db-2.tar')" 'repetiu o 503'
}

teste_rtx06_too_many_write_operations_e_retry_after() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _regra "$base" files/delete_v2 '*"/bk/db-1.tar"*' 409 '{"error_summary":"too_many_write_operations/.."}' uma
  _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' 429 '{"error_summary":"too_many_requests/.."}' uma 'Retry-After: 7'
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'apagados=3' "$DBX_SAIDA" 'todos apagados na segunda tentativa'
  assert_igual 1 "$(_harness_contar '^7\.000$' "$base/esperas")" 'Retry-After respeitado'
}

teste_rtx07_artefato_novo_durante_a_execucao_nunca_e_apagado() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  # O "upload" termina durante a execucao: a proxima listagem o traria, mas o
  # plano e desta listagem.
  _regra "$base" files/list_folder '*' 200 "{\"entries\":[$(_arq db-0.tar 2019-01-01T00:00:00Z 0000000000a),$CINCO],\"cursor\":\"c\",\"has_more\":false}"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_igual 1 "$(_chamadas "$base" '^files/list_folder ')" 'uma listagem so'
  assert_igual 0 "$(_chamadas "$base" 'db-0.tar')" 'o que nao estava na listagem nunca e apagado'
}

teste_rtx08_duas_execucoes_simultaneas() {
  local base n p1 p2 e1 e2
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  for n in 1 2 3; do
    _regra "$base" files/delete_v2 "*\"/bk/db-$n.tar\"*" 200 '{"metadata":{".tag":"file","path_lower":"@PATH@"}}' uma
    _regra "$base" files/delete_v2 "*\"/bk/db-$n.tar\"*" 409 '{"error_summary":"path_lookup/not_found/.."}'
  done
  mkdir -p "$base/b"
  (
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
      TMPDIR="$base/tmp" timeout -k 2 60 bash "$DBX_EXEC_PADRAO" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar \
      </dev/null >"$base/out1" 2>"$base/err1"
  ) &
  p1=$!
  (
    env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" XDG_STATE_HOME="$base/estado" \
      TMPDIR="$base/tmp" timeout -k 2 60 bash "$DBX_EXEC_PADRAO" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar \
      </dev/null >"$base/out2" 2>"$base/err2"
  ) &
  p2=$!
  wait "$p1"
  e1=$?
  wait "$p2"
  e2=$?
  assert_igual 0 "$e1" 'a primeira termina sem falha'
  assert_igual 0 "$e2" 'a segunda termina sem falha'
  assert_igual 0 "$(_chamadas "$base" 'db-[45].tar')" 'os dois mais novos restam'
  assert_igual 0 "$(_harness_contar 'falhas=[1-9]' "$base/out1")" 'sem falha na primeira'
  assert_igual 0 "$(_harness_contar 'falhas=[1-9]' "$base/out2")" 'sem falha na segunda'
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'nenhuma trava criada'
}

teste_rtx09_sinal_entre_dois_deletes_sai_14_sem_proximo_delete() {
  local base sinal
  for sinal in INT TERM HUP; do
    base=$(_ambiente)
    _listagem "$base" "$CINCO"
    _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' "SINAL:$sinal:200" '{"metadata":{".tag":"file","path_lower":"@PATH@"}}'
    _apagar_ok "$base"
    _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
    assert_igual 14 "$DBX_ESTADO" "$sinal sai 14"
    assert_igual 'db-1.tar db-2.tar' "$(_ordem_dos_deletes "$base")" "nenhum delete_v2 depois do $sinal"
    assert_contem 'interrompido' "$DBX_ERRO" "resumo parcial em stderr ($sinal)"
    assert_contem 'db-3.tar' "$DBX_ERRO" 'o que nao foi tentado'
    assert_igual '' "$(_residuo "$base")" 'TMPDIR limpo'
  done
}

teste_rtx10_autenticacao_na_renovacao_antes_de_qualquer_delete() {
  local base
  base=$(_ambiente)
  _regra "$base" oauth2/token '*' 400 '{"error":"invalid_grant","error_description":"x"}'
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  assert_igual 5 "$DBX_ESTADO" 'renovacao recusada'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

teste_rtx11_rtx12_sem_segredo_e_com_a_recuperacao() {
  local base canal
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _regra "$base" files/delete_v2 '*"/bk/db-2.tar"*' 409 "{\"error_summary\":\"path_write/no_write_permission/$SENTINELA_TOKEN\"}"
  _apagar_ok "$base"
  _rodar "$base" --debug reter /bk --padrao 'db-*.tar' --manter 2 --confirmar
  for canal in "$DBX_SAIDA" "$DBX_ERRO"; do
    assert_segredo_ausente "$SENTINELA_TOKEN" "$canal" 'token'
    assert_segredo_ausente "$SENTINELA_REFRESH" "$canal" 'refresh'
    assert_segredo_ausente "$SENTINELA_SEGREDO" "$canal" 'segredo'
  done
  assert_contem 'dbx lixeira /bk' "$DBX_SAIDA$DBX_ERRO" 'recuperacao pela lixeira'
  assert_contem 'dbx restaurar' "$DBX_SAIDA$DBX_ERRO" 'e pelo restaurar'
}

# ===========================================================================
# DIV-134 — relogio local conferido contra o Date da listagem
# ===========================================================================

teste_div134_relogio_divergente_sai_3_sem_delete() {
  local base
  base=$(_ambiente)
  printf 'Mon, 01 Jan 2001 00:00:00 GMT\n' >"$base/data"
  _listagem "$base" "$(_arq db-1.tar 2000-01-01T00:00:00Z 0000000001a),$(_arq db-2.tar 2000-01-02T00:00:00Z 0000000002a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
  assert_igual 3 "$DBX_ESTADO" 'divergencia acima de 300 s'
  assert_contem 'relogio local diverge do servidor' "$DBX_ERRO" 'mensagem'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_igual 0 "$DBX_ESTADO" '--manter nao usa o relogio'
}

teste_div134_date_ausente_ou_malformado_com_dias_e_10() {
  local base
  base=$(_ambiente)
  : >"$base/sem_data"
  _listagem "$base" "$(_arq db-1.tar 2000-01-01T00:00:00Z 0000000001a),$(_arq db-2.tar 2000-01-02T00:00:00Z 0000000002a)"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
  assert_igual 10 "$DBX_ESTADO" 'Date ausente'
  rm -f "$base/sem_data"
  printf 'ontem\n' >"$base/data"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
  assert_igual 10 "$DBX_ESTADO" 'Date malformado'
  assert_igual 0 "$(_deletes "$base")" 'zero delete_v2'
}

teste_div134_mutante_sem_a_conferencia_do_relogio_reprova() {
  local mutante base
  mutante=$(_copia_mutante commands/reter.sh '/# MUTACAO:relogio$/d')
  base=$(_ambiente)
  printf 'Mon, 01 Jan 2001 00:00:00 GMT\n' >"$base/data"
  _listagem "$base" "$(_arq db-1.tar 2000-01-01T00:00:00Z 0000000001a),$(_arq db-2.tar 2000-01-02T00:00:00Z 0000000002a)"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 1 --confirmar
  assert_diferente 0 "$(_deletes "$base")" 'sem a conferencia, o relogio errado apaga'
}

teste_p04_mutante_sem_a_validacao_de_server_modified_reprova() {
  local mutante base
  mutante=$(_copia_mutante lib/retencao.sh '/# MUTACAO:carimbo$/d' commands/reter.sh '/# MUTACAO:carimbo$/d')
  base=$(_ambiente)
  _listagem "$base" "$CINCO,$(_arq db-9.tar 2026-02-30T00:00:00Z 0000000009a)"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_diferente 0 "$(_deletes "$base")" 'sem a validacao, a ordem indefinida apaga'
}

teste_p04_mutante_sem_o_cursor_repetido_reprova() {
  local mutante base
  mutante=$(_copia_mutante commands/reter.sh '/# MUTACAO:cursor$/d')
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$CINCO],\"cursor\":\"c1\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*' 200 '{"entries":[],"cursor":"c1","has_more":true}' uma
  _regra "$base" files/list_folder/continue '*' 200 '{"entries":[],"cursor":"c9","has_more":false}'
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  assert_diferente 0 "$(_deletes "$base")" 'sem a conferencia do cursor, apaga com listagem suspeita'
}

teste_p02_mutantes_de_selecao_reprovam() {
  local base mutante
  # Sem o filtro de tag: a pasta que casa o padrao vira candidata.
  mutante=$(_copia_mutante commands/reter.sh 's/^\(.*\)# MUTACAO:tag$/  :/' commands/reter.sh '/# MUTACAO:guarda$/d')
  base=$(_ambiente)
  _listagem "$base" "{\".tag\":\"folder\",\"name\":\"db-0.tar\",\"path_lower\":\"/bk/db-0.tar\",\"path_display\":\"/Bk/db-0.tar\",\"server_modified\":\"2000-01-01T00:00:00Z\",\"rev\":\"0000000000a\"},$CINCO"
  _apagar_ok "$base"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 4 --confirmar
  assert_igual 0 "$(_chamadas "$base" 'db-0.tar')" 'sem mutacao, a pasta nunca e apagada'
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 4 --confirmar
  assert_diferente 0 "$(_chamadas "$base" 'db-0.tar')" 'sem o filtro de tag, a pasta seria apagada'
  # Sem o casamento do padrao=o arquivo fora do padrao vira candidato.
  mutante=$(_copia_mutante commands/reter.sh 's/^\(.*\)# MUTACAO:padrao$/  :/' commands/reter.sh '/# MUTACAO:guarda$/d')
  base=$(_ambiente)
  _listagem "$base" "$(_arq nota.txt 2000-01-01T00:00:00Z 0000000000a),$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$mutante _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 5 --confirmar
  assert_diferente 0 "$(_chamadas "$base" 'nota.txt')" 'sem o casamento, o fora do padrao seria apagado'
}

# ===========================================================================
# TC-RTO — saida (RF-99)
# ===========================================================================

teste_rto01_rto05_texto_com_cabecalho_linhas_e_resumo() {
  local base campo
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 2
  for campo in 'operacao=reter' 'pasta=/bk' "padrao='db-*.tar'" 'politica=manter' 'valor=2' \
    'modo=plano' 'simulado=nao' 'acao=fica' 'name=db-5.tar' 'path_display=/Bk/db-5.tar' \
    'server_modified=2026-10-05T00:00:00Z' 'size=10' 'rev=0000000005a' 'candidatos=5' 'ficam=2' \
    'saem=3' 'mantido_pelo_minimo=nao' 'fora_do_padrao=0' 'ignorados=0' 'ja_ausentes=0' 'falhas=0' \
    'nao_tentados=0' 'listados=5'; do
    assert_contem "$campo" "$DBX_SAIDA" "campo [$campo]"
  done
  assert_nao_contem 'corte:' "$DBX_SAIDA" 'corte so com --dias'
  assert_nao_contem 'agora:' "$DBX_SAIDA" 'agora so com --dias'
  _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 3650
  assert_contem 'politica=dias' "$DBX_SAIDA" 'politica dias'
  assert_contem 'corte=' "$DBX_SAIDA" 'corte'
  assert_contem 'agora=' "$DBX_SAIDA" 'agora'
}

teste_rto02_json_com_a_versao_do_contrato() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _rodar "$base" --json reter /bk --padrao 'db-*.tar' --manter 2
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  assert_contem 'contrato=1' "$DBX_SAIDA" 'versao do contrato'
  assert_contem 'operacao=reter' "$DBX_SAIDA" 'operacao'
  assert_contem 'saem=3' "$DBX_SAIDA" 'resumo'
}

teste_rto03_rto04_null_intacto_e_texto_escapado() {
  local base nulo
  base=$(_ambiente)
  _listagem "$base" "{\".tag\":\"file\",\"name\":\"db-a\\nb.tar\",\"path_lower\":\"/bk/db-a\\nb.tar\",\"path_display\":\"/Bk/db-a\\nb.tar\",\"id\":\"id:anb\",\"server_modified\":\"2026-10-01T00:00:00Z\",\"rev\":\"0000000001a\",\"size\":1},$(_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a)"
  _rodar "$base" --null reter /bk --padrao 'db-*.tar' --manter 1
  assert_igual 0 "$DBX_ESTADO" "$DBX_ERRO"
  nulo=$(tr '\0' '|' <"$base/out")
  assert_contem $'name=db-a\nb.tar|' "$nulo" 'o nome com quebra chega intacto no --null'
  _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1
  assert_igual 0 "$DBX_ESTADO" "texto: $DBX_ERRO"
  assert_contem "name=\$'db-a\\nb.tar'" "$DBX_SAIDA" 'escapado no texto'
}

teste_rto06_avisos_so_em_stderr() {
  local base com sem
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _rodar "$base" reter /bk --padrao '*' --manter 2
  com=$DBX_SAIDA
  assert_contem 'nada foi apagado' "$DBX_ERRO" 'avisos em stderr'
  assert_nao_contem 'nada foi apagado' "$DBX_SAIDA" 'nunca em stdout'
  assert_nao_contem 'casa todo arquivo' "$DBX_SAIDA" 'nunca em stdout'
  _rodar "$base" reter /bk --padrao '*' --manter 2
  sem=$DBX_SAIDA
  assert_igual "$com" "$sem" 'stdout so com o plano'
}

# ===========================================================================
# TC-CPL-11, TC-DOC-05, TC-TST-09 (RF-100)
# ===========================================================================

_ajuda() { env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC_PADRAO" help "$@" 2>&1; }

_opcoes_da_ajuda() { # <comando> — a mesma leitura de completar_test
  local linha secao=nao
  while IFS= read -r linha; do
    [[ $linha == Opcoes* ]] && secao=sim && continue
    [[ -z $linha ]] && secao=nao
    [[ $secao == sim && $linha == '  -'* ]] || continue
    linha=${linha#  }
    linha=${linha%%  *}
    grep -oE '(^|[ ,])-{1,2}[A-Za-z][A-Za-z-]*' <<<"$linha" | tr -d ' ,'
  done < <(_ajuda "$@") | LC_ALL=C sort -u
}

_completar() {
  env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash -c '
    . "$1"; shift
    COMP_WORDS=(dbx "$@"); COMP_CWORD=$#; COMPREPLY=()
    _dbx_completar dbx "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    for item in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do printf "%s\n" "$item"; done
  ' _ "$DBX_HARNESS_RAIZ/completions/dbx.bash" "$@" 2>&1 | LC_ALL=C sort -u
}

teste_cpl11_ajuda_e_autocompletar_coincidem() {
  local opcoes
  opcoes=$(_opcoes_da_ajuda reter)
  assert_contem '--padrao' "$opcoes" 'a ajuda traz --padrao'
  assert_contem '--keep' "$opcoes" 'e os aliases'
  assert_igual "$opcoes" "$(_completar reter -)" 'opcoes de reter'
  assert_igual "$opcoes" "$(_completar retain -)" 'pelo alias retain'
  assert_contem 'retain' "$(_completar re)" 'alias completado'
  assert_contem 'reter' "$(_completar re)" 'comando completado'
  assert_igual '' "$(_completar reter --padrao '')" 'valor de --padrao nao e completado'
  assert_igual "$(_ajuda reter)" "$(_ajuda retain)" 'a ajuda do alias e a mesma'
}

teste_doc05_ajuda_e_readme_trazem_as_frases() {
  local texto readme frase
  texto=$(_ajuda reter)
  IFS= read -r -d '' readme <"$DBX_HARNESS_RAIZ/README.md" || :
  for frase in 'sem --confirmar nada e apagado: o comando so mostra o plano' \
    'sempre mantem pelo menos 1 artefato' \
    'so o nivel de cima da pasta e so arquivos; o padrao casa o nome, sem diferenciar maiusculas' \
    'o mais novo e o de data do servidor mais recente; em empate, o de maior nome' \
    'os apagados vao para a lixeira e podem ser recuperados com dbx restaurar dentro do prazo do plano da conta' \
    '--dias compara a data do servidor com o relogio desta maquina' \
    'restaurar ou regravar um artefato antigo o torna o mais novo' \
    "dbx upload ... && dbx reter /backups --padrao 'db-*.tar.gz' --manter 7 --confirmar"; do
    assert_contem "$frase" "$texto" "ajuda: $frase"
  done
  assert_contem 'reter' "$(_ajuda)" 'lista de comandos'
  assert_contem 'retain' "$(_ajuda)" 'alias na lista'
  for frase in 'Retencao de backup' 'dbx reter' '--manter' '--dias' '--confirmar' 'lixeira' 'cron'; do
    assert_contem "$frase" "$readme" "README: $frase"
  done
  assert_nao_contem 'reter' "$(<"$DBX_HARNESS_RAIZ/commands/diagnostico.sh")" 'diagnostico inalterado'
}

# ===========================================================================
# Ciclo 1 do QA (DIV-158, DIV-159, DIV-160)
# ===========================================================================

# _qa158 <produto> — 0 quando a listagem com path_lower repetido (mesma pagina
# ou outra pagina, caixa ASCII diferente) nunca apaga o caminho do que fica.
# Status 0/1 e em _QA158_ESTADO o ultimo codigo de saida.
_QA158_ESTADO=''
_qa158() {
  local base
  base=$(_ambiente)
  _listagem "$base" "$(_arq db-5.tar 2026-10-05T00:00:00Z 0000000005a),$(_arq db-5.tar 2026-10-05T00:00:00Z 0000000005a)"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  [[ $(_chamadas "$base" '"path":"/bk/db-5.tar"') -eq 0 ]] || return 1
  _QA158_ESTADO=$DBX_ESTADO
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$(_arq db-5.tar 2026-10-05T00:00:00Z 0000000005a)],\"cursor\":\"c1\",\"has_more\":true}"
  _regra "$base" files/list_folder/continue '*' 200 "{\"entries\":[{\".tag\":\"file\",\"name\":\"DB-5.TAR\",\"path_lower\":\"/BK/DB-5.TAR\",\"path_display\":\"/Bk/DB-5.TAR\",\"server_modified\":\"2026-10-01T00:00:00Z\",\"rev\":\"0000000005a\"}],\"cursor\":\"c2\",\"has_more\":false}"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  [[ $(_chamadas "$base" '"path":"/[bB][kK]/[dD][bB]-5') -eq 0 ]] || return 1
  [[ $_QA158_ESTADO == "$DBX_ESTADO" ]] || _QA158_ESTADO="$_QA158_ESTADO/$DBX_ESTADO"
  return 0
}

teste_div158_path_lower_repetido_sai_10_sem_delete() {
  _qa158 "$DBX_EXEC_PADRAO" || _harness_falhar 'o caminho do que fica recebeu delete_v2'
  assert_igual 10 "$_QA158_ESTADO" 'listagem com path_lower repetido: 10 nas duas formas'
}

teste_div158_mutantes_das_tres_barreiras() {
  local m1 m2 m3
  # Sem a conferencia da listagem: o plano recusa caminho repetido (10).
  m1=$(_copia_mutante commands/reter.sh '/# MUTACAO:duplicado$/d')
  _qa158 "$m1" || _harness_falhar 'segunda barreira (plano) nao segurou'
  assert_igual 10 "$_QA158_ESTADO" 'o plano recusa'
  # Sem a listagem e sem o plano: a guarda por caminho barra o que fica.
  m2=$(_copia_mutante commands/reter.sh '/# MUTACAO:duplicado$/d' lib/retencao.sh '/# MUTACAO:unico$/d')
  _qa158 "$m2" || _harness_falhar 'terceira barreira (guarda por caminho) nao segurou'
  # Sem as tres, o registro de chamadas acusa o delete do que fica.
  m3=$(_copia_mutante commands/reter.sh '/# MUTACAO:duplicado$/d' lib/retencao.sh '/# MUTACAO:unico$/d' \
    lib/retencao.sh '/# MUTACAO:fica$/d' commands/reter.sh '/# MUTACAO:identidade$/d' lib/retencao.sh '/# MUTACAO:identidade_guarda$/d')
  _qa158 "$m3" && _harness_falhar 'sem as tres barreiras o caso deveria acusar o delete'
  return 0
}

# _qa159 <produto> — 0 quando name `.`/`..` ou path_lower nao normalizado
# derruba a execucao com 10 e ZERO delete_v2.
_qa159() {
  local base entrada
  for entrada in \
    '{".tag":"file","name":"..","path_lower":"/bk/..","path_display":"/Bk/..","server_modified":"2026-10-02T00:00:00Z","id":"id:ponto","rev":"00000000d2a"}' \
    '{".tag":"file","name":".","path_lower":"/bk/.","path_display":"/Bk/.","server_modified":"2026-10-02T00:00:00Z","id":"id:ponto","rev":"00000000d2a"}' \
    '{".tag":"folder","name":"..","path_lower":"/bk/.."}'; do
    base=$(_ambiente)
    _listagem "$base" "$entrada,$CINCO"
    _apagar_ok "$base"
    DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*' --manter 1 --confirmar
    [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || return 1
  done
  return 0
}

teste_div159_ponto_e_ponto_ponto_derrubam_a_listagem() {
  _qa159 "$DBX_EXEC_PADRAO" || _harness_falhar 'name . ou .. nao derrubou a listagem antes de qualquer exclusao'
  return 0
}

teste_div159_mutante_sem_a_conferencia_de_normalizacao_reprova() {
  local m
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:normalizado$/d')
  _qa159 "$m" && _harness_falhar 'o mutante deveria apagar antes de a guarda parar'
  return 0
}

# _qa160 <produto> <data_p1> <data_p2> — codigo de saida com --dias e o Date
# de cada pagina dado pela regra.
_qa160() {
  local base
  base=$(_ambiente)
  _regra "$base" files/list_folder '*"/bk"*' 200 "{\"entries\":[$(_arq db-1.tar 2000-01-01T00:00:00Z 0000000001a)],\"cursor\":\"c1\",\"has_more\":true}" - "Date: $2"
  _regra "$base" files/list_folder/continue '*' 200 "{\"entries\":[$(_arq db-2.tar 2000-01-02T00:00:00Z 0000000002a)],\"cursor\":\"c2\",\"has_more\":false}" - "Date: $3"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --dias 1
  printf '%s' "$DBX_ESTADO"
}

teste_div160_relogio_conferido_contra_a_ultima_pagina() {
  local agora antigo='Mon, 01 Jan 2001 00:00:00 GMT'
  agora=$(TZ=UTC0 LC_ALL=C bash -c 'printf "%(%a, %d %b %Y %H:%M:%S GMT)T" -1')
  assert_igual 0 "$(_qa160 "$DBX_EXEC_PADRAO" "$antigo" "$agora")" 'a ultima pagina concorda: 0'
  assert_igual 3 "$(_qa160 "$DBX_EXEC_PADRAO" "$agora" "$antigo")" 'a ultima pagina diverge: 3'
}

teste_div160_mutante_que_le_so_a_primeira_pagina_reprova() {
  local m agora antigo='Mon, 01 Jan 2001 00:00:00 GMT'
  agora=$(TZ=UTC0 LC_ALL=C bash -c 'printf "%(%a, %d %b %Y %H:%M:%S GMT)T" -1')
  m=$(_copia_mutante commands/reter.sh 's/^\( *\)\(_DBX_RETER_DATA=.*\) # MUTACAO:data$/\1((paginas == 1)) \&\& \2/')
  assert_diferente 3 "$(_qa160 "$m" "$agora" "$antigo")" 'o mutante nao ve a divergencia da ultima pagina'
}

# _qa161 <produto> — 0 quando (a) a duplicata em caixa nao ASCII, (b) o
# path_lower fora da minuscula Unicode e (c) a entrada fora do ASCII sem a
# localidade saem 10 com ZERO delete_v2, e (d) sem a localidade, a listagem so
# ASCII segue normal.
_qa161() {
  local E_MAI=$'\xc3\x89'
  local base
  base=$(_ambiente)
  _listagem "$base" "$(_arq $'\xc3\xa9.tar' 2026-10-05T00:00:00Z 0000000005a),{\".tag\":\"file\",\"name\":\"${E_MAI}.tar\",\"path_lower\":\"/bk/${E_MAI}.tar\",\"path_display\":\"/Bk/${E_MAI}.tar\",\"server_modified\":\"2026-10-01T00:00:00Z\",\"rev\":\"0000000005a\"}"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf a; return 1; }
  base=$(_ambiente)
  _listagem "$base" "{\".tag\":\"file\",\"name\":\"${E_MAI}.tar\",\"path_lower\":\"/bk/${E_MAI}.tar\",\"path_display\":\"/Bk/${E_MAI}.tar\",\"id\":\"id:emai\",\"server_modified\":\"2020-01-01T00:00:00Z\",\"rev\":\"00000000e1a\"},$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf b; return 1; }
  base=$(_ambiente)
  _listagem "$base" "$(_arq $'\xc3\xa9.tar' 2020-01-01T00:00:00Z 00000000e2a),$CINCO"
  _apagar_ok "$base"
  DBX_T_LOC=xx_INEXISTENTE.UTF-8 DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf c; return 1; }
  base=$(_ambiente)
  _listagem "$base" "$CINCO"
  _apagar_ok "$base"
  DBX_T_LOC=xx_INEXISTENTE.UTF-8 DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 0 && $(_deletes "$base") -eq 4 ]] || { printf d; return 1; }
  return 0
}

teste_div161_chave_unicode_nas_barreiras_da_listagem() {
  local falhou
  falhou=$(_qa161 "$DBX_EXEC_PADRAO") || _harness_falhar "cenario [$falhou] escapou"
  return 0
}

teste_div161_mutantes_reprovam() {
  local m falhou
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:minusculo$/d' commands/reter.sh '/# MUTACAO:identidade$/d' lib/retencao.sh '/# MUTACAO:identidade_guarda$/d')
  falhou=$(_qa161 "$m") && _harness_falhar 'sem exigir path_lower minusculo, o caso deveria pegar'
  assert_igual b "$falhou" 'o path_lower em maiuscula nao ASCII passa no mutante'
  m=$(_copia_mutante lib/retencao.sh '/# MUTACAO:localidade$/d')
  falhou=$(_qa161 "$m") && _harness_falhar 'sem a conferencia da localidade, o caso deveria pegar'
  assert_igual c "$falhou" 'fora do ASCII sem a localidade passa no mutante'
  # Sem a exigencia de minuscula e com as barreiras so ASCII, a duplicata apaga.
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:minusculo$/d' \
    lib/retencao.sh 's/^\(.*\)# MUTACAO:unicode$/  _dbx_retencao_ascii "$1"; DBX_RETENCAO_CHAVE=$_dbx_retencao_k/' commands/reter.sh '/# MUTACAO:identidade$/d' lib/retencao.sh '/# MUTACAO:identidade_guarda$/d')
  falhou=$(_qa161 "$m") && _harness_falhar 'com a dobra so ASCII, o caso deveria pegar'
  assert_igual a "$falhou" 'a duplicata em caixa nao ASCII apaga no mutante'
}

# _qa164 <produto> — 0 quando (a) NFC e NFD do mesmo nome e (b) uma pasta nao
# candidata com marca combinante saem 10 com ZERO delete_v2.
_qa164() {
  local base nfd=$'e\xcc\x81'
  base=$(_ambiente)
  _listagem "$base" "$(_arq $'\xc3\xa9.tar' 2026-10-05T00:00:00Z 0000000005a),{\".tag\":\"file\",\"name\":\"${nfd}.tar\",\"path_lower\":\"/bk/${nfd}.tar\",\"path_display\":\"/Bk/${nfd}.tar\",\"server_modified\":\"2026-10-01T00:00:00Z\",\"rev\":\"0000000005a\"}"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf a; return 1; }
  base=$(_ambiente)
  _listagem "$base" "{\".tag\":\"folder\",\"name\":\"${nfd}\",\"path_lower\":\"/bk/${nfd}\"},$CINCO"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf b; return 1; }
  return 0
}

teste_div164_marca_combinante_derruba_a_listagem() {
  local falhou
  falhou=$(_qa164 "$DBX_EXEC_PADRAO") || _harness_falhar "cenario [$falhou] escapou"
  return 0
}

teste_div164_mutantes_reprovam() {
  local m falhou
  # Sem a conferencia da listagem: a guarda segura o NFD que sai (zero delete),
  # mas a pasta nao candidata passa (b).
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:combinante$/d')
  falhou=$(_qa164 "$m") && _harness_falhar 'sem a conferencia da listagem, o caso deveria pegar'
  assert_igual b "$falhou" 'a pasta com marca combinante passa no mutante'
  # Sem a listagem e sem a guarda: o NFD que sai e apagado (a).
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:combinante$/d' lib/retencao.sh '/# MUTACAO:combinante_guarda$/d' commands/reter.sh '/# MUTACAO:identidade$/d' lib/retencao.sh '/# MUTACAO:identidade_guarda$/d')
  falhou=$(_qa164 "$m") && _harness_falhar 'sem as duas barreiras, o caso deveria pegar'
  assert_igual a "$falhou" 'o NFD do mesmo arquivo e apagado no mutante'
}

# _qa167 <produto> — 0 quando cada cenario sai 10 com ZERO delete_v2:
# (a) dois arquivos ASCII distintos com o mesmo rev; (b) mesmo id;
# (c) arquivo sem id; (d) arquivo fora do padrao sem rev;
# (e) kana NFC e NFD do mesmo nome com o mesmo rev (fora dos blocos de DIV-164).
_qa167() {
  local base ga=$'\xe3\x81\x8c' kad=$'\xe3\x81\x8b\xe3\x82\x99' e
  for e in \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":"id:z","server_modified":"2020-01-01T00:00:00Z","rev":"0000000005a"}' \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","id":"id:0000000005a","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000f"}' \
    '{".tag":"file","name":"db-0.tar","path_lower":"/bk/db-0.tar","path_display":"/Bk/db-0.tar","server_modified":"2020-01-01T00:00:00Z","rev":"0000000000f"}' \
    '{".tag":"file","name":"nota.txt","path_lower":"/bk/nota.txt","path_display":"/Bk/nota.txt","id":"id:nota","server_modified":"2020-01-01T00:00:00Z"}'; do
    base=$(_ambiente)
    _listagem "$base" "$e,$CINCO"
    _apagar_ok "$base"
    DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf '%s' "${e:0:40}"; return 1; }
  done
  base=$(_ambiente)
  _listagem "$base" "$(_arq "$ga.tar" 2026-10-05T00:00:00Z 0000000005a),$(_arq "$kad.tar" 2026-10-01T00:00:00Z 0000000005a /bk /Bk ',"x":1')"
  _apagar_ok "$base"
  DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf kana; return 1; }
  return 0
}

teste_div167_id_e_rev_unicos_na_listagem() {
  local falhou
  falhou=$(_qa167 "$DBX_EXEC_PADRAO") || _harness_falhar "cenario escapou: $falhou"
  return 0
}

# Sem a unicidade de id/rev na listagem, a guarda (7) segura sozinha os
# cenarios de duplicata (zero delete, 10 pela guarda); sem as duas, o delete
# aparece.
teste_div167_mutantes_a_guarda_segura_sozinha() {
  local m base ga=$'\xe3\x81\x8c' kad=$'\xe3\x81\x8b\xe3\x82\x99'
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:identidade$/d')
  base=$(_ambiente)
  _listagem "$base" "$(_arq "$ga.tar" 2026-10-05T00:00:00Z 0000000005a),$(_arq "$kad.tar" 2026-10-01T00:00:00Z 0000000005a /bk /Bk ',"x":1')"
  _apagar_ok "$base"
  DBX_T_EXEC=$m _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  assert_igual 0 "$(_deletes "$base")" 'a guarda segura a copia NFD com o mesmo rev'
  assert_igual 10 "$DBX_ESTADO" 'e para com 10'
  base=$(_ambiente)
  _listagem "$base" "$(_arq db-2.tar 2026-10-02T00:00:00Z 0000000002a),{\".tag\":\"file\",\"name\":\"db-1.tar\",\"path_lower\":\"/bk/db-1.tar\",\"path_display\":\"/Bk/db-1.tar\",\"id\":\"id:0000000002a\",\"server_modified\":\"2026-10-01T00:00:00Z\",\"rev\":\"0000000001a\"}"
  _apagar_ok "$base"
  DBX_T_EXEC=$m _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  assert_igual 0 "$(_deletes "$base")" 'a guarda segura o mesmo id'
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:identidade$/d' lib/retencao.sh '/# MUTACAO:identidade_guarda$/d')
  base=$(_ambiente)
  _listagem "$base" "$(_arq "$ga.tar" 2026-10-05T00:00:00Z 0000000005a),$(_arq "$kad.tar" 2026-10-01T00:00:00Z 0000000005a /bk /Bk ',"x":1')"
  _apagar_ok "$base"
  DBX_T_EXEC=$m _rodar "$base" reter /bk --padrao '*.tar' --manter 1 --confirmar
  assert_diferente 0 "$(_deletes "$base")" 'sem as duas barreiras, o delete da copia aparece'
}

# DIV-168: UTF-8 invalido em name ou path_lower, de qualquer entrada.
_qa168() {
  local base b nome
  for b in '\xe0\x8c\x81' '\xc0\x81' '\xcc' '\x81' '\xf8\x88\x80\x80\x80' '\xed\xa0\x80' '\xf5\x80\x80\x80'; do
    printf -v nome 'nota%b.txt' "$b"
    base=$(_ambiente)
    _listagem "$base" "{\".tag\":\"file\",\"name\":\"$nome\",\"path_lower\":\"/bk/$nome\",\"path_display\":\"/Bk/$nome\",\"id\":\"id:n\",\"server_modified\":\"2020-01-01T00:00:00Z\",\"rev\":\"0000000000f\"},$CINCO"
    _apagar_ok "$base"
    DBX_T_EXEC=$1 _rodar "$base" reter /bk --padrao 'db-*.tar' --manter 1 --confirmar
    [[ $DBX_ESTADO -eq 10 && $(_deletes "$base") -eq 0 ]] || { printf '%s' "$b"; return 1; }
  done
  return 0
}

teste_div168_utf8_invalido_derruba_a_listagem() {
  local falhou
  falhou=$(_qa168 "$DBX_EXEC_PADRAO") || _harness_falhar "forma aceita: $falhou"
  return 0
}

teste_div168_mutante_sem_a_validacao_reprova() {
  local m
  m=$(_copia_mutante commands/reter.sh '/# MUTACAO:utf8$/d')
  _qa168 "$m" >/dev/null && _harness_falhar 'sem a validacao de UTF-8, o caso deveria pegar'
  return 0
}

# Os mutantes acima so provam algo se a linha marcada existe: `_copia_mutante`
# roda em substituicao de comando, onde a sua recusa nao reprova o caso.
teste_marcas_de_mutacao_existem() {
  local marca arquivo
  for marca in commands/reter.sh:confirmar commands/reter.sh:simulacao commands/reter.sh:coerencia \
    commands/reter.sh:tag commands/reter.sh:padrao commands/reter.sh:carimbo commands/reter.sh:cursor \
    commands/reter.sh:relogio commands/reter.sh:guarda commands/reter.sh:duplicado \
    commands/reter.sh:normalizado commands/reter.sh:data commands/reter.sh:minusculo lib/retencao.sh:valor \
    lib/retencao.sh:minimo lib/retencao.sh:carimbo lib/retencao.sh:primeiro lib/retencao.sh:unico \
    lib/retencao.sh:fica lib/retencao.sh:unicode lib/retencao.sh:localidade lib/retencao.sh:lista \
    commands/reter.sh:combinante lib/retencao.sh:combinante_guarda lib/retencao.sh:formato \
    commands/reter.sh:identidade lib/retencao.sh:identidade_guarda commands/reter.sh:utf8; do
    arquivo=${marca%%:*}
    grep -q "# MUTACAO:${marca#*:}\$" "$DBX_HARNESS_RAIZ/$arquivo" || _harness_falhar "marca ausente: $marca"
  done
  grep -q ',\\"parent_rev\\":\\"\$rev\\"' "$DBX_HARNESS_RAIZ/commands/reter.sh" || _harness_falhar 'corpo com parent_rev ausente'
  return 0
}

teste_tst09_mapa_de_modulos_tem_as_entradas() {
  local mapa
  IFS= read -r -d '' mapa <"$DBX_HARNESS_RAIZ/docs/testes/mapa-modulos.md" || :
  assert_contem '`lib/retencao.sh`' "$mapa" 'lib/retencao no mapa'
  assert_contem '`commands/reter.sh`' "$mapa" 'commands/reter no mapa'
  assert_contem 'retencao_test' "$mapa" 'teste de unidade no mapa'
  assert_contem 'reter_test' "$mapa" 'teste ponta a ponta no mapa'
}

harness_executar "$@"
