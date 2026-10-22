#!/usr/bin/env bash
# link_temporario — URL direta de download de um arquivo, valida por 4 horas
# (RF-84, F-15). Nomes: `link-temporario` e o alias `temp-link`.
#
# O LINK E A EXPOSICAO: quem o tiver baixa o arquivo ate ele expirar, e a API
# nao o revoga (RSK-60). Por isso:
#
#   - o caminho passa pelo ponto unico de confinamento antes de qualquer
#     chamada, inclusive a renovacao do token (RNF-20(b), RNF-10(b));
#   - o `--dry-run` NAO gera o link: faz so `get_metadata` (DIV-115);
#   - a resposta e conferida antes de imprimir: `metadata.path_lower` presente,
#     sem chave repetida e dentro da raiz remota; fora disso, `erro_remoto` e o
#     link nao sai em lugar nenhum (falha fechada, DIV-115);
#   - o link vai so para a saida padrao, no campo de resultado; nunca para
#     stderr nem para mensagem de erro.
#
# A API nao devolve a hora de expiracao: `expira_em_estimado` e o relogio local
# mais 4 horas, em UTC, pelo proprio shell (sem `date`). Nada em lib/state, sem
# trava (DIV-63).

dbx_cmd_link_temporario_requisitos() { printf 'credencial'; }

dbx_cmd_link_temporario_executar() {
  # shellcheck source=lib/compartilhamento.sh
  . "$DBX_CLI_RAIZ/lib/compartilhamento.sh"
  local caminho='' posicionais=0
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: ${1%%=*} (o link-temporario so aceita as opcoes globais)"
        return $?
        ;;
      *)
        posicionais=$((posicionais + 1))
        caminho=$1
        ;;
    esac
    shift
  done
  [[ $posicionais -eq 1 ]] || {
    dbx_cmd_falhar uso_invalido "informe exatamente um arquivo remoto ($posicionais argumento(s) posicional(is))"
    return $?
  }

  # RF-84(a), DIV-123: relativo e uso invalido (2); o ponto unico o recusaria com 13.
  [[ $caminho == /* ]] || {
    dbx_cmd_falhar uso_invalido 'informe o caminho remoto absoluto do arquivo (comeca com /)'
    return $?
  }
  local remoto corpo
  _dbx_cmd_caminho_remoto "$caminho" || return $?
  remoto=$DBX_CMD_LIDO
  [[ -n $remoto ]] || {
    dbx_cmd_falhar uso_invalido 'link temporario existe so para arquivo; para pasta use dbx compartilhar'
    return $?
  }
  dbx_compartilhamento_corpo_simples corpo path "$remoto"

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    _dbx_cmd_link_temporario_simular "$remoto" "$corpo"
    return $?
  fi

  dbx_auth_requisitar POST 'https://api.dropboxapi.com/2/files/get_temporary_link' "$corpo" sim || {
    _dbx_cmd_link_temporario_recusa
    return $?
  }

  # Conferencia do resultado, sem emitir nada antes dela (DIV-115).
  local link='' minusculo='' duplicadas=0
  dbx_json_contexto link_temporario || {
    dbx_cmd_falhar erro_remoto 'contexto de analise indisponivel'
    return $?
  }
  if dbx_json_analisar "$DBX_HTTP_CORPO" 2>/dev/null; then
    duplicadas=$DBX_JSON_DUPLICADAS
    dbx_json_valor link >/dev/null 2>&1 && link=$DBX_JSON_RESULTADO
    dbx_json_valor metadata path_lower >/dev/null 2>&1 && minusculo=$DBX_JSON_RESULTADO
  else
    duplicadas=-1
  fi
  DBX_JSON_RESULTADO=''
  # QA-B5-06, QA-B5-15: link com espaco, byte de controle (ou que nao e https) e resposta
  # malformada: 10, sem imprimir.
  # QA-B5-18: so ASCII imprimivel (`^[!-~]+$`, sob LC_ALL=C).
  local ascii='nao'
  _dbx_cmd_link_temporario_ascii "$link" && ascii='sim'
  if [[ $duplicadas -ne 0 || -z $link || $ascii != 'sim' || $link != https://* || $link == *[[:space:]]* ||
    $link == *[$'\001'-$'\037\177']* ]] ||
    ! dbx_compartilhamento_confinado "$minusculo" "${DBX_CONFIG_RAIZ_REMOTA:-/}"; then
    link=''
    dbx_json_descartar link_temporario
    dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
    DBX_HTTP_CORPO=''
    dbx_cmd_falhar erro_remoto \
      'a resposta do servico nao identifica um arquivo dentro da raiz remota (metadata.path_lower ausente, repetido ou fora): o link nao foi exibido'
    return $?
  fi

  local agora estimado
  dbx_compartilhamento_agora
  agora=$DBX_COMPARTILHAMENTO_AGORA
  dbx_compartilhamento_carimbo $((agora + DBX_COMPARTILHAMENTO_VALIDADE_TEMPORARIO))
  estimado=$DBX_COMPARTILHAMENTO_CARIMBO

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao link_temporario
  _dbx_cmd_campo metadata path_display && dbx_cmd_campo_caminho caminho "$DBX_CMD_LIDO"
  dbx_output_campo link "$link"
  dbx_output_campo validade_segundos "$DBX_COMPARTILHAMENTO_VALIDADE_TEMPORARIO"
  dbx_output_campo expira_em_estimado "$estimado"
  _dbx_cmd_metadado_em metadata
  dbx_json_descartar link_temporario
  dbx_json_contexto "$DBX_JSON_CONTEXTO_ANTERIOR"
  DBX_HTTP_CORPO=''
  dbx_output_render
  link=''

  if [[ -t 2 ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso \
      "qualquer pessoa com este link baixa o arquivo ate $estimado (estimado); o link temporario nao pode ser revogado"
    dbx_output_render_diagnostico >&2
  fi
  return 0
}

# _dbx_cmd_link_temporario_ascii <texto> — 0 so com ASCII imprimivel.
_dbx_cmd_link_temporario_ascii() {
  local LC_ALL=C
  [[ ${1-} =~ ^[!-~]+$ ]]
}

# _dbx_cmd_link_temporario_simular <remoto> <corpo> — RF-84(g): so o tipo.
_dbx_cmd_link_temporario_simular() {
  local remoto=$1 corpo=$2 tag
  _dbx_cmd_consultar 'https://api.dropboxapi.com/2/files/get_metadata' "$corpo" || return $?
  _dbx_cmd_campo '.tag' || DBX_CMD_LIDO=''
  tag=$DBX_CMD_LIDO
  if [[ $tag != 'file' ]]; then
    _dbx_cmd_encerrar_consulta
    dbx_cmd_falhar uso_invalido 'link temporario existe so para arquivo; para pasta use dbx compartilhar'
    return $?
  fi
  dbx_cmd_iniciar_saida
  dbx_output_campo operacao link_temporario
  dbx_cmd_campo_caminho caminho "$remoto"
  dbx_output_campo simulado sim
  _dbx_cmd_metadado_em
  _dbx_cmd_encerrar_consulta
  dbx_output_render
  return 0
}

# _dbx_cmd_link_temporario_recusa — RF-84(d)(h): traduz a recusa do servico.
_dbx_cmd_link_temporario_recusa() {
  local resumo=${DBX_HTTP_RESUMO_DE_ERRO:-}
  case $resumo in
    path/not_file* | not_file*)
      dbx_cmd_falhar uso_invalido 'link temporario existe so para arquivo; para pasta use dbx compartilhar'
      ;;
    unsupported_file*)
      dbx_cmd_falhar uso_invalido 'este tipo de arquivo nao tem link temporario (exige exportacao, fora do escopo)'
      ;;
    *)
      dbx_cmd_falhar "${DBX_HTTP_CLASSE:-erro_remoto}" \
        "link temporario recusado: ${resumo:-codigo ${DBX_HTTP_CODIGO:-0}}"
      ;;
  esac
}
