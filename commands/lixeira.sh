#!/usr/bin/env bash
# lixeira — lista os itens apagados (RF-75) e, com `--excluir`, expurga um item
# apagado de forma PERMANENTE (RF-76). Alias: `trash`; `--excluir` tem alias
# `--purge`.
#
# LISTAGEM: so leitura. `list_folder` com `include_deleted` e
# `include_restorable_info`, um nivel por chamada; com `-R` desce nas pastas
# VIVAS (o `DeletedMetadata` nao diz se o item apagado era pasta, DIV-64, e a
# saida nao inventa tipo nem data).
#
# EXCLUSAO PERMANENTE: irreversivel e so em Dropbox Business, com o escopo
# opcional `files.permanent_delete`. A especificacao avisa que
# `permanently_delete` sobre item VIVO apaga e expurga de uma vez; por isso:
#
#   - a guarda pergunta a API (`get_metadata` com `include_deleted`) e so segue
#     com `DeletedMetadata` (DIV-54). Nada de estado local decide aqui: a
#     memoria do sync nao e lida (guarda sem estado);
#   - toda recusa vem ANTES da chamada destrutiva; a de uso, de confinamento, de
#     raiz e de confirmacao vem antes de qualquer chamada, inclusive a
#     renovacao do token;
#   - a confirmacao repete o alvo (DIV-55): sem terminal, `--confirmar-caminho`
#     identico ao alvo; com terminal, o operador digita o caminho (a opcao,
#     quando dada e identica, dispensa a pergunta). Nao ha `--yes` nem `-y`.
#
# A janela entre a checagem e o expurgo e risco residual declarado (DIV-54).
# Nao trava (DIV-63).

dbx_cmd_lixeira_requisitos() { printf 'credencial'; }

readonly DBX_LIXEIRA_LIMITE_PADRAO=100

dbx_cmd_lixeira_executar() {
  local pasta='' tem_pasta='nao' recursivo='nao' limite=$DBX_LIXEIRA_LIMITE_PADRAO
  local alvo='' tem_alvo='nao' confirmacao='' tem_confirmacao='nao'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --recursivo | --recursive | -R) recursivo='sim' ;;
      --limite | --limit)
        shift
        limite=${1-}
        if [[ ! $limite =~ ^[0-9]{1,3}$ ]] || ((10#$limite < 1 || 10#$limite > 100)); then
          dbx_cmd_caminho_exibivel "$limite"
          dbx_cmd_falhar uso_invalido "limite invalido: [${DBX_CMD_EXIBIDO}] (inteiro de 1 a 100)"
          return $?
        fi
        limite=$((10#$limite))
        ;;
      --excluir | --purge)
        [[ $tem_alvo == 'nao' ]] || {
          dbx_cmd_falhar uso_invalido 'informe um unico alvo para --excluir'
          return $?
        }
        shift
        alvo=${1-} tem_alvo='sim'
        ;;
      --confirmar-caminho)
        shift
        confirmacao=${1-} tem_confirmacao='sim'
        ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        [[ $tem_pasta == 'nao' ]] || {
          dbx_cmd_falhar uso_invalido 'informe apenas uma pasta'
          return $?
        }
        pasta=$1 tem_pasta='sim'
        ;;
    esac
    shift
  done

  if [[ $tem_alvo == 'sim' ]]; then
    [[ $tem_pasta == 'nao' ]] || {
      dbx_cmd_falhar uso_invalido '--excluir nao aceita pasta posicional: informe so o alvo'
      return $?
    }
    [[ $recursivo == 'nao' ]] || {
      dbx_cmd_falhar uso_invalido '--excluir expurga um alvo e nao aceita --recursivo'
      return $?
    }
    [[ -n $alvo ]] || {
      dbx_cmd_falhar uso_invalido '--excluir exige o caminho do item apagado'
      return $?
    }
    _dbx_cmd_lixeira_excluir "$alvo" "$tem_confirmacao" "$confirmacao" "$limite"
    return $?
  fi
  [[ $tem_confirmacao == 'nao' ]] || {
    dbx_cmd_falhar uso_invalido '--confirmar-caminho so vale com --excluir'
    return $?
  }

  # Sem argumento, a raiz remota configurada (como `list`).
  [[ $tem_pasta == 'sim' ]] || pasta=${DBX_CONFIG_RAIZ_REMOTA:-/}
  local remoto
  _dbx_cmd_caminho_remoto "$pasta" || return $?
  remoto=$DBX_CMD_LIDO

  local -a fila=("$remoto") tags caminhos nomes restauraveis
  local -A visitadas=()
  local atual indice total=0
  # QA-B3-06: cada pasta e listada uma vez (chave sem caixa ASCII).
  dbx_cmd_chave_ascii "${remoto:-/}"
  visitadas[$DBX_CMD_CHAVE]=1
  while [[ ${#fila[@]} -gt 0 ]]; do
    atual=${fila[0]}
    fila=("${fila[@]:1}")
    if ! dbx_cmd_listar_nivel "$atual" "$limite"; then
      if [[ $atual == "$remoto" && ${DBX_HTTP_RESUMO_DE_ERRO:-} == *not_folder* ]]; then
        dbx_cmd_falhar uso_invalido "o caminho e arquivo; a lixeira lista pasta: $pasta"
        return $?
      fi
      dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
      return $?
    fi
    tags=("${DBX_CMD_NIVEL_TAGS[@]}")
    nomes=("${DBX_CMD_NIVEL_NOMES[@]}")
    caminhos=("${DBX_CMD_NIVEL_CAMINHOS[@]}")
    restauraveis=("${DBX_CMD_NIVEL_RESTAURAVEIS[@]}")
    for indice in "${!tags[@]}"; do
      dbx_cmd_remoto_confinado "${caminhos[indice]}" || continue
      case ${tags[indice]} in
        deleted)
          dbx_cmd_iniciar_saida
          dbx_output_campo tipo apagado
          dbx_cmd_campo_caminho name "${nomes[indice]}"
          dbx_cmd_campo_caminho path_display "${caminhos[indice]}"
          dbx_output_campo restauravel "${restauraveis[indice]}"
          dbx_output_render
          total=$((total + 1))
          ;;
        folder)
          # So descendente estrito da pasta listada, e nunca uma ja vista.
          [[ $recursivo == 'sim' ]] || continue
          dbx_cmd_descendente_estrito "${caminhos[indice]}" "$atual" || continue
          [[ -z ${visitadas[$DBX_CMD_CHAVE]:-} ]] || continue
          visitadas[$DBX_CMD_CHAVE]=1
          fila+=("$DBX_CMD_LIDO")
          ;;
      esac
    done
  done

  dbx_cmd_iniciar_saida
  dbx_output_campo total "$total"
  dbx_output_render
  return 0
}

# _dbx_cmd_lixeira_excluir <alvo> <tem_confirmacao> <confirmacao> <limite> — RF-76.
_dbx_cmd_lixeira_excluir() {
  local argumento=$1 tem_confirmacao=$2 confirmacao=$3 limite=$4 alvo raiz

  _dbx_cmd_caminho_remoto "$argumento" || return $?
  alvo=$DBX_CMD_LIDO
  _dbx_cmd_caminho_remoto "${DBX_CONFIG_RAIZ_REMOTA:-/}" || return $?
  raiz=$DBX_CMD_LIDO
  # A raiz da conta e a propria raiz remota nunca sao alvo (RF-76(b)); a
  # comparacao e sem caixa no ASCII, como o confinamento.
  local LC_ALL=C
  if [[ -z $alvo || ${alvo,,} == "${raiz,,}" ]]; then
    dbx_cmd_falhar uso_invalido "alvo e a raiz: a exclusao permanente nao aceita a raiz da conta nem a raiz remota configurada"
    return $?
  fi

  # Confirmacao ANTES de qualquer chamada, quando ela nao depende do terminal.
  local confirmado='nao'
  if [[ $tem_confirmacao == 'sim' ]]; then
    [[ -n $confirmacao && ($confirmacao == "$argumento" || $confirmacao == "$alvo") ]] || {
      dbx_cmd_falhar uso_invalido \
        "--confirmar-caminho difere do alvo: repita exatamente $alvo; nada foi feito"
      return $?
    }
    confirmado='sim'
  elif [[ ${DBX_CLI_SIMULACAO:-nao} != 'sim' && ! -t 0 ]]; then
    dbx_cmd_falhar uso_invalido \
      "exclusao permanente sem terminal exige --confirmar-caminho $alvo (identico ao alvo); nada foi feito"
    return $?
  fi

  # Guarda pela API, nunca por estado local (DIV-54).
  dbx_json_escapar_cadeia "$alvo"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/get_metadata' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\",\"include_deleted\":true}" sim || {
    dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "consulta do alvo recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  dbx_cmd_ler_corpo_silencioso '.tag' path_lower || {
    dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
    return $?
  }
  local minusculo=${DBX_CMD_CAMPOS[1]}
  # QA-B3-05: campo repetido na resposta e ambiguidade; nenhuma das leituras
  # autoriza o expurgo.
  [[ $DBX_CMD_DUPLICADAS -eq 0 ]] || {
    dbx_cmd_falhar erro_remoto \
      "a resposta da guarda tem campo repetido ($DBX_CMD_DUPLICADAS): ambigua, nada foi expurgado"
    return $?
  }
  [[ ${DBX_CMD_CAMPOS[0]} == 'deleted' ]] || {
    dbx_cmd_falhar uso_invalido \
      "o item existe; apague-o antes com dbx delete $alvo (a exclusao permanente so aceita item ja apagado)"
    return $?
  }
  # QA-B3-02: o DeletedMetadata tem de ser do PROPRIO alvo. `path_lower`
  # presente e igual ao alvo normalizado, os dois dobrados so no ASCII (LC_ALL=C
  # ja vale nesta funcao), como o confinamento da fase 1b. Ausente ou
  # divergente, inclusive por caixa fora do ASCII: resposta que nao se pode
  # atribuir ao alvo, `erro_remoto` (10), sem expurgo.
  if [[ -z $minusculo || ${minusculo,,} != "${alvo,,}" ]]; then
    dbx_cmd_caminho_exibivel "${minusculo:-ausente}"
    dbx_cmd_falhar erro_remoto \
      "a resposta da guarda nao identifica o alvo $alvo (path_lower: $DBX_CMD_EXIBIDO); nada foi expurgado"
    return $?
  fi

  # Pasta apagada: quantos itens apagados ha nela (so leitura; arquivo falha e
  # fica sem contagem).
  local detalhe='' indice apagados=0
  if dbx_cmd_listar_nivel "$alvo" "$limite"; then
    for indice in "${!DBX_CMD_NIVEL_TAGS[@]}"; do
      [[ ${DBX_CMD_NIVEL_TAGS[indice]} == 'deleted' ]] && apagados=$((apagados + 1))
    done
    detalhe=" (pasta com $apagados item(ns) apagado(s) encontrado(s))"
  fi
  dbx_cmd_iniciar_saida
  dbx_output_diagnostico aviso "exclusao PERMANENTE e irreversivel: $alvo nao podera ser restaurado$detalhe"
  dbx_output_render_diagnostico

  if [[ $confirmado != 'sim' && ${DBX_CLI_SIMULACAO:-nao} != 'sim' ]]; then
    local resposta=''
    printf 'Digite o caminho remoto %s para confirmar a exclusao permanente: ' "$alvo" >&2
    IFS= read -r resposta || resposta=''
    [[ -n $resposta && ($resposta == "$alvo" || $resposta == "$argumento") ]] || {
      dbx_cmd_falhar nao_concluida 'caminho digitado difere do alvo: exclusao permanente nao confirmada, nada foi feito'
      return $?
    }
  fi

  local estado
  dbx_json_escapar_cadeia "$alvo"
  _dbx_cmd_escrita_remota 'https://api.dropboxapi.com/2/files/permanently_delete' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\"}" silencioso
  estado=$?
  if [[ $estado -ne 0 ]]; then
    # DIV-57: conta pessoal (400 sem JSON, ou `invalid_account_type`).
    if [[ ${DBX_HTTP_CODIGO:-} == 400 && -z ${DBX_HTTP_RESUMO_DO_SERVICO:-} ]] ||
      [[ ${DBX_HTTP_RESUMO_DE_ERRO:-} == *invalid_account_type* ]]; then
      dbx_cmd_falhar permissao \
        'exclusao permanente so existe em contas Dropbox Business; remedio: use dbx delete (o item fica na lixeira pelo prazo da conta); o item continua na lixeira'
      return $?
    fi
    # DIV-56: escopo opcional ausente.
    if [[ ${DBX_HTTP_RESUMO_DE_ERRO:-} == *missing_scope* ]]; then
      dbx_cmd_falhar autenticacao \
        'escopo files.permanent_delete ausente; remedio: habilite files.permanent_delete no App Console do aplicativo e reautorize com dbx unlink seguido de dbx config; o item continua na lixeira'
      return $?
    fi
    dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO; o item continua na lixeira"
    return $?
  fi

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao excluir_permanente
  dbx_output_campo caminho "$alvo"
  if [[ $DBX_CMD_SIMULADO == 'sim' ]]; then
    dbx_output_campo simulado sim
  else
    _dbx_cmd_encerrar_consulta
    dbx_output_campo resultado expurgado
  fi
  dbx_output_render
  return 0
}
