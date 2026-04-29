# Checkpoint — 1" Rule

**Date:** 2026-04-29
**PR:** #81 (closes #46)
**Branch:** `feat/46-one-inch-rule`

Same-day continuation of the stand-and-shoot session. With #54 + #77 in,
#46 was the natural next mechanic — foundational for #47 (charge fail
movement) and #50/#51 (vanguard, dash). This checkpoint is written
pre-merge, on the feature branch.

## What shipped

End-position 1" rule (v17 p.9 + p.17), enforced inline at three call
sites with three distinct sub-rules:

- **`Board.validate_move`** (`godot/game/board.gd:38`) — march and
  move-and-shoot. Standard p.9 rules: a Follower may not end within 1"
  of a friendly Follower; any unit (Follower or Snob) may not end
  within 1" of an enemy. Snobs are exempt as either mover or near-unit
  for the friendly check ("Snobs may be moved and end their moves
  within 1" of any Friendly unit"); enemy proximity always counts.

- **`Targeting.find_adjacent_cell`** (`godot/game/targeting.gd:151`) —
  charge end position. Stricter p.17 rule: destination must be >1"
  from any unit except the charge target. No Snob exemption — even
  friendly Snobs near a candidate cell block it.

- **`Panic._is_valid_retreat_dest`** (`godot/game/panic.gd:212`) —
  retreat end. p.9 retreat clause: destination must be >1" from any
  other unit. No exemptions; "any other unit" means any.

Geometry, on the integer grid with Euclidean distance (per #44):

- Cardinal-adjacent cells are at distance 1.0 — within 1", illegal.
- Diagonal-adjacent cells are at √2 ≈ 1.41 — legal.

Test changes:

- The #77 corner-trap test asserted the diagonal `(9,9)` was selected
  when all 4 cardinals were blocked. Under strict charge geometry
  (p.17), every diagonal in that scenario is exactly 1.0 from a
  cardinal blocker, so the rules-correct outcome is "no legal cell".
  Test now asserts the sentinel `(-1, -1)`.
- Replaced with a "shorter-diagonal" test that exercises the actual
  #77 win case: charger at (8,8), target at (10,10), no blockers —
  diagonal contact at √2 beats the longer cardinal route at 2.24.
- New `_test_one_inch_rule` suite with 8 tests:
  - Follower → friendly Follower: forbidden
  - Snob mover → friendly Follower: allowed (mover exemption)
  - Follower → friendly Snob: allowed (near-unit exemption)
  - Any unit → enemy: forbidden (Snob mover doesn't help vs enemies)
  - Diagonal-adjacent (1.41) is legal
  - March integration via `execute_order`: rejected with `"1\""` in
    error
  - Charge non-target friendly within 1" blocks the cell
  - Retreat dest within 1" of friendly Snob is rejected (no exemption
    for retreat — spirals outward to a legal cell)

Tests on branch: **132 engine + 29 type = 161 passing** (+9 vs the
stand-and-shoot checkpoint: 8 from the new 1" rule suite + 1 from the
new shorter-diagonal targeting test, with the corner-trap test
rewritten in place rather than added).

`Board` is now imported in `tests/test_game_engine.gd` alongside
`Targeting`/`Combat`/`Panic`/`Objectives` — required by the new direct
unit tests against `Board.validate_move`.

## Design decisions

- **Inline at three call sites, not one mega-helper.** The three
  modes diverge enough — different allow-list semantics, different
  exemption rules, different "who counts as a near-unit" predicates —
  that a unified helper would need a `mode` enum or three flags. Three
  ~10-line inline checks beat a flag-soup helper. The deliberate
  duplication mirrors the `objective` check choice from the
  engine-module-split (board.gd, panic.gd, targeting.gd each do their
  own objective lookup for the same reason).
- **Standard mode lives in `Board.validate_move`, not a sibling
  function.** Both march and move-and-shoot already call
  `validate_move` for bounds + occupancy + objective. Adding the 1"
  check there means no caller changes — the validator just got
  stricter. Charge and retreat needed their own variants because
  their call paths use different validators (`find_adjacent_cell` and
  `_is_valid_retreat_dest`).
- **`d <= 1.0` (inclusive) for "within 1 inch".** A cardinal-adjacent
  cell is at exactly 1.0 distance and we count it as within 1". Same
  convention as objective capture (Euclidean ≤1.0). Diagonal-adjacent
  at 1.41 is outside. This makes the rule match the colloquial reading
  ("right next to a unit").
- **Kept `find_adjacent_cell` returning `(-1, -1)` on no-legal-cell
  rather than throwing or returning a result type.** The sentinel was
  already there; tightening the legality criteria just narrows the
  set of cells that pass. Caller already handles sentinel via the
  "No open cell adjacent to target" error path in `_execute_charge`.
- **Retreat keeps the `_is_valid_retreat_dest` spiral search.** With
  the 1" rule added, the spiral may need to expand further before
  finding a legal cell. The spiral was already 5 layers deep
  (`for radius in range(1, 6)`); 1"-rule failures within that radius
  will keep cycling until a >1"-from-everyone cell is found. Did not
  expand the spiral cap — existing tests pass within radius 5.

## Deferred

- **Deployment 1" rule** (v17 p.9: Followers may not be deployed
  within 1" of friendly Followers). `place_unit` doesn't go through
  `validate_move` and has its own bounds/zone/occupancy check. The
  issue scope was move validation; deployment is a separate code path
  with a separate sub-clause and minimal interaction (enemies usually
  aren't on board yet at placement time). Worth a small follow-up PR
  if it bites in playtest.
- **Path-not-just-end checking.** The rule wording "A unit may never
  move within 1\" ... of an enemy model" technically restricts the
  entire move PATH, not just the end position. Our discrete grid
  treats movement as teleportation between cells; we only validate
  the destination. For march/move_and_shoot this is harmless (the
  path ≤ end position in proximity terms when moves are short
  Euclidean lines). For retreat the rule explicitly allows
  passing-through, so we already match that. Charge has a strict
  end check but no path enforcement; current `find_adjacent_cell`
  doesn't reason about the swept route.
- **Detailed error messages.** Errors say "Cannot end move within 1\"
  of enemy unit (Toff)" with the unit type, which is sufficient for
  the action_log. If the UI ever wants to highlight the offending
  unit, the message would need to include the unit ID — currently
  absent. Not blocking.
- **Charge "must still move full distance on fail" (#47).** The 1"
  rule machinery is in place but the related #47 work — chargers that
  fail to make contact must still move their full charge distance
  along the shortest route — is the next mechanic, not bundled.

## Board state after

PR #81 closes #46. Audit memory `project_audit_sequencing.md` rotates
the next pickup to **#47** (charge fail-still-move-full + 1" exception),
which uses the same machinery added here.

Open mechanics + audit issues:

- **#47** — Charge: fail-still-move-full + 1" exception ← natural next
  pickup, reuses Board.validate_move + the find_adjacent_cell 1" check
- **#48** — Snob moves with its commanded unit during order
- **#49** — Reroll infrastructure (once-only enforcement)
- **#50** — Vanguard: pre-game free move phase (uses #46 helpers)
- **#51** — Dash: Whelps free move after order (uses #46 helpers)
- **#57** — Toff Off! Snob duel mechanic
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

**#47 — Charge: fail-still-move-full + 1" exception.** v17 p.17:
"Failed Charges: If it is impossible for any model in the charging
unit make it into base-to-base contact with the target, they must
still move towards the target their full charge distance via the
shortest route possible." Currently `_execute_charge` rejects charges
that can't reach base contact; under the rule the charger should
still spend its full charge distance moving toward the target along
the shortest legal path.

The 1" rule machinery added here is what gates the failed-charge end
position — even on a failed charge, the unit can't end within 1" of
non-target units. Reuse `Targeting.find_adjacent_cell`'s 1" filter
when picking the closest legal cell along the charge vector.

Likely shape:

- Detect failure mode (no `find_adjacent_cell` result OR move_distance
  > charge_range).
- Move the charger along the vector toward target, maxing out at
  charge_range, but stopping at the last legal end position (>1"
  from any non-target unit, in-bounds, not occupied).
- No melee, no Stand-and-Shoot, no panic test (the charge is declared
  but failed to connect — though arguably the target's panic test still
  fired before the charge-distance roll, per p.16 step 2; check the
  rules wording carefully).
- Action log: a new `charge_failed_path` entry with the
  failed-charge-end position.
