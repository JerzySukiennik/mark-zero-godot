extends Node
class_name PadInput
## The controller, and the only way this game is played.
##
## Jurek's decision when the project moved to Godot: "tylko kontroler do komputera, czyli
## wszystkie input prompty i w ogóle powinno to wszystko być do kontrolera." No mouse, no
## keyboard, no split attention in the UI — every prompt the player ever sees names a pad
## button, and menus are navigated with the stick.
##
## This is a deliberate simplification over the browser build, where the controls had to be
## a keyboard scheme with a pad bolted alongside. Designing for one device means the flight
## model can assume analog input everywhere: there is no "W is 0 or 1" case to carry.
##
## Godot's InputMap is set up in code rather than in project.godot so that the binding table
## lives next to the glyph table — a prompt that says the wrong button is worse than no
## prompt, and keeping them in one file is what stops them drifting apart.

signal pad_changed(connected: bool)

## Action name -> [JoyButton] . One place, read by both the InputMap setup and the glyphs.
## Action -> every physical button that should trigger it.
##
## A LIST, not a single index, and that is load-bearing. The touchpad click is reported as
## JOY_BUTTON_TOUCHPAD (20) by SDL's DualShock mapping and as JOY_BUTTON_MISC1 (15) by some
## driver builds; binding only MISC1 is why the menu could not be opened at all — Jurek
## pressed "ten duzy przycisk" and nothing happened, because the pad was sending 20.
## Listing both costs nothing and removes a whole class of "works on my machine".
const BUTTONS := {
	"fire_r":      [JOY_BUTTON_RIGHT_SHOULDER],   # R1 - right palm
	"fire_l":      [JOY_BUTTON_LEFT_SHOULDER],    # L1 - left palm
	"turret":      [JOY_BUTTON_X],                # square - shoulder turret
	"menu":        [JOY_BUTTON_TOUCHPAD, JOY_BUTTON_MISC1, JOY_BUTTON_START],
	"up":          [JOY_BUTTON_A, JOY_BUTTON_DPAD_UP],
	# Descend used to share L1 with the left repulsor, so every left-hand shot also dropped
	# the suit. The d-pad is free; firing and flying no longer fight over one button.
	"down":        [JOY_BUTTON_DPAD_DOWN],
	"interact":    [JOY_BUTTON_Y],                # triangle
	"suit_toggle": [JOY_BUTTON_B],                # circle
	"hover":       [JOY_BUTTON_LEFT_STICK],       # L3
	"faceplate":   [JOY_BUTTON_RIGHT_STICK],      # R3
	"pause":       [JOY_BUTTON_START],            # options
	"ui_accept_pad": [JOY_BUTTON_A],
	"ui_back":     [JOY_BUTTON_B],
}

## What the player is told to press. PlayStation names, because the pad is a DualShock.
##
## STATIC, and reachable without the autoload. It is a lookup table, and a lookup table has
## no business requiring a running SceneTree — the menu and the HUD both draw button prompts,
## and a screenshot tool or a test that renders them must not need the whole input system
## booted to find out that fire is R1. Same lesson as the armour spec table.
const GLYPH := {
	"fire_r": "R1", "fire_l": "L1", "turret": "□", "up": "✕", "down": "D-PAD ↓",
	"menu": "TOUCHPAD", "interact": "△",
	"suit_toggle": "○", "hover": "L3", "faceplate": "R3", "pause": "OPTIONS",
	"supersonic": "R2", "aim": "L2", "move": "L STICK", "look": "R STICK",
	"ui_accept_pad": "✕", "ui_back": "○",
}

## A DualShock rests a few percent off centre and never returns exactly to zero. Below this
## the stick is centred, or the suit drifts on its own for a whole flight and it reads as
## the physics being broken rather than as the hardware.
const DEADZONE := 0.18
## Sticks are linear, hands are not. Squaring the deflection (keeping the sign) gives fine
## control near the centre and full authority at the edge.
const LOOK_CURVE := 2.0
const LOOK_SPEED := 2.6          ## radians per second at full deflection
const TRIGGER_FLOOR := 0.06

var connected := false
var device := -1

func _ready() -> void:
	_install_actions()
	Input.joy_connection_changed.connect(_on_joy_changed)
	_rescan()

func _install_actions() -> void:
	for action in BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for idx: int in BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = idx
			InputMap.action_add_event(action, ev)

func _on_joy_changed(idx: int, is_connected: bool) -> void:
	_rescan()
	pad_changed.emit(connected)
	if not is_connected and idx == device:
		device = -1

func _rescan() -> void:
	var pads := Input.get_connected_joypads()
	connected = pads.size() > 0
	device = pads[0] if connected else -1
	# Haptics go to the same pad we read from. Told once here rather than passed around,
	# because a rumble sent to a disconnected device is silently dropped and looks like the
	# effect simply not firing.
	if connected:
		Rumble.set_device(device)

# ---- analog reads ----------------------------------------------------------------------
# All of these return 0 when no pad is attached, so nothing downstream has to check.

func _dz(v: float) -> float:
	var a := absf(v)
	if a < DEADZONE:
		return 0.0
	# Rescale so the first live value is 0 rather than the deadzone edge — otherwise the
	# stick jumps to 18% the instant it crosses the threshold.
	return signf(v) * ((a - DEADZONE) / (1.0 - DEADZONE))

func _axis(ax: JoyAxis) -> float:
	if device < 0:
		return 0.0
	return _dz(Input.get_joy_axis(device, ax))

## Left stick: movement on foot, lateral thrust and pitch trim in the air.
func move() -> Vector2:
	return Vector2(_axis(JOY_AXIS_LEFT_X), _axis(JOY_AXIS_LEFT_Y))

## Right stick: turns the whole body. Returned in radians for this frame.
func look(delta: float) -> Vector2:
	var x := _axis(JOY_AXIS_RIGHT_X)
	var y := _axis(JOY_AXIS_RIGHT_Y)
	if x == 0.0 and y == 0.0:
		return Vector2.ZERO
	var cx := signf(x) * pow(absf(x), LOOK_CURVE)
	var cy := signf(y) * pow(absf(y), LOOK_CURVE)
	return Vector2(cx, cy) * LOOK_SPEED * delta

## R2 — main thrust. Analog: this is the whole reason the game is pad-only.
func thrust() -> float:
	if device < 0:
		return 0.0
	var v := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	return v if v > TRIGGER_FLOOR else 0.0

## L2 — the retro burn. Also analog, so a light touch trims speed instead of stopping dead.
func retro() -> float:
	if device < 0:
		return 0.0
	var v := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	return v if v > TRIGGER_FLOOR else 0.0

func pressed(action: String) -> bool:
	return Input.is_action_pressed(action)

func just_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)

## The button glyph for a prompt, e.g. PadInput.glyph("interact") -> "△".
static func glyph(action: String) -> String:
	return GLYPH.get(action, "?")
