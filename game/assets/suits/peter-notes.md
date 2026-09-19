# peter.glb — notes for the game programmer

The boy inside the Iron Spider: 15, 1.60 m, t-shirt, jeans, trainers, dark tousled hair.
Built procedurally by `models/peter-build.py` (Blender 4.5, headless) the same way
`pilot.glb` is — lofted profile rings, flat Principled colours, no textures, no UVs, no
armature.

```
/Applications/Blender.app/Contents/MacOS/Blender --background --python models/peter-build.py
```

`RENDER=0` skips the previews, `SAMPLES=n` sets EEVEE quality, `FACE=1` adds close-ups.

## Facts

| | |
|---|---|
| File | `assets/suits/peter.glb` (GLB, 0.28 MB) |
| Triangles | **16,800** |
| Objects | 17 meshes |
| Pivots | 20 Empties — the full contract hierarchy, same shape as `pilot.glb` |
| Height | 1.6000 m exactly, soles on y = 0 |
| Shoulder span | 0.357 m; depth 0.283 m |
| Up / facing | +Y up, **−Z forward**, **+X is the character's LEFT** |
| glTF extensions | `KHR_materials_specular` only; **no** `extensionsRequired` |
| Materials | `mat_primary` (t-shirt, brick red), `mat_secondary` (jeans, indigo), `mat_trim` (skin), `mat_dark` (hair, shoe uppers, eyes), `mat_glow` (white trainer rubber — **emission strength 0**, it is here only to keep the contract's material names) |

Geometry is authored on the same 1.78 m master profile the pilot uses and scaled at build
time, so the two characters stay proportionally comparable. The exact scale is measured,
not assumed: the tousled hair adds an unpredictable few millimetres, so the script
measures the top of the model and corrects by `k` (currently 0.98698) before rigging, and
the pivots take the same factor.

## Rig

Peter carries the **whole** contract hierarchy, including the two thrusters he will never
fire, so nothing binding a rig to him has to special-case him. World positions from the
exported `.glb` (`tools/probe_newsuits.gd`):

```
piv_root        ( 0.000, 0.000,  0.000)
 piv_hips       ( 0.000, 0.856,  0.004)
  piv_chest     ( 0.000, 1.007, -0.002)
   piv_neck     ( 0.000, 1.311,  0.004)
    piv_head    ( 0.000, 1.380,  0.004)
   piv_shoulderL(+0.129, 1.264,  0.004)   piv_shoulderR mirrored
    piv_elbowL  (+0.144, 1.025,  0.004)
     piv_palmL  (+0.156, 0.770, -0.012)
  piv_hipL      (+0.069, 0.772,  0.000)
   piv_kneeL    (+0.067, 0.421,  0.002)
    piv_ankleL  (+0.067, 0.080, -0.004)
     piv_thrusterL(+0.067, 0.023, 0.007)
 piv_reactor    ( 0.000, 1.153, -0.094)
```

Emitter axes are authored even though Peter emits nothing, so a rig reads the same numbers
on him as on a suit: `piv_palmL` local −Y = (−0.942, −0.100, −0.321), `piv_palmR`
mirrored, `piv_thrusterL/R` local −Y = (0, −1, 0), `piv_reactor` local −Z out of the chest.
Every other pivot has identity rotation, so a fresh model is the rest pose.

Mesh → parent:

| pivot | meshes |
|---|---|
| `piv_hips` | `body_hips` (jeans pelvis) |
| `piv_chest` | `body_shirt` |
| `piv_neck` | `body_neck` |
| `piv_head` | `body_head`, `body_hair` |
| `piv_shoulderL/R` | `body_armL/R` (sleeve + bare upper arm) |
| `piv_elbowL/R` | `body_forearmL/R` |
| `piv_palmL/R` | `body_handL/R` |
| `piv_hipL/R` | `body_jeansL/R` (thigh) |
| `piv_kneeL/R` | `body_shinL/R` |
| `piv_ankleL/R` | `body_shoeL/R` |

This is one split finer than `pilot.glb`, which hangs the whole arm off the shoulder and
the hand off the elbow: Peter has a real forearm mesh on `piv_elbowL/R` and his hands on
`piv_palmL/R`, so elbow and wrist rotations actually deform something. Nothing else in the
hierarchy differs, and the game can swap the two models without touching a pivot name.

## Things worth knowing when you animate him

- **Joints overlap on purpose.** Each segment runs a few centimetres past its joint and
  tapers inside its neighbour. Bends to roughly 90° at the knee and 100° at the elbow stay
  closed; past that the seam can open.
- **The neck belongs to `body_neck`, and the shirt collar swallows its base.** Keep head
  yaw under ~55° and pitch under ~35°.
- **Feet are toed out 7°** in the mesh; `piv_ankle` itself is axis-aligned, so a plain
  X-rotation still swings the leg straight forward.
- **Face detail is geometry, not texture** — eyes, brows and mouth are flat patches on the
  skull using `body_head`'s second material slot. Same trick for `body_shirt` (shirt +
  skin) and `body_armL/R` (sleeve + skin).
- **The hair is deterministic, not random.** Three offset sine lobes ruffle the cap. Change
  the amplitudes in `tuft()` and the height correction will re-normalise him to 1.60 m on
  its own.
- Colours come from material base colour, so restyling his shirt at runtime is one line.
- His hips are deliberately slimmer than the pilot's. They were not, at first, and the
  armour that has to close over them came out pear-shaped and leaked at the seat.

## Standing inside the suit

The game places him inside `ironspider.glb` **raised by 0.050 m** — the thickness of the
boot soles. At that offset, and only at that offset, the shell encloses him completely:
`models/ironspider-fit.py` renders the pair from 13 directions with Peter painted emissive
magenta and counts the pixels that show through. Current result: **0 of 6,370,000**.

If either model is edited, re-run that script before believing the fit. It is quick, it
prints a number, and it caught five separate leaks that all measured fine.

## Verified

- Export re-parsed with `tools/probe_newsuits.gd`: 20 pivots, 17 meshes, height 1.6000,
  floor −0.0000, `piv_palmL` at **x = +0.156** (LEFT is +X), emitter axes as above.
- Loaded through `SuitLoader.load_suit` at runtime — no `extensionsRequired`, so no
  meshopt or quantization to strip.
- `peter-front.png`, `peter-side.png`, `peter-hero.png` at 1200×1200, rendered and looked
  at.
