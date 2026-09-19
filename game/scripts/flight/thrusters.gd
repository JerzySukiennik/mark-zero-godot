class_name Thrusters
extends Node3D
## What comes out of the armour. Four emitters: two boots, two palms.
##
## WHY THERE IS NO CONE AND NO BIG SPRITE.
##
## The browser build drew each plume as a cone mesh with a gradient on it. From a metre away
## that reads as a painted plastic cone, because a cone has a SILHOUETTE and fire does not.
## Replacing it with a single large billboard was no better — Jurek's word for both was that
## they looked like SVG, and he is right: one flat shape pasted into a 3D scene stays a flat
## shape however it is coloured.
##
## Volume comes from MANY SMALL OVERLAPPING THINGS, never from one big one. So each emitter
## is a dense stream of small additive particles whose colour runs down a temperature ramp,
## plus a FogVolume at the throat — actual volumetric density that the scene's lights scatter
## through, which is the one element here that is genuinely three-dimensional rather than a
## convincing stack of flat ones.
##
## THE FOUR THINGS THAT MAKE EXHAUST READ, in the order they matter:
##
##   1. A BLOWN-OUT CORE. The throat must be pure white and overexposed. Colour belongs to
##      the glow around it — a coloured core looks like plastic, a white one looks hot.
##   2. A TEMPERATURE RAMP. White at the throat, amber a hand's width out, deep red as it
##      dies. One flat colour cannot be fire whatever colour it is.
##   3. LIGHT ON THE WORLD. A thruster that does not light the ground under it is pasted on.
##      This is the single strongest "is it real" cue and the cheapest to get wrong.
##   4. MOTION. Flicker and a little randomness in length. A steady flame is a lamp.
##
## BUDGET, because this runs on a laptop RTX 3050 with 4 GB: two lights, not four. The boots
## share one and the palms share one, placed between each pair. Four dynamic lights on the
## player is four more shader permutations for every material in the scene.

const EMITTERS := [
	{ pivot = "piv_thrusterL", boot = true },
	{ pivot = "piv_thrusterR", boot = true },
	{ pivot = "piv_palmL", boot = false },
	{ pivot = "piv_palmR", boot = false },
]

## The temperature ramp. Read as: throat, mid, tail.
const HOT := Color(1.0, 1.0, 1.0)
const WARM := Color(1.0, 0.68, 0.22)
const COOL := Color(0.85, 0.16, 0.03)

var _emitters: Array = []
var _lights: Array = []
var _rig: SuitRig
var _level := [0.0, 0.0, 0.0, 0.0]

func _ready() -> void:
	name = "Thrusters"
	for i in 2:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.74, 0.45)
		l.light_energy = 0.0
		l.omni_range = 9.0
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)

## Called whenever an armour is worn: the pivots are new objects every time.
func attach(rig: SuitRig) -> void:
	_rig = rig
	for e in _emitters:
		if is_instance_valid(e.holder):
			e.holder.queue_free()
	_emitters.clear()
	if rig == null:
		return
	for spec in EMITTERS:
		if not rig.has_pivot(spec.pivot):
			continue
		var pivot: Node3D = rig.pivots[spec.pivot]
		var holder := Node3D.new()
		holder.name = "fx_" + spec.pivot
		# Parented to the pivot, so the plume follows the pose for free and points wherever
		# the limb points. The emitter axis is the pivot's local -Y (assets/suits/CONTRACT.md).
		pivot.add_child(holder)
		var scale_f: float = 1.0 if spec.boot else 0.62
		_emitters.append({
			holder = holder,
			boot = spec.boot,
			core = _make_core(holder, scale_f),
			glow = _make_glow(holder, scale_f),
			flame = _make_flame(holder, scale_f),
			fog = _make_fog(holder, scale_f),
			sparks = _make_sparks(holder, scale_f),
		})

## THE ARC. A solid tapered cone of light out of the nozzle, redrawn every frame.
##
## Particles cannot do this, and that is the lesson from the whole exhaust so far: however
## you tune them, a cloud of separate sprites reads as SMOKE. What Jurek asked for is the
## opposite — "mega mocne przy nogach, takie bez przerwy... jak jest spawanie" — a welding
## arc, which is continuous, has a hard bright core and hurts to look at. That is geometry
## with additive blending, not a particle system. The particles stay, but they are now the
## sparks AROUND the arc rather than the thing itself.
func _make_core(parent: Node3D, s: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	# Emitter axis is the pivot's local -Y, and a CylinderMesh runs along +Y, so it is hung
	# below the nozzle and tapers as it goes.
	cm.top_radius = 0.052 * s
	cm.bottom_radius = 0.012 * s
	cm.height = 0.95 * s
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.position.y = -cm.height * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Past white on purpose. Values over one are what the glow pass picks up, and the bloom
	# is most of what makes it read as too bright to look at rather than as a blue cone.
	m.albedo_color = Color(2.6, 3.0, 3.4, 0.95)
	mi.material_override = m
	parent.add_child(mi)
	return mi

## The halo around the arc. Wider, much softer, and the part that actually blooms.
func _make_glow(parent: Node3D, s: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16 * s
	cm.bottom_radius = 0.05 * s
	cm.height = 1.5 * s
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.position.y = -cm.height * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.55, 0.85, 1.35, 0.32)
	mi.material_override = m
	parent.add_child(mi)
	return mi

## The plume: a dense stream of small additive particles. Small and many is the whole point.
func _make_flame(parent: Node3D, s: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# THE ARC CARRIES THE EXHAUST NOW, and these are a whisper of heat around it. Rendered
	# side by side, the arc alone is exactly the welding torch Jurek asked for and the
	# particles were a white cloud swallowing the suit from the waist down. So they keep
	# their job — hot grit in the blast — and lose the volume.
	p.amount = 55
	p.lifetime = 0.15
	p.explosiveness = 0.0
	p.fixed_fps = 0
	p.local_coords = false          # the plume is left behind as the suit moves through it
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.028 * s
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 7.0
	# TIGHT AND SHORT. Never visible until now, so never tuned: at 9-15 m/s over a quarter
	# second the plume threw itself six metres past the boots and read as a launch vehicle
	# rather than as a man hovering. Jurek wants it "mega mocne przy nogach" — the intensity
	# belongs AT the nozzle, and length is what dilutes it.
	pm.initial_velocity_min = 4.0 * s
	pm.initial_velocity_max = 6.5 * s
	pm.gravity = Vector3.ZERO
	pm.damping_min = 14.0
	pm.damping_max = 20.0
	pm.scale_min = 0.085 * s
	pm.scale_max = 0.155 * s
	# Grows as it cools and slows, the way a jet spreads once it leaves the nozzle.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 0.55))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color_ramp = _ramp([
		[0.00, Color(HOT.r, HOT.g, HOT.b, 0.42)],
		[0.18, Color(1.0, 0.92, 0.70, 0.34)],
		[0.50, Color(WARM.r, WARM.g, WARM.b, 0.20)],
		[1.00, Color(COOL.r, COOL.g, COOL.b, 0.0)],
	])
	p.process_material = pm
	p.draw_pass_1 = _billboard(0.34)
	parent.add_child(p)
	return p

## The volumetric core. This is the only genuinely three-dimensional part: real density that
## the scene's lights scatter through, rather than a stack of flat quads that merely reads
## as volume. Small, because volumetric fog is charged by the cubic metre.
func _make_fog(parent: Node3D, s: float) -> FogVolume:
	var f := FogVolume.new()
	f.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	# Shrunk with the plume: a fog volume a metre and a half tall was most of the soft white
	# mass swallowing the suit.
	f.size = Vector3(0.34, 0.70, 0.34) * s
	f.position = Vector3(0, -0.7 * s, 0)
	var m := FogMaterial.new()
	m.density = 0.0                 # driven per frame from the emitter's output
	m.albedo = Color(1.0, 0.80, 0.55)
	m.emission = Color(1.0, 0.62, 0.22)
	f.material = m
	parent.add_child(f)
	return f

## A few bright specks thrown clear. They do almost nothing on their own and a surprising
## amount together with the rest: they are what stops the plume looking like a smooth gas.
func _make_sparks(parent: Node3D, s: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.5
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 12.0 * s
	pm.initial_velocity_max = 26.0 * s
	pm.gravity = Vector3(0, -6.0, 0)
	pm.damping_min = 3.0
	pm.damping_max = 8.0
	pm.scale_min = 0.03 * s
	pm.scale_max = 0.07 * s
	pm.color_ramp = _ramp([
		[0.0, Color(1.0, 0.95, 0.8, 1.0)],
		[0.55, Color(1.0, 0.55, 0.12, 0.9)],
		[1.0, Color(0.7, 0.12, 0.02, 0.0)],
	])
	p.process_material = pm
	p.draw_pass_1 = _billboard(0.055)
	parent.add_child(p)
	return p

static func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for st in stops:
		g.add_point(st[0], st[1])
	# add_point leaves the two default stops at 0 and 1; drop them so the ramp is only ours.
	while g.get_point_count() > stops.size():
		g.remove_point(0)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

## One quad, always facing the camera, additive and unshaded. Each particle is flat — the
## volume comes from a hundred of them overlapping, which is the whole trick.
static func _billboard(sz: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(sz, sz)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_receive_shadows = true
	m.albedo_texture = _dot()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	q.material = m
	return q

## A soft round falloff. Never a hard-edged disc: a hundred hard discs is a hundred visible
## edges, and edges are exactly what fire must not have.
static var _dot_tex: GradientTexture2D
static func _dot() -> GradientTexture2D:
	if _dot_tex != null:
		return _dot_tex
	var g := Gradient.new()
	g.add_point(0.0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.45))
	g.add_point(1.0, Color(1, 1, 1, 0.0))
	while g.get_point_count() > 3:
		g.remove_point(0)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_dot_tex = t
	return t

## `thrust` 0..1 overall, `lateral` and `vertical` so the palms answer to the hands' work.
## `hover` is how hard the stabiliser is working, 0..1, and it is SEPARATE from `thrust`
## for a reason: holding station is exactly when the sticks are asking for nothing, so a
## thrust-driven exhaust goes dark at the one moment the suit is working hardest. Passing
## the stick alone is why a hovering armour had four cold boots.
func drive(delta: float, thrust: float, lateral: float, vertical: float, braking: float,
		hover: float = 0.0) -> void:
	if _emitters.is_empty():
		return
	# Boots carry the lift and the forward push; palms are stabilisers and only light up hard
	# when braking or working sideways. That division is what makes the suit look like it is
	# flying itself rather than being dragged.
	var boot := clampf(thrust * 0.85 + maxf(vertical, 0.0) * 0.6 + braking * 0.35
		+ hover * 0.95, 0.0, 1.4)
	# In a hover the PALMS matter as much as the boots — it is the four of them together
	# holding him up, and it is the palms you actually see from behind.
	var palm := clampf(braking * 0.9 + absf(lateral) * 0.55 + maxf(vertical, 0.0) * 0.35
		+ thrust * 0.12 + hover * 0.75, 0.0, 1.3)

	for i in _emitters.size():
		var e = _emitters[i]
		var want: float = boot if e.boot else palm
		# Flicker: fast, small, and different per emitter so they never pulse in unison.
		want *= 0.90 + 0.10 * sin(Time.get_ticks_msec() * 0.031 + i * 2.3)
		_level[i] = lerpf(_level[i], want, 1.0 - exp(-delta / 0.05))
		var lv: float = _level[i]
		var on := lv > 0.02

		# The arc is continuous — it does not pulse on and off, it lengthens and brightens.
		# Length is scaled rather than alpha alone, because a jet that only fades looks like
		# a light being dimmed while one that grows looks like a throttle opening.
		for part: String in ["core", "glow"]:
			var mi: MeshInstance3D = e[part]
			mi.visible = lv > 0.02
			if mi.visible:
				var stretch: float = 0.45 + lv * 1.25
				mi.scale = Vector3(0.7 + lv * 0.45, stretch, 0.7 + lv * 0.45)
				var mat: StandardMaterial3D = mi.material_override
				var a: Color = mat.albedo_color
				mat.albedo_color = Color(a.r, a.g, a.b,
					(0.95 if part == "core" else 0.32) * clampf(lv * 1.2, 0.0, 1.0))

		e.flame.emitting = on
		e.sparks.emitting = lv > 0.35
		if on:
			e.flame.amount_ratio = clampf(lv, 0.15, 1.0)
			e.flame.speed_scale = 0.8 + lv * 0.6
		# A trace, not a cloud. At 0.55 the fog volumes were most of the white mass that
		# buried the legs; they exist to catch the light, not to be seen.
		(e.fog.material as FogMaterial).density = lv * 0.10

	# The two lights, placed between each pair so a single source covers both.
	_place_light(0, "piv_thrusterL", "piv_thrusterR", maxf(_level[0], _level[1]))
	_place_light(1, "piv_palmL", "piv_palmR", maxf(_level[2], _level[3]))

func _place_light(idx: int, a: String, b: String, level: float) -> void:
	if idx >= _lights.size() or _rig == null:
		return
	var l: OmniLight3D = _lights[idx]
	if not (_rig.has_pivot(a) and _rig.has_pivot(b)):
		l.light_energy = 0.0
		return
	var pa: Node3D = _rig.pivots[a]
	var pb: Node3D = _rig.pivots[b]
	l.global_position = (pa.global_position + pb.global_position) * 0.5 - Vector3(0, 0.45, 0)
	# NEVER toggled with `visible`: the renderer bakes the light count into every material's
	# shader, so a light appearing or disappearing recompiles the whole scene. Energy to zero
	# instead. This cost a multi-second freeze on the first shot in the browser build.
	l.light_energy = level * 5.5
	l.omni_range = 7.0 + level * 5.0
