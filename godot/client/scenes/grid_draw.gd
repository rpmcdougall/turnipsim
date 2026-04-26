extends Control
## Draws the game board grid, deployment zones, and cell highlights.

const Board = preload("res://game/board.gd")

var battle_ref = null  # Reference to battle.gd for cell_size and state


func _draw() -> void:
	if not battle_ref:
		return

	var cs = battle_ref.cell_size
	if cs <= 0:
		return

	var bw = Board.BOARD_WIDTH
	var bh = Board.BOARD_HEIGHT

	# Board background
	draw_rect(Rect2(0, 0, bw * cs, bh * cs), Color(0.12, 0.12, 0.16))

	# Deployment zones
	# Seat 1 (bottom) — blue tint
	draw_rect(
		Rect2(0, Board.DEPLOYMENT_ZONE_1_Y_MIN * cs, bw * cs, (Board.DEPLOYMENT_ZONE_1_Y_MAX - Board.DEPLOYMENT_ZONE_1_Y_MIN + 1) * cs),
		Color(0.15, 0.2, 0.35, 0.5)
	)
	# Seat 2 (top) — red tint
	draw_rect(
		Rect2(0, Board.DEPLOYMENT_ZONE_2_Y_MIN * cs, bw * cs, (Board.DEPLOYMENT_ZONE_2_Y_MAX - Board.DEPLOYMENT_ZONE_2_Y_MIN + 1) * cs),
		Color(0.35, 0.15, 0.15, 0.5)
	)

	# Grid lines
	var line_color = Color(0.3, 0.3, 0.35, 0.4)
	for x in range(bw + 1):
		draw_line(Vector2(x * cs, 0), Vector2(x * cs, bh * cs), line_color, 1.0)
	for y in range(bh + 1):
		draw_line(Vector2(0, y * cs), Vector2(bw * cs, y * cs), line_color, 1.0)

	# Zone labels
	var font = ThemeDB.fallback_font
	if font:
		var font_size = clampi(int(cs * 0.8), 10, 20)
		draw_string(font, Vector2(4, Board.DEPLOYMENT_ZONE_2_Y_MAX * cs + cs * 0.8), "P2 Deploy", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.6, 0.6, 0.6))
		draw_string(font, Vector2(4, Board.DEPLOYMENT_ZONE_1_Y_MIN * cs + cs * 0.8), "P1 Deploy", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.6, 1.0, 0.6))

	var state = battle_ref.current_game_state

	# Objective markers. Drawn before command/reach overlays so they show
	# through tints, but before unit sprites (handled in battle.gd's
	# units_container) so units on adjacent cells still read clearly.
	if state:
		for obj in state.objectives:
			_draw_objective_marker(obj, cs)

	# Command-range overlay: Euclidean circle around the Made-Ready Snob.
	if state and state.order_phase == "order_declare" and state.current_snob_id != "":
		var snob = battle_ref._get_unit_by_id(state.current_snob_id)
		if snob and snob.x >= 0 and snob.y >= 0:
			_draw_range_circle(snob.x, snob.y, snob.get_command_range(), cs, bw, bh,
				Color(1.0, 0.95, 0.4, 0.12), Color(1.0, 0.9, 0.3, 0.8))

	# Order-execute overlay: reach diamond + valid target outlines for the
	# acting unit. Client-side hint only — server remains authoritative.
	if state and state.order_phase == "order_execute":
		_draw_order_execute_overlay(state, cs, bw, bh)


## Draw an objective marker: filled circle in the cell's center, colored by
## the controlling seat (neutral grey when uncaptured), with a darker outline
## for contrast against both board and highlight overlays.
func _draw_objective_marker(obj, cs: float) -> void:
	var fill: Color
	var outline: Color
	match obj.captured_by:
		1:
			fill = Color(0.35, 0.6, 1.0, 0.95)
			outline = Color(0.15, 0.3, 0.6, 1.0)
		2:
			fill = Color(1.0, 0.4, 0.4, 0.95)
			outline = Color(0.6, 0.15, 0.15, 1.0)
		_:
			fill = Color(0.85, 0.85, 0.85, 0.9)
			outline = Color(0.3, 0.3, 0.3, 1.0)

	var center = Vector2((obj.x + 0.5) * cs, (obj.y + 0.5) * cs)
	var radius = cs * 0.38
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 32, outline, 2.0, true)

	# Center dot emphasizes captured state without leaning on text rendering.
	if obj.captured_by != 0:
		draw_circle(center, radius * 0.35, outline)


## Fill every cell whose Euclidean distance from (cx, cy) is ≤ range with a
## translucent highlight, and outline the circle boundary.
func _draw_range_circle(cx: int, cy: int, range_cells: int, cs: float, bw: int, bh: int, fill: Color, outline: Color) -> void:
	if range_cells <= 0:
		return
	var r_sq: float = float(range_cells * range_cells)
	for dy in range(-range_cells, range_cells + 1):
		var y = cy + dy
		if y < 0 or y >= bh:
			continue
		for dx in range(-range_cells, range_cells + 1):
			var x = cx + dx
			if x < 0 or x >= bw:
				continue
			if float(dx * dx + dy * dy) <= r_sq:
				draw_rect(Rect2(x * cs, y * cs, cs, cs), fill)
	# Circle outline centered on the cell
	var center = Vector2((cx + 0.5) * cs, (cy + 0.5) * cs)
	var radius = (range_cells + 0.5) * cs
	draw_arc(center, radius, 0.0, TAU, 64, outline, 1.5, true)


## Draw reach circle + valid-target cell outlines for the acting unit during
## order_execute. Reach semantics mirror game_engine.gd (Euclidean distance):
##   volley_fire      → weapon_range from unit.pos
##   march            → M + move_bonus from unit.pos (no targets)
##   charge           → M + move_bonus from unit.pos (enemies within)
##   move_and_shoot   → M (or move_bonus if blundered) from unit.pos for the
##                      move; after staging, weapon_range from the staged cell
##                      for the shot.
func _draw_order_execute_overlay(state, cs: float, bw: int, bh: int) -> void:
	var unit = battle_ref._get_unit_by_id(state.current_order_unit_id)
	if not unit or unit.x < 0 or unit.y < 0:
		return

	# Only show hints to the seat whose turn it is.
	if unit.owner_seat != battle_ref.my_seat:
		return

	var order_type: String = state.current_order_type
	var move_bonus: int = state.current_order_move_bonus
	var blundered: bool = state.current_order_blundered

	# Cyan for move reach, orange for weapon/shoot reach, red for charge reach.
	var move_fill = Color(0.3, 0.8, 1.0, 0.10)
	var move_outline = Color(0.4, 0.85, 1.0, 0.7)
	var shoot_fill = Color(1.0, 0.6, 0.2, 0.10)
	var shoot_outline = Color(1.0, 0.7, 0.3, 0.75)
	var charge_fill = Color(1.0, 0.3, 0.3, 0.10)
	var charge_outline = Color(1.0, 0.4, 0.3, 0.75)

	var target_cells: Array = []

	match order_type:
		"volley_fire":
			var reach = unit.base_stats.weapon_range
			_draw_range_circle(unit.x, unit.y, reach, cs, bw, bh, shoot_fill, shoot_outline)
			target_cells = _enemy_cells_within(unit.x, unit.y, reach, unit.owner_seat)
		"march":
			var reach = unit.base_stats.movement + move_bonus
			_draw_range_circle(unit.x, unit.y, reach, cs, bw, bh, move_fill, move_outline)
		"charge":
			var reach = unit.base_stats.movement + move_bonus
			_draw_range_circle(unit.x, unit.y, reach, cs, bw, bh, charge_fill, charge_outline)
			target_cells = _enemy_cells_within(unit.x, unit.y, reach, unit.owner_seat)
		"move_and_shoot":
			var max_move: int = unit.base_stats.movement
			if blundered:
				max_move = move_bonus
			if battle_ref.pending_move_x < 0:
				_draw_range_circle(unit.x, unit.y, max_move, cs, bw, bh, move_fill, move_outline)
			else:
				var px: int = battle_ref.pending_move_x
				var py: int = battle_ref.pending_move_y
				# Fading outline of move reach for context
				_draw_range_circle(unit.x, unit.y, max_move, cs, bw, bh,
					Color(0.3, 0.8, 1.0, 0.04), Color(0.4, 0.85, 1.0, 0.35))
				# Shoot reach from the staged cell
				var reach = unit.base_stats.weapon_range
				_draw_range_circle(px, py, reach, cs, bw, bh, shoot_fill, shoot_outline)
				target_cells = _enemy_cells_within(px, py, reach, unit.owner_seat)
				# Mark the staged cell itself
				draw_rect(Rect2(px * cs, py * cs, cs, cs), Color(1.0, 1.0, 0.4, 0.25))
				draw_rect(Rect2(px * cs, py * cs, cs, cs), Color(1.0, 1.0, 0.4, 0.9), false, 2.0)

	# Green ring around each valid enemy target cell.
	var target_ring = Color(0.4, 1.0, 0.4, 0.95)
	var inset = maxf(1.5, cs * 0.08)
	for cell in target_cells:
		draw_rect(
			Rect2(cell.x * cs + inset, cell.y * cs + inset, cs - inset * 2, cs - inset * 2),
			target_ring, false, 2.0
		)


## Return cell coords of alive enemies within Euclidean distance `reach` of
## (cx, cy). Empty when reach <= 0.
func _enemy_cells_within(cx: int, cy: int, reach: int, own_seat: int) -> Array:
	var out: Array = []
	if reach <= 0:
		return out
	var state = battle_ref.current_game_state
	if not state:
		return out
	var r_sq: float = float(reach * reach)
	for u in state.units:
		if u.is_dead or u.owner_seat == own_seat:
			continue
		if u.x < 0 or u.y < 0:
			continue
		var dx: int = u.x - cx
		var dy: int = u.y - cy
		if float(dx * dx + dy * dy) <= r_sq:
			out.append(Vector2i(u.x, u.y))
	return out
