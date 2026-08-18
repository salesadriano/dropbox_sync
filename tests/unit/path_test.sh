#!/usr/bin/env bash
# Testes de lib/path.sh — normalizacao de caminho e confinamento de raiz.
# Requisitos: RNF-10 (nomes com caracteres especiais) e RNF-20 (menor privilegio
# e confinamento validado ANTES de qualquer chamada de rede).

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a um "bash -c", que precisa
# chegar sem expansao ao processo filho, e mensagens de diagnostico citam
# nomes de arquivo com barra invertida como dado, nao como expansao.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"

# Area de trabalho fisica: se $TMPDIR for um link simbolico, comparar com o
# caminho logico produziria falha espuria em todos os casos de confinamento.
_area() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/path.XXXXXX") || return 1
  (cd -P -- "$dir" && pwd -P)
}

# ---------------------------------------------------------------------------
# Normalizacao de caminho remoto
# ---------------------------------------------------------------------------

teste_normaliza_separadores_redundantes() {
  assert_igual '/a/b' "$(dbx_path_remoto_normalizar '/a//b')"
  assert_igual '/a/b' "$(dbx_path_remoto_normalizar '///a///b///')"
  assert_igual '/a/b' "$(dbx_path_remoto_normalizar '/a/b/')"
}

teste_normaliza_componentes_ponto() {
  assert_igual '/a/b' "$(dbx_path_remoto_normalizar '/a/./b')"
  assert_igual '/a' "$(dbx_path_remoto_normalizar '/a/.')"
  assert_igual '/' "$(dbx_path_remoto_normalizar '/.')"
}

teste_resolve_ponto_ponto_lexicalmente() {
  # Resolucao lexical e correta no espaco remoto: a Dropbox nao tem links
  # simbolicos do lado do servidor, entao nao ha alvo a seguir.
  assert_igual '/a' "$(dbx_path_remoto_normalizar '/a/b/..')"
  assert_igual '/a/d' "$(dbx_path_remoto_normalizar '/a/b/c/../../d')"
  assert_igual '/' "$(dbx_path_remoto_normalizar '/a/..')"
}

teste_raiz_e_preservada() {
  assert_igual '/' "$(dbx_path_remoto_normalizar '/')"
  assert_igual '/' "$(dbx_path_remoto_normalizar '//')"
}

teste_travessia_acima_da_raiz_e_recusada() {
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_normalizar '/..'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_normalizar '/a/../..'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_normalizar '/../etc/passwd'
}

teste_caminho_relativo_ou_vazio_e_uso_invalido() {
  assert_status "$DBX_PATH_USO_INVALIDO" dbx_path_remoto_normalizar 'a/b'
  assert_status "$DBX_PATH_USO_INVALIDO" dbx_path_remoto_normalizar ''
  assert_status "$DBX_PATH_USO_INVALIDO" dbx_path_remoto_normalizar
}

teste_nomes_com_caracteres_especiais_sao_preservados() {
  assert_igual '/pasta com espaco/arquivo.txt' \
    "$(dbx_path_remoto_normalizar '/pasta com espaco/arquivo.txt')"
  # que o componente nao expande a variavel embutida no nome (RNF-10).
  assert_igual '/a/$VAR nao expandida' "$(dbx_path_remoto_normalizar '/a/$VAR nao expandida')"
  assert_igual '/a/*.txt' "$(dbx_path_remoto_normalizar '/a/*.txt')"
  assert_igual "/a/aspas'simples\"duplas" "$(dbx_path_remoto_normalizar "/a/aspas'simples\"duplas")"
  assert_igual '/a/acentuacao-cafe-uniao' "$(dbx_path_remoto_normalizar '/a/acentuacao-cafe-uniao')"
  assert_igual '/a/til~cifrao$e&comercial' "$(dbx_path_remoto_normalizar '/a/til~cifrao$e&comercial')"
}

teste_nome_com_ponto_ponto_embutido_nao_e_travessia() {
  # `..coisa` e `a..b` sao nomes validos, nao componentes de travessia.
  assert_igual '/a/..oculto' "$(dbx_path_remoto_normalizar '/a/..oculto')"
  assert_igual '/a/versao..final' "$(dbx_path_remoto_normalizar '/a/versao..final')"
  assert_igual '/a/...' "$(dbx_path_remoto_normalizar '/a/...')"
}

teste_nome_com_quebra_de_linha_e_preservado() {
  local entrada="/pasta/nome"$'\n'"com quebra.txt"
  assert_igual "$entrada" "$(dbx_path_remoto_normalizar "$entrada")" \
    'a quebra de linha faz parte do nome e nao pode ser removida (RNF-10)'
}

# ---------------------------------------------------------------------------
# Quebra de linha TERMINAL. E o caso que `$( )` destroi, e por isso o unico que
# prova a preservacao byte a byte. Um caso com a quebra no meio passa mesmo em
# implementacao defeituosa, porque a substituicao de comando so remove quebras
# FINAIS. Toda assercao aqui le DBX_PATH_RESULTADO, nunca `$( )`.
# ---------------------------------------------------------------------------

teste_quebra_de_linha_terminal_sobrevive_na_normalizacao_remota() {
  local entrada="/pasta/arquivo"$'\n'
  dbx_path_remoto_normalizar "$entrada" >/dev/null
  assert_igual "$entrada" "$DBX_PATH_RESULTADO" \
    'a quebra de linha final faz parte do nome e nao pode ser descartada'
}

teste_quebra_de_linha_terminal_sobrevive_no_confinamento_remoto() {
  local entrada="/backups/arquivo"$'\n'
  dbx_path_remoto_confinar '/backups' "$entrada" >/dev/null
  assert_igual "$entrada" "$DBX_PATH_RESULTADO" \
    'o confinamento nao pode truncar o nome que aprovou'
}

teste_multiplas_quebras_terminais_sao_preservadas() {
  local entrada="/backups/arquivo"$'\n\n\n'
  dbx_path_remoto_confinar '/backups' "$entrada" >/dev/null
  assert_igual "$entrada" "$DBX_PATH_RESULTADO" \
    'tres quebras finais sao tres bytes do nome, nao formatacao'
}

teste_quebra_terminal_local_nao_entrega_arquivo_errado() {
  # O defeito e de seguranca, nao de estetica: `arq` e `arq\n` sao dois arquivos
  # distintos. Truncar o nome faz a aplicacao ler ou sobrescrever o alvo errado
  # reportando sucesso.
  local area status
  area=$(_area)
  mkdir -p "$area/raiz"
  printf 'CONTEUDO-DE-ARQ' >"$area/raiz/arq"
  printf 'CONTEUDO-DE-ARQ-COM-QUEBRA' >"$area/raiz/arq"$'\n'

  dbx_path_local_confinar "$area/raiz" "$area/raiz/arq"$'\n' >/dev/null
  status=$?
  assert_igual 0 "$status" 'o caminho esta dentro da raiz e deve ser aceito'
  assert_igual "$area/raiz/arq"$'\n' "$DBX_PATH_RESULTADO" \
    'o caminho devolvido precisa ser o solicitado, byte a byte'
  assert_igual 'CONTEUDO-DE-ARQ-COM-QUEBRA' "$(cat -- "$DBX_PATH_RESULTADO")" \
    'ler o caminho devolvido tem de entregar o arquivo solicitado, nao o vizinho'
}

teste_resultado_e_limpo_quando_o_caminho_e_recusado() {
  # Um valor remanescente de chamada anterior seria lido como aprovacao.
  local area
  area=$(_area)
  mkdir -p "$area/raiz" "$area/fora"
  dbx_path_local_confinar "$area/raiz" "$area/raiz/valido" >/dev/null
  dbx_path_local_confinar "$area/raiz" "$area/fora/invasor" >/dev/null
  assert_igual '' "$DBX_PATH_RESULTADO" \
    'recusa precisa zerar o resultado, e nao deixar o valor anterior'
}

teste_deteccao_de_caminho_inseguro_para_saida_de_uma_linha() {
  # O contrato de saida estruturada e orientado a linha (RF-28/RF-35): quem
  # emite precisa saber que este caminho exige escape.
  assert_sucesso dbx_path_seguro_para_linha '/pasta/arquivo com espaco.txt'
  assert_status 1 dbx_path_seguro_para_linha "/pasta/nome"$'\n'"quebrado"
  assert_status 1 dbx_path_seguro_para_linha "/pasta/nome"$'\t'"tabulado"
  assert_status 1 dbx_path_seguro_para_linha "/pasta/nome"$'\r'"retorno"
}

teste_conversao_para_o_formato_da_api() {
  # A Dropbox representa a raiz como cadeia vazia, nao como "/".
  assert_igual '' "$(dbx_path_remoto_para_api '/')"
  assert_igual '/a/b' "$(dbx_path_remoto_para_api '/a/b')"
}

# ---------------------------------------------------------------------------
# Confinamento de raiz remota (RNF-20)
# ---------------------------------------------------------------------------

teste_caminho_dentro_da_raiz_e_aceito() {
  assert_igual '/backups/dia.tgz' "$(dbx_path_remoto_confinar '/backups' '/backups/dia.tgz')"
  assert_igual '/backups' "$(dbx_path_remoto_confinar '/backups' '/backups')"
  assert_igual '/backups/a/b' "$(dbx_path_remoto_confinar '/backups' '/backups/a/b/')"
}

teste_irmao_com_prefixo_comum_e_recusado() {
  # Defeito classico de comparacao por prefixo textual: `/backups2` NAO esta
  # dentro de `/backups`.
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/backups2/dia.tgz'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/backupsX'
}

teste_travessia_para_fora_da_raiz_e_recusada() {
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/backups/../segredos'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/backups/a/../../segredos'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/outra/pasta'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/'
}

teste_caminho_relativo_e_ancorado_na_raiz() {
  assert_igual '/backups/sub/arquivo' "$(dbx_path_remoto_confinar '/backups' 'sub/arquivo')"
  assert_igual '/backups/arquivo' "$(dbx_path_remoto_confinar '/backups' './arquivo')"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '../segredos'
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' 'a/../../segredos'
}

teste_confinamento_ignora_caixa_como_a_dropbox() {
  # A Dropbox resolve caminho sem diferenciar caixa. Comparar de forma sensivel
  # a caixa recusaria um caminho que o servico considera dentro da raiz.
  assert_igual '/BACKUPS/dia.tgz' "$(dbx_path_remoto_confinar '/backups' '/BACKUPS/dia.tgz')" \
    'a caixa original do caminho informado e preservada na saida'
  assert_sucesso dbx_path_remoto_confinar '/BackUps' '/backups/dia.tgz'
}

teste_raiz_barra_sem_opcao_explicita_falha_fechado() {
  # Operar sobre a conta inteira e uma decisao, nao um padrao silencioso. Antes,
  # raiz "/" desligava o confinamento por curto-circuito, sem que nada no uso
  # revelasse que a protecao de RNF-20 estava inativa.
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_remoto_confinar '/' '/qualquer/coisa'
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_remoto_confinar '/' '/qualquer/coisa' nao
}

teste_raiz_barra_com_opcao_explicita_opera_sem_confinamento() {
  assert_igual '/qualquer/coisa' "$(dbx_path_remoto_confinar '/' '/qualquer/coisa' sim)"
}

teste_raiz_barra_explicita_ainda_barra_travessia_acima_da_raiz() {
  # Desligar o confinamento nao pode desligar a normalizacao: `..` acima da raiz
  # continua sendo caminho invalido, e nao caminho permitido.
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/' '/../fora' sim
}

teste_opcao_de_raiz_total_nao_afeta_raiz_restrita() {
  # A opcao autoriza a raiz "/", e nao qualquer caminho: com raiz restrita, o
  # confinamento continua valendo integralmente mesmo com a opcao ligada.
  assert_igual '/backups/x' "$(dbx_path_remoto_confinar '/backups' '/backups/x' sim)"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_remoto_confinar '/backups' '/outra/x' sim
}

teste_valor_invalido_da_opcao_de_raiz_total_e_recusado() {
  assert_status "$DBX_PATH_USO_INVALIDO" dbx_path_remoto_confinar '/backups' '/backups/x' talvez
}

teste_raiz_local_barra_tambem_exige_opcao_explicita() {
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_local_confinar '/' '/etc/passwd'
  assert_sucesso dbx_path_local_confinar '/' '/etc/passwd' sim
}

teste_raiz_malformada_falha_fechado() {
  # Raiz ausente nunca pode ser interpretada como "sem restricao": seria uma
  # falha aberta, e o pior modo de falha possivel para RNF-20.
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_remoto_confinar '' '/a'
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_remoto_confinar 'backups' '/a'
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_remoto_confinar '/..' '/a'
  assert_status "$DBX_PATH_USO_INVALIDO" dbx_path_remoto_confinar '/backups' ''
}

teste_codigo_de_recusa_corresponde_a_taxonomia_de_erro() {
  # RNF-20 exige recusa antes de qualquer chamada de rede, e RF-29 exige que a
  # recusa tenha codigo de saida estavel.
  assert_igual "$(dbx_errors_codigo_saida caminho_recusado)" "$DBX_PATH_RECUSADO"
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_PATH_CONFIGURACAO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_PATH_USO_INVALIDO"
}

teste_confinamento_preserva_nomes_adversariais() {
  local esperado
  esperado='/backups/nome com espaco e $cifrao.txt'
  assert_igual "$esperado" "$(dbx_path_remoto_confinar '/backups' "$esperado")"
  esperado="/backups/nome"$'\n'"quebrado.txt"
  assert_igual "$esperado" "$(dbx_path_remoto_confinar '/backups' "$esperado")"
  esperado='/backups/*'
  assert_igual "$esperado" "$(dbx_path_remoto_confinar '/backups' "$esperado")"
}

# ---------------------------------------------------------------------------
# Confinamento de caminho local, com resolucao de links simbolicos
# ---------------------------------------------------------------------------

teste_caminho_local_dentro_da_raiz_e_aceito() {
  local area
  area=$(_area)
  mkdir -p "$area/raiz/sub"
  printf 'x' >"$area/raiz/sub/arquivo.txt"
  assert_igual "$area/raiz/sub/arquivo.txt" \
    "$(dbx_path_local_confinar "$area/raiz" "$area/raiz/sub/arquivo.txt")"
}

teste_link_simbolico_para_fora_da_raiz_e_recusado() {
  # Verificacao apenas lexical nao pega este caso: o caminho parece estar dentro
  # da raiz e aponta para fora dela.
  local area
  area=$(_area)
  mkdir -p "$area/raiz" "$area/fora"
  printf 'segredo' >"$area/fora/segredo.txt"
  ln -s "$area/fora" "$area/raiz/atalho"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/raiz/atalho/segredo.txt"
}

teste_link_simbolico_folha_para_fora_da_raiz_e_recusado() {
  local area
  area=$(_area)
  mkdir -p "$area/raiz" "$area/fora"
  printf 'segredo' >"$area/fora/segredo.txt"
  ln -s "$area/fora/segredo.txt" "$area/raiz/aparente.txt"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/raiz/aparente.txt"
}

teste_link_simbolico_interno_a_raiz_e_aceito() {
  local area
  area=$(_area)
  mkdir -p "$area/raiz/destino"
  printf 'x' >"$area/raiz/destino/arquivo.txt"
  ln -s "$area/raiz/destino" "$area/raiz/atalho"
  assert_igual "$area/raiz/destino/arquivo.txt" \
    "$(dbx_path_local_confinar "$area/raiz" "$area/raiz/atalho/arquivo.txt")" \
    'o caminho devolvido e o fisico, ja resolvido'
}

teste_travessia_local_por_ponto_ponto_e_recusada() {
  local area
  area=$(_area)
  mkdir -p "$area/raiz/sub" "$area/fora"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/raiz/../fora"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/raiz/sub/../../fora"
}

teste_irmao_local_com_prefixo_comum_e_recusado() {
  local area
  area=$(_area)
  mkdir -p "$area/raiz" "$area/raiz2"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/raiz2"
}

teste_destino_local_ainda_inexistente_e_aceito_dentro_da_raiz() {
  # Caso real do recebimento de arquivo: o destino ainda nao existe.
  local area
  area=$(_area)
  mkdir -p "$area/raiz"
  assert_igual "$area/raiz/novo/arquivo.bin" \
    "$(dbx_path_local_confinar "$area/raiz" "$area/raiz/novo/arquivo.bin")"
}

teste_destino_local_inexistente_com_travessia_e_recusado() {
  local area
  area=$(_area)
  mkdir -p "$area/raiz"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/raiz/novo/../../fora/arquivo.bin"
}

teste_raiz_local_inexistente_falha_fechado() {
  local area
  area=$(_area)
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_local_confinar "$area/nao-existe" "$area/nao-existe/a"
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_local_confinar '' "$area/a"
  assert_status "$DBX_PATH_CONFIGURACAO" dbx_path_local_confinar 'relativa' "$area/a"
}

teste_nome_local_com_espacos_e_quebra_de_linha() {
  local area destino
  area=$(_area)
  mkdir -p "$area/raiz"
  destino="$area/raiz/nome com espaco e "$'\n'" quebra.txt"
  assert_igual "$destino" "$(dbx_path_local_confinar "$area/raiz" "$destino")" \
    'nomes adversariais nao podem ser corrompidos na resolucao (RNF-10)'
}

teste_confinamento_local_e_sensivel_a_caixa() {
  # Ao contrario do espaco remoto, o sistema de arquivos alvo diferencia caixa.
  local area
  area=$(_area)
  mkdir -p "$area/raiz" "$area/RAIZ"
  assert_status "$DBX_PATH_RECUSADO" dbx_path_local_confinar "$area/raiz" "$area/RAIZ/arquivo"
}

# ---------------------------------------------------------------------------
# C2-01 — a RAIZ tambem precisa ser resolvida sem substituicao de comando.
#
# Regressao do ciclo 1: `$( )` foi removido do caminho, mas mantido na
# resolucao da raiz, com um comentario afirmando que raiz terminada em quebra
# de linha seria "configuracao invalida" — algo que o codigo nunca verificava.
# A falha era ABERTA nas duas direcoes.
# ---------------------------------------------------------------------------

teste_raiz_com_quebra_de_linha_final_nao_alcanca_a_raiz_vizinha() {
  local area status
  area=$(_area)
  mkdir -p "$area/raiz" "$area/raiz"$'\n'
  printf 'DADO-DE-FORA' > "$area/raiz/segredo"
  printf 'DADO-DE-DENTRO' > "$area/raiz"$'\n'"/segredo"

  dbx_path_local_confinar "$area/raiz"$'\n' 'segredo' >/dev/null
  status=$?
  if [[ $status -eq 0 ]]; then
    assert_igual "$area/raiz"$'\n'"/segredo" "$DBX_PATH_RESULTADO" \
      'a raiz configurada e `raiz\n`; alcancar `raiz` e evasao de confinamento'
    assert_igual 'DADO-DE-DENTRO' "$(cat -- "$DBX_PATH_RESULTADO")" \
      'o conteudo lido tem de vir da raiz configurada'
  fi
}

teste_raiz_com_quebra_de_linha_nao_captura_caminho_da_raiz_vizinha() {
  # Direcao inversa: acesso legitimo dentro de `raiz\n` nao pode ser gravado
  # dentro de `raiz`.
  local area
  area=$(_area)
  mkdir -p "$area/raiz" "$area/raiz"$'\n'
  dbx_path_local_confinar "$area/raiz"$'\n' 'interno' >/dev/null
  assert_diferente "$area/raiz/interno" "$DBX_PATH_RESULTADO" \
    'o destino nao pode escorregar para a raiz vizinha'
}

teste_resultado_e_limpo_quando_a_raiz_total_nao_e_autorizada() {
  # C2-06: `|| return $?` saia antes da limpeza e deixava `/` residual — o pior
  # valor possivel num componente que declara falhar fechado.
  local area
  area=$(_area)
  mkdir -p "$area/raiz"
  dbx_path_local_confinar "$area/raiz" "$area/raiz/valido" >/dev/null
  dbx_path_local_confinar '/' '/etc/passwd' >/dev/null
  assert_igual '' "$DBX_PATH_RESULTADO" \
    'raiz total recusada precisa zerar o resultado'
  dbx_path_remoto_confinar '/backups' '/backups/ok' >/dev/null
  dbx_path_remoto_confinar '/' '/qualquer' >/dev/null
  assert_igual '' "$DBX_PATH_RESULTADO" \
    'idem no espaco remoto'
}

harness_executar "$@"
