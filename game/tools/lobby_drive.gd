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
	var moved := false
	var last_pos := Vector3.ZERO
	var kind := ""

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

	func _mine(scene: Node) -> Node:
		for c in scene.get_children():
			if (c is SuitPilot or c is SpiderPilot) and c.get("is_mine"):
				return c
		return null

	func _theirs(scene: Node) -> Node:
		for c in scene.get_children():
			if (c is SuitPilot or c is SpiderPilot) and not c.get("is_mine"):
				return c
		return null

	## Both machines do the SAME thing: move their own body and measure the other one.
	## One run therefore tests replication in both directions, which matters because the
	## armour and Spider-Man are separate implementations that failed separately.
	func _sample(scene: Node, d: float) -> void:
		arena_t += d
		var me := _mine(scene)
		if me != null and me.model != null:
			# Walk for three seconds, then leave the ground, so the watcher on the other
			# machine sees both a stride and an airborne pose.
			if arena_t < 3.0:
				me.model.grounded = true
				me.model.velocity = me.model.basis_ * Vector3(0, 0, -4.0)
			else:
				me.model.grounded = false
				me.model.velocity = me.model.basis_ * Vector3(0, 2.0, -30.0)
				if me is SuitPilot:
					me.model.thrust_mag = 0.8

		var them := _theirs(scene)
		if them == null:
			if not dumped and arena_t > 3.0:
				dumped = true
				var what: Array = []
				for c in scene.get_children():
					what.append("%s(%s)" % [c.name, c.get_class()])
				print("[%s] arena holds: %s" % [mode, ", ".join(what)])
				print("[%s] roster: %s  my_id=%d" % [mode, Net.players, Net.my_id])
			if arena_t > 16.0:
				print("[%s] RESULT: NEVER SAW THE OTHER PLAYER'S BODY" % mode)
				get_tree().quit(1)
			return

		if kind == "":
			kind = "IRON MAN" if them is SuitPilot else "SPIDER-MAN"
			print("[%s] watching a %s" % [mode, kind])
		if them.global_position.distance_to(last_pos) > 0.05:
			moved = true
		last_pos = them.global_position
		if them.model != null:
			if absf(them.model.stride_phase - stride_seen) > 0.01:
				stride_moved = true
			stride_seen = them.model.stride_phase
		if them.poses != null:
			var now_pose := str(them.poses.blend)
			if last_pose != "" and now_pose != last_pose:
				pose_moved = true
			last_pose = now_pose
		if them is SuitPilot and them.fx != null:
			for lv in them.fx._level:
				if float(lv) > 0.05:
					fx_lit = true

		# LATCH AS SOON AS THE EVIDENCE IS IN, rather than at a fixed time. Both machines
		# exit when they are done, and whichever finishes first takes its body out of the
		# other one's world — which is how a passing Spider-Man once got reported as
		# "never saw the other player's body": it had been there, watched and sampled, and
		# was freed by the disconnect a second before the deadline.
		var have: bool = moved and stride_moved and pose_moved \
			and (fx_lit or not (them is SuitPilot))
		if (have and arena_t > 5.0) or arena_t > 20.0:
			print("[%s] body moving across the map: %s" % [mode, moved])
			print("[%s] walk clock advancing:      %s" % [mode, stride_moved])
			print("[%s] pose blend changing:       %s" % [mode, pose_moved])
			if them is SuitPilot:
				print("[%s] repulsors lit:              %s" % [mode, fx_lit])
			var ok := have
			print("[%s] RESULT: the remote %s is %s" % [mode, kind,
				"ANIMATING" if ok else "STILL DEAD"])
			get_tree().quit(0 if ok else 1)

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
