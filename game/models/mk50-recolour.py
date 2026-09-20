#!/usr/bin/env python3
"""Recolour mk50.glb in place — MATERIALS AND TEXTURES ONLY.

There is no `mk50-build.py`: the five mk* suits came from the old three.js prototype
(`../Niepotrzebne/prototyp-threejs-2026-09-01/models/`), and only `mk3-build.py`,
`mk42-build.py` and `pilot-build.py` survived. So mk50 is recoloured by rewriting the
exported glTF rather than regenerated.

WHAT IS TOUCHED
  * the five embedded baseColor PNGs, remapped to a new palette
  * metallicFactor / roughness level per material
  * which material a few named primitives point at (gold moved onto chest, pauldrons,
    forearms, collars)

WHAT IS NOT TOUCHED
  every accessor, every bufferView that carries mesh data, every node, every transform.
  New image blobs are APPENDED to the end of the binary chunk and the image bufferViews
  repointed, so no existing byte offset moves and the rig re-parses identically.

Run:  python3 models/mk50-recolour.py
"""
import io, json, os, struct, sys

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow:  python3 -m pip install Pillow")

HERE = os.path.dirname(os.path.abspath(__file__))
GLB = os.path.join(HERE, "..", "assets", "suits", "mk50.glb")
# The PRISTINE input, kept beside the script so the recolour can be re-tuned and re-run
# any number of times without compounding on its own output. Every run reads SRC and
# writes GLB; never the other way round.
SRC = os.path.join(HERE, "mk50-source.glb")

# ---------------------------------------------------------------- palette
# sRGB bytes, as they are authored into the baseColor texture.
#
# Authored BRIGHT and SATURATED on purpose. suit_loader.gd adds emission with
# EMISSION_OP_ADD and emission = Color(1,1,1), which lands a flat ~0.11 linear WHITE
# lift on every plate regardless of its texture. A dark burgundy reflects less than
# that veil and drowns in it — which is exactly why the shipped mk50 read as a pale
# ghost. Hot crimson and bright gold sit well above the veil and stay saturated.
PALETTE = {
    "mat_primary":   (206,  16,  22),   # hot crimson — the nanotech red
    "mat_secondary": (208, 160,  66),   # bright gold — faceplate, chest, shoulders, arms
    "mat_trim":      (168, 166, 162),   # bright polished silver ridges and edges
    "mat_dark":      ( 16,  16,  20),   # near-black recesses, joints, eye slots
    "mat_glow":      (120, 216, 246),   # cyan slots (contract: mk50 glow is cyan)
}

# Metallic is raised across the board: a partly-dielectric surface answers the sky with
# an UNTINTED white highlight, which desaturates. Near-full metal tints its own
# reflection, which is what keeps crimson reading as crimson.
METALLIC = {
    "mat_primary": 0.95, "mat_secondary": 0.97, "mat_trim": 0.93,
    "mat_dark": 0.60, "mat_glow": 0.0,
}

# Roughness texture levels are scaled down: the Mark 50 is glossy and clean, and the
# Mark III next to it measures 0.13 mean where mk50 measured 0.42.
ROUGH_SCALE = {
    "mat_primary": 0.62, "mat_secondary": 0.72, "mat_trim": 0.88,
    "mat_dark": 1.00, "mat_glow": 0.95,
}

# "far more gold than red on the chest, shoulders and forearms": the big shell primitive
# of these meshes is moved off mat_primary onto mat_secondary. Material re-assignment
# only — no primitive is added, removed or re-indexed.
GOLD_SHELLS = {"chest", "pauldronL", "pauldronR", "forearmL", "forearmR",
               "collarL", "collarR", "gauntletL", "gauntletR"}


def srgb_to_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def recolour(png_bytes, target):
    """Keep the texture's own micro-variation, swap the colour it varies around."""
    im = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    px = im.load()
    w, h = im.size
    # mean luminance of the source, so every pixel becomes a RATIO around it
    tot = 0.0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            tot += 0.2126 * r + 0.7152 * g + 0.0722 * b
    mean = max(tot / (w * h), 1.0)
    out = Image.new("RGB", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            k = (0.2126 * r + 0.7152 * g + 0.0722 * b) / mean
            # a gentle gamma on the ratio keeps scratches readable without smearing
            k = k ** 0.85
            op[x, y] = tuple(min(255, max(0, int(round(t * k)))) for t in target)
    buf = io.BytesIO()
    out.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def scale_rough(png_bytes, k):
    """Scale the glTF roughness channel (G). Metal (B) and R are left alone."""
    im = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    r, g, b = im.split()
    g = g.point(lambda v: min(255, int(round(v * k))))
    buf = io.BytesIO()
    Image.merge("RGB", (r, g, b)).save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def main():
    if not os.path.exists(SRC):
        sys.exit("missing %s — the pristine pre-recolour export" % SRC)
    raw = open(SRC, "rb").read()
    jlen = struct.unpack("<I", raw[12:16])[0]
    assert raw[16:20] == b"JSON"
    j = json.loads(raw[20:20 + jlen])
    bin_off = 20 + jlen + 8
    assert raw[20 + jlen + 4:20 + jlen + 8] == b"BIN\x00"
    blen = struct.unpack("<I", raw[20 + jlen:20 + jlen + 4])[0]
    binary = bytearray(raw[bin_off:bin_off + blen])

    views = j["bufferViews"]
    images = j["images"]
    tex_img = {i: t["source"] for i, t in enumerate(j["textures"])}

    def read_image(idx):
        v = views[images[idx]["bufferView"]]
        o = v.get("byteOffset", 0)
        return bytes(binary[o:o + v["byteLength"]])

    def append_image(idx, data):
        while len(binary) % 4:
            binary.append(0)
        off = len(binary)
        binary.extend(data)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
        images[idx]["bufferView"] = len(views) - 1

    for m in j["materials"]:
        name = m["name"]
        pbr = m["pbrMetallicRoughness"]
        if name in PALETTE and "baseColorTexture" in pbr:
            src = tex_img[pbr["baseColorTexture"]["index"]]
            append_image(src, recolour(read_image(src), PALETTE[name]))
            pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
            print("  %-14s base -> rgb%s" % (name, PALETTE[name]))
        if name in METALLIC:
            pbr["metallicFactor"] = METALLIC[name]
        if name in ROUGH_SCALE and "metallicRoughnessTexture" in pbr:
            src = tex_img[pbr["metallicRoughnessTexture"]["index"]]
            append_image(src, scale_rough(read_image(src), ROUGH_SCALE[name]))
        # anisotropy is a Godot no-op and only muddies a nanotech shell
        if "extensions" in m:
            m["extensions"].pop("KHR_materials_anisotropy", None)
            if not m["extensions"]:
                del m["extensions"]
        if name == "mat_glow":
            m["emissiveFactor"] = [0.35, 0.86, 1.0]

    # gold shells
    mat_by_name = {m["name"]: i for i, m in enumerate(j["materials"])}
    gold = mat_by_name["mat_secondary"]
    prim_mat = mat_by_name["mat_primary"]
    moved = []
    for mesh in j["meshes"]:
        if mesh.get("name") in GOLD_SHELLS:
            for p in mesh["primitives"]:
                if p.get("material") == prim_mat:
                    p["material"] = gold
                    moved.append(mesh["name"])
    print("  gold shells:", ", ".join(sorted(set(moved))))

    used = set(j.get("extensionsUsed", []))
    used.discard("KHR_materials_anisotropy")
    j["extensionsUsed"] = sorted(used)
    j.pop("extensionsRequired", None)

    # ---- rewrite the container
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    while len(binary) % 4:
        binary.append(0)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary))
    out += struct.pack("<I", len(js)) + b"JSON" + js
    out += struct.pack("<I", len(binary)) + b"BIN\x00" + bytes(binary)
    j["buffers"][0]["byteLength"] = len(binary)
    # byteLength lives in the JSON, so the JSON has to be written after it is known
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary))
    out += struct.pack("<I", len(js)) + b"JSON" + js
    out += struct.pack("<I", len(binary)) + b"BIN\x00" + bytes(binary)
    open(GLB, "wb").write(out)
    print("  wrote %s  (%.2f MB)" % (os.path.normpath(GLB), len(out) / 1e6))


if __name__ == "__main__":
    main()
