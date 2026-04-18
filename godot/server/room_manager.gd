extends Node
## Manages game rooms / lobbies — Phase 3.

## Room state data structure
class RoomState:
	var code: String
	var status: String  # "lobby" | "active" | "finished"
	var players: Array[Dictionary] = []  # {peer_id, seat, display_name, ready, army}
	var max_players: int = 2
	var created_at: float

	func _init(p_code: String) -> void:
		code = p_code
		status = "lobby"
		created_at = Time.get_unix_time_from_system()

	func add_player(peer_id: int, display_name: String) -> bool:
		if players.size() >= max_players:
			return false

		# Assign next available seat
		var seat = players.size() + 1
		players.append({
			"peer_id": peer_id,
			"seat": seat,
			"display_name": display_name,
			"ready": false,
			"army": []
		})
		return true

	func remove_player(peer_id: int) -> void:
		for i in range(players.size()):
			if players[i]["peer_id"] == peer_id:
				players.remove_at(i)
				return

	func get_player(peer_id: int) -> Dictionary:
		for player in players:
			if player["peer_id"] == peer_id:
				return player
		return {}

	func is_full() -> bool:
		return players.size() >= max_players

	func is_empty() -> bool:
		return players.is_empty()

	func to_dict() -> Dictionary:
		return {
			"code": code,
			"status": status,
			"players": players,
			"max_players": max_players
		}


# Room storage: code -> RoomState
var rooms: Dictionary = {}

# Player to room mapping: peer_id -> room_code
var player_rooms: Dictionary = {}

# Characters allowed in room codes (exclude I, O, 0, 1 for clarity)
const ROOM_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH = 6


## Generate a unique 6-character room code
func generate_room_code() -> String:
	var code = ""
	for i in range(ROOM_CODE_LENGTH):
		var idx = randi() % ROOM_CODE_CHARS.length()
		code += ROOM_CODE_CHARS[idx]

	# If by chance this code exists, recurse
	if rooms.has(code):
		return generate_room_code()

	return code


## Create a new room and add the creator as the first player
func create_room(peer_id: int, display_name: String) -> String:
	# Check if player is already in a room
	if player_rooms.has(peer_id):
		push_warning("[RoomManager] Peer %d already in room %s" % [peer_id, player_rooms[peer_id]])
		return ""

	var code = generate_room_code()
	var room = RoomState.new(code)

	if not room.add_player(peer_id, display_name):
		push_error("[RoomManager] Failed to add creator to room")
		return ""

	rooms[code] = room
	player_rooms[peer_id] = code

	print("[RoomManager] Room %s created by peer %d (%s)" % [code, peer_id, display_name])
	return code


## Join an existing room
func join_room(peer_id: int, display_name: String, code: String) -> bool:
	# Check if player is already in a room
	if player_rooms.has(peer_id):
		push_warning("[RoomManager] Peer %d already in room %s" % [peer_id, player_rooms[peer_id]])
		return false

	# Check if room exists
	if not rooms.has(code):
		print("[RoomManager] Room %s not found" % code)
		return false

	var room: RoomState = rooms[code]

	# Check if room is full
	if room.is_full():
		print("[RoomManager] Room %s is full" % code)
		return false

	# Add player to room
	if not room.add_player(peer_id, display_name):
		push_error("[RoomManager] Failed to add peer %d to room %s" % [peer_id, code])
		return false

	player_rooms[peer_id] = code
	print("[RoomManager] Peer %d (%s) joined room %s" % [peer_id, display_name, code])
	return true


## Get the room for a given peer
func get_room_for_peer(peer_id: int) -> RoomState:
	if not player_rooms.has(peer_id):
		return null

	var code = player_rooms[peer_id]
	return rooms.get(code, null)


## Handle peer disconnection
func handle_peer_disconnect(peer_id: int) -> void:
	if not player_rooms.has(peer_id):
		return

	var code = player_rooms[peer_id]
	var room: RoomState = rooms.get(code)

	if not room:
		return

	print("[RoomManager] Removing peer %d from room %s" % [peer_id, code])
	room.remove_player(peer_id)
	player_rooms.erase(peer_id)

	# If room is empty, delete it
	if room.is_empty():
		print("[RoomManager] Room %s is empty, deleting" % code)
		rooms.erase(code)


## Set player ready status
func set_player_ready(peer_id: int, ready: bool) -> bool:
	var room = get_room_for_peer(peer_id)
	if not room:
		return false

	var player = room.get_player(peer_id)
	if player.is_empty():
		return false

	player["ready"] = ready
	print("[RoomManager] Peer %d ready status: %s" % [peer_id, ready])
	return true


## Check if all players in a room are ready
func are_all_players_ready(room: RoomState) -> bool:
	if room.players.is_empty():
		return false

	for player in room.players:
		if not player["ready"]:
			return false

	return true
