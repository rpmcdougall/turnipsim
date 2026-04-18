extends SceneTree
## Test Phase 3 scenes can be instantiated without errors.
##
## Run with: godot --headless --script tests/test_phase3_scenes.gd

func _init() -> void:
	print("Testing Phase 3 scene instantiation...")

	# Test server_main.tscn
	print("\n[1/2] Testing server_main.tscn...")
	var server_scene = load("res://server/server_main.tscn")
	if not server_scene:
		print("ERROR: Failed to load server_main.tscn")
		quit(1)
		return
	print("✓ server_main.tscn loaded")

	# Can't instantiate server scene in client mode, but loading is enough validation

	# Test lobby.tscn
	print("\n[2/2] Testing lobby.tscn...")
	var lobby_scene = load("res://client/scenes/lobby.tscn")
	if not lobby_scene:
		print("ERROR: Failed to load lobby.tscn")
		quit(1)
		return
	print("✓ lobby.tscn loaded")

	var lobby_instance = lobby_scene.instantiate()
	if not lobby_instance:
		print("ERROR: Failed to instantiate lobby.tscn")
		quit(1)
		return
	print("✓ lobby.tscn instantiated")

	# Check expected nodes
	var expected_nodes = [
		"MarginContainer/VBoxContainer/ConnectionPanel",
		"MarginContainer/VBoxContainer/RoomPanel",
		"MarginContainer/VBoxContainer/InRoomPanel"
	]

	for node_path in expected_nodes:
		var node = lobby_instance.get_node_or_null(node_path)
		if not node:
			print("ERROR: Expected node not found: %s" % node_path)
			quit(1)
			return

	print("✓ All expected nodes found")

	print("")
	print("Phase 3 scene validation: PASSED")
	lobby_instance.free()
	quit(0)
