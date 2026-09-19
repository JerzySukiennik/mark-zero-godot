extends SceneTree
## The Iron Spider's four back legs.
##
## They are the one part of the rig no authored pose mentions, so they are also the one
## part that will silently sit at rest forever if the wiring is wrong — and a folded leg
## looks exactly like a correctly folded leg. Hence measuring where the talons actually end
## up rather than trusting that something was called.

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

## World position of one leg's talon, which is the thing a player actually sees move.
func _talon(skel: SuitRig, leg: String) -> Vector3:
	var n := "piv_leg%s3" % leg
	return (skel.pivots[n] as Node3D).global_position if skel.has_pivot(n) else Vector3.ZERO

func _run(legs: SpiderLegs, skel: SuitRig, want: bool, secs: float) -> void:
	for i in int(secs / STEP):
		legs.drive(STEP, want, skel)
		skel.update_pose(STEP)

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	var node: Node3D = SuitLoaderS.load_suit("res://assets/suits/ironspider.glb")
	if node == null:
		print("FAIL  no ironspider.glb"); quit(1); return true
	root.add_child(node)
	var skel := SuitRig.new(); skel.index(node)
	var legs := SpiderLegs.new()

	print("=== the legs exist ===")
	var have := 0
	for leg: String in SpiderLegs.ORDER:
		for seg in 3:
			if skel.has_pivot("piv_leg%s%d" % [leg, seg + 1]):
				have += 1
	_ok(have == 12, "twelve leg pivots are in the model (%d)" % have)

	skel.set_pose("stand")
	_run(legs, skel, false, 0.5)
	var folded := _talon(skel, "A")
	_ok(legs.out < 0.01, "they start folded")

	print("=== deploying ===")
	_run(legs, skel, true, SpiderLegs.OUT_TIME + 0.4)
	var deployed := _talon(skel, "A")
	_ok(legs.out >= 0.999, "they reach full deploy")
	_ok(folded.distance_to(deployed) > 0.15,
		"and the talon actually MOVED (%.2f m)" % folded.distance_to(deployed))
	# Out, not in: a deployed leg reaches away from the spine, not across it.
	_ok(absf(deployed.x) > absf(folded.x),
		"outward, not across the back (|x| %.3f -> %.3f)" % [absf(folded.x), absf(deployed.x)])

	print("=== the stagger ===")
	# Partway through the swing, leg A must be further along than leg D. Four legs moving in
	# perfect lockstep read as one object, which is the whole reason the stagger exists.
	_run(legs, skel, false, 1.0)
	_run(legs, skel, true, SpiderLegs.OUT_TIME * 0.45)
	var a_moved := folded.distance_to(_talon(skel, "A"))
	var d_folded := Vector3.ZERO
	# Measure D against its own folded position, not A's.
	var legs2 := SpiderLegs.new()
	var skel2 := SuitRig.new(); skel2.index(node)
	_run(legs2, skel2, false, 0.5)
	d_folded = _talon(skel2, "D")
	_ok(a_moved > d_folded.distance_to(_talon(skel, "D")),
		"leg A leads leg D through the swing")

	print("=== folding back ===")
	_run(legs, skel, true, 1.0)
	_run(legs, skel, false, SpiderLegs.IN_TIME + 0.05)
	_ok(legs.out <= 0.001, "they fold all the way back")
	_ok(SpiderLegs.IN_TIME < SpiderLegs.OUT_TIME,
		"and tidying up is quicker than showing off")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
	return true
