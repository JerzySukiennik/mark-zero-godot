# ironspider.glb — notes for the game programmer

Peter Parker's Iron Spider: **deep-crimson and navy-black** nanotech armour with narrow
gold trim, four stowed spider legs, web shooters. Built procedurally by `models/ironspider-build.py` (Blender 4.5, headless), to
the same contract as the Mark suits plus the additions below.

```
/Applications/Blender.app/Contents/MacOS/Blender --background --python models/ironspider-build.py
```

`RENDER=0` skips the previews, `SAMPLES=n` sets EEVEE quality, `FACE=1` adds close-ups
in `/tmp`.

## Facts

| | |
|---|---|
| File | `assets/suits/ironspider.glb` (GLB, 1.04 MB) |
| Triangles | **61,760** (contract budget 40k–120k) |
| Objects | 51 meshes — the 37 contract plates + 12 spider-leg segments + 2 finger groups |
| Pivots | 37 Empties |
| Height | 1.7198 m, soles exactly on y = 0 |
| Width / depth | 0.447 m across the pauldrons, 0.432 m including the stowed legs |
| Up / facing | +Y up, **−Z forward**, **+X is the character's LEFT** |
| glTF extensions | `KHR_materials_emissive_strength`, `KHR_materials_specular` — **no** `extensionsRequired`, no meshopt, no quantization, so `GLTFDocument.append_from_buffer` reads it |
| Armature | none |
| Materials | `mat_primary` (deep crimson, metallic 0.80 / rough 0.26), `mat_secondary` (champagne gold, 1.0 / 0.24), `mat_trim` (bright silver, 1.0 / 0.16), `mat_dark` (navy-black armour panel, 0.62 / 0.30), `mat_glow` (cyan, emission strength 3.2) |

## Palette — and why it is not red-and-gold

The **comics** Iron Spider is red-and-gold. The **film** suit (Infinity War, Endgame, and
unchanged in No Way Home) is not: it is a deep crimson body carrying large near-black
**navy** armour panels, with gold only as narrow trim. Sampled straight off reference
frames — a daylight full-body plate and a lit turntable of the torso:

| | sampled on film | authored albedo (linear) | authored albedo (sRGB) |
|---|---|---|---|
| `mat_primary` crimson | `#7c2e2e` … `#692934` | `(0.165, 0.0062, 0.0125)` | ≈ `#6E1119` |
| `mat_dark` navy-black | `#0c171d` … `#12202b` | `(0.0165, 0.0215, 0.0380)` | ≈ `#222837` |
| `mat_secondary` gold | `#bfb29a` (lit bracer) | `(0.400, 0.302, 0.158)` | ≈ `#AC9877` |
| `mat_glow` lens | cyan-white | emit `(0.12, 0.62, 1.0)` × 3.2 | — |

The dark panels are **blue-biased, never neutral black** (B > G > R in every sample); that
is what makes them read as navy in daylight and as black in shadow, which is exactly how
the suit behaves on screen. The authored values sit a touch below the screen values on
purpose: `SuitLoader` clamps roughness to 0.34 and floors `metallic_specular`, so the game
lifts them again. Do not pre-brighten.

**Where each colour sits**

- **Crimson** (`mat_primary`): mask/helmet, chest, abdomen, gauntlets, palms, fingers, boots.
- **Navy-black** (`mat_dark`): pauldrons, collars, biceps, back, ribs, pelvis, thighs, shins,
  ears, the helmet crest, the brow flicks, the chest emblem — *and* the inner surface of
  every plate, which is what you see in the gaps and what makes the suit read as nanotech
  rather than as a costume. This is now the largest area on the model, by design.
- **Gold** (`mat_secondary`): forearm bracers (the web shooters — the one large gold mass
  on the film suit), elbows, knees, belts, and the four spider legs. Nothing else.
- **Silver** (`mat_trim`): the web-shooter housings on the gauntlets.
- **Cyan** (`mat_glow`): eye lenses, emblem core, palm and boot emitters, web-shooter ports.

*Previously: gold covered the chest, collars, pauldrons, forearms, elbows, knees, shins,
belts and the mask's brows, and red covered everything else — the comics scheme. Corrected
2026-09-19 against film reference.*

## It is a shell, not a statue

Every enclosing plate has an outer skin, an **inner cavity** and rims. That is what lets
`peter.glb` stand inside it, and it is checked, not assumed — see the bottom of this file.

## Rig

World positions in the rest pose, straight out of the exported `.glb` (Godot's own probe,
`tools/probe_newsuits.gd`). **+X is LEFT**: `piv_palmL` is at positive x.

```
piv_root        ( 0.000, 0.000,  0.000)
 piv_hips       ( 0.000, 0.906,  0.002)
  piv_chest     ( 0.000, 1.057, -0.002)
   piv_neck     ( 0.000, 1.361,  0.004)
    piv_head    ( 0.000, 1.431,  0.004)
    piv_faceplate(0.000, 1.372, -0.020)   nanotech recede, see below
   piv_shoulderL(+0.129, 1.314, 0.004)    piv_shoulderR mirrored
    piv_elbowL  (+0.144, 1.075, 0.004)
     piv_palmL  (+0.158, 0.830, -0.006)   repulsor emitter
      piv_fingersL(+0.160, 0.760, -0.006) the web-shooting gesture
      piv_websL (+0.146, 0.862, -0.032)   web emitter
   piv_legA1..A3 / B / C / D               four spider legs, see below
  piv_hipL      (+0.069, 0.822,  0.000)
   piv_kneeL    (+0.067, 0.471,  0.002)
    piv_ankleL  (+0.067, 0.130, -0.004)
     piv_thrusterL(+0.067, 0.014, -0.052)
 piv_reactor    ( 0.000, 1.235, -0.128)
```

### Emitter axes (measured on the export, not in Blender)

| pivot | local −Y points | meaning |
|---|---|---|
| `piv_palmL` | (−0.942, −0.100, −0.321) | repulsor, straight out of the palm |
| `piv_palmR` | (+0.942, −0.100, −0.321) | mirrored |
| `piv_websL/R` | (0.000, −0.978, −0.208) | web, out past the fingertips, 12° forward of the forearm |
| `piv_thrusterL/R` | (0.000, −1.000, 0.000) | boot jet, straight down |
| `piv_reactor` | local **−Z** = (0, 0, −1) | out of the chest |

If you ever re-author these: Blender's glTF exporter conjugates the Y-up conversion into
every node's rotation, so Blender's local **−Z** is what arrives as glTF's local **−Y**.
Aiming Blender's own −Y puts the repulsor out of the back of the hand. It did, once.

## Plates

The 37 contract names, all present, each its own object with its origin at its own centre:

```
bootL bootR thrusterL thrusterR shinL shinR kneeL kneeR
thighL thighR pelvis beltL beltR abdomen
chest ribL ribR back reactor collarL collarR
pauldronL pauldronR bicepL bicepR elbowL elbowR
forearmL forearmR gauntletL gauntletR palmL palmR
earL earR helmet faceplate
```

Plus, beyond the 37: `legA1 legA2 legA3 … legD3` (12) and `fingersL fingersR` (2).

- **`reactor`** is not an arc reactor. It is the suit's spider emblem — a body, eight
  swept legs and a glowing core — laid on the chest surface in navy-black so it reads
  against the crimson chestplate, with a `mat_glow` core at `piv_reactor`.
- **`faceplate`** carries the eyes: a black rim, a large cyan-lit lens and a hotter core, each
  projected onto the mask surface. The lenses deliberately stop short of the mask's
  silhouette; pushed out to the edge the relief vanishes into the curvature and the mask
  tears through them.
- **`helmet`** also carries the dorsal crest, the dark neck seal and the crown plug.
- **`gauntletL/R`** carry the web-shooter housing (silver) with a small emissive port.

### Faceplate mechanism

Nanotech, like the Mark 50: it does not hinge. `piv_faceplate` sits at the collar centre
(0, 1.372, −0.020); dissolve `faceplate` along a shader from the chin upward and sink it
into the collar. The helmet underneath is a complete closed mask, so removing the
faceplate leaves a finished dark head rather than a hole.

## The four spider legs

Chains of three segments, all four parented to `piv_chest`. Segment lengths: A/B
0.100 / 0.200 / 0.240 m, C/D 0.092 / 0.184 / 0.220 m. Segment 3 ends in a talon.

**The rest pose IS the stowed pose** — folded flat on the upper back, tips down by the
waist — and deploying is a **pure rotation** of the same pivots. Nothing translates.

Directions below are in the same form `SuitRig.POSES` already speaks: `dir` is where the
segment points expressed in its **parent's** frame, in game axes.

```
DEPLOY
  legA  A1 (+0.620, +0.620, +0.480)  A2 (+0.540, -0.393, +0.740)  A3 (+0.041, -0.906, -0.423)
  legB  B1 (-0.620, +0.620, +0.480)  B2 (-0.540, -0.393, +0.740)  B3 (-0.041, -0.906, -0.423)
  legC  C1 (+0.720, +0.300, +0.620)  C2 (+0.501, -0.304, +0.808)  C3 (+0.127, -0.950, -0.287)
  legD  D1 (-0.720, +0.300, +0.620)  D2 (-0.501, -0.304, +0.808)  D3 (-0.127, -0.950, -0.287)

STOW (the authored rest — feed these back to re-fold)
  legA  A1 (+0.550, +0.820, +0.150)  A2 (+0.109, +0.733, +0.672)  A3 (+0.017, -0.994, +0.062)
  legB  B1 (-0.550, +0.820, +0.150)  B2 (-0.109, +0.733, +0.672)  B3 (-0.017, -0.994, +0.062)
  legC  C1 (+0.550, +0.700, +0.180)  C2 (+0.102, +0.619, +0.774)  C3 (+0.014, -0.993, +0.101)
  legD  D1 (-0.550, +0.700, +0.180)  D2 (-0.102, +0.619, +0.774)  D3 (-0.014, -0.993, +0.101)
```

Deploy in 0.45 s, root segment first with 0.05 s between legs (A, B, C, D), ease-out with
a small overshoot on segment 3 so the talons snap. Retract in 0.30 s, tips first, no
overshoot. Upper pair (A/B) reaches past the shoulders, lower pair (C/D) sweeps wider and
lower — that split is what makes four legs read as four rather than as a bundle.

## The nanotech suit-up

### `order` — the 37 plates in the order they land

```
reactor
chest  back  ribL ribR  abdomen  collarL collarR
pelvis  beltL beltR  thighL thighR  kneeL kneeR  shinL shinR  bootL bootR  thrusterL thrusterR
pauldronL pauldronR  bicepL bicepR  elbowL elbowR  forearmL forearmR
gauntletL gauntletR  palmL palmR
earL earR  helmet  faceplate
```

`legA1 legA2 legA3 … legD3` extrude out of `back` between the shin and the pauldron
group; `fingersL/R` land with `palmL/R`.

### `origin` — `reactor`

This suit does not get bolted on and nothing flies in from across the room. Every piece
pours out of the chest emblem: collapse each plate to a point at `piv_reactor`, scaled to
about 0.02, and animate position and scale outward along the body surface to its final
transform. The path should hug the body (interpolate through a mid-point pushed 6–8 cm
along the plate's own outward normal) rather than cutting across the torso.

### `duration` — 1.25 s

Chest group 0.00–0.35 s, legs and pelvis 0.20–0.65 s, arms 0.45–0.90 s, hands 0.75–1.00 s,
head 0.85–1.15 s, `faceplate` last, 1.05–1.25 s. Overlap is the point; a strictly
sequential version reads as a machine assembling a doll.

### How it should feel

Fast and *eager*, not ceremonial. The Mark suits are machinery closing around a man; this
one is alive and slightly ahead of him. Plates should arrive with a tiny overshoot and
settle in about 60 ms, the gold going on a frame before the red under it so the chest
flashes gold as it forms. No gantry clank: a rising liquid hiss, and the only hard sound
is the faceplate seating. Run the retract at 0.6× speed and in reverse order, and let the
last thing to go be the mask, which should peel back off the face rather than dissolve.

## Web-shooting hand pose

`piv_fingersL/R` carry the finger group (the middle pair, plus the creases that read as
the rest). Their local frame is authored for exactly one job:

- local **−Y** runs down the finger,
- local **+X** is the knuckle axis (L: (+0.321, 0, −0.947), R: (+0.321, 0, +0.947)),
- local **+Z** is the palm's outward normal.

So the gesture is **one rotation**:

| joint | rest | web-shooting |
|---|---|---|
| `piv_fingersL/R` | identity | **+95° about local X** (both hands; the mirrored frame makes the sign the same) |
| `piv_palmL/R` | `aim` (−0.942, −0.100, −0.321) | `aim` along the shot direction — the same mechanism `SuitRig` already uses for the repulsor |
| `piv_elbowL/R` | — | `dir` (−0.05, −0.62, −0.78) L / (+0.05, −0.62, −0.78) R, i.e. forearm up and forward |
| `piv_shoulderL/R` | — | `dir` (+0.42, −0.74, −0.53) L / (−0.42, −0.74, −0.53) R |

Fold the fingers over 70 ms with a 0.2 overshoot, hold while the strand is live, release
over 140 ms. Fire the strand from `piv_websL/R` (not from the palm) one frame after the
fingers reach full fold — the gesture should look like it *triggers* the shot.

## Web strand — what to build in Godot

Not a line segment and not a `RibbonTrailMesh`. Build it as an **ImmediateMesh tube
rebuilt per frame** along the flight path, and give it the four properties that make a web
read as a web:

1. **Braid.** Three strands, each an 8-sided tube of radius ≈ 0.012 m, wound around the
   centre line with one full turn every 0.45 m. Offset each strand's phase by 120°. The
   twist is what stops it reading as a pipe; it also gives you free specular sparkle as
   the camera moves.
2. **Taper.** Radius scales 1.0 at the anchor to 0.55 at the wrist, so the far end looks
   anchored and heavy. On release, taper the whole thing to zero from the wrist end
   over 0.12 s rather than deleting the mesh.
3. **Ribs.** Every 0.06 m of arc length, bump all three radii by ×1.35 for two rings. Read
   at speed these become the silk's knots. Cheap, and it is what sells the material.
4. **A bright leading tip.** While the web is in flight, the leading 0.10 m is a separate
   unshaded quad-strip in `mat_glow` white, scaled 1.6×, fading to the strand colour over
   0.08 s after impact. The tip is the thing the eye tracks; without it the shot has no
   direction.

Behaviour:

- **Taut** (the player is being pulled, or the strand is load-bearing): the centre line is
  a straight segment from `piv_websL/R` to the anchor, the braid pitch stretches by up to
  1.4×, the radius thins by up to 0.85×, and a faint emissive ramp runs the length at
  ~3 m/s. It should look like it is *under tension*.
- **Slack** (attached, no load): sag the centre line with a catenary, `sag = 0.14 *
  length * (1 − tension)`, sampled at 16 points; let the braid pitch relax back to 1.0 and
  add a low-amplitude sine wobble (2 cm, 1.8 Hz) that damps out over a second.
- **In flight**: interpolate the centre line over 4–6 frames with the tip leading, so the
  strand is drawn as it extends rather than appearing whole. Length ≤ 28 m; beyond that
  the shot should miss and retract.
- Two strands can be live at once (one per wrist). Cap it there.

Material: base colour near-white (0.86, 0.88, 0.92), roughness 0.55, metallic 0, a little
rim light, and `cull_disabled` so a thin tube seen edge-on does not flicker.

## Verified

- **Export re-parsed, not the Blender scene.** `tools/probe_newsuits.gd` (a copy of
  `probe_rig.gd`) loads the `.glb` through `SuitLoader` and prints every pivot's world
  position and local −Y. 37 pivots, 51 meshes, height 1.7198, floor 0.0000, `piv_palmL`
  at **x = +0.158**, every emitter axis as tabulated above.
- **Godot reads it at runtime**: `GLTFDocument.append_from_buffer` parses it, which the
  probe above exercises. `extensionsRequired` is absent, so no dequantize pass is needed.
- **Peter fits inside it.** `models/ironspider-fit.py` stands `peter.glb` in the shell
  raised by the 0.050 m boot lift, paints him emissive magenta, and renders 13 views
  (12 yaws plus overhead) at 700×700. **0 leaked pixels of 6,370,000.** Earlier passes
  leaked 7,574 — at the throat, the crotch, the instep, the seat and, once the palm shell
  was shortened for the finger pivot, between the fingers. Each was fixed in geometry.
- **Rendered and looked at**: `ironspider-front/side/hero.png` at 1200×1200, plus a
  deployed-legs and folded-hand pose test driven through the numbers in this file.
- **The 2026-09-19 palette change touched nothing but materials.** `tools/probe_rig.gd`
  was run against the old `.glb` and the new one and its output is byte-identical
  (same md5): 37 pivots, same world positions, same emitter axes. Mesh and node counts
  are unchanged (51 / 88), `extensionsRequired` is still absent and accessors are still
  plain float/ushort — no meshopt, no quantization.
