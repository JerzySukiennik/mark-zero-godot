extends SceneTree
## The repulsor magazine readout: does the number on the glass match what the gun will do?
##
## Jurek: "czasem się bugguje wskaźnik ile jest strzałów (że pokazuje maks a nie chce
## strzelać)." Nothing was bugged. The readout rounded, and it ignored the lockout — so
## a magazine three quarters of a second from ready displayed sixteen of sixteen. This
## test exists so the strip can never claim a shot the gun will refuse.

const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _process(_d: float) -> bool:
	_all()
	return true

func _all() -> void:
	var g := Repulsors.new()
	root.add_child(g)
	g.build()

	print("=== the readout never promises a shot the gun will not take ===")
	# Empty it the way a player empties it: hold the trigger down and let the cooldown
	# pace the shots, one physics step at a time. Stepping by a whole cooldown at once
	# also hands the tank that much recharge, which is enough to keep it off the lockout
	# forever — the test measured the test rather than the gun.
	var taps := 0
	var t := 0.0
	while not g.locked["R"] and t < 6.0:
		if g.ready_to_fire("R"):
			g.fire("R", Vector3.ZERO, Vector3.FORWARD)
			taps += 1
		g._physics_process(STEP)
		t += STEP
	_ok(g.locked["R"], "holding the trigger locks it out, after %d shots" % taps)
	_ok(taps >= Repulsors.SHOTS - 1, "and that is a full magazine's worth (%d)" % taps)

	# THE WHOLE BUG, IN ONE LOOP. Every frame of the refill, the number on the glass is
	# checked against what the gun would actually do if the trigger were pulled.
	var worst_lie := 0
	var saw_full_while_locked := false
	var secs := 0.0
	while g.locked["R"] and secs < 40.0:
		g._physics_process(STEP)
		secs += STEP
		var shown: int = g.shots_left("R")
		# Asked of the GUN, not of the loop: the lockout clears inside a step, so on the
		# last pass round the strip is allowed to read full because by then it is true.
		# Checking the while condition instead failed a correct frame.
		if not g.ready_to_fire("R"):
			# It refuses to fire, so anything above zero overstates — but a bar that
			# fills is useful, so what is forbidden is specifically reading FULL.
			if shown >= Repulsors.SHOTS:
				saw_full_while_locked = true
			worst_lie = maxi(worst_lie, shown)

	_ok(not saw_full_while_locked,
		"and never shows a full magazine while it is still reloading")
	_ok(worst_lie <= Repulsors.SHOTS - 1,
		"the strip stays at most %d of %d until the gun is ready (peaked at %d)"
			% [Repulsors.SHOTS - 1, Repulsors.SHOTS, worst_lie])
	_ok(g.ready_to_fire("R"), "and it does come back")
	_ok(g.shots_left("R") == Repulsors.SHOTS,
		"reading a full %d once it has" % Repulsors.SHOTS)

	print("=== and it counts DOWN honestly ===")
	# Floor, not round: you have fifteen shots until you have sixteen.
	g.charge["L"] = 1.0
	g.locked["L"] = false
	g._cool["L"] = 0.0
	var before: int = g.shots_left("L")
	g.fire("L", Vector3.ZERO, Vector3.FORWARD)
	_ok(before == Repulsors.SHOTS, "a full tank reads %d" % Repulsors.SHOTS)
	_ok(g.shots_left("L") == Repulsors.SHOTS - 1,
		"and one shot takes exactly one pip off it (%d)" % g.shots_left("L"))

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
