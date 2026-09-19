class_name SpiderLegs
extends RefCounted
## The four legs on the Iron Spider's back.
##
## Folded flat against the shell at rest and swung out when they are wanted. Deploying is a
## PURE ROTATION of the same pivots — nothing translates — which is the property that lets
## twelve numbers describe the whole thing.
##
## Directions are lifted verbatim from assets/suits/ironspider-notes.md, in the same form
## SuitRig.POSES already speaks: where each segment points in its PARENT's frame.

## Seconds to swing out, and to fold back. Out is slower than in: deploying is a display,
## retracting is tidying up.
const OUT_TIME := 0.45
const IN_TIME := 0.30
## Head start between legs, so four of them read as four rather than as one bundle.
const STAGGER := 0.05
const ORDER := ["A", "B", "C", "D"]

const STOW := {
	"A1": Vector3(+0.550, +0.820, +0.150), "A2": Vector3(+0.109, +0.733, +0.672), "A3": Vector3(+0.017, -0.994, +0.062),
	"B1": Vector3(-0.550, +0.820, +0.150), "B2": Vector3(-0.109, +0.733, +0.672), "B3": Vector3(-0.017, -0.994, +0.062),
	"C1": Vector3(+0.550, +0.700, +0.180), "C2": Vector3(+0.102, +0.619, +0.774), "C3": Vector3(+0.014, -0.993, +0.101),
	"D1": Vector3(-0.550, +0.700, +0.180), "D2": Vector3(-0.102, +0.619, +0.774), "D3": Vector3(-0.014, -0.993, +0.101),
}
const DEPLOY := {
	"A1": Vector3(+0.620, +0.620, +0.480), "A2": Vector3(+0.540, -0.393, +0.740), "A3": Vector3(+0.041, -0.906, -0.423),
	"B1": Vector3(-0.620, +0.620, +0.480), "B2": Vector3(-0.540, -0.393, +0.740), "B3": Vector3(-0.041, -0.906, -0.423),
	"C1": Vector3(+0.720, +0.300, +0.620), "C2": Vector3(+0.501, -0.304, +0.808), "C3": Vector3(+0.127, -0.950, -0.287),
	"D1": Vector3(-0.720, +0.300, +0.620), "D2": Vector3(-0.501, -0.304, +0.808), "D3": Vector3(-0.127, -0.950, -0.287),
}

## 0 folded, 1 fully out. Public so the pilot and the tests can read it.
var out := 0.0

func drive(delta: float, want: bool, skel: SuitRig) -> void:
	if skel == null:
		return
	out = move_toward(out, 1.0 if want else 0.0, delta / (OUT_TIME if want else IN_TIME))

	for i in ORDER.size():
		var leg: String = ORDER[i]
		# Each leg runs on its own clock, offset by the stagger and rescaled so it still
		# finishes inside the same window rather than overrunning the last one.
		var lead := float(i) * STAGGER / OUT_TIME
		var t := clampf((out - lead) / maxf(0.01, 1.0 - lead), 0.0, 1.0)
		for seg in 3:
			var key: String = "%s%d" % [leg, seg + 1]
			var a: Vector3 = STOW[key]
			var b: Vector3 = DEPLOY[key]
			# The talon overshoots a little on the way out and snaps back, which is what
			# makes a machine unfolding read as sprung rather than as driven by a servo.
			var k := t
			if seg == 2 and want and t > 0.55:
				k = t + sin((t - 0.55) / 0.45 * PI) * 0.16
			skel.aim_joint("piv_leg" + key, a.lerp(b, k).normalized())
