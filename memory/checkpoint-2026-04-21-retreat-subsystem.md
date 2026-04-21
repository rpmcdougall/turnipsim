# Checkpoint — 2026-04-21 — Retreat Subsystem (#53)

**PR:** [#63](https://github.com/rpmcdougall/turnipsim/pull/63) on branch `feature/retreat-subsystem`. **Merged.**
**Closes:** #53 (retreat subsystem).

## What shipped

Retreat movement per v17 core p.20.

**`_execute_retreat(state, unit_id) -> Dictionary`:**
- Find nearest alive enemy → compute direction away
- Distance = 2 × panic_tokens (min 1)
- Board edge → unit destroyed (is_dead, model_count=0)
- Stubborn Fanatics → stays put (never retreats)
- Returns `{retreated, destroyed, from_x/y, to_x/y, distance, stubborn_held}`

**Helpers:** `_find_nearest_enemy()`, `_find_retreat_cell()` (spiral fallback), `_is_valid_retreat_dest()` (bounds + occupancy + objective check)

**Charge integration:** Failed panic test now triggers real retreat. Target moves away from charger, charger occupies adjacent cell, no melee. Replaces the interim melee-skip from #52.

**Tests:** 6 new retreat tests + 1 updated charge integration. 81 engine + 19 type = 100 total, all passing.

**Filed #62:** DT tests when retreating through Followers — deferred to terrain system.

## Design decisions

- **No D6 in retreat distance** — rules reference says "2" per panic token", issue text was ambiguous ("D6 + 2" per panic token"). Went with simpler interpretation. Easy to add a die later if wrong.
- **Spiral search for destination** — if ideal cell is occupied/objective, spiral outward up to radius 5. Covers crowded board states.
- **Retreat is deterministic** — no server dice needed (unlike panic test). Simplifies network layer.
- **Board edge is lethal** — if ideal destination is off-board, unit is destroyed immediately. No partial retreat.

## Deferred

- DT tests retreating through Followers (#62)
- Impassable terrain crush (#58)
- Shooting/melee loss retreat triggers (#40, #55)

## Session summary (2026-04-21)

Three PRs shipped today:
1. **#60** — Euclidean distance (#44). All range checks use sqrt, circles replace diamonds.
2. **#61** — Panic test subsystem (#52). Keystone mechanic, Fearless/Safety in Numbers gates.
3. **#63** — Retreat subsystem (#53). Real retreat movement wired into charge panic.

Issues closed: #44, #52, #53, #34 (stale)
Issues filed: #62 (DT retreat)
Test count: 81 engine + 19 type = 100 total

## Board state after

Open issues (sequencing order):
1. **#55** — Two-sided melee bouts (next in sequence, depends on panic+retreat)
2. **#56** — LoS + closest-target (depends on #44, done)
3. **#45–#51, #54, #57** — Independent mediums
4. **#58** — Terrain system (large)
5. **#59** — Scenario system (large)
6. **#62** — DT retreat (depends on #53+#58)
7. **#40** — Return fire + retreat triggers (sibling of #53)
8. **#42** — Cult audit (pre-deploy)

## Next pickup

**#55 (two-sided melee bouts)** is the natural next step — it depends on panic (done) and retreat (done). Currently melee is one-sided (charger only); v17 has bouts where both sides attack.
