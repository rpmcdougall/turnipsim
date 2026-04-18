# Codebase Tour

A guided tour of the Turnip28 Simulator repository to help you navigate and understand the code structure.

## Repository Overview

```
turnipsim/
├── .github/              # GitHub-specific files
│   └── workflows/        # CI/CD automation
├── docs/                 # Documentation
│   └── wiki/             # Developer wiki (you are here)
├── godot/                # Main Godot project
│   ├── game/             # Pure game logic
│   ├── server/           # Server-only code
│   ├── client/           # Client-only code
│   ├── autoloads/        # Singleton managers
│   └── tests/            # Automated tests
├── memory/               # Session checkpoints
└── rules_export/         # Turnip28 rulebook PDFs
```

## Key Files at Repo Root

### Documentation
- **CLAUDE.md** - Project overview, architecture decisions, phase status
- **MEMORY.md** - Current session state, quick reference
- **CONTRIBUTING.md** - Feature branch workflow, CI/CD
- **turnip28-sim-plan-godot.md** - Full roadmap (Phases 0-6)
- **README.md** - Project introduction

### Configuration
- **.gitignore** - Files excluded from git
- **.github/workflows/tests.yml** - CI configuration

## Godot Project (`godot/`)

### Entry Point

**godot/entry.tscn** and **godot/entry.gd**
- First scene loaded
- Detects server vs client mode
- Branches to appropriate main scene

```gdscript
if NetworkManager.is_server:
	get_tree().change_scene_to_file("res://server/server_main.tscn")
else:
	get_tree().change_scene_to_file("res://client/main.tscn")
```

**godot/project.godot**
- Godot project configuration
- Entry scene: `entry.tscn`
- Renderer: `gl_compatibility`
- Autoloads: NetworkManager

### Autoloads (`godot/autoloads/`)

**network_manager.gd** - Singleton for network state
- Detects server vs client mode (`--server` flag, `dedicated_server` feature)
- Stores connection state
- Tracks player seat assignment

```gdscript
# Access from anywhere
NetworkManager.is_server  # bool
NetworkManager.my_seat    # int (1 or 2)
```

### Game Logic (`godot/game/`)

**Pure RefCounted classes - No Node dependencies**

**types.gd** (~380 lines)
- `Stats` - Movement, Shooting, Combat, Resolve, Wounds, Save
- `Weapon` - Name, type, range, strength, AP
- `Mutation` - Name, table, effect description
- `Unit` - Full unit data (archetype, stats, mutations, weapon)
- `GameState` - Battle state (phase, turn, active_seat, units, log)
- `UnitState` - Runtime unit state (position, wounds, activation, death)
- `EngineResult` - Wrapper for engine function results

Each class has:
- `to_dict()` - Serialize to Dictionary
- `from_dict(data)` - Deserialize from Dictionary

**ruleset.gd** (~200 lines)
- Loads JSON rulesets from `game/rulesets/`
- Validates structure
- Provides accessors for archetypes, mutations, weapons
- Returns clear errors on malformed data

**army_roller.gd** (~150 lines)
- `roll_army(ruleset: Ruleset, roll_d6: Callable) -> Array[Unit]`
- Generates armies per ruleset composition rules
- Dependency injection for dice (deterministic testing)
- Returns 5-10 units with stats, weapons, mutations

**game/rulesets/mvp.json**
- Minimal viable ruleset
- 3 archetypes: Toff (leader), Chuff, Root Beast
- 2-3 mutation tables per archetype
- Weapon pool (melee + ranged variants)

### Server (`godot/server/`)

**server_main.gd** and **server_main.tscn** (~100 lines)
- Bootstrap dedicated server
- Create ENet server on port 9999 (UDP)
- Max 32 clients
- Handles peer connected/disconnected events

**room_manager.gd** (~200 lines)
- Generate 6-char room codes (ABCDEF, excludes I/O/0/1)
- Track rooms: `Dictionary[String, RoomState]`
- `create_room(peer_id, display_name) -> String` (returns code)
- `join_room(peer_id, display_name, code) -> bool`
- Ready status management
- Handle peer disconnections (clean up rooms)

**network_server.gd** (~360 lines)
- **RPC handlers** for client requests:
  - `create_room(display_name)`
  - `join_room(code, display_name)`
  - `set_ready(ready: bool)`
  - `submit_army(army_data: Array)` (Phase 3b)
  - `request_action(action_data: Dictionary)` (Phase 4)

- **Broadcast RPCs** to clients:
  - `_send_room_joined(room_data)`
  - `_send_peer_joined(player_data)`
  - `_send_player_ready_changed(peer_id, ready)`
  - `_send_army_submitted(peer_id, army_size)`
  - `_send_game_started(game_state)`
  - `_send_action_resolved(action, result)`
  - `_send_state_update(state_data)`
  - `_send_game_ended(winner_seat, reason)`

- **Game management:**
  - `active_games: Dictionary` - room_code → GameState
  - `_start_game(room)` - Initialize game state when both armies submitted
  - `_initialize_game_state(room)` - Convert armies to UnitStates

**game_engine.gd** (~644 lines)
- **Pure static functions** - all game logic
- **Constants**: BOARD_WIDTH=48, BOARD_HEIGHT=32, deployment zones

- **Placement phase:**
  - `place_unit(state, unit_id, x, y) -> EngineResult`
  - `confirm_placement(state) -> EngineResult`

- **Combat phase:**
  - `move_unit(state, unit_id, x, y) -> EngineResult`
  - `resolve_shoot(state, attacker_id, target_id, dice) -> EngineResult`
  - `resolve_charge(state, attacker_id, target_id, dice) -> EngineResult`
  - `end_activation(state, unit_id) -> EngineResult`
  - `end_turn(state) -> EngineResult`

- **Victory:**
  - `check_victory(state) -> Dictionary` (winner, reason)

- **Helpers:**
  - `_clone_state(state)` - Immutable state updates

### Client (`godot/client/`)

**main.tscn** and **main.gd**
- Main menu scene
- Buttons: "Army Roller Demo", "Multiplayer Lobby", "Quit"
- Entry point for client mode

**scenes/test_roll.tscn** and **test_roll.gd** (~120 lines)
- Army roller demonstration (Phase 2)
- Roll army button
- Re-roll button
- Displays units in ScrollContainer
- Unit panels show: name, archetype, stats, weapon, mutations
- Independent of networking (local-only)

**scenes/lobby.tscn** and **lobby.gd** (~300 lines)
- Multiplayer lobby UI (Phase 3 + 3b)
- **Connection panel:**
  - Server IP input (default: 127.0.0.1:9999)
  - Player name input
  - Connect button
- **Room management panel:**
  - Create room button
  - Join room (code input)
- **In-room panel:**
  - Player list (seat 1, seat 2)
  - Ready checkbox
  - Roll Army button (Phase 3b)
  - Submit Army button (Phase 3b)
  - Army display (ScrollContainer)
- **RPC handlers:**
  - `_send_room_joined()`, `_send_peer_joined()`, etc.
  - `_send_army_submitted()`, `_send_game_started()`

**scenes/battle.tscn** and **battle.gd** (TODO: Phase 4 client)
- Battle UI scene (not yet created)
- Will include TileMap, unit sprites, action panels

### Tests (`godot/tests/`)

**test_runner.gd** (~400 lines, 19 tests)
- Phase 1 game logic tests
- Ruleset loading, army rolling, determinism
- Run with: `godot --headless -s tests/test_runner.gd`

**test_game_engine.gd** (~577 lines, 38 tests)
- Phase 4 engine tests
- Placement, movement, shooting, melee, turns, victory
- 28/34 currently passing
- Run with: `godot --headless -s tests/test_game_engine.gd`

**test_ui_instantiate.gd** (~50 lines)
- Validates all client scenes load without errors
- Quick smoke test for UI

**test_phase3_scenes.gd** (~100 lines)
- Validates Phase 3 networking scenes
- Lobby, server_main instantiation

**demo_army_roll.gd** (~80 lines)
- Not an automated test
- Manual demo of army rolling
- Used for development/debugging

## Memory Files (`memory/`)

**checkpoint-YYYY-MM-DD-<topic>.md**
- Deep archives of significant sessions
- What was implemented, decisions made, commits
- Created after completing phases or major work

**Example:** `checkpoint-2026-04-17-phase-3b-4.md` - Phase 3b + 4 implementation

## CI/CD (`.github/workflows/`)

**tests.yml**
- Runs on PR to main, push to main
- Downloads Godot 4.6.2 headless (Linux)
- Runs all test suites
- Fails PR if tests fail

## Git Branches

**main** - Stable, production-ready code

**feature/* branches:**
- `feature/phase-3-networking` (merged)
- `feature/phase-3b-4-battle` (current)

**Workflow:**
1. Branch from main: `git checkout -b feature/phase-x-name`
2. Develop with modular commits
3. Push: `git push -u origin feature/phase-x-name`
4. Create PR: `gh pr create`
5. Merge after approval
6. Delete branch

## Common Code Paths

### Scenario 1: Client Connects to Server

1. Client launches → `entry.gd` → `client/main.tscn`
2. User clicks "Multiplayer Lobby" → `client/scenes/lobby.tscn`
3. User enters IP, clicks "Connect"
4. `lobby.gd` calls `NetworkManager.connect_to_server(ip, port)`
5. Server accepts connection → `server_main.gd` handles `peer_connected`

### Scenario 2: Creating a Room

1. Client clicks "Create Room"
2. `lobby.gd` calls `create_room.rpc_id(1, display_name)`
3. Server `network_server.gd` receives RPC
4. `room_manager.create_room(peer_id, display_name)` generates code
5. Server calls `_send_room_joined.rpc_id(peer_id, room_data)`
6. Client `lobby.gd` receives `_send_room_joined()`, displays in-room panel

### Scenario 3: Rolling and Submitting Army

1. Client clicks "Roll Army"
2. `lobby.gd` calls `ArmyRoller.roll_army(ruleset, func(): return randi_range(1, 6))`
3. Army displayed in ScrollContainer
4. Client clicks "Submit Army"
5. `lobby.gd` calls `submit_army.rpc_id(1, army_data)`
6. Server validates, stores, broadcasts `_send_army_submitted`
7. When both submitted → server calls `_start_game(room)`
8. Server broadcasts `_send_game_started(game_state)`
9. Clients transition to `battle.tscn`

### Scenario 4: Moving a Unit in Battle

1. Client clicks unit → select
2. Client clicks destination tile
3. `battle.gd` calls `request_action.rpc_id(1, {type: "move", unit_id, x, y})`
4. Server validates turn ownership, range
5. Server calls `GameEngine.move_unit(state, unit_id, x, y)`
6. Server updates `active_games[room_code]` with new state
7. Server broadcasts `_send_action_resolved()` and `_send_state_update()`
8. Clients re-render units at new positions

## Finding Things Quickly

### "Where is the combat math?"
→ `godot/server/game_engine.gd:resolve_shoot()` and `resolve_charge()`

### "Where are room codes generated?"
→ `godot/server/room_manager.gd:_generate_room_code()`

### "Where is army generation logic?"
→ `godot/game/army_roller.gd:roll_army()`

### "Where are data classes defined?"
→ `godot/game/types.gd`

### "Where are network RPCs handled?"
→ `godot/server/network_server.gd` (server-side)
→ `godot/client/scenes/lobby.gd` (client-side)

### "Where are tests?"
→ `godot/tests/test_runner.gd` (Phase 1)
→ `godot/tests/test_game_engine.gd` (Phase 4)

### "What's the current phase status?"
→ `MEMORY.md` (quick reference)
→ `CLAUDE.md` (official status)

### "What was done in the last session?"
→ `memory/` directory, sort by date, read latest checkpoint

## See Also

- [Project Setup](Project-Setup.md) - Getting the project running
- [Architecture Overview](Architecture-Overview.md) - System design
- [Development Process](Development-Process.md) - Workflow and conventions
