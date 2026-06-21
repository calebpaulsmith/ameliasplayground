# Art pipeline — getting real 3D models into the game (no Mac required)

How to produce **original** USDZ models and drop them into the game. This is the
practical "how" for decision **D-ART-1** (art sourcing) and the rule in
**D-IP-1** (original IP only). The engine already loads any model by id with a
placeholder fallback (see `AmeliaTV/Assets/Models/README.md`), so this doc is
purely about *making the files* — no code changes are needed to use them.

> TL;DR: Use an **AI text/image→3D** tool that **exports USDZ directly** (Meshy or
> Tripo), generate originals from our style prompts, name the file after the id
> (`bus.usdz`, `veh_fire.usdz`, …), commit it under `AmeliaTV/Assets/Models/`, and
> the game uses it. Everything stays in this GitHub repo. None of this needs a Mac.

---

## 1. The style brief (paste into any generator)

Keep every model in one cozy, original look — **no** Tayo / Pixar *Cars* / any
real brand likeness (D-IP-1):

> *Cute low-poly cartoon **<thing>** for a toddler's game, big friendly rounded
> shapes, soft pastel colors, simple baked textures, two large expressive eyes on
> the front windshield, no text or logos, clean topology, game-ready.*

Hard technical rules (so a model drops in without fiddling):

| Rule | Value | Why |
|------|-------|-----|
| **Forward axis** | **+X** | Engine puts eyes/headlights on +X and turns the bus so +X faces the camera. |
| **Origin** | at the **wheels**, y = 0 on the ground | So it sits on the road, not floating/sunk. |
| **Bus size** | ≈ **1.6 × 1.1 × 0.9** units (L×H×W) | Matches the placeholder; camera + face offsets assume it. |
| **Vehicle size** | ≈ 1.5 wide | Matches the rescue-friend placeholders. |
| **Budget** | **low-poly + baked textures** | tvOS / iPhone GPU; keep it light. |
| **File size** | aim **< ~5 MB** each | Stays in plain Git; see LFS note below. |
| **Format** | **USDZ** | Runtime format RealityKit loads on tvOS/iOS. |

If a generated model faces the wrong way or is the wrong scale, fix it once in
Blender (rotate to +X, set origin to the base, scale) and re-export — or tell me
the offset and I can bake a correction into the loader.

---

## 2. Recommended tools (all export USDZ, all work off a Mac)

Pick one; all are browser-based, so Windows/Linux/iPad are fine.

- **Meshy** — best all-rounder; strong textures; **exports USDZ directly**. Good
  first choice for our props/vehicles. (text→3D and image→3D)
- **Tripo** — fastest (~seconds), auto-optimizes topology for game engines,
  **exports USDZ**. Great for iterating on the rescue vehicles.
- **Rodin (Hyper3D)** — highest mesh quality / clean quad topology if you want a
  hero-grade bus you can still edit.
- **Luma Genie** — generous free tier, good for cheap prototyping.
- **Sloyd** — parametric (sliders/toggles) if you'd rather *dial in* a vehicle
  than prompt for it.

**Workflow A (simplest):** generate → choose **USDZ** export → done.

**Workflow B (only got a GLB):** convert GLB→USDZ, no Mac, via either
- **Blender** (free, Windows/Linux): *Import glTF 2.0* → *File ▸ Export ▸ USD
  (.usdz)*; or
- a free online converter (e.g. Convert3D, Meshy's converter, ImageToSTL).

> Image→3D tip: sketch (or AI-image) one consistent reference per character first,
> then feed that image to the 3D tool — you'll get a coherent **cast** instead of
> five unrelated styles.

---

## 3. Names the game looks for

Drop files here → `AmeliaTV/Assets/Models/<name>.usdz`. Wired into both app
targets already; a matching file replaces the placeholder automatically.

| File | Model | Starter prompt (after the style brief above) |
|------|-------|----------------------------------------------|
| `bus.usdz` | Amelia, the hero bus | "…cute school-bus shape, sky-blue body, white roof" |
| `veh_fire.usdz` | Pim, fire truck | "…little fire truck, red, tiny ladder on top" |
| `veh_tow.usdz` | Hux, tow truck | "…friendly tow truck, green, small hook arm at the back" |
| `veh_amb.usdz` | Bea, ambulance | "…tiny ambulance, cream/white, a red cross, gentle look" |
| `veh_heli.usdz` | Skip, helicopter | "…cheerful little helicopter, yellow, rounded cockpit, top rotor" |

> Passenger characters (`passenger_*`) and place props don't load USDZ **yet** —
> the engine hand-animates their faces/arms. Wiring USDZ for them is a small
> follow-up (ask me); the bus + four rescue vehicles work today.

---

## 4. Get it into the build

1. Save the file with the exact id name, e.g. `bus.usdz`.
2. Put it in `AmeliaTV/Assets/Models/`.
3. Commit + push. If you can run Xcode/Simulator, that's the visual check; if not,
   CI confirms it builds and the next TestFlight build will show it on device.
4. No code change. (If it looks rotated/oversized, see §1.)

**Storage:** plain Git is fine while files are small. If models grow past
~10 MB each (or the repo bloats), switch `*.usdz` to **Git LFS** — still in this
GitHub repo, just stored as LFS pointers. Nothing about this workflow leaves
GitHub.

---

## 5. Originality sign-off (don't skip — D-IP-1)

Before any generated model becomes "final art," eyeball it against the rule: it
must **not** resemble Tayo, Pixar *Cars*, or any real vehicle brand/livery. Prompt
for generic cozy shapes; avoid naming real characters or brands in prompts. Record
the decision (who approved, which tool/prompt) in
`docs/tvos/RISKS_AND_DECISIONS.md` under D-ART-1 / D-IP-1.

---

## Sources

- [Best 8 AI 3D Model Generators in 2026](https://www.rapiddirect.com/blog/best-8-ai-3d-model-generators/)
- [Meshy — AI 3D model generator (USDZ export)](https://www.meshy.ai/)
- [7 Best AI 3D Object Generators (June 2026) — Unite.AI](https://www.unite.ai/best-ai-3d-object-generators/)
- [Best AI Tools for 3D Game Assets (2026) — Meshy blog](https://www.meshy.ai/blog/best-ai-tools-for-3d-game-assets)
- [GLB→USDZ online converter — Convert3D](https://convert3d.org/glb-to-usdz)
- [GLB→USDZ converter — Meshy](https://www.meshy.ai/3d-tools/file-converter/glb/to/usdz)
