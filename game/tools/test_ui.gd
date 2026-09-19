extends SceneTree
## Does the visor actually SIZE the panels it contains?
##
## This is the regression that cost three separate bug reports at once — the integrity bar
## cropped into the corner, the menu opening as a tiny window, and the repulsor counts
## missing entirely. All three were one fact: a Control parented to a SubViewport is left at
## size ZERO however its anchors are set, and a zero-sized Control still draws.
##
## It hid for so long because the screenshot tool builds its own Hud and sizes it, so every
## preview was correct while the game was wrong. So this test goes through Visor, the real
## path, and asserts on pixels the panels would actually occupy.

var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	var v := Visor.new()
	root.add_child(v)
	await process_frame

	var want := root.get_visible_rect().size
	_ok(v.hud.size.x > 1.0 and v.hud.size.y > 1.0,
		"the HUD has a size at all (%s)" % v.hud.size)
	_ok(v.hud.size == want, "and it fills the viewport (%s)" % v.hud.size)
	_ok(v.menu.size == want, "so does the menu (%s)" % v.menu.size)
	_ok(Vector2(v._vp.size) == want, "and the SubViewport matches the window")

	# The panel that goes missing FIRST when the size is wrong is the one laid out from the
	# far edge, because a small width sends it to a negative x. Recomputing its left edge
	# here is what actually catches the bug rather than trusting the size.
	var u: float = maxf(0.55, v.hud.size.y / 1080.0)
	var inset: float = v.hud.size.x * Hud.VISOR_CUT
	var repulsor_x: float = (v.hud.size.x - inset * 2.0) - 340.0 * u + inset
	_ok(repulsor_x > 0.0 and repulsor_x < v.hud.size.x,
		"the repulsor panel is on screen (left edge x=%.0f of %.0f)" % [repulsor_x, v.hud.size.x])
	_ok(repulsor_x > v.hud.size.x * 0.5, "and on the RIGHT half, where it belongs")

	# The integrity panel must clear the band the curved glass eats.
	_ok(inset >= v.hud.size.x * 0.02,
		"the safe inset is wide enough for the visor warp (%.0f px)" % inset)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
	return true
