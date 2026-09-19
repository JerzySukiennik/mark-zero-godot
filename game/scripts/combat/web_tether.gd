class_name WebTether
extends RefCounted
## The rope. Fires at a target, holds on, and lets go.
##
## Jurek's ask, verbatim: flying as Iron Man, the player on Spider-Man should be able to
## look at the suit, press a button, and end up hanging off it — swinging, and carried
## along. So the anchor is a NODE, not a point: the thing on the other end is moving at
## three hundred metres a second and the rope has to follow it.
##
## A ROPE PULLS AND NEVER PUSHES. That one rule is what separates a tether from a spring,
## and getting it wrong is unmistakable — a spring shoves you away when you swing in past
## the anchor, which reads as being repelled by the thing you are holding onto.

enum { IDLE, FLYING, ATTACHED }

## How far a web will reach.
const MAX_RANGE := 140.0
## How wide a cone counts as "looking at it", in degrees. Generous on purpose: this is a
## trick shot taken at a target crossing the sky, and a tight cone makes it a lottery.
const AIM_CONE := 14.0
## Metres per second the web travels on the way out.
const FLY_SPEED := 340.0
## Rope spring, per kilogram, and its damping. Stiff enough not to feel elastic, damped
## enough not to oscillate — a bouncy rope is the other classic failure here.
const STIFFNESS := 46.0
const DAMPING := 7.0
## How fast the player can haul themselves in or pay line out, in metres per second.
const REEL_SPEED := 14.0
const MIN_LENGTH := 3.0

var state := IDLE
var anchor_node: Node3D = null
## Where on the target the web landed, in the TARGET's local frame, so it stays stuck to
## that spot as the target rolls rather than sliding around to face the shooter.
var anchor_local := Vector3.ZERO
var rest_length := 0.0
var reach := 0.0                  ## 0..1, how far the web has travelled on the way out
var _fly_t := 0.0
var _fly_dist := 0.0

func anchor_point() -> Vector3:
	if anchor_node == null or not anchor_node.is_inside_tree():
		return Vector3.ZERO
	return anchor_node.global_transform * anchor_local

## Picks the best target from `candidates` for someone at `from` looking along `aim`.
## Returns null when nothing is in the cone. Scored by ANGLE, not by distance: the player
## is pointing at one specific suit, and the nearest one is very often not it.
static func pick(from: Vector3, aim: Vector3, candidates: Array) -> Node3D:
	var best: Node3D = null
	var best_dot := cos(deg_to_rad(AIM_CONE))
	for n: Node3D in candidates:
		if n == null or not n.is_inside_tree():
			continue
		var d := n.global_position - from
		var dist := d.length()
		if dist < 1.0 or dist > MAX_RANGE:
			continue
		var dot := aim.dot(d / dist)
		if dot > best_dot:
			best_dot = dot
			best = n
	return best

## `at` is the world point the web should stick to. Omitted, it lands just above the
## target's origin, which is what you want for a suit — the origin is at the soles, and a
## web stuck to the bottom of the boots puts the rider underneath the exhaust. For a
## BUILDING there is no such convention and the ray's hit point is the only sensible
## anchor, so it is passed in.
func fire(from: Vector3, target: Node3D, at: Vector3 = Vector3.INF) -> bool:
	if target == null:
		return false
	anchor_node = target
	var world: Vector3 = at if at != Vector3.INF else target.global_position + Vector3(0, 1.1, 0)
	anchor_local = target.global_transform.affine_inverse() * world
	_fly_dist = maxf(1.0, from.distance_to(anchor_point()))
	_fly_t = 0.0
	reach = 0.0
	state = FLYING
	return true

func release() -> void:
	state = IDLE
	anchor_node = null
	reach = 0.0

## Advances the flight, and once landed returns the acceleration the rope applies to a
## body at `pos` moving at `vel`. Zero whenever the rope is slack, which is most of a good
## swing — the arc you feel comes from the moments it goes tight.
func step(delta: float, pos: Vector3, vel: Vector3, reel: float) -> Vector3:
	if state == IDLE:
		return Vector3.ZERO

	# The target may have been destroyed, or left the room.
	if anchor_node == null or not anchor_node.is_inside_tree():
		release()
		return Vector3.ZERO

	if state == FLYING:
		_fly_t += delta
		reach = clampf(_fly_t * FLY_SPEED / _fly_dist, 0.0, 1.0)
		if reach >= 1.0:
			state = ATTACHED
			# The rope is exactly as long as the shot that made it. Starting shorter yanks
			# the player forward the instant it lands, which reads as being harpooned.
			rest_length = maxf(MIN_LENGTH, pos.distance_to(anchor_point()))
		return Vector3.ZERO

	# ---- attached ------------------------------------------------------------------
	if absf(reel) > 0.05:
		rest_length = maxf(MIN_LENGTH, rest_length - reel * REEL_SPEED * delta)

	var d := anchor_point() - pos
	var dist := d.length()
	if dist <= rest_length or dist < 0.001:
		return Vector3.ZERO              # slack: the rope is not there at all

	var along := d / dist
	var stretch := dist - rest_length
	# Damping acts only on the CLOSING speed along the rope, so it kills the twang without
	# stealing any of the sideways swing.
	var closing := vel.dot(along)
	return along * (STIFFNESS * stretch - DAMPING * closing)
