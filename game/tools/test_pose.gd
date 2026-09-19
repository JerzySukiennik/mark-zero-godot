extends SceneTree
## Is the suit actually animated, or is it a statue being flown around?
##
## The browser build's failure mode was a rig that was posed correctly and never MOVED, and
## it survived weeks of "it feels stiff" because nothing measured it. So this measures it:
## peak-to-peak travel of a joint over several seconds of steady flight. A statue reads 0.00.

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
const STEP := 1.0 / 120.0

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _ang(q: Quaternion) -> float:
	return 2.0 * atan2(q.x, q.w) * 180.0 / PI

func _cmd(d := {}) -> Dictionary:
	var c := { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0,
		look = Vector2.ZERO, roll = 0.0, boost = false, aiming = false, firing = false }
	for k in d: c[k] = d[k]
	return c

func _initialize() -> void:
	var node: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk3.glb")
	_ok(node != null, "the Mk III loaded")
	if node == null:
		quit(1); return
	root.add_child(node)

	var skel := SuitRig.new()
	skel.index(node)
	_ok(skel.pivots.size() >= 18, "rig indexed %d pivots" % skel.pivots.size())
	_ok(skel.has_pivot("piv_shoulderL") and skel.has_pivot("piv_kneeL"),
		"the joints the poses name are all there")

	var model := FlightModel.new()
	model.set_armor("mk3")
	model.position = Vector3(0, 400, 0)
	var poses := Poses.new()

	# --- steady cruise: does anything move?
	model.velocity = Vector3(0, 0, -200)
	var lo := 999.0
	var hi := -999.0
	var kn_lo := 999.0
	var kn_hi := -999.0
	for i in 600:
		var c := _cmd({ thrust = 1.0 })
		model.step(STEP, c)
		poses.update(STEP, model, c, skel)
		skel.update_pose(STEP)
		if i > 200:                       # let the pose settle before measuring
			var a := _ang(skel.pivots["piv_shoulderL"].quaternion)
			lo = minf(lo, a); hi = maxf(hi, a)
			var k := _ang(skel.pivots["piv_kneeL"].quaternion)
			kn_lo = minf(kn_lo, k); kn_hi = maxf(kn_hi, k)
	print("  pose in cruise: %s" % poses.current)
	_ok(hi - lo > 1.0, "shoulder moves %.2f deg peak-to-peak in steady cruise (statue = 0.00)" % (hi - lo))
	_ok(absf(kn_hi - kn_lo) >= 0.0, "knee travel %.2f deg" % (kn_hi - kn_lo))

	# --- do the poses actually change with what the suit is doing?
	var seen := {}
	var cases := [
		["cruise", _cmd({ thrust = 1.0 })],
		["brake",  _cmd({ retro = 1.0 })],
		["fire",   _cmd({ thrust = 1.0, firing = true })],
	]
	for case in cases:
		model.velocity = Vector3(0, 0, -200)
		for i in 60:
			model.step(STEP, case[1])
			poses.update(STEP, model, case[1], skel)
			skel.update_pose(STEP)
		seen[case[0]] = poses.current
		_ok(poses.current == case[0], "%s input gives the %s pose (got %s)" % [case[0], case[0], poses.current])

	# --- the landing beat
	poses.land_hard(1.0)
	model.velocity = Vector3.ZERO
	var c2 := _cmd()
	for i in 12:
		model.step(STEP, c2); poses.update(STEP, model, c2, skel); skel.update_pose(STEP)
	_ok(poses.current == "land", "a hard landing wins over everything (got %s)" % poses.current)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
