extends Node
## DOES THE GAME ACTUALLY RUN? Driven as a SCENE, not with `--script`.
##
## Every other suite here runs under `godot --script`, which has no autoloads — so none of
## them can even load SuitPilot or SpiderPilot, both of which reference Net. Twelve suites
## went green while SpiderPilot did not COMPILE, and choosing Spider-Man therefore freed the
## Iron Man and spawned nothing at all. From the pad that looked like the button doing
## nothing; underneath, the player entity could not be constructed.
##
## So this one boots the real arena and drives the real roster. Run it with:
##   godot --headless --path . res://tools/swap_test.tscn

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _ready() -> void:
	# Both player scripts must LOAD. This is the check that was missing: a parse error in
	# either is invisible to every `--script` suite.
	for path: String in ["res://scripts/suit/suit_pilot.gd", "res://scripts/spider/spider_pilot.gd"]:
		var scr = load(path)
		_ok(scr != null and scr.can_instantiate(), "%s compiles" % path.get_file())

	var arena: Node3D = load("res://scenes/world/arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	print("=== starting as Iron Man ===")
	_ok(Net.local_hero == "ironman", "the game opens on Iron Man")
	_ok(arena.suits.size() == 1, "one entity in the arena (%d)" % arena.suits.size())
	var first = arena.suits.get(1)
	_ok(first != null and first is SuitPilot, "and it is the armour")
	_ok(Net.players[1].get("armor", "") == "mk1", "wearing the Mark I")

	print("=== switching to Spider-Man ===")
	Net.announce_hero("spiderman")
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout

	_ok(Net.local_hero == "spiderman", "the roster says Spider-Man")
	_ok(arena.suits.size() == 1, "there is still exactly one entity (%d)" % arena.suits.size())
	var now = arena.suits.get(1)
	_ok(now != null, "the entity EXISTS — the armour was not simply deleted")
	_ok(now is SpiderPilot, "and it is Spider-Man")
	if now is SpiderPilot:
		_ok(now.rig != null, "he has a body")
		_ok(now.skel != null and now.skel.has_pivot("piv_palmL"), "and a rig with hands")

	print("=== and back again ===")
	Net.announce_hero("ironman")
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	_ok(arena.suits.get(1) is SuitPilot, "switching back returns the armour")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
