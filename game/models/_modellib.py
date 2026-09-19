"""Shared procedural-modelling helpers for the MARK ZERO builders.

Both `peter-build.py` and `ironspider-build.py` are standalone entry points
(`blender --background --python models/<id>-build.py`); they load this module by
path, so there is still exactly one script per model and no package to install.

Everything here works in SPEC SPACE: +Y up, the character faces -Z, +X is the
character's LEFT.  `B()` converts to Blender space on mesh creation, and the glTF
exporter converts back, which is what makes the contract's axes come out right.
"""

import bpy, bmesh, math
from mathutils import Vector, Quaternion

TAU = math.pi * 2.0

# 0 rad points at +X (the character's LEFT), and the angle runs toward +Z (his BACK).
A_LEFT, A_BACK, A_RIGHT, A_FRONT = 0.0, math.pi * 0.5, math.pi, math.pi * 1.5


def B(p):
    """spec space -> blender space"""
    x, y, z = p
    return (x, -z, y)


def cr(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def resample(profile, m):
    """Catmull-Rom resample of a list of same-length tuples."""
    n = len(profile)
    out = []
    for i in range(m):
        u = i / (m - 1) * (n - 1)
        k = min(int(u), n - 2)
        t = u - k
        row = []
        for c in range(len(profile[0])):
            row.append(cr(profile[max(k - 1, 0)][c], profile[k][c],
                          profile[k + 1][c], profile[min(k + 2, n - 1)][c], t))
        out.append(tuple(row))
    return out


def sup(a, power):
    """unit superellipse direction"""
    c, s = math.cos(a), math.sin(a)
    e = 2.0 / power
    return (math.copysign(abs(c) ** e, c), math.copysign(abs(s) ** e, s))


def ring_xz(cx, cy, cz, rx, rz, n, power=2.0):
    return [(cx + sup(TAU * i / n, power)[0] * rx, cy,
             cz + sup(TAU * i / n, power)[1] * rz) for i in range(n)]


def ring_xy(cx, cy, cz, rx, ry, n, power=2.0):
    return [(cx + sup(TAU * i / n, power)[0] * rx,
             cy + sup(TAU * i / n, power)[1] * ry, cz) for i in range(n)]


def arc_xz(cx, cy, cz, rx, rz, a0, a1, n, power=2.0):
    """Open arc of a superellipse in the XZ plane, n points from a0 to a1."""
    out = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / (n - 1)
        px, pz = sup(a, power)
        out.append((cx + px * rx, cy, cz + pz * rz))
    return out


def lerp(a, b, t):
    return a + (b - a) * t


class Part:
    """A vertex/face/material-index soup in spec space."""

    def __init__(self):
        self.v, self.f, self.m = [], [], []

    # ---------------------------------------------------------- transforms
    def shift(self, dx=0.0, dy=0.0, dz=0.0):
        self.v = [(x + dx, y + dy, z + dz) for (x, y, z) in self.v]

    def scale_about(self, s, cy):
        self.v = [(x * s, cy + (y - cy) * s, z * s) for (x, y, z) in self.v]

    def scale_xyz(self, sx, sy, sz, c=(0.0, 0.0, 0.0)):
        self.v = [(c[0] + (x - c[0]) * sx, c[1] + (y - c[1]) * sy,
                   c[2] + (z - c[2]) * sz) for (x, y, z) in self.v]

    def rot_y(self, ang, cx, cz):
        ca, sa = math.cos(ang), math.sin(ang)
        self.v = [(cx + (x - cx) * ca - (z - cz) * sa, y,
                   cz + (x - cx) * sa + (z - cz) * ca) for (x, y, z) in self.v]

    def rot_x(self, ang, cy, cz):
        ca, sa = math.cos(ang), math.sin(ang)
        self.v = [(x, cy + (y - cy) * ca - (z - cz) * sa,
                   cz + (y - cy) * sa + (z - cz) * ca) for (x, y, z) in self.v]

    def rot_z(self, ang, cx, cy):
        ca, sa = math.cos(ang), math.sin(ang)
        self.v = [(cx + (x - cx) * ca - (y - cy) * sa,
                   cy + (x - cx) * sa + (y - cy) * ca, z) for (x, y, z) in self.v]

    def bounds(self):
        mn = [min(p[i] for p in self.v) for i in range(3)]
        mx = [max(p[i] for p in self.v) for i in range(3)]
        return mn, mx

    def centre(self):
        mn, mx = self.bounds()
        return tuple((mn[i] + mx[i]) * 0.5 for i in range(3))

    # ---------------------------------------------------------- geometry
    def add(self, verts, faces, mat=0):
        o = len(self.v)
        self.v.extend(verts)
        for fc in faces:
            self.f.append(tuple(o + i for i in fc))
            self.m.append(mat)

    def loft(self, rings, cap_start=True, cap_end=True, mat=0, mat_fn=None, flip=False):
        """Closed rings (each the same length) lofted into a tube."""
        n = len(rings[0])
        base = len(self.v)
        for r in rings:
            self.v.extend(r)
        for s in range(len(rings) - 1):
            a, b = base + s * n, base + (s + 1) * n
            mi = mat_fn(s) if mat_fn else mat
            for i in range(n):
                j = (i + 1) % n
                q = (a + i, a + j, b + j, b + i)
                self.f.append(q[::-1] if flip else q)
                self.m.append(mi)
        for cap, idx, sec in ((cap_start, base, 0),
                              (cap_end, base + (len(rings) - 1) * n, len(rings) - 2)):
            if not cap:
                continue
            c = len(self.v)
            r = rings[0] if sec == 0 else rings[-1]
            self.v.append(tuple(sum(p[k] for p in r) / n for k in range(3)))
            for i in range(n):
                j = (i + 1) % n
                tri = (idx + j, idx + i, c) if sec == 0 else (idx + i, idx + j, c)
                self.f.append(tri[::-1] if flip else tri)
                self.m.append(mat_fn(sec) if mat_fn else mat)

    def grid(self, rings, mat=0, mat_fn=None, flip=False, close=False):
        """Open strips (each the same length) stitched into a sheet."""
        n = len(rings[0])
        base = len(self.v)
        for r in rings:
            self.v.extend(r)
        span = n if close else n - 1
        for s in range(len(rings) - 1):
            a, b = base + s * n, base + (s + 1) * n
            mi = mat_fn(s) if mat_fn else mat
            for i in range(span):
                j = (i + 1) % n
                q = (a + i, a + j, b + j, b + i)
                self.f.append(q[::-1] if flip else q)
                self.m.append(mi)
        return base


def shrink(ring, t):
    """Pull a ring `t` metres toward its own centroid (radially)."""
    n = len(ring)
    c = [sum(p[k] for p in ring) / n for k in range(3)]
    out = []
    for (x, y, z) in ring:
        dx, dz = x - c[0], z - c[2]
        d = math.hypot(dx, dz)
        if d < 1e-9:
            out.append((x, y, z))
        else:
            k = max(d - t, d * 0.15) / d
            out.append((c[0] + dx * k, y, c[2] + dz * k))
    return out


def plate(profile, a0, a1, th, nseg=16, nring=None, power=2.2, mat=0, inner_mat=None,
          closed=False, taper=None, swell=None):
    """An ARMOUR PLATE: a sector of a lofted body of revolution, given real thickness.

    `profile` is a list of (y, rx, rz, zc) or (y, rx, rz, zc, cx) in spec space — the
    fifth column lets a limb tube drift sideways as it runs down the arm.  The plate
    spans the angular sector [a0, a1] (or wraps right round, with `closed`) and is `th`
    metres thick, so it has an outer surface, an inner cavity surface and rims.
    Thickness is what makes the poke-through check possible: a solid slug of geometry
    would report every limb inside it as a collision.
    """
    p = Part()
    im = mat if inner_mat is None else inner_mat
    prof = resample(profile, nring or max(4, len(profile) * 3))
    outer, inner = [], []
    for k, row in enumerate(prof):
        y, rx, rz, zc = row[0], row[1], row[2], row[3]
        cx = row[4] if len(row) > 4 else 0.0
        t = k / (len(prof) - 1)
        s = 1.0 if swell is None else lerp(swell[0], swell[1], t)
        rx, rz = rx * s, rz * s
        if closed:
            outer.append(ring_xz(cx, y, zc, rx, rz, nseg, power))
            inner.append(ring_xz(cx, y, zc, max(rx - th, rx * 0.2),
                                 max(rz - th, rz * 0.2), nseg, power))
            continue
        wide = 1.0 if taper is None else lerp(taper[0], taper[1], t)
        aa0 = a0 + (a1 - a0) * (1.0 - wide) * 0.5
        aa1 = a1 - (a1 - a0) * (1.0 - wide) * 0.5
        outer.append(arc_xz(cx, y, zc, rx, rz, aa0, aa1, nseg, power))
        inner.append(arc_xz(cx, y, zc, max(rx - th, rx * 0.2),
                            max(rz - th, rz * 0.2), aa0, aa1, nseg, power))
    if closed:
        # A tube: outer skin, inner cavity, and a rim ring at each open end.
        p.loft(outer, cap_start=False, cap_end=False, mat=mat)
        p.loft(inner, cap_start=False, cap_end=False, mat=im, flip=True)
        n = nseg
        ni = len(outer) * n
        for (row, flip) in ((0, False), (len(outer) - 1, True)):
            a, c = row * n, ni + row * n
            for i in range(n):
                j = (i + 1) % n
                q = (a + i, a + j, c + j, c + i)
                p.f.append(q[::-1] if flip else q)
                p.m.append(mat)
        return p
    p.grid(outer, mat=mat)
    p.grid(inner, mat=im, flip=True)
    n = nseg
    no = 0
    ni = len(outer) * n
    # side rims (the two long edges of the plate)
    for s in range(len(outer) - 1):
        a, b = no + s * n, no + (s + 1) * n
        c, d = ni + s * n, ni + (s + 1) * n
        p.f.append((a, b, d, c)); p.m.append(mat)
        p.f.append((c + n - 1, d + n - 1, b + n - 1, a + n - 1)); p.m.append(mat)
    # end rims
    for (row, flip) in ((0, False), (len(outer) - 1, True)):
        a, c = no + row * n, ni + row * n
        for i in range(n - 1):
            q = (a + i, a + i + 1, c + i + 1, c + i)
            p.f.append(q[::-1] if flip else q)
            p.m.append(mat)
    return p


def dome(cx, cy, cz, rx, ry, rz, seg=14, rings=7, y0=0.0, mat=0, flip=False,
         squash_back=1.0):
    """Half/whole ellipsoid; y0 = -1 gives the full ball, 0 gives the top half."""
    p = Part()
    rows = []
    for r in range(rings + 1):
        v = lerp(math.asin(max(y0, -1.0)), math.pi * 0.5, r / rings)
        yy, rr = math.sin(v), math.cos(v)
        row = []
        for i in range(seg):
            a = TAU * i / seg
            px, pz = sup(a, 2.3)
            zz = cz + pz * rz * rr
            if pz > 0:
                zz = cz + pz * rz * rr * squash_back
            row.append((cx + px * rx * rr, cy + yy * ry, zz))
        rows.append(row)
    p.loft(rows, cap_start=(y0 > -0.999), cap_end=True, mat=mat, flip=flip)
    return p


def box(c, half, mat=0, bevel=0.0):
    """Axis-aligned box, optionally with the vertical edges pulled in (a bevel)."""
    cx, cy, cz = c
    hx, hy, hz = half
    p = Part()
    rows = []
    for (dy, s) in ((-hy, 1.0 - bevel * 2.0), (-hy * 0.55, 1.0), (hy * 0.55, 1.0),
                    (hy, 1.0 - bevel * 2.0)):
        rows.append(ring_xz(cx, cy + dy, cz, hx * s, hz * s, 12, 3.4))
    p.loft(rows, mat=mat)
    return p


# ------------------------------------------------------------------ blender glue

def mat(name, color, rough, metal=0.0, spec=0.5, emit=None, emit_strength=0.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    # Look the shader up by TYPE. Node NAMES are localized, so nodes["Principled BSDF"]
    # is None on a non-English Blender and the whole material silently comes out grey.
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = spec
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m


def build_object(name, part, mats, smooth_angle=40.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([B(v) for v in part.v], [], part.f)
    me.validate()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(bpy.data.materials[m])
    for i, poly in enumerate(me.polygons):
        poly.material_index = min(part.m[i], len(mats) - 1)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = True
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
    except Exception:
        pass
    ob.select_set(False)
    return ob


def wipe():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras,
                bpy.data.worlds):
        for b in list(blk):
            blk.remove(b)


def empty(name, size=0.05):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'PLAIN_AXES'
    e.empty_display_size = size
    bpy.context.collection.objects.link(e)
    return e


def aim_quat(direction):
    """Blender-space quaternion whose local -Y points along `direction` (spec space)."""
    d = Vector(B(direction)).normalized()
    return d.to_track_quat('-Y', 'Z')


def stats(objs):
    tris = 0
    mn, mx = [1e9] * 3, [-1e9] * 3
    for ob in objs:
        ob.data.calc_loop_triangles()
        tris += len(ob.data.loop_triangles)
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
    return tris, mn, mx


# ------------------------------------------------------------------ preview render

def setup_render(samples=96, bg=(0.31, 0.34, 0.39), bg_strength=0.65, ground=True):
    scn = bpy.context.scene
    try:
        scn.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        pass
    if hasattr(scn, "eevee"):
        scn.eevee.taa_render_samples = samples
    scn.render.resolution_x = scn.render.resolution_y = 1200
    scn.render.film_transparent = False
    scn.view_settings.view_transform = 'Standard'
    scn.view_settings.look = 'None'

    world = bpy.data.worlds.new("W")
    scn.world = world
    world.use_nodes = True
    bgn = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bgn.inputs[0].default_value = (*bg, 1)
    bgn.inputs[1].default_value = bg_strength

    if ground:
        bpy.ops.mesh.primitive_plane_add(size=16, location=(0, 0, 0))
        gp = bpy.context.active_object
        gp.data.materials.append(mat("mat_ground", (0.17, 0.18, 0.20), 0.9))

    sun = bpy.data.lights.new("sun", 'SUN')
    sun.energy, sun.angle = 2.6, math.radians(5)
    sun.color = (1.0, 0.96, 0.90)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), 0, math.radians(-145))
    bpy.context.collection.objects.link(so)

    def area(name, loc, energy, size, rot, col=(1, 1, 1)):
        ld = bpy.data.lights.new(name, 'AREA')
        ld.energy, ld.size, ld.color = energy, size, col
        lo = bpy.data.objects.new(name, ld)
        lo.location, lo.rotation_euler = loc, rot
        bpy.context.collection.objects.link(lo)

    area("fill", (2.8, 2.6, 1.7), 220, 3.2, (math.radians(64), 0, math.radians(132)))
    area("rim", (-2.4, -2.8, 2.4), 210, 2.0, (math.radians(118), 0, math.radians(-40)),
         (0.72, 0.82, 1.0))
    area("kick", (-2.9, 2.4, 1.2), 140, 2.4, (math.radians(72), 0, math.radians(-131)),
         (1.0, 0.88, 0.72))

    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scn.camera = cam

    def shot(path, loc, target, lens):
        cam_data.lens = lens
        cam.location = Vector(loc)
        cam.rotation_euler = (Vector(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scn.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("RENDERED", path)

    return shot
