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

## A GROWN MAN. They were wearing pilot.glb, which is a thirteen-year-old boy — it was
## simply the only humanoid the project had. Jurek: "oni powinni być realistycznymi ludźmi".
const BODY := "res://assets/suits/thug.glb"
const GRAVITY := 22.0
## How long a stagger locks him out after a solid hit.
const STAGGER_TIME := 0.42
## Seconds of being glued per web hit past the threshold.
const WEB_TIME := 4.5
## He stops being a threat below this, and lies there rather than vanishing — a fight you
## cannot see the results of is a fight you cannot read.
const CORPSE_TIME := 12.0

signal died(enemy: Enemy)
## Fired the moment he commits to a volley, so the player can be warned before it lands.
signal warned(enemy: Enemy, delay: float)

enum { SEEK, ATTACK, STAGGER, WEBBED, DOWN }
## What he has talked himself into this moment.
enum { PRESS, HOLD, FLEE }

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
var _juggle := 0.0
var _telegraph := 0.0
var _fall_way := 1.0

## How long he takes aim before firing, and the longer beat an RPG gets.
const AIM_TELL := 0.85
const ROCKET_TELL := 1.35

## Is he winding up on you right now, and how long is left?
func telegraphing() -> float:
	return _telegraph

## Is the thing he is about to throw a rocket?
func telegraph_is_rocket() -> bool:
	return _telegraph > 0.0 and bool(spec.get("rocket", false))
var _mood := PRESS
var _mind := 0.0
var _drift := 1.0

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
					# SKIN IS NOT CLOTHING. The tint repaints every surface, which turned
					# his face, neck and hands the same colour as his coat — a man in a
					# balaclava. The model names that material `mat_trim` and the name
					# survives the load, so the one place this can be fixed is here.
					if String((src as StandardMaterial3D).resource_name) == "mat_trim":
						continue
					var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
					var pick: Color = spec["trim"] if i % 3 == 1 else spec["body"]
					m.albedo_color = pick
					m.albedo_texture = null
					# NO GLOW. They were lit from within to solve being invisible on a
					# near-black plate, and that worked — but glowing men are not what
					# Jurek wants on screen: "nie podświetlaj ich bez potrzeby". The
					# readability now comes from the colours themselves being mid-value
					# rather than from the material emitting, which is the honest fix.
					m.emission_enabled = false
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
		_telegraph = 0.0

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
		_telegraph = 0.0
		velocity = Vector3.ZERO

## KNOCKED INTO THE AIR, and held there. Jurek's launcher: Spider-Man punches a man
## upwards, goes up with him and juggles him until he either dies or is dropped.
##
## Being juggled is a state rather than just an upward velocity, because the point is that
## he cannot do anything while it lasts — a thug who keeps swinging at you mid-combo is
## not being juggled, he is falling past you.
func launch(up: float, carry: Vector3 = Vector3.ZERO) -> void:
	if state == DOWN:
		return
	state = STAGGER
	_stagger = 0.9
	velocity = Vector3(carry.x, up, carry.z)
	_juggle = 1.4

## Keeps him hanging. Called once per hit in the air; each connection buys a little more
## time before gravity gets him back.
func juggle(up: float) -> void:
	if state == DOWN:
		return
	_juggle = maxf(_juggle, 0.55)
	velocity.y = maxf(velocity.y, up)
	_stagger = maxf(_stagger, 0.4)
	state = STAGGER

func is_juggled() -> bool:
	return _juggle > 0.0

## FALLING OVER. Jurek: "nawet nie ma animacji zabicia." The `down` pose folds the limbs
## and that is half of it; the other half is that a dead man does not stay standing, and
## the body has to go from vertical to flat where the player can see it happen.
##
## A rotation rather than a ragdoll. A ragdoll is a physics body, a solver and a pile of
## tuning, and what it buys over a half-second topple is variety in a thing the player
## looks at once. This is honest about what it is.
const TOPPLE_TIME := 0.55

func _topple(delta: float) -> void:
	if rig == null:
		return
	var t: float = clampf(_dead_for / TOPPLE_TIME, 0.0, 1.0)
	# Eased out, so he goes over quickly and settles rather than rotating at a constant
	# rate like a door.
	var eased := 1.0 - pow(1.0 - t, 3.0)
	rig.rotation.x = _fall_way * (PI * 0.5) * eased
	# NO SINKING. The model pivots about its SOLES, so rotating it a quarter turn about
	# that point already lays the body flat AT floor level — the feet stay put and the head
	# swings down to meet the ground. Pushing it down as well buried him, which is why only
	# his limbs were showing: "oni są pod mapą i widać ich kończyny tylko".
	rig.position.y = sin(absf(rig.rotation.x)) * 0.12

func _die(from: Vector3) -> void:
	state = DOWN
	_dead_for = 0.0
	Sfx.play("body_drop", global_position, -4.0)
	# Forwards or backwards depending on which way he was hit, which is the one bit of
	# variety that costs nothing and reads immediately.
	var facing := global_transform.basis * Vector3(0, 0, -1)
	_fall_way = -1.0 if facing.dot((global_position - from).normalized()) > 0.0 else 1.0
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
		_topple(delta)
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
	if _juggle > 0.0:
		_juggle -= delta
	if not is_on_floor():
		# A tenth of gravity while he is being juggled. Real gravity ends a combo in about
		# a third of a second, which is not long enough to press a second button.
		velocity.y -= GRAVITY * (0.12 if _juggle > 0.0 else 1.0) * delta
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

	# HE HAS TO NOTICE YOU FIRST. Everything on the plate used to run at the player from
	# anywhere — "jak jestem mega daleko, to oni już biegną do mnie" — which made a street
	# read as a swarm rather than as people who happen to be standing there.
	if dist > float(spec["notice"]):
		_idle_about(delta)
		state = SEEK
		return

	# AND HE KNOWS HE WILL LOSE. Jurek: "oni nie powinni być tak chętnie gonić tego, bo
	# wiedzą, że umrą". Nerve decides whether he closes, holds where he is, or backs off,
	# and it is re-rolled on a slow timer rather than every frame so he commits to a choice
	# for a second or two instead of vibrating between them.
	_mind -= delta
	if _mind <= 0.0:
		_mind = randf_range(1.1, 2.6)
		var scared := 1.0 - float(spec["nerve"])
		var hurt := 1.0 - clampf(hp / maxf(1.0, float(spec["hp"])), 0.0, 1.0)
		# RUNNING IS EARNED, not rolled. A cold dice-throw sent men sprinting away from a
		# fight they had not yet lost, which reads as broken rather than as frightened.
		# What makes a man break is being HURT, or watching something he cannot reach hang
		# in the air above him — so those are the two things that open the door.
		var airborne := _target != null and _target.global_position.y - global_position.y > 8.0
		var panic := hurt * 0.75 + scared * (0.25 if airborne else 0.0)
		var roll := randf()
		if roll < panic:
			_mood = FLEE
		elif roll < panic + scared * 0.7:
			_mood = HOLD
		else:
			_mood = PRESS

	var want := Vector3.ZERO
	match _mood:
		FLEE:
			want = -flat.normalized() * float(spec["speed"]) * 0.9
		HOLD:
			# Shuffling sideways rather than standing at attention: a man keeping his
			# distance still moves, and a line of statues reads as a bug.
			var side := flat.normalized().cross(Vector3.UP)
			want = side * float(spec["speed"]) * 0.35 * _drift
			if dist > reach * 2.2:
				want += flat.normalized() * float(spec["speed"]) * 0.4
		_:
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

	# THE TELEGRAPH. He shoulders the weapon and aims before anything comes out, and says
	# so — Jurek wants a second of warning above Spider-Man's head, and a warning that
	# arrives with the bullet is not a warning.
	if _telegraph > 0.0:
		_telegraph -= delta
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if _telegraph <= 0.0:
			_burst = int(spec["burst"])
			_burst_gap = 0.0
		return

	if in_range and _cool <= 0.0:
		if spec["ranged"]:
			# VOLLEYS. They fired at their own rate forever, which is a hose rather than a
			# fight — Jurek: "oni nie powinni strzelać non stop, tylko w takich falach co
			# pięć sekund". A burst, then a long enough gap to move in it.
			_cool = float(spec["volley"]) * randf_range(0.82, 1.18)
			# A rocket is announced for longer than a rifle, because it is the one thing
			# you are meant to get out of the way of rather than tank.
			_telegraph = ROCKET_TELL if spec["rocket"] else AIM_TELL
			warned.emit(self, _telegraph)
		else:
			_cool = float(spec["rate"])
			_swing()

## Fists and knives. No projectile — if he is in reach when the swing lands, it lands.
func _swing() -> void:
	if _target == null:
		return
	var d := global_position.distance_to(_target.global_position)
	if d > float(spec["reach"]) * 1.35:
		return
	poses.strike()
	Sfx.play("punch" if kind != "brute" else "punch_big", global_position, -3.0)
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
	# The rifle is the heavier of the two synthesised shots; an RPG has its own launch.
	if spec["rocket"]:
		Sfx.play("rpg_launch", muzzle, -1.0)
	else:
		Sfx.play("gunshot_rifle" if kind == "rifle" else "gunshot", muzzle, -5.0)
	guns.fire(muzzle, aim, float(spec["muzzle_speed"]), float(spec["damage"]),
		float(spec["blast"]) if spec["rocket"] else 0.0,
		_target if spec["rocket"] else null)

## Turns to face what he is fighting. Only the body — nothing here pitches.
func _face(delta: float) -> void:
	if _target == null:
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return
	# NEGATED, both of them. A Node3D faces its own -Z, so the yaw that points it along
	# `to` is atan2(-to.x, -to.z); atan2(to.x, to.z) is that plus a half turn, which aims
	# him exactly away from you. Every thug in the game walked at the player backwards.
	var want := atan2(-to.x, -to.z)
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

## Milling about, out of range and with nothing to do. Not standing perfectly still: a
## street of motionless men reads as a scene that has not loaded.
func _idle_about(delta: float) -> void:
	_mind -= delta
	if _mind <= 0.0:
		_mind = randf_range(1.8, 4.0)
		_drift = -_drift
		_idle_dir = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var amble: float = float(spec["speed"]) * 0.22
	velocity.x = move_toward(velocity.x, _idle_dir.x * amble, 8.0 * delta)
	velocity.z = move_toward(velocity.z, _idle_dir.z * amble, 8.0 * delta)

var _idle_dir := Vector3.FORWARD
