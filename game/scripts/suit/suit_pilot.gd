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
## AIM ASSIST. The cone the reticle counts as "on" a man, and how far the look stick is
## slowed while he is inside it — friction, the oldest trick in the book and the one that
## costs the player nothing, because it only ever makes the camera easier to hold still.
## Narrowed, and the friction lightened. Jurek: "jest zbyt mocne to automatyczne
## wspomaganie. Powinno być, ale nie takie mocne." Assistance the player can feel steering
## for him stops being help and starts being a fight over the camera.
const ASSIST_CONE := deg_to_rad(4.0)
const ASSIST_FRICTION := 0.74

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
var marks: ThreatMarks

## Per-hand shot envelope, 1 at the instant of firing and gone in a fifth of a second.
## This is the ONLY thing that tells the two arms apart while shooting: the authored "fire"
## pose is deliberately symmetric, so that pressing R1 cannot animate the left arm.
var _recoil := { "R": 0.0, "L": 0.0 }
var _buffer := { "R": 0.0, "L": 0.0 }
## Who the reticle is currently over. Shared by the friction, the magnetism and the HUD.
var locked_on: Node3D = null
var _last_step := 0
var _was_boosting := false
## How far the firing arm reaches past the shared stance, in radians.
const SHOT_REACH := 0.42
## The snap back through the shoulder. Cubed, so it is violent for two frames and then gone.
const SHOT_KICK := 0.30
const SHOT_DECAY := 5.0
## How long a press is remembered while the repulsor is still cooling.
const FIRE_BUFFER := 0.22
var _net_thrust := 0.0
var armour: ArmourDamage
## The two things this particular armour can do that no other one can. See gadgets.gd.
var gadgets: Gadgets
## Tony, once there is nothing left. Held rather than spawned on demand so the swap is
## instant — a frame with no body at all reads as the player being deleted.
var pilot_body: Node3D
var stripped := false
var on_foot_only := false

var is_mine: bool:
	get: return peer_id == Net.my_id

func setup(id: int, armor: String, stage: Stage) -> void:
	peer_id = id
	armor_id = armor
	_stage = stage

func _ready() -> void:
	add_to_group("player")
	add_to_group("hittable")
	gadgets = Gadgets.new()
	gadgets.name = "Gadgets"
	add_child(gadgets)
	marks = ThreatMarks.new()
	marks.name = "ThreatMarks"
	# In the WORLD, so the bracket does not inherit a body that banks and tumbles.
	get_parent().call_deferred("add_child", marks)
	# Something for incoming fire to hit; see scripts/combat/hurtbox.gd.
	add_child(Hurtbox.new(self, 0.62, 2.10))
	model = FlightModel.new()
	model.set_armor(armor_id)
	poses = Poses.new()

	# EVERYTHING THAT BOLTS ONTO THE RIG IS BUILT FIRST.
	#
	# _load_rig ends by attaching the exhaust, the turret and the laser to the new skeleton,
	# and each of those calls is guarded with `if x != null`. Loading the rig BEFORE they
	# existed meant all three guards were false and every one of them silently did nothing —
	# and nothing ever attached them afterwards. The suit has had NO exhaust at all since
	# the port: `_emitters` was empty, measured, which is why no amount of tuning the flame
	# ever made a repulsor appear. "Nie widac w ogole tych repulsorow" was exactly right.
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

	# Debris lives in the WORLD, like the bolts and the contrail: a shoulder pad that
	# follows the suit around after falling off it is not a shoulder pad that fell off.
	armour = ArmourDamage.new()
	armour.name = "ArmourDamage"
	get_parent().call_deferred("add_child", armour)

	# Now the rig, with somewhere for all of it to attach.
	_load_rig(armor_id)
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
		# CONNECTED HERE, NOT OFF visor.ready.
		#
		# add_child fires the child's _ready SYNCHRONOUSLY when the parent is already in the
		# tree, which it is — this is the parent's own _ready. So `ready` had been emitted
		# and gone before the connect ran, and every one of these handlers was dead code.
		# That is the whole of "dalej sie nie zmienia Spider-Man", and the armour bay not
		# responding either. The menu exists by now because Visor._ready made it.
		visor.menu.armor_chosen.connect(func(id: String): wear(id))
		# Switching hero replaces the whole entity, so it goes through Net and the arena
		# rebuilds — this node is about to be freed and must not try to react.
		visor.menu.hero_chosen.connect(func(id: String): Net.announce_hero(id))
		# The roster panel is fed rather than reaching for Net itself, so refresh it
		# whenever it comes up.
		visor.menu.opened.connect(func(): _feed_roster())
		_feed_roster()

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
	if armour != null:
		armour.bind(rig, skel)
		armour.ground_y = _stage.ground_y if _stage != null else 0.0
	if gadgets != null:
		gadgets.bind(skel, model, id)
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
	# FRICTION. Slowing the stick while the crosshair is over someone is what lets a thumb
	# hold an aim it could never hold steady on its own.
	locked_on = _assist_target()
	if locked_on != null:
		look *= ASSIST_FRICTION
	_hurt_cool = maxf(0.0, _hurt_cool - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
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
				rig.basis = model.view_basis
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
	# ON FOOT THE SAME STICK WALKS. Standing on the plate with the boots cold, pushing the
	# stick has to move the suit across the ground rather than light the thrusters — so the
	# flight controls stand down entirely until something asks it into the air. X, R2 and
	# any real deflection of the stick while already flying all count as asking.
	# WITH NO SUIT THERE IS NO FLYING. He walks, and that is all — which is the whole
	# point of the armour coming apart rather than a number reaching zero.
	# THE STICKS ARE ALSO THE GADGETS. L3 is what this armour does to survive, R3 is what
	# it does to the other man, and both change completely with the suit — see gadgets.gd.
	# Stripped, Tony has neither, because neither of them is Tony.
	if gadgets != null and not stripped:
		if Pad.just_pressed("hover"):
			gadgets.press("left")
		elif Pad.just_pressed("faceplate"):
			gadgets.press("right")
		model.agility = gadgets.agility()

	if stripped:
		on_foot_only = true
	var on_foot := (model.grounded and not Pad.pressed("up")) or stripped
	# The instant X is pressed with both feet down, kick clear of the plate. Without it the
	# climb rate alone has to fight a full g from a standing start, which reads as a hop.
	if model.grounded and Pad.just_pressed("up"):
		model.velocity.y = maxf(model.velocity.y, FlightModel.TAKEOFF_KICK)
		model.grounded = false

	var stick_fwd := 0.0 if on_foot else -move.y

	# AND IT STOPS ITSELF. "Strój powinien sam hamować." Let go of the stick and the suit
	# swings its repulsors round and kills the speed, rather than coasting on drag alone —
	# which at 300 m/s takes most of a kilometre and feels like ice. This is the retro burn
	# the flight model already has, asked for automatically instead of by a button: hands off
	# means stop, which is what a hovering machine should do.
	var thrust := maxf(stick_fwd, 0.0)
	var retro := maxf(-stick_fwd, 0.0)
	var brake_only := false
	if not on_foot and absf(stick_fwd) < AUTO_BRAKE_DEADZONE and model.speed > AUTO_BRAKE_FLOOR:
		brake_only = true
		# Eased in over the first few m/s so the last metre per second does not jerk.
		retro = clampf((model.speed - AUTO_BRAKE_FLOOR) / 12.0, 0.0, 1.0) * AUTO_BRAKE

	# Supersonic on R2, Mk II and up: the Mk I is a flying oil drum and has no business
	# breaking the sound barrier.
	var supersonic := Pad.thrust() > 0.35 and armor_id != "mk1"
	if supersonic and not _was_boosting:
		Sfx.play("boost", global_position, -2.0)
	_was_boosting = supersonic

	# AIMING SLOWS THE WORLD, the way Marvel's Spider-Man does it. Time dilation rather than
	# a zoom: it buys thinking time instead of magnifying the target, which is what makes a
	# snap decision at 300 m/s possible at all.
	Engine.time_scale = AIM_TIME_SCALE if aiming else 1.0

	var cmd := {
		thrust = thrust,
		retro = retro,
		brake_only = brake_only,
		lateral = 0.0 if on_foot else move.x,
		# The raw stick, for FlightModel._walk. Untouched by the flight mapping above,
		# because walking wants both axes as a direction rather than as throttle and slide.
		walk = move if on_foot else Vector2.ZERO,
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
		rig.basis = model.view_basis
	# Firing happens before the pose is solved, so a shot and the arm that threw it land on
	# the SAME frame. Solving first meant the recoil was always one frame stale.
	_shoot(aiming, delta)
	_turret(delta)
	_laser(delta)

	if skel != null:
		# FOOTSTEPS OFF THE STRIDE, not off a timer. The cycle already counts distance, so
		# every half-cycle is exactly one foot landing, at any speed, for free.
		if model.grounded and model.ground_speed > 0.6:
			var half := floori(model.stride_phase * 2.0)
			if half != _last_step:
				_last_step = half
				Sfx.play("step", global_position, lerpf(-18.0, -7.0, clampf(model.ground_speed / 7.0, 0.0, 1.0)))
		poses.update(delta, model, cmd, skel)
		_drive_shot_arms(delta)
		_drive_laser_arm()
		skel.update_pose(delta)

	if fx != null:
		# model.thrust_mag, not the stick: the flight model raises it while the stabiliser
		# carries the suit's weight, and that is the number the exhaust has to answer to.
		var hold: float = model.thrust_mag if model.hover_active else 0.0
		fx.drive(delta, thrust, cmd["lateral"], cmd["vertical"], retro, hold)
	if trail != null:
		# From the SOLES, which is where the boots are — a trail from the point mass hangs a
		# metre above the exhaust it is supposed to be coming out of.
		trail.update(delta, model.position - Vector3(0, FEET_DROP * 0.8, 0),
			model.speed, model.speed / 343.0, model.basis_)

	_update_threat_marks(delta)
	Rumble.set_flight(model.thrust_mag, model.g_force)
	if was_flying and model.grounded:
		var f := clampf(-falling / 40.0, 0.0, 1.0)
		Rumble.landing(f)
		Sfx.play("land", global_position, lerpf(-12.0, 1.0, f), lerpf(1.15, 0.8, f))
		if f > 0.25:
			poses.land_hard(f)

	if camera != null:
		camera.follow(delta, model.position, model.basis_, model.speed, aiming,
			model.spec.top_speed)
	if visor != null and visor.hud != null:
		# Real time, not scaled: the HUD must not sway in slow motion while aiming, or it
		# reads as the helmet lagging rather than the world slowing.
		visor.hud.target_locked = locked_on != null
		visor.hud.feed(delta / maxf(0.05, Engine.time_scale), look, model.speed, health, aiming)
		if guns != null:
			visor.hud.repulsor_l = guns.charge["L"]
			visor.hud.repulsor_r = guns.charge["R"]
			visor.hud.shots_max = Repulsors.SHOTS
			visor.hud.shots_l = guns.shots_left("L")
			visor.hud.shots_r = guns.shots_left("R")
			visor.hud.locked_l = guns.locked["L"]
			visor.hud.locked_r = guns.locked["R"]
		if turret != null:
			visor.hud.turret = turret.charge

## The laser's own posing: the firing arm straight out in front, and on the ground the
## torso twisted over legs that do not move.
func _drive_laser_arm() -> void:
	if laser == null or not laser.active or skel == null:
		return
	var side: String = SuitRig.SIDE["R"]
	# WORLD-aimed, down the suit's own nose. Asking in the parent frame — which is what the
	# authored poses speak — put the forearm 45 degrees above the horizon and the beam with
	# it, because the elbow's "forward" is forward OF A SHOULDER that had itself just been
	# turned. Jurek, twice: "ten laser teraz strzela jakoś do góry".
	var nose := -model.basis_.z
	skel.aim_joint_world("piv_shoulder" + side, (nose + Vector3(0, -0.06, 0)).normalized())
	skel.aim_joint_world("piv_elbow" + side, nose)
	# The other arm tucks in, out of the beam's way and out of the silhouette.
	var off: String = SuitRig.SIDE["L"]
	skel.add_offset("piv_shoulder" + off, Poses.Z_AX, 0.40)
	skel.add_offset("piv_elbow" + off, Poses.X_AX, -0.9)

	if not laser.in_air:
		# Split between the hips and the chest, because a spine turns along its length —
		# putting it all in one joint reads as the torso being unscrewed.
		skel.add_offset("piv_hips", Poses.Y_AX, laser.twist * 0.35)
		skel.add_offset("piv_chest", Poses.Y_AX, laser.twist * 0.65)

## Singles out the arm that just fired. Negative X on a shoulder is forward — the same
## convention the arm trail uses in Poses, where braking throws both arms out in front.
func _drive_shot_arms(delta: float) -> void:
	for hand: String in ["R", "L"]:
		var r: float = _recoil[hand]
		if r <= 0.0:
			continue
		_recoil[hand] = maxf(0.0, r - delta * SHOT_DECAY)
		# Reach holds the arm at the target; kick is the recoil going back through the
		# shoulder and dies almost immediately, so the two read as one punch.
		var kick: float = SHOT_KICK * r * r * r
		var side: String = SuitRig.SIDE[hand]
		skel.add_offset("piv_shoulder" + side, Poses.X_AX, -SHOT_REACH * r + kick)
		skel.add_offset("piv_elbow" + side, Poses.X_AX, -0.45 * r)

## RAPID-PRESS, NOT HOLD. Jurek's rule, from Marvel's Spider-Man: while aiming you tap R1
## and L1 as fast as you can and each tap is a shot. So these are just-pressed edges rather
## than held state — holding does nothing, which is deliberate. A held trigger is a machine
## gun; a tapped one is a fight you are participating in.
func _shoot(aiming: bool, delta: float) -> void:
	if guns == null or skel == null:
		return
	for hand: String in ["R", "L"]:
		# BUFFERED, NOT DROPPED. A press that lands during the cooldown used to be thrown
		# away, so mashing faster than seven taps a second simply lost most of them — and
		# these are meant to be mashed. Remembering the press for a moment and firing it
		# the instant the barrel clears turns "the button ignored me" into "it went as soon
		# as it could", which is the whole difference. Jurek: "nie da sie rapid-strzelac".
		_buffer[hand] = maxf(0.0, _buffer[hand] - delta)
		if Pad.just_pressed("fire_" + hand.to_lower()):
			_buffer[hand] = FIRE_BUFFER
		if _buffer[hand] <= 0.0:
			continue
		if not guns.ready_to_fire(hand):
			# The empty click, and only on the press that found it empty — held down it
			# would be a machine gun of error noises.
			if _buffer[hand] >= FIRE_BUFFER - 0.001:
				Sfx.flat("repulsor_dry", -12.0)
			continue
		# NO ARM, NO REPULSOR. The cost of losing a piece is the point of losing it.
		if armour != null and not armour.can_use(hand):
			continue
		_buffer[hand] = 0.0
		# SuitRig.SIDE, not `hand`: the models name their sides from the opposite
		# convention to the one the game flies in, so piv_palmL is the hand on the RIGHT of
		# the screen. Measured in tools/test_sides.gd through the real camera.
		var pivot_name: String = "piv_palm" + SuitRig.SIDE[hand]
		if not skel.has_pivot(pivot_name):
			continue
		var muzzle: Vector3 = (skel.pivots[pivot_name] as Node3D).global_position
		var target := Repulsors.aim_point(camera, muzzle)
		var kick := guns.fire(hand, muzzle, target, locked_on)
		_recoil[hand] = 1.0
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
		# YAW, NOT ROLL. Rolling about the direction of travel put the suit head-down and
		# swept the beam through a vertical disc, which is neither what it looks like nor
		# what it is for — Jurek: "on sie tak dziwnie obraca, ze jakby glowa w dol". A full
		# fast spin about the vertical axis is the move: the beam sweeps a horizontal
		# circle and cuts everything standing around him.
		model.yaw += step
	else:
		# THE WHOLE BODY TURNS ON THE GROUND TOO.
		#
		# It used to be a spine twist over planted feet, which is anatomically the honest
		# answer and completely invisible: measured at 112 degrees of twist, and Jurek's
		# reading of it was "on się nie obraca w ogóle". A move nobody can see is a move
		# that does not exist. So the body turns, more slowly than in the air, and the
		# twist stays on top as a lean into it — the legs are the pose layer's problem.
		model.yaw += step
		laser.twist = clampf(laser.twist + step * 0.18, -PI * 0.3, PI * 0.3)
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

## Hands the menu the room's state. Kept on this side of the line so SuitMenu stays
## renderable without a running SceneTree.
func _feed_roster() -> void:
	if visor == null or visor.menu == null:
		return
	visor.menu.active_hero = Net.local_hero
	var taken: Dictionary = {}
	for pid in Net.players:
		if pid != Net.my_id:
			taken[Net.players[pid].get("hero", "ironman")] = Net.players[pid].get("name", "PILOT")
	visor.menu.taken_heroes = taken

## THE WORLD-PARENTED PIECES GO WITH IT.
##
## The camera, the bolts and the contrail deliberately live in the arena rather than on the
## suit, because each of them would be wrong if it inherited the body's tumbling. That also
## means freeing the suit leaves all three behind — and switching hero frees the suit. A
## couple of changes of mind and the arena holds three chase cameras, of which the one still
## marked current belongs to an armour that no longer exists.
func _exit_tree() -> void:
	for n: Node in [camera, guns, trail]:
		if n != null and is_instance_valid(n):
			n.queue_free()

## ---- taking fire ---------------------------------------------------------------------
## The same method name every weapon in the game looks for, on both heroes and on the
## thugs. One contract rather than a type check per shooter: a bullet does not care what
## it hit, only that the thing knew how to be hurt.
##
## `health` is a FRACTION, because the integrity bar has always drawn it as one — so the
## damage numbers in EnemyKinds, which are in points, are divided by the armour's total
## here rather than everywhere they are written.
const MAX_HP := 100.0
## Seconds of grace after a hit lands. Without it a burst from a rifle at 120 Hz is one
## unbroken stream of damage and a crowd is instantly lethal.
const HURT_GRACE := 0.12
var _hurt_cool := 0.0
var _hurt_flash := 0.0

func take_hit(amount: float, from: Vector3, kind := "") -> void:
	if _hurt_cool > 0.0 or health <= 0.0:
		return
	# WHATEVER IS UP EATS SOME OF IT FIRST. A shield that only works from the front is a
	# decision; one that works everywhere is just a bigger health bar.
	if gadgets != null:
		amount *= gadgets.damage_through(from, global_position)
	if amount <= 0.01:
		Sfx.play("hit_metal", global_position, -8.0, 1.9)
		return
	_hurt_cool = HURT_GRACE
	health = clampf(health - amount / MAX_HP, 0.0, 1.0)
	_hurt_flash = 0.35
	Rumble.hit(0.7, 0.45, 0.14)
	Sfx.play("hit_metal", global_position, -2.0)
	# THE SUIT COMES APART AS IT GOES. Pieces are shed against the new figure, so a rocket
	# that takes a quarter of the bar strips a quarter of the armour in one go.
	if armour != null:
		armour.sync(health)
	if health <= 0.0 and not stripped:
		_strip()
	# Shoved by what hit you. Small — being knocked about by rifle fire would take the
	# flight model out of the player's hands, which is the one thing it must never do.
	var push := global_position - from
	push.y *= 0.3
	if push.length_squared() > 1e-4 and model != null:
		model.velocity += push.normalized() * amount * 0.06

## NOTHING LEFT. The armour is gone, and what is standing there is a man who cannot fly.
##
## The rig is hidden rather than freed: the pose system, the exhaust, the turret and the
## laser are all bound to its pivots, and tearing those out mid-frame is a crash looking
## for a place to happen. They are silenced instead, which is also the honest model — the
## hardware is still strapped to him, it just has no power.
func _strip() -> void:
	stripped = true
	if rig != null:
		rig.visible = false
	if fx != null:
		fx.drive(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
	# Tony himself. The adult body, tinted as an undersuit rather than a jacket.
	pilot_body = SuitLoader.load_suit("res://assets/suits/thug.glb")
	if pilot_body != null:
		add_child(pilot_body)
		pilot_body.position = Vector3(0, -FEET_DROP, 0)
		_wear_undersuit(pilot_body)
	if visor != null and visor.hud != null:
		visor.hud.set_armor_name("TONY STARK")

func _wear_undersuit(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var src = mesh.surface_get_material(i)
				if not (src is StandardMaterial3D):
					continue
				# Skin stays skin — the same material the thug names, and the same reason.
				if String((src as StandardMaterial3D).resource_name) == "mat_trim":
					continue
				var m: StandardMaterial3D = (src as StandardMaterial3D).duplicate()
				m.albedo_color = Color(0.11, 0.12, 0.14)
				m.albedo_texture = null
				m.emission_enabled = false
				m.metallic = 0.05
				m.roughness = 0.80
				(n as MeshInstance3D).set_surface_override_material(i, m)
	for c in n.get_children():
		_wear_undersuit(c)

## THE TWO WARNINGS. Polled rather than wired through signals: enemies come and go by the
## dozen and a connection per thug per frame is a lot of bookkeeping for something one
## loop over a group answers exactly.
func _update_threat_marks(delta: float) -> void:
	if marks == null:
		return
	marks.global_position = global_position

	# NOT FOR THE ARMOUR. Spider-sense is Spider-Man's, and only his — Jurek: "Iron Man ma
	# jakby... też ma spider sense, więc wyłącz mu to." The armour keeps the missile
	# bracket, which is a lock warning and not a sixth sense.
	marks.sense_on = 0.0

	# And the bracket, for a rocket that is actually chasing this body.
	var near := -1.0
	for n in get_tree().get_nodes_in_group("gunfire"):
		if n is Gunfire:
			near = maxf(near, (n as Gunfire).lock_on(self))
	marks.locked = near >= 0.0
	marks.lock_near = maxf(0.0, near)

## The man under the crosshair, if there is one. Angle, not distance: the player is
## pointing at somebody, and the nearest body to the SUIT is very often not him.
func _assist_target() -> Node3D:
	if camera == null:
		return null
	var eye := camera.global_position
	var aim := -camera.global_transform.basis.z
	var best: Node3D = null
	var best_ang := ASSIST_CONE
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Enemy) or not is_instance_valid(n):
			continue
		var e: Enemy = n
		if e.state == Enemy.DOWN:
			continue
		var to := (e.global_position + Vector3(0, 0.9, 0)) - eye
		var d := to.length()
		if d < 2.0 or d > 400.0:
			continue
		var ang := aim.angle_to(to / d)
		if ang < best_ang:
			best_ang = ang
			best = e
	return best
