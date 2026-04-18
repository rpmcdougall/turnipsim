extends Node
## ENet server listener — Phase 3.
## Exposes RPCs for clients to interact with the server.

@onready var room_manager: Node = get_parent().get_node("RoomManager")


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

	# Send room state back to creator
	var room = room_manager.get_room_for_peer(peer_id)
	_send_room_joined.rpc_id(peer_id, room.to_dict())


## Client RPC: Join an existing room
@rpc("any_peer", "call_remote", "reliable")
func join_room(code: String, display_name: String) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d requesting to join room %s (name: %s)" % [peer_id, code, display_name])

	var success = room_manager.join_room(peer_id, display_name, code)

	if not success:
		_send_error_to_client(peer_id, "Failed to join room " + code)
		return

	# Get room state and send to new player
	var room = room_manager.get_room_for_peer(peer_id)
	_send_room_joined.rpc_id(peer_id, room.to_dict())

	# Notify all other players in the room
	var new_player = room.get_player(peer_id)
	for player in room.players:
		if player["peer_id"] != peer_id:
			_send_peer_joined.rpc_id(player["peer_id"], new_player)


## Client RPC: Set ready status
@rpc("any_peer", "call_remote", "reliable")
func set_ready(ready: bool) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d set ready: %s" % [peer_id, ready])

	var success = room_manager.set_player_ready(peer_id, ready)

	if not success:
		_send_error_to_client(peer_id, "Failed to set ready status")
		return

	# Broadcast ready status to all players in the room
	var room = room_manager.get_room_for_peer(peer_id)
	if room:
		for player in room.players:
			_send_player_ready_changed.rpc_id(player["peer_id"], peer_id, ready)

		# Check if all players are ready
		if room.is_full() and room_manager.are_all_players_ready(room):
			print("[NetworkServer] All players in room %s are ready" % room.code)
			# Phase 3b will handle game_started broadcast


## Client RPC: Submit army (Phase 3b)
@rpc("any_peer", "call_remote", "reliable")
func submit_army(army_data: Array) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	print("[NetworkServer] Peer %d submitting army (%d units)" % [peer_id, army_data.size()])

	var room = room_manager.get_room_for_peer(peer_id)
	if not room:
		_send_error_to_client(peer_id, "Not in a room")
		return

	# Validate army size
	if army_data.size() < 5 or army_data.size() > 10:
		_send_error_to_client(peer_id, "Invalid army size (must be 5-10 units)")
		return

	# Store army in room state
	var player = room.get_player(peer_id)
	if player.is_empty():
		_send_error_to_client(peer_id, "Player not found in room")
		return

	player["army"] = army_data

	# Broadcast to all players in room
	for p in room.players:
		_send_army_submitted.rpc_id(p["peer_id"], peer_id, army_data.size())

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


## Helper: Start the game (Phase 3b)
func _start_game(room) -> void:
	print("[NetworkServer] Starting game for room %s" % room.code)

	# Transition room to "active"
	room.status = "active"

	# Initialize game state
	var game_state = _initialize_game_state(room)

	# Broadcast to all players
	for player in room.players:
		_send_game_started.rpc_id(player["peer_id"], game_state)


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


## Helper to send error to a specific client
func _send_error_to_client(peer_id: int, message: String) -> void:
	print("[NetworkServer] Sending error to peer %d: %s" % [peer_id, message])
	_send_error.rpc_id(peer_id, message)


## Helper: Initialize game state from room data (Phase 3b)
func _initialize_game_state(room) -> Dictionary:
	var units: Array = []
	var unit_id_counter: int = 0

	# Convert armies to UnitState structures
	for player in room.players:
		for unit_dict in player["army"]:
			# Create UnitState data
			var unit_state = {
				"id": "unit_%d" % unit_id_counter,
				"owner_seat": player["seat"],
				"name": unit_dict["name"],
				"archetype": unit_dict["archetype"],
				"base_stats": unit_dict["base_stats"],
				"weapon": unit_dict["weapon"],
				"mutations": unit_dict.get("mutations", []),
				"max_wounds": unit_dict["base_stats"]["wounds"],  # Will be adjusted by mutations later
				"current_wounds": unit_dict["base_stats"]["wounds"],
				"x": -1,  # Not placed yet
				"y": -1,
				"has_activated": false,
				"is_dead": false
			}
			units.append(unit_state)
			unit_id_counter += 1

	return {
		"room_code": room.code,
		"phase": "placement",  # Start with placement phase
		"current_turn": 1,
		"active_seat": 1,  # Seat 1 starts
		"units": units,
		"action_log": [],
		"winner_seat": 0
	}
