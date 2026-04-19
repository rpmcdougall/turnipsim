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
- Cult-specific units and mechanics (core units only for now)
- Terrain beyond simple impassable tiles
- Morale, panic, retreat, or any rules beyond move/shoot/melee

## Turnip 28 domain notes

Turnip 28 is a skirmish wargame in the grimdark root-vegetable apocalypse aesthetic. The simulator uses the **official v17 Core Rules** as its data source.

### Stats (Turnip28 v17 Characteristics)
- **M** (Movement): max distance in inches
- **A** (Attacks): number of melee dice per model
- **I** (Inaccuracy): minimum D6 result to hit (lower = better, same for shooting + melee)
- **W** (Wounds): damage capacity per model
- **V** (Vulnerability): minimum D6 result to save (lower = better)

### Core Unit Types
- **Snobs**: Toff (1 model, cmd range 6"), Toady (1 model, cmd range 3")
- **Infantry**: Fodder (12), Chaff (4), Brutes (6)
- **Cavalry**: Whelps (4), Bastards (3)
- **Artillery**: Stump Gun (1)

### Equipment Types
- **Black Powder** (ranged): generates powder smoke token, can't shoot again until next round
- **Missile** (ranged): target's V reduced by 2
- **Close Combat** (melee): -1 I for melee, may re-roll charge distance
- **Pistols and Sabres** (Snob only): no powder smoke, not close combat

### Army Building (Snobs + Followers)
- 1 Toff (brings 2 Follower units) + N Toadies (each brings 1 Follower unit)
- Standard game: 3 Snobs (1 Toff + 2 Toadies) = 4 Follower units
- Followers chosen from core unit types or Cult-specific units
- All models in a unit share the same equipment

### Turn Structure
- Played in rounds (usually 4), initiative set once at start
- Each round: alternate ordering Snobs → Snobs order Followers in command range
- Orders: Volley Fire, Move and Shoot, March, Charge
- Blunder check on D6 (roll 1 = blunder + panic token)
- Combat: Inaccuracy roll to hit → Vulnerability roll to save → wounds

### Army Submission
- Players build a roster selecting Snobs, Followers, and equipment within rules constraints
- Roster format: `{ cult, snobs: [{ snob_type, equipment, followers: [{ unit_type, equipment }] }] }`
- Presets available for quick start (sourced from community lists)
- Server validates roster against ruleset composition rules before accepting

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
│   ├── types.gd            # Stats, UnitDef, Roster, UnitState, GameState (RefCounted)
│   ├── ruleset.gd          # Loads + validates v17 JSON rulesets
│   └── rulesets/           # One JSON file per ruleset
│       └── v17.json        # Turnip28 v17 core rules data
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
- **Data-driven rulesets.** Unit types, equipment, special rules, and composition constraints live in JSON files under `game/rulesets/`, not in GDScript. The engine is singular; the data varies.
- **Dependency injection for dice.** Game logic that needs randomness takes a `roll_d6: Callable` argument. This makes tests deterministic and keeps the server as the sole authority for real dice rolls.
- **Single project, runtime split.** Don't duplicate code across two Godot projects. `NetworkManager.is_server` picks the entry path; the `game/` folder is literally shared because it's literally one folder.

## Networking architecture

- Server listens on a fixed UDP port (e.g. 9999) on the VPS
- Client connects with `ENetMultiplayerPeer.create_client(server_ip, 9999)`
- Authentication: none for MVP. Players enter a display name. Server assigns peer IDs.
- Room model: server holds a dictionary of `room_code -> RoomState`. Room codes are 6-char uppercase (exclude I/O/0/1).
- RPCs:
  - Client → Server: `create_room()`, `join_room(code)`, `set_ready(bool)`, `submit_roster(roster_data)`, `request_action(action_type, payload)`
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
    var unit_type: String      # "Fodder", "Toff", etc.
    var category: String       # "snob", "infantry", "cavalry", "artillery"
    var model_count: int       # Current living models
    var max_models: int        # Starting model count
    var base_stats: Stats      # M/A/I/W/V + weapon_range
    var equipment: String      # Equipment type key
    var special_rules: Array[String]
    var panic_tokens: int      # 0-6
    var has_powder_smoke: bool
    var current_wounds: int
    var x: int
    var y: int
    var has_activated: bool
    var is_dead: bool
    var snob_id: String        # Commanding Snob's ID
```

## Build order (strictly sequential — don't skip ahead)

Phase numbering matches `CLAUDE.md`. Phase 0 is already complete.

### Phase 0: Project scaffold ✅
1. Single Godot project at `godot/`
2. `autoloads/network_manager.gd` detects `--server` / `dedicated_server` → sets `is_server`
3. `entry.tscn` branches to server or client main scene
4. Folder layout established; empty server + client + game + tests dirs

### Phase 1: Game data (types, ruleset JSON) ← REWORKED
1. Define RefCounted data classes in `game/types.gd`: `Stats` (M/A/I/W/V), `Equipment`, `UnitDef`, `Roster`, `RosterSnob`, `RosterUnit`, `UnitState`, `GameState`
2. Author the v17 ruleset at `game/rulesets/v17.json`: all core unit types with real stats, equipment types, special rules, army composition constraints
3. Implement `game/ruleset.gd` — loads and validates v17 JSON; validates rosters against composition rules

Checkpoint: `godot --headless` runs tests green. Ruleset loads, roster validation works.

### Phase 2: REMOVED (was: Army rolling UI — replaced by Phase 5b Army Submission)

### Phase 3: ENet networking, lobby, room management
1. `server/server_main.gd`: boot ENet server on port 9999, log connections/disconnections
2. `server/room_manager.gd`: create_room, join_room, generate 6-char codes, evict full/empty rooms
3. `server/network_server.gd`: expose RPCs for room management only (no game logic yet)
4. Client `MainMenu` + `Lobby` scenes — just enough UI to exercise the RPCs
5. Two client instances connect to the local server, create/join a room, see each other

Checkpoint: Two clients on my laptop connect to the local server, share a room code, see each other's names.

Phase 3b — Roster submission (fold into Phase 3 if small):
- Each client selects a preset roster or builds one via Phase 5b UI, submits via `submit_roster`
- Server validates roster against ruleset composition rules
- Server stores rosters in `RoomState.players[].roster`
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

### Phase 5: Polish
1. Win condition check at end of each activation; Victory/Defeat screen
2. "New game" button returns both players to lobby
3. Visual polish: placeholder sprites, health bars, movement range highlight, attack target highlight
4. Peer disconnect handling: opposing peer drops → "Opponent disconnected — you win" → menu

### Phase 5b: Army Submission UI
1. Roster builder screen — pick Snobs, assign Followers, choose equipment within ruleset constraints
2. Preset rosters: hardcoded community-sourced army lists for quick start
3. Roster validation feedback in UI (highlight invalid picks, show composition errors)
4. Replace the old test_roll screen; wire into lobby flow (build roster → submit → ready up)

### Phase 6: Export presets, deployment
1. Export presets for Windows, Mac, Linux clients (created via editor UI, **not** committed to git)
2. Export preset for headless Linux server binary
3. `deploy/turnip28-server.service` systemd unit: restart on failure, log to journald
4. `deploy/deploy.sh`: rsync server binary + restart systemd service
5. Open UDP port 9999 in firewall (ufw or VPS panel)
6. Client: "Server IP" field on main menu (default to VPS IP, overridable)
7. Put client binaries on a GitHub release

Checkpoint: Two clients on two different machines, connecting over the internet, play a full game.

### Phase 7: Cult mechanics
1. Extend `v17.json` with cult-specific data: unique unit types, cult special rules, army composition overrides
2. Add cult selection to roster builder (Phase 5b UI) — selecting a cult unlocks cult units and applies army mod constraints
3. Implement cult special rules in `game_engine.gd` — data-driven where possible, code hooks where necessary
4. Start with 2–3 simpler cults (Toadpole tier: Harry's Recruits, Slug's Lament, Fungivorous Herd) and expand
5. Tests for cult-specific composition validation and combat interactions

Checkpoint: Two players can pick different cults and play a game using cult-specific units and abilities.

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
- Don't implement Cult-specific mechanics until after core gameplay loop ships.
- Don't bother with Mac/Windows code signing for MVP. Friends will click through warnings.
- Don't use Godot's `MultiplayerSynchronizer`/`MultiplayerSpawner` nodes. They're designed for real-time games with replicated transforms. For a turn-based authoritative model, plain RPCs are simpler and clearer.
- Don't commit export presets. They're editor-generated per-machine (Phase 6).

## What I want from you, Claude Code

Work through the phases in order. At each checkpoint, stop and let me verify before moving to the next phase. When you hit a decision that isn't covered here (specific mutation names, sprite placeholders, exact dice math), make a reasonable choice, flag it with a `# DECISION:` comment, and keep going — don't ask me mid-phase unless you're genuinely blocked.

Use Godot's built-in test affordances or GUT if you prefer. Colocate tests next to source as `*_test.gd` or keep them in `godot/tests/`. Keep scripts short. Prefer composition of small scenes over monolithic ones. No premature abstractions.

For the VPS deploy in Phase 6, assume Ubuntu 24.04 and that I have SSH access as a sudo user. Generate the systemd unit and deploy script but don't try to execute them — I'll run those myself.
