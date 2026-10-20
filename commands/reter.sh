#!/usr/bin/env bash
# reter — retencao e rotacao de backup (RF-93 a RF-99, F-10). Alias: `retain`.
#
#   dbx reter <pasta-remota> --padrao GLOB (--manter N | --dias D) [--confirmar]
#
# DECISOES DO SOLICITANTE (memoria 2026-10-20-2010-retencao):
#
#   - comando proprio, nao opcao do `upload`;
#   - os mais novos sao os de `server_modified` mais recente; em empate, o nome;
#   - a exclusao vai para a LIXEIRA por `delete_v2` (recuperavel); nunca
#     `permanently_delete`;
#   - sem `--confirmar`, so o plano (o que fica e o que sai), codigo 0;
#   - sempre fica pelo menos 1 artefato;
#   - a guarda destrutiva nao depende de estado local.
#
# FRONTEIRA DE SEGURANCA (RF-97, RSK-62..66). A unica fonte da autorizacao e a
# listagem DESTA execucao: o plano so existe depois da ultima pagina; listagem
# incoerente, `server_modified` invalido, cursor repetido, teto de paginas ou
# relogio divergente derrubam tudo antes de qualquer exclusao (DIV-143, 145,
# 147, 134); cada `delete_v2` passa de novo pela guarda de lib/retencao e leva o
# `parent_rev` listado (DIV-138), o que impede apagar um backup novo de mesmo
# nome e impede apagar pasta. Nada vem de lib/state, cache ou plano anterior.
# Sem trava (DIV-140): o artefato que surge depois da listagem nao esta no plano.
#
# Ordem: uso -> confinamento -> rede (RF-93(k)). Codigos so da taxonomia.
#
# Linhas marcadas `MUTACAO:<nome>` sao as que os casos de mutacao de
# `reter_test` removem ou trocam: cada uma e uma barreira de P0.

dbx_cmd_reter_requisitos() { printf 'credencial'; }

readonly DBX_RETER_URL_LISTAR='https://api.dropboxapi.com/2/files/list_folder'
readonly DBX_RETER_URL_CONTINUAR='https://api.dropboxapi.com/2/files/list_folder/continue'
readonly DBX_RETER_URL_APAGAR='https://api.dropboxapi.com/2/files/delete_v2'
# DIV-143: teto de paginas (licao QA-B5-14) e `limit` explicito, no maximo do
# ajudante de colecao (RNF-23; o `files.stone` aceita 1 a 2000).
readonly DBX_RETER_PAGINAS_MAXIMAS=1000
readonly DBX_RETER_LIMITE=100
# DIV-134: divergencia maxima entre o relogio local e o `Date` da listagem.
readonly DBX_RETER_RELOGIO_TOLERANCIA_S=300

# Candidatos da listagem desta execucao, em vetores paralelos (um indice por
# candidato), e o resultado de cada um. Lidos tambem pelo resumo de sinal.
declare -ga _DBX_RETER_TAG=() _DBX_RETER_NOME=() _DBX_RETER_PL=() _DBX_RETER_PD=()
declare -ga _DBX_RETER_SM=() _DBX_RETER_REV=() _DBX_RETER_TAMANHO=() _DBX_RETER_CHAVE=()
declare -ga _DBX_RETER_RESULTADO=() _DBX_RETER_MOTIVO=() _DBX_RETER_ID=()
_DBX_RETER_LISTADOS=0
_DBX_RETER_FORA=0
_DBX_RETER_IGNORADOS=0
_DBX_RETER_DATA=''
_DBX_RETER_FALHA=''
# DIV-158, DIV-161: chaves de RF-54 dos `path_lower` ja vistos nesta listagem.
declare -gA _DBX_RETER_VISTOS=()
# DIV-167: `id` e `rev` ja vistos entre os arquivos desta listagem.
declare -gA _DBX_RETER_IDS=() _DBX_RETER_REVS=()
_DBX_RETER_CLASSE='erro_remoto'
_DBX_RETER_EM_CURSO=''

dbx_cmd_reter_executar() {
  # shellcheck source=lib/retencao.sh
  . "$DBX_CLI_RAIZ/lib/retencao.sh"
  local pasta='' posicionais=0 padrao='' padroes=0 opcao_padrao='--padrao'
  local manter='' manteres=0 opcao_manter='--manter' dias='' diases=0 opcao_dias='--dias' confirmar='nao'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --padrao | --pattern)
        opcao_padrao=$1
        shift
        [[ $# -gt 0 ]] || {
          dbx_cmd_falhar uso_invalido "$opcao_padrao exige um valor"
          return $?
        }
        padrao=$1 padroes=$((padroes + 1))
        ;;
      --manter | --keep)
        opcao_manter=$1
        shift
        [[ $# -gt 0 ]] || {
          dbx_cmd_falhar uso_invalido "$opcao_manter exige um valor"
          return $?
        }
        manter=$1 manteres=$((manteres + 1))
        ;;
      --dias | --days)
        opcao_dias=$1
        shift
        [[ $# -gt 0 ]] || {
          dbx_cmd_falhar uso_invalido "$opcao_dias exige um valor"
          return $?
        }
        dias=$1 diases=$((diases + 1))
        ;;
      --confirmar | --yes | -y) confirmar='sim' ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: ${1%%=*}"
        return $?
        ;;
      *)
        posicionais=$((posicionais + 1))
        pasta=$1
        ;;
    esac
    shift
  done

  # RF-93(a)..(h): toda recusa de uso antes do confinamento e da rede.
  [[ $posicionais -eq 1 ]] || {
    dbx_cmd_falhar uso_invalido "informe exatamente uma pasta remota ($posicionais argumento(s) posicional(is))"
    return $?
  }
  [[ $pasta == /* ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto absoluto da pasta (comeca com /)'
    return $?
  }
  if [[ $padroes -eq 0 ]]; then
    dbx_cmd_falhar uso_invalido 'informe --padrao GLOB: o padrao do nome dos artefatos e obrigatorio'
    return $?
  fi
  # DIV-131: numa operacao destrutiva, dois padroes indicam engano.
  if [[ $padroes -gt 1 ]]; then
    dbx_cmd_falhar uso_invalido '--padrao repetido: informe um unico padrao (nenhum dos dois foi escolhido)'
    return $?
  fi
  if [[ $manteres -gt 1 || $diases -gt 1 ]]; then
    dbx_cmd_falhar uso_invalido '--manter ou --dias repetido: informe um unico valor'
    return $?
  fi
  # DIV-133: exclusivas.
  if [[ $((manteres + diases)) -ne 1 ]]; then
    dbx_cmd_falhar uso_invalido 'informe --manter N ou --dias D (um dos dois)'
    return $?
  fi
  local politica valor
  if [[ $manteres -eq 1 ]]; then
    politica='manter'
    dbx_retencao_validar_manter "$opcao_manter" "$manter" || {
      dbx_cmd_falhar uso_invalido "$DBX_RETENCAO_MOTIVO"
      return $?
    }
  else
    politica='dias'
    dbx_retencao_validar_dias "$opcao_dias" "$dias" || {
      dbx_cmd_falhar uso_invalido "$DBX_RETENCAO_MOTIVO"
      return $?
    }
  fi
  valor=$DBX_RETENCAO_VALOR
  dbx_filtro_nome_preparar "$opcao_padrao" "$padrao" || {
    dbx_cmd_falhar uso_invalido "$DBX_FILTRO_MOTIVO"
    return $?
  }
  local amplo=$DBX_FILTRO_AMPLO

  # RF-96: sem --confirmar, plano; --dry-run vence (DIV-135).
  [[ $confirmar == 'sim' ]] || confirmar='nao' # MUTACAO:confirmar
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && confirmar='nao' # MUTACAO:simulacao
  local modo='plano'
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && modo='simulado'
  [[ $confirmar == 'sim' ]] && modo='confirmado'

  # RF-97(a): confinamento do argumento, antes de qualquer chamada.
  local alvo
  _dbx_cmd_caminho_remoto "$pasta" || return $?
  alvo=$DBX_CMD_LIDO

  dbx_filtro_citar "$padrao"
  local citado=$DBX_FILTRO_CITADO exibida=${alvo:-/}
  dbx_cmd_caminho_exibivel "$exibida"
  exibida=$DBX_CMD_EXIBIDO
  # DIV-132: padrao sem caractere literal e aceito, com aviso, nos tres modos.
  [[ $amplo == 'sim' ]] && _dbx_cmd_reter_avisar "o padrao $citado casa todo arquivo da pasta"

  local agora estado
  _dbx_cmd_reter_listar "$alvo" || return $?
  printf -v agora '%(%s)T' -1
  [[ $politica == 'manter' ]] || { _dbx_cmd_reter_relogio "$agora" || return $?; } # MUTACAO:relogio

  if ! dbx_retencao_planejar "$politica" "$valor" "$agora" _DBX_RETER_SM _DBX_RETER_CHAVE _DBX_RETER_PL; then
    dbx_cmd_falhar erro_remoto "plano recusado: $DBX_RETENCAO_MOTIVO; nada foi apagado"
    return $?
  fi
  local i
  for i in ${DBX_RETENCAO_ORDEM[@]+"${DBX_RETENCAO_ORDEM[@]}"}; do
    _DBX_RETER_RESULTADO[i]=${DBX_RETENCAO_ACAO[i]}
  done

  # RF-95(e)(f), DIV-146: avisos em stderr, antes do resultado.
  if [[ ${#_DBX_RETER_NOME[@]} -eq 0 ]]; then
    _dbx_cmd_reter_avisar "o padrao $citado nao casou nenhum arquivo em $exibida"
  elif [[ $DBX_RETENCAO_MINIMO == 'sim' && $politica == 'dias' ]]; then
    dbx_cmd_caminho_exibivel "${_DBX_RETER_NOME[${DBX_RETENCAO_ORDEM[0]}]}"
    _dbx_cmd_reter_avisar "nenhum artefato dentro de $valor dias; o mais novo foi mantido: $DBX_CMD_EXIBIDO"
  fi

  estado=0
  if [[ $modo == 'confirmado' ]]; then
    _dbx_cmd_reter_aplicar "$alvo"
    estado=$?
  fi
  _dbx_cmd_reter_emitir "$alvo" "$citado" "$politica" "$valor" "$modo"
  case $modo in
    plano) _dbx_cmd_reter_avisar 'nada foi apagado; para aplicar, repita com --confirmar' ;;
    simulado) _dbx_cmd_reter_avisar 'simulacao (--dry-run): nada foi apagado' ;;
  esac
  [[ $estado -eq 0 ]] || {
    dbx_cmd_falhar "$_DBX_RETER_CLASSE" "$_DBX_RETER_FALHA"
    return $?
  }
  return 0
}

_dbx_cmd_reter_avisar() {
  dbx_cmd_iniciar_saida
  dbx_output_diagnostico aviso "$1"
  dbx_output_render_diagnostico >&2
}

# ---------------------------------------------------------------------------
# Listagem (RF-94): um nivel, completa e coerente antes de qualquer exclusao
# ---------------------------------------------------------------------------

# _dbx_cmd_reter_listar <pasta_api> — `list_folder` e `continue` ate o fim,
# preenchendo os vetores de candidatos. Falha: diagnostico emitido e o codigo.
_dbx_cmd_reter_listar() {
  local alvo=$1 corpo paginas=0 estado cursor mais tipo
  local -A vistos=()
  _DBX_RETER_TAG=() _DBX_RETER_NOME=() _DBX_RETER_PL=() _DBX_RETER_PD=()
  _DBX_RETER_SM=() _DBX_RETER_REV=() _DBX_RETER_TAMANHO=() _DBX_RETER_CHAVE=()
  _DBX_RETER_RESULTADO=() _DBX_RETER_MOTIVO=()
  _DBX_RETER_LISTADOS=0 _DBX_RETER_FORA=0 _DBX_RETER_IGNORADOS=0 _DBX_RETER_DATA=''
  _DBX_RETER_VISTOS=() _DBX_RETER_IDS=() _DBX_RETER_REVS=() _DBX_RETER_ID=()
  dbx_json_escapar_cadeia "$alvo"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"recursive\":false,\"include_deleted\":false}"
  # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
  DBX_JSON_ESCAPADO=''
  while :; do
    if ((paginas >= DBX_RETER_PAGINAS_MAXIMAS)); then
      dbx_cmd_falhar erro_remoto "listagem nao terminou em $DBX_RETER_PAGINAS_MAXIMAS paginas; nada foi apagado"
      return $?
    fi
    paginas=$((paginas + 1))
    if ((paginas == 1)); then
      dbx_auth_colecao POST "$DBX_RETER_URL_LISTAR" "$corpo" "$DBX_RETER_LIMITE"
      estado=$?
    else
      # ListFolderContinueArg so tem `cursor` (files.stone): sem `limit`.
      dbx_auth_requisitar POST "$DBX_RETER_URL_CONTINUAR" "$corpo" sim
      estado=$?
    fi
    if ((estado != 0)); then
      _dbx_cmd_reter_recusa_da_listagem "$alvo" "$estado"
      return $?
    fi
    # DIV-134, DIV-160: o `Date` da ULTIMA pagina; o "agora" e lido logo depois
    # dela, para uma listagem longa nao produzir divergencia falsa.
    _DBX_RETER_DATA=${DBX_HTTP_DATA:-} # MUTACAO:data
    dbx_json_contexto reter_pagina || {
      dbx_cmd_falhar erro_remoto 'contexto de analise indisponivel'
      return $?
    }
    _DBX_RETER_FALHA=''
    if dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null; then
      DBX_HTTP_CORPO=''
      _dbx_cmd_reter_pagina "$alvo"
      estado=$?
    else
      DBX_HTTP_CORPO=''
      _DBX_RETER_FALHA="pagina da listagem nao interpretavel (${DBX_JSON_MOTIVO:-sem detalhe})"
      estado=1
    fi
    mais='' cursor='' tipo=''
    if ((estado == 0)); then
      tipo=$(dbx_json_tipo has_more 2>/dev/null) || tipo=''
      dbx_json_valor has_more >/dev/null 2>&1 && mais=$DBX_JSON_RESULTADO
      [[ $tipo == 'booleano' ]] || { _DBX_RETER_FALHA='pagina da listagem sem has_more'; estado=1; }
      if [[ $mais == 'true' ]]; then
        tipo=$(dbx_json_tipo cursor 2>/dev/null) || tipo=''
        dbx_json_valor cursor >/dev/null 2>&1 && cursor=$DBX_JSON_RESULTADO
        [[ $tipo == 'cadeia' && -n $cursor ]] || { _DBX_RETER_FALHA='paginacao nao avanca: has_more sem cursor'; estado=1; }
      fi
    fi
    dbx_json_descartar reter_pagina
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
    DBX_JSON_RESULTADO=''
    ((estado == 0)) || {
      dbx_cmd_falhar erro_remoto "listagem incoerente: $_DBX_RETER_FALHA; nada foi apagado"
      return $?
    }
    [[ $mais == 'true' ]] || break
    # DIV-143: cursor repetido (inclusive o da pagina anterior) nao avanca.
    [[ -z ${vistos[$cursor]:-} ]] || { dbx_cmd_falhar erro_remoto 'paginacao nao avanca: o servico repetiu o cursor; nada foi apagado'; return $?; } # MUTACAO:cursor
    vistos[$cursor]=1
    dbx_json_escapar_cadeia "$cursor"
    corpo="{\"cursor\":\"$DBX_JSON_ESCAPADO\"}"
    # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
    DBX_JSON_ESCAPADO=''
  done
  return 0
}

# _dbx_cmd_reter_recusa_da_listagem <pasta_api> <status> — RF-94(a)(e).
#
# O status devolvido decide a classe quando os canais de lib/http descrevem
# outra chamada: a renovacao do token que falha (RF-98(e), `5`) deixa neles a
# resposta do endpoint de token, que nao e a da listagem.
_dbx_cmd_reter_recusa_da_listagem() {
  local classe=${DBX_HTTP_CLASSE:-erro_remoto} resumo=${DBX_HTTP_RESUMO_DE_ERRO:-} estado=${2:-10}
  dbx_cmd_caminho_exibivel "${1:-/}"
  if [[ $classe == 'sucesso' ]]; then
    dbx_cmd_falhar erro_remoto 'resposta da listagem nao interpretavel; nada foi apagado'
    return $?
  fi
  if ! dbx_errors_classe_valida "$classe" || [[ ${DBX_ERRORS_CODIGO[$classe]} != "$estado" ]]; then
    classe=$(dbx_errors_classe_do_codigo "$estado")
    dbx_cmd_falhar "$classe" "listagem nao feita: ${DBX_AUTH_MOTIVO:-codigo $estado}; nada foi apagado"
    return $?
  fi
  dbx_errors_tag_reconhecida "$resumo"
  case $DBX_ERRORS_TAG in
    not_found)
      dbx_cmd_falhar nao_encontrado "pasta remota inexistente: $DBX_CMD_EXIBIDO; nada foi apagado"
      return $?
      ;;
    not_folder)
      dbx_cmd_falhar uso_invalido "reter opera sobre uma pasta de artefatos: $DBX_CMD_EXIBIDO nao e pasta"
      return $?
      ;;
  esac
  if [[ $classe == 'nao_concluida' ]]; then
    dbx_cmd_falhar nao_concluida 'a pasta mudou durante a listagem; repita (nada foi apagado)'
    return $?
  fi
  dbx_errors_classe_valida "$classe" || classe='erro_remoto'
  dbx_cmd_falhar "$classe" "listagem recusada: ${resumo:-codigo ${DBX_HTTP_CODIGO:-0}}; nada foi apagado"
}

# Campos da entrada corrente (valor e tipo), lidos por _dbx_cmd_reter_ler.
_e_tag='' _e_nome='' _e_pl='' _e_pd='' _e_sm='' _e_rev='' _e_tamanho=''
_e_t_tag='' _e_t_nome='' _e_t_pl='' _e_t_pd='' _e_t_sm='' _e_t_rev=''
_e_id='' _e_t_id=''

# _dbx_cmd_reter_ler <indice> <campo> <var_valor> <var_tipo>
_dbx_cmd_reter_ler() {
  local -n _rl_v=$3 _rl_t=$4
  _rl_v='' _rl_t=''
  dbx_json_valor entries "$1" "$2" >/dev/null 2>&1 || return 0
  _rl_v=$DBX_JSON_RESULTADO
  _rl_t=$(dbx_json_tipo entries "$1" "$2" 2>/dev/null) || _rl_t=''
}

# _dbx_cmd_reter_pagina <pasta_api> — percorre as entradas da pagina analisada.
# Status 1 com _DBX_RETER_FALHA quando a pagina e suspeita (DIV-147).
_dbx_cmd_reter_pagina() {
  local alvo=$1 quantidade indice tipo
  [[ $DBX_JSON_DUPLICADAS -eq 0 ]] || {
    _DBX_RETER_FALHA="a pagina da listagem tem campo repetido ($DBX_JSON_DUPLICADAS): ambigua"
    return 1
  }
  tipo=$(dbx_json_tipo entries 2>/dev/null) || tipo=''
  [[ $tipo == 'arranjo' ]] || {
    _DBX_RETER_FALHA='pagina da listagem sem entries'
    return 1
  }
  quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
  for ((indice = 0; indice < quantidade; indice++)); do
    _dbx_cmd_reter_ler "$indice" '.tag' _e_tag _e_t_tag
    _dbx_cmd_reter_ler "$indice" name _e_nome _e_t_nome
    _dbx_cmd_reter_ler "$indice" path_lower _e_pl _e_t_pl
    _DBX_RETER_LISTADOS=$((_DBX_RETER_LISTADOS + 1))
    _dbx_cmd_reter_utf8 || return 1 # MUTACAO:utf8
    _dbx_cmd_reter_coerente "$indice" "$alvo" || return 1 # MUTACAO:coerencia
    _dbx_cmd_reter_normalizado || return 1 # MUTACAO:normalizado
    _dbx_cmd_reter_minusculo || return 1 # MUTACAO:minusculo
    _dbx_cmd_reter_composto || return 1 # MUTACAO:combinante
    _dbx_cmd_reter_inedito || return 1 # MUTACAO:duplicado
    _dbx_cmd_reter_identidade "$indice" || return 1 # MUTACAO:identidade
    [[ $_e_tag == 'file' ]] || { _DBX_RETER_IGNORADOS=$((_DBX_RETER_IGNORADOS + 1)); continue; } # MUTACAO:tag
    dbx_filtro_nome_casa "$_e_nome" || { _DBX_RETER_FORA=$((_DBX_RETER_FORA + 1)); continue; } # MUTACAO:padrao
    _dbx_cmd_reter_ler "$indice" path_display _e_pd _e_t_pd
    _dbx_cmd_reter_ler "$indice" server_modified _e_sm _e_t_sm
    _dbx_cmd_reter_ler "$indice" rev _e_rev _e_t_rev
    _e_tamanho=''
    dbx_json_valor entries "$indice" size >/dev/null 2>&1 && [[ $DBX_JSON_RESULTADO =~ ^[0-9]{1,18}$ ]] &&
      _e_tamanho=$DBX_JSON_RESULTADO
    _dbx_cmd_reter_candidato_completo || return 1 # MUTACAO:coerencia
    { [[ $_e_t_sm == 'cadeia' ]] && dbx_retencao_carimbo_valido "$_e_sm"; } || { _dbx_cmd_reter_incoerente 'server_modified invalido (ordem indefinida)'; return 1; } # MUTACAO:carimbo
    _DBX_RETER_TAG+=("$_e_tag") _DBX_RETER_NOME+=("$_e_nome") _DBX_RETER_PL+=("$_e_pl")
    _DBX_RETER_PD+=("$_e_pd") _DBX_RETER_SM+=("$_e_sm") _DBX_RETER_REV+=("$_e_rev")
    _DBX_RETER_TAMANHO+=("$_e_tamanho") _DBX_RETER_ID+=("$_e_id")
    dbx_filtro_chave "$_e_nome"
    _DBX_RETER_CHAVE+=("$DBX_FILTRO_CHAVE")
  done
  return 0
}

# _dbx_cmd_reter_incoerente <motivo> — _DBX_RETER_FALHA com o item citado.
_dbx_cmd_reter_incoerente() {
  dbx_cmd_caminho_exibivel "${_e_pl:-${_e_nome:-sem nome}}"
  _DBX_RETER_FALHA="$1 em $DBX_CMD_EXIBIDO"
}

# _dbx_cmd_reter_coerente <indice> <pasta_api> — RF-94(g) para TODA entrada:
# `.tag` e `name` textuais, `name` nao vazio e sem `/`, `path_lower` textual e
# filho direto da pasta (DIV-137: fora do ASCII, igualdade exata).
_dbx_cmd_reter_coerente() {
  [[ $_e_t_tag == 'cadeia' && -n $_e_tag ]] || { _dbx_cmd_reter_incoerente 'entrada sem .tag'; return 1; }
  [[ $_e_t_nome == 'cadeia' && -n $_e_nome && $_e_nome != */* ]] ||
    { _dbx_cmd_reter_incoerente 'name ausente, vazio ou com /'; return 1; }
  [[ $_e_t_pl == 'cadeia' ]] || { _dbx_cmd_reter_incoerente 'path_lower ausente'; return 1; }
  dbx_retencao_pai_igual "$_e_pl" "$2" || { _dbx_cmd_reter_incoerente 'path_lower fora da pasta pedida'; return 1; }
  return 0
}

# _dbx_cmd_reter_normalizado — DIV-159: `name` diferente de `.` e `..` e
# `path_lower` ja normalizado (sem `//`, sem segmento `.`/`..`, sem barra
# final), para TODA entrada.
_dbx_cmd_reter_normalizado() {
  if [[ $_e_nome == '.' || $_e_nome == '..' ]] || ! dbx_retencao_caminho_normalizado "$_e_pl"; then
    _dbx_cmd_reter_incoerente 'name . ou .., ou path_lower nao normalizado'
    return 1
  fi
  return 0
}

# _dbx_cmd_reter_composto — DIV-164: `path_lower` sem marca combinante (o
# servidor compoe os decompostos), em toda entrada.
_dbx_cmd_reter_composto() {
  dbx_retencao_sem_combinante "$_e_pl" && return 0
  _dbx_cmd_reter_incoerente 'path_lower com marca combinante (decomposto, NFD)'
  return 1
}

# _dbx_cmd_reter_minusculo — DIV-161: o `path_lower` ja e a sua propria chave
# sem caixa de RF-54 (minuscula Unicode). Fora disso, ou sem como calcular a
# chave fora do ASCII, a listagem e incoerente.
_dbx_cmd_reter_minusculo() {
  if ! dbx_retencao_chave "$_e_pl"; then
    _dbx_cmd_reter_incoerente 'caminho fora do ASCII sem a chave sem caixa (localidade C.UTF-8 indisponivel)'
    return 1
  fi
  [[ $DBX_RETENCAO_CHAVE == "$_e_pl" ]] && return 0
  _dbx_cmd_reter_incoerente 'path_lower fora da minuscula'
  return 1
}

# _dbx_cmd_reter_utf8 — DIV-168: `name` e `path_lower` sao UTF-8 valido, em
# toda entrada (por bytes, sem depender da localidade).
_dbx_cmd_reter_utf8() {
  dbx_retencao_utf8_valido "$_e_nome" && dbx_retencao_utf8_valido "$_e_pl" && return 0
  _dbx_cmd_reter_incoerente 'name ou path_lower com UTF-8 invalido'
  return 1
}

# _dbx_cmd_reter_identidade <indice> — DIV-167: todo ARQUIVO da listagem traz
# `id` (`Id = String(min_length=1)`, obrigatorio em FileMetadata no
# files.stone) e `rev` no formato `Rev`, e nenhum dos dois se repete entre os
# arquivos, em pagina nenhuma. Barreira estrutural contra a mesma entrada em
# outra grafia (caixa, NFC/NFD, composicao fora dos blocos de DIV-164).
_dbx_cmd_reter_identidade() {
  _e_id='' _e_rev=''
  [[ $_e_tag == 'file' ]] || return 0
  _dbx_cmd_reter_ler "$1" id _e_id _e_t_id
  _dbx_cmd_reter_ler "$1" rev _e_rev _e_t_rev
  [[ $_e_t_id == 'cadeia' && -n $_e_id ]] || { _dbx_cmd_reter_incoerente 'arquivo sem id'; return 1; }
  local LC_ALL=C
  [[ $_e_t_rev == 'cadeia' && $_e_rev =~ ^[0-9a-f]{9,}$ ]] || { _dbx_cmd_reter_incoerente 'arquivo sem rev (ou malformado)'; return 1; }
  if [[ -n ${_DBX_RETER_IDS[$_e_id]+x} ]]; then
    _dbx_cmd_reter_incoerente 'id repetido entre arquivos da listagem'
    return 1
  fi
  if [[ -n ${_DBX_RETER_REVS[$_e_rev]+x} ]]; then
    _dbx_cmd_reter_incoerente 'rev repetido entre arquivos da listagem'
    return 1
  fi
  _DBX_RETER_IDS[$_e_id]=1
  _DBX_RETER_REVS[$_e_rev]=1
  return 0
}

# _dbx_cmd_reter_inedito — DIV-158, DIV-161: a chave de RF-54 do `path_lower`
# nao apareceu antes nesta listagem, em pagina nenhuma, de `.tag` nenhuma.
_dbx_cmd_reter_inedito() {
  local chave
  dbx_retencao_chave "$_e_pl" || {
    _dbx_cmd_reter_incoerente 'caminho fora do ASCII sem a chave sem caixa (localidade C.UTF-8 indisponivel)'
    return 1
  }
  chave=$DBX_RETENCAO_CHAVE
  if [[ -n ${_DBX_RETER_VISTOS[$chave]+x} ]]; then
    _dbx_cmd_reter_incoerente 'path_lower repetido na listagem'
    return 1
  fi
  _DBX_RETER_VISTOS[$chave]=1
  return 0
}

# _dbx_cmd_reter_candidato_completo — RF-94(g) para o CANDIDATO: `name`
# coerente com `path_lower`, `path_display` textual e `rev` no formato `Rev`
# do `files.stone` (`[0-9a-f]`, 9 ou mais).
_dbx_cmd_reter_candidato_completo() {
  dbx_retencao_nome_coerente "$_e_nome" "$_e_pl" ||
    { _dbx_cmd_reter_incoerente 'name diferente do ultimo componente de path_lower'; return 1; }
  [[ $_e_t_pd == 'cadeia' && -n $_e_pd ]] || { _dbx_cmd_reter_incoerente 'path_display ausente'; return 1; }
  local LC_ALL=C
  [[ $_e_t_rev == 'cadeia' && $_e_rev =~ ^[0-9a-f]{9,}$ ]] || { _dbx_cmd_reter_incoerente 'rev ausente ou malformado'; return 1; }
  return 0
}

# _dbx_cmd_reter_relogio <agora> — DIV-134: com `--dias`, o relogio local tem
# de concordar com o `Date` da listagem desta execucao.
_dbx_cmd_reter_relogio() {
  local agora=$1 diferenca
  dbx_retencao_epoca_http "$_DBX_RETER_DATA" || {
    dbx_cmd_falhar erro_remoto \
      'cabecalho Date ausente ou malformado na resposta da listagem: o relogio local nao pode ser conferido para --dias; nada foi apagado'
    return $?
  }
  diferenca=$((agora - DBX_RETENCAO_EPOCA))
  ((diferenca < 0)) && diferenca=$((-diferenca))
  ((diferenca <= DBX_RETER_RELOGIO_TOLERANCIA_S)) && return 0
  dbx_cmd_falhar configuracao \
    "relogio local diverge do servidor em $diferenca s (limite $DBX_RETER_RELOGIO_TOLERANCIA_S s): acerte o relogio desta maquina antes de usar --dias; nada foi apagado"
}

# ---------------------------------------------------------------------------
# Execucao confirmada (RF-97(b)(c)(e), RF-98)
# ---------------------------------------------------------------------------

# _dbx_cmd_reter_aplicar <pasta_api> — um `delete_v2` por item que sai, do
# mais velho ao mais novo (DIV-142). Status: 0; 14 com falha de item ou parada
# (5, 8, 9 esgotados); 10 com guarda recusada ou resposta 2xx incoerente, que
# param antes do proximo. Mensagem em _DBX_RETER_FALHA.
_dbx_cmd_reter_aplicar() {
  local alvo=$1 raiz=${DBX_CONFIG_RAIZ_REMOTA:-/} k i primeiro=${DBX_RETENCAO_ORDEM[0]:-} parada='' guarda
  local corpo caminho rev estado falhas=0 nao_tentados=0
  local -a sai=() ficam=() ficam_revs=() ficam_ids=()
  for ((k = ${#DBX_RETENCAO_ORDEM[@]} - 1; k >= 0; k--)); do
    i=${DBX_RETENCAO_ORDEM[k]}
    if [[ ${DBX_RETENCAO_ACAO[i]} == 'sai' ]]; then
      sai+=("$i")
    else
      ficam+=("${_DBX_RETER_PL[i]}") ficam_revs+=("${_DBX_RETER_REV[i]}") ficam_ids+=("${_DBX_RETER_ID[i]}")
    fi
  done
  [[ ${#sai[@]} -gt 0 ]] || return 0
  # RF-98(h): sinal entre dois `delete_v2` encerra com 14 e este resumo.
  dbx_tmp_acao_registrar _dbx_cmd_reter_ao_sinal
  local acao_id=$DBX_TMP_ID
  for i in "${sai[@]}"; do
    if [[ -n $parada ]]; then
      _DBX_RETER_RESULTADO[i]='nao_tentado'
      nao_tentados=$((nao_tentados + 1))
      continue
    fi
    guarda='ok'
    local e_primeiro='nao'
    [[ $i == "$primeiro" ]] && e_primeiro='sim'
    dbx_retencao_guarda "${_DBX_RETER_TAG[i]}" "${_DBX_RETER_PL[i]}" "${_DBX_RETER_NOME[i]}" "$alvo" "$raiz" "${DBX_RETENCAO_ACAO[i]}" "$e_primeiro" ficam "${_DBX_RETER_REV[i]}" "${_DBX_RETER_ID[i]}" ficam_revs ficam_ids || guarda=$DBX_RETENCAO_MOTIVO # MUTACAO:guarda
    if [[ $guarda != 'ok' ]]; then
      dbx_cmd_caminho_exibivel "${_DBX_RETER_PL[i]}"
      _DBX_RETER_FALHA="guarda recusou a exclusao de $DBX_CMD_EXIBIDO: $guarda; a execucao parou"
      _DBX_RETER_RESULTADO[i]='nao_tentado'
      nao_tentados=$((nao_tentados + 1))
      parada='erro_remoto'
      continue
    fi
    caminho=${_DBX_RETER_PL[i]}
    dbx_json_escapar_cadeia "$caminho"
    caminho=$DBX_JSON_ESCAPADO
    dbx_json_escapar_cadeia "${_DBX_RETER_REV[i]}"
    rev=$DBX_JSON_ESCAPADO
    # shellcheck disable=SC2034  # canal publico de lib/json, limpo aqui
    DBX_JSON_ESCAPADO=''
    # DIV-138: `parent_rev` sempre; com ele, repetir e idempotente (DIV-141).
    corpo="{\"path\":\"$caminho\",\"parent_rev\":\"$rev\"}"
    # Token valido antes da escrita: a falha da renovacao (5) para a execucao
    # pela classe certa, sem passar pelos canais de outra chamada.
    if ! dbx_auth_preparar; then
      _DBX_RETER_RESULTADO[i]='nao_tentado' _DBX_RETER_MOTIVO[i]=${DBX_AUTH_CLASSE:-autenticacao}
      nao_tentados=$((nao_tentados + 1)) parada=${DBX_AUTH_CLASSE:-autenticacao}
      _dbx_cmd_reter_avisar "renovacao do token recusada: ${DBX_AUTH_MOTIVO:-sem detalhe}"
      continue
    fi
    _DBX_RETER_EM_CURSO=$i
    _dbx_cmd_escrita_remota "$DBX_RETER_URL_APAGAR" "$corpo" silencioso sim
    estado=$?
    corpo=''
    if [[ ${DBX_CMD_SIMULADO:-nao} == 'sim' ]]; then
      _DBX_RETER_EM_CURSO=''
      continue
    fi
    if ((estado == 0)); then
      if _dbx_cmd_reter_resposta_coerente "${_DBX_RETER_PL[i]}"; then
        _DBX_RETER_RESULTADO[i]='apagado'
      else
        _DBX_RETER_RESULTADO[i]='falhou' _DBX_RETER_MOTIVO[i]='erro_remoto'
        falhas=$((falhas + 1)) parada='erro_remoto'
      fi
    elif [[ ${DBX_HTTP_CLASSE:-} == 'sucesso' ]]; then
      # QA-B5-12: 2xx malformado (lib/cmd ja o diagnosticou).
      dbx_cmd_caminho_exibivel "${_DBX_RETER_PL[i]}"
      _DBX_RETER_FALHA="resposta do delete_v2 nao interpretavel para $DBX_CMD_EXIBIDO; a execucao parou"
      _DBX_RETER_RESULTADO[i]='falhou' _DBX_RETER_MOTIVO[i]='erro_remoto'
      falhas=$((falhas + 1)) parada='erro_remoto'
    elif dbx_errors_tag_reconhecida "${DBX_HTTP_RESUMO_DE_ERRO:-}" && [[ $DBX_ERRORS_TAG == 'not_found' ]]; then
      _DBX_RETER_RESULTADO[i]='ja_ausente'
    else
      local classe=${DBX_CMD_FALHA_CLASSE:-erro_remoto}
      _DBX_RETER_RESULTADO[i]='falhou' _DBX_RETER_MOTIVO[i]=$classe
      falhas=$((falhas + 1))
      dbx_cmd_caminho_exibivel "${_DBX_RETER_PL[i]}"
      _dbx_cmd_reter_avisar "nao apagado: $DBX_CMD_EXIBIDO: $classe (${DBX_CMD_FALHA_MOTIVO:-sem detalhe})"
      case $classe in
        autenticacao | limite_taxa | rede) parada=$classe ;;
      esac
    fi
    _DBX_RETER_EM_CURSO=''
  done
  dbx_tmp_acao_cancelar "$acao_id"
  _DBX_RETER_CLASSE='erro_remoto'
  if [[ $parada == 'erro_remoto' ]]; then
    return "$(dbx_errors_codigo_saida erro_remoto)"
  fi
  if ((falhas > 0 || nao_tentados > 0)); then
    _DBX_RETER_FALHA="retencao nao concluida: $falhas falha(s), $nao_tentados nao tentado(s)"
    [[ -n $parada ]] && _DBX_RETER_FALHA+="; parou por $parada"
    _DBX_RETER_CLASSE='nao_concluida'
    return "$(dbx_errors_codigo_saida nao_concluida)"
  fi
  return 0
}

# _dbx_cmd_reter_resposta_coerente <path_lower> — RF-97(e): a resposta 2xx do
# `delete_v2` traz `metadata` de arquivo com o `path_lower` do alvo, sem chave
# repetida. Le o documento que lib/cmd analisou e o descarta.
_dbx_cmd_reter_resposta_coerente() {
  local alvo=$1 tag='' minusculo='' tipo duplicadas=$DBX_JSON_DUPLICADAS ok='sim'
  tipo=$(dbx_json_tipo metadata 2>/dev/null) || tipo=''
  dbx_json_valor metadata '.tag' >/dev/null 2>&1 && tag=$DBX_JSON_RESULTADO
  dbx_json_valor metadata path_lower >/dev/null 2>&1 && minusculo=$DBX_JSON_RESULTADO
  _dbx_cmd_encerrar_consulta
  [[ $duplicadas -eq 0 && $tipo == 'objeto' && $tag == 'file' && $minusculo == "$alvo" ]] || ok='nao'
  [[ $ok == 'sim' ]] && return 0
  dbx_cmd_caminho_exibivel "$alvo"
  _DBX_RETER_FALHA="resposta do delete_v2 incoerente para $DBX_CMD_EXIBIDO (metadata ausente, de outro item ou nao arquivo); a execucao parou"
  return 1
}

# _dbx_cmd_reter_ao_sinal — acao de lib/tmp: resumo parcial em stderr quando um
# sinal encerra a execucao entre exclusoes (RF-98(h)).
_dbx_cmd_reter_ao_sinal() {
  local i apagados=0 resto=''
  for i in "${!_DBX_RETER_RESULTADO[@]}"; do
    [[ ${_DBX_RETER_RESULTADO[i]} == 'apagado' ]] && apagados=$((apagados + 1))
    if [[ ${_DBX_RETER_RESULTADO[i]} == 'sai' && $i != "$_DBX_RETER_EM_CURSO" ]]; then
      dbx_cmd_caminho_exibivel "${_DBX_RETER_PL[i]}"
      resto+=" $DBX_CMD_EXIBIDO"
    fi
  done
  local texto="interrompido: $apagados apagado(s) para a lixeira; nao tentados:${resto:- nenhum}"
  if [[ -n $_DBX_RETER_EM_CURSO ]]; then
    dbx_cmd_caminho_exibivel "${_DBX_RETER_PL[$_DBX_RETER_EM_CURSO]}"
    texto+="; em curso (pode ter ido para a lixeira): $DBX_CMD_EXIBIDO"
  fi
  _dbx_cmd_reter_avisar "$texto"
}

# ---------------------------------------------------------------------------
# Saida (RF-99)
# ---------------------------------------------------------------------------

# _dbx_cmd_reter_emitir <pasta_api> <padrao_citado> <politica> <valor> <modo>
_dbx_cmd_reter_emitir() {
  local alvo=$1 citado=$2 politica=$3 valor=$4 modo=$5 i
  local apagados=0 ja=0 falhas=0 nao_tentados=0
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao reter
  dbx_cmd_campo_caminho pasta "${alvo:-/}"
  dbx_output_campo padrao "$citado"
  dbx_output_campo politica "$politica"
  dbx_output_campo valor "$valor"
  if [[ $politica == 'dias' ]]; then
    dbx_output_campo corte "$DBX_RETENCAO_CORTE"
    dbx_output_campo agora "$DBX_RETENCAO_AGORA"
  fi
  dbx_output_campo modo "$modo"
  if [[ $modo == 'simulado' ]]; then dbx_output_campo simulado sim; else dbx_output_campo simulado nao; fi
  dbx_output_render
  for i in ${DBX_RETENCAO_ORDEM[@]+"${DBX_RETENCAO_ORDEM[@]}"}; do
    case ${_DBX_RETER_RESULTADO[i]} in
      apagado) apagados=$((apagados + 1)) ;;
      ja_ausente) ja=$((ja + 1)) ;;
      falhou) falhas=$((falhas + 1)) ;;
      nao_tentado) nao_tentados=$((nao_tentados + 1)) ;;
    esac
    dbx_cmd_iniciar_saida
    dbx_output_campo acao "${_DBX_RETER_RESULTADO[i]}"
    dbx_cmd_campo_caminho name "${_DBX_RETER_NOME[i]}"
    dbx_cmd_campo_caminho path_display "${_DBX_RETER_PD[i]}"
    dbx_output_campo server_modified "${_DBX_RETER_SM[i]}"
    dbx_output_campo size "${_DBX_RETER_TAMANHO[i]}"
    dbx_output_campo rev "${_DBX_RETER_REV[i]}"
    [[ ${_DBX_RETER_RESULTADO[i]} == 'falhou' ]] && dbx_output_campo motivo "${_DBX_RETER_MOTIVO[i]:-erro_remoto}"
    dbx_output_render
  done
  dbx_cmd_iniciar_saida
  dbx_output_campo candidatos "${#_DBX_RETER_NOME[@]}"
  dbx_output_campo ficam "$DBX_RETENCAO_FICAM"
  if [[ $modo == 'confirmado' ]]; then
    dbx_output_campo apagados "$apagados"
  else
    dbx_output_campo saem "$DBX_RETENCAO_SAEM"
  fi
  dbx_output_campo mantido_pelo_minimo "$DBX_RETENCAO_MINIMO"
  dbx_output_campo fora_do_padrao "$_DBX_RETER_FORA"
  dbx_output_campo ignorados "$_DBX_RETER_IGNORADOS"
  dbx_output_campo ja_ausentes "$ja"
  dbx_output_campo falhas "$falhas"
  dbx_output_campo nao_tentados "$nao_tentados"
  dbx_output_campo listados "$_DBX_RETER_LISTADOS"
  if ((apagados > 0)); then
    dbx_cmd_caminho_exibivel "${alvo:-/}"
    dbx_output_campo recuperacao "os apagados estao na lixeira: dbx lixeira $DBX_CMD_EXIBIDO e dbx restaurar <arquivo>, dentro do prazo do plano da conta"
  fi
  dbx_output_render
}
