#!/usr/bin/env bash
# Testes do registro de retomada em lib/state.sh (fase 7a, F-03; RF-101, RF-105,
# RF-107 e a emenda C3 de RF-61; TC-RME-01, 03..11, 13; TC-UPC-13; TC-RMC-02,
# 03; TC-RML-01..04; parecer do DBA, C1 a C6).
#
# O ESTADO SO ACELERA. Cada caso de descarte prova as duas metades da regra:
# registro que nao serve sai (e so ele), e o chamador recebe "ausente" e nunca
# uma falha. O `.part` de um registro so e apagado pela barreira de identidade
# (dono, regular, mesmo dispositivo e inode, padrao de nome, diretorio do alvo).
#
# Cada caso roda os roteiros num `bash` proprio com lib/state carregada e com
# `XDG_STATE_HOME` e `TMPDIR` privados (`_filho`, como em state_trava_test).
#
# shellcheck disable=SC2016,SC2097,SC2098
# Justificativa: os roteiros dos processos filhos chegam sem expansao, e as
# atribuicoes de ambiente repassam ao filho valores do proprio caso.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

CONTA='cred-0123456789abcdef0123456789abcdef'
PREFIXO_H='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
VOO_H='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
HASH_D='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'

_area() {
  AREA=$(mktemp -d "$DBX_TESTES_TMP/retomada.XXXXXX")
  mkdir -p "$AREA/xdg" "$AREA/tmp" "$AREA/alvo"
  ESTADO="$AREA/xdg/dbx"
}

_filho() {
  local roteiro=$1
  shift
  FILHO_SAIDA=$(_filho_cru "$roteiro" "$@" 2>&1)
  FILHO_ESTADO=$?
}

_filho_cru() {
  local roteiro=$1
  shift
  XDG_STATE_HOME="$AREA/xdg" TMPDIR="$AREA/tmp" AREA="$AREA" ESTADO="$ESTADO" \
    RAIZ="$DBX_HARNESS_RAIZ" CONTA="$CONTA" PREFIXO_H="$PREFIXO_H" VOO_H="$VOO_H" HASH_D="$HASH_D" \
    bash -c '
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
'"$roteiro" _ "$@" </dev/null
}

# Contexto e registros validos de cada sentido (os campos do sentido de RF-101(c)).
readonly CTX_UP='dbx_state_retomada_contexto upload "$CONTA" "$AREA/local.bin" /Remoto/Grande.ISO || exit 90'
readonly CTX_DOWN='dbx_state_retomada_contexto download "$CONTA" "$AREA/alvo/grande.iso" /Remoto/Grande.ISO || exit 90'
readonly GRAVAR_UP='dbx_state_retomada_gravar "S:sessao-SENTINELA_1" 8388608 4194304 "$VOO_H" 167772160 "1|a|b|2|3|167772160" 1700000000 "$PREFIXO_H"'
readonly CARREGAR='dbx_state_retomada_carregar; e=$?
printf "estado=%s\n" "$e"
printf "motivo=%s\n" "$DBX_STATE_MOTIVO"
printf "campos=%s\n" "${#DBX_STATE_RETOMADA_CAMPOS[@]}"'

# _arquivo_do <ctx> — caminho do registro do contexto.
_arquivo_do() {
  _filho_cru "$1"'; printf "%s" "$DBX_STATE_RETOMADA_ARQUIVO"'
}

# _plantar <arquivo> — conteudo cru da entrada padrao, 0600, no diretorio 0700.
_plantar() {
  [[ $1 == "$AREA"/* ]] || _harness_falhar 'registro fora da area do caso' "[$1]"
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  cat >"$1"
  chmod 600 "$1"
}

# _registro_up <campos...> — registro de upload valido, com campos trocaveis por
# variavel: MAGIA, VERSAO, SENTIDO, CONTA_R, HOST_R, REMOTO_R, LOCAL_R, SESSAO_R,
# CONF_R, EXTRA (campo a mais antes do local).
_registro_up() {
  local host
  host=$(_filho_cru 'dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_NOME"')
  printf '%s\0' "${MAGIA:-dbx-retomada}" "${VERSAO:-1}" "${SENTIDO:-upload}" "${CONTA_R:-$CONTA}" \
    "${HOST_R:-$host}" "${REMOTO_R:-/Remoto/Grande.ISO}" "${SESSAO_R:-S:sessao-1}" "${CONF_R:-8388608}" \
    4194304 "$VOO_H" 167772160 '1|a|b|2|3|167772160' 1700000000 "$PREFIXO_H"
  [[ -n ${EXTRA:-} ]] && printf '%s\0' "$EXTRA"
  [[ -n ${SEM_LOCAL:-} ]] || printf '%s\0' "${LOCAL_R:-$AREA/local.bin}"
}

# ---------------------------------------------------------------------------
# Formato, local e permissoes (TC-RME-01)
# ---------------------------------------------------------------------------

teste_rme01_registro_nasce_0600_em_0700_com_campos_nul_na_ordem_e_local_por_ultimo() {
  _area
  _filho 'umask 022; '"$CTX_UP"'; '"$GRAVAR_UP"' || exit 91
    a=$DBX_STATE_RETOMADA_ARQUIVO
    stat -c "%a" "$a" >"$AREA/modo"; stat -c "%a" "${a%/*}" >"$AREA/modo_dir"
    cp "$a" "$AREA/copia"; printf "%s" "$a" >"$AREA/nome"'
  assert_igual 0 "$FILHO_ESTADO" "gravacao: $FILHO_SAIDA"
  assert_igual 600 "$(cat "$AREA/modo")" 'registro 0600 apesar do umask 022'
  assert_igual 700 "$(cat "$AREA/modo_dir")" 'diretorio 0700'
  local nome
  nome=$(cat "$AREA/nome")
  [[ ${nome##*/} =~ ^retomada-[0-9a-f]{32}$ ]] || _harness_falhar 'nome retomada-<resumo32>' "$nome"
  assert_igual "$ESTADO" "${nome%/*}" 'no mesmo diretorio de estado'
  local -a campos=()
  local campo
  while IFS= read -r -d '' campo; do campos+=("$campo"); done <"$AREA/copia"
  assert_igual 15 "${#campos[@]}" 'contagem fixa do upload'
  assert_igual 'dbx-retomada|1|upload|'"$CONTA" "${campos[0]}|${campos[1]}|${campos[2]}|${campos[3]}" 'magia, versao, sentido, conta'
  assert_igual '/Remoto/Grande.ISO' "${campos[5]}" 'remoto como dado'
  assert_igual 'S:sessao-SENTINELA_1|8388608|4194304' "${campos[6]}|${campos[7]}|${campos[8]}" 'sessao, confirmado, parte em voo'
  assert_igual "$PREFIXO_H" "${campos[13]}" 'prefixo_hash'
  assert_igual "$AREA/local.bin" "${campos[14]}" 'caminho local por ultimo'
  assert_igual '' "$(find "$ESTADO" -name '.retomada.*')" 'sem temporario residual'
}

teste_rme01_registro_de_download_tem_treze_campos() {
  _area
  _filho "$CTX_DOWN"'; dbx_state_retomada_gravar 0123456789a 167772160 "$HASH_D" .grande.iso.dbx-part.AbC123 "5|6" 1700000000 || exit 91
    cp "$DBX_STATE_RETOMADA_ARQUIVO" "$AREA/copia"'
  assert_igual 0 "$FILHO_ESTADO" "gravacao: $FILHO_SAIDA"
  local -a campos=()
  local campo
  while IFS= read -r -d '' campo; do campos+=("$campo"); done <"$AREA/copia"
  assert_igual 13 "${#campos[@]}" 'contagem fixa do download'
  assert_igual "download|0123456789a|.grande.iso.dbx-part.AbC123|5|6|$AREA/alvo/grande.iso" \
    "${campos[2]}|${campos[6]}|${campos[9]}|${campos[10]}|${campos[12]}" 'campos do download, alvo por ultimo'
}

teste_rme01_gravacao_recusa_campo_invalido_sem_criar_registro() {
  _area
  _filho "$CTX_UP"'; dbx_state_retomada_gravar "sessao com espaco" 0 0 - 167772160 "1|a|b|2|3|167772160" 1 "$PREFIXO_H"; printf "e=%s\n" "$?"'
  assert_nao_contem 'e=0' "$FILHO_SAIDA" 'session_id fora da regex nao e gravado'
  assert_igual '' "$(find "$ESTADO" -name 'retomada-*' 2>/dev/null)" 'nenhum registro'
}

# ---------------------------------------------------------------------------
# Chave (TC-RME-03; C4)
# ---------------------------------------------------------------------------

teste_rme03_chave_separa_destino_sentido_conta_e_nao_colide_por_quebra_de_linha() {
  _area
  local a b c d e f g h
  a=$(_filho_cru 'dbx_state_retomada_contexto upload "$CONTA" /dados/x /R/a; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  b=$(_filho_cru 'dbx_state_retomada_contexto upload "$CONTA" /dados/x /R/b; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  c=$(_filho_cru 'dbx_state_retomada_contexto download "$CONTA" /dados/x /R/a; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  d=$(_filho_cru 'dbx_state_retomada_contexto upload cred-ffffffffffffffffffffffffffffffff /dados/x /R/a; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  e=$(_filho_cru 'dbx_state_retomada_contexto upload "$CONTA" /dados/x /r/A; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  f=$(_filho_cru 'dbx_state_retomada_contexto upload "$CONTA" $'"'"'a\nb'"'"' c; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  g=$(_filho_cru 'dbx_state_retomada_contexto upload "$CONTA" a $'"'"'b\nc'"'"'; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  h=$(_filho_cru 'dbx_state_retomada_contexto upload "$CONTA" /dados/SENTINELA /R/a; printf %s "$DBX_STATE_RETOMADA_ARQUIVO"')
  [[ $a =~ /retomada-[0-9a-f]{32}$ ]] || _harness_falhar 'nome so com resumo' "$a"
  assert_diferente "$a" "$b" 'mesmo arquivo para dois destinos: dois registros'
  assert_diferente "$a" "$c" 'upload e download do mesmo par: dois registros'
  assert_diferente "$a" "$d" 'outra credencial: outro registro'
  assert_igual "$a" "$e" 'o remoto entra so com a caixa ASCII dobrada'
  assert_diferente "$f" "$g" 'a\nb+c e a+b\nc nao colidem (separador NUL)'
  assert_nao_contem 'SENTINELA' "$h" 'nenhum dado externo cru no nome'
  assert_nao_contem 'trava-' "$a" 'prefixo distinto dos demais namespaces'
}

# ---------------------------------------------------------------------------
# Carga valida e descarte (TC-RME-04..10, 13; P2)
# ---------------------------------------------------------------------------

teste_rme13_registro_valido_carrega_sem_relogio_decidir() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  _registro_up | _plantar "$arquivo"
  # Modificado ha 30 dias e no futuro: o relogio nunca descarta registro em uso.
  touch -d '30 days ago' "$arquivo"
  _filho "$CTX_UP; $CARREGAR"'; printf "sessao=%s conf=%s\n" "${DBX_STATE_RETOMADA_CAMPOS[0]}" "${DBX_STATE_RETOMADA_CAMPOS[1]}"'
  assert_contem 'estado=0' "$FILHO_SAIDA" 'valido apesar de velho'
  assert_contem 'sessao=S:sessao-1 conf=8388608' "$FILHO_SAIDA" 'campos do sentido publicados'
  touch -d '30 days' "$arquivo"
  _filho "$CTX_UP; $CARREGAR"
  assert_contem 'estado=0' "$FILHO_SAIDA" 'valido com relogio atrasado'
}

# _descarta <descricao> — o registro plantado e descartado: apagado, um motivo
# de uma linha sem byte cru, e o chamador recebe 2 (descartado, segue do zero).
_descarta() {
  local arquivo=$1 descricao=$2
  _filho "$CTX_UP; $CARREGAR"
  assert_contem 'estado=2' "$FILHO_SAIDA" "$descricao: descartado"
  assert_arquivo_ausente "$arquivo" "$descricao: registro apagado"
  local motivo=${FILHO_SAIDA#*motivo=}
  motivo=${motivo%%$'\n'*}
  [[ -n $motivo ]] || _harness_falhar "$descricao: sem motivo"
  [[ $motivo == *[$'\001'-$'\037\177']* ]] && _harness_falhar "$descricao: motivo com byte de controle"
  assert_nao_contem 'sessao' "$motivo" "$descricao: motivo sem session_id"
  return 0
}

teste_rme04_a_rme06_vazio_truncado_e_lixo_nul_sao_descartados() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  : | _plantar "$arquivo"
  _descarta "$arquivo" 'arquivo de 0 bytes'
  _registro_up | head -c 120 | _plantar "$arquivo"
  _descarta "$arquivo" 'campo truncado'
  head -c 4000 /dev/zero | _plantar "$arquivo"
  _descarta "$arquivo" 'cheio de NUL'
  printf 'lixo\001\033[31m sem nulo' | _plantar "$arquivo"
  _descarta "$arquivo" 'lixo sem NUL'
}

teste_rme07_magia_errada_e_versao_2_sao_descartadas() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  MAGIA=dbx-cursor _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'magia errada'
  VERSAO=2 _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'versao maior'
}

teste_rme08_contagem_e_campos_fora_da_regex_sao_descartados() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  EXTRA=a-mais _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'campo a mais'
  SEM_LOCAL=1 _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'campo a menos'
  CONF_R=1234567890123456789 _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'deslocamento com 19 digitos'
  SESSAO_R='sessao com espaco' _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'session_id com espaco'
  CONF_R=1000 _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'confirmado fora do multiplo de 4 MiB'
  # Download com rev em maiuscula e resumo com 63 hexadecimais.
  local d host
  d=$(_arquivo_do "$CTX_DOWN")
  host=$(_filho_cru 'dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_NOME"')
  printf '%s\0' dbx-retomada 1 download "$CONTA" "$host" /Remoto/Grande.ISO 0123456789A 167772160 "$HASH_D" \
    .grande.iso.dbx-part.AbC123 '5|6' 1700000000 "$AREA/alvo/grande.iso" | _plantar "$d"
  _filho "$CTX_DOWN; $CARREGAR"
  assert_contem 'estado=2' "$FILHO_SAIDA" 'rev com maiuscula'
  printf '%s\0' dbx-retomada 1 download "$CONTA" "$host" /Remoto/Grande.ISO 0123456789a 167772160 "${HASH_D:1}" \
    .grande.iso.dbx-part.AbC123 '5|6' 1700000000 "$AREA/alvo/grande.iso" | _plantar "$d"
  _filho "$CTX_DOWN; $CARREGAR"
  assert_contem 'estado=2' "$FILHO_SAIDA" 'resumo com 63 hexadecimais'
  assert_arquivo_ausente "$d" 'registro de download apagado'
}

teste_rme09_registro_acima_de_16_kib_e_descartado() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  # O caminho local, ultimo campo, empurra o arquivo para 16 KiB + 1.
  local tamanho folga
  tamanho=$(LOCAL_R=x _registro_up | wc -c)
  folga=$((16385 - tamanho))
  LOCAL_R="/$(head -c "$folga" /dev/zero | tr '\0' a)" _registro_up | _plantar "$arquivo"
  assert_igual 16385 "$(stat -c %s "$arquivo")" 'massa de 16 KiB + 1'
  _descarta "$arquivo" 'acima do limite'
}

teste_rme10_conta_sentido_host_remoto_e_local_divergentes_descartam() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  CONTA_R=cred-ffffffffffffffffffffffffffffffff _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'outra conta'
  SENTIDO=download _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'outro sentido'
  HOST_R=outro-host _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'outro host'
  REMOTO_R=/remoto/grande.iso _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'outro remoto (byte a byte)'
  LOCAL_R=/outro/local.bin _registro_up | _plantar "$arquivo"
  _descarta "$arquivo" 'outro local'
}

teste_rme11_ligacao_simbolica_e_diretorio_no_lugar_nao_sao_lidos_nem_apagados() {
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  mkdir -p "$ESTADO"
  _registro_up >"$AREA/alheio"
  ln -s "$AREA/alheio" "$arquivo"
  _filho "$CTX_UP; $CARREGAR"
  assert_contem 'estado=3' "$FILHO_SAIDA" 'ligacao simbolica: intocavel'
  [[ -L $arquivo ]] || _harness_falhar 'a ligacao foi apagada'
  assert_igual "$(_registro_up | wc -c)" "$(wc -c <"$AREA/alheio")" 'alvo intacto'
  _filho "$CTX_UP; $GRAVAR_UP"'; printf "g=%s\n" "$?"'
  assert_nao_contem 'g=0' "$FILHO_SAIDA" 'nao grava por cima do que nao leu'
  [[ -L $arquivo ]] || _harness_falhar 'a gravacao trocou a ligacao'
  rm -f "$arquivo"
  mkdir "$arquivo"
  _filho "$CTX_UP; $CARREGAR"
  assert_contem 'estado=3' "$FILHO_SAIDA" 'diretorio no lugar: intocavel'
  [[ -d $arquivo ]] || _harness_falhar 'o diretorio foi apagado'
}

teste_rme11_registro_de_outro_dono_nao_e_lido_nem_apagado() {
  [[ $EUID -eq 0 ]] || pular 'exige root para criar arquivo de outro dono'
  _area
  local arquivo
  arquivo=$(_arquivo_do "$CTX_UP")
  _registro_up | _plantar "$arquivo"
  chown 65534 "$arquivo"
  _filho "$CTX_UP; $CARREGAR"
  assert_contem 'estado=3' "$FILHO_SAIDA" 'de outro dono: intocavel'
  assert_arquivo_existe "$arquivo" 'nao apagado'
}

teste_rme12_diretorio_de_estado_alheio_ou_sem_escrita_fica_inutilizavel() {
  _area
  mkdir -p "$ESTADO"
  chmod 500 "$ESTADO"
  _filho 'dbx_state_retomada_diretorio_utilizavel; printf "u=%s motivo=%s\n" "$?" "$DBX_STATE_MOTIVO"'
  chmod 700 "$ESTADO"
  assert_nao_contem 'u=0' "$FILHO_SAIDA" 'sem escrita: inutilizavel'
  assert_contem 'motivo=' "$FILHO_SAIDA" 'com motivo'
  rm -rf "$ESTADO"
  _filho 'dbx_state_retomada_diretorio_utilizavel; printf "u=%s\n" "$?"; stat -c %a "$ESTADO"'
  assert_contem 'u=0' "$FILHO_SAIDA" 'ausente: criado'
  assert_contem '700' "$FILHO_SAIDA" 'criado em 0700'
}

# ---------------------------------------------------------------------------
# Leitor limitado tambem no `upload-*` (TC-UPC-13; C3)
# ---------------------------------------------------------------------------

# _rchar_de <roteiro> — bytes lidos pelo processo durante o roteiro (rchar de
# /proc/self/io, medido no mesmo processo antes e depois).
readonly RCHAR='_rc() { local l; while IFS= read -r l; do [[ $l == rchar:* ]] && printf "%s" "${l#rchar: }"; done </proc/$BASHPID/io; }'

teste_upc13_upload_acima_do_limite_sem_nul_ou_com_campo_invalido_e_cache_ausente() {
  [[ -r /proc/self/io ]] || pular 'sem /proc/self/io para medir bytes lidos'
  _area
  local arquivo identidade chave="$AREA/origem.bin"
  printf 'conteudo' >"$chave"
  arquivo=$(_filho_cru 'dbx_state_upload_caminho "$1"; printf %s "$DBX_STATE_RESULTADO"' "$chave")
  identidade='1|a|b|2|3|8'
  # Valido: o formato v2 de RF-61 nao muda.
  printf '2\0upload\0%s\0%s\t%s\0' "$chave" "$PREFIXO_H" "$identidade" | _plantar "$arquivo"
  _filho 'dbx_state_upload_consultar "$1" "$2"; printf "c=%s h=%s\n" "$?" "$DBX_STATE_HASH"' "$chave" "$identidade"
  assert_contem "c=0 h=$PREFIXO_H" "$FILHO_SAIDA" 'registro valido continua aceito'
  # 1 MiB sem nulo: rejeitado sem ler alem do limite.
  head -c 1048576 /dev/zero | tr '\0' a | _plantar "$arquivo"
  _filho "$RCHAR"'; a=$(_rc); dbx_state_upload_consultar "$1" "$2"; c=$?; b=$(_rc); printf "c=%s lidos=%s\n" "$c" "$((b - a))"' "$chave" "$identidade"
  assert_contem 'c=1' "$FILHO_SAIDA" '1 MiB sem nulo: cache ausente'
  local lidos=${FILHO_SAIDA##*lidos=}
  [[ $lidos =~ ^[0-9]+$ && $lidos -lt 65536 ]] || _harness_falhar 'o leitor leu alem do limite' "lidos: $lidos"
  # 16 KiB + 1 com o formato certo.
  local enchimento
  enchimento=$(head -c 16300 /dev/zero | tr '\0' b)
  printf '2\0upload\0%s\0%s\t%s\0%s' "$chave" "$PREFIXO_H" "$identidade" "$enchimento" | head -c 16385 | _plantar "$arquivo"
  _filho 'dbx_state_upload_consultar "$1" "$2"; printf "c=%s\n" "$?"' "$chave" "$identidade"
  assert_contem 'c=1' "$FILHO_SAIDA" '16 KiB + 1: cache ausente'
  printf '2\0upload\0%s\0%s\t%s\0extra\0' "$chave" "$PREFIXO_H" "$identidade" | _plantar "$arquivo"
  _filho 'dbx_state_upload_consultar "$1" "$2"; printf "c=%s\n" "$?"' "$chave" "$identidade"
  assert_contem 'c=1' "$FILHO_SAIDA" 'campo a mais: cache ausente'
  printf '2\0upload\0%s\0%s\t%s\0' "$chave" "zz${PREFIXO_H:2}" "$identidade" | _plantar "$arquivo"
  _filho 'dbx_state_upload_consultar "$1" "$2"; printf "c=%s\n" "$?"' "$chave" "$identidade"
  assert_contem 'c=1' "$FILHO_SAIDA" 'resumo fora da regex: cache ausente'
}

# ---------------------------------------------------------------------------
# Barreira do `.part` (RF-104(c)(e); P1)
# ---------------------------------------------------------------------------

_part() { # <nome> — cria o .part no diretorio do alvo e imprime "dev|ino"
  printf 'parcial' >"$AREA/alvo/$1"
  chmod 600 "$AREA/alvo/$1"
  stat -c '%d|%i' "$AREA/alvo/$1"
}

readonly BARREIRA='dbx_state_retomada_part_barreira "$1" "$2" "$3"; printf "b=%s\n" "$?"'

teste_barreira_so_aceita_o_part_registrado() {
  _area
  local di nome=.grande.iso.dbx-part.AbC123
  di=$(_part "$nome")
  _filho "$BARREIRA" "$AREA/alvo" "$nome" "$di"
  assert_contem 'b=0' "$FILHO_SAIDA" 'o .part registrado passa'
  _filho "$BARREIRA" "$AREA/alvo" "$nome" '1|2'
  assert_contem 'b=1' "$FILHO_SAIDA" 'outro inode reprova'
  _filho "$BARREIRA" "$AREA/alvo" "../alvo/$nome" "$di"
  assert_contem 'b=1' "$FILHO_SAIDA" 'nome com barra reprova'
  _filho "$BARREIRA" "$AREA/alvo" grande.iso "$di"
  assert_contem 'b=1' "$FILHO_SAIDA" 'fora do padrao de nome reprova'
  _filho "$BARREIRA" "$AREA" "$nome" "$di"
  assert_contem 'b=1' "$FILHO_SAIDA" 'fora do diretorio do alvo reprova'
  mv "$AREA/alvo/$nome" "$AREA/real"
  ln -s "$AREA/real" "$AREA/alvo/$nome"
  _filho "$BARREIRA" "$AREA/alvo" "$nome" "$di"
  assert_contem 'b=1' "$FILHO_SAIDA" 'ligacao simbolica para o mesmo inode reprova'
}

# ---------------------------------------------------------------------------
# Trava por registro (TC-RMC-02, 03; C2)
# ---------------------------------------------------------------------------

teste_rmc02_trava_de_registro_tem_comando_retomada_e_o_mesmo_resumo() {
  _area
  _filho "$CTX_UP"'; dbx_state_retomada_diretorio_utilizavel; dbx_state_retomada_travar; printf "t=%s\n" "$?"
    r=${DBX_STATE_RETOMADA_ARQUIVO##*/retomada-}
    t="${DBX_STATE_RETOMADA_ARQUIVO%/*}/trava-$r"
    [[ -e $t ]] && cp "$t" "$AREA/copia"
    dbx_state_retomada_soltar
    [[ -e $t ]] && printf "sobrou\n"; exit 0'
  assert_contem 't=0' "$FILHO_SAIDA" 'adquirida'
  assert_nao_contem 'sobrou' "$FILHO_SAIDA" 'liberada'
  local -a campos=()
  IFS=$'\t' read -r -a campos <"$AREA/copia"
  assert_igual 'retomada fim' "${campos[5]} ${campos[6]}" 'comando retomada'
  # O fim do processo tambem libera (acao registrada em lib/tmp).
  _filho "$CTX_UP"'; dbx_state_retomada_diretorio_utilizavel; dbx_state_retomada_travar; exit 0'
  assert_igual '' "$(find "$ESTADO" -name 'trava-*')" 'liberada na saida'
}

teste_rmc02_trava_de_par_e_de_registro_convivem_no_mesmo_processo() {
  _area
  _filho 'dbx_state_trava_adquirir "$CONTA" /dados /R sync 0; printf "p=%s\n" "$?"
    '"$CTX_UP"'; dbx_state_retomada_travar; printf "t=%s\n" "$?"
    find "$ESTADO" -name "trava-*" | wc -l'
  assert_contem 'p=0' "$FILHO_SAIDA" 'trava de par'
  assert_contem 't=0' "$FILHO_SAIDA" 'trava de registro alem da de par'
  assert_contem $'\n2' "$FILHO_SAIDA" 'duas travas'
}

teste_rmc03_ocupada_outro_host_e_ilegivel_recusam_sem_apagar_e_orfa_e_retomada() {
  _area
  local trava host
  trava=$(_filho_cru "$CTX_UP"'; printf "%s/trava-%s" "${DBX_STATE_RETOMADA_ARQUIVO%/*}" "${DBX_STATE_RETOMADA_ARQUIVO##*/retomada-}"')
  host=$(_filho_cru 'dbx_state_host_id; printf %s "$DBX_STATE_HOST_ID"')
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' "$$" "$host" 1700000000 >"$trava"
  _filho "$CTX_UP"'; dbx_state_retomada_travar; printf "t=%s\nmotivo=%s\n" "$?" "$DBX_STATE_MOTIVO"'
  assert_contem 't=7' "$FILHO_SAIDA" 'viva: conflito'
  assert_contem "pid $$" "$FILHO_SAIDA" 'o motivo nomeia o pid'
  assert_arquivo_existe "$trava" 'a viva fica'
  printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' 4242 'outro:x:x' 1700000000 >"$trava"
  _filho "$CTX_UP"'; dbx_state_retomada_travar; printf "t=%s\n" "$?"'
  assert_contem 't=7' "$FILHO_SAIDA" 'outro host: conflito'
  assert_arquivo_existe "$trava" 'a de outro host fica'
  printf 'lixo' >"$trava"
  _filho "$CTX_UP"'; dbx_state_retomada_travar; printf "t=%s\n" "$?"'
  assert_contem 't=7' "$FILHO_SAIDA" 'ilegivel: conflito'
  assert_igual 'lixo' "$(cat "$trava")" 'a ilegivel fica'
  local morto
  sleep 0 &
  morto=$!
  wait "$morto"
  printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' "$morto" "$host" 1700000000 >"$trava"
  _filho "$CTX_UP"'; dbx_state_retomada_travar; printf "t=%s\naviso=%s\n" "$?" "$DBX_STATE_AVISO"'
  assert_contem 't=0' "$FILHO_SAIDA" 'orfa do mesmo host: retomada'
  assert_contem 'orfa' "$FILHO_SAIDA" 'com aviso'
}

# ---------------------------------------------------------------------------
# Poda e temporarios (TC-RML-01..04; DIV-184)
# ---------------------------------------------------------------------------

# _registro_down_em <arquivo> <nome_part> <devino> — registro de download valido.
_registro_down_em() {
  local host
  host=$(_filho_cru 'dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_NOME"')
  printf '%s\0' dbx-retomada 1 download "$CONTA" "$host" /Remoto/Outro.iso 0123456789a 10 "$HASH_D" \
    "$2" "$3" 1700000000 "$AREA/alvo/outro.iso" | _plantar "$1"
}

teste_rml01_poda_tira_so_retomada_com_mais_de_8_dias_e_sem_trava_viva() {
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  local velho="$ESTADO/retomada-0000000000000000000000000000000a"
  local novo="$ESTADO/retomada-0000000000000000000000000000000b"
  local preso="$ESTADO/retomada-0000000000000000000000000000000c"
  printf 'x' >"$velho"
  printf 'x' >"$novo"
  printf 'x' >"$preso"
  printf 'x' >"$ESTADO/memoria-0000000000000000000000000000000a"
  printf 'x' >"$ESTADO/upload-0000000000000000000000000000000a"
  printf 'x' >"$ESTADO/trava-0000000000000000000000000000000d"
  local host
  host=$(_filho_cru 'dbx_state_host_id; printf %s "$DBX_STATE_HOST_ID"')
  printf 'dbx-trava\t1\t%s\t%s\t%s\tretomada\tfim\n' "$$" "$host" 1700000000 >"$ESTADO/trava-0000000000000000000000000000000c"
  touch -d '9 days ago' "$velho" "$preso" "$ESTADO/memoria-0000000000000000000000000000000a" \
    "$ESTADO/upload-0000000000000000000000000000000a" "$ESTADO/trava-0000000000000000000000000000000d"
  touch -d '7 days ago' "$novo"
  _filho "$CTX_UP; $GRAVAR_UP"' || exit 91'
  assert_igual 0 "$FILHO_ESTADO" "gravacao: $FILHO_SAIDA"
  assert_arquivo_ausente "$velho" '9 dias: podado'
  assert_arquivo_existe "$novo" '7 dias: fica'
  assert_arquivo_existe "$preso" 'velho com trava viva: fica'
  assert_arquivo_existe "$ESTADO/memoria-0000000000000000000000000000000a" 'memoria fica'
  assert_arquivo_existe "$ESTADO/upload-0000000000000000000000000000000a" 'upload fica'
  assert_arquivo_existe "$ESTADO/trava-0000000000000000000000000000000d" 'trava fica'
}

teste_rml02_teto_de_1000_registros_tira_os_mais_antigos() {
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  local i nome sete oito
  for ((i = 0; i < 1000; i++)); do
    printf -v nome '%032x' "$i"
    printf 'x' >"$ESTADO/retomada-$nome"
  done
  printf -v sete '%032x' 7
  printf -v oito '%032x' 8
  touch -d '2 days ago' "$ESTADO"/retomada-*
  touch -d '3 days ago' "$ESTADO/retomada-$sete"
  _filho "$CTX_UP; $GRAVAR_UP"' || exit 91'
  assert_igual 0 "$FILHO_ESTADO" "gravacao: $FILHO_SAIDA"
  local -a restantes=("$ESTADO"/retomada-*)
  assert_igual 1000 "${#restantes[@]}" '1001 com o novo: restam 1000'
  assert_arquivo_ausente "$ESTADO/retomada-$sete" 'saiu o mais antigo'
  rm -f "$ESTADO/retomada-$oito"
  _filho "$CTX_DOWN"'; dbx_state_retomada_gravar 0123456789a 10 "$HASH_D" .x.dbx-part.AbC123 "1|2" 1 || exit 91'
  restantes=("$ESTADO"/retomada-*)
  assert_igual 1000 "${#restantes[@]}" '1000 com o novo: nenhum sai'
}

teste_rml03_part_de_registro_podado_so_sai_pela_barreira() {
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  local bom=.outro.iso.dbx-part.Aaaaa1 trocado=.outro.iso.dbx-part.Bbbbb2 ligado=.outro.iso.dbx-part.Ccccc3
  local di_bom di_trocado
  di_bom=$(_part "$bom")
  di_trocado=$(_part "$trocado")
  rm -f "$AREA/alvo/$trocado"
  printf 'usuario' >"$AREA/alvo/$trocado" # mesmo nome, outro inode
  printf 'alvo' >"$AREA/real"
  ln -s "$AREA/real" "$AREA/alvo/$ligado"
  _registro_down_em "$ESTADO/retomada-0000000000000000000000000000000a" "$bom" "$di_bom"
  _registro_down_em "$ESTADO/retomada-0000000000000000000000000000000b" "$trocado" "$di_trocado"
  _registro_down_em "$ESTADO/retomada-0000000000000000000000000000000c" "$ligado" "$di_bom"
  printf 'ilegivel' >"$ESTADO/retomada-0000000000000000000000000000000d"
  touch -d '9 days ago' "$ESTADO"/retomada-*
  _filho "$CTX_UP; $GRAVAR_UP"' || exit 91'
  assert_igual 0 "$FILHO_ESTADO" "gravacao: $FILHO_SAIDA"
  assert_arquivo_ausente "$AREA/alvo/$bom" 'passa a barreira: apagado'
  assert_igual 'usuario' "$(cat "$AREA/alvo/$trocado")" 'outro inode: intacto'
  [[ -L $AREA/alvo/$ligado ]] || _harness_falhar 'a ligacao simbolica foi apagada'
  assert_igual 'alvo' "$(cat "$AREA/real")" 'o alvo da ligacao intacto'
  local x zeros
  printf -v zeros '%031d' 0
  for x in a b c d; do
    assert_arquivo_ausente "$ESTADO/retomada-$zeros$x" "registro podado ($x)"
  done
}

teste_rml04_temporario_retomada_velho_sai_e_o_recente_fica() {
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  printf 'x' >"$ESTADO/.retomada.1.velho"
  printf 'x' >"$ESTADO/.retomada.1.novo"
  touch -d '2 days ago' "$ESTADO/.retomada.1.velho"
  _filho "$CTX_UP; $GRAVAR_UP"' || exit 91'
  assert_arquivo_ausente "$ESTADO/.retomada.1.velho" 'mais de 1 dia: removido'
  assert_arquivo_existe "$ESTADO/.retomada.1.novo" 'recente: preservado'
}

# ---------------------------------------------------------------------------
# Listagem para o diagnostico e o unlink (RF-107(c)(d))
# ---------------------------------------------------------------------------

teste_rml06_listagem_so_le_e_classifica_pendente_ilegivel_e_orfa() {
  _area
  _filho 'dbx_state_retomada_listar; printf "n=%s\n" "${#DBX_STATE_RETOMADAS_ARQUIVO[@]}"'
  assert_contem 'n=0' "$FILHO_SAIDA" 'sem diretorio: nada'
  assert_arquivo_ausente "$ESTADO" 'a listagem nao cria o diretorio'
  local pend velho
  pend=$(_arquivo_do "$CTX_UP")
  _registro_up | _plantar "$pend"
  velho="$ESTADO/retomada-0000000000000000000000000000000e"
  _registro_down_em "$velho" .outro.iso.dbx-part.Aaaaa1 '1|2'
  touch -d '9 days ago' "$velho"
  printf 'ruim' >"$ESTADO/retomada-0000000000000000000000000000000f"
  _filho 'dbx_state_retomada_listar
    for i in "${!DBX_STATE_RETOMADAS_ARQUIVO[@]}"; do
      printf "%s|%s|%s|%s\n" "${DBX_STATE_RETOMADAS_ESTADO[i]}" "${DBX_STATE_RETOMADAS_SENTIDO[i]}" "${DBX_STATE_RETOMADAS_BYTES[i]}" "${DBX_STATE_RETOMADAS_REMOTO[i]}"
    done'
  assert_contem 'pendente|upload|8388608|/Remoto/Grande.ISO' "$FILHO_SAIDA" 'pendente com bytes confirmados'
  assert_contem 'orfa|download|' "$FILHO_SAIDA" 'mais de 8 dias: orfa'
  assert_contem 'ilegivel|' "$FILHO_SAIDA" 'ilegivel'
  assert_nao_contem 'sessao-1' "$FILHO_SAIDA" 'nenhum session_id na listagem'
  assert_arquivo_existe "$ESTADO/retomada-0000000000000000000000000000000f" 'nada removido'
}

# ---------------------------------------------------------------------------
# Ciclo 2 do QA: entrada nao regular nunca bloqueia (QA-B7A-01) e o descarte
# por cabecalho leva o `.part` pela barreira (QA-B7A-02)
# ---------------------------------------------------------------------------

teste_c2_fifo_no_lugar_do_registro_nao_bloqueia_leitor_listagem_nem_travas() {
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  mkfifo -m 600 "$ESTADO/retomada-0123456789abcdef0123456789abcdef"
  mkfifo -m 600 "$ESTADO/trava-0123456789abcdef0123456789abcdef"
  _filho 'timeout 10 bash -c '"'"'
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    _dbx_state_ler_limitado "$ESTADO/retomada-0123456789abcdef0123456789abcdef" 15; printf "leitor=%s\n" "$?"
    dbx_state_retomada_listar; printf "lista=%s\n" "${DBX_STATE_RETOMADAS_ESTADO[*]}"
    dbx_state_travas_listar; printf "travas=%s\n" "${DBX_STATE_TRAVAS_ESTADO[*]}"
  '"'"'; printf "saida=%s\n" "$?"'
  assert_contem 'saida=0' "$FILHO_SAIDA" 'nada bloqueia numa FIFO (timeout seria 124)'
  assert_contem 'leitor=1' "$FILHO_SAIDA" 'o leitor limitado recusa a FIFO'
  assert_contem 'lista=ilegivel' "$FILHO_SAIDA" 'a listagem a mostra como ilegivel'
  assert_contem 'travas=ilegivel' "$FILHO_SAIDA" 'a trava FIFO e ilegivel'
  [[ -p $ESTADO/retomada-0123456789abcdef0123456789abcdef ]] || _harness_falhar 'a FIFO nao e tocada'
}

teste_c2_poda_ignora_entrada_nao_regular() {
  _area
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  mkfifo -m 600 "$ESTADO/retomada-0000000000000000000000000000000a"
  touch -d '9 days ago' "$ESTADO/retomada-0000000000000000000000000000000a"
  _filho 'timeout 10 bash -c '"'"'
    . "$RAIZ/lib/errors.sh"; . "$RAIZ/lib/json.sh"; . "$RAIZ/lib/config.sh"; . "$RAIZ/lib/state.sh"
    '"$CTX_UP; $GRAVAR_UP"'
  '"'"'; printf "saida=%s\n" "$?"'
  assert_contem 'saida=0' "$FILHO_SAIDA" 'a gravacao (com poda) nao bloqueia'
  [[ -p $ESTADO/retomada-0000000000000000000000000000000a ]] || _harness_falhar 'a FIFO nao e podada'
}

teste_c2_descarte_por_cabecalho_leva_o_part_pela_barreira() {
  _area
  local d host nome=.grande.iso.dbx-part.AbC123 di
  di=$(_part "$nome")
  d=$(_arquivo_do "$CTX_DOWN")
  host=$(_filho_cru 'dbx_state_host_id; printf "%s" "$DBX_STATE_HOST_NOME"')
  # Registro valido de OUTRO remoto (mesma chave pela dobra de caixa).
  printf '%s\0' dbx-retomada 1 download "$CONTA" "$host" /Remoto/grande.iso 0123456789a 10 "$HASH_D" \
    "$nome" "$di" 1700000000 "$AREA/alvo/grande.iso" | _plantar "$d"
  _filho "$CTX_DOWN; $CARREGAR"
  assert_contem 'estado=2' "$FILHO_SAIDA" 'descartado pelo cabecalho'
  assert_arquivo_ausente "$AREA/alvo/$nome" 'o .part do registro descartado sai pela barreira'
  # O mesmo, com o arquivo trocado por outro inode: fica.
  printf 'usuario' >"$AREA/alvo/$nome"
  printf '%s\0' dbx-retomada 1 download "$CONTA" "$host" /Remoto/grande.iso 0123456789a 10 "$HASH_D" \
    "$nome" "$di" 1700000000 "$AREA/alvo/grande.iso" | _plantar "$d"
  _filho "$CTX_DOWN; $CARREGAR"
  assert_contem 'estado=2' "$FILHO_SAIDA" 'descartado'
  assert_igual 'usuario' "$(cat "$AREA/alvo/$nome")" 'outro inode: intocado'
  # Registro de OUTRO alvo copiado para esta chave: o `.part` dele fica.
  rm -f "$AREA/alvo/$nome"
  di=$(_part "$nome")
  printf '%s\0' dbx-retomada 1 download "$CONTA" "$host" /Remoto/Grande.ISO 0123456789a 10 "$HASH_D" \
    "$nome" "$di" 1700000000 "$AREA/alvo/outro.iso" | _plantar "$d"
  _filho "$CTX_DOWN; $CARREGAR"
  assert_contem 'estado=2' "$FILHO_SAIDA" 'descartado'
  assert_arquivo_existe "$AREA/alvo/$nome" 'o .part de outro alvo nunca sai por esta chave'
}

harness_executar "$@"
