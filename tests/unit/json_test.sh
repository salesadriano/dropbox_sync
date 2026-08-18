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
  assert_igual $'a\tb' "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\nb"}' v
  assert_igual $'a\nb' "$DBX_JSON_RESULTADO"
  _valor '{"v":"a\rb"}' v
  assert_igual $'a\rb' "$DBX_JSON_RESULTADO"
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
  local recheio
  printf -v recheio 'x%.0s' $(seq 1 200)
  json="{\"v\":\"$recheio\"}"
  assert_sucesso dbx_json_analisar "$json"
  local acima_do_teto
  printf -v acima_do_teto 'y%.0s' $(seq 1 $((DBX_JSON_MAXIMO_ENTRADA + 10)))
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$acima_do_teto"
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
  saida=$(timeout 120 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/json.sh"   || exit 90
    . "$1/tests/support/harness.sh" || exit 90
    gera() { local n=$1 s="{\"e\":[" i
      for ((i=0;i<n;i++)); do [[ $i -gt 0 ]] && s+=","
        s+="{\"n\":\"a\\\\\"b$i\",\"p\":\"/x/y$i\",\"s\":$i}"
      done; s+="]}"; printf "%s" "$s"; }
    _analisar() { dbx_json_analisar "$1"; }
    c1=$(gera 100); c4=$(gera 400)
    printf "%s %s\n" "$(_medir_minimo_ms 5 _analisar "$c1")" "$(_medir_minimo_ms 5 _analisar "$c4")"
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  status=$?
  [[ $status -eq 124 ]] && _harness_falhar 'analise nao terminou em 120s com corpus adversarial'
  assert_igual 0 "$status" 'a medicao precisa concluir'
  local -a t
  read -r -a t <<<"$saida"
  [[ ${#t[@]} -eq 2 ]] || _harness_falhar "medicao invalida: [$saida]"
  # Razao entre MINIMOS: contencao so soma tempo, entao o minimo converge para o
  # custo real e a razao fica insensivel a carga da maquina.
  local primeiro=${t[0]} ultimo=${t[1]}
  [[ $primeiro -lt 1 ]] && primeiro=1
  if [[ $ultimo -gt $((primeiro * 12)) ]]; then
    _harness_falhar "custo super-linear: 100 entradas em ${primeiro}ms, 400 em ${ultimo}ms"
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
  assert_sucesso dbx_json_existe $'\036'
}

teste_chave_contendo_separador_e_enderecavel_por_si() {
  local chave
  chave=$'a\037b'
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
  json=$'{"a\001b":1}'
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$json"
  dbx_json_analisar "$json" 2>/dev/null
  assert_igual 'controle' "$DBX_JSON_MOTIVO"
  json=$'{"v":"x\037y"}'
  assert_status "$DBX_JSON_ERRO_REMOTO" dbx_json_analisar "$json"
}

teste_teto_de_entrada_e_aplicado() {
  # G-02: um requisito derivado de um valor nao testado nao tem sustentacao.
  local grande
  local recheio
  printf -v recheio 'x%.0s' $(seq 1 $((DBX_JSON_MAXIMO_ENTRADA + 100)))
  grande="{\"v\":\"$recheio\"}"
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
  # `dbx_json_tipo` entra pelo mesmo criterio dos demais: devolve uma de seis
  # palavras fixas do vocabulario de tipos, nunca byte vindo de fora.
  local permitidos='dbx_errors_codigo_saida|dbx_errors_classificar|_dbx_errors_classe_da_tag|_dbx_hash_sha256_hex|_dbx_hash_calcular|dbx_json_tipo|dbx_errors_politica_retentativa'
  for arquivo in "$DBX_HARNESS_RAIZ"/lib/*.sh; do
    codigo=$(grep -vE '^[[:space:]]*#' "$arquivo")
    # O padrao anterior exigia o `$(` LOGO APOS o `=`, entao `+=" ... $(...)"`
    # escapava — e havia uma ocorrencia viva. Uma garantia que so pega a forma
    # mais obvia da classe da falsa seguranca (E3-04). Agora qualquer
    # substituicao de comando sobre funcao do projeto e sinalizada, em qualquer
    # posicao da linha.
    achados=$(grep -nE '[$]\((_dbx_|dbx_)' <<<"$codigo" |
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

# ---------------------------------------------------------------------------
# Contexto nomeado (E3-01) — o caso de uso real de lib/http
# ---------------------------------------------------------------------------

teste_corpo_de_erro_nao_destroi_listagem_em_curso() {
  # E o padrao que motivou o recurso: interpretar um corpo de erro no meio de
  # uma listagem paginada, sem perder a pagina corrente.
  dbx_json_analisar '{"entries":[{"name":"a.txt"}],"cursor":"ABC"}'
  dbx_json_contexto erro
  dbx_json_analisar '{"error_summary":"path/not_found/."}'
  dbx_json_valor error_summary >/dev/null
  assert_igual 'path/not_found/.' "$DBX_JSON_RESULTADO"

  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  dbx_json_valor cursor >/dev/null
  assert_igual 'ABC' "$DBX_JSON_RESULTADO" 'a listagem em curso precisa sobreviver'
  dbx_json_valor entries 0 name >/dev/null
  assert_igual 'a.txt' "$DBX_JSON_RESULTADO"
}

teste_contextos_nao_enxergam_os_campos_um_do_outro() {
  dbx_json_analisar '{"so_no_padrao":1}'
  dbx_json_contexto erro
  dbx_json_analisar '{"so_no_erro":2}'
  assert_status 1 dbx_json_valor so_no_padrao
  dbx_json_contexto padrao
  assert_status 1 dbx_json_valor so_no_erro
  dbx_json_valor so_no_padrao >/dev/null
  assert_igual '1' "$DBX_JSON_RESULTADO"
}

teste_contexto_devolve_o_anterior_para_restauracao() {
  dbx_json_contexto padrao
  dbx_json_contexto erro
  assert_igual 'padrao' "$DBX_JSON_CONTEXTO_ANTERIOR"
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  assert_igual 'padrao' "$DBX_JSON_CONTEXTO"
}

teste_diagnostico_acompanha_o_contexto_corrente() {
  dbx_json_analisar '{"bom":1}'
  dbx_json_contexto erro
  dbx_json_analisar '{"ruim":' 2>/dev/null
  assert_igual 'malformado' "$DBX_JSON_MOTIVO"
  dbx_json_contexto padrao
  assert_igual '' "$DBX_JSON_MOTIVO" \
    'o motivo pertence ao contexto, e nao a ultima operacao global'
  dbx_json_valor bom >/dev/null
  assert_igual '1' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# A restricao do nome precisa ser VERIFICADA, e nao convencionada
# ---------------------------------------------------------------------------

teste_nome_de_contexto_restrito_a_minusculas_e_sublinhado() {
  local ruim
  # As formas com byte de controle usam $'...' e nao $(printf ...): a
  # substituicao de comando removeria a quebra final e o nome invalido viraria
  # valido — a mesma classe de armadilha que o caso pretende cobrir.
  for ruim in 'Erro' 'erro1' 'erro-2' 'erro.x' '' 'com espaco' 'a/b' 'x=y' \
    $'com\037separador' $'com\nquebra' $'quebra\n'; do
    if dbx_json_contexto "$ruim" 2>/dev/null; then
      _harness_falhar "nome de contexto invalido foi aceito: [$ruim]"
    fi
  done
  assert_sucesso dbx_json_contexto erro
  assert_sucesso dbx_json_contexto com_sublinhado
  dbx_json_contexto padrao
}

teste_nome_invalido_nao_troca_o_contexto_corrente() {
  dbx_json_contexto padrao
  dbx_json_contexto 'INVALIDO' 2>/dev/null
  assert_igual 'padrao' "$DBX_JSON_CONTEXTO" \
    'recusa precisa ser fechada: o contexto corrente nao pode mudar'
}

teste_descartar_recusa_nome_invalido() {
  assert_status "$DBX_JSON_ERRO_USO" dbx_json_descartar 'INVALIDO'
}

# ---------------------------------------------------------------------------
# A guarda do E2-09 nao pode afrouxar pelo contexto nomeado
# ---------------------------------------------------------------------------

teste_contexto_nomeado_nao_vira_porta_para_analise_em_subshell() {
  local status
  dbx_json_analisar '{"lista":1}'
  status=$( (dbx_json_analisar '{"outro":2}') >/dev/null 2>&1; echo $? )
  assert_diferente 0 "$status" 'a guarda continua valendo no contexto corrente'

  # Em contexto novo, analisar dentro de subshell e consultar FORA continua sem
  # responder: o estado nao volta, e a consulta nao pode inventar valor.
  ( dbx_json_contexto erro && dbx_json_analisar '{"novo":3}' ) >/dev/null 2>&1
  dbx_json_contexto erro
  assert_status 1 dbx_json_valor novo \
    'estado de subshell nao pode reaparecer no processo pai'
  dbx_json_contexto padrao
  dbx_json_valor lista >/dev/null
  assert_igual '1' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# Ciclo de vida: reanalise no mesmo contexto nao pode acumular nos
# ---------------------------------------------------------------------------

teste_reanalise_no_mesmo_contexto_libera_os_nos_anteriores() {
  local antes depois
  dbx_json_analisar '{"a":{"b":{"c":1}}}'
  antes=${#DBX_JSON_FILHO[@]}
  dbx_json_analisar '{"a":{"b":{"c":1}}}'
  depois=${#DBX_JSON_FILHO[@]}
  assert_igual "$antes" "$depois" \
    'listagem paginada acumularia os nos de todas as paginas sem a liberacao'
  dbx_json_valor a b c >/dev/null
  assert_igual '1' "$DBX_JSON_RESULTADO"
}

teste_descartar_libera_o_contexto() {
  dbx_json_contexto erro
  dbx_json_analisar '{"x":1}'
  dbx_json_descartar
  assert_status 1 dbx_json_valor x
  dbx_json_contexto padrao
}

# ---------------------------------------------------------------------------
# E4-01 — o ciclo de vida precisa valer TAMBEM no caminho de excecao
#
# O ramo de lixo apos o fim do documento retornava sem fechar a faixa de nos.
# Sem esse registro, toda liberacao futura do contexto retornava cedo e o inicio
# era sobrescrito, orfanando as faixas anteriores em definitivo. Cinco analises
# deixavam 35 nos vivos contra 7 na reanalise valida — vazamento ilimitado em
# processo de vida longa, que e o cenario de listagem paginada.
#
# A invariante fixada nao e "o ramo de lixo fecha a faixa", e sim "TODA analise
# fecha a faixa, qualquer que seja o desfecho". Por isso o caso varre os sete
# desfechos, e nao apenas o que falhou.
# ---------------------------------------------------------------------------

_dbx_nos_vivos() { printf '%s' "${#DBX_JSON_FILHO[@]}"; }

teste_nenhum_desfecho_de_analise_vaza_nos() {
  local documento antes depois
  local -a documentos=(
    '{"a":1,"b":{"c":2},"d":[1,2,3]}'
    '{"a":1,"b":{"c":2},"d":[1,2,3]}extra'
    '{"a":1,"b":{"c":2}'
    '{"a":1,}'
    '{"a":"sem fechamento}'
    'nao_e_json'
    '{"a":tru}'
  )
  for documento in "${documentos[@]}"; do
    dbx_json_analisar "$documento" >/dev/null 2>&1
    antes=$(_dbx_nos_vivos)
    for _ in 1 2 3 4 5; do
      dbx_json_analisar "$documento" >/dev/null 2>&1
    done
    depois=$(_dbx_nos_vivos)
    if [[ $antes != "$depois" ]]; then
      _harness_falhar \
        "nos acumulando ao reanalisar [$documento]: $antes para $depois" \
        'toda analise precisa fechar a faixa de nos, inclusive nos caminhos de falha'
    fi
  done
}

teste_faixa_de_nos_e_fechada_mesmo_quando_a_analise_falha() {
  # Verificacao direta da invariante, e nao apenas do seu efeito.
  dbx_json_analisar '{"a":1}extra' >/dev/null 2>&1
  assert_diferente '' "${DBX_JSON_FIM_DO_CONTEXTO[padrao]:-}" \
    'o fim da faixa precisa ser registrado tambem no desfecho de excecao'
  assert_diferente '' "${DBX_JSON_INICIO_DO_CONTEXTO[padrao]:-}"
}

teste_falha_no_meio_de_listagem_paginada_nao_acumula() {
  # Combinacao que motivou o contexto nomeado: paginas boas intercaladas com uma
  # resposta corrompida, no mesmo contexto.
  local antes depois
  dbx_json_analisar '{"entries":[{"n":1}],"cursor":"A"}' >/dev/null 2>&1
  antes=$(_dbx_nos_vivos)
  for _ in 1 2 3; do
    dbx_json_analisar '{"entries":[{"n":1}],"cursor":"A"}' >/dev/null 2>&1
    dbx_json_analisar '{"entries":[{"n":1}],"cursor":"A"}lixo' >/dev/null 2>&1
  done
  dbx_json_analisar '{"entries":[{"n":1}],"cursor":"A"}' >/dev/null 2>&1
  depois=$(_dbx_nos_vivos)
  assert_igual "$antes" "$depois" 'resposta corrompida no meio do percurso nao pode acumular nos'
  dbx_json_valor cursor >/dev/null
  assert_igual 'A' "$DBX_JSON_RESULTADO"
}

# ---------------------------------------------------------------------------
# RSK-28 — contramedida verificavel para a classe "instrumento de observacao
# interfere na propriedade observada".
#
# Seis instancias em tres papeis ate aqui: duas do QA com sondas usando
# substituicao de comando sobre quebra de linha, uma do coordenador com `grep`
# cegado por byte de controle, e tres do desenvolvimento — inclusive uma DENTRO
# de um teste escrito para cobrir essa mesma familia.
#
# Regra adotada: massa adversarial se constroi com `$'...'` ou `printf -v`,
# nunca com substituicao de comando, que remove quebras finais e converte massa
# invalida em valida em silencio.
# ---------------------------------------------------------------------------

teste_massa_adversarial_nao_e_construida_por_substituicao_de_comando() {
  local arquivo codigo achados
  for arquivo in "$DBX_HARNESS_RAIZ"/tests/unit/*.sh "$DBX_HARNESS_RAIZ"/tests/support/*.sh; do
    codigo=$(grep -vE '^[[:space:]]*#' "$arquivo")
    achados=$(grep -nE '[$]\(printf' <<<"$codigo" || true)
    if [[ -n $achados ]]; then
      _harness_falhar \
        "massa construida por substituicao de comando em $(basename "$arquivo"): $achados" \
        "use \$'...' ou printf -v: a substituicao remove quebras finais e pode tornar valida uma massa que deveria ser invalida"
    fi
  done
}

# ---------------------------------------------------------------------------
# R2-04 — o codificador precisa de casos DIRETOS, e nao so de ida e volta.
#
# Mutando o escape da barra invertida, `json` e `composicao` davam zero e so
# `config` reprovava. O proximo consumidor e `lib/http`, que codifica CORPO DE
# REQUISICAO: ali nao ha ida e volta local, e um escape quebrado vira requisicao
# malformada detectavel somente em rede.
# ---------------------------------------------------------------------------

teste_codificador_escapa_cada_forma_exigida() {
  dbx_json_escapar_cadeia 'a\b'
  assert_igual 'a\\b' "$DBX_JSON_ESCAPADO" 'barra invertida'
  dbx_json_escapar_cadeia 'a"b'
  assert_igual 'a\"b' "$DBX_JSON_ESCAPADO" 'aspa'
  dbx_json_escapar_cadeia $'a\tb'
  assert_igual 'a\tb' "$DBX_JSON_ESCAPADO" 'tabulacao'
  dbx_json_escapar_cadeia $'a\nb'
  assert_igual 'a\nb' "$DBX_JSON_ESCAPADO" 'quebra de linha'
  dbx_json_escapar_cadeia $'a\rb'
  assert_igual 'a\rb' "$DBX_JSON_ESCAPADO" 'retorno de carro'
}

teste_codificador_escapa_a_barra_invertida_antes_das_demais() {
  # A ORDEM e o ponto: escapar a barra depois duplicaria as barras introduzidas
  # pelos outros escapes, produzindo duas barras onde deveria haver uma.
  dbx_json_escapar_cadeia $'a\nb'
  assert_igual 'a\nb' "$DBX_JSON_ESCAPADO" \
    'quebra de linha vira exatamente uma barra seguida de n'
  dbx_json_escapar_cadeia $'\\\n'
  assert_igual '\\\n' "$DBX_JSON_ESCAPADO" \
    'barra literal seguida de quebra: duas barras e depois o escape da quebra'
}

teste_codificador_escapa_controle_como_sequencia_unicode() {
  dbx_json_escapar_cadeia $'a\001b'
  assert_igual 'a\u0001b' "$DBX_JSON_ESCAPADO"
  dbx_json_escapar_cadeia $'a\037b'
  assert_igual 'a\u001fb' "$DBX_JSON_ESCAPADO"
}

teste_codificador_nao_altera_texto_sem_escape() {
  local entrada='/pasta/comum com espaco e acentuacao-cafe'
  dbx_json_escapar_cadeia "$entrada"
  assert_igual "$entrada" "$DBX_JSON_ESCAPADO" \
    'texto sem caractere especial nao pode ser alterado'
}

harness_executar "$@"
