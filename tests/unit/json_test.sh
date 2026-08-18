#!/usr/bin/env bash
# Testes de lib/json.sh — interpretacao de resposta JSON sem `jq` (RNF-11).
#
# Este componente le resposta de servico externo NAO CONFIAVEL em shell puro.
# E exatamente onde o projeto de referencia erra, extraindo campo com expressao
# regular por `sed` (DIV-04). Entrada malformada precisa falhar FECHADA e
# CLASSIFICADA, nunca em silencio.

# shellcheck disable=SC2016
# Justificativa: varios casos usam cadeias com `$`, `\` e chaves como DADO de
# teste, e entregam script literal a "bash -c", que precisa chegar sem expansao.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"

# _valor <json> <segmentos...> — analisa e consulta NO SHELL CORRENTE, deixando
# o resultado em DBX_JSON_RESULTADO. Nao pode ser chamada dentro de `$( )`: a
# analise em subshell perderia o estado, e e justamente o defeito E2-09.
_valor() {
  local json=$1
  shift
  dbx_json_analisar "$json" || return $?
  dbx_json_valor "$@" >/dev/null || return $?
}

# ---------------------------------------------------------------------------
# Formas basicas
# ---------------------------------------------------------------------------

teste_objeto_simples() {
  _valor '{".tag":"file","name":"a.txt"}' '.tag'
  assert_igual 'file' "$DBX_JSON_RESULTADO"
  _valor '{".tag":"file","name":"a.txt"}' name
  assert_igual 'a.txt' "$DBX_JSON_RESULTADO"
}

teste_tipos_escalares() {
  local json='{"s":"texto","n":42,"f":-1.5,"e":2.5e3,"b":true,"z":false,"nulo":null}'
  _valor "$json" s
  assert_igual 'texto' "$DBX_JSON_RESULTADO"
  _valor "$json" n
  assert_igual '42' "$DBX_JSON_RESULTADO"
  _valor "$json" f
  assert_igual '-1.5' "$DBX_JSON_RESULTADO"
  _valor "$json" e
  assert_igual '2.5e3' "$DBX_JSON_RESULTADO"
  _valor "$json" b
  assert_igual 'true' "$DBX_JSON_RESULTADO"
  _valor "$json" z
  assert_igual 'false' "$DBX_JSON_RESULTADO"
  _valor "$json" nulo
  assert_igual '' "$DBX_JSON_RESULTADO"
  dbx_json_analisar "$json"
  assert_igual 'cadeia' "$(dbx_json_tipo s)"
  assert_igual 'numero' "$(dbx_json_tipo n)"
  assert_igual 'booleano' "$(dbx_json_tipo b)"
  assert_igual 'nulo' "$(dbx_json_tipo nulo)"
}

teste_aninhamento_e_arranjo() {
  local json='{"entries":[{"name":"a"},{"name":"b"}],"has_more":false}'
  _valor "$json" entries 0 name
  assert_igual 'a' "$DBX_JSON_RESULTADO"
  _valor "$json" entries 1 name
  assert_igual 'b' "$DBX_JSON_RESULTADO"
  _valor "$json" has_more
  assert_igual 'false' "$DBX_JSON_RESULTADO"
  dbx_json_analisar "$json"
  assert_igual 2 "$(dbx_json_tamanho_arranjo entries)"
}

teste_objeto_e_arranjo_vazios_e_cadeia_vazia() {
  assert_sucesso dbx_json_analisar '{}'
  assert_sucesso dbx_json_analisar '[]'
  _valor '{"vazia":""}' vazia
  assert_igual '' "$DBX_JSON_RESULTADO"
  dbx_json_analisar '{"o":{},"a":[]}'
  assert_igual 'objeto' "$(dbx_json_tipo o)"
  assert_igual 'arranjo' "$(dbx_json_tipo a)"
  assert_igual 0 "$(dbx_json_tamanho_arranjo a)"
}

teste_aninhamento_profundo_valido() {
  local json='{"a":{"b":{"c":{"d":{"e":"fundo"}}}}}'
  _valor "$json" a b c d e
  assert_igual 'fundo' "$DBX_JSON_RESULTADO"
}

teste_arranjo_de_arranjo() {
  _valor '{"m":[["x","y"],["z"]]}' m 0 0
  assert_igual 'x' "$DBX_JSON_RESULTADO"
  _valor '{"m":[["x","y"],["z"]]}' m 1 0
  assert_igual 'z' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# Escapes — a superficie mais escorregadia
# ---------------------------------------------------------------------------

teste_escapes_simples() {
  _valor '{"v":"a\"b"}' v
  assert_igual 'a"b' "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\\b"}' v
  assert_igual 'a\b' "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\/b"}' v
  assert_igual 'a/b' "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\tb"}' v
  assert_igual "$(printf 'a\tb')" "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\nb"}' v
  assert_igual "$(printf 'a\nb')" "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\rb"}' v
  assert_igual "$(printf 'a\rb')" "$DBX_JSON_RESULTADO"
}

teste_quebra_de_linha_no_valor_e_preservada_byte_a_byte() {
  # A leitura por DBX_JSON_RESULTADO existe justamente porque `$( )` remove
  # quebras finais — licao fixada na Etapa 1.
  dbx_json_analisar '{"v":"linha\n"}'
  dbx_json_valor v
  assert_igual "linha"$'\n' "$DBX_JSON_RESULTADO" \
    'quebra de linha final do valor nao pode ser descartada'
}

teste_escape_unicode() {
  _valor '{"v":"café"}' v
  assert_igual 'café' "$DBX_JSON_RESULTADO"
  _valor '{"v":"A"}' v
  assert_igual 'A' "$DBX_JSON_RESULTADO"
}

teste_escape_unicode_com_par_surrogate() {
  # U+1F600 codificado como par surrogate, forma obrigatoria em JSON.
  _valor '{"v":"😀"}' v
  assert_igual '😀' "$DBX_JSON_RESULTADO"
}

teste_utf8_multibyte_direto() {
  _valor '{"v":"ação"}' v
  assert_igual 'ação' "$DBX_JSON_RESULTADO"
  _valor '{"ação":"ação"}' 'ação'
  assert_igual 'ação' "$DBX_JSON_RESULTADO"
}

teste_delimitadores_dentro_de_cadeia_nao_estruturam() {
  # Chaves, colchetes, virgulas e dois-pontos dentro de cadeia sao conteudo.
  local json='{"v":"{[,:]} nao e estrutura","w":"ok"}'
  _valor "$json" v
  assert_igual '{[,:]} nao e estrutura' "$DBX_JSON_RESULTADO"
  _valor "$json" w
  assert_igual 'ok' "$DBX_JSON_RESULTADO"
}

teste_barra_invertida_antes_de_aspa_final() {
  # `"a\\"` termina a cadeia; `"a\"` nao. Distinguir os dois e o teste real.
  _valor '{"v":"a\\","w":"depois"}' v
  assert_igual $'a\\' "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\\","w":"depois"}' w
  assert_igual 'depois' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# Robustez a variacao de formatacao (RNF-11)
# ---------------------------------------------------------------------------

teste_espacamento_e_ordem_nao_afetam() {
  local a='{"x":1,"y":2}'
  local b='{  "y" : 2 ,
     "x"  :  1  }'
  local de_a
  _valor "$a" x
  de_a=$DBX_JSON_RESULTADO
  _valor "$b" x
  assert_igual "$de_a" "$DBX_JSON_RESULTADO" 'espacamento e ordem nao alteram o valor'
  _valor "$b" y
  assert_igual '2' "$DBX_JSON_RESULTADO"
}

teste_chave_duplicada_vence_a_ultima() {
  # Comportamento precisa ser DEFINIDO, e nao acidental.
  _valor '{"v":"primeiro","v":"segundo"}' v
  assert_igual 'segundo' "$DBX_JSON_RESULTADO"
}

teste_valor_contendo_delimitadores_de_erro_da_dropbox() {
  local json='{"error_summary":"path/not_found/.","error":{".tag":"path"}}'
  _valor "$json" error_summary
  assert_igual 'path/not_found/.' "$DBX_JSON_RESULTADO"
  _valor "$json" error '.tag'
  assert_igual 'path' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# Entrada malformada — falha fechada e classificada
# ---------------------------------------------------------------------------

teste_entrada_malformada_e_recusada() {
  local ruim
  for ruim in '{"a":1' '{"a"1}' '{"a":}' '{,}' '{"a":1,}' '[1,]' '{"a":1}extra' \
    '{"a":"nao fechada}' 'nao_e_json' '' '{"a":01}' '{"a":+1}' '{"a":tru}'; do
    if dbx_json_analisar "$ruim" 2>/dev/null; then
      _harness_falhar "entrada malformada foi aceita: [$ruim]"
    fi
  done
}

teste_falha_e_classificada_e_nao_silenciosa() {
  dbx_json_analisar '{"a":1' 2>/dev/null
  assert_igual 'malformado' "$DBX_JSON_MOTIVO" 'o motivo precisa ser identificavel'
  assert_diferente '' "$DBX_JSON_ERRO" 'a falha precisa ter mensagem'
}

teste_profundidade_excessiva_e_recusada() {
  local json='' i
  for ((i = 0; i < 200; i++)); do json+='{"a":'; done
  json+='1'
  for ((i = 0; i < 200; i++)); do json+='}'; done
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$json"
  dbx_json_analisar "$json" 2>/dev/null
  assert_igual 'profundidade' "$DBX_JSON_MOTIVO"
}

teste_entrada_gigante_e_recusada_pelo_teto() {
  local json
  json="{\"v\":\"$(printf 'x%.0s' $(seq 1 200))\"}"
  assert_sucesso dbx_json_analisar "$json"
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$(printf 'y%.0s' $(seq 1 $((DBX_JSON_MAXIMO_ENTRADA + 10))))"
}

teste_apos_falha_nao_ha_resultado_residual() {
  dbx_json_analisar '{"v":"bom"}'
  dbx_json_valor v
  dbx_json_analisar '{"v":' 2>/dev/null
  assert_status 1 dbx_json_valor v
  assert_igual '' "$DBX_JSON_RESULTADO" 'resultado anterior nao pode sobreviver a falha'
}

teste_caminho_inexistente_falha_sem_inventar_valor() {
  dbx_json_analisar '{"a":1}'
  assert_status 1 dbx_json_valor b
  assert_status 1 dbx_json_valor a b
  assert_igual '' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# Direcao de dependencia e ausencia de jq
# ---------------------------------------------------------------------------

teste_nao_usa_jq_nem_sed_por_campo() {
  local alvo="$DBX_HARNESS_RAIZ/lib/json.sh" codigo
  assert_arquivo_existe "$alvo"
  codigo=$(grep -vE '^[[:space:]]*#' "$alvo")
  if printf '%s\n' "$codigo" | grep -qE '(^|[^_a-zA-Z.])jq([^_a-zA-Z]|$)'; then
    _harness_falhar 'lib/json.sh invoca jq, contrariando a decisao do solicitante'
  fi
  if printf '%s\n' "$codigo" | grep -qE '(^|[^_a-zA-Z])(sed|awk|perl|python3?)([^_a-zA-Z]|$)'; then
    _harness_falhar 'lib/json.sh delega a interpretador externo'
  fi
}

teste_custo_com_corpus_adversarial() {
  # Corpus denso em delimitadores e escapes, sob tempo limite em processo filho:
  # regressao de custo deve REPROVAR, nao pendurar a suite.
  local saida status
  saida=$(timeout 60 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/json.sh"   || exit 90
    . "$1/tests/support/harness.sh" || exit 90
    gera() { local n=$1 s="{\"e\":[" i
      for ((i=0;i<n;i++)); do [[ $i -gt 0 ]] && s+=","
        s+="{\"n\":\"a\\\\\"b$i\",\"p\":\"/x/y$i\",\"s\":$i}"
      done; s+="]}"; printf "%s" "$s"; }
    for n in 100 200 400; do
      c=$(gera "$n"); t0=$(_agora_ms); dbx_json_analisar "$c" >/dev/null; t1=$(_agora_ms)
      printf "%s " "$((t1 - t0))"
    done
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  status=$?
  [[ $status -eq 124 ]] && _harness_falhar 'analise nao terminou em 60s com corpus adversarial'
  assert_igual 0 "$status" 'a medicao precisa concluir'
  local -a t
  read -r -a t <<<"$saida"
  [[ ${#t[@]} -eq 3 ]] || _harness_falhar "medicao invalida: [$saida]"
  local primeiro=${t[0]} ultimo=${t[2]}
  [[ $primeiro -lt 1 ]] && primeiro=1
  if [[ $ultimo -gt $((primeiro * 12)) ]]; then
    _harness_falhar "custo super-linear: 100 em ${primeiro}ms, 400 em ${ultimo}ms"
  fi
}

# ---------------------------------------------------------------------------
# E2-01 / E2-02 — injecao no espaco de chaves pelo delimitador em banda.
#
# O remedio adotado nao e ordem de operacoes, e sim eliminar a concatenacao de
# caminho: a unica composicao restante e `<id do pai><sep><segmento>`, e ela e
# injetiva porque o lado esquerdo e sempre digito. Estes casos ficam como
# regressao permanente da classe.
# ---------------------------------------------------------------------------

teste_separador_em_chave_por_escape_unicode_nao_desloca_campo() {
  # `a\u001fb` decodifica para o separador interno. Antes, o valor dessa chave
  # respondia por `a` -> `b`, permitindo substituir content_hash, rev ou cursor.
  _valor '{"a":{"b":"LEGITIMO"},"a\u001fb":"INJETADO"}' a b
  assert_igual 'LEGITIMO' "$DBX_JSON_RESULTADO" \
    'chave com separador nao pode designar outro campo'
}

teste_separador_em_chave_nas_duas_ordens() {
  _valor '{"a\u001fb":"INJETADO","a":{"b":"LEGITIMO"}}' a b
  assert_igual 'LEGITIMO' "$DBX_JSON_RESULTADO" 'ordem inversa tambem'
}

teste_sentinela_de_documento_em_chave_nao_sequestra_a_raiz() {
  dbx_json_analisar '{"\u001e":"SEQUESTRO","real":"ok"}'
  dbx_json_valor real >/dev/null
  assert_igual 'ok' "$DBX_JSON_RESULTADO"
  assert_sucesso dbx_json_existe "$(printf '\036')"
}

teste_chave_contendo_separador_e_enderecavel_por_si() {
  local chave
  chave="a$(printf '\037')b"
  _valor '{"a\u001fb":"VALOR-PROPRIO"}' "$chave"
  assert_igual 'VALOR-PROPRIO' "$DBX_JSON_RESULTADO" \
    'a chave com separador designa o proprio campo, e nao outro'
}

# ---------------------------------------------------------------------------
# E2-03 — chave vazia e JSON valido
# ---------------------------------------------------------------------------

teste_chave_vazia_e_aceita_e_enderecavel() {
  _valor '{"":"vazia"}' ''
  assert_igual 'vazia' "$DBX_JSON_RESULTADO"
  _valor '{"a":{"":"aninhada"}}' a ''
  assert_igual 'aninhada' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# E2-04 — quebra de linha final em chave
# ---------------------------------------------------------------------------

teste_chave_terminada_em_quebra_de_linha_nao_entrega_outro_campo() {
  local com_quebra
  # `$(printf '\n')` removeria justamente a quebra final que este caso existe
  # para verificar — a armadilha e a mesma que o teste denuncia.
  com_quebra=$'k\n'
  dbx_json_analisar '{"k":"SEM-QUEBRA","k\n":"COM-QUEBRA"}'
  dbx_json_valor "$com_quebra" >/dev/null
  assert_igual 'COM-QUEBRA' "$DBX_JSON_RESULTADO" \
    'a chave terminada em quebra de linha designa o proprio campo'
  dbx_json_valor k >/dev/null
  assert_igual 'SEM-QUEBRA' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# E2-08 — chave duplicada nao pode deixar filhas fantasma
# ---------------------------------------------------------------------------

teste_chave_duplicada_nao_deixa_filha_fantasma() {
  dbx_json_analisar '{"o":{"antiga":1},"o":{"nova":2}}'
  assert_status 1 dbx_json_valor o antiga
  dbx_json_valor o nova >/dev/null
  assert_igual '2' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# E2-09 — estado obsoleto nunca pode responder em silencio
# ---------------------------------------------------------------------------

teste_analise_em_subshell_sobre_estado_alheio_e_recusada() {
  dbx_json_analisar '{"antigo":"A"}'
  local status
  status=$( (dbx_json_analisar '{"novo":"B"}') >/dev/null 2>&1; echo $? )
  assert_diferente 0 "$status" \
    'analisar em subshell sobre estado de outro processo precisa falhar'
}

teste_consulta_apos_analise_perdida_nao_responde_pelo_documento_novo() {
  dbx_json_analisar '{"antigo":"A"}'
  ( dbx_json_analisar '{"novo":"B"}' ) >/dev/null 2>&1
  assert_status 1 dbx_json_valor novo
}

# ---------------------------------------------------------------------------
# E2-11 — o teto de profundidade declarado precisa ser o efetivo
# ---------------------------------------------------------------------------

teste_teto_de_profundidade_declarado_e_o_efetivo() {
  local json='' i
  for ((i = 1; i < DBX_JSON_MAXIMO_PROFUNDIDADE; i++)); do json+='{"a":'; done
  json+='1'
  for ((i = 1; i < DBX_JSON_MAXIMO_PROFUNDIDADE; i++)); do json+='}'; done
  assert_sucesso dbx_json_analisar "$json"
}

# ---------------------------------------------------------------------------
# G-01 e G-02 — lacunas apontadas por mutacao do QA
# ---------------------------------------------------------------------------

teste_caractere_de_controle_cru_e_recusado() {
  # G-01: e a defesa contra colisao com o separador da marcacao, e estava sem
  # teste — a mutacao que a removia nao reprovava nada.
  local json
  json="{\"a$(printf '\001')b\":1}"
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$json"
  dbx_json_analisar "$json" 2>/dev/null
  assert_igual 'controle' "$DBX_JSON_MOTIVO"
  json="{\"v\":\"x$(printf '\037')y\"}"
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$json"
}

teste_teto_de_entrada_e_aplicado() {
  # G-02: um requisito derivado de um valor nao testado nao tem sustentacao.
  local grande
  grande="{\"v\":\"$(printf 'x%.0s' $(seq 1 $((DBX_JSON_MAXIMO_ENTRADA + 100))))\"}"
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$grande"
  dbx_json_analisar "$grande" 2>/dev/null
  assert_igual 'tamanho' "$DBX_JSON_MOTIVO" \
    'o motivo precisa permitir ao chamador reduzir o limite de pagina, e nao abortar'
}

# ---------------------------------------------------------------------------
# Invariante de projeto: canal de dado externo nunca passa por `$( )`
# ---------------------------------------------------------------------------

teste_nenhum_valor_externo_transita_por_substituicao_de_comando() {
  # Terceira ocorrencia da classe no projeto (D1, C2-01, E2-04). A auditoria
  # estatica torna a regra verificavel, em vez de depender de disciplina.
  # A regra vale para canal que possa carregar BYTE ARBITRARIO vindo de fora.
  # Captura de valor de alfabeto fechado e comprimento limitado — codigo de
  # saida, nome de classe, resumo hexadecimal — nao perde informacao por
  # remocao de quebra final, e esta listada como excecao justificada.
  local arquivo codigo achados
  local permitidos='dbx_errors_codigo_saida|dbx_errors_classificar|_dbx_errors_classe_da_tag|_dbx_hash_sha256_hex|_dbx_hash_calcular'
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh; do
    codigo=$(grep -vE '^[[:space:]]*#' "$arquivo")
    # O padrao anterior exigia o `$(` LOGO APOS o `=`, entao `+=" ... $(...)"`
    # escapava — e havia uma ocorrencia viva. Uma garantia que so pega a forma
    # mais obvia da classe da falsa seguranca (E3-04). Agora qualquer
    # substituicao de comando sobre funcao do projeto e sinalizada, em qualquer
    # posicao da linha.
    achados=$(printf '%s\n' "$codigo" | grep -nE '[$]\((_dbx_|dbx_)' |
      grep -vE "[$]\\((${permitidos})" || true)
    if [[ -n $achados ]]; then
      _harness_falhar "captura de canal de dado externo por substituicao de comando em $(basename "$arquivo"): $achados" \
        'use variavel de resultado: a substituicao de comando remove quebras finais'
    fi
  done
}

# ---------------------------------------------------------------------------
# E3-02 — enumeracao inequivoca
# ---------------------------------------------------------------------------

teste_enumeracao_por_indice_devolve_o_nome_exato() {
  dbx_json_analisar '{"a":1,"b\nc":2}'
  dbx_json_nome_da_filha 1 >/dev/null
  assert_igual $'b\nc' "$DBX_JSON_RESULTADO" \
    'o nome da filha precisa vir byte a byte, sem depender de delimitador'
  dbx_json_nome_da_filha 0 >/dev/null
  assert_igual 'a' "$DBX_JSON_RESULTADO"
  assert_status 1 dbx_json_nome_da_filha 9
  assert_status "$DBX_JSON_ERRO_USO" dbx_json_nome_da_filha nao_numero
}

teste_enumeracao_terminada_por_nulo_nao_e_ambigua() {
  local registros linhas
  dbx_json_analisar '{"a":1,"b\nc":2}'
  registros=$(dbx_json_chaves_nul | tr -cd '\0' | wc -c)
  linhas=$(dbx_json_chaves | wc -l)
  assert_igual 2 "$registros" 'um registro por filha, mesmo com quebra de linha no nome'
  assert_igual 3 "$linhas" \
    'a forma por linhas permanece ambigua por construcao, e por isso e so conveniencia'
}

# ---------------------------------------------------------------------------
# E3-03 — contador e enumeracao precisam concordar
# ---------------------------------------------------------------------------

teste_contador_e_enumeracao_concordam_com_chave_duplicada() {
  local total nomes
  dbx_json_analisar '{"o":{"a":1},"o":{"b":2}}'
  total=$(dbx_json_tamanho_arranjo)
  nomes=$(dbx_json_chaves_nul | tr -cd '\0' | wc -c)
  assert_igual "$nomes" "$total" \
    'o contador precisa medir chaves distintas, e nao ocorrencias sintaticas'
  assert_igual 1 "$total"
}

# ---------------------------------------------------------------------------
# E3-06 — o estado precisa ser limpo entre analises
# ---------------------------------------------------------------------------

teste_analise_seguinte_nao_herda_nos_da_anterior() {
  dbx_json_analisar '{"antigo":{"interno":1}}'
  dbx_json_analisar '{"novo":2}'
  assert_status 1 dbx_json_valor antigo
  assert_status 1 dbx_json_valor antigo interno
  dbx_json_valor novo >/dev/null
  assert_igual '2' "$DBX_JSON_RESULTADO"
  assert_igual 1 "$(dbx_json_tamanho_arranjo)" 'a raiz nova nao pode contar filhas antigas'
}

harness_executar "$@"
