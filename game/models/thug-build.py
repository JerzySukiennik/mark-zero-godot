"""MARK ZERO — `thug.glb`: the adult men you fight.

    /Applications/Blender.app/Contents/MacOS/Blender --background --python models/thug-build.py

A grown man in street clothes — work boots, heavy trousers, a shirt under a canvas
jacket with a rolled hood at the nape — 1.82 m tall, built the same way `peter.glb`
and `pilot.glb` are: lofted profile rings in spec space (+Y up, faces -Z, +X = LEFT),
flat Principled colours, no textures, no UVs, no armature, one Empty per joint.

WHY HE EXISTS. The enemies were `pilot.glb`, a THIRTEEN-YEAR-OLD BOY, recoloured. A
child is not made into an adult by scaling: the tell is the head, which is a seventh
of an adult and closer to a fifth of a child, and no uniform scale can change that
ratio. So this model is authored on adult landmarks from the floor up — head 1 : 7.4,
shoulders 0.51 m across, a thick neck, heavy forearms and a deep chest — and it is
those RATIOS, not the height, that are the deliverable.

The rig is the FULL contract hierarchy, identical in shape to `peter.glb`, including
`piv_thrusterL/R`, which a man in boots will never fire. They are there so `SuitRig`
binds to him with no special case.

NO EMISSION anywhere. `scripts/enemy/enemy.gd` sets albedo, metallic, roughness and
emission itself, per surface, at runtime; anything baked in here is overwritten or —
worse, for emission — added to. The enemies were just toned down for being too bright.

`RENDER=0` skips the previews, `SAMPLES=n` sets EEVEE quality, `EXTRA=1` adds a back
view and a head close-up to /tmp.
"""

import bpy, math, os, sys
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _modellib import (Part, TAU, resample, ring_xz, ring_xy, sup, mat, build_object,
                       wipe, empty, aim_quat, stats, setup_render, B, dome)

OUT = os.path.abspath(os.path.join(HERE, "..", "assets", "suits"))
RENDER = os.environ.get("RENDER", "1") == "1"

HEIGHT = 1.82
MASTER = 1.82
S = HEIGHT / MASTER          # authored at final size; the hook stays for consistency

NT, NH, NA, NL = 34, 30, 22, 24

# Joint centres. Every one is a fraction of stature off an adult male canon, not off
# the boy's numbers with a multiplier on top.
Y_SHOULDER, X_SH = 1.472, 0.190       # acromion; half-span 0.190 -> 0.51 m over deltoids
Y_ELBOW, X_EL = 1.132, 0.202
Y_WRIST, X_WR = 0.878, 0.212
Y_HIPJ, X_HIP = 0.940, 0.098          # greater trochanter
Y_KNEE, X_KN = 0.520, 0.095
Y_ANKLE, X_AN = 0.098, 0.095          # raised: he is standing in a work boot
Y_NECK, Y_HEAD = 1.540, 1.620
Y_HIPS, Y_CHEST = 0.990, 1.170

wipe()

# MID-VALUE AND NEUTRAL, ON PURPOSE. The game repaints every surface, so a saturated
# base colour here would only ever be seen in these previews and would lie about what
# the thug looks like in game. Values sit in 0.07 - 0.48 linear: dark enough to read
# as worn cloth, light enough that a tint lands on something.
mat("mat_primary", (0.283, 0.272, 0.256), 0.89, spec=0.28)      # canvas jacket
mat("mat_secondary", (0.223, 0.232, 0.252), 0.91, spec=0.24)    # heavy trousers
mat("mat_trim", (0.452, 0.322, 0.256), 0.74, spec=0.32)         # skin
mat("mat_dark", (0.074, 0.071, 0.069), 0.63, spec=0.36)         # boots, hair, belt, eyes
# No emitters on a man in a jacket, so `mat_glow` keeps the contract's name and carries
# the shirt and the boot rubber instead. Emission strength 0 — see the header.
mat("mat_glow", (0.470, 0.462, 0.446), 0.80, spec=0.40)         # shirt, cuffs, soles

objs = {}


def emit(name, part, mats, smooth=40.0):
    part.scale_about(S, 0.0)
    objs[name] = build_object(name, part, mats, smooth)


# ---------------------------------------------------------------- torso (jacket)
# Deep through the chest and square across the yoke. A boy's torso is a tube; this one
# has a v from waist to shoulder, which is most of what "adult male" reads as at 30 m.
SHIRT_Y = 1.524                                  # above this the jacket opens on shirt
torso_prof = [
    (0.988, 0.180, 0.134, 0.005),                # jacket hem, flared over the seat
    (1.048, 0.172, 0.128, 0.003),
    (1.118, 0.166, 0.124, 0.000),                # waist
    (1.190, 0.176, 0.133, -0.004),
    (1.262, 0.190, 0.141, -0.008),
    (1.328, 0.202, 0.146, -0.009),               # chest
    (1.396, 0.209, 0.141, -0.004),
    (1.448, 0.213, 0.133, 0.003),                # shoulder yoke
    (1.482, 0.211, 0.127, 0.005),                # yoke stays SQUARE to the very top
    (1.502, 0.196, 0.119, 0.006),
    (1.516, 0.152, 0.106, 0.006),
    (1.530, 0.092, 0.086, 0.006),                # collar
    (1.552, 0.069, 0.071, 0.005),
    (1.605, 0.066, 0.068, 0.004),                # shirt neck, ends inside the head
]
tp = resample(torso_prof, 30)
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, NT, 2.5) for (y, rx, rz, zc) in tp],
       mat_fn=lambda s: 1 if tp[s][0] > SHIRT_Y else 0)

# The rolled hood at the nape. Cheap, and it is the one silhouette cue that says
# "street" from behind at forty metres, where the face is four pixels wide.
hood = []
for k, (y, rx, rz, zc, sqz) in enumerate([
        (1.408, 0.112, 0.034, 0.080, 1.0),
        (1.442, 0.132, 0.046, 0.092, 1.0),
        (1.476, 0.138, 0.050, 0.099, 1.0),
        (1.506, 0.128, 0.045, 0.097, 1.0),
        (1.532, 0.098, 0.031, 0.089, 1.0)]):
    hood.append([(px, py, pz) for (px, py, pz) in
                 ring_xz(0.0, y, zc, rx, rz, 18, 2.6)])
p.loft(hood, mat=0)
emit("body_jacket", p, ["mat_primary", "mat_glow"])

# The bare neck is its own object so the collar can move independently of it. Thick:
# an adult male neck is roughly three quarters the width of his own jaw.
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, 18, 2.2) for (y, rx, rz, zc) in
        resample([(1.500, 0.063, 0.066, 0.004), (1.540, 0.060, 0.063, 0.003),
                  (1.600, 0.058, 0.061, 0.001)], 8)])
emit("body_neck", p, ["mat_trim"])

# ---------------------------------------------------------------- hips (trousers)
hips_prof = [
    (1.032, 0.138, 0.106, 0.000),                # inside the jacket, never seen
    (1.010, 0.158, 0.124, 0.000),
    (0.992, 0.172, 0.135, 0.000),
    (0.962, 0.185, 0.143, 0.004),                # seat, as wide as the thigh tops
    (0.924, 0.186, 0.140, 0.000),
    (0.890, 0.176, 0.126, -0.005),
    (0.868, 0.152, 0.099, -0.006),
    (0.850, 0.112, 0.065, -0.006),               # crotch
]
hp = resample(hips_prof, 16)
p = Part()
p.loft([ring_xz(0, y, zc, rx, rz, NT, 2.4) for (y, rx, rz, zc) in hp])
# belt — a band a centimetre proud of the waistband, on the dark slot
belt = []
for (y, g) in ((0.962, 0.000), (0.952, 0.005), (0.924, 0.005), (0.914, 0.000)):
    belt.append(ring_xz(0, y, 0.000, 0.187 + g, 0.142 + g, NT, 2.4))
p.loft(belt, cap_start=False, cap_end=False, mat=1)
emit("body_hips", p, ["mat_secondary", "mat_dark"])

# ---------------------------------------------------------------- head
# Chin 1.570, crown 1.796, hair to about 1.814: a head of roughly 1 : 7.4 of stature.
# The boy's was 1 : 6.4. This single ratio is the difference the brief asked for.
head_prof = [   # (y, rx, rz, zc)
    (1.535, 0.050, 0.053, 0.009),
    (1.558, 0.063, 0.071, -0.002),
    (1.570, 0.073, 0.087, -0.015),               # chin
    (1.596, 0.084, 0.099, -0.019),               # jaw — heavy, squared
    (1.627, 0.091, 0.105, -0.018),               # mouth
    (1.658, 0.095, 0.109, -0.015),               # nose / cheekbone
    (1.684, 0.097, 0.110, -0.011),               # eye line
    (1.712, 0.098, 0.108, -0.005),               # skull widest
    (1.742, 0.094, 0.100, 0.001),
    (1.768, 0.081, 0.085, 0.005),
    (1.788, 0.056, 0.058, 0.007),
    (1.798, 0.023, 0.025, 0.008),
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


def on_face(x, y, out=0.002):
    return (x, y, face_z(y, x) - out)


# nose — bigger and straighter than the boy's
nv, nf = [], []
lvl = [(1.706, 0.009, 0.002), (1.684, 0.010, 0.008), (1.666, 0.011, 0.014),
       (1.652, 0.013, 0.018), (1.640, 0.017, 0.012), (1.632, 0.017, 0.003)]
for (y, w, out) in lvl:
    zf = face_z(y, 0.0)
    nv += [(-w, y, zf - out), (w, y, zf - out),
           (-w * 1.5, y, zf + 0.005), (w * 1.5, y, zf + 0.005)]
for i in range(len(lvl) - 1):
    a, b = i * 4, (i + 1) * 4
    nf += [(a + 0, a + 1, b + 1, b + 0), (a + 2, a + 0, b + 0, b + 2),
           (a + 1, a + 3, b + 3, b + 1)]
nf += [(0, 2, 3, 1), (len(nv) - 4, len(nv) - 3, len(nv) - 1, len(nv) - 2)]
p.add(nv, nf, 0)

# ears
for sx in (1, -1):
    ev, ef = [], []
    cy, cz, seg = 1.674, 0.034, 10
    inner_x = sx * 0.088
    for k, (rr_y, rr_z, dx) in enumerate([(0.029, 0.018, 0.0), (0.022, 0.013, sx * 0.014)]):
        for i in range(seg):
            a = TAU * i / seg
            ev.append((inner_x + dx, cy + math.sin(a) * rr_y, cz + math.cos(a) * rr_z))
    for i in range(seg):
        j = (i + 1) % seg
        ef.append((i, j, seg + j, seg + i))
    ef.append(tuple(range(seg))[::-1])
    ef.append(tuple(range(seg, 2 * seg)))
    p.add(ev, ef, 0)

# eyes, heavy brows, a stubble shadow along the jaw — all flat patches on slot 1, the
# same trick peter.glb uses. The brow is deeper than the boy's; a low brow is the other
# half of reading as a grown man.
for sx in (1, -1):
    cx, cy = sx * 0.037, 1.684
    ev, ef = [], []
    seg = 14
    ev.append(on_face(cx, cy, 0.0034))
    for i in range(seg):
        a = TAU * i / seg
        ca, sa = math.cos(a), math.sin(a)
        ev.append(on_face(cx + ca * 0.0180, cy + sa * (0.0094 if sa > 0 else 0.0080), 0.0016))
    for i in range(seg):
        ef.append((0, 1 + i, 1 + (i + 1) % seg))
    p.add(ev, ef, 1)
    bv, bf = [], []
    for t in (-1.0, -0.35, 0.35, 1.0):
        bx = cx + t * 0.0225
        arch = 0.0014 * (1.0 - t * t)
        bv.append(on_face(bx, 1.7025 + arch, 0.0018))
        bv.append(on_face(bx, 1.6955 + arch, 0.0018))
    for i in range(3):
        bf.append((i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2))
    p.add(bv, bf, 1)
# mouth
mv, mf = [], []
for t in (-1.0, -0.4, 0.4, 1.0):
    mx_ = t * 0.0175
    dip = 0.0016 * (1.0 - t * t)
    mv.append(on_face(mx_, 1.6180 - dip, 0.0018))
    mv.append(on_face(mx_, 1.6135 - dip, 0.0018))
for i in range(3):
    mf.append((i * 2, i * 2 + 1, i * 2 + 3, i * 2 + 2))
p.add(mv, mf, 1)
# There WAS a jaw-stubble band here. It is gone twice over: it was built INSIDE the
# skull surface, so the render never showed it, and had it shown it would have been on
# slot 1 — the slot enemy.gd paints with the accent colour — giving every thug a bright
# red or orange chin strap. Dead geometry that would have been wrong if it were alive.
emit("body_head", p, ["mat_trim", "mat_dark"])

# ---------------------------------------------------------------- hair (short crop)
# A grown man's short crop, not the boy's tousle: the cap sits close, the hairline is
# higher and squarer, and the ruffle amplitude is a third of Peter's.
HAIR_TOP = 1.814
p = Part()


def edge_y(a):
    s = math.sin(a)                              # +z is the back of the head
    if s >= 0:
        return 1.690 - 0.052 * s ** 1.1          # nape, cropped high
    return 1.704 + 0.008 * (-s) ** 1.4           # square hairline over the brow


def tuft(a, y):
    """Deterministic ruffle — kept small, this is a number-two crop."""
    return (0.0036 * math.sin(a * 3.0 + 0.7) + 0.0026 * math.sin(a * 5.0 + 2.1)
            + 0.0018 * math.sin(a * 9.0 + 4.4)) * (0.6 + 1.3 * max(0.0, y - 1.720) / 0.08)


def hair_ring(yfn, grow, lift):
    o, ii = [], []
    for k in range(NH):
        a = TAU * k / NH
        y = min(yfn(a), 1.798)
        rx_, rz_, zc_ = head_at(y)
        px, pz = sup(a, 2.2)
        ii.append((px * rx_, y, zc_ + pz * rz_))
        g = grow + max(0.0, tuft(a, y))
        o.append((px * (rx_ * 1.02 + g), y + lift + g * 0.5, zc_ + pz * (rz_ * 1.02 + g)))
    return o, ii


outer, inner = [], []
ro, ri = hair_ring(edge_y, 0.005, 0.0)
outer.append(ro); inner.append(ri)
for y in (1.722, 1.744, 1.764, 1.780, 1.792, 1.798):
    ro, ri = hair_ring(lambda a, y=y: y, 0.007, 0.003)
    outer.append(ro); inner.append(ri)
outer.append([(x * 0.36, HAIR_TOP, z * 0.36 - 0.002) for (x, y, z) in outer[-1]])
inner.append([(x * 0.36, 1.802, z * 0.36 - 0.001) for (x, y, z) in inner[-1]])
p.loft(outer, cap_start=False, cap_end=True)
p.loft(inner, cap_start=False, cap_end=True, flip=True)
i0 = len(outer) * NH + 1
for i in range(NH):
    j = (i + 1) % NH
    p.f.append((i, j, i0 + j, i0 + i))
    p.m.append(0)
emit("body_hair", p, ["mat_dark"])

# ---------------------------------------------------------------- arms
# Sleeved to the wrist. The upper arm carries a deltoid swell at the top — the boy's
# arm was a straight taper, and a straight taper under a shoulder this wide reads as a
# coat hanger.
for side, sx in (("L", 1), ("R", -1)):
    prof = [
        (1.504, 0.026, 0.028, 0.168),
        (1.490, 0.046, 0.046, 0.174),
        (1.472, 0.058, 0.057, 0.180),            # deltoid cap, tucked under the yoke
        (1.444, 0.062, 0.060, 0.186),            # widest point of the arm
        (1.408, 0.061, 0.058, 0.190),
        (1.360, 0.058, 0.055, 0.193),
        (1.300, 0.056, 0.053, 0.196),
        (1.240, 0.054, 0.051, 0.198),
        (1.186, 0.053, 0.050, 0.200),
        (1.148, 0.050, 0.047, 0.201),
        (1.122, 0.044, 0.042, 0.202),
    ]
    ap = resample(prof, 22)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.004, rx, rz, NA) for (y, rx, rz, cx) in ap])
    emit("body_arm" + side, p, ["mat_primary"])

    # forearm: sleeve down to a turned cuff, then bare wrist
    prof = [
        (1.176, 0.052, 0.050, 0.201),
        (1.120, 0.058, 0.056, 0.203),            # elbow of the sleeve
        (1.050, 0.055, 0.053, 0.206),
        (0.985, 0.050, 0.048, 0.208),
        (0.935, 0.045, 0.043, 0.210),
        (0.912, 0.044, 0.042, 0.211),            # cuff band
        (0.896, 0.043, 0.041, 0.211),
        (0.884, 0.033, 0.032, 0.212),            # bare wrist
    ]
    fp = resample(prof, 18)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.004, rx, rz, NA) for (y, rx, rz, cx) in fp],
           mat_fn=lambda s: 1 if 0.893 < fp[s][0] < 0.918 else 0)
    emit("body_forearm" + side, p, ["mat_primary", "mat_glow"])

    # hand — heavy, loosely closed
    prof = [
        (0.890, 0.022, 0.029, 0.212),
        (0.866, 0.021, 0.038, 0.213),
        (0.836, 0.021, 0.045, 0.214),
        (0.800, 0.020, 0.046, 0.215),
        (0.766, 0.018, 0.043, 0.216),
        (0.740, 0.014, 0.033, 0.217),
        (0.726, 0.008, 0.017, 0.217),
    ]
    hp2 = resample(prof, 15)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.008, rx, rz, 18, 2.4) for (y, rx, rz, cx) in hp2])
    trings = []
    for k, (y, r) in enumerate([(0.864, 0.012), (0.840, 0.014), (0.812, 0.013),
                                (0.794, 0.009)]):
        trings.append(ring_xz(sx * (0.212 - 0.011 - k * 0.002), y,
                              -0.024 - k * 0.004, r * 0.75, r, 10))
    p.loft(trings)
    emit("body_hand" + side, p, ["mat_trim"])

# ---------------------------------------------------------------- legs
for side, sx in (("L", 1), ("R", -1)):
    # thigh, heavy trousers with a bit of slack at the knee
    prof = [
        (1.006, 0.084, 0.092, 0.098),
        (0.952, 0.088, 0.097, 0.098),
        (0.896, 0.087, 0.095, 0.098),
        (0.808, 0.082, 0.089, 0.097),
        (0.708, 0.075, 0.082, 0.097),
        (0.610, 0.069, 0.075, 0.096),
        (0.556, 0.066, 0.072, 0.096),
        (0.512, 0.062, 0.067, 0.095),
        (0.482, 0.052, 0.056, 0.095),
    ]
    tp2 = resample(prof, 18)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.0, rx, rz, NL, 2.2) for (y, rx, rz, cx) in tp2])
    emit("body_thigh" + side, p, ["mat_secondary"])

    # shin: calf, then the trouser breaks over the boot
    prof = [
        (0.582, 0.062, 0.068, 0.095),
        (0.520, 0.063, 0.070, 0.095),
        (0.452, 0.065, 0.078, 0.095),            # calf
        (0.380, 0.061, 0.074, 0.095),
        (0.300, 0.055, 0.065, 0.095),
        (0.228, 0.050, 0.057, 0.095),
        (0.192, 0.052, 0.059, 0.095),            # trouser break, slight bunch
        (0.170, 0.049, 0.054, 0.095),
    ]
    sp = resample(prof, 18)
    p = Part()
    p.loft([ring_xz(sx * cx, y, 0.002, rx, rz, NL, 2.2) for (y, rx, rz, cx) in sp])
    emit("body_shin" + side, p, ["mat_secondary"])

    # work boot: high ankle collar, blunt toe, thick lugged sole on slot 1
    # Work boot. The upper's TOP EDGE has to fall monotonically from the shaft to the
    # toe: the first pass let it ramp steeply out of a tall heel and the profile read
    # as an elf shoe. (z, rx, ry, cy); the top of each ring is cy + ry.
    boot = [
        (0.086, 0.054, 0.052, 0.136),            # shaft top 0.188, under the trouser break
        (0.064, 0.059, 0.060, 0.122),            # 0.182
        (0.034, 0.064, 0.064, 0.104),            # 0.168, instep
        (-0.012, 0.067, 0.050, 0.078),           # 0.128
        (-0.062, 0.068, 0.041, 0.062),           # 0.103
        (-0.112, 0.065, 0.036, 0.052),           # 0.088
        (-0.154, 0.057, 0.031, 0.046),           # 0.077
        (-0.178, 0.035, 0.025, 0.040),           # 0.065, blunt toe cap
    ]
    shp = resample(boot, 17)
    p = Part()
    rings = []
    for (z, rx, ry, cy) in shp:
        r = ring_xy(sx * 0.095, cy, z, rx, ry, 20, 2.8)
        rings.append([(px, max(py, 0.032), pz) for (px, py, pz) in r])
    p.loft(rings)
    srings = [ring_xy(sx * 0.095, 0.0175, z, rx + 0.005, 0.0175, 20, 5.0)
              for (z, rx, ry, cy) in shp]
    p.loft(srings)
    p.rot_y(sx * math.radians(-7), sx * 0.095, 0.03)
    emit("body_boot" + side, p, ["mat_dark"])

# ------------------------------------------------- exact height correction
# Height is MEASURED, then corrected. The hair adds a few unpredictable millimetres on
# top of the skull; the pivots take the same factor, which keeps the rig glued to the
# geometry instead of drifting a centimetre off every joint.
_top = max((ob.matrix_world @ v.co).z for ob in objs.values() for v in ob.data.vertices)
K = HEIGHT / _top
for ob in objs.values():
    for v in ob.data.vertices:
        v.co *= K
SS = S * K
print("HEIGHT CORRECTION:", round(_top, 4), "->", HEIGHT, "k=", round(K, 5))

# ---------------------------------------------------------------- rig
PIVOTS = {
    "piv_root":      (None, (0.0, 0.0, 0.0)),
    "piv_hips":      ("piv_root", (0.0, Y_HIPS, 0.004)),
    "piv_chest":     ("piv_hips", (0.0, Y_CHEST, -0.002)),
    "piv_neck":      ("piv_chest", (0.0, Y_NECK, 0.004)),
    "piv_head":      ("piv_neck", (0.0, Y_HEAD, 0.004)),
    "piv_reactor":   ("piv_hips", (0.0, 1.345, -0.150)),
    "piv_shoulderL": ("piv_chest", (X_SH, Y_SHOULDER, 0.004)),
    "piv_elbowL":    ("piv_shoulderL", (X_EL, Y_ELBOW, 0.004)),
    "piv_palmL":     ("piv_elbowL", (0.214, 0.818, -0.018)),
    "piv_shoulderR": ("piv_chest", (-X_SH, Y_SHOULDER, 0.004)),
    "piv_elbowR":    ("piv_shoulderR", (-X_EL, Y_ELBOW, 0.004)),
    "piv_palmR":     ("piv_elbowR", (-0.214, 0.818, -0.018)),
    "piv_hipL":      ("piv_hips", (X_HIP, Y_HIPJ, 0.0)),
    "piv_kneeL":     ("piv_hipL", (X_KN, Y_KNEE, 0.002)),
    "piv_ankleL":    ("piv_kneeL", (X_AN, Y_ANKLE, -0.006)),
    "piv_thrusterL": ("piv_ankleL", (X_AN, 0.030, 0.010)),
    "piv_hipR":      ("piv_hips", (-X_HIP, Y_HIPJ, 0.0)),
    "piv_kneeR":     ("piv_hipR", (-X_KN, Y_KNEE, 0.002)),
    "piv_ankleR":    ("piv_kneeR", (-X_AN, Y_ANKLE, -0.006)),
    "piv_thrusterR": ("piv_ankleR", (-X_AN, 0.030, 0.010)),
}
# -Y of each emitter points where its output would go. A thug emits nothing, but the
# axes are authored anyway so a rig bound to him reads the same numbers it reads on a
# suit and needs no special case.
AIM = {
    "piv_palmL": (-0.942, -0.100, -0.321),
    "piv_palmR": (0.942, -0.100, -0.321),
    "piv_thrusterL": (0.0, -1.0, 0.0),
    "piv_thrusterR": (0.0, -1.0, 0.0),
    "piv_reactor": None,                          # -Z out of the chest = identity
}
MESH_PARENT = {
    "body_hips": "piv_hips", "body_jacket": "piv_chest", "body_neck": "piv_neck",
    "body_head": "piv_head", "body_hair": "piv_head",
    "body_armL": "piv_shoulderL", "body_forearmL": "piv_elbowL", "body_handL": "piv_palmL",
    "body_armR": "piv_shoulderR", "body_forearmR": "piv_elbowR", "body_handR": "piv_palmR",
    "body_thighL": "piv_hipL", "body_shinL": "piv_kneeL", "body_bootL": "piv_ankleL",
    "body_thighR": "piv_hipR", "body_shinR": "piv_kneeR", "body_bootR": "piv_ankleR",
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

# Each mesh gets its own origin at its own centre, then is placed so the geometry lands
# back where it was. matrix_parent_inverse is cleared explicitly: it does not survive
# glTF export, and relying on it is how a model looks right in Blender and wrong in game.
for mname, pname in MESH_PARENT.items():
    ob = objs[mname]
    c = sum((ob.matrix_world @ v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
    for v in ob.data.vertices:
        v.co -= c
    ob.parent = emp[pname]
    par = emp[pname].matrix_world
    ob.matrix_parent_inverse.identity()
    ob.location = par.inverted() @ c
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = par.to_quaternion().inverted()
bpy.context.view_layer.update()

# ---------------------------------------------------------------- stats
tris, mn, mx = stats(list(objs.values()))
print("TRIS:", tris)
print("HEIGHT:", round(mx[2] - mn[2], 4), "WIDTH:", round(mx[0] - mn[0], 4),
      "DEPTH:", round(mx[1] - mn[1], 4), "FLOOR:", round(mn[2], 4))
_chin = 1.570 * SS
print("HEAD RATIO: 1 :", round(HEIGHT / (HEIGHT - _chin), 2))
for n in ("piv_palmL", "piv_palmR", "piv_head"):
    print("  ", n, [round(v, 3) for v in emp[n].matrix_world.translation])

os.makedirs(OUT, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "thug.glb"), export_format='GLB',
                          use_selection=False, export_apply=True, export_yup=True,
                          export_cameras=False, export_lights=False)
print("EXPORTED")

if not RENDER:
    raise SystemExit

shot = setup_render(samples=int(os.environ.get("SAMPLES", "96")))
for _l in bpy.data.lights:
    _l.energy *= 0.46
_bg = next(n for n in bpy.context.scene.world.node_tree.nodes if n.type == 'BACKGROUND')
_bg.inputs[1].default_value = 0.42
shot(os.path.join(OUT, "thug-front.png"), (0.0, 6.2, 0.98), (0, 0, 0.98), 100)
shot(os.path.join(OUT, "thug-side.png"), (-6.2, 0.0, 0.98), (0, 0, 0.98), 100)
shot(os.path.join(OUT, "thug-hero.png"), (2.78, 3.84, 1.60), (-0.02, 0.0, 0.96), 85)
if os.environ.get("EXTRA") == "1":
    shot("/tmp/thug-back.png", (0.0, -7.2, 0.98), (0, 0, 0.98), 100)
    shot("/tmp/thug-head.png", (0.36, 1.05, 1.72), (0.0, 0.0, 1.66), 85)
print("DONE")
