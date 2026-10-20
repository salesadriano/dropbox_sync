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
    printf '#!%s\nbase=%q\ndormir=%q\n' "$BASH" "$base" "$DORMIR"
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
_rodar() {
  local base=$1
  shift
  DBX_SAIDA='' DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" ${DBX_T_TZ:+TZ="$DBX_T_TZ"} \
    ${DBX_T_LC:+LC_ALL="$DBX_T_LC"} \
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

teste_flt13_flt14_malformado_sai_2_antes_de_trava_memoria_rede_e_escrita() {
  local base padrao
  base=$(_cenario)
  for padrao in '' '/' 'a//b' './a' 'a/../b' 'x\' '[abc' '[]' '[z-a]' '[[:alpha:]]' '!x' \
    $'a\tb' $'a\nb' $'a\x7fb'; do
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir "$padrao"
    assert_igual "$USO" "$DBX_ESTADO" "sync: [$padrao]"
    _sem_efeito "$base" "sync [$padrao]"
    _rodar "$base" sync --receber --origem /r --destino "$base/destino" --incluir "$padrao"
    assert_igual "$USO" "$DBX_ESTADO" "sync --receber: [$padrao]"
    assert_arquivo_ausente "$base/destino" 'o destino local nao e criado'
  done
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r --exclude '[z-a]'
  assert_igual "$USO" "$DBX_ESTADO" 'verificar'
  assert_contem '--exclude' "$DBX_ERRO" 'nomeia a opcao'
  assert_contem "'[z-a]'" "$DBX_ERRO" 'cita o padrao'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir $'a\x1b]0;X\x07'
  assert_nao_contem $'\x1b' "$DBX_ERRO" 'sem byte de controle cru na mensagem'
  _sem_efeito "$base" 'verificar e controle'
}

teste_flt16_padrao_e_dado_na_linha_de_comando() {
  local base sentinela
  base=$(_cenario)
  sentinela="$base/SENTINELA"
  _local "$base" 'a.txt'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r \
    --excluir "\$(touch $sentinela)" --excluir "\`touch $sentinela\`" --excluir '$HOME' \
    --excluir '~' --excluir "a;touch $sentinela"
  assert_igual 0 "$DBX_ESTADO" "conclui; diagnostico: $DBX_ERRO"
  assert_arquivo_ausente "$sentinela" 'nada executado'
  assert_contem 'transferir=a.txt' "$DBX_SAIDA" 'e nada casou por expansao'
}

teste_flt18_repetivel_acumula_e_a_ordem_nao_importa() {
  local base primeira
  base=$(_cenario)
  _local "$base" a.log
  _local "$base" b.tmp
  _local "$base" c.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r \
    --excluir '*.log' --excluir '*.tmp'
  assert_igual 0 "$DBX_ESTADO" "conclui; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=c.txt' "$DBX_SAIDA" 'o que fica'
  assert_nao_contem 'transferir=a.log' "$DBX_SAIDA" 'primeiro padrao'
  assert_nao_contem 'transferir=b.tmp' "$DBX_SAIDA" 'segundo padrao acumula'
  primeira=$DBX_SAIDA
  _rodar "$base" --dry-run sync --excluir '*.tmp' --destino /r --excluir '*.log' --enviar \
    --origem "$base/local"
  # So a ordem em que os padroes sao citados no cabecalho acompanha a linha.
  assert_igual "$(sed '/^excluir=/d' <<<"$primeira")" "$(sed '/^excluir=/d' <<<"$DBX_SAIDA")" \
    'ordem indiferente ao resultado'
  assert_contem 'filtrados_origem=2' "$DBX_SAIDA" 'dois filtrados'
}

teste_flt19_sem_valor_vazio_e_comandos_que_nao_aceitam() {
  local base
  base=$(_cenario)
  _local "$base" a.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir
  assert_igual "$USO" "$DBX_ESTADO" 'sem valor'
  assert_contem '--excluir' "$DBX_ERRO" 'nomeia a opcao'
  assert_nao_contem 'nao reconhecida' "$DBX_ERRO" 'a opcao existe no sync'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --incluir ''
  assert_igual "$USO" "$DBX_ESTADO" 'valor vazio'
  assert_contem 'padrao vazio' "$DBX_ERRO" 'diz por que'
  _rodar "$base" upload --excluir '*.log' "$base/local/a.txt" /r/a.txt
  assert_igual "$USO" "$DBX_ESTADO" 'upload'
  _rodar "$base" list --incluir x /r
  assert_igual "$USO" "$DBX_ESTADO" 'list'
  _rodar "$base" info --excluir x /r
  assert_igual "$USO" "$DBX_ESTADO" 'info'
  _rodar "$base" restaurar --incluir x /r/a.txt
  assert_igual "$USO" "$DBX_ESTADO" 'restaurar'
  _rodar "$base" lixeira --incluir x /r
  assert_igual "$USO" "$DBX_ESTADO" 'lixeira'
  _sem_efeito "$base" 'recusas'
}

teste_flt20_malformado_com_trava_ocupada_sai_2_e_nao_7() {
  local base
  base=$(_cenario)
  _local "$base" a.txt
  printf 'list_folder' >"$base/bloquear"
  _segundo_plano "$base" dono sync --enviar --origem "$base/local" --destino /r --excluir 'a'
  _esperar_arquivo "$base/bloqueado"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir '[z-a]'
  assert_igual "$USO" "$DBX_ESTADO" 'malformado: 2, nao 7'
  # TC-FES-14: o mesmo par com OUTRO filtro valido se exclui (7).
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir 'b'
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'filtros diferentes, mesma trava'
  : >"$base/soltar"
  _esperar_arquivo "$base/estado.dono"
  assert_igual 0 "$(<"$base/estado.dono")" "o dono conclui; $(<"$base/err.dono")"
}

teste_flt21_aceito_em_sync_verificar_e_download_de_pasta_com_aliases() {
  local base pt en
  base=$(_cenario)
  _local "$base" a.log
  _local "$base" b.txt
  _listar "$base" "$(_arq c.log)" "$(_arq d.txt)"
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "sync --enviar; $DBX_ERRO"
  pt=$DBX_SAIDA
  _rodar "$base" --dry-run sync --push --source "$base/local" --dest /r --exclude '*.log'
  en=$DBX_SAIDA
  assert_igual "$pt" "$en" 'alias --exclude identico'
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local" --incluir '*.txt'
  assert_igual 0 "$DBX_ESTADO" "sync --receber; $DBX_ERRO"
  pt=$DBX_SAIDA
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local" --include '*.txt'
  assert_igual "$pt" "$DBX_SAIDA" 'alias --include identico'
  _rodar "$base" verificar --receber --origem /r --destino "$base/local" --excluir '*' --incluir x
  assert_igual 0 "$DBX_ESTADO" "verificar aceita; $DBX_ERRO"
  _rodar "$base" download /r "$base/baixado" --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "download de pasta aceita; $DBX_ERRO"
  assert_arquivo_existe "$base/baixado/d.txt" 'o que passa e recebido'
  assert_arquivo_ausente "$base/baixado/c.log" 'o filtrado nao'
}

# ---------------------------------------------------------------------------
# TC-FES — escopo, travessia e espelhamento
# ---------------------------------------------------------------------------

teste_fes02_so_incluir_pdf_e_pasta_sem_pdf_nao_e_criada() {
  local base
  base=$(_cenario)
  _local "$base" a/b/c.pdf
  _local "$base" a/x.txt
  _local "$base" d/e.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --incluir '*.pdf'
  assert_contem 'transferir=a/b/c.pdf' "$DBX_SAIDA" 'pdf em profundidade'
  assert_nao_contem 'x.txt' "$DBX_SAIDA" 'o resto nao entra'
  assert_nao_contem 'e.txt' "$DBX_SAIDA" 'nem e listado'
  _listar "$base" "$(_arq a/b/c.pdf)" "$(_arq d/e.txt)"
  _rodar "$base" sync --receber --origem /r --destino "$base/recebido" --incluir '*.pdf'
  assert_igual 0 "$DBX_ESTADO" "recebe; $DBX_ERRO"
  assert_arquivo_existe "$base/recebido/a/b/c.pdf" 'pdf recebido'
  assert_arquivo_ausente "$base/recebido/d" 'pasta sem pdf nao e criada'
}

teste_fes04_pasta_excluida_nao_e_percorrida_e_erro_dentro_dela_nao_conta() {
  [[ $EUID -ne 0 ]] || pular 'root le diretorio sem permissao'
  local base
  base=$(_cenario)
  _local "$base" a.txt
  _local "$base" cache/NAO-TOCAR.bin
  mkdir -p "$base/local/cache/fechado"
  chmod 000 "$base/local/cache/fechado"
  # `stat` que registra: a travessia nunca o chama dentro da pasta excluida.
  printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexec %q "$@"\n' "$BASH" "$base/stat.log" \
    "$(command -v stat)" >"$base/bin/stat"
  chmod +x "$base/bin/stat"
  _listar "$base" "$(_arq a.txt)" "$(_arq z.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --excluir 'cache/'
  chmod 700 "$base/local/cache/fechado"
  assert_igual 0 "$DBX_ESTADO" "saida 0; $DBX_ERRO"
  assert_contem 'travessia_parcial=nao' "$DBX_SAIDA" 'erro dentro da pasta excluida nao existe'
  assert_contem '/r/z.txt' "$(_deletes "$base")" 'a exclusao segue habilitada'
  assert_nao_contem 'NAO-TOCAR' "$(cat "$base/stat.log" 2>/dev/null)" 'stat nunca dentro da pasta excluida'
  assert_nao_contem 'cache' "$(_uploads "$base")" 'nada dela e enviado'
}

teste_fes05_regressao_ilegivel_fora_de_pasta_excluida_desabilita_a_exclusao() {
  [[ $EUID -ne 0 ]] || pular 'root le diretorio sem permissao'
  local base
  base=$(_cenario)
  _local "$base" a.txt
  mkdir -p "$base/local/fechado"
  chmod 000 "$base/local/fechado"
  _listar "$base" "$(_arq a.txt)" "$(_arq z.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --excluir 'cache/'
  chmod 700 "$base/local/fechado"
  assert_contem 'travessia_parcial=sim' "$DBX_SAIDA" 'parcial como hoje'
  assert_igual '' "$(_deletes "$base")" 'nenhuma exclusao'
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'codigo de travessia parcial'
}

teste_fes06_remoto_sob_pasta_excluida_e_descartado_e_a_pasta_conta_1() {
  local base
  base=$(_cenario)
  _local "$base" cache/l1
  _local "$base" cache/sub/l2
  _local "$base" k.txt
  _listar "$base" "$(_pasta cache)" "$(_arq cache/a)" "$(_arq cache/b/c)" "$(_pasta cache/b)" "$(_arq k.txt)"
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local" --excluir 'cache/'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_contem 'filtrados_origem=1' "$DBX_SAIDA" 'pasta remota conta 1'
  assert_contem 'filtrados_destino=1' "$DBX_SAIDA" 'pasta local conta 1'
  assert_nao_contem 'cache' "${DBX_SAIDA//excluir=cache\//}" 'nada sob a pasta no plano'
}

teste_fes07_d1_enviar_espelhar_zero_delete_de_filtrado() {
  local base
  base=$(_cenario)
  _local "$base" keep.txt
  _local "$base" novo.log
  _listar "$base" "$(_arq x.log)" "$(_arq sub/y.log)" "$(_arq z.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_igual '{"path":"/r/z.txt"}' "$(_deletes "$base")" 'so o item no escopo e apagado'
  assert_nao_contem '.log' "$(_uploads "$base")" 'filtrado da origem nao e enviado'
  assert_contem 'keep.txt' "$(_uploads "$base")" 'o resto e enviado'
}

teste_div95_chamada_json_depois_de_um_envio_leva_o_proprio_corpo() {
  # DIV-95 (defeito anterior a fase 4, achado pelo registro de chamadas de
  # TC-FES-07): `lib/http` nao limpava o arquivo de corpo do modo de conteudo,
  # e o `delete_v2` que seguia um envio levava o ARQUIVO ENVIADO como corpo.
  local base
  base=$(_cenario)
  _local "$base" a.txt 'conteudo enviado'
  _listar "$base" "$(_arq z.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_igual '{"path":"/r/z.txt"}' "$(_deletes "$base")" 'o corpo do delete_v2 e o JSON dele'
}

teste_div103_receber_espelhar_incluir_impreciso_nao_apaga_nome_nao_utf8() {
  # DIV-103 revisada: `--incluir '[!e]*'` (conjunto negado, impreciso em bytes)
  # sobre nome local que nao e UTF-8 valido, ausente no remoto: o item NAO
  # entra no escopo e o espelhamento nao o apaga.
  local base nome=$'lixo\xff.bin'
  base=$(_cenario)
  _local "$base" "$nome" 'bytes do operador'
  _local "$base" z.txt
  _listar "$base" "$(_arq k.txt)"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local" \
    --incluir $'[!\xc3\xa9]*'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_arquivo_existe "$base/local/$nome" 'nome nao UTF-8 intacto'
  assert_igual 'bytes do operador' "$(<"$base/local/$nome")" 'mesmos bytes'
  assert_arquivo_ausente "$base/local/z.txt" 'o item valido no escopo e apagado (o espelho funciona)'
  assert_nao_contem 'lixo' "$(cat "$base/rm.log" 2>/dev/null)" 'nenhum rm sobre ele'
}

teste_fes08_d2_receber_espelhar_filtrado_local_intacto_sem_rm() {
  local base antes
  base=$(_cenario)
  _local "$base" cache/a.bin 'bytes do operador'
  _local "$base" z.txt
  antes=$(stat -c '%Y %s' -- "$base/local/cache/a.bin")
  _listar "$base" "$(_arq k.txt)"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local" --excluir 'cache/'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_igual 'bytes do operador' "$(<"$base/local/cache/a.bin")" 'mesmos bytes'
  assert_igual "$antes" "$(stat -c '%Y %s' -- "$base/local/cache/a.bin")" 'mesmo mtime'
  assert_arquivo_ausente "$base/local/z.txt" 'o item no escopo e apagado (o espelho funciona)'
  assert_nao_contem 'cache' "$(cat "$base/rm.log" 2>/dev/null)" 'nenhum rm sobre o filtrado'
}

teste_fes09_d3_incluir_nao_apaga_o_que_nao_casa_nos_dois_sentidos() {
  local base
  base=$(_cenario)
  _local "$base" a.pdf
  _listar "$base" "$(_arq nota.txt)" "$(_arq velho.pdf)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --incluir '*.pdf'
  assert_igual 0 "$DBX_ESTADO" "enviar; $DBX_ERRO"
  assert_igual '{"path":"/r/velho.pdf"}' "$(_deletes "$base")" 'nota.txt fica; velho.pdf (no escopo) sai'
  base=$(_cenario)
  _local "$base" nota.txt
  _local "$base" velho.pdf
  _listar "$base" "$(_arq a.pdf)"
  _rodar "$base" sync --receber --espelhar --confirmar --origem /r --destino "$base/local" --incluir '*.pdf'
  assert_igual 0 "$DBX_ESTADO" "receber; $DBX_ERRO"
  assert_arquivo_existe "$base/local/nota.txt" 'nota.txt local fica'
  assert_arquivo_ausente "$base/local/velho.pdf" 'velho.pdf no escopo sai'
}

teste_fes10_d4_filtro_novo_nao_apaga_o_que_deixou_de_fora() {
  local base
  base=$(_cenario)
  _local "$base" a.txt
  _listar "$base" "$(_arq a.txt)" "$(_arq b/c.txt)" "$(_arq b/d/e.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --excluir 'b/'
  assert_igual 0 "$DBX_ESTADO" "com filtro; $DBX_ERRO"
  assert_igual '' "$(_deletes "$base")" 'nada sob b/ e apagado'
  : >"$base/chamadas"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r
  assert_contem '/r/b/c.txt' "$(_deletes "$base")" 'sem o filtro, a regra normal volta'
  assert_contem '/r/b/d/e.txt' "$(_deletes "$base")" 'inclusive em profundidade'
}

# _copia_mutante <arquivo> <sed> [<arquivo> <sed>]... — copia do produto com
# os arquivos dados mutados pelo `sed` de cada um.
_copia_mutante() {
  local copia
  copia=$(mktemp -d "$DBX_TESTES_TMP/mutante.XXXXXX")
  cp -R "$DBX_HARNESS_RAIZ/bin" "$DBX_HARNESS_RAIZ/lib" "$DBX_HARNESS_RAIZ/commands" "$copia/"
  [[ -d $DBX_HARNESS_RAIZ/completions ]] && cp -R "$DBX_HARNESS_RAIZ/completions" "$copia/"
  while [[ $# -ge 2 ]]; do
    sed -i "$2" "$copia/$1"
    cmp -s "$DBX_HARNESS_RAIZ/$1" "$copia/$1" && _harness_falhar "a mutacao nao alterou $1"
    shift 2
  done
  printf '%s' "$copia"
}

_rodar_mutante() { # <mutante> <base> <argumentos...>
  local mutante=$1 base=$2
  shift 2
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$mutante/bin/dbx" "$@" </dev/null >/dev/null 2>&1
  return 0
}

teste_fes11_d5_mutacao_que_filtra_so_um_lado_e_detectada() {
  local base mutante
  # Filtro so na origem: o destino passa sem filtro e a guarda sem estado cede.
  mutante=$(_copia_mutante lib/sync.sh '/^dbx_sync_no_escopo() {$/a\  [[ $1 == destino ]] \&\& return 0' \
    commands/sync.sh '/^_dbx_cmd_sync_protegido() {$/a\  return 1')
  base=$(_cenario)
  _local "$base" keep.txt
  _listar "$base" "$(_arq x.log)"
  _rodar_mutante "$mutante" "$base" sync --enviar --espelhar --confirmar --origem "$base/local" \
    --destino /r --excluir '*.log'
  assert_contem 'x.log' "$(_deletes "$base")" 'a mutacao apagaria o filtrado (d1): o caso a reprova'
  base=$(_cenario)
  _local "$base" a.txt
  _local "$base" velho.bin
  _listar "$base" "$(_arq k.txt)"
  _rodar_mutante "$mutante" "$base" sync --receber --espelhar --confirmar --origem /r \
    --destino "$base/local" --excluir '*.bin'
  assert_arquivo_ausente "$base/local/velho.bin" 'a mutacao apagaria o filtrado local (d2)'
  # So o filtro do destino desligado: a guarda sem estado segura sozinha.
  mutante=$(_copia_mutante lib/sync.sh '/^dbx_sync_no_escopo() {$/a\  [[ $1 == destino ]] \&\& return 0')
  base=$(_cenario)
  _local "$base" keep.txt
  _listar "$base" "$(_arq x.log)"
  _rodar_mutante "$mutante" "$base" sync --enviar --espelhar --confirmar --origem "$base/local" \
    --destino /r --excluir '*.log'
  assert_igual '' "$(_deletes "$base")" 'a segunda barreira, sem estado, segura sozinha'
  # Filtro so no destino: o filtrado da origem seria enviado.
  mutante=$(_copia_mutante lib/sync.sh '/^dbx_sync_no_escopo() {$/a\  [[ $1 == origem ]] \&\& return 0')
  base=$(_cenario)
  _local "$base" novo.log
  _rodar_mutante "$mutante" "$base" sync --enviar --origem "$base/local" --destino /r --excluir '*.log'
  assert_contem 'novo.log' "$(_uploads "$base")" 'a mutacao enviaria o filtrado: a contagem a reprova'
}

teste_fes_guarda_sem_estado_nao_apaga_filtrado_mesmo_com_memoria_que_o_conhece() {
  # A memoria registra x.log de uma execucao sem filtro; com o filtro, a guarda
  # nao consulta a memoria e x.log continua intocado no destino.
  local base
  base=$(_cenario)
  _local "$base" x.log
  _local "$base" k.txt
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "primeira; $DBX_ERRO"
  "$RM_REAL" -f "$base/local/x.log"
  _listar "$base" "$(_arq x.log)" "$(_arq k.txt)"
  : >"$base/chamadas"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --excluir '*.LOG'
  assert_igual 0 "$DBX_ESTADO" "segunda; $DBX_ERRO"
  assert_igual '' "$(_deletes "$base")" 'filtrado sem caixa nunca apagado'
}

teste_fes12_origem_toda_filtrada_e_vazia_para_a_guarda() {
  local base
  base=$(_cenario)
  _local "$base" a.txt
  _listar "$base" "$(_arq b.pdf)" "$(_arq c.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --incluir '*.pdf'
  assert_igual "$NAO_CONCLUIDA" "$DBX_ESTADO" 'recusa'
  assert_contem 'origem vazia depois dos filtros' "$DBX_ERRO" 'mensagem'
  assert_contem "--incluir '*.pdf'" "$DBX_ERRO" 'cita os filtros ativos'
  assert_contem '--permitir-origem-vazia' "$DBX_ERRO" 'e a dispensa'
  assert_contem 'recusada=origem vazia' "$DBX_SAIDA" 'plano'
  assert_igual '' "$(_deletes "$base")$(_uploads "$base")" 'nenhuma escrita'
  _rodar "$base" --dry-run sync --enviar --espelhar --origem "$base/local" --destino /r --incluir '*.pdf'
  assert_igual 0 "$DBX_ESTADO" 'simulacao sai 0'
  assert_contem 'recusaria=origem vazia' "$DBX_SAIDA" 'simulacao anuncia'
  _rodar "$base" sync --enviar --espelhar --confirmar --permitir-origem-vazia --origem "$base/local" \
    --destino /r --incluir '*.pdf'
  assert_igual 0 "$DBX_ESTADO" "dispensa; $DBX_ERRO"
  assert_igual '{"path":"/r/b.pdf"}' "$(_deletes "$base")" 'apaga so o que esta no escopo'
  base=$(_cenario)
  _local "$base" a.txt
  _listar "$base" "$(_arq c.txt)"
  _rodar "$base" sync --enviar --espelhar --confirmar --origem "$base/local" --destino /r --incluir '*.pdf'
  assert_igual 0 "$DBX_ESTADO" "sem item no escopo a apagar, sem recusa; $DBX_ERRO"
}

_memoria() { # <base> — registros da memoria do sync, um por linha
  local -a lista=()
  shopt -s nullglob
  lista=("$1/estado/dbx"/memoria-*)
  shopt -u nullglob
  [[ ${#lista[@]} -eq 1 ]] || { printf 'memorias:%s' "${#lista[@]}"; return 0; }
  tr '\0' '\n' <"${lista[0]}"
}

teste_fes13_memoria_sem_filtrados_e_sem_poder_de_decisao() {
  local base com sem
  base=$(_cenario)
  _local "$base" a.txt
  _local "$base" b.log
  _local "$base" cache/c.bin
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir '*.log' --excluir 'cache/'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_contem 'a.txt' "$(_memoria "$base")" 'pasta excluida nao impede a gravacao'
  assert_nao_contem 'b.log' "$(_memoria "$base")" 'filtrado fora da memoria'
  assert_nao_contem 'c.bin' "$(_memoria "$base")" 'conteudo da pasta excluida fora'
  _listar "$base" "$(_arq a.txt '' 1 '' "$(_resumo x)")"
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  com=$DBX_SAIDA
  "$RM_REAL" -f "$base"/estado/dbx/memoria-*
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  sem=$DBX_SAIDA
  assert_igual "$(sed '/^memoria=/d' <<<"$sem")" "$(sed '/^memoria=/d' <<<"$com")" 'mesmo plano com e sem memoria'
}

teste_fes15_colisao_de_caixa_dentro_de_pasta_excluida_nao_recusa() {
  local base
  base=$(_cenario)
  _local "$base" velho/a.txt
  _local "$base" velho/A.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --excluir 'velho/'
  assert_igual 0 "$DBX_ESTADO" "dentro da pasta excluida; $DBX_ERRO"
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --excluir 'outro/'
  assert_igual "$CONFLITO" "$DBX_ESTADO" 'fora dela, recusa'
}

_primeiro_registro() { # <texto> — ate o segundo `contrato=`
  local resto=${1#*contrato=}
  printf 'contrato=%s' "${resto%%contrato=*}"
}

teste_fes16_plano_simulado_igual_ao_real_e_campos_do_plano() {
  local base simulado real
  base=$(_cenario)
  _local "$base" a.txt
  _local "$base" b.log
  _local "$base" cache/c
  _listar "$base" "$(_arq z.log)"
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --excluir '*.log' --excluir 'cache/'
  simulado=$(_primeiro_registro "$DBX_SAIDA")
  assert_contem 'filtros=sim' "$simulado" 'cabecalho'
  assert_contem 'excluir=*.log' "$simulado" 'padrao citado'
  assert_contem 'excluir=cache/' "$simulado" 'cada padrao'
  assert_contem 'filtrados_origem=2' "$simulado" 'b.log e cache contam 1 cada'
  assert_contem 'filtrados_destino=1' "$simulado" 'z.log'
  assert_nao_contem 'b.log' "${simulado//excluir=\*.log/}" 'filtrados nao listados um a um'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir '*.log' --excluir 'cache/'
  real=$(_primeiro_registro "$DBX_SAIDA")
  assert_igual "$simulado" "$real" 'plano do --dry-run = plano da execucao real'
  assert_contem 'filtrados_origem=2' "${DBX_SAIDA#*operacao=sync*operacao=sync}" 'resumo final tambem'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  assert_contem 'filtros=nao' "$DBX_SAIDA" 'sem filtros'
  assert_contem 'filtrados_origem=0' "$DBX_SAIDA" 'contagem 0'
  assert_contem 'filtrados_destino=0' "$DBX_SAIDA" 'contagem 0'
  _rodar "$base" --json --null --dry-run sync --enviar --origem "$base/local" --destino /r --excluir '*.log'
  # Registros terminados por NUL, lidos do arquivo (a variavel para no 1o NUL).
  local nulos
  nulos=$(tr '\0' '|' <"$base/out")
  assert_contem 'contrato=1|' "$nulos" 'versao principal inalterada'
  assert_contem '|filtros=sim|' "$nulos" '--null com os campos'
  assert_contem '|filtrados_origem=1|' "$nulos" '--null com as contagens'
}

teste_fes17_verificar_nao_conta_filtrado_como_divergencia() {
  local base
  base=$(_cenario)
  _local "$base" a.txt
  _local "$base" so-local.log
  _listar "$base" "$(_arq a.txt '' 1 '' "$(_resumo x)")" "$(_arq so-remoto.log)" "$(_arq cache/q)"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r --excluir '*.log' --excluir 'cache/'
  assert_igual 0 "$DBX_ESTADO" "so filtrados divergem: 0; $DBX_ERRO"
  assert_contem 'iguais=1' "$DBX_SAIDA" 'o item no escopo'
  assert_contem 'filtrados_origem=1' "$DBX_SAIDA" 'contagem da origem'
  assert_contem 'filtrados_destino=2' "$DBX_SAIDA" 'contagem do destino'
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" 'sem filtro, diverge'
}

teste_fes18_avisos_de_filtro_mal_escrito_em_stderr() {
  local base saida
  base=$(_cenario)
  _local "$base" a.txt
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r
  saida=$DBX_SAIDA
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --excluir '*.lgo'
  assert_igual 0 "$DBX_ESTADO" 'codigo inalterado'
  assert_contem "padrao '*.lgo' nao casou nenhum item" "$DBX_ERRO" 'aviso de padrao sem casamento'
  assert_igual 1 "$(grep -c 'nao casou' <<<"$DBX_ERRO")" 'uma linha'
  assert_igual "$(sed '/^filtros=/d' <<<"$saida")" "$(sed '/^filtros=/d; /^excluir=/d' <<<"$DBX_SAIDA")" \
    'stdout so ganha os campos do filtro'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --incluir '*.pdf'
  assert_contem 'nenhum item da origem passou pelos filtros' "$DBX_ERRO" 'aviso de origem toda filtrada'
}

teste_fes19_download_de_pasta_filtra_e_de_arquivo_recusa() {
  local base
  base=$(_cenario)
  _listar "$base" "$(_arq a.txt)" "$(_arq b.log)"
  _rodar "$base" download /r "$base/d1" --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "pasta; $DBX_ERRO"
  assert_arquivo_existe "$base/d1/a.txt" 'recebido'
  assert_arquivo_ausente "$base/d1/b.log" 'filtrado'
  assert_contem 'filtrados_origem=1' "$DBX_SAIDA" 'resumo do download de pasta'
  printf '%s' '{".tag":"file","name":"a.txt","path_display":"/r/a.txt","size":1}' >"$base/metadado"
  : >"$base/chamadas"
  _rodar "$base" download /r/a.txt "$base/d2" --excluir '*.log'
  assert_igual "$USO" "$DBX_ESTADO" 'arquivo com filtro: 2'
  assert_arquivo_ausente "$base/d2" 'nenhuma escrita'
  assert_igual 0 "$(_contar "$base" files/download)" 'nenhum recebimento'
}

teste_fes19_espaco_soma_so_o_escopo_e_filtrado_nao_gera_falha() {
  local base
  base=$(_cenario)
  _local "$base" a.txt 'abc'
  _local "$base" grande.bin '0123456789'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --excluir '*.bin'
  assert_contem 'espaco_necessario=3' "$DBX_SAIDA" 'so o escopo conta'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --excluir '*.bin'
  assert_nao_contem 'falha' "$DBX_ERRO" 'filtrado nunca gera linha de falha'
}

# ---------------------------------------------------------------------------
# TC-FDT — data e tamanho na linha de comando
# ---------------------------------------------------------------------------

teste_fdt01_fdt06_valores_invalidos_saem_2_sem_rede() {
  local base valor
  base=$(_cenario)
  for valor in 2026-1-5 2026-02-30 2026-10-01T12:00:00+03:00 2026-10-01T12:00:00.5Z ''; do
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --modificado-desde "$valor"
    assert_igual "$USO" "$DBX_ESTADO" "data [$valor]"
    assert_contem '--modificado-desde' "$DBX_ERRO" "nomeia a opcao: [$valor]"
    assert_nao_contem 'nao reconhecida' "$DBX_ERRO" "recusa de valor, nao de opcao: [$valor]"
  done
  for valor in 1.5M -1 01 10KB 1KiB 1T ' 1' '' 1234567890; do
    _rodar "$base" sync --enviar --origem "$base/local" --destino /r --min-size "$valor"
    assert_igual "$USO" "$DBX_ESTADO" "tamanho [$valor]"
    assert_nao_contem 'nao reconhecida' "$DBX_ERRO" "recusa de valor, nao de opcao: [$valor]"
  done
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --modified-since 2026-10-02 \
    --modified-until 2026-10-01
  assert_igual "$USO" "$DBX_ESTADO" 'desde > ate'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --tamanho-min 2K --tamanho-max 1K
  assert_igual "$USO" "$DBX_ESTADO" 'min > max'
  _sem_efeito "$base" 'recusas de data e tamanho'
}

teste_fdt04_local_por_mtime_em_utc_sem_date_em_qualquer_fuso() {
  local base fuso
  base=$(_cenario)
  _local "$base" velho.txt
  _local "$base" novo.txt
  touch -d '2026-09-30T23:59:59Z' "$base/local/velho.txt"
  touch -d '2026-10-01T00:00:00Z' "$base/local/novo.txt"
  for fuso in UTC America/Sao_Paulo Asia/Tokyo; do
    DBX_T_TZ=$fuso _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r \
      --modificado-desde 2026-10-01
    assert_igual 0 "$DBX_ESTADO" "$fuso; $DBX_ERRO"
    assert_contem 'transferir=novo.txt' "$DBX_SAIDA" "$fuso: o limite inclusivo entra"
    assert_nao_contem 'velho.txt' "$DBX_SAIDA" "$fuso: um segundo antes nao"
    assert_contem 'filtrados_origem=1' "$DBX_SAIDA" "$fuso: contado"
  done
  assert_arquivo_ausente "$base/proibido" 'nenhum date chamado'
}

teste_fdt05_remoto_por_server_modified_ignorando_client_modified() {
  local base
  base=$(_cenario)
  _listar "$base" "$(_arq a.txt 2026-10-05T00:00:00Z 1 2026-09-01T00:00:00Z)" \
    "$(_arq b.txt 2026-09-01T00:00:00Z 1 2026-10-05T00:00:00Z)"
  _rodar "$base" --dry-run sync --receber --origem /r --destino "$base/local" --modificado-desde 2026-10-01
  assert_contem 'transferir=a.txt' "$DBX_SAIDA" 'server_modified recente'
  assert_nao_contem 'b.txt' "$DBX_SAIDA" 'client_modified recente nao basta'
}

teste_fdt08_data_e_tamanho_com_espelhar_saem_2_antes_de_tudo() {
  local base opcao
  base=$(_cenario)
  for opcao in '--modificado-desde 2026-10-01' '--modificado-ate 2026-10-01' '--tamanho-min 1' \
    '--tamanho-max 1K' '--modified-since 2026-10-01' '--max-size 1'; do
    # shellcheck disable=SC2086  # a opcao e seu valor, separados de proposito
    _rodar "$base" sync --enviar --espelhar --origem "$base/local" --destino /r $opcao
    assert_igual "$USO" "$DBX_ESTADO" "$opcao"
    assert_contem 'filtros de data e tamanho avaliam so a origem e fariam o espelhamento apagar no destino; use --excluir/--incluir' \
      "$DBX_ERRO" "mensagem: $opcao"
    # shellcheck disable=SC2086
    _rodar "$base" sync --receber --mirror --origem /r --destino "$base/dst" $opcao
    assert_igual "$USO" "$DBX_ESTADO" "--mirror $opcao"
  done
  _sem_efeito "$base" 'data e tamanho com espelhamento'
  assert_arquivo_ausente "$base/dst" 'nenhuma escrita'
}

teste_fdt09_fdt10_so_a_origem_e_conjuncao_com_caminho() {
  local base
  base=$(_cenario)
  _local "$base" pequeno.txt 'a'
  _local "$base" grande.txt '0123456789'
  _local "$base" grande.log '0123456789'
  _listar "$base" "$(_arq so-destino.txt '' 1)"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --tamanho-min 5 --excluir '*.log'
  assert_igual 0 "$DBX_ESTADO" "conclui; $DBX_ERRO"
  assert_contem 'grande.txt' "$(_uploads "$base")" 'passa nos dois filtros'
  assert_nao_contem 'pequeno' "$(_uploads "$base")" 'fora da faixa, nao enviado'
  assert_nao_contem 'grande.log' "$(_uploads "$base")" 'conjuncao com o caminho'
  assert_contem 'filtrados_origem=2' "$DBX_SAIDA" 'os dois contados'
  assert_contem 'filtrados_destino=0' "$DBX_SAIDA" 'o destino nunca e avaliado por tamanho'
  assert_igual '' "$(_deletes "$base")" 'destino nao tocado'
}

teste_fdt11_pastas_nunca_sao_filtradas_por_data_ou_tamanho() {
  local base
  base=$(_cenario)
  _local "$base" a/b/grande.txt '0123456789'
  touch -d '2026-10-05T00:00:00Z' "$base/local/a/b/grande.txt"
  touch -d '2020-01-01T00:00:00Z' "$base/local/a" "$base/local/a/b"
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --tamanho-min 5 \
    --modificado-desde 2026-10-01
  assert_contem 'transferir=a/b/grande.txt' "$DBX_SAIDA" 'pasta antiga e pequena e percorrida'
}

teste_fdt12_verificar_recusa_data_e_tamanho_e_o_ultimo_valor_vence() {
  local base opcao
  base=$(_cenario)
  for opcao in --modificado-desde --modificado-ate --tamanho-min --tamanho-max --min-size; do
    _rodar "$base" verificar --enviar --origem "$base/local" --destino /r "$opcao" 1
    assert_igual "$USO" "$DBX_ESTADO" "verificar $opcao"
    assert_contem 'verificar' "$DBX_ERRO" "a recusa diz por que (DIV-83): $opcao"
    assert_nao_contem 'nao reconhecida' "$DBX_ERRO" "recusa propria: $opcao"
  done
  _sem_efeito "$base" 'verificar'
  _local "$base" a.txt 'abc'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --tamanho-min 1 --tamanho-min 1K
  assert_igual 0 "$DBX_ESTADO" "repetida e aceita; $DBX_ERRO"
  assert_nao_contem 'transferir=a.txt' "$DBX_SAIDA" 'o ultimo valor vence'
}

harness_executar "$@"
