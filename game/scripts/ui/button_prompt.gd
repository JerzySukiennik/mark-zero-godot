class_name ButtonPrompt
extends Sprite3D
## A "press these" tag that floats on a thing in the world.
##
## Drawn through a SubViewport rather than written with a Label3D, because what Jurek asked
## for is BUTTON ICONS — "powinny być takie ikonki, że jest ikonka L1 i potem jest plus i
## ikonka R1" — and a pill with a border around a glyph is a drawing, not a string. The
## same trick the visor already uses: a Control renders once, and a quad in the world shows
## what it rendered.
##
## It renders ONCE and then never again. A prompt is static; giving it a live viewport per
## bin would cost a full redraw a frame each, for something that changes when the bindings
## change and at no other time.

const PAD := 14
const HEIGHT := 64

var _vp: SubViewport
var _canvas: _PromptDraw

class _PromptDraw:
	extends Control
	var keys: Array = []
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := 30
		var x := float(PAD)
		for i in keys.size():
			var label: String = keys[i]
			if label == "+":
				# The join, drawn small and dim: it is punctuation, not an instruction.
				draw_string(font, Vector2(x + 2, HEIGHT * 0.5 + fs * 0.34), "+",
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.78, 0.84, 0.92, 0.85))
				x += font.get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16
				continue
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 26
			var r := Rect2(Vector2(x, 8), Vector2(w, HEIGHT - 16))
			# A pill: dark fill, bright rim, the shape every console prompt has used for
			# twenty years and which reads as "a button" with no explaining.
			draw_rect(r, Color(0.04, 0.06, 0.09, 0.92), true)
			draw_rect(r, Color(0.85, 0.92, 1.0, 0.95), false, 3.0)
			draw_string(font, Vector2(x + 13, HEIGHT * 0.5 + fs * 0.34), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 1))
			x += w + 12

func _init(keys: Array = ["L1", "+", "R1"]) -> void:
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	# ONCE. Anything else is a viewport redrawing a static image every frame, per bin.
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.size = Vector2i(_width(keys), HEIGHT)
	add_child(_vp)

	_canvas = _PromptDraw.new()
	_canvas.keys = keys
	_canvas.size = Vector2(_vp.size)
	_vp.add_child(_canvas)

	texture = _vp.get_texture()
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	pixel_size = 0.004
	# Unshaded, so a prompt on a dark plate at night reads the same as one in daylight.
	shaded = false
	modulate = Color(1, 1, 1, 0)

static func _width(keys: Array) -> int:
	var font := ThemeDB.fallback_font
	var w := PAD * 2
	for k in keys:
		if k == "+":
			w += int(font.get_string_size("+", HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x) + 16
		else:
			w += int(font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x) + 38
	return maxi(64, w)

## 0..1. Fades rather than snapping, so walking past one does not strobe.
func show_at(alpha: float) -> void:
	modulate = Color(1, 1, 1, alpha)
	visible = alpha > 0.01
