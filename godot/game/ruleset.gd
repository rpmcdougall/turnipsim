class_name Ruleset
extends RefCounted
## Loads and exposes a Turnip28 ruleset from a JSON data file.
##
## The ruleset defines unit types, equipment, special rules, and army
## composition constraints. It does NOT contain game logic — that lives
## in the game engine.
##
## Usage:
##   var rs = Ruleset.new()
##   var error = rs.load_from_file("res://game/rulesets/v17.json")

var name: String = ""
var version: String = ""
var description: String = ""
var unit_types: Dictionary = {}       # unit_type_key -> UnitDef data dict
var equipment_types: Dictionary = {}  # equipment_key -> Equipment data dict
var special_rules: Dictionary = {}    # rule_key -> { name, description }
var composition: Dictionary = {}      # Army building constraints

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


func _validate_and_load(data: Dictionary) -> String:
	for field in ["name", "unit_types", "equipment_types", "composition"]:
		if not data.has(field):
			return "Missing required field: " + field

	name = data["name"]
	version = data.get("version", "")
	description = data.get("description", "")

	# Validate equipment types
	if typeof(data["equipment_types"]) != TYPE_DICTIONARY:
		return "equipment_types must be a dictionary"
	for key in data["equipment_types"]:
		var equip = data["equipment_types"][key]
		if typeof(equip) != TYPE_DICTIONARY:
			return "Equipment '" + key + "' must be a dictionary"
		if not equip.has("name"):
			return "Equipment '" + key + "' missing field: name"
		if not equip.has("type"):
			return "Equipment '" + key + "' missing field: type"
	equipment_types = data["equipment_types"]

	# Validate unit types
	if typeof(data["unit_types"]) != TYPE_DICTIONARY:
		return "unit_types must be a dictionary"
	for key in data["unit_types"]:
		var error = _validate_unit_type(key, data["unit_types"][key])
		if error:
			return error
	unit_types = data["unit_types"]

	if unit_types.is_empty():
		return "At least one unit type is required"

	# Load special rules (optional — just descriptive text)
	if data.has("special_rules"):
		if typeof(data["special_rules"]) != TYPE_DICTIONARY:
			return "special_rules must be a dictionary"
		special_rules = data["special_rules"]

	# Validate composition
	if typeof(data["composition"]) != TYPE_DICTIONARY:
		return "composition must be a dictionary"
	var error = _validate_composition(data["composition"])
	if error:
		return error
	composition = data["composition"]

	return ""


func _validate_unit_type(key: String, data: Dictionary) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "Unit type '" + key + "' must be a dictionary"

	for field in ["unit_type", "category", "model_count", "base_stats"]:
		if not data.has(field):
			return "Unit type '" + key + "' missing field: " + field

	var category = data["category"]
	if category not in ["snob", "infantry", "cavalry", "artillery"]:
		return "Unit type '" + key + "' invalid category: " + str(category)

	var stats = data["base_stats"]
	if typeof(stats) != TYPE_DICTIONARY:
		return "Unit type '" + key + "' base_stats must be a dictionary"

	for stat in ["movement", "attacks", "inaccuracy", "wounds", "vulnerability"]:
		if not stats.has(stat):
			return "Unit type '" + key + "' base_stats missing: " + stat

	return ""


func _validate_composition(comp: Dictionary) -> String:
	if not comp.has("snob_count"):
		return "composition missing field: snob_count"
	if not comp.has("followers_per_toff"):
		return "composition missing field: followers_per_toff"
	if not comp.has("followers_per_toady"):
		return "composition missing field: followers_per_toady"
	return ""


## Get a unit type definition by key, or empty dict if not found.
func get_unit_type(unit_type_key: String) -> Dictionary:
	return unit_types.get(unit_type_key, {})


## Get a UnitDef object for a unit type key.
func get_unit_def(unit_type_key: String) -> Types.UnitDef:
	var data = get_unit_type(unit_type_key)
	if data.is_empty():
		return null
	return Types.UnitDef.from_dict(data)


## Get an equipment type definition by key.
func get_equipment(equipment_key: String) -> Dictionary:
	return equipment_types.get(equipment_key, {})


## Get all unit type keys for a given category.
func get_unit_types_by_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for key in unit_types:
		if unit_types[key].get("category", "") == category:
			result.append(key)
	return result


## Get all follower unit type keys (infantry + cavalry + artillery).
func get_follower_types() -> Array[String]:
	var result: Array[String] = []
	for key in unit_types:
		var cat = unit_types[key].get("category", "")
		if cat in ["infantry", "cavalry", "artillery"]:
			result.append(key)
	return result


## Get allowed equipment keys for a unit type.
func get_allowed_equipment(unit_type_key: String) -> Array[String]:
	var data = get_unit_type(unit_type_key)
	if data.is_empty():
		return []
	var result: Array[String] = []
	if data.has("allowed_equipment"):
		for e in data["allowed_equipment"]:
			result.append(str(e))
	return result


## Validate a roster against this ruleset's composition rules.
## Returns empty string if valid, error message if not.
func validate_roster(roster: Types.Roster) -> String:
	if roster.snobs.is_empty():
		return "Roster must have at least one Snob"

	var toff_count = 0
	var toady_count = 0

	for snob in roster.snobs:
		if snob.snob_type == "Toff":
			toff_count += 1
		elif snob.snob_type == "Toady":
			toady_count += 1
		else:
			return "Unknown Snob type: " + snob.snob_type

		# Validate Snob equipment
		var snob_def = get_unit_type(snob.snob_type)
		if snob_def.is_empty():
			return "Unknown unit type: " + snob.snob_type

		# Validate follower count
		var max_followers = composition.get("followers_per_toff", 2) if snob.snob_type == "Toff" else composition.get("followers_per_toady", 1)
		if snob.followers.size() > max_followers:
			return snob.snob_type + " has too many followers: " + str(snob.followers.size()) + " (max " + str(max_followers) + ")"

		# Validate each follower
		for follower in snob.followers:
			var fdef = get_unit_type(follower.unit_type)
			if fdef.is_empty():
				return "Unknown follower unit type: " + follower.unit_type
			var fcat = fdef.get("category", "")
			if fcat == "snob":
				return "Cannot take a Snob as a follower: " + follower.unit_type
			# Validate equipment choice
			var allowed = get_allowed_equipment(follower.unit_type)
			if not allowed.is_empty() and follower.equipment not in allowed:
				return follower.unit_type + " cannot equip " + follower.equipment + " (allowed: " + ", ".join(allowed) + ")"

	if toff_count != 1:
		return "Roster must have exactly 1 Toff (has " + str(toff_count) + ")"

	var expected_toadies = composition.get("snob_count", 3) - 1
	if toady_count != expected_toadies:
		return "Roster must have " + str(expected_toadies) + " Toadies (has " + str(toady_count) + ")"

	return ""


func is_loaded() -> bool:
	return _is_loaded
