#!/usr/bin/env bash
# Testes de lib/transfer.sh — sessao de envio em partes (RF-08, RF-09, RF-31).
#
# O que estes casos guardam, e por que cada um existe
# ---------------------------------------------------
# A sessao em partes e o unico caminho do produto em que um defeito produz
# arquivo remoto BEM FORMADO E ERRADO: ordem de chamada trocada, deslocamento
# fora de passo ou bloco reenviado geram um arquivo que existe, tem tamanho
# plausivel e conteudo embaralhado. Nada disso aparece no status de saida. Por
# isso os casos abaixo verificam a SEQUENCIA observada pelo cliente, e nao
# apenas o desfecho.
#
# O substituto do cliente registra, por chamada: a URL, o alvo, o tamanho do
# corpo enviado, o argumento do cabecalho, a ocupacao em disco e as permissoes
# observadas. Registrar a ocupacao NO MOMENTO DA CHAMADA e o que torna o teto de
# RF-31 mensuravel: a chamada acontece com o bloco recem-lido em disco, que e
# exatamente o instante de pico.
#
# ---------------------------------------------------------------------------
# O QUE A MEDICAO DE OCUPACAO ABRANGE — corrigido no ciclo 1 de QA (achado A9)
# ---------------------------------------------------------------------------
# Cada caso roda com um `TMPDIR` PROPRIO E VAZIO, montado por `preparar_caso`. A
# ocupacao e `find "$TMPDIR" -type f`: RECURSIVA e SEM filtro de nome. A pergunta
# respondida e "quanto ocupa em disco", e nao mais uma pergunta mais estreita.
#
# A versao anterior media "soma dos arquivos regulares no PRIMEIRO NIVEL das
# areas cujo nome comeca com `dbx-transfer.`". As duas estreitezas foram
# exploradas por mutacao, e as duas APROVAVAM 22/22 com residuo real:
#   - blocos acumulados em subdiretorio da propria area: `for arquivo in
#     "$area"/*` com filtro `-f` nao desce, e a ocupacao crescia linearmente sem
#     ninguem ver;
#   - blocos acumulados em area IRMA (`dbx-cache.XXXX`), nunca removida: o filtro
#     de nome a `-maxdepth 1` nao a enxergava, e 60+ MiB ficavam em `/tmp` sem
#     que nenhum dos casos de residuo reclamasse.
# Ambas reprovam contra o instrumento atual.
#
# LIMITE QUE PERMANECE, declarado em vez de arredondado: a ocupacao e amostrada
# nos instantes de chamada, e nao continuamente. Um pico que existisse ENTRE duas
# chamadas nao seria visto. O desenho torna isso improvavel — o unico arquivo da
# area e o bloco, escrito imediatamente antes da chamada — mas improvavel nao e
# impossivel, e a medicao nao prova a ausencia.
#
# LIMITE QUE DEIXOU DE EXISTIR: a estreiteza por NOME e por PROFUNDIDADE. Nao ha
# mais filtro de prefixo e nao ha mais teto de profundidade.

# shellcheck disable=SC2016
# Justificativa: o caso de interrupcao entrega um script literal a `bash -c`, que
# precisa chegar ao processo filho SEM expansao — expandir no shell pai
# destruiria o proposito do caso.
#
# shellcheck disable=SC2034
# Justificativa: `DBX_AUTH_TOKEN`, `DBX_AUTH_EXPIRA_EM`, `DBX_HTTP_ESPERA_BASE_MS`
# e `DBX_CLI_SIMULACAO` sao canais de OUTROS componentes, definidos aqui para
# posicionar o cenario. Quem os le esta em `lib/`, e a analise estatica nao
# cruza arquivos.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
# shellcheck source=tests/support/fixtures.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/fixtures.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/http.sh"
. "$DBX_HARNESS_RAIZ/lib/auth.sh"
. "$DBX_HARNESS_RAIZ/lib/hash.sh"
. "$DBX_HARNESS_RAIZ/lib/transfer.sh"

# Token em memoria: estes casos exercitam a sessao, nao a renovacao. Sem isto
# cada chamada tentaria renovar e o caso mediria o caminho errado.
DBX_AUTH_TOKEN='sl.tokenDeTeste'
DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
# Recuo minimo: o que se verifica na retentativa e QUANTAS vezes e COM QUE
# corpo, nunca o tempo de espera.
DBX_HTTP_ESPERA_BASE_MS=1

readonly COMMIT_DE_TESTE='{"path":"/r/a.bin","mode":"add","autorename":false,"mute":false}'
readonly ESPERADO_VAZIO=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

# preparar_caso — TMPDIR PROPRIO E VAZIO por caso.
#
# Sem isto, medir `find "$TMPDIR"` somaria a massa de teste, os diretorios do
# duplo e o que mais estivesse em `/tmp` na maquina, e o instrumento voltaria a
# precisar de um filtro de nome — que foi exatamente o defeito A9. Com area
# privada a pergunta "sobrou alguma coisa?" tem resposta exata: o diretorio
# comeca vazio e tem de terminar vazio.
#
# A massa e o estado do duplo vivem sob `$DBX_TESTES_TMP`, FORA deste TMPDIR, de
# proposito: sao instrumento, e instrumento contado como ocupacao do produto
# tornaria a medicao ruidosa.
#
# O harness chama esta funcao dentro do subshell de cada caso, entao a
# exportacao nao vaza para o caso seguinte.
preparar_caso() {
  TMPDIR=$(mktemp -d "$DBX_TESTES_TMP/tmpdir.XXXXXX") || return 1
  export TMPDIR
}

# _massa <bytes> — cria um arquivo de conteudo deterministico e imprime o caminho.
_massa() {
  local bytes=$1 caminho="$DBX_TESTES_TMP/massa-$1.bin"
  [[ -e $caminho ]] || head -c "$bytes" /dev/zero >"$caminho"
  printf '%s' "$caminho"
}

# _duplo — substituto do cliente com resposta por alvo. Devolve o diretorio de
# estado, onde ficam os registros que os casos leem.
_duplo() {
  local dir
  dir=$(mktemp -d "$DBX_TESTES_TMP/sess.XXXXXX")
  printf '%s' '{"session_id":"S-1"}' >"$dir/corpo_start"
  printf '200\n' >"$dir/cod_start"
  printf '%s' '{}' >"$dir/corpo_append"
  printf '200\n' >"$dir/cod_append"
  printf '%s' '{"name":"a.bin","path_display":"/r/a.bin","rev":"016","size":1}' >"$dir/corpo_finish"
  printf '200\n' >"$dir/cod_finish"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'dir=%s\n' "$dir"
    cat <<'FIM'
conf=$(cat)
printf '%s\n' "$*" >>"$dir/argv"
url=''; saida=''; escrever=''; corpoarq=''; ant=''
for a in "$@"; do
  case $ant in -o) saida=$a ;; -w) escrever=$a ;; esac
  case $a in http*) url=$a ;; @*) corpoarq=${a#@} ;; esac
  ant=$a
done
bytes='-'
if [[ -n $corpoarq && -r $corpoarq ]]; then
  bytes=$(wc -c <"$corpoarq")
  bytes=${bytes//[^0-9]/}
fi
argapi=''
while IFS= read -r linha; do
  case $linha in
    *Dropbox-API-Arg:*)
      argapi=${linha#*Dropbox-API-Arg: }
      argapi=${argapi%\"}
      argapi=${argapi//\\\"/\"}
      ;;
  esac
done <<<"$conf"
for area in "${TMPDIR:-/tmp}"/dbx-transfer.*; do
  [[ -d $area ]] || continue
  stat -c %a "$area" >>"$dir/perm_area"
  for arquivo in "$area"/*; do
    [[ -f $arquivo ]] || continue
    stat -c %a "$arquivo" >>"$dir/perm_arquivo"
  done
done
ocupacao=0
while IFS= read -r tamanho; do
  [[ $tamanho =~ ^[0-9]+$ ]] || continue
  ocupacao=$((ocupacao + tamanho))
done < <(find "${TMPDIR:-/tmp}" -type f -printf '%s\n' 2>/dev/null)
pico=0
[[ -r $dir/pico ]] && read -r pico <"$dir/pico"
[[ $ocupacao -gt $pico ]] && printf '%s' "$ocupacao" >"$dir/pico"
case $url in
  *upload_session/start*) alvo=start ;;
  *upload_session/append_v2*) alvo=append ;;
  *upload_session/finish*) alvo=finish ;;
  *) alvo=outro ;;
esac
printf 'alvo=%s bytes=%s arg=%s\n' "$alvo" "$bytes" "$argapi" >>"$dir/chamadas"
vez=0
[[ -r "$dir/n_$alvo" ]] && read -r vez <"$dir/n_$alvo"
vez=$((vez + 1))
printf '%s' "$vez" >"$dir/n_$alvo"
corpo=''
codigo=200
[[ -r "$dir/corpo_$alvo" ]] && IFS= read -r -d '' corpo <"$dir/corpo_$alvo"
[[ -r "$dir/corpo_${alvo}_$vez" ]] && IFS= read -r -d '' corpo <"$dir/corpo_${alvo}_$vez"
if [[ -r "$dir/cod_$alvo" ]]; then
  indice=0
  while IFS= read -r linha; do
    indice=$((indice + 1))
    codigo=$linha
    [[ $indice -ge $vez ]] && break
  done <"$dir/cod_$alvo"
fi
if [[ -r "$dir/matar" && -r "$dir/pid" ]]; then
  gatilho=''
  read -r gatilho <"$dir/matar"
  if [[ $gatilho == "$alvo:$vez" ]]; then
    vitima=''
    read -r vitima <"$dir/pid"
    kill -TERM "$vitima" 2>/dev/null
  fi
fi
[[ -n $saida ]] && printf '%s' "$corpo" >"$saida"
[[ -n $escrever ]] && printf '%s' "$codigo"
exit 0
FIM
  } >"$dir/curl"
  chmod +x "$dir/curl"
  printf '%s' "$dir"
}

# _campo_das_chamadas <dir> <campo> — imprime o valor do campo, uma linha por
# chamada, na ordem observada.
_campo_das_chamadas() {
  local dir=$1 campo=$2 linha resto
  [[ -r "$dir/chamadas" ]] || return 0
  while IFS= read -r linha; do
    resto=${linha#*"$campo"=}
    printf '%s\n' "${resto%% *}"
  done <"$dir/chamadas"
}

# _deslocamentos <dir> — imprime o `offset` do cursor de cada chamada que o tem.
_deslocamentos() {
  local dir=$1 linha resto
  [[ -r "$dir/chamadas" ]] || return 0
  while IFS= read -r linha; do
    case $linha in
      *'"offset":'*) ;;
      *) continue ;;
    esac
    resto=${linha#*\"offset\":}
    printf '%s\n' "${resto%%[^0-9]*}"
  done <"$dir/chamadas"
}

# _conteudo_do_tmpdir — TUDO que existe sob o TMPDIR privado do caso.
#
# Recursivo e sem filtro de nome, pelo mesmo motivo de A9: uma listagem que so
# enxerga `dbx-transfer.*` no primeiro nivel certifica ausencia de residuo que
# nao verificou. `lib/http` e `lib/hash` tambem criam area sob TMPDIR, e residuo
# deles e residuo igual.
_conteudo_do_tmpdir() {
  find "${TMPDIR:-/tmp}" -mindepth 1 2>/dev/null | sort
}

# ---------------------------------------------------------------------------
# Contrato do componente
# ---------------------------------------------------------------------------

teste_tamanho_de_parte_e_de_4_mib() {
  # O tamanho da parte esta amarrado ao bloco do content_hash. Um valor
  # diferente quebraria a cadeia de resumos em silencio.
  assert_igual 4194304 "$DBX_TRANSFER_TAMANHO_PARTE" 'parte de 4 MiB exatos'
  assert_igual "$DBX_HASH_TAMANHO_BLOCO" "$DBX_TRANSFER_TAMANHO_PARTE" \
    'parte e bloco do resumo sao a MESMA grandeza nesta entrega'
}

teste_limiar_de_roteamento_e_o_teto_por_requisicao() {
  assert_igual 157286400 "$DBX_TRANSFER_LIMITE_REQUISICAO" '150 MiB por requisicao'
  assert_sucesso dbx_transfer_precisa_de_sessao $((DBX_TRANSFER_LIMITE_REQUISICAO + 1))
  assert_status 1 dbx_transfer_precisa_de_sessao "$DBX_TRANSFER_LIMITE_REQUISICAO"
  assert_status 1 dbx_transfer_precisa_de_sessao 0
}

teste_roteamento_recusa_tamanho_que_nao_e_numero() {
  # O predicado tem de RECUSAR entrada nao numerica em vez de responder "nao
  # precisa de sessao": um arquivo grande roteado por engano para a requisicao
  # unica so falharia no servico, com `payload_too_large`, longe da causa.
  assert_status "$(dbx_errors_codigo_saida uso_invalido)" \
    dbx_transfer_precisa_de_sessao 'abc'
  assert_status "$(dbx_errors_codigo_saida uso_invalido)" \
    dbx_transfer_precisa_de_sessao
}

teste_tamanho_de_arquivo_ausente_ou_ilegivel_e_uso_invalido() {
  assert_status "$(dbx_errors_codigo_saida uso_invalido)" \
    dbx_transfer_tamanho_de_arquivo "$DBX_TESTES_TMP/nao-existe-$$"
  assert_status "$(dbx_errors_codigo_saida uso_invalido)" \
    dbx_transfer_tamanho_de_arquivo
}

teste_tamanho_de_arquivo_vem_do_proprio_arquivo() {
  # Roteamento por tamanho declarado em vez de medido erraria justamente no
  # arquivo que cresce entre a decisao e o envio.
  local caminho
  caminho=$(_massa 4194304)
  assert_sucesso dbx_transfer_tamanho_de_arquivo "$caminho"
  dbx_transfer_tamanho_de_arquivo "$caminho"
  assert_igual 4194304 "$DBX_TRANSFER_TAMANHO" 'o tamanho medido e o do arquivo'
}

# ---------------------------------------------------------------------------
# Sequencia de chamadas e deslocamentos
# ---------------------------------------------------------------------------

teste_fluxo_multiplo_exato_de_partes_emite_a_sequencia_correta() {
  local dir massa
  dir=$(_duplo)
  massa=$(_massa 8388608)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  assert_igual 0 $? "sessao deve concluir; motivo: ${DBX_TRANSFER_MOTIVO:-}"

  assert_igual $'start\nappend\nappend\nfinish' \
    "$(_campo_das_chamadas "$dir" alvo)" \
    'a ordem das chamadas e start, uma append por bloco cheio, finish'
  assert_igual $'0\n4194304\n8388608' "$(_deslocamentos "$dir")" \
    'os deslocamentos avancam de um bloco e o finish fecha no total'
  assert_igual $'0\n4194304\n4194304\n0' "$(_campo_das_chamadas "$dir" bytes)" \
    'o inicio nao carrega dado e o finish fecha com corpo vazio quando o total e multiplo'
  assert_igual 8388608 "$DBX_TRANSFER_BYTES" 'o total enviado e o total lido'
}

teste_fluxo_nao_multiplo_de_partes_fecha_com_o_resto_no_finish() {
  local dir massa
  dir=$(_duplo)
  massa=$(_massa 5242880)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  assert_igual 0 $? "sessao deve concluir; motivo: ${DBX_TRANSFER_MOTIVO:-}"

  assert_igual $'start\nappend\nfinish' "$(_campo_das_chamadas "$dir" alvo)" \
    'resto parcial nao vira append proprio: viaja no finish'
  assert_igual $'0\n4194304' "$(_deslocamentos "$dir")" 'deslocamentos'
  assert_igual $'0\n4194304\n1048576' "$(_campo_das_chamadas "$dir" bytes)" \
    'o resto de 1 MiB e o corpo do finish'
  assert_igual 5242880 "$DBX_TRANSFER_BYTES" 'contagem total'
}

teste_entrada_vazia_produz_arquivo_vazio_com_resumo_do_conteudo_vazio() {
  # RF-31 nao exclui o fluxo vazio, e ele e o caso em que um laco mal escrito
  # nao emite `finish` nenhum e sai com zero — sucesso sem arquivo.
  local dir
  dir=$(_duplo)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" </dev/null
  assert_igual 0 $? "sessao vazia deve concluir; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_igual $'start\nfinish' "$(_campo_das_chamadas "$dir" alvo)" \
    'entrada vazia ainda precisa publicar o arquivo, e portanto emitir finish'
  assert_igual '0' "$(_deslocamentos "$dir")" 'o finish fecha no deslocamento zero'
  assert_igual 0 "$DBX_TRANSFER_BYTES" 'zero bytes lidos'
  assert_igual "$ESPERADO_VAZIO" "$DBX_TRANSFER_CONTENT_HASH" \
    'o resumo do conteudo vazio e o SHA-256 da cadeia vazia'
}

teste_nenhuma_requisicao_isolada_acima_do_teto_por_requisicao() {
  # Com parte de 4 MiB isto e trivialmente verdadeiro. O caso existe para
  # segurar a constante: quem a elevar acima do teto reprova aqui, e nao em
  # producao com `payload_too_large`.
  local dir massa maior=0 valor
  dir=$(_duplo)
  massa=$(_massa 8388608)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  assert_igual 0 $? 'sessao deve concluir'
  while IFS= read -r valor; do
    [[ $valor =~ ^[0-9]+$ ]] || continue
    [[ $valor -gt $maior ]] && maior=$valor
  done < <(_campo_das_chamadas "$dir" bytes)
  [[ $maior -gt 0 ]] ||
    _harness_falhar 'nenhum corpo foi medido: a verificacao seria vacua'
  [[ $maior -le $DBX_TRANSFER_LIMITE_REQUISICAO ]] ||
    _harness_falhar "requisicao isolada acima do teto: $maior bytes"
}

# ---------------------------------------------------------------------------
# RF-31 — teto de ocupacao, permissoes e ausencia de residuo
# ---------------------------------------------------------------------------

teste_ocupacao_maxima_e_de_um_bloco_e_nao_cresce_com_o_numero_de_partes() {
  # ESTE E O CRITERIO CENTRAL DE RF-31. A propriedade nao e "usa pouco disco", e
  # sim "a ocupacao nao acompanha o tamanho do conteudo": duas execucoes com
  # numeros diferentes de partes tem de dar o MESMO pico.
  local dir_dois dir_quatro pico_dois=0 pico_quatro=0
  dir_dois=$(_duplo)
  PATH="$dir_dois:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$(_massa 8388608)"
  assert_igual 0 $? 'sessao de duas partes deve concluir'
  dir_quatro=$(_duplo)
  PATH="$dir_quatro:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$(_massa 16777216)"
  assert_igual 0 $? 'sessao de quatro partes deve concluir'

  read -r pico_dois <"$dir_dois/pico"
  read -r pico_quatro <"$dir_quatro/pico"
  [[ $pico_dois -gt 0 ]] ||
    _harness_falhar 'ocupacao medida como zero: a medicao nao observou nada e seria vacua'
  assert_igual "$pico_dois" "$pico_quatro" \
    'dobrar o conteudo nao pode elevar a ocupacao em disco (RF-31)'
  [[ $pico_dois -le $DBX_TRANSFER_TAMANHO_PARTE ]] ||
    _harness_falhar "ocupacao acima de um bloco: $pico_dois bytes"
}

teste_area_e_bloco_nascem_com_permissao_restrita() {
  local dir modo vistos=0
  dir=$(_duplo)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$(_massa 8388608)"
  assert_igual 0 $? 'sessao deve concluir'
  while IFS= read -r modo; do
    vistos=$((vistos + 1))
    assert_igual 700 "$modo" 'a area temporaria e 0700'
  done <"$dir/perm_area"
  [[ $vistos -gt 0 ]] ||
    _harness_falhar 'nenhuma permissao de area observada: a verificacao seria vacua'
  vistos=0
  while IFS= read -r modo; do
    vistos=$((vistos + 1))
    assert_igual 600 "$modo" 'o arquivo de bloco e 0600'
  done <"$dir/perm_arquivo"
  [[ $vistos -gt 0 ]] ||
    _harness_falhar 'nenhuma permissao de arquivo observada: a verificacao seria vacua'
}

teste_nenhum_residuo_temporario_apos_sucesso() {
  local dir antes depois
  dir=$(_duplo)
  antes=$(_conteudo_do_tmpdir)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$(_massa 5242880)"
  assert_igual 0 $? 'sessao deve concluir'
  depois=$(_conteudo_do_tmpdir)
  assert_igual "$antes" "$depois" \
    'a sessao nao pode deixar area temporaria para tras (RNF-05, PRJ-DEC-07)'
}

teste_falha_de_leitura_no_meio_nao_publica_nada_e_nao_deixa_residuo() {
  # A origem que falha no meio e o cenario de RF-31 em que um erro silencioso
  # publicaria conteudo truncado como se fosse o arquivo inteiro.
  local dir leitor antes depois status
  dir=$(_duplo)
  leitor="$DBX_TESTES_TMP/leitor-falho-transfer.$$"
  mkdir -p "$leitor"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf %s\n' "'PARCIAL'"
    printf 'exit 1\n'
  } >"$leitor/head"
  chmod +x "$leitor/head"

  antes=$(_conteudo_do_tmpdir)
  PATH="$leitor:$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" </dev/null
  status=$?
  depois=$(_conteudo_do_tmpdir)

  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$status" \
    'leitura que falha e operacao nao concluida, nunca sucesso parcial'
  assert_igual 0 "$(_harness_contar 'alvo=finish' "$dir/chamadas")" \
    'nada pode ser publicado: sem finish nao existe arquivo no destino'
  assert_igual "$antes" "$depois" 'nenhum residuo apos falha de leitura'
}

teste_interrupcao_com_o_tratador_armado_nao_publica_nada_e_esvazia_o_tmpdir() {
  # Sinal chega enquanto a sessao esta em curso. Sem tratamento, a area
  # sobreviveria ao processo e o `finish` poderia ainda ser emitido.
  #
  # O NOME DIZ O RECORTE, de proposito. A versao anterior deste caso se chamava
  # "nao_deixa_residuo" e comparava apenas o glob `dbx-transfer.*`: ele
  # CERTIFICAVA uma propriedade falsa. Medido no produto real — `bin/dbx upload -
  # /r/a.bin` com 40 MiB e `kill -TERM` durante o terceiro `append` — nada era
  # publicado, a area do transfer sumia, o codigo era 14, e `$TMPDIR` ficava com
  # `dbx-http.XXXX/{erro_cliente,cabecalhos,resposta}`. O caso aprovava.
  #
  # O que este caso afirma AGORA, e so isto: quando o sinal chega com o tratador
  # de `dbx_transfer_sessao` ARMADO, o TMPDIR inteiro termina vazio. A garantia
  # nao se estende a sinal recebido fora dessa janela — antes do `trap`, depois
  # do `trap -`, ou durante um `upload` por requisicao unica, que nao passa pelo
  # transfer. Nesses caminhos `lib/http` continua vazando pelo mesmo motivo
  # (`trap ... RETURN` nao dispara em `exit` nem em sinal), e a correcao
  # estrutural e o componente `lib/tmp`. Pendencia aberta, nao coberta aqui.
  local dir antes depois status
  dir=$(_duplo)
  printf 'append:1\n' >"$dir/matar"
  antes=$(_conteudo_do_tmpdir)
  PATH="$dir:$PATH" timeout 60 bash -c '
    printf "%s" "$$" >"$2/pid"
    . "$1/lib/errors.sh" || exit 90
    . "$1/lib/json.sh"   || exit 90
    . "$1/lib/http.sh"   || exit 90
    . "$1/lib/auth.sh"   || exit 90
    . "$1/lib/hash.sh"   || exit 90
    . "$1/lib/transfer.sh" || exit 90
    DBX_AUTH_TOKEN=sl.t
    DBX_AUTH_EXPIRA_EM=$((SECONDS + 3600))
    dbx_transfer_sessao "$3" <"$4"
  ' _ "$DBX_HARNESS_RAIZ" "$dir" "$COMMIT_DE_TESTE" "$(_massa 8388608)" >/dev/null 2>&1
  status=$?
  depois=$(_conteudo_do_tmpdir)

  assert_diferente 0 "$status" 'interrupcao nao pode sair como sucesso'
  assert_igual 0 "$(_harness_contar 'alvo=finish' "$dir/chamadas")" \
    'interrompida antes do finish, a sessao abandonada expira sozinha e nada e publicado'
  assert_igual "$antes" "$depois" \
    'com o tratador armado, a interrupcao esvazia o TMPDIR inteiro, e nao so a area do transfer'
}

# ---------------------------------------------------------------------------
# RF-09 — retentativa por parte e reconciliacao de deslocamento
# ---------------------------------------------------------------------------

teste_falha_transitoria_reenvia_apenas_a_parte_afetada() {
  # A propriedade que importa nao e "termina bem": e que o arquivo INTEIRO nao
  # reinicia. Uma implementacao que recomecasse a sessao tambem terminaria bem e
  # passaria num caso que so olhasse o desfecho.
  local dir massa
  dir=$(_duplo)
  printf '500\n200\n' >"$dir/cod_append"
  massa=$(_massa 8388608)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  assert_igual 0 $? "falha transitoria em uma parte nao pode derrubar a sessao; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_igual 1 "$(_harness_contar 'alvo=start' "$dir/chamadas")" \
    'o arquivo inteiro nao reinicia: uma unica sessao'
  assert_igual 3 "$(_harness_contar 'alvo=append' "$dir/chamadas")" \
    'a parte recusada e reenviada e a seguinte segue: 2 tentativas da primeira e 1 da segunda'
  assert_igual $'0\n0\n4194304\n8388608' "$(_deslocamentos "$dir")" \
    'a retentativa repete o MESMO deslocamento, que e a chave de deduplicacao'
}

teste_incorrect_offset_coerente_conta_como_parte_ja_aceita() {
  # Contrato DOCUMENTADO (nao exercitado contra o servico): a resposta de uma
  # tentativa anterior pode ter se perdido com a parte ja aplicada. O servico
  # informa o deslocamento correto; se ele for exatamente o fim desta parte, a
  # parte esta aplicada e insistir duplicaria conteudo.
  local dir massa
  dir=$(_duplo)
  printf '409\n' >"$dir/cod_append"
  printf '%s' '{"error_summary":"incorrect_offset/...","error":{".tag":"incorrect_offset","correct_offset":4194304}}' \
    >"$dir/corpo_append"
  massa=$(_massa 5242880)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  assert_igual 0 $? "deslocamento coerente e progresso, nao falha; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_igual 1 "$(_harness_contar 'alvo=finish' "$dir/chamadas")" \
    'a sessao prossegue ate publicar'
}

teste_incorrect_offset_incoerente_aborta_com_diagnostico_util() {
  # Qualquer outro valor significa que o servico e nos discordamos sobre o que
  # ja chegou. A entrada padrao nao e posicionavel: reposicionar nao e opcao, e
  # continuar publicaria um arquivo embaralhado.
  local dir massa status
  dir=$(_duplo)
  printf '409\n' >"$dir/cod_append"
  printf '%s' '{"error_summary":"incorrect_offset/...","error":{".tag":"incorrect_offset","correct_offset":1234}}' \
    >"$dir/corpo_append"
  massa=$(_massa 5242880)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  status=$?
  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$status" \
    'discordancia de deslocamento e operacao nao concluida'
  assert_igual 0 "$(_harness_contar 'alvo=finish' "$dir/chamadas")" \
    'nada e publicado quando os deslocamentos divergem'
  assert_contem '4194304' "$DBX_TRANSFER_MOTIVO" 'o diagnostico diz o deslocamento esperado'
  assert_contem '1234' "$DBX_TRANSFER_MOTIVO" 'o diagnostico diz o deslocamento recebido'
}

teste_tag_que_apenas_contem_incorrect_offset_nao_entra_no_ramo_de_deslocamento() {
  # A REGRA DE `incorrect_offset` TEM UM DONO SO: `lib/errors.sh`. Este caso
  # existe para impedir que ela volte a ter dois.
  #
  # A versao anterior de `_dbx_transfer_anexar` reconhecia a tag por SUBSTRING
  # (`*incorrect_offset*`), decidindo de novo o que a taxonomia ja decide. Com
  # `path/conflict/incorrect_offset_like` os dois donos divergiam, e a
  # divergencia foi MEDIDA: a taxonomia dizia `classe=conflito, politica=nenhuma`
  # e o transfer entrava no ramo de deslocamento e abortava dizendo "por
  # deslocamento incorreto". Falha fechada, sim — com DIAGNOSTICO ERRADO,
  # mandando investigar deslocamento diante de um conflito de caminho.
  #
  # O criterio agora e a POLITICA publicada por lib/http, que e a taxonomia
  # falando. Reintroduzir o reconhecimento por substring reprova aqui.
  local dir massa status
  dir=$(_duplo)
  printf '409\n' >"$dir/cod_append"
  printf '%s' '{"error_summary":"path/conflict/incorrect_offset_like/...","error":{".tag":"path"}}' \
    >"$dir/corpo_append"
  massa=$(_massa 5242880)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  status=$?

  assert_igual "$(dbx_errors_codigo_saida conflito)" "$status" \
    'a classe vem da taxonomia: conflito de caminho e conflito, nao deslocamento'
  assert_igual 'conflito' "$DBX_TRANSFER_CLASSE" \
    'a classe publicada e a que o comando usa para redigir e sair'
  assert_nao_contem 'deslocamento' "$DBX_TRANSFER_MOTIVO" \
    'diagnostico de deslocamento diante de conflito de caminho manda investigar o lugar errado'
  assert_igual 0 "$(_harness_contar 'alvo=finish' "$dir/chamadas")" \
    'nada e publicado quando a parte e recusada'
}

teste_sessao_invalidada_pelo_servico_aborta_com_diagnostico_proprio() {
  # `reset` recebe politica `reiniciar` da taxonomia, e reiniciar EXIGE reler a
  # origem desde o inicio. Com entrada padrao isso e impossivel. Antes desta
  # correcao o caso caia no ramo generico: falha fechada, mas sem dizer que o
  # motivo era invalidacao de sessao — o operador ficava com "parte recusada" e
  # uma tag crua.
  local dir massa status
  dir=$(_duplo)
  printf '409\n' >"$dir/cod_append"
  printf '%s' '{"error_summary":"reset/...","error":{".tag":"reset"}}' \
    >"$dir/corpo_append"
  massa=$(_massa 5242880)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  status=$?

  assert_igual "$(dbx_errors_codigo_saida nao_concluida)" "$status" \
    'sessao invalidada e operacao nao concluida'
  assert_contem 'reiniciar' "$DBX_TRANSFER_MOTIVO" \
    'o diagnostico precisa dizer que o servico exige reiniciar o envio'
  assert_contem 'posicionavel' "$DBX_TRANSFER_MOTIVO" \
    'e por que reiniciar nao e possivel a partir da entrada padrao'
  assert_igual 0 "$(_harness_contar 'alvo=finish' "$dir/chamadas")" \
    'nada e publicado quando a sessao e invalidada'
}

teste_a_sessao_devolve_a_umask_que_recebeu() {
  # A mascara e estado do PROCESSO. `lib/config.sh` ja salva e restaura; o irmao
  # novo nao salvava, e a sessao devolvia 0077 a quem entrou com 0022 — a forma
  # exata da familia de gemeos, ainda que o valor deixado fosse o mais estrito.
  local dir antes depois
  dir=$(_duplo)
  antes=$(umask)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" </dev/null
  assert_igual 0 $? "sessao deve concluir; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  depois=$(umask)
  assert_igual "$antes" "$depois" \
    'a sessao devolve a umask do chamador, e nao a que ela usou internamente'
}

teste_a_umask_e_devolvida_tambem_quando_a_area_temporaria_falha() {
  # O caminho de erro e onde a restauracao costuma faltar: quem escreve o par
  # lembra do retorno feliz e esquece da porta lateral.
  local dir antes depois status
  dir=$(_duplo)
  antes=$(umask)
  PATH="$dir:$PATH" TMPDIR="$DBX_TESTES_TMP/nao-existe-$$/mais-fundo" \
    dbx_transfer_sessao "$COMMIT_DE_TESTE" </dev/null
  status=$?
  depois=$(umask)
  assert_igual "$(dbx_errors_codigo_saida configuracao)" "$status" \
    'area temporaria indisponivel e problema de configuracao do host'
  assert_igual "$antes" "$depois" \
    'a umask volta ao valor do chamador tambem pela porta de erro'
}

# ---------------------------------------------------------------------------
# Integridade ponta a ponta
# ---------------------------------------------------------------------------

teste_content_hash_do_finish_divergente_do_local_e_integridade() {
  local dir massa status
  dir=$(_duplo)
  printf '%s' '{"name":"a.bin","content_hash":"0000000000000000000000000000000000000000000000000000000000000000"}' \
    >"$dir/corpo_finish"
  massa=$(_massa 5242880)
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  status=$?
  assert_igual "$(dbx_errors_codigo_saida integridade)" "$status" \
    'resumo divergente e classe integridade, nunca sucesso'
  assert_igual 'integridade' "$DBX_TRANSFER_CLASSE" \
    'a classe publicada e a que o comando usa para redigir e sair'
  assert_contem 'resumo' "$DBX_TRANSFER_MOTIVO" \
    'o diagnostico precisa dizer que o que divergiu foi o resumo, e nao a rede'
}

teste_content_hash_coincidente_declara_integridade_conferida() {
  local dir massa esperado
  dir=$(_duplo)
  massa=$(_massa 5242880)
  esperado=$(dbx_hash_conteudo_arquivo "$massa")
  printf '%s' "{\"name\":\"a.bin\",\"content_hash\":\"$esperado\"}" >"$dir/corpo_finish"
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$massa"
  assert_igual 0 $? "resumo coincidente deve concluir; motivo: ${DBX_TRANSFER_MOTIVO:-}"
  assert_igual 'conferida' "$DBX_TRANSFER_INTEGRIDADE" 'a conferencia ocorreu e e declarada'
  assert_igual "$esperado" "$DBX_TRANSFER_CONTENT_HASH" 'o resumo local acompanha o envio'
}

teste_sem_resumo_no_finish_a_integridade_nao_e_afirmada() {
  # Afirmar verificacao que nao ocorreu e pior que nao verificar. Mesmo criterio
  # ja adotado em `download`.
  local dir
  dir=$(_duplo)
  printf '%s' '{"name":"a.bin","rev":"016"}' >"$dir/corpo_finish"
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" <"$(_massa 5242880)"
  assert_igual 0 $? 'ausencia de resumo do servico nao e falha'
  assert_igual 'nao_aplicavel' "$DBX_TRANSFER_INTEGRIDADE" \
    'sem resumo publicado pelo servico a verificacao nao pode ser afirmada'
}

# ---------------------------------------------------------------------------
# RF-15 — segunda linha de defesa contra escrita em simulacao
# ---------------------------------------------------------------------------

teste_simulacao_nao_alcanca_a_sessao_e_falha_fechado() {
  # O gate de simulacao vive no comando, ANTES da bifurcacao de escrita. Esta
  # guarda existe para o caso de um chamador futuro esquecer: falha fechada, e
  # nao emissao silenciosa. Removida a guarda, o caso reprova por haver chamada.
  local dir status
  dir=$(_duplo)
  DBX_CLI_SIMULACAO='sim'
  PATH="$dir:$PATH" dbx_transfer_sessao "$COMMIT_DE_TESTE" </dev/null
  status=$?
  DBX_CLI_SIMULACAO='nao'
  assert_diferente 0 "$status" 'sessao alcancada em simulacao e defeito do chamador'
  assert_arquivo_ausente "$dir/argv" 'RF-15: nenhuma chamada pode ser emitida em simulacao'
}

teste_commit_ausente_e_uso_invalido() {
  local dir status
  dir=$(_duplo)
  PATH="$dir:$PATH" dbx_transfer_sessao ''
  status=$?
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$status" \
    'sem argumento de commit nao ha o que publicar'
  assert_arquivo_ausente "$dir/argv" 'sem commit nao ha o que iniciar'
}

harness_executar "$@"
