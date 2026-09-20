class_name PauseMenu
extends CanvasLayer
## Escape, mid-game.
##
## Jurek: "dodaj też menu, jak się przyciśnie Escape na klawiaturze, to wtedy że można
## kontrolować, czyli że wychodzisz z gry." Deliberately three lines and nothing else —
## the suit already has a menu on the touchpad for everything about the suit, and a second
## one competing with it would be two places to look for the same thing.
##
## It pauses the tree, so the fight genuinely stops rather than continuing quietly behind
## a panel while the player reads it.

const ITEMS := ["RESUME", "MAIN MENU", "QUIT"]

var _row := 0
var _panel: _PausePanel
var _cool := 0.0

func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS   # it has to keep running while paused
	_panel = _PausePanel.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	visible = false

func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)

	# ESC on the keyboard, OPTIONS on the pad. Both, because the game is controller-only
	# and the one thing a player reaches for the keyboard to do is leave.
	if Input.is_action_just_pressed("ui_cancel") or Pad.just_pressed("pause"):
		if visible:
			_close()
		else:
			_open()
		return
	if not visible:
		return

	var mv := 0.0
	if Input.is_action_pressed("ui_down"):
		mv = 1.0
	elif Input.is_action_pressed("ui_up"):
		mv = -1.0
	elif Pad.connected:
		mv = Pad.move().y
	if absf(mv) > 0.55 and _cool <= 0.0:
		_row = wrapi(_row + (1 if mv > 0.0 else -1), 0, ITEMS.size())
		_cool = 0.18
		Sfx.flat("ui_move", -13.0)
	elif absf(mv) < 0.3:
		_cool = 0.0

	if Input.is_action_just_pressed("ui_accept") or Pad.just_pressed("ui_accept_pad"):
		Sfx.flat("ui_select", -9.0)
		_pick(ITEMS[_row])
	_panel.row = _row
	_panel.queue_redraw()

func _open() -> void:
	visible = true
	_row = 0
	_panel.row = 0
	get_tree().paused = true
	Sfx.flat("ui_open", -9.0)
	_panel.queue_redraw()

func _close() -> void:
	visible = false
	get_tree().paused = false
	Sfx.flat("ui_close", -10.0)

func _pick(item: String) -> void:
	match item:
		"RESUME":
			_close()
		"MAIN MENU":
			# Unpause FIRST. A scene change into a paused tree gives you a menu that does
			# not respond to anything, which looks exactly like a crash.
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		"QUIT":
			get_tree().paused = false
			get_tree().quit()

class _PausePanel:
	extends Control
	const CYAN := Color(0.55, 0.88, 1.0)
	const DIM := Color(0.48, 0.58, 0.68)
	var row := 0

	func _draw() -> void:
		size = get_viewport_rect().size
		var u: float = maxf(0.55, size.y / 1080.0)
		var font := ThemeDB.fallback_font
		# A wash over the whole screen rather than a box: the game is stopped, and saying
		# so costs one rectangle.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.07, 0.72), true)

		var x := size.x * 0.5 - 150.0 * u
		var y := size.y * 0.5 - 60.0 * u
		draw_string(font, Vector2(x, y - 62 * u), "PAUSED",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(40 * u), CYAN)
		for i in ITEMS.size():
			var on := i == row
			if on:
				draw_rect(Rect2(Vector2(x - 22 * u, y - 24 * u), Vector2(5 * u, 32 * u)), CYAN, true)
			draw_string(font, Vector2(x, y), ITEMS[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				int((32.0 if on else 26.0) * u), CYAN if on else DIM)
			y += 52 * u
