#!/usr/bin/env bash
# Suite independente do QA: `install.sh` e `scripts/empacotar.sh` da linha de
# produto (F-102; RF-201..RF-205; TC-B42-09..22; DIV-385, DIV-389). Escrita como
# ADVERSARIO, sem reaproveitar os casos do Senior Developer
# (`tests/unit/instalador_linha_test.sh`), com fonte, area e duplos proprios.
#
# Foco: `--canal` hostil nao executa nada nem escreve fora; troca de linha avisa
# e preserva credencial e estado (0600); fonte local sem piso legivel e recusada
# sem escrever no destino; `escolher_linha` nas bordas; `empacotar.sh` passa
# `--latest=false` so na legada e sempre `--target <sha>`. Sem rede: `git` falso
# no PATH e `FUNCAO_BAIXAR` substituida (DBX_INSTALL_SO_FUNCOES=1).
#
# shellcheck disable=SC2016
# Justificativa: roteiros entregues como texto literal a "bash -c"; a expansao
# ocorre no processo filho.
#
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

Q_BASH=$(command -v bash)
readonly Q_BASH
readonly Q_INSTALADOR="$DBX_HARNESS_RAIZ/install.sh"
# sha256 literais (calculados fora do teste) do que _qb22_credencial grava.
readonly Q_SHA_CRED='7e0bb6e9240d53c714e58a1a252ab6da6d8b477ae00a56b62f97d55e2e88c4fd'
readonly Q_SHA_ESTADO='d585bca38af0280f8f94aedcb9040ff16b0ae9e357dbb02cc4bd8228d09b5cd0'
readonly Q_CRED='{"versao":1,"app_key":"qa-b22-ak","refresh_token":"QAB22-refresh-sintetico"}'

# _qb22_area — area temporaria do caso em A, com HOME, TMPDIR e PATH proprios.
_qb22_area() {
  A=$(mktemp -d "$DBX_TESTES_TMP/qa-b22.XXXXXX") || return 1
  mkdir -p "$A/home" "$A/tmp" "$A/bin"
}

# _qb22_git_falso — `git` no PATH da area que registra cada argumento em
# $A/git.argv e falha: nenhum teste toca a rede.
_qb22_git_falso() {
  printf '#!%s\nfor a in "$@"; do printf "%%s\\n" "$a"; done >>"%s/git.argv"\nexit 1\n' "$Q_BASH" "$A" >"$A/bin/git"
  chmod +x "$A/bin/git"
}

# _qb22_arvore <dir> <piso_maior> <piso_menor> <versao> — fonte fabricada.
_qb22_arvore() {
  mkdir -p "$1/bin" "$1/lib" "$1/commands" "$1/completions"
  printf '#!/usr/bin/env bash\nprintf "dbx qa\\n"\n' >"$1/bin/dbx"
  chmod 755 "$1/bin/dbx"
  printf 'readonly DBX_PREFLIGHT_BASH_MAIOR=%s\nreadonly DBX_PREFLIGHT_BASH_MENOR=%s\n' "$2" "$3" >"$1/lib/preflight.sh"
  printf "readonly DBX_CLI_VERSAO='%s'\n" "$4" >"$1/lib/cli.sh"
  : >"$1/commands/x.sh"
  : >"$1/completions/dbx.bash"
}

# _qb22_canal_hostil <canal> — instalador REAL com --canal, git falso, destino em $A.
_qb22_canal_hostil() {
  rm -f "$A/git.argv" "$A/saida"
  HOME="$A/home" TMPDIR="$A/tmp" PATH="$A/bin:$PATH" timeout 60 \
    "$Q_BASH" "$Q_INSTALADOR" --prefix "$A/prefixo" --canal "$1" >"$A/saida" 2>&1
  Q_STATUS=$?
}

# _qb22_credencial — credencial 0600 e estado fabricados em $A/home/.config/dropbox_sync.
_qb22_credencial() {
  mkdir -p "$A/home/.config/dropbox_sync"
  chmod 700 "$A/home/.config/dropbox_sync"
  printf '%s' "$Q_CRED" >"$A/home/.config/dropbox_sync/credencial.json"
  chmod 600 "$A/home/.config/dropbox_sync/credencial.json"
  printf 'estado-qa-b22\n' >"$A/home/.config/dropbox_sync/estado.log"
  chmod 600 "$A/home/.config/dropbox_sync/estado.log"
}

# _qb22_instantaneo <arq> — "<sha256> <modo>" do arquivo.
_qb22_instantaneo() {
  printf '%s %s' "$(sha256sum "$1" | cut -d' ' -f1)" "$(stat -c '%a' "$1")"
}

# _qb22_instalar <maior> <menor> <fonte_duplo> — executar_instalacao com o bash do
# host simulado, destino em $A/prefixo e o download substituido por um duplo que
# registra o canal em $A/canais e entrega a arvore <fonte_duplo>; o 4o argumento,
# se dado, e o --canal explicito.
_qb22_instalar() {
  HOME="$A/home" TMPDIR="$A/tmp" timeout 60 "$Q_BASH" -c '
    export DBX_INSTALL_SO_FUNCOES=1
    raiz=$1 maior=$2 menor=$3 pref=$4 dup=$5 canais=$6 explicito=$7
    set --
    . "$raiz/install.sh"
    HOST_MAIOR=$maior HOST_MENOR=$menor
    [[ -z $explicito ]] || { CANAL=$explicito; CANAL_EXPLICITO=$explicito; }
    DIR_BIN="$pref/bin" DIR_SHARE="$pref/share/dropbox_sync"
    DIR_COMPLETAR="$pref/share/bash-completion/completions"
    duplo() {
      printf "%s\n" "$1" >>"$canais"
      [[ -n $dup ]] || return 1
      RAIZ_ORIGEM=$dup
      ORIGEM_TEMPORARIA=""
    }
    FUNCAO_BAIXAR=duplo
    executar_instalacao
  ' _ "$DBX_HARNESS_RAIZ" "$1" "$2" "$A/prefixo" "$3" "$A/canais" "${4-}" >"$A/saida" 2>&1
  Q_STATUS=$?
}

# ---------------------------------------------------------------------------
# (1) --canal hostil: nada e executado, nada e escrito fora (protocolo-tdd Regra 6)
# ---------------------------------------------------------------------------

teste_qa_b22_canal_hostil_e_recusado_sem_chamar_git_nem_escrever() {
  _qb22_area
  _qb22_git_falso
  local canal
  local -a canais=(
    "x; touch $A/pwned"
    "\$(touch $A/pwned)"
    "\`touch $A/pwned\`"
    "ramo com espaco"
    "x&&touch $A/pwned"
    "x|touch $A/pwned"
    "x' ; touch '$A/pwned"
    "--upload-pack=touch $A/pwned"
    "-x"
  )
  for canal in "${canais[@]}"; do
    _qb22_canal_hostil "$canal"
    assert_igual 1 "$Q_STATUS" "canal recusado com status 1: $canal"
    assert_contem 'Canal invalido' "$(<"$A/saida")" "mensagem de recusa: $canal"
    assert_arquivo_ausente "$A/pwned" "nada do canal pode ser executado: $canal"
    assert_arquivo_ausente "$A/prefixo" "nada e escrito no destino: $canal"
    assert_arquivo_ausente "$A/git.argv" "git nao e chamado: $canal"
    assert_igual '' "$(find "$A/tmp" -mindepth 1)" "nenhuma area temporaria criada"
    assert_igual '' "$(find "$A/home" -mindepth 1)" "o HOME nao e tocado"
  done
}

teste_qa_b22_canal_com_ponto_ponto_nao_escreve_fora_do_destino() {
  _qb22_area
  _qb22_git_falso
  _qb22_canal_hostil "../../../escape"
  assert_diferente 0 "$Q_STATUS"
  assert_igual 1 "$(_harness_contar '^clone$' "$A/git.argv")" "o padrao admite o canal e o git e chamado"
  assert_arquivo_ausente "$A/prefixo"
  assert_arquivo_ausente "$A/../escape"
  assert_igual '' "$(find "$A/tmp" -mindepth 1)"
  assert_contem 'Nada foi instalado' "$(<"$A/saida")" "a falha diz que nada foi instalado"
}

teste_qa_b22_canal_vazio_e_recusado_antes_de_qualquer_acao() {
  _qb22_area
  _qb22_git_falso
  _qb22_canal_hostil ""
  assert_diferente 0 "$Q_STATUS"
  assert_contem 'Informe o branch/tag' "$(<"$A/saida")"
  assert_arquivo_ausente "$A/git.argv" "git nao e chamado"
  assert_arquivo_ausente "$A/prefixo"
}

# ---------------------------------------------------------------------------
# (2) troca de linha avisa e preserva credencial e estado (RF-203b/c; TC-B42-18/19)
# ---------------------------------------------------------------------------

teste_qa_b22_rebaixamento_avisa_e_preserva_credencial_0600() {
  _qb22_area
  _qb22_credencial
  _qb22_arvore "$A/prefixo/share/dropbox_sync" 4 4 '2.3.0'
  _qb22_arvore "$A/duplo" 4 2 '2.3.0-bash42'
  local antes depois listagem_antes
  antes=$(_qb22_instantaneo "$A/home/.config/dropbox_sync/credencial.json")
  listagem_antes=$(find "$A/home" | sort)
  _qb22_instalar 4 2 "$A/duplo"
  assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
  assert_contem 'TROCA DE LINHA' "$(<"$A/saida")" "RF-203c: aviso destacado"
  assert_contem 'linha legada' "$(<"$A/saida")"
  assert_igual 1 "$(_harness_contar '^support/bash-4.2$' "$A/canais")" "baixou so a legada, uma vez"
  assert_igual 1 "$(_harness_contar 'bash42' "$A/prefixo/share/dropbox_sync/lib/cli.sh")" "a legada sobrescreveu a principal"
  depois=$(_qb22_instantaneo "$A/home/.config/dropbox_sync/credencial.json")
  assert_igual "$antes" "$depois" "credencial com o mesmo conteudo e modo"
  assert_igual "$Q_SHA_CRED 600" "$depois" "0600 e conteudo fabricado"
  assert_igual "$listagem_antes" "$(find "$A/home" | sort)" "nada novo em ~/.config nem no HOME"
}

teste_qa_b22_promocao_avisa_preserva_credencial_e_nao_baixa() {
  _qb22_area
  _qb22_credencial
  _qb22_arvore "$A/prefixo/share/dropbox_sync" 4 2 '2.3.0-bash42'
  local antes depois
  antes=$(_qb22_instantaneo "$A/home/.config/dropbox_sync/estado.log")
  _qb22_instalar 5 1 ""
  assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
  assert_contem 'TROCA DE LINHA' "$(<"$A/saida")"
  assert_contem 'linha principal' "$(<"$A/saida")"
  assert_arquivo_ausente "$A/canais" "fonte local compativel: nenhum download (RF-202d)"
  assert_igual 0 "$(_harness_contar 'bash42' "$A/prefixo/share/dropbox_sync/lib/cli.sh")" "a principal sobrescreveu a legada"
  depois=$(_qb22_instantaneo "$A/home/.config/dropbox_sync/estado.log")
  assert_igual "$antes" "$depois" "estado com o mesmo conteudo e modo 0600"
  assert_igual "$Q_SHA_ESTADO 600" "$depois"
  assert_igual "$Q_SHA_CRED 600" "$(_qb22_instantaneo "$A/home/.config/dropbox_sync/credencial.json")"
}

teste_qa_b22_reinstalar_a_mesma_linha_nao_emite_aviso_de_troca() {
  _qb22_area
  _qb22_arvore "$A/prefixo/share/dropbox_sync" 4 4 '2.3.0'
  _qb22_instalar 5 1 ""
  assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
  assert_nao_contem 'TROCA DE LINHA' "$(<"$A/saida")"
}

teste_qa_b22_instalacao_nova_sem_linha_anterior_nao_emite_aviso() {
  _qb22_area
  _qb22_instalar 5 1 ""
  assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
  assert_nao_contem 'TROCA DE LINHA' "$(<"$A/saida")"
  assert_arquivo_existe "$A/prefixo/bin/dbx"
}

# ---------------------------------------------------------------------------
# (3) fonte local invalida e recusada sem escrever no destino (RF-201b, RF-202)
# ---------------------------------------------------------------------------

# _qb22_fonte_local — copia do instalador com a arvore real em $A/fonte.
_qb22_fonte_local() {
  mkdir -p "$A/fonte"
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" \
    "$DBX_HARNESS_RAIZ/completions" "$A/fonte/"
  cp "$Q_INSTALADOR" "$A/fonte/install.sh"
}

# _qb22_rodar_fonte_local — roda a copia, sem rede, com destino em $A/prefixo.
_qb22_rodar_fonte_local() {
  HOME="$A/home" TMPDIR="$A/tmp" PATH="$A/bin:$PATH" timeout 60 \
    "$Q_BASH" "$A/fonte/install.sh" --prefix "$A/prefixo" >"$A/saida" 2>&1
  Q_STATUS=$?
}

teste_qa_b22_fonte_local_sem_preflight_e_recusada_sem_escrever() {
  _qb22_area
  _qb22_git_falso
  _qb22_fonte_local
  rm -f "$A/fonte/lib/preflight.sh"
  _qb22_rodar_fonte_local
  assert_diferente 0 "$Q_STATUS"
  assert_contem 'Fonte invalida' "$(<"$A/saida")"
  assert_arquivo_ausente "$A/prefixo" "nada escrito no destino"
  assert_arquivo_ausente "$A/git.argv" "sem piso a fonte local nao vira download"
}

teste_qa_b22_fonte_local_com_piso_ilegivel_por_modo_e_recusada_sem_escrever() {
  [[ $(id -u) -ne 0 ]] || pular 'root le arquivo de modo 000'
  _qb22_area
  _qb22_git_falso
  _qb22_fonte_local
  chmod 000 "$A/fonte/lib/preflight.sh"
  _qb22_rodar_fonte_local
  chmod 644 "$A/fonte/lib/preflight.sh"
  assert_diferente 0 "$Q_STATUS"
  assert_contem 'Fonte invalida' "$(<"$A/saida")"
  assert_arquivo_ausente "$A/prefixo"
}

teste_qa_b22_fonte_local_com_piso_malformado_e_recusada_sem_escrever() {
  _qb22_area
  _qb22_git_falso
  local conteudo
  for conteudo in '' 'readonly DBX_PREFLIGHT_BASH_MAIOR=4' 'readonly DBX_PREFLIGHT_BASH_MAIOR=abc
readonly DBX_PREFLIGHT_BASH_MENOR=4'; do
    rm -rf "$A/fonte" "$A/prefixo"
    _qb22_fonte_local
    printf '%s\n' "$conteudo" >"$A/fonte/lib/preflight.sh"
    _qb22_rodar_fonte_local
    assert_diferente 0 "$Q_STATUS" "piso malformado: [$conteudo]"
    assert_contem 'Fonte invalida' "$(<"$A/saida")"
    assert_arquivo_ausente "$A/prefixo" "nada escrito no destino"
  done
}

teste_qa_b22_fonte_baixada_com_piso_acima_do_host_e_recusada_com_ou_sem_canal_explicito() {
  _qb22_area
  _qb22_arvore "$A/duplo" 4 4 '2.3.0'
  local explicito
  for explicito in master ''; do
    rm -rf "$A/prefixo" "$A/canais"
    _qb22_instalar 4 2 "$A/duplo" "$explicito"
    assert_diferente 0 "$Q_STATUS" "canal [$explicito]"
    assert_contem 'exige bash 4.4' "$(<"$A/saida")" "nomeia o piso da fonte"
    assert_contem 'support/bash-4.2' "$(<"$A/saida")" "nomeia o canal certo (DIV-385)"
    assert_arquivo_ausente "$A/prefixo/share" "nada escrito no destino"
    assert_arquivo_ausente "$A/prefixo/bin" "nenhum executavel no destino"
    assert_igual 1 "$(_harness_contar '.' "$A/canais")" "uma unica tentativa de download"
  done
}

teste_qa_b22_fonte_baixada_sem_piso_e_recusada_antes_de_escrever() {
  _qb22_area
  mkdir -p "$A/duplo/bin" "$A/duplo/lib" "$A/duplo/commands" "$A/duplo/completions"
  : >"$A/duplo/bin/dbx"
  _qb22_instalar 4 2 "$A/duplo"
  assert_diferente 0 "$Q_STATUS"
  assert_contem 'Fonte invalida' "$(<"$A/saida")"
  assert_arquivo_ausente "$A/prefixo/share" "nada escrito no destino"
  assert_igual '' "$(find "$A/tmp" -mindepth 1)"
}

# ---------------------------------------------------------------------------
# (4) escolher_linha nas bordas (RF-201a; TC-B42-10, 11)
# ---------------------------------------------------------------------------

teste_qa_b22_escolher_linha_em_entradas_limite() {
  local saida
  saida=$(DBX_INSTALL_SO_FUNCOES=1 "$Q_BASH" -c '
    raiz=$1
    set --
    . "$raiz/install.sh"
    for v in "0 0" "3 99" "4 0" "4 1" "4 2" "4 3" "4 4" "4 5" "4 10" "5 0" "10 0"; do
      # shellcheck disable=SC2086
      printf "%s=%s " "${v// /.}" "$(escolher_linha $v)"
    done' _ "$DBX_HARNESS_RAIZ")
  assert_igual '0.0=recusa 3.99=recusa 4.0=recusa 4.1=recusa 4.2=legada 4.3=legada 4.4=principal 4.5=principal 4.10=principal 5.0=principal 10.0=principal ' "$saida"
}

teste_qa_b22_recusa_abaixo_do_piso_absoluto_nao_escreve_e_nomeia_versao_e_minimo() {
  _qb22_area
  _qb22_instalar 4 1 ""
  assert_igual 1 "$Q_STATUS"
  assert_contem '4.1' "$(<"$A/saida")" "nomeia a versao detectada"
  assert_contem '4.2' "$(<"$A/saida")" "nomeia o minimo"
  assert_arquivo_ausente "$A/prefixo" "nada escrito"
  assert_arquivo_ausente "$A/canais" "nenhum download"
}

# ---------------------------------------------------------------------------
# (5) empacotar.sh: --latest=false so na legada, --target sempre (RF-205b)
# ---------------------------------------------------------------------------

# _qb22_publicar <versao> <novo|existente> — copia temporaria do projeto com a
# versao dada, git proprio e `gh` falso que registra cada chamada em $A/gh.log.
_qb22_publicar() {
  local versao=$1 modo=$2 proj="$A/proj"
  mkdir -p "$proj/scripts" "$proj/docs/releases"
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" \
    "$DBX_HARNESS_RAIZ/completions" "$proj/"
  cp "$Q_INSTALADOR" "$DBX_HARNESS_RAIZ/uninstall.sh" "$DBX_HARNESS_RAIZ/README.md" \
    "$DBX_HARNESS_RAIZ/LICENSE" "$proj/"
  cp "$DBX_HARNESS_RAIZ/scripts/empacotar.sh" "$proj/scripts/"
  sed -i "s/^readonly DBX_CLI_VERSAO=.*/readonly DBX_CLI_VERSAO='$versao'/" "$proj/lib/cli.sh"
  printf '# Titulo\ncorpo\n' >"$proj/docs/releases/v$versao.md"
  git -C "$proj" init -q
  git -C "$proj" -c user.email=qa@qa -c user.name=qa commit -q --allow-empty -m qa
  Q_SHA=$(git -C "$proj" rev-parse HEAD)
  if [[ $modo == existente ]]; then
    printf '#!%s\nprintf "%%s\\n" "$*" >>"%s/gh.log"\nexit 0\n' "$Q_BASH" "$A" >"$A/bin/gh"
  else
    printf '#!%s\nprintf "%%s\\n" "$*" >>"%s/gh.log"\n[ "$1 $2" = "release view" ] && exit 1\nexit 0\n' "$Q_BASH" "$A" >"$A/bin/gh"
  fi
  chmod +x "$A/bin/gh"
  PATH="$A/bin:$PATH" TMPDIR="$A/tmp" timeout 120 "$Q_BASH" "$proj/scripts/empacotar.sh" --publicar >"$A/saida" 2>&1
  Q_STATUS=$?
}

teste_qa_b22_release_da_legada_passa_latest_false_e_target_do_head() {
  _qb22_area
  local sha_cli_antes
  sha_cli_antes=$(sha256sum "$DBX_HARNESS_RAIZ/lib/cli.sh" | cut -d' ' -f1)
  local v
  for v in 2.3.0-bash42 9.9.9-bash42 2.3.0-bash42-rc1; do
    rm -rf "$A/proj" "$A/gh.log"
    _qb22_publicar "$v" novo
    assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
    assert_igual 1 "$(_harness_contar '^release create ' "$A/gh.log")" "uma criacao de release"
    assert_igual 1 "$(_harness_contar '--latest=false' "$A/gh.log")" "RF-205b: nunca Latest: $v"
    assert_igual 1 "$(_harness_contar "--target $Q_SHA" "$A/gh.log")" "a tag nasce no HEAD empacotado: $v"
    assert_igual 1 "$(_harness_contar "^release create v$v " "$A/gh.log")" "a tag e v$v"
  done
  assert_igual "$sha_cli_antes" "$(sha256sum "$DBX_HARNESS_RAIZ/lib/cli.sh" | cut -d' ' -f1)" "o lib/cli.sh do worktree nao foi tocado"
}

teste_qa_b22_release_da_principal_tem_target_e_nao_tem_latest_false() {
  _qb22_area
  _qb22_publicar 2.3.0 novo
  assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
  assert_igual 1 "$(_harness_contar "--target $Q_SHA" "$A/gh.log")" "o alvo e sempre o commit empacotado"
  assert_igual 0 "$(_harness_contar '--latest' "$A/gh.log")" "a principal segue como Latest por padrao"
}

teste_qa_b22_release_existente_edita_e_nao_cria_outra() {
  _qb22_area
  _qb22_publicar 2.3.0-bash42 existente
  assert_igual 0 "$Q_STATUS" "$(<"$A/saida")"
  assert_igual 0 "$(_harness_contar '^release create ' "$A/gh.log")" "nao recria a release"
  assert_igual 1 "$(_harness_contar '^release edit .*--latest=false' "$A/gh.log")" "reenvia as notas sem virar Latest"
  assert_igual 1 "$(_harness_contar '^release upload ' "$A/gh.log")" "reenvia os artefatos"
}

harness_executar "$@"
