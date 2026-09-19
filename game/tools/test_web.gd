extends SceneTree
## The web: does it grab the right thing, and is it a ROPE?
##
## The rope rule is the one worth guarding. A spring shoves you away when you swing in past
## the anchor, which reads as the thing you are holding onto repelling you, and it is the
## classic way this feature is got wrong. So: slack means no force at all, taut means pull
## only, and the pull always points AT the anchor.

const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _marker(at: Vector3) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = at
	return n

## Run on the FIRST FRAME, not in _initialize. Nodes added to `root` before the tree has
## started are not inside it yet, and every global_transform read returns identity with an
## error — which looks exactly like the aiming maths being wrong.
func _initialize() -> void:
	pass

func _process(_delta: float) -> bool:
	_run()
	quit(1 if bad > 0 else 0)
	return true

func _run() -> void:
	print("=== picking a target ===")
	var ahead := _marker(Vector3(0, 0, -60))
	var beside := _marker(Vector3(40, 0, -6))       # much closer, far off the aim line
	var miles := _marker(Vector3(0, 0, -400))       # dead ahead, out of range
	var aim := Vector3(0, 0, -1)

	var got := WebTether.pick(Vector3.ZERO, aim, [ahead, beside, miles])
	_ok(got == ahead, "it takes the one being AIMED at, not the nearest")
	_ok(WebTether.pick(Vector3.ZERO, aim, [beside]) == null, "nothing outside the cone")
	_ok(WebTether.pick(Vector3.ZERO, aim, [miles]) == null, "nothing past the range")

	print("=== the rope ===")
	var t := WebTether.new()
	_ok(t.fire(Vector3.ZERO, ahead), "it fires")
	_ok(t.state == WebTether.FLYING, "and travels before it lands")
	_ok(t.step(STEP, Vector3.ZERO, Vector3.ZERO, 0.0) == Vector3.ZERO,
		"a web still in flight pulls on nothing")

	var ticks := 0
	while t.state == WebTether.FLYING and ticks < 2000:
		t.step(STEP, Vector3.ZERO, Vector3.ZERO, 0.0)
		ticks += 1
	_ok(t.state == WebTether.ATTACHED, "it lands (%.3f s)" % (ticks * STEP))
	_ok(absf(t.rest_length - 60.0) < 2.0,
		"the rope is as long as the shot that made it (%.1f m)" % t.rest_length)

	# Slack: standing closer to the anchor than the rope is long.
	var slack_f := t.step(STEP, Vector3(0, 0, -30), Vector3.ZERO, 0.0)
	_ok(slack_f == Vector3.ZERO, "slack rope, no force at all")

	# Taut: hanging below and beyond it.
	var pos := Vector3(0, -30, 20)
	var taut := t.step(STEP, pos, Vector3.ZERO, 0.0)
	_ok(taut.length() > 1.0, "a stretched rope pulls (%.1f)" % taut.length())
	var to_anchor := (t.anchor_point() - pos).normalized()
	_ok(taut.normalized().dot(to_anchor) > 0.999, "and it pulls straight AT the anchor")

	# The rope must never push, at any distance inside its length.
	var pushed := false
	for i in 40:
		var p := t.anchor_point() + Vector3(0, -1.0 - i * 1.4, 0)
		var f := t.step(STEP, p, Vector3.ZERO, 0.0)
		if f.length() > 0.0 and f.normalized().dot((t.anchor_point() - p).normalized()) < 0.9:
			pushed = true
	_ok(not pushed, "it never pushes, at any length")

	print("=== being towed ===")
	# The anchor is a NODE, so an Iron Man flying away drags the rider after him. This is
	# the whole feature: a tether stuck to a fixed POINT would simply snap taut and stop.
	var flier := _marker(Vector3(0, 40, -60))
	var t2 := WebTether.new()
	t2.fire(Vector3.ZERO, flier)
	while t2.state == WebTether.FLYING:
		t2.step(STEP, Vector3.ZERO, Vector3.ZERO, 0.0)

	var rider := Vector3.ZERO
	var vel := Vector3.ZERO
	for i in 600:                                    # five seconds
		flier.global_position += Vector3(0, 0, -80) * STEP    # 80 m/s away
		var a := t2.step(STEP, rider, vel, 0.0) + Vector3(0, -9.81, 0)
		vel += a * STEP
		rider += vel * STEP
	_ok(rider.z < -100.0, "the rider is dragged along behind (z %.0f)" % rider.z)
	_ok(rider.distance_to(t2.anchor_point()) < t2.rest_length * 1.6,
		"and stays on the end of the rope, not left behind")

	print("=== reeling and letting go ===")
	var before := t2.rest_length
	t2.step(STEP * 60.0, rider, vel, 1.0)
	_ok(t2.rest_length < before, "hauling in shortens the rope")
	t2.release()
	_ok(t2.state == WebTether.IDLE and t2.step(STEP, rider, vel, 0.0) == Vector3.ZERO,
		"letting go drops it entirely")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
