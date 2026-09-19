class_name WebLine
extends MeshInstance3D
## One strand of web, drawn fresh every frame.
##
## Jurek's brief was that it must not be "zwykla nitka" — a plain thread. A single line
## segment is the obvious implementation and it looks like debug geometry: no thickness, no
## weight, and nothing at all happens to it when it goes slack.
##
## So it is built as a BRAID. Three thin filaments wound helically around a core, all four
## drawn as camera-facing ribbons, over a path that SAGS when the rope is longer than the
## gap it spans and pulls dead straight when it is taut. The sag is the whole trick: it is
## the only thing that tells you, without a HUD, whether the web is currently carrying your
## weight or whether you are falling.

## Filaments wound around the core.
const STRANDS := 3
## Points along the path. Enough for the sag to read as a curve rather than as a crease.
const SEGMENTS := 26
## Helix turns over the full span.
const TWIST := 5.0
## Radius of the braid, in metres, at full width.
const BRAID := 0.045
const CORE := 0.022

var _mesh: ImmediateMesh
var _mat: StandardMaterial3D

func build() -> void:
	# `build`, not `_ready`: add_child does not fire _ready under `godot --script`, and the
	# test suites construct this directly. Same pattern as every other effect here.
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material_override = _mat

## `from` and `to` are world points; `slack` is how much longer the rope is than the gap,
## in metres; `reach` is 0..1 while the web is still flying out, 1 once it has landed.
func draw_web(from: Vector3, to: Vector3, slack: float, reach: float, cam: Vector3) -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	visible = reach > 0.001
	if not visible:
		return

	# While it is still in flight the strand is only drawn as far as it has got, so firing
	# reads as something travelling rather than as a line appearing all at once.
	var tip := from.lerp(to, clampf(reach, 0.0, 1.0))
	var span := tip - from
	var len := span.length()
	if len < 0.05:
		return

	# A real rope hangs in a catenary. A parabola is within a few per cent of one over this
	# length and costs a multiply, and nobody has ever spotted the difference.
	var sag := clampf(slack, 0.0, len * 0.5) * 0.55
	var dir := span / len
	# Any vector not parallel to the strand will do for the frame; world up fails only when
	# the web is fired straight up, which is exactly when a player will be looking at it.
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-5:
		side = dir.cross(Vector3.FORWARD)
	side = side.normalized()
	var up := side.cross(dir).normalized()

	var path: PackedVector3Array = []
	path.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		path[i] = from + span * t - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)

	# The core first, then the filaments wound around it. Drawing the core underneath is
	# what keeps the braid reading as one rope rather than as three separate threads.
	_ribbon(path, dir, side, up, 0.0, 0.0, CORE, Color(1.0, 1.0, 1.0, 0.85), cam, reach)
	for s in STRANDS:
		var phase := TAU * float(s) / STRANDS
		_ribbon(path, dir, side, up, phase, BRAID, CORE * 0.62,
			Color(0.88, 0.94, 1.0, 0.65), cam, reach)

## One camera-facing ribbon, optionally wound helically at `offset` metres from the centre.
func _ribbon(path: PackedVector3Array, dir: Vector3, side: Vector3, up: Vector3,
		phase: float, offset: float, width: float, col: Color, cam: Vector3,
		reach: float) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := path.size()
	for i in n:
		var t := float(i) / (n - 1)
		var a := phase + t * TAU * TWIST
		var p: Vector3 = path[i] + (side * cos(a) + up * sin(a)) * offset

		# Facing the camera per-point rather than per-strand: over a hundred-metre web the
		# near end and the far end are at genuinely different angles, and a single billboard
		# axis makes the far half collapse to nothing.
		var view := (p - cam)
		var flat := dir.cross(view)
		if flat.length_squared() < 1e-6:
			flat = side
		flat = flat.normalized() * width

		# The strand thins towards the anchor — perspective does some of this, but the eye
		# wants more of it than perspective gives — and the leading tip is bright and fat
		# while the web is still travelling, which is what sells the shot.
		var taper := lerpf(1.0, 0.55, t)
		var c := col
		if reach < 1.0:
			var head: float = clampf(1.0 - (reach - t) * 9.0, 0.0, 1.0) if t <= reach else 0.0
			taper *= 1.0 + head * 1.6
			c = c.lerp(Color(1, 1, 1, 1), head * 0.8)
		flat *= taper

		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - flat)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + flat)
	_mesh.surface_end()
