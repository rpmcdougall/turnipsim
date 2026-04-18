extends Control
## Battle — main gameplay view, unit placement, combat resolution.

const CELL_SIZE = 16
const BOARD_WIDTH = 48
const BOARD_HEIGHT = 32

# Scene nodes (created programmatically)
var board_background: ColorRect
var units_container: Node2D
var ui_layer: CanvasLayer
var turn_banner: Label
var placement_panel: PanelContainer
var confirm_placement_button: Button
var combat_panel: PanelContainer
var end_activation_button: Button
var end_turn_button: Button
var action_log_panel: PanelContainer
var log_scroll: ScrollContainer
var log_container: VBoxContainer

# State
var current_game_state: Types.GameState = null
var my_seat: int = 0
var selected_unit_id: String = ""
var unit_sprites: Dictionary = {}  # unit_id -> Sprite2D


func _ready() -> void:
	# Get seat assignment from NetworkManager
	my_seat = NetworkManager.my_seat
	print("[Battle] My seat: %d" % my_seat)

	# Create entire scene structure programmatically
	_create_scene_structure()

	# Request initial state from server
	# (Server should send state automatically on scene load, or we request it)
	request_initial_state.rpc_id(1)


## Create all UI nodes programmatically
func _create_scene_structure() -> void:
	print("[Battle] Creating scene structure programmatically...")

	# 1. Board background (48x32 grid visualization)
	board_background = ColorRect.new()
	board_background.name = "BoardBackground"
	board_background.color = Color(0.15, 0.15, 0.2)  # Dark gray-blue
	board_background.custom_minimum_size = Vector2(BOARD_WIDTH * CELL_SIZE, BOARD_HEIGHT * CELL_SIZE)
	board_background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_background.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(board_background)

	# 2. Units container (Node2D for sprite positioning)
	units_container = Node2D.new()
	units_container.name = "UnitsContainer"
	add_child(units_container)

	# 3. UI Layer (CanvasLayer for overlay UI)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	# 4. Turn Banner (top center)
	turn_banner = Label.new()
	turn_banner.name = "TurnBanner"
	turn_banner.text = "Waiting for game state..."
	turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.add_theme_font_size_override("font_size", 20)
	turn_banner.position = Vector2(400, 10)
	turn_banner.custom_minimum_size = Vector2(400, 40)
	ui_layer.add_child(turn_banner)

	# 5. Placement Panel (visible during placement phase)
	placement_panel = PanelContainer.new()
	placement_panel.name = "PlacementPanel"
	placement_panel.position = Vector2(10, 60)
	placement_panel.visible = false
	ui_layer.add_child(placement_panel)

	var placement_vbox = VBoxContainer.new()
	placement_panel.add_child(placement_vbox)

	var placement_label = Label.new()
	placement_label.text = "Placement Phase"
	placement_vbox.add_child(placement_label)

	confirm_placement_button = Button.new()
	confirm_placement_button.name = "ConfirmPlacementButton"
	confirm_placement_button.text = "Confirm Placement"
	confirm_placement_button.custom_minimum_size = Vector2(0, 40)
	confirm_placement_button.pressed.connect(_on_confirm_placement_pressed)
	placement_vbox.add_child(confirm_placement_button)

	# 6. Combat Panel (visible during combat phase)
	combat_panel = PanelContainer.new()
	combat_panel.name = "CombatPanel"
	combat_panel.position = Vector2(10, 60)
	combat_panel.visible = false
	ui_layer.add_child(combat_panel)

	var combat_vbox = VBoxContainer.new()
	combat_panel.add_child(combat_vbox)

	var combat_label = Label.new()
	combat_label.text = "Combat Phase"
	combat_vbox.add_child(combat_label)

	end_activation_button = Button.new()
	end_activation_button.name = "EndActivationButton"
	end_activation_button.text = "End Activation"
	end_activation_button.custom_minimum_size = Vector2(0, 40)
	end_activation_button.pressed.connect(_on_end_activation_pressed)
	combat_vbox.add_child(end_activation_button)

	end_turn_button = Button.new()
	end_turn_button.name = "EndTurnButton"
	end_turn_button.text = "End Turn"
	end_turn_button.custom_minimum_size = Vector2(0, 40)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	combat_vbox.add_child(end_turn_button)

	# 7. Action Log Panel (right side)
	action_log_panel = PanelContainer.new()
	action_log_panel.name = "ActionLogPanel"
	action_log_panel.position = Vector2(900, 60)
	action_log_panel.custom_minimum_size = Vector2(300, 500)
	ui_layer.add_child(action_log_panel)

	var log_vbox = VBoxContainer.new()
	action_log_panel.add_child(log_vbox)

	var log_title = Label.new()
	log_title.text = "Action Log"
	log_title.add_theme_font_size_override("font_size", 16)
	log_vbox.add_child(log_title)

	log_scroll = ScrollContainer.new()
	log_scroll.name = "LogScroll"
	log_scroll.custom_minimum_size = Vector2(0, 450)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	log_vbox.add_child(log_scroll)

	log_container = VBoxContainer.new()
	log_container.name = "LogContainer"
	log_container.size_flags_horizontal = Control.SIZE_FILL
	log_scroll.add_child(log_container)

	print("[Battle] Scene structure created successfully")


## Render the current game state
func _render_state() -> void:
	if not current_game_state:
		return

	# Update turn banner
	var is_my_turn = current_game_state.active_seat == my_seat
	var turn_text = "Turn %d - Player %d %s" % [
		current_game_state.current_turn,
		current_game_state.active_seat,
		"(Your turn)" if is_my_turn else "(Opponent's turn)"
	]
	turn_banner.text = turn_text

	# Show appropriate panel based on phase
	if current_game_state.phase == "placement":
		placement_panel.visible = is_my_turn
		combat_panel.visible = false
	elif current_game_state.phase == "combat":
		placement_panel.visible = false
		combat_panel.visible = is_my_turn
	else:
		placement_panel.visible = false
		combat_panel.visible = false

	# Render units
	_render_units()


## Render all units on the board
func _render_units() -> void:
	# Clear existing sprites
	for child in units_container.get_children():
		child.queue_free()
	unit_sprites.clear()

	if not current_game_state:
		return

	# Create sprite for each placed, living unit
	for unit in current_game_state.units:
		if unit.x >= 0 and unit.y >= 0 and not unit.is_dead:
			var sprite = _create_unit_sprite(unit)
			units_container.add_child(sprite)
			unit_sprites[unit.id] = sprite


## Create a sprite for a unit
func _create_unit_sprite(unit: Types.UnitState) -> ColorRect:
	var sprite = ColorRect.new()
	sprite.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	sprite.position = Vector2(unit.x * CELL_SIZE, unit.y * CELL_SIZE)

	# Color by owner (blue for player 1, red for player 2)
	sprite.color = Color(0.2, 0.4, 0.8) if unit.owner_seat == 1 else Color(0.8, 0.2, 0.2)

	# Highlight if selected
	if unit.id == selected_unit_id:
		sprite.color = sprite.color.lightened(0.3)

	# Store unit_id in metadata
	sprite.set_meta("unit_id", unit.id)

	return sprite


## Input handling
func _input(event: InputEvent) -> void:
	if not current_game_state:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Convert mouse position to grid coordinates
		var mouse_pos = get_local_mouse_position()
		var grid_x = int(mouse_pos.x / CELL_SIZE)
		var grid_y = int(mouse_pos.y / CELL_SIZE)

		# Validate bounds
		if grid_x < 0 or grid_x >= BOARD_WIDTH or grid_y < 0 or grid_y >= BOARD_HEIGHT:
			return

		# Handle click based on phase
		if current_game_state.phase == "placement":
			_handle_placement_click(grid_x, grid_y)
		elif current_game_state.phase == "combat":
			_handle_combat_click(grid_x, grid_y)


## Handle click during placement phase
func _handle_placement_click(x: int, y: int) -> void:
	# Only allow placement on our turn
	if current_game_state.active_seat != my_seat:
		return

	# Find first unplaced unit
	var unplaced_unit = null
	for unit in current_game_state.units:
		if unit.owner_seat == my_seat and unit.x == -1:
			unplaced_unit = unit
			break

	if not unplaced_unit:
		print("[Battle] No unplaced units")
		return

	# Send placement request
	var action_data = {
		"type": "place_unit",
		"unit_id": unplaced_unit.id,
		"x": x,
		"y": y
	}
	request_action.rpc_id(1, action_data)


## Handle click during combat phase
func _handle_combat_click(x: int, y: int) -> void:
	# Only allow actions on our turn
	if current_game_state.active_seat != my_seat:
		return

	# Check if clicked on a unit
	var clicked_unit = _get_unit_at(x, y)

	if clicked_unit:
		# If it's our unit, select it
		if clicked_unit.owner_seat == my_seat:
			selected_unit_id = clicked_unit.id
			_render_units()  # Re-render to show selection
			print("[Battle] Selected unit: %s" % clicked_unit.name)
		# If it's enemy unit and we have selection, attack
		elif selected_unit_id != "":
			var selected_unit = _get_unit_by_id(selected_unit_id)
			if selected_unit and not selected_unit.has_activated:
				_attack_unit(selected_unit, clicked_unit)
	else:
		# Empty cell - move selected unit if we have one
		if selected_unit_id != "":
			var selected_unit = _get_unit_by_id(selected_unit_id)
			if selected_unit and not selected_unit.has_activated:
				_move_unit(selected_unit, x, y)


## Move selected unit to target position
func _move_unit(unit: Types.UnitState, x: int, y: int) -> void:
	var action_data = {
		"type": "move",
		"unit_id": unit.id,
		"x": x,
		"y": y
	}
	request_action.rpc_id(1, action_data)


## Attack target unit with selected unit
func _attack_unit(attacker: Types.UnitState, target: Types.UnitState) -> void:
	# Determine action type based on weapon
	var action_type = "shoot" if attacker.weapon.type == "ranged" else "charge"

	var action_data = {
		"type": action_type,
		"attacker_id": attacker.id,
		"target_id": target.id
	}
	request_action.rpc_id(1, action_data)


## Get unit at grid position
func _get_unit_at(x: int, y: int) -> Types.UnitState:
	if not current_game_state:
		return null

	for unit in current_game_state.units:
		if unit.x == x and unit.y == y and not unit.is_dead:
			return unit

	return null


## Get unit by ID
func _get_unit_by_id(unit_id: String) -> Types.UnitState:
	if not current_game_state:
		return null

	for unit in current_game_state.units:
		if unit.id == unit_id:
			return unit

	return null


## Add entry to action log
func _add_log_entry(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_container.add_child(label)

	# Auto-scroll to bottom
	await get_tree().process_frame
	log_scroll.scroll_vertical = log_scroll.get_v_scroll_bar().max_value


## Button handlers
func _on_confirm_placement_pressed() -> void:
	var action_data = {"type": "confirm_placement"}
	request_action.rpc_id(1, action_data)


func _on_end_activation_pressed() -> void:
	if selected_unit_id == "":
		return

	var action_data = {
		"type": "end_activation",
		"unit_id": selected_unit_id
	}
	request_action.rpc_id(1, action_data)
	selected_unit_id = ""


func _on_end_turn_pressed() -> void:
	var action_data = {"type": "end_turn"}
	request_action.rpc_id(1, action_data)


# =============================================================================
# RPCs - Client calls to server
# =============================================================================

@rpc("any_peer", "call_remote", "reliable")
func request_initial_state() -> void:
	pass  # Server handles


@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	pass  # Server handles


# =============================================================================
# RPCs - Server calls to client
# =============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_state_update(state_data: Dictionary) -> void:
	print("[Battle] Received state update")
	current_game_state = Types.GameState.from_dict(state_data)
	_render_state()


@rpc("authority", "call_remote", "reliable")
func _send_action_resolved(action: Dictionary, result: Dictionary) -> void:
	print("[Battle] Action resolved: %s" % action["type"])

	# Add to action log
	if result.has("description"):
		_add_log_entry(result["description"])


@rpc("authority", "call_remote", "reliable")
func _send_game_ended(winner_seat: int, reason: String) -> void:
	print("[Battle] Game ended - Winner: %d, Reason: %s" % [winner_seat, reason])

	# Display victory/defeat message
	var message = ""
	if winner_seat == my_seat:
		message = "VICTORY! " + reason
	elif winner_seat == 0:
		message = "DRAW! " + reason
	else:
		message = "DEFEAT! " + reason

	turn_banner.text = message
	_add_log_entry("=== GAME OVER: " + message + " ===")
