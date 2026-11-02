#!/usr/bin/env sh
# Roda a suite do projeto (ou um filtro) no bash 4.2.46 real de uma imagem
# CentOS 7 fixada por digest (RF-206). E o comando da suite completa oficial da
# linha legada; na principal serve para conferir o comportamento em bash 4.2.
#
# Uso: sh scripts/suite-bash42.sh [filtro]
# A suite completa leva cerca de 50 minutos: prefira um filtro.
#
# Requisitos: docker e a imagem abaixo (`docker pull <imagem>`).
set -eu

IMAGEM='centos:7@sha256:be65f488b7764ad3638f236b7b515b3678369a5124c47b8d32916d6487418ea4'
RAIZ=$(cd -P -- "$(dirname -- "$0")/.." && pwd -P)

if ! command -v docker >/dev/null 2>&1; then
  printf 'Erro: docker nao encontrado. Instale o docker e rode: docker pull %s\n' "$IMAGEM" >&2
  exit 1
fi
if ! docker image inspect "$IMAGEM" >/dev/null 2>&1; then
  printf 'Erro: imagem ausente. Obtenha com: docker pull %s\n' "$IMAGEM" >&2
  exit 1
fi

# Usuario do host (nao root): os testes de permissao (0600, leitura negada)
# so valem sem privilegio; HOME gravavel dentro do conteiner.
exec docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$RAIZ:/src" -w /src "$IMAGEM" bash tests/run.sh "$@"
