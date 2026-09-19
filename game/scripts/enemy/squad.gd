class_name Squad
extends Node3D
## Puts thugs on the plate and keeps the fight going.
##
## Deliberately a spawner rather than a level: there is no campaign yet, and what is needed
## first is something to shoot at while the feel of shooting is being tuned. Waves keep a
## roughly constant number alive and get harder as they go, so a session is never five
## minutes of nothing followed by one brawl.

## How many are alive at once, at wave one and at the cap.
const START_ALIVE := 5
const MAX_ALIVE := 14
## Seconds between spawns, and how much a wave tightens it.
const SPAWN_GAP := 2.2
## Where they come from, relative to whoever they are after.
const RING_MIN := 34.0
const RING_MAX := 78.0

var guns: Gunfire
var wave := 1
## UNTYPED on purpose. A freed Node is still a value in the array until it is pruned, and
## assigning a list containing one back into an Array[Enemy] fails the type conversion
## with "invalid previously freed instance" — the prune itself becomes the crash.
var alive: Array = []
var _gap := 1.5
var _stage: Stage
var _enabled := true

## Which kinds are available, by wave. Fists first, then knives, then the men with guns,
## and the brute last — so the player meets one new problem at a time rather than all of
## them in the first thirty seconds.
const ROSTER := [
	{ wave = 1, kinds = ["brawler"] },
	{ wave = 2, kinds = ["brawler", "knifer"] },
	{ wave = 3, kinds = ["brawler", "knifer", "pistol"] },
	{ wave = 4, kinds = ["brawler", "knifer", "pistol", "rifle"] },
	{ wave = 5, kinds = ["knifer", "pistol", "rifle", "brute"] },
	{ wave = 6, kinds = ["brawler", "pistol", "rifle", "rpg", "brute"] },
]

func setup(stage: Stage) -> void:
	_stage = stage

func _ready() -> void:
	name = "Squad"
	guns = Gunfire.new()
	guns.name = "Gunfire"
	# In the WORLD, not on a thug: a round already in the air has to outlive whoever fired
	# it, and every one of them is on a twelve second timer.
	add_child(guns)

func set_enabled(on: bool) -> void:
	_enabled = on

func _physics_process(delta: float) -> void:
	# Pruned by hand rather than with filter(), so a freed entry is dropped before anything
	# tries to read a property off it.
	var still: Array = []
	for e in alive:
		if is_instance_valid(e):
			still.append(e)
	alive = still
	if not _enabled:
		return
	_gap -= delta
	if _gap > 0.0:
		return
	_gap = maxf(0.7, SPAWN_GAP - wave * 0.16)

	var cap: int = mini(MAX_ALIVE, START_ALIVE + wave)
	if alive.size() >= cap:
		# A full field for a while means the player is holding: push the wave on.
		wave = mini(wave + 1, ROSTER.size())
		return
	_spawn()

## Picks a kind for the current wave and drops one in a ring around the player.
func _spawn() -> void:
	var target := _player()
	if target == null:
		return
	var kinds: Array = ROSTER[0].kinds
	for row in ROSTER:
		if wave >= int(row.wave):
			kinds = row.kinds
	var kind: String = kinds[randi() % kinds.size()]

	var e := Enemy.new()
	e.name = "Enemy_%s_%d" % [kind, randi() % 10000]
	e.setup(kind, guns)
	add_child(e)

	var a := randf() * TAU
	var r := randf_range(RING_MIN, RING_MAX)
	var at := target.global_position + Vector3(sin(a) * r, 0, cos(a) * r)
	# On the plate, whatever height the player happens to be at — they walk, they do not
	# spawn in mid-air under an Iron Man who is hovering at two hundred metres.
	at.y = (_stage.ground_y if _stage != null else 0.0) + 0.1
	e.global_position = at
	alive.append(e)

func _player() -> Node3D:
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node3D and (n as Node3D).is_inside_tree():
			return n
	return null

## Everything currently on its feet, for the HUD.
func standing() -> int:
	var n := 0
	for e in alive:
		if is_instance_valid(e) and e.state != Enemy.DOWN:
			n += 1
	return n
