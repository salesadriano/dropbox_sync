#!/usr/bin/env bash
# Bancada de medicao de desempenho do dbx (fase 9, F-34): gera volume local deterministico, mede
# envio, reenvio sem mudancas (caminho do skip) e recebimento, e limpa a pasta remota de teste.
#
# Uso:
#   bash scripts/bancada.sh gerar  <dir> [--semente N]
#   bash scripts/bancada.sh medir  <dir> --remoto /dbx-bancada-<sufixo> --saida <arquivo> \
#        --confirmo-conta-real [-- <opcoes extras do dbx sync>]
#   bash scripts/bancada.sh limpar --remoto /dbx-bancada-<sufixo>
#
# Volume padrao (3 niveis de pasta): 1000 arquivos de 1-50 KB, 50 de 1-5 MB e 2 de 100 MB.
# Ajustaveis por ambiente (usado pelos testes): BANCADA_PEQUENOS, BANCADA_MEDIOS, BANCADA_GRANDES,
# BANCADA_GRANDE_MB. Mesma semente = mesmos nomes e bytes.
# `medir` fala com a conta REAL: so roda com --confirmo-conta-real. Chamadas HTTP e respostas 429 sao
# contadas por um shim de `curl` no PATH (lib/http.sh nao expoe contagem); cada tentativa conta.
# Pasta remota (RF-138(b)): `medir` recusa pasta que ja existe sem o marcador `.bancada-marcador`, cria a
# pasta com o marcador e so `limpar` apaga se o marcador estiver la. O trap de EXIT/INT/TERM do `medir`
# apaga a pasta remota (validada pelo padrao) e o volume local (so se `<dir>.marcador` existir, criado por
# `gerar`); se a limpeza falhar, sai nao zero e imprime o caminho remanescente (RF-138(f)).
# A saida de cada etapa (stdout+stderr, sem segredo) fica em `<saida>.<etapa>.log`; etapa com status
# diferente de 0 faz o `medir` sair 1 apontando o log. Etapas: envio, reenvio_sem_mudancas, recebimento e
# reter (`dbx reter` sobre uma subpasta, `--manter 1` dos `pequeno-*`, apaga um subconjunto deterministico).
# Saida (TSV, uma linha por etapa): etapa, segundos, chamadas, http_429, status, remoto.
# DBX_BIN troca o executavel do dbx. Saida: 0 ok; 1 falha; 2 uso invalido (antes de qualquer rede).

set -eu

RAIZ=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DBX_BIN=${DBX_BIN:-$RAIZ/bin/dbx}
PADRAO_REMOTO='^/dbx-bancada-[a-z0-9-]+$'
MARCADOR='.bancada-marcador'
NAO_ENCONTRADO=4

uso() { printf 'uso: bancada.sh gerar|medir|limpar ... (ver cabecalho do script)\n' >&2; exit 2; }
recusar() { printf 'bancada: %s\n' "$1" >&2; exit 2; }

validar_remoto() {
  [[ ${1-} =~ $PADRAO_REMOTO ]] || recusar "remoto fora do padrao ^/dbx-bancada-[a-z0-9-]+\$: '${1-}'"
}

TEMPORARIOS=()
limpar_temporarios() {
  local t
  for t in "${TEMPORARIOS[@]:+${TEMPORARIOS[@]}}"; do rm -rf -- "$t"; done
}
LIMPAR_REMOTO=''
LIMPAR_LOCAL=''
# Encerramento unico (EXIT/INT/TERM): temporarios, pasta remota e volume local. Falha de limpeza = nao zero.
encerrar() {
  local rc=${1:-$?}
  trap - EXIT INT TERM
  set +e
  limpar_temporarios
  if [[ -n $LIMPAR_REMOTO ]]; then
    validar_remoto "$LIMPAR_REMOTO"
    if ! "$DBX_BIN" delete "$LIMPAR_REMOTO" --yes >/dev/null 2>&1; then
      printf 'bancada: limpeza falhou; remanescente remoto: %s\n' "$LIMPAR_REMOTO" >&2
      [[ $rc -ne 0 ]] || rc=1
    fi
  fi
  if [[ -n $LIMPAR_LOCAL && -f $LIMPAR_LOCAL.marcador ]]; then
    if ! rm -rf -- "$LIMPAR_LOCAL" "$LIMPAR_LOCAL.marcador" || [[ -e $LIMPAR_LOCAL ]]; then
      printf 'bancada: limpeza falhou; remanescente local: %s\n' "$LIMPAR_LOCAL" >&2
      [[ $rc -ne 0 ]] || rc=1
    fi
  fi
  exit "$rc"
}
trap 'encerrar' EXIT
trap 'encerrar 130' INT
trap 'encerrar 143' TERM

# Existencia da pasta remota: 0 existe com marcador; 1 nao existe; 2 existe sem marcador; 3 erro.
estado_da_pasta() {
  local remoto=$1 saida st=0
  saida=$("$DBX_BIN" list "$remoto" 2>&1) || st=$?
  if [[ $st -eq 0 ]]; then
    [[ $saida == *"$MARCADOR"* ]] && return 0
    return 2
  fi
  [[ $st -eq $NAO_ENCONTRADO ]] && return 1
  return 3
}

# Escreve $2 bytes deterministicos (chave derivada de semente e nome) em $1.
escrever() {
  local alvo=$1 bytes=$2 chave
  chave=$(printf "%s" "$SEMENTE:${alvo#"$BASE"/}" | sha256sum | cut -c1-32)
  head -c "$bytes" /dev/zero | openssl enc -aes-128-ctr -K "$chave" -iv 00000000000000000000000000000000 -out "$alvo"
}

caminho_do() { # indice -> d1/d2/d3 (3 niveis)
  printf 'n1-%d/n2-%d/n3-%d' $(($1 % 4)) $(($1 / 4 % 3)) $(($1 / 12 % 2))
}

cmd_gerar() {
  local dir=${1-} i d bytes
  [[ -n $dir ]] || uso
  shift
  SEMENTE=42
  while [[ $# -gt 0 ]]; do
    case $1 in
      --semente) SEMENTE=${2-}; shift 2 ;;
      *) uso ;;
    esac
  done
  [[ $SEMENTE =~ ^[0-9]+$ ]] || recusar 'semente deve ser inteira'
  local np=${BANCADA_PEQUENOS:-1000} nm=${BANCADA_MEDIOS:-50} ng=${BANCADA_GRANDES:-2} gmb=${BANCADA_GRANDE_MB:-100}
  BASE=$dir
  mkdir -p "$dir"
  printf 'dbx-bancada\n' >"$dir.marcador"
  RANDOM=$SEMENTE
  for ((i = 0; i < np; i++)); do
    d=$dir/$(caminho_do "$i"); mkdir -p "$d"
    bytes=$((1024 + RANDOM % 49153))
    escrever "$d/pequeno-$i.bin" "$bytes"
  done
  for ((i = 0; i < nm; i++)); do
    d=$dir/$(caminho_do "$i"); mkdir -p "$d"
    bytes=$((1048576 + (RANDOM * 32768 + RANDOM) % 4194305))
    escrever "$d/medio-$i.bin" "$bytes"
  done
  for ((i = 0; i < ng; i++)); do
    d=$dir/$(caminho_do "$i"); mkdir -p "$d"
    escrever "$d/grande-$i.bin" $((gmb * 1048576))
  done
}

# Shim de curl: repassa stdin/args ao curl real e registra uma linha por tentativa com o codigo HTTP.
criar_shim() {
  local shimdir=$1 real
  real=$(command -v curl) || recusar 'curl ausente'
  cat >"$shimdir/curl" <<SHIM
#!/usr/bin/env bash
saida=\$(mktemp); rc=0
"$real" "\$@" >"\$saida" || rc=\$?
cat "\$saida"
codigo=\$(tail -c 3 "\$saida")
case \$codigo in [0-9][0-9][0-9]) ;; *) codigo=000 ;; esac
printf '%s\n' "\$codigo" >>"\$BANCADA_LOG_HTTP"
rm -f "\$saida"
exit \$rc
SHIM
  chmod +x "$shimdir/curl"
}

cmd_medir() {
  local dir=${1-} remoto='' saida='' confirmo=nao
  [[ -n $dir ]] || uso
  shift
  local extras=()
  while [[ $# -gt 0 ]]; do
    case $1 in
      --remoto) remoto=${2-}; shift 2 ;;
      --saida) saida=${2-}; shift 2 ;;
      --confirmo-conta-real) confirmo=sim; shift ;;
      --) shift; extras=("$@"); break ;;
      *) uso ;;
    esac
  done
  validar_remoto "$remoto"
  [[ $confirmo = sim ]] || recusar 'medir usa a conta real: exige --confirmo-conta-real'
  [[ -n $saida ]] || recusar '--saida e obrigatorio'
  [[ -d $dir ]] || recusar "diretorio de volume inexistente: $dir"

  local work shimdir recv st=0 falhas=0
  work=$(mktemp -d); TEMPORARIOS+=("$work")
  shimdir=$work/shim; mkdir -p "$shimdir"; recv=$work/recebido; mkdir -p "$recv"
  criar_shim "$shimdir"
  export BANCADA_LOG_HTTP=$work/http.log
  : >"$BANCADA_LOG_HTTP"
  : >"$saida"

  # RF-138(b): recusa pasta existente sem marcador; cria com marcador. O que sera apagado e registrado
  # para o trap ANTES de criar, para que uma falha no meio nao deixe a pasta.
  estado_da_pasta "$remoto" || st=$?
  case $st in
    0) ;;
    2) recusar "a pasta remota $remoto ja existe sem o marcador $MARCADOR: nao e uma pasta da bancada" ;;
    1)
      printf 'dbx-bancada\n' >"$work/$MARCADOR"
      LIMPAR_REMOTO=$remoto
      LIMPAR_LOCAL=$dir
      "$DBX_BIN" upload "$work/$MARCADOR" "$remoto/$MARCADOR" >/dev/null 2>&1 ||
        { printf 'bancada: nao foi possivel criar a pasta %s com o marcador\n' "$remoto" >&2; exit 1; }
      ;;
    *) printf 'bancada: nao foi possivel consultar a pasta %s\n' "$remoto" >&2; exit 1 ;;
  esac
  LIMPAR_REMOTO=$remoto
  LIMPAR_LOCAL=$dir

  # etapa <nome> <comando do dbx> <args...>; extras so no `sync`.
  etapa() {
    local nome=$1 comando=$2 ini fim st=0 antes c n429 log
    shift 2
    antes=$(wc -l <"$BANCADA_LOG_HTTP")
    ini=$(date +%s.%N)
    if [[ $comando == sync ]]; then
      PATH="$shimdir:$PATH" "$DBX_BIN" sync "$@" ${extras[@]:+"${extras[@]}"} >"$work/$nome.out" 2>&1 || st=$?
    else
      PATH="$shimdir:$PATH" "$DBX_BIN" "$comando" "$@" >"$work/$nome.out" 2>&1 || st=$?
    fi
    fim=$(date +%s.%N)
    c=$(($(wc -l <"$BANCADA_LOG_HTTP") - antes))
    n429=$(tail -n +"$((antes + 1))" "$BANCADA_LOG_HTTP" | grep -c '^429$' || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$nome" "$(awk -v a="$ini" -v b="$fim" 'BEGIN{printf "%.3f", b-a}')" \
      "$c" "$n429" "$st" "$remoto" >>"$saida"
    # RF-138: a saida da etapa sobrevive ao trap, redigida (RNF-03).
    log="$saida.$nome.log"
    # QA-B9-01: Basic em base64 e chaves de credencial (com ou sem aspas) tambem saem redigidas.
    sed -E 's/sl\.[A-Za-z0-9_.-]{8,}/[REDIGIDO]/g
      s/([Aa]uthorization:?)[ =]+([Bb]asic|[Bb]earer)[ ]+[^ ]+/\1 \2 [REDIGIDO]/g
      s/([Bb]earer|[Aa]uthorization:?)[ =]+([^ B][^ ]*|B[^ae][^ ]*)/\1 [REDIGIDO]/g
      s/((refresh_token|access_token|app_secret|app_key|client_secret|client_id|code)"?[ ]*[=:][ ]*"?)[^"&, ]+/\1[REDIGIDO]/g' \
      "$work/$nome.out" >"$log"
    if [[ $st -ne 0 ]]; then
      printf 'bancada: etapa %s saiu com status %s; ver %s\n' "$nome" "$st" "$log" >&2
      falhas=$((falhas + 1))
    fi
    return 0
  }
  etapa envio sync --enviar --origem "$dir" --destino "$remoto"
  etapa reenvio_sem_mudancas sync --enviar --origem "$dir" --destino "$remoto"
  etapa recebimento sync --receber --origem "$remoto" --destino "$recv"
  # Subconjunto deterministico: dos `pequeno-*` de uma subpasta, fica so o mais novo (empate: o nome).
  etapa reter reter "$remoto/n1-0/n2-0/n3-0" --padrao 'pequeno-*.bin' --manter 1 --confirmar
  [[ $falhas -eq 0 ]] || exit 1
}

cmd_limpar() {
  local remoto=''
  while [[ $# -gt 0 ]]; do
    case $1 in
      --remoto) remoto=${2-}; shift 2 ;;
      *) uso ;;
    esac
  done
  validar_remoto "$remoto"
  local st=0
  estado_da_pasta "$remoto" || st=$?
  case $st in
    0) "$DBX_BIN" delete "$remoto" --yes ;;
    1) printf 'bancada: %s nao existe; nada a limpar\n' "$remoto" >&2 ;;
    2) recusar "a pasta remota $remoto existe sem o marcador $MARCADOR: nao e uma pasta da bancada; nada foi apagado" ;;
    *) printf 'bancada: nao foi possivel consultar a pasta %s\n' "$remoto" >&2; exit 1 ;;
  esac
}

[[ $# -ge 1 ]] || uso
sub=$1; shift
case $sub in
  gerar) cmd_gerar "$@" ;;
  medir) cmd_medir "$@" ;;
  limpar) cmd_limpar "$@" ;;
  *) uso ;;
esac
