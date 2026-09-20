class_name MainMenu
extends Node3D
## The front of the game.
##
## Jurek's brief: the two of them hanging there, Spider-Man with a line out, the camera
## drifting round in slow motion, and four things to press. So the menu is a SCENE rather
## than a screen — the same models, the same lighting, the same web strand the game uses,
## shown doing nothing in particular. A title card made of stills would need art nobody has
## made; this needs nothing that does not already exist.

const ITEMS := ["SINGLE PLAYER", "MULTIPLAYER", "OPTIONS", "QUIT"]
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

func _ready() -> void:
	_sky()
	_build_heroes()
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.current = true

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_ui = _MenuUi.new()
	_ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(_ui)
	_ui.chosen.connect(_choose)

	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

## The same environment the arena uses, because the menu showing a different sky than the
## game is the cheapest possible way to look unfinished.
func _sky() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.10, 0.14, 0.22)
	mat.sky_horizon_color = Color(0.30, 0.34, 0.40)
	mat.ground_bottom_color = Color(0.05, 0.05, 0.06)
	mat.ground_horizon_color = Color(0.16, 0.17, 0.19)
	# LOWER THAN THE MAP'S. 2.6 was chosen to lift a metal figure off a near-black plate;
	# here there is no plate to fight, so the same value simply blows the armour out into a
	# pale ghost. The suit is polished metal — what it reflects IS the lighting, so the
	# backdrop is the exposure control.
	mat.sky_energy_multiplier = 1.15
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.60
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.16, 0.18, 0.22)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -128, 0)
	sun.light_energy = 3.0
	sun.light_color = Color(1.0, 0.96, 0.90)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-16, 58, 0)
	fill.light_energy = 1.05
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

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
		"SINGLE PLAYER":
			get_tree().change_scene_to_file("res://scenes/world/arena.tscn")
		"MULTIPLAYER":
			# Hosting IS single player plus a door — the arena already spawns off Net's
			# roster, so there is no separate mode to write.
			Net.host()
			get_tree().change_scene_to_file("res://scenes/world/arena.tscn")
		"OPTIONS":
			_ui.show_options()
		"QUIT":
			get_tree().quit()

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
