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
## Same rule as the armour: the stride LENGTHENS with speed, so cadence stays human. At a
## flat 1.55 m he ran at six leg cycles a second, which is what Jurek saw as "mega szybkie
## cos sie dzieje dziwnego" — the legs were a blur and the pelvis twist went with them.
const STRIDE_WALK := 1.35
const STRIDE_RUN := 3.90

static func stride_len(speed: float, top: float) -> float:
	return lerpf(STRIDE_WALK, STRIDE_RUN, clampf(speed / maxf(0.01, top), 0.0, 1.0))

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var accel := Vector3.ZERO
var basis_ := Basis.IDENTITY
## Yaw AND pitch, for the camera. A body that pitches when you look up is a body lying
## down, so this never reaches the rig.
var view_basis := Basis.IDENTITY
var yaw := 0.0
var pitch := 0.0
var grounded := false
var ground_y := 0.0
var ground_speed := 0.0
var stride_phase := 0.0
var swinging := false

## ---- on a wall ---------------------------------------------------------------------
## Spider-Man's whole point is that a wall is a floor. Until now the only surface in the
## model was a ground PLANE at y = 0 — buildings had collision bodies that nothing ever
## asked about, so he flew straight through them.
var stuck := false
var wall_normal := Vector3.UP
## Set by the pilot each frame. The model does its own sweeps rather than handing the job
## up, because sticking has to happen in the same step as the movement that caused it —
## a frame spent airborne inside a wall is a frame the camera sees.
var space: PhysicsDirectSpaceState3D = null

## How fast he crawls, and how fast he runs when the trigger is held.
const CRAWL_SPEED := 4.2
const WALL_RUN_SPEED := 11.5
const CRAWL_ACCEL := 40.0
## Clearance kept off the surface so the next sweep does not start inside it.
const SKIN := 0.12
## The push-off when he lets go backwards.
const FLIP_OUT := 9.0
const FLIP_UP := 6.5

var speed: float:
	get: return velocity.length()

## `rope` is the acceleration the tethers are applying this step, already summed.
func step(delta: float, cmd: Dictionary, rope: Vector3) -> void:
	if stuck:
		_crawl(delta, cmd)
		basis_ = Basis.from_euler(Vector3(0, yaw, 0), EULER_ORDER_YXZ)
		view_basis = Basis.from_euler(Vector3(pitch, yaw, 0), EULER_ORDER_YXZ)
		return

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
			var dir := basis_ * Vector3(ask.x, 0.0, ask.y)
			dir.y = 0.0
			if dir.length_squared() > 1e-6:
				a += dir.normalized() * AIR_STEER

	accel = a
	velocity += a * delta
	var from := position
	position += velocity * delta

	_hit_wall(from)
	_resolve_ground()
	_walk(delta, cmd)

	basis_ = Basis.from_euler(Vector3(0, yaw, 0), EULER_ORDER_YXZ)
	# THE CAMERA PITCHES, THE BODY DOES NOT. `pitch` was being accumulated off the stick and
	# then used by nothing at all — the basis is yaw-only, so looking up and down moved
	# exactly one thing in the game, which was the HUD sway. "Nie moge patrzec w gore i w
	# dol, bo to rusza jakos dziwnie UI" was precisely the whole of its effect.
	view_basis = Basis.from_euler(Vector3(pitch, yaw, 0), EULER_ORDER_YXZ)

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
		var dir := basis_ * Vector3(ask.x, 0.0, ask.y)
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
	stride_phase += ground_speed * delta / stride_len(ground_speed, RUN_SPEED)

## Did this step drive him into something? Sticks him to it if so.
##
## A ray rather than a shape sweep: he is a point mass everywhere else in this file, and a
## capsule here would disagree with the ground handling by exactly its own radius.
func _hit_wall(from: Vector3) -> void:
	if space == null or stuck:
		return
	var q := PhysicsRayQueryParameters3D.create(from, position)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Vector3 = hit.get("normal", Vector3.UP)
	# A near-flat surface is the FLOOR, and the floor is handled by _resolve_ground — going
	# down that path here would leave him "stuck" to the plate and unable to walk.
	if n.dot(Vector3.UP) > 0.7:
		return
	stuck = true
	wall_normal = n.normalized()
	position = (hit["position"] as Vector3) + wall_normal * SKIN
	velocity = Vector3.ZERO
	ground_speed = 0.0

## Crawling, running and letting go. While he is on a wall there is no gravity and no
## tether — it is a different mode, not flight with a different pose.
func _crawl(delta: float, cmd: Dictionary) -> void:
	if cmd.get("release", false):
		# BACKFLIP OFF. Out along the normal and up, so he arcs away from the face rather
		# than sliding down it — and being airborne again is what re-enables the webs.
		stuck = false
		velocity = wall_normal * FLIP_OUT + Vector3.UP * FLIP_UP
		return

	# A frame ON the wall: "up" is world up flattened into the surface, so crawling a
	# vertical face feels like climbing and crawling a ceiling still has a consistent
	# forward. Facing the wall, his right is up-cross-normal.
	var up := (Vector3.UP - wall_normal * Vector3.UP.dot(wall_normal))
	if up.length_squared() < 1e-4:
		up = (basis_ * Vector3(0, 0, -1)) - wall_normal * (basis_ * Vector3(0, 0, -1)).dot(wall_normal)
	up = up.normalized()
	var right := up.cross(wall_normal).normalized()

	var ask: Vector2 = cmd.get("walk", Vector2.ZERO)
	var mag := clampf(ask.length(), 0.0, 1.0)
	# HOLDING THE TRIGGER RUNS. Jurek: on a wall L2 must not throw a web, it must make him
	# stand up and sprint up the face. So the same finger means two different things in two
	# different modes, which is fine because the modes are unmistakable.
	var top: float = WALL_RUN_SPEED if cmd.get("wall_run", false) else CRAWL_SPEED
	var want := (right * ask.x - up * ask.y) * (top * mag)

	velocity = velocity.move_toward(want, CRAWL_ACCEL * delta)
	position += velocity * delta
	ground_speed = velocity.length()
	stride_phase += ground_speed * delta / stride_len(ground_speed, WALL_RUN_SPEED)

	# Stay ON it. A short probe into the face each step follows curves and, when it finds
	# nothing, means he has crawled off an edge — at which point he simply falls.
	if space == null:
		return
	var probe := PhysicsRayQueryParameters3D.create(
		position + wall_normal * 0.4, position - wall_normal * 0.8)
	probe.collide_with_areas = false
	var hit := space.intersect_ray(probe)
	if hit.is_empty():
		stuck = false
		return
	var n: Vector3 = (hit.get("normal", wall_normal) as Vector3).normalized()
	if n.dot(Vector3.UP) > 0.7:
		stuck = false          # crawled onto a roof; let the ground handling take him
		return
	wall_normal = n
	position = (hit["position"] as Vector3) + wall_normal * SKIN
