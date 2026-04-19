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
