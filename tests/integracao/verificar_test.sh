#!/usr/bin/env bash
# Testes ponta a ponta do `dbx verificar` (RF-65, TC-VER-01..09).
#
# O comando so le. O que estes casos precisam provar, alem dos quatro estados,
# e a AUSENCIA de efeito: nenhum endpoint de escrita sai pelo duplo de rede, o
# diretorio de estado fica byte a byte identico (inclusive ausente), a raiz
# local de recebimento nao e criada e nenhum temporario sobra.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

# _cenario — credencial, duplo de rede com listagem vazia (os casos a regravam
# em `$base/listagem`), arvore local e area temporaria propria (para provar que
# nada sobra nela).
_cenario() {
  local listagem='{"entries":[],"has_more":false}'
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/verificar.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' "$listagem" >"$base/listagem"
  cat >"$base/bin/curl" <<FIM
#!/usr/bin/env bash
base=$base
FIM
  cat >>"$base/bin/curl" <<'FIM'
cat >/dev/null 2>&1
saida=""; escrever=""; anterior=""; url=""
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
[[ -f $base/curl_saida ]] && exit "$(cat "$base/curl_saida")"
codigo=200
case $url in
  *oauth2/token*) corpo='{"access_token":"sl.t","expires_in":14400}' ;;
  *list_folder*) corpo=$(cat "$base/listagem") ;;
  *) corpo='{}' ;;
esac
if [[ $url == *list_folder* && -f $base/listagem_codigo ]]; then
  codigo=$(cat "$base/listagem_codigo"); corpo=$(cat "$base/listagem_corpo")
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  IFS= read -r -d '' DBX_SAIDA <"$base/out"
  IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_resumo_de() { # <arquivo>
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$1'"
}

_entrada() { # <caminho> <hash>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":1,"rev":"r1"}' "$1" "$2"
}

_listagem() { # <entradas...>
  local IFS=,
  printf '{"entries":[%s],"has_more":false}' "$*"
}

_retrato() { # <diretorio> — caminho, modo e conteudo de tudo que existe nele
  [[ -e $1 ]] || {
    printf 'ausente\n'
    return 0
  }
  find "$1" -printf '%P %m %s\n' | sort
  find "$1" -type f -exec cksum {} + | sort
}

_escritas() { # <base>
  _harness_contar 'files/upload\|files/delete\|upload_session\|create_folder\|files/move\|files/copy' "$1/chamadas"
}

readonly OUTRO=0000000000000000000000000000000000000000000000000000000000000000

# ---------------------------------------------------------------------------
# TC-VER-01, TC-VER-02, TC-VER-09 — estados, contagens e codigo de saida
# ---------------------------------------------------------------------------

teste_ver01_arvores_iguais_saem_com_zero_e_nao_escrevem() {
  local base
  base=$(_cenario)
  printf 'um' >"$base/local/a.txt"
  mkdir "$base/local/sub"
  printf 'dois' >"$base/local/sub/b.txt"
  _listagem "$(_entrada /r/a.txt "$(_resumo_de "$base/local/a.txt")")" \
    "$(_entrada /r/sub/b.txt "$(_resumo_de "$base/local/sub/b.txt")")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "arvores iguais saem com 0; diagnostico: $DBX_ERRO"
  assert_contem $'igual=a.txt\nigual=sub/b.txt' "$DBX_SAIDA" 'cada arquivo listado como igual'
  assert_contem $'iguais=2\ndiferentes=0\nso_origem=0\nso_destino=0\ntotal=2' "$DBX_SAIDA" \
    'quatro contagens coerentes e o total'
  assert_igual 0 "$(_escritas "$base")" 'nenhum endpoint de escrita'
}

teste_ver01_arvores_ambas_vazias_saem_com_zero() {
  local base
  base=$(_cenario)
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "vazias sao iguais; diagnostico: $DBX_ERRO"
  assert_contem 'total=0' "$DBX_SAIDA" 'nada a listar'
}

teste_ver02_quatro_estados_e_codigo_onze_no_enviar() {
  local base
  base=$(_cenario)
  printf 'igual' >"$base/local/igual.txt"
  printf 'novo' >"$base/local/mudou.txt"
  printf 'so aqui' >"$base/local/so_local.txt"
  _listagem "$(_entrada /r/igual.txt "$(_resumo_de "$base/local/igual.txt")")" \
    "$(_entrada /r/mudou.txt "$OUTRO")" "$(_entrada /r/so_remoto.txt "$OUTRO")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" 'divergencia sai com 11'
  assert_contem 'sentido=enviar' "$DBX_SAIDA" 'o sentido e declarado'
  assert_contem 'igual=igual.txt' "$DBX_SAIDA" 'igual'
  assert_contem $'diferente=mudou.txt\nmotivo=conteudo' "$DBX_SAIDA" 'diferente, com motivo'
  assert_contem 'so_origem=so_local.txt' "$DBX_SAIDA" 'so na origem (local)'
  assert_contem 'so_destino=so_remoto.txt' "$DBX_SAIDA" 'so no destino (remoto)'
  assert_contem $'iguais=1\ndiferentes=1\nso_origem=1\nso_destino=1\ntotal=4' "$DBX_SAIDA" 'contagens'
  assert_contem 'divergencia encontrada' "$DBX_ERRO" 'mensagem propria (DIV-34)'
  assert_nao_contem 'transferido' "$DBX_ERRO" 'sem a mensagem padrao de integridade'
  assert_igual 0 "$(_escritas "$base")" 'nenhum endpoint de escrita'
}

teste_ver02_no_receber_os_papeis_se_invertem() {
  local base
  base=$(_cenario)
  printf 'so aqui' >"$base/local/so_local.txt"
  _listagem "$(_entrada /r/so_remoto.txt "$OUTRO")" >"$base/listagem"
  _rodar "$base" verificar --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" 'divergencia sai com 11'
  assert_contem 'so_origem=so_remoto.txt' "$DBX_SAIDA" 'a origem agora e a remota'
  assert_contem 'so_destino=so_local.txt' "$DBX_SAIDA" 'o destino agora e o local'
  assert_igual 0 "$(_escritas "$base")" 'nenhum endpoint de escrita'
}

teste_ver09_origem_vazia_nao_e_recusada_e_lista_tudo_como_so_destino() {
  local base
  base=$(_cenario)
  _listagem "$(_entrada /r/a.txt "$OUTRO")" "$(_entrada /r/b.txt "$OUTRO")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" 'origem vazia nao e recusa: 11'
  assert_contem $'so_destino=a.txt\nso_destino=b.txt' "$DBX_SAIDA" 'tudo so no destino'
}

# ---------------------------------------------------------------------------
# TC-VER-03, TC-VER-04 — nenhuma escrita; a memoria nao decide
# ---------------------------------------------------------------------------

teste_ver03_so_le_e_nao_toca_estado_nem_temporarios() {
  local base antes depois
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _listagem "$(_entrada /r/b.txt "$OUTRO")" >"$base/listagem"
  # Estado ausente continua ausente.
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual 'ausente' "$(_retrato "$base/estado")" 'estado ausente nao e criado'
  assert_igual '' "$(_retrato "$base/tmp" | grep -v '^ ' || true)" 'nenhum temporario sobra'
  local chamada
  while IFS= read -r chamada; do
    case $chamada in
      *oauth2/token | *files/list_folder | *files/list_folder/continue) ;;
      *) _harness_falhar "chamada fora das tres de leitura: $chamada" ;;
    esac
  done <"$base/chamadas"
  # Estado presente fica identico, byte a byte e modo a modo.
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  printf 'qualquer coisa' >"$base/estado/dbx/memoria-x"
  antes=$(_retrato "$base/estado")
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  depois=$(_retrato "$base/estado")
  assert_igual "$antes" "$depois" 'o diretorio de estado fica identico'
}

teste_ver03_receber_nao_cria_a_raiz_local_ausente() {
  local base
  base=$(_cenario)
  _listagem "$(_entrada /r/a.txt "$OUTRO")" >"$base/listagem"
  _rodar "$base" verificar --receber --origem /r --destino "$base/nao_existe"
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" 'tudo so na origem: 11'
  assert_contem 'so_origem=a.txt' "$DBX_SAIDA" 'a raiz ausente e arvore vazia'
  assert_arquivo_ausente "$base/nao_existe" 'o verificar nao cria a raiz local'
}

teste_ver04_memoria_corrompida_ou_de_outra_conta_nao_muda_o_resultado() {
  local base limpa
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _listagem "$(_entrada /r/a.txt "$OUTRO")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  limpa=$DBX_SAIDA
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  local arquivo
  for arquivo in "$base"/estado/dbx/memoria-a "$base"/estado/dbx/upload-b; do
    printf 'v2\tdbid:OUTRA\ncorrompido\0\t\t' >"$arquivo"
  done
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$limpa" "$DBX_SAIDA" 'memoria corrompida ou alheia: resultado identico'
}

# ---------------------------------------------------------------------------
# TC-VER-05 — guardas (Regra 6: caminho hostil)
# ---------------------------------------------------------------------------

teste_ver05_caminho_remoto_hostil_e_recusado_antes_da_api_e_do_disco() {
  local base
  base=$(_cenario)
  _rodar "$base" verificar --enviar --origem "$base/local" --destino '/r/../../fora'
  assert_igual "$(dbx_errors_codigo_saida caminho_recusado)" "$DBX_ESTADO" 'caminho fora da raiz: 13'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada a API'
  _rodar "$base" verificar --receber --origem 'relativo/sem/raiz' --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida caminho_recusado)" "$DBX_ESTADO" 'caminho remoto malformado: 13'
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada a API'
}

teste_ver05_vinculo_simbolico_para_fora_nao_e_seguido_e_a_travessia_e_parcial() {
  local base
  base=$(_cenario)
  mkdir -p "$base/fora"
  printf 'segredo de fora' >"$base/fora/alvo.txt"
  ln -s "$base/fora" "$base/local/atalho"
  printf 'x' >"$base/local/a.txt"
  _listagem "$(_entrada /r/a.txt "$(_resumo_de "$base/local/a.txt")")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'travessia parcial sai com 14'
  assert_nao_contem 'alvo.txt' "$DBX_SAIDA" 'o vinculo nao e seguido'
  assert_contem 'travessia_parcial=sim' "$DBX_SAIDA" 'o relatorio declara a parcialidade'
}

teste_ver05_colisao_de_caixa_local_e_recusada_antes_de_qualquer_acesso_remoto() {
  local base
  base=$(_cenario)
  printf '1' >"$base/local/a.txt"
  printf '2' >"$base/local/A.txt"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" 'mesmo codigo do sync'
  assert_contem 'colisao de caixa' "$DBX_ERRO" 'o motivo e nomeado'
  assert_arquivo_ausente "$base/chamadas" 'nenhum acesso remoto'
}

teste_ver05_caixa_e_acento_sao_o_mesmo_caminho() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/Docs"
  printf 'foto' >"$base/local/Docs/Foto.JPG"
  printf 'acento' >"$base/local/É.txt"
  _listagem "$(_entrada /r/docs/foto.jpg "$(_resumo_de "$base/local/Docs/Foto.JPG")")" \
    "$(_entrada /r/é.txt "$(_resumo_de "$base/local/É.txt")")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  if [[ $DBX_ERRO == *'localidade'* ]]; then
    pular 'localidade C.UTF-8 ausente nesta maquina (RF-54(f))'
  fi
  assert_igual 0 "$DBX_ESTADO" "caixa e acento casam; diagnostico: $DBX_ERRO"
  assert_contem 'igual=Docs/Foto.JPG' "$DBX_SAIDA" 'grafia da origem preservada'
  assert_contem 'igual=É.txt' "$DBX_SAIDA" 'É e é sao o mesmo caminho'
}

# ---------------------------------------------------------------------------
# TC-VER-06 — saida estruturada
# ---------------------------------------------------------------------------

teste_ver06_json_traz_a_versao_de_contrato_e_null_preserva_quebra_de_linha() {
  local base
  base=$(_cenario)
  printf 'x' >"$base/local/"$'linha\nquebrada.txt'
  _rodar "$base" --json verificar --enviar --origem "$base/local" --destino /r
  assert_contem 'contrato=1' "$DBX_SAIDA" 'versao de contrato'
  assert_contem 'operacao=verificar' "$DBX_SAIDA" 'operacao nomeada'
  assert_contem "so_origem=\$'linha\\nquebrada.txt'" "$DBX_SAIDA" \
    'por linha, o nome com quebra sai citado, sem abrir outra linha'
  _rodar "$base" --json --null verificar --enviar --origem "$base/local" --destino /r
  assert_contem $'\0so_origem=linha\nquebrada.txt\0' "$DBX_SAIDA" 'com --null o nome sai integro'
}

# ---------------------------------------------------------------------------
# TC-VER-07 — erro de execucao prevalece sobre divergencia
# ---------------------------------------------------------------------------

teste_ver07_erro_de_execucao_prevalece_sobre_a_divergencia() {
  local base
  base=$(_cenario)
  printf 'x' >"$base/local/so_local.txt"
  printf '429' >"$base/listagem_codigo"
  printf '%s' '{"error_summary":"too_many_requests/"}' >"$base/listagem_corpo"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida limite_taxa)" "$DBX_ESTADO" 'limite de taxa: 8'
  printf '401' >"$base/listagem_codigo"
  printf '%s' '{"error_summary":"invalid_access_token/"}' >"$base/listagem_corpo"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida autenticacao)" "$DBX_ESTADO" 'autenticacao: 5'
  rm -f "$base/listagem_codigo"
  printf '7' >"$base/curl_saida"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida rede)" "$DBX_ESTADO" 'rede: 9'
}

# ---------------------------------------------------------------------------
# TC-VER-08 — opcoes recusadas e aliases
# ---------------------------------------------------------------------------

teste_ver08_opcoes_do_sync_que_nao_se_aplicam_sao_recusadas() {
  local base opcao
  base=$(_cenario)
  for opcao in --espelhar --mirror --confirmar --yes --permitir-origem-vazia \
    --allow-empty-source --forcar --force; do
    _rodar "$base" verificar --enviar --origem "$base/local" --destino /r "$opcao"
    assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" "$opcao recusada como 2"
  done
  assert_arquivo_ausente "$base/chamadas" 'a recusa vem antes da rede'
}

teste_ver08_aliases_produzem_o_mesmo_resultado() {
  local base referencia
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _listagem "$(_entrada /r/b.txt "$OUTRO")" >"$base/listagem"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  referencia=$DBX_SAIDA
  _rodar "$base" verify --push --source "$base/local" --dest /r
  assert_igual "$referencia" "$DBX_SAIDA" 'verify, --push, --source e --dest'
  _rodar "$base" verify --pull --source /r --dest "$base/local"
  assert_contem 'so_origem=b.txt' "$DBX_SAIDA" '--pull inverte os papeis'
  _rodar "$base" verificar --receber --origem /r --destino "$base/local"
  assert_contem 'so_origem=b.txt' "$DBX_SAIDA" 'mesmo resultado em portugues'
}

teste_ver08_simulacao_e_aceita_e_sem_efeito() {
  local base referencia
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _rodar "$base" verificar --enviar --origem "$base/local" --destino /r
  referencia=$DBX_SAIDA
  _rodar "$base" --dry-run verificar --enviar --origem "$base/local" --destino /r
  assert_igual "$referencia" "$DBX_SAIDA" '--dry-run nao muda o relatorio'
}

harness_executar "$@"
