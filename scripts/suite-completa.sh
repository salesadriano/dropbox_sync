#!/usr/bin/env sh
# Ponto de entrada do modelo para a suite completa (Regra 8 de protocolo-tdd; regra 3 do guarda de comandos).
# Delega ao script da skill governanca-por-hooks, que e a unica implementacao; o comando oficial esta em
# scripts/suite-completa.cmd. Uso: sh scripts/suite-completa.sh [-- <comando> | --conferir | --mostrar]
exec sh "$(dirname -- "$0")/../.github/skills/governanca-por-hooks/scripts/suite-completa.sh" "$@"
