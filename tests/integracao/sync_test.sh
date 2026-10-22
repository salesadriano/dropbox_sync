#!/usr/bin/env bash
# Testes ponta a ponta do `sync` direcional (DP-27, DP-28, RF-37..RF-53).
#
# O QUE ESTE ARQUIVO PRECISA PROVAR, e por que ele e o mais adversarial da suite:
# `RSK-35` registra que a matriz de tres estados garantia ESTRUTURALMENTE que a
# primeira execucao nunca apagava nada, e que essa garantia caiu com `DP-27`.
# Sobraram quatro barreiras — RF-40, RF-41, RF-47 e RF-48 — e elas nao tem
# suporte estrutural nenhum: se qualquer uma falhar, o sintoma e a arvore do
# operador apagada.
#
# shellcheck disable=SC2016
# Justificativa: casos escrevem o substituto de `curl`, que precisa chegar sem
# expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"

# _cenario <json_do_list_folder> — monta credencial, duplo de rede e arvore local.
#
# O duplo registra CADA URL chamada em `$base/chamadas`, que e o que permite
# afirmar "zero exclusoes emitidas" olhando o que saiu, e nao o que o relatorio
# diz ter feito.
_cenario() {
  local listagem=${1:-'{"entries":[],"has_more":false}'}
  local base
  base=$(mktemp -d "$DBX_TESTES_TMP/sync.XXXXXX")
  mkdir -p "$base/config/dbx" "$base/bin" "$base/local"
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  chmod 700 "$base/config/dbx"
  chmod 600 "$base/config/dbx/credencial.json"
  printf '%s' "$listagem" >"$base/listagem"
  printf '%s' 'conteudo remoto' >"$base/conteudo_remoto"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'base=%s\nDBX_HARNESS_RAIZ=%q\n' "$base" "$DBX_HARNESS_RAIZ"
    printf 'conf=$(cat 2>/dev/null)\n'
    printf 'printf "%%s\\n" "$conf" >>"$base/opcoes"\n'
    printf 'saida=""; escrever=""; anterior=""; url=""; cabecalhos=""; corpo_arquivo=""\n'
    printf 'for arg in "$@"; do\n'
    printf '  case $anterior in -o) saida=$arg ;; -w) escrever=$arg ;; -D) cabecalhos=$arg ;; --data-binary) corpo_arquivo=${arg#@} ;; esac\n'
    printf '  case $arg in http*) url=$arg ;; esac\n'
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
    # RF-136: o lote de exclusao do `--espelhar` (delete_batch + check) responde
    # aqui; cada item confirmado e ecoado em `chamadas` como `files/delete_v2`.
    cat <<'LOTE'
LOTE_ECOA_V2=sim
. "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
lote_responder "$url" "$corpo_arquivo" || :
LOTE
    # Conflito de rev (RF-49): o envio cujo argumento cita o caminho marcado e
    # recusado como a Dropbox recusa, com 409 e tag `conflict`.
    printf 'if [[ $url == *files/upload && -f "$base/upload_conflito" && $conf == *"$(cat "$base/upload_conflito")"* ]]; then\n'
    printf '  codigo=409; corpo=%s\n' "'{\"error_summary\":\"path/conflict/file/..\"}'"
    printf 'fi\n'
    printf 'if [[ $url == *files/download* && -n $cabecalhos && -f "$base/resultado_cabecalho" ]]; then\n'
    printf '  printf "Dropbox-API-Result: %%s\\r\\n" "$(cat "$base/resultado_cabecalho")" >"$cabecalhos"\n'
    printf 'fi\n'
    # RF-59: token e erros por tipo de item; RNF-31: sinal ao grupo do processo
    # quando a URL casa, so seguro sob `setsid` (ver `_rodar_em_sessao`).
    cat <<'FIM'
if [[ $url == *oauth2/token* && -f "$base/token" ]]; then
  corpo="{\"access_token\":\"$(cat "$base/token")\",\"expires_in\":14400}"
fi
# RF-52(a): a identificacao da conta falha, sem retentativa (400).
if [[ $url == *get_current_account* && -f "$base/conta_falha" ]]; then
  codigo=400; corpo='{"error_summary":"other/"}'
fi
# QA-P3-03: a enumeracao remota responde com o codigo e o corpo dados.
if [[ $url == *list_folder* && -f "$base/listagem_codigo" ]]; then
  codigo=$(cat "$base/listagem_codigo")
fi
for tipo in upload:files/upload download:files/download delete:files/delete_v2; do
  if [[ $url == *"${tipo#*:}" && -f "$base/${tipo%%:*}_erro" ]]; then
    codigo=$(cat "$base/${tipo%%:*}_erro")
    corpo=$(cat "$base/erro_corpo")
  fi
done
# RF-137: dois ou mais pequenos vao por `upload_session/start` (lote); o erro de
# envio dado e o mesmo nessa rota, para o item falhar com a mesma classe e resumo.
if [[ $url == *upload_session/start && -f "$base/upload_erro" ]]; then
  codigo=$(cat "$base/upload_erro")
  corpo=$(cat "$base/erro_corpo")
fi
if [[ -f "$base/sinal" && $url == *"$(cat "$base/sinal_url")"* ]]; then
  kill -s "$(cat "$base/sinal")" 0
  sleep 5
fi
FIM
    printf '[[ -n $saida ]] && printf "%%s" "$corpo" >"$saida"\n'
    printf '[[ -n $escrever ]] && printf "%%s" "$codigo"\n'
    printf 'exit 0\n'
  } >"$base/bin/curl"
  chmod +x "$base/bin/curl"
  # RNF-02, TC-DEP-03: sentinelas no lugar de `sqlite3` e `python3`.
  local proibido
  for proibido in sqlite3 python3 python; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>%q\nexit 1\n' \
      "$proibido" "$base/proibido" >"$base/bin/$proibido"
    chmod +x "$base/bin/$proibido"
  done
  printf '%s' "$base"
}

_rodar() { # <base> <argumentos...>
  local base=$1
  shift
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

_escritas() { # <base> — quantas chamadas de escrita remota sairam
  _harness_contar 'files/upload\|files/delete_v2' "$1/chamadas"
}

_exclusoes() { # <base>
  _harness_contar 'files/delete_v2' "$1/chamadas"
}

_entrada_remota() { # <caminho> <hash> <tamanho>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s}' "$1" "$2" "$3"
}

_entrada_remota_com_rev() { # <caminho> <hash> <tamanho> <rev>
  printf '{".tag":"file","path_display":"%s","content_hash":"%s","size":%s,"rev":"%s"}' \
    "$1" "$2" "$3" "$4"
}

_resumo_de() { # <arquivo>
  bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$1'"
}

_conteudo_do_diretorio() { # <diretorio> — nomes, inclusive ocultos, um por linha
  find "$1" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
}

readonly RESUMO_ZERADO=0000000000000000000000000000000000000000000000000000000000000000

# ---------------------------------------------------------------------------
# Contrato dos lados (RF-53, DP-28)
# ---------------------------------------------------------------------------

teste_origem_e_destino_sao_obrigatorios() {
  local base
  base=$(_cenario)
  _rodar "$base" sync --enviar --destino /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem --origem'
  assert_contem '--origem' "$DBX_ERRO" 'o diagnostico nomeia o que falta'
  _rodar "$base" sync --enviar --origem "$base/local"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem --destino'
  assert_contem '--destino' "$DBX_ERRO" 'o diagnostico nomeia o que falta'
}

teste_sentido_e_obrigatorio_e_mutuamente_exclusivo() {
  # DP-28 adotou a leitura OBRIGATORIA. Na leitura opcional a inferencia
  # continuaria decidindo nos casos que nao empatam — que sao justamente os que
  # invertem o sentido em silencio.
  local base
  base=$(_cenario)
  _rodar "$base" sync --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'sem sentido declarado'
  assert_contem '--enviar' "$DBX_ERRO" 'o diagnostico oferece as duas opcoes'
  assert_contem '--receber' "$DBX_ERRO" 'o diagnostico oferece as duas opcoes'
  _rodar "$base" sync --origem "$base/local" --destino /r --enviar --receber
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'os dois juntos'
  assert_contem 'mutuamente exclusiv' "$DBX_ERRO" 'a recusa diz por que'
}

teste_o_tipo_de_cada_lado_nunca_e_inferido_do_caminho() {
  # RF-53(c) com verificacao estatica: `DP-28` fechou a inferencia, e reintroduzi
  # -la nao produziria sintoma em teste de dado — produziria o `sync` enviando
  # quando o operador pediu receber.
  local achados
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/commands/sync.sh" 'sem o arquivo a auditoria seria vacua'
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/commands/sync.sh" |
    grep -nE '\[\[[^]]*-(d|e|f)[[:space:]]+"?\$\{?(origem|destino)\}?"?' || true)
  assert_igual '' "$achados" "inspecao de caminho para decidir tipo: $achados"
  # Prova de discriminacao: o reconhecedor precisa reagir a forma que proibe.
  local amostra='  if [[ -d $origem ]]; then sentido=enviar; fi'
  grep -qE '\[\[[^]]*-(d|e|f)[[:space:]]+"?\$\{?(origem|destino)\}?"?' <<<"$amostra" ||
    _harness_falhar 'o reconhecedor nao detecta a inferencia que deveria proibir'
  local inocente='  [[ -d $raiz_local ]] || return 1'
  grep -qE '\[\[[^]]*-(d|e|f)[[:space:]]+"?\$\{?(origem|destino)\}?"?' <<<"$inocente" &&
    _harness_falhar 'o reconhecedor acusa a verificacao legitima da raiz local'
  return 0
}

teste_fluxo_e_recusado_nos_dois_lados() {
  local base
  base=$(_cenario)
  _rodar "$base" sync --enviar --origem - --destino /r
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'origem em fluxo'
  assert_contem '--origem' "$DBX_ERRO" 'RF-45: a recusa nomeia o sinalizador'
  _rodar "$base" sync --enviar --origem "$base/local" --destino -
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_ESTADO" 'destino em fluxo'
  assert_contem '--destino' "$DBX_ERRO" 'RF-45: a recusa nomeia o sinalizador'
}

teste_carimbo_de_tempo_nao_participa_de_decisao() {
  # RF-39 sob DP-27: a proibicao passou a ser TOTAL, porque a etapa de ordenacao
  # deixou de existir. `mtime` so pode aparecer para decidir reaproveitamento de
  # resumo ja calculado, e isso mora em lib/state.
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/sync.sh" |
    grep -nE 'mtime|client_modified|server_modified' || true)
  assert_igual '' "$achados" "carimbo de tempo em lib/sync: $achados"
}

# ---------------------------------------------------------------------------
# Tabela de decisao (5.8.2)
# ---------------------------------------------------------------------------

teste_transfere_o_que_so_existe_na_origem_e_omite_identico() {
  local base resumo
  base=$(_cenario '{"entries":[],"has_more":false}')
  printf 'um' >"$base/local/um.txt"
  printf 'dois' >"$base/local/dois.txt"
  # O resumo do arquivo que ja existe do outro lado precisa ser o real, senao a
  # linha "conteudo identico" nunca seria exercitada.
  resumo=$(bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$base/local/um.txt'")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/um.txt' "$resumo" 2)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=dois.txt' "$DBX_SAIDA" 'ausente no destino: transferir'
  assert_nao_contem 'transferir=um.txt' "$DBX_SAIDA" 'RF-33: conteudo identico nao transfere'
  assert_contem 'identicos=1' "$DBX_SAIDA" 'o contador de omitidos declara a omissao'
}

teste_conteudo_divergente_transfere_com_a_origem_prevalecendo() {
  local base
  base=$(_cenario)
  printf 'novo conteudo' >"$base/local/x.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/x.txt' '0000000000000000000000000000000000000000000000000000000000000000' 5)" \
    >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem 'transferir=x.txt' "$DBX_SAIDA" 'divergencia resolve a favor da origem'
}

teste_resumo_remoto_malformado_nunca_e_lido_como_identico() {
  # A falha aqui nao teria sintoma: omitir transferencia nao emite operacao, e o
  # relatorio diria que esta tudo sincronizado.
  local base
  base=$(_cenario)
  printf 'conteudo' >"$base/local/y.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/y.txt' 'nao-e-resumo' 8)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem 'transferir=y.txt' "$DBX_SAIDA" 'resumo ilegivel obriga a transferir'
}

# ---------------------------------------------------------------------------
# As quatro barreiras que sobraram (RSK-35)
# ---------------------------------------------------------------------------

teste_sem_espelhar_nenhuma_exclusao_e_emitida() {
  # RF-40: o padrao e preservar. O caminho so no destino e reportado como
  # divergencia nao propagada, e nao apagado.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/fica.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'apenas_no_destino=orfao.txt' "$DBX_SAIDA" 'a divergencia e reportada'
  assert_igual 0 "$(_exclusoes "$base")" 'RF-40: zero exclusoes sem espelhamento'
}

teste_travessia_parcial_desabilita_exclusao_na_execucao_inteira() {
  # RF-41(a). O ramo ilegivel esta em PROFUNDIDADE, e o efeito precisa alcancar a
  # execucao toda — inclusive o orfao que nao tem relacao com o ramo que falhou.
  # Mutacao que restrinja o efeito ao ramo com erro reprova aqui.
  local base
  base=$(_cenario)
  mkdir -p "$base/local/sub/fundo"
  printf 'a' >"$base/local/raiz.txt"
  printf 'b' >"$base/local/sub/fundo/dentro.txt"
  chmod 000 "$base/local/sub/fundo"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  chmod 755 "$base/local/sub/fundo"
  assert_igual 0 "$(_exclusoes "$base")" 'RF-41a: zero exclusoes com travessia parcial'
  assert_contem 'exclusao_desabilitada=' "$DBX_SAIDA" 'o relatorio declara por que nao apagou'
  assert_diferente 0 "$DBX_ESTADO" 'RF-41a: o codigo de saida difere de zero'
}

teste_vinculo_simbolico_tambem_desabilita_exclusao() {
  # O ramo do outro lado do vinculo e invisivel para a origem, e invisivel
  # produz a mesma observacao que apagado.
  local base fora
  base=$(_cenario)
  fora=$(mktemp -d "$DBX_TESTES_TMP/fora.XXXXXX")
  printf 'a' >"$base/local/fica.txt"
  ln -s "$fora" "$base/local/atalho"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_exclusoes "$base")" 'vinculo pulado tambem desabilita exclusao'
}

teste_origem_vazia_com_memoria_povoada_recusa_integralmente() {
  # RF-41(b). Uma raiz que ficou vazia por engano — ponto de montagem que nao
  # subiu — e indistinguivel de uma esvaziada de proposito.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/um.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "primeira execucao deve concluir; diagnostico: $DBX_ERRO"
  rm -f "$base/local/um.txt"
  # MUDANCA DECLARADA (fase 4, O-1): a recusa nao depende mais da memoria, e
  # sim de haver algo a apagar no destino. O duplo agora lista o `um.txt` que a
  # primeira execucao enviou, como a Dropbox listaria.
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/um.txt' 'ff' 1)" >"$base/listagem"
  : >"$base/chamadas"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_diferente 0 "$DBX_ESTADO" 'origem vazia com memoria povoada e recusa'
  assert_igual 0 "$(_escritas "$base")" 'RF-41b: recusa INTEGRAL, sem nenhuma escrita'
}

teste_primeira_execucao_com_espelhamento_exige_reconhecimento() {
  # RF-48, com a razao invertida por DP-27: nao e mais que "sem base nada pode
  # ser apagado" — e que sem base TUDO pode.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/um.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_diferente 0 "$DBX_ESTADO" 'primeira execucao com espelhamento sem reconhecimento'
  assert_contem '--dry-run' "$DBX_ERRO" 'o diagnostico oferece a simulacao'
  assert_contem '--confirmar' "$DBX_ERRO" 'o diagnostico oferece a confirmacao'
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita antes do reconhecimento'
}

teste_exclusoes_sao_anunciadas_antes_de_executadas() {
  # RF-41(d) e RF-47: a lista completa sai antes da primeira exclusao, e o
  # registro e NOMINAL.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/fica.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sai.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_contem 'apagar=sai.txt' "$DBX_SAIDA" 'RF-47: a perda e registrada nominalmente'
  assert_contem 'a_apagar=1' "$DBX_SAIDA" 'o total sai antes da execucao'
  assert_igual 1 "$(_exclusoes "$base")" 'com espelhamento e travessia sa, a exclusao ocorre'
}

# ---------------------------------------------------------------------------
# Simulacao, idempotencia e a memoria que nao decide (DP-27b)
# ---------------------------------------------------------------------------

teste_simulacao_imprime_o_plano_e_nao_escreve() {
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/um.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sai.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json --dry-run sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual 0 "$DBX_ESTADO" "RF-44: a simulacao deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=um.txt' "$DBX_SAIDA" 'o plano lista a transferencia'
  assert_contem 'apagar=sai.txt' "$DBX_SAIDA" 'o plano lista a exclusao'
  assert_contem 'simulado=sim' "$DBX_SAIDA" 'a simulacao se declara'
  assert_igual 0 "$(_escritas "$base")" 'RF-15: simulacao nao emite escrita'
}

teste_segunda_execucao_sem_alteracao_nao_emite_escrita() {
  # Idempotencia verificavel (RF-37). Sem ela, um `sync` periodico reenviaria a
  # arvore inteira a cada execucao.
  local base resumo
  base=$(_cenario)
  printf 'um' >"$base/local/um.txt"
  resumo=$(bash -c ". '$DBX_HARNESS_RAIZ/lib/errors.sh'; . '$DBX_HARNESS_RAIZ/lib/hash.sh'; dbx_hash_conteudo_arquivo '$base/local/um.txt'")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/um.txt' "$resumo" 2)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  : >"$base/chamadas"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "segunda execucao deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita quando nada mudou'
}

teste_apagar_a_memoria_nao_muda_o_conjunto_de_operacoes() {
  # A VERIFICACAO QUE FIXA DP-27b, e ela e o par de mutacao de RSK-23: se a
  # memoria voltar a arbitrar, os dois planos divergem. Sem este caso, um cache
  # que decide passaria despercebido — porque cache que decide errado OMITE
  # operacao, e omissao nao aparece em relatorio.
  local base plano_com plano_sem
  base=$(_cenario)
  printf 'um' >"$base/local/um.txt"
  printf 'dois' >"$base/local/dois.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  plano_com=$(grep '^transferir=' <<<"$DBX_SAIDA" | sort)
  rm -rf "$base/estado"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  plano_sem=$(grep '^transferir=' <<<"$DBX_SAIDA" | sort)
  assert_igual "$plano_com" "$plano_sem" \
    'memoria apagada nao pode mudar o conjunto de operacoes decididas'
}

teste_recebimento_grava_no_local_e_cria_as_pastas_intermediarias() {
  local base
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sub/fundo/a.txt' 'ff' 3)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'sentido=receber' "$DBX_SAIDA" 'o sentido apurado e declarado'
  assert_arquivo_existe "$base/local/sub/fundo/a.txt" 'as pastas intermediarias sao criadas'
}

teste_recebimento_cria_diretorio_de_destino_caso_nao_exista() {
  local base
  base=$(_cenario)
  local destino_novo="$base/local/nova_pasta/subpasta"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 3)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$destino_novo"
  assert_igual 0 "$DBX_ESTADO" "recebimento com destino novo deve concluir; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$destino_novo" 'o diretorio raiz de destino inexistente deve ser criado'
  assert_sucesso test -d "$destino_novo"
  assert_arquivo_existe "$destino_novo/a.txt" 'o arquivo deve ser gravado dentro do novo destino'
}

teste_sync_com_progresso_emite_em_stderr_e_preserva_stdout() {
  local base
  base=$(_cenario)
  printf 'conteudo' >"$base/local/a.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '[sync' "$DBX_ERRO" 'stderr deve conter marcadores de progresso do sync'
  assert_nao_contem '[sync' "$DBX_SAIDA" 'stdout nao pode ser contaminado com progresso'
}

teste_sync_com_progresso_lista_arquivos_e_resultados_da_analise() {
  local base
  base=$(_cenario)
  printf 'conteudo 1' >"$base/local/arq1.txt"
  printf 'conteudo 2' >"$base/local/arq2.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'analisando local (1/2): arq' "$DBX_ERRO" 'deve listar analise de arquivo local'
  assert_contem 'analise [' "$DBX_ERRO" 'deve listar resultado da analise'
  assert_contem 'novo (a enviar)' "$DBX_ERRO" 'resultado deve classificar arquivo novo'
}

teste_sync_com_progresso_exibe_andamento_da_consulta_remota() {
  local base
  base=$(_cenario)
  printf 'conteudo 1' >"$base/local/arq1.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_entrada_remota '/r/rem1.txt' 'hash1' 10)" \
    "$(_entrada_remota '/r/rem2.txt' 'hash2' 20)" \
    >"$base/listagem"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'consultando arquivos remotos em: /r' "$DBX_ERRO" 'deve anunciar inicio da consulta remota'
  assert_contem 'consultando remoto (1): rem1.txt' "$DBX_ERRO" 'deve exibir progresso do primeiro arquivo remoto'
  assert_contem 'consultando remoto (2): rem2.txt' "$DBX_ERRO" 'deve exibir progresso do segundo arquivo remoto'
  assert_contem 'arquivos remotos consultados: 2 arquivo(s)' "$DBX_ERRO" 'deve exibir total de arquivos remotos consultados'
  assert_nao_contem 'consultando remoto' "$DBX_SAIDA" 'stdout nao pode conter mensagens de progresso'
}

teste_sync_com_progresso_exibe_andamento_da_analise_local() {
  local base
  base=$(_cenario)
  printf 'conteudo 1' >"$base/local/arq1.txt"
  printf 'conteudo 2' >"$base/local/arq2.txt"
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync com --progresso deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'analisando arquivos locais em: ' "$DBX_ERRO" 'deve anunciar inicio da analise local'
  assert_contem 'analisando local (1/2): arq' "$DBX_ERRO" 'deve exibir andamento do primeiro arquivo local'
  assert_contem 'analisando local (2/2): arq' "$DBX_ERRO" 'deve exibir andamento do segundo arquivo local'
  assert_contem 'arquivos locais analisados: 2 arquivo(s)' "$DBX_ERRO" 'deve exibir total de arquivos locais analisados'
  assert_nao_contem 'analisando local' "$DBX_SAIDA" 'stdout nao pode conter mensagens de progresso'
}

# ---------------------------------------------------------------------------
# Caixa de caminho (RF-54, DP-31): a Dropbox nao diferencia caixa
# ---------------------------------------------------------------------------

teste_caixa_diferente_e_o_mesmo_arquivo_e_espelhar_nao_apaga_o_enviado() {
  # TC-CX-01 e TC-CX-02. Antes, o par virava "transferir" + "apagar", e o
  # `delete_v2` removia o arquivo que acabara de ser enviado.
  local base
  base=$(_cenario)
  mkdir -p "$base/local/Docs"
  printf 'novo' >"$base/local/Docs/Foto.JPG"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/docs/foto.jpg' "$RESUMO_ZERADO" 4)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'transferir=Docs/Foto.JPG' "$DBX_SAIDA" 'o conteudo divergente e enviado'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'RF-54(a): o par nao entra no plano de exclusao'
  assert_nao_contem 'apagar=docs/foto.jpg' "$DBX_SAIDA" 'RF-54(a): nenhum apagar para o mesmo arquivo'
  assert_igual 0 "$(_exclusoes "$base")" 'RF-54(b): nenhuma exclusao remota atinge o enviado'
  assert_igual 1 "$(_harness_contar 'files/upload$' "$base/chamadas")" 'um unico envio'
  assert_contem '/r/docs/foto.jpg' "$(cat "$base/opcoes")" \
    'a escrita usa a grafia que o destino ja tem'
}

teste_caixa_diferente_com_conteudo_identico_e_omitido() {
  local base resumo
  base=$(_cenario)
  printf 'igual' >"$base/local/LEIA.txt"
  resumo=$(_resumo_de "$base/local/LEIA.txt")
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/leia.TXT' "$resumo" 5)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'identicos=1' "$DBX_SAIDA" 'o mesmo arquivo com conteudo igual e omitido'
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita para arquivo identico'
}

teste_colisao_de_caixa_local_e_recusada_antes_de_qualquer_escrita() {
  # TC-CX-03: `a.txt` e `A.txt` sao o MESMO caminho na Dropbox. Enviar os dois
  # faria um sobrescrever o outro em silencio.
  local base modo
  base=$(_cenario)
  printf 'minusculo' >"$base/local/a.txt"
  printf 'MAIUSCULO' >"$base/local/A.txt"
  for modo in --dry-run --json; do
    : >"$base/chamadas"
    _rodar "$base" --json "$modo" sync --enviar --origem "$base/local" --destino /r
    assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" \
      "RF-54(c): colisao de caixa recusada ($modo)"
    assert_contem 'a.txt' "$DBX_ERRO" 'o diagnostico nomeia um dos caminhos'
    assert_contem 'A.txt' "$DBX_ERRO" 'o diagnostico nomeia o outro caminho'
    assert_igual 0 "$(_escritas "$base")" 'RF-54(c): nenhuma escrita remota'
    assert_nao_contem 'transferir=' "$DBX_SAIDA" 'nenhum plano e emitido'
  done
}

teste_colisao_de_caixa_no_destino_local_recusa_o_recebimento() {
  local base
  base=$(_cenario)
  printf 'minusculo' >"$base/local/a.txt"
  printf 'MAIUSCULO' >"$base/local/A.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 3)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual "$(dbx_errors_codigo_saida conflito)" "$DBX_ESTADO" 'RF-54(c): recusa tambem no recebimento'
  assert_igual 0 "$(_harness_contar 'files/download' "$base/chamadas")" 'nenhum recebimento emitido'
  assert_igual 'minusculo' "$(cat "$base/local/a.txt")" 'o local fica intacto'
  assert_igual 'MAIUSCULO' "$(cat "$base/local/A.txt")" 'o local fica intacto'
}

teste_recebimento_com_caixa_diferente_grava_no_arquivo_local_existente() {
  local base
  base=$(_cenario)
  mkdir -p "$base/local/docs"
  printf 'antigo' >"$base/local/docs/foto.jpg"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/Docs/Foto.JPG' "$RESUMO_ZERADO" 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 'conteudo remoto' "$(cat "$base/local/docs/foto.jpg")" 'o arquivo local existente e atualizado'
  assert_arquivo_ausente "$base/local/Docs" 'nenhuma copia com a grafia remota e criada'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'RF-54: o mesmo arquivo nao e apagado no local'
}

# ---------------------------------------------------------------------------
# Recebimento atomico no sync (RF-55(e)) e umask (RNF-29)
# ---------------------------------------------------------------------------

teste_recebimento_com_hash_divergente_preserva_o_arquivo_local() {
  local base
  base=$(_cenario)
  printf 'antigo' >"$base/local/a.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf '{"name":"a.txt","content_hash":"%s"}' "$RESUMO_ZERADO" >"$base/resultado_cabecalho"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" \
    'RF-55(e): divergencia conta como falha do item'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'a falha e contada'
  assert_igual 'antigo' "$(cat "$base/local/a.txt")" 'RF-55(b): o arquivo anterior fica intacto'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/local")" 'RF-55(b): sem temporario'
}

teste_recebimento_com_hash_conferido_substitui_sem_temporario() {
  local base resumo
  base=$(_cenario)
  printf 'antigo' >"$base/local/a.txt"
  printf 'conteudo remoto' >"$base/referencia"
  resumo=$(_resumo_de "$base/referencia")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf '{"name":"a.txt","content_hash":"%s"}' "$resumo" >"$base/resultado_cabecalho"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 'conteudo remoto' "$(cat "$base/local/a.txt")" 'RF-55(d): conteudo novo'
  assert_igual 'a.txt' "$(_conteudo_do_diretorio "$base/local")" 'RF-55(d): sem temporario'
}

teste_recebimento_segue_o_umask_do_usuario() {
  local base
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/sub/a.txt' ff 15)" >"$base/listagem"
  umask 022
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 755 "$(stat -c %a "$base/local/sub")" 'RNF-29(a): diretorio criado segue o umask'
  assert_igual 644 "$(stat -c %a "$base/local/sub/a.txt")" 'RNF-29(a): arquivo recebido segue o umask'
}

# ---------------------------------------------------------------------------
# Envio pelo caminho do upload (RF-57) com concorrencia otimista (RF-49)
# ---------------------------------------------------------------------------

teste_envio_define_client_modified() {
  local base
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'client_modified' "$(cat "$base/opcoes")" 'RF-57(b): o envio carrega client_modified'
}

teste_envio_sobre_arquivo_existente_carrega_o_rev_da_listagem() {
  # TC-REV-01: o rev lido NAQUELA execucao viaja com a escrita; arquivo novo
  # vai em modo add, sem renomeacao automatica.
  local base opcoes
  base=$(_cenario)
  # x acima do limiar do lote (DIV-256) e y sozinho abaixo dele (DIV-272): ambos
  # unitarios, que e onde o argumento viaja no cabecalho do cliente.
  head -c 1048577 /dev/zero >"$base/local/x.txt"
  printf 'arquivo novo' >"$base/local/y.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota_com_rev '/r/x.txt' "$RESUMO_ZERADO" 5 015abc)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  # O argumento viaja com as aspas escapadas no arquivo de opcoes do cliente.
  opcoes=$(grep 'Dropbox-API-Arg' "$base/opcoes")
  assert_contem '\"update\":\"015abc\"' "$(grep '/r/x.txt' <<<"$opcoes")" 'RF-49: o envio carrega o rev esperado'
  assert_contem '\"mode\":\"add\"' "$(grep '/r/y.txt' <<<"$opcoes")" 'arquivo novo vai em modo add'
  assert_contem '\"autorename\":false' "$(grep '/r/y.txt' <<<"$opcoes")" 'sem renomeacao automatica'
  assert_nao_contem 'overwrite' "$opcoes" 'o envio nunca sobrescreve as cegas'
}

teste_conflito_de_rev_nao_sobrescreve_e_conta_como_falha() {
  # TC-REV-02: mudanca remota concorrente. O item falha, os demais seguem e o
  # codigo de saida e o de operacao nao concluida.
  local base
  base=$(_cenario)
  # x acima do limiar do lote (1 MiB, DIV-256) e y sozinho abaixo dele (DIV-272):
  # os dois seguem o envio unitario, que e o que o RF-49 verifica.
  head -c 1048577 /dev/zero >"$base/local/x.txt"
  printf 'arquivo novo' >"$base/local/y.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota_com_rev '/r/x.txt' "$RESUMO_ZERADO" 5 015abc)" >"$base/listagem"
  printf '/r/x.txt' >"$base/upload_conflito"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" \
    'RF-49: conflito sai como operacao nao concluida'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'o item em conflito conta como falha'
  assert_contem 'enviados=1' "$DBX_SAIDA" 'os demais itens seguem'
  assert_igual 2 "$(_harness_contar 'files/upload$' "$base/chamadas")" 'uma tentativa por item, sem repeticao'
}

teste_envio_acima_do_teto_vai_por_sessao_com_rev() {
  # TC-SYE-01. Arquivo esparso: o que se verifica e o roteamento por tamanho
  # medido, sem materializar 150 MiB de conteudo.
  local base
  base=$(_cenario)
  dd if=/dev/null of="$base/local/grande.bin" bs=1 seek=$((157286400 + 1)) 2>/dev/null ||
    pular 'nao foi possivel criar arquivo esparso acima do teto'
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota_com_rev '/r/grande.bin' "$RESUMO_ZERADO" 3 R9)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_harness_contar 'files/upload$' "$base/chamadas")" \
    'RF-57(a): nenhuma requisicao unica acima do teto'
  assert_igual 1 "$(_harness_contar 'upload_session/start' "$base/chamadas")" 'RF-57(a): uma sessao'
  assert_igual 1 "$(_harness_contar 'upload_session/finish' "$base/chamadas")" 'RF-57(a): uma conclusao'
  assert_contem '\"update\":\"R9\"' "$(grep 'grande.bin' "$base/opcoes")" \
    'RF-49: o finish da sessao carrega o rev esperado'
}

teste_envio_do_sync_mantem_mute_verdadeiro() {
  local base
  base=$(_cenario)
  printf 'x' >"$base/local/a.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem '\"mute\":true' "$(grep 'Dropbox-API-Arg' "$base/opcoes")" \
    'o sync envia sem notificar, como antes'
}

# ---------------------------------------------------------------------------
# Temporario de recebimento orfao (`.<nome>.dbx-part.XXXXXX`)
# ---------------------------------------------------------------------------

teste_temporario_de_recebimento_nao_e_enviado_nem_entra_no_plano() {
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  mkdir -p "$base/local/sub"
  printf 'parcial' >"$base/local/sub/.b.txt.dbx-part.Ab12Cd"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'a_transferir=1' "$DBX_SAIDA" 'so o arquivo real entra no plano'
  assert_nao_contem 'dbx-part' "$DBX_SAIDA" 'o temporario nao aparece no plano'
  assert_nao_contem 'dbx-part' "$(cat "$base/opcoes")" 'o temporario nunca e enviado'
}

teste_temporario_de_recebimento_nao_entra_na_exclusao_local() {
  local base
  base=$(_cenario)
  printf 'parcial' >"$base/local/.x.txt.dbx-part.Zz99Yy"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "recebimento deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'o temporario nao conta como arquivo local'
  assert_nao_contem 'dbx-part' "$DBX_SAIDA" 'o temporario nao aparece no plano'
  assert_contem 'apagados=0' "$DBX_SAIDA" 'nada e apagado'
}

teste_recebimento_sobre_arquivo_somente_leitura_falha_o_item_e_segue() {
  local base
  base=$(_cenario)
  printf 'antigo' >"$base/local/a.txt"
  chmod 444 "$base/local/a.txt"
  printf '{"entries":[%s,%s],"has_more":false}' \
    "$(_entrada_remota '/r/a.txt' ff 15)" "$(_entrada_remota '/r/b.txt' ff 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'o item recusado torna a execucao nao concluida'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'o arquivo somente leitura conta como falha'
  assert_contem 'recebidos=1' "$DBX_SAIDA" 'os demais itens seguem'
  assert_igual 'antigo' "$(cat "$base/local/a.txt")" 'o arquivo fica intacto'
  assert_igual 444 "$(stat -c %a "$base/local/a.txt")" 'o modo fica intacto'
  assert_igual $'a.txt\nb.txt' "$(_conteudo_do_diretorio "$base/local")" 'nao resta temporario'
}

# ---------------------------------------------------------------------------
# RF-59 — falhas por item reportadas uma a uma, sem segredo (TC-FLH-01..04)
# ---------------------------------------------------------------------------

# _linhas_de_falha <texto> — so as linhas que comecam por `falha `.
_linhas_de_falha() {
  local linha
  while IFS= read -r linha; do
    [[ $linha == 'falha '* ]] && printf '%s\n' "$linha"
  done <<<"$1"
  return 0
}

teste_falha_de_envio_gera_uma_linha_por_item_e_stdout_inalterado() {
  # TC-FLH-01.
  local base linhas
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  printf 'b' >"$base/local/b.txt"
  printf '409' >"$base/upload_erro"
  printf '%s' '{"error_summary":"path/conflict/file/..","error":{".tag":"path"}}' >"$base/erro_corpo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'item falho e operacao nao concluida'
  linhas=$(_linhas_de_falha "$DBX_ERRO")
  assert_igual $'falha a.txt: conflito path/conflict/file\nfalha b.txt: conflito path/conflict/file' \
    "$linhas" 'uma linha por item, com caminho, classe e resumo'
  assert_contem 'falhas=2' "$DBX_SAIDA" 'o contador coincide com as linhas de falha'
  assert_igual '' "$(_linhas_de_falha "$DBX_SAIDA")" 'nenhuma linha de falha no stdout'
  assert_nao_contem 'falha_' "$DBX_SAIDA" 'sem --json o stdout nao ganha campo novo'
}

teste_falha_de_recebimento_e_de_exclusao_tambem_geram_linha() {
  local base linhas
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf '409' >"$base/download_erro"
  printf '%s' '{"error_summary":"path/not_found/..."}' >"$base/erro_corpo"
  _rodar "$base" sync --receber --origem /r --destino "$base/local"
  linhas=$(_linhas_de_falha "$DBX_ERRO")
  assert_igual 'falha a.txt: nao_encontrado path/not_found' "$linhas" \
    'o recebimento falho tem linha propria'

  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf 'b' >"$base/local/b.txt"
  printf '409' >"$base/delete_erro"
  printf '%s' '{"error_summary":"path_lookup/not_found/..."}' >"$base/erro_corpo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  linhas=$(_linhas_de_falha "$DBX_ERRO")
  assert_igual 'falha a.txt: nao_encontrado path_lookup/not_found' "$linhas" \
    'a exclusao remota falha tem linha propria'
  assert_contem 'falhas=1' "$DBX_SAIDA" 'o contador coincide'
}

teste_json_ganha_a_lista_de_falhas_com_caminho_e_classe() {
  # TC-FLH-02: acrescimo compativel; `falhas` (contagem) continua como era.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem 'falhas=0' "$DBX_SAIDA" 'sem falha, o campo existe e e zero'
  assert_nao_contem 'falha_caminho=' "$DBX_SAIDA" 'sem falha, a lista e vazia'
  printf '409' >"$base/upload_erro"
  printf '%s' '{"error_summary":"path/conflict/file/.."}' >"$base/erro_corpo"
  printf 'x' >"$base/local/a.txt"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_contem $'falhas=1\nfalha_caminho=a.txt\nfalha_classe=conflito' "$DBX_SAIDA" \
    'cada falha e um par caminho e classe, logo depois da contagem'
}

teste_linha_de_falha_nunca_carrega_token_nem_corpo_bruto() {
  # TC-FLH-03: sentinelas no token e no corpo de erro, JSON e texto puro.
  local base saida
  base=$(_cenario)
  printf 'sl.SENTINELAtokenXYZ' >"$base/token"
  printf 'a' >"$base/local/a.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/so-remoto.txt' ff 15)" >"$base/listagem"
  printf '409' >"$base/upload_erro"
  printf '%s' '{"error_summary":"path/conflict/file/..","eco":"SENTINELAcorpoJSON"}' >"$base/erro_corpo"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  saida="$DBX_SAIDA$DBX_ERRO"
  assert_igual 1 "$(_linhas_de_falha "$DBX_ERRO" | wc -l)" 'a falha foi reportada'
  assert_segredo_ausente 'SENTINELAtokenXYZ' "$saida" 'o token nunca aparece'
  assert_segredo_ausente 'SENTINELAcorpoJSON' "$saida" 'o corpo bruto nunca aparece'

  rm -f "$base/upload_erro"
  printf '500' >"$base/delete_erro"
  printf '%s' 'SENTINELAcorpoTEXTO Authorization: Bearer sl.SENTINELAtokenXYZ' >"$base/erro_corpo"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  saida="$DBX_SAIDA$DBX_ERRO"
  assert_igual 1 "$(_linhas_de_falha "$DBX_ERRO" | wc -l)" 'a exclusao falha foi reportada'
  assert_segredo_ausente 'SENTINELAtokenXYZ' "$saida" 'o token ecoado no corpo nunca aparece'
  assert_segredo_ausente 'SENTINELAcorpoTEXTO' "$saida" 'o corpo em texto puro nunca aparece'
}

teste_linha_de_falha_mascara_token_e_refresh_token_pelo_valor() {
  # QA-P2-02 (b): segredos SEM forma reconhecivel (sem `sl.`, minusculos, no
  # alfabeto de tag) devolvidos no error_summary. O corte do alfabeto nao os
  # alcanca; so o mascaramento pelo valor em memoria.
  local base resumo
  for resumo in 'tokenqasentinela/..' 'rtqasentinela/..' 'path/rtqasentinela'; do
    base=$(_cenario)
    printf 'tokenqasentinela' >"$base/token"
    printf '%s' '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rtqasentinela","raiz_remota":"/"}' \
      >"$base/config/dbx/credencial.json"
    printf 'a' >"$base/local/a.txt"
    printf '409' >"$base/upload_erro"
    printf '{"error_summary":"%s"}' "$resumo" >"$base/erro_corpo"
    _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
    assert_igual 1 "$(_linhas_de_falha "$DBX_ERRO" | wc -l)" "a falha foi reportada ($resumo)"
    assert_segredo_ausente 'tokenqasentinela' "$DBX_SAIDA$DBX_ERRO" "token de acesso ausente ($resumo)"
    assert_segredo_ausente 'rtqasentinela' "$DBX_SAIDA$DBX_ERRO" "refresh token ausente ($resumo)"
  done
}

teste_caminho_com_quebra_de_linha_nao_forja_linha_de_falha() {
  # TC-FLH-04.
  local base linha total=0
  base=$(_cenario)
  printf 'a' >"$base/local/"$'a\nfalha forjada.txt: rede x'
  printf '409' >"$base/upload_erro"
  printf '%s' '{"error_summary":"path/conflict/file/.."}' >"$base/erro_corpo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  while IFS= read -r linha; do
    [[ $linha == 'falha '* ]] && total=$((total + 1))
  done <<<"$DBX_ERRO"
  assert_igual 1 "$total" 'uma linha de falha por item falho'
  assert_nao_contem $'\nfalha forjada' "$DBX_ERRO" 'o caminho nao abre uma segunda linha'
}

# ---------------------------------------------------------------------------
# RNF-31 — area `dbx-sync.*` removida em INT, TERM e HUP (TC-SIG-01..03)
# ---------------------------------------------------------------------------

# _rodar_em_sessao <base> <argumentos...> — sessao propria, para o sinal ao
# grupo nao alcancar o executor da suite, e TMPDIR PRIVADO do caso: a
# conferencia nunca olha o diretorio compartilhado.
_rodar_em_sessao() {
  local base=$1
  shift
  mkdir -p "$base/tmp"
  DBX_SAIDA=''
  DBX_ERRO=''
  setsid -w env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$base/tmp" \
    bash "$DBX_EXEC" "$@" </dev/null >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

teste_int_durante_o_envio_nao_deixa_area_do_sync() {
  # TC-SIG-01: o sinal chega durante o `files/upload`, com o tratador do sync.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  printf 'INT' >"$base/sinal"
  printf 'files/upload' >"$base/sinal_url"
  _rodar_em_sessao "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_igual 1 "$(_harness_contar 'files/upload' "$base/chamadas")" 'o sinal chegou durante o envio'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area dbx-sync.* nem dbx-http.* resta'
}

teste_term_durante_o_recebimento_nao_deixa_area_do_sync() {
  # TC-SIG-02: o sinal chega com o tratador do RECEBIMENTO armado; ele precisa
  # entregar ao do sync, e nao encerrar sozinho.
  local base
  base=$(_cenario)
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' ff 15)" >"$base/listagem"
  printf 'TERM' >"$base/sinal"
  printf 'files/download' >"$base/sinal_url"
  _rodar_em_sessao "$base" sync --receber --origem /r --destino "$base/local"
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_igual 1 "$(_harness_contar 'files/download' "$base/chamadas")" 'o sinal chegou durante o recebimento'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area dbx-sync.* nem dbx-http.* resta'
  assert_igual '' "$(_conteudo_do_diretorio "$base/local")" 'nem temporario de recebimento'
}

teste_hup_durante_a_listagem_remota_nao_deixa_area_do_sync() {
  # TC-SIG-03.
  local base
  base=$(_cenario)
  printf 'a' >"$base/local/a.txt"
  printf 'HUP' >"$base/sinal"
  printf 'list_folder' >"$base/sinal_url"
  _rodar_em_sessao "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'interrompido e nao concluido'
  assert_igual 0 "$(_harness_contar 'files/upload' "$base/chamadas")" 'o sinal chegou antes de qualquer envio'
  assert_igual '' "$(find "$base/tmp" -mindepth 1)" 'nenhuma area dbx-sync.* nem dbx-http.* resta'
}

# ---------------------------------------------------------------------------
# Fase 3 — memoria do sync no cache unico (RF-38, RF-52(a), RF-62(c), RNF-02)
# ---------------------------------------------------------------------------

_hash_de() {
  bash -c '. "$1/lib/errors.sh"; . "$1/lib/hash.sh"; dbx_hash_conteudo_arquivo "$2"' _ "$DBX_HARNESS_RAIZ" "$1"
}

# _antigo <arquivo> <conteudo> — `mtime` fora da janela anti-corrida de 2 s.
_antigo() {
  printf '%s' "$2" >"$1"
  touch -d '@1700000000.250000000' "$1"
}

_memoria_do_sync() { # <base> — registros da unica memoria-*, um por linha
  local -a lista=()
  shopt -s nullglob
  lista=("$1/estado/dbx"/memoria-*)
  shopt -u nullglob
  [[ ${#lista[@]} -eq 1 ]] || { printf 'memorias:%s' "${#lista[@]}"; return 0; }
  tr '\0' '\n' <"${lista[0]}"
}

_quantas_memorias() { # <base>
  local -a lista=()
  shopt -s nullglob
  lista=("$1/estado/dbx"/memoria-*)
  shopt -u nullglob
  printf '%s' "${#lista[@]}"
}

_esperar_tique_do_ctime() { # ver a nota em tests/unit/walk_test.sh
  local arquivo=$1 sonda=$1.sonda referencia
  referencia=$(stat -c '%z' -- "$arquivo")
  : >"$sonda"
  while [[ $(stat -c '%z' -- "$sonda") == "$referencia" ]]; do
    chmod 600 "$sonda"
  done
  rm -f -- "$sonda"
}

teste_travessia_completa_grava_so_os_arquivos_visitados() {
  # TC-MEM-04 (RF-38(b)).
  local base
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  _antigo "$base/local/b.txt" 'bbbb'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_contem 'b.txt' "$(_memoria_do_sync "$base")" 'primeira execucao registra b.txt'
  rm -f "$base/local/b.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "segunda execucao conclui; diagnostico: $DBX_ERRO"
  assert_nao_contem 'b.txt' "$(_memoria_do_sync "$base")" 'arquivo apagado na origem sai da memoria'
  assert_contem 'a.txt' "$(_memoria_do_sync "$base")" 'o visitado permanece'
}

teste_travessia_parcial_preserva_a_memoria_do_ramo_nao_visitado() {
  # TC-MEM-05 (RF-38(b)).
  [[ $EUID -ne 0 ]] || pular 'root le diretorio sem permissao'
  local base
  base=$(_cenario)
  mkdir -p "$base/local/ramo"
  _antigo "$base/local/a.txt" 'aaaa'
  _antigo "$base/local/ramo/b.txt" 'bbbb'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  chmod 000 "$base/local/ramo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  chmod 755 "$base/local/ramo"
  assert_contem 'ramo/b.txt' "$(_memoria_do_sync "$base")" 'travessia parcial nao descarta o ramo invisivel'
}

teste_reescrita_no_mesmo_segundo_com_remoto_antigo_e_enviada() {
  # TC-MEM-06 (RF-38(e), DIV-26): mutacao que volte a `mtime` em segundos
  # reprova aqui.
  local base hash
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  hash=$(_hash_de "$base/local/a.txt")
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' "$hash" 4)" >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$(_escritas "$base")" 'conteudo igual ao remoto: nada a enviar'
  assert_contem "$hash" "$(_memoria_do_sync "$base")" 'e o resumo vai a memoria'
  _esperar_tique_do_ctime "$base/local/a.txt"
  printf 'bbbb' >"$base/local/a.txt"
  touch -d '@1700000000.250000000' "$base/local/a.txt"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 1 "$(_harness_contar 'files/upload' "$base/chamadas")" \
    'mesmo segundo, mesmo tamanho e mtime restaurado: o sync envia'
}

teste_sem_identidade_de_conta_o_sync_segue_sem_memoria() {
  # TC-CONTA-02 (RF-52(a)).
  local base primeira
  base=$(_cenario)
  : >"$base/conta_falha"
  _antigo "$base/local/a.txt" 'aaaa'
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sem conta o sync segue; diagnostico: $DBX_ERRO"
  primeira=$(grep '^transferir=' <<<"$DBX_SAIDA")
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$(_quantas_memorias "$base")" 'nenhum memoria-* criado'
  assert_igual "$primeira" "$(grep '^transferir=' <<<"$DBX_SAIDA")" 'as mesmas operacoes de uma execucao sem memoria'
  assert_igual '' "$(grep -rl 'sem-identidade' "$base/estado" 2>/dev/null)" 'nenhum identificador substituto'
}

teste_sem_identidade_de_conta_espelhar_pede_reconhecimento_e_a_ajuda_avisa() {
  # TC-CONTA-04 (RF-52(a), DIV-28): falha segura documentada.
  local base
  base=$(_cenario)
  : >"$base/conta_falha"
  _antigo "$base/local/a.txt" 'aaaa'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" \
    'sem memoria o par conta como nunca visto'
  assert_contem '--confirmar' "$DBX_ERRO" 'o diagnostico oferece a confirmacao'
  _rodar "$base" help sync
  assert_contem 'identificacao da conta' "$DBX_SAIDA" 'a ajuda do sync avisa a contrapartida'
  assert_contem '--confirmar' "$DBX_SAIDA" 'e nomeia o sinalizador que a rotina precisa'
  assert_contem 'exclusoes ficam DESABILITADAS' "$DBX_SAIDA" 'ciclo 2: a ajuda descreve as exclusoes desabilitadas'
  assert_contem 'NAO reabilita' "$DBX_SAIDA" 'e que --confirmar nao as reabilita'
  assert_contem 'identificação da conta falhar' "$(cat "$DBX_HARNESS_RAIZ/README.md")" 'o README tambem'
  assert_contem 'exclusões ficam desabilitadas' "$(cat "$DBX_HARNESS_RAIZ/README.md")" 'com o comportamento do ciclo 2'
}

# Ciclo 2 (DIV-28 revista, RF-41): sem identidade de conta nao ha memoria, e
# sem memoria a recusa de RF-41(b) nao protege. A exclusao fica DESABILITADA na
# execucao, com a semantica de RF-41(a), e `--confirmar` nao a reabilita.

# MUDANCA DECLARADA (fase 4, O-6): este caso se chamava
# `teste_sem_conta_origem_vazia_com_confirmar_nao_apaga_nada`. Desde o ciclo 4
# (RF-41(b) emendado) o que ele prova e a RECUSA por origem vazia, que vale
# mesmo sem identidade de conta; o nome passou a dizer isso. As assercoes nao
# mudaram. A afirmacao de `exclusao_desabilitada` sem conta segue no caso de
# origem povoada, logo abaixo.
teste_sem_conta_origem_vazia_com_algo_a_apagar_e_recusada_mesmo_com_confirmar() {
  local base
  base=$(_cenario)
  : >"$base/conta_falha"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/valioso.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$(_exclusoes "$base")" 'conta nao identificada: zero exclusoes'
  assert_diferente 0 "$DBX_ESTADO" 'a execucao nao e o espelho pedido'
  assert_contem 'origem esta vazia' "$DBX_ERRO" 'recusada pela guarda de origem vazia'
}

teste_sem_conta_origem_povoada_transfere_e_nao_apaga() {
  local base
  base=$(_cenario)
  : >"$base/conta_falha"
  printf 'novo' >"$base/local/novo.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 1 "$(_harness_contar 'files/upload' "$base/chamadas")" 'a transferencia acontece'
  assert_igual 0 "$(_exclusoes "$base")" 'zero exclusoes'
  assert_diferente 0 "$DBX_ESTADO" 'codigo de saida diferente de 0'
  assert_contem 'exclusao_desabilitada=' "$DBX_SAIDA" 'motivo na saida estruturada'
}

teste_sem_conta_receber_espelhar_nao_apaga_local() {
  local base
  base=$(_cenario)
  : >"$base/conta_falha"
  printf 'meu' >"$base/local/so_local.txt"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/remoto.txt' 'ff' 15)" >"$base/listagem"
  _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
  assert_contem 'transferir=remoto.txt' "$DBX_SAIDA" "o recebimento segue; diagnostico: $DBX_ERRO"
  assert_arquivo_existe "$base/local/remoto.txt" 'o arquivo remoto foi recebido'
  assert_arquivo_existe "$base/local/so_local.txt" 'no sentido receber o arquivo local fica'
  assert_contem 'exclusao_desabilitada=' "$DBX_SAIDA" 'motivo na saida estruturada'
  assert_diferente 0 "$DBX_ESTADO" 'codigo de saida diferente de 0'
}

# Ciclo 3 (QA-P3-01, decisao do Tech Lead): memoria que EXISTE mas e descartada
# na carga mantem o par "visto" e zera a linha de base — a guarda de origem
# vazia (RF-41(b)) nao atua. A exclusao fica desabilitada naquela execucao, e a
# memoria e regravada em v2 para a execucao seguinte voltar ao normal.

# _memoria_v1 <base> — troca a memoria do par pela do formato anterior (v1).
_memoria_v1() {
  local memoria
  memoria=$(find "$1/estado/dbx" -name 'memoria-*' -print -quit)
  [[ -n $memoria ]] || _harness_falhar 'sem memoria-* para rebaixar'
  printf '1\0dbid:CONTA\0%s\0/r\0%s\t4\t1700000000\ta.txt\0' "$1/local" \
    "$(_hash_de "$1/local/a.txt")" >"$memoria"
}

teste_memoria_descartada_desabilita_a_exclusao_e_a_seguinte_volta_ao_normal() {
  local base
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  _antigo "$base/local/b.txt" 'bbbb'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "semeadura; diagnostico: $DBX_ERRO"
  _memoria_v1 "$base"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  : >"$base/chamadas"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual 0 "$(_exclusoes "$base")" 'memoria descartada: nenhuma exclusao'
  assert_diferente 0 "$DBX_ESTADO" 'a execucao nao e o espelho pedido'
  assert_contem 'exclusao_desabilitada=memoria descartada' "$DBX_SAIDA" 'motivo na saida estruturada'
  assert_igual 2 "$(tr '\0' '\n' <"$(find "$base/estado/dbx" -name 'memoria-*' -print -quit)" | head -1)" \
    'a memoria foi regravada em v2'
  : >"$base/chamadas"
  _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual 0 "$DBX_ESTADO" "a execucao seguinte volta ao normal; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_exclusoes "$base")" 'e volta a propagar a exclusao'
}

teste_enumeracao_remota_que_falha_sai_com_o_codigo_da_classe() {
  # QA-P3-03: o status era lido dentro de `if !`, onde vale 0.
  local base
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  # `path/not_found` na raiz remota e destino ainda vazio, e nao falha; uma
  # recusa de permissao (nao retentavel) e falha da enumeracao.
  printf '403' >"$base/listagem_codigo"
  printf '%s' '{"error_summary":"no_permission/.."}' >"$base/listagem"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_diferente 0 "$DBX_ESTADO" "enumeracao recusada nunca sai com sucesso; diagnostico: $DBX_ERRO"
  assert_igual "$(dbx_errors_codigo_saida "$(dbx_errors_classificar 403 'no_permission/..')")" "$DBX_ESTADO" \
    "enumeracao recusada sai com o codigo da classe; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_escritas "$base")" 'nada escrito sem a listagem remota'
}

teste_sync_com_segredo_vazio_recusa_antes_da_rede_na_classe_de_rf03() {
  # QA-P3-02: RF-63(a) ponta a ponta.
  local base
  base=$(_cenario)
  printf '%s' '{"versao":1,"app_key":"ak","app_secret":"","refresh_token":"rt","raiz_remota":"/"}' \
    >"$base/config/dbx/credencial.json"
  _antigo "$base/local/a.txt" 'aaaa'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_ESTADO" "classe de RF-03; diagnostico: $DBX_ERRO"
  assert_arquivo_ausente "$base/chamadas" 'nenhuma chamada de rede'
  assert_contem 'segredo' "$DBX_ERRO" 'o motivo nomeia o segredo'
}

# ---------------------------------------------------------------------------
# Ciclo 4 — guarda de origem vazia SEM depender da memoria (RF-41(b) emendado,
# memoria `2026-10-18-2243-guarda-origem-vazia`; QA-P3-05..07)
# ---------------------------------------------------------------------------

# _par_semeado <base> <sentido> <memoria> — prepara origem vazia com algo a
# apagar no destino e a memoria do par no estado pedido:
# valida | descartada | ilegivel | ausente.
_par_semeado() {
  local base=$1 sentido=$2 memoria=$3 arquivo
  if [[ $sentido == enviar ]]; then
    _antigo "$base/local/a.txt" 'aaaa'
    printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 4)" >"$base/listagem"
    if [[ $memoria != ausente ]]; then
      _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
    fi
    rm -f -- "$base/local/a.txt"
  else
    printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/a.txt' 'ff' 15)" >"$base/listagem"
    if [[ $memoria != ausente ]]; then
      _rodar "$base" sync --receber --origem /r --destino "$base/local" --espelhar --confirmar
    else
      printf 'local' >"$base/local/a.txt"
    fi
    printf '%s' '{"entries":[],"has_more":false}' >"$base/listagem"
  fi
  arquivo=$(find "$base/estado/dbx" -name 'memoria-*' -print -quit 2>/dev/null)
  case $memoria in
    descartada) printf '1\0dbid:CONTA\0x\0y\0' >"$arquivo" ;;
    ilegivel) chmod 000 "$arquivo" ;;
  esac
  : >"$base/chamadas"
}

teste_origem_vazia_com_algo_a_apagar_e_recusada_em_toda_combinacao() {
  [[ $EUID -ne 0 ]] || pular 'root le memoria sem permissao'
  local sentido memoria confirmar base recusa
  recusa=$(dbx_errors_codigo_saida nao_concluida)
  for sentido in enviar receber; do
    for memoria in valida descartada ilegivel ausente; do
      for confirmar in '' --confirmar; do
        base=$(_cenario)
        _par_semeado "$base" "$sentido" "$memoria"
        if [[ $sentido == enviar ]]; then
          _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar $confirmar
        else
          _rodar "$base" sync --receber --origem /r --destino "$base/local" --espelhar $confirmar
        fi
        assert_igual "$recusa" "$DBX_ESTADO" "$sentido/$memoria/${confirmar:-sem}: recusa; diagnostico: $DBX_ERRO"
        assert_igual 0 "$(_escritas "$base")" "$sentido/$memoria/${confirmar:-sem}: nenhuma escrita remota"
        [[ $sentido == receber ]] && assert_arquivo_existe "$base/local/a.txt" \
          "$sentido/$memoria/${confirmar:-sem}: o arquivo local fica"
      done
    done
  done
}

teste_origem_vazia_com_algo_a_apagar_traz_o_motivo_mesmo_com_confirmar() {
  local base
  base=$(_cenario)
  _par_semeado "$base" enviar ausente
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_contem 'origem esta vazia' "$DBX_ERRO" 'o motivo nomeia a origem vazia'
  assert_contem '--permitir-origem-vazia' "$DBX_ERRO" 'e a unica opcao que libera'
}

teste_permitir_origem_vazia_libera_a_exclusao_nos_dois_sentidos() {
  local base
  base=$(_cenario)
  _par_semeado "$base" enviar valida
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --permitir-origem-vazia
  assert_igual 0 "$DBX_ESTADO" "com a opcao a execucao segue; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_exclusoes "$base")" 'e apaga no destino'
  base=$(_cenario)
  _par_semeado "$base" receber valida
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --espelhar --permitir-origem-vazia
  assert_igual 0 "$DBX_ESTADO" "receber com a opcao segue; diagnostico: $DBX_ERRO"
  assert_arquivo_ausente "$base/local/a.txt" 'e apaga o local'
}

teste_simulacao_com_origem_vazia_anuncia_a_recusa_e_nao_lista_exclusao() {
  # RF-44 com RF-41(b) emendado: a previa sai com 0 e mostra que a execucao
  # real seria recusada.
  local base
  base=$(_cenario)
  _par_semeado "$base" enviar valida
  _rodar "$base" --json --dry-run sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual 0 "$DBX_ESTADO" "a simulacao sai com 0; diagnostico: $DBX_ERRO"
  assert_contem 'recusaria=origem vazia' "$DBX_SAIDA" 'o plano anuncia a recusa'
  assert_nao_contem 'apagar=a.txt' "$DBX_SAIDA" 'nenhuma exclusao listada'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'total de exclusoes zero'
  _rodar "$base" --dry-run sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_contem 'recusaria' "$DBX_SAIDA" 'e o relatorio legivel tambem'
  assert_igual 0 "$(_escritas "$base")" 'simulacao nao escreve'
}

teste_simulacao_com_permitir_origem_vazia_lista_as_exclusoes() {
  local base
  base=$(_cenario)
  _par_semeado "$base" enviar valida
  _rodar "$base" --json --dry-run sync --enviar --origem "$base/local" --destino /r --espelhar \
    --permitir-origem-vazia
  assert_igual 0 "$DBX_ESTADO" "a simulacao sai com 0; diagnostico: $DBX_ERRO"
  assert_contem 'apagar=a.txt' "$DBX_SAIDA" 'com a opcao, a exclusao e listada'
  assert_nao_contem 'recusaria' "$DBX_SAIDA" 'e nada e recusado'
}

teste_origem_vazia_com_destino_vazio_nao_e_recusada() {
  local base
  base=$(_cenario)
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "nada a apagar: nao ha o que recusar; diagnostico: $DBX_ERRO"
}

teste_travessia_parcial_nao_regrava_a_memoria() {
  # QA-P3-06: so a travessia COMPLETA regrava; com memoria descartada e um ramo
  # ilegivel, a v1 continua la, e a proxima execucao continua sem base.
  [[ $EUID -ne 0 ]] || pular 'root le diretorio sem permissao'
  local base memoria antes
  base=$(_cenario)
  mkdir -p "$base/local/ramo"
  _antigo "$base/local/a.txt" 'aaaa'
  _antigo "$base/local/ramo/b.txt" 'bbbb'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  memoria=$(find "$base/estado/dbx" -name 'memoria-*' -print -quit)
  printf '1\0dbid:CONTA\0x\0y\0' >"$memoria"
  antes=$(tr '\0' '|' <"$memoria")
  chmod 000 "$base/local/ramo"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r --espelhar
  chmod 755 "$base/local/ramo"
  assert_diferente 0 "$DBX_ESTADO" 'travessia parcial nao e espelho completo'
  assert_igual "$antes" "$(tr '\0' '|' <"$memoria")" 'com travessia parcial nada e gravado'
}

teste_raiz_relativa_e_absoluta_usam_a_mesma_memoria() {
  # TC-CAN-03 (RF-62(c)): o mesmo estado de "par visto" (RF-48).
  local base
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  (cd "$base" && _rodar "$base" sync --enviar --origem ./local --destino /r --espelhar &&
    printf '%s' "$DBX_ESTADO" >"$base/estado_relativo")
  assert_igual 0 "$(cat "$base/estado_relativo")" 'a raiz relativa ja conta como vista'
  assert_igual 1 "$(_quantas_memorias "$base")" 'uma unica memoria para as duas grafias'
}

teste_diretorio_de_estado_alheio_avisa_e_nao_muda_o_resultado() {
  # TC-EST-04 (RNF-25(b1)) ponta a ponta: nada e lido nem escrito no diretorio
  # alheio, o operador e avisado e o sync conclui com o codigo de sempre.
  [[ $EUID -ne 0 ]] || pular 'como root todo diretorio pertence ao usuario'
  local base
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  mkdir -p "$base/estado"
  ln -s /usr "$base/estado/dbx"
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "o sync conclui; diagnostico: $DBX_ERRO"
  assert_contem 'outro usuario' "$DBX_ERRO" 'o operador e avisado'
  assert_igual 0 "$(_quantas_memorias "$base")" 'nenhuma memoria gravada no diretorio alheio'
}

teste_sync_usa_a_memoria_sem_sqlite_nem_python_e_preserva_o_legado() {
  # TC-DEP-03 (RNF-02(c)) e TC-LEG-02 (RNF-33(b)).
  local base legado antes depois
  base=$(_cenario)
  _antigo "$base/local/a.txt" 'aaaa'
  mkdir -p "$base/estado/dbx"
  chmod 700 "$base/estado/dbx"
  for legado in dbx.db dbx.db-wal dbx.db-shm; do
    printf 'legado %s' "$legado" >"$base/estado/dbx/$legado"
    touch -d '@1600000000' "$base/estado/dbx/$legado"
  done
  antes=$(cd "$base/estado/dbx" && stat -c '%n %s %Y' dbx.db dbx.db-wal dbx.db-shm && cat dbx.db dbx.db-wal dbx.db-shm)
  _rodar "$base" sync --enviar --origem "$base/local" --destino /r
  _rodar "$base" --progresso sync --enviar --origem "$base/local" --destino /r
  assert_igual 0 "$DBX_ESTADO" "sync conclui; diagnostico: $DBX_ERRO"
  assert_contem 'em cache (memoria)' "$DBX_ERRO" 'a segunda execucao reaproveita a memoria'
  assert_nao_contem 'sqlite' "$DBX_ERRO" 'nenhum segundo nivel de cache'
  assert_arquivo_ausente "$base/proibido" 'nenhuma invocacao de sqlite3, python3 ou python'
  depois=$(cd "$base/estado/dbx" && stat -c '%n %s %Y' dbx.db dbx.db-wal dbx.db-shm && cat dbx.db dbx.db-wal dbx.db-shm)
  assert_igual "$antes" "$depois" 'dbx.db* intactos: conteudo e mtime'
}

# ---------------------------------------------------------------------------
# Fase 4 — aliases em ingles (RF-64), origem vazia pelo plano no `--receber`
# (RF-41(b), O-1, DIV-30) e localidade da comparacao sem caixa (RF-54(e)(f)(g))
# ---------------------------------------------------------------------------

# _rodar_com_ambiente <base> <atribuicoes> <argumentos...> — como `_rodar`, com
# atribuicoes extras (`NOME=valor`, separadas por espaco) no ambiente limpo.
_rodar_com_ambiente() {
  local base=$1 extra=$2
  shift 2
  local -a ambiente=()
  [[ -n $extra ]] && read -r -a ambiente <<<"$extra"
  DBX_SAIDA=''
  DBX_ERRO=''
  env -i PATH="$base/bin:$PATH" HOME="$base" XDG_CONFIG_HOME="$base/config" \
    XDG_STATE_HOME="$base/estado" TMPDIR="$DBX_TESTES_TMP" ${ambiente[@]+"${ambiente[@]}"} \
    bash "$DBX_EXEC" "$@" >"$base/out" 2>"$base/err"
  DBX_ESTADO=$?
  [[ -r $base/out ]] && IFS= read -r -d '' DBX_SAIDA <"$base/out"
  [[ -r $base/err ]] && IFS= read -r -d '' DBX_ERRO <"$base/err"
  return 0
}

# _plano_de <base> <argumentos do sync...> — saida do `--json --dry-run sync`,
# com o caminho temporario do cenario trocado por um marcador, para comparar
# planos de cenarios diferentes.
_plano_de() {
  local base=$1
  shift
  _rodar "$base" --json --dry-run sync "$@"
  printf '%s|%s' "$DBX_ESTADO" "${DBX_SAIDA//$base/BASE}"
}

# _cenario_de_plano <com_origem_vazia> — local com `novo.txt` (ou vazio) e
# remoto com `orfao.txt`, o que torna visiveis no plano o sentido, os lados, o
# espelhamento e a liberacao da origem vazia.
_cenario_de_plano() {
  local base
  base=$(_cenario)
  [[ $1 == sim ]] || printf 'novo' >"$base/local/novo.txt"
  printf '{"entries":[%s],"has_more":false}' "$(_entrada_remota '/r/orfao.txt' 'ff' 1)" >"$base/listagem"
  printf '%s' "$base"
}

teste_cada_alias_do_sync_produz_o_mesmo_plano_que_o_nome_em_portugues() {
  # TC-ALI-01, RF-64(a)(b): um caso por par. Cada linha troca UM nome pelo alias
  # e o plano da simulacao tem de ser identico ao do portugues.
  local -a pares=(
    '--origem|--source' '--destino|--dest' '--enviar|--push' '--espelhar|--mirror'
    '--confirmar|--yes' '--permitir-origem-vazia|--allow-empty-source'
  )
  local par pt en vazia esperado obtido base
  for par in "${pares[@]}"; do
    pt=${par%|*} en=${par#*|}
    vazia=nao
    [[ $pt == --permitir-origem-vazia ]] && vazia=sim
    local -a comando=(--enviar --origem LOCAL --destino /r --espelhar --confirmar)
    [[ $vazia == sim ]] && comando+=(--permitir-origem-vazia)
    base=$(_cenario_de_plano "$vazia")
    comando=("${comando[@]/#LOCAL/$base/local}")
    esperado=$(_plano_de "$base" "${comando[@]}")
    obtido=$(_plano_de "$base" "${comando[@]/#$pt/$en}")
    assert_contem '0|' "${esperado:0:2}" "$pt: o plano de referencia sai com 0 ($esperado)"
    assert_igual "$esperado" "$obtido" "$en: mesmo plano que $pt"
  done
  # `--pull` = `--receber`, no sentido inverso.
  base=$(_cenario_de_plano nao)
  esperado=$(_plano_de "$base" --receber --origem /r --destino "$base/local" --espelhar)
  obtido=$(_plano_de "$base" --pull --origem /r --destino "$base/local" --espelhar)
  assert_contem 'sentido=receber' "$esperado" 'o plano de referencia e de recebimento'
  assert_igual "$esperado" "$obtido" '--pull: mesmo plano que --receber'
}

teste_aliases_do_sync_todos_em_ingles_e_misturados_dao_o_mesmo_plano() {
  # TC-ALI-01, RF-64(d): misturar os dois idiomas e valido.
  local base pt en misto
  base=$(_cenario_de_plano nao)
  pt=$(_plano_de "$base" --enviar --origem "$base/local" --destino /r --espelhar --confirmar)
  en=$(_plano_de "$base" --push --source "$base/local" --dest /r --mirror --yes)
  misto=$(_plano_de "$base" --push --origem "$base/local" --dest /r --mirror --confirmar)
  assert_contem 'apagar=orfao.txt' "$pt" 'o plano de referencia lista a exclusao espelhada'
  assert_igual "$pt" "$en" 'todo em ingles: mesmo plano'
  assert_igual "$pt" "$misto" 'misto: mesmo plano'
}

teste_yes_reconhece_a_primeira_execucao_espelhada_como_confirmar() {
  # RF-64(b) com RF-48: o efeito de `--yes` so aparece na execucao real.
  local base
  base=$(_cenario_de_plano nao)
  _rodar "$base" sync --push --source "$base/local" --dest /r --mirror
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$DBX_ESTADO" 'sem reconhecimento, recusa'
  _rodar "$base" sync --push --source "$base/local" --dest /r --mirror --yes
  assert_igual 0 "$DBX_ESTADO" "--yes reconhece; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_exclusoes "$base")" 'e a exclusao espelhada acontece'
}

teste_aliases_do_sync_herdam_as_recusas() {
  # TC-ALI-01, RF-64(b)(e), DIV-31: o alias e a MESMA opcao.
  local base uso recusa
  uso=$(dbx_errors_codigo_saida uso_invalido)
  recusa=$(dbx_errors_codigo_saida nao_concluida)
  base=$(_cenario)
  _rodar "$base" sync --push --pull --source "$base/local" --dest /r
  assert_igual "$uso" "$DBX_ESTADO" '--push com --pull e uso invalido'
  assert_contem 'mutuamente exclusiv' "$DBX_ERRO" 'pela regra do sentido, e nao por opcao desconhecida'
  _rodar "$base" sync --enviar --push --origem "$base/local" --destino /r
  assert_igual "$uso" "$DBX_ESTADO" '--enviar --push repete o sentido: uso invalido'
  assert_contem 'mutuamente exclusiv' "$DBX_ERRO" '--enviar --push: mesma recusa de --enviar --enviar'
  _rodar "$base" sync --pull --receber --origem /r --destino "$base/local"
  assert_igual "$uso" "$DBX_ESTADO" '--pull --receber tambem'
  assert_contem 'mutuamente exclusiv' "$DBX_ERRO" '--pull --receber: mesma recusa'
  # Origem vazia com algo a apagar: `--yes` nao dispensa; so o alias de
  # `--permitir-origem-vazia` dispensa.
  base=$(_cenario_de_plano sim)
  _rodar "$base" sync --push --source "$base/local" --dest /r --mirror --yes
  assert_igual "$recusa" "$DBX_ESTADO" "--mirror --yes com origem vazia: recusa; diagnostico: $DBX_ERRO"
  assert_igual 0 "$(_escritas "$base")" 'recusa sem escrita'
  _rodar "$base" sync --push --source "$base/local" --dest /r --mirror --yes --allow-empty-source
  assert_igual 0 "$DBX_ESTADO" "--allow-empty-source dispensa; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_exclusoes "$base")" 'e a exclusao acontece'
}

teste_opcao_com_valor_repetida_por_alias_vale_o_ultimo() {
  # RF-64(e): `--origem a --source b` usa `b`; o mesmo para o destino.
  local base outro
  base=$(_cenario)
  outro=$(mktemp -d "$DBX_TESTES_TMP/outro.XXXXXX")
  _rodar "$base" --json --dry-run sync --push --origem /nao/existe --source "$outro" --dest /x --destino /r
  assert_igual 0 "$DBX_ESTADO" "o ultimo valor vale; diagnostico: $DBX_ERRO"
  assert_contem "origem=$outro" "$DBX_SAIDA" 'a origem e a do alias, dado por ultimo'
  assert_contem 'destino=/r' "$DBX_SAIDA" 'o destino e o do nome em portugues, dado por ultimo'
}

teste_ajuda_do_sync_lista_os_dois_nomes_de_cada_opcao() {
  # RF-64(c): o `Uso:` nao pode listar so o portugues.
  local base nome uso
  base=$(_cenario)
  _rodar "$base" help sync
  assert_igual 0 "$DBX_ESTADO" 'a ajuda sai com 0'
  uso=${DBX_SAIDA%%$'\n'*}
  for nome in --origem --source --destino --dest --enviar --push --receber --pull \
    --espelhar --mirror --confirmar --yes --permitir-origem-vazia --allow-empty-source; do
    assert_contem "$nome" "$uso" "o Uso: do sync lista $nome"
  done
}

teste_receber_espelhado_com_origem_vazia_recusa_pelo_plano_em_toda_memoria() {
  # TC-DEL-13 (RF-41(b) emendado por O-1): no `--receber` a recusa sai pelo
  # plano, como no `--enviar`, com memoria valida, descartada ou ausente, e
  # nenhuma mensagem cita a memoria.
  local memoria confirmar base recusa
  recusa=$(dbx_errors_codigo_saida nao_concluida)
  for memoria in valida descartada ausente; do
    for confirmar in '' --confirmar; do
      # Sem memoria o par nunca foi visto, e sem `--confirmar` quem recusa antes
      # e o reconhecimento da primeira execucao (RF-48), nao a origem vazia.
      [[ $memoria == ausente && -z $confirmar ]] && continue
      base=$(_cenario)
      _par_semeado "$base" receber "$memoria"
      _rodar "$base" --json sync --receber --origem /r --destino "$base/local" --espelhar $confirmar
      assert_igual "$recusa" "$DBX_ESTADO" "$memoria/${confirmar:-sem}: recusa; diagnostico: $DBX_ERRO"
      assert_contem 'recusada=origem vazia' "$DBX_SAIDA" "$memoria/${confirmar:-sem}: o plano traz a recusa"
      assert_contem 'a_apagar=0' "$DBX_SAIDA" "$memoria/${confirmar:-sem}: o plano nao lista exclusao"
      assert_nao_contem 'memoria registra' "$DBX_ERRO" "$memoria/${confirmar:-sem}: a recusa nao cita a memoria"
      assert_arquivo_existe "$base/local/a.txt" "$memoria/${confirmar:-sem}: o arquivo local fica"
    done
  done
}

teste_receber_espelhado_com_origem_vazia_simula_e_libera_como_o_enviar() {
  # TC-DEL-13: a simulacao nao muda; `--permitir-origem-vazia` libera.
  local base
  base=$(_cenario)
  _par_semeado "$base" receber valida
  _rodar "$base" --json --dry-run sync --receber --origem /r --destino "$base/local" --espelhar
  assert_igual 0 "$DBX_ESTADO" "a simulacao sai com 0; diagnostico: $DBX_ERRO"
  assert_contem 'recusaria=origem vazia' "$DBX_SAIDA" 'o plano anuncia a recusa'
  assert_arquivo_existe "$base/local/a.txt" 'simulacao nao apaga'
  _rodar "$base" sync --receber --origem /r --destino "$base/local" --espelhar --permitir-origem-vazia
  assert_igual 0 "$DBX_ESTADO" "a opcao libera; diagnostico: $DBX_ERRO"
  assert_arquivo_ausente "$base/local/a.txt" 'e a exclusao acontece'
}

teste_origem_vazia_sem_espelhar_e_operacao_vazia_com_saida_zero() {
  # DIV-30 (decisao do Tech Lead): sem `--espelhar` nada seria apagado, e a
  # guarda antiga, anterior ao plano, recusava pela memoria. Nos dois sentidos.
  local base sentido
  for sentido in receber enviar; do
    base=$(_cenario)
    _par_semeado "$base" "$sentido" valida
    if [[ $sentido == receber ]]; then
      _rodar "$base" --json sync --receber --origem /r --destino "$base/local"
    else
      _rodar "$base" --json sync --enviar --origem "$base/local" --destino /r
    fi
    assert_igual 0 "$DBX_ESTADO" "$sentido sem --espelhar: operacao vazia; diagnostico: $DBX_ERRO"
    assert_nao_contem 'recusad' "$DBX_SAIDA" "$sentido: o plano nao anuncia recusa"
    assert_igual 0 "$(_escritas "$base")" "$sentido: nenhuma escrita remota"
    [[ $sentido == receber ]] && assert_arquivo_existe "$base/local/a.txt" 'receber: o local fica'
  done
  return 0
}

teste_raiz_local_inexistente_continua_recusada() {
  # RF-41(b): a remocao da guarda antiga nao alcanca a raiz inexistente.
  local base
  base=$(_cenario)
  _rodar "$base" sync --enviar --origem "$base/nao_existe" --destino /r --espelhar --confirmar
  assert_igual "$(dbx_errors_codigo_saida nao_encontrado)" "$DBX_ESTADO" 'raiz inexistente e recusada'
  assert_igual 0 "$(_escritas "$base")" 'sem escrita'
}

readonly E_AGUDO_MAIUSCULO=$'\xc3\x89'
readonly E_AGUDO_MINUSCULO=$'\xc3\xa9'

teste_caixa_fora_do_ascii_e_um_caminho_mesmo_com_lc_all_c() {
  # TC-CX-04 (RF-54(e), DIV-32): `LC_ALL=C` no ambiente nao anula a fixacao,
  # que vale so dentro da comparacao.
  local base local_nome remoto_nome
  local_nome="${E_AGUDO_MAIUSCULO}a.txt"
  remoto_nome="${E_AGUDO_MINUSCULO}a.txt"
  base=$(_cenario)
  printf 'novo' >"$base/local/$local_nome"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota "/r/$remoto_nome" "$RESUMO_ZERADO" 4)" >"$base/listagem"
  _rodar_com_ambiente "$base" 'LC_ALL=C LANG=C' --json sync --enviar --origem "$base/local" \
    --destino /r --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem "transferir=$local_nome" "$DBX_SAIDA" 'o conteudo divergente e enviado'
  assert_contem 'a_apagar=0' "$DBX_SAIDA" 'o par nao entra no plano de exclusao'
  assert_igual 0 "$(_exclusoes "$base")" 'o --espelhar nao apaga o recem-enviado'
  assert_contem "/r/$remoto_nome" "$(cat "$base/opcoes")" 'a escrita usa a grafia do destino'
  assert_nao_contem 'C.UTF-8' "$DBX_ERRO" 'com a localidade presente nao ha aviso'
}

teste_caixa_fora_do_ascii_com_conteudo_igual_e_omitida_com_lc_all_c() {
  local base resumo
  base=$(_cenario)
  printf 'igual' >"$base/local/${E_AGUDO_MAIUSCULO}.txt"
  resumo=$(_resumo_de "$base/local/${E_AGUDO_MAIUSCULO}.txt")
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota "/r/${E_AGUDO_MINUSCULO}.txt" "$resumo" 5)" >"$base/listagem"
  _rodar_com_ambiente "$base" 'LC_ALL=C' --json sync --enviar --origem "$base/local" --destino /r \
    --espelhar --confirmar
  assert_igual 0 "$DBX_ESTADO" "sync deve concluir; diagnostico: $DBX_ERRO"
  assert_contem 'identicos=1' "$DBX_SAIDA" 'o mesmo arquivo e omitido'
  assert_igual 0 "$(_escritas "$base")" 'nenhuma escrita'
}

teste_comparacao_sem_caixa_nao_muda_medida_em_bytes() {
  # RF-54(e): a fixacao nao vaza da comparacao. Sob `LC_ALL=C`, nome multibyte
  # continua medido em bytes antes e depois dela, e `lib/json` o preserva.
  local saida
  saida=$(env -i LC_ALL=C bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/progress.sh"; . "$1/lib/json.sh"; . "$1/lib/sync.sh"
    nome=$2
    antes=${#nome}
    _dbx_sync_chave "$nome"
    chave=$DBX_SYNC_CHAVE
    depois=${#nome}
    dbx_json_escapar_cadeia "$nome"
    printf "%s|%s|%s|%s" "$antes" "$depois" "${#chave}" "$([[ $DBX_JSON_ESCAPADO == "$nome" ]] && echo igual)"
  ' _ "$DBX_HARNESS_RAIZ" "${E_AGUDO_MAIUSCULO}a.txt")
  assert_igual '7|7|7|igual' "$saida" 'medidas em bytes antes e depois da comparacao, e json intacto'
}

teste_localidade_ausente_avisa_uma_vez_e_compara_so_no_ascii() {
  # TC-CX-05 (RF-54(f)): a ausencia e simulada pelo nome da localidade, sem
  # depender da maquina do teste.
  local base local_nome remoto_nome
  local_nome="${E_AGUDO_MAIUSCULO}a.txt"
  remoto_nome="${E_AGUDO_MINUSCULO}a.txt"
  base=$(_cenario)
  printf 'novo' >"$base/local/$local_nome"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota "/r/$remoto_nome" "$RESUMO_ZERADO" 4)" >"$base/listagem"
  _rodar_com_ambiente "$base" 'LC_ALL=C DBX_SYNC_LOCALIDADE=xx_XX.inexistente' --json --dry-run \
    sync --enviar --origem "$base/local" --destino /r --espelhar
  assert_igual 0 "$DBX_ESTADO" "o aviso nao recusa; diagnostico: $DBX_ERRO"
  assert_igual 1 "$(_harness_contar 'comparacao sem caixa' "$base/err")" 'um aviso so, no stderr'
  assert_contem 'ausente' "$DBX_ERRO" 'o aviso nomeia a causa'
  assert_contem 'so no ASCII' "$DBX_ERRO" 'e o efeito'
  assert_nao_contem 'comparacao sem caixa' "$DBX_SAIDA" 'a saida padrao nao recebe o aviso'
  assert_contem "transferir=$local_nome" "$DBX_SAIDA" 'fora do ASCII as chaves sao distintas'
  assert_contem "apagar=$remoto_nome" "$DBX_SAIDA" 'e o remoto vira candidato a exclusao'
}

teste_localidade_ausente_nao_muda_saida_nem_codigo_no_ascii() {
  # RF-54(f): no ASCII o resultado e o mesmo de uma execucao sem aviso.
  local base com sem
  base=$(_cenario)
  printf 'novo' >"$base/local/Foto.JPG"
  printf '{"entries":[%s],"has_more":false}' \
    "$(_entrada_remota '/r/foto.jpg' "$RESUMO_ZERADO" 4)" >"$base/listagem"
  _rodar_com_ambiente "$base" '' --json --dry-run sync --enviar --origem "$base/local" --destino /r --espelhar
  sem="$DBX_ESTADO|$DBX_SAIDA"
  _rodar_com_ambiente "$base" 'DBX_SYNC_LOCALIDADE=xx_XX.inexistente' --json --dry-run sync --enviar \
    --origem "$base/local" --destino /r --espelhar
  com="$DBX_ESTADO|$DBX_SAIDA"
  assert_contem 'comparacao sem caixa' "$DBX_ERRO" 'o aviso sai'
  assert_igual "$sem" "$com" 'codigo e saida padrao iguais aos da execucao sem aviso'
}

teste_aviso_de_localidade_e_so_do_sync() {
  # RF-54(g): so o `sync` compara caminhos sem caixa.
  local base
  base=$(_cenario)
  _rodar_com_ambiente "$base" 'DBX_SYNC_LOCALIDADE=xx_XX.inexistente' list /r
  assert_igual 0 "$DBX_ESTADO" "list conclui; diagnostico: $DBX_ERRO"
  assert_nao_contem 'comparacao sem caixa' "$DBX_ERRO" 'list nao avisa'
}

harness_executar "$@"
