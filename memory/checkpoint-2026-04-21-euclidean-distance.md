# Checkpoint — 2026-04-21 — Euclidean Distance (#44)

**PR:** [#60](https://github.com/rpmcdougall/turnipsim/pull/60) on branch `feature/euclidean-distance`. **Merged.**
**Closes:** #44 (grid-vs-inches decision).

## What shipped

Replaced Manhattan distance (`abs(dx)+abs(dy)`) with Euclidean (`sqrt(dx²+dy²)`) across all range, movement, and command checks. Integer grid positions unchanged; 1 cell = 1 inch; only distance comparisons use floats.

**game_engine.gd:**
- New `_grid_distance(x1, y1, x2, y2) -> float` helper
- 12 Manhattan call sites replaced (command range, weapon range, movement, march, charge target/move, volley/charge valid-target checks, follower command range, objective capture, adjacent cell finder)
- Objective capture "within 1 inch" = Euclidean ≤ 1.0 (still orthogonal-only since √2 > 1)

**grid_draw.gd:**
- `_draw_range_diamond` → `_draw_range_circle` (cell fill via `dx²+dy² ≤ r²`, outline via `draw_arc`)
- `_enemy_cells_within` uses squared Euclidean

**battle.gd:** 2 client-side hint functions updated to match engine.

**Tests:** 3 new diagonal-specific tests that would fail under Manhattan but pass with Euclidean (command range, volley fire, march). 64 total engine tests, 19 type/ruleset tests, all passing.

## Design decisions

- **Charge adjacency stays orthogonal (4 cells, not 8)** — diagonal adjacency (√2 ≈ 1.41") is technically "in contact" but 4-directional is simpler. Revisit if gameplay demands it.
- **No pathfinding** — movement is still "any cell within range" regardless of obstacles. Terrain (#58) will need pathfinding; that's the right time to add it.
- **Circle outlines via `draw_arc`** with 64 segments — smooth enough at all zoom levels tested.

## Visually verified

Launched solo stack, confirmed:
- Yellow command-range circle around Made-Ready Snob
- Colored reach circles during order execution (cyan/orange/red)
- Circles render cleanly at default window size

## Also cleaned up

- Closed stale #34 (fixed in PR #35 but never closed)
- Updated `docs/wiki/Manual-Testing-Guide.md` — diamond → circle references

## Board state after

- **#44** — Closed
- **#34** — Closed (was stale)
- **#52** (panic subsystem) — Next up, foundational keystone

## Next pickup

**#52 Panic test subsystem** — `_panic_test()` function, Fearless gate, wire into charge. Keystone for combat realism.
