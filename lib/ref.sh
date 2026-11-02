#!/usr/bin/env bash
# lib/ref.sh — acesso a vetor pelo NOME, sem nameref (linha legada, bash 4.2).
#
# Camada: utilitario puro. Nao imprime, nao acessa rede, nao depende de outra
# biblioteca. Requisitos: RF-199 (codigo da linha legada roda no bash 4.2) e
# o System Design de suporte-bash-42, eixo 5.
#
# Por que existe: `local -n` so chegou no bash 4.3. As funcoes que recebem o
# nome de um vetor do chamador passam a acessa-lo por estas funcoes.
#
# Abordagens avaliadas:
#   (a) copiar o vetor para dentro e de volta. Rejeitada: os mapas do sync
#       chegam a dezenas de milhares de entradas por bloco; copia por chamada
#       torna o laco quadratico.
#   (b) `printf -v "vetor[$chave]"` e `${!ref}` com a chave interpolada.
#       Rejeitada: o bash EXPANDE o subscrito, e uma chave vinda do remoto como
#       `$(comando)` seria executada. Nome de arquivo e dado adversarial.
#   (c) ESCOLHIDA — `eval` apenas com o NOME validado (`^[A-Za-z_][A-Za-z0-9_]*$`)
#       interpolado; chave e valor entram SEMPRE como `$2`/`$3` dentro do texto
#       avaliado, expandidos uma unica vez e usados literalmente (vetor
#       associativo). Em vetor indexado o subscrito e aritmetico: so passe
#       indice numerico gerado pelo proprio codigo.
#
# Contrato comum: nome invalido devolve 2 sem tocar em nada. Chave VAZIA em
# vetor associativo e erro do proprio bash (`bad array subscript`, no 4.2 e no
# 5): o chamador nunca passa chave vazia (caminho, chave de caixa ou indice). As funcoes nao
# declaram `local` (usam so os parametros posicionais), para nao sombrear o
# vetor do chamador. Vetor vazio sob `set -u` e protegido com `${v[@]+...}`.
#
# Regra para o chamador: as variaveis locais da funcao que recebe o nome levam
# prefixo proprio (`_fc_`, `_rp_` ...), como ja faziam com o nameref, para nao
# sombrear o vetor do chamador por escopo dinamico.

[[ -n ${DBX_REF_CARREGADO:-} ]] && return 0
DBX_REF_CARREGADO=1

# dbx_ref_valido <nome> -> 0 se e nome de variavel do shell.
dbx_ref_valido() {
  [[ ${1-} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# dbx_ref_obter <destino> <vetor> <chave> — destino recebe vetor[chave] (vazio
# se ausente).
dbx_ref_obter() {
  dbx_ref_valido "${1-}" && dbx_ref_valido "${2-}" || return 2
  eval "$1=\${$2[\$3]-}"
}

# dbx_ref_definir <vetor> <chave> <valor>
dbx_ref_definir() {
  dbx_ref_valido "${1-}" || return 2
  eval "$1[\$2]=\$3"
}

# dbx_ref_remover <vetor> <chave>
dbx_ref_remover() {
  dbx_ref_valido "${1-}" || return 2
  eval "unset '$1[\$2]'"
}

# dbx_ref_existe <vetor> <chave> -> 0 se a chave esta definida.
dbx_ref_existe() {
  dbx_ref_valido "${1-}" || return 2
  eval "[[ -n \${$1[\$2]+x} ]]"
}

# dbx_ref_anexar <vetor_indexado> <valor...>
dbx_ref_anexar() {
  dbx_ref_valido "${1-}" || return 2
  eval "$1+=(\"\${@:2}\")"
}

# dbx_ref_tamanho <destino> <vetor>
dbx_ref_tamanho() {
  dbx_ref_valido "${1-}" && dbx_ref_valido "${2-}" || return 2
  eval "$1=\${#$2[@]}"
}

# dbx_ref_chaves <destino_indexado> <vetor> — destino recebe as chaves.
dbx_ref_chaves() {
  dbx_ref_valido "${1-}" && dbx_ref_valido "${2-}" || return 2
  eval "$1=(\${$2[@]+\"\${!$2[@]}\"})"
}

# dbx_ref_copiar <destino_indexado> <vetor_indexado> — copia os valores, em
# ordem de indice (reindexa a partir de 0).
dbx_ref_copiar() {
  dbx_ref_valido "${1-}" && dbx_ref_valido "${2-}" || return 2
  eval "$1=(\${$2[@]+\"\${$2[@]}\"})"
}

# dbx_ref_limpar <vetor> — esvazia mantendo o tipo declarado pelo chamador.
dbx_ref_limpar() {
  dbx_ref_valido "${1-}" || return 2
  eval "$1=()"
}
