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
#
# TRAVA NAO VIVA FICA (RF-69(h2), RF-51(f) emendado, DIV-44/DIV-45). A viva ja
# recusou o comando antes daqui; a orfa, a ilegivel e a de outro host nao sao
# apagadas — a de outro host pode ser de execucao viva noutra maquina, e a
# ilegivel nunca e apagada por ninguem. Cada uma sai em DBX_CMD_UNLINK_MANTIDAS,
# e o diretorio so some se ficar vazio.
#
# QA-B2-02 e QA-B2-09: a lista de travas e refeita IMEDIATAMENTE antes da
# remocao, com a impressao de cada uma (estado, pid, host, inicio). Antes de
# CADA entrada apagada, e mais uma vez no fim, toda `trava-*` e relida e
# reclassificada: trava nova, trava viva ou trava cujo conteudo mudou (uma orfa
# conhecida retomada no meio, com o mesmo nome) para a remocao com `conflito`
# (7). So travas que continuam iguais e nao vivas sao descritas como mantidas.
#
# JANELA RESIDUAL, DECLARADA: entre a ultima conferencia e o `rm` de uma
# entrada (microssegundos), um `sync` pode adquirir a trava e ler a memoria que
# em seguida some. O efeito e o de memoria ausente — a execucao recalcula e
# regrava ao fim —, nunca decisao errada (RF-38: a memoria nao decide).
_dbx_cmd_unlink_remover_estado() {
  local estado entrada falhou='nao' indice
  # shellcheck disable=SC2034  # lido por referencia de nome na conferencia
  local -A impressoes=()
  DBX_CMD_UNLINK_BASES=()
  DBX_CMD_UNLINK_MANTIDAS=()

  dbx_config_caminho_de_estado || return 0
  estado=$DBX_CONFIG_RESULTADO

  [[ $estado == /*/dbx ]] || return 0
  [[ -L $estado ]] && return 0
  [[ -d $estado ]] || return 0

  _dbx_cmd_unlink_recusar_se_trava_viva depois || return $?
  # Fase 7a (RF-107(c), DIV-185): os `.part` de download interrompido saem so
  # pela barreira de identidade, antes dos registros que os descrevem.
  _dbx_cmd_unlink_parts
  for indice in "${!DBX_STATE_TRAVAS_ARQUIVO[@]}"; do
    dbx_state_trava_examinar "${DBX_STATE_TRAVAS_ARQUIVO[indice]}"
    # shellcheck disable=SC2034  # lido por referencia de nome na conferencia
    impressoes["${DBX_STATE_TRAVAS_ARQUIVO[indice]}"]="$DBX_STATE_TRAVA_ESTADO|$DBX_STATE_RESULTADO"
  done

  for entrada in "$estado"/* "$estado"/.[!.]* "$estado"/..?*; do
    [[ -e $entrada || -L $entrada ]] || continue
    if [[ ${entrada##*/} == trava-* ]]; then
      DBX_CMD_UNLINK_MANTIDAS+=("$entrada")
      continue
    fi
    _dbx_cmd_unlink_travas_inalteradas "$estado" impressoes || return $?
    DBX_CMD_UNLINK_BASES+=("${entrada##*/}")
    rm -rf -- "$entrada" 2>/dev/null || falhou='sim'
  done
  # Ultima conferencia: nenhuma trava descrita como mantida pode estar viva.
  _dbx_cmd_unlink_travas_inalteradas "$estado" impressoes || return $?

  [[ $falhou == 'nao' ]] || return 1
  [[ ${#DBX_CMD_UNLINK_MANTIDAS[@]} -gt 0 ]] && return 0
  rmdir -- "$estado" 2>/dev/null || return 1
  return 0
}

# _dbx_cmd_unlink_parts — RF-107(c) (fase 7a, DIV-185): para cada registro de
# retomada de download legivel, o `.part` que ele aponta e apagado SO se passar
# a barreira de identidade (`lib/state`); o que existe e nao passa NAO e
# apagado e fica em DBX_CMD_UNLINK_PARTS para o aviso. O estado nunca decide
# apagar arquivo do usuario.
DBX_CMD_UNLINK_PARTS=()
_dbx_cmd_unlink_parts() {
  local indice part cred=${1:-}
  DBX_CMD_UNLINK_PARTS=()
  dbx_state_retomada_listar
  for indice in "${!DBX_STATE_RETOMADAS_ARQUIVO[@]}"; do
    # Fase 8 (RF-125(c)): com identidade, so os `.part` dos registros dela.
    [[ -z $cred || ${DBX_STATE_RETOMADAS_CRED[indice]} == "$cred" ]] || continue
    part=${DBX_STATE_RETOMADAS_PART[indice]}
    [[ ${DBX_STATE_RETOMADAS_SENTIDO[indice]} == 'download' && -n $part ]] || continue
    dbx_state_retomada_part_apagar "${part%/*}" "${part##*/}" "${DBX_STATE_RETOMADAS_DEVINO[indice]}" && continue
    [[ -e $part || -L $part ]] && DBX_CMD_UNLINK_PARTS+=("$part")
  done
  return 0
}

# _dbx_cmd_unlink_travas_inalteradas <estado> <nome_do_mapa> — 0 quando cada
# `trava-*` presente e uma das listadas, com a MESMA impressao (estado, pid,
# host, inicio) e nao viva. Trava que sumiu nao impede (ninguem a detem mais).
_dbx_cmd_unlink_travas_inalteradas() {
  local estado=$1 trava
  local -n _conhecidas=$2
  for trava in "$estado"/trava-*; do
    [[ -e $trava || -L $trava ]] || continue
    [[ -n ${_conhecidas[$trava]:-} ]] || {
      _dbx_cmd_unlink_trava_nova "$trava"
      return $?
    }
    dbx_state_trava_examinar "$trava"
    if [[ $DBX_STATE_TRAVA_ESTADO == 'viva' ||
      "$DBX_STATE_TRAVA_ESTADO|$DBX_STATE_RESULTADO" != "${_conhecidas[$trava]}" ]]; then
      _dbx_cmd_unlink_trava_nova "$trava"
      return $?
    fi
  done
  return 0
}

# _dbx_cmd_unlink_trava_nova <arquivo> — trava que surgiu durante a remocao:
# uma execucao comecou; para tudo com `conflito`.
_dbx_cmd_unlink_trava_nova() {
  dbx_cmd_caminho_exibivel "$1"
  dbx_cmd_falhar conflito \
    "uma execucao de sync ou verificar comecou durante o desvinculo (trava $DBX_CMD_EXIBIDO): a remocao do estado parou; rode dbx unlink de novo quando ela terminar"
}

# _dbx_cmd_unlink_recusar_se_trava_viva [depois] — RF-69(h2): execucao viva de
# `sync` ou `verificar` neste host recusa o desvinculo com `conflito`. Chamada
# ANTES da confirmacao e da revogacao e de novo (`depois`) logo antes de apagar
# a credencial e o estado (QA-B2-02): a revogacao e uma chamada de rede, e uma
# execucao pode comecar durante ela.
_dbx_cmd_unlink_recusar_se_trava_viva() {
  local indice depois=${1:-} outro=''
  # DIV-247: a trava nao e atribuivel a perfil; com perfis em jogo a mensagem
  # diz que pode ser a execucao de OUTRO perfil que bloqueia.
  [[ ${DBX_CMD_UNLINK_MULTI:-nao} == 'sim' ]] &&
    outro=' (pode ser um sync ou verificar de outro perfil: a trava nao identifica o perfil)'
  dbx_state_travas_listar
  for indice in "${!DBX_STATE_TRAVAS_ARQUIVO[@]}"; do
    [[ ${DBX_STATE_TRAVAS_ESTADO[indice]} == 'viva' ]] || continue
    dbx_state_trava_descrever "$indice"
    dbx_cmd_caminho_exibivel "${DBX_STATE_TRAVAS_ARQUIVO[indice]}"
    if [[ -n $depois ]]; then
      dbx_cmd_falhar conflito \
        "execucao em curso: $DBX_STATE_RESULTADO, detem a trava $DBX_CMD_EXIBIDO$outro; o desvinculo parou antes de apagar a credencial e o estado (a revogacao remota, se emitida, ja vale): rode dbx unlink de novo quando ela terminar"
    else
      dbx_cmd_falhar conflito \
        "execucao em curso: $DBX_STATE_RESULTADO, detem a trava $DBX_CMD_EXIBIDO$outro; o desvinculo apagaria o estado dela e foi recusado sem apagar nada: rode de novo quando ela terminar"
    fi
    return $?
  done
  return 0
}


# _dbx_cmd_unlink_remover_estado_seletivo <cred> — fase 8 (RF-125(c), DIV-236,
# DIV-238; C5 do DBA): remocao do estado SO da identidade do perfil quando
# restam outras credenciais.
#
# Remove somente: os `retomada-*` e `cursor-*` cujo CABECALHO traz esta
# identidade, os `.part` que os primeiros apontam (pela barreira de identidade
# de RF-107(c)) e a `trava-<r>` da retomada, so quando orfa (nao viva) e
# inalterada. NUNCA remove `memoria-*`, `upload-*`, `trava-*` do par ou de raiz,
# registro de outra identidade ou ilegivel, nem o diretorio de estado (sem
# `rmdir`: o estado de outro perfil pode estar ali). Guardas por identidade
# (`cred-`), nunca por grafia de nome.
_dbx_cmd_unlink_remover_estado_seletivo() {
  local cred=$1 estado indice arquivo trava falhou='nao' apagar_trava
  local -a registros=() creds=()
  # shellcheck disable=SC2034  # lido por referencia de nome na conferencia
  local -A impressoes=()
  DBX_CMD_UNLINK_BASES=()
  DBX_CMD_UNLINK_MANTIDAS=()
  DBX_CMD_UNLINK_PARTS=()
  [[ -n $cred ]] || return 0

  dbx_config_caminho_de_estado || return 0
  estado=$DBX_CONFIG_RESULTADO
  [[ $estado == /*/dbx ]] || return 0
  [[ -L $estado ]] && return 0
  [[ -d $estado ]] || return 0

  _dbx_cmd_unlink_recusar_se_trava_viva depois || return $?
  _dbx_cmd_unlink_parts "$cred"

  dbx_state_retomada_listar
  registros=(${DBX_STATE_RETOMADAS_ARQUIVO[@]+"${DBX_STATE_RETOMADAS_ARQUIVO[@]}"})
  creds=(${DBX_STATE_RETOMADAS_CRED[@]+"${DBX_STATE_RETOMADAS_CRED[@]}"})
  for indice in "${!registros[@]}"; do
    [[ ${creds[indice]} == "$cred" ]] || continue
    arquivo=${registros[indice]}
    trava="$estado/trava-${arquivo##*/retomada-}"
    apagar_trava='nao'
    if [[ -e $trava || -L $trava ]]; then
      dbx_state_trava_examinar "$trava"
      case $DBX_STATE_TRAVA_ESTADO in
        viva)
          _dbx_cmd_unlink_trava_nova "$trava"
          return $?
          ;;
        orfa)
          # shellcheck disable=SC2034  # lido por referencia de nome na conferencia
          impressoes["$trava"]="$DBX_STATE_TRAVA_ESTADO|$DBX_STATE_RESULTADO"
          apagar_trava='sim'
          ;;
        *) DBX_CMD_UNLINK_MANTIDAS+=("$trava") ;;
      esac
    fi
    if [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]]; then
      if rm -f -- "$arquivo" 2>/dev/null; then
        DBX_CMD_UNLINK_BASES+=("${arquivo##*/}")
      else
        falhou='sim'
      fi
    fi
    if [[ $apagar_trava == 'sim' ]]; then
      dbx_state_trava_examinar "$trava"
      if [[ $DBX_STATE_TRAVA_ESTADO == 'orfa' && "$DBX_STATE_TRAVA_ESTADO|$DBX_STATE_RESULTADO" == "${impressoes[$trava]}" ]]; then
        rm -f -- "$trava" 2>/dev/null
      elif [[ $DBX_STATE_TRAVA_ESTADO != 'ausente' ]]; then
        _dbx_cmd_unlink_trava_nova "$trava"
        return $?
      fi
    fi
  done

  dbx_state_cursor_listar
  registros=(${DBX_STATE_CURSORES_ARQUIVO[@]+"${DBX_STATE_CURSORES_ARQUIVO[@]}"})
  creds=(${DBX_STATE_CURSORES_CRED[@]+"${DBX_STATE_CURSORES_CRED[@]}"})
  for indice in "${!registros[@]}"; do
    [[ ${creds[indice]} == "$cred" ]] || continue
    arquivo=${registros[indice]}
    if [[ -f $arquivo && ! -L $arquivo && -O $arquivo ]]; then
      if rm -f -- "$arquivo" 2>/dev/null; then
        DBX_CMD_UNLINK_BASES+=("${arquivo##*/}")
      else
        falhou='sim'
      fi
    fi
  done
  [[ $falhou == 'nao' ]] || return 1
  return 0
}

dbx_cmd_unlink_executar() {
  dbx_carregar_camada_de_credencial

  local confirmado='nao' modo='integral'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --confirmar | --yes) confirmado='sim' ;;
      --manter-aplicativo | --keep-app) modo='aplicativo' ;;
      # A selecao ja foi feita por `lib/cli`; aqui so se consome o par.
      --perfil | --profile) shift ;;
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
  local nome=${DBX_CONFIG_PERFIL:-$DBX_CONFIG_PERFIL_PADRAO} nomeado='nao' explicito='nao'
  dbx_config_perfil_nomeado && nomeado='sim'
  [[ -n $DBX_CONFIG_PERFIL_ORIGEM ]] && explicito='sim'

  # RF-124(c): perfil nomeado inexistente (ou atras de ligacao simbolica) sai
  # `3` ANTES da advertencia, da confirmacao, da rede e de qualquer remocao.
  if [[ $nomeado == 'sim' ]]; then
    if [[ -L ${arquivo%/*} || -L ${arquivo%/*/*} ]]; then
      dbx_cmd_falhar configuracao \
        "perfil $nome: dbx ou perfis e ligacao simbolica; nada foi removido"
      return $?
    fi
    if [[ ! -e $arquivo && ! -L $arquivo ]]; then
      dbx_cmd_caminho_exibivel "$arquivo"
      dbx_cmd_falhar configuracao \
        "perfil $nome inexistente: $DBX_CMD_EXIBIDO; nada foi removido (liste com: dbx perfis)"
      return $?
    fi
  fi

  # Os demais perfis (RF-124(e)(g)): um por vez, canais esvaziados entre eles.
  local -a outros=()
  local candidato
  dbx_config_perfis_listar
  for candidato in ${DBX_CONFIG_PERFIS_NOME[@]+"${DBX_CONFIG_PERFIS_NOME[@]}"}; do
    [[ $candidato == "$nome" ]] || outros+=("$candidato")
  done
  DBX_CMD_UNLINK_MULTI='nao'
  if [[ ($explicito == 'sim' && $nomeado == 'sim') || ${#outros[@]} -gt 0 ]]; then
    DBX_CMD_UNLINK_MULTI='sim'
  fi

  _dbx_cmd_unlink_recusar_se_trava_viva || return $?

  # RF-124(j): a identidade do perfil e calculada da credencial carregada ANTES
  # de qualquer remocao; ilegivel, o estado nao sera tocado.
  local ident='' havia='nao'
  [[ -e $arquivo || ($nomeado == 'sim' && -L $arquivo) ]] && havia='sim'
  if [[ $havia == 'sim' ]] && dbx_config_carregar 2>/dev/null; then
    dbx_config_identidade
    ident=$DBX_CONFIG_IDENTIDADE
  fi
  local -a compartilhado=()
  local nao_comparaveis=0
  if [[ -n $ident ]]; then
    for candidato in ${outros[@]+"${outros[@]}"}; do
      if dbx_config_identidade_de_perfil "$candidato"; then
        [[ $DBX_CONFIG_IDENTIDADE == "$ident" ]] && compartilhado+=("$candidato")
      else
        nao_comparaveis=$((nao_comparaveis + 1))
      fi
    done
  fi
  DBX_CONFIG_IDENTIDADE=''

  local rotulo='desta instalacao'
  [[ $nomeado == 'sim' ]] && rotulo="do perfil $nome"
  if [[ ${#compartilhado[@]} -gt 0 ]]; then
    # RF-124(e), DIV-237: identidade compartilhada nao revoga.
    {
      printf 'Este perfil (%s) tem a MESMA credencial (app key e refresh token) de: %s.\n' "$nome" "${compartilhado[*]}"
      printf 'O refresh token NAO sera revogado: revoga-lo, em cascata, inutilizaria esses perfis.\n'
      printf 'So o arquivo do perfil sai; o estado dessa credencial e mantido.\n'
    } >&2
  else
    # ADVERTENCIA DE CASCATA (RF-06a, RES-12). Ela e dita ANTES da confirmacao, e
    # nao depois: advertencia que chega depois da decisao nao e advertencia.
    {
      printf 'Desvincular revoga o refresh token %s.\n' "$rotulo"
      printf 'A revogacao e em cascata: invalida tambem todos os access tokens\n'
      printf 'derivados dele, inclusive os de outras maquinas e de execucoes em\n'
      printf 'curso. Nao ha desfazer — religar exige autorizar de novo.\n'
    } >&2
  fi
  if [[ $nao_comparaveis -gt 0 ]]; then
    printf 'aviso: %s perfil(is) nao puderam ser comparados (ilegivel, inseguro ou incompleto); se algum tiver a mesma credencial, a revogacao o inutiliza\n' \
      "$nao_comparaveis" >&2
  fi

  # RF-06a exige confirmacao no modo interativo e sinalizador explicito no modo
  # automatizado. O criterio e o TERMINAL, e nao uma suposicao sobre quem chama.
  if [[ $confirmado != 'sim' ]]; then
    if [[ ! -t 0 ]]; then
      dbx_cmd_falhar uso_invalido \
        'desvinculo sem terminal exige o sinalizador explicito --confirmar (ou --yes)'
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
    [[ $explicito == 'sim' ]] && dbx_output_campo perfil "$nome"
    dbx_output_campo credencial "$arquivo"
    dbx_output_campo modo "$modo"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  # A ordem importa: revogar exige a credencial que a limpeza vai apagar. A
  # comparacao acima esvaziou os canais: o perfil e carregado de novo.
  local revogacao='nao_emitida' classe_remota='' carregou='nao'
  if [[ $havia == 'sim' ]] && dbx_config_carregar 2>/dev/null; then
    carregou='sim'
    if [[ ${#compartilhado[@]} -eq 0 ]]; then
      if dbx_auth_revogar; then
        revogacao='emitida'
      else
        revogacao='falhou'
        classe_remota=${DBX_HTTP_CLASSE:-erro_remoto}
      fi
    fi
  fi

  # RF-124(l), C8 do DBA: depois da revogacao e antes do `rm`, o perfil e
  # recarregado e a identidade reconferida. Mudou (um `config --substituir`
  # regravou no meio): nao apaga, nao revoga de novo, `conflito`.
  if [[ $carregou == 'sim' && -n $ident && ${#compartilhado[@]} -eq 0 && $revogacao != 'nao_emitida' ]]; then
    local identidade_agora=''
    if [[ ! -e $arquivo ]]; then
      identidade_agora=$ident
    elif dbx_config_carregar 2>/dev/null; then
      dbx_config_identidade
      identidade_agora=$DBX_CONFIG_IDENTIDADE
    fi
    if [[ $identidade_agora != "$ident" ]]; then
      dbx_cmd_falhar conflito \
        "o perfil $nome foi regravado durante o desvinculo (outro dbx config?): nada foi apagado e o token novo nao foi revogado; rode dbx unlink de novo"
      return $?
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

  # QA-B2-02: segunda conferencia, logo antes de apagar qualquer coisa.
  _dbx_cmd_unlink_recusar_se_trava_viva depois || return $?

  local remocao='concluida'
  dbx_config_remover "$modo" || remocao='falhou'

  # Estado (RF-124(g), DIV-238): com identidade compartilhada, nenhum; sem
  # outra credencial restante, remocao TOTAL como hoje; senao, seletiva.
  local bases='concluida' estado_bases=0
  # shellcheck disable=SC2034  # canal publico preenchido pelo auxiliar
  DBX_CMD_UNLINK_BASES=()
  DBX_CMD_UNLINK_MANTIDAS=()
  DBX_CMD_UNLINK_PARTS=()
  if [[ ${#compartilhado[@]} -gt 0 ]]; then
    :
  elif [[ ${#outros[@]} -eq 0 ]]; then
    _dbx_cmd_unlink_remover_estado || estado_bases=$?
  elif [[ -n $ident ]]; then
    _dbx_cmd_unlink_remover_estado_seletivo "$ident" || estado_bases=$?
  else
    printf 'aviso: a identidade do perfil %s nao pode ser calculada (credencial ilegivel ou incompleta): nenhum estado foi removido\n' "$nome" >&2
  fi
  # Terceira conferencia, dentro da remocao: execucao que comecou no meio.
  [[ $estado_bases -eq $(dbx_errors_codigo_saida conflito) ]] && return "$estado_bases"
  [[ $estado_bases -eq 0 ]] || bases='falhou'

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao unlink
  [[ $explicito == 'sim' ]] && dbx_output_campo perfil "$nome"
  dbx_output_campo revogacao "$revogacao"
  for candidato in ${compartilhado[@]+"${compartilhado[@]}"}; do
    dbx_output_campo compartilhada_com "$candidato"
  done
  dbx_output_campo credencial "$remocao"
  dbx_output_campo modo "$modo"
  dbx_output_campo bases "$bases"
  local base
  for base in ${DBX_CMD_UNLINK_BASES[@]+"${DBX_CMD_UNLINK_BASES[@]}"}; do
    dbx_output_campo base_removida "$base"
  done
  dbx_output_render

  if [[ ${#compartilhado[@]} -gt 0 ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso \
      "o perfil $nome saiu sem revogar o token, que segue em uso por: ${compartilhado[*]}; para revoga-lo rode dbx unlink --perfil ${compartilhado[0]}"
    dbx_output_render_diagnostico >&2
  fi

  # Uma linha por trava mantida, com o caminho exibivel (sem byte cru).
  local mantida
  for mantida in ${DBX_CMD_UNLINK_MANTIDAS[@]+"${DBX_CMD_UNLINK_MANTIDAS[@]}"}; do
    dbx_cmd_caminho_exibivel "$mantida"
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso \
      "trava mantida (orfa, ilegivel ou de outro host): $DBX_CMD_EXIBIDO; confirme que nenhum sync ou verificar deste par esta em curso e remova-a com rm"
    dbx_output_render_diagnostico >&2
  done

  # RF-107(c): quantos `.part` ficaram e onde, uma linha cada, citados.
  if [[ ${#DBX_CMD_UNLINK_PARTS[@]} -gt 0 ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso \
      "${#DBX_CMD_UNLINK_PARTS[@]} arquivo(s) parcial(is) de download interrompido nao apagado(s): nao passam a barreira de identidade (outro inode, outro dono, ligacao simbolica ou fora do padrao); confira e remova com rm"
    local parte
    for parte in "${DBX_CMD_UNLINK_PARTS[@]}"; do
      dbx_cmd_caminho_exibivel "$parte"
      dbx_output_diagnostico aviso "parcial mantido: $DBX_CMD_EXIBIDO"
    done
    dbx_output_render_diagnostico >&2
  fi

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
