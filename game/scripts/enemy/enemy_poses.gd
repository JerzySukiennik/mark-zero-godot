class_name EnemyPoses
extends RefCounted
## How a thug carries himself.
##
## Far smaller than the heroes' pose sets on purpose. Spider-Man and the armour are what
## the camera is pointed at for an entire session, so they earn their authored stances;
## these are read at a glance across a fight, and what has to be legible is only ever
## three things — is he coming at me, is he about to hit me, and is he out of it.

const X_AX := Vector3(1, 0, 0)
const Y_AX := Vector3(0, 1, 0)
const Z_AX := Vector3(0, 0, 1)

static func _d(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z).normalized()

static var POSES := {
	# Hands up, weight forward, knees soft. A man who wants to be closer than he is.
	"ready": {
		"piv_shoulderL": { "dir": _d(0.30, -0.72, -0.62), "twist": -14.0 },
		"piv_shoulderR": { "dir": _d(-0.30, -0.72, -0.62), "twist": 14.0 },
		"piv_elbowL": { "dir": _d(-0.14, -0.40, -0.90) },
		"piv_elbowR": { "dir": _d(0.14, -0.40, -0.90) },
		"piv_hipL": { "dir": _d(0.10, -0.98, -0.14) },
		"piv_hipR": { "dir": _d(-0.10, -0.98, -0.14) },
		"piv_kneeL": { "dir": _d(0, -0.96, 0.28) },
		"piv_kneeR": { "dir": _d(0, -0.96, 0.28) },
		"piv_chest": { "dir": _d(0, 0.98, -0.18) },
		"piv_neck": { "dir": _d(0, 0.97, -0.22) },
	},
	# Both arms driven out in front — the frame the eye reads as "this one is attacking",
	# whether what is in his hand is a fist, a knife or a rifle.
	"strike": {
		"piv_shoulderL": { "dir": _d(0.22, -0.34, -0.91), "twist": -20.0 },
		"piv_shoulderR": { "dir": _d(-0.18, -0.28, -0.94), "twist": 20.0 },
		"piv_elbowL": { "dir": _d(-0.06, -0.22, -0.97) },
		"piv_elbowR": { "dir": _d(0.04, -0.14, -0.99) },
		"piv_hipL": { "dir": _d(0.12, -0.96, -0.24) },
		"piv_hipR": { "dir": _d(-0.12, -0.97, 0.20) },
		"piv_kneeL": { "dir": _d(0, -0.94, 0.34) },
		"piv_kneeR": { "dir": _d(0, -0.92, 0.39) },
		"piv_chest": { "dir": _d(0, 0.95, -0.31) },
		"piv_neck": { "dir": _d(0, 0.96, -0.28) },
	},
	# ARMS PINNED TO THE BODY. Being webbed has to read instantly from across a street, and
	# the fastest way to say "he cannot use his hands" is to take them away.
	"webbed": {
		"piv_shoulderL": { "dir": _d(0.06, -0.99, 0.10), "twist": -4.0 },
		"piv_shoulderR": { "dir": _d(-0.06, -0.99, 0.10), "twist": 4.0 },
		"piv_elbowL": { "dir": _d(-0.02, -0.92, -0.38) },
		"piv_elbowR": { "dir": _d(0.02, -0.92, -0.38) },
		"piv_hipL": { "dir": _d(0.04, -0.999, 0.0) },
		"piv_hipR": { "dir": _d(-0.04, -0.999, 0.0) },
		"piv_kneeL": { "dir": _d(0, -0.99, 0.12) },
		"piv_kneeR": { "dir": _d(0, -0.99, 0.12) },
		"piv_chest": { "dir": _d(0, 0.99, 0.10) },
		"piv_neck": { "dir": _d(0, 0.98, 0.16) },
	},
	# Folded up. Not a ragdoll — a ragdoll is a physics system and this is a pose.
	"down": {
		"piv_shoulderL": { "dir": _d(0.55, -0.30, 0.78), "twist": -30.0 },
		"piv_shoulderR": { "dir": _d(-0.55, -0.30, 0.78), "twist": 30.0 },
		"piv_elbowL": { "dir": _d(-0.20, -0.44, 0.87) },
		"piv_elbowR": { "dir": _d(0.20, -0.44, 0.87) },
		"piv_hipL": { "dir": _d(0.24, -0.52, 0.82) },
		"piv_hipR": { "dir": _d(-0.24, -0.52, 0.82) },
		"piv_kneeL": { "dir": _d(0, -0.40, 0.92) },
		"piv_kneeR": { "dir": _d(0, -0.40, 0.92) },
		"piv_chest": { "dir": _d(0, 0.74, 0.67) },
		"piv_neck": { "dir": _d(0, 0.62, 0.78) },
	},
}

const NAMES := ["ready", "strike", "webbed", "down"]
## A swing has to snap and then relax; going down is quick and getting up never happens.
const ENTER := { "ready": 8.0, "strike": 26.0, "webbed": 12.0, "down": 16.0 }
const LEAVE := { "ready": 7.0, "strike": 7.0, "webbed": 6.0, "down": 2.0 }

var blend: Dictionary = {}
var _strike := 0.0

func _init() -> void:
	for n in NAMES:
		blend[n] = 1.0 if n == "ready" else 0.0

## Called the moment a punch, a stab or a shot goes out.
func strike() -> void:
	_strike = 0.26

func update(delta: float, e: Enemy, speed: float, stride: float, rig: SuitRig) -> void:
	if rig == null:
		return
	rig.pose_table = POSES
	# CLEARED EVERY FRAME. add_offset accumulates onto whatever is already on the joint, so
	# a driver that forgets to clear turns a constant offset into a constant angular
	# velocity. That cost this project a character whose head span in circles.
	rig.clear_offsets()

	if _strike > 0.0:
		_strike -= delta

	var want := "ready"
	if e.state == Enemy.DOWN:
		want = "down"
	elif e.state == Enemy.WEBBED:
		want = "webbed"
	elif _strike > 0.0:
		want = "strike"

	for n in NAMES:
		var to := 1.0 if n == want else 0.0
		var rate: float = ENTER[n] if to > blend[n] else LEAVE[n]
		blend[n] = to + (blend[n] - to) * exp(-rate * delta)
	rig.set_pose_weights(blend)

	# The walk, driven by distance covered so the feet cannot skate. Suppressed while he is
	# webbed or down, where the legs have no business moving at all.
	var free: float = clampf(1.0 - blend["webbed"] - blend["down"], 0.0, 1.0)
	if speed > 0.4 and free > 0.01:
		var ph := stride * TAU
		var gait := clampf(speed / 8.0, 0.0, 1.0)
		var amp := lerpf(0.26, 0.62, gait) * free
		var s1 := sin(ph)
		var s2 := sin(ph + PI)
		rig.add_offset("piv_hipL", X_AX, -s1 * amp)
		rig.add_offset("piv_hipR", X_AX, -s2 * amp)
		rig.add_offset("piv_kneeL", X_AX, maxf(0.0, sin(ph - PI * 0.35)) * amp * 1.5)
		rig.add_offset("piv_kneeR", X_AX, maxf(0.0, sin(ph + PI * 0.65)) * amp * 1.5)
		rig.add_offset("piv_shoulderL", X_AX, -s2 * amp * 0.5)
		rig.add_offset("piv_shoulderR", X_AX, -s1 * amp * 0.5)
		rig.add_offset("piv_hips", Y_AX, s1 * amp * 0.2)

	# Webbed men struggle. A thing that is perfectly still reads as scenery, and a thug
	# frozen mid-street is the single most obvious place for that to go wrong.
	if blend["webbed"] > 0.01:
		var t := Time.get_ticks_msec() * 0.004
		var w: float = blend["webbed"]
		rig.add_offset("piv_chest", Z_AX, sin(t * 1.7) * 0.10 * w)
		rig.add_offset("piv_hips", Y_AX, sin(t * 1.1) * 0.13 * w)
		rig.add_offset("piv_neck", Y_AX, sin(t * 2.3) * 0.16 * w)
