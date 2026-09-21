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
	## With `anim` on the command line the watcher does not stop at the arena door. The
	## host walks and then flies its own suit; the joiner measures whether the OTHER
	## player's armour is animating at all — the walk clock advancing, the pose system
	## running, the exhaust lit. Those are exactly the three things that were dead.
	var probe := false
	var arena_t := 0.0
	var stride_seen := 0.0
	var stride_moved := false
	var pose_moved := false
	var fx_lit := false
	var last_pose := ""
	var dumped := false

	func _mine(scene: Node) -> SuitPilot:
		for c in scene.get_children():
			if c is SuitPilot and (c as SuitPilot).is_mine:
				return c
		return null

	func _theirs(scene: Node) -> SuitPilot:
		for c in scene.get_children():
			if c is SuitPilot and not (c as SuitPilot).is_mine:
				return c
		return null

	func _sample(scene: Node, d: float) -> void:
		arena_t += d
		if mode == "host":
			# Walk for three seconds, then take off, so the watcher sees both cases.
			var me := _mine(scene)
			if me != null and me.model != null:
				if arena_t < 3.0:
					me.model.grounded = true
					me.model.velocity = me.model.basis_ * Vector3(0, 0, -4.0)
				else:
					me.model.grounded = false
					me.model.velocity = me.model.basis_ * Vector3(0, 2.0, -40.0)
					me.model.thrust_mag = 0.8
					me.model.hover_active = false
			if arena_t > 12.0:
				print("[host] done flying")
				get_tree().quit(0)
			return

		var them := _theirs(scene)
		if them == null:
			# Say WHAT is in the arena rather than only that the wanted thing is not.
			if not dumped and arena_t > 3.0:
				dumped = true
				var what: Array = []
				for c in scene.get_children():
					var mine := ""
					if c is SuitPilot:
						mine = " mine=%s peer=%d" % [(c as SuitPilot).is_mine, (c as SuitPilot).peer_id]
					elif c is SpiderPilot:
						mine = " mine=%s peer=%d" % [(c as SpiderPilot).is_mine, (c as SpiderPilot).peer_id]
					what.append("%s(%s)%s" % [c.name, c.get_class(), mine])
				print("[join] arena holds: ", ", ".join(what))
				print("[join] roster: ", Net.players, "  my_id=", Net.my_id)
			if arena_t > 14.0:
				print("[join] RESULT: NEVER SAW THE OTHER PLAYER'S SUIT")
				get_tree().quit(1)
			return
		if them.model != null:
			if absf(them.model.stride_phase - stride_seen) > 0.01:
				stride_moved = true
			stride_seen = them.model.stride_phase
		if them.poses != null:
			# The pose blend lives on Poses, not on the rig. Comparing its printed form is
			# crude and exactly right for the question being asked: is it changing at all?
			var now_pose := str(them.poses.blend)
			if last_pose != "" and now_pose != last_pose:
				pose_moved = true
			last_pose = now_pose
		if them.fx != null:
			# `_level` is what drive() writes per nozzle — the emitters themselves are
			# plain dictionaries, so asking one for `.light` throws every frame and takes
			# the whole sampler down with it.
			for lv in them.fx._level:
				if float(lv) > 0.05:
					fx_lit = true
		if arena_t > 12.0:
			print("[join] walk clock advancing: %s" % stride_moved)
			print("[join] pose blend changing:  %s" % pose_moved)
			print("[join] repulsors lit:        %s" % fx_lit)
			var ok := stride_moved and pose_moved and fx_lit
			print("[join] RESULT: %s" % ("THE OTHER SUIT IS ANIMATING" if ok
				else "THE OTHER SUIT IS STILL DEAD"))
			get_tree().quit(0 if ok else 1)
	func _process(d: float) -> void:
		t += d
		var scene := get_tree().current_scene
		var here: String = scene.name if scene != null else "<none>"
		if int(t) % 5 == 0 and absf(t - roundf(t)) < d:
			print("[%s] t=%02d scene=%s online=%s players=%d"
				% [mode, int(t), here, Net.online, Net.players.size()])
		if here == "Arena":
			if not probe:
				print("[%s] RESULT: REACHED THE ARENA after %.1fs" % [mode, t])
				get_tree().quit(0)
			_sample(scene, d)
			return
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
	w.probe = "anim" in a
	w.life = 90.0 if w.probe else 60.0
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
