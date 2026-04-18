# Phase 4 Manual Testing Guide

**Status:** Phase 3b + Phase 4 Server Complete
**Branch:** `feature/phase-3b-4-battle`
**Date:** 2026-04-17

This guide covers manual testing procedures for Phase 3b (army submission) and Phase 4 (battle gameplay). Client UI is pending, so some tests require implementing the battle scene first.

---

## Prerequisites

### Required
- Godot 4.6.2 stable installed
- Server and client builds working
- Two separate client windows (for multiplayer testing)

### Verify Installation

```bash
# Check Godot version
/Applications/Godot.app/Contents/MacOS/Godot --version
# Should output: 4.6.2.stable.official
```

---

## Part 1: Automated Tests

Run these first to verify core functionality.

### 1.1 Phase 1 Game Logic Tests

```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_runner.gd
```

**Expected output:**
```
=== Running Game Tests ===

✓ PASS: Ruleset should load from valid JSON
✓ PASS: Ruleset should error on missing file
...
✓ PASS: Army roller should be deterministic
...

=== Test Results ===
Passed: 19
Failed: 0
```

**If failed:**
- Check working directory is `godot/`
- Verify `game/rulesets/mvp.json` exists
- Check for syntax errors in test file

### 1.2 Phase 4 Engine Tests

```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_game_engine.gd
```

**Expected output:**
```
=== Running GameEngine Tests ===

✓ PASS: place_unit should succeed in valid deployment zone
✓ PASS: place_unit should fail outside deployment zone
...
✓ PASS: move_unit should succeed within movement range
...
✓ PASS: check_victory should detect last unit standing

=== Test Results ===
Passed: 28
Failed: 6

Note: 6 shooting mechanics edge cases pending (known issue)
```

**If more than 6 failed:**
- Check for recent code changes
- Review error messages for clues
- Verify typed array handling (use `.append()` not `= []`)

### 1.3 UI Instantiation Tests

```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_ui_instantiate.gd
```

**Expected output:**
```
=== UI Instantiation Tests ===

✓ PASS: main.tscn should load without errors
✓ PASS: test_roll.tscn should load without errors
✓ PASS: lobby.tscn should load without errors
...

=== Test Results ===
Passed: X
Failed: 0
```

**If failed:**
- Scene file might be corrupted
- Missing script dependencies
- Try opening scene in Godot editor to see specific errors

---

## Part 2: Phase 3b Army Submission Flow

**Goal:** Verify army rolling and submission works in lobby.

### 2.1 Start Server

```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server
```

**Expected console output:**
```
[ServerMain] Starting dedicated server on port 9999
[ServerMain] ENet server listening on *:9999
[RoomManager] Room manager initialized
```

**If server doesn't start:**
- Check port 9999 not in use: `lsof -i :9999`
- Check firewall settings
- Look for error messages in console

### 2.2 Start Two Clients

**Terminal 1:**
```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot
```

**Terminal 2:**
```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot
```

Both clients should open to main menu.

### 2.3 Client 1: Create Room

**Steps:**
1. Click **"Multiplayer Lobby"**
2. Enter player name: `Player1`
3. Server IP: `127.0.0.1:9999`
4. Click **"Connect"**
5. ✅ Verify: Status shows "Connected"
6. Click **"Create Room"**
7. ✅ Verify: Room code appears (e.g., "XYZ789")
8. ✅ Verify: Player list shows "Player1 (Seat 1)"

**Server console should show:**
```
[ServerMain] Peer connected: 1234567890
[NetworkServer] Peer 1234567890 requesting room creation (name: Player1)
[RoomManager] Created room XYZ789 for peer 1234567890
```

### 2.4 Client 2: Join Room

**Steps:**
1. Click **"Multiplayer Lobby"**
2. Enter player name: `Player2`
3. Server IP: `127.0.0.1:9999`
4. Click **"Connect"**
5. ✅ Verify: Status shows "Connected"
6. Enter room code from Client 1 (e.g., "XYZ789")
7. Click **"Join Room"**
8. ✅ Verify: Both clients show "Player1 (Seat 1)" and "Player2 (Seat 2)"

**Server console should show:**
```
[ServerMain] Peer connected: 9876543210
[NetworkServer] Peer 9876543210 requesting to join room XYZ789 (name: Player2)
[RoomManager] Peer 9876543210 joined room XYZ789
```

### 2.5 Both Clients: Ready Up

**Steps:**
1. Both clients check **"Ready"** checkbox
2. ✅ Verify: Both see checkmarks next to player names

**Server console:**
```
[NetworkServer] Peer 1234567890 set ready: true
[NetworkServer] Peer 9876543210 set ready: true
[NetworkServer] All players in room XYZ789 are ready
```

### 2.6 Client 1: Roll Army

**Steps:**
1. Click **"Roll Army"** button
2. ✅ Verify: Army display shows 5-10 units
3. ✅ Verify: Each unit shows:
   - Name (e.g., "Toff Leader")
   - Archetype
   - Stats (Movement, Shooting, Combat, etc.)
   - Weapon
   - Mutations (if any)
4. ✅ Verify: **"Submit Army"** button is now enabled

**If Roll Army button doesn't exist:**
- UI nodes not added to lobby.tscn yet
- See `docs/wiki/Phase-4-UI-Tasks.md` Task 1

### 2.7 Client 1: Submit Army

**Steps:**
1. Click **"Submit Army"** button
2. ✅ Verify: Status message "Army submitted"

**Server console:**
```
[NetworkServer] Peer 1234567890 submitting army (7 units)
```

**Both clients should see:**
- Notification that Player1 submitted their army

### 2.8 Client 2: Roll and Submit Army

**Steps:**
1. Click **"Roll Army"**
2. ✅ Verify: Army displays
3. Click **"Submit Army"**
4. ✅ Verify: Status message "Army submitted"

**Server console:**
```
[NetworkServer] Peer 9876543210 submitting army (6 units)
[NetworkServer] Starting game for room XYZ789
```

### 2.9 Game Start Transition

**Expected behavior:**
- Server broadcasts `_send_game_started` to both clients
- Both clients transition to `battle.tscn`

**If battle.tscn doesn't exist:**
- Clients will show error: "Scene not found"
- Expected at this stage (client UI pending)
- See `docs/wiki/Phase-4-UI-Tasks.md` Task 2

**Server console:**
```
[NetworkServer] Starting game for room XYZ789
[NetworkServer] Initialized game state: placement phase, active_seat=1
```

---

## Part 3: Phase 4 Server-Side Testing

**Goal:** Verify game engine and server RPC routing work correctly.

**Note:** These tests can be done via server console or by implementing temporary RPC test scripts.

### 3.1 Verify Game State Initialization

**Server console should show:**
```
[NetworkServer] Initialized game state: placement phase, active_seat=1
```

**Check that:**
- ✅ All units from both armies are in game state
- ✅ All units have position (-1, -1) = not placed
- ✅ Phase is "placement"
- ✅ Active seat is 1
- ✅ Turn is 1

### 3.2 Test Placement Actions (Manual RPC)

**Create temporary test script:** `godot/tests/test_placement_rpc.gd`

```gdscript
extends Node

func _ready() -> void:
	# Connect to server
	var peer = ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", 9999)
	multiplayer.multiplayer_peer = peer

	await get_tree().create_timer(1.0).timeout

	# Send placement action
	var action_data = {
		"type": "place_unit",
		"unit_id": "unit_0",
		"x": 10,
		"y": 30
	}
	request_action.rpc_id(1, action_data)

	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func _send_action_resolved(action: Dictionary, result: Dictionary) -> void:
	print("Received action_resolved: ", result)

@rpc("authority", "call_remote", "reliable")
func _send_state_update(state_data: Dictionary) -> void:
	print("Received state_update")
```

**Run:**
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_placement_rpc.gd
```

**Expected server console:**
```
[NetworkServer] Received request_action from peer 1234567890: {type: place_unit, unit_id: unit_0, x: 10, y: 30}
[GameEngine] Validating placement: unit_0 at (10, 30)
[GameEngine] Placement successful
```

**Expected client output:**
```
Received action_resolved: {success: true, description: "Unit placed at (10, 30)"}
Received state_update
```

### 3.3 Test Combat Actions (After Placement Complete)

**Similar test script for movement:**

```gdscript
var action_data = {
	"type": "move",
	"unit_id": "unit_0",
	"x": 15,
	"y": 25
}
request_action.rpc_id(1, action_data)
```

**Expected:**
- Server validates Manhattan distance ≤ movement stat
- Returns success or error
- Broadcasts new state

**Test shooting:**

```gdscript
var action_data = {
	"type": "shoot",
	"attacker_id": "unit_0",
	"target_id": "unit_5"
}
request_action.rpc_id(1, action_data)
```

**Expected:**
- Server rolls 3d6 (hit, wound, save)
- Calculates damage
- Updates target's current_wounds
- Broadcasts result with dice rolled

### 3.4 Test Victory Detection

**Simulate killing all enemy units:**

Keep attacking until only one player's units remain alive.

**Expected:**
- `check_victory()` returns winner seat and reason
- Server broadcasts `_send_game_ended`
- Game state phase becomes "finished"

---

## Part 4: Full Integration Test (Requires Client UI)

**Prerequisites:**
- Tasks from `docs/wiki/Phase-4-UI-Tasks.md` completed:
  - [x] Task 1: lobby.tscn updated with army UI
  - [x] Task 2: battle.tscn created
  - [x] Task 3: battle.gd implemented

### 4.1 Complete Game Flow Test

**Setup:**
1. Start server: `godot project.godot --server`
2. Start Client 1
3. Start Client 2

**Test Procedure:**

#### Step 1: Room Setup (5 minutes)
1. Client 1: Create room
2. Client 2: Join room
3. Both: Check ready
4. ✅ Verify: Player list shows both ready

#### Step 2: Army Submission (5 minutes)
1. Client 1: Roll army
2. Client 1: Submit army
3. Client 2: Roll army
4. Client 2: Submit army
5. ✅ Verify: Both transition to battle scene
6. ✅ Verify: Turn banner shows "Turn 1 - Player 1"

#### Step 3: Placement Phase (10 minutes)

**Client 1 (Seat 1, Active):**
1. Click grid at rows 28-31 to place units
2. ✅ Verify: Units appear as blue rectangles
3. ✅ Verify: Server accepts placements in deployment zone
4. ✅ Verify: Server rejects placements outside zone
5. Place all units
6. Click "Confirm Placement"
7. ✅ Verify: Turn banner changes to "Player 2 (Opponent's Turn)"

**Client 2 (Seat 2, Active):**
1. Click grid at rows 0-3 to place units
2. ✅ Verify: Units appear as red rectangles
3. Place all units
4. Click "Confirm Placement"
5. ✅ Verify: Turn banner changes to "Turn 1 - Player 1 (Your Turn)"
6. ✅ Verify: Phase transitions to "Combat"

#### Step 4: Combat Phase - Turn 1 (15 minutes)

**Client 1 (Active):**
1. Click friendly unit to select
2. ✅ Verify: Unit highlights in yellow
3. Click empty cell within movement range
4. ✅ Verify: Unit moves to new position
5. ✅ Verify: Action log shows "Unit moved to (x, y)"

**Attack with ranged unit:**
1. Select unit with ranged weapon
2. Click enemy unit within weapon range
3. ✅ Verify: Action log shows dice rolls
4. ✅ Verify: Action log shows hit/miss/damage result
5. ✅ Verify: Target's wounds update if hit

**Attack with melee unit:**
1. Select unit with melee weapon
2. Move adjacent to enemy
3. Click enemy unit
4. ✅ Verify: Charge action resolves
5. ✅ Verify: Combat results shown

**End activations:**
1. Activate remaining units (move or attack)
2. Click "End Turn"
3. ✅ Verify: Server validates all units activated
4. ✅ Verify: Turn banner shows "Player 2 (Your Turn)"

**Client 2 (Active):**
1. Repeat combat actions for Player 2
2. End turn
3. ✅ Verify: Turn increments to "Turn 2"

#### Step 5: Continue Until Victory (Variable)

**Keep playing until:**
- One player's units all dead
- ✅ Verify: Victory screen appears
- ✅ Verify: Winning player sees "Victory!"
- ✅ Verify: Losing player sees "Defeat"
- ✅ Verify: Reason displayed (e.g., "All enemy units eliminated")

---

## Part 5: Error Handling Tests

### 5.1 Invalid Actions

**Test invalid placement:**
1. Try placing unit outside deployment zone
2. ✅ Verify: Server returns error
3. ✅ Verify: Client displays error message
4. ✅ Verify: State doesn't change

**Test invalid movement:**
1. Try moving unit beyond movement range
2. ✅ Verify: Server rejects with error
3. ✅ Verify: Unit stays in original position

**Test invalid attack:**
1. Try shooting beyond weapon range
2. ✅ Verify: Server rejects
3. Try melee attack from non-adjacent position
4. ✅ Verify: Server rejects

### 5.2 Turn Ownership

**Test wrong player acting:**
1. Client 2: Try to act during Client 1's turn
2. ✅ Verify: Server rejects with "Not your turn"
3. ✅ Verify: No state change

### 5.3 Network Interruption

**Test client disconnect:**
1. During game, close Client 2 window
2. ✅ Verify: Server detects disconnect
3. ✅ Verify: Room cleaned up
4. ✅ Verify: Client 1 receives notification (if implemented)

**Test reconnection:**
1. Client 2 disconnects
2. Client 2 reconnects and rejoins
3. ✅ Verify: Game state not preserved (expected for MVP)
4. ✅ Verify: Room no longer exists or in invalid state

---

## Part 6: Performance Testing

### 6.1 Multiple Concurrent Games

**Setup:**
1. Start server
2. Create 3 rooms with different room codes
3. Have 6 clients (2 per room) play simultaneously

**Test:**
- ✅ Verify: All games run independently
- ✅ Verify: No state bleeding between rooms
- ✅ Verify: Server handles multiple request_action RPCs
- ✅ Verify: No significant lag

### 6.2 Long Games

**Test:**
1. Play a game with many units (8-10 per side)
2. Avoid killing units quickly
3. Play for 10+ turns

**Verify:**
- ✅ No memory leaks
- ✅ No slowdown over time
- ✅ Action log doesn't become unresponsive
- ✅ State updates remain fast

---

## Troubleshooting

### Issue: Server won't start

**Check:**
```bash
# Port in use?
lsof -i :9999

# Kill conflicting process
kill -9 <PID>
```

### Issue: Client can't connect

**Check:**
1. Server is running and listening
2. Firewall allows UDP port 9999
3. IP address is correct (127.0.0.1 for local)

**Test connection:**
```bash
nc -u -v 127.0.0.1 9999
```

### Issue: Army doesn't display after rolling

**Check:**
1. lobby.tscn has ArmyScrollContainer node
2. Node is named exactly "ArmyDisplay" (child of ScrollContainer)
3. Check console for errors

### Issue: Game doesn't start after both armies submitted

**Check server console for:**
- `_start_game` called
- Game state initialized
- `_send_game_started` broadcast

**Common causes:**
- Army validation failed (not 5-10 units)
- Network RPC not received
- battle.tscn doesn't exist (expected if UI not done)

### Issue: Actions rejected by server

**Check:**
1. It's your turn (active_seat matches your seat)
2. Unit belongs to you
3. Action is valid for current phase
4. Unit hasn't already activated (combat phase)

**Enable verbose logging:**
Add print statements in `network_server.gd` `request_action()`:
```gdscript
print("[NetworkServer] Action: ", action_data)
print("[NetworkServer] Active seat: ", state.active_seat)
print("[NetworkServer] Requesting peer seat: ", player["seat"])
```

### Issue: Tests fail

**Phase 1 tests:**
- Check working directory is `godot/`
- Verify mvp.json exists and is valid

**Phase 4 engine tests:**
- 6 failures expected (shooting edge cases)
- More failures = check recent code changes
- Review test output for specific errors

---

## Test Results Template

Copy this template to document your test results:

```markdown
# Phase 4 Test Results

**Date:** YYYY-MM-DD
**Tester:** [Name]
**Branch:** feature/phase-3b-4-battle
**Commit:** [git rev-parse HEAD]

## Automated Tests
- [ ] Phase 1 tests: ___/19 passing
- [ ] Phase 4 engine tests: ___/34 passing (6 expected failures)
- [ ] UI instantiation tests: ___/___ passing

## Phase 3b Army Submission
- [ ] Server starts successfully
- [ ] Clients connect to server
- [ ] Room creation works
- [ ] Room joining works
- [ ] Ready system works
- [ ] Army rolling displays units
- [ ] Army submission sends to server
- [ ] Both armies submitted triggers game start

## Phase 4 Server Integration
- [ ] Game state initializes correctly
- [ ] Placement actions validated
- [ ] Combat actions validated
- [ ] Turn switching works
- [ ] Victory detection works

## Phase 4 Client UI (Pending)
- [ ] Battle scene loads
- [ ] Units render on grid
- [ ] Placement phase UI works
- [ ] Combat phase UI works
- [ ] Action log displays
- [ ] Victory screen shows

## Error Handling
- [ ] Invalid actions rejected
- [ ] Turn ownership enforced
- [ ] Error messages displayed

## Issues Found
[List any bugs or unexpected behavior]

## Notes
[Additional observations]
```

---

## Next Steps

After completing these tests:

1. **If all automated tests pass:**
   - Proceed with client UI implementation
   - Follow `docs/wiki/Phase-4-UI-Tasks.md`

2. **If manual tests pass:**
   - Document results
   - Update GitHub issues
   - Create demo video (optional)

3. **If issues found:**
   - Create GitHub issues for bugs
   - Reference this testing guide in issue description
   - Include steps to reproduce

---

## References

- **Engine Tests:** `godot/tests/test_game_engine.gd`
- **UI Implementation Guide:** `docs/wiki/Phase-4-UI-Tasks.md`
- **Debugging Guide:** `docs/wiki/Debugging-Guide.md`
- **Server Code:** `godot/server/game_engine.gd`, `godot/server/network_server.gd`
- **Client Code:** `godot/client/scenes/lobby.gd`
