extends Node
## Drives the REAL lobby screen, not the network layer underneath it.
##
## tools/net_host.tscn and net_join.tscn already proved that a room can be beaconed,
## found and joined — but they call Net and Discovery directly and never touch LobbyUi.
## Jurek: "nawet z jednym pokojem nie działa", which is a sentence about the screen. So
## this one instantiates the actual menu, opens the actual lobby and presses the actual
## rows, and prints what the screen would be showing at each step.
##
##   godot --headless --path . res://tools/lobby_drive.tscn -- host
##   godot --headless --path . res://tools/lobby_drive.tscn -- join

var _menu: Node
var _lob: Node
var _mode := "join"
var _t := 0.0
var _pressed := false
var _last := ""

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_mode = a[0]
	Net.local_name = _mode.to_upper()
	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_menu)
	await get_tree().process_frame
	_menu.call("_open_lobby")
	_lob = _menu.get("_lobby")
	print("[%s] lobby open, online=%s" % [_mode, Net.online])

func _rows_text() -> String:
	var out: Array = []
	for r in _lob.get("_rows"):
		var lab := String(r.get("label", ""))
		var note := String(r.get("note", ""))
		out.append(("%s %s" % [lab, note]).strip_edges())
	return " | ".join(out)

func _process(d: float) -> void:
	if _lob == null or not is_instance_valid(_lob):
		return
	_t += d
	var now := _rows_text()
	if now != _last:
		_last = now
		print("[%s] screen: %s" % [_mode, now])

	if not _pressed and _t > 1.5:
		if _mode == "host":
			_pressed = true
			print("[host] pressing OPEN A ROOM")
			_lob.call("_press", "host")
		else:
			# Press whatever join row the screen is actually offering, found the same way
			# the player finds it: by looking at the list.
			for r in _lob.get("_rows"):
				var kind := String(r.get("kind", ""))
				if kind.begins_with("join:"):
					_pressed = true
					print("[join] pressing ROOM ROW: %s" % kind)
					_lob.call("_press", kind)
					break

	if _t > (70.0 if _mode == "host" else 32.0):
		print("[%s] online=%s  is_host=%s  players=%d"
			% [_mode, Net.online, Net.is_host, Net.players.size()])
		var ok := Net.online and Net.players.size() >= 2
		print("[%s] RESULT: %s" % [_mode, "IN A ROOM WITH SOMEBODY" if ok else "NOT CONNECTED"])
		get_tree().quit(0 if ok else 1)
