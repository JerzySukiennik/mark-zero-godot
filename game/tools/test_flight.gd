extends SceneTree
## Does the ported flight model behave like the one it came from?
##
## The browser build's numbers are written into the expectations below. A port that compiles
## proves nothing; a port that stops from 150 m/s in the same 0.85 s is the same aircraft.

## Loaded explicitly rather than through `class_name`: the global class registry is built
## by the editor's import pass, and a headless `--script` run cannot count on it being there.
const FlightModelS := preload("res://scripts/flight/flight_model.gd")

const SuitSpecsS := preload("res://scripts/flight/specs.gd")

const STEP := 1.0 / 120.0

var bad := 0

func _ok(cond: bool, msg: String) -> void:
	if not cond:
		bad += 1
	print(("  ok    " if cond else "  FAIL  ") + msg)

func _run(m, cmd: Dictionary, secs: float, stop_below := -1.0) -> float:
	var t := 0.0
	while t < secs:
		m.step(STEP, cmd)
		t += STEP
		if stop_below >= 0.0 and m.speed < stop_below:
			break
	return t

func _cmd(d := {}) -> Dictionary:
	var c := { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0,
		look = Vector2.ZERO, roll = 0.0, boost = false }
	for k in d:
		c[k] = d[k]
	return c

func _initialize() -> void:
	print("=== flight model port ===")
	var m: RefCounted = FlightModelS.new()
	m.set_armor("mk3")
	_ok(m.spec != null and m.spec.name == "MARK III", "the spec table loaded (%s, top speed %d)" % [m.spec.name, m.spec.top_speed])

	# --- braking, the number we fought hardest for
	m.position = Vector3(0, 300, 0); m.velocity = Vector3(0, 0, -150); m.basis_ = Basis.IDENTITY
	var t1 := _run(m, _cmd({ retro = 1.0 }), 8.0, 3.0)
	_ok(t1 < 1.3, "150 m/s to a stop in %.2f s   (browser build: 0.85 s)" % t1)

	m.position = Vector3(0, 300, 0); m.velocity = Vector3(0, 0, -60); m.basis_ = Basis.IDENTITY
	var t2 := _run(m, _cmd({ retro = 1.0 }), 8.0, 3.0)
	_ok(t2 < 0.6, "60 m/s to a stop in %.2f s   (browser build: 0.34 s)" % t2)

	# --- the brake must never overshoot into reverse on its own
	m.position = Vector3(0, 300, 0); m.velocity = Vector3(0, 0, -100); m.basis_ = Basis.IDENTITY
	_run(m, _cmd({ retro = 1.0 }), 1.6)
	_ok(m.velocity.z > 0.0, "held retro then flies backwards (vz %.1f) — by design, not a bug" % m.velocity.z)

	# --- fall arrest
	m.position = Vector3(0, 300, 0); m.velocity = Vector3(0, -70, 0); m.basis_ = Basis.IDENTITY
	var y0: float = m.position.y
	var t4 := 0.0
	while t4 < 4.0 and m.velocity.y < -0.5:
		m.step(STEP, _cmd({ vertical = 1.0 })); t4 += STEP
	_ok(t4 < 1.0, "a 70 m/s fall is arrested in %.2f s, after %.1f m" % [t4, y0 - m.position.y])

	# --- and then climbs SLOWLY, which is the thing that was wrong before the governor
	var y1: float = m.position.y
	_run(m, _cmd({ vertical = 1.0 }), 2.0)
	var climb: float = (m.position.y - y1) / 2.0
	_ok(climb < 18.0, "then climbs at %.1f m/s   (was 33 before the governor)" % climb)

	# --- level flight plus up-thrust must not be a launch
	m.position = Vector3(0, 300, 0); m.velocity = Vector3(0, 0, -120); m.basis_ = Basis.IDENTITY
	_run(m, _cmd({ thrust = 1.0, vertical = 1.0 }), 1.0)
	_ok(m.velocity.y < 18.0, "level flight + up = %.1f m/s of climb, not a rocket" % m.velocity.y)

	# --- the throttle is analog, which is the whole point of a pad
	m.position = Vector3(0, 300, 0); m.velocity = Vector3.ZERO; m.basis_ = Basis.IDENTITY
	_run(m, _cmd({ thrust = 0.45 }), 2.0)
	var half: float = m.speed
	m.position = Vector3(0, 300, 0); m.velocity = Vector3.ZERO; m.basis_ = Basis.IDENTITY
	_run(m, _cmd({ thrust = 1.0 }), 2.0)
	var full: float = m.speed
	_ok(half < full * 0.75 and half > 1.0, "45%% throttle gives %.0f m/s against %.0f at full" % [half, full])

	# --- it actually reaches its stated top speed, eventually
	m.position = Vector3(0, 2000, 0); m.velocity = Vector3.ZERO; m.basis_ = Basis.IDENTITY
	_run(m, _cmd({ thrust = 1.0 }), 40.0)
	_ok(m.speed > m.spec.top_speed * 0.75, "40 s at full throttle reaches %.0f m/s (target %d)" % [m.speed, m.spec.top_speed])

	# --- hands off the stick: the suit stops itself (see AUTO_BRAKE in suit_pilot.gd)
	m.position = Vector3(0, 300, 0); m.velocity = Vector3(0, 0, -200); m.basis_ = Basis.IDENTITY
	var t6 := 0.0
	while t6 < 12.0 and m.speed > 3.0:
		# What suit_pilot asks for with the stick centred: eased-in retro, not full.
		var r: float = clampf((m.speed - 1.5) / 12.0, 0.0, 1.0) * 0.55
		m.step(STEP, _cmd({ retro = r, brake_only = true }))
		t6 += STEP
	_ok(t6 < 6.0, "hands off the stick, 200 m/s coasts to a stop in %.1f s" % t6)
	_ok(m.velocity.z < 30.0, "and it does not sail off backwards (vz %.1f)" % m.velocity.z)

	# --- every armour loads and flies
	for id in SuitSpecsS.order:
		var n: RefCounted = FlightModelS.new()
		n.set_armor(id)
		n.position = Vector3(0, 500, 0); n.velocity = Vector3.ZERO
		_run(n, _cmd({ thrust = 1.0 }), 3.0)
		_ok(n.speed > 5.0, "%s accelerates (%.0f m/s in 3 s)" % [n.spec.name, n.speed])

	print("=== holding altitude under power ===")
	# Thrust is a BODY-frame vector along -Z, so flying level put all of it horizontal and
	# nothing held the suit up — it sank across the whole plate under full power, and it
	# sank hardest banked into a turn, when a body-frame lift loses its vertical component.
	for bank: String in ["level", "banked"]:
		var a := FlightModel.new()
		a.set_armor("mk3")
		a.position = Vector3(0, 400, 0)
		var lat := 0.0 if bank == "level" else 1.0
		for i in 1200:                                   # ten seconds of cruising
			a.step(STEP, { thrust = 0.8, retro = 0.0, lateral = lat, vertical = 0.0,
				walk = Vector2.ZERO, look = Vector2.ZERO, roll = 0.0, boost = false,
				aiming = false, firing = false })
		var drop := 400.0 - a.position.y
		_ok(drop < 25.0, "flying %s for 10 s loses little height (%.0f m)" % [bank, drop])
		_ok(a.speed > 40.0, "and it is actually flying (%.0f m/s)" % a.speed)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
