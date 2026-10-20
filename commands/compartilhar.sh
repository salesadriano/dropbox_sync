#!/usr/bin/env bash
# compartilhar — link compartilhado (RF-85 a RF-90, F-16). Alias: `share`.
#
# Tres modos, mutuamente exclusivos:
#
#   criar     `compartilhar <caminho> (--publico | --equipe | --senha | --senha-stdin) [--expira V]`
#   listar    `compartilhar --listar [pasta]`
#   revogar   `compartilhar --revogar <url>`
#
# DECISOES DO SOLICITANTE (memoria 2026-10-20-1110-compartilhamento):
#
#   - visibilidade SEMPRE explicita: sem `--publico`, `--equipe` ou `--senha`,
#     sai 2 antes de qualquer rede; nada e publicado por omissao (RSK-57);
#   - a senha nunca vem do argv nem do ambiente: `--senha` le do terminal sem
#     eco (duas vezes, DIV-109) e `--senha-stdin` le uma linha. Ela vive so numa
#     variavel `local` desta execucao, vai ao corpo pelo escape de lib/json e
#     dali ao arquivo de corpo da area de lib/http, e e apagada logo depois da
#     chamada (RF-86, DIV-110, RSK-58);
#   - link existente: igual ao pedido, e devolvido sem escrita; diferente, e
#     modificado, com o antes e o depois (DIV-104, DIV-107, DIV-108).
#
# FRONTEIRA DE CONFINAMENTO DO `--revogar` (RF-89, RSK-59): a revogacao so e
# autorizada pelo `path_lower` que a API devolve em `get_shared_link_metadata`
# NA MESMA EXECUCAO — presente, sem chave repetida e dentro da raiz remota,
# inclusive com a raiz `/` (DIV-114). Nada de lib/state, cache, listagem
# anterior ou arquivo do usuario decide aqui (guarda sem estado).
#
# Ordem: uso -> confinamento -> senha -> rede (RF-85(g)). Nada em lib/state; sem
# trava (DIV-63). Os codigos sao os da taxonomia (0..15).

dbx_cmd_compartilhar_requisitos() { printf 'credencial'; }

readonly DBX_COMPARTILHAR_URL_CRIAR='https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings'
readonly DBX_COMPARTILHAR_URL_LISTAR='https://api.dropboxapi.com/2/sharing/list_shared_links'
readonly DBX_COMPARTILHAR_URL_MODIFICAR='https://api.dropboxapi.com/2/sharing/modify_shared_link_settings'
readonly DBX_COMPARTILHAR_URL_METADADOS='https://api.dropboxapi.com/2/sharing/get_shared_link_metadata'
readonly DBX_COMPARTILHAR_URL_REVOGAR='https://api.dropboxapi.com/2/sharing/revoke_shared_link'
# QA-B5-14 (decisao do Tech Lead): teto de paginas do `--listar`.
readonly DBX_COMPARTILHAR_PAGINAS_MAXIMAS=1000

dbx_cmd_compartilhar_executar() {
  # shellcheck source=lib/compartilhamento.sh
  . "$DBX_CLI_RAIZ/lib/compartilhamento.sh"
  local caminho='' posicionais=0 publico='nao' equipe='nao' senha_terminal='nao' senha_entrada='nao'
  local expira_valor='' expira_opcao='' tem_expira='nao' listar='nao' revogar='nao' url='' urls=0
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --publico | --public) publico='sim' ;;
      --equipe | --team) equipe='sim' ;;
      --senha | --password) senha_terminal='sim' ;;
      --senha-stdin | --password-stdin) senha_entrada='sim' ;;
      --senha=* | --senha-stdin=* | --password=* | --password-stdin=*)
        # RF-86(a): nem a opcao com valor e citada, para o valor nao sair.
        dbx_cmd_falhar uso_invalido 'a senha nunca e aceita na linha de comando; use --senha ou --senha-stdin'
        return $?
        ;;
      --expira | --expires)
        expira_opcao=$1
        shift
        [[ $# -gt 0 ]] || {
          dbx_cmd_falhar uso_invalido "$expira_opcao exige um valor"
          return $?
        }
        expira_valor=$1 tem_expira='sim'
        ;;
      --listar | --list) listar='sim' ;;
      --revogar | --revoke)
        shift
        [[ $# -gt 0 ]] || {
          dbx_cmd_falhar uso_invalido '--revogar exige a url do link'
          return $?
        }
        url=$1 urls=$((urls + 1))
        ;;
      -*)
        # So o nome da opcao: o que vem depois de `=` pode ser segredo.
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: ${1%%=*}"
        return $?
        ;;
      *)
        posicionais=$((posicionais + 1))
        caminho=$1
        ;;
    esac
    shift
  done
  [[ $urls -gt 0 ]] && revogar='sim'

  # Combinacoes (RF-85(d), DIV-112), antes da rede e da leitura da senha. A
  # recusa conta os posicionais, nunca os cita (RF-86(a)).
  local visibilidade='nao'
  [[ $publico$equipe$senha_terminal$senha_entrada == *sim* ]] && visibilidade='sim'
  if [[ $listar == 'sim' && $revogar == 'sim' ]]; then
    dbx_cmd_falhar uso_invalido '--listar e --revogar sao modos diferentes: use um so'
    return $?
  fi
  if [[ ($listar == 'sim' || $revogar == 'sim') && ($visibilidade == 'sim' || $tem_expira == 'sim') ]]; then
    dbx_cmd_falhar uso_invalido 'visibilidade, senha e --expira so valem para criar link (sem --listar nem --revogar)'
    return $?
  fi
  if [[ $revogar == 'sim' && ($urls -ne 1 || $posicionais -ne 0) ]]; then
    dbx_cmd_falhar uso_invalido "--revogar aceita exatamente uma url e nenhum caminho ($urls url(s), $posicionais posicional(is))"
    return $?
  fi
  if [[ $listar == 'sim' && $posicionais -gt 1 ]]; then
    dbx_cmd_falhar uso_invalido "--listar aceita no maximo uma pasta ($posicionais argumento(s) posicional(is))"
    return $?
  fi

  if [[ $revogar == 'sim' ]]; then
    dbx_compartilhamento_validar_url "$url" || {
      dbx_cmd_falhar uso_invalido "$DBX_COMPARTILHAMENTO_MOTIVO"
      return $?
    }
    # A raiz da credencial passa pelo ponto unico (malformada: 3, antes da rede).
    _dbx_cmd_caminho_remoto "${DBX_CONFIG_RAIZ_REMOTA:-/}" || return $?
    _dbx_cmd_compartilhar_revogar "$url"
    return $?
  fi

  if [[ $listar == 'sim' ]]; then
    [[ $posicionais -eq 1 ]] || caminho=${DBX_CONFIG_RAIZ_REMOTA:-/}
    # DIV-123: relativo e uso invalido (2), como no criar e no link-temporario.
    [[ $caminho == /* ]] || {
      dbx_cmd_falhar uso_invalido 'informe o caminho remoto absoluto da pasta (comeca com /)'
      return $?
    }
    _dbx_cmd_caminho_remoto "$caminho" || return $?
    _dbx_cmd_compartilhar_listar "$DBX_CMD_LIDO"
    return $?
  fi

  # Modo criar.
  [[ $posicionais -eq 1 ]] || {
    dbx_cmd_falhar uso_invalido "informe exatamente um caminho remoto ($posicionais argumento(s) posicional(is))"
    return $?
  }
  [[ $visibilidade == 'sim' ]] || {
    dbx_cmd_falhar uso_invalido 'informe a visibilidade: --publico, --equipe ou --senha; nada e publicado por omissao'
    return $?
  }
  if [[ $publico == 'sim' && $equipe == 'sim' ]]; then
    dbx_cmd_falhar uso_invalido '--publico e --equipe sao excludentes'
    return $?
  fi
  if [[ $equipe == 'sim' && ($senha_terminal == 'sim' || $senha_entrada == 'sim') ]]; then
    dbx_cmd_falhar uso_invalido '--equipe nao aceita senha: a senha e para quem nao e da equipe (use --senha sozinha)'
    return $?
  fi
  if [[ $senha_terminal == 'sim' && $senha_entrada == 'sim' ]]; then
    dbx_cmd_falhar uso_invalido '--senha e --senha-stdin sao excludentes: escolha uma fonte'
    return $?
  fi
  local modo='publico'
  [[ $equipe == 'sim' ]] && modo='equipe'
  [[ $senha_terminal == 'sim' || $senha_entrada == 'sim' ]] && modo='senha'
  local expira=''
  if [[ $tem_expira == 'sim' ]]; then
    dbx_compartilhamento_validar_expira "$expira_opcao" "$expira_valor" || {
      dbx_cmd_falhar uso_invalido "$DBX_COMPARTILHAMENTO_MOTIVO"
      return $?
    }
    expira=$DBX_COMPARTILHAMENTO_EXPIRA
  fi

  # RF-85(f), DIV-123: caminho absoluto; relativo e uso invalido (2).
  [[ $caminho == /* ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto absoluto (comeca com /)'
    return $?
  }
  local alvo
  _dbx_cmd_caminho_remoto "$caminho" || return $?
  alvo=$DBX_CMD_LIDO
  [[ -n $alvo ]] || {
    dbx_cmd_falhar uso_invalido 'compartilhar a conta inteira nao e permitido; informe uma pasta ou arquivo'
    return $?
  }

  # A senha, depois do confinamento e antes da rede; nunca na simulacao.
  local senha=''
  if [[ $modo == 'senha' && ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    _dbx_cmd_compartilhar_ler_senha "$senha_terminal" || return $?
  fi
  _dbx_cmd_compartilhar_criar "$alvo" "$modo" "$expira" "$tem_expira"
  local estado=$?
  senha=''
  return "$estado"
}

# _dbx_cmd_compartilhar_ler_senha <do_terminal: sim|nao> — RF-86(b)(c)(d).
#
# Preenche `senha` do chamador (escopo dinamico; nenhum local com esse nome
# aqui). Os tratadores de lib/tmp sao armados antes: sinal durante a leitura
# termina com 14, e o `read -s` de lib/cli religa o eco.
_dbx_cmd_compartilhar_ler_senha() {
  local do_terminal=$1 confirmacao=''
  dbx_tmp_armar
  if [[ $do_terminal == 'sim' ]]; then
    [[ -t 0 ]] || {
      dbx_cmd_falhar uso_invalido 'a opcao --senha le do terminal; sem terminal use --senha-stdin'
      return $?
    }
    dbx_cli_ler_oculto 'senha do link: ' senha || :
  elif [[ -t 0 ]]; then
    dbx_cli_ler_oculto 'senha do link: ' senha || :
  else
    IFS= read -r senha || :
  fi
  dbx_compartilhamento_validar_senha "$senha" || {
    senha=''
    dbx_cmd_falhar uso_invalido "$DBX_COMPARTILHAMENTO_MOTIVO"
    return $?
  }
  [[ $do_terminal == 'sim' ]] || return 0
  dbx_cli_ler_oculto 'confirme a senha: ' confirmacao || :
  if [[ $confirmacao != "$senha" ]]; then
    senha='' confirmacao=''
    dbx_cmd_falhar nao_concluida 'as duas senhas digitadas diferem; nada foi criado nem modificado'
    return $?
  fi
  confirmacao=''
  return 0
}

# ---------------------------------------------------------------------------
# Leitura de SharedLinkMetadata
# ---------------------------------------------------------------------------

# Campos do ultimo link lido.
DBX_COMPARTILHAR_URL='' DBX_COMPARTILHAR_TIPO='' DBX_COMPARTILHAR_CAMINHO=''
DBX_COMPARTILHAR_NOME='' DBX_COMPARTILHAR_VISIBILIDADE='' DBX_COMPARTILHAR_SENHA=''
DBX_COMPARTILHAR_EXPIRA='' DBX_COMPARTILHAR_TEM_CAMINHO='nao'

# _dbx_cmd_compartilhar_ler_link <segmentos...> — le um SharedLinkMetadata do
# documento corrente (raiz ou item de `links`).
_dbx_cmd_compartilhar_ler_link() {
  DBX_COMPARTILHAR_URL='' DBX_COMPARTILHAR_TIPO='' DBX_COMPARTILHAR_CAMINHO=''
  DBX_COMPARTILHAR_NOME='' DBX_COMPARTILHAR_VISIBILIDADE='' DBX_COMPARTILHAR_SENHA='nao'
  DBX_COMPARTILHAR_EXPIRA='' DBX_COMPARTILHAR_TEM_CAMINHO='nao'
  _dbx_cmd_campo "$@" url && DBX_COMPARTILHAR_URL=$DBX_CMD_LIDO
  _dbx_cmd_campo "$@" name && DBX_COMPARTILHAR_NOME=$DBX_CMD_LIDO
  _dbx_cmd_campo "$@" expires && DBX_COMPARTILHAR_EXPIRA=$DBX_CMD_LIDO
  if _dbx_cmd_campo "$@" '.tag'; then
    case $DBX_CMD_LIDO in
      file) DBX_COMPARTILHAR_TIPO='arquivo' ;;
      folder) DBX_COMPARTILHAR_TIPO='pasta' ;;
      *) DBX_COMPARTILHAR_TIPO=$DBX_CMD_LIDO ;;
    esac
  fi
  if [[ $(dbx_json_tipo "$@" path_lower 2>/dev/null) == 'cadeia' ]]; then
    DBX_COMPARTILHAR_TEM_CAMINHO='sim'
    _dbx_cmd_campo "$@" path_lower && DBX_COMPARTILHAR_CAMINHO=$DBX_CMD_LIDO
  fi
  _dbx_cmd_campo "$@" link_permissions resolved_visibility '.tag' && DBX_COMPARTILHAR_VISIBILIDADE=$DBX_CMD_LIDO
  _dbx_cmd_campo "$@" link_permissions require_password && [[ $DBX_CMD_LIDO == 'true' ]] && DBX_COMPARTILHAR_SENHA='sim'
  DBX_CMD_LIDO=''
  return 0
}

# _dbx_cmd_compartilhar_campos_do_link — url, visibilidade, senha, expira.
_dbx_cmd_compartilhar_campos_do_link() {
  dbx_output_campo url "$DBX_COMPARTILHAR_URL"
  dbx_output_campo visibilidade "$DBX_COMPARTILHAR_VISIBILIDADE"
  dbx_output_campo senha "$DBX_COMPARTILHAR_SENHA"
  dbx_output_campo expira "$DBX_COMPARTILHAR_EXPIRA"
}

# _dbx_cmd_compartilhar_recusa <operacao> <escopo> — diagnostico da recusa do
# servico guardada em DBX_CMD_FALHA_* ou nos canais de lib/http (RF-90(b)).
#
# [sigiloso] = `sim` quando o pedido levou a senha (QA-B5-08, QA-B5-09): nenhum
# texto do servico e citado — nem `error_summary`, nem corpo, nem trecho —, so a
# mensagem propria da classe, o codigo HTTP e a tag do vocabulario fechado de
# lib/errors. A classificacao usa o resumo ORIGINAL, sem mascara.
_dbx_cmd_compartilhar_recusa() {
  local operacao=$1 escopo=$2 sigiloso=${3:-nao} resumo=${DBX_HTTP_RESUMO_DE_ERRO:-}
  local classe=${DBX_HTTP_CLASSE:-erro_remoto} citacao
  # QA-B5-12: 2xx que chega aqui e corpo malformado, nunca sucesso.
  [[ $classe == 'sucesso' ]] && classe='erro_remoto'
  if [[ $sigiloso == 'sim' ]]; then
    citacao="codigo HTTP ${DBX_HTTP_CODIGO:-0}"
    # QA-B5-17: a tag igual a senha enviada nao e citada (seria a propria senha).
    dbx_errors_tag_reconhecida "$resumo" && [[ $DBX_ERRORS_TAG != "${senha:-}" ]] &&
      citacao+=", tag $DBX_ERRORS_TAG"
  else
    citacao=${resumo:-codigo ${DBX_HTTP_CODIGO:-0}}
  fi
  case $resumo in
    *missing_scope*)
      [[ $sigiloso == 'sim' ]] ||
        { dbx_cmd_ler_corpo_silencioso 'error required_scope' && [[ -n ${DBX_CMD_CAMPOS[0]} ]] &&
          [[ ${DBX_CMD_CAMPOS[0]} =~ ^[a-z._]{1,64}$ ]] && escopo=${DBX_CMD_CAMPOS[0]}; }
      dbx_cmd_falhar autenticacao \
        "escopo $escopo ausente; remedio: habilite $escopo no App Console do aplicativo e rode dbx unlink e depois dbx config"
      ;;
    settings_error/not_authorized* | not_authorized*)
      dbx_cmd_falhar permissao \
        'a conta nao permite esta configuracao de link (no plano Basic, so link publico, sem senha e sem expiracao); remedio: use --publico sem --expira, ou uma conta que permita'
      ;;
    settings_error/invalid_settings* | invalid_settings*)
      dbx_cmd_falhar uso_invalido 'configuracao de link recusada pelo servico (invalid_settings)'
      ;;
    *)
      dbx_errors_classe_valida "$classe" || classe='erro_remoto'
      dbx_cmd_falhar "$classe" "$operacao recusada: $citacao"
      ;;
  esac
}

# _dbx_cmd_compartilhar_coerente — QA-B5-16, QA-B5-19: `resolved_visibility`
# em {password, team_and_password} se, e somente se, `require_password` e
# verdadeiro. Resposta incoerente: 10, com o remedio de conferir. Vale na
# criacao, no modify e no reuso.
_dbx_cmd_compartilhar_coerente() {
  local exige='nao'
  case $DBX_COMPARTILHAR_VISIBILIDADE in password | team_and_password) exige='sim' ;; esac
  [[ $exige == "$DBX_COMPARTILHAR_SENHA" ]] && return 0
  dbx_cmd_falhar erro_remoto \
    "resposta incoerente do servico (visibilidade ${DBX_COMPARTILHAR_VISIBILIDADE:-ausente} com require_password $DBX_COMPARTILHAR_SENHA) para $DBX_COMPARTILHAR_URL; confira o link com dbx compartilhar --listar"
}

# _dbx_cmd_compartilhar_mascarar_senha — QA-B5-02: troca o VALOR da senha
# (variavel `senha` do chamador, por escopo dinamico) nos canais que a resposta
# do servico enche e que chegam ao diagnostico: `error_summary` JSON, primeira
# linha de corpo nao JSON, motivo de falha, diagnostico do cliente e o corpo.
# So substituicao de parametro do shell: nada vai a argv nem ao ambiente.
_dbx_cmd_compartilhar_mascarar_senha() {
  [[ -n ${senha:-} ]] || return 0
  DBX_HTTP_RESUMO_DE_ERRO=${DBX_HTTP_RESUMO_DE_ERRO//"$senha"/[REDIGIDO]}
  # shellcheck disable=SC2034  # canais publicos de lib/http e lib/cmd
  DBX_HTTP_RESUMO_DO_SERVICO=${DBX_HTTP_RESUMO_DO_SERVICO//"$senha"/[REDIGIDO]}
  # shellcheck disable=SC2034
  DBX_HTTP_DIAGNOSTICO=${DBX_HTTP_DIAGNOSTICO//"$senha"/[REDIGIDO]}
  DBX_HTTP_CORPO=${DBX_HTTP_CORPO//"$senha"/[REDIGIDO]}
  DBX_CMD_FALHA_MOTIVO=${DBX_CMD_FALHA_MOTIVO//"$senha"/[REDIGIDO]}
  return 0
}

# _dbx_cmd_compartilhar_url_valida — QA-B5-07: resposta de escrita bem
# sucedida tem de trazer a `url` do link, sem byte de controle.
_dbx_cmd_compartilhar_url_valida() {
  local LC_ALL=C
  # QA-B5-18: so ASCII imprimivel (sem espaco Unicode como U+00A0 e U+2028).
  [[ $DBX_COMPARTILHAR_URL =~ ^[!-~]+$ && $DBX_COMPARTILHAR_URL == https://* &&
    $DBX_COMPARTILHAR_URL != *[[:space:]]* &&
    $DBX_COMPARTILHAR_URL != *[$'\001'-$'\037\177']* ]] && return 0
  dbx_cmd_falhar erro_remoto 'o servico respondeu sem a url do link (ou com url malformada): resposta nao interpretavel'
}

# ---------------------------------------------------------------------------
# Criar (RF-85) e link existente (RF-87)
# ---------------------------------------------------------------------------

# _dbx_cmd_compartilhar_criar <alvo> <modo> <expira> <tem_expira>
_dbx_cmd_compartilhar_criar() {
  local alvo=$1 modo=$2 expira=$3 tem_expira=$4 corpo estado
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    _dbx_cmd_compartilhar_existente "$alvo" "$modo" "$expira" "$tem_expira"
    return $?
  fi
  dbx_compartilhamento_corpo corpo path "$alvo" "$modo" "$expira" senha
  _dbx_cmd_escrita_remota "$DBX_COMPARTILHAR_URL_CRIAR" "$corpo" silencioso sim
  estado=$?
  corpo=''
  if [[ $estado -eq 0 ]]; then
    senha=''
    _dbx_cmd_compartilhar_ler_link
    _dbx_cmd_encerrar_consulta
    _dbx_cmd_compartilhar_url_valida || return $?
    _dbx_cmd_compartilhar_coerente || return $?
    _dbx_cmd_compartilhar_emitir criado "$alvo" "$modo"
    return $?
  fi
  # QA-B5-12: 2xx com corpo malformado ja foi diagnosticado (10) por lib/cmd.
  if [[ ${DBX_HTTP_CLASSE:-} == 'sucesso' ]]; then
    _dbx_cmd_compartilhar_mascarar_senha
    senha=''
    return "$estado"
  fi
  # RF-87, DIV-119: inclusive na retentativa de uma resposta perdida. O
  # resumo e o ORIGINAL: a mascara por valor vem depois (QA-B5-08).
  if [[ ${DBX_HTTP_RESUMO_DE_ERRO:-} == shared_link_already_exists* ]]; then
    _dbx_cmd_compartilhar_mascarar_senha
    _dbx_cmd_compartilhar_existente "$alvo" "$modo" "$expira" "$tem_expira"
    return $?
  fi
  local sigiloso='nao'
  [[ $modo == 'senha' ]] && sigiloso='sim'
  _dbx_cmd_compartilhar_recusa 'criacao do link' sharing.write "$sigiloso"
  estado=$?
  _dbx_cmd_compartilhar_mascarar_senha
  senha=''
  return "$estado"
}

# _dbx_cmd_compartilhar_emitir <situacao> <alvo> <modo> — o link lido, com o
# aviso de visibilidade resolvida diferente da pedida (RF-85(i)).
_dbx_cmd_compartilhar_emitir() {
  local situacao=$1 alvo=$2 modo=$3 aviso=''
  dbx_compartilhamento_visibilidade_esperada "$modo"
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao compartilhar
  dbx_output_campo situacao "$situacao"
  dbx_cmd_campo_caminho caminho "$alvo"
  dbx_output_campo tipo "$DBX_COMPARTILHAR_TIPO"
  _dbx_cmd_compartilhar_campos_do_link
  if [[ $DBX_COMPARTILHAR_VISIBILIDADE != "$DBX_COMPARTILHAMENTO_ESPERADA" ]]; then
    dbx_output_campo visibilidade_pedida "$DBX_COMPARTILHAMENTO_ESPERADA"
    aviso="o servico aplicou ${DBX_COMPARTILHAR_VISIBILIDADE:-desconhecida} no lugar de $DBX_COMPARTILHAMENTO_ESPERADA"
  fi
  dbx_output_render
  [[ -n $aviso ]] && _dbx_cmd_compartilhar_avisar "$aviso"
  if [[ $modo == 'publico' && -t 2 ]]; then
    _dbx_cmd_compartilhar_avisar "qualquer pessoa com o link acessa $alvo"
  fi
  return 0
}

_dbx_cmd_compartilhar_avisar() {
  dbx_cmd_iniciar_saida
  dbx_output_diagnostico aviso "$1"
  dbx_output_render_diagnostico >&2
}

# _dbx_cmd_compartilhar_existente <alvo> <modo> <expira> <tem_expira> — RF-87 e
# o plano do `--dry-run` (RF-85(j)).
_dbx_cmd_compartilhar_existente() {
  local alvo=$1 modo=$2 expira=$3 tem_expira=$4 corpo quantidade indice
  local -a candidatos=()
  dbx_compartilhamento_corpo_simples corpo path "$alvo"
  corpo="${corpo%\}},\"direct_only\":true}"
  dbx_auth_requisitar POST "$DBX_COMPARTILHAR_URL_LISTAR" "$corpo" sim || {
    senha=''
    _dbx_cmd_compartilhar_recusa 'listagem dos links do alvo' sharing.read
    return $?
  }
  _dbx_cmd_analisar_corpo || {
    senha=''
    return $?
  }
  [[ $DBX_JSON_DUPLICADAS -eq 0 ]] || {
    senha=''
    _dbx_cmd_encerrar_consulta
    dbx_cmd_falhar erro_remoto 'a listagem dos links tem campo repetido: ambigua, nada foi feito'
    return $?
  }
  quantidade=$(dbx_json_tamanho_arranjo links) || quantidade=0
  for ((indice = 0; indice < quantidade; indice++)); do
    _dbx_cmd_compartilhar_ler_link links "$indice"
    # So o link do PROPRIO alvo; o de pasta ancestral e descartado.
    [[ $DBX_COMPARTILHAR_TEM_CAMINHO == 'sim' ]] || continue
    dbx_compartilhamento_mesmo_caminho "$DBX_COMPARTILHAR_CAMINHO" "$alvo" || continue
    candidatos+=("$indice")
  done

  if [[ ${#candidatos[@]} -eq 0 ]]; then
    _dbx_cmd_encerrar_consulta
    if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
      dbx_compartilhamento_visibilidade_esperada "$modo"
      dbx_cmd_iniciar_saida
      dbx_output_campo operacao compartilhar
      dbx_output_campo situacao criaria
      dbx_cmd_campo_caminho caminho "$alvo"
      dbx_output_campo visibilidade "$DBX_COMPARTILHAMENTO_ESPERADA"
      dbx_output_campo senha "$([[ $modo == 'senha' ]] && printf sim || printf nao)"
      dbx_output_campo expira "$expira"
      dbx_output_campo simulado sim
      dbx_output_render
      return 0
    fi
    senha=''
    dbx_cmd_falhar erro_remoto 'o servico diz que o link existe mas nao o lista; nada foi feito'
    return $?
  fi
  if [[ ${#candidatos[@]} -gt 1 ]]; then
    local lista=''
    for indice in "${candidatos[@]}"; do
      _dbx_cmd_compartilhar_ler_link links "$indice"
      lista+=" $DBX_COMPARTILHAR_URL"
    done
    _dbx_cmd_encerrar_consulta
    senha=''
    dbx_cmd_falhar conflito \
      "ha ${#candidatos[@]} links para $alvo:$lista; nada foi modificado; remedio: revogue os excedentes com dbx compartilhar --revogar <url>"
    return $?
  fi

  _dbx_cmd_compartilhar_ler_link links "${candidatos[0]}"
  _dbx_cmd_encerrar_consulta
  # QA-B5-13: link listado sem url (ou malformada) nao e reusado nem modificado.
  _dbx_cmd_compartilhar_url_valida || {
    senha=''
    return 10
  }
  local antes_url=$DBX_COMPARTILHAR_URL antes_vis=$DBX_COMPARTILHAR_VISIBILIDADE
  local antes_senha=$DBX_COMPARTILHAR_SENHA antes_expira=$DBX_COMPARTILHAR_EXPIRA
  local pedida_senha='nao'
  [[ $modo == 'senha' ]] && pedida_senha='sim'
  dbx_compartilhamento_visibilidade_esperada "$modo"
  local pedida_vis=$DBX_COMPARTILHAMENTO_ESPERADA

  # DIV-104: igual = visibilidade resolvida, senha e, so com --expira, expiracao.
  # DIV-108: a senha vigente nao e comparavel; com senha pedida, sempre modifica.
  if [[ $modo != 'senha' && $antes_vis == "$pedida_vis" && $antes_senha == 'nao' ]] &&
    [[ $tem_expira == 'nao' || $antes_expira == "$expira" ]]; then
    # QA-B5-19 (DIV-129): link incoerente nunca e devolvido como esta. Link
    # incoerente difere do pedido e cai no modify, cuja resposta e conferida;
    # a guarda aqui fecha o reuso sem escrita por construcao.
    _dbx_cmd_compartilhar_coerente || return $?
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao compartilhar
    if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
      dbx_output_campo situacao reusaria
    else
      dbx_output_campo situacao existente
    fi
    dbx_cmd_campo_caminho caminho "$alvo"
    dbx_output_campo tipo "$DBX_COMPARTILHAR_TIPO"
    _dbx_cmd_compartilhar_campos_do_link
    [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  local depois_vis depois_senha depois_expira tipo=$DBX_COMPARTILHAR_TIPO
  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    depois_vis=$pedida_vis depois_senha=$pedida_senha depois_expira=$antes_expira
    [[ $tem_expira == 'sim' ]] && depois_expira=$expira
    _dbx_cmd_compartilhar_antes_depois modificaria "$alvo" "$tipo" "$antes_url" \
      "$antes_vis" "$antes_senha" "$antes_expira" "$depois_vis" "$depois_senha" "$depois_expira" "$modo"
    return $?
  fi

  local estado
  dbx_compartilhamento_corpo corpo url "$antes_url" "$modo" "$expira" senha
  _dbx_cmd_escrita_remota "$DBX_COMPARTILHAR_URL_MODIFICAR" "$corpo" silencioso sim
  estado=$?
  corpo=''
  if [[ $estado -ne 0 ]]; then
    local sigiloso='nao'
    [[ $modo == 'senha' ]] && sigiloso='sim'
    if [[ ${DBX_HTTP_CLASSE:-} == 'sucesso' ]]; then
      : # QA-B5-12: 2xx malformado, ja diagnosticado (10) por lib/cmd.
    elif [[ ${DBX_HTTP_RESUMO_DE_ERRO:-} == shared_link_not_found* ]]; then
      dbx_cmd_falhar nao_encontrado 'o link mudou durante a operacao; repita (nenhum link novo foi criado)'
      estado=$?
    else
      _dbx_cmd_compartilhar_recusa 'modificacao do link' sharing.write "$sigiloso"
      estado=$?
    fi
    _dbx_cmd_compartilhar_mascarar_senha
    senha=''
    return "$estado"
  fi
  senha=''
  # O depois e o da RESPOSTA, nunca uma copia do pedido (RF-87(c)).
  _dbx_cmd_compartilhar_ler_link
  _dbx_cmd_encerrar_consulta
  _dbx_cmd_compartilhar_url_valida || return $?
  _dbx_cmd_compartilhar_coerente || return $?
  [[ -n $DBX_COMPARTILHAR_TIPO ]] && tipo=$DBX_COMPARTILHAR_TIPO
  _dbx_cmd_compartilhar_antes_depois modificado "$alvo" "$tipo" "$DBX_COMPARTILHAR_URL" \
    "$antes_vis" "$antes_senha" "$antes_expira" \
    "$DBX_COMPARTILHAR_VISIBILIDADE" "$DBX_COMPARTILHAR_SENHA" "$DBX_COMPARTILHAR_EXPIRA" "$modo"
}

# _dbx_cmd_compartilhar_antes_depois <situacao> <alvo> <tipo> <url> <antes x3> <depois x3> <modo>
_dbx_cmd_compartilhar_antes_depois() {
  local situacao=$1 alvo=$2 tipo=$3 url=$4 antes_vis=$5 antes_senha=$6 antes_expira=$7
  local depois_vis=$8 depois_senha=$9 depois_expira=${10} modo=${11} aviso=''
  dbx_compartilhamento_visibilidade_esperada "$modo"
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao compartilhar
  dbx_output_campo situacao "$situacao"
  dbx_cmd_campo_caminho caminho "$alvo"
  dbx_output_campo tipo "$tipo"
  dbx_output_campo url "$url"
  dbx_output_campo visibilidade "$depois_vis"
  dbx_output_campo senha "$depois_senha"
  dbx_output_campo expira "$depois_expira"
  # QA-B5-01: a senha so foi redefinida se o depois (lido da resposta) tem senha.
  [[ $modo == 'senha' && $depois_senha == 'sim' ]] && dbx_output_campo senha_redefinida sim
  # RF-85(i) tambem depois do modify: pedido nao atendido sai com a pedida e aviso.
  if [[ $depois_vis != "$DBX_COMPARTILHAMENTO_ESPERADA" ]]; then
    dbx_output_campo visibilidade_pedida "$DBX_COMPARTILHAMENTO_ESPERADA"
    aviso="o servico aplicou ${depois_vis:-desconhecida} no lugar de $DBX_COMPARTILHAMENTO_ESPERADA"
  fi
  dbx_output_campo antes_visibilidade "$antes_vis"
  dbx_output_campo antes_senha "$antes_senha"
  dbx_output_campo antes_expira "$antes_expira"
  dbx_output_campo depois_visibilidade "$depois_vis"
  dbx_output_campo depois_senha "$depois_senha"
  dbx_output_campo depois_expira "$depois_expira"
  dbx_output_campo antes "visibilidade $antes_vis, senha $antes_senha, expira ${antes_expira:-nunca}"
  dbx_output_campo depois "visibilidade $depois_vis, senha $depois_senha, expira ${depois_expira:-nunca}"
  [[ $situacao == 'modificaria' ]] && dbx_output_campo simulado sim
  dbx_output_render
  [[ $situacao == 'modificaria' ]] && return 0
  [[ -n $aviso ]] && _dbx_cmd_compartilhar_avisar "$aviso"
  if [[ $antes_senha == 'sim' && $depois_senha == 'nao' ]]; then
    _dbx_cmd_compartilhar_avisar "a senha do link foi removida: $url"
  fi
  dbx_compartilhamento_exposicao "$antes_vis" "$antes_senha" "$antes_expira" "$depois_vis" "$depois_senha" "$depois_expira"
  if [[ -n $DBX_COMPARTILHAMENTO_EXPOSICAO ]]; then
    _dbx_cmd_compartilhar_avisar "o link $url ficou mais exposto: $DBX_COMPARTILHAMENTO_EXPOSICAO"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Listar (RF-88)
# ---------------------------------------------------------------------------

# _dbx_cmd_compartilhar_listar <pasta_api> — `list_shared_links` SEM `path`,
# paginada ate o fim (DIV-105), filtrada no cliente pelo confinamento.
_dbx_cmd_compartilhar_listar() {
  local pasta=${1:-/} raiz=${DBX_CONFIG_RAIZ_REMOTA:-/} corpo='{}' quantidade indice mais cursor
  local omitidos=0 paginas=0
  local -A vistos=()
  local -a chaves=() urls=() tipos=() nomes=() caminhos=() visibilidades=() senhas=() expiras=()
  while :; do
    # QA-B5-14: teto de paginas, contra `has_more` sem fim com paginas cheias.
    if ((paginas >= DBX_COMPARTILHAR_PAGINAS_MAXIMAS)); then
      dbx_cmd_falhar erro_remoto "listagem nao terminou em $DBX_COMPARTILHAR_PAGINAS_MAXIMAS paginas; nada foi listado"
      return $?
    fi
    paginas=$((paginas + 1))
    dbx_auth_requisitar POST "$DBX_COMPARTILHAR_URL_LISTAR" "$corpo" sim || {
      if [[ ${DBX_HTTP_CLASSE:-} == 'nao_concluida' ]]; then
        dbx_cmd_falhar nao_concluida 'a listagem foi reiniciada pelo servico (reset): repita a listagem'
        return $?
      fi
      _dbx_cmd_compartilhar_recusa 'listagem de links' sharing.read
      return $?
    }
    _dbx_cmd_analisar_corpo || return $?
    [[ $DBX_JSON_DUPLICADAS -eq 0 ]] || {
      _dbx_cmd_encerrar_consulta
      dbx_cmd_falhar erro_remoto 'a pagina da listagem tem campo repetido: ambigua, nada foi listado'
      return $?
    }
    quantidade=$(dbx_json_tamanho_arranjo links) || quantidade=0
    for ((indice = 0; indice < quantidade; indice++)); do
      _dbx_cmd_compartilhar_ler_link links "$indice"
      # Falha fechada: sem path_lower, fora da raiz ou fora da pasta, nao sai.
      if [[ $DBX_COMPARTILHAR_TEM_CAMINHO != 'sim' ]] ||
        ! dbx_compartilhamento_confinado "$DBX_COMPARTILHAR_CAMINHO" "$raiz" "$pasta"; then
        omitidos=$((omitidos + 1))
        continue
      fi
      dbx_cmd_chave_ascii "$DBX_COMPARTILHAR_CAMINHO"
      chaves+=("$DBX_CMD_CHAVE"$'\001'"$DBX_COMPARTILHAR_URL")
      urls+=("$DBX_COMPARTILHAR_URL") tipos+=("$DBX_COMPARTILHAR_TIPO") nomes+=("$DBX_COMPARTILHAR_NOME")
      caminhos+=("$DBX_COMPARTILHAR_CAMINHO") visibilidades+=("$DBX_COMPARTILHAR_VISIBILIDADE")
      senhas+=("$DBX_COMPARTILHAR_SENHA") expiras+=("$DBX_COMPARTILHAR_EXPIRA")
    done
    mais='' cursor=''
    _dbx_cmd_campo has_more && mais=$DBX_CMD_LIDO
    _dbx_cmd_campo cursor && cursor=$DBX_CMD_LIDO
    _dbx_cmd_encerrar_consulta
    [[ $mais == 'true' ]] || break
    # QA-B5-03: pagina sem item com `has_more` tambem nao avanca (RF-88(b)).
    if [[ -z $cursor || -n ${vistos[$cursor]:-} || $quantidade -eq 0 ]]; then
      dbx_cmd_falhar erro_remoto 'paginacao nao avanca: o servico repetiu o cursor ou nao o enviou; nada foi listado'
      return $?
    fi
    vistos[$cursor]=1
    dbx_compartilhamento_corpo_simples corpo cursor "$cursor"
  done

  # Ordem pela chave sem caixa de path_lower e depois pela url (LC_ALL=C).
  local -a ordem=()
  local atual posicao
  for indice in "${!chaves[@]}"; do
    posicao=${#ordem[@]}
    while ((posicao > 0)); do
      atual=${ordem[posicao - 1]}
      _dbx_cmd_compartilhar_menor "${chaves[indice]}" "${chaves[atual]}" || break
      ordem[posicao]=$atual
      posicao=$((posicao - 1))
    done
    ordem[posicao]=$indice
  done
  for indice in ${ordem[@]+"${ordem[@]}"}; do
    dbx_cmd_iniciar_saida
    dbx_output_campo url "${urls[indice]}"
    dbx_output_campo tipo "${tipos[indice]}"
    dbx_cmd_campo_caminho name "${nomes[indice]}"
    dbx_cmd_campo_caminho path_lower "${caminhos[indice]}"
    dbx_output_campo visibilidade "${visibilidades[indice]}"
    dbx_output_campo senha "${senhas[indice]}"
    dbx_output_campo expira "${expiras[indice]}"
    dbx_output_render
  done
  dbx_cmd_iniciar_saida
  dbx_output_campo total "${#ordem[@]}"
  dbx_output_campo omitidos "$omitidos"
  dbx_output_render
  return 0
}

_dbx_cmd_compartilhar_menor() { # <a> <b> — 0 quando a < b em bytes
  local LC_ALL=C
  [[ $1 < $2 ]]
}

# ---------------------------------------------------------------------------
# Revogar (RF-89) — P0 de confinamento
# ---------------------------------------------------------------------------

# _dbx_cmd_compartilhar_revogar <url> — URL ja validada e raiz ja conferida.
_dbx_cmd_compartilhar_revogar() {
  local url=$1 corpo minusculo='' tipo='' duplicadas raiz=${DBX_CONFIG_RAIZ_REMOTA:-/}
  dbx_compartilhamento_corpo_simples corpo url "$url"
  dbx_auth_requisitar POST "$DBX_COMPARTILHAR_URL_METADADOS" "$corpo" sim || {
    _dbx_cmd_compartilhar_recusa 'consulta do link' sharing.read
    return $?
  }
  # A guarda: so a resposta desta execucao decide (sem estado local).
  dbx_json_contexto guarda_revogacao || {
    dbx_cmd_falhar erro_remoto 'contexto de analise indisponivel'
    return $?
  }
  if ! dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null; then
    DBX_HTTP_CORPO=''
    dbx_json_descartar guarda_revogacao
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    dbx_cmd_falhar erro_remoto 'resposta da guarda nao interpretavel: nada foi revogado'
    return $?
  fi
  DBX_HTTP_CORPO=''
  duplicadas=$DBX_JSON_DUPLICADAS
  tipo=$(dbx_json_tipo path_lower 2>/dev/null) || tipo='ausente'
  [[ $tipo == 'cadeia' ]] && dbx_json_valor path_lower >/dev/null 2>&1 && minusculo=$DBX_JSON_RESULTADO
  DBX_JSON_RESULTADO=''
  dbx_json_descartar guarda_revogacao
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"

  if [[ $duplicadas -ne 0 ]]; then
    dbx_cmd_falhar erro_remoto "a resposta da guarda tem campo repetido ($duplicadas): ambigua, nada foi revogado"
    return $?
  fi
  case $tipo in
    ausente | nulo)
      dbx_cmd_falhar caminho_recusado \
        'o link nao aponta para item da sua Dropbox (sem path_lower): fora do confinamento, nada foi revogado'
      return $?
      ;;
    cadeia) ;;
    *)
      dbx_cmd_falhar erro_remoto 'path_lower da guarda nao e texto: nada foi revogado'
      return $?
      ;;
  esac
  if [[ -z $minusculo ]]; then
    dbx_cmd_falhar erro_remoto 'path_lower vazio na resposta da guarda: nada foi revogado'
    return $?
  fi
  dbx_compartilhamento_confinado "$minusculo" "$raiz" || {
    dbx_cmd_caminho_exibivel "$minusculo"
    dbx_cmd_falhar caminho_recusado \
      "o link aponta para item fora da raiz remota configurada ($raiz): $DBX_CMD_EXIBIDO; nada foi revogado"
    return $?
  }

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao revogar
    dbx_output_campo url "$url"
    dbx_cmd_campo_caminho caminho "$minusculo"
    dbx_output_campo resultado revogaria
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  _dbx_cmd_escrita_remota "$DBX_COMPARTILHAR_URL_REVOGAR" "$corpo" silencioso sim || {
    local estado=$?
    # QA-B5-12: 2xx com corpo malformado ja foi diagnosticado (10) por lib/cmd.
    [[ ${DBX_HTTP_CLASSE:-} == 'sucesso' ]] && return "$estado"
    if [[ ${DBX_HTTP_RESUMO_DE_ERRO:-} == shared_link_not_found* ]]; then
      dbx_cmd_falhar nao_encontrado 'o link nao existe (pode ja ter sido revogado pela tentativa anterior)'
      return $?
    fi
    _dbx_cmd_compartilhar_recusa 'revogacao do link' sharing.write
    return $?
  }
  _dbx_cmd_encerrar_consulta
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao revogar
  dbx_output_campo url "$url"
  dbx_cmd_campo_caminho caminho "$minusculo"
  dbx_output_campo resultado revogado
  dbx_output_render
  return 0
}
