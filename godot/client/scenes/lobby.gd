extends Control
## Lobby — shows connected players, army previews, ready state.

const PORT = 9999

# UI nodes
@onready var connection_panel = $MarginContainer/VBoxContainer/ConnectionPanel
@onready var room_panel = $MarginContainer/VBoxContainer/RoomPanel
@onready var in_room_panel = $MarginContainer/VBoxContainer/InRoomPanel

@onready var server_ip_input = $MarginContainer/VBoxContainer/ConnectionPanel/VBoxContainer/HBoxContainer/ServerIPInput
@onready var player_name_input = $MarginContainer/VBoxContainer/ConnectionPanel/VBoxContainer/HBoxContainer2/PlayerNameInput
@onready var status_label = $MarginContainer/VBoxContainer/ConnectionPanel/VBoxContainer/StatusLabel

@onready var room_code_input = $MarginContainer/VBoxContainer/RoomPanel/VBoxContainer/HBoxContainer2/RoomCodeInput
@onready var room_code_display = $MarginContainer/VBoxContainer/InRoomPanel/VBoxContainer/RoomCodeDisplay
@onready var players_list = $MarginContainer/VBoxContainer/InRoomPanel/VBoxContainer/PlayersList
@onready var ready_button = $MarginContainer/VBoxContainer/InRoomPanel/VBoxContainer/ReadyButton

# State
var is_connected: bool = false
var is_in_room: bool = false
var current_room_data: Dictionary = {}
var my_peer_id: int = 0


func _ready() -> void:
	# Set up multiplayer signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Connect to server button
func _on_connect_button_pressed() -> void:
	if is_connected:
		_disconnect_from_server()
		return

	var server_ip = server_ip_input.text.strip_edges()
	if server_ip.is_empty():
		status_label.text = "Please enter server IP"
		return

	var player_name = player_name_input.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "Please enter your name"
		return

	print("[Lobby] Connecting to %s:%d..." % [server_ip, PORT])
	status_label.text = "Connecting..."

	# Create ENet client peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(server_ip, PORT)

	if error != OK:
		status_label.text = "Failed to connect: " + str(error)
		print("[Lobby] Connection failed: %s" % error)
		return

	multiplayer.multiplayer_peer = peer


func _disconnect_from_server() -> void:
	print("[Lobby] Disconnecting from server")
	multiplayer.multiplayer_peer = null
	is_connected = false
	is_in_room = false
	status_label.text = "Disconnected"
	_show_connection_panel()


func _on_connected_to_server() -> void:
	print("[Lobby] Connected to server!")
	is_connected = true
	my_peer_id = multiplayer.get_unique_id()
	status_label.text = "Connected (ID: %d)" % my_peer_id
	_show_room_panel()


func _on_connection_failed() -> void:
	print("[Lobby] Connection failed")
	status_label.text = "Connection failed"
	is_connected = false


func _on_server_disconnected() -> void:
	print("[Lobby] Server disconnected")
	status_label.text = "Server disconnected"
	is_connected = false
	is_in_room = false
	_show_connection_panel()


## Create room button
func _on_create_room_button_pressed() -> void:
	if not is_connected:
		return

	var player_name = player_name_input.text.strip_edges()
	print("[Lobby] Requesting room creation (name: %s)" % player_name)

	# Call server RPC
	create_room.rpc_id(1, player_name)


## Join room button
func _on_join_room_button_pressed() -> void:
	if not is_connected:
		return

	var code = room_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Room code must be 6 characters"
		return

	var player_name = player_name_input.text.strip_edges()
	print("[Lobby] Requesting to join room %s (name: %s)" % [code, player_name])

	# Call server RPC
	join_room.rpc_id(1, code, player_name)


## Ready button toggled
func _on_ready_button_toggled(toggled_on: bool) -> void:
	if not is_in_room:
		return

	print("[Lobby] Setting ready: %s" % toggled_on)
	set_ready.rpc_id(1, toggled_on)


## Leave room button
func _on_leave_room_button_pressed() -> void:
	_disconnect_from_server()


## Back button
func _on_back_button_pressed() -> void:
	if is_connected:
		_disconnect_from_server()
	get_tree().change_scene_to_file("res://client/main.tscn")


## Show/hide UI panels based on state
func _show_connection_panel() -> void:
	connection_panel.visible = true
	room_panel.visible = false
	in_room_panel.visible = false


func _show_room_panel() -> void:
	connection_panel.visible = true  # Keep visible to show connection status
	room_panel.visible = true
	in_room_panel.visible = false


func _show_in_room_panel() -> void:
	connection_panel.visible = true  # Keep visible to show connection status
	room_panel.visible = false
	in_room_panel.visible = true


## Update players list display
func _update_players_list() -> void:
	# Clear existing labels
	for child in players_list.get_children():
		child.queue_free()

	if not current_room_data.has("players"):
		return

	# Add labels for each player
	for player in current_room_data["players"]:
		var label = Label.new()
		var ready_text = " [READY]" if player["ready"] else ""
		label.text = "%d. %s%s" % [player["seat"], player["display_name"], ready_text]
		players_list.add_child(label)


# =============================================================================
# RPCs - Client calls to server
# =============================================================================

@rpc("any_peer", "call_remote", "reliable")
func create_room(display_name: String) -> void:
	pass  # Server handles this


@rpc("any_peer", "call_remote", "reliable")
func join_room(code: String, display_name: String) -> void:
	pass  # Server handles this


@rpc("any_peer", "call_remote", "reliable")
func set_ready(ready: bool) -> void:
	pass  # Server handles this


# =============================================================================
# RPCs - Server calls to client
# =============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_room_joined(room_data: Dictionary) -> void:
	print("[Lobby] Joined room: %s" % room_data["code"])
	current_room_data = room_data
	is_in_room = true

	room_code_display.text = "Room: %s" % room_data["code"]
	_update_players_list()
	_show_in_room_panel()


@rpc("authority", "call_remote", "reliable")
func _send_peer_joined(player_data: Dictionary) -> void:
	print("[Lobby] Peer joined: %s" % player_data["display_name"])

	# Add the new player to our local room data
	if current_room_data.has("players"):
		current_room_data["players"].append(player_data)
		_update_players_list()


@rpc("authority", "call_remote", "reliable")
func _send_player_ready_changed(peer_id: int, ready: bool) -> void:
	print("[Lobby] Peer %d ready status: %s" % [peer_id, ready])

	# Update player ready status in our local room data
	if current_room_data.has("players"):
		for player in current_room_data["players"]:
			if player["peer_id"] == peer_id:
				player["ready"] = ready
				break
		_update_players_list()


@rpc("authority", "call_remote", "reliable")
func _send_error(message: String) -> void:
	print("[Lobby] Error from server: %s" % message)
	status_label.text = "Error: " + message
