class_name ArmourDamage
extends Node3D
## The suit coming apart.
##
## Jurek: as integrity falls, pieces should tear off and drop to the ground, and when it
## reaches zero there should be nothing left but Tony Stark, who cannot fly. And losing a
## piece has to COST something — "jak odpada kawałek ręki, to już nie może strzelać prawą
## ręką".
##
## That last rule is what makes this a mechanic rather than a particle effect. A suit that
## sheds decoration is a health bar with extra steps; a suit that loses the arm you were
## shooting with changes what you can do, and the player feels the damage without reading
## a number.
##
## Pieces are detached rather than hidden: they are re-parented into the world keeping
## their world transform, given a tumble, and left to fall. Nothing is pooled because this
## happens a handful of times in a fight and each piece is one mesh.

## How long a fallen piece lies on the plate before it goes.
const DEBRIS_LIFE := 25.0
const GRAVITY := 18.0

## Which meshes belong to which part of the body. Suffixes are the MODEL's, which name the
## sides from the opposite convention to the game — see SuitRig.SIDE — so `armL` here is
## the arm the player sees on the right.
const REGIONS := {
	"armL": ["pauldronL", "bicepL", "elbowL", "forearmL", "gauntletL", "collarL"],
	"armR": ["pauldronR", "bicepR", "elbowR", "forearmR", "gauntletR", "collarR"],
	"legL": ["thighL", "kneeL", "shinL", "bootL", "beltL"],
	"legR": ["thighR", "kneeR", "shinR", "bootR", "beltR"],
	"torso": ["ribL", "ribR", "back", "abdomen", "pelvis"],
	"head": ["earL", "earR"],
}
## Integrity below which a region is considered stripped — the ARM is gone once its
## gauntlet and forearm are off, not once a shoulder pad has fallen.
const ARM_CORE := ["forearmL", "gauntletL", "forearmR", "gauntletR"]

var rig: Node3D
var skel: SuitRig
var ground_y := 0.0

## Model-suffix -> true once that arm can no longer hold a repulsor.
var lost := {}
var shed_count := 0

var _pieces: Array = []          ## name -> still attached
var _debris: Array = []
var _order: Array = []           ## the sequence pieces come off in, shuffled once
var _next := 0

func bind(r: Node3D, s: SuitRig) -> void:
	rig = r
	skel = s
	_pieces.clear()
	_order.clear()
	_next = 0
	lost.clear()
	shed_count = 0
	if rig == null:
		return
	# The order is fixed at bind time rather than rolled per hit, so a suit does not lose
	# the same pad twice or strip one whole side by chance.
	var pool: Array = []
	for region in REGIONS:
		for nm in REGIONS[region]:
			pool.append({ region = region, mesh = nm })
	pool.shuffle()
	_order = pool

## Called whenever integrity changes. `health` is 0..1. Sheds whatever the new figure has
## earned — plural, because a rocket can take a quarter of the bar in one go.
func sync(health: float) -> void:
	# Full armour at full health, nothing left at zero, linear in between. Deliberately
	# simple: the interesting part is WHICH piece goes, not the curve.
	var want := int(round((1.0 - clampf(health, 0.0, 1.0)) * _order.size()))
	while _next < want and _next < _order.size():
		_detach(_order[_next])
		_next += 1

func _detach(entry: Dictionary) -> void:
	if rig == null:
		return
	var node := _find(rig, entry["mesh"])
	if node == null:
		return
	shed_count += 1
	var world := node.global_transform
	var parent := get_parent()
	node.get_parent().remove_child(node)
	if parent == null:
		node.queue_free()
		return
	parent.add_child(node)
	node.global_transform = world
	# Thrown outwards and spun. The direction is away from the suit's own centre, so a
	# shoulder pad leaves over the shoulder rather than through the chest.
	var out := (world.origin - rig.global_position)
	out.y = 0.0
	if out.length_squared() < 1e-4:
		out = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_debris.append({
		node = node,
		vel = out.normalized() * randf_range(2.5, 6.0) + Vector3.UP * randf_range(1.5, 4.0),
		spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)),
		life = DEBRIS_LIFE,
	})
	# Once the forearm or the gauntlet is gone, that hand has nothing to fire with.
	if entry["mesh"] in ARM_CORE:
		lost[entry["region"]] = true

## Can that hand still shoot? `hand` is the BUTTON side, R or L, and the model names its
## sides the other way round.
func can_use(hand: String) -> bool:
	return not lost.get("arm" + SuitRig.SIDE[hand], false)

func _find(n: Node, want: String) -> Node3D:
	if n is MeshInstance3D and String(n.name) == want:
		return n
	for c in n.get_children():
		var hit := _find(c, want)
		if hit != null:
			return hit
	return null

func _physics_process(delta: float) -> void:
	var keep: Array = []
	for d in _debris:
		var node: Node3D = d["node"]
		if not is_instance_valid(node):
			continue
		d["life"] -= delta
		if d["life"] <= 0.0:
			node.queue_free()
			continue
		var v: Vector3 = d["vel"]
		var p := node.global_position
		if p.y > ground_y + 0.08:
			v.y -= GRAVITY * delta
			node.global_position = p + v * delta
			node.rotate_x(d["spin"].x * delta)
			node.rotate_y(d["spin"].y * delta)
			node.rotate_z(d["spin"].z * delta)
		else:
			# Landed. It stops dead rather than bouncing: a piece of armour is not a ball,
			# and a plate skittering across the plate for ten seconds draws the eye to the
			# wrong thing entirely.
			node.global_position = Vector3(p.x, ground_y + 0.06, p.z)
			v = Vector3.ZERO
			d["spin"] = Vector3.ZERO
		d["vel"] = v
		keep.append(d)
	_debris = keep
