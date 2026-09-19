"""MARK ZERO — `ironspider.glb`: the Iron Spider suit.

    /Applications/Blender.app/Contents/MacOS/Blender --background --python models/ironspider-build.py

Deep-crimson / navy-black nanotech armour with gold trim, 1.72 m, built to the same
contract as the Mark suits:
spec space (+Y up, faces -Z, +X is the character's LEFT), one Empty per joint, every
plate a separate object with its origin at its own centre, no armature.

Two things are specific to this suit:

* **It is a shell, not a statue.** Every enclosing plate is built with real thickness —
  an outer skin, an inner cavity and rims — so `peter.glb` can stand inside it and the
  fit can be MEASURED (`models/ironspider-fit.py`) instead of eyeballed. The cavity
  radii below are Peter's own profile radii plus clearance; that is why they look
  oddly specific.
* **Four spider legs** stow flat on the upper back. They are three-segment chains
  parented to `piv_chest`; the rest pose IS the stowed pose, and the deployed pose is
  a pure rotation of the same pivots (angles in `ironspider-notes.md`).
"""

import bpy, math, os, sys
from mathutils import Vector, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from _modellib import (Part, TAU, resample, ring_xz, ring_xy, arc_xz, sup, lerp, mat,
                       build_object, wipe, empty, aim_quat, frame_quat, stats, setup_render, B,
                       plate, dome, box, A_LEFT, A_BACK, A_RIGHT, A_FRONT)

OUT = os.path.abspath(os.path.join(HERE, "..", "assets", "suits"))
RENDER = os.environ.get("RENDER", "1") == "1"

HEIGHT = 1.72
LIFT = 0.050        # how far Peter's soles sit above the ground inside the boots

R = math.radians

# ---------------------------------------------------------------- joints
# Peter's joints (peter-build.py, master profile x 0.887174) plus LIFT. The armour's
# pivots sit on the WEARER's joints; that is the whole point of a suit.
Y_HIPS, Y_CHEST, Y_NECK, Y_HEAD = 0.906, 1.057, 1.361, 1.431
Y_SHOULDER, X_SH = 1.314, 0.129
Y_ELBOW, X_EL = 1.075, 0.144
Y_PALM, X_PALM = 0.830, 0.158
Y_HIPJ, X_HIP = 0.822, 0.069
Y_KNEE, X_KN = 0.471, 0.067
Y_ANKLE, X_AN = 0.130, 0.067
Y_REACTOR, Z_REACTOR = 1.235, -0.128

wipe()

# --------------------------------------------------------------- materials
# Metallic 0.9+ with roughness under 0.35 is what reads as metal under an environment
# map; plastic is what a low metallic and a flat roughness give you.
# FILM PALETTE (Infinity War / Endgame), sampled off reference frames, not invented:
# the suit is a DEEP CRIMSON body carrying large near-black NAVY armour panels, with
# gold only as narrow trim. It is not the comics' red-and-gold. Sampled albedos from a
# daylight frame: red #7c2e2e-#692934, dark panels #0c171d-#12202b (blue-biased, never
# neutral black), bracer gold #bfb29a (pale champagne, low saturation), lenses cyan.
# Authored a touch below the screen values on purpose: SuitLoader clamps roughness to
# 0.34 and floors metallic_specular, so the game lifts these again.
mat("mat_primary", (0.165, 0.0062, 0.0125), 0.26, metal=0.80, spec=0.6)  # deep crimson
mat("mat_secondary", (0.400, 0.302, 0.158), 0.24, metal=1.0, spec=0.6)   # restrained champagne gold
mat("mat_trim", (0.420, 0.440, 0.480), 0.16, metal=1.0, spec=0.6)        # bright silver
mat("mat_dark", (0.0165, 0.0215, 0.0380), 0.30, metal=0.62, spec=0.55)   # navy-black armour panel
# The lenses read cyan-white on film, not white. Emission is authored so the RED channel
# stays well under 1.0 after the strength multiply (0.12 x 3.2 = 0.38): push it past one
# and all three channels clip, the hue is gone and the lens tone-maps to flat paper white.
# Measured: at emit R 0.30 the lens centre still sampled #ffffff in the preview render.
mat("mat_glow", (0.14, 0.66, 0.95), 0.28, metal=0.0, spec=0.5,
    emit=(0.12, 0.62, 1.0), emit_strength=3.2)                           # cyan lenses, emitters

RED, GOLD, SILVER, DARK, GLOW = "mat_primary", "mat_secondary", "mat_trim", "mat_dark", "mat_glow"

objs = {}


def P(name, part, mats, smooth=34.0):
    objs[name] = build_object(name, part, mats, smooth)
    return objs[name]


# ---------------------------------------------------------------- torso surface
# (y, rx, rz, zc) — the OUTER surface of the torso armour. Inner cavity = these minus
# the plate thickness, which stays clear of Peter's shirt by 10-15 mm everywhere.
TORSO = [
    (0.900, 0.120, 0.102, 0.004),
    (0.960, 0.128, 0.108, 0.002),
    (1.020, 0.118, 0.100, 0.000),     # waist
    (1.080, 0.122, 0.104, -0.004),
    (1.150, 0.133, 0.112, -0.008),
    (1.215, 0.143, 0.118, -0.010),    # chest
    (1.270, 0.150, 0.114, -0.006),
    (1.320, 0.166, 0.108, 0.000),     # shoulder line
    (1.360, 0.128, 0.096, 0.004),
    (1.386, 0.086, 0.078, 0.004),     # collar
]
TS = resample(TORSO, 40)


def torso_at(y):
    for i in range(len(TS) - 1):
        if TS[i][0] <= y <= TS[i + 1][0]:
            t = (y - TS[i][0]) / (TS[i + 1][0] - TS[i][0])
            return tuple(TS[i][k] + (TS[i + 1][k] - TS[i][k]) * t for k in (1, 2, 3))
    return TS[-1][1:] if y > TS[-1][0] else TS[0][1:]


def torso_z(y, x, out=0.0):
    """Front surface z of the torso at (x, y). Front is -Z."""
    rx, rz, zc = torso_at(y)
    t = min(abs(x) / rx, 0.999)
    return zc - (rz + out) * (1.0 - t ** 2.2) ** (1 / 2.2)


TH = 0.018          # torso plate thickness
FR0, FR1 = R(203), R(337)           # front sector
BK0, BK1 = R(23), R(157)            # back sector

# chest — deep crimson, the broad pectoral shell
p = plate([(1.150, 0.133, 0.112, -0.008), (1.215, 0.143, 0.118, -0.010),
           (1.270, 0.150, 0.114, -0.006), (1.320, 0.166, 0.108, 0.000),
           (1.352, 0.142, 0.100, 0.004)],
          FR0, FR1, TH, nseg=30, nring=22, inner_mat=1, taper=(1.0, 0.72))
P("chest", p, [RED, DARK])

# back — red, and the shelf the spider legs stow against
p = plate([(1.060, 0.122, 0.104, -0.002), (1.180, 0.140, 0.116, -0.008),
           (1.270, 0.150, 0.114, -0.006), (1.325, 0.165, 0.107, 0.000),
           (1.358, 0.138, 0.097, 0.004)],
          BK0, BK1, TH, nseg=30, nring=22, inner_mat=1, taper=(1.0, 0.78))
P("back", p, [DARK, DARK])

# flank ribs — red, they close the gap between chest and back
for side, a in (("L", 0.0), ("R", math.pi)):
    p = plate([(1.060, 0.124, 0.106, -0.002), (1.140, 0.133, 0.112, -0.008),
               (1.215, 0.143, 0.118, -0.010), (1.280, 0.149, 0.112, -0.005)],
              a - R(36), a + R(36), TH, nseg=20, nring=16, inner_mat=1)
    P("rib" + side, p, [DARK, DARK])

# abdomen — red with three segment ribs, the flexible midriff
p = plate([(0.996, 0.117, 0.099, 0.000), (1.060, 0.121, 0.103, -0.002),
           (1.120, 0.130, 0.110, -0.006), (1.168, 0.136, 0.114, -0.008)],
          0, TAU, 0.015, nseg=30, nring=18, closed=True, inner_mat=1)
for y in (1.030, 1.082, 1.132):                  # segment grooves, in dark
    ring = arc_xz(0.0, y, torso_at(y)[2], torso_at(y)[0] + 0.0015,
                  torso_at(y)[1] + 0.0015, R(200), R(340), 22, 2.2)
    ring2 = arc_xz(0.0, y - 0.004, torso_at(y - 0.004)[2], torso_at(y - 0.004)[0] + 0.0015,
                   torso_at(y - 0.004)[1] + 0.0015, R(200), R(340), 22, 2.2)
    p.grid([ring, ring2], mat=1)
P("abdomen", p, [RED, DARK])

# pelvis — red
# These radii are Peter's own hips profile plus 10 mm of clearance and 16 mm of plate.
# They were 20 mm too small at the seat on the first pass, and the fit render showed his
# jeans straight through the armour in a patch the size of a hand.
p = plate([(0.793, 0.123, 0.098, 0.004), (0.820, 0.129, 0.107, 0.004),
           (0.853, 0.129, 0.109, 0.003), (0.893, 0.120, 0.103, 0.002),
           (0.955, 0.106, 0.093, 0.001), (1.006, 0.099, 0.088, 0.000)],
          0, TAU, 0.016, nseg=30, nring=18, closed=True, inner_mat=1)
groin = plate([(0.722, 0.078, 0.062, 0.000), (0.756, 0.096, 0.076, 0.002),
               (0.790, 0.116, 0.094, 0.004), (0.812, 0.126, 0.104, 0.004)],
              R(206), R(334), 0.014, nseg=20, nring=12, inner_mat=1, taper=(0.68, 1.0))
p.add(groin.v, groin.f, 0)
p.m[-len(groin.f):] = groin.m
P("pelvis", p, [DARK, DARK])

# hip belts — gold blocks over the iliac crest
for side, sx in (("L", 1), ("R", -1)):
    p = plate([(0.930, 0.126, 0.107, 0.002), (0.975, 0.128, 0.108, 0.001),
               (1.010, 0.120, 0.101, 0.000)],
              (0.0 if sx > 0 else math.pi) - R(42), (0.0 if sx > 0 else math.pi) + R(42),
              0.016, nseg=18, nring=14, inner_mat=1)
    P("belt" + side, p, [GOLD, DARK])

# collar — gold, neck ring to shoulder
for side, sx in (("L", 1), ("R", -1)):
    a = 0.0 if sx > 0 else math.pi
    p = plate([(1.320, 0.166, 0.108, 0.000), (1.352, 0.146, 0.101, 0.003),
               (1.378, 0.108, 0.086, 0.004), (1.398, 0.080, 0.072, 0.004)],
              a - R(94), a + R(94), 0.015, nseg=24, nring=16, inner_mat=1,
              taper=(1.0, 0.94))
    P("collar" + side, p, [DARK, DARK])

# ---------------------------------------------------------------- shoulders
for side, sx in (("L", 1), ("R", -1)):
    a = 0.0 if sx > 0 else math.pi
    p = plate([(1.244, 0.214, 0.108, -0.002), (1.288, 0.224, 0.112, -0.001),
               (1.330, 0.216, 0.106, 0.001), (1.372, 0.180, 0.096, 0.003),
               (1.396, 0.134, 0.082, 0.004)],
              a - R(84), a + R(84), 0.016, nseg=24, nring=18, inner_mat=1,
              taper=(1.0, 0.70))
    P("pauldron" + side, p, [DARK, DARK])

# ---------------------------------------------------------------- arms
for side, sx in (("L", 1), ("R", -1)):
    # bicep — red tube; cavity clears Peter's upper arm by 12 mm
    p = plate([(1.300, 0.070, 0.070, 0.004, sx * 0.129),
               (1.240, 0.066, 0.066, 0.004, sx * 0.133),
               (1.160, 0.060, 0.060, 0.004, sx * 0.139),
               (1.098, 0.056, 0.056, 0.004, sx * 0.143)],
              0, TAU, 0.014, nseg=20, nring=16, closed=True, inner_mat=1)
    P("bicep" + side, p, [DARK, DARK])

    # elbow — gold cowl
    p = plate([(1.108, 0.058, 0.058, 0.004, sx * 0.143),
               (1.075, 0.061, 0.061, 0.004, sx * 0.144),
               (1.040, 0.058, 0.058, 0.004, sx * 0.145)],
              0, TAU, 0.014, nseg=20, nring=14, closed=True, inner_mat=1)
    P("elbow" + side, p, [GOLD, DARK])

    # forearm — gold, the signature outer-limb gold
    p = plate([(1.048, 0.059, 0.059, 0.004, sx * 0.145),
               (0.990, 0.056, 0.056, 0.004, sx * 0.149),
               (0.930, 0.051, 0.051, 0.004, sx * 0.152),
               (0.884, 0.047, 0.047, 0.004, sx * 0.154)],
              0, TAU, 0.014, nseg=20, nring=16, closed=True, inner_mat=1)
    P("forearm" + side, p, [GOLD, DARK])

    # gauntlet — red wrist cuff, and the web-shooter housing on its inner face
    p = plate([(0.892, 0.048, 0.048, 0.004, sx * 0.154),
               (0.856, 0.046, 0.046, 0.002, sx * 0.156),
               (0.824, 0.042, 0.042, 0.000, sx * 0.157)],
              0, TAU, 0.013, nseg=20, nring=14, closed=True, inner_mat=1)
    hp = Part()
    hp.loft([ring_xz(sx * 0.148, 0.882, -0.030, 0.016, 0.014, 10, 2.6),
             ring_xz(sx * 0.147, 0.862, -0.032, 0.018, 0.016, 10, 2.6),
             ring_xz(sx * 0.146, 0.842, -0.031, 0.015, 0.013, 10, 2.6)], mat=1)
    hp.loft([ring_xz(sx * 0.146, 0.846, -0.033, 0.006, 0.005, 8, 2.0),
             ring_xz(sx * 0.146, 0.836, -0.033, 0.005, 0.004, 8, 2.0)], mat=2)
    p.add(hp.v, hp.f, 0)
    p.m[-len(hp.f):] = hp.m
    P("gauntlet" + side, p, [RED, SILVER, GLOW])

    # palm — red hand shell with a glowing emitter disc in the middle
    # The shell stops at the knuckles. The two fingers that fold for a web-shot are
    # their own object on their own pivot, below.
    prof = [(0.836, 0.042, 0.042, 0.000, sx * 0.157),
            (0.810, 0.038, 0.050, -0.002, sx * 0.158),
            (0.784, 0.036, 0.054, -0.004, sx * 0.159),
            (0.762, 0.033, 0.052, -0.006, sx * 0.160)]
    p = plate(prof, 0, TAU, 0.012, nseg=20, nring=16, closed=True, inner_mat=1, power=2.6)
    # emitter disc on the palm side (medial, toward the body)
    dv, df = [], []
    cx, cy, cz = sx * 0.130, 0.788, -0.008
    seg = 12
    dv.append((cx - sx * 0.004, cy, cz))
    for i in range(seg):
        aa = TAU * i / seg
        dv.append((cx, cy + math.sin(aa) * 0.016, cz + math.cos(aa) * 0.013))
    for i in range(seg):
        df.append((0, 1 + i, 1 + (i + 1) % seg))
    if sx < 0:
        df = [f[::-1] for f in df]
    p.add(dv, df, 2)
    P("palm" + side, p, [RED, DARK, GLOW])

    # fingersL/R — the finger group as ONE piece. Local -Y runs down the finger,
    # local X is the knuckle axis, so folding them into the palm is a single positive
    # rotation about local X and nothing else.
    # Local x is the knuckle axis and local z is the palm normal, so the radii look
    # transposed: rz is what has to cover the WIDTH of his hand.
    # ONE piece, not two bars: split into separate fingers it leaves slots, and from
    # the side his fingertips showed through them. The pair reads as two fingers from
    # the silhouette and the crease, and stays watertight.
    f = Part()
    f.loft([ring_xz(0.0, 0.002, 0.0, 0.0470, 0.0290, 18, 3.2),
            ring_xz(0.0, -0.016, 0.0, 0.0462, 0.0285, 18, 3.2),
            ring_xz(0.0, -0.032, 0.0, 0.0430, 0.0255, 18, 3.2),
            ring_xz(0.0, -0.046, 0.0, 0.0330, 0.0180, 18, 3.2)], mat=0)
    for cx in (-0.024, 0.0, 0.024):   # creases, so it still reads as separate fingers
        f.loft([ring_xz(cx, -0.004, 0.0, 0.0075, 0.0305, 8, 2.6),
                ring_xz(cx, -0.034, 0.0, 0.0065, 0.0270, 8, 2.6)], mat=0)
    P("fingers" + side, f, [RED])

# ---------------------------------------------------------------- legs
for side, sx in (("L", 1), ("R", -1)):
    # thigh — red
    p = plate([(0.920, 0.092, 0.098, 0.000, sx * 0.069),
               (0.860, 0.096, 0.102, 0.000, sx * 0.070),
               (0.800, 0.094, 0.100, 0.000, sx * 0.070),
               (0.700, 0.088, 0.094, 0.000, sx * 0.070),
               (0.600, 0.080, 0.086, 0.000, sx * 0.069),
               (0.522, 0.072, 0.078, 0.002, sx * 0.068)],
              0, TAU, 0.016, nseg=24, nring=18, closed=True, inner_mat=1)
    P("thigh" + side, p, [DARK, DARK])

    # knee — gold cap
    p = plate([(0.530, 0.073, 0.079, 0.002, sx * 0.068),
               (0.480, 0.076, 0.082, 0.000, sx * 0.067),
               (0.430, 0.072, 0.080, -0.002, sx * 0.067)],
              0, TAU, 0.015, nseg=20, nring=14, closed=True, inner_mat=1)
    P("knee" + side, p, [GOLD, DARK])

    # shin — gold
    p = plate([(0.440, 0.071, 0.079, -0.002, sx * 0.067),
               (0.380, 0.068, 0.080, 0.000, sx * 0.067),
               (0.300, 0.062, 0.074, 0.000, sx * 0.067),
               (0.220, 0.056, 0.066, -0.002, sx * 0.067),
               (0.166, 0.053, 0.062, -0.004, sx * 0.067)],
              0, TAU, 0.015, nseg=24, nring=18, closed=True, inner_mat=1)
    P("shin" + side, p, [DARK, DARK])

    # boot — red shell around the foot, lofted over Z slices like a real last
    boot = [   # (z, rx, ry, cy) — cavity = (cy + 0.004, rx - 0.014, ry - 0.016)
        (0.112, 0.052, 0.088, 0.085),          # heel back
        (0.070, 0.062, 0.094, 0.090),
        (0.020, 0.072, 0.090, 0.086),
        (-0.040, 0.074, 0.082, 0.078),
        (-0.100, 0.074, 0.074, 0.070),
        (-0.160, 0.070, 0.064, 0.060),
        (-0.208, 0.060, 0.052, 0.048),
        (-0.244, 0.034, 0.036, 0.032),
    ]
    bp = resample(boot, 20)
    p = Part()
    outer, inner = [], []
    for (z, rx, ry, cy) in bp:
        o = [(px, max(py, 0.0), pz) for (px, py, pz) in
             ring_xy(sx * 0.067, cy, z, rx, ry, 22, 2.8)]
        i = [(px, max(py, 0.050), pz) for (px, py, pz) in
             ring_xy(sx * 0.067, cy + 0.004, z, rx - 0.014, ry - 0.016, 22, 2.8)]
        outer.append(o); inner.append(i)
    p.loft(outer, cap_start=True, cap_end=True)
    p.loft(inner, cap_start=True, cap_end=True, flip=True, mat=1)
    p.rot_y(sx * R(-6), sx * 0.067, 0.02)
    P("boot" + side, p, [RED, DARK])

    # thruster — the sole jet: a dark housing with a glowing disc facing down
    p = Part()
    p.loft([ring_xz(sx * 0.067, 0.030, -0.052, 0.050, 0.086, 16, 2.8),
            ring_xz(sx * 0.067, 0.012, -0.052, 0.046, 0.080, 16, 2.8),
            ring_xz(sx * 0.067, 0.004, -0.052, 0.040, 0.072, 16, 2.8)], mat=0)
    g = Part()
    g.loft([ring_xz(sx * 0.067, 0.006, -0.052, 0.034, 0.062, 16, 2.8),
            ring_xz(sx * 0.067, 0.001, -0.052, 0.030, 0.056, 16, 2.8)], mat=1)
    p.add(g.v, g.f, 1)
    p.rot_y(sx * R(-6), sx * 0.067, 0.02)
    P("thruster" + side, p, [DARK, GLOW])

# ---------------------------------------------------------------- head
# The mask. Crown at HEIGHT; the chin line clears Peter's jaw, and the cavity roof
# clears his hair by ~20 mm.
MASK = [
    (1.392, 0.090, 0.104, -0.006),
    (1.428, 0.112, 0.124, -0.012),    # jaw
    (1.468, 0.128, 0.136, -0.010),    # cheek
    (1.508, 0.135, 0.142, -0.006),    # eye line
    (1.550, 0.136, 0.143, -0.002),
    (1.598, 0.132, 0.139, 0.002),
    (1.646, 0.119, 0.127, 0.004),
    (1.686, 0.093, 0.101, 0.006),
    (1.708, 0.050, 0.058, 0.006),
    (1.7185, 0.014, 0.018, 0.006),
]
MS = resample(MASK, 30)


def mask_at(y):
    for i in range(len(MS) - 1):
        if MS[i][0] <= y <= MS[i + 1][0]:
            t = (y - MS[i][0]) / (MS[i + 1][0] - MS[i][0])
            return tuple(MS[i][k] + (MS[i + 1][k] - MS[i][k]) * t for k in (1, 2, 3))
    return MS[-1][1:] if y > MS[-1][0] else MS[0][1:]


SWELL = 1.018       # the faceplate sits proud of the helmet by ~2 mm


def mask_z(y, x, out=0.0):
    rx, rz, zc = mask_at(y)
    rx, rz = rx * SWELL, rz * SWELL
    t = min(abs(x) / rx, 0.999)
    return zc - (rz + out) * (1.0 - t ** 2.2) ** (1 / 2.2)


# helmet — everything except the face, red, with a dorsal crest
p = plate(MASK, 0, TAU, 0.016, nseg=38, nring=34, closed=True, inner_mat=1, power=2.2)
crest = []
for (y, rx, rz, zc) in resample([(1.552, 0.0, 0.143, -0.002), (1.600, 0.0, 0.139, 0.002),
                                 (1.648, 0.0, 0.127, 0.004), (1.688, 0.0, 0.100, 0.006),
                                 (1.7135, 0.0, 0.040, 0.006)], 12):
    crest.append([(-0.011, y, zc + rz * 0.995), (0.0, y + 0.006, zc + rz * 1.045),
                  (0.011, y, zc + rz * 0.995)])
p.grid(crest, mat=2)
neck = Part()
neck.loft([ring_xz(0.0, 1.262, 0.004, 0.080, 0.076, 16, 2.2),
           ring_xz(0.0, 1.330, 0.004, 0.076, 0.072, 16, 2.2),
           ring_xz(0.0, 1.392, 0.004, 0.070, 0.066, 16, 2.2),
           ring_xz(0.0, 1.430, 0.004, 0.058, 0.055, 16, 2.2)], mat=1)
# A plug over the apex. The closed mask's top rim leaves a ~6 mm hole where the cavity
# radius clamps, and from straight overhead you could see his hair through it.
neck.loft([ring_xz(0.0, 1.704, 0.006, 0.052, 0.058, 14, 2.2),
           ring_xz(0.0, 1.716, 0.006, 0.030, 0.034, 14, 2.2),
           ring_xz(0.0, 1.7198, 0.006, 0.004, 0.005, 14, 2.2)], mat=1)
p.add(neck.v, neck.f, 1)
P("helmet", p, [RED, DARK, DARK])

# ears — small dark audio pods
for side, sx in (("L", 1), ("R", -1)):
    p = Part()
    p.loft([ring_xz(sx * 0.112, 1.512, 0.012, 0.010, 0.026, 10, 2.4),
            ring_xz(sx * 0.122, 1.516, 0.012, 0.012, 0.030, 10, 2.4),
            ring_xz(sx * 0.128, 1.520, 0.012, 0.008, 0.022, 10, 2.4)])
    P("ear" + side, p, [DARK])

# faceplate — the front of the mask, and THE EYES
p = plate(MASK[:8], R(210), R(330), 0.014, nseg=34, nring=28, inner_mat=1,
          swell=(SWELL, SWELL))

EYE = [   # outline of the left lens, (dx, dy) about its own centre — a teardrop whose
          # wide end is outboard and whose point runs in toward the nose
    (0.056, 0.013), (0.045, 0.026), (0.022, 0.031), (-0.003, 0.028),
    (-0.021, 0.018), (-0.034, 0.005), (-0.027, -0.007), (-0.010, -0.016),
    (0.013, -0.021), (0.038, -0.016),
]
# The lenses stop well short of the mask's silhouette on purpose. Pushed out to 95 % of
# the half-width they sit where the surface turns away from the camera, the few
# millimetres of relief vanish into the curvature, and the mask tears through the lens
# in a ragged crescent that looks like a modelling error because it is one.


def eye_outline(sx, scale, n=44):
    pts = [(x * sx, y) for (x, y) in EYE]
    closed = pts + pts[:3]
    out = []
    for i in range(n):
        u = i / n * len(pts)
        k = int(u)
        t = u - k
        q = [closed[(k - 1) % len(pts)], closed[k % len(pts)],
             closed[(k + 1) % len(pts)], closed[(k + 2) % len(pts)]]
        row = []
        for c in (0, 1):
            p0, p1, p2, p3 = (v[c] for v in q)
            t2, t3 = t * t, t * t * t
            row.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        out.append((row[0] * scale, row[1] * scale))
    return out


EYE_TILT = R(-15)          # outer corner lifted; this is what makes them read as eyes
for sx in (1, -1):
    ecx, ecy = sx * 0.050, 1.516
    layers = []
    for (scale, out, m) in ((1.18, 0.0012, 1),    # black rim, sunk into the mask
                            (1.00, 0.0060, 3)):   # the lens itself, lit
        ring = []
        for (dx, dy) in eye_outline(sx, scale):
            ca, sa = math.cos(EYE_TILT * sx), math.sin(EYE_TILT * sx)
            rx_, ry_ = dx * ca - dy * sa, dx * sa + dy * ca
            x, y = ecx + rx_, ecy + ry_
            ring.append((x, y, mask_z(y, x, out)))
        layers.append((ring, m))
    # rim -> lens wall
    p.grid([layers[0][0], layers[1][0]], mat=layers[0][1], close=True, flip=(sx < 0))
    # The lens is filled by shrinking the outline onto the mask surface, not by a flat
    # fan to an averaged centre: the mask bulges forward between the ring points, so a
    # flat fan sinks behind it and the lens renders as a bare outline.
    shells = []
    for (k, (sc, out)) in enumerate(((1.00, 0.0060), (0.62, 0.0092), (0.26, 0.0112))):
        ring = []
        for (dx, dy) in eye_outline(sx, sc):
            ca, sa = math.cos(EYE_TILT * sx), math.sin(EYE_TILT * sx)
            rx_, ry_ = dx * ca - dy * sa, dx * sa + dy * ca
            x, y = ecx + rx_, ecy + ry_
            ring.append((x, y, mask_z(y, x, out)))
        shells.append(ring)
    p.grid(shells, mat=3, close=True, flip=(sx > 0))
    base = len(p.v)
    inner = shells[-1]
    c = (ecx, ecy, mask_z(ecy, ecx, 0.0118))
    p.v.extend(inner); p.v.append(c)
    ci = base + len(inner)
    for i in range(len(inner)):
        j = (i + 1) % len(inner)
        tri = (base + i, base + j, ci)
        p.f.append(tri if sx > 0 else tri[::-1])
        p.m.append(3)
# two short dark brow flicks — ABOVE the lenses and stopping well short of the centre,
# so they read as brows and never as the bridge of a pair of glasses. Black, not gold:
# on the film suit the only thing framing the lenses is the black rim.
for sx in (1, -1):
    rows = []
    for k in range(9):
        t = k / 8
        x = sx * (0.036 + 0.082 * t)
        y0 = 1.566 + 0.016 * t
        w = lerp(0.004, 0.009, t)
        rows.append([(x, y0 + w, mask_z(y0 + w, x, 0.0014)),
                     (x, y0 - w, mask_z(y0 - w, x, 0.0014))])
    p.grid([[r[0] for r in rows], [r[1] for r in rows]], mat=2, flip=(sx < 0))
P("faceplate", p, [RED, DARK, DARK, GLOW])

# ---------------------------------------------------------------- chest emblem
# `reactor` on this suit is the spider emblem: a body, eight legs and a glowing core,
# in navy-black so it reads against the deep crimson chestplate it is laid on — which is
# exactly how the film suit carries it.
p = Part()


def emblem_pt(x, y, out):
    return (x, y, torso_z(y, x, out) - 0.0)


body = []
for i in range(14):
    a = TAU * i / 14
    body.append((math.cos(a) * 0.021, math.sin(a) * 0.034))
ring = [emblem_pt(Y_REACTOR * 0 + dx, 1.238 + dy, 0.004) for (dx, dy) in body]
cen = (0.0, 1.238, torso_z(1.238, 0.0, 0.010))
base = len(p.v)
p.v.extend(ring); p.v.append(cen)
for i in range(len(ring)):
    p.f.append((base + i, base + (i + 1) % len(ring), base + len(ring)))
    p.m.append(0)
# glowing core
gr = [emblem_pt(math.cos(TAU * i / 12) * 0.009, 1.244 + math.sin(TAU * i / 12) * 0.011, 0.008)
      for i in range(12)]
gc = (0.0, 1.244, torso_z(1.244, 0.0, 0.013))
base = len(p.v)
p.v.extend(gr); p.v.append(gc)
for i in range(12):
    p.f.append((base + i, base + (i + 1) % 12, base + 12))
    p.m.append(1)
# eight legs, as thin tapered strips laid on the chest
for sx in (1, -1):
    for (a0d, reach, drop) in ((34, 0.072, 0.030), (13, 0.084, 0.008),
                               (-14, 0.080, -0.018), (-36, 0.066, -0.040)):
        aa = R(a0d)
        knee = (sx * 0.030 + sx * reach * 0.45 * math.cos(aa),
                1.240 + drop * 0.35 + reach * 0.45 * math.sin(aa))
        tip = (sx * 0.026 + sx * reach * math.cos(aa), 1.240 + drop + reach * math.sin(aa) * 0.5)
        pts = [(sx * 0.018, 1.240), knee, tip]
        rows = []
        for k in range(9):
            t = k / 8
            u = 2 * t
            if u <= 1:
                x = lerp(pts[0][0], pts[1][0], u); y = lerp(pts[0][1], pts[1][1], u)
            else:
                x = lerp(pts[1][0], pts[2][0], u - 1); y = lerp(pts[1][1], pts[2][1], u - 1)
            w = lerp(0.0052, 0.0014, t)
            rows.append([emblem_pt(x, y + w, 0.005), emblem_pt(x, y - w, 0.005)])
        p.grid([[r[0] for r in rows], [r[1] for r in rows]], mat=0, flip=(sx < 0))
P("reactor", p, [DARK, GLOW])

# ---------------------------------------------------------------- spider legs
# Four three-segment chains on the upper back. Authored STOWED; `DEPLOY` in the notes
# is the same pivots rotated, nothing translated.
LEG_ROOT = {
    "A": (0.082, 1.300, 0.104), "B": (-0.082, 1.300, 0.104),
    "C": (0.100, 1.168, 0.112), "D": (-0.100, 1.168, 0.112),
}
LEG_LEN = {"A": (0.100, 0.200, 0.240), "B": (0.100, 0.200, 0.240),
           "C": (0.092, 0.184, 0.220), "D": (0.092, 0.184, 0.220)}
# world-space direction of each segment in the STOWED rest pose (spec space)
STOW = {
    "A": [(0.55, 0.82, 0.15), (0.10, -0.985, 0.14), (0.05, -0.99, 0.10)],
    "C": [(0.55, 0.70, 0.18), (0.16, -0.97, 0.16), (0.08, -0.99, 0.10)],
}
STOW["B"] = [(-x, y, z) for (x, y, z) in STOW["A"]]
STOW["D"] = [(-x, y, z) for (x, y, z) in STOW["C"]]
# the deployed pose, same pivots, pure rotation
DEPLOY = {
    "A": [(0.62, 0.62, 0.48), (0.66, -0.10, 0.74), (0.30, -0.82, 0.49)],
    "C": [(0.72, 0.30, 0.62), (0.62, -0.28, 0.73), (0.26, -0.86, 0.44)],
}
DEPLOY["B"] = [(-x, y, z) for (x, y, z) in DEPLOY["A"]]
DEPLOY["D"] = [(-x, y, z) for (x, y, z) in DEPLOY["C"]]

LEG_R = {1: (0.022, 0.018), 2: (0.018, 0.013), 3: (0.013, 0.0035)}


def leg_segment(length, r0, r1, talon):
    """One segment in its pivot's LOCAL frame: it runs down local -Y from the joint."""
    p = Part()
    rows = []
    n = 12
    for k in range(n):
        t = k / (n - 1)
        y = -length * t
        r = lerp(r0, r1, t ** 0.85)
        bulge = 1.0 + 0.45 * math.exp(-((t - 0.04) / 0.10) ** 2)     # knuckle at the joint
        rows.append(ring_xz(0.0, y, 0.0, r * bulge, r * bulge * 1.15, 12, 2.2))
    if talon:
        rows.append([(x * 0.25, -length - 0.022, z * 0.25) for (x, y, z) in rows[-1]])
    p.loft(rows, mat=0)
    # dark collar at the joint
    c = Part()
    c.loft([ring_xz(0.0, -0.004, 0.0, r0 * 1.5, r0 * 1.62, 10, 2.2),
            ring_xz(0.0, -0.020, 0.0, r0 * 1.42, r0 * 1.54, 10, 2.2)], mat=1)
    p.add(c.v, c.f, 1)
    return p


def qdir(d):
    """Spider-leg segments run down their pivot's local -Z (see aim_quat)."""
    return aim_quat(d, '-Z', 'Y')


leg_pivot_local = {}
for leg in ("A", "B", "C", "D"):
    parent_q = Quaternion((1, 0, 0, 0))
    for seg in (1, 2, 3):
        wq = qdir(STOW[leg][seg - 1])
        lq = parent_q.inverted() @ wq
        leg_pivot_local["piv_leg%s%d" % (leg, seg)] = lq
        parent_q = wq
        r0, r1 = LEG_R[seg]
        P("leg%s%d" % (leg, seg),
          leg_segment(LEG_LEN[leg][seg - 1], r0, r1, seg == 3), [GOLD, DARK], smooth=45.0)

# ---------------------------------------------------------------- rig
PIVOTS = {
    "piv_root":      (None, (0.0, 0.0, 0.0)),
    "piv_hips":      ("piv_root", (0.0, Y_HIPS, 0.002)),
    "piv_chest":     ("piv_hips", (0.0, Y_CHEST, -0.002)),
    "piv_neck":      ("piv_chest", (0.0, Y_NECK, 0.004)),
    "piv_head":      ("piv_neck", (0.0, Y_HEAD, 0.004)),
    "piv_faceplate": ("piv_neck", (0.0, 1.372, -0.020)),
    "piv_reactor":   ("piv_hips", (0.0, Y_REACTOR, Z_REACTOR)),
    "piv_shoulderL": ("piv_chest", (X_SH, Y_SHOULDER, 0.004)),
    "piv_elbowL":    ("piv_shoulderL", (X_EL, Y_ELBOW, 0.004)),
    "piv_palmL":     ("piv_elbowL", (X_PALM, Y_PALM, -0.006)),
    "piv_fingersL":  ("piv_palmL", (0.160, 0.760, -0.006)),
    "piv_websL":     ("piv_palmL", (0.146, 0.862, -0.032)),
    "piv_shoulderR": ("piv_chest", (-X_SH, Y_SHOULDER, 0.004)),
    "piv_elbowR":    ("piv_shoulderR", (-X_EL, Y_ELBOW, 0.004)),
    "piv_palmR":     ("piv_elbowR", (-X_PALM, Y_PALM, -0.006)),
    "piv_fingersR":  ("piv_palmR", (-0.160, 0.760, -0.006)),
    "piv_websR":     ("piv_palmR", (-0.146, 0.862, -0.032)),
    "piv_hipL":      ("piv_hips", (X_HIP, Y_HIPJ, 0.0)),
    "piv_kneeL":     ("piv_hipL", (X_KN, Y_KNEE, 0.002)),
    "piv_ankleL":    ("piv_kneeL", (X_AN, Y_ANKLE, -0.004)),
    "piv_thrusterL": ("piv_ankleL", (X_AN, 0.014, -0.052)),
    "piv_hipR":      ("piv_hips", (-X_HIP, Y_HIPJ, 0.0)),
    "piv_kneeR":     ("piv_hipR", (-X_KN, Y_KNEE, 0.002)),
    "piv_ankleR":    ("piv_kneeR", (-X_AN, Y_ANKLE, -0.004)),
    "piv_thrusterR": ("piv_ankleR", (-X_AN, 0.014, -0.052)),
}
# local X = the knuckle axis (perpendicular to both the finger and the palm normal),
# local -Y = down the finger. FOLD is then +95 deg about X, for either hand.
FRAME = {
    "piv_fingersL": ((0.321, 0.0, -0.947), (0.0, 1.0, 0.0), (0.947, 0.0, 0.321)),
    "piv_fingersR": ((0.321, 0.0, 0.947), (0.0, 1.0, 0.0), (-0.947, 0.0, 0.321)),
}
AIM = {
    "piv_palmL": (-0.942, -0.100, -0.321),      # repulsor, straight out of the palm
    "piv_palmR": (0.942, -0.100, -0.321),
    "piv_websL": (0.0, -0.978, -0.208),         # web, out past the fingertips
    "piv_websR": (0.0, -0.978, -0.208),
    "piv_thrusterL": (0.0, -1.0, 0.0),
    "piv_thrusterR": (0.0, -1.0, 0.0),
}
MESH_PARENT = {
    "chest": "piv_chest", "back": "piv_chest", "ribL": "piv_chest", "ribR": "piv_chest",
    "abdomen": "piv_chest", "pelvis": "piv_hips", "beltL": "piv_hips", "beltR": "piv_hips",
    "collarL": "piv_chest", "collarR": "piv_chest",
    "pauldronL": "piv_shoulderL", "pauldronR": "piv_shoulderR",
    "bicepL": "piv_shoulderL", "bicepR": "piv_shoulderR",
    "elbowL": "piv_elbowL", "elbowR": "piv_elbowR",
    "forearmL": "piv_elbowL", "forearmR": "piv_elbowR",
    "gauntletL": "piv_elbowL", "gauntletR": "piv_elbowR",
    "palmL": "piv_palmL", "palmR": "piv_palmR",
    "fingersL": "piv_fingersL", "fingersR": "piv_fingersR",
    "thighL": "piv_hipL", "thighR": "piv_hipR",
    "kneeL": "piv_kneeL", "kneeR": "piv_kneeR",
    "shinL": "piv_kneeL", "shinR": "piv_kneeR",
    "bootL": "piv_ankleL", "bootR": "piv_ankleR",
    "thrusterL": "piv_thrusterL", "thrusterR": "piv_thrusterR",
    "helmet": "piv_head", "earL": "piv_head", "earR": "piv_head",
    "faceplate": "piv_head", "reactor": "piv_reactor",
}

# spider-leg chains hang off the chest
for leg in ("A", "B", "C", "D"):
    PIVOTS["piv_leg%s1" % leg] = ("piv_chest", LEG_ROOT[leg])
    for seg in (2, 3):
        PIVOTS["piv_leg%s%d" % (leg, seg)] = ("piv_leg%s%d" % (leg, seg - 1), None)

emp = {}
for name in PIVOTS:
    emp[name] = empty(name, 0.04)
# Parents first, and every placement goes through the parent's FULL matrix. Subtracting
# world positions instead is what puts a wrist emitter 4 cm out to the side the moment
# its parent carries a rotation.
done = set()
order = []
while len(order) < len(PIVOTS):
    for name, (parent, loc) in PIVOTS.items():
        if name in done:
            continue
        if parent is None or parent in done:
            order.append(name); done.add(name)
for name in order:
    parent, loc = PIVOTS[name]
    e = emp[name]
    e.rotation_mode = 'QUATERNION'
    if parent:
        e.parent = emp[parent]
        e.matrix_parent_inverse.identity()
    if name in leg_pivot_local:
        e.rotation_quaternion = leg_pivot_local[name]
        if loc is None:                       # segments 2 and 3 sit at the far end
            seg = int(name[-1]); leg = name[-2]
            e.location = Vector((0.0, 0.0, -LEG_LEN[leg][seg - 2]))
        else:
            e.location = emp[parent].matrix_world.inverted() @ Vector(B(loc))
    else:
        w = Vector(B(loc))
        e.location = (emp[parent].matrix_world.inverted() @ w) if parent else w
        d = AIM.get(name)
        fr = FRAME.get(name)
        if d or fr:
            want = frame_quat(*fr) if fr else aim_quat(d)
            e.rotation_quaternion = (emp[parent].matrix_world.to_quaternion().inverted()
                                     @ want) if parent else want
    bpy.context.view_layer.update()
bpy.context.view_layer.update()

for leg in ("A", "B", "C", "D"):
    for seg in (1, 2, 3):
        MESH_PARENT["leg%s%d" % (leg, seg)] = "piv_leg%s%d" % (leg, seg)

# Plates carry world-space vertices; spider-leg segments are already authored in their
# pivot's local frame. Both end up with their own origin and a parent that is the only
# thing that moves them.
for mname, pname in MESH_PARENT.items():
    ob = objs[mname]
    par = emp[pname]
    ob.parent = par
    ob.matrix_parent_inverse.identity()
    ob.rotation_mode = 'QUATERNION'
    if mname.startswith("leg") or mname.startswith("fingers"):
        c = sum((v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
        for v in ob.data.vertices:
            v.co -= c
        ob.location = c
        continue
    c = sum((v.co for v in ob.data.vertices), Vector()) / len(ob.data.vertices)
    for v in ob.data.vertices:
        v.co -= c
    pm = par.matrix_world
    ob.location = pm.inverted() @ c
    ob.rotation_quaternion = pm.to_quaternion().inverted()
bpy.context.view_layer.update()

# ---------------------------------------------------------------- stats
tris, mn, mx = stats(list(objs.values()))
print("PLATES:", len([k for k in objs if not k.startswith("leg") and not k.startswith("fingers")]),
      "LEGSEGS:", len([k for k in objs if k.startswith("leg")]),
      "FINGERS:", len([k for k in objs if k.startswith("fingers")]))
print("TRIS:", tris)
print("HEIGHT:", round(mx[2] - mn[2], 4), "WIDTH:", round(mx[0] - mn[0], 4),
      "DEPTH:", round(mx[1] - mn[1], 4), "FLOOR:", round(mn[2], 4))
for n in ("piv_palmL", "piv_palmR", "piv_websL", "piv_websR", "piv_thrusterL",
          "piv_fingersL", "piv_fingersR", "piv_head", "piv_legA3", "piv_legD3"):
    w = emp[n].matrix_world
    bl = w.to_quaternion() @ Vector((0, 0, -1))          # blender -Z == glTF local -Y
    wt = w.translation
    print("  %-14s world(spec)=[%+.3f,%+.3f,%+.3f]  -Y(spec)=[%+.3f,%+.3f,%+.3f]" % (
        n, wt.x, wt.z, -wt.y, bl.x, bl.z, -bl.y))

os.makedirs(OUT, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "ironspider.glb"), export_format='GLB',
                          use_selection=False, export_apply=True, export_yup=True,
                          export_cameras=False, export_lights=False)
print("EXPORTED")

# ---------------------------------------------------------------- deployed pose
# Printed in the SAME form suit_rig.gd already speaks: `dir` is where the segment
# points expressed in its PARENT's frame, in the game's axes. Euler triples would have
# to be re-derived every time the rest roll changed; a direction never does.
def dir_in_parent(pivname, d_world):
    par = emp[PIVOTS[pivname][0]]
    u = par.matrix_world.to_quaternion().inverted() @ Vector(B(d_world))
    return (u.x, u.z, -u.y)          # blender-local -> glTF-local


print("DEPLOY (dir in parent frame, game axes):")
for leg in ("A", "B", "C", "D"):
    row = []
    for seg in (1, 2, 3):
        n = "piv_leg%s%d" % (leg, seg)
        d = dir_in_parent(n, DEPLOY[leg][seg - 1])
        row.append("%s=(%+.3f,%+.3f,%+.3f)" % (n[-2:], d[0], d[1], d[2]))
    print("   leg", leg, " ".join(row))
print("STOW (the authored rest pose, same form — feed these back to re-stow):")
for leg in ("A", "B", "C", "D"):
    row = []
    for seg in (1, 2, 3):
        n = "piv_leg%s%d" % (leg, seg)
        d = dir_in_parent(n, STOW[leg][seg - 1])
        row.append("%s=(%+.3f,%+.3f,%+.3f)" % (n[-2:], d[0], d[1], d[2]))
    print("   leg", leg, " ".join(row))

if not RENDER:
    raise SystemExit

shot = setup_render(samples=int(os.environ.get("SAMPLES", "96")))
shot(os.path.join(OUT, "ironspider-front.png"), (0.0, 5.9, 0.92), (0, 0, 0.92), 100)
shot(os.path.join(OUT, "ironspider-side.png"), (-5.9, 0.0, 0.92), (0, 0, 0.92), 100)
shot(os.path.join(OUT, "ironspider-hero.png"), (2.64, 3.64, 1.52), (-0.02, 0.0, 0.92), 85)
if os.environ.get("FACE") == "1":
    shot("/tmp/is-face.png", (0.30, 1.05, 1.60), (0.0, 0.0, 1.53), 85)
    shot("/tmp/is-back.png", (0.0, -6.4, 1.05), (0, 0, 1.05), 100)
    shot("/tmp/is-back34.png", (-2.2, -3.4, 1.55), (0, 0, 1.15), 85)
print("DONE")
