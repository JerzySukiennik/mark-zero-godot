class_name SuitRig
extends RefCounted
## The armour's skeleton, and how it is posed. Ported from the browser build's rig.js.
##
## A pose is a set of LIMB DIRECTIONS in each joint's parent space, plus an optional twist.
## The rig turns a direction into a rotation by swinging the joint's own rest child-direction
## onto it, so the numbers mean the same thing whatever orientation the modeller gave the
## empties. Emitters — the palms — are AIMED instead, because a palm repulsor has to point
## where its thrust goes no matter what the shoulder and elbow are doing.
##
## Every number in POSES was read off a reference frame rather than invented. The one time
## they were guessed, the result was a cruise pose with the arms swept back like a dart,
## which is not what the films do and looked like it.

const PIVOT_PARENT := {
	"piv_hips": "piv_root", "piv_chest": "piv_hips", "piv_neck": "piv_chest",
	"piv_head": "piv_neck",
	"piv_shoulderL": "piv_chest", "piv_elbowL": "piv_shoulderL", "piv_palmL": "piv_elbowL",
	"piv_shoulderR": "piv_chest", "piv_elbowR": "piv_shoulderR", "piv_palmR": "piv_elbowR",
	"piv_hipL": "piv_hips", "piv_kneeL": "piv_hipL", "piv_ankleL": "piv_kneeL",
	"piv_thrusterL": "piv_ankleL",
	"piv_hipR": "piv_hips", "piv_kneeR": "piv_hipR", "piv_ankleR": "piv_kneeR",
	"piv_thrusterR": "piv_ankleR",
	"piv_reactor": "piv_hips",
}

## WHICH PIVOT IS ON THE PLAYER'S RIGHT.
##
## Named separately from the model because the two disagree. assets/suits/CONTRACT.md says
## "+X is the character's LEFT" and every model obeys it — but the same contract has the
## figure facing -Z, and an entity facing -Z has its own right at +X, which is the
## convention Godot itself uses for a camera. So the pivot called `piv_palmL` sits on the
## character's anatomical RIGHT, and pressing R1 fired out of the hand on the left of the
## screen.
##
## Rather than rename twenty pivots across five shipped models, the disagreement is
## declared once, here, and everything that cares about sides asks. tools/test_sides.gd
## measures it through the real camera rather than trusting this comment.
const SCREEN_RIGHT_PALM := "piv_palmL"

## Maps a BUTTON side ("R" or "L") to the model's own suffix.
const SIDE := { "R": "L", "L": "R" }

static func _d(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z).normalized()

## The authored poses. `dir` is where the limb points in its parent's frame, `twist` is
## degrees of roll about it, `aim` points an emitter in the SUIT's frame.
static var POSES := {
	"stand": {},
	# The walk has no authored base either: it IS the stand, with the cycle laid over it as
	# offsets. Authoring a mid-stride key here would fight the cycle for the same joints.
	"walk": {},

	# Arms swept down the flanks with the fists past the hips. The first version held them
	# straight out to the sides, off a hero frame — and a hero frame is a deliberate hold for
	# the camera, not what the suit does when it is going somewhere. Laid down at speed, arms
	# out is a crucifix sliding through the sky. This reading is also the only one that puts
	# the palm repulsors where their thrust belongs: behind him.
	"cruise": {
		"piv_shoulderL": { "dir": _d(0.20, -0.95, 0.24), "twist": -8.0 },
		"piv_shoulderR": { "dir": _d(-0.20, -0.95, 0.24), "twist": 8.0 },
		"piv_elbowL": { "dir": _d(-0.02, -0.98, 0.19) },
		"piv_elbowR": { "dir": _d(0.02, -0.98, 0.19) },
		"piv_palmL": { "aim": _d(0.08, -0.25, 0.96) },
		"piv_palmR": { "aim": _d(-0.08, -0.25, 0.96) },
		"piv_hipL": { "dir": _d(-0.04, -0.99, 0.09) },
		"piv_hipR": { "dir": _d(0.04, -0.99, 0.09) },
		"piv_kneeL": { "dir": _d(0, -0.99, -0.10) },
		"piv_kneeR": { "dir": _d(0, -0.99, -0.10) },
		"piv_ankleL": { "dir": _d(0, -0.70, 0.71) },
		"piv_ankleR": { "dir": _d(0, -0.70, 0.71) },
		"piv_chest": { "dir": _d(0, 0.985, -0.17) },
		"piv_neck": { "dir": _d(0, 0.95, -0.30) },
	},

	# Arms out and forward, knees soft, and the palm discs pointing STRAIGHT DOWN because
	# they are what is holding him up.
	# HE STANDS IN THE AIR. Jurek: "powinien stac z rekami i nogami prosto w dol".
	#
	# The previous hover was a crouch — knees folded back, elbows tucked, shoulders thrown
	# out sideways — which is a man bracing, not a man being held up by four repulsors. The
	# real thing is almost a standing figure that happens to have no floor: legs straight
	# and together, arms hanging just clear of the body, and all four emitters pointing
	# DOWN, because they are the only reason he is not falling.
	"hover": {
		"piv_shoulderL": { "dir": _d(0.24, -0.97, -0.04), "twist": -5.0 },
		"piv_shoulderR": { "dir": _d(-0.24, -0.97, -0.04), "twist": 5.0 },
		"piv_elbowL": { "dir": _d(-0.02, -0.999, 0.02) },
		"piv_elbowR": { "dir": _d(0.02, -0.999, 0.02) },
		"piv_palmL": { "aim": _d(0.04, -0.999, 0.0) },
		"piv_palmR": { "aim": _d(-0.04, -0.999, 0.0) },
		"piv_hipL": { "dir": _d(0.03, -0.999, -0.02) },
		"piv_hipR": { "dir": _d(-0.03, -0.999, -0.02) },
		"piv_kneeL": { "dir": _d(0, -0.999, 0.03) },
		"piv_kneeR": { "dir": _d(0, -0.999, 0.03) },
		# Feet nearly flat, because the BOOT JETS point along the ankle and they are what is
		# holding him up. Toes back at 0.60 aimed the exhaust thirty-seven degrees behind
		# vertical — measured — so a hovering suit was firing backwards and down.
		"piv_ankleL": { "dir": _d(0, -0.992, 0.13) },
		"piv_ankleR": { "dir": _d(0, -0.992, 0.13) },
		"piv_chest": { "dir": _d(0, 1.0, 0.0) },
	},

	# The repulsor stance. Asymmetric on purpose: two arms out is a pose, one arm out is a
	# shot. The left punches out at the target, the right stays low and ready.
	# SYMMETRIC, on purpose. This pose used to throw the LEFT arm out front and leave the
	# right one hanging, whichever palm had actually fired -- so pressing R1 looked like the
	# suit shooting left-handed ("sa zamienione rece strzelania"). The stance is now the
	# same on both sides and the FIRING arm is singled out by a short offset pushed from
	# SuitPilot, which is also where the recoil snap belongs.
	"fire": {
		"piv_shoulderL": { "dir": _d(0.34, -0.38, -0.86), "twist": -10.0 },
		"piv_shoulderR": { "dir": _d(-0.34, -0.38, -0.86), "twist": 10.0 },
		"piv_elbowL": { "dir": _d(-0.05, -0.24, -0.97) },
		"piv_elbowR": { "dir": _d(0.05, -0.24, -0.97) },
		"piv_palmL": { "aim": _d(0, -0.06, -1) },
		"piv_palmR": { "aim": _d(0, -0.06, -1) },
		"piv_hipL": { "dir": _d(0.06, -0.99, -0.10) },
		"piv_hipR": { "dir": _d(-0.06, -0.99, -0.10) },
		"piv_kneeL": { "dir": _d(0, -0.97, 0.24) },
		"piv_kneeR": { "dir": _d(0, -0.97, 0.24) },
		"piv_chest": { "dir": _d(0, 0.99, 0.14) },
	},

	# THE STOP. The body snaps upright out of the dive and all four repulsors swing round to
	# face where it is still travelling — the whole armour becomes a parachute made of
	# thrust. This is the shot everyone remembers.
	"brake": {
		"piv_shoulderL": { "dir": _d(0.34, -0.42, -0.84), "twist": -20.0 },
		"piv_shoulderR": { "dir": _d(-0.34, -0.42, -0.84), "twist": 20.0 },
		"piv_elbowL": { "dir": _d(-0.05, -0.30, -0.95) },
		"piv_elbowR": { "dir": _d(0.05, -0.30, -0.95) },
		"piv_palmL": { "aim": _d(0.05, -0.12, -0.99) },
		"piv_palmR": { "aim": _d(-0.05, -0.12, -0.99) },
		"piv_hipL": { "dir": _d(0.12, -0.72, -0.68) },
		"piv_hipR": { "dir": _d(-0.12, -0.72, -0.68) },
		"piv_kneeL": { "dir": _d(0, -0.86, -0.51) },
		"piv_kneeR": { "dir": _d(0, -0.86, -0.51) },
		"piv_ankleL": { "dir": _d(0, -0.55, -0.83) },
		"piv_ankleR": { "dir": _d(0, -0.55, -0.83) },
		"piv_chest": { "dir": _d(0, 0.98, 0.20) },
		"piv_neck": { "dir": _d(0, 0.97, -0.24) },
	},

	# The landing: left fist into the ground, right arm trailing, right knee down, head up.
	"land": {
		"piv_shoulderL": { "dir": _d(0.30, -0.93, -0.22), "twist": -14.0 },
		"piv_shoulderR": { "dir": _d(-0.62, -0.44, 0.65), "twist": 24.0 },
		"piv_elbowL": { "dir": _d(0.06, -0.99, 0.10) },
		"piv_elbowR": { "dir": _d(-0.20, -0.62, 0.76) },
		"piv_palmL": { "aim": _d(0, -1, 0) },
		"piv_palmR": { "aim": _d(-0.30, -0.55, 0.78) },
		"piv_hipL": { "dir": _d(0.22, -0.83, -0.51) },
		"piv_hipR": { "dir": _d(-0.16, -0.78, 0.60) },
		"piv_kneeL": { "dir": _d(0, -0.93, 0.36) },
		"piv_kneeR": { "dir": _d(0, -0.55, -0.84) },
		"piv_ankleL": { "dir": _d(0, -0.96, -0.28) },
		"piv_ankleR": { "dir": _d(0, -0.72, -0.69) },
		"piv_chest": { "dir": _d(0, 0.94, -0.34) },
		"piv_neck": { "dir": _d(0, 0.86, -0.51) },
	},
}

var root: Node3D
var pivots: Dictionary = {}          ## name -> Node3D
var _rest: Dictionary = {}           ## name -> Quaternion, as the model was authored
var _child_dir: Dictionary = {}      ## name -> Vector3, unit direction to the child, local
var _target: Dictionary = {}         ## name -> Quaternion, where the pose wants it
var _shown: Dictionary = {}          ## name -> Quaternion, the FILTERED pose (see update)
var _offset: Dictionary = {}         ## name -> Quaternion, this frame's procedural layer

var pose_blend: float = 12.0         ## default catch-up rate, per second

func index(r: Node3D) -> void:
	root = r
	pivots.clear(); _rest.clear(); _child_dir.clear()
	_target.clear(); _shown.clear(); _offset.clear()
	var stack: Array = [r]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is Node3D and n.name.begins_with("piv_"):
			var name := String(n.name)
			pivots[name] = n
			_rest[name] = (n as Node3D).quaternion
			# Direction to the child PIVOT, in this pivot's own space. That is the limb's
			# axis, and it is what a pose direction is swung onto.
			#
			# "The first child with a non-zero offset" is the obvious rule and it is wrong:
			# meshes hang off these pivots too, and they come first. piv_kneeL's children
			# are the 1.5 cm knee cap, then the ankle 40 cm below — so the shin's axis was
			# taken as the cap's offset and came out pointing FORWARDS. Every knee and ankle
			# direction in every authored pose was then swung from the wrong axis: asking
			# for a leg hanging straight down produced a shin sticking out horizontally,
			# ninety-two degrees off. It is the anatomy that defines the limb, and the
			# anatomy is the pivot chain; the meshes are decoration hung on it.
			var dir := Vector3(0, -1, 0)
			var best := 0.0
			for c in n.get_children():
				if not (c is Node3D) or not String(c.name).begins_with("piv_"):
					continue
				var d := (c as Node3D).position
				# The FARTHEST child pivot, for joints that carry more than one — the elbow
				# is the palm's axis, not that of anything clipped nearer the joint.
				if d.length() > best and d.length() > 1e-4:
					best = d.length()
					dir = d.normalized()
			_child_dir[name] = dir

func has_pivot(n: String) -> bool:
	return pivots.has(n)

## Rotation that puts this joint's limb along `dir` (parent space), with `twist` degrees of
## roll about the limb itself.
func _aim_joint(name: String, dir: Vector3, twist_deg: float) -> Quaternion:
	var rest: Quaternion = _rest[name]
	var rest_dir: Vector3 = (rest * _child_dir[name]).normalized()
	var swing := Quaternion(rest_dir, dir.normalized())
	var q := swing * rest
	if absf(twist_deg) > 0.001:
		q = q * Quaternion(_child_dir[name], deg_to_rad(twist_deg))
	return q

## Rotation that points this joint's own axis along `dir`, given in the pivot's parent space.
func _aim_emitter(name: String, dir: Vector3) -> Quaternion:
	var rest: Quaternion = _rest[name]
	var rest_dir: Vector3 = (rest * _child_dir[name]).normalized()
	return Quaternion(rest_dir, dir.normalized()) * rest

## Build the target rotations for one named pose. `_chain` accumulates each pivot's rotation
## in suit space, so an `aim` given in the suit's frame can be converted into the parent's.
## Which table `set_pose` reads. Defaults to the armour's POSES; Spider-Man swaps in his
## own, because he is not wearing an aircraft and none of the six flight poses describe
## anything he does. Sharing one table meant he walked around in the Mark III's stance.
var pose_table: Dictionary = POSES

func set_pose(name: String) -> void:
	var fallback = pose_table.values()[0] if not pose_table.is_empty() else {}
	var pose: Dictionary = pose_table.get(name, fallback)
	var chain: Dictionary = {}
	for p in pivots:
		var parent_name: String = PIVOT_PARENT.get(p, "")
		var q_parent: Quaternion = chain.get(parent_name, Quaternion.IDENTITY)
		var spec = pose.get(p, null)
		var q: Quaternion
		if spec == null:
			q = _rest[p]
		elif spec.has("aim"):
			var local: Vector3 = (q_parent.inverse() * (spec["aim"] as Vector3)).normalized()
			q = _aim_emitter(p, local)
		else:
			q = _aim_joint(p, spec["dir"], spec.get("twist", 0.0))
		_target[p] = q
		chain[p] = q_parent * q

## Points ONE joint, after a pose has been chosen.
##
## For limbs no authored pose mentions — the Iron Spider's four back legs — which set_pose
## leaves parked at rest forever because they appear in none of the six POSES entries.
## Adding them to all six instead would mean forty-eight lines describing a stowed leg.
func aim_joint(name: String, dir: Vector3, twist: float = 0.0) -> void:
	if not pivots.has(name):
		return
	_target[name] = _aim_joint(name, dir, twist)

## Points one joint along a WORLD direction.
##
## `aim_joint` takes its direction in the pivot's PARENT frame, which is the same grammar
## the authored poses use and is right for them — a pose describes a shape, and a shape is
## relative. It is exactly wrong for aiming at something: asking for "straight ahead" in a
## parent frame that has itself just been rotated gives you straight ahead OF THAT, and
## down a chain the error compounds. Measured on the wrist laser: a shoulder and an elbow
## both asked to point forward produced a forearm 45 degrees ABOVE the horizon, and the
## beam went with it.
func aim_joint_world(name: String, world_dir: Vector3, twist := 0.0) -> void:
	if not pivots.has(name) or world_dir.length_squared() < 1e-6:
		return
	var node: Node3D = pivots[name]
	var local := world_dir
	var parent := node.get_parent()
	if parent is Node3D and (parent as Node3D).is_inside_tree():
		local = (parent as Node3D).global_basis.inverse() * world_dir
	_target[name] = _aim_joint(name, local.normalized(), twist)

## Blend several poses at once. `weights` is name -> 0..1; they need not sum to one.
func set_pose_weights(weights: Dictionary) -> void:
	var first := true
	var done := 0.0
	var acc: Dictionary = {}
	for pose_name in weights:
		var w: float = weights[pose_name]
		if w <= 0.001:
			continue
		set_pose(pose_name)
		if first:
			first = false
			done = w
			for p in _target:
				acc[p] = _target[p]
		else:
			done += w
			var t: float = w / done      # incremental nlerp: each term takes its share
			for p in _target:
				acc[p] = (acc.get(p, _target[p]) as Quaternion).slerp(_target[p], t)
	if not acc.is_empty():
		_target = acc

## A procedural rotation layered on top of the pose. ACCUMULATES — several drivers write to
## the same joint each frame, and a plain assignment means the last one silently deletes all
## the others.
func add_offset(name: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0005 or not pivots.has(name):
		return
	var q := Quaternion(axis.normalized(), angle)
	_offset[name] = (_offset.get(name, Quaternion.IDENTITY) as Quaternion) * q

func clear_offsets() -> void:
	_offset.clear()

## THE FILTER BELONGS TO THE POSE, NOT TO THE OFFSETS.
##
## This was one exponential over the product of both, and it cost the suit its whole
## procedural layer. The time constant exists so cross-fades between authored poses do not
## pop, and for that it is right. But the offsets are the only FAST channel the rig has —
## the arm trail, the fire reach, the landing crouch — and running them through the same
## filter smeared every one of them before it reached the screen: a 0.2 s strike got 125 ms
## of attack and 125 ms of release and never arrived. Measured in the browser build, the
## shoulder went from 0.00 to 13.21 degrees peak-to-peak in steady cruise the moment they
## were separated. That is the difference between a statue being flown around and a suit.
func update_pose(delta: float) -> void:
	var k := 1.0 - exp(-pose_blend * delta)
	for p in _target:
		var node: Node3D = pivots.get(p, null)
		if node == null:
			continue
		var want: Quaternion = _target[p]
		var shown: Quaternion = _shown.get(p, node.quaternion)
		shown = shown.slerp(want, k)
		_shown[p] = shown
		var off = _offset.get(p, null)
		node.quaternion = (shown * (off as Quaternion)) if off != null else shown
