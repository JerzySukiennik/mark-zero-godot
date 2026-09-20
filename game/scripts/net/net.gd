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

var players: Dictionary = {}          ## peer id -> { name, armor, hero }

## IRON MAN OR SPIDER-MAN, and in a room the two are EXCLUSIVE.
##
## Jurek: solo you pick one of them; in multiplayer one player is Iron Man and the other is
## Spider-Man. So this is not a cosmetic choice like the armour — it decides which entity
## the arena spawns, and two people cannot hold the same one.
const HEROES := ["ironman", "spiderman"]
var local_hero := "ironman"
var local_name := "PILOT"
var local_armor := "mk1"
var is_host := false

func _ready() -> void:
	# A solo run is a room with one peer in it. Seeding the roster here means the arena
	# spawns a suit whether or not anyone ever opens a room, and there is no "offline" code
	# path to keep in step with the online one.
	players[1] = { name = local_name, armor = local_armor, hero = local_hero }
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
	players[multiplayer.get_unique_id()] = { name = local_name, armor = local_armor, hero = local_hero }
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

## IS THERE ACTUALLY A NETWORK UNDER US? This used to ask whether `multiplayer_peer` was
## non-null and connected — and both are true in a game nobody has networked, because
## Godot installs an OfflineMultiplayerPeer by default and it reports CONNECTION_CONNECTED.
## So `online` was true the moment the game booted, and every announce_* took the RPC
## branch in a solo session. The lobby made it visible: it drew the in-a-room roster for a
## player sitting alone at the menu.
##
## Asked of the peer's TYPE, because that is the thing that is actually different: a real
## room is an ENet peer and nothing else in this game ever creates one.
var online: bool:
	get:
		var p := multiplayer.multiplayer_peer
		return p is ENetMultiplayerPeer \
			and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

var my_id: int:
	get: return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1

# ---- roster ----------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host:
		# Tell the newcomer about everyone already here, then everyone about the newcomer.
		for pid in players:
			_register.rpc_id(id, pid, players[pid].name, players[pid].armor, players[pid].get("hero", "ironman"))
	_register.rpc_id(id, my_id, local_name, local_armor, local_hero)

func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peers_changed.emit()

func _on_connected() -> void:
	players[my_id] = { name = local_name, armor = local_armor, hero = local_hero }
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
func _register(id: int, who: String, armor: String, hero: String) -> void:
	players[id] = { name = who, armor = armor, hero = hero }
	# TWO HEROES, ONE EACH. If the newcomer wants the role we are already playing, they get
	# the other one — settled locally and identically on every peer, so nobody has to ask
	# the host and there is no window where the room holds two Iron Men.
	if id != my_id and hero == players.get(my_id, {}).get("hero", ""):
		players[id].hero = other_hero(hero)
	peers_changed.emit()

static func other_hero(hero: String) -> String:
	return "spiderman" if hero == "ironman" else "ironman"

## Switch sides. In a room this also pushes whoever held it onto the other role, because
## the pair is exclusive and somebody has to move.
@rpc("any_peer", "call_local", "reliable")
func set_hero(id: int, hero: String) -> void:
	if not players.has(id):
		return
	# Refused on the RECEIVING side as well, not only where the button was pressed: the
	# exclusivity rule below pushes whoever held that role onto the other one, so an
	# unchecked late call would change a character somebody else is currently playing.
	if hero_locked:
		return
	for pid in players:
		if pid != id and players[pid].get("hero", "") == hero:
			players[pid].hero = other_hero(hero)
	players[id].hero = hero
	if id == my_id:
		local_hero = hero
	peers_changed.emit()

## LOCKED ONCE THE MATCH STARTS. Jurek: "raz w lobby się wybiera character i potem już
## nie można zmieniać." Which side you are is the shape of the match, not a setting: if
## Iron Man can become Spider-Man mid-fight then the other player loses their role to a
## keystroke, every entity in the world is thrown away and rebuilt, and there is no reason
## to ever commit to one. The lobby is the only place it is a question.
var hero_locked := false

## Called when the lobby hands over to the arena. From here the choice stands until the
## players come back out to the menu.
func lock_heroes() -> void:
	hero_locked = true

func unlock_heroes() -> void:
	hero_locked = false

func announce_hero(hero: String) -> void:
	if hero_locked:
		push_warning("[net] hero is locked for this match")
		return
	if online:
		set_hero.rpc(my_id, hero)
	else:
		local_hero = hero
		if players.has(my_id):
			players[my_id].hero = hero
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
		# WRITE THE FIELD, DO NOT REBUILD THE ROW. This used to assign a fresh dictionary
		# with only `name` and `armor` in it, which quietly deleted `hero` — so every
		# change of armour in a solo game reset the player to Iron Man, because everything
		# downstream reads the hero with a default of "ironman". Changing your suit is not
		# a statement about which character you are.
		if not players.has(my_id):
			players[my_id] = { name = local_name, armor = armor, hero = local_hero }
		else:
			players[my_id].armor = armor
		peers_changed.emit()

# ---- starting the match ----------------------------------------------------------------

signal match_started

## THE HOST DECIDES WHEN. Everyone loads the arena on the same call rather than each
## player pressing their own start, because the roster — and with it who is Iron Man and
## who is Spider-Man — has to be settled and identical on every machine before a single
## entity is spawned. A client that entered the arena early would spawn against a roster
## that is still changing under it.
@rpc("authority", "call_local", "reliable")
func start_match() -> void:
	lock_heroes()
	match_started.emit()

## Called by the host from the lobby. Solo, there is nobody to tell, so it is the same
## call with no network under it — one code path, exactly like `players[1]` in _ready.
func begin_match() -> void:
	if online and is_host:
		start_match.rpc()
	else:
		start_match()

## Coming back out to the menu. The choice is only locked for the duration of a match.
func end_match() -> void:
	unlock_heroes()

## Is this side already somebody else's? The lobby dims a side rather than letting two
## people fight over it and silently pushing one of them off it.
func hero_taken_by(hero: String) -> String:
	for pid in players:
		if pid != my_id and players[pid].get("hero", "") == hero:
			return String(players[pid].get("name", "PILOT"))
	return ""
