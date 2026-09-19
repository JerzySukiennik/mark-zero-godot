class_name FlightModel
extends RefCounted
## Six degrees of freedom, ported from the browser build.
##
## THE CONTROL LAW, which is the one decision the whole game rests on: the look direction
## turns the WHOLE BODY, and the throttle is thrust along the body's own axes. Nothing
## steers the velocity directly. The consequence is the thing Jurek wanted from the start —
## spin round and open the throttle and you stop violently, because that is what the physics
## does, not because a brake button was pressed.
##
## Every constant below was found by flying and measuring, not chosen. The notes say what
## was measured, because a number with no story behind it gets "cleaned up" by the next
## person to read it.

## The spec table, loaded as a script rather than reached for as a singleton — see the note
## at the top of specs.gd.
const SuitSpecsS := preload("res://scripts/flight/specs.gd")

const G := 9.81

## Retro authority as a fraction of the mains.
##
## This has been wrong twice, in both directions. The original 0.28 on the forward axis
## alone took nineteen seconds and three kilometres to stop — "it tries to stop, but very
## badly". 0.85 brought that to three and a half seconds, which is physically defensible
## and still far too slow to play: the test is weaving between buildings, and at three and a
## half seconds you commit to a line the moment you see the gap.
##
## 2.8 is the film's answer rather than the airframe's. Stopping is not the mains throttling
## back, it is all four repulsors swinging round to face the way you are going and burning
## at full power. Measured at 2.8: 150 m/s to rest in 0.85 s, 60 m/s in 0.34 s.
##
## Safe to make this large because the stopping half is impulse-capped below — the brake
## converges on a stop, it can never produce speed in the opposite direction.
const BRAKE_K := 2.8

## Seconds for the up-thrust to arrest a fall. The drop is killed almost on the frame, and
## only then does the slow climb start. Two separate forces on purpose: making ordinary
## vertical thrust strong enough to stop a terminal-velocity fall would also fire the suit
## into the sky the moment you tapped it in level flight.
const FALL_ARREST_TIME := 0.22

## Metres per second of held climb. Measured before this existed: a held up-thrust put the
## suit at 33 m/s upward inside a second, from level flight and from a caught fall alike —
## it left the map. A governor rather than a weaker thruster, so take-off is still immediate
## and arresting a fall is still violent, while the steady climb settles somewhere flyable.
const CLIMB_RATE := 15.0

var spec: SuitSpecsS.Spec

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var basis_ := Basis.IDENTITY
var omega := Vector3.ZERO          ## angular velocity, body axes
var accel := Vector3.ZERO          ## world-frame linear acceleration, for the pose system

var yaw := 0.0
var pitch := 0.0
var roll := 0.0

var grounded := false
var thrust_mag := 0.0
var g_force := 1.0
var boost_active := 0.0
var _boost_t := 0.0
var ground_y := 0.0                ## set by the owner each step from the world

## Derived drag constants, rebuilt whenever the armour changes.
var _k_fwd := 0.0
var _k_lat := 0.0
var _k_vert := 0.0
var _k_back := 0.0
var _lift_k := 0.0

func set_armor(id: String) -> void:
	spec = SuitSpecsS.get_spec(id)
	# k = main / top_speed^2 — the suit reaches exactly top_speed when thrust balances drag.
	_k_fwd = spec.main / (spec.top_speed * spec.top_speed)
	_k_lat = _k_fwd * spec.drag_lateral
	_k_vert = _k_fwd * spec.drag_vertical
	_k_back = _k_fwd * spec.drag_back
	# A suit flying nose-first is a lifting body. Without this, holding the throttle level
	# sinks at vertical terminal velocity and a long cruise ends in the ground.
	_lift_k = _k_fwd * 0.55

var speed: float:
	get: return velocity.length()

## `cmd` carries what the pad asked for this step:
##   thrust 0..1, retro 0..1, lateral -1..1, vertical -1..1, look Vector2 (radians),
##   roll -1..1, boost bool
func step(delta: float, cmd: Dictionary) -> void:
	if spec == null:
		set_armor("mk3")

	_rotate(delta, cmd)

	var power := 1.0
	var boosting: bool = cmd.get("boost", false) and cmd.get("thrust", 0.0) > 0.05
	_boost_t = _boost_t + delta if boosting else 0.0
	# A punch that decays over a third of a second, so pressing boost is an EVENT. A flat
	# multiplier develops extra top speed over fifteen seconds and changes nothing you can
	# feel in the first one — which is why boost "did nothing" in the browser build.
	var boost := spec.boost * (1.0 + 0.8 * exp(-_boost_t / 0.35)) if boosting else 1.0
	boost_active = 1.0 if boosting else 0.0

	var fwd: float = cmd.get("thrust", 0.0)
	var back: float = cmd.get("retro", 0.0)

	# ---- forces, in BODY axes -----------------------------------------------------------
	var f := Vector3.ZERO
	f.z -= fwd * spec.main * boost * power          # body forward is -Z

	# The retro burn opposes the BODY-FRAME VELOCITY on all three axes, not just forward:
	# sideways drift used to be untouchable, so a botched approach could not be salvaged.
	if back > 0.01:
		var bv := basis_.inverse() * velocity
		var bs := bv.length()
		# beta is how much of the burn is "go backwards" rather than "stop": all of it once
		# nearly stopped or already travelling backwards, none of it at speed. Capping the
		# retro at the impulse that zeroes velocity made a brake that could never produce
		# reverse motion — "you can't fly backwards any more" was the cost of fixing braking.
		# STOP-ONLY, for a brake nobody pressed.
		#
		# beta is what lets a HELD retro turn into reverse thrust once you have stopped, and
		# that is right for a button: the player asked for it and can let go. It is wrong for
		# the automatic brake that runs whenever the stick is centred, because the suit would
		# come to a halt and then quietly fly off backwards on its own. Measured before this
		# existed: 200 m/s never reached a stop at all and ended up doing 140 m/s in reverse.
		#
		# With beta at zero the burn only ever opposes the velocity it can see, and the cap
		# below means it converges on a stop rather than shooting past it.
		var beta := 0.0 if cmd.get("brake_only", false) else \
			(1.0 if (bs > 0.05 and bv.z > 0.7 * bs) else 1.0 - clampf((bs - 4.0) / 8.0, 0.0, 1.0))
		var d := Vector3(0, 0, beta)
		if bs > 0.05:
			d += bv * (-(1.0 - beta) / bs)
		if d.length_squared() > 1e-6:
			d = d.normalized()
			var want := back * spec.main * BRAKE_K * power
			# Only the STOPPING part is impulse-capped; the reverse part accelerates freely.
			var cap := (bs / delta) * spec.mass / maxf(1e-4, 1.0 - beta) if beta < 0.999 else INF
			f += d * minf(want, cap)

	f.x += cmd.get("lateral", 0.0) * spec.lateral * power

	var vert: float = cmd.get("vertical", 0.0)
	# Vertical thrust, governed on the way up. The taper reads WORLD climb rate, so it
	# cannot be defeated by rolling the suit over.
	var v_gov := 1.0
	if vert > 0.0 and velocity.y > 0.0:
		v_gov = clampf(1.0 - velocity.y / CLIMB_RATE, 0.0, 1.0)
	f.y += vert * spec.vertical * power * (v_gov if vert > 0.0 else 1.0)

	# Fall arrest. Reads WORLD velocity — a suit nose-down at 70 m/s is falling whatever its
	# own +Y says — and pushes straight up in the world, then hands the force back in body
	# axes. Capped at exactly the impulse that brings vertical speed to zero this step, so
	# it arrests and stops rather than launching.
	if vert > 0.05 and velocity.y < -0.5:
		var need := (-velocity.y / FALL_ARREST_TIME) * spec.mass
		var cap_now := (-velocity.y / delta) * spec.mass
		f += basis_.inverse() * Vector3(0, minf(need, cap_now) * vert, 0)

	thrust_mag = clampf((fwd * boost + absf(cmd.get("lateral", 0.0)) * 0.4
		+ absf(vert) * 0.5) * power, 0.0, 1.6)

	# ---- drag, anisotropic, in body axes ------------------------------------------------
	var b := basis_.inverse() * velocity
	var rho := _air_density(position.y)
	# Forward drag is cut while boosting, or the top end never actually moves.
	var kz := _k_back if b.z > 0.0 else _k_fwd * (0.75 if boosting else 1.0)
	f += Vector3(
		-_k_lat * b.x * absf(b.x),
		-_k_vert * b.y * absf(b.y),
		-kz * b.z * absf(b.z)) * rho

	# Lateral flight assist. Quadratic drag at a 20 m/s slide is 0.95 m/s^2 — nothing — so
	# letting go of the stick left the suit sliding for the rest of the flight. Only on X,
	# only when no slide is being asked for, sized to bleed one out in about 0.6 s.
	if absf(cmd.get("lateral", 0.0)) < 0.05 and absf(b.x) > 0.01:
		f.x += clampf(-b.x * spec.mass / 0.6 - b.x * 40.0, -spec.lateral, spec.lateral)

	# Body lift: CL = sin(2a), the flat-plate law. Zero at zero angle of attack, peak at 45
	# degrees, back to zero at 90 so a suit flying broadside gets nothing.
	var vmag := b.length()
	var fwd_comp := -b.z
	if vmag > 8.0 and fwd_comp > 0.0:
		var alpha := atan2(-b.y, fwd_comp)
		var lift := _lift_k * rho * vmag * vmag * sin(2.0 * alpha) * (fwd_comp / vmag)
		f.y += clampf(lift, -3.0 * spec.mass * G, 3.0 * spec.mass * G)

	# ---- integrate ----------------------------------------------------------------------
	var world_f := basis_ * f
	world_f.y -= G * spec.mass
	accel = world_f / spec.mass
	g_force = (accel + Vector3(0, G, 0)).length() / G

	velocity += accel * delta
	position += velocity * delta
	_resolve_ground()

func _rotate(delta: float, cmd: Dictionary) -> void:
	var look: Vector2 = cmd.get("look", Vector2.ZERO)
	# Rate limited by the armour, and the limit falls off with speed: a suit doing 300 m/s
	# cannot pivot like one hovering, and pretending otherwise is what makes flight feel
	# weightless. rate_falloff_ref is the speed at which authority is halved.
	var falloff := 1.0 / (1.0 + speed / spec.rate_falloff_ref)
	yaw -= look.x * spec.max_rate * falloff
	pitch = clampf(pitch - look.y * spec.max_rate * falloff, -1.45, 1.45)
	roll += cmd.get("roll", 0.0) * spec.roll_rate * delta
	# Auto-level, weak on purpose: strong enough that the horizon comes back on its own,
	# weak enough that a deliberate bank holds.
	roll = lerpf(roll, 0.0, 1.0 - exp(-delta * spec.stability * 1.6))
	basis_ = Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_YXZ)

func _air_density(alt: float) -> float:
	return maxf(0.14, exp(-maxf(0.0, alt) / 8500.0))

func _resolve_ground() -> void:
	# The armour's origin is at the SOLES (assets/suits/CONTRACT.md) and the flight model is
	# a point mass one metre above them.
	var floor_y := ground_y + 1.0
	if position.y <= floor_y:
		position.y = floor_y
		if velocity.y < 0.0:
			velocity.y = 0.0
		grounded = true
	else:
		grounded = false
