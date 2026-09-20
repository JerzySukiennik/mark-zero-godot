extends Node
## A look at the front of the game. Run WITHOUT --headless.
const OUT := "user://menu"
var _i := 0
var _menu: Node3D
func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	_menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(_menu)
func _process(_d: float) -> void:
	_i += 1
	# Far enough into the orbit that the camera is not at its starting angle.
	# `lobby` on the command line opens the side-picker over the same scene, so the screen
	# that actually decides a match can be looked at rather than described.
	if _i == 300 and "lobby" in OS.get_cmdline_user_args():
		_menu.call("_open_lobby")
	if _i < 420:
		return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	img.save_png(OUT + "/menu%s.png" % ("_lobby" if "lobby" in OS.get_cmdline_user_args() else ""))
	print("[menu] saved")
	get_tree().quit(0)
