# Turnip 28 Multiplayer Simulator — MVP Build Plan (Godot 4)

## Project goal

Build a desktop multiplayer simulator for Turnip 28 where two players can:
1. Roll a random army following simplified Turnip 28 rules
2. Connect to a shared game room through a relay server
3. Play a skirmish battle with authoritative server-side state

Priority order: ship fast > low ops > no-install for friends > my existing stack.

## Stack decisions (locked in — do not re-litigate)

- **Engine:** Godot 4.6.2 stable
- **Language:** GDScript (NOT C# — GDScript is faster to iterate in, has zero build step, and the project doesn't need C#'s perf)
- **Networking:** Godot's built-in `MultiplayerAPI` over ENet (`ENetMultiplayerPeer`)
- **Architecture:** Authoritative dedicated server (headless export) + thin clients, both from the **same Godot project**; mode chosen at runtime
- **Renderer:** `gl_compatibility` (lightest option, no Vulkan requirement)
- **Server hosting:** Single cheap VPS (DigitalOcean/Hetzner, ~$5/month), Ubuntu, systemd service
- **Client distribution:** Direct download of exported binaries (Windows `.exe`, Mac `.app`, Linux binary) — no Steam, no installers
- **Persistence:** None for MVP. Server holds game state in memory. Games disappear on server restart.
- **Version control:** Git + GitHub.

## Non-goals for MVP

Explicitly out of scope — do not build these:
- Matchmaking, lobbies browser, or player accounts
- Voice chat, text chat, emotes
- Spectator mode
- AI opponent
- Reconnect after disconnect (treat disconnect as forfeit for MVP)
- Replay system
- Persistent stats, rankings, or game history
- Steam, itch.io, or any distribution platform (just share the binary)
- Mac/Linux code signing (friends will dismiss the warning)
- Animations beyond tween-based move/attack feedback
- Sound effects or music
- Custom army lists (MVP is random roll only)
- Terrain beyond simple impassable tiles
- Morale, panic, retreat, or any rules beyond move/shoot/melee

## Turnip 28 domain notes

Turnip 28 is a skirmish wargame in the Trench Crusade / grimdark mud aesthetic. Ship **our own simplified ruleset** inspired by it — do not reproduce published stat blocks verbatim.

For the MVP:
- Units have stats: Movement, Shooting, Combat, Resolve, Wounds, Save
- Armies are ~5–10 models rolled from random tables (Toff leader, Chuff retinue, Root mutations)
- 3 unit archetypes (Toff, Chuff, Root Beast) defined in data
- 2–3 random mutation tables per archetype
- One weapon per unit (melee OR ranged) chosen at roll time
- Turn structure: alternating activations, each activation = move + one action (shoot OR charge)
- Measurements: grid-based, 1 cell = 1 inch equivalent, recommend 48×32 cell board
- Dice: simple d6 to-hit, to-wound, save rolls

## Project structure

A **single** Godot project at `godot/`. Server vs. client mode is decided at runtime — by the `--server` CLI arg or the `dedicated_server` feature tag — not by having two separate projects.

```
godot/
├── project.godot
├── entry.tscn              # Main scene — branches on NetworkManager.is_server
├── entry.gd
├── icon.svg
│
├── autoloads/
│   └── network_manager.gd  # Mode detection singleton (is_server flag)
│
├── game/                   # Pure logic — NO node/scene dependencies
│   ├── types.gd            # Unit, Stats, Weapon, Mutation (RefCounted)
│   ├── ruleset.gd          # Loads + validates JSON rulesets
│   ├── army_roller.gd      # roll_army(ruleset, roll_d6: Callable)
│   └── rulesets/           # One JSON file per ruleset
│       └── mvp.json
│
├── server/                 # Server-only
│   ├── server_main.gd
│   ├── server_main.tscn
│   ├── network_server.gd   # Accepts peers, routes RPCs
│   ├── room_manager.gd     # Tracks rooms by code
│   └── game_engine.gd      # Authoritative game logic (pure functions)
│
├── client/                 # Client-only
│   ├── main.gd
│   ├── main.tscn
│   └── scenes/             # MainMenu, Lobby, Battle
│
└── tests/                  # Headless tests for game/ logic
```

**Key contracts:**

- **`game/` is no-node.** Everything in `game/` must be pure RefCounted — no `Node`, no `get_tree()`, no scene tree, no signals. Safe to use from server, client, or headless tests.
- **Data-driven rulesets.** Archetypes, mutation tables, weapons, and composition rules live in JSON files under `game/rulesets/`, not in GDScript. The engine is singular; the data varies.
- **Dependency injection for dice.** Game logic that needs randomness takes a `roll_d6: Callable` argument. This makes tests deterministic and keeps the server as the sole authority for real dice rolls.
- **Single project, runtime split.** Don't duplicate code across two Godot projects. `NetworkManager.is_server` picks the entry path; the `game/` folder is literally shared because it's literally one folder.

## Networking architecture

- Server listens on a fixed UDP port (e.g. 9999) on the VPS
- Client connects with `ENetMultiplayerPeer.create_client(server_ip, 9999)`
- Authentication: none for MVP. Players enter a display name. Server assigns peer IDs.
- Room model: server holds a dictionary of `room_code -> RoomState`. Room codes are 6-char uppercase (exclude I/O/0/1).
- RPCs:
  - Client → Server: `create_room()`, `join_room(code)`, `set_ready(bool)`, `submit_army(army_data)`, `request_action(action_type, payload)`
  - Server → Clients: `room_joined(room_state)`, `peer_joined(player)`, `game_started(initial_state)`, `state_update(units_delta)`, `action_resolved(action, dice, result)`, `game_ended(winner)`
- All RPCs are `@rpc("any_peer", "call_remote", "reliable")` unless specifically noted
- Server validates every action. Clients never trust each other, and never mutate shared state directly.

## Data model (in-memory on server)

```gdscript
# Pseudocode — actual types defined in godot/game/types.gd as RefCounted

class RoomState:
    var code: String
    var status: String  # "lobby" | "active" | "finished"
    var players: Array[PlayerState]
    var current_turn_seat: int
    var turn_number: int
    var units: Array[UnitState]
    var action_log: Array[Dictionary]

class PlayerState:
    var peer_id: int
    var seat: int  # 1 or 2
    var display_name: String
    var army: Array[UnitState]
    var ready: bool

class UnitState:
    var id: String  # uuid
    var owner_seat: int
    var name: String
    var archetype: String
    var stats: Dictionary
    var mutations: Array[String]
    var weapon: Dictionary
    var max_wounds: int
    var current_wounds: int
    var x: int
    var y: int
    var has_activated: bool
    var is_dead: bool
```

## Build order (strictly sequential — don't skip ahead)

Phase numbering matches `CLAUDE.md`. Phase 0 is already complete.

### Phase 0: Project scaffold ✅
1. Single Godot project at `godot/`
2. `autoloads/network_manager.gd` detects `--server` / `dedicated_server` → sets `is_server`
3. `entry.tscn` branches to server or client main scene
4. Folder layout established; empty server + client + game + tests dirs

### Phase 1: Game data (types, ruleset JSON, army roller)
1. Define RefCounted data classes in `game/types.gd`: `Stats`, `Weapon`, `Mutation`, `Unit`
2. Author the first ruleset at `game/rulesets/mvp.json`: 3 archetypes, 2–3 mutation tables each, weapon pool, composition rules
3. Implement `game/ruleset.gd` — loads and validates a ruleset JSON; fails fast on malformed data
4. Implement `game/army_roller.gd` with `roll_army(ruleset, roll_d6: Callable) -> Array[Unit]`
5. Headless tests in `tests/`: deterministic dice sequence → identical army; composition rules respected; loader error paths

Checkpoint: `godot --headless` runs tests green. Same dice sequence produces the same army.

### Phase 2: Army rolling UI (client-side, no networking)
1. Build a `TestRoll.tscn` under `client/scenes/` that rolls an army and displays it as labels
2. Wire the Main Menu → TestRoll flow locally (no server involved)
3. Add a re-roll button

Checkpoint: I can run the client, click a button, see a random army, and re-roll.

### Phase 3: ENet networking, lobby, room management
1. `server/server_main.gd`: boot ENet server on port 9999, log connections/disconnections
2. `server/room_manager.gd`: create_room, join_room, generate 6-char codes, evict full/empty rooms
3. `server/network_server.gd`: expose RPCs for room management only (no game logic yet)
4. Client `MainMenu` + `Lobby` scenes — just enough UI to exercise the RPCs
5. Two client instances connect to the local server, create/join a room, see each other

Checkpoint: Two clients on my laptop connect to the local server, share a room code, see each other's names.

Phase 3b — Army submission (fold into Phase 3 if small):
- Each client rolls locally via Phase 1 code, submits via `submit_army`
- Server stores armies in `RoomState.players[].army`
- `set_ready(bool)` — when both ready, server broadcasts `game_started`

### Phase 4: Battle gameplay (server-authoritative)
1. Pure engine functions in `server/game_engine.gd` (state + action + dice → new state):
   - `move_unit(state, unit_id, x, y) -> Result`
   - `resolve_shoot(state, attacker_id, target_id, dice) -> Result`
   - `resolve_charge(state, attacker_id, target_id, dice) -> Result`
   - `end_activation(state, seat) -> Result`
   - `end_turn(state) -> Result`
2. Dice rolls are passed in, never rolled inside the engine — keeps tests deterministic
3. Engine tests covering: valid/invalid moves, range checks, wound application, death, activation exhaustion, turn flip, win condition
4. `Battle.tscn` on the client: TileMap grid, unit sprites with click handling
5. Client sends `request_action` RPCs; server validates, rolls dice, applies engine, broadcasts `state_update` + `action_resolved`
6. Clients re-render from server state. **No client-side prediction in MVP.**
7. Action log sidebar reading from `action_resolved`; turn banner; active-player indicator

Checkpoint: Two clients on my laptop play a full networked game against the local server. State stays consistent.

### Phase 5: Polish, multiple rulesets
1. Win condition check at end of each activation; Victory/Defeat screen
2. "New game" button returns both players to lobby
3. Visual polish: placeholder sprites, health bars, movement range highlight, attack target highlight
4. Peer disconnect handling: opposing peer drops → "Opponent disconnected — you win" → menu
5. Prove the data-driven ruleset story by adding a second JSON ruleset and swapping between them in the lobby

### Phase 6: Export presets, deployment
1. Export presets for Windows, Mac, Linux clients (created via editor UI, **not** committed to git)
2. Export preset for headless Linux server binary
3. `deploy/turnip28-server.service` systemd unit: restart on failure, log to journald
4. `deploy/deploy.sh`: rsync server binary + restart systemd service
5. Open UDP port 9999 in firewall (ufw or VPS panel)
6. Client: "Server IP" field on main menu (default to VPS IP, overridable)
7. Put client binaries on a GitHub release

Checkpoint: Two clients on two different machines, connecting over the internet, play a full game.

## Things to get right early (cheap now, expensive later)

- **Pure engine functions.** `game_engine.gd` takes state and returns state. No signals, no `get_tree()`, no direct node access. This is what makes Phase 4 testable without networking and trivially portable.
- **Server is the authority, always.** Client-side prediction is a post-MVP problem. For MVP, clients are dumb renderers. The small latency is fine for a turn-based game.
- **Inject dice, don't call them.** The army roller and combat resolver take a `Callable` for dice. Tests pass a deterministic stub; the server passes a real RNG. Replay comes almost for free later.
- **One data definition, not two.** `UnitState` lives once in `game/`. Single project, single folder — no symlink drift to worry about.
- **Rulesets are data, not code.** Add a new faction by writing JSON, not by editing `army_roller.gd`. If you feel tempted to branch on ruleset ID inside the engine, the data model is wrong.
- **Room code, not peer ID, in the UI.** Peer IDs are internal. Friends type 6-char codes.
- **Log every RPC on the server at INFO level in dev.** systemd journal + `print()` is fine. When multiplayer breaks, you'll need the timeline.

## Things I will be tempted to do — don't

- Don't use C#. GDScript ships faster for a project this size.
- Don't split into two Godot projects. One project, runtime mode split. The old plan had two; we consolidated for a reason.
- Don't build client-side prediction, rollback, or reconciliation. Turn-based game. Not needed.
- Don't add a database in Phase 6. In-memory rooms are fine. Persistence is post-MVP.
- Don't build a server browser UI. Direct-connect by IP is the whole interface.
- Don't generalize the weapon/stat/mutation system until a second ruleset demands it. (Phase 5 is where that pressure shows up — not before.)
- Don't try to match official Turnip 28 balance. Ship the loop first.
- Don't bother with Mac/Windows code signing for MVP. Friends will click through warnings.
- Don't use Godot's `MultiplayerSynchronizer`/`MultiplayerSpawner` nodes. They're designed for real-time games with replicated transforms. For a turn-based authoritative model, plain RPCs are simpler and clearer.
- Don't commit export presets. They're editor-generated per-machine (Phase 6).

## What I want from you, Claude Code

Work through the phases in order. At each checkpoint, stop and let me verify before moving to the next phase. When you hit a decision that isn't covered here (specific mutation names, sprite placeholders, exact dice math), make a reasonable choice, flag it with a `# DECISION:` comment, and keep going — don't ask me mid-phase unless you're genuinely blocked.

Use Godot's built-in test affordances or GUT if you prefer. Colocate tests next to source as `*_test.gd` or keep them in `godot/tests/`. Keep scripts short. Prefer composition of small scenes over monolithic ones. No premature abstractions.

For the VPS deploy in Phase 6, assume Ubuntu 24.04 and that I have SSH access as a sudo user. Generate the systemd unit and deploy script but don't try to execute them — I'll run those myself.
