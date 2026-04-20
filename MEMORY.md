# Turnip28 Simulator - Project Memory

**Last Updated:** 2026-04-18
**Current Phase:** Phase 4 Complete (Client UI)
**Feature Branch:** `feature/phase-3b-4-battle` (PR #26)

## Project Status

### Completed Phases ✅

- **Phase 0:** Project scaffold (commit d2f127b)
- **Phase 1:** Game data layer (commit 9b9b2c1) - 19 tests
- **Phase 2:** Army rolling UI (commit ab201f5)
- **Phase 3:** ENet networking & lobby (commit 91047e5)
- **Phase 3b:** Army submission flow (commits 5afc56a-5d4296b)
  - Battle state data structures (GameState, UnitState, EngineResult)
  - Lobby army rolling UI with submit functionality
  - Server submit_army RPC and game initialization
  - NetworkManager seat tracking

### Phase 4: Battle Gameplay ✅

**Status:** Implementation Complete (Awaiting Integration Testing)

**Server-side (commits 96a2140-9c0a6a1):**
- ✅ `game_engine.gd`: 644 lines, pure functions (placement, combat, turns, victory)
- ✅ `test_game_engine.gd`: 38 comprehensive tests (all passing)
- ✅ `network_server.gd`: request_action RPC routing, dice rolling, victory checks

**Client-side (commits d6c012f-a38be87):**
- ✅ `lobby.gd`: Programmatic army UI creation (_ensure_army_ui_exists)
- ✅ `battle.gd`: Complete battle UI with programmatic scene generation (432 lines)
  - State rendering, input handling, RPC communication
  - Placement phase, combat phase, action log
  - All RPC handlers including _send_error
- ✅ `battle.tscn`: Minimal scene (Control root + script)
- ✅ Issues #17, #18, #19 marked Done on project board

**Documentation:**
- ✅ `docs/wiki/Phase-4-UI-Programmatic.md` - Programmatic UI guide
- ✅ `docs/wiki/UI-Implementation-Verification.md` - Verification report
- ✅ `docs/wiki/Manual-Testing-Guide.md` - Local multiplayer smoke-test procedure

**Next:** End-to-end integration testing (2 clients + server, full game flow)

### Remaining Phases

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
│   └── game_engine.gd      # ✅ Pure battle engine (644 lines, 38 tests)
├── client/         # Client-only
│   ├── main.tscn           # Main menu
│   ├── scenes/test_roll.tscn   # Army roller demo
│   ├── scenes/lobby.gd     # ✅ Lobby + army submission
│   └── scenes/battle.gd    # ✅ Battle UI (programmatic, 432 lines)
└── tests/
    ├── test_runner.gd      # 19 tests (Phase 1)
    └── test_game_engine.gd # 38 tests (Phase 4)
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
9. **Programmatic UI:** All Phase 4 UI created in code (no manual Godot editor work)

---

## Battle Flow (Phase 3b + 4)

### Army Submission (Phase 3b)
1. Client rolls army locally using ArmyRoller
2. Client displays army in programmatically created ScrollContainer
3. Client calls `submit_army.rpc_id(1, army_data)`
4. Server validates (5-10 units) and stores in room.players[].army
5. When both submitted → server initializes GameState
6. Server broadcasts `_send_game_started` with initial state
7. Clients transition to battle.tscn

### Battle Gameplay (Phase 4)

**Placement Phase:**
- Active player places units in deployment zone (seat 1: rows 28-31, seat 2: rows 0-3)
- Client: click grid → `request_action.rpc_id(1, {type: "place_unit", ...})`
- Server: validate, update state, broadcast to all clients
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
```

### Manual Integration Test
```bash
# Terminal 1: Server
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server

# Terminal 2: Client 1
/Applications/Godot.app/Contents/MacOS/Godot project.godot

# Terminal 3: Client 2
/Applications/Godot.app/Contents/MacOS/Godot project.godot
```

**Test Flow:**
1. Client 1: Multiplayer Lobby → Create Room
2. Client 2: Multiplayer Lobby → Join Room (enter code)
3. Both: Roll Army → Submit Army
4. Verify transition to battle.tscn
5. Test placement phase (click grid to place units)
6. Test combat phase (select, move, attack)
7. Verify action log updates
8. Play until victory

---

## GitHub Project Board

**Project:** TurnipSim v0.1 (project #1)
- Phase 1: Issues #1-5 (Done)
- Phase 2: Issue #6 (Done)
- Phase 3: Issues #7-8 (Done)
- Phase 3b: Issues #10-13 (Done)
- Phase 4: Issues #14-19 (Done)
- Phase 5: Issues #20-22 (Todo)
- Phase 6: Issues #23-25 (Todo)

**Branch:** `feature/phase-3b-4-battle` (PR #26 open)
**Last Updated:** 2026-04-18

---

## Important Files

### Documentation
- `CLAUDE.md` — Phase status, architecture overview
- `turnip28-sim-plan-godot.md` — Full roadmap (Phases 0-6)
- `CONTRIBUTING.md` — Feature branch workflow
- `docs/wiki/Manual-Testing-Guide.md` — Manual integration test procedures

### Wiki (`docs/wiki/`)
- `Home.md` — Wiki navigation
- `Development-Process.md` — Workflow, branches, commits
- `Code-Style-Guide.md` — GDScript conventions
- `Testing-Guidelines.md` — Test procedures
- `Phase-4-UI-Programmatic.md` — Programmatic UI implementation guide
- `UI-Implementation-Verification.md` — Implementation verification report

### Checkpoints
- `memory/checkpoint-2026-04-17-phases-1-2-3.md` — Previous session
- `memory/checkpoint-2026-04-18-phase-4-ui.md` — This session (programmatic UI)

---

## Commands Quick Reference

```bash
# Godot executable path (macOS)
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

# Run server
$GODOT project.godot --server

# Run client
$GODOT project.godot

# Run tests
$GODOT --headless -s tests/test_game_engine.gd

# Git workflow
git status
git log --oneline -10
git push

# PR management
gh pr view 26
gh pr checks 26
```

---

## Session Discipline Reminders

- [x] Update MEMORY.md before `/clear` or session end
- [x] Create checkpoint between phases
- [x] Keep MEMORY.md under 200 lines (currently 184)
- [x] Update GitHub project board after phase completion
- [x] Use feature branches for all new phases
- [x] Make modular commits (one logical unit per commit)

---

**Last checkpoint:** `memory/checkpoint-2026-04-18-phase-4-ui.md`
**Next work:** Manual integration testing (full game flow) OR merge PR #26
