#!/usr/bin/env bash
# Testes diretos de lib/state.sh — o cache unico de `content_hash` (fase 3).
#
# RNF-32(d): ate a fase 3 nenhum teste carregava `lib/state` diretamente; ele so
# era exercitado pelo `sync` ponta a ponta. Estes casos cobrem carga, gravacao
# atomica, descarte de corrupcao, os dois namespaces (`memoria-*` do `sync`,
# `upload-*` do `upload`), a identidade forte, a poda e o diretorio de estado.
#
# Os casos montam o estado em `XDG_STATE_HOME` proprio, e cada um roda em
# subshell do harness: nada vaza entre casos.
#
# shellcheck disable=SC2034
# Justificativa: vetores e canais lidos por referencia de nome em lib/state.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/json.sh"
. "$DBX_HARNESS_RAIZ/lib/config.sh"
. "$DBX_HARNESS_RAIZ/lib/state.sh"

readonly HASH_A='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
readonly HASH_B='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'

# _area — diretorio de ensaio com XDG_STATE_HOME proprio; publica AREA e ESTADO.
_area() {
  AREA=$(mktemp -d "$DBX_TESTES_TMP/estado.XXXXXX")
  export XDG_STATE_HOME="$AREA/xdg"
  ESTADO="$XDG_STATE_HOME/dbx"
}

# _arquivo_antigo <caminho> <conteudo> — arquivo com `mtime` no passado, para
# que a regra anti-corrida de 2 s nao impeca o registro.
_arquivo_antigo() {
  printf '%s' "$2" >"$1"
  touch -d '@1700000000.250000000' "$1"
}

# _identidade <arquivo> — identidade atual, pela definicao unica de lib/hash.
_identidade() {
  dbx_hash_identidade "$1" || _harness_falhar "sem identidade para $1"
  IDENT=$DBX_HASH_IDENTIDADE
}

_contar() { # <padrao_glob> — quantos arquivos casam no diretorio de estado
  local -a lista=()
  shopt -s nullglob dotglob
  # shellcheck disable=SC2206  # o padrao e um glob, e deve expandir
  lista=("$ESTADO"/$1)
  shopt -u nullglob dotglob
  printf '%s' "${#lista[@]}"
}

_modo() { stat -c '%a' -- "$1"; }

# ---------------------------------------------------------------------------
# Namespace do upload (RF-61(a), RF-62(b))
# ---------------------------------------------------------------------------

teste_upload_grava_e_reaproveita_com_identidade_identica() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  assert_sucesso dbx_state_upload_gravar /canonico/a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_upload_consultar /canonico/a.txt "$IDENT"
  assert_igual 0 $? 'identidade igual reaproveita o resumo'
  assert_igual "$HASH_A" "$DBX_STATE_HASH" 'o resumo gravado volta intacto'
}

teste_upload_nao_reaproveita_quando_qualquer_campo_da_identidade_difere() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  local campo partes alterada
  for campo in 0 1 2 3 4 5; do
    IFS='|' read -r -a partes <<<"$IDENT"
    partes[campo]="9${partes[campo]}"
    printf -v alterada '%s|' "${partes[@]}"
    alterada=${alterada%|}
    dbx_state_upload_consultar /c/a.txt "$alterada"
    assert_igual 1 $? "campo $campo da identidade divergente nao pode reaproveitar"
    assert_igual '' "$DBX_STATE_HASH" 'nada publicado na falta'
  done
}

teste_upload_nao_grava_quando_o_stat_muda_durante_o_calculo() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  local antes=$IDENT
  printf 'outro conteudo' >"$AREA/a.txt"
  touch -d '@1700000000.250000000' "$AREA/a.txt"
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$antes" "$IDENT"
  assert_diferente 0 $? 'stat antes e depois divergentes nao gravam (RF-61(c))'
  assert_igual 0 "$(_contar 'upload-*')" 'nenhum registro criado'
}

teste_upload_nao_grava_arquivo_modificado_ha_menos_de_dois_segundos() {
  _area
  printf 'recente' >"$AREA/a.txt"
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_diferente 0 $? 'anti-corrida de 2 s (RF-61(d))'
  assert_igual 0 "$(_contar 'upload-*')" 'nenhum registro criado'
}

teste_upload_sem_cache_para_arquivo_vazio_e_para_fila_nomeada() {
  _area
  : >"$AREA/vazio"
  touch -d '@1700000000' "$AREA/vazio"
  _identidade "$AREA/vazio"
  dbx_state_upload_gravar /c/vazio "$HASH_A" "$IDENT" "$IDENT"
  assert_diferente 0 $? 'arquivo de tamanho 0 nao e cacheado (RF-61(e))'
  dbx_state_upload_consultar /c/vazio "$IDENT"
  assert_igual 1 $? 'nem consultado'
  if mkfifo "$AREA/cano" 2>/dev/null; then
    touch -d '@1700000000' "$AREA/cano"
    _identidade "$AREA/cano"
    dbx_state_upload_gravar /c/cano "$HASH_A" "$IDENT" "$IDENT"
    assert_diferente 0 $? 'fila nomeada nao e cacheada (RF-61(e))'
  fi
  assert_igual 0 "$(_contar 'upload-*')" 'nenhum registro criado'
}

teste_nome_do_arquivo_de_cache_nao_carrega_texto_do_caminho() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  local chave=$'/home/u/segredo\n../../nome.txt'
  dbx_state_upload_caminho "$chave"
  local nome=${DBX_STATE_RESULTADO##*/}
  assert_igual "$ESTADO" "${DBX_STATE_RESULTADO%/*}" 'o cache mora no diretorio de estado'
  [[ $nome =~ ^upload-[0-9a-f]{32}$ ]] ||
    _harness_falhar 'o nome e upload- seguido de 32 hexadecimais (RF-62(b))' "obtido: [$nome]"
  dbx_state_upload_gravar "$chave" "$HASH_A" "$IDENT" "$IDENT"
  assert_arquivo_existe "$DBX_STATE_RESULTADO" 'gravado no nome derivado por resumo'
  dbx_state_upload_caminho /outra/chave
  assert_diferente "$ESTADO/$nome" "$DBX_STATE_RESULTADO" 'chaves diferentes, arquivos diferentes'
}

teste_namespaces_do_upload_e_do_sync_nao_se_tocam() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_igual 0 "$(_contar 'memoria-*')" 'upload nunca cria memoria-* (protecao de RF-48)'
  dbx_state_carregar dbid:C /origem /destino
  assert_igual 'nao' "$DBX_STATE_VISTO" 'par de raizes continua nunca visto'
  dbx_state_registrar a.txt "$HASH_B" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:C /origem /destino
  assert_igual 1 "$(_contar 'upload-*')" 'sync nao cria upload-*'
  assert_igual 1 "$(_contar 'memoria-*')" 'e grava o proprio namespace'
}

# ---------------------------------------------------------------------------
# Corrupcao e estado hostil (RF-42; Regra 6 de protocolo-tdd)
# ---------------------------------------------------------------------------

teste_registro_de_upload_corrompido_e_descartado_sem_falhar() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_upload_caminho /c/a.txt
  local arquivo=$DBX_STATE_RESULTADO variante
  # Cada variante e escrita byte a byte com printf, e nao capturada: o NUL nao
  # cabe em variavel.
  for variante in versao tipo chave truncado hash_invalido campo_texto nul_extra; do
    case $variante in
      versao) printf '9\0upload\0/c/a.txt\0%s\t%s\0' "$HASH_A" "$IDENT" >"$arquivo" ;;
      tipo) printf '2\0sync\0/c/a.txt\0%s\t%s\0' "$HASH_A" "$IDENT" >"$arquivo" ;;
      chave) printf '2\0upload\0/c/outro.txt\0%s\t%s\0' "$HASH_A" "$IDENT" >"$arquivo" ;;
      truncado) printf '2\0upload\0/c/a.txt\0%s' "$HASH_A" >"$arquivo" ;;
      hash_invalido) printf '2\0upload\0/c/a.txt\0%s\t%s\0' 'zz' "$IDENT" >"$arquivo" ;;
      campo_texto) printf '2\0upload\0/c/a.txt\0%s\t%s\0' "$HASH_A" "${IDENT/|/|x}" >"$arquivo" ;;
      nul_extra) printf '2\0upload\0/c/a.txt\0%s\0\t%s\0' "$HASH_A" "$IDENT" >"$arquivo" ;;
    esac
    dbx_state_upload_consultar /c/a.txt "$IDENT"
    assert_igual 1 $? "registro corrompido ($variante) nao pode ser reaproveitado"
    assert_igual '' "$DBX_STATE_HASH" "nada publicado ($variante)"
  done
  # E a gravacao seguinte reconstroi.
  assert_sucesso dbx_state_upload_gravar /c/a.txt "$HASH_B" "$IDENT" "$IDENT"
  dbx_state_upload_consultar /c/a.txt "$IDENT"
  assert_igual "$HASH_B" "$DBX_STATE_HASH" 'registro reconstruido apos o descarte'
}

teste_memoria_do_sync_corrompida_ou_hostil_e_descartada() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_registrar a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:C /o /d
  dbx_state_caminho dbid:C /o /d
  local arquivo=$DBX_STATE_RESULTADO
  # Versao 1 (formato anterior, sem identidade forte): descartada, mas o par
  # continua "visto" — corrupcao prova execucao anterior (RF-48).
  printf '1\0dbid:C\0/o\0/d\0%s\t4\t1700000000\ta.txt\0' "$HASH_A" >"$arquivo"
  dbx_state_carregar dbid:C /o /d
  assert_igual 'sim' "$DBX_STATE_VISTO" 'memoria ilegivel ainda prova execucao anterior'
  assert_igual 0 "${#DBX_STATE_ENTRADA[@]}" 'versao anterior e descartada'
  # Cabecalho de outra conta.
  printf '2\0dbid:OUTRA\0/o\0/d\0%s\t%s\ta.txt\0' "$HASH_A" "$IDENT" >"$arquivo"
  dbx_state_carregar dbid:C /o /d
  assert_igual 0 "${#DBX_STATE_ENTRADA[@]}" 'conta divergente descarta (RF-52)'
  # Registros hostis: hash fora do formato, identidade sem campos, caminho que
  # sai da raiz. Os dois primeiros sao ignorados; o terceiro nunca e usado para
  # abrir arquivo e sai na proxima gravacao completa.
  printf '2\0dbid:C\0/o\0/d\0%s\t%s\tok.txt\0zz\t%s\truim.txt\0%s\tsem-identidade\toutro.txt\0' \
    "$HASH_A" "$IDENT" "$IDENT" "$HASH_A" >"$arquivo"
  dbx_state_carregar dbid:C /o /d
  assert_igual 1 "${#DBX_STATE_ENTRADA[@]}" 'so o registro bem formado entra'
  dbx_state_consultar ok.txt "$IDENT"
  assert_igual "$HASH_A" "$DBX_STATE_HASH" 'o registro bem formado e reaproveitado'
}

teste_memoria_existente_e_ilegivel_conta_como_descartada() {
  # QA-P3-07: memoria que EXISTE e nao pode ser lida nao e memoria ausente —
  # o par ja foi visto, e a linha de base sumiu.
  [[ $EUID -ne 0 ]] || pular 'root le arquivo sem permissao'
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_registrar a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:C /o /d
  dbx_state_caminho dbid:C /o /d
  chmod 000 "$DBX_STATE_RESULTADO"
  dbx_state_carregar dbid:C /o /d
  assert_igual 'sim' "$DBX_STATE_VISTO" 'o par continua visto'
  assert_igual 'sim' "$DBX_STATE_DESCARTADA" 'e a memoria conta como descartada'
  assert_igual 0 "${#DBX_STATE_ENTRADA[@]}" 'sem base'
  dbx_state_carregar dbid:C /o /nunca-visto
  assert_igual 'nao' "$DBX_STATE_DESCARTADA" 'memoria ausente nao e descartada'
  assert_igual 'nao' "$DBX_STATE_VISTO" 'nem vista'
}

# ---------------------------------------------------------------------------
# Memoria do sync: identidade forte e entradas visitadas (RF-38(b), (e))
# ---------------------------------------------------------------------------

teste_sync_reaproveita_so_com_identidade_identica() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_carregar dbid:C /o /d
  dbx_state_registrar a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_igual 0 $? 'identidade estavel e antiga registra'
  dbx_state_gravar dbid:C /o /d
  dbx_state_carregar dbid:C /o /d
  dbx_state_consultar a.txt "$IDENT"
  assert_igual "$HASH_A" "$DBX_STATE_HASH" 'reaproveita apos recarregar'
  dbx_state_consultar a.txt "${IDENT%|*}|999"
  assert_igual 1 $? 'tamanho divergente nao reaproveita'
}

teste_sync_nao_registra_stat_divergente_nem_mtime_recente() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  local antes=$IDENT
  printf 'agora mesmo' >"$AREA/b.txt"
  _identidade "$AREA/b.txt"
  dbx_state_carregar dbid:C /o /d
  dbx_state_registrar a.txt "$HASH_A" "$antes" "$IDENT"
  assert_diferente 0 $? 'stat antes e depois divergentes nao registram'
  dbx_state_registrar b.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_diferente 0 $? 'mtime a menos de 2 s nao registra'
  dbx_state_gravar dbid:C /o /d
  dbx_state_carregar dbid:C /o /d
  dbx_state_consultar a.txt "$antes"
  assert_igual 1 $? 'nenhum resumo reaproveitavel de a.txt'
  dbx_state_consultar b.txt "$IDENT"
  assert_igual 1 $? 'nenhum resumo reaproveitavel de b.txt'
}

teste_caminho_sem_resumo_admissivel_continua_registrado_como_presente() {
  # RF-41(b) le a memoria para recusar a origem que ficou vazia. Arvore de
  # arquivos recem-criados (todos na janela anti-corrida) nao pode deixar a
  # memoria vazia, ou a recusa nunca dispara.
  _area
  printf 'agora mesmo' >"$AREA/b.txt"
  _identidade "$AREA/b.txt"
  dbx_state_carregar dbid:C /o /d
  dbx_state_registrar b.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:C /o /d sim
  dbx_state_carregar dbid:C /o /d
  assert_igual 1 "${#DBX_STATE_ENTRADA[@]}" 'o caminho continua registrado na memoria'
  dbx_state_consultar b.txt "$IDENT"
  assert_igual 1 $? 'mas sem resumo a reaproveitar'
}

teste_gravacao_completa_guarda_so_as_entradas_visitadas() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'aaaa'
  _identidade "$AREA/a.txt"
  dbx_state_carregar dbid:C /o /d
  dbx_state_registrar a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_registrar apagado.txt "$HASH_B" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:C /o /d
  # Execucao seguinte: so a.txt existe na origem.
  dbx_state_carregar dbid:C /o /d
  dbx_state_consultar a.txt "$IDENT"
  dbx_state_gravar dbid:C /o /d sim
  dbx_state_carregar dbid:C /o /d
  assert_igual 1 "${#DBX_STATE_ENTRADA[@]}" 'travessia completa: o apagado sai (TC-MEM-04)'
  dbx_state_consultar a.txt "$IDENT"
  assert_igual "$HASH_A" "$DBX_STATE_HASH" 'o visitado permanece'
}

teste_gravacao_parcial_preserva_as_entradas_nao_visitadas() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'aaaa'
  _identidade "$AREA/a.txt"
  dbx_state_carregar dbid:C /o /d
  dbx_state_registrar a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_registrar ramo/b.txt "$HASH_B" "$IDENT" "$IDENT"
  dbx_state_gravar dbid:C /o /d
  dbx_state_carregar dbid:C /o /d
  dbx_state_consultar a.txt "$IDENT"
  dbx_state_gravar dbid:C /o /d nao
  dbx_state_carregar dbid:C /o /d
  assert_igual 2 "${#DBX_STATE_ENTRADA[@]}" 'travessia parcial preserva o ramo nao visitado (TC-MEM-05)'
}

# ---------------------------------------------------------------------------
# Gravacao atomica e diretorio de estado (RNF-25)
# ---------------------------------------------------------------------------

teste_diretorio_de_estado_nasce_0700_e_arquivos_0600() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  umask 022
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_igual 700 "$(_modo "$ESTADO")" 'diretorio criado em 0700 com umask 022 (TC-EST)'
  dbx_state_upload_caminho /c/a.txt
  assert_igual 600 "$(_modo "$DBX_STATE_RESULTADO")" 'registro em 0600'
  assert_igual 0 "$(_contar '.upload.*')" 'nenhum temporario sobra'
  dbx_state_gravar dbid:C /o /d
  dbx_state_caminho dbid:C /o /d
  assert_igual 600 "$(_modo "$DBX_STATE_RESULTADO")" 'memoria do sync em 0600'
  assert_igual 0 "$(_contar '.memoria.*')" 'nenhum temporario sobra'
}

teste_diretorio_existente_do_usuario_e_corrigido_para_0700() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  mkdir -p "$ESTADO"
  chmod 755 "$ESTADO"
  assert_sucesso dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_igual 700 "$(_modo "$ESTADO")" 'TC-EST-04: 0755 do usuario corrigido na gravacao'
  chmod 755 "$ESTADO"
  dbx_state_gravar dbid:C /o /d
  assert_igual 700 "$(_modo "$ESTADO")" 'a gravacao do sync corrige igualmente'
}

teste_diretorio_de_outro_dono_e_recusado_como_permissao_sem_escrita() {
  [[ $EUID -ne 0 ]] || pular 'como root todo diretorio pertence ao usuario'
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  # Diretorio de estado que resolve para um diretorio do sistema, de outro dono.
  mkdir -p "$XDG_STATE_HOME"
  ln -s /usr "$ESTADO"
  local antes depois estado permissao
  permissao=$(dbx_errors_codigo_saida permissao)
  antes=$(stat -c '%a %Y' /usr)
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  estado=$?
  assert_igual "$permissao" "$estado" 'recusa com a classe permissao (RNF-25(b1))'
  dbx_state_gravar dbid:C /o /d
  estado=$?
  assert_igual "$permissao" "$estado" 'a memoria do sync tambem recusa'
  depois=$(stat -c '%a %Y' /usr)
  assert_igual "$antes" "$depois" 'nem modo nem conteudo do diretorio alheio mudam'
  dbx_state_carregar dbid:C /o /d
  assert_igual 'nao' "$DBX_STATE_VISTO" 'diretorio alheio nao e lido nem prova execucao'
  dbx_state_upload_consultar /c/a.txt "$IDENT"
  assert_igual 1 $? 'nem o cache do upload e lido de diretorio alheio'
}

teste_registro_hostil_que_e_diretorio_nao_recebe_a_gravacao() {
  # Estado hostil: no lugar do registro, um diretorio. `mv` moveria o
  # temporario PARA DENTRO dele e diria que deu certo.
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_upload_caminho /c/a.txt
  local alvo=$DBX_STATE_RESULTADO
  mkdir -p "$alvo"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_diferente 0 $? 'gravacao sobre diretorio falha'
  local -a dentro=()
  shopt -s nullglob dotglob
  dentro=("$alvo"/*)
  shopt -u nullglob dotglob
  assert_igual 0 "${#dentro[@]}" 'nada e movido para dentro do diretorio hostil'
  assert_igual 0 "$(_contar '.upload.*')" 'e o temporario nao sobra'
}

teste_reescrita_do_registro_e_atomica_por_renomeacao() {
  # O leitor nunca ve registro pela metade: o arquivo novo nasce com outro
  # inode (temporario no mesmo diretorio, depois renomeado), e o anterior so
  # deixa de existir quando o novo ja esta inteiro.
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_upload_caminho /c/a.txt
  local inode_antes inode_depois
  inode_antes=$(stat -c '%i' -- "$DBX_STATE_RESULTADO")
  dbx_state_upload_gravar /c/a.txt "$HASH_B" "$IDENT" "$IDENT"
  inode_depois=$(stat -c '%i' -- "$DBX_STATE_RESULTADO")
  assert_diferente "$inode_antes" "$inode_depois" 'substituicao por renomeacao, e nao reescrita no lugar'
  dbx_state_upload_consultar /c/a.txt "$IDENT"
  assert_igual "$HASH_B" "$DBX_STATE_HASH" 'o registro novo e o vigente'
}

teste_temporarios_orfaos_antigos_saem_e_os_recentes_ficam() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  mkdir -p "$ESTADO"
  : >"$ESTADO/.memoria.111.AAAAAAAA"
  : >"$ESTADO/.upload.222.BBBBBBBB"
  : >"$ESTADO/.upload.333.CCCCCCCC"
  touch -d '2 days ago' "$ESTADO/.memoria.111.AAAAAAAA" "$ESTADO/.upload.222.BBBBBBBB"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_arquivo_ausente "$ESTADO/.memoria.111.AAAAAAAA" 'orfao do sync com mais de 1 dia sai'
  assert_arquivo_ausente "$ESTADO/.upload.222.BBBBBBBB" 'orfao do upload com mais de 1 dia sai'
  assert_arquivo_existe "$ESTADO/.upload.333.CCCCCCCC" 'temporario recente pode ser gravacao concorrente'
}

# ---------------------------------------------------------------------------
# Poda do upload (RF-61(i))
# ---------------------------------------------------------------------------

# _povoar <quantidade> — registros upload-* sinteticos, 5 deles sem uso ha 91 dias.
_povoar() {
  local total=$1 i nome
  mkdir -p "$ESTADO"
  chmod 700 "$ESTADO"
  for ((i = 0; i < total; i++)); do
    printf -v nome 'upload-%032x' "$i"
    : >"$ESTADO/$nome"
  done
  touch -d '91 days ago' "$ESTADO"/upload-0000000000000000000000000000000{0,1,2,3,4}
  touch -d '89 days ago' "$ESTADO/upload-00000000000000000000000000000005"
}

teste_poda_acima_do_teto_remove_os_nao_usados_ha_mais_de_90_dias() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  _povoar 10001
  dbx_state_upload_gravar /c/novo.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_igual 9997 "$(_contar 'upload-*')" '10.001 registros, 5 velhos: restam os demais e o novo'
  assert_arquivo_ausente "$ESTADO/upload-00000000000000000000000000000000" 'velho removido'
  assert_arquivo_existe "$ESTADO/upload-00000000000000000000000000000005" '89 dias nao e mais de 90'
}

teste_poda_no_teto_nao_remove_nada() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  _povoar 10000
  dbx_state_upload_gravar /c/novo.txt "$HASH_A" "$IDENT" "$IDENT"
  assert_igual 10001 "$(_contar 'upload-*')" '10.000 registros: nenhum removido'
}

teste_gravacao_renova_o_carimbo_de_uso() {
  _area
  _arquivo_antigo "$AREA/a.txt" 'conteudo'
  _identidade "$AREA/a.txt"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  dbx_state_upload_caminho /c/a.txt
  touch -d '100 days ago' "$DBX_STATE_RESULTADO"
  dbx_state_upload_gravar /c/a.txt "$HASH_A" "$IDENT" "$IDENT"
  local idade
  printf -v idade '%(%s)T' -1
  idade=$((idade - $(stat -c '%Y' -- "$DBX_STATE_RESULTADO")))
  [[ $idade -lt 60 ]] || _harness_falhar 'uso renova o carimbo usado pela poda' "idade: $idade s"
}

harness_executar "$@"
