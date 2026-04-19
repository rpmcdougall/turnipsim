class_name Types
extends RefCounted
## Shared data classes for game state.
##
## This file and everything in game/ must have ZERO node/scene dependencies.
## Pure data + logic only — safe to use from server, client, or tests.
##
## Stats match Turnip28 v17 characteristics:
##   M (movement), A (attacks), I (inaccuracy), W (wounds), V (vulnerability)


## Unit statistics matching Turnip28 v17 characteristics.
class Stats extends RefCounted:
	var movement: int = 0       # M — max distance in inches
	var attacks: int = 0        # A — number of melee attack dice per model
	var inaccuracy: int = 0     # I — minimum D6 result to hit (lower = better)
	var wounds: int = 0         # W — damage capacity per model
	var vulnerability: int = 0  # V — minimum D6 result to save (lower = better)
	var weapon_range: int = 0   # Weapon's Range in inches (0 = melee only)

	func _init(p_movement: int = 0, p_attacks: int = 0, p_inaccuracy: int = 0, p_wounds: int = 0, p_vulnerability: int = 0, p_weapon_range: int = 0) -> void:
		movement = p_movement
		attacks = p_attacks
		inaccuracy = p_inaccuracy
		wounds = p_wounds
		vulnerability = p_vulnerability
		weapon_range = p_weapon_range

	func to_dict() -> Dictionary:
		return {
			"movement": movement,
			"attacks": attacks,
			"inaccuracy": inaccuracy,
			"wounds": wounds,
			"vulnerability": vulnerability,
			"weapon_range": weapon_range
		}

	static func from_dict(data: Dictionary) -> Stats:
		return Stats.new(
			data.get("movement", 0),
			data.get("attacks", 0),
			data.get("inaccuracy", 0),
			data.get("wounds", 0),
			data.get("vulnerability", 0),
			data.get("weapon_range", 0)
		)


## Equipment type that modifies combat behavior.
class Equipment extends RefCounted:
	var name: String = ""
	var type: String = ""  # "black_powder", "missile", "close_combat", "pistols_and_sabres"
	var description: String = ""

	func _init(p_name: String = "", p_type: String = "", p_description: String = "") -> void:
		name = p_name
		type = p_type
		description = p_description

	func to_dict() -> Dictionary:
		return {
			"name": name,
			"type": type,
			"description": description
		}

	static func from_dict(data: Dictionary) -> Equipment:
		return Equipment.new(
			data.get("name", ""),
			data.get("type", ""),
			data.get("description", "")
		)


## A unit definition from the ruleset (template, not runtime state).
class UnitDef extends RefCounted:
	var unit_type: String = ""     # "Fodder", "Chaff", "Brutes", "Toff", etc.
	var category: String = ""      # "snob", "infantry", "cavalry", "artillery"
	var model_count: int = 1
	var base_stats: Stats = null
	var special_rules: Array[String] = []
	var allowed_equipment: Array[String] = []  # Equipment type keys
	var description: String = ""

	func _init(
		p_unit_type: String = "",
		p_category: String = "",
		p_model_count: int = 1,
		p_base_stats: Stats = null,
		p_special_rules: Array[String] = [],
		p_allowed_equipment: Array[String] = [],
		p_description: String = ""
	) -> void:
		unit_type = p_unit_type
		category = p_category
		model_count = p_model_count
		base_stats = p_base_stats if p_base_stats else Stats.new()
		special_rules = p_special_rules
		allowed_equipment = p_allowed_equipment
		description = p_description

	func to_dict() -> Dictionary:
		return {
			"unit_type": unit_type,
			"category": category,
			"model_count": model_count,
			"base_stats": base_stats.to_dict(),
			"special_rules": special_rules,
			"allowed_equipment": allowed_equipment,
			"description": description
		}

	static func from_dict(data: Dictionary) -> UnitDef:
		var rules: Array[String] = []
		if data.has("special_rules"):
			for r in data["special_rules"]:
				rules.append(str(r))
		var equip: Array[String] = []
		if data.has("allowed_equipment"):
			for e in data["allowed_equipment"]:
				equip.append(str(e))
		return UnitDef.new(
			data.get("unit_type", ""),
			data.get("category", ""),
			data.get("model_count", 1),
			Stats.from_dict(data.get("base_stats", {})),
			rules,
			equip,
			data.get("description", "")
		)


## A unit pick in a roster — a Follower assigned to a Snob.
class RosterUnit extends RefCounted:
	var unit_type: String = ""      # e.g. "Fodder", "Chaff", "Brutes"
	var equipment: String = ""      # Equipment type key, e.g. "black_powder"

	func _init(p_unit_type: String = "", p_equipment: String = "") -> void:
		unit_type = p_unit_type
		equipment = p_equipment

	func to_dict() -> Dictionary:
		return {
			"unit_type": unit_type,
			"equipment": equipment
		}

	static func from_dict(data: Dictionary) -> RosterUnit:
		return RosterUnit.new(
			data.get("unit_type", ""),
			data.get("equipment", "")
		)


## A Snob entry in a roster with their assigned Followers.
class RosterSnob extends RefCounted:
	var snob_type: String = ""       # "Toff" or "Toady"
	var equipment: String = ""       # Always "pistols_and_sabres" for core
	var followers: Array[RosterUnit] = []

	func _init(p_snob_type: String = "", p_equipment: String = "", p_followers: Array[RosterUnit] = []) -> void:
		snob_type = p_snob_type
		equipment = p_equipment
		followers = p_followers

	func to_dict() -> Dictionary:
		var follower_dicts: Array = []
		for f in followers:
			follower_dicts.append(f.to_dict())
		return {
			"snob_type": snob_type,
			"equipment": equipment,
			"followers": follower_dicts
		}

	static func from_dict(data: Dictionary) -> RosterSnob:
		var followers_array: Array[RosterUnit] = []
		if data.has("followers"):
			for f_data in data["followers"]:
				followers_array.append(RosterUnit.from_dict(f_data))
		return RosterSnob.new(
			data.get("snob_type", ""),
			data.get("equipment", ""),
			followers_array
		)


## A complete army roster submitted by a player.
class Roster extends RefCounted:
	var cult: String = ""  # "none" for core-only
	var snobs: Array[RosterSnob] = []

	func _init(p_cult: String = "none", p_snobs: Array[RosterSnob] = []) -> void:
		cult = p_cult
		snobs = p_snobs

	func to_dict() -> Dictionary:
		var snob_dicts: Array = []
		for s in snobs:
			snob_dicts.append(s.to_dict())
		return {
			"cult": cult,
			"snobs": snob_dicts
		}

	static func from_dict(data: Dictionary) -> Roster:
		var snobs_array: Array[RosterSnob] = []
		if data.has("snobs"):
			for s_data in data["snobs"]:
				snobs_array.append(RosterSnob.from_dict(s_data))
		return Roster.new(
			data.get("cult", "none"),
			snobs_array
		)

	## Get total number of units (snobs + followers).
	func get_unit_count() -> int:
		var count = 0
		for snob in snobs:
			count += 1  # The snob itself
			count += snob.followers.size()
		return count

	## Get total number of snobs.
	func get_snob_count() -> int:
		return snobs.size()


## Runtime state of a single unit on the battlefield.
class UnitState extends RefCounted:
	var id: String = ""
	var owner_seat: int = 0
	var unit_type: String = ""
	var category: String = ""       # "snob", "infantry", "cavalry", "artillery"
	var model_count: int = 1        # Current living models in this unit
	var max_models: int = 1         # Starting model count
	var base_stats: Stats = null
	var equipment: String = ""      # Equipment type key
	var special_rules: Array[String] = []
	var panic_tokens: int = 0       # 0-6
	var has_powder_smoke: bool = false
	var current_wounds: int = 0     # Wounds on the currently damaged model
	var x: int = -1                 # -1 = not placed
	var y: int = -1
	var has_activated: bool = false
	var is_dead: bool = false
	var snob_id: String = ""        # ID of commanding Snob (empty if this IS a snob)

	func _init(
		p_id: String = "",
		p_owner_seat: int = 0,
		p_unit_type: String = "",
		p_category: String = "",
		p_model_count: int = 1,
		p_max_models: int = 1,
		p_base_stats: Stats = null,
		p_equipment: String = "",
		p_special_rules: Array[String] = [],
		p_panic_tokens: int = 0,
		p_has_powder_smoke: bool = false,
		p_current_wounds: int = 0,
		p_x: int = -1,
		p_y: int = -1,
		p_has_activated: bool = false,
		p_is_dead: bool = false,
		p_snob_id: String = ""
	) -> void:
		id = p_id
		owner_seat = p_owner_seat
		unit_type = p_unit_type
		category = p_category
		model_count = p_model_count
		max_models = p_max_models
		base_stats = p_base_stats if p_base_stats else Stats.new()
		equipment = p_equipment
		special_rules = p_special_rules
		panic_tokens = p_panic_tokens
		has_powder_smoke = p_has_powder_smoke
		current_wounds = p_current_wounds
		x = p_x
		y = p_y
		has_activated = p_has_activated
		is_dead = p_is_dead
		snob_id = p_snob_id

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"owner_seat": owner_seat,
			"unit_type": unit_type,
			"category": category,
			"model_count": model_count,
			"max_models": max_models,
			"base_stats": base_stats.to_dict(),
			"equipment": equipment,
			"special_rules": special_rules,
			"panic_tokens": panic_tokens,
			"has_powder_smoke": has_powder_smoke,
			"current_wounds": current_wounds,
			"x": x,
			"y": y,
			"has_activated": has_activated,
			"is_dead": is_dead,
			"snob_id": snob_id
		}

	static func from_dict(data: Dictionary) -> UnitState:
		var rules: Array[String] = []
		if data.has("special_rules"):
			for r in data["special_rules"]:
				rules.append(str(r))
		return UnitState.new(
			data.get("id", ""),
			data.get("owner_seat", 0),
			data.get("unit_type", ""),
			data.get("category", ""),
			data.get("model_count", 1),
			data.get("max_models", 1),
			Stats.from_dict(data.get("base_stats", {})),
			data.get("equipment", ""),
			rules,
			data.get("panic_tokens", 0),
			data.get("has_powder_smoke", false),
			data.get("current_wounds", 0),
			data.get("x", -1),
			data.get("y", -1),
			data.get("has_activated", false),
			data.get("is_dead", false),
			data.get("snob_id", "")
		)

	## Is this unit a Snob (commander)?
	func is_snob() -> bool:
		return category == "snob"

	## Can this unit shoot? (has ranged weapon and no powder smoke)
	func can_shoot() -> bool:
		return base_stats.weapon_range > 0 and not has_powder_smoke

	## Get command range for Snobs. Returns 0 for non-Snobs.
	func get_command_range() -> int:
		if unit_type == "Toff":
			return 6
		elif unit_type == "Toady":
			return 3
		return 0


## Game state for a battle in progress.
class GameState extends RefCounted:
	var room_code: String = ""
	var phase: String = "placement"  # "placement" | "orders" | "finished"
	var current_round: int = 1
	var max_rounds: int = 4
	var active_seat: int = 1
	var initiative_seat: int = 1    # Player with initiative (set once, stays)
	var units: Array[UnitState] = []
	var action_log: Array[Dictionary] = []
	var winner_seat: int = 0

	func _init(
		p_room_code: String = "",
		p_phase: String = "placement",
		p_current_round: int = 1,
		p_max_rounds: int = 4,
		p_active_seat: int = 1,
		p_initiative_seat: int = 1,
		p_units: Array[UnitState] = [],
		p_action_log: Array[Dictionary] = [],
		p_winner_seat: int = 0
	) -> void:
		room_code = p_room_code
		phase = p_phase
		current_round = p_current_round
		max_rounds = p_max_rounds
		active_seat = p_active_seat
		initiative_seat = p_initiative_seat
		units = p_units
		action_log = p_action_log
		winner_seat = p_winner_seat

	func to_dict() -> Dictionary:
		var units_array: Array = []
		for unit in units:
			units_array.append(unit.to_dict())

		return {
			"room_code": room_code,
			"phase": phase,
			"current_round": current_round,
			"max_rounds": max_rounds,
			"active_seat": active_seat,
			"initiative_seat": initiative_seat,
			"units": units_array,
			"action_log": action_log,
			"winner_seat": winner_seat
		}

	static func from_dict(data: Dictionary) -> GameState:
		var units_array: Array[UnitState] = []
		if data.has("units"):
			for unit_data in data["units"]:
				units_array.append(UnitState.from_dict(unit_data))

		return GameState.new(
			data.get("room_code", ""),
			data.get("phase", "placement"),
			data.get("current_round", 1),
			data.get("max_rounds", 4),
			data.get("active_seat", 1),
			data.get("initiative_seat", 1),
			units_array,
			data.get("action_log", []),
			data.get("winner_seat", 0)
		)


## Result of an engine operation.
class EngineResult extends RefCounted:
	var success: bool = false
	var error: String = ""
	var new_state: GameState = null
	var dice_rolled: Array = []
	var description: String = ""

	func _init(
		p_success: bool = false,
		p_error: String = "",
		p_new_state: GameState = null,
		p_dice_rolled: Array = [],
		p_description: String = ""
	) -> void:
		success = p_success
		error = p_error
		new_state = p_new_state
		dice_rolled = p_dice_rolled
		description = p_description

	func to_dict() -> Dictionary:
		return {
			"success": success,
			"error": error,
			"new_state": new_state.to_dict() if new_state else {},
			"dice_rolled": dice_rolled,
			"description": description
		}
