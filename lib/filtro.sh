#!/usr/bin/env bash
# lib/filtro.sh — escopo de caminho, data e tamanho (RF-79, RF-80(a), RF-81).
#
# Camada: dominio. Depende so de lib/errors.sh.
#
# PURO (DIV-94): nao chama rede, nao le nem escreve disco, nao guarda estado
# entre execucoes e nao invoca utilitario externo. Os padroes vivem so na
# memoria do processo e vem da linha de comando de CADA execucao — e por isso
# que a guarda que impede apagar item filtrado (RF-80(d)) nao depende de estado
# local nenhum. Consumido por lib/walk (poda da descida), lib/sync (descarte
# remoto, contagens) e pelos comandos (validacao das opcoes).
#
# O PADRAO E DADO, NUNCA CODIGO (RF-79(l))
#
#   Cada padrao e traduzido caractere a caractere para uma expressao regular
#   estendida, com todo metacaractere da regex escapado; os curingas do padrao
#   (`*`, `?`, `[...]`, `**`) sao os UNICOS que viram construcao da regex. Nao ha
#   `eval` nem expansao de nome de arquivo contra o disco: `$(...)`, crase, `;`,
#   `$VAR` e `~` chegam a comparacao como texto.
#
# SEM CAIXA PELA MESMA CHAVE DO SYNC (RF-54, RF-79(h))
#
#   A chave sem caixa mora aqui (`dbx_filtro_chave`) e `lib/sync` a usa: padrao
#   e caminho passam pela MESMA dobra, e uma segunda copia dela seria o codigo
#   gemeo de RNF-36. A localidade `C.UTF-8` e fixada so dentro da funcao, em
#   `LC_ALL` local (DIV-32): nenhuma medida em bytes do resto do processo muda.
#   Sem a localidade, a dobra fica no ASCII e `?` casa um byte (RF-54(f)).
#
#   Nome que nao e UTF-8 valido (so possivel do lado local) nao casa `.` numa
#   regex sob `C.UTF-8`, e o filtro deixaria de proteger o item (DIV-99). Para
#   ele a comparacao recua para bytes (`LC_ALL=C`), mas com a MESMA dobra do
#   padrao: o caminho e dobrado caractere a caractere sob a localidade UTF-8 (o
#   byte invalido passa como esta), e a regex de bytes, compilada junto com a
#   de caracteres, faz `?` e o conjunto negado casarem uma sequencia UTF-8
#   inteira ou, na falta dela, um byte (QA-B4-01). Conjunto com membro fora do
#   ASCII casa, em bytes, qualquer sequencia multibyte: falha para o lado de
#   casar, nunca de deixar passar.

# shellcheck disable=SC2034
# Justificativa: os `DBX_FILTRO_*` sao canais publicos, lidos por lib/sync,
# lib/walk, lib/cmd e pelos comandos; a analise estatica nao cruza arquivos.

[[ -n ${DBX_FILTRO_CARREGADO:-} ]] && return 0
DBX_FILTRO_CARREGADO=1

DBX_FILTRO_ERRO_USO=$(dbx_errors_codigo_saida uso_invalido)
readonly DBX_FILTRO_ERRO_USO

# Limites de DIV-80: padroes por execucao (as duas opcoes somadas) e bytes por
# padrao. Casar N itens contra M padroes custa N x M regex no shell.
readonly DBX_FILTRO_MAXIMO_PADROES=64
readonly DBX_FILTRO_MAXIMO_BYTES=1024

# Campo da listagem remota que e a data do filtro (RF-81(e), DIV-84): a data em
# que o Dropbox recebeu a versao. Mora AQUI, no dominio do filtro, e nao em
# `lib/sync`: la carimbo de tempo nao participa de decisao alguma (RF-39), e o
# filtro de data so decide ESCOPO da origem — nunca transferencia por
# comparacao, e nunca exclusao (recusado junto de `--espelhar`, RF-81(b)).
readonly DBX_FILTRO_CAMPO_DATA_REMOTA='server_modified'

# Localidade da comparacao sem caixa (RF-54(e)). O nome so e lido do ambiente
# para a suite simular a ausencia sem depender da maquina (TC-CX-05, TC-FLT-11);
# fora do alfabeto de nome de localidade, vale o padrao.
DBX_FILTRO_LOCALIDADE=${DBX_SYNC_LOCALIDADE:-C.UTF-8}
[[ $DBX_FILTRO_LOCALIDADE =~ ^[A-Za-z0-9_.@-]+$ ]] || DBX_FILTRO_LOCALIDADE=C.UTF-8
readonly DBX_FILTRO_LOCALIDADE

# shellcheck disable=SC2034  # canais publicos, lidos por lib/sync, lib/walk e comandos
DBX_FILTRO_CHAVE=''
DBX_FILTRO_MOTIVO=''
DBX_FILTRO_FILTRADO=''
DBX_FILTRO_RAZAO=''
DBX_FILTRO_DATA=''
DBX_FILTRO_BYTES=''
DBX_FILTRO_CARIMBO=''
DBX_FILTRO_DESCRICAO=''
DBX_FILTRO_DESDE=''
DBX_FILTRO_ATE=''
DBX_FILTRO_MIN=''
DBX_FILTRO_MAX=''
# Padroes aceitos, em vetores paralelos: tipo (`excluir`/`incluir`), opcao como
# digitada (para a mensagem) e o texto do padrao.
declare -ga DBX_FILTRO_TIPOS=()
declare -ga DBX_FILTRO_OPCOES=()
declare -ga DBX_FILTRO_PADROES=()
declare -ga DBX_FILTRO_SEM_CASAMENTO=()
# Internos: regex compilada, `sim` quando o padrao casa so pasta (`/` final), e
# `sim` quando o padrao casou algum item nesta execucao (avisos de DIV-91).
declare -ga _dbx_filtro_regex=()
# A mesma regex para a comparacao por bytes (DIV-99, QA-B4-01).
declare -ga _dbx_filtro_regex_b=()
# `sim` quando a regex de bytes do padrao e IMPRECISA (`?`, conjunto negado ou
# com membro fora do ASCII casam a mais). DIV-103 revisada: no --incluir, um
# padrao impreciso nunca casa em bytes — casar a mais poria o item no escopo,
# e o --espelhar o apagaria. No --excluir ele casa (protege a mais).
declare -ga _dbx_filtro_impreciso=()
declare -ga _dbx_filtro_so_pasta=()
declare -ga _dbx_filtro_casou=()
_dbx_filtro_tem_incluir='nao'
_dbx_filtro_falha=''
_dbx_filtro_rx=''
# `sim` quando o ultimo padrao compilado tem ao menos um caractere literal
# (padrao amplo de RF-96(f), DIV-132: so curingas).
_dbx_filtro_literal_visto='nao'
_dbx_filtro_rxb=''
_dbx_filtro_conj=''
_dbx_filtro_conj_b=''
# `caracteres` (regex sob a localidade) ou `bytes` (sob `C`), do caminho corrente.
_dbx_filtro_modo='caracteres'
# Um caractere UTF-8 multibyte, em bytes: byte inicial e continuacoes. Mais
# largo que o UTF-8 estrito de proposito: aqui so se erra para o lado de casar.
_dbx_filtro_seq=$'[\xc0-\xff][\x80-\xbf]*'
_dbx_filtro_sp=''
DBX_FILTRO_CITADO=''

# dbx_filtro_chave <texto> — chave sem caixa em DBX_FILTRO_CHAVE (RF-54).
#
# A Dropbox nao diferencia caixa. Sob `C`, `${x,,}` so converte ASCII e um `É`
# local nao casaria com o `é` remoto; por isso a conversao roda sob a localidade
# UTF-8, em `LC_ALL` LOCAL: ele tem precedencia sobre o que o operador exportou
# (inclusive `LC_ALL=C`) e se desfaz no retorno. Sem a localidade, a atribuicao
# falha em silencio e a conversao fica no ASCII.
dbx_filtro_chave() {
  { local LC_ALL=$DBX_FILTRO_LOCALIDADE; } 2>/dev/null
  DBX_FILTRO_CHAVE=${1,,}
}

# dbx_filtro_limpar — descarta padroes, faixas e marcas da execucao anterior.
dbx_filtro_limpar() {
  DBX_FILTRO_TIPOS=()
  DBX_FILTRO_OPCOES=()
  DBX_FILTRO_PADROES=()
  DBX_FILTRO_SEM_CASAMENTO=()
  _dbx_filtro_regex=()
  _dbx_filtro_regex_b=()
  _dbx_filtro_impreciso=()
  _dbx_filtro_so_pasta=()
  _dbx_filtro_casou=()
  _dbx_filtro_tem_incluir='nao'
  DBX_FILTRO_DESDE='' DBX_FILTRO_ATE='' DBX_FILTRO_MIN='' DBX_FILTRO_MAX=''
  DBX_FILTRO_MOTIVO=''
  return 0
}

# dbx_filtro_ativo — 0 quando ha ao menos um padrao de caminho.
dbx_filtro_ativo() { [[ ${#DBX_FILTRO_PADROES[@]} -gt 0 ]]; }

# dbx_filtro_citar <texto> — o texto citado, sem byte cru (RNF-22): entre
# aspas simples; com byte de controle, na forma `$'...'` do shell. Truncado.
dbx_filtro_citar() {
  { local LC_ALL=C; } 2>/dev/null
  local texto=${1-}
  [[ ${#texto} -gt 80 ]] && texto="${texto:0:80}..."
  if [[ $texto == *[$'\001'-$'\037\177']* ]]; then
    printf -v DBX_FILTRO_CITADO '%q' "$texto"
  else
    DBX_FILTRO_CITADO="'$texto'"
  fi
}

# _dbx_filtro_bytes <texto> — comprimento em BYTES em _dbx_filtro_sp, qualquer que
# seja a localidade do processo (RF-79(k)).
_dbx_filtro_bytes() {
  { local LC_ALL=C; } 2>/dev/null
  _dbx_filtro_sp=${#1}
}

# _dbx_filtro_literal <caractere> — o caractere como literal de regex estendida,
# acrescido as duas regex (caracteres e bytes: o literal multibyte e a mesma
# sequencia de bytes nas duas).
_dbx_filtro_literal() {
  local literal=$1
  case $1 in
    \\ | . | '[' | ']' | '(' | ')' | '{' | '}' | '*' | '+' | '?' | '^' | '$' | '|')
      literal="\\$1" ;;
  esac
  _dbx_filtro_rx+=$literal
  _dbx_filtro_rxb+=$literal
}

# _dbx_filtro_ordem <caractere> — ponto de codigo (ou byte, sem a localidade)
# em _dbx_filtro_falha, para conferir faixa invertida.
_dbx_filtro_ordem() { printf -v _dbx_filtro_falha '%d' "'$1"; }

# _dbx_filtro_conjunto <padrao> <posicao_do_[> — traduz `[...]` para a regex.
#
# Publica o pedaco da regex de caracteres em _dbx_filtro_conj e o da regex de
# bytes em _dbx_filtro_conj_b, a posicao seguinte ao `]` em _dbx_filtro_sp e
# status 1 com o motivo em _dbx_filtro_falha quando malformado: sem `]`, faixa
# invertida, classe POSIX, `/` no conjunto ou faixa com extremo que a regex
# leria como sintaxe (`[`, `]`, `-`, `^`). Como no gitignore, `]` logo depois de
# `[`, `[!` ou `[^` e membro, e nao o fim (QA-B4-02): `[]a]` casa `]` ou `a`.
_dbx_filtro_conjunto() {
  local p=$1 j=$(($2 + 1)) n=${#1} c fim negado='nao' fechado='nao' primeiro='sim'
  local membros='' tem_fecha='nao' tem_abre='nao' tem_circ='nao' tem_hifen='nao' quantos=0 ini_o fim_o
  local nao_ascii='nao'
  _dbx_filtro_conj=''
  _dbx_filtro_conj_b=''
  if [[ ${p:j:1} == '!' || ${p:j:1} == '^' ]]; then
    negado='sim'
    j=$((j + 1))
  fi
  while ((j < n)); do
    c=${p:j:1}
    if [[ $c == ']' && $primeiro == 'nao' ]]; then
      fechado='sim'
      j=$((j + 1))
      break
    fi
    if [[ $c == '[' && ${p:j+1:1} == [:.=] ]]; then
      _dbx_filtro_falha='classe POSIX ([:...:]) nao e aceita'
      return 1
    fi
    primeiro='nao'
    if [[ $c == \\ ]]; then
      ((j + 1 < n)) || { _dbx_filtro_falha='barra invertida no fim do padrao'; return 1; }
      c=${p:j+1:1}
      j=$((j + 2))
    else
      j=$((j + 1))
    fi
    [[ $c == '/' ]] && { _dbx_filtro_falha='conjunto com / (um conjunto nunca casa /)'; return 1; }
    [[ $c == [$'\x01'-$'\x7f'] ]] || nao_ascii='sim'
    quantos=$((quantos + 1))
    if [[ ${p:j:1} == '-' ]] && ((j + 1 < n)) && [[ ${p:j+1:1} != ']' ]]; then
      fim=${p:j+1:1}
      j=$((j + 2))
      if [[ $fim == \\ ]]; then
        ((j < n)) || { _dbx_filtro_falha='barra invertida no fim do padrao'; return 1; }
        fim=${p:j:1}
        j=$((j + 1))
      fi
      case $c$fim in
        *'['* | *']'* | *-* | *'^'* | */*)
          _dbx_filtro_falha='faixa com extremo [, ], -, ^ ou /'
          return 1
          ;;
      esac
      _dbx_filtro_ordem "$c"
      ini_o=$_dbx_filtro_falha
      _dbx_filtro_ordem "$fim"
      fim_o=$_dbx_filtro_falha
      _dbx_filtro_falha=''
      ((ini_o <= fim_o)) || { _dbx_filtro_falha="faixa invertida ($c-$fim)"; return 1; }
      [[ $fim == [$'\x01'-$'\x7f'] ]] || nao_ascii='sim'
      membros+="$c-$fim"
      continue
    fi
    case $c in
      ']') tem_fecha='sim' ;;
      '[') tem_abre='sim' ;;
      '^') tem_circ='sim' ;;
      -) tem_hifen='sim' ;;
      *) membros+=$c ;;
    esac
  done
  # `[]`, `[!]` e `[^]` chegam aqui sem fechamento: o `]` e membro.
  [[ $fechado == 'sim' ]] || { _dbx_filtro_falha='conjunto sem ]'; return 1; }
  ((quantos > 0)) || { _dbx_filtro_falha='conjunto vazio'; return 1; }
  _dbx_filtro_sp=$j
  # Ordem segura numa expressao entre colchetes: `]` primeiro, `[` depois dos
  # membros comuns (nunca seguido de `:`, `.` ou `=`), `^` fora da primeira
  # posicao e `-` por ultimo. O negado nunca casa `/` (RF-79(e)).
  if [[ $negado == 'nao' && $tem_fecha$membros$tem_abre == 'nao''nao' && $tem_circ == 'sim' ]]; then
    if [[ $tem_hifen == 'sim' ]]; then
      _dbx_filtro_conj='[-^]'
    else
      _dbx_filtro_conj='\^'
    fi
  else
    _dbx_filtro_conj='['
    [[ $negado == 'sim' ]] && _dbx_filtro_conj+='^'
    [[ $tem_fecha == 'sim' ]] && _dbx_filtro_conj+=']'
    [[ $negado == 'sim' ]] && _dbx_filtro_conj+='/'
    _dbx_filtro_conj+=$membros
    [[ $tem_abre == 'sim' ]] && _dbx_filtro_conj+='['
    [[ $tem_circ == 'sim' ]] && _dbx_filtro_conj+='^'
    [[ $tem_hifen == 'sim' ]] && _dbx_filtro_conj+='-'
    _dbx_filtro_conj+=']'
  fi
  # Em bytes, o conjunto negado (e o que tem membro fora do ASCII) casa tambem
  # uma sequencia multibyte inteira; o conjunto so ASCII positivo e o mesmo.
  _dbx_filtro_conj_b=$_dbx_filtro_conj
  if [[ $negado == 'sim' || $nao_ascii == 'sim' ]]; then
    _dbx_filtro_conj_b="(${_dbx_filtro_seq}|${_dbx_filtro_conj})"
  fi
  return 0
}

# _dbx_filtro_compilar <padrao> — regex em _dbx_filtro_rx e `sim`/`nao` (so
# pasta) em _dbx_filtro_sp; status 1 com o motivo em _dbx_filtro_falha.
#
# Sintaxe de RF-79(c)..(g), com os desvios de DIV-79: `!` inicial recusado,
# `#` literal, espaco final preservado. O padrao ja chega dobrado.
_dbx_filtro_compilar() {
  { local LC_ALL=$DBX_FILTRO_LOCALIDADE; } 2>/dev/null
  local p=$1 i=0 n=${#1} c k
  local -a tok=()
  _dbx_filtro_falha=''
  _dbx_filtro_rx=''
  _dbx_filtro_literal_visto='nao'
  # 1. Fichas: `L<c>` literal, `S` estrela, `Q` interrogacao, `B<regex>`
  #    conjunto ja traduzido, `/` separador.
  while ((i < n)); do
    c=${p:i:1}
    case $c in
      \\)
        ((i + 1 < n)) || { _dbx_filtro_falha='barra invertida no fim do padrao'; return 1; }
        tok+=("L${p:i+1:1}")
        _dbx_filtro_literal_visto='sim'
        i=$((i + 2))
        ;;
      '*') tok+=(S) i=$((i + 1)) ;;
      '?') tok+=(Q) i=$((i + 1)) ;;
      /) tok+=(/) i=$((i + 1)) ;;
      '[')
        _dbx_filtro_conjunto "$p" "$i" || return 1
        # As duas formas na mesma ficha, separadas por `\x1e` (byte de
        # controle, que o padrao nao aceita).
        tok+=("B${_dbx_filtro_conj}"$'\x1e'"${_dbx_filtro_conj_b}")
        i=$_dbx_filtro_sp
        ;;
      *) tok+=("L$c") i=$((i + 1)) _dbx_filtro_literal_visto='sim' ;;
    esac
  done
  # 2. `/` final: so pasta. `/` inicial: so ancora. `/` no meio: ancora.
  _dbx_filtro_sp='nao'
  local ancorado='nao' total=${#tok[@]}
  if ((total > 0)) && [[ ${tok[total - 1]} == / ]]; then
    _dbx_filtro_sp='sim'
    unset 'tok[total-1]'
    total=$((total - 1))
  fi
  if ((total > 0)) && [[ ${tok[0]} == / ]]; then
    ancorado='sim'
    tok=("${tok[@]:1}")
    total=$((total - 1))
  fi
  ((total > 0)) || { _dbx_filtro_falha='padrao so com /'; return 1; }
  # 3. Componentes: nenhum vazio (`//`), nenhum `.` ou `..`.
  local -a comps=()
  local atual='' literal='sim' texto=''
  for ((k = 0; k <= total; k++)); do
    if ((k == total)) || [[ ${tok[k]} == / ]]; then
      [[ -n $atual ]] || { _dbx_filtro_falha='componente vazio (//)'; return 1; }
      if [[ $literal == 'sim' && ($texto == . || $texto == ..) ]]; then
        _dbx_filtro_falha="componente $texto"
        return 1
      fi
      comps+=("$atual")
      ((k < total)) && ancorado='sim'
      atual='' literal='sim' texto=''
      continue
    fi
    # Fichas do componente separadas por NUL logico: `\x1f` nao entra (o padrao
    # nao aceita byte de controle), entao serve de separador interno.
    atual+="${tok[k]}"$'\x1f'
    if [[ ${tok[k]} == L* ]]; then texto+=${tok[k]:1}; else literal='nao'; fi
  done
  # 4. Regex. `**` como componente inteiro: no inicio `(.*/)?`, no fim `.+`
  #    (todo descendente, nao a propria pasta), no meio `(.*/)?`; em outra
  #    posicao vale `*` (RF-79(f)).
  #    A regex de bytes (`_dbx_filtro_rxb`) sai na mesma passada: so `?` e o
  #    conjunto mudam, para casar uma sequencia UTF-8 inteira ou um byte.
  local ncomp=${#comps[@]} ficha resto
  _dbx_filtro_rx=''
  _dbx_filtro_rxb=''
  for ((k = 0; k < ncomp; k++)); do
    if [[ ${comps[k]} == $'S\x1fS\x1f' ]] && ((ncomp > 1)); then
      if ((k == ncomp - 1)); then
        _dbx_filtro_rx+='.+'
        _dbx_filtro_rxb+='.+'
      else
        _dbx_filtro_rx+='(.*/)?'
        _dbx_filtro_rxb+='(.*/)?'
      fi
      continue
    fi
    resto=${comps[k]}
    while [[ -n $resto ]]; do
      ficha=${resto%%$'\x1f'*}
      resto=${resto#*$'\x1f'}
      case $ficha in
        S)
          _dbx_filtro_rx+='[^/]*'
          _dbx_filtro_rxb+='[^/]*'
          ;;
        Q)
          _dbx_filtro_rx+='[^/]'
          _dbx_filtro_rxb+="(${_dbx_filtro_seq}|[^/])"
          ;;
        B*)
          ficha=${ficha:1}
          _dbx_filtro_rx+=${ficha%%$'\x1e'*}
          _dbx_filtro_rxb+=${ficha#*$'\x1e'}
          ;;
        L*) _dbx_filtro_literal "${ficha:1}" ;;
      esac
    done
    if ((k < ncomp - 1)); then
      _dbx_filtro_rx+='/'
      _dbx_filtro_rxb+='/'
    fi
  done
  if [[ $ancorado == 'sim' ]]; then
    _dbx_filtro_rx="^${_dbx_filtro_rx}\$"
    _dbx_filtro_rxb="^${_dbx_filtro_rxb}\$"
  else
    _dbx_filtro_rx="^(.*/)?${_dbx_filtro_rx}\$"
    _dbx_filtro_rxb="^(.*/)?${_dbx_filtro_rxb}\$"
  fi
  return 0
}

# _dbx_filtro_validar_padrao <padrao> <remedio_do_!> — RF-79(i)(j)(k): a UNICA
# validacao do padrao, para os filtros de caminho e para o nome avulso da
# retencao (RNF-36). Compila em _dbx_filtro_rx/_dbx_filtro_rxb; status 1 com o
# motivo (sem a opcao) em _dbx_filtro_falha.
_dbx_filtro_validar_padrao() {
  local padrao=${1-} remedio=${2:---incluir} bytes
  _dbx_filtro_bytes "$padrao"
  bytes=$_dbx_filtro_sp
  if [[ -z $padrao ]]; then
    _dbx_filtro_falha='padrao vazio'
  elif [[ $bytes -gt $DBX_FILTRO_MAXIMO_BYTES ]]; then
    _dbx_filtro_falha="padrao com $bytes bytes; o maximo e $DBX_FILTRO_MAXIMO_BYTES"
  elif [[ $padrao == *[$'\001'-$'\037\177']* ]]; then
    _dbx_filtro_falha='byte de controle no padrao'
  elif [[ $padrao == '!'* ]]; then
    _dbx_filtro_falha="a negacao com ! nao existe aqui; use $remedio (ou \\! para o caractere literal)"
  else
    dbx_filtro_chave "$padrao"
    _dbx_filtro_compilar "$DBX_FILTRO_CHAVE" && return 0
    _dbx_filtro_falha="padrao malformado: $_dbx_filtro_falha"
  fi
  return 1
}

# _dbx_filtro_recusar <opcao> <padrao> <motivo> — DBX_FILTRO_MOTIVO com a opcao
# e o padrao citado sem byte cru (RNF-22).
_dbx_filtro_recusar() {
  dbx_filtro_citar "$2"
  if [[ -z $2 ]]; then
    DBX_FILTRO_MOTIVO="$1: $3"
  else
    DBX_FILTRO_MOTIVO="$1 $DBX_FILTRO_CITADO: $3"
  fi
}

# dbx_filtro_adicionar <excluir|incluir> <opcao_como_digitada> <padrao>
#
# Valida (RF-79(i)(j)(k)) e acrescenta. Recusa com uso invalido e a mensagem em
# DBX_FILTRO_MOTIVO, que nomeia a opcao e cita o padrao sem byte cru.
dbx_filtro_adicionar() {
  local tipo=${1-} opcao=${2-} padrao=${3-} motivo=''
  DBX_FILTRO_MOTIVO=''
  case $tipo in
    excluir | incluir) ;;
    *) return "$DBX_FILTRO_ERRO_USO" ;;
  esac
  if [[ ${#DBX_FILTRO_PADROES[@]} -ge $DBX_FILTRO_MAXIMO_PADROES ]]; then
    motivo="mais de $DBX_FILTRO_MAXIMO_PADROES padroes por execucao (--excluir e --incluir somados)"
  elif ! _dbx_filtro_validar_padrao "$padrao" '--incluir'; then
    motivo=$_dbx_filtro_falha
  fi
  if [[ -n $motivo ]]; then
    _dbx_filtro_recusar "$opcao" "$padrao" "$motivo"
    return "$DBX_FILTRO_ERRO_USO"
  fi
  DBX_FILTRO_TIPOS+=("$tipo")
  DBX_FILTRO_OPCOES+=("$opcao")
  DBX_FILTRO_PADROES+=("$padrao")
  _dbx_filtro_regex+=("$_dbx_filtro_rx")
  _dbx_filtro_regex_b+=("$_dbx_filtro_rxb")
  # Toda construcao imprecisa em bytes, e so ela, usa a sequencia multibyte.
  if [[ $_dbx_filtro_rxb == *"$_dbx_filtro_seq"* ]]; then
    _dbx_filtro_impreciso+=(sim)
  else
    _dbx_filtro_impreciso+=(nao)
  fi
  _dbx_filtro_so_pasta+=("$_dbx_filtro_sp")
  _dbx_filtro_casou+=(nao)
  [[ $tipo == 'incluir' ]] && _dbx_filtro_tem_incluir='sim'
  return 0
}

# _dbx_filtro_casa <tipo> <dobrado> <e_pasta> — 0 se algum padrao do tipo casa;
# marca TODOS os que casam (o aviso de DIV-91 nao pode acusar um padrao que
# casou junto com outro). Roda sob a localidade fixada por quem chama.
_dbx_filtro_casa() {
  local tipo=$1 alvo=$2 e_pasta=$3 i casou=1 rx estado
  for i in "${!DBX_FILTRO_TIPOS[@]}"; do
    [[ ${DBX_FILTRO_TIPOS[i]} == "$tipo" ]] || continue
    [[ ${_dbx_filtro_so_pasta[i]} == 'sim' && $e_pasta != 'sim' ]] && continue
    rx=${_dbx_filtro_regex[i]}
    if [[ $_dbx_filtro_modo == 'bytes' ]]; then
      # DIV-103: inclusao imprecisa em bytes nao casa; o item fica fora do
      # escopo e, portanto, protegido.
      [[ $tipo == 'incluir' && ${_dbx_filtro_impreciso[i]} == 'sim' ]] && continue
      rx=${_dbx_filtro_regex_b[i]}
    fi
    [[ $alvo =~ $rx ]]
    estado=$?
    # Em bytes, regex que a biblioteca recusa (status 2) conta como casamento:
    # o recuo existe para proteger, e nunca para deixar passar.
    if [[ $estado -eq 0 || ($estado -eq 2 && $_dbx_filtro_modo == 'bytes') ]]; then
      _dbx_filtro_casou[i]='sim'
      casou=0
    fi
  done
  return "$casou"
}

# _dbx_filtro_dobrar_bytes <caminho> — o caminho dobrado caractere a caractere
# sob a localidade (a MESMA dobra do padrao), em _dbx_filtro_rx. Sob `C.UTF-8`,
# o byte invalido sai como um "caractere" de um byte e passa sem mudar.
_dbx_filtro_dobrar_bytes() {
  { local LC_ALL=$DBX_FILTRO_LOCALIDADE; } 2>/dev/null
  local texto=$1 i c
  _dbx_filtro_rx=''
  for ((i = 0; i < ${#texto}; i++)); do
    c=${texto:i:1}
    _dbx_filtro_rx+=${c,,}
  done
}

# dbx_filtro_classificar <relativo> <e_pasta: sim|nao> — RF-80(a).
#
# 0: no escopo. 1: filtrado, com o item que CONTA em DBX_FILTRO_FILTRADO (a
# pasta excluida mais alta, ou o proprio item) e a razao em DBX_FILTRO_RAZAO
# (`excluido` ou `nao_incluido`). Exclusao vence: nem o item nem pasta ancestral
# alguma casa `--excluir`; e, havendo `--incluir`, o item ou um ancestral casa.
# A propria raiz (caminho vazio) nunca e filtrada.
dbx_filtro_classificar() {
  local caminho=${1-} e_pasta=${2:-nao}
  DBX_FILTRO_FILTRADO=''
  DBX_FILTRO_RAZAO=''
  [[ ${#DBX_FILTRO_PADROES[@]} -gt 0 && -n $caminho ]] || return 0
  { local LC_ALL=$DBX_FILTRO_LOCALIDADE; } 2>/dev/null
  local _dbx_filtro_modo='caracteres' dobrado
  # Byte invalido na localidade: compara por bytes, com a mesma dobra (topo).
  if [[ $caminho =~ ^.*$ ]]; then
    dobrado=${caminho,,}
  else
    _dbx_filtro_dobrar_bytes "$caminho" 2>/dev/null
    dobrado=$_dbx_filtro_rx
    _dbx_filtro_modo='bytes'
    { LC_ALL=C; } 2>/dev/null
  fi
  local -a original=() chave=()
  local resto=$caminho
  while [[ $resto == */* ]]; do
    original+=("${resto%%/*}")
    resto=${resto#*/}
  done
  original+=("$resto")
  resto=$dobrado
  while [[ $resto == */* ]]; do
    chave+=("${resto%%/*}")
    resto=${resto#*/}
  done
  chave+=("$resto")
  local total=${#original[@]} k prefixo='' alvo='' tipo_k
  for ((k = 0; k < total; k++)); do
    prefixo+=${prefixo:+/}${original[k]}
    alvo+=${alvo:+/}${chave[k]}
    tipo_k='sim'
    ((k == total - 1)) && tipo_k=$e_pasta
    if _dbx_filtro_casa excluir "$alvo" "$tipo_k"; then
      DBX_FILTRO_FILTRADO=$prefixo
      DBX_FILTRO_RAZAO='excluido'
      return 1
    fi
  done
  [[ $_dbx_filtro_tem_incluir == 'sim' ]] || return 0
  local incluido='nao'
  alvo=''
  for ((k = 0; k < total; k++)); do
    alvo+=${alvo:+/}${chave[k]}
    tipo_k='sim'
    ((k == total - 1)) && tipo_k=$e_pasta
    _dbx_filtro_casa incluir "$alvo" "$tipo_k" && incluido='sim'
  done
  [[ $incluido == 'sim' ]] && return 0
  DBX_FILTRO_FILTRADO=$caminho
  DBX_FILTRO_RAZAO='nao_incluido'
  return 1
}

# dbx_filtro_pasta_excluida <relativo> — 0 quando a PROPRIA pasta casa um
# `--excluir` (RF-80(b)): a descida local nao entra nela. Os ancestrais ja foram
# conferidos por quem desceu ate aqui.
dbx_filtro_pasta_excluida() {
  [[ ${#DBX_FILTRO_PADROES[@]} -gt 0 && -n ${1-} ]] || return 1
  { local LC_ALL=$DBX_FILTRO_LOCALIDADE; } 2>/dev/null
  local _dbx_filtro_modo='caracteres' dobrado
  if [[ $1 =~ ^.*$ ]]; then
    dobrado=${1,,}
  else
    _dbx_filtro_dobrar_bytes "$1" 2>/dev/null
    dobrado=$_dbx_filtro_rx
    _dbx_filtro_modo='bytes'
    { LC_ALL=C; } 2>/dev/null
  fi
  _dbx_filtro_casa excluir "$dobrado" sim
}

# dbx_filtro_avisos — padroes que nao casaram item algum em DBX_FILTRO_SEM_CASAMENTO.
dbx_filtro_avisos() {
  local i
  DBX_FILTRO_SEM_CASAMENTO=()
  for i in "${!DBX_FILTRO_PADROES[@]}"; do
    [[ ${_dbx_filtro_casou[i]} == 'sim' ]] || DBX_FILTRO_SEM_CASAMENTO+=("${DBX_FILTRO_PADROES[i]}")
  done
  return 0
}

# dbx_filtro_descrever — os filtros ativos, citados, em DBX_FILTRO_DESCRICAO.
dbx_filtro_descrever() {
  local i
  DBX_FILTRO_DESCRICAO=''
  for i in "${!DBX_FILTRO_PADROES[@]}"; do
    dbx_filtro_citar "${DBX_FILTRO_PADROES[i]}"
    DBX_FILTRO_DESCRICAO+="${DBX_FILTRO_DESCRICAO:+ }${DBX_FILTRO_OPCOES[i]} $DBX_FILTRO_CITADO"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Nome avulso (fase 6, RF-93(g)(h)(j), DIV-131, DIV-132)
# ---------------------------------------------------------------------------
#
# O `--padrao` do `reter` casa o NOME de um arquivo, nunca o caminho. A
# validacao e o casamento sao os mesmos dos filtros de caminho (RNF-36, sem
# codigo gemeo): `_dbx_filtro_validar_padrao` e `_dbx_filtro_compilar`. Proprio
# daqui: `/` em qualquer posicao e recusado, e o padrao fica fora dos vetores
# dos filtros de caminho (as duas coisas convivem na mesma execucao).
#
# FALHA FECHADA. Casar e tornar o arquivo candidato a exclusao, como o
# `--incluir` sob `--espelhar` (DIV-103): nome que nao e UTF-8 valido (so
# possivel com resposta incoerente) compara em bytes, e ai padrao impreciso NAO
# casa; regex que a biblioteca recusa tambem nao casa.

DBX_FILTRO_AMPLO='nao'
_dbx_filtro_nome_rx=''
_dbx_filtro_nome_rxb=''
_dbx_filtro_nome_impreciso='nao'
_dbx_filtro_nome_pronto='nao'

# dbx_filtro_nome_preparar <opcao_como_digitada> <padrao> — valida e guarda o
# padrao de nome. Recusa com uso invalido e DBX_FILTRO_MOTIVO (opcao e padrao
# citado). DBX_FILTRO_AMPLO = `sim` quando o padrao nao tem caractere literal.
dbx_filtro_nome_preparar() {
  local opcao=${1-} padrao=${2-} motivo=''
  DBX_FILTRO_MOTIVO=''
  DBX_FILTRO_AMPLO='nao'
  _dbx_filtro_nome_pronto='nao'
  if [[ $padrao == */* ]]; then
    motivo='/ no padrao: o padrao casa so o nome; a retencao olha um nivel'
  elif ! _dbx_filtro_validar_padrao "$padrao" 'um padrao que case so os artefatos'; then
    motivo=$_dbx_filtro_falha
  fi
  if [[ -n $motivo ]]; then
    _dbx_filtro_recusar "$opcao" "$padrao" "$motivo"
    return "$DBX_FILTRO_ERRO_USO"
  fi
  _dbx_filtro_nome_rx=$_dbx_filtro_rx
  _dbx_filtro_nome_rxb=$_dbx_filtro_rxb
  _dbx_filtro_nome_impreciso='nao'
  [[ $_dbx_filtro_rxb == *"$_dbx_filtro_seq"* ]] && _dbx_filtro_nome_impreciso='sim'
  [[ $_dbx_filtro_literal_visto == 'sim' ]] || DBX_FILTRO_AMPLO='sim'
  _dbx_filtro_nome_pronto='sim'
  return 0
}

# dbx_filtro_nome_casa <nome> — 0 quando o nome inteiro casa o padrao
# preparado, sem caixa (RF-54). Nome vazio, com `/` ou sem padrao preparado:
# nao casa.
dbx_filtro_nome_casa() {
  local nome=${1-} dobrado rx
  [[ $_dbx_filtro_nome_pronto == 'sim' && -n $nome && $nome != */* ]] || return 1
  { local LC_ALL=$DBX_FILTRO_LOCALIDADE; } 2>/dev/null
  if [[ $nome =~ ^.*$ ]]; then
    dobrado=${nome,,}
    rx=$_dbx_filtro_nome_rx
    [[ $dobrado =~ $rx ]]
    return
  fi
  [[ $_dbx_filtro_nome_impreciso == 'nao' ]] || return 1
  _dbx_filtro_dobrar_bytes "$nome" 2>/dev/null
  dobrado=$_dbx_filtro_rx
  { LC_ALL=C; } 2>/dev/null
  rx=$_dbx_filtro_nome_rxb
  [[ $dobrado =~ $rx ]]
}

# ---------------------------------------------------------------------------
# Data e tamanho (RF-81): so a origem, sempre arquivo, nunca pasta.
# ---------------------------------------------------------------------------

# _dbx_filtro_dias_no_mes <ano> <mes>
_dbx_filtro_dias_no_mes() {
  local ano=$1 mes=$2
  case $mes in
    1 | 3 | 5 | 7 | 8 | 10 | 12) _dbx_filtro_sp=31 ;;
    4 | 6 | 9 | 11) _dbx_filtro_sp=30 ;;
    *)
      _dbx_filtro_sp=28
      if ((ano % 4 == 0 && (ano % 100 != 0 || ano % 400 == 0))); then _dbx_filtro_sp=29; fi
      ;;
  esac
}

# dbx_filtro_validar_data <opcao> <valor> <desde|ate> — RF-81(d).
#
# `AAAA-MM-DD` ou `AAAA-MM-DDTHH:MM:SSZ` (UTC). O dia sozinho vale o inicio no
# `desde` e o fim (23:59:59) no `ate`, como `--antes-de` de RF-73(d). Carimbo
# normalizado em DBX_FILTRO_DATA.
dbx_filtro_validar_data() {
  local opcao=$1 valor=${2-} lado=${3:-desde} ano mes dia hora=0 minuto=0 segundo=0
  { local LC_ALL=C; } 2>/dev/null
  DBX_FILTRO_DATA=''
  DBX_FILTRO_MOTIVO=''
  if [[ $valor =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})(T([0-9]{2}):([0-9]{2}):([0-9]{2})Z)?$ ]]; then
    ano=$((10#${BASH_REMATCH[1]})) mes=$((10#${BASH_REMATCH[2]})) dia=$((10#${BASH_REMATCH[3]}))
    if [[ -n ${BASH_REMATCH[4]} ]]; then
      hora=$((10#${BASH_REMATCH[5]})) minuto=$((10#${BASH_REMATCH[6]})) segundo=$((10#${BASH_REMATCH[7]}))
    fi
    _dbx_filtro_dias_no_mes "$ano" "$mes"
    if ((ano >= 1 && mes >= 1 && mes <= 12 && dia >= 1 && dia <= _dbx_filtro_sp &&
      hora <= 23 && minuto <= 59 && segundo <= 59)); then
      if [[ -n ${BASH_REMATCH[4]} ]]; then
        DBX_FILTRO_DATA=$valor
      elif [[ $lado == 'ate' ]]; then
        DBX_FILTRO_DATA="${valor}T23:59:59Z"
      else
        DBX_FILTRO_DATA="${valor}T00:00:00Z"
      fi
      return 0
    fi
  fi
  dbx_filtro_citar "$valor"
  DBX_FILTRO_MOTIVO="valor invalido para $opcao: $DBX_FILTRO_CITADO; use AAAA-MM-DD ou AAAA-MM-DDTHH:MM:SSZ (UTC), data existente"
  return "$DBX_FILTRO_ERRO_USO"
}

# dbx_filtro_validar_tamanho <opcao> <valor> — RF-81(f): bytes em DBX_FILTRO_BYTES.
dbx_filtro_validar_tamanho() {
  local opcao=$1 valor=${2-} fator=1
  { local LC_ALL=C; } 2>/dev/null
  DBX_FILTRO_BYTES=''
  DBX_FILTRO_MOTIVO=''
  if [[ $valor =~ ^(0|[1-9][0-9]{0,8})([KkMmGg]?)$ ]]; then
    case ${BASH_REMATCH[2]} in
      [Kk]) fator=1024 ;;
      [Mm]) fator=1048576 ;;
      [Gg]) fator=1073741824 ;;
    esac
    DBX_FILTRO_BYTES=$((BASH_REMATCH[1] * fator))
    return 0
  fi
  dbx_filtro_citar "$valor"
  DBX_FILTRO_MOTIVO="valor invalido para $opcao: $DBX_FILTRO_CITADO; use inteiro sem sinal nem zero a esquerda, com sufixo opcional K, M ou G (base 1024)"
  return "$DBX_FILTRO_ERRO_USO"
}

# dbx_filtro_meta_definir <desde> <ate> <min> <max> — valores ja validados
# (vazio = sem limite). Recusa faixa invertida.
dbx_filtro_meta_definir() {
  { local LC_ALL=C; } 2>/dev/null
  DBX_FILTRO_MOTIVO=''
  if [[ -n $1 && -n $2 && $1 > $2 ]]; then
    DBX_FILTRO_MOTIVO="a data de --modificado-desde ($1) e posterior a de --modificado-ate ($2)"
    return "$DBX_FILTRO_ERRO_USO"
  fi
  if [[ -n $3 && -n $4 ]] && (($3 > $4)); then
    DBX_FILTRO_MOTIVO="--tamanho-min ($3 bytes) e maior que --tamanho-max ($4 bytes)"
    return "$DBX_FILTRO_ERRO_USO"
  fi
  # shellcheck disable=SC2034  # canais publicos, lidos pelos comandos no plano
  DBX_FILTRO_DESDE=$1 DBX_FILTRO_ATE=$2 DBX_FILTRO_MIN=$3 DBX_FILTRO_MAX=$4
  return 0
}

# dbx_filtro_meta_ativo — 0 quando ha filtro de data ou de tamanho.
dbx_filtro_meta_ativo() { [[ -n $DBX_FILTRO_DESDE$DBX_FILTRO_ATE$DBX_FILTRO_MIN$DBX_FILTRO_MAX ]]; }

# dbx_filtro_meta_passa <carimbo_utc> <tamanho> — 0 se o arquivo da origem esta
# na faixa (limites inclusivos). Carimbo ou tamanho ausente ou malformado nao
# passa no filtro que o exige: transferir o que o operador pediu para deixar de
# fora seria o erro, e a origem fica intocada de qualquer forma.
dbx_filtro_meta_passa() {
  local carimbo=${1-} tamanho=${2-}
  { local LC_ALL=C; } 2>/dev/null
  if [[ -n $DBX_FILTRO_DESDE$DBX_FILTRO_ATE ]]; then
    [[ $carimbo =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
    [[ -n $DBX_FILTRO_DESDE && $carimbo < $DBX_FILTRO_DESDE ]] && return 1
    [[ -n $DBX_FILTRO_ATE && $carimbo > $DBX_FILTRO_ATE ]] && return 1
  fi
  if [[ -n $DBX_FILTRO_MIN$DBX_FILTRO_MAX ]]; then
    [[ $tamanho =~ ^[0-9]{1,18}$ ]] || return 1
    [[ -n $DBX_FILTRO_MIN ]] && ((10#$tamanho < DBX_FILTRO_MIN)) && return 1
    [[ -n $DBX_FILTRO_MAX ]] && ((10#$tamanho > DBX_FILTRO_MAX)) && return 1
  fi
  return 0
}

# dbx_filtro_carimbo_de_epoca <segundos> — `AAAA-MM-DDTHH:MM:SSZ` em
# DBX_FILTRO_CARIMBO, por aritmetica (algoritmo civil de dias desde 1970),
# sem utilitario e sem depender do fuso do processo (RF-81(e)).
dbx_filtro_carimbo_de_epoca() {
  DBX_FILTRO_CARIMBO=''
  [[ ${1-} =~ ^[0-9]{1,12}$ ]] || return 1
  local s=$((10#$1))
  local dias=$((s / 86400)) resto=$((s % 86400))
  local z=$((dias + 719468))
  local era=$((z / 146097))
  local doe=$((z - era * 146097))
  local yoe=$(((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365))
  local ano=$((yoe + era * 400))
  local doy=$((doe - (365 * yoe + yoe / 4 - yoe / 100)))
  local mp=$(((5 * doy + 2) / 153))
  local dia=$((doy - (153 * mp + 2) / 5 + 1))
  local mes=$((mp < 10 ? mp + 3 : mp - 9))
  ((mes <= 2)) && ano=$((ano + 1))
  printf -v DBX_FILTRO_CARIMBO '%04d-%02d-%02dT%02d:%02d:%02dZ' \
    "$ano" "$mes" "$dia" $((resto / 3600)) $((resto % 3600 / 60)) $((resto % 60))
  return 0
}
