# 3D model assets (USDZ)

Drop runtime 3D models here as **`<id>.usdz`** and the game picks them up
automatically — no code changes. This is the "swap art behind an id" guarantee
(D-ART-1 / F1-06): gameplay always runs on built-in placeholder primitives, and a
real model replaces the placeholder the moment a file with the matching name is in
the app bundle.

Authoring pipeline: easiest is an **AI text/image→3D** tool that exports **USDZ**
directly (Meshy / Tripo), or model in GLB and convert to USDZ (Blender / online —
no Mac needed). Commit the `.usdz` here. Everything stays in this Git repo — see
"Storage" below. **Full step-by-step + recommended tools + style prompts:
[`docs/tvos/ART_PIPELINE.md`](../../../docs/tvos/ART_PIPELINE.md).**

## File names the game looks for

`ModelLibrary` resolves these ids today (anything not present falls back to a
cute placeholder, so partial art is fine):

| File              | What it is                         | Comes from            |
|-------------------|------------------------------------|-----------------------|
| `bus.usdz`        | Amelia, the hero bus               | hard-coded id `"bus"` |
| `veh_fire.usdz`   | Pim, the fire truck                | `vehicles.json` modelRef |
| `veh_tow.usdz`    | Hux, the tow truck                 | `vehicles.json` modelRef |
| `veh_amb.usdz`    | Bea, the ambulance                 | `vehicles.json` modelRef |
| `veh_heli.usdz`   | Skip, the helicopter               | `vehicles.json` modelRef |

> **Not wired yet:** passenger characters (`passenger_*`) and place props render
> as primitives for now, because the engine animates their faces/arms directly
> (blink, look, wave). Loading a USDZ for them needs a small follow-up so the rig
> still drives the loaded model. The bus + rescue vehicles work today.

## Conventions for a model to drop in cleanly

- **Forward face = +X.** The engine puts eyes/headlights on +X and turns the bus
  so +X faces the camera. Model the front along +X.
- **Origin at the wheels** (y = 0 on the ground), roughly **1.6 × 1.1 × 0.9** units
  for the bus so it matches the placeholder's scale; vehicles ~1.5 wide.
- Keep it **low-poly + baked textures** (tvOS / iPhone GPU budget), **original IP
  only** (no Tayo/Cars/Pixar likeness — see RISKS_AND_DECISIONS D-IP-1).

## Storage

Plain Git is fine for small `.usdz` files. If models get large (rule of thumb
> ~10 MB each, or the repo balloons), switch these binaries to **Git LFS** — they
still live in this GitHub repo, just stored as LFS pointers. Nothing about the
asset workflow moves off GitHub.
