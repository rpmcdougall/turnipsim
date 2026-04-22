# Checkpoint — 2026-04-22 — Two-sided Melee Bouts (#55)

**Branch:** `feature/melee-bouts` (commits `0f4584c`, `6af7a16`). **Not yet merged.**
**Closes:** #55 (two-sided melee bouts with counter-attack).

## What shipped

Melee resolves in bouts per v17 core p.18 instead of a single attacker-only pass.

**`_resolve_melee(attacker, target, dice_results) -> Dictionary`:**
- Per bout: attacker strikes → defender removes casualties → (if defender alive) defender counter-strikes → attacker removes casualties.
- Winner = side dealing more unsaved wounds that bout. Equal → next bout.
- Hard cap `MELEE_MAX_BOUTS = 3`; cap-hit draw = no retreat (both sides still panic).
- Returns `{bouts: [...], winner_id, loser_id, draw, dice_used, error}`.

**Helpers:** `_resolve_bout_side` (one side's strikes, consumes dice from a pool via offset), `_melee_dice_budget` (worst-case sizing, unused externally but available).

**Charge integration (`_execute_charge`):**
- After melee: +1 panic to both survivors; loser runs `_execute_retreat`.
- Charger can now lose and retreat — no longer guaranteed to hold the adjacent cell.
- Action log carries full bout history, winner/loser ids, retreat result, `charger_retreated` flag.

**Server dice pool:** `network_server._roll_execute_dice` now sizes charge pool as `(A_atk + A_def) * 2 * MELEE_MAX_BOUTS`, using the target's stats when available. Fizzle path falls back to a symmetric pool on attacker stats.

**Tests:** 8 new (6 direct `_resolve_melee`, 2 charge integration) + 1 updated (Fearless test now supplies counter-attack dice + expects post-melee panic). 89 engine + 19 type = 108 total, all passing.

**User-reported manual validation:** charging bouts exercised via test-stack clients — works end-to-end.

## Design decisions

- **Bout cap = 3 with draw-on-cap** — rules have no hard cap, but tied bouts on whiffing dice could loop forever. Cap keeps the engine deterministic; draws still apply the post-melee panic. Easy to lift later if playtest finds 3 feels wrong.
- **Pre-rolled dice pool, not a `roll_d6` Callable** — initially planned to switch to Callable injection (panic/retreat pattern) but the engine's charge path already uses a pool for audit/determinism. Keeping the pool convention; caller sizes it for worst case.
- **Charger retreats on loss, without re-pathfinding** — `_execute_retreat` anchors off nearest enemy; the defender is adjacent, so charger retreats back away naturally. No special-case code.
- **Dead target skips its counter-attack** — checked between attacker strike and defender strike. Prevents ghost attacks from a wiped unit.

## Deferred / not addressed

- Return fire on shooting (#40) — sibling problem to #55, still open.
- Stand-and-shoot (#54) — fires at charger before melee.
- Two-sided shooting engagements with simultaneous return (#40).
- Line of sight / closest-target enforcement (#56).

## Board state after

Open issues (suggested sequencing):
1. **#40** — v17 shooting engagements: simultaneous return fire + winner/loser retreat (natural next, same shape as #55)
2. **#56** — LoS + closest-target (Euclidean + #55 done, unblocked)
3. **#54** — Stand and Shoot (small, depends on #40)
4. **#45–#51, #57** — independent mediums
5. **#58** — Terrain system (large)
6. **#59** — Scenario system (large)
7. **#62** — DT retreat (depends on #58)
8. **#42** — Cult audit (pre-deploy)

New since last checkpoint: **#64** (Pulumi/DO infra), **#65** (refactor large files), **#66** (beads evaluation), **#67** (roster export), **#68** (copy room code), **#69** (rules viewer exploration), **#70** (UI scaling + art pipeline).

## Next pickup

**#40 (return fire + shooting retreat)** — mirrors #55's bout structure for shooting. Defender returns fire simultaneously, winner/loser determined by unsaved wounds, loser retreats. Can reuse `_execute_retreat` and the post-engagement panic pattern.
