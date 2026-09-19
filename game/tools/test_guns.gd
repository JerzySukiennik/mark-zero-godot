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

	print("=== the magazine ===")
	# Jurek's rule, in numbers: sixteen taps empties it, an empty hand is LOCKED until it
	# has refilled all the way, and stopping short lets you carry straight on.
	var mag := Repulsors.new()
	root.add_child(mag)
	mag.build()

	var fired := 0
	for i in 40:
		mag._cool["R"] = 0.0
		if mag.ready_to_fire("R"):
			mag.fire("R", Vector3.ZERO, Vector3(0, 0, -50))
			fired += 1
	_ok(fired == Repulsors.SHOTS, "a full hand gives exactly %d shots (%d)" % [Repulsors.SHOTS, fired])
	_ok(mag.locked["R"], "and then locks out")
	_ok(mag.shots_left("R") == 0, "with nothing left on the gauge")

	# Half a reload is not enough — that is the whole point of the lockout.
	var half := int(Repulsors.SHOTS * Repulsors.RELOAD_PER_SHOT * 0.5 / STEP)
	for i in half:
		mag._physics_process(STEP)
	mag._cool["R"] = 0.0
	_ok(not mag.ready_to_fire("R"), "half reloaded is still locked (%d shots showing)" % mag.shots_left("R"))
	for i in half + 200:
		mag._physics_process(STEP)
	mag._cool["R"] = 0.0
	_ok(mag.ready_to_fire("R") and not mag.locked["R"], "full again, and it fires")

	# Stopping short of empty must NOT lock, and must top itself up a shot at a time.
	for i in 4:
		mag._cool["R"] = 0.0
		mag.fire("R", Vector3.ZERO, Vector3(0, 0, -50))
	_ok(not mag.locked["R"], "spending four shots does not lock anything")
	_ok(mag.shots_left("R") == Repulsors.SHOTS - 4, "and the gauge counts down (%d)" % mag.shots_left("R"))
	for i in int(Repulsors.RELOAD_PER_SHOT * 2.0 / STEP):
		mag._physics_process(STEP)
	_ok(mag.shots_left("R") == Repulsors.SHOTS - 2,
		"two shots come back in two reload times (%d)" % mag.shots_left("R"))
	mag._cool["R"] = 0.0
	_ok(mag.ready_to_fire("R"), "and it stayed usable the whole time")

	print("=== mashing ===")
	# The repulsors are designed to be tapped as fast as the player can manage. A press that
	# arrived during the cooldown used to be DROPPED, so mashing above the fire rate lost
	# most of the taps and the button read as unresponsive. What matters is that a hand
	# fires at its cooldown rate under a faster stream of presses, rather than at the rate
	# the presses happen to line up with it.
	var mash := Repulsors.new()
	root.add_child(mash)
	mash.build()
	var shots_out := 0
	var seconds := 1.0
	# Twenty presses a second against a hand that can take about ten.
	var steps := int(seconds / STEP)
	var since := 0.0
	for i in steps:
		since += STEP
		var pressed := since >= 0.05
		if pressed:
			since = 0.0
		if pressed and mash.ready_to_fire("R"):
			mash.fire("R", Vector3.ZERO, Vector3(0, 0, -50))
			shots_out += 1
		mash._physics_process(STEP)
	var expected := int(seconds / Repulsors.COOLDOWN)
	_ok(shots_out >= expected - 2,
		"a second of mashing gets close to the fire rate (%d of a possible %d)" % [shots_out, expected])
	_ok(Repulsors.COOLDOWN <= 0.1, "and the rate is fast enough to be worth mashing (%.0f/s)"
		% (1.0 / Repulsors.COOLDOWN))

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
