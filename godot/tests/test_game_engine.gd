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
	_test_combat_movement()
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
		print("✓ All tests passed!")
		quit(0)


# =============================================================================
# TEST SUITES
# =============================================================================

func _test_placement_phase() -> void:
	print("\n[Test Suite: Placement Phase]")

	_test("Place unit in valid deployment zone (seat 1)", func():
		var state = _mock_game_state()
		var unit = state.units[0]  # Seat 1 unit

		var result = GameEngine.place_unit(state, unit.id, 10, 30)  # Row 30 is in seat 1 zone

		return result.success and result.new_state.units[0].x == 10 and result.new_state.units[0].y == 30
	)

	_test("Place unit in valid deployment zone (seat 2)", func():
		var state = _mock_game_state()
		state.active_seat = 2
		var unit = state.units[1]  # Seat 2 unit

		var result = GameEngine.place_unit(state, unit.id, 10, 2)  # Row 2 is in seat 2 zone

		return result.success and result.new_state.units[1].x == 10 and result.new_state.units[1].y == 2
	)

	_test("Reject placement outside deployment zone", func():
		var state = _mock_game_state()
		var unit = state.units[0]

		var result = GameEngine.place_unit(state, unit.id, 10, 15)  # Row 15 not in any zone

		return not result.success and "deployment zone" in result.error
	)

	_test("Reject placement on occupied position", func():
		var state = _mock_game_state()
		# Place first unit
		state = GameEngine.place_unit(state, state.units[0].id, 10, 30).new_state

		# Try to place another unit in same spot
		# Switch to seat 2, place one of their units in seat 2 zone first
		state.active_seat = 2
		state = GameEngine.place_unit(state, state.units[1].id, 10, 2).new_state

		# Now try to place seat 2's second unit on top of their first
		var result = GameEngine.place_unit(state, state.units[3].id, 10, 2)

		return not result.success and "occupied" in result.error
	)

	_test("Reject placement of already placed unit", func():
		var state = _mock_game_state()
		var unit = state.units[0]

		# Place unit once
		state = GameEngine.place_unit(state, unit.id, 10, 30).new_state

		# Try to place it again
		var result = GameEngine.place_unit(state, unit.id, 11, 30)

		return not result.success and "already placed" in result.error
	)

	_test("Reject placement out of bounds", func():
		var state = _mock_game_state()
		var unit = state.units[0]

		var result = GameEngine.place_unit(state, unit.id, 100, 100)

		return not result.success and "out of bounds" in result.error
	)

	_test("Confirm placement switches to other player", func():
		var state = _mock_game_state_all_placed_seat_1()
		# Seat 1 has all units placed, seat 2 does not

		var result = GameEngine.confirm_placement(state)

		return result.success and result.new_state.active_seat == 2
	)

	_test("Confirm placement starts combat when both done", func():
		var state = _mock_game_state_both_placed()

		var result = GameEngine.confirm_placement(state)

		return result.success and result.new_state.phase == "combat" and result.new_state.active_seat == 1
	)

	_test("Reject confirm placement with unplaced units", func():
		var state = _mock_game_state()
		# Units not placed yet

		var result = GameEngine.confirm_placement(state)

		return not result.success and "Not all units placed" in result.error
	)


func _test_combat_movement() -> void:
	print("\n[Test Suite: Combat Movement]")

	_test("Move unit within range", func():
		var state = _mock_combat_state()
		var unit = state.units[0]
		var stats = unit.get_effective_stats()

		# Move 3 cells (within movement of 5)
		var result = GameEngine.move_unit(state, unit.id, unit.x + 3, unit.y)

		return result.success and result.new_state.units[0].x == unit.x + 3
	)

	_test("Reject move out of range", func():
		var state = _mock_combat_state()
		var unit = state.units[0]

		# Try to move 20 cells (way out of range)
		var result = GameEngine.move_unit(state, unit.id, unit.x + 20, unit.y)

		return not result.success and "movement range" in result.error
	)

	_test("Reject move to occupied position", func():
		var state = _mock_combat_state()
		var unit1 = state.units[0]
		var unit2 = state.units[1]

		# Try to move unit1 to unit2's position
		var result = GameEngine.move_unit(state, unit1.id, unit2.x, unit2.y)

		return not result.success and "occupied" in result.error
	)

	_test("Reject move of already activated unit", func():
		var state = _mock_combat_state()
		var unit = state.units[0]

		# Activate the unit
		state.units[0].has_activated = true

		var result = GameEngine.move_unit(state, unit.id, unit.x + 1, unit.y)

		return not result.success and "already activated" in result.error
	)

	_test("Reject move of opponent's unit", func():
		var state = _mock_combat_state()
		state.active_seat = 1
		var opponent_unit = state.units[1]  # Seat 2 unit

		var result = GameEngine.move_unit(state, opponent_unit.id, opponent_unit.x + 1, opponent_unit.y)

		return not result.success and "Not your unit" in result.error
	)


func _test_shooting() -> void:
	print("\n[Test Suite: Shooting]")

	_test("Successful shooting attack (hit, wound, failed save)", func():
		var state = _mock_combat_state_with_ranged()
		var attacker = state.units[0]
		var target = state.units[1]
		var target_hp = target.current_wounds

		var dice = [6, 6, 1]  # High hit, high wound, low save (fails)
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds < target_hp
	)

	_test("Shooting miss due to failed to-hit roll", func():
		var state = _mock_combat_state_with_ranged()
		var attacker = state.units[0]
		var target = state.units[1]
		var target_hp = target.current_wounds

		var dice = [1, 6, 1]  # Miss on hit roll
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds == target_hp
	)

	_test("Shooting saved by target", func():
		var state = _mock_combat_state_with_ranged()
		var attacker = state.units[0]
		var target = state.units[1]
		var target_hp = target.current_wounds

		var dice = [6, 6, 6]  # Hit, wound, but save succeeds
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds == target_hp
	)

	_test("Reject shooting out of range", func():
		var state = _mock_combat_state_with_ranged()
		var attacker = state.units[0]
		var target = state.units[1]

		# Move target far away
		state.units[1].x = 100
		state.units[1].y = 100

		var dice = [6, 6, 1]
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return not result.success and "out of range" in result.error
	)

	_test("Reject shooting with melee weapon", func():
		var state = _mock_combat_state()  # Has melee weapons
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [6, 6, 1]
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return not result.success and "no ranged weapon" in result.error
	)

	_test("Shooting marks attacker as activated", func():
		var state = _mock_combat_state_with_ranged()
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [6, 6, 1]
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[0].has_activated
	)

	_test("Shooting kills target when wounds reach zero", func():
		var state = _mock_combat_state_with_ranged()
		var attacker = state.units[0]
		var target = state.units[1]

		# Set target to 1 wound
		state.units[1].current_wounds = 1

		var dice = [6, 6, 1]  # Hit, wound, failed save → 1 damage
		var result = GameEngine.resolve_shoot(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].is_dead
	)


func _test_melee() -> void:
	print("\n[Test Suite: Melee]")

	_test("Successful melee attack on adjacent unit", func():
		var state = _mock_combat_state_adjacent()
		var attacker = state.units[0]
		var target = state.units[1]
		var target_hp = target.current_wounds

		var dice = [6, 6, 1]  # Hit, wound, failed save
		var result = GameEngine.resolve_charge(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[1].current_wounds < target_hp
	)

	_test("Reject melee on non-adjacent unit", func():
		var state = _mock_combat_state()  # Units not adjacent
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [6, 6, 1]
		var result = GameEngine.resolve_charge(state, attacker.id, target.id, dice)

		return not result.success and "adjacent" in result.error
	)

	_test("Reject melee with ranged weapon", func():
		var state = _mock_combat_state_with_ranged_adjacent()
		var attacker = state.units[0]  # Has ranged weapon
		var target = state.units[1]

		var dice = [6, 6, 1]
		var result = GameEngine.resolve_charge(state, attacker.id, target.id, dice)

		return not result.success and "no melee weapon" in result.error
	)

	_test("Melee marks attacker as activated", func():
		var state = _mock_combat_state_adjacent()
		var attacker = state.units[0]
		var target = state.units[1]

		var dice = [6, 6, 1]
		var result = GameEngine.resolve_charge(state, attacker.id, target.id, dice)

		return result.success and result.new_state.units[0].has_activated
	)


func _test_turn_management() -> void:
	print("\n[Test Suite: Turn Management]")

	_test("End activation marks unit as activated", func():
		var state = _mock_combat_state()
		var unit = state.units[0]

		var result = GameEngine.end_activation(state, unit.id)

		return result.success and result.new_state.units[0].has_activated
	)

	_test("End turn switches active player", func():
		var state = _mock_combat_state_all_activated()

		var result = GameEngine.end_turn(state)

		return result.success and result.new_state.active_seat == 2
	)

	_test("End turn resets activation for new active player", func():
		var state = _mock_combat_state_all_activated()

		var result = GameEngine.end_turn(state)

		# Check that seat 2 units have activation reset
		var seat_2_activated = false
		for unit in result.new_state.units:
			if unit.owner_seat == 2 and unit.has_activated:
				seat_2_activated = true

		return result.success and not seat_2_activated
	)

	_test("End turn increments turn number when returning to seat 1", func():
		var state = _mock_combat_state_all_activated()
		state.active_seat = 2
		state.current_turn = 1

		var result = GameEngine.end_turn(state)

		return result.success and result.new_state.current_turn == 2
	)

	_test("Reject end turn with unactivated units", func():
		var state = _mock_combat_state()  # Units not activated

		var result = GameEngine.end_turn(state)

		return not result.success and "unactivated" in result.error
	)


func _test_victory_conditions() -> void:
	print("\n[Test Suite: Victory Conditions]")

	_test("Victory when all enemy units dead (seat 1 wins)", func():
		var state = _mock_combat_state()

		# Kill all seat 2 units
		for unit in state.units:
			if unit.owner_seat == 2:
				unit.is_dead = true

		var victory = GameEngine.check_victory(state)

		return victory["winner"] == 1
	)

	_test("Victory when all enemy units dead (seat 2 wins)", func():
		var state = _mock_combat_state()

		# Kill all seat 1 units
		for unit in state.units:
			if unit.owner_seat == 1:
				unit.is_dead = true

		var victory = GameEngine.check_victory(state)

		return victory["winner"] == 2
	)

	_test("Draw when both players eliminated", func():
		var state = _mock_combat_state()

		# Kill all units
		for unit in state.units:
			unit.is_dead = true

		var victory = GameEngine.check_victory(state)

		return victory["winner"] == 0 and "Draw" in victory["reason"]
	)

	_test("No winner when both have living units", func():
		var state = _mock_combat_state()

		var victory = GameEngine.check_victory(state)

		return victory["winner"] == 0 and victory["reason"] == ""
	)


# =============================================================================
# HELPER FUNCTIONS - MOCK STATE GENERATORS
# =============================================================================

func _mock_game_state() -> Types.GameState:
	var state = Types.GameState.new()
	state.phase = "placement"
	state.active_seat = 1

	# Create 2 units per seat (4 total)
	var unit1 = _mock_unit_state("unit_0", 1, 10, 30)  # Seat 1 unit
	var unit2 = _mock_unit_state("unit_1", 2, 10, 2)   # Seat 2 unit
	var unit3 = _mock_unit_state("unit_2", 1, 12, 30)  # Seat 1 unit 2
	var unit4 = _mock_unit_state("unit_3", 2, 12, 2)   # Seat 2 unit 2

	# Mark as not placed
	unit1.x = -1
	unit1.y = -1
	unit2.x = -1
	unit2.y = -1
	unit3.x = -1
	unit3.y = -1
	unit4.x = -1
	unit4.y = -1

	state.units = [unit1, unit2, unit3, unit4]

	return state


func _mock_game_state_all_placed_seat_1() -> Types.GameState:
	var state = _mock_game_state()

	# Place all seat 1 units
	state.units[0].x = 10
	state.units[0].y = 30
	state.units[2].x = 12
	state.units[2].y = 30

	# Seat 2 units still not placed
	return state


func _mock_game_state_both_placed() -> Types.GameState:
	var state = _mock_game_state()
	state.active_seat = 2  # Seat 2 is confirming

	# Place all units
	state.units[0].x = 10
	state.units[0].y = 30
	state.units[1].x = 10
	state.units[1].y = 2
	state.units[2].x = 12
	state.units[2].y = 30
	state.units[3].x = 12
	state.units[3].y = 2

	return state


func _mock_combat_state() -> Types.GameState:
	var state = _mock_game_state_both_placed()
	state.phase = "combat"
	state.active_seat = 1

	return state


func _mock_combat_state_with_ranged() -> Types.GameState:
	var state = _mock_combat_state()

	# Give seat 1 units ranged weapons
	state.units[0].weapon = Types.Weapon.new("Musket", "ranged", 12, 0)
	state.units[2].weapon = Types.Weapon.new("Musket", "ranged", 12, 0)

	return state


func _mock_combat_state_adjacent() -> Types.GameState:
	var state = _mock_combat_state()

	# Position units adjacent (distance = 1)
	state.units[0].x = 10
	state.units[0].y = 10
	state.units[1].x = 11
	state.units[1].y = 10

	return state


func _mock_combat_state_with_ranged_adjacent() -> Types.GameState:
	var state = _mock_combat_state_adjacent()

	# Give units ranged weapons
	state.units[0].weapon = Types.Weapon.new("Musket", "ranged", 12, 0)

	return state


func _mock_combat_state_all_activated() -> Types.GameState:
	var state = _mock_combat_state()

	# Mark all seat 1 units as activated
	for unit in state.units:
		if unit.owner_seat == 1:
			unit.has_activated = true

	return state


func _mock_unit_state(id: String, seat: int, x: int, y: int) -> Types.UnitState:
	var unit = Types.UnitState.new()
	unit.id = id
	unit.owner_seat = seat
	unit.name = "Test Unit %s" % id
	unit.archetype = "Toff"
	unit.base_stats = Types.Stats.new(5, 4, 4, 5, 2, 3)
	unit.weapon = Types.Weapon.new("Sabre", "melee", 0, 0)
	unit.max_wounds = 2
	unit.current_wounds = 2
	unit.x = x
	unit.y = y
	unit.has_activated = false
	unit.is_dead = false

	return unit


# =============================================================================
# TEST FRAMEWORK
# =============================================================================

func _test(description: String, test_fn: Callable) -> void:
	var result = test_fn.call()
	if result:
		print("  ✓ " + description)
		_tests_passed += 1
	else:
		print("  ✗ " + description)
		_tests_failed += 1
