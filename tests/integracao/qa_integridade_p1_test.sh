#!/usr/bin/env bash
# Suite independente do QA Expert para a fase P1 de integridade de dados
# (RF-49, RF-54, RF-55, RF-56, RF-57, RNF-29, RNF-04 emendado).
#
# Independente da suite do Senior Developer: duplo de rede proprio, area
# temporaria (`TMPDIR`) propria por cenario para contar residuos, e cenarios de
# borda que a suite de desenvolvimento nao exercita — caixa em subdiretorio,
# `rev` casado por chave sem caixa, teto de sessao exato, umask 027, alvo
# somente leitura, nomes parecidos com o temporario de recebimento, vinculo
# simbolico no destino de pasta e residuo em `TMPDIR` apos reemissao
# diagnostica e apos sinal.
#
# shellcheck disable=SC2016
# Justificativa: o substituto de `curl` e escrito sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly QA_TETO=157286400 # 150 MiB, teto da requisicao unica
readonly QA_ZERADO=0000000000000000000000000000000000000000000000000000000000000000

# _qa_cenario — credencial, duplo de `curl` e arvore local; TMPDIR proprio.
#
# Controles do duplo, por arquivo em $base:
#   listagem             corpo do list_folder
#   conteudo_remoto      corpo do download
#   resultado_cabecalho  Dropbox-API-Result do download
#   download_409         download responde 409 com o corpo do arquivo
#   sinal                escreve bytes parciais no download e envia TERM ao grupo
# O duplo honra `--fail` como o cliente real: 4xx sem corpo e saida 22.
_qa_cenario() {
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/qa-p1.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local" "$base/tmp"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\n' "$base"
    printf 'conf=$(cat 2>/dev/null)\n'
    printf 'printf "%%s\\n" "$conf" >>"$base/opcoes"\n'
    printf 'saida=""; escrever=""; anterior=""; url=""; cabecalhos=""; fail=nao\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; --fail) fail=sim ;; esac\n'
    printf '  anterior=$arg\n'
    printf 'done\n'
    printf 'printf "%%s\\n" "$url" >>"$base/chamadas"\n'
    printf 'codigo=200\n'
    printf 'case $url in\n'
    printf '  *oauth2/token*) corpo=%s ;;\n' "'{\"access_token\":\"sl.t\",\"expires_in\":14400}'"
    printf '  *get_current_account*) corpo=%s ;;\n' "'{\"account_id\":\"dbid:CONTA\"}'"
    printf '  *list_folder*) corpo=$(cat "$base/listagem") ;;\n'
    printf '  *files/download*) corpo=$(cat "$base/conteudo_remoto") ;;\n'
    printf '  *upload_session/start*) corpo=%s ;;\n' "'{\"session_id\":\"S-1\"}'"
    printf '  *upload_session/append_v2*) corpo=%s ;;\n' "'{}'"
    printf '  *) corpo=%s ;;\n' "'{\"name\":\"x\",\"rev\":\"1\"}'"
    printf 'esac\n'
    printf 'if [[ $url == *files/download* && -f "$base/download_409" ]]; then\n'
    printf '  codigo=409; corpo=$(cat "$base/download_409")\n'
    printf 'fi\n'
    printf 'if [[ $url == *files/download* && -n $cabecalhos && -f "$base/resultado_cabecalho" ]]; then\n'
    printf '  printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"\n'
    printf 'fi\n'
    printf 'if [[ $url == *files/download* && -f "$base/sinal" ]]; then\n'
    printf '  [[ -n $saida ]] && printf "%%s" "${corpo:0:3}" >"$saida"\n'
    printf '  kill -TERM 0\n'
    printf '  sleep 5\n'
    printf 'fi\n'
    printf 'if [[ $fail == sim && $codigo -ge 400 ]]; then\n'
    printf '  [[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf '  exit 22\n'
    printf 'fi\n'
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  printf '%s' "$base"
}

_qa_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_rodar_em_sessao() { # <base> <argumentos...> — o duplo pode sinalizar o grupo
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_qa_residuos_http() { # <base> — areas HTTP (com token) remanescentes em TMPDIR
  find "$1/tmp" -mindepth 1 -maxdepth 1 -name 'dbx-http*' | wc -l
}

_qa_partes() { # <diretorio> — temporarios de recebimento remanescentes
  find "$1" -name '*.dbx-part.*' | wc -l
}

_qa_entrada() { # <caminho> <hash> <tamanho> [rev]
  if [[ -n ${4:-} ]]; then
    printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s,"rev":"%s"}' \
      "$1" "$2" "$3" "$4"
  else
    printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s}' "$1" "$2" "$3"
  fi
}

_qa_resumo() { # <arquivo>
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$1'"
}

_qa_args_de_envio() { # <base> <trecho_do_caminho> — Dropbox-API-Arg do envio
  grep 'Dropbox-API-Arg' "$1/opcoes" | grep -F -- "$2" || :
}

# ---------------------------------------------------------------------------
# RF-54 — caixa de caminho no sync
# ---------------------------------------------------------------------------

teste_qa_colisao_de_caixa_em_subdiretorio_e_recusada() {
  # So a caixa do diretorio E do nome difere: `Docs/a.txt` x `docs/A.TXT`.
  local base modo
  base=$(_qa_cenario)
  mkdir -p "$base/local/Docs" "$base/local/docs"
  printf 'um' >"$base/local/Docs/a.txt"
  printf 'dois' >"$base/local/docs/A.TXT"
  for modo in --dry-run --json; do
    : >"$base/chamadas"
    _qa_rodar "$base" --json "$modo" sync --enviar --origem "$base/local" --destino /r
    assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" "colisao em subdiretorio ($modo)"
    assert_contem 'Docs/a.txt' "$DBX_ERRO" 'o diagnostico nomeia o primeiro caminho'
    assert_contem 'docs/A.TXT' "$DBX_ERRO" 'o diagnostico nomeia o segundo caminho'
    assert_igual 0 "$(_harness_contar 'files/upload\|delete_v2\|upload_session' "$base/chamadas")" \
      'nenhuma escrita remota'
  done
}

teste_qa_pastas_irmas_sem_colisao_de_arquivo_nao_sao_recusadas() {
  # `Docs/a.txt` e `docs/b.txt` viram uma pasta so na Dropbox, mas nenhum
  # arquivo colide: recusar aqui seria falso positivo.
  local base
  base=$(_qa_cenario)
  mkdir -p "$base/local/Docs" "$base/local/docs"
  printf 'a' >"$base/local/Docs/a.txt"
  printf 'b' >"$base/local/docs/b.txt"
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sem colisao de arquivo o sync conclui; diagnostico: $DBX_ERRO"
  assert_contem 'enviados=2' "$DBX_SAIDA" 'os dois arquivos sao enviados'
}

teste_qa_espelhar_enviar_com_pasta_de_caixa_diferente_apaga_so_o_ausente() {
  local base
  base=$(_qa_cenario)
  mkdir -p "$base/local/Pasta"
  printf 'novo' >"$base/local/Pasta/x.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_qa_entrada '/r/pasta/x.txt' "$QA_ZERADO" 4 Rx)" \
    "$(_qa_entrada '/r/pasta/y.txt' "$QA_ZERADO" 4 Ry)" >"$base/listagem"
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'a_apagar=1' "$DBX_SAIDA" 'so o ausente na origem entra na exclusao'
  assert_contem 'apagar=pasta/y.txt' "$DBX_SAIDA" 'o ausente e apagado'
  assert_nao_contem 'apagar=pasta/x.txt' "$DBX_SAIDA" 'o par com caixa diferente nao e apagado'
  assert_igual 1 "$(_harness_contar 'delete_v2' "$base/chamadas")" 'uma unica exclusao emitida'
  assert_contem '\"update\":\"Rx\"' "$(_qa_args_de_envio "$base" '/r/pasta/x.txt')" \
    'a escrita usa a grafia remota e o rev dela'
}

teste_qa_rev_e_casado_pela_chave_sem_caixa() {
  # RF-49 x RF-54: local `X.TXT`, remoto `/r/x.txt` com rev. Se o rev fosse
  # procurado pela grafia local, o envio iria em `add` e falharia no servico
  # real como conflito permanente a cada execucao.
  local base args
  base=$(_qa_cenario)
  printf 'novo' >"$base/local/X.TXT"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_qa_entrada '/r/x.txt' "$QA_ZERADO" 4 0a1b2c)" >"$base/listagem"
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  args=$(_qa_args_de_envio "$base" '/r/x.txt')
  assert_contem '\"update\":\"0a1b2c\"' "$args" 'o rev da listagem viaja pela chave sem caixa'
  assert_nao_contem '\"mode\":\"add\"' "$args" 'arquivo existente nunca vai em add'
}

teste_qa_rev_ausente_na_listagem_nunca_vira_sobrescrita_cega() {
  local base args
  base=$(_qa_cenario)
  printf 'novo' >"$base/local/a.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada '/r/a.txt' "$QA_ZERADO" 4)" >"$base/listagem"
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  args=$(_qa_args_de_envio "$base" '/r/a.txt')
  assert_contem 'Dropbox-API-Arg' "$args" 'houve tentativa de envio'
  assert_nao_contem 'overwrite' "$args" 'sem rev o envio nao sobrescreve as cegas'
  assert_contem '\"autorename\":false' "$args" 'nem renomeia em silencio'
}

teste_qa_espelhar_receber_identico_com_caixa_diferente_nada_faz() {
  local base resumo
  base=$(_qa_cenario)
  mkdir -p "$base/local/Sub"
  printf 'igual' >"$base/local/Sub/A.txt"
  resumo=$(_qa_resumo "$base/local/Sub/A.txt")
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada '/r/sub/a.txt' "$resumo" 5)" >"$base/listagem"
  _qa_rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'identicos=1' "$DBX_SAIDA" 'o par e o mesmo arquivo'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'nada e apagado no local'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" 'nenhum recebimento'
  assert_igual 'igual' "$(cat "$base/local/Sub/A.txt")" 'o arquivo local fica intacto'
}

# ---------------------------------------------------------------------------
# RF-57 — teto de sessao, fronteira exata
# ---------------------------------------------------------------------------

teste_qa_sync_arquivo_exatamente_no_teto_vai_por_requisicao_unica() {
  local base
  base=$(_qa_cenario)
  dd if=/dev/null of="$base/local/teto.bin" bs=1 seek="$QA_TETO" 2>/dev/null ||
    pular 'nao foi possivel criar arquivo esparso'
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/chamadas")" '150 MiB cabem numa requisicao'
  assert_igual 0 "$(_harness_contar 'upload_session' "$base/chamadas")" 'sem sessao no teto exato'
}

teste_qa_upload_de_diretorio_acima_do_teto_vai_por_sessao() {
  # RF-57(a): "o mesmo vale para upload <diretorio>" — sem caso proprio na suite
  # de desenvolvimento.
  local base
  base=$(_qa_cenario)
  dd if=/dev/null of="$base/local/grande.bin" bs=1 seek=$((QA_TETO + 1)) 2>/dev/null ||
    pular 'nao foi possivel criar arquivo esparso'
  _qa_rodar "$base" upload "$base/local" /r
  assert_igual 0 "$DBX_ESTADO" "upload de diretorio deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_harness_contar 'files/upload$' "$base/chamadas")" 'nenhuma requisicao unica acima do teto'
  assert_igual 1 "$(_harness_contar 'upload_session/finish' "$base/chamadas")" 'uma sessao concluida'
  assert_contem 'client_modified' "$(_qa_args_de_envio "$base" 'grande.bin')" \
    'o finish da sessao leva client_modified'
}

# ---------------------------------------------------------------------------
# RF-55 — recebimento atomico
# ---------------------------------------------------------------------------

teste_qa_sync_receber_hash_divergente_em_arquivo_novo_nao_cria_nada() {
  local base
  base=$(_qa_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada '/r/novo/a.txt' ff 15)" >"$base/listagem"
  printf '{"name":"a.txt","content_hash":"%s"}' "$QA_ZERADO" >"$base/resultado_cabecalho"
  _qa_rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'divergencia e falha do item'
  assert_arquivo_ausente "$base/local/novo/a.txt" 'conteudo nao conferido nunca vira arquivo'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
  assert_igual 0 "$(_qa_residuos_http "$base")" 'nenhuma area HTTP resta'
}

teste_qa_download_hash_divergente_em_alvo_novo_nao_cria_nada() {
  local base
  base=$(_qa_cenario)
  printf '{"name":"a.txt","content_hash":"%s"}' "$QA_ZERADO" >"$base/resultado_cabecalho"
  _qa_rodar "$base" download /r/a.txt "$base/local/a.txt"
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$DBX_ESTADO" 'divergencia sai por integridade'
  assert_arquivo_ausente "$base/local/a.txt" 'o alvo nao e criado'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
}

teste_qa_download_hash_malformado_nao_conta_como_conferido() {
  local base
  base=$(_qa_cenario)
  printf 'ANTIGO' >"$base/local/a.txt"
  printf '{"name":"a.txt","content_hash":"nao-e-hex"}' >"$base/resultado_cabecalho"
  _qa_rodar "$base" download /r/a.txt "$base/local/a.txt"
  assert_diferente 0 "$DBX_ESTADO" 'resumo ilegivel nao e prova de integridade'
  assert_igual 'ANTIGO' "$(cat "$base/local/a.txt")" 'o alvo fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
}

teste_qa_download_em_diretorio_somente_leitura_falha_sem_efeito() {
  [[ $(id -u) -eq 0 ]] && pular 'root ignora permissao de diretorio'
  local base
  base=$(_qa_cenario)
  mkdir -p "$base/local/ro"
  printf 'ANTIGO' >"$base/local/ro/a.txt"
  chmod 555 "$base/local/ro"
  _qa_rodar "$base" download /r/a.txt "$base/local/ro/a.txt"
  chmod 755 "$base/local/ro"
  assert_diferente 0 "$DBX_ESTADO" 'sem escrita no diretorio nao ha sucesso'
  assert_igual 'ANTIGO' "$(cat "$base/local/ro/a.txt")" 'o alvo fica intacto'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" \
    'a falha local vem antes de qualquer recebimento'
  assert_igual 0 "$(_qa_residuos_http "$base")" 'nenhuma area HTTP resta'
}

# RF-55(f), TC-ATM-05 (decisao do solicitante): alvo sem escrita e RECUSADO.
_qa_hash_conferido() { # <base> — o servico publica o resumo do conteudo remoto
  local resumo
  printf 'conteudo remoto' >"$1/ref"
  resumo=$(_qa_resumo "$1/ref")
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$1/resultado_cabecalho"
}

teste_qa_download_sobre_alvo_somente_leitura_recusa_e_preserva() {
  [[ $(id -u) -eq 0 ]] && pular 'root ignora permissao de escrita'
  local base mtime_antes
  base=$(_qa_cenario)
  printf 'ANTIGO' >"$base/local/a.txt"
  chmod 444 "$base/local/a.txt"
  touch -d '2021-05-06 07:08:09' "$base/local/a.txt"
  mtime_antes=$(stat -c %Y "$base/local/a.txt")
  _qa_hash_conferido "$base"
  _qa_rodar "$base" download /r/a.txt "$base/local/a.txt"
  assert_igual "$(dbx_errors_codigo_saida permissao)" "$DBX_ESTADO" 'RF-55(f): alvo somente leitura e recusado'
  assert_contem 'somente leitura' "$DBX_ERRO" 'o diagnostico nomeia a causa'
  assert_igual 'ANTIGO' "$(cat "$base/local/a.txt")" 'o conteudo fica intacto'
  assert_igual 444 "$(stat -c %a "$base/local/a.txt")" 'o modo fica intacto'
  assert_igual "$mtime_antes" "$(stat -c %Y "$base/local/a.txt")" 'o mtime fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" 'a recusa vem antes de transferir'
}

teste_qa_download_por_vinculo_para_alvo_somente_leitura_recusa() {
  # O vinculo e resolvido antes da checagem: a protecao vale para o arquivo
  # apontado, e o vinculo nao e trocado por um arquivo regular.
  [[ $(id -u) -eq 0 ]] && pular 'root ignora permissao de escrita'
  local base
  base=$(_qa_cenario)
  mkdir -p "$base/local/real"
  printf 'ANTIGO' >"$base/local/real/a.txt"
  chmod 444 "$base/local/real/a.txt"
  ln -s real/a.txt "$base/local/vinculo"
  _qa_hash_conferido "$base"
  _qa_rodar "$base" download /r/a.txt "$base/local/vinculo"
  assert_igual "$(dbx_errors_codigo_saida permissao)" "$DBX_ESTADO" 'alvo apontado sem escrita e recusado'
  assert_sucesso test -L "$base/local/vinculo"
  assert_igual 'ANTIGO' "$(cat "$base/local/real/a.txt")" 'o arquivo apontado fica intacto'
  assert_igual 444 "$(stat -c %a "$base/local/real/a.txt")" 'o modo fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
}

teste_qa_sync_receber_espelhar_com_alvo_somente_leitura_falha_o_item_sem_apagar() {
  [[ $(id -u) -eq 0 ]] && pular 'root ignora permissao de escrita'
  local base
  base=$(_qa_cenario)
  mkdir -p "$base/local/Sub"
  printf 'ANTIGO' >"$base/local/Sub/A.txt"
  chmod 444 "$base/local/Sub/A.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_qa_entrada '/r/sub/a.txt' ff 15)" "$(_qa_entrada '/r/b.txt' ff 15)" >"$base/listagem"
  _qa_hash_conferido "$base"
  _qa_rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'o item recusado torna o sync nao concluido'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'o alvo somente leitura (caixa diferente) e falha do item'
  assert_contem 'recebidos=1' "$DBX_SAIDA" 'o outro item segue'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'o par recusado nunca entra na exclusao'
  assert_igual 'ANTIGO' "$(cat "$base/local/Sub/A.txt")" 'o alvo fica intacto'
  assert_igual 444 "$(stat -c %a "$base/local/Sub/A.txt")" 'o modo fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
}

# ---------------------------------------------------------------------------
# RF-56 — download de pasta nunca apaga arquivo
# ---------------------------------------------------------------------------

teste_qa_download_de_pasta_sobre_vinculo_para_arquivo_recusa() {
  local base
  base=$(_qa_cenario)
  printf 'MEU' >"$base/local/real.txt"
  ln -s real.txt "$base/local/vinculo"
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_409"
  _qa_rodar "$base" download /pasta "$base/local/vinculo"
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" 'vinculo para arquivo e recusado'
  assert_sucesso test -L "$base/local/vinculo"
  assert_igual 'MEU' "$(cat "$base/local/real.txt")" 'o arquivo apontado fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
  assert_igual 0 "$(_qa_residuos_http "$base")" 'reemissao diagnostica sem area HTTP restante'
}

teste_qa_download_de_pasta_sobre_vinculo_quebrado_recusa() {
  local base
  base=$(_qa_cenario)
  ln -s inexistente "$base/local/vinculo"
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_409"
  _qa_rodar "$base" download /pasta "$base/local/vinculo"
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" 'vinculo quebrado e recusado'
  assert_sucesso test -L "$base/local/vinculo"
  assert_arquivo_ausente "$base/local/inexistente" 'nada e criado no destino do vinculo'
}

teste_qa_download_de_pasta_para_destino_novo_sem_residuo() {
  local base
  base=$(_qa_cenario)
  printf '%s' '{"error_summary":"path/not_file/..."}' >"$base/download_409"
  _qa_rodar "$base" download /pasta "$base/local/nova"
  assert_igual 0 "$DBX_ESTADO" "pasta para destino novo continua funcionando; diagnostico: $DBX_ERRO"
  assert_sucesso test -d "$base/local/nova"
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta ao lado do destino'
  assert_igual 0 "$(_qa_residuos_http "$base")" 'nenhuma area HTTP resta apos a reemissao'
}

# ---------------------------------------------------------------------------
# RNF-29 — umask e areas temporarias
# ---------------------------------------------------------------------------

teste_qa_download_segue_umask_027() {
  local base
  base=$(_qa_cenario)
  umask 027
  _qa_rodar "$base" download /r/a.txt "$base/local/n/a.txt"
  assert_igual 0 "$DBX_ESTADO" "download deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 640 "$(stat -c %a "$base/local/n/a.txt")" 'arquivo segue o umask 027'
  assert_igual 750 "$(stat -c %a "$base/local/n")" 'diretorio segue o umask 027'
}

teste_qa_sync_receber_segue_umask_027_e_preserva_modo_existente() {
  local base
  base=$(_qa_cenario)
  printf 'velho' >"$base/local/b.txt"
  chmod 600 "$base/local/b.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_qa_entrada '/r/s/a.txt' ff 15)" "$(_qa_entrada '/r/b.txt' ff 15)" >"$base/listagem"
  umask 027
  _qa_rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 640 "$(stat -c %a "$base/local/s/a.txt")" 'arquivo novo segue o umask 027'
  assert_igual 750 "$(stat -c %a "$base/local/s")" 'diretorio novo segue o umask 027'
  assert_igual 600 "$(stat -c %a "$base/local/b.txt")" 'arquivo existente mantem o modo'
  assert_igual 'conteudo remoto' "$(cat "$base/local/b.txt")" 'e recebe o conteudo novo'
}

teste_qa_falha_de_rede_no_download_nao_deixa_area_http() {
  local base
  base=$(_qa_cenario)
  printf 'ANTIGO' >"$base/local/a.txt"
  printf '%s' '{"error_summary":"path/not_found/..."}' >"$base/download_409"
  _qa_rodar "$base" download /r/a.txt "$base/local/a.txt"
  assert_igual "$(dbx_errors_codigo_saida nao_encontrado)" "$DBX_ESTADO" 'nao encontrado'
  assert_igual 'ANTIGO' "$(cat "$base/local/a.txt")" 'o alvo fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'nenhum temporario resta'
  assert_igual 0 "$(_qa_residuos_http "$base")" 'reemissao diagnostica sem area HTTP restante'
}

teste_qa_sinal_no_sync_receber_remove_temporario_e_area_http() {
  local base
  base=$(_qa_cenario)
  printf 'ANTIGO' >"$base/local/a.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_qa_entrada '/r/a.txt' ff 15)" >"$base/listagem"
  : >"$base/sinal"
  _qa_rodar_em_sessao "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_diferente 0 "$DBX_ESTADO" 'sinal nao e sucesso'
  assert_igual 'ANTIGO' "$(cat "$base/local/a.txt")" 'o alvo fica intacto'
  assert_igual 0 "$(_qa_partes "$base/local")" 'o temporario e removido no sinal'
  assert_igual 0 "$(_qa_residuos_http "$base")" 'a area HTTP com o token e removida no sinal'
}

# ---------------------------------------------------------------------------
# Filtro do temporario orfao: so a marca exata e filtrada
# ---------------------------------------------------------------------------

teste_qa_nomes_parecidos_com_temporario_continuam_sincronizados() {
  local base
  base=$(_qa_cenario)
  printf '1' >"$base/local/.x.dbx-part.abc"     # sufixo curto
  printf '2' >"$base/local/.x.dbx-part.abcdefg" # sufixo longo
  printf '3' >"$base/local/x.dbx-part.abcdef"   # nao oculto
  printf '4' >"$base/local/.x.dbx-part.Ab12Cd"  # marca exata: filtrado
  _qa_rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'a_transferir=3' "$DBX_SAIDA" 'so a marca exata e retirada da arvore'
  assert_contem '.x.dbx-part.abc' "$(_qa_args_de_envio "$base" '/r/.x.dbx-part.abc')" 'sufixo curto e enviado'
  assert_nao_contem 'Ab12Cd' "$(cat "$base/opcoes")" 'o temporario com a marca exata nunca e enviado'
}

harness_executar "$@"
