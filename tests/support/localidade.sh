#!/usr/bin/env bash
# Sonda compartilhada da localidade dos testes (QA-B42-03): uma copia so, para que
# as suites que pulam sem a dobra Unicode nunca divirjam entre si (QA-B42-01).
#
# _localidade_disponivel — 0 quando a localidade C.UTF-8 existe e o bash dobra a
# caixa fora do ASCII. No CentOS 7 nao ha C.UTF-8 e o bash 4.2 nao dobra `${x,,}`
# fora do ASCII nem em en_US.utf8; o produto degrada com aviso (RF-54(f)) e o caso
# que exige a dobra e pulado.
# shellcheck disable=SC2016  # o script do bash filho e literal: a expansao acontece nele, nao aqui
_localidade_disponivel() {
  LC_ALL=C.UTF-8 "${BASH:-bash}" -c 'x=$'"'"'\xc3\x89'"'"'; [[ ${x,,} == $'"'"'\xc3\xa9'"'"' ]]' 2>/dev/null
}
