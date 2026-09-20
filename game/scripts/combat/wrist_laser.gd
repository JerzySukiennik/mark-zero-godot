class_name WristLaser
extends Node3D
## The cutting laser. Triangle and circle together, and only when the suit is charged.
##
## THE ICONIC ONE, and the design follows from that: it is not a gun, it is a CUT. A gun is
## aimed and fires; this sweeps, and what makes it read is that the suit turns its whole
## body to carry the beam through the target rather than pointing at it.
##
## So the move owns the suit for its duration. That is the cost, and it is deliberate —
## Jurek's rule is that it needs a charged suit, which means it is rare, and something rare
## should be worth watching rather than something you can do while doing something else.
##
## TWO TURNS, because the body cannot do the same thing in both places. In the air the suit
## rolls — it has nothing to push against, so the whole airframe rotates about its own axis
## and the beam sweeps a disc. On the ground it pivots about the feet, which is slower, and
## the beam sweeps a horizontal arc at chest height. Same weapon, two different pieces of
## choreography, because the physics underneath them is different.

signal started
signal finished

## Seconds the whole move takes.
const AIR_TIME := 1.45
const GROUND_TIME := 1.85
## How far round the suit turns during it, radians.
const AIR_TURN := TAU
const GROUND_TURN := PI * 1.15
const RANGE := 60.0
## Damage a SECOND. The sweep passes over a man in a fraction of one, so this is high on
## purpose: what it costs is the whole charge and being a sitting target while it runs.
const DPS := 260.0
const CHARGE_COST := 1.0
## The suit charges from electrical damage taken, cables, and the like. Rare on purpose:
## this is a thing you earn, not a cooldown you wait out.
##
## It was 0.035, which is a hair under THIRTY SECONDS from empty to a single shot, and the
## suit also started empty. The result was a weapon that could not be fired at all in any
## session short enough to be called a playtest — "nie dziala tez to trojkat z kolkiem" was
## the button working perfectly and the charge never arriving. Eight seconds still makes it
## the rarest thing on the pad without making it fiction.
## Eight seconds from empty was long enough that a second use never happened inside one
## fight, and "it did nothing" is what an unavailable weapon looks like from the pad.
const TRICKLE := 0.20

## FULL AT SPAWN. The first press of a weapon has to do something, or the player concludes
## the binding is broken and stops pressing it — and then never finds out it works.
var charge := 1.0
var active := false
var in_air := false
var t := 0.0
var turn_done := 0.0
## How far the upper body has twisted, for the grounded sweep. The legs stay planted —
## "nogi zostaja w miejscu, a on po prostu sie obraca" — so this never reaches the flight
## model; the pilot applies it to the spine.
var twist := 0.0          ## radians turned so far, so the suit can be driven from it

var _beam: MeshInstance3D
var _elbow: Node3D
var _glow: OmniLight3D
var _origin: Node3D
var _rig: SuitRig
var _built := false

func _ready() -> void:
	name = "WristLaser"
	build()

func build() -> void:
	if _built:
		return
	_built = true
	_beam = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.05
	cm.height = 1.0
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	_beam.mesh = cm
	# Left along its own +Y. `update` builds the basis by hand and points that axis down
	# the beam, so a pre-rotation here would only be something else to overwrite.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# White core, not coloured: the colour belongs to the glow, same rule as the exhaust.
	m.albedo_color = Color(1.0, 0.94, 0.90, 0.9)
	m.disable_receive_shadows = true
	_beam.material_override = m
	_beam.visible = false
	add_child(_beam)

	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.45, 0.30)
	_glow.light_energy = 0.0
	_glow.omni_range = 12.0
	_glow.shadow_enabled = false
	add_child(_glow)

func attach(rig: SuitRig) -> void:
	_rig = rig
	_origin = null
	# Same side correction as the turret: the right forearm as the PLAYER sees it.
	var mount: String = "piv_palm" + SuitRig.SIDE["R"]
	var arm: String = "piv_elbow" + SuitRig.SIDE["R"]
	_elbow = rig.pivots[arm] if rig != null and rig.has_pivot(arm) else null
	if rig != null and rig.has_pivot(mount):
		_origin = rig.pivots[mount]

var ready_to_fire: bool:
	get: return not active and charge >= CHARGE_COST and _origin != null

## Feed it power. Called when the suit takes electrical damage or touches a live cable.
func add_charge(amount: float) -> void:
	charge = clampf(charge + amount, 0.0, 1.0)

func trickle(delta: float) -> void:
	charge = clampf(charge + TRICKLE * delta, 0.0, 1.0)

## Start the move. `airborne` picks which of the two turns it does.
func start(airborne: bool) -> bool:
	if not ready_to_fire:
		return false
	active = true
	in_air = airborne
	t = 0.0
	turn_done = 0.0
	charge -= CHARGE_COST
	_beam.visible = true
	started.emit()
	Rumble.hit(0.85, 0.6, 0.35)
	return true

## How far the suit should have turned by now, in radians. The suit reads this and rotates
## itself, so the beam and the body can never disagree about where they are in the move.
func turn_for(delta: float) -> float:
	if not active:
		return 0.0
	var dur := AIR_TIME if in_air else GROUND_TIME
	var total := AIR_TURN if in_air else GROUND_TURN
	var was := _eased(t / dur)
	t += delta
	var now := _eased(minf(t / dur, 1.0))
	var step := (now - was) * total
	turn_done += step
	if t >= dur:
		_stop()
	return step

## Slow at the start, quick through the middle, and slowing again at the end. A linear turn
## looks like a turntable; this looks like something deciding to move.
static func _eased(x: float) -> float:
	var c: float = clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

func _stop() -> void:
	active = false
	twist = 0.0
	_beam.visible = false
	_glow.light_energy = 0.0
	finished.emit()

## Draw the beam from the wrist out to whatever it hits.
func update(_delta: float) -> void:
	if not active or _origin == null or _beam == null:
		return
	var from := _origin.global_position
	# ALONG THE ARM, elbow to wrist. The contract's emitter axis is the pivot's -Y, which
	# points out of the PALM — straight down while the arm hangs, and never where the arm
	# is pointing. Jurek asked for it to leave the wrist "jakby prosto, jak przedluzenie
	# reki", which is the forearm's own direction and nothing else. That is also why no
	# beam was ever visible: it was being drawn into the ground under his own feet.
	var dir := (_origin.global_basis * Vector3(0, -1, 0)).normalized()
	if _elbow != null and _elbow.is_inside_tree():
		var arm := from - _elbow.global_position
		if arm.length_squared() > 1e-5:
			dir = arm.normalized()
	var to := from + dir * RANGE

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit.has("position"):
		to = hit["position"]
		# IT CUTS. Continuous rather than per-shot, because the move is a sweep: standing
		# in it for a quarter of a second is what a hit means here, and that is exactly
		# what "ten laser przecina wszystkich wrogów dookoła" describes.
		var who = hit.get("collider", null)
		if who != null and who.has_method("take_hit"):
			who.take_hit(DPS * _delta, to, "laser")

	var len := maxf(0.05, from.distance_to(to))
	# THE BASIS IS BUILT BY HAND, because look_at cannot be used here. A CylinderMesh runs
	# along its own +Y, and the node carried a +90 degree pre-rotation about X to account
	# for that — which look_at then overwrote completely, leaving the cylinder standing
	# PERPENDICULAR to the beam it was supposed to be. Measured at a dot product of 0.000.
	# Pointing +Y straight down `dir`, and folding the length into that same axis, removes
	# both the pre-rotation and the scale-on-the-wrong-axis in one go.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var xa := up.cross(dir).normalized()
	var za := xa.cross(dir).normalized()
	# Axes assigned one at a time, NOT through Basis(x, y, z). That constructor takes ROWS
	# while `basis.y` reads back a COLUMN, so building it in one call and then asking for
	# the y axis returns something perpendicular to what was put in — measured at a dot
	# product of exactly 0.000 against the arm, which is the giveaway.
	var b := Basis()
	b.x = xa
	b.y = dir * len
	b.z = za
	_beam.global_transform = Transform3D(b, (from + to) * 0.5)
	# The beam flickers hard. A steady cylinder is a tube; a flickering one is energy.
	var m: StandardMaterial3D = _beam.material_override
	var f := 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.09)
	m.albedo_color = Color(1.0, 0.94, 0.90, 0.85 * f)
	_glow.global_position = to
	_glow.light_energy = 7.0 * f
