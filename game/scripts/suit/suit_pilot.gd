class_name SuitPilot
extends Node3D
## One player in an armour. Networked from its first line — see scripts/net/net.gd.
##
## AUTHORITY: the peer this suit belongs to runs the flight model locally and publishes
## where it ended up. Everyone else interpolates towards what they were told. Flying never
## waits for the network, and nobody can be pushed around by someone else's lag.
##
## The model imported from the browser build brings its own contract with it
## (assets/suits/CONTRACT.md): +Y up, the body faces -Z, the origin is at the SOLES, and the
## suit is 1.95 m tall. The flight model is a point mass one metre above the soles, which is
## why the mesh hangs a metre below the model's position rather than sitting on it.

const SUITS := {
	"mk1": "res://assets/suits/mk1.glb",
	"mk2": "res://assets/suits/mk2.glb",
	"mk3": "res://assets/suits/mk3.glb",
	"mk42": "res://assets/suits/mk42.glb",
	"mk50": "res://assets/suits/mk50.glb",
}
## Point mass to soles, from CONTRACT.md.
const FEET_DROP := 1.0

@export var peer_id := 1
@export var armor_id := "mk3"

var model: FlightModel
var rig: Node3D
var camera: Camera3D
var _city: City

## What a remote suit is heading towards. Position and rotation are published, never
## velocity: a remote suit that dead-reckons off stale velocity overshoots corners and
## visibly snaps back, which reads far worse than being 120 ms behind.
var _net_pos := Vector3.ZERO
var _net_basis := Basis.IDENTITY
var _net_thrust := 0.0

var is_mine: bool:
	get: return peer_id == Net.my_id

func setup(id: int, armor: String, city: City) -> void:
	peer_id = id
	armor_id = armor
	_city = city

func _ready() -> void:
	model = FlightModel.new()
	model.set_armor(armor_id)
	_load_rig(armor_id)
	if is_mine:
		camera = Camera3D.new()
		camera.fov = 70.0
		camera.far = 6000.0
		add_child(camera)
		camera.current = true

func _load_rig(id: String) -> void:
	if rig != null:
		rig.queue_free()
	var path: String = SUITS.get(id, SUITS["mk3"])
	var packed: PackedScene = load(path)
	if packed == null:
		push_warning("[suit] %s would not load" % path)
		return
	rig = packed.instantiate()
	add_child(rig)

func wear(id: String) -> void:
	armor_id = id
	model.set_armor(id)
	_load_rig(id)
	if is_mine:
		Net.announce_armor(id)

func _physics_process(delta: float) -> void:
	if is_mine:
		_step_local(delta)
	else:
		_step_remote(delta)

func _step_local(delta: float) -> void:
	var look := Pad.look(delta)
	var move := Pad.move()
	var cmd := {
		thrust = Pad.thrust(),
		retro = Pad.retro(),
		lateral = move.x,
		# Cross lifts, circle drops. The left stick's Y is pitch TRIM in the air rather than
		# a second climb control: two ways to go up that disagree is how a player ends up
		# fighting his own hands.
		vertical = (1.0 if Pad.pressed("up") else 0.0) - (1.0 if Pad.pressed("down") else 0.0),
		look = look,
		roll = 0.0,
		boost = Pad.pressed("boost"),
	}
	if _city != null:
		model.ground_y = _city.ground_y
	model.step(delta, cmd)

	global_position = model.position
	if rig != null:
		rig.position = Vector3(0, -FEET_DROP, 0)
		rig.basis = model.basis_
	if camera != null:
		_drive_camera(delta)

func _step_remote(delta: float) -> void:
	# 120 ms of smoothing: enough that a dropped packet is invisible, short enough that a
	# shot you dodge is a shot you actually dodged.
	var k := 1.0 - exp(-delta / 0.12)
	global_position = global_position.lerp(_net_pos, k)
	if rig != null:
		rig.basis = rig.basis.slerp(_net_basis, k)

## The chase camera. Sits behind and above, and is dragged rather than bolted on: a camera
## rigidly attached to the suit turns the world instead of turning the suit, and at speed
## that is nauseating. Distance opens up with speed so fast flight feels fast.
func _drive_camera(delta: float) -> void:
	var back := 6.0 + clampf(model.speed / 40.0, 0.0, 6.0)
	var up := 2.0 + clampf(model.speed / 120.0, 0.0, 2.0)
	var want := model.basis_ * Vector3(0, up, back)
	var target := model.position + want
	var k := 1.0 - exp(-delta / 0.10)
	camera.global_position = camera.global_position.lerp(target, k)
	camera.look_at(model.position + model.basis_ * Vector3(0, 0.6, -8.0), Vector3.UP)
	# A little FOV with speed. Small on purpose — this is the cheapest way to sell speed and
	# also the easiest to overdo into a fisheye.
	camera.fov = lerpf(camera.fov, 70.0 + clampf(model.speed / 380.0, 0.0, 1.0) * 18.0, k)

# ---- replication -----------------------------------------------------------------------

func publish() -> void:
	if not is_mine or not Net.online:
		return
	_sync.rpc(model.position, model.basis_.get_rotation_quaternion(), model.thrust_mag)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync(p: Vector3, q: Quaternion, th: float) -> void:
	_net_pos = p
	_net_basis = Basis(q)
	_net_thrust = th
