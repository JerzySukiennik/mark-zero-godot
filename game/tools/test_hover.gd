extends SceneTree
## Does the suit HOLD STATION, or does it levitate?
##
## Levitating is easy to detect and was what the game did: position constant to the
## millimetre, joints motionless. Holding station means wandering a little and correcting,
## so the test asks for both — it must move, and it must not drift away.

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _cmd() -> Dictionary:
	return { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0,
		look = Vector2.ZERO, roll = 0.0, boost = false, aiming = false, firing = false }

func _initialize() -> void:
	var node: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk3.glb")
	root.add_child(node)
	var skel := SuitRig.new(); skel.index(node)
	var poses := Poses.new()
	var m := FlightModel.new()
	m.set_armor("mk3")
	m.position = Vector3(0, 120, 0)
	m.velocity = Vector3.ZERO

	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var sh_lo := 999.0
	var sh_hi := -999.0
	var start := m.position
	var engaged := false
	for i in 1800:                       # 15 seconds of doing nothing
		var c := _cmd()
		m.step(STEP, c)
		poses.update(STEP, m, c, skel)
		skel.update_pose(STEP)
		if m.hover_active: engaged = true
		if i > 240:
			lo = lo.min(m.position); hi = hi.max(m.position)
			var a := 2.0 * atan2(skel.pivots["piv_shoulderL"].quaternion.x,
				skel.pivots["piv_shoulderL"].quaternion.w) * 180.0 / PI
			sh_lo = minf(sh_lo, a); sh_hi = maxf(sh_hi, a)

	var wander := hi - lo
	var drift := m.position.distance_to(start)
	print("  pose while hovering: %s" % poses.current)
	_ok(engaged and m.hover_active, "the stabiliser engaged and stayed engaged")
	_ok(wander.length() > 0.08, "it wanders while holding station: %.2f x %.2f x %.2f m" %
		[wander.x, wander.y, wander.z])
	_ok(drift < 8.0, "but it does not float away (%.2f m from where it started)" % drift)
	_ok(sh_hi - sh_lo > 0.8, "the arms answer the corrections: %.2f deg of shoulder" % (sh_hi - sh_lo))
	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
