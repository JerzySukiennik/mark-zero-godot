class_name SpiderModel
extends RefCounted
## Spider-Man's body. A point mass, a rope, and the ground.
##
## Deliberately NOT FlightModel. The armour is an aircraft — thrust, anisotropic drag, a
## lifting body, a stabiliser that holds station. Spider-Man has none of that: he has
## gravity, whatever the web is doing to him, and two feet. Sharing a model between them
## would mean one file full of "if hero == ..." and two half-right sets of physics.

const G := 9.81
const MASS := 68.0
## Terminal velocity in a dive, near enough. Quadratic, one coefficient, no body axes.
const DRAG := 0.0022
## He is far more manoeuvrable in the air than an aircraft is, because he is not flying —
## this is shifting his weight on the end of a rope, and it is how a swing gets steered.
const AIR_STEER := 11.0
const WALK_SPEED := 3.4
const RUN_SPEED := 9.6
const WALK_GEAR := 0.35
const GROUND_ACCEL := 34.0
const GROUND_FRICTION := 22.0
const JUMP := 9.4
const STRIDE := 1.55

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var accel := Vector3.ZERO
var basis_ := Basis.IDENTITY
var yaw := 0.0
var pitch := 0.0
var grounded := false
var ground_y := 0.0
var ground_speed := 0.0
var stride_phase := 0.0
var swinging := false

var speed: float:
	get: return velocity.length()

## `rope` is the acceleration the tethers are applying this step, already summed.
func step(delta: float, cmd: Dictionary, rope: Vector3) -> void:
	var look: Vector2 = cmd.get("look", Vector2.ZERO)
	yaw -= look.x
	pitch = clampf(pitch - look.y, -1.2, 1.2)

	var a := Vector3(0, -G, 0) + rope
	swinging = rope.length_squared() > 0.01

	var v := velocity
	var sp := v.length()
	if sp > 0.01:
		a -= v * (DRAG * sp)

	if not grounded:
		# Steering in the air. Small, and it is not thrust — it is the difference between a
		# swing you are riding and one that is happening to you.
		var ask: Vector2 = cmd.get("walk", Vector2.ZERO)
		if ask.length() > 0.08:
			var dir := basis_ * Vector3(ask.x, 0.0, -ask.y)
			dir.y = 0.0
			if dir.length_squared() > 1e-6:
				a += dir.normalized() * AIR_STEER

	accel = a
	velocity += a * delta
	position += velocity * delta

	_resolve_ground()
	_walk(delta, cmd)

	basis_ = Basis.from_euler(Vector3(0, yaw, 0), EULER_ORDER_YXZ)

func _resolve_ground() -> void:
	# Same convention as the armour: the model is a metre above soles that sit on y = 0.
	var floor_y := ground_y + 1.0
	if position.y <= floor_y:
		position.y = floor_y
		if velocity.y < 0.0:
			velocity.y = 0.0
		grounded = true
	else:
		grounded = false

func _walk(delta: float, cmd: Dictionary) -> void:
	if not grounded:
		ground_speed = 0.0
		return

	if cmd.get("jump", false):
		velocity.y = JUMP
		grounded = false
		return

	var ask: Vector2 = cmd.get("walk", Vector2.ZERO)
	var mag := clampf(ask.length(), 0.0, 1.0)
	var want := Vector3.ZERO
	if mag > 0.08:
		var dir := basis_ * Vector3(ask.x, 0.0, -ask.y)
		dir.y = 0.0
		if dir.length_squared() > 1e-6:
			var gear: float = (WALK_SPEED * mag / WALK_GEAR if mag < WALK_GEAR
				else lerpf(WALK_SPEED, RUN_SPEED, (mag - WALK_GEAR) / (1.0 - WALK_GEAR)))
			want = dir.normalized() * gear

	var v := Vector3(velocity.x, 0.0, velocity.z)
	v = v.move_toward(want, (GROUND_ACCEL if mag > 0.08 else GROUND_FRICTION) * delta)
	velocity.x = v.x
	velocity.z = v.z
	ground_speed = v.length()
	# Distance, not time — the same rule the armour's walk follows, for the same reason.
	stride_phase += ground_speed * delta / STRIDE
