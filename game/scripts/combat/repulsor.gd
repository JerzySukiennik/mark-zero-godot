class_name Repulsors
extends Node3D
## The palm weapons, and what they throw.
##
## AIM IS WHERE THE CAMERA POINTS; THE MUZZLE IS WHERE THE HAND IS. These are different
## places, and pretending otherwise is the commonest way to make a shooter feel wrong: fire
## straight out of the palm and the shot misses the crosshair by however far the hand sits
## off the sight line, which at arm's length is a lot. So the bolt leaves the hand but
## travels towards the point the camera is looking at. The hand governs where it comes FROM,
## the crosshair governs where it GOES.
##
## A BOLT IS NOT A DOT. At 260 m/s it crosses two metres between physics ticks, so a small
## sphere is a dot that teleports. A hot head with a streak behind it is both what a repulsor
## bolt looks like and the only thing that reads at all at that speed.
##
## This node is expected to sit at the WORLD ORIGIN — bolt positions are its local space,
## which is the same as world space there. Parent it anywhere else and every shot is offset.
##
## Pooled: firing allocates nothing. A burst that stutters because it is building meshes
## feels bad for a reason the player will never guess at.

const SPEED := 260.0
const LIFE := 2.4
const POOL := 24
const COOLDOWN := 0.14          ## per hand, so alternating hands doubles the rate
const RECOIL := 2.4             ## m/s of push-back per shot
const DRAIN := 0.055            ## fraction of that hand's charge per shot
const RECHARGE := 0.22          ## fraction per second

signal fired(hand: String)

class Bolt:
	var node: Node3D
	var light: OmniLight3D
	var tail: Node3D
	var vel := Vector3.ZERO
	var life := 0.0
	var live := false

var _pool: Array = []
var _cool := { "L": 0.0, "R": 0.0 }
var charge := { "L": 1.0, "R": 1.0 }

func _ready() -> void:
	build()

## Separate from _ready, and this is the second system here to need it: in a headless
## `--script` run `add_child()` does not fire `_ready` when you expect it to, so a test that
## adds the node and immediately uses it finds an empty pool and reports a weapon that does
## not fire. The code was fine both times. Anything a test needs to drive gets a build()
## it can call.
func build() -> void:
	if not _pool.is_empty():
		return
	name = "Repulsors"
	for i in POOL:
		_pool.append(_make_bolt())

func _make_bolt() -> Bolt:
	var b := Bolt.new()
	b.node = Node3D.new()
	b.node.visible = false
	add_child(b.node)

	# The head: small and blown out. White, not blue — the colour belongs to the glow around
	# it, and a coloured core reads as plastic.
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.radial_segments = 8
	sm.rings = 5
	head.mesh = sm
	head.material_override = _glow(Color(1.0, 0.98, 0.95), 1.0)
	b.node.add_child(head)

	var tail := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.02
	cm.bottom_radius = 0.085
	cm.height = 1.0
	cm.radial_segments = 6
	cm.cap_top = false
	cm.cap_bottom = false
	tail.mesh = cm
	tail.rotation_degrees = Vector3(90, 0, 0)
	tail.material_override = _glow(Color(0.55, 0.80, 1.0), 0.45)
	b.node.add_child(tail)
	b.tail = tail

	# One light per bolt, dimmed rather than hidden: the renderer bakes the light count into
	# every material's shader, so a light appearing recompiles the scene and stutters on the
	# first shot of the session.
	b.light = OmniLight3D.new()
	b.light.light_color = Color(0.65, 0.85, 1.0)
	b.light.light_energy = 0.0
	b.light.omni_range = 7.0
	b.light.shadow_enabled = false
	b.node.add_child(b.light)
	return b

static func _glow(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.disable_receive_shadows = true
	return m

## Where the crosshair is pointing, in world space.
static func aim_point(cam: Camera3D, fallback: Vector3, max_dist := 900.0) -> Vector3:
	if cam == null:
		return fallback + Vector3(0, 0, -max_dist)
	var origin := cam.global_position
	var dir := -cam.global_basis.z
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist)
	var hit := space.intersect_ray(q)
	return hit.get("position", origin + dir * max_dist)

func ready_to_fire(hand: String) -> bool:
	return _cool.get(hand, 0.0) <= 0.0 and charge.get(hand, 0.0) >= DRAIN

## Fire one hand. Returns the recoil to apply to the airframe, or ZERO if it did not fire.
func fire(hand: String, muzzle: Vector3, target: Vector3) -> Vector3:
	if not ready_to_fire(hand):
		return Vector3.ZERO
	var b: Bolt = _take()
	if b == null:
		return Vector3.ZERO
	_cool[hand] = COOLDOWN
	charge[hand] = maxf(0.0, charge[hand] - DRAIN)

	var dir := target - muzzle
	if dir.length_squared() < 1e-6:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()

	b.live = true
	b.life = LIFE
	b.vel = dir * SPEED
	b.node.visible = true
	# LOCAL, not global. This node sits at the world origin, so the two are the same thing in
	# play — and local works in a headless test run, where global transforms have not been
	# computed yet and an assignment to global_position is silently dropped. The bolts sat at
	# the origin with a correct velocity and never moved.
	b.node.position = muzzle
	b.node.look_at_from_position(muzzle, muzzle + dir, Vector3.UP)
	b.light.light_energy = 3.2
	fired.emit(hand)
	Rumble.shot()
	return -dir * RECOIL

func _take() -> Bolt:
	for b: Bolt in _pool:
		if not b.live:
			return b
	return null

func _physics_process(delta: float) -> void:
	for k in _cool:
		_cool[k] = maxf(0.0, _cool[k] - delta)
		charge[k] = minf(1.0, charge[k] + RECHARGE * delta)

	for b: Bolt in _pool:
		if not b.live:
			continue
		b.life -= delta
		var step := b.vel * delta
		b.node.position += step
		# The streak is exactly as long as the ground covered this frame, so it is honest
		# about speed rather than a decorative fixed-length smear.
		if b.tail != null:
			var l := maxf(0.6, step.length() * 1.6)
			b.tail.scale = Vector3(1, l, 1)
			b.tail.position = Vector3(0, 0, l * 0.5)
		if b.life <= 0.0:
			b.live = false
			b.node.visible = false
			b.light.light_energy = 0.0
