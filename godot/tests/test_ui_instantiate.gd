extends SceneTree
## Quick test to verify TestRoll scene can be instantiated without errors.
##
## Run with: godot --headless --script tests/test_ui_instantiate.gd

func _init() -> void:
	print("Testing TestRoll scene instantiation...")

	# Load the scene
	var scene = load("res://client/scenes/test_roll.tscn")
	if not scene:
		print("ERROR: Failed to load test_roll.tscn")
		quit(1)
		return

	print("✓ test_roll.tscn loaded successfully")

	# Try to instantiate it
	var instance = scene.instantiate()
	if not instance:
		print("ERROR: Failed to instantiate test_roll.tscn")
		quit(1)
		return

	print("✓ test_roll.tscn instantiated successfully")

	# Check that it has the expected nodes
	var army_display = instance.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/ArmyDisplay")
	if not army_display:
		print("ERROR: ArmyDisplay node not found")
		quit(1)
		return

	print("✓ ArmyDisplay node found")
	print("")
	print("TestRoll scene validation: PASSED")

	instance.free()
	quit(0)
