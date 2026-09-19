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

## THE SAFE AREA, as a fraction of each axis.
##
## The visor shader magnifies what it samples — that is what makes the glass read as curved
## — so the outermost band of the SubViewport is never shown on screen at all. The cut is
## worst at the corners and is exactly `curve * r2 * half`, which for the shader's 0.028 and
## a corner's r2 of 2 comes to 2.8% of each axis. Drawing to the raw edge therefore put the
## integrity panel half outside the helmet: "znika w ogole z ekranu to HP". Everything is
## laid out inside this inset instead, with a little margin over the computed loss.
const VISOR_CUT := 0.034

var health := 1.0
var repulsor_l := 1.0
var repulsor_r := 1.0
var turret := 1.0
var _turret_show := 0.0           ## seconds left on the turret bar
var _sway := Vector2.ZERO
var _armor_name := "MARK I"
## What the right-hand panel counts. The HUD is worn by Spider-Man too, and telling him his
## REPULSORS are at full while he has none is worse than telling him nothing — it was still
## reading "MARK I / INTEGRITY / REPULSORS" through the Iron Spider's eyes.
var ammo_label := "REPULSORS"
var ammo_rows := ["L", "R"]
var _speed := 0.0
var _mach := 0.0
var _aiming := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# TOP-LEFT, not FULL_RECT. Full-rect anchors inside a SubViewport left this at size
	# ZERO and then overrode any explicit size set afterwards, so the panel drew into a
	# zero-wide rect in the corner. Visor._fit owns the size now; the anchors stay out of it.
	set_anchors_preset(Control.PRESET_TOP_LEFT)

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

## Same rule as the menu: sized in units against a 1080p reference, never in raw pixels.
## A HUD that is right on one screen and a postage stamp on another is not a HUD.
func _u() -> float:
	return maxf(0.55, size.y / 1080.0)

func _draw() -> void:
	# `s` is the SAFE rect, not the viewport, and `o` carries the inset — so every panel
	# below can go on measuring from the edges without knowing the glass exists.
	var m := size * VISOR_CUT
	var s := size - m * 2.0
	var u := _u()
	var o := _sway + m

	# ---- top left: the suit itself -------------------------------------------------
	_panel(Rect2(o + Vector2(38, 30) * u, Vector2(300, 84) * u))
	_label(o + Vector2(54, 54) * u, _armor_name, CYAN, int(19 * u))
	_label(o + Vector2(54, 76) * u, "INTEGRITY", Color(0.6, 0.72, 0.8), int(12 * u))
	_bar(Rect2(o + Vector2(54, 84) * u, Vector2(266, 11) * u), health,
		RED if health < 0.3 else AMBER)

	# ---- top right: what you can shoot with ----------------------------------------
	var rx := s.x - 340.0 * u
	_panel(Rect2(o + Vector2(rx, 30 * u), Vector2(300 * u, (84 + (30.0 if _turret_show > 0.0 else 0.0)) * u)))
	_label(o + Vector2(rx + 16 * u, 54 * u), ammo_label, Color(0.6, 0.72, 0.8), int(12 * u))
	# One bar per hand, because they are fired by different buttons and drain separately.
	_label(o + Vector2(rx + 16 * u, 76 * u), ammo_rows[0], CYAN, int(13 * u))
	_bar(Rect2(o + Vector2(rx + 34 * u, 66 * u), Vector2(248 * u, 11 * u)), repulsor_l, CYAN)
	_label(o + Vector2(rx + 16 * u, 98 * u), ammo_rows[1], CYAN, int(13 * u))
	_bar(Rect2(o + Vector2(rx + 34 * u, 88 * u), Vector2(248 * u, 11 * u)), repulsor_r, CYAN)
	if _turret_show > 0.0:
		# The turret bar is not always on screen: a readout that is always there is
		# furniture, one that appears when it matters is information.
		var a: float = clampf(_turret_show, 0.0, 1.0)
		_label(o + Vector2(rx + 16 * u, 120 * u), "T", AMBER * Color(1, 1, 1, a), int(13 * u))
		_bar(Rect2(o + Vector2(rx + 34 * u, 110 * u), Vector2(248 * u, 11 * u)), turret, AMBER * Color(1, 1, 1, a))

	# ---- bottom left: speed --------------------------------------------------------
	_label(o + Vector2(46 * u, s.y - 82 * u), "%d" % roundi(_speed), CYAN, int(42 * u))
	_label(o + Vector2(46 * u, s.y - 54 * u), "M/S", Color(0.6, 0.72, 0.8), int(12 * u))
	if _mach > 0.55:
		_label(o + Vector2(136 * u, s.y - 54 * u), "MACH %.2f" % _mach,
			AMBER if _mach >= 1.0 else Color(0.6, 0.72, 0.8), int(14 * u))

	# ---- centre: the reticle, only while aiming ------------------------------------
	if _aiming > 0.01:
		# The TRUE centre, not the safe rect's — the crosshair marks where the suit is
		# pointing, and the inset is symmetric so the two centres coincide anyway. Adding
		# the inset here would have walked it off the aim point.
		var c := size * 0.5 + _sway * 0.35 # the reticle sways less than the frame around it
		var col := Color(CYAN.r, CYAN.g, CYAN.b, _aiming)
		var r := lerpf(38.0, 25.0, _aiming) * u
		draw_arc(c, r, 0, TAU, 48, col, maxf(1.5, 1.8 * u), true)
		for i in 4:
			var ang := i * PI * 0.5 + PI * 0.25
			var d := Vector2(cos(ang), sin(ang))
			draw_line(c + d * (r + 6 * u), c + d * (r + 15 * u), col, maxf(1.5, 1.8 * u), true)
		draw_circle(c, 2.0 * u, col)

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
