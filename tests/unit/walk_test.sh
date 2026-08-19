#!/usr/bin/env bash
# Testes de lib/walk.sh — travessia por descida (RNF-28, RF-41a).
#
# shellcheck disable=SC2016
# Justificativa: a auditoria estatica procura a forma `cd -P -- "$raiz"` no
# codigo-fonte, e o padrao precisa chegar ao `grep` sem expansao.
#
# shellcheck disable=SC2034
# Justificativa: `dbx_walk_ler` preenche tres vetores por referencia de nome; os
# casos que so verificam os caminhos ainda precisam declarar os outros dois, e a
# analise estatica nao segue nameref entre arquivos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/walk.sh"

_arvore() { # <nome> — devolve a raiz de uma arvore de ensaio
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/walk.XXXXXX")
  mkdir -p "$base/raiz/sub/fundo"
  printf 'a' >"$base/raiz/um.txt"
  printf 'bb' >"$base/raiz/sub/dois.txt"
  printf 'ccc' >"$base/raiz/sub/fundo/tres.txt"
  printf '%s' "$base"
}

_registros() { # <raiz> <arquivo> — percorre e devolve o vetor por nome
  dbx_walk_local "$1" "$2"
}

teste_percorre_a_arvore_inteira_com_caminhos_relativos() {
  local base
  base=$(_arvore)
  _registros "$base/raiz" "$base/reg"
  assert_igual 0 $? 'a travessia deve concluir'
  assert_igual 3 "$DBX_WALK_TOTAL" 'tres arquivos comuns'
  assert_igual 'nao' "$DBX_WALK_PARCIAL" 'arvore sa nao e travessia parcial'
  local -a caminhos=() tamanhos=() mtimes=()
  dbx_walk_ler "$base/reg" caminhos tamanhos mtimes
  local juntos
  printf -v juntos '%s|' "${caminhos[@]}"
  assert_contem 'um.txt|' "$juntos" 'arquivo na raiz'
  assert_contem 'sub/dois.txt|' "$juntos" 'caminho relativo em profundidade 1'
  assert_contem 'sub/fundo/tres.txt|' "$juntos" 'caminho relativo em profundidade 2'
  assert_nao_contem "$base" "$juntos" 'nenhum caminho pode ser absoluto'
}

teste_arquivo_oculto_e_transferivel_como_qualquer_outro() {
  # Omitir arquivo oculto faria o destino divergir em silencio, e com
  # espelhamento a divergencia vira exclusao.
  local base
  base=$(_arvore)
  printf 'x' >"$base/raiz/.perfil"
  _registros "$base/raiz" "$base/reg"
  assert_igual 4 "$DBX_WALK_TOTAL" 'oculto entra na travessia'
}

teste_nome_com_quebra_de_linha_sobrevive_a_travessia() {
  # O separador de registro e o byte nulo justamente por isto: nome de arquivo
  # aceita quebra de linha, e um formato por linha perderia o nome ou inventaria
  # um segundo arquivo.
  local base nome
  base=$(_arvore)
  nome=$'estranho\ncom quebra.txt'
  printf 'z' >"$base/raiz/$nome"
  _registros "$base/raiz" "$base/reg"
  assert_igual 4 "$DBX_WALK_TOTAL" 'quebra de linha nao pode virar dois registros'
  local -a caminhos=() tamanhos=() mtimes=()
  dbx_walk_ler "$base/reg" caminhos tamanhos mtimes
  local achou='nao' c
  for c in "${caminhos[@]}"; do [[ $c == "$nome" ]] && achou='sim'; done
  assert_igual 'sim' "$achou" 'o nome precisa voltar byte a byte'
}

teste_diretorio_vazio_nao_produz_registro_literal() {
  # Sem `nullglob`, o laco veria a cadeia `*` como se fosse um arquivo chamado
  # asterisco — e o `sync` tentaria transferi-lo.
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/walk.XXXXXX")
  mkdir -p "$base/raiz/vazio"
  _registros "$base/raiz" "$base/reg"
  assert_igual 0 "$DBX_WALK_TOTAL" 'diretorio vazio nao produz arquivo'
  assert_igual 'nao' "$DBX_WALK_PARCIAL" 'diretorio vazio nao e erro'
}

teste_ligacao_simbolica_nao_e_seguida_e_marca_a_travessia() {
  # Segui-la sairia da raiz por construcao. Pula-la em silencio seria pior:
  # o conteudo sumiria da origem sem sumir do destino, e com espelhamento isso
  # vira exclusao.
  local base fora
  base=$(_arvore)
  fora=$(mktemp -d "$DBX_TESTES_TMP/fora.XXXXXX")
  printf 'nao devia ser visto' >"$fora/alvo.txt"
  ln -s "$fora" "$base/raiz/atalho"
  _registros "$base/raiz" "$base/reg"
  assert_igual 3 "$DBX_WALK_TOTAL" 'o alvo do vinculo nao pode entrar na travessia'
  assert_igual 'sim' "$DBX_WALK_PARCIAL" 'vinculo pulado torna a travessia parcial'
  assert_contem 'ligacao simbolica' "$DBX_WALK_MOTIVO" 'o motivo precisa nomear a causa'
  local -a caminhos=() tamanhos=() mtimes=()
  dbx_walk_ler "$base/reg" caminhos tamanhos mtimes
  local juntos
  printf -v juntos '%s|' "${caminhos[@]}"
  assert_nao_contem 'alvo.txt' "$juntos" 'nada de fora da raiz pode ser alcancado'
}

teste_subdiretorio_ilegivel_em_profundidade_um_marca_parcial() {
  local base
  base=$(_arvore)
  chmod 000 "$base/raiz/sub"
  _registros "$base/raiz" "$base/reg"
  local parcial=$DBX_WALK_PARCIAL motivo=$DBX_WALK_MOTIVO
  chmod 755 "$base/raiz/sub"
  assert_igual 'sim' "$parcial" 'RF-41a: qualquer erro torna a travessia parcial'
  assert_contem 'sub' "$motivo" 'o caminho que falhou consta do motivo'
}

teste_subdiretorio_ilegivel_em_profundidade_n_marca_parcial() {
  # RF-41(a) fala em QUALQUER profundidade, e nao so na raiz. Este caso e o par
  # do anterior: sem ele, uma implementacao que so olhasse o primeiro nivel
  # passaria.
  local base
  base=$(_arvore)
  chmod 000 "$base/raiz/sub/fundo"
  _registros "$base/raiz" "$base/reg"
  local parcial=$DBX_WALK_PARCIAL motivo=$DBX_WALK_MOTIVO
  chmod 755 "$base/raiz/sub/fundo"
  assert_igual 'sim' "$parcial" 'erro em profundidade N tambem torna parcial'
  assert_contem 'sub/fundo' "$motivo" 'o motivo nomeia o ramo em profundidade'
}

teste_raiz_inexistente_ou_ilegivel_e_recusada() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/walk.XXXXXX")
  assert_status "$DBX_WALK_ERRO_NAO_ENCONTRADO" dbx_walk_local "$base/nao-existe" "$base/reg"
  mkdir -p "$base/fechada"
  chmod 000 "$base/fechada"
  dbx_walk_local "$base/fechada" "$base/reg"
  local estado=$?
  chmod 755 "$base/fechada"
  assert_igual "$DBX_WALK_ERRO_NAO_ENCONTRADO" "$estado" 'raiz ilegivel e recusa, e nao arvore vazia'
}

teste_entrada_que_nao_e_arquivo_comum_marca_parcial() {
  # Fila nomeada nao tem conteudo transferivel. Omiti-la em silencio faria o
  # destino perder o par sem que ninguem soubesse.
  local base
  base=$(_arvore)
  mkfifo "$base/raiz/cano" 2>/dev/null || return 0
  _registros "$base/raiz" "$base/reg"
  assert_igual 3 "$DBX_WALK_TOTAL" 'fila nomeada nao e arquivo transferivel'
  assert_igual 'sim' "$DBX_WALK_PARCIAL" 'entrada nao transferivel torna a travessia parcial'
}

teste_travessia_nao_altera_o_diretorio_corrente_do_chamador() {
  # A descida muda o diretorio do processo. Se vazasse, todo caminho relativo
  # posterior — inclusive o de outros comandos — passaria a significar outra
  # coisa.
  local base antes depois
  base=$(_arvore)
  antes=$(pwd -P)
  _registros "$base/raiz" "$base/reg"
  depois=$(pwd -P)
  assert_igual "$antes" "$depois" 'a travessia roda em subshell e nao vaza o cd'
}

teste_nenhum_ponto_da_travessia_reconstroi_caminho_absoluto() {
  # RNF-28 exige auditoria estatica: a garantia e que nenhum componente ja
  # percorrido seja reaberto por texto montado.
  local achados
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/lib/walk.sh" 'sem o arquivo a auditoria seria vacua'
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/walk.sh" |
    grep -nE 'cd[[:space:]]+(-[A-Za-z]+[[:space:]]+)*"?\$\{?(raiz|prefixo|relativo)' || true)
  # A unica descida por caminho montado permitida e a entrada na raiz, feita uma
  # vez dentro do subshell, ANTES de a travessia comecar. A contagem passa pelo
  # auxiliar do arcabouco: `grep -c` imprime a contagem E sai com 1 sem
  # correspondencia, e a forma `$(grep -c ... || printf 0)` produz "0\n0".
  local permitidas
  permitidas=$(_harness_contar 'cd -P -- "\$raiz"' "$DBX_HARNESS_RAIZ/lib/walk.sh")
  assert_igual 1 "$permitidas" 'a entrada na raiz e unica e explicita'
  # A massa nao passa por substituicao de comando (RSK-28): a cadeia ja existe e
  # chega por aqui-string.
  achados=$(grep -v 'cd -P -- "\$raiz"' <<<"$achados" || true)
  achados=${achados//[$'\n']/}
  assert_igual '' "$achados" "descida por caminho montado alem da raiz: $achados"
}

harness_executar "$@"
