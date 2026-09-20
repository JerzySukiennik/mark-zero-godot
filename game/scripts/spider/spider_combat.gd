class_name SpiderCombat
extends RefCounted
## Spider-Man's hands. Everything he does at arm's length.
##
## Jurek's design, taken as given:
##   TRIANGLE  a strike from a distance — he throws himself at the man and hits him, and
##             it is spammable. "Ta najbardziej prymitywna walka."
##   SQUARE    held, launches the man into the air and goes up with him; then square and
##             triangle juggle him until he dies or you stop, and he drops and gets up.
##   CIRCLE    a dodge, and it reads the stick: sideways to the side, backwards a backflip.
##   L2        AIM, not a web. Holding it lets R1 and L1 be spammed.
##
## Kept out of SpiderPilot because that file is already the input map, the tethers, the
## camera and the HUD. This is a state machine with its own clock, and the two only meet
## where the pilot asks it what the body should be doing.

enum { FREE, ZIP, LAUNCH, AIR, DODGE }

## How far a triangle strike will reach for someone.
const ZIP_RANGE := 26.0
## The cone it will reach INSIDE, in degrees. Wide, because this is the primitive attack
## and having it whiff on a man who is plainly there is worse than it being generous.
const ZIP_CONE := 55.0
const ZIP_SPEED := 52.0
## How close counts as arrived.
const ZIP_HIT := 2.6
const ZIP_TIMEOUT := 0.55
const PUNCH := 14.0
## The recovery after a landed punch. Short — it is meant to be mashed.
const PUNCH_RECOVER := 0.16

## Holding square this long commits to a launcher rather than a punch.
const HOLD_TIME := 0.22
const LAUNCH_UP := 15.0
const LAUNCH_RISE := 13.0
## How long the air combo stays open with no further input.
const AIR_GRACE := 0.9
const AIR_HIT := 11.0

const DODGE_TIME := 0.34
const DODGE_SPEED := 17.0
## Damage taken during a dodge, as a fraction. Not zero: invulnerability frames make a
## dodge the answer to everything, and then there is only one button.
const DODGE_ARMOUR := 0.25

var state := FREE
var target: Enemy = null
var t := 0.0                    ## time left in whatever is happening
var air_left := 0.0             ## how long the juggle window stays open
var combo := 0
var dodge_dir := Vector3.ZERO
var last_hand := "L"

var _recover := 0.0
var _square_held := 0.0

## Is he untouchable-ish right now?
func damage_scale() -> float:
	return DODGE_ARMOUR if state == DODGE else 1.0

## The man a strike would go for: nearest inside the cone, in front, alive.
func pick(from: Vector3, facing: Vector3, tree: SceneTree) -> Enemy:
	var best: Enemy = null
	var best_score := -1e9
	var cone := cos(deg_to_rad(ZIP_CONE))
	for n in tree.get_nodes_in_group("enemy"):
		if not (n is Enemy) or not is_instance_valid(n):
			continue
		var e: Enemy = n
		if e.state == Enemy.DOWN:
			continue
		var to := e.global_position + Vector3(0, 0.9, 0) - from
		var d := to.length()
		if d > ZIP_RANGE or d < 0.2:
			continue
		var dot := facing.dot(to / d)
		if dot < cone:
			continue
		# Closest wins, but being straight ahead is worth a couple of metres — otherwise a
		# man at your shoulder steals a strike aimed at the one in front of you.
		var score := -d + dot * 6.0
		if score > best_score:
			best_score = score
			best = e
	return best

## Driven every frame by the pilot. `cmd` carries the buttons; returns what the body should
## be doing so the pose layer can answer it.
func update(delta: float, model: SpiderModel, cmd: Dictionary, tree: SceneTree) -> void:
	_recover = maxf(0.0, _recover - delta)
	if t > 0.0:
		t -= delta
	if air_left > 0.0:
		air_left -= delta
		if air_left <= 0.0 and state == AIR:
			_end_air()

	match state:
		ZIP:
			_run_zip(delta, model)
			return
		DODGE:
			model.velocity.x = dodge_dir.x * DODGE_SPEED
			model.velocity.z = dodge_dir.z * DODGE_SPEED
			if t <= 0.0:
				state = FREE
			return
		LAUNCH:
			# Riding up with him. He is held by his own juggle timer; this is the camera's
			# half of the move.
			model.velocity.y = maxf(model.velocity.y, LAUNCH_RISE)
			if t <= 0.0:
				state = AIR
				air_left = AIR_GRACE
			return

	if cmd.get("dodge", false):
		_start_dodge(model, cmd)
		return

	# SQUARE: tapped it is a punch, HELD it is a launcher. The hold is measured rather than
	# guessed at, so a quick tap never launches by accident.
	if cmd.get("heavy_down", false):
		_square_held = 0.0
	if cmd.get("heavy", false):
		_square_held += delta
		if _square_held >= HOLD_TIME and state != AIR and _recover <= 0.0:
			_try_launch(model, cmd, tree)
			return
	elif _square_held > 0.0:
		var quick := _square_held < HOLD_TIME
		_square_held = 0.0
		if quick and _recover <= 0.0:
			_strike(model, cmd, tree, true)
			return

	if cmd.get("light", false) and _recover <= 0.0:
		_strike(model, cmd, tree, false)

## Triangle, and a tapped square. Throws him at the man if there is one in front, and
## simply swings if there is not — a strike that does nothing when you press it teaches
## the player the button is broken.
func _strike(model: SpiderModel, cmd: Dictionary, tree: SceneTree, heavy: bool) -> void:
	var facing: Vector3 = cmd.get("facing", -model.basis_.z)
	target = pick(model.position, facing, tree)
	last_hand = "R" if last_hand == "L" else "L"
	combo += 1
	if state == AIR and target != null and is_instance_valid(target):
		# Mid-combo: keep him up and keep hitting.
		target.juggle(AIR_HIT * 0.35)
		target.take_hit(AIR_HIT if not heavy else AIR_HIT * 1.6, model.position, "spider")
		air_left = AIR_GRACE
		_recover = PUNCH_RECOVER
		model.velocity.y = maxf(model.velocity.y, 4.0)
		return
	if target == null:
		_recover = PUNCH_RECOVER
		return
	state = ZIP
	t = ZIP_TIMEOUT

func _run_zip(delta: float, model: SpiderModel) -> void:
	if target == null or not is_instance_valid(target) or target.state == Enemy.DOWN:
		state = FREE
		return
	var to := target.global_position + Vector3(0, 0.9, 0) - model.position
	var d := to.length()
	if d <= ZIP_HIT or t <= 0.0:
		if d <= ZIP_HIT * 1.6:
			target.take_hit(PUNCH, model.position, "spider")
			# Knocked back along the punch, and up a little so it reads as a hit rather
			# than a shove.
			target.velocity += to.normalized() * 7.0 + Vector3.UP * 2.5
		# Stop dead on arrival instead of sailing past, which is what made it feel like a
		# dash rather than a strike.
		model.velocity *= 0.25
		state = FREE
		_recover = PUNCH_RECOVER
		return
	model.velocity = to / d * ZIP_SPEED
	model.grounded = false

## Held square. Only launches someone who is actually in reach — otherwise it is a punch
## at nothing that also throws you into the sky.
func _try_launch(model: SpiderModel, cmd: Dictionary, tree: SceneTree) -> void:
	var facing: Vector3 = cmd.get("facing", -model.basis_.z)
	target = pick(model.position, facing, tree)
	_square_held = 0.0
	if target == null or not is_instance_valid(target):
		_recover = PUNCH_RECOVER
		return
	var to := target.global_position - model.position
	if to.length() > ZIP_HIT * 2.4:
		# Close first, then launch on arrival.
		state = ZIP
		t = ZIP_TIMEOUT
		return
	target.take_hit(PUNCH, model.position, "spider")
	target.launch(LAUNCH_UP, model.velocity * 0.3)
	state = LAUNCH
	t = 0.22
	combo = 1
	model.grounded = false

func _end_air() -> void:
	state = FREE
	combo = 0
	# Letting go drops him. He gets up on his own — that is Enemy's business.
	if target != null and is_instance_valid(target):
		target.velocity.y = minf(target.velocity.y, -2.0)

## Circle. Reads the stick so the move matches what the player was already doing: nothing
## is more obviously wrong than a backflip while running forwards.
func _start_dodge(model: SpiderModel, cmd: Dictionary) -> void:
	var ask: Vector2 = cmd.get("walk", Vector2.ZERO)
	var dir := Vector3.ZERO
	if ask.length() > 0.2:
		dir = (model.basis_ * Vector3(ask.x, 0.0, ask.y)).normalized()
	else:
		dir = (model.basis_ * Vector3(0, 0, 1)).normalized()   # no input: step back
	dir.y = 0.0
	dodge_dir = dir.normalized()
	state = DODGE
	t = DODGE_TIME
	# A backwards dodge is a backflip; sideways is a roll. The pose layer reads this.
	var back: float = (model.basis_ * Vector3(0, 0, 1)).normalized().dot(dodge_dir)
	dodge_back = back > 0.4
	model.velocity.y = maxf(model.velocity.y, 3.2 if dodge_back else 1.4)

var dodge_back := false
