# Contributing to Turnip28 Simulator

Environment setup lives in [`docs/wiki/Project-Setup.md`](docs/wiki/Project-Setup.md). This file covers the contribution workflow: branching, testing, commits, PRs.

## Branching strategy

Feature-branch workflow. Every non-trivial change ships via PR against `main`.

```bash
git checkout main
git pull
git checkout -b feature/<short-topic>
# ... commits ...
git push -u origin feature/<short-topic>
gh pr create --base main --fill
```

**Naming:**

- `feature/<topic>` — new functionality
- `fix/<topic>` — bug fixes
- `docs/<topic>` — doc-only changes
- `chore/<topic>` — tooling, CI, etc.

Topic should be terse and descriptive. Prefer `feature/order-mechanics` over `feature/phase-4-part-3`.

## Local testing

Set `$GODOT` per platform (see `docs/wiki/Project-Setup.md`), then from the repo root:

```bash
cd godot/

# Automated suites — run both before pushing
$GODOT --headless -s tests/test_runner.gd         # 19 tests: types, ruleset, roster
$GODOT --headless -s tests/test_game_engine.gd    # 48 tests: order state machine, combat
```

For end-to-end multiplayer smoke tests, use the cross-platform launcher:

```bash
scripts/test-stack.sh          # headless server + 2 clients
scripts/test-stack.sh --solo   # server + 1 client
```

See [`docs/wiki/Manual-Testing-Guide.md`](docs/wiki/Manual-Testing-Guide.md) for the procedure.

## CI

`.github/workflows/tests.yml` runs on every PR to `main` and every push to `main`:

1. Download Godot 4.6.2 + import project
2. `test_runner.gd` — Phase 1 suite
3. `test_ui_instantiate.gd` — scene-loading smoke test
4. `test_phase3_scenes.gd` — lobby/networking scene smoke test

`.github/workflows/sync-wiki.yml` runs on push to `main` when `docs/wiki/**` changes: mirrors `docs/wiki/*.md` into `<repo>.wiki.git` so the GitHub Wiki stays in sync with the tracked docs.

> **Known gap:** CI does not currently run `test_game_engine.gd` (the 48-test engine suite). Worth adding as an additional step in `.github/workflows/tests.yml`.

## Commit format

Conventional commits with a `Co-Authored-By` trailer when Claude helped:

```
<type>(<scope>): <description>

[Optional body explaining WHY, not WHAT]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

**Types:** `feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`
**Scopes:** `engine`, `client`, `server`, `game`, `types`, `autoload`, `scripts`, etc.

One logical unit per commit. For multi-layer features, commit each layer as you validate it (engine → tests → server routing → client) rather than batching.

## Documentation source of truth

- Developer docs live in `docs/wiki/*.md` and auto-sync to the GitHub Wiki on merge to `main`.
- Architecture decisions and project conventions: `CLAUDE.md`.
- Phase plan: `turnip28-sim-plan-godot.md`.
- Session memory: `MEMORY.md` + `memory/checkpoint-YYYY-MM-DD-<topic>.md`.

Don't create root-level `PHASE<N>_TESTING.md` or similar — they drift. Put testing procedure in the wiki.

## Phase status

| Phase | Status |
|---|---|
| 0 — Scaffold | ✅ |
| 1 — Game data | ✅ |
| 2 — Army UI | ✅ (superseded by Phase 5b) |
| 3 — ENet + lobby | ✅ |
| 3b — Army submission | ✅ |
| 4 — Battle engine + v17 data model + v17 order mechanics | ✅ |
| 5 — Polish | 🚧 partial (victory conditions in progress) |
| 5b — Army submission UI | ✅ |
| 6 — Deploy | ⬜ |
| 7 — Cult mechanics | ⬜ |

See `MEMORY.md` for detail, or the [project board](https://github.com/users/rpmcdougall/projects/1).
