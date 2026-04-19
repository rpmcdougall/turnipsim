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

# Army UI nodes (created programmatically if not in scene)
var roll_army_button: Button = null
var submit_army_button: Button = null
var army_display: VBoxContainer = null
var waiting_label: Label = null
var start_solo_button: Button = null

# State
var is_connected: bool = false
var is_in_room: bool = false
var current_room_data: Dictionary = {}
var my_peer_id: int = 0

# Army state
var ruleset: Ruleset = null
var my_roster: Types.Roster = null
var has_submitted_army: bool = false


func _ready() -> void:
	# Load ruleset (cache for army rolling)
	ruleset = Ruleset.new()
	var error = ruleset.load_from_file("res://game/rulesets/v17.json")
	if error:
		push_error("[Lobby] Failed to load ruleset: " + error)
		status_label.text = "Error: Failed to load ruleset"
		return

	# Set up multiplayer signals
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Set up NetworkClient signals (server→client events)
	NetworkClient.room_joined.connect(_on_room_joined)
	NetworkClient.peer_joined.connect(_on_peer_joined)
	NetworkClient.player_ready_changed.connect(_on_player_ready_changed)
	NetworkClient.error_received.connect(_on_error_received)
	NetworkClient.army_submitted.connect(_on_army_submitted)
	NetworkClient.game_started.connect(_on_game_started)

	# Ensure army UI nodes exist (create programmatically if needed)
	_ensure_army_ui_exists()

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

	# Call server RPC via NetworkClient autoload
	NetworkClient.create_room.rpc_id(1, player_name)


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

	# Call server RPC via NetworkClient autoload
	NetworkClient.join_room.rpc_id(1, code, player_name)


## Ready button toggled
func _on_ready_button_toggled(toggled_on: bool) -> void:
	if not is_in_room:
		return

	print("[Lobby] Setting ready: %s" % toggled_on)
	NetworkClient.set_ready.rpc_id(1, toggled_on)


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
	print("[Lobby] Switching to in-room panel")
	connection_panel.visible = true  # Keep visible to show connection status
	room_panel.visible = false
	in_room_panel.visible = true
	print("[Lobby] in_room_panel.visible = %s" % in_room_panel.visible)

	# Debug: Check if roll_army_button exists and is visible
	if roll_army_button:
		print("[Lobby] roll_army_button exists, visible=%s, disabled=%s" % [roll_army_button.visible, roll_army_button.disabled])

		# Check signal connections
		var connections = roll_army_button.pressed.get_connections()
		print("[Lobby] roll_army_button.pressed has %d connections" % connections.size())
		for conn in connections:
			print("[Lobby]   -> connected to: %s.%s" % [conn["callable"].get_object(), conn["callable"].get_method()])
	else:
		print("[Lobby] roll_army_button is NULL!")


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

	# Update waiting status
	_update_waiting_status()


## Select Army button — picks the first preset roster for now.
## DECISION: Phase 5b will replace this with a full roster builder UI.
func _on_roll_army_button_pressed() -> void:
	print("[Lobby] Select Army button clicked! is_in_room=%s, ruleset=%s" % [is_in_room, ruleset != null])

	if not is_in_room:
		return
	if not ruleset:
		return

	# For now, use the first preset roster from the ruleset
	# Phase 5b will add a proper roster builder UI
	var presets_data = _get_presets_from_ruleset()
	if presets_data.is_empty():
		status_label.text = "No presets available"
		return

	# Pick a random preset for variety
	var preset = presets_data[randi() % presets_data.size()]
	my_roster = Types.Roster.from_dict(preset["roster"])

	print("[Lobby] Selected preset: %s (%d units)" % [preset["name"], my_roster.get_unit_count()])

	# Display the roster
	_display_army()

	# Enable submit button
	if submit_army_button:
		submit_army_button.disabled = false
		submit_army_button.visible = true

	status_label.text = "Roster selected: %s (%d units)" % [preset["name"], my_roster.get_unit_count()]


## Get presets from the loaded ruleset JSON (re-parse to access presets field).
func _get_presets_from_ruleset() -> Array:
	var file = FileAccess.open("res://game/rulesets/v17.json", FileAccess.READ)
	if not file:
		return []
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return []
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY or not data.has("presets"):
		return []
	return data["presets"]


## Display the selected roster
func _display_army() -> void:
	if not army_display or not my_roster:
		return

	for child in army_display.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Your Regiment: %d units" % my_roster.get_unit_count()
	header.add_theme_font_size_override("font_size", 16)
	army_display.add_child(header)

	var unit_num = 0
	for snob in my_roster.snobs:
		unit_num += 1
		var snob_panel = _create_roster_entry_panel(unit_num, snob.snob_type, snob.equipment, true)
		army_display.add_child(snob_panel)

		for follower in snob.followers:
			unit_num += 1
			var f_panel = _create_roster_entry_panel(unit_num, follower.unit_type, follower.equipment, false)
			army_display.add_child(f_panel)


func _create_roster_entry_panel(number: int, unit_type: String, equipment: String, is_snob: bool) -> PanelContainer:
	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var name_label = Label.new()
	var prefix = "  " if not is_snob else ""
	name_label.text = "%s[%d] %s" % [prefix, number, unit_type]
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)

	# Show stats from ruleset if available
	if ruleset:
		var unit_def = ruleset.get_unit_type(unit_type)
		if not unit_def.is_empty():
			var stats = unit_def["base_stats"]
			var stats_label = Label.new()
			stats_label.text = "%sM%d A%d I%d+ W%d V%d+ | %s | %d models" % [
				prefix, stats["movement"], stats["attacks"], stats["inaccuracy"],
				stats["wounds"], stats["vulnerability"], equipment,
				unit_def["model_count"]
			]
			vbox.add_child(stats_label)

	return panel


## Ensure army UI nodes exist (create programmatically if missing from .tscn)
func _ensure_army_ui_exists() -> void:
	print("[Lobby] _ensure_army_ui_exists() called")

	# Find the InRoomPanel VBoxContainer
	var in_room_vbox = in_room_panel.get_node_or_null("VBoxContainer")
	if not in_room_vbox:
		push_error("[Lobby] InRoomPanel/VBoxContainer not found")
		return

	# Try to get nodes from scene first
	roll_army_button = in_room_vbox.get_node_or_null("RollArmyButton")
	submit_army_button = in_room_vbox.get_node_or_null("SubmitArmyButton")

	print("[Lobby] Found existing nodes: roll=%s, submit=%s" % [roll_army_button != null, submit_army_button != null])

	var scroll_container = in_room_vbox.get_node_or_null("ArmyScrollContainer")
	if scroll_container:
		army_display = scroll_container.get_node_or_null("ArmyDisplay")

	# If they exist, connect signals and we're done
	if roll_army_button != null and submit_army_button != null and army_display != null:
		print("[Lobby] Army UI nodes already exist in scene, connecting signals")

		# Connect signals if not already connected
		if not roll_army_button.pressed.is_connected(_on_roll_army_button_pressed):
			print("[Lobby] Connecting roll_army_button.pressed signal")
			roll_army_button.pressed.connect(_on_roll_army_button_pressed)
		else:
			print("[Lobby] roll_army_button.pressed already connected")

		if not submit_army_button.pressed.is_connected(_on_submit_army_button_pressed):
			print("[Lobby] Connecting submit_army_button.pressed signal")
			submit_army_button.pressed.connect(_on_submit_army_button_pressed)
		else:
			print("[Lobby] submit_army_button.pressed already connected")

		return

	print("[Lobby] Creating army UI nodes programmatically...")

	# Create RollArmyButton if needed
	if not roll_army_button:
		print("[Lobby] Creating new RollArmyButton")
		roll_army_button = Button.new()
		roll_army_button.name = "RollArmyButton"
		roll_army_button.text = "Roll Army"
		roll_army_button.custom_minimum_size = Vector2(0, 40)
		in_room_vbox.add_child(roll_army_button)

	# Connect signal (whether new or existing)
	if roll_army_button and not roll_army_button.pressed.is_connected(_on_roll_army_button_pressed):
		print("[Lobby] Connecting roll_army_button.pressed signal")
		roll_army_button.pressed.connect(_on_roll_army_button_pressed)

	# Create ArmyScrollContainer
	if not scroll_container:
		scroll_container = ScrollContainer.new()
		scroll_container.name = "ArmyScrollContainer"
		scroll_container.custom_minimum_size = Vector2(0, 120)
		scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		in_room_vbox.add_child(scroll_container)

	# Create ArmyDisplay (VBoxContainer inside ScrollContainer)
	if not army_display:
		army_display = VBoxContainer.new()
		army_display.name = "ArmyDisplay"
		army_display.size_flags_horizontal = Control.SIZE_FILL
		army_display.size_flags_vertical = Control.SIZE_FILL
		scroll_container.add_child(army_display)

	# Create SubmitArmyButton if needed
	if not submit_army_button:
		print("[Lobby] Creating new SubmitArmyButton")
		submit_army_button = Button.new()
		submit_army_button.name = "SubmitArmyButton"
		submit_army_button.text = "Submit Army"
		submit_army_button.disabled = true  # Enabled after rolling
		submit_army_button.custom_minimum_size = Vector2(0, 40)
		in_room_vbox.add_child(submit_army_button)

	# Connect signal (whether new or existing)
	if submit_army_button and not submit_army_button.pressed.is_connected(_on_submit_army_button_pressed):
		print("[Lobby] Connecting submit_army_button.pressed signal")
		submit_army_button.pressed.connect(_on_submit_army_button_pressed)

	# Create waiting status label
	if not waiting_label:
		waiting_label = Label.new()
		waiting_label.name = "WaitingLabel"
		waiting_label.text = ""
		waiting_label.visible = false
		waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		waiting_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))  # Yellow
		in_room_vbox.add_child(waiting_label)

	# Create Start Solo button (for testing)
	if not start_solo_button:
		start_solo_button = Button.new()
		start_solo_button.name = "StartSoloButton"
		start_solo_button.text = "Start Solo (Testing)"
		start_solo_button.visible = false
		start_solo_button.custom_minimum_size = Vector2(0, 40)
		start_solo_button.pressed.connect(_on_start_solo_button_pressed)
		in_room_vbox.add_child(start_solo_button)

	print("[Lobby] Army UI nodes created successfully")


## Submit Army button
func _on_submit_army_button_pressed() -> void:
	if not is_in_room or not my_roster or has_submitted_army:
		return

	print("[Lobby] Submitting roster (%d units)" % my_roster.get_unit_count())

	# Send roster as dictionary to server
	NetworkClient.submit_army.rpc_id(1, my_roster.to_dict())
	has_submitted_army = true

	# Disable buttons
	if roll_army_button:
		roll_army_button.disabled = true
	if submit_army_button:
		submit_army_button.disabled = true

	status_label.text = "Army submitted! Waiting for opponent..."

	# Update waiting status (may show solo test button)
	_update_waiting_status()


## Update waiting status label and solo test button visibility
func _update_waiting_status() -> void:
	if not waiting_label or not start_solo_button:
		print("[Lobby] _update_waiting_status: waiting UI nodes not found")
		return

	if not is_in_room or not current_room_data.has("players"):
		print("[Lobby] _update_waiting_status: not in room or no players data")
		waiting_label.visible = false
		start_solo_button.visible = false
		return

	var player_count = current_room_data["players"].size()
	print("[Lobby] _update_waiting_status: player_count=%d, has_submitted_army=%s" % [player_count, has_submitted_army])

	# Show waiting message if we've submitted army but game hasn't started
	# (Either alone waiting for player 2, or with player 2 but they haven't submitted yet)
	if has_submitted_army:
		print("[Lobby] Showing waiting indicator and solo button")
		waiting_label.text = "⏳ Waiting for Player 2 to join and submit army..." if player_count == 1 else "⏳ Waiting for opponent to submit army..."
		waiting_label.visible = true
		# Only show solo button if alone
		start_solo_button.visible = (player_count == 1)
	else:
		print("[Lobby] Hiding waiting indicator - haven't submitted army yet")
		waiting_label.visible = false
		start_solo_button.visible = false


## Start Solo button handler
func _on_start_solo_button_pressed() -> void:
	if not is_in_room or not has_submitted_army:
		return

	print("[Lobby] Requesting solo test start")
	NetworkClient.start_solo_test.rpc_id(1)

	# Hide the button and update status
	if start_solo_button:
		start_solo_button.visible = false
	if waiting_label:
		waiting_label.text = "Starting solo test..."
	status_label.text = "Starting solo test..."


# =============================================================================
# Signal handlers - Server→Client events via NetworkClient
# =============================================================================

func _on_room_joined(room_data: Dictionary) -> void:
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


func _on_peer_joined(player_data: Dictionary) -> void:
	print("[Lobby] Peer joined: %s" % player_data["display_name"])

	# Add the new player to our local room data
	if current_room_data.has("players"):
		current_room_data["players"].append(player_data)
		_update_players_list()


func _on_player_ready_changed(peer_id: int, ready: bool) -> void:
	print("[Lobby] Peer %d ready status: %s" % [peer_id, ready])

	# Update player ready status in our local room data
	if current_room_data.has("players"):
		for player in current_room_data["players"]:
			if player["peer_id"] == peer_id:
				player["ready"] = ready
				break
		_update_players_list()


func _on_error_received(message: String) -> void:
	print("[Lobby] Error from server: %s" % message)
	status_label.text = "Error: " + message


func _on_army_submitted(peer_id: int, army_size: int) -> void:
	print("[Lobby] Peer %d submitted army (%d units)" % [peer_id, army_size])

	# Update UI to show submission status
	if peer_id == my_peer_id:
		status_label.text = "Army submitted! Waiting for opponent..."
	else:
		status_label.text = "Opponent submitted their army (%d units)!" % army_size


func _on_game_started(game_state: Dictionary) -> void:
	print("[Lobby] Game starting! Transitioning to battle... (My seat: %d)" % NetworkManager.my_seat)
	status_label.text = "Game starting!"

	# Cache game state for Battle scene to access
	NetworkManager.cached_game_state = game_state

	# Transition to battle scene
	await get_tree().create_timer(0.5).timeout  # Brief delay for feedback
	get_tree().change_scene_to_file("res://client/scenes/battle.tscn")
