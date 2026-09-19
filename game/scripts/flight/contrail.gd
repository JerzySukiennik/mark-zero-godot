class_name Contrail
extends Node3D
## The flight line: smoke that stays in the air after the suit has gone.
##
## THE MISTAKE THIS AVOIDS. The browser build drew the trail as a ribbon — a quad chain
## streaming off the boots. It was invisible, and the reason is geometric rather than a bug:
## a ribbon is a SURFACE, and in level flight it streams directly behind you, which is
## exactly the angle at which a surface is one pixel wide. It was there the whole time; you
## cannot see a sheet of paper from its edge.
##
## Puffs have no edge to be seen from. They also linger, which a 0.55 s ribbon could not:
## the point of a trail is the shape of the flight still hanging in the air after you have
## left, not a tail showing where you are now.
##
## EMISSION IS BY DISTANCE, NOT BY TIME. A fixed rate leaves a dotted line at 300 m/s and a
## solid blob at a hover. One puff every few metres travelled is the same density however
## fast you are going, which is what the eye reads as speed.

## Metres between puffs along the flight path.
const SPACING := 3.0
const MIN_SPEED := 14.0          ## below this it is exhaust pooling, not a trail

var _smoke: GPUParticles3D
var _vapour: MeshInstance3D
var _last_pos := Vector3.ZERO
var _carry := 0.0
var _have_last := false

func _ready() -> void:
	name = "Contrail"
	_smoke = _make_smoke()
	add_child(_smoke)
	_vapour = _make_vapour_cone()
	add_child(_vapour)

func _make_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 900
	p.lifetime = 7.0
	p.local_coords = false          # puffs stay where they were made, not glued to the suit
	p.emitting = false
	p.one_shot = false
	p.explosiveness = 0.0
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	# Emission is driven by hand from `update`, one burst per SPACING metres, so the density
	# follows distance rather than time. `emitting` stays on and the RATE is what moves.
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	# A slow rise, so the line drifts upward and reads as smoke rather than as dots hanging
	# in a vacuum.
	pm.gravity = Vector3(0, 1.1, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.4
	pm.scale_min = 1.6
	pm.scale_max = 3.0
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.25))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 2.4))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	# Hot for the first instant — it is still flame as it leaves the boot — then smoke.
	pm.color_ramp = Thrusters._ramp([
		[0.00, Color(1.0, 0.80, 0.45, 0.85)],
		[0.08, Color(1.0, 0.62, 0.25, 0.60)],
		[0.30, Color(0.86, 0.88, 0.92, 0.42)],
		[1.00, Color(0.78, 0.82, 0.88, 0.0)],
	])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX      # smoke occludes; it is not a light
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Thrusters._dot()
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	return p

## The Prandtl-Glauert cone: the disc of condensation that forms around something going
## transonic. It is the single most recognisable "this is fast" image there is, and it costs
## one cone and one shaderless material.
func _make_vapour_cone() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.1
	cm.bottom_radius = 2.6
	cm.height = 3.2
	cm.radial_segments = 28
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	# Nose-first: the cone opens backwards along the body's +Z.
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.position = Vector3(0, 0, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.85, 0.92, 1.0, 0.0)
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.visible = false
	return mi

## Called every frame by the suit.
##   at      where the boots are, in world space
##   speed   m/s
##   mach    speed / 343
func update(delta: float, at: Vector3, speed: float, mach: float, body: Basis) -> void:
	# The trail is added to the world deferred, so the suit's first physics steps can arrive
	# before _ready has built anything. Nothing to do until it exists.
	if _smoke == null or _vapour == null:
		return
	if not _have_last:
		_last_pos = at
		_have_last = true

	var moved := at.distance_to(_last_pos)
	_last_pos = at

	if speed > MIN_SPEED:
		_carry += moved
		if _carry >= SPACING:
			var n := int(_carry / SPACING)
			_carry -= n * SPACING
			_smoke.global_position = at
			_smoke.emitting = true
			# amount_ratio is how much of the pool is in flight; more of it at speed keeps
			# the rope continuous rather than beaded.
			_smoke.amount_ratio = clampf(speed / 260.0, 0.25, 1.0)
	else:
		_smoke.emitting = false

	# The cone only exists near and past the sound barrier, and it is strongest right AT it —
	# which is physically true and also the right dramatic beat: it flashes as you break
	# through rather than sitting there permanently.
	var m: StandardMaterial3D = _vapour.material_override
	var near_one := 1.0 - clampf(absf(mach - 1.0) / 0.35, 0.0, 1.0)
	var a := near_one * 0.32
	_vapour.visible = a > 0.004
	if _vapour.visible:
		m.albedo_color = Color(0.85, 0.92, 1.0, a)
		_vapour.global_position = at + body * Vector3(0, 0.9, 1.4)
		_vapour.global_basis = body * Basis.from_euler(Vector3(PI * 0.5, 0, 0))
