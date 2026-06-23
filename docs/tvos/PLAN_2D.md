# Amelia's Bus Adventure — 2D (GTA-style) Plan

> **Status:** active plan (2026-06-22). This supersedes the *engine/architecture*
> direction of the original 3D docs (`TECHNICAL_ARCHITECTURE.md`, `VERTICAL_SLICE.md`).
> The **product values** in `PRODUCT_VISION.md`, `GAME_DESIGN.md`, and
> `MODES_AND_DIRECTION.md` still hold — we're changing *how* we render and build,
> not *who it's for*. The 3D build is archived (`AmeliaTV/Archive3D/`,
> `docs/tvos/RESTORE_3D.md`).

## Why we pivoted (one paragraph)

The 3D RealityKit game was built over ~50 PRs that **no one ever watched**. Unit
tests pass on logic but can't see a bad camera, overlapping buildings, or a bus
with no collision — so the whole visual layer was unverified placeholder and the
game felt like garbage. The root cause was a **broken feedback loop**. We fix the
loop first, then build a game whose failure modes are *visible and cheap*: a 2D,
top-down, **GTA 1/2-style drivable town** in SpriteKit.

---

## Part 1 — The feedback review loop (priority #1, non-negotiable)

This is the most important section in the repo. Everything else fails without it.

**The rule: no visual/feel change merges without a capture a human has seen.**
"It compiles and the tests pass" is necessary, never sufficient, for anything on
screen.

### How the loop works
1. **Every PR that touches rendering produces a CI capture.** `ci-screenshots.yml`
   boots the tvOS Simulator, runs a **scripted demo** (no human input needed), and
   publishes a **gameplay video + frame sequence** as artifacts and to the
   `ci-video` branch. (Already live — this is how we first *saw* the game.)
2. **The capture is the review artifact.** Claude pulls the frames back
   (`git fetch origin ci-video`), looks at them, and reports what it sees against
   what it intended — in its own words, in the PR. If they disagree, that's a bug
   to fix *before* asking for human review.
3. **The human watches the capture, not the diff, to judge feel.** Approve/reject
   on what's on screen. The diff is for correctness; the video is for the game.
4. **Tighten the loop over time** (see Backlog FL-*): per-scene "screenshot
   harness" entry points so any scene can be captured in isolation; a deterministic
   "demo script" format so captures are stable and comparable; side-by-side
   before/after frames in the PR; optional real `.mp4` once the headless recorder
   is reliable (today the frame sequence is the source of truth).

### What keeps the loop honest (architecture)
- **Rendering-agnostic Game Core** (`Sources/AmeliaCore`, pure Swift, no SpriteKit):
  driving, world, episodes, dialogue, rewards, NPC decisions — **unit-tested on CI
  without a GPU.** Logic bugs get caught in tests; only *presentation* needs eyes.
- **Data-driven world** (JSON authored as readable text/grids): a layout bug is
  visible *on the page* in the diff, not hidden in coordinates. CI validates the
  data against schemas.
- **Reduce-Motion / determinism:** the demo script runs the same every time so two
  captures are comparable.

### The per-PR gate (checklist every visual PR copies in)
- [ ] Core logic covered by a unit test (if logic changed).
- [ ] Content validates against schema; bilingual strings complete.
- [ ] CI capture attached; **Claude has looked at it and described it**.
- [ ] What I intended vs. what the capture shows — discrepancies noted/fixed.
- [ ] Reduce-Motion respected; no harsh-failure path introduced.

---

## Part 2 — The game: a cozy GTA-style drivable town

Take GTA 1/2's **format** — top-down, a living drivable city, sprite cars and
pedestrians, free roaming — and **none** of its content. This is a warm, bilingual,
child-first world: Amelia drives her bus around a friendly town.

### Look & camera
- **Top-down camera that follows the bus**, gentle zoom. No angle to get wrong.
- **Faked height ("perspective"):** buildings/objects are drawn as sprites with
  visible walls + rooftops + soft drop shadows (a ¾ / oblique art style) so the
  town reads as having height — *without real 3D.* The **logic** underneath stays a
  clean top-down road network in readable data; we only *style* the render. This is
  how we keep the feedback-loop win and still get the GTA look.

### World architecture (the big map)
- **`RoadNetwork`** (data): intersections + lane'd road segments authored as JSON
  with **real positions**. This is the evolution of the old `RouteGraph` and is the
  one structure that *both* Adventure routing and Free Drive steering consume.
- **City blocks / districts:** hand-authored tiles of town (homes, school, park,
  shops, seaside) placed on the network — a **big, explorable map**, authored as
  data, grown a district at a time. (Procedural *city layout* is explicitly **not**
  v1 — we hand-author the map and procedurally *populate* it; see Risks.)
- **Soft bounds:** the map edge is a gentle turn-around, never a wall, never a
  fail.

### The three play modes (same axis as the old plan)
- **Adventure** — episodic, story-based missions (drop-off, find-it, help someone).
  Built on the `EpisodeRunner` we already have. This is the spine.
- **Free Drive** — open, objective-free roaming of the big map. 2D makes this
  *easy* (a drivable network + collision), which is exactly why it died in 3D.
- **Jobs / Helper** — pick-up-and-deliver loops (passengers, parcels) layered on the
  same world.

### Driving model + assist levels
- **Free steering** by default (push to turn, GTA-style) for the slice.
- **`AssistLevel`** still scales controls with the child: **Auto-Drive** (remote =
  decisions, not steering) / **Assisted** / **Free**. Free steering for the slice;
  auto-assist returns as an option, not a requirement. Works with **Siri Remote
  alone**; controller is the nicer option.

### NPCs, traffic & characters
- **Procedurally generated traffic & pedestrians:** sprite cars follow lanes on the
  `RoadNetwork`; pedestrians walk paths/sidewalks. Simple behaviors (follow lane,
  yield, stop at lights, despawn off-screen, respawn ahead). Pure-Core decisions →
  render observes. This gives a *living* town cheaply and is unit-testable.
- **Good, recurring characters:** Amelia, Mechanic Mom, named passengers/neighbors
  with their own look, palette, and bilingual lines — **original IP only** (D-IP-1).
  Cute, expressive (the `FaceRig`/eased-animation utilities already exist in Core).

### Honk → the world reacts (the popular verb — make it a system)
A first-class **reaction system**: honking (and other verbs) emits a Core
*stimulus*; nearby entities **react in varied, delightful ways** — a friend waves,
birds scatter, a cat hops, a duck quacks back, a light turns green, a shy NPC
giggles. Reactions are **data-driven** (`reactions.json`: stimulus → weighted
reactions per entity type) so we can add charm without code, and **varied** so it
never feels canned. This was a hit in the prototype; it becomes a core toy of Free
Drive and a teaching tool in Adventure.

### Educational layer (woven in, never a worksheet)
- Spoken **EN/ES** everywhere (string ids with both languages; CI fails on a
  missing translation).
- Gentle, in-world learning: counting passengers, colors, shapes of signs, safe
  road rules (stop at red, look both ways), letters/place names — surfaced through
  play (honk to count, find the blue house), never as a quiz, never with failure.

### The feeling (unchanged)
Cozy, warm, "a show you can drive." Minimal reading, big readable UI, immediate
positive feedback, **no harsh failure**, **privacy as a hard constraint** (no ads/
analytics/accounts/IAP/network; local saves; Kids-Category).

---

## Part 3 — Architecture & what we reuse

```
SwiftUI shell ── observes ──▶ SpriteKit scenes (town, HUD overlay)
      ▲                              ▲ render-only: sprites, faked height, juice
      │ intents                      │
      └────────── Game Core (pure Swift, unit-tested, no SpriteKit) ──────────┐
         RoadNetwork · DrivingModel/AssistLevel · EpisodeRunner · Traffic &   │
         NPC decisions · ReactionSystem · Dialogue · Rewards · Save · Localizer│
                         ▲ GameController (Siri Remote + MFi) → intents        │
```

**Reused from today (kept):** `AmeliaCore` — `EpisodeRunner`, `DialogueDirector`,
rewards, `SaveSlot`/`SaveStore`, `Localizer`, `Easing`/`SpringValue`, `Vec2`,
`AssistLevel`, and `RouteGraph` (evolves into `RoadNetwork`). The bilingual content
(`strings/`, `passengers.json`, `places.json`) carries over.

**New (Render, SpriteKit):** town scene, faked-height building sprites, bus +
follow camera, traffic/pedestrian sprites, HUD overlay, juice.

**New (Core):** `RoadNetwork`, `DrivingModel` (free steering + assist), traffic/NPC
decision systems, `ReactionSystem` — all pure and unit-tested.

---

## Part 4 — Roadmap (every milestone ends in a capture a human watches)

- **M0 — Loop + one room (done).** SpriteKit app on tvOS 26, walkable room, tile
  collision, CI gameplay capture. *We can see the game.* ✅
- **M1 — Drivable block.** `RoadNetwork` (data) + bus **free-steering** along it +
  follow camera + a few **height-styled buildings** + **one procedural car** +
  collision. Capture it.
- **M2 — Living street.** Procedural **traffic + pedestrians**, traffic light,
  **honk → reaction system** (first 4–5 reactions). Capture it.
- **M3 — Adventure beat in the town.** Port the `first-day` episode onto the road
  network (drive → stop → pick up → drop off → reward) with TTS EN/ES + HUD.
- **M4 — Free Drive + bigger map.** Soft bounds, 2–3 districts, collectibles, the
  "spot it" find beat. The open toy.
- **M5 — Charm & polish.** Character life, more reactions, cozy day/night, audio
  pass, splash/language.
- **Beyond.** Jobs/Helper mode; more episodes; iPad build (same code); TestFlight.

## Part 5 — Backlog (first, concrete items)

**Feedback loop**
- **FL-01** Per-scene capture entry points (launch any scene headless for CI).
- **FL-02** Deterministic demo-script format (stable, comparable captures).
- **FL-03** Reliable `.mp4` out of the headless recorder (frames are truth until then).
- **FL-04** PR template embedding the per-PR gate checklist.

**Game (M1–M2)**
- **G-01** `RoadNetwork` model + schema + unit tests (pathfind, nearest-lane).
- **G-02** `DrivingModel`: free steering + `AssistLevel`, unit-tested kinematics.
- **G-03** SpriteKit town scene: road rendering + faked-height building sprites.
- **G-04** Bus entity + follow camera + collision against buildings/edges.
- **G-05** Procedural traffic (lane-following cars) — Core decisions + render.
- **G-06** Procedural pedestrians.
- **G-07** `ReactionSystem` + `reactions.json` + honk verb (5 reactions, varied).

## Part 6 — Risks & decisions

- **R-2D-1 — Faked perspective vs. real 3D.** We fake height in 2D art to keep the
  feedback-loop win. Accept: no true camera rotation/parallax. Mitigation: lean art
  style; if we ever *need* real perspective, a fixed top-down SceneKit camera is the
  fallback — but that reintroduces the 3D problems we left, so resist it.
- **R-2D-2 — Procedural scope creep.** Procedural *NPCs/traffic* = in scope & easy.
  Procedural *whole-city generation* = **out of v1**; hand-author the map, populate
  it procedurally. Revisit only after the big hand-authored map proves fun.
- **R-2D-3 — Performance on real Apple TV 4K.** Many sprites + faked height can get
  busy. Mitigation: sprite atlases, cull off-screen, cap active NPCs, test on
  device early.
- **D-IP-1 (still open)** original-IP rule; **D-ART-1** art sourcing; **D-SIGN-1**
  signing — unchanged from `RISKS_AND_DECISIONS.md`.
- **D-2D-REPO — repo/App Store.** Decided: **same repo, one app target**; the 2D
  game supersedes the archived 3D in dev; the App Store listing/bundle decision is
  deferred to ship time. (Avoids rebuilding the hard-won signing pipeline.)

## Part 7 — Added scope (2026-06-23, owner request)

New ideas to fold into the milestones above. Keep moving; implement the visual
pieces now, leave the interactive ones to their milestone.

### CH-01 — "Quick Stop!" challenge (an Adventure beat → M3, posed visual now)
A **cutscene-driven driving challenge**: a **ball rolls across the street** and a
**kid is about to chase it**; Amelia must **brake in time**. Mechanics:
- A **reaction meter** appears and **drains**; the bus must come to a stop **before
  it empties**. Stop in time → **points + reward** (more points the quicker/closer
  to the line); never a harsh fail — if missed, the kid safely waits and we retry
  with encouragement (no harm shown, child-appropriate).
- Teaches **stopping, looking, road safety**. Pairs with the traffic-light beat.
- **Now:** a **posed still** (ball mid-street, kid at the curb, bus stopped) so we
  can see the moment. **Later (M3):** the live meter + scoring + the brake input
  hooked to the reaction window, authored as an `Episode` beat (`quickStop`).
- **Done (2026-06-23):** the meter is now **interactive on the Montrose crossing**.
  When the ball arms, a spoken + subtitled **bilingual prompt** ("A ball! Press the
  brake!" / "¡Una pelota! ¡Frena!") fires and a pulsing **"Brake!"** cue floats over
  the bus; the goal beacon hides so the eyes go to the brake. The player's real brake
  drives the unit-tested `QuickStopChallenge` (stop before the meter empties → score
  + sparkle + praise; the kid trots out, scoops the ball, hops home). **No harsh
  failure:** a miss rolls the ball safely clear, offers gentle encouragement, and
  re-arms for another try. Still scene-driven; authoring it as a first-class
  `Episode` `quickStop` beat (so it sequences in data) remains the follow-up.

### ART-PARK-01 — the city park (M2 charm, build now)
Turn the placeholder pond into a **real city park**: **water** (pond/fountain),
a **statue**, **pigeons** (peck/hop), **trees + shade**, a **soccer field** with a
ball and goals, and **kids playing**. Static/animated dressing; no new systems.

### ART-PERSP-01 — a building with GTA-style shifting perspective (build now)
At least **one landmark building** whose **faked height re-projects as the bus
drives around it** — the roof/walls lean based on the camera's position, so you
appear to orbit a 3D box (while the logic stays flat top-down). Proves the look;
generalize to more buildings later if it reads well. (Softens R-2D-1: we *can*
fake parallax per-building without real 3D.)

### ART-BUS-01 — cuter hero bus (build now)
The bus is the star and must be **cute**: rounder, friendlier proportions, **big
eyes / a face**, warm details. Original design (D-IP-1).

### D-ART-1 — where to source real art (recommendation, for the owner)
Until commissioned/AI art lands, everything is original placeholder shapes. Paths,
roughly cheapest→nicest:
- **Ready-made 2D top-down asset packs** (fastest): **Kenney.nl** (free, CC0,
  cohesive top-down/roads/characters — ideal first pass), **itch.io** asset packs,
  **Game Art 2D**, **CraftPix**, **Unity/Unreal asset stores** (sprites are engine-
  agnostic PNGs). Check licenses (CC0/royalty-free, commercial OK).
- **AI generation** for sprites/tiles: **Midjourney**, **DALL·E**, **Stable
  Diffusion** (with a fixed top-down style prompt), then trace/clean to a
  consistent palette. Watch originality/IP (D-IP-1) and license terms.
- **Commission a 2D artist** (best cohesion): **Fiverr / Upwork**, **ArtStation**
  marketplace, or a children's-illustration freelancer for a bespoke cozy look.
- **Audio** (separate): **Freesound** (CC0 SFX), **Kenney audio**, or a composer on
  Fiverr; voice via on-device TTS now, hero VO later.
Recommendation: start with **Kenney top-down packs** to get a cohesive look fast,
then **commission a hero set** (bus + Amelia + key buildings) once the play proves
out. **Pick one art director/reviewer** to keep style + originality consistent.

### WORLD-01 — Welles Park reshape (2026-06-23, owner request, build now)
Reshape the demo block into a **real neighborhood** modeled on **Welles Park,
Lincoln Square, Chicago**: a big park bounded by **Western Ave** (west, straight),
**Montrose** (north), the **Lincoln Ave diagonal** (NE→SW, east), and **Sunnyside**
(south) — `RoadNetwork.welles` + `wellesLoop`. The `first-day` episode is re-homed
onto this loop and still runs end-to-end (bus homes in on the goal so the bigger map
doesn't strand it short of the arrival radius).
- **Road tiles / markings:** solid white lane-edge lines inset from both curbs,
  **zebra crosswalks** at the bus stop / school / traffic light, and **asphalt
  intersection pads** at the four corners (`RoadNetwork.intersections()`, unit-tested).
- **Park interior** (off the roads), laid out like the real park: a **baseball
  diamond**, the **gym + indoor-pool fieldhouse**, **tennis** and **pickleball**
  courts, a **playground** (slide/swings/sandbox), the **pond + fountain**, and an
  **adventure grove** of trees with children.
- **Outside the roads:** a generic neighborhood **church** (north), **apartments**
  (west, Western), **restaurants/shops** (south, Sunnyside), the **library** as the
  shifting-perspective landmark (east, across Lincoln), and the **school** at the
  drop-off. Original, generic silhouettes only (D-IP-1).

### WORLD-02 — charm/detail pass (2026-06-23, owner request)
Make the buildings feel lived-in (render-only, no Core change):
- **Warmer windows everywhere:** mix of warm-**lit** (golden glow + spill) and cool
  glass panes, each with a frame + mullion, on every building's street face.
- **Storefronts:** striped scalloped **awnings** + a wordless **icon sign** — a
  steaming **mug** for the café/restaurant, a **shopping bag** for the shop — plus a
  door. Icons (not words) so pre-readers get them and nothing needs translating.
- **School:** double doors + step, a **clock**, a waving **flag**, and a **bell** sign.
- **Apartments:** a stoop door + balcony rails.
- **Church:** arched **stained-glass** windows + an arched wooden door (keeps the
  bell tower, spire, rose window).
- **Library:** a **monument sign** (board on posts) with a wordless open-**book**
  icon, set toward Lincoln Ave so the landmark reads from the road.
