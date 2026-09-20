class_name ThreatMarks
extends Node3D
## The two warnings the player gets: the spider-sense, and being locked up by a rocket.
##
## Both are WORLD-SPACE and sit on the character rather than on the glass. A HUD icon
## tells you something is happening somewhere; a ring over your own head tells you it is
## happening to YOU, and a bracket that stays wrapped around you while you run is the only
## way to say "this is still tracking" without words.

## How far above the head the spider-sense sits, in metres.
const SENSE_UP := 1.35
## The bracket's half-size.
const FRAME := 1.25
## Beeps a second at the slowest and the fastest, as the rocket closes.
const BEEP_SLOW := 2.2
const BEEP_FAST := 11.0

var sense_on := 0.0            ## 0..1, how loud the spider-sense is
var locked := false            ## a rocket is tracking
var lock_near := 0.0           ## 0..1, how close it is

var _sense: MeshInstance3D
var _frame: MeshInstance3D
var _beep: AudioStreamPlayer3D
var _beep_t := 0.0
var _t := 0.0
var _built := false

func build() -> void:
	if _built:
		return
	_built = true
	_sense = MeshInstance3D.new()
	_sense.mesh = _sense_mesh()
	_sense.material_override = _unshaded(Color(1.0, 0.92, 0.35, 0.0))
	_sense.position.y = SENSE_UP
	_sense.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sense)

	_frame = MeshInstance3D.new()
	_frame.mesh = _frame_mesh()
	_frame.material_override = _unshaded(Color(1.0, 0.30, 0.22, 0.0))
	_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_frame)

	_beep = AudioStreamPlayer3D.new()
	var snd := load("res://assets/audio/lock_beep.wav")
	if snd != null:
		_beep.stream = snd
	_beep.unit_size = 14.0
	_beep.max_db = 0.0
	add_child(_beep)

func _ready() -> void:
	build()

static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	# Billboarded: both marks are read, not looked at, so they must never be edge-on.
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m

## Three arcs radiating from a point — the shape everyone reads as "danger, behind you",
## without borrowing anything trademarked.
static func _sense_mesh() -> ArrayMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 3:
		var r0 := 0.16 + ring * 0.13
		var r1 := r0 + 0.07
		var steps := 14
		for i in steps:
			# A broken arc, not a circle: gaps are what make it read as a signal.
			var a0 := PI * 0.18 + float(i) / steps * PI * 0.64
			var a1 := PI * 0.18 + float(i + 1) / steps * PI * 0.64
			for mirror: float in [1.0, -1.0]:
				var p00 := Vector3(cos(a0) * r0 * mirror, sin(a0) * r0, 0)
				var p01 := Vector3(cos(a1) * r0 * mirror, sin(a1) * r0, 0)
				var p10 := Vector3(cos(a0) * r1 * mirror, sin(a0) * r1, 0)
				var p11 := Vector3(cos(a1) * r1 * mirror, sin(a1) * r1, 0)
				im.surface_add_vertex(p00); im.surface_add_vertex(p10); im.surface_add_vertex(p11)
				im.surface_add_vertex(p00); im.surface_add_vertex(p11); im.surface_add_vertex(p01)
	im.surface_end()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, im.surface_get_arrays(0))
	return am

## Four corner brackets. Corners rather than a box, because a closed rectangle hides what
## is inside it and the thing inside it is the player.
static func _frame_mesh() -> ArrayMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.075
	var arm := FRAME * 0.42
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var c := Vector3(FRAME * sx, FRAME * sy, 0)
			_bar(im, c, Vector3(-arm * sx, 0, 0), w)
			_bar(im, c, Vector3(0, -arm * sy, 0), w)
	im.surface_end()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, im.surface_get_arrays(0))
	return am

static func _bar(im: ImmediateMesh, at: Vector3, along: Vector3, w: float) -> void:
	var n := Vector3(-along.y, along.x, 0).normalized() * w
	var a := at
	var b := at + along
	im.surface_add_vertex(a - n); im.surface_add_vertex(b - n); im.surface_add_vertex(b + n)
	im.surface_add_vertex(a - n); im.surface_add_vertex(b + n); im.surface_add_vertex(a + n)

func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta

	# The spider-sense pulses. A steady glyph is furniture; one that ticks is an alarm.
	var pulse := 0.55 + 0.45 * sin(_t * 12.0)
	var sm: StandardMaterial3D = _sense.material_override
	sm.albedo_color = Color(1.0, 0.92, 0.35, sense_on * pulse * 0.95)
	_sense.visible = sense_on > 0.01
	_sense.scale = Vector3.ONE * (0.9 + 0.25 * sense_on)

	var fm: StandardMaterial3D = _frame.material_override
	fm.albedo_color = Color(1.0, 0.30, 0.22, 0.85 if locked else 0.0)
	_frame.visible = locked
	if locked:
		# It tightens as the rocket closes, which is the whole message.
		_frame.scale = Vector3.ONE * lerpf(1.25, 0.78, lock_near)
		_beep_t -= delta
		if _beep_t <= 0.0:
			_beep_t = 1.0 / lerpf(BEEP_SLOW, BEEP_FAST, lock_near)
			if _beep != null and _beep.stream != null:
				_beep.pitch_scale = lerpf(0.88, 1.5, lock_near)
				_beep.play()
	else:
		_beep_t = 0.0
