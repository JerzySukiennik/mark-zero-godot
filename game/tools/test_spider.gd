extends SceneTree
## Spider-Man's own body: the stances, the run, and hanging off one arm.
##
## He spent several rounds wearing the armour's poses, which describe an aircraft. The
## things asserted here are the ones that make him a different character rather than a
## reskin: he is never straight, the run is a run and not a march, and a swing hangs off
## the arm that is actually holding the web.

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _fresh() -> Array:
	var n: Node3D = SuitLoaderS.load_suit("res://assets/suits/ironspider.glb")
	root.add_child(n)
	var r := SuitRig.new(); r.index(n)
	return [n, r, SpiderPoses.new(), SpiderModel.new()]

func _run(bits: Array, hands: Dictionary, secs: float, walk := Vector2.ZERO) -> void:
	var r: SuitRig = bits[1]
	var ps: SpiderPoses = bits[2]
	var m: SpiderModel = bits[3]
	for i in int(secs / STEP):
		m.step(STEP, { walk = walk, look = Vector2.ZERO, jump = false, aiming = false },
			Vector3.ZERO)
		ps.update(STEP, m, hands, r)
		r.update_pose(STEP)

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	var none := { "R": false, "L": false }

	print("=== standing ===")
	var b := _fresh()
	(b[3] as SpiderModel).position = Vector3(0, 1, 0)
	_run(b, none, 1.0)
	_ok((b[2] as SpiderPoses).current == "idle", "on the ground doing nothing, he idles (%s)" % (b[2] as SpiderPoses).current)
	# NEVER STRAIGHT. Iron Man stands to attention because servos hold him there; this is a
	# teenager, and a knee locked at zero is the single clearest way to get that wrong.
	var r: SuitRig = b[1]
	var hip: Vector3 = (r.pivots["piv_hipL"] as Node3D).global_position
	var knee: Vector3 = (r.pivots["piv_kneeL"] as Node3D).global_position
	var ankle: Vector3 = (r.pivots["piv_ankleL"] as Node3D).global_position
	var bend := rad_to_deg((knee - hip).angle_to(ankle - knee))
	_ok(bend > 8.0 and bend < 40.0, "and he stands COILED, not locked (%.0f deg at the knee)" % bend)

	print("=== running ===")
	var c := _fresh()
	(c[3] as SpiderModel).position = Vector3(0, 1, 0)
	_run(c, none, 3.0, Vector2(0, -1))
	var cm: SpiderModel = c[3]
	_ok((c[2] as SpiderPoses).current == "run", "pushing the stick, he runs (%s)" % (c[2] as SpiderPoses).current)
	_ok(cm.ground_speed > 8.0, "at a real speed (%.1f m/s)" % cm.ground_speed)
	var p0 := cm.stride_phase
	_run(c, none, 2.0, Vector2(0, -1))
	var hz := (cm.stride_phase - p0) / 2.0
	_ok(hz > 1.3 and hz < 2.8, "with a human cadence (%.2f cycles/s)" % hz)

	print("=== in the air ===")
	var d := _fresh()
	var dm: SpiderModel = d[3]
	dm.position = Vector3(0, 300, 0)
	_run(d, none, 1.0)
	_ok((d[2] as SpiderPoses).current == "fall", "off a web and off the ground, he falls (%s)" % (d[2] as SpiderPoses).current)

	print("=== hanging ===")
	var e := _fresh()
	var em: SpiderModel = e[3]
	em.position = Vector3(0, 300, 0)
	_run(e, { "R": true, "L": false }, 1.2)
	_ok((e[2] as SpiderPoses).current == "swing", "on a web, he swings (%s)" % (e[2] as SpiderPoses).current)

	# ONE ARM CARRIES HIM. Posing both is the difference between a man on a rope and a man
	# being lifted by the shoulders — and which arm it is must follow which web is attached.
	var er: SuitRig = e[1]
	var hips: Vector3 = (er.pivots["piv_hips"] as Node3D).global_position
	var right_hand: Vector3 = (er.pivots["piv_palm" + SuitRig.SIDE["R"]] as Node3D).global_position
	var left_hand: Vector3 = (er.pivots["piv_palm" + SuitRig.SIDE["L"]] as Node3D).global_position
	_ok(right_hand.y > left_hand.y + 0.08,
		"the arm holding the web is the one raised (R %.2f vs L %.2f)" % [right_hand.y - hips.y, left_hand.y - hips.y])

	var f := _fresh()
	(f[3] as SpiderModel).position = Vector3(0, 300, 0)
	_run(f, { "R": false, "L": true }, 1.2)
	var fr: SuitRig = f[1]
	var fh: Vector3 = (fr.pivots["piv_hips"] as Node3D).global_position
	var fr_hand: Vector3 = (fr.pivots["piv_palm" + SuitRig.SIDE["R"]] as Node3D).global_position
	var fl_hand: Vector3 = (fr.pivots["piv_palm" + SuitRig.SIDE["L"]] as Node3D).global_position
	_ok(fl_hand.y > fr_hand.y + 0.08, "and it swaps with the other web (L %.2f vs R %.2f)"
		% [fl_hand.y - fh.y, fr_hand.y - fh.y])

	print("=== he keeps his own poses ===")
	_ok(fr.pose_table == SpiderPoses.POSES,
		"the rig is reading SpiderPoses, not the armour's stances")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
	return true
