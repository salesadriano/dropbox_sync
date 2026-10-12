#!/usr/bin/env bash
# Testes de lib/progress.sh — controle, formatacao e emissao de progresso em tempo real.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/progress.sh"

teste_progresso_desativado_por_padrao_sem_terminal() {
  # Sem flag explicita, sob redirecionamento / execucao nao interativa ([ ! -t 2 ]),
  # o progresso deve ficar desativado por padrao (RNF-19).
  DBX_CLI_PROGRESSO='auto'
  # Em ambiente de teste automatizado, stderr e capturado/redirecionado.
  # Garantimos explicitamente que nao seja terminal para a assercao de auto.
  if [[ ! -t 2 ]]; then
    assert_status 1 dbx_progress_ativo
  fi
}

teste_progresso_ativado_por_flag_explicita() {
  # Flag explicita --progresso / -p forca ativacao mesmo em pipes/scripts.
  DBX_CLI_PROGRESSO='sim'
  assert_status 0 dbx_progress_ativo
}

teste_progresso_desativado_por_flag_negativa() {
  # Flag explicita --sem-progresso forca desativacao mesmo em TTY.
  DBX_CLI_PROGRESSO='nao'
  assert_status 1 dbx_progress_ativo
}

teste_progresso_emite_em_stderr_e_preserva_stdout() {
  DBX_CLI_PROGRESSO='sim'
  local saida_out saida_err
  local arq_out="$DBX_TESTES_TMP/p_out.$$" arq_err="$DBX_TESTES_TMP/p_err.$$"

  dbx_progress_mensagem 'mensagem de teste' >"$arq_out" 2>"$arq_err"
  # shellcheck disable=SC2034
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout nao pode ser contaminado com progresso (RF-28, RF-32)'
  assert_contem 'mensagem de teste' "$saida_err" 'stderr deve conter a mensagem de progresso'
}

teste_progresso_silenciado_nao_emite_em_nenhum_descritor() {
  DBX_CLI_PROGRESSO='nao'
  local saida_out saida_err
  local arq_out="$DBX_TESTES_TMP/s_out.$$" arq_err="$DBX_TESTES_TMP/s_err.$$"

  dbx_progress_mensagem 'mensagem de teste' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout deve permanecer vazio'
  assert_igual '' "$saida_err" 'stderr deve permanecer vazio quando silenciado'
}

teste_formatacao_de_bytes() {
  assert_igual '500 B' "$(dbx_progress_formatar_bytes 500)" 'bytes'
  assert_igual '2 KiB' "$(dbx_progress_formatar_bytes 2048)" 'kibibytes'
  assert_igual '10 MiB' "$(dbx_progress_formatar_bytes 10485760)" 'mebibytes'
  assert_igual '1 GiB' "$(dbx_progress_formatar_bytes 1073741824)" 'gibibytes'
}

teste_etapa_formata_e_emite_em_stderr() {
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/e_out.$$" arq_err="$DBX_TESTES_TMP/e_err.$$"
  local saida_out saida_err

  dbx_progress_etapa 3 10 'enviando' 'documentos/relatorio.pdf' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout vazio'
  assert_contem '[3/10] enviando: documentos/relatorio.pdf' "$saida_err" 'formato de etapa em stderr'
}

teste_transferencia_formata_com_percentual_em_stderr() {
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/t_out.$$" arq_err="$DBX_TESTES_TMP/t_err.$$"
  local saida_out saida_err

  # 1 MiB de 4 MiB = 25%
  dbx_progress_transferencia 'upload' 1048576 4194304 'parte 1' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout vazio'
  assert_contem '[upload] parte 1: 1 MiB / 4 MiB (25%)' "$saida_err" 'progresso com percentual'
}

teste_barra_gerar_percentual_zero_e_cem() {
  local barra_0='' barra_100=''
  dbx_progress_barra_gerar 0 10 barra_0
  dbx_progress_barra_gerar 100 10 barra_100

  assert_contem '[' "$barra_0" 'delimitador inicial'
  assert_contem ']' "$barra_0" 'delimitador final'
  assert_contem '[' "$barra_100" 'delimitador inicial'
  assert_contem ']' "$barra_100" 'delimitador final'
  assert_diferente "$barra_0" "$barra_100" '0% e 100% devem ser graficamente distintos'
}

teste_barra_gerar_valores_intermediarios_e_limites() {
  local b50='' b_neg='' b_sup=''
  dbx_progress_barra_gerar 50 10 b50
  dbx_progress_barra_gerar -20 10 b_neg
  dbx_progress_barra_gerar 200 10 b_sup

  local b0='' b100=''
  dbx_progress_barra_gerar 0 10 b0
  dbx_progress_barra_gerar 100 10 b100

  assert_igual "$b0" "$b_neg" 'valor negativo deve limitar em 0%'
  assert_igual "$b100" "$b_sup" 'valor acima de 100 deve limitar em 100%'
  assert_diferente "$b0" "$b50" '50% deve ser diferente de 0%'
  assert_diferente "$b100" "$b50" '50% deve ser diferente de 100%'
}

teste_barra_grafica_emite_em_stderr_e_preserva_stdout() {
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/bg_out.$$" arq_err="$DBX_TESTES_TMP/bg_err.$$"
  local saida_out saida_err

  dbx_progress_barra 'upload' 512 1024 'enviando arquivo' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout deve permanecer vazio'
  assert_contem '[upload]' "$saida_err" 'rotulo deve estar em stderr'
  assert_contem '50%' "$saida_err" 'percentual deve estar em stderr'
  assert_contem '512 B / 1 KiB' "$saida_err" 'tamanhos formatados em stderr'
  assert_contem 'enviando arquivo' "$saida_err" 'detalhe deve constar em stderr'
}

teste_transferencia_inclui_barra_grafica_em_stderr() {
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/tb_out.$$" arq_err="$DBX_TESTES_TMP/tb_err.$$"
  local saida_out saida_err

  dbx_progress_transferencia 'download' 2097152 4194304 'bloco A' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout deve permanecer vazio'
  assert_contem '[download] bloco A: 2 MiB / 4 MiB (50%)' "$saida_err" 'progresso com percentual preservado'
  assert_contem '[' "$saida_err" 'delimitador de barra grafica presente'
  assert_contem ']' "$saida_err" 'delimitador de barra grafica fechado'
}

teste_etapa_inclui_barra_grafica_em_stderr() {
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/eb_out.$$" arq_err="$DBX_TESTES_TMP/eb_err.$$"
  local saida_out saida_err

  dbx_progress_etapa 4 10 'recebendo' 'arquivo.zip' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout deve permanecer vazio'
  assert_contem '[4/10] recebendo: arquivo.zip' "$saida_err" 'etapa base preservada'
  assert_contem '(40%)' "$saida_err" 'percentual da etapa calculado'
}

teste_etapa_com_progresso_fracionario_exibe_decimais() {
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/ef_out.$$" arq_err="$DBX_TESTES_TMP/ef_err.$$"
  local saida_out saida_err

  # 47 de 228418 = 0.02%
  dbx_progress_etapa 47 228418 'recebendo' 'arquivo.xml' >"$arq_out" 2>"$arq_err"
  saida_out=$(cat "$arq_out")
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"

  assert_igual '' "$saida_out" 'stdout deve permanecer vazio'
  assert_contem '[47/228418] recebendo: arquivo.xml' "$saida_err" 'etapa identificada'
  assert_contem '(0.02%)' "$saida_err" 'percentual fracionario calculado com 2 casas'

  # 1 de 1000000 = <0.01%
  dbx_progress_etapa 1 1000000 'recebendo' 'arquivo.xml' >"$arq_out" 2>"$arq_err"
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"
  assert_contem '(<0.01%)' "$saida_err" 'percentual menor que 0.01% exibe menor que'

  # 0 de 228418 = 0%
  dbx_progress_etapa 0 228418 'recebendo' 'arquivo.xml' >"$arq_out" 2>"$arq_err"
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"
  assert_contem '(0%)' "$saida_err" 'zero itens preserva 0%'
}

teste_transferencia_e_barra_com_progresso_fracionario() {
  # shellcheck disable=SC2034
  DBX_CLI_PROGRESSO='sim'
  local arq_out="$DBX_TESTES_TMP/tf_out.$$" arq_err="$DBX_TESTES_TMP/tf_err.$$"
  local saida_err

  dbx_progress_barra 'upload' 100 1000000 'iniciando' >"$arq_out" 2>"$arq_err"
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"
  assert_contem '0.01%' "$saida_err" 'barra com percentual fracionario'

  dbx_progress_transferencia 'upload' 100 1000000 'parte 1' >"$arq_out" 2>"$arq_err"
  saida_err=$(cat "$arq_err")
  rm -f "$arq_out" "$arq_err"
  assert_contem '(0.01%)' "$saida_err" 'transferencia com percentual fracionario'
}

harness_executar "$@"
