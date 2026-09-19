class_name SuitPilot
extends Node3D
## One player in an armour. Networked from its first line — see scripts/net/net.gd.
##
## AUTHORITY: the peer this suit belongs to runs the flight model locally and publishes
## where it ended up. Everyone else interpolates towards what they were told. Flying never
## waits for the network, and nobody can be pushed around by someone else's lag.
##
## The model imported from the browser build brings its own contract with it
## (assets/suits/CONTRACT.md): +Y up, the body faces -Z, the origin is at the SOLES, and the
## suit is 1.95 m tall. The flight model is a point mass one metre above the soles, which is
## why the mesh hangs a metre below the model's position rather than sitting on it.

const SUITS := {
	"mk1": "res://assets/suits/mk1.glb",
	"mk2": "res://assets/suits/mk2.glb",
	"mk3": "res://assets/suits/mk3.glb",
	"mk42": "res://assets/suits/mk42.glb",
	"mk50": "res://assets/suits/mk50.glb",
}
## Point mass to soles, from CONTRACT.md.
const FEET_DROP := 1.0
## How far the world slows while the aim trigger is held.
const AIM_TIME_SCALE := 0.22
## Hands off the stick: how hard the suit stops itself, as a fraction of full retro.
const AUTO_BRAKE := 0.55
const AUTO_BRAKE_DEADZONE := 0.12
## Below this it stops braking, so it settles instead of hunting around zero.
const AUTO_BRAKE_FLOOR := 1.5

@export var peer_id := 1
@export var armor_id := "mk1"
var health := 1.0

var model: FlightModel
var rig: Node3D
var skel: SuitRig                          ## the pose machinery, indexed off `rig`
var poses: Poses
var fx: Thrusters
var guns: Repulsors
var turret: ShoulderTurret
var laser: WristLaser
var trail: Contrail
var camera: ChaseCamera
var visor: Visor
var _stage: Stage

## What a remote suit is heading towards. Position and rotation are published, never
## velocity: a remote suit that dead-reckons off stale velocity overshoots corners and
## visibly snaps back, which reads far worse than being 120 ms behind.
var _net_pos := Vector3.ZERO
var _net_basis := Basis.IDENTITY
var _net_thrust := 0.0

var is_mine: bool:
	get: return peer_id == Net.my_id

func setup(id: int, armor: String, stage: Stage) -> void:
	peer_id = id
	armor_id = armor
	_stage = stage

func _ready() -> void:
	model = FlightModel.new()
	model.set_armor(armor_id)
	_load_rig(armor_id)
	poses = Poses.new()
	fx = Thrusters.new()
	add_child(fx)
	# Bolts live in the WORLD, not on the suit: one parented to the armour would fly along
	# with it, which is a laser pointer rather than a projectile.
	guns = Repulsors.new()
	get_parent().call_deferred("add_child", guns)
	# Both of these own geometry bolted to the rig, so they live on the SUIT — but their
	# projectiles are world objects, handled inside each.
	turret = ShoulderTurret.new()
	add_child(turret)
	laser = WristLaser.new()
	add_child(laser)
	# The trail is parented to the WORLD, not the suit: puffs must stay where they were made.
	trail = Contrail.new()
	get_parent().call_deferred("add_child", trail)
	if is_mine:
		# The camera is a sibling in the world, not a child of the suit. A camera parented to
		# something that pitches and rolls inherits every bit of that, so the horizon tumbles
		# with the body — which is exactly what makes six-degree-of-freedom flight unplayable.
		camera = ChaseCamera.new()
		camera.name = "ChaseCamera"
		get_parent().call_deferred("add_child", camera)
		visor = Visor.new()
		visor.name = "Visor"
		add_child(visor)
		visor.ready.connect(func():
			visor.menu.armor_chosen.connect(func(id: String): wear(id)))

func _load_rig(id: String) -> void:
	if rig != null:
		rig.queue_free()
	var path: String = SUITS.get(id, SUITS["mk3"])
	# Through SuitLoader rather than load(): the models are parsed at runtime when the
	# editor has never imported them, which is the difference between a game that has a
	# suit in it and one that does not. See scripts/suit/suit_loader.gd.
	rig = SuitLoader.load_suit(path)
	if rig == null:
		push_warning("[suit] no rig for %s" % id)
		return
	add_child(rig)
	skel = SuitRig.new()
	skel.index(rig)
	skel.set_pose("stand")
	# Re-parented onto whatever rig is worn now: the pivots are new objects every time an
	# armour loads, and a plume left on a discarded rig never appears again.
	if fx != null:
		fx.attach(skel)
	if turret != null:
		turret.attach(skel)
	if laser != null:
		laser.attach(skel)
	if visor != null and visor.hud != null:
		visor.hud.set_armor_name(SuitSpecs.get_spec(id).name)

func wear(id: String) -> void:
	armor_id = id
	model.set_armor(id)
	_load_rig(id)
	if is_mine:
		Net.announce_armor(id)

func _physics_process(delta: float) -> void:
	if is_mine:
		_step_local(delta)
	else:
		_step_remote(delta)

func _step_local(delta: float) -> void:
	var look := Pad.look(delta)
	var move := Pad.move()
	var aiming := Pad.retro() > 0.25          # L2 — see AIM_TIME_SCALE

	# THE MENU TAKES THE CONTROLS. While it is open the suit holds station and the stick
	# belongs to the list — flying blind behind an open menu is how a player loses a suit he
	# was not even in control of.
	if visor != null and visor.menu != null:
		if visor.menu.is_open:
			visor.menu.step(delta / maxf(0.05, Engine.time_scale))
			Engine.time_scale = 1.0
			var hold := { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0,
				look = Vector2.ZERO, roll = 0.0, boost = false, aiming = false, firing = false }
			if _stage != null:
				model.ground_y = _stage.ground_y
			model.step(delta, hold)
			global_position = model.position
			if rig != null:
				rig.position = Vector3(0, -FEET_DROP, 0)
				rig.basis = model.basis_
			if skel != null:
				poses.update(delta, model, hold, skel)
				skel.update_pose(delta)
			if camera != null:
				camera.follow(delta, model.position, model.basis_, model.speed, false,
					model.spec.top_speed)
			return
		elif Pad.just_pressed("menu"):
			visor.menu.open()
			return

	# THE STICKS FLY IT. Jurek's revision: "R2 do naddźwiękowej, a latanie to po prostu gałki
	# i X do góry." So there is no throttle button at all — pushing the left stick forward IS
	# the throttle, X climbs, and R2 is reserved for the one speed decision that matters.
	#
	# This is a better fit for a suit than a trigger was. A trigger is a pedal; a stick is a
	# direction, and a flying armour is aimed rather than driven.
	var stick_fwd := -move.y

	# AND IT STOPS ITSELF. "Strój powinien sam hamować." Let go of the stick and the suit
	# swings its repulsors round and kills the speed, rather than coasting on drag alone —
	# which at 300 m/s takes most of a kilometre and feels like ice. This is the retro burn
	# the flight model already has, asked for automatically instead of by a button: hands off
	# means stop, which is what a hovering machine should do.
	var thrust := maxf(stick_fwd, 0.0)
	var retro := maxf(-stick_fwd, 0.0)
	var brake_only := false
	if absf(stick_fwd) < AUTO_BRAKE_DEADZONE and model.speed > AUTO_BRAKE_FLOOR:
		brake_only = true
		# Eased in over the first few m/s so the last metre per second does not jerk.
		retro = clampf((model.speed - AUTO_BRAKE_FLOOR) / 12.0, 0.0, 1.0) * AUTO_BRAKE

	# Supersonic on R2, Mk II and up: the Mk I is a flying oil drum and has no business
	# breaking the sound barrier.
	var supersonic := Pad.thrust() > 0.35 and armor_id != "mk1"

	# AIMING SLOWS THE WORLD, the way Marvel's Spider-Man does it. Time dilation rather than
	# a zoom: it buys thinking time instead of magnifying the target, which is what makes a
	# snap decision at 300 m/s possible at all.
	Engine.time_scale = AIM_TIME_SCALE if aiming else 1.0

	var cmd := {
		thrust = thrust,
		retro = retro,
		brake_only = brake_only,
		lateral = move.x,
		vertical = (1.0 if Pad.pressed("up") else 0.0) - (1.0 if Pad.pressed("down") else 0.0),
		look = look,
		roll = 0.0,
		boost = supersonic,
		aiming = aiming,
		firing = Pad.pressed("fire_r") or Pad.pressed("fire_l"),
	}
	if _stage != null:
		model.ground_y = _stage.ground_y

	var was_flying := not model.grounded
	var falling := model.velocity.y
	model.step(delta, cmd)

	global_position = model.position
	if rig != null:
		rig.position = Vector3(0, -FEET_DROP, 0)
		rig.basis = model.basis_
	if skel != null:
		poses.update(delta, model, cmd, skel)
		skel.update_pose(delta)

	if fx != null:
		fx.drive(delta, thrust, cmd["lateral"], cmd["vertical"], retro)
	if trail != null:
		# From the SOLES, which is where the boots are — a trail from the point mass hangs a
		# metre above the exhaust it is supposed to be coming out of.
		trail.update(delta, model.position - Vector3(0, FEET_DROP * 0.8, 0),
			model.speed, model.speed / 343.0, model.basis_)

	_shoot(aiming)
	_turret(delta)
	_laser(delta)

	Rumble.set_flight(model.thrust_mag, model.g_force)
	if was_flying and model.grounded:
		var f := clampf(-falling / 40.0, 0.0, 1.0)
		Rumble.landing(f)
		if f > 0.25:
			poses.land_hard(f)

	if camera != null:
		camera.follow(delta, model.position, model.basis_, model.speed, aiming,
			model.spec.top_speed)
	if visor != null and visor.hud != null:
		# Real time, not scaled: the HUD must not sway in slow motion while aiming, or it
		# reads as the helmet lagging rather than the world slowing.
		visor.hud.feed(delta / maxf(0.05, Engine.time_scale), look, model.speed, health, aiming)
		if guns != null:
			visor.hud.repulsor_l = guns.charge["L"]
			visor.hud.repulsor_r = guns.charge["R"]
		if turret != null:
			visor.hud.turret = turret.charge

## RAPID-PRESS, NOT HOLD. Jurek's rule, from Marvel's Spider-Man: while aiming you tap R1
## and L1 as fast as you can and each tap is a shot. So these are just-pressed edges rather
## than held state — holding does nothing, which is deliberate. A held trigger is a machine
## gun; a tapped one is a fight you are participating in.
func _shoot(aiming: bool) -> void:
	if guns == null or skel == null:
		return
	for hand: String in ["R", "L"]:
		if not Pad.just_pressed("fire_" + hand.to_lower()):
			continue
		var pivot_name: String = "piv_palm" + hand
		if not skel.has_pivot(pivot_name):
			continue
		var muzzle: Vector3 = (skel.pivots[pivot_name] as Node3D).global_position
		var target := Repulsors.aim_point(camera, muzzle)
		var kick := guns.fire(hand, muzzle, target)
		if kick != Vector3.ZERO:
			# RECOIL MOVES THE SUIT. Firing downward should lift you — a repulsor is a
			# thruster you are pointing at something else, so it has to push back.
			model.velocity += kick
			if visor != null and visor.hud != null:
				visor.hud.repulsor_l = guns.charge["L"]
				visor.hud.repulsor_r = guns.charge["R"]

## SQUARE HOLDS THE TURRET OUT. Unlike the palms this is a sustained weapon: holding keeps
## it deployed and firing, letting go leaves it out for a few seconds and then it folds
## itself away. The third of a second it takes to deploy is a real cost — you cannot
## snap-shoot with it — and paying that is what makes it machinery rather than a hotkey.
func _turret(delta: float) -> void:
	if turret == null:
		return
	var held := Pad.pressed("turret")
	turret.request(held)
	if held and turret.ready_to_fire():
		var muzzle := global_position
		var kick := turret.fire(Repulsors.aim_point(camera, muzzle))
		if kick != Vector3.ZERO:
			model.velocity += kick
			if visor != null and visor.hud != null:
				visor.hud.turret = turret.charge
				visor.hud.flash_turret()

## TRIANGLE AND CIRCLE TOGETHER, and only on a charged suit. The move owns the body for its
## whole duration: the suit turns and carries the beam through whatever is in front of it,
## which is the difference between a cutting laser and a gun. Two different turns, because
## in the air there is nothing to push against and the airframe rolls about its own axis,
## while on the ground it pivots about the feet.
func _laser(delta: float) -> void:
	if laser == null:
		return
	laser.trickle(delta)
	if not laser.active:
		if Pad.pressed("interact") and Pad.pressed("suit_toggle") and laser.ready_to_fire:
			laser.start(not model.grounded)
		return
	var step := laser.turn_for(delta)
	if laser.in_air:
		# Airborne: roll about the direction of travel, so the beam sweeps a disc.
		model.roll += step
	else:
		# Grounded: turn on the spot at chest height.
		model.yaw += step
	laser.update(delta)

func _step_remote(delta: float) -> void:
	# 120 ms of smoothing: enough that a dropped packet is invisible, short enough that a
	# shot you dodge is a shot you actually dodged.
	var k := 1.0 - exp(-delta / 0.12)
	global_position = global_position.lerp(_net_pos, k)
	if rig != null:
		rig.basis = rig.basis.slerp(_net_basis, k)

## The chase camera. Sits behind and above, and is dragged rather than bolted on: a camera
## rigidly attached to the suit turns the world instead of turning the suit, and at speed
## that is nauseating. Distance opens up with speed so fast flight feels fast.
func _drive_camera(delta: float) -> void:
	var back := 6.0 + clampf(model.speed / 40.0, 0.0, 6.0)
	var up := 2.0 + clampf(model.speed / 120.0, 0.0, 2.0)
	var want := model.basis_ * Vector3(0, up, back)
	var target := model.position + want
	var k := 1.0 - exp(-delta / 0.10)
	camera.global_position = camera.global_position.lerp(target, k)
	camera.look_at(model.position + model.basis_ * Vector3(0, 0.6, -8.0), Vector3.UP)
	# A little FOV with speed. Small on purpose — this is the cheapest way to sell speed and
	# also the easiest to overdo into a fisheye.
	camera.fov = lerpf(camera.fov, 70.0 + clampf(model.speed / 380.0, 0.0, 1.0) * 18.0, k)

# ---- replication -----------------------------------------------------------------------

func publish() -> void:
	if not is_mine or not Net.online:
		return
	_sync.rpc(model.position, model.basis_.get_rotation_quaternion(), model.thrust_mag)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync(p: Vector3, q: Quaternion, th: float) -> void:
	_net_pos = p
	_net_basis = Basis(q)
	_net_thrust = th
