extends Node
func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(400, 2, 400)
	cs.shape = box; floor_body.add_child(cs); add_child(floor_body)
	floor_body.global_position = Vector3(0, -1, 0)

	var e := Enemy.new()
	e.setup("brawler", null)
	add_child(e)
	e.global_position = Vector3(100, 1, -40)
	await get_tree().physics_frame

	var rep := Repulsors.new()
	add_child(rep)
	rep.build()
	var start := Vector3(100, 1.2, 0)
	var wide := (e.global_position + Vector3(1.5, 0.9, 0)) - start
	print("[m] aim offset = %.2f deg" % rad_to_deg(wide.normalized().angle_to((e.global_position + Vector3(0,0.9,0) - start).normalized())))
	var kick := rep.fire("R", start, start + wide.normalized() * 60.0, e)
	print("[m] fired=%s  pool live=%d" % [kick != Vector3.ZERO, rep._pool.filter(func(b): return b.live).size()])
	var closest := 1e9
	for i in 200:
		await get_tree().physics_frame
		for b in rep._pool:
			if b.live:
				closest = minf(closest, b.node.global_position.distance_to(e.global_position + Vector3(0, 0.9, 0)))
	print("[m] closest approach = %.2f m   hp = %.0f" % [closest, e.hp])
	get_tree().quit(0)
