# Phase 3 Testing Instructions

## Automated Validation ✅

Scene instantiation test passed:
```bash
cd godot/
godot --headless --script tests/test_phase3_scenes.gd
# Result: PASSED - Server and lobby scenes load correctly
```

## Manual Testing (Two Clients + Server)

Phase 3 requires testing with a server and two client instances. You'll need to run Godot three times.

### Step 1: Start the Server

1. **Open Godot project:**
   ```bash
   cd godot/
   godot project.godot
   ```

2. **Configure for server mode:**
   - Go to Project → Project Settings → Run
   - Set "Main Run Args" to `--server`
   - Click "Run Project" (F5)

3. **Verify server startup:**
   - Console should show:
     ```
     [NetworkManager] Mode: SERVER
     [Server] Turnip28 server starting...
     [Server] ENet server listening on port 9999
     ```

### Step 2: Start First Client

1. **Open a second Godot instance** (or export the client binary)
2. **Run the project** (F5) — will start in client mode by default
3. **Navigate:** Click "Multiplayer Lobby"
4. **Connect to server:**
   - Server IP: `127.0.0.1` (already filled)
   - Your Name: `Alice`
   - Click "Connect to Server"
   - Should see: `Connected (ID: <peer_id>)`

5. **Create a room:**
   - Click "Create Room"
   - Should see the room code displayed (e.g., "Room: ABC123")
   - Players list should show: `1. Alice`

### Step 3: Start Second Client

1. **Open a third Godot instance** (or use exported binary)
2. **Run the project** (F5)
3. **Navigate:** Click "Multiplayer Lobby"
4. **Connect to server:**
   - Server IP: `127.0.0.1`
   - Your Name: `Bob`
   - Click "Connect to Server"

5. **Join the room:**
   - Room Code: `<code from Alice's screen>`
   - Click "Join Room"
   - Should see the room code and players list: `1. Alice` `2. Bob`

### Step 4: Test Ready System

1. **On Alice's client:**
   - Click "Ready" button
   - Button should toggle on
   - Both clients should see: `1. Alice [READY]`

2. **On Bob's client:**
   - Click "Ready" button
   - Both clients should see:
     ```
     1. Alice [READY]
     2. Bob [READY]
     ```

3. **Server console** should log all player ready changes

### Step 5: Test Disconnection

1. **Close Bob's client**
2. **On Alice's client:** Should see Bob removed from players list
3. **Server console:** Should log peer disconnect and room cleanup

## Expected Results

✅ Server listens on port 9999
✅ Clients connect with unique peer IDs
✅ Room codes are 6 uppercase characters (no I/O/0/1)
✅ Create room works, room code displayed
✅ Join room with correct code works
✅ Players list updates in real-time
✅ Ready status syncs across clients
✅ Disconnect handling cleans up players
✅ Empty rooms are deleted

## Known Limitations (Expected)

- No army submission yet (Phase 3b)
- No game start transition (Phase 3b)
- Max 2 players per room (design constraint)
- Server runs locally only (Phase 6 will deploy to VPS)

## Phase 3 Checkpoint

**Goal:** Two clients on my laptop connect to the local server, share a room code, see each other's names.

**Status:** ✅ READY FOR TESTING
