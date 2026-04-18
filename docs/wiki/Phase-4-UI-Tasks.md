# Phase 4: UI Implementation Tasks

**Status:** In Progress
**Project Board Issues:** [#17](https://github.com/rpmcdougall/turnipsim/issues/17), [#18](https://github.com/rpmcdougall/turnipsim/issues/18), [#19](https://github.com/rpmcdougall/turnipsim/issues/19)
**Branch:** `feature/phase-3b-4-battle`

This document provides step-by-step instructions for completing Phase 4 client UI work in the Godot editor.

---

## Overview

Phase 4 server-side implementation is **complete** (game engine, tests, RPC routing). The remaining work requires the Godot editor to:

1. **Update lobby.tscn** - Add army rolling UI elements ([#19](https://github.com/rpmcdougall/turnipsim/issues/19))
2. **Create battle.tscn** - Build battle scene structure ([#17](https://github.com/rpmcdougall/turnipsim/issues/17))
3. **Implement battle.gd** - Write battle UI logic ([#18](https://github.com/rpmcdougall/turnipsim/issues/18))

**Implementation order:**
- Task 1 first (enables army submission testing)
- Task 2 second (scene structure)
- Task 3 last (depends on Task 2)

---

## Task 1: Update lobby.tscn ([Issue #19](https://github.com/rpmcdougall/turnipsim/issues/19))

**Goal:** Add UI elements for rolling and submitting armies

**Code status:** `lobby.gd` logic is **already implemented** (commit aa2c746). We just need to add the UI nodes and connect them.

### Steps

#### 1.1 Open lobby.tscn in Godot Editor

```bash
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot
```

In Godot:
- Scene > Open Scene
- Navigate to `client/scenes/lobby.tscn`
- Click "Open"

#### 1.2 Locate InRoomPanel

In the Scene tree (left panel):
```
Lobby (Control)
└── Panels (CanvasLayer)
    └── InRoomPanel (Panel)
        └── VBoxContainer
            ├── RoomCodeLabel (Label)
            ├── PlayersLabel (Label)
            ├── PlayersList (VBoxContainer)
            ├── ReadyCheckbox (CheckBox)
            └── LeaveRoomButton (Button)
```

We'll add new nodes as siblings to `ReadyCheckbox`.

#### 1.3 Add RollArmyButton

1. **Right-click** on `VBoxContainer` under `InRoomPanel`
2. Select **Add Child Node**
3. Search for `Button`
4. Click **Create**
5. Rename node to `RollArmyButton`
6. In Inspector (right panel):
   - **Text:** "Roll Army"
   - **Custom Minimum Size > Y:** 40

#### 1.4 Add ArmyDisplay (ScrollContainer)

1. **Right-click** on `VBoxContainer` under `InRoomPanel`
2. Select **Add Child Node**
3. Search for `ScrollContainer`
4. Click **Create**
5. Rename to `ArmyScrollContainer`
6. In Inspector:
   - **Custom Minimum Size > Y:** 200
   - **Horizontal Scroll Mode:** Disabled
   - **Vertical Scroll Mode:** Auto

7. **Right-click** on `ArmyScrollContainer`
8. Select **Add Child Node**
9. Search for `VBoxContainer`
10. Click **Create**
11. Rename to `ArmyDisplay`
12. In Inspector:
    - **Size Flags > Horizontal:** Fill
    - **Size Flags > Vertical:** Fill

#### 1.5 Add SubmitArmyButton

1. **Right-click** on `VBoxContainer` under `InRoomPanel`
2. Select **Add Child Node**
3. Search for `Button`
4. Click **Create**
5. Rename to `SubmitArmyButton`
6. In Inspector:
   - **Text:** "Submit Army"
   - **Disabled:** true (will be enabled after rolling)
   - **Custom Minimum Size > Y:** 40

#### 1.6 Connect Signals

**Connect RollArmyButton:**
1. Select `RollArmyButton` in Scene tree
2. Click **Node** tab (right panel, next to Inspector)
3. Double-click `pressed()` signal
4. In dialog:
   - **Receiver Method:** `_on_roll_army_button_pressed`
   - Click **Connect**

**Connect SubmitArmyButton:**
1. Select `SubmitArmyButton` in Scene tree
2. Click **Node** tab
3. Double-click `pressed()` signal
4. In dialog:
   - **Receiver Method:** `_on_submit_army_button_pressed`
   - Click **Connect**

#### 1.7 Reorder Nodes (Optional)

For better UI flow, reorder nodes in `VBoxContainer`:

1. RoomCodeLabel
2. PlayersLabel
3. PlayersList
4. ReadyCheckbox
5. **RollArmyButton** (new)
6. **ArmyScrollContainer** (new)
7. **SubmitArmyButton** (new)
8. LeaveRoomButton

Drag nodes in Scene tree to reorder.

#### 1.8 Save and Test

1. **File > Save Scene** (Ctrl/Cmd+S)
2. Run client: Click **Play** button (F5)
3. Go to Multiplayer Lobby
4. Create a room
5. Verify new buttons appear
6. Click "Roll Army" - should display units
7. Click "Submit Army" - should send to server (if connected)

**Expected behavior:**
- Roll Army button generates and displays army
- Army shown in scrollable container
- Submit Army button enabled after rolling
- Clicking Submit sends army to server

---

## Task 2: Create battle.tscn ([Issue #17](https://github.com/rpmcdougall/turnipsim/issues/17))

**Goal:** Build the battle scene structure with TileMap, UI panels, and placeholders for units.

### Steps

#### 2.1 Create New Scene

In Godot:
1. **Scene > New Scene**
2. Click **Other Node**
3. Search for `Control`
4. Click **Create**
5. Rename root node to `Battle`

#### 2.2 Add TileMap

1. **Right-click** on `Battle`
2. **Add Child Node**
3. Search for `TileMap`
4. Click **Create**
5. Rename to `BoardTileMap`

6. In Inspector:
   - **Cell > Quadrant Size:** 16
   - **Cell > Custom Transform > x:** 16, 0
   - **Cell > Custom Transform > y:** 0, 16

7. **Create TileSet:**
   - In Inspector, click **Tile Set** property
   - Select **New TileSet**
   - Click the new TileSet to edit it

8. **Add placeholder tile source:**
   - In TileSet panel (bottom), click **+** button
   - Select **Atlas**
   - For now, use a simple colored image:
     - Create a 16x16 white square image
     - Or use Godot's built-in white texture
   - This is just a placeholder for MVP

**Note:** For MVP, we'll use simple colored tiles. Proper terrain graphics come in Phase 5.

#### 2.3 Add UnitsContainer

1. **Right-click** on `Battle`
2. **Add Child Node**
3. Search for `Node2D`
4. Click **Create**
5. Rename to `UnitsContainer`

This will hold dynamically created unit sprites during gameplay.

#### 2.4 Add UI Layer

1. **Right-click** on `Battle`
2. **Add Child Node**
3. Search for `CanvasLayer`
4. Click **Create**
5. Rename to `UI`

#### 2.5 Add TurnBanner

1. **Right-click** on `UI`
2. **Add Child Node**
3. Search for `Label`
4. Click **Create**
5. Rename to `TurnBanner`

6. In Inspector:
   - **Layout > Anchors Preset:** Top Wide
   - **Text:** "Turn 1 - Player 1 (Your Turn)"
   - **Horizontal Alignment:** Center
   - **Vertical Alignment:** Center
   - **Custom Minimum Size > Y:** 50

7. Add theme styling (optional):
   - **Theme Overrides > Font Sizes > Font Size:** 24
   - **Theme Overrides > Colors > Font Color:** White

#### 2.6 Add PlacementPanel

1. **Right-click** on `UI`
2. **Add Child Node**
3. Search for `Panel`
4. Click **Create**
5. Rename to `PlacementPanel`

6. In Inspector:
   - **Layout > Anchors Preset:** Bottom Wide
   - **Offset > Top:** -100 (from bottom)
   - **Offset > Left:** 0
   - **Offset > Right:** 0
   - **Offset > Bottom:** 0

7. **Right-click** on `PlacementPanel`
8. **Add Child Node > VBoxContainer**
9. Rename to `PlacementContent`

10. **Right-click** on `PlacementContent`
11. **Add Child Node > Label**
12. Set **Text:** "Placement Phase - Click grid to place units"

13. **Right-click** on `PlacementContent`
14. **Add Child Node > Button**
15. Rename to `ConfirmPlacementButton`
16. Set **Text:** "Confirm Placement"

#### 2.7 Add CombatPanel

1. **Right-click** on `UI`
2. **Add Child Node**
3. Search for `Panel`
4. Click **Create**
5. Rename to `CombatPanel`

6. In Inspector:
   - **Layout > Anchors Preset:** Bottom Wide
   - **Offset > Top:** -100
   - **Visible:** false (hidden by default, shown during combat)

7. **Right-click** on `CombatPanel`
8. **Add Child Node > HBoxContainer**
9. Rename to `CombatActions`

10. Add action buttons (repeat for each):
    - **Right-click** on `CombatActions`
    - **Add Child Node > Button**
    - Rename: `EndActivationButton`
    - Text: "End Activation"

    - Repeat for `EndTurnButton`
    - Text: "End Turn"

#### 2.8 Add ActionLogPanel

1. **Right-click** on `UI`
2. **Add Child Node > Panel**
3. Rename to `ActionLogPanel`

4. In Inspector:
   - **Layout > Anchors Preset:** Right Wide
   - **Offset > Left:** -300 (from right)
   - **Offset > Top:** 60 (below turn banner)
   - **Offset > Right:** 0
   - **Offset > Bottom:** -110 (above combat panel)

5. **Right-click** on `ActionLogPanel`
6. **Add Child Node > VBoxContainer**
7. Rename to `ActionLogContainer`

8. **Right-click** on `ActionLogContainer`
9. **Add Child Node > Label**
10. Rename to `ActionLogTitle`
11. Set **Text:** "Action Log"

12. **Right-click** on `ActionLogContainer`
13. **Add Child Node > ScrollContainer**
14. Rename to `ActionLogScroll`

15. In Inspector:
    - **Size Flags > Vertical:** Expand Fill
    - **Horizontal Scroll Mode:** Disabled

16. **Right-click** on `ActionLogScroll`
17. **Add Child Node > VBoxContainer**
18. Rename to `ActionLogContent`

#### 2.9 Attach Script

1. Select `Battle` (root node)
2. **Right-click > Attach Script**
3. **Path:** `res://client/scenes/battle.gd`
4. **Template:** Empty
5. Click **Create**

This creates a skeleton `battle.gd` file. We'll implement it in Task 3.

#### 2.10 Set Initial Visibility

To ensure correct panels show for each phase:

**PlacementPanel:**
- Select in Scene tree
- Inspector > **Visible:** true

**CombatPanel:**
- Select in Scene tree
- Inspector > **Visible:** false

#### 2.11 Save Scene

1. **File > Save Scene** (Ctrl/Cmd+S)
2. **Path:** `res://client/scenes/battle.tscn`
3. Click **Save**

#### 2.12 Test Scene

1. **Scene > Run Current Scene** (F6)
2. Verify:
   - TileMap visible (placeholder tiles)
   - Turn banner at top
   - Placement panel at bottom (visible)
   - Combat panel hidden
   - Action log on right side

**Expected result:**
- Scene loads without errors
- UI layout looks reasonable
- No gameplay functionality yet (that's Task 3)

---

## Task 3: Implement battle.gd ([Issue #18](https://github.com/rpmcdougall/turnipsim/issues/18))

**Goal:** Write battle UI logic for state rendering, input handling, and RPC communication.

**Prerequisites:**
- Task 2 complete (battle.tscn exists)
- Server running and accessible

### File Structure

Create `godot/client/scenes/battle.gd` with ~300-400 lines implementing:

1. **State Management** - Track game state, selected unit
2. **Rendering** - Display state, units, turn info
3. **Input Handling** - Mouse clicks on grid
4. **RPC Handlers** - Receive state updates from server
5. **Action Requests** - Send player actions to server

### Steps

#### 3.1 Create Script Template

If not already created in Task 2:

1. Open `battle.tscn`
2. Select `Battle` root node
3. **Right-click > Attach Script**
4. **Path:** `res://client/scenes/battle.gd`
5. Click **Create**

#### 3.2 Implement Battle Script

**Full implementation:** `godot/client/scenes/battle.gd`

```gdscript
extends Control
## Battle scene - Client-side battle UI
##
## Renders game state, handles input, sends action requests to server

# Node references
@onready var board_tilemap: TileMap = $BoardTileMap
@onready var units_container: Node2D = $UnitsContainer
@onready var turn_banner: Label = $UI/TurnBanner
@onready var placement_panel: Panel = $UI/PlacementPanel
@onready var combat_panel: Panel = $UI/CombatPanel
@onready var action_log_content: VBoxContainer = $UI/ActionLogPanel/ActionLogContainer/ActionLogScroll/ActionLogContent
@onready var confirm_placement_button: Button = $UI/PlacementPanel/PlacementContent/ConfirmPlacementButton

# Game state
var current_game_state: Types.GameState = null
var my_seat: int = 0
var selected_unit_id: String = ""
var unit_sprites: Dictionary = {}  # unit_id -> Sprite2D

# Constants
const CELL_SIZE: int = 16


func _ready() -> void:
	# Get player's seat from NetworkManager
	my_seat = NetworkManager.my_seat
	print("[Battle] My seat: %d" % my_seat)

	# Connect button signals
	confirm_placement_button.pressed.connect(_on_confirm_placement_pressed)
	$UI/CombatPanel/CombatActions/EndActivationButton.pressed.connect(_on_end_activation_pressed)
	$UI/CombatPanel/CombatActions/EndTurnButton.pressed.connect(_on_end_turn_pressed)

	# Initial state will come from server via _send_game_started
	_log_action("Battle started - Waiting for game state from server")


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_game_state == null:
			return

		# Convert mouse position to grid coordinates
		var mouse_pos = get_global_mouse_position()
		var grid_x = int(mouse_pos.x / CELL_SIZE)
		var grid_y = int(mouse_pos.y / CELL_SIZE)

		# Handle click based on phase
		match current_game_state.phase:
			"placement":
				_handle_placement_click(grid_x, grid_y)
			"combat":
				_handle_combat_click(grid_x, grid_y)


func _handle_placement_click(x: int, y: int) -> void:
	if current_game_state.active_seat != my_seat:
		_log_action("Not your turn")
		return

	# Find first unplaced unit owned by player
	var unit_to_place: Types.UnitState = null
	for unit in current_game_state.units:
		if unit.owner_seat == my_seat and unit.x == -1 and unit.y == -1:
			unit_to_place = unit
			break

	if unit_to_place == null:
		_log_action("All units placed - click Confirm Placement")
		return

	# Send placement request
	var action_data = {
		"type": "place_unit",
		"unit_id": unit_to_place.id,
		"x": x,
		"y": y
	}
	request_action.rpc_id(1, action_data)


func _handle_combat_click(x: int, y: int) -> void:
	if current_game_state.active_seat != my_seat:
		_log_action("Not your turn")
		return

	# Check if clicking on a unit
	var clicked_unit: Types.UnitState = null
	for unit in current_game_state.units:
		if unit.x == x and unit.y == y and not unit.is_dead:
			clicked_unit = unit
			break

	if clicked_unit != null:
		if clicked_unit.owner_seat == my_seat:
			# Select own unit
			selected_unit_id = clicked_unit.id
			_log_action("Selected: %s" % clicked_unit.name)
			_render_state()  # Re-render to show selection
		else:
			# Attack enemy unit
			if selected_unit_id.is_empty():
				_log_action("Select your unit first")
				return

			_attack_unit(selected_unit_id, clicked_unit.id)
	else:
		# Clicked empty cell - try to move selected unit
		if selected_unit_id.is_empty():
			_log_action("Select a unit first")
			return

		_move_unit(selected_unit_id, x, y)


func _move_unit(unit_id: String, x: int, y: int) -> void:
	var action_data = {
		"type": "move",
		"unit_id": unit_id,
		"x": x,
		"y": y
	}
	request_action.rpc_id(1, action_data)


func _attack_unit(attacker_id: String, target_id: String) -> void:
	# Determine attack type based on weapon
	var attacker: Types.UnitState = null
	for unit in current_game_state.units:
		if unit.id == attacker_id:
			attacker = unit
			break

	if attacker == null:
		return

	var action_type = "charge" if attacker.weapon.type == "melee" else "shoot"

	var action_data = {
		"type": action_type,
		"attacker_id": attacker_id,
		"target_id": target_id
	}
	request_action.rpc_id(1, action_data)


func _on_confirm_placement_pressed() -> void:
	var action_data = {
		"type": "confirm_placement"
	}
	request_action.rpc_id(1, action_data)


func _on_end_activation_pressed() -> void:
	if selected_unit_id.is_empty():
		_log_action("Select a unit first")
		return

	var action_data = {
		"type": "end_activation",
		"unit_id": selected_unit_id
	}
	request_action.rpc_id(1, action_data)


func _on_end_turn_pressed() -> void:
	var action_data = {
		"type": "end_turn"
	}
	request_action.rpc_id(1, action_data)


func _render_state() -> void:
	if current_game_state == null:
		return

	# Update turn banner
	var turn_text = "Turn %d - Player %d" % [current_game_state.current_turn, current_game_state.active_seat]
	if current_game_state.active_seat == my_seat:
		turn_text += " (Your Turn)"
	else:
		turn_text += " (Opponent's Turn)"
	turn_banner.text = turn_text

	# Show/hide panels based on phase
	placement_panel.visible = (current_game_state.phase == "placement")
	combat_panel.visible = (current_game_state.phase == "combat")

	# Render units
	_render_units()


func _render_units() -> void:
	# Clear existing sprites
	for child in units_container.get_children():
		child.queue_free()
	unit_sprites.clear()

	# Create sprite for each placed, living unit
	for unit in current_game_state.units:
		if unit.x == -1 or unit.y == -1 or unit.is_dead:
			continue

		var sprite = ColorRect.new()
		sprite.custom_minimum_size = Vector2(CELL_SIZE - 2, CELL_SIZE - 2)
		sprite.position = Vector2(unit.x * CELL_SIZE + 1, unit.y * CELL_SIZE + 1)

		# Color by seat
		if unit.owner_seat == 1:
			sprite.color = Color.BLUE
		else:
			sprite.color = Color.RED

		# Highlight selected unit
		if unit.id == selected_unit_id:
			sprite.color = Color.YELLOW

		# Add label with unit name
		var label = Label.new()
		label.text = unit.name.substr(0, 1)  # First letter
		label.position = Vector2(2, 0)
		sprite.add_child(label)

		units_container.add_child(sprite)
		unit_sprites[unit.id] = sprite


func _log_action(message: String) -> void:
	var label = Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_log_content.add_child(label)

	# Auto-scroll to bottom
	await get_tree().process_frame
	var scroll = $UI/ActionLogPanel/ActionLogContainer/ActionLogScroll
	scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value


# ============================================================================
# RPC Handlers (Server → Client)
# ============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_game_started(game_state: Dictionary) -> void:
	print("[Battle] Received game_started")
	current_game_state = Types.GameState.from_dict(game_state)
	_render_state()
	_log_action("Game started - Phase: %s" % current_game_state.phase)


@rpc("authority", "call_remote", "reliable")
func _send_state_update(state_data: Dictionary) -> void:
	current_game_state = Types.GameState.from_dict(state_data)
	_render_state()


@rpc("authority", "call_remote", "reliable")
func _send_action_resolved(action: Dictionary, result: Dictionary) -> void:
	var result_obj = Types.EngineResult.from_dict(result)
	_log_action(result_obj.description)

	# Deselect unit after action
	if action.get("type") in ["shoot", "charge", "end_activation"]:
		selected_unit_id = ""


@rpc("authority", "call_remote", "reliable")
func _send_game_ended(winner_seat: int, reason: String) -> void:
	var message = ""
	if winner_seat == my_seat:
		message = "Victory! " + reason
	else:
		message = "Defeat. " + reason

	_log_action(message)
	turn_banner.text = message


@rpc("authority", "call_remote", "reliable")
func _send_error(message: String) -> void:
	_log_action("Error: " + message)


# ============================================================================
# RPC Stubs (Client → Server)
# ============================================================================

@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	pass  # Server handles this
```

#### 3.3 Update lobby.gd Transition

Open `godot/client/scenes/lobby.gd` and find the `_send_game_started` handler.

Update it to transition to battle scene:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _send_game_started(game_state: Dictionary) -> void:
	print("[Lobby] Game started, transitioning to battle")

	# Store seat assignment (already in NetworkManager from room join)

	# Transition to battle scene
	get_tree().change_scene_to_file("res://client/scenes/battle.tscn")
```

#### 3.4 Test Battle Implementation

**Manual integration test:**

1. **Start server:**
   ```bash
   cd godot/
   /Applications/Godot.app/Contents/MacOS/Godot project.godot --server
   ```

2. **Start two clients:**
   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot project.godot &
   /Applications/Godot.app/Contents/MacOS/Godot project.godot &
   ```

3. **Test flow:**
   - Client 1: Multiplayer Lobby > Create Room
   - Client 2: Multiplayer Lobby > Join Room (enter code)
   - Both: Check ready
   - Both: Click "Roll Army"
   - Both: Click "Submit Army"
   - **Expected:** Both clients transition to battle.tscn
   - **Expected:** Turn banner shows "Turn 1 - Player 1 (Your Turn)" or "(Opponent's Turn)"
   - Client 1: Click grid to place units
   - **Expected:** Units appear as blue/red colored rectangles
   - Continue placement, confirm, test combat

4. **Verify:**
   - ✅ State renders correctly
   - ✅ Turn banner updates
   - ✅ Placement phase works
   - ✅ Combat phase works (move, shoot, charge)
   - ✅ Action log updates
   - ✅ Victory detection works

---

## Verification Checklist

After completing all tasks:

### Task 1: Lobby UI
- [ ] RollArmyButton exists and works
- [ ] ArmyDisplay shows rolled units
- [ ] SubmitArmyButton enabled after rolling
- [ ] Server receives army submission

### Task 2: Battle Scene
- [ ] battle.tscn loads without errors
- [ ] TileMap visible
- [ ] UI panels present (turn banner, placement, combat, log)
- [ ] PlacementPanel visible by default
- [ ] CombatPanel hidden by default

### Task 3: Battle Logic
- [ ] Clients transition to battle after both armies submitted
- [ ] Turn banner shows correct turn/player
- [ ] Placement phase: click grid places units
- [ ] Combat phase: select unit, move, attack works
- [ ] Action log updates with descriptions
- [ ] Victory screen shows when game ends
- [ ] Error messages display

### Integration
- [ ] Full game flow: lobby → roll → submit → place → combat → victory
- [ ] Two clients can play against each other
- [ ] Server validates all actions
- [ ] State synchronizes between clients

---

## Troubleshooting

### Issue: Nodes not found in battle.gd

**Symptom:** Error like "Invalid get index '@onready' on base 'null instance'"

**Solution:**
- Verify node paths in battle.gd match scene tree exactly
- Check node names (case-sensitive)
- Use `$` syntax or `get_node()` correctly

### Issue: RPC not received

**Symptom:** Client sends action, server doesn't respond

**Solution:**
- Verify RPC signatures match on client and server
- Check `_send_*` functions exist in both `battle.gd` and `network_server.gd`
- Add print statements to verify RPC calls

### Issue: Units not rendering

**Symptom:** State updates but no sprites visible

**Solution:**
- Check `units_container` exists
- Verify `_render_units()` creates sprites
- Check unit positions (x, y) are valid
- Ensure `CELL_SIZE` matches TileMap

### Issue: Transition to battle fails

**Symptom:** Scene doesn't load after army submission

**Solution:**
- Verify `battle.tscn` saved correctly
- Check path: `res://client/scenes/battle.tscn`
- Add error handling to `change_scene_to_file()`

---

## Project Board Updates

After completing each task:

### Update Issue #19 (Lobby UI)
```bash
gh issue comment 19 --body "✅ Completed lobby.tscn updates:
- Added RollArmyButton, ArmyScrollContainer, SubmitArmyButton
- Connected signals to existing lobby.gd handlers
- Tested: army rolling and submission works"
```

### Update Issue #17 (Battle Scene)
```bash
gh issue comment 17 --body "✅ Completed battle.tscn scene structure:
- Created TileMap (48x32 grid)
- Added UI panels (placement, combat, action log)
- Turn banner and button controls in place
- Ready for battle.gd implementation"
```

### Update Issue #18 (Battle Logic)
```bash
gh issue comment 18 --body "✅ Completed battle.gd implementation:
- State rendering (units, turn info, panels)
- Input handling (placement, movement, attacks)
- RPC handlers (state updates, action results, victory)
- Tested: full game flow from placement through combat"
```

### Move to Done
```bash
# Get project item IDs
gh project item-list 1 --owner rpmcdougall --format json | jq -r '.items[] | select(.content.number == 17 or .content.number == 18 or .content.number == 19) | "\(.id) \(.content.number)"'

# Mark as Done (replace ITEM_ID with actual IDs)
gh project item-edit --id PVTI_xxx --field-id PVTSSF_lAHOAG78Fc4BU8gpzhMIc_o --single-select-option-id 98236657
```

---

## See Also

- [Development Process](Development-Process.md) - Committing and PR workflow
- [Testing Guidelines](Testing-Guidelines.md) - Manual testing procedures
- [Debugging Guide](Debugging-Guide.md) - Troubleshooting UI issues
- [MEMORY.md](../../MEMORY.md) - Current project status
