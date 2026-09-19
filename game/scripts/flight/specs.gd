extends RefCounted
class_name SuitSpecs
## The five armours, and what each one can do.
##
## Ported verbatim from the browser build's ARMOR_SPECS. These numbers are not guesses —
## they were found by flying and measuring over many sessions, so they come across as they
## are rather than being re-tuned from scratch. Two things to know before touching them:
##
##   `top_speed` is a TARGET, not a clamp. Forward drag is derived from it as
##   k = main / top_speed^2, so the suit reaches exactly that speed when thrust and drag
##   balance, and getting there takes real time.
##
##   `drag_ratio` says how much worse the other two axes are than forward. `back` is drag
##   flying TAIL-FIRST: the table used to be symmetric on Z, so a suit going backwards was
##   as slippery as one going nose-first and nothing ever bled a reversed flight off.
##
## `self_don` marks an armour that puts itself on with no machine to help it.
##
## STATIC, not an autoload. FlightModel used to reach for a global `Specs` singleton, which
## looked tidy and was a hidden dependency: the model could not be built or tested without a
## running SceneTree, and a headless test run — where autoloads do not exist — could not
## touch it at all. A table of numbers has no business being a node.

class Spec:
	var id: String
	var name: String
	var mass: float
	var main: float          ## newtons, forward
	var lateral: float
	var vertical: float
	var top_speed: float     ## m/s, the speed where thrust and drag balance
	var drag_lateral: float
	var drag_vertical: float
	var drag_back: float
	var max_rate: float      ## rad/s of pitch/yaw
	var roll_rate: float
	var alpha_max: float     ## rad/s^2, how fast it can change its turn rate
	var roll_alpha_max: float
	var rate_falloff_ref: float
	var stability: float
	var integrity: float
	var power: float         ## reactor output, also scales walking speed on the ground
	var boost: float
	var flaw: String
	var self_don: bool

	func _init(d: Dictionary) -> void:
		id = d.id
		name = d.name
		mass = d.mass
		main = d.main
		lateral = d.lateral
		vertical = d.vertical
		top_speed = d.top_speed
		drag_lateral = d.drag.x
		drag_vertical = d.drag.y
		drag_back = d.drag.z
		max_rate = d.max_rate
		roll_rate = d.roll_rate
		alpha_max = d.alpha_max
		roll_alpha_max = d.roll_alpha_max
		rate_falloff_ref = d.rate_falloff_ref
		stability = d.stability
		integrity = d.integrity
		power = d.power
		boost = d.boost
		flaw = d.get("flaw", "")
		self_don = d.get("self_don", false)

static var _all: Dictionary = {}
static var order: PackedStringArray = ["mk1", "mk2", "mk3", "mk42", "mk50"]

static func _build() -> void:
	if not _all.is_empty():
		return
	_add({ id = "mk1", name = "MARK I", mass = 340.0,
		main = 9800.0, lateral = 4410.0, vertical = 7350.0,
		top_speed = 150.0, drag = Vector3(3.2, 4.2, 6.5),
		max_rate = 1.9, roll_rate = 2.4, alpha_max = 8.0, roll_alpha_max = 12.0,
		rate_falloff_ref = 90.0, stability = 0.55, integrity = 900.0, power = 0.8,
		boost = 1.15 })
	_add({ id = "mk2", name = "MARK II", mass = 215.0,
		main = 12600.0, lateral = 5670.0, vertical = 9450.0,
		top_speed = 300.0, drag = Vector3(4.0, 5.6, 8.0),
		max_rate = 3.0, roll_rate = 4.2, alpha_max = 14.0, roll_alpha_max = 24.0,
		rate_falloff_ref = 200.0, stability = 1.0, integrity = 1100.0, power = 1.0,
		boost = 1.4, flaw = "icing" })
	_add({ id = "mk3", name = "MARK III", mass = 220.0,
		main = 13400.0, lateral = 6030.0, vertical = 10050.0,
		top_speed = 320.0, drag = Vector3(4.0, 5.6, 8.0),
		max_rate = 3.1, roll_rate = 4.4, alpha_max = 14.0, roll_alpha_max = 25.0,
		rate_falloff_ref = 210.0, stability = 1.05, integrity = 1600.0, power = 1.0,
		boost = 1.45, self_don = true })
	_add({ id = "mk42", name = "MARK XLII", mass = 190.0,
		main = 13000.0, lateral = 5850.0, vertical = 9750.0,
		top_speed = 330.0, drag = Vector3(3.8, 5.2, 8.0),
		max_rate = 3.4, roll_rate = 5.0, alpha_max = 16.0, roll_alpha_max = 28.0,
		rate_falloff_ref = 215.0, stability = 0.85, integrity = 1200.0, power = 0.9,
		boost = 1.45, flaw = "unstable" })
	_add({ id = "mk50", name = "MARK L", mass = 205.0,
		main = 15200.0, lateral = 6840.0, vertical = 11400.0,
		top_speed = 380.0, drag = Vector3(4.2, 5.8, 8.5),
		max_rate = 3.6, roll_rate = 5.2, alpha_max = 18.0, roll_alpha_max = 30.0,
		rate_falloff_ref = 240.0, stability = 1.2, integrity = 2000.0, power = 1.25,
		boost = 1.5, self_don = true })

static func _add(d: Dictionary) -> void:
	_all[d.id] = Spec.new(d)

static func get_spec(id: String) -> Spec:
	_build()
	return _all.get(id, _all["mk3"])

static func all() -> Dictionary:
	_build()
	return _all
