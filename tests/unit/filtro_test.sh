#!/usr/bin/env bash
# Testes diretos de lib/filtro.sh — casamento gitignore, sem caixa, validacao dos
# padroes, data e tamanho (RF-79, RF-80(a), RF-81; TC-FLT, TC-FES-01/03, TC-FDT).
#
# `lib/filtro` e puro (DIV-94): sem rede, sem disco, sem estado. Por isso a
# semantica inteira do padrao e provada aqui, por unidade, e os testes ponta a
# ponta (`filtros_test`) so provam a ligacao com sync, verificar e download.
#
# shellcheck disable=SC2016,SC1003
# Justificativa: padroes com `$(...)`, crase e `$HOME` precisam chegar literais.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"
. "$DBX_HARNESS_RAIZ/lib/filtro.sh"

USO=$(dbx_errors_codigo_saida uso_invalido)
readonly USO

# _exclui <padrao> <caminho> [sim|nao] — `sim` se o padrao, como --excluir,
# tira o caminho do escopo; `nao` se ele fica.
_exclui() {
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir "$1" || _harness_falhar "padrao recusado: [$1] $DBX_FILTRO_MOTIVO"
  if dbx_filtro_classificar "$2" "${3:-nao}"; then printf 'nao'; else printf 'sim'; fi
}

# _recusa <padrao> — status e motivo da validacao do padrao.
_recusa() {
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir "$1"
}

# ---------------------------------------------------------------------------
# TC-FLT-01..08 — sintaxe
# ---------------------------------------------------------------------------

teste_flt01_padrao_sem_barra_casa_o_nome_em_qualquer_nivel() {
  assert_igual sim "$(_exclui '*.log' a.log)" 'raiz'
  assert_igual sim "$(_exclui '*.log' x/y/a.log)" 'em profundidade'
  assert_igual nao "$(_exclui '*.log' a.log.bak)" 'sufixo a mais'
  assert_igual nao "$(_exclui '*.log' a/log)" 'a barra separa'
}

teste_flt02_estrela_nao_cruza_barra_e_casa_nome_com_ponto() {
  assert_igual sim "$(_exclui 'a/*.txt' a/b.txt)" 'um nivel'
  assert_igual nao "$(_exclui 'a/*.txt' a/c/b.txt)" '* nao cruza /'
  assert_igual sim "$(_exclui '*' .oculto)" 'nome iniciado por ponto'
  assert_igual sim "$(_exclui 'a/*' a/.x)" 'oculto dentro de pasta'
}

teste_flt03_interrogacao_casa_um_caractere() {
  assert_igual sim "$(_exclui 'a?.txt' ab.txt)" 'um caractere'
  assert_igual nao "$(_exclui 'a?.txt' a.txt)" 'zero caracteres'
  assert_igual nao "$(_exclui 'a?.txt' abc.txt)" 'dois caracteres'
  assert_igual nao "$(_exclui 'a?.txt' a/.txt)" 'nunca a barra'
  assert_igual sim "$(_exclui 'a?.txt' $'a\xc3\xa9.txt')" 'com C.UTF-8, e acentuado e um caractere'
}

teste_flt04_conjuntos_faixas_e_negacao_nunca_casam_barra() {
  assert_igual sim "$(_exclui 'x[abc]' xb)" 'conjunto'
  assert_igual nao "$(_exclui 'x[abc]' xd)" 'fora do conjunto'
  assert_igual sim "$(_exclui 'x[a-c]' xc)" 'faixa'
  assert_igual sim "$(_exclui 'x[!0-9]' xa)" 'negacao por !'
  assert_igual nao "$(_exclui 'x[!0-9]' x5)" 'negacao por ! exclui a faixa'
  # QA-B4-02: como no gitignore, `]` logo depois de `[`, `[!` ou `[^` e membro.
  assert_igual sim "$(_exclui 'x[]a]' 'x]')" '[]a] casa ]'
  assert_igual sim "$(_exclui 'x[]a]' xa)" '[]a] casa a'
  assert_igual nao "$(_exclui 'x[]a]' xb)" '[]a] nao casa b'
  assert_igual sim "$(_exclui 'x[!]a]' xb)" '[!]a] casa b'
  assert_igual nao "$(_exclui 'x[!]a]' 'x]')" '[!]a] nao casa ]'
  assert_igual nao "$(_exclui 'x[^]]' 'x]')" '[^]] nao casa ]'
  assert_igual sim "$(_exclui 'x[^0-9]' xa)" 'negacao por ^'
  assert_igual nao "$(_exclui 'x[^0-9]' x7)" 'negacao por ^ exclui a faixa'
  assert_igual nao "$(_exclui 'a[!b]c' a/c)" 'conjunto negado nunca casa /'
}

teste_flt05_duas_estrelas_no_inicio_no_fim_no_meio_e_em_outra_posicao() {
  assert_igual sim "$(_exclui '**/tmp' tmp sim)" '**/ no inicio casa na raiz'
  assert_igual sim "$(_exclui '**/tmp' a/b/tmp sim)" 'e em qualquer nivel'
  assert_igual sim "$(_exclui 'build/**' build/a)" 'descendente de build'
  assert_igual sim "$(_exclui 'build/**' build/x/y)" 'descendente profundo'
  assert_igual nao "$(_exclui 'build/**' x/build/a)" 'ancorado: build fora da raiz nao'
  assert_igual nao "$(_exclui 'build/**' build sim)" 'nao a propria pasta'
  assert_igual sim "$(_exclui 'a/**/b' a/b)" 'zero pastas'
  assert_igual sim "$(_exclui 'a/**/b' a/x/b)" 'uma pasta'
  assert_igual sim "$(_exclui 'a/**/b' a/x/y/b)" 'duas pastas'
  assert_igual nao "$(_exclui 'a/**/b' a/xb)" 'nao junta componentes'
  assert_igual sim "$(_exclui 'a**b' axyb)" 'a**b vale a*b'
  assert_igual nao "$(_exclui 'a**b' a/b)" 'a**b nao cruza /'
  assert_igual sim "$(_exclui '**.log' x/a.log)" '**.log vale *.log'
}

teste_flt06_barra_no_inicio_ou_no_meio_ancora_na_raiz() {
  assert_igual sim "$(_exclui '/build' build)" '/build na raiz'
  assert_igual nao "$(_exclui '/build' x/build)" '/build so na raiz'
  assert_igual sim "$(_exclui 'doc/a.txt' doc/a.txt)" 'barra no meio'
  assert_igual nao "$(_exclui 'doc/a.txt' x/doc/a.txt)" 'ancorado, nunca abaixo'
}

teste_flt07_barra_final_casa_so_pasta_e_tudo_abaixo_dela() {
  assert_igual sim "$(_exclui 'logs/' logs sim)" 'a pasta'
  assert_igual nao "$(_exclui 'logs/' logs nao)" 'nunca o arquivo logs'
  assert_igual sim "$(_exclui 'logs/' x/logs/a.txt)" 'conteudo da pasta, em qualquer nivel'
  assert_igual sim "$(_exclui '/logs/' logs/a.txt)" '/logs/ ancorada'
  assert_igual nao "$(_exclui '/logs/' x/logs/a.txt)" '/logs/ so na raiz'
}

teste_flt08_barra_invertida_torna_literal_o_caractere_seguinte() {
  assert_igual sim "$(_exclui '\*.txt' '*.txt')" 'asterisco literal'
  assert_igual nao "$(_exclui '\*.txt' 'a.txt')" 'e nao curinga'
  assert_igual sim "$(_exclui '\[a\]' '[a]')" 'colchetes literais'
  assert_igual nao "$(_exclui '\[a\]' 'a')" 'e nao conjunto'
  assert_igual sim "$(_exclui 'a\\b' 'a\b')" 'barra invertida literal'
  assert_igual sim "$(_exclui '\!x' '!x')" 'exclamacao literal'
  assert_igual sim "$(_exclui 'a\ ' 'a ')" 'espaco escapado'
  assert_igual sim "$(_exclui 'a\?' 'a?')" 'interrogacao literal'
  assert_igual nao "$(_exclui 'a\?' 'ab')" 'e nao curinga'
}

# ---------------------------------------------------------------------------
# TC-FLT-09..12 — caixa e localidade (RF-54)
# ---------------------------------------------------------------------------

teste_flt09_sem_caixa_no_ascii_e_faixa_depois_da_dobra() {
  assert_igual sim "$(_exclui '*.JPG' foto.jpg)" 'padrao em maiuscula'
  assert_igual sim "$(_exclui '*.jpg' FOTO.JPG)" 'caminho em maiuscula'
  assert_igual sim "$(_exclui 'x[A-C]' xb)" 'faixa avaliada depois da dobra'
  assert_igual sim "$(_exclui 'LOGS/' logs/a sim)" 'pasta sem caixa'
}

teste_flt10_sem_caixa_unicode_sob_lc_all_c_sem_vazar_a_localidade() {
  local obtido
  # O processo inteiro sob `LC_ALL=C`: a fixacao e so dentro da comparacao.
  obtido=$(LC_ALL=C bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/filtro.sh"
    dbx_filtro_adicionar excluir --excluir $'"'"'\xc3\x89*'"'"'
    if dbx_filtro_classificar $'"'"'\xc3\xa9a.txt'"'"' nao; then r=dentro; else r=fora; fi
    v=$'"'"'\xc3\xa9'"'"'
    printf "%s|%s|%s" "$r" "$LC_ALL" "${#v}"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual 'fora|C|2' "$obtido" 'E* casa ea.txt; LC_ALL do processo intacto; contagem em bytes intacta'
  # Prova de discriminacao: sem a fixacao (localidade `C` na comparacao), o
  # mesmo par deixa de casar — e a fixacao que faz o caso passar.
  obtido=$(LC_ALL=C DBX_SYNC_LOCALIDADE=C bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/filtro.sh"
    dbx_filtro_adicionar excluir --excluir $'"'"'\xc3\x89*'"'"'
    if dbx_filtro_classificar $'"'"'\xc3\xa9a.txt'"'"' nao; then printf dentro; else printf fora; fi
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual dentro "$obtido" 'sem a fixacao a caixa acentuada nao dobra'
}

teste_flt11_localidade_ausente_vale_so_o_ascii_e_interrogacao_e_um_byte() {
  local obtido
  obtido=$(LC_ALL=C DBX_SYNC_LOCALIDADE=xx_YY.inexistente bash -c '
    . "$1/lib/errors.sh"; . "$1/lib/filtro.sh"
    r=""
    dbx_filtro_adicionar excluir --excluir "*.JPG"
    dbx_filtro_classificar foto.jpg nao || r+="ascii "
    dbx_filtro_limpar; dbx_filtro_adicionar excluir --excluir $'"'"'\xc3\x89*'"'"'
    dbx_filtro_classificar $'"'"'\xc3\xa9a'"'"' nao && r+="acento-distinto "
    dbx_filtro_limpar; dbx_filtro_adicionar excluir --excluir "a?.txt"
    dbx_filtro_classificar $'"'"'a\xc3\xa9.txt'"'"' nao && r+="um-byte "
    dbx_filtro_limpar; dbx_filtro_adicionar excluir --excluir "a??.txt"
    dbx_filtro_classificar $'"'"'a\xc3\xa9.txt'"'"' nao || r+="dois-bytes"
    printf "%s" "$r"
  ' _ "$DBX_HARNESS_RAIZ" 2>&1)
  assert_igual 'ascii acento-distinto um-byte dois-bytes' "$obtido" 'sem a localidade: so ASCII, ? casa um byte'
}

teste_flt12_nfc_e_nfd_sao_distintos() {
  # e composto (U+00E9) e decomposto (e + U+0301): limitacao declarada.
  assert_igual sim "$(_exclui $'\xc3\xa9.txt' $'\xc3\xa9.txt')" 'NFC casa NFC'
  assert_igual nao "$(_exclui $'\xc3\xa9.txt' $'e\xcc\x81.txt')" 'NFC nao casa NFD'
}

teste_flt_nome_que_nao_e_utf8_valido_ainda_casa_por_bytes() {
  # Nome local com byte invalido em UTF-8: a regex sob C.UTF-8 nao casa `.` com
  # ele, e o filtro deixaria de proteger o item. A comparacao recua para bytes.
  assert_igual sim "$(_exclui '*.log' $'a\xffb.log')" 'byte invalido no nome'
  assert_igual sim "$(_exclui 'cache/' $'x\xff/cache/a' )" 'byte invalido no ancestral'
}

teste_qa_b4_01_queda_para_bytes_usa_a_mesma_dobra_do_padrao() {
  # QA-B4-01: na queda para bytes o caminho tem de passar pela MESMA dobra
  # UTF-8 do padrao; com dobra so ASCII, `É` deixava de casar `é`.
  assert_igual sim "$(_exclui $'\xc3\x89foto.jpg' $'x\xff/\xc3\x89foto.jpg')" 'grafia identica nao ASCII'
  assert_igual sim "$(_exclui $'\xc3\xa9foto.jpg' $'x\xff/\xc3\x89foto.jpg')" 'caixa trocada nao ASCII'
  assert_igual sim "$(_exclui $'\xc3\xbc/' $'\xc3\x9c/\xfea')" 'pasta nao ASCII, byte invalido abaixo dela'
  assert_igual nao "$(_exclui $'\xc3\xbc/' $'\xc3\x9c\xfe/a')" 'a pasta e outra: o byte faz parte do nome'
  assert_igual nao "$(_exclui $'\xc3\xa9x' $'x\xff/\xc3\xa9y')" 'e nao casa o que e diferente'
}

teste_div103_incluir_impreciso_em_bytes_nunca_casa_a_mais() {
  # DIV-103 revisada: em bytes, conjunto negado, conjunto com membro fora do
  # ASCII e `?` sao imprecisos. No --incluir, casar a mais poria o item no
  # escopo (e o --espelhar o apagaria): o padrao impreciso NAO casa nesse modo.
  local nome=$'x\xff/\xc3\xa9eu.txt'
  _inclui() {
    dbx_filtro_limpar
    dbx_filtro_adicionar incluir --incluir "$1" || _harness_falhar "recusado: $1"
    if dbx_filtro_classificar "$2" nao; then printf 'dentro'; else printf 'fora'; fi
  }
  assert_igual fora "$(_inclui '[!a]*' "$nome")" 'conjunto negado nao inclui em bytes'
  assert_igual fora "$(_inclui $'[\xc3\xa9]*' "$nome")" 'membro nao ASCII nao inclui em bytes'
  assert_igual fora "$(_inclui '?eu.txt' "$nome")" '? nao inclui em bytes'
  assert_igual dentro "$(_inclui '*.txt' "$nome")" 'padrao preciso continua incluindo'
  assert_igual dentro "$(_inclui $'\xc3\x89eu.txt' "$nome")" 'literal nao ASCII continua incluindo'
  assert_igual dentro "$(_inclui '[!a]*' 'x/beu.txt')" 'fora do modo de bytes, nada muda'
  # No --excluir o mesmo padrao continua casando (protege a mais).
  assert_igual sim "$(_exclui '[!a]*' "$nome")" 'excluir impreciso segue casando'
}

teste_qa_b4_01_interrogacao_e_conjunto_negado_casam_um_caractere_inteiro_em_bytes() {
  assert_igual sim "$(_exclui '?eu.txt' $'x\xff/\xc3\xa9eu.txt')" '? casa e acentuado inteiro'
  assert_igual sim "$(_exclui '?eu.txt' $'x\xff/\xffeu.txt')" '? casa um byte invalido'
  assert_igual sim "$(_exclui 'a[!0-9]b' $'x\xff/a\xc3\xa9b')" 'conjunto negado casa o caractere inteiro'
  assert_igual nao "$(_exclui 'a[!0-9]b' $'x\xff/a5b')" 'e continua negando'
  assert_igual sim "$(_exclui $'[\xc3\xa9x]z' $'x\xff/\xc3\x89z')" 'conjunto com membro nao ASCII'
  assert_igual nao "$(_exclui 'a?b' $'x\xff/a/b')" '? nunca casa /'
}

# ---------------------------------------------------------------------------
# TC-FLT-13..17 — validacao
# ---------------------------------------------------------------------------

teste_flt13_malformados_sao_uso_invalido() {
  local padrao
  for padrao in '' '/' '//' 'a//b' './a' 'a/./b' 'a/../b' '..' 'x\' '[abc' '[]' '[!]' '[z-a]' \
    '[[:alpha:]]' '!x' $'a\tb' $'a\nb' $'a\x7fb' $'a\x01b' 'a[/]b'; do
    _recusa "$padrao"
    assert_igual "$USO" $? "malformado: [$padrao]"
  done
}

teste_flt14_mensagem_nomeia_a_opcao_e_cita_o_padrao_sem_byte_cru() {
  dbx_filtro_limpar
  dbx_filtro_adicionar incluir --include $'[z-a]'
  assert_contem '--include' "$DBX_FILTRO_MOTIVO" 'nomeia a opcao como digitada'
  assert_contem "'[z-a]'" "$DBX_FILTRO_MOTIVO" 'cita o padrao'
  dbx_filtro_adicionar excluir --excluir $'a\nb'
  assert_nao_contem $'\n' "$DBX_FILTRO_MOTIVO" 'sem quebra de linha crua'
  assert_contem "a\\nb" "$DBX_FILTRO_MOTIVO" 'o byte de controle sai escapado'
  dbx_filtro_adicionar excluir --excluir '!x'
  assert_contem 'use --incluir' "$DBX_FILTRO_MOTIVO" 'remedio da negacao (DIV-79)'
}

teste_flt15_limites_de_quantidade_e_de_tamanho() {
  local i longo
  dbx_filtro_limpar
  for ((i = 1; i <= 64; i++)); do
    dbx_filtro_adicionar excluir --excluir "p$i" || _harness_falhar "o padrao $i deveria caber"
  done
  dbx_filtro_adicionar incluir --incluir 'p65'
  assert_igual "$USO" $? 'o 65o padrao, somando as duas opcoes, e recusado'
  assert_contem '64' "$DBX_FILTRO_MOTIVO" 'o limite e citado'
  printf -v longo '%*s' 1024 ''
  longo=${longo// /a}
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir "$longo"
  assert_igual 0 $? '1024 bytes cabem'
  dbx_filtro_adicionar excluir --excluir "${longo}b"
  assert_igual "$USO" $? '1025 bytes nao cabem'
  # A medida e em bytes, mesmo com caractere multibyte e LC_ALL de UTF-8.
  printf -v longo '%*s' 512 ''
  longo=${longo// /$'\xc3\xa9'}
  dbx_filtro_limpar
  LC_ALL=C.UTF-8 dbx_filtro_adicionar excluir --excluir "${longo}x"
  assert_igual "$USO" $? '513 caracteres de 2 bytes = 1025 bytes'
}

teste_flt16_padrao_e_dado_nunca_codigo() {
  local sentinela="$DBX_TESTES_TMP/flt16.$$" padrao
  for padrao in "\$(touch $sentinela)" "\`touch $sentinela\`" "a;touch $sentinela" '$HOME' '~' '*'; do
    _exclui "$padrao" 'qualquer' >/dev/null
  done
  assert_arquivo_ausente "$sentinela" 'nada executado'
  assert_igual sim "$(_exclui '$HOME' '$HOME')" '$HOME e literal'
  assert_igual nao "$(_exclui '$HOME' "${HOME#/}")" 'e nao expandido'
  assert_igual sim "$(_exclui '~' '~')" '~ e literal'
  assert_igual sim "$(_exclui 'a;b' 'a;b')" '; e literal'
}

teste_flt17_cerquilha_literal_e_espaco_final_preservado() {
  assert_igual sim "$(_exclui '#x' '#x')" '# inicial e literal'
  assert_igual sim "$(_exclui 'a ' 'a ')" 'espaco final preservado'
  assert_igual nao "$(_exclui 'a ' 'a')" 'e significativo'
}

# ---------------------------------------------------------------------------
# TC-FES-01, 02, 03 — regra de escopo (RF-80(a)(c))
# ---------------------------------------------------------------------------

_no_escopo() { # <caminho> [sim|nao] — `sim`/`nao` com os filtros correntes
  if dbx_filtro_classificar "$1" "${2:-nao}"; then printf 'sim'; else printf 'nao'; fi
}

teste_fes01_exclusao_vence_inclusao_nas_duas_ordens() {
  dbx_filtro_limpar
  dbx_filtro_adicionar incluir --incluir '*.pdf'
  dbx_filtro_adicionar excluir --excluir 'velho/'
  assert_igual nao "$(_no_escopo velho/a.pdf)" 'incluir antes'
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir 'velho/'
  dbx_filtro_adicionar incluir --incluir '*.pdf'
  assert_igual nao "$(_no_escopo velho/a.pdf)" 'excluir antes'
  assert_igual sim "$(_no_escopo novo/a.pdf)" 'o resto do incluir vale'
}

teste_fes02_com_incluir_so_o_que_casa_entra_em_qualquer_profundidade() {
  dbx_filtro_limpar
  dbx_filtro_adicionar incluir --incluir '*.pdf'
  assert_igual sim "$(_no_escopo a/b/c.pdf)" 'pasta implicita'
  assert_igual nao "$(_no_escopo a/b/c.txt)" 'o resto fica fora'
  assert_igual 1 "$(dbx_filtro_classificar a/b/c.txt nao; printf '%s' $?)" 'status 1 = filtrado'
  assert_igual a/b/c.txt "$(dbx_filtro_classificar a/b/c.txt nao; printf '%s' "$DBX_FILTRO_FILTRADO")" \
    'o proprio arquivo e o item contado'
}

teste_fes03_pasta_casada_por_incluir_inclui_o_conteudo() {
  dbx_filtro_limpar
  dbx_filtro_adicionar incluir --incluir 'docs/'
  assert_igual sim "$(_no_escopo docs/a.txt)" 'conteudo da pasta'
  assert_igual sim "$(_no_escopo x/docs/y/b.bin)" 'em qualquer nivel'
  assert_igual nao "$(_no_escopo outros/a.txt)" 'fora dela, nao'
}

teste_fes_pasta_excluida_e_o_item_contado_pelo_conteudo() {
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir 'Cache/'
  dbx_filtro_classificar a/cache/x/y.bin nao
  assert_igual a/cache "$DBX_FILTRO_FILTRADO" 'a pasta excluida mais alta, na grafia do caminho'
  dbx_filtro_pasta_excluida a/cache
  assert_igual 0 $? 'a pasta e podada na descida'
  dbx_filtro_pasta_excluida a
  assert_igual 1 $? 'o ancestral nao'
}

teste_fes18_padrao_sem_casamento_e_listado_para_o_aviso() {
  dbx_filtro_limpar
  dbx_filtro_adicionar excluir --excluir '*.log'
  dbx_filtro_adicionar excluir --excluir '*.lgo'
  dbx_filtro_classificar a.log nao
  dbx_filtro_avisos
  assert_igual '*.lgo' "${DBX_FILTRO_SEM_CASAMENTO[*]}" 'so o que nunca casou'
}

teste_flt_sem_filtro_tudo_esta_no_escopo() {
  dbx_filtro_limpar
  dbx_filtro_ativo
  assert_igual 1 $? 'sem padrao, filtro inativo'
  assert_igual sim "$(_no_escopo qualquer/coisa.txt)" 'tudo no escopo'
}

# ---------------------------------------------------------------------------
# TC-FDT-01..07 — data e tamanho
# ---------------------------------------------------------------------------

teste_fdt01_datas_validas_e_invalidas() {
  dbx_filtro_validar_data --modificado-desde 2026-10-01 desde
  assert_igual '2026-10-01T00:00:00Z' "$DBX_FILTRO_DATA" 'dia no desde vale o inicio'
  dbx_filtro_validar_data --modificado-ate 2026-10-01 ate
  assert_igual '2026-10-01T23:59:59Z' "$DBX_FILTRO_DATA" 'dia no ate vale o fim'
  dbx_filtro_validar_data --modified-since 2026-10-01T12:00:00Z desde
  assert_igual '2026-10-01T12:00:00Z' "$DBX_FILTRO_DATA" 'carimbo completo'
  dbx_filtro_validar_data --modificado-desde 2024-02-29 desde
  assert_igual 0 $? 'bissexto'
  local valor
  for valor in 2026-1-5 2026-02-30 2025-02-29 2026-13-01 2026-10-01T12:00:00+03:00 \
    2026-10-01T12:00:00.5Z 2026-10-01T24:00:00Z 2026-10-01T12:60:00Z '' ' 2026-10-01' 2026-10-01T12:00:00; do
    dbx_filtro_validar_data --modificado-desde "$valor" desde
    assert_igual "$USO" $? "data invalida: [$valor]"
  done
  assert_contem '--modificado-desde' "$DBX_FILTRO_MOTIVO" 'nomeia a opcao'
}

teste_fdt02_fdt07_limites_inclusivos() {
  dbx_filtro_meta_definir 2026-10-01T00:00:00Z 2026-10-01T23:59:59Z '' ''
  dbx_filtro_meta_passa 2026-10-01T00:00:00Z 1
  assert_igual 0 $? 'desde inclusivo'
  dbx_filtro_meta_passa 2026-10-01T23:59:59Z 1
  assert_igual 0 $? 'ate inclusivo'
  dbx_filtro_meta_passa 2026-10-02T00:00:00Z 1
  assert_igual 1 $? 'depois do ate'
  dbx_filtro_meta_passa 2026-09-30T23:59:59Z 1
  assert_igual 1 $? 'antes do desde'
  dbx_filtro_meta_definir '' '' 1024 ''
  dbx_filtro_meta_passa '' 1024
  assert_igual 0 $? 'min 1K inclui 1024'
  dbx_filtro_meta_passa '' 1023
  assert_igual 1 $? 'min 1K exclui 1023'
  dbx_filtro_meta_definir '' '' '' 1024
  dbx_filtro_meta_passa '' 1024
  assert_igual 0 $? 'max 1K inclui 1024'
  dbx_filtro_meta_passa '' 1025
  assert_igual 1 $? 'max 1K exclui 1025'
}

teste_fdt03_fdt07_faixa_invertida_e_uso_invalido() {
  dbx_filtro_meta_definir 2026-10-02T00:00:00Z 2026-10-01T23:59:59Z '' ''
  assert_igual "$USO" $? 'desde > ate'
  dbx_filtro_meta_definir '' '' 2048 1024
  assert_igual "$USO" $? 'min > max'
  dbx_filtro_meta_definir '' '' '' ''
  dbx_filtro_meta_ativo
  assert_igual 1 $? 'sem data nem tamanho, inativo'
}

teste_fdt04_epoca_vira_utc_sem_utilitario_e_sem_depender_do_fuso() {
  local obtido
  dbx_filtro_carimbo_de_epoca 0
  assert_igual '1970-01-01T00:00:00Z' "$DBX_FILTRO_CARIMBO" 'epoca zero'
  dbx_filtro_carimbo_de_epoca 951782400
  assert_igual '2000-02-29T00:00:00Z' "$DBX_FILTRO_CARIMBO" 'bissexto secular'
  dbx_filtro_carimbo_de_epoca 1790899199
  assert_igual '2026-10-01T23:59:59Z' "$DBX_FILTRO_CARIMBO" 'fim do dia'
  obtido=$(TZ=America/Sao_Paulo bash -c '. "$1/lib/errors.sh"; . "$1/lib/filtro.sh"
    dbx_filtro_carimbo_de_epoca 1790899199; printf "%s" "$DBX_FILTRO_CARIMBO"' _ "$DBX_HARNESS_RAIZ")
  assert_igual '2026-10-01T23:59:59Z' "$obtido" 'mesmo resultado sob outro fuso'
  assert_nao_contem 'date ' "$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/filtro.sh")" \
    'nenhum utilitario date'
}

teste_fdt06_tamanhos_validos_e_invalidos() {
  local par valor
  for par in 0=0 1=1 10K=10240 1m=1048576 2G=2147483648 999999999=999999999; do
    dbx_filtro_validar_tamanho --tamanho-min "${par%%=*}"
    assert_igual "${par#*=}" "$DBX_FILTRO_BYTES" "tamanho ${par%%=*}"
  done
  for valor in 1.5M -1 +1 01 10KB 1KiB 1T ' 1' '' 1234567890 1B; do
    dbx_filtro_validar_tamanho --min-size "$valor"
    assert_igual "$USO" $? "tamanho invalido: [$valor]"
  done
  assert_contem '--min-size' "$DBX_FILTRO_MOTIVO" 'nomeia a opcao'
}

teste_fdt_sem_carimbo_conhecido_o_arquivo_fica_fora_da_faixa_de_data() {
  # Carimbo ausente ou malformado nao pode passar num filtro de data: seria
  # transferir o que o operador pediu para deixar de fora.
  dbx_filtro_meta_definir 2026-10-01T00:00:00Z '' '' ''
  dbx_filtro_meta_passa '' 1
  assert_igual 1 $? 'sem carimbo'
  dbx_filtro_meta_passa 'lixo' 1
  assert_igual 1 $? 'carimbo malformado'
}

# ---------------------------------------------------------------------------
# Pureza (DIV-94)
# ---------------------------------------------------------------------------

teste_lib_filtro_e_pura_sem_rede_disco_estado_nem_eval() {
  local codigo
  assert_arquivo_existe "$DBX_HARNESS_RAIZ/lib/filtro.sh" 'componente proprio (DIV-94)'
  codigo=$(grep -vE '^[[:space:]]*#' "$DBX_HARNESS_RAIZ/lib/filtro.sh")
  assert_nao_contem 'eval' "$codigo" 'sem eval'
  assert_nao_contem 'dbx_http' "$codigo" 'sem rede'
  assert_nao_contem 'dbx_state' "$codigo" 'sem estado'
  assert_nao_contem 'dbx_tmp' "$codigo" 'sem area'
  assert_nao_contem '>"' "$codigo" 'sem escrita'
  assert_nao_contem 'shopt' "$codigo" 'sem expansao de nome de arquivo'
}

harness_executar "$@"
