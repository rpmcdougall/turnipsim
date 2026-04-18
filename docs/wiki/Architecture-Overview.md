# Architecture Overview

High-level system design and architectural decisions for Turnip28 Simulator.

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Client (Godot)                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │  Main    │  │  Lobby   │  │  Battle UI       │  │
│  │  Menu    │  │  Scene   │  │  (TileMap+Units) │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│         │              │                │            │
│         └──────────────┴────────────────┘            │
│                        │                             │
│                 NetworkManager (autoload)            │
│                        │                             │
└────────────────────────┼─────────────────────────────┘
                         │ ENet (UDP)
                         │ Port 9999
┌────────────────────────┼─────────────────────────────┐
│                 NetworkManager                       │
│                        │                             │
│         ┌──────────────┴────────────────┐            │
│         │                               │            │
│  ┌──────────────┐              ┌──────────────┐     │
│  │ NetworkServer│              │ RoomManager  │     │
│  │  (RPC Layer) │◄────────────►│ (Room State) │     │
│  └──────────────┘              └──────────────┘     │
│         │                                            │
│         ▼                                            │
│  ┌──────────────┐                                    │
│  │ GameEngine   │  Pure functions                   │
│  │ (Battle      │  (state, action, dice) → state   │
│  │  Logic)      │                                    │
│  └──────────────┘                                    │
│                                                      │
│                    Server (Godot --server)          │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              Shared Game Logic (game/)              │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │  Types   │  │ Ruleset  │  │  ArmyRoller      │  │
│  │ (Data)   │  │ (JSON)   │  │  (Generation)    │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│                                                      │
│  Pure RefCounted classes - No Node dependencies    │
└─────────────────────────────────────────────────────┘
```

## Key Architectural Decisions

### 1. Single Project, Runtime Mode Split

**Decision:** One Godot project, mode determined at runtime

**Rationale:**
- Share game logic (`game/` folder) between client and server
- No code duplication for rules, types, army generation
- Simplifies testing (can run both modes from same codebase)

**Implementation:**
```gdscript
# entry.gd
if NetworkManager.is_server:
	get_tree().change_scene_to_file("res://server/server_main.tscn")
else:
	get_tree().change_scene_to_file("res://client/main.tscn")
```

Mode detection:
- `--server` CLI flag → server mode
- `dedicated_server` feature tag → server mode
- Otherwise → client mode

### 2. Pure Game Logic Layer

**Decision:** `game/` folder contains only RefCounted classes

**Rationale:**
- Testable without scene tree
- Usable from both client and server
- Deterministic (no hidden state in Nodes)
- Easy to reason about (pure functions)

**Constraints:**
- No `extends Node` or `extends Control`
- No `_ready()`, `_process()`, or lifecycle methods
- No signals (use return values)
- No direct scene access

**Example:**
```gdscript
# game/types.gd - Pure data class
class Stats extends RefCounted:
	var movement: int = 0
	var shooting: int = 0
	# ... no Node dependencies

# server/game_engine.gd - Pure static functions
static func move_unit(state: GameState, unit_id: String, x: int, y: int) -> EngineResult:
	# Pure function: same inputs → same outputs
	var new_state = _clone_state(state)
	# ... modify new_state
	return EngineResult.success(new_state)
```

### 3. Dependency Injection for Randomness

**Decision:** Inject `roll_d6: Callable` instead of calling `randi()`

**Rationale:**
- Enables deterministic testing (provide fixed dice sequence)
- Server controls all randomness (client can't cheat)
- Reproducible bugs (can replay with same seed)

**Implementation:**
```gdscript
# ArmyRoller usage
func roll_army(ruleset: Ruleset, roll_d6: Callable) -> Array[Unit]:
	var dice_result = roll_d6.call()  # Injected randomness
	# ... use dice_result

# Production use (server)
var army = ArmyRoller.roll_army(ruleset, func(): return randi_range(1, 6))

# Test use (deterministic)
var dice_sequence = [4, 2, 6, 3, 5, 1]
var index = 0
var mock_dice = func():
	var result = dice_sequence[index]
	index += 1
	return result
var army = ArmyRoller.roll_army(ruleset, mock_dice)
```

### 4. Server-Authoritative Gameplay

**Decision:** All game state lives on server, clients are thin UIs

**Rationale:**
- Prevents cheating (client can't modify state)
- Simpler client code (just render + send inputs)
- Turn-based gameplay (latency not critical)
- Easy to implement (no client prediction needed)

**Flow:**
1. Client sends action request: `request_action.rpc_id(1, {type: "move", ...})`
2. Server validates, updates state, rolls dice if needed
3. Server broadcasts new state: `_send_state_update.rpc_id(peer_id, state_dict)`
4. Clients re-render based on new state

**Trade-offs:**
- ✅ Cheat-proof
- ✅ Simple client logic
- ✅ Centralized game logic
- ❌ Network latency affects responsiveness
- ❌ Can't play offline (requires server)

### 5. Data-Driven Rulesets

**Decision:** Rulesets are JSON files, not GDScript code

**Rationale:**
- Non-programmers can create new rulesets
- Easy to version and distribute
- Engine logic is singular, data varies
- Can load community rulesets at runtime

**Format:**
```json
{
	"name": "MVP Ruleset",
	"version": "1.0.0",
	"archetypes": [
		{
			"name": "Toff",
			"category": "leader",
			"base_stats": { "movement": 6, "shooting": 4, ... },
			"mutation_tables": ["toff_mutations"],
			"weapon_pool": ["musket", "sword", "pistol"]
		}
	],
	"mutations": [...],
	"weapons": [...]
}
```

### 6. Immutable State Updates

**Decision:** Game engine clones state instead of mutating

**Rationale:**
- Prevents accidental mutations
- Easy to implement undo/replay
- Simplifies debugging (can compare states)
- Thread-safe (if we add threads later)

**Implementation:**
```gdscript
static func move_unit(state: GameState, unit_id: String, x: int, y: int) -> EngineResult:
	var new_state = _clone_state(state)  # Deep copy
	var unit = _find_unit(new_state, unit_id)
	unit.x = x
	unit.y = y
	return EngineResult.success(new_state)  # Return new state

static func _clone_state(state: GameState) -> GameState:
	return GameState.from_dict(state.to_dict())  # Simple, correct
```

### 7. Room-Based Multiplayer

**Decision:** 6-character room codes instead of matchmaking

**Rationale:**
- Simple to implement
- No server-side matchmaking logic needed
- Players control who they play with
- Works for small player base
- Easy to share codes (Discord, voice, etc.)

**Implementation:**
```gdscript
# RoomManager generates codes: ABCDEF (excludes I, O, 0, 1)
var code = _generate_room_code()  # e.g., "XYZ789"

# Client creates or joins
create_room.rpc_id(1, display_name)
join_room.rpc_id(1, code, display_name)
```

## Component Responsibilities

### Client (`client/`)

**Responsibilities:**
- Render game state (TileMap, unit sprites, UI panels)
- Capture user input (mouse clicks, button presses)
- Send action requests to server
- Display error messages and feedback

**Does NOT:**
- Validate actions (server does this)
- Calculate combat results
- Manage game state
- Roll dice

### Server (`server/`)

**Responsibilities:**
- Accept ENet connections on port 9999
- Manage rooms (create, join, ready system)
- Store active game states per room
- Validate action requests
- Execute game engine logic
- Roll dice for combat
- Broadcast state updates to all clients
- Detect victory conditions

**Does NOT:**
- Render graphics
- Handle user input (receives RPCs)
- Store persistent data (in-memory only for MVP)

### Game Logic (`game/`)

**Responsibilities:**
- Define data structures (Stats, Unit, GameState, etc.)
- Load and validate ruleset JSON
- Generate armies (ArmyRoller)
- Execute pure game engine functions (placement, movement, combat)
- Calculate effective stats (base + mutations)

**Does NOT:**
- Access network
- Render graphics
- Store state (pure functions, stateless)
- Roll dice (injected as parameter)

## Network Protocol

### Connection Flow

```
Client                          Server
  │                               │
  │─────── connect to :9999 ──────►│
  │◄────── connected ──────────────│
  │                               │
  │─────── create_room(name) ─────►│
  │◄────── _send_room_joined ──────│
  │                               │
```

### Game Flow

```
Client 1            Server              Client 2
  │                   │                    │
  │── submit_army ───►│◄─── submit_army ───│
  │                   │                    │
  │◄─ _send_game_started ──────────────────┤
  │                   │                    │
  │─ request_action ─►│                    │
  │  (place_unit)     │                    │
  │                   │                    │
  │◄─────────────── _send_action_resolved ─┤
  │◄─────────────── _send_state_update ────┤
  │                   │                    │
```

See [RPC Protocol](RPC-Protocol.md) for full message format reference.

## Directory Structure

```
godot/
├── entry.tscn              # Entry point (mode detection)
├── project.godot           # Godot project config
│
├── autoloads/              # Singleton managers
│   └── network_manager.gd  # Mode detection, connection state
│
├── game/                   # Pure game logic (RefCounted only)
│   ├── types.gd            # Data classes
│   ├── ruleset.gd          # JSON loader
│   ├── army_roller.gd      # Army generation
│   └── rulesets/
│       └── mvp.json        # MVP ruleset
│
├── server/                 # Server-only code
│   ├── server_main.gd      # ENet server bootstrap
│   ├── room_manager.gd     # Room creation/joining
│   ├── network_server.gd   # RPC handlers
│   └── game_engine.gd      # Battle logic
│
├── client/                 # Client-only code
│   ├── main.tscn           # Main menu
│   ├── scenes/
│   │   ├── lobby.tscn      # Lobby UI
│   │   ├── battle.tscn     # Battle UI
│   │   └── test_roll.tscn  # Army roller demo
│   └── (scripts attached to scenes)
│
└── tests/                  # Automated tests
    ├── test_runner.gd      # Phase 1 tests
    ├── test_game_engine.gd # Phase 4 tests
    └── ...
```

## Testing Strategy

### Unit Tests (Automated)
- **game/**: Pure function tests with mocked inputs
- **server/game_engine.gd**: Comprehensive engine logic tests
- Run headless, deterministic, fast

### Integration Tests (Manual)
- **Networking**: Server + 2 clients, manual flow testing
- **UI**: Godot editor, visual verification
- Documented in `PHASE<N>_TESTING.md`

### No End-to-End Automation (Yet)
- Godot headless can't render UI
- Manual testing required for client UI
- Future: Godot's UI testing framework or external tools

## Performance Considerations

### Optimized for Turn-Based

**Not critical:**
- Network latency (turn-based, not real-time)
- Frame rate (static board, minimal animation)
- Memory (small game states, ~10 units per side)

**Critical:**
- Determinism (same inputs → same outputs)
- Correctness (no bugs in combat math)
- Maintainability (clear code > clever code)

### Scalability

**Current MVP:**
- 32 max clients per server
- ~5-10 concurrent games
- In-memory state only (no persistence)

**Future scaling:**
- Add Redis for state persistence
- Horizontal scaling (multiple server processes)
- Load balancer for room assignment

## Security Considerations

### Server-Side Validation

**All client inputs must be validated:**
- Turn ownership (is it your turn?)
- Action validity (can you move there?)
- Range checks (within board bounds?)
- Rate limiting (prevent spam)

### No Client Trust

**Never trust client-sent data:**
- Dice rolls (server rolls)
- Combat results (server calculates)
- Victory detection (server checks)

### Room Codes

**Not cryptographically secure:**
- 6 characters = ~2 billion combinations
- Good enough for casual play
- Don't store sensitive data in rooms

## Future Architecture Changes

### Phase 5: Multiple Rulesets
- Lobby includes ruleset selector
- Server validates both clients use same ruleset
- More archetypes, mutations, weapons

### Phase 6: Persistence
- Save/load game states to disk
- Resume interrupted games
- Replay system

### Post-MVP: Advanced Features
- Spectator mode
- Replay viewer
- Tournament bracket system
- Elo rating system
- Persistent accounts

## See Also

- [Code Style Guide](Code-Style-Guide.md) - Implementation patterns
- [Testing Guidelines](Testing-Guidelines.md) - Testing pure functions
- [RPC Protocol](RPC-Protocol.md) - Network message reference
- [CLAUDE.md](../../CLAUDE.md) - Project conventions
