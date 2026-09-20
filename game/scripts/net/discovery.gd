class_name Discovery
extends Node
## Finding rooms on the local network, so that joining one never involves typing.
##
## THE REASON THIS EXISTS. Mark Zero is controller-only and always will be — there is no
## keyboard path anywhere in it. "Enter the host's IP address" is therefore not a slightly
## awkward screen, it is an impossible one: an on-screen keyboard driven by a stick to type
## 192.168.1.15 is about twenty stick flicks to make one typo. So the host shouts its
## presence on the LAN and the joiner picks a room off a list with one press.
##
## HOW. A UDP broadcast on a fixed port, once every BEACON seconds, carrying a small JSON
## blob: who is hosting, how many are in, and which game port to connect on. Anything
## listening collects them and forgets a room it has not heard from in STALE seconds, so a
## host that closes its laptop disappears from the list on its own rather than leaving a
## dead entry that fails to connect.
##
## This is a LAN mechanism and nothing more. Broadcasts do not cross routers, so it finds
## the other machine in the house and never anything on the internet — which is exactly the
## scope wanted, and also why there is nothing here worth attacking: the beacon carries a
## player name and a port, both of which anyone on the network can see anyway.

## The port the beacons themselves go out on. Deliberately NOT the game port: the game
## port is TCP-ish ENet traffic between two known peers, this is broadcast chatter.
const BEACON_PORT := 27016
const BEACON := 0.5
## How long a room stays listed after its last beacon. Four missed beacons, so a single
## dropped packet never makes a room flicker out of the list under the cursor.
const STALE := 2.2

signal rooms_changed

## address -> { name, players, port, seen }
var rooms: Dictionary = {}

var _out: PacketPeerUDP
var _in: PacketPeerUDP
var _t := 0.0
var _hosting := false

## Start shouting. Called by the host right after the room opens.
func begin_beacon() -> void:
	if _out != null:
		return
	_out = PacketPeerUDP.new()
	_out.set_broadcast_enabled(true)
	_out.set_dest_address("255.255.255.255", BEACON_PORT)
	_hosting = true
	_t = 0.0

## Start listening. Called by anyone sitting in the lobby looking for a room.
func begin_listen() -> bool:
	if _in != null:
		return true
	_in = PacketPeerUDP.new()
	var err := _in.bind(BEACON_PORT, "0.0.0.0")
	if err != OK:
		# The usual cause is a second copy of the game already listening on this machine,
		# which is exactly what happens while testing two clients side by side. Not fatal:
		# the lobby still lets you host.
		push_warning("[discovery] could not listen on %d (%d)" % [BEACON_PORT, err])
		_in = null
		return false
	return true

func stop() -> void:
	if _out != null:
		_out.close()
		_out = null
	if _in != null:
		_in.close()
		_in = null
	_hosting = false
	rooms.clear()

func _process(delta: float) -> void:
	if _out != null and _hosting:
		_t -= delta
		if _t <= 0.0:
			_t = BEACON
			var blob := {
				"mz": 1,                    # so a stray packet on this port is ignored
				"name": Net.local_name,
				"players": Net.players.size(),
				"max": Net.MAX_PLAYERS,
				"port": Net.DEFAULT_PORT,
			}
			_out.put_packet(JSON.stringify(blob).to_utf8_buffer())

	var changed := false
	if _in != null:
		while _in.get_available_packet_count() > 0:
			var from := _in.get_packet_ip()
			var raw := _in.get_packet().get_string_from_utf8()
			var blob = JSON.parse_string(raw)
			# Anything that is not one of ours, from a mistyped port or another program,
			# is dropped without comment rather than shown as a room that cannot be joined.
			if typeof(blob) != TYPE_DICTIONARY or blob.get("mz", 0) != 1 or from == "":
				continue
			var had: bool = rooms.has(from)
			rooms[from] = {
				name = String(blob.get("name", "ROOM")),
				players = int(blob.get("players", 1)),
				max = int(blob.get("max", Net.MAX_PLAYERS)),
				port = int(blob.get("port", Net.DEFAULT_PORT)),
				seen = 0.0,
			}
			if not had:
				changed = true

	# Ageing. A room that has gone quiet leaves the list on its own.
	for addr in rooms.keys():
		rooms[addr].seen += delta
		if rooms[addr].seen > STALE:
			rooms.erase(addr)
			changed = true
	if changed:
		rooms_changed.emit()

## The list as the lobby wants it: oldest-seen first so the order does not jitter under
## the cursor as packets arrive.
func listed() -> Array:
	var out: Array = []
	for addr in rooms:
		var r: Dictionary = rooms[addr].duplicate()
		r["address"] = addr
		out.append(r)
	out.sort_custom(func(a, b): return String(a["address"]) < String(b["address"]))
	return out
