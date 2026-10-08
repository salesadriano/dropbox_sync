#!/usr/bin/env bash
# config — assistente de vinculo inicial (RF-01, RF-03, RNF-04, DP-11).
#
# POR QUE ESTE COMANDO DECLARA `ambiente` E NAO `credencial`
#
#   Porque ele e a ferramenta que CRIA a credencial, e a verificacao previa do
#   nivel `credencial` RECUSA a execucao quando a credencial existente esta em
#   permissao larga. Declarar `credencial` aqui produziria o impasse que
#   `lib/cli` descreve desde que o vocabulario foi escrito: o operador nao
#   conseguiria consertar a credencial com a unica ferramenta que sabe grava-la
#   corretamente.
#
# O SEGREDO NAO ENTRA POR `argv` NEM POR AMBIENTE
#
#   Nao ha `--app-secret`, e nao ha leitura de variavel de ambiente (DP-11). Os
#   valores sao lidos da ENTRADA PADRAO, e as perguntas vao para a saida de erro.
#   Um caminho so serve aos dois usos: no terminal o operador digita, num
#   automatismo os valores chegam por `printf ... | dbx config`, e em nenhum dos
#   dois o segredo aparece na tabela de processos. A saida padrao fica livre para
#   o registro de resultado, como exige RF-28.
#
# ORDEM DE COLETA — decidida pelo relogio, e nao pela estetica
#
#   Chave e segredo primeiro, URL depois, codigo por ultimo. Chave e segredo saem
#   da MESMA tela do console do desenvolvedor; o codigo de autorizacao serve uma
#   vez so e expira em minutos. Perguntar o segredo depois do codigo abriria uma
#   janela de digitacao entre a emissao do codigo e a troca, e codigo vencido
#   entre uma pergunta e outra produz erro que parece de credencial errada.

dbx_cmd_config_requisitos() { printf 'ambiente'; }

# _dbx_cmd_config_perguntar <texto> <nome_da_variavel> [oculto]
#
# Pergunta pela saida de erro, le da entrada padrao e devolve por NOME. Nao usa
# substituicao de comando porque `$( )` roda em subshell — o valor lido morreria
# com ele — e porque remove quebras finais, que e a classe de defeito ja vista
# tres vezes neste projeto.
#
# Os locais levam sublinhado a frente para nao colidirem com o nome recebido: a
# atribuicao de `read` alcanca o escopo dinamico, entao um pedido para preencher
# `texto` preencheria o local desta funcao em vez do do chamador.
_dbx_cmd_config_perguntar() {
  local _texto=$1 _nome=$2 _oculto=${3:-nao}
  printf '%s' "$_texto" >&2
  # O STATUS DE `read` NAO E O CRITERIO, e confundir os dois foi defeito real.
  #
  # `read` devolve NAO ZERO ao encontrar o fim da entrada, mesmo tendo atribuido
  # o que leu. Uma entrada legitima terminada sem quebra de linha — que e o que
  # sai de `$( )`, de um documento aqui e de varios geradores — teria o ultimo
  # valor LIDO e mesmo assim recusado, com diagnostico dizendo que o operador nao
  # informou o que informou. O criterio e o valor: veio algo, serve.
  # shellcheck disable=SC2229
  # Justificativa: a expansao aqui e DELIBERADA e e o mecanismo da funcao. `read`
  # recebe o NOME da variavel a preencher, que e como o valor volta ao chamador
  # sem passar por substituicao de comando — que rodaria em subshell e removeria
  # a quebra final. Escrever `read -r _nome` preencheria o local desta funcao.
  if [[ $_oculto == 'sim' ]]; then
    # `-s` so tem efeito quando a entrada e terminal; num canal nao ha eco a
    # suprimir e a leitura e a mesma. A quebra de linha e reposta a mao porque
    # sob `-s` o terminal nao a exibe e a pergunta seguinte sairia colada.
    IFS= read -r -s "$_nome"
    printf '\n' >&2
  else
    IFS= read -r "$_nome"
  fi
  [[ -n ${!_nome} ]] || return 1
  return 0
}

dbx_cmd_config_executar() {
  # Carregado ANTES da leitura de argumentos: `dbx_cmd_falhar` mora em `lib/cmd`,
  # e recusar uma opcao invalida sem ele daria erro de funcao inexistente no
  # lugar do diagnostico.
  dbx_carregar_camada_de_credencial

  local substituir='nao' raiz='/'
  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      --substituir) substituir='sim' ;;
      --raiz)
        shift
        raiz=${1-}
        ;;
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

  local remoto
  _dbx_cmd_caminho_remoto "$raiz" || {
    dbx_cmd_falhar caminho_recusado "raiz remota recusada: $raiz"
    return $?
  }
  remoto=$DBX_CMD_LIDO

  dbx_config_caminho || {
    dbx_cmd_falhar configuracao \
      "nao foi possivel determinar o caminho da credencial: $DBX_CONFIG_MOTIVO"
    return $?
  }
  local arquivo=$DBX_CONFIG_RESULTADO

  # SUBSTITUIR CREDENCIAL EXISTENTE EXIGE SINALIZADOR, por seguranca e nao por
  # conveniencia: gravar por cima descarta o refresh token anterior DA NOSSA
  # VISTA sem revoga-lo. Nada neste caminho emite revogacao, entao do nosso lado
  # o token some e do lado da Dropbox nao ha acao alguma sobre ele.
  #
  # O QUE NAO FOI MEDIDO, e por isso a decisao e conservadora: nao verifiquei se
  # autorizar de novo invalida o refresh anterior. Sabemos que a Dropbox nao
  # ROTACIONA o refresh na renovacao — isso foi verificado —, mas isso e outra
  # pergunta. Na duvida, o desenho supoe que o token anterior CONTINUA VALIDO,
  # que e a suposicao que erra para o lado seguro: se ele de fato morrer, a
  # recusa custou um sinalizador; se sobreviver, ela evitou deixar acesso vivo a
  # conta sem que ninguem soubesse. Esta e uma das perguntas para a verificacao
  # contra o servico real.
  #
  # A unica forma que CONTROLAMOS de encerra-lo e `unlink`, e o diagnostico diz
  # isso em vez de so recusar.
  if [[ -e $arquivo && $substituir == 'nao' ]]; then
    dbx_cmd_falhar configuracao \
      "ja existe credencial em $arquivo; gravar por cima NAO revoga o token anterior, que segue valido na Dropbox — use 'dbx unlink' para revoga-lo antes, ou 'dbx config --substituir' para trocar assumindo esse risco"
    return $?
  fi

  if [[ ${DBX_CLI_SIMULACAO:-nao} == 'sim' ]]; then
    dbx_cmd_iniciar_saida
    dbx_output_campo operacao config
    dbx_output_campo credencial "$arquivo"
    dbx_output_campo raiz_remota "$remoto"
    dbx_output_campo simulado sim
    dbx_output_render
    return 0
  fi

  {
    printf 'Vinculo com a Dropbox — passos:\n'
    printf '  1. Abra https://www.dropbox.com/developers/apps e crie um aplicativo\n'
    printf '     do tipo "Scoped access". Em Permissions marque ao menos\n'
    printf '     files.metadata.read, files.content.read, files.content.write e\n'
    printf '     account_info.read, e clique em Submit.\n'
    printf '  2. Na aba Settings do aplicativo, copie App key e App secret.\n\n'
  } >&2

  local chave='' segredo='' codigo='' estado=0
  _dbx_cmd_config_perguntar 'App key: ' chave || {
    dbx_cmd_falhar uso_invalido 'app key nao informada'
    return $?
  }
  # A chave vai para dentro de uma URL que o operador cola no navegador. A
  # validacao deriva da gramatica de URL e mora em `lib/auth`, junto de quem
  # monta a URL — verificar aqui tambem duplicaria a regra em dois lugares.
  dbx_auth_chave_de_aplicativo_valida "$chave" || {
    dbx_cmd_falhar uso_invalido 'app key contem caractere que nao pertence a uma URL'
    return $?
  }

  _dbx_cmd_config_perguntar 'App secret (nao sera exibido): ' segredo sim || {
    dbx_cmd_falhar uso_invalido 'app secret nao informado'
    return $?
  }

  local url=''
  url=$(dbx_auth_url_de_autorizacao "$chave") || {
    segredo=''
    dbx_cmd_falhar uso_invalido 'nao foi possivel montar a URL de autorizacao'
    return $?
  }
  {
    printf '  3. Abra esta URL, autorize o acesso e copie o codigo exibido:\n\n'
    printf '     %s\n\n' "$url"
    printf '     O codigo vale por poucos minutos e serve uma vez so.\n\n'
  } >&2

  _dbx_cmd_config_perguntar 'Codigo de autorizacao: ' codigo || {
    segredo=''
    dbx_cmd_falhar uso_invalido 'codigo de autorizacao nao informado'
    return $?
  }

  dbx_auth_trocar_codigo "$chave" "$segredo" "$codigo"
  estado=$?
  codigo=''
  if [[ $estado -ne 0 ]]; then
    segredo=''
    dbx_cmd_falhar "$(dbx_errors_classe_do_codigo "$estado")" \
      "vinculo recusado: ${DBX_AUTH_MOTIVO:-sem detalhe}"
    return $?
  fi

  dbx_config_gravar "$chave" "$segredo" "$DBX_AUTH_REFRESH_TOKEN" "$remoto" || {
    segredo=''
    dbx_auth_esquecer_vinculo
    dbx_cmd_falhar configuracao "gravacao da credencial falhou: $DBX_CONFIG_MOTIVO"
    return $?
  }
  # Os dois segredos deixam de existir neste processo assim que estao em disco.
  segredo=''

  # A advertencia so aparece quando houve troca de verdade: dita antes, seria
  # aviso sobre algo que talvez nao acontecesse.
  [[ $substituir == 'sim' ]] &&
    printf 'aviso: a credencial anterior foi substituida; o refresh token antigo NAO foi revogado e segue valido na Dropbox\n' >&2

  dbx_cmd_iniciar_saida
  dbx_output_campo operacao config
  dbx_output_campo credencial "$arquivo"
  dbx_output_campo raiz_remota "$remoto"
  [[ -n ${DBX_AUTH_CONTA:-} ]] && dbx_output_campo conta "$DBX_AUTH_CONTA"
  dbx_output_render
  dbx_auth_esquecer_vinculo
  return 0
}
