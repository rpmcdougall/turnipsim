extends Control
## Test scene for previewing roster presets (replaces old army roller).

@onready var army_display: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ArmyDisplay

var ruleset: Ruleset = null
var presets: Array = []
var current_preset_index: int = 0


func _ready() -> void:
	ruleset = Ruleset.new()
	var error = ruleset.load_from_file("res://game/rulesets/v17.json")
	if error:
		push_error("TestRoll: Failed to load ruleset: " + error)
		return

	# Load presets from JSON
	presets = _get_presets()
	if presets.is_empty():
		push_error("TestRoll: No presets found")
		return

	_display_preset(0)


func _get_presets() -> Array:
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


func _display_preset(index: int) -> void:
	current_preset_index = index
	for child in army_display.get_children():
		child.queue_free()

	var preset = presets[index]
	var roster = Types.Roster.from_dict(preset["roster"])

	# Header
	var header = Label.new()
	header.text = "%s — %s" % [preset["name"], preset.get("description", "")]
	header.add_theme_font_size_override("font_size", 18)
	army_display.add_child(header)

	var count_label = Label.new()
	count_label.text = "Units: %d (Preset %d/%d)" % [roster.get_unit_count(), index + 1, presets.size()]
	army_display.add_child(count_label)

	# Display each snob and their followers
	var unit_num = 0
	for snob in roster.snobs:
		unit_num += 1
		var snob_panel = _create_unit_panel(unit_num, snob.snob_type, snob.equipment, true)
		army_display.add_child(snob_panel)

		for follower in snob.followers:
			unit_num += 1
			var f_panel = _create_unit_panel(unit_num, follower.unit_type, follower.equipment, false)
			army_display.add_child(f_panel)


func _create_unit_panel(number: int, unit_type: String, equipment: String, is_snob: bool) -> PanelContainer:
	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	var prefix = "" if is_snob else "  "
	var name_label = Label.new()
	name_label.text = "%s[%d] %s" % [prefix, number, unit_type]
	name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_label)

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

			# Show special rules
			if unit_def.has("special_rules") and not unit_def["special_rules"].is_empty():
				var rules_label = Label.new()
				rules_label.text = "%sRules: %s" % [prefix, ", ".join(unit_def["special_rules"])]
				vbox.add_child(rules_label)

	return panel


func _on_reroll_button_pressed() -> void:
	if presets.is_empty():
		return
	current_preset_index = (current_preset_index + 1) % presets.size()
	_display_preset(current_preset_index)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://client/main.tscn")
