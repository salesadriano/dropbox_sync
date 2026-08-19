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

# _guardas_de_metadado_em <funcao> <arquivo> — extrai do CODIGO o conjunto de
# guardas que a funcao aplica sobre metadado da credencial.
#
# CRITERIO, reenunciado. Uma divergencia entre gemeos importa quando cria um
# SEGUNDO CAMINHO NAO GUARDADO ATE O MESMO RISCO. Nao e "metadado contra
# conteudo": essa formulacao coincide com a certa hoje apenas porque o preflight
# nunca alcanca o conteudo, havendo uma unica porta para a interpretacao —
# guardar a unica porta que alcanca o risco e desenho, nao assimetria. Quando
# houver dois pontos que interpretem corpo de resposta, uma guarda de conteudo
# em um lado so SERA divergencia legitima, e o criterio por categoria de dado a
# excluiria por engano.
#
# A EXISTENCIA (`-e` contra `-f`) fica de fora pelo mesmo criterio: o preflight
# verifica ambiente e trata credencial ausente como estado normal antes da
# configuracao inicial, enquanto a leitura verifica autorizacao. Nao ha segundo
# caminho ate o risco, e sim duas perguntas diferentes.
#
# O RECONHECEDOR tambem deriva do codigo. A versao anterior mantinha a mao a
# lista de nomes de variavel que contavam como metadado, e por isso guardas
# novas sobre `%Y` ou `%i` passavam despercebidas — a mesma inversao que ja
# fora feita para o conjunto de guardas, faltando um nivel abaixo (R3-02).
# Agora as variaveis de metadado sao descobertas pelas proprias atribuicoes a
# partir de `stat`, e a assinatura da guarda carrega o ESPECIFICADOR, e nao o
# nome da variavel: assim `%a` e `%Y` nao se confundem.
_guardas_de_metadado_em() {
  local funcao=$1 arquivo=$2 corpo variavel especificador
  corpo=$(awk -v alvo="$funcao" '
    $0 ~ "^" alvo "\\(\\)" { dentro = 1 }
    dentro && /^}/ { dentro = 0 }
    dentro { print }
  ' "$arquivo" | grep -vE '^[[:space:]]*#')

  {
    # Guardas sobre variaveis derivadas de `stat`, nomeadas pelo especificador.
    while IFS= read -r atribuicao; do
      [[ -n $atribuicao ]] || continue
      variavel=${atribuicao%%=*}
      variavel=${variavel##* }
      especificador=$(grep -oE "%[a-zA-Z]" <<<"$atribuicao" | head -1)
      [[ -n $variavel && -n $especificador ]] || continue
      grep -oE "\\\$${variavel}[[:space:]]*(=~|==|!=|-(eq|ne|gt|ge|lt|le))[[:space:]]*[^]|&)]*" <<<"$corpo" |
        sed -e "s/\\\$$variavel/$especificador/" -e 's/[[:space:]]\+/ /g' -e 's/ $//'
    done < <(grep -oE '[a-z_]+=\$\(stat[^)]*\)' <<<"$corpo")

    # Testes de arquivo sobre os caminhos da credencial, exceto existencia.
    grep -oE '\-[fdwrxs][[:space:]]+"?\$(arquivo|diretorio)' <<<"$corpo" |
      sed 's/[[:space:]]\+/ /g'
  } | sort -u
}

teste_gemeos_aplicam_o_mesmo_conjunto_de_guardas_de_metadado() {
  # ESCOPO DERIVADO DO CODIGO. Guarda de metadado acrescentada a um gemeo e nao
  # ao outro passa a reprovar POR CONSTRUCAO, e nao por acaso de o modo novo
  # estar entre os fixados.
  local do_preflight do_config
  # O gemeo do lado do preflight passou a ser `dbx_preflight_credencial`, que e a
  # funcao dedicada criada quando o nivel virou parametro. A auditoria segue a
  # funcao que INSPECIONA, e nao o nome antigo: apontada para a funcao errada ela
  # extrairia conjunto vazio, e conjunto vazio compara igual a conjunto vazio.
  # E por isso que a guarda de vacuidade logo abaixo existe.
  do_preflight=$(_guardas_de_metadado_em dbx_preflight_credencial "$DBX_LIB/preflight.sh")
  do_config=$(_guardas_de_metadado_em dbx_config_carregar "$DBX_LIB/config.sh")

  if [[ -z $do_preflight || -z $do_config ]]; then
    _harness_falhar 'a extracao nao encontrou guarda alguma: a auditoria estaria vazia'
  fi
  assert_igual "$do_preflight" "$do_config" \
    'os dois caminhos gemeos precisam aplicar o mesmo conjunto de guardas de metadado'
}

teste_auditoria_de_gemeos_detecta_guarda_nova_em_um_lado_so() {
  # RSK-27 na forma NAO OBVIA: nao basta detectar a divergencia que existia — e
  # preciso detectar uma divergencia NOVA. A amostra e sintetica para nao
  # depender de mutar o codigo real.
  local amostra_a amostra_b guardas_a guardas_b
  amostra_a=$(mktemp "$DBX_TESTES_TMP/gem.XXXXXX")
  amostra_b=$(mktemp "$DBX_TESTES_TMP/gem.XXXXXX")
  {
    printf '%s\n' 'f_a() {'
    printf '%s\n' '  modo=$(stat -c "%a" "$arquivo")'
    printf '%s\n' '  dono=$(stat -c "%u" "$arquivo")'
    printf '%s\n' '  [[ $modo =~ ^[4567]00$ ]] || return 1'
    printf '%s\n' '  [[ $dono == "$EUID" ]] || return 1'
    printf '%s\n' '}'
  } >"$amostra_a"
  {
    printf '%s\n' 'f_b() {'
    printf '%s\n' '  modo=$(stat -c "%a" "$arquivo")'
    printf '%s\n' '  dono=$(stat -c "%u" "$arquivo")'
    printf '%s\n' '  mtime=$(stat -c "%Y" "$arquivo")'
    printf '%s\n' '  [[ $modo =~ ^[4567]00$ ]] || return 1'
    printf '%s\n' '  [[ $dono == "$EUID" ]] || return 1'
    printf '%s\n' '  [[ $mtime == 0 ]] || return 1'
    printf '%s\n' '}'
  } >"$amostra_b"
  guardas_a=$(_guardas_de_metadado_em f_a "$amostra_a")
  guardas_b=$(_guardas_de_metadado_em f_b "$amostra_b")
  rm -f "$amostra_a" "$amostra_b"
  assert_diferente "$guardas_a" "$guardas_b" \
    'guarda nova em um lado so precisa produzir conjuntos diferentes'
  assert_contem '%Y' "$guardas_b" \
    'o reconhecedor precisa enxergar especificador novo sem que ninguem o liste'
}

teste_gemeos_decidem_igual_em_todo_o_espaco_de_permissao() {
  # ESCOPO DERIVADO DO DOMINIO: os 512 modos possiveis, e nao uma amostra.
  local area arquivo modo octal status_preflight status_config divergentes=0
  . "$DBX_LIB/errors.sh"
  . "$DBX_LIB/json.sh"
  . "$DBX_LIB/preflight.sh"
  . "$DBX_LIB/config.sh"
  area=$(mktemp -d "$DBX_TESTES_TMP/espaco.XXXXXX")
  mkdir -p "$area/config/dbx"
  chmod 700 "$area/config/dbx"
  arquivo="$area/config/dbx/credencial.json"
  printf '{"versao":1,"app_key":"AK","app_secret":"AS","refresh_token":"RT","raiz_remota":"/r"}' >"$arquivo"

  for ((modo = 0; modo < 512; modo++)); do
    printf -v octal '%03o' "$modo"
    chmod "$octal" "$arquivo" 2>/dev/null || continue
    XDG_CONFIG_HOME="$area/config" dbx_preflight_verificar >/dev/null 2>&1
    status_preflight=$?
    XDG_CONFIG_HOME="$area/config" dbx_config_carregar >/dev/null 2>&1
    status_config=$?
    # Concordancia de DECISAO: ambos aceitam ou ambos recusam.
    local aceita_preflight=nao aceita_config=nao
    [[ $status_preflight -eq 0 ]] && aceita_preflight=sim
    [[ $status_config -eq 0 ]] && aceita_config=sim
    if [[ $aceita_preflight != "$aceita_config" ]]; then
      divergentes=$((divergentes + 1))
      [[ $divergentes -le 3 ]] && printf '# divergencia no modo %s: preflight=%s config=%s\n' \
        "$octal" "$status_preflight" "$status_config" >&2
    fi
  done
  chmod 600 "$arquivo"
  assert_igual 0 "$divergentes" \
    'os gemeos precisam decidir identicamente em TODO o espaco de permissao'
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

# ---------------------------------------------------------------------------
# QH-01 generalizado: canal publico alheio que recebe dado derivado de
# credencial tem de ser limpo por quem o encheu.
#
# Por que as auditorias existentes nao pegam esta classe: todas comparam FORMA
# — presenca de construcao, padrao sintatico, especificador. O QH-01 nao tem
# forma: e a AUSENCIA de uma limpeza sobre um recurso que auditoria nenhuma
# enumerava. Nao da para procurar o que nao esta escrito sem antes derivar a
# lista do que deveria estar.
#
# Os dois conjuntos sao derivados do artefato, e nao enumerados a mao:
#   - o que e segredo vem da TABELA DE CHAVES SENSIVEIS de lib/errors.sh, a
#     mesma que governa a redacao;
#   - os prefixos de componente vem dos arquivos em lib/;
#   - os canais publicos alheios vem das referencias `$DBX_<OUTRO>_*` no texto.
# Mantido a mao so o conjunto de EXCECOES, e cada uma precisa de motivo.
# ---------------------------------------------------------------------------

_chaves_sensiveis_em_maiuscula() {
  # Derivadas da tabela real, e nao reescritas aqui: reescrever criaria uma
  # segunda copia que divergiria em silencio da que governa a redacao.
  sed -n '/^DBX_ERRORS_CHAVES_SENSIVEIS=(/,/^)/p' "$DBX_HARNESS_RAIZ/lib/errors.sh" |
    grep -oE '[a-z_]+' | grep -vE '^(DBX|ERRORS|CHAVES|SENSIVEIS)$' |
    tr '[:lower:]' '[:upper:]' | sort -u
}

_prefixos_de_componente() {
  local arquivo nome
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh; do
    nome=${arquivo##*/}
    printf '%s\n' "${nome%.sh}" | tr '[:lower:]' '[:upper:]'
  done
}

# Excecoes: canais alheios que NAO podem carregar valor derivado de credencial.
# Cada um precisa de motivo, e o motivo e estrutural, nao "eu olhei e nao vaza".
_canal_nao_carrega_credencial() {
  case $1 in
    # Codigos de saida e constantes de classe: valores fixos da taxonomia.
    DBX_ERRORS_STATUS_USO | DBX_ERRORS_CLASSES | DBX_ERRORS_CODIGO) return 0 ;;
    # Metadados de resposta, nunca conteudo: codigo HTTP, classe, politica e
    # identificador de correlacao emitido pelo servico.
    DBX_HTTP_CODIGO | DBX_HTTP_CLASSE | DBX_HTTP_POLITICA) return 0 ;;
    DBX_HTTP_CORRELACAO | DBX_HTTP_DEFEITO_CLIENTE) return 0 ;;
    DBX_HTTP_ERRO_USO | DBX_HTTP_ERRO_REDE) return 0 ;;
    # Nome de contexto e motivo de recusa do analisador: vocabulario fechado.
    DBX_JSON_CONTEXTO_ANTERIOR | DBX_JSON_MOTIVO) return 0 ;;
    DBX_JSON_MAXIMO_* ) return 0 ;;
    # Caminho e motivo do componente de configuracao: sistema de arquivos.
    DBX_CONFIG_RESULTADO | DBX_CONFIG_MOTIVO | DBX_CONFIG_ARQUIVO) return 0 ;;
    DBX_CONFIG_ERRO_* | DBX_CONFIG_VERSAO | DBX_CONFIG_IDADE_ORFAO) return 0 ;;
    DBX_PATH_RESULTADO | DBX_HASH_RESULTADO) return 0 ;;
    # Saida do REDATOR: por construcao ja passou pela redacao. Exigir limpeza
    # dela seria exigir limpeza do resultado de limpar.
    DBX_ERRORS_REDIGIDO) return 0 ;;
  esac
  return 1
}

teste_canal_publico_alheio_com_dado_de_credencial_e_limpo_por_quem_o_encheu() {
  local -a sensiveis=() prefixos=()
  mapfile -t sensiveis < <(_chaves_sensiveis_em_maiuscula)
  mapfile -t prefixos < <(_prefixos_de_componente)
  [[ ${#sensiveis[@]} -ge 5 ]] ||
    _harness_falhar 'tabela de chaves sensiveis nao foi derivada' "obtidas: ${#sensiveis[@]}"
  [[ ${#prefixos[@]} -ge 5 ]] ||
    _harness_falhar 'prefixos de componente nao foram derivados'

  local arquivo proprio texto chave var outro
  local -a faltando=()
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh; do
    proprio=${arquivo##*/}
    proprio=$(printf '%s' "${proprio%.sh}" | tr '[:lower:]' '[:upper:]')
    texto=$(grep -vE '^[[:space:]]*#' "$arquivo")

    # O componente lida com credencial?
    local lida_com_credencial=nao
    for chave in "${sensiveis[@]}"; do
      grep -qE "DBX_[A-Z_]*${chave}" <<<"$texto" && lida_com_credencial=sim && break
    done
    [[ $lida_com_credencial == 'sim' ]] || continue

    # Canais publicos ALHEIOS que ele le.
    while IFS= read -r var; do
      [[ -n $var ]] || continue
      outro=${var#DBX_}
      outro=${outro%%_*}
      [[ $outro == "$proprio" ]] && continue
      printf '%s\n' "${prefixos[@]}" | grep -qx "$outro" || continue
      _canal_nao_carrega_credencial "$var" && continue
      # A exigencia recai sobre quem PREENCHEU o canal, e nao sobre quem apenas
      # o le como entrada. Sem esta distincao a regra mandaria lib/auth apagar
      # `DBX_CONFIG_REFRESH_TOKEN`, que e a credencial de origem e precisa
      # sobreviver a proxima renovacao — a auditoria transformaria zelo em
      # defeito. O criterio derivavel: o componente preencheu o canal se invoca
      # alguma funcao do dono dele.
      local dono
      dono=$(printf '%s' "$outro" | tr '[:upper:]' '[:lower:]')
      grep -qE "(^|[^a-z_])dbx_${dono}_[a-z_]+" <<<"$texto" || continue
      # Exige atribuicao de limpeza no proprio arquivo.
      grep -qE "^[[:space:]]*$var=" <<<"$texto" ||
        faltando+=("${arquivo##*/}: le $var e nao o limpa")
    done < <(grep -oE '\$\{?DBX_[A-Z_]+' <<<"$texto" | sed -e 's/^\${\?//' | sort -u)
  done

  [[ ${#faltando[@]} -eq 0 ]] ||
    _harness_falhar 'canal publico alheio com dado de credencial sem limpeza' "${faltando[@]}"
  return 0
}

# A guarda de fronteira de linha de lib/output NAO incide sobre canal de corpo
# do transporte — e nao deve incidir: corpo pode conter byte nulo, que variavel
# de shell nao carrega e que a apresentacao nao sabe terminar.
#
# Declarar isso em comentario e o que ja falhou sete vezes. Aqui e CASO: se
# algum comando passar um canal de corpo para a apresentacao, reprova. A regra
# deriva do nome do canal, entao vale tambem para o canal binario que ainda vai
# existir, sem ninguem precisar lembrar de acrescenta-lo.
teste_canal_de_corpo_nunca_e_alimentado_na_apresentacao() {
  local arquivo achados=()
  for arquivo in "$DBX_HARNESS_RAIZ"/commands/*.sh "$DBX_HARNESS_RAIZ"/lib/cmd.sh; do
    [[ -e $arquivo ]] || continue
    while IFS= read -r linha; do
      [[ -n $linha ]] || continue
      achados+=("${arquivo##*/}: $linha")
    done < <(grep -vE '^[[:space:]]*#' "$arquivo" |
      grep -nE 'dbx_output_(campo|diagnostico)[^#]*DBX_(HTTP|JSON)_CORPO' || true)
  done
  [[ ${#achados[@]} -eq 0 ]] ||
    _harness_falhar 'canal de corpo do transporte alimentado na apresentacao' "${achados[@]}"

  # Prova de discriminacao: o reconhecedor precisa reagir a forma que procura.
  local amostra='  dbx_output_campo conteudo "$DBX_HTTP_CORPO_ARQUIVO"'
  grep -qE 'dbx_output_(campo|diagnostico)[^#]*DBX_(HTTP|JSON)_CORPO' <<<"$amostra" ||
    _harness_falhar 'o reconhecedor nao detecta a forma que deveria proibir'
  local inocente='  dbx_output_campo total "$total"'
  grep -qE 'dbx_output_(campo|diagnostico)[^#]*DBX_(HTTP|JSON)_CORPO' <<<"$inocente" &&
    _harness_falhar 'o reconhecedor acusa forma legitima'
  return 0
}

# Contagem sobre arquivo passa pelo auxiliar do arcabouco.
#
# `grep -c` imprime a contagem E sai com 1 quando nao ha correspondencia. A forma
# `$(grep -c ... || printf 0)` dispara o recuo ALEM da saida ja emitida e produz
# "0\n0", falhando exatamente quando a contagem deveria ser zero — que e o caso
# que as assercoes de ausencia existem para verificar. Doze usos da construcao
# existiam; dois deles verificavam que NENHUMA chamada de escrita fora emitida.
#
# O universo deriva do artefato: enumera `grep -c` sobre ARQUIVO em tests/, e a
# lista mantida a mao e so de excecoes — contagem sobre cadeia, que nao tem o
# problema, e a implementacao do proprio auxiliar.
teste_contagem_sobre_arquivo_passa_pelo_auxiliar() {
  local arquivo linha fora_do_auxiliar=''
  for arquivo in "$DBX_HARNESS_RAIZ"/tests/unit/*.sh \
                 "$DBX_HARNESS_RAIZ"/tests/integracao/*.sh; do
    while IFS= read -r linha; do
      [[ -n $linha ]] || continue
      # Excecoes, todas declaradas: contagem sobre cadeia nao le arquivo; o
      # enumerador precisa citar o padrao que procura; e linha precedida de
      # `contagem-direta:` traz a razao no proprio ponto de uso.
      [[ $linha == *'<<<'* ]] && continue
      [[ $linha == *'grep -n '* ]] && continue
      [[ $linha == *'contagem-direta'* ]] && continue
      fora_do_auxiliar+=" ${arquivo##*/}:${linha%%:*}"
    done < <(grep -n 'grep -c' "$arquivo" 2>/dev/null |
      grep -vE ':[[:space:]]*#' |
      grep -vE "contagem-direta" || true)
  done
  assert_igual '' "$fora_do_auxiliar" \
    "contagem sobre arquivo fora do auxiliar _harness_contar:$fora_do_auxiliar"
}

# Prova de discriminacao: o auxiliar responde 0 nos tres cenarios em que a forma
# antiga produzia "0\n0" ou falhava, e conta certo quando ha correspondencia.
teste_auxiliar_de_contagem_discrimina() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/contagem.XXXXXX") || return 1
  printf 'sem correspondencia\n' >"$area/com_conteudo"
  : >"$area/vazio"
  printf 'alvo\nalvo\noutra\n' >"$area/com_alvo"

  assert_igual 0 "$(_harness_contar alvo "$area/com_conteudo")" \
    'arquivo com conteudo e sem correspondencia conta zero'
  assert_igual 0 "$(_harness_contar alvo "$area/vazio")" \
    'arquivo vazio conta zero'
  assert_igual 0 "$(_harness_contar alvo "$area/ausente")" \
    'arquivo ausente conta zero'
  assert_igual 2 "$(_harness_contar alvo "$area/com_alvo")" \
    'duas correspondencias contam duas'
}

harness_executar "$@"
