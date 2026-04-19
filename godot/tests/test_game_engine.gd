extends SceneTree
## Tests for GameEngine pure functions.
##
## Run with: godot --headless -s tests/test_game_engine.gd

var _tests_passed: int = 0
var _tests_failed: int = 0


func _init() -> void:
	print("============================================================")
	print("Running Game Engine Tests")
	print("============================================================")

	_test_placement_phase()
	_test_orders_movement()
	_test_shooting()
	_test_melee()
	_test_turn_management()
	_test_victory_conditions()

	print("")
	print("============================================================")
	print("Test Results:")
	print("  Passed: " + str(_tests_passed))
	print("  Failed: " + str(_tests_failed))
	print("============================================================")

	if _tests_failed > 0:
		quit(1)
	else:
		print("")
		print("All tests passed!")
		quit(0)


# =============================================================================
# TEST SUITES
# =============================================================================

func _test_placement_phase() -> void:
	print("\n[Test Suite: Placement Phase]")

	_test("Place unit in valid deployment zone (seat 1)", func():
		var state = _mock_game_state()
		var unit = state.units[0]

		var result = GameEngine.place_unit(state, unit.id, 10, 30)

		return result.success and result.new_state.units[0].x == 10 and result.new_state.units[0].y == 30
	)

	_test("Reject placement outside deployment zone", func():
		var state = _mock_game_state()
		var unit = state.units[0]

		var result = GameEngine.place_unit(state, unit.id, 10, 15)

		return not result.success and "deployment zone" in result.error
	)

	_test("Reject placement on occupied position", func():
		var state = _mock_game_state()
		state = GameEngine.place_unit(state, state.units[0].id, 10, 30).new_state

		state.active_seat = 2
		state = GameEngine.place_unit(state, state.units[1].id, 10, 2).new_state

		var result = GameEngine.place_unit(state, state.units[3].id, 10, 2)

		return not result.success and "occupied" in result.error
	)

	_test("Confirm placement starts orders when both done", func():
		var state = _mock_game_state_both_placed()

		var result = GameEngine.confirm_placement(state)

		return result.success and result.new_state.phase == "orders"
	)


func _test_orders_movement() -> void:
	print("\n[Test Suite: Orders Movement]")

	_test("Move unit within range", func():
		var state = _mock_orders_state()
		var unit = state.units[0]

		var result = GameEngine.move_unit(state, unit.id, unit.x + 3, unit.y)

		return result.success and result.new_state.units[0].x == unit.x + 3
	)

	_test("Reject move out of range", func():
		var state = _mock_orders_state()
		var unit = state.units[0]

		var result = GameEngine.move_unit(state, unit.id, unit.x + 20, unit.y)

		return not result.success and "movement range" in result.error
	)

	_test("Reject move of already activated unit", func():
		var state = _mock_orders_state()
		state.units[0].has_ordered = true

		var result = GameEngine.move_unit(state, state.units[0].id, state.units[0].x + 1, state.units[0].y)

		return not result.success and "already activated" in result.error
	)


func _test_shooting() -> void:
	print("\n[Test Suite: Shooting]")

	_test("Successful shooting attack (hit + failed save)", func():
		var state = _mock_orders_state_ranged()
		var attacker = state.units[0]  # 1 model, I6+, weapon_range 18
		var target = state.units[1]    # 1 model, W2, V5+

		# Need 2 dice: 1 inaccuracy + 1 vulnerability
		# Roll 6 (hits I6+), roll 1 (fails V5+)
		var dice = [6, 1]
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds == 1
	)

	_test("Shooting miss due to failed inaccuracy", func():
		var state = _mock_orders_state_ranged()
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [1, 6]  # Misses I6+
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds == 0
	)

	_test("Shooting saved by vulnerability", func():
		var state = _mock_orders_state_ranged()
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [6, 6]  # Hits I6+, but saved by V5+
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds == 0
	)

	_test("Shooting gives target panic token on hit", func():
		var state = _mock_orders_state_ranged()
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [6, 6]  # Hit (even if saved)
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].panic_tokens == 1
	)

	_test("Black powder shooting gives powder smoke", func():
		var state = _mock_orders_state_ranged()
		state.units[0].equipment = "black_powder"

		var dice = [6, 6]
		var result = GameEngine.resolve_shoot(state, state.units[0].id, state.units[1].id, dice)

		return result.success and result.new_state.units[0].has_powder_smoke
	)

	_test("Reject shooting with powder smoke", func():
		var state = _mock_orders_state_ranged()
		state.units[0].has_powder_smoke = true

		var dice = [6, 6]
		var result = GameEngine.resolve_shoot(state, state.units[0].id, state.units[1].id, dice)

		return not result.success and "powder smoke" in result.error
	)

	_test("Reject shooting without ranged weapon", func():
		var state = _mock_orders_state()
		# Force attacker to have no ranged weapon
		state.units[0].base_stats.weapon_range = 0
		# Put units close together so range isn't the issue
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 11; state.units[1].y = 10
		var dice = [6, 1]
		var result = GameEngine.resolve_shoot(state, state.units[0].id, state.units[1].id, dice)

		return not result.success and "no ranged weapon" in result.error
	)

	_test("Multi-model unit shoots once per model", func():
		var state = _mock_orders_state_ranged()
		# Make attacker a 4-model unit
		state.units[0].model_count = 4
		state.units[0].max_models = 4

		# 4 inaccuracy dice + 4 vulnerability dice = 8 total
		# All hit (6), all fail save (1)
		var dice = [6, 6, 6, 6, 1, 1, 1, 1]
		var result = GameEngine.resolve_shoot(state, state.units[0].id, state.units[1].id, dice)

		# Target has W2, so 4 wounds should kill (2 wounds to kill 1 model, but only 1 model)
		return result.success and result.new_state.units[1].is_dead
	)


func _test_melee() -> void:
	print("\n[Test Suite: Melee]")

	_test("Successful melee on adjacent unit", func():
		var state = _mock_orders_state_adjacent()
		var attacker = state.units[0]  # A2, I5+
		var target = state.units[1]    # V5+, W2

		# A=2 attacks: 2 inaccuracy + 2 vulnerability = 4 dice
		# Both hit (5+), both fail save (1)
		var dice = [5, 6, 1, 1]
		var result = GameEngine.resolve_charge(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].is_dead  # 2 wounds kills W2 model
	)

	_test("Reject melee on non-adjacent unit", func():
		var state = _mock_orders_state()
		var dice = [6, 6, 1, 1]
		var result = GameEngine.resolve_charge(state, state.units[0].id, state.units[1].id, dice)

		return not result.success and "adjacent" in result.error
	)

	_test("Close combat equipment reduces inaccuracy by 1", func():
		var state = _mock_orders_state_adjacent()
		state.units[0].equipment = "close_combat"
		state.units[0].base_stats.inaccuracy = 6  # Would need 6+, but CC makes it 5+

		# A=2: 2 inaccuracy + 2 vulnerability = 4 dice
		# Roll 5s for inaccuracy (hits with CC bonus), 1s for vulnerability
		var dice = [5, 5, 1, 1]
		var result = GameEngine.resolve_charge(state, state.units[0].id, state.units[1].id, dice)

		return result.success and result.new_state.units[1].is_dead
	)


func _test_turn_management() -> void:
	print("\n[Test Suite: Turn Management]")

	_test("End activation marks unit as activated", func():
		var state = _mock_orders_state()

		var result = GameEngine.end_activation(state, state.units[0].id)

		return result.success and result.new_state.units[0].has_ordered
	)

	_test("End turn switches active player", func():
		var state = _mock_orders_state_all_activated()

		var result = GameEngine.end_turn(state)

		return result.success and result.new_state.active_seat == 2
	)

	_test("End turn clears powder smoke at new round", func():
		var state = _mock_orders_state_all_activated()
		state.active_seat = 2
		state.initiative_seat = 1
		state.current_round = 1
		# Give a unit powder smoke
		state.units[0].has_powder_smoke = true

		# Activate all seat 2 units
		for unit in state.units:
			if unit.owner_seat == 2:
				unit.has_ordered = true

		var result = GameEngine.end_turn(state)

		# Should advance round and clear powder smoke
		return result.success and result.new_state.current_round == 2 and not result.new_state.units[0].has_powder_smoke
	)

	_test("Game ends when max rounds exceeded", func():
		var state = _mock_orders_state_all_activated()
		state.active_seat = 2
		state.initiative_seat = 1
		state.current_round = 4
		state.max_rounds = 4

		for unit in state.units:
			if unit.owner_seat == 2:
				unit.has_ordered = true

		var result = GameEngine.end_turn(state)

		return result.success and result.new_state.phase == "finished"
	)

	_test("Reject end turn with unactivated units", func():
		var state = _mock_orders_state()

		var result = GameEngine.end_turn(state)

		return not result.success and "unactivated" in result.error
	)


func _test_victory_conditions() -> void:
	print("\n[Test Suite: Victory Conditions]")

	_test("Victory when all enemy units dead", func():
		var state = _mock_orders_state()
		for unit in state.units:
			if unit.owner_seat == 2:
				unit.is_dead = true

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 1
	)

	_test("Headless Chicken: all Snobs dead = instant loss", func():
		var state = _mock_orders_state()
		# Kill seat 1's snob (unit 0) — seat 2 still has their snob (unit 1)
		state.units[0].is_dead = true

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 2 and "Snobs" in victory["reason"]
	)

	_test("Solo mode: no victory when only one side has units", func():
		# Simulate solo mode — only seat 1 units exist
		var state = Types.GameState.new()
		state.phase = "orders"
		state.active_seat = 1
		state.units.append(_mock_unit("u0", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1))
		state.units[0].x = 10; state.units[0].y = 10

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 0
	)

	_test("No winner when both have living units and snobs", func():
		var state = _mock_orders_state()

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 0 and victory["reason"] == ""
	)


# =============================================================================
# MOCK STATE GENERATORS
# =============================================================================

func _mock_unit(id: String, seat: int, unit_type: String, category: String, m: int, a: int, i: int, w: int, v: int, wr: int, models: int) -> Types.UnitState:
	var stats = Types.Stats.new(m, a, i, w, v, wr)
	var rules: Array[String] = []
	return Types.UnitState.new(id, seat, unit_type, category, models, models, stats, "black_powder", rules)


func _mock_game_state() -> Types.GameState:
	var state = Types.GameState.new()
	state.phase = "placement"
	state.active_seat = 1
	state.initiative_seat = 1

	# 2 units per seat: 1 snob + 1 follower each
	var u0 = _mock_unit("u0", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
	var u1 = _mock_unit("u1", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
	var u2 = _mock_unit("u2", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)
	var u3 = _mock_unit("u3", 2, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)

	u0.x = -1; u0.y = -1
	u1.x = -1; u1.y = -1
	u2.x = -1; u2.y = -1
	u3.x = -1; u3.y = -1

	state.units.append(u0)
	state.units.append(u1)
	state.units.append(u2)
	state.units.append(u3)

	return state


func _mock_game_state_both_placed() -> Types.GameState:
	var state = _mock_game_state()
	state.active_seat = 2

	state.units[0].x = 10; state.units[0].y = 30
	state.units[1].x = 10; state.units[1].y = 2
	state.units[2].x = 12; state.units[2].y = 30
	state.units[3].x = 12; state.units[3].y = 2

	return state


func _mock_orders_state() -> Types.GameState:
	var state = _mock_game_state_both_placed()
	state.phase = "orders"
	state.active_seat = 1
	return state


func _mock_orders_state_ranged() -> Types.GameState:
	var state = _mock_orders_state()
	# Position units within range of each other (distance 10, range 18)
	state.units[0].x = 10; state.units[0].y = 15
	state.units[1].x = 20; state.units[1].y = 15
	# Give units ranged weapons via weapon_range
	state.units[0].base_stats.weapon_range = 18
	state.units[1].base_stats.weapon_range = 18
	return state


func _mock_orders_state_adjacent() -> Types.GameState:
	var state = _mock_orders_state()
	state.units[0].x = 10; state.units[0].y = 10
	state.units[1].x = 11; state.units[1].y = 10
	return state


func _mock_orders_state_all_activated() -> Types.GameState:
	var state = _mock_orders_state()
	for unit in state.units:
		if unit.owner_seat == 1:
			unit.has_ordered = true
	return state


# =============================================================================
# TEST FRAMEWORK
# =============================================================================

func _test(description: String, test_fn: Callable) -> void:
	var result = test_fn.call()
	if result:
		print("  PASS " + description)
		_tests_passed += 1
	else:
		print("  FAIL " + description)
		_tests_failed += 1
