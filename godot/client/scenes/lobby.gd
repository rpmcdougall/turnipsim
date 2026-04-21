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
var preset_picker: OptionButton = null
var submit_army_button: Button = null
var army_display: VBoxContainer = null
var waiting_label: Label = null
var start_solo_button: Button = null
var preset_mode_button: Button = null
var custom_mode_button: Button = null
var roster_builder: RosterBuilder = null

# Presets loaded from v17.json (for the preset dropdown). Cached at _ready.
var _presets: Array = []

# Current roster-entry mode — "preset" (dropdown) or "custom" (builder).
var _roster_mode: String = "preset"

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

	# Cache presets for the dropdown
	_presets = _get_presets_from_ruleset()

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
	_reset_army_state()
	status_label.text = "Disconnected"
	_show_connection_panel()


## Clear roster + submission flags so a reconnect/rejoin starts fresh.
## Without this, has_submitted_army persists and hides the Submit button
## after joining a new room, leaving the client stuck ready-without-army.
func _reset_army_state() -> void:
	my_roster = null
	has_submitted_army = false
	_roster_mode = "preset"
	if submit_army_button:
		submit_army_button.disabled = true
		submit_army_button.visible = false
	if preset_picker:
		preset_picker.disabled = false
		preset_picker.select(0)  # "— Select preset —" placeholder
	if army_display:
		for child in army_display.get_children():
			child.queue_free()
	if preset_mode_button and custom_mode_button:
		_apply_roster_mode()


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
	_reset_army_state()
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

	# Update waiting status
	_update_waiting_status()


## Preset picker — index 0 is the placeholder, presets start at index 1.
func _on_preset_picker_item_selected(index: int) -> void:
	if not is_in_room or not ruleset:
		return

	# Index 0 is the "— Select preset —" placeholder; clear any displayed roster.
	if index <= 0:
		my_roster = null
		if army_display:
			for child in army_display.get_children():
				child.queue_free()
		if submit_army_button:
			submit_army_button.disabled = true
			submit_army_button.visible = false
		return

	var preset_index = index - 1
	if preset_index >= _presets.size():
		return

	var preset = _presets[preset_index]
	my_roster = Types.Roster.from_dict(preset["roster"])

	_display_army(preset.get("name", ""), preset.get("description", ""))

	# Pre-fill the custom builder with this preset so switching to Custom
	# mode starts from the same roster. Only meaningful when the builder
	# exists (always true after _ensure_army_ui_exists).
	if roster_builder:
		roster_builder.load_roster(my_roster)

	if submit_army_button:
		submit_army_button.disabled = false
		submit_army_button.visible = true

	status_label.text = "Preset selected: %s (%d units)" % [preset["name"], my_roster.get_unit_count()]


func _on_preset_mode_pressed() -> void:
	_roster_mode = "preset"
	_apply_roster_mode()


func _on_custom_mode_pressed() -> void:
	_roster_mode = "custom"
	_apply_roster_mode()


## Swap visibility + clear roster state when the entry mode changes. Each
## mode is self-contained for now; step 3 of #28 will let preset selection
## pre-fill the custom builder.
func _apply_roster_mode() -> void:
	if preset_mode_button:
		preset_mode_button.button_pressed = (_roster_mode == "preset")
	if custom_mode_button:
		custom_mode_button.button_pressed = (_roster_mode == "custom")
	if preset_picker:
		preset_picker.visible = (_roster_mode == "preset")
	if roster_builder:
		roster_builder.visible = (_roster_mode == "custom")

	# Switching modes discards the in-progress roster from the other mode.
	my_roster = null
	if preset_picker:
		preset_picker.select(0)
	if army_display:
		for child in army_display.get_children():
			child.queue_free()
	if submit_army_button:
		submit_army_button.disabled = true
		submit_army_button.visible = false

	# If we land in custom mode, immediately publish the builder's current
	# validity so Submit reflects reality (an empty builder is invalid).
	if _roster_mode == "custom" and roster_builder:
		roster_builder._refresh_validation()


## Emitted by RosterBuilder whenever a dropdown changes.
func _on_custom_roster_changed(is_valid: bool, _error: String) -> void:
	if _roster_mode != "custom" or not roster_builder:
		return
	if is_valid:
		my_roster = roster_builder.get_roster()
		_display_army("Custom Roster", "")
		if submit_army_button:
			submit_army_button.disabled = false
			submit_army_button.visible = true
	else:
		my_roster = null
		if army_display:
			for child in army_display.get_children():
				child.queue_free()
		if submit_army_button:
			submit_army_button.disabled = true
			submit_army_button.visible = false


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


## Display the selected roster. preset_name/description are optional context
## strings shown above the unit list.
func _display_army(preset_name: String = "", preset_description: String = "") -> void:
	if not army_display or not my_roster:
		return

	for child in army_display.get_children():
		child.queue_free()

	var header_text = "Your Regiment: %d units" % my_roster.get_unit_count()
	if not preset_name.is_empty():
		header_text = "%s — %d units" % [preset_name, my_roster.get_unit_count()]
	var header = Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 16)
	army_display.add_child(header)

	if not preset_description.is_empty():
		var desc = Label.new()
		desc.text = preset_description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		army_display.add_child(desc)

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
	# Find the InRoomPanel VBoxContainer
	var in_room_vbox = in_room_panel.get_node_or_null("VBoxContainer")
	if not in_room_vbox:
		# Might already be wrapped (see below) — search one level deeper.
		var scroll = in_room_panel.get_node_or_null("LobbyScroll")
		if scroll:
			in_room_vbox = scroll.get_node_or_null("VBoxContainer")
	if not in_room_vbox:
		push_error("[Lobby] InRoomPanel/VBoxContainer not found")
		return

	# Wrap the in-room content in a ScrollContainer so the Submit button and
	# other controls stay reachable when the roster builder + army display
	# make the content taller than the window. @onready paths have already
	# resolved, so moving the VBoxContainer under a new ScrollContainer
	# doesn't invalidate any cached node references.
	if in_room_vbox.get_parent() == in_room_panel:
		in_room_panel.remove_child(in_room_vbox)
		var scroll := ScrollContainer.new()
		scroll.name = "LobbyScroll"
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		in_room_panel.add_child(scroll)
		in_room_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(in_room_vbox)

	# Remove any legacy "Roll Army" button from an earlier build
	var legacy_roll = in_room_vbox.get_node_or_null("RollArmyButton")
	if legacy_roll:
		legacy_roll.queue_free()

	submit_army_button = in_room_vbox.get_node_or_null("SubmitArmyButton")

	var scroll_container = in_room_vbox.get_node_or_null("ArmyScrollContainer")
	if scroll_container:
		army_display = scroll_container.get_node_or_null("ArmyDisplay")

	# Mode toggle — [Preset] [Custom]
	var mode_row: HBoxContainer = in_room_vbox.get_node_or_null("RosterModeRow")
	if not mode_row:
		mode_row = HBoxContainer.new()
		mode_row.name = "RosterModeRow"
		in_room_vbox.add_child(mode_row)
	preset_mode_button = mode_row.get_node_or_null("PresetModeButton")
	if not preset_mode_button:
		preset_mode_button = Button.new()
		preset_mode_button.name = "PresetModeButton"
		preset_mode_button.text = "Preset"
		preset_mode_button.toggle_mode = true
		preset_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(preset_mode_button)
	custom_mode_button = mode_row.get_node_or_null("CustomModeButton")
	if not custom_mode_button:
		custom_mode_button = Button.new()
		custom_mode_button.name = "CustomModeButton"
		custom_mode_button.text = "Custom"
		custom_mode_button.toggle_mode = true
		custom_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_row.add_child(custom_mode_button)
	if not preset_mode_button.pressed.is_connected(_on_preset_mode_pressed):
		preset_mode_button.pressed.connect(_on_preset_mode_pressed)
	if not custom_mode_button.pressed.is_connected(_on_custom_mode_pressed):
		custom_mode_button.pressed.connect(_on_custom_mode_pressed)

	# Create preset picker if needed
	preset_picker = in_room_vbox.get_node_or_null("PresetPicker")
	if not preset_picker:
		preset_picker = OptionButton.new()
		preset_picker.name = "PresetPicker"
		preset_picker.custom_minimum_size = Vector2(0, 40)
		in_room_vbox.add_child(preset_picker)

	_populate_preset_picker()

	if not preset_picker.item_selected.is_connected(_on_preset_picker_item_selected):
		preset_picker.item_selected.connect(_on_preset_picker_item_selected)

	# Create roster builder (initially hidden — Preset mode is default)
	roster_builder = in_room_vbox.get_node_or_null("RosterBuilder") as RosterBuilder
	if not roster_builder:
		roster_builder = RosterBuilder.new()
		roster_builder.name = "RosterBuilder"
		in_room_vbox.add_child(roster_builder)
		roster_builder.setup(ruleset)
		roster_builder.roster_changed.connect(_on_custom_roster_changed)

	_apply_roster_mode()

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
		submit_army_button = Button.new()
		submit_army_button.name = "SubmitArmyButton"
		submit_army_button.text = "Submit Army"
		submit_army_button.disabled = true  # Enabled after rolling
		submit_army_button.custom_minimum_size = Vector2(0, 40)
		in_room_vbox.add_child(submit_army_button)

	# Connect signal (whether new or existing)
	if submit_army_button and not submit_army_button.pressed.is_connected(_on_submit_army_button_pressed):
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


## Populate the preset dropdown from cached _presets. Index 0 is a placeholder.
func _populate_preset_picker() -> void:
	if not preset_picker:
		return
	preset_picker.clear()
	preset_picker.add_item("— Select preset —")
	for preset in _presets:
		preset_picker.add_item(preset.get("name", "<unnamed>"))
	preset_picker.select(0)


## Submit Army button
func _on_submit_army_button_pressed() -> void:
	if not is_in_room or not my_roster or has_submitted_army:
		return

	print("[Lobby] Submitting roster (%d units)" % my_roster.get_unit_count())

	# Send roster as dictionary to server
	NetworkClient.submit_army.rpc_id(1, my_roster.to_dict())
	has_submitted_army = true

	# Disable further selection/submission until reset
	if preset_picker:
		preset_picker.disabled = true
	if preset_mode_button:
		preset_mode_button.disabled = true
	if custom_mode_button:
		custom_mode_button.disabled = true
	if roster_builder:
		roster_builder.visible = false
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
