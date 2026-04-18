class_name Types
extends RefCounted
## Shared data classes for game state.
##
## This file and everything in game/ must have ZERO node/scene dependencies.
## Pure data + logic only — safe to use from server, client, or tests.


## Unit statistics.
class Stats extends RefCounted:
	var movement: int = 0
	var shooting: int = 0
	var combat: int = 0
	var resolve: int = 0
	var wounds: int = 0
	var save: int = 0

	func _init(p_movement: int = 0, p_shooting: int = 0, p_combat: int = 0, p_resolve: int = 0, p_wounds: int = 0, p_save: int = 0) -> void:
		movement = p_movement
		shooting = p_shooting
		combat = p_combat
		resolve = p_resolve
		wounds = p_wounds
		save = p_save

	func to_dict() -> Dictionary:
		return {
			"movement": movement,
			"shooting": shooting,
			"combat": combat,
			"resolve": resolve,
			"wounds": wounds,
			"save": save
		}

	static func from_dict(data: Dictionary) -> Stats:
		return Stats.new(
			data.get("movement", 0),
			data.get("shooting", 0),
			data.get("combat", 0),
			data.get("resolve", 0),
			data.get("wounds", 0),
			data.get("save", 0)
		)


## Weapon definition.
class Weapon extends RefCounted:
	var name: String = ""
	var type: String = ""  # "melee" or "ranged"
	var range: int = 0  # 0 for melee
	var modifier: int = 0  # Bonus/penalty to hit

	func _init(p_name: String = "", p_type: String = "melee", p_range: int = 0, p_modifier: int = 0) -> void:
		name = p_name
		type = p_type
		range = p_range
		modifier = p_modifier

	func to_dict() -> Dictionary:
		return {
			"name": name,
			"type": type,
			"range": range,
			"modifier": modifier
		}

	static func from_dict(data: Dictionary) -> Weapon:
		return Weapon.new(
			data.get("name", ""),
			data.get("type", "melee"),
			data.get("range", 0),
			data.get("modifier", 0)
		)


## Mutation that modifies a unit.
class Mutation extends RefCounted:
	var name: String = ""
	var description: String = ""
	var stat_modifiers: Dictionary = {}  # stat_name -> modifier value

	func _init(p_name: String = "", p_description: String = "", p_stat_modifiers: Dictionary = {}) -> void:
		name = p_name
		description = p_description
		stat_modifiers = p_stat_modifiers

	func to_dict() -> Dictionary:
		return {
			"name": name,
			"description": description,
			"stat_modifiers": stat_modifiers
		}

	static func from_dict(data: Dictionary) -> Mutation:
		return Mutation.new(
			data.get("name", ""),
			data.get("description", ""),
			data.get("stat_modifiers", {})
		)


## A complete unit with stats, weapon, and mutations.
class Unit extends RefCounted:
	var name: String = ""
	var archetype: String = ""  # "Toff", "Chuff", "Root Beast"
	var base_stats: Stats = null
	var weapon: Weapon = null
	var mutations: Array[Mutation] = []

	func _init(p_name: String = "", p_archetype: String = "", p_base_stats: Stats = null, p_weapon: Weapon = null, p_mutations: Array[Mutation] = []) -> void:
		name = p_name
		archetype = p_archetype
		base_stats = p_base_stats if p_base_stats else Stats.new()
		weapon = p_weapon if p_weapon else Weapon.new()
		mutations = p_mutations

	## Get effective stats after applying all mutations.
	func get_effective_stats() -> Stats:
		var stats = Stats.new(
			base_stats.movement,
			base_stats.shooting,
			base_stats.combat,
			base_stats.resolve,
			base_stats.wounds,
			base_stats.save
		)

		for mutation in mutations:
			for stat_name in mutation.stat_modifiers:
				var modifier = mutation.stat_modifiers[stat_name]
				match stat_name:
					"movement": stats.movement += modifier
					"shooting": stats.shooting += modifier
					"combat": stats.combat += modifier
					"resolve": stats.resolve += modifier
					"wounds": stats.wounds += modifier
					"save": stats.save += modifier

		return stats

	func to_dict() -> Dictionary:
		var mutation_dicts: Array = []
		for mutation in mutations:
			mutation_dicts.append(mutation.to_dict())

		return {
			"name": name,
			"archetype": archetype,
			"base_stats": base_stats.to_dict(),
			"weapon": weapon.to_dict(),
			"mutations": mutation_dicts
		}

	static func from_dict(data: Dictionary) -> Unit:
		var mutations_array: Array[Mutation] = []
		if data.has("mutations"):
			for mutation_data in data["mutations"]:
				mutations_array.append(Mutation.from_dict(mutation_data))

		return Unit.new(
			data.get("name", ""),
			data.get("archetype", ""),
			Stats.from_dict(data.get("base_stats", {})),
			Weapon.from_dict(data.get("weapon", {})),
			mutations_array
		)


## Runtime state of a unit on the battlefield.
class UnitState extends RefCounted:
	var id: String = ""
	var owner_seat: int = 0
	var name: String = ""
	var archetype: String = ""
	var base_stats: Stats = null
	var weapon: Weapon = null
	var mutations: Array[Mutation] = []
	var max_wounds: int = 0
	var current_wounds: int = 0
	var x: int = -1  # -1 = not placed
	var y: int = -1
	var has_activated: bool = false
	var is_dead: bool = false

	func _init(
		p_id: String = "",
		p_owner_seat: int = 0,
		p_name: String = "",
		p_archetype: String = "",
		p_base_stats: Stats = null,
		p_weapon: Weapon = null,
		p_mutations: Array[Mutation] = [],
		p_max_wounds: int = 0,
		p_current_wounds: int = 0,
		p_x: int = -1,
		p_y: int = -1,
		p_has_activated: bool = false,
		p_is_dead: bool = false
	) -> void:
		id = p_id
		owner_seat = p_owner_seat
		name = p_name
		archetype = p_archetype
		base_stats = p_base_stats if p_base_stats else Stats.new()
		weapon = p_weapon if p_weapon else Weapon.new()
		mutations = p_mutations
		max_wounds = p_max_wounds
		current_wounds = p_current_wounds
		x = p_x
		y = p_y
		has_activated = p_has_activated
		is_dead = p_is_dead

	## Get effective stats after applying mutations.
	func get_effective_stats() -> Stats:
		var stats = Stats.new(
			base_stats.movement,
			base_stats.shooting,
			base_stats.combat,
			base_stats.resolve,
			base_stats.wounds,
			base_stats.save
		)

		for mutation in mutations:
			for stat_name in mutation.stat_modifiers:
				var modifier = mutation.stat_modifiers[stat_name]
				match stat_name:
					"movement": stats.movement += modifier
					"shooting": stats.shooting += modifier
					"combat": stats.combat += modifier
					"resolve": stats.resolve += modifier
					"wounds": stats.wounds += modifier
					"save": stats.save += modifier

		return stats

	func to_dict() -> Dictionary:
		var mutations_array: Array = []
		for mutation in mutations:
			mutations_array.append(mutation.to_dict())

		return {
			"id": id,
			"owner_seat": owner_seat,
			"name": name,
			"archetype": archetype,
			"base_stats": base_stats.to_dict(),
			"weapon": weapon.to_dict(),
			"mutations": mutations_array,
			"max_wounds": max_wounds,
			"current_wounds": current_wounds,
			"x": x,
			"y": y,
			"has_activated": has_activated,
			"is_dead": is_dead
		}

	static func from_dict(data: Dictionary) -> UnitState:
		var mutations_array: Array[Mutation] = []
		if data.has("mutations"):
			for mut_data in data["mutations"]:
				mutations_array.append(Mutation.from_dict(mut_data))

		return UnitState.new(
			data.get("id", ""),
			data.get("owner_seat", 0),
			data.get("name", ""),
			data.get("archetype", ""),
			Stats.from_dict(data.get("base_stats", {})),
			Weapon.from_dict(data.get("weapon", {})),
			mutations_array,
			data.get("max_wounds", 1),
			data.get("current_wounds", 1),
			data.get("x", -1),
			data.get("y", -1),
			data.get("has_activated", false),
			data.get("is_dead", false)
		)


## Game state for a battle in progress.
class GameState extends RefCounted:
	var room_code: String = ""
	var phase: String = "placement"  # "placement" | "combat" | "finished"
	var current_turn: int = 1
	var active_seat: int = 1  # Which player's turn
	var units: Array[UnitState] = []
	var action_log: Array[Dictionary] = []
	var winner_seat: int = 0  # 0 = no winner yet

	func _init(
		p_room_code: String = "",
		p_phase: String = "placement",
		p_current_turn: int = 1,
		p_active_seat: int = 1,
		p_units: Array[UnitState] = [],
		p_action_log: Array[Dictionary] = [],
		p_winner_seat: int = 0
	) -> void:
		room_code = p_room_code
		phase = p_phase
		current_turn = p_current_turn
		active_seat = p_active_seat
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
			"current_turn": current_turn,
			"active_seat": active_seat,
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
			data.get("current_turn", 1),
			data.get("active_seat", 1),
			units_array,
			data.get("action_log", []),
			data.get("winner_seat", 0)
		)


## Result of an engine operation.
class EngineResult extends RefCounted:
	var success: bool = false
	var error: String = ""
	var new_state: GameState = null
	var dice_rolled: Array = []  # For logging/replay
	var description: String = ""  # Human-readable action description

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
