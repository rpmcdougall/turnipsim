# Checkpoint — 2026-04-22 — Session Wrap

Big session. Three combat subsystems shipped, multiple follow-up issues
filed, #56 pre-scoped but not started. Session ends on `main` at
`13559fc`, branch tree clean.

## PRs merged this session

| PR | Topic | Issue |
|---|---|---|
| #71 | Two-sided melee bouts with counter-attack | #55 |
| #73 | Retreat distance fix: `D6 + 2" × panic tokens` | (#53 correction) |
| #75 | Simultaneous shooting engagements with return fire | #40 |

Combat engine now rules-accurate for: panic tests, retreat (D6+2×tokens),
melee bouts with counter-attack, shooting engagements with return fire
and winner/loser retreat. 103 engine + 19 type = 122 tests passing.

## Issues filed this session

Most out-of-scope observations got their own issues per scope discipline:

- **#64** — Phase 6: Manage DigitalOcean droplet with Pulumi (free tier)
- **#65** — Refactor: split oversized files into cohesive modules
- **#66** — Tooling: evaluate beads as local issue tracker
- **#67** — Roster export: save built rosters to file
- **#68** — Lobby: click-to-copy room code
- **#69** — Explore: in-app rules viewer
- **#70** — Explore: UI scaling + art asset pipeline
- **#72** — Ruleset-version agility audit (pre-v19)
- **#74** — Battle UI: powder smoke indicator

## Stable decisions reaffirmed / made this session

- **Pre-rolled dice pool convention** — charge/shooting paths use a
  server-rolled `dice_results: Array` passed into the engine, with
  offset-based consumption and a returned `dice_used` count. **Not**
  `Callable` injection. Decision logged in all three combat checkpoints;
  any future engine work should follow this pattern.
- **`MELEE_MAX_BOUTS = 3`** with draw-on-cap (no retreat). Can tune later.
- **Retreat distance = `retreat_die + 2 × panic_tokens`** per v17 p.20
  (confirmed against the PDF). `_execute_retreat(state, unit_id, retreat_die)`.
- **Shooting engagement panic** = per-hit only (no bilateral +1 like melee).
- **Return fire inaccuracy_mod = 0** — volley-fire `-1` applies only to
  the declared order, not the response.

## Pre-work already done for #56 (LoS + closest-target)

**Scope locked; no code yet.** The scoping conversation is preserved here
so the next session can skip re-scoping.

**Proposed shape:**
- `_has_line_of_sight(state, from_x, from_y, to_x, to_y) -> bool` — supercover
  walk along the line; any alive **non-Snob** unit strictly between
  endpoints blocks. Snobs never block (v17 p.5). Pure function.
- `_find_shooting_targets(state, shooter) -> Array[UnitState]` — alive +
  enemy + in range + LoS. Used by fizzle gates and closest-target check.
- `_is_valid_shooting_target(state, shooter, target) -> String` — returns
  empty string on legal, error string on illegal. Closes on: exists,
  alive, enemy, in range, LoS, and (unless `sharpshooters`) is among the
  tied-closest enemies.
- **Callers:** `_execute_volley_fire`, `_execute_move_and_shoot` (LoS from
  post-move position), `_execute_charge` (LoS required, closest-target
  does NOT apply to charges per the issue). Fizzle gates updated to use
  the same helpers.

**Locked design calls:**
1. Both endpoints excluded from blocker check.
2. Tied-closest is permissive (any tied target legal).
3. Supercover discretization (every touched cell checked), not Bresenham.
4. Terrain LoS deferred to #58.
5. Chaff = Sharpshooters bypass closest-target only, still need LoS.

**Pending on next pickup:**
- Branch `feature/line-of-sight`.
- Implement the three helpers.
- Wire into callers.
- Tests: LoS blocked by Follower, not blocked by Snob, not blocked by
  dead unit, endpoints don't block, closest-target violation rejected,
  tied-closest both legal, sharpshooters bypass closest, LoS from
  post-move position for move_and_shoot, charge LoS check.
- Housekeeping: Manual-Testing-Guide row, checkpoint.

## Session side quest — skills files on desktop

User generated two markdown files on the desktop for starting a personal
Claude Code skills repo:
- `C:\Users\rpmcd\Desktop\skill-opportunities.md` — 10 skill ideas ranked.
- `C:\Users\rpmcd\Desktop\skill-opportunities-briefing.md` — full context
  brief for any implementing agent.

Not relevant to sim work; logged for continuity.

## Board state after session

Phase 4 combat engine is close to rules-complete. Remaining open
mechanics issues:

1. **#56** — LoS + closest-target (pre-scoped above) **← NEXT PICKUP**
2. **#54** — Stand and Shoot (depends on LoS, sibling to #56)
3. **#45–#51, #57** — independent medium-sized mechanics
4. **#58** — Terrain system (large, blocks #62 DT tests)
5. **#59** — Scenario system (large)
6. **#38** — Remaining v17 rules-accuracy audit items
7. **#42** — Cult rules audit (pre-deploy)

Out-of-mechanics: #64–#70, #72, #74 all available.

## Next pickup

Pick up at **#56 (LoS + closest-target)** — pre-work done, locked,
unblocked. Scoping section above is your re-entry point; no re-scoping
needed.
