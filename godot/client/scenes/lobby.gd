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

# Army UI nodes (TODO: Add these to lobby.tscn scene)
@onready var roll_army_button = $MarginContainer/VBoxContainer/InRoomPanel/VBoxContainer/RollArmyButton
@onready var submit_army_button = $MarginContainer/VBoxContainer/InRoomPanel/VBoxContainer/SubmitArmyButton
@onready var army_display = $MarginContainer/VBoxContainer/InRoomPanel/VBoxContainer/ArmyScrollContainer/ArmyDisplay

# State
var is_connected: bool = false
var is_in_room: bool = false
var current_room_data: Dictionary = {}
var my_peer_id: int = 0

# Army state
var ruleset: Ruleset = null
var my_army: Array[Types.Unit] = []
var has_submitted_army: bool = false


func _ready() -> void:
	# Load ruleset (cache for army rolling)
	ruleset = Ruleset.new()
	var error = ruleset.load_from_file("res://game/rulesets/mvp.json")
	if error:
		push_error("[Lobby] Failed to load ruleset: " + error)
		status_label.text = "Error: Failed to load ruleset"
		return

	# Set up multiplayer signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Initialize army UI
	if submit_army_button:
		submit_army_button.disabled = true


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
	NetworkManager.reset_seat()  # Clear seat assignment
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


## Roll Army button
func _on_roll_army_button_pressed() -> void:
	if not is_in_room or not ruleset:
		return

	print("[Lobby] Rolling army...")

	# Roll a new army using real RNG
	var roller = ArmyRoller.new()
	my_army = roller.roll_army(ruleset, func(): return randi_range(1, 6))

	# Display the army
	_display_army()

	# Enable submit button
	if submit_army_button:
		submit_army_button.disabled = false

	status_label.text = "Army rolled! (%d units)" % my_army.size()


## Display the rolled army
func _display_army() -> void:
	if not army_display:
		return

	# Clear previous display
	for child in army_display.get_children():
		child.queue_free()

	# Display army info
	var header = Label.new()
	header.text = "Your Army: %d units" % my_army.size()
	header.add_theme_font_size_override("font_size", 16)
	army_display.add_child(header)

	# Display each unit (compact version)
	for i in range(my_army.size()):
		var unit = my_army[i]
		var unit_panel = _create_unit_panel(i + 1, unit)
		army_display.add_child(unit_panel)


## Create a panel for displaying a unit (reused from test_roll.gd)
func _create_unit_panel(number: int, unit: Types.Unit) -> PanelContainer:
	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	# Unit name and archetype
	var name_label = Label.new()
	name_label.text = "[%d] %s (%s)" % [number, unit.name, unit.archetype]
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)

	# Stats
	var effective = unit.get_effective_stats()
	var stats_label = Label.new()
	stats_label.text = "M%d S%d C%d R%d W%d Sv%d+" % [
		effective.movement,
		effective.shooting,
		effective.combat,
		effective.resolve,
		effective.wounds,
		effective.save
	]
	vbox.add_child(stats_label)

	# Weapon
	var weapon_label = Label.new()
	weapon_label.text = "%s (%s)" % [unit.weapon.name, unit.weapon.type]
	vbox.add_child(weapon_label)

	return panel


## Submit Army button
func _on_submit_army_button_pressed() -> void:
	if not is_in_room or my_army.is_empty() or has_submitted_army:
		return

	print("[Lobby] Submitting army (%d units)" % my_army.size())

	# Serialize army to dictionaries
	var army_data: Array = []
	for unit in my_army:
		army_data.append(unit.to_dict())

	# Send to server
	submit_army.rpc_id(1, army_data)
	has_submitted_army = true

	# Disable buttons
	if roll_army_button:
		roll_army_button.disabled = true
	if submit_army_button:
		submit_army_button.disabled = true

	status_label.text = "Army submitted! Waiting for opponent..."


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


@rpc("any_peer", "call_remote", "reliable")
func submit_army(army_data: Array) -> void:
	pass  # Server handles this


# =============================================================================
# RPCs - Server calls to client
# =============================================================================

@rpc("authority", "call_remote", "reliable")
func _send_room_joined(room_data: Dictionary) -> void:
	print("[Lobby] Joined room: %s" % room_data["code"])
	current_room_data = room_data
	is_in_room = true

	# Extract and store our seat assignment
	if room_data.has("players"):
		for player in room_data["players"]:
			if player["peer_id"] == my_peer_id:
				NetworkManager.set_my_seat(player["seat"])
				break

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


@rpc("authority", "call_remote", "reliable")
func _send_army_submitted(peer_id: int, army_size: int) -> void:
	print("[Lobby] Peer %d submitted army (%d units)" % [peer_id, army_size])

	# Update UI to show submission status
	if peer_id == my_peer_id:
		status_label.text = "Army submitted! Waiting for opponent..."
	else:
		status_label.text = "Opponent submitted their army (%d units)!" % army_size


@rpc("authority", "call_remote", "reliable")
func _send_game_started(game_state: Dictionary) -> void:
	print("[Lobby] Game starting! Transitioning to battle... (My seat: %d)" % NetworkManager.my_seat)
	status_label.text = "Game starting!"

	# my_seat is already stored in NetworkManager from _send_room_joined
	# The battle scene will read it from there

	# Transition to battle scene
	await get_tree().create_timer(0.5).timeout  # Brief delay for feedback
	get_tree().change_scene_to_file("res://client/scenes/battle.tscn")
