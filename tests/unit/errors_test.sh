#!/usr/bin/env bash
# Testes de lib/errors.sh — taxonomia de erro e codigos de saida (RF-29, RNF-08).
#
# O bloco "contrato congelado" existe por exigencia de RF-35: se alguem mudar o
# valor numerico de um codigo de saida ou o nome de uma classe, a suite reprova.
# Consumidores automatizados dependem desses valores.

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a um "bash -c", que precisa
# chegar sem expansao ao processo filho, e mensagens de diagnostico citam
# nomes de arquivo com barra invertida como dado, nao como expansao.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

# ---------------------------------------------------------------------------
# Contrato congelado
# ---------------------------------------------------------------------------

teste_tabela_de_codigos_de_saida_e_congelada() {
  assert_igual 0 "$(dbx_errors_codigo_saida sucesso)" 'sucesso'
  assert_igual 1 "$(dbx_errors_codigo_saida desconhecido)" 'desconhecido'
  assert_igual 2 "$(dbx_errors_codigo_saida uso_invalido)" 'uso invalido'
  assert_igual 3 "$(dbx_errors_codigo_saida configuracao)" 'configuracao (RF-03)'
  assert_igual 4 "$(dbx_errors_codigo_saida nao_encontrado)" 'nao encontrado (RF-17)'
  assert_igual 5 "$(dbx_errors_codigo_saida autenticacao)" 'autenticacao'
  assert_igual 6 "$(dbx_errors_codigo_saida permissao)" 'permissao'
  assert_igual 7 "$(dbx_errors_codigo_saida conflito)" 'conflito no destino'
  assert_igual 8 "$(dbx_errors_codigo_saida limite_taxa)" 'limite de taxa'
  assert_igual 9 "$(dbx_errors_codigo_saida rede)" 'falha de rede'
  assert_igual 10 "$(dbx_errors_codigo_saida erro_remoto)" 'erro remoto'
  assert_igual 11 "$(dbx_errors_codigo_saida integridade)" 'integridade'
  assert_igual 12 "$(dbx_errors_codigo_saida espaco)" 'espaco insuficiente'
  assert_igual 13 "$(dbx_errors_codigo_saida caminho_recusado)" 'caminho fora da raiz (RNF-20)'
  assert_igual 14 "$(dbx_errors_codigo_saida nao_concluida)" 'operacao nao concluida'
  assert_igual 15 "$(dbx_errors_codigo_saida consumidor_encerrou)" 'consumidor encerrou (RF-32)'
}

# _taxonomia — devolve a lista de classes, falhando o caso se ela vier curta.
# Sem essa guarda, todo teste que itera sobre as classes passaria por vacuidade.
# A lista e consumida por here-string, e nao por substituicao de processo, para
# que a falha de uma assercao encerre o caso e nao apenas um subshell.
_taxonomia() {
  local lista quantidade
  lista=$(dbx_errors_listar_classes 2>/dev/null)
  quantidade=$(grep -c '^[a-z_]\{3,\}$' <<<"$lista")
  if [[ $quantidade -lt 10 ]]; then
    _harness_falhar "taxonomia incompleta: $quantidade classe(s) declarada(s), minimo 10"
  fi
  printf '%s' "$lista"
}

teste_codigos_de_saida_nao_colidem_entre_classes() {
  local classe codigo vistos='' lista
  lista=$(_taxonomia) || exit 1
  while IFS= read -r classe; do
    [[ -n $classe ]] || continue
    codigo=$(dbx_errors_codigo_saida "$classe")
    assert_nao_contem "|$codigo|" "$vistos" "codigo $codigo repetido na classe $classe"
    vistos+="|$codigo|"
  done <<<"$lista"
}

teste_toda_classe_tem_codigo_e_mensagem() {
  local classe mensagem lista
  lista=$(_taxonomia) || exit 1
  while IFS= read -r classe; do
    [[ -n $classe ]] || continue
    assert_sucesso dbx_errors_codigo_saida "$classe"
    mensagem=$(dbx_errors_mensagem "$classe")
    if [[ -z $mensagem ]]; then
      _harness_falhar "classe sem mensagem acionavel: $classe"
    fi
  done <<<"$lista"
}

teste_codigos_ficam_fora_da_faixa_reservada_pelo_shell() {
  # 126, 127 e 128+n sao reservados por convencao do shell; reusa-los tornaria
  # o codigo de saida ambiguo para o orquestrador (RF-28).
  local classe codigo lista
  lista=$(_taxonomia) || exit 1
  while IFS= read -r classe; do
    [[ -n $classe ]] || continue
    codigo=$(dbx_errors_codigo_saida "$classe")
    if [[ $codigo -ge 126 ]]; then
      _harness_falhar "classe $classe usa codigo reservado: $codigo"
    fi
  done <<<"$lista"
}

teste_classe_desconhecida_e_recusada() {
  assert_status 2 dbx_errors_codigo_saida classe_que_nao_existe
  assert_status 2 dbx_errors_codigo_saida ''
  assert_status 1 dbx_errors_classe_valida classe_que_nao_existe
  assert_sucesso dbx_errors_classe_valida nao_encontrado
}

# ---------------------------------------------------------------------------
# Classificacao por codigo HTTP
# ---------------------------------------------------------------------------

teste_classificacao_por_codigo_http_sem_resumo() {
  assert_igual uso_invalido "$(dbx_errors_classificar 400 '')"
  assert_igual autenticacao "$(dbx_errors_classificar 401 '')"
  assert_igual permissao "$(dbx_errors_classificar 403 '')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 '')"
  assert_igual limite_taxa "$(dbx_errors_classificar 429 '')"
  assert_igual erro_remoto "$(dbx_errors_classificar 500 '')"
  assert_igual erro_remoto "$(dbx_errors_classificar 503 '')"
  assert_igual sucesso "$(dbx_errors_classificar 200 '')"
}

teste_ausencia_de_resposta_http_e_falha_de_rede() {
  # Falha de transporte: cURL nao obteve resposta. Nao pode ser confundida com
  # erro remoto, porque a acao corretiva e outra.
  assert_igual rede "$(dbx_errors_classificar 0 '')"
}

# ---------------------------------------------------------------------------
# Correspondencia por PREFIXO do error_summary, nunca por igualdade
# ---------------------------------------------------------------------------

teste_prefixo_e_nao_igualdade() {
  # Formato real da Dropbox: a tag vem sufixada.
  assert_igual nao_encontrado "$(dbx_errors_classificar 409 'path/not_found/.')"
  assert_igual nao_encontrado "$(dbx_errors_classificar 409 'path/not_found/')"
  assert_igual nao_encontrado "$(dbx_errors_classificar 409 'path/not_found')"
  assert_igual conflito "$(dbx_errors_classificar 409 'path/conflict/file/.')"
  assert_igual espaco "$(dbx_errors_classificar 409 'path/insufficient_space/..')"
}

teste_prefixo_respeita_a_fronteira_do_componente() {
  # `path/not_founded` nao e `path/not_found`. Sem fronteira, uma tag futura da
  # Dropbox seria classificada errado em silencio.
  assert_igual desconhecido "$(dbx_errors_classificar 409 'path/not_founded/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'path/conflicting/.')"
}

teste_tags_relevantes_documentadas_no_system_design() {
  assert_igual limite_taxa "$(dbx_errors_classificar 429 'rate_limit/too_many_requests/.')"
  assert_igual limite_taxa "$(dbx_errors_classificar 429 'too_many_write_operations/.')"
  assert_igual erro_remoto "$(dbx_errors_classificar 503 'transient_error/.')"
  assert_igual integridade "$(dbx_errors_classificar 409 'content_hash_mismatch/.')"
  assert_igual permissao "$(dbx_errors_classificar 403 'no_permission/.')"
  assert_igual nao_concluida "$(dbx_errors_classificar 409 'reset/.')"
}

teste_tags_de_autenticacao_e_escopo() {
  assert_igual autenticacao "$(dbx_errors_classificar 401 'invalid_access_token/.')"
  assert_igual autenticacao "$(dbx_errors_classificar 401 'expired_access_token/.')"
  assert_igual autenticacao "$(dbx_errors_classificar 401 'missing_scope/.')"
}

teste_tags_de_caminho_malformado_sao_uso_invalido() {
  assert_igual uso_invalido "$(dbx_errors_classificar 400 'path/malformed_path/.')"
  assert_igual uso_invalido "$(dbx_errors_classificar 409 'malformed_path/.')"
}

teste_erro_do_servidor_ignora_o_resumo() {
  # Um corpo de 5xx nao segue o contrato de error_summary. Deixar o prefixo
  # vencer aqui produziria classificacao arbitraria a partir de corpo de proxy.
  assert_igual erro_remoto "$(dbx_errors_classificar 500 'path/not_found/.')"
  assert_igual erro_remoto "$(dbx_errors_classificar 502 'rate_limit/.')"
}

teste_resumo_com_espacos_e_quebras_de_linha_nao_quebra_a_classificacao() {
  assert_igual nao_encontrado "$(dbx_errors_classificar 409 'path/not_found/. ')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 $'linha1\nlinha2')"
}

teste_classificacao_exige_codigo_http_numerico() {
  assert_status 2 dbx_errors_classificar 'abc' ''
  assert_status 2 dbx_errors_classificar '' ''
}

# ---------------------------------------------------------------------------
# Politica de retentativa (RNF-07)
# ---------------------------------------------------------------------------

teste_400_nunca_sofre_retentativa() {
  assert_igual nenhuma "$(dbx_errors_politica_retentativa 400 '')"
  assert_igual nenhuma "$(dbx_errors_politica_retentativa 400 'path/malformed_path/.')"
}

teste_401_renova_token_uma_unica_vez() {
  assert_igual renovar_token_uma_vez "$(dbx_errors_politica_retentativa 401 '')"
}

teste_429_respeita_retry_after() {
  assert_igual respeitar_retry_after "$(dbx_errors_politica_retentativa 429 'rate_limit/.')"
}

teste_5xx_classifica_como_erro_remoto() {
  # A POLITICA de 5xx passou a depender da idempotencia (decisao do ciclo 2,
  # coberta em `5xx_segue_a_idempotencia_como_a_falha_de_transporte`). A CLASSE
  # continua fixa.
  assert_igual erro_remoto "$(dbx_errors_classificar 500 '')"
  assert_igual erro_remoto "$(dbx_errors_classificar 503 '')"
}

teste_409_nao_sofre_retentativa_exceto_cursor_invalidado() {
  assert_igual nenhuma "$(dbx_errors_politica_retentativa 409 'path/conflict/file/.')"
  assert_igual reiniciar "$(dbx_errors_politica_retentativa 409 'reset/.')"
}

teste_falha_de_transporte_depende_da_idempotencia_da_operacao() {
  # Sem resposta HTTP nao ha como saber se a escrita foi aplicada do outro lado.
  # Mas isso so e um problema para operacao NAO idempotente. Repetir um
  # `download`, um `list_folder` ou um `get_metadata` e trivialmente seguro, e
  # negar essa retentativa encerra um lote de cron por um RST de TCP.
  assert_igual recuo_exponencial "$(dbx_errors_politica_retentativa 0 '' sim)" \
    'operacao idempotente pode repetir apos falha de transporte'
}

teste_falha_de_transporte_em_operacao_nao_idempotente_e_indeterminada() {
  # O estado precisa ter nome proprio. `nenhuma` seria lido por quem implementa
  # lib/http como instrucao ("nao tente"), quando o significado real e "nao da
  # para saber se a escrita foi aplicada" — decisao que cabe ao chamador, que
  # conhece a operacao.
  assert_igual indeterminado "$(dbx_errors_politica_retentativa 0 '' nao)"
}

teste_idempotencia_omitida_assume_o_lado_seguro() {
  # Sem a informacao, nao se pode presumir que repetir e seguro.
  assert_igual indeterminado "$(dbx_errors_politica_retentativa 0 '')"
}

teste_valor_invalido_de_idempotencia_e_recusado() {
  assert_status 2 dbx_errors_politica_retentativa 0 '' talvez
}

teste_408_e_retentavel() {
  # Lacuna do mapa anterior: 408 caia no ramo generico `nenhuma`, embora seja
  # tempo limite de requisicao e portanto retentavel.
  assert_igual recuo_exponencial "$(dbx_errors_politica_retentativa 408 '')"
  assert_igual recuo_exponencial "$(dbx_errors_politica_retentativa 408 '' nao)"
}

teste_idempotencia_nao_altera_as_demais_classes() {
  # A idempotencia so muda a decisao onde existe ambiguidade de aplicacao.
  assert_igual nenhuma "$(dbx_errors_politica_retentativa 400 '' sim)"
  assert_igual respeitar_retry_after "$(dbx_errors_politica_retentativa 429 '' nao)"
  assert_igual renovar_token_uma_vez "$(dbx_errors_politica_retentativa 401 '' nao)"
}

teste_politicas_pertencem_ao_conjunto_congelado() {
  local politica status idem
  for status in 0 400 401 403 408 409 429 500 503; do
    for idem in sim nao; do
      politica=$(dbx_errors_politica_retentativa "$status" '' "$idem")
      case $politica in
        nenhuma | recuo_exponencial | respeitar_retry_after | renovar_token_uma_vez | reiniciar | retomar | indeterminado) ;;
        *) _harness_falhar "politica fora do contrato para status $status/$idem: $politica" ;;
      esac
    done
  done
}

# ---------------------------------------------------------------------------
# Familia de erros de rota do 409 (defeito D5 do QA)
#
# O `error_summary` da Dropbox e composto como {qualificador de uniao}/{tag}.
# Enumerar formas soltas deixa a maior parte da familia cair no balde
# `desconhecido`, que sai com codigo 1 e enfraquece RF-29. O tratamento e por
# remocao dos qualificadores conhecidos antes do casamento.
# ---------------------------------------------------------------------------

teste_qualificadores_de_uniao_sao_removidos_antes_do_casamento() {
  assert_igual permissao "$(dbx_errors_classificar 409 'path/restricted_content/.')"
  assert_igual uso_invalido "$(dbx_errors_classificar 409 'path/not_file/.')"
  assert_igual uso_invalido "$(dbx_errors_classificar 409 'path/not_folder/.')"
  assert_igual nao_encontrado "$(dbx_errors_classificar 409 'lookup_failed/not_found/.')"
  assert_igual nao_concluida "$(dbx_errors_classificar 409 'lookup_failed/incorrect_offset/.')"
  assert_igual nao_concluida "$(dbx_errors_classificar 409 'lookup_failed/closed/.')"
  assert_igual permissao "$(dbx_errors_classificar 409 'no_write_permission/.')"
  assert_igual uso_invalido "$(dbx_errors_classificar 409 'invalid_argument/.')"
  assert_igual permissao "$(dbx_errors_classificar 409 'email_unverified/.')"
}

teste_tag_other_e_o_desconhecido_declarado_da_uniao() {
  # `other` e membro legitimo da uniao, e nao ausencia de mapeamento.
  assert_igual desconhecido "$(dbx_errors_classificar 409 'other/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'path/other/.')"
}

teste_remocao_de_qualificador_nao_afrouxa_a_fronteira_de_componente() {
  # Verificacao de nao regressao: remover o qualificador nao pode transformar o
  # casamento em "comeca com". Estas formas precisam continuar SEM classificacao
  # especifica, caindo no padrao do codigo HTTP.
  assert_igual desconhecido "$(dbx_errors_classificar 409 'path/not_founded/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'not_found_x/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'reset_me/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'conflicts/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'resetting/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'path/conflicting/.')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'restricted_contents/.')"
}

teste_qualificador_nao_e_confundido_com_tag() {
  # `path` e `to` sao qualificadores; sozinhos nao designam classe alguma.
  assert_igual desconhecido "$(dbx_errors_classificar 409 'path')"
  assert_igual desconhecido "$(dbx_errors_classificar 409 'to/')"
}

teste_qualificadores_encadeados_sao_removidos() {
  assert_igual nao_encontrado "$(dbx_errors_classificar 409 'path/lookup_failed/not_found/.')"
  assert_igual conflito "$(dbx_errors_classificar 409 'to/conflict/file/.')"
}

# ---------------------------------------------------------------------------
# Mensagens acionaveis
# ---------------------------------------------------------------------------

teste_mensagem_e_acionavel_e_inclui_o_detalhe() {
  local mensagem
  mensagem=$(dbx_errors_mensagem nao_encontrado '/pasta/arquivo.txt')
  assert_contem '/pasta/arquivo.txt' "$mensagem" 'o detalhe informado aparece na mensagem'
  assert_diferente '' "$mensagem" 'mensagem nao pode ser vazia'
}

teste_mensagem_nao_vaza_segredo_conhecido() {
  # Salvaguarda de RNF-03: nenhuma mensagem pode ecoar material sensivel que
  # tenha chegado por engano no campo de detalhe.
  local mensagem
  mensagem=$(dbx_errors_mensagem autenticacao 'Bearer sl.ABCDEF-token-secreto')
  assert_nao_contem 'sl.ABCDEF-token-secreto' "$mensagem" 'segredo no detalhe deve ser mascarado'
  assert_contem 'REDIGIDO' "$mensagem" 'a mensagem sinaliza que houve mascaramento'
}

teste_mensagem_de_classe_invalida_e_recusada() {
  assert_status 2 dbx_errors_mensagem classe_inexistente
}

teste_detalhe_com_multiplas_linhas_nao_e_truncado() {
  # Um corpo de erro pode chegar com quebras de linha. Perder o que vem depois
  # da primeira linha esconderia justamente o trecho diagnostico.
  local mensagem
  mensagem=$(dbx_errors_mensagem erro_remoto "primeira linha"$'\n'"segunda linha")
  assert_contem 'primeira linha' "$mensagem"
  assert_contem 'segunda linha' "$mensagem" 'o detalhe nao pode parar na primeira linha'
}

# ---------------------------------------------------------------------------
# Suite adversarial de redacao (RNF-03)
#
# O corpo de erro e de token da Dropbox e JSON, e as credenciais aparecem em
# cabecalho, querystring e corpo urlencoded. Um exemplo isolado nao prova nada:
# o que segue e a lista de formatos em que o segredo realmente circula.
# Cada caso e verificado nos dois sentidos: o segredo desaparece E a marca de
# redacao aparece, para que uma implementacao que apenas apague tudo nao passe.
# ---------------------------------------------------------------------------

_assert_redige() {
  local segredo=$1 entrada=$2 descricao=$3 saida
  saida=$(dbx_errors_redigir "$entrada")
  assert_nao_contem "$segredo" "$saida" "vazamento em $descricao: [$saida]"
  assert_contem 'REDIGIDO' "$saida" "sem marca de redacao em $descricao: [$saida]"
}

teste_redacao_de_token_em_json() {
  _assert_redige 'sl.BxSecretoAAAA' \
    '{"access_token":"sl.BxSecretoAAAA","token_type":"bearer"}' \
    'corpo JSON do endpoint de token'
}

teste_redacao_de_refresh_token_em_json() {
  _assert_redige 'RTsegredoBBBB' \
    '{"refresh_token": "RTsegredoBBBB", "expires_in": 14400}' \
    'refresh token em JSON com espacos'
}

teste_redacao_em_querystring() {
  _assert_redige 'SEGREDO123' \
    'https://api.dropbox.com/oauth2/token?client_secret=SEGREDO123&grant_type=refresh_token' \
    'client_secret em querystring'
}

teste_redacao_em_corpo_urlencoded() {
  local saida
  saida=$(dbx_errors_redigir 'grant_type=authorization_code&code=AUTHCODE999&client_secret=SEG888')
  assert_nao_contem 'AUTHCODE999' "$saida" 'codigo de autorizacao em corpo urlencoded'
  assert_nao_contem 'SEG888' "$saida" 'client_secret em corpo urlencoded'
  assert_contem 'grant_type=authorization_code' "$saida" \
    'o que nao e segredo precisa sobreviver, sob pena de inutilizar o diagnostico'
}

teste_redacao_de_token_entre_aspas_em_prosa() {
  _assert_redige 'sl.TokenEmProsa123' \
    'a chamada falhou usando o token "sl.TokenEmProsa123" no cabecalho' \
    'token entre aspas em texto corrido'
}

teste_redacao_ignora_caixa_do_prefixo_de_token() {
  _assert_redige 'SL.TOKENMAIUSCULO' 'valor recebido: SL.TOKENMAIUSCULO' \
    'prefixo de token em caixa alta'
  _assert_redige 'Sl.TokenMisto' 'valor recebido: Sl.TokenMisto' \
    'prefixo de token em caixa mista'
}

teste_redacao_de_cabecalho_authorization() {
  _assert_redige 'YXBwOnNlZ3JlZG8=' 'Authorization: Basic YXBwOnNlZ3JlZG8=' \
    'cabecalho Authorization com credencial Basic'
  _assert_redige 'sl.TokenNoBearer' 'Authorization: Bearer sl.TokenNoBearer' \
    'cabecalho Authorization com Bearer'
}

teste_redacao_de_credencial_em_linha_de_comando_curl() {
  _assert_redige 'segredoDoApp' 'curl -u chaveDoApp:segredoDoApp https://api.dropbox.com' \
    'credencial em -u de linha de comando'
}

teste_redacao_de_cookie() {
  _assert_redige 'valorDeSessao999' 'Cookie: sessao=valorDeSessao999; outro=1' \
    'cabecalho Cookie'
}

teste_redacao_preserva_texto_sem_segredo() {
  # Redigir demais tambem e defeito: destruiria o diagnostico.
  local saida entrada='path/not_found/. em /pasta/arquivo com espaco.txt'
  saida=$(dbx_errors_redigir "$entrada")
  assert_igual "$entrada" "$saida" 'texto sem segredo nao pode ser alterado'
}

teste_redacao_preserva_estrutura_do_texto() {
  # A versao anterior reconstruia o texto por juncao de palavras, destruindo
  # pontuacao, indentacao e quebras. Diagnostico ilegivel nao serve a ninguem.
  local saida
  saida=$(dbx_errors_redigir 'linha um'$'\n''  linha dois indentada')
  assert_contem $'\n' "$saida" 'a quebra de linha do texto original precisa sobreviver'
  assert_contem '  linha dois' "$saida" 'a indentacao precisa sobreviver'
}

teste_redacao_de_entrada_muito_grande_e_limitada() {
  # Teto de entrada: sem ele, o custo cresce com um corpo de resposta grande.
  # O segredo e posto no INICIO, para que o teste prove redacao e nao apenas
  # que o truncamento jogou o segredo fora.
  local entrada saida
  printf -v entrada 'palavra%.0s ' $(seq 1 3000)
  saida=$(dbx_errors_redigir "sl.SEGREDO-NO-INICIO $entrada")
  assert_nao_contem 'sl.SEGREDO-NO-INICIO' "$saida" \
    'segredo antes do teto precisa ser redigido'
  assert_contem 'REDIGIDO' "$saida"
  if [[ ${#saida} -gt 6000 ]]; then
    _harness_falhar "saida sem teto: ${#saida} caracteres"
  fi
}

teste_custo_da_redacao_cresce_proporcionalmente_a_entrada() {
  # Substitui um limite ABSOLUTO de tempo, que media velocidade da maquina e nao
  # complexidade, e por isso era candidato a intermitencia sob carga. A
  # propriedade verificada e a mesma que motivou o caso original — a versao
  # quadratica levava mais de 15 s para 50 mil palavras — mas expressa como
  # RAZAO entre minimos, insensivel a carga.
  local pequena grande t_pequena t_grande
  printf -v pequena 'palavra%.0s ' $(seq 1 5000)
  printf -v grande 'palavra%.0s ' $(seq 1 50000)
  # shellcheck disable=SC2317  # invocada indiretamente por _medir_minimo_ms
  _redigir() { dbx_errors_redigir "$1"; }
  t_pequena=$(_medir_minimo_ms 5 _redigir "$pequena")
  t_grande=$(_medir_minimo_ms 5 _redigir "$grande")
  unset -f _redigir
  if [[ $t_grande -gt $((t_pequena * 30)) ]]; then
    _harness_falhar \
      "custo super-linear: 5 mil palavras em ${t_pequena}ms, 50 mil em ${t_grande}ms" \
      'dez vezes a entrada nao pode custar trinta vezes o tempo'
  fi
}

teste_segredo_em_linha_posterior_tambem_e_redigido() {
  local mensagem
  mensagem=$(dbx_errors_mensagem autenticacao "contexto"$'\n'"token sl.SEGREDO-EM-OUTRA-LINHA")
  assert_nao_contem 'sl.SEGREDO-EM-OUTRA-LINHA' "$mensagem" \
    'a redacao precisa alcancar todas as linhas do detalhe'
  assert_contem 'REDIGIDO' "$mensagem"
}

# ---------------------------------------------------------------------------
# Independencia de camada
# ---------------------------------------------------------------------------

teste_nao_depende_de_jq_nem_de_lib_json() {
  # A camada de dominio nao pode presumir interpretador JSON (DP-08 em aberto,
  # e `jq` descartado pelo solicitante). lib/errors recebe strings ja extraidas.
  # A analise recai sobre o codigo executavel: linhas de comentario sao
  # descartadas, porque a documentacao do componente cita, de proposito, a
  # divergencia registrada em relacao ao System Design.
  local alvo="$DBX_HARNESS_RAIZ/lib/errors.sh" codigo
  assert_arquivo_existe "$alvo" 'o componente sob analise precisa existir'
  codigo=$(grep -vE '^[[:space:]]*#' "$alvo")

  if printf '%s\n' "$codigo" | grep -qE '(^|[^_a-zA-Z.])jq([^_a-zA-Z]|$)'; then
    _harness_falhar 'lib/errors.sh invoca jq'
  fi
  if printf '%s\n' "$codigo" | grep -qE 'lib/json|dbx_json_'; then
    _harness_falhar 'lib/errors.sh depende de lib/json, violando a direcao de dependencia'
  fi
  if printf '%s\n' "$codigo" | grep -qE '(^|[^_a-zA-Z])curl|dbx_http_|dbx_config_'; then
    _harness_falhar 'lib/errors.sh depende da camada de adaptadores'
  fi
}

# ---------------------------------------------------------------------------
# C2-05 — sobre-redacao destroi o diagnostico que RF-29, RF-30 e RNF-08 exigem.
# A chave precisa casar em fronteira, e nao por substring.
# ---------------------------------------------------------------------------

teste_chaves_que_apenas_terminam_em_code_nao_sao_redigidas() {
  local entrada saida
  for entrada in 'error_code=409' 'exit_code=13' 'status_code: 500' 'geocode=BR' \
    '{"error_code":409}' 'http_status_code=429'; do
    saida=$(dbx_errors_redigir "$entrada")
    assert_igual "$entrada" "$saida" "diagnostico destruido em [$entrada]"
  done
}

teste_chave_code_isolada_continua_sendo_redigida() {
  local saida
  saida=$(dbx_errors_redigir 'code=AUTORIZACAO123')
  assert_nao_contem 'AUTORIZACAO123' "$saida"
  assert_contem 'REDIGIDO' "$saida"
}

teste_cabecalho_sensivel_preserva_o_nome_e_o_restante_da_linha() {
  # RF-30 existe para preservar o identificador de requisicao. Apagar a linha
  # inteira leva junto justamente o dado de diagnostico.
  local saida
  saida=$(dbx_errors_redigir 'Authorization: Bearer sl.SEGREDO'$'\n''X-Dropbox-Request-Id: abc123')
  assert_nao_contem 'sl.SEGREDO' "$saida"
  assert_contem 'abc123' "$saida" 'o identificador de requisicao precisa sobreviver (RF-30)'
  assert_contem 'Authorization' "$saida" 'o nome do cabecalho e diagnostico, nao segredo'
}

# ---------------------------------------------------------------------------
# C2-11 — formas residuais
# ---------------------------------------------------------------------------

teste_redacao_de_valor_json_sem_aspas() {
  _assert_redige '9pQrSegredo' '{"refresh_token":9pQrSegredo}' 'valor JSON sem aspas'
}

teste_redacao_de_chave_com_hifen() {
  _assert_redige 'SEG9pQr' '{"client-secret":"SEG9pQr"}' 'chave com hifen'
}

teste_redacao_de_valor_em_arranjo() {
  _assert_redige '9pQrSegredo' '{"tokens":["9pQrSegredo"]}' 'valor dentro de arranjo'
}

# ---------------------------------------------------------------------------
# C2-04 — a truncagem nao pode criar bypass da redacao
# ---------------------------------------------------------------------------

teste_truncagem_nao_deixa_segredo_escapar() {
  # O segredo e posicionado ATRAVESSANDO o corte: comeca antes e termina depois.
  # Era assim que o defeito se manifestava — a truncagem levava embora a aspa de
  # fechamento, a regra deixava de casar e o prefixo do segredo sobrevivia, com
  # o tamanho do vazamento controlado por quem escrevia o corpo.
  local recheio distancia entrada saida
  # O recheio e dimensionado para que o VALOR comece `distancia` caracteres
  # antes do corte, de modo que a chave fique dentro e o valor atravesse.
  for distancia in 20 35 50; do
    printf -v recheio 'x%.0s' $(seq 1 $((4096 - distancia - 25)))
    entrada="{\"a\":\"$recheio\",\"refresh_token\":\"SEGREDOxSEGREDOxSEGREDOxSEGREDOxSEGREDOxSEGREDO\"}"
    saida=$(dbx_errors_redigir "$entrada")
    assert_nao_contem 'SEGREDOxSEGREDO' "$saida" \
      "fragmento do segredo sobreviveu com o corte a $distancia caracteres"
    assert_contem 'REDIGIDO' "$saida" 'o valor precisa ter sido efetivamente mascarado'
  done
}

teste_saida_permanece_limitada_apos_a_redacao() {
  local entrada saida
  printf -v entrada 'z%.0s' $(seq 1 20000)
  saida=$(dbx_errors_redigir "$entrada")
  if [[ ${#saida} -gt 6000 ]]; then
    _harness_falhar "saida sem teto apos a redacao: ${#saida} caracteres"
  fi
}

teste_entrada_acima_do_teto_de_analise_e_truncada_com_redacao() {
  # Acima do teto, a entrada e truncada e o trecho analisado e redigido. Truncar
  # e seguro porque o mascaramento nao depende de delimitador de fechamento —
  # invariante fixada em `valor_sem_delimitador_de_fechamento_e_mascarado_ate_o_fim`.
  local entrada saida
  local recheio
  printf -v recheio 'w%.0s' $(seq 1 40000)
  entrada="sl.TOKENSECRETO refresh_token=9pQrSegredoNoInicio $recheio"
  saida=$(dbx_errors_redigir "$entrada")
  assert_nao_contem 'sl.TOKENSECRETO' "$saida" 'segredo dentro da janela analisada precisa ser mascarado'
  assert_nao_contem '9pQrSegredoNoInicio' "$saida"
  assert_contem 'REDIGIDO' "$saida"
  if [[ ${#saida} -gt 6000 ]]; then
    _harness_falhar "saida sem teto: ${#saida} caracteres"
  fi
}

# ---------------------------------------------------------------------------
# C2-02 — custo da redacao com corpo DENSO em `=`, que e o formato real de
# corpo urlencoded, querystring e trace de cURL. Texto benigno e plano, e por
# isso a medicao anterior nao pegou o custo.
#
# Roda em processo filho sob tempo limite: mutacao lenta deve REPROVAR, e nao
# pendurar a suite.
# ---------------------------------------------------------------------------

teste_custo_da_redacao_com_corpo_denso_e_limitado() {
  local saida status
  saida=$(timeout 120 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/tests/support/harness.sh" || exit 90
    denso() { local n=$1 s="" i; for ((i=0;i<n;i++)); do s+="secret$i=v$i&"; done; printf "%s" "$s"; }
    _redigir_denso() { dbx_errors_redigir "$1"; }
    corpo_pequeno=$(denso 448)
    corpo_grande=$(denso 3584)
    printf "%s %s\n" \
      "$(_medir_minimo_ms 5 _redigir_denso "$corpo_pequeno")" \
      "$(_medir_minimo_ms 5 _redigir_denso "$corpo_grande")"
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  status=$?

  if [[ $status -eq 124 ]]; then
    _harness_falhar 'a redacao nao terminou em 120s com corpo denso em `=`' \
      'sintoma de custo super-linear; foi assim que C2-02 passou despercebido'
  fi
  assert_igual 0 "$status" 'a medicao precisa concluir'

  local -a t
  read -r -a t <<<"$saida"
  [[ ${#t[@]} -eq 2 ]] || _harness_falhar "medicao invalida: [$saida]"

  # Razao entre MINIMOS. Oito vezes a entrada nao pode custar quarenta vezes o
  # tempo. O limite absoluto que existia aqui foi removido: ele media VELOCIDADE
  # da maquina, nao complexidade, e era o mais fragil dos tres sob carga, porque
  # nenhuma razao o normalizava.
  local primeiro=${t[0]} ultimo=${t[1]}
  [[ $primeiro -lt 1 ]] && primeiro=1
  if [[ $ultimo -gt $((primeiro * 40)) ]]; then
    _harness_falhar "custo super-linear: 448 pares em ${primeiro}ms, 3584 pares em ${ultimo}ms" \
      'oito vezes a entrada nao pode custar quarenta vezes o tempo'
  fi
}

teste_teto_de_redacao_nao_e_afrouxavel_pelo_ambiente() {
  # C2-10: o teto e o unico freio do custo; se vier do ambiente, nao e freio.
  local tamanho
  tamanho=$(DBX_ERRORS_LIMITE_REDACAO=999999 timeout 30 bash -c '
    . "$1/lib/errors.sh" || exit 90
    printf -v entrada "y%.0s" $(seq 1 20000)
    saida=$(dbx_errors_redigir "$entrada")
    printf "%s" "${#saida}"
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  if [[ ! $tamanho =~ ^[0-9]+$ ]]; then
    _harness_falhar "medicao invalida do teto: [$tamanho]"
  fi
  if [[ $tamanho -gt 6000 ]]; then
    _harness_falhar "o teto foi afrouxado pelo ambiente: saida de $tamanho caracteres"
  fi
}

# ---------------------------------------------------------------------------
# C2-03 — classificacao e politica nao podem se contradizer.
# A politica precisa CONSULTAR a classificacao, e nao reimplementar uma decisao
# rasa por codigo HTTP.
# ---------------------------------------------------------------------------

teste_politica_concorda_com_a_classificacao_em_limite_de_taxa() {
  # Contencao de lock de namespace da Dropbox: o servico manda repetir. Chegando
  # como 429 acertava; como 409, abortava o lote.
  local resumo
  for resumo in 'too_many_write_operations/.' 'path/rate_limit/.' 'too_many_requests/.'; do
    assert_igual limite_taxa "$(dbx_errors_classificar 409 "$resumo")" "classe de [$resumo]"
    assert_igual respeitar_retry_after "$(dbx_errors_politica_retentativa 409 "$resumo")" \
      "politica de [$resumo] precisa acompanhar a classe"
  done
}

teste_politica_concorda_com_a_classificacao_em_erro_remoto() {
  assert_igual erro_remoto "$(dbx_errors_classificar 409 'transient_error/.')"
  assert_igual recuo_exponencial "$(dbx_errors_politica_retentativa 409 'transient_error/.' sim)"
  assert_igual indeterminado "$(dbx_errors_politica_retentativa 409 'internal_error/.' nao)"
}

teste_nenhuma_classe_retentavel_devolve_politica_nenhuma() {
  # Varredura de coerencia: toda combinacao cuja CLASSE e retentavel precisa ter
  # politica diferente de `nenhuma`.
  local resumo classe politica
  for resumo in 'too_many_write_operations/.' 'path/rate_limit/.' 'transient_error/.' \
    'internal_error/.' 'lookup_failed/incorrect_offset/.' 'reset/.'; do
    classe=$(dbx_errors_classificar 409 "$resumo")
    politica=$(dbx_errors_politica_retentativa 409 "$resumo" sim)
    if [[ $politica == 'nenhuma' ]]; then
      _harness_falhar "classe $classe de [$resumo] e retentavel, mas a politica diz nenhuma"
    fi
  done
}

# ---------------------------------------------------------------------------
# C2-12 — `incorrect_offset` carrega o deslocamento correto: manda RETOMAR, e
# nao reexecutar. Dizer "reexecute" reinicia envio de varios GB.
# ---------------------------------------------------------------------------

teste_deslocamento_incorreto_pede_retomada_e_nao_reinicio() {
  assert_igual retomar "$(dbx_errors_politica_retentativa 409 'lookup_failed/incorrect_offset/.')"
  assert_diferente reiniciar "$(dbx_errors_politica_retentativa 409 'lookup_failed/incorrect_offset/.')"
  assert_igual reiniciar "$(dbx_errors_politica_retentativa 409 'reset/.')" \
    'cursor invalidado continua sendo reinicio, nao retomada'
}

# ---------------------------------------------------------------------------
# Decisao do solicitante: `5xx` segue a mesma regra de `http=0`
# ---------------------------------------------------------------------------

teste_5xx_segue_a_idempotencia_como_a_falha_de_transporte() {
  assert_igual recuo_exponencial "$(dbx_errors_politica_retentativa 500 '' sim)"
  assert_igual indeterminado "$(dbx_errors_politica_retentativa 500 '' nao)"
  assert_igual recuo_exponencial "$(dbx_errors_politica_retentativa 503 '' sim)"
  assert_igual indeterminado "$(dbx_errors_politica_retentativa 503 '' nao)"
}

# ---------------------------------------------------------------------------
# Decisao do solicitante: mensagem de `configuracao` nao pode presumir credencial
# ---------------------------------------------------------------------------

teste_mensagem_de_configuracao_nao_presume_credencial() {
  # A classe cobre tambem utilitario de sistema ausente e area temporaria
  # indisponivel. Falar so em credencial manda o operador investigar um arquivo
  # que esta intacto.
  local mensagem
  mensagem=$(dbx_errors_mensagem configuracao)
  assert_nao_contem 'credencial' "$mensagem" \
    'a mensagem nao pode restringir o diagnostico a credencial'
}

teste_arquivo_de_teste_com_filtro_sem_correspondencia_reprova() {
  # C2-09: mesma falha do executor, um nivel abaixo e alcancavel por invocacao
  # direta em integracao continua. `1..0` com codigo de saida 0 e job verde que
  # nao executou nada.
  local saida status
  saida=$(timeout 30 bash "$DBX_HARNESS_RAIZ/tests/unit/errors_test.sh" filtro_que_nao_existe_xyz 2>&1)
  status=$?
  assert_diferente 0 "$status" 'filtro sem correspondencia precisa reprovar'
  assert_contem 'nao_ok=1' "$saida" 'o agregado precisa registrar a falha'
}

# ---------------------------------------------------------------------------
# R-01 — o separador interno nao pode ser consumido do texto do usuario.
#
# O byte usado internamente para marcar fronteiras era removido pela divisao e
# nunca voltava na juncao. Isso quebrava a fidelidade byte a byte E permitia
# contornar a redacao: um byte de controle dentro do nome da chave a partia em
# dois termos, nenhum deles sensivel, e o segredo saia com aparencia de texto
# normal nao redigido — a pior forma possivel, porque nada no diagnostico
# indicava que a redacao havia sido contornada.
# ---------------------------------------------------------------------------

teste_byte_de_controle_em_chave_sensivel_nao_contorna_a_redacao() {
  local entrada saida
  entrada=$'{"access\001_token":"9pQrRefreshTokenAbcdef"}'
  saida=$(dbx_errors_redigir "$entrada")
  assert_nao_contem '9pQrRefreshTokenAbcdef' "$saida" \
    'byte de controle dentro da chave nao pode liberar o valor'
  assert_contem 'REDIGIDO' "$saida" 'a recusa precisa ser visivel no diagnostico'
}

teste_byte_de_controle_nao_e_apagado_silenciosamente() {
  local saida
  saida=$(dbx_errors_redigir $'ctrl\001aqui')
  assert_diferente 'ctrlaqui' "$saida" \
    'apagar o byte em silencio esconde do operador que houve manipulacao'
  assert_contem 'REDIGIDO' "$saida"
}

teste_fidelidade_byte_a_byte_para_entrada_aceita() {
  # A invariante declarada no cabecalho da funcao: sem segredo, a saida e a
  # entrada, byte a byte.
  local entrada
  entrada='path/not_found/. em /pasta/nome com espaco, "aspas", {chaves} e [colchetes]'$'\n''  linha indentada	com tabulacao'
  assert_igual "$entrada" "$(dbx_errors_redigir "$entrada")" \
    'texto sem segredo precisa atravessar sem alteracao'
}

# ---------------------------------------------------------------------------
# R-02 — aspa escapada nao pode encerrar o mascaramento
# ---------------------------------------------------------------------------

teste_aspa_escapada_no_valor_nao_encerra_o_mascaramento() {
  local saida
  saida=$(dbx_errors_redigir '{"refresh_token":"a\"b9pQrRefreshTokenAbcdef"}')
  assert_nao_contem '9pQrRefreshTokenAbcdef' "$saida" \
    'a aspa escapada faz parte do valor, e nao o encerra'
  assert_contem 'REDIGIDO' "$saida"
}

teste_aspa_escapada_em_senha_com_pontuacao() {
  local saida
  saida=$(dbx_errors_redigir '{"password":"aa\"bb\"ccSenhaSecreta"}')
  assert_nao_contem 'SenhaSecreta' "$saida"
}

# ---------------------------------------------------------------------------
# R-03 — a guarda de espaco em `bearer`/`basic` precisa de teste proprio.
# Sem ela, `"token_type":"bearer"` dispara a regra de esquema e consome o
# fechamento do JSON.
# ---------------------------------------------------------------------------

teste_esquema_de_autenticacao_exige_espaco_antes_da_credencial() {
  local entrada saida
  entrada='{"token_type":"bearer","expires_in":14400}'
  saida=$(dbx_errors_redigir "$entrada")
  assert_igual "$entrada" "$saida" \
    'bearer como VALOR de JSON nao e esquema de autenticacao'

  entrada='{"scheme":"basic","retry":3}'
  assert_igual "$entrada" "$(dbx_errors_redigir "$entrada")" \
    'idem para basic'

  # E o esquema de verdade continua sendo tratado.
  saida=$(dbx_errors_redigir 'Bearer 9pQrCredencialReal')
  assert_nao_contem '9pQrCredencialReal' "$saida"
}

# ---------------------------------------------------------------------------
# R-06 — a INVARIANTE que sustenta a conclusao sobre a ordem entre redigir e
# truncar: valor sem delimitador de fechamento e mascarado ate o fim da entrada.
#
# Enquanto ela nao estiver fixada por teste, um refatoramento que reintroduza
# dependencia de delimitador de fechamento devolve o bypass de truncagem sem que
# nada acuse — nem a mutacao de ordem, que e semanticamente nula.
# ---------------------------------------------------------------------------

teste_valor_sem_delimitador_de_fechamento_e_mascarado_ate_o_fim() {
  local saida entrada
  for entrada in '{"refresh_token":"9pQrSegredoSemFechamento' \
    'client_secret=9pQrSegredoSemFechamento' \
    '{"access_token": "9pQrSegredoSemFechamento' \
    'Authorization: Bearer 9pQrSegredoSemFechamento'; do
    saida=$(dbx_errors_redigir "$entrada")
    assert_nao_contem '9pQrSegredoSemFechamento' "$saida" \
      "valor sem fechamento precisa ser mascarado ate o fim em [$entrada]"
    assert_contem 'REDIGIDO' "$saida"
  done
}

harness_executar "$@"
