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

## One per hand. Right is R1, left is L1 — the same hands the armour fires from, so the
## two characters do not need separate muscle memory.
var tether := { "R": WebTether.new(), "L": WebTether.new() }
var line := { "R": null, "L": null }
## Rises while a hand is throwing a web, and drives that arm out towards the anchor.
var _throw := { "R": 0.0, "L": 0.0 }

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
		visor.ready.connect(func():
			visor.menu.hero_chosen.connect(func(id: String): Net.announce_hero(id))
			# The roster panel is fed rather than reaching for Net itself, so refresh it
			# whenever it comes up.
			visor.menu.opened.connect(func(): _feed_roster()))

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
	var aiming := Pad.retro() > 0.25
	Engine.time_scale = AIM_TIME_SCALE if aiming else 1.0

	if visor != null and visor.menu != null and visor.menu.is_open:
		visor.menu.step(delta)
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

	var cmd := {
		walk = move,
		look = look,
		jump = model.grounded and Pad.just_pressed("up"),
		aiming = aiming,
	}
	if _stage != null:
		model.ground_y = _stage.ground_y
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

	_draw_webs()

	if camera != null:
		camera.follow(delta, model.position, model.basis_, model.speed, aiming, 120.0)
	if visor != null and visor.hud != null:
		visor.hud.feed(delta / maxf(0.05, Engine.time_scale), look, model.speed, health, aiming)

## Fire, or let go. TAP TO FIRE, TAP AGAIN TO RELEASE — not hold. A held button would mean
## the player cannot look around or steer with that thumb during the one part of the game
## where both matter, and a swing lasts several seconds.
func _service_web(hand: String, delta: float) -> void:
	var t: WebTether = tether[hand]
	_throw[hand] = maxf(0.0, _throw[hand] - delta * 4.0)

	if not Pad.just_pressed("fire_" + hand.to_lower()):
		return
	if t.state != WebTether.IDLE:
		t.release()
		return

	# Aim from the CAMERA, not from the hand. The player is pointing with the reticle, and
	# a cone taken from the wrist disagrees with it by several degrees at a hundred metres —
	# which feels like the web missing something you were plainly looking at.
	var from := _hand_point(hand)
	var eye := camera.global_position if camera != null else from
	var aim := -camera.global_transform.basis.z if camera != null else -model.basis_.z
	var target := WebTether.pick(eye, aim, _targets())
	if target != null and t.fire(from, target):
		_throw[hand] = 1.0
		Rumble.landing(0.25)

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
	var name := "piv_palm" + hand
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

## Kept here rather than in Poses, which is typed against FlightModel and is full of things
## with no meaning for a man on a rope — thrust, boost, station keeping.
func _pose(_delta: float) -> void:
	var hanging: bool = tether["R"].state == WebTether.ATTACHED or tether["L"].state == WebTether.ATTACHED
	skel.set_pose_weights({
		"stand": 1.0 if model.grounded and model.ground_speed <= 0.5 else 0.0,
		"walk": 1.0 if model.grounded and model.ground_speed > 0.5 else 0.0,
		"cruise": 1.0 if (not model.grounded and hanging) else 0.0,
		"hover": 1.0 if (not model.grounded and not hanging) else 0.0,
	})

	if model.grounded and model.ground_speed > 0.5:
		var ph := model.stride_phase * TAU
		var gait := clampf(model.ground_speed / SpiderModel.RUN_SPEED, 0.0, 1.0)
		var amp := lerpf(0.28, 0.82, gait)
		var s1 := sin(ph)
		var s2 := sin(ph + PI)
		skel.add_offset("piv_hipL", Poses.X_AX, -s1 * amp)
		skel.add_offset("piv_hipR", Poses.X_AX, -s2 * amp)
		skel.add_offset("piv_kneeL", Poses.X_AX, maxf(0.0, sin(ph - PI * 0.35)) * amp * 1.6)
		skel.add_offset("piv_kneeR", Poses.X_AX, maxf(0.0, sin(ph + PI * 0.65)) * amp * 1.6)
		skel.add_offset("piv_shoulderL", Poses.X_AX, -s2 * amp * 0.6)
		skel.add_offset("piv_shoulderR", Poses.X_AX, -s1 * amp * 0.6)
		skel.add_offset("piv_hips", Poses.Y_AX, s1 * amp * 0.24)
		skel.add_offset("piv_chest", Poses.Y_AX, -s1 * amp * 0.18)

	# THE THROWING ARM. The hand that fired reaches out along the web and the other stays
	# put, so which hand threw it is readable without looking at the HUD — the same lesson
	# the armour's fire pose had to learn the hard way.
	#
	# The authored web-shooting gesture (two fingers folded to the palm) arrives with the
	# Iron Spider model; until then this is the arm, not the hand.
	for hand: String in ["R", "L"]:
		var th: float = _throw[hand]
		var t: WebTether = tether[hand]
		var hold := 0.55 if t.state == WebTether.ATTACHED else 0.0
		var reach: float = maxf(th, hold)
		if reach <= 0.001:
			continue
		skel.add_offset("piv_shoulder" + hand, Poses.X_AX, -1.25 * reach)
		skel.add_offset("piv_elbow" + hand, Poses.X_AX, -0.7 * reach)
		# THE THWIP. Two fingers folded to the palm, and it is one clean rotation because
		# the model was authored for exactly that. It snaps shut with the throw and relaxes
		# while the web is held, so a hand carrying a rope is not still mid-gesture.
		var fold: float = maxf(th, hold * 0.45)
		skel.add_offset("piv_fingers" + hand, Poses.X_AX, THWIP_ANGLE * fold)

	# Hanging, the legs tuck and trail. A figure on a rope with its legs straight down is a
	# plumb bob, and reads as one.
	if hanging:
		var tuck := clampf(model.speed / 40.0, 0.25, 1.0)
		skel.add_offset("piv_hipL", Poses.X_AX, 0.5 * tuck)
		skel.add_offset("piv_hipR", Poses.X_AX, 0.35 * tuck)
		skel.add_offset("piv_kneeL", Poses.X_AX, 1.1 * tuck)
		skel.add_offset("piv_kneeR", Poses.X_AX, 0.8 * tuck)

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
