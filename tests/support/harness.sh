#!/usr/bin/env bash
# harness.sh — arcabouco minimo de teste para shell, com saida em formato TAP 13.
#
# Motivo de existir: `bats` e `shunit2` nao estao instalados neste ambiente e a
# instalacao de pacotes exige sinalizacao previa ao solicitante. O formato de
# saida adotado e TAP 13 justamente para que a troca por `bats` no futuro nao
# altere o contrato de relatorio consumido pelo QA.
#
# Uso em um arquivo de teste:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/../support/harness.sh"
#   teste_algum_comportamento() { assert_igual esperado obtido "descricao"; }
#   harness_executar "$@"
#
# Cada funcao com prefixo `teste_` e executada em subshell proprio, o que impede
# vazamento de estado entre casos.

set -u

DBX_HARNESS_RAIZ=${DBX_HARNESS_RAIZ:-$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}
export DBX_HARNESS_RAIZ

# Executar um arquivo de teste isoladamente, sem o ambiente que o executor
# monta, fazia casos reprovarem por falta de area temporaria — diagnostico
# enganoso, que chega a sugerir que o executor mascara falhas. A recusa e
# explicita e imediata: falha clara em vez de resultado que engana.
if [[ -z ${DBX_TESTES_TMP:-} ]]; then
  printf 'Este arquivo de teste precisa do ambiente montado pelo executor.\n' >&2
  printf 'Use: bash tests/run.sh [filtro]\n' >&2
  printf 'Motivo: DBX_TESTES_TMP nao esta definida.\n' >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Assercoes. Toda assercao que falha encerra o caso de teste corrente.
# ---------------------------------------------------------------------------

_harness_falhar() {
  printf '# FALHA: %s\n' "$1" >&2
  shift
  local linha
  for linha in "$@"; do
    printf '#   %s\n' "$linha" >&2
  done
  exit 1
}

assert_igual() {
  local esperado=$1 obtido=$2 descricao=${3:-valores devem ser iguais}
  [[ $esperado == "$obtido" ]] && return 0
  _harness_falhar "$descricao" "esperado: [$esperado]" "obtido:   [$obtido]"
}

assert_diferente() {
  local proibido=$1 obtido=$2 descricao=${3:-valores devem ser diferentes}
  [[ $proibido != "$obtido" ]] && return 0
  _harness_falhar "$descricao" "valor proibido foi obtido: [$obtido]"
}

assert_contem() {
  local agulha=$1 palheiro=$2 descricao=${3:-texto deve conter trecho}
  [[ $palheiro == *"$agulha"* ]] && return 0
  _harness_falhar "$descricao" "trecho ausente: [$agulha]" "texto:          [$palheiro]"
}

assert_nao_contem() {
  local agulha=$1 palheiro=$2 descricao=${3:-texto nao deve conter trecho}
  [[ $palheiro != *"$agulha"* ]] && return 0
  _harness_falhar "$descricao" "trecho proibido presente: [$agulha]" "texto: [$palheiro]"
}

# assert_segredo_ausente <segredo> <palheiro> [descricao]
#
# Prova que um segredo NAO aparece num texto, sem nunca imprimir o segredo.
#
# As assercoes comuns imprimem o valor comparado para diagnosticar, e desde que
# o diario grava esse diagnostico em disco, `assert_nao_contem <segredo> ...`
# passou a ser ela propria um vetor: a assercao usada para provar que o segredo
# nao vaza imprime a agulha exatamente quando falha, ou seja, exatamente quando
# ha algo a registrar.
#
# A mascara e feita por substituicao da agulha LITERAL, nao por redacao. A
# redacao de `lib/errors.sh` reconhece FORMAS (prefixo `sl.`, chave sensivel
# com `=` ou `:`) e por construcao nao alcanca um valor cru sem forma
# reconhecivel — que e justamente o formato de um segredo fabricado num teste.
# Substituir a agulha garante zero ocorrencias na saida seja qual for a forma.
#
# O que fica no lugar do segredo e o que permite diagnosticar: posicao da
# primeira ocorrencia, comprimento, quantidade de ocorrencias e o texto inteiro
# com as ocorrencias marcadas. Omitir tambem o contexto produziria mensagem
# inutil — o defeito equivalente ao vazamento, ja observado no diario.
#
# Nota: comprimento e posicao sao informacao sobre o segredo. Em teste, onde o
# segredo e fabricado e a suite nunca detem credencial real (RNF-14), isso e
# diagnostico; nao use esta assercao para comparar credencial de producao.
assert_segredo_ausente() {
  local agulha=$1 palheiro=$2 descricao=${3:-segredo nao pode aparecer no texto}
  # Agulha vazia casaria com qualquer texto e faria a assercao reprovar sempre,
  # ou — pior, se a comparacao fosse invertida — aprovar sempre sem verificar
  # nada. Recusa explicita em vez de resultado sem significado.
  [[ -n $agulha ]] ||
    _harness_falhar "$descricao" 'agulha de tamanho vazio: a assercao seria vacua e foi recusada'
  [[ $palheiro != *"$agulha"* ]] && return 0

  local prefixo=${palheiro%%"$agulha"*}
  local mascarado=${palheiro//"$agulha"/[SEGREDO]}
  # A parada e estrutural, e nao depende da recusa acima ter encerrado o caso:
  # se a remocao do prefixo nao encurtar `resto`, o laco para. Sem isso, uma
  # `_harness_falhar` que deixasse de encerrar o caso faria a execucao cair aqui
  # com agulha vazia e girar para sempre — medido, a suite travava. Falha de
  # teste tem de virar reprovacao, nunca pendura da execucao.
  local resto=$palheiro anterior ocorrencias=0
  while [[ $resto == *"$agulha"* ]]; do
    anterior=$resto
    resto=${resto#*"$agulha"}
    [[ $resto == "$anterior" ]] && break
    ocorrencias=$((ocorrencias + 1))
  done

  _harness_falhar "$descricao" \
    'segredo encontrado no texto; o valor e omitido de proposito' \
    "posicao: ${#prefixo}" \
    "comprimento: ${#agulha}" \
    "ocorrencias: $ocorrencias" \
    "texto mascarado: [$mascarado]"
}

# assert_status <esperado> <comando...>
#
# A saida e desviada para arquivo, e NAO capturada com `$( )`. Substituicao de
# comando cria subshell, o que impede testar funcao que mantenha estado global
# e mascara defeitos de obsolescencia de estado — foi o que escondeu E2-09.
assert_status() {
  local esperado=$1
  shift
  local saida obtido arquivo
  arquivo="${DBX_TESTES_TMP:-${TMPDIR:-/tmp}}/dbx-assert.$$"
  "$@" >"$arquivo" 2>&1
  obtido=$?
  saida=$(cat "$arquivo" 2>/dev/null)
  rm -f "$arquivo"
  [[ $esperado == "$obtido" ]] && return 0
  _harness_falhar "status de saida divergente ao executar: $*" \
    "esperado: $esperado" "obtido:   $obtido" "saida:    ${saida//$'\n'/ | }"
}

assert_sucesso() { assert_status 0 "$@"; }

assert_arquivo_existe() {
  local caminho=$1 descricao=${2:-arquivo deve existir}
  [[ -e $caminho ]] && return 0
  _harness_falhar "$descricao" "caminho ausente: [$caminho]"
}

assert_arquivo_ausente() {
  local caminho=$1 descricao=${2:-arquivo nao deve existir}
  [[ ! -e $caminho ]] && return 0
  _harness_falhar "$descricao" "caminho presente indevidamente: [$caminho]"
}

# _dbx_estado_da_maquina — instantaneo do host, so com recursos internos do
# shell. Ler `/proc` por redirecionamento evita introduzir dependencia de
# utilitario externo que teria de passar pelo preflight.
_dbx_estado_da_maquina() {
  local carga='desconhecida' memoria='desconhecida' processadores=0 campo valor
  [[ -r /proc/loadavg ]] && read -r carga </proc/loadavg
  if [[ -r /proc/meminfo ]]; then
    while read -r campo valor _; do
      [[ $campo == 'MemAvailable:' ]] && {
        memoria=$valor
        break
      }
    done </proc/meminfo
  fi
  if [[ -r /proc/cpuinfo ]]; then
    while read -r campo _; do
      [[ $campo == 'processor' ]] && processadores=$((processadores + 1))
    done </proc/cpuinfo
  fi
  printf 'processadores=%s memoria_disponivel_kB=%s carga=[%s]' \
    "$processadores" "$memoria" "$carga"
}

# _agora_ms — relogio monotonico em milissegundos, para medir custo relativo.
_agora_ms() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local partes=${EPOCHREALTIME/,/.}
    printf '%s' "$(((${partes%.*} * 1000) + (10#${partes#*.} / 1000)))"
    return 0
  fi
  printf '%s' "$((SECONDS * 1000))"
}

# _medir_minimo_ms <repeticoes> <comando...> — menor tempo observado.
#
# Instrumento para verificar COMPLEXIDADE ALGORITMICA, propriedade que por
# definicao nao depende da carga da maquina — mas que era medida por um proxy,
# tempo de parede, que depende. Sob contencao, uma medicao isolada infla
# arbitrariamente, e a razao entre duas medicoes dispara sem que o algoritmo
# tenha mudado. Agravante: nos casos afetados a medicao maior vem sempre depois,
# entao carga que chegue durante a execucao penaliza sempre o mesmo lado.
#
# O minimo e robusto porque contencao so pode SOMAR tempo, nunca subtrair: com
# repeticoes suficientes, o menor valor converge para o custo real, e a razao
# entre minimos fica insensivel a carga.
#
# Alternativas avaliadas e descartadas, com evidencia:
#   - tempo de CPU pelo `times` do shell: mediria desescalonamento corretamente,
#     mas devolve zero para trabalho em processo neste `bash`, o que o torna
#     inutilizavel aqui;
#   - contagem de operacoes: mediria a complexidade diretamente, sem proxy, mas
#     o custo destes casos esta DENTRO de primitivas do shell — fatiamento e
#     concatenacao de cadeia — e nao e contavel no nivel do script.
_medir_minimo_ms() {
  local repeticoes=$1
  shift
  local indice inicio fim atual minimo=''
  for ((indice = 0; indice < repeticoes; indice++)); do
    inicio=$(_agora_ms)
    "$@" >/dev/null 2>&1
    fim=$(_agora_ms)
    atual=$((fim - inicio))
    [[ -z $minimo || $atual -lt $minimo ]] && minimo=$atual
  done
  [[ $minimo -lt 1 ]] && minimo=1
  printf '%s' "$minimo"
}

# pular <motivo> — marca o caso como nao executado, sem falhar a suite.
pular() {
  printf '%s\n' "${1:-sem motivo declarado}" >"${DBX_HARNESS_ARQ_PULAR:-/dev/null}"
  exit 77
}

# ---------------------------------------------------------------------------
# Execucao
# ---------------------------------------------------------------------------

# _harness_registrar_reprovacao <caso> <status> <estado_inicial> <arquivo_saida>
#
# Grava o diagnostico em ARQUIVO que sobrevive a execucao, e nao apenas na saida
# padrao. Uma reprovacao intermitente so e diagnosticavel se, no momento em que
# ocorre, ficarem registrados o caso, os valores medidos e o estado do host —
# sem depender de alguem lembrar depois o que estava rodando na maquina.
_harness_registrar_reprovacao() {
  local caso=$1 status=$2 estado_inicial=$3 arquivo_saida=$4 linha
  local diario=${DBX_HARNESS_DIARIO:-}
  [[ -n $diario ]] || return 0
  # A taxonomia de redacao e carregada aqui se ainda nao estiver: sem ela o
  # recuo apagaria o diagnostico inteiro, que e o defeito equivalente ao
  # vazamento — diario ilegivel nao diagnostica nada.
  if ! declare -F dbx_errors_redigir >/dev/null; then
    # shellcheck source=lib/errors.sh
    . "$DBX_HARNESS_RAIZ/lib/errors.sh" 2>/dev/null || return 0
  fi
  {
    printf '=== reprovacao ===\n'
    printf 'caso: %s\n' "$caso"
    printf 'arquivo: %s\n' "${DBX_HARNESS_ARQUIVO:-desconhecido}"
    printf 'momento: %s\n' "${EPOCHREALTIME:-$SECONDS}"
    printf 'status: %s\n' "$status"
    printf 'host_no_inicio: %s\n' "$estado_inicial"
    printf 'host_na_falha:  %s\n' "$(_dbx_estado_da_maquina)"
    printf 'diagnostico do caso:\n'
    # A saida do caso vai para ARQUIVO PERSISTENTE, entao passa pela redacao
    # antes de ser gravada. Uma assercao que falhe comparando credencial imprime
    # o valor comparado, e sem isso o diario — instituido para diagnosticar
    # intermitencia — viraria um deposito de segredo em disco. Verificado: sem a
    # redacao, um `refresh_token` de teste chegava integro ao arquivo.
    while IFS= read -r linha; do
      dbx_errors_redigir "$linha" >/dev/null
      printf '  %s\n' "$DBX_ERRORS_REDIGIDO"
    done <"$arquivo_saida"
    printf '\n'
  } >>"$diario" 2>/dev/null
  return 0
}

harness_executar() {
  local filtro=${1:-}
  local -a casos=()
  local nome
  while IFS= read -r nome; do
    casos+=("$nome")
  done < <(declare -F | awk '{print $3}' | grep '^teste_' | sort)

  if [[ -n $filtro ]]; then
    local -a filtrados=()
    for nome in "${casos[@]}"; do
      [[ $nome == *"$filtro"* ]] && filtrados+=("$nome")
    done
    casos=("${filtrados[@]:-}")
    [[ -z ${casos[0]:-} ]] && casos=()
  fi

  local total=${#casos[@]}
  printf 'TAP version 13\n'
  printf '1..%d\n' "$total"

  # Filtro que nao corresponde a nenhum caso REPROVA. Aprovar sem executar nada
  # faz um job de integracao com nome errado passar verde — a mesma falha que o
  # executor tinha, um nivel abaixo e alcancavel por invocacao direta.
  if [[ $total -eq 0 ]]; then
    if [[ -n $filtro ]]; then
      printf '# FALHA: o filtro "%s" nao corresponde a nenhum caso deste arquivo\n' "$filtro" >&2
    else
      printf '# FALHA: nenhum caso de teste encontrado neste arquivo\n' >&2
    fi
    printf '# resumo ok=0 nao_ok=1 pulados=0\n'
    [[ -n ${DBX_HARNESS_RESUMO:-} ]] && printf '0 1 0\n' >"$DBX_HARNESS_RESUMO"
    return 1
  fi

  # Estado do host ANTES de executar. Colher apenas apos a reprovacao mediria o
  # estado pos-falha, que pode diferir do estado durante — e o instrumento
  # voltaria a interferir no observado. Os dois instantaneos juntos dizem o que
  # nenhum diz sozinho.
  local estado_inicial
  estado_inicial=$(_dbx_estado_da_maquina)

  local indice=0 ok=0 nao_ok=0 pulados=0 status motivo saida_do_caso linha
  # Area controlada da suite, e nao `mktemp` puro: um temporario fora de
  # $DBX_TESTES_TMP escapa da limpeza do executor.
  DBX_HARNESS_ARQ_PULAR=$(mktemp "${DBX_TESTES_TMP:-${TMPDIR:-/tmp}}/dbx-harness.XXXXXX") || return 1
  export DBX_HARNESS_ARQ_PULAR
  trap 'rm -f "$DBX_HARNESS_ARQ_PULAR"' EXIT

  saida_do_caso="${DBX_TESTES_TMP:-${TMPDIR:-/tmp}}/dbx-caso.$$"

  for nome in "${casos[@]}"; do
    indice=$((indice + 1))
    : >"$DBX_HARNESS_ARQ_PULAR"
    # A saida do caso e desviada para arquivo e reemitida em seguida: sem isso
    # as linhas de diagnostico so existiriam no terminal, que rola e se perde —
    # foi exatamente o que aconteceu com a reprovacao sem causa estabelecida.
    (
      set -u
      if declare -F preparar_caso >/dev/null; then preparar_caso; fi
      "$nome"
    ) 2>"$saida_do_caso"
    status=$?
    while IFS= read -r linha; do printf '%s\n' "$linha" >&2; done <"$saida_do_caso"
    case $status in
      0)
        ok=$((ok + 1))
        printf 'ok %d - %s\n' "$indice" "${nome#teste_}"
        ;;
      77)
        pulados=$((pulados + 1))
        motivo=$(cat "$DBX_HARNESS_ARQ_PULAR" 2>/dev/null)
        printf 'ok %d - %s # SKIP %s\n' "$indice" "${nome#teste_}" "$motivo"
        ;;
      *)
        nao_ok=$((nao_ok + 1))
        printf 'not ok %d - %s\n' "$indice" "${nome#teste_}"
        _harness_registrar_reprovacao "$nome" "$status" "$estado_inicial" "$saida_do_caso"
        ;;
    esac
  done

  # A linha abaixo e informativa, destinada a leitura humana. Ela NAO e a fonte
  # do agregado: o executor le os totais de $DBX_HARNESS_RESUMO, um canal
  # separado da saida padrao dos testes. Sem essa separacao, o agregado seria
  # apenas texto que os proprios testes emitem, e portanto forjavel.
  printf '# resumo ok=%d nao_ok=%d pulados=%d\n' "$ok" "$nao_ok" "$pulados"
  if [[ -n ${DBX_HARNESS_RESUMO:-} ]]; then
    printf '%d %d %d\n' "$ok" "$nao_ok" "$pulados" >"$DBX_HARNESS_RESUMO"
  fi
  [[ $nao_ok -eq 0 ]]
}
