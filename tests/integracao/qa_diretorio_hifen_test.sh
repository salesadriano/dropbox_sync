#!/usr/bin/env bash
# Validacao independente do QA da demanda `diretorio-chamado-hifen` (defeito em
# producao na 2.3.1): `cd -- -` vai ao OLDPWD e imprime o destino no stdout, o que
# corrompia a lista `n<TAB>caminho\0` do `sync` e desviava a travessia.
#
# Estrategia: arvores locais com pasta ou arquivo de nome especial (`-`, `--`,
# `-x`) sob `sync --dry-run` (plano sem escrita), contra duplo de rede. O plano tem
# de ler cada pasta pelo nome, listar cada arquivo EXATAMENTE uma vez e nunca
# repetir o irmao. A conferencia e por contagem exata de linhas do plano.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` precisa chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="${DBX_QA_EXEC:-$DBX_HARNESS_RAIZ/bin/dbx}"

# _cenario [listagem] — credencial, duplo de rede e pasta local vazia.
_cenario() {
  local listagem=${1:-'{"entries":[],"has_more":false}'} base
  base=$(mktemp -d "$DBX_TESTES_TMP/qahifen.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' "$listagem" >"$base/listagem"
  {
    printf '#!%s\nbase=%q\n' "$BASH" "$base"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '200'
exit 0
FIM
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

# _plano <base> [--espelhar] — roda o plano e deixa saida, erro e estado em DBX_*.
_plano() {
  local base=$1
  shift
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" --json --dry-run sync --enviar --origem "$base/local" --destino /r "$@" \
    </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  DBX_SAIDA=$(<"$base/out")
  DBX_ERRO=$(<"$base/err")
}

# _lista <base> <campo> — itens do plano (transferir=/apagar=) um por linha, ordenados.
_lista() {
  grep -oE "$2=[^\",}]+" "$1/out" | grep -vxE "$2=[0-9]+" | LC_ALL=C sort
}

# _conferir <rotulo> <esperado: itens ordenados> — exige conclusao limpa e o plano exato.
_conferir() {
  local rotulo=$1 esperado=$2 base=$3
  assert_igual 0 "$DBX_ESTADO" "$rotulo: conclui; diagnostico: $DBX_ERRO"
  assert_nao_contem 'syntax' "$DBX_ERRO" "$rotulo: sem erro aritmetico/de sintaxe"
  assert_nao_contem 'arithmetic' "$DBX_ERRO" "$rotulo: lista de diretorios intacta"
  assert_nao_contem "$base" "$(_lista "$base" 'transferir')" "$rotulo: o destino do cd nao vira item do plano"
  assert_igual "$esperado" "$(_lista "$base" 'transferir')" "$rotulo: cada arquivo exatamente uma vez, nenhum irmao repetido"
}

teste_pasta_hifen_na_raiz_da_origem() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/-" "$base/local/ant"
  printf 'h' >"$base/local/-/h.txt"
  printf 'a' >"$base/local/ant/a.txt"
  printf 'r' >"$base/local/raiz.txt"
  _plano "$base"
  _conferir 'raiz' $'transferir=-/h.txt\ntransferir=ant/a.txt\ntransferir=raiz.txt' "$base"
}

teste_pasta_hifen_como_primeiro_irmao() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/-" "$base/local/b" "$base/local/c"
  printf 'h' >"$base/local/-/h.txt"
  printf 'b' >"$base/local/b/b.txt"
  printf 'c' >"$base/local/c/c.txt"
  _plano "$base"
  _conferir 'primeiro' $'transferir=-/h.txt\ntransferir=b/b.txt\ntransferir=c/c.txt' "$base"
}

teste_pasta_hifen_como_ultimo_irmao() {
  local base
  base=$(_cenario)
  # '!' e '+' precedem '-' na ordem ASCII; em outros locales a ordem muda, e o
  # plano exato continua sendo o mesmo.
  mkdir -p "$base/local/+" "$base/local/!" "$base/local/-"
  printf 'm' >"$base/local/+/m.txt"
  printf 'v' >"$base/local/!/v.txt"
  printf 'h' >"$base/local/-/h.txt"
  _plano "$base"
  _conferir 'ultimo' $'transferir=!/v.txt\ntransferir=+/m.txt\ntransferir=-/h.txt' "$base"
}

teste_pasta_hifen_aninhada() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/a/-/b" "$base/local/a/irmao" "$base/local/a/-/-"
  printf 'b' >"$base/local/a/-/b/b.txt"
  printf 'i' >"$base/local/a/irmao/i.txt"
  printf 'd' >"$base/local/a/-/-/d.txt"
  printf 'f' >"$base/local/a/-/f.txt"
  _plano "$base"
  _conferir 'aninhada' $'transferir=a/-/-/d.txt\ntransferir=a/-/b/b.txt\ntransferir=a/-/f.txt\ntransferir=a/irmao/i.txt' "$base"
}

teste_pasta_hifen_so_do_destino_sob_espelhar() {
  local base entrada
  entrada='{".tag":"file","path_display":"/r/-/x.txt","content_hash":"ff","size":1}'
  base=$(_cenario "{\"entries\":[$entrada],\"has_more\":false}")
  mkdir -p "$base/local/ant" "$base/local/zul"
  printf 'a' >"$base/local/ant/a.txt"
  printf 'z' >"$base/local/zul/z.txt"
  _plano "$base" --espelhar
  _conferir 'so do destino' $'transferir=ant/a.txt\ntransferir=zul/z.txt' "$base"
  assert_igual 'apagar=-/x.txt' "$(_lista "$base" 'apagar')" 'so do destino: o excedente remoto sob `-` entra no plano de exclusao, uma vez'
}

teste_arquivo_chamado_hifen_nao_e_pasta() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/sub" "$base/local/ant"
  printf 'f' >"$base/local/-"
  printf 's' >"$base/local/sub/s.txt"
  printf 'a' >"$base/local/ant/a.txt"
  _plano "$base"
  _conferir 'arquivo hifen' $'transferir=-\ntransferir=ant/a.txt\ntransferir=sub/s.txt' "$base"
}

teste_pastas_chamadas_hifen_hifen_e_hifen_x() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/--" "$base/local/-x" "$base/local/-" "$base/local/y"
  printf 'dd' >"$base/local/--/dd.txt"
  printf 'x' >"$base/local/-x/x.txt"
  printf 'h' >"$base/local/-/h.txt"
  printf 'y' >"$base/local/y/y.txt"
  _plano "$base"
  _conferir 'hifens' $'transferir=--/dd.txt\ntransferir=-/h.txt\ntransferir=-x/x.txt\ntransferir=y/y.txt' "$base"
}

teste_pasta_hifen_nao_desvia_a_enumeracao_de_diretorios() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/sl/SL" "$base/local/sl/-" "$base/local/z"
  printf 'a' >"$base/local/sl/SL/a.txt"
  printf 'h' >"$base/local/sl/-/h.txt"
  printf 'z' >"$base/local/z/z.txt"
  _plano "$base" --espelhar
  _conferir 'enumeracao' $'transferir=sl/-/h.txt\ntransferir=sl/SL/a.txt\ntransferir=z/z.txt' "$base"
  assert_nao_contem 'sl/SL/SL' "$DBX_SAIDA" 'o irmao SL nao e lido como se fosse a pasta `-`'
}

harness_executar "$@"
