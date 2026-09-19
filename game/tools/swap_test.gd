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

	print("=== switching to Spider-Man, THROUGH THE MENU ===")
	# Through the menu, not by calling Net. Driving Net directly is what let this pass while
	# the game was broken: the menu's signals were connected off visor.ready, which had
	# already fired, so every handler was dead and pressing X did nothing but print
	# "SELECTED". A test that skips the step the player actually takes tests nothing about
	# that step.
	var menu: SuitMenu = first.visor.menu
	_ok(menu != null, "the armour has a menu")
	_ok(menu.hero_chosen.get_connections().size() > 0,
		"and something is LISTENING to hero_chosen (%d)" % menu.hero_chosen.get_connections().size())
	_ok(menu.armor_chosen.get_connections().size() > 0,
		"and to armor_chosen too (%d)" % menu.armor_chosen.get_connections().size())
	menu.open()
	menu.tab = 0
	menu.row = 1                      # SPIDER-MAN
	menu._accept()
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

	if now is SpiderPilot:
		# He is not wearing an armour and the panels must not claim he is: it still read
		# "MARK I / INTEGRITY / REPULSORS" through the Iron Spider's eyes.
		_ok(now.visor != null and now.visor.hud != null, "Spider-Man has a visor")
		_ok(now.visor.hud._armor_name == "IRON SPIDER",
			"and it names him correctly (%s)" % now.visor.hud._armor_name)
		_ok(now.visor.hud.ammo_label == "WEB FLUID",
			"and counts web fluid, not repulsors (%s)" % now.visor.hud.ammo_label)
		# And he can reach the menu at all, which is the only way back to Iron Man.
		_ok(now.visor.menu != null and now.visor.menu.hero_chosen.get_connections().size() > 0,
			"and his menu is wired up")
		# The four back legs must come out when he leaves the ground.
		now.model.position = Vector3(0, 40, 0)
		now.model.grounded = false
		await get_tree().create_timer(0.8).timeout
		_ok(now.legs.out > 0.9, "the spider legs deploy in the air (%.2f)" % now.legs.out)

	print("=== swinging off the tower ===")
	if now is SpiderPilot:
		# The tower is the only thing on the plate to swing from, so a web that cannot
		# anchor to it is a mechanic with no world to use it on.
		var tower: Node3D = null
		for c in arena.stage.get_children():
			if c.name == "Tower":
				for g in c.get_children():
					if g is StaticBody3D:
						tower = g
		_ok(tower != null, "there is a tower to web")

		if tower != null:
			var sp: SpiderPilot = now
			sp.model.position = Vector3(0, 120, -40)
			sp.model.velocity = Vector3(0, 0, -30)
			sp.model.grounded = false
			# The ROPE on its own. He is aimed straight at the tower here, and now that the
			# buildings actually collide he sticks to it a metre in — which is correct, and
			# is what the wall section below measures. Isolating the pendulum from the
			# collision keeps each test about one thing.
			sp.model.space = null
			sp.model.stuck = false
			var t: WebTether = sp.tether["R"]
			# Anchored high on the near face, which is what a ray from the player would hit.
			_ok(t.fire(sp.model.position, tower, Vector3(0, 150, -78)), "a web reaches it")
			while t.state == WebTether.FLYING:
				t.step(1.0 / 120.0, sp.model.position, sp.model.velocity, 0.0)
			_ok(t.state == WebTether.ATTACHED, "and sticks")

			var start_y: float = sp.model.position.y
			var low := 1e9
			var rose := false
			for i in 480:                      # four seconds on the line
				var rope := t.step(1.0 / 120.0, sp.model.position, sp.model.velocity, 0.0)
				sp.model.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO,
					jump = false, aiming = false }, rope)
				low = minf(low, sp.model.position.y)
				if sp.model.position.y > low + 4.0:
					rose = true
			# THE TEST OF A SWING is that it comes back UP. Anything falls; only something
			# on a rope trades the height for speed and then trades it back.
			_ok(sp.model.position.y > 5.0, "he does not simply hit the ground (y %.0f)" % sp.model.position.y)
			_ok(rose, "and the swing carries him back UP after the low point (low %.0f)" % low)
			_ok(sp.model.position.distance_to(t.anchor_point()) < t.rest_length * 1.3,
				"staying on the end of the line")

			# MOMENTUM. A swing is a pendulum: it trades height for speed on the way down.
			# At a damping of 7.0 the rope was eating that energy as fast as gravity put it
			# in, so every arc came out at the entry speed and the whole thing felt flat —
			# "leci sie z ta sama predkoscia". This measures the trade actually happening.
			# Measured as the pendulum property itself rather than against a number picked
			# in advance: the SAME swing must be faster at the bottom of the arc than at the
			# top. Comparing against a fixed entry speed only measured how long the test had
			# been running before it started looking.
			var high := -1e9
			var deep := 1e9
			var at_high := 0.0
			var at_deep := 0.0
			for i in 360:
				var rope2 := t.step(1.0 / 120.0, sp.model.position, sp.model.velocity, 0.0)
				sp.model.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO,
					jump = false, aiming = false }, rope2)
				if sp.model.position.y > high:
					high = sp.model.position.y
					at_high = sp.model.speed
				if sp.model.position.y < deep:
					deep = sp.model.position.y
					at_deep = sp.model.speed
			_ok(high - deep > 8.0, "it is a real arc, not a hang (%.0f m of swing)" % (high - deep))
			_ok(at_deep > at_high * 1.25,
				"and height turns into SPEED down the arc (%.0f m/s at the bottom, %.0f at the top)"
				% [at_deep, at_high])

	print("=== the wall ===")
	if now is SpiderPilot:
		var sp2: SpiderPilot = now
		sp2.model.space = sp2.get_world_3d().direct_space_state
		_ok(sp2.model.space != null, "he can see the physics world at all")

		# Flown at the near face of the first tower, which stands at z = -95 and is 34 m
		# across, so its face is at z = -78.
		sp2.model.stuck = false
		sp2.model.grounded = false
		sp2.model.position = Vector3(0, 100, -60)
		sp2.model.velocity = Vector3(0, 0, -60)
		for i in 60:
			sp2.model.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO,
				jump = false, aiming = false, release = false, wall_run = false }, Vector3.ZERO)
			if sp2.model.stuck:
				break
		# The buildings had collision bodies that nothing ever queried, so he flew straight
		# through them: "zrob, zeby te budynki mialy kolizje przede wszystkim".
		_ok(sp2.model.stuck, "flying into a tower sticks him to it")
		_ok(absf(sp2.model.wall_normal.y) < 0.4,
			"on a vertical face (normal.y %.2f)" % sp2.model.wall_normal.y)

		if sp2.model.stuck:
			# AND HE DOES NOT FALL. That is the whole request — a wall is a floor.
			var y0: float = sp2.model.position.y
			for i in 180:
				sp2.model.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO,
					jump = false, aiming = false, release = false, wall_run = false }, Vector3.ZERO)
			_ok(absf(sp2.model.position.y - y0) < 0.2,
				"and he holds there instead of sliding down (%.2f m)" % (sp2.model.position.y - y0))

			# The stick climbs the face.
			for i in 240:
				sp2.model.step(1.0 / 120.0, { walk = Vector2(0, -1), look = Vector2.ZERO,
					jump = false, aiming = false, release = false, wall_run = false }, Vector3.ZERO)
			_ok(sp2.model.position.y > y0 + 4.0,
				"pushing up crawls him up the wall (%.1f m)" % (sp2.model.position.y - y0))
			var crawl_to: float = sp2.model.position.y

			# And the trigger makes it a run rather than a crawl.
			for i in 240:
				sp2.model.step(1.0 / 120.0, { walk = Vector2(0, -1), look = Vector2.ZERO,
					jump = false, aiming = false, release = false, wall_run = true }, Vector3.ZERO)
			_ok(sp2.model.position.y - crawl_to > (crawl_to - y0) * 1.5,
				"and holding the trigger RUNS it (%.1f m against %.1f)" % [
					sp2.model.position.y - crawl_to, crawl_to - y0])

			# X pushes him off, backwards and up.
			sp2.model.step(1.0 / 120.0, { walk = Vector2.ZERO, look = Vector2.ZERO,
				jump = false, aiming = false, release = true, wall_run = false }, Vector3.ZERO)
			_ok(not sp2.model.stuck, "X lets go of the wall")
			_ok(sp2.model.velocity.y > 2.0 and sp2.model.velocity.length() > 6.0,
				"with a push out and up (%.0f m/s)" % sp2.model.velocity.length())

	print("=== and back again, also through the menu ===")
	var m2: SuitMenu = now.visor.menu
	m2.open()
	m2.tab = 0
	m2.row = 0                        # IRON MAN
	m2._accept()
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	_ok(arena.suits.get(1) is SuitPilot, "switching back returns the armour")

	print("=== and the armour bay actually dresses him ===")
	var back = arena.suits.get(1)
	if back is SuitPilot:
		var m3: SuitMenu = back.visor.menu
		m3.open()
		m3.tab = 1                    # ARMOUR BAY
		m3.row = 0                    # MARK I, the one that is free
		m3.owned["mk3"] = true
		m3.row = 2                    # MARK III
		m3._accept()
		await get_tree().process_frame
		_ok(back.armor_id == "mk3", "picking an armour changes it (%s)" % back.armor_id)
		_ok(Net.local_armor == "mk3", "and the roster agrees (%s)" % Net.local_armor)

	print("=== switching over and over ===")
	# "Dalej tylko bardzo rzadko dziala stroj Iron Spider." Intermittent is the hardest kind
	# of report to act on, so this just does it eight times and checks every single one —
	# a race in the teardown would show up as one bad round in the middle rather than as a
	# clean pass or a clean fail.
	var misses := 0
	for i in 8:
		var want := "spiderman" if i % 2 == 0 else "ironman"
		Net.announce_hero(want)
		await get_tree().process_frame
		await get_tree().create_timer(0.2).timeout
		var who = arena.suits.get(1)
		var ok_now := who != null and ((want == "spiderman" and who is SpiderPilot)
			or (want == "ironman" and who is SuitPilot))
		if not ok_now:
			misses += 1
		elif who is SpiderPilot and (who.rig == null or who.skel == null):
			misses += 1        # spawned, but with no body — which looks the same from the pad
	_ok(misses == 0, "eight switches in a row, all of them took (%d missed)" % misses)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	get_tree().quit(1 if bad > 0 else 0)
