extends Node
## The fight. Run as a SCENE, never with `--script`:
##   godot --headless --path . res://tools/combat_test.tscn
##
## It has to be a scene for two reasons this project keeps relearning: `--script` has no
## autoloads, and the enemies are CharacterBody3Ds whose whole job depends on a live
## physics world. A headless run with neither would measure nothing and pass.

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

## A stand-in for the hero: something in the player group that can be hurt and counted.
class Dummy:
	extends Node3D
	var hurt := 0.0
	var hits := 0
	func _ready() -> void:
		add_to_group("player")
		add_to_group("hittable")
		# The same hurtbox the real heroes carry — without it a ray has nothing to find,
		# which is exactly the bug this test caught.
		add_child(Hurtbox.new(self, 0.6, 2.0))
	func take_hit(amount: float, _from: Vector3, _kind := "") -> void:
		hurt += amount
		hits += 1

var _floor: StaticBody3D

## Repulsors live under the test node like everything else here.
func root_add(n: Node) -> void:
	add_child(n)

func _make_floor() -> void:
	_floor = StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	_floor.add_child(cs)
	add_child(_floor)
	_floor.global_position = Vector3(0, -1, 0)

func _spawn(kind: String, at: Vector3, guns: Gunfire) -> Enemy:
	var e := Enemy.new()
	e.setup(kind, guns)
	add_child(e)
	e.global_position = at
	return e

func _tick(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	# SEEDED. The thugs decide whether to press, hold or run on a die roll now, which is
	# the behaviour Jurek asked for and is death to a test with a fixed threshold — the
	# same run passes and fails depending on the weather. A fixed seed keeps the randomness
	# being exercised while making the result reproducible.
	seed(20260920)
	_make_floor()
	var guns := Gunfire.new()
	add_child(guns)
	await get_tree().physics_frame

	print("=== everyone in the roster stands up ===")
	var built := 0
	for k: String in EnemyKinds.names():
		var e := _spawn(k, Vector3(built * 6.0 - 20.0, 1.0, -40.0), guns)
		await get_tree().physics_frame
		if e.skel != null and e.hp > 0.0:
			built += 1
	_ok(built == EnemyKinds.names().size(),
		"all %d kinds build with a rig (%d)" % [EnemyKinds.names().size(), built])
	for c in get_children():
		if c is Enemy:
			c.queue_free()
	await _tick(2)

	print("=== fists reach you ===")
	var hero := Dummy.new()
	add_child(hero)
	hero.global_position = Vector3(0, 1, 0)
	var thug := _spawn("brawler", Vector3(0, 1, -14.0), guns)
	# CLOSEST APPROACH, not final position. They hold, circle and back off on purpose now —
	# "oni nie powinni być tak chętnie gonić tego" — so where a man happens to be standing
	# when the clock runs out says nothing. Whether he ever got to you does.
	# Fifteen seconds, because he re-decides every second or two and is allowed to spend
	# some of them holding his ground. What is being tested is that he DOES come, not that
	# he comes immediately.
	var closest := 1e9
	for i in 1800:
		await get_tree().physics_frame
		closest = minf(closest, thug.global_position.distance_to(hero.global_position))
	_ok(closest < 3.0, "a brawler does close on you (got within %.1f m)" % closest)
	_ok(hero.hits > 0, "and hits you when he gets there (%d times, %.0f damage)" % [hero.hits, hero.hurt])
	thug.queue_free()
	await _tick(2)

	print("=== and so do rifles ===")
	hero.hits = 0
	hero.hurt = 0.0
	var shooter := _spawn("rifle", Vector3(0, 1, -34.0), guns)
	# Long enough for two volleys. They used to fire continuously at their own rate; now a
	# burst is followed by five seconds of nothing, so a three-second window could sample
	# the gap and read as a rifleman who never fires.
	await _tick(900)
	_ok(hero.hits > 0, "a rifleman hits you from range (%d rounds, %.0f damage)" % [hero.hits, hero.hurt])
	shooter.queue_free()
	await _tick(2)

	print("=== they can be killed ===")
	var mark := _spawn("brawler", Vector3(30, 1, 0), guns)
	await get_tree().physics_frame
	var shots := 0
	while mark.state != Enemy.DOWN and shots < 40:
		mark.take_hit(Repulsors.DAMAGE, Vector3(40, 1, 0), "repulsor")
		shots += 1
	_ok(mark.state == Enemy.DOWN, "a thug drops to repulsor fire (%d bolts)" % shots)
	_ok(shots <= 4, "and it does not take a magazine (%d)" % shots)

	var big := _spawn("brute", Vector3(34, 1, 0), guns)
	await get_tree().physics_frame
	var big_shots := 0
	while big.state != Enemy.DOWN and big_shots < 200:
		big.take_hit(Repulsors.DAMAGE, Vector3(44, 1, 0), "repulsor")
		big_shots += 1
	_ok(big.state == Enemy.DOWN, "so does a brute, eventually (%d bolts)" % big_shots)
	# THE BIG ONE IS A DECISION. If he folds in about the same number of shots as a thug
	# he is just a thug wearing a bigger model.
	_ok(big_shots >= shots * 3,
		"but he costs far more (%d against %d)" % [big_shots, shots])
	mark.queue_free()
	big.queue_free()
	await _tick(2)

	print("=== webbing, and why the big ones are worth it ===")
	var glue := _spawn("knifer", Vector3(-30, 1, 0), guns)
	await get_tree().physics_frame
	glue.web_hit(1.0)
	_ok(glue.state == Enemy.WEBBED, "one web glues an ordinary thug")

	var tough := _spawn("brute", Vector3(-34, 1, 0), guns)
	await get_tree().physics_frame
	tough.web_hit(1.0)
	_ok(tough.state != Enemy.WEBBED, "the same web does NOT glue a brute")
	var need: int = EnemyKinds.spec("brute")["web"]
	for i in need - 1:
		tough.web_hit(1.0)
	_ok(tough.state == Enemy.WEBBED, "it takes %d of them (Jurek's big ones)" % need)

	# And being glued has to actually stop him, or it is a colour change.
	var was := tough.global_position
	tough.velocity = Vector3(8, 0, 0)
	await _tick(90)
	_ok(tough.global_position.distance_to(was) < 1.0,
		"a webbed man stays put (%.2f m)" % tough.global_position.distance_to(was))
	# And it wears off, faster on him than on anyone else.
	_ok(EnemyKinds.spec("brute")["web_decay"] > 1.0,
		"and it rots off a brute faster than off a thug")

	print("=== Spider-Man's hands ===")
	var fist := SpiderCombat.new()
	var body := SpiderModel.new()
	body.position = Vector3(-60, 1, 0)
	body.grounded = true
	var mark2 := _spawn("brawler", Vector3(-60, 1, -9.0), guns)
	await get_tree().physics_frame

	var base := {
		walk = Vector2.ZERO, facing = Vector3(0, 0, -1),
		light = false, heavy = false, heavy_down = false, dodge = false,
	}
	# TRIANGLE reaches. The whole point of the primitive attack is that it closes the gap
	# itself — a strike that only works when you are already touching him is a strike
	# nobody presses.
	var press := base.duplicate()
	press["light"] = true
	fist.update(1.0 / 120.0, body, press, get_tree())
	_ok(fist.state == SpiderCombat.ZIP, "triangle throws him at a man nine metres off")
	var hp0: float = mark2.hp
	for i in 90:
		fist.update(1.0 / 120.0, body, base, get_tree())
		body.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO, jump = false,
			aiming = false, release = false, wall_run = false }, Vector3.ZERO)
		await get_tree().physics_frame
	_ok(mark2.hp < hp0, "and it lands (%.0f -> %.0f hp)" % [hp0, mark2.hp])
	_ok(body.position.distance_to(mark2.global_position) < 6.0,
		"arriving next to him (%.1f m)" % body.position.distance_to(mark2.global_position))

	# HELD SQUARE launches. Tapped it must NOT — the hold is measured so a quick tap is a
	# punch and never a launcher by accident.
	# A FRESH man, somewhere clean. The one from the zip above is down to 2 hp, and a
	# launcher hits before it lifts — so it killed him and then correctly refused to
	# launch a corpse, which reads in the log exactly like the launcher not working.
	mark2.queue_free()
	await get_tree().physics_frame
	body.position = Vector3(-90, 1, 0)
	var mark3 := _spawn("brawler", body.position + Vector3(0, 0, -2.0), guns)
	await get_tree().physics_frame
	var hold := base.duplicate()
	hold["heavy"] = true
	hold["heavy_down"] = true
	fist.update(1.0 / 120.0, body, hold, get_tree())
	hold["heavy_down"] = false
	_ok(fist.state == SpiderCombat.FREE, "a tap of square is not a launcher")
	for i in 40:
		fist.update(1.0 / 120.0, body, hold, get_tree())
		if fist.state == SpiderCombat.LAUNCH:
			break
	_ok(fist.state == SpiderCombat.LAUNCH, "holding it is (after %.2f s)" % SpiderCombat.HOLD_TIME)
	# WHICHEVER man it picked, not the one the test happened to spawn last: the strike
	# chooses the nearest in front, and after the zip above that is the first one.
	var flung: Enemy = fist.target
	_ok(flung != null and flung.velocity.y > 5.0,
		"and the man goes UP (%.0f m/s)" % (flung.velocity.y if flung != null else 0.0))
	_ok(flung != null and flung.is_juggled(), "and hangs there rather than dropping straight back")

	# CIRCLE dodges, and it costs the enemy most of a hit.
	var before := body.position
	var duck := base.duplicate()
	duck["dodge"] = true
	duck["walk"] = Vector2(1.0, 0.0)
	fist.state = SpiderCombat.FREE
	fist.update(1.0 / 120.0, body, duck, get_tree())
	_ok(fist.state == SpiderCombat.DODGE, "circle dodges")
	_ok(fist.damage_scale() < 0.5, "and soaks most of a hit while it lasts (%.0f%%)"
		% (fist.damage_scale() * 100.0))
	# Past the full dodge, which is 0.34 s — a window sampled at 0.25 s catches it still
	# running and reads as a dodge that never ends.
	for i in int(SpiderCombat.DODGE_TIME * 120.0) + 20:
		fist.update(1.0 / 120.0, body, base, get_tree())
		body.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO, jump = false,
			aiming = false, release = false, wall_run = false }, Vector3.ZERO)
	_ok(body.position.distance_to(before) > 1.5,
		"moving him out of the way (%.1f m)" % body.position.distance_to(before))
	_ok(fist.damage_scale() == 1.0, "and it ends")

	print("=== warnings before the shot ===")
	# A warning that arrives with the bullet is not a warning. The rifleman aims first, and
	# says so, which is what the spider-sense over Spider-Man's head is reading.
	var teller := _spawn("rifle", Vector3(40, 1, -30.0), guns)
	hero.global_position = Vector3(40, 1, 0)
	await get_tree().physics_frame
	var saw_tell := false
	var tell_before_shot := true
	var rounds_before := hero.hits
	for i in 700:
		await get_tree().physics_frame
		if teller.telegraphing() > 0.0:
			saw_tell = true
		if hero.hits > rounds_before and not saw_tell:
			tell_before_shot = false
			break
		if hero.hits > rounds_before:
			break
	_ok(saw_tell, "he takes aim visibly before firing")
	_ok(tell_before_shot, "and the warning comes BEFORE the round does")
	teller.queue_free()
	await _tick(2)

	print("=== falling over ===")
	var doomed := _spawn("brawler", Vector3(70, 1, 0), guns)
	await get_tree().physics_frame
	var upright: float = doomed.rig.rotation.x
	while doomed.state != Enemy.DOWN:
		doomed.take_hit(50.0, Vector3(78, 1, 0), "test")
	for i in int(Enemy.TOPPLE_TIME * 120.0) + 30:
		await get_tree().physics_frame
		if not is_instance_valid(doomed):
			break
	if is_instance_valid(doomed):
		_ok(absf(doomed.rig.rotation.x - upright) > 1.2,
			"a dead man goes over (%.0f deg)" % rad_to_deg(absf(doomed.rig.rotation.x)))
		_ok(doomed.rig.position.y < -0.4,
			"and lies on the plate rather than on his heels (%.2f m)" % doomed.rig.position.y)

	print("=== the shot bends towards him ===")
	# Bullet magnetism, the technique every console shooter has used since Halo. A bolt
	# fired a few degrees wide must still land, because at two hundred metres up a man is
	# a few pixels and a thumbstick cannot do better than "a few degrees wide".
	var mark4 := _spawn("brawler", Vector3(100, 1, -40.0), guns)
	await get_tree().physics_frame
	var rep := Repulsors.new()
	root_add(rep)
	rep.build()
	var start := Vector3(100, 1.2, 0)
	# Deliberately off: aimed a metre and a half to the side of a man forty metres away.
	var wide := (mark4.global_position + Vector3(1.5, 0.9, 0)) - start
	var hp_before: float = mark4.hp
	rep.fire("R", start, start + wide.normalized() * 60.0, mark4)
	for i in 120:
		rep._physics_process(1.0 / 120.0)
		await get_tree().physics_frame
		if mark4.hp < hp_before:
			break
	_ok(mark4.hp < hp_before, "a shot aimed wide still lands (%.0f -> %.0f hp)" % [hp_before, mark4.hp])

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
