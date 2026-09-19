class_name ShoulderTurret
extends Node3D
## The gun that comes out of the right shoulder. Square fires it.
##
## Built in code rather than modelled, because none of the five armours has one and adding
## it to all five in Blender is a separate project. Procedural also means it is the same
## piece on every Mark and it scales to whichever shoulder it is bolted to — the Mk I's
## shoulder is a slab and the Mk L's is a curve, and one model would sit wrong on at least
## one of them.
##
## THE DEPLOY IS THE POINT. Jurek asked for it to "open nicely", and that is most of what
## makes this weapon feel like Iron Man rather than a gun: two covers hinge back, the
## housing rises out of the pauldron, the barrel extends and only THEN does it fire. It
## takes a third of a second, which is a real cost — you cannot snap-shoot with it — and
## paying that cost is what makes it read as machinery rather than as a hotkey.
##
## It also FOLDS AWAY on its own. A turret left standing proud is a turret that stops being
## an event, and the whole appeal is watching it appear.

signal fired

const DEPLOY_TIME := 0.34
const STOW_AFTER := 3.0          ## seconds of not firing before it packs itself away
const COOLDOWN := 0.55
const SPEED := 340.0
const LIFE := 3.0
const POOL := 8
const DRAIN := 0.2               ## a fifth of the magazine per shot: four shots, then wait
const RECHARGE := 0.09

var charge := 1.0
var deployed := 0.0              ## 0 stowed, 1 fully out
var _want := 0.0
var _cool := 0.0
var _idle := 0.0
var _mount: Node3D
var _housing: Node3D
var _barrel: Node3D
var _covers: Array = []
var _muzzle: Node3D
var _pool: Array = []
var _built := false

func _ready() -> void:
	name = "ShoulderTurret"
	build()

func build() -> void:
	if _built:
		return
	_built = true
	for i in POOL:
		_pool.append(_make_shell())

## Bolt it onto a rig. Called whenever an armour is worn.
func attach(rig: SuitRig) -> void:
	if _mount != null and is_instance_valid(_mount):
		_mount.queue_free()
	_mount = null
	# The RIGHT shoulder as the player sees it, which the models call L — see SuitRig.SIDE.
	# It was mounting on the model's own R and therefore popping out of the shoulder on the
	# left of the screen, which is not where anyone has ever seen it.
	var mount: String = "piv_shoulder" + SuitRig.SIDE["R"]
	if rig == null or not rig.has_pivot(mount):
		return
	var shoulder: Node3D = rig.pivots[mount]

	_mount = Node3D.new()
	_mount.name = "TurretMount"
	# Sat on top of the pauldron and a little outboard, which is where it is in every
	# reference. The shoulder pivot's own axis points DOWN the arm, so up is -Y here.
	_mount.position = Vector3(0.0, -0.10, -0.02)
	shoulder.add_child(_mount)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.22, 0.23, 0.26)
	steel.metallic = 0.9
	steel.roughness = 0.35

	# The two covers. Flush when stowed, hinged back when deployed — this is the bit you
	# actually watch.
	for side in [-1.0, 1.0]:
		var cover := Node3D.new()
		cover.position = Vector3(0.055 * side, 0, 0)
		var panel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.10, 0.02, 0.15)
		panel.mesh = bm
		panel.position = Vector3(0.05 * side, 0, 0)
		panel.material_override = steel
		cover.add_child(panel)
		_mount.add_child(cover)
		_covers.append({ node = cover, side = side })

	# The housing rises out from between them.
	_housing = Node3D.new()
	_mount.add_child(_housing)
	var body := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.09, 0.07, 0.13)
	body.mesh = hb
	body.material_override = steel
	_housing.add_child(body)

	# And the barrel extends out of the housing, pointing forward (-Z).
	_barrel = Node3D.new()
	_housing.add_child(_barrel)
	var tube := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018
	cm.bottom_radius = 0.024
	cm.height = 0.16
	cm.radial_segments = 10
	tube.mesh = cm
	tube.rotation_degrees = Vector3(90, 0, 0)
	tube.position = Vector3(0, 0, -0.08)
	var gun := StandardMaterial3D.new()
	gun.albedo_color = Color(0.14, 0.14, 0.16)
	gun.metallic = 0.95
	gun.roughness = 0.25
	tube.material_override = gun
	_barrel.add_child(tube)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, -0.17)
	_barrel.add_child(_muzzle)

func _make_shell() -> Dictionary:
	var n := Node3D.new()
	n.visible = false
	add_child(n)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.06
	cm.height = 0.9
	cm.radial_segments = 8
	cm.cap_top = false
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.material_override = Repulsors._glow(Color(1.0, 0.78, 0.35), 0.9)
	n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.35)
	l.light_energy = 0.0
	l.omni_range = 6.0
	l.shadow_enabled = false
	n.add_child(l)
	return { node = n, light = l, vel = Vector3.ZERO, life = 0.0, live = false }

func ready_to_fire() -> bool:
	return _cool <= 0.0 and charge >= DRAIN and deployed > 0.92

## Ask for the gun. Held or tapped — unlike the palms this one is a sustained weapon, so
## holding keeps it out and firing.
func request(wants: bool) -> void:
	_want = 1.0 if wants else _want
	if wants:
		_idle = 0.0

## Fire, if it is out and loaded. Returns recoil.
func fire(target: Vector3) -> Vector3:
	if not ready_to_fire() or _muzzle == null:
		return Vector3.ZERO
	var s: Dictionary = _take()
	if s.is_empty():
		return Vector3.ZERO
	_cool = COOLDOWN
	charge = maxf(0.0, charge - DRAIN)
	var muzzle := _muzzle.global_position
	var dir := (target - muzzle)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else -_muzzle.global_basis.z
	s.live = true
	s.life = LIFE
	s.vel = dir * SPEED
	s.node.visible = true
	s.node.position = muzzle
	s.node.look_at_from_position(muzzle, muzzle + dir, Vector3.UP)
	s.light.light_energy = 5.0
	fired.emit()
	Rumble.hit(0.55, 0.35, 0.12)
	# RECOIL, and a small one. This was 5.5 m/s of velocity PER SHOT, applied straight to
	# the flight model — so holding square emptied the magazine into the suit as thrust and
	# fired it backwards for a second. Jurek: "po przycisnieciu kwadratu... ma taki burst,
	# ze leci przez sekunde do tylu."
	#
	# A shoulder gun on a flying armour should be FELT and should not fly it. The kick is
	# now about a tenth of what it was, and the suit's own stabiliser absorbs it, which is
	# the point of having one.
	return -dir * 0.55

func _take() -> Dictionary:
	for s: Dictionary in _pool:
		if not s.live:
			return s
	return {}

func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	charge = minf(1.0, charge + RECHARGE * delta)

	# Stow itself when it has not been asked for in a while.
	_idle += delta
	if _idle > STOW_AFTER:
		_want = 0.0
	# Out faster than in: deploying should feel eager and stowing unhurried.
	var rate := DEPLOY_TIME if _want > deployed else DEPLOY_TIME * 1.8
	deployed = move_toward(deployed, _want, delta / rate)
	_pose()

	for s: Dictionary in _pool:
		if not s.live:
			continue
		s.life -= delta
		s.node.position += s.vel * delta
		if s.life <= 0.0:
			s.live = false
			s.node.visible = false
			s.light.light_energy = 0.0

## Three staged movements rather than one: the covers go first, the housing follows, and the
## barrel comes last. Doing them at once reads as one object scaling up; staggering them
## reads as a mechanism.
func _pose() -> void:
	if _mount == null:
		return
	var d := deployed
	var covers_t: float = clampf(d / 0.45, 0.0, 1.0)
	var rise_t: float = clampf((d - 0.25) / 0.5, 0.0, 1.0)
	var barrel_t: float = clampf((d - 0.6) / 0.4, 0.0, 1.0)

	for c in _covers:
		var node: Node3D = c.node
		node.rotation = Vector3(0, 0, c.side * -covers_t * 1.25)

	_housing.visible = d > 0.02
	_housing.position = Vector3(0, -0.055 * rise_t, 0)
	_housing.scale = Vector3.ONE * (0.35 + 0.65 * rise_t)
	_barrel.position = Vector3(0, 0, -0.06 * barrel_t)
	_barrel.visible = barrel_t > 0.02
