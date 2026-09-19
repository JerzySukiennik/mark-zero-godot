extends MainLoop
## Copy of probe_rig.gd, pointed at the two new models, and extended to print each
## pivot's local -Y as well as its position — the emitter axes are half the contract
## and a position alone cannot show that a palm is aimed into the body.

func _walk(n: Node, xf: Transform3D, out: Dictionary) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
		if n.name.begins_with("piv_"):
			out[String(n.name)] = here
	for c in n.get_children():
		_walk(c, here, out)

func _initialize() -> void:
	for id: String in ["ironspider", "peter"]:
		var scn := SuitLoader.load_suit("res://assets/suits/%s.glb" % id)
		if scn == null:
			print(id, ": no model"); continue
		var out: Dictionary = {}
		_walk(scn, Transform3D.IDENTITY, out)
		var names: Array = out.keys(); names.sort()
		var meshes: int = 0
		var stack: Array = [scn]
		var top := -1.0
		var low := 1e9
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			if nd is MeshInstance3D:
				meshes += 1
				var aabb: AABB = (nd as MeshInstance3D).get_aabb()
				var gx: Transform3D = (nd as MeshInstance3D).transform
				var p: Node = nd.get_parent()
				while p != null and p is Node3D:
					gx = (p as Node3D).transform * gx
					p = p.get_parent()
				for i in 8:
					var w: Vector3 = gx * aabb.get_endpoint(i)
					top = maxf(top, w.y)
					low = minf(low, w.y)
			for c in nd.get_children():
				stack.push_back(c)
		print("--- ", id, " --- pivots=", names.size(), " meshes=", meshes,
			" height=", "%.4f" % (top - low), " floor=", "%.4f" % low)
		for n: String in names:
			var t: Transform3D = out[n]
			var p: Vector3 = t.origin
			var my: Vector3 = -t.basis.y.normalized()
			print("%-16s x=%+6.3f y=%+6.3f z=%+6.3f   -Y=(%+5.2f,%+5.2f,%+5.2f)"
				% [n, p.x, p.y, p.z, my.x, my.y, my.z])

func _process(_d: float) -> bool:
	return true
