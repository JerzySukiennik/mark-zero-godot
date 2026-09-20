class_name Sfx
extends Node
## Every sound in the game, and the pool that plays them.
##
## NOT an autoload, and the reason is the oldest lesson in this project: `godot --script`
## has no autoloads, so a test or a screenshot tool that touches anything which reaches
## for one cannot run at all. Instead the arena builds one of these and it registers
## itself in a static slot — so `Sfx.play(...)` works from anywhere, and is a silent
## no-op everywhere there is no instance, which is exactly what a headless suite wants.
##
## The same reasoning Rumble already uses.

## One entry per sound. Everything is loaded once at startup rather than on first use: a
## repulsor that stutters the first time it fires has told the player something untrue
## about the weapon.
const BANK := {
	# ---- the armour ----------------------------------------------------------------
	"repulsor":     "res://assets/audio/repulsor.ogg",
	"repulsor_dry": "res://assets/audio/repulsor_dry.ogg",
	"turret":       "res://assets/audio/turret.ogg",
	"boost":        "res://assets/audio/boost.ogg",
	"armour_drop":  "res://assets/audio/armour_drop.ogg",
	"hit_metal":    "res://assets/audio/hit_metal.ogg",
	"explosion":    "res://assets/audio/explosion.ogg",
	"explosion_low":"res://assets/audio/explosion_low.ogg",
	# ---- Spider-Man ------------------------------------------------------------------
	"thwip":        "res://assets/audio/thwip.wav",
	"web_stick":    "res://assets/audio/web_stick.ogg",
	"swing":        "res://assets/audio/swing_whoosh.ogg",
	"dodge":        "res://assets/audio/dodge.ogg",
	"punch":        "res://assets/audio/punch.ogg",
	"punch_big":    "res://assets/audio/punch_big.ogg",
	"land":         "res://assets/audio/land.ogg",
	"step":         "res://assets/audio/step.ogg",
	# ---- the opposition --------------------------------------------------------------
	"gunshot":      "res://assets/audio/gunshot.wav",
	"gunshot_rifle":"res://assets/audio/gunshot_rifle.wav",
	"rpg_launch":   "res://assets/audio/rpg_launch.ogg",
	"body_drop":    "res://assets/audio/body_drop.ogg",
	"knife":        "res://assets/audio/knife_draw.ogg",
	"lock":         "res://assets/audio/lock_beep.wav",
	# ---- the glass -------------------------------------------------------------------
	"ui_move":      "res://assets/audio/ui_move.ogg",
	"ui_select":    "res://assets/audio/ui_select.ogg",
	"ui_open":      "res://assets/audio/ui_open.ogg",
	"ui_close":     "res://assets/audio/ui_close.ogg",
}

## Positional voices. Sixteen is enough for a firefight and cheap enough not to think about.
const VOICES := 16
## Flat voices, for anything that belongs to the player rather than to a place.
const FLAT_VOICES := 6
## How far a world sound carries before it is inaudible.
const EARSHOT := 140.0

static var _me: Sfx = null

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next := 0
var _next_flat := 0

func _ready() -> void:
	_me = self
	for key in BANK:
		var res = load(BANK[key])
		if res != null:
			_bank[key] = res
		else:
			push_warning("[sfx] missing %s" % BANK[key])
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 18.0
		p.max_distance = EARSHOT
		p.max_db = 0.0
		add_child(p)
		_voices.append(p)
	for i in FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_flat.append(p)

func _exit_tree() -> void:
	if _me == self:
		_me = null

## A sound somewhere in the world. `pitch` is a multiplier, `vol` in decibels.
static func play(key: String, at: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if _me == null:
		return
	_me._play_at(key, at, vol, pitch)

## A sound with no place — the player's own suit, the interface. Never attenuated, because
## the thing it belongs to is always exactly where the listener is.
static func flat(key: String, vol := 0.0, pitch := 1.0) -> void:
	if _me == null:
		return
	_me._play_flat(key, vol, pitch)

## Is there anything to play at all? Lets callers skip work rather than guess.
static func ready_for_sound() -> bool:
	return _me != null

func _play_at(key: String, at: Vector3, vol: float, pitch: float) -> void:
	var stream = _bank.get(key, null)
	if stream == null:
		return
	# ROUND ROBIN, with no stealing logic. A voice cut off mid-shot is less noticeable
	# than the bookkeeping needed to avoid it, and at sixteen it takes a real brawl to
	# wrap around.
	var p := _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = stream
	p.global_position = at
	p.volume_db = vol
	# Every voice is detuned a little. Identical repeats are the single clearest way to
	# make a good sound feel cheap, and a repulsor is fired sixteen times in four seconds.
	p.pitch_scale = pitch * randf_range(0.94, 1.07)
	p.play()

func _play_flat(key: String, vol: float, pitch: float) -> void:
	var stream = _bank.get(key, null)
	if stream == null:
		return
	var p := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	p.stream = stream
	p.volume_db = vol
	p.pitch_scale = pitch * randf_range(0.96, 1.05)
	p.play()
