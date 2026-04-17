# Turnip 28 Multiplayer Simulator — MVP Build Plan (Godot 4)

## Project goal

Build a desktop multiplayer simulator for Turnip 28 where two players can:
1. Roll a random army following simplified Turnip 28 rules
2. Connect to a shared game room through a relay server
3. Play a skirmish battle with authoritative server-side state

Priority order: ship fast > low ops > no-install for friends > my existing stack.

## Stack decisions (locked in — do not re-litigate)

- **Engine:** Godot 4.3+ (stable channel)
- **Language:** GDScript (NOT C# — GDScript is faster to iterate in, has zero build step, and the project doesn't need C#'s perf)
- **Networking:** Godot's built-in `MultiplayerAPI` over ENet (`ENetMultiplayerPeer`)
- **Architecture:** Authoritative dedicated server (headless Godot export) + two thin clients
- **Server hosting:** Single cheap VPS (DigitalOcean/Hetzner, ~$5/month), Ubuntu, systemd service
- **Client distribution:** Direct download of exported binaries (Windows `.exe`, Mac `.app`, Linux binary) — no Steam, no installers
- **Persistence:** None for MVP. Server holds game state in memory. Games disappear on server restart.
- **Version control:** Git + GitHub. Godot's `.gitignore` template.

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
- 3 unit archetypes (Toff, Chuff, Root Beast) with hardcoded stat blocks in a data file
- 2–3 random mutation tables per archetype
- One weapon per unit (melee OR ranged) chosen at roll time
- Turn structure: alternating activations, each activation = move + one action (shoot OR charge)
- Measurements: grid-based, 1 cell = 1 inch equivalent, recommend 48×32 cell board
- Dice: simple d6 to-hit, to-wound, save rolls

## Project structure

```
turnip28-sim/
├── client/                    # Godot project: the client app
│   ├── project.godot
│   ├── scenes/
│   │   ├── Main.tscn          # Root, holds MainMenu/Lobby/Battle
│   │   ├── MainMenu.tscn      # Connect to server, enter name
│   │   ├── Lobby.tscn         # Create/join room, roll army, ready up
│   │   └── Battle.tscn        # The tabletop
│   ├── scripts/
│   │   ├── network_client.gd  # Wraps MultiplayerAPI, signals for UI
│   │   ├── game_state.gd      # Client-side mirror of server state
│   │   └── ui/                # One script per scene
│   ├── game/                  # Shared logic (copied to server/)
│   │   ├── types.gd           # Unit, Army, Stats resources
│   │   ├── archetypes.gd      # Stat blocks
│   │   ├── mutations.gd       # Mutation tables
│   │   └── army_roller.gd     # Pure function, seedable
│   └── assets/                # Minimal: unit sprites, board tiles
│
├── server/                    # Godot project: headless server
│   ├── project.godot          # Exports as headless Linux binary
│   ├── main.gd                # Entry point, boots ENet server
│   ├── network_server.gd      # Accepts peers, routes RPCs
│   ├── room_manager.gd        # Tracks rooms by code, handles join/leave
│   ├── game_engine.gd         # Authoritative game logic
│   └── game/                  # Symlink or copy of client/game/
│
├── deploy/
│   ├── turnip28-server.service  # systemd unit file
│   └── deploy.sh                # rsync + restart script
│
└── README.md
```

**Key principle:** the `game/` folder is identical between client and server. The client uses it for the army roller and for predicting/displaying state. The server uses it as the authority. Either symlink it or set up a simple copy step — don't let the two drift.

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
# Pseudocode — actual will be Godot Resources or typed dicts

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

### Phase 0: Repo scaffolding
1. Create the directory structure above
2. Initialize two Godot 4 projects (`client/`, `server/`)
3. Server project: set main scene to a blank node, enable headless-friendly project settings (no window, no rendering)
4. Set up shared `game/` folder — use a symlink for dev, a copy step in deploy
5. Create empty GitHub repo, commit, verify both projects open cleanly

### Phase 1: Army roller (client only, pure logic)
1. Define Godot Resources in `game/types.gd` for Unit, Stats, Weapon, Mutation
2. Fill in `game/archetypes.gd` and `game/mutations.gd` with hardcoded data — 3 archetypes, 2–3 mutations each
3. Write `game/army_roller.gd` with `roll_army(seed: int) -> Array[Unit]` — use `RandomNumberGenerator` seeded explicitly
4. Write GUT tests (or simple `_ready()` test scene) that roll armies with fixed seeds and assert structure
5. Build a temporary `TestRoll.tscn` that rolls and displays an army as labels

Checkpoint: I can run the client, see a random army, re-roll. Same seed → same army. Tests pass.

### Phase 2: Battle logic (server-side pure functions, no networking yet)
1. In `server/game_engine.gd`, write pure functions that take state + action + dice rolls and return new state:
   - `move_unit(state, unit_id, x, y) -> Result`
   - `resolve_shoot(state, attacker_id, target_id, dice) -> Result`
   - `resolve_charge(state, attacker_id, target_id, dice) -> Result`
   - `end_activation(state, seat) -> Result`
   - `end_turn(state) -> Result`
2. Dice rolls are passed in, NOT rolled inside the functions — this makes tests deterministic and keeps the engine pure
3. Write tests covering: valid/invalid moves, range checks, wound application, death, activation exhaustion, turn flip, win condition
4. Build a throwaway `TestBattle.tscn` in the client that runs a full game locally using the engine — no networking

Checkpoint: I can play both sides of a full battle in one client window. Tests pass.

### Phase 3: Server skeleton
1. `server/main.gd`: boot ENet server on port 9999, log connections/disconnections
2. `server/room_manager.gd`: create_room, join_room, generate 6-char codes, evict full/empty rooms
3. Expose RPCs for room management only — no game logic yet
4. Run server locally (`godot --headless`), connect from client manually, verify you can create/join rooms across two client instances
5. Wire up a minimal `MainMenu.tscn` and `Lobby.tscn` — just enough to exercise the RPCs

Checkpoint: Two client instances on my laptop can connect to the local server, create a room, both join, see each other's names.

### Phase 4: Lobby + army submission
1. In the lobby: each client rolls an army locally (using Phase 1 code), displays it, sends to server via `submit_army`
2. Server stores armies in `RoomState.players[].army`
3. Server exposes `set_ready(bool)`. When both players ready, server transitions room to "active" and broadcasts `game_started` with the initial unit positions (seat 1 bottom, seat 2 top)

Checkpoint: Two clients roll armies, ready up, and both receive a `game_started` event with matching state.

### Phase 5: Networked battle
1. Build `Battle.tscn` on the client: grid board as a TileMap, units as Sprite2Ds with click handling
2. Client sends `request_action` RPCs for moves and attacks
3. Server validates (correct player's turn? unit belongs to them? action legal?), rolls dice server-side, applies engine, broadcasts `state_update` + `action_resolved` to both clients
4. Clients re-render from received state. Do NOT do client-side prediction in MVP.
5. Show action log sidebar that reads from `action_resolved` events
6. Turn banner, active-player indicator

Checkpoint: Two clients on my laptop play a full networked game against the local server. State stays consistent.

### Phase 6: Deploy the server
1. Install Godot headless on the VPS (or export the server as a Linux binary and scp it — the latter is cleaner)
2. Write `deploy/turnip28-server.service` systemd unit: restart on failure, log to journald
3. Open UDP port 9999 in the firewall (ufw or the VPS provider's panel)
4. `deploy.sh`: rsync server binary + restart systemd service
5. Client: add a "Server IP" field to the main menu (default to your VPS IP, overridable)

Checkpoint: Two clients on two different machines, connecting over the internet, play a full game.

### Phase 7: Polish (only after Phase 6 works end to end)
1. Win condition check at end of each activation; show "Victory" / "Defeat" screen
2. "New game" button returns both players to lobby
3. Visual polish: unit sprites (placeholder art fine — simple colored shapes with letters), health bars, movement range highlight, attack target highlight
4. Handle peer disconnect: if opposing peer drops, show "Opponent disconnected — you win" and return to menu
5. Export clients for Windows + Mac + Linux. Put binaries on a GitHub release. Share the link.

## Things to get right early (cheap now, expensive later)

- **Pure engine functions.** `game_engine.gd` takes state and returns state. No signals, no `get_tree()`, no direct node access. This is what makes Phase 2 testable without networking and Phase 5 trivially portable.
- **Server is the authority, always.** Client-side prediction is a Phase 8+ problem. For MVP, clients are dumb renderers. The small latency is fine for a turn-based game.
- **Seed the RNG explicitly.** Both the army roller and the server's combat resolver take a `RandomNumberGenerator` argument. Makes tests deterministic and gives us replay later for free.
- **One data definition, not two.** The client's `UnitState` and the server's `UnitState` are the same Resource class in the shared `game/` folder. If they drift, you'll spend a weekend debugging it.
- **Room code, not peer ID, in the UI.** Peer IDs are internal. Friends type 6-char codes.
- **Log every RPC on the server at INFO level in dev.** systemd journal + `print()` is fine. When things go wrong in multiplayer, you'll need the timeline.

## Things I will be tempted to do — don't

- Don't use C#. GDScript ships faster for a project this size.
- Don't build client-side prediction, rollback, or reconciliation. Turn-based game. Not needed.
- Don't add a database in Phase 6. In-memory rooms are fine. Persistence is Phase 8+.
- Don't build a server browser UI. Direct-connect by IP is the whole interface.
- Don't generalize the weapon/stat/mutation system until a second instance demands it.
- Don't try to match official Turnip 28 balance. Ship the loop first.
- Don't bother with Mac/Windows code signing for MVP. Friends will click through warnings.
- Don't use Godot's `MultiplayerSynchronizer`/`MultiplayerSpawner` nodes. They're designed for real-time games with replicated transforms. For a turn-based authoritative model, plain RPCs are simpler and clearer.

## What I want from you, Claude Code

Work through the phases in order. At each checkpoint, stop and let me verify before moving to the next phase. When you hit a decision that isn't covered here (specific mutation names, sprite placeholders, exact dice math), make a reasonable choice, flag it with a `# DECISION:` comment, and keep going — don't ask me mid-phase unless you're genuinely blocked.

Use Godot's built-in test affordances or GUT if you prefer. Colocate tests next to source as `*_test.gd`. Keep scripts short. Prefer composition of small scenes over monolithic ones. No premature abstractions.

For the VPS deploy in Phase 6, assume Ubuntu 24.04 and that I have SSH access as a sudo user. Generate the systemd unit and deploy script but don't try to execute them — I'll run those myself.
