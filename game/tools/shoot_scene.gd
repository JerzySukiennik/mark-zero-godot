extends Node
## Renders the actual 3D scene to a PNG. Run as a SCENE, never with `--script`:
##   godot --path . res://tools/shoot_scene.tscn
##
## Two reasons, and both have already cost a session each. `--script` has no autoloads, so
## SuitPilot cannot compile and the arena spawns nothing — this tool hit that itself before
## it worked. And `--headless` has no renderer at all, which matters because every "can you
## see the exhaust" question so far has been answered by reading numbers instead of looking,
## which is exactly how a suit passes every test with four dark boots.

const OUT := "user://scene"
var _i := 0
var _pilot: SuitPilot
var _arena: Node3D
var _cam: Camera3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	_arena = load("res://scenes/world/arena.tscn").instantiate()
	add_child(_arena)

func _process(_d: float) -> void:
	_i += 1
	if _pilot == null:
		for c in _arena.get_children():
			if c is SuitPilot:
				_pilot = c
				break
		if _pilot == null:
			if _i > 400:
				push_error("[shot] never found a pilot")
				get_tree().quit(1)
			return
		# In the air, with the sticks reading zero — which IS the hover case, the one where
		# the boots were dark.
		_pilot.model.position = Vector3(0, 60, 0)
		_pilot.model.grounded = false
		return

	if _i < 260:
		# An isolation pass: "only", "noflame", "nofog", "nosparks" or nothing.
		var only := ""
		for a in OS.get_cmdline_user_args():
			only = a
		if only != "":
			for e in (_pilot.fx as Thrusters)._emitters:
				if only == "nofog" or only == "arconly":
					(e.fog as FogVolume).visible = false
				if only == "noflame" or only == "arconly":
					(e.flame as GPUParticles3D).visible = false
				if only == "nosparks" or only == "arconly":
					(e.sparks as GPUParticles3D).visible = false
		return
	if _cam == null:
		# Our own camera, low and close: the boots are what is being judged here.
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.global_position = _pilot.model.position + Vector3(4.0, -1.2, 6.5)
		_cam.look_at(_pilot.model.position + Vector3(0, -0.8, 0), Vector3.UP)
		_cam.fov = 45.0
		_cam.current = true
		return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	img.save_png(OUT + "/hover_%s.png" % ("all" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]))
	# A NUMBER for how bright the suit actually is, sampled off the middle of the frame
	# where the body sits. Eyeballing "still too dark" through five renders is how two
	# changes got made at once and both got blamed on the wrong one.
	var lum := 0.0
	var n := 0
	var c0 := img.get_size() / 2
	for y in range(c0.y - 170, c0.y + 40, 3):
		for x in range(c0.x - 70, c0.x + 70, 3):
			var px := img.get_pixel(x, y)
			var l := 0.2126 * px.r + 0.7152 * px.g + 0.0722 * px.b
			# ONLY THE DARK PIXELS. Averaging the whole box measured mostly SKY, so the
			# number sat at 0.28 whatever the lighting did and told me nothing. The suit is
			# the dark thing in front of a bright background, so that is what to sample.
			if l < 0.55:
				lum += l
				n += 1
	print("[shot] suit luminance = %.3f over %d samples" % [lum / maxf(1, n), n])
	print("[shot] saved — thrust_mag=%.2f hover=%s y=%.0f" % [
		_pilot.model.thrust_mag, _pilot.model.hover_active, _pilot.model.position.y])
	var fx: Thrusters = _pilot.fx
	print("[shot] emitters=%d levels=%s" % [fx._emitters.size(), fx._level])
	for e in fx._emitters:
		var core: MeshInstance3D = e.core
		print("[shot]   core vis=%s scale=%s world=%s alpha=%.2f" % [
			core.visible, core.scale, core.global_position,
			(core.material_override as StandardMaterial3D).albedo_color.a])
	get_tree().quit(0)
