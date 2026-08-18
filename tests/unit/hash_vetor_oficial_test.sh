#!/usr/bin/env bash
# Vetor de teste oficial da Dropbox para o content_hash (criterio de aceite de RF-34).
#
# O criterio de aceite exige o arquivo de exemplo publicado pela Dropbox, que
# nao pode ser versionado neste repositorio (9,3 MiB, licenca de terceiro). Este
# arquivo de teste, portanto:
#
#   1. usa uma copia local se DBX_TESTE_ARQUIVO_OFICIAL apontar para ela;
#   2. baixa o arquivo do proprio host de documentacao da Dropbox se
#      DBX_TESTES_REDE=1 estiver definido;
#   3. e marcado como PULADO em qualquer outro caso.
#
# Antes de comparar o content_hash, o SHA-256 do proprio arquivo e conferido
# contra um valor fixado. Sem isso, um arquivo trocado no servidor produziria
# uma reprovacao enganosa em vez de um aviso de insumo invalido.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

readonly URL_OFICIAL='https://www.dropbox.com/static/images/developers/milky-way-nasa.jpg'
readonly SHA256_DO_ARQUIVO=83e1d9c98ee2dd2d50bc6c66450ee80cbecbcff0732e00b4feca4660647dbd82
readonly TAMANHO_DO_ARQUIVO=9711423
readonly CONTENT_HASH_OFICIAL=485291fa0ee50c016982abbfa943957bcd231aae0492ccbaa22c58e3997b35e0

_obter_arquivo_oficial() {
  local destino="$DBX_TESTES_TMP/milky-way-nasa.jpg"
  if [[ -n ${DBX_TESTE_ARQUIVO_OFICIAL:-} ]]; then
    printf '%s\n' "$DBX_TESTE_ARQUIVO_OFICIAL"
    return 0
  fi
  if [[ ${DBX_TESTES_REDE:-0} != 1 ]]; then
    return 1
  fi
  [[ -s $destino ]] && { printf '%s\n' "$destino"; return 0; }
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS -m 120 -o "$destino" "$URL_OFICIAL" >/dev/null 2>&1 || return 1
  printf '%s\n' "$destino"
}

teste_vetor_oficial_de_content_hash() {
  local arquivo sha tamanho
  if ! arquivo=$(_obter_arquivo_oficial); then
    pular 'arquivo oficial indisponivel — defina DBX_TESTES_REDE=1 ou DBX_TESTE_ARQUIVO_OFICIAL'
  fi
  if [[ ! -s $arquivo ]]; then
    pular "arquivo oficial vazio ou ausente em $arquivo"
  fi

  tamanho=$(wc -c <"$arquivo" | tr -d ' ')
  sha=$(sha256sum <"$arquivo" | cut -d' ' -f1)
  if [[ $sha != "$SHA256_DO_ARQUIVO" || $tamanho != "$TAMANHO_DO_ARQUIVO" ]]; then
    pular "insumo divergente do vetor oficial (sha=$sha tamanho=$tamanho); nao ha o que comparar"
  fi

  assert_igual "$CONTENT_HASH_OFICIAL" "$(dbx_hash_conteudo_arquivo "$arquivo")" \
    'content_hash do arquivo de exemplo oficial da Dropbox (RF-34)'
}

teste_vetor_oficial_por_fluxo() {
  local arquivo sha
  if ! arquivo=$(_obter_arquivo_oficial) || [[ ! -s $arquivo ]]; then
    pular 'arquivo oficial indisponivel — defina DBX_TESTES_REDE=1 ou DBX_TESTE_ARQUIVO_OFICIAL'
  fi
  sha=$(sha256sum <"$arquivo" | cut -d' ' -f1)
  [[ $sha == "$SHA256_DO_ARQUIVO" ]] || pular "insumo divergente do vetor oficial (sha=$sha)"

  assert_igual "$CONTENT_HASH_OFICIAL" "$(dbx_hash_conteudo_fluxo <"$arquivo")" \
    'mesmo vetor oficial calculado a partir de fluxo'
}

harness_executar "$@"
