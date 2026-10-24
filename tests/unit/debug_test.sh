#!/usr/bin/env bash
# Testes de lib/debug.sh — ponto unico de emissao das linhas `debug:` (RF-156,
# RF-163(d), RF-164(b); TC-DBG-22, TC-DBG-27, TC-DBG-30).

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/debug.sh"

# _emitir <argumentos de dbx_debug_linha...> — publica em _SAIDA o stderr.
_emitir() {
  _SAIDA=$(DBX_CLI_DEBUG=sim dbx_debug_linha "$@" 2>&1 >/dev/null)
}

teste_linha_tem_prefixo_categoria_e_pares_em_ordem() {
  _emitir upload modalidade=simples arquivo=a.txt bytes=10
  assert_igual 'debug: upload modalidade=simples arquivo=a.txt bytes=10' "$_SAIDA"
}

teste_posicional_entra_sem_chave() {
  _emitir http POST content.dropboxapi.com/2/files/upload tentativa=1
  assert_igual 'debug: http POST content.dropboxapi.com/2/files/upload tentativa=1' "$_SAIDA"
}

teste_valor_com_espaco_vai_entre_aspas() {
  _emitir upload arquivo='meu arquivo.txt'
  assert_igual 'debug: upload arquivo="meu arquivo.txt"' "$_SAIDA"
}

teste_valor_vazio_vai_entre_aspas() {
  _emitir sync motivo=
  assert_igual 'debug: sync motivo=""' "$_SAIDA"
}

teste_aspas_e_barra_sao_escapadas() {
  _emitir upload arquivo='a"b\c'
  assert_igual 'debug: upload arquivo="a\"b\\c"' "$_SAIDA"
}

teste_caractere_de_controle_vira_interrogacao_em_uma_so_linha() {
  _emitir upload arquivo=$'a\nb\tc\rd\x01e'
  [[ $_SAIDA != *$'\n'* ]] || _harness_falhar "mais de uma linha: $_SAIDA"
  assert_contem 'a?b?c?d?e' "$_SAIDA"
}

teste_valor_passa_pela_redacao() {
  _emitir http resumo='falha com Authorization: Bearer sl.SENTINELA_segredo_123456789 no envio'
  assert_nao_contem 'SENTINELA_segredo_123456789' "$_SAIDA"
}

teste_sem_debug_nada_e_escrito() {
  local saida
  saida=$(DBX_CLI_DEBUG=nao dbx_debug_linha upload bytes=1 2>&1)
  assert_igual '' "$saida"
  saida=$(unset DBX_CLI_DEBUG; dbx_debug_linha upload bytes=1 2>&1)
  assert_igual '' "$saida"
}

teste_nada_vai_ao_stdout() {
  local saida
  saida=$(DBX_CLI_DEBUG=sim dbx_debug_linha upload bytes=1 2>/dev/null)
  assert_igual '' "$saida"
}

teste_falha_de_escrita_em_stderr_nao_muda_o_resultado() {
  DBX_CLI_DEBUG=sim dbx_debug_linha upload bytes=1 2>&-
  assert_igual 0 "$?"
}

harness_executar "$@"
