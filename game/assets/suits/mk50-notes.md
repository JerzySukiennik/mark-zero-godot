# mk50.glb — the Mark L, recoloured

This suit was **recoloured, not rebuilt**. No geometry, no pivot, no axis, no proportion
was touched; the rig probe before and after is identical line for line.

## There is no `models/mk50-build.py`

The five `mk*` suits came from the old three.js prototype. Only three of its builders
survived the move (`mk3-build.py`, `mk42-build.py`, `pilot-build.py` in
`../Niepotrzebne/prototyp-threejs-2026-09-01/models/`); **mk50's generator is gone.** So
mk50 is recoloured by rewriting the exported glTF, with `models/mk50-recolour.py`:

```
python3 models/mk50-recolour.py
```

It reads the pristine `models/mk50-source.glb` and writes `assets/suits/mk50.glb`, so it is
idempotent and the palette can be re-tuned and re-run any number of times without
compounding on its own output. It touches the five embedded baseColor PNGs, the roughness
levels, the metallic factors, and which material nine named primitives point at. Every
accessor and every bufferView carrying mesh data is left where it was — new image blobs are
appended to the end of the binary chunk and the image bufferViews repointed.

## Why the old one looked like a ghost — it was NOT the albedo

The shipped mk50 read as a pale, almost translucent figure, and the obvious reading was
that its albedo was near-white. It was not. Measured off the embedded textures, the old
`mat_primary` baseColor averaged **rgb(80, 11, 16)** — a dark burgundy — and `mat_dark` was
rgb(8, 8, 9). Nothing in the file was pale.

The wash comes from `scripts/suit/suit_loader.gd`:

```gdscript
sm.emission_texture = sm.albedo_texture
sm.emission = Color(1, 1, 1)
sm.emission_energy_multiplier = 0.11
```

`emission_operator` is left at its default, **`EMISSION_OP_ADD`**, and Godot's shader for
ADD is `EMISSION = (emission.rgb + emission_tex) * emission_energy`. With `emission` at
white that is `(1 + tex) * 0.11` — a **flat white lift of ~0.11 linear on every plate**,
barely tinted by the texture at all. The loader's own comment says the opposite ("a red
panel glows red and a gold one gold"); that is what MULTIPLY would do, not ADD.

0.11 linear is about 0.37 in sRGB. A burgundy shell whose reflected radiance sits below
that drowns in it, which is exactly what happened. Proven by rendering the same model four
ways under the arena's own lighting (`tools/probe_why.gd`): with emission disabled, or with
`EMISSION_OP_MULTIPLY`, the *unchanged* old model renders as a rich deep crimson.

**The real fix is one line in the loader** (`sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY`,
or `sm.emission = Color(0, 0, 0)` so the texture alone drives it). That is a game script and
was out of scope here, so the palette below is instead authored to sit **well above** the
white veil: high red with the green and blue channels pushed near zero, and near-full
metallic so the reflection is tinted by the plate rather than by an untinted white specular.
If the loader is ever fixed, re-run the recolour with the levels dropped ~20 %.

## Palette

sRGB as authored into the baseColor textures. The per-pixel micro-variation of the original
textures (scratches, weave) is preserved: each pixel keeps its luminance ratio to the
texture mean and only the colour it varies around is swapped.

| material | sRGB | metallic | rough ×| where it sits |
|---|---|---|---|---|
| `mat_primary` | **206, 16, 22** hot crimson | 0.95 | 0.62 | helmet dome, ribs, back, abdomen, pelvis, belt, biceps, elbows, thighs, knees, shins, boots, thrusters, ears, palms |
| `mat_secondary` | **208, 160, 66** bright gold | 0.97 | 0.72 | faceplate, the whole chest shell, collars, pauldrons, forearms, gauntlets, and the ring accents on belt, knees and pauldrons |
| `mat_trim` | **168, 166, 162** polished silver | 0.93 | 0.88 | the raised sculpted ridges — abdominal segments, rib sweeps, shoulder and forearm edge strips |
| `mat_dark` | **16, 16, 20** near-black | 0.60 | 1.00 | eye recesses, helmet interior, reactor housing, joint gaps |
| `mat_glow` | **120, 216, 246** pale cyan | 0.0 | 0.95 | triangular chest reactor, palm discs, boot jets, the slot lines on chest, pauldrons, forearms, knees and belt |

`mat_glow` keeps `KHR_materials_emissive_strength` with `emissiveFactor` (0.35, 0.86, 1.00)
— cyan, per the contract. Note the loader overwrites emission on every plate anyway, so in
game the cyan you see comes from this material's **albedo**, not its emissive.

`KHR_materials_anisotropy` was removed from `mat_trim` and `mat_secondary`. Godot ignores
the extension, and a brushed-metal sheen is wrong for a seamless nanotech shell in any case.

### Gold placement

The brief is "far more gold than red on the chest, shoulders and forearms, and a strong gold
faceplate", so the **big shell primitive** of `chest`, `pauldronL/R`, `forearmL/R`,
`gauntletL/R` and `collarL/R` was moved off `mat_primary` onto `mat_secondary`. This is
material re-assignment only — no primitive was added, removed or re-indexed, and the probe
shows the change as `mat_primary -> mat_secondary` on exactly those nine meshes and nothing
else.

Be aware this is **more gold than the film**, where the Mark 50's pectorals are red with
gold ribs and gold abdominal segments. It was done deliberately to the brief; to pull it
back, shrink `GOLD_SHELLS` in the recolour script (dropping `pauldronL/R` alone gives red
shoulders over a gold chest, which is closer to the MCU suit) and re-run.

## Not the Iron Spider

`ironspider.glb` is deep crimson over near-black navy with restrained gold. The Mark 50 is
the opposite read: a **bright** scarlet at roughly twice the luminance, with gold as a
major mass rather than an accent, silver ridge lines, and cyan rather than gold glow. Side
by side there is no confusing them.

## Verified

- `tools/probe_mk50.gd` re-parses the **exported** `.glb` through `SuitLoader`. All 21
  pivots, their −Y and −Z axes, the 37 mesh→parent tree and the bounds
  (height/width/depth/floor/x-centre) are **identical before and after**; the only diff in
  the whole probe output is the nine material re-assignments above.
  `piv_palmL.x = +0.2440` still positive, reactor still −Z of the chest.
- `extensionsRequired` is absent. `extensionsUsed` is `["KHR_materials_emissive_strength"]`
  only — **no `EXT_meshopt_compression`, no `KHR_mesh_quantization`**, so no
  `gltf-transform dequantize` pass was needed. See `tools/README-models.md` for why this
  matters.
- 100,598 triangles, inside the contract's 40k–120k. 37 meshes, 58 nodes. 6.59 MB.
- Rendered under the arena's exact lighting and **looked at**, front / side / three-quarter,
  alone and beside `mk3.glb`: `tools/preview_suits.gd`, e.g.
  `Godot --path . res://tools/preview_suits.tscn -- mk50 mk3 hero`.
  Stills: `mk50-front.png`, `mk50-side.png`, `mk50-hero.png` beside this file.

### What is still not right

Under flat frontal light the big smooth thigh and shin shells still carry a faint milky
sheen and read closer to scarlet-pink than to crimson. That is the residue of the loader's
white emission add and cannot be removed from the model — only reduced, which is what the
high-red / near-zero green-and-blue palette does. In three-quarter light, which is how the
suit is normally seen, it does not show.

## Suit-up parameters

There was no `mk50-notes.md` before this one, so the contract's suit-up block had never been
written for this armour. The values below are **proposed, not measured** — they are a
starting point for whoever wires the sequence, not something read off the model.

### `order` — the 37 plates in the order they land

```
reactor  chest  ribL ribR  back  abdomen  pelvis  beltL beltR
collarL collarR  pauldronL pauldronR
bicepL bicepR  elbowL elbowR  forearmL forearmR  gauntletL gauntletR  palmL palmR
thighL thighR  kneeL kneeR  shinL shinR  bootL bootR  thrusterL thrusterR
earL earR  helmet  faceplate
```

### `origin` — `reactor`

Nanotech. Every plate pours out of the chest and runs over the body; nothing flies in from
across the room and no gantry touches it. This is the one armour in the lineup where the
suit-up has no mechanical stage at all.

### `duration` — 0.9 s

The fastest in the lineup, and it should feel it. The Mark III takes its time because arms
bolt it on; the Mark L is already there.

### How it should feel

A liquid running uphill. Plates should not fly and click — they should **spread**, each one
sliding out of the plate before it with no gap and no pause, the seam closing behind them so
the finished shell reads as one surface. Weight the first 0.25 s to the torso, let the limbs
run outward from the shoulders and hips simultaneously, and finish on the faceplate, which
is the only moment of the whole sequence that should read as a distinct *click*. The
retract is the same motion in reverse at 1.3× speed, sinking into the collar — see the
faceplate row of `CONTRACT.md`: no hinge, the game dissolves it along a shader.
