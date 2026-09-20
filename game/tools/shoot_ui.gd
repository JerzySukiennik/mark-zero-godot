extends SceneTree
## Render the menu and the HUD to PNGs, so they can be looked at without playing.
##
## Needs a real rendering context, so this is run WITHOUT --headless. It opens a window,
## draws a few frames, saves, and quits — the window is incidental, the files are the point.

const OUT := "user://ui"

var _shots: Array = []
var _frame := 0
var _menu: SuitMenu
var _hud: Hud
var _root: Control

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var vp := root
	vp.transparent_bg = false

	# A dark backdrop, so the interface is judged against something like the game rather
	# than against a grey void.
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.10, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)

	_hud = Hud.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(_hud)
	_hud.set_armor_name("MARK III")
	_hud.health = 0.78
	_hud.repulsor_l = 0.62
	_hud.repulsor_r = 0.93
	_hud.turret = 0.4
	_hud.flash_turret()
	_hud.feed(0.016, Vector2(0.004, -0.002), 287.0, 0.78, true)

	_menu = SuitMenu.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(_menu)
	# No override any more: every armour is owned, so a preview that pretends otherwise is
	# showing a screen the player will never see.
	_menu.equipped = "mk2"
	_menu.visible = false

	_shots = [
		{ file = "hud.png", setup = func(): _hud.visible = true; _menu.visible = false },
		{ file = "menu_hero.png", setup = func():
			_hud.visible = false
			_menu.visible = true; _menu.tab = 0; _menu.row = 1
			_menu.active_hero = "ironman"
			_menu.taken_heroes = { "spiderman": "NAREK" }
			_menu.queue_redraw() },
		{ file = "menu_bay.png", setup = func():
			_hud.visible = false
			_menu.visible = true; _menu.tab = 1; _menu.row = 2; _menu.queue_redraw() },
		{ file = "menu_bay_top.png", setup = func():
			_hud.visible = false
			_menu.visible = true; _menu.tab = 1; _menu.row = 4; _menu.queue_redraw() },
		{ file = "menu_controls.png", setup = func():
			_hud.visible = false
			_menu.visible = true; _menu.tab = 4; _menu.queue_redraw() },
	]

func _process(_d: float) -> bool:
	_frame += 1
	# A few frames of settle before the first capture: the first frame of a fresh viewport
	# is not what the player ever sees.
	if _frame < 6:
		return false
	var idx := (_frame - 6) / 3
	if idx >= _shots.size():
		print("saved %d files to %s" % [_shots.size(), ProjectSettings.globalize_path(OUT)])
		return true
	if (_frame - 6) % 3 == 0:
		_shots[idx].setup.call()
	elif (_frame - 6) % 3 == 2:
		var img := root.get_texture().get_image()
		img.save_png(OUT + "/" + _shots[idx].file)
	return false
