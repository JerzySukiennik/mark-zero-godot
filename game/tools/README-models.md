# The suit models, and why they are stored uncompressed

The five armours and the pilot come from the browser version, where they were built by
Blender scripts (`mk*-build.py` in the old project) and exported with
**`EXT_meshopt_compression`** plus `KHR_mesh_quantization`. That is the right choice for the
web: it took each suit from about 7 MB to about 3 MB, and the browser build shipped a
meshopt decoder to read them.

**Godot supports neither extension.** Both are listed in the files' `extensionsRequired`, so
Godot refuses the file outright.

This cost real time because of how it fails. Godot's importer marks the model `valid=false`,
writes no output resource, and prints **no error at all** — so the obvious reading is that
the import simply did not run. I concluded twice that `--headless --import` skips scene
importers, wrote that into a commit message, and only found the truth when the runtime
loader returned `ERR_PARSE_ERROR` and the glTF header could be read directly. The editor
would have failed in exactly the same way. Headless had nothing to do with it.

## Converting a new model

Any suit exported from Blender with compression must be decoded before it is committed:

```sh
npx --yes @gltf-transform/cli@latest dequantize in.glb out.glb
```

`dequantize` also decodes meshopt on read, so one command clears both. Check it worked:

```sh
python3 -c "
import struct,json,sys
d=open(sys.argv[1],'rb').read(); n=struct.unpack('<I',d[12:16])[0]
print(json.loads(d[20:20+n])['extensionsRequired'])" out.glb
```

`KHR_texture_transform` may remain and is fine — Godot supports it.

Expect the file to roughly double, 3 MB to about 7 MB. That is the price of the models
working at all, and at six models it is not a price worth optimising.

## They are parsed at runtime

`scripts/suit/suit_loader.gd` reads the `.glb` bytes and builds the scene with
`GLTFDocument`, rather than relying on Godot's import step. That means a fresh clone has
suits in it immediately, with no editor pass and no way to forget one. The cost is no
automatic LODs or shadow meshes on the suits, which for six player-carried models is worth
paying.
