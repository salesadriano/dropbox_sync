#!/usr/bin/env bash
# fixtures.sh — geradores deterministicos de massa de teste.
#
# Nenhuma massa e versionada no repositorio: tudo e gerado em tempo de execucao
# sob $DBX_TESTES_TMP e removido pelo runner. O conteudo e deterministico
# (sequencias de bytes fixas, nunca /dev/urandom) para que os valores esperados
# fixados nos testes permanecam validos entre execucoes e entre maquinas.

: "${DBX_TESTES_TMP:=${TMPDIR:-/tmp}}"

DBX_FIXT_BLOCO=4194304

# _fixt_repetir <byte_octal> <quantidade>  -> escreve na saida padrao
_fixt_repetir() {
  local octal=$1 quantidade=$2
  if [[ $octal == '000' ]]; then
    head -c "$quantidade" /dev/zero
  else
    tr '\000' "\\$octal" </dev/zero 2>/dev/null | head -c "$quantidade"
  fi
}

# fixture_criar <nome> -> imprime o caminho do arquivo gerado (gera uma unica vez)
fixture_criar() {
  local nome=$1
  local caminho="$DBX_TESTES_TMP/fixture-$nome.bin"
  if [[ -e $caminho ]]; then
    printf '%s\n' "$caminho"
    return 0
  fi
  case $nome in
    vazio)
      : >"$caminho"
      ;;
    um_byte)
      printf 'A' >"$caminho"
      ;;
    quase_bloco) # um byte a menos que um bloco
      _fixt_repetir 101 $((DBX_FIXT_BLOCO - 1)) >"$caminho"
      ;;
    bloco_exato) # exatamente um bloco
      _fixt_repetir 000 "$DBX_FIXT_BLOCO" >"$caminho"
      ;;
    bloco_mais_um) # um bloco cheio mais um byte de resto
      {
        _fixt_repetir 000 "$DBX_FIXT_BLOCO"
        printf 'A'
      } >"$caminho"
      ;;
    dois_blocos_resto) # dois blocos cheios mais resto de 7 bytes
      {
        _fixt_repetir 000 "$DBX_FIXT_BLOCO"
        _fixt_repetir 377 "$DBX_FIXT_BLOCO"
        printf 'AAAAAAA'
      } >"$caminho"
      ;;
    grande) # 16 blocos cheios, sem resto (64 MiB)
      _fixt_repetir 000 $((DBX_FIXT_BLOCO * 16)) >"$caminho"
      ;;
    *)
      printf 'fixture desconhecida: %s\n' "$nome" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$caminho"
}

# fixture_tamanho <caminho>
fixture_tamanho() {
  wc -c <"$1" | tr -d ' '
}
