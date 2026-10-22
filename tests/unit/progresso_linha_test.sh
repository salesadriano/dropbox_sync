#!/usr/bin/env bash
# Testes do progresso por arquivo em lib/progress.sh (F-49; RF-140 a RF-147;
# TC-PRG-01, 03, 04, 10, 11, 12, 13, 15, 27, 29, 30, 31, 32). Seam: funcoes
# publicas dbx_progress_arquivo_*; o terminal e simulado por DBX_PROGRESS_TERMINAL.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/progress.sh"

_prg_preparar() {
  # shellcheck disable=SC2034  # lidos por lib/progress
  DBX_CLI_PROGRESSO='sim'
  # shellcheck disable=SC2034  # lido por lib/progress
  DBX_PROGRESS_TERMINAL="${1:-nao}"
  # shellcheck disable=SC2034  # lido por lib/progress (deteccao de UTF-8)
  LC_ALL=C.UTF-8
  COLUMNS=80
  ARQ_ERR="$DBX_TESTES_TMP/prg_err.$$.$RANDOM"
  : >"$ARQ_ERR"
}

_prg_conteudo() {
  CONTEUDO=$(
    cat "$ARQ_ERR"
    printf x
  )
  CONTEUDO=${CONTEUDO%x}
}

_prg_vivo() { kill -0 "$1" 2>/dev/null; }

teste_linha_tem_formato_posicao_barra_percentual_e_bytes() {
  _prg_preparar
  {
    dbx_progress_arquivo_iniciar 3 10 enviando fotos/a.jpg 10485760
    dbx_progress_arquivo_avancar 4194304
  } 2>"$ARQ_ERR"
  assert_igual '[3/10] enviando: fotos/a.jpg [░░░░░░░░░░] 0% 0 B / 10 MiB' "$(head -n 1 "$ARQ_ERR")" 'RF-141(a): inicia em 0%'
  assert_igual '[3/10] enviando: fotos/a.jpg [████░░░░░░] 40% 4 MiB / 10 MiB' "$(tail -n 1 "$ARQ_ERR")" 'RF-140: percentual do arquivo no fim'
}

teste_percentual_arredonda_para_baixo_e_nunca_cem_antes_de_concluir() {
  _prg_preparar
  {
    dbx_progress_arquivo_iniciar 1 1 enviando x 1000
    dbx_progress_arquivo_avancar 999
    dbx_progress_arquivo_avancar 1000
  } 2>"$ARQ_ERR"
  _prg_conteudo
  assert_contem ' 99% ' "$CONTEUDO" 'TC-PRG-04: 999 de 1000 e 99%'
  assert_nao_contem '100%' "$CONTEUDO" 'RF-140(f): 100% so ao concluir'
  dbx_progress_arquivo_concluir 2>>"$ARQ_ERR"
  assert_contem '[██████████] 100% 1000 B / 1000 B' "$(tail -n 1 "$ARQ_ERR")" 'concluir chega a 100%'
}

teste_arquivo_de_zero_bytes_vai_de_zero_a_cem() {
  _prg_preparar
  {
    dbx_progress_arquivo_iniciar 1 1 enviando vazio 0
    dbx_progress_arquivo_concluir
  } 2>"$ARQ_ERR"
  assert_contem ' 0% 0 B / 0 B' "$(head -n 1 "$ARQ_ERR")" 'TC-PRG-11: 0%'
  assert_contem ' 100% 0 B / 0 B' "$(tail -n 1 "$ARQ_ERR")" 'TC-PRG-11: depois 100%'
}

teste_percentual_nunca_diminui() {
  _prg_preparar
  {
    dbx_progress_arquivo_iniciar 1 1 enviando x 100
    dbx_progress_arquivo_avancar 50
    dbx_progress_arquivo_avancar 20
  } 2>"$ARQ_ERR"
  assert_igual 2 "$(wc -l <"$ARQ_ERR" | tr -d ' ')" 'RF-140(g): avanco menor nao gera linha'
  assert_contem ' 50% ' "$(tail -n 1 "$ARQ_ERR")" 'RF-140(g): mantem 50%'
}

teste_retomada_inicia_no_confirmado() {
  _prg_preparar
  dbx_progress_arquivo_iniciar 1 1 enviando x 100 50 2>"$ARQ_ERR"
  assert_contem ' 50% 50 B / 100 B' "$(head -n 1 "$ARQ_ERR")" 'DIV-294: nunca 0% na retomada'
}

teste_total_desconhecido_mostra_so_bytes_feitos() {
  _prg_preparar
  {
    dbx_progress_arquivo_iniciar 1 1 baixando x ''
    dbx_progress_arquivo_avancar 4194304
    dbx_progress_arquivo_concluir
  } 2>"$ARQ_ERR"
  _prg_conteudo
  assert_igual '[1/1] baixando: x 4 MiB' "$(tail -n 1 "$ARQ_ERR")" 'DIV-288: sem barra'
  assert_nao_contem '%' "$CONTEUDO" 'DIV-288: sem percentual'
}

teste_sem_terminal_cada_atualizacao_e_uma_linha_nova_sem_controle() {
  _prg_preparar nao
  {
    dbx_progress_arquivo_iniciar 1 1 enviando grande 300
    dbx_progress_arquivo_avancar 100
    dbx_progress_arquivo_avancar 200
    dbx_progress_arquivo_avancar 299
  } 2>"$ARQ_ERR"
  _prg_conteudo
  assert_igual 4 "$(wc -l <"$ARQ_ERR" | tr -d ' ')" 'TC-PRG-13: 0% mais tres partes'
  assert_nao_contem $'\r' "$CONTEUDO" 'RF-142(b): sem retorno de carro'
  assert_nao_contem $'\033' "$CONTEUDO" 'RF-142(d): sem sequencia de controle'
}

teste_com_terminal_a_mesma_linha_e_atualizada_e_quebra_so_ao_concluir() {
  _prg_preparar sim
  {
    dbx_progress_arquivo_iniciar 1 1 enviando a.bin 100
    dbx_progress_arquivo_avancar 50
  } 2>"$ARQ_ERR"
  _prg_conteudo
  assert_contem $'\r' "$CONTEUDO" 'TC-PRG-12: retorno de carro'
  assert_nao_contem $'\n' "$CONTEUDO" 'TC-PRG-12: sem quebra enquanto em curso'
  dbx_progress_arquivo_concluir 2>>"$ARQ_ERR"
  _prg_conteudo
  local quebras=${CONTEUDO//[^$'\n']/}
  assert_igual 1 "${#quebras}" 'TC-PRG-12: uma quebra, ao concluir'
  assert_igual $'\n' "${CONTEUDO: -1}" 'TC-PRG-12: termina em quebra'
}

teste_falha_deixa_ultimo_percentual_com_sufixo_falhou() {
  _prg_preparar
  {
    dbx_progress_arquivo_iniciar 3 10 enviando fotos/a.jpg 10485760
    dbx_progress_arquivo_avancar 4194304
    dbx_progress_arquivo_falhar
    dbx_progress_arquivo_concluir
  } 2>"$ARQ_ERR"
  _prg_conteudo
  assert_igual '[3/10] enviando: fotos/a.jpg [████░░░░░░] 40% 4 MiB / 10 MiB falhou' "$(tail -n 1 "$ARQ_ERR")" 'TC-PRG-32 / RF-146(b)'
  assert_nao_contem '100%' "$CONTEUDO" 'RF-146(a): nunca forja 100%'
}

teste_falha_no_terminal_termina_a_linha() {
  _prg_preparar sim
  {
    dbx_progress_arquivo_iniciar 1 1 enviando a 100
    dbx_progress_arquivo_avancar 40
    dbx_progress_arquivo_falhar
  } 2>"$ARQ_ERR"
  _prg_conteudo
  assert_contem ' 40% 40 B / 100 B falhou' "$CONTEUDO" 'TC-PRG-31'
  assert_igual $'\n' "${CONTEUDO: -1}" 'TC-PRG-31: linha terminada'
}

teste_sinal_termina_a_linha_em_curso_uma_vez() {
  _prg_preparar sim
  {
    dbx_progress_arquivo_iniciar 1 1 enviando a 100
    dbx_progress_arquivo_encerrar
    dbx_progress_arquivo_encerrar
  } 2>"$ARQ_ERR"
  _prg_conteudo
  local quebras=${CONTEUDO//[^$'\n']/}
  assert_igual 1 "${#quebras}" 'TC-PRG-15: uma quebra de linha'
}

teste_caractere_de_controle_no_nome_vira_interrogacao() {
  _prg_preparar
  dbx_progress_arquivo_iniciar 1 1 enviando $'a\tb\033[31m.txt' 10 2>"$ARQ_ERR"
  _prg_conteudo
  assert_contem 'a?b?[31m.txt' "$CONTEUDO" 'TC-PRG-29'
  assert_nao_contem $'\033' "$CONTEUDO" 'RF-145(d)'
}

teste_nome_longo_e_truncado_pelo_meio_preservando_extensao_no_terminal() {
  _prg_preparar sim
  COLUMNS=60
  dbx_progress_arquivo_iniciar 1 1 enviando 'diretorio/muito/longo/com/nome/enorme/de/arquivo/relatorio-final.pdf' 10485760 2>"$ARQ_ERR"
  _prg_conteudo
  local linha=${CONTEUDO#$'\r'}
  linha=${linha%$'\033[K'}
  assert_contem '....pdf [' "$linha" 'DIV-284: reticencias e extensao'
  assert_contem ' 0% 0 B / 10 MiB' "$linha" 'DIV-284: percentual e bytes nunca truncados'
  assert_status 0 test "${#linha}" -lt 60
}

teste_sem_terminal_nome_longo_nao_e_truncado() {
  _prg_preparar nao
  COLUMNS=60
  dbx_progress_arquivo_iniciar 1 1 enviando 'diretorio/muito/longo/com/nome/enorme/de/arquivo/relatorio-final.pdf' 10 2>"$ARQ_ERR"
  assert_contem 'diretorio/muito/longo/com/nome/enorme/de/arquivo/relatorio-final.pdf' "$(cat "$ARQ_ERR")" 'DIV-284: sem terminal nao trunca'
}

teste_progresso_inativo_nao_emite_nem_inicia_observador() {
  _prg_preparar
  # shellcheck disable=SC2034  # lido por lib/progress
  DBX_CLI_PROGRESSO='nao'
  local f="$DBX_TESTES_TMP/prg_inativo.$$"
  head -c 2097152 /dev/zero >"$f"
  {
    dbx_progress_arquivo_iniciar 1 1 baixando x 4194304
    dbx_progress_arquivo_observar "$f"
    dbx_progress_arquivo_avancar 10
    dbx_progress_arquivo_observar_parar "$f"
    dbx_progress_arquivo_concluir
  } 2>"$ARQ_ERR"
  rm -f "$f"
  assert_igual '' "$(cat "$ARQ_ERR")" 'RF-145(c): nada em stderr'
  assert_igual '' "${_DBX_PRG_OBS_PID:-}" 'RF-145(c): nenhum observador'
  assert_igual '' "$(jobs -p)" 'RF-145(c): nenhum processo adicional'
}

teste_observador_acompanha_o_part_e_nao_deixa_orfao() {
  _prg_preparar nao
  local f="$DBX_TESTES_TMP/prg_part.$$" pid
  head -c 2097152 /dev/zero >"$f"
  # shellcheck disable=SC2094  # le o arquivo que o observador escreve, de proposito
  {
    dbx_progress_arquivo_iniciar 1 1 baixando x 4194304
    dbx_progress_arquivo_observar "$f"
    pid=$_DBX_PRG_OBS_PID
    for ((i = 0; i < 50; i++)); do
      [[ $(<"$ARQ_ERR") == *' 50% 2 MiB'* ]] && break
      sleep 0.1
    done
    dbx_progress_arquivo_observar_parar "$f"
  } 2>"$ARQ_ERR"
  rm -f "$f"
  _prg_conteudo
  assert_contem ' 50% 2 MiB / 4 MiB' "$CONTEUDO" 'TC-PRG-10: segue o tamanho do .part'
  assert_nao_contem '100%' "$CONTEUDO" 'TC-PRG-10: 100% so apos a conferencia'
  assert_status 1 _prg_vivo "$pid"
  assert_igual '' "$_DBX_PRG_OBS_PID" 'TC-PRG-30: identificador limpo'
}

teste_arquivo_abaixo_de_1_mib_nao_tem_observador() {
  _prg_preparar nao
  {
    dbx_progress_arquivo_iniciar 1 1 baixando x 1000
    dbx_progress_arquivo_observar /nao/existe
  } 2>"$ARQ_ERR"
  assert_igual '' "${_DBX_PRG_OBS_PID:-}" 'DIV-282: sem amostra abaixo de 1 MiB'
}


teste_canal_escrita_concorrente_nunca_deixa_status_invalido() {
  _prg_preparar nao
  local canal="$DBX_TESTES_TMP/canal.$$.$RANDOM" w rodadas=0 invalidos=0 f t e vivo
  local -a pids=()
  dbx_progress_canal_definir "$canal"
  _DBX_PRG_TOTAL=1000 _DBX_PRG_ESTADO=ativo
  _DBX_PRG_FEITOS=1
  _dbx_progress_canal_gravar
  for w in 1 2 3; do
    (
      for ((i = 1; i <= 150; i++)); do
        _DBX_PRG_FEITOS=$((w * 100 + i))
        _dbx_progress_canal_gravar || exit 1
      done
    ) &
    pids+=($!)
  done
  vivo=sim
  while [[ $vivo == sim ]]; do
    vivo=nao
    for w in "${pids[@]}"; do kill -0 "$w" 2>/dev/null && vivo=sim; done
    { IFS= read -r f; IFS= read -r t; IFS= read -r e; } <"$canal" 2>/dev/null
    rodadas=$((rodadas + 1))
    [[ $f =~ ^[0-9]+$ && $t == 1000 && $e == ativo ]] || invalidos=$((invalidos + 1))
  done
  for w in "${pids[@]}"; do wait "$w" || _harness_falhar 'um escritor falhou na troca atomica do status'; done
  assert_igual 0 "$invalidos" "o leitor nunca ve status invalido ($rodadas leituras)"
  assert_igual "$canal" "$(find "${canal%/*}" -maxdepth 1 -name "${canal##*/}*")" 'so o arquivo de status resta, sem temporario ao lado'
  rm -f "$canal"
}
harness_executar "$@"
