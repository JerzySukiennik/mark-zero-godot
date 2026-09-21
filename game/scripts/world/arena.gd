class_name Arena
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

	build_sky(self)
	# DEFERRED. Switching hero frees the entity whose own menu emitted the change, from
	# inside that signal; rebuilding the roster on the next idle frame keeps the teardown
	# and the rebuild from overlapping.
	Net.peers_changed.connect(func(): call_deferred("_sync_suits"))
	_sync_suits()
	print("[mark zero] ready — %d suit(s), camera %s" % [
		suits.size(), "yes" if get_viewport().get_camera_3d() != null else "NONE"])

## The LOOK OF THE GAME, in one place and static so every preview tool renders through this
## exact code. A preview with its own copy of the lighting proves nothing about the game —
## which is how the armour passed a render while being grey in the thing Jurek plays.
static func build_sky(parent: Node) -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	# A brighter sky is not a mood choice here: it IS the suit's key light, because a sky
	# this size is the only large source in an empty scene.
	# WARM, AND NOT ONE COLOUR. Jurek: "stroje są strasznie szare i grumpy" — and they were,
	# because the sky was a flat blue-grey from top to bottom. A polished metal figure is
	# almost entirely a mirror of the sky, so a sky with no colour in it hands the armour no
	# colour to reflect, whatever the albedo of its plates says.
	#
	# The fix is a sky with a GRADIENT the metal can pick up: cold indigo overhead and a hot
	# amber band at the horizon. Every curved plate then catches both, which is what makes a
	# suit read as gold and crimson rather than as a grey mannequin. It is also what a city
	# at dusk actually looks like, so it costs nothing in believability.
	mat.sky_top_color = Color(0.08, 0.14, 0.28)
	mat.sky_horizon_color = Color(0.44, 0.26, 0.21)
	mat.ground_bottom_color = Color(0.06, 0.05, 0.05)
	mat.ground_horizon_color = Color(0.22, 0.13, 0.10)
	# A tight, bright sun disc in that band — a second highlight rolling over the plates as
	# he banks, and the single cheapest thing that makes metal look like metal.
	mat.sun_angle_max = 6.0
	mat.sun_curve = 0.12
	# THE BAND HAS TO STAY LOW. Left at the default the horizon colour climbs most of the
	# way up the dome and the whole picture turns into one orange wash — which is the same
	# mistake as the grey one, just a warmer flavour of it. A tight curve keeps the sky
	# blue overhead and the heat in a strip, so the two colours can play off each other
	# across a curved plate instead of one of them winning.
	mat.sky_curve = 0.02
	mat.ground_curve = 0.04
	# THE lever for a metal subject. Measured on the Mark I hovering: 1.25 gave a suit
	# luminance of 0.195 and 2.60 gives 0.295, which is the difference between a black
	# silhouette and readable plates and panel lines. Raising the LIGHTS did nothing for
	# two rounds because metal has almost no diffuse response — what you see on it is the
	# sky, so the sky is what has to be brighter.
	mat.sky_energy_multiplier = 3.10
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
	env.adjustment_contrast = 1.08
	# Pushed hard on purpose. The whole complaint was that the picture had no colour in it,
	# and a scene lit almost entirely by a sky answers saturation more than it answers any
	# light's energy.
	env.adjustment_saturation = 1.22
	# Haze over a city this size is not a mood, it is depth: without it the far end of the
	# island reads as being the same distance away as the next block.
	env.fog_enabled = true
		# CUT BY HALF. With a warm sky the haze stopped being depth and became a coat of paint:
	# at 0.0009 every building, the plate and the far half of the frame all settled on the
	# same dusty rose, which is a wash by another route.
	env.fog_density = 0.00040
	# The haze takes the horizon's colour rather than a neutral grey, so distance warms the
	# picture instead of draining it.
	env.fog_light_color = Color(0.22, 0.21, 0.27)

	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, -125, 0)
	# STRONG, now that the world itself is near-black. Directional light is the one lever
	# that separates the two: the plate's albedo is 0.03 so it barely answers, while the
	# armour is polished metal and answers hard. That is how the map stays black with white
	# lines while the suit stops being a silhouette — both of which Jurek has asked for, and
	# which turning the SKY up could not do at once, because the sky lights everything.
	sun.light_energy = 2.5
	# Low and warm, to match the band it is sitting in.
	sun.light_color = Color(1.0, 0.82, 0.60)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	parent.add_child(sun)

	# A cool fill from the opposite side, with no shadow. Without it the unlit side of the
	# armour goes to black and the silhouette loses all its shape — the single biggest reason
	# a metal figure reads as "too dark" even when the key light is strong.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 55, 0)
	fill.light_energy = 1.15
	# Deliberately the OPPOSITE colour to the sun. Warm key against cool fill is what gives
	# a curved metal surface two colours to separate its forms with; two white lights give
	# it one, and one is grey.
	fill.light_color = Color(0.46, 0.62, 1.0)
	fill.shadow_enabled = false
	parent.add_child(fill)

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
		# BOTH HEROES. This used to publish the armour only, on the grounds that Spider-Man
		# had no remote body worth sending — which stopped being true when the Iron Spider
		# model landed, and left the Iron Man player watching a statue for a whole match.
		if suits[id].has_method("publish"):
			suits[id].publish()

static func _hero_of(n: Node) -> String:
	return "spiderman" if n is SpiderPilot else "ironman"

