# Checkpoint — Stand and Shoot

**Date:** 2026-04-29
**PRs:** #79 (closes #77), #80 (closes #54)
**Branches:** `fix/77-diagonal-charge-contact`, `feat/54-stand-and-shoot` (both merged + deleted)

Backfilled checkpoint — pre-merge-housekeeping was skipped on both PRs,
so this is written retroactively from the merged commits and the live
audit memory. Both PRs branched off `main`; #77 was a 5-minute warm-up
on the new `Targeting` module before #54 went in on its own branch, per
the "lets do both separate" call.

## What shipped

### #77 — Diagonal charge contact (PR #79)

`Targeting.find_adjacent_cell` (`godot/game/targeting.gd:151`) used to
iterate only the 4 cardinal offsets `(±1, 0)` / `(0, ±1)`. A charger
whose target had cardinals blocked but diagonals open returned the
sentinel `Vector2i(-1, -1)` and got rejected as "no open cell adjacent
to target". v17 base contact (p.16: "for something to be in base to
base contact, it is enough for any part of one base to be touching any
part of another base") accepts diagonal contact at √2 ≈ 1.41 on the
integer grid. Loop now walks all 8 ring offsets; tie-break by Euclidean
distance from the charger is unchanged, so cardinals still win when
both options exist (cardinal at 1.0 < diagonal at √2).

Three new direct unit tests under `_test_targeting()` in
`tests/test_game_engine.gd`:

- corner-trap diagonal accepted (charger 8,8 / target 10,10 / cardinals
  blocked → returns (9,9), the closest diagonal)
- cardinal preferred when both available (charger 8,10 / target 10,10
  → returns (9,10))
- all 8 ring cells blocked → returns `(-1,-1)` sentinel

### #54 — Stand and Shoot (PR #80)

v17 core p.16 step 3 reaction window — the target of a charge MUST
Stand and Shoot if it has a ranged weapon, no powder smoke, and is not
close-combat-equipped. Range and LoS are NOT required ("the unit waits
until just before impact before firing"). Charger cannot return fire
(it's a shooting attack, not a shooting engagement). Wounds, panic
token (any hit, saved or not), and powder smoke applied per the
standard shooting attack steps (p.14). If S&S wipes out the charger,
the charge ends with no melee.

New API in `godot/game/combat.gd`:

- `Combat.can_stand_and_shoot(target: UnitState) -> bool` — alive,
  `weapon_range > 0`, no `has_powder_smoke`, `equipment != "close_combat"`.
- `Combat.resolve_stand_and_shoot(target, charger, dice, offset) -> Dictionary`
  — calls `resolve_shooting_side` (one-sided), applies wounds to charger,
  applies powder smoke to target if `equipment == "black_powder"`, gives
  charger +1 panic token if any hit lands. Returns
  `{hits, saves, wounds, charger_dead, smoke_applied, dice_used, error}`.

Wiring in `godot/server/game_engine.gd::_execute_charge`:

- Inserted between panic-pass and melee. Failed-panic branch (target
  retreats) is untouched — S&S is gated on the panic test passing,
  matching v17 p.16 step 3 (this is a rules-text correction vs. the
  issue body, which implied S&S was unconditional).
- If `new_unit.is_dead` after S&S: dedicated early-return that builds
  its own action_log entry (`charger_destroyed_by_ss: true`) and skips
  the move + melee path entirely.
- Otherwise, melee dice are sliced from `dice_results.slice(ss_dice_used)`
  so the S&S dice and the melee dice live in one pre-rolled flat array
  (S&S first, then melee).
- Post-melee action_log gains `stand_and_shoot` and
  `charger_destroyed_by_ss: false` fields. The result description
  appends ` — S&S N wounds` when `wounds > 0`.

Dice budget in `godot/server/network_server.gd::_roll_execute_dice`
charge case bumped: `ss_dice = target.model_count * 2` when target is
known and `Combat.can_stand_and_shoot(target)` returns true; falls back
to the charger's own `model_count * 2` when target is unknown at roll
time (fizzle path). Total = `ss_dice + (atk_per_bout + def_per_bout) *
MELEE_MAX_BOUTS`.

Six new tests in `_test_execute_charge`:

- eligibility predicate (5 sub-cases: ranged-OK, smoked, no-range,
  close-combat, dead)
- S&S fires before melee, charger takes wounds (dies in counter-strike)
- powder smoke on target blocks S&S (no `stand_and_shoot` log entry)
- close-combat-equipped target blocks S&S
- S&S wipes out charger → charge ends, no melee, defender unscathed
  (action_log has `charger_destroyed_by_ss: true`, no `bouts` key)
- failed panic test → target retreats, no S&S (target never fires,
  `has_powder_smoke` stays false)

Five existing charge integration tests now set `target.has_powder_smoke
= true` to skip S&S where the test is focused on melee/panic mechanics
— `_test_execute_charge` x3, `_test_panic_test` x1 (Fearless target),
`_test_melee_bouts` x2. No dice arrays were touched; all behavior
preserved.

Tests on main: **123 engine + 29 type = 152 passing** (+9 vs the #78
checkpoint: 3 from #77, 6 from #54).

## Design decisions

- **Two separate PRs, not one bundle.** User explicitly chose separate
  ("we can do both separate"). #77 was a 1-line targeting fix sitting
  in the same module the post-#65 split moved it to; bundling it with
  S&S would have hidden the small fix inside a larger feature diff and
  made the targeting bug harder to revert independently.
- **`can_stand_and_shoot` is a pure predicate, no charger argument.**
  Eligibility depends only on the target's own state — equipment,
  smoke, alive, weapon_range. Range/LoS are explicitly waived by the
  rule, so there's no caller-position dependency. Compare with
  `can_return_fire(target, shooter)` which DOES need the shooter
  position to range-check — keeping the signatures different signals
  the rule difference.
- **One-sided resolver, not a wrapper around `resolve_shooting_engagement`.**
  S&S forbids charger return fire (rules: "this is a shooting attack,
  not a shooting engagement"), so reusing the engagement path would
  require a flag to disable return fire. Calling `resolve_shooting_side`
  directly and bundling the wound + smoke + panic-token bookkeeping
  reads more directly.
- **Powder-smoke as the test-bypass for existing tests.** Five existing
  charge tests had targets with `weapon_range > 0` and `equipment =
  "black_powder"` (the `_mock_unit` default), so all of them now
  trigger S&S. Setting `target.has_powder_smoke = true` is a
  one-line-per-test fix that semantically signals "we're not testing
  S&S in this case" and avoids reshuffling each test's dice array.
- **S&S dice come first in the flat array, melee after.** Matches the
  rule's temporal order. `_execute_charge` passes
  `dice_results.slice(ss_dice_used)` to `Combat.resolve_melee` after
  S&S returns — `resolve_melee` already starts at offset 0 of its
  input, no signature change needed.
- **Conservative S&S budget when target unknown.** `_roll_execute_dice`
  for charge falls back to `unit.model_count * 2` (the charger's count)
  for the S&S budget when the target hasn't been resolved yet (fizzle
  path or pre-target params). Over-rolls slightly but never
  under-rolls; resolver only consumes what it needs.
- **Rules-text correction vs the issue body.** The #54 issue body
  implied S&S was a flat reaction every charge; v17 p.16 actually
  gates it on the target passing its panic test (failed panic = retreat
  path, no S&S). Memory `project_audit_sequencing.md` now records this.

## Deferred

- **Black powder edge: charger fires before S&S resolves.** Pure
  reading of v17 says S&S happens "just before impact" — no rule
  ordering question with the charger's own shooting earlier in the
  round. We don't have charger-shoots-then-charges sequencing in the
  engine yet (volley_fire and move_and_shoot are their own orders), so
  no conflict to resolve.
- **`charger_destroyed_by_ss` action_log field.** Added because the UI
  layer hasn't been wired yet (#74 powder smoke indicator is the
  closest open issue but doesn't render charge outcomes). When
  battle_log surfacing lands we'll likely fold this into a unified
  `outcome` enum.
- **Action_log shape duplication.** The S&S-charger-wiped early-return
  rebuilds most of the same dict that the post-melee path builds.
  Tolerable today (two sites, ~15 lines apart); if a third charge-end
  outcome appears we should extract a `_make_charge_log_entry()` helper.
- **`stand_and_shoot` dict in log when not eligible.** Currently the
  field is set to `{}` (empty) when S&S didn't fire. Tests rely on
  `is_empty()` to detect "didn't fire". An explicit `null` would be
  semantically cleaner but the existing `panic_test` field uses the
  same `{}` sentinel for auto-pass, so we're consistent.

## Board state after

PR #79 closed #77. PR #80 closed #54. Audit memory
`project_audit_sequencing.md` updated with both as Done and the next
pickup rotated to #46.

Open mechanics + audit issues (per `gh issue list --state open`):

- **#46** — 1" rule (can't end move within 1" of an enemy unit) ←
  natural next pickup, foundational for #47/#50/#51
- **#47** — Charge: fail-still-move-full + 1" exception (uses #46)
- **#48** — Snob moves with its commanded unit during order
- **#49** — Reroll infrastructure (once-only enforcement)
- **#50** — Vanguard: pre-game free move phase (uses #46)
- **#51** — Dash: Whelps free move after order (uses #46)
- **#57** — Toff Off! Snob duel mechanic
- **#58** — Terrain system (Cover/Defensible/Dangerous/Impassable) —
  large; blocks #62
- **#59** — Scenario system (objectives, blunders, table layout)
- **#62** — Dangerous terrain test on retreat through Followers
  (blocked by #58)
- **#42** — cult rules audit (pre-deploy)

Bugs / out-of-mechanics:

- **#74** — Battle UI: powder smoke indicator (more relevant after #54
  — every charge against an unsmoked target now generates a smoke token
  on the defender; the visual cue is missing in the client)
- **#72** — Ruleset-version agility audit (pre-v19)
- **#70, #69, #68, #67, #66, #64** — UX/tooling/infra explorations

No new issues filed this session.

## Next pickup

**#46 — 1" rule.** v17 p.17: "Charging is the only time a unit may
come within 1\" of an enemy unit." Every other move type — march,
move_and_shoot post-move, retreat destination, future vanguard/dash —
must enforce a min-1" gap from any enemy unit. Charge is the explicit
exception (and even charging units cannot END within 1" of any unit
other than the target).

Likely shape: a `Board.is_legal_end_position(state, unit, x, y, allow_target_id)`
helper checking enemy-proximity (≤1.0 Euclidean to any non-target enemy)
on top of the existing in-bounds + objective-cell constraints. Wired
into the march, retreat, and move_and_shoot post-move validation paths.
Charge keeps its existing `find_adjacent_cell` flow (charge END must
be base contact = the diagonal/cardinal cell next to the target,
which is necessarily ≤1.0 from the target and ≥1.0 from anything else
since other units are blockers in the search).

Knock-on: unblocks #47 (charge fail must still move full distance per
the rule, but cannot end within 1" of non-targets — same helper),
#50 (vanguard free moves), #51 (Whelps dash). #46 is the cheapest
unlock for those three.
