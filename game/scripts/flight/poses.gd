class_name Poses
extends RefCounted
## What the armour DOES while it flies. Ported from the browser build's poses.js.
##
## Two layers, and keeping them apart is the whole design:
##
##   THE POSE     one of six authored silhouettes, cross-faded. Slow, smooth, readable.
##   THE OFFSETS  procedural rotations layered on top, driven by what the airframe is
##                actually doing this instant. Fast, small, and they are what makes the
##                suit look alive rather than posed.
##
## The offsets are the part that took longest to get right, and the lesson is recorded in
## SuitRig.update_pose: they must NOT go through the pose's smoothing filter. When they did,
## every one of them was averaged away before it reached the screen and the suit read as a
## statue — which is exactly what Jurek reported, repeatedly, for weeks.

const NAMES := ["stand", "walk", "hover", "cruise", "brake", "fire", "land"]

## How fast each pose arrives, and how fast it lets go, per second.
##
## One rate for everything means every pose takes about 200 ms. For a cruise-to-hover
## cross-fade that is right. For FIRING it is the whole problem: the shot leaves on the frame
## you pull the trigger and the arm meant to throw it is still 200 ms behind. The pose has to
## beat the bolt. Same for a landing, which is an impact and not a mood.
##
## Asymmetric on purpose: snapping INTO a pose reads as a decision, snapping out of one reads
## as a glitch.
const ENTER := { "stand": 5.0, "walk": 9.0, "hover": 5.0, "cruise": 4.0, "brake": 9.0, "fire": 22.0, "land": 26.0 }
const LEAVE := { "stand": 4.0, "walk": 7.0, "hover": 5.0, "cruise": 4.0, "brake": 6.0, "fire": 5.0, "land": 3.0 }

const X_AX := Vector3(1, 0, 0)
const Y_AX := Vector3(0, 1, 0)
const Z_AX := Vector3(0, 0, 1)

var blend: Dictionary = {}
var current := "stand"
var _t := 0.0
var _land_timer := 0.0

func _init() -> void:
	for n in NAMES:
		blend[n] = 1.0 if n == "stand" else 0.0

## Called when the suit touches down hard, so the landing pose wins for a moment.
func land_hard(force: float) -> void:
	_land_timer = 0.35 + clampf(force, 0.0, 1.0) * 0.45

func update(delta: float, model: FlightModel, cmd: Dictionary, rig: SuitRig) -> void:
	_t += delta
	if _land_timer > 0.0:
		_land_timer -= delta

	_pick(delta, model, cmd)
	rig.set_pose_weights(blend)
	rig.clear_offsets()
	_drive(delta, model, cmd, rig)

func _pick(delta: float, model: FlightModel, cmd: Dictionary) -> void:
	var speed := model.speed
	var fast := clampf(speed / maxf(1.0, model.spec.top_speed * 0.55), 0.0, 1.0)
	var bv := model.basis_.inverse() * model.velocity
	var backwards := bv.z > 12.0
	var retro: float = cmd.get("retro", 0.0)

	var name := "hover"
	# The landing beats everything: you do not get to strike a cruise pose while still
	# folded over your own fist.
	if _land_timer > 0.0:
		name = "land"
	elif model.grounded and model.thrust_mag < 0.1:
		# Half a metre per second is the line: below it the legs would be swinging for a
		# drift the eye cannot see, which reads as the suit shuffling on the spot.
		name = "walk" if model.ground_speed > 0.5 else "stand"
	elif cmd.get("aiming", false) or cmd.get("firing", false):
		name = "fire"
	elif backwards or retro > 0.05:
		name = "brake"
	elif fast > 0.35:
		name = "cruise"
	current = name

	for n in NAMES:
		var to := 1.0 if n == name else 0.0
		var rate: float = ENTER[n] if to > blend[n] else LEAVE[n]
		blend[n] = _approach(blend[n], to, rate, delta)

static func _approach(v: float, to: float, rate: float, delta: float) -> float:
	return to + (v - to) * exp(-rate * delta)

## The procedural layer. Everything here is small, fast, and driven by a real quantity —
## nothing is a sine wave for its own sake except the idle, which exists precisely because
## a correct pose held perfectly still reads as a statue being dragged through the air.
func _drive(delta: float, model: FlightModel, cmd: Dictionary, rig: SuitRig) -> void:
	# What the pilot FEELS: acceleration in body axes. Gravity is added back only when he is
	# NOT standing on something — on the ground the floor has already cancelled it, and
	# adding it anyway invents a full g out of nothing. That phantom g used to hold both
	# shoulders thirty degrees back for as long as the suit stood there: "arms bent
	# backwards, as if they were broken".
	var a := model.accel
	if not model.grounded:
		a.y += FlightModel.G
	a = model.basis_.inverse() * a

	var fast := clampf(model.speed / maxf(1.0, model.spec.top_speed * 0.55), 0.0, 1.0)
	var slide: float = clampf(cmd.get("lateral", 0.0), -1.0, 1.0)
	var settled := clampf(1.0 - (blend["stand"] + blend["land"] + blend["walk"]), 0.0, 1.0)

	# Arms trail the acceleration: push forward and they sweep back, brake and they are
	# thrown out in front. Faded out as the suit settles onto its feet — a man standing still
	# has his arms at his sides whatever the accelerometer says.
	var arm_trail: float = clampf(-a.z * 0.012, -0.35, 0.35) * settled
	var sweep: float = blend["cruise"] * 0.42
	rig.add_offset("piv_shoulderL", X_AX, arm_trail + sweep)
	rig.add_offset("piv_shoulderR", X_AX, arm_trail + sweep)

	# The skier: through a slide the OUTSIDE arm opens and the inside one tucks. This is the
	# asymmetry that stops a turn looking like a rigid object being rotated, and at 0.26 it
	# was too faint to read at all — a suit sliding sideways looked exactly like a suit
	# hanging still. It also now drives the ELBOWS and the legs, because a real turn is the
	# whole body committing to it rather than two shoulders moving politely.
	rig.add_offset("piv_shoulderL", Z_AX, -slide * 0.58)
	rig.add_offset("piv_shoulderR", Z_AX, slide * 0.58)
	# The inside arm folds in towards the chest; the outside one reaches away. Which is
	# which flips with the direction, which is what the signed max is doing.
	rig.add_offset("piv_elbowL", X_AX, -maxf(0.0, slide) * 0.45)
	rig.add_offset("piv_elbowR", X_AX, -maxf(0.0, -slide) * 0.45)
	# The legs trail out of the turn, the way they do behind a motorbike leaning over.
	rig.add_offset("piv_hipL", Z_AX, -slide * 0.22)
	rig.add_offset("piv_hipR", Z_AX, slide * 0.22)
	# And he looks WHERE HE IS GOING. A head locked forward through a sideways slide is the
	# clearest possible sign that the body is being dragged rather than steering.
	rig.add_offset("piv_neck", Z_AX, slide * 0.14)
	rig.add_offset("piv_chest", Z_AX, -slide * 0.12)

	# Elbows bend in a hover and under braking, dead straight at cruise.
	# Hover's share used to be 0.55, which folded the elbows a further thirty degrees on top
	# of an already-tucked pose — the arms never came anywhere near straight. A hovering man
	# has straight arms; it is BRAKING that bends them.
	var bend: float = (blend["hover"] * 0.10 + blend["brake"] * 0.85 + blend["stand"] * 0.2) * 0.9
	rig.add_offset("piv_elbowL", X_AX, -bend)
	rig.add_offset("piv_elbowR", X_AX, -bend)

	# Legs trail the same acceleration at 60% and tuck together with speed.
	var leg_trail := arm_trail * 0.6
	rig.add_offset("piv_hipL", X_AX, leg_trail)
	rig.add_offset("piv_hipR", X_AX, leg_trail)
	rig.add_offset("piv_hipL", Z_AX, -fast * 0.05)
	rig.add_offset("piv_hipR", Z_AX, fast * 0.05)

	# The head leads a turn slightly, and looks where the stick is pointing. A head locked
	# to the chest is the single most robotic thing a rig can do.
	var look: Vector2 = cmd.get("look", Vector2.ZERO)
	rig.add_offset("piv_neck", Y_AX, clampf(-look.x * 6.0, -0.30, 0.30))
	rig.add_offset("piv_neck", X_AX, clampf(look.y * 4.0, -0.22, 0.22))

	# THE WALK CYCLE. Phase comes from FlightModel.stride_phase, which counts DISTANCE
	# rather than seconds — the feet cannot skate if the legs are geared to the ground.
	var walking: float = blend["walk"]
	if walking > 0.001:
		var ph: float = model.stride_phase * TAU
		var gait := clampf(model.ground_speed / FlightModel.RUN_SPEED, 0.0, 1.0)
		# A stroll barely swings; a run throws the legs. One amplitude drives the whole
		# cycle so the parts cannot drift out of proportion with each other.
		var amp := lerpf(0.26, 0.70, gait) * walking
		var s1 := sin(ph)
		var s2 := sin(ph + PI)

		# Hips swing fore and aft in opposition. Negative X is forward here, the same
		# convention the arm trail uses.
		rig.add_offset("piv_hipL", X_AX, -s1 * amp)
		rig.add_offset("piv_hipR", X_AX, -s2 * amp)

		# Knees bend on the BACK half of the swing only. A knee that bends symmetrically
		# through the whole cycle is the single clearest tell of a puppet: real legs are
		# straight as they plant and fold as they are picked up behind.
		rig.add_offset("piv_kneeL", X_AX, maxf(0.0, sin(ph - PI * 0.35)) * amp * 1.6)
		rig.add_offset("piv_kneeR", X_AX, maxf(0.0, sin(ph + PI * 0.65)) * amp * 1.6)
		# Ankles keep the sole roughly flat against the plate through the plant.
		rig.add_offset("piv_ankleL", X_AX, s1 * amp * 0.35)
		rig.add_offset("piv_ankleR", X_AX, s2 * amp * 0.35)

		# Arms counter-swing: the left arm goes with the RIGHT leg. Getting this the same
		# way round is how a walk starts looking like a march.
		rig.add_offset("piv_shoulderL", X_AX, -s2 * amp * 0.55)
		rig.add_offset("piv_shoulderR", X_AX, -s1 * amp * 0.55)
		rig.add_offset("piv_elbowL", X_AX, -(0.22 + 0.24 * gait) * walking)
		rig.add_offset("piv_elbowR", X_AX, -(0.22 + 0.24 * gait) * walking)

		# The pelvis twists with the stride and the chest counter-rotates against it. This
		# pair costs two lines and does more for the walk than the legs do.
		rig.add_offset("piv_hips", Y_AX, s1 * amp * 0.22)
		rig.add_offset("piv_chest", Y_AX, -s1 * amp * 0.16)
		rig.add_offset("piv_chest", Z_AX, s1 * amp * 0.09)

	# HOLDING STATION. The flight model publishes what its stabiliser is doing this instant
	# (see FlightModel._hover), and the limbs answer it. This is the difference between a
	# suit that levitates and one that is visibly working to stay put: the arms move BECAUSE
	# the body was pushed, on the body's rhythm, not on a timer of their own.
	#
	# Counter-intuitively the arms swing WITH the correction, not against it. A stabilised
	# aircraft points its thrust where it needs to go, and a hovering man does the same with
	# his hands — the palms are the control surfaces, so they lead the recovery rather than
	# bracing against it.
	var hov: float = blend["hover"]
	if hov > 0.02:
		var corr := model.hover_correction
		var gain := hov * 0.55
		# Sideways correction rolls both shoulders the same way — the whole body leans into
		# the save, which is what makes it read as balance rather than as flapping.
		rig.add_offset("piv_shoulderL", Z_AX, -corr.x * gain)
		rig.add_offset("piv_shoulderR", Z_AX, -corr.x * gain)
		# Fore-and-aft correction opens or closes the arms.
		rig.add_offset("piv_shoulderL", X_AX, corr.z * gain * 0.8)
		rig.add_offset("piv_shoulderR", X_AX, corr.z * gain * 0.8)
		# Vertical is the palms: they are what is holding him up, so they take the load.
		rig.add_offset("piv_elbowL", X_AX, -corr.y * gain * 0.5)
		rig.add_offset("piv_elbowR", X_AX, -corr.y * gain * 0.5)
		# The legs trail the save a beat later, which is what stops the whole body moving as
		# one rigid piece.
		rig.add_offset("piv_hipL", X_AX, corr.z * gain * 0.35)
		rig.add_offset("piv_hipR", X_AX, corr.z * gain * 0.35)
		# And the head stays level against it — a stabilised head on a moving body is the
		# oldest trick there is for making something look alive rather than driven.
		rig.add_offset("piv_neck", Z_AX, corr.x * gain * 0.6)
		rig.add_offset("piv_neck", X_AX, -corr.z * gain * 0.4)

	# THE IDLE. Correct and perfectly still is a statue. Three slow incommensurate wobbles
	# cost nothing and keep the armour alive between manoeuvres; the frequencies are
	# deliberately unrelated so it never settles into a visible loop.
	var idle: float = 1.0 - 0.5 * blend["stand"]
	rig.add_offset("piv_shoulderL", X_AX, sin(_t * 0.83) * 0.016 * idle)
	rig.add_offset("piv_shoulderR", X_AX, sin(_t * 1.27 + 2.1) * 0.014 * idle)
	rig.add_offset("piv_chest", X_AX, sin(_t * 0.61 + 0.7) * 0.010 * idle)

	# The rattle. Only above 2 g, only a few thousandths of a radian: at 6 g the armour
	# buzzes, and below 2 it is perfectly still.
	var jitter := maxf(model.g_force - 2.0, 0.0)
	if jitter > 0.01:
		var j := minf(jitter, 4.0) * 0.004
		rig.add_offset("piv_chest", Z_AX, sin(_t * 61.0) * j)
		rig.add_offset("piv_head", X_AX, sin(_t * 47.0) * j)
