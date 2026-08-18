#!/usr/bin/env bash
# lib/errors.sh — taxonomia de erro, codigos de saida e politica de retentativa.
#
# Camada: dominio. Puramente logico: nao imprime, nao acessa rede, nao le
# configuracao e NAO interpreta JSON. Recebe o codigo HTTP e o `error_summary`
# ja extraidos pelo chamador (lib/http com lib/json) e devolve strings.
#
# Requisitos atendidos: RF-29 (codigos deterministicos por classe de falha),
# RF-35 (estabilidade do contrato de automacao) e RNF-08 (mapeamento explicito
# da semantica de erro da Dropbox).
#
# Divergencia registrada contra o System Design: a tabela de componentes lista
# `lib/json` como dependencia de `lib/errors`. Isso contraria a propria regra de
# dependencia declarada no mesmo documento ("Dominio: sem dependencia externa") e
# tornaria a taxonomia refem de DP-08, ainda em aberto. A dependencia foi
# invertida: quem extrai o campo e o adaptador; o dominio so classifica texto.
#
# Abordagens avaliadas para a correspondencia de `error_summary`:
#   (a) igualdade exata contra uma lista de tags. Rejeitada: a Dropbox sufixa as
#       tags (`path/not_found/.`) e orienta explicitamente o uso de prefixo.
#   (b) expressao regular por tag. Rejeitada: custo de manutencao alto e risco de
#       casar demais, que e a origem do defeito DIV-04 no projeto de referencia.
#   (c) ESCOLHIDA — correspondencia por prefixo com FRONTEIRA de componente: casa
#       `path/not_found`, `path/not_found/` e `path/not_found.`, mas nunca
#       `path/not_founded`. Cobre o formato documentado sem classificar errado
#       uma tag futura que apenas comece com as mesmas letras.

[[ -n ${DBX_ERRORS_CARREGADO:-} ]] && return 0
DBX_ERRORS_CARREGADO=1

# ---------------------------------------------------------------------------
# Contrato congelado de codigos de saida (RF-29, RF-35)
#
# Mudar qualquer valor abaixo e mudanca incompativel do contrato de automacao:
# exige nova versao principal da saida estruturada e reprova a suite de proposito.
# A faixa util e 0..15; 126, 127 e 128+n permanecem reservados ao shell.
# ---------------------------------------------------------------------------

DBX_ERRORS_CLASSES=(
  sucesso
  desconhecido
  uso_invalido
  configuracao
  nao_encontrado
  autenticacao
  permissao
  conflito
  limite_taxa
  rede
  erro_remoto
  integridade
  espaco
  caminho_recusado
  nao_concluida
  consumidor_encerrou
)

declare -gA DBX_ERRORS_CODIGO=(
  [sucesso]=0
  [desconhecido]=1
  [uso_invalido]=2
  [configuracao]=3
  [nao_encontrado]=4
  [autenticacao]=5
  [permissao]=6
  [conflito]=7
  [limite_taxa]=8
  [rede]=9
  [erro_remoto]=10
  [integridade]=11
  [espaco]=12
  [caminho_recusado]=13
  [nao_concluida]=14
  [consumidor_encerrou]=15
)

declare -gA DBX_ERRORS_MENSAGEM=(
  [sucesso]='Operacao concluida.'
  [desconhecido]='Falha nao classificada. Repita com diagnostico elevado e guarde o error_summary integral e o identificador de requisicao para abrir chamado.'
  [uso_invalido]='Uso invalido. Verifique os argumentos e as opcoes do comando; consulte a ajuda do subcomando.'
  [configuracao]='Ambiente ou configuracao inadequados para executar a operacao. Verifique o arquivo de configuracao, os utilitarios exigidos e a area temporaria, conforme o detalhe informado.'
  [nao_encontrado]='Caminho ou item inexistente no destino informado. Confira o caminho remoto e a raiz configurada.'
  [autenticacao]='Credencial invalida, expirada ou sem o escopo necessario. Reautentique a aplicacao e confirme os escopos concedidos ao aplicativo.'
  [permissao]='Acesso negado pela conta, pelo plano contratado ou pela politica da pasta. Verifique as permissoes do item e do aplicativo.'
  [conflito]='Ja existe item no caminho de destino. Escolha a politica de colisao desejada: sobrescrever, ignorar ou renomear.'
  [limite_taxa]='Limite de taxa atingido e esgotadas as tentativas permitidas. Reduza a concorrencia e distribua as execucoes ao longo do tempo.'
  [rede]='Nao houve resposta do servico. Verifique conectividade, resolucao de nome, proxy e cadeia de certificados TLS.'
  [erro_remoto]='Falha no lado do servico apos esgotar as tentativas. Repita mais tarde e registre o identificador de requisicao.'
  [integridade]='O conteudo transferido nao confere com o resumo esperado. Repita a operacao; nao considere o item integro.'
  [espaco]='Espaco insuficiente na conta de destino. Libere espaco ou amplie o plano antes de repetir.'
  [caminho_recusado]='Caminho fora da raiz permitida para esta configuracao. A operacao foi recusada antes de qualquer chamada a API.'
  [nao_concluida]='Operacao interrompida antes da conclusao. Nenhum resultado parcial deve ser considerado valido; reexecute a operacao.'
  [consumidor_encerrou]='O processo consumidor encerrou antes do fim do fluxo. A transferencia foi interrompida de forma controlada.'
)

# Correspondencia por prefixo do `error_summary`, na ordem de avaliacao.
# Formato: <prefixo>=<classe>.
# Tags de erro da Dropbox, sem qualificador de uniao.
#
# O `error_summary` e composto como {qualificador}/{tag}/..., por exemplo
# `path/restricted_content/.` ou `lookup_failed/incorrect_offset/.`. Enumerar as
# formas compostas uma a uma deixava a maior parte da familia de erros de rota
# cair no balde `desconhecido`, que sai com codigo 1 e esvazia RF-29. Aqui a
# tabela guarda apenas TAGS, e os qualificadores conhecidos sao removidos antes
# do casamento — o que cobre a combinacao {qualificador} x {tag} sem enumerar o
# produto cartesiano.
DBX_ERRORS_QUALIFICADORES=(
  path
  path_lookup
  path_write
  from_lookup
  from_write
  to
  lookup_failed
)

DBX_ERRORS_TAGS=(
  'not_found=nao_encontrado'
  'malformed_path=uso_invalido'
  'disallowed_name=uso_invalido'
  'not_file=uso_invalido'
  'not_folder=uso_invalido'
  'invalid_argument=uso_invalido'
  'payload_too_large=uso_invalido'
  'insufficient_space=espaco'
  'no_write_permission=permissao'
  'no_permission=permissao'
  'access_denied=permissao'
  'restricted_content=permissao'
  'invalid_account_type=permissao'
  'email_unverified=permissao'
  'conflict=conflito'
  'content_hash_mismatch=integridade'
  'rate_limit=limite_taxa'
  'too_many_requests=limite_taxa'
  'too_many_write_operations=limite_taxa'
  'invalid_access_token=autenticacao'
  'expired_access_token=autenticacao'
  'missing_scope=autenticacao'
  'reset=nao_concluida'
  'incorrect_offset=nao_concluida'
  'closed=nao_concluida'
  'not_closed=nao_concluida'
  'transient_error=erro_remoto'
  'internal_error=erro_remoto'
  'other=desconhecido'
)

# ---------------------------------------------------------------------------
# Redacao de material sensivel (RNF-03)
#
# A credencial circula em JSON (corpo do endpoint de token), em cabecalho
# (`Authorization`, `Cookie`), em querystring e em corpo urlencoded. Reconhecer
# apenas palavras separadas por espaco deixa passar justamente o formato
# dominante, porque em JSON o valor vem entre aspas e colado a dois-pontos.
#
# A varredura usa substituicao por padrao estendido do proprio shell, executada
# em C, em vez de laco por token no nivel do script. Isso preserva pontuacao,
# indentacao e quebras de linha do texto original — diagnostico reformatado
# perde valor — e mantem o custo proporcional ao tamanho da entrada, ja limitada
# por DBX_ERRORS_LIMITE_REDACAO.
# ---------------------------------------------------------------------------

# Teto do RESULTADO. Fixo e readonly: vindo do ambiente nao seria freio nenhum,
# e ele e uma das defesas de custo desta funcao.
readonly DBX_ERRORS_LIMITE_REDACAO=4096
# Teto da ENTRADA analisada. Dimensionado em relacao ao teto de SAIDA: nao faz
# sentido varrer centenas de KiB para emitir 4 KiB. Com 262.144 o pior caso
# medido era de 4,56 s; com 16.384 fica na ordem de 0,1 s.
#
# Truncar a entrada e seguro porque o mascaramento NAO depende de encontrar um
# delimitador de fechamento: um valor sem fechamento e mascarado ate o fim da
# entrada. Essa invariante esta fixada pelo caso
# `valor_sem_delimitador_de_fechamento_e_mascarado_ate_o_fim`, e e ela — nao a
# ordem entre redigir e truncar — que impede o bypass de truncagem.
readonly DBX_ERRORS_MAXIMO_ENTRADA=16384

DBX_ERRORS_CHAVES_SENSIVEIS=(
  access_token refresh_token client_secret app_secret oauth_token id_token
  api_key apikey auth authorization proxy_authorization cookie set_cookie
  password passwd secret token tokens code
)

# Chaves cujo valor se estende ate o fim da linha, e nao ate um delimitador.
DBX_ERRORS_CHAVES_DE_CABECALHO=(authorization cookie set_cookie)

# Caracteres que encerram um identificador. Tudo que nao esta aqui e que nao e
# `[A-Za-z0-9_-]` permanece colado ao identificador, o que e inofensivo: apenas
# torna o termo mais longo e portanto sem correspondencia com chave sensivel.
DBX_ERRORS_DELIMITADORES=(
  ' ' $'\t' $'\n' $'\r' '"' "'" '=' ':' ',' ';' '&' '?' '{' '}' '[' ']'
  '(' ')' '<' '>' '.' '/' $'\\' '|' '+' '%' '#' '@' '!' '*' '~' '`' '^' '$'
)

declare -gA DBX_ERRORS_E_SENSIVEL=()
for _dbx_errors_chave in "${DBX_ERRORS_CHAVES_SENSIVEIS[@]}"; do
  DBX_ERRORS_E_SENSIVEL[$_dbx_errors_chave]=1
done
declare -gA DBX_ERRORS_E_CABECALHO=()
for _dbx_errors_chave in "${DBX_ERRORS_CHAVES_DE_CABECALHO[@]}"; do
  DBX_ERRORS_E_CABECALHO[$_dbx_errors_chave]=1
done
unset _dbx_errors_chave

readonly -a DBX_ERRORS_CLASSES DBX_ERRORS_TAGS DBX_ERRORS_QUALIFICADORES
readonly -a DBX_ERRORS_CHAVES_SENSIVEIS DBX_ERRORS_CHAVES_DE_CABECALHO DBX_ERRORS_DELIMITADORES
readonly -A DBX_ERRORS_CODIGO DBX_ERRORS_MENSAGEM
readonly -A DBX_ERRORS_E_SENSIVEL DBX_ERRORS_E_CABECALHO

readonly DBX_ERRORS_STATUS_OK=0
readonly DBX_ERRORS_STATUS_USO=2

# ---------------------------------------------------------------------------
# Consulta da taxonomia
# ---------------------------------------------------------------------------

dbx_errors_listar_classes() {
  printf '%s\n' "${DBX_ERRORS_CLASSES[@]}"
}

dbx_errors_classe_valida() {
  local classe=${1:-}
  [[ -n $classe && -n ${DBX_ERRORS_CODIGO[$classe]:-} ]]
}

# dbx_errors_codigo_saida <classe> — imprime o codigo; status 2 se a classe nao existe.
dbx_errors_codigo_saida() {
  local classe=${1:-}
  dbx_errors_classe_valida "$classe" || return "$DBX_ERRORS_STATUS_USO"
  printf '%s\n' "${DBX_ERRORS_CODIGO[$classe]}"
}

# ---------------------------------------------------------------------------
# Classificacao
# ---------------------------------------------------------------------------

# _dbx_errors_prefixo_casa <error_summary> <prefixo>
# Casa o prefixo apenas em fronteira de componente: fim da cadeia, `/` ou `.`.
_dbx_errors_prefixo_casa() {
  local resumo=$1 prefixo=$2
  [[ $resumo == "$prefixo" ]] && return 0
  [[ $resumo == "$prefixo/"* ]] && return 0
  [[ $resumo == "$prefixo."* ]] && return 0
  return 1
}

# _dbx_errors_classe_da_tag <resumo> — casa o resumo contra a tabela de tags,
# respeitando a fronteira de componente. Imprime a classe, ou status 1.
_dbx_errors_classe_da_tag() {
  local resumo=$1 entrada tag classe
  [[ -n $resumo ]] || return 1
  for entrada in "${DBX_ERRORS_TAGS[@]}"; do
    tag=${entrada%%=*}
    classe=${entrada#*=}
    if _dbx_errors_prefixo_casa "$resumo" "$tag"; then
      printf '%s' "$classe"
      return 0
    fi
  done
  return 1
}

# _dbx_errors_remover_qualificador <resumo> — remove UM qualificador de uniao
# inicial, se houver. Imprime o restante, ou status 1 se nada foi removido.
#
# A remocao exige a barra: `path/` e qualificador, `pathological` nao e. Sem
# essa exigencia, remover o qualificador afrouxaria o casamento para "comeca
# com" e devolveria justamente o defeito de fronteira que a suite ja cobre.
# Deixa o restante em DBX_ERRORS_RESTANTE em vez de imprimir: o `error_summary`
# vem de fora e a substituicao de comando removeria quebras finais dele.
_dbx_errors_remover_qualificador() {
  local resumo=$1 qualificador
  DBX_ERRORS_RESTANTE=''
  for qualificador in "${DBX_ERRORS_QUALIFICADORES[@]}"; do
    if [[ $resumo == "$qualificador/"* ]]; then
      DBX_ERRORS_RESTANTE=${resumo#"$qualificador"/}
      return 0
    fi
  done
  return 1
}

# dbx_errors_classificar <codigo_http> <error_summary> — imprime a classe.
# Codigo HTTP `0` significa ausencia de resposta (falha de transporte).
dbx_errors_classificar() {
  local http=${1:-} resumo=${2:-} classe
  [[ $http =~ ^[0-9]+$ ]] || return "$DBX_ERRORS_STATUS_USO"

  if [[ $http -ge 200 && $http -lt 300 ]]; then
    printf 'sucesso\n'
    return "$DBX_ERRORS_STATUS_OK"
  fi
  if [[ $http -eq 0 ]]; then
    printf 'rede\n'
    return "$DBX_ERRORS_STATUS_OK"
  fi
  # Corpo de 5xx nao segue o contrato de `error_summary` e pode vir de um proxy
  # no caminho. Deixar o prefixo decidir aqui produziria classificacao arbitraria.
  if [[ $http -ge 500 ]]; then
    printf 'erro_remoto\n'
    return "$DBX_ERRORS_STATUS_OK"
  fi

  # Casa a tag; nao casando, remove um qualificador de uniao e tenta de novo.
  # O teto de voltas encerra qualquer composicao inesperada sem laco aberto.
  local restante=$resumo voltas=0
  while [[ -n $restante && $voltas -le 4 ]]; do
    if classe=$(_dbx_errors_classe_da_tag "$restante"); then
      printf '%s\n' "$classe"
      return "$DBX_ERRORS_STATUS_OK"
    fi
    _dbx_errors_remover_qualificador "$restante" || break
    restante=$DBX_ERRORS_RESTANTE
    voltas=$((voltas + 1))
  done

  case $http in
    400) printf 'uso_invalido\n' ;;
    401) printf 'autenticacao\n' ;;
    403) printf 'permissao\n' ;;
    429) printf 'limite_taxa\n' ;;
    *) printf 'desconhecido\n' ;;
  esac
  return "$DBX_ERRORS_STATUS_OK"
}

# dbx_errors_politica_retentativa <codigo_http> <error_summary> [idempotente]
#
# `idempotente` vale `sim` ou `nao`; omitido, assume `nao`, que e o lado seguro.
# Valores possiveis de retorno, SETE ao todo: nenhuma, recuo_exponencial,
# respeitar_retry_after, renovar_token_uma_vez, reiniciar, retomar,
# indeterminado.
#
# A versao anterior deste comentario listava seis, omitindo `retomar` — que
# governa a retomada de sessao em partes, e portanto o pior dos sete a faltar
# num contrato que `lib/http` lera antes de ler o codigo (TL-18).
#
# Sobre `indeterminado`: sem resposta HTTP nao ha como saber se a escrita foi
# aplicada do outro lado. Devolver `nenhuma` nesse caso seria enganoso, porque
# quem implementa lib/http leria como instrucao ("nao tente"), quando o
# significado real e "nao da para saber". O estado tem nome proprio, e a decisao
# cabe ao chamador, que conhece a operacao. Para operacao idempotente
# (`download`, `list_folder`, `get_metadata`) a ambiguidade nao existe e a
# retentativa e liberada: sem isso, um RST de TCP encerra um lote de cron por
# falha trivialmente recuperavel (PRJ-DEC-02).
dbx_errors_politica_retentativa() {
  local http=${1:-} resumo=${2:-} idempotente=${3:-nao} classe
  [[ $http =~ ^[0-9]+$ ]] || return "$DBX_ERRORS_STATUS_USO"
  case $idempotente in
    sim | nao) ;;
    *) return "$DBX_ERRORS_STATUS_USO" ;;
  esac

  # A politica CONSULTA a classificacao. Decidir de novo, por codigo HTTP, fazia
  # as duas se contradizerem: `409 too_many_write_operations` era classificado
  # como limite de taxa e recebia politica `nenhuma`, embora seja a contencao de
  # lock de namespace da Dropbox, que o servico manda repetir. O mesmo valia para
  # `path/rate_limit`, `transient_error`, `internal_error` e `incorrect_offset`.
  classe=$(dbx_errors_classificar "$http" "$resumo") || return "$DBX_ERRORS_STATUS_USO"

  # Duas condicoes especificas de sessao, distinguidas pela tag: uma reinicia o
  # percurso, a outra retoma do deslocamento informado pelo servico. Tratar as
  # duas como "reexecute" reiniciaria um envio de varios GB ja quase concluido.
  if [[ -n $resumo ]]; then
    local restante=$resumo voltas=0
    while [[ -n $restante && $voltas -le 4 ]]; do
      if _dbx_errors_prefixo_casa "$restante" reset; then
        printf 'reiniciar\n'
        return "$DBX_ERRORS_STATUS_OK"
      fi
      if _dbx_errors_prefixo_casa "$restante" incorrect_offset; then
        printf 'retomar\n'
        return "$DBX_ERRORS_STATUS_OK"
      fi
      _dbx_errors_remover_qualificador "$restante" || break
    restante=$DBX_ERRORS_RESTANTE
      voltas=$((voltas + 1))
    done
  fi

  case $classe in
    limite_taxa)
      printf 'respeitar_retry_after\n'
      ;;
    autenticacao)
      printf 'renovar_token_uma_vez\n'
      ;;
    erro_remoto | rede)
      # Sem confirmacao de que a operacao NAO foi aplicada, repetir e decisao do
      # chamador, que conhece a operacao. Para operacao idempotente a
      # ambiguidade nao existe.
      if [[ $idempotente == 'sim' ]]; then
        printf 'recuo_exponencial\n'
      else
        printf 'indeterminado\n'
      fi
      ;;
    *)
      # `408` e tempo limite de requisicao: retentavel, e nao classificado por
      # tag alguma.
      if [[ $http -eq 408 ]]; then
        printf 'recuo_exponencial\n'
      else
        printf 'nenhuma\n'
      fi
      ;;
  esac
  return "$DBX_ERRORS_STATUS_OK"
}

# ---------------------------------------------------------------------------
# Mensagens
# ---------------------------------------------------------------------------

# dbx_errors_redigir <texto> — mascara material sensivel antes de qualquer
# exibicao ou registro (RNF-03). Opera so com recursos internos do shell, sem
# `sed`, evitando a divergencia GNU/BSD apontada em RSK-09.
# _dbx_errors_e_espaco <elemento>
_dbx_errors_e_espaco() {
  [[ $1 == ' ' || $1 == $'\t' || $1 == $'\n' || $1 == $'\r' ]]
}

# dbx_errors_redigir <texto> — mascara material sensivel (RNF-03).
#
# Desenho: VARREDURA EM PASSADA UNICA, linear por construcao.
#
# As duas versoes anteriores iteravam padroes sobre a cadeia inteira — primeiro
# por tokens separados por espaco, depois por substituicao com padrao estendido.
# Ambas trocaram um custo por outro pior: a segunda chegou a 77 s para 4 KB de
# corpo denso em `chave=valor`, porque cada casamento de chave sensivel disparava
# retrocesso sobre o restante do texto. Enquanto o desenho for "iterar padroes
# sobre a cadeia inteira", o custo depende do CONTEUDO e nao do tamanho, e um
# teto de tamanho nao o contem.
#
# Aqui o texto e percorrido uma unica vez:
#   1. cada delimitador e envolvido por um separador — uma passagem em C por
#      delimitador, custo proporcional ao tamanho;
#   2. uma unica divisao produz um vetor que alterna termos e delimitadores,
#      preservando tudo, de modo que a juncao reproduz a entrada byte a byte;
#   3. o vetor e varrido uma vez, com indexacao O(1), por uma maquina de estados
#      que reconhece chave, delimitador e valor.
#
# Nao ha fatiamento de cadeia longa, nao ha retrocesso e nao ha padrao aplicado
# repetidamente sobre o todo, e por isso o custo deixa de depender do CONTEUDO.
# Ele nao e, porem, estritamente proporcional ao tamanho: medido de 4 KiB a
# 256 KiB, cresce com expoente da ordem de 1,5, por causa do custo de montar e
# percorrer o vetor de termos. E previsivel e limitado pelo teto de entrada,
# que existe justamente para fechar o pior caso.
#
# A chave e reconhecida como TERMO COMPLETO, nunca como subcadeia: por isso
# `error_code`, `exit_code`, `status_code` e `geocode` sobrevivem intactos,
# enquanto `code` isolado e redigido.
#
# Em cabecalho sensivel o NOME e preservado e o valor e mascarado ate o fim da
# LINHA — ou seja, o restante da linha e consumido junto. Em dump HTTP, onde
# cada cabecalho ocupa a propria linha, o efeito pratico e preservar todos os
# demais campos de diagnostico. Em um registro de uma linha so, com campos
# separados por outro caractere, o que vier depois do cabecalho sensivel se
# perde. Errar para o lado de redigir demais e a escolha correta sob RNF-03.
#
# REQUISITO DE ENTRADA PARA lib/output: nao concatenar campos de diagnostico na
# mesma linha de um cabecalho sensivel, sob pena de perder o identificador de
# requisicao que RF-30 existe para preservar.
dbx_errors_redigir() {
  local texto=${1:-}
  DBX_ERRORS_REDIGIDO=''
  [[ -n $texto ]] || return 0

  # O separador de fronteiras usado internamente e um byte de controle. Se ele
  # aparecer no texto original, a divisao o consome e a juncao nao o devolve:
  # a fidelidade byte a byte se perde E a redacao pode ser contornada, porque um
  # byte de controle no meio do nome da chave a parte em dois termos, nenhum
  # deles sensivel, e o valor sai com aparencia de texto normal nao redigido.
  # Nada no diagnostico denunciaria o contorno, que e o pior modo de falha.
  # Por isso texto com caractere de controle (exceto tabulacao, quebra de linha
  # e retorno de carro) nao e analisado, e nada dele e emitido.
  local sem_quebras=${texto//[$'\t\n\r']/}
  if [[ $sem_quebras == *[[:cntrl:]]* ]]; then
    DBX_ERRORS_REDIGIDO='[REDIGIDO: corpo com caractere de controle, nao analisavel]'
    printf '%s' "$DBX_ERRORS_REDIGIDO"
    return 0
  fi

  if [[ ${#texto} -gt $DBX_ERRORS_MAXIMO_ENTRADA ]]; then
    texto=${texto:0:$DBX_ERRORS_MAXIMO_ENTRADA}
  fi

  local separador=$'\x01' marcado=$texto delimitador
  for delimitador in "${DBX_ERRORS_DELIMITADORES[@]}"; do
    marcado=${marcado//"$delimitador"/$separador$delimitador$separador}
  done

  local -a partes=()
  IFS=$separador read -r -d '' -a partes < <(printf '%s' "$marcado") || true

  local total=${#partes[@]} indice segundo terceiro termo chave
  for ((indice = 0; indice < total; indice++)); do
    termo=${partes[indice]}
    [[ -n $termo ]] || continue
    # Elemento de um unico caractere delimitador nunca e chave.
    case $termo in
      [!A-Za-z0-9_-]) continue ;;
    esac

    chave=${termo,,}
    chave=${chave//-/_}

    # Prefixo documentado do access token da Dropbox: `sl` `.` `<termo>`.
    if [[ $chave == 'sl' && ${partes[indice + 1]:-} == '.' && -n ${partes[indice + 2]:-} ]]; then
      partes[indice]='[REDIGIDO]'
      partes[indice + 1]=''
      partes[indice + 2]=''
      indice=$((indice + 2))
      continue
    fi

    # Esquema de autenticacao seguido da credencial.
    if [[ $chave == 'bearer' || $chave == 'basic' || $termo == '-u' ]]; then
      # Exige espaco real entre o esquema e a credencial. Sem isso, o `bearer`
      # que aparece como VALOR em `"token_type":"bearer"` dispararia a regra e
      # consumiria o fechamento do JSON.
      segundo=$((indice + 1))
      local houve_espaco='nao'
      while [[ $segundo -lt $total ]]; do
        [[ -z ${partes[segundo]} ]] && {
          segundo=$((segundo + 1))
          continue
        }
        _dbx_errors_e_espaco "${partes[segundo]}" || break
        houve_espaco='sim'
        segundo=$((segundo + 1))
      done
      if [[ $houve_espaco == 'sim' ]]; then
        _dbx_errors_mascarar_valor partes "$segundo" "$total" espaco
        indice=$segundo
      fi
      continue
    fi

    [[ -n ${DBX_ERRORS_E_SENSIVEL[$chave]:-} ]] || continue

    # Localiza o delimitador entre chave e valor, tolerando aspas e espacos.
    segundo=$((indice + 1))
    while [[ $segundo -lt $total ]]; do
      # Delimitadores consecutivos produzem elementos vazios; sao posicao, nao
      # conteudo, e nao podem interromper a busca.
      case ${partes[segundo]} in
        '') ;;
        '"' | "'") ;;
        '=' | ':') break ;;
        *) _dbx_errors_e_espaco "${partes[segundo]}" || break ;;
      esac
      segundo=$((segundo + 1))
    done
    [[ $segundo -lt $total ]] || continue
    [[ ${partes[segundo]} == '=' || ${partes[segundo]} == ':' ]] || continue

    # Posiciona no inicio do valor, saltando espacos e a aspa de abertura.
    terceiro=$((segundo + 1))
    while [[ $terceiro -lt $total ]]; do
      if [[ -z ${partes[terceiro]} ]] || _dbx_errors_e_espaco "${partes[terceiro]}"; then
        terceiro=$((terceiro + 1))
        continue
      fi
      if [[ ${partes[terceiro]} == '"' || ${partes[terceiro]} == "'" ]]; then
        terceiro=$((terceiro + 1))
        continue
      fi
      break
    done

    if [[ ${partes[terceiro]:-} == '[' ]]; then
      _dbx_errors_mascarar_valor partes $((terceiro + 1)) "$total" arranjo
    elif [[ -n ${DBX_ERRORS_E_CABECALHO[$chave]:-} ]]; then
      _dbx_errors_mascarar_valor partes "$terceiro" "$total" linha
    else
      _dbx_errors_mascarar_valor partes "$terceiro" "$total" delimitador
    fi
    indice=$terceiro
  done

  local IFS=''
  texto="${partes[*]}"

  # A truncagem ocorre DEPOIS da redacao. Truncar antes podia cortar a aspa de
  # fechamento que as regras antigas exigiam e, com isso, o proprio corte
  # decidia quantos caracteres do segredo sobreviviam.
  if [[ ${#texto} -gt $DBX_ERRORS_LIMITE_REDACAO ]]; then
    texto="${texto:0:$DBX_ERRORS_LIMITE_REDACAO} [...truncado]"
  fi
  DBX_ERRORS_REDIGIDO=$texto
  printf '%s' "$texto"
}

# _dbx_errors_mascarar_valor <nome_do_vetor> <inicio> <total> <modo>
# Substitui o valor por uma marca unica. Modos: `delimitador` para ate o proximo
# separador estrutural, `linha` para ate o fim da linha, `arranjo` para ate o
# fechamento do colchete, `espaco` para ate o proximo espaco.
_dbx_errors_mascarar_valor() {
  local -n vetor=$1
  local posicao=$2 total=$3 modo=$4
  local primeiro=$posicao elemento anterior=''

  [[ $posicao -lt $total ]] || return 0

  while [[ $posicao -lt $total ]]; do
    elemento=${vetor[posicao]}
    # Aspa precedida de barra invertida esta ESCAPADA e pertence ao valor. Sem
    # esta verificacao, `"a\"b<segredo>"` encerrava o mascaramento na primeira
    # aspa e o restante do valor vazava. Nao ocorre com token da Dropbox, que e
    # base64url, mas a funcao e generica e cobre `password` e `secret`.
    if [[ $anterior == $'\\' && ( $elemento == '"' || $elemento == "'" ) ]]; then
      anterior=$elemento
      vetor[posicao]=''
      posicao=$((posicao + 1))
      continue
    fi
    # Delimitadores consecutivos produzem elementos vazios entre si. Eles sao
    # posicao, nao conteudo, e nao podem apagar a memoria do caractere anterior
    # — sem esta guarda, o vazio entre `\` e `"` desfazia a deteccao do escape.
    [[ -n $elemento ]] && anterior=$elemento
    case $modo in
      linha)
        [[ $elemento == $'\n' || $elemento == $'\r' ]] && break
        ;;
      arranjo)
        [[ $elemento == ']' ]] && break
        ;;
      espaco)
        _dbx_errors_e_espaco "$elemento" && break
        ;;
      *)
        case $elemento in
          '"' | "'" | ',' | ';' | '&' | '}' | ']' | ')') break ;;
        esac
        _dbx_errors_e_espaco "$elemento" && break
        ;;
    esac
    vetor[posicao]=''
    posicao=$((posicao + 1))
  done

  [[ $posicao -gt $primeiro ]] || return 0
  vetor[primeiro]='[REDIGIDO]'
}

# dbx_errors_mensagem <classe> [detalhe] — mensagem acionavel, com o detalhe
# redigido. Nao imprime na saida de erro: quem renderiza e lib/output.
dbx_errors_mensagem() {
  local classe=${1:-} detalhe=${2:-} texto
  dbx_errors_classe_valida "$classe" || return "$DBX_ERRORS_STATUS_USO"
  texto=${DBX_ERRORS_MENSAGEM[$classe]}
  if [[ -n $detalhe ]]; then
    # Canal por variavel: a substituicao de comando removeria quebras finais do
    # detalhe, que vem de fora. E a mesma classe de D1, C2-01 e E2-04.
    dbx_errors_redigir "$detalhe" >/dev/null
    texto+=" Detalhe: $DBX_ERRORS_REDIGIDO"
  fi
  printf '%s\n' "$texto"
}
