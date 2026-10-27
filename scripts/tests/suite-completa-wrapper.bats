#!/usr/bin/env bats
# O scripts/suite-completa.sh e a implementacao do projeto (copia da skill ai-team:governanca-por-hooks, que o despachante do plugin prefere); estes casos prendem a interface.

setup() { RAIZ="$BATS_TEST_DIRNAME/../.."; }

@test "o wrapper delega ao script da skill e repassa os argumentos (--mostrar responde com o registro real ou com a ausencia dele)" {
  run sh "$RAIZ/scripts/suite-completa.sh" --mostrar
  [ "$status" -eq 0 ]
  [[ "$output" == "sem registro de suite completa neste worktree" || "${lines[0]}" =~ ^[0-9a-f]{40}\ (limpo|sujo)\ [0-9]+\ [0-9T:Z-]+\ [0-9]+$ ]]
}

@test "argumento invalido chega ao script da skill e sai com 2" {
  run sh "$RAIZ/scripts/suite-completa.sh" --xpto
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconhecido: --xpto"* ]]
}

@test "scripts/suite-completa.cmd traz o mesmo comando do passo 5 do main.yml" {
  cmd=$(cat "$RAIZ/scripts/suite-completa.cmd")
  grep -qF -- "$cmd" "$RAIZ/.github/workflows/main.yml"
}
