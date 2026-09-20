extends Node
## Boots the REAL main scene and counts what is standing on it. Run as a scene.
func _ready() -> void:
	var arena: Node3D = load("res://scenes/world/arena.tscn").instantiate()
	add_child(arena)
	for wait in [1.0, 3.0, 6.0]:
		await get_tree().create_timer(wait).timeout
		var sq = arena.get("squad")
		var players := get_tree().get_nodes_in_group("player").size()
		var enemies := get_tree().get_nodes_in_group("enemy").size()
		print("[probe] t~%.0fs  squad=%s  wave=%s  alive=%s  players=%d  enemies=%d" % [
			wait, sq != null, (sq.wave if sq != null else -1),
			(sq.alive.size() if sq != null else -1), players, enemies])
	get_tree().quit(0)
