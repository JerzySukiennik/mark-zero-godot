extends Node
## Opens a room and beacons it, then reports who turns up. Run as a SCENE (Net is an
## autoload) on one machine while tools/net_join.tscn runs on another:
##   godot --headless --path . res://tools/net_host.tscn
## Optional arg: seconds to stay open (default 40).

var _t := 0.0
var _life := 40.0
var _disc: Discovery
var _seen := {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_life = float(args[0])
	Net.local_name = "MAC"
	Net.local_hero = "ironman"
	if not Net.host():
		print("[host] FAILED to open a room"); get_tree().quit(1); return
	_disc = Discovery.new()
	add_child(_disc)
	_disc.begin_beacon()
	Net.peers_changed.connect(_roster)
	print("[host] room open on %d, beaconing on %d, online=%s"
		% [Net.DEFAULT_PORT, Discovery.BEACON_PORT, Net.online])
	_roster()

func _roster() -> void:
	var rows: Array = []
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		rows.append("%s=%s/%s" % [pid, p.get("name", "?"), p.get("hero", "?")])
		if pid != Net.my_id and not _seen.has(pid):
			_seen[pid] = true
			print("[host] JOINED: peer %d" % pid)
	print("[host] roster: ", ", ".join(rows))

func _process(d: float) -> void:
	_t += d
	if _t >= _life:
		print("[host] peers seen: %d" % _seen.size())
		print("[host] RESULT: " + ("SOMEBODY CONNECTED" if _seen.size() > 0 else "NOBODY CONNECTED"))
		get_tree().quit(0 if _seen.size() > 0 else 1)
