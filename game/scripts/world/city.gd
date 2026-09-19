class_name City
extends Node3D
## A stylised New York. Hand-laid rules, not real data.
##
## Jurek's choice over OpenStreetMap footprints: full control over where things stand, and
## it stays light enough that the frame budget goes on the suit and the sky rather than on
## sixty thousand building shells. It still has to READ as New York, which means three
## things and not much else — a tight rectangular grid, towers that are far taller than they
## are wide, and a long green rectangle through the middle that everyone recognises.
##
## Built from a seeded generator so the city is identical every run. A landmark you learned
## to fly around must still be there tomorrow, and a measurement taken twice must mean the
## same thing.
##
## GEOMETRY BUDGET: every building is a box. The detail that sells a city from the air is
## the SKYLINE and the canyons between towers, not window frames — at 300 m/s nobody reads a
## facade. Boxes also mean one mesh and one material per district, which is what keeps this
## affordable while a suit is throwing light around inside it.

const BLOCK := 80.0           ## metres, one city block including the street
const STREET := 22.0          ## the gap between blocks — wide enough to fly down
const GRID_X := 14            ## blocks east-west  (Manhattan is narrow)
const GRID_Z := 38            ## blocks north-south (and long)
const PARK_X0 := 5
const PARK_X1 := 9
const PARK_Z0 := 16
const PARK_Z1 := 27
const SEED := 0x4A55524B      ## "JURK"

var _rng := RandomNumberGenerator.new()
var ground_y := 0.0

var _built := false

func _ready() -> void:
	build()

## Separate from _ready() so the city can be built and measured without a running scene.
## The first version did the work in _ready and the headless test walked the node before
## that had fired, counted zero buildings and reported a city that was in fact fine.
func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = SEED
	_build_ground()
	_build_blocks()
	_build_park()

func span_x() -> float: return GRID_X * BLOCK
func span_z() -> float: return GRID_Z * BLOCK

func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _build_ground() -> void:
	var plane := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(span_x() + 400.0, 2.0, span_z() + 400.0)
	plane.mesh = box
	plane.position.y = -1.0
	plane.material_override = _mat(Color(0.10, 0.10, 0.11), 0.95)
	add_child(plane)

	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	body.add_child(shape)
	body.position.y = -1.0
	add_child(body)

func _in_park(ix: int, iz: int) -> bool:
	return ix >= PARK_X0 and ix <= PARK_X1 and iz >= PARK_Z0 and iz <= PARK_Z1

## Height profile: a spine of towers down the middle of the island, shorter towards the
## water. Two clusters, the way Manhattan actually looks — midtown and downtown — with a
## dip between them, because a uniform wall of towers reads as a wall, not a city.
func _height_at(ix: int, iz: int) -> float:
	var fz := float(iz) / float(GRID_Z)
	var midtown := exp(-pow((fz - 0.62) * 3.2, 2.0))
	var downtown := exp(-pow((fz - 0.12) * 4.0, 2.0))
	var spine := 1.0 - absf(float(ix) / float(GRID_X) - 0.5) * 1.3
	var h := 40.0 + 300.0 * maxf(midtown, downtown * 0.85) * clampf(spine, 0.25, 1.0)
	return h * _rng.randf_range(0.55, 1.35)

func _build_blocks() -> void:
	var shell := _mat(Color(0.20, 0.21, 0.24), 0.78, 0.15)
	var glass := _mat(Color(0.14, 0.18, 0.22), 0.25, 0.55)
	var holder := Node3D.new()
	holder.name = "Blocks"
	add_child(holder)

	for ix in GRID_X:
		for iz in GRID_Z:
			if _in_park(ix, iz):
				continue
			var x := (ix - GRID_X * 0.5) * BLOCK
			var z := (iz - GRID_Z * 0.5) * BLOCK
			var footprint := BLOCK - STREET
			# One to three towers per block, so the skyline has texture instead of being
			# one box per block repeated four hundred times.
			var n := 1 if _rng.randf() < 0.45 else (2 if _rng.randf() < 0.7 else 3)
			for i in n:
				var w := footprint / float(n) * _rng.randf_range(0.6, 0.95)
				var d := footprint * _rng.randf_range(0.45, 0.9)
				var h := _height_at(ix, iz) * _rng.randf_range(0.5, 1.0)
				var ox := (float(i) - (n - 1) * 0.5) * (footprint / float(n))
				var oz := _rng.randf_range(-1.0, 1.0) * (footprint - d) * 0.4
				_tower(holder, Vector3(x + ox, 0, z + oz), Vector3(w, h, d),
					glass if _rng.randf() < 0.35 else shell)

func _tower(parent: Node3D, at: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at + Vector3(0, size.y * 0.5, 0)
	mi.material_override = mat
	parent.add_child(mi)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = mi.position
	parent.add_child(body)

func _build_park() -> void:
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var w := (PARK_X1 - PARK_X0 + 1) * BLOCK
	var d := (PARK_Z1 - PARK_Z0 + 1) * BLOCK
	bm.size = Vector3(w, 1.0, d)
	g.mesh = bm
	g.position = Vector3(
		((PARK_X0 + PARK_X1) * 0.5 - GRID_X * 0.5 + 0.5) * BLOCK,
		0.2,
		((PARK_Z0 + PARK_Z1) * 0.5 - GRID_Z * 0.5 + 0.5) * BLOCK)
	g.material_override = _mat(Color(0.09, 0.19, 0.10), 0.95)
	g.name = "Park"
	add_child(g)
