#!/usr/bin/env bash
# Testes de lib/config.sh para perfis nomeados de credencial (F-18, fase 8).
# RF-120..RF-122, RF-125 (identidade), RF-126 (leitura), RNF-37; TC-PFN, TC-PFC.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"

_area() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/perfis.XXXXXX") || return 1
  (cd -P -- "$dir" && pwd -P)
}

_xdg() {
  XDG_CONFIG_HOME="$1/config"
  export XDG_CONFIG_HOME
  unset DBX_PERFIL
}

# _escrever <arquivo> <app_key> <refresh>
_escrever() {
  mkdir -p "${1%/*}"
  printf '{"versao":1,"app_key":"%s","app_secret":"seg","refresh_token":"%s","raiz_remota":"/"}' "$2" "$3" >"$1"
  chmod 600 "$1"
}

_perfil_seguro() { # <area> <nome> <app_key> <refresh>
  mkdir -p "$1/config/dbx/perfis"
  chmod 700 "$1/config/dbx" "$1/config/dbx/perfis"
  _escrever "$1/config/dbx/perfis/$2.json" "$3" "$4"
}

# ---------------------------------------------------------------------------
# TC-PFN: gramatica
# ---------------------------------------------------------------------------

teste_pfn01_nomes_validos_de_1_e_32_caracteres() {
  local n32
  printf -v n32 '%032d' 7
  dbx_config_perfil_validar a || _harness_falhar 'a'
  dbx_config_perfil_validar 9_x-y || _harness_falhar '9_x-y'
  dbx_config_perfil_validar "$n32" || _harness_falhar '32 caracteres'
  dbx_config_perfil_validar padrao || _harness_falhar 'padrao e valido'
}

teste_pfn02_trinta_e_tres_caracteres_recusado_com_2() {
  local n33
  printf -v n33 '%033d' 7
  dbx_config_perfil_validar "$n33"
  assert_igual 2 $? '33 caracteres'
}

teste_pfn03_a_pfn06_nomes_invalidos_recusados_com_2() {
  local nome
  for nome in '../x' 'a/b' 'a\b' '.' '..' 'A' 'á' 'a b' $'a\tb' $'a\nb' $'a\001b' '-a' '_a' '' $'a\n'; do
    dbx_config_perfil_validar "$nome"
    assert_igual 2 $? "nome invalido aceito: [${nome//[^[:print:]]/?}]"
  done
}

teste_pfn_validacao_nao_toca_disco() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_perfil_validar '../x'
  dbx_config_perfil_selecionar 'A' opcao
  [[ ! -e $area/config ]] || _harness_falhar 'a validacao criou o diretorio de configuracao'
  assert_igual '' "${DBX_CONFIG_PERFIL:-}" 'nome invalido nao pode ficar selecionado'
}

teste_pfn09_valor_invalido_do_ambiente_nao_e_ecoado() {
  DBX_PERFIL='SEGREDO-NO-AMBIENTE'
  dbx_config_perfil_do_ambiente
  assert_igual 2 $? 'DBX_PERFIL invalida'
  assert_segredo_ausente 'SEGREDO-NO-AMBIENTE' "$DBX_CONFIG_DETALHE|$DBX_CONFIG_MOTIVO" 'valor da variavel nao pode sair em mensagem'
  assert_contem 'a-z' "$DBX_CONFIG_DETALHE" 'a mensagem cita a gramatica'
  unset DBX_PERFIL
}

teste_pfn_nome_da_opcao_invalido_e_citado_truncado() {
  local longo
  printf -v longo 'X%0100d' 1
  dbx_config_perfil_validar "$longo" opcao
  assert_contem 'X000' "$DBX_CONFIG_DETALHE" 'cita o nome da opcao'
  assert_nao_contem "$longo" "$DBX_CONFIG_DETALHE" 'truncado em 64 bytes'
}

# ---------------------------------------------------------------------------
# RF-120: selecao e precedencia
# ---------------------------------------------------------------------------

teste_pfs_ambiente_vazio_equivale_a_nao_definida() {
  DBX_PERFIL=''
  dbx_config_perfil_do_ambiente
  assert_igual 0 $? 'vazio e nao definida'
  assert_igual '' "$DBX_CONFIG_PERFIL_ORIGEM" 'sem selecao'
  unset DBX_PERFIL
}

teste_pfs_ambiente_seleciona_com_origem_ambiente() {
  DBX_PERFIL=trabalho
  dbx_config_perfil_do_ambiente
  assert_igual trabalho "$DBX_CONFIG_PERFIL" 'nome'
  assert_igual ambiente "$DBX_CONFIG_PERFIL_ORIGEM" 'origem'
  unset DBX_PERFIL
}

teste_pfs_opcao_vence_a_variavel() {
  DBX_PERFIL=a
  dbx_config_perfil_selecionar b opcao
  dbx_config_perfil_do_ambiente
  assert_igual b "$DBX_CONFIG_PERFIL" 'a opcao vence'
  assert_igual opcao "$DBX_CONFIG_PERFIL_ORIGEM" 'origem opcao'
  unset DBX_PERFIL
}

# ---------------------------------------------------------------------------
# TC-PFC: caminho e verificacoes
# ---------------------------------------------------------------------------

teste_pfc01_padrao_resolve_credencial_json_como_hoje() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_caminho
  assert_igual "$area/config/dbx/credencial.json" "$DBX_CONFIG_RESULTADO" 'sem selecao'
  dbx_config_perfil_selecionar padrao opcao
  dbx_config_caminho
  assert_igual "$area/config/dbx/credencial.json" "$DBX_CONFIG_RESULTADO" '--perfil padrao'
}

teste_pfc02_outro_nome_resolve_perfis_nome_json() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_perfil_selecionar trabalho opcao
  dbx_config_caminho
  assert_igual "$area/config/dbx/perfis/trabalho.json" "$DBX_CONFIG_RESULTADO"
}

teste_pfc_composicao_so_com_nome_validado() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_caminho_de_perfil '../x'
  assert_igual 2 $? 'nome cru nao vira caminho'
  assert_igual '' "$DBX_CONFIG_RESULTADO" 'nenhum caminho publicado'
}

teste_pfc03_perfil_ausente_nao_recua_para_o_padrao() {
  local area
  area=$(_area)
  _xdg "$area"
  mkdir -p "$area/config/dbx"
  chmod 700 "$area/config/dbx"
  _escrever "$area/config/dbx/credencial.json" PAD rt-padrao
  dbx_config_perfil_selecionar ausente opcao
  dbx_config_carregar
  assert_igual 3 $? 'ausente sai 3'
  assert_igual ausente "$DBX_CONFIG_MOTIVO" 'motivo'
  assert_igual '' "$DBX_CONFIG_REFRESH_TOKEN" 'nao carregou o padrao'
}

teste_pfc_perfil_carrega_do_seu_arquivo() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar || _harness_falhar "carga: $DBX_CONFIG_MOTIVO"
  assert_igual AKA "$DBX_CONFIG_APP_KEY" 'app key do perfil'
  assert_igual rta "$DBX_CONFIG_REFRESH_TOKEN" 'refresh do perfil'
}

teste_pfc04_arquivo_do_perfil_0644_recusado() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  chmod 644 "$area/config/dbx/perfis/a.json"
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar
  assert_igual 3 $? 'status'
  assert_igual permissao "$DBX_CONFIG_MOTIVO" 'motivo'
}

teste_pfc05_perfis_0755_recusado() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  chmod 755 "$area/config/dbx/perfis"
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar
  assert_igual 3 $? 'status'
  assert_igual permissao_diretorio "$DBX_CONFIG_MOTIVO" 'motivo'
  assert_igual "$area/config/dbx/perfis" "$DBX_CONFIG_DETALHE" 'o detalhe nomeia o diretorio'
}

teste_pfc06_dbx_0755_recusado_para_perfil() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  chmod 755 "$area/config/dbx"
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar
  assert_igual 3 $? 'status'
  assert_igual permissao_diretorio "$DBX_CONFIG_MOTIVO" 'motivo'
}

teste_pfc07_perfis_ligacao_simbolica_recusado_sem_ler() {
  local area alvo
  area=$(_area)
  _xdg "$area"
  alvo="$area/atacante"
  mkdir -p "$alvo" "$area/config/dbx"
  chmod 700 "$alvo" "$area/config/dbx"
  _escrever "$alvo/a.json" ATK rt-atacante
  ln -s "$alvo" "$area/config/dbx/perfis"
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar
  assert_igual 3 $? 'status'
  assert_igual ligacao_simbolica "$DBX_CONFIG_MOTIVO" 'motivo'
  assert_igual '' "$DBX_CONFIG_REFRESH_TOKEN" 'nada lido'
}

teste_pfc08_arquivo_do_perfil_ligacao_simbolica_inclusive_pendente() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" real AKR rtr
  ln -s real.json "$area/config/dbx/perfis/ln.json"
  dbx_config_perfil_selecionar ln opcao
  dbx_config_carregar
  assert_igual ligacao_simbolica "$DBX_CONFIG_MOTIVO" 'simbolica valida'
  ln -s nao-existe.json "$area/config/dbx/perfis/pend.json"
  dbx_config_perfil_selecionar pend opcao
  dbx_config_carregar
  assert_igual ligacao_simbolica "$DBX_CONFIG_MOTIVO" 'simbolica pendente'
}

teste_pfc13_dbx_ligacao_simbolica_recusada_para_perfil() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  mv "$area/config/dbx" "$area/real-dbx"
  ln -s "$area/real-dbx" "$area/config/dbx"
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar
  assert_igual ligacao_simbolica "$DBX_CONFIG_MOTIVO" 'dbx/ simbolica'
}

teste_pfc_padrao_reservado_nunca_le_perfis_padrao_json() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" padrao AKX rtx
  dbx_config_perfil_selecionar padrao opcao
  dbx_config_carregar
  assert_igual ausente "$DBX_CONFIG_MOTIVO" 'perfis/padrao.json e reservado'
}

# ---------------------------------------------------------------------------
# Gravacao e remocao
# ---------------------------------------------------------------------------

teste_pfg01_gravar_cria_perfis_0700_e_arquivo_0600() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_perfil_selecionar trabalho opcao
  dbx_config_gravar AK AS RT /r || _harness_falhar "gravar: $DBX_CONFIG_MOTIVO"
  assert_igual 700 "$(stat -c %a "$area/config/dbx/perfis")" 'perfis/'
  assert_igual 600 "$(stat -c %a "$area/config/dbx/perfis/trabalho.json")" 'arquivo'
  assert_arquivo_ausente "$area/config/dbx/credencial.json" 'o padrao nao e criado'
}

teste_pfg04_destino_inseguro_recusado_antes_de_gravar() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  chmod 755 "$area/config/dbx/perfis"
  dbx_config_perfil_selecionar novo opcao
  dbx_config_verificar_destino
  assert_igual 3 $? 'verificacao previa recusa'
  assert_igual permissao_diretorio "$DBX_CONFIG_MOTIVO" 'motivo'
  dbx_config_gravar AK AS RT /r
  assert_igual 3 $? 'gravar tambem recusa'
  assert_arquivo_ausente "$area/config/dbx/perfis/novo.json" 'nada gravado'
}

teste_pfg05_destino_ligacao_simbolica_pendente_recusado() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  ln -s /nao/existe "$area/config/dbx/perfis/novo.json"
  dbx_config_perfil_selecionar novo opcao
  dbx_config_verificar_destino
  assert_igual ligacao_simbolica "$DBX_CONFIG_MOTIVO" 'alvo simbolico'
}

teste_pfg_verificar_destino_do_padrao_nao_recusa_nada_novo() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_verificar_destino
  assert_igual 0 $? 'padrao: como hoje'
}

teste_pfc11_gravar_e_remover_varrem_orfaos_em_perfis() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  printf x >"$area/config/dbx/perfis/.credencial.999999.AAAAAAAA"
  dbx_config_perfil_selecionar b opcao
  dbx_config_gravar AK AS RT /r
  assert_arquivo_ausente "$area/config/dbx/perfis/.credencial.999999.AAAAAAAA" 'varrido ao gravar'
  printf x >"$area/config/dbx/perfis/.credencial.999998.AAAAAAAA"
  dbx_config_remover integral
  assert_arquivo_ausente "$area/config/dbx/perfis/.credencial.999998.AAAAAAAA" 'varrido ao remover'
  printf x >"$area/config/dbx/perfis/.credencial.999997.AAAAAAAA"
  dbx_config_perfil_selecionar padrao opcao
  dbx_config_remover integral
  assert_arquivo_ausente "$area/config/dbx/perfis/.credencial.999997.AAAAAAAA" 'varrido no padrao'
}

teste_pfu11_remover_perfil_remove_perfis_vazio() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  dbx_config_perfil_selecionar a opcao
  dbx_config_remover integral
  assert_arquivo_ausente "$area/config/dbx/perfis/a.json" 'arquivo'
  [[ ! -d $area/config/dbx/perfis ]] || _harness_falhar 'perfis/ vazio devia sair'
}

teste_pfu_remover_nao_segue_perfis_ligacao_simbolica() {
  local area alvo
  area=$(_area)
  _xdg "$area"
  alvo="$area/atacante"
  mkdir -p "$alvo" "$area/config/dbx"
  chmod 700 "$area/config/dbx"
  _escrever "$alvo/a.json" ATK rta
  ln -s "$alvo" "$area/config/dbx/perfis"
  dbx_config_perfil_selecionar a opcao
  dbx_config_remover integral
  assert_igual 3 $? 'recusa'
  assert_arquivo_existe "$alvo/a.json" 'nada apagado atraves da ligacao'
}

teste_pfu06_manter_aplicativo_regrava_o_perfil() {
  local area conteudo
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AKA rta
  dbx_config_perfil_selecionar a opcao
  dbx_config_carregar
  dbx_config_remover aplicativo || _harness_falhar "aplicativo: $DBX_CONFIG_MOTIVO"
  IFS= read -r -d '' conteudo <"$area/config/dbx/perfis/a.json"
  assert_contem '"app_key":"AKA"' "$conteudo" 'chave preservada'
  assert_segredo_ausente rta "$conteudo" 'refresh removido'
}

# ---------------------------------------------------------------------------
# Identidade, listagem e mascaramento
# ---------------------------------------------------------------------------

teste_pfu08_identidade_de_perfil_e_igual_para_a_mesma_credencial() {
  local area ia ib ic
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AK rt
  _perfil_seguro "$area" b AK rt
  _perfil_seguro "$area" c AK outro
  dbx_config_identidade_de_perfil a
  ia=$DBX_CONFIG_IDENTIDADE
  dbx_config_identidade_de_perfil b
  ib=$DBX_CONFIG_IDENTIDADE
  dbx_config_identidade_de_perfil c
  ic=$DBX_CONFIG_IDENTIDADE
  [[ $ia == cred-* ]] || _harness_falhar 'identidade a'
  assert_igual "$ia" "$ib" 'mesma credencial, mesma identidade'
  assert_diferente "$ia" "$ic" 'refresh diferente, identidade diferente'
  assert_igual '' "$DBX_CONFIG_REFRESH_TOKEN" 'canais esvaziados entre perfis'
  assert_igual '' "$DBX_CONFIG_APP_KEY" 'canais esvaziados entre perfis'
}

teste_pfc12_identidade_de_perfil_ilegivel_falha_sem_identidade() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AK rt
  chmod 644 "$area/config/dbx/perfis/a.json"
  dbx_config_identidade_de_perfil a
  assert_igual 3 $? 'nao comparavel'
  assert_igual '' "$DBX_CONFIG_IDENTIDADE" 'sem identidade'
}

teste_pfl_listar_padrao_primeiro_e_ordem_de_bytes() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" b AK rt
  _perfil_seguro "$area" a AK rt
  _perfil_seguro "$area" 0z AK rt
  _escrever "$area/config/dbx/credencial.json" PAD rtp
  dbx_config_perfis_listar
  assert_igual 'padrao 0z a b' "${DBX_CONFIG_PERFIS_NOME[*]}" 'ordem'
  assert_igual 'completa completa completa completa' "${DBX_CONFIG_PERFIS_CREDENCIAL[*]}" 'veredito'
}

teste_pfl03_padrao_so_aparece_se_existir() {
  local area
  area=$(_area)
  _xdg "$area"
  _perfil_seguro "$area" a AK rt
  dbx_config_perfis_listar
  assert_igual 'a' "${DBX_CONFIG_PERFIS_NOME[*]}" 'sem credencial.json'
}

teste_pfl05_vocabulario_do_veredito() {
  local area d
  area=$(_area)
  _xdg "$area"
  d="$area/config/dbx/perfis"
  _perfil_seguro "$area" completa AK rt
  _perfil_seguro "$area" semrefresh AK ''
  : >"$d/vazio.json"
  chmod 600 "$d/vazio.json"
  _perfil_seguro "$area" aberto AK rt
  chmod 644 "$d/aberto.json"
  ln -s completa.json "$d/simb.json"
  printf '{"versao":1,"app_key":"AK","app_secret":"","refresh_token":"rt","raiz_remota":"/"}' >"$d/semsegredo.json"
  chmod 600 "$d/semsegredo.json"
  dbx_config_perfis_listar
  local i mapa=''
  for i in "${!DBX_CONFIG_PERFIS_NOME[@]}"; do
    mapa+="${DBX_CONFIG_PERFIS_NOME[i]}=${DBX_CONFIG_PERFIS_CREDENCIAL[i]} "
  done
  assert_igual 'aberto=permissao completa=completa semrefresh=incompleta semsegredo=incompleta simb=ligacao_simbolica vazio=ilegivel ' "$mapa" 'vocabulario'
  assert_igual '' "$DBX_CONFIG_REFRESH_TOKEN$DBX_CONFIG_APP_SECRET" 'canais vazios ao final'
}

teste_pfl08_entradas_anomalas_nao_viram_registro() {
  local area d
  area=$(_area)
  _xdg "$area"
  d="$area/config/dbx/perfis"
  _perfil_seguro "$area" ok AK rt
  _escrever "$d/Foo.json" AK rt
  _escrever "$d/padrao.json" AK rt
  _escrever "$d/a b.json" AK rt
  _escrever "$d/semext" AK rt
  mkdir "$d/subdir.json"
  printf x >"$d/.credencial.1.XXXX"
  dbx_config_perfis_listar
  assert_igual 'ok' "${DBX_CONFIG_PERFIS_NOME[*]}" 'so o valido'
  assert_igual 5 "${#DBX_CONFIG_PERFIS_IGNORADAS[@]}" 'cinco anomalias, temporarios ocultos em silencio'
}

teste_pfl_listar_nao_cria_diretorios() {
  local area
  area=$(_area)
  _xdg "$area"
  dbx_config_perfis_listar
  [[ ! -e $area/config ]] || _harness_falhar 'listar criou diretorio'
  assert_igual 0 "${#DBX_CONFIG_PERFIS_NOME[@]}" 'nenhum'
}

harness_executar "$@"
