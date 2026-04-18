# Turnip28 Simulator - Project Memory

**Last Updated:** 2026-04-17
**Current Phase:** Phase 3b Complete, Phase 4 In Progress
**Feature Branch:** `feature/phase-3b-4-battle` (7 commits)

## Project Status

### Completed Phases ✅

- **Phase 0:** Project scaffold (commit d2f127b)
- **Phase 1:** Game data layer (commit 9b9b2c1)
  - types.gd, ruleset.gd, army_roller.gd, mvp.json
  - 19 passing tests
- **Phase 2:** Army rolling UI (commit ab201f5)
  - test_roll.tscn, re-roll functionality
- **Phase 3:** ENet networking & lobby (commit 91047e5)
  - Server: ENet on port 9999, room manager, network RPCs
  - Client: Lobby UI with connection, room management, ready system
- **Phase 3b:** Army submission flow (commits 5afc56a-5d4296b)
  - Battle state data structures (GameState, UnitState, EngineResult)
  - Lobby army rolling UI (reuses test_roll patterns)
  - Server submit_army RPC and game initialization
  - NetworkManager seat tracking

### Current Phase 🎯

**Phase 4: Battle Gameplay (Server-Authoritative)** - In Progress

**Completed (commits 96a2140-9c0a6a1):**
- ✅ `game_engine.gd`: 644 lines, all placement/combat functions (pure, tested)
- ✅ `test_game_engine.gd`: 38 comprehensive tests covering all engine logic
- ✅ `network_server.gd`: request_action RPC routing, dice rolling, victory checks
- ✅ Server-side integration complete and tested

**Remaining:**
- Battle.tscn scene structure (requires Godot editor)
- battle.gd client UI implementation (~300-400 lines)
- lobby.tscn UI updates (Roll/Submit Army buttons, ScrollContainer)
- End-to-end manual testing

**Checkpoint Goal:** Two clients play full networked game (placement + combat) against local server.

### Remaining After Phase 4

- **Phase 5:** Polish (win conditions, visual polish, 2nd ruleset)
- **Phase 6:** Export & deployment (VPS, binaries, systemd)

---

## Architecture Quick Reference

### Project Structure
```
godot/
├── game/           # Pure RefCounted logic (no Node deps)
│   ├── types.gd    # Stats, Weapon, Mutation, Unit + GameState, UnitState, EngineResult
│   ├── ruleset.gd  # JSON loader & validator
│   ├── army_roller.gd  # roll_army(ruleset, roll_d6)
│   └── rulesets/mvp.json
├── server/         # Server-only
│   ├── server_main.gd      # ENet server (port 9999)
│   ├── room_manager.gd     # Room creation, 6-char codes
│   ├── network_server.gd   # RPC layer (lobby + battle)
│   └── game_engine.gd      # ✅ Pure battle engine (644 lines)
├── client/         # Client-only
│   ├── main.tscn           # Main menu
│   ├── scenes/test_roll.tscn   # Army roller demo
│   ├── scenes/lobby.tscn   # Multiplayer lobby + army submission
│   └── scenes/battle.tscn  # TODO: Battle UI
└── tests/
    ├── test_runner.gd      # 19 tests (Phase 1)
    ├── test_ui_instantiate.gd
    ├── test_phase3_scenes.gd
    └── test_game_engine.gd # ✅ 38 tests (Phase 4)
```

### Key Design Decisions

1. **Single project, runtime mode split:** `--server` flag determines mode
2. **Pure game/ folder:** RefCounted only, no Node dependencies
3. **Data-driven rulesets:** JSON defines archetypes/mutations/weapons
4. **Dependency injection for dice:** `roll_d6: Callable` enables deterministic tests
5. **Server-authoritative:** No client-side prediction (turn-based, latency OK)
6. **6-char room codes:** Uppercase, excludes I/O/0/1
7. **Player-controlled placement:** Interactive deployment phase before combat
8. **Pure engine functions:** All game logic takes state + dice → new state

---

## Phase 3b + 4 Battle Flow

### Army Submission (Phase 3b)
1. Client rolls army locally using ArmyRoller
2. Client displays army in ScrollContainer
3. Client calls `submit_army.rpc_id(1, army_data)`
4. Server validates (5-10 units) and stores in room.players[].army
5. Server broadcasts `_send_army_submitted` to all players
6. When both submitted → server calls `_start_game()`
7. Server broadcasts `_send_game_started` with initial GameState
8. Clients transition to battle.tscn

### Battle Gameplay (Phase 4)

**Placement Phase:**
- Active player places units in deployment zone (seat 1: rows 28-31, seat 2: rows 0-3)
- Client: click grid → `request_action.rpc_id(1, {type: "place_unit", unit_id, x, y})`
- Server: validate zone, update state, broadcast
- Player confirms → switches to opponent or starts combat

**Combat Phase:**
- Alternating activations (each player activates all units before passing turn)
- Client: click unit → select, click grid → move OR click enemy → attack
- Actions: move, shoot (ranged), charge (melee), end_activation, end_turn
- Server: validate, roll dice for attacks, apply damage, check victory
- Victory: last unit standing

**RPC Flow:**
```
Client → Server: request_action({type, ...params})
Server: validate turn, apply GameEngine function, roll dice if needed
Server → All: _send_action_resolved(action, result)
Server → All: _send_state_update(new_state)
Server → All: _send_game_ended(winner, reason) if victory
```

---

## Testing

### Run Tests Locally
```bash
cd godot/

# Phase 1 tests (19 tests)
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_runner.gd

# Phase 4 engine tests (38 tests)
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_game_engine.gd

# UI instantiation tests
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_ui_instantiate.gd

# Phase 3 scene tests
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_phase3_scenes.gd
```

### Run Server
```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server
```

### Run Client
```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot
```

### CI
- GitHub Actions on PR to main, push to main
- Downloads Godot 4.6.2 headless
- Runs all test suites
- Uses `-s` flag (not `--script`) to load project context

---

## GitHub Project Board

**Project:** TurnipSim v0.1 (project #1)
- Phase 1: Issues #1-5 (Done)
- Phase 2: Issue #6 (Done)
- Phase 3: Issues #7-8 (Done)
- Phase 3b: Issues #10-13 (Done)
- Phase 4: Issues #14-16 (Done - server), #17-19 (Todo - client)
- Phase 5: Issues #20-22 (Todo)
- Phase 6: Issues #23-25 (Todo)

**Last Updated:** 2026-04-17 (all phases prepopulated)

---

## Important Files

### Documentation
- `CLAUDE.md` — Phase status, architecture overview
- `turnip28-sim-plan-godot.md` — Full roadmap (Phases 0-6)
- `CONTRIBUTING.md` — Feature branch workflow
- `phase1-review.md` — Phase 1 comprehensive review
- `PHASE2_TESTING.md` — Phase 2 manual test instructions
- `PHASE3_TESTING.md` — Phase 3 manual test instructions (2 clients + server)

### Checkpoints
- `memory/checkpoint-2026-04-17-phases-1-2-3.md` — Previous session
- `memory/checkpoint-2026-04-17-phase-3b-4.md` — This session

---

## Current Implementation Status

### Phase 3b (Complete)
- [x] GameState, UnitState, EngineResult data structures (types.gd:168-380)
- [x] Lobby army rolling UI (lobby.gd:_on_roll_army_button_pressed)
- [x] submit_army RPC handler (network_server.gd:74-103)
- [x] _initialize_game_state helper (network_server.gd:184-218)
- [x] NetworkManager.my_seat tracking (network_manager.gd:6-27)
- [x] _send_game_started RPC and transition (lobby.gd:295-302)

### Phase 4 Engine (Complete)
- [x] GameEngine constants (BOARD_WIDTH=48, BOARD_HEIGHT=32, deployment zones)
- [x] place_unit() - validates zones, bounds, occupation (game_engine.gd:25-103)
- [x] confirm_placement() - switches players or starts combat (game_engine.gd:108-156)
- [x] move_unit() - Manhattan distance validation (game_engine.gd:165-239)
- [x] resolve_shoot() - hit/wound/save cascade, range check (game_engine.gd:244-381)
- [x] resolve_charge() - melee, adjacency required (game_engine.gd:386-512)
- [x] end_activation() - marks unit done (game_engine.gd:516-560)
- [x] end_turn() - switches player, resets activation (game_engine.gd:564-603)
- [x] check_victory() - counts living units (game_engine.gd:612-634)
- [x] _clone_state() - immutable state updates (game_engine.gd:643-644)

### Phase 4 Server Integration (Complete)
- [x] active_games dictionary (network_server.gd:8)
- [x] request_action RPC routing (network_server.gd:184-282)
- [x] Dice rolling for attacks (network_server.gd:285-286)
- [x] Victory checking after actions (network_server.gd:251-255)
- [x] Broadcast flow: action_resolved + state_update + game_ended (network_server.gd:257-274)

### Phase 4 Client (Pending)
- [ ] battle.tscn scene structure (TileMap, panels, UI)
- [ ] battle.gd state rendering
- [ ] battle.gd input handling
- [ ] battle.gd RPC handlers

---

## Commands Quick Reference

**Important:** Godot executable path for macOS: `/Applications/Godot.app/Contents/MacOS/Godot`

```bash
# Run server
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server

# Run client
/Applications/Godot.app/Contents/MacOS/Godot project.godot

# Run tests
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_game_engine.gd

# Feature branch (current)
git checkout feature/phase-3b-4-battle

# Commit status
git log --oneline -10

# Push and create PR (when ready)
git push -u origin feature/phase-3b-4-battle
gh pr create --title "feat(phase3b+4): army submission and battle engine"
```

---

## Session Discipline Reminders

- [x] Update MEMORY.md before `/clear` or session end
- [x] Create checkpoint between phases
- [x] Keep MEMORY.md under 200 lines (archive old content to `memory/history.md`)
- [x] Update GitHub project board after phase completion
- [x] Use feature branches for all new phases
- [x] Make modular commits (one logical unit per commit)

---

**Last checkpoint:** memory/checkpoint-2026-04-17-phase-3b-4.md
**Next work:** battle.gd client UI OR run tests + manual integration testing
