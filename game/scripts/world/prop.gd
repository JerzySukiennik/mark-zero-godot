class_name Prop
extends StaticBody3D
## Something you can pick up and throw at someone.
##
## Jurek asked for this to be contextual: the prompt appears when the thing is on screen
## and near, follows it while you walk around it, and goes away when you leave — "i tak
## jakby, że jak chodzisz dookoła tego, to dalej powinno to być i dopiero jak odejdziesz".
## So the prompt and the outline live on the PROP rather than on the HUD, which is also
## what makes them work for a second prop without any extra bookkeeping.

## How close the player has to be for it to offer itself.
const NOTICE := 9.0
## What it does to whoever it lands on, and how fast it leaves the hand.
const DAMAGE := 26.0
const THROW_SPEED := 38.0
const GRAVITY := 20.0

enum { RESTING, HELD, FLYING }

var state := RESTING
var ground_y := 0.0
var _vel := Vector3.ZERO
var _mesh: MeshInstance3D
var _label: Label3D
var _glow := 0.0

func _ready() -> void:
	add_to_group("prop")
	_build()

func _build() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.28
	cyl.height = 0.95
	cyl.radial_segments = 14
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cyl
	_mesh.position.y = cyl.height * 0.5

	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.22, 0.24)
	m.metallic = 0.55
	m.roughness = 0.55
	# THE OUTLINE. A grown, front-culled copy behind the real surface — the standard trick,
	# and the reason it is a second PASS rather than a second mesh is that it then follows
	# the thing through every transform for free.
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.cull_mode = BaseMaterial3D.CULL_FRONT
	edge.grow = true
	edge.grow_amount = 0.02
	edge.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge.albedo_color = Color(1, 1, 1, 0.0)
	m.next_pass = edge
	_mesh.material_override = m
	add_child(_mesh)

	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 0.95
	cs.shape = shape
	cs.position.y = 0.475
	add_child(cs)

	# The prompt. A Label3D because it has to sit in the world and stay readable from any
	# angle — the same thing on the HUD would need to know where the prop is on screen,
	# which is a projection problem nobody needs to have.
	_label = Label3D.new()
	_label.text = "L1 + R1"
	_label.font_size = 64
	_label.pixel_size = 0.0032
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color(1, 1, 1, 0)
	_label.outline_size = 16
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	_label.position.y = 1.45
	add_child(_label)

## Picked up. It stops being solid so the player does not trip over what he is carrying.
func grab() -> void:
	state = HELD
	_set_solid(false)

## Thrown from where it is, along `dir`.
func hurl(dir: Vector3) -> void:
	state = FLYING
	_vel = dir.normalized() * THROW_SPEED
	_set_solid(false)

func _set_solid(on: bool) -> void:
	collision_layer = 1 if on else 0
	collision_mask = 1 if on else 0

func _physics_process(delta: float) -> void:
	var player := _nearest_player()
	# The highlight and the prompt fade with distance rather than snapping, so walking past
	# one does not strobe.
	var want := 0.0
	if state == RESTING and player != null:
		var d := global_position.distance_to(player.global_position)
		want = clampf(1.0 - (d - NOTICE * 0.55) / (NOTICE * 0.45), 0.0, 1.0)
	_glow = move_toward(_glow, want, delta * 5.0)
	var mat: StandardMaterial3D = _mesh.material_override
	var edge: StandardMaterial3D = mat.next_pass
	edge.albedo_color = Color(1, 1, 1, _glow * 0.9)
	_label.modulate = Color(1, 1, 1, _glow)

	match state:
		HELD:
			return          # the pilot moves it
		FLYING:
			_vel.y -= GRAVITY * delta
			var from := global_position
			var to := from + _vel * delta
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.collide_with_areas = true
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var who = hit.get("collider", null)
				if who != null and who.has_method("take_hit"):
					who.take_hit(DAMAGE, from, "thrown")
				global_position = hit["position"]
				_land()
				return
			global_position = to
			rotate_x(6.0 * delta)
			rotate_z(4.0 * delta)
			if global_position.y <= ground_y + 0.05:
				_land()
		_:
			if global_position.y > ground_y + 0.05:
				_vel.y -= GRAVITY * delta
				global_position += _vel * delta
			else:
				_vel = Vector3.ZERO

func _land() -> void:
	state = RESTING
	_vel = Vector3.ZERO
	global_position.y = ground_y
	rotation = Vector3.ZERO
	_set_solid(true)

func _nearest_player() -> Node3D:
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D and (n as Node3D).is_inside_tree():
			return n
	return null
