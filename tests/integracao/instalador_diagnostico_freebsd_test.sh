#!/usr/bin/env bash
# Instalador, desinstalador e diagnostico no FreeBSD (RF-170, RF-172;
# TC-FBSD-08, 09 e 23).
#
# O instalador sugere o gerenciador que EXISTE no host (`pkg` ou `apt`), por
# capacidade (`command -v`), e e neutro quando nenhum existe (DIV-357). O
# diagnostico diz de qual utilitario vem o resumo SHA-256 e marca "nao
# verificado" onde o tipo do sistema de arquivos nao pode ser lido (RF-172).
#
# shellcheck disable=SC2016
# Justificativa: os programas filhos e os dubles sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/tests/support/freebsd.sh"

BASH_ABSOLUTO=$(command -v bash)
readonly BASH_ABSOLUTO

# _bin <area> [utilitario...] — diretorio de links com a base e os extras.
_bin() {
  local dir=$1/bin alvo origem
  shift
  mkdir -p "$dir"
  for alvo in bash env id dirname basename cat mkdir rm cp chmod mktemp stat sed tr head ln mv \
    readlink find df tail wc sleep rmdir "$@"; do
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -sf "$origem" "$dir/$alvo"
  done
  printf '%s' "$dir"
}

# _gerenciador <diretorio> <nome> — executavel vazio que so existe para o
# `command -v` do instalador.
_gerenciador() {
  printf '#!%s\nexit 0\n' "$BASH_ABSOLUTO" >"$1/$2"
  chmod +x "$1/$2"
}

# _instalar_sem_curl <bin> <area> — roda o instalador sem curl; saida em $2/log.
_instalar_sem_curl() {
  env -i PATH="$1" HOME="$2" "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/install.sh" --user \
    >"$2/log" 2>&1
  DBX_ESTADO=$?
}

# ---------------------------------------------------------------------------
# RF-170(c): mensagens por gerenciador detectado
# ---------------------------------------------------------------------------

teste_curl_ausente_com_pkg_sugere_pkg_install() {
  local area bin
  area=$(mktemp -d "$DBX_TESTES_TMP/inst.XXXXXX")
  bin=$(_bin "$area" sha256sum)
  _gerenciador "$bin" pkg
  _instalar_sem_curl "$bin" "$area"
  assert_igual 1 "$DBX_ESTADO" 'sem curl o instalador recusa'
  assert_contem 'pkg install' "$(cat "$area/log")" 'RF-170(c): sugere pkg'
  assert_nao_contem 'apt install' "$(cat "$area/log")" 'nao sugere apt onde nao ha apt'
}

teste_curl_ausente_com_apt_sugere_apt_install() {
  local area bin
  area=$(mktemp -d "$DBX_TESTES_TMP/inst.XXXXXX")
  bin=$(_bin "$area" sha256sum)
  _gerenciador "$bin" apt
  _instalar_sem_curl "$bin" "$area"
  assert_contem 'apt install' "$(cat "$area/log")" 'RF-170(c): sugere apt'
  assert_nao_contem 'pkg install' "$(cat "$area/log")" 'nao sugere pkg onde nao ha pkg'
}

teste_curl_ausente_sem_gerenciador_conhecido_e_neutro() {
  local area bin
  area=$(mktemp -d "$DBX_TESTES_TMP/inst.XXXXXX")
  bin=$(_bin "$area" sha256sum)
  _instalar_sem_curl "$bin" "$area"
  assert_contem 'cURL' "$(cat "$area/log")" 'a mensagem ainda nomeia o curl'
  assert_nao_contem 'pkg install' "$(cat "$area/log")" 'neutra: sem pkg'
  assert_nao_contem 'apt install' "$(cat "$area/log")" 'neutra: sem apt'
}

teste_resumo_ausente_com_pkg_tambem_sugere_pkg_install() {
  local area bin
  area=$(mktemp -d "$DBX_TESTES_TMP/inst.XXXXXX")
  bin=$(_bin "$area" curl)
  _gerenciador "$bin" pkg
  _instalar_sem_curl "$bin" "$area"
  assert_contem 'integridade' "$(cat "$area/log")" 'a recusa nomeia o utilitario de resumo'
  assert_contem 'pkg install' "$(cat "$area/log")" 'e sugere pkg'
}

# ---------------------------------------------------------------------------
# TC-FBSD-08 e TC-FBSD-09: instalar e desinstalar com os dubles do FreeBSD
# ---------------------------------------------------------------------------

_modo() { dbx_freebsd_real stat -c %a "$1"; }

teste_install_prefix_conclui_com_os_dubles_e_uninstall_remove_o_instalado() {
  local area prefixo share modo
  dbx_freebsd_ativar
  area=$(mktemp -d "$DBX_TESTES_TMP/inst.XXXXXX")
  prefixo="$area/prefixo"
  share="$prefixo/share/dropbox_sync"
  env -i PATH="$PATH" HOME="$area" DBX_FREEBSD_REGISTRO="$DBX_FREEBSD_REGISTRO" \
    "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/install.sh" --prefix "$prefixo" >"$area/log" 2>&1
  assert_igual 0 $? "TC-FBSD-08: instalacao conclui: $(cat "$area/log")"
  assert_igual 755 "$(_modo "$share/bin/dbx")" 'RF-170(d): bin/dbx 0755'
  assert_igual 755 "$(_modo "$share/uninstall.sh")" 'RF-170(d): uninstall.sh 0755'
  assert_igual 644 "$(_modo "$share/lib/hash.sh")" 'RF-170(d): lib 0644'
  assert_igual 644 "$(_modo "$share/commands/diagnostico.sh")" 'RF-170(d): commands 0644'
  [[ -L $prefixo/bin/dbx ]] || _harness_falhar 'o vinculo simbolico bin/dbx nao foi criado'
  assert_igual '' "$(dbx_freebsd_erros)" 'nenhum duble registrou erro de uso na instalacao'

  env -i PATH="$PATH" HOME="$area" DBX_FREEBSD_REGISTRO="$DBX_FREEBSD_REGISTRO" \
    "$BASH_ABSOLUTO" "$share/uninstall.sh" --prefix "$prefixo" >"$area/log2" 2>&1
  assert_igual 0 $? "TC-FBSD-09: desinstalacao conclui: $(cat "$area/log2")"
  [[ ! -e $prefixo/bin/dbx && ! -L $prefixo/bin/dbx ]] || _harness_falhar 'bin/dbx continua'
  [[ ! -d $share ]] || _harness_falhar 'o diretorio de dados continua'
  [[ ! -e $prefixo/share/bash-completion/completions/dbx ]] || _harness_falhar 'o autocompletar continua'
}

# ---------------------------------------------------------------------------
# TC-FBSD-23: diagnostico
# ---------------------------------------------------------------------------

# _diagnostico_bsd <area> — roda `dbx diagnostico` com PATH so de dubles BSD
# (stat que recusa -c, sha256 da base, sem sha256sum, shasum nem openssl).
_diagnostico_bsd() {
  local area=$1 bin
  bin=$(_bin "$area" curl)
  ln -sf "$DBX_FREEBSD_DUPLOS/sha256" "$bin/sha256"
  rm -f -- "$bin/stat"
  ln -s "$DBX_FREEBSD_DUPLOS/stat" "$bin/stat"
  mkdir -p "$area/config/dbx" "$area/estado/dbx" "$area/tmp"
  env -i PATH="$bin" HOME="$area" XDG_CONFIG_HOME="$area/config" XDG_STATE_HOME="$area/estado" \
    TMPDIR="$area/tmp" DBX_FREEBSD_REGISTRO="$area/registro" \
    "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/bin/dbx" diagnostico >"$area/out" 2>"$area/err"
  cat -- "$area/out" "$area/err"
}

teste_diagnostico_diz_de_qual_utilitario_vem_o_resumo() {
  local area saida
  area=$(mktemp -d "$DBX_TESTES_TMP/diag.XXXXXX")
  saida=$(_diagnostico_bsd "$area")
  assert_contem 'resumo SHA-256 via sha256' "$saida" 'RF-172(b): informa o utilitario do resumo'
}

teste_diagnostico_marca_nao_verificado_onde_o_tipo_do_sistema_de_arquivos_falha() {
  local area saida
  area=$(mktemp -d "$DBX_TESTES_TMP/diag.XXXXXX")
  saida=$(_diagnostico_bsd "$area")
  assert_contem 'nao verificado' "$saida" 'RF-172(c): marca em vez de omitir'
}

harness_executar "$@"
