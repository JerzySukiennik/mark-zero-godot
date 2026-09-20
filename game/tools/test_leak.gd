extends Node
## Does a pilot take its world-parented furniture with it when it goes?
##
## Run as a SCENE, never with --script: SuitPilot reaches for the Net autoload, and
## autoloads do not exist under `godot --script`.
##   godot --headless --path . res://tools/test_leak.tscn
##
## THE BUG THIS EXISTS FOR. The lock bracket, the chase camera and the web strands are
## deliberately parented to the WORLD rather than to the character, so they do not bank
## and tumble with a body that is doing barrel rolls. The cost of that is that nothing
## frees them when the body is replaced — and a leaked ThreatMarks keeps whatever state
## it was last given, so a red "a rocket is tracking you" bracket hangs frozen in mid-air
## for the rest of the session. Jurek: "czasem się bugguje ta ramka od RPG."
##
## It is a whole CLASS of bug, not one node, so this counts every kind rather than the
## one that was reported.

var bad := 0
var _i := 0
var _world: Node3D

func _ok(c: bool, m: String) -> void:
	if not c: bad += 1
	print(("  ok    " if c else "  FAIL  ") + m)

func _count(t: String) -> int:
	var n := 0
	for c in _world.get_children():
		if c.get_class() == "Node3D" or true:
			if c.get_script() != null and String(c.get_script().resource_path).ends_with(t):
				n += 1
	return n

func _ready() -> void:
	_world = Node3D.new()
	add_child(_world)

func _process(_d: float) -> void:
	_i += 1
	# A frame is needed between each step: the marks are attached with call_deferred, and
	# queue_free lands at the end of a frame rather than inside the call.
	match _i:
		2:
			var p := SuitPilot.new()
			p.setup(1, "mk3", null)
			_world.add_child(p)
			p.name = "Pilot"
		4:
			_ok(_count("threat_marks.gd") == 1, "a pilot puts one bracket in the world")
			_world.get_node("Pilot").queue_free()
		8:
			print("=== nothing of the pilot is left behind ===")
			_ok(_count("threat_marks.gd") == 0,
				"the lock bracket goes with it (%d left)" % _count("threat_marks.gd"))
			_ok(_count("chase_camera.gd") == 0,
				"so does the camera (%d left)" % _count("chase_camera.gd"))
			_ok(_count("contrail.gd") == 0,
				"and the contrail (%d left)" % _count("contrail.gd"))
			print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
			get_tree().quit(1 if bad > 0 else 0)
