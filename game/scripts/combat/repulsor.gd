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
## Per hand, so alternating hands doubles the rate. Tightened, because the whole design of
## these is "tap as fast as you can" and 0.14 caps a single hand at seven a second.
const COOLDOWN := 0.095
const RECOIL := 2.4             ## m/s of push-back per shot
## SIXTEEN SHOTS A HAND, counted rather than measured.
##
## Jurek's rule: tap it sixteen times and the bar goes red and STAYS locked until it has
## refilled all the way; stop short of empty and you can keep going whenever you like, with
## the magazine topping itself up a shot at a time. That makes the last few shots a real
## decision — spend them and you are unarmed for a while — which a smooth bar that always
## lets you squeeze out one more never did.
const SHOTS := 16
const DRAIN := 1.0 / SHOTS
## Seconds to put one shot back.
const RELOAD_PER_SHOT := 1.5
const RECHARGE := 1.0 / (SHOTS * RELOAD_PER_SHOT)
## What one bolt takes off. Sized against EnemyKinds: three drop a thug, five a rifleman,
## and a brute needs most of a magazine — so the big one is a decision, not a speed bump.
const DAMAGE := 12.0
## AIM ASSIST, of the kind console shooters have used since the first Halo. Three things
## are standard and all three are here, split across this file and SuitPilot:
##   FRICTION    the look stick slows while the reticle is over a man        (SuitPilot)
##   MAGNETISM   the shot curves a little towards him                        (here)
##   a LOCK MARK so the player can see which one the game thinks he means    (Hud)
##
## Magnetism is the one that does the work at this range. A suit hovering two hundred
## metres up is aiming at a target a few pixels across, and Jurek's report was blunt:
## "dosłownie nie da się trafić teraz tym Iron Manem." Bending the bolt is far kinder than
## snapping the camera, which fights the player for control of where he is looking.
## Swept against a target 40 m away aimed 1.5 m wide: at 3.4 the bolt closed to 1.38 m and
## missed, at 8 to 1.12 m and still missed, at 18 it lands, and past that nothing improves
## because the residual is the lateral offset at the instant it goes by. Twenty, with the
## margin on the right side of the cliff.
const MAGNET_TURN := 11.0
## Bolts only bend for something they were already roughly aimed at.
## Tightened with the rest of the assist: a bolt still bends for a shot that was nearly
## right, and no longer for one that was not.
const MAGNET_CONE := 0.991

signal fired(hand: String)

class Bolt:
	## What this bolt is bending towards, if anything.
	var chase: Node3D = null
	var node: Node3D
	var light: OmniLight3D
	var tail: Node3D
	var vel := Vector3.ZERO
	var life := 0.0
	var live := false

var _pool: Array = []
var _cool := { "L": 0.0, "R": 0.0 }
var charge := { "L": 1.0, "R": 1.0 }
## A hand that has been run dry refuses to fire until it is back at FULL, not until it has
## scraped together one shot's worth. Without it the empty bar just becomes a very slow
## trickle of single shots, which is not a reload, it is a stutter.
var locked := { "L": false, "R": false }

## Whole shots left in that hand, for the HUD to draw as pips.
func shots_left(hand: String) -> int:
	return int(round(charge.get(hand, 0.0) * SHOTS))

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
	return _cool.get(hand, 0.0) <= 0.0 and not locked.get(hand, false) \
		and charge.get(hand, 0.0) >= DRAIN - 0.0001

## Fire one hand. Returns the recoil to apply to the airframe, or ZERO if it did not fire.
func fire(hand: String, muzzle: Vector3, target: Vector3, chase: Node3D = null) -> Vector3:
	if not ready_to_fire(hand):
		return Vector3.ZERO
	var b: Bolt = _take()
	if b == null:
		return Vector3.ZERO
	_cool[hand] = COOLDOWN
	Sfx.play("repulsor", muzzle, -4.0)
	charge[hand] = maxf(0.0, charge[hand] - DRAIN)
	if charge[hand] <= 0.0001:
		locked[hand] = true

	var dir := target - muzzle
	if dir.length_squared() < 1e-6:
		dir = Vector3(0, 0, -1)
	dir = dir.normalized()

	b.live = true
	b.chase = chase
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
		if locked[k] and charge[k] >= 0.9999:
			locked[k] = false

	for b: Bolt in _pool:
		if not b.live:
			continue
		b.life -= delta

		# The bend. Small, capped by a cone, and only towards a body the shot was already
		# pointed at — a bolt that turns ninety degrees is a homing missile and stops being
		# something the player aimed.
		if b.chase != null and is_instance_valid(b.chase):
			var want := (b.chase.global_position + Vector3(0, 0.9, 0)) - b.node.global_position
			if want.length_squared() > 1e-4:
				var dir := b.vel.normalized()
				var to := want.normalized()
				if dir.dot(to) > MAGNET_CONE:
					b.vel = dir.slerp(to, clampf(MAGNET_TURN * delta, 0.0, 1.0)) * b.vel.length()
					b.node.look_at(b.node.global_position + b.vel, Vector3.UP)

		var step := b.vel * delta

		# SWEPT AGAINST THE WORLD. Until there was anything solid to find, these simply
		# flew for three seconds and expired — the shot existed, the hit did not. At 260 m/s
		# a 120 Hz frame covers two metres, which is wider than a man, so testing the end
		# point alone would let bolts pass through people.
		if is_inside_tree():
			var space := get_world_3d().direct_space_state
			var from := b.node.global_position
			var q := PhysicsRayQueryParameters3D.create(from, from + step)
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var who = hit.get("collider", null)
				if who != null and who.has_method("take_hit"):
					who.take_hit(DAMAGE, from, "repulsor")
				b.live = false
				b.node.visible = false
				b.light.light_energy = 0.0
				continue

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
