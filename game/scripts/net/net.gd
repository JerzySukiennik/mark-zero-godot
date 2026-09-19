extends Node
## Multiplayer, wired in from day one.
##
## Jurek chose this over "solo first, network later" knowing it is slower to start. The
## reason it is worth it: retro-fitting authority onto an entity that was written as a local
## object means rewriting the entity. Everything the player controls is built here as a
## networked thing from its first line, even while there is only one player in the room.
##
## SHAPE: host-and-clients over ENet, no dedicated server. Whoever starts the room is the
## host and also plays. Each player has AUTHORITY over their own suit: they run the flight
## model locally and publish where it ended up, so flying never waits on the network. Nobody
## can be shoved around by someone else's lag.
##
## This is the same rule the browser build arrived at the hard way — and one bug from there
## is worth carrying across as a warning: identity must not come from anything the machine
## shares between windows. Two clients that believe they are the same peer discard each
## other's traffic as their own echo, and the sky stays empty while every log says "sent".
## Godot's `get_unique_id()` is per-connection and cannot collide, so this uses only that.

signal room_opened(port: int)
signal room_joined
signal room_failed(reason: String)
signal peers_changed

const DEFAULT_PORT := 27015
const MAX_PLAYERS := 8

var players: Dictionary = {}          ## peer id -> { name, armor }
var local_name := "PILOT"
var local_armor := "mk3"
var is_host := false

func _ready() -> void:
	# A solo run is a room with one peer in it. Seeding the roster here means the arena
	# spawns a suit whether or not anyone ever opens a room, and there is no "offline" code
	# path to keep in step with the online one.
	players[1] = { name = local_name, armor = local_armor }
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)

# ---- opening and joining ---------------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		room_failed.emit("Could not open a room on port %d" % port)
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	players[multiplayer.get_unique_id()] = { name = local_name, armor = local_armor }
	peers_changed.emit()
	room_opened.emit(port)
	return true

func join(address: String, port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		room_failed.emit("Could not reach %s" % address)
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	return true

func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	peers_changed.emit()

var online: bool:
	get: return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

var my_id: int:
	get: return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1

# ---- roster ----------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host:
		# Tell the newcomer about everyone already here, then everyone about the newcomer.
		for pid in players:
			_register.rpc_id(id, pid, players[pid].name, players[pid].armor)
	_register.rpc_id(id, my_id, local_name, local_armor)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peers_changed.emit()

func _on_connected() -> void:
	players[my_id] = { name = local_name, armor = local_armor }
	peers_changed.emit()
	room_joined.emit()

func _on_connect_failed() -> void:
	multiplayer.multiplayer_peer = null
	room_failed.emit("The room did not answer")

func _on_server_gone() -> void:
	players.clear()
	is_host = false
	peers_changed.emit()
	room_failed.emit("The host left")

@rpc("any_peer", "call_remote", "reliable")
func _register(id: int, who: String, armor: String) -> void:
	players[id] = { name = who, armor = armor }
	peers_changed.emit()

## Tell everyone which armour you are wearing now. Called when a suit is put on.
@rpc("any_peer", "call_local", "reliable")
func set_armor(id: int, armor: String) -> void:
	if players.has(id):
		players[id].armor = armor
		peers_changed.emit()

func announce_armor(armor: String) -> void:
	local_armor = armor
	if online:
		set_armor.rpc(my_id, armor)
	else:
		players[my_id] = { name = local_name, armor = armor }
		peers_changed.emit()
