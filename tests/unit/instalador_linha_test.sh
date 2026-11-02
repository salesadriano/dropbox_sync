#!/usr/bin/env bash
# Testes do `install.sh`: escolha da linha de produto pelo bash do host
# (RF-201 a RF-203, TC-B42-09..19). Sem rede: o download e isolado em
# `baixar_fonte` (apontada por FUNCAO_BAIXAR), que cada caso substitui por um duplo que copia uma arvore
# fabricada. O instalador e carregado por `.` com DBX_INSTALL_SO_FUNCOES=1.

# shellcheck disable=SC2016,SC2183
# Justificativa: roteiros e duplos entregues como texto literal a "bash -c" e a
# arquivos gerados; a expansao ocorre no processo filho.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

# _arvore <piso_maior> <piso_menor> — fonte fabricada (bin, lib, commands, completions)
_arvore() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/instalador.XXXXXX") || return 1
  mkdir -p "$dir/bin" "$dir/lib" "$dir/commands" "$dir/completions"
  printf '#!/usr/bin/env bash\nprintf "dbx %s\\n" "${DBX_FAKE_VERSAO:-x}"\n' >"$dir/bin/dbx"
  chmod 755 "$dir/bin/dbx"
  printf 'readonly DBX_PREFLIGHT_BASH_MAIOR=%s\nreadonly DBX_PREFLIGHT_BASH_MENOR=%s\n' "$1" "$2" >"$dir/lib/preflight.sh"
  printf 'readonly DBX_CLI_VERSAO=%s\n' "'${3:-2.3.0}'" >"$dir/lib/cli.sh"
  : >"$dir/commands/x.sh"
  : >"$dir/completions/dbx.bash"
  printf '%s' "$dir"
}

# _instalador <maior> <menor> <fonte_local> <script> — roda <script> com o
# instalador carregado, o bash do host simulado e o download substituido.
# $DBX_T_CANAIS recebe o canal de cada download tentado.
_instalador() {
  local maior=$1 menor=$2 fonte=$3 roteiro=$4
  timeout 60 bash -c '
    export DBX_INSTALL_SO_FUNCOES=1
    raiz=$1 maior=$2 menor=$3 DBX_T_CANAIS=$5
    set --
    . "$raiz/install.sh"
    HOST_MAIOR=$maior HOST_MENOR=$menor
    set +e
    # Duplo unico de download: devolve a arvore de DUPLO_FONTE (vazia = sem rede)
    # e registra o canal pedido em $DBX_T_CANAIS.
    duplo_baixar() {
      printf "%s\n" "$1" >>"$DBX_T_CANAIS"
      [[ -n ${DUPLO_FONTE:-} ]] || return 1
      RAIZ_ORIGEM=$DUPLO_FONTE
      ORIGEM_TEMPORARIA=""
    }
    '"$roteiro"'
  ' _ "$DBX_HARNESS_RAIZ" "$maior" "$menor" "$fonte" "$(mktemp "$DBX_TESTES_TMP/canais.XXXXXX")" 2>&1
}

# ---------------------------------------------------------------------------
# escolher_linha (RF-201a, TC-B42-09, 10, 11)
# ---------------------------------------------------------------------------

teste_escolha_da_linha_por_versao_do_bash() {
  local saida
  saida=$(_instalador 5 2 "" '
    for v in "3 2" "4 1" "4 2" "4 3" "4 4" "5 2"; do
      # shellcheck disable=SC2086
      printf "%s=%s " "${v// /.}" "$(escolher_linha $v)"
    done')
  assert_igual '3.2=recusa 4.1=recusa 4.2=legada 4.3=legada 4.4=principal 5.2=principal ' "$saida"
}

teste_canais_da_linha_tem_nome_fixo() {
  local saida
  saida=$(_instalador 5 2 "" 'printf "%s|%s" "$CANAL_PRINCIPAL" "$CANAL_LEGADO"')
  assert_igual 'master|support/bash-4.2' "$saida"
}

# ---------------------------------------------------------------------------
# piso_da_fonte (RF-201b, TC-B42-12)
# ---------------------------------------------------------------------------

teste_piso_e_lido_do_preflight_da_propria_fonte() {
  local fonte saida
  fonte=$(_arvore 4 7)
  saida=$(_instalador 5 2 "" "piso_da_fonte '$fonte'")
  assert_igual '4 7' "$saida" 'o piso vem do lib/preflight.sh fabricado, nao de constante do instalador'
}

teste_fonte_sem_piso_legivel_e_invalida() {
  local fonte saida
  fonte=$(_arvore 4 4)
  : >"$fonte/lib/preflight.sh"
  saida=$(_instalador 5 2 "" "piso_da_fonte '$fonte' || printf invalida")
  assert_igual 'invalida' "$saida"
}

teste_instalador_nao_copia_piso_nem_detecta_so_por_uname() {
  local fonte_instalador
  fonte_instalador=$(grep -v '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/install.sh")
  assert_nao_contem 'uname' "$fonte_instalador" 'RNF-39: sem uname'
  assert_nao_contem 'OSTYPE' "$fonte_instalador" 'RNF-39: sem OSTYPE'
  assert_contem 'DBX_PREFLIGHT_BASH_MAIOR' "$fonte_instalador" 'le o piso da fonte'
}

# ---------------------------------------------------------------------------
# Bash 4.1: recusa sem escrever (RF-201a, TC-B42-11)
# ---------------------------------------------------------------------------

teste_bash_41_recusa_com_a_versao_e_o_minimo() {
  local dest saida status
  dest="$DBX_TESTES_TMP/dest41"
  saida=$(_instalador 4 1 "" "
    DIR_BIN='$dest/bin' DIR_SHARE='$dest/share'
    ( verificar_prerequisitos ); printf 'status=%s' \$?")
  status=${saida##*status=}
  assert_igual 1 "$status"
  assert_contem '4.1' "$saida" 'nomeia a versao detectada'
  assert_contem '4.2' "$saida" 'nomeia o minimo'
  assert_arquivo_ausente "$dest"
}

# ---------------------------------------------------------------------------
# Execucao local (RF-202a/b/d, TC-B42-13, 14, 16)
# ---------------------------------------------------------------------------

teste_fonte_local_incompativel_cai_no_remoto_com_o_canal_da_linha() {
  local local_p dest saida legada
  local_p=$(_arvore 4 4)
  legada=$(_arvore 4 2 2.3.0-bash42)
  dest="$DBX_TESTES_TMP/dest13"
  saida=$(_instalador 4 2 "$local_p" "
    CANAL_EXPLICITO='' FUNCAO_BAIXAR=duplo_baixar DUPLO_FONTE='$legada'
    verificar_prerequisitos >/dev/null
    obter_raiz_origem '$local_p' >/dev/null
    printf 'raiz=%s canal=%s' \"\$RAIZ_ORIGEM\" \"\$(cat \"\$DBX_T_CANAIS\")\"")
  assert_contem "raiz=$legada" "$saida"
  assert_contem 'canal=support/bash-4.2' "$saida"
}

teste_fonte_local_compativel_nao_baixa_nada() {
  local local_p saida
  local_p=$(_arvore 4 4)
  saida=$(_instalador 5 2 "$local_p" "
    CANAL_EXPLICITO='' FUNCAO_BAIXAR=duplo_baixar
    verificar_prerequisitos >/dev/null
    obter_raiz_origem '$local_p' >/dev/null
    printf 'raiz=%s' \"\$RAIZ_ORIGEM\"")
  assert_igual "raiz=$local_p" "$saida"
}

teste_sem_rede_falha_com_o_comando_manual_do_canal_certo_e_nada_escrito() {
  local local_p dest saida status
  local_p=$(_arvore 4 4)
  dest="$DBX_TESTES_TMP/dest14"
  saida=$(_instalador 4 2 "$local_p" "
    DIR_BIN='$dest/bin' DIR_SHARE='$dest/share'
    CANAL_EXPLICITO='' FUNCAO_BAIXAR=duplo_baixar
    ( verificar_prerequisitos >/dev/null; obter_raiz_origem '$local_p' ); printf 'status=%s' \$?")
  status=${saida##*status=}
  assert_diferente 0 "$status"
  assert_contem 'support/bash-4.2/install.sh | bash' "$saida" 'comando manual do canal certo'
  assert_arquivo_ausente "$dest"
}

# ---------------------------------------------------------------------------
# --canal incompativel (RF-202c, DIV-385 A, TC-B42-15)
# ---------------------------------------------------------------------------

teste_canal_incompativel_e_recusado_nomeando_o_canal_certo_sem_escrever() {
  local principal dest saida status
  principal=$(_arvore 4 4)
  dest="$DBX_TESTES_TMP/dest15"
  saida=$(_instalador 4 2 "" "
    DIR_BIN='$dest/bin' DIR_SHARE='$dest/share'
    CANAL=master CANAL_EXPLICITO=master FUNCAO_BAIXAR=duplo_baixar DUPLO_FONTE='$principal'
    ( verificar_prerequisitos >/dev/null; obter_raiz_origem '' >/dev/null ); printf 'status=%s' \$?")
  status=${saida##*status=}
  assert_igual 1 "$status"
  assert_contem 'support/bash-4.2' "$saida" 'nomeia o canal certo'
  assert_arquivo_ausente "$dest"
}

# ---------------------------------------------------------------------------
# Troca de linha (RF-203, TC-B42-17, 19)
# ---------------------------------------------------------------------------

teste_rebaixamento_de_linha_avisa_de_forma_destacada() {
  local dest saida
  dest="$DBX_TESTES_TMP/dest19"
  mkdir -p "$dest/share/lib"
  printf "readonly DBX_CLI_VERSAO='2.3.0'\n" >"$dest/share/lib/cli.sh"
  saida=$(_instalador 4 2 "" "
    DIR_SHARE='$dest/share'
    LINHA=legada
    avisar_troca_de_linha")
  assert_contem 'TROCA DE LINHA' "$saida"
  assert_contem 'principal' "$saida"
  assert_contem 'legada' "$saida"
}

teste_mesma_linha_ou_primeira_instalacao_nao_avisa_troca() {
  local dest saida
  dest="$DBX_TESTES_TMP/dest17"
  saida=$(_instalador 4 4 "" "
    DIR_SHARE='$dest/share'
    LINHA=principal
    avisar_troca_de_linha")
  assert_nao_contem 'TROCA DE LINHA' "$saida" 'primeira instalacao nao e troca'
}

teste_subida_da_legada_para_a_principal_informa_a_troca() {
  local dest saida
  dest="$DBX_TESTES_TMP/dest17b"
  mkdir -p "$dest/share/lib"
  printf "readonly DBX_CLI_VERSAO='2.3.0-bash42'\n" >"$dest/share/lib/cli.sh"
  saida=$(_instalador 4 4 "" "
    DIR_SHARE='$dest/share'
    LINHA=principal
    avisar_troca_de_linha")
  assert_contem 'legada' "$saida"
  assert_contem 'principal' "$saida"
}

# ---------------------------------------------------------------------------
# Empacotador (RF-205, TC-B42-21, 22; DIV-390)
# ---------------------------------------------------------------------------

# _publicar <versao> — roda `empacotar.sh --publicar` numa copia do projeto com a
# versao dada e um `gh` falso; imprime os argumentos de `gh release create`.
_publicar() {
  local versao=$1 proj bin
  proj=$(mktemp -d "$DBX_TESTES_TMP/pacote.XXXXXX") || return 1
  bin="$proj/fakebin"
  mkdir -p "$bin" "$proj/scripts" "$proj/docs/releases"
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" \
    "$DBX_HARNESS_RAIZ/completions" "$proj/"
  cp "$DBX_HARNESS_RAIZ/install.sh" "$DBX_HARNESS_RAIZ/uninstall.sh" "$DBX_HARNESS_RAIZ/README.md" \
    "$DBX_HARNESS_RAIZ/LICENSE" "$proj/"
  cp "$DBX_HARNESS_RAIZ/scripts/empacotar.sh" "$proj/scripts/"
  sed -i "s/^readonly DBX_CLI_VERSAO=.*/readonly DBX_CLI_VERSAO='$versao'/" "$proj/lib/cli.sh"
  printf '# Titulo\ncorpo\n' >"$proj/docs/releases/v$versao.md"
  (cd "$proj" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m x)
  printf '#!/bin/sh\n[ "$1 $2" = "release view" ] && exit 1\nprintf "%%s\\n" "$*" >>"%s/gh.log"\n' "$proj" >"$bin/gh"
  chmod +x "$bin/gh"
  PATH="$bin:$PATH" bash "$proj/scripts/empacotar.sh" --publicar >/dev/null 2>&1 || { printf 'FALHOU'; return 0; }
  printf '%s|%s' "$(cat "$proj/gh.log")" "$(cd "$proj" && git rev-parse HEAD)"
}

teste_release_aponta_a_tag_para_o_commit_de_head() {
  local saida
  saida=$(_publicar 2.3.0)
  assert_contem "--target ${saida##*|}" "$saida" 'a tag nasce no HEAD, nao no ramo padrao'
  assert_nao_contem '--latest=false' "$saida" 'a principal continua a Latest'
}

teste_release_da_legada_nao_e_marcada_latest() {
  local saida
  saida=$(_publicar 2.3.0-bash42)
  assert_contem '--latest=false' "$saida" 'RF-205b'
  assert_contem "--target ${saida##*|}" "$saida"
  assert_contem 'v2.3.0-bash42' "$saida" 'o sufixo nao quebra a tag nem o teste do pacote'
}

# ---------------------------------------------------------------------------
# Suite no CentOS 7 (RF-206)
# ---------------------------------------------------------------------------

teste_suite_bash42_sem_docker_falha_dizendo_como_obter() {
  local saida status vazio
  vazio=$(mktemp -d "$DBX_TESTES_TMP/semdocker.XXXXXX")
  saida=$(PATH="$vazio" /bin/sh "$DBX_HARNESS_RAIZ/scripts/suite-bash42.sh" preflight 2>&1) && status=0 || status=$?
  assert_diferente 0 "$status"
  assert_contem 'docker' "$saida"
  assert_contem 'centos:7@sha256:be65f488b7764ad3638f236b7b515b3678369a5124c47b8d32916d6487418ea4' "$saida" 'digest fixado na mensagem'
}

teste_suite_bash42_monta_o_comando_do_container_com_a_imagem_por_digest() {
  local fake saida
  fake=$(mktemp -d "$DBX_TESTES_TMP/fakedocker.XXXXXX")
  printf '#!/bin/sh\n[ "$1" = image ] && exit 0\nprintf "%%s\\n" "$*"\n' >"$fake/docker"
  chmod +x "$fake/docker"
  saida=$(PATH="$fake:$PATH" sh "$DBX_HARNESS_RAIZ/scripts/suite-bash42.sh" preflight 2>&1)
  assert_contem 'run --rm --user ' "$saida" 'conteiner com o usuario do host, nao root (testes de permissao)'
  assert_contem ' -e HOME=/tmp -v ' "$saida"
  assert_contem ':/src -w /src centos:7@sha256:be65f488b7764ad3638f236b7b515b3678369a5124c47b8d32916d6487418ea4 bash tests/run.sh preflight' "$saida"
}

# Achado menor do QA (ciclo 1): o canal vai ao comando manual sugerido ao
# usuario; so nome de ref e aceito, antes de qualquer acao.
teste_canal_com_trecho_de_shell_e_recusado_antes_de_qualquer_acao() {
  local saida status=0
  saida=$(timeout 60 bash "$DBX_HARNESS_RAIZ/install.sh" --prefix "$DBX_TESTES_TMP/nao-criar" --canal 'x; echo PWN' 2>&1) || status=$?
  assert_igual 1 "$status" 'canal invalido sai com 1'
  assert_contem 'Canal invalido' "$saida"
  assert_nao_contem 'PWN' "${saida#*Canal invalido}" 'o trecho nao e ecoado como comando'
  assert_arquivo_ausente "$DBX_TESTES_TMP/nao-criar"
}

teste_linha_instalada_reconhece_so_o_sufixo_bash42_exato() {
  local raiz saida
  raiz=$DBX_HARNESS_RAIZ
  saida=$(timeout 60 bash -c '
    export DBX_INSTALL_SO_FUNCOES=1
    raiz=$1 area=$2
    set --
    . "$raiz/install.sh"
    for v in 2.3.0-bash42 2.3.0-bash42-rc1 2.3.0-bash42.1 2.3.0-bash420 2.3.0; do
      mkdir -p "$area/$v/lib"
      printf "readonly DBX_CLI_VERSAO=%s\n" "'"'"'$v'"'"'" >"$area/$v/lib/cli.sh"
      printf "%s=%s " "$v" "$(linha_instalada "$area/$v")"
    done
  ' _ "$raiz" "$DBX_TESTES_TMP/versoes" 2>&1)
  assert_igual '2.3.0-bash42=legada 2.3.0-bash42-rc1=legada 2.3.0-bash42.1=legada 2.3.0-bash420=principal 2.3.0=principal ' "$saida"
}

harness_executar "$@"
