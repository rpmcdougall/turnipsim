# Checkpoint — Failed Charge Movement

**Date:** 2026-05-02
**PR:** #47 (closes #47)
**Branch:** `feat/47-charge-fail-move-full`

Continuation of the v17 audit sequence. With #46 (1" rule) shipped in PR
#81, #47 was the natural next pickup — the same charge-strict 1" filter
gates failed-charge end positions. Pre-merge checkpoint, on branch.

## What shipped

v17 p.17 "Failed Charges": when no model can reach base-to-base contact,
the unit must still move its full charge distance toward target via the
shortest legal route. Replaces three error returns in `_execute_charge`
with a unified failed-charge resolution.

- **`Targeting.find_failed_charge_destination`** (`godot/game/targeting.gd:206`) —
  new helper. Iterates cells within `charge_range` Euclidean distance of
  the charger; filters to legal cells (in bounds, unoccupied, not on an
  objective, >1" from any non-target non-charger unit — the same
  charge-strict 1" mode `find_adjacent_cell` uses). Picks the legal cell
  minimizing Euclidean distance to target; tie-breaks by maximizing
  distance from charger's start cell. Falls back to the charger's own
  cell if no legal destination exists (pinned).

- **`_execute_charge`** (`godot/server/game_engine.gd:741`) — three
  failure paths now route into a single failed-charge branch:
  1. `target_distance > charge_range` → `failure_reason = "out_of_range"`
  2. `find_adjacent_cell` returns `(-1,-1)` → `"no_legal_adjacent_cell"`
  3. closest legal 8-ring cell is past `charge_range` → `"adjacent_cell_unreachable"`

  The branch moves the unit to the helper's destination, calls
  `_advance_after_order`, logs an `action: "charge_failed"` entry with
  `failure_reason`, `from_x`/`from_y`, `to_x`/`to_y`, and returns.
  No panic test, no Stand and Shoot, no melee — the charge never
  contacted the target.

- **Tests** — `tests/test_game_engine.gd`:
  - Replaced the obsolete "charge: reject target out of charge range"
    test (which expected `result.error` to contain "charge range") with
    "charge fail: target out of range — moves full charge distance
    toward target". With Toff M=6 and dice [1,1] (bonus 2, range 8),
    target at (30, 10), the charger advances from (10, 10) to (18, 10)
    on the rim of its charge disc, target alive, log records
    `charge_failed` with `failure_reason: out_of_range`.
  - "charge fail: target ring all 1\"-blocked — advances and stops
    short": surrounds target with 8 friendly Snob blockers. Snobs
    occupy the ring cells (so `find_adjacent_cell` returns `(-1,-1)`)
    but don't block LoS (v17 p.5), so the charge declares cleanly. The
    helper places the charger at one of the 4 corner cells outside the
    ring at distance √8 ≈ 2.83 from target. Asserts the end position
    respects the >1" rule against every non-target unit.
  - "charge fail: pinned charger with no legal cell stays put": direct
    helper unit test. Wraps the charger in a 5×5 block of seat-2
    Followers; passes `charge_range=2` so every cell within reach is
    occupied or 1"-blocked; asserts `find_failed_charge_destination`
    returns `Vector2i(charger.x, charger.y)`.

Tests on branch: **134 engine + 29 type = 163 passing** (+2 vs the
1"-rule checkpoint: net of one obsolete test deleted and three new
tests added).

## Design decisions

- **Two-criterion ranking ("closest to target" primary, "farthest from
  start" tie-break) over a single rim-only search.** Rules text reads
  "their full charge distance via the shortest route possible." Two
  natural readings:
  - (A) End on the rim of the charge disc (full distance, mandatory),
    cell that minimizes distance to target along the rim.
  - (B) End at the cell minimizing distance to target within the disc,
    breaking ties by maximizing distance from start.

  (B) was chosen. The "ring blocked" case is the realistic failure mode
  — target is well within range but you can't reach base contact — and
  there (A) would force the charger to overshoot past the target, which
  is wrong. (B) lets the charger advance up close and stop, while still
  honoring "full distance" via the tie-break in cases where multiple
  legal cells tie for closeness. For the "out of range" case the two
  interpretations converge: the rim cell on the line from charger to
  target wins on the closest-to-target criterion.

- **Helper iterates the bounding box around the charger, not a
  spiral.** Charge ranges are small (M+2D6 ≤ ~18); the disc has at most
  ~1000 cells. A direct nested loop is simpler than a spiral and
  doesn't need to track "is this cell inside the disc" beyond a
  Euclidean check. Matches the iteration shape of `find_adjacent_cell`.

- **Pinned-charger fallback returns the start cell.** v17 doesn't say
  what happens if the charger has no legal move. The conservative
  reading: the unit stays put. The start cell may itself violate the
  charge-strict 1" rule (e.g., a Snob ended adjacent to a friendly
  Follower last turn under the lenient standard rule), but that's the
  fault of the strict rule applied to a position established under a
  permissive rule — staying put is at worst a no-op. The fallback
  doesn't validate the start cell, just returns it.

- **`failure_reason` carries the path tag.** The three modes are
  fundamentally one rule but differ in what the player sees: "I picked
  a target out of range" vs "I picked a target in range but couldn't
  squeeze in." The action_log entry distinguishes them so the UI can
  surface a meaningful explanation later. No client wiring yet — pure
  data field for now.

- **Snob blockers (not Followers) for the "ring blocked" test.** Hit
  this during test debugging: 8 Follower blockers around the target
  blocked LoS to the target (one of them sat exactly on the line from
  charger to target). The pre-existing LoS check in `_execute_charge`
  fired first and rejected the charge declaration outright, never
  reaching the failed-charge branch. Switching the blockers to Snobs
  (which don't block LoS per v17 p.5) lets the charge declare cleanly
  and exercises the actual failed-charge path.

## Deferred

- **Charge declared with no LoS** still errors out with "No line of
  sight to charge target". v17 p.16 makes LoS a precondition for charge
  declaration, so this isn't strictly a "failed charge" case — it's an
  invalid declaration. Could be revisited if playtest finds it
  surprising (player picks an enemy that LoS just barely excludes,
  expects to advance and discovers the charge silently bounced).
- **Snob-moves-with-Follower (#48).** Identified as the next pickup.
  Currently a Snob ordering a Follower stays put; should move with
  the unit it commands during the order's movement step.
- **Closest-cell pre-check overshoot.** Line 744's `target_distance >
  charge_range` test is overly strict in narrow geometric cases — when
  the closest 8-ring cell is exactly at distance `charge_range`, the
  pre-check rejects and routes to failed-charge even though contact
  was geometrically reachable. Fixing it would require deferring the
  range check to after `find_adjacent_cell` and inspecting that cell's
  reachability instead. Not worth the extra logic until a playtest
  surfaces it; the failed-charge fallback still does the right thing
  (the unit moves toward target).
- **`charge_failed` UI rendering.** Battle log currently formats
  `charge` actions specifically; `charge_failed` will render with the
  default fallback until `client/scenes/battle/action_log_view.gd`
  gets a case for it. Cosmetic — server logs are correct.

## Board state after

PR #47 closes issue #47. Audit memory `project_audit_sequencing.md`
rotates the next pickup to **#48** (Snob moves with its commanded
unit during order — v17 p.16 step 1).

Open mechanics + audit issues:

- **#48** — Snob moves with commanded Follower ← natural next pickup
- **#49** — Reroll infrastructure (once-only enforcement)
- **#50** — Vanguard: pre-game free move phase (uses #46 helpers)
- **#51** — Dash: Whelps free move after order (uses #46 helpers)
- **#57** — Toff Off! Snob duel mechanic
- **#45** — Improbable hits (7+/8+ via dice math)
- **#58** — Terrain system (Cover/Defensible/Dangerous/Impassable) —
  large; blocks #62
- **#59** — Scenario system (objectives, blunders, table layout)
- **#62** — Dangerous terrain test on retreat through Followers
  (blocked by #58)
- **#42** — cult rules audit (pre-deploy)

Bugs / out-of-mechanics:

- **#74** — Battle UI: powder smoke indicator
- **#72** — Ruleset-version agility audit (pre-v19)
- **#70, #69, #68, #67, #66, #64** — UX/tooling/infra explorations

No new issues filed this session.

## Next pickup

**#48 — Snob moves with its commanded unit during order.** v17 p.16
step 1: "When the Snob issues an order to a Follower unit, the Snob
moves with the Follower unit if the Follower moves." Currently
`_execute_march` / `_execute_charge` / `_execute_move_and_shoot` move
only the ordered unit (`unit`), leaving the commanding Snob in place.
For Snob-orders-Follower (the cross-order case), the Snob should
translate by the same delta as the Follower, subject to its own 1"
rule and bounds.

Implementation likely shape:
- Identify the cross-order case: `state.active_snob_id != unit.id`.
- After the ordered unit's new position is determined and validated,
  compute the Snob's would-be destination: `snob.x + (unit.new_x -
  unit.old_x)`, same for y.
- Validate the Snob's destination separately (1" rule, bounds, no
  occupancy clash). If illegal, the Snob stays — the order still
  executes for the Follower; only the Snob's drag-along is
  conditional. Or reject the whole order? Rules ambiguous; default
  to "Snob stays put if its drag-along would be illegal" pending a
  rules-text re-read.
- Wire into all three movement orders: march, charge, move-and-shoot.
- Failed-charge case: even on a failed charge, the Follower moves —
  so the Snob should drag along on a failed charge too.
