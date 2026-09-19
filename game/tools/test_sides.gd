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

	print("=== banking ===")
	# Sliding sideways with the body level is what made lateral flight read as levitation.
	# The direction of the lean is measured, not reasoned about: the suit's own UP vector
	# must tip towards the side it is travelling to.
	var b := FlightModel.new()
	b.set_armor("mk3")
	b.position = Vector3(0, 200, 0)
	for i in 600:
		b.step(1.0 / 120.0, { thrust = 0.6, retro = 0.0, lateral = 1.0, vertical = 0.0,
			walk = Vector2.ZERO, look = Vector2.ZERO, roll = 0.0, boost = false,
			aiming = false, firing = false })
	var up := b.view_basis * Vector3.UP
	var side := b.basis_.inverse() * b.velocity
	_ok(side.x > 3.0, "stick RIGHT actually moves it right (%.1f m/s)" % side.x)
	_ok(up.x > 0.15, "and the suit LEANS that way (up.x %.2f)" % up.x)
	_ok(absf(b.bank) > 0.2, "a real bank angle, not a token one (%.1f deg)" % rad_to_deg(b.bank))

	print("=== standing in the air ===")
	# The hover pose was a crouch. "Powinien stac z rekami i nogami prosto w dol."
	var h := FlightModel.new()
	h.set_armor("mk3")
	h.position = Vector3(0, 200, 0)
	var ps := Poses.new()
	# A FRESH model. Indexing a second rig onto the node the first one has already posed
	# captures that pose as the new rig's REST, and every angle measured afterwards is off
	# by whatever the first rig happened to be doing.
	var node2: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk1.glb")
	root.add_child(node2)
	var hs := SuitRig.new(); hs.index(node2)
	for i in 600:
		var c := { thrust = 0.0, retro = 0.0, lateral = 0.0, vertical = 0.0,
			walk = Vector2.ZERO, look = Vector2.ZERO, roll = 0.0, boost = false,
			aiming = false, firing = false }
		h.step(1.0 / 120.0, c)
		ps.update(1.0 / 120.0, h, c, hs)
		hs.update_pose(1.0 / 120.0)
	_ok(ps.current == "hover", "it is hovering (%s)" % ps.current)

	# Measured as the angle at the joint, which is what "bent" actually means.
	var hip := (hs.pivots["piv_hipL"] as Node3D).global_position
	var knee := (hs.pivots["piv_kneeL"] as Node3D).global_position
	var ankle := (hs.pivots["piv_ankleL"] as Node3D).global_position
	var leg_bend := rad_to_deg((knee - hip).angle_to(ankle - knee))
	_ok(leg_bend < 18.0, "the legs hang straight (%.0f deg at the knee)" % leg_bend)

	var sh := (hs.pivots["piv_shoulderL"] as Node3D).global_position
	var el := (hs.pivots["piv_elbowL"] as Node3D).global_position
	var pa := (hs.pivots["piv_palmL"] as Node3D).global_position
	var arm_bend := rad_to_deg((el - sh).angle_to(pa - el))
	_ok(arm_bend < 22.0, "and the arms hang straight (%.0f deg at the elbow)" % arm_bend)
	_ok(pa.y < sh.y - 0.35, "with the hands well below the shoulders")
	_ok(h.thrust_mag >= FlightModel.HOVER_BURN, "and the repulsors are burning (%.2f)" % h.thrust_mag)

	# AND THEY POINT DOWN. The boot jets leave along the ankle pivot's local -Y, so the
	# foot's angle IS the exhaust angle: toes back at 0.60 aimed them thirty-seven degrees
	# behind vertical, and a hovering suit was firing backwards while holding station.
	var tl: Node3D = hs.pivots["piv_thrusterL"]
	var jet: Vector3 = (tl.global_transform.basis * Vector3(0, -1, 0)).normalized()
	_ok(rad_to_deg(jet.angle_to(Vector3.DOWN)) < 15.0,
		"the boot jets fire straight down in a hover (%.0f deg off)" % rad_to_deg(jet.angle_to(Vector3.DOWN)))

	print("=== the arms through a slide ===")
	# A full sideways slide must produce a real ASYMMETRY — one arm reaching away from the
	# turn, the other tucked across it — and neither hand may cross the body's centre line.
	#
	# It failed both ways at once, and the cause is worth guarding: the two shoulder pivots
	# have MIRRORED local frames, so giving them opposite signs rotates them the same way in
	# body space. That is symmetric. A full slide threw both hands across the chest in one
	# direction and flung both of them wide in the other.
	for dir: float in [1.0, -1.0]:
		var fresh: Node3D = SuitLoaderS.load_suit("res://assets/suits/mk1.glb")
		root.add_child(fresh)
		var rg := SuitRig.new(); rg.index(fresh)
		var pz := Poses.new()
		var fm := FlightModel.new(); fm.set_armor("mk1")
		fm.position = Vector3(0, 300, 0)
		for i in 900:
			var c := { thrust = 0.7, retro = 0.0, lateral = dir, vertical = 0.0,
				walk = Vector2.ZERO, look = Vector2.ZERO, roll = 0.0, boost = false,
				aiming = false, firing = false }
			fm.step(1.0 / 120.0, c)
			pz.update(1.0 / 120.0, fm, c, rg)
			rg.update_pose(1.0 / 120.0)

		var hips: Vector3 = (rg.pivots["piv_hips"] as Node3D).global_position
		var pL: float = (rg.pivots["piv_palmL"] as Node3D).global_position.x - hips.x
		var pR: float = (rg.pivots["piv_palmR"] as Node3D).global_position.x - hips.x
		var sL: float = (rg.pivots["piv_shoulderL"] as Node3D).global_position.x - hips.x
		var sR: float = (rg.pivots["piv_shoulderR"] as Node3D).global_position.x - hips.x
		var tag := "right" if dir > 0.0 else "left"

		_ok(pL > 0.0 and pR < 0.0,
			"sliding %s, neither hand crosses the body (L %+.3f, R %+.3f)" % [tag, pL, pR])
		# Each hand keeps a clear margin on its own side rather than sitting on the midline.
		_ok(absf(pL) > absf(sL) * 0.2 and absf(pR) > absf(sR) * 0.2,
			"and both keep clear of the midline sliding %s" % tag)
		# And the two arms must be doing DIFFERENT things, or it is not a turn.
		_ok(absf(absf(pL) - absf(pR)) > 0.18,
			"the arms are asymmetric sliding %s (%.2f apart)" % [tag, absf(absf(pL) - absf(pR))])
		fresh.queue_free()

	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad > 0 else 0)
	return true
