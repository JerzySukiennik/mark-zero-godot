class_name SuitLoader
extends RefCounted
## Loading the armour models without needing Godot's import step.
##
## WHY THIS EXISTS. Godot normally converts a .glb into its own format on import, and only
## the converted result can be load()ed. That import is an EDITOR job: `--headless --import`
## scans the files, writes nothing, reports no error whatsoever and leaves them marked
## invalid. Measured on two machines — the Mac and the laptop with a real RTX 3050 — so it
## is the engine's behaviour and not a quirk of one setup.
##
## The consequence was a game that ran perfectly and had no suit in it, because the city,
## the sky and the flight model are all code while the armour is the one thing that is an
## asset. Every fresh install would have hit this, and the fix — "open the editor once" —
## is a step that is easy to skip and gives no clue when it is missed.
##
## So the suits are parsed at RUNTIME from the .glb bytes, which is a first-class Godot API
## and needs no import at all. An imported version is still preferred when one exists, so
## nothing is lost on a machine where the editor has been opened; this is a floor, not a
## replacement.
##
## Cost: no automatic LODs or shadow meshes on the suits. For six models of about three
## megabytes, carried by the player and never more than a handful on screen, that is a price
## worth paying to make the game work the moment it is cloned.

static var _cache: Dictionary = {}

## Returns a fresh Node3D for `path`, or null. Safe to call repeatedly — the parsed scene is
## cached, and each caller gets its own instance of it.
static func load_suit(path: String) -> Node3D:
	if _cache.has(path):
		var packed: PackedScene = _cache[path]
		return packed.instantiate() if packed != null else null

	# Always the runtime path, never ResourceLoader. Asking for the imported resource first
	# sounded harmless and is not: a .import file exists beside every .glb whether or not the
	# import ever succeeded, so ResourceLoader.exists() says yes, load() then fails, and
	# Godot prints two errors per suit per session before the fallback quietly works. One
	# path that always works beats two where the first one shouts on the way past.
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("[suit] %s is missing or empty" % path)
		_cache[path] = null
		return null

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	# base_path matters for a .gltf with separate files beside it. These are .glb with
	# everything embedded, but passing the real folder costs nothing and keeps it correct
	# if a loose-file model is ever added.
	var err := doc.append_from_buffer(bytes, path.get_base_dir(), state)
	if err != OK:
		push_warning("[suit] %s would not parse (error %d)" % [path, err])
		_cache[path] = null
		return null

	var node := doc.generate_scene(state)
	if node == null:
		push_warning("[suit] %s parsed but produced no scene" % path)
		_cache[path] = null
		return null

	# Done once, here, before the scene is packed — so every spawn gets it for free and no
	# caller has to remember.
	_polish(node)

	# Pack it once so later instances are cheap: parsing three megabytes of glTF on every
	# spawn would be felt the moment a second player joins.
	var packed := PackedScene.new()
	_pack_owner(node, node)
	if packed.pack(node) != OK:
		push_warning("[suit] %s could not be packed for reuse" % path)
		_cache[path] = null
		return node as Node3D          # still usable once
	_cache[path] = packed
	node.queue_free()
	return packed.instantiate() as Node3D

## PackedScene.pack() only keeps children whose `owner` is the root. A scene built at runtime
## has no owners set, so packing one without this returns a root with nothing inside it —
## which looks exactly like a model that loaded and is invisible.
static func _pack_owner(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_pack_owner(c, root)

## POLISH THE ARMOUR.
##
## Measured off the shipped models, every plate came in at roughness 1.00 with metallic up
## to 0.90 — and a fully rough metal is the darkest thing you can put in a scene. Metal has
## almost no diffuse response, so nearly everything you see on it is reflected environment;
## at roughness 1 that reflection is smeared into a uniform dim grey, and with only a sky to
## reflect it goes nearly black. That is why the suit stayed "zbyt ciemny" through two
## rounds of turning the LIGHTS up: the lights were never the problem, the surface was.
##
## Polishing it is also just correct. Tony's armour is a mirror.
const MAX_ROUGHNESS := 0.34
const MIN_SPECULAR := 0.55
## A FLOOR UNDER THE ARMOUR, so it never goes to pure black.
##
## Jurek wants two things that fight: a map that is black with white lines, and a suit that
## is not a silhouette. Turning the SKY up gives the second and loses the first, because
## the sky lights everything; turning the LIGHTS up does almost nothing, because polished
## metal answers a directional with a small sharp highlight rather than a broad wash. A
## little emission on the plates is the one lever that touches the suit and nothing else.
## It is the same trick as a rim light on a film set: not physical, and it is what makes a
## dark subject readable against a dark background.
## Was 0.11 while the operator was ADD, where it meant a flat white 0.11 on top of every
## plate. Under MULTIPLY it means "0.11 OF the plate's own colour", which is a fraction of
## a dark texture and therefore almost nothing — the armour measured 0.082 luminance, down
## from 0.195. Same number, completely different quantity. Raised until the plates read
## again, and it is still tinted, so nothing greys out.
const PLATE_GLOW := 0.55
##
## NOT by lifting albedo. That was tried at 1.75 and at 1.18 and both rendered the armour
## as a featureless white blob, which is not a tuning miss — for a METAL, albedo_color is
## the specular reflectance, so pushing it past one makes the surface reflect more light
## than reaches it. With a bright sky, a near-mirror roughness and a glow pass on top, it
## runs away immediately. Brightness has to come from the lighting and the roughness.

static func _polish(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var m = mesh.surface_get_material(i)
				if m is StandardMaterial3D:
					var sm: StandardMaterial3D = m
					# BACK FACES OFF. Every plate arrives double-sided, so the camera was
					# seeing the INSIDE of the far side of the shell through the near
					# side — which reads exactly as a figure made of glass. Jurek: "nie
					# zrobiłeś w środku człowieka, czyli nie widać, tylko jest po prostu
					# przezroczyste." Nothing was transparent; every material measured
					# alpha 1.0. It was culling.
					sm.cull_mode = BaseMaterial3D.CULL_BACK
					sm.roughness = minf(sm.roughness, MAX_ROUGHNESS)
					sm.metallic_specular = maxf(sm.metallic_specular, MIN_SPECULAR)
					if sm.albedo_texture != null:
						# Driven from the plate's OWN texture, so a red panel glows red and
						# a gold one gold — a flat white lift would grey the whole suit out.
						sm.emission_enabled = true
						sm.emission_texture = sm.albedo_texture
						sm.emission = Color(1, 1, 1)
						# MULTIPLY, AND THIS LINE IS THE WHOLE POINT. Godot defaults the
						# operator to ADD, and ADD computes (emission.rgb + texture) *
						# energy — so emission = white added a FLAT 0.11 of untinted light
						# to every plate on every suit, which is a grey veil and precisely
						# the thing the comment above swore it was avoiding. Jurek: "stroje
						# są strasznie szare i grumpy." MULTIPLY gives texture * 0.11,
						# which is the tinted lift that was always meant: a red panel
						# glows red, a gold one gold, and nothing goes grey.
						sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
						sm.emission_energy_multiplier = PLATE_GLOW
	for c in n.get_children():
		_polish(c)
