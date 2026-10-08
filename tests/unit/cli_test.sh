#!/usr/bin/env bash
# Testes de lib/cli.sh — interpretacao de opcoes globais e despacho.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"
. "$DBX_HARNESS_RAIZ/lib/cli.sh"

# ---------------------------------------------------------------------------
# Despacho por tabela fechada
# ---------------------------------------------------------------------------

teste_comando_conhecido_e_aceito() {
  local nome
  for nome in upload download list delete info space config unlink sync; do
    dbx_cli_comando_valido "$nome" ||
      _harness_falhar "comando previsto no bloco foi recusado: $nome"
  done
  return 0
}

teste_comando_desconhecido_e_recusado() {
  local nome
  # O conjunto fechado ficou completo com `sync`. O que precisa continuar sendo
  # recusado e o que nunca sera comando — inclusive as formas quase certas, que
  # sao as que um `case` mal escrito deixaria passar.
  for nome in inexistente '' 'sync ' ' sync' 'sync;rm'; do
    dbx_cli_comando_valido "$nome" &&
      _harness_falhar "comando fora do bloco foi aceito: [$nome]"
  done
  return 0
}

teste_nome_de_comando_nunca_compoe_caminho_de_arquivo() {
  # O nome vem de fora. Compor `commands/$1.sh` seria derivar caminho de origem
  # externa — a classe que RNF-24 proibe no analisador, aqui com consequencia
  # pior: execucao de codigo arbitrario.
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/cli.sh" |
    grep -nE 'commands/\$|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\.sh|/\$[A-Za-z_]' || true)
  [[ -n $achados ]] &&
    _harness_falhar "caminho de comando composto a partir de variavel: $achados"
  return 0
}

teste_travessia_no_nome_do_comando_e_recusada() {
  local nome
  for nome in '../lib/errors' 'list/../../etc/passwd' 'li st' 'LIST' 'list;rm'; do
    dbx_cli_comando_valido "$nome" &&
      _harness_falhar "nome perigoso aceito: [$nome]"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Opcoes globais
# ---------------------------------------------------------------------------

teste_opcoes_globais_antes_do_comando() {
  dbx_cli_analisar --json --null --dry-run list /a
  assert_igual 0 $? 'analise deve concluir'
  assert_igual 'list' "$DBX_CLI_COMANDO" 'comando'
  assert_igual 'sim' "$DBX_CLI_ESTRUTURADA" 'saida estruturada'
  assert_igual 'sim' "$DBX_CLI_NULO" 'terminador nulo'
  assert_igual 'sim' "$DBX_CLI_SIMULACAO" 'modo de simulacao'
  assert_igual '/a' "${DBX_CLI_ARGS[0]}" 'argumento do comando'
}

teste_opcoes_apos_o_comando_pertencem_ao_comando() {
  # `--json` depois do subcomando NAO e opcao global: pertence ao comando, que
  # pode ter opcao de mesmo nome. Sem esta fronteira, o despacho consumiria
  # argumento alheio e o comando receberia lista incompleta.
  dbx_cli_analisar list --json /a
  assert_igual 'list' "$DBX_CLI_COMANDO" 'comando'
  assert_igual 'nao' "$DBX_CLI_ESTRUTURADA" 'opcao apos o comando nao e global'
  assert_igual '--json' "${DBX_CLI_ARGS[0]}" 'opcao deve chegar ao comando'
}

teste_separador_de_fim_de_opcoes_e_respeitado() {
  local estado
  dbx_cli_analisar --json -- --nao-e-opcao
  estado=$?
  # O status e capturado ANTES de qualquer assercao: assercao e comando, e
  # comando redefine `$?`. Ler `$?` depois mediria a assercao, nao a analise.
  assert_igual "$DBX_CLI_ERRO_USO" "$estado" 'sem comando a analise deve recusar'
  assert_igual '' "$DBX_CLI_COMANDO" 'apos o separador nao ha comando global'
}

teste_opcao_global_desconhecida_e_recusada() {
  dbx_cli_analisar --opcao-que-nao-existe list
  assert_igual "$DBX_CLI_ERRO_USO" $? 'opcao global desconhecida deve recusar'
  assert_contem 'opcao-que-nao-existe' "$DBX_CLI_MOTIVO" 'o motivo deve nomear a opcao'
}

teste_ausencia_de_comando_e_uso_invalido() {
  dbx_cli_analisar
  assert_igual "$DBX_CLI_ERRO_USO" $? 'sem argumento algum'
  dbx_cli_analisar --json
  assert_igual "$DBX_CLI_ERRO_USO" $? 'so com opcao global'
}

teste_ajuda_e_versao_sao_comandos_e_nao_opcoes_pendentes() {
  dbx_cli_analisar --version
  assert_igual 0 $? 'versao deve ser aceita sem comando'
  assert_igual 'version' "$DBX_CLI_COMANDO" 'versao vira comando interno'
  dbx_cli_analisar --help
  assert_igual 0 $? 'ajuda deve ser aceita sem comando'
  assert_igual 'help' "$DBX_CLI_COMANDO" 'ajuda vira comando interno'
}

# ---------------------------------------------------------------------------
# Politica de verificacao previa
# ---------------------------------------------------------------------------

teste_todo_comando_declara_seu_requisito_de_ambiente() {
  # Regra do conjunto: a disciplina so vale se alguem ENUMERA os lugares onde
  # ela incide. O conjunto e derivado dos arquivos de comando, e nao de lista
  # mantida a mao.
  local arquivo nome faltando=()
  for arquivo in "$DBX_HARNESS_RAIZ"/commands/*.sh; do
    [[ -e $arquivo ]] || continue
    nome=${arquivo##*/}
    nome=${nome%.sh}
    grep -qE "^dbx_cmd_${nome}_requisitos\(\)" "$arquivo" ||
      faltando+=("$nome nao declara requisito")
    grep -qE "^dbx_cmd_${nome}_executar\(\)" "$arquivo" ||
      faltando+=("$nome nao define execucao")
  done
  [[ ${#faltando[@]} -eq 0 ]] ||
    _harness_falhar 'comando sem contrato declarado' "${faltando[@]}"
  return 0
}

teste_requisito_declarado_pertence_ao_vocabulario_fechado() {
  local arquivo nome valor
  for arquivo in "$DBX_HARNESS_RAIZ"/commands/*.sh; do
    [[ -e $arquivo ]] || continue
    nome=${arquivo##*/}
    nome=${nome%.sh}
    # shellcheck source=/dev/null
    . "$arquivo"
    valor=$("dbx_cmd_${nome}_requisitos")
    case $valor in
      nenhum | ambiente | credencial) ;;
      *) _harness_falhar "requisito fora do vocabulario: $nome -> [$valor]" ;;
    esac
  done
  return 0
}

teste_ajuda_e_versao_nao_exigem_ambiente() {
  # Falso negativo de verificacao previa trava uso legitimo: pedir ajuda numa
  # maquina sem o cliente de rede tem de funcionar.
  assert_igual 'nenhum' "$(dbx_cli_requisito_interno help)" 'ajuda'
  assert_igual 'nenhum' "$(dbx_cli_requisito_interno version)" 'versao'
}


teste_tabela_de_despacho_e_os_arquivos_de_comando_se_correspondem() {
  # O UNIVERSO DERIVA DO ARTEFATO. A tabela e de nomes literais, escrita a mao, e
  # e por isso que ela precisa ser confrontada com o conjunto que ninguem mantem
  # a mao: os arquivos em `commands/`. Comando novo que chegue sem entrada na
  # tabela reprova aqui, e nao no primeiro uso.
  # A resolucao le `DBX_CLI_RAIZ`, que o ponto de entrada publica. Aqui ele e
  # definido explicitamente: sem isso a funcao falharia por variavel ausente e a
  # auditoria acusaria divergencia onde ha so ambiente incompleto.
  # shellcheck disable=SC2034  # lida DENTRO da funcao sob teste, que a analise
  # estatica nao segue por ser de outro arquivo.
  local DBX_CLI_RAIZ=$DBX_HARNESS_RAIZ
  local arquivo nome destino faltando=()
  for arquivo in "$DBX_HARNESS_RAIZ"/commands/*.sh; do
    [[ -e $arquivo ]] || continue
    nome=${arquivo##*/}
    nome=${nome%.sh}
    dbx_cli_comando_valido "$nome" ||
      faltando+=("$nome tem arquivo e nao esta na tabela de nomes")
    destino=$(_dbx_cli_arquivo_do_comando "$nome") ||
      faltando+=("$nome nao resolve para arquivo algum")
    [[ $destino == "$arquivo" ]] ||
      faltando+=("$nome resolve para [$destino] em vez de [$arquivo]")
  done
  [[ ${#faltando[@]} -eq 0 ]] ||
    _harness_falhar 'tabela de despacho e arquivos de comando divergem' "${faltando[@]}"
  return 0
}

teste_nome_sem_arquivo_nao_resolve_para_caminho() {
  # O outro sentido da correspondencia: o que a tabela nao conhece nao pode
  # produzir caminho. Sem este caso, um `*)` que devolvesse caminho qualquer
  # passaria pela auditoria acima, que so percorre os arquivos existentes.
  local destino
  destino=$(_dbx_cli_arquivo_do_comando sync) &&
    _harness_falhar "nome fora da tabela resolveu para caminho: [$destino]"
  destino=$(_dbx_cli_arquivo_do_comando '../../etc/passwd') &&
    _harness_falhar "nome arbitrario resolveu para caminho: [$destino]"
  return 0
}

harness_executar "$@"
