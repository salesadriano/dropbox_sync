#!/usr/bin/env bash
# restaurar — restaura uma revisao de arquivo, inclusive de arquivo apagado
# (RF-73), ou uma pasta apagada, arquivo por arquivo (RF-74). Alias: `restore`.
#
# ARQUIVO (RF-73)
#
#   `get_metadata` com `include_deleted` diz se o caminho e arquivo vivo, item
#   apagado ou pasta. A revisao sai de `list_revisions` DO PROPRIO CAMINHO
#   (DIV-59): a API restaura qualquer `rev` em qualquer caminho, e aceitar um
#   `rev` que nao esta no historico gravaria o conteudo de outro arquivo. Por
#   isso `--rev` e procurado pagina a pagina (`before_rev`) e, ausente, nao ha
#   `restore`. `--antes-de` escolhe a revisao mais recente cujo
#   `server_modified` nao e posterior a data (DIV-60), por comparacao textual do
#   carimbo UTC, sem utilitario de data. Sem selecao: arquivo apagado volta na
#   ultima revisao; arquivo vivo recusa (DIV-61). O `rev` vigente vira
#   `ja_atual`, sem `restore` (DIV-66). Restaurar sobre arquivo vivo e direto
#   (decisao do solicitante): a saida traz `rev_substituida` e o comando que
#   desfaz.
#
# PASTA APAGADA (RF-74)
#
#   Descida um nivel por vez (`dbx_cmd_listar_nivel`), entrando em toda subpasta
#   viva ou apagada; item vivo nao e tocado. Cada item apagado e sondado com
#   `list_revisions(limit=1)`: `not_file` e subpasta apagada (DIV-65), revisao
#   encontrada e o item a restaurar. Os itens seguem a ordem da chave sem caixa
#   do `verificar`. Falha de item ou travessia parcial nao interrompe: entra no
#   resumo e o codigo e `nao_concluida` (14). Rodar de novo restaura so o que
#   ainda esta apagado. Sinal encerra com 14 e resumo parcial em stderr, pela
#   acao registrada em `lib/tmp`.
#
# Nao trava (DIV-63) e nao le nem grava `lib/state`.

dbx_cmd_restaurar_requisitos() { printf 'credencial'; }

readonly DBX_RESTAURAR_PAGINA=100

# Pagina corrente de `list_revisions`.
DBX_RESTAURAR_REVS=() DBX_RESTAURAR_MODIFICADOS=()
DBX_RESTAURAR_APAGADO_EM='' DBX_RESTAURAR_MAIS='nao'

# _dbx_cmd_restaurar_revisoes <caminho_api> <limite> [before_rev] — uma pagina
# de `list_revisions` (modo `path`), sem emitir nada. Falha: status da classe,
# com DBX_CMD_FALHA_CLASSE e DBX_CMD_FALHA_MOTIVO; o resumo do servico fica em
# DBX_HTTP_RESUMO_DE_ERRO.
_dbx_cmd_restaurar_revisoes() {
  local caminho=$1 limite=$2 antes=${3:-} corpo quantidade indice
  DBX_RESTAURAR_REVS=() DBX_RESTAURAR_MODIFICADOS=()
  DBX_RESTAURAR_APAGADO_EM='' DBX_RESTAURAR_MAIS='nao'
  DBX_CMD_FALHA_CLASSE='' DBX_CMD_FALHA_MOTIVO=''
  dbx_json_escapar_cadeia "$caminho"
  corpo="{\"path\":\"$DBX_JSON_ESCAPADO\",\"mode\":\"path\",\"limit\":$limite"
  if [[ -n $antes ]]; then
    dbx_json_escapar_cadeia "$antes"
    corpo+=",\"before_rev\":\"$DBX_JSON_ESCAPADO\""
  fi
  corpo+='}'
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/list_revisions' "$corpo" sim || {
    if dbx_auth_falha_e_do_token; then
      dbx_auth_falhar_com dbx_cmd_falha_registrar
      return "$(dbx_errors_codigo_saida "$DBX_CMD_FALHA_CLASSE")"
    fi
    DBX_CMD_FALHA_CLASSE=${DBX_HTTP_CLASSE:-erro_remoto}
    dbx_errors_classe_valida "$DBX_CMD_FALHA_CLASSE" || DBX_CMD_FALHA_CLASSE='erro_remoto'
    DBX_CMD_FALHA_MOTIVO="consulta de revisoes recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return "$(dbx_errors_codigo_saida "$DBX_CMD_FALHA_CLASSE")"
  }
  dbx_json_contexto revisoes_restaurar || return "$(dbx_errors_codigo_saida erro_remoto)"
  if ! dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null; then
    DBX_CMD_FALHA_CLASSE='erro_remoto'
    DBX_CMD_FALHA_MOTIVO="resposta nao interpretavel: ${DBX_JSON_MOTIVO:-sem detalhe}"
    dbx_json_descartar revisoes_restaurar
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    return "$(dbx_errors_codigo_saida erro_remoto)"
  fi
  quantidade=$(dbx_json_tamanho_arranjo entries) || quantidade=0
  for ((indice = 0; indice < quantidade; indice++)); do
    DBX_RESTAURAR_REVS+=('') DBX_RESTAURAR_MODIFICADOS+=('')
    dbx_json_valor entries "$indice" rev >/dev/null 2>&1 && DBX_RESTAURAR_REVS[indice]=$DBX_JSON_RESULTADO
    dbx_json_valor entries "$indice" server_modified >/dev/null 2>&1 &&
      DBX_RESTAURAR_MODIFICADOS[indice]=$DBX_JSON_RESULTADO
  done
  dbx_json_valor server_deleted >/dev/null 2>&1 && DBX_RESTAURAR_APAGADO_EM=$DBX_JSON_RESULTADO
  dbx_json_valor has_more >/dev/null 2>&1 && [[ $DBX_JSON_RESULTADO == 'true' ]] && DBX_RESTAURAR_MAIS='sim'
  dbx_json_descartar revisoes_restaurar
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  # shellcheck disable=SC2034  # canais publicos alheios, limpos aqui
  DBX_JSON_RESULTADO='' DBX_HTTP_CORPO=''
  return 0
}

# _dbx_cmd_restaurar_data <valor> — `AAAA-MM-DD` (fim do dia UTC, inclusivo) ou
# `AAAA-MM-DDTHH:MM:SSZ`; o carimbo normalizado vai em DBX_CMD_LIDO. Data
# inexistente, outro fuso ou outra forma: status 1 (DIV-60).
_dbx_cmd_restaurar_data() {
  local valor=${1-} ano mes dia hora=23 minuto=59 segundo=59 ultimo
  if [[ $valor =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    :
  elif [[ $valor =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$ ]]; then
    hora=$((10#${BASH_REMATCH[4]})) minuto=$((10#${BASH_REMATCH[5]})) segundo=$((10#${BASH_REMATCH[6]}))
  else
    return 1
  fi
  ano=$((10#${BASH_REMATCH[1]})) mes=$((10#${BASH_REMATCH[2]})) dia=$((10#${BASH_REMATCH[3]}))
  ((mes >= 1 && mes <= 12 && hora <= 23 && minuto <= 59 && segundo <= 59)) || return 1
  case $mes in
    4 | 6 | 9 | 11) ultimo=30 ;;
    2)
      ultimo=28
      ((ano % 4 == 0 && (ano % 100 != 0 || ano % 400 == 0))) && ultimo=29
      ;;
    *) ultimo=31 ;;
  esac
  ((dia >= 1 && dia <= ultimo)) || return 1
  printf -v DBX_CMD_LIDO '%s-%s-%sT%02d:%02d:%02dZ' "${valor:0:4}" "${valor:5:2}" "${valor:8:2}" \
    "$hora" "$minuto" "$segundo"
  return 0
}

# _dbx_cmd_restaurar_ate <a> <b> — 0 quando o carimbo <a> nao e posterior a <b>.
_dbx_cmd_restaurar_ate() {
  local LC_ALL=C
  [[ -n $1 && ($1 < $2 || $1 == "$2") ]]
}

# Progresso da restauracao de pasta, lido pela acao de sinal: os itens na ordem
# de restauracao e a posicao do proximo.
DBX_RESTAURAR_FEITOS=0 DBX_RESTAURAR_FALHAS=0 DBX_RESTAURAR_TOTAL=0 DBX_RESTAURAR_POSICAO=0
DBX_RESTAURAR_FILA=()

# _dbx_cmd_restaurar_parcial — acao registrada em lib/tmp: no sinal, o resumo do
# que ja voltou e do que faltou, em stderr (RF-74(j)).
_dbx_cmd_restaurar_parcial() {
  local restantes='' indice
  for ((indice = DBX_RESTAURAR_POSICAO; indice < ${#DBX_RESTAURAR_FILA[@]}; indice++)); do
    dbx_cmd_caminho_exibivel "${DBX_RESTAURAR_FILA[indice]}"
    restantes+="${restantes:+, }$DBX_CMD_EXIBIDO"
  done
  dbx_cmd_iniciar_saida
  dbx_output_diagnostico aviso \
    "restauracao interrompida: restaurados=$DBX_RESTAURAR_FEITOS falhas=$DBX_RESTAURAR_FALHAS total=$DBX_RESTAURAR_TOTAL; faltaram: ${restantes:-nenhum}"
  dbx_output_render_diagnostico
}

dbx_cmd_restaurar_executar() {
  local caminho='' rev='' antes='' tem_rev='nao' tem_antes='nao' limite_data=''
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --rev)
        shift
        rev=${1-} tem_rev='sim'
        ;;
      --antes-de | --before)
        shift
        antes=${1-} tem_antes='sim'
        ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        [[ -z $caminho ]] || {
          dbx_cmd_falhar uso_invalido 'informe apenas um caminho'
          return $?
        }
        caminho=$1
        ;;
    esac
    shift
  done

  [[ $tem_rev == 'sim' && $tem_antes == 'sim' ]] && {
    dbx_cmd_falhar uso_invalido '--rev e --antes-de (--before) sao mutuamente exclusivos'
    return $?
  }
  if [[ $tem_rev == 'sim' && ! $rev =~ ^[0-9a-f]{9,}$ ]]; then
    dbx_cmd_caminho_exibivel "$rev"
    dbx_cmd_falhar uso_invalido \
      "valor invalido para --rev: [$DBX_CMD_EXIBIDO]; use o rev da revisao (hexadecimal minusculo, 9 ou mais caracteres; veja dbx revisoes)"
    return $?
  fi
  if [[ $tem_antes == 'sim' ]]; then
    _dbx_cmd_restaurar_data "$antes" || {
      dbx_cmd_caminho_exibivel "$antes"
      dbx_cmd_falhar uso_invalido \
        "valor invalido para --antes-de: [$DBX_CMD_EXIBIDO]; use AAAA-MM-DD ou AAAA-MM-DDTHH:MM:SSZ (UTC)"
      return $?
    }
    limite_data=$DBX_CMD_LIDO
  fi
  [[ -n $caminho ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto do arquivo ou da pasta apagada'
    return $?
  }

  local remoto
  _dbx_cmd_caminho_remoto "$caminho" || return $?
  remoto=$DBX_CMD_LIDO
  [[ -n $remoto ]] || {
    dbx_cmd_falhar uso_invalido 'a raiz da conta nao e alvo de restauracao'
    return $?
  }

  # Arquivo vivo, item apagado ou pasta: a API responde, e nao memoria local.
  dbx_json_escapar_cadeia "$remoto"
  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/get_metadata' \
    "{\"path\":\"$DBX_JSON_ESCAPADO\",\"include_deleted\":true}" sim || {
    if dbx_auth_falha_e_do_token; then
      dbx_auth_falhar_com dbx_cmd_falhar
      return $?
    fi
    dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
      "consulta do caminho recusada: ${DBX_HTTP_RESUMO_DE_ERRO:-codigo ${DBX_HTTP_CODIGO:-0}}"
    return $?
  }
  dbx_cmd_ler_corpo_silencioso '.tag' || {
    dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
    return $?
  }
  local situacao=${DBX_CMD_CAMPOS[0]}
  case $situacao in
    file | deleted) ;;
    folder)
      dbx_cmd_falhar uso_invalido \
        "a pasta existe: restaurar recupera arquivo (vivo ou apagado) ou pasta apagada; para um arquivo dentro dela use dbx restaurar <arquivo>"
      return $?
      ;;
    *)
      dbx_cmd_falhar erro_remoto "tipo de item nao reconhecido na resposta: ${situacao:-ausente}"
      return $?
      ;;
  esac

  _dbx_cmd_restaurar_revisoes "$remoto" "$DBX_RESTAURAR_PAGINA"
  local estado=$?
  if [[ $estado -ne 0 ]]; then
    case ${DBX_HTTP_RESUMO_DE_ERRO:-} in
      *not_file*)
        [[ $situacao == 'deleted' ]] && {
          _dbx_cmd_restaurar_pasta "$remoto" "$tem_rev" "$tem_antes"
          return $?
        }
        ;;
    esac
    dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
    return $?
  fi

  local vigente='' escolhida='' indice anterior=''
  [[ $situacao == 'file' ]] && vigente=${DBX_RESTAURAR_REVS[0]:-}
  if [[ $tem_rev == 'sim' || $tem_antes == 'sim' ]]; then
    while :; do
      for indice in "${!DBX_RESTAURAR_REVS[@]}"; do
        if [[ $tem_rev == 'sim' && ${DBX_RESTAURAR_REVS[indice]} == "$rev" ]] ||
          { [[ $tem_antes == 'sim' ]] &&
            _dbx_cmd_restaurar_ate "${DBX_RESTAURAR_MODIFICADOS[indice]}" "$limite_data"; }; then
          escolhida=${DBX_RESTAURAR_REVS[indice]}
          break 2
        fi
      done
      [[ $DBX_RESTAURAR_MAIS == 'sim' && ${#DBX_RESTAURAR_REVS[@]} -gt 0 ]] || break
      local ultima=${DBX_RESTAURAR_REVS[${#DBX_RESTAURAR_REVS[@]} - 1]}
      [[ -n $ultima && $ultima != "$anterior" ]] || break
      anterior=$ultima
      _dbx_cmd_restaurar_revisoes "$remoto" "$DBX_RESTAURAR_PAGINA" "$ultima" || {
        dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
        return $?
      }
    done
    if [[ -z $escolhida ]]; then
      if [[ $tem_rev == 'sim' ]]; then
        # QA-B3-01: rev alheio ao caminho e erro de uso, nao item inexistente.
        dbx_cmd_falhar uso_invalido "revisao $rev nao pertence a $remoto (ausente do historico do caminho)"
      else
        dbx_cmd_falhar nao_encontrado "nenhuma revisao ate $antes em $remoto"
      fi
      return $?
    fi
  elif [[ $situacao == 'file' ]]; then
    dbx_cmd_falhar uso_invalido \
      "o arquivo existe: informe --rev ou --antes-de (veja dbx revisoes $remoto)"
    return $?
  else
    escolhida=${DBX_RESTAURAR_REVS[0]:-}
    [[ -n $escolhida ]] || {
      dbx_cmd_falhar nao_encontrado "nenhuma revisao restauravel de $remoto"
      return $?
    }
  fi

  local estava_apagado='nao'
  [[ $situacao == 'deleted' ]] && estava_apagado='sim'
  if [[ -n $vigente && $escolhida == "$vigente" ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao restaurar
    dbx_cmd_campo_caminho caminho "$remoto"
    dbx_output_campo rev_escolhida "$escolhida"
    dbx_output_campo rev_substituida "$vigente"
    dbx_output_campo estava_apagado "$estava_apagado"
    dbx_output_campo situacao ja_atual
    dbx_output_render
    return 0
  fi

  dbx_json_escapar_cadeia "$remoto"
  local corpo="{\"path\":\"$DBX_JSON_ESCAPADO\""
  dbx_json_escapar_cadeia "$escolhida"
  corpo+=",\"rev\":\"$DBX_JSON_ESCAPADO\"}"
  _dbx_cmd_escrita_remota 'https://api.dropboxapi.com/2/files/restore' "$corpo" || return $?

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao restaurar
  dbx_cmd_campo_caminho caminho "$remoto"
  dbx_output_campo rev_escolhida "$escolhida"
  dbx_output_campo rev_substituida "$vigente"
  dbx_output_campo estava_apagado "$estava_apagado"
  if [[ $DBX_CMD_SIMULADO == 'sim' ]]; then
    dbx_output_campo simulado sim
  else
    _dbx_cmd_metadado_em
    _dbx_cmd_encerrar_consulta
  fi
  if [[ -n $vigente ]]; then
    dbx_cmd_caminho_exibivel "$remoto"
    dbx_output_campo para_desfazer "dbx restaurar $DBX_CMD_EXIBIDO --rev $vigente"
  fi
  dbx_output_render
  return 0
}

# _dbx_cmd_restaurar_pasta <caminho_api> <tem_rev> <tem_antes> — RF-74.
_dbx_cmd_restaurar_pasta() {
  local raiz=$1
  [[ $2 == 'sim' || $3 == 'sim' ]] && {
    dbx_cmd_falhar uso_invalido \
      "$raiz e pasta apagada: pasta nao tem revisao; --rev e --antes-de valem so para arquivo"
    return $?
  }

  local -a fila=("$raiz") itens=() revs=() datas=() falhas=() nao_percorridas=()
  local -a tags caminhos restauraveis
  local -A vistos=()
  local pasta indice item sem_revisao=0 total=0
  # QA-B3-06: cada pasta (e cada item) e visitado uma vez, chave sem caixa ASCII.
  dbx_cmd_chave_ascii "$raiz"
  vistos[$DBX_CMD_CHAVE]=1
  while [[ ${#fila[@]} -gt 0 ]]; do
    pasta=${fila[0]}
    fila=("${fila[@]:1}")
    if ! dbx_cmd_listar_nivel "$pasta" "$DBX_RESTAURAR_PAGINA"; then
      if [[ $pasta == "$raiz" ]]; then
        dbx_cmd_falhar "$DBX_CMD_FALHA_CLASSE" "$DBX_CMD_FALHA_MOTIVO"
        return $?
      fi
      dbx_cmd_caminho_exibivel "$pasta"
      nao_percorridas+=("$DBX_CMD_EXIBIDO: $DBX_CMD_FALHA_CLASSE")
      continue
    fi
    tags=("${DBX_CMD_NIVEL_TAGS[@]}")
    caminhos=("${DBX_CMD_NIVEL_CAMINHOS[@]}")
    restauraveis=("${DBX_CMD_NIVEL_RESTAURAVEIS[@]}")
    for indice in "${!tags[@]}"; do
      item=${caminhos[indice]}
      [[ -n $item && ${tags[indice]} != 'file' ]] || continue
      # DIV-78: dentro da raiz remota E da pasta pedida, por componente.
      if ! dbx_cmd_remoto_confinado "$item" || ! dbx_cmd_remoto_confinado "$item" "$raiz"; then
        dbx_cmd_caminho_exibivel "$item"
        falhas+=("$DBX_CMD_EXIBIDO: caminho_recusado (fora da raiz remota)")
        total=$((total + 1))
        continue
      fi
      # Descendente estrito da pasta listada (a propria pasta ou um ancestral
      # prenderiam a descida) e nunca um ja visto: ignorado.
      dbx_cmd_descendente_estrito "$item" "$pasta" || continue
      [[ -z ${vistos[$DBX_CMD_CHAVE]:-} ]] || continue
      vistos[$DBX_CMD_CHAVE]=1
      item=$DBX_CMD_LIDO
      if [[ ${tags[indice]} == 'folder' ]]; then
        fila+=("$item")
        continue
      fi
      [[ ${tags[indice]} == 'deleted' ]] || continue
      if ! _dbx_cmd_restaurar_revisoes "$item" 1; then
        if [[ ${DBX_HTTP_RESUMO_DE_ERRO:-} == *not_file* ]]; then
          fila+=("$item")
        else
          dbx_cmd_caminho_exibivel "$item"
          falhas+=("$DBX_CMD_EXIBIDO: $DBX_CMD_FALHA_CLASSE")
          total=$((total + 1))
        fi
        continue
      fi
      total=$((total + 1))
      if [[ ${#DBX_RESTAURAR_REVS[@]} -eq 0 || -z ${DBX_RESTAURAR_REVS[0]} || ${restauraveis[indice]} == 'nao' ]]; then
        dbx_cmd_caminho_exibivel "$item"
        falhas+=("$DBX_CMD_EXIBIDO: sem_revisao")
        sem_revisao=$((sem_revisao + 1))
        continue
      fi
      itens+=("$item") revs+=("${DBX_RESTAURAR_REVS[0]}") datas+=("$DBX_RESTAURAR_APAGADO_EM")
    done
  done

  # shellcheck source=lib/sync.sh
  . "$DBX_CLI_RAIZ/lib/sync.sh"
  dbx_sync_ordem_sem_caixa itens
  local -a ordem=("${DBX_SYNC_ORDEM[@]}")

  DBX_RESTAURAR_FEITOS=0 DBX_RESTAURAR_FALHAS=${#falhas[@]} DBX_RESTAURAR_TOTAL=$total
  DBX_RESTAURAR_POSICAO=0 DBX_RESTAURAR_FILA=()
  for indice in "${ordem[@]}"; do
    DBX_RESTAURAR_FILA+=("${itens[indice]}")
  done
  local acao=''
  dbx_tmp_acao_registrar _dbx_cmd_restaurar_parcial && acao=$DBX_TMP_ID

  local restaurados=0 simulado='nao' corpo resultado motivo
  for indice in "${ordem[@]}"; do
    item=${itens[indice]}
    dbx_json_escapar_cadeia "$item"
    corpo="{\"path\":\"$DBX_JSON_ESCAPADO\""
    dbx_json_escapar_cadeia "${revs[indice]}"
    corpo+=",\"rev\":\"$DBX_JSON_ESCAPADO\"}"
    motivo=''
    if _dbx_cmd_escrita_remota 'https://api.dropboxapi.com/2/files/restore' "$corpo" silencioso; then
      if [[ $DBX_CMD_SIMULADO == 'sim' ]]; then
        resultado='simulado' simulado='sim'
      else
        _dbx_cmd_encerrar_consulta
        resultado='restaurado'
        restaurados=$((restaurados + 1))
      fi
    else
      resultado='falha' motivo=$DBX_CMD_FALHA_CLASSE
      dbx_cmd_caminho_exibivel "$item"
      falhas+=("$DBX_CMD_EXIBIDO: $motivo")
    fi
    DBX_RESTAURAR_FEITOS=$restaurados DBX_RESTAURAR_FALHAS=${#falhas[@]}
    DBX_RESTAURAR_POSICAO=$((DBX_RESTAURAR_POSICAO + 1))
    dbx_cmd_iniciar_saida
    dbx_cmd_campo_caminho item "$item"
    dbx_output_campo rev "${revs[indice]}"
    dbx_output_campo apagado_em "${datas[indice]}"
    dbx_output_campo resultado "$resultado"
    [[ -n $motivo ]] && dbx_output_campo motivo "$motivo"
    dbx_output_render
  done
  [[ -n $acao ]] && dbx_tmp_acao_cancelar "$acao"
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && simulado='sim'

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao restaurar_pasta
  dbx_cmd_campo_caminho caminho "$raiz"
  [[ $simulado == 'sim' ]] && dbx_output_campo simulado sim
  [[ $total -eq 0 && ${#nao_percorridas[@]} -eq 0 ]] && dbx_output_campo situacao nada_a_restaurar
  dbx_output_campo restaurados "$restaurados"
  dbx_output_campo falhas "${#falhas[@]}"
  dbx_output_campo sem_revisao "$sem_revisao"
  dbx_output_campo total "$total"
  for item in ${falhas[@]+"${falhas[@]}"}; do
    dbx_output_campo falha "$item"
  done
  for item in ${nao_percorridas[@]+"${nao_percorridas[@]}"}; do
    dbx_output_campo pasta_nao_percorrida "$item"
  done
  dbx_output_render

  [[ $simulado == 'sim' ]] && return 0
  if [[ ${#falhas[@]} -gt 0 || ${#nao_percorridas[@]} -gt 0 ]]; then
    dbx_cmd_falhar nao_concluida \
      "restauracao incompleta: ${#falhas[@]} item(ns) com falha, ${#nao_percorridas[@]} pasta(s) nao percorrida(s); rode de novo para restaurar so o que falta"
    return $?
  fi
  return 0
}
