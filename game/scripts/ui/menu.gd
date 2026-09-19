class_name SuitMenu
extends Control
## The in-suit menu. Opened with the touchpad, driven entirely by the pad.
##
## Jurek's shape: tabs across the top, L1 and R1 to move between them, and the first tab is
## the armour bay — Mark I is yours and the rest are bought. Nothing here is clickable,
## because there is no mouse: the stick moves the selection and ✕ takes it.
##
## It is drawn rather than built out of Control nodes. For a panel this size that is less
## code, not more, and it means the whole thing lives in one file where the layout and the
## rules it is expressing sit next to each other. A dozen nested containers with their
## anchors spread across a scene file would be harder to change, not easier.
##
## THE MENU IS DIEGETIC. It is the suit's own display, so it uses the visor's palette and
## goes through the same curved glass — see scripts/ui/visor.gd. A menu that looks like it
## belongs to the game engine rather than to the armour breaks the one illusion the whole
## project is built on.

signal opened
signal closed
signal armor_chosen(id: String)
signal purchase_attempted(id: String, price: int)

const CYAN := Color(0.55, 0.88, 1.0)
const AMBER := Color(1.0, 0.72, 0.28)
const DIM := Color(0.45, 0.58, 0.68)
const LOCKED := Color(0.38, 0.42, 0.48)

const TABS := ["ARMOUR BAY", "LOADOUT", "FLIGHT", "CONTROLS"]

## Price in credits. The Mark I is free because it is the one he built in a cave.
const CATALOGUE := [
	{ id = "mk1",  name = "MARK I",     sub = "CAVE BUILD",      price = 0 },
	{ id = "mk2",  name = "MARK II",    sub = "PROTOTYPE",       price = 1200 },
	{ id = "mk3",  name = "MARK III",   sub = "RED AND GOLD",    price = 3000 },
	{ id = "mk42", name = "MARK XLII",  sub = "PREHENSILE",      price = 6500 },
	{ id = "mk50", name = "MARK L",     sub = "NANOTECH",        price = 14000 },
]

var tab := 0
var row := 0
var owned := { "mk1": true }
var credits := 0
var equipped := "mk1"
var _msg := ""
var _msg_t := 0.0
var _nav_cool := 0.0
var _open := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func open() -> void:
	_open = true
	visible = true
	row = 0
	opened.emit()
	queue_redraw()

func close() -> void:
	_open = false
	visible = false
	closed.emit()

var is_open: bool:
	get: return _open

## Driven from the suit every frame. Real seconds, so the menu does not crawl if the world
## happens to be in slow motion behind it.
func step(delta: float) -> void:
	if not _open:
		return
	# Reached through the tree rather than as a global, so this file can be drawn by a tool
	# that has no autoloads — the glyphs are static, but the polling is not.
	var pad: PadInput = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		pad = (loop as SceneTree).root.get_node_or_null("/root/Pad") as PadInput
	if pad == null:
		return
	if _msg_t > 0.0:
		_msg_t -= delta

	if pad.just_pressed("pause") or pad.just_pressed("menu") or pad.just_pressed("ui_back"):
		close()
		return

	# L1 and R1 move between tabs, which is the console convention and leaves the stick free
	# for the list.
	if pad.just_pressed("fire_l"):
		tab = wrapi(tab - 1, 0, TABS.size()); row = 0
	if pad.just_pressed("fire_r"):
		tab = wrapi(tab + 1, 0, TABS.size()); row = 0

	# A stick is analog and a list is not, so it has to be rate-limited or one flick scrolls
	# the whole catalogue. Repeats while held, after a pause, like a key.
	_nav_cool = maxf(0.0, _nav_cool - delta)
	var mv: float = pad.move().y
	if absf(mv) > 0.55 and _nav_cool <= 0.0:
		row = clampi(row + (1 if mv > 0.0 else -1), 0, maxi(0, _rows() - 1))
		_nav_cool = 0.16
	elif absf(mv) < 0.3:
		_nav_cool = 0.0

	if pad.just_pressed("ui_accept_pad"):
		_accept()
	queue_redraw()

func _rows() -> int:
	return CATALOGUE.size() if tab == 0 else 0

func _accept() -> void:
	if tab != 0:
		return
	var item: Dictionary = CATALOGUE[row]
	if owned.get(item.id, false):
		equipped = item.id
		armor_chosen.emit(item.id)
		_say("%s ONLINE" % item.name)
	elif credits >= item.price:
		credits -= item.price
		owned[item.id] = true
		purchase_attempted.emit(item.id, item.price)
		_say("%s ACQUIRED" % item.name)
	else:
		_say("NEED %d MORE CREDITS" % (item.price - credits))

func _say(t: String) -> void:
	_msg = t
	_msg_t = 2.4

## EVERYTHING IS SIZED IN UNITS, NOT PIXELS.
##
## The first cut used fixed pixel sizes, which looked right in the editor and then drew a
## postage stamp in the middle of a 3584-pixel Retina capture. A HUD has to hold its
## proportions across every screen it will ever be on, so one number — the viewport height
## against a 1080p reference — scales the lot.
func _u() -> float:
	return maxf(0.55, size.y / 1080.0)

func _draw() -> void:
	var s := size
	var u := _u()
	# A dark wash rather than a solid panel: the suit is still there behind it, and being
	# able to see it is the point of a menu that lives inside the helmet.
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.05, 0.08, 0.72), true)

	var m := Vector2(s.x * 0.07, s.y * 0.13)
	var w := s.x - m.x * 2.0

	_text(Vector2(m.x, m.y - 18 * u), "MARK ZERO", CYAN, int(15 * u))
	draw_line(Vector2(m.x, m.y + 4 * u), Vector2(m.x + w, m.y + 4 * u), Color(CYAN.r, CYAN.g, CYAN.b, 0.35), maxf(1.0, u))

	# ---- tabs -----------------------------------------------------------------------
	var tx := m.x
	for i in TABS.size():
		var on := i == tab
		var label: String = TABS[i]
		var tw := label.length() * 12.0 * u + 36.0 * u
		if on:
			draw_rect(Rect2(Vector2(tx, m.y + 16 * u), Vector2(tw, 34 * u)), Color(CYAN.r, CYAN.g, CYAN.b, 0.14), true)
			draw_rect(Rect2(Vector2(tx, m.y + 16 * u), Vector2(tw, 34 * u)), Color(CYAN.r, CYAN.g, CYAN.b, 0.5), false, maxf(1.0, u))
		_text(Vector2(tx + 18 * u, m.y + 39 * u), label, CYAN if on else DIM, int(14 * u))
		tx += tw + 9.0 * u
	# The two buttons that move between tabs, named on screen. A control the player has to
	# discover is a control most players never find.
	_text(Vector2(m.x + w - 165 * u, m.y + 39 * u), "%s  ◀  ▶  %s" % [PadInput.glyph("fire_l"), PadInput.glyph("fire_r")], DIM, int(13 * u))

	var top := m.y + 76.0 * u
	match tab:
		0: _draw_bay(Vector2(m.x, top), w, s.y - top - m.y * 1.6, u)
		1: _draw_stub(Vector2(m.x, top), "LOADOUT", "Shoulder turret and wrist laser go here.", u)
		2: _draw_stub(Vector2(m.x, top), "FLIGHT", "Trim, assists and camera preferences.", u)
		3: _draw_controls(Vector2(m.x, top), w, u)

	# ---- footer ---------------------------------------------------------------------
	var fy := s.y - m.y * 0.45
	_text(Vector2(m.x, fy), "CREDITS  %d" % credits, AMBER, int(15 * u))
	var hint := "%s SELECT     %s BACK" % [PadInput.glyph("ui_accept_pad"), PadInput.glyph("ui_back")]
	_text(Vector2(m.x + w - hint.length() * 8.6 * u, fy), hint, DIM, int(13 * u))
	if _msg_t > 0.0:
		var a: float = clampf(_msg_t, 0.0, 1.0)
		_text(Vector2(m.x, fy - 30 * u), _msg, Color(AMBER.r, AMBER.g, AMBER.b, a), int(16 * u))

func _draw_bay(at: Vector2, w: float, h: float, u: float) -> void:
	var rh := 70.0 * u
	var gap := 9.0 * u
	var list_w := w * 0.55
	for i in CATALOGUE.size():
		var item: Dictionary = CATALOGUE[i]
		var y := at.y + i * (rh + gap)
		var have: bool = owned.get(item.id, false)
		var sel := i == row
		var is_on: bool = item.id == equipped

		if sel:
			draw_rect(Rect2(Vector2(at.x, y), Vector2(list_w, rh)), Color(CYAN.r, CYAN.g, CYAN.b, 0.10), true)
			# A bright edge on the left rather than a full border: it marks the row without
			# boxing it in, and it reads at a glance from across a room.
			draw_rect(Rect2(Vector2(at.x, y), Vector2(4 * u, rh)), CYAN, true)

		var name_col := CYAN if have else LOCKED
		_text(Vector2(at.x + 22 * u, y + 30 * u), item.name, name_col, int(21 * u))
		_text(Vector2(at.x + 22 * u, y + 52 * u), item.sub, DIM if have else LOCKED, int(12 * u))

		var right := at.x + list_w - 22 * u
		if is_on:
			_right(Vector2(right, y + 40 * u), "EQUIPPED", AMBER, int(15 * u))
		elif have:
			_right(Vector2(right, y + 40 * u), "OWNED", DIM, int(15 * u))
		else:
			var col: Color = AMBER if credits >= item.price else LOCKED
			_right(Vector2(right, y + 40 * u), "%d CR" % item.price, col, int(16 * u))

	# The detail panel. Shows what the selection actually buys you, in the numbers the
	# flight model really uses — a shop that quotes made-up stats is a shop that lies. Sized
	# to its CONTENT rather than to a fraction of the screen, which left it three-quarters
	# empty on a tall display.
	var item2: Dictionary = CATALOGUE[row]
	var spec := SuitSpecs.get_spec(item2.id)
	var rows := [
		["TOP SPEED", "%d m/s" % spec.top_speed],
		["THRUST", "%.1f g" % (spec.main / spec.mass / 9.81)],
		["MASS", "%d kg" % spec.mass],
		["INTEGRITY", "%d" % spec.integrity],
		["REACTOR", "%.2f" % spec.power],
		["SUPERSONIC", "NO" if item2.id == "mk1" else "YES"],
	]
	var px := at.x + w * 0.60
	var pw := w - (px - at.x)
	var ph := (86.0 + rows.size() * 30.0 + (26.0 if spec.flaw != "" else 0.0)) * u
	draw_rect(Rect2(Vector2(px, at.y), Vector2(pw, ph)), Color(0.03, 0.08, 0.12, 0.6), true)
	draw_rect(Rect2(Vector2(px, at.y), Vector2(pw, ph)), Color(CYAN.r, CYAN.g, CYAN.b, 0.28), false, maxf(1.0, u))
	_text(Vector2(px + 20 * u, at.y + 36 * u), spec.name, CYAN, int(23 * u))
	for i in rows.size():
		var ry := at.y + 74 * u + i * 30 * u
		_text(Vector2(px + 20 * u, ry), rows[i][0], DIM, int(13 * u))
		_right(Vector2(px + pw - 20 * u, ry), rows[i][1], CYAN, int(15 * u))
	if spec.flaw != "":
		_text(Vector2(px + 20 * u, at.y + 74 * u + rows.size() * 30 * u + 16 * u),
			"FLAW: " + spec.flaw.to_upper(), AMBER, int(13 * u))

func _draw_controls(at: Vector2, w: float, u: float) -> void:
	var pairs := [
		["move", "FLY / WALK"], ["look", "LOOK"], ["supersonic", "SUPERSONIC"],
		["aim", "AIM (SLOWS TIME)"], ["fire_r", "RIGHT REPULSOR"], ["fire_l", "LEFT REPULSOR"],
		["turret", "SHOULDER TURRET"], ["up", "CLIMB"], ["suit_toggle", "SUIT ON / OFF"],
		["interact", "INTERACT"], ["menu", "THIS MENU"],
	]
	for i in pairs.size():
		var y := at.y + 26 * u + i * 34 * u
		_right(Vector2(at.x + 150 * u, y), PadInput.glyph(pairs[i][0]), AMBER, int(17 * u))
		_text(Vector2(at.x + 172 * u, y), pairs[i][1], CYAN, int(15 * u))

func _draw_stub(at: Vector2, title: String, note: String, u: float) -> void:
	_text(Vector2(at.x, at.y + 30 * u), title, CYAN, int(23 * u))
	_text(Vector2(at.x, at.y + 60 * u), note, DIM, int(15 * u))
	_text(Vector2(at.x, at.y + 86 * u), "NOT BUILT YET", LOCKED, int(13 * u))

func _text(at: Vector2, t: String, c: Color, px: int) -> void:
	draw_string(ThemeDB.fallback_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)

func _right(at: Vector2, t: String, c: Color, px: int) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(f, Vector2(at.x - w, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)
