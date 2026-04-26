# Checkpoint — Line of Sight + Closest-Target Enforcement

**Date:** 2026-04-25
**PR:** #76
**Branch:** feature/line-of-sight (merged + deleted)

Backfilled checkpoint — pre-merge-housekeeping was skipped on this PR, so
this is written retroactively from PR #76 + commit `a15729b`. Pre-scoping
lives in `memory/checkpoint-2026-04-22-session-wrap.md`; the implementation
followed that scope without deviation.

## What shipped

Six new static helpers in `godot/server/game_engine.gd`, all pure (no
state mutation, no RNG):

- `_has_line_of_sight(state, from_x, from_y, to_x, to_y) -> bool`
  (game_engine.gd:1587) — supercover line walk between integer cells. Any
  alive **non-Snob** unit strictly between the endpoints blocks. Snobs
  never block (v17 p.5). Endpoints excluded; dead units don't block.
- `_find_shooting_targets(state, shooter) -> Array` (game_engine.gd:1650)
  — alive + enemy + in weapon range + LoS, from shooter's current cell.
- `_find_shooting_targets_from(state, shooter, from_x, from_y) -> Array`
  (game_engine.gd:1667) — same, but LoS measured from an arbitrary cell.
  Used by Move & Shoot to validate post-move LoS.
- `_is_valid_shooting_target(state, shooter, target) -> String`
  (game_engine.gd:1688) — empty string on legal, error string on illegal.
  Closes on: exists, alive, enemy, in range, LoS, and (unless
  `sharpshooters`) is among the tied-closest valid enemies.
- `_is_valid_shooting_target_from(...)` (game_engine.gd:1721) — same with
  LoS-from-position semantics for M&S.

Wired into:
- `_execute_volley_fire` (game_engine.gd:501) — LoS + closest-target gate.
- `_execute_move_and_shoot` (game_engine.gd:628) — LoS from post-move cell.
- `_execute_charge` (game_engine.gd:762) — LoS required, **no**
  closest-target (chargers can pick any reachable enemy per #56 scope).
- Fizzle gates (game_engine.gd:1799, 1811) updated to use the same
  helpers, so panic-fail / no-target-available paths agree with the
  validation gates.

11 new tests in `godot/tests/test_game_engine.gd`: LoS clear, LoS blocked
by Follower, Snob doesn't block, dead unit doesn't block, endpoints don't
block, diagonal LoS, closest-target rejection, tied-closest both legal,
Sharpshooters bypass closest-target, fizzle with blocked LoS, charge with
blocked LoS. **114 engine + 19 type = 133 tests passing.**

## Design decisions

- **Supercover discretization, not Bresenham.** Every cell touched by the
  line is checked. Slightly more conservative than Bresenham (favors the
  defender on diagonals) and avoids the "thin line slips through a corner"
  surprise.
- **Endpoints excluded from blocker check.** Shooter and target cells
  never count as blockers; otherwise every unit blocks itself.
- **Tied-closest is permissive.** If two enemies are tied for nearest, the
  shooter may pick either. Cleaner UX than coin-flipping; matches v17 p.13
  reading.
- **Snobs never block.** v17 p.5 explicit rule. The supercover walk skips
  Snob-typed units when checking blockers.
- **Closest-target does NOT apply to charges.** Per #56 scope: a charging
  unit may target any reachable enemy with LoS, even if a closer enemy
  exists. This is consistent with v17's separation of shooting targeting
  rules from charge target selection.
- **`from_x/from_y` parameter pattern over post-move state mutation.** M&S
  needs LoS from the post-move cell *before* committing the move. Passing
  the cell explicitly to a `_from` variant keeps the helpers pure rather
  than threading a hypothetical-state object.
- **Server stays authoritative; client hints unchanged.** `grid_draw.gd`
  still draws green target rings around all in-range enemies, including
  ones behind blockers. Clicks on those will fail server-side. Deferred
  visual fix called out in PR body and below.

## Deferred

- **#58 Terrain LoS blocking** — terrain doesn't exist yet. When it lands,
  `_has_line_of_sight` gains a terrain check inside the supercover loop.
- **Client-side LoS hints** (no issue filed; trivial when the time comes)
  — `grid_draw.gd` should suppress target rings on enemies without LoS so
  players don't click illegal targets. Server-authoritative behavior is
  correct today; this is purely UX.

## Board state after

PR #76 closed #56. **Phase 4 combat engine continues to converge on
rules-completeness.** Open mechanics + audit issues:

- **#54** — Stand and Shoot ← unblocked by this PR, natural next pickup
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
- **#38** — remaining v17 audit items
- **#42** — cult rules audit (pre-deploy)

Out-of-mechanics: **#64–#70, #72, #74** all available. **#65 (refactor:
split oversized files)** is starting to itch — `game_engine.gd` is now
1800+ lines with this PR's helpers added. Worth thinking about before
#54/#58 inflate it further.

No new issues filed this session.

## Next pickup

**#54 — Stand and Shoot.** Unblocked by this PR (depends on LoS), small
scope (defender fires at charger before melee resolves), and the LoS code
is freshly in head. Reuses `_is_valid_shooting_target` directly.

Alternatively, if file size is bothering you, **#65** (refactor split) is
a good rainy-day pickup before more mechanics pile in — `game_engine.gd`
is the obvious split candidate, with targeting/LoS, combat resolution,
and order execution as the natural seams.
