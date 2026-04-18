class_name GameEngine
extends RefCounted
## Authoritative game engine for Turnip28 battle simulation.
##
## All functions are pure: (state, action, dice) -> new state.
## Dice rolls are injected via parameters for deterministic testing.
## No mutation of input state — always return new state via cloning.

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

	# Validation: phase must be placement
	if state.phase != "placement":
		result.error = "Not in placement phase"
		return result

	# Find the unit
	var unit: Types.UnitState = null
	for u in state.units:
		if u.id == unit_id:
			unit = u
			break

	if not unit:
		result.error = "Unit not found: " + unit_id
		return result

	# Validation: unit must belong to active player
	if unit.owner_seat != state.active_seat:
		result.error = "Not your unit"
		return result

	# Validation: unit not already placed
	if unit.x != -1 or unit.y != -1:
		result.error = "Unit already placed"
		return result

	# Validation: coordinates in bounds
	if x < 0 or x >= BOARD_WIDTH or y < 0 or y >= BOARD_HEIGHT:
		result.error = "Coordinates out of bounds"
		return result

	# Validation: coordinates in deployment zone
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

	# Validation: no other unit at this position
	for u in state.units:
		if u.x == x and u.y == y:
			result.error = "Position occupied"
			return result

	# All validations passed — create new state
	var new_state = _clone_state(state)

	# Find and update the unit in the new state
	for u in new_state.units:
		if u.id == unit_id:
			u.x = x
			u.y = y
			break

	# Add to action log
	new_state.action_log.append({
		"turn": state.current_turn,
		"seat": state.active_seat,
		"action": "place",
		"unit_id": unit_id,
		"unit_name": unit.name,
		"x": x,
		"y": y
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s placed at (%d, %d)" % [unit.name, x, y]

	return result


## Confirm placement for the active player.
## Switches to other player or starts combat phase if both done.
static func confirm_placement(state: Types.GameState) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "placement":
		result.error = "Not in placement phase"
		return result

	# Check that all units for active seat are placed
	for unit in state.units:
		if unit.owner_seat == state.active_seat:
			if unit.x == -1 or unit.y == -1:
				result.error = "Not all units placed"
				return result

	var new_state = _clone_state(state)

	# Check if other player has placed all units
	var other_seat = 3 - state.active_seat  # Flip 1->2, 2->1
	var other_player_done: bool = true

	for unit in state.units:
		if unit.owner_seat == other_seat:
			if unit.x == -1 or unit.y == -1:
				other_player_done = false
				break

	if other_player_done:
		# Both players placed — start combat
		new_state.phase = "combat"
		new_state.active_seat = 1  # Seat 1 goes first
		new_state.action_log.append({
			"turn": state.current_turn,
			"action": "combat_phase_started"
		})
		result.description = "Combat phase started!"
	else:
		# Switch to other player
		new_state.active_seat = other_seat
		new_state.action_log.append({
			"turn": state.current_turn,
			"action": "placement_confirmed",
			"seat": state.active_seat
		})
		result.description = "Player %d placement confirmed. Player %d's turn." % [state.active_seat, other_seat]

	result.success = true
	result.new_state = new_state

	return result


# =============================================================================
# COMBAT PHASE
# =============================================================================

## Move a unit to a new position.
## NOTE: Moving does NOT activate the unit — only attacks or end_activation do.
static func move_unit(state: Types.GameState, unit_id: String, x: int, y: int) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "combat":
		result.error = "Not in combat phase"
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

	if unit.has_activated:
		result.error = "Unit already activated this turn"
		return result

	if unit.is_dead:
		result.error = "Unit is dead"
		return result

	# Validation: coordinates in bounds
	if x < 0 or x >= BOARD_WIDTH or y < 0 or y >= BOARD_HEIGHT:
		result.error = "Coordinates out of bounds"
		return result

	# Validation: not occupied
	for u in state.units:
		if not u.is_dead and u.x == x and u.y == y:
			result.error = "Position occupied"
			return result

	# Validation: within movement range (Manhattan distance)
	var effective_stats = unit.get_effective_stats()
	var distance = abs(x - unit.x) + abs(y - unit.y)

	if distance > effective_stats.movement:
		result.error = "Out of movement range (max %d)" % effective_stats.movement
		return result

	# Valid move
	var new_state = _clone_state(state)

	for u in new_state.units:
		if u.id == unit_id:
			u.x = x
			u.y = y
			# NOTE: Activation is NOT set here
			break

	new_state.action_log.append({
		"turn": state.current_turn,
		"seat": state.active_seat,
		"action": "move",
		"unit_id": unit_id,
		"unit_name": unit.name,
		"from_x": unit.x,
		"from_y": unit.y,
		"to_x": x,
		"to_y": y
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s moved to (%d, %d)" % [unit.name, x, y]

	return result


## Resolve shooting attack.
## dice_results: Array of 3 d6 rolls [hit, wound, save]
static func resolve_shoot(state: Types.GameState, attacker_id: String, target_id: String, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "combat":
		result.error = "Not in combat phase"
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

	if attacker.has_activated:
		result.error = "Unit already activated"
		return result

	if attacker.is_dead or target.is_dead:
		result.error = "Dead unit cannot attack or be attacked"
		return result

	if target.owner_seat == attacker.owner_seat:
		result.error = "Cannot attack your own units"
		return result

	# Validation: weapon must be ranged
	if attacker.weapon.type != "ranged":
		result.error = "Unit has no ranged weapon"
		return result

	# Validation: range check (Manhattan distance)
	var distance = abs(target.x - attacker.x) + abs(target.y - attacker.y)

	if distance > attacker.weapon.range:
		result.error = "Target out of range (max %d)" % attacker.weapon.range
		return result

	# Combat mechanics: roll to hit, wound, save
	var attacker_stats = attacker.get_effective_stats()
	var target_stats = target.get_effective_stats()

	var to_hit_target = 7 - attacker_stats.shooting - attacker.weapon.modifier
	var to_wound_target = 7 - attacker_stats.combat

	# Clamp to 2-6 range (always at least 2+ needed, max 6+)
	to_hit_target = clampi(to_hit_target, 2, 6)
	to_wound_target = clampi(to_wound_target, 2, 6)

	# Need 3 dice: hit, wound, save
	if dice_results.size() < 3:
		result.error = "Not enough dice provided"
		return result

	var hit_roll = dice_results[0]
	var wound_roll = dice_results[1]
	var save_roll = dice_results[2]

	var hit_success = hit_roll >= to_hit_target
	var wound_success = wound_roll >= to_wound_target
	var save_success = save_roll >= target_stats.save

	var damage_dealt: int = 0

	if hit_success and wound_success and not save_success:
		damage_dealt = 1

	# Create new state
	var new_state = _clone_state(state)

	# Find attacker and target in new state
	var new_attacker: Types.UnitState = null
	var new_target: Types.UnitState = null

	for u in new_state.units:
		if u.id == attacker_id:
			new_attacker = u
		if u.id == target_id:
			new_target = u

	# Mark attacker as activated
	new_attacker.has_activated = true

	# Apply damage
	if damage_dealt > 0:
		new_target.current_wounds -= damage_dealt
		if new_target.current_wounds <= 0:
			new_target.is_dead = true

	# Log action
	new_state.action_log.append({
		"turn": state.current_turn,
		"seat": state.active_seat,
		"action": "shoot",
		"attacker_id": attacker_id,
		"attacker_name": attacker.name,
		"target_id": target_id,
		"target_name": target.name,
		"hit_roll": hit_roll,
		"hit_needed": to_hit_target,
		"hit_success": hit_success,
		"wound_roll": wound_roll,
		"wound_needed": to_wound_target,
		"wound_success": wound_success,
		"save_roll": save_roll,
		"save_needed": target_stats.save,
		"save_success": save_success,
		"damage": damage_dealt,
		"target_killed": new_target.is_dead
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	result.description = "%s shot %s (Hit:%d/%d, Wound:%d/%d, Save:%d/%d) - %d damage%s" % [
		attacker.name, target.name,
		hit_roll, to_hit_target,
		wound_roll, to_wound_target,
		save_roll, target_stats.save,
		damage_dealt,
		" [KILLED]" if new_target.is_dead else ""
	]

	return result


## Resolve melee charge attack.
## dice_results: Array of 3 d6 rolls [hit, wound, save]
static func resolve_charge(state: Types.GameState, attacker_id: String, target_id: String, dice_results: Array) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "combat":
		result.error = "Not in combat phase"
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

	if attacker.has_activated:
		result.error = "Unit already activated"
		return result

	if attacker.is_dead or target.is_dead:
		result.error = "Dead unit cannot attack"
		return result

	if target.owner_seat == attacker.owner_seat:
		result.error = "Cannot attack your own units"
		return result

	# Validation: weapon must be melee
	if attacker.weapon.type != "melee":
		result.error = "Unit has no melee weapon"
		return result

	# Validation: must be adjacent (distance = 1)
	var distance = abs(target.x - attacker.x) + abs(target.y - attacker.y)

	if distance != 1:
		result.error = "Target not adjacent (must be 1 cell away)"
		return result

	# Combat mechanics
	var attacker_stats = attacker.get_effective_stats()
	var target_stats = target.get_effective_stats()

	var to_hit_target = 7 - attacker_stats.combat - attacker.weapon.modifier
	var to_wound_target = 7 - attacker_stats.combat

	to_hit_target = clampi(to_hit_target, 2, 6)
	to_wound_target = clampi(to_wound_target, 2, 6)

	if dice_results.size() < 3:
		result.error = "Not enough dice provided"
		return result

	var hit_roll = dice_results[0]
	var wound_roll = dice_results[1]
	var save_roll = dice_results[2]

	var hit_success = hit_roll >= to_hit_target
	var wound_success = wound_roll >= to_wound_target
	var save_success = save_roll >= target_stats.save

	var damage_dealt: int = 0

	if hit_success and wound_success and not save_success:
		damage_dealt = 1

	var new_state = _clone_state(state)

	var new_attacker: Types.UnitState = null
	var new_target: Types.UnitState = null

	for u in new_state.units:
		if u.id == attacker_id:
			new_attacker = u
		if u.id == target_id:
			new_target = u

	new_attacker.has_activated = true

	if damage_dealt > 0:
		new_target.current_wounds -= damage_dealt
		if new_target.current_wounds <= 0:
			new_target.is_dead = true

	new_state.action_log.append({
		"turn": state.current_turn,
		"seat": state.active_seat,
		"action": "charge",
		"attacker_id": attacker_id,
		"attacker_name": attacker.name,
		"target_id": target_id,
		"target_name": target.name,
		"hit_roll": hit_roll,
		"hit_needed": to_hit_target,
		"hit_success": hit_success,
		"wound_roll": wound_roll,
		"wound_needed": to_wound_target,
		"wound_success": wound_success,
		"save_roll": save_roll,
		"save_needed": target_stats.save,
		"save_success": save_success,
		"damage": damage_dealt,
		"target_killed": new_target.is_dead
	})

	result.success = true
	result.new_state = new_state
	result.dice_rolled = dice_results
	result.description = "%s charged %s (Hit:%d/%d, Wound:%d/%d, Save:%d/%d) - %d damage%s" % [
		attacker.name, target.name,
		hit_roll, to_hit_target,
		wound_roll, to_wound_target,
		save_roll, target_stats.save,
		damage_dealt,
		" [KILLED]" if new_target.is_dead else ""
	]

	return result


## End activation for a unit (used when unit moves but doesn't attack).
static func end_activation(state: Types.GameState, unit_id: String) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "combat":
		result.error = "Not in combat phase"
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

	if unit.has_activated:
		result.error = "Unit already activated"
		return result

	var new_state = _clone_state(state)

	for u in new_state.units:
		if u.id == unit_id:
			u.has_activated = true
			break

	new_state.action_log.append({
		"turn": state.current_turn,
		"seat": state.active_seat,
		"action": "end_activation",
		"unit_id": unit_id,
		"unit_name": unit.name
	})

	result.success = true
	result.new_state = new_state
	result.description = "%s ended activation" % unit.name

	return result


## End the current turn. Switches to other player or advances turn.
static func end_turn(state: Types.GameState) -> Types.EngineResult:
	var result = Types.EngineResult.new()

	if state.phase != "combat":
		result.error = "Not in combat phase"
		return result

	# Check if active player has any unactivated units
	for unit in state.units:
		if unit.owner_seat == state.active_seat and not unit.is_dead and not unit.has_activated:
			result.error = "You have unactivated units"
			return result

	var new_state = _clone_state(state)

	# Switch to other player
	var other_seat = 3 - state.active_seat
	new_state.active_seat = other_seat

	# Reset activation flags for the new active player
	for unit in new_state.units:
		if unit.owner_seat == other_seat:
			unit.has_activated = false

	# If both players have gone, increment turn
	if other_seat == 1:
		new_state.current_turn += 1

	new_state.action_log.append({
		"turn": state.current_turn,
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
## Returns {winner: int (1 or 2 or 0), reason: String}
static func check_victory(state: Types.GameState) -> Dictionary:
	# Count living units per seat
	var units_alive_1: int = 0
	var units_alive_2: int = 0

	for unit in state.units:
		if not unit.is_dead:
			if unit.owner_seat == 1:
				units_alive_1 += 1
			else:
				units_alive_2 += 1

	if units_alive_1 == 0 and units_alive_2 > 0:
		return {"winner": 2, "reason": "Player 1 eliminated"}

	if units_alive_2 == 0 and units_alive_1 > 0:
		return {"winner": 1, "reason": "Player 2 eliminated"}

	if units_alive_1 == 0 and units_alive_2 == 0:
		return {"winner": 0, "reason": "Draw (both eliminated)"}

	# No winner yet
	return {"winner": 0, "reason": ""}


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

## Deep clone a GameState (to avoid mutation).
## Uses to_dict/from_dict for simplicity (not performant, but correct).
static func _clone_state(state: Types.GameState) -> Types.GameState:
	return Types.GameState.from_dict(state.to_dict())
