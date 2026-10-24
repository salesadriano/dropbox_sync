#!/usr/bin/env bash
# Testes de lib/disponibilidade.sh e de dbx_http_sondar (RF-149, RF-150,
# RF-152(a); TC-DSP-13..21, 22..25, 27). Duplo de `curl` no caminho de busca.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/disponibilidade.sh"

# _duplo <codigo|falha> — instala o `curl` falso; devolve o diretorio.
_duplo() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/dsp.XXXXXX")
  printf '#!%s\nbase=%s\ncodigo=%s\n' "$(command -v bash)" "$dir" "$1" >"$dir/curl"
  cat >>"$dir/curl" <<'FIM'
read -r -d '' conf
saida=""; escrever=""; anterior=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  anterior=$arg
done
printf 'ARGV: %s CONF: %s\n' "$*" "${conf//$'\n'/ ; }" >>"$base/pedidos"
[[ $codigo == falha ]] && exit 28
[[ -n $saida ]] && printf 'corpo' >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

teste_sondar_qualquer_status_http_responde() {
  local dir status
  for status in 200 204 302 404 503; do
    dir=$(_duplo "$status")
    PATH="$dir:$PATH" dbx_http_sondar 'https://exemplo.test/p'
    assert_igual 0 $? "status $status responde"
    assert_igual "$status" "$DBX_HTTP_SONDA_CODIGO" 'codigo publicado'
  done
}

teste_sondar_sem_resposta_nao_responde_e_codigo_zero() {
  local dir
  dir=$(_duplo falha)
  PATH="$dir:$PATH" dbx_http_sondar 'https://exemplo.test/p'
  assert_diferente 0 $? 'sem resposta HTTP'
  assert_igual 0 "$DBX_HTTP_SONDA_CODIGO" 'codigo zero'
}

teste_sondar_requisicao_minima_sem_segredo_nem_repeticao() {
  local dir pedidos
  dir=$(_duplo 204)
  PATH="$dir:$PATH" dbx_http_sondar 'https://exemplo.test/p'
  pedidos=$(<"$dir/pedidos")
  assert_igual 1 "$(wc -l <"$dir/pedidos" | tr -d " ")" 'uma requisicao, sem repeticao'
  assert_contem 'connect-timeout = 5' "$pedidos" 'conexao'
  assert_contem 'max-time = 10' "$pedidos" 'total'
  assert_nao_contem 'Authorization' "$pedidos" 'sem token'
  assert_nao_contem 'data' "$pedidos" 'sem corpo'
  assert_nao_contem ' -L' "$pedidos" 'sem redirecionamento'
}

teste_sonda_url_padrao_vazia_e_invalida() {
  unset DBX_TESTE_INTERNET_URL
  dbx_disp_sonda_configurar
  assert_igual padrao "$DBX_DISP_SONDA_ESTADO" 'nao definida'
  assert_igual 'https://www.gstatic.com/generate_204' "$DBX_DISP_SONDA_URL" 'padrao'
  DBX_TESTE_INTERNET_URL='https://exemplo.test/ping' dbx_disp_sonda_configurar
  assert_igual 'https://exemplo.test/ping' "$DBX_DISP_SONDA_URL" 'configurada'
  DBX_TESTE_INTERNET_URL='' dbx_disp_sonda_configurar
  assert_igual desligada "$DBX_DISP_SONDA_ESTADO" 'vazia desliga'
  DBX_TESTE_INTERNET_URL='http://x' dbx_disp_sonda_configurar
  assert_igual invalida "$DBX_DISP_SONDA_ESTADO" 'nao https'
  assert_igual '' "$DBX_DISP_SONDA_URL" 'URL invalida nao e guardada'
}

teste_sonda_uma_por_execucao() {
  local dir
  dir=$(_duplo 204)
  unset DBX_TESTE_INTERNET_URL
  # shellcheck disable=SC2034  # lido pela lib
  DBX_DISP_INTERNET_FEITA=nao
  PATH="$dir:$PATH" dbx_disp_internet
  PATH="$dir:$PATH" dbx_disp_internet
  assert_igual responde "$DBX_DISP_INTERNET" 'responde'
  assert_igual 1 "$(wc -l <"$dir/pedidos" | tr -d " ")" 'memoizada (RF-149(g))'
}

# DIV-331 candidata (RF-149(g)): a sonda e uma por EXECUCAO, tambem entre os
# processos de um mesmo comando (auxiliares em background do `sync`), por marca
# em diretorio da execucao.
teste_sonda_uma_por_execucao_entre_processos_com_marca_compartilhada() {
  local dir marca
  dir=$(_duplo 204)
  marca=$(mktemp -d "$DBX_TESTES_TMP/marca.XXXXXX")
  unset DBX_TESTE_INTERNET_URL
  dbx_disp_compartilhar_sonda "$marca"
  (
    PATH="$dir:$PATH" DBX_DISP_INTERNET_FEITA=nao dbx_disp_internet
  ) &
  (
    PATH="$dir:$PATH" DBX_DISP_INTERNET_FEITA=nao dbx_disp_internet
  ) &
  wait
  assert_igual 1 "$(wc -l <"$dir/pedidos" | tr -d " ")" 'uma sonda para os dois processos'
}

# DIV-331 A: quem perde a reserva ESPERA o resultado do vencedor e adota a causa.
teste_perdedor_da_reserva_espera_e_recebe_a_causa_do_vencedor() {
  local marca
  marca=$(mktemp -d "$DBX_TESTES_TMP/marca.XXXXXX")
  : >"$marca/sonda.reserva"
  (
    sleep 0.3
    printf '%s\n' nao_responde >"$marca/sonda.resultado"
  ) &
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao DBX_DISP_ESPERA_MS=5000
  dbx_disp_compartilhar_sonda "$marca"
  dbx_disp_internet
  wait
  assert_igual nao_responde "$DBX_DISP_INTERNET" 'causa do vencedor'
}

# DIV-331 A: sem resultado no prazo, a causa e indeterminada.
teste_perdedor_sem_resultado_no_prazo_da_causa_indeterminada() {
  local marca
  marca=$(mktemp -d "$DBX_TESTES_TMP/marca.XXXXXX")
  : >"$marca/sonda.reserva"
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao DBX_DISP_ESPERA_MS=200
  dbx_disp_compartilhar_sonda "$marca"
  dbx_disp_internet
  assert_igual indeterminada "$DBX_DISP_INTERNET" 'prazo esgotado'
}

# RF-149(b), DIV-310 A: URL de sonda invalida avisa em stderr, uma vez por
# execucao, sem o valor da variavel.
teste_sonda_invalida_avisa_uma_vez_sem_o_valor() {
  local erro
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao DBX_DISP_AVISO_FEITO=nao
  export DBX_TESTE_INTERNET_URL='http://segredo.test/x?tok=ABC123'
  erro=$(
    {
      dbx_disp_nomear_falha rede
      dbx_disp_nomear_falha rede
    } 2>&1 >/dev/null
  )
  unset DBX_TESTE_INTERNET_URL
  assert_contem 'DBX_TESTE_INTERNET_URL' "$erro" 'nomeia a variavel'
  assert_nao_contem 'segredo' "$erro" 'sem o valor'
  assert_nao_contem 'ABC123' "$erro" 'sem o valor'
  assert_igual 1 "$(grep -c 'DBX_TESTE_INTERNET_URL' <<<"$erro")" 'uma vez por execucao'
}

# RF-151(e): a causa enriquece o resumo de erro, preservando o original.
teste_causa_enriquece_o_resumo_de_erro_sem_perder_o_original() {
  # shellcheck disable=SC2034  # lido pela lib
  DBX_DISP_INTERNET_FEITA=nao
  export DBX_TESTE_INTERNET_URL=''
  DBX_HTTP_RESUMO_DE_ERRO='conexao recusada'
  dbx_disp_ao_falhar_chamada 9
  unset DBX_TESTE_INTERNET_URL
  assert_contem 'sem acesso a internet ou Dropbox inacessivel' "$DBX_HTTP_RESUMO_DE_ERRO" 'causa'
  assert_contem 'conexao recusada' "$DBX_HTTP_RESUMO_DE_ERRO" 'original preservado'
}

teste_classificar_tabela_unica_de_classes_e_codigos() {
  dbx_disp_mensagem sem_internet
  assert_igual rede "$DBX_DISP_CLASSE" 'sem internet'
  assert_contem 'sem acesso a internet' "$DBX_DISP_MENSAGEM" 'mensagem'
  dbx_disp_mensagem dropbox_inacessivel
  assert_igual rede "$DBX_DISP_CLASSE" 'inacessivel'
  assert_contem 'Dropbox inacessivel' "$DBX_DISP_MENSAGEM" 'mensagem'
  dbx_disp_mensagem dropbox_indisponivel
  assert_igual erro_remoto "$DBX_DISP_CLASSE" '5xx'
  assert_contem 'servico Dropbox indisponivel' "$DBX_DISP_MENSAGEM" 'mensagem'
  dbx_disp_mensagem limite_taxa
  assert_igual limite_taxa "$DBX_DISP_CLASSE" '429'
  dbx_disp_mensagem sonda_desligada
  assert_igual rede "$DBX_DISP_CLASSE" 'sonda desligada'
  assert_contem 'sonda desligada' "$DBX_DISP_MENSAGEM" 'nao distingue as causas'
}

teste_mensagens_sem_segredo_url_com_parametro_nem_corpo() {
  local causa
  for causa in sem_internet dropbox_inacessivel dropbox_indisponivel limite_taxa sonda_desligada; do
    dbx_disp_mensagem "$causa"
    assert_nao_contem '?' "$DBX_DISP_MENSAGEM$DBX_DISP_REMEDIO" "sem parametro de URL ($causa)"
    assert_nao_contem 'Bearer' "$DBX_DISP_MENSAGEM$DBX_DISP_REMEDIO" "sem cabecalho ($causa)"
    assert_nao_contem 'http' "$DBX_DISP_MENSAGEM$DBX_DISP_REMEDIO" "sem URL ($causa)"
  done
}

teste_portao_fechado_sem_terminal_e_com_as_chaves() {
  DBX_TESTE_CONFIG='' DBX_DISP_OFERTA_FEITA=nao dbx_disp_oferta_possivel </dev/null
  assert_diferente 0 $? 'sem terminal'
  DBX_TESTE_CONFIG=nao DBX_DISP_OFERTA_FEITA=nao dbx_disp_oferta_possivel
  assert_diferente 0 $? 'DBX_TESTE_CONFIG=nao'
  DBX_DISP_OFERTA_FEITA=sim dbx_disp_oferta_possivel
  assert_diferente 0 $? 'uma oferta por execucao'
}


# N2 (RF-149(b)): auxiliar com stderr descartado nao consome o aviso; o principal
# o emite, uma vez, sem o valor.
teste_aviso_de_sonda_invalida_do_auxiliar_sai_pelo_principal() {
  local marca erro
  marca=$(mktemp -d "$DBX_TESTES_TMP/marca.XXXXXX")
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao DBX_DISP_AVISO_FEITO=nao
  export DBX_TESTE_INTERNET_URL='http://segredo.test/x?tok=ABC123'
  dbx_disp_compartilhar_sonda "$marca"
  (
    dbx_disp_nomear_falha rede
  ) </dev/null >/dev/null 2>&1
  erro=$(
    {
      dbx_disp_emitir_aviso_pendente
      dbx_disp_emitir_aviso_pendente
    } 2>&1 >/dev/null
  )
  unset DBX_TESTE_INTERNET_URL
  assert_igual 1 "$(grep -c 'DBX_TESTE_INTERNET_URL' <<<"$erro")" 'um aviso no stderr do principal'
  assert_nao_contem 'ABC123' "$erro" 'sem o valor'
}

# R5 (rodada 3): chamada com stderr descartado, fora do sync, nao consome o aviso;
# a chamada seguinte, com stderr visivel, o emite uma vez (e so uma).
teste_aviso_nao_e_consumido_com_stderr_descartado() {
  local erro
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao DBX_DISP_AVISO_FEITO=nao
  dbx_disp_compartilhar_sonda ''
  export DBX_TESTE_INTERNET_URL='http://segredo.test/x?tok=ABC123'
  dbx_disp_nomear_falha rede >/dev/null 2>&1
  assert_igual nao "$DBX_DISP_AVISO_FEITO" 'stderr descartado nao marca o aviso como feito'
  DBX_DISP_INTERNET_FEITA=nao
  erro=$({ dbx_disp_nomear_falha rede; dbx_disp_nomear_falha rede; } 2>&1 >/dev/null)
  unset DBX_TESTE_INTERNET_URL
  assert_igual 1 "$(grep -c 'DBX_TESTE_INTERNET_URL' <<<"$erro")" 'um aviso quando o stderr chega ao operador'
  assert_nao_contem 'ABC123' "$erro" 'sem o valor'
}

# N4: diretorio ausente nao espera; sonda local.
teste_diretorio_compartilhado_ausente_sonda_localmente() {
  local dir antes
  dir=$(_duplo 204)
  unset DBX_TESTE_INTERNET_URL
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao
  dbx_disp_compartilhar_sonda "$DBX_TESTES_TMP/nao-existe"
  antes=$SECONDS
  PATH="$dir:$PATH" dbx_disp_internet
  assert_igual responde "$DBX_DISP_INTERNET" 'sondou localmente'
  assert_igual 1 "$(wc -l <"$dir/pedidos" | tr -d " ")" 'uma sonda'
  ((SECONDS - antes < 3)) || assert_igual 'rapido' 'lento' 'sem espera'
}

# N4: reserva orfa (PID do vencedor inexistente) nao espera o prazo inteiro.
teste_reserva_orfa_nao_espera_o_prazo() {
  local marca antes
  marca=$(mktemp -d "$DBX_TESTES_TMP/marca.XXXXXX")
  printf '%s\n' 999999999 >"$marca/sonda.reserva"
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao DBX_DISP_ESPERA_MS=20000
  dbx_disp_compartilhar_sonda "$marca"
  antes=$SECONDS
  dbx_disp_internet
  assert_igual indeterminada "$DBX_DISP_INTERNET" 'vencedor morto'
  ((SECONDS - antes < 3)) || assert_igual 'rapido' 'lento' 'sem esperar 20 s'
}

# N7: valor inesperado em sonda.resultado vira indeterminada.
teste_resultado_fora_do_vocabulario_vira_indeterminada() {
  local marca
  marca=$(mktemp -d "$DBX_TESTES_TMP/marca.XXXXXX")
  : >"$marca/sonda.reserva"
  printf '%s\n' lixo >"$marca/sonda.resultado"
  # shellcheck disable=SC2034  # lidos pela lib
  DBX_DISP_INTERNET_FEITA=nao
  dbx_disp_compartilhar_sonda "$marca"
  dbx_disp_internet
  assert_igual indeterminada "$DBX_DISP_INTERNET" 'valor inesperado'
}

# #6: o motivo da autenticacao e enriquecido, nao substituido.
teste_motivo_da_autenticacao_preserva_o_original() {
  . "$DBX_HARNESS_RAIZ/lib/auth.sh"
  DBX_AUTH_MOTIVO='motivo original'
  dbx_disp_mensagem sem_internet
  _dbx_disp_publicar_causa auth
  assert_contem 'sem acesso a internet' "$DBX_AUTH_MOTIVO" 'causa nomeada'
  assert_contem 'motivo original' "$DBX_AUTH_MOTIVO" 'original preservado'
}

harness_executar "$@"
