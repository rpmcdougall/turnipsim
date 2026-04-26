extends Node
## ENet server listener — Phase 3 + 4.
## Exposes RPCs for clients to interact with the server.

const Combat = preload("res://game/combat.gd")
const Objectives = preload("res://game/objectives.gd")

@onready var room_manager: Node = get_parent().get_node("RoomManager")

# Active game states: room_code -> Types.GameState
var active_games: Dictionary = {}


## Client RPC: Create a new room
@rpc("any_peer", "call_remote", "reliable")
func create_room(display_name: String) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d requesting room creation (name: %s)" % [peer_id, display_name])

	var code = room_manager.create_room(peer_id, display_name)

	if code.is_empty():
		# Failed to create room
		_send_error_to_client(peer_id, "Failed to create room")
		return

	# Send room state back to creator via NetworkClient
	var room = room_manager.get_room_for_peer(peer_id)
	NetworkClient._send_room_joined.rpc_id(peer_id, room.to_dict())


## Client RPC: Join an existing room
@rpc("any_peer", "call_remote", "reliable")
func join_room(code: String, display_name: String) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d requesting to join room %s (name: %s)" % [peer_id, code, display_name])

	var success = room_manager.join_room(peer_id, display_name, code)

	if not success:
		_send_error_to_client(peer_id, "Failed to join room " + code)
		return

	# Get room state and send to new player via NetworkClient
	var room = room_manager.get_room_for_peer(peer_id)
	NetworkClient._send_room_joined.rpc_id(peer_id, room.to_dict())

	# Notify all other players in the room
	var new_player = room.get_player(peer_id)
	for player in room.players:
		if player["peer_id"] != peer_id:
			NetworkClient._send_peer_joined.rpc_id(player["peer_id"], new_player)


## Client RPC: Set ready status
@rpc("any_peer", "call_remote", "reliable")
func set_ready(ready: bool) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d set ready: %s" % [peer_id, ready])

	var success = room_manager.set_player_ready(peer_id, ready)

	if not success:
		_send_error_to_client(peer_id, "Failed to set ready status")
		return

	# Broadcast ready status to all players in the room via NetworkClient
	var room = room_manager.get_room_for_peer(peer_id)
	if room:
		for player in room.players:
			NetworkClient._send_player_ready_changed.rpc_id(player["peer_id"], peer_id, ready)

		# Check if all players are ready
		if room.is_full() and room_manager.are_all_players_ready(room):
			print("[NetworkServer] All players in room %s are ready" % room.code)
			# Phase 3b will handle game_started broadcast


## Client RPC: Submit roster (Phase 3b — replaces old submit_army)
@rpc("any_peer", "call_remote", "reliable")
func submit_army(roster_data: Dictionary) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d submitting roster" % peer_id)

	var room = room_manager.get_room_for_peer(peer_id)
	if not room:
		_send_error_to_client(peer_id, "Not in a room")
		return

	# Parse and validate roster
	var roster = Types.Roster.from_dict(roster_data)
	var ruleset = Ruleset.new()
	var load_error = ruleset.load_from_file("res://game/rulesets/v17.json")
	if load_error:
		_send_error_to_client(peer_id, "Server failed to load ruleset")
		return

	var validation_error = ruleset.validate_roster(roster)
	if validation_error:
		_send_error_to_client(peer_id, "Invalid roster: " + validation_error)
		return

	# Store roster in room state
	var player = room.get_player(peer_id)
	if player.is_empty():
		_send_error_to_client(peer_id, "Player not found in room")
		return

	player["army"] = roster_data  # Store as dict for serialization

	# Broadcast to all players in room via NetworkClient
	var unit_count = roster.get_unit_count()
	for p in room.players:
		NetworkClient._send_army_submitted.rpc_id(p["peer_id"], peer_id, unit_count)

	# Check if both armies are submitted
	if _are_both_armies_submitted(room):
		_start_game(room)


## Helper: Check if both players have submitted armies
func _are_both_armies_submitted(room) -> bool:
	if room.players.size() != 2:
		return false

	for player in room.players:
		if player["army"].is_empty():
			return false

	return true


## Client RPC: Start game in solo testing mode (bypass 2-player requirement)
@rpc("any_peer", "call_remote", "reliable")
func start_solo_test() -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d requesting solo test start" % peer_id)

	var room = room_manager.get_room_for_peer(peer_id)
	if not room:
		_send_error_to_client(peer_id, "Not in a room")
		return

	# Verify player has submitted an army
	var player = room.get_player(peer_id)
	if player.is_empty() or (typeof(player["army"]) == TYPE_DICTIONARY and player["army"].is_empty()) or (typeof(player["army"]) == TYPE_ARRAY and player["army"].is_empty()):
		_send_error_to_client(peer_id, "Must submit roster before starting solo test")
		return

	print("[NetworkServer] Starting solo test mode for room %s (1 player)" % room.code)
	_start_game(room)


## Helper: Start the game (Phase 3b)
func _start_game(room) -> void:
	print("[NetworkServer] Starting game for room %s" % room.code)

	# Transition room to "active"
	room.status = "active"

	# Initialize game state
	var game_state_dict = _initialize_game_state(room)
	var game_state = Types.GameState.from_dict(game_state_dict)

	# Store in active games
	active_games[room.code] = game_state

	# Broadcast to all players via NetworkClient
	for player in room.players:
		NetworkClient._send_game_started.rpc_id(player["peer_id"], game_state_dict)


## Server → Client: Room joined successfully
@rpc("authority", "call_remote", "reliable")
func _send_room_joined(room_data: Dictionary) -> void:
	pass  # Implemented on client


## Server → Client: Another peer joined the room
@rpc("authority", "call_remote", "reliable")
func _send_peer_joined(player_data: Dictionary) -> void:
	pass  # Implemented on client


## Server → Client: Player ready status changed
@rpc("authority", "call_remote", "reliable")
func _send_player_ready_changed(peer_id: int, ready: bool) -> void:
	pass  # Implemented on client


## Server → Client: Error message
@rpc("authority", "call_remote", "reliable")
func _send_error(message: String) -> void:
	pass  # Implemented on client


## Server → Client: Army submitted (Phase 3b)
@rpc("authority", "call_remote", "reliable")
func _send_army_submitted(peer_id: int, army_size: int) -> void:
	pass  # Implemented on client


## Server → Client: Game started (Phase 3b)
@rpc("authority", "call_remote", "reliable")
func _send_game_started(game_state: Dictionary) -> void:
	pass  # Implemented on client


## Server → Client: Action resolved (Phase 4)
@rpc("authority", "call_remote", "reliable")
func _send_action_resolved(action: Dictionary, result: Dictionary) -> void:
	pass  # Implemented on client


## Server → Client: State update (Phase 4)
@rpc("authority", "call_remote", "reliable")
func _send_state_update(state_data: Dictionary) -> void:
	pass  # Implemented on client


## Server → Client: Game ended (Phase 4)
@rpc("authority", "call_remote", "reliable")
func _send_game_ended(winner_seat: int, reason: String) -> void:
	pass  # Implemented on client


## Client RPC: Request a game action (Phase 4)
@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	var peer_id = multiplayer.get_remote_sender_id()

	var room = room_manager.get_room_for_peer(peer_id)
	if not room:
		_send_error_to_client(peer_id, "Not in a room")
		return

	if not active_games.has(room.code):
		_send_error_to_client(peer_id, "Game not started")
		return

	var state: Types.GameState = active_games[room.code]

	# Validate requesting player is the active player
	var player = room.get_player(peer_id)
	if player.is_empty():
		_send_error_to_client(peer_id, "Player not found")
		return

	if player["seat"] != state.active_seat:
		_send_error_to_client(peer_id, "Not your turn")
		return

	# Route action to appropriate handler
	var action_type = action_data.get("type", "")
	var result: Types.EngineResult = null

	match action_type:
		"place_unit":
			result = GameEngine.place_unit(
				state,
				action_data.get("unit_id", ""),
				action_data.get("x", -1),
				action_data.get("y", -1)
			)

		"confirm_placement":
			result = GameEngine.confirm_placement(state)

		"select_snob":
			result = GameEngine.select_snob(
				state,
				action_data.get("snob_id", "")
			)

		"declare_order":
			var blunder_die = _roll_d6()
			var move_dice = [_roll_d6(), _roll_d6()]
			result = GameEngine.declare_order(
				state,
				action_data.get("unit_id", ""),
				action_data.get("order_type", ""),
				blunder_die,
				move_dice
			)

		"declare_self_order":
			var blunder_die = _roll_d6()
			var move_dice = [_roll_d6(), _roll_d6()]
			result = GameEngine.declare_self_order(
				state,
				action_data.get("unit_id", ""),
				action_data.get("order_type", ""),
				blunder_die,
				move_dice
			)

		"execute_order":
			var params = action_data.get("params", {})
			# Charge: server rolls panic test + fearless + retreat dice for the target.
			if state.current_order_type == "charge" and not params.get("fizzle", false):
				params["panic_die"] = _roll_d6()
				params["fearless_die"] = _roll_d6()
				params["retreat_die"] = _roll_d6()
			# Shooting engagements can also trigger a retreat (v17 p.15).
			if state.current_order_type in ["volley_fire", "move_and_shoot"]:
				params["retreat_die"] = _roll_d6()
			var dice = _roll_execute_dice(state, params)
			result = GameEngine.execute_order(state, params, dice)

		_:
			_send_error_to_client(peer_id, "Unknown action type: " + action_type)
			return

	if not result.is_success():
		_send_error_to_client(peer_id, result.error)
		return

	# Update stored state
	active_games[room.code] = result.new_state

	# Check victory (also handles max-rounds tiebreak / draw)
	var victory = Objectives.check_victory(result.new_state)
	var game_over: bool = victory["winner"] != 0 or result.new_state.phase == "finished"
	if game_over:
		result.new_state.phase = "finished"
		result.new_state.winner_seat = victory["winner"]

	# Broadcast to all players via NetworkClient
	for p in room.players:
		NetworkClient._send_action_resolved.rpc_id(
			p["peer_id"],
			action_data,
			result.to_dict()
		)

		NetworkClient._send_state_update.rpc_id(
			p["peer_id"],
			result.new_state.to_dict()
		)

		if game_over:
			NetworkClient._send_game_ended.rpc_id(
				p["peer_id"],
				victory["winner"],
				victory["reason"]
			)


## Helper: Find a unit by ID in a game state
func _find_unit(state: Types.GameState, unit_id: String) -> Types.UnitState:
	for u in state.units:
		if u.id == unit_id:
			return u
	return null


## Helper: Roll a d6
func _roll_d6() -> int:
	return randi_range(1, 6)


## Helper: Roll the combat dice pool an execute_order requires, sized to the
## ordered unit and the declared order type. Charge sizing accounts for the
## full melee: both sides strike per bout, up to Combat.MELEE_MAX_BOUTS.
func _roll_execute_dice(state: Types.GameState, params: Dictionary) -> Array:
	var unit = _find_unit(state, state.current_order_unit_id)
	if unit == null:
		return []

	var num_dice = 0
	match state.current_order_type:
		"volley_fire", "move_and_shoot":
			# Shooting engagement: both sides may fire. Target dice added when
			# the target is known; otherwise over-roll with a symmetric pool.
			var att_dice = unit.model_count * 2
			var def_dice = att_dice
			var s_target = _find_unit(state, params.get("target_id", ""))
			if s_target != null:
				def_dice = s_target.model_count * 2
			num_dice = att_dice + def_dice
		"charge":
			# Worst case: attacker + defender each strike every bout. Target
			# may be unknown at roll time (fizzle path) — fall back to a
			# symmetric pool sized to the attacker.
			var atk_per_bout = unit.model_count * unit.base_stats.attacks * 2
			var def_per_bout = atk_per_bout
			var target = _find_unit(state, params.get("target_id", ""))
			if target != null:
				def_per_bout = target.model_count * target.base_stats.attacks * 2
			num_dice = (atk_per_bout + def_per_bout) * Combat.MELEE_MAX_BOUTS
		"march":
			num_dice = 0

	var dice: Array = []
	for i in range(num_dice):
		dice.append(_roll_d6())
	return dice


## Helper to send error to a specific client
func _send_error_to_client(peer_id: int, message: String) -> void:
	print("[NetworkServer] Sending error to peer %d: %s" % [peer_id, message])
	NetworkClient._send_error.rpc_id(peer_id, message)


## Helper: Initialize game state from room data (Phase 3b)
## Expands rosters into UnitState structures.
func _initialize_game_state(room) -> Dictionary:
	var units: Array = []
	var unit_id_counter: int = 0

	# Load ruleset for unit definitions
	var ruleset = Ruleset.new()
	ruleset.load_from_file("res://game/rulesets/v17.json")

	# Roll initiative — v17 core p.9: players roll off with a D6 each; ties
	# re-roll. Higher roll takes initiative.
	var initiative_seat: int = 1
	while true:
		var roll_1 := _roll_d6()
		var roll_2 := _roll_d6()
		if roll_1 > roll_2:
			initiative_seat = 1
			break
		elif roll_2 > roll_1:
			initiative_seat = 2
			break
		# Tie — re-roll.

	# Expand each player's roster into UnitStates
	for player in room.players:
		var roster_data = player["army"]
		if roster_data.is_empty():
			continue

		var roster = Types.Roster.from_dict(roster_data)

		for snob in roster.snobs:
			# Create Snob UnitState
			var snob_id = "unit_%d" % unit_id_counter
			unit_id_counter += 1

			var snob_def = ruleset.get_unit_type(snob.snob_type)
			if snob_def.is_empty():
				continue

			var snob_stats = snob_def["base_stats"]
			var snob_rules: Array = []
			if snob_def.has("special_rules"):
				for r in snob_def["special_rules"]:
					snob_rules.append(str(r))

			units.append({
				"id": snob_id,
				"owner_seat": player["seat"],
				"unit_type": snob.snob_type,
				"category": "snob",
				"model_count": 1,
				"max_models": 1,
				"base_stats": snob_stats,
				"equipment": snob.equipment,
				"special_rules": snob_rules,
				"panic_tokens": 0,
				"has_powder_smoke": false,
				"current_wounds": 0,
				"x": -1,
				"y": -1,
				"has_ordered": false,
				"is_dead": false,
				"snob_id": ""
			})

			# Create Follower UnitStates
			for follower in snob.followers:
				var f_id = "unit_%d" % unit_id_counter
				unit_id_counter += 1

				var f_def = ruleset.get_unit_type(follower.unit_type)
				if f_def.is_empty():
					continue

				var f_stats = f_def["base_stats"]
				var f_rules: Array = []
				if f_def.has("special_rules"):
					for r in f_def["special_rules"]:
						f_rules.append(str(r))

				units.append({
					"id": f_id,
					"owner_seat": player["seat"],
					"unit_type": follower.unit_type,
					"category": f_def.get("category", "infantry"),
					"model_count": f_def.get("model_count", 1),
					"max_models": f_def.get("model_count", 1),
					"base_stats": f_stats,
					"equipment": follower.equipment,
					"special_rules": f_rules,
					"panic_tokens": 0,
					"has_powder_smoke": false,
					"current_wounds": 0,
					"x": -1,
					"y": -1,
					"has_ordered": false,
					"is_dead": false,
					"snob_id": snob_id
				})

	# Objective placement. v17 core p.22: "Every scenario will present the
	# players with up to 5 objectives and instructions on how to place them."
	# Real scenarios drive count + layout + placement rules (players taking
	# turns to place). Until the scenario system lands (see memory note on
	# scenarios_future_design), we auto-place 5 markers evenly along the
	# centerline as a stand-in.
	var objectives: Array = []
	var centerline_y := 16  # Board is 48x32 (see battle.gd); midpoint.
	var xs := [8, 16, 24, 32, 40]
	for i in range(xs.size()):
		objectives.append({
			"id": "obj_%d" % i,
			"x": xs[i],
			"y": centerline_y,
			"captured_by": 0
		})

	return {
		"room_code": room.code,
		"phase": "placement",
		"current_round": 1,
		"max_rounds": 4,
		"active_seat": initiative_seat,
		"initiative_seat": initiative_seat,
		"units": units,
		"objectives": objectives,
		"action_log": [],
		"winner_seat": 0
	}
