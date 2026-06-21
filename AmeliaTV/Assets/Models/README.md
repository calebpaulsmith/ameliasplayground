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

| File                    | What it is                    | Comes from               |
|-------------------------|-------------------------------|--------------------------|
| `bus.usdz`              | Amelia, the hero bus          | hard-coded id `"bus"`    |
| `veh_fire.usdz`         | Pim, the fire truck           | `vehicles.json` modelRef |
| `veh_tow.usdz`          | Hux, the tow truck            | `vehicles.json` modelRef |
| `veh_amb.usdz`          | Bea, the ambulance            | `vehicles.json` modelRef |
| `veh_heli.usdz`         | Skip, the helicopter          | `vehicles.json` modelRef |
| `passenger_bear.usdz`   | Pip (the rider)               | `passengers.json` modelRef |
| `passenger_bunny.usdz`  | Lola                          | `passengers.json` modelRef |
| `passenger_frog.usdz`   | Tomas                         | `passengers.json` modelRef |
| `passenger_cat.usdz`    | Mia                           | `passengers.json` modelRef |
| `mom.usdz`              | Mechanic Mom (garage)         | hard-coded id `"mom"`    |
| `place_garage.usdz`     | the home garage district      | `place_<id>` (places.json) |
| `place_stopA.usdz`      | the bus stop                  | `place_<id>` |
| `place_park.usdz`       | the park                      | `place_<id>` |
| `place_school.usdz`     | the school                    | `place_<id>` |
| `place_market.usdz`     | the market                    | `place_<id>` |
| `place_beach.usdz`      | the seaside                   | `place_<id>` |

The whole cast + districts are swappable. A character USDZ replaces the rigged
placeholder wholesale (it carries its own face/pose), so the engine's
blink/look/wave animation simply doesn't apply to it — model the expression in.
A `place_<id>.usdz` replaces that district's primitive landmark + dressing, so
include its own ground/base.

## Conventions for a model to drop in cleanly

- **Vehicles face +X** (bus, rescue friends): the engine puts eyes/headlights on
  +X and turns them so +X faces the camera. **Characters face +Z** (passengers,
  Mom) — their face is on +Z.
- **Origin on the ground** (y = 0): wheels for vehicles, feet for characters, base
  for places.
- **Scale (scene meters):** bus ≈ **1.6 × 1.1 × 0.9**, vehicles ~1.5 wide,
  characters ~1.2 tall, place landmarks a few meters (the placeholder buildings
  are ~2.5–4 m).
- Keep it **low-poly + baked textures** (tvOS / iPhone GPU budget), **original IP
  only** (no Tayo/Cars/Pixar likeness — see RISKS_AND_DECISIONS D-IP-1).

## Storage

Plain Git is fine for small `.usdz` files. If models get large (rule of thumb
> ~10 MB each, or the repo balloons), switch these binaries to **Git LFS** — they
still live in this GitHub repo, just stored as LFS pointers. Nothing about the
asset workflow moves off GitHub.
