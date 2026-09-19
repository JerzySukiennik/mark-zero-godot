extends SceneTree
## WHICH SIDE OF THE SCREEN IS EACH HAND ON?
##
## This has now been got wrong twice by reasoning about it instead of measuring it. The
## asset contract says "+X is the character's LEFT", the model obeys that to the millimetre,
## and the game still fires out of the wrong hand — so the contract's own sentence is what
## needs checking, not the model.
##
## The only question that matters is what the PLAYER sees, so this puts the real ChaseCamera
## behind the suit exactly the way SuitPilot does and unprojects each palm to screen pixels.
## Nothing here is an opinion about axes.

const SuitLoaderS := preload("res://scripts/suit/suit_loader.gd")
var bad := 0

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _initialize() -> void:
	pass

func _process(_d: float) -> bool:
	var node: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk1.glb")
	root.add_child(node)
	var skel := SuitRig.new(); skel.index(node)
	skel.set_pose("stand")
	skel.update_pose(1.0)

	var cam := ChaseCamera.new()
	root.add_child(cam)
	cam.snap(Vector3.ZERO, Basis.IDENTITY)
	cam.current = true
	await process_frame

	var mid := root.get_visible_rect().size.x * 0.5
	var pl := cam.unproject_position((skel.pivots["piv_palmL"] as Node3D).global_position)
	var pr := cam.unproject_position((skel.pivots["piv_palmR"] as Node3D).global_position)
	print("  screen midline %.0f    piv_palmL x=%.0f    piv_palmR x=%.0f" % [mid, pl.x, pr.x])

	# The suit is seen from BEHIND, so the hand the player reads as "the right hand" is the
	# one on the right of the screen. Whatever it is NAMED is beside the point.
	var right_named: String = "piv_palmR" if pr.x > pl.x else "piv_palmL"
	print("  the pivot on the player's RIGHT is: ", right_named)
	_ok(right_named == SuitRig.SCREEN_RIGHT_PALM,
		"SuitRig.SCREEN_RIGHT_PALM names the hand on the right of the screen")

	# And the same for the shoulders, which the turret is bolted to.
	var sl := cam.unproject_position((skel.pivots["piv_shoulderL"] as Node3D).global_position)
	var sr := cam.unproject_position((skel.pivots["piv_shoulderR"] as Node3D).global_position)
	_ok((sr.x > sl.x) == (pr.x > pl.x), "the shoulders agree with the palms")

	# Walking forward must move the suit AWAY from a camera parked behind it.
	var m := FlightModel.new()
	m.set_armor("mk1")
	m.position = Vector3(0, 1.0, 0)
	var eye := Vector3(0, 0, 12.0)              # behind the suit, which faces -Z
	var d0 := m.position.distance_to(eye)
	for i in 240:
		m.step(1.0 / 120.0, { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0,
			walk = Vector2(0, -1), look = Vector2.ZERO, roll = 0.0, boost = false,
			aiming = false, firing = false })
	_ok(m.position.distance_to(eye) > d0 + 2.0,
		"stick FORWARD walks away from the camera (%.1f m -> %.1f m)" % [d0, m.position.distance_to(eye)])
	_ok(m.position.z < -2.0, "and forward is -Z (z %.1f)" % m.position.z)

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
	return true
