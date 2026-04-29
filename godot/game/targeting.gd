class_name Targeting
extends RefCounted
## Line of sight, valid-target enumeration, and charge-cell selection.
##
## Pure RefCounted, no node deps. Imported by both the server engine
## (authoritative validation) and the client renderer (target rings,
## "is this enemy reachable" hints) so client and server cannot diverge
## on what counts as a legal target.
##
## V17 model:
##   - Supercover line of sight (modified Bresenham) — every cell the
##     line touches is checked. Snobs and dead units never block (v17 p.5).
##   - Closest-target restriction on shooting (v17 p.12). Sharpshooters
##     bypass the closest rule but still need range + LoS.
##   - Diagonals are full Euclidean distance (sqrt(dx² + dy²)), so a
##     diagonal-adjacent cell is at √2 ≈ 1.41, NOT 1.

const Board = preload("res://game/board.gd")


## Supercover line-of-sight check between two grid cells.
## Returns true if no alive non-Snob unit (except the two endpoints) occupies
## any cell the line passes through. Snobs never block LoS (v17 p.5).
static func has_line_of_sight(state: Types.GameState, from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
	# Build a set of occupied cells that block LoS (alive non-Snob Followers).
	# Exclude the two endpoint cells.
	var blockers: Dictionary = {}  # "x,y" -> true
	for u in state.units:
		if u.is_dead or u.is_snob():
			continue
		if u.x < 0 or u.y < 0:
			continue
		if (u.x == from_x and u.y == from_y) or (u.x == to_x and u.y == to_y):
			continue
		blockers["%d,%d" % [u.x, u.y]] = true

	if blockers.is_empty():
		return true

	# Supercover line walk: enumerate every cell the line from center of
	# (from_x, from_y) to center of (to_x, to_y) touches or crosses.
	var dx: int = to_x - from_x
	var dy: int = to_y - from_y
	var sx: int = 1 if dx > 0 else (-1 if dx < 0 else 0)
	var sy: int = 1 if dy > 0 else (-1 if dy < 0 else 0)
	var adx: int = abs(dx)
	var ady: int = abs(dy)

	var cx: int = from_x
	var cy: int = from_y

	# Modified Bresenham for supercover (checks diagonal-adjacent cells).
	var error: int = adx - ady

	var steps: int = adx + ady
	for _i in range(steps):
		var e2: int = 2 * error
		if e2 > -ady and e2 < adx:
			# Diagonal step — supercover: check both axis-adjacent cells too
			if blockers.has("%d,%d" % [cx + sx, cy]):
				return false
			if blockers.has("%d,%d" % [cx, cy + sy]):
				return false
			cx += sx
			cy += sy
			error += -ady + adx
		elif e2 > -ady:
			cx += sx
			error -= ady
		else:
			cy += sy
			error += adx

		# Skip endpoint
		if cx == to_x and cy == to_y:
			break
		if blockers.has("%d,%d" % [cx, cy]):
			return false

	return true


## Find all valid shooting targets for a unit: alive enemies in weapon range
## with line of sight.
static func find_shooting_targets(state: Types.GameState, shooter: Types.UnitState) -> Array:
	return find_shooting_targets_from(state, shooter, shooter.x, shooter.y)


## Find shooting targets from an arbitrary position (for move_and_shoot post-move).
static func find_shooting_targets_from(state: Types.GameState, shooter: Types.UnitState, from_x: int, from_y: int) -> Array:
	var targets: Array = []
	var wr: int = shooter.base_stats.weapon_range
	if wr <= 0:
		return targets
	for u in state.units:
		if u.is_dead or u.owner_seat == shooter.owner_seat:
			continue
		if u.x < 0 or u.y < 0:
			continue
		var d := Board.grid_distance(from_x, from_y, u.x, u.y)
		if d <= wr and has_line_of_sight(state, from_x, from_y, u.x, u.y):
			targets.append(u)
	return targets


## Validate whether a specific target is legal for shooting.
## Returns "" if valid, error string if not. Enforces closest-target rule
## (v17 p.12): must target the closest valid enemy in range + LoS (ties
## allowed — any tied target is legal). Sharpshooters bypass closest but
## still need LoS.
static func is_valid_shooting_target(state: Types.GameState, shooter: Types.UnitState, target: Types.UnitState) -> String:
	return is_valid_shooting_target_from(state, shooter, target, shooter.x, shooter.y)


## Same as is_valid_shooting_target but with the shooter at (from_x, from_y)
## (used for move_and_shoot post-move validation).
static func is_valid_shooting_target_from(state: Types.GameState, shooter: Types.UnitState, target: Types.UnitState, from_x: int, from_y: int) -> String:
	if target.is_dead:
		return "Target is dead"
	if target.owner_seat == shooter.owner_seat:
		return "Cannot target your own units"

	var distance := Board.grid_distance(from_x, from_y, target.x, target.y)
	if distance > shooter.base_stats.weapon_range:
		return "Target out of range (max %d)" % shooter.base_stats.weapon_range

	if not has_line_of_sight(state, from_x, from_y, target.x, target.y):
		return "No line of sight to target"

	# Closest-target enforcement (skip for Sharpshooters)
	if "sharpshooters" not in shooter.special_rules:
		var valid_targets := find_shooting_targets_from(state, shooter, from_x, from_y)
		if valid_targets.is_empty():
			return "No valid targets in range with LoS"
		var min_dist: float = 99999.0
		for vt in valid_targets:
			var vd := Board.grid_distance(from_x, from_y, vt.x, vt.y)
			if vd < min_dist:
				min_dist = vd
		if distance > min_dist + 0.01:  # epsilon for float comparison
			return "Must target closest enemy (closest is at %.1f, target is at %.1f)" % [min_dist, distance]

	return ""


## Find the best adjacent cell to a target for a charging unit.
##
## Iterates all 8 neighbors (4 cardinal + 4 diagonal). v17 base contact is
## "touching base", which on the integer grid means any of the 8 ring cells
## around the target. Tie-break: cell closest to the charger.
static func find_adjacent_cell(state: Types.GameState, charger: Types.UnitState, target: Types.UnitState) -> Vector2i:
	var best = Vector2i(-1, -1)
	var best_dist = 9999.0

	for offset in [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]:
		var cx = target.x + offset.x
		var cy = target.y + offset.y
		if not Board.is_in_bounds(cx, cy):
			continue
		# Not occupied by another live unit (charger may "occupy" its source).
		var occupied = false
		for u in state.units:
			if not u.is_dead and u.x == cx and u.y == cy and u.id != charger.id:
				occupied = true
				break
		if occupied:
			continue
		# Objective cells are invalid end-of-move destinations (v17 p.22).
		var on_objective = false
		for obj in state.objectives:
			if obj.x == cx and obj.y == cy:
				on_objective = true
				break
		if on_objective:
			continue
		var dist = Board.grid_distance(charger.x, charger.y, cx, cy)
		if dist < best_dist:
			best_dist = dist
			best = Vector2i(cx, cy)

	return best
