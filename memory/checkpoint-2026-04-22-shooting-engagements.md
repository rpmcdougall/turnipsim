# Checkpoint — 2026-04-22 — Shooting Engagements (#40)

**Branch:** `feature/shooting-engagements` (commits `082fc9f`, `2e4c7e7`). **Not yet merged.**
**Closes:** #40 (simultaneous return fire + winner/loser retreat).

## What shipped

Shooting resolves as a two-sided engagement per v17 core pp. 13, 15, 20.

**`_resolve_shooting_engagement(attacker, target, dice, att_inac_mod) -> Dictionary`:**
- Attacker rolls first (pool laid out attacker-then-defender).
- Defender returns fire if eligible — computed from pre-engagement model counts.
- Wounds applied to both sides AFTER both rolls (casualties don't suppress return).
- Hit-triggered panic tokens (per side), powder smoke on whichever side fired with `black_powder`.
- Winner = more unsaved wounds. Tie = no winner, no retreat.
- Returns `{att/def_hits/saves/wounds, return_fire_fired, winner_id, loser_id, tie, dice_used, error}`.

**Helpers:**
- `_resolve_shooting_side(attacker, target, dice, offset, inac_mod)` — the old `_resolve_shooting` refactored to pure computation with dice offset, no mutation.
- `_can_return_fire(target, shooter)` — alive + `weapon_range > 0` + no smoke + shooter in target's range.

**Caller integration:**
- `_execute_volley_fire` + `_execute_move_and_shoot` now route through the engagement resolver, retreat the loser via `_execute_retreat(..., retreat_die)`.
- Move & Shoot return-fire range uses shooter's **post-move** position.
- Action log gains `return_fire`, `return_hits`, `return_wounds`, `engagement_winner_id/loser_id/tie`, `retreat`.

**Server:**
- Rolls `retreat_die` for `volley_fire` / `move_and_shoot` alongside the existing charge roll.
- Dice pool sizing: `(shooter.models + target.models) × 2` when target known, symmetric pool otherwise (fizzle / no-target move_and_shoot branches).

**Tests:** 13 new shooting engagement tests (9 direct resolver + 4 integration), 7 existing shooting tests updated to pad for return-fire dice. 103 engine + 19 type = 122 total, all passing.

## Design decisions

- **Per-hit panic only** — v17 shooting rules don't call for an "all participants gain +1 panic" like melee p.18 does. Only hit-triggered tokens accrue (both sides independently, based on whether the opposite side landed a hit).
- **Smoke applies after resolution** — so return fire can still happen when the attacker is a black_powder unit (attacker's smoke token lands at the end of the engagement, not before target checks).
- **Return fire inaccuracy_mod = 0** — volley fire's `-1` bonus is only for the declared order, not the return fire response.
- **Dice laid out attacker-then-defender** — simple offset scheme, matches melee bout layout.
- **Move & Shoot no-target path unchanged** — when shooter just moves (no target_id), `fired` stays false, no engagement, legacy behavior preserved.

## Not addressed here (deferred)

- **DT tests on retreat through Followers** (#62) — gated on terrain system (#58).
- **Powder-smoke UI indicator** — filed as new issue **#74**.
- **v18 off-board retreat rule** — tracked under #72.
- **Stand-and-shoot** (#54) — defender fires before melee on a charge. Separate mechanic.

## Board state after

Major v17 combat mechanics now complete: panic (#52 → #61), retreat (#53 → #63) with D6+2×tokens (fix in #73), melee bouts (#55 → #71), shooting engagements (#40 → this PR). Phase 4 combat engine is close to rules-complete.

New issues this session: #64, #65, #66, #67, #68, #69, #70 (feature/refactor tracking), #72 (ruleset agility audit), #74 (powder smoke UI).

Still open for Phase 4 rules accuracy:
- **#56** LoS + closest-target (unblocked)
- **#54** Stand and Shoot
- **#45–#51, #57** independent mediums
- **#58** terrain (large)
- **#59** scenarios (large)
- **#42** cult audit
- **#38** remaining v17 rules-accuracy audit items

## Next pickup

**#56 (LoS + closest-target)** is a natural follow-up — constrains who can be shot at, tightens the targeting that now gets exercised by return fire too. Small-to-medium scope.
