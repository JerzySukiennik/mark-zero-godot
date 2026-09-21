extends Node
## The rules the lobby exists to enforce. Run as a SCENE — Net is an autoload.
##   godot --headless --path . res://tools/test_lobby.tscn

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
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

	print("=== two machines reach the SAME answer about who is who ===")
	# The bug this replaces: the rule was "move the newcomer", and the newcomer is a
	# different person on each machine, so the host's screen and the joiner's screen
	# disagreed about which of them was Iron Man. Both sides here declare Iron Man, which
	# is the default, so it is also the ordinary case rather than an awkward one.
	Net.unlock_heroes()

	# The HOST's view: it is peer 1 and already in, then 77 arrives wanting Iron Man.
	Net.players = { 1: { name = "HOST", armor = "mk3", hero = "ironman" } }
	Net._register(77, "JOIN", "mk3", "ironman")
	var host_view := "%s/%s" % [Net.players[1].hero, Net.players[77].hero]

	# The JOINER's view of the very same room: it is peer 77 and knows only itself, then
	# the host arrives, also wanting Iron Man.
	Net.players = { 77: { name = "JOIN", armor = "mk3", hero = "ironman" } }
	Net._register(1, "HOST", "mk3", "ironman")
	var join_view := "%s/%s" % [Net.players[1].hero, Net.players[77].hero]

	_ok(host_view == join_view,
		"both machines agree (host sees %s, joiner sees %s)" % [host_view, join_view])
	_ok(host_view == "ironman/spiderman",
		"and the host keeps the side it picked (%s)" % host_view)

	print("=== two players cannot be the same character ===")
	# Fresh roster: the block above left peer 77 in it, and a stale third player makes
	# hero_taken_by answer about the wrong person.
	Net.players = { 1: { name = "JUREK", armor = "mk1", hero = "spiderman" } }
	Net.local_hero = "spiderman"
	Net.players[2] = { name = "NAREK", armor = "mk3", hero = "ironman" }
	Net.set_hero(1, "ironman")
	_ok(Net.players[2].get("hero", "") == "spiderman",
		"claiming a side pushes whoever held it onto the other (%s)"
			% Net.players[2].get("hero", "?"))
	_ok(Net.hero_taken_by("spiderman") == "NAREK",
		"and the lobby can say who has it")
	_ok(Net.hero_taken_by("ironman") == "", "but not report your own side as taken")

	print("=== everyone in the lobby is listening for the start, not just the host ===")
	# The bug: the listener was hooked up inside the START MATCH handler, which runs only
	# on the machine that pressed it. Only the host presses it, so on every other machine
	# the signal arrived with nobody attached and the player sat in the lobby forever.
	# Asked of a lobby that has been OPENED and nothing else, which is exactly the state a
	# joining player is in.
	Net.unlock_heroes()
	var menu: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.call("_open_lobby")
	_ok(Net.match_started.get_connections().size() >= 1,
		"opening the lobby subscribes to the match starting (%d listener(s))"
			% Net.match_started.get_connections().size())
	menu.call("_close_lobby")
	_ok(Net.match_started.get_connections().size() == 0,
		"and backing out of it unsubscribes again")
	menu.queue_free()

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
