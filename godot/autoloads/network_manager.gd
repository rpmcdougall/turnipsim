extends Node

## True when running as dedicated server (via --server flag or dedicated_server feature tag).
var is_server: bool = false

## Client's seat assignment (1 or 2) when in a game.
## 0 means not assigned yet.
var my_seat: int = 0

## Client's peer ID when connected to server.
var my_peer_id: int = 0

## Game state handed off from lobby → battle scene (read by battle.gd on load).
## Cleared on leave_room / reset.
var cached_game_state: Dictionary = {}


func _ready() -> void:
	var engine_args = OS.get_cmdline_args()
	var user_args = OS.get_cmdline_user_args()
	is_server = (OS.has_feature("dedicated_server")
		or "--server" in engine_args
		or "--server" in user_args)
	if is_server:
		print("[NetworkManager] Mode: SERVER")
	else:
		print("[NetworkManager] Mode: CLIENT")


## Set the client's seat assignment (called when joining a room).
func set_my_seat(seat: int) -> void:
	my_seat = seat
	print("[NetworkManager] My seat: %d" % my_seat)


## Reset seat assignment (when leaving a room).
func reset_seat() -> void:
	my_seat = 0
	cached_game_state = {}
	print("[NetworkManager] Seat reset")
