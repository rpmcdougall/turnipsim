class_name Ruleset
extends RefCounted
## Loads and exposes a ruleset from a JSON data file.
##
## Usage:
##   var rs = Ruleset.new()
##   var error = rs.load_from_file("res://game/rulesets/mvp.json")
##   if error:
##       push_error("Failed to load ruleset: " + error)

var name: String = ""
var version: String = ""
var description: String = ""
var archetypes: Dictionary = {}  # archetype_name -> archetype_data
var weapons: Array[Dictionary] = []
var composition_rules: Dictionary = {}

var _is_loaded: bool = false


## Load and validate a ruleset from a JSON file.
## Returns an error string if loading fails, or empty string on success.
func load_from_file(path: String) -> String:
	_is_loaded = false

	if not FileAccess.file_exists(path):
		return "File not found: " + path

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Failed to open file: " + path

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_text)
	if parse_result != OK:
		return "JSON parse error at line " + str(json.get_error_line()) + ": " + json.get_error_message()

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return "Root JSON must be a dictionary"

	var validation_error = _validate_and_load(data)
	if validation_error:
		return validation_error

	_is_loaded = true
	return ""


## Validate the loaded data and populate fields.
func _validate_and_load(data: Dictionary) -> String:
	# Required top-level fields
	if not data.has("name"):
		return "Missing required field: name"
	if not data.has("archetypes"):
		return "Missing required field: archetypes"
	if not data.has("weapons"):
		return "Missing required field: weapons"
	if not data.has("composition_rules"):
		return "Missing required field: composition_rules"

	name = data["name"]
	version = data.get("version", "")
	description = data.get("description", "")

	# Validate archetypes
	if typeof(data["archetypes"]) != TYPE_DICTIONARY:
		return "archetypes must be a dictionary"

	for archetype_key in data["archetypes"]:
		var archetype_data = data["archetypes"][archetype_key]
		var error = _validate_archetype(archetype_key, archetype_data)
		if error:
			return error
		archetypes[archetype_key] = archetype_data

	if archetypes.is_empty():
		return "At least one archetype is required"

	# Validate weapons
	if typeof(data["weapons"]) != TYPE_ARRAY:
		return "weapons must be an array"

	for weapon_data in data["weapons"]:
		var error = _validate_weapon(weapon_data)
		if error:
			return error
		weapons.append(weapon_data)

	if weapons.is_empty():
		return "At least one weapon is required"

	# Validate composition rules
	if typeof(data["composition_rules"]) != TYPE_DICTIONARY:
		return "composition_rules must be a dictionary"

	var error = _validate_composition_rules(data["composition_rules"])
	if error:
		return error
	composition_rules = data["composition_rules"]

	return ""


func _validate_archetype(key: String, data: Dictionary) -> String:
	if not data.has("name"):
		return "Archetype '" + key + "' missing field: name"
	if not data.has("base_stats"):
		return "Archetype '" + key + "' missing field: base_stats"
	if not data.has("mutation_tables"):
		return "Archetype '" + key + "' missing field: mutation_tables"

	# Validate base_stats
	var stats = data["base_stats"]
	if typeof(stats) != TYPE_DICTIONARY:
		return "Archetype '" + key + "' base_stats must be a dictionary"

	var required_stats = ["movement", "shooting", "combat", "resolve", "wounds", "save"]
	for stat in required_stats:
		if not stats.has(stat):
			return "Archetype '" + key + "' base_stats missing: " + stat

	# Validate mutation_tables
	if typeof(data["mutation_tables"]) != TYPE_ARRAY:
		return "Archetype '" + key + "' mutation_tables must be an array"

	for table in data["mutation_tables"]:
		var error = _validate_mutation_table(key, table)
		if error:
			return error

	return ""


func _validate_mutation_table(archetype_key: String, table: Dictionary) -> String:
	if not table.has("name"):
		return "Mutation table in archetype '" + archetype_key + "' missing field: name"
	if not table.has("rolls"):
		return "Mutation table '" + table.get("name", "?") + "' missing field: rolls"

	if typeof(table["rolls"]) != TYPE_ARRAY:
		return "Mutation table '" + table["name"] + "' rolls must be an array"

	for roll in table["rolls"]:
		if typeof(roll) != TYPE_DICTIONARY:
			return "Mutation table '" + table["name"] + "' roll entry must be a dictionary"
		if not roll.has("range"):
			return "Mutation table '" + table["name"] + "' roll missing field: range"
		if not roll.has("name"):
			return "Mutation table '" + table["name"] + "' roll missing field: name"

	return ""


func _validate_weapon(data: Dictionary) -> String:
	if not data.has("name"):
		return "Weapon missing field: name"
	if not data.has("type"):
		return "Weapon '" + data.get("name", "?") + "' missing field: type"

	var weapon_type = data["type"]
	if weapon_type != "melee" and weapon_type != "ranged":
		return "Weapon '" + data["name"] + "' type must be 'melee' or 'ranged', got: " + str(weapon_type)

	return ""


func _validate_composition_rules(rules: Dictionary) -> String:
	if not rules.has("min_units"):
		return "composition_rules missing field: min_units"
	if not rules.has("max_units"):
		return "composition_rules missing field: max_units"

	var min_units = rules["min_units"]
	var max_units = rules["max_units"]

	if typeof(min_units) != TYPE_INT and typeof(min_units) != TYPE_FLOAT:
		return "composition_rules min_units must be a number"
	if typeof(max_units) != TYPE_INT and typeof(max_units) != TYPE_FLOAT:
		return "composition_rules max_units must be a number"
	if min_units > max_units:
		return "composition_rules min_units cannot be greater than max_units"

	return ""


## Get an archetype by name, or null if not found.
func get_archetype(archetype_name: String) -> Dictionary:
	return archetypes.get(archetype_name, {})


## Get all weapon names for a given archetype from composition rules.
func get_allowed_weapons_for_archetype(archetype_name: String) -> Array:
	if composition_rules.has("allowed_weapons"):
		var allowed = composition_rules["allowed_weapons"]
		if allowed.has(archetype_name):
			return allowed[archetype_name]
	return []


## Get a random weapon from the allowed list for an archetype.
func get_random_weapon_for_archetype(archetype_name: String, roll_fn: Callable) -> Dictionary:
	var allowed = get_allowed_weapons_for_archetype(archetype_name)
	if allowed.is_empty():
		return {}

	# Find matching weapons
	var matching_weapons: Array[Dictionary] = []
	for weapon in weapons:
		if weapon["name"] in allowed:
			matching_weapons.append(weapon)

	if matching_weapons.is_empty():
		return {}

	var index = roll_fn.call() % matching_weapons.size()
	return matching_weapons[index]


## Check if the ruleset is loaded and valid.
func is_loaded() -> bool:
	return _is_loaded
