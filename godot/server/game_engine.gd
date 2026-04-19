class_name GameEngine
extends RefCounted
## Authoritative game engine for Turnip28 battle simulation.
##
## All functions are pure: (state, action, dice) -> new state.
## Dice rolls are injected via parameters for deterministic testing.
## No mutation of input state — always return new state via cloning.
##
## Combat follows Turnip28 v17 rules:
##   Shooting: 1 attack per model → Inaccuracy roll (I+) → Vulnerability save (V+)
##   Melee:    A attacks per model → Inaccuracy roll (I+) → Vulnerability save (V+)

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
# ORDERS PHASE
# =============================================================================

## Move a unit to a new position.
static func move_unit(state: Types.GameState, unit_id: String, x: int, y: int) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result

	var unit: Types.UnitState = null
	for u in state.units:
		if u.id == unit_id:
			unit = u
			break

	if not unit:
		result.error = "Unit not found"
		return result

	if unit.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result

	if unit.has_ordered:
		result.error = "Unit already activated this round"
		return result

	if unit.is_dead:
		result.error = "Unit is dead"
		return result

	if x < 0 or x >= BOARD_WIDTH or y < 0 or y >= BOARD_HEIGHT:
		result.error = "Coordinates out of bounds"
		return result

	for u in state.units:
		if not u.is_dead and u.x == x and u.y == y:
			result.error = "Position occupied"
			return result

	# Movement range check (Manhattan distance, 1 cell = 1 inch)
	var distance = abs(x - unit.x) + abs(y - unit.y)
	if distance > unit.base_stats.movement:
		result.error = "Out of movement range (max %d)" % unit.base_stats.movement
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
		"action": "move",
		"unit_id": unit_id,
		"unit_type": unit.unit_type,
		"from_x": unit.x,
		"from_y": unit.y,
		"to_x": x,
		"to_y": y
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s moved to (%d, %d)" % [unit.unit_type, x, y]

	return result


## Resolve a shooting engagement.
## dice_results: Array of D6 rolls — need (model_count) inaccuracy dice + (hits) vulnerability dice
## For simplicity, pass all dice upfront: [inaccuracy_1, ..., inaccuracy_N, vuln_1, ..., vuln_N]
## where N = attacker.model_count. Extra vuln dice are ignored if not needed.
static func resolve_shoot(state: Types.GameState, attacker_id: String, target_id: String, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result

	var attacker: Types.UnitState = null
	var target: Types.UnitState = null

	for u in state.units:
		if u.id == attacker_id:
			attacker = u
		if u.id == target_id:
			target = u

	if not attacker:
		result.error = "Attacker not found"
		return result
	if not target:
		result.error = "Target not found"
		return result
	if attacker.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result
	if attacker.has_ordered:
		result.error = "Unit already activated"
		return result
	if attacker.is_dead or target.is_dead:
		result.error = "Dead unit cannot attack or be attacked"
		return result
	if target.owner_seat == attacker.owner_seat:
		result.error = "Cannot attack your own units"
		return result

	# Must have ranged weapon (weapon_range > 0) and no powder smoke
	if attacker.base_stats.weapon_range <= 0:
		result.error = "Unit has no ranged weapon"
		return result
	if attacker.has_powder_smoke:
		result.error = "Unit has powder smoke — cannot shoot"
		return result

	# Range check
	var distance = abs(target.x - attacker.x) + abs(target.y - attacker.y)
	if distance > attacker.base_stats.weapon_range:
		result.error = "Target out of range (max %d)" % attacker.base_stats.weapon_range
		return result

	# Turnip28 shooting: 1 attack per model in the unit
	var num_attacks = attacker.model_count
	var needed_dice = num_attacks * 2  # inaccuracy + vulnerability for each
	if dice_results.size() < needed_dice:
		result.error = "Not enough dice (need %d, got %d)" % [needed_dice, dice_results.size()]
		return result

	var inaccuracy = attacker.base_stats.inaccuracy
	var vulnerability = target.base_stats.vulnerability

	# Equipment modifiers
	if attacker.equipment == "missile":
		# Missile weapons reduce target's V by 2 (making it easier to wound)
		vulnerability = maxi(vulnerability - 2, 2)

	var hits: int = 0
	var saves: int = 0
	var unsaved_wounds: int = 0
	var hit_details: Array = []

	for i in range(num_attacks):
		var inac_roll = dice_results[i]
		var vuln_roll = dice_results[num_attacks + i]
		var hit = inac_roll >= inaccuracy
		var saved = false

		if hit:
			hits += 1
			saved = vuln_roll >= vulnerability
			if saved:
				saves += 1
			else:
				unsaved_wounds += 1

		hit_details.append({
			"inaccuracy_roll": inac_roll,
			"hit": hit,
			"vulnerability_roll": vuln_roll if hit else 0,
			"saved": saved
		})

	# Apply wounds to target (remove models)
	var new_state = _clone_state(state)
	var new_attacker: Types.UnitState = null
	var new_target: Types.UnitState = null

	for u in new_state.units:
		if u.id == attacker_id:
			new_attacker = u
		if u.id == target_id:
			new_target = u

	new_attacker.has_ordered = true

	# Black powder generates powder smoke
	if attacker.equipment == "black_powder":
		new_attacker.has_powder_smoke = true

	# Apply wounds — each unsaved wound kills one 1W model or chips multi-wound models
	_apply_wounds(new_target, unsaved_wounds)

	# Any hit (even saved) gives target a panic token
	if hits > 0 and new_target.panic_tokens < 6:
		new_target.panic_tokens = mini(new_target.panic_tokens + 1, 6)

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "shoot",
		"attacker_id": attacker_id,
		"attacker_type": attacker.unit_type,
		"target_id": target_id,
		"target_type": target.unit_type,
		"num_attacks": num_attacks,
		"inaccuracy_needed": inaccuracy,
		"vulnerability_needed": vulnerability,
		"hits": hits,
		"saves": saves,
		"unsaved_wounds": unsaved_wounds,
		"models_remaining": new_target.model_count,
		"target_killed": new_target.is_dead,
		"details": hit_details
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	result.description = "%s shot %s (%d attacks, %d hits, %d saved, %d wounds)%s" % [
		attacker.unit_type, target.unit_type,
		num_attacks, hits, saves, unsaved_wounds,
		" [DESTROYED]" if new_target.is_dead else " [%d models left]" % new_target.model_count
	]

	return result


## Resolve a melee charge.
## dice_results: Array of D6 rolls — need (total_attacks) inaccuracy dice + (total_attacks) vulnerability dice
## total_attacks = model_count * attacks_per_model
static func resolve_charge(state: Types.GameState, attacker_id: String, target_id: String, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result

	var attacker: Types.UnitState = null
	var target: Types.UnitState = null

	for u in state.units:
		if u.id == attacker_id:
			attacker = u
		if u.id == target_id:
			target = u

	if not attacker or not target:
		result.error = "Unit not found"
		return result
	if attacker.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result
	if attacker.has_ordered:
		result.error = "Unit already activated"
		return result
	if attacker.is_dead or target.is_dead:
		result.error = "Dead unit cannot attack"
		return result
	if target.owner_seat == attacker.owner_seat:
		result.error = "Cannot attack your own units"
		return result

	# Must be adjacent (distance = 1)
	var distance = abs(target.x - attacker.x) + abs(target.y - attacker.y)
	if distance != 1:
		result.error = "Target not adjacent (must be 1 cell away)"
		return result

	# Turnip28 melee: A attacks per model
	var attacks_per_model = attacker.base_stats.attacks
	var inaccuracy = attacker.base_stats.inaccuracy
	var vulnerability = target.base_stats.vulnerability

	# Close combat weapons reduce inaccuracy by 1
	if attacker.equipment == "close_combat":
		inaccuracy = maxi(inaccuracy - 1, 2)

	var num_attacks = attacker.model_count * attacks_per_model
	var needed_dice = num_attacks * 2
	if dice_results.size() < needed_dice:
		result.error = "Not enough dice (need %d, got %d)" % [needed_dice, dice_results.size()]
		return result

	var hits: int = 0
	var saves: int = 0
	var unsaved_wounds: int = 0

	for i in range(num_attacks):
		var inac_roll = dice_results[i]
		var vuln_roll = dice_results[num_attacks + i]
		var hit = inac_roll >= inaccuracy

		if hit:
			hits += 1
			var saved = vuln_roll >= vulnerability
			if saved:
				saves += 1
			else:
				unsaved_wounds += 1

	var new_state = _clone_state(state)
	var new_attacker: Types.UnitState = null
	var new_target: Types.UnitState = null

	for u in new_state.units:
		if u.id == attacker_id:
			new_attacker = u
		if u.id == target_id:
			new_target = u

	new_attacker.has_ordered = true
	_apply_wounds(new_target, unsaved_wounds)

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "charge",
		"attacker_id": attacker_id,
		"attacker_type": attacker.unit_type,
		"target_id": target_id,
		"target_type": target.unit_type,
		"num_attacks": num_attacks,
		"inaccuracy_needed": inaccuracy,
		"vulnerability_needed": vulnerability,
		"hits": hits,
		"saves": saves,
		"unsaved_wounds": unsaved_wounds,
		"models_remaining": new_target.model_count,
		"target_killed": new_target.is_dead
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	result.description = "%s charged %s (%d attacks, %d hits, %d saved, %d wounds)%s" % [
		attacker.unit_type, target.unit_type,
		num_attacks, hits, saves, unsaved_wounds,
		" [DESTROYED]" if new_target.is_dead else " [%d models left]" % new_target.model_count
	]

	return result


## End activation for a unit (used when unit moves but doesn't attack).
static func end_activation(state: Types.GameState, unit_id: String) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result

	var unit: Types.UnitState = null
	for u in state.units:
		if u.id == unit_id:
			unit = u
			break

	if not unit:
		result.error = "Unit not found"
		return result
	if unit.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result
	if unit.has_ordered:
		result.error = "Unit already activated"
		return result

	var new_state = _clone_state(state)

	for u in new_state.units:
		if u.id == unit_id:
			u.has_ordered = true
			break

	new_state.action_log.append({
		"round": state.current_round,
		"seat": state.active_seat,
		"action": "end_activation",
		"unit_id": unit_id,
		"unit_type": unit.unit_type
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s ended activation" % unit.unit_type

	return result


## End the current turn. Switches to other player or advances round.
static func end_turn(state: Types.GameState) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "orders":
		result.error = "Not in orders phase"
		return result

	for unit in state.units:
		if unit.owner_seat == state.active_seat and not unit.is_dead and not unit.has_ordered:
			result.error = "You have unactivated units"
			return result

	var new_state = _clone_state(state)

	var other_seat = 3 - state.active_seat
	new_state.active_seat = other_seat

	# Reset activation and powder smoke for the new active player
	for unit in new_state.units:
		if unit.owner_seat == other_seat:
			unit.has_ordered = false

	# If both players have gone, advance to next round
	if other_seat == new_state.initiative_seat:
		new_state.current_round += 1
		# Clear powder smoke for all units at start of new round
		for unit in new_state.units:
			unit.has_powder_smoke = false

		# Check if game is over (max rounds reached)
		if new_state.current_round > new_state.max_rounds:
			new_state.phase = "finished"

	new_state.action_log.append({
		"round": state.current_round,
		"action": "end_turn",
		"seat": state.active_seat,
		"next_seat": other_seat
	})

	result.success = true
	result.new_state = new_state
	result.description = "Turn ended. Player %d's turn." % other_seat

	return result


# =============================================================================
# VICTORY CONDITION
# =============================================================================

## Check for victory condition.
## Only triggers when both sides have (or had) units — solo mode skips victory checks.
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

	return {"winner": 0, "reason": ""}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Apply wounds to a unit, removing models as they die.
## Follows Turnip28 wound allocation: finish killing current model before moving to next.
static func _apply_wounds(unit: Types.UnitState, wounds: int) -> void:
	var remaining_wounds = wounds
	while remaining_wounds > 0 and not unit.is_dead:
		unit.current_wounds += 1
		remaining_wounds -= 1
		if unit.current_wounds >= unit.base_stats.wounds:
			# Model dies
			unit.model_count -= 1
			unit.current_wounds = 0
			if unit.model_count <= 0:
				unit.is_dead = true
				unit.model_count = 0


## Deep clone a GameState.
static func _clone_state(state: Types.GameState) -> Types.GameState:
	return Types.GameState.from_dict(state.to_dict())
