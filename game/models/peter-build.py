"""MARK ZERO — `peter.glb`: the boy inside the Iron Spider.

    /Applications/Blender.app/Contents/MacOS/Blender --background --python models/peter-build.py

A 15-year-old in a t-shirt, jeans and trainers, 1.60 m tall, built the same way
`pilot.glb` is: lofted profile rings in spec space (+Y up, faces -Z, +X = LEFT),
flat Principled colours, no textures, no armature — one Empty per joint.

The rig is the FULL contract hierarchy, identical in shape to `pilot.glb`, so the
game can swap Peter for the Iron Spider exactly the way it swaps Tony for an armour.
`piv_thrusterL/R` exist and emit nothing; they are there so the rig binding never has
to special-case him.

Geometry is authored on the 1.78 m master profile the pilot uses and scaled to 1.60 m
by `S` at build time, which keeps the two characters proportionally comparable and
keeps the numbers in this file readable next to `pilot-build.py`.
"""

import bpy, math, os, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _modellib import (Part, TAU, resample, ring_xz, ring_xy, sup, mat, build_object,
                       wipe, empty, aim_quat, stats, setup_render, B, dome)

OUT = os.path.abspath(os.path.join(HERE, "..", "assets", "suits"))
RENDER = os.environ.get("RENDER", "1") == "1"

HEIGHT = 1.60
MASTER = 1.78
S = HEIGHT / MASTER          # every spec number below is on the 1.78 master

NT, NH, NA, NL = 34, 32, 22, 24

# joints, master scale
Y_SHOULDER, X_SH = 1.425, 0.145
Y_ELBOW, X_EL = 1.155, 0.162
Y_WRIST, X_WR = 0.930, 0.173
Y_HIPJ, X_HIP = 0.870, 0.078
Y_KNEE, X_KN = 0.475, 0.075
Y_ANKLE, X_AN = 0.090, 0.075
Y_NECK, Y_HEAD = 1.478, 1.556
Y_HIPS, Y_CHEST = 0.965, 1.135

wipe()

# t-shirt: a warm brick red, so he reads as Peter even out of the suit; jeans indigo.
mat("mat_primary", (0.330, 0.088, 0.080), 0.88, spec=0.30)      # t-shirt
mat("mat_secondary", (0.115, 0.160, 0.255), 0.92, spec=0.25)    # jeans
mat("mat_trim", (0.560, 0.372, 0.285), 0.76, spec=0.30)         # skin
mat("mat_dark", (0.036, 0.028, 0.026), 0.66, spec=0.35)         # hair, shoe upper, eyes
# Peter carries no emitters, so `mat_glow` is here only to keep the contract's
# material names: it is the white rubber of the trainers, emission strength 0.
mat("mat_glow", (0.620, 0.630, 0.645), 0.55, spec=0.45)         # trainer soles

objs = {}


def emit(name, part, mats, smooth=40.0):
    part.scale_about(S, 0.0)
    objs[name] = build_object(name, part, mats, smooth)


# ---------------------------------------------------------------- torso (t-shirt)
SLEEVE = 1.352                                   # short sleeve hem, master scale
torso_prof = [
    (0.980, 0.112, 0.091, 0.004),                # shirt hem, loose
    (1.040, 0.104, 0.087, 0.002),
    (1.100, 0.100, 0.085, 0.000),                # waist
    (1.160, 0.103, 0.089, -0.003),
    (1.230, 0.112, 0.095, -0.007),
    (1.300, 0.122, 0.099, -0.008),               # chest
    (1.365, 0.131, 0.097, -0.004),
    (1.425, 0.142, 0.090, 0.002),                # shoulder line
    (1.444, 0.136, 0.086, 0.003),
    (1.458, 0.121, 0.080, 0.004),
    (1.475, 0.088, 0.071, 0.004),
    (1.492, 0.050, 0.050, 0.004),                # collar
    (1.515, 0.043, 0.045, 0.003),
    (1.548, 0.042, 0.044, 0.002),                # neck top, inside the head
]
tp = resample(torso_prof, 30)
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, NT, 2.5) for (y, rx, rz, zc) in tp],
       mat_fn=lambda s: 1 if tp[s][0] > 1.486 else 0)
# collar band
for k, (y, rx, rz, zc) in enumerate(tp):
    if 1.480 < y < 1.500:
        pass
emit("body_shirt", p, ["mat_primary", "mat_trim"])

# the bare neck is its own object so the shirt collar can move independently
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, 18, 2.2) for (y, rx, rz, zc) in
        resample([(1.470, 0.046, 0.048, 0.004), (1.500, 0.043, 0.045, 0.004),
                  (1.545, 0.042, 0.044, 0.002)], 8)])
emit("body_neck", p, ["mat_trim"])

# ---------------------------------------------------------------- hips (jeans)
# Slimmer through the seat than the pilot's: a 15-year-old is narrow there, and the
# armour that has to close over these numbers was coming out pear-shaped.
hips_prof = [
    (1.060, 0.082, 0.070, 0.000),
    (1.020, 0.090, 0.076, 0.000),
    (0.950, 0.106, 0.087, 0.000),
    (0.905, 0.114, 0.093, 0.002),                # seat
    (0.868, 0.116, 0.091, 0.000),
    (0.838, 0.109, 0.081, -0.004),
    (0.815, 0.096, 0.064, -0.004),
    (0.800, 0.072, 0.043, -0.004),               # crotch
]
hp = resample(hips_prof, 16)
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, NT, 2.4) for (y, rx, rz, zc) in hp])
emit("body_hips", p, ["mat_secondary"])

# ---------------------------------------------------------------- head
head_prof = [   # (y, rx, rz, zc)
    (1.486, 0.033, 0.035, 0.006),
    (1.512, 0.050, 0.058, -0.004),
    (1.540, 0.062, 0.074, -0.014),               # chin
    (1.564, 0.074, 0.086, -0.015),               # jaw
    (1.590, 0.083, 0.093, -0.014),               # mouth
    (1.618, 0.089, 0.097, -0.012),               # nose / cheek
    (1.648, 0.092, 0.098, -0.009),               # eye line
    (1.678, 0.093, 0.096, -0.004),               # skull widest
    (1.708, 0.089, 0.089, 0.000),
    (1.737, 0.077, 0.076, 0.003),
    (1.757, 0.054, 0.052, 0.005),
    (1.766, 0.021, 0.022, 0.006),
]
hd = resample(head_prof, 24)
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, NH, 2.2) for (y, rx, rz, zc) in hd])


def head_at(y):
    for i in range(len(hd) - 1):
        if hd[i][0] <= y <= hd[i + 1][0]:
            t = (y - hd[i][0]) / (hd[i + 1][0] - hd[i][0])
            return tuple(hd[i][k] + (hd[i + 1][k] - hd[i][k]) * t for k in (1, 2, 3))
    return (hd[-1][1], hd[-1][2], hd[-1][3])


def face_z(y, x):
    rx, rz, zc = head_at(y)
    t = min(abs(x) / rx, 0.999)
    return zc - rz * (1.0 - t ** 2.2) ** (1 / 2.2)


def on_face(x, y, out=0.0018):
    return (x, y, face_z(y, x) - out)


# nose
nv, nf = [], []
lvl = [(1.666, 0.008, 0.002), (1.648, 0.009, 0.006), (1.633, 0.010, 0.011),
       (1.621, 0.011, 0.014), (1.611, 0.014, 0.009), (1.605, 0.014, 0.002)]
for (y, w, out) in lvl:
    zf = face_z(y, 0.0)
    nv += [(-w, y, zf - out), (w, y, zf - out),
           (-w * 1.5, y, zf + 0.004), (w * 1.5, y, zf + 0.004)]
for i in range(len(lvl) - 1):
    a, b = i * 4, (i + 1) * 4
    nf += [(a + 0, a + 1, b + 1, b + 0), (a + 2, a + 0, b + 0, b + 2),
           (a + 1, a + 3, b + 3, b + 1)]
nf += [(0, 2, 3, 1), (len(nv) - 4, len(nv) - 3, len(nv) - 1, len(nv) - 2)]
p.add(nv, nf, 0)

# ears
for sx in (1, -1):
    ev, ef = [], []
    cy, cz, seg = 1.641, 0.030, 10
    inner_x = sx * 0.082
    for k, (rr_y, rr_z, dx) in enumerate([(0.025, 0.016, 0.0), (0.019, 0.011, sx * 0.013)]):
        for i in range(seg):
            a = TAU * i / seg
            ev.append((inner_x + dx, cy + math.sin(a) * rr_y, cz + math.cos(a) * rr_z))
    for i in range(seg):
        j = (i + 1) % seg
        ef.append((i, j, seg + j, seg + i))
    ef.append(tuple(range(seg))[::-1])
    ef.append(tuple(range(seg, 2 * seg)))
    p.add(ev, ef, 0)

# eyes + brows
for sx in (1, -1):
    cx, cy = sx * 0.035, 1.648
    ev, ef = [], []
    seg = 14
    ev.append(on_face(cx, cy, 0.0032))
    for i in range(seg):
        a = TAU * i / seg
        ca, sa = math.cos(a), math.sin(a)
        ev.append(on_face(cx + ca * 0.0175, cy + sa * (0.0104 if sa > 0 else 0.0080), 0.0014))
    for i in range(seg):
        ef.append((0, 1 + i, 1 + (i + 1) % seg))
    p.add(ev, ef, 1)
    bv, bf = [], []
    for t in (-1.0, -0.35, 0.35, 1.0):
        bx = cx + t * 0.0200
        arch = 0.0020 * (1.0 - t * t)
        bv.append(on_face(bx, 1.6665 + arch, 0.0016))
        bv.append(on_face(bx, 1.6620 + arch, 0.0016))
    for i in range(3):
        bf.append((i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2))
    p.add(bv, bf, 1)
# mouth
mv, mf = [], []
for t in (-1.0, -0.4, 0.4, 1.0):
    mx_ = t * 0.0150
    dip = 0.0016 * (1.0 - t * t)
    mv.append(on_face(mx_, 1.5815 - dip, 0.0016))
    mv.append(on_face(mx_, 1.5780 - dip, 0.0016))
for i in range(3):
    mf.append((i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2))
p.add(mv, mf, 1)
emit("body_head", p, ["mat_trim", "mat_dark"])

# ---------------------------------------------------------------- hair (tousled)
HAIR_TOP = 1.784
p = Part()


def edge_y(a):
    s = math.sin(a)                              # +z is the back of the head
    if s >= 0:
        return 1.663 - 0.055 * s ** 1.1          # nape
    return 1.663 + 0.028 * (-s) ** 1.6           # fringe sits high over the brow


def tuft(a, y):
    """Deterministic ruffle — three offset sine lobes, so the cap is not a swim cap."""
    return (0.0115 * math.sin(a * 3.0 + 0.7) + 0.0082 * math.sin(a * 5.0 + 2.1)
            + 0.0055 * math.sin(a * 9.0 + 4.4)) * (0.55 + 1.5 * max(0.0, y - 1.690) / 0.08)


def hair_ring(yfn, grow, lift):
    o, ii = [], []
    for k in range(NH):
        a = TAU * k / NH
        y = min(yfn(a), 1.766)
        rx_, rz_, zc_ = head_at(y)
        px, pz = sup(a, 2.2)
        ii.append((px * rx_, y, zc_ + pz * rz_))
        g = grow + max(0.0, tuft(a, y))
        o.append((px * (rx_ * 1.04 + g), y + lift + g * 0.55, zc_ + pz * (rz_ * 1.04 + g)))
    return o, ii


outer, inner = [], []
ro, ri = hair_ring(edge_y, 0.010, 0.0)
outer.append(ro); inner.append(ri)
for y in (1.690, 1.712, 1.734, 1.750, 1.760, 1.766):
    ro, ri = hair_ring(lambda a, y=y: y, 0.014, 0.006)
    outer.append(ro); inner.append(ri)
outer.append([(x * 0.36, HAIR_TOP, z * 0.36 - 0.002) for (x, y, z) in outer[-1]])
inner.append([(x * 0.36, 1.770, z * 0.36 - 0.001) for (x, y, z) in inner[-1]])
p.loft(outer, cap_start=False, cap_end=True)
p.loft(inner, cap_start=False, cap_end=True, flip=True)
i0 = len(outer) * NH + 1
for i in range(NH):
    j = (i + 1) % NH
    p.f.append((i, j, i0 + j, i0 + i))
    p.m.append(0)
emit("body_hair", p, ["mat_dark"])

# ---------------------------------------------------------------- arms
for side, sx in (("L", 1), ("R", -1)):
    prof = [
        (1.444, 0.022, 0.023, 0.146),
        (1.435, 0.039, 0.039, 0.145),
        (1.422, 0.047, 0.046, 0.146),
        (1.400, 0.048, 0.047, 0.149),
        (1.375, 0.047, 0.046, 0.151),
        (SLEEVE, 0.046, 0.045, 0.153),           # sleeve hem, mid-upper-arm
        (1.344, 0.038, 0.037, 0.154),
        (1.300, 0.037, 0.036, 0.157),
        (1.240, 0.036, 0.035, 0.159),
        (1.190, 0.034, 0.033, 0.161),
        (1.160, 0.031, 0.030, 0.162),
        (1.140, 0.026, 0.025, 0.162),
    ]
    ap = resample(prof, 22)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.004, rx, rz, NA) for (y, rx, rz, cx) in ap],
           mat_fn=lambda s: 0 if ap[s][0] > SLEEVE - 0.003 else 1)
    emit("body_arm" + side, p, ["mat_primary", "mat_trim"])

    prof = [
        (1.180, 0.034, 0.033, 0.162),
        (1.130, 0.037, 0.036, 0.164),
        (1.070, 0.034, 0.033, 0.167),
        (1.010, 0.029, 0.028, 0.170),
        (0.960, 0.025, 0.024, 0.172),
        (0.932, 0.023, 0.022, 0.173),
    ]
    fp = resample(prof, 15)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.004, rx, rz, NA) for (y, rx, rz, cx) in fp])
    emit("body_forearm" + side, p, ["mat_trim"])

    prof = [
        (0.938, 0.022, 0.023, 0.173),
        (0.912, 0.020, 0.030, 0.174),
        (0.882, 0.019, 0.036, 0.175),
        (0.845, 0.018, 0.037, 0.176),
        (0.805, 0.016, 0.034, 0.177),
        (0.778, 0.012, 0.026, 0.178),
        (0.762, 0.007, 0.014, 0.178),
    ]
    hp2 = resample(prof, 15)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.008, rx, rz, 18, 2.4) for (y, rx, rz, cx) in hp2])
    trings = []
    for k, (y, r) in enumerate([(0.908, 0.011), (0.885, 0.013), (0.858, 0.012), (0.840, 0.008)]):
        trings.append(ring_xz(sx * (0.173 - 0.010 - k * 0.002), y,
                              -0.020 - k * 0.004, r * 0.85, r, 10))
    p.loft(trings)
    emit("body_hand" + side, p, ["mat_trim"])

# ---------------------------------------------------------------- legs
for side, sx in (("L", 1), ("R", -1)):
    prof = [
        (0.955, 0.067, 0.073, 0.077),
        (0.905, 0.075, 0.081, 0.078),
        (0.845, 0.076, 0.082, 0.078),
        (0.755, 0.072, 0.078, 0.078),
        (0.655, 0.065, 0.071, 0.077),
        (0.555, 0.058, 0.064, 0.076),
        (0.500, 0.054, 0.059, 0.075),
        (0.460, 0.048, 0.053, 0.075),
        (0.435, 0.039, 0.043, 0.075),
    ]
    tp2 = resample(prof, 18)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.0, rx, rz, NL, 2.2) for (y, rx, rz, cx) in tp2])
    emit("body_jeans" + side, p, ["mat_secondary"])

    prof = [
        (0.530, 0.051, 0.056, 0.075),
        (0.470, 0.051, 0.058, 0.075),
        (0.405, 0.052, 0.063, 0.075),            # calf
        (0.340, 0.049, 0.060, 0.075),
        (0.265, 0.043, 0.052, 0.075),
        (0.190, 0.038, 0.045, 0.075),
        (0.135, 0.035, 0.041, 0.075),
        (0.098, 0.034, 0.040, 0.075),
    ]
    sp = resample(prof, 18)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.002, rx, rz, NL, 2.2) for (y, rx, rz, cx) in sp])
    emit("body_shin" + side, p, ["mat_secondary"])

    shoe = [
        (0.082, 0.036, 0.034, 0.062),            # (z, rx, ry, cy) heel collar
        (0.058, 0.045, 0.050, 0.066),
        (0.014, 0.050, 0.051, 0.063),
        (-0.034, 0.052, 0.043, 0.052),
        (-0.088, 0.053, 0.035, 0.041),
        (-0.142, 0.050, 0.027, 0.031),
        (-0.184, 0.042, 0.020, 0.023),
        (-0.208, 0.024, 0.013, 0.016),
    ]
    shp = resample(shoe, 17)
    p = Part()
    rings = []
    for (z, rx, ry, cy) in shp:
        r = ring_xy(sx * 0.075, cy, z, rx, ry, 20, 2.8)
        rings.append([(px, max(py, 0.019), pz) for (px, py, pz) in r])
    p.loft(rings)
    srings = [ring_xy(sx * 0.075, 0.0115, z, rx + 0.002, 0.0115, 20, 5.0)
              for (z, rx, ry, cy) in shp]
    p.loft(srings, mat=1)
    p.rot_y(sx * math.radians(-7), sx * 0.075, 0.03)
    emit("body_shoe" + side, p, ["mat_dark", "mat_glow"])

# ------------------------------------------------- exact height correction
# The tousled hair adds a few unpredictable millimetres on top of the skull, so the
# height is MEASURED and corrected rather than assumed. Pivots take the same factor,
# which keeps the rig glued to the geometry.
_top = max((ob.matrix_world @ v.co).z for ob in objs.values() for v in ob.data.vertices)
K = HEIGHT / _top
for ob in objs.values():
    for v in ob.data.vertices:
        v.co *= K
SS = S * K
print("HEIGHT CORRECTION:", round(_top, 4), "->", HEIGHT, "k=", round(K, 5))

# ---------------------------------------------------------------- rig
# Every pivot from the contract exists, including the two thrusters Peter never fires.
PIVOTS = {
    "piv_root":      (None, (0.0, 0.0, 0.0)),
    "piv_hips":      ("piv_root", (0.0, Y_HIPS, 0.004)),
    "piv_chest":     ("piv_hips", (0.0, Y_CHEST, -0.002)),
    "piv_neck":      ("piv_chest", (0.0, Y_NECK, 0.004)),
    "piv_head":      ("piv_neck", (0.0, Y_HEAD, 0.004)),
    "piv_reactor":   ("piv_hips", (0.0, 1.300, -0.106)),
    "piv_shoulderL": ("piv_chest", (X_SH, Y_SHOULDER, 0.004)),
    "piv_elbowL":    ("piv_shoulderL", (X_EL, Y_ELBOW, 0.004)),
    "piv_palmL":     ("piv_elbowL", (0.176, 0.868, -0.014)),
    "piv_shoulderR": ("piv_chest", (-X_SH, Y_SHOULDER, 0.004)),
    "piv_elbowR":    ("piv_shoulderR", (-X_EL, Y_ELBOW, 0.004)),
    "piv_palmR":     ("piv_elbowR", (-0.176, 0.868, -0.014)),
    "piv_hipL":      ("piv_hips", (X_HIP, Y_HIPJ, 0.0)),
    "piv_kneeL":     ("piv_hipL", (X_KN, Y_KNEE, 0.002)),
    "piv_ankleL":    ("piv_kneeL", (X_AN, Y_ANKLE, -0.004)),
    "piv_thrusterL": ("piv_ankleL", (X_AN, 0.026, 0.008)),
    "piv_hipR":      ("piv_hips", (-X_HIP, Y_HIPJ, 0.0)),
    "piv_kneeR":     ("piv_hipR", (-X_KN, Y_KNEE, 0.002)),
    "piv_ankleR":    ("piv_kneeR", (-X_AN, Y_ANKLE, -0.004)),
    "piv_thrusterR": ("piv_ankleR", (-X_AN, 0.026, 0.008)),
}
# -Y of each emitter points where its output goes. Peter emits nothing, but the axes
# are authored anyway so a rig bound to him reads the same numbers it reads on a suit.
AIM = {
    "piv_palmL": (-0.942, -0.100, -0.321),       # out of the palm, medial and forward
    "piv_palmR": (0.942, -0.100, -0.321),
    "piv_thrusterL": (0.0, -1.0, 0.0),
    "piv_thrusterR": (0.0, -1.0, 0.0),
    "piv_reactor": None,                          # -Z out of the chest = identity
}
MESH_PARENT = {
    "body_hips": "piv_hips", "body_shirt": "piv_chest", "body_neck": "piv_neck",
    "body_head": "piv_head", "body_hair": "piv_head",
    "body_armL": "piv_shoulderL", "body_forearmL": "piv_elbowL", "body_handL": "piv_palmL",
    "body_armR": "piv_shoulderR", "body_forearmR": "piv_elbowR", "body_handR": "piv_palmR",
    "body_jeansL": "piv_hipL", "body_shinL": "piv_kneeL", "body_shoeL": "piv_ankleL",
    "body_jeansR": "piv_hipR", "body_shinR": "piv_kneeR", "body_shoeR": "piv_ankleR",
}

WORLD = {n: Vector(B(tuple(c * SS for c in loc))) for n, (par, loc) in PIVOTS.items()}
emp = {}
for name in PIVOTS:
    emp[name] = empty(name)
for name, (parent, loc) in PIVOTS.items():
    e = emp[name]
    e.parent = emp[parent] if parent else None
    e.location = WORLD[name] - (WORLD[parent] if parent else Vector((0, 0, 0)))
    d = AIM.get(name)
    if d:
        e.rotation_mode = 'QUATERNION'
        e.rotation_quaternion = aim_quat(d)
bpy.context.view_layer.update()

# Meshes carry world-space vertices. Give each one its own origin at its centre, then
# place it so the geometry lands back where it was: the game can then spin a part about
# itself, and the parent's rotation is the only thing that moves it.
for mname, pname in MESH_PARENT.items():
    ob = objs[mname]
    c = sum((ob.matrix_world @ v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
    for v in ob.data.vertices:
        v.co -= c
    ob.parent = emp[pname]
    par = emp[pname].matrix_world
    ob.matrix_parent_inverse.identity()
    loc = par.inverted() @ c
    ob.location = loc
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = par.to_quaternion().inverted()
bpy.context.view_layer.update()

# ---------------------------------------------------------------- stats
tris, mn, mx = stats(list(objs.values()))
print("TRIS:", tris)
print("HEIGHT:", round(mx[2] - mn[2], 4), "WIDTH:", round(mx[0] - mn[0], 4),
      "DEPTH:", round(mx[1] - mn[1], 4), "FLOOR:", round(mn[2], 4))
for n in ("piv_palmL", "piv_palmR", "piv_head"):
    print("  ", n, [round(v, 3) for v in emp[n].matrix_world.translation])

os.makedirs(OUT, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "peter.glb"), export_format='GLB',
                          use_selection=False, export_apply=True, export_yup=True,
                          export_cameras=False, export_lights=False)
print("EXPORTED")

if not RENDER:
    raise SystemExit

shot = setup_render(samples=int(os.environ.get("SAMPLES", "96")))
shot(os.path.join(OUT, "peter-front.png"), (0.0, 5.6, 0.86), (0, 0, 0.86), 100)
shot(os.path.join(OUT, "peter-side.png"), (-5.6, 0.0, 0.86), (0, 0, 0.86), 100)
shot(os.path.join(OUT, "peter-hero.png"), (2.50, 3.46, 1.42), (-0.02, 0.0, 0.86), 85)
if os.environ.get("FACE") == "1":
    shot("/tmp/peter-face.png", (0.32, 0.95, 1.52), (0.0, 0.0, 1.46), 85)
    shot("/tmp/peter-back.png", (0.0, -6.6, 0.86), (0, 0, 0.86), 100)
print("DONE")
