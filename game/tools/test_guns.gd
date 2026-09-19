extends SceneTree
## Do the repulsors fire, and do the shots go where the crosshair is rather than where the
## hand happens to be pointing?

const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _initialize() -> void:
	var g := Repulsors.new()
	root.add_child(g)
	g.build()

	# A hand well off to one side, and a target straight ahead. A bolt fired "out of the
	# palm" would miss by the width of the offset; one aimed at the crosshair must not.
	var muzzle := Vector3(1.4, 0.0, 0.0)
	var target := Vector3(0.0, 0.0, -120.0)
	var kick := g.fire("R", muzzle, target)
	_ok(kick != Vector3.ZERO, "the right palm fired")
	_ok(kick.z > 0.0, "and it pushed the suit backwards (recoil %.2f m/s)" % kick.length())

	var live := 0
	var b0 = null
	for b in g._pool:
		if b.live:
			live += 1
			b0 = b
	_ok(live == 1, "exactly one bolt is in the air")

	# Fly it and see where it ends up relative to the sight line.
	var start: Vector3 = b0.node.position
	for i in 40:
		g._physics_process(STEP)
	var travelled: Vector3 = b0.node.position - start
	var to_target := (target - muzzle).normalized()
	var along := travelled.normalized().dot(to_target)
	_ok(along > 0.999, "the bolt flies at the crosshair, not out of the palm (alignment %.4f)" % along)
	_ok(travelled.length() > 60.0, "and it is quick: %.0f m in a third of a second" % travelled.length())

	# The hand has to cool down, or a held button is a machine gun. Checked on a FRESH
	# repulsor, because the flight above already burned more than a cooldown's worth of time.
	var g2 := Repulsors.new()
	root.add_child(g2)
	g2.build()
	g2.fire("R", muzzle, target)
	var again := g2.fire("R", muzzle, target)
	_ok(again == Vector3.ZERO, "the same hand cannot fire again immediately")
	var other := g2.fire("L", muzzle, target)
	_ok(other != Vector3.ZERO, "but the other hand can — alternating doubles the rate")

	# Charge drains and comes back. Measured on the fresh one, which has just fired twice.
	var before: float = g2.charge["R"]
	for i in 120:
		g2._physics_process(STEP)
	_ok(g2.charge["R"] > before, "charge recovers (%.2f -> %.2f in a second)" % [before, g2.charge["R"]])

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
