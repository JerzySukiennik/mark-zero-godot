class_name Stage
extends Node3D
## An empty plate to work on. Nothing else.
##
## The city went away on purpose. Jurek: "najpierw zajmijmy się działaniem stroju i UI, więc
## usuń całe miasto i zostaw pusty prosty baseplate." He is right, and the reason is worth
## writing down: a city is scenery, and scenery makes it HARDER to judge whether the suit
## itself feels good. Every complaint so far has been about the suit — how it moves, what it
## does, what you can see of it — and a grey plate answers those questions without 836
## buildings in the way.
##
## A grid is drawn on it, which is not decoration either: without a texture, flying over a
## flat plane gives the eye nothing to measure speed or height against, and the suit feels
## like it is hovering still. The lines are the speedometer.

const SIZE := 1200.0
const CELL := 20.0
const GROUND_Y := 0.0

var ground_y := GROUND_Y

func _ready() -> void:
	build()

var _built := false

## Separate from _ready so the plate can be built and measured without a running scene.
func build() -> void:
	if _built:
		return
	_built = true
	_plate()
	_grid()

func _plate() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE, 2.0, SIZE)
	mi.mesh = bm
	mi.position.y = GROUND_Y - 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.14, 0.16)
	m.roughness = 0.92
	m.metallic = 0.0
	mi.material_override = m
	mi.name = "Plate"
	add_child(mi)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	body.add_child(cs)
	body.position.y = GROUND_Y - 1.0
	add_child(body)

## One mesh for every line on the plate. Drawn as lines rather than a texture so it stays
## sharp from a metre up and from three hundred, with no mipmap blur in between.
func _grid() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var half := SIZE * 0.5
	var n := int(SIZE / CELL)
	for i in n + 1:
		var p := -half + i * CELL
		# Every fifth line is brighter, so there is a coarse scale as well as a fine one.
		var c := Color(0.42, 0.46, 0.52) if i % 5 == 0 else Color(0.22, 0.24, 0.27)
		st.set_color(c); st.add_vertex(Vector3(p, 0.02, -half))
		st.set_color(c); st.add_vertex(Vector3(p, 0.02, half))
		st.set_color(c); st.add_vertex(Vector3(-half, 0.02, p))
		st.set_color(c); st.add_vertex(Vector3(half, 0.02, p))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.name = "Grid"
	add_child(mi)
