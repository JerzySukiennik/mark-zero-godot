class_name Rumble
extends RefCounted
## The controller as an output device, not just an input one.
##
## The rule this follows: rumble is INFORMATION, never decoration. Every effect here tells
## the player something he cannot see or would otherwise miss — how hard the engines are
## working, that he clipped a building, that the charged shot is ready. A pad that buzzes
## continuously teaches the hands to ignore it, and then it cannot tell them anything.
##
## So there are two channels and they are kept apart:
##
##   THE BED   a continuous, quiet hum under flight, proportional to thrust. It is the
##             engine note you feel rather than hear. Never above a third of full strength,
##             because it has to leave headroom for everything below it to be felt ON TOP.
##   EVENTS    short, loud, and they win. An impact, a landing, a shot. These interrupt.
##
## Godot's API takes a weak and a strong motor. On a DualShock the strong one is the low
## rumble in the left grip and the weak one is the higher buzz in the right, so they are not
## interchangeable: low for mass and impact, high for machinery and electricity.

const BED_MAX := 0.30          ## the engine hum never goes above this
const EVENT_MIN_GAP := 0.04    ## two events closer than this are one event

static var _device := 0
static var _bed_weak := 0.0
static var _bed_strong := 0.0
static var _event_until := 0.0
static var _last_event := 0.0
static var _enabled := true

static func set_device(d: int) -> void:
	_device = d

static func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		Input.stop_joy_vibration(_device)

## Called every frame with what the engines are doing, 0..1.
static func set_flight(thrust: float, g_force: float) -> void:
	if not _enabled:
		return
	# The hum rises with throttle; the low motor also answers to g, so a hard turn is felt
	# in the grip rather than only seen in the camera.
	_bed_weak = clampf(thrust, 0.0, 1.0) * BED_MAX
	_bed_strong = clampf((g_force - 1.0) / 6.0, 0.0, 1.0) * BED_MAX * 0.8
	_apply()

## A one-off knock. `low` and `high` are 0..1, `secs` how long.
static func hit(low: float, high: float, secs: float) -> void:
	if not _enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_event < EVENT_MIN_GAP:
		return
	_last_event = now
	_event_until = now + secs
	Input.start_joy_vibration(_device, clampf(high, 0.0, 1.0), clampf(low, 0.0, 1.0), secs)

static func _apply() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _event_until:
		return          # an event is playing; do not talk over it
	# Re-issued every frame with a short duration: Godot's vibration expires on its own, so
	# a bed that is set once fades out and the engines go silent mid-flight.
	if _bed_weak < 0.01 and _bed_strong < 0.01:
		Input.stop_joy_vibration(_device)
	else:
		Input.start_joy_vibration(_device, _bed_weak, _bed_strong, 0.25)

# ---- the named effects, so call sites read as what they mean --------------------------

## Touching down. Scaled by how hard: a feather landing is a tap, a hard one is a slam.
static func landing(force: float) -> void:
	hit(clampf(0.35 + force * 0.65, 0.0, 1.0), 0.25, 0.18 + force * 0.22)

## Clipping a building. Sharp and mostly high, because it is a scrape, not a collision.
static func scrape(speed: float) -> void:
	hit(0.25, clampf(speed / 120.0, 0.15, 0.9), 0.10)

## An ordinary repulsor shot: a flick in the right hand, where the palm emitter is.
static func shot() -> void:
	hit(0.12, 0.45, 0.07)

## The charged shot going off. The heaviest thing in the game, and it should feel it.
static func charged() -> void:
	hit(1.0, 0.8, 0.45)

## The charge finishing — a short double tick, so the player knows without looking.
static func charge_ready() -> void:
	hit(0.0, 0.7, 0.06)

## Being hit.
static func damage(amount: float) -> void:
	hit(clampf(0.4 + amount, 0.3, 1.0), 0.3, 0.16)

## The suit closing around you at the end of a suit-up.
static func suit_locked() -> void:
	hit(0.8, 0.5, 0.30)
