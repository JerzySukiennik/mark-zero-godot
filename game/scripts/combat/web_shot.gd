class_name WebShot
extends Node3D
## The web you THROW, as opposed to the one you hang from.
##
## Jurek: R1 is the right hand, L1 the left, the fingers fold, it leaves the wrist and it
## sticks where it lands — "na ścianie zostawiać, a w przyszłości... sklejać wrogów". So
## this is a projectile and a splat, and deliberately NOT the tether: the tether is a rope
## you are attached to, this is ammunition you let go of. Keeping them apart is what lets
## the triggers mean "hold on" and the bumpers mean "throw".

const SPEED := 145.0
const LIFE := 2.2
const POOL := 14
## How long a splat stays on the wall. Long, because a wall covered in your own webbing is
## the only record the plate keeps of anything you have done.
const SPLAT_LIFE := 22.0
const SPLAT_POOL := 24
## Fast enough to mash. Webbing a wall is meant to feel like flicking your wrist, not like
## working a bolt action.
const COOLDOWN := 0.13

class Glob:
	var node: MeshInstance3D
	var vel := Vector3.ZERO
	var life := 0.0
	var live := false

var _pool: Array[Glob] = []
var _splats: Array[MeshInstance3D] = []
var _splat_life: Array[float] = []
var _next_splat := 0
var _cool := { "L": 0.0, "R": 0.0 }
var _built := false

func _ready() -> void:
	# The pool was never built: `build` existed, nothing called it, `_take` therefore always
	# returned null and `fire` always returned false. From the pad that is a button that
	# does nothing at all — "one teraz w ogole nie strzelaja". Every other effect here keeps
	# both, because add_child does not run _ready under `godot --script`.
	build()

func build() -> void:
	if _built:
		return
	_built = true
	for i in POOL:
		var g := Glob.new()
		g.node = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.10
		sm.height = 0.20
		sm.radial_segments = 8
		sm.rings = 4
		g.node.mesh = sm
		g.node.material_override = _web_material(0.92)
		g.node.visible = false
		g.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g.node)
		_pool.append(g)

	for i in SPLAT_POOL:
		var mi := MeshInstance3D.new()
		# A flattened sphere, so a splat has thickness rather than being a decal that
		# vanishes edge-on.
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.10
		sm.radial_segments = 10
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = _web_material(0.80)
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_splats.append(mi)
		_splat_life.append(0.0)

static func _web_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.94, 0.96, 1.0, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.75
	m.metallic = 0.0
	# A touch of emission so webbing reads on a black plate, where a white unlit blob is
	# the same colour as the shadow it is sitting in.
	m.emission_enabled = true
	m.emission = Color(0.55, 0.62, 0.75)
	m.emission_energy_multiplier = 0.30
	return m

func ready_to_fire(hand: String) -> bool:
	return _cool.get(hand, 0.0) <= 0.0

## Throws one. `from` and `dir` are world; returns true if it actually went.
func fire(hand: String, from: Vector3, dir: Vector3) -> bool:
	if not ready_to_fire(hand):
		return false
	var g := _take()
	if g == null:
		return false
	_cool[hand] = COOLDOWN
	Sfx.play("thwip", from, -3.0)
	g.live = true
	g.life = LIFE
	g.vel = dir.normalized() * SPEED
	g.node.visible = true
	g.node.global_position = from
	return true

func _take() -> Glob:
	for g: Glob in _pool:
		if not g.live:
			return g
	return null

func _physics_process(delta: float) -> void:
	for k in _cool:
		_cool[k] = maxf(0.0, _cool[k] - delta)

	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for g: Glob in _pool:
		if not g.live:
			continue
		g.life -= delta
		# Webbing is light but it is not weightless; a dead flat line out of the wrist
		# reads as a laser rather than as something thrown.
		g.vel.y -= 4.5 * delta
		var from := g.node.global_position
		var to := from + g.vel * delta
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				# THIS IS WHAT THE WEBBING IS FOR. The splat on a wall was always the
				# placeholder; the point was ever "sklejać wrogów".
				var who = hit.get("collider", null)
				if who != null and who.has_method("web_hit"):
					who.web_hit(1.0)
				Sfx.play("web_stick", hit["position"], -6.0)
				_splat(hit["position"], hit.get("normal", Vector3.UP))
				g.live = false
				g.node.visible = false
				continue
		g.node.global_position = to
		if g.life <= 0.0:
			g.live = false
			g.node.visible = false

	for i in _splats.size():
		if _splat_life[i] <= 0.0:
			continue
		_splat_life[i] -= delta
		var mi: MeshInstance3D = _splats[i]
		if _splat_life[i] <= 0.0:
			mi.visible = false
		else:
			# Fades out over its last couple of seconds rather than blinking away.
			var a: float = clampf(_splat_life[i] / 2.5, 0.0, 1.0)
			var m: StandardMaterial3D = mi.material_override
			m.albedo_color = Color(0.94, 0.96, 1.0, 0.80 * a)

## Sticks a patch of webbing to whatever was hit, lying flat against the surface.
func _splat(at: Vector3, normal: Vector3) -> void:
	var mi: MeshInstance3D = _splats[_next_splat]
	_splat_life[_next_splat] = SPLAT_LIFE
	_next_splat = (_next_splat + 1) % _splats.size()
	mi.visible = true
	var n := normal.normalized() if normal.length_squared() > 1e-5 else Vector3.UP
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var xa := up.cross(n).normalized()
	var za := xa.cross(n).normalized()
	# Axes set one at a time: Basis(x, y, z) takes ROWS, and the flattened axis here is the
	# surface normal, which has to be the y COLUMN.
	var b := Basis()
	b.x = xa * randf_range(0.7, 1.25)
	b.y = n * 0.16                      # squashed against the wall
	b.z = za * randf_range(0.7, 1.25)
	mi.global_transform = Transform3D(b, at + n * 0.04)
	var m: StandardMaterial3D = mi.material_override
	m.albedo_color = Color(0.94, 0.96, 1.0, 0.80)
