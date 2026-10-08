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

harness_executar "$@"
