# Checkpoint — 2026-04-22 — Retreat Distance Fix

**Branch:** `fix/retreat-distance` (commit `696c877`). **Not yet merged.**
**Fixes:** latent bug in #53 — retreat distance missing the D6 component.

## What shipped

Retreat distance corrected from `2 × panic_tokens (min 1)` to the rules-accurate
`D6 + 2 × panic_tokens` per v17 core p.20 (same formula in v18 playtest).

- `_execute_retreat` signature: adds `retreat_die: int` parameter (pre-rolled
  1..6). Returns dict now includes `retreat_die` and `no_enemy` fields.
- Charge caller (`_execute_charge`) reads `params.retreat_die`, threads it
  through both the panic-fail retreat branch and the post-melee loser retreat.
- `network_server._send_execute_order_action` rolls retreat_die alongside
  panic_die/fearless_die for charge actions.

**Tests:** rewrote 5 retreat tests for the new formula, added 1 coverage case
(D6 alone with 0 panic tokens). 90 engine + 19 type = 109 passing.

## Context — how the bug got there

The original #53 PR explicitly chose `2 × tokens` and flagged the ambiguity in
its checkpoint:

> **No D6 in retreat distance** — rules reference says "2" per panic token",
> issue text was ambiguous ("D6 + 2" per panic token"). Went with simpler
> interpretation. Easy to add a die later if wrong.

Confirmed against the v17 PDF (p.20, "Retreating" step 1): the D6 is part of
the formula. Prior checkpoint's "easy to add later" note held up — single
signature change, ~5 tests updated.

## Not addressed here

- **v18 off-board rule** — if retreat pushes a unit over the board edge, v18
  removes models equal to panic token count instead of destroying the whole
  unit. v17 has no such rule; we stay v17-correct (full destruction). Tracked
  under **#72** (ruleset-version agility audit).
- **DT tests on retreat through Followers** — still deferred to #62 (terrain
  system #58).
- **Shooting engagement retreat** — #40 work will consume this corrected
  retreat as-is.

## Board state after

Retreat subsystem is now v17-accurate. #40 (shooting engagements) unblocked
and can assert retreat positions in its tests without adjusting later.

New issue filed this session: **#72** (ruleset-version agility audit, pre-v19).

## Next pickup

**#40 — v17 shooting engagements** (simultaneous return fire + winner/loser
retreat). Plan already locked: split `_resolve_shooting` into a
`_resolve_shooting_side` helper, new `_resolve_shooting_engagement` applies
wounds/smoke/panic post-computation, both callers route the loser through the
now-correct `_execute_retreat`.
