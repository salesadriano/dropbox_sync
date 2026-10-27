#!/usr/bin/env bash
# lib/download_paralelo.sh — recebimento de UM arquivo grande em faixas
# simultaneas (F-100, etapa 2b; RF-180 a RF-184; DIV-369 a DIV-371, DIV-375,
# DIV-376). Carregada por `lib/cmd` so quando ha `--paralelo N > 1` E mais de uma
# faixa a baixar; N=1, arquivo abaixo do limiar e saida padrao nunca chegam aqui.
#
# DESENHO
#   - Faixas de 16 MiB (`DBX_TRANSFER_PARALELO_PARTE`, DIV-371 A) a partir do
#     deslocamento ja gravado no `.part` (o prefixo contiguo, DIV-370 B).
#   - Cada auxiliar (grupo proprio, como o upload da etapa 2a) baixa UMA faixa,
#     por `Range: bytes=a-b`, para um arquivo temporario DELE na area de
#     trabalho, e confere `206`, `Content-Range` exato e a mesma revisao.
#   - O descritor do `.part` (aberto e conferido por `_dbx_cmd_part_abrir`) e do
#     processo principal e so ele grava (DIV-376 B; sem `/dev/fd`): copia as
#     faixas prontas NA ORDEM dos deslocamentos. Como a gravacao e sempre no fim
#     do `.part`, ele nunca tem buracos: tamanho do `.part` = prefixo contiguo
#     (RF-104(c), DIV-369/370), e a retomada continua com `Range: bytes=T-`. O
#     `dd conv=notrunc seek=` do RF-180(b) fica desnecessario: o deslocamento de
#     escrita e sempre o fim.
#   - Janela: faixa nova so e despachada se estiver a menos de N a frente da
#     proxima a gravar; a area de trabalho tem no maximo N x 16 MiB.
#   - Falha definitiva de uma faixa: nada novo e despachado, as em voo terminam,
#     as ja contiguas sao gravadas, e o `.part` e o registro ficam (RF-182(b)).

[[ -n ${DBX_DOWNLOAD_PARALELO_CARREGADO:-} ]] && return 0
DBX_DOWNLOAD_PARALELO_CARREGADO=1

# shellcheck source=lib/transfer_paralelo.sh
. "${BASH_SOURCE[0]%/*}/transfer_paralelo.sh"

_DBX_FAIXAS_PASTA=''
_DBX_FAIXAS_ARG=''
_DBX_FAIXAS_REV=''
_DBX_FAIXAS_TOTAL=0
_DBX_FAIXAS_N=1
_DBX_FAIXAS_FD=''

# _dbx_faixas_banda — DIV-362 A: o teto total dividido por N, nunca abaixo do
# piso de 2 x a velocidade minima.
_dbx_faixas_banda() {
  local total=${_DBX_HTTP_LIMITE_BANDA:-} parte piso
  [[ $total =~ ^[0-9]+$ ]] || return 0
  piso=$((2 * ${DBX_HTTP_EFETIVO[DBX_HTTP_VELOCIDADE_MINIMA_BPS]:-1024}))
  parte=$((total / _DBX_FAIXAS_N))
  ((parte < piso)) && parte=$piso
  dbx_http_limite_banda "$parte"
}

# _dbx_faixas_aux <indice> <inicio> <fim> — corpo do auxiliar: UMA faixa para
# f.<indice>; resultado em r.<indice> (status, classe, faixa_ignorada, `429`,
# codigo, resumo).
_dbx_faixas_aux() {
  local j=$1 a=$2 b=$3 pasta=$_DBX_FAIXAS_PASTA arq status=0 est ignorada='nao' tam antes_429=${DBX_HTTP_LIMITES_429:-0}
  arq="$pasta/f.$j"
  # shellcheck disable=SC2034  # lido por lib/http, no mesmo processo auxiliar
  DBX_HTTP_MARCA_PAUSA="$pasta/p.$j"
  [[ -n $_DBX_FAIXAS_FD ]] && exec {_DBX_FAIXAS_FD}>&-
  _dbx_faixas_banda
  dbx_debug_linha download parte="$j" deslocamento="$a" tamanho=$((b - a + 1))
  dbx_auth_conteudo_receber_faixa GET 'https://content.dropboxapi.com/2/files/download' \
    "$_DBX_FAIXAS_ARG" "$arq" "$a" "$b"
  est=$?
  if [[ $est -eq 0 ]]; then
    _dbx_cmd_resultado_campo rev
    tam=0
    dbx_atributo tamanho "$arq" && tam=$DBX_ATRIBUTO
    # RF-180(a): so a faixa pedida, da mesma revisao, e gravada.
    if [[ ${DBX_HTTP_CODIGO:-0} != '206' || $DBX_CMD_LIDO != "$_DBX_FAIXAS_REV" ||
      ${DBX_HTTP_FAIXA_CABECALHO:-} != "bytes $a-$b/$_DBX_FAIXAS_TOTAL" || $tam != $((b - a + 1)) ]]; then
      status=1 ignorada='sim'
      DBX_HTTP_CLASSE='erro_remoto'
    fi
  else
    status=$est
    ignorada=${DBX_HTTP_FAIXA_IGNORADA:-nao}
  fi
  [[ $status -eq 0 ]] || rm -f -- "$arq"
  dbx_debug_linha download parte="$j" resultado="$([[ $status -eq 0 ]] && echo ok || echo falha)"
  {
    printf '%s\n%s\n%s\n%s\n%s\n' "$status" "${DBX_HTTP_CLASSE:-erro_remoto}" "$ignorada" \
      "$((${DBX_HTTP_LIMITES_429:-0} - antes_429))" "${DBX_HTTP_CODIGO:-0}"
    printf '%s\n' "${DBX_HTTP_RESUMO_DE_ERRO:-}"
  } >"$pasta/r.$j.parcial" && mv -f -- "$pasta/r.$j.parcial" "$pasta/r.$j"
}

# dbx_cmd_baixar_faixas <arg_json> <fd_do_part> <inicio> <total> <n> <rev> <diretorio> <nome> <dev|ino>
#
# Baixa [inicio, total) do `.part` aberto em <fd_do_part>. 0 quando completo;
# senao o codigo da classe da falha, com DBX_HTTP_CLASSE, DBX_HTTP_CODIGO,
# DBX_HTTP_RESUMO_DE_ERRO e DBX_HTTP_FAIXA_IGNORADA como numa requisicao so.
dbx_cmd_baixar_faixas() {
  local argumento=$1 fd=$2 inicio=$3 total=$4 n=$5 rev=$6 diretorio=$7 nome=$8 devino=$9
  local q=$DBX_TRANSFER_PARALELO_PARTE m j a b vivos proximo=0 escrever=0 falhou='nao' pausa='nao' acao_id=''
  local st cl ign l429 cod mo dbg marcada
  local -a est=()
  m=$(((total - inicio + q - 1) / q))
  ((n <= m)) || n=$m
  dbx_tmp_area faixas || {
    DBX_HTTP_CLASSE='configuracao'
    DBX_HTTP_RESUMO_DE_ERRO='area temporaria indisponivel para o recebimento em faixas'
    return "$(dbx_errors_codigo_saida configuracao)"
  }
  _DBX_FAIXAS_PASTA=$DBX_TMP_CAMINHO
  # shellcheck disable=SC2034  # canal alheio esvaziado por quem o leu
  DBX_TMP_CAMINHO=''
  _DBX_FAIXAS_ARG=$argumento _DBX_FAIXAS_REV=$rev _DBX_FAIXAS_TOTAL=$total _DBX_FAIXAS_N=$n _DBX_FAIXAS_FD=$fd
  DBX_HTTP_CLASSE='' DBX_HTTP_CODIGO=0 DBX_HTTP_RESUMO_DE_ERRO='' DBX_HTTP_FAIXA_IGNORADA='nao'
  dbx_debug_linha download paralelo="$n" partes="$m" parte_tamanho="$q"

  _DBX_TRANSFER_PAR_PIDS=()
  dbx_tmp_acao_registrar _dbx_transfer_par_encerrar
  acao_id=$DBX_TMP_ID
  set -m
  while :; do
    vivos=0
    for ((j = escrever; j < proximo; j++)); do [[ ${est[j]:-} == v ]] && vivos=$((vivos + 1)); done
    [[ $pausa == 'sim' && $vivos -eq 0 ]] && pausa='nao'
    # Pausa vigente: algum auxiliar recebeu 429 e ainda nao terminou (DIV-365 A).
    marcada='nao'
    compgen -G "$_DBX_FAIXAS_PASTA/p.*" >/dev/null && marcada='sim'
    if [[ $falhou == 'nao' && $pausa == 'nao' && $marcada == 'nao' ]]; then
      while ((proximo < m && vivos < n && proximo < escrever + n)); do
        a=$((inicio + proximo * q))
        b=$((a + q - 1))
        ((b >= total)) && b=$((total - 1))
        dbg=''
        [[ ${DBX_CLI_DEBUG:-nao} == 'sim' ]] && dbg="$_DBX_FAIXAS_PASTA/dbg.$proximo"
        compgen -G "$_DBX_FAIXAS_PASTA/p.*" >/dev/null && break
        mkdir -m 700 -- "$_DBX_FAIXAS_PASTA/t.$proximo" 2>/dev/null || :
        TMPDIR="$_DBX_FAIXAS_PASTA/t.$proximo" DBX_DEBUG_DESTINO=$dbg _dbx_faixas_aux "$proximo" "$a" "$b" </dev/null >/dev/null 2>&1 &
        _DBX_TRANSFER_PAR_PIDS[proximo]=$!
        est[proximo]=v
        proximo=$((proximo + 1))
        vivos=$((vivos + 1))
      done
    fi
    # Coleta do que terminou.
    for ((j = escrever; j < proximo; j++)); do
      [[ ${est[j]:-} == v ]] || continue
      if [[ ! -e $_DBX_FAIXAS_PASTA/r.$j ]]; then
        if kill -0 "${_DBX_TRANSFER_PAR_PIDS[j]}" 2>/dev/null; then continue; fi
        sleep 0.05
        [[ -e $_DBX_FAIXAS_PASTA/r.$j ]] ||
          printf '1\nnao_concluida\nnao\n0\n0\nauxiliar encerrado sem resultado\n' >"$_DBX_FAIXAS_PASTA/r.$j"
      fi
      st=1 cl='' ign='nao' l429=0 cod=0 mo=''
      {
        IFS= read -r st
        IFS= read -r cl
        IFS= read -r ign
        IFS= read -r l429
        IFS= read -r cod
        IFS= read -r mo
      } <"$_DBX_FAIXAS_PASTA/r.$j"
      rm -f -- "$_DBX_FAIXAS_PASTA/r.$j" "$_DBX_FAIXAS_PASTA/p.$j"
      _DBX_TRANSFER_PAR_PIDS[j]=''
      [[ $l429 =~ ^[0-9]{1,9}$ ]] || l429=0
      if ((l429 > 0)); then
        dbx_debug_somar_429 "$l429"
        pausa='sim'
      fi
      if [[ ${DBX_CLI_DEBUG:-nao} == 'sim' && -s $_DBX_FAIXAS_PASTA/dbg.$j ]]; then
        dbx_debug_descarregar "$_DBX_FAIXAS_PASTA/dbg.$j"
      fi
      if [[ $st == '0' ]]; then
        est[j]=p
      else
        est[j]=f
        if [[ $falhou == 'nao' ]]; then
          falhou='sim'
          DBX_HTTP_CLASSE=${cl:-nao_concluida}
          DBX_HTTP_FAIXA_IGNORADA=$ign
          [[ $cod =~ ^[0-9]{1,3}$ ]] || cod=0
          DBX_HTTP_CODIGO=$cod
          DBX_HTTP_RESUMO_DE_ERRO=$mo
        fi
      fi
    done
    # Gravacao no `.part`, SO pelo descritor do processo principal e na ordem:
    # o prefixo contiguo cresce e nunca ha buraco (DIV-369/370/376).
    while [[ ${est[escrever]:-} == p ]]; do
      if ! dbx_state_retomada_part_barreira "$diretorio" "$nome" "$devino" ||
        ! cat -- "$_DBX_FAIXAS_PASTA/f.$escrever" >&"$fd"; then
        est[escrever]=f
        if [[ $falhou == 'nao' ]]; then
          falhou='sim'
          DBX_HTTP_CLASSE='configuracao'
          DBX_HTTP_RESUMO_DE_ERRO='o arquivo parcial mudou ou nao pode ser gravado'
        fi
        break
      fi
      rm -f -- "$_DBX_FAIXAS_PASTA/f.$escrever"
      est[escrever]=w
      escrever=$((escrever + 1))
    done
    vivos=0
    for ((j = escrever; j < proximo; j++)); do [[ ${est[j]:-} == v ]] && vivos=$((vivos + 1)); done
    if ((vivos == 0)); then
      if ((escrever >= m)) || [[ $falhou == 'sim' ]]; then break; fi
    else
      wait -n 2>/dev/null || sleep 0.05
    fi
  done
  # So os auxiliares: `wait` sem argumento esperaria tambem outros filhos do
  # principal, como o observador de progresso do `.part` (`-p`), que so para
  # depois desta funcao, e o download pendurava em 99%.
  for j in "${!_DBX_TRANSFER_PAR_PIDS[@]}"; do
    [[ -n ${_DBX_TRANSFER_PAR_PIDS[j]} ]] && wait "${_DBX_TRANSFER_PAR_PIDS[j]}" 2>/dev/null
  done
  set +m
  _DBX_TRANSFER_PAR_PIDS=()
  dbx_tmp_acao_cancelar "$acao_id"
  dbx_tmp_remover "$_DBX_FAIXAS_PASTA"
  _DBX_FAIXAS_PASTA='' _DBX_FAIXAS_FD=''
  [[ $falhou == 'sim' ]] && return "$(dbx_errors_codigo_saida "${DBX_HTTP_CLASSE:-nao_concluida}")"
  return 0
}
