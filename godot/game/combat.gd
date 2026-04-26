class_name Combat
extends RefCounted
## Shooting and melee resolution.
##
## Pure RefCounted — no Node, no signals, no scene tree. Dice rolls are
## passed in as a flat Array[int] so the caller (engine or test) controls
## the RNG. Wound application and panic-token bookkeeping mutate the
## supplied UnitState refs in place; range/LoS validation is the caller's
## job (handled in game/targeting.gd).
##
## V17 model:
##   - Shooting engagement: attacker rolls, then defender rolls return fire
##     against pre-engagement model counts (casualties do NOT suppress
##     return fire — v17 core p.13). Wounds applied simultaneously.
##   - Melee bout: attacker strikes, defender removes casualties; if
##     defender survives, defender counter-strikes. Winner = more unsaved
##     wounds in the bout. Tie = next bout. Hard cap MELEE_MAX_BOUTS = 3
##     bouts to prevent dice-whiff infinite loops; cap-tie ends in a draw
##     (no retreat, but caller still applies +1 panic per melee-ended).

const Board = preload("res://game/board.gd")

# Melee bout cap — v17 has no hard limit, but tied bouts could loop forever
# on whiffing dice. Cap at 3; unresolved ties after the cap end in a draw
# with no retreat (caller still applies +1 panic per melee-ended rule).
const MELEE_MAX_BOUTS: int = 3


## Apply wounds to a unit, removing models as they die. Mutates `unit`.
static func apply_wounds(unit: Types.UnitState, wounds: int) -> void:
	var remaining_wounds = wounds
	while remaining_wounds > 0 and not unit.is_dead:
		unit.current_wounds += 1
		remaining_wounds -= 1
		if unit.current_wounds >= unit.base_stats.wounds:
			unit.model_count -= 1
			unit.current_wounds = 0
			if unit.model_count <= 0:
				unit.is_dead = true
				unit.model_count = 0


## Resolve one side's shooting attacks. Consumes dice from the pool starting
## at `offset`. Does NOT mutate either unit — caller applies wounds, smoke,
## and panic tokens after both sides have rolled.
## Returns { hits, saves, unsaved_wounds, dice_used, error }.
static func resolve_shooting_side(attacker: Types.UnitState, target: Types.UnitState, dice_results: Array, offset: int, inaccuracy_mod: int) -> Dictionary:
	var num_attacks = attacker.model_count
	var needed_dice = num_attacks * 2
	if dice_results.size() - offset < needed_dice:
		return {"hits": 0, "saves": 0, "unsaved_wounds": 0, "dice_used": 0,
				"error": "Not enough dice (need %d at offset %d, have %d)" % [needed_dice, offset, dice_results.size() - offset]}

	var inaccuracy = maxi(attacker.base_stats.inaccuracy + inaccuracy_mod, 2)
	var vulnerability = target.base_stats.vulnerability

	# Equipment modifiers
	if attacker.equipment == "missile":
		vulnerability = maxi(vulnerability - 2, 2)

	var hits = 0
	var saves = 0
	var unsaved_wounds = 0

	for i in range(num_attacks):
		var inac_roll = dice_results[offset + i]
		var vuln_roll = dice_results[offset + num_attacks + i]
		if inac_roll >= inaccuracy:
			hits += 1
			if vuln_roll >= vulnerability:
				saves += 1
			else:
				unsaved_wounds += 1

	return {"hits": hits, "saves": saves, "unsaved_wounds": unsaved_wounds,
			"dice_used": needed_dice, "error": ""}


## Is the target eligible to return fire at the shooter? v17 core p.13:
## target must have a ranged weapon, no powder smoke, and the shooter must
## be within the target's weapon range. Casualties from the primary strike
## do NOT suppress return fire (resolved from pre-engagement state).
static func can_return_fire(target: Types.UnitState, shooter: Types.UnitState) -> bool:
	if target.is_dead or shooter.is_dead:
		return false
	if target.base_stats.weapon_range <= 0:
		return false
	if target.has_powder_smoke:
		return false
	return Board.grid_distance(target.x, target.y, shooter.x, shooter.y) <= target.base_stats.weapon_range


## Resolve a shooting engagement (v17 core p.13). Both sides roll against
## pre-engagement model counts — casualties from the primary strike do not
## suppress return fire. Wounds, smoke, and hit-panic tokens applied after
## both sides have rolled.
##
## Winner = side that dealt more unsaved wounds. Tie = no winner, no retreat
## (caller still runs retreat only when winner/loser set).
##
## Returns {
##   att_hits, att_saves, att_wounds,
##   def_hits, def_saves, def_wounds,
##   return_fire_fired: bool,
##   winner_id, loser_id,           # "" on tie
##   tie: bool,
##   dice_used: int,
##   error: String
## }
static func resolve_shooting_engagement(attacker: Types.UnitState, target: Types.UnitState, dice_results: Array, attacker_inaccuracy_mod: int) -> Dictionary:
	var result = {
		"att_hits": 0, "att_saves": 0, "att_wounds": 0,
		"def_hits": 0, "def_saves": 0, "def_wounds": 0,
		"return_fire_fired": false,
		"winner_id": "", "loser_id": "",
		"tie": false,
		"dice_used": 0,
		"error": "",
	}

	if attacker.is_dead or target.is_dead:
		result["error"] = "Cannot resolve shooting: one side already dead"
		return result

	# Attacker rolls first (dice pool laid out attacker-then-defender).
	var att = resolve_shooting_side(attacker, target, dice_results, 0, attacker_inaccuracy_mod)
	if att["error"] != "":
		result["error"] = att["error"]
		return result
	result["att_hits"] = att["hits"]
	result["att_saves"] = att["saves"]
	result["att_wounds"] = att["unsaved_wounds"]

	var offset: int = att["dice_used"]

	# Return fire eligibility checked from pre-engagement state.
	var can_return = can_return_fire(target, attacker)
	if can_return:
		# Defender return fire — inaccuracy_mod=0 (no volley-fire bonus on return).
		var defn = resolve_shooting_side(target, attacker, dice_results, offset, 0)
		if defn["error"] != "":
			result["error"] = defn["error"]
			return result
		result["def_hits"] = defn["hits"]
		result["def_saves"] = defn["saves"]
		result["def_wounds"] = defn["unsaved_wounds"]
		result["return_fire_fired"] = true
		offset += defn["dice_used"]

	result["dice_used"] = offset

	# Apply wounds simultaneously (casualties don't suppress return fire).
	apply_wounds(target, result["att_wounds"])
	if result["return_fire_fired"]:
		apply_wounds(attacker, result["def_wounds"])

	# Panic tokens from taking hits (any hits, saved or not).
	if result["att_hits"] > 0 and not target.is_dead:
		target.panic_tokens = mini(target.panic_tokens + 1, 6)
	if result["def_hits"] > 0 and not attacker.is_dead:
		attacker.panic_tokens = mini(attacker.panic_tokens + 1, 6)

	# Powder smoke: whichever side fired with black_powder gets a smoke token.
	if attacker.equipment == "black_powder":
		attacker.has_powder_smoke = true
	if result["return_fire_fired"] and target.equipment == "black_powder":
		target.has_powder_smoke = true

	# Winner / loser / tie — decided by total unsaved wounds dealt.
	if result["att_wounds"] > result["def_wounds"]:
		result["winner_id"] = attacker.id
		result["loser_id"] = target.id
	elif result["def_wounds"] > result["att_wounds"]:
		result["winner_id"] = target.id
		result["loser_id"] = attacker.id
	else:
		result["tie"] = true

	return result


## Resolve one side's attacks in a melee bout. Consumes dice from the pool
## starting at `offset`. Returns { hits, saves, unsaved_wounds, dice_used, error }.
## Mutates `defender` via apply_wounds.
static func resolve_bout_side(attacker: Types.UnitState, defender: Types.UnitState, dice_results: Array, offset: int) -> Dictionary:
	var attacks_per_model = attacker.base_stats.attacks
	var inaccuracy = attacker.base_stats.inaccuracy
	var vulnerability = defender.base_stats.vulnerability

	# Close combat equipment reduces inaccuracy by 1 (min 2)
	if attacker.equipment == "close_combat":
		inaccuracy = maxi(inaccuracy - 1, 2)

	var num_attacks = attacker.model_count * attacks_per_model
	var needed_dice = num_attacks * 2
	if dice_results.size() - offset < needed_dice:
		return {"hits": 0, "saves": 0, "unsaved_wounds": 0, "dice_used": 0,
				"error": "Not enough dice (need %d at offset %d, have %d)" % [needed_dice, offset, dice_results.size() - offset]}

	var hits = 0
	var saves = 0
	var unsaved_wounds = 0

	for i in range(num_attacks):
		var inac_roll = dice_results[offset + i]
		var vuln_roll = dice_results[offset + num_attacks + i]
		if inac_roll >= inaccuracy:
			hits += 1
			if vuln_roll >= vulnerability:
				saves += 1
			else:
				unsaved_wounds += 1

	apply_wounds(defender, unsaved_wounds)

	return {"hits": hits, "saves": saves, "unsaved_wounds": unsaved_wounds,
			"dice_used": needed_dice, "error": ""}


## Worst-case dice pool size for a full melee between two units.
## Attacker strikes + defender counter-strikes, each at 2 dice per attack,
## across up to MELEE_MAX_BOUTS. Callers should supply at least this many.
static func melee_dice_budget(attacker: Types.UnitState, defender: Types.UnitState) -> int:
	var per_bout = (attacker.model_count * attacker.base_stats.attacks * 2) \
		+ (defender.model_count * defender.base_stats.attacks * 2)
	return per_bout * MELEE_MAX_BOUTS


## Resolve a melee engagement as bouts (v17 core p.18). Mutates both units
## in place via wound application. Does NOT apply post-melee panic tokens or
## trigger retreat — caller handles those so it can integrate with state.
##
## Each bout: attacker strikes → defender removes casualties → if defender
## still alive, defender counter-strikes → attacker removes casualties.
## Winner = side that dealt more unsaved wounds that bout. Tie → next bout.
## Hard cap at MELEE_MAX_BOUTS; if still tied at the cap, draw (no retreat).
##
## Returns {
##   bouts: [{atk_hits, atk_saves, atk_wounds, def_hits, def_saves, def_wounds}...],
##   winner_id, loser_id,  # "" on draw or if one side was already dead
##   draw: bool,           # true only when cap hit with no winner
##   dice_used: int,
##   error: String
## }
static func resolve_melee(attacker: Types.UnitState, target: Types.UnitState, dice_results: Array) -> Dictionary:
	var summary = {
		"bouts": [],
		"winner_id": "",
		"loser_id": "",
		"draw": false,
		"dice_used": 0,
		"error": "",
	}

	if attacker.is_dead or target.is_dead:
		summary["error"] = "Cannot resolve melee: one side already dead"
		return summary

	var offset: int = 0

	for bout_idx in range(MELEE_MAX_BOUTS):
		var bout = {
			"atk_hits": 0, "atk_saves": 0, "atk_wounds": 0,
			"def_hits": 0, "def_saves": 0, "def_wounds": 0,
		}

		# Attacker strikes first
		var atk = resolve_bout_side(attacker, target, dice_results, offset)
		if atk["error"] != "":
			summary["error"] = atk["error"]
			return summary
		offset += atk["dice_used"]
		bout["atk_hits"] = atk["hits"]
		bout["atk_saves"] = atk["saves"]
		bout["atk_wounds"] = atk["unsaved_wounds"]

		# Target wiped out before counter-attack
		if target.is_dead:
			summary["bouts"].append(bout)
			summary["winner_id"] = attacker.id
			summary["loser_id"] = target.id
			summary["dice_used"] = offset
			return summary

		# Defender counter-strikes
		var def = resolve_bout_side(target, attacker, dice_results, offset)
		if def["error"] != "":
			summary["error"] = def["error"]
			return summary
		offset += def["dice_used"]
		bout["def_hits"] = def["hits"]
		bout["def_saves"] = def["saves"]
		bout["def_wounds"] = def["unsaved_wounds"]
		summary["bouts"].append(bout)

		# Attacker wiped out — defender wins the bout trivially
		if attacker.is_dead:
			summary["winner_id"] = target.id
			summary["loser_id"] = attacker.id
			summary["dice_used"] = offset
			return summary

		# Both alive — decide the bout
		if bout["atk_wounds"] > bout["def_wounds"]:
			summary["winner_id"] = attacker.id
			summary["loser_id"] = target.id
			summary["dice_used"] = offset
			return summary
		if bout["def_wounds"] > bout["atk_wounds"]:
			summary["winner_id"] = target.id
			summary["loser_id"] = attacker.id
			summary["dice_used"] = offset
			return summary
		# Tie → next bout

	# Cap reached with no decisive bout — draw.
	summary["draw"] = true
	summary["dice_used"] = offset
	return summary
