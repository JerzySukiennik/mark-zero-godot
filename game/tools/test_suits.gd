extends SceneTree
## Do the five suits actually load, and do they contain what the contract promises?

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")

func _initialize() -> void:
	var bad := 0
	for id in ["mk1", "mk2", "mk3", "mk42", "mk50", "pilot"]:
		var path := "res://assets/suits/%s.glb" % id
		var n: Node3D = SuitLoaderS.load_suit(path)
		if n == null:
			bad += 1
			print("  FAIL  %s did not load" % id)
			continue
		# Walk it: a model that loads and is empty looks exactly like one that failed.
		var meshes := 0
		var verts := 0
		var named := 0
		var stack: Array = [n]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for ch in node.get_children():
				stack.push_back(ch)
			if node.name.begins_with("piv_"):
				named += 1
			if node is MeshInstance3D:
				meshes += 1
				var m := (node as MeshInstance3D).mesh
				if m != null:
					for si in m.get_surface_count():
						verts += m.surface_get_array_len(si)
		var ok := meshes > 5 and verts > 1000
		if not ok:
			bad += 1
		print("  %s  %-6s %2d meshes, %6d verts, %2d piv_ nodes" %
			["ok   " if ok else "FAIL ", id, meshes, verts, named])
	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
