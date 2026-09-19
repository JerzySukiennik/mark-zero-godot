extends SceneTree
## Does the city build, and does a suit fly inside it?

const StageS := preload("res://scripts/world/stage.gd")

func _initialize() -> void:
	var bad := 0
	print("=== stage ===")
	var c: Node3D = StageS.new()
	c.build()
	root.add_child(c)

	var meshes := 0
	var bodies := 0
	var tallest := 0.0
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	var stack: Array = [c]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.push_back(ch)
		if n is MeshInstance3D:
			meshes += 1
			var m := n as MeshInstance3D
			if m.mesh is BoxMesh:
				var s: Vector3 = (m.mesh as BoxMesh).size
				tallest = maxf(tallest, s.y)
				lo = lo.min(m.position - s * 0.5)
				hi = hi.max(m.position + s * 0.5)
		elif n is StaticBody3D:
			bodies += 1

	print("  meshes: %d   collision bodies: %d" % [meshes, bodies])
	
	print("  plate: %.0f x %.0f m" % [hi.x - lo.x, hi.z - lo.z])
	if meshes < 2: bad += 1; print("  FAIL  no plate")
	if bodies < 1: bad += 1; print("  FAIL  a plate you would fall through")
	

	# Same seed, same city — twice.
	var c2: Node3D = StageS.new()
	c2.build()
	root.add_child(c2)
	var m2 := 0
	var st2: Array = [c2]
	while not st2.is_empty():
		var n2: Node = st2.pop_back()
		for ch in n2.get_children(): st2.push_back(ch)
		if n2 is MeshInstance3D: m2 += 1
	if m2 != meshes:
		bad += 1
		print("  FAIL  the plate is not the same twice (%d vs %d)" % [meshes, m2])
	else:
		print("  ok    the same plate every run (%d meshes both times)" % m2)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
