extends SceneTree
## Demo script to roll and display armies.
##
## Run with: godot --headless --script tests/demo_army_roll.gd

func _init() -> void:
	print("======================================================================")
	print("ARMY ROLLER DEMO")
	print("======================================================================")
	print("")

	# Load the MVP ruleset
	var ruleset = Ruleset.new()
	var error = ruleset.load_from_file("res://game/rulesets/mvp.json")
	if error:
		print("ERROR: Failed to load ruleset: " + error)
		quit(1)
		return

	print("Loaded ruleset: " + ruleset.name + " v" + ruleset.version)
	print(ruleset.description)
	print("")

	# Roll 3 different armies to show variety
	for army_num in range(1, 4):
		print("----------------------------------------------------------------------")
		print("ARMY #" + str(army_num))
		print("----------------------------------------------------------------------")

		var roller = ArmyRoller.new()
		var army = roller.roll_army(ruleset, func(): return randi_range(1, 6))

		print("Army size: " + str(army.size()) + " units")
		print("")

		for i in range(army.size()):
			var unit = army[i]
			_print_unit(i + 1, unit)

		print("")

	print("======================================================================")
	print("Demo complete!")
	print("======================================================================")
	quit(0)


func _print_unit(number: int, unit: Types.Unit) -> void:
	print("[" + str(number) + "] " + unit.name + " (" + unit.archetype + ")")

	var effective = unit.get_effective_stats()
	print("    Stats: M" + str(effective.movement) +
	      " S" + str(effective.shooting) +
	      " C" + str(effective.combat) +
	      " R" + str(effective.resolve) +
	      " W" + str(effective.wounds) +
	      " Sv" + str(effective.save) + "+")

	print("    Weapon: " + unit.weapon.name + " (" + unit.weapon.type + ")")

	if unit.mutations.size() > 0:
		print("    Mutations:")
		for mutation in unit.mutations:
			var mods = []
			for stat_name in mutation.stat_modifiers:
				var mod_value = mutation.stat_modifiers[stat_name]
				var sign = "+" if mod_value >= 0 else ""
				mods.append(stat_name.capitalize() + " " + sign + str(mod_value))
			print("      • " + mutation.name + " — " + mutation.description)
			print("        (" + ", ".join(mods) + ")")

	print()
