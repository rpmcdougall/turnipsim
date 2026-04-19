extends Control
## Battle — main gameplay view, unit placement, combat resolution.

const BOARD_WIDTH = 48
const BOARD_HEIGHT = 32

# Deployment zones
const DEPLOY_1_Y_MIN = 28
const DEPLOY_1_Y_MAX = 31
const DEPLOY_2_Y_MIN = 0
const DEPLOY_2_Y_MAX = 3

# Scene nodes
var board_container: Control
var grid_draw: Control  # Custom draw node for grid + zones
var units_container: Node2D
var sidebar: VBoxContainer
var turn_banner: Label
var unit_info_label: Label
var placement_panel: PanelContainer
var confirm_placement_button: Button
var roster_scroll: ScrollContainer
var roster_list: VBoxContainer
var orders_panel: PanelContainer
var end_activation_button: Button
var end_turn_button: Button
var log_scroll: ScrollContainer
var log_container: VBoxContainer

# State
var current_game_state: Types.GameState = null
var my_seat: int = 0
var selected_unit_id: String = ""
var unit_sprites: Dictionary = {}  # unit_id -> ColorRect
var cell_size: float = 16.0  # Computed from available space


func _ready() -> void:
	my_seat = NetworkManager.my_seat
	print("[Battle] My seat: %d" % my_seat)

	_create_scene_structure()

	NetworkClient.game_started.connect(_on_game_started)
	NetworkClient.state_update.connect(_on_state_update)
	NetworkClient.action_resolved.connect(_on_action_resolved)
	NetworkClient.game_ended.connect(_on_game_ended)
	NetworkClient.error_received.connect(_on_error_received)

	if not NetworkManager.cached_game_state.is_empty():
		_on_game_started(NetworkManager.cached_game_state)

	get_tree().root.size_changed.connect(_on_window_resized)


func _create_scene_structure() -> void:
	# Root: HBoxContainer fills the window — board on left, sidebar on right
	var root_hbox = HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 8)
	add_child(root_hbox)

	# Left side: board area
	var board_margin = MarginContainer.new()
	board_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_margin.add_theme_constant_override("margin_top", 50)  # Room for banner
	board_margin.add_theme_constant_override("margin_left", 8)
	board_margin.add_theme_constant_override("margin_bottom", 8)
	root_hbox.add_child(board_margin)

	# Board container — holds the grid draw + units
	board_container = Control.new()
	board_container.name = "BoardContainer"
	board_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_margin.add_child(board_container)

	# Grid drawing node (custom _draw for grid lines + deployment zones)
	grid_draw = Control.new()
	grid_draw.name = "GridDraw"
	grid_draw.set_script(load("res://client/scenes/grid_draw.gd"))
	grid_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_container.add_child(grid_draw)
	grid_draw.battle_ref = self

	# Units container (child of board_container so coordinates match)
	units_container = Node2D.new()
	units_container.name = "UnitsContainer"
	board_container.add_child(units_container)

	# Turn banner (overlay at top)
	var ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	turn_banner = Label.new()
	turn_banner.text = "Waiting for game state..."
	turn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_banner.add_theme_font_size_override("font_size", 22)
	turn_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	turn_banner.custom_minimum_size = Vector2(0, 44)
	turn_banner.add_theme_color_override("font_color", Color(1, 1, 1))
	ui_layer.add_child(turn_banner)

	# Right side: sidebar
	sidebar = VBoxContainer.new()
	sidebar.name = "Sidebar"
	sidebar.custom_minimum_size = Vector2(260, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", 6)
	root_hbox.add_child(sidebar)

	# Unit info display (selected unit details)
	unit_info_label = Label.new()
	unit_info_label.name = "UnitInfo"
	unit_info_label.text = ""
	unit_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	unit_info_label.custom_minimum_size = Vector2(0, 60)
	unit_info_label.add_theme_font_size_override("font_size", 14)
	sidebar.add_child(unit_info_label)

	# Placement panel
	placement_panel = PanelContainer.new()
	placement_panel.name = "PlacementPanel"
	placement_panel.visible = false
	sidebar.add_child(placement_panel)

	var placement_vbox = VBoxContainer.new()
	placement_panel.add_child(placement_vbox)

	var placement_label = Label.new()
	placement_label.text = "Click in your deployment zone\nto place the next unit"
	placement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	placement_vbox.add_child(placement_label)

	# Roster list — shows all units and placement status
	roster_scroll = ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(0, 100)
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	placement_vbox.add_child(roster_scroll)

	roster_list = VBoxContainer.new()
	roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster_list)

	confirm_placement_button = Button.new()
	confirm_placement_button.text = "Confirm Placement"
	confirm_placement_button.custom_minimum_size = Vector2(0, 36)
	confirm_placement_button.pressed.connect(_on_confirm_placement_pressed)
	placement_vbox.add_child(confirm_placement_button)

	# Orders panel
	orders_panel = PanelContainer.new()
	orders_panel.name = "OrdersPanel"
	orders_panel.visible = false
	sidebar.add_child(orders_panel)

	var orders_vbox = VBoxContainer.new()
	orders_panel.add_child(orders_vbox)

	var orders_label = Label.new()
	orders_label.text = "Select unit → click to move\nClick enemy to attack"
	orders_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	orders_vbox.add_child(orders_label)

	end_activation_button = Button.new()
	end_activation_button.text = "End Activation"
	end_activation_button.custom_minimum_size = Vector2(0, 36)
	end_activation_button.pressed.connect(_on_end_activation_pressed)
	orders_vbox.add_child(end_activation_button)

	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.custom_minimum_size = Vector2(0, 36)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	orders_vbox.add_child(end_turn_button)

	# Action log
	var log_title = Label.new()
	log_title.text = "Action Log"
	log_title.add_theme_font_size_override("font_size", 16)
	sidebar.add_child(log_title)

	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sidebar.add_child(log_scroll)

	log_container = VBoxContainer.new()
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_container)

	# Compute initial cell size
	await get_tree().process_frame
	_recompute_cell_size()


func _on_window_resized() -> void:
	_recompute_cell_size()
	if grid_draw:
		grid_draw.queue_redraw()
	_render_units()


func _recompute_cell_size() -> void:
	if not board_container:
		return
	var avail = board_container.size
	if avail.x <= 0 or avail.y <= 0:
		return
	# Fit board into available space, maintaining aspect ratio
	var cs_x = avail.x / BOARD_WIDTH
	var cs_y = avail.y / BOARD_HEIGHT
	cell_size = min(cs_x, cs_y)


## Convert grid coords to pixel position
func grid_to_pixel(gx: int, gy: int) -> Vector2:
	return Vector2(gx * cell_size, gy * cell_size)


## Convert pixel position to grid coords
func pixel_to_grid(px: float, py: float) -> Vector2i:
	return Vector2i(int(px / cell_size), int(py / cell_size))


# =============================================================================
# RENDERING
# =============================================================================

func _render_state() -> void:
	if not current_game_state:
		return

	var is_my_turn = current_game_state.active_seat == my_seat
	turn_banner.text = "Round %d — Player %d %s" % [
		current_game_state.current_round,
		current_game_state.active_seat,
		"(Your turn)" if is_my_turn else "(Opponent's turn)"
	]

	if current_game_state.phase == "placement":
		placement_panel.visible = is_my_turn
		orders_panel.visible = false
		_render_roster_list()
	elif current_game_state.phase == "orders":
		placement_panel.visible = false
		orders_panel.visible = is_my_turn
	else:
		placement_panel.visible = false
		orders_panel.visible = false

	if grid_draw:
		grid_draw.queue_redraw()
	_render_units()
	_update_unit_info()


func _render_units() -> void:
	for child in units_container.get_children():
		child.queue_free()
	unit_sprites.clear()

	if not current_game_state:
		return

	for unit in current_game_state.units:
		if unit.x >= 0 and unit.y >= 0 and not unit.is_dead:
			var sprite = _create_unit_sprite(unit)
			units_container.add_child(sprite)
			unit_sprites[unit.id] = sprite


func _create_unit_sprite(unit: Types.UnitState) -> ColorRect:
	var sprite = ColorRect.new()
	var padding = maxf(1.0, cell_size * 0.1)
	sprite.size = Vector2(cell_size - padding * 2, cell_size - padding * 2)
	sprite.position = Vector2(unit.x * cell_size + padding, unit.y * cell_size + padding)

	# Color by owner
	if unit.owner_seat == 1:
		sprite.color = Color(0.2, 0.5, 0.9) if not unit.is_snob() else Color(0.3, 0.6, 1.0)
	else:
		sprite.color = Color(0.9, 0.2, 0.2) if not unit.is_snob() else Color(1.0, 0.4, 0.3)

	# Highlight selected
	if unit.id == selected_unit_id:
		sprite.color = sprite.color.lightened(0.4)

	# Dim activated units
	if unit.has_activated:
		sprite.color = sprite.color.darkened(0.4)

	sprite.set_meta("unit_id", unit.id)

	# Add a label showing unit type initial
	var lbl = Label.new()
	lbl.text = unit.unit_type.left(2)
	lbl.add_theme_font_size_override("font_size", clampi(int(cell_size * 0.5), 8, 18))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = sprite.size
	sprite.add_child(lbl)

	return sprite


## Render the roster list in the placement sidebar
func _render_roster_list() -> void:
	if not roster_list or not current_game_state:
		return

	for child in roster_list.get_children():
		child.queue_free()

	var next_unplaced_found = false
	for unit in current_game_state.units:
		if unit.owner_seat != my_seat:
			continue

		var lbl = Label.new()
		lbl.add_theme_font_size_override("font_size", 13)

		var placed = unit.x >= 0 and unit.y >= 0
		var is_next = not placed and not next_unplaced_found

		if placed:
			lbl.text = "  [Placed] %s (%d models)" % [unit.unit_type, unit.model_count]
			lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		elif is_next:
			lbl.text = "> %s (%d models) — NEXT" % [unit.unit_type, unit.model_count]
			lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
			next_unplaced_found = true
		else:
			lbl.text = "  %s (%d models)" % [unit.unit_type, unit.model_count]
			lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

		roster_list.add_child(lbl)


func _update_unit_info() -> void:
	if not unit_info_label or not current_game_state:
		return

	if selected_unit_id == "":
		# Show summary of unplaced/unactivated units
		if current_game_state.phase == "placement":
			var unplaced = 0
			for u in current_game_state.units:
				if u.owner_seat == my_seat and u.x == -1:
					unplaced += 1
			unit_info_label.text = "%d units to place" % unplaced
		else:
			unit_info_label.text = "Click a unit to select"
		return

	var unit = _get_unit_by_id(selected_unit_id)
	if not unit:
		unit_info_label.text = "Click a unit to select"
		return

	var s = unit.base_stats
	unit_info_label.text = "%s [%s]\nM%d A%d I%d+ W%d V%d+\nModels: %d/%d | Panic: %d\nEquip: %s%s" % [
		unit.unit_type, unit.category,
		s.movement, s.attacks, s.inaccuracy, s.wounds, s.vulnerability,
		unit.model_count, unit.max_models, unit.panic_tokens,
		unit.equipment,
		"\n[ACTIVATED]" if unit.has_activated else ""
	]


# =============================================================================
# INPUT
# =============================================================================

func _input(event: InputEvent) -> void:
	if not current_game_state:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Get mouse position relative to board_container
		var local_pos = board_container.get_local_mouse_position()
		var grid = pixel_to_grid(local_pos.x, local_pos.y)

		if grid.x < 0 or grid.x >= BOARD_WIDTH or grid.y < 0 or grid.y >= BOARD_HEIGHT:
			return

		if current_game_state.phase == "placement":
			_handle_placement_click(grid.x, grid.y)
		elif current_game_state.phase == "orders":
			_handle_combat_click(grid.x, grid.y)


func _handle_placement_click(x: int, y: int) -> void:
	if current_game_state.active_seat != my_seat:
		return

	var unplaced_unit = null
	for unit in current_game_state.units:
		if unit.owner_seat == my_seat and unit.x == -1:
			unplaced_unit = unit
			break

	if not unplaced_unit:
		return

	NetworkClient.request_action.rpc_id(1, {
		"type": "place_unit",
		"unit_id": unplaced_unit.id,
		"x": x,
		"y": y
	})


func _handle_combat_click(x: int, y: int) -> void:
	if current_game_state.active_seat != my_seat:
		return

	var clicked_unit = _get_unit_at(x, y)

	if clicked_unit:
		if clicked_unit.owner_seat == my_seat:
			selected_unit_id = clicked_unit.id
			_render_units()
			_update_unit_info()
		elif selected_unit_id != "":
			var selected_unit = _get_unit_by_id(selected_unit_id)
			if selected_unit and not selected_unit.has_activated:
				_attack_unit(selected_unit, clicked_unit)
	else:
		if selected_unit_id != "":
			var selected_unit = _get_unit_by_id(selected_unit_id)
			if selected_unit and not selected_unit.has_activated:
				_move_unit(selected_unit, x, y)


func _move_unit(unit: Types.UnitState, x: int, y: int) -> void:
	NetworkClient.request_action.rpc_id(1, {
		"type": "move",
		"unit_id": unit.id,
		"x": x,
		"y": y
	})


func _attack_unit(attacker: Types.UnitState, target: Types.UnitState) -> void:
	var action_type = "shoot" if attacker.base_stats.weapon_range > 0 and not attacker.has_powder_smoke else "charge"
	NetworkClient.request_action.rpc_id(1, {
		"type": action_type,
		"attacker_id": attacker.id,
		"target_id": target.id
	})


func _get_unit_at(x: int, y: int) -> Types.UnitState:
	if not current_game_state:
		return null
	for unit in current_game_state.units:
		if unit.x == x and unit.y == y and not unit.is_dead:
			return unit
	return null


func _get_unit_by_id(unit_id: String) -> Types.UnitState:
	if not current_game_state:
		return null
	for unit in current_game_state.units:
		if unit.id == unit_id:
			return unit
	return null


func _add_log_entry(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	log_container.add_child(label)

	await get_tree().process_frame
	log_scroll.scroll_vertical = log_scroll.get_v_scroll_bar().max_value


func _on_confirm_placement_pressed() -> void:
	NetworkClient.request_action.rpc_id(1, {"type": "confirm_placement"})


func _on_end_activation_pressed() -> void:
	if selected_unit_id == "":
		return
	NetworkClient.request_action.rpc_id(1, {
		"type": "end_activation",
		"unit_id": selected_unit_id
	})
	selected_unit_id = ""
	_update_unit_info()


func _on_end_turn_pressed() -> void:
	NetworkClient.request_action.rpc_id(1, {"type": "end_turn"})


# =============================================================================
# SERVER EVENT HANDLERS
# =============================================================================

func _on_game_started(game_state: Dictionary) -> void:
	print("[Battle] Game state received: phase=%s, units=%d" % [game_state.get("phase", "?"), game_state.get("units", []).size()])
	current_game_state = Types.GameState.from_dict(game_state)
	print("[Battle] Parsed state: phase=%s, units=%d, active_seat=%d, my_seat=%d" % [current_game_state.phase, current_game_state.units.size(), current_game_state.active_seat, my_seat])
	for u in current_game_state.units:
		print("[Battle]   Unit: %s (seat %d, %s, x=%d y=%d)" % [u.unit_type, u.owner_seat, u.category, u.x, u.y])
	# Wait a frame for layout to settle before computing cell size
	await get_tree().process_frame
	_recompute_cell_size()
	print("[Battle] Cell size: %f, board_container size: %s" % [cell_size, board_container.size if board_container else "null"])
	_render_state()


func _on_state_update(state_data: Dictionary) -> void:
	current_game_state = Types.GameState.from_dict(state_data)
	_render_state()


func _on_action_resolved(action: Dictionary, result: Dictionary) -> void:
	if result.has("description"):
		_add_log_entry(result["description"])


func _on_game_ended(winner_seat: int, reason: String) -> void:
	var message = ""
	if winner_seat == my_seat:
		message = "VICTORY! " + reason
	elif winner_seat == 0:
		message = "DRAW! " + reason
	else:
		message = "DEFEAT! " + reason

	turn_banner.text = message
	_add_log_entry("=== GAME OVER: " + message + " ===")


func _on_error_received(message: String) -> void:
	_add_log_entry("Error: " + message)

