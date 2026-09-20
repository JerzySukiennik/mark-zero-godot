extends Node
## Diagnostic: mk50 alone, four variants, to find what makes it pale.
var _i := 0
var _mode := "as-is"
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1: _mode = a[0]
	DisplayServer.window_set_size(Vector2i(1200, 1200))
	var env := Environment.new()
	var sky := Sky.new()
	var m := ProceduralSkyMaterial.new()
	m.sky_top_color = Color(0.10, 0.14, 0.22)
	m.sky_horizon_color = Color(0.30, 0.34, 0.40)
	m.ground_bottom_color = Color(0.05, 0.05, 0.06)
	m.ground_horizon_color = Color(0.16, 0.17, 0.19)
	m.sky_energy_multiplier = 2.60
	sky.sky_material = m
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.60
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = _mode != "noglow"
	env.glow_intensity = 0.5
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.06
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.10
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -125, 0); sun.light_energy = 2.2
	sun.light_color = Color(1,0.96,0.90); add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 55, 0); fill.light_energy = 1.05
	fill.light_color = Color(0.72,0.82,1.0); add_child(fill)
	var s := SuitLoader.load_suit("res://assets/suits/mk50.glb")
	add_child(s)
	if _mode != "as-is": _fix(s)
	var cam := Camera3D.new(); add_child(cam)
	cam.position = Vector3(0, 1.35, -1.9); cam.look_at(Vector3(0,1.30,0), Vector3.UP)
	cam.fov = 40.0; cam.current = true

func _fix(n: Node) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var sm = mesh.surface_get_material(i)
			if sm is StandardMaterial3D:
				match _mode:
					"noemis": sm.emission_enabled = false
					"blackalbedo": sm.albedo_texture = null; sm.albedo_color = Color(0,0,0); sm.emission_enabled = false
					"rough": sm.roughness = 0.34; sm.roughness_texture = null
					"metal1": sm.metallic = 1.0
					"emismul": sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	for c in n.get_children(): _fix(c)

func _process(_d: float) -> void:
	_i += 1
	if _i < 30: return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://preview"))
	img.save_png("user://preview/why_%s.png" % _mode)
	get_tree().quit()
