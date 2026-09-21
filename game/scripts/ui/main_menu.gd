class_name MainMenu
extends Node3D
## The front of the game.
##
## Jurek's brief: the two of them hanging there, Spider-Man with a line out, the camera
## drifting round in slow motion, and four things to press. So the menu is a SCENE rather
## than a screen — the same models, the same lighting, the same web strand the game uses,
## shown doing nothing in particular. A title card made of stills would need art nobody has
## made; this needs nothing that does not already exist.

## One PLAY, not a solo item and a multiplayer item. Both used to lead to the arena by
## different routes, and neither asked which character you were — so the choice happened
## later, in the middle of a fight, from the suit menu. Everything about a match that has
## to be settled before it starts is now settled in one place. See scripts/ui/lobby_ui.gd.
const ITEMS := ["PLAY", "OPTIONS", "QUIT"]
## Seconds for one full turn of the camera. Slow enough to read as a held shot rather than
## a turntable, which is the whole of "zwolnione tempo".
const ORBIT_TIME := 54.0
const ORBIT_RADIUS := 7.6
const ORBIT_HEIGHT := 1.9

var _t := 0.0
var _cam: Camera3D
var _ui: _MenuUi
var _iron: Node3D
var _spider: Node3D
var _iron_rig: SuitRig
var _spider_rig: SuitRig
var _web: WebLine
var _iron_fx: Thrusters
var _bob := 0.0
var _lobby: LobbyUi
var _layer: CanvasLayer

func _ready() -> void:
	_sky()
	_build_heroes()
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.current = true

	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	_ui = _MenuUi.new()
	_ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layer.add_child(_ui)
	_ui.chosen.connect(_choose)

	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

## The same environment the arena uses — and now literally the same code, not a copy of
## it. It WAS a copy, with its own sky energy and its own sun, which had already drifted
## far enough that the menu and the game were lit differently. A duplicated look is a look
## that will be wrong in one of the two places. See Arena.build_sky.
func _sky() -> void:
	Arena.build_sky(self)

func _build_heroes() -> void:
	# The armour, hovering, with its boots lit — the pose the whole game is about.
	# THE MARK III, not the Mark L. The nanotech suit's own texture is near-white, so under
	# any lighting bright enough to show a metal figure it reads as a pale ghost — which is
	# exactly what Jurek saw and described as "przezroczyste". That is a model to recolour,
	# not a light to tune, and the menu should not be the place it gets discovered.
	_iron = SuitLoader.load_suit("res://assets/suits/mk3.glb")
	if _iron != null:
		add_child(_iron)
		_iron.position = Vector3(-1.5, 0.3, 0)
		_iron.rotation.y = deg_to_rad(28)
		_iron_rig = SuitRig.new()
		_iron_rig.index(_iron)
		_iron_rig.set_pose("hover")
		_iron_fx = Thrusters.new()
		add_child(_iron_fx)
		_iron_fx.attach(_iron_rig)

	# And Spider-Man, mid-swing, with a line already out. A web going somewhere off frame
	# says more about the game than any pose of him standing still could.
	_spider = SuitLoader.load_suit("res://assets/suits/ironspider.glb")
	if _spider != null:
		add_child(_spider)
		_spider.position = Vector3(1.7, -0.5, 0.4)
		_spider.rotation.y = deg_to_rad(-22)
		_spider_rig = SuitRig.new()
		_spider_rig.index(_spider)
		_spider_rig.pose_table = SpiderPoses.POSES
		_spider_rig.set_pose("swing")
		# The carrying arm, pointed up the line exactly as it is in play.
		_spider_rig.aim_joint("piv_shoulder" + SuitRig.SIDE["R"], Vector3(-0.22, 0.95, -0.22).normalized())
		_spider_rig.aim_joint("piv_elbow" + SuitRig.SIDE["R"], Vector3(0, 0.99, -0.14).normalized())

	_web = WebLine.new()
	_web.build()
	add_child(_web)

func _process(delta: float) -> void:
	_t += delta
	_bob += delta

	# The orbit. One slow revolution, with the camera easing up and down a little so it
	# never reads as a fixed turntable.
	var a := _t / ORBIT_TIME * TAU
	var h := ORBIT_HEIGHT + sin(_t * 0.23) * 0.7
	_cam.position = Vector3(sin(a) * ORBIT_RADIUS, h, cos(a) * ORBIT_RADIUS)
	_cam.look_at(Vector3(0, 0.55, 0), Vector3.UP)

	# Neither of them is still. A menu of frozen models is a screenshot.
	if _iron != null:
		_iron.position.y = 0.3 + sin(_bob * 0.9) * 0.10
		_iron.rotation.y = deg_to_rad(28) + sin(_bob * 0.35) * 0.06
		if _iron_rig != null:
			_iron_rig.update_pose(delta)
	if _iron_fx != null:
		_iron_fx.drive(delta, 0.0, 0.0, 0.0, 0.0, 0.62)
	if _spider != null:
		_spider.position.y = -0.5 + sin(_bob * 0.7 + 1.1) * 0.14
		_spider.rotation.z = sin(_bob * 0.5) * 0.05
		if _spider_rig != null:
			_spider_rig.update_pose(delta)

	if _web != null and _spider_rig != null and _spider_rig.has_pivot("piv_palm" + SuitRig.SIDE["R"]):
		var hand: Node3D = _spider_rig.pivots["piv_palm" + SuitRig.SIDE["R"]]
		# Anchored up and behind, off frame: the line has somewhere to be going.
		_web.draw_web(hand.global_position, Vector3(6.0, 11.0, -7.0), 0.0, 1.0, _cam.global_position)

func _choose(item: String) -> void:
	match item:
		"PLAY":
			_open_lobby()
		"OPTIONS":
			_ui.show_options()
		"QUIT":
			get_tree().quit()

## The lobby is drawn OVER this scene rather than replacing it, so the two of them keep
## hovering behind the choice. Picking a side while looking at the side you are picking is
## the entire reason the menu was built as a scene in the first place.
func _open_lobby() -> void:
	if _lobby != null and is_instance_valid(_lobby):
		return
	_ui.visible = false
	_lobby = LobbyUi.new()
	_lobby.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_layer.add_child(_lobby)
	_lobby.back.connect(_close_lobby)
	_lobby.start_requested.connect(_start)
	# SUBSCRIBED THE MOMENT THE LOBBY OPENS, not when START is pressed.
	#
	# This used to live inside _start(), which runs only on the machine that pressed START
	# MATCH — and only the host ever presses it; every other player's lobby says "waiting
	# for the host". So the host's own scene change worked, the RPC arrived on the client,
	# Net emitted match_started, and on the client NOTHING was listening to it. The client
	# sat in the lobby forever while the host dropped into the arena alone. Jurek: "jak
	# zaczynam grę z hosta to nie dołącza mi gracza."
	#
	# Everyone sitting in the lobby is waiting for the same event, so everyone listens for
	# it from the moment they are in the lobby.
	if not Net.match_started.is_connected(_enter):
		Net.match_started.connect(_enter, CONNECT_ONE_SHOT)

func _close_lobby() -> void:
	if _lobby != null and is_instance_valid(_lobby):
		_lobby.queue_free()
	_lobby = null
	_ui.visible = true
	# Backing out of the lobby means you are no longer waiting for anybody's match.
	if Net.match_started.is_connected(_enter):
		Net.match_started.disconnect(_enter)

func _start() -> void:
	# The host tells everyone at once; solo this is the same call with nothing under it.
	# It also locks the sides, which is what makes the lobby the only place they are asked.
	# The listener is already in place from _open_lobby — see the note there for why it
	# cannot be set up here.
	Net.begin_match()

func _enter() -> void:
	get_tree().change_scene_to_file("res://scenes/world/arena.tscn")

## The list itself. A Control rather than a set of nodes, for the same reason the HUD is:
## four labels and a highlight are less code drawn than assembled, and far less to keep in
## step when the wording changes.
class _MenuUi:
	extends Control
	signal chosen(item: String)

	const CYAN := Color(0.55, 0.88, 1.0)
	const DIM := Color(0.48, 0.58, 0.68)

	var row := 0
	var options_open := false
	var _cool := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func show_options() -> void:
		options_open = true
		queue_redraw()

	func _process(delta: float) -> void:
		size = get_viewport_rect().size
		_cool = maxf(0.0, _cool - delta)

		if options_open:
			if Input.is_action_just_pressed("ui_back") or Input.is_action_just_pressed("ui_cancel"):
				options_open = false
				Sfx.flat("ui_close", -10.0)
			queue_redraw()
			return

		var mv := Pad.move().y if Pad.connected else 0.0
		if Input.is_action_pressed("ui_down"):
			mv = 1.0
		elif Input.is_action_pressed("ui_up"):
			mv = -1.0
		if absf(mv) > 0.55 and _cool <= 0.0:
			row = wrapi(row + (1 if mv > 0.0 else -1), 0, ITEMS.size())
			_cool = 0.18
			Sfx.flat("ui_move", -13.0)
		elif absf(mv) < 0.3:
			_cool = 0.0

		if Input.is_action_just_pressed("ui_accept") or Pad.just_pressed("ui_accept_pad"):
			Sfx.flat("ui_select", -9.0)
			chosen.emit(ITEMS[row])
		queue_redraw()

	func _draw() -> void:
		var u: float = maxf(0.55, size.y / 1080.0)
		var font := ThemeDB.fallback_font

		# The title, top left, where the HUD's own name panel sits — the menu and the game
		# share a corner so the interface reads as one thing.
		draw_string(font, Vector2(72 * u, 108 * u), "MARK ZERO",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(64 * u), CYAN)
		draw_string(font, Vector2(76 * u, 142 * u), "IRON MAN  ·  SPIDER-MAN",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * u), DIM)

		if options_open:
			_draw_options(u, font)
			return

		var y := size.y - 340.0 * u
		for i in ITEMS.size():
			var on := i == row
			var col := CYAN if on else DIM
			var fs := int((38.0 if on else 30.0) * u)
			if on:
				# A bar rather than a box: it marks the line without drawing a button
				# around text that is already the button.
				draw_rect(Rect2(Vector2(64 * u, y - 26 * u), Vector2(5 * u, 34 * u)), CYAN, true)
			draw_string(font, Vector2(86 * u, y), ITEMS[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			y += 58 * u

		draw_string(font, Vector2(72 * u, size.y - 56 * u),
			"STICK / ARROWS  MOVE      ✕ / ENTER  SELECT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * u), DIM)

	func _draw_options(u: float, font: Font) -> void:
		var x := 86.0 * u
		var y := size.y - 340.0 * u
		draw_string(font, Vector2(x, y), "OPTIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * u), CYAN)
		y += 52 * u
		# Honest about what is here. A settings screen full of controls that do nothing is
		# worse than one that says so.
		for line in ["CONTROLLER ONLY — a pad is required to play",
					 "LOOK AND FLIGHT TUNING  ·  not yet",
					 "AUDIO LEVELS  ·  not yet"]:
			draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * u), DIM)
			y += 30 * u
		draw_string(font, Vector2(x, size.y - 56 * u), "○ / ESC  BACK",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * u), DIM)
