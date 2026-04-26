# Checkpoint — Engine Module Split

**Date:** 2026-04-25
**PR:** #78
**Branch:** refactor/65-engine-modules (merged + deleted)

Backfilled checkpoint — pre-merge-housekeeping was skipped, so this is
written retroactively from PR #78 + commit `f8bcdc5`. Pre-scoping for
this work lives in the #65 issue body and in
`memory/project_audit_sequencing.md`; the implementation followed that
plan without deviation.

## What shipped

Five new pure-RefCounted modules in `godot/game/`, each owning one slice
of v17 rule logic:

- **`game/board.gd`** (47 lines) — `BOARD_WIDTH`/`BOARD_HEIGHT`,
  `DEPLOYMENT_ZONE_*` constants, `Board.grid_distance(x1,y1,x2,y2)`,
  `Board.is_in_bounds(x,y)`, `Board.validate_move(state, unit, x, y)`.
  The validator inlines the objective-cell lookup so board.gd doesn't
  depend on objectives.gd.
- **`game/targeting.gd`** (181 lines) —
  `Targeting.has_line_of_sight(state, fx, fy, tx, ty)` (supercover
  Bresenham), `Targeting.find_shooting_targets[_from](...)`,
  `Targeting.is_valid_shooting_target[_from](...)` (range + LoS +
  closest-target with Sharpshooter bypass), `Targeting.find_adjacent_cell`
  (charger contact-cell search; still 4-cardinal only — see #77).
- **`game/combat.gd`** (319 lines) —
  `Combat.resolve_shooting_engagement` (attacker + return-fire,
  pre-engagement model counts, simultaneous wound application),
  `Combat.resolve_shooting_side`, `Combat.can_return_fire`,
  `Combat.resolve_melee` (bouts to MELEE_MAX_BOUTS=3),
  `Combat.resolve_bout_side`, `Combat.melee_dice_budget`,
  `Combat.apply_wounds`. Constant `Combat.MELEE_MAX_BOUTS = 3` is the
  authoritative declaration.
- **`game/panic.gd`** (229 lines) —
  `Panic.is_fearless(unit)` (Brutes + Safety in Numbers ≥8),
  `Panic.panic_test(unit, panic_die, fearless_die)`,
  `Panic.execute_retreat(state, unit_id, retreat_die)` (D6 + 2"/token,
  away from nearest enemy, board-edge destruction, Stubborn Fanatics
  opt-out), `Panic.find_nearest_enemy`, plus internal
  `_find_retreat_cell` spiral search and `_is_valid_retreat_dest`.
- **`game/objectives.gd`** (133 lines) —
  `Objectives.is_objective_at(state, x, y)`,
  `Objectives.resolve_objective_captures(state)` (Follower-only,
  Euclidean ≤1.0, contested-on-both-adjacent, retain-on-empty),
  `Objectives.check_victory(state)` (elimination → Headless Chicken →
  round-limit objective scoring → no winner).

`godot/server/game_engine.gd` shrunk from **1932 → 1061 lines** (-871).
What remains is order-flow orchestration: `place_unit`,
`confirm_placement`, `select_snob`, `declare_order`,
`declare_self_order`, `execute_order`, the four `_execute_*` order
handlers (volley_fire, move_and_shoot, march, charge), and a few
state-query helpers (`_clone_state`, `_find_unit`, `_has_unordered_*`,
`_has_valid_*_target`, `get_followers_in_command_range`).

Three dormant contract bugs fixed as warm-up commits:

- `_find_unit_in` was byte-identical to `_find_unit` with contradictory
  docstrings (read-only vs. mutable). Collapsed to one function with a
  docstring that admits the caller decides the read/write mode.
- `Types.GameState.from_dict` used `Array.assign` on `action_log`, which
  is shallow on inner Dicts. Replaced with per-entry `.duplicate(true)`.
- `Types.UnitDef._init` and `Types.UnitState._init` assigned
  `p_special_rules` by reference. Two instances built from one source
  array shared the array. Switched both to `.duplicate()`.

`Types.EngineResult.success` field removed; replaced with
`is_success() -> bool` derived from `error.is_empty()`. Twelve
`result.success = true` lines deleted from `game_engine.gd`, 65 test
assertions migrated, one network_server check_victory call updated.

Client-side validation drift eliminated for shooting:
`client/scenes/battle.gd::_has_valid_shooting_target` and
`client/scenes/grid_draw.gd::_shooting_target_cells` now consume
`Targeting.find_shooting_targets[_from]`. Green target rings during
volley_fire and move_and_shoot only appear around enemies the shooter
actually has LoS to. Charge fizzle/ring still uses pure Euclidean
(`Board.grid_distance`) since charge ignores LoS in v17.

Tests: **114 engine + 29 type = 143 passing** (+10 from PR #76: 8 LoS
unit tests in `test_runner.gd::_test_targeting`, 1 action_log clone
regression, 1 special_rules alias regression).

## Design decisions

- **Stage in two halves: extract first, sweep callers second.** Each
  module landed in two commits — extraction left thin wrappers in
  `game_engine.gd` so all callers compiled untouched, then a follow-up
  commit deleted the wrappers and pointed every caller at `Module.X`
  directly. Locked rule was "no rename + relocate in one commit"; this
  obeys it and gave the wrapper-sweep diffs single-file scope.
- **`preload()` everywhere, not just `class_name`.** The headless test
  runner doesn't refresh Godot's global script class cache, so newly
  added `class_name` files weren't resolvable mid-session. Every
  consumer has `const Module = preload("res://game/X.gd")` at module
  scope; the modules also carry `class_name` for editor support.
- **Inline 3-line objective check in board.gd, panic.gd, targeting.gd.**
  All three need "is this cell an objective?" but coupling them to
  objectives.gd would be a bigger sin than three identical 3-line loops.
  Duplication beats coupling here.
- **`game_engine.gd` stays under `server/`, not `game/`.** Moving the
  orchestrator under `game/` was explicitly out of scope per #65 — it
  touches autoload wiring and is a separate decision.
- **`check_victory` kept its public (no-underscore) name.** External
  callers (network_server, victory banner) use the legacy name; the
  wrapper preserved the call shape during transition, then the sweep
  pass updated those callers to `Objectives.check_victory` directly.
- **Closing `EngineResult.success`** (not just deprecating it). The
  redundant boolean was a contract trap — caller could set one without
  the other. `is_success()` derives from `error.is_empty()` so there's
  exactly one source of truth.

## Deferred

- **#77** `_find_adjacent_cell` 4-cardinal limitation — filed during the
  refactor, still open. Now lives in `Targeting.find_adjacent_cell`; fix
  is one line (add the four diagonal offsets to the offset array).
- **`_find_unit` duplicates** — `network_server.gd:347` and
  `panic.gd::_find_unit` both define their own local copies. Not worth
  consolidating: each is 4 lines, removing them would require either an
  upward dep on `game_engine` or a new shared module for one helper.
- **`game_engine.gd` further splitting** — at 1061 lines it's still
  bigger than the issue's ~700-line estimate. The residual is genuine
  orchestration (order flow + state helpers) and any further split
  would invent artificial seams.
- **Caching `find_shooting_targets`** — speculative until perf bites.

## Board state after

PR #78 closed #65. The five-module split is the pre-condition for the
remaining v17 mechanics work landing on a clean codebase rather than
inflating a 1900-line monolith.

Open mechanics + audit issues:

- **#54** — Stand and Shoot ← unblocked by #76, easier on
  `Targeting`/`Combat` post-split, natural next pickup
- **#46** — 1" rule (can't end move within 1" of another unit)
- **#47** — Charge: fail-still-move-full + 1" exception
- **#48** — Snob moves with its commanded unit during order
- **#49** — Reroll infrastructure (once-only enforcement)
- **#50** — Vanguard: pre-game free move phase
- **#51** — Dash: Whelps free move after order
- **#57** — Toff Off! Snob duel mechanic
- **#58** — Terrain system (Cover/Defensible/Dangerous/Impassable) —
  large; blocks #62
- **#59** — Scenario system (objectives, blunders, table layout)
- **#62** — Dangerous terrain test on retreat through Followers (blocked
  by #58)
- **#42** — cult rules audit (pre-deploy)

Bugs / out-of-mechanics:

- **#77** — `_find_adjacent_cell` diagonal charge contact (small, lives
  in `targeting.gd` post-split)
- **#74** — Battle UI: powder smoke indicator
- **#72** — Ruleset-version agility audit (pre-v19)
- **#70, #69, #68, #67, #66, #64** — UX/tooling/infra explorations

No new issues filed this session beyond #77 (filed during the refactor
review).

## Next pickup

**#54 — Stand and Shoot.** Defender fires at charger before melee
resolves. Reuses `Targeting.is_valid_shooting_target` and
`Combat.resolve_shooting_side` directly — the post-split module API was
designed with this exact reaction-window in mind. Smaller than landing
it would have been pre-refactor (the engine no longer balloons by
~150 lines per mechanic).

Alternatively, if you want to clear small debt first, **#77** is a
1-line fix in `Targeting.find_adjacent_cell` — add the four diagonal
offsets, run the engine tests, ship.
