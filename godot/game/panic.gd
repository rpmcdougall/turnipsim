class_name Panic
extends RefCounted
## Panic tests, Fearless override, and forced retreat movement.
##
## Pure RefCounted, no node deps. Mutates the GameState in place when
## executing retreat (moves the unit, marks it dead on board-edge).
##
## V17 model:
##   - Panic test (v17 core p.19): roll D6 + panic_tokens. ≤6 pass, ≥7 fail.
##     Natural 1 always passes. 0 tokens auto-pass (skip the test entirely).
##   - Fearless override: a unit that fails its panic test gets a second
##     chance if Fearless. fearless_die ≥ 3 = override to pass.
##     Sources of Fearless: "fearless" rule (Brutes) or "safety_in_numbers"
##     with model_count ≥ 8 (Fodder).
##   - Retreat (v17 core p.20): D6 + 2" per panic token, away from nearest
##     enemy. Off-board ends the unit (destroyed). Stubborn Fanatics never
##     retreat (Stump Gun). DT through Followers deferred to terrain (#58).

const Board = preload("res://game/board.gd")


## Check whether a unit is currently Fearless (3+ to ignore forced retreat).
## Sources: "fearless" special rule (Brutes), or "safety_in_numbers" with 8+
## models alive (Fodder).
static func is_fearless(unit: Types.UnitState) -> bool:
	if "fearless" in unit.special_rules:
		return true
	if "safety_in_numbers" in unit.special_rules and unit.model_count >= 8:
		return true
	return false


## Panic test per v17 core p.19.
## Roll D6 + panic_tokens: ≤6 pass, ≥7 fail (must retreat).
## Natural 1 always passes. 0 tokens auto-pass (skip test).
## Fearless units that fail get a second chance: fearless_die 3+ = override to pass.
##
## Returns { passed, roll, total, auto_passed, fearless_override, used_fearless }.
## Does NOT modify unit state — caller applies consequences.
static func panic_test(unit: Types.UnitState, panic_die: int, fearless_die: int) -> Dictionary:
	var result = {
		"passed": true,
		"roll": panic_die,
		"total": 0,
		"auto_passed": false,
		"fearless_override": false,
		"used_fearless": false,
	}

	# 0 tokens = auto-pass (v17: "units with zero panic tokens can skip the test")
	if unit.panic_tokens == 0:
		result["auto_passed"] = true
		return result

	# Natural 1 always passes
	if panic_die == 1:
		return result

	var total: int = panic_die + unit.panic_tokens
	result["total"] = total

	if total <= 6:
		# Passed normally
		return result

	# Failed — check Fearless override
	if is_fearless(unit):
		result["used_fearless"] = true
		if fearless_die >= 3:
			result["fearless_override"] = true
			return result

	result["passed"] = false
	return result


## Find the nearest alive enemy unit to the given unit.
static func find_nearest_enemy(state: Types.GameState, unit: Types.UnitState) -> Types.UnitState:
	var best: Types.UnitState = null
	var best_dist: float = 99999.0
	for u in state.units:
		if u.is_dead or u.owner_seat == unit.owner_seat:
			continue
		if u.x < 0 or u.y < 0:
			continue
		var d := Board.grid_distance(unit.x, unit.y, u.x, u.y)
		if d < best_dist:
			best_dist = d
			best = u
	return best


## Execute retreat for a unit. Mutates state in place.
## v17 core p.20: move directly away from closest enemy, D6 + 2" per panic
## token. Board edge = unit destroyed. Stubborn Fanatics never retreat.
##
## `retreat_die` is a pre-rolled D6 supplied by the caller (1..6). Pass 1 for
## the minimum distance when a test intentionally suppresses the D6 component.
##
## Returns { retreated, destroyed, from_x, from_y, to_x, to_y, distance,
##           retreat_die, stubborn_held, no_enemy }.
## DT tests for crossing Followers deferred to terrain system (#58).
static func execute_retreat(state: Types.GameState, unit_id: String, retreat_die: int) -> Dictionary:
	var unit = _find_unit(state, unit_id)
	var result = {
		"retreated": false,
		"destroyed": false,
		"from_x": unit.x, "from_y": unit.y,
		"to_x": unit.x, "to_y": unit.y,
		"distance": 0,
		"retreat_die": retreat_die,
		"stubborn_held": false,
		"no_enemy": false,
	}

	if not unit or unit.is_dead:
		return result

	# Stubborn Fanatics: never retreat (Stump Gun)
	if "stubborn_fanatics" in unit.special_rules:
		result["stubborn_held"] = true
		return result

	# Retreat distance: D6 + 2" per panic token (v17 core p.20).
	var retreat_dist: int = retreat_die + unit.panic_tokens * 2
	result["distance"] = retreat_dist

	# Direction: away from nearest alive enemy
	var nearest_enemy = find_nearest_enemy(state, unit)
	if not nearest_enemy:
		# No enemies alive — nowhere to retreat from. Stay put.
		result["no_enemy"] = true
		return result

	var dx: float = float(unit.x - nearest_enemy.x)
	var dy: float = float(unit.y - nearest_enemy.y)
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist < 0.001:
		# On top of enemy (shouldn't happen). Default direction: toward own deployment zone.
		dy = 1.0 if unit.owner_seat == 1 else -1.0
		dx = 0.0
		dist = 1.0

	# Normalize direction
	dx /= dist
	dy /= dist

	# Ideal retreat destination
	var ideal_x: float = float(unit.x) + dx * float(retreat_dist)
	var ideal_y: float = float(unit.y) + dy * float(retreat_dist)
	var target_x: int = clampi(roundi(ideal_x), 0, Board.BOARD_WIDTH - 1)
	var target_y: int = clampi(roundi(ideal_y), 0, Board.BOARD_HEIGHT - 1)

	# Board edge check: if the ideal position is off the board, unit is destroyed.
	if not Board.is_in_bounds(roundi(ideal_x), roundi(ideal_y)):
		unit.is_dead = true
		unit.model_count = 0
		unit.x = -1
		unit.y = -1
		result["retreated"] = true
		result["destroyed"] = true
		result["to_x"] = -1
		result["to_y"] = -1
		return result

	# Find the best valid cell near the target
	var dest = _find_retreat_cell(state, unit, target_x, target_y)
	if dest.x == -1:
		# No valid cell found — stay in place (edge case, shouldn't normally happen)
		return result

	unit.x = dest.x
	unit.y = dest.y
	result["retreated"] = true
	result["to_x"] = dest.x
	result["to_y"] = dest.y
	return result


## Find a valid retreat destination cell near (target_x, target_y).
## Searches the target cell first, then spirals outward. Returns Vector2i(-1,-1)
## if nothing found within a reasonable radius.
static func _find_retreat_cell(state: Types.GameState, unit: Types.UnitState, target_x: int, target_y: int) -> Vector2i:
	# Try the ideal cell first
	if _is_valid_retreat_dest(state, unit, target_x, target_y):
		return Vector2i(target_x, target_y)

	# Spiral outward looking for an alternative
	for radius in range(1, 6):
		var best = Vector2i(-1, -1)
		var best_dist: float = 99999.0
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dy) != radius:
					continue  # Skip inner cells already checked
				var cx: int = target_x + dx
				var cy: int = target_y + dy
				if _is_valid_retreat_dest(state, unit, cx, cy):
					var d := Board.grid_distance(target_x, target_y, cx, cy)
					if d < best_dist:
						best_dist = d
						best = Vector2i(cx, cy)
		if best.x != -1:
			return best

	return Vector2i(-1, -1)


## Is this cell a valid retreat destination? Bounds, not occupied by another
## live unit, not on an objective marker (v17 p.22).
static func _is_valid_retreat_dest(state: Types.GameState, unit: Types.UnitState, x: int, y: int) -> bool:
	if not Board.is_in_bounds(x, y):
		return false
	for u in state.units:
		if not u.is_dead and u.id != unit.id and u.x == x and u.y == y:
			return false
	for obj in state.objectives:
		if obj.x == x and obj.y == y:
			return false
	return true


## Find a unit by ID in a GameState. Local helper so panic.gd doesn't need
## to depend on the engine's _find_unit.
static func _find_unit(state: Types.GameState, unit_id: String) -> Types.UnitState:
	for u in state.units:
		if u.id == unit_id:
			return u
	return null
