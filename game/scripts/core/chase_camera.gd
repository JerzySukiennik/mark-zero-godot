class_name ChaseCamera
extends Camera3D
## Over the shoulder, and never directly behind.
##
## Jurek asked whether the camera should sit slightly to the right, and whether it should
## swap sides. Short answer: right always, swap almost never.
##
## Dead behind is the worst option available, because the player's own body covers exactly
## the thing he is aiming at — which is why every third-person action game since Resident
## Evil 4 offsets the camera. The character belongs in one half of the frame and the world
## in the other.
##
## SWAPPING SIDES automatically is tempting and usually wrong: the world lurches sideways
## for a reason the player did not ask for and cannot predict, and it happens most often
## when things are busy, which is exactly when a stable frame matters. Games that do it well
## (Gears) tie it to something the player is doing deliberately — taking cover on a
## left-hand wall. There is no such thing here yet. So: one side, always, and the offset
## DEEPENS when aiming, because that is when the crosshair needs the most clear space. If a
## reason to swap ever appears — a wall on the right at close quarters — it can be added
## then, tied to that reason.
##
## The suit is pushed left by moving the camera's TARGET sideways, not by orbiting the
## camera around the suit. Orbiting changes what you are looking at; shifting the target
## changes only where the body sits in frame, and leaves the direction of travel centred.

## Distance behind, at rest and at speed. Opening it with speed is the cheapest way to make
## fast flight feel fast without touching the field of view much.
const BACK_NEAR := 5.5
const BACK_FAR := 11.0
## Height above the point mass.
const UP_NEAR := 1.9
const UP_FAR := 3.4
## How far the suit is pushed off centre, in metres. Deepens while aiming.
const SHOULDER := 1.15
const SHOULDER_AIM := 1.85
## Field of view at rest, and how much speed adds.
const FOV_BASE := 68.0
const FOV_SPEED := 16.0
const FOV_AIM := -9.0                ## aiming pulls in, which reads as concentration

## Seconds for the camera to catch up. Deliberately not zero: a camera bolted rigidly to the
## suit turns the WORLD instead of turning the suit, and at speed that is nauseating.
const LAG_POS := 0.10
const LAG_AIM := 0.05                ## tighter while aiming, so the crosshair is not soggy

var shoulder_side := 1.0             ## +1 right, -1 left. One place, if it ever needs to flip.
var _aim := 0.0                      ## 0..1, smoothed

func _ready() -> void:
	fov = FOV_BASE
	far = 4000.0
	current = true

## Called every physics step by the suit that owns this camera.
##   focus    where the suit's point mass is
##   basis    the suit's orientation
##   speed    m/s
##   aiming   true while the aim trigger is held
##   top      the armour's top speed, so framing is relative to what this suit can do
func follow(delta: float, focus: Vector3, basis_: Basis, speed: float, aiming: bool, top: float) -> void:
	_aim = lerpf(_aim, 1.0 if aiming else 0.0, 1.0 - exp(-delta / 0.12))
	var fast := clampf(speed / maxf(60.0, top * 0.55), 0.0, 1.0)

	var back := lerpf(BACK_NEAR, BACK_FAR, fast)
	var up := lerpf(UP_NEAR, UP_FAR, fast)
	var side := lerpf(SHOULDER, SHOULDER_AIM, _aim) * shoulder_side

	# The camera sits behind and above; the SIDE offset is applied to where it looks, which
	# is what pushes the body off centre without swinging the view off the line of travel.
	var want_pos := focus + basis_ * Vector3(side, up, back)
	var look_at_p := focus + basis_ * Vector3(side * 0.45, 0.35, -12.0)

	var k := 1.0 - exp(-delta / lerpf(LAG_POS, LAG_AIM, _aim))
	global_position = global_position.lerp(want_pos, k)
	look_at(look_at_p, Vector3.UP)
	fov = lerpf(fov, FOV_BASE + fast * FOV_SPEED + _aim * FOV_AIM, k)

## Snap to where it should be, with no catch-up. For spawning and teleports, where lag would
## show as the camera flying in from wherever it was.
func snap(focus: Vector3, basis_: Basis) -> void:
	global_position = focus + basis_ * Vector3(SHOULDER * shoulder_side, UP_NEAR, BACK_NEAR)
	look_at(focus + basis_ * Vector3(0, 0.35, -12.0), Vector3.UP)
