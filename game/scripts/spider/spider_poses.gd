class_name SpiderPoses
extends RefCounted
## Spider-Man's body language, authored from scratch.
##
## He was borrowing the armour's poses, and it showed: the Mark III's six stances describe
## an aircraft — cruise, brake, hover, station-keeping — and none of them is anything
## Spider-Man does. Standing, he stood like a suit of armour; running, he ran like one; and
## hanging off a web he was posed as though holding formation. Jurek: "ta animacja Iron
## Spider powinna być zrobiona od zera."
##
## The rules this is built on, which are the ones that separate him from Iron Man:
##  - He is never straight. Iron Man holds still because servos hold him; Spider-Man is a
##    teenager who cannot stand still, so every pose here is slightly coiled.
##  - The legs lead. He crouches, springs and lands on them; the arms are for aiming webs.
##  - Hanging, the whole body is a pendulum under ONE arm — which arm depends on which web
##    is carrying him, and that asymmetry is most of what makes a swing read as a swing.

const X_AX := Vector3(1, 0, 0)
const Y_AX := Vector3(0, 1, 0)
const Z_AX := Vector3(0, 0, 1)

static func _d(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z).normalized()

## The authored stances. Same grammar as SuitRig.POSES — `dir` is where the limb points in
## its parent's frame — so the rig can blend these exactly as it blends the armour's.
static var POSES := {
	# Never at attention. Knees soft, weight forward on the balls of the feet, hands open
	# and slightly out: a body ready to move rather than one at rest.
	"idle": {
		"piv_shoulderL": { "dir": _d(0.26, -0.94, -0.22), "twist": -8.0 },
		"piv_shoulderR": { "dir": _d(-0.26, -0.94, -0.22), "twist": 8.0 },
		"piv_elbowL": { "dir": _d(-0.10, -0.90, -0.42) },
		"piv_elbowR": { "dir": _d(0.10, -0.90, -0.42) },
		"piv_hipL": { "dir": _d(0.10, -0.98, -0.15) },
		"piv_hipR": { "dir": _d(-0.10, -0.98, -0.15) },
		"piv_kneeL": { "dir": _d(0, -0.95, 0.31) },
		"piv_kneeR": { "dir": _d(0, -0.95, 0.31) },
		"piv_ankleL": { "dir": _d(0, -0.93, -0.37) },
		"piv_ankleR": { "dir": _d(0, -0.93, -0.37) },
		"piv_chest": { "dir": _d(0, 0.99, -0.14) },
		"piv_neck": { "dir": _d(0, 0.97, -0.24) },
	},
	# A sprinter's carriage: chest well forward over the hips, arms driving rather than
	# swinging. The cycle itself is laid over this as offsets.
	"run": {
		"piv_shoulderL": { "dir": _d(0.18, -0.90, -0.40), "twist": -14.0 },
		"piv_shoulderR": { "dir": _d(-0.18, -0.90, -0.40), "twist": 14.0 },
		"piv_elbowL": { "dir": _d(-0.06, -0.62, -0.78) },
		"piv_elbowR": { "dir": _d(0.06, -0.62, -0.78) },
		"piv_hipL": { "dir": _d(0.08, -0.99, 0.0) },
		"piv_hipR": { "dir": _d(-0.08, -0.99, 0.0) },
		"piv_kneeL": { "dir": _d(0, -0.93, 0.36) },
		"piv_kneeR": { "dir": _d(0, -0.93, 0.36) },
		"piv_chest": { "dir": _d(0, 0.94, -0.34) },
		"piv_neck": { "dir": _d(0, 0.93, -0.36) },
	},
	# Hanging off a web. Legs swept back and tucked, body raked, head up towards the anchor
	# — he is looking where he is going, which is up the line.
	"swing": {
		# Both arms LOW here. The one actually carrying him is aimed straight up the line
		# below, and the contrast between the two is the whole read.
		"piv_shoulderL": { "dir": _d(0.34, -0.72, 0.60), "twist": -10.0 },
		"piv_shoulderR": { "dir": _d(-0.34, -0.72, 0.60), "twist": 10.0 },
		"piv_elbowL": { "dir": _d(-0.08, -0.80, 0.59) },
		"piv_elbowR": { "dir": _d(0.08, -0.80, 0.59) },
		"piv_hipL": { "dir": _d(0.10, -0.80, 0.59) },
		"piv_hipR": { "dir": _d(-0.10, -0.80, 0.59) },
		"piv_kneeL": { "dir": _d(0, -0.55, 0.84) },
		"piv_kneeR": { "dir": _d(0, -0.62, 0.78) },
		"piv_chest": { "dir": _d(0, 0.96, -0.28) },
		"piv_neck": { "dir": _d(0, 0.88, -0.48) },
	},
	# Falling free: spread, belly down, the way a diver holds an arch.
	"fall": {
		"piv_shoulderL": { "dir": _d(0.72, -0.30, -0.62), "twist": -22.0 },
		"piv_shoulderR": { "dir": _d(-0.72, -0.30, -0.62), "twist": 22.0 },
		"piv_elbowL": { "dir": _d(-0.20, -0.42, -0.88) },
		"piv_elbowR": { "dir": _d(0.20, -0.42, -0.88) },
		"piv_hipL": { "dir": _d(0.26, -0.88, 0.40) },
		"piv_hipR": { "dir": _d(-0.26, -0.88, 0.40) },
		"piv_kneeL": { "dir": _d(0, -0.78, 0.63) },
		"piv_kneeR": { "dir": _d(0, -0.78, 0.63) },
		"piv_chest": { "dir": _d(0, 0.97, -0.24) },
	},
	# THE THREE-POINT LANDING. Deep crouch, one hand down, the other trailed behind.
	"land": {
		"piv_shoulderL": { "dir": _d(0.34, -0.86, -0.38), "twist": -16.0 },
		"piv_shoulderR": { "dir": _d(-0.46, -0.30, 0.83), "twist": 26.0 },
		"piv_elbowL": { "dir": _d(-0.08, -0.97, -0.22) },
		"piv_elbowR": { "dir": _d(0.12, -0.55, 0.83) },
		"piv_hipL": { "dir": _d(0.22, -0.72, -0.66) },
		"piv_hipR": { "dir": _d(-0.16, -0.94, 0.30) },
		"piv_kneeL": { "dir": _d(0, -0.62, 0.79) },
		"piv_kneeR": { "dir": _d(0, -0.42, 0.91) },
		"piv_chest": { "dir": _d(0, 0.88, -0.48) },
		"piv_neck": { "dir": _d(0, 0.90, -0.44) },
	},
}

const NAMES := ["idle", "run", "swing", "fall", "land"]
## Entering a landing is instant; leaving one is slow, because picking yourself up takes
## longer than hitting the ground.
const ENTER := { "idle": 7.0, "run": 11.0, "swing": 9.0, "fall": 6.0, "land": 26.0 }
const LEAVE := { "idle": 6.0, "run": 8.0, "swing": 6.0, "fall": 5.0, "land": 3.0 }

var blend: Dictionary = {}
var current := "idle"
var _land_timer := 0.0
var _bob := 0.0

func _init() -> void:
	for n in NAMES:
		blend[n] = 1.0 if n == "idle" else 0.0

func land_hard(force: float) -> void:
	_land_timer = maxf(_land_timer, 0.25 + force * 0.45)

## `hands` is which tethers are attached, e.g. {"R": true, "L": false}.
func update(delta: float, model: SpiderModel, hands: Dictionary, rig: SuitRig) -> void:
	if rig == null:
		return
	rig.pose_table = POSES
	# CLEARED FIRST, EVERY FRAME. add_offset ACCUMULATES — it multiplies onto whatever is
	# already there, because several drivers write to one joint per frame and a plain
	# assignment would let the last one silently delete the rest. Which means the whole set
	# has to be thrown away at the top of each frame, and this never did it: the neck's
	# 0.10 rad idle turn compounded at 120 Hz into roughly two full revolutions a second.
	# "Kreci mu sie glowa w kolko" was exactly that, and the same accumulation was wrecking
	# every other joint, which is why the walk looked deranged.
	rig.clear_offsets()
	_choose(delta, model, hands)
	rig.set_pose_weights(blend)
	_drive(delta, model, hands, rig)

func _choose(delta: float, model: SpiderModel, hands: Dictionary) -> void:
	if _land_timer > 0.0:
		_land_timer -= delta
	var hanging: bool = hands.get("R", false) or hands.get("L", false)

	var name := "idle"
	if _land_timer > 0.0 and model.grounded:
		name = "land"
	elif model.grounded:
		name = "run" if model.ground_speed > 0.5 else "idle"
	elif hanging:
		name = "swing"
	else:
		name = "fall"
	current = name

	for n in NAMES:
		var to := 1.0 if n == name else 0.0
		var rate: float = ENTER[n] if to > blend[n] else LEAVE[n]
		blend[n] = to + (blend[n] - to) * exp(-rate * delta)

## The procedural layer. Everything driven by a real quantity, and nothing on a timer
## except the idle breath — which exists because a correct pose held perfectly still reads
## as a mannequin, and that is twice as wrong for this character as for the armour.
func _drive(delta: float, model: SpiderModel, hands: Dictionary, rig: SuitRig) -> void:
	_bob += delta

	# ---- the run cycle -----------------------------------------------------------------
	var running: float = blend["run"]
	if running > 0.001:
		var ph: float = model.stride_phase * TAU
		var gait := clampf(model.ground_speed / SpiderModel.RUN_SPEED, 0.0, 1.0)
		var amp := lerpf(0.30, 0.95, gait) * running
		var s1 := sin(ph)
		var s2 := sin(ph + PI)
		# Negative X is forward, the same convention the armour's arm trail uses.
		rig.add_offset("piv_hipL", X_AX, -s1 * amp)
		rig.add_offset("piv_hipR", X_AX, -s2 * amp)
		# Knees fold only as the leg comes through behind — a symmetric bend is the clearest
		# tell of a puppet.
		rig.add_offset("piv_kneeL", X_AX, maxf(0.0, sin(ph - PI * 0.35)) * amp * 1.7)
		rig.add_offset("piv_kneeR", X_AX, maxf(0.0, sin(ph + PI * 0.65)) * amp * 1.7)
		rig.add_offset("piv_ankleL", X_AX, s1 * amp * 0.40)
		rig.add_offset("piv_ankleR", X_AX, s2 * amp * 0.40)
		# Arms drive OPPOSITE the leg on the same side.
		rig.add_offset("piv_shoulderL", X_AX, -s2 * amp * 0.72)
		rig.add_offset("piv_shoulderR", X_AX, -s1 * amp * 0.72)
		rig.add_offset("piv_hips", Y_AX, s1 * amp * 0.26)
		rig.add_offset("piv_chest", Y_AX, -s1 * amp * 0.20)
		rig.add_offset("piv_chest", Z_AX, s1 * amp * 0.08)

	# ---- hanging ------------------------------------------------------------------------
	# ONE arm carries him and the other does not, and which one is whichever web is
	# actually attached. Posing both arms up is the difference between a man on a rope and
	# a man being lifted by the shoulders.
	var swinging: float = blend["swing"]
	if swinging > 0.001:
		# AIMED, not offset. An offset about X swings an arm fore and aft, which is why
		# nudging it by 0.85 rad moved the hand two centimetres: what is wanted is the arm
		# pointing straight UP the web, which is a direction, not a nudge. aim_joint takes
		# the direction and works out the rotation.
		if swinging > 0.5:
			for hand: String in ["R", "L"]:
				if not hands.get(hand, false):
					continue
				var side: String = SuitRig.SIDE[hand]
				var out := 0.22 if side == "L" else -0.22
				rig.aim_joint("piv_shoulder" + side, _d(out, 0.95, -0.22))
				rig.aim_joint("piv_elbow" + side, _d(0, 0.99, -0.14))
		# The body swings with its own momentum: lateral speed rakes it sideways.
		var lat: float = clampf((model.basis_.inverse() * model.velocity).x / 24.0, -1.0, 1.0)
		rig.add_offset("piv_hips", Z_AX, -lat * 0.30 * swinging)
		rig.add_offset("piv_chest", Z_AX, -lat * 0.22 * swinging)
		rig.add_offset("piv_neck", Z_AX, lat * 0.16 * swinging)

	# ---- falling ------------------------------------------------------------------------
	var falling: float = blend["fall"]
	if falling > 0.001:
		# Arms and legs flare with airspeed, which is the only cue for how fast a fall is
		# when there is nothing nearby to judge it against.
		var fast := clampf(model.speed / 55.0, 0.0, 1.0) * falling
		rig.add_offset("piv_shoulderL", Z_AX, -0.32 * fast)
		rig.add_offset("piv_shoulderR", Z_AX, 0.32 * fast)
		rig.add_offset("piv_hipL", Z_AX, -0.20 * fast)
		rig.add_offset("piv_hipR", Z_AX, 0.20 * fast)

	# ---- he is never still --------------------------------------------------------------
	var settled := clampf(blend["idle"] + blend["land"], 0.0, 1.0)
	rig.add_offset("piv_chest", X_AX, sin(_bob * 1.9) * 0.022 * settled)
	rig.add_offset("piv_neck", Y_AX, sin(_bob * 0.7) * 0.10 * settled)
	rig.add_offset("piv_neck", X_AX, sin(_bob * 1.3 + 1.0) * 0.045 * settled)
