extends Control
## Draws the game board grid, deployment zones, and cell highlights.

var battle_ref = null  # Reference to battle.gd for cell_size and state


func _draw() -> void:
	if not battle_ref:
		return

	var cs = battle_ref.cell_size
	if cs <= 0:
		return

	var bw = battle_ref.BOARD_WIDTH
	var bh = battle_ref.BOARD_HEIGHT

	# Board background
	draw_rect(Rect2(0, 0, bw * cs, bh * cs), Color(0.12, 0.12, 0.16))

	# Deployment zones
	# Seat 1 (bottom) — blue tint
	draw_rect(
		Rect2(0, battle_ref.DEPLOY_1_Y_MIN * cs, bw * cs, (battle_ref.DEPLOY_1_Y_MAX - battle_ref.DEPLOY_1_Y_MIN + 1) * cs),
		Color(0.15, 0.2, 0.35, 0.5)
	)
	# Seat 2 (top) — red tint
	draw_rect(
		Rect2(0, battle_ref.DEPLOY_2_Y_MIN * cs, bw * cs, (battle_ref.DEPLOY_2_Y_MAX - battle_ref.DEPLOY_2_Y_MIN + 1) * cs),
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
		draw_string(font, Vector2(4, battle_ref.DEPLOY_2_Y_MAX * cs + cs * 0.8), "P2 Deploy", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.6, 0.6, 0.6))
		draw_string(font, Vector2(4, battle_ref.DEPLOY_1_Y_MIN * cs + cs * 0.8), "P1 Deploy", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.6, 0.6, 1.0, 0.6))

	# Command-range overlay: Manhattan diamond around the Made-Ready Snob.
	# Matches the engine's |dx| + |dy| <= range check used by declare_order.
	var state = battle_ref.current_game_state
	if state and state.current_snob_id != "":
		var snob = battle_ref._get_unit_by_id(state.current_snob_id)
		if snob and snob.x >= 0 and snob.y >= 0:
			_draw_command_diamond(snob.x, snob.y, snob.get_command_range(), cs, bw, bh)


## Fill every cell whose Manhattan distance from (cx, cy) is ≤ range with a
## translucent highlight, and outline the diamond boundary.
func _draw_command_diamond(cx: int, cy: int, range_cells: int, cs: float, bw: int, bh: int) -> void:
	if range_cells <= 0:
		return
	var fill = Color(1.0, 0.95, 0.4, 0.12)
	for dy in range(-range_cells, range_cells + 1):
		var span = range_cells - abs(dy)
		var y = cy + dy
		if y < 0 or y >= bh:
			continue
		var x_start = maxi(cx - span, 0)
		var x_end = mini(cx + span, bw - 1)
		draw_rect(
			Rect2(x_start * cs, y * cs, (x_end - x_start + 1) * cs, cs),
			fill
		)
	# Outline the diamond's four edges
	var outline = Color(1.0, 0.9, 0.3, 0.8)
	var top = Vector2((cx + 0.5) * cs, (cy - range_cells) * cs)
	var bottom = Vector2((cx + 0.5) * cs, (cy + range_cells + 1) * cs)
	var left = Vector2((cx - range_cells) * cs, (cy + 0.5) * cs)
	var right = Vector2((cx + range_cells + 1) * cs, (cy + 0.5) * cs)
	draw_line(top, right, outline, 1.5)
	draw_line(right, bottom, outline, 1.5)
	draw_line(bottom, left, outline, 1.5)
	draw_line(left, top, outline, 1.5)
