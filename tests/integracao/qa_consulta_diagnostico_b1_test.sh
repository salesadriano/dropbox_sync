#!/usr/bin/env bash
# Suite independente do QA Expert — fase 1 do backlog (RF-65 a RF-68).
#
# Porte M: validacao independente de `dbx verificar`, `dbx diagnostico`, da
# checagem previa de espaco do `upload`/`sync --enviar` e do autocompletar de
# bash. Massa, duplo de `curl`, valores sentinela e retrato do estado sao
# proprios do QA; nenhum caso reaproveita auxiliar do Senior Developer.
#
# Precedencia e dados: os casos sao independentes entre si. Cada um cria a
# propria massa (`_qa_cenario`, massa derivada sob $DBX_TESTES_TMP) e nao
# depende de estado de caso anterior; o descarte e o do executor, ao fim do
# roteiro inteiro.
#
# shellcheck disable=SC2016
# Justificativa: o duplo de `curl` e literal.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
BASH_ABSOLUTO=$(command -v bash)
readonly BASH_ABSOLUTO

QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_CONFIG=$(dbx_errors_codigo_saida configuracao)
QA_INTEGRIDADE=$(dbx_errors_codigo_saida integridade)
QA_ESPACO=$(dbx_errors_codigo_saida espaco)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
QA_REDE=$(dbx_errors_codigo_saida rede)
QA_RECUSADO=$(dbx_errors_codigo_saida caminho_recusado)
readonly QA_USO QA_CONFIG QA_INTEGRIDADE QA_ESPACO QA_NAO_CONCLUIDA QA_REDE QA_RECUSADO

# Sentinelas proprios do QA: nenhum pode aparecer em saida alguma (RNF-03).
readonly QA_S_CHAVE='QAb1chaveDoApp_k7'
readonly QA_S_SEGREDO='QAb1segredoDoApp_s9'
readonly QA_S_REFRESH='QAb1refreshTok_r3'
readonly QA_S_ACESSO='sl.QAb1acessoTok_a5'
readonly QA_OUTRO_HASH=1111111111111111111111111111111111111111111111111111111111111111

# ---------------------------------------------------------------------------
# Massa e duplo
# ---------------------------------------------------------------------------
#
# _qa_cenario — publica BASE. Controles do duplo, por arquivo em $BASE:
#   r_<chave>  corpo da resposta     c_<chave>  codigo HTTP
#   x_<chave>  `curl` sai com este codigo (falha de transporte)
# com <chave> em token, espaco, listagem, continuacao, metadata, check, conta,
# sessao, escrita. Toda URL vai para `chamadas`, uma por linha.
_qa_cenario() {
  BASE=$(mktemp -d "$DBX_TESTES_TMP/qa_b1.XXXXXX")
  mkdir -p "$BASE/config/dbx" "$BASE/bin" "$BASE/local" "$BASE/tmp"
  _qa_credencial "{\"versao\":1,\"app_key\":\"$QA_S_CHAVE\",\"app_secret\":\"$QA_S_SEGREDO\",\"refresh_token\":\"$QA_S_REFRESH\",\"raiz_remota\":\"/\"}"
  printf '{"access_token":"%s","expires_in":14400}' "$QA_S_ACESSO" >"$BASE/r_token"
  printf '%s' '{"used":0,"allocation":{".tag":"individual","allocated":1000000000000}}' >"$BASE/r_espaco"
  printf '%s' '{"entries":[],"has_more":false}' >"$BASE/r_listagem"
  printf '%s' '{"error_summary":"path/not_found/.."}' >"$BASE/r_metadata"
  printf '409' >"$BASE/c_metadata"
  {
    printf '#!%s\nbase=%q\n' "$BASH_ABSOLUTO" "$BASE"
    cat <<'FIM'
cat >/dev/null 2>&1
saida='' escrever='' anterior='' url=''
for arg in "$@"; do
  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; esac
  case $arg in http*) url=$arg ;; esac
  anterior=$arg
done
printf '%s\n' "$url" >>"$base/chamadas"
case $url in
  *oauth2/token*) chave=token ;;
  *get_space_usage*) chave=espaco ;;
  *list_folder/continue*) chave=continuacao ;;
  *list_folder*) chave=listagem ;;
  *get_metadata*) chave=metadata ;;
  *check/user*) chave=check ;;
  *get_current_account*) chave=conta ;;
  *upload_session/start*) chave=sessao ;;
  *) chave=escrita ;;
esac
[[ -f $base/x_$chave ]] && exit "$(<"$base/x_$chave")"
codigo=200
[[ -f $base/c_$chave ]] && codigo=$(<"$base/c_$chave")
case $chave in
  conta) corpo='{"account_id":"dbid:QAB1"}' ;;
  check) corpo='{"result":"dbx"}' ;;
  sessao) corpo='{"session_id":"QA-S1"}' ;;
  escrita) corpo='{"name":"x","rev":"0qa1","size":1}' ;;
  *) corpo='' ;;
esac
[[ -f $base/r_$chave ]] && corpo=$(<"$base/r_$chave")
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$BASE/bin/curl"
  chmod +x "$BASE/bin/curl"
}

_qa_credencial() { # <json>
  printf '%s' "$1" >"$BASE/config/dbx/credencial.json"
  chmod 700 "$BASE/config/dbx"
  chmod 600 "$BASE/config/dbx/credencial.json"
}

# _qa_rodar [VAR=valor...] -- <argumentos do dbx...>
_qa_rodar() {
  local -a extra=()
  while [[ $# -gt 0 && $1 != '--' ]]; do
    extra+=("$1")
    shift
  done
  shift
  rm -f "$BASE/chamadas"
  env -i PATH="${QA_PATH:-$BASE/bin:$PATH}" HOME="$BASE" XDG_CONFIG_HOME="$BASE/config" \
    XDG_STATE_HOME="$BASE/estado" TMPDIR="$BASE/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    ${extra[@]+"${extra[@]}"} "$BASH_ABSOLUTO" "${QA_EXEC:-$DBX_EXEC}" "$@" >"$BASE/out" 2>"$BASE/err"
  ESTADO=$?
  SAIDA='' ERRO=''
  # Com `--null` o registro termina em NUL: a leitura troca NUL por quebra de
  # linha para as assercoes de texto (as de terminador olham o arquivo).
  SAIDA=$(tr '\0' '\n' <"$BASE/out")
  ERRO=$(tr '\0' '\n' <"$BASE/err")
  return 0
}

_qa_contar() { _harness_contar "$1" "$BASE/chamadas"; }
# Toda chamada que NAO esta na lista branca dada (lista branca, e nao lista
# negra: endpoint de escrita novo ou desconhecido tambem conta).
_qa_fora_de() { # <padrao_permitido>
  [[ -f $BASE/chamadas ]] || { printf '0'; return 0; }
  local total
  total=$(grep -vc -- "$1" "$BASE/chamadas") || true
  printf '%s' "${total:-0}"
}
_qa_escritas() { _qa_contar 'files/upload\|upload_session\|files/delete\|create_folder\|files/move\|files/copy'; }

_qa_hash() { # <arquivo>
  "$BASH_ABSOLUTO" -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo \"\$1\"" _ "$1"
}

_qa_entrada() { # <path_display> <hash> [tamanho]
  printf '{".tag":"file","name":"n","path_display":"%s","content_hash":"%s","size":%s,"rev":"0qa"}' \
    "$1" "$2" "${3:-1}"
}

_qa_listagem() { # <entradas...>
  local IFS=,
  printf '{"entries":[%s],"has_more":false}' "$*" >"$BASE/r_listagem"
}

_qa_espaco() { # <usado> <alocado>
  printf '{"used":%s,"allocation":{".tag":"individual","allocated":%s}}' "$1" "$2" >"$BASE/r_espaco"
}

_qa_bytes() { # <arquivo> <n>
  local linha
  printf -v linha '%*s' "$2" ''
  printf '%s' "${linha// /q}" >"$1"
}

# _qa_retrato <dir> — caminho, tipo, modo, tamanho, mtime e sha256 de tudo.
_qa_retrato() {
  [[ -e $1 ]] || {
    printf 'ausente'
    return 0
  }
  find "$1" -printf '%P|%y|%m|%s|%T@\n' | LC_ALL=C sort
  (cd -- "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

# _qa_retrato_conteudo <dir> — o mesmo sem o mtime (idempotencia de copia).
_qa_retrato_conteudo() {
  find "$1" -printf '%P|%y|%m|%s\n' | LC_ALL=C sort
  (cd -- "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)
}

_qa_tmp_vazio() { # <descricao>
  assert_igual '' "$(find "$BASE/tmp" -mindepth 1 -print -quit)" "$1"
}

# Estado de `lib/state` povoado com memorias sinteticas (do par e alheias).
_qa_estado_povoado() {
  mkdir -p "$BASE/estado/dbx"
  chmod 700 "$BASE/estado/dbx"
  printf 'v2 memoria sintetica do QA\n' >"$BASE/estado/dbx/memoria-qa1"
  printf '{"corrompida' >"$BASE/estado/dbx/memoria-qa2"
  printf 'outro\n' >"$BASE/estado/dbx/upload-cache"
  chmod 600 "$BASE/estado/dbx/"*
  touch -d '@1600000000' "$BASE/estado/dbx/"* "$BASE/estado/dbx"
}

# ===========================================================================
# 1. RF-65 — `verificar` e so leitura
# ===========================================================================

teste_qa_ver_estado_fica_byte_a_byte_igual_presente_ou_ausente() {
  # Com divergencia (11) e com igualdade (0), nos dois sentidos: o diretorio de
  # estado nao muda (mtime incluso) e, ausente, continua ausente.
  _qa_cenario
  printf 'qa um' >"$BASE/local/um.txt"
  printf 'qa dois' >"$BASE/local/dois.txt"
  _qa_listagem "$(_qa_entrada /r/um.txt "$(_qa_hash "$BASE/local/um.txt")")" \
    "$(_qa_entrada /r/tres.txt "$QA_OUTRO_HASH")"
  local antes sentido
  for sentido in enviar receber; do
    rm -rf "$BASE/estado"
    if [[ $sentido == enviar ]]; then
      _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
    else
      _qa_rodar -- verificar --receber --origem /r --destino "$BASE/local"
    fi
    assert_igual "$QA_INTEGRIDADE" "$ESTADO" "$sentido: divergencia sai 11; erro: $ERRO"
    assert_igual 'ausente' "$(_qa_retrato "$BASE/estado")" "$sentido: estado ausente continua ausente"
    _qa_estado_povoado
    antes=$(_qa_retrato "$BASE/estado")
    if [[ $sentido == enviar ]]; then
      _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
    else
      _qa_rodar -- verificar --receber --origem /r --destino "$BASE/local"
    fi
    assert_igual "$QA_INTEGRIDADE" "$ESTADO" "$sentido: com estado, mesmo codigo"
    assert_igual "$antes" "$(_qa_retrato "$BASE/estado")" "$sentido: estado presente byte a byte igual"
    assert_igual 0 "$(_qa_fora_de 'oauth2/token\|files/list_folder')" \
      "$sentido: so renovacao e listagem (lista branca)"
    _qa_tmp_vazio "$sentido: nenhuma area temporaria sobra"
  done
  # Igualdade: memoria presente nao decide e nao e tocada.
  rm -f "$BASE/local/dois.txt"
  _qa_listagem "$(_qa_entrada /r/UM.txt "$(_qa_hash "$BASE/local/um.txt")")"
  antes=$(_qa_retrato "$BASE/estado")
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" "iguais sem caixa saem 0; erro: $ERRO"
  assert_contem 'igual=um.txt' "$SAIDA" 'grafia da origem'
  assert_igual "$antes" "$(_qa_retrato "$BASE/estado")" 'igualdade: estado intacto'
}

teste_qa_ver_caminhos_hostis_recusados_antes_da_api() {
  # `..` que sobe acima da raiz da conta e caminho relativo: recusa antes de
  # qualquer chamada e de qualquer acesso a disco (RF-65(c), mesmas guardas do
  # sync). A raiz `raiz_remota` da credencial nao e aplicada por comando algum
  # (achado preexistente, registrado no parecer); por isso nao e vetor aqui.
  _qa_cenario
  printf 'x' >"$BASE/local/a.txt"
  local remoto
  for remoto in '/r/../../etc' '/../fora' '/r/./../../x' 'relativo/r' './r'; do
    _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino "$remoto"
    assert_diferente 0 "$ESTADO" "remoto hostil [$remoto] nao e aceito"
    assert_diferente "$QA_INTEGRIDADE" "$ESTADO" "remoto hostil [$remoto] nao vira divergencia"
    assert_igual 0 "$(_qa_contar .)" "remoto hostil [$remoto]: nenhuma chamada, nem de token"
    _qa_tmp_vazio "remoto hostil [$remoto]: nenhuma area criada"
    _qa_rodar -- verificar --receber --origem "$remoto" --destino "$BASE/novo"
    assert_diferente 0 "$ESTADO" "receber de remoto hostil [$remoto] nao e aceito"
    assert_igual 0 "$(_qa_contar .)" "receber de [$remoto]: nenhuma chamada"
    assert_arquivo_ausente "$BASE/novo" "receber de [$remoto]: raiz local nao criada"
  done
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino '/r/../../etc'
  assert_igual "$QA_RECUSADO" "$ESTADO" 'travessia remota acima da raiz e caminho_recusado (13)'
}

teste_qa_ver_vinculo_para_fora_nao_vaza_nome_nem_conteudo() {
  _qa_cenario
  mkdir -p "$BASE/fora"
  printf 'segredo de fora' >"$BASE/fora/QAsegredoExterno.txt"
  printf 'dentro' >"$BASE/local/dentro.txt"
  ln -s "$BASE/fora" "$BASE/local/atalho"
  ln -s "$BASE/fora/QAsegredoExterno.txt" "$BASE/local/arquivo-atalho.txt"
  _qa_listagem "$(_qa_entrada /r/dentro.txt "$(_qa_hash "$BASE/local/dentro.txt")")"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_nao_contem 'QAsegredoExterno' "$SAIDA" 'o arquivo de fora nao e listado'
  assert_diferente 0 "$ESTADO" 'arvore com vinculo nao afirma igualdade'
  assert_diferente "$QA_INTEGRIDADE" "$ESTADO" 'travessia que pulou vinculo nao e divergencia completa'
  assert_igual 'segredo de fora' "$(<"$BASE/fora/QAsegredoExterno.txt")" 'o alvo nao e tocado'
}

teste_qa_ver_quebra_de_linha_no_remoto_nao_forja_linha() {
  _qa_cenario
  printf 'qa' >"$BASE/local/a.txt"
  _qa_listagem "$(_qa_entrada /r/a.txt "$(_qa_hash "$BASE/local/a.txt")")" \
    "$(_qa_entrada '/r/x\nigual=forjado.txt' "$QA_OUTRO_HASH")"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_igual "$QA_INTEGRIDADE" "$ESTADO" "so no destino diverge; erro: $ERRO"
  local linha forjada=nao
  while IFS= read -r linha; do
    [[ $linha == 'igual=forjado.txt' ]] && forjada=sim
  done <<<"$SAIDA"
  assert_igual nao "$forjada" 'o nome com quebra de linha nao abre uma linha "igual="'
  assert_contem 'iguais=1' "$SAIDA" 'so um igual'
  assert_contem 'so_destino=1' "$SAIDA" 'o nome hostil e um so_destino'
  _qa_rodar -- --json --null verificar --enviar --origem "$BASE/local" --destino /r
  assert_sucesso grep -qz $'^so_destino=x\nigual=forjado.txt$' "$BASE/out"
}

teste_qa_ver_caixa_decide_por_conteudo_e_colisao_recusa_sem_rede() {
  _qa_cenario
  printf 'relatorio' >"$BASE/local/Relatorio.PDF"
  _qa_listagem "$(_qa_entrada /r/relatorio.pdf "$(_qa_hash "$BASE/local/Relatorio.PDF")")"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" "mesma chave sem caixa e mesmo conteudo: 0; erro: $ERRO"
  assert_contem 'total=1' "$SAIDA" 'listado uma vez so'
  _qa_listagem "$(_qa_entrada /r/relatorio.pdf "$QA_OUTRO_HASH")"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_igual "$QA_INTEGRIDADE" "$ESTADO" 'mesma chave, conteudo outro: 11'
  assert_contem 'diferente=Relatorio.PDF' "$SAIDA" 'diferente pela grafia da origem'
  assert_contem 'diferentes=1' "$SAIDA" 'um diferente'
  printf 'outro' >"$BASE/local/relatorio.pdf"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_diferente 0 "$ESTADO" 'colisao de caixa local e recusada'
  assert_diferente "$QA_INTEGRIDADE" "$ESTADO" 'colisao nao e divergencia'
  assert_igual 0 "$(_qa_contar .)" 'colisao: nenhuma chamada, nem de token'
  _qa_tmp_vazio 'colisao: area removida'
}

teste_qa_ver_erro_de_execucao_prevalece_sobre_divergencia() {
  _qa_cenario
  printf 'qa' >"$BASE/local/so-aqui.txt"
  # Primeira pagina ja diverge; a continuacao falha no transporte.
  printf '{"entries":[%s],"has_more":true,"cursor":"QAC1"}' \
    "$(_qa_entrada /r/so-la.txt "$QA_OUTRO_HASH")" >"$BASE/r_listagem"
  printf '7' >"$BASE/x_continuacao"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_igual "$QA_REDE" "$ESTADO" "rede na continuacao prevalece: 9; erro: $ERRO"
  assert_nao_contem 'divergencia encontrada' "$ERRO" 'nao anuncia divergencia'
  _qa_tmp_vazio 'falha de rede: area removida'
  rm -f "$BASE/x_continuacao"
  # Renovacao recusada: autenticacao, nunca 11.
  printf '400' >"$BASE/c_token"
  printf '{"error":"invalid_grant","error_description":"refresh token is malformed"}' >"$BASE/r_token"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida autenticacao)" "$ESTADO" "renovacao recusada: 5; erro: $ERRO"
  assert_igual 0 "$(_qa_contar list_folder)" 'sem token, nenhuma listagem'
  rm -f "$BASE/c_token"
  printf '{"access_token":"%s","expires_in":14400}' "$QA_S_ACESSO" >"$BASE/r_token"
  # Travessia parcial com divergencia: 14, nunca 11 nem 0.
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada /r/so-la.txt "$QA_OUTRO_HASH")" >"$BASE/r_listagem"
  mkdir -p "$BASE/local/trancado"
  printf 'x' >"$BASE/local/trancado/oculto.txt"
  chmod 000 "$BASE/local/trancado"
  _qa_rodar -- verificar --enviar --origem "$BASE/local" --destino /r
  chmod 700 "$BASE/local/trancado"
  assert_igual "$QA_NAO_CONCLUIDA" "$ESTADO" "parcial com divergencia: 14; erro: $ERRO"
}

teste_qa_ver_opcoes_do_sync_sao_recusadas_sem_nenhum_efeito() {
  _qa_cenario
  printf 'qa' >"$BASE/local/a.txt"
  local opcao comando
  for comando in verificar verify; do
    for opcao in --espelhar --mirror --confirmar --yes --permitir-origem-vazia \
      --allow-empty-source --forcar --force; do
      _qa_rodar -- "$comando" --push --source "$BASE/local" --dest /r "$opcao"
      assert_igual "$QA_USO" "$ESTADO" "$comando $opcao (no fim) e uso invalido"
      assert_igual 0 "$(_qa_contar .)" "$comando $opcao: nenhuma chamada"
      _qa_tmp_vazio "$comando $opcao: nenhuma area"
    done
  done
  _qa_rodar -- verificar --enviar --receber --origem "$BASE/local" --destino /r
  assert_igual "$QA_USO" "$ESTADO" 'dois sentidos: 2'
  _qa_rodar -- --dry-run verify --push --source "$BASE/local" --dest /r
  assert_igual "$QA_INTEGRIDADE" "$ESTADO" "--dry-run e aceito e sem efeito; erro: $ERRO"
  assert_contem 'so_origem=a.txt' "$SAIDA" 'o relatorio sai igual em simulacao'
}

# ===========================================================================
# 2. RF-66 — `diagnostico`
# ===========================================================================

# _qa_bin_sem <utilitario> — publica QA_PATH com todos os utilitarios do
# preflight (por vinculo) menos um, mais o duplo de `curl`.
_qa_bin_sem() {
  local alvo origem dir="$BASE/bin-sem-$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  for alvo in mktemp mv rm chmod mkdir stat head wc readlink dirname find cat sleep tail df \
    sha256sum shasum locale; do
    [[ $alvo == "$1" ]] && continue
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -s "$origem" "$dir/$alvo"
  done
  [[ $1 == curl ]] || ln -s "$BASE/bin/curl" "$dir/curl"
  # sha256sum e shasum sao alternativos: tirar um tira os dois.
  [[ $1 == sha256sum ]] && rm -f "$dir/shasum"
  QA_PATH=$dir
}

teste_qa_dia_cada_utilitario_ausente_um_por_um() {
  # Um por um, pelos dois pontos de entrada: `bin/dbx` direto e o vinculo
  # simbolico que o install.sh cria em ~/.local/bin/dbx. Os desvios sao
  # acumulados e reportados juntos, para a devolucao nomear todos.
  _qa_cenario
  mkdir -p "$BASE/instalado"
  ln -s "$DBX_EXEC" "$BASE/instalado/dbx"
  local utilitario entrada rotulo id desvios=''
  for entrada in "$DBX_EXEC" "$BASE/instalado/dbx"; do
    rotulo=direto
    [[ $entrada == "$DBX_EXEC" ]] || rotulo=vinculo
    for utilitario in curl mktemp mv rm chmod mkdir stat head wc readlink dirname find cat sleep \
      tail df sha256sum; do
      _qa_bin_sem "$utilitario"
      QA_EXEC=$entrada _qa_rodar -- diagnostico
      if [[ $ESTADO != "$QA_CONFIG" || $SAIDA != *dependencias=falha*"$utilitario"* ||
        $ERRO == *'utilitario obrigatorio ausente'* ]]; then
        desvios+="[$rotulo sem $utilitario: saiu $ESTADO, stderr: ${ERRO%%$'\n'*}] "
      else
        for id in credencial conectividade escopos espaco localidade estado; do
          [[ $SAIDA == *"$id="* ]] || desvios+="[$rotulo sem $utilitario: checagem $id sumiu] "
        done
      fi
      QA_EXEC=$entrada _qa_rodar -- info /r/a.txt
      [[ $ESTADO == "$QA_CONFIG" && $(_qa_contar .) == 0 ]] ||
        desvios+="[$rotulo sem $utilitario: info nao foi recusado pelo preflight (saiu $ESTADO)] "
      QA_PATH=''
    done
  done
  assert_igual '' "$desvios" 'diagnostico roda e nomeia cada ausente; info segue recusado (RF-66(a)(e))'
  # O-4 (ciclo 2): sem `stat`, a permissao nao e conferida e vira aviso.
  _qa_bin_sem stat
  _qa_rodar -- diagnostico
  QA_PATH=''
  assert_contem 'credencial=aviso' "$SAIDA" 'sem stat: credencial em aviso, nao em falha'
  assert_contem 'nao conferida' "$SAIDA" 'sem stat: o aviso diz que a permissao nao foi conferida'
  # D-1, limite aceito pelo Tech Lead: pelo vinculo, sem `readlink` E sem
  # `find`, nao ha como achar o alvo; a recusa e explicita (3), nomeia o que
  # instalar e nao vaza erro do bash.
  _qa_bin_sem readlink
  rm -f "$QA_PATH/find"
  QA_EXEC="$BASE/instalado/dbx" _qa_rodar -- diagnostico
  QA_PATH=''
  assert_igual "$QA_CONFIG" "$ESTADO" "vinculo sem readlink e sem find: recusa 3; erro: $ERRO"
  assert_contem 'readlink' "$ERRO" 'a recusa nomeia readlink'
  assert_nao_contem 'command not found' "$ERRO" 'sem erro cru do bash'
  assert_nao_contem 'No such file' "$ERRO" 'sem erro cru do bash'
}

teste_qa_dia_credencial_larga_ausente_ou_corrompida_nao_vaza_nada() {
  _qa_cenario
  local saidas=''
  # 0644: falha com o remedio; o modo nao e corrigido.
  chmod 644 "$BASE/config/dbx/credencial.json"
  _qa_rodar -- --debug diagnostico
  assert_igual "$QA_CONFIG" "$ESTADO" '0644: 3'
  assert_contem 'credencial=falha' "$SAIDA" '0644: falha na credencial'
  assert_contem 'chmod 600' "$SAIDA" '0644: remedio chmod 600'
  assert_igual 644 "$(stat -c '%a' "$BASE/config/dbx/credencial.json")" '0644: o remedio nao e aplicado'
  assert_igual 0 "$(_qa_contar .)" '0644: nada de rede com credencial recusada'
  saidas+="$SAIDA$ERRO"
  # Corrompida, com os sentinelas no texto truncado.
  printf '{"versao":1,"app_key":"%s","app_secret":"%s","refresh_token":"%s' \
    "$QA_S_CHAVE" "$QA_S_SEGREDO" "$QA_S_REFRESH" >"$BASE/config/dbx/credencial.json"
  chmod 600 "$BASE/config/dbx/credencial.json"
  local apresentacao
  for apresentacao in '' --json '--json --null' --debug; do
    # shellcheck disable=SC2086  # apresentacao e lista de opcoes
    _qa_rodar -- $apresentacao diagnostico
    assert_igual "$QA_CONFIG" "$ESTADO" "corrompida [$apresentacao]: 3"
    assert_contem 'credencial' "$SAIDA" "corrompida [$apresentacao]: checagem presente"
    saidas+="$SAIDA$ERRO"
  done
  # Ausente.
  rm -f "$BASE/config/dbx/credencial.json"
  _qa_rodar -- diagnostico
  assert_igual "$QA_CONFIG" "$ESTADO" 'ausente: 3'
  assert_contem 'dbx config' "$SAIDA" 'ausente: remedio dbx config'
  assert_arquivo_ausente "$BASE/config/dbx/credencial.json" 'ausente: nada e criado'
  assert_arquivo_ausente "$BASE/estado" 'nenhum diagnostico cria o estado'
  saidas+="$SAIDA$ERRO"
  local sentinela
  for sentinela in "$QA_S_CHAVE" "$QA_S_SEGREDO" "$QA_S_REFRESH" "$QA_S_ACESSO"; do
    assert_segredo_ausente "$sentinela" "$saidas" 'nenhum sentinela em saida alguma'
  done
}

teste_qa_dia_falha_de_rede_que_ecoa_segredos_nao_vaza() {
  _qa_cenario
  local saidas='' apresentacao
  # Renovacao recusada com corpo que ecoa os tres valores da credencial.
  printf '400' >"$BASE/c_token"
  printf '{"error":"invalid_client","error_description":"%s %s %s"}' \
    "$QA_S_CHAVE" "$QA_S_SEGREDO" "$QA_S_REFRESH" >"$BASE/r_token"
  for apresentacao in '' --json '--json --null' --debug '--debug --json'; do
    # shellcheck disable=SC2086  # apresentacao e lista de opcoes
    _qa_rodar -- $apresentacao diagnostico
    assert_igual "$QA_CONFIG" "$ESTADO" "renovacao recusada [$apresentacao]: 3"
    assert_contem 'conectividade' "$SAIDA" "renovacao recusada [$apresentacao]: checagem presente"
    saidas+="$SAIDA$ERRO"
  done
  # Renovacao ok, check/user recusa ecoando o token de acesso e a chave.
  rm -f "$BASE/c_token"
  printf '{"access_token":"%s","expires_in":14400,"scope":"account_info.read files.metadata.read files.content.read files.content.write"}' \
    "$QA_S_ACESSO" >"$BASE/r_token"
  printf '401' >"$BASE/c_check"
  printf '{"error_summary":"invalid_access_token/%s/%s"}' "$QA_S_ACESSO" "$QA_S_CHAVE" >"$BASE/r_check"
  for apresentacao in '' --json --debug; do
    # shellcheck disable=SC2086  # apresentacao e lista de opcoes
    _qa_rodar -- $apresentacao diagnostico
    assert_igual "$QA_CONFIG" "$ESTADO" "check/user recusado [$apresentacao]: 3"
    assert_contem 'conectividade=falha' "$SAIDA" "check/user recusado [$apresentacao]: falha"
    assert_igual 0 "$(_qa_fora_de 'oauth2/token\|check/user\|get_space_usage')" \
      "check/user recusado [$apresentacao]: so os tres endpoints de leitura"
    saidas+="$SAIDA$ERRO"
  done
  local sentinela
  for sentinela in "$QA_S_CHAVE" "$QA_S_SEGREDO" "$QA_S_REFRESH" "$QA_S_ACESSO" 'QAb1acessoTok_a5'; do
    assert_segredo_ausente "$sentinela" "$saidas" 'nenhum sentinela, inclusive em falha'
  done
}

# ===========================================================================
# 3. RF-67 — checagem previa de espaco
# ===========================================================================

teste_qa_esp_upload_cabe_exatamente_e_falta_um_byte() {
  _qa_cenario
  _qa_espaco 1234 2234 # livre 1000
  _qa_bytes "$BASE/local/falta.bin" 1001
  _qa_rodar -- upload "$BASE/local/falta.bin" /r/falta.bin
  assert_igual "$QA_ESPACO" "$ESTADO" 'falta 1 byte: 12'
  assert_igual 0 "$(_qa_escritas)" 'recusa: nenhuma escrita, nem sessao'
  assert_igual 1 "$(_qa_contar get_space_usage)" 'uma consulta'
  assert_contem '1001' "$ERRO" 'nomeia o necessario'
  assert_contem '1000' "$ERRO" 'nomeia a folga'
  assert_arquivo_ausente "$BASE/estado" 'recusa: nem a memoria do upload'
  _qa_bytes "$BASE/local/cabe.bin" 1000
  _qa_rodar -- upload "$BASE/local/cabe.bin" /r/cabe.bin
  assert_igual 0 "$ESTADO" "livre = necessario cabe; erro: $ERRO"
  assert_igual 1 "$(_qa_contar 'files/upload')" 'o envio sai'
}

teste_qa_esp_sync_cabe_exatamente_e_falta_um_byte_sem_memoria() {
  _qa_cenario
  _qa_espaco 77 1077 # livre 1000
  _qa_bytes "$BASE/local/a.bin" 400
  _qa_bytes "$BASE/local/b.bin" 601
  _qa_rodar -- sync --enviar --origem "$BASE/local" --destino /r
  assert_igual "$QA_ESPACO" "$ESTADO" '1001 em 1000: 12'
  assert_igual 0 "$(_qa_escritas)" 'nenhuma escrita'
  assert_arquivo_ausente "$BASE/estado" 'nenhuma memoria gravada'
  _qa_tmp_vazio 'recusa: area do sync removida'
  _qa_bytes "$BASE/local/b.bin" 600
  _qa_rodar -- sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" "1000 em 1000 cabe; erro: $ERRO"
  assert_igual 2 "$(_qa_contar 'files/upload')" 'os dois envios saem'
  assert_igual 1 "$(_qa_contar get_space_usage)" 'uma unica consulta para os dois'
}

teste_qa_esp_sobrescrita_conta_o_arquivo_inteiro_no_upload_e_no_sync() {
  _qa_cenario
  _qa_espaco 900 1100 # livre 200
  _qa_bytes "$BASE/local/a.bin" 300
  # Remoto com 900 bytes de outro conteudo: abater o antigo daria folga.
  printf '200' >"$BASE/c_metadata"
  printf '{".tag":"file","name":"a.bin","path_display":"/r/a.bin","content_hash":"%s","size":900,"rev":"0qa"}' \
    "$QA_OUTRO_HASH" >"$BASE/r_metadata"
  _qa_rodar -- upload --mode overwrite "$BASE/local/a.bin" /r/a.bin
  assert_igual "$QA_ESPACO" "$ESTADO" "upload: sobrescrita de 300 em folga 200 e recusada; erro: $ERRO"
  assert_igual 0 "$(_qa_escritas)" 'upload: nenhuma escrita'
  _qa_listagem "$(_qa_entrada /r/a.bin "$QA_OUTRO_HASH" 900)"
  _qa_rodar -- sync --enviar --origem "$BASE/local" --destino /r
  assert_igual "$QA_ESPACO" "$ESTADO" 'sync: sobrescrita conta o arquivo inteiro'
  assert_contem 'faltam 100' "$ERRO" 'a diferenca e 300 - 200'
}

teste_qa_esp_forcar_pula_e_forcar_com_receber_e_recusado() {
  _qa_cenario
  _qa_espaco 1000 1000 # livre 0
  _qa_bytes "$BASE/local/a.bin" 50
  local opcao
  for opcao in --forcar --force; do
    _qa_rodar -- upload "$opcao" "$BASE/local/a.bin" /r/a.bin
    assert_igual 0 "$ESTADO" "upload $opcao envia sem folga; erro: $ERRO"
    assert_igual 0 "$(_qa_contar get_space_usage)" "upload $opcao: zero consultas"
    _qa_rodar -- sync "$opcao" --push --source "$BASE/local" --dest /r
    assert_igual 0 "$ESTADO" "sync $opcao envia sem folga; erro: $ERRO"
    assert_igual 0 "$(_qa_contar get_space_usage)" "sync $opcao: zero consultas"
    _qa_rodar -- sync --receber --origem /r --destino "$BASE/recebe" "$opcao"
    assert_igual "$QA_USO" "$ESTADO" "$opcao com --receber: 2"
    assert_igual 0 "$(_qa_contar .)" "$opcao com --receber: nenhuma chamada"
    assert_arquivo_ausente "$BASE/recebe" "$opcao com --receber: nada criado"
    _qa_rodar -- sync "$opcao" --pull --source /r --dest "$BASE/recebe"
    assert_igual "$QA_USO" "$ESTADO" "$opcao antes de --pull: 2"
  done
  _qa_rodar -- upload "$BASE/local/a.bin" /r/b.bin
  assert_igual "$QA_ESPACO" "$ESTADO" 'sem --forcar, a mesma conta recusa'
}

teste_qa_esp_simulacao_so_avisa_e_nao_escreve() {
  _qa_cenario
  _qa_espaco 10 100 # livre 90
  _qa_bytes "$BASE/local/a.bin" 91
  # Simulacao proibe ESCRITA; as leituras sao um conjunto fechado, com
  # contagem exata (decisao do Tech Lead na O-3: `get_metadata` antes do
  # espaco, na ordem da execucao real). Remoto ausente (409): consulta.
  _qa_rodar -- --dry-run upload "$BASE/local/a.bin" /r/a.bin
  assert_igual 0 "$ESTADO" "upload simulado sai 0; erro: $ERRO"
  assert_contem 'recusaria' "$SAIDA$ERRO" 'upload simulado anuncia a recusa'
  assert_igual 0 "$(_qa_escritas)" 'upload simulado: nenhuma escrita'
  assert_igual 1 "$(_qa_contar oauth2/token)" 'upload simulado: uma renovacao'
  assert_igual 1 "$(_qa_contar files/get_metadata)" 'upload simulado: uma leitura do hash remoto'
  assert_igual 1 "$(_qa_contar get_space_usage)" 'upload simulado: uma consulta de espaco'
  assert_igual 3 "$(_qa_contar .)" 'upload simulado: nenhuma outra chamada'
  # O-3: remoto com conteudo DIFERENTE: mesma consulta e o anuncio "recusaria".
  printf '200' >"$BASE/c_metadata"
  printf '{".tag":"file","name":"a.bin","path_display":"/r/a.bin","content_hash":"%s","size":91,"rev":"0qa"}' \
    "$QA_OUTRO_HASH" >"$BASE/r_metadata"
  _qa_rodar -- --dry-run upload "$BASE/local/a.bin" /r/a.bin
  assert_igual 0 "$ESTADO" "hash diferente: 0; erro: $ERRO"
  assert_contem 'recusaria' "$SAIDA$ERRO" 'hash diferente: anuncia a recusa'
  assert_igual 1 "$(_qa_contar get_space_usage)" 'hash diferente: consulta o espaco'
  assert_igual 3 "$(_qa_contar .)" 'hash diferente: as mesmas tres leituras'
  # O-3: remoto IDENTICO: dispensado, sem consulta de espaco e sem "recusaria".
  printf '{".tag":"file","name":"a.bin","path_display":"/r/a.bin","content_hash":"%s","size":91,"rev":"0qa"}' \
    "$(_qa_hash "$BASE/local/a.bin")" >"$BASE/r_metadata"
  _qa_rodar -- --dry-run upload "$BASE/local/a.bin" /r/a.bin
  assert_igual 0 "$ESTADO" "hash igual: 0; erro: $ERRO"
  assert_contem 'dispensado' "$SAIDA" 'hash igual: dispensado, como na execucao real'
  assert_nao_contem 'recusaria' "$SAIDA$ERRO" 'hash igual: nao anuncia recusa do que seria dispensado'
  assert_igual 0 "$(_qa_contar get_space_usage)" 'hash igual: sem consulta de espaco'
  assert_igual 0 "$(_qa_escritas)" 'hash igual: nenhuma escrita'
  assert_arquivo_ausente "$BASE/estado" 'hash igual: simulacao nao grava o cache do upload'
  rm -f "$BASE/c_metadata" "$BASE/r_metadata"
  printf '409' >"$BASE/c_metadata"
  printf '%s' '{"error_summary":"path/not_found/.."}' >"$BASE/r_metadata"
  _qa_rodar -- --dry-run sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" "sync simulado sai 0; erro: $ERRO"
  assert_contem 'recusaria' "$SAIDA$ERRO" 'sync simulado anuncia a recusa'
  assert_igual 0 "$(_qa_escritas)" 'sync simulado: nenhuma escrita'
  assert_arquivo_ausente "$BASE/estado" 'simulacao nao grava memoria'
  _qa_espaco 0 1000
  _qa_rodar -- --dry-run sync --enviar --origem "$BASE/local" --destino /r
  assert_igual 0 "$ESTADO" 'cabe: 0'
  assert_nao_contem 'recusaria' "$SAIDA$ERRO" 'cabe: sem aviso de recusa'
}

teste_qa_esp_consulta_que_falha_so_avisa_uma_vez() {
  local modo
  for modo in transporte 500 lixo sem_alocacao; do
    _qa_cenario
    _qa_bytes "$BASE/local/a.bin" 10
    _qa_bytes "$BASE/local/b.bin" 10
    case $modo in
      transporte) printf '7' >"$BASE/x_espaco" ;;
      500) printf '500' >"$BASE/c_espaco" && printf '{"error_summary":"internal"}' >"$BASE/r_espaco" ;;
      lixo) printf 'nao e json {' >"$BASE/r_espaco" ;;
      sem_alocacao) printf '{"used":5,"allocation":{".tag":"other"}}' >"$BASE/r_espaco" ;;
    esac
    _qa_rodar -- sync --enviar --origem "$BASE/local" --destino /r
    assert_igual 0 "$ESTADO" "$modo: o envio segue; erro: $ERRO"
    assert_igual 2 "$(_qa_contar 'files/upload')" "$modo: os dois arquivos saem"
    assert_igual 1 "$(_qa_contar get_space_usage)" "$modo: uma consulta"
    local avisos=0 linha
    while IFS= read -r linha; do
      [[ $linha == *espaco* || $linha == *alocacao* ]] && avisos=$((avisos + 1))
    done <<<"$ERRO"
    assert_igual 1 "$avisos" "$modo: um unico aviso em stderr"
    _qa_rodar -- upload "$BASE/local/a.bin" /r/c.bin
    assert_igual 0 "$ESTADO" "$modo: upload segue; erro: $ERRO"
  done
}

teste_qa_esp_entrada_padrao_nao_consulta() {
  _qa_cenario
  _qa_espaco 100 100 # livre 0
  printf 'fluxo do QA' >"$BASE/entrada"
  rm -f "$BASE/chamadas"
  env -i PATH="$BASE/bin:$PATH" HOME="$BASE" XDG_CONFIG_HOME="$BASE/config" \
    XDG_STATE_HOME="$BASE/estado" TMPDIR="$BASE/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=1 \
    "$BASH_ABSOLUTO" "$DBX_EXEC" upload - /r/fluxo.txt <"$BASE/entrada" >"$BASE/out" 2>"$BASE/err"
  assert_igual 0 "$?" "upload - sem folga segue: $(<"$BASE/err")"
  assert_igual 0 "$(_qa_contar get_space_usage)" 'upload -: nenhuma consulta'
}

teste_qa_esp_ordem_em_relacao_as_guardas_do_sync() {
  _qa_cenario
  _qa_espaco 1000 1000 # livre 0
  _qa_bytes "$BASE/local/a.bin" 10
  _qa_listagem "$(_qa_entrada /r/sobra.bin "$QA_OUTRO_HASH" 5)"
  # RF-48: primeira execucao com --espelhar sem --confirmar vem antes.
  _qa_rodar -- sync --enviar --espelhar --origem "$BASE/local" --destino /r
  assert_diferente 0 "$ESTADO" 'RF-48 recusa'
  assert_diferente "$QA_ESPACO" "$ESTADO" 'RF-48 prevalece sobre a falta de espaco'
  assert_igual 0 "$(_qa_contar get_space_usage)" 'RF-48: espaco nem consultado'
  assert_igual 0 "$(_qa_escritas)" 'RF-48: nenhuma escrita'
  # RF-41(b): origem vazia com algo a apagar recusa como 14, nao 12.
  mkdir -p "$BASE/vazia"
  _qa_rodar -- sync --enviar --espelhar --confirmar --origem "$BASE/vazia" --destino /r
  assert_igual "$QA_NAO_CONCLUIDA" "$ESTADO" 'origem vazia: 14'
  assert_igual 0 "$(_qa_escritas)" 'origem vazia: nenhuma escrita'
  # Com reconhecimento, sem folga: 12, sem exclusao do espelho.
  _qa_rodar -- sync --enviar --espelhar --confirmar --origem "$BASE/local" --destino /r
  assert_igual "$QA_ESPACO" "$ESTADO" "espelho sem folga: 12; erro: $ERRO"
  assert_igual 0 "$(_qa_contar 'files/delete')" 'nenhuma exclusao do --espelhar'
  assert_igual 0 "$(_qa_escritas)" 'nenhuma escrita'
  assert_arquivo_ausente "$BASE/estado/dbx" 'nenhuma memoria'
}

# ===========================================================================
# 4. RF-68 — autocompletar
# ===========================================================================

# _qa_completar <PATH> <palavras...> — roda a funcao de completar num bash
# limpo, com o cursor na ultima palavra; uma sugestao por linha.
_qa_completar() {
  local caminho=$1
  shift
  env -i PATH="$caminho" HOME="$BASE" "$BASH_ABSOLUTO" --norc --noprofile -c '
    source "$1"; shift
    COMP_WORDS=("$@"); COMP_CWORD=$(($# - 1))
    _dbx_completar
    printf "%s\n" "${COMPREPLY[@]}"' _ "$DBX_HARNESS_RAIZ/completions/dbx.bash" "$@"
}

teste_qa_cpl_funciona_sem_curl_e_sem_rede() {
  _qa_cenario
  mkdir -p "$BASE/vazio"
  local sugestoes
  sugestoes=$(_qa_completar "$BASE/vazio" dbx ve)
  assert_contem 'verificar' "$sugestoes" 'comando sem nenhum utilitario no PATH'
  assert_contem 'verify' "$sugestoes" 'alias sem nenhum utilitario no PATH'
  sugestoes=$(_qa_completar "$BASE/vazio" dbx sync --perm)
  assert_igual '--permitir-origem-vazia' "$sugestoes" 'opcao sem nenhum utilitario'
  # `dbx completar bash` com o duplo de curl no PATH: zero invocacoes.
  _qa_rodar -- completar bash
  assert_igual 0 "$ESTADO" "completar bash: 0; erro: $ERRO"
  assert_arquivo_ausente "$BASE/chamadas" 'completar bash nao invoca curl'
  _qa_bin_sem curl
  _qa_rodar -- completion bash
  QA_PATH=''
  assert_igual 0 "$ESTADO" "completion bash sem curl no PATH: 0; erro: $ERRO"
  assert_sucesso cmp -s "$BASE/out" "$DBX_HARNESS_RAIZ/completions/dbx.bash"
  rm -f "$BASE/config/dbx/credencial.json"
  _qa_rodar -- completar bash
  assert_igual 0 "$ESTADO" 'sem credencial: 0'
  assert_sucesso cmp -s "$BASE/out" "$DBX_HARNESS_RAIZ/completions/dbx.bash"
  _qa_rodar -- completar fish
  assert_igual "$QA_USO" "$ESTADO" 'outro shell: 2'
  _qa_rodar -- completar bash bash
  assert_igual "$QA_USO" "$ESTADO" 'dois argumentos: 2'
}

# _qa_opcoes_da_ajuda <comando> — as opcoes do bloco de opcoes da ajuda, uma
# por linha e ordenadas: so as palavras iniciais da linha que comecam com `-`.
_qa_opcoes_da_ajuda() {
  local linha palavra dentro=nao
  local -a palavras
  "$BASH_ABSOLUTO" "$DBX_EXEC" help "$1" 2>/dev/null | while IFS= read -r linha; do
    if [[ $linha =~ ^\ \ +- ]]; then
      dentro=sim
      read -r -a palavras <<<"$linha"
      for palavra in "${palavras[@]}"; do
        palavra=${palavra%,}
        case $palavra in
          -*) printf '%s\n' "$palavra" ;;
          '<'*) ;;
          *) break ;;
        esac
      done
    elif [[ $dentro == sim && -z $linha ]]; then
      break
    fi
  done | LC_ALL=C sort -u
}

teste_qa_cpl_opcoes_do_script_batem_com_a_ajuda() {
  _qa_cenario
  local comando ajuda script
  for comando in upload download list delete info space config unlink sync verificar \
    diagnostico completar; do
    ajuda=$(_qa_opcoes_da_ajuda "$comando")
    script=$(_qa_completar "$PATH" dbx "$comando" - | LC_ALL=C sort -u)
    assert_igual "$ajuda" "$script" "$comando: opcoes da ajuda = opcoes completadas"
  done
  local globais
  globais=$("$BASH_ABSOLUTO" "$DBX_EXEC" help | sed -n 's/^Opcoes globais: //p' | tr ' ' '\n' | LC_ALL=C sort -u)
  assert_igual "$globais" "$(_qa_completar "$PATH" dbx - | LC_ALL=C sort -u)" 'opcoes globais'
  # Aliases resolvem para o mesmo conjunto.
  assert_igual "$(_qa_completar "$PATH" dbx verificar - | LC_ALL=C sort)" \
    "$(_qa_completar "$PATH" dbx verify - | LC_ALL=C sort)" 'verify = verificar'
  # --raiz do config e remota: nenhuma sugestao de caminho local.
  : >"$BASE/local/raiz-local-qa"
  assert_igual '' "$(cd "$BASE/local" && _qa_completar "$PATH" dbx config --raiz raiz)" \
    '--raiz nao completa caminho local'
}

teste_qa_cpl_install_idempotente_sem_sudo_e_uninstall_remove() {
  _qa_cenario
  local casa="$BASE/casa" alvo
  mkdir -p "$casa" "$BASE/falsos"
  printf '# bashrc do QA\n' >"$casa/.bashrc"
  printf '# profile do QA\n' >"$casa/.profile"
  local bashrc_antes profile_antes
  bashrc_antes=$(sha256sum <"$casa/.bashrc")
  profile_antes=$(sha256sum <"$casa/.profile")
  printf '#!%s\nprintf "%%s\\n" "$*" >>%q\nexit 1\n' "$BASH_ABSOLUTO" "$BASE/sudo.log" >"$BASE/falsos/sudo"
  chmod +x "$BASE/falsos/sudo"
  alvo="$casa/.local/share/bash-completion/completions/dbx"
  local primeira
  for _ in 1 2; do
    env -i PATH="$BASE/falsos:$PATH" HOME="$casa" TERM=dumb \
      "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/install.sh" --user </dev/null >"$BASE/out" 2>&1
    assert_igual 0 "$?" "install.sh --user conclui: $(<"$BASE/out")"
    assert_sucesso cmp -s "$alvo" "$DBX_HARNESS_RAIZ/completions/dbx.bash"
    assert_igual 644 "$(stat -c '%a' "$alvo")" 'modo 0644'
    [[ -z ${primeira:-} ]] && primeira=$(_qa_retrato_conteudo "$casa/.local/share/bash-completion")
  done
  assert_igual "$primeira" "$(_qa_retrato_conteudo "$casa/.local/share/bash-completion")" \
    'rodar duas vezes nao muda o resultado (modo, tamanho e conteudo)'
  assert_arquivo_ausente "$BASE/sudo.log" 'nenhuma invocacao de sudo'
  assert_igual "$bashrc_antes" "$(sha256sum <"$casa/.bashrc")" '.bashrc intacto'
  assert_igual "$profile_antes" "$(sha256sum <"$casa/.profile")" '.profile intacto'
  # O dbx instalado imprime o mesmo script.
  env -i PATH="$BASE/falsos:$PATH" HOME="$casa" "$BASH_ABSOLUTO" "$casa/.local/bin/dbx" completar bash \
    >"$BASE/out" 2>"$BASE/err"
  assert_igual 0 "$?" "dbx instalado: completar bash; erro: $(<"$BASE/err")"
  assert_sucesso cmp -s "$BASE/out" "$DBX_HARNESS_RAIZ/completions/dbx.bash"
  # Desinstalacao: so o arquivo do dbx sai; o vizinho de outro programa fica.
  printf 'complete -F _outro outro\n' >"${alvo%/dbx}/outro"
  env -i PATH="$BASE/falsos:$PATH" HOME="$casa" TERM=dumb \
    "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/uninstall.sh" --user </dev/null >"$BASE/out" 2>&1
  assert_igual 0 "$?" "uninstall.sh conclui: $(<"$BASE/out")"
  assert_arquivo_ausente "$alvo" 'uninstall.sh remove o autocompletar'
  assert_arquivo_existe "${alvo%/dbx}/outro" 'uninstall.sh preserva o vizinho'
  env -i PATH="$BASE/falsos:$PATH" HOME="$casa" TERM=dumb \
    "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/install.sh" --user </dev/null >"$BASE/out" 2>&1
  env -i PATH="$BASE/falsos:$PATH" HOME="$casa" TERM=dumb \
    "$BASH_ABSOLUTO" "$DBX_HARNESS_RAIZ/install.sh" --uninstall </dev/null >"$BASE/out" 2>&1
  assert_arquivo_ausente "$alvo" 'install.sh --uninstall remove o autocompletar'
  assert_arquivo_existe "${alvo%/dbx}/outro" 'install.sh --uninstall preserva o vizinho'
  assert_arquivo_ausente "$BASE/sudo.log" 'nenhuma invocacao de sudo no ciclo inteiro'
  assert_igual "$bashrc_antes" "$(sha256sum <"$casa/.bashrc")" '.bashrc intacto no fim'
}

harness_executar "$@"
