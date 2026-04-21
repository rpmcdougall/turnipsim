# Checkpoint — 2026-04-20 — Roster builder (Phase 5b)

PR: [#37](https://github.com/rpmcdougall/turnipsim/pull/37) on branch `feature/roster-builder`. **Awaiting merge.** Closes #28.

## What shipped

Phase 5b replaces the "pick a random preset" button with a real roster-building UI. Delivered as four depth-first steps, three commits.

- **`4cf442b` — Named preset dropdown.** OptionButton listing Balanced Regiment / Cavalry Rush / Gunline / Melee Horde, with description shown under the unit list on selection. Cleaned up the debug-print scaffolding around the old `roll_army_button`.

- **`324ed32` — Custom roster builder.** New `RosterBuilder` class (`client/scenes/roster_builder.gd`, no .tscn — programmatic like the rest of the lobby UI). Behind a **[Preset] / [Custom]** mode toggle. Fixed v17 composition: 1 Toff with 2 follower slots, 2 Toadies with 1 each. Per-slot `OptionButton` pair for unit-type + equipment; equipment options filter to each unit's `allowed_equipment`. Rebuilds `Types.Roster` on every change and runs `Ruleset.validate_roster()` for live green/red feedback. Submit is gated on validity. Same commit wraps the in-room panel in a runtime `ScrollContainer` so Submit stays reachable at any window size (@onready paths are resolved before the restructure, so nothing breaks).

- **`067c2d9` — Preset pre-fill + per-slot stats.** Selecting a preset now also populates the builder's dropdowns, so switching to Custom starts from the preset rather than blank (`RosterBuilder.load_roster()` + metadata-based picker lookup). Compact stat line (`M/A/I/W/V + special rules`) appears under each slot once a unit type is picked — browsing without cross-referencing docs.

## Bugs found during the session

1. **Warning-as-error on inferred Variant.** `var display := eq_def.get("name", eq_key) if not eq_def.is_empty() else eq_key` — the conditional-expression typing inferred `Variant`, which the project treats as an error. That failed compilation on the whole `roster_builder.gd`, which meant `RosterBuilder.new()` errored with "Nonexistent function 'new' in base 'GDScript'" and Custom mode appeared as a blank panel. Fixed by splitting into an explicit-typed `if`/assign. **Pattern to watch:** any ternary with a `Dictionary.get(...)` branch.

2. **Autoload-in-headless-tests noise.** Attempted to fix the long-standing `Identifier not found: NetworkClient` error in `test_phase3_scenes.gd` by manually registering the autoload nodes. Didn't work — `NetworkClient` is a parser-level global that `godot -s <script>` mode never sets up, regardless of runtime node creation. Reverted. The test still reports PASSED because `load()` returns a usable scene resource despite the compile error, so the noise is cosmetic. If this ever blocks CI, the real fix is rewriting autoload call sites to `get_node("/root/NetworkClient")`.

## Rules-accuracy check during testing

User observed 2 Stump Guns validated as a legal roster and asked if that should be capped. Verified via v17 core rules: **no per-unit cap.** The rulebook literally jokes "Four Stump Guns are fun until you realise they can't move." Validator is correct; the only real limit is the practical one. Worth remembering — don't assume "feels wrong" = rules violation.

## Manual-testing path

Solo stack via `scripts/test-stack.sh --solo`. Verified:
- Each of the 4 presets selects, displays, and pre-fills the builder.
- Custom mode from scratch: all 4 slots filled with various combos validates green.
- Mid-flow tweaks update validation live; Submit toggles correctly.
- Scroll container keeps Submit reachable at normal window sizes.

**Not tested this session:** full 2-client game from Custom rosters end-to-end. PR notes it.

## Test counts

- `test_runner.gd`: 19 (unchanged)
- `test_game_engine.gd`: 55 (unchanged — builder is UI-only, no engine changes)

## Commits on branch

1. `4cf442b` feat(lobby): replace random-preset button with named-preset dropdown
2. `324ed32` feat(lobby): custom roster builder with live validation
3. `067c2d9` feat(lobby): preset pre-fill + per-slot stats

## What I'd do differently

- The inferred-Variant bug cost ~15 min of false-lead diagnostics (print statements, type assumptions) before reading the actual client log. Lesson: **for any "UI didn't appear" symptom, check the client log for script compile errors first** before assuming logic bugs. The log tells you immediately.
- The autoload-in-tests fix wasn't a big lift but also wasn't a small lift — ~5 min sunk before recognizing the parse-time constraint. Next time: verify the error is runtime vs parse-time before trying a runtime workaround.

## Next pickup

Per previous checkpoint's agreement, with #28 handed off for merge:

- **#21** — Phase 5 visual polish. Grid targeting visibility was flagged as friction on 2026-04-20; still the most-obvious next UX improvement for comfortable play-testing.
- **#36** — v17 objectives. Replaces the placeholder max-rounds tiebreak with real objective-based scoring. Self-contained mini-phase, rules-accuracy work.
- **Phase 6** — export presets + deploy (#23–25).

No dependencies between #21, #36, and Phase 6 — pick per session fit.
