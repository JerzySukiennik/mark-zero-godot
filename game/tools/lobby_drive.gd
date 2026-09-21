extends Node
## Drives the REAL lobby screen on each machine, and keeps watching after START MATCH.
##
##   godot --headless --path . res://tools/lobby_drive.tscn -- host
##   godot --headless --path . res://tools/lobby_drive.tscn -- join
##
## TWO THINGS THIS HAS TO DO THAT THE OBVIOUS VERSION CANNOT.
##
## It must go through LobbyUi rather than calling Net directly: net_host/net_join proved a
## packet crosses the house and said nothing about the screen, and the bug where two
## machines disagreed about who was who lived entirely in that gap.
##
## And it must SURVIVE the scene change. change_scene_to_file frees the current scene, so a
## driver parented inside it dies at the exact moment the thing being measured happens —
## which is why "does the client follow the host into the arena" went unnoticed. The Watch
## node is parked on the tree root, where nothing frees it, and it is what returns the
## verdict.

class Watch:
	extends Node
	var mode := "join"
	var t := 0.0
	var life := 60.0
	func _process(d: float) -> void:
		t += d
		var scene := get_tree().current_scene
		var here: String = scene.name if scene != null else "<none>"
		if int(t) % 5 == 0 and absf(t - roundf(t)) < d:
			print("[%s] t=%02d scene=%s online=%s players=%d"
				% [mode, int(t), here, Net.online, Net.players.size()])
		if here == "Arena":
			print("[%s] RESULT: REACHED THE ARENA after %.1fs" % [mode, t])
			get_tree().quit(0)
		if t > life:
			print("[%s] RESULT: STILL IN %s AFTER %.0fs — never entered the match"
				% [mode, here, life])
			get_tree().quit(1)

var _menu: Node
var _lob: Node
var _mode := "join"
var _t := 0.0
var _opened := false
var _started := false
var _last := ""

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_mode = a[0]
	Net.local_name = _mode.to_upper()
	var w := Watch.new()
	w.name = "Watch"
	w.mode = _mode
	get_tree().root.call_deferred("add_child", w)
	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_menu)
	await get_tree().process_frame
	_menu.call("_open_lobby")
	_lob = _menu.get("_lobby")
	print("[%s] lobby open" % _mode)

func _process(d: float) -> void:
	if _lob == null or not is_instance_valid(_lob):
		return
	_t += d
	var rows: Array = _lob.get("_rows")
	var text: Array = []
	for r in rows:
		text.append(("%s %s" % [r.get("label", ""), r.get("note", "")]).strip_edges())
	var now := " | ".join(text)
	if now != _last:
		_last = now
		print("[%s] screen: %s" % [_mode, now])

	if _mode == "host":
		if not _opened and _t > 1.5:
			_opened = true
			print("[host] pressing OPEN A ROOM")
			_lob.call("_press", "host")
		# START only once somebody is actually in the room — starting alone would prove
		# nothing about whether the other machine comes along.
		elif _opened and not _started and Net.players.size() >= 2 and _t > 4.0:
			_started = true
			print("[host] pressing START MATCH with %d in the room" % Net.players.size())
			_lob.call("_press", "start")
	else:
		# The joiner presses the room row and then NOTHING. It must be carried into the
		# match by the host, which is the whole point of the test.
		if not _opened:
			for r in rows:
				var kind := String(r.get("kind", ""))
				if kind.begins_with("join:"):
					_opened = true
					print("[join] pressing ROOM ROW: %s" % kind)
					_lob.call("_press", kind)
					break
