# Checkpoint: v17 Order Mechanics + Tooling

**Date:** 2026-04-19
**Branch:** `feature/order-mechanics` (merged via PR #32 → main at `f5fa929`)
**Issue:** #31 (Done, closed)

## What shipped

End-to-end implementation of the Turnip 28 v17 order sequence, replacing the free-form move/shoot/charge model that landed with the initial Phase 4 engine.

**State machine:** `snob_select` → `order_declare` → `order_execute` → advance (with `follower_self_order` as a parallel track after all Snobs have ordered).

**Four order types:** Volley Fire (−1 Inaccuracy), Move & Shoot, March (M + 2D6, 1D6 blundered), Charge (M + 2D6 to adjacent, resolve melee).

**Coverage:**
- `game_engine.gd` — `select_snob`, `declare_order`, `declare_self_order`, `execute_order`, `_advance_after_order`, `_end_round`. Blunder check embedded in declare; server-authoritative dice throughout.
- `network_server.gd` — routes the four new action types, sizes combat dice pool by order type.
- `battle.gd` — four phase-aware sidebar sub-panels, Move & Shoot two-click flow, `_reconcile_selection_state()` clears stale UI on state shifts.
- `grid_draw.gd` — Manhattan diamond overlay around Made-Ready Snob matching engine's command-range check exactly.
- `test_game_engine.gd` — rewrote top to bottom: 48 tests covering snob select / declare / execute (all four types) / follower self-order / advance flow / victory.

**Validated** end-to-end in local multiplayer (two clients + server) through deployment and combat. No crashes, state machine held up.

## Latent bugs surfaced

Four things that had been broken since PR #30 merged, all fixed on this branch:

1. **`NetworkClient` autoload was never registered** in `project.godot` despite being referenced with autoload syntax throughout. Full-stack runs failed with parse errors. Nobody had actually run client+server since the v17 data model merge.
2. **`--server` detection** only checked `OS.get_cmdline_args()`, so flags passed after `--` (as `scripts/test-stack.sh` does) were invisible. Server booted in client mode. Now checks both.
3. **`cached_game_state`** was assigned by lobby.gd but never declared on NetworkManager. Battle scene load crashed.
4. **Blundered `move_and_shoot`** had `max_move=0` because `declare_order` only set `move_bonus` for march/charge. Plan spec was "1D6 if blundered" — now implemented with regression tests. Surfaced during user testing when a Bastards unit got stuck.

## Non-obvious decisions (for future me)

- **Flipped plan order** — did Step 5 (tests) before Step 4 (UI) to lock the engine contract before UI churn could hide engine bugs. Plan had 3→4→5; I went 3→5→4. Paid off when blunder bug surfaced mid-user-testing and tests caught the regression the fix.
- **Kept `-- --server` separator** and fixed the code to read both arg arrays, rather than dropping the separator. Keeps user-args semantics clean if we ever add more runtime flags.
- **`wait` not `wait -n`** in `scripts/test-stack.sh` — closing one client window no longer cascades into full stack shutdown. Iterating on one client during a session was painful with `wait -n`.
- **Snob self-order bypasses blunder check** in `declare_order` — plan spec. Command-range check is also skipped when ordering self.
- **`_advance_after_order` marks both the ordering Snob and the ordered unit** — so a Snob orders itself via a single cycle.

## New tooling

- `scripts/test-stack.sh` — cross-platform (Windows Git Bash + macOS) local launcher. Headless server + 2 clients (or `--solo`). Per-process logs to `test-logs/` (gitignored).
- `.github/workflows/sync-wiki.yml` — on push to main, mirrors `docs/wiki/*.md` into `<repo>.wiki.git`. Default `GITHUB_TOKEN` works. First run after merge succeeded ✓.
- Auto-memory: saved Godot binary paths for both Windows (`C:\tools\Godot\`) and macOS (`/Applications/Godot.app/...`).

## Docs consolidation

Deleted `PHASE{2,3,4}_TESTING.md` at repo root. The wiki now owns manual-testing procedure. `docs/wiki/Manual-Testing-Guide.md` rewritten against the v17 state machine + launcher. All wiki docs use `$GODOT` placeholder convention (set per-platform per `Project-Setup.md`).

## Board state after

- **#31** (v17 Order Sequence Implementation) — Done, issue closed
- **#27** (v17 Data Model Rework) — Done (was stuck In Progress; issue was already closed)
- **#22** (Phase 5 victory conditions) — In Progress, partial. Remaining: objectives, victory/defeat screen, end-of-game summary, "New Game" button
- **#21** (Phase 5 visual polish) — Todo
- **#23–25** (Phase 6 deployment) — Todo

## Known deferred items

- Benign `entry.gd:6/8` warning ("parent node busy adding/removing children") on every startup — `change_scene_to_file()` in `_ready()` should be `call_deferred`'d. Not blocking.
- First-run cold cache: `$GODOT --editor --quit` needs to run once on a fresh clone before headless tests work, otherwise `class_name` globals don't resolve. Could be scripted.
- `docs/wiki/Phase-4-UI-Programmatic.md` and `Phase-4-UI-Tasks.md` are historical checkpoint-style docs; left untouched but could be archived or removed later.

## Next session

Natural pickup points:

1. **#22 victory conditions** — finish the partial implementation (victory/defeat UI, end-of-game summary, objectives, new-game button)
2. **Phase 5 polish** (#21) — unit sprites instead of ColorRects, terrain, etc.
3. **Phase 6 deployment** (#23–25) — export presets, VPS server deploy

Ask before picking; these are independent.
