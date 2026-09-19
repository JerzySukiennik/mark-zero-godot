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
	await _tick(300)
	_ok(thug.global_position.distance_to(hero.global_position) < 6.0,
		"a brawler closes the distance (%.1f m)" % thug.global_position.distance_to(hero.global_position))
	_ok(hero.hits > 0, "and hits you when he gets there (%d times, %.0f damage)" % [hero.hits, hero.hurt])
	thug.queue_free()
	await _tick(2)

	print("=== and so do rifles ===")
	hero.hits = 0
	hero.hurt = 0.0
	var shooter := _spawn("rifle", Vector3(0, 1, -34.0), guns)
	await _tick(420)
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

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
