#!/usr/bin/env bash
# unlink — desvinculo desta instalacao (RF-04, RF-06a, RF-51, RES-12).
#
# O COMANDO TRATA O ESTADO LOCAL, E NAO SO O TOKEN REMOTO
#
#   Revogar e a parte visivel; RF-51 existe porque a parte invisivel e maior. A
#   revogacao deixa DOIS artefatos orfaos no disco: a credencial gravada, que
#   fica inutil mas continua contendo `app key` e `app secret`, e a linha de base
#   do `sync`, que continua descrevendo um pareamento que nao existe mais. O
#   segundo e perigoso: religar a outra conta com base antiga preservada leva o
#   `sync` a interpretar arquivo local como "apagado do outro lado" e a apaga-lo
#   (RF-52). Por isso o desvinculo invalida as bases, e nao so o token.
#
# POR QUE DECLARA `ambiente` E NAO `credencial`
#
#   Porque uma das suas funcoes e remover credencial QUEBRADA. O nivel
#   `credencial` recusa a execucao quando a credencial esta em permissao larga ou
#   nao carrega — que e precisamente o estado em que o operador mais precisa
#   deste comando. `config` tem o mesmo motivo pela porta oposta: um grava, o
#   outro remove, e nenhum dos dois pode depender do que esta consertando.
#
# O QUE ACONTECE QUANDO A REVOGACAO FALHA
#
#   A limpeza local acontece assim mesmo, e o comando NAO sai com zero. Sair com
#   zero diria "desvinculado" a quem ficou com um refresh token vivo do lado da
#   Dropbox; nao limpar diria "nada feito" a quem pediu o desvinculo e ficou com
#   o segredo em disco. As duas coisas sao ditas: a limpeza no registro de
#   resultado, a revogacao pendente no codigo de saida e no diagnostico.
#
# LIMITE DECLARADO SOBRE AS BASES
#
#   `lib/state` ainda nao existe, entao o formato da linha de base nao existe e
#   este comando NAO pode listar as raizes afetadas, como RF-51(d) pede — nomear
#   raiz exigiria ler um formato que ninguem definiu, e inventa-lo aqui fixaria
#   contrato pelo lado errado. O que ele faz e o que da para fazer com verdade:
#   remove o diretorio de estado que DP-23 fixou e NOMEIA AS ENTRADAS removidas.
#   Quando `lib/state` definir o formato, a nomeacao passa de entrada para raiz
#   sem que o resto mude.

dbx_cmd_unlink_requisitos() { printf 'ambiente'; }

# _dbx_cmd_unlink_remover_estado — apaga o diretorio de estado e publica o que
# removeu em DBX_CMD_UNLINK_BASES.
#
# REMOCAO RECURSIVA E ONDE UM DEFEITO DESTROI DADO DO OPERADOR, entao o caminho
# passa por tres guardas antes do `rm`, e nenhuma delas confia na anterior:
#
#   - absoluto e terminando em `/dbx`, para que erro de composicao nao aponte
#     para a raiz do XDG nem para o diretorio pessoal inteiro;
#   - diretorio de verdade;
#   - NAO ligacao simbolica — apagar a ligacao deixaria o alvo intacto e
#     reportaria remocao que nao houve, e apagar atraves dela alcancaria arvore
#     que nao e nossa.
_dbx_cmd_unlink_remover_estado() {
  local estado entrada
  DBX_CMD_UNLINK_BASES=()

  dbx_config_caminho_de_estado || return 0
  estado=$DBX_CONFIG_RESULTADO

  [[ $estado == /*/dbx ]] || return 0
  [[ -L $estado ]] && return 0
  [[ -d $estado ]] || return 0

  for entrada in "$estado"/* "$estado"/.[!.]*; do
    [[ -e $entrada ]] || continue
    DBX_CMD_UNLINK_BASES+=("${entrada##*/}")
  done

  rm -rf -- "$estado" 2>/dev/null || return 1
  return 0
}

dbx_cmd_unlink_executar() {
  dbx_carregar_camada_de_credencial

  local confirmado='nao' modo='integral'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --confirmar) confirmado='sim' ;;
      --manter-aplicativo) modo='aplicativo' ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        dbx_cmd_falhar uso_invalido "argumento inesperado: $1"
        return $?
        ;;
    esac
    shift
  done

  dbx_config_caminho || {
    dbx_cmd_falhar configuracao \
      "nao foi possivel determinar o caminho da credencial: $DBX_CONFIG_MOTIVO"
    return $?
  }
  local arquivo=$DBX_CONFIG_RESULTADO

  # ADVERTENCIA DE CASCATA (RF-06a, RES-12). Ela e dita ANTES da confirmacao, e
  # nao depois: advertencia que chega depois da decisao nao e advertencia.
  {
    printf 'Desvincular revoga o refresh token desta instalacao.\n'
    printf 'A revogacao e em cascata: invalida tambem todos os access tokens\n'
    printf 'derivados dele, inclusive os de outras maquinas e de execucoes em\n'
    printf 'curso. Nao ha desfazer — religar exige autorizar de novo.\n'
  } >&2

  # RF-06a exige confirmacao no modo interativo e sinalizador explicito no modo
  # automatizado. O criterio e o TERMINAL, e nao uma suposicao sobre quem chama.
  if [[ $confirmado != 'sim' ]]; then
    if [[ ! -t 0 ]]; then
      dbx_cmd_falhar uso_invalido \
        'desvinculo sem terminal exige o sinalizador explicito --confirmar'
      return $?
    fi
    local resposta=''
    printf "Digite 'revogar' para confirmar: " >&2
    IFS= read -r resposta
    [[ $resposta == 'revogar' ]] || {
      dbx_cmd_falhar nao_concluida 'desvinculo nao confirmado'
      return $?
    }
  fi

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao unlink
    dbx_output_campo credencial "$arquivo"
    dbx_output_campo modo "$modo"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  # A ordem importa: revogar exige a credencial que a limpeza vai apagar.
  local havia='nao' revogacao='nao_emitida' classe_remota='' carregou='nao'
  [[ -e $arquivo ]] && havia='sim'
  if [[ $havia == 'sim' ]] && dbx_config_carregar 2>/dev/null; then
    carregou='sim'
    if dbx_auth_revogar; then
      revogacao='emitida'
    else
      revogacao='falhou'
      classe_remota=${DBX_HTTP_CLASSE:-erro_remoto}
    fi
  fi

  # `--manter-aplicativo` so tem o que preservar se a credencial carregou. Sem
  # ela, preservar significaria escrever `app key` inventada; o comando recua
  # para a remocao integral e DIZ que recuou, em vez de falhar num pedido que
  # perdeu o objeto.
  if [[ $modo == 'aplicativo' && $carregou != 'sim' ]]; then
    modo='integral'
    printf 'aviso: credencial ilegivel; --manter-aplicativo nao se aplica e a remocao sera integral\n' >&2
  fi

  local remocao='concluida'
  dbx_config_remover "$modo" || remocao='falhou'

  local bases='concluida'
  # shellcheck disable=SC2034  # canal publico preenchido pelo auxiliar
  DBX_CMD_UNLINK_BASES=()
  _dbx_cmd_unlink_remover_estado || bases='falhou'

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao unlink
  dbx_output_campo revogacao "$revogacao"
  dbx_output_campo credencial "$remocao"
  dbx_output_campo modo "$modo"
  dbx_output_campo bases "$bases"
  local base
  for base in ${DBX_CMD_UNLINK_BASES[@]+"${DBX_CMD_UNLINK_BASES[@]}"}; do
    dbx_output_campo base_removida "$base"
  done
  dbx_output_render

  # CODIGO DE SAIDA — cada caso diz uma coisa diferente ao operador.
  if [[ $remocao == 'falhou' || $bases == 'falhou' ]]; then
    dbx_cmd_falhar permissao \
      'o desvinculo nao conseguiu remover o estado local; verifique permissoes'
    return $?
  fi
  if [[ $revogacao == 'falhou' ]]; then
    dbx_cmd_falhar "$classe_remota" \
      'estado local removido, mas a revogacao remota falhou: o refresh token pode continuar valido na Dropbox'
    return $?
  fi
  if [[ $havia == 'sim' && $carregou != 'sim' ]]; then
    dbx_cmd_falhar nao_concluida \
      'a credencial existia e nao pode ser lida: foi removida sem que a revogacao fosse emitida, e o token pode continuar valido na Dropbox'
    return $?
  fi
  return 0
}
