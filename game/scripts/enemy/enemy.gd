class_name Enemy
extends CharacterBody3D
## One thug. Which one it is comes from EnemyKinds.
##
## A CharacterBody3D rather than the hand-rolled integrators the players use, and for a
## reason: the players need exact, tuned, reproducible motion — a suit that stops in 0.85 s
## from 150 m/s is a measured number this project defends. A thug needs to walk round a
## corner and not fall through the plate, which is exactly what move_and_slide is for.
##
## It also gives them a collider for free, and that turns out to be the thing that makes
## combat work at all: every weapon in the game already raycasts, and until now those rays
## passed through empty air because there was nothing solid to find.

const BODY := "res://assets/suits/pilot.glb"
const GRAVITY := 22.0
## How long a stagger locks him out after a solid hit.
const STAGGER_TIME := 0.42
## Seconds of being glued per web hit past the threshold.
const WEB_TIME := 4.5
## He stops being a threat below this, and lies there rather than vanishing — a fight you
## cannot see the results of is a fight you cannot read.
const CORPSE_TIME := 12.0

signal died(enemy: Enemy)

enum { SEEK, ATTACK, STAGGER, WEBBED, DOWN }

var kind := "brawler"
var spec: Dictionary = {}
var hp := 30.0
var state := SEEK
var webbing := 0.0              ## web hits landed, against spec.web
var glued := 0.0                ## seconds left stuck

var rig: Node3D
var skel: SuitRig
var poses: EnemyPoses
var guns: Gunfire               ## shared, handed in by the squad

var _target: Node3D
var _cool := 0.0
var _stagger := 0.0
var _dead_for := 0.0
var _burst := 0
var _burst_gap := 0.0
var _stride := 0.0
var _hurt_flash := 0.0

func setup(k: String, gunfire: Gunfire) -> void:
	kind = k
	spec = EnemyKinds.spec(k)
	hp = spec["hp"]
	guns = gunfire

func _ready() -> void:
	add_to_group("hittable")
	add_to_group("enemy")
	if spec.is_empty():
		spec = EnemyKinds.spec(kind)
		hp = spec["hp"]

	# The capsule is what every ray in the game finally has something to hit.
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var s: float = spec["scale"]
	cap.radius = 0.38 * s
	cap.height = 1.75 * s
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)

	_load_body()
	poses = EnemyPoses.new()

func _load_body() -> void:
	rig = SuitLoader.load_suit(BODY)
	if rig == null:
		push_warning("[enemy] no body model")
		return
	add_child(rig)
	var s: float = spec["scale"]
	rig.scale = Vector3(s, s, s)
	_tint(rig)
	skel = SuitRig.new()
	skel.index(rig)
	_weapon()

## Thugs are the same model in different colours, which is honest about what they are and
## costs nothing. The materials are shared by the cached scene, so each one gets its own.
func _tint(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var src = mesh.surface_get_material(i)
				if src is StandardMaterial3D:
					var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
					var pick: Color = spec["trim"] if i % 3 == 1 else spec["body"]
					m.albedo_color = pick
					m.albedo_texture = null
					# LIT FROM WITHIN, a little. The map is deliberately near-black with
					# white lines, and these were authored dark on top of that — so they
					# spawned, walked in and were measured, and Jurek still reported "nie
					# ma". Five of them were on the plate at the time. A dark figure on a
					# dark floor at forty metres is not there as far as the player is
					# concerned, and being correct in a group count is no defence.
					#
					# Same lever as the armour: emission touches the character and nothing
					# else, where turning the lights up would take the map with it.
					m.emission_enabled = true
					m.emission = pick
					m.emission_energy_multiplier = 0.34
					m.metallic = 0.10
					m.roughness = 0.72
					(n as MeshInstance3D).set_surface_override_material(i, m)
	for c in n.get_children():
		_tint(c)

## Something in his hands, so you can tell a rifle from a knife before it goes off.
func _weapon() -> void:
	if skel == null or not spec.get("ranged", false) and kind != "knifer":
		if kind != "knifer":
			return
	var hand := "piv_palm" + SuitRig.SIDE["R"]
	if not skel.has_pivot(hand):
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match kind:
		"knifer": bm.size = Vector3(0.03, 0.28, 0.05)
		"pistol": bm.size = Vector3(0.06, 0.16, 0.22)
		"rifle":  bm.size = Vector3(0.07, 0.12, 0.86)
		"rpg":    bm.size = Vector3(0.14, 0.14, 1.25)
		_:        return
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.75, 0.80) if kind == "knifer" else Color(0.10, 0.11, 0.13)
	m.metallic = 0.85
	m.roughness = 0.35
	mi.material_override = m
	mi.position = Vector3(0, -0.10, -0.18)
	(skel.pivots[hand] as Node3D).add_child(mi)

# ---- taking it ---------------------------------------------------------------------

## Called by everything the player shoots. The name is the contract — Gunfire, Repulsors,
## the turret and the laser all look for exactly this.
func take_hit(amount: float, from: Vector3, _kind := "") -> void:
	if state == DOWN:
		return
	hp -= amount
	_hurt_flash = 0.18
	if hp <= 0.0:
		_die(from)
		return
	# Knocked back away from whatever hit him, less so if he is big.
	var push := (global_position - from)
	push.y = 0.0
	if push.length_squared() > 1e-4:
		var resist: float = spec.get("knockback_resist", 0.0)
		velocity += push.normalized() * amount * 0.45 * (1.0 - resist)
	if state != WEBBED:
		state = STAGGER
		_stagger = STAGGER_TIME

## A web landing on him. THE BIG ONES TAKE MORE, which is the whole reason the brute is in
## the game: "duzych (ktorych spiderman trudniej zwiazac)". One flick glues a thug; a brute
## needs four, and his webbing rots faster, so it has to be four in short order.
func web_hit(amount := 1.0) -> void:
	if state == DOWN:
		return
	webbing += amount
	if webbing >= float(spec["web"]):
		webbing = 0.0
		state = WEBBED
		glued = WEB_TIME
		velocity = Vector3.ZERO

func _die(from: Vector3) -> void:
	state = DOWN
	_dead_for = 0.0
	var push := (global_position - from)
	push.y = 0.0
	if push.length_squared() > 1e-4:
		velocity = push.normalized() * 4.0 + Vector3.UP * 2.0
	died.emit(self)

# ---- the loop -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash -= delta

	if state == DOWN:
		_dead_for += delta
		_fall(delta)
		if _dead_for > CORPSE_TIME:
			queue_free()
		_pose(delta)
		return

	_target = _pick_target()

	match state:
		STAGGER:
			_stagger -= delta
			if _stagger <= 0.0:
				state = SEEK
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		WEBBED:
			# Glued: he cannot move, and the webbing rots at his own rate.
			glued -= delta * float(spec.get("web_decay", 1.0))
			velocity.x = 0.0
			velocity.z = 0.0
			if glued <= 0.0:
				state = SEEK
		_:
			_fight(delta)

	_fall(delta)
	_face(delta)
	_pose(delta)

func _fall(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()

## Closest player, and only one that is actually there. The roster changes when heroes are
## swapped, so this is looked up rather than cached.
func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("player"):
		if not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var d := global_position.distance_to((n as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = n
	return best

func _fight(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _target == null:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 12.0 * delta)
		state = SEEK
		return

	var to := _target.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	var reach: float = spec["reach"]

	# CLOSE THE GAP, then hold it. A crowd that walks into you and keeps pushing is a
	# crowd that shoves the player around the map; they stop where they can reach.
	var want := Vector3.ZERO
	if dist > reach * 0.9:
		want = flat.normalized() * float(spec["speed"])
	elif dist < reach * 0.55:
		want = -flat.normalized() * float(spec["speed"]) * 0.6
	# ELBOW ROOM. Everyone is walking to the same point, so without this a wave arrives as
	# one column standing inside itself — visible in the very first render of a crowd. It
	# is not pathfinding, just enough shove to keep a mob looking like a mob.
	want += _separation() * float(spec["speed"]) * 0.8

	velocity.x = move_toward(velocity.x, want.x, 26.0 * delta)
	velocity.z = move_toward(velocity.z, want.z, 26.0 * delta)

	# A ranged thug needs the height too; a melee one only cares about the floor distance.
	var in_range := dist <= reach if not spec["ranged"] else to.length() <= reach
	state = ATTACK if in_range else SEEK

	if _burst > 0:
		_burst_gap -= delta
		if _burst_gap <= 0.0:
			_shoot()
			_burst -= 1
			_burst_gap = 0.09
		return

	if in_range and _cool <= 0.0:
		_cool = float(spec["rate"])
		if spec["ranged"]:
			_burst = int(spec["burst"])
			_burst_gap = 0.0
		else:
			_swing()

## Fists and knives. No projectile — if he is in reach when the swing lands, it lands.
func _swing() -> void:
	if _target == null:
		return
	var d := global_position.distance_to(_target.global_position)
	if d > float(spec["reach"]) * 1.35:
		return
	poses.strike()
	if _target.has_method("take_hit"):
		_target.take_hit(float(spec["damage"]), global_position, kind)

func _shoot() -> void:
	if guns == null or _target == null:
		return
	var muzzle := global_position + Vector3(0, 1.45 * float(spec["scale"]), 0)
	var aim := (_target.global_position + Vector3(0, 0.6, 0)) - muzzle
	if aim.length_squared() < 1e-4:
		return
	aim = aim.normalized()
	# Scatter, so a line of riflemen is a threat rather than a sniper wall.
	var sp: float = spec["spread"]
	aim = (aim + Vector3(randf_range(-sp, sp), randf_range(-sp, sp), randf_range(-sp, sp))).normalized()
	poses.strike()
	guns.fire(muzzle, aim, float(spec["muzzle_speed"]), float(spec["damage"]),
		float(spec["blast"]) if spec["rocket"] else 0.0)

## Turns to face what he is fighting. Only the body — nothing here pitches.
func _face(delta: float) -> void:
	if _target == null:
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return
	var want := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-delta * 7.0))

func _pose(delta: float) -> void:
	if skel == null or poses == null:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z).length()
	_stride += flat * delta / 1.55
	poses.update(delta, self, flat, _stride, skel)
	skel.update_pose(delta)

## A push away from whoever is standing too close, falling off with distance. Flat — being
## shoved upwards by a neighbour is how a crowd starts climbing itself.
const PERSONAL := 2.1

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other) or not (other is Node3D):
			continue
		var d := global_position - (other as Node3D).global_position
		d.y = 0.0
		var len := d.length()
		if len < 0.01 or len > PERSONAL:
			continue
		push += d / len * (1.0 - len / PERSONAL)
	return push.limit_length(1.0)
