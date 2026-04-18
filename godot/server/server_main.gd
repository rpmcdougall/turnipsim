extends Node
## Server entry point — boots ENet listener and manages networking.

const PORT = 9999
const MAX_CLIENTS = 32

@onready var room_manager: Node = $RoomManager
@onready var network_server: Node = $NetworkServer


func _ready() -> void:
	print("[Server] Turnip28 server starting...")

	# Create ENet multiplayer peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CLIENTS)

	if error != OK:
		push_error("[Server] Failed to create server on port %d: %s" % [PORT, error])
		get_tree().quit(1)
		return

	# Set as the active multiplayer peer
	multiplayer.multiplayer_peer = peer

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	print("[Server] ENet server listening on port %d" % PORT)
	print("[Server] Max clients: %d" % MAX_CLIENTS)


func _on_peer_connected(peer_id: int) -> void:
	print("[Server] Peer %d connected" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("[Server] Peer %d disconnected" % peer_id)

	# Clean up player's room if they were in one
	room_manager.handle_peer_disconnect(peer_id)
