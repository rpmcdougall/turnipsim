# Checkpoint: Phases 1-3 Complete (2026-04-17)

## Session Summary

Completed full implementation of Phases 1, 2, and 3 of the Turnip28 Simulator multiplayer game.

## What Was Built

### Phase 1: Game Data Layer
**Commit:** `9b9b2c1` (merged to main)

- **types.gd:** RefCounted data classes (Stats, Weapon, Mutation, Unit) with serialization and effective stat calculation
- **ruleset.gd:** JSON loader with comprehensive validation, fails fast on malformed data
- **army_roller.gd:** Army generation with dependency-injected dice for deterministic testing
- **mvp.json:** First ruleset with 3 archetypes (Toff, Chuff, RootBeast), 2 mutation tables each, 7 weapons, composition rules
- **test_runner.gd:** 19 passing tests covering types, ruleset loading, army rolling

**Key Decision:** Dependency injection for dice (`roll_d6: Callable`) enables deterministic testing and server-authoritative randomness.

**Validation:** All tests pass headless. Same dice sequence produces identical army.

---

### Phase 2: Army Rolling UI
**Commit:** `ab201f5` (merged to main)

- **test_roll.tscn:** ScrollContainer UI displaying rolled armies
- **test_roll.gd:** Loads MVP ruleset, rolls on scene load, displays units with stats/weapons/mutations
- **Re-roll button:** Generates new random armies on demand
- **Navigation:** Main menu → TestRoll → Back to menu

**Validation:** User can run client, click button, see random army, and re-roll.

---

### Phase 3: ENet Networking & Lobby
**Commit:** `91047e5` (merged to main via PR #9)

**Server:**
- **server_main.gd:** ENet server on port 9999, handles peer connections/disconnections (max 32 clients)
- **room_manager.gd:** Room creation/joining with 6-char codes (excludes I/O/0/1 for clarity), player tracking, ready status
- **network_server.gd:** RPC layer (create_room, join_room, set_ready) with state broadcasts

**Client:**
- **lobby.tscn:** Multi-panel UI (connection, room management, in-room view)
- **lobby.gd:** ENet client connection, RPC handlers, real-time player list updates
- **Navigation:** Main menu → Multiplayer Lobby → Connect → Create/Join Room → Ready toggle

**Features:**
- 6-char room codes generated server-side
- Real-time player list synchronization
- Ready/unready toggle broadcasts to all clients in room
- Graceful disconnect handling and room cleanup

**Validation:** Two clients connect to local server, share room code, see each other's names, toggle ready status.

---

## CI/CD Improvements

### GitHub Actions Setup
**Commit:** `c246693` (on main)

- Workflow triggers on PR to main and push to main
- Downloads Godot 4.6.2 headless
- Runs all test suites (Phase 1, 2, 3)

### CI Fixes
**Commits:** `1c9de1b`, `25afef3`, `b026c7d` (on feature branch, merged)

**Issue:** Tests failed in CI due to `--script` mode not loading project context, causing `class_name` declarations to be unavailable.

**Solution:**
- Use `--import` to load project assets first
- Use `-s` flag instead of `--script` to load project context
- Removed unnecessary preloads from test files

**Result:** All tests now pass in CI (19/19 Phase 1, UI validation, Phase 3 scenes).

---

## Workflow Improvements

### Feature Branch + PR Process
**Commit:** `3803d96` (on main)

- Created `CONTRIBUTING.md` with feature branch workflow
- Phase 3 developed on `feature/phase-3-networking` branch
- PR #9 created, CI validated, squash-merged to main
- Branch auto-deleted after merge

Going forward: All phases developed on feature branches, merged via PR after CI passes.

---

## GitHub Project Board

Created issues retroactively for Phases 2 and 3:
- Issue #6: Phase 2 — Army rolling UI (Done)
- Issue #7: Phase 3 — ENet server (Done)
- Issue #8: Phase 3 — Lobby UI (Done)

Phase 1 issues #1-5 already existed and marked Done.

**Board Status:** All 8 items (Phases 1-3) marked as Done in "TurnipSim v0.1" project.

---

## Technical Decisions Log

1. **Single Godot project:** Server/client mode determined at runtime via `--server` flag, not separate projects
2. **Pure game/ folder:** No Node dependencies in `game/`, only RefCounted classes
3. **Data-driven rulesets:** JSON files define archetypes/mutations/weapons, not hardcoded GDScript
4. **Dependency injection for dice:** Enables deterministic tests and server-authoritative rolls
5. **ENet over UDP port 9999:** Standard multiplayer setup, up to 32 concurrent clients
6. **6-char room codes:** Uppercase letters/numbers excluding I/O/0/1 for clarity
7. **No client-side prediction:** Server is authority, clients are dumb renderers (fine for turn-based)

---

## Files Created/Modified

### Core Implementation
- `godot/game/types.gd` (168 lines)
- `godot/game/ruleset.gd` (226 lines)
- `godot/game/army_roller.gd` (199 lines)
- `godot/game/rulesets/mvp.json` (250 lines)
- `godot/server/server_main.gd` (44 lines)
- `godot/server/room_manager.gd` (186 lines)
- `godot/server/network_server.gd` (98 lines)
- `godot/client/scenes/test_roll.gd` (102 lines)
- `godot/client/scenes/lobby.gd` (242 lines)

### Tests
- `godot/tests/test_runner.gd` (19 tests)
- `godot/tests/test_ui_instantiate.gd`
- `godot/tests/test_phase3_scenes.gd`
- `godot/tests/demo_army_roll.gd` (demo script)

### Documentation
- `phase1-review.md` (comprehensive review with recommendations)
- `PHASE2_TESTING.md` (manual testing instructions)
- `PHASE3_TESTING.md` (2 clients + server test procedure)
- `CONTRIBUTING.md` (feature branch workflow)

### CI/CD
- `.github/workflows/tests.yml` (GitHub Actions workflow)

---

## Known Issues / Tech Debt

None blocking. Minor notes from Phase 1 review:
1. Stat modifiers can push values negative (acceptable - just makes units bad)
2. Weapon references in `allowed_weapons` not validated against weapons array (graceful degradation)
3. Mutation table selection always uses first N tables (could randomize in future)

---

## Next Phase: Phase 4

**Phase 4: Battle Gameplay (Server-Authoritative)**

Remaining work:
1. Pure engine functions in `game_engine.gd`: move, shoot, charge, end turn
2. Engine tests (deterministic, no networking)
3. `Battle.tscn` client UI: TileMap grid, unit sprites, click handling
4. Client → Server: `request_action` RPCs
5. Server → Client: `state_update` + `action_resolved` broadcasts
6. Action log, turn banner, active player indicator

**Checkpoint Goal:** Two clients play full networked game. State stays consistent.

---

## Session Stats

- **Duration:** ~2 hours
- **Commits:** 12 (across 3 phases)
- **Tests:** 19 passing (Phase 1) + scene validation
- **Lines of Code:** ~1,500 (implementation + tests)
- **PRs Merged:** 1 (PR #9)
