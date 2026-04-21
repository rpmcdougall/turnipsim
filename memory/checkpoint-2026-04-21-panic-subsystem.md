# Checkpoint — 2026-04-21 — Panic Test Subsystem (#52)

**PR:** [#61](https://github.com/rpmcdougall/turnipsim/pull/61) on branch `feature/panic-subsystem`. **Merged.**
**Closes:** #52 (panic test subsystem — FOUNDATIONAL).

## What shipped

v17 core p.19 panic test implementation — the keystone mechanic for combat realism.

**`_panic_test(unit, panic_die, fearless_die) -> Dictionary`:**
- 0 tokens → auto-pass (skip test)
- Natural 1 → always pass
- D6 + panic_tokens ≥ 7 → fail
- Returns `{passed, roll, total, auto_passed, fearless_override, used_fearless}`
- Does NOT mutate unit state — caller applies consequences

**`_is_fearless(unit) -> bool`:**
- `"fearless"` in special_rules (Brutes)
- `"safety_in_numbers"` + model_count ≥ 8 (Fodder)
- Failed panic test + Fearless → second chance on 3+

**Charge integration:**
- Target takes panic test before melee resolves
- Pass → melee as normal
- Fail → +1 panic token, charger moves adjacent, melee skipped (interim until #53)
- Server rolls `panic_die` + `fearless_die` via network_server.gd

**Tests:** 11 new (8 unit tests for _panic_test/_is_fearless, 3 charge integration). 75 engine + 19 type = 94 total, all passing.

## Deferred items (explicit)

- **Bowel-Loosening Charge** (Bastards force reroll) — needs #49 reroll infra
- **Retreat movement** — needs #53; currently failed panic just skips melee
- **Panic from shooting loss** — needs #40 return fire
- **Panic from melee loss** — needs #55 two-sided bouts

## Design decisions

- Panic test is a pure function returning a result dict, not mutating state. Caller decides consequences. This keeps it reusable for shooting/melee panic tests later.
- Panic dice passed via `params` dict (not the combat `dice_results` array) to keep combat dice pool clean.
- Interim "target fled" behavior on failed panic: charger still moves adjacent, melee skipped. Not rules-accurate (target should physically retreat) but mechanically meaningful — panic matters right now.

## Board state after

- **#52** — Closed
- **#53** (retreat subsystem) — Next in sequence, depends on this
- **#55** (two-sided melee) — Depends on panic + retreat

## Next pickup

**#53 Retreat subsystem** — per the audit sequencing plan. Depends on panic (done). Unlocks melee loss retreat, shooting loss retreat, charge flee movement.
