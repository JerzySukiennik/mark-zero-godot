extends Node3D
## The playable scene: a city, a sky, and however many suits are in the room.
##
## Spawning is driven off Net's roster rather than off a scene full of pre-placed players,
## so a solo run and an eight-player room take exactly the same code path. A solo run IS a
## room with one peer in it — that is what "multiplayer from day one" buys.

var stage: Stage
var squad: Squad
var suits: Dictionary = {}          ## peer id -> SuitPilot
var _publish_acc := 0.0
const PUBLISH_HZ := 20.0

func _ready() -> void:
	# Printed so a log file can prove the scene actually started, which is the difference
	# between "it launched and rendered nothing" and "it never launched".
	print("[mark zero] arena starting — display %s, renderer %s" % [
		DisplayServer.get_name(), RenderingServer.get_video_adapter_name()])
	# Sound first, so anything that makes a noise on its very first frame can be heard.
	var sfx := Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)

	stage = Stage.new()
	stage.name = "Stage"
	add_child(stage)
	# The opposition. Built after the stage so it can put people on the plate, and before
	# the suits so a spawn on the first frame already has somewhere to stand.
	squad = Squad.new()
	squad.setup(stage)
	add_child(squad)
	# Escape, and the way out of the game.
	var pause := PauseMenu.new()
	pause.name = "PauseMenu"
	add_child(pause)

	_sky()
	# DEFERRED. Switching hero frees the entity whose own menu emitted the change, from
	# inside that signal; rebuilding the roster on the next idle frame keeps the teardown
	# and the rebuild from overlapping.
	Net.peers_changed.connect(func(): call_deferred("_sync_suits"))
	_sync_suits()
	print("[mark zero] ready — %d suit(s), camera %s" % [
		suits.size(), "yes" if get_viewport().get_camera_3d() != null else "NONE"])

func _sky() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	# A brighter sky is not a mood choice here: it IS the suit's key light, because a sky
	# this size is the only large source in an empty scene.
	mat.sky_top_color = Color(0.10, 0.14, 0.22)
	mat.sky_horizon_color = Color(0.30, 0.34, 0.40)
	mat.ground_bottom_color = Color(0.05, 0.05, 0.06)
	mat.ground_horizon_color = Color(0.16, 0.17, 0.19)
	# THE lever for a metal subject. Measured on the Mark I hovering: 1.25 gave a suit
	# luminance of 0.195 and 2.60 gives 0.295, which is the difference between a black
	# silhouette and readable plates and panel lines. Raising the LIGHTS did nothing for
	# two rounds because metal has almost no diffuse response — what you see on it is the
	# sky, so the sky is what has to be brighter.
	mat.sky_energy_multiplier = 2.60
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# The subject is a dark red and gold METAL figure, and metal has almost no diffuse
	# response — nearly everything you see on it is reflected environment. Lighting tuned for
	# a city of flat concrete leaves the suit reading as a silhouette. Jurek: "strój jest
	# zbyt ciemny."
	# NOT the lever, measured: sweeping this from 1.35 to 2.30 moved the armour's brightness
	# by 0.001. With ambient_light_source = SKY the sky's own energy is what drives both the
	# ambient and the reflection, and a metal figure is almost entirely reflection. Left at
	# a sane value rather than tuned.
	env.ambient_light_energy = 1.60
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.5
	# Brightens the midtones without blowing the highlights, which is what a metal subject
	# against a bright sky needs — raising exposure alone would just clip the sky.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.06
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.10
	# Haze over a city this size is not a mood, it is depth: without it the far end of the
	# island reads as being the same distance away as the next block.
	env.fog_enabled = true
	env.fog_density = 0.0009
	env.fog_light_color = Color(0.16, 0.18, 0.22)

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -125, 0)
	# STRONG, now that the world itself is near-black. Directional light is the one lever
	# that separates the two: the plate's albedo is 0.03 so it barely answers, while the
	# armour is polished metal and answers hard. That is how the map stays black with white
	# lines while the suit stops being a silhouette — both of which Jurek has asked for, and
	# which turning the SKY up could not do at once, because the sky lights everything.
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	add_child(sun)

	# A cool fill from the opposite side, with no shadow. Without it the unlit side of the
	# armour goes to black and the silhouette loses all its shape — the single biggest reason
	# a metal figure reads as "too dark" even when the key light is strong.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 55, 0)
	fill.light_energy = 1.05
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

func _sync_suits() -> void:
	# Anyone in the roster who has no suit yet gets one; anyone who left loses theirs.
	for id in Net.players:
		var hero: String = Net.players[id].get("hero", "ironman")
		# A player who switched sides needs a different BODY, not a different costume, so
		# the old entity is thrown away and the loop below builds the right one.
		if suits.has(id) and _hero_of(suits[id]) != hero:
			suits[id].queue_free()
			suits.erase(id)
		if not suits.has(id):
			# Spread the spawns so nobody starts inside anybody.
			var i := suits.size()
			# On the plate, not two hundred metres up: the character is the thing being
			# looked at.
			var at := Vector3(i * 4.0, Stage.GROUND_Y + 1.0, 0)
			var n: Node3D
			if hero == "spiderman":
				var sp := SpiderPilot.new()
				sp.name = "Spider_%d" % id
				sp.setup(id, stage)
				sp.position = at
				add_child(sp)
				sp.model.position = at
				n = sp
			else:
				var s := SuitPilot.new()
				s.name = "Suit_%d" % id
				s.setup(id, Net.players[id].get("armor", "mk1"), stage)
				s.position = at
				add_child(s)
				s.model.position = at
				n = s
			suits[id] = n
	for id in suits.keys():
		if not Net.players.has(id):
			suits[id].queue_free()
			suits.erase(id)

func _physics_process(delta: float) -> void:
	# BEFORE the online check. This sat after it, which meant the readout only ever
	# appeared in a multiplayer room — and the whole reason it exists is a player alone on
	# the plate asking whether anything had spawned at all.
	#
	# Told, not fetched: the HUD is deliberately unable to reach into the scene tree.
	var standing: int = squad.standing() if squad != null else 0
	for pid in suits:
		var pilot = suits[pid]
		if pilot != null and pilot.get("visor") != null and pilot.visor.hud != null:
			pilot.visor.hud.threats = standing

	if not Net.online:
		return
	_publish_acc += delta
	if _publish_acc < 1.0 / PUBLISH_HZ:
		return
	_publish_acc = 0.0

	for id in suits:
		# Only the armour syncs for now; Spider-Man's remote representation comes with the
		# Iron Spider model, and publishing a body nobody can see yet buys nothing.
		if suits[id] is SuitPilot:
			suits[id].publish()

static func _hero_of(n: Node) -> String:
	return "spiderman" if n is SpiderPilot else "ironman"

