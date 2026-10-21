#!/usr/bin/env bash
# Testes de lib/cli.sh para a opcao global --perfil (F-18, RF-120, RF-121(g),
# DIV-241; TC-PFS-01..08, TC-PFN-09, TC-PFN-10).
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/path.sh"
. "$DBX_HARNESS_RAIZ/lib/output.sh"
. "$DBX_HARNESS_RAIZ/lib/cli.sh"
DBX_CLI_RAIZ=$DBX_HARNESS_RAIZ

teste_pfs05_perfil_e_profile_equivalem_antes_do_subcomando() {
  dbx_cli_analisar --perfil a space || _harness_falhar "--perfil: $DBX_CLI_MOTIVO"
  assert_igual a "$DBX_CLI_PERFIL" 'nome'
  assert_igual space "$DBX_CLI_COMANDO" 'comando'
  dbx_cli_analisar --profile b --json space || _harness_falhar "--profile: $DBX_CLI_MOTIVO"
  assert_igual b "$DBX_CLI_PERFIL" 'nome'
}

teste_pfs06_sem_valor_sai_2() {
  dbx_cli_analisar --perfil
  assert_igual 2 $? 'sem valor'
}

teste_pfs07_repeticao_sai_2_mesmo_igual() {
  dbx_cli_analisar --perfil a --perfil a space
  assert_igual 2 $? 'repetida'
  dbx_cli_analisar --perfil a --profile a space
  assert_igual 2 $? 'repetida com alias'
}

teste_pfs08_depois_do_subcomando_so_em_config_e_unlink() {
  dbx_cli_analisar config --perfil a || _harness_falhar "config: $DBX_CLI_MOTIVO"
  assert_igual a "$DBX_CLI_PERFIL" 'config'
  assert_igual '--perfil a' "${DBX_CLI_ARGS[*]}" 'os argumentos seguem com o comando'
  dbx_cli_analisar unlink --yes --profile b || _harness_falhar "unlink: $DBX_CLI_MOTIVO"
  assert_igual b "$DBX_CLI_PERFIL" 'unlink'
  dbx_cli_analisar space --perfil a
  assert_igual 'space' "$DBX_CLI_COMANDO" 'space despacha; a opcao e do comando (desconhecida la)'
  assert_igual '' "$DBX_CLI_PERFIL" 'nao selecionou'
}

teste_pfs_depois_do_subcomando_repeticao_e_valor_de_raiz() {
  dbx_cli_analisar --perfil a config --perfil a
  assert_igual 2 $? 'repeticao antes e depois'
  dbx_cli_analisar config --perfil a --profile a
  assert_igual 2 $? 'repeticao depois'
  dbx_cli_analisar config --raiz --perfil
  assert_igual 0 $? '--perfil como VALOR de --raiz nao e a opcao'
  assert_igual '' "$DBX_CLI_PERFIL" 'nao selecionou'
  dbx_cli_analisar config --perfil
  assert_igual 2 $? 'depois do subcomando, sem valor'
}

teste_pfn10_nome_invalido_em_qualquer_comando_sai_2() {
  local nome
  for nome in 'Ab' '../x' '' 'a b' '-a'; do
    dbx_cli_analisar --perfil "$nome" completar bash
    assert_igual 2 $? "completar com [$nome]"
    dbx_cli_analisar --perfil "$nome" space
    assert_igual 2 $? "space com [$nome]"
  done
  dbx_cli_analisar config --perfil Ab
  assert_igual 2 $? 'depois do subcomando'
  assert_contem 'perfil' "$DBX_CLI_MOTIVO" 'mensagem'
}

teste_pfn10_help_e_version_curto_circuitam_na_ordem_da_analise() {
  dbx_cli_analisar --perfil ok help
  assert_igual 0 $? 'perfil valido e help'
  assert_igual help "$DBX_CLI_COMANDO" 'help'
  dbx_cli_analisar --help --perfil Ab
  assert_igual 0 $? 'help antes do nome invalido'
  assert_igual help "$DBX_CLI_COMANDO" 'help'
  dbx_cli_analisar config --help --perfil Ab
  assert_igual 0 $? 'depois do subcomando, --help vence'
}

teste_pfs_aplicar_opcao_vence_variavel_e_vazio_e_nao_definida() {
  . "$DBX_HARNESS_RAIZ/lib/json.sh"
  . "$DBX_HARNESS_RAIZ/lib/config.sh"
  DBX_PERFIL=a
  dbx_cli_analisar --perfil b space
  dbx_cli_perfil_aplicar
  assert_igual b "$DBX_CONFIG_PERFIL" 'opcao vence'
  assert_igual opcao "$DBX_CONFIG_PERFIL_ORIGEM" 'origem'
  DBX_CONFIG_PERFIL='' DBX_CONFIG_PERFIL_ORIGEM=''
  dbx_cli_analisar space
  dbx_cli_perfil_aplicar
  assert_igual a "$DBX_CONFIG_PERFIL" 'variavel'
  assert_igual ambiente "$DBX_CONFIG_PERFIL_ORIGEM" 'origem'
  DBX_CONFIG_PERFIL='' DBX_CONFIG_PERFIL_ORIGEM=''
  DBX_PERFIL=''
  dbx_cli_perfil_aplicar
  assert_igual '' "$DBX_CONFIG_PERFIL_ORIGEM" 'vazia = nao definida'
}

teste_pfn09_variavel_invalida_so_e_validada_quando_usada() {
  . "$DBX_HARNESS_RAIZ/lib/json.sh"
  . "$DBX_HARNESS_RAIZ/lib/config.sh"
  DBX_PERFIL='SEGREDO'
  dbx_cli_analisar --perfil ok space
  dbx_cli_perfil_aplicar
  assert_igual 0 $? 'a opcao vence; a variavel nao e validada'
  DBX_CONFIG_PERFIL='' DBX_CONFIG_PERFIL_ORIGEM=''
  dbx_cli_analisar space
  dbx_cli_perfil_aplicar
  assert_igual 2 $? 'usada e invalida'
  assert_segredo_ausente SEGREDO "$DBX_CLI_MOTIVO" 'nao ecoa o valor'
}

harness_executar "$@"
