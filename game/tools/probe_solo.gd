extends Node
## Drives the real PLAY SOLO path and keeps WATCHING after it, which the obvious version
## of this probe cannot do: change_scene_to_file frees the current scene, so a watcher
## parented inside it dies at the very moment it is supposed to start reporting. This one
## parks a second node directly on the tree root, where nothing frees it.

class Watch:
	extends Node
	var n := 0
	func _process(_d: float) -> void:
		n += 1
		if n % 60 == 0:
			print("[watch] alive ", n, "  scene=", get_tree().current_scene)
		if n == 600:
			print("[watch] SURVIVED")
			get_tree().quit(0)

var _i := 0
var _m: Node

func _ready() -> void:
	var w := Watch.new()
	w.name = "Watch"
	get_tree().root.call_deferred("add_child", w)
	_m = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_m)

func _process(_d: float) -> void:
	_i += 1
	if _i == 20:
		print("[probe] opening lobby")
		_m.call("_open_lobby")
	elif _i == 40:
		print("[probe] pressing PLAY SOLO")
		_m.get("_lobby").call("_press", "solo")
