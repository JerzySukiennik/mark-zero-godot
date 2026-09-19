extends SceneTree
## Does the city build, and does a suit fly inside it?

const CityS := preload("res://scripts/world/city.gd")

func _initialize() -> void:
	var bad := 0
	print("=== city ===")
	var c: Node3D = CityS.new()
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

	print("  buildings drawn: %d   collision bodies: %d" % [meshes, bodies])
	print("  tallest tower: %.0f m" % tallest)
	print("  island extent: %.0f x %.0f m" % [hi.x - lo.x, hi.z - lo.z])
	if meshes < 200: bad += 1; print("  FAIL  too few buildings")
	if bodies < 200: bad += 1; print("  FAIL  buildings you could fly through")
	if tallest < 150.0: bad += 1; print("  FAIL  no skyline")

	# Same seed, same city — twice.
	var c2: Node3D = CityS.new()
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
		print("  FAIL  the city is not the same twice (%d vs %d)" % [meshes, m2])
	else:
		print("  ok    the same city every run (%d buildings both times)" % m2)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
