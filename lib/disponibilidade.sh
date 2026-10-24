#!/usr/bin/env bash
# lib/disponibilidade.sh — disponibilidade de internet, do servico Dropbox e da
# credencial (RF-148 a RF-153, fase 11, F-50).
#
# Camada: adaptadores. Carrega lib/errors.sh e lib/http.sh (que e o ponto unico
# de saida de rede: a sonda passa por `dbx_http_sondar`, nunca por curl daqui).
# Usa, SEM carregar (o ponto de entrada ja os tem quando o gancho esta armado):
# lib/config (`dbx_config_carregar`, `DBX_CONFIG_MOTIVO`), lib/auth
# (`dbx_auth_renovar`, `dbx_auth_definir_motivo`, `dbx_auth_enriquecer_motivo`, `dbx_auth_falha_de_servidor`),
# `dbx_iniciar_config` (bin/dbx, DIV-325) e `DBX_CLI_SIMULACAO` (lib/cli).
# Estado: o do processo; so a marca opcional de `dbx_disp_compartilhar_sonda`
# (diretorio da execucao, informado por quem lanca processos auxiliares) vai a
# disco, para a sonda ser uma por EXECUCAO (RF-149(g)).
#
# TABELA UNICA DE CLASSIFICACAO (RF-150), sem codigo de saida novo:
#   sem internet              rede 9          (a sonda nao responde)
#   Dropbox inacessivel       rede 9          (a sonda responde, a API nao)
#   servico indisponivel      erro_remoto 10  (a API respondeu 5xx; sem sonda)
#   limite de taxa            limite_taxa 8   (429: o servico esta no ar)
#   sonda desligada           rede 9          (nao distingue as duas causas)
#
# NENHUM SEGREDO: a sonda e o alcance do Dropbox viajam sem token; as mensagens
# daqui nao citam URL, cabecalho nem corpo (RF-150(c), RF-154).

# shellcheck disable=SC2034
# Justificativa: as variaveis DBX_DISP_* sao canais publicos lidos por quem chama.

[[ -n ${DBX_DISP_CARREGADO:-} ]] && return 0
DBX_DISP_CARREGADO=1

# DBX_CLI_RAIZ ja existe no ponto de entrada (sem fork); o calculo pelo proprio
# caminho fica para o carregamento isolado (testes unitarios).
if [[ -n ${DBX_CLI_RAIZ:-} ]]; then
  _dbx_disp_diretorio="$DBX_CLI_RAIZ/lib"
else
  _dbx_disp_diretorio=${BASH_SOURCE[0]%/*}
  [[ $_dbx_disp_diretorio == "${BASH_SOURCE[0]}" ]] && _dbx_disp_diretorio=.
  _dbx_disp_diretorio=$(cd -P -- "$_dbx_disp_diretorio" && pwd -P)
fi
# shellcheck source=lib/errors.sh
. "$_dbx_disp_diretorio/errors.sh"
# shellcheck source=lib/http.sh
. "$_dbx_disp_diretorio/http.sh"
unset _dbx_disp_diretorio

readonly DBX_DISP_SONDA_PADRAO='https://www.gstatic.com/generate_204'
readonly DBX_DISP_URL_API='https://api.dropboxapi.com/'
readonly DBX_DISP_URL_CONTEUDO='https://content.dropboxapi.com/'

# Estado da sonda no processo (RF-149(g)).
# Estado da sonda: padrao, configurada, desligada ou invalida.
DBX_DISP_SONDA_ESTADO=''
DBX_DISP_SONDA_URL=''
DBX_DISP_INTERNET_FEITA='nao'
# Resultado: responde, nao_responde, desligada ou invalida.
DBX_DISP_INTERNET=''
# Status HTTP observado; zero sem resposta.
DBX_DISP_INTERNET_STATUS=0
# Diretorio da execucao para a marca compartilhada da sonda (vazio = so o processo).
DBX_DISP_MARCA_DIR=''
# Aviso de URL de sonda invalida: um por execucao (RF-149(b)).
DBX_DISP_AVISO_FEITO='nao'
# Uma oferta por execucao (RF-152, item h).
DBX_DISP_OFERTA_FEITA='nao'

# Canal de saida de dbx_disp_mensagem e dbx_disp_alcance.
DBX_DISP_CLASSE=''
DBX_DISP_MENSAGEM=''
DBX_DISP_REMEDIO=''
# Alcance: ok, sem_resposta, indisponivel ou limite_taxa.
DBX_DISP_ALCANCE=''

# dbx_disp_sonda_configurar — le DBX_TESTE_INTERNET_URL (RF-149(b)): nao definida
# usa o padrao; definida e vazia desliga; sem https:// e invalida (o valor nunca
# e guardado nem citado).
dbx_disp_sonda_configurar() {
  DBX_DISP_SONDA_URL=''
  if [[ -z ${DBX_TESTE_INTERNET_URL+definida} ]]; then
    DBX_DISP_SONDA_ESTADO='padrao'
    DBX_DISP_SONDA_URL=$DBX_DISP_SONDA_PADRAO
  elif [[ -z $DBX_TESTE_INTERNET_URL ]]; then
    DBX_DISP_SONDA_ESTADO='desligada'
  elif [[ $DBX_TESTE_INTERNET_URL == "$DBX_HTTP_ESQUEMA_SONDA"?* ]]; then
    DBX_DISP_SONDA_ESTADO='configurada'
    DBX_DISP_SONDA_URL=$DBX_TESTE_INTERNET_URL
  else
    DBX_DISP_SONDA_ESTADO='invalida'
  fi
}

# dbx_disp_compartilhar_sonda <diretorio> — declara o diretorio da execucao (ja
# criado por quem lanca processos auxiliares, herdado por eles) onde fica a marca
# da sonda: o primeiro processo que a reserva sonda e publica o resultado; os
# demais o leem, sem sondar (RF-149(g)).
dbx_disp_compartilhar_sonda() {
  DBX_DISP_MARCA_DIR=${1-}
  # Sem diretorio utilizavel nao ha o que compartilhar: sonda local, sem espera.
  [[ -d $DBX_DISP_MARCA_DIR && -w $DBX_DISP_MARCA_DIR ]] || DBX_DISP_MARCA_DIR=''
}

# Prazo maximo (ms) que quem perde a reserva espera o resultado do vencedor: o
# tempo limite da sonda (`max-time 10`, DIV-312) mais uma folga de 2000 ms. Canal
# publico, ajustavel em teste.
DBX_DISP_ESPERA_MS=12000

# _dbx_disp_agora_ms — relogio em milissegundos (EPOCHREALTIME; segundos inteiros
# quando a variavel nao existe).
_dbx_disp_agora_ms() {
  if [[ -n ${EPOCHREALTIME:-} ]]; then
    local t=${EPOCHREALTIME/[.,]/}
    _DBX_DISP_AGORA=$((10#$t / 1000))
  else
    _DBX_DISP_AGORA=$((SECONDS * 1000))
  fi
}

# _dbx_disp_reservar_sonda — 0 quando este processo deve sondar; 1 quando outro
# processo da execucao ja reservou: ESPERA o resultado dele ate DBX_DISP_ESPERA_MS,
# contado por relogio (DIV-331 A), e o publica em DBX_DISP_INTERNET; sem resultado
# no prazo, ou com o vencedor morto (PID gravado na reserva), a causa e
# `indeterminada`. A reserva e a criacao exclusiva de arquivo (noclobber, O_EXCL):
# `mkdir` nao e exclusivo em todo sistema de arquivos. Falha de criacao que nao
# seja "ja existe" (sem diretorio utilizavel) sonda localmente, sem espera.
_dbx_disp_reservar_sonda() {
  local meu=$BASHPID fim pid
  [[ -n $DBX_DISP_MARCA_DIR ]] || return 0
  (
    set -C
    printf '%s\n' "$meu" >"$DBX_DISP_MARCA_DIR/sonda.reserva"
  ) 2>/dev/null && return 0
  [[ -e $DBX_DISP_MARCA_DIR/sonda.reserva ]] || return 0
  DBX_DISP_INTERNET='indeterminada'
  _dbx_disp_agora_ms
  fim=$((_DBX_DISP_AGORA + DBX_DISP_ESPERA_MS))
  while :; do
    if [[ -s $DBX_DISP_MARCA_DIR/sonda.resultado ]]; then
      IFS= read -r DBX_DISP_INTERNET <"$DBX_DISP_MARCA_DIR/sonda.resultado" || :
      case $DBX_DISP_INTERNET in
        responde | nao_responde | desligada | invalida | indeterminada) ;;
        *) DBX_DISP_INTERNET='indeterminada' ;;
      esac
      return 1
    fi
    pid=''
    IFS= read -r pid <"$DBX_DISP_MARCA_DIR/sonda.reserva" 2>/dev/null || :
    # Vencedor que nao existe mais (kill -KILL): nao ha resultado a esperar.
    if [[ $pid =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
      [[ -s $DBX_DISP_MARCA_DIR/sonda.resultado ]] || return 1
      continue
    fi
    _dbx_disp_agora_ms
    ((_DBX_DISP_AGORA < fim)) || return 1
    sleep 0.05
  done
}

# dbx_disp_internet — roda a sonda UMA vez por processo (RF-149(g)), e uma vez por
# execucao quando ha marca compartilhada, e publica DBX_DISP_INTERNET e
# DBX_DISP_INTERNET_STATUS. Qualquer resposta HTTP, de qualquer status, conta como
# "responde" (DIV-311).
dbx_disp_internet() {
  [[ $DBX_DISP_INTERNET_FEITA == 'sim' ]] && return 0
  DBX_DISP_INTERNET_FEITA='sim'
  DBX_DISP_INTERNET_STATUS=0
  _dbx_disp_reservar_sonda || return 0
  dbx_disp_sonda_configurar
  case $DBX_DISP_SONDA_ESTADO in
    desligada) DBX_DISP_INTERNET='desligada' ;;
    invalida) DBX_DISP_INTERNET='invalida' ;;
    *)
      if dbx_http_sondar "$DBX_DISP_SONDA_URL"; then
        DBX_DISP_INTERNET='responde'
      else
        DBX_DISP_INTERNET='nao_responde'
      fi
      DBX_DISP_INTERNET_STATUS=$DBX_HTTP_SONDA_CODIGO
      ;;
  esac
  if [[ -n $DBX_DISP_MARCA_DIR ]]; then
    printf '%s\n' "$DBX_DISP_INTERNET" >"$DBX_DISP_MARCA_DIR/sonda.tmp" &&
      mv -f -- "$DBX_DISP_MARCA_DIR/sonda.tmp" "$DBX_DISP_MARCA_DIR/sonda.resultado"
  fi
  return 0
}

# dbx_disp_alcance <url> — a API/host Dropbox responde, sem token (RF-148(b))?
# Publica DBX_DISP_ALCANCE: ok, limite_taxa (429), indisponivel (5xx) ou
# sem_resposta (resolucao, conexao, TLS ou tempo).
dbx_disp_alcance() {
  if ! dbx_http_sondar "$1"; then
    DBX_DISP_ALCANCE='sem_resposta'
    return 1
  fi
  case $DBX_HTTP_SONDA_CODIGO in
    429) DBX_DISP_ALCANCE='limite_taxa' ;;
    5??) DBX_DISP_ALCANCE='indisponivel' ;;
    *)
      DBX_DISP_ALCANCE='ok'
      return 0
      ;;
  esac
  return 1
}

# dbx_disp_mensagem <causa> — classe, frase e remedio da causa (RF-150(a)(c)).
dbx_disp_mensagem() {
  case ${1-} in
    sem_internet)
      DBX_DISP_CLASSE='rede'
      DBX_DISP_MENSAGEM='sem acesso a internet'
      DBX_DISP_REMEDIO='verifique o cabo/Wi-Fi, o proxy e o DNS'
      ;;
    dropbox_inacessivel)
      DBX_DISP_CLASSE='rede'
      DBX_DISP_MENSAGEM='Dropbox inacessivel (a internet responde, o servico nao)'
      DBX_DISP_REMEDIO='verifique firewall, proxy e DNS para dropboxapi.com'
      ;;
    dropbox_indisponivel)
      DBX_DISP_CLASSE='erro_remoto'
      DBX_DISP_MENSAGEM='servico Dropbox indisponivel (a API respondeu erro do servidor)'
      DBX_DISP_REMEDIO='aguarde e rode de novo; veja o status do Dropbox'
      ;;
    limite_taxa)
      DBX_DISP_CLASSE='limite_taxa'
      DBX_DISP_MENSAGEM='limite de taxa do servico Dropbox (o servico esta no ar)'
      DBX_DISP_REMEDIO='aguarde alguns minutos e rode de novo'
      ;;
    indeterminada)
      DBX_DISP_CLASSE='rede'
      DBX_DISP_MENSAGEM='sem acesso a internet ou Dropbox inacessivel'
      DBX_DISP_REMEDIO='verifique a rede, o proxy e o DNS'
      ;;
    *)
      DBX_DISP_CLASSE='rede'
      DBX_DISP_MENSAGEM='sem acesso a internet ou Dropbox inacessivel; sonda desligada'
      DBX_DISP_REMEDIO='verifique a rede, o proxy e o DNS; a sonda se liga desfazendo DBX_TESTE_INTERNET_URL'
      ;;
  esac
}

# _dbx_disp_avisar_sonda_invalida — RF-149(b), DIV-310 A: URL de sonda invalida
# no fluxo automatico avisa em stderr, uma vez por execucao; nomeia a variavel e
# nunca o valor.
_dbx_disp_avisar_sonda_invalida() {
  [[ $DBX_DISP_AVISO_FEITO == 'sim' ]] && return 0
  # R5: stderr descartado (auxiliar do sync, ou chamada com `2>/dev/null`) nao
  # chega ao operador: com area compartilhada o pedido fica na marca e o principal
  # o emite; sem ela, o aviso NAO e consumido e a proxima chamada o escreve.
  if [[ /dev/stderr -ef /dev/null ]]; then
    [[ -n $DBX_DISP_MARCA_DIR ]] && : >"$DBX_DISP_MARCA_DIR/sonda.aviso" 2>/dev/null
    return 0
  fi
  _dbx_disp_escrever_aviso_sonda
}

# _dbx_disp_escrever_aviso_sonda — escreve o aviso, se ainda nao saiu.
_dbx_disp_escrever_aviso_sonda() {
  [[ $DBX_DISP_AVISO_FEITO == 'sim' ]] && return 0
  DBX_DISP_AVISO_FEITO='sim'
  printf 'dbx: aviso: DBX_TESTE_INTERNET_URL deve comecar com %s; a sonda de internet foi ignorada\n' \
    "$DBX_HTTP_ESQUEMA_SONDA" >&2
}

# dbx_disp_emitir_aviso_pendente — o processo principal emite o aviso de URL
# invalida pedido por um auxiliar (marca `sonda.aviso`), uma vez por execucao.
dbx_disp_emitir_aviso_pendente() {
  [[ -n $DBX_DISP_MARCA_DIR && -e $DBX_DISP_MARCA_DIR/sonda.aviso ]] || return 0
  rm -f -- "$DBX_DISP_MARCA_DIR/sonda.aviso"
  _dbx_disp_escrever_aviso_sonda
}

# dbx_disp_nomear_falha <rede|erro_remoto|limite_taxa> — nomeia a causa de uma
# falha de transporte ja ocorrida (RF-151(d)): 5xx e 429 nao disparam sonda; so
# `rede` aciona a sonda, uma vez. O codigo de saida e sempre o da classe original.
dbx_disp_nomear_falha() {
  case ${1-} in
    erro_remoto) dbx_disp_mensagem dropbox_indisponivel ;;
    limite_taxa) dbx_disp_mensagem limite_taxa ;;
    *)
      dbx_disp_internet
      case $DBX_DISP_INTERNET in
        nao_responde) dbx_disp_mensagem sem_internet ;;
        responde) dbx_disp_mensagem dropbox_inacessivel ;;
        indeterminada) dbx_disp_mensagem indeterminada ;;
        invalida)
          _dbx_disp_avisar_sonda_invalida
          dbx_disp_mensagem sonda_desligada
          ;;
        *) dbx_disp_mensagem sonda_desligada ;;
      esac
      ;;
  esac
}

# dbx_disp_oferta_possivel — portao de RF-152(a): stdin e stderr terminais,
# TERM diferente de dumb, comando que nao consome a entrada padrao
# (DBX_DISP_CONSOME_STDIN=sim fecha), sem --dry-run, DBX_TESTE_CONFIG diferente
# de `nao` e nenhuma oferta anterior. Faltando qualquer um, nao ha pergunta nem
# leitura de stdin.
dbx_disp_oferta_possivel() {
  [[ $DBX_DISP_OFERTA_FEITA == 'sim' ]] && return 1
  [[ ${DBX_TESTE_CONFIG-} == 'nao' ]] && return 1
  [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]] && return 1
  [[ ${DBX_DISP_CONSOME_STDIN:-nao} == 'sim' ]] && return 1
  [[ ${TERM:-dumb} == 'dumb' ]] && return 1
  [[ -t 0 && -t 2 ]] || return 1
  return 0
}

# dbx_disp_oferecer_config <ausente|invalida> — pergunta em stderr e, aceito,
# roda o `config` NO MESMO PROCESSO (RF-152(f)) por `dbx_iniciar_config`, definida em bin/dbx. Devolve 0 so quando o config
# terminou com sucesso; 1 em recusa, cancelamento ou falha (o chamador mantem o
# codigo da falha original, DIV-319). Marca a oferta como feita antes de
# perguntar. Nenhum valor de credencial e dito.
dbx_disp_oferecer_config() {
  local causa=${1-invalida} resposta='' substituir=()
  # DIV-325: lib nao carrega commands/; o ponto de entrada define a funcao que
  # inicia o config. Sem ela o portao esta fechado.
  declare -F dbx_iniciar_config >/dev/null || return 1
  dbx_disp_oferta_possivel || return 1
  DBX_DISP_OFERTA_FEITA='sim'
  printf 'Credencial %s. Configurar agora? [s/N] ' "$causa" >&2
  IFS= read -r resposta || resposta=''
  [[ -t 2 ]] && printf '\n' >&2
  case ${resposta,,} in
    s | sim) ;;
    *)
      printf 'nenhuma alteracao feita\n' >&2
      return 1
      ;;
  esac
  [[ $causa == 'invalida' ]] && substituir=(--substituir)
  # O resultado do config sai em stderr: stdout fica para o comando original.
  dbx_iniciar_config "${substituir[@]}" >&2
}

# dbx_disp_ao_falhar_token <codigo> — gancho de falha do token (RF-151(c)(d),
# RF-153). Devolve o codigo final da obtencao do token (0 = obtido).
#   autenticacao  oferta o `config --substituir` sob o portao; aceito e config ok,
#                 relê a credencial e renova UMA vez; recusa ou falha mantem o codigo
#   rede          a sonda decide a causa (sem internet x Dropbox inacessivel)
#   erro_remoto   5xx na renovacao: servico indisponivel, sem sonda
# Nos dois ultimos o codigo de saida e o original; so a mensagem (resumo de erro
# publicado em DBX_HTTP_RESUMO_DE_ERRO) passa a nomear a causa.
dbx_disp_ao_falhar_token() {
  local estado=$1 classe=''
  _dbx_disp_classe_de "$estado"
  case $classe in
    autenticacao)
      dbx_disp_oferecer_config invalida || return "$estado"
      dbx_config_carregar || {
        dbx_auth_definir_motivo "credencial indisponivel: ${DBX_CONFIG_MOTIVO:-desconhecido}"
        return "${DBX_ERRORS_CODIGO[configuracao]}"
      }
      dbx_auth_renovar
      return $?
      ;;
    rede)
      dbx_disp_nomear_falha rede
      _dbx_disp_publicar_causa auth
      ;;
    erro_remoto)
      dbx_auth_falha_de_servidor || return "$estado"
      dbx_disp_nomear_falha erro_remoto
      _dbx_disp_publicar_causa auth
      ;;
  esac
  return "$estado"
}

# _dbx_disp_classe_de <codigo> — classe da taxonomia em $classe do chamador
# (dinamico) a partir do codigo de saida.
_dbx_disp_classe_de() {
  local candidata
  classe=''
  for candidata in "${DBX_ERRORS_CLASSES[@]}"; do
    if [[ ${DBX_ERRORS_CODIGO[$candidata]} == "$1" ]]; then
      classe=$candidata
      break
    fi
  done
}

# _dbx_disp_publicar_causa [auth] — poe a causa nomeada no resumo de erro e, com
# `auth`, tambem no motivo da autenticacao (DIV-329a), que os comandos de
# `dbx_auth_preparar` imprimem. O resumo original e preservado entre parenteses.
_dbx_disp_publicar_causa() {
  local original=${DBX_HTTP_RESUMO_DE_ERRO:-}
  DBX_HTTP_RESUMO_DE_ERRO="$DBX_DISP_MENSAGEM; $DBX_DISP_REMEDIO${original:+ ($original)}"
  [[ ${1-} == 'auth' ]] && dbx_auth_enriquecer_motivo "$DBX_DISP_MENSAGEM; $DBX_DISP_REMEDIO"
  return 0
}

# dbx_disp_ao_falhar_chamada <codigo> — gancho de falha da chamada (RF-151(e),
# DIV-329b): falha `rede` ou 5xx de uma requisicao DEPOIS do token. So enriquece a
# mensagem; o codigo de saida e o da classe original (o chamador ignora o retorno),
# a sonda roda no maximo uma vez por processo (memoizada) e nunca ha oferta de config.
dbx_disp_ao_falhar_chamada() {
  local classe=''
  _dbx_disp_classe_de "$1"
  case $classe in
    rede) dbx_disp_nomear_falha rede ;;
    erro_remoto)
      [[ ${DBX_HTTP_CODIGO:-0} == 5?? ]] || return 0
      dbx_disp_nomear_falha erro_remoto
      ;;
    *) return 0 ;;
  esac
  _dbx_disp_publicar_causa
}
