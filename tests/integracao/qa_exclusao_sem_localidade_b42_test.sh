#!/usr/bin/env bash
# Testes ponta a ponta dos filtros (RF-79, RF-80, RF-81; TC-FLT, TC-FES, TC-FDT).
#
# A semantica do padrao e provada por unidade em `tests/unit/filtro_test.sh`.
# Aqui se prova a LIGACAO: opcoes de `sync`, `verificar` e `download` de pasta,
# a ordem das recusas (antes da trava, da memoria, da rede e da escrita), o
# plano e, acima de tudo, RF-80(d): com `--espelhar`, item filtrado NUNCA e
# apagado, nem no remoto nem no local. Essa garantia e provada pelo REGISTRO DE
# CHAMADAS do duplo de rede e de `rm`, e nao pelo relatorio do proprio `sync`.
#
# RF-12 (emendado pela DIV-90): a exclusao do envio recursivo e entregue por
# `sync --enviar --excluir`, verificada por TC-FES-07 e TC-FLT-01.
#
# shellcheck disable=SC2016,SC1003
# Justificativa: o duplo e os padroes precisam chegar sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly USO=2
readonly CONFLITO=7
readonly NAO_CONCLUIDA=14
DORMIR=$(command -v sleep)
readonly DORMIR
RM_REAL=$(command -v rm)
readonly RM_REAL
readonly H0=0000000000000000000000000000000000000000000000000000000000000000

# _cenario — credencial, duplo de rede, duplos de `rm` e `date` e arvore local.
#
# Cada chamada de rede vira uma linha `url<TAB>argumento` em `$base/chamadas`,
# onde argumento e o `Dropbox-API-Arg` (modo de conteudo) ou o corpo JSON: e por
# ela que se afirma "nenhum delete_v2 sobre item filtrado".
_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/filtros.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' '{".tag":"folder","name":"r","path_display":"/r"}' >"$base/metadado"
  {
    printf '#!%s\nbase=%q\ndormir=%q\nDBX_HARNESS_RAIZ=%q\n' "$BASH" "$base" "$DORMIR" "$DBX_HARNESS_RAIZ"
    cat <<'FIM'
conf=$(cat 2>/dev/null)
saida='' escrever='' anterior='' url='' corpo_req=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; --data-binary) corpo_req=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
argumento=''
if [[ $conf =~ Dropbox-API-Arg:\ ([^$'\n']*) ]]; then
  argumento=${BASH_REMATCH[1]}
elif [[ $corpo_req == @* && -r ${corpo_req#@} ]]; then
  argumento=$(<"${corpo_req#@}")
fi
printf '%s\t%s\n' "$url" "$argumento" >>"$base/chamadas"
if [[ -f $base/bloquear && $url == *"$(<"$base/bloquear")"* ]] && mkdir "$base/bloqueado" 2>/dev/null; then
  while [[ ! -e $base/soltar ]]; do "$dormir" 0.05; done
fi
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *get_current_account*) corpo='{"account_id":"dbid:CONTA"}' ;;
  *list_folder*) corpo=$(<"$base/listagem") ;;
  *get_metadata*) corpo=$(<"$base/metadado") ;;
  *files/download*) corpo='conteudo remoto' ;;
  *get_space_usage*) corpo='{"used":0,"allocation":{".tag":"individual","allocated":1000000000}}' ;;
  *) corpo='{"name":"x","rev":"1"}' ;;
esac
LOTE_ECOA_V2=sim
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "${corpo_req#@}" || :
if [[ $url == *files/download* && -f $base/pasta ]]; then
  codigo=409
  corpo='{"error_summary":"path/not_file/.."}'
fi
if [[ -n $saida ]]; then printf '%s' "$corpo" >"$saida" 2>/dev/null || exit 23; fi
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$base/bin/curl"
  # `rm` que registra cada chamada e delega ao real: prova "nenhum rm local".
  printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexec %q "$@"\n' "$BASH" "$base/rm.log" "$RM_REAL" \
    >"$base/bin/rm"
  # `date` proibido (RF-81(e)): a conversao do `mtime` e do proprio shell.
  printf '#!%s\nprintf "date %%s\\n" "$*" >>%q\nexit 1\n' "$BASH" "$base/proibido" >"$base/bin/date"
  chmod +x "$base/bin/curl" "$base/bin/rm" "$base/bin/date"
  printf '%s' "$base"
}

# _rodar <base> <argumentos...> — com TZ e LC_ALL opcionais por DBX_T_TZ e DBX_T_LC.
# A ausencia da localidade e SIMULADA (DBX_SYNC_LOCALIDADE inexistente, lida
# pelo produto para a suite) para a suite valer tambem em host com C.UTF-8.
_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_TZ:+TZ="$DBX_T_TZ"} \
    ${DBX_T_LC:+LC_ALL="$DBX_T_LC"} DBX_SYNC_LOCALIDADE=xx_XX.UTF-8 \
    setsid -w bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_segundo_plano() { # <base> <rotulo> <argumentos...>
  local base=$1 rotulo=$2
  shift 2
  ( env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
      XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
      setsid -w bash "$DBX_EXEC" "$@" </dev/null >"$base/out.$rotulo" 2>"$base/err.$rotulo"
    printf '%s' "$?" >"$base/estado.$rotulo" ) &
}

_esperar_arquivo() {
  local espera=0
  while [[ ! -e $1 && $espera -lt 400 ]]; do "$DORMIR" 0.05; espera=$((espera + 1)); done
  [[ -e $1 ]] || _harness_falhar "nao apareceu: $1"
}

_resumo() { # <conteudo> — content_hash do conteudo
  local arquivo="$DBX_TESTES_TMP/resumo.$$"
  printf '%s' "$1" >"$arquivo"
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; dbx_hash_conteudo_arquivo "$2"' _ \
    "$DBX_HARNESS_RAIZ" "$arquivo"
}

# _arq <relativo> [server_modified] [size] [client_modified] [hash] — entrada sob /r
_arq() {
  printf '{".tag":"file","name":"%s","path_display":"/r/%s","content_hash":"%s","size":%s,"rev":"1","server_modified":"%s","client_modified":"%s"}' \
    "${1##*/}" "$1" "${5:-$H0}" "${3:-1}" "${2:-2026-10-05T00:00:00Z}" "${4:-${2:-2026-10-05T00:00:00Z}}"
}

_pasta() { printf '{".tag":"folder","name":"%s","path_display":"/r/%s"}' "${1##*/}" "$1"; }

_listar() { # <base> <entradas...>
  local base=$1 juntas
  shift
  juntas=$(IFS=,; printf '%s' "$*")
  printf '{"entries":[%s],"has_more":false}' "$juntas" >"$base/listagem"
}

_local() { # <base> <relativo> [conteudo] — arquivo local antigo (fora da janela da memoria)
  mkdir -p "$(dirname -- "$1/local/$2")"
  printf '%s' "${3:-x}" >"$1/local/$2"
  touch -d '@1700000000' "$1/local/$2"
}

_chamadas() { [[ -r $1/chamadas ]] && cat "$1/chamadas"; return 0; }

_contar() { # <base> <trecho> — chamadas que contem o trecho
  local n=0 linha
  while IFS= read -r linha; do [[ $linha == *"$2"* ]] && n=$((n + 1)); done < <(_chamadas "$1")
  printf '%s' "$n"
}

_deletes() { # <base> — argumentos dos delete_v2, um por linha
  local linha
  while IFS= read -r linha; do
    [[ $linha == *files/delete_v2* ]] && printf '%s\n' "${linha#*$'\t'}"
  done < <(_chamadas "$1")
  return 0
}

_uploads() { # <base> — argumentos dos files/upload, um por linha
  local linha
  while IFS= read -r linha; do
    [[ $linha == *content.dropboxapi.com/2/files/upload$'\t'* ]] && printf '%s\n' "${linha#*$'\t'}"
  done < <(_chamadas "$1")
  return 0
}

_sem_efeito() { # <base> <rotulo> — nenhuma chamada, nenhum estado, nenhuma escrita
  assert_igual '' "$(_chamadas "$1")" "$2: nenhuma chamada de rede"
  assert_arquivo_ausente "$1/estado" "$2: nem trava nem memoria"
}

# ---------------------------------------------------------------------------
# TC-FLT-13, 14, 16, 18..21 — opcoes
# ---------------------------------------------------------------------------

# QA-B42-01 (ciclo 2): sem C.UTF-8 nada com byte nao ASCII pode ser apagado.
# Dados: tudo criado pelo proprio caso (arvore local, listagem remota falsa).
_qa_receber() { # <base> <opcoes...> — receber espelhando; remoto so tem k.txt
  local base=$1
  shift
  _listar "$base" "$(_arq k.txt)"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local" "$@"
}
_qa_intactos() { # <base> <relativos...>
  local base=$1 r
  shift
  local _q
  for r in "$@"; do printf -v _q '%q' "$r"; assert_arquivo_existe "$base/local/$r" "preservado: $_q"; done
}
_qa_nomes() { printf '%s\n' $'lixo\xff.bin' $'caf\xc3\xa9.txt' $'\xc3\xa9a.txt' $'\xc3\x89a.txt' $'a\xe2\x82\xac.txt' $'\xf0\x9f\x98\x80.txt'; }

teste_qa_b42_receber_incluir_impreciso_preserva_todo_nome_nao_ascii() {
  local base n
  base=$(_cenario)
  while IFS= read -r n; do _local "$base" "$n"; done < <(_qa_nomes)
  _local "$base" z.txt
  _qa_receber "$base" --incluir '[!a]*'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  while IFS= read -r n; do _qa_intactos "$base" "$n"; done < <(_qa_nomes)
}
teste_qa_b42_receber_incluir_preciso_nao_ascii_preserva() {
  local base n
  base=$(_cenario)
  while IFS= read -r n; do _local "$base" "$n"; done < <(_qa_nomes)
  _qa_receber "$base" --incluir $'\xc3\xa9*' --incluir $'caf\xc3\xa9.txt' --incluir '?a.txt'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  while IFS= read -r n; do _qa_intactos "$base" "$n"; done < <(_qa_nomes)
}
teste_qa_b42_receber_excluir_com_acento_preserva() {
  local base n
  base=$(_cenario)
  while IFS= read -r n; do _local "$base" "$n"; done < <(_qa_nomes)
  _local "$base" x.txt
  _qa_receber "$base" --excluir $'\xc3\xa9*' --excluir $'[\xc3\xa9]a.txt' --excluir '?a.txt'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  while IFS= read -r n; do _qa_intactos "$base" "$n"; done < <(_qa_nomes)
}
teste_qa_b42_receber_ramo_de_pasta_nao_ascii_preserva() {
  local base
  base=$(_cenario)
  _local "$base" $'pasta\xff/x.txt'
  _local "$base" $'pasta\xc3\xa9/sub/y.txt'
  _local "$base" $'ascii/\xc3\xa9.txt'
  _qa_receber "$base" --incluir '*'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  _qa_intactos "$base" $'pasta\xff/x.txt' $'pasta\xc3\xa9/sub/y.txt' $'ascii/\xc3\xa9.txt'
  _qa_receber "$base" --incluir '[!a]*/'
  _qa_intactos "$base" $'pasta\xff/x.txt' $'pasta\xc3\xa9/sub/y.txt' $'ascii/\xc3\xa9.txt'
}
teste_qa_b42_receber_sem_filtro_preserva() {
  local base n
  base=$(_cenario)
  while IFS= read -r n; do _local "$base" "$n"; done < <(_qa_nomes)
  _qa_receber "$base"
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  while IFS= read -r n; do _qa_intactos "$base" "$n"; done < <(_qa_nomes)
}
teste_qa_b42_enviar_espelhar_remoto_nao_ascii_nao_e_apagado() {
  local base
  base=$(_cenario)
  _local "$base" novo.txt
  _listar "$base" "$(_arq $'\xc3\xa9.txt')" "$(_arq $'d\xc3\xa9/x.txt')" "$(_arq orfao.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r \
    --incluir '[!a]*' --incluir $'\xc3\xa9*'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_nao_contem $'\xc3\xa9' "$(_deletes "$base")" 'nenhum delete de caminho nao ASCII'
}

harness_executar "$@"
