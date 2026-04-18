extends Control


func _ready() -> void:
	print("[Client] Turnip28 client started.")


func _on_test_roll_button_pressed() -> void:
	get_tree().change_scene_to_file("res://client/scenes/test_roll.tscn")
