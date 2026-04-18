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
