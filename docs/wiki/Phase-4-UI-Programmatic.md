# Phase 4: UI Implementation (Programmatic)

**Alternative to manual Godot editor work**

This guide shows how to implement Phase 4 client UI entirely in code, without opening the Godot editor. All UI elements are created programmatically.

**Advantages:**
- No manual editor work required
- Everything version controlled in code
- Can be implemented via Claude Code
- Easier to review in PRs

**Disadvantages:**
- Harder to tweak visually
- More code to write initially
- Goes against typical Godot workflow

---

## Task 1: Auto-Generate Lobby UI Elements

Instead of manually adding nodes in lobby.tscn, we'll modify `lobby.gd` to create them programmatically if they don't exist.

### Implementation

**File:** `godot/client/scenes/lobby.gd`

Add this function to create missing UI nodes:

```gdscript
func _ensure_army_ui_exists() -> void:
	"""Create army UI nodes if they don't exist in the scene tree"""

	# Find InRoomPanel/VBoxContainer
	var in_room_panel = $Panels/InRoomPanel
	if not in_room_panel:
		push_error("InRoomPanel not found - lobby.tscn structure may have changed")
		return

	var vbox = in_room_panel.get_node_or_null("VBoxContainer")
	if not vbox:
		push_error("VBoxContainer not found in InRoomPanel")
		return

	# Check if nodes already exist (from .tscn file)
	if vbox.has_node("RollArmyButton"):
		print("[Lobby] Army UI nodes already exist in scene")
		return

	print("[Lobby] Creating army UI nodes programmatically...")

	# Create RollArmyButton
	var roll_button = Button.new()
	roll_button.name = "RollArmyButton"
	roll_button.text = "Roll Army"
	roll_button.custom_minimum_size = Vector2(0, 40)
	roll_button.pressed.connect(_on_roll_army_button_pressed)
	vbox.add_child(roll_button)

	# Create ArmyScrollContainer
	var scroll = ScrollContainer.new()
	scroll.name = "ArmyScrollContainer"
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	# Create ArmyDisplay (VBoxContainer inside ScrollContainer)
	var army_display = VBoxContainer.new()
	army_display.name = "ArmyDisplay"
	army_display.size_flags_horizontal = Control.SIZE_FILL
	army_display.size_flags_vertical = Control.SIZE_FILL
	scroll.add_child(army_display)

	# Create SubmitArmyButton
	var submit_button = Button.new()
	submit_button.name = "SubmitArmyButton"
	submit_button.text = "Submit Army"
	submit_button.disabled = true  # Enabled after rolling
	submit_button.custom_minimum_size = Vector2(0, 40)
	submit_button.pressed.connect(_on_submit_army_button_pressed)
	vbox.add_child(submit_button)

	print("[Lobby] Army UI nodes created successfully")
```

**Call this in _ready():**

```gdscript
func _ready() -> void:
	# Existing _ready code...

	# Ensure army UI nodes exist
	_ensure_army_ui_exists()

	# Rest of _ready code...
```

Now the lobby will auto-generate the UI if it doesn't exist in the .tscn file!

---

## Task 2 & 3: Create Battle Scene Programmatically

Instead of creating battle.tscn in the editor, we'll build the entire scene in code.

### Implementation

**File:** `godot/client/scenes/battle.gd`

Create a complete battle scene programmatically:

```gdscript
extends Control
## Battle scene - Client-side battle UI
## Auto-generates all UI elements programmatically

# Node references (will be created in _ready)
var board_tilemap: TileMap
var units_container: Node2D
var turn_banner: Label
var placement_panel: Panel
var combat_panel: Panel
var action_log_content: VBoxContainer
var confirm_placement_button: Button
var end_activation_button: Button
var end_turn_button: Button

# Game state
var current_game_state: Types.GameState = null
var my_seat: int = 0
var selected_unit_id: String = ""
var unit_sprites: Dictionary = {}  # unit_id -> ColorRect

# Constants
const CELL_SIZE: int = 16
const BOARD_WIDTH: int = 48
const BOARD_HEIGHT: int = 32


func _ready() -> void:
	print("[Battle] Initializing battle scene programmatically...")

	# Get player's seat from NetworkManager
	my_seat = NetworkManager.my_seat
	print("[Battle] My seat: %d" % my_seat)

	# Create all UI nodes
	_create_scene_structure()

	# Initial state will come from server
	_log_action("Battle started - Waiting for game state from server")


func _create_scene_structure() -> void:
	"""Create the entire battle UI programmatically"""

	# 1. Create TileMap
	board_tilemap = TileMap.new()
	board_tilemap.name = "BoardTileMap"
	board_tilemap.set_cell_size(Vector2(CELL_SIZE, CELL_SIZE))
	add_child(board_tilemap)

	# Create a simple tileset for the grid
	var tileset = TileSet.new()
	board_tilemap.tile_set = tileset

	# Draw grid background (optional - just for visibility)
	_draw_grid_background()

	# 2. Create UnitsContainer
	units_container = Node2D.new()
	units_container.name = "UnitsContainer"
	add_child(units_container)

	# 3. Create UI Layer
	var ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	# 4. Create Turn Banner
	turn_banner = Label.new()
	turn_banner.name = "TurnBanner"
	turn_banner.text = "Turn 1 - Waiting..."
	turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_banner.custom_minimum_size = Vector2(0, 50)
	turn_banner.anchors_preset = Control.PRESET_TOP_WIDE
	turn_banner.offset_top = 0
	turn_banner.offset_bottom = 50
	turn_banner.add_theme_font_size_override("font_size", 24)
	ui_layer.add_child(turn_banner)

	# 5. Create Placement Panel
	_create_placement_panel(ui_layer)

	# 6. Create Combat Panel
	_create_combat_panel(ui_layer)

	# 7. Create Action Log Panel
	_create_action_log_panel(ui_layer)

	print("[Battle] Scene structure created successfully")


func _draw_grid_background() -> void:
	"""Draw a simple grid background for visibility"""
	# Create a ColorRect background
	var background = ColorRect.new()
	background.color = Color(0.1, 0.1, 0.1)  # Dark gray
	background.custom_minimum_size = Vector2(BOARD_WIDTH * CELL_SIZE, BOARD_HEIGHT * CELL_SIZE)
	background.z_index = -1
	add_child(background)
	background.move_to_front()
	board_tilemap.move_to_front()


func _create_placement_panel(parent: CanvasLayer) -> void:
	"""Create placement phase UI panel"""
	placement_panel = Panel.new()
	placement_panel.name = "PlacementPanel"
	placement_panel.anchors_preset = Control.PRESET_BOTTOM_WIDE
	placement_panel.offset_top = -100
	placement_panel.offset_bottom = 0
	placement_panel.visible = true  # Visible by default
	parent.add_child(placement_panel)

	var vbox = VBoxContainer.new()
	vbox.name = "PlacementContent"
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	placement_panel.add_child(vbox)

	var label = Label.new()
	label.text = "Placement Phase - Click grid to place units"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	confirm_placement_button = Button.new()
	confirm_placement_button.name = "ConfirmPlacementButton"
	confirm_placement_button.text = "Confirm Placement"
	confirm_placement_button.pressed.connect(_on_confirm_placement_pressed)
	vbox.add_child(confirm_placement_button)


func _create_combat_panel(parent: CanvasLayer) -> void:
	"""Create combat phase UI panel"""
	combat_panel = Panel.new()
	combat_panel.name = "CombatPanel"
	combat_panel.anchors_preset = Control.PRESET_BOTTOM_WIDE
	combat_panel.offset_top = -100
	combat_panel.offset_bottom = 0
	combat_panel.visible = false  # Hidden by default
	parent.add_child(combat_panel)

	var hbox = HBoxContainer.new()
	hbox.name = "CombatActions"
	hbox.anchors_preset = Control.PRESET_CENTER
	combat_panel.add_child(hbox)

	end_activation_button = Button.new()
	end_activation_button.name = "EndActivationButton"
	end_activation_button.text = "End Activation"
	end_activation_button.pressed.connect(_on_end_activation_pressed)
	hbox.add_child(end_activation_button)

	end_turn_button = Button.new()
	end_turn_button.name = "EndTurnButton"
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	hbox.add_child(end_turn_button)


func _create_action_log_panel(parent: CanvasLayer) -> void:
	"""Create action log panel on right side"""
	var log_panel = Panel.new()
	log_panel.name = "ActionLogPanel"
	log_panel.anchors_preset = Control.PRESET_RIGHT_WIDE
	log_panel.offset_left = -300
	log_panel.offset_top = 60  # Below turn banner
	log_panel.offset_bottom = -110  # Above combat panel
	parent.add_child(log_panel)

	var vbox = VBoxContainer.new()
	vbox.name = "ActionLogContainer"
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	log_panel.add_child(vbox)

	var title = Label.new()
	title.text = "Action Log"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.name = "ActionLogScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	action_log_content = VBoxContainer.new()
	action_log_content.name = "ActionLogContent"
	scroll.add_child(action_log_content)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if current_game_state == null:
			return

		# Convert mouse position to grid coordinates
		var mouse_pos = get_global_mouse_position()
		var grid_x = int(mouse_pos.x / CELL_SIZE)
		var grid_y = int(mouse_pos.y / CELL_SIZE)

		# Bounds check
		if grid_x < 0 or grid_x >= BOARD_WIDTH or grid_y < 0 or grid_y >= BOARD_HEIGHT:
			return

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
			_render_state()
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
	var action_data = {"type": "confirm_placement"}
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
	var action_data = {"type": "end_turn"}
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

		# Add label with unit name (first letter)
		var label = Label.new()
		label.text = unit.name.substr(0, 1)
		label.position = Vector2(2, 0)
		label.add_theme_font_size_override("font_size", 10)
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
	var scroll = action_log_content.get_parent() as ScrollContainer
	if scroll:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


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

### Create Battle Scene File

Since we're building the scene programmatically, we just need a minimal .tscn file:

**File:** `godot/client/scenes/battle.tscn`

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://client/scenes/battle.gd" id="1"]

[node name="Battle" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
```

Or create it programmatically via Write tool!

---

## Testing the Programmatic Implementation

```bash
# 1. Start server
cd godot/
/Applications/Godot.app/Contents/MacOS/Godot project.godot --server

# 2. Start two clients
/Applications/Godot.app/Contents/MacOS/Godot project.godot &
/Applications/Godot.app/Contents/MacOS/Godot project.godot &

# 3. Test flow
# - Both connect to lobby
# - Create/join room
# - Roll and submit armies
# - Verify UI appears automatically
# - Play through placement and combat
```

**Expected:**
- Lobby auto-generates Roll/Submit buttons
- Battle scene creates entire UI on load
- All functionality works without manual .tscn editing

---

## Advantages of This Approach

1. **No manual work** - Everything done in code
2. **Version controlled** - All UI in .gd files
3. **Reviewable** - Can see UI changes in PRs
4. **Claude Code friendly** - Can implement without Godot editor
5. **Portable** - Works on any machine without scene file sync issues

## Disadvantages

1. **Harder to visualize** - Can't see layout in editor
2. **More verbose** - More code than editor approach
3. **Tweaking harder** - Need to restart to see changes
4. **Non-standard** - Most Godot projects use editor for UI

---

## Recommendation

**For this project:** Use programmatic approach

**Reasons:**
- You're working with Claude Code primarily
- UI is simple (placeholder graphics for MVP)
- Unblocks testing immediately
- Can always migrate to .tscn files later if needed

**For future projects:** Use editor for complex UI, code for simple/dynamic UI

---

## See Also

- [Phase 4 UI Tasks](Phase-4-UI-Tasks.md) - Original manual approach
- [Godot UI Documentation](https://docs.godotengine.org/en/stable/tutorials/ui/index.html)
- [Code Style Guide](Code-Style-Guide.md) - UI code conventions
