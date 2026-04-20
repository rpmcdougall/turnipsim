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

# Deployment zones (4 rows each)
const DEPLOYMENT_ZONE_1_Y_MIN: int = 28  # Bottom (seat 1)
const DEPLOYMENT_ZONE_1_Y_MAX: int = 31
const DEPLOYMENT_ZONE_2_Y_MIN: int = 0   # Top (seat 2)
const DEPLOYMENT_ZONE_2_Y_MAX: int = 3


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
		var distance = abs(unit.x - snob.x) + abs(unit.y - snob.y)
		if distance > snob.get_command_range():
			result.error = "Unit out of command range (%d > %d)" % [distance, snob.get_command_range()]
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
	if order_type in ["march", "charge"] and "immobile" in unit.special_rules:
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
	if order_type in ["march", "charge"] and "immobile" in unit.special_rules:
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
	var distance = abs(target.x - unit.x) + abs(target.y - unit.y)
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
	var distance = abs(x - unit.x) + abs(y - unit.y)
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
			var shoot_dist = abs(new_target.x - x) + abs(new_target.y - y)
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
	var distance = abs(x - unit.x) + abs(y - unit.y)
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
	var target_distance = abs(target.x - unit.x) + abs(target.y - unit.y)
	if target_distance > charge_range:
		result.error = "Target out of charge range (distance %d, max %d)" % [target_distance, charge_range]
		return result

	# Find an adjacent cell to the target to move to
	var charge_dest = _find_adjacent_cell(state, unit, target)
	if charge_dest.x == -1:
		result.error = "No open cell adjacent to target"
		return result

	# Verify the adjacent cell is within charge range
	var move_distance = abs(charge_dest.x - unit.x) + abs(charge_dest.y - unit.y)
	if move_distance > charge_range:
		result.error = "Cannot reach target (need %d, have %d)" % [move_distance, charge_range]
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit_in(new_state, unit.id)
	var new_target = _find_unit_in(new_state, target_id)

	# Move to adjacent cell
	new_unit.x = charge_dest.x
	new_unit.y = charge_dest.y

	# Resolve melee
	var combat = _resolve_melee(new_unit, new_target, dice_results)
	if combat["error"] != "":
		result.error = combat["error"]
		return result

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
		"hits": combat["hits"],
		"saves": combat["saves"],
		"unsaved_wounds": combat["unsaved_wounds"]
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	result.description = "Charge! %s → %s (%d hits, %d saved, %d wounds)%s" % [
		unit.unit_type, target.unit_type,
		combat["hits"], combat["saves"], combat["unsaved_wounds"],
		" [DESTROYED]" if new_target.is_dead else ""
	]

	return result


# =============================================================================
# ORDER FLOW MANAGEMENT
# =============================================================================

## After an order is fully executed, advance the state machine.
## Marks units as ordered, switches players, transitions phases.
static func _advance_after_order(state: Types.GameState) -> void:
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


## Resolve a melee engagement. Modifies new_attacker and new_target in place.
static func _resolve_melee(attacker: Types.UnitState, target: Types.UnitState, dice_results: Array) -> Dictionary:
	var attacks_per_model = attacker.base_stats.attacks
	var inaccuracy = attacker.base_stats.inaccuracy
	var vulnerability = target.base_stats.vulnerability

	# Close combat equipment reduces inaccuracy by 1
	if attacker.equipment == "close_combat":
		inaccuracy = maxi(inaccuracy - 1, 2)

	var num_attacks = attacker.model_count * attacks_per_model
	var needed_dice = num_attacks * 2
	if dice_results.size() < needed_dice:
		return {"hits": 0, "saves": 0, "unsaved_wounds": 0, "error": "Not enough dice (need %d, got %d)" % [needed_dice, dice_results.size()]}

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

	_apply_wounds(target, unsaved_wounds)

	return {"hits": hits, "saves": saves, "unsaved_wounds": unsaved_wounds, "error": ""}


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

	# Time limit reached: placeholder tiebreak by surviving units, then by
	# model count. v17's real rule is objective-based scoring (see #36) —
	# replace this branch once objectives / scenarios are implemented.
	# TODO(objectives): see https://github.com/rpmcdougall/turnipsim/issues/36
	if state.current_round > state.max_rounds:
		if units_alive_1 > units_alive_2:
			return {"winner": 1, "reason": "Time expired — Player 1 holds the field"}
		if units_alive_2 > units_alive_1:
			return {"winner": 2, "reason": "Time expired — Player 2 holds the field"}
		var models_alive_1: int = 0
		var models_alive_2: int = 0
		for unit in state.units:
			if unit.is_dead:
				continue
			if unit.owner_seat == 1:
				models_alive_1 += unit.model_count
			else:
				models_alive_2 += unit.model_count
		if models_alive_1 > models_alive_2:
			return {"winner": 1, "reason": "Time expired — Player 1 has more models standing"}
		if models_alive_2 > models_alive_1:
			return {"winner": 2, "reason": "Time expired — Player 2 has more models standing"}
		return {"winner": 0, "reason": "Time expired — the field is contested (Draw)"}

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
		var d: int = abs(u.x - unit.x) + abs(u.y - unit.y)
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
		var d: int = abs(u.x - unit.x) + abs(u.y - unit.y)
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
			var distance = abs(unit.x - snob.x) + abs(unit.y - snob.y)
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
	return ""


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
		var dist = abs(cx - charger.x) + abs(cy - charger.y)
		if dist < best_dist:
			best_dist = dist
			best = Vector2i(cx, cy)

	return best
