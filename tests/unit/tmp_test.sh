#!/usr/bin/env bash
# Testes diretos de lib/tmp.sh — registro unico de areas temporarias e de acoes
# de liberacao, com tratadores compostos (RNF-35, RNF-36; TC-TMP-01..09,
# TC-CNF-01).
#
# Cada caso que precisa de sinal roda um processo PROPRIO (bash -c), com
# TMPDIR privado do caso: a conferencia de residuo nunca olha o `/tmp`
# compartilhado, e o sinal nunca alcanca o executor da suite.
#
# Este arquivo tambem AUDITA `lib/*.sh`, `commands/*.sh` e `bin/dbx` (TC-TMP-01
# e TC-CNF-01): pela Regra 1 do mapa de modulos, entra em todo diff de `lib/`.
#
# shellcheck disable=SC2016,SC2097,SC2098
# Justificativa: os roteiros dos processos filhos chegam sem expansao, e as
# atribuicoes de ambiente repassam ao filho valores do proprio caso.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly TMP_NAO_CONCLUIDA=14

# _base — area do caso com TMPDIR privado; publica BASE.
_base() {
  BASE=$(mktemp -d "$DBX_TESTES_TMP/tmp.XXXXXX")
  mkdir -p "$BASE/tmp"
}

# _rodar <roteiro> [args...] — roda o roteiro num bash proprio, em sessao
# propria, com lib/tmp carregada e TMPDIR privado. Publica TMP_ESTADO e
# TMP_SAIDA (stdout e stderr juntos).
_rodar() {
  local roteiro=$1
  shift
  TMP_SAIDA=$(TMPDIR="$BASE/tmp" BASE="$BASE" RAIZ="$DBX_HARNESS_RAIZ" \
    setsid -w bash -c '. "$RAIZ/lib/tmp.sh" || exit 99
'"$roteiro" _ "$@" 2>&1 </dev/null)
  TMP_ESTADO=$?
}

# _sinalizar_quando <arquivo> <sinal>... — em segundo plano: espera o marcador
# e entrega cada sinal, em ordem, ao processo cujo pid o roteiro gravou em
# `$BASE/pid` (o segundo sinal so depois de `$BASE/liberando`, se houver).
#
# O ROTEIRO RODA EM PRIMEIRO PLANO, e o remetente e que vai para o fundo: job em
# segundo plano de shell nao interativo nasce com INT ignorado, e sinal
# ignorado na entrada nao pode ser tratado. Testar assim mediria o shell, e nao
# lib/tmp.
_sinalizar_quando() {
  local marcador=$1 espera=0 sinal
  shift
  while [[ ! -e $marcador && $espera -lt 400 ]]; do sleep 0.05; espera=$((espera + 1)); done
  for sinal in "$@"; do
    if [[ $sinal == '@liberando' ]]; then
      espera=0
      while [[ ! -e $BASE/liberando && $espera -lt 400 ]]; do sleep 0.05; espera=$((espera + 1)); done
      continue
    fi
    kill "-$sinal" "$(cat "$BASE/pid")" 2>/dev/null
  done
}

# _rodar_e_sinalizar <sinal>... -- <roteiro> — o roteiro grava `$BASE/pid` e
# cria `$BASE/pronto` quando quer o sinal.
_rodar_e_sinalizar() {
  local -a sinais=()
  while [[ $1 != '--' ]]; do sinais+=("$1"); shift; done
  shift
  _sinalizar_quando "$BASE/pronto" "${sinais[@]}" &
  local remetente=$!
  TMP_SAIDA=$(TMPDIR="$BASE/tmp" BASE="$BASE" RAIZ="$DBX_HARNESS_RAIZ" \
    setsid -w bash -c '. "$RAIZ/lib/tmp.sh" || exit 99
printf "%s" "$$" >"$BASE/pid"
'"$1" 2>&1 </dev/null)
  TMP_ESTADO=$?
  wait "$remetente"
}

_residuo() { find "$BASE/tmp" -mindepth 1 -maxdepth 1 -name 'dbx-*' 2>/dev/null; }

# ---------------------------------------------------------------------------
# Area e arquivo temporarios (RNF-35(a)(i), TC-TMP-08, TC-TMP-09)
# ---------------------------------------------------------------------------

teste_area_nasce_0700_com_nome_do_projeto_e_sai_no_termino_normal() {
  _base
  _rodar '
    u=$(umask)
    dbx_tmp_area teste || exit 1
    printf "%s\n" "$DBX_TMP_CAMINHO" >"$BASE/caminho"
    stat -c %a "$DBX_TMP_CAMINHO" >"$BASE/modo"
    [[ $(umask) == "$u" ]] || exit 3
    exit 0'
  assert_igual 0 "$TMP_ESTADO" "umask preservado e criacao ok: $TMP_SAIDA"
  assert_igual 700 "$(cat "$BASE/modo")" 'area 0700'
  assert_contem "$BASE/tmp/dbx-teste." "$(cat "$BASE/caminho")" 'nome dbx-<rotulo>.* sob TMPDIR'
  assert_igual '' "$(_residuo)" 'a area sai no termino normal'
}

teste_termino_normal_preserva_o_codigo_de_saida() {
  # TC-TMP-09.
  _base
  _rodar 'dbx_tmp_area teste || exit 1; exit 11'
  assert_igual 11 "$TMP_ESTADO" 'o codigo original e preservado'
  _rodar 'dbx_tmp_area teste || exit 1; false'
  assert_igual 1 "$TMP_ESTADO" 'o status do ultimo comando e preservado'
  assert_igual '' "$(_residuo)" 'sem residuo'
}

teste_rotulo_fora_do_alfabeto_e_recusado_sem_criar_nada() {
  _base
  _rodar 'dbx_tmp_area "a/../b"; printf "%s" "$?"'
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$TMP_SAIDA" 'rotulo invalido e uso invalido'
  assert_igual '' "$(_residuo)" 'nada criado'
}

teste_arquivo_em_diretorio_dado_e_esquecido_depois_do_mv() {
  _base
  mkdir -p "$BASE/destino"
  _rodar '
    dbx_tmp_arquivo "$BASE/destino/.x.XXXXXXXX" || exit 1
    printf "%s" "$(stat -c %a "$DBX_TMP_CAMINHO")" >"$BASE/modo"
    printf conteudo >"$DBX_TMP_CAMINHO"
    mv -f -- "$DBX_TMP_CAMINHO" "$BASE/destino/final"
    dbx_tmp_esquecer "$DBX_TMP_CAMINHO"
    dbx_tmp_arquivo "$BASE/destino/.y.XXXXXXXX" || exit 1
    exit 0'
  assert_igual 0 "$TMP_ESTADO" "$TMP_SAIDA"
  assert_igual 600 "$(cat "$BASE/modo")" 'arquivo 0600'
  assert_igual conteudo "$(cat "$BASE/destino/final")" 'o arquivo esquecido nao e apagado'
  assert_igual '' "$(find "$BASE/destino" -name '.y.*')" 'o registrado sai no termino'
}

teste_remover_apaga_e_tira_do_registro() {
  _base
  _rodar '
    dbx_tmp_area teste || exit 1
    a=$DBX_TMP_CAMINHO
    dbx_tmp_remover "$a"
    [[ -e $a ]] && exit 4
    mkdir "$a"   # mesmo nome recriado por terceiro: nao e mais nosso
    printf "%s" "$a" >"$BASE/a"
    exit 0'
  assert_igual 0 "$TMP_ESTADO" "$TMP_SAIDA"
  assert_arquivo_existe "$(cat "$BASE/a")" 'removido do registro: o termino nao o apaga de novo'
}

# ---------------------------------------------------------------------------
# Sinais e composicao (RNF-35(b)(d), TC-TMP-02, TC-TMP-03)
# ---------------------------------------------------------------------------

_roteiro_com_duas_acoes='
  a1() { printf "a1:%s\n" "$1" >>"$BASE/ordem"; }
  a2() { printf "a2:%s\n" "$1" >>"$BASE/ordem"; [[ -d $(cat "$BASE/area") ]] && printf "area-viva\n" >>"$BASE/ordem"; }
  dbx_tmp_area teste || exit 1
  printf "%s" "$DBX_TMP_CAMINHO" >"$BASE/area"
  dbx_tmp_acao_registrar a1 primeiro || exit 1
  dbx_tmp_acao_registrar a2 segundo || exit 1
'

teste_sinais_removem_a_area_executam_as_acoes_e_saem_com_14() {
  local sinal
  for sinal in INT TERM HUP; do
    _base
    _rodar_e_sinalizar "$sinal" -- "$_roteiro_com_duas_acoes"'
      : >"$BASE/pronto"
      while :; do sleep 0.05; done'
    assert_igual "$TMP_NAO_CONCLUIDA" "$TMP_ESTADO" "$sinal: operacao nao concluida ($TMP_SAIDA)"
    assert_igual '' "$(_residuo)" "$sinal: nenhuma entrada dbx-* resta"
    assert_igual $'a2:segundo\narea-viva\na1:primeiro' "$(cat "$BASE/ordem")" \
      "$sinal: as duas acoes, em ordem inversa, uma vez cada, antes das areas"
  done
}

teste_termino_normal_executa_as_acoes_em_ordem_inversa() {
  # TC-TMP-03: nenhum tratador sobrescreve o outro.
  _base
  _rodar "$_roteiro_com_duas_acoes"'exit 0'
  assert_igual 0 "$TMP_ESTADO" "$TMP_SAIDA"
  assert_igual $'a2:segundo\narea-viva\na1:primeiro' "$(cat "$BASE/ordem")" 'LIFO, acoes antes das areas'
}

teste_acao_cancelada_nao_executa() {
  _base
  _rodar '
    cancelada() { printf "a1\n" >>"$BASE/ordem"; }
    dbx_tmp_acao_registrar cancelada || exit 1
    dbx_tmp_acao_cancelar "$DBX_TMP_ID"
    exit 0'
  assert_igual 0 "$TMP_ESTADO" "$TMP_SAIDA"
  assert_arquivo_ausente "$BASE/ordem" 'cancelada nao roda'
}

teste_acao_que_nao_e_funcao_e_recusada() {
  # Texto nunca vira acao: so nome de funcao existente.
  _base
  _rodar 'dbx_tmp_acao_registrar "touch $BASE/injetado"; printf "%s" "$?"'
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$TMP_SAIDA" 'recusada'
  assert_arquivo_ausente "$BASE/injetado" 'e nunca executada'
}

teste_sinal_seguido_de_exit_nao_repete_as_acoes() {
  # RNF-35(b): idempotente.
  _base
  _rodar_e_sinalizar TERM -- '
    repetida() { printf "a1\n" >>"$BASE/ordem"; }
    dbx_tmp_acao_registrar repetida || exit 1
    : >"$BASE/pronto"
    while :; do sleep 0.05; done'
  assert_igual "$TMP_NAO_CONCLUIDA" "$TMP_ESTADO" "$TMP_SAIDA"
  assert_igual 'a1' "$(cat "$BASE/ordem")" 'uma vez so'
}

teste_sinal_durante_a_liberacao_nao_interrompe_a_liberacao() {
  # TC-TMP-07 (parte de lib/tmp): o segundo e o terceiro sinal chegam com a
  # primeira acao em curso; as duas acoes terminam, uma vez cada, e a area sai.
  _base
  _rodar_e_sinalizar TERM @liberando TERM INT -- '
    lenta() { : >"$BASE/liberando"; sleep 0.6; printf "lenta\n" >>"$BASE/ordem"; }
    outra() { printf "outra\n" >>"$BASE/ordem"; }
    dbx_tmp_area teste || exit 1
    dbx_tmp_acao_registrar outra || exit 1
    dbx_tmp_acao_registrar lenta || exit 1
    : >"$BASE/pronto"
    while :; do sleep 0.05; done'
  assert_igual "$TMP_NAO_CONCLUIDA" "$TMP_ESTADO" "nao concluida: $TMP_SAIDA"
  assert_igual $'lenta\noutra' "$(cat "$BASE/ordem")" 'as duas acoes, uma vez cada'
  assert_igual '' "$(_residuo)" 'a area sai'
}

teste_subshell_limpa_so_o_que_registrou() {
  # O calculo de resumo roda em subshell: o termino dele nao pode apagar a area
  # nem executar a acao de quem o chamou.
  _base
  _rodar '
    do_pai() { printf "a1\n" >>"$BASE/ordem"; }
    dbx_tmp_area pai || exit 1
    pai=$DBX_TMP_CAMINHO
    dbx_tmp_acao_registrar do_pai || exit 1
    filho=$(dbx_tmp_area filho && printf "%s" "$DBX_TMP_CAMINHO")
    [[ -n $filho && ! -e $filho ]] || exit 5
    [[ -d $pai ]] || exit 6
    [[ ! -e $BASE/ordem ]] || exit 7
    exit 0'
  assert_igual 0 "$TMP_ESTADO" "a area do filho sai com ele, a do pai fica: $TMP_SAIDA"
  assert_igual 'a1' "$(cat "$BASE/ordem")" 'a acao do pai roda uma vez, no termino do pai'
  assert_igual '' "$(_residuo)" 'sem residuo'
}

# ---------------------------------------------------------------------------
# OBS-03: sem janela entre `mktemp` e o registro (RNF-35(e), TC-TMP-04)
# ---------------------------------------------------------------------------

teste_sinal_logo_depois_do_mktemp_nao_deixa_a_area() {
  local sinal real
  real=$(command -v mktemp)
  for sinal in INT TERM HUP; do
    _base
    mkdir -p "$BASE/bin"
    # Dobro: cria de verdade e sinaliza o processo dono ANTES de devolver o nome.
    {
      printf '#!/usr/bin/env bash\n'
      printf 'saida=$(%q "$@") || exit 1\n' "$real"
      printf 'kill -%s "$DBX_TESTE_ALVO"\n' "$sinal"
      printf 'sleep 0.2\n'
      printf 'printf "%%s\\n" "$saida"\n'
    } >"$BASE/bin/mktemp"
    chmod +x "$BASE/bin/mktemp"
    _rodar '
      export DBX_TESTE_ALVO=$$
      PATH="$BASE/bin:$PATH"
      dbx_tmp_area janela
      printf "nao deveria seguir\n"
      exit 0'
    assert_igual "$TMP_NAO_CONCLUIDA" "$TMP_ESTADO" "$sinal: o sinal adiado e entregue ($TMP_SAIDA)"
    assert_nao_contem 'nao deveria seguir' "$TMP_SAIDA" "$sinal: a execucao nao segue"
    assert_igual '' "$(_residuo)" "$sinal: a area criada na janela e removida"
  done
}

# ---------------------------------------------------------------------------
# Auditorias (RNF-35(a)(d), RNF-36; TC-TMP-01, TC-CNF-01)
# ---------------------------------------------------------------------------

# _fora_do_tmp <arquivo...> — linhas de codigo com `mktemp` ou `trap` em posicao
# de comando (ou de captura), comentarios fora.
# Literais entre aspas saem antes (lista de utilitarios e mensagem nao sao
# codigo); o numero da linha fica.
_fora_do_tmp() {
  local arquivo
  for arquivo in "$@"; do
    sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g' "$arquivo" |
      grep -nE '(^|[[:space:];&|({`]|\$\()(mktemp|trap)([[:space:]]|$)' |
      grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|$arquivo:|"
  done
}

teste_nenhum_mktemp_nem_trap_fora_de_lib_tmp() {
  local arquivo
  local -a alvos=()
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh "$DBX_HARNESS_RAIZ"/bin/dbx; do
    [[ ${arquivo##*/} == tmp.sh ]] && continue
    alvos+=("$arquivo")
  done
  assert_igual '' "$(_fora_do_tmp "${alvos[@]}")" 'mktemp ou trap fora de lib/tmp'
}

teste_auditoria_reprova_a_forma_reintroduzida() {
  # Mutacao (RSK-27): cada forma nao obvia, inserida numa copia, e acusada.
  local amostra forma
  _base
  amostra="$BASE/amostra.sh"
  for forma in \
    'area=$(mktemp -d "${TMPDIR:-/tmp}/dbx-x.XXXXXXXX")' \
    '  x=$(umask 077 && mktemp -d "$d")' \
    "  trap '_limpar' EXIT" \
    '  trap - INT TERM HUP' \
    '  [[ -n $a ]] && trap -- "$f" INT' \
    '  mktemp "$dir/.y.XXXX" >"$f"'; do
    printf '%s\n' "$forma" >"$amostra"
    [[ -n $(_fora_do_tmp "$amostra") ]] || _harness_falhar 'forma nao acusada' "$forma"
  done
  for forma in '# trap e mktemp em comentario' '  printf "%s" "mktemp"' '  dbx_tmp_area sync'; do
    printf '%s\n' "$forma" >"$amostra"
    [[ -z $(_fora_do_tmp "$amostra") ]] || _harness_falhar 'forma legitima acusada' "$forma"
  done
  return 0
}

teste_sync_e_verificar_usam_o_mesmo_ciclo_sem_codigo_gemeo() {
  # TC-CNF-01: nenhum dos dois tem area, remocao ou tratador proprio; os dois
  # chamam a mesma funcao compartilhada de inicio do ciclo.
  local arquivo
  for arquivo in sync verificar; do
    assert_igual '' "$(grep -nE '_AREA=|rm -rf|_interrompid|_encerrar_area' \
      "$DBX_HARNESS_RAIZ/commands/$arquivo.sh" | grep -vE '^[0-9]+:[[:space:]]*#')" \
      "$arquivo: sem area, remocao ou tratador proprio"
    assert_contem 'dbx_cmd_ciclo_iniciar' "$(cat "$DBX_HARNESS_RAIZ/commands/$arquivo.sh")" \
      "$arquivo: usa o ciclo compartilhado"
  done
  # Mutacao: devolver um `mktemp` ao verificar reprova a auditoria de TC-TMP-01.
  _base
  cp "$DBX_HARNESS_RAIZ/commands/verificar.sh" "$BASE/verificar.sh"
  printf '%s\n' '  DBX_CMD_VERIFICAR_AREA=$(mktemp -d "${TMPDIR:-/tmp}/dbx-sync.XXXXXXXX")' >>"$BASE/verificar.sh"
  [[ -n $(_fora_do_tmp "$BASE/verificar.sh") ]] || _harness_falhar 'mutacao no verificar nao acusada'
  return 0
}

harness_executar "$@"
