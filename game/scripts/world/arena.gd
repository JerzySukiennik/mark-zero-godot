extends Node3D
## The playable scene: a city, a sky, and however many suits are in the room.
##
## Spawning is driven off Net's roster rather than off a scene full of pre-placed players,
## so a solo run and an eight-player room take exactly the same code path. A solo run IS a
## room with one peer in it — that is what "multiplayer from day one" buys.

var city: City
var suits: Dictionary = {}          ## peer id -> SuitPilot
var _publish_acc := 0.0
const PUBLISH_HZ := 20.0

func _ready() -> void:
	# Printed so a log file can prove the scene actually started, which is the difference
	# between "it launched and rendered nothing" and "it never launched".
	print("[mark zero] arena starting — display %s, renderer %s" % [
		DisplayServer.get_name(), RenderingServer.get_video_adapter_name()])
	city = City.new()
	city.name = "City"
	add_child(city)
	_sky()
	Net.peers_changed.connect(_sync_suits)
	_sync_suits()
	print("[mark zero] ready — %d suit(s), camera %s" % [
		suits.size(), "yes" if get_viewport().get_camera_3d() != null else "NONE"])

func _sky() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.13, 0.22, 0.38)
	mat.sky_horizon_color = Color(0.58, 0.62, 0.66)
	mat.ground_bottom_color = Color(0.08, 0.08, 0.09)
	mat.ground_horizon_color = Color(0.45, 0.47, 0.50)
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.5
	# Haze over a city this size is not a mood, it is depth: without it the far end of the
	# island reads as being the same distance away as the next block.
	env.fog_enabled = true
	env.fog_density = 0.0009
	env.fog_light_color = Color(0.55, 0.60, 0.66)

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -125, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	add_child(sun)

func _sync_suits() -> void:
	# Anyone in the roster who has no suit yet gets one; anyone who left loses theirs.
	for id in Net.players:
		if not suits.has(id):
			var s := SuitPilot.new()
			s.name = "Suit_%d" % id
			s.setup(id, Net.players[id].get("armor", "mk3"), city)
			# Spread the spawns down the avenue so nobody starts inside anybody.
			var i := suits.size()
			s.position = Vector3(0, 220, -city.span_z() * 0.35 + i * 25.0)
			add_child(s)
			s.model.position = s.position
			suits[id] = s
	for id in suits.keys():
		if not Net.players.has(id):
			suits[id].queue_free()
			suits.erase(id)

func _physics_process(delta: float) -> void:
	if not Net.online:
		return
	_publish_acc += delta
	if _publish_acc < 1.0 / PUBLISH_HZ:
		return
	_publish_acc = 0.0
	for id in suits:
		suits[id].publish()
