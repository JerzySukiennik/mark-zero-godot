class_name Visor
extends CanvasLayer
## Puts the HUD behind curved glass.
##
## The HUD draws into a SubViewport; this displays that viewport's texture through
## shaders/visor.gdshader. Doing it in two steps is what keeps the warp off the WORLD — a
## shader on the whole screen would bend the city too, which is a camera lens, not a helmet.

var hud: Hud
var menu: SuitMenu
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

	# The menu goes through the SAME glass as the HUD. It is the suit's own display, not the
	# game engine's — a menu that looks like it belongs to Godot breaks the one illusion the
	# whole project rests on.
	menu = SuitMenu.new()
	menu.name = "Menu"
	_vp.add_child(menu)
	# The flight HUD stands down while the menu is up. Two interfaces on one piece of glass
	# is two things competing for the same corners, and in the first render the integrity
	# panel sat straight through the menu's title.
	menu.opened.connect(func(): hud.visible = false)
	menu.closed.connect(func(): hud.visible = true)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/visor.gdshader")

	_screen = TextureRect.new()
	_screen.texture = _vp.get_texture()
	_screen.material = mat
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_screen)

	_fit()
	get_viewport().size_changed.connect(_fit)

func _target_size() -> Vector2i:
	var v := get_viewport()
	return v.get_visible_rect().size as Vector2i if v != null else Vector2i(1920, 1080)

## SIZE THEM EXPLICITLY. Anchors alone do not.
##
## Both panels called set_anchors_preset(PRESET_FULL_RECT) in their own _ready and that
## looked like enough. It is not: a Control parented to a SubViewport is left at size ZERO,
## and a zero-sized Control still draws. Everything laid out from the top-left came out in a
## tiny cluster in the corner, and everything laid out from the far edge — the whole
## repulsor panel, at `size.x - 340` — went to a negative x and off the screen entirely.
## That single measurement explains three separate bug reports: the integrity bar cropped in
## the corner, the menu opening as "male okienko przyciete", and the ammo counts not being
## there at all.
##
## It survived because the screenshot tool builds a Hud and a SuitMenu itself and sizes
## them, so the renders were always right while the game was always wrong. A preview that
## does not go through the real path proves nothing about the real path.
func _fit() -> void:
	var sz := _target_size()
	if sz.x < 1 or sz.y < 1:
		return
	_vp.size = sz
	for c: Control in [hud, menu]:
		c.position = Vector2.ZERO
		c.size = Vector2(sz)

func _process(_delta: float) -> void:
	# The window is not always at its final size when _ready runs, and size_changed does not
	# always reach a CanvasLayer added this early. Comparing two integers per frame is
	# cheaper than another evening spent on a HUD in the corner.
	if hud != null and Vector2i(hud.size) != _target_size():
		_fit()
