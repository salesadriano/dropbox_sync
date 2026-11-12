# Teste da trava na linha legada: pid de outro usuario tomado como morto

**Branch:** `chore/teste-trava-pid-alheio-bash42` (de `origin/support/bash-4.2` @ `66d7c6d`), worktree `../dropbox_api.worktrees/chore-teste-trava-pid-alheio-bash42`
**Porte:** P. Mesmas 4 linhas de teste da PR #114 da principal, portadas por cherry-pick de `11b27f3` (so o teste).
**Instancia:** myPCWin/Adriano Sales Santos
**issues:** nenhuma
**PRs abertas na entrada:** nenhuma. `alteracoes-externas.sh --detectar` (checkout principal): sem divergencia; `--inicial` no worktree.

## Prompt 1 — 2026-11-12

> corrija o teste na linha legada agora

**Intencao:** levar para `support/bash-4.2` a correcao de `state_trava_test.sh` da PR #114 (registro `docs/reviews/2026-11-12-1046-registro-teste-trava-pid-alheio.md` na principal).

**Inferencias do Tech Lead:**
- A causa e a mesma: no host WSL o pid 12 e uma thread `Interop` do root; `kill -0` da EPERM e o teste o planta como morto. No conteiner da suite oficial (`suite-bash42.sh`) o namespace de pids e outro e o caso passava; no host falhava.
- Sem release nova: so teste.
