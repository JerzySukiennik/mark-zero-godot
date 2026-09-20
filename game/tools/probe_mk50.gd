extends MainLoop
## Re-parses the EXPORTED mk50.glb and measures the rig. Adapted from tools/probe_rig.gd.

func _walk(n: Node, xf: Transform3D, piv: Dictionary, meshes: Array, aabb: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
		if n.name.begins_with("piv_"):
			piv[String(n.name)] = here
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var surf := []
		for i in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(i)
			surf.append(m.resource_name if m != null else "?")
		meshes.append([String(n.name), n.get_parent().name, surf])
		var b := mi.mesh.get_aabb()
		for c in 8:
			var p: Vector3 = here * b.get_endpoint(c)
			aabb[0] = aabb[0].min(p); aabb[1] = aabb[1].max(p)
	for c in n.get_children():
		_walk(c, here, piv, meshes, aabb)

func _initialize() -> void:
	var scn := SuitLoader.load_suit("res://assets/suits/mk50.glb")
	if scn == null:
		print("NO MODEL"); return
	var piv: Dictionary = {}
	var meshes: Array = []
	var aabb: Array = [Vector3(1e9,1e9,1e9), Vector3(-1e9,-1e9,-1e9)]
	_walk(scn, Transform3D.IDENTITY, piv, meshes, aabb)
	var names: Array = piv.keys(); names.sort()
	print("--- mk50.glb: ", names.size(), " pivots, ", meshes.size(), " meshes ---")
	for n: String in names:
		var t: Transform3D = piv[n]
		print("%-16s x=%+6.3f y=%+6.3f z=%+6.3f   -Y=(%+5.2f,%+5.2f,%+5.2f)  -Z=(%+5.2f,%+5.2f,%+5.2f)"
			% [n, t.origin.x, t.origin.y, t.origin.z,
			   -t.basis.y.x, -t.basis.y.y, -t.basis.y.z,
			   -t.basis.z.x, -t.basis.z.y, -t.basis.z.z])
	print("--- meshes ---")
	for m in meshes:
		print("%-16s -> %-16s  %s" % [m[0], m[1], str(m[2])])
	var mn: Vector3 = aabb[0]; var mx: Vector3 = aabb[1]
	print("--- bounds ---")
	print("height %.4f  width %.4f  depth %.4f  floor %.4f  x-centre %.4f"
		% [mx.y - mn.y, mx.x - mn.x, mx.z - mn.z, mn.y, (mn.x + mx.x) * 0.5])
	print("piv_palmL.x = %+.4f  (must be POSITIVE)" % (piv["piv_palmL"] as Transform3D).origin.x)
	var nose := (piv["piv_head"] as Transform3D).origin
	print("face check: chest pivot z %+.4f, reactor z %+.4f (reactor must be -Z of chest)"
		% [(piv["piv_chest"] as Transform3D).origin.z, (piv["piv_reactor"] as Transform3D).origin.z])
	print("head pivot ", nose)

func _process(_d: float) -> bool:
	return true
