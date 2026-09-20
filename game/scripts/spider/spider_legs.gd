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

# ---- lashing ------------------------------------------------------------------------
## Jurek: "prawą gałką jak się przyciśnie, to on aktywuje te ręce z tyłu, które jakby się
## ruszają i uderzają we wrogów, którzy nachodzą z różnych stron."
##
## The point of the legs as a WEAPON is that they answer the thing behind you. Nothing else
## Spider-Man has does: the web, the zip and every punch go where he is facing. So a leg
## picks its own man, anywhere in a full circle, and the four of them cover four arcs.
const LASH_TIME := 1.5
## How far a leg can reach, and how hard it lands. Two jabs per leg over the window.
const LASH_REACH := 5.0
const LASH_DAMAGE := 34.0
const LASH_JABS := 2

## Seconds left of the flurry, 0 when idle.
var lash := 0.0
## One target per leg, so four men get hit rather than one man four times.
var _marks := { "A": null, "B": null, "C": null, "D": null }
## Which jab each leg has already landed, so damage goes in at the extension and not
## once a frame for a second and a half.
var _landed := { "A": 0, "B": 0, "C": 0, "D": 0 }

func lashing() -> bool:
	return lash > 0.0

## Starts the flurry and hands each leg the closest man in its own arc.
func begin_lash(origin: Node3D, enemies: Array) -> void:
	lash = LASH_TIME
	for leg in ORDER:
		_marks[leg] = null
		_landed[leg] = 0
	if origin == null:
		return
	var here := origin.global_position
	var fwd := -origin.global_basis.z
	var left := -origin.global_basis.x
	# A, B, C, D take front-right, front-left, back-right, back-left. The arcs are quarters
	# with no gaps, so a man anywhere around him belongs to exactly one leg.
	var arcs := {
		"A": (fwd - left).normalized(), "B": (fwd + left).normalized(),
		"C": (-fwd - left).normalized(), "D": (-fwd + left).normalized(),
	}
	for leg in ORDER:
		var best: Node3D = null
		var best_d := LASH_REACH
		for n in enemies:
			if not is_instance_valid(n) or n in _marks.values():
				continue
			var to: Vector3 = (n as Node3D).global_position - here
			to.y = 0.0
			var d := to.length()
			if d > best_d or d < 0.01:
				continue
			if (arcs[leg] as Vector3).dot(to / d) < 0.35:
				continue
			best = n
			best_d = d
		_marks[leg] = best

## Advances the flurry and reports which enemies were struck THIS frame, so the pilot can
## apply the damage — the legs know where they are, not what damage means.
func service_lash(delta: float) -> Array:
	var hits: Array = []
	if lash <= 0.0:
		return hits
	lash = maxf(0.0, lash - delta)
	var done := 1.0 - lash / LASH_TIME
	for leg in ORDER:
		var mark = _marks[leg]
		if mark == null or not is_instance_valid(mark):
			continue
		# Each jab lands at its own extension. Evenly spaced across the window and offset
		# per leg, which is why it reads as a flurry rather than a single slam.
		var phase: float = fposmod(done * LASH_JABS + ORDER.find(leg) * 0.17, 1.0)
		var at_reach := phase > 0.45 and phase < 0.62
		if at_reach and _landed[leg] < int(done * LASH_JABS) + 1:
			_landed[leg] = int(done * LASH_JABS) + 1
			hits.append(mark)
	return hits

## Where a leg should point right now, as a direction in the OWNER's frame, or the parked
## deploy direction when it has nobody.
func _lash_aim(leg: String, key: String, base: Vector3, origin: Node3D) -> Vector3:
	var mark = _marks.get(leg)
	if mark == null or not is_instance_valid(mark) or origin == null or not key.ends_with("1"):
		return base
	var to: Vector3 = origin.global_basis.inverse() * ((mark as Node3D).global_position - origin.global_position)
	if to.length_squared() < 1e-4:
		return base
	# Only the root segment turns to face the man; the two below it keep the authored
	# shape, so a leg that is aiming still looks like that leg.
	return base.lerp(to.normalized(), 0.65).normalized()

func drive(delta: float, want: bool, skel: SuitRig, origin: Node3D = null) -> void:
	if skel == null:
		return
	# A flurry forces them out whatever the rest of him is doing — you press the stick
	# standing on the pavement and they come out.
	if lash > 0.0:
		want = true
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
			var dir := a.lerp(b, k).normalized()
			if lash > 0.0:
				# The jab itself: the whole leg drives out and snaps back twice over the
				# window, on top of wherever it is pointing.
				var done := 1.0 - lash / LASH_TIME
				var phase := fposmod(done * LASH_JABS + ORDER.find(leg) * 0.17, 1.0)
				var drive_out := sin(clampf(phase, 0.0, 1.0) * PI)
				dir = _lash_aim(leg, key, dir, origin)
				if seg < 2:
					dir = dir.lerp(dir + Vector3(0, -0.35, 0), drive_out).normalized()
			skel.aim_joint("piv_leg" + key, dir)
