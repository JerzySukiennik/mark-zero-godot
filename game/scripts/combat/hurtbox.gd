class_name Hurtbox
extends Area3D
## Something for incoming fire to actually hit.
##
## Both heroes are plain Node3Ds — they run hand-written physics rather than a
## CharacterBody, because their motion is tuned to measured numbers that move_and_slide
## would not reproduce. The cost of that is they have no collider, so every ray in the game
## passes straight through them. The enemies' rifles found this immediately: a test with a
## target that had no shape recorded zero hits from a man standing thirty metres away
## emptying a magazine into it.
##
## An AREA rather than a body, deliberately. A solid body on the player would be something
## the thugs bump into and shove around, something the wall-crawl sweep would stick to, and
## something his own webs would anchor on. An area is hit by anything that asks for areas
## and ignored by everything that does not — and the only thing that asks is incoming fire.
## Who to tell when something lands.
var host: Node = null

func _init(owner_node: Node = null, radius := 0.55, height := 2.0) -> void:
	host = owner_node
	monitoring = false
	monitorable = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position.y = height * 0.5 - 1.0     # the model's origin is at the soles
	add_child(cs)

## The same contract as everything else that can be hurt. Forwarded rather than handled,
## because the health, the rumble and the knockback all belong to the pilot.
func take_hit(amount: float, from: Vector3, kind := "") -> void:
	if host != null and is_instance_valid(host) and host.has_method("take_hit"):
		host.take_hit(amount, from, kind)
