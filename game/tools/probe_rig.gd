extends MainLoop
## Prints where each pivot actually sits, so left/right is measured, never assumed.
## Transforms are accumulated by hand: global_position needs the node to be inside a tree,
## and a MainLoop has none.

func _walk(n: Node, xf: Transform3D, out: Dictionary) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
		if n.name.begins_with("piv_"):
			out[String(n.name)] = here.origin
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
		print("--- ", id, " (", names.size(), " pivots) ---")
		for n: String in names:
			var p: Vector3 = out[n]
			print("%-20s x=%+6.3f y=%+6.3f z=%+6.3f" % [n, p.x, p.y, p.z])

func _process(_d: float) -> bool:
	return true
