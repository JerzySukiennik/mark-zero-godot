extends SceneTree
## Does the armour WALK, and are the legs geared to the ground?
##
## The suit had no ground locomotion at all until now — _resolve_ground clamped Y and that
## was the whole of it. The two things worth asserting are that the stick is a gearbox
## rather than an on/off switch, and that the stride is advanced by DISTANCE. The second is
## what stops the feet skating, and it is invisible in a screenshot: a cycle driven by time
## looks perfectly correct standing still and slides the moment the speed changes.

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
const STEP := 1.0 / 120.0
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _cmd(walk: Vector2) -> Dictionary:
	return { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0, walk = walk,
		look = Vector2.ZERO, roll = 0.0, boost = false, aiming = false, firing = false }

## Runs the model on the ground for `secs` with the stick held at `walk`.
func _run(m: FlightModel, poses: Poses, skel: SuitRig, walk: Vector2, secs: float) -> void:
	for i in int(secs / STEP):
		var c := _cmd(walk)
		m.step(STEP, c)
		poses.update(STEP, m, c, skel)
		skel.update_pose(STEP)

func _initialize() -> void:
	var node: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk1.glb")
	root.add_child(node)
	var skel := SuitRig.new(); skel.index(node)
	var poses := Poses.new()
	var m := FlightModel.new()
	m.set_armor("mk1")
	m.position = Vector3(0, 1.0, 0)          # origin is at the soles, model is a metre up
	m.velocity = Vector3.ZERO

	print("=== on foot ===")
	_run(m, poses, skel, Vector2.ZERO, 0.5)
	_ok(m.grounded, "it is standing on the plate")
	_ok(poses.current == "stand", "and it is standing, not walking (%s)" % poses.current)

	# ---- the gearbox ------------------------------------------------------------------
	_run(m, poses, skel, Vector2(0, -0.25), 2.0)     # stick up is forward
	var slow := m.ground_speed
	_ok(absf(slow - FlightModel.WALK_SPEED * (0.25 / FlightModel.WALK_GEAR)) < 0.35,
		"a gentle push walks (%.2f m/s)" % slow)
	_ok(poses.current == "walk", "and the walk pose is up")

	_run(m, poses, skel, Vector2(0, -1.0), 3.0)
	var fastv := m.ground_speed
	_ok(absf(fastv - FlightModel.RUN_SPEED) < 0.4, "a full push runs (%.2f m/s)" % fastv)
	_ok(fastv > slow * 2.0, "and running is clearly faster than walking")

	# ---- the legs are geared to the ground ---------------------------------------------
	# Same DISTANCE at two different speeds must cost the same number of strides. A cycle
	# driven by time would need twice as many at half the speed.
	var p0 := m.stride_phase
	var d0 := m.position
	_run(m, poses, skel, Vector2(0, -1.0), 2.0)
	var run_cycles := m.stride_phase - p0
	var run_dist := m.position.distance_to(d0)

	p0 = m.stride_phase
	d0 = m.position
	_run(m, poses, skel, Vector2(0, -0.3), 4.0)
	var walk_cycles := m.stride_phase - p0
	var walk_dist := m.position.distance_to(d0)

	# CADENCE, not strides per metre. The stride LENGTHENS with speed, exactly as real legs
	# do, so strides per metre is supposed to differ between a walk and a run — what must
	# stay human is how often the legs actually swing. A fixed stride length gave four
	# cycles a second at a run, which reads as a blur rather than as running.
	var run_hz := run_cycles / 2.0
	var walk_hz := walk_cycles / 4.0
	_ok(run_hz > 1.4 and run_hz < 2.6, "running cadence is human (%.2f cycles/s)" % run_hz)
	_ok(walk_hz > 0.6 and walk_hz < 1.5, "so is walking (%.2f cycles/s)" % walk_hz)
	_ok(run_hz > walk_hz, "and a run cycles faster than a walk")
	# The anti-skate rule still holds: phase comes from distance, so a given stretch of
	# ground at a given speed always costs the same number of strides.
	_ok(absf(run_cycles - run_dist / FlightModel.stride_len(FlightModel.RUN_SPEED, FlightModel.RUN_SPEED)) < 0.1,
		"and the phase still comes from distance (%.2f cycles for %.1f m)" % [run_cycles, run_dist])

	# ---- letting go stops it ------------------------------------------------------------
	_run(m, poses, skel, Vector2.ZERO, 1.5)
	_ok(m.ground_speed < 0.05, "letting go stops it (%.3f m/s)" % m.ground_speed)
	_ok(poses.current == "stand", "and it settles back to standing")

	# ---- it stands UP -------------------------------------------------------------------
	m.pitch = 0.7
	m.roll = -0.5
	_run(m, poses, skel, Vector2.ZERO, 1.5)
	_ok(absf(m.pitch) < 0.02 and absf(m.roll) < 0.02,
		"a suit on its feet straightens up (pitch %.3f, roll %.3f)" % [m.pitch, m.roll])

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
