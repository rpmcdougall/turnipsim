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
	_test_snob_selection()
	_test_declare_order()
	_test_declare_self_order()
	_test_execute_volley_fire()
	_test_execute_move_and_shoot()
	_test_execute_march()
	_test_execute_charge()
	_test_advance_flow()
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

		return (result.success
			and result.new_state.phase == "orders"
			and result.new_state.order_phase == "snob_select")
	)


func _test_snob_selection() -> void:
	print("\n[Test Suite: Snob Selection]")

	_test("select_snob: valid Toff transitions to order_declare", func():
		var state = _mock_orders_state()
		var result = GameEngine.select_snob(state, state.units[0].id)

		return (result.success
			and result.new_state.order_phase == "order_declare"
			and result.new_state.current_snob_id == state.units[0].id)
	)

	_test("select_snob: reject non-Snob", func():
		var state = _mock_orders_state()
		var result = GameEngine.select_snob(state, state.units[2].id)

		return not result.success and "not a Snob" in result.error
	)

	_test("select_snob: reject enemy Snob", func():
		var state = _mock_orders_state()
		var result = GameEngine.select_snob(state, state.units[1].id)

		return not result.success and "Not your Snob" in result.error
	)

	_test("select_snob: reject already-ordered Snob", func():
		var state = _mock_orders_state()
		state.units[0].has_ordered = true

		var result = GameEngine.select_snob(state, state.units[0].id)

		return not result.success and "already ordered" in result.error
	)

	_test("select_snob: reject outside snob_select phase", func():
		var state = _mock_orders_state()
		state.order_phase = "order_declare"

		var result = GameEngine.select_snob(state, state.units[0].id)

		return not result.success and "snob selection" in result.error
	)


func _test_declare_order() -> void:
	print("\n[Test Suite: Declare Order]")

	_test("declare_order: valid follower in command range", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "march", 3, [3, 4])

		return (result.success
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

		return not result.success and "command range" in result.error
	)

	_test("declare_order: Snob self-order bypasses blunder check", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		# blunder_die=1 normally blunders, but self-order never blunders
		var result = GameEngine.declare_order(state, state.units[0].id, "march", 1, [3, 3])

		return (result.success
			and not result.new_state.current_order_blundered
			and result.new_state.units[0].panic_tokens == 0)
	)

	_test("declare_order: blunder_die==1 adds panic + halves march bonus", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "march", 1, [4, 5])

		return (result.success
			and result.new_state.current_order_blundered
			and result.new_state.units[2].panic_tokens == 1
			and result.new_state.current_order_move_bonus == 4)  # only first die
	)

	_test("declare_order: reject volley_fire without ranged weapon", func():
		var state = _mock_orders_state()
		state.units[2].base_stats.weapon_range = 0
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "volley_fire", 3, [3, 3])

		return not result.success and "ranged weapon" in result.error
	)

	_test("declare_order: reject volley_fire with powder smoke", func():
		var state = _mock_orders_state()
		state.units[2].base_stats.weapon_range = 12
		state.units[2].has_powder_smoke = true
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "volley_fire", 3, [3, 3])

		return not result.success and "powder smoke" in result.error
	)

	_test("declare_order: reject ordering another Snob", func():
		var state = _mock_orders_state()
		# Add a second seat-1 Snob (Toady) within command range
		var u4 = _mock_unit("u4", 1, "Toady", "snob", 6, 2, 5, 2, 5, 0, 1)
		u4.x = 11; u4.y = 30
		state.units.append(u4)
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, u4.id, "march", 3, [3, 3])

		return not result.success and "another Snob" in result.error
	)

	_test("declare_order: reject invalid order type", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state

		var result = GameEngine.declare_order(state, state.units[2].id, "teleport", 3, [3, 3])

		return not result.success and "Invalid order type" in result.error
	)


func _test_declare_self_order() -> void:
	print("\n[Test Suite: Declare Self-Order (Follower Phase)]")

	_test("declare_self_order: valid follower self-orders", func():
		var state = _mock_orders_state_follower_phase()
		var result = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 4])

		return (result.success
			and result.new_state.order_phase == "order_execute"
			and result.new_state.current_order_unit_id == state.units[2].id
			and result.new_state.current_snob_id == ""
			and result.new_state.current_order_move_bonus == 7)
	)

	_test("declare_self_order: blunder_die==1 always blunders", func():
		var state = _mock_orders_state_follower_phase()
		var result = GameEngine.declare_self_order(state, state.units[2].id, "march", 1, [4, 5])

		return (result.success
			and result.new_state.current_order_blundered
			and result.new_state.units[2].panic_tokens == 1
			and result.new_state.current_order_move_bonus == 4)
	)

	_test("declare_self_order: reject Snob", func():
		var state = _mock_orders_state_follower_phase()
		state.units[0].has_ordered = false  # un-order the Snob to test rejection

		var result = GameEngine.declare_self_order(state, state.units[0].id, "march", 3, [3, 3])

		return not result.success and "Snobs don't self-order" in result.error
	)

	_test("declare_self_order: reject outside follower_self_order phase", func():
		var state = _mock_orders_state()
		# phase is snob_select, not follower_self_order
		var result = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 3])

		return not result.success and "follower self-order" in result.error
	)


func _test_execute_volley_fire() -> void:
	print("\n[Test Suite: Execute Volley Fire]")

	_test("volley_fire: unblundered grants -1 Inaccuracy", func():
		var state = _mock_orders_state_ranged()
		# Self-order from Snob 0: weapon_range=18, target at distance 10
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Toff I=5, -1 bonus → needs 4+. Target V=5, W=2.
		# Die 4 hits (4>=4), die 1 fails save → 1 wound.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [4, 1])

		return result.success and result.new_state.units[1].current_wounds == 1
	)

	_test("volley_fire: unblundered roll that barely misses without bonus still hits", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Die 4 hits with -1 bonus (base I=5 would have missed). Die 6 saves V=5.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [4, 6])

		return result.success and result.new_state.units[1].current_wounds == 0  # saved
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
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [5, 1])

		return result.success and result.new_state.units[1].current_wounds == 0
	)

	_test("volley_fire: black_powder grants powder smoke after firing", func():
		var state = _mock_orders_state_ranged()
		state.units[0].equipment = "black_powder"
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [3, 1])

		return result.success and result.new_state.units[0].has_powder_smoke
	)

	_test("volley_fire: hit grants target a panic token", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "volley_fire", 3, [3, 3]).new_state

		# Die 4 hits (I4+ with bonus), die 6 saves. Hit → panic token even if saved.
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, [4, 6])

		return result.success and result.new_state.units[1].panic_tokens == 1
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
		var dice = [5, 5, 5, 5, 1, 1, 1, 1]
		var result = GameEngine.execute_order(state, {"target_id": state.units[1].id}, dice)

		return result.success and result.new_state.units[1].is_dead
	)


func _test_execute_move_and_shoot() -> void:
	print("\n[Test Suite: Execute Move and Shoot]")

	_test("move_and_shoot: moves then fires at new position", func():
		var state = _mock_orders_state_ranged()
		# Target u1 at (20,15). Move Snob from (10,15) to (12,15), still within 18.
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# After move, distance 8 ≤ 18. Toff I=5, no bonus → 5+. Die 5 hits. Die 1 wounds.
		var params = {"x": 12, "y": 15, "target_id": state.units[1].id}
		var result = GameEngine.execute_order(state, params, [5, 1])

		return (result.success
			and result.new_state.units[0].x == 12
			and result.new_state.units[1].current_wounds == 1)
	)

	_test("move_and_shoot: move without target is legal (no target_id)", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# Just move, no shot (no target_id)
		var result = GameEngine.execute_order(state, {"x": 13, "y": 15}, [])

		return (result.success
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

		return (result.success
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

		return not result.success and "movement range" in result.error
	)

	_test("move_and_shoot: reject move beyond M", func():
		var state = _mock_orders_state_ranged()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "move_and_shoot", 3, [3, 3]).new_state

		# Toff M=6, from (10,15). (17,15) is distance 7 > 6 and unoccupied.
		var result = GameEngine.execute_order(state, {"x": 17, "y": 15}, [])

		return not result.success and "movement range" in result.error
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

		return (result.success
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

		return not result.success and "march range" in result.error
	)

	_test("march: reject out-of-range destination", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [1, 1]).new_state

		# Toff M=6, bonus 2, total 8. Distance 20 > 8.
		var result = GameEngine.execute_order(state, {"x": 10, "y": 10}, [])

		return not result.success and "march range" in result.error
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

		return (result.success
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

		return not result.success and "charge range" in result.error
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

		return result.success and result.new_state.units[1].is_dead
	)


func _test_advance_flow() -> void:
	print("\n[Test Suite: Advance Flow]")

	_test("advance: after order, switches to other seat if they have Snobs", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[0].id, "march", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"x": 10, "y": 24}, [])

		return (result.success
			and result.new_state.active_seat == 2
			and result.new_state.order_phase == "snob_select")
	)

	_test("advance: marks both ordering Snob and ordered unit", func():
		var state = _mock_orders_state()
		state = GameEngine.select_snob(state, state.units[0].id).new_state
		state = GameEngine.declare_order(state, state.units[2].id, "march", 3, [3, 3]).new_state

		var result = GameEngine.execute_order(state, {"x": 12, "y": 24}, [])

		return (result.success
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

		return (result.success
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

		return result.success and result.new_state.phase == "finished"
	)

	_test("advance: powder smoke cleared at round end", func():
		var state = _mock_orders_state_follower_phase()
		state.current_round = 1
		state.units[3].has_ordered = true
		state.units[0].has_powder_smoke = true
		state.active_seat = 1

		state = GameEngine.declare_self_order(state, state.units[2].id, "march", 3, [3, 3]).new_state
		var result = GameEngine.execute_order(state, {"x": 12, "y": 24}, [])

		return result.success and not result.new_state.units[0].has_powder_smoke
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
		state.units[0].is_dead = true  # kill seat 1 Snob

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 2 and "Snobs" in victory["reason"]
	)

	_test("Solo mode: no victory when only one side has units", func():
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

	_test("Max-rounds tiebreak: more surviving units wins", func():
		var state = _mock_orders_state()
		state.current_round = 5
		state.max_rounds = 4
		# Kill one seat 2 non-snob unit so seat 1 has more alive
		for unit in state.units:
			if unit.owner_seat == 2 and not unit.is_snob():
				unit.is_dead = true
				break

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 1 and "Time expired" in victory["reason"]
	)

	_test("Max-rounds tiebreak: equal units, more models wins", func():
		var state = _mock_orders_state()
		state.current_round = 5
		state.max_rounds = 4
		# Both sides have same unit count alive; give seat 2 an extra model
		for unit in state.units:
			if unit.owner_seat == 2 and not unit.is_snob():
				unit.model_count += 5
				break

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 2 and "more models" in victory["reason"]
	)

	_test("Max-rounds tiebreak: fully tied = draw", func():
		var state = _mock_orders_state()
		state.current_round = 5
		state.max_rounds = 4

		var victory = GameEngine.check_victory(state)
		return victory["winner"] == 0 and "Draw" in victory["reason"]
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
