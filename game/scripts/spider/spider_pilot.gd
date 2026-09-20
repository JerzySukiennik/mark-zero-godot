class_name SpiderPilot
extends Node3D
## The Spider-Man player.
##
## The headline ability, in Jurek's words: flying as Iron Man, the other player should be
## able to look at the suit, press a button, fire a web at it, hold on, swing, and be
## carried along. That is what TETHERS are — one per hand, each able to grab a different
## thing, which is also how a swing between two anchors works.
##
## He does not fly. Everything he does in the air is gravity plus rope, and the only input
## that touches him mid-swing is a weight shift. That restraint is the point: an Iron Man
## who can hover and a Spider-Man who can also hover are the same character in two costumes.

## Tried in order. The Iron Spider is being modelled; until it lands the Mk 50 stands in,
## because a player with no body at all cannot be playtested and "NIe widac stroju" has
## already cost this project a session.
const BODIES := [
	"res://assets/suits/ironspider.glb",
	"res://assets/suits/mk50.glb",
	"res://assets/suits/pilot.glb",
]
## How far the fingers fold for the thwip, from assets/suits/ironspider-notes.md. The
## pivot's frame is authored so the SIGN is the same on both hands, which is why this is
## one number rather than a mirrored pair.
const THWIP_ANGLE := deg_to_rad(95.0)
## How far the trigger has to be squeezed to throw a web. Well past the resting slop on a
## DualShock, and short of the hard stop so it does not need a deliberate clench.
const TRIGGER_FIRE := 0.35
## How long a bumper press is remembered while that hand is still reloading.
const FIRE_BUFFER := 0.22
## Mid-air hops, and what each one is worth.
const MAX_HOPS := 2
const HOP_UP := 7.5
const HOP_FWD := 9.0
## Where a web looks for an anchor: up and ahead, not wherever the camera happens to point.
const SWING_ELEVATION := deg_to_rad(52.0)
## How wide a fan of rays is tried before giving up.
const SWING_FAN := 5
const SWING_SPREAD := deg_to_rad(26.0)
## The pull into the arc when a web lands: it shortens and hauls, rather than going taut
## and leaving you hanging.
## A NUDGE, not a yank. At 0.88 and 6 m/s the catch threw him upwards every single time —
## "nie powinno to tak jakby skakac za kazdym razem". Enough to turn a fall into an arc and
## no more; the arc itself is supposed to do the rest of the work.
const CATCH_SHORTEN := 0.975
const CATCH_LIFT := 2.2
const FEET_DROP := 1.0
const AIM_TIME_SCALE := 0.35

var peer_id := 1
var model: SpiderModel
var rig: Node3D
var skel: SuitRig
var camera: ChaseCamera
var visor: Visor
var health := 1.0
var marks: ThreatMarks

var legs := SpiderLegs.new()
var poses := SpiderPoses.new()
var fight := SpiderCombat.new()
var shots: WebShot
## Counts down while the back legs are braced for a landing.
var _brace := 0.0

## One per hand. Right is R1, left is L1 — the same hands the armour fires from, so the
## two characters do not need separate muscle memory.
var tether := { "R": WebTether.new(), "L": WebTether.new() }
var line := { "R": null, "L": null }
## Rises while a hand is throwing a web, and drives that arm out towards the anchor.
var _throw := { "R": 0.0, "L": 0.0 }
## Trigger edges, so holding fires ONE web rather than one per frame.
var _held := { "R": false, "L": false }
var _buffer := { "R": 0.0, "L": 0.0 }
var _swing_hand := "L"
## WEB FLUID, and it actually runs out. Jurek: "zrób, żeby temu Spider-Manowi jakby
## naprawdę się zużywały te strzały." The HUD has drawn two tanks since the day he got
## one; until now they were decoration that read "full" forever.
##
## Generous on purpose — running dry mid-swing is a death sentence, not a decision — so
## the cost is on THROWN webs and the tanks refill quickly.
const WEB_MAX := 24.0
const WEB_PER_SHOT := 1.0
const WEB_PER_SWING := 0.5
const WEB_REFILL := 3.2
var web_fluid := { "R": WEB_MAX, "L": WEB_MAX }
var _whoosh := 0.35
## How long the wind-up has been going, and how fast he turns during it.
var _wind := 0.0
const SPIN_RATE := 9.0
## How far away a thug can be and still be the one it goes to.
const HURL_RANGE := 55.0
var _last_step := 0
## What he is carrying, if anything.
var carried: Prop = null
const CARRY_RANGE := 9.0
var _hops := MAX_HOPS
## Webs that landed this frame and still owe the player their pull into the arc.
var _catch_pending := { "R": false, "L": false }

var _stage: Stage
var _shoot_t := 0.0

var is_mine: bool:
	get: return peer_id == Net.my_id

func setup(id: int, stage: Stage) -> void:
	peer_id = id
	_stage = stage

func _ready() -> void:
	add_to_group("player")
	add_to_group("hittable")
	marks = ThreatMarks.new()
	marks.name = "ThreatMarks"
	# In the WORLD, so the bracket does not inherit a body that banks and tumbles.
	get_parent().call_deferred("add_child", marks)
	# Something for incoming fire to hit; see scripts/combat/hurtbox.gd.
	add_child(Hurtbox.new(self, 0.52, 1.85))
	model = SpiderModel.new()
	model.position = position
	_load_body()
	for hand: String in ["R", "L"]:
		var w := WebLine.new()
		w.name = "Web" + hand
		w.build()
		# The strands live in the WORLD. Parented to the body they would be dragged along
		# by every swing, which is the one thing a rope must never do.
		get_parent().call_deferred("add_child", w)
		line[hand] = w
	shots = WebShot.new()
	shots.name = "WebShots"
	# In the WORLD: a glob in flight and a splat on a wall both stay where they are while
	# he swings away, which is the entire point of throwing one.
	get_parent().call_deferred("add_child", shots)
	if is_mine:
		camera = ChaseCamera.new()
		camera.name = "ChaseCamera"
		get_parent().call_deferred("add_child", camera)
		visor = Visor.new()
		visor.name = "Visor"
		add_child(visor)
		# Same as SuitPilot: NOT off visor.ready, which has already fired by the time
		# add_child returns.
		visor.menu.hero_chosen.connect(func(id: String): Net.announce_hero(id))
		visor.menu.opened.connect(func(): _feed_roster())
		_feed_roster()
		# He is not wearing an armour, so the panels must not claim he is.
		visor.hud.use_palette("spider")
		visor.menu.use_palette("spider")
		visor.hud.set_armor_name("IRON SPIDER")
		visor.hud.ammo_label = "WEB FLUID"
		visor.hud.ammo_rows = ["L", "R"]

func _load_body() -> void:
	for path: String in BODIES:
		rig = SuitLoader.load_suit(path)
		if rig != null:
			break
	if rig == null:
		push_warning("[spider] no body model found")
		return
	add_child(rig)
	skel = SuitRig.new()
	skel.index(rig)
	skel.set_pose("stand")

# ---- the loop ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_mine:
		return

	_hurt_cool = maxf(0.0, _hurt_cool - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	var move := Pad.move()
	var look := Pad.look(delta)
	# NO AIM TRIGGER. L2 is the left web now, and it was ALSO slowing the world to a third
	# — so every left-handed web throw put the game into slow motion, which is most of what
	# "to jest takie napiete i w ogole" was describing.
	var aiming := false

	# THE MENU. Spider-Man simply had no branch for it — the touchpad did nothing at all
	# once you were wearing the Iron Spider, which also meant no way back to Iron Man.
	if visor != null and visor.menu != null:
		if visor.menu.is_open:
			visor.menu.step(delta)
			return
		elif Pad.just_pressed("menu"):
			visor.menu.open()
			return

	# Reeling is on the d-pad rather than the stick, because the stick is already steering
	# the swing and hauling yourself in is something you do DURING one.
	var reel := (1.0 if Pad.pressed("up") else 0.0) - (1.0 if Pad.pressed("down") else 0.0)

	# AIMING, on L2. Jurek: "L2 przytrzymanie to powinno być celowanie, czyli że jak
	# przytrzymam L2, to jest celowanie i mogę bardzo dużo razy przyciskać R1 albo L1."
	# So the left trigger stopped being a second web the moment it became a modifier — one
	# finger cannot both hold a rope and steady a shot.
	aiming = Pad.retro() > TRIGGER_FIRE
	Engine.time_scale = AIM_TIME_SCALE if aiming else 1.0

	# BOTH BUMPERS: WEB IT, SPIN, THROW IT AT SOMEBODY.
	#
	# Jurek's description, which the first cut got wrong in every part: "żeby strzelał
	# siecią w ten kosz na śmieci z dwóch rąk i zaczął się tak kręcić i po prostu jak się
	# puszcza, to wtedy to rzuca w najbliższego barbarzyńcy, nawet jak jest za nim, to po
	# prostu troszeczkę się obraca jeszcze i rzuca w niego."
	#
	# So: two lines, not two separate web shots; a wind-up you can see; and a release that
	# FINDS a target rather than throwing where the camera happens to point. Checked before
	# the single-bumper throws below, or grabbing would always fire two webs on the way in.
	var both := Pad.pressed("fire_r") and Pad.pressed("fire_l")
	if carried != null:
		_wind += delta
		# The spin. Fast, and it is what says "this is charging" without a meter.
		model.yaw += SPIN_RATE * delta
		# Held out to the side at arm's length, swung round with him.
		var swing := model.basis_ * Vector3(0.0, 0.6, -1.7)
		carried.global_position = model.position + swing
		if not both:
			_hurl_carried()
		return
	if both:
		var got := _reach_for_prop()
		if got != null:
			carried = got
			got.grab()
			_wind = 0.0
			# BOTH HANDS. The lines are cosmetic here — the prop is carried, not towed —
			# but two of them is the whole read of the move.
			for hand: String in ["R", "L"]:
				_throw[hand] = 1.0
			Sfx.play("thwip", model.position, -2.0)
			Rumble.landing(0.2)
			return

	# R1 AND L1 THROW A WEB. Separate from the triggers, which hold on to one: "R1... reka
	# powinna tak strzelic... i to powinno z nadgarstka mu leciec takie i na scianie
	# zostawiac". Bumpers throw, triggers hold — and keeping the two apart is what lets
	# each mean one thing.
	for hand: String in ["R", "L"]:
		# Buffered the same way the armour's repulsors are: a press during the cooldown is
		# remembered rather than dropped, so mashing throws as fast as the hand can reload
		# instead of silently swallowing most of the taps.
		_buffer[hand] = maxf(0.0, _buffer[hand] - delta)
		if Pad.just_pressed("fire_" + hand.to_lower()):
			_buffer[hand] = FIRE_BUFFER
		if _buffer[hand] <= 0.0:
			continue
		if shots == null or not shots.ready_to_fire(hand):
			continue
		_buffer[hand] = 0.0
		var wrist := _web_point(hand)
		var aim := -camera.global_transform.basis.z if camera != null else model.basis_ * Vector3(0, 0, -1)
		if web_fluid[hand] < WEB_PER_SHOT:
			Sfx.flat("repulsor_dry", -16.0)
			continue
		if shots.fire(hand, wrist, aim):
			web_fluid[hand] -= WEB_PER_SHOT
			_throw[hand] = 1.0
			Rumble.hit(0.35, 0.2, 0.08)

	# NO WEBS ON A WALL. Jurek: "jak jest na tej scianie, to nie powinny sie wlaczac sieci,
	# czyli R2 i L2 nie powinny byc wlaczone w ogole" — and L2 has a different job there
	# anyway, which is to make him run. Any line still out is dropped the moment he lands
	# on a face, because hanging off a web while clinging to a wall is neither.
	var rope := Vector3.ZERO
	if model.stuck:
		for hand: String in ["R", "L"]:
			_held[hand] = false
			if tether[hand].state != WebTether.IDLE:
				tether[hand].release()
	# ONE TRIGGER, TWO HANDS. R2 swings; which arm throws is the game's problem, not the
	# player's — "mają być dalej dwie, tylko że się automatycznie dobierać". It alternates,
	# so a second web thrown while the first is still out uses the free hand and you end up
	# hanging from both, which is how a two-line swing happens without a second button.
	if not model.stuck:
		_service_swing(delta)

	# Both ropes are stepped whatever fired them, because either hand may be carrying one.
	for hand: String in ["R", "L"]:
		var t: WebTether = tether[hand]
		# WebTether's constants are already per-kilogram, so this is an acceleration and
		# goes straight into the model. Dividing by the mass again would have made the rope
		# almost seventy times too weak.
		rope += t.step(delta, model.position, model.velocity, reel)

		# THE CATCH, the frame the line goes tight. A rope that only goes taut leaves you
		# swinging under the anchor from wherever you happened to be; converting the drop
		# into an arc needs the line pulled IN and the body lifted, once. This is the
		# "automatycznie trochę go tak jakby podnosi i już zaczyna lecieć łukiem" part, and
		# without it the first swing reads as being stopped rather than picked up.
		if _catch_pending[hand] and t.state == WebTether.ATTACHED:
			_catch_pending[hand] = false
			t.rest_length = maxf(WebTether.MIN_LENGTH, t.rest_length * CATCH_SHORTEN)
			model.velocity.y = maxf(model.velocity.y, 0.0) + CATCH_LIFT
			# And it keeps whatever speed he already had, pointed along the arc rather
			# than at the anchor, which is what stops a catch feeling like a jerk.
			var to_anchor := (t.anchor_point() - model.position).normalized()
			var along := model.velocity - to_anchor * model.velocity.dot(to_anchor)
			model.velocity = along + to_anchor * maxf(0.0, model.velocity.dot(to_anchor)) * 0.35

	# AIR HOPS. Jurek's loop: swing, let go, "w powietrzu może przycisnąć X parę razy, żeby
	# poskakać sobie w powietrzu", then web again. Without them a release is the end of the
	# run — you fall, and the next anchor is always slightly out of reach. They are limited
	# and refill on the ground or on a fresh web, so the loop is web-swing-hop rather than
	# free flight, which is Iron Man's job.
	var hopped := false
	if not model.grounded and not model.stuck and Pad.just_pressed("up") and _hops > 0:
		_hops -= 1
		hopped = true
		var fwd := model.basis_ * Vector3(0, 0, -1)
		model.velocity.y = maxf(model.velocity.y, 0.0) + HOP_UP
		model.velocity += fwd * HOP_FWD
		Rumble.landing(0.3)
	if model.grounded or model.stuck:
		_hops = MAX_HOPS

	# A move owns the body while it runs. Steering out of a launcher or a dodge would make
	# every attack cancellable into a walk, which is the difference between a fight and a
	# set of buttons that occasionally play animations.
	var busy := fight.state != SpiderCombat.FREE
	var cmd := {
		walk = Vector2.ZERO if busy else move,
		look = look,
		jump = model.grounded and Pad.just_pressed("up"),
		aiming = aiming,
		# On a wall X pushes OFF it rather than jumping, and the left trigger sprints up
		# the face instead of throwing a web.
		release = model.stuck and Pad.just_pressed("up"),
		wall_run = Pad.retro() > TRIGGER_FIRE,
	}
	# THE FISTS. Fed the buttons and the direction the camera is looking, and it decides
	# what the body is doing — the pilot only asks afterwards whether it may still move.
	var facing := -camera.global_transform.basis.z if camera != null else -model.basis_.z
	facing.y = 0.0
	fight.update(delta, model, {
		walk = move,
		facing = facing.normalized() if facing.length_squared() > 1e-4 else -model.basis_.z,
		light = Pad.just_pressed("light"),
		heavy = Pad.pressed("heavy"),
		heavy_down = Pad.just_pressed("heavy"),
		dodge = Pad.just_pressed("dodge"),
	}, get_tree())

	if _stage != null:
		model.ground_y = _stage.ground_y
	# Handed in every frame so the model can do its own sweeps. It is a RefCounted and has
	# no tree of its own.
	model.space = get_world_3d().direct_space_state
	var was_down := not model.grounded
	var fell := model.velocity.y
	model.step(delta, cmd, rope)

	global_position = model.position
	if rig != null:
		rig.position = Vector3(0, -FEET_DROP, 0)
		rig.basis = model.basis_
	if skel != null:
		_pose(delta)
		# The legs come out whenever he is off the ground — they are what he lands and
		# catches himself on, so they belong to being airborne rather than to a button.
		if _brace > 0.0:
			_brace -= delta
		# R3 SENDS THEM AFTER PEOPLE. Off the ground they are already out, so on the
		# pavement this is the only thing that deploys them — and the only attack Spider-Man
		# has that answers somebody standing behind him.
		if Pad.just_pressed("faceplate") and not legs.lashing():
			legs.begin_lash(self, get_tree().get_nodes_in_group("enemy"))
			Sfx.play("thwip", global_position, -5.0, 0.7)
		for who in legs.service_lash(delta):
			if is_instance_valid(who) and who.has_method("take_hit"):
				who.take_hit(SpiderLegs.LASH_DAMAGE, global_position, "legs")
				Sfx.play("punch", (who as Node3D).global_position, -1.0, 1.25)
		legs.drive(delta, (not model.grounded) or _brace > 0.0, skel, self)
		skel.update_pose(delta)

	if was_down and model.grounded:
		var force: float = clampf(-fell / 30.0, 0.0, 1.0)
		poses.land_hard(force)
		Sfx.play("land", global_position, lerpf(-14.0, -1.0, force), lerpf(1.2, 0.85, force))
		# THE LEGS CATCH HIM. Jurek: coming down off a swing "one powinny sie tak otwierac
		# i tak hamowac go od tylu". They are already out in the air; holding them out
		# through the landing is what turns a fold-away into a brace.
		_brace = 0.55 + clampf(-fell / 40.0, 0.0, 1.0) * 0.45

	for hand: String in ["R", "L"]:
		web_fluid[hand] = minf(WEB_MAX, web_fluid[hand] + WEB_REFILL * delta)
	if visor != null and visor.hud != null:
		visor.hud.shots_max = int(WEB_MAX)
		visor.hud.shots_l = int(web_fluid["L"])
		visor.hud.shots_r = int(web_fluid["R"])
		visor.hud.locked_l = web_fluid["L"] < WEB_PER_SHOT
		visor.hud.locked_r = web_fluid["R"] < WEB_PER_SHOT

	_update_threat_marks(delta)
	# THE RUSH OF AIR. Only while actually carried by a line and actually quick, retriggered
	# on a distance clock so it does not machine-gun at the bottom of an arc.
	var hanging: bool = tether["R"].state == WebTether.ATTACHED or tether["L"].state == WebTether.ATTACHED
	if hanging and model.speed > 16.0:
		_whoosh -= delta * (model.speed / 26.0)
		if _whoosh <= 0.0:
			_whoosh = 1.0
			Sfx.play("swing", global_position, lerpf(-16.0, -4.0, clampf(model.speed / 45.0, 0.0, 1.0)))
	else:
		_whoosh = 0.35

	if model.grounded and model.ground_speed > 0.6:
		var half := floori(model.stride_phase * 2.0)
		if half != _last_step:
			_last_step = half
			Sfx.play("step", global_position, lerpf(-20.0, -10.0, clampf(model.ground_speed / 9.0, 0.0, 1.0)))

	_draw_webs()

	if camera != null:
		camera.follow(delta, model.position, model.view_basis, model.speed, aiming, 120.0)
	if visor != null and visor.hud != null:
		visor.hud.feed(delta / maxf(0.05, Engine.time_scale), look, model.speed, health, aiming)
		visor.hud.repulsor_l = web_fluid["L"] / WEB_MAX
		visor.hud.repulsor_r = web_fluid["R"] / WEB_MAX

## HELD ON THE TRIGGERS. Jurek: "pod R2 powinna byc prawa siec, a pod L2 lewa siec."
##
## Hold and you are on the web; let go and you drop. That is both what every Spider-Man
## game does and the better fit for an analogue trigger, which has a natural "still holding
## it" state that a face button does not — and it frees both thumbs for the sticks, which
## during a swing are steering and looking.
## R2, for both hands. Picks whichever is free, preferring to alternate.
func _service_swing(delta: float) -> void:
	var pull := Pad.thrust()
	var held := pull > TRIGGER_FIRE
	var was: bool = _held["R"] or _held["L"]

	if not held:
		for hand: String in ["R", "L"]:
			_held[hand] = false
			_throw[hand] = maxf(0.0, _throw[hand] - delta * 4.0)
			if tether[hand].state != WebTether.IDLE:
				tether[hand].release()
		return

	for hand: String in ["R", "L"]:
		_throw[hand] = maxf(0.0, _throw[hand] - delta * 4.0)
	if was:
		return

	# Fresh press: use the hand that is not already carrying one, alternating otherwise.
	var pick := "R" if _swing_hand == "L" else "L"
	if tether[pick].state != WebTether.IDLE:
		pick = "R" if pick == "L" else "L"
	if tether[pick].state != WebTether.IDLE:
		return
	_swing_hand = pick
	_held[pick] = true
	_fire_swing(pick)

## Throws ONE web from one hand. The trigger handling lives in _service_swing now; this
## is only the part that finds something to stick to and sticks to it.
func _fire_swing(hand: String) -> void:
	var t: WebTether = tether[hand]
	# Aim from the CAMERA, not from the hand. The player is pointing with the reticle, and
	# a cone taken from the wrist disagrees with it by several degrees at a hundred metres —
	# which feels like the web missing something you were plainly looking at.
	var from := _hand_point(hand)
	var eye := camera.global_position if camera != null else from
	var aim := -camera.global_transform.basis.z if camera != null else -model.basis_.z
	# AIMED HIGH AND AHEAD, not wherever the camera points.
	#
	# This is the difference between the mechanic Jurek described and the one that was
	# here. Pointing the reticle at a building and firing gives you a rope to a wall; what
	# he asked for is "strzela siecią wysoko i automatycznie trochę go tak jakby podnosi i
	# już zaczyna lecieć łukiem". So the web looks for an anchor UP and AHEAD of where he is
	# travelling — a fan of rays at about fifty degrees of elevation — and takes the best
	# one. The camera only decides which way "ahead" is.
	var target := _find_swing_anchor(from)
	var hit_at: Vector3 = target[1]
	var node: Node3D = target[0]

	if web_fluid[hand] < WEB_PER_SWING:
		return
	if node != null and t.fire(from, node, hit_at):
		web_fluid[hand] -= WEB_PER_SWING
		_throw[hand] = 1.0
		Rumble.landing(0.25)
		# AND IT CATCHES. A rope that simply goes taut leaves you hanging under the anchor;
		# a swing has to convert the fall into an arc. Shortening the line as it lands and
		# adding a lift does exactly that, and it is why the first swing feels like being
		# picked up rather than like stopping.
		_catch_pending[hand] = true
		# Landing a web is also what refills the hops, so the loop pays for itself.
		_hops = MAX_HOPS

## Looks for something to swing from: up, and ahead of where he is going.
##
## Returns [node, world point] or [null, INF]. A fan rather than a single ray, because one
## ray through a gap between towers misses everything and the throw silently does nothing —
## which is what "tylko czasami strzela" was.
func _find_swing_anchor(from: Vector3) -> Array:
	var space := get_world_3d().direct_space_state
	if space == null:
		return [null, Vector3.INF]

	# "Ahead" is where he is MOVING if he is moving, and where he is facing if he is not.
	# Using the camera alone meant a glance sideways mid-swing threw the next web sideways.
	var ahead := model.basis_ * Vector3(0, 0, -1)
	var flat := Vector3(model.velocity.x, 0.0, model.velocity.z)
	if flat.length() > 6.0:
		ahead = ahead.lerp(flat.normalized(), 0.6).normalized()

	var best_node: Node3D = null
	var best_at := Vector3.INF
	var best_score := -1e9
	var right := ahead.cross(Vector3.UP).normalized()

	for i in SWING_FAN:
		# Centred fan: 0, -1, +1, -2, +2 ... so the straight-ahead ray is tried first.
		var step := (i + 1) / 2
		var side := (-1.0 if i % 2 == 1 else 1.0) * step
		var yawed := ahead.rotated(Vector3.UP, side * SWING_SPREAD)
		var dir := (yawed * cos(SWING_ELEVATION) + Vector3.UP * sin(SWING_ELEVATION)).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * WebTether.MAX_RANGE)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not (hit.collider is Node3D):
			continue
		var at: Vector3 = hit.position
		if at.y < from.y + 8.0:
			continue          # not an anchor to swing from, just a wall in the way
		# Prefer high and straight ahead. Height buys arc; a wide angle costs control.
		var score := (at.y - from.y) - absf(side) * 14.0
		if score > best_score:
			best_score = score
			best_node = hit.collider
			best_at = at
	# Nothing overhead — fall back to whatever the player is actually pointing at, so
	# aiming deliberately at a low anchor still works.
	if best_node == null and camera != null:
		var eye := camera.global_position
		var aim := -camera.global_transform.basis.z
		var suit := WebTether.pick(eye, aim, _targets())
		if suit != null:
			return [suit, Vector3.INF]
	return [best_node, best_at]

## Everything a web can stick to. Right now that is the armours — which is exactly the
## feature asked for — and the list is built fresh because the roster changes.
func _targets() -> Array:
	var out: Array = []
	var p := get_parent()
	if p == null:
		return out
	for c in p.get_children():
		if c is SuitPilot:
			out.append(c)
	return out

## The web shooter itself, on the underside of the wrist. The Iron Spider model carries a
## `piv_websL/R` for exactly this; the palm is where a repulsor would go.
func _web_point(hand: String) -> Vector3:
	var side: String = SuitRig.SIDE[hand]
	var n := "piv_webs" + side
	if skel != null and skel.has_pivot(n):
		return (skel.pivots[n] as Node3D).global_position
	return _hand_point(hand)

func _hand_point(hand: String) -> Vector3:
	var name: String = "piv_palm" + SuitRig.SIDE[hand]
	if skel != null and skel.has_pivot(name):
		return (skel.pivots[name] as Node3D).global_position
	return model.position

func _draw_webs() -> void:
	var cam := camera.global_position if camera != null else global_position
	for hand: String in ["R", "L"]:
		var t: WebTether = tether[hand]
		var w: WebLine = line[hand]
		if w == null:
			continue
		if t.state == WebTether.IDLE:
			w.draw_web(Vector3.ZERO, Vector3.ZERO, 0.0, 0.0, cam)
			continue
		var from := _hand_point(hand)
		var to := t.anchor_point()
		# Slack is the only cue that says whether the rope is carrying you. Before it has
		# landed there is no rest length yet, so it flies dead straight.
		var slack := 0.0
		if t.state == WebTether.ATTACHED:
			slack = maxf(0.0, t.rest_length - from.distance_to(to))
		w.draw_web(from, to, slack, t.reach, cam)

# ---- posing -----------------------------------------------------------------------------

## Spider-Man's stances live in SpiderPoses, authored from scratch. He was borrowing the
## armour's six, which describe an aircraft, so standing still he stood like a suit of
## armour and hanging off a web he held formation.
func _pose(delta: float) -> void:
	poses.update(delta, model, {
		"R": tether["R"].state == WebTether.ATTACHED,
		"L": tether["L"].state == WebTether.ATTACHED,
	}, skel, fight)

	# THE THROWING ARM, layered on top: the hand that fired reaches along its web, so which
	# hand threw it is readable without looking at the HUD.
	for hand: String in ["R", "L"]:
		var th: float = _throw[hand]
		if th <= 0.001:
			continue
		var side: String = SuitRig.SIDE[hand]
		skel.add_offset("piv_shoulder" + side, SpiderPoses.X_AX, -1.15 * th)
		skel.add_offset("piv_elbow" + side, SpiderPoses.X_AX, -0.65 * th)
		# The thwip: two fingers folded to the palm, one clean rotation, authored so the
		# sign is the same on both hands (assets/suits/ironspider-notes.md).
		skel.add_offset("piv_fingers" + side, SpiderPoses.X_AX, THWIP_ANGLE * th)




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

## Same rule as SuitPilot: the strands and the camera are parented to the world so they do
## not swing with the body, so they have to be cleaned up by hand when he is replaced.
func _exit_tree() -> void:
	var doomed: Array = [camera, line["R"], line["L"]]
	for n: Node in doomed:
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
## TOUGHER THAN THE ARMOUR. Jurek: "zrób, żeby strój też mu wolniej się rozwalał, bo to
## jest jakieś w ogóle nieporozumienie, że tak wszystko się szybko rozwala." He is harder
## to hit than a suit hovering in the open, and a nanotech weave does not lose plates —
## so the same rifle burst costs him a third of what it costs Tony.
const MAX_HP := 260.0
## Seconds of grace after a hit lands. Without it a burst from a rifle at 120 Hz is one
## unbroken stream of damage and a crowd is instantly lethal.
const HURT_GRACE := 0.12
var _hurt_cool := 0.0
var _hurt_flash := 0.0

func take_hit(amount: float, from: Vector3, kind := "") -> void:
	if _hurt_cool > 0.0 or health <= 0.0:
		return
	# A dodge is worth most of a hit but not all of it: true invulnerability frames make
	# one button the answer to everything, and then there is only one button.
	if fight != null:
		amount *= fight.damage_scale()
	_hurt_cool = HURT_GRACE
	health = clampf(health - amount / MAX_HP, 0.0, 1.0)
	_hurt_flash = 0.35
	Rumble.hit(0.7, 0.45, 0.14)
	Sfx.play("punch", global_position, -4.0)
	# Shoved by what hit you. Small — being knocked about by rifle fire would take the
	# flight model out of the player's hands, which is the one thing it must never do.
	var push := global_position - from
	push.y *= 0.3
	if push.length_squared() > 1e-4 and model != null:
		model.velocity += push.normalized() * amount * 0.06

## THE TWO WARNINGS. Polled rather than wired through signals: enemies come and go by the
## dozen and a connection per thug per frame is a lot of bookkeeping for something one
## loop over a group answers exactly.
func _update_threat_marks(delta: float) -> void:
	if marks == null:
		return
	marks.global_position = global_position

	# Spider-sense: is anything winding up on ME, and how soon. The closest tell wins, so
	# a second man aiming does not reset the urgency of the first.
	var soonest := -1.0
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Enemy) or not is_instance_valid(n):
			continue
		var e: Enemy = n
		var tell: float = e.telegraphing()
		if tell <= 0.0 or e._target != self:
			continue
		soonest = maxf(soonest, 1.0 - clampf(tell / Enemy.AIM_TELL, 0.0, 1.0))
	marks.sense_on = move_toward(marks.sense_on, maxf(0.0, soonest), delta * 6.0)

	# And the bracket, for a rocket that is actually chasing this body.
	var near := -1.0
	for n in get_tree().get_nodes_in_group("gunfire"):
		if n is Gunfire:
			near = maxf(near, (n as Gunfire).lock_on(self))
	marks.locked = near >= 0.0
	marks.lock_near = maxf(0.0, near)

## The nearest prop worth grabbing: close, and roughly in front. "Only when something is
## on screen" is the rule, and in front of the camera is the honest reading of it.
func _reach_for_prop() -> Prop:
	var eye := camera.global_position if camera != null else model.position
	var aim := -camera.global_transform.basis.z if camera != null else -model.basis_.z
	var best: Prop = null
	var best_d := CARRY_RANGE
	for n in get_tree().get_nodes_in_group("prop"):
		if not (n is Prop) or not is_instance_valid(n):
			continue
		var pr: Prop = n
		if pr.state != Prop.RESTING:
			continue
		var to := pr.global_position - model.position
		var d := to.length()
		if d > best_d:
			continue
		# In front of the camera, not merely nearby — reaching backwards through your own
		# shoulder for a bin you cannot see is not a pickup, it is telekinesis.
		if aim.dot((pr.global_position - eye).normalized()) < 0.35:
			continue
		best_d = d
		best = pr
	return best

## Lets go of what he is carrying, at somebody. Turns to face them first, however far
## round they are — that turn is the whole point of the move reading as aimed rather than
## as dropped.
func _hurl_carried() -> void:
	if carried == null:
		return
	var prop := carried
	carried = null
	_wind = 0.0

	var mark := _nearest_thug()
	var dir: Vector3
	if mark != null:
		var to := (mark.global_position + Vector3(0, 0.9, 0)) - prop.global_position
		dir = to.normalized()
		# Snap round to look at him. Not lerped: the throw happens on this frame, and a
		# body still rotating towards a thing it has already thrown at reads as a bug.
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length_squared() > 1e-4:
			model.yaw = atan2(-flat.x, -flat.z)
	else:
		dir = -camera.global_transform.basis.z if camera != null else -model.basis_.z
	prop.hurl(dir)
	Sfx.play("punch_big", model.position, -2.0, 0.9)
	Rumble.hit(0.6, 0.35, 0.14)

## Nearest man still on his feet, in ANY direction — behind counts, which is what makes the
## turn worth having.
func _nearest_thug() -> Enemy:
	var best: Enemy = null
	var best_d := HURL_RANGE
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Enemy) or not is_instance_valid(n):
			continue
		var e: Enemy = n
		if e.state == Enemy.DOWN:
			continue
		var d := model.position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best
