extends Control
## Battle — main gameplay view, unit placement, combat resolution.
##
## Board geometry and deployment zones live in game/board.gd — never
## redeclare them here. Use Board.BOARD_WIDTH etc.

const Board = preload("res://game/board.gd")
const Targeting = preload("res://game/targeting.gd")

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

# Order-phase panels (one visible at a time based on state.order_phase)
var snob_select_panel: PanelContainer
var snob_select_list: VBoxContainer
var order_declare_panel: PanelContainer
var order_declare_header: Label
var declare_target_list: VBoxContainer
var declare_order_buttons: Dictionary = {}  # order_type -> Button
var order_execute_panel: PanelContainer
var order_execute_header: Label
var order_execute_instruction: Label
var order_execute_confirm_button: Button
var follower_self_panel: PanelContainer
var self_target_list: VBoxContainer
var self_order_buttons: Dictionary = {}  # order_type -> Button

var log_scroll: ScrollContainer
var log_container: VBoxContainer

# State
var current_game_state: Types.GameState = null
var my_seat: int = 0
var selected_unit_id: String = ""
var selected_target_id: String = ""      # For declare/self_order: target unit picked from list
var pending_move_x: int = -1             # For move_and_shoot: staged destination before shot pick
var pending_move_y: int = -1
var unit_sprites: Dictionary = {}  # unit_id -> ColorRect
var cell_size: float = 16.0  # Computed from available space

const ORDER_TYPES: Array[String] = ["volley_fire", "move_and_shoot", "march", "charge"]
const ORDER_LABELS: Dictionary = {
	"volley_fire": "Volley Fire",
	"move_and_shoot": "Move & Shoot",
	"march": "March",
	"charge": "Charge",
}


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

	# Snob-select panel (order_phase == "snob_select")
	snob_select_panel = PanelContainer.new()
	snob_select_panel.name = "SnobSelectPanel"
	snob_select_panel.visible = false
	sidebar.add_child(snob_select_panel)

	var snob_select_vbox = VBoxContainer.new()
	snob_select_panel.add_child(snob_select_vbox)

	var snob_select_title = Label.new()
	snob_select_title.text = "Pick a Snob to Make Ready"
	snob_select_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	snob_select_vbox.add_child(snob_select_title)

	snob_select_list = VBoxContainer.new()
	snob_select_list.add_theme_constant_override("separation", 4)
	snob_select_vbox.add_child(snob_select_list)

	# Order-declare panel (order_phase == "order_declare")
	order_declare_panel = PanelContainer.new()
	order_declare_panel.name = "OrderDeclarePanel"
	order_declare_panel.visible = false
	sidebar.add_child(order_declare_panel)

	var declare_vbox = VBoxContainer.new()
	order_declare_panel.add_child(declare_vbox)

	order_declare_header = Label.new()
	order_declare_header.text = ""
	order_declare_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	declare_vbox.add_child(order_declare_header)

	var declare_target_title = Label.new()
	declare_target_title.text = "Target (self or follower in range):"
	declare_target_title.add_theme_font_size_override("font_size", 12)
	declare_vbox.add_child(declare_target_title)

	declare_target_list = VBoxContainer.new()
	declare_target_list.add_theme_constant_override("separation", 2)
	declare_vbox.add_child(declare_target_list)

	var declare_order_title = Label.new()
	declare_order_title.text = "Order:"
	declare_order_title.add_theme_font_size_override("font_size", 12)
	declare_vbox.add_child(declare_order_title)

	for order_type in ORDER_TYPES:
		var btn = Button.new()
		btn.text = ORDER_LABELS[order_type]
		btn.custom_minimum_size = Vector2(0, 30)
		btn.disabled = true
		btn.pressed.connect(_on_declare_order_pressed.bind(order_type))
		declare_vbox.add_child(btn)
		declare_order_buttons[order_type] = btn

	# Order-execute panel (order_phase == "order_execute")
	order_execute_panel = PanelContainer.new()
	order_execute_panel.name = "OrderExecutePanel"
	order_execute_panel.visible = false
	sidebar.add_child(order_execute_panel)

	var execute_vbox = VBoxContainer.new()
	order_execute_panel.add_child(execute_vbox)

	order_execute_header = Label.new()
	order_execute_header.text = ""
	order_execute_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	execute_vbox.add_child(order_execute_header)

	order_execute_instruction = Label.new()
	order_execute_instruction.text = ""
	order_execute_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_execute_instruction.add_theme_font_size_override("font_size", 13)
	execute_vbox.add_child(order_execute_instruction)

	# Only used for move_and_shoot to skip the shot after moving
	order_execute_confirm_button = Button.new()
	order_execute_confirm_button.text = "Confirm move (no shot)"
	order_execute_confirm_button.custom_minimum_size = Vector2(0, 32)
	order_execute_confirm_button.visible = false
	order_execute_confirm_button.pressed.connect(_on_execute_confirm_pressed)
	execute_vbox.add_child(order_execute_confirm_button)

	# Follower-self-order panel (order_phase == "follower_self_order")
	follower_self_panel = PanelContainer.new()
	follower_self_panel.name = "FollowerSelfPanel"
	follower_self_panel.visible = false
	sidebar.add_child(follower_self_panel)

	var self_vbox = VBoxContainer.new()
	follower_self_panel.add_child(self_vbox)

	var self_title = Label.new()
	self_title.text = "Unordered followers self-order"
	self_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	self_vbox.add_child(self_title)

	var self_target_title = Label.new()
	self_target_title.text = "Follower:"
	self_target_title.add_theme_font_size_override("font_size", 12)
	self_vbox.add_child(self_target_title)

	self_target_list = VBoxContainer.new()
	self_target_list.add_theme_constant_override("separation", 2)
	self_vbox.add_child(self_target_list)

	var self_order_title = Label.new()
	self_order_title.text = "Order:"
	self_order_title.add_theme_font_size_override("font_size", 12)
	self_vbox.add_child(self_order_title)

	for order_type in ORDER_TYPES:
		var btn = Button.new()
		btn.text = ORDER_LABELS[order_type]
		btn.custom_minimum_size = Vector2(0, 30)
		btn.disabled = true
		btn.pressed.connect(_on_self_order_pressed.bind(order_type))
		self_vbox.add_child(btn)
		self_order_buttons[order_type] = btn

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
	var cs_x = avail.x / Board.BOARD_WIDTH
	var cs_y = avail.y / Board.BOARD_HEIGHT
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

	_reconcile_selection_state()

	var is_my_turn = current_game_state.active_seat == my_seat
	var turn_suffix := "(Your turn)"
	if not is_my_turn:
		turn_suffix = "(Opponent's turn)"
	var objs_1: int = 0
	var objs_2: int = 0
	for obj in current_game_state.objectives:
		if obj.captured_by == 1:
			objs_1 += 1
		elif obj.captured_by == 2:
			objs_2 += 1
	var objective_tag := ""
	if current_game_state.objectives.size() > 0:
		objective_tag = "   |   Objectives P1: %d · P2: %d" % [objs_1, objs_2]
	turn_banner.text = "Round %d — Player %d %s%s" % [
		current_game_state.current_round,
		current_game_state.active_seat,
		turn_suffix,
		objective_tag
	]

	# Hide all order-phase panels first
	snob_select_panel.visible = false
	order_declare_panel.visible = false
	order_execute_panel.visible = false
	follower_self_panel.visible = false

	if current_game_state.phase == "placement":
		placement_panel.visible = is_my_turn
		_render_roster_list()
	elif current_game_state.phase == "orders":
		placement_panel.visible = false
		if is_my_turn:
			match current_game_state.order_phase:
				"snob_select":
					snob_select_panel.visible = true
					_render_snob_select_panel()
				"order_declare":
					order_declare_panel.visible = true
					_render_order_declare_panel()
				"order_execute":
					order_execute_panel.visible = true
					_render_order_execute_panel()
				"follower_self_order":
					follower_self_panel.visible = true
					_render_follower_self_panel()
	else:
		placement_panel.visible = false

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
	if unit.has_ordered:
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
		"\n[ORDERED]" if unit.has_ordered else ""
	]


# =============================================================================
# INPUT
# =============================================================================

func _input(event: InputEvent) -> void:
	if not current_game_state:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos = board_container.get_local_mouse_position()
		var grid = pixel_to_grid(local_pos.x, local_pos.y)

		if not Board.is_in_bounds(grid.x, grid.y):
			return

		if current_game_state.phase == "placement":
			_handle_placement_click(grid.x, grid.y)
		elif current_game_state.phase == "orders" and current_game_state.active_seat == my_seat:
			match current_game_state.order_phase:
				"snob_select":
					_handle_snob_select_click(grid.x, grid.y)
				"order_declare":
					_handle_order_declare_click(grid.x, grid.y)
				"order_execute":
					_handle_order_execute_click(grid.x, grid.y)
				"follower_self_order":
					_handle_follower_self_click(grid.x, grid.y)


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


## Snob-select phase: clicking own Snob on the board is a shortcut for the
## sidebar button.
func _handle_snob_select_click(x: int, y: int) -> void:
	var clicked = _get_unit_at(x, y)
	if clicked and clicked.owner_seat == my_seat and clicked.is_snob() and not clicked.has_ordered:
		_send_select_snob(clicked.id)


## Order-declare phase: clicking own eligible unit selects it as the target
## of the order (Snob self-order or follower in command range). Clicking
## elsewhere just updates the selected_unit_id for display.
func _handle_order_declare_click(x: int, y: int) -> void:
	var clicked = _get_unit_at(x, y)
	if clicked and clicked.owner_seat == my_seat:
		if _is_valid_declare_target(clicked):
			selected_target_id = clicked.id
			selected_unit_id = clicked.id
			_render_state()


## Order-execute phase: behaviour depends on the declared order.
func _handle_order_execute_click(x: int, y: int) -> void:
	var order_type = current_game_state.current_order_type
	var clicked = _get_unit_at(x, y)

	match order_type:
		"volley_fire":
			if clicked and clicked.owner_seat != my_seat:
				_send_execute_order({"target_id": clicked.id})
		"charge":
			if clicked and clicked.owner_seat != my_seat:
				_send_execute_order({"target_id": clicked.id})
		"march":
			if not clicked:
				_send_execute_order({"x": x, "y": y})
		"move_and_shoot":
			if pending_move_x == -1:
				# First click: stage destination cell
				if not clicked:
					pending_move_x = x
					pending_move_y = y
					_render_state()
			else:
				# Second click: pick enemy to shoot, or same cell to cancel staging
				if clicked and clicked.owner_seat != my_seat:
					_send_execute_order({
						"x": pending_move_x,
						"y": pending_move_y,
						"target_id": clicked.id
					})
				elif not clicked:
					# Restage destination
					pending_move_x = x
					pending_move_y = y
					_render_state()


## Follower self-order phase: click own unordered follower to select it.
func _handle_follower_self_click(x: int, y: int) -> void:
	var clicked = _get_unit_at(x, y)
	if clicked and clicked.owner_seat == my_seat and not clicked.is_snob() and not clicked.has_ordered:
		selected_target_id = clicked.id
		selected_unit_id = clicked.id
		_render_state()


# =============================================================================
# ACTION SENDERS
# =============================================================================

func _send_select_snob(snob_id: String) -> void:
	NetworkClient.request_action.rpc_id(1, {
		"type": "select_snob",
		"snob_id": snob_id
	})


func _send_declare_order(unit_id: String, order_type: String) -> void:
	NetworkClient.request_action.rpc_id(1, {
		"type": "declare_order",
		"unit_id": unit_id,
		"order_type": order_type
	})


func _send_declare_self_order(unit_id: String, order_type: String) -> void:
	NetworkClient.request_action.rpc_id(1, {
		"type": "declare_self_order",
		"unit_id": unit_id,
		"order_type": order_type
	})


func _send_execute_order(params: Dictionary) -> void:
	pending_move_x = -1
	pending_move_y = -1
	NetworkClient.request_action.rpc_id(1, {
		"type": "execute_order",
		"params": params
	})


# =============================================================================
# ORDER-PHASE PANEL RENDERING
# =============================================================================

func _render_snob_select_panel() -> void:
	for child in snob_select_list.get_children():
		child.queue_free()

	for unit in current_game_state.units:
		if (unit.owner_seat == my_seat and unit.is_snob()
				and not unit.is_dead and not unit.has_ordered):
			var btn = Button.new()
			btn.text = "%s (%d,%d)" % [unit.unit_type, unit.x, unit.y]
			btn.custom_minimum_size = Vector2(0, 32)
			btn.pressed.connect(_send_select_snob.bind(unit.id))
			snob_select_list.add_child(btn)


func _render_order_declare_panel() -> void:
	var snob = _get_unit_by_id(current_game_state.current_snob_id)
	var snob_name = snob.unit_type if snob else "?"
	order_declare_header.text = "Snob Made Ready: %s (range %d)" % [
		snob_name, snob.get_command_range() if snob else 0
	]

	for child in declare_target_list.get_children():
		child.queue_free()

	var valid_targets = _declare_valid_targets()
	if valid_targets.is_empty():
		var lbl = Label.new()
		lbl.text = "No valid targets in range"
		lbl.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
		declare_target_list.add_child(lbl)
	else:
		for unit in valid_targets:
			var btn = Button.new()
			var is_self = (unit.id == current_game_state.current_snob_id)
			var prefix = "[Self] " if is_self else ""
			btn.text = "%s%s (%d,%d)" % [prefix, unit.unit_type, unit.x, unit.y]
			btn.custom_minimum_size = Vector2(0, 28)
			btn.toggle_mode = true
			btn.button_pressed = (unit.id == selected_target_id)
			btn.pressed.connect(_on_declare_target_picked.bind(unit.id))
			declare_target_list.add_child(btn)

	_update_declare_button_states()


func _render_order_execute_panel() -> void:
	var unit = _get_unit_by_id(current_game_state.current_order_unit_id)
	var unit_name = unit.unit_type if unit else "?"
	var order_type = current_game_state.current_order_type
	var blunder_tag = " [BLUNDERED]" if current_game_state.current_order_blundered else ""
	order_execute_header.text = "%s: %s%s" % [unit_name, ORDER_LABELS.get(order_type, order_type), blunder_tag]

	order_execute_confirm_button.visible = false

	match order_type:
		"volley_fire":
			if unit and not _has_valid_shooting_target(unit):
				order_execute_instruction.text = "No enemies in range — the volley fizzles."
				order_execute_confirm_button.text = "Continue (no effect)"
				order_execute_confirm_button.visible = true
			else:
				order_execute_instruction.text = "Click an enemy unit to fire."
				order_execute_confirm_button.text = "Confirm move (no shot)"
		"charge":
			var bonus = current_game_state.current_order_move_bonus
			var move = unit.base_stats.movement if unit else 0
			if unit and not _has_valid_enemy_in_range(unit, move + bonus):
				order_execute_instruction.text = "No enemies in charge range — the charge fizzles."
				order_execute_confirm_button.text = "Continue (no effect)"
				order_execute_confirm_button.visible = true
			else:
				order_execute_instruction.text = "Click enemy to charge (range %d + %d = %d)." % [
					move, bonus, move + bonus
				]
				order_execute_confirm_button.text = "Confirm move (no shot)"
		"march":
			var bonus = current_game_state.current_order_move_bonus
			var move = unit.base_stats.movement if unit else 0
			order_execute_instruction.text = "Click destination cell (range %d + %d = %d)." % [
				move, bonus, move + bonus
			]
		"move_and_shoot":
			var move = unit.base_stats.movement if unit else 0
			if pending_move_x == -1:
				order_execute_instruction.text = "Click destination (max %d cells), or Skip to stay put." % move
				order_execute_confirm_button.text = "Skip (no move, no shot)"
				order_execute_confirm_button.visible = true
			else:
				order_execute_instruction.text = "Destination: (%d,%d).\nClick enemy to shoot, or Confirm to skip the shot." % [
					pending_move_x, pending_move_y
				]
				order_execute_confirm_button.text = "Confirm move (no shot)"
				order_execute_confirm_button.visible = true


func _render_follower_self_panel() -> void:
	for child in self_target_list.get_children():
		child.queue_free()

	for unit in current_game_state.units:
		if (unit.owner_seat == my_seat and not unit.is_snob()
				and not unit.is_dead and not unit.has_ordered):
			var btn = Button.new()
			btn.text = "%s (%d,%d)" % [unit.unit_type, unit.x, unit.y]
			btn.custom_minimum_size = Vector2(0, 28)
			btn.toggle_mode = true
			btn.button_pressed = (unit.id == selected_target_id)
			btn.pressed.connect(_on_self_target_picked.bind(unit.id))
			self_target_list.add_child(btn)

	_update_self_button_states()


# =============================================================================
# BUTTON HANDLERS
# =============================================================================

func _on_declare_target_picked(unit_id: String) -> void:
	selected_target_id = unit_id
	selected_unit_id = unit_id
	_render_state()


func _on_self_target_picked(unit_id: String) -> void:
	selected_target_id = unit_id
	selected_unit_id = unit_id
	_render_state()


func _on_declare_order_pressed(order_type: String) -> void:
	if selected_target_id == "":
		return
	_send_declare_order(selected_target_id, order_type)
	selected_target_id = ""


func _on_self_order_pressed(order_type: String) -> void:
	if selected_target_id == "":
		return
	_send_declare_self_order(selected_target_id, order_type)
	selected_target_id = ""


func _on_execute_confirm_pressed() -> void:
	var order_type = current_game_state.current_order_type
	# Volley fire / charge fizzle path — no valid targets in range.
	if order_type == "volley_fire" or order_type == "charge":
		_send_execute_order({"fizzle": true})
		return
	# Move-and-shoot: no staged destination → stay put. Otherwise commit.
	if pending_move_x == -1:
		var unit = _get_unit_by_id(current_game_state.current_order_unit_id)
		if not unit:
			return
		_send_execute_order({"x": unit.x, "y": unit.y})
		return
	_send_execute_order({"x": pending_move_x, "y": pending_move_y})


## True if any alive enemy is within Euclidean `reach` of `unit`. No LoS
## check — used for charge fizzle detection (charge ignores LoS in v17).
## For shooting fizzle, use `_has_valid_shooting_target` so closest-target
## + LoS rules match the server.
func _has_valid_enemy_in_range(unit: Types.UnitState, reach: int) -> bool:
	if reach <= 0:
		return false
	for u in current_game_state.units:
		if u.is_dead or u.owner_seat == unit.owner_seat:
			continue
		if Board.grid_distance(unit.x, unit.y, u.x, u.y) <= reach:
			return true
	return false


## True if `shooter` has any legal shooting target right now (in range AND
## with LoS). Delegates to the shared Targeting module so client and server
## cannot diverge on what counts as a valid target.
func _has_valid_shooting_target(shooter: Types.UnitState) -> bool:
	return not Targeting.find_shooting_targets(current_game_state, shooter).is_empty()


# =============================================================================
# VALIDATION HELPERS (client-side hints only — server is authoritative)
# =============================================================================

## Targets a player may legally pick in order_declare: the commanding Snob
## itself, plus alive unordered followers within Euclidean command range.
func _declare_valid_targets() -> Array:
	var results: Array = []
	var snob = _get_unit_by_id(current_game_state.current_snob_id)
	if not snob:
		return results
	# Snob can always self-order
	results.append(snob)
	var cmd_range = snob.get_command_range()
	for unit in current_game_state.units:
		if (unit.owner_seat == my_seat and not unit.is_snob()
				and not unit.is_dead and not unit.has_ordered):
			if Board.grid_distance(snob.x, snob.y, unit.x, unit.y) <= cmd_range:
				results.append(unit)
	return results


func _is_valid_declare_target(unit: Types.UnitState) -> bool:
	var targets = _declare_valid_targets()
	for t in targets:
		if t.id == unit.id:
			return true
	return false


## Can `unit` legally receive `order_type`? Mirror of engine's declare_order
## validation, used to enable/disable order buttons.
func _can_receive_order(unit: Types.UnitState, order_type: String) -> bool:
	if not unit or unit.is_dead or unit.has_ordered:
		return false
	var immobile: bool = "immobile" in unit.special_rules
	match order_type:
		"volley_fire":
			return unit.base_stats.weapon_range > 0 and not unit.has_powder_smoke
		"move_and_shoot":
			return (unit.base_stats.weapon_range > 0
				and not unit.has_powder_smoke
				and not immobile)
		"march":
			return not immobile
		"charge":
			return not immobile
	return false


## Drop stale UI selections when the server-driven state changes phase/order.
func _reconcile_selection_state() -> void:
	var order_phase = current_game_state.order_phase
	# Clear staged move-and-shoot destination whenever we're not executing an order,
	# or when the ordered unit has changed.
	if order_phase != "order_execute":
		pending_move_x = -1
		pending_move_y = -1
	# Clear target selection outside declaration phases, or if target no longer valid.
	if order_phase != "order_declare" and order_phase != "follower_self_order":
		selected_target_id = ""
	elif selected_target_id != "":
		var t = _get_unit_by_id(selected_target_id)
		if not t or t.is_dead or t.owner_seat != my_seat:
			selected_target_id = ""


func _update_declare_button_states() -> void:
	var unit = _get_unit_by_id(selected_target_id)
	# Hide order types the unit can't receive (e.g. move orders for immobile
	# artillery) rather than just disabling them — cuts clutter on units with
	# narrow option sets. No selection → show all, all disabled.
	for order_type in ORDER_TYPES:
		var btn: Button = declare_order_buttons[order_type]
		if unit == null:
			btn.visible = true
			btn.disabled = true
		else:
			var eligible := _can_receive_order(unit, order_type)
			btn.visible = eligible
			btn.disabled = not eligible


func _update_self_button_states() -> void:
	var unit = _get_unit_by_id(selected_target_id)
	for order_type in ORDER_TYPES:
		var btn: Button = self_order_buttons[order_type]
		if unit == null:
			btn.visible = true
			btn.disabled = true
		else:
			var eligible := _can_receive_order(unit, order_type)
			btn.visible = eligible
			btn.disabled = not eligible


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
	var outcome := ""
	var title_color := Color.WHITE
	if winner_seat == my_seat:
		outcome = "VICTORY"
		title_color = Color(0.4, 0.9, 0.4)
	elif winner_seat == 0:
		outcome = "DRAW"
		title_color = Color(0.85, 0.85, 0.55)
	else:
		outcome = "DEFEAT"
		title_color = Color(0.95, 0.45, 0.45)

	turn_banner.text = "%s — %s" % [outcome, reason]
	_add_log_entry("=== GAME OVER: %s — %s ===" % [outcome, reason])
	_show_game_over_overlay(outcome, title_color, reason)


func _show_game_over_overlay(outcome: String, title_color: Color, reason: String) -> void:
	# Guard against double-firing
	if has_node("GameOverOverlay"):
		return

	var rounds_played: int = 0
	var my_units_total: int = 0
	var my_units_alive: int = 0
	var enemy_units_total: int = 0
	var enemy_units_alive: int = 0
	if current_game_state:
		# current_round advances past the last completed round; clamp to max_rounds for display
		rounds_played = mini(current_game_state.current_round, current_game_state.max_rounds)
		for unit in current_game_state.units:
			var is_mine := unit.owner_seat == my_seat
			if is_mine:
				my_units_total += 1
				if not unit.is_dead:
					my_units_alive += 1
			else:
				enemy_units_total += 1
				if not unit.is_dead:
					enemy_units_alive += 1

	var overlay := ColorRect.new()
	overlay.name = "GameOverOverlay"
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = outcome
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", title_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var reason_label := Label.new()
	reason_label.text = reason
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.custom_minimum_size = Vector2(380, 0)
	vbox.add_child(reason_label)

	var separator := HSeparator.new()
	vbox.add_child(separator)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	vbox.add_child(stats)

	var rounds_line := Label.new()
	rounds_line.text = "Rounds played: %d" % rounds_played
	stats.add_child(rounds_line)

	var my_line := Label.new()
	my_line.text = "Your units: %d / %d surviving (%d lost)" % [
		my_units_alive, my_units_total, my_units_total - my_units_alive
	]
	stats.add_child(my_line)

	var enemy_line := Label.new()
	enemy_line.text = "Enemy units: %d / %d surviving (%d lost)" % [
		enemy_units_alive, enemy_units_total, enemy_units_total - enemy_units_alive
	]
	stats.add_child(enemy_line)

	var button := Button.new()
	button.text = "Return to Main Menu"
	button.pressed.connect(_on_return_to_menu_pressed)
	vbox.add_child(button)


func _on_return_to_menu_pressed() -> void:
	print("[Battle] Returning to main menu")
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	NetworkManager.reset_seat()
	get_tree().change_scene_to_file("res://client/main.tscn")


func _on_error_received(message: String) -> void:
	_add_log_entry("Error: " + message)

