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
