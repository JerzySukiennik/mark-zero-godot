extends Node
## Looks for a room the way the lobby does — UDP broadcast, no address typed — and joins
## the first one it finds. Run as a SCENE:
##   godot --headless --path . res://tools/net_join.tscn

var _t := 0.0
var _disc: Discovery
var _tried := false
var _joined := false

func _ready() -> void:
	Net.local_name = "HP"
	Net.local_hero = "spiderman"
	_disc = Discovery.new()
	add_child(_disc)
	if not _disc.begin_listen():
		print("[join] could not listen on %d" % Discovery.BEACON_PORT)
	Net.room_joined.connect(func():
		_joined = true
		print("[join] CONNECTED, my id=%d" % Net.my_id))
	Net.room_failed.connect(func(why: String): print("[join] failed: ", why))
	Net.peers_changed.connect(func():
		var rows: Array = []
		for pid in Net.players:
			rows.append("%s=%s/%s" % [pid, Net.players[pid].get("name", "?"),
				Net.players[pid].get("hero", "?")])
		print("[join] roster: ", ", ".join(rows)))

func _process(d: float) -> void:
	_t += d
	if not _tried:
		var found: Array = _disc.listed()
		if not found.is_empty():
			var r: Dictionary = found[0]
			print("[join] FOUND ROOM: %s at %s:%d (%d players)"
				% [r["name"], r["address"], r["port"], r["players"]])
			_tried = true
			Net.join(String(r["address"]), int(r["port"]))
	if _t > 30.0:
		print("[join] RESULT: " + ("JOINED AND SAW THE ROSTER" if _joined
			else ("FOUND A ROOM BUT NEVER CONNECTED" if _tried else "NEVER SAW A BEACON")))
		get_tree().quit(0 if _joined else 1)
