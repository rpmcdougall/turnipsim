extends SceneTree
## Headless test runner for game logic.
##
## Run with: godot --headless -s tests/test_runner.gd

const Targeting = preload("res://game/targeting.gd")

var _tests_passed: int = 0
var _tests_failed: int = 0


func _init() -> void:
	print("============================================================")
	print("Running Game Logic Tests")
	print("============================================================")

	_test_types()
	_test_ruleset_loader()
	_test_roster_validation()
	_test_targeting()

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


## Test Types classes (Stats, Equipment, UnitDef, Roster, UnitState)
func _test_types() -> void:
	print("\n[Test Suite: Types]")

	_test("Stats creation with v17 characteristics", func():
		var stats = Types.Stats.new(6, 2, 5, 2, 5, 6)
		return stats.movement == 6 and stats.attacks == 2 and stats.inaccuracy == 5 and stats.wounds == 2 and stats.vulnerability == 5 and stats.weapon_range == 6
	)

	_test("Stats to_dict and from_dict", func():
		var stats = Types.Stats.new(12, 4, 5, 2, 5, 18)
		var dict = stats.to_dict()
		var restored = Types.Stats.from_dict(dict)
		return restored.movement == 12 and restored.attacks == 4 and restored.weapon_range == 18
	)

	_test("Equipment creation", func():
		var equip = Types.Equipment.new("Black Powder Weapons", "black_powder", "Muskets etc.")
		return equip.name == "Black Powder Weapons" and equip.type == "black_powder"
	)

	_test("Roster creation and serialization", func():
		var follower = Types.RosterUnit.new("Fodder", "black_powder")
		var snob = Types.RosterSnob.new("Toff", "pistols_and_sabres", [follower])
		var roster = Types.Roster.new("none", [snob])

		var dict = roster.to_dict()
		var restored = Types.Roster.from_dict(dict)
		return restored.cult == "none" and restored.snobs.size() == 1 and restored.snobs[0].followers.size() == 1
	)

	_test("Roster get_unit_count", func():
		var f1 = Types.RosterUnit.new("Fodder", "black_powder")
		var f2 = Types.RosterUnit.new("Brutes", "close_combat")
		var f3 = Types.RosterUnit.new("Chaff", "black_powder")
		var toff = Types.RosterSnob.new("Toff", "pistols_and_sabres", [f1, f2])
		var toady = Types.RosterSnob.new("Toady", "pistols_and_sabres", [f3])
		var roster = Types.Roster.new("none", [toff, toady])

		return roster.get_unit_count() == 5 and roster.get_snob_count() == 2
	)

	_test("UnitState serialization roundtrip", func():
		var stats = Types.Stats.new(6, 1, 6, 1, 6, 18)
		var rules: Array[String] = ["safety_in_numbers"]
		var unit = Types.UnitState.new("u1", 1, "Fodder", "infantry", 12, 12, stats, "black_powder", rules)

		var dict = unit.to_dict()
		var restored = Types.UnitState.from_dict(dict)
		return restored.id == "u1" and restored.unit_type == "Fodder" and restored.model_count == 12 and restored.special_rules.size() == 1
	)

	_test("UnitState helper methods", func():
		var snob_stats = Types.Stats.new(6, 2, 5, 2, 5, 6)
		var snob = Types.UnitState.new("s1", 1, "Toff", "snob", 1, 1, snob_stats)
		return snob.is_snob() and snob.get_command_range() == 6
	)

	_test("UnitState/UnitDef do not alias special_rules across instances", func():
		var rules: Array[String] = ["fearless"]
		var stats = Types.Stats.new(6, 2, 5, 2, 5, 6)
		var u1 = Types.UnitState.new("a", 1, "Toff", "snob", 1, 1, stats, "", rules)
		var u2 = Types.UnitState.new("b", 1, "Toff", "snob", 1, 1, stats, "", rules)
		u1.special_rules.append("stubborn")
		var def1 = Types.UnitDef.new("Toff", "snob", 1, stats, rules)
		var def2 = Types.UnitDef.new("Toff", "snob", 1, stats, rules)
		def1.special_rules.append("dervish")
		return u2.special_rules.size() == 1 and def2.special_rules.size() == 1 and rules.size() == 1
	)

	_test("GameState with initiative and rounds", func():
		var gs = Types.GameState.new("ABCD", "placement", 1, 4, 1, 2)
		var dict = gs.to_dict()
		var restored = Types.GameState.from_dict(dict)
		return restored.initiative_seat == 2 and restored.max_rounds == 4
	)

	_test("GameState clone deep-copies action_log entries", func():
		var log: Array[Dictionary] = [{"type": "shoot", "shooter": "u1", "dice": [3, 4, 5]}]
		var units: Array[Types.UnitState] = []
		var src = Types.GameState.new("ABCD", "placement", 1, 4, 1, 1, units, log, 0)
		var clone = Types.GameState.from_dict(src.to_dict())
		clone.action_log[0]["shooter"] = "MUTATED"
		(clone.action_log[0]["dice"] as Array).append(6)
		return src.action_log[0]["shooter"] == "u1" and (src.action_log[0]["dice"] as Array).size() == 3
	)


## Test Ruleset loading and validation
func _test_ruleset_loader() -> void:
	print("\n[Test Suite: Ruleset]")

	_test("Load v17 ruleset", func():
		var ruleset = Ruleset.new()
		var error = ruleset.load_from_file("res://game/rulesets/v17.json")
		return error == "" and ruleset.is_loaded()
	)

	_test("v17 has expected unit types", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")
		return ruleset.unit_types.has("Toff") and ruleset.unit_types.has("Fodder") and ruleset.unit_types.has("Brutes") and ruleset.unit_types.has("StumpGun")
	)

	_test("v17 has equipment types", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")
		return ruleset.equipment_types.has("black_powder") and ruleset.equipment_types.has("close_combat") and ruleset.equipment_types.has("pistols_and_sabres")
	)

	_test("Get unit type returns correct stats", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")
		var fodder = ruleset.get_unit_type("Fodder")
		return fodder["base_stats"]["movement"] == 6 and fodder["base_stats"]["inaccuracy"] == 6 and fodder["model_count"] == 12
	)

	_test("Get follower types excludes snobs", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")
		var followers = ruleset.get_follower_types()
		return "Fodder" in followers and "Toff" not in followers and "Toady" not in followers
	)

	_test("Get allowed equipment for unit type", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")
		var equip = ruleset.get_allowed_equipment("Fodder")
		return "black_powder" in equip and "close_combat" in equip and "pistols_and_sabres" not in equip
	)

	_test("Reject non-existent file", func():
		var ruleset = Ruleset.new()
		var error = ruleset.load_from_file("res://game/rulesets/nonexistent.json")
		return error != "" and not ruleset.is_loaded()
	)


## Test roster validation against ruleset
func _test_roster_validation() -> void:
	print("\n[Test Suite: Roster Validation]")

	_test("Valid 3-snob roster passes", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")

		var roster = Types.Roster.new("none", [
			Types.RosterSnob.new("Toff", "pistols_and_sabres", [
				Types.RosterUnit.new("Fodder", "black_powder"),
				Types.RosterUnit.new("Brutes", "close_combat")
			]),
			Types.RosterSnob.new("Toady", "pistols_and_sabres", [
				Types.RosterUnit.new("Chaff", "black_powder")
			]),
			Types.RosterSnob.new("Toady", "pistols_and_sabres", [
				Types.RosterUnit.new("Fodder", "black_powder")
			])
		])

		return ruleset.validate_roster(roster) == ""
	)

	_test("Reject roster with no Toff", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")

		var roster = Types.Roster.new("none", [
			Types.RosterSnob.new("Toady", "pistols_and_sabres", [
				Types.RosterUnit.new("Fodder", "black_powder")
			])
		])

		return ruleset.validate_roster(roster) != ""
	)

	_test("Reject Toff with 3 followers", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")

		var roster = Types.Roster.new("none", [
			Types.RosterSnob.new("Toff", "pistols_and_sabres", [
				Types.RosterUnit.new("Fodder", "black_powder"),
				Types.RosterUnit.new("Brutes", "close_combat"),
				Types.RosterUnit.new("Chaff", "black_powder")
			]),
			Types.RosterSnob.new("Toady", "pistols_and_sabres", []),
			Types.RosterSnob.new("Toady", "pistols_and_sabres", [])
		])

		return ruleset.validate_roster(roster) != ""
	)

	_test("Reject invalid equipment for unit type", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/v17.json")

		var roster = Types.Roster.new("none", [
			Types.RosterSnob.new("Toff", "pistols_and_sabres", [
				Types.RosterUnit.new("Fodder", "pistols_and_sabres"),  # Invalid for Fodder
				Types.RosterUnit.new("Brutes", "close_combat")
			]),
			Types.RosterSnob.new("Toady", "pistols_and_sabres", [
				Types.RosterUnit.new("Chaff", "black_powder")
			]),
			Types.RosterSnob.new("Toady", "pistols_and_sabres", [
				Types.RosterUnit.new("Fodder", "black_powder")
			])
		])

		return ruleset.validate_roster(roster) != ""
	)


## Test Targeting line-of-sight semantics. Builds tiny game states with
## hand-placed units and asserts what blocks LoS.
func _test_targeting() -> void:
	print("\n[Test Suite: Targeting]")

	var _make_state := func(units: Array[Types.UnitState]) -> Types.GameState:
		return Types.GameState.new("ABCD", "battle", 1, 4, 1, 1, units, [], 0)

	# A Follower (non-Snob) standing on a cell does block LoS through that cell.
	# Stats with movement=6 placed at (5, 5).
	var stats = Types.Stats.new(6, 2, 5, 2, 5, 6)

	_test("LoS: open line, no blockers", func():
		var units: Array[Types.UnitState] = []
		var state = _make_state.call(units)
		return Targeting.has_line_of_sight(state, 0, 0, 5, 0)
	)

	_test("LoS: Follower on midline blocks", func():
		var blocker = Types.UnitState.new("b", 1, "Fodder", "follower", 1, 1, stats, "", [], 0, false, 0, 3, 0)
		var units: Array[Types.UnitState] = [blocker]
		var state = _make_state.call(units)
		return not Targeting.has_line_of_sight(state, 0, 0, 6, 0)
	)

	_test("LoS: Snob on midline does NOT block (v17 p.5)", func():
		var snob = Types.UnitState.new("s", 1, "Toff", "snob", 1, 1, stats, "", [], 0, false, 0, 3, 0)
		var units: Array[Types.UnitState] = [snob]
		var state = _make_state.call(units)
		return Targeting.has_line_of_sight(state, 0, 0, 6, 0)
	)

	_test("LoS: dead Follower does NOT block", func():
		var corpse = Types.UnitState.new("c", 1, "Fodder", "follower", 0, 1, stats, "", [], 0, false, 0, 3, 0, false, true, "")
		var units: Array[Types.UnitState] = [corpse]
		var state = _make_state.call(units)
		return Targeting.has_line_of_sight(state, 0, 0, 6, 0)
	)

	_test("LoS: blocker AT endpoint does not block its own visibility", func():
		# A unit standing at the to-cell is the target itself; it must not
		# block LoS to itself.
		var target = Types.UnitState.new("t", 2, "Fodder", "follower", 1, 1, stats, "", [], 0, false, 0, 6, 0)
		var units: Array[Types.UnitState] = [target]
		var state = _make_state.call(units)
		return Targeting.has_line_of_sight(state, 0, 0, 6, 0)
	)

	_test("LoS: blocker AT origin does not block (shooter at from)", func():
		var shooter = Types.UnitState.new("sh", 1, "Fodder", "follower", 1, 1, stats, "", [], 0, false, 0, 0, 0)
		var units: Array[Types.UnitState] = [shooter]
		var state = _make_state.call(units)
		return Targeting.has_line_of_sight(state, 0, 0, 6, 0)
	)

	_test("LoS: diagonal supercover catches off-axis blocker", func():
		# Shooting from (0,0) to (4,4). On a pure diagonal walk the line passes
		# through cells where the supercover Bresenham checks (cx+sx, cy) and
		# (cx, cy+sy). Place a Follower at (1,0) to ensure the axis-adjacent
		# check fires.
		var blocker = Types.UnitState.new("b", 1, "Fodder", "follower", 1, 1, stats, "", [], 0, false, 0, 1, 0)
		var units: Array[Types.UnitState] = [blocker]
		var state = _make_state.call(units)
		return not Targeting.has_line_of_sight(state, 0, 0, 4, 4)
	)

	_test("LoS: clear diagonal passes when no blocker", func():
		var units: Array[Types.UnitState] = []
		var state = _make_state.call(units)
		return Targeting.has_line_of_sight(state, 0, 0, 4, 4)
	)


## Run a single test
func _test(test_name: String, test_func: Callable) -> void:
	var result = test_func.call()
	if result:
		_tests_passed += 1
		print("  PASS " + test_name)
	else:
		_tests_failed += 1
		print("  FAIL " + test_name)
