#!/usr/bin/env bash
# Testes de COMPOSICAO entre componentes.
#
# Razao de existir: a suite chegou a 237 casos sem nenhum que cruzasse
# componentes, e foi exatamente ali que o QF-01 se escondeu — cada componente
# individualmente correto, o defeito existindo so em cadeia. Uma guarda tinha
# sido aplicada a um caminho e nao ao irmao, e nenhum teste de unidade podia
# enxergar isso, porque nenhum olhava para os dois ao mesmo tempo.
#
# Os eixos abaixo sao os que o QA sondou a mao no parecer final, mais o caminho
# que produziu o QF-01 e a auditoria de procedencia exigida por RNF-24.

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a "bash -c", que precisa chegar
# sem expansao ao processo filho.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

DBX_LIB="$DBX_HARNESS_RAIZ/lib"

# ---------------------------------------------------------------------------
# Eixo 1 — ordens de carregamento
# ---------------------------------------------------------------------------

teste_qualquer_ordem_de_carregamento_funciona() {
  # Os componentes se carregam entre si por caminho relativo e usam guarda de
  # carga. Nenhuma ordem pode quebrar, senao a ordem vira contrato implicito.
  local ordem saida
  local -a ordens=(
    'errors path hash json output'
    'output json hash path errors'
    'json errors output path hash'
    'hash output errors json path'
    'path hash json output errors'
    'output errors json path hash'
  )
  for ordem in "${ordens[@]}"; do
    saida=$(timeout 30 bash -c '
      for componente in $2; do . "$1/$componente.sh" || exit 1; done
      dbx_json_analisar "{\"a\":1}" || exit 2
      dbx_json_valor a >/dev/null || exit 3
      printf "%s" "$DBX_JSON_RESULTADO"
    ' _ "$DBX_LIB" "$ordem" 2>&1)
    assert_igual '1' "$saida" "ordem de carregamento falhou: [$ordem]"
  done
}

teste_carga_multipla_e_idempotente() {
  local saida
  saida=$(timeout 30 bash -c '
    for _ in 1 2 3; do
      . "$1/errors.sh" && . "$1/path.sh" && . "$1/hash.sh" &&
        . "$1/json.sh" && . "$1/output.sh" || exit 1
    done
    dbx_json_analisar "{\"a\":1}" || exit 2
    dbx_json_valor a >/dev/null || exit 3
    printf "%s" "$DBX_JSON_RESULTADO"
  ' _ "$DBX_LIB" 2>&1)
  assert_igual '1' "$saida" 'carga tripla precisa ser inofensiva (guarda de carga)'
}

# ---------------------------------------------------------------------------
# Eixo 2 — espaco de nomes global
# ---------------------------------------------------------------------------

teste_nenhuma_global_sem_prefixo_do_projeto() {
  # Global sem prefixo colide com o ambiente do usuario e com outros scripts.
  # As variaveis mantidas pelo proprio `bash` sao excluidas: elas aparecem por
  # causa da sonda, e nao da biblioteca — a sonda estava se medindo.
  local achados
  achados=$(timeout 30 bash -c '
    antes=$(compgen -v | sort)
    . "$1/errors.sh"; . "$1/path.sh"; . "$1/hash.sh"; . "$1/json.sh"; . "$1/output.sh"
    depois=$(compgen -v | sort)
    comm -13 <(printf "%s\n" "$antes") <(printf "%s\n" "$depois") |
      grep -vE "^(DBX_|_dbx_)" |
      grep -vE "^(antes|depois|componente|_)$" |
      grep -vE "^(PIPESTATUS|BASH_REMATCH|OPTIND|OPTARG|REPLY|FUNCNAME)$" || true
  ' _ "$DBX_LIB" 2>/dev/null)
  assert_igual '' "$achados" "globais sem prefixo do projeto: $achados"
}

teste_nenhuma_funcao_publica_colide() {
  local duplicadas
  duplicadas=$(timeout 30 bash -c '
    . "$1/errors.sh"; . "$1/path.sh"; . "$1/hash.sh"; . "$1/json.sh"; . "$1/output.sh"
    declare -F | awk "{print \$3}" | grep "^dbx_" | sort | uniq -d
  ' _ "$DBX_LIB" 2>/dev/null)
  assert_igual '' "$duplicadas" "funcoes publicas com nome repetido: $duplicadas"
}

teste_toda_funcao_publica_tem_prefixo_do_projeto() {
  local sem_prefixo
  sem_prefixo=$(timeout 30 bash -c '
    antes=$(declare -F | awk "{print \$3}" | sort)
    . "$1/errors.sh"; . "$1/path.sh"; . "$1/hash.sh"; . "$1/json.sh"; . "$1/output.sh"
    declare -F | awk "{print \$3}" | sort |
      comm -13 <(printf "%s\n" "$antes") - | grep -vE "^_?dbx_" || true
  ' _ "$DBX_LIB" 2>/dev/null)
  assert_igual '' "$sem_prefixo" "funcoes sem prefixo do projeto: $sem_prefixo"
}

# ---------------------------------------------------------------------------
# Eixo 3 — coerencia dos codigos de saida entre componentes
# ---------------------------------------------------------------------------

teste_codigos_de_saida_concordam_entre_componentes() {
  # Cada componente deriva seus status da taxonomia. Um status propagado nunca
  # pode significar duas coisas.
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/path.sh"
  . "$DBX_LIB/hash.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/output.sh"

  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_PATH_USO_INVALIDO"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_PATH_CONFIGURACAO"
  assert_igual "$(dbx_errors_codigo_saida caminho_recusado)" "$DBX_PATH_RECUSADO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_HASH_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_HASH_ERRO_DEPENDENCIA"
  assert_igual "$(dbx_errors_codigo_saida nao_encontrado)" "$DBX_HASH_ERRO_ORIGEM"
  assert_igual "$(dbx_errors_codigo_saida desconhecido)" "$DBX_HASH_ERRO_RESUMO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_JSON_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida erro_remoto)" "$DBX_JSON_ERRO_REMOTO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_OUTPUT_ERRO_USO"
}

# ---------------------------------------------------------------------------
# Eixo 4 — QF-01: guarda aplicada a um caminho precisa valer para o irmao
# ---------------------------------------------------------------------------

teste_ambos_os_canais_de_saida_recusam_valor_que_parte_o_registro() {
  # Foi aqui que o QF-01 se escondeu: a guarda de fronteira existia no canal de
  # resultado e nao no de diagnostico, e o consumidor lia CAMPO FORJADO,
  # escolhido por quem controla a resposta remota.
  local multilinha=$'path/not_found/.\nhttp_status=200\nresultado=sucesso'

  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/path.sh"
  . "$DBX_LIB/output.sh"

  dbx_output_iniciar
  dbx_output_modo estruturada
  dbx_output_campo http_status 409
  dbx_output_campo detalhe "$multilinha"
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_render

  dbx_output_iniciar
  dbx_output_modo estruturada
  dbx_output_diagnostico http_status 409
  dbx_output_diagnostico detalhe "$multilinha"
  assert_status "$DBX_OUTPUT_ERRO_USO" dbx_output_render_diagnostico
}

teste_nenhum_canal_emite_registro_forjado_antes_de_recusar() {
  local multilinha=$'x\nhttp_status=200' saida
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/path.sh"
  . "$DBX_LIB/output.sh"
  dbx_output_iniciar
  dbx_output_modo estruturada
  dbx_output_diagnostico http_status 409
  dbx_output_diagnostico detalhe "$multilinha"
  saida=$(dbx_output_render_diagnostico 2>&1 || true)
  assert_nao_contem 'http_status=200' "$saida" \
    'nenhum registro pode sair antes de a validacao reprovar'
}

teste_cadeia_json_para_saida_preserva_o_valor() {
  # Caminho real: interpretar resposta e emitir resultado, ponta a ponta.
  local saida
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/path.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/output.sh"
  dbx_json_analisar '{"entries":[{"name":"com espaco.txt","size":42}]}'
  dbx_json_valor entries 0 name >/dev/null
  dbx_output_iniciar
  dbx_output_modo estruturada
  dbx_output_campo caminho "$DBX_JSON_RESULTADO"
  saida=$(dbx_output_render)
  assert_contem 'caminho=com espaco.txt' "$saida"
}

# ---------------------------------------------------------------------------
# Eixo 5 — cobertura de irmaos: guarda em uma funcao vale para as congeneres
# ---------------------------------------------------------------------------

teste_toda_consulta_de_json_recusa_sem_documento_analisado() {
  # Generaliza a pergunta que o QF-01 levantou: uma guarda aplicada a uma
  # funcao precisa valer para todas as suas congeneres.
  local saida
  saida=$(timeout 30 bash -c '
    . "$1/errors.sh"; . "$1/json.sh"
    falhas=""
    for f in dbx_json_valor dbx_json_tipo dbx_json_existe \
      dbx_json_tamanho_arranjo dbx_json_chaves dbx_json_chaves_nul; do
      "$f" qualquer >/dev/null 2>&1 && falhas="$falhas $f"
    done
    dbx_json_nome_da_filha 0 qualquer >/dev/null 2>&1 && falhas="$falhas dbx_json_nome_da_filha"
    printf "%s" "$falhas"
  ' _ "$DBX_LIB" 2>&1)
  assert_igual '' "$saida" "consultas que respondem sem documento analisado:$saida"
}

# ---------------------------------------------------------------------------
# RNF-24 criterio 3 — procedencia do nome de contexto no SITIO DE CHAMADA
#
# O ciclo anterior testou o validador de alfabeto e a mutacao no validador, e
# concluiu que RNF-24 estava satisfeito. Mas o criterio 3 e sobre PROCEDENCIA
# no sitio de chamada, propriedade diferente, que nao estava coberta. Derivar o
# nome de uma tag remota nao e so brecha de procedencia: produz COLISAO COM
# PERDA DE DOCUMENTO, porque dois corpos de erro com tags coincidentes gravam
# no mesmo contexto e o segundo destroi o primeiro — exatamente o modo de falha
# que o contexto nomeado existe para impedir.
# ---------------------------------------------------------------------------

teste_nenhum_sitio_de_chamada_deriva_contexto_de_dado_externo() {
  local arquivo achados diretorio padrao_bom padrao_ruim aceito
  # Auditoria declarada como GARANTIA precisa provar que discrimina, e nao so
  # que passa (RSK-27). Antes de varrer os arquivos reais, o padrao e submetido
  # a amostras conhecidas: se aceitar a ruim ou recusar a boa, a garantia e
  # indicio.
  # O padrao e declarado UMA VEZ e usado tanto na autovalidacao quanto na
  # varredura. Duas copias poderiam divergir, e mutar so a da varredura passaria
  # despercebido — a autovalidacao continuaria exercitando a copia forte.
  local aceito='dbx_json_contexto[[:space:]]+([a-z_]+|"\$DBX_JSON_CONTEXTO_ANTERIOR")([[:space:]]|$)'
  padrao_bom='  dbx_json_contexto config || falhar'
  padrao_ruim='  dbx_json_contexto "$tag_do_erro"'
  if grep -qE "$aceito" <<<"$padrao_ruim"; then
    _harness_falhar 'a auditoria aceita nome derivado de variavel: nao discrimina'
  fi
  if ! grep -qE "$aceito" <<<"$padrao_bom"; then
    _harness_falhar 'a auditoria recusa forma literal legitima: reprovaria por engano'
  fi
  for diretorio in "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands"; do
    [[ -d $diretorio ]] || continue
    for arquivo in "$diretorio"/*.sh; do
      [[ -e $arquivo ]] || continue
      # Aceita apenas literal do alfabeto permitido ou a variavel de restauracao
      # publicada pelo proprio componente.
      achados=$(grep -vE '^[[:space:]]*#' "$arquivo" |
        grep -nE 'dbx_json_contexto[[:space:]]+' |
        grep -vE "$aceito" || true)
      if [[ -n $achados ]]; then
        _harness_falhar \
          "nome de contexto possivelmente derivado de dado externo em $(basename "$arquivo"): $achados" \
          'derivar o nome de tag remota faz dois corpos de erro colidirem no mesmo contexto, destruindo o primeiro'
      fi
    done
  done
}

teste_tags_reais_da_dropbox_seriam_recusadas_como_contexto() {
  # Demonstra o risco de forma concreta: as tags reais nem sempre passam pelo
  # alfabeto, e as que passam colidem entre si.
  local tag recusadas=0 aceitas=0
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/json.sh"
  for tag in 'path' 'conflict' 'too_many_write_operations' 'incorrect_offset' \
    'restricted_content' 'not_found' 'insufficient_space' 'malformed_path'; do
    if dbx_json_contexto "$tag" 2>/dev/null; then
      aceitas=$((aceitas + 1))
    else
      recusadas=$((recusadas + 1))
    fi
  done
  dbx_json_contexto padrao
  # O ponto nao e quantas passam: e que passar pelo alfabeto NAO torna seguro
  # derivar o nome de dado externo, porque duas respostas com a mesma tag
  # gravariam no mesmo contexto.
  if [[ $aceitas -eq 0 ]]; then
    _harness_falhar 'esperado que tags reais passassem pelo alfabeto, evidenciando o risco'
  fi
}

# ---------------------------------------------------------------------------
# Etapa 3 — composicao de preflight e config com o restante
# ---------------------------------------------------------------------------

teste_preflight_e_config_entram_em_qualquer_ordem_de_carregamento() {
  local ordem saida
  local -a ordens=(
    'errors path hash json output preflight config'
    'config preflight output json hash path errors'
    'json config errors preflight output path hash'
    'preflight config errors json path hash output'
  )
  for ordem in "${ordens[@]}"; do
    saida=$(timeout 30 bash -c '
      for componente in $2; do . "$1/$componente.sh" || exit 1; done
      dbx_preflight_verificar >/dev/null 2>&1 || exit 2
      printf "ok"
    ' _ "$DBX_LIB" "$ordem" 2>&1)
    assert_igual 'ok' "$saida" "ordem de carregamento falhou: [$ordem]"
  done
}

teste_codigos_de_saida_de_preflight_e_config_concordam_com_a_taxonomia() {
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/preflight.sh"
  . "$DBX_LIB/config.sh"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_PREFLIGHT_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_PREFLIGHT_ERRO_CONFIGURACAO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_CONFIG_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_CONFIG_ERRO_CONFIGURACAO"
}

teste_config_nao_destroi_documento_de_outro_contexto() {
  # Cadeia real: uma listagem paginada em curso enquanto a credencial e lida.
  local area
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/config.sh"
  area=$(mktemp -d "$DBX_TESTES_TMP/comp.XXXXXX")
  XDG_CONFIG_HOME="$area/config" dbx_config_gravar 'AK' 'AS' 'RT' '/r'
  dbx_json_contexto padrao
  dbx_json_analisar '{"entries":[{"name":"a"}],"cursor":"C1"}'
  XDG_CONFIG_HOME="$area/config" dbx_config_carregar
  dbx_json_valor cursor >/dev/null
  assert_igual 'C1' "$DBX_JSON_RESULTADO"
  assert_igual 'padrao' "$DBX_JSON_CONTEXTO" 'o contexto precisa ser restaurado'
}

teste_ambas_as_verificacoes_de_permissao_da_credencial_concordam() {
  # Pergunta do QF-01 aplicada a este incremento: a guarda de permissao existe
  # em DOIS caminhos gemeos — preflight e leitura. Ambas precisam recusar os
  # mesmos modos, senao uma delas e porta de entrada.
  local area arquivo modo status_preflight status_config
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/preflight.sh"
  . "$DBX_LIB/config.sh"
  area=$(mktemp -d "$DBX_TESTES_TMP/perm.XXXXXX")
  mkdir -p "$area/config/dbx"
  # O diretorio tambem passou a ser verificado (P3-04): sem restringi-lo, o
  # caso mediria a permissao do diretorio em vez da do arquivo.
  chmod 700 "$area/config/dbx"
  arquivo="$area/config/dbx/credencial.json"
  printf '{"versao":1,"app_key":"AK","app_secret":"AS","refresh_token":"RT","raiz_remota":"/r"}' >"$arquivo"
  for modo in 600 400 700 644 640 604 660 606 666 200; do
    chmod "$modo" "$arquivo"
    XDG_CONFIG_HOME="$area/config" dbx_preflight_verificar >/dev/null 2>&1
    status_preflight=$?
    XDG_CONFIG_HOME="$area/config" dbx_config_carregar >/dev/null 2>&1
    status_config=$?
    if [[ $modo =~ ^[4567]00$ ]]; then
      assert_igual 0 "$status_preflight" "modo $modo devia passar no preflight"
      assert_igual 0 "$status_config" "modo $modo devia passar na leitura"
    else
      assert_diferente 0 "$status_preflight" "modo $modo passou no preflight"
      assert_diferente 0 "$status_config" "modo $modo passou na leitura"
    fi
  done
}

teste_credencial_gravada_e_integralmente_redigida_pela_taxonomia() {
  # Composicao entre o FORMATO escolhido e a redacao: se o formato mudasse e a
  # taxonomia nao acompanhasse, um diagnostico que citasse o arquivo vazaria.
  local area conteudo
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/config.sh"
  area=$(mktemp -d "$DBX_TESTES_TMP/red.XXXXXX")
  XDG_CONFIG_HOME="$area/config" dbx_config_gravar \
    'AK9pQrSegredo' 'AS9pQrSegredo' 'RT9pQrSegredo' '/raiz'
  conteudo=$(cat "$area/config/dbx/credencial.json")
  dbx_errors_redigir "$conteudo" >/dev/null
  assert_nao_contem '9pQrSegredo' "$DBX_ERRORS_REDIGIDO" \
    'todo campo secreto do formato precisa estar coberto pela taxonomia'
  assert_contem 'raiz_remota' "$DBX_ERRORS_REDIGIDO" \
    'o que nao e segredo precisa sobreviver, sob pena de inutilizar o diagnostico'
}

teste_nenhum_componente_novo_introduz_estado_persistente() {
  # PRJ-DEC-07 e RSK-23: a unica escrita persistente e a credencial.
  local arquivo codigo achados
  for arquivo in "$DBX_LIB/preflight.sh" "$DBX_LIB/config.sh"; do
    codigo=$(grep -vE '^[[:space:]]*#' "$arquivo")
    achados=$(grep -nE '>[[:space:]]*"?\$(HOME|XDG_CACHE|XDG_DATA)' <<<"$codigo" || true)
    [[ -n $achados ]] && _harness_falhar "escrita fora da credencial em $(basename "$arquivo"): $achados"
    achados=$(grep -nEi '(cache|indice|cursor_local|lockfile|arquivo_de_trava)' <<<"$codigo" || true)
    [[ -n $achados ]] && _harness_falhar "indicio de estado local em $(basename "$arquivo"): $achados"
  done
  return 0
}

harness_executar "$@"
