class_name Objectives
extends RefCounted
## Objective marker capture and end-of-game victory determination.
##
## Pure RefCounted, no node deps. Imported by the engine to recompute
## capture state after any positional change and to declare a winner
## once the round limit is reached or one side is wiped out.
##
## V17 model:
##   - Only Followers capture (Snobs never do — v17 core p.22).
##   - "Within 1"" = Euclidean distance ≤ 1.0, so only orthogonal neighbors.
##     Diagonal cells (√2 ≈ 1.41) are out of range and do NOT capture.
##   - Both seats adjacent → contested → captured_by = 0.
##   - Only one seat adjacent → captured by that seat.
##   - Neither adjacent → retain prior captured_by.
##   - Units cannot end a move on an objective cell (enforced in board.gd).
##
## Victory order:
##   1. One side has zero alive units and the other has any → that side wins.
##   2. Headless Chicken — one side has zero alive Snobs → instant loss.
##   3. Round limit reached → most-controlled-objectives wins, ties = draw.
##   4. Otherwise no winner yet.
##
## Solo mode (one side has zero units total) skips victory entirely.

const Board = preload("res://game/board.gd")


## Is there an objective marker at this cell?
static func is_objective_at(state: Types.GameState, x: int, y: int) -> bool:
	for obj in state.objectives:
		if obj.x == x and obj.y == y:
			return true
	return false


## Recompute capture state for every objective per v17 core p.22.
## Called after any state change that could shift Follower positions
## (placement finalized, moves, charges, unit deaths). Mutates in place.
##
## MVP simplification: the v17 "only one objective captured per move"
## player-choice rule is not enforced here — a move that ends adjacent to
## two uncontrolled objectives will capture both. Tracked for a follow-up
## when objective placement is dense enough to matter in practice.
static func resolve_objective_captures(state: Types.GameState) -> void:
	for obj in state.objectives:
		var seat1_adjacent := 0
		var seat2_adjacent := 0
		for u in state.units:
			if u.is_dead or u.is_snob():
				continue
			if u.x < 0 or u.y < 0:
				continue
			var d := Board.grid_distance(u.x, u.y, obj.x, obj.y)
			if d <= 1.0:
				if u.owner_seat == 1:
					seat1_adjacent += 1
				else:
					seat2_adjacent += 1
		if seat1_adjacent > 0 and seat2_adjacent > 0:
			obj.captured_by = 0
		elif seat1_adjacent > 0:
			obj.captured_by = 1
		elif seat2_adjacent > 0:
			obj.captured_by = 2
		# else: retain obj.captured_by (captured objective stays captured
		# until enemy contests or claims it).


## Check for victory condition. Read-only; returns { winner, reason }.
## winner = 1 or 2 for a decisive result, 0 for "no winner yet" OR draw
## (the reason string disambiguates).
static func check_victory(state: Types.GameState) -> Dictionary:
	var units_total_1: int = 0
	var units_total_2: int = 0
	var units_alive_1: int = 0
	var units_alive_2: int = 0

	for unit in state.units:
		if unit.owner_seat == 1:
			units_total_1 += 1
			if not unit.is_dead:
				units_alive_1 += 1
		else:
			units_total_2 += 1
			if not unit.is_dead:
				units_alive_2 += 1

	# Solo mode: one side has no units at all — no victory check
	if units_total_1 == 0 or units_total_2 == 0:
		return {"winner": 0, "reason": ""}

	if units_alive_1 == 0 and units_alive_2 > 0:
		return {"winner": 2, "reason": "Player 1 eliminated"}
	if units_alive_2 == 0 and units_alive_1 > 0:
		return {"winner": 1, "reason": "Player 2 eliminated"}
	if units_alive_1 == 0 and units_alive_2 == 0:
		return {"winner": 0, "reason": "Draw (both eliminated)"}

	# Headless Chicken: all Snobs dead = instant loss
	var snobs_alive_1 = 0
	var snobs_alive_2 = 0
	for unit in state.units:
		if not unit.is_dead and unit.is_snob():
			if unit.owner_seat == 1:
				snobs_alive_1 += 1
			else:
				snobs_alive_2 += 1

	if snobs_alive_1 == 0 and snobs_alive_2 > 0:
		return {"winner": 2, "reason": "Player 1 lost all Snobs (Headless Chicken)"}
	if snobs_alive_2 == 0 and snobs_alive_1 > 0:
		return {"winner": 1, "reason": "Player 2 lost all Snobs (Headless Chicken)"}

	# Round limit reached: v17 objective scoring (core p.22, scenarios p.23+).
	# "The player who controls the most objective markers at the end of the
	# final round is the victor." Ties go straight to draw — no secondary
	# model-count fallback in the rules.
	if state.current_round > state.max_rounds:
		var objectives_1: int = 0
		var objectives_2: int = 0
		for obj in state.objectives:
			if obj.captured_by == 1:
				objectives_1 += 1
			elif obj.captured_by == 2:
				objectives_2 += 1
		if objectives_1 > objectives_2:
			return {"winner": 1, "reason": "Player 1 controls %d objective(s) to %d" % [objectives_1, objectives_2]}
		if objectives_2 > objectives_1:
			return {"winner": 2, "reason": "Player 2 controls %d objective(s) to %d" % [objectives_2, objectives_1]}
		return {"winner": 0, "reason": "Objectives tied %d–%d (Draw)" % [objectives_1, objectives_2]}

	return {"winner": 0, "reason": ""}
