extends Node
## Does every sound in the bank actually exist and load?
##
## A missing stream is silent, and silence is exactly what an unwired sound sounds like —
## so "it did not play" and "it was never there" are indistinguishable by ear. This is the
## only check that tells them apart, and it has to be a SCENE because loading an audio
## resource needs the resource system a `--script` run does not fully bring up.

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _ready() -> void:
	print("=== the bank ===")
	var missing: Array = []
	for key in Sfx.BANK:
		var res = load(Sfx.BANK[key])
		if res == null or not (res is AudioStream):
			missing.append(key)
	_ok(missing.is_empty(), "every sound loads (%d of %d)%s" % [
		Sfx.BANK.size() - missing.size(), Sfx.BANK.size(),
		"" if missing.is_empty() else "  missing: " + ", ".join(missing)])

	# Jurek's standing rule, from a previous project: this one specifically is not to be
	# used, and Claude had been pasting it onto every success everywhere.
	var banned := false
	for key in Sfx.BANK:
		if String(Sfx.BANK[key]).contains("confirmation"):
			banned = true
	_ok(not banned, "and none of them is the confirmation ding Jurek banned")

	print("=== it comes up with the game ===")
	var arena: Node3D = load("res://scenes/world/arena.tscn").instantiate()
	add_child(arena)
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_ok(Sfx.ready_for_sound(), "the arena builds a working sound bank")

	# And the engine note is a LOOP. A one-shot here reads as the suit cutting out after
	# two seconds, which is worse than having no engine sound at all.
	var hum = load("res://assets/audio/thruster_loop.ogg")
	_ok(hum != null, "the engine note is there")
	if hum is AudioStreamOggVorbis:
		_ok((hum as AudioStreamOggVorbis).loop, "and it loops")

	# Playing into the void must be safe: every test and tool in this project runs without
	# a bank, and a null check missed anywhere would take all of them down.
	Sfx.play("no_such_sound", Vector3.ZERO)
	Sfx.flat("no_such_sound")
	_ok(true, "asking for a sound that does not exist is harmless")

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
