class_name Visor
extends CanvasLayer
## Puts the HUD behind curved glass.
##
## The HUD draws into a SubViewport; this displays that viewport's texture through
## shaders/visor.gdshader. Doing it in two steps is what keeps the warp off the WORLD — a
## shader on the whole screen would bend the city too, which is a camera lens, not a helmet.

var hud: Hud
var _vp: SubViewport
var _screen: TextureRect

func _ready() -> void:
	layer = 10
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = _target_size()
	add_child(_vp)

	hud = Hud.new()
	hud.name = "Hud"
	_vp.add_child(hud)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/visor.gdshader")

	_screen = TextureRect.new()
	_screen.texture = _vp.get_texture()
	_screen.material = mat
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_screen)

	get_viewport().size_changed.connect(_resize)

func _target_size() -> Vector2i:
	var v := get_viewport()
	return v.get_visible_rect().size as Vector2i if v != null else Vector2i(1920, 1080)

func _resize() -> void:
	_vp.size = _target_size()
	hud.size = _vp.size
