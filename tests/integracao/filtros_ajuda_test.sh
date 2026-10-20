#!/usr/bin/env bash
# Ajuda, autocompletar, README e mapa de modulos dos filtros e do limite de
# banda (RF-83; TC-CPL-09, TC-DOC-03, TC-TST-07).
#
# A conferencia geral "ajuda = autocompletar" por comando e de `completar_test`
# (TC-CPL-02); aqui se prova que as opcoes NOVAS estao nos comandos certos, e so
# neles, e que o texto entrega o que o operador precisa para nao se ferir.
#
# shellcheck disable=SC2016
# Justificativa: crases e `$` de Markdown e do script entregue a `bash -c` chegam literais.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly SCRIPT="$DBX_HARNESS_RAIZ/completions/dbx.bash"
readonly README="$DBX_HARNESS_RAIZ/README.md"
readonly MAPA="$DBX_HARNESS_RAIZ/docs/testes/mapa-modulos.md"

_ajuda() { env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help "$@" 2>&1; }

_completar() { # <comando> — opcoes oferecidas para `dbx <comando> -`
  env -i PATH="$PATH" bash -c '
    . "$1"; shift
    COMP_WORDS=(dbx "$@"); COMP_CWORD=$#; COMPREPLY=()
    _dbx_completar dbx "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    for item in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do printf "%s\n" "$item"; done
  ' _ "$SCRIPT" "$1" - 2>&1
}

_tem() { # <lista> <opcao> — `sim` se a opcao esta na lista, linha a linha
  local linha
  while IFS= read -r linha; do [[ $linha == "$2" ]] && { printf sim; return 0; }; done <<<"$1"
  printf nao
}

teste_cpl09_opcoes_novas_por_comando_na_ajuda_e_no_autocompletar() {
  local comando opcao ajuda lista
  for comando in sync verificar download; do
    ajuda=$(_ajuda "$comando")
    lista=$(_completar "$comando")
    for opcao in --excluir --exclude --incluir --include; do
      assert_contem "$opcao" "$ajuda" "help $comando: $opcao"
      assert_igual sim "$(_tem "$lista" "$opcao")" "completar $comando: $opcao"
    done
  done
  for comando in sync download; do
    ajuda=$(_ajuda "$comando")
    lista=$(_completar "$comando")
    for opcao in --modificado-desde --modified-since --modificado-ate --modified-until \
      --tamanho-min --min-size --tamanho-max --max-size; do
      assert_contem "$opcao" "$ajuda" "help $comando: $opcao"
      assert_igual sim "$(_tem "$lista" "$opcao")" "completar $comando: $opcao"
    done
  done
  for comando in upload download sync; do
    lista=$(_completar "$comando")
    for opcao in --limite-banda --bwlimit; do
      assert_contem "$opcao" "$(_ajuda "$comando")" "help $comando: $opcao"
      assert_igual sim "$(_tem "$lista" "$opcao")" "completar $comando: $opcao"
    done
  done
  lista=$(_completar verificar)
  assert_igual nao "$(_tem "$lista" --limite-banda)" 'verificar nao transfere'
  assert_igual nao "$(_tem "$lista" --tamanho-min)" 'verificar recusa tamanho (DIV-83)'
  lista=$(_completar upload)
  assert_igual nao "$(_tem "$lista" --excluir)" 'upload nao filtra'
}

teste_doc03_ajuda_traz_sintaxe_desvios_seguranca_unidade_piso_e_variavel() {
  local sync verificar download upload lixeira
  sync=$(_ajuda sync)
  verificar=$(_ajuda verificar)
  download=$(_ajuda download)
  upload=$(_ajuda upload)
  lixeira=$(_ajuda lixeira)
  local texto
  for texto in "$sync" "$verificar" "$download"; do
    assert_contem 'item filtrado nunca e apagado no espelhamento; remover um filtro devolve os itens ao escopo' \
      "$texto" 'a frase de seguranca'
    assert_contem '**' "$texto" 'sintaxe resumida'
    assert_contem 'sem caixa' "$texto" 'sem caixa'
    assert_contem 'exclusao vence' "$texto" 'precedencia'
    assert_contem 'sem !' "$texto" 'desvio do gitignore'
    assert_contem 'NAO normaliza Unicode: NFC e NFD' "$texto" 'sem normalizacao Unicode (QA-B4-03, RF-79(h))'
  done
  for texto in "$sync" "$download"; do
    assert_contem 'AAAA-MM-DD' "$texto" 'formato da data'
    assert_contem 'server_modified' "$texto" 'fonte remota da data (DIV-84)'
    assert_contem 'base 1024' "$texto" 'tamanho'
    assert_contem 'recusad' "$texto" 'recusa junto de --espelhar'
  done
  for texto in "$sync" "$download" "$upload"; do
    assert_contem 'bytes/s' "$texto" 'unidade'
    assert_contem 'DBX_LIMITE_BANDA' "$texto" 'variavel'
    assert_contem 'por transferencia' "$texto" 'por transferencia'
    assert_contem 'DBX_HTTP_VELOCIDADE_MINIMA_BPS' "$texto" 'piso'
  done
  assert_contem 'PERMANENTE' "$lixeira" 'o --excluir da lixeira e o expurgo (DIV-86)'
  assert_contem 'nao e o filtro' "$lixeira" 'e a ajuda diz que nao e o filtro'
}

teste_doc03_readme_traz_filtros_e_limite_de_banda() {
  local readme
  readme=$(<"$README")
  assert_contem '## Filtros' "$readme" 'secao Filtros'
  assert_contem '## Limite de banda' "$readme" 'secao Limite de banda'
  assert_contem 'nunca é apagado' "$readme" 'interacao com --espelhar'
  assert_contem 'backup com filtro é parcial' "$readme" 'aviso de backup parcial'
  assert_contem 'DBX_LIMITE_BANDA' "$readme" 'variavel'
  assert_contem 'DBX_HTTP_VELOCIDADE_MINIMA_BPS' "$readme" 'piso'
  assert_contem 'bytes/s' "$readme" 'unidade'
  assert_contem '`!`' "$readme" 'desvio: sem negacao'
  assert_contem 'não normaliza NFC e NFD' "$readme" 'sem normalizacao Unicode (QA-B4-03)'
}

teste_tst07_mapa_de_modulos_tem_lib_filtro_com_seus_testes() {
  local linha achou=nao
  while IFS= read -r linha; do
    if [[ $linha == '| `lib/filtro.sh`'* ]]; then
      achou=sim
      assert_contem '`filtro`' "$linha" 'teste direto'
      assert_contem 'filtros' "$linha" 'teste ponta a ponta'
    fi
  done <"$MAPA"
  assert_igual sim "$achou" 'entrada de lib/filtro.sh'
  assert_contem 'banda' "$(<"$MAPA")" 'o teste do limite de banda entra no mapa'
}

harness_executar "$@"
