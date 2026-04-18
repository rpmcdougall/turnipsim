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


## Helper to send error to a specific client
func _send_error_to_client(peer_id: int, message: String) -> void:
	print("[NetworkServer] Sending error to peer %d: %s" % [peer_id, message])
	_send_error.rpc_id(peer_id, message)
