class_name Hud
extends Control
## The visor. Everything the pilot reads while flying.
##
## It lives inside a SubViewport and is then drawn through shaders/visor.gdshader, so the
## curve, the scanline and the chromatic edge apply to the INTERFACE and never to the world
## behind it. That separation is the whole trick: warping the 3D would be a fisheye lens,
## warping the overlay is a curved piece of glass in front of your face.
##
## It also SWAYS. A HUD painted rigidly onto the screen belongs to the monitor; one that lags
## the head by a few pixels belongs to a helmet the head is moving inside. Driven off the
## suit's turn rate, tiny, and it is the cheapest part of the whole illusion.

const AMBER := Color(1.0, 0.72, 0.28)
const CYAN := Color(0.55, 0.88, 1.0)
const RED := Color(1.0, 0.36, 0.30)

## How far the HUD lags the head, in pixels at full turn rate.
const SWAY := 26.0
const SWAY_LAG := 0.09

var health := 1.0
var repulsor_l := 1.0
var repulsor_r := 1.0
var turret := 1.0
var _turret_show := 0.0           ## seconds left on the turret bar
var _sway := Vector2.ZERO
var _armor_name := "MARK I"
var _speed := 0.0
var _mach := 0.0
var _aiming := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

## Fed every frame by the suit.
func feed(delta: float, look: Vector2, speed: float, hp: float, aiming: bool) -> void:
	_speed = speed
	_mach = speed / 343.0
	health = hp
	_aiming = lerpf(_aiming, 1.0 if aiming else 0.0, 1.0 - exp(-delta / 0.12))
	var want := Vector2(-look.x, -look.y) * SWAY * 60.0
	_sway = _sway.lerp(want.limit_length(SWAY), 1.0 - exp(-delta / SWAY_LAG))
	if _turret_show > 0.0:
		_turret_show -= delta
	queue_redraw()

## Called when the shoulder turret fires, so its bar appears for a moment.
func flash_turret() -> void:
	_turret_show = 2.5

func _draw() -> void:
	var s := size
	var o := _sway

	# ---- top left: the suit itself -------------------------------------------------
	_panel(Rect2(o + Vector2(38, 30), Vector2(260, 74)))
	_label(o + Vector2(52, 50), _armor_name, CYAN, 15)
	_label(o + Vector2(52, 70), "INTEGRITY", Color(0.6, 0.72, 0.8), 9)
	_bar(Rect2(o + Vector2(52, 78), Vector2(230, 9)), health,
		RED if health < 0.3 else AMBER)

	# ---- top right: what you can shoot with ----------------------------------------
	var rx := s.x - 298.0
	_panel(Rect2(o + Vector2(rx, 30), Vector2(260, 74 + (26.0 if _turret_show > 0.0 else 0.0))))
	_label(o + Vector2(rx + 14, 50), "REPULSORS", Color(0.6, 0.72, 0.8), 9)
	# One bar per hand, because they are fired by different buttons and drain separately.
	_label(o + Vector2(rx + 14, 68), "L", CYAN, 10)
	_bar(Rect2(o + Vector2(rx + 30, 60), Vector2(214, 9)), repulsor_l, CYAN)
	_label(o + Vector2(rx + 14, 86), "R", CYAN, 10)
	_bar(Rect2(o + Vector2(rx + 30, 78), Vector2(214, 9)), repulsor_r, CYAN)
	if _turret_show > 0.0:
		# The turret bar is not always on screen: a readout that is always there is
		# furniture, one that appears when it matters is information.
		var a: float = clampf(_turret_show, 0.0, 1.0)
		_label(o + Vector2(rx + 14, 104), "T", AMBER * Color(1, 1, 1, a), 10)
		_bar(Rect2(o + Vector2(rx + 30, 96), Vector2(214, 9)), turret, AMBER * Color(1, 1, 1, a))

	# ---- bottom left: speed --------------------------------------------------------
	_label(o + Vector2(44, s.y - 74), "%d" % roundi(_speed), CYAN, 34)
	_label(o + Vector2(44, s.y - 50), "M/S", Color(0.6, 0.72, 0.8), 9)
	if _mach > 0.55:
		_label(o + Vector2(120, s.y - 50), "MACH %.2f" % _mach,
			AMBER if _mach >= 1.0 else Color(0.6, 0.72, 0.8), 11)

	# ---- centre: the reticle, only while aiming ------------------------------------
	if _aiming > 0.01:
		var c := s * 0.5 + o * 0.35        # the reticle sways less than the frame around it
		var col := Color(CYAN.r, CYAN.g, CYAN.b, _aiming)
		var r := lerpf(34.0, 22.0, _aiming)
		draw_arc(c, r, 0, TAU, 48, col, 1.5, true)
		for i in 4:
			var ang := i * PI * 0.5 + PI * 0.25
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * (r + 5), c + d * (r + 13), col, 1.5, true)
		draw_circle(c, 1.6, col)

func _panel(r: Rect2) -> void:
	draw_rect(r, Color(0.02, 0.05, 0.08, 0.42), true)
	draw_rect(r, Color(CYAN.r, CYAN.g, CYAN.b, 0.28), false, 1.0)

func _bar(r: Rect2, v: float, col: Color) -> void:
	draw_rect(r, Color(0.1, 0.16, 0.2, 0.7), true)
	var w := r.size.x * clampf(v, 0.0, 1.0)
	if w > 0.5:
		draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col, true)
	# Ticks, so a bar is readable as a QUANTITY and not just a length.
	for i in range(1, 4):
		var x := r.position.x + r.size.x * i * 0.25
		draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + r.size.y),
			Color(0, 0, 0, 0.35), 1.0)

func _label(at: Vector2, text: String, col: Color, px: int) -> void:
	var f := ThemeDB.fallback_font
	draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

func set_armor_name(n: String) -> void:
	_armor_name = n
