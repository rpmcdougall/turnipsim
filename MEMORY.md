# Turnip28 Simulator - Project Memory

**Last Updated:** 2026-04-17
**Current Phase:** Phase 3 Complete, Phase 4 Next
**Main Branch:** `5ccf02d`

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

### Next Phase 🎯

**Phase 4: Battle Gameplay (Server-Authoritative)**
- Implement `game_engine.gd` with pure functions (move, shoot, charge, end turn)
- Engine tests (deterministic, dice injected)
- `Battle.tscn` UI: TileMap grid, unit sprites, click handling
- Client sends `request_action` RPCs
- Server validates, rolls dice, broadcasts `state_update`
- Action log, turn banner, active player indicator

**Checkpoint Goal:** Two clients play full networked game against local server.

### Remaining After Phase 4

- **Phase 5:** Polish (win conditions, visual polish, 2nd ruleset)
- **Phase 6:** Export & deployment (VPS, binaries, systemd)

---

## Architecture Quick Reference

### Project Structure
```
godot/
├── game/           # Pure RefCounted logic (no Node deps)
│   ├── types.gd    # Stats, Weapon, Mutation, Unit
│   ├── ruleset.gd  # JSON loader & validator
│   ├── army_roller.gd  # roll_army(ruleset, roll_d6)
│   └── rulesets/mvp.json
├── server/         # Server-only
│   ├── server_main.gd      # ENet server (port 9999)
│   ├── room_manager.gd     # Room creation, 6-char codes
│   ├── network_server.gd   # RPC layer
│   └── game_engine.gd      # TODO: Phase 4
├── client/         # Client-only
│   ├── main.tscn           # Main menu
│   ├── scenes/test_roll.tscn   # Army roller demo
│   └── scenes/lobby.tscn   # Multiplayer lobby
└── tests/
    ├── test_runner.gd      # 19 tests
    ├── test_ui_instantiate.gd
    └── test_phase3_scenes.gd
```

### Key Design Decisions

1. **Single project, runtime mode split:** `--server` flag determines mode
2. **Pure game/ folder:** RefCounted only, no Node dependencies
3. **Data-driven rulesets:** JSON defines archetypes/mutations/weapons
4. **Dependency injection for dice:** `roll_d6: Callable` enables deterministic tests
5. **Server-authoritative:** No client-side prediction (turn-based, latency OK)
6. **6-char room codes:** Uppercase, excludes I/O/0/1

---

## Current Networking Flow

1. **Connect:** Client → Server (ENet on 127.0.0.1:9999)
2. **Create Room:** Client calls `create_room.rpc_id(1, display_name)`
3. **Server Response:** `_send_room_joined.rpc_id(peer_id, room_data)`
4. **Join Room:** Client calls `join_room.rpc_id(1, code, display_name)`
5. **Broadcast:** Server notifies all players via `_send_peer_joined`
6. **Ready Toggle:** Client calls `set_ready.rpc_id(1, bool)`
7. **Sync:** Server broadcasts `_send_player_ready_changed` to all

**Room State:**
```gdscript
{
  "code": "ABC123",
  "status": "lobby",  # or "active", "finished"
  "players": [
    {"peer_id": 123, "seat": 1, "display_name": "Alice", "ready": false, "army": []},
    {"peer_id": 456, "seat": 2, "display_name": "Bob", "ready": false, "army": []}
  ],
  "max_players": 2
}
```

---

## Testing

### Run Tests Locally
```bash
cd godot/
godot --headless -s tests/test_runner.gd
godot --headless -s tests/test_ui_instantiate.gd
godot --headless -s tests/test_phase3_scenes.gd
```

### Run Server
```bash
cd godot/
godot project.godot --server
```

### Run Client
```bash
cd godot/
godot project.godot
```

### CI
- GitHub Actions on PR to main, push to main
- Downloads Godot 4.6.2 headless
- Runs all test suites
- Uses `-s` flag (not `--script`) to load project context

---

## Workflow

### Feature Branch Process (Established Phase 3+)
1. Create branch: `git checkout -b feature/phase-N-description`
2. Implement with modular commits
3. Push: `git push -u origin feature/phase-N-description`
4. Create PR: `gh pr create --title "..." --body "..."`
5. CI validates automatically
6. Merge via squash after approval
7. Update CLAUDE.md phase status
8. Update GitHub project board

### Commit Format
```
<type>(<scope>): <description>

[optional body]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`

---

## GitHub Project Board

**Project:** TurnipSim v0.1 (project #1)
- Phase 1: Issues #1-5 (All Done)
- Phase 2: Issue #6 (Done)
- Phase 3: Issues #7-8 (Done)

**Update after each phase completion.**

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
- `memory/checkpoint-2026-04-17-phases-1-2-3.md` — This session

---

## Phase 4 Planning Notes

### game_engine.gd Functions Needed
```gdscript
# Pure functions (state + action + dice → new state)
func move_unit(state, unit_id, x, y) -> Result
func resolve_shoot(state, attacker_id, target_id, dice) -> Result
func resolve_charge(state, attacker_id, target_id, dice) -> Result
func end_activation(state, seat) -> Result
func end_turn(state) -> Result
```

### Battle.tscn Components
- TileMap grid (48×32 cells recommended)
- Unit sprites (placeholder sprites OK)
- Click handling for unit selection
- Action log sidebar (ScrollContainer with Labels)
- Turn banner (whose turn, turn number)
- Active player indicator

### RPC Flow (Phase 4)
1. Client sends: `request_action.rpc_id(1, {"type": "move", "unit_id": "...", "x": 5, "y": 3})`
2. Server validates, rolls dice if needed, applies engine
3. Server broadcasts: `state_update.rpc(units_delta)` and `action_resolved.rpc(action, dice, result)`
4. Clients re-render from server state

**No client-side prediction in MVP.** Clients wait for server confirmation.

---

## Commands Quick Reference

```bash
# Run server
godot --server

# Run client
godot

# Run tests
godot --headless -s tests/test_runner.gd

# Create feature branch
git checkout -b feature/phase-4-battle

# Push and create PR
git push -u origin feature/phase-4-battle
gh pr create --title "feat(phase4): implement battle gameplay"

# Update project board
gh project item-list 1 --owner rpmcdougall
gh project item-edit --project-id PVT_kwHOAG78Fc4BU8gp --id <ITEM_ID> \
  --field-id PVTSSF_lAHOAG78Fc4BU8gpzhMIc_o --single-select-option-id 98236657
```

---

## Session Discipline Reminders

- [ ] Update MEMORY.md before `/clear` or session end
- [ ] Create checkpoint between phases (`memory/checkpoint-YYYY-MM-DD-<topic>.md`)
- [ ] Keep MEMORY.md under 200 lines (archive old content to `memory/history.md`)
- [ ] Update GitHub project board after phase completion
- [ ] Use feature branches for all new phases
- [ ] Make modular commits (one logical unit per commit)

---

**Last checkpoint:** memory/checkpoint-2026-04-17-phases-1-2-3.md
**Next session:** Start Phase 4 (Battle Gameplay)
