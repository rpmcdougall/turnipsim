class_name ArmyRoller
extends RefCounted
## Generates a random army from a Ruleset using injected dice rolls.
##
## Usage:
##   var roller = ArmyRoller.new()
##   var army = roller.roll_army(ruleset, func(): return randi_range(1, 6))


## Roll a complete army following the ruleset's composition rules.
## roll_d6: Callable that returns an int from 1-6 (or any RNG function)
func roll_army(ruleset: Ruleset, roll_d6: Callable) -> Array[Types.Unit]:
	if not ruleset or not ruleset.is_loaded():
		push_error("ArmyRoller: Invalid or unloaded ruleset")
		return []

	var army: Array[Types.Unit] = []
	var comp = ruleset.composition_rules

	# Determine army size
	var min_size: int = comp.get("min_units", 5)
	var max_size: int = comp.get("max_units", 10)
	var army_size: int = _roll_range(min_size, max_size, roll_d6)

	# Track slots filled
	var slots_remaining: int = army_size
	var archetype_counts: Dictionary = {}

	# First, fulfill required units
	if comp.has("required"):
		for archetype_name in comp["required"]:
			var requirements = comp["required"][archetype_name]
			var min_count: int = requirements.get("min", 0)
			var max_count: int = requirements.get("max", min_count)

			var count: int = _roll_range(min_count, max_count, roll_d6)
			archetype_counts[archetype_name] = count
			slots_remaining -= count

	# Fill remaining slots with random archetypes
	var all_archetypes: Array = ruleset.archetypes.keys()
	while slots_remaining > 0:
		var archetype_name: String = _pick_random(all_archetypes, roll_d6)

		# Check if this archetype has a max limit
		var has_limit: bool = false
		if comp.has("required") and comp["required"].has(archetype_name):
			var requirements = comp["required"][archetype_name]
			var max_count: int = requirements.get("max", 999)
			var current_count: int = archetype_counts.get(archetype_name, 0)
			if current_count >= max_count:
				has_limit = true

		if not has_limit:
			archetype_counts[archetype_name] = archetype_counts.get(archetype_name, 0) + 1
			slots_remaining -= 1

		# Safety: if all archetypes hit their limits, break
		if _all_archetypes_maxed(archetype_counts, comp, all_archetypes):
			break

	# Now create units for each archetype
	for archetype_name in archetype_counts:
		var count: int = archetype_counts[archetype_name]
		for i in range(count):
			var unit = _roll_unit(ruleset, archetype_name, roll_d6)
			if unit:
				army.append(unit)

	return army


## Roll a single unit of the given archetype.
func _roll_unit(ruleset: Ruleset, archetype_name: String, roll_d6: Callable) -> Types.Unit:
	var archetype_data = ruleset.get_archetype(archetype_name)
	if archetype_data.is_empty():
		push_error("ArmyRoller: Unknown archetype: " + archetype_name)
		return null

	# Load base stats
	var stats_data = archetype_data["base_stats"]
	var base_stats = Types.Stats.from_dict(stats_data)

	# Roll mutations
	var mutations: Array[Types.Mutation] = []
	var mutations_per_unit: int = ruleset.composition_rules.get("mutations_per_unit", 2)
	var mutation_tables: Array = archetype_data.get("mutation_tables", [])

	for i in range(min(mutations_per_unit, mutation_tables.size())):
		var table = mutation_tables[i]
		var mutation = _roll_mutation_from_table(table, roll_d6)
		if mutation:
			mutations.append(mutation)

	# Pick a weapon
	var weapon_dict = ruleset.get_random_weapon_for_archetype(archetype_name, roll_d6)
	var weapon = Types.Weapon.from_dict(weapon_dict) if not weapon_dict.is_empty() else Types.Weapon.new()

	# Generate unit name
	var unit_name = _generate_unit_name(archetype_name, archetype_data, roll_d6)

	return Types.Unit.new(unit_name, archetype_name, base_stats, weapon, mutations)


## Roll a mutation from a mutation table.
func _roll_mutation_from_table(table: Dictionary, roll_d6: Callable) -> Types.Mutation:
	if not table.has("rolls"):
		return null

	var roll_value: int = roll_d6.call()
	var rolls: Array = table["rolls"]

	# Find matching roll
	for roll_entry in rolls:
		var range_array = roll_entry["range"]
		if typeof(range_array) == TYPE_ARRAY and range_array.size() == 2:
			var min_val: int = range_array[0]
			var max_val: int = range_array[1]
			if roll_value >= min_val and roll_value <= max_val:
				return Types.Mutation.new(
					roll_entry.get("name", ""),
					roll_entry.get("description", ""),
					roll_entry.get("stat_modifiers", {})
				)

	# Fallback: if no match, return the first entry
	if not rolls.is_empty():
		var first_roll = rolls[0]
		return Types.Mutation.new(
			first_roll.get("name", ""),
			first_roll.get("description", ""),
			first_roll.get("stat_modifiers", {})
		)

	return null


## Generate a thematic name for a unit.
func _generate_unit_name(archetype_name: String, archetype_data: Dictionary, roll_d6: Callable) -> String:
	# DECISION: Simple naming scheme — can be enhanced later with name tables
	var prefixes = ["Corporal", "Private", "Sergeant", "Lieutenant", "Captain", "Major"]
	var suffixes = ["Mudsworth", "Rootley", "Turnipson", "Mashfield", "Sproutington", "Parsnipwell"]

	match archetype_name:
		"Toff":
			prefixes = ["Lord", "Sir", "Baron", "Count", "Duke", "Viscount"]
			suffixes = ["Moldington", "Rotsworth", "Blightwell", "Pustule", "Gangrenshire", "Slimewood"]
		"Chuff":
			prefixes = ["Private", "Grunt", "Wretch", "Corpse", "Mudlark", "Scab"]
			suffixes = ["the Sodden", "the Wretched", "Trenchfoot", "Lungrot", "Scurvy", "Filth"]
		"RootBeast":
			prefixes = ["", "", "", "", "", ""]  # No prefix for beasts
			suffixes = ["Rootbeast", "The Turnip Horror", "Mud Fiend", "Carrot Abomination", "Parsnip Terror", "Vegetable Nightmare"]

	var prefix = _pick_random(prefixes, roll_d6) if not prefixes[0].is_empty() else ""
	var suffix = _pick_random(suffixes, roll_d6)

	if prefix.is_empty():
		return suffix
	else:
		return prefix + " " + suffix


## Roll a random integer between min and max (inclusive).
func _roll_range(min_val: int, max_val: int, roll_d6: Callable) -> int:
	if min_val == max_val:
		return min_val
	var range_size = max_val - min_val + 1
	# Use multiple d6 rolls if needed for larger ranges
	var roll = roll_d6.call()
	return min_val + (roll % range_size)


## Pick a random element from an array.
func _pick_random(array: Array, roll_d6: Callable) -> Variant:
	if array.is_empty():
		return null
	var index = (roll_d6.call() - 1) % array.size()
	return array[index]


## Check if all archetypes have reached their maximum counts.
func _all_archetypes_maxed(counts: Dictionary, comp: Dictionary, all_archetypes: Array) -> bool:
	if not comp.has("required"):
		return false

	for archetype_name in all_archetypes:
		if comp["required"].has(archetype_name):
			var requirements = comp["required"][archetype_name]
			var max_count: int = requirements.get("max", 999)
			var current_count: int = counts.get(archetype_name, 0)
			if current_count < max_count:
				return false
		else:
			# No limit on this archetype
			return false

	return true
