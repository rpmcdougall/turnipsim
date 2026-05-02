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

# Pure logic modules — all live under game/, all RefCounted, all preloaded
# (not just class_name) so headless test runs don't depend on the global
# script class cache being up to date.
const Board = preload("res://game/board.gd")
const Targeting = preload("res://game/targeting.gd")
const Combat = preload("res://game/combat.gd")
const Panic = preload("res://game/panic.gd")
const Objectives = preload("res://game/objectives.gd")


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

	if x < 0 or x >= Board.BOARD_WIDTH or y < 0 or y >= Board.BOARD_HEIGHT:
		result.error = "Coordinates out of bounds"
		return result

	var valid_zone: bool = false
	if state.active_seat == 1:
		if y >= Board.DEPLOYMENT_ZONE_1_Y_MIN and y <= Board.DEPLOYMENT_ZONE_1_Y_MAX:
			valid_zone = true
	else:
		if y >= Board.DEPLOYMENT_ZONE_2_Y_MIN and y <= Board.DEPLOYMENT_ZONE_2_Y_MAX:
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
		Objectives.resolve_objective_captures(new_state)
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
		var distance = Board.grid_distance(snob.x, snob.y, unit.x, unit.y)
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
		var new_unit = _find_unit(new_state, unit_id)
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
		var new_unit = _find_unit(new_state, unit_id)
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
		result.new_state = fizzled_state
		result.description = "%s volley fire fizzled (no targets in range)" % unit.unit_type
		return result

	var target_id = params.get("target_id", "")
	var target = _find_unit(state, target_id)
	if not target:
		result.error = "Target not found"
		return result

	# LoS + range + closest-target validation
	var target_error = Targeting.is_valid_shooting_target(state, unit, target)
	if target_error != "":
		result.error = target_error
		return result

	# Volley Fire gives -1 Inaccuracy bonus (unless blundered)
	var inaccuracy_mod = -1 if not state.current_order_blundered else 0
	var retreat_die: int = params.get("retreat_die", 1)

	var new_state = _clone_state(state)
	var new_unit = _find_unit(new_state, unit.id)
	var new_target = _find_unit(new_state, target_id)

	var combat = Combat.resolve_shooting_engagement(new_unit, new_target, dice_results, inaccuracy_mod)
	if combat["error"] != "":
		result.error = combat["error"]
		return result

	# Loser retreats (v17 core p.15). Tie → no retreat.
	var retreat: Dictionary = {}
	if not combat["tie"] and combat["loser_id"] != "":
		var loser = _find_unit(new_state, combat["loser_id"])
		if loser and not loser.is_dead:
			retreat = Panic.execute_retreat(new_state, combat["loser_id"], retreat_die)

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
		"hits": combat["att_hits"],
		"saves": combat["att_saves"],
		"unsaved_wounds": combat["att_wounds"],
		"return_fire": combat["return_fire_fired"],
		"return_hits": combat["def_hits"],
		"return_saves": combat["def_saves"],
		"return_wounds": combat["def_wounds"],
		"engagement_winner_id": combat["winner_id"],
		"engagement_loser_id": combat["loser_id"],
		"engagement_tie": combat["tie"],
		"retreat": retreat,
	})

	result.new_state = new_state
	result.dice_rolled = dice_results
	var blunder_text = " (blundered, no bonus)" if state.current_order_blundered else " (-1 Inaccuracy)"
	var return_text = ""
	if combat["return_fire_fired"]:
		return_text = " | return fire %d hits, %d wounds" % [combat["def_hits"], combat["def_wounds"]]
	var outcome = ""
	if combat["tie"]:
		outcome = " — tied"
	elif combat["winner_id"] == new_unit.id:
		outcome = " — shooter wins"
		if new_target.is_dead:
			outcome += " [TARGET DESTROYED]"
		elif retreat.get("destroyed", false):
			outcome += " — target fled off board [DESTROYED]"
	else:
		outcome = " — target wins"
		if new_unit.is_dead:
			outcome += " [SHOOTER DESTROYED]"
		elif retreat.get("destroyed", false):
			outcome += " — shooter fled off board [DESTROYED]"
	result.description = "Volley Fire! %s → %s%s (%d hits, %d wounds)%s%s" % [
		unit.unit_type, target.unit_type, blunder_text,
		combat["att_hits"], combat["att_wounds"],
		return_text, outcome,
	]

	return result


static func _execute_move_and_shoot(state: Types.GameState, unit: Types.UnitState, params: Dictionary, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	var x = params.get("x", -1)
	var y = params.get("y", -1)
	var target_id = params.get("target_id", "")

	# Movement validation
	var move_error = Board.validate_move(state, unit, x, y)
	if move_error != "":
		result.error = move_error
		return result

	# Movement range: M normally, blunder_move_bonus (from move_dice[0]) if blundered
	var max_move = unit.base_stats.movement
	if state.current_order_blundered:
		max_move = state.current_order_move_bonus  # D6 result stored during declare
	var distance = Board.grid_distance(unit.x, unit.y, x, y)
	if distance > max_move:
		result.error = "Out of movement range (max %d)" % max_move
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit(new_state, unit.id)

	# Move the unit
	new_unit.x = x
	new_unit.y = y

	# Shoot target (if provided and able). Return-fire eligibility uses the
	# shooter's post-move position.
	var retreat_die: int = params.get("retreat_die", 1)
	var combat: Dictionary = {
		"att_hits": 0, "att_saves": 0, "att_wounds": 0,
		"def_hits": 0, "def_saves": 0, "def_wounds": 0,
		"return_fire_fired": false,
		"winner_id": "", "loser_id": "",
		"tie": false,
		"error": "",
	}
	var retreat: Dictionary = {}
	var fired: bool = false
	var new_target: Types.UnitState = null
	if target_id != "":
		new_target = _find_unit(new_state, target_id)
		if new_target and not new_target.is_dead and new_target.owner_seat != unit.owner_seat:
			# Validate from post-move position: range + LoS + closest-target
			var shoot_error = Targeting.is_valid_shooting_target_from(new_state, new_unit, new_target, x, y)
			if shoot_error == "" and not new_unit.has_powder_smoke:
				combat = Combat.resolve_shooting_engagement(new_unit, new_target, dice_results, 0)
				if combat["error"] != "":
					result.error = combat["error"]
					return result
				fired = true
				if not combat["tie"] and combat["loser_id"] != "":
					var loser = _find_unit(new_state, combat["loser_id"])
					if loser and not loser.is_dead:
						retreat = Panic.execute_retreat(new_state, combat["loser_id"], retreat_die)

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
		"fired": fired,
		"hits": combat["att_hits"],
		"unsaved_wounds": combat["att_wounds"],
		"return_fire": combat["return_fire_fired"],
		"return_hits": combat["def_hits"],
		"return_wounds": combat["def_wounds"],
		"engagement_winner_id": combat["winner_id"],
		"engagement_loser_id": combat["loser_id"],
		"engagement_tie": combat["tie"],
		"retreat": retreat,
	})

	result.new_state = new_state
	result.dice_rolled = dice_results
	var shoot_text = ""
	if fired:
		shoot_text = " → shot %s (%d hits, %d wounds)" % [
			new_target.unit_type if new_target else "?",
			combat["att_hits"], combat["att_wounds"]
		]
		if combat["return_fire_fired"]:
			shoot_text += ", return fire %d wounds" % combat["def_wounds"]
	result.description = "Move & Shoot! %s to (%d,%d)%s" % [unit.unit_type, x, y, shoot_text]

	return result


static func _execute_march(state: Types.GameState, unit: Types.UnitState, params: Dictionary) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	var x = params.get("x", -1)
	var y = params.get("y", -1)

	var move_error = Board.validate_move(state, unit, x, y)
	if move_error != "":
		result.error = move_error
		return result

	# March range: M + move_bonus (2D6 or 1D6 if blundered)
	var max_move = unit.base_stats.movement + state.current_order_move_bonus
	var distance = Board.grid_distance(unit.x, unit.y, x, y)
	if distance > max_move:
		result.error = "Out of march range (max %d = M%d + %d)" % [max_move, unit.base_stats.movement, state.current_order_move_bonus]
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit(new_state, unit.id)
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

	# LoS check (v17 p.16: must have LoS to charge target)
	if not Targeting.has_line_of_sight(state, unit.x, unit.y, target.x, target.y):
		result.error = "No line of sight to charge target"
		return result

	# Charge range: M + move_bonus. Must end adjacent (distance = 1) to target.
	var charge_range = unit.base_stats.movement + state.current_order_move_bonus
	var target_distance = Board.grid_distance(unit.x, unit.y, target.x, target.y)

	# v17 p.17 "Failed Charges": if no model can make base contact, the unit
	# must still move its full charge distance toward target via the shortest
	# legal route. Three ways a charge can fail:
	#   1. target_distance > charge_range — target sits outside M+2D6 reach
	#   2. find_adjacent_cell returns (-1,-1) — every 8-ring cell illegal
	#      (occupied, on objective, or within 1" of a non-target unit)
	#   3. closest legal 8-ring cell exists but is itself out of charge_range
	# All three resolve the same way: move to find_failed_charge_destination,
	# skip panic test / S&S / melee, log charge_failed.
	var failure_reason: String = ""
	if target_distance > charge_range:
		failure_reason = "out_of_range"

	var charge_dest = Targeting.find_adjacent_cell(state, unit, target)
	if failure_reason == "" and charge_dest.x == -1:
		failure_reason = "no_legal_adjacent_cell"

	var move_distance: float = 0.0
	if failure_reason == "":
		move_distance = Board.grid_distance(unit.x, unit.y, charge_dest.x, charge_dest.y)
		if move_distance > charge_range:
			failure_reason = "adjacent_cell_unreachable"

	if failure_reason != "":
		var failed_dest = Targeting.find_failed_charge_destination(state, unit, target, charge_range)
		var failed_state = _clone_state(state)
		var failed_unit = _find_unit(failed_state, unit.id)
		var from_x: int = unit.x
		var from_y: int = unit.y
		failed_unit.x = failed_dest.x
		failed_unit.y = failed_dest.y
		_advance_after_order(failed_state)
		failed_state.action_log.append({
			"round": state.current_round,
			"seat": state.active_seat,
			"action": "charge_failed",
			"unit_id": unit.id,
			"unit_type": unit.unit_type,
			"target_id": target_id,
			"target_type": target.unit_type,
			"charge_range": charge_range,
			"failure_reason": failure_reason,
			"from_x": from_x, "from_y": from_y,
			"to_x": failed_dest.x, "to_y": failed_dest.y,
			"blundered": state.current_order_blundered,
		})
		result.new_state = failed_state
		result.description = "Charge! %s → %s — failed (%s), advanced to (%d,%d)" % [
			unit.unit_type, target.unit_type, failure_reason, failed_dest.x, failed_dest.y
		]
		return result

	var new_state = _clone_state(state)
	var new_unit = _find_unit(new_state, unit.id)
	var new_target = _find_unit(new_state, target_id)

	# v17 core p.16: target takes panic test when charged.
	var panic_die: int = params.get("panic_die", 1)
	var fearless_die: int = params.get("fearless_die", 1)
	var retreat_die: int = params.get("retreat_die", 1)
	var panic = Panic.panic_test(new_target, panic_die, fearless_die)

	if not panic["passed"]:
		# Target failed panic test — gains +1 panic token (v17 p.19),
		# then retreats away from nearest enemy. Charger moves to the
		# now-vacated adjacent cell. No melee.
		new_target.panic_tokens = mini(new_target.panic_tokens + 1, 6)
		var retreat = Panic.execute_retreat(new_state, target_id, retreat_die)

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

	# v17 core p.16 step 3: target Stands and Shoots if able. Only fires
	# after the panic test passed (failed panic = retreat path above, no
	# S&S). The charger CANNOT return fire — this is a one-sided shooting
	# attack, not a shooting engagement. Range/LoS not required.
	var stand_and_shoot: Dictionary = {}
	var ss_dice_used: int = 0
	if Combat.can_stand_and_shoot(new_target):
		stand_and_shoot = Combat.resolve_stand_and_shoot(new_target, new_unit, dice_results, 0)
		if stand_and_shoot["error"] != "":
			result.error = stand_and_shoot["error"]
			return result
		ss_dice_used = stand_and_shoot["dice_used"]

		if new_unit.is_dead:
			# Charger wiped out by Stand and Shoot — no melee, no movement.
			# Charger sits dead at its starting square; defender holds.
			_advance_after_order(new_state)

			var ss_panic_log = panic if not panic["auto_passed"] else {}
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
				"panic_test": ss_panic_log,
				"target_fled": false,
				"stand_and_shoot": stand_and_shoot,
				"charger_destroyed_by_ss": true,
				"unsaved_wounds": 0,
				"counter_unsaved_wounds": 0,
			})

			result.new_state = new_state
			result.dice_rolled = [panic_die, fearless_die] + dice_results.slice(0, ss_dice_used)
			result.description = "Charge! %s → %s — Stand and Shoot wiped out the charger [CHARGER DESTROYED]" % [
				unit.unit_type, target.unit_type
			]
			return result

	# Move to adjacent cell
	new_unit.x = charge_dest.x
	new_unit.y = charge_dest.y

	# Resolve melee as bouts (v17 core p.18). Melee dice come AFTER any
	# Stand and Shoot dice consumed above.
	var combat = Combat.resolve_melee(new_unit, new_target, dice_results.slice(ss_dice_used))
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
		var loser = _find_unit(new_state, combat["loser_id"])
		if loser and not loser.is_dead:
			retreat = Panic.execute_retreat(new_state, combat["loser_id"], retreat_die)
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
		"stand_and_shoot": stand_and_shoot,
		"charger_destroyed_by_ss": false,
		"bouts": combat["bouts"],
		"melee_draw": combat["draw"],
		"melee_winner_id": combat["winner_id"],
		"melee_loser_id": combat["loser_id"],
		"retreat": retreat,
		"charger_retreated": charger_retreated,
		"unsaved_wounds": atk_wounds_total,
		"counter_unsaved_wounds": def_wounds_total,
	})

	result.new_state = new_state
	result.dice_rolled = [panic_die, fearless_die] + dice_results
	var panic_text = ""
	if panic["fearless_override"]:
		panic_text = " (target Fearless — held!)"
	elif not panic["auto_passed"]:
		panic_text = " (target passed panic test)"

	var ss_text = ""
	if not stand_and_shoot.is_empty() and stand_and_shoot.get("wounds", 0) > 0:
		ss_text = " — S&S %d wounds" % stand_and_shoot["wounds"]

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

	result.description = "Charge! %s → %s%s%s — %s (atk %d / def %d wounds)" % [
		unit.unit_type, target.unit_type, panic_text, ss_text, outcome_text,
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
	Objectives.resolve_objective_captures(state)

	# Mark the ordered unit
	var unit = _find_unit(state, state.current_order_unit_id)
	if unit:
		unit.has_ordered = true

	# Mark the snob (if one was commanding)
	if state.current_snob_id != "":
		var snob = _find_unit(state, state.current_snob_id)
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
# HELPER FUNCTIONS
# =============================================================================

## Deep clone a GameState.
static func _clone_state(state: Types.GameState) -> Types.GameState:
	return Types.GameState.from_dict(state.to_dict())


## Find a unit by ID in a GameState. Caller decides whether the returned
## reference is treated as read-only or as the mutable handle into a cloned state.
static func _find_unit(state: Types.GameState, unit_id: String) -> Types.UnitState:
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
	return not Targeting.find_shooting_targets(state, unit).is_empty()


## Does at least one alive enemy unit sit inside the charger's M + move_bonus range with LoS?
static func _has_valid_charge_target(state: Types.GameState, unit: Types.UnitState) -> bool:
	var reach: int = unit.base_stats.movement + state.current_order_move_bonus
	if reach <= 0:
		return false
	for u in state.units:
		if u.is_dead or u.owner_seat == unit.owner_seat:
			continue
		var d := Board.grid_distance(unit.x, unit.y, u.x, u.y)
		if d <= reach and Targeting.has_line_of_sight(state, unit.x, unit.y, u.x, u.y):
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
			var distance = Board.grid_distance(snob.x, snob.y, unit.x, unit.y)
			if distance <= cmd_range:
				result.append(unit.id)

	return result


