extends SceneTree
## Tests for GameEngine pure functions.
##
## Run with: godot --headless -s tests/test_game_engine.gd

const Targeting = preload("res://game/targeting.gd")
const Combat = preload("res://game/combat.gd")
const Panic = preload("res://game/panic.gd")
const Objectives = preload("res://game/objectives.gd")

var _tests_passed: int = 0
var _tests_failed: int = 0


func _init() -> void:
	print("============================================================")
	print("Running Game Engine Tests")
	print("============================================================")

	_test_placement_phase()
	_test_snob_selection()
	_test_declare_order()
	_test_declare_self_order()
	_test_execute_volley_fire()
	_test_execute_move_and_shoot()
	_test_execute_march()
	_test_execute_charge()
	_test_panic_test()
	_test_retreat()
	_test_melee_bouts()
	_test_shooting_engagements()
	_test_line_of_sight()
	_test_advance_flow()
	_test_victory_conditions()
	_test_objectives()

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

		return result.is_success() and result.new_state.units[0].x == 10 and result.new_state.units[0].y == 30
	)

	_test("Reject placement outside deployment zone", func():
		var state = _mock_game_state()
		var unit = state.units[0]

		var result = GameEngine.place_unit(state, unit.id, 10, 15)

		return not result.is_success() and "deployment zone" in result.error
	)

	_test("Reject placement on occupied position", func():
		var state = _mock_game_state()
		state = GameEngine.place_unit(state, state.units[0].id, 10, 30).new_state

		state.active_seat = 2
		state = GameEngine.place_unit(state, state.units[1].id, 10, 2).new_state

		var result = GameEngine.place_unit(state, state.units[3].id, 10, 2)

		return not result.is_success() and "occupied" in result.error
	)

	_test("Confirm placement starts orders when both done", func():
		var state = _mock_game_state_both_placed()

		var result = GameEngine.confirm_placement(state)

		return (result.is_success()
			and result.new_state.phase == "orders"
			and result.new_state.order_phase == "snob_select")
	)


func _test_snob_selection() -> void:
	print("\n[Test Suite: Snob Selection]")

	_test("select_snob: valid Toff transitions to order_declare", func():
		var state = _mock_orders_state()
		var result = GameEngine.select_snob(state, state.units[0].id)

		return (result.is_success()
			and result.new_state.order_phase == "order_declare"
			and result.new_state.current_snob_id == state.units[0].id)
	)

	_test("select_snob: reject non-Snob", func():
		var state = _mock_orders_state()
		var result = GameEngine.select_snob(state, state.units[2].id)

		return not result.is_success() and "not a Snob" in result.error
	)

	_test("select_snob: reject enemy Snob", func():
		var state = _mock_orders_state()
		var result = GameEngine.select_snob(state, state.units[1].id)

		return not result.is_success() and "Not your Snob" in result.error
	)

	_test("select_snob: reject already-ordered Snob", func():
		var state = _mock_orders_state()
		state.units[0].has_ordered = true

		var result = GameEngine.select_snob(state, state.units[0].id)

		return not result.is_success() and "already ordered" in result.error
	)

	_test("select_snob: reject outside snob_select phase", func():
		var state = _mock_orders_state()
		state.order_phase = "order_declare"

		var result = GameEngine.select_snob(state, state.units[0].id)

		return not result.is_success() and "snob selection" in result.error
	)


func _test_declare_order() -> void:
	print("\n[Test Suite: Declare Order]")

	_test("declare_order: valid follower in command range", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "march", 3, [3, 4])

		return (result.is_success()
			and result.new_state.order_phase == "order_execute"
			and result.new_state.current_order_type == "march"
			and result.new_state.current_order_move_bonus == 7)  # 3+4 unblundered
	)

	_test("declare_order: reject follower out of command range", func():
		var state = _mock_orders_state()
		# Toff at (10,30), range=6. Move Fodder 20 cells away.
		state.units[2].x = 30; state.units[2].y = 30
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "march", 3, [3, 3])

		return not result.is_success() and "command range" in result.error
	)

	_test("declare_order: diagonal follower within Euclidean command range succeeds", func():
		var state = _mock_orders_state()
		# Toff at (10,30), command_range=6. Place Fodder diagonally:
		# dx=4, dy=4. Euclidean = sqrt(32) ≈ 5.66 ≤ 6. In range.
		# Manhattan would be 8 > 6 → rejected. Proves Euclidean.
		state.units[2].x = 14; state.units[2].y = 26
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "march", 3, [3, 3])

		return result.is_success()
	)

	_test("declare_order: Snob self-order bypasses blunder check", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		# blunder_die=1 normally blunders, but self-order never blunders
		var result = GameEngine.declare_order(state, state.units[0].id, "march", 1, [3, 3])

		return (result.is_success()
			and not result.new_state.current_order_blundered
			and result.new_state.units[0].panic_tokens == 0)
	)

	_test("declare_order: blunder_die==1 adds panic + halves march bonus", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "march", 1, [4, 5])

		return (result.is_success()
			and result.new_state.current_order_blundered
			and result.new_state.units[2].panic_tokens == 1
			and result.new_state.current_order_move_bonus == 4)  # only first die
	)

	_test("declare_order: reject volley_fire without ranged weapon", func():
		var state = _mock_orders_state()
		state.units[2].base_stats.weapon_range = 0
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "volley_fire", 3, [3, 3])

		return not result.is_success() and "ranged weapon" in result.error
	)

	_test("declare_order: reject volley_fire with powder smoke", func():
		var state = _mock_orders_state()
		state.units[2].base_stats.weapon_range = 12
		state.units[2].has_powder_smoke = true
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "volley_fire", 3, [3, 3])

		return not result.is_success() and "powder smoke" in result.error
	)

	_test("declare_order: reject ordering another Snob", func():
		var state = _mock_orders_state()
		# Add a second seat-1 Snob (Toady) within command range
		var u4 = _mock_unit("u4", 1, "Toady", "snob", 6, 2, 5, 2, 5, 0, 1)
		u4.x = 11; u4.y = 30
		state.units.append(u4)
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, u4.id, "march", 3, [3, 3])

		return not result.is_success() and "another Snob" in result.error
	)

	_test("declare_order: reject invalid order type", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "teleport", 3, [3, 3])

		return not result.is_success() and "Invalid order type" in result.error
	)


func _test_declare_self_order() -> void:
	print("\n[Test Suite: Declare Self-Order (Follower Phase)]")

	_test("declare_self_order: valid follower self-orders", func():
		var state = _mock_orders_state_follower_phase()
		var result = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 4])

		return (result.is_success()
			and result.new_state.order_phase == "order_execute"
			and result.new_state.current_order_unit_id == state.units[2].id
			and result.new_state.current_snob_id == ""
			and result.new_state.current_order_move_bonus == 7)
	)

	_test("declare_self_order: blunder_die==1 always blunders", func():
		var state = _mock_orders_state_follower_phase()
		var result = GameEngine.declare_self_order(state, state.units[2].id, "march", 1, [4, 5])

		return (result.is_success()
			and result.new_state.current_order_blundered
			and result.new_state.units[2].panic_tokens == 1
			and result.new_state.current_order_move_bonus == 4)
	)

	_test("declare_self_order: reject Snob", func():
		var state = _mock_orders_state_follower_phase()
		state.units[0].has_ordered = false  # un-order the Snob to test rejection

		var result = GameEngine.declare_self_order(state, state.units[0].id, "march", 3, [3, 3])

		return not result.is_success() and "Snobs don't self-order" in result.error
	)

	_test("declare_self_order: reject outside follower_self_order phase", func():
		var state = _mock_orders_state()
		# phase is snob_select, not follower_self_order
		var result = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 3])

		return not result.is_success() and "follower self-order" in result.error
	)


func _test_execute_volley_fire() -> void:
	print("\n[Test Suite: Execute Volley Fire]")

	_test("volley_fire: unblundered grants -1 Inaccuracy", func():
		var state = _mock_orders_state_ranged()
		# Self-order from Snob 0: weapon_range=18, target at distance 10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Toff I=5, -1 bonus → needs 4+. Target V=5, W=2.
		# Die 4 hits, die 1 fails save → 1 wound. Target returns fire with 2 dice,
		# both whiff → 0 shooter wounds.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [4, 1, 1, 1])

		return result.is_success() and result.new_state.units[1].current_wounds == 1
	)

	_test("volley_fire: unblundered roll that barely misses without bonus still hits", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Die 4 hits with -1 bonus (base I=5 would have missed). Die 6 saves V=5.
		# Return fire: 2 dice of 1 → miss, no shooter wounds.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [4, 6, 1, 1])

		return result.is_success() and result.new_state.units[1].current_wounds == 0  # saved
	)

	_test("volley_fire: blundered loses -1 bonus", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Order FOLLOWER (u2) so blunder applies. Follower is Fodder, set up for ranged.
		state.units[2].base_stats.weapon_range = 18
		state.units[2].model_count = 1  # simplify dice count for this test
		state.units[2].max_models = 1
		state.units[2].x = 12; state.units[2].y = 15
		state = GameEngine.declare_order(state, state.units[2].id, "volley_fire", 1, [3, 3]).new_state

		# Fodder I=6. Blundered: no -1, so needs 6+. Die 5 misses.
		# Return fire from Toff u1: 2 dice → 1s miss.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [5, 1, 1, 1])

		return result.is_success() and result.new_state.units[1].current_wounds == 0
	)

	_test("volley_fire: black_powder grants powder smoke after firing", func():
		var state = _mock_orders_state_ranged()
		state.units[0].equipment = "black_powder"
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Shooter miss (3 at I4+), return fire 2 dice of 1 → miss.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [3, 1, 1, 1])

		return result.is_success() and result.new_state.units[0].has_powder_smoke
	)

	_test("volley_fire: hit grants target a panic token", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Die 4 hits (I4+ with bonus), die 6 saves. Hit → panic token even if saved.
		# Return fire: 2 dice of 1 → miss (no extra panic flow).
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [4, 6, 1, 1])

		return result.is_success() and result.new_state.units[1].panic_tokens == 1
	)

	_test("volley_fire: fizzle succeeds when no enemy in range", func():
		var state = _mock_orders_state()
		# u0 Toff weapon_range=6 at (10,30); u1 at (10,2) → distance 28, out of range.
		# u3 at (12,2) → distance 26, also out of range. No valid target.
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"fizzle": true}, [])
		return (result.is_success()
			and result.new_state.units[0].has_ordered
			and result.new_state.units[1].current_wounds == 0)
	)

	_test("volley_fire: fizzle rejected when a valid target exists", func():
		var state = _mock_orders_state_ranged()
		# Enemies are in range (18); fizzle should be refused.
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"fizzle": true}, [])
		return not result.is_success() and "Cannot fizzle" in result.error
	)

	_test("volley_fire: diagonal target within Euclidean range is valid", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[0].base_stats.weapon_range = 18
		# Place enemy diagonally: dx=12, dy=12. Euclidean = sqrt(288) ≈ 16.97 ≤ 18.
		# Manhattan would be 24 > 18 → out of range. Proves Euclidean works.
		state.units[1].x = 22; state.units[1].y = 27
		# Remove other enemy so u1 is the closest (closest-target rule).
		state.units[3].is_dead = true
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [6, 1])
		return result.is_success()
	)

	_test("volley_fire: multi-model unit fires one attack per model", func():
		var state = _mock_orders_state_ranged()
		# Make Fodder a 4-model ranged unit
		state.units[2].model_count = 4
		state.units[2].max_models = 4
		state.units[2].base_stats.weapon_range = 18
		state.units[2].x = 12; state.units[2].y = 15
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[2].id, "volley_fire", 3, [3, 3]).new_state

		# Fodder I=6, bonus -1 → 5+. All 4 hit, all 4 fail save → 4 wounds.
		# Target is Toff W=2, model_count=1 → dies after 2 wounds.
		# Target had 1 model pre-engagement → returns fire with 2 dice (casualties
		# don't suppress return fire per v17 p.13). Both miss.
		var dice = [5, 5, 5, 5, 1, 1, 1, 1, 1, 1]
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, dice)

		return result.is_success() and result.new_state.units[1].is_dead
	)


func _test_execute_move_and_shoot() -> void:
	print("\n[Test Suite: Execute Move and Shoot]")

	_test("move_and_shoot: moves then fires at new position", func():
		var state = _mock_orders_state_ranged()
		# Target u1 at (20,15). Move Snob from (10,15) to (12,15), still within 18.
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# After move, distance 8 ≤ 18. Toff I=5, no bonus → 5+. Die 5 hits. Die 1 wounds.
		# Return fire: 2 dice of 1 → miss.
		var params = {"x": 12, "y": 15, "target_id": state.units[1].id}
		var result = GameEngine.execute_order(state, params, [5, 1, 1, 1])

		return (result.is_success()
			and result.new_state.units[0].x == 12
			and result.new_state.units[1].current_wounds == 1)
	)

	_test("move_and_shoot: move without target is legal (no target_id)", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# Just move, no shot (no target_id)
		var result = GameEngine.execute_order(state, {"x": 13, "y": 15}, [])

		return (result.is_success()
			and result.new_state.units[0].x == 13
			and result.new_state.units[1].current_wounds == 0)
	)

	_test("move_and_shoot: blundered caps movement to 1D6 (first die)", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Order FOLLOWER so blunder applies. Make Fodder ranged for move_and_shoot legality.
		state.units[2].base_stats.weapon_range = 12
		state.units[2].model_count = 1
		state.units[2].max_models = 1
		state.units[2].x = 12; state.units[2].y = 15
		# Blunder (die=1), move_dice=[3, 5] → bonus should be 3, so max_move=3.
		state = GameEngine.declare_order(state, state.units[2].id, "move_and_shoot", 1, [3, 5]).new_state

		# (15, 15) from (12, 15) = distance 3. Exactly at the blundered cap.
		var result = GameEngine.execute_order(state, {"x": 15, "y": 15}, [])

		return (result.is_success()
			and result.new_state.units[2].x == 15
			and result.new_state.units[2].y == 15)
	)

	_test("move_and_shoot: blundered rejects move beyond 1D6", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state.units[2].base_stats.weapon_range = 12
		state.units[2].model_count = 1
		state.units[2].max_models = 1
		state.units[2].x = 12; state.units[2].y = 15
		# Blunder, bonus = 2 (first die)
		state = GameEngine.declare_order(state, state.units[2].id, "move_and_shoot", 1, [2, 5]).new_state

		# Distance 3 > 2 → rejected
		var result = GameEngine.execute_order(state, {"x": 15, "y": 15}, [])

		return not result.is_success() and "movement range" in result.error
	)

	_test("move_and_shoot: reject move beyond M", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# Toff M=6, from (10,15). (17,15) is distance 7 > 6 and unoccupied.
		var result = GameEngine.execute_order(state, {"x": 17, "y": 15}, [])

		return not result.is_success() and "movement range" in result.error
	)


func _test_execute_march() -> void:
	print("\n[Test Suite: Execute March]")

	_test("march: moves up to M + bonus dice (unblundered)", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Self-order march with dice [5, 5]: bonus = 10. Toff M=6 → max 16.
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [5, 5]).new_state

		# From (10,30) to (10,14) = distance 16. Exactly max.
		var result = GameEngine.execute_order(state, {"x": 10, "y": 14}, [])

		return (result.is_success()
			and result.new_state.units[0].x == 10
			and result.new_state.units[0].y == 14)
	)

	_test("march: blundered uses only first die for bonus", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Order follower with blunder, dice [3, 5]: bonus = 3 (only first), not 8.
		state = GameEngine.declare_order(state, state.units[2].id, "march", 1, [3, 5]).new_state

		# Fodder M=6, bonus 3, total 9. From (12,30) to (12,20) = 10 > 9.
		var result = GameEngine.execute_order(state, {"x": 12, "y": 20}, [])

		return not result.is_success() and "march range" in result.error
	)

	_test("march: reject out-of-range destination", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [1, 1]).new_state

		# Toff M=6, bonus 2, total 8. Distance 20 > 8.
		var result = GameEngine.execute_order(state, {"x": 10, "y": 10}, [])

		return not result.is_success() and "march range" in result.error
	)

	_test("march: diagonal move within Euclidean range succeeds (would fail Manhattan)", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 15
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Self-order march, bonus = 6+4=10. Toff M=6 → max 16.
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [6, 4]).new_state

		# (21, 26) → dx=11, dy=11. Euclidean = sqrt(242) ≈ 15.56 ≤ 16. OK.
		# Manhattan would be 22 > 16 → rejected. This test proves Euclidean is active.
		var result = GameEngine.execute_order(state, {"x": 21, "y": 26}, [])

		return result.is_success() and result.new_state.units[0].x == 21
	)


func _test_execute_charge() -> void:
	print("\n[Test Suite: Execute Charge]")

	_test("charge: moves adjacent to target and resolves melee", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 15; state.units[1].y = 10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Self-order, dice [3, 3]: bonus = 6. Toff M=6 → range 12. Distance to target = 5.
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		# Toff A=2, I=5, target V=5 W=2. 2 attacks × 2 dice = 4 dice.
		# [5,5,1,1]: 2 hits, 2 unsaved → 2 wounds → target dies.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [5, 5, 1, 1])

		return (result.is_success()
			and result.new_state.units[0].x == 14  # moves to nearest adjacent cell
			and result.new_state.units[0].y == 10
			and result.new_state.units[1].is_dead)
	)

	_test("charge: reject target out of charge range", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 30; state.units[1].y = 10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		# Bonus 2, total range 8. Distance 20 > 8.
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [1, 1]).new_state

		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [5, 5, 1, 1])

		return not result.is_success() and "charge range" in result.error
	)

	_test("charge: close_combat equipment reduces inaccuracy by 1", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 11; state.units[1].y = 10
		state.units[0].equipment = "close_combat"
		state.units[0].base_stats.inaccuracy = 6  # Without CC would need 6+; with CC 5+.
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		# Roll 5s for attacks (hits only with CC bonus), 1s for saves.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [5, 5, 1, 1])

		return result.is_success() and result.new_state.units[1].is_dead
	)

	_test("charge: fizzle succeeds when no enemy in charge range", func():
		var state = _mock_orders_state()
		# Default Toff M=6, blunder roll=1 caps bonus. Put enemies far away.
		state.units[0].x = 10; state.units[0].y = 30
		state.units[1].x = 10; state.units[1].y = 2   # distance 28
		state.units[3].x = 12; state.units[3].y = 2   # distance 26
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"fizzle": true}, [])
		return (result.is_success() and result.new_state.units[0].has_ordered)
	)

	_test("charge: fizzle rejected when a valid target exists", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 11; state.units[1].y = 10  # adjacent, clearly chargeable
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"fizzle": true}, [])
		return not result.is_success() and "Cannot fizzle" in result.error
	)


func _test_panic_test() -> void:
	print("\n[Test Suite: Panic Test]")

	_test("panic_test: 0 tokens auto-passes", func():
		var unit = _mock_unit("u0", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)
		unit.panic_tokens = 0
		var result = GameEngine.Panic.panic_test(unit, 6, 1)
		return result["passed"] and result["auto_passed"]
	)

	_test("panic_test: natural 1 always passes regardless of tokens", func():
		var unit = _mock_unit("u0", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)
		unit.panic_tokens = 6  # max tokens, but die=1 → pass
		var result = GameEngine.Panic.panic_test(unit, 1, 1)
		return result["passed"] and not result["auto_passed"]
	)

	_test("panic_test: D6 + tokens <= 6 passes", func():
		var unit = _mock_unit("u0", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)
		unit.panic_tokens = 3  # die=3, total=6 ≤ 6 → pass
		var result = GameEngine.Panic.panic_test(unit, 3, 1)
		return result["passed"] and result["total"] == 6
	)

	_test("panic_test: D6 + tokens >= 7 fails", func():
		var unit = _mock_unit("u0", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)
		unit.panic_tokens = 3  # die=4, total=7 ≥ 7 → fail
		var result = GameEngine.Panic.panic_test(unit, 4, 1)
		return not result["passed"] and result["total"] == 7
	)

	_test("panic_test: Fearless unit overrides fail on 3+", func():
		var stats = Types.Stats.new(6, 2, 5, 1, 5, 18)
		var rules: Array[String] = ["fearless"]
		var unit = Types.UnitState.new("u0", 1, "Brutes", "infantry", 6, 6, stats, "black_powder", rules)
		unit.panic_tokens = 4  # die=5, total=9 → fail, but Fearless 3+ saves
		var result = GameEngine.Panic.panic_test(unit, 5, 3)
		return result["passed"] and result["fearless_override"] and result["used_fearless"]
	)

	_test("panic_test: Fearless unit fails override on 1-2", func():
		var stats = Types.Stats.new(6, 2, 5, 1, 5, 18)
		var rules: Array[String] = ["fearless"]
		var unit = Types.UnitState.new("u0", 1, "Brutes", "infantry", 6, 6, stats, "black_powder", rules)
		unit.panic_tokens = 4  # die=5, total=9 → fail, Fearless die=2 → still fails
		var result = GameEngine.Panic.panic_test(unit, 5, 2)
		return not result["passed"] and result["used_fearless"] and not result["fearless_override"]
	)

	_test("panic_test: Safety in Numbers grants Fearless at 8+ models", func():
		var stats = Types.Stats.new(6, 1, 6, 1, 6, 0)
		var rules: Array[String] = ["safety_in_numbers"]
		var unit = Types.UnitState.new("u0", 1, "Fodder", "infantry", 8, 12, stats, "black_powder", rules)
		unit.panic_tokens = 4
		var result = GameEngine.Panic.panic_test(unit, 5, 4)  # total=9, Fearless die=4 → override
		return result["passed"] and result["fearless_override"]
	)

	_test("panic_test: Safety in Numbers loses Fearless below 8 models", func():
		var stats = Types.Stats.new(6, 1, 6, 1, 6, 0)
		var rules: Array[String] = ["safety_in_numbers"]
		var unit = Types.UnitState.new("u0", 1, "Fodder", "infantry", 7, 12, stats, "black_powder", rules)
		unit.panic_tokens = 4
		var result = GameEngine.Panic.panic_test(unit, 5, 4)  # total=9, but not Fearless → fails
		return not result["passed"] and not result["used_fearless"]
	)

	# -- Charge integration --

	_test("charge: target with panic tokens fails test and flees (no melee)", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 15; state.units[1].y = 10
		state.units[1].panic_tokens = 4  # die=4 → total=8 ≥ 7 → fail
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		var params = {"target_id": state.units[1].id, "panic_die": 4, "fearless_die": 1, "retreat_die": 2}
		var result = GameEngine.execute_order(state, params, [5, 5, 1, 1])

		# After +1 panic token, target has 5 tokens. Retreat distance = D6 + 2×5 =
		# 2 + 10 = 12. Target was at (15,10), charger at (10,10), retreat +X.
		# Ideal destination: (27, 10).
		return (result.is_success()
			and result.new_state.units[0].x == 14  # charger moved adjacent
			and not result.new_state.units[1].is_dead  # no melee happened
			and result.new_state.units[1].panic_tokens == 5  # +1 from failed test
			and result.new_state.units[1].x == 27  # retreated 12 cells right
			and result.new_state.units[1].y == 10
			and result.new_state.units[1].current_wounds == 0)
	)

	_test("charge: target passes panic test, melee resolves normally", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 15; state.units[1].y = 10
		state.units[1].panic_tokens = 2  # die=3 → total=5 ≤ 6 → pass
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		var params = {"target_id": state.units[1].id, "panic_die": 3, "fearless_die": 1}
		var result = GameEngine.execute_order(state, params, [5, 5, 1, 1])

		return (result.is_success()
			and result.new_state.units[1].is_dead  # melee resolved, target killed
			and result.new_state.units[1].panic_tokens == 2)  # no extra panic
	)

	_test("charge: Fearless target holds despite failed panic roll", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		# Replace u1 with Brutes (Fearless)
		var stats = Types.Stats.new(6, 2, 5, 2, 5, 18)
		var rules: Array[String] = ["fearless"]
		state.units[1] = Types.UnitState.new("u1", 2, "Brutes", "infantry", 6, 6, stats, "black_powder", rules)
		state.units[1].x = 15; state.units[1].y = 10
		state.units[1].panic_tokens = 4  # die=5 → total=9, Fearless die=3 → override
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [3, 3]).new_state

		var params = {"target_id": state.units[1].id, "panic_die": 5, "fearless_die": 3}
		# Bout 1: attacker Toff (A=2, 1 model) strikes first with 4 dice
		# [5,5,1,1] → 2 hits, 0 saves, 2 unsaved → Brutes lose 1 model (6→5).
		# Defender counter-strikes: Brutes A=2 × 5 models = 10 attacks = 20 dice.
		# [1,1,...] all misses → 0 wounds. Atk=2, def=0 → charger wins bout 1.
		# Panic post-melee: +1 for both. Brutes had 4 → 5 (test asserts final).
		var dice = [5, 5, 1, 1]
		for i in range(20):
			dice.append(1)
		var result = GameEngine.execute_order(state, params, dice)

		return (result.is_success()
			and result.new_state.units[0].x == 14  # charger moved
			and result.new_state.units[1].panic_tokens == 5  # +1 post-melee
			and result.new_state.units[1].model_count < 6)  # melee happened, took casualties
	)


func _test_retreat() -> void:
	print("\n[Test Suite: Retreat]")

	_test("retreat: distance is D6 + 2 per panic token", func():
		var state = _mock_orders_state()
		# Unit at (20,15), enemy at (15,15). Retreat direction: +X.
		# retreat_die=3, 3 tokens → distance = 3 + 6 = 9 → x = 29.
		state.units[2].x = 20; state.units[2].y = 15
		state.units[2].panic_tokens = 3
		state.units[1].x = 15; state.units[1].y = 15  # nearest enemy
		var result = GameEngine.Panic.execute_retreat(state, state.units[2].id, 3)
		return (result["retreated"]
			and result["distance"] == 9
			and state.units[2].x == 29
			and state.units[2].y == 15)
	)

	_test("retreat: diagonal direction works correctly", func():
		var state = _mock_orders_state()
		# Unit at (20,20), enemy at (17,17). Direction: +X,+Y (normalized).
		# retreat_die=1, 2 tokens → distance 5. Diagonal: 5/√2 ≈ 3.54 → (24,24).
		state.units[2].x = 20; state.units[2].y = 20
		state.units[2].panic_tokens = 2
		state.units[1].x = 17; state.units[1].y = 17
		var result = GameEngine.Panic.execute_retreat(state, state.units[2].id, 1)
		return (result["retreated"]
			and state.units[2].x == 24
			and state.units[2].y == 24)
	)

	_test("retreat: D6 alone carries the unit with 0 panic tokens", func():
		var state = _mock_orders_state()
		# retreat_die=4, 0 tokens → distance 4, x = 24.
		state.units[2].x = 20; state.units[2].y = 15
		state.units[2].panic_tokens = 0
		state.units[1].x = 15; state.units[1].y = 15
		var result = GameEngine.Panic.execute_retreat(state, state.units[2].id, 4)
		return (result["retreated"]
			and result["distance"] == 4
			and state.units[2].x == 24)
	)

	_test("retreat: board edge destroys unit", func():
		var state = _mock_orders_state()
		# Unit at (46,15), enemy at (44,15). Retreat direction: +X.
		# retreat_die=1, 3 tokens → distance 7. Ideal: (53,15) → off board → destroyed.
		state.units[2].x = 46; state.units[2].y = 15
		state.units[2].panic_tokens = 3
		state.units[1].x = 44; state.units[1].y = 15
		var result = GameEngine.Panic.execute_retreat(state, state.units[2].id, 1)
		return (result["retreated"]
			and result["destroyed"]
			and state.units[2].is_dead
			and state.units[2].model_count == 0)
	)

	_test("retreat: Stubborn Fanatics never retreat", func():
		var state = _mock_orders_state()
		var stats = Types.Stats.new(0, 3, 6, 3, 5, 60)
		var rules: Array[String] = ["immobile", "stubborn_fanatics"]
		var stump = Types.UnitState.new("stump", 1, "Stump Gun", "artillery", 1, 1, stats, "black_powder", rules)
		stump.x = 20; stump.y = 15
		stump.panic_tokens = 4
		state.units.append(stump)
		state.units[1].x = 15; state.units[1].y = 15
		var result = GameEngine.Panic.execute_retreat(state, "stump", 6)
		return (result["stubborn_held"]
			and not result["retreated"]
			and stump.x == 20 and stump.y == 15)
	)

	_test("retreat: avoids occupied cells", func():
		var state = _mock_orders_state()
		# Unit at (20,15), enemy at (18,15). Retreat direction: +X.
		# retreat_die=1, 1 token → distance 3. Ideal dest: (23,15). Blocker there.
		state.units[2].x = 20; state.units[2].y = 15
		state.units[2].panic_tokens = 1
		state.units[1].x = 18; state.units[1].y = 15
		state.units[3].x = 23; state.units[3].y = 15  # blocker at ideal dest
		var result = GameEngine.Panic.execute_retreat(state, state.units[2].id, 1)
		return (result["retreated"]
			and (state.units[2].x != 23 or state.units[2].y != 15))
	)

	_test("retreat: retreat_die carries even with 0 panic tokens and high roll", func():
		var state = _mock_orders_state()
		# retreat_die=6, 0 tokens → distance 6.
		state.units[2].x = 20; state.units[2].y = 15
		state.units[2].panic_tokens = 0
		state.units[1].x = 15; state.units[1].y = 15
		var result = GameEngine.Panic.execute_retreat(state, state.units[2].id, 6)
		return (result["retreated"]
			and result["distance"] == 6
			and state.units[2].x == 26)
	)


func _test_melee_bouts() -> void:
	print("\n[Test Suite: Melee Bouts]")

	# --- Direct Combat.resolve_melee unit tests ---

	_test("melee: attacker kills defender in bout 1, no counter-attack", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		var def = _mock_unit("def", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		# Attacker 2 attacks × 2 dice = 4 dice. [5,5,1,1] → 2 hits, 2 unsaved → defender dies.
		var combat = GameEngine.Combat.resolve_melee(atk, def, [5, 5, 1, 1])
		return (combat["error"] == ""
			and combat["bouts"].size() == 1
			and combat["winner_id"] == "atk"
			and combat["loser_id"] == "def"
			and not combat["draw"]
			and combat["dice_used"] == 4
			and def.is_dead
			and not atk.is_dead)
	)

	_test("melee: defender counter-attack kills attacker in bout 1", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		var def = _mock_unit("def", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		# Attacker [1,1,1,1] → 0 hits. Defender [5,5,1,1] → 2 unsaved → attacker dies.
		var combat = GameEngine.Combat.resolve_melee(atk, def, [1, 1, 1, 1, 5, 5, 1, 1])
		return (combat["error"] == ""
			and combat["bouts"].size() == 1
			and combat["winner_id"] == "def"
			and combat["loser_id"] == "atk"
			and atk.is_dead
			and not def.is_dead)
	)

	_test("melee: tied bout 1 proceeds to bout 2, decisive there", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		var def = _mock_unit("def", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		# Bout 1: both whiff (0-0 tie). Bout 2: attacker kills.
		var dice = [1, 1, 1, 1,   1, 1, 1, 1,   5, 5, 1, 1]
		var combat = GameEngine.Combat.resolve_melee(atk, def, dice)
		return (combat["error"] == ""
			and combat["bouts"].size() == 2
			and combat["winner_id"] == "atk"
			and combat["loser_id"] == "def"
			and not combat["draw"]
			and def.is_dead)
	)

	_test("melee: bout cap reached with ties ends in draw, no winner", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		var def = _mock_unit("def", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		# 3 bouts × 2 sides × 4 dice = 24 dice, all whiffs → ties every bout.
		var dice: Array = []
		for i in range(24):
			dice.append(1)
		var combat = GameEngine.Combat.resolve_melee(atk, def, dice)
		return (combat["error"] == ""
			and combat["bouts"].size() == Combat.MELEE_MAX_BOUTS
			and combat["draw"]
			and combat["winner_id"] == ""
			and combat["loser_id"] == ""
			and not atk.is_dead
			and not def.is_dead)
	)

	_test("melee: rejects if one side already dead", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		var def = _mock_unit("def", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		def.is_dead = true
		var combat = GameEngine.Combat.resolve_melee(atk, def, [])
		return combat["error"] != ""
	)

	_test("melee: errors when dice pool too small", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		var def = _mock_unit("def", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
		# Attacker needs 4 dice, give it 2.
		var combat = GameEngine.Combat.resolve_melee(atk, def, [5, 5])
		return combat["error"] != "" and "Not enough dice" in combat["error"]
	)

	# --- Integration via charge path ---

	_test("charge: both participants gain +1 panic after melee ends", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 11; state.units[1].y = 10  # adjacent
		state.units[0].panic_tokens = 0
		state.units[1].panic_tokens = 0
		# Give defender multiple models so melee doesn't end via death.
		# Replace u1 with 6-model Brutes-like unit (use Toff stats for simplicity).
		state.units[1].model_count = 6
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [1, 1]).new_state

		# Attacker bout 1: [5,5,1,1] → 2 unsaved → 1 model killed (6→5). Defender counters
		# with 5×2=10 attacks = 20 dice, all whiff → 0 wounds. Atk=2, def=0 → atk wins bout 1.
		var dice = [5, 5, 1, 1]
		for i in range(20):
			dice.append(1)
		# Target panic_die=6 + 0 tokens → auto-passes (skipped).
		var params = {"target_id": state.units[1].id, "panic_die": 6, "fearless_die": 1}
		var result = GameEngine.execute_order(state, params, dice)

		return (result.is_success()
			and result.new_state.units[0].panic_tokens == 1  # attacker +1 post-melee
			and result.new_state.units[1].panic_tokens == 1  # defender +1 post-melee
			and not result.new_state.units[0].is_dead
			and result.new_state.units[1].model_count == 5)
	)

	_test("charge: charger loses bout → charger retreats, defender holds", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 11; state.units[1].y = 10
		state.units[0].panic_tokens = 0
		state.units[1].panic_tokens = 0
		# Boost charger wounds so it survives the bout and can retreat.
		state.units[0].base_stats.wounds = 5
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [1, 1]).new_state

		# Charger strikes first with [1,1,1,1] → 0 wounds. Defender counters [5,5,1,1]
		# → 2 unsaved → charger current_wounds=2 (W=5, still alive). Def wins bout 1.
		# Charger is the loser → charger retreats.
		var dice = [1, 1, 1, 1, 5, 5, 1, 1]
		var params = {"target_id": state.units[1].id, "panic_die": 6, "fearless_die": 1}
		var result = GameEngine.execute_order(state, params, dice)

		# Charger moved adjacent to (x=10, y=10 → x=10 target at 11), charge_dest x=10 wait...
		# Targeting.find_adjacent_cell picks nearest adjacent cell to target. Target at (11,10), charger
		# approaching from (10,10) → adjacent cell (10,10) itself is distance 1 from target. Fine.
		# After losing: charger retreats 2×(panic_tokens_after_melee=1) = 2 cells away from defender.
		# Defender at (11,10), charger now at charge_dest.x. Retreat direction = -x.
		# So final charger x < charge_dest.x.
		var charger = result.new_state.units[0]
		return (result.is_success()
			and not charger.is_dead
			and charger.panic_tokens == 1  # +1 post-melee
			and charger.x < 11  # retreated away from defender
			and not result.new_state.units[1].is_dead
			and result.new_state.units[1].x == 11  # defender held
			and result.new_state.units[1].y == 10)
	)


func _test_shooting_engagements() -> void:
	print("\n[Test Suite: Shooting Engagements]")

	# --- Direct Combat.resolve_shooting_engagement tests ---

	_test("engagement: return fire fires when target in range with weapon", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 15; dfn.y = 10  # within 18
		# Attacker [5,1] hits + wounds (I5+, V5). Defender [5,1] same.
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [5, 1, 5, 1], 0)
		return (combat["error"] == ""
			and combat["return_fire_fired"]
			and combat["att_hits"] == 1 and combat["att_wounds"] == 1
			and combat["def_hits"] == 1 and combat["def_wounds"] == 1
			and combat["tie"]
			and combat["winner_id"] == "" and combat["loser_id"] == "")
	)

	_test("engagement: powder smoke on target blocks return fire", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 15; dfn.y = 10
		dfn.has_powder_smoke = true
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [5, 1], 0)
		return (combat["error"] == ""
			and not combat["return_fire_fired"]
			and combat["att_wounds"] == 1
			and combat["def_wounds"] == 0
			and combat["winner_id"] == "atk"
			and combat["loser_id"] == "dfn")
	)

	_test("engagement: target out of own range cannot return fire", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		# Defender wr=4 but attacker 10 cells away → out of range for return.
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 4, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 20; dfn.y = 10
		atk.base_stats.weapon_range = 18
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [5, 1], 0)
		return (combat["error"] == ""
			and not combat["return_fire_fired"]
			and combat["winner_id"] == "atk")
	)

	_test("engagement: melee-only target (wr=0) cannot return fire", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Brutes", "infantry", 6, 2, 5, 2, 5, 0, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 12; dfn.y = 10
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [5, 1], 0)
		return combat["error"] == "" and not combat["return_fire_fired"]
	)

	_test("engagement: casualties do not suppress return fire", func():
		# Multi-model defender losing a model pre-return still returns fire with
		# pre-engagement model count. Attacker 4 models vs Defender 3 models.
		var atk = _mock_unit("atk", 1, "Atk", "infantry", 6, 1, 5, 1, 5, 18, 4)
		var dfn = _mock_unit("dfn", 2, "Dfn", "infantry", 6, 1, 5, 1, 5, 18, 3)
		atk.x = 10; atk.y = 10
		dfn.x = 15; dfn.y = 10
		# Attacker 4 shots × 2 dice = 8. All hit+wound → 4 unsaved → dfn has 1 model left.
		# Defender return fire rolled from 3-model state = 6 dice — casualties
		# should not reduce the pool.
		var dice = [5, 5, 5, 5, 1, 1, 1, 1,   # attacker 4 hits, 4 wounds
					5, 5, 5, 1, 1, 1]          # defender 3 hits (I5+), 3 wounds
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, dice, 0)
		return (combat["error"] == ""
			and combat["return_fire_fired"]
			and combat["att_hits"] == 4 and combat["att_wounds"] == 4
			and combat["def_hits"] == 3 and combat["def_wounds"] == 3
			and combat["dice_used"] == 14
			# Dfn had 3 models, took 4 wounds → 3 models dead → is_dead.
			and dfn.is_dead
			# Atk 4 models W=1 took 3 wounds → 3 models dead, 1 survives.
			and atk.model_count == 1)
	)

	_test("engagement: attacker wins and defender becomes loser", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 15; dfn.y = 10
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [5, 1, 1, 1], 0)
		return (combat["error"] == ""
			and combat["winner_id"] == "atk"
			and combat["loser_id"] == "dfn"
			and not combat["tie"])
	)

	_test("engagement: defender wins and attacker becomes loser", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 15; dfn.y = 10
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [1, 1, 5, 1], 0)
		return (combat["error"] == ""
			and combat["winner_id"] == "dfn"
			and combat["loser_id"] == "atk"
			and not combat["tie"])
	)

	_test("engagement: both whiff → no winner, no loser", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		atk.x = 10; atk.y = 10
		dfn.x = 15; dfn.y = 10
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [1, 1, 1, 1], 0)
		return (combat["error"] == ""
			and combat["tie"]
			and combat["winner_id"] == "" and combat["loser_id"] == "")
	)

	_test("engagement: rejects when one side already dead", func():
		var atk = _mock_unit("atk", 1, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		var dfn = _mock_unit("dfn", 2, "Toff", "snob", 6, 2, 5, 2, 5, 18, 1)
		dfn.is_dead = true
		var combat = GameEngine.Combat.resolve_shooting_engagement(atk, dfn, [], 0)
		return combat["error"] != ""
	)

	# --- volley_fire integration ---

	_test("volley_fire: loser retreats after engagement", func():
		var state = _mock_orders_state_ranged()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Attacker hits+wounds, defender whiffs → atk wins, dfn retreats.
		var params = {"target_id": state.units[1].id, "retreat_die": 2}
		var result = GameEngine.execute_order(state, params, [4, 1, 1, 1])

		# Defender had 0 panic tokens, got hit → +1 panic. Retreat distance = 2 + 2*1 = 4.
		# Defender at (20,15), attacker at (10,15), retreat +X → (24,15).
		return (result.is_success()
			and result.new_state.units[1].panic_tokens == 1
			and result.new_state.units[1].x == 24
			and result.new_state.units[1].y == 15)
	)

	_test("volley_fire: tied engagement → no retreat", func():
		var state = _mock_orders_state_ranged()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Both hit+wound (4 with -1 bonus hits for atk, 5 hits for dfn at I5). Tie 1-1.
		var params = {"target_id": state.units[1].id, "retreat_die": 3}
		var result = GameEngine.execute_order(state, params, [4, 1, 5, 1])

		# Neither retreats; both still at original positions.
		return (result.is_success()
			and result.new_state.units[0].x == 10 and result.new_state.units[0].y == 15
			and result.new_state.units[1].x == 20 and result.new_state.units[1].y == 15
			and result.new_state.units[0].current_wounds == 1
			and result.new_state.units[1].current_wounds == 1)
	)

	_test("volley_fire: target killed outright still returned fire pre-death", func():
		var state = _mock_orders_state_ranged()
		# Give attacker enough shots to kill Toff target (W=2) in one engagement.
		state.units[0].model_count = 2  # 2 shots per engagement
		state.units[0].max_models = 2
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Attacker 2 shots, both hit+wound → dfn W=2, dies. Defender pre-engagement
		# count was 1 → returns fire with 2 dice.
		var params = {"target_id": state.units[1].id, "retreat_die": 1}
		var result = GameEngine.execute_order(state, params, [5, 5, 1, 1, 5, 1])

		# Attacker took 1 wound from return fire; defender dead.
		return (result.is_success()
			and result.new_state.units[1].is_dead
			and result.new_state.units[0].current_wounds == 1)
	)

	# --- move_and_shoot integration ---

	_test("move_and_shoot: return fire uses shooter's post-move position", func():
		var state = _mock_orders_state_ranged()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[0].base_stats.weapon_range = 18
		state.units[1].x = 22; state.units[1].y = 15
		state.units[1].base_stats.weapon_range = 10  # pre-move distance 12 > 10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# Attacker moves to (14,15) → distance 8 ≤ 10 → defender can return fire.
		var params = {"x": 14, "y": 15, "target_id": state.units[1].id, "retreat_die": 1}
		var result = GameEngine.execute_order(state, params, [5, 1, 5, 1])

		# Both hit+wound → tie, no retreat. Confirms return fire measured from (14,15).
		return (result.is_success()
			and result.new_state.units[0].x == 14
			and result.new_state.units[0].current_wounds == 1
			and result.new_state.units[1].current_wounds == 1)
	)


func _test_line_of_sight() -> void:
	print("\n[Test Suite: Line of Sight + Closest Target]")

	_test("LoS: clear line between two units passes", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		# No blockers between them
		state.units[2].x = 5; state.units[2].y = 5  # out of the way
		state.units[3].x = 30; state.units[3].y = 5  # out of the way
		return GameEngine.Targeting.has_line_of_sight(state, 10, 15, 20, 15)
	)

	_test("LoS: Follower unit on the line blocks", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		# Place a Follower directly between them
		state.units[2].x = 15; state.units[2].y = 15
		return not GameEngine.Targeting.has_line_of_sight(state, 10, 15, 20, 15)
	)

	_test("LoS: Snob on the line does NOT block", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		# Place the enemy Snob (u1) on the line — Snobs never block LoS.
		# Create a separate target behind the Snob.
		state.units[1].x = 15; state.units[1].y = 15  # Snob in the middle
		state.units[3].x = 20; state.units[3].y = 15  # Follower as actual target
		# LoS from u0 to u3 should pass — u1 (Snob) doesn't block.
		state.units[2].x = 5; state.units[2].y = 5  # out of the way
		return GameEngine.Targeting.has_line_of_sight(state, 10, 15, 20, 15)
	)

	_test("LoS: dead unit on the line does NOT block", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 15
		state.units[1].x = 20; state.units[1].y = 15
		state.units[2].x = 15; state.units[2].y = 15  # Follower in the way
		state.units[2].is_dead = true  # but dead
		state.units[3].x = 30; state.units[3].y = 5
		return GameEngine.Targeting.has_line_of_sight(state, 10, 15, 20, 15)
	)

	_test("LoS: endpoints are excluded from blocker check", func():
		var state = _mock_orders_state()
		# Both shooter and target are Followers at endpoints — they shouldn't block themselves.
		state.units[2].x = 10; state.units[2].y = 15
		state.units[3].x = 20; state.units[3].y = 15
		state.units[0].x = 5; state.units[0].y = 5
		state.units[1].x = 30; state.units[1].y = 5
		return GameEngine.Targeting.has_line_of_sight(state, 10, 15, 20, 15)
	)

	_test("LoS: diagonal line blocked by unit on the path", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 16; state.units[1].y = 16
		# Place blocker at (13,13) — on the diagonal line
		state.units[2].x = 13; state.units[2].y = 13
		state.units[3].x = 30; state.units[3].y = 5
		return not GameEngine.Targeting.has_line_of_sight(state, 10, 10, 16, 16)
	)

	_test("closest-target: reject non-closest enemy", func():
		var state = _mock_orders_state_ranged()
		# u0 at (10,15), u1 (enemy Snob) at (20,15) dist=10.
		# Place u3 (enemy Follower) closer at (14,17) dist≈4.5. Off-axis so no LoS block.
		state.units[3].x = 14; state.units[3].y = 17
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Try to target u1 (farther) instead of u3 (closer) — should be rejected.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [6, 1])
		return not result.is_success() and "closest" in result.error
	)

	_test("closest-target: tied-closest both legal", func():
		var state = _mock_orders_state_ranged()
		# u0 at (10,15). Place both enemies equidistant, neither blocking LoS to the other.
		state.units[1].x = 20; state.units[1].y = 15  # dist=10
		state.units[3].x = 10; state.units[3].y = 25  # dist=10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Both should be valid — provide enough dice for engagement (atk + return fire)
		var r1 = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [6, 1, 1, 1])
		# Reset state for second attempt
		state = _mock_orders_state_ranged()
		state.units[1].x = 20; state.units[1].y = 15
		state.units[3].x = 10; state.units[3].y = 25
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state
		var r2 = GameEngine.execute_order(state, {"target_id": state.units[3].id}, [6, 1, 1, 1])

		return r1.is_success() and r2.is_success()
	)

	_test("closest-target: Sharpshooters bypass restriction", func():
		var state = _mock_orders_state_ranged()
		# Make u0 a Sharpshooter (Chaff)
		state.units[0].special_rules = ["sharpshooters"] as Array[String]
		# u3 closer and off-axis so it doesn't block LoS to u1.
		state.units[3].x = 14; state.units[3].y = 17
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Target u1 (farther) — should succeed for Sharpshooters. Enough dice for engagement.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [6, 1, 1, 1])
		return result.is_success()
	)

	_test("volley_fire: LoS blocked = fizzle succeeds", func():
		var state = _mock_orders_state_ranged()
		# Place blocker between shooter and all enemies
		state.units[2].x = 15; state.units[2].y = 15  # blocks LoS to u1 at (20,15)
		state.units[3].x = 15; state.units[3].y = 16  # blocks LoS diagonally too
		# Actually need to make sure NO enemy has LoS. u1 at (20,15) blocked by u2 at (15,15).
		# u3 at (15,16) is a friendly unit, won't be targeted. Need to check u1 only.
		# u1 is the only enemy in range. u2 blocks LoS to u1.
		state.units[3].x = 40; state.units[3].y = 2  # move enemy far away and out of range
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"fizzle": true}, [])
		return result.is_success()
	)

	_test("charge: LoS required to target", func():
		var state = _mock_orders_state()
		state.units[0].x = 10; state.units[0].y = 10
		state.units[1].x = 20; state.units[1].y = 10
		# Place Follower blocker between charger and target
		state.units[2].x = 15; state.units[2].y = 10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "charge", 3, [6, 6]).new_state

		var params = {"target_id": state.units[1].id, "panic_die": 1, "fearless_die": 1}
		var result = GameEngine.execute_order(state, params, [5, 5, 1, 1])
		return not result.is_success() and "line of sight" in result.error
	)


func _test_advance_flow() -> void:
	print("\n[Test Suite: Advance Flow]")

	_test("advance: after order, switches to other seat if they have Snobs", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"x": 10, "y": 24}, [])

		return (result.is_success()
			and result.new_state.active_seat == 2
			and result.new_state.order_phase == "snob_select")
	)

	_test("advance: marks both ordering Snob and ordered unit", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[2].id, "march", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"x": 12, "y": 24}, [])

		return (result.is_success()
			and result.new_state.units[0].has_ordered  # Snob
			and result.new_state.units[2].has_ordered)  # Follower
	)

	_test("advance: after all Snobs ordered, enters follower_self_order", func():
		var state = _mock_orders_state()
		# Seat 1 Snob self-orders
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [3, 3]).new_state
		state = GameEngine.execute_order(state, {"x": 10, "y": 24}, []).new_state

		# Seat 2 Snob self-orders
		state = GameEngine.select_snob(state, state.units[1].id).new_state
		state = GameEngine.declare_order(state, state.units[1].id, "march", 3, [3, 3]).new_state
		state = GameEngine.execute_order(state, {"x": 10, "y": 8}, []).new_state

		return state.order_phase == "follower_self_order"
	)

	_test("advance: end of round clears has_ordered and advances round", func():
		var state = _mock_orders_state_follower_phase()
		state.current_round = 1
		# Mark everyone ordered except u2 (seat 1 Fodder)
		state.units[3].has_ordered = true  # seat 2 Fodder already ordered
		state.active_seat = 1

		state = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 3]).new_state
		var result = GameEngine.execute_order(state, {"x": 12, "y": 24}, [])

		return (result.is_success()
			and result.new_state.current_round == 2
			and not result.new_state.units[0].has_ordered  # flags cleared
			and result.new_state.order_phase == "snob_select")
	)

	_test("advance: game finishes after max_rounds", func():
		var state = _mock_orders_state_follower_phase()
		state.current_round = 4
		state.max_rounds = 4
		state.units[3].has_ordered = true
		state.active_seat = 1

		state = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 3]).new_state
		var result = GameEngine.execute_order(state, {"x": 12, "y": 24}, [])

		return result.is_success() and result.new_state.phase == "finished"
	)

	_test("advance: powder smoke cleared at round end", func():
		var state = _mock_orders_state_follower_phase()
		state.current_round = 1
		state.units[3].has_ordered = true
		state.units[0].has_powder_smoke = true
		state.active_seat = 1

		state = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 3]).new_state
		var result = GameEngine.execute_order(state, {"x": 12, "y": 24}, [])

		return result.is_success() and not result.new_state.units[0].has_powder_smoke
	)


func _test_victory_conditions() -> void:
	print("\n[Test Suite: Victory Conditions]")

	_test("Victory when all enemy units dead", func():
		var state = _mock_orders_state()
		for unit in state.units:
			if unit.owner_seat == 2:
				unit.is_dead = true

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 1
	)

	_test("Headless Chicken: all Snobs dead = instant loss", func():
		var state = _mock_orders_state()
		state.units[0].is_dead = true  # kill seat 1 Snob

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 2 and "Snobs" in victory["reason"]
	)

	_test("Solo mode: no victory when only one side has units", func():
		var state = Types.GameState.new()
		state.phase = "orders"
		state.active_seat = 1
		state.units.append(_mock_unit("u0", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1))
		state.units[0].x = 10; state.units[0].y = 10

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 0
	)

	_test("No winner when both have living units and snobs", func():
		var state = _mock_orders_state()

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 0 and victory["reason"] == ""
	)

	_test("Round-limit: seat with more captured objectives wins", func():
		var state = _mock_orders_state()
		state.current_round = 5
		state.max_rounds = 4
		state.objectives = _mock_objectives([[1, 2], [1, 0], [2, 0]])

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 1 and "2 objective" in victory["reason"]
	)

	_test("Round-limit: equal objective counts = draw (no model tiebreak)", func():
		var state = _mock_orders_state()
		state.current_round = 5
		state.max_rounds = 4
		# Equal objective counts; seat 2 has extra models → still a draw per v17.
		state.objectives = _mock_objectives([[1, 0], [2, 0]])
		for unit in state.units:
			if unit.owner_seat == 2 and not unit.is_snob():
				unit.model_count += 5
				break

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 0 and "Draw" in victory["reason"]
	)

	_test("Round-limit: no captured objectives = 0–0 draw", func():
		var state = _mock_orders_state()
		state.current_round = 5
		state.max_rounds = 4
		state.objectives = _mock_objectives([[0, 0], [0, 0]])

		var victory = Objectives.check_victory(state)
		return victory["winner"] == 0 and "Draw" in victory["reason"]
	)


# =============================================================================
# OBJECTIVE CAPTURE / BLOCKING
# =============================================================================

func _test_objectives() -> void:
	print("")
	print("[Test Suite: Objectives]")

	_test("Follower adjacent to uncaptured objective captures it", func():
		var state = _mock_orders_state()
		state.objectives = _mock_objectives_at([[20, 15]])
		state.units[2].x = 20; state.units[2].y = 16  # seat 1 Follower
		GameEngine.Objectives.resolve_objective_captures(state)
		return state.objectives[0].captured_by == 1
	)

	_test("Snob adjacent to objective does NOT capture", func():
		var state = _mock_orders_state()
		state.objectives = _mock_objectives_at([[10, 29]])
		# Seat 1 Snob at (10, 30) is already adjacent to (10, 29).
		GameEngine.Objectives.resolve_objective_captures(state)
		return state.objectives[0].captured_by == 0
	)

	_test("Contested objective (both seats adjacent) becomes uncaptured", func():
		var state = _mock_orders_state()
		state.objectives = _mock_objectives_at([[15, 15]])
		state.objectives[0].captured_by = 1  # Pre-existing control
		state.units[2].x = 15; state.units[2].y = 14  # seat 1 Follower
		state.units[3].x = 15; state.units[3].y = 16  # seat 2 Follower
		GameEngine.Objectives.resolve_objective_captures(state)
		return state.objectives[0].captured_by == 0
	)

	_test("Captured objective stays captured when the Follower leaves", func():
		var state = _mock_orders_state()
		state.objectives = _mock_objectives_at([[20, 15]])
		state.objectives[0].captured_by = 2
		# No followers adjacent at all.
		state.units[2].x = 0; state.units[2].y = 0
		state.units[3].x = 0; state.units[3].y = 31
		GameEngine.Objectives.resolve_objective_captures(state)
		return state.objectives[0].captured_by == 2
	)

	_test("Enemy Follower entering a controlled objective flips capture", func():
		var state = _mock_orders_state()
		state.objectives = _mock_objectives_at([[20, 15]])
		state.objectives[0].captured_by = 1
		# Seat 2 Follower adjacent, seat 1 Follower far away.
		state.units[2].x = 0; state.units[2].y = 0
		state.units[3].x = 20; state.units[3].y = 14
		GameEngine.Objectives.resolve_objective_captures(state)
		return state.objectives[0].captured_by == 2
	)

	_test("March onto an objective cell is rejected", func():
		var state = _mock_orders_state()
		state.objectives = _mock_objectives_at([[20, 15]])
		var follower = state.units[2]
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, follower.id, "march", 4, [3, 3]).new_state
		var res = GameEngine.execute_order(state, {"x": 20, "y": 15}, [])
		return not res.is_success() and "objective" in res.error
	)


# =============================================================================
# MOCK STATE GENERATORS
# =============================================================================

func _mock_unit(id: String, seat: int, unit_type: String, category: String, m: int, a: int, i: int, w: int, v: int, wr: int, models: int) -> Types.UnitState:
	var stats = Types.Stats.new(m, a, i, w, v, wr)
	var rules: Array[String] = []
	return Types.UnitState.new(id, seat, unit_type, category, models, models, stats, "black_powder", rules)


## Build an objectives list from [captured_by, placeholder] pairs. The second
## element is unused — tests only care about captured_by — but the shape
## keeps each entry visually distinct. Positions are synthetic (i*3, 10).
func _mock_objectives(entries: Array) -> Array[Types.Objective]:
	var out: Array[Types.Objective] = []
	for i in range(entries.size()):
		var entry = entries[i]
		out.append(Types.Objective.new("obj_%d" % i, i * 3, 10, entry[0]))
	return out


## Objectives placed at explicit [x, y] coords, all starting uncaptured.
func _mock_objectives_at(positions: Array) -> Array[Types.Objective]:
	var out: Array[Types.Objective] = []
	for i in range(positions.size()):
		var p = positions[i]
		out.append(Types.Objective.new("obj_%d" % i, p[0], p[1], 0))
	return out


func _mock_game_state() -> Types.GameState:
	var state = Types.GameState.new()
	state.phase = "placement"
	state.active_seat = 1
	state.initiative_seat = 1

	# 1 Snob + 1 Follower per seat
	var u0 = _mock_unit("u0", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
	var u1 = _mock_unit("u1", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1)
	var u2 = _mock_unit("u2", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)
	var u3 = _mock_unit("u3", 2, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12)

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


## Orders phase, snob_select sub-phase, seat 1 active.
func _mock_orders_state() -> Types.GameState:
	var state = _mock_game_state_both_placed()
	state.phase = "orders"
	state.order_phase = "snob_select"
	state.active_seat = 1
	return state


## Orders state configured for ranged combat — attacker and target in range.
func _mock_orders_state_ranged() -> Types.GameState:
	var state = _mock_orders_state()
	state.units[0].x = 10; state.units[0].y = 15
	state.units[1].x = 20; state.units[1].y = 15
	state.units[0].base_stats.weapon_range = 18
	state.units[1].base_stats.weapon_range = 18
	return state


## Orders state in follower_self_order phase — all Snobs already ordered.
func _mock_orders_state_follower_phase() -> Types.GameState:
	var state = _mock_orders_state()
	state.order_phase = "follower_self_order"
	state.units[0].has_ordered = true
	state.units[1].has_ordered = true
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
