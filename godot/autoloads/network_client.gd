extends Node
## Client→Server RPC interface (autoload).
## Provides RPC methods that clients call to communicate with server.
## This node exists on both client and server at the same path (/root/NetworkClient).

## On server, forward to NetworkServer
var network_server: Node = null

## Signals for client to listen to (server→client events)
signal room_joined(room_data: Dictionary)
signal peer_joined(player_data: Dictionary)
signal player_ready_changed(peer_id: int, ready: bool)
signal error_received(message: String)
signal army_submitted(peer_id: int, army_size: int)
signal game_started(game_state: Dictionary)
signal action_resolved(action: Dictionary, result: Dictionary)
signal state_update(game_state: Dictionary)
signal game_ended(winner_seat: int, reason: String)


func _ready() -> void:
	if NetworkManager.is_server:
		# Wait for server to be ready, then get reference
		await get_tree().process_frame
		await get_tree().process_frame
		network_server = get_node_or_null("/root/ServerMain/NetworkServer")
		if network_server:
			print("[NetworkClient] Connected to NetworkServer")
		else:
			push_warning("[NetworkClient] NetworkServer not found on server")


## Client RPC: Create a new room
@rpc("any_peer", "call_remote", "reliable")
func create_room(display_name: String) -> void:
	if NetworkManager.is_server and network_server:
		network_server.create_room(display_name)


## Client RPC: Join an existing room
@rpc("any_peer", "call_remote", "reliable")
func join_room(code: String, display_name: String) -> void:
	if NetworkManager.is_server and network_server:
		network_server.join_room(code, display_name)


## Client RPC: Set ready status
@rpc("any_peer", "call_remote", "reliable")
func set_ready(ready: bool) -> void:
	if NetworkManager.is_server and network_server:
		network_server.set_ready(ready)


## Client RPC: Submit roster (Phase 3b)
@rpc("any_peer", "call_remote", "reliable")
func submit_army(roster_data: Dictionary) -> void:
	if NetworkManager.is_server and network_server:
		network_server.submit_army(roster_data)


## Client RPC: Start solo testing mode
@rpc("any_peer", "call_remote", "reliable")
func start_solo_test() -> void:
	if NetworkManager.is_server and network_server:
		network_server.start_solo_test()


## Client RPC: Request game action (Phase 4)
@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	if NetworkManager.is_server and network_server:
		network_server.request_action(action_data)


# =============================================================================
# Server → Client RPCs (called by server, received by all clients)
# =============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_room_joined(room_data: Dictionary) -> void:
	room_joined.emit(room_data)


@rpc("authority", "call_remote", "reliable")
func _send_peer_joined(player_data: Dictionary) -> void:
	peer_joined.emit(player_data)


@rpc("authority", "call_remote", "reliable")
func _send_player_ready_changed(peer_id: int, ready: bool) -> void:
	player_ready_changed.emit(peer_id, ready)


@rpc("authority", "call_remote", "reliable")
func _send_error(message: String) -> void:
	error_received.emit(message)


@rpc("authority", "call_remote", "reliable")
func _send_army_submitted(peer_id: int, army_size: int) -> void:
	army_submitted.emit(peer_id, army_size)


@rpc("authority", "call_remote", "reliable")
func _send_game_started(game_state: Dictionary) -> void:
	game_started.emit(game_state)


@rpc("authority", "call_remote", "reliable")
func _send_action_resolved(action: Dictionary, result: Dictionary) -> void:
	action_resolved.emit(action, result)


@rpc("authority", "call_remote", "reliable")
func _send_state_update(game_state: Dictionary) -> void:
	state_update.emit(game_state)


@rpc("authority", "call_remote", "reliable")
func _send_game_ended(winner: int, reason: String) -> void:
	game_ended.emit(winner, reason)
