#!/usr/bin/env bash
# Testes de lib/hash.sh — calculo do content_hash da Dropbox (RF-33, RF-34).
#
# Origem dos valores esperados
# ----------------------------
# Os valores abaixo NAO foram copiados da implementacao sob teste. Foram
# derivados de forma independente a partir da especificacao publicada, com um
# oraculo escrito em Python (hashlib), antes de existir qualquer linha de
# lib/hash.sh. O procedimento esta descrito em docs/registros/vetores-content-hash.md
# e pode ser reproduzido por qualquer revisor.
#
# O vetor oficial da Dropbox (485291fa...) fica em hash_vetor_oficial_test.sh
# porque depende de um arquivo externo ao repositorio.

# shellcheck disable=SC2016
# Justificativa da supressao acima: varios casos entregam um script literal a
# um "bash -c", que precisa chegar sem expansao ao processo filho. Expandir as
# variaveis no shell pai destruiria o proposito do caso, que e exercitar o
# componente em um processo separado e limpo.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
# shellcheck source=tests/support/fixtures.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/fixtures.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"

# Vetores derivados independentemente (ver cabecalho).
readonly ESPERADO_VAZIO=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
readonly ESPERADO_UM_BYTE=1cd6ef71e6e0ff46ad2609d403dc3fee244417089aa4461245a4e4fe23a55e42
readonly ESPERADO_QUASE_BLOCO=647c8627d70f7a7d13ce96b1e7710a771a55d41a62c3da490d92e56044d311fa
readonly ESPERADO_BLOCO_EXATO=c7e946d101855255d919ef0c70718633adf77d3dfb3adeeecf5d0cb4e951be58
readonly ESPERADO_BLOCO_MAIS_UM=11d29899ccb4a260814f07931519a87c793ec37a2d50e145ae9e1269a3b4bcd8
readonly ESPERADO_DOIS_BLOCOS_RESTO=002579d0d7791a3e8c75d539c7495efa6c225e5a47e27ca8afea0c4a34714db8
readonly ESPERADO_GRANDE=a4e26995fdee474eebe1999bd311b50162f28858425920b0102fcb6896a2e117

# Valores que a implementacao produziria se concatenasse os resumos em
# hexadecimal em vez de bytes brutos. Sao a armadilha documentada em PRJ-DEC-08:
# a diferenca so apareceria na comparacao com a API.
readonly ARMADILHA_BLOCO_MAIS_UM=5e4902cc7e48f60d8d8c20edf768a600c87692d3649bf6be2d5ce2ab583d2364
readonly ARMADILHA_DOIS_BLOCOS=ebd94ae9e1e6500a61221d63f2526847e88b28e85123feb2ca3e6d41e8fa16ad

# ---------------------------------------------------------------------------
# Contrato do componente
# ---------------------------------------------------------------------------

teste_tamanho_de_bloco_e_4_mib() {
  assert_igual 4194304 "$DBX_HASH_TAMANHO_BLOCO" \
    'o bloco do content_hash e de 4 MiB exatos (4.194.304 bytes)'
}

teste_saida_tem_64_caracteres_hexadecimais_minusculos() {
  local caminho valor
  caminho=$(fixture_criar um_byte)
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_igual 64 "${#valor}" 'o content_hash tem 64 caracteres'
  if [[ ! $valor =~ ^[0-9a-f]{64}$ ]]; then
    assert_igual 'hexadecimal minusculo' "$valor" 'o content_hash usa apenas [0-9a-f]'
  fi
}

# ---------------------------------------------------------------------------
# Casos de borda exigidos pelos criterios de aceite de RF-34
# ---------------------------------------------------------------------------

teste_arquivo_vazio() {
  local caminho
  caminho=$(fixture_criar vazio)
  assert_igual "$ESPERADO_VAZIO" "$(dbx_hash_conteudo_arquivo "$caminho")" \
    'arquivo vazio produz o SHA-256 da concatenacao vazia'
}

teste_arquivo_de_um_byte() {
  local caminho
  caminho=$(fixture_criar um_byte)
  assert_igual "$ESPERADO_UM_BYTE" "$(dbx_hash_conteudo_arquivo "$caminho")" \
    'arquivo menor que um bloco'
}

teste_arquivo_com_um_byte_a_menos_que_um_bloco() {
  local caminho
  caminho=$(fixture_criar quase_bloco)
  assert_igual "$ESPERADO_QUASE_BLOCO" "$(dbx_hash_conteudo_arquivo "$caminho")" \
    'limite inferior do primeiro bloco'
}

teste_arquivo_de_bloco_exato() {
  local caminho
  caminho=$(fixture_criar bloco_exato)
  assert_igual "$ESPERADO_BLOCO_EXATO" "$(dbx_hash_conteudo_arquivo "$caminho")" \
    'arquivo de exatamente um bloco nao pode gerar um segundo bloco vazio'
}

teste_arquivo_de_bloco_mais_um_byte() {
  local caminho
  caminho=$(fixture_criar bloco_mais_um)
  assert_igual "$ESPERADO_BLOCO_MAIS_UM" "$(dbx_hash_conteudo_arquivo "$caminho")" \
    'bloco cheio seguido de resto minimo'
}

teste_arquivo_com_multiplos_blocos_e_resto() {
  local caminho
  caminho=$(fixture_criar dois_blocos_resto)
  assert_igual "$ESPERADO_DOIS_BLOCOS_RESTO" "$(dbx_hash_conteudo_arquivo "$caminho")" \
    'dois blocos cheios mais resto de 7 bytes'
}

# ---------------------------------------------------------------------------
# A armadilha: concatenacao binaria e nao hexadecimal
# ---------------------------------------------------------------------------

teste_nao_concatena_resumos_em_hexadecimal_com_dois_blocos() {
  local caminho valor
  caminho=$(fixture_criar dois_blocos_resto)
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_sucesso dbx_hash_formato_valido "$valor"
  assert_diferente "$ARMADILHA_DOIS_BLOCOS" "$valor" \
    'concatenar as representacoes hexadecimais produz valor errado (PRJ-DEC-08)'
}

teste_nao_concatena_resumos_em_hexadecimal_com_bloco_mais_um() {
  local caminho valor
  caminho=$(fixture_criar bloco_mais_um)
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_sucesso dbx_hash_formato_valido "$valor"
  assert_diferente "$ARMADILHA_BLOCO_MAIS_UM" "$valor" \
    'concatenar as representacoes hexadecimais produz valor errado (PRJ-DEC-08)'
}

teste_um_unico_bloco_nao_e_o_sha256_do_proprio_conteudo() {
  # Salvaguarda contra a simplificacao de "arquivo pequeno = sha256 direto":
  # mesmo com um unico bloco ha uma segunda passagem de SHA-256.
  local caminho sha_direto valor
  caminho=$(fixture_criar um_byte)
  sha_direto=$(sha256sum <"$caminho" | cut -d' ' -f1)
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_sucesso dbx_hash_formato_valido "$valor"
  assert_diferente "$sha_direto" "$valor" \
    'o content_hash de um bloco unico ainda aplica SHA-256 sobre o resumo'
}

# ---------------------------------------------------------------------------
# Entrada por fluxo (nao seekavel) — sustenta RF-31 e RF-32
# ---------------------------------------------------------------------------

teste_fluxo_e_arquivo_produzem_o_mesmo_valor() {
  local caminho por_arquivo por_fluxo
  caminho=$(fixture_criar dois_blocos_resto)
  por_arquivo=$(dbx_hash_conteudo_arquivo "$caminho")
  por_fluxo=$(dbx_hash_conteudo_fluxo <"$caminho")
  assert_igual "$por_arquivo" "$por_fluxo" \
    'o resultado independe de a origem ser arquivo ou fluxo'
}

teste_fluxo_a_partir_de_cano_sem_arquivo_intermediario() {
  local valor
  # shellcheck disable=SC2002  # o `cat` e proposital: cria um cano nao seekavel,
  # que e exatamente o que este caso precisa exercitar. `< arquivo` seria seekavel.
  valor=$(cat "$(fixture_criar bloco_mais_um)" | dbx_hash_conteudo_fluxo)
  assert_igual "$ESPERADO_BLOCO_MAIS_UM" "$valor" \
    'entrada nao seekavel (cano) e tratada corretamente'
}

teste_fluxo_vazio() {
  local valor
  valor=$(dbx_hash_conteudo_fluxo </dev/null)
  assert_igual "$ESPERADO_VAZIO" "$valor" 'fluxo sem bytes'
}

teste_bytes_nulos_nao_truncam_o_conteudo() {
  # Se a implementacao passasse o conteudo por variavel de shell, o primeiro
  # byte 0x00 truncaria tudo e o resultado seria o de um arquivo vazio.
  local caminho valor
  caminho=$(fixture_criar bloco_exato) # 4 MiB de bytes 0x00
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_diferente "$ESPERADO_VAZIO" "$valor" 'conteudo so de bytes nulos nao pode virar vazio'
  assert_igual "$ESPERADO_BLOCO_EXATO" "$valor" 'conteudo so de bytes nulos e integralmente lido'
}

# ---------------------------------------------------------------------------
# Arquivo grande sem carregar tudo em memoria
# ---------------------------------------------------------------------------

# _medir_pico <fixture> <hash_esperado> -> imprime o pico de memoria residente em KiB
# Falha o caso se o valor calculado divergir: sem isso a medicao poderia ser de
# um processo que sequer chegou a resumir o arquivo.
_medir_pico() {
  local fixture=$1 esperado=$2 caminho pico resultado_arq
  caminho=$(fixture_criar "$fixture")
  resultado_arq="$DBX_TESTES_TMP/pico-$fixture-$$.out"
  pico=$(/usr/bin/time -f '%M' bash -c '
    . "$1/lib/hash.sh" || exit 1
    dbx_hash_conteudo_arquivo "$2" >"$3"
  ' _ "$DBX_HARNESS_RAIZ" "$caminho" "$resultado_arq" 2>&1 >/dev/null | tail -1)
  assert_igual "$esperado" "$(cat "$resultado_arq" 2>/dev/null)" \
    "o calculo medido sobre a fixture $fixture precisa ter produzido o valor correto"
  printf '%s' "$pico"
}

teste_arquivo_grande_nao_e_carregado_em_memoria() {
  # A propriedade verificada nao e "usa pouca memoria", e sim "a memoria nao
  # cresce com o tamanho da entrada". Um arquivo 8x maior nao pode elevar o
  # pico de memoria residente de forma proporcional.
  local pico_pequeno pico_grande delta
  if ! command -v /usr/bin/time >/dev/null 2>&1; then
    pular 'GNU time indisponivel para medir pico de memoria residente'
  fi

  pico_pequeno=$(_medir_pico dois_blocos_resto "$ESPERADO_DOIS_BLOCOS_RESTO") # ~8 MiB
  pico_grande=$(_medir_pico grande "$ESPERADO_GRANDE")                        # 64 MiB

  if [[ ! $pico_pequeno =~ ^[0-9]+$ || ! $pico_grande =~ ^[0-9]+$ ]]; then
    pular "nao foi possivel medir o pico de memoria ($pico_pequeno / $pico_grande)"
  fi

  delta=$((pico_grande - pico_pequeno))
  [[ $delta -lt 0 ]] && delta=$((-delta))
  if [[ $delta -gt 1024 ]]; then
    assert_igual "delta <= 1024 KiB" "delta de $delta KiB" \
      "o pico de memoria nao pode acompanhar o tamanho do arquivo (8 MiB: ${pico_pequeno} KiB, 64 MiB: ${pico_grande} KiB)"
  fi

  # Teto absoluto de sanidade: um bloco de 4 MiB em transito mais a folga do
  # interpretador. Bem abaixo dos 64 MiB da entrada.
  if [[ $pico_grande -gt 16384 ]]; then
    assert_igual '<= 16384 KiB' "$pico_grande KiB" \
      'pico de memoria acima do esperado para um calculo por blocos'
  fi
}

teste_nao_deixa_residuo_temporario() {
  local antes depois caminho valor
  caminho=$(fixture_criar bloco_mais_um)
  antes=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'dbx-*' 2>/dev/null | sort)
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_igual "$ESPERADO_BLOCO_MAIS_UM" "$valor" 'calculo precisa ter ocorrido de fato'
  depois=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'dbx-*' 2>/dev/null | sort)
  assert_igual "$antes" "$depois" \
    'o calculo nao pode deixar arquivo temporario para tras (RNF-05, PRJ-DEC-07)'
}

# ---------------------------------------------------------------------------
# Falhas de uso
# ---------------------------------------------------------------------------

teste_arquivo_inexistente_falha_com_status_dedicado() {
  assert_status "$DBX_HASH_ERRO_ORIGEM" dbx_hash_conteudo_arquivo "$DBX_TESTES_TMP/nao-existe-$$"
}

teste_diretorio_nao_e_aceito_como_origem() {
  assert_status "$DBX_HASH_ERRO_ORIGEM" dbx_hash_conteudo_arquivo "$DBX_TESTES_TMP"
}

teste_origem_pode_ser_um_cano_e_nao_apenas_arquivo_comum() {
  # Sustenta o uso previsto em RF-31: a origem nem sempre e um arquivo comum.
  # Substituicao de processo e `/dev/stdin` chegam como cano. Executado em
  # processo separado com tempo limite para que uma regressao vire reprovacao,
  # e nunca uma suite travada.
  local valor
  valor=$(timeout 30 bash -c '
    . "$1/lib/hash.sh" || exit 1
    dbx_hash_conteudo_arquivo <(printf "A")
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  assert_igual "$ESPERADO_UM_BYTE" "$valor" \
    'um cano deve ser origem valida, tanto quanto um arquivo comum'
}

teste_argumento_ausente_falha_com_status_de_uso() {
  assert_status "$DBX_HASH_ERRO_USO" dbx_hash_conteudo_arquivo
}

teste_nome_de_arquivo_com_espacos_e_caracteres_especiais() {
  local caminho valor
  caminho="$DBX_TESTES_TMP/nome com espaco \$VAR 'aspas' \"duplas\" *asterisco* acentuacao-cafe.bin"
  printf 'A' >"$caminho"
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_igual "$ESPERADO_UM_BYTE" "$valor" \
    'nome com metacaracteres de shell nao pode sofrer expansao (RNF-10)'
}

teste_nome_de_arquivo_com_quebra_de_linha() {
  local caminho valor
  caminho="$DBX_TESTES_TMP/nome"$'\n'"com quebra.bin"
  printf 'A' >"$caminho"
  valor=$(dbx_hash_conteudo_arquivo "$caminho")
  assert_igual "$ESPERADO_UM_BYTE" "$valor" 'nome com quebra de linha (RNF-10)'
}

# ---------------------------------------------------------------------------
# Comparacao e validacao de formato — usadas por lib/transfer (RF-33)
# ---------------------------------------------------------------------------

teste_valida_formato_de_content_hash() {
  assert_sucesso dbx_hash_formato_valido "$ESPERADO_VAZIO"
  assert_status 1 dbx_hash_formato_valido "${ESPERADO_VAZIO:0:63}"
  assert_status 1 dbx_hash_formato_valido "${ESPERADO_VAZIO}0"
  assert_status 1 dbx_hash_formato_valido ''
  assert_status 1 dbx_hash_formato_valido 'ZZZ0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
}

teste_comparacao_ignora_caixa_mas_nao_valores_diferentes() {
  local maiusculo
  maiusculo=${ESPERADO_VAZIO^^}
  assert_sucesso dbx_hash_iguais "$ESPERADO_VAZIO" "$maiusculo"
  assert_status 1 dbx_hash_iguais "$ESPERADO_VAZIO" "$ESPERADO_UM_BYTE"
}

teste_comparacao_recusa_valor_malformado() {
  # Nunca declarar "identicos" a partir de entrada invalida: seria omissao
  # indevida de transferencia em RF-33.
  assert_status 2 dbx_hash_iguais '' ''
  assert_status 2 dbx_hash_iguais 'abc' 'abc'
}

# ---------------------------------------------------------------------------
# Falha do leitor nao pode ser mascarada
#
# Um `content_hash` bem formado calculado sobre conteudo incompleto e o pior
# resultado possivel: a aplicacao declararia integridade sobre dado truncado.
# ---------------------------------------------------------------------------

_leitor_que_falha() {
  # Cria um `head` substituto que entrega dados parciais e sai com erro,
  # simulando EIO, truncamento sob leitura ou produtor morto no meio.
  local dir="$DBX_TESTES_TMP/leitor-falho.$$"
  mkdir -p "$dir"
  {
    printf '#!/usr/bin/env bash\n'
    printf "printf 'CONTEUDO-PARCIAL'\n"
    printf 'exit 1\n'
  } >"$dir/head"
  chmod +x "$dir/head"
  printf '%s' "$dir"
}

teste_falha_do_leitor_nao_produz_hash_com_status_zero() {
  local dir saida status
  dir=$(_leitor_que_falha)
  saida=$(PATH="$dir:$PATH" timeout 30 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/hash.sh"   || exit 90
    dbx_hash_conteudo_fluxo </dev/null
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  status=$?
  assert_diferente 0 "$status" \
    'leitor com falha precisa reprovar a operacao, e nao devolver hash de conteudo parcial'
  assert_igual '' "$saida" 'nenhum resumo pode ser emitido quando a leitura falhou'
}

# ---------------------------------------------------------------------------
# Contagem de bytes lidos — exigida por RF-31 ("o tamanho corresponde ao total
# de bytes lidos da entrada padrao") e unica forma de o chamador distinguir fim
# de fluxo de truncamento.
# ---------------------------------------------------------------------------

teste_expoe_o_total_de_bytes_lidos() {
  local caminho
  caminho=$(fixture_criar vazio)
  assert_igual "$ESPERADO_VAZIO 0" "$(dbx_hash_conteudo_arquivo_com_tamanho "$caminho")"

  caminho=$(fixture_criar um_byte)
  assert_igual "$ESPERADO_UM_BYTE 1" "$(dbx_hash_conteudo_arquivo_com_tamanho "$caminho")"

  caminho=$(fixture_criar bloco_exato)
  assert_igual "$ESPERADO_BLOCO_EXATO 4194304" "$(dbx_hash_conteudo_arquivo_com_tamanho "$caminho")"

  caminho=$(fixture_criar dois_blocos_resto)
  assert_igual "$ESPERADO_DOIS_BLOCOS_RESTO 8388615" \
    "$(dbx_hash_conteudo_arquivo_com_tamanho "$caminho")"
}

teste_expoe_o_total_de_bytes_lidos_a_partir_de_fluxo() {
  local valor
  # shellcheck disable=SC2002  # idem: o cano nao seekavel e o objeto do teste.
  valor=$(cat "$(fixture_criar bloco_mais_um)" | dbx_hash_conteudo_fluxo_com_tamanho)
  assert_igual "$ESPERADO_BLOCO_MAIS_UM 4194305" "$valor" \
    'a contagem precisa funcionar onde mais importa: entrada nao seekavel'
}

teste_contagem_confere_com_o_tamanho_real_do_arquivo() {
  local caminho relatado real
  caminho=$(fixture_criar dois_blocos_resto)
  relatado=$(dbx_hash_conteudo_arquivo_com_tamanho "$caminho")
  relatado=${relatado##* }
  real=$(wc -c <"$caminho" | tr -d ' ')
  assert_igual "$real" "$relatado" 'a contagem reportada tem de ser a contagem real'
}

# ---------------------------------------------------------------------------
# Custo da conversao de resumos em bytes — precisa ser LINEAR na quantidade de
# blocos. A versao anterior fatiava uma cadeia que crescia a cada bloco, o que
# tornava a conversao quadratica e limitava a capacidade real a poucos GiB.
# ---------------------------------------------------------------------------

# DBX_HASH_FORMATO e o acumulador global escrito por _dbx_hash_anexar_escapes,
# definido em lib/hash.sh. O analisador estatico nao enxerga esse uso porque ele
# esta em outro arquivo, dai a supressao abaixo.
teste_conversao_de_escapes_e_linear_na_quantidade_de_blocos() {
  # A medicao roda em processo filho sob `timeout`. Sem esse teto, uma regressao
  # quadratica nao reprovaria: ela penduraria a suite, e um job de integracao
  # continua travado e um job reprovado exigem reacoes muito diferentes.
  local saida status t1 t2 n=4000

  saida=$(timeout 60 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/hash.sh"   || exit 90
    . "$1/tests/support/harness.sh" || exit 90
    base=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    n=$2
    inicio=$(_agora_ms)
    DBX_HASH_FORMATO=""
    for ((i = 0; i < n; i++)); do _dbx_hash_anexar_escapes "$base"; done
    meio=$(_agora_ms)
    DBX_HASH_FORMATO=""
    for ((i = 0; i < n * 2; i++)); do _dbx_hash_anexar_escapes "$base"; done
    fim=$(_agora_ms)
    printf "%s %s\n" "$((meio - inicio))" "$((fim - meio))"
  ' _ "$DBX_HARNESS_RAIZ" "$n" 2>/dev/null)
  status=$?

  if [[ $status -eq 124 ]]; then
    _harness_falhar \
      "a conversao nao terminou em 60s para $n e $((n * 2)) blocos" \
      'sintoma tipico de custo quadratico na quantidade de blocos'
  fi
  assert_igual 0 "$status" 'a medicao precisa concluir'

  t1=${saida%% *}
  t2=${saida##* }
  [[ $t1 =~ ^[0-9]+$ && $t2 =~ ^[0-9]+$ ]] || _harness_falhar "medicao invalida: [$saida]"
  [[ $t1 -lt 1 ]] && t1=1

  if [[ $t2 -gt $((t1 * 3)) ]]; then
    _harness_falhar \
      "conversao nao e linear: $n blocos em ${t1}ms, $((n * 2)) blocos em ${t2}ms" \
      'dobrar a quantidade de blocos deve aproximadamente dobrar o tempo, nao quadruplicar'
  fi
}

# ---------------------------------------------------------------------------
# Alinhamento com o contrato publico de codigos de saida (RF-29)
# ---------------------------------------------------------------------------

teste_status_do_componente_seguem_a_taxonomia_de_erro() {
  # Antes, os valores 1, 3 e 4 coincidiam numericamente com classes de RF-29 que
  # tem OUTRO significado. Codigo de saida ambiguo quebra o orquestrador.
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_HASH_ERRO_USO"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_HASH_ERRO_DEPENDENCIA"
  assert_igual "$(dbx_errors_codigo_saida nao_encontrado)" "$DBX_HASH_ERRO_ORIGEM"
  assert_igual "$(dbx_errors_codigo_saida desconhecido)" "$DBX_HASH_ERRO_RESUMO"
}

teste_backend_invalido_vindo_do_ambiente_e_recusado() {
  # DBX_HASH_BACKEND vem do ambiente. Um valor arbitrario nao pode virar falha
  # generica: precisa dizer que a dependencia esta indisponivel.
  local status
  DBX_HASH_BACKEND='utilitario_que_nao_existe' timeout 20 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/hash.sh"   || exit 90
    dbx_hash_conteudo_fluxo </dev/null
  ' _ "$DBX_HARNESS_RAIZ" >/dev/null 2>&1
  status=$?
  assert_igual "$DBX_HASH_ERRO_DEPENDENCIA" "$status" \
    'backend inexistente deve reprovar como dependencia ausente'
}

teste_backend_valido_vindo_do_ambiente_e_aceito() {
  local valor
  valor=$(DBX_HASH_BACKEND='sha256sum' timeout 20 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/hash.sh"   || exit 90
    dbx_hash_conteudo_fluxo </dev/null
  ' _ "$DBX_HARNESS_RAIZ" 2>/dev/null)
  assert_igual "$ESPERADO_VAZIO" "$valor" 'backend valido informado pelo ambiente continua funcionando'
}

teste_falha_da_area_temporaria_e_erro_de_configuracao() {
  # C2-07: classificar problema de disco local como `nao_encontrado` mandava o
  # operador investigar a Dropbox por uma falha que e do proprio host.
  local status
  TMPDIR=/caminho/que/nao/existe/nunca timeout 20 bash -c '
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/hash.sh"   || exit 90
    dbx_hash_conteudo_fluxo </dev/null
  ' _ "$DBX_HARNESS_RAIZ" >/dev/null 2>&1
  status=$?
  assert_igual "$DBX_HASH_ERRO_DEPENDENCIA" "$status" \
    'falha de area temporaria e problema de ambiente, nao recurso remoto ausente'
}

harness_executar "$@"
