extends PanelContainer
## Custom roster builder — per-slot dropdowns for unit type + equipment.
##
## Composition is fixed per v17: 1 Toff (2 follower slots) + 2 Toadies
## (1 follower slot each). Snob types are not user-selectable; follower
## types are constrained to non-snob categories (infantry / cavalry /
## artillery) and equipment is constrained to each unit's allowed list.
##
## The builder rebuilds a Types.Roster from UI state on every change and
## runs it through Ruleset.validate_roster(). Validity is published via
## the `roster_changed` signal so the lobby can enable/disable Submit.

class_name RosterBuilder

signal roster_changed(is_valid: bool, error: String)

const UNSELECTED_LABEL: String = "— Select —"

var ruleset: Ruleset = null

# Follower slot controls, in visit order (Toff f1, Toff f2, Toady1 f1, Toady2 f1)
var _follower_slots: Array = []  # Array[Dictionary] {type_picker, equip_picker}
var _validation_label: Label = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Must be called once before use.
func setup(p_ruleset: Ruleset) -> void:
	ruleset = p_ruleset
	_build_ui()
	_refresh_validation()


## Build the authoritative Types.Roster from the current UI state.
## Slots whose unit_type is still UNSELECTED are skipped; this produces
## an intentionally invalid roster so validate_roster() catches it with
## a clear "too few followers" message instead of silently passing.
func get_roster() -> Types.Roster:
	var roster := Types.Roster.new()
	roster.cult = "none"

	var toff := Types.RosterSnob.new("Toff", "pistols_and_sabres", [])
	var toady1 := Types.RosterSnob.new("Toady", "pistols_and_sabres", [])
	var toady2 := Types.RosterSnob.new("Toady", "pistols_and_sabres", [])

	# _follower_slots order: Toff f1, Toff f2, Toady1 f1, Toady2 f1
	_append_follower(toff, _follower_slots[0])
	_append_follower(toff, _follower_slots[1])
	_append_follower(toady1, _follower_slots[2])
	_append_follower(toady2, _follower_slots[3])

	roster.snobs = [toff, toady1, toady2]
	return roster


func _append_follower(snob: Types.RosterSnob, slot: Dictionary) -> void:
	var unit_type: String = _picker_value(slot["type_picker"])
	if unit_type.is_empty():
		return  # leave slot empty → validation will flag it
	var equipment: String = _picker_value(slot["equip_picker"])
	snob.followers.append(Types.RosterUnit.new(unit_type, equipment))


## Populate the builder's dropdowns to match the supplied roster.
## Used to pre-fill the Custom view when a player selects a preset,
## so they can tweak rather than start from scratch. Silently ignores
## followers beyond the fixed slot count.
func load_roster(roster: Types.Roster) -> void:
	if roster == null:
		return

	# Flatten roster followers into the same order the slots expect:
	# Toff f0, Toff f1, Toady0 f0, Toady1 f0. Tolerate missing followers
	# by leaving the corresponding slot unselected.
	var flat: Array = [null, null, null, null]
	var toff_idx := 0
	var toady_idx := 0
	for snob in roster.snobs:
		if snob.snob_type == "Toff":
			for i in range(min(2, snob.followers.size())):
				flat[i] = snob.followers[i]
			toff_idx += 1
		elif snob.snob_type == "Toady":
			var target_index := 2 + toady_idx
			if target_index < flat.size() and snob.followers.size() > 0:
				flat[target_index] = snob.followers[0]
			toady_idx += 1

	for i in range(_follower_slots.size()):
		_apply_slot_from_follower(_follower_slots[i], flat[i] if i < flat.size() else null)

	_refresh_validation()


## Set a slot's dropdowns to match a RosterUnit (or clear them if null).
func _apply_slot_from_follower(slot: Dictionary, follower) -> void:
	var type_picker: OptionButton = slot["type_picker"]
	var equip_picker: OptionButton = slot["equip_picker"]

	if follower == null:
		type_picker.select(0)
		_refresh_equipment_picker(slot)
		_refresh_info_label(slot)
		return

	_select_by_metadata(type_picker, follower.unit_type)
	_refresh_equipment_picker(slot)
	_select_by_metadata(equip_picker, follower.equipment)
	_refresh_info_label(slot)


## Select the OptionButton item whose metadata matches `value`.
## Falls back to index 0 (placeholder) if no match — e.g. if the preset
## contains a unit type not offered in the dropdown.
func _select_by_metadata(picker: OptionButton, value: String) -> void:
	for i in range(picker.item_count):
		if picker.get_item_metadata(i) == value:
			picker.select(i)
			return
	picker.select(0)


func _picker_value(picker: OptionButton) -> String:
	if picker.selected <= 0:
		return ""
	return picker.get_item_metadata(picker.selected)


# =============================================================================
# UI construction
# =============================================================================

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(vbox)

	var title := Label.new()
	title.text = "Custom Roster"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_build_snob_block(vbox, "Toff", 2)
	_build_snob_block(vbox, "Toady 1", 1)
	_build_snob_block(vbox, "Toady 2", 1)

	_validation_label = Label.new()
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_validation_label)


func _build_snob_block(parent: VBoxContainer, label_text: String, follower_count: int) -> void:
	var header := Label.new()
	header.text = label_text
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	parent.add_child(header)

	for i in range(follower_count):
		parent.add_child(_build_follower_row())


func _build_follower_row() -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pickers := HBoxContainer.new()
	pickers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(pickers)

	var type_picker := OptionButton.new()
	type_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_picker.add_item(UNSELECTED_LABEL)
	type_picker.set_item_metadata(0, "")
	for key in ruleset.get_follower_types():
		var def := ruleset.get_unit_type(key)
		var display: String = "%s (%d models)" % [def.get("unit_type", key), def.get("model_count", 0)]
		type_picker.add_item(display)
		type_picker.set_item_metadata(type_picker.item_count - 1, key)
	pickers.add_child(type_picker)

	var equip_picker := OptionButton.new()
	equip_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_picker.disabled = true
	equip_picker.add_item(UNSELECTED_LABEL)
	equip_picker.set_item_metadata(0, "")
	pickers.add_child(equip_picker)

	# Stats / special-rules hint line, hidden until a unit type is picked.
	var info_label := Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_label.visible = false
	wrapper.add_child(info_label)

	var slot := {"type_picker": type_picker, "equip_picker": equip_picker, "info_label": info_label}
	_follower_slots.append(slot)

	type_picker.item_selected.connect(_on_type_picker_selected.bind(slot))
	equip_picker.item_selected.connect(_on_equip_picker_selected)

	return wrapper


# =============================================================================
# Handlers
# =============================================================================

func _on_type_picker_selected(_index: int, slot: Dictionary) -> void:
	_refresh_equipment_picker(slot)
	_refresh_info_label(slot)
	_refresh_validation()


## Populate the per-slot info label with a compact stat line + any
## special-rule names. Hidden when no unit type is selected.
func _refresh_info_label(slot: Dictionary) -> void:
	var info_label: Label = slot["info_label"]
	var unit_type: String = _picker_value(slot["type_picker"])
	if unit_type.is_empty():
		info_label.visible = false
		info_label.text = ""
		return

	var def := ruleset.get_unit_type(unit_type)
	if def.is_empty():
		info_label.visible = false
		return

	var stats: Dictionary = def.get("base_stats", {})
	var parts: Array[String] = []
	parts.append("M%d A%d I%d+ W%d V%d+" % [
		stats.get("movement", 0), stats.get("attacks", 0),
		stats.get("inaccuracy", 0), stats.get("wounds", 0),
		stats.get("vulnerability", 0),
	])
	var rules: Array = def.get("special_rules", [])
	if not rules.is_empty():
		var rule_names: Array[String] = []
		for key in rules:
			rule_names.append(str(key).replace("_", " "))
		parts.append("[%s]" % ", ".join(rule_names))

	info_label.text = "  " + "  ·  ".join(parts)
	info_label.visible = true


func _on_equip_picker_selected(_index: int) -> void:
	_refresh_validation()


## Re-populate the equipment dropdown for a slot based on the selected unit
## type. Called whenever the type picker changes. Clears the current choice
## so the player is forced to pick equipment valid for the new type.
func _refresh_equipment_picker(slot: Dictionary) -> void:
	var type_picker: OptionButton = slot["type_picker"]
	var equip_picker: OptionButton = slot["equip_picker"]
	var unit_type: String = _picker_value(type_picker)

	equip_picker.clear()
	equip_picker.add_item(UNSELECTED_LABEL)
	equip_picker.set_item_metadata(0, "")

	if unit_type.is_empty():
		equip_picker.disabled = true
		return

	equip_picker.disabled = false
	for eq_key in ruleset.get_allowed_equipment(unit_type):
		var eq_def := ruleset.get_equipment(eq_key)
		var display: String = eq_key
		if not eq_def.is_empty():
			display = str(eq_def.get("name", eq_key))
		equip_picker.add_item(display)
		equip_picker.set_item_metadata(equip_picker.item_count - 1, eq_key)

	# Auto-select if there's only one allowed option (beyond the placeholder).
	if equip_picker.item_count == 2:
		equip_picker.select(1)


## Rebuild the roster, validate, update the inline label, emit the signal.
func _refresh_validation() -> void:
	var roster := get_roster()
	var error := ruleset.validate_roster(roster)
	var is_valid := error.is_empty()

	if is_valid:
		_validation_label.text = "✓ Valid roster (%d units)" % roster.get_unit_count()
		_validation_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	else:
		_validation_label.text = "✗ " + error
		_validation_label.add_theme_color_override("font_color", Color(0.95, 0.5, 0.5))

	roster_changed.emit(is_valid, error)
