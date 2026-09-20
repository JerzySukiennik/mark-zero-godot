class_name LobbyUi
extends Control
## The lobby: where you choose which of the two you are, and who you are playing with.
##
## Jurek: "raz w lobby się wybiera character i potem już nie można zmieniać." So this
## screen is the ONLY place the question is asked. Everything below exists to make that
## one decision, and then to get into a match without ever needing a keyboard.
##
## It draws over the menu's own scene — the slowly orbiting Iron Man and Spider-Man are
## still there behind it, which is the whole reason the choice is made here rather than on
## a blank page: you pick the one you can see.

signal start_requested
signal back

const CYAN := Color(0.55, 0.88, 1.0)
const AMBER := Color(1.0, 0.72, 0.28)
const DIM := Color(0.48, 0.58, 0.68)
const OFF := Color(0.34, 0.38, 0.44)

## Rows are built fresh every frame from the state of the room, because the room changes
## underneath the cursor: hosts appear, players join, sides get taken. Each row is
## { kind, label, note, on } where `kind` is what pressing it does.
var _rows: Array = []
var row := 0
var _cool := 0.0
var _status := ""
var _status_t := 0.0

var disc: Discovery

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc = Discovery.new()
	disc.name = "Discovery"
	add_child(disc)
	disc.begin_listen()
	set_process(true)

func _exit_tree() -> void:
	if disc != null and is_instance_valid(disc):
		disc.stop()

func _say(t: String) -> void:
	_status = t
	_status_t = 3.5

# ---- what is on the screen right now ---------------------------------------------------

func _build() -> void:
	_rows.clear()
	# SIDES FIRST, because it is the decision the screen is for.
	for hero in Net.HEROES:
		var taken := Net.hero_taken_by(hero)
		_rows.append({
			kind = "hero:" + hero,
			label = "IRON MAN" if hero == "ironman" else "SPIDER-MAN",
			note = ("· " + taken.to_upper() if taken != "" else ""),
			on = taken == "" and Net.local_hero == hero,
			dead = taken != "",
		})

	if not Net.online:
		_rows.append({ kind = "solo", label = "PLAY SOLO", note = "", on = false, dead = false })
		_rows.append({ kind = "host", label = "OPEN A ROOM", note = "others on this network can join",
			on = false, dead = false })
		var found: Array = disc.listed()
		for r in found:
			_rows.append({
				kind = "join:%s:%d" % [r["address"], r["port"]],
				label = String(r["name"]).to_upper() + "'S ROOM",
				note = "%d/%d  ·  %s" % [r["players"], r["max"], r["address"]],
				on = false, dead = false,
			})
		if found.is_empty():
			_rows.append({ kind = "", label = "", note = "SEARCHING FOR ROOMS ON THIS NETWORK…",
				on = false, dead = true })
	else:
		# In a room: who is here, and the one button that matters.
		for pid in Net.players:
			var p: Dictionary = Net.players[pid]
			var side: String = "IRON MAN" if p.get("hero", "") == "ironman" else "SPIDER-MAN"
			_rows.append({
				kind = "",
				label = String(p.get("name", "PILOT")).to_upper() + ("  (YOU)" if pid == Net.my_id else ""),
				note = side, on = false, dead = true,
			})
		if Net.is_host:
			_rows.append({ kind = "start", label = "START MATCH",
				note = "everyone drops in together", on = false, dead = false })
		else:
			_rows.append({ kind = "", label = "WAITING FOR THE HOST…", note = "",
				on = false, dead = true })
		_rows.append({ kind = "leave", label = "LEAVE ROOM", note = "", on = false, dead = false })

func _first_live(from: int, dir: int) -> int:
	# Skips the rows that are only there to be read. A cursor that can land on a heading
	# is a cursor the player has to learn the shape of.
	var n := _rows.size()
	for i in n:
		var k := wrapi(from + dir * (i + 1), 0, n)
		if not _rows[k].get("dead", false):
			return k
	return from

func _process(delta: float) -> void:
	size = get_viewport_rect().size
	_cool = maxf(0.0, _cool - delta)
	_status_t = maxf(0.0, _status_t - delta)
	_build()
	row = clampi(row, 0, maxi(0, _rows.size() - 1))
	if not _rows.is_empty() and _rows[row].get("dead", false):
		row = _first_live(row, 1)

	var mv := Pad.move().y if Pad.connected else 0.0
	if Input.is_action_pressed("ui_down"):
		mv = 1.0
	elif Input.is_action_pressed("ui_up"):
		mv = -1.0
	if absf(mv) > 0.55 and _cool <= 0.0:
		row = _first_live(row, 1 if mv > 0.0 else -1)
		_cool = 0.18
		Sfx.flat("ui_move", -13.0)
	elif absf(mv) < 0.3:
		_cool = 0.0

	if Input.is_action_just_pressed("ui_back") or Input.is_action_just_pressed("ui_cancel") \
			or Pad.just_pressed("ui_back_pad"):
		Sfx.flat("ui_close", -10.0)
		if Net.online:
			Net.leave()
		back.emit()
		return

	if Input.is_action_just_pressed("ui_accept") or Pad.just_pressed("ui_accept_pad"):
		_press(String(_rows[row].get("kind", "")))
	queue_redraw()

func _press(kind: String) -> void:
	if kind == "":
		return
	Sfx.flat("ui_select", -9.0)
	if kind.begins_with("hero:"):
		Net.announce_hero(kind.substr(5))
		return
	if kind.begins_with("join:"):
		var bits := kind.split(":")
		if Net.join(bits[1], int(bits[2])):
			_say("JOINING %s…" % bits[1])
		else:
			_say("COULD NOT REACH THAT ROOM")
		return
	match kind:
		"solo":
			start_requested.emit()
		"host":
			if Net.host():
				disc.begin_beacon()
				_say("ROOM OPEN — others can see it now")
				row = 0
			else:
				_say("COULD NOT OPEN A ROOM ON PORT %d" % Net.DEFAULT_PORT)
		"start":
			start_requested.emit()
		"leave":
			Net.leave()
			disc.stop()
			disc.begin_listen()
			_say("LEFT THE ROOM")

# ---- drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var u: float = maxf(0.55, size.y / 1080.0)
	var font := ThemeDB.fallback_font

	draw_string(font, Vector2(72 * u, 108 * u), "MARK ZERO",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(64 * u), CYAN)
	draw_string(font, Vector2(76 * u, 142 * u),
		"CHOOSE YOUR SIDE — you keep it for the whole match",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * u), DIM)

	var x := 86.0 * u
	var y := size.y - (78.0 + 52.0 * _rows.size()) * u
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var here := i == row
		var lab := String(r.get("label", ""))
		if lab != "":
			var col := OFF if r.get("dead", false) else (CYAN if here else DIM)
			# The side you are currently holding is amber, the same colour the HUD uses
			# for "this is yours", whether or not the cursor is on it.
			if r.get("on", false):
				col = AMBER
			if here and not r.get("dead", false):
				draw_rect(Rect2(Vector2(64 * u, y - 24 * u), Vector2(5 * u, 32 * u)), CYAN, true)
			draw_string(font, Vector2(x, y), lab,
				HORIZONTAL_ALIGNMENT_LEFT, -1, int((32.0 if here else 27.0) * u), col)
			var note := String(r.get("note", ""))
			if note != "":
				draw_string(font, Vector2(x + 360 * u, y), note,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * u), OFF)
		else:
			draw_string(font, Vector2(x, y), String(r.get("note", "")),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * u), OFF)
		y += 52 * u

	if _status_t > 0.0:
		draw_string(font, Vector2(x, size.y - 92 * u), _status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * u), AMBER)
	draw_string(font, Vector2(72 * u, size.y - 56 * u),
		"STICK  MOVE      ✕  SELECT      ○  BACK",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * u), DIM)
