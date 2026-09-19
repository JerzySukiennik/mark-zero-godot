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
const CATCH_SHORTEN := 0.88
const CATCH_LIFT := 6.0
const FEET_DROP := 1.0
const AIM_TIME_SCALE := 0.35

var peer_id := 1
var model: SpiderModel
var rig: Node3D
var skel: SuitRig
var camera: ChaseCamera
var visor: Visor
var health := 1.0
var legs := SpiderLegs.new()
var poses := SpiderPoses.new()

## One per hand. Right is R1, left is L1 — the same hands the armour fires from, so the
## two characters do not need separate muscle memory.
var tether := { "R": WebTether.new(), "L": WebTether.new() }
var line := { "R": null, "L": null }
## Rises while a hand is throwing a web, and drives that arm out towards the anchor.
var _throw := { "R": 0.0, "L": 0.0 }
## Trigger edges, so holding fires ONE web rather than one per frame.
var _held := { "R": false, "L": false }
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

	var rope := Vector3.ZERO
	for hand: String in ["R", "L"]:
		_service_web(hand, delta)
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
	if not model.grounded and Pad.just_pressed("up") and _hops > 0:
		_hops -= 1
		hopped = true
		var fwd := model.basis_ * Vector3(0, 0, -1)
		model.velocity.y = maxf(model.velocity.y, 0.0) + HOP_UP
		model.velocity += fwd * HOP_FWD
		Rumble.landing(0.3)
	if model.grounded:
		_hops = MAX_HOPS

	var cmd := {
		walk = move,
		look = look,
		jump = model.grounded and Pad.just_pressed("up"),
		aiming = aiming,
	}
	if _stage != null:
		model.ground_y = _stage.ground_y
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
		legs.drive(delta, not model.grounded, skel)
		skel.update_pose(delta)

	if was_down and model.grounded:
		poses.land_hard(clampf(-fell / 30.0, 0.0, 1.0))

	_draw_webs()

	if camera != null:
		camera.follow(delta, model.position, model.view_basis, model.speed, aiming, 120.0)
	if visor != null and visor.hud != null:
		visor.hud.feed(delta / maxf(0.05, Engine.time_scale), look, model.speed, health, aiming)
		# A hand holding a web reads as spent; a free hand reads as loaded. Crude, and it is
		# the only thing on that panel that means anything to him.
		visor.hud.repulsor_l = 0.15 if tether["L"].state != WebTether.IDLE else 1.0
		visor.hud.repulsor_r = 0.15 if tether["R"].state != WebTether.IDLE else 1.0

## HELD ON THE TRIGGERS. Jurek: "pod R2 powinna byc prawa siec, a pod L2 lewa siec."
##
## Hold and you are on the web; let go and you drop. That is both what every Spider-Man
## game does and the better fit for an analogue trigger, which has a natural "still holding
## it" state that a face button does not — and it frees both thumbs for the sticks, which
## during a swing are steering and looking.
func _service_web(hand: String, delta: float) -> void:
	var t: WebTether = tether[hand]
	_throw[hand] = maxf(0.0, _throw[hand] - delta * 4.0)

	# R2 is the right hand, L2 the left.
	var pull: float = Pad.thrust() if hand == "R" else Pad.retro()
	var held := pull > TRIGGER_FIRE
	var was: bool = _held[hand]
	_held[hand] = held

	if not held:
		if t.state != WebTether.IDLE:
			t.release()
		return
	if was or t.state != WebTether.IDLE:
		return

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

	if node != null and t.fire(from, node, hit_at):
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
	}, skel)

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
