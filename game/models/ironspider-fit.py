"""Does Peter actually fit inside the Iron Spider shell?

    /Applications/Blender.app/Contents/MacOS/Blender --background --python models/ironspider-fit.py

Loads the two exported `.glb` files and stands `peter.glb` inside `ironspider.glb`,
raised by LIFT (the thickness of the boot soles).

HOW THE TEST WORKS, and why it is not the obvious one. The obvious test — "is a Peter
vertex inside a plate's solid?" — fails on a correct model, because a 15-year-old's arms
hang against his own ribs: `peter.glb`'s arm meshes already intersect his own torso mesh,
so they intersect anything wrapped around that torso too. None of that is visible, and
invisible is the whole question.

So the test is the one the player actually runs: RENDER him. Peter is painted pure
emissive magenta, the suit keeps its own materials, and the pair is rendered from twelve
directions. Every magenta pixel is a place where the boy shows through the armour. The
count per view is printed, and the views are written out to look at.
"""

import bpy, math, os, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _modellib import wipe, mat, setup_render

SUITS = os.path.abspath(os.path.join(HERE, "..", "assets", "suits"))
LIFT = 0.050
RES = 700

wipe()


def load(path, prefix):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        o.name = prefix + o.name
    return new


shell = load(os.path.join(SUITS, "ironspider.glb"), "IS_")
peter = load(os.path.join(SUITS, "peter.glb"), "PE_")

for o in peter:                       # onto the boot soles; Blender's up axis is Z
    if o.parent is None:
        o.location.z += LIFT
bpy.context.view_layer.update()

shell_meshes = [o for o in shell if o.type == 'MESH']
peter_meshes = [o for o in peter if o.type == 'MESH']

flag = mat("mat_flag", (1.0, 0.0, 1.0), 0.5, emit=(1.0, 0.0, 1.0), emit_strength=6.0)
for o in peter_meshes:
    o.data.materials.clear()
    o.data.materials.append(flag)

shot = setup_render(samples=8, bg=(0.0, 0.25, 0.0), bg_strength=1.0, ground=False)
scn = bpy.context.scene
scn.render.resolution_x = scn.render.resolution_y = RES


def leaks(path):
    shot_img = bpy.data.images.load(path)
    px = list(shot_img.pixels)
    n = 0
    for i in range(0, len(px), 4):
        r, g, b = px[i], px[i + 1], px[i + 2]
        if r > 0.55 and b > 0.55 and g < 0.30:
            n += 1
    bpy.data.images.remove(shot_img)
    return n


total, views = 0, []
for k in range(12):
    a = math.tau * k / 12
    d = 4.6
    p = "/tmp/fit-%02d.png" % k
    shot(p, (math.sin(a) * d, math.cos(a) * d, 1.00), (0, 0, 0.92), 95)
    n = leaks(p)
    total += n
    views.append((n, int(math.degrees(a)), p))
shot("/tmp/fit-top.png", (0.0, 0.05, 3.4), (0, 0, 1.0), 85)
n = leaks("/tmp/fit-top.png"); total += n; views.append((n, -1, "/tmp/fit-top.png"))

print("---- FIT: magenta pixels of peter.glb visible through ironspider.glb ----")
for (n, deg, p) in views:
    print("   yaw %4s  leaked px %6d   %s" % (deg if deg >= 0 else "top", n, p))
print("TOTAL LEAK PIXELS:", total, "of", RES * RES * 13, "=>",
      "PASS" if total == 0 else "FAIL")

# ------------------------------------------------------------ look at it as well
for o in peter_meshes:
    o.data.materials.clear()
mat("mat_boy", (0.42, 0.28, 0.22), 0.8)
for o in peter_meshes:
    o.data.materials.append(bpy.data.materials["mat_boy"])
scn.render.resolution_x = scn.render.resolution_y = 1200
wf = setup_render(samples=48)
HIDE_FRONT = {"IS_chest", "IS_abdomen", "IS_pelvis", "IS_faceplate", "IS_thighL",
              "IS_thighR", "IS_shinL", "IS_shinR", "IS_helmet", "IS_collarL",
              "IS_collarR", "IS_beltL", "IS_beltR", "IS_bootL", "IS_bootR"}
for o in shell_meshes:
    if o.name in HIDE_FRONT:
        o.hide_render = True
wf("/tmp/fit-cutaway-front.png", (0.0, 4.6, 0.90), (0, 0, 0.90), 95)
wf("/tmp/fit-cutaway-head.png", (0.0, 1.05, 1.56), (0, 0, 1.50), 85)
print("DONE")
