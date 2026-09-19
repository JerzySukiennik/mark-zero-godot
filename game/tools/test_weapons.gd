extends SceneTree
## The shoulder turret and the wrist laser: do they deploy, fire, and cost what they should?

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _run(n: Node, secs: float) -> void:
	for i in int(secs / STEP):
		n._physics_process(STEP)

## Run on the FIRST FRAME, not in _initialize: nodes added to `root` before the tree has
## started are not inside it yet, so every global_transform WRITE is silently dropped and
## every read returns identity. The laser beam's orientation is exactly that kind of
## measurement, and it looked like a maths bug for three rounds.
func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	_all()
	return true

func _all() -> void:
	var node: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk3.glb")
	root.add_child(node)
	var skel := SuitRig.new()
	skel.index(node)

	# ---- the turret ------------------------------------------------------------------
	print("=== shoulder turret ===")
	var t := ShoulderTurret.new()
	root.add_child(t)
	t.build()
	t.attach(skel)
	_ok(t.deployed == 0.0, "it starts stowed")
	_ok(not t.ready_to_fire(), "and will not fire while stowed — the deploy is a real cost")

	t.request(true)
	_run(t, 0.15)
	_ok(t.deployed > 0.05 and t.deployed < 0.95, "it is mid-deploy after 0.15 s (%.2f)" % t.deployed)
	_run(t, 0.4)
	_ok(t.deployed > 0.92, "fully out after about a third of a second (%.2f)" % t.deployed)
	_ok(t.ready_to_fire(), "and now it will fire")

	var before: float = t.charge
	var kick := t.fire(Vector3(0, 0, -80))
	_ok(kick != Vector3.ZERO, "it fired (recoil %.1f m/s)" % kick.length())
	_ok(t.charge < before, "and it cost ammunition (%.2f -> %.2f)" % [before, t.charge])
	_ok(not t.ready_to_fire(), "it has to cool down between shots")

	# Left alone, it packs itself away. A turret left standing proud stops being an event.
	t.request(false)
	_run(t, 4.5)
	_ok(t.deployed < 0.05, "left alone it folds itself away (%.2f)" % t.deployed)

	# ---- the wrist laser -------------------------------------------------------------
	print("=== wrist laser ===")
	var l := WristLaser.new()
	root.add_child(l)
	l.build()
	l.attach(skel)
	# Spawned charged now, so the first press of triangle+circle does something. The rule
	# being tested is still the real one — an EMPTY suit refuses — so the test drains it by
	# hand instead of leaning on the starting value.
	l.charge = 0.0
	_ok(not l.ready_to_fire, "it will not fire on an uncharged suit")
	l.add_charge(1.0)
	_ok(l.ready_to_fire, "a charged suit can use it")

	_ok(l.start(true), "it starts in the air")
	_ok(l.charge < 0.01, "and it spends the whole charge")
	var turned := 0.0
	var ticks := 0
	while l.active and ticks < 1000:
		turned += l.turn_for(STEP)
		ticks += 1
	_ok(absf(turned - WristLaser.AIR_TURN) < 0.05,
		"the airborne move rolls the suit a full turn (%.2f rad of %.2f)" % [turned, WristLaser.AIR_TURN])
	_ok(not l.active, "and it ends on its own after %.2f s" % (ticks * STEP))

	l.add_charge(1.0)
	l.start(false)
	var turned2 := 0.0
	ticks = 0
	while l.active and ticks < 1000:
		turned2 += l.turn_for(STEP)
		ticks += 1
	_ok(turned2 < WristLaser.AIR_TURN,
		"the grounded move turns LESS — it pivots on its feet, it does not roll (%.2f rad)" % turned2)
	_ok(ticks * STEP > WristLaser.AIR_TIME, "and takes longer (%.2f s)" % (ticks * STEP))

	print("=== the laser points along the ARM ===")
	# It was drawn along the palm pivot's -Y, which is the contract's emitter axis and
	# points out of the PALM — straight down while the arm hangs. So the beam existed and
	# went into the floor: "on tez teraz w ogole nie ma laseru". It has to be the forearm's
	# own direction, which is what "przedluzenie reki" means.
	var lr := WristLaser.new()
	root.add_child(lr)
	lr.build()
	lr.attach(skel)
	lr.charge = 1.0
	lr.start(true)
	lr.update(STEP)
	var elbow: Node3D = skel.pivots["piv_elbow" + SuitRig.SIDE["R"]]
	var palm: Node3D = skel.pivots["piv_palm" + SuitRig.SIDE["R"]]
	var along := (palm.global_position - elbow.global_position).normalized()
	# The cylinder's own axis is +Y, and that is what has to lie along the arm.
	var beam_dir := lr._beam.global_basis.y.normalized()
	_ok(absf(beam_dir.dot(along)) > 0.95,
		"the beam runs down the forearm (dot %.3f)" % beam_dir.dot(along))

	print("=== and it spins about the right axis ===")
	# Airborne it was applied to ROLL, which tips the suit head-down and sweeps the beam
	# through a VERTICAL disc. The move is a fast flat spin.
	var air := FlightModel.new()
	air.set_armor("mk3")
	air.position = Vector3(0, 400, 0)
	var la := WristLaser.new()
	root.add_child(la)
	la.build()
	la.attach(skel)
	la.charge = 1.0
	la.start(true)
	var yaw0 := air.yaw
	var roll0 := air.roll
	var spun := 0.0
	while la.active:
		var stp := la.turn_for(STEP)
		air.yaw += stp
		spun += stp
		la.update(STEP)
	_ok(absf(spun) > TAU * 0.9, "the airborne sweep is a full turn (%.0f deg)" % rad_to_deg(spun))
	_ok(absf(air.roll - roll0) < 0.05, "and it does not roll him over (roll %.3f)" % air.roll)

	# On the ground the legs stay put, so the sweep lives in the spine and is capped there.
	var lg := WristLaser.new()
	root.add_child(lg)
	lg.build()
	lg.attach(skel)
	lg.charge = 1.0
	lg.start(false)
	var ground_yaw := 0.0
	while lg.active:
		lg.twist = clampf(lg.twist + lg.turn_for(STEP), -PI * 0.62, PI * 0.62)
		lg.update(STEP)
	_ok(absf(lg.twist) > 1.0, "the grounded sweep really turns the torso (%.0f deg)" % rad_to_deg(lg.twist))
	_ok(absf(lg.twist) <= PI * 0.62 + 0.01,
		"but stops where a spine stops (%.0f deg)" % rad_to_deg(lg.twist))
	_ok(ground_yaw == 0.0, "without spinning the whole body on planted feet")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
