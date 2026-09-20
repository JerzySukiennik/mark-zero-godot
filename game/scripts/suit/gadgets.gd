class_name Gadgets
extends Node3D
## What makes one armour different from another, beyond being faster.
##
## Jurek: "chcę, żeby każdy ze strojów miał różne, jakby trochę takie swoje opcje... ten
## najlepszy strój powinien mieć jakieś takie dodatki, które się pojawiają, taką animacją
## na technologii." So every suit carries TWO, on the sticks: L3 is the defensive one and
## R3 the offensive one, which means the pair is always in the same place and only what
## they DO changes with the armour.
##
## The sticks were chosen because they are the only buttons left, and because pressing one
## is a deliberate act rather than something you do by accident while flying.

## id -> { left, right }. Each entry is a key into EFFECTS below.
const LOADOUT := {
	# The cave build has no finesse and never did. What it has is plate and scrap.
	"mk1":  { left = "bulwark",    right = "scrap" },
	# The prototype's whole story is that it ices up. Its defensive slot is the fix.
	"mk2":  { left = "stabilise",  right = "pulse" },
	# The first real suit: countermeasures and a missile rack.
	"mk3":  { left = "chaff",      right = "salvo" },
	# The prehensile one comes apart on purpose, so both of its tricks are that.
	"mk42": { left = "phase",      right = "shatter" },
	# Nanotech. The shield and the blade Jurek asked for by name.
	"mk50": { left = "shield",     right = "blade" },
}

## Everything about a gadget that is not code: what it is called, how long it lasts, how
## long before you may use it again, and the numbers its effect reads.
const EFFECTS := {
	"bulwark":   { name = "BULWARK",      hold = 5.0,  cool = 9.0,  guard = 0.82 },
	"scrap":     { name = "SCRAP BURST",  hold = 0.25, cool = 7.0,  radius = 9.0, damage = 34.0 },
	"stabilise": { name = "STABILISERS",  hold = 7.0,  cool = 11.0, agility = 1.8 },
	"pulse":     { name = "SONIC PULSE",  hold = 0.3,  cool = 6.5,  radius = 13.0, damage = 12.0, push = 16.0 },
	"chaff":     { name = "CHAFF",        hold = 3.5,  cool = 10.0, breaks_lock = true },
	"salvo":     { name = "MICRO-SALVO",  hold = 0.9,  cool = 9.0,  rounds = 6, damage = 26.0 },
	"phase":     { name = "PHASE",        hold = 1.6,  cool = 12.0, guard = 1.0 },
	"shatter":   { name = "SHATTER",      hold = 0.35, cool = 8.0,  radius = 11.0, damage = 46.0, push = 9.0 },
	"shield":    { name = "NANO SHIELD",  hold = 6.0,  cool = 8.0,  guard = 0.88 },
	"blade":     { name = "NANO BLADE",   hold = 0.55, cool = 4.0,  reach = 6.5, damage = 200.0 },
}

## How long the "it is forming" animation runs. Short — the point is that you SEE nanotech
## assemble, not that you wait for it.
const FORM_TIME := 0.22

signal used(key: String, label: String)

var armor := "mk1"
var skel: SuitRig
var model: FlightModel

## Which slot is live, "" when neither, and how long is left on it.
var active := ""
var left_t := 0.0
var _cool := { "left": 0.0, "right": 0.0 }

var _shield: MeshInstance3D
var _blade: MeshInstance3D
var _form := 0.0

func bind(rig: SuitRig, m: FlightModel, id: String) -> void:
	skel = rig
	model = m
	armor = id
	_mount()

## What this armour has in each hand, as a label for the HUD and the menu.
func label(slot: String) -> String:
	var row: Dictionary = LOADOUT.get(armor, LOADOUT["mk1"])
	var key: String = row.get(slot, "")
	return EFFECTS.get(key, {}).get("name", "—")

func ready_in(slot: String) -> float:
	return _cool.get(slot, 0.0)

## How much incoming damage survives whatever is up. 1.0 means no protection.
func damage_through(from: Vector3, at: Vector3) -> float:
	if active == "":
		return 1.0
	var e: Dictionary = _effect(active)
	var guard: float = e.get("guard", 0.0)
	if guard <= 0.0:
		return 1.0
	# A SHIELD ONLY WORKS ONE WAY. Phase is the exception — you cannot be shot from behind
	# a thing you are not solidly in — and that is what makes it worth a longer cooldown.
	if active == "phase" or armor == "mk42":
		return 1.0 - guard
	var facing := -model.basis_.z if model != null else Vector3.FORWARD
	var incoming := (at - from)
	incoming.y = 0.0
	if incoming.length_squared() < 1e-5:
		return 1.0 - guard
	# Behind you it does nothing, which is the whole reason a shield is a decision.
	return 1.0 - guard if facing.dot(-incoming.normalized()) > 0.25 else 1.0

## Extra handling while the stabilisers are up.
func agility() -> float:
	if active == "" :
		return 1.0
	return float(_effect(active).get("agility", 1.0))

func press(slot: String) -> void:
	if _cool.get(slot, 0.0) > 0.0 or active != "":
		return
	var row: Dictionary = LOADOUT.get(armor, LOADOUT["mk1"])
	var key: String = row.get(slot, "")
	if key == "":
		return
	var e: Dictionary = EFFECTS[key]
	active = key
	left_t = float(e["hold"])
	_cool[slot] = float(e["cool"])
	_form = FORM_TIME
	used.emit(key, String(e["name"]))
	_fire(key, e)

func _effect(key: String) -> Dictionary:
	return EFFECTS.get(key, {})

## The one-shot half of a gadget. Everything with a `hold` longer than a moment does its
## work in `damage_through` or `agility` instead.
func _fire(key: String, e: Dictionary) -> void:
	match key:
		"scrap", "pulse", "shatter":
			_burst(e)
		"salvo":
			_salvo(e)
		"blade":
			_blade_strike(e)
		"chaff":
			_break_locks()
		_:
			pass

## Everything around him, damaged and shoved. Three gadgets share it because three
## gadgets ARE it with different numbers — a crude shrapnel burst, a sonic shove and a
## suit throwing its own plates outward all mean "hurt what is close".
func _burst(e: Dictionary) -> void:
	var here := global_position
	var r: float = e.get("radius", 8.0)
	var dmg: float = e.get("damage", 20.0)
	var push: float = e.get("push", 0.0)
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Enemy) or not is_instance_valid(n):
			continue
		var enemy: Enemy = n
		var d := here.distance_to(enemy.global_position)
		if d > r:
			continue
		# Falls off with distance, so standing in the middle of a crowd is the point.
		var f: float = 1.0 - d / r
		enemy.take_hit(dmg * f, here, "gadget")
		if push > 0.0 and is_instance_valid(enemy):
			var away := enemy.global_position - here
			away.y = 0.0
			if away.length_squared() > 1e-4:
				enemy.velocity += away.normalized() * push * f + Vector3.UP * push * 0.25 * f
	Sfx.play("explosion", here, -4.0, 1.25)

## Micro-missiles, one per nearby man, fired through the enemies' own projectile pool
## because a rocket is a rocket whoever launched it.
func _salvo(e: Dictionary) -> void:
	# Borrowed from whoever owns the projectile pool, because one pool of rockets in the
	# air is simpler than two, and `friendly` is the whole difference.
	var guns: Gunfire = null
	for n in get_tree().get_nodes_in_group("gunfire"):
		if n is Gunfire:
			guns = n
			break
	if guns == null:
		return
	var here := global_position + Vector3(0, 0.8, 0)
	var marks: Array = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is Enemy and is_instance_valid(n) and (n as Enemy).state != Enemy.DOWN:
			marks.append(n)
	marks.sort_custom(func(a, b): return here.distance_to(a.global_position) < here.distance_to(b.global_position))
	var rounds: int = int(e.get("rounds", 4))
	for i in mini(rounds, marks.size()):
		var mark: Node3D = marks[i]
		var dir := (mark.global_position + Vector3(0, 0.8, 0)) - here
		if dir.length_squared() < 1e-4:
			continue
		guns.fire(here, dir.normalized(), 70.0, float(e.get("damage", 20.0)), 4.0, mark, true)
	Sfx.play("rpg_launch", here, -3.0, 1.2)

## The blade. A short, decisive reach in front — it kills an ordinary man outright, which
## is what a sword made of nanomachines ought to do, and the cooldown is what stops it
## being the only button.
func _blade_strike(e: Dictionary) -> void:
	var here := global_position + Vector3(0, 0.8, 0)
	var facing := -model.basis_.z if model != null else Vector3.FORWARD
	var reach: float = e.get("reach", 5.0)
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Enemy) or not is_instance_valid(n):
			continue
		var enemy: Enemy = n
		var to := enemy.global_position + Vector3(0, 0.8, 0) - here
		var d := to.length()
		if d > reach or facing.dot(to / maxf(d, 0.001)) < 0.55:
			continue
		enemy.take_hit(float(e.get("damage", 100.0)), here, "blade")
	Sfx.play("punch_big", here, -1.0, 1.3)

## Chaff. Anything chasing you loses you.
func _break_locks() -> void:
	for n in get_tree().get_nodes_in_group("gunfire"):
		if n is Gunfire:
			(n as Gunfire).break_locks()
	Sfx.play("boost", global_position, -4.0, 1.5)

# ---- the hardware itself -----------------------------------------------------------

## Builds the shield and the blade onto the rig. Both are hidden until used and both grow
## into place, because "appears with a tech animation" is the entire brief for them.
func _mount() -> void:
	for n in [_shield, _blade]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_shield = null
	_blade = null
	if skel == null:
		return
	var arm := "piv_palm" + SuitRig.SIDE["L"]
	var arm_r := "piv_palm" + SuitRig.SIDE["R"]
	if skel.has_pivot(arm):
		_shield = _make_shield()
		(skel.pivots[arm] as Node3D).add_child(_shield)
	if skel.has_pivot(arm_r):
		_blade = _make_blade()
		(skel.pivots[arm_r] as Node3D).add_child(_blade)

static func _make_shield() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.62
	cm.height = 0.05
	cm.radial_segments = 6            # hexagonal, which reads as "built" rather than "round"
	mi.mesh = cm
	mi.rotation_degrees = Vector3(90, 0, 0)
	mi.position = Vector3(0, -0.34, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.55, 0.85, 1.6, 0.42)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

static func _make_blade() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.10, 1.35, 0.028)
	mi.mesh = pm
	mi.position = Vector3(0, -0.85, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.90, 0.98)
	m.metallic = 1.0
	m.roughness = 0.12
	m.emission_enabled = true
	m.emission = Color(0.8, 0.9, 1.0)
	m.emission_energy_multiplier = 0.5
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi

func _physics_process(delta: float) -> void:
	for slot in _cool:
		_cool[slot] = maxf(0.0, _cool[slot] - delta)
	if active != "":
		left_t -= delta
		if left_t <= 0.0:
			active = ""
	if _form > 0.0:
		_form -= delta

	# GROWING INTO PLACE. The scale ramp over FORM_TIME is the "tech animation" — a piece
	# of hardware that simply appears at full size reads as a model being switched on.
	var grow: float = 1.0 if _form <= 0.0 else 1.0 - (_form / FORM_TIME)
	if _shield != null and is_instance_valid(_shield):
		var on := active == "shield"
		_shield.visible = on
		if on:
			_shield.scale = Vector3(grow, 1.0, grow)
			var m: StandardMaterial3D = _shield.material_override
			# It flickers where it is thinnest, which is what says "held together by
			# machines" rather than "a pane of glass".
			m.albedo_color = Color(0.55, 0.85, 1.6, 0.30 + 0.18 * sin(Time.get_ticks_msec() * 0.011))
	if _blade != null and is_instance_valid(_blade):
		var on_b := active == "blade"
		_blade.visible = on_b
		if on_b:
			_blade.scale = Vector3(1.0, grow, 1.0)
