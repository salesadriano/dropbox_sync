#!/usr/bin/env bats
# O scripts/suite-completa.sh e a implementacao do projeto (copia da skill ai-team:governanca-por-hooks, que o despachante do plugin prefere); estes casos prendem a interface.

setup() { RAIZ="$BATS_TEST_DIRNAME/../.."; }

@test "--conferir sem registro chega ao script da skill e o wrapper sai com 3 e explica a ausencia" {
  git init -q -b main "$BATS_TEST_TMPDIR/repo"
  git -C "$BATS_TEST_TMPDIR/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
  run sh -c "cd '$BATS_TEST_TMPDIR/repo' && sh '$RAIZ/scripts/suite-completa.sh' --conferir"
  [ "$status" -eq 3 ]
  [[ "$output" == *"sem registro da suite completa para o commit atual"* ]]
}
