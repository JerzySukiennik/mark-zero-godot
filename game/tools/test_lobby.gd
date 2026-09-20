extends Node
## The rules the lobby exists to enforce. Run as a SCENE — Net is an autoload.
##   godot --headless --path . res://tools/test_lobby.tscn

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _ready() -> void:
	Net.unlock_heroes()
	Net.players = { 1: { name = "JUREK", armor = "mk1", hero = "ironman" } }
	Net.local_hero = "ironman"
	Net.local_armor = "mk1"

	print("=== a game nobody has networked is not online ===")
	# Godot hands every project an OfflineMultiplayerPeer that reports itself as CONNECTED,
	# so the obvious test for "are we in a room" answers yes at the title screen.
	_ok(not Net.online, "sitting at the menu alone is not a room")
	_ok(Net.my_id == 1, "and you are peer 1")

	print("=== changing your armour is not a statement about who you are ===")
	# The bug: offline, announce_armor rebuilt the player row without a `hero` key, so the
	# hero silently fell back to the default on every suit change.
	Net.announce_hero("spiderman")
	_ok(Net.local_hero == "spiderman", "you can pick Spider-Man in the lobby")
	Net.announce_armor("mk50")
	_ok(Net.players[Net.my_id].get("hero", "") == "spiderman",
		"and changing armour leaves you as Spider-Man (%s)"
			% Net.players[Net.my_id].get("hero", "GONE"))
	_ok(Net.local_armor == "mk50", "while still changing the armour")

	print("=== and once the match starts, the side is yours ===")
	Net.begin_match()
	_ok(Net.hero_locked, "starting a match locks the sides")
	Net.announce_hero("ironman")
	_ok(Net.local_hero == "spiderman",
		"pressing it in the suit menu does nothing (%s)" % Net.local_hero)
	# The receiving end must refuse too: the exclusivity rule moves whoever holds a side,
	# so an unchecked late call would change a character somebody ELSE is playing.
	Net.set_hero(Net.my_id, "ironman")
	_ok(Net.local_hero == "spiderman", "and neither does the call underneath it")

	print("=== leaving the match asks the question again ===")
	Net.end_match()
	_ok(not Net.hero_locked, "coming out to the menu unlocks them")
	Net.announce_hero("ironman")
	_ok(Net.local_hero == "ironman", "so the next match can be the other one")

	print("=== two players cannot be the same character ===")
	Net.players[2] = { name = "NAREK", armor = "mk3", hero = "ironman" }
	Net.set_hero(1, "ironman")
	_ok(Net.players[2].get("hero", "") == "spiderman",
		"claiming a side pushes whoever held it onto the other (%s)"
			% Net.players[2].get("hero", "?"))
	_ok(Net.hero_taken_by("spiderman") == "NAREK",
		"and the lobby can say who has it")
	_ok(Net.hero_taken_by("ironman") == "", "but not report your own side as taken")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
