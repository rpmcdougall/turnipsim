extends SceneTree
## Headless test runner for Phase 1 game logic.
##
## Run with: godot --headless -s tests/test_runner.gd

var _tests_passed: int = 0
var _tests_failed: int = 0


func _init() -> void:
	print("============================================================")
	print("Running Phase 1 Tests")
	print("============================================================")

	_test_types()
	_test_ruleset_loader()
	_test_army_roller()

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


## Test Types classes (Stats, Weapon, Mutation, Unit)
func _test_types() -> void:
	print("\n[Test Suite: Types]")

	# Test Stats creation and to_dict/from_dict
	_test("Stats creation", func():
		var stats = Types.Stats.new(5, 4, 4, 5, 2, 3)
		return stats.movement == 5 and stats.shooting == 4 and stats.wounds == 2
	)

	_test("Stats to_dict and from_dict", func():
		var stats = Types.Stats.new(5, 4, 4, 5, 2, 3)
		var dict = stats.to_dict()
		var restored = Types.Stats.from_dict(dict)
		return restored.movement == 5 and restored.combat == 4 and restored.save == 3
	)

	# Test Weapon
	_test("Weapon creation", func():
		var weapon = Types.Weapon.new("Sabre", "melee", 0, 1)
		return weapon.name == "Sabre" and weapon.type == "melee" and weapon.modifier == 1
	)

	_test("Weapon to_dict and from_dict", func():
		var weapon = Types.Weapon.new("Musket", "ranged", 12, 0)
		var dict = weapon.to_dict()
		var restored = Types.Weapon.from_dict(dict)
		return restored.name == "Musket" and restored.range == 12
	)

	# Test Mutation
	_test("Mutation with stat modifiers", func():
		var mutation = Types.Mutation.new("Gouty Leg", "Swollen", {"movement": -1, "wounds": 1})
		return mutation.name == "Gouty Leg" and mutation.stat_modifiers["movement"] == -1
	)

	# Test Unit with effective stats
	_test("Unit with mutations applies stat modifiers", func():
		var base_stats = Types.Stats.new(5, 4, 4, 5, 2, 3)
		var mutation = Types.Mutation.new("Fast", "Speedy", {"movement": 2, "combat": 1})
		var weapon = Types.Weapon.new("Sabre", "melee", 0, 1)
		var unit = Types.Unit.new("Test", "Toff", base_stats, weapon, [mutation])

		var effective = unit.get_effective_stats()
		return effective.movement == 7 and effective.combat == 5 and effective.wounds == 2
	)

	_test("Unit to_dict and from_dict", func():
		var base_stats = Types.Stats.new(5, 4, 4, 5, 2, 3)
		var mutation = Types.Mutation.new("Test", "Desc", {"movement": 1})
		var weapon = Types.Weapon.new("Sabre", "melee", 0, 1)
		var unit = Types.Unit.new("Lord Test", "Toff", base_stats, weapon, [mutation])

		var dict = unit.to_dict()
		var restored = Types.Unit.from_dict(dict)
		return restored.name == "Lord Test" and restored.archetype == "Toff" and restored.mutations.size() == 1
	)


## Test Ruleset loading and validation
func _test_ruleset_loader() -> void:
	print("\n[Test Suite: Ruleset]")

	_test("Load valid MVP ruleset", func():
		var ruleset = Ruleset.new()
		var error = ruleset.load_from_file("res://game/rulesets/mvp.json")
		return error == "" and ruleset.is_loaded()
	)

	_test("MVP ruleset has expected archetypes", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")
		return ruleset.archetypes.has("Toff") and ruleset.archetypes.has("Chuff") and ruleset.archetypes.has("RootBeast")
	)

	_test("MVP ruleset has weapons", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")
		return ruleset.weapons.size() > 0
	)

	_test("Get archetype returns correct data", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")
		var toff = ruleset.get_archetype("Toff")
		return toff.has("base_stats") and toff["base_stats"]["movement"] == 5
	)

	_test("Get allowed weapons for archetype", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")
		var weapons = ruleset.get_allowed_weapons_for_archetype("Toff")
		return weapons.size() > 0 and "Sabre" in weapons
	)

	_test("Reject non-existent file", func():
		var ruleset = Ruleset.new()
		var error = ruleset.load_from_file("res://game/rulesets/nonexistent.json")
		return error != "" and not ruleset.is_loaded()
	)

	# Test malformed JSON
	_test("Reject invalid JSON", func():
		# Create a temp invalid JSON file for testing
		var temp_path = "res://tests/temp_invalid.json"
		var file = FileAccess.open(temp_path, FileAccess.WRITE)
		if file:
			file.store_string("{invalid json")
			file.close()

		var ruleset = Ruleset.new()
		var error = ruleset.load_from_file(temp_path)

		# Clean up
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(temp_path)

		return error != "" and not ruleset.is_loaded()
	)


## Test ArmyRoller with deterministic dice
func _test_army_roller() -> void:
	print("\n[Test Suite: ArmyRoller]")

	# Deterministic dice roller for testing
	var deterministic_sequence: Array[int] = [3, 5, 2, 4, 6, 1, 3, 5, 2, 4, 6, 1, 3, 5, 2, 4]
	var dice_index: int = 0
	var deterministic_d6 = func() -> int:
		var value = deterministic_sequence[dice_index % deterministic_sequence.size()]
		dice_index += 1
		return value

	_test("Roll army with deterministic dice", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")

		dice_index = 0
		var roller = ArmyRoller.new()
		var army = roller.roll_army(ruleset, deterministic_d6)

		return army.size() >= ruleset.composition_rules["min_units"] and army.size() <= ruleset.composition_rules["max_units"]
	)

	_test("Army respects composition rules (has required Toff)", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")

		dice_index = 0
		var roller = ArmyRoller.new()
		var army = roller.roll_army(ruleset, deterministic_d6)

		var toff_count = 0
		for unit in army:
			if unit.archetype == "Toff":
				toff_count += 1

		return toff_count >= 1 and toff_count <= 2
	)

	_test("Units have mutations", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")

		dice_index = 0
		var roller = ArmyRoller.new()
		var army = roller.roll_army(ruleset, deterministic_d6)

		# At least some units should have mutations
		var units_with_mutations = 0
		for unit in army:
			if unit.mutations.size() > 0:
				units_with_mutations += 1

		return units_with_mutations > 0
	)

	_test("Units have weapons", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")

		dice_index = 0
		var roller = ArmyRoller.new()
		var army = roller.roll_army(ruleset, deterministic_d6)

		# All units should have a weapon
		for unit in army:
			if unit.weapon.name.is_empty():
				return false

		return true
	)

	_test("Same dice sequence produces identical army", func():
		var ruleset = Ruleset.new()
		ruleset.load_from_file("res://game/rulesets/mvp.json")

		dice_index = 0
		var roller1 = ArmyRoller.new()
		var army1 = roller1.roll_army(ruleset, deterministic_d6)

		dice_index = 0
		var roller2 = ArmyRoller.new()
		var army2 = roller2.roll_army(ruleset, deterministic_d6)

		if army1.size() != army2.size():
			return false

		for i in range(army1.size()):
			var u1 = army1[i]
			var u2 = army2[i]
			if u1.name != u2.name or u1.archetype != u2.archetype or u1.weapon.name != u2.weapon.name:
				return false

		return true
	)


## Run a single test
func _test(test_name: String, test_func: Callable) -> void:
	var result = test_func.call()
	if result:
		_tests_passed += 1
		print("  ✓ " + test_name)
	else:
		_tests_failed += 1
		print("  ✗ " + test_name)
