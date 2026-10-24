#!/usr/bin/env bash
# Testes de lib/preflight.sh — verificacao de ambiente e dependencias.
#
# A classe de erro para dependencia ausente e `configuracao` (3): a proposta de
# um codigo 16 dedicado foi REJEITADA, e a mensagem de `configuracao` foi
# reescrita para nao presumir credencial.

# shellcheck disable=SC2016
# Justificativa: casos entregam script literal a "bash -c", que precisa chegar
# sem expansao ao processo filho.

# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/preflight.sh"

_area() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/preflight.XXXXXX") || return 1
  (cd -P -- "$dir" && pwd -P)
}

# _sem <utilitario...> — cria um PATH em que os utilitarios indicados nao existem
_sem() {
  local -a ausentes=("$@")
  local dir alvo faltante
  dir=$(_area)/bin
  mkdir -p "$dir"
  # `timeout` e os utilitarios usados pela propria sonda precisam existir no
  # PATH reduzido, senao a sonda mede a si mesma em vez do componente.
  for alvo in bash curl sha256sum shasum openssl timeout env head wc mktemp stat \
    readlink find tr grep cat chmod mv rm mkdir dirname basename sed seq awk od tail df sleep ln rmdir; do
    for faltante in "${ausentes[@]}"; do
      [[ $alvo == "$faltante" ]] && continue 2
    done
    local origem
    origem=$(command -v "$alvo" 2>/dev/null) || continue
    ln -sf "$origem" "$dir/$alvo"
  done
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Contrato de status
# ---------------------------------------------------------------------------

teste_status_segue_a_taxonomia_de_erro() {
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$DBX_PREFLIGHT_ERRO_CONFIGURACAO"
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$DBX_PREFLIGHT_ERRO_USO"
}

teste_ambiente_saudavel_e_aprovado() {
  assert_sucesso dbx_preflight_verificar
  assert_igual '' "$DBX_PREFLIGHT_MOTIVO"
}

# ---------------------------------------------------------------------------
# Dependencias externas: apenas cURL e utilitario de resumo (DP-08)
# ---------------------------------------------------------------------------

teste_curl_ausente_e_recusado_nomeando_o_utilitario() {
  local caminho status saida
  caminho=$(_sem curl)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar 2>&1
    printf "|%s|%s|%s" "$?" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  status=${saida#*|}
  status=${status%%|*}
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$status"
  assert_contem 'curl' "$saida" 'RNF-02 exige nomear o utilitario ausente'
}

teste_utilitario_de_resumo_ausente_e_recusado() {
  local caminho saida
  # Precisa remover TODOS: lib/hash aceita mais de um utilitario de resumo, e
  # deixar um deles no PATH faria a sonda medir outra coisa.
  caminho=$(_sem sha256sum shasum openssl)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar 2>&1
    printf "|%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem "|$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$saida" \
    'sem utilitario de resumo nao ha content_hash, e RF-34 fica inviavel'
}

teste_jq_nao_e_exigido() {
  # DP-08: dependencia externa unica e o cURL. Exigir jq contrariaria a decisao.
  local achados
  achados=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/preflight.sh" |
    grep -nE '(^|[^_a-zA-Z.])jq([^_a-zA-Z]|$)' || true)
  assert_igual '' "$achados" "preflight exige jq: $achados"
}

# _deteccao_fora_do_ponto_unico <arquivo...> — `uname`, `OSTYPE` e `MACHTYPE`
# fora de comentario e fora do corpo de `dbx_preflight_plataforma`.
_deteccao_fora_do_ponto_unico() {
  awk '
    /^dbx_preflight_plataforma\(\) \{/ { dentro = 1 }
    dentro { if ($0 ~ /^\}/) dentro = 0; next }
    /^[[:space:]]*#/ { next }
    /(^|[^A-Za-z0-9_])(uname|OSTYPE|MACHTYPE)([^A-Za-z0-9_]|$)/ { print FILENAME ":" FNR ": " $0 }
  ' "$@"
}

teste_deteccao_de_plataforma_so_no_ponto_unico() {
  # DP-07 reaberta (secao 5.22, DIV-356): a deteccao e liberada, mas num ponto
  # unico. Ramificar por sistema espalhado pelo codigo recriaria a camada de
  # compatibilidade que a decisao original removeu.
  local area mutacao achados
  area=$(mktemp -d "$DBX_TESTES_TMP/ponto.XXXXXX")
  printf '%s\n' 'sistema=$(uname -s)' >"$area/uname.sh"
  printf '%s\n' '[[ $OSTYPE == freebsd* ]] && x=1' >"$area/ostype.sh"
  printf '%s\n' 'arq=$MACHTYPE' >"$area/machtype.sh"
  for mutacao in uname ostype machtype; do
    [[ -n $(_deteccao_fora_do_ponto_unico "$area/$mutacao.sh") ]] ||
      _harness_falhar "a auditoria nao acusou a forma '$mutacao'"
  done
  printf '%s\n' '# uname em comentario' 'dbx_preflight_plataforma() {' \
    '  sistema=$(uname -s)' '}' 'x=1' >"$area/permitido.sh"
  assert_igual '' "$(_deteccao_fora_do_ponto_unico "$area/permitido.sh")" \
    'comentario e corpo do ponto unico nao sao acusados'
  achados=$(_deteccao_fora_do_ponto_unico "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh \
    "$DBX_HARNESS_RAIZ/bin/dbx" "$DBX_HARNESS_RAIZ/install.sh" "$DBX_HARNESS_RAIZ/uninstall.sh")
  assert_igual '' "$achados" "deteccao de plataforma fora de dbx_preflight_plataforma: $achados"
}

# ---------------------------------------------------------------------------
# Piso de bash 4.4 (DP-07, RNF-01 descongelado)
# ---------------------------------------------------------------------------

teste_versao_de_bash_abaixo_do_piso_e_recusada() {
  local saida
  saida=$(timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_versao_de_bash_suficiente 4 1 && printf "aceitou-4.1"
    dbx_preflight_versao_de_bash_suficiente 3 2 && printf "aceitou-3.2"
    dbx_preflight_versao_de_bash_suficiente 4 3 && printf "aceitou-4.3"
    dbx_preflight_versao_de_bash_suficiente 4 4 || printf "recusou-4.4"
    dbx_preflight_versao_de_bash_suficiente 5 3 || printf "recusou-5.3"
    printf "ok"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual 'ok' "$saida" \
    'o piso e 4.4: RHEL 6 com 4.1 fica fora, e 4.3 nao tem nameref'
}

teste_piso_declarado_e_o_verificado() {
  assert_igual '4' "$DBX_PREFLIGHT_BASH_MAIOR"
  assert_igual '4' "$DBX_PREFLIGHT_BASH_MENOR"
}

# ---------------------------------------------------------------------------
# Area temporaria
# ---------------------------------------------------------------------------

teste_area_temporaria_inexistente_e_recusada() {
  local saida
  saida=$(TMPDIR=/caminho/que/nao/existe timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s|%s|%s" "$?" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|" "$saida"
  assert_contem 'temporaria' "$saida" 'o motivo precisa apontar o host, nao a Dropbox'
}

teste_area_temporaria_somente_leitura_e_recusada() {
  local area saida
  area=$(_area)/somente_leitura
  mkdir -p "$area"
  chmod 500 "$area"
  saida=$(TMPDIR="$area" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  chmod 700 "$area"
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$saida" \
    'sem escrita em area temporaria o envio em partes fica inviavel'
}

# ---------------------------------------------------------------------------
# Diretorio de configuracao (RNF-04)
# ---------------------------------------------------------------------------

teste_xdg_invalido_e_recusado() {
  local saida
  saida=$(XDG_CONFIG_HOME='relativo' timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s" "$?"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" "$saida"
}

teste_permissao_da_credencial_e_verificada_no_preflight() {
  # DP-11 exige a verificacao AQUI, e nao apenas na leitura.
  local area saida
  area=$(_area)
  mkdir -p "$area/config/dbx"
  printf '{}' >"$area/config/dbx/credencial.json"
  chmod 644 "$area/config/dbx/credencial.json"
  saida=$(XDG_CONFIG_HOME="$area/config" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_verificar >/dev/null 2>&1
    printf "%s|%s|%s" "$?" "$DBX_PREFLIGHT_MOTIVO" "$DBX_PREFLIGHT_DETALHE"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|" "$saida"
  assert_contem 'permissao' "$saida"
}

teste_credencial_ausente_nao_reprova_o_preflight() {
  # Ambiente sem credencial e o estado normal antes da configuracao inicial: o
  # preflight verifica o AMBIENTE, e quem exige credencial e o comando.
  local area
  area=$(_area)
  XDG_CONFIG_HOME="$area/config" assert_sucesso dbx_preflight_verificar
}

# ---------------------------------------------------------------------------
# Diagnostico nao vaza segredo
# ---------------------------------------------------------------------------

teste_diagnostico_do_preflight_nao_ecoa_conteudo_da_credencial() {
  local area saida
  area=$(_area)
  mkdir -p "$area/config/dbx"
  printf '{"refresh_token":"RT9pQrSecretoTotal"}' >"$area/config/dbx/credencial.json"
  chmod 644 "$area/config/dbx/credencial.json"
  saida=$(XDG_CONFIG_HOME="$area/config" dbx_preflight_verificar 2>&1 || true)
  assert_nao_contem 'RT9pQrSecretoTotal' "$saida"
}

# ---------------------------------------------------------------------------
# P3-02 — RNF-02 exige NOMEAR o utilitario ausente, para todos eles
# ---------------------------------------------------------------------------

teste_todo_utilitario_ausente_reprova_e_e_nomeado() {
  local utilitario caminho saida
  for utilitario in mktemp mv rm chmod mkdir stat head wc readlink dirname ln; do
    caminho=$(_sem "$utilitario")
    saida=$(PATH="$caminho" timeout 30 bash -c '
      . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
      dbx_preflight_verificar >/dev/null 2>&1
      printf "%s|%s" "$?" "$DBX_PREFLIGHT_DETALHE"
    ' _ "$DBX_HARNESS_RAIZ" 2>&1)
    assert_contem "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|" "$saida" \
      "ambiente sem $utilitario foi aprovado pelo preflight"
    assert_contem "$utilitario" "$saida" \
      "RNF-02 exige nomear o utilitario ausente: $utilitario"
  done
}

teste_inspecao_sem_parada_nomeia_cada_ausente() {
  # RF-66(a)(e): o `diagnostico` nao para no primeiro item. A lista e a MESMA do
  # preflight, perguntada a ele, e a inspecao so usa o proprio shell.
  local caminho saida
  caminho=$(_sem stat mktemp readlink)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_ausentes
    printf "%s|%s" "$?" "${DBX_PREFLIGHT_AUSENTES[*]}"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO|mktemp stat readlink" "$saida" \
    'cada ausente nomeado, na ordem da lista do preflight'
  caminho=$(_sem)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_ausentes
    printf "%s|%s" "$?" "${DBX_PREFLIGHT_AUSENTES[*]}"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual '0|' "$saida" 'ambiente completo: nada ausente'
}

teste_inspecao_sem_parada_inclui_o_resumo_sha256() {
  local caminho saida
  caminho=$(_sem sha256sum shasum openssl)
  saida=$(PATH="$caminho" timeout 30 bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/preflight.sh"
    dbx_preflight_ausentes
    printf "%s" "${DBX_PREFLIGHT_AUSENTES[*]}"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_contem 'sha256sum' "$saida" 'a falta do utilitario de resumo e nomeada'
}

# _comandos_externos_de <arquivo...> — candidatos a comando externo, extraidos
# do TEXTO do codigo, e nao de uma lista de nomes conhecidos.
#
# Descarta, nesta ordem: comentarios, literais entre aspas (conteudo de mensagem
# nao e codigo) e rotulos de `case`. Depois toma a palavra em POSICAO DE
# COMANDO: inicio de linha ou apos separador de comando, seguida de espaco ou
# fim de linha. Invocacao por caminho absoluto e reduzida ao nome do utilitario.
# _palavras_que_abrem_comando — derivadas da GRAMATICA, e nao do idioma que o
# autor usa.
#
# O universo sao as palavras reservadas do PROPRIO shell. Mantem-se a mao apenas
# a lista das que NAO sao seguidas de comando — terminadores, e as que tomam
# nome ou padrao em vez de comando. A inversao e a mesma ja aplicada duas vezes
# neste arquivo, agora no reconhecedor de POSICAO DE COMANDO.
#
# Era aqui que a tese ainda falhava: a amostra anterior nascera das formas que o
# codigo do projeto usa — `then`, `do`, `else` —, e a gramatica contem formas
# que ele nao usava. `if`, `while`, `until` e `time` escapavam; `elif` e `!`
# eram detectados por acidente, por ja constarem da lista de separadores.
_palavras_que_abrem_comando() {
  local nao_introduzem=' fi done esac case for select in function } [[ ]] '
  local palavra
  while IFS= read -r palavra; do
    [[ $palavra =~ ^[a-z]+$ ]] || continue
    [[ $nao_introduzem == *" $palavra "* ]] && continue
    printf '%s\n' "$palavra"
  done < <(compgen -k)
}

_comandos_externos_de() {
  local abrem='' palavra
  # Alternacao montada sem utilitario externo: a auditoria nao pode depender de
  # um comando que ela propria teria de exigir.
  while IFS= read -r palavra; do
    abrem+="${abrem:+|}$palavra"
  done < <(_palavras_que_abrem_comando)
  # Descarta, nesta ordem: comentarios; literais entre aspas, porque conteudo de
  # mensagem nao e codigo; BLOCOS DE LITERAL DE VETOR, cujas linhas de
  # continuacao sao indistinguiveis de linhas de comando; e rotulos de `case`.
  #
  # Depois NORMALIZA: todo separador de comando e toda palavra reservada que
  # abre lista vira quebra de linha, e o primeiro campo de cada linha resultante
  # e a posicao de comando. Ancorar a expressao no separador nao servia: a
  # propria ancora consumia a correspondencia e o comando seguinte ficava de
  # fora — era por isso que `then`, `do`, `else` e abertura de bloco eram cegos
  # (R3-01), e as tres primeiras sao idiomaticas, nao estilo de conveniencia.
  sed -e 's/^[[:space:]]*#.*//' -e "s/'[^']*'/ /g" -e 's/"[^"]*"/ /g' "$@" |
    awk '
      # Saldo de parenteses da linha (as aspas ja sairam). O bloco termina
      # quando o saldo volta a zero, e NAO na proxima linha que comeca com `)`:
      # um vetor aberto e fechado na mesma linha (`x=()`, `x=(a b)`) nao abre
      # bloco nenhum. Com a regra antiga, cada `x=()` cegava a auditoria ate
      # o fim do arquivo ou o proximo `)` em inicio de linha (QA, fase 2).
      #
      # Antes do saldo, sai o que nao e posicao de comando e so ficava oculto
      # pela cegueira: expansao `${...}` (inclusive `${!nome-}`), aritmetica
      # `((...))`, descritor nomeado `{fd}<` e redirecao (`2>/dev/null`, `<&3`).
      # Vetor de uma linha (`x=(a b)`, `x+=(a)`) vira so `=`: o conteudo e dado.
      function limpar(s,   antes) {
        do { antes = s; gsub(/\$\{[^{}]*\}/, " ", s) } while (s != antes)
        do { antes = s; gsub(/\(\([^()]*\)\)/, " ", s) } while (s != antes)
        gsub(/\{[A-Za-z_][A-Za-z0-9_]*\}[<>]/, " ", s)
        gsub(/[0-9]*[<>]+&?[^[:space:];|&()]*/, " ", s)
        return s
      }
      function saldo(s,   t, abre, fecha) {
        t = s; abre = gsub(/\(/, "", t)
        t = s; fecha = gsub(/\)/, "", t)
        return abre - fecha
      }
      { $0 = limpar($0) }
      dentro { profundidade += saldo($0); if (profundidade <= 0) dentro = 0; next }
      /^[[:space:]]*(declare[[:space:]]+-[a-zA-Z]+[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?=\(/ {
        profundidade = saldo(substr($0, index($0, "=(")))
        if (profundidade > 0) { dentro = 1; next }
      }
      { gsub(/[A-Za-z0-9_\]][+]?=\([^()]*\)/, "= "); print }
    ' |
    grep -vE '^[[:space:]]*[^|&;()]+([[:space:]]*\|[[:space:]]*[^|&;()]+)*[[:space:]]*\)' |
    sed -E -e 's/&&/\n/g' -e 's/\|\|/\n/g' -e 's/[;&|(){}!]/\n/g' \
      -e "s/\\<($abrem)\\>/\n/g" |
    awk '{ print $1 }' |
    grep -vE '[$:=]' |
    sed 's|.*/||' |
    grep -E '^[a-z][a-z0-9_-]*$' |
    sort -u
}

# _nomes_de_variavel_de <arquivo...> — nomes atribuidos no proprio codigo.
# Derivado, e nao listado: e o que remove `indice`, `posicao`, `alto` e afins,
# que aparecem em posicao de comando dentro de expressao aritmetica.
_nomes_de_variavel_de() {
  {
    grep -ohE '(^|[[:space:](])(local[[:space:]]+)?[a-z_][a-z0-9_]*=' "$@" |
      tr -d ' (' | sed 's/=$//'
    grep -ohE 'for[[:space:]]*\(\([[:space:]]*[a-z_][a-z0-9_]*' "$@" |
      sed 's/.*[( ]//'
    grep -ohE 'local[[:space:]]+[a-z_ ]+' "$@" | sed 's/local[[:space:]]*//' | tr ' ' '\n'
  } 2>/dev/null | grep -E '^[a-z_][a-z0-9_]*$' | sort -u
}

# _vocabulario_de_argumento_de <arquivo...> — palavras passadas como ARGUMENTO
# a funcoes do projeto. Tambem derivado do codigo: sao termos do dominio, como
# nomes de tipo e de classe, que aparecem em posicao de comando apenas quando a
# linha e reescrita pela normalizacao.
_vocabulario_de_argumento_de() {
  grep -ohE '(_dbx_|dbx_)[a-z_]+([[:space:]]+[^|&;()#]*)?' "$@" |
    sed -E 's/^[^[:space:]]+[[:space:]]*//' |
    tr ' ' '\n' |
    grep -E '^[a-z][a-z0-9_-]*$' |
    sort -u
}

# _nao_e_comando_externo <palavra> <nomes_de_variavel> <vocabulario>
_nao_e_comando_externo() {
  local palavra=$1 variaveis=$2 vocabulario=${3-}
  [[ -n $vocabulario ]] && grep -qxF "$palavra" <<<"$vocabulario" && return 0
  [[ $palavra == dbx_* || $palavra == _dbx_* ]] && return 0
  compgen -b | grep -qxF "$palavra" && return 0
  compgen -k | grep -qxF "$palavra" && return 0
  grep -qxF "$palavra" <<<"$variaveis" && return 0
  # Unica lista mantida a mao, e de EXCECOES. Manter excecoes e barato e
  # visivel; manter o universo de nomes possiveis e impossivel — foi essa
  # inversao que faltou na versao anterior desta auditoria.
  #
  # `sha256sum`, `openssl` e `shasum` sao membros da familia de resumo, cuja
  # presenca e
  # verificada em conjunto por `dbx_hash_verificar_dependencias`, e nao
  # individualmente: exigir os tres reprovaria ambiente que tem apenas um.
  local excecoes=' sudo env sha256sum openssl shasum '
  [[ $excecoes == *" $palavra "* ]] && return 0
  return 1
}

teste_todo_comando_externo_de_lib_e_exigido_pelo_preflight() {
  # ESCOPO DERIVADO DO CODIGO. A versao anterior comparava contra uma lista fixa
  # de vinte nomes escrita no proprio teste, e portanto era circular: o cenario
  # que o comentario declarava cobrir — a biblioteca invocar um utilitario NOVO
  # — nao era detectado, porque o nome novo nao estava na lista de busca.
  local comando faltantes='' variaveis vocabulario
  variaveis=$(_nomes_de_variavel_de "$DBX_HARNESS_RAIZ"/lib/*.sh)
  vocabulario=$(_vocabulario_de_argumento_de "$DBX_HARNESS_RAIZ"/lib/*.sh)
  while IFS= read -r comando; do
    [[ -n $comando ]] || continue
    _nao_e_comando_externo "$comando" "$variaveis" "$vocabulario" && continue
    case " $DBX_PREFLIGHT_UTILITARIOS " in *" $comando "*) continue ;; esac
    faltantes+=" $comando"
  done < <(_comandos_externos_de "$DBX_HARNESS_RAIZ"/lib/*.sh)
  assert_igual '' "$faltantes" \
    "comandos externos invocados por lib/ e nao exigidos pelo preflight:$faltantes"
}

teste_auditoria_de_comandos_enxerga_utilitario_fora_de_qualquer_lista() {
  # RSK-27, forma NAO OBVIA: a forma obvia — reduzir a lista do preflight — ja
  # era detectada. A que faltava era a biblioteca passar a invocar algo novo.
  local amostra extraidos
  amostra=$(mktemp "$DBX_TESTES_TMP/amostra.XXXXXX")
  # As QUATRO formas de posicao de comando, e nao apenas a de linha propria: as
  # tres que faltavam — apos abertura de bloco, apos `then` e apos `do` — sao
  # idiomaticas, e nao estilo de conveniencia. A amostra cobre todas para que a
  # correcao nasca pinada.
  {
    printf '%s\n' 'saida=$(cut -d: -f1 "$arquivo")'
    printf '%s\n' '/usr/bin/paste "$a" "$b"'
    printf '%s\n' 'date +%s'
    printf '%s\n' 'if [[ -n $1 ]]; then touch "$a"; fi'
    printf '%s\n' 'for _x in a; do du -sh "$a"; done'
    printf '%s\n' 'if [[ -n $1 ]]; then :; else expr 1 + 1; fi'
    printf '%s\n' '{ sort "$a"; }'
  } >"$amostra"
  extraidos=$(_comandos_externos_de "$amostra")
  rm -f "$amostra"
  local esperado
  for esperado in cut paste date touch du expr sort; do
    assert_contem "$esperado" "$extraidos" \
      "a extracao precisa enxergar '$esperado', que nao consta de lista alguma"
  done
}

teste_auditoria_de_comandos_nao_fica_cega_depois_de_vetor_de_uma_linha() {
  # Vetor aberto e fechado na MESMA linha (`x=()`, `x=(a b) y=$z`) nao abre
  # bloco de literal: o comando nas linhas seguintes e enxergado. O bloco de
  # varias linhas continua descartado ate o saldo de parenteses voltar a zero,
  # inclusive com `)` que nao comeca a linha.
  local amostra extraidos
  amostra=$(mktemp "$DBX_TESTES_TMP/amostra.XXXXXX")
  {
    printf '%s\n' 'lista=()'
    printf '%s\n' 'cut -d: -f1 "$a"'
    printf '%s\n' '  segmentos=() resto=$campo'
    printf '%s\n' '  paste "$a" "$b"'
    printf '%s\n' 'declare -ga VETOR=(um dois)'
    printf '%s\n' 'expr 1 + 1'
    printf '%s\n' 'BLOCO=('
    printf '%s\n' '  falsopositivo'
    printf '%s\n' '  outrofalso)'
    printf '%s\n' 'touch "$a"'
  } >"$amostra"
  extraidos=$(_comandos_externos_de "$amostra")
  rm -f "$amostra"
  local esperado
  for esperado in cut paste expr touch; do
    assert_contem "$esperado" "$extraidos" "comando depois de vetor de uma linha: '$esperado'"
  done
  assert_nao_contem 'falsopositivo' "$extraidos" 'linha de continuacao do bloco de varias linhas'
  assert_nao_contem 'outrofalso' "$extraidos" 'ultima linha do bloco, fechada sem `)` no inicio'
}

teste_auditoria_de_comandos_ignora_o_que_nao_e_comando() {
  # Falso positivo tambem e defeito: uma auditoria que reprova por engano deixa
  # de ser consultada.
  local amostra extraidos
  amostra=$(mktemp "$DBX_TESTES_TMP/amostra.XXXXXX")
  {
    printf '%s\n' "  [configuracao]='Verifique o arquivo; consulte a ajuda'"
    printf '%s\n' '      app_key) DBX_CONFIG_APP_KEY=$valor ;;'
    printf '%s\n' '  # comentario com sudo e rm dentro'
    printf '%s\n' '  local caminho=$1'
  } >"$amostra"
  extraidos=$(_comandos_externos_de "$amostra")
  rm -f "$amostra"
  local proibido
  for proibido in consulte app_key caminho; do
    assert_nao_contem "$proibido" "$extraidos" \
      "'$proibido' nao e comando externo e nao pode ser extraido"
  done
}


# ---------------------------------------------------------------------------
# TL-27 — posicao de comando derivada da GRAMATICA, nao do idioma observado
# ---------------------------------------------------------------------------

teste_palavras_que_abrem_comando_vem_da_gramatica_do_shell() {
  # O universo precisa vir do proprio shell. Se alguem substituir a derivacao
  # por uma lista, uma palavra reservada nova ou nao antecipada volta a escapar.
  local derivadas palavra
  derivadas=$(_palavras_que_abrem_comando)
  for palavra in 'if' 'while' 'until' 'time' 'then' 'do' 'else' 'elif'; do
    assert_contem "$palavra" "$derivadas" \
      "'$palavra' abre comando e precisa sair da gramatica, nao de lista"
  done
  # E as que NAO abrem comando precisam ficar de fora, senao a normalizacao
  # quebra construcoes legitimas.
  for palavra in 'fi' 'done' 'esac' 'case' 'for' 'select' 'function'; do
    if grep -qx "$palavra" <<<"$derivadas"; then
      _harness_falhar "'$palavra' nao introduz comando e nao pode virar ponto de corte"
    fi
  done
}

teste_extracao_enxerga_comando_apos_cada_palavra_que_abre() {
  # As quatro formas que escapavam — `if`, `while`, `until`, `time` — mais as
  # que ja funcionavam. A amostra anterior nascera das formas que o proprio
  # codigo usa, e a gramatica contem formas que ele nao usava: era essa a causa
  # comum dos quatro niveis em que a inversao faltou.
  local amostra extraidos esperado
  amostra=$(mktemp "$DBX_TESTES_TMP/gram.XXXXXX")
  {
    printf '%s\n' 'if cut -d: -f1 /dev/null; then :; fi'
    printf '%s\n' 'while paste /dev/null; do break; done'
    printf '%s\n' 'until du -sh /tmp; do break; done'
    printf '%s\n' 'time expr 1 + 1'
    printf '%s\n' 'if true; then sort /dev/null; fi'
    printf '%s\n' 'for _x in 1; do touch /dev/null; done'
  } >"$amostra"
  extraidos=$(_comandos_externos_de "$amostra")
  rm -f "$amostra"
  for esperado in cut paste du expr sort touch; do
    assert_contem "$esperado" "$extraidos" \
      "comando apos palavra que abre lista precisa ser visto: $esperado"
  done
}

# ---------------------------------------------------------------------------
# TL-30 — a biblioteca nao pode depender de utilitario externo para CARREGAR
# ---------------------------------------------------------------------------

teste_biblioteca_carrega_sem_utilitario_externo_algum() {
  # Antes, os componentes resolviam o proprio diretorio com `dirname` na carga,
  # antes de qualquer verificacao: sem ele carregavam com status 0 e QUEBRADOS —
  # dependencias nunca carregadas e constantes de codigo de erro vazias.
  local vazio saida
  vazio="$DBX_TESTES_TMP/vazio.$$"
  mkdir -p "$vazio"
  # `timeout` fica FORA do PATH esvaziado, senao a sonda mede a si mesma — a
  # armadilha ja registrada duas vezes neste arquivo.
  saida=$(timeout 30 env PATH="$vazio" "$BASH" -c '
    . "$1/lib/errors.sh" || exit 1
    . "$1/lib/json.sh"   || exit 2
    . "$1/lib/config.sh" || exit 3
    . "$1/lib/preflight.sh" || exit 4
    printf "%s|%s|%s" "$DBX_CONFIG_ERRO_CONFIGURACAO" "$DBX_JSON_ERRO_REMOTO" "$DBX_PREFLIGHT_ERRO_CONFIGURACAO"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  rmdir "$vazio" 2>/dev/null
  assert_igual '3|10|3' "$saida" \
    'sem utilitario externo no PATH a carga precisa funcionar e as constantes precisam valer'
}


# ---------------------------------------------------------------------------
# O NIVEL E PARAMETRO — e o par abaixo e o que prova que ele funciona
#
# `lib/cli` justifica os tres niveis dizendo que, sem eles, o assistente de
# configuracao ficaria impossivel de usar exatamente quando e necessario. A regra
# estava escrita la e nao estava aplicada aqui: esta funcao inspecionava a
# credencial em qualquer nivel. Ninguem viu porque os seis comandos do bloco
# anterior declaram `credencial`, e o conjunto onde a distincao incide estava
# vazio.
#
# Os dois casos andam juntos de proposito. Sozinho, o primeiro passaria com uma
# funcao que nunca reprova nada; sozinho, o segundo passaria com a versao
# defeituosa. E o par que discrimina.
# ---------------------------------------------------------------------------

_credencial_em() { # <area> <modo>
  local area=$1 modo=$2
  mkdir -p "$area/dbx"
  chmod 700 "$area/dbx"
  printf '%s' '{"versao":1,"app_key":"AK","app_secret":"AS","refresh_token":"RT","raiz_remota":"/"}' \
    >"$area/dbx/credencial.json"
  chmod "$modo" "$area/dbx/credencial.json"
}

teste_nivel_ambiente_nao_recusa_por_permissao_de_credencial() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/nivel.XXXXXX")
  _credencial_em "$area" 644
  XDG_CONFIG_HOME=$area dbx_preflight_verificar ambiente
  assert_igual 0 $? \
    'credencial larga nao pode impedir o comando que existe para regrava-la'
}

teste_nivel_credencial_continua_recusando_permissao_larga() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/nivel.XXXXXX")
  _credencial_em "$area" 644
  XDG_CONFIG_HOME=$area dbx_preflight_verificar credencial
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" $? \
    'RNF-04 manda RECUSAR, e nao alertar, quando a credencial esta em permissao larga'
}

teste_omissao_de_nivel_assume_o_mais_estrito() {
  # Recuo para o nivel fraco transformaria esquecimento de argumento em
  # afrouxamento silencioso de verificacao de seguranca.
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/nivel.XXXXXX")
  _credencial_em "$area" 644
  XDG_CONFIG_HOME=$area dbx_preflight_verificar
  assert_igual "$DBX_PREFLIGHT_ERRO_CONFIGURACAO" $? \
    'sem argumento a verificacao precisa valer pelo nivel mais estrito'
}

teste_nivel_fora_do_vocabulario_e_recusado() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/nivel.XXXXXX")
  _credencial_em "$area" 600
  XDG_CONFIG_HOME=$area dbx_preflight_verificar quase_credencial
  assert_igual "$DBX_PREFLIGHT_ERRO_USO" $? \
    'nivel desconhecido e erro de uso, e nao aprovacao'
}

# ---------------------------------------------------------------------------
# Fase 3 — sem `sqlite3`/`python3` (RNF-02 emendado) e sem `lib/db` (RNF-33)
# ---------------------------------------------------------------------------

# _codigo_do_produto — os arquivos que a auditoria cobre (scripts de governanca
# em `scripts/` ficam fora, RNF-02(a)).
_codigo_do_produto() {
  printf '%s\n' "$DBX_HARNESS_RAIZ/bin/dbx" "$DBX_HARNESS_RAIZ"/lib/*.sh "$DBX_HARNESS_RAIZ"/commands/*.sh
}

# _interpretadores_em <arquivo...> — mencao a `sqlite3` ou `python3` fora de
# comentario, em QUALQUER posicao (o nome atribuido a variavel conta, porque e
# a forma de esconder a invocacao), e invocacao de interpretador por variavel
# com `-c`, que e a forma nao obvia de executar codigo de outra linguagem.
_interpretadores_em() {
  grep -nE '(^|[^A-Za-z0-9_])(sqlite3?|python[0-9.]*)([^A-Za-z0-9_]|$)|"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"[[:space:]]+-c([[:space:]]|$)' "$@" |
    grep -vE '^[0-9]+:[[:space:]]*#' || true
}

teste_nenhum_codigo_do_produto_invoca_sqlite3_nem_python3() {
  # TC-DEP-01 (RNF-02(a)), com prova de discriminacao (RSK-27): cada forma nao
  # obvia precisa ser acusada antes de a varredura valer.
  local area mutacao arquivo achados=''
  area=$(mktemp -d "$DBX_TESTES_TMP/dep.XXXXXX")
  printf '%s\n' 'motor=python3' 'x=$("$motor" -c "print(1)")' >"$area/variavel.sh"
  printf '%s\n' 'if command -v sqlite3 >/dev/null; then :; fi' >"$area/command_v.sh"
  printf '%s\n' 'interp=$1' '"$interp" -c "$programa"' >"$area/interp_c.sh"
  printf '%s\n' 'printf "%s" "$sql" | sqlite3 "$db"' >"$area/direto.sh"
  for mutacao in variavel command_v interp_c direto; do
    [[ -n $(_interpretadores_em "$area/$mutacao.sh") ]] ||
      _harness_falhar "a auditoria nao acusou a forma '$mutacao'"
  done
  printf '%s\n' '# sqlite3 em comentario nao e invocacao' 'printf "%s" ok' >"$area/limpo.sh"
  assert_igual '' "$(_interpretadores_em "$area/limpo.sh")" 'comentario nao e acusado'
  while IFS= read -r arquivo; do
    achados+=$(_interpretadores_em "$arquivo" | sed "s|^|${arquivo##*/}:|")
  done < <(_codigo_do_produto)
  assert_igual '' "$achados" "interpretador no codigo do produto: $achados"
}

teste_preflight_nao_lista_nem_sonda_sqlite3_e_python3() {
  # TC-DEP-02 (RNF-02(b)).
  case " $DBX_PREFLIGHT_UTILITARIOS " in
    *' sqlite3 '* | *' python3 '* | *' python '*)
      _harness_falhar "lista do preflight cita interpretador: $DBX_PREFLIGHT_UTILITARIOS" ;;
  esac
  assert_igual '' "$(_interpretadores_em "$DBX_HARNESS_RAIZ/lib/preflight.sh")" 'nem sonda'
  local utilitario
  for utilitario in stat readlink find mktemp mv; do
    case " $DBX_PREFLIGHT_UTILITARIOS " in
      *" $utilitario "*) ;;
      *) _harness_falhar "o cache usa $utilitario e ele precisa constar do preflight" ;;
    esac
  done
}

teste_lib_db_e_suas_chamadas_nao_existem_mais() {
  # TC-LEG-01 (RNF-33(a)).
  assert_arquivo_ausente "$DBX_HARNESS_RAIZ/lib/db.sh" 'lib/db.sh removido'
  local achados
  achados=$(_codigo_do_produto | xargs grep -nE 'dbx_db_|DBX_DB_|dbx\.db|lib/db\.sh' || true)
  assert_igual '' "$achados" "referencia ao lib/db no codigo do produto: $achados"
}

teste_instalador_nao_detecta_nem_recomenda_sqlite3() {
  # TC-LEG-03 (RNF-33(d)).
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/install.sh" 'sem o instalador a auditoria seria vacua'
  assert_igual '' "$(grep -niE 'sqlite|python' "$DBX_HARNESS_RAIZ/install.sh" || true)" \
    'o install.sh nao detecta nem recomenda sqlite3'
}

teste_canal_de_hash_do_envio_por_sessao_tem_nome_unico() {
  # RF-61(j), F-29: o canal e DBX_TRANSFER_CONTENT_HASH; o nome antigo, que nao
  # existia, fazia o hash da sessao nunca chegar ao cache.
  local achados
  achados=$(_codigo_do_produto | xargs grep -nE 'DBX_TRANSFER_HASH([^_A-Z]|$)' || true)
  assert_igual '' "$achados" "canal inexistente referenciado: $achados"
}

# ---------------------------------------------------------------------------
# TC-DOC-01 (RNF-34(c), RNF-02): o README e o preflight nomeiam os mesmos
# utilitarios. O preflight e quem diz ao operador o que falta; um README que
# lista outra coisa manda instalar o que nao e preciso e omite o que e.
# ---------------------------------------------------------------------------

# _utilitarios_do_readme — nomes entre crases da linha "Utilitarios" da secao
# "Requisitos do Sistema", um por linha, ordenados.
_utilitarios_do_readme() {
  local linha
  linha=$(grep -m1 -E '^- \*\*Utilit' "$DBX_HARNESS_RAIZ/README.md") || return 0
  grep -oE '`[a-z0-9]+`' <<<"$linha" | tr -d '`' | sort -u
}

teste_lista_de_utilitarios_do_readme_e_a_do_preflight() {
  # O `cURL` tem linha propria ("Rede"); a familia de resumo SHA-256 e verificada
  # em conjunto por `lib/hash`, entao entra pelos tres nomes que ele aceita.
  local esperado obtido
  esperado=$({
    tr ' ' '\n' <<<"$DBX_PREFLIGHT_UTILITARIOS"
    printf '%s\n' sha256sum shasum openssl
  } | grep -vx -e curl -e '' | sort -u)
  obtido=$(_utilitarios_do_readme)
  assert_diferente '' "$obtido" 'o README precisa trazer a linha de utilitarios'
  assert_igual "$esperado" "$obtido" 'README e preflight listam os mesmos utilitarios'
}

teste_preflight_exige_os_utilitarios_do_diagnostico_do_config() {
  # `commands/config.sh` invoca `df` e `tail` no diagnostico de `--debug`; a
  # auditoria de comandos externos so varre `lib/`, entao o par e fixado aqui.
  local utilitario
  for utilitario in df tail; do
    grep -qE "(^|[|(;&[:space:]])${utilitario}[[:space:]]" "$DBX_HARNESS_RAIZ/commands/config.sh" ||
      _harness_falhar "commands/config.sh nao invoca mais $utilitario: revise este caso"
    case " $DBX_PREFLIGHT_UTILITARIOS " in
      *" $utilitario "*) ;;
      *) _harness_falhar "commands/config.sh invoca $utilitario e o preflight nao o exige" ;;
    esac
  done
}

harness_executar "$@"
