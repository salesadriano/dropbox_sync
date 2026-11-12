# Teste da trava: pid de outro usuario tomado como morto

**Branch:** `chore/teste-trava-pid-alheio` (de `origin/develop` @ `8988ddc`), worktree `../dropbox_api.worktrees/chore-teste-trava-pid-alheio`
**Porte:** P. `sh scripts/porte.sh`: `arquivos: 1 | linhas de codigo: 4 (limite 50)`, `porte: P`.
**Instancia:** myPCWin/Adriano Sales Santos
**issues:** nenhuma
**PRs abertas na entrada:** nenhuma. `alteracoes-externas.sh --detectar` (checkout principal): sem divergencia; `--inicial` no worktree.

## Prompt 1 — 2026-11-12 (da demanda da release v2.4.1)

> merge as PRs

**Intencao:** mesclar as PRs #112 e #113 e seguir a release v2.4.1. A suite completa de `develop` @ `8988ddc`, exigida para a PR `develop` -> `master`, reprovou duas vezes em `state_trava_test.sh::matriz_hostil_e_ilegivel_nunca_apagada_nem_retomada_nem_ecoada`, e esta demanda corrige o teste para destravar a release.

**Inferencias do Tech Lead:**
- A falha e do teste, nao do produto: o pid 12 e uma thread do `Interop` do WSL (root); `kill -0` da EPERM e o teste o tomava por morto, enquanto `lib/state.sh:774` (vivo por `kill -0` ou `/proc/<pid>`) o ve vivo e recusa, como deve.
- Correcao: o teste pula o pid com a mesma regra de vivo do produto. O pid 9999999 continua exercitando a retomada.
