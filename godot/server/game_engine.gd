class_name GameEngine
extends RefCounted
## Authoritative game engine for Turnip28 battle simulation.
##
## All functions are pure: (state, action, dice) -> new state.
## Dice rolls are injected via parameters for deterministic testing.
## No mutation of input state — always return new state via cloning.
##
## V17 Order Sequence:
##   1. Players alternate selecting Snobs to "Make Ready"
##   2. Snob orders a Follower in command range (or itself)
##   3. Blunder check (D6, on 1 = blunder + panic token)
##   4. Execute order (Volley Fire, Move & Shoot, March, Charge)
##   5. After all Snobs ordered, unordered Followers order themselves
##   6. Round ends, advance to next round

# Board constants
const BOARD_WIDTH: int = 48
const BOARD_HEIGHT: int = 32


## Euclidean distance between two grid cells.
## All range/movement checks use this instead of Manhattan distance so that
## diagonal distances are geometrically correct (1 cell = 1 inch).
static func _grid_distance(x1: int, y1: int, x2: int, y2: int) -> float:
	var dx: int = x2 - x1
	var dy: int = y2 - y1
	return sqrt(float(dx * dx + dy * dy))

# Deployment zones (4 rows each)
const DEPLOYMENT_ZONE_1_Y_MIN: int = 28  # Bottom (seat 1)
const DEPLOYMENT_ZONE_1_Y_MAX: int = 31
const DEPLOYMENT_ZONE_2_Y_MIN: int = 0   # Top (seat 2)
const DEPLOYMENT_ZONE_2_Y_MAX: int = 3

# Melee bout cap — v17 has no hard limit, but tied bouts could loop forever on
# whiffing dice. Cap at 3; unresolved ties after the cap end in a draw with no
# retreat (both sides still take +1 panic per melee-ended rule).
const MELEE_MAX_BOUTS: int = 3


# =============================================================================
# PLACEMENT PHASE
# =============================================================================

## Place a unit at the given coordinates during placement phase.
static func place_unit(state: Types.GameState, unit_id: String, x: int, y: int) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "placement":
		result.error = "Not in placement phase"
		return result

	var unit: Types.UnitState = null
	for u in state.units:
		if u.id == unit_id:
			unit = u
			break

	if not unit:
		result.error = "Unit not found: " + unit_id
		return result

	if unit.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result

	if unit.x != -1 or unit.y != -1:
		result.error = "Unit already placed"
		return result

	if x < 0 or x >= BOARD_WIDTH or y < 0 or y >= BOARD_HEIGHT:
		result.error = "Coordinates out of bounds"
		return result

	var valid_zone: bool = false
	if state.active_seat == 1:
		if y >= DEPLOYMENT_ZONE_1_Y_MIN and y <= DEPLOYMENT_ZONE_1_Y_MAX:
			valid_zone = true
	else:
		if y >= DEPLOYMENT_ZONE_2_Y_MIN and y <= DEPLOYMENT_ZONE_2_Y_MAX:
			valid_zone = true

	if not valid_zone:
		result.error = "Not in your deployment zone"
		return result

	for u in state.units:
		if u.x == x and u.y == y:
			result.error = "Position occupied"
			return result

	var new_state = _clone_state(state)

	for u in new_state.units:
		if u.id == unit_id:
			u.x = x
			u.y = y
			break

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "place",
		"unit_id": unit_id,
		"unit_type": unit.unit_type,
		"x": x,
		"y": y
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s placed at (%d, %d)" % [unit.unit_type, x, y]

	return result


## Confirm placement for the active player.
static func confirm_placement(state: Types.GameState) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "placement":
		result.error = "Not in placement phase"
		return result

	for unit in state.units:
		if unit.owner_seat == state.active_seat:
			if unit.x == -1 or unit.y == -1:
				result.error = "Not all units placed"
				return result

	var new_state = _clone_state(state)

	var other_seat = 3 - state.active_seat
	var other_player_done: bool = true

	for unit in state.units:
		if unit.owner_seat == other_seat:
			if unit.x == -1 or unit.y == -1:
				other_player_done = false
				break

	if other_player_done:
		new_state.phase = "orders"
		new_state.order_phase = "snob_select"
		new_state.active_seat = new_state.initiative_seat
		# v17 p.22: "Objectives with units deployed within 1" are considered
		# captured." Run the resolver once deployment is final.
		_resolve_objective_captures(new_state)
		new_state.action_log.append({
			"round": state.current_round,
			"action": "orders_phase_started"
		})
		result.description = "Orders phase started!"
	else:
		new_state.active_seat = other_seat
		new_state.action_log.append({
			"round": state.current_round,
			"action": "placement_confirmed",
			"seat": state.active_seat
		})
		result.description = "Player %d placement confirmed. Player %d's turn." % [state.active_seat, other_seat]

	result.success = true
	result.new_state = new_state

	return result


# =============================================================================
# ORDERS PHASE — V17 ORDER SEQUENCE
# =============================================================================

## Step 1: Select a Snob to Make Ready.
static func select_snob(state: Types.GameState, snob_id: String) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result
	if state.order_phase != "snob_select":
		result.error = "Not in snob selection phase (current: %s)" % state.order_phase
		return result

	var snob = _find_unit(state, snob_id)
	if not snob:
		result.error = "Snob not found"
		return result
	if not snob.is_snob():
		result.error = "Unit is not a Snob"
		return result
	if snob.owner_seat != state.active_seat:
		result.error = "Not your Snob"
		return result
	if snob.is_dead:
		result.error = "Snob is dead"
		return result
	if snob.has_ordered:
		result.error = "Snob already ordered this round"
		return result

	var new_state = _clone_state(state)
	new_state.order_phase = "order_declare"
	new_state.current_snob_id = snob_id

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "select_snob",
		"snob_id": snob_id,
		"snob_type": snob.unit_type
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s Made Ready" % snob.unit_type

	return result


## Step 2: Declare an order for a unit.
## unit_id: the Follower to order (or the Snob itself)
## order_type: "volley_fire", "move_and_shoot", "march", "charge"
## blunder_die: D6 roll for blunder check (1 = blunder)
## move_dice: Array of D6 rolls for march/charge bonus movement [d1, d2]
static func declare_order(state: Types.GameState, unit_id: String, order_type: String, blunder_die: int, move_dice: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result
	if state.order_phase != "order_declare":
		result.error = "Not in order declaration phase"
		return result

	var snob = _find_unit(state, state.current_snob_id)
	if not snob:
		result.error = "Current Snob not found"
		return result

	var unit = _find_unit(state, unit_id)
	if not unit:
		result.error = "Unit not found"
		return result
	if unit.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result
	if unit.is_dead:
		result.error = "Unit is dead"
		return result
	if unit.has_ordered:
		result.error = "Unit already ordered this round"
		return result

	var ordering_self = (unit_id == state.current_snob_id)

	# Command range check (skip if ordering self)
	if not ordering_self:
		if unit.is_snob():
			result.error = "Cannot order another Snob"
			return result
		var distance = _grid_distance(snob.x, snob.y, unit.x, unit.y)
		if distance > snob.get_command_range():
			result.error = "Unit out of command range (%.1f > %d)" % [distance, snob.get_command_range()]
			return result

	# Validate order type
	if order_type not in ["volley_fire", "move_and_shoot", "march", "charge"]:
		result.error = "Invalid order type: " + order_type
		return result

	# Validate order is legal for unit
	if order_type == "volley_fire" and unit.base_stats.weapon_range <= 0:
		result.error = "Cannot Volley Fire without ranged weapon"
		return result
	if order_type == "volley_fire" and unit.has_powder_smoke:
		result.error = "Cannot Volley Fire with powder smoke"
		return result
	if order_type == "move_and_shoot" and unit.base_stats.weapon_range <= 0:
		result.error = "Cannot Move and Shoot without ranged weapon"
		return result
	if order_type == "move_and_shoot" and unit.has_powder_smoke:
		result.error = "Cannot Move and Shoot with powder smoke"
		return result
	if order_type in ["march", "charge", "move_and_shoot"] and "immobile" in unit.special_rules:
		result.error = "Immobile unit cannot %s" % order_type
		return result

	var new_state = _clone_state(state)

	# Blunder check: Snobs ordering themselves never blunder
	var blundered = false
	if not ordering_self and blunder_die == 1:
		blundered = true
		var new_unit = _find_unit_in(new_state, unit_id)
		new_unit.panic_tokens = mini(new_unit.panic_tokens + 1, 6)

	new_state.order_phase = "order_execute"
	new_state.current_order_unit_id = unit_id
	new_state.current_order_type = order_type
	new_state.current_order_blundered = blundered

	# Compute move bonus for march/charge (stored so client can show range).
	# Also for blundered move_and_shoot, since _execute_move_and_shoot reads
	# move_bonus as the capped movement (1D6) when blundered.
	var move_bonus = 0
	if order_type in ["march", "charge"]:
		if move_dice.size() >= 2:
			move_bonus = move_dice[0] + move_dice[1] if not blundered else move_dice[0]
		elif move_dice.size() >= 1:
			move_bonus = move_dice[0]
	elif order_type == "move_and_shoot" and blundered:
		if move_dice.size() >= 1:
			move_bonus = move_dice[0]
	new_state.current_order_move_bonus = move_bonus

	var blunder_text = " [BLUNDERED!]" if blundered else ""
	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "declare_order",
		"unit_id": unit_id,
		"unit_type": unit.unit_type,
		"order_type": order_type,
		"blundered": blundered,
		"blunder_die": blunder_die,
		"move_bonus": move_bonus
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = [blunder_die] + move_dice
	result.description = "%s ordered to %s%s (move bonus: +%d)" % [
		unit.unit_type, order_type.replace("_", " ").capitalize(), blunder_text, move_bonus
	]

	return result


## Step 2b: Declare a self-order for an unordered Follower (follower_self_order phase).
## Same as declare_order but no snob, always blunder-checks.
static func declare_self_order(state: Types.GameState, unit_id: String, order_type: String, blunder_die: int, move_dice: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result
	if state.order_phase != "follower_self_order":
		result.error = "Not in follower self-order phase"
		return result

	var unit = _find_unit(state, unit_id)
	if not unit:
		result.error = "Unit not found"
		return result
	if unit.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result
	if unit.is_dead:
		result.error = "Unit is dead"
		return result
	if unit.has_ordered:
		result.error = "Unit already ordered this round"
		return result
	if unit.is_snob():
		result.error = "Snobs don't self-order"
		return result

	# Validate order type
	if order_type not in ["volley_fire", "move_and_shoot", "march", "charge"]:
		result.error = "Invalid order type: " + order_type
		return result
	if order_type == "volley_fire" and (unit.base_stats.weapon_range <= 0 or unit.has_powder_smoke):
		result.error = "Cannot Volley Fire"
		return result
	if order_type == "move_and_shoot" and (unit.base_stats.weapon_range <= 0 or unit.has_powder_smoke):
		result.error = "Cannot Move and Shoot"
		return result
	if order_type in ["march", "charge", "move_and_shoot"] and "immobile" in unit.special_rules:
		result.error = "Immobile unit cannot %s" % order_type
		return result

	var new_state = _clone_state(state)

	# Always blunder check for self-ordering followers
	var blundered = (blunder_die == 1)
	if blundered:
		var new_unit = _find_unit_in(new_state, unit_id)
		new_unit.panic_tokens = mini(new_unit.panic_tokens + 1, 6)

	new_state.order_phase = "order_execute"
	new_state.current_snob_id = ""  # No snob commanding
	new_state.current_order_unit_id = unit_id
	new_state.current_order_type = order_type
	new_state.current_order_blundered = blundered

	var move_bonus = 0
	if order_type in ["march", "charge"]:
		if move_dice.size() >= 2:
			move_bonus = move_dice[0] + move_dice[1] if not blundered else move_dice[0]
		elif move_dice.size() >= 1:
			move_bonus = move_dice[0]
	elif order_type == "move_and_shoot" and blundered:
		if move_dice.size() >= 1:
			move_bonus = move_dice[0]
	new_state.current_order_move_bonus = move_bonus

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "declare_self_order",
		"unit_id": unit_id,
		"unit_type": unit.unit_type,
		"order_type": order_type,
		"blundered": blundered,
		"blunder_die": blunder_die,
		"move_bonus": move_bonus
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = [blunder_die] + move_dice
	var blunder_text = " [BLUNDERED!]" if blundered else ""
	result.description = "%s self-orders %s%s" % [
		unit.unit_type, order_type.replace("_", " ").capitalize(), blunder_text
	]

	return result


## Step 3: Execute the declared order.
## params: Dictionary with order-specific parameters:
##   volley_fire:    { "target_id": String }
##   move_and_shoot: { "x": int, "y": int, "target_id": String }
##   march:          { "x": int, "y": int }
##   charge:         { "target_id": String }
## dice_results: Array of D6 rolls for combat resolution
static func execute_order(state: Types.GameState, params: Dictionary, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result
	if state.order_phase != "order_execute":
		result.error = "Not in order execution phase"
		return result

	var unit = _find_unit(state, state.current_order_unit_id)
	if not unit:
		result.error = "Ordered unit not found"
		return result

	match state.current_order_type:
		"volley_fire":
			return _execute_volley_fire(state, unit, params, dice_results)
		"move_and_shoot":
			return _execute_move_and_shoot(state, unit, params, dice_results)
		"march":
			return _execute_march(state, unit, params)
		"charge":
			return _execute_charge(state, unit, params, dice_results)
		_:
			result.error = "Unknown order type: " + state.current_order_type
			return result


# =============================================================================
# ORDER EXECUTION
# =============================================================================

static func _execute_volley_fire(state: Types.GameState, unit: Types.UnitState, params: Dictionary, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	# Fizzle path: no valid target exists in range. Advance without combat.
	if params.get("fizzle", false):
		if _has_valid_volley_target(state, unit):
			result.error = "Cannot fizzle: valid targets exist in range"
			return result
		var fizzled_state = _clone_state(state)
		_advance_after_order(fizzled_state)
		fizzled_state.action_log.append({
			"round": state.current_round,
			"seat": state.active_seat,
			"action": "volley_fire_fizzled",
			"unit_id": unit.id,
			"unit_type": unit.unit_type,
			"blundered": state.current_order_blundered
		})
		result.success = true
		result.new_state = fizzled_state
		result.description = "%s volley fire fizzled (no targets in range)" % unit.unit_type
		return result

	var target_id = params.get("target_id", "")
	var target = _find_unit(state, target_id)
	if not target:
		result.error = "Target not found"
		return result
	if target.is_dead:
		result.error = "Target is dead"
		return result
	if target.owner_seat == unit.owner_seat:
		result.error = "Cannot target your own units"
		return result

	# Range check
	var distance = _grid_distance(unit.x, unit.y, target.x, target.y)
	if distance > unit.base_stats.weapon_range:
		result.error = "Target out of range (max %d)" % unit.base_stats.weapon_range
		return result

	# Volley Fire gives -1 Inaccuracy bonus (unless blundered)
	var inaccuracy_mod = -1 if not state.current_order_blundered else 0

	var new_state = _clone_state(state)
	var new_unit = _find_unit_in(new_state, unit.id)
	var new_target = _find_unit_in(new_state, target_id)

	var combat = _resolve_shooting(new_unit, new_target, dice_results, inaccuracy_mod)
	if combat["error"] != "":
		result.error = combat["error"]
		return result

	_advance_after_order(new_state)

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "volley_fire",
		"unit_id": unit.id,
		"unit_type": unit.unit_type,
		"target_id": target_id,
		"target_type": target.unit_type,
		"blundered": state.current_order_blundered,
		"hits": combat["hits"],
		"saves": combat["saves"],
		"unsaved_wounds": combat["unsaved_wounds"]
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	var blunder_text = " (blundered, no bonus)" if state.current_order_blundered else " (-1 Inaccuracy)"
	result.description = "Volley Fire! %s → %s%s (%d hits, %d saved, %d wounds)%s" % [
		unit.unit_type, target.unit_type, blunder_text,
		combat["hits"], combat["saves"], combat["unsaved_wounds"],
		" [DESTROYED]" if new_target.is_dead else ""
	]

	return result


static func _execute_move_and_shoot(state: Types.GameState, unit: Types.UnitState, params: Dictionary, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	var x = params.get("x", -1)
	var y = params.get("y", -1)
	var target_id = params.get("target_id", "")

	# Movement validation
	var move_error = _validate_move(state, unit, x, y)
	if move_error != "":
		result.error = move_error
		return result

	# Movement range: M normally, blunder_move_bonus (from move_dice[0]) if blundered
	var max_move = unit.base_stats.movement
	if state.current_order_blundered:
		max_move = state.current_order_move_bonus  # D6 result stored during declare
	var distance = _grid_distance(unit.x, unit.y, x, y)
	if distance > max_move:
		result.error = "Out of movement range (max %d)" % max_move
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit_in(new_state, unit.id)

	# Move the unit
	new_unit.x = x
	new_unit.y = y

	# Shoot target (if provided and able)
	var combat = {"hits": 0, "saves": 0, "unsaved_wounds": 0, "error": ""}
	var new_target: Types.UnitState = null
	if target_id != "":
		new_target = _find_unit_in(new_state, target_id)
		if new_target and not new_target.is_dead and new_target.owner_seat != unit.owner_seat:
			# Check range from new position
			var shoot_dist = _grid_distance(x, y, new_target.x, new_target.y)
			if shoot_dist <= new_unit.base_stats.weapon_range and not new_unit.has_powder_smoke:
				combat = _resolve_shooting(new_unit, new_target, dice_results, 0)

	_advance_after_order(new_state)

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "move_and_shoot",
		"unit_id": unit.id,
		"unit_type": unit.unit_type,
		"from_x": unit.x, "from_y": unit.y,
		"to_x": x, "to_y": y,
		"target_id": target_id,
		"blundered": state.current_order_blundered,
		"hits": combat["hits"],
		"unsaved_wounds": combat["unsaved_wounds"]
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	var shoot_text = ""
	if target_id != "" and combat["hits"] > 0:
		shoot_text = " → shot %s (%d hits, %d wounds)" % [
			new_target.unit_type if new_target else "?", combat["hits"], combat["unsaved_wounds"]
		]
	result.description = "Move & Shoot! %s to (%d,%d)%s" % [unit.unit_type, x, y, shoot_text]

	return result


static func _execute_march(state: Types.GameState, unit: Types.UnitState, params: Dictionary) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	var x = params.get("x", -1)
	var y = params.get("y", -1)

	var move_error = _validate_move(state, unit, x, y)
	if move_error != "":
		result.error = move_error
		return result

	# March range: M + move_bonus (2D6 or 1D6 if blundered)
	var max_move = unit.base_stats.movement + state.current_order_move_bonus
	var distance = _grid_distance(unit.x, unit.y, x, y)
	if distance > max_move:
		result.error = "Out of march range (max %d = M%d + %d)" % [max_move, unit.base_stats.movement, state.current_order_move_bonus]
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit_in(new_state, unit.id)
	new_unit.x = x
	new_unit.y = y

	_advance_after_order(new_state)

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "march",
		"unit_id": unit.id,
		"unit_type": unit.unit_type,
		"from_x": unit.x, "from_y": unit.y,
		"to_x": x, "to_y": y,
		"move_bonus": state.current_order_move_bonus,
		"blundered": state.current_order_blundered
	})

	result.success = true
	result.new_state = new_state
	result.description = "March! %s to (%d,%d) (M%d + %d)" % [
		unit.unit_type, x, y, unit.base_stats.movement, state.current_order_move_bonus
	]

	return result


static func _execute_charge(state: Types.GameState, unit: Types.UnitState, params: Dictionary, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	# Fizzle path: no chargeable enemy in range. Advance without combat.
	if params.get("fizzle", false):
		if _has_valid_charge_target(state, unit):
			result.error = "Cannot fizzle: valid charge targets exist in range"
			return result
		var fizzled_state = _clone_state(state)
		_advance_after_order(fizzled_state)
		fizzled_state.action_log.append({
			"round": state.current_round,
			"seat": state.active_seat,
			"action": "charge_fizzled",
			"unit_id": unit.id,
			"unit_type": unit.unit_type,
			"blundered": state.current_order_blundered
		})
		result.success = true
		result.new_state = fizzled_state
		result.description = "%s charge fizzled (no targets in range)" % unit.unit_type
		return result

	var target_id = params.get("target_id", "")
	var target = _find_unit(state, target_id)
	if not target:
		result.error = "Target not found"
		return result
	if target.is_dead:
		result.error = "Target is dead"
		return result
	if target.owner_seat == unit.owner_seat:
		result.error = "Cannot charge your own units"
		return result

	# Charge range: M + move_bonus. Must end adjacent (distance = 1) to target.
	var charge_range = unit.base_stats.movement + state.current_order_move_bonus
	var target_distance = _grid_distance(unit.x, unit.y, target.x, target.y)
	if target_distance > charge_range:
		result.error = "Target out of charge range (distance %.1f, max %d)" % [target_distance, charge_range]
		return result

	# Find an adjacent cell to the target to move to
	var charge_dest = _find_adjacent_cell(state, unit, target)
	if charge_dest.x == -1:
		result.error = "No open cell adjacent to target"
		return result

	# Verify the adjacent cell is within charge range
	var move_distance = _grid_distance(unit.x, unit.y, charge_dest.x, charge_dest.y)
	if move_distance > charge_range:
		result.error = "Cannot reach target (need %.1f, have %d)" % [move_distance, charge_range]
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit_in(new_state, unit.id)
	var new_target = _find_unit_in(new_state, target_id)

	# v17 core p.16: target takes panic test when charged.
	var panic_die: int = params.get("panic_die", 1)
	var fearless_die: int = params.get("fearless_die", 1)
	var retreat_die: int = params.get("retreat_die", 1)
	var panic = _panic_test(new_target, panic_die, fearless_die)

	if not panic["passed"]:
		# Target failed panic test — gains +1 panic token (v17 p.19),
		# then retreats away from nearest enemy. Charger moves to the
		# now-vacated adjacent cell. No melee.
		new_target.panic_tokens = mini(new_target.panic_tokens + 1, 6)
		var retreat = _execute_retreat(new_state, target_id, retreat_die)

		# Charger advances to adjacent cell (target may have vacated it,
		# or stayed put if Stubborn Fanatics).
		new_unit.x = charge_dest.x
		new_unit.y = charge_dest.y

		_advance_after_order(new_state)

		new_state.action_log.append({
			"round": state.current_round,
			"seat": state.active_seat,
			"action": "charge",
			"unit_id": unit.id,
			"unit_type": unit.unit_type,
			"target_id": target_id,
			"target_type": target.unit_type,
			"charge_range": charge_range,
			"blundered": state.current_order_blundered,
			"panic_test": panic,
			"target_fled": true,
			"retreat": retreat,
			"hits": 0, "saves": 0, "unsaved_wounds": 0
		})

		result.success = true
		result.new_state = new_state
		result.dice_rolled = [panic_die, fearless_die]
		var retreat_text = ""
		if retreat["destroyed"]:
			retreat_text = " — fled off board! [DESTROYED]"
		elif retreat["stubborn_held"]:
			retreat_text = " — Stubborn Fanatics held!"
		elif retreat["retreated"]:
			retreat_text = " — retreated to (%d,%d)" % [retreat["to_x"], retreat["to_y"]]
		var fearless_text = " (Fearless failed)" if panic["used_fearless"] else ""
		result.description = "Charge! %s → %s — target panicked%s%s" % [
			unit.unit_type, target.unit_type, fearless_text, retreat_text
		]
		return result

	# Move to adjacent cell
	new_unit.x = charge_dest.x
	new_unit.y = charge_dest.y

	# Resolve melee as bouts (v17 core p.18)
	var combat = _resolve_melee(new_unit, new_target, dice_results)
	if combat["error"] != "":
		result.error = combat["error"]
		return result

	# Post-melee: both participants gain +1 panic token (v17 p.18 + p.19).
	if not new_unit.is_dead:
		new_unit.panic_tokens = mini(new_unit.panic_tokens + 1, 6)
	if not new_target.is_dead:
		new_target.panic_tokens = mini(new_target.panic_tokens + 1, 6)

	# Loser retreats. Draw (bout cap with no winner) = no retreat.
	var retreat: Dictionary = {}
	var charger_retreated: bool = false
	if not combat["draw"] and combat["loser_id"] != "":
		var loser = _find_unit_in(new_state, combat["loser_id"])
		if loser and not loser.is_dead:
			retreat = _execute_retreat(new_state, combat["loser_id"], retreat_die)
			if combat["loser_id"] == new_unit.id:
				charger_retreated = true

	_advance_after_order(new_state)

	var panic_log = {}
	if not panic["auto_passed"]:
		panic_log = panic

	# Aggregate wounds across bouts for legacy log fields.
	var atk_wounds_total: int = 0
	var def_wounds_total: int = 0
	for b in combat["bouts"]:
		atk_wounds_total += b["atk_wounds"]
		def_wounds_total += b["def_wounds"]

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "charge",
		"unit_id": unit.id,
		"unit_type": unit.unit_type,
		"target_id": target_id,
		"target_type": target.unit_type,
		"charge_range": charge_range,
		"blundered": state.current_order_blundered,
		"panic_test": panic_log,
		"target_fled": false,
		"bouts": combat["bouts"],
		"melee_draw": combat["draw"],
		"melee_winner_id": combat["winner_id"],
		"melee_loser_id": combat["loser_id"],
		"retreat": retreat,
		"charger_retreated": charger_retreated,
		"unsaved_wounds": atk_wounds_total,
		"counter_unsaved_wounds": def_wounds_total,
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = [panic_die, fearless_die] + dice_results
	var panic_text = ""
	if panic["fearless_override"]:
		panic_text = " (target Fearless — held!)"
	elif not panic["auto_passed"]:
		panic_text = " (target passed panic test)"

	var outcome_text: String
	if combat["draw"]:
		outcome_text = "drawn after %d bouts" % combat["bouts"].size()
	elif combat["winner_id"] == new_unit.id:
		outcome_text = "charger won in %d bout(s)" % combat["bouts"].size()
		if new_target.is_dead:
			outcome_text += " [DEFENDER DESTROYED]"
		elif retreat.get("destroyed", false):
			outcome_text += " — defender fled off board [DESTROYED]"
		elif retreat.get("stubborn_held", false):
			outcome_text += " — defender Stubborn, held ground"
	else:
		outcome_text = "charger lost in %d bout(s)" % combat["bouts"].size()
		if new_unit.is_dead:
			outcome_text += " [CHARGER DESTROYED]"
		elif retreat.get("destroyed", false):
			outcome_text += " — charger fled off board [DESTROYED]"

	result.description = "Charge! %s → %s%s — %s (atk %d / def %d wounds)" % [
		unit.unit_type, target.unit_type, panic_text, outcome_text,
		atk_wounds_total, def_wounds_total,
	]

	return result


# =============================================================================
# ORDER FLOW MANAGEMENT
# =============================================================================

## After an order is fully executed, advance the state machine.
## Marks units as ordered, switches players, transitions phases.
static func _advance_after_order(state: Types.GameState) -> void:
	# Re-resolve objective control after any positional or unit-death change.
	_resolve_objective_captures(state)

	# Mark the ordered unit
	var unit = _find_unit_in(state, state.current_order_unit_id)
	if unit:
		unit.has_ordered = true

	# Mark the snob (if one was commanding)
	if state.current_snob_id != "":
		var snob = _find_unit_in(state, state.current_snob_id)
		if snob:
			snob.has_ordered = true

	# Clear current order tracking
	state.current_snob_id = ""
	state.current_order_unit_id = ""
	state.current_order_type = ""
	state.current_order_blundered = false
	state.current_order_move_bonus = 0

	# Determine next phase
	var seat1_has_unordered_snobs = _has_unordered_snobs(state, 1)
	var seat2_has_unordered_snobs = _has_unordered_snobs(state, 2)

	if seat1_has_unordered_snobs or seat2_has_unordered_snobs:
		# More snobs to order — switch to other player if they have snobs
		var other_seat = 3 - state.active_seat
		if _has_unordered_snobs(state, other_seat):
			state.active_seat = other_seat
		# else: current player continues (opponent has no unordered snobs)
		state.order_phase = "snob_select"
	else:
		# All snobs have ordered — check for unordered followers
		var seat1_has_unordered_followers = _has_unordered_followers(state, 1)
		var seat2_has_unordered_followers = _has_unordered_followers(state, 2)

		if seat1_has_unordered_followers or seat2_has_unordered_followers:
			state.order_phase = "follower_self_order"
			# Initiative player's unordered followers go first
			if _has_unordered_followers(state, state.initiative_seat):
				state.active_seat = state.initiative_seat
			else:
				state.active_seat = 3 - state.initiative_seat
		else:
			# All units ordered — end the round
			_end_round(state)


## End the current round: reset flags, advance round counter.
static func _end_round(state: Types.GameState) -> void:
	# Clear all has_ordered flags
	for unit in state.units:
		unit.has_ordered = false

	# Clear powder smoke at start of new round
	for unit in state.units:
		unit.has_powder_smoke = false

	state.current_round += 1

	if state.current_round > state.max_rounds:
		state.phase = "finished"
		state.order_phase = ""
	else:
		state.order_phase = "snob_select"
		state.active_seat = state.initiative_seat

	state.action_log.append({
		"round": state.current_round - 1,
		"action": "round_ended"
	})


# =============================================================================
# PANIC TEST
# =============================================================================

## Check whether a unit is currently Fearless (3+ to ignore forced retreat).
## Sources: "fearless" special rule (Brutes), or "safety_in_numbers" with 8+
## models alive (Fodder).
static func _is_fearless(unit: Types.UnitState) -> bool:
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
static func _panic_test(unit: Types.UnitState, panic_die: int, fearless_die: int) -> Dictionary:
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
	if _is_fearless(unit):
		result["used_fearless"] = true
		if fearless_die >= 3:
			result["fearless_override"] = true
			return result

	result["passed"] = false
	return result


# =============================================================================
# RETREAT
# =============================================================================

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
static func _execute_retreat(state: Types.GameState, unit_id: String, retreat_die: int) -> Dictionary:
	var unit = _find_unit_in(state, unit_id)
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
	var nearest_enemy = _find_nearest_enemy(state, unit)
	if not nearest_enemy:
		# No enemies alive — nowhere to retreat from. Stay put.
		result["no_enemy"] = true
		return result

	var dx: float = float(unit.x - nearest_enemy.x)
	var dy: float = float(unit.y - nearest_enemy.y)
	var dist: float = sqrt(dx * dx + dy * dy)
	if dist < 0.001:
		# On top of enemy (shouldn't happen). Default retreat direction: toward own deployment zone.
		dy = 1.0 if unit.owner_seat == 1 else -1.0
		dx = 0.0
		dist = 1.0

	# Normalize direction
	dx /= dist
	dy /= dist

	# Ideal retreat destination
	var ideal_x: float = float(unit.x) + dx * float(retreat_dist)
	var ideal_y: float = float(unit.y) + dy * float(retreat_dist)
	var target_x: int = clampi(roundi(ideal_x), 0, BOARD_WIDTH - 1)
	var target_y: int = clampi(roundi(ideal_y), 0, BOARD_HEIGHT - 1)

	# Board edge check: if the ideal position is off the board, unit is destroyed.
	if roundi(ideal_x) < 0 or roundi(ideal_x) >= BOARD_WIDTH or roundi(ideal_y) < 0 or roundi(ideal_y) >= BOARD_HEIGHT:
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


## Find the nearest alive enemy unit to the given unit.
static func _find_nearest_enemy(state: Types.GameState, unit: Types.UnitState) -> Types.UnitState:
	var best: Types.UnitState = null
	var best_dist: float = 99999.0
	for u in state.units:
		if u.is_dead or u.owner_seat == unit.owner_seat:
			continue
		if u.x < 0 or u.y < 0:
			continue
		var d := _grid_distance(unit.x, unit.y, u.x, u.y)
		if d < best_dist:
			best_dist = d
			best = u
	return best


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
					var d := _grid_distance(target_x, target_y, cx, cy)
					if d < best_dist:
						best_dist = d
						best = Vector2i(cx, cy)
		if best.x != -1:
			return best

	return Vector2i(-1, -1)


## Is this cell a valid retreat destination?
static func _is_valid_retreat_dest(state: Types.GameState, unit: Types.UnitState, x: int, y: int) -> bool:
	if x < 0 or x >= BOARD_WIDTH or y < 0 or y >= BOARD_HEIGHT:
		return false
	# Can't land on an occupied cell
	for u in state.units:
		if not u.is_dead and u.id != unit.id and u.x == x and u.y == y:
			return false
	# Can't land on an objective (v17 p.22)
	if _is_objective_at(state, x, y):
		return false
	return true


# =============================================================================
# COMBAT RESOLUTION HELPERS
# =============================================================================

## Resolve a shooting engagement. Modifies new_attacker and new_target in place.
## Returns { hits, saves, unsaved_wounds, error }
static func _resolve_shooting(attacker: Types.UnitState, target: Types.UnitState, dice_results: Array, inaccuracy_mod: int) -> Dictionary:
	var num_attacks = attacker.model_count
	var needed_dice = num_attacks * 2
	if dice_results.size() < needed_dice:
		return {"hits": 0, "saves": 0, "unsaved_wounds": 0, "error": "Not enough dice (need %d, got %d)" % [needed_dice, dice_results.size()]}

	var inaccuracy = maxi(attacker.base_stats.inaccuracy + inaccuracy_mod, 2)
	var vulnerability = target.base_stats.vulnerability

	# Equipment modifiers
	if attacker.equipment == "missile":
		vulnerability = maxi(vulnerability - 2, 2)

	var hits = 0
	var saves = 0
	var unsaved_wounds = 0

	for i in range(num_attacks):
		var inac_roll = dice_results[i]
		var vuln_roll = dice_results[num_attacks + i]
		if inac_roll >= inaccuracy:
			hits += 1
			if vuln_roll >= vulnerability:
				saves += 1
			else:
				unsaved_wounds += 1

	# Apply wounds
	_apply_wounds(target, unsaved_wounds)

	# Any hit gives target a panic token
	if hits > 0:
		target.panic_tokens = mini(target.panic_tokens + 1, 6)

	# Black powder gives powder smoke
	if attacker.equipment == "black_powder":
		attacker.has_powder_smoke = true

	return {"hits": hits, "saves": saves, "unsaved_wounds": unsaved_wounds, "error": ""}


## Resolve one side's attacks in a melee bout. Consumes dice from the pool
## starting at `offset`. Returns { hits, saves, unsaved_wounds, dice_used, error }.
## Mutates `defender` via _apply_wounds.
static func _resolve_bout_side(attacker: Types.UnitState, defender: Types.UnitState, dice_results: Array, offset: int) -> Dictionary:
	var attacks_per_model = attacker.base_stats.attacks
	var inaccuracy = attacker.base_stats.inaccuracy
	var vulnerability = defender.base_stats.vulnerability

	# Close combat equipment reduces inaccuracy by 1 (min 2)
	if attacker.equipment == "close_combat":
		inaccuracy = maxi(inaccuracy - 1, 2)

	var num_attacks = attacker.model_count * attacks_per_model
	var needed_dice = num_attacks * 2
	if dice_results.size() - offset < needed_dice:
		return {"hits": 0, "saves": 0, "unsaved_wounds": 0, "dice_used": 0,
				"error": "Not enough dice (need %d at offset %d, have %d)" % [needed_dice, offset, dice_results.size() - offset]}

	var hits = 0
	var saves = 0
	var unsaved_wounds = 0

	for i in range(num_attacks):
		var inac_roll = dice_results[offset + i]
		var vuln_roll = dice_results[offset + num_attacks + i]
		if inac_roll >= inaccuracy:
			hits += 1
			if vuln_roll >= vulnerability:
				saves += 1
			else:
				unsaved_wounds += 1

	_apply_wounds(defender, unsaved_wounds)

	return {"hits": hits, "saves": saves, "unsaved_wounds": unsaved_wounds,
			"dice_used": needed_dice, "error": ""}


## Worst-case dice pool size for a full melee between two units.
## Attacker strikes + defender counter-strikes, each at 2 dice per attack,
## across up to MELEE_MAX_BOUTS. Callers should supply at least this many.
static func _melee_dice_budget(attacker: Types.UnitState, defender: Types.UnitState) -> int:
	var per_bout = (attacker.model_count * attacker.base_stats.attacks * 2) \
		+ (defender.model_count * defender.base_stats.attacks * 2)
	return per_bout * MELEE_MAX_BOUTS


## Resolve a melee engagement as bouts (v17 core p.18). Mutates both units
## in place via wound application. Does NOT apply post-melee panic tokens or
## trigger retreat — caller handles those so it can integrate with state.
##
## Each bout: attacker strikes → defender removes casualties → if defender
## still alive, defender counter-strikes → attacker removes casualties.
## Winner = side that dealt more unsaved wounds that bout. Tie → next bout.
## Hard cap at MELEE_MAX_BOUTS; if still tied at the cap, draw (no retreat).
##
## Returns {
##   bouts: [{atk_hits, atk_saves, atk_wounds, def_hits, def_saves, def_wounds}...],
##   winner_id, loser_id,  # "" on draw or if one side was already dead
##   draw: bool,           # true only when cap hit with no winner
##   dice_used: int,
##   error: String
## }
static func _resolve_melee(attacker: Types.UnitState, target: Types.UnitState, dice_results: Array) -> Dictionary:
	var summary = {
		"bouts": [],
		"winner_id": "",
		"loser_id": "",
		"draw": false,
		"dice_used": 0,
		"error": "",
	}

	if attacker.is_dead or target.is_dead:
		summary["error"] = "Cannot resolve melee: one side already dead"
		return summary

	var offset: int = 0

	for bout_idx in range(MELEE_MAX_BOUTS):
		var bout = {
			"atk_hits": 0, "atk_saves": 0, "atk_wounds": 0,
			"def_hits": 0, "def_saves": 0, "def_wounds": 0,
		}

		# Attacker strikes first
		var atk = _resolve_bout_side(attacker, target, dice_results, offset)
		if atk["error"] != "":
			summary["error"] = atk["error"]
			return summary
		offset += atk["dice_used"]
		bout["atk_hits"] = atk["hits"]
		bout["atk_saves"] = atk["saves"]
		bout["atk_wounds"] = atk["unsaved_wounds"]

		# Target wiped out before counter-attack
		if target.is_dead:
			summary["bouts"].append(bout)
			summary["winner_id"] = attacker.id
			summary["loser_id"] = target.id
			summary["dice_used"] = offset
			return summary

		# Defender counter-strikes
		var def = _resolve_bout_side(target, attacker, dice_results, offset)
		if def["error"] != "":
			summary["error"] = def["error"]
			return summary
		offset += def["dice_used"]
		bout["def_hits"] = def["hits"]
		bout["def_saves"] = def["saves"]
		bout["def_wounds"] = def["unsaved_wounds"]
		summary["bouts"].append(bout)

		# Attacker wiped out — defender wins the bout trivially
		if attacker.is_dead:
			summary["winner_id"] = target.id
			summary["loser_id"] = attacker.id
			summary["dice_used"] = offset
			return summary

		# Both alive — decide the bout
		if bout["atk_wounds"] > bout["def_wounds"]:
			summary["winner_id"] = attacker.id
			summary["loser_id"] = target.id
			summary["dice_used"] = offset
			return summary
		if bout["def_wounds"] > bout["atk_wounds"]:
			summary["winner_id"] = target.id
			summary["loser_id"] = attacker.id
			summary["dice_used"] = offset
			return summary
		# Tie → next bout

	# Cap reached with no decisive bout — draw.
	summary["draw"] = true
	summary["dice_used"] = offset
	return summary


# =============================================================================
# VICTORY CONDITION
# =============================================================================

## Check for victory condition.
static func check_victory(state: Types.GameState) -> Dictionary:
	var units_total_1: int = 0
	var units_total_2: int = 0
	var units_alive_1: int = 0
	var units_alive_2: int = 0

	for unit in state.units:
		if unit.owner_seat == 1:
			units_total_1 += 1
			if not unit.is_dead:
				units_alive_1 += 1
		else:
			units_total_2 += 1
			if not unit.is_dead:
				units_alive_2 += 1

	# Solo mode: one side has no units at all — no victory check
	if units_total_1 == 0 or units_total_2 == 0:
		return {"winner": 0, "reason": ""}

	if units_alive_1 == 0 and units_alive_2 > 0:
		return {"winner": 2, "reason": "Player 1 eliminated"}
	if units_alive_2 == 0 and units_alive_1 > 0:
		return {"winner": 1, "reason": "Player 2 eliminated"}
	if units_alive_1 == 0 and units_alive_2 == 0:
		return {"winner": 0, "reason": "Draw (both eliminated)"}

	# Headless Chicken: all Snobs dead = instant loss
	var snobs_alive_1 = 0
	var snobs_alive_2 = 0
	for unit in state.units:
		if not unit.is_dead and unit.is_snob():
			if unit.owner_seat == 1:
				snobs_alive_1 += 1
			else:
				snobs_alive_2 += 1

	if snobs_alive_1 == 0 and snobs_alive_2 > 0:
		return {"winner": 2, "reason": "Player 1 lost all Snobs (Headless Chicken)"}
	if snobs_alive_2 == 0 and snobs_alive_1 > 0:
		return {"winner": 1, "reason": "Player 2 lost all Snobs (Headless Chicken)"}

	# Round limit reached: v17 objective scoring (core p.22, scenarios p.23+).
	# "The player who controls the most objective markers at the end of the
	# final round is the victor." Ties go straight to draw — no secondary
	# model-count fallback in the rules.
	if state.current_round > state.max_rounds:
		var objectives_1: int = 0
		var objectives_2: int = 0
		for obj in state.objectives:
			if obj.captured_by == 1:
				objectives_1 += 1
			elif obj.captured_by == 2:
				objectives_2 += 1
		if objectives_1 > objectives_2:
			return {"winner": 1, "reason": "Player 1 controls %d objective(s) to %d" % [objectives_1, objectives_2]}
		if objectives_2 > objectives_1:
			return {"winner": 2, "reason": "Player 2 controls %d objective(s) to %d" % [objectives_2, objectives_1]}
		return {"winner": 0, "reason": "Objectives tied %d–%d (Draw)" % [objectives_1, objectives_2]}

	return {"winner": 0, "reason": ""}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Apply wounds to a unit, removing models as they die.
static func _apply_wounds(unit: Types.UnitState, wounds: int) -> void:
	var remaining_wounds = wounds
	while remaining_wounds > 0 and not unit.is_dead:
		unit.current_wounds += 1
		remaining_wounds -= 1
		if unit.current_wounds >= unit.base_stats.wounds:
			unit.model_count -= 1
			unit.current_wounds = 0
			if unit.model_count <= 0:
				unit.is_dead = true
				unit.model_count = 0


## Deep clone a GameState.
static func _clone_state(state: Types.GameState) -> Types.GameState:
	return Types.GameState.from_dict(state.to_dict())


## Find a unit by ID in a GameState (read-only).
static func _find_unit(state: Types.GameState, unit_id: String) -> Types.UnitState:
	for u in state.units:
		if u.id == unit_id:
			return u
	return null


## Find a unit by ID in a mutable state (for modification after clone).
static func _find_unit_in(state: Types.GameState, unit_id: String) -> Types.UnitState:
	for u in state.units:
		if u.id == unit_id:
			return u
	return null


## Check if a seat has any alive, unordered Snobs.
static func _has_unordered_snobs(state: Types.GameState, seat: int) -> bool:
	for unit in state.units:
		if unit.owner_seat == seat and unit.is_snob() and not unit.is_dead and not unit.has_ordered:
			return true
	return false


## Does at least one alive enemy unit sit inside the shooter's weapon range?
static func _has_valid_volley_target(state: Types.GameState, unit: Types.UnitState) -> bool:
	var wr: int = unit.base_stats.weapon_range
	if wr <= 0:
		return false
	for u in state.units:
		if u.is_dead or u.owner_seat == unit.owner_seat:
			continue
		var d := _grid_distance(unit.x, unit.y, u.x, u.y)
		if d <= wr:
			return true
	return false


## Does at least one alive enemy unit sit inside the charger's M + move_bonus range?
static func _has_valid_charge_target(state: Types.GameState, unit: Types.UnitState) -> bool:
	var reach: int = unit.base_stats.movement + state.current_order_move_bonus
	if reach <= 0:
		return false
	for u in state.units:
		if u.is_dead or u.owner_seat == unit.owner_seat:
			continue
		var d := _grid_distance(unit.x, unit.y, u.x, u.y)
		if d <= reach:
			return true
	return false


## Check if a seat has any alive, unordered non-Snob units.
static func _has_unordered_followers(state: Types.GameState, seat: int) -> bool:
	for unit in state.units:
		if unit.owner_seat == seat and not unit.is_snob() and not unit.is_dead and not unit.has_ordered:
			return true
	return false


## Get list of follower IDs in command range of a snob.
static func get_followers_in_command_range(state: Types.GameState, snob_id: String) -> Array[String]:
	var snob = _find_unit(state, snob_id)
	if not snob or not snob.is_snob():
		return []

	var cmd_range = snob.get_command_range()
	var result: Array[String] = []

	for unit in state.units:
		if unit.owner_seat == snob.owner_seat and not unit.is_snob() and not unit.is_dead and not unit.has_ordered:
			var distance = _grid_distance(snob.x, snob.y, unit.x, unit.y)
			if distance <= cmd_range:
				result.append(unit.id)

	return result


## Validate basic movement constraints (bounds, not occupied).
static func _validate_move(state: Types.GameState, unit: Types.UnitState, x: int, y: int) -> String:
	if x < 0 or x >= BOARD_WIDTH or y < 0 or y >= BOARD_HEIGHT:
		return "Coordinates out of bounds"
	for u in state.units:
		if not u.is_dead and u.x == x and u.y == y and u.id != unit.id:
			return "Position occupied"
	# v17 core p.22: "A unit may move across objectives, but may never finish
	# a move on top of one."
	if _is_objective_at(state, x, y):
		return "Cannot end move on an objective marker"
	return ""


## Is there an objective marker at this cell?
static func _is_objective_at(state: Types.GameState, x: int, y: int) -> bool:
	for obj in state.objectives:
		if obj.x == x and obj.y == y:
			return true
	return false


## Recompute capture state for every objective per v17 core p.22.
## Called after any state change that could shift Follower positions
## (placement finalized, moves, charges, unit deaths). Mutates in place.
##
## Rules modeled:
##   - Only Follower units capture (Snobs never do).
##   - "Within 1"" maps to Euclidean distance ≤ 1.0 (orthogonal neighbor).
##     Diagonal neighbors (√2 ≈ 1.41) are outside 1" and do not capture.
##   - Objective cell itself is uncapturable-from; units can't end there.
##   - If only one seat has adjacent Followers → captured by that seat.
##   - If both seats have adjacent Followers → contested (uncaptured).
##   - If neither seat has adjacent Followers → retain previous control.
##
## MVP simplification: the v17 "only one objective captured per move"
## player-choice rule is not enforced here — a move that ends adjacent to
## two uncontrolled objectives will capture both. Tracked for a follow-up
## when objective placement is dense enough to matter in practice.
static func _resolve_objective_captures(state: Types.GameState) -> void:
	for obj in state.objectives:
		var seat1_adjacent := 0
		var seat2_adjacent := 0
		for u in state.units:
			if u.is_dead or u.is_snob():
				continue
			if u.x < 0 or u.y < 0:
				continue
			var d := _grid_distance(u.x, u.y, obj.x, obj.y)
			if d <= 1.0:
				if u.owner_seat == 1:
					seat1_adjacent += 1
				else:
					seat2_adjacent += 1
		if seat1_adjacent > 0 and seat2_adjacent > 0:
			obj.captured_by = 0
		elif seat1_adjacent > 0:
			obj.captured_by = 1
		elif seat2_adjacent > 0:
			obj.captured_by = 2
		# else: retain obj.captured_by (captured objective stays captured
		# until enemy contests or claims it).


## Find the best adjacent cell to a target for a charging unit.
static func _find_adjacent_cell(state: Types.GameState, charger: Types.UnitState, target: Types.UnitState) -> Vector2i:
	var best = Vector2i(-1, -1)
	var best_dist = 9999

	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cx = target.x + offset.x
		var cy = target.y + offset.y
		if cx < 0 or cx >= BOARD_WIDTH or cy < 0 or cy >= BOARD_HEIGHT:
			continue
		# Check not occupied (except by charger itself)
		var occupied = false
		for u in state.units:
			if not u.is_dead and u.x == cx and u.y == cy and u.id != charger.id:
				occupied = true
				break
		if occupied:
			continue
		# Objective cells are invalid end-of-move destinations (v17 p.22).
		if _is_objective_at(state, cx, cy):
			continue
		var dist = _grid_distance(charger.x, charger.y, cx, cy)
		if dist < best_dist:
			best_dist = dist
			best = Vector2i(cx, cy)

	return best
