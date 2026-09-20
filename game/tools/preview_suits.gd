extends Node
## Renders two suits side by side under the arena's exact lighting (literally: it calls
## Arena.build_sky), so a recolour can be
## LOOKED at instead of measured. Run as a SCENE (needs a renderer):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/preview_suits.tscn -- mk50 mk3
## Writes user://preview/<a>_vs_<b>_<view>.png

var _i := 0
var _ids: PackedStringArray = ["mk50", "mk3"]
var _view := "front"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_ids = PackedStringArray([args[0], args[1]])
	if args.size() >= 3:
		_view = args[2]
	# One id twice means SOLO: one figure, 1200x1200, the contract's preview format.
	var solo := _ids[0] == _ids[1]
	DisplayServer.window_set_size(Vector2i(1200, 1200) if solo else Vector2i(1600, 1000))
	_sky()
	# side-on, two figures separated in X would stack behind each other, so they are
	# separated along the view-independent axis instead.
	var xs := [0.0, 0.0] if solo else [-0.75, 0.75]
	for k in (1 if solo else _ids.size()):
		var scn := SuitLoader.load_suit("res://assets/suits/%s.glb" % _ids[k])
		if scn == null:
			push_error("[preview] no model %s" % _ids[k]); get_tree().quit(1); return
		add_child(scn)
		scn.position = Vector3(0, 0, xs[k] * 1.6) if _view == "side" else Vector3(xs[k], 0, 0)
	var cam := Camera3D.new()
	add_child(cam)
	match _view:
		"side":
			cam.position = Vector3(3.0 if solo else 4.2, 1.05, 0.0)
		"hero":
			cam.position = Vector3(1.7 if solo else 2.4, 1.85, -2.3 if solo else -3.2)
		_:
			cam.position = Vector3(0.0, 1.05, -3.0 if solo else -4.2)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.fov = 40.0
	cam.current = true

## Deliberately SELF-CONTAINED. It mirrors scripts/world/arena.gd's sky, but this file is
## a preview harness and must keep rendering while the game scripts are mid-refactor.
## NOT a copy of the arena's lighting — it calls the game's own builder. A preview that
## lights the subject itself proves nothing about the thing Jurek plays, which is exactly
## how a suit can pass a render and still be grey in the game.
func _sky() -> void:
	Arena.build_sky(self)

func _process(_d: float) -> void:
	_i += 1
	if _i < 30:
		return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://preview"))
	if _ids[0] == _ids[1]:
		img.resize(1200, 1200, Image.INTERPOLATE_LANCZOS)
		img.save_png("user://preview/%s-%s.png" % [_ids[0], _view])
	else:
		img.save_png("user://preview/%s_vs_%s_%s.png" % [_ids[0], _ids[1], _view])
	print("[preview] wrote ", ProjectSettings.globalize_path("user://preview"))
	get_tree().quit()
