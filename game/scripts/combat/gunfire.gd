class_name Gunfire
extends Node3D
## Everything the ENEMIES shoot: bullets and rockets, in one pool.
##
## Kept apart from Repulsors deliberately. That one is a weapon the player aims and feels
## the recoil of; this is incoming fire, and the only things it needs to be good at are
## being READABLE in the air and landing on the right side of the fight. Merging them
## would mean one file full of "if this is the player's".
##
## Bullets travel fast enough that a frame at 120 Hz covers several metres, so every step
## is swept as a ray rather than tested at a point — a bullet that tunnels through a suit
## is a bullet the player never sees and never forgives.

const POOL := 48
const LIFE := 4.0
## Rockets are slow and obvious on purpose: they are the one incoming thing you are meant
## to have time to dodge.
const ROCKET_TRAIL := 0.045
## How sharply a rocket can turn, as a fraction of the angle per second.
const ROCKET_TURN := 1.25

signal hit_player(amount: float, at: Vector3)

class Round:
	var node: MeshInstance3D
	var vel := Vector3.ZERO
	var life := 0.0
	var live := false
	var damage := 0.0
	var blast := 0.0
	var rocket := false
	## Rockets chase. Bullets do not, and never will — a bullet you cannot outrun is not a
	## threat the player can answer.
	var chase: Node3D = null
	var launched := 0.0
	## Set when the PLAYER fired it (the Mark III's micro-salvo). The only thing it
	## changes is that the splash skips the man who launched it.
	var friendly := false

var _pool: Array[Round] = []
var _built := false

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	for i in POOL:
		var r := Round.new()
		r.node = MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.055
		cm.height = 0.34
		cm.radial_segments = 6
		cm.rings = 2
		r.node.mesh = cm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Hot orange, because every friendly thing in this game is cyan-white. Telling
		# incoming from outgoing at a glance matters more than either looking right.
		m.albedo_color = Color(1.6, 0.62, 0.22, 0.95)
		r.node.material_override = m
		r.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.node.visible = false
		add_child(r.node)
		_pool.append(r)

func _take() -> Round:
	for r: Round in _pool:
		if not r.live:
			return r
	return null

## Fires one. `damage` is what it does on a direct hit; a non-zero `blast` makes it a
## rocket, which also hurts anything close to where it lands.
## `chase` is only honoured by rockets. Jurek: "jak jest wystrzelony RPG, to on powinien
## jakby gonić za tym Spidermanem albo Iron Manem" — slow, obvious and persistent, so the
## answer is to move rather than to have been standing somewhere else.
func fire(from: Vector3, dir: Vector3, speed: float, damage: float, blast := 0.0,
		chase: Node3D = null, friendly := false) -> bool:
	var r := _take()
	if r == null:
		return false
	r.live = true
	r.life = LIFE
	r.vel = dir.normalized() * speed
	r.damage = damage
	r.blast = blast
	r.rocket = blast > 0.0
	r.chase = chase if r.rocket else null
	r.friendly = friendly
	r.launched = 0.0
	r.node.visible = true
	r.node.global_position = from
	var m: StandardMaterial3D = r.node.material_override
	m.albedo_color = Color(1.8, 0.45, 0.15, 0.95) if r.rocket else Color(1.6, 0.62, 0.22, 0.95)
	r.node.scale = Vector3(2.2, 2.2, 2.2) if r.rocket else Vector3.ONE
	return true

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	for r: Round in _pool:
		if not r.live:
			continue
		r.life -= delta
		if r.rocket:
			r.launched += delta
			r.vel.y -= 3.0 * delta          # a slight droop, so an RPG arcs
			# STEERING, and weakly. A rocket that turns hard is unavoidable and therefore
			# not a mechanic; one that turns slowly has to be out-manoeuvred, which is the
			# only interesting version. It also only starts steering after a beat, so
			# walking two metres sideways at the moment of firing does not beat it.
			if r.chase != null and is_instance_valid(r.chase) and r.launched > 0.35:
				var want := (r.chase.global_position + Vector3(0, 0.7, 0)) - r.node.global_position
				if want.length_squared() > 1e-4:
					var sp := r.vel.length()
					r.vel = r.vel.normalized().slerp(want.normalized(),
						clampf(ROCKET_TURN * delta, 0.0, 1.0)) * sp
		var from := r.node.global_position
		var to := from + r.vel * delta

		# SWEPT, not sampled. At 210 m/s a 120 Hz frame is 1.75 m, which is wider than a
		# man — testing only the end point lets rounds pass straight through people.
		var q := PhysicsRayQueryParameters3D.create(from, to)
		# AREAS TOO, and this is the only query in the game that asks for them. The
		# players' hurtboxes are areas precisely so that nothing else — the wall sweep,
		# the web anchors, the thugs walking about — can see them.
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_land(r, hit["position"], hit.get("collider", null))
			continue

		# The pointy end faces the way it is going.
		if r.vel.length_squared() > 1e-4:
			var d := r.vel.normalized()
			var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
			var xa := up.cross(d).normalized()
			# Axes assigned one at a time: Basis(x, y, z) takes ROWS while basis.y reads
			# back a COLUMN, which silently gives you a right angle.
			var b := Basis()
			b.x = xa
			b.y = d
			b.z = xa.cross(d).normalized()
			r.node.global_transform = Transform3D(b, to)
		else:
			r.node.global_position = to

		if r.life <= 0.0:
			r.live = false
			r.node.visible = false

func _land(r: Round, at: Vector3, collider) -> void:
	r.live = false
	r.node.visible = false
	if r.blast > 0.0:
		# Splash: everything within the radius, players included, falling off with range.
		for n in get_tree().get_nodes_in_group("hittable"):
			if not (n is Node3D):
				continue
			var d: float = (n as Node3D).global_position.distance_to(at)
			if r.friendly and (n as Node).is_in_group("player"):
				continue
			if d < r.blast:
				_apply(n, r.damage * (1.0 - d / r.blast), at)
		Sfx.play("explosion", at, 2.0)
		Sfx.play("explosion_low", at, 0.0, 0.9)
		_shout(at, r.damage, r.blast)
		return
	if collider != null:
		_apply(collider, r.damage, at)

func _apply(node, amount: float, at: Vector3) -> void:
	if node == null or amount <= 0.0:
		return
	if node.has_method("take_hit"):
		node.take_hit(amount, at, "bullet")
	elif node.is_in_group("player"):
		hit_player.emit(amount, at)

## A rocket going off, as a light and a flash. Cheap, and the only warning a second
## rocket gives you is the memory of the first.
func _shout(at: Vector3, _amount: float, radius: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.22)
	l.light_energy = 12.0
	l.omni_range = radius * 2.4
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)

## Is anything tracking `who`, and how close is it? Returns -1 when nothing is, and 0..1
## as it closes, which is what drives the bracket and the beeping.
func lock_on(who: Node3D) -> float:
	if who == null:
		return -1.0
	var best := -1.0
	for r: Round in _pool:
		if not r.live or not r.rocket or r.chase != who:
			continue
		var d: float = r.node.global_position.distance_to(who.global_position)
		# Sixty metres is about as far as one is ever fired from, so that is full scale.
		var near: float = clampf(1.0 - d / 60.0, 0.0, 1.0)
		best = maxf(best, near)
	return best

## Everything tracking anybody forgets them. Chaff, and the Mark III's whole answer to a
## rocket already in the air.
func break_locks() -> void:
	for r: Round in _pool:
		r.chase = null
