extends SceneTree
## Demo script to display roster presets.
##
## Run with: godot --headless --script tests/demo_army_roll.gd

func _init() -> void:
	print("======================================================================")
	print("ROSTER PRESETS DEMO")
	print("======================================================================")
	print("")

	# Load the v17 ruleset
	var ruleset = Ruleset.new()
	var error = ruleset.load_from_file("res://game/rulesets/v17.json")
	if error:
		print("ERROR: Failed to load ruleset: " + error)
		quit(1)
		return

	print("Loaded ruleset: " + ruleset.name + " v" + ruleset.version)
	print(ruleset.description)
	print("")

	# Load presets from JSON
	var file = FileAccess.open("res://game/rulesets/v17.json", FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	var data = json.get_data()
	var presets = data.get("presets", [])

	for preset_idx in range(presets.size()):
		var preset = presets[preset_idx]
		print("----------------------------------------------------------------------")
		print("PRESET: %s" % preset["name"])
		print(preset.get("description", ""))
		print("----------------------------------------------------------------------")

		var roster = Types.Roster.from_dict(preset["roster"])
		print("Total units: %d (Snobs: %d)" % [roster.get_unit_count(), roster.get_snob_count()])

		# Validate against ruleset
		var validation = ruleset.validate_roster(roster)
		if validation == "":
			print("Validation: PASS")
		else:
			print("Validation: FAIL - %s" % validation)

		print("")

		var unit_num = 0
		for snob in roster.snobs:
			unit_num += 1
			_print_unit(unit_num, snob.snob_type, snob.equipment, ruleset, true)

			for follower in snob.followers:
				unit_num += 1
				_print_unit(unit_num, follower.unit_type, follower.equipment, ruleset, false)

		print("")

	print("======================================================================")
	print("Demo complete!")
	print("======================================================================")
	quit(0)


func _print_unit(number: int, unit_type: String, equipment: String, ruleset: Ruleset, is_snob: bool) -> void:
	var prefix = "" if is_snob else "  "
	var def_data = ruleset.get_unit_type(unit_type)

	print("%s[%d] %s (%s)" % [prefix, number, unit_type, equipment])

	if not def_data.is_empty():
		var stats = def_data["base_stats"]
		print("%s    M%d A%d I%d+ W%d V%d+ | Range:%d\" | Models:%d" % [
			prefix, stats["movement"], stats["attacks"], stats["inaccuracy"],
			stats["wounds"], stats["vulnerability"], stats.get("weapon_range", 0),
			def_data.get("model_count", 1)
		])

		if def_data.has("special_rules") and not def_data["special_rules"].is_empty():
			print("%s    Rules: %s" % [prefix, ", ".join(def_data["special_rules"])])

	print("")
