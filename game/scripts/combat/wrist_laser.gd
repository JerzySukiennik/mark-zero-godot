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
const CHARGE_COST := 1.0
## The suit charges from electrical damage taken, cables, and the like. Slow on purpose:
## this is a thing you earn, not a cooldown you wait out.
const TRICKLE := 0.035

var charge := 0.0
var active := false
var in_air := false
var t := 0.0
var turn_done := 0.0          ## radians turned so far, so the suit can be driven from it

var _beam: MeshInstance3D
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
	# Built along +Z so it can be pointed with look_at like everything else here.
	_beam.rotation_degrees = Vector3(90, 0, 0)
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
	if rig != null and rig.has_pivot("piv_palmR"):
		_origin = rig.pivots["piv_palmR"]

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
	_beam.visible = false
	_glow.light_energy = 0.0
	finished.emit()

## Draw the beam from the wrist out to whatever it hits.
func update(_delta: float) -> void:
	if not active or _origin == null or _beam == null:
		return
	var from := _origin.global_position
	# Out of the wrist along the emitter axis, which the contract puts at the pivot's -Y.
	var dir := (_origin.global_basis * Vector3(0, -1, 0)).normalized()
	var to := from + dir * RANGE

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit.has("position"):
		to = hit["position"]

	var len := from.distance_to(to)
	_beam.global_position = (from + to) * 0.5
	_beam.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	_beam.scale = Vector3(1, 1, maxf(0.05, len))
	# The beam flickers hard. A steady cylinder is a tube; a flickering one is energy.
	var m: StandardMaterial3D = _beam.material_override
	var f := 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.09)
	m.albedo_color = Color(1.0, 0.94, 0.90, 0.85 * f)
	_glow.global_position = to
	_glow.light_energy = 7.0 * f
