# Debugging Guide

Common issues, troubleshooting steps, and debugging techniques for Turnip28 Simulator.

## General Debugging Workflow

1. **Read the error message** - Godot provides clear stack traces
2. **Check recent changes** - `git diff`, `git log`
3. **Isolate the problem** - Minimal reproduction
4. **Add logging** - `print()` statements liberally
5. **Use debugger** - Godot's built-in debugger
6. **Check documentation** - MEMORY.md, checkpoints, wiki

## Common Issues

### Server Won't Start

**Symptom:** Server exits immediately or hangs

**Possible causes:**

1. **Port 9999 already in use**
   ```bash
   # Check what's using port 9999
   lsof -i :9999

   # Kill the process
   kill -9 <PID>
   ```

2. **Wrong Godot version**
   ```bash
   # Check version
   /Applications/Godot.app/Contents/MacOS/Godot --version
   # Should be 4.6.2.stable.official
   ```

3. **Missing --server flag**
   ```bash
   # Wrong
   /Applications/Godot.app/Contents/MacOS/Godot project.godot

   # Correct
   /Applications/Godot.app/Contents/MacOS/Godot project.godot --server
   ```

**Debug steps:**
```bash
# Run with verbose output
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server --verbose

# Check console for errors
# Look for port binding errors, missing files
```

### Client Can't Connect to Server

**Symptom:** "Connection failed" or timeout

**Possible causes:**

1. **Server not running**
   - Start server first: `godot project.godot --server`
   - Check server console for "listening on *:9999"

2. **Wrong IP address**
   - For local testing, use `127.0.0.1:9999`
   - For LAN, use server's local IP (e.g., `192.168.1.100:9999`)

3. **Firewall blocking**
   ```bash
   # macOS: Allow Godot through firewall
   # System Preferences > Security & Privacy > Firewall > Firewall Options
   # Add Godot.app, allow incoming connections

   # Linux: Check iptables
   sudo iptables -L -n | grep 9999
   ```

**Debug steps:**
```bash
# Test UDP port is open
nc -u -v 127.0.0.1 9999

# On server, verify it's listening
lsof -i :9999
```

### Tests Failing

**Symptom:** Tests exit with code 1, failures reported

**Possible causes:**

1. **Wrong working directory**
   ```bash
   # Wrong - run from repo root
   /Applications/Godot.app/Contents/MacOS/Godot --headless -s godot/tests/test_runner.gd

   # Correct - run from godot/
   cd godot/
   /Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_runner.gd
   ```

2. **Typed array assignment**
   ```gdscript
   # Wrong - fails with typed arrays
   var units: Array[UnitState] = []
   units = [unit1, unit2]  # Error!

   # Correct
   var units: Array[UnitState] = []
   units.append(unit1)
   units.append(unit2)
   ```

3. **Missing dependencies** (scenes, resources)
   ```
   # Error: "res://game/rulesets/mvp.json" not found
   # → Check file exists, path is correct
   ```

**Debug steps:**
```bash
# Run tests without --headless to see Godot output window
/Applications/Godot.app/Contents/MacOS/Godot -s tests/test_runner.gd

# Add verbose logging to failing test
func _test_failing_case() -> void:
	print("State before: %s" % state.to_dict())
	var result = GameEngine.my_function(state)
	print("Result: %s" % result.to_dict())
	# ...
```

### RPC Not Received

**Symptom:** Client sends RPC, server doesn't receive (or vice versa)

**Possible causes:**

1. **RPC not registered on both sides**
   ```gdscript
   # Both client AND server must declare RPC signatures

   # Client-side (sends):
   @rpc("any_peer", "call_remote", "reliable")
   func request_action(action_data: Dictionary) -> void:
   	pass  # Stub only

   # Server-side (receives and implements):
   @rpc("any_peer", "call_remote", "reliable")
   func request_action(action_data: Dictionary) -> void:
   	# Actual implementation
   	var peer_id = multiplayer.get_remote_sender_id()
   	# ...
   ```

2. **Wrong RPC call syntax**
   ```gdscript
   # Wrong
   request_action.rpc(action_data)  # Sends to ALL peers

   # Correct (client → server)
   request_action.rpc_id(1, action_data)  # 1 = server
   ```

3. **Multiplayer not initialized**
   - Ensure client connected before sending RPCs
   - Check `multiplayer.get_unique_id() != 1` before sending

**Debug steps:**
```gdscript
# Server: Add logging to RPC handlers
@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[Server] Received request_action from peer %d: %s" % [peer_id, action_data])
	# ...

# Client: Log before sending
print("[Client] Sending request_action: %s" % action_data)
request_action.rpc_id(1, action_data)
```

### Scene Won't Load

**Symptom:** `change_scene_to_file()` fails, errors about missing scene

**Possible causes:**

1. **Wrong path**
   ```gdscript
   # Wrong - relative path
   get_tree().change_scene_to_file("client/main.tscn")

   # Correct - res:// path
   get_tree().change_scene_to_file("res://client/main.tscn")
   ```

2. **Scene doesn't exist**
   - Verify file exists in godot/ folder
   - Check .tscn vs .scn extension

3. **Scene has errors**
   - Open in Godot editor
   - Check for missing scripts, broken node references

**Debug steps:**
```gdscript
# Check if file exists before loading
var path = "res://client/main.tscn"
if ResourceLoader.exists(path):
	get_tree().change_scene_to_file(path)
else:
	print("ERROR: Scene not found: %s" % path)
```

### Typed Array Errors

**Symptom:** "Invalid assignment of property 'units' with value of type 'Array'"

**Cause:** GDScript typed arrays (`Array[Type]`) have special behavior

**Solutions:**

```gdscript
# Problem: Direct assignment fails
var units: Array[UnitState] = []
units = [unit1, unit2]  # ❌ Error

# Solution 1: Use append
var units: Array[UnitState] = []
units.append(unit1)
units.append(unit2)  # ✅ Works

# Solution 2: Use untyped intermediate
var units: Array[UnitState] = []
var temp = [unit1, unit2]
for unit in temp:
	units.append(unit)  # ✅ Works

# Solution 3: Don't use typed arrays (not recommended)
var units: Array = []
units = [unit1, unit2]  # ✅ Works but loses type safety
```

## Debugging Techniques

### Print Debugging

**Basic logging:**
```gdscript
print("Variable x:", x)
print("State:", state.to_dict())
```

**Conditional logging:**
```gdscript
const DEBUG = true

func debug_log(message: String) -> void:
	if DEBUG:
		print("[DEBUG] %s" % message)

debug_log("Processing action: " + action_type)
```

**Pretty-print dictionaries:**
```gdscript
print(JSON.stringify(state.to_dict(), "\t"))
```

### Godot Debugger

1. **Set breakpoints** in Godot editor (click line number gutter)
2. **Run with debugger attached** (F5 or Play button)
3. **Inspect variables** in debugger panel
4. **Step through code** (F10 = step over, F11 = step into)

**Limitations:**
- Doesn't work with `--headless` mode
- Can't debug server if run from command line

### Assertion Debugging

```gdscript
# Crash immediately if condition false (debug builds only)
assert(units.size() > 0, "Units array should not be empty")
assert(active_seat == 1 or active_seat == 2, "Invalid seat: " + str(active_seat))

# Note: Assertions disabled in release builds
```

### Git Bisect

**Find which commit introduced a bug:**

```bash
# Start bisect
git bisect start
git bisect bad  # Current commit is broken
git bisect good d1d3bc0  # This old commit worked

# Git checks out middle commit
# Test if bug exists
godot --headless -s tests/test_game_engine.gd

# Mark commit as good or bad
git bisect good  # or git bisect bad

# Repeat until git identifies first bad commit
# Reset when done
git bisect reset
```

### Network Debugging

**Wireshark to inspect UDP packets:**

```bash
# macOS
brew install wireshark

# Start capture on loopback interface
# Filter: udp.port == 9999
```

**ENet debug output:**
```gdscript
# In server_main.gd
var peer = ENetMultiplayerPeer.new()
peer.create_server(9999, 32)
peer.set_compression_mode(ENetMultiplayerPeer.COMPRESS_NONE)  # Easier to debug

# Enable Godot network profiler
# Editor > Debugger > Network Profiler
```

## Performance Debugging

### Profiling

**Godot Profiler:**
1. Run client/server in editor (not headless)
2. Open Debugger > Profiler
3. Watch for slow functions

**Manual timing:**
```gdscript
var start_time = Time.get_ticks_msec()
# ... code to profile ...
var elapsed = Time.get_ticks_msec() - start_time
print("Function took %d ms" % elapsed)
```

### Memory Leaks

**Check for unreleased objects:**
```gdscript
# Godot monitors RefCounted automatically
# Use print_orphan_nodes() to find leaks

func _exit_tree() -> void:
	print_orphan_nodes()
```

**Common leak sources:**
- Circular references (A → B → A)
- Signals not disconnected
- Timers not stopped

## Logging Best Practices

### Structured Logging

```gdscript
# Add context to log messages
print("[%s] %s" % [get_class(), message])
print("[NetworkServer] Peer %d created room %s" % [peer_id, code])

# Include timestamps for debugging timing issues
print("[%s] %s" % [Time.get_datetime_string_from_system(), message])
```

### Log Levels

```gdscript
enum LogLevel { DEBUG, INFO, WARN, ERROR }
var log_level: LogLevel = LogLevel.INFO

func log(level: LogLevel, message: String) -> void:
	if level >= log_level:
		var prefix = ["DEBUG", "INFO", "WARN", "ERROR"][level]
		print("[%s] %s" % [prefix, message])

# Usage
log(LogLevel.DEBUG, "Entering function")
log(LogLevel.ERROR, "Failed to parse JSON")
```

## Error Messages

### Interpreting Godot Errors

**"Identifier not declared in current scope"**
- Variable/function name typo
- Missing import/preload
- Accessing before declaration

**"Invalid call. Nonexistent function in base"**
- Calling function on wrong type
- Function name typo
- Object is null

**"Cannot assign value of type X to variable of type Y"**
- Type mismatch
- Check typed arrays (`Array[Type]`)
- Use explicit casting if needed

**"Invalid get index 'property' (on base: 'Dictionary')"**
- Dictionary key doesn't exist
- Use `get(key, default)` or `has(key)` first

### Custom Error Messages

```gdscript
# Use EngineResult pattern for clear errors
if not unit:
	return EngineResult.error("Unit '%s' not found in state" % unit_id)

if unit.owner_seat != state.active_seat:
	return EngineResult.error(
		"Unit belongs to seat %d but active seat is %d" % [unit.owner_seat, state.active_seat]
	)
```

## Debugging Checklist

**Before asking for help:**

- [ ] Read the full error message and stack trace
- [ ] Check git diff for recent changes
- [ ] Try minimal reproduction (isolate the problem)
- [ ] Add print() statements around the issue
- [ ] Check MEMORY.md and checkpoints for context
- [ ] Search codebase for similar patterns
- [ ] Review relevant wiki pages
- [ ] Check GitHub issues for similar problems

**Information to provide when reporting bugs:**

- Exact error message and stack trace
- Steps to reproduce
- Expected vs actual behavior
- Godot version (`godot --version`)
- Git commit hash (`git rev-parse HEAD`)
- Platform (macOS, Linux, Windows)
- Relevant code snippets

## See Also

- [Testing Guidelines](Testing-Guidelines.md) - Writing tests to catch bugs
- [Code Style Guide](Code-Style-Guide.md) - Patterns that avoid common issues
- [Architecture Overview](Architecture-Overview.md) - Understanding system design
- [Codebase Tour](Codebase-Tour.md) - Finding relevant code
