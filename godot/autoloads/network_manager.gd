extends Node

## True when running as dedicated server (via --server flag or dedicated_server feature tag).
var is_server: bool = false


func _ready() -> void:
	is_server = OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_args()
	if is_server:
		print("[NetworkManager] Mode: SERVER")
	else:
		print("[NetworkManager] Mode: CLIENT")
