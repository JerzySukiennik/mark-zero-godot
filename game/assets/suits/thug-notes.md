# thug.glb — notes for the game programmer

The adult men you fight. A grown male, 1.82 m, in work boots, heavy trousers, a shirt
and a canvas jacket with the hood rolled at the nape. Built procedurally by
`models/thug-build.py` (Blender 4.5, headless) exactly the way `peter.glb` is — lofted
profile rings, flat Principled colours, no textures, no UVs, no armature.

```
/Applications/Blender.app/Contents/MacOS/Blender --background --python models/thug-build.py
```

`RENDER=0` skips the previews, `SAMPLES=n` sets EEVEE quality, `EXTRA=1` adds a back
view and a head close-up to `/tmp`.

## Why he is not the pilot in a different colour

The enemies were `pilot.glb` — a **thirteen-year-old boy** — recoloured, because he was
the only humanoid in the project. Scaling cannot fix that, and the reason is the head:
it is about **1 : 6.4** of stature on a child and **1 : 7.4** on a man, and a uniform
scale multiplies both numbers by the same factor. So every landmark here is authored off
an adult canon from the floor up rather than off the boy's numbers with a multiplier on
top. Measured on the export: head **1 : 7.43**, shoulder span **0.51 m** at the jacket
yoke (the boy is 0.36 m), crotch at 47 % of stature, a neck three quarters the width of
his own jaw. Those RATIOS are the deliverable; 1.82 m is just where they land.

## Facts

| | |
|---|---|
| File | `assets/suits/thug.glb` (GLB, 0.30 MB) |
| Triangles | **17,288** |
| Objects | 17 meshes |
| Pivots | 20 Empties — the full contract hierarchy, same shape as `peter.glb` and `pilot.glb` |
| Height | 1.8200 m exactly, soles on y = 0, x-centre 0.0000 |
| Shoulder span | 0.525 m at the widest (the sleeve at the elbow); depth 0.331 m |
| Head | chin 1.575 m, crown with hair 1.820 m → **1 : 7.43** |
| Up / facing | +Y up, **−Z forward**, **+X is the character's LEFT** |
| glTF extensions | `KHR_materials_specular` only; **no** `extensionsRequired`, so no meshopt and no quantization to strip |
| Emission | **none, anywhere.** See below. |

## Materials and what each surface is

Five Principled BSDFs, contract-named. All **mid-value and neutral on purpose**: the
game repaints every surface at runtime, so a saturated base colour here would only ever
be visible in the previews and would lie about what a thug looks like in the map.

| material | base colour (linear) | rough | what it is |
|---|---|---|---|
| `mat_primary` | 0.283, 0.272, 0.256 | 0.89 | canvas jacket — body, sleeves, forearms, the rolled hood |
| `mat_secondary` | 0.223, 0.232, 0.252 | 0.91 | heavy trousers — hips, thighs, shins |
| `mat_trim` | 0.452, 0.322, 0.256 | 0.74 | skin — face, neck, hands |
| `mat_dark` | 0.074, 0.071, 0.069 | 0.63 | boots, hair, belt, eyes and brows |
| `mat_glow` | 0.470, 0.462, 0.446 | 0.80 | the shirt at the collar and the turned sleeve cuffs. **Emission strength 0** — the name is here only to keep the contract's five |

**No emission is baked in, deliberately.** `enemy.gd::_tint` sets `emission_enabled`,
`emission` and `emission_energy_multiplier` itself, and the enemies were just toned down
for being too bright; a baked emission would stack on top of the value that fixed that
and undo it silently.

Metallic and roughness are authored honestly but the game overrides both (0.10 / 0.72),
so they matter only to these previews.

## Surface indices — READ THIS BEFORE COLOURING HIM

`enemy.gd::_tint` picks the colour per surface with

```gdscript
var pick: Color = spec["trim"] if i % 3 == 1 else spec["body"]
```

so **surface 1 of every mesh gets the accent colour and everything else gets the body
colour**. The material slots below are ordered around that rule, so the accent lands
only on things that should read as an accent:

| mesh | parent pivot | surface 0 → `body` | surface 1 → `trim` |
|---|---|---|---|
| `body_jacket` | `piv_chest` | jacket + hood | shirt at the collar |
| `body_hips` | `piv_hips` | trousers | belt |
| `body_head` | `piv_head` | face | eyes, brows, mouth |
| `body_hair` | `piv_head` | hair | — |
| `body_neck` | `piv_neck` | neck | — |
| `body_armL/R` | `piv_shoulderL/R` | sleeve | — |
| `body_forearmL/R` | `piv_elbowL/R` | sleeve | turned cuff |
| `body_handL/R` | `piv_palmL/R` | hand | — |
| `body_thighL/R` | `piv_hipL/R` | trousers | — |
| `body_shinL/R` | `piv_kneeL/R` | trousers | — |
| `body_bootL/R` | `piv_ankleL/R` | whole boot | — |

**The boots are deliberately one slot.** A sole on its own slot would be surface 1 and
would therefore arrive painted with `spec["trim"]` — a glowing orange sole on the RPG
thug, a white one on the knifer. Anything split onto slot 1 in future has to be
something that looks right in the accent colour.

**Skin is painted too, and there is no way round it from the model side.** `_tint` walks
every `MeshInstance3D` and overrides every surface, so `body_head`, `body_neck` and
`body_handL/R` come out in `spec["body"]` — a grey-blue or olive face. At 10–40 m that
reads as a man in a balaclava and is fine. If you ever want real skin, the one-line fix
lives in the game, not here: skip the override when the source material's
`resource_name` is `mat_trim`. The materials survive the load with their names intact —
the probe below prints them.

## Rig

The **whole** contract hierarchy, including `piv_thrusterL/R`, which a man in boots will
never fire. They exist so `SuitRig.index()` binds to him with no special case, exactly
as on Peter. World positions re-parsed from the **exported** `.glb` by
`tools/probe_thug.gd` (Blender's `matrix_parent_inverse` is cleared in the build script
because it does not survive glTF export):

```
piv_root         ( 0.000, 0.000,  0.000)
 piv_hips        ( 0.000, 0.993,  0.004)
  piv_chest      ( 0.000, 1.174, -0.002)
   piv_neck      ( 0.000, 1.545,  0.004)
    piv_head     ( 0.000, 1.625,  0.004)
   piv_shoulderL (+0.191, 1.477,  0.004)   piv_shoulderR mirrored
    piv_elbowL   (+0.203, 1.136,  0.004)
     piv_palmL   (+0.215, 0.821, -0.018)
  piv_hipL       (+0.098, 0.943,  0.000)
   piv_kneeL     (+0.095, 0.522,  0.002)
    piv_ankleL   (+0.095, 0.098, -0.006)
     piv_thrusterL(+0.095, 0.030, 0.010)
 piv_reactor     ( 0.000, 1.349, -0.150)
```

Emitter axes, measured on the export: `piv_palmL` local −Y = (−0.94, −0.10, −0.32),
`piv_palmR` mirrored, `piv_thrusterL/R` local −Y = (0, −1, 0), `piv_reactor` local −Z out
of the chest. Every other pivot has identity rotation, so a freshly loaded model is the
rest pose. The numbers are the same shape Peter's are, so nothing that reads a rig has to
know which of the two it has.

`piv_ankle` is at **y = 0.098**, not at the floor: he is standing in a work boot with a
sole. Anything that assumes the ankle sits a few centimetres up (Peter's is at 0.080) is
still right; anything that assumes it is at zero was already wrong.

## Things worth knowing when you animate him

- **Joints overlap on purpose.** Each segment runs past its joint and tapers inside its
  neighbour. Roughly 90° at the knee and 100° at the elbow stay closed; past that a seam
  can open.
- **The jacket hem reaches down to y ≈ 0.99, over the top of the hips mesh**, which is
  cut off at 1.03 because nothing above the hem is ever seen. A large chest-vs-hips
  counter-rotation (more than ~25°) will show the hips mesh through the hem.
- The **belt sits below the hem**, low-slung at 0.91–0.96, which is the only place it is
  visible on this silhouette. It is part of `body_hips` and moves with the pelvis.
- **Feet are toed out 7°** in the mesh; `piv_ankle` itself is axis-aligned, so a plain
  X-rotation still swings the leg straight forward.
- **Face detail is geometry, not texture** — eyes, brows and mouth are flat patches on
  the skull using `body_head`'s second material slot, the same trick `peter.glb` uses.
- **The hair is deterministic, not random.** Three offset sine lobes, at a third of
  Peter's amplitude, because this is a number-two crop and not a teenager's tousle.
  Change them and the measured height correction re-normalises him to 1.82 m by itself.
- Keep head yaw under ~55° and pitch under ~35°; the jacket collar swallows the neck's
  base and will clip past that.
- The `scale` column in `EnemyKinds` still applies. At the brute's 1.45 he is **2.64 m**,
  which is the intended read for that row but is worth knowing before anyone tunes it.

## Hooking him up

`scripts/enemy/enemy.gd` still has `const BODY := "res://assets/suits/pilot.glb"`. This
model is a drop-in for it — same pivot names, same hierarchy, same mesh-per-joint split —
but **the constant was not changed**, because no game script was touched for this task.
One line.

## Verified

- Export re-parsed through `SuitLoader.load_suit` by `tools/probe_thug.gd`
  (`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script
  res://tools/probe_thug.gd`): 20 pivots, 17 meshes, height 1.8200, floor 0.0000,
  x-centre 0.0000, **`piv_palmL` at x = +0.2147** (LEFT is +X), emitter axes as above.
- `extensionsRequired` absent — no `EXT_meshopt_compression`, no `KHR_mesh_quantization`,
  so no `gltf-transform dequantize` pass was needed and Godot parses it at runtime.
- `thug-front.png`, `thug-side.png`, `thug-hero.png` at 1200×1200, rendered **and looked
  at**, through four revisions: the first pass had ball-shaped deltoids floating outside
  the jacket, a hood hanging off the back of the neck, the hips mesh poking through the
  jacket hem, and an elf-shoe boot profile. None of that showed in any measurement.
