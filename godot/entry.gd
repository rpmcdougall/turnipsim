extends Node


func _ready() -> void:
	if NetworkManager.is_server:
		get_tree().change_scene_to_file("res://server/server_main.tscn")
	else:
		get_tree().change_scene_to_file("res://client/main.tscn")
