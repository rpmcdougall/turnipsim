extends Control
## Test scene for rolling and displaying armies (Phase 2).

@onready var army_display: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ArmyDisplay

var ruleset: Ruleset = null


func _ready() -> void:
	# Load the MVP ruleset
	ruleset = Ruleset.new()
	var error = ruleset.load_from_file("res://game/rulesets/mvp.json")
	if error:
		push_error("TestRoll: Failed to load ruleset: " + error)
		return

	# Roll the first army
	_roll_army()


func _roll_army() -> void:
	# Clear previous display
	for child in army_display.get_children():
		child.queue_free()

	# Roll a new army using real RNG
	var roller = ArmyRoller.new()
	var army = roller.roll_army(ruleset, func(): return randi_range(1, 6))

	# Display army info
	var header = Label.new()
	header.text = "Army: %d units" % army.size()
	header.add_theme_font_size_override("font_size", 18)
	army_display.add_child(header)

	# Display each unit
	for i in range(army.size()):
		var unit = army[i]
		var unit_panel = _create_unit_panel(i + 1, unit)
		army_display.add_child(unit_panel)


func _create_unit_panel(number: int, unit: Types.Unit) -> PanelContainer:
	var panel = PanelContainer.new()
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)

	# Unit name and archetype
	var name_label = Label.new()
	name_label.text = "[%d] %s (%s)" % [number, unit.name, unit.archetype]
	name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(name_label)

	# Stats
	var effective = unit.get_effective_stats()
	var stats_label = Label.new()
	stats_label.text = "Stats: M%d S%d C%d R%d W%d Sv%d+" % [
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
	weapon_label.text = "Weapon: %s (%s)" % [unit.weapon.name, unit.weapon.type]
	vbox.add_child(weapon_label)

	# Mutations
	if unit.mutations.size() > 0:
		var mutations_label = Label.new()
		mutations_label.text = "Mutations:"
		vbox.add_child(mutations_label)

		for mutation in unit.mutations:
			var mut_label = Label.new()
			var mod_strings: Array[String] = []
			for stat_name in mutation.stat_modifiers:
				var mod_value = mutation.stat_modifiers[stat_name]
				var sign = "+" if mod_value >= 0 else ""
				mod_strings.append("%s %s%d" % [stat_name.capitalize(), sign, mod_value])

			mut_label.text = "  • %s — %s (%s)" % [
				mutation.name,
				mutation.description,
				", ".join(mod_strings)
			]
			vbox.add_child(mut_label)

	return panel


func _on_reroll_button_pressed() -> void:
	_roll_army()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://client/main.tscn")
