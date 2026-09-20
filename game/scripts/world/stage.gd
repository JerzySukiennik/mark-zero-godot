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
	_towers()
	_props()

## ONE building. Not a city — the plate is still the point — but Spider-Man cannot swing
## off nothing, and a web fired into an empty sky is a mechanic with no world to use it on.
## Jurek: "nie ma zadnych budynkow. Wiec moze dodaj jeden budynek."
##
## A HANDFUL, not one, and not a city.
##
## One tower was enough to prove a web could stick to something. It is not enough for what
## Jurek actually described — swing, let go, hop, swing again, "w kolko" — because that
## loop needs the NEXT anchor to already be in front of you when you release the last one.
## With a single tower every swing ends in a walk back. So: a scattered line of them down
## the plate, varied in height so the arcs vary, and still nothing like scenery.
const TOWER_WIDTH := 34.0
## x, z, height. Spread along -Z, which is the direction the suits spawn facing.
const TOWERS := [
	Vector3(0, -95, 180.0),
	Vector3(-72, -190, 135.0),
	Vector3(64, -235, 210.0),
	Vector3(-30, -330, 160.0),
	Vector3(88, -410, 120.0),
	Vector3(-96, -470, 195.0),
	Vector3(12, -560, 150.0),
	Vector3(-58, -660, 225.0),
	Vector3(78, -730, 140.0),
]

func _towers() -> void:
	for t: Vector3 in TOWERS:
		_tower(Vector3(t.x, 0, t.y), t.z)

func _tower(at: Vector3, height: float) -> void:
	var root := Node3D.new()
	root.name = "Tower"
	root.position = at
	add_child(root)

	var bm := BoxMesh.new()
	bm.size = Vector3(TOWER_WIDTH, height, TOWER_WIDTH)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position.y = height * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.055, 0.060, 0.070)
	m.metallic = 0.35
	m.roughness = 0.42
	mi.material_override = m
	root.add_child(mi)

	# Bands up the face. Same reasoning as the grid on the plate: a flat slab gives the eye
	# nothing to judge height or closing speed against, and swinging is entirely about both.
	var bands := ImmediateMesh.new()
	var bmi := MeshInstance3D.new()
	bmi.mesh = bands
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.85, 0.92, 1.0, 0.65)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmi.material_override = lm
	bands.surface_begin(Mesh.PRIMITIVE_LINES)
	var h := TOWER_WIDTH * 0.5 + 0.05
	var y := 6.0
	while y < height:
		for c: Vector2 in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]:
			bands.surface_add_vertex(Vector3(c.x, y, c.y))
		# Close the ring: four segments need the first corner again at the end.
		bands.surface_add_vertex(Vector3(-h, y, -h))
		bands.surface_add_vertex(Vector3(h, y, -h))
		bands.surface_add_vertex(Vector3(h, y, h))
		bands.surface_add_vertex(Vector3(-h, y, h))
		y += 6.0
	bands.surface_end()
	root.add_child(bmi)

	var body := StaticBody3D.new()
	body.name = "TowerBody"
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = bm.size
	cs.shape = sh
	cs.position.y = height * 0.5
	body.add_child(cs)
	root.add_child(body)

func _plate() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE, 2.0, SIZE)
	mi.mesh = bm
	mi.position.y = GROUND_Y - 1.0
	var m := StandardMaterial3D.new()
	# NEAR BLACK. The sky had to be turned up a long way to get the armour off black — see
	# arena.gd — and the plate came up with it: "cala mapa nagle jest niebieska, a powinna
	# byc czarna, z takimi paskami bialymi". The plate is a dielectric and the suit is
	# metal, so they can be separated: drop the plate's albedo until the brighter sky lands
	# it back where it was, and leave the metal alone.
	m.albedo_color = Color(0.030, 0.032, 0.036)
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
		# WHITE LINES on a black plate, which is how Jurek has always described it and how
		# it read before the sky went up. Every fifth line is full white so there is a
		# coarse grid to judge distance against as well as a fine one.
		var c := Color(1.0, 1.0, 1.0) if i % 5 == 0 else Color(0.55, 0.58, 0.62)
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

## A couple of things to throw, by the spawn. Jurek asked for one bin to prove the
## mechanic; two is barely more work and stops the first throw ending the feature.
const PROPS := [Vector3(6, 0, -4), Vector3(-5, 0, -7), Vector3(11, 0, -12)]

func _props() -> void:
	for at: Vector3 in PROPS:
		var p := Prop.new()
		p.name = "Prop"
		p.ground_y = GROUND_Y
		add_child(p)
		p.position = Vector3(at.x, GROUND_Y, at.z)
