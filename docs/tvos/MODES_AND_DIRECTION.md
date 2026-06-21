# Amelia's Bus Adventure — Modes & Direction

> Status: **agreed product direction** (set with the project owner, 2026‑06‑21).
> This is the companion to [`GAME_DESIGN.md`](GAME_DESIGN.md): it pins down the
> **three play modes** (including **Free Drive**), the **"make it a game, not a
> ride"** push (player agency / verbs), the **educational layer**, and — crucially
> — the **world architecture changes Free Drive forces on us**. Where this and the
> older docs disagree, **this file wins** for direction; the system mechanics in
> `GAME_DESIGN.md` still hold.

## Why this exists

The vertical slice is charming but **thin**: in ~10–15 minutes the child makes a
handful of decisions (GO, STOP at a red light, one LEFT/RIGHT, honk) while
Auto‑Drive does the rest. That's right for the *youngest* player but risks being
**passive** — closer to an interactive ride than a game. We are deliberately
investing in **agency, variety, discovery, and learning** (never *difficulty* —
the no‑harsh‑failure rule is absolute) so the same cozy world stays fun as the
child grows.

---

## The three modes

The game has **three play modes**. All three obey every non‑negotiable constraint
(no failure, minimal reading, bilingual, local‑only, Kids‑Category safe). A child
should be able to move between them from the **garage**.

1. **Adventure** — the main game today. Guided **story episodes** (data‑defined
   beats): drive a route, pick up a friend, obey a light, make a choice, drop off,
   go home, earn stars + a sticker. This is where new *content* mostly lives.

2. **Free Drive** — **open, objective‑free roaming** of the unlocked world. No
   fail, no timer, no required goal: just drive around the neighborhood, honk at
   friends, find collectibles, visit places, give rides for fun. Framed as a
   *reward* ("You know the neighborhood now — go explore!"), not a sandbox the
   child can get lost or stuck in. **This is the mode that reshapes the world (see
   below).**

3. **Jobs / Helper** *(proposed third mode — confirm with owner)* — light,
   endlessly repeatable **pick‑up‑and‑deliver** tasks across the open world
   ("take Pip to the park, take Lola to school"). Bridges Adventure (structure)
   and Free Drive (freedom); gives near‑infinite gentle content and a strong
   educational hook (match friend→place, count passengers, colors). *If the owner
   intended a different third mode, swap this — the other two are fixed.*

### Cross‑cutting: three **driving levels** (how you control, not what you play)

These already exist in code as `AssistLevel` and apply **inside** any mode, so the
controls scale with the child:

- **Auto‑Drive** — the game drives; the child does the fun decisions. Siri Remote
  is fully sufficient. Default for the youngest.
- **Assisted** — the child **steers**, but the bus is on strong lane rails and
  **cannot crash**. Speed capped. Default for ~5–6 / a parent. *Not yet surfaced
  in the UI — doing so is the biggest "watching → playing" win for older kids.*
- **Free Steering** — looser assist, full analog steering on a controller stick.
  Still no harsh consequences. The natural default for **Free Drive**.

> "3 modes" (what you play) and "3 driving levels" (how you control) are
> **different axes**. Don't collapse them.

---

## Free Drive forces a real, drivable world (architecture)

Adventure mode can fake its world: the bus **auto‑drives in straight lines** to
episode waypoints, and the roads we render are **cosmetic**. **Free Drive cannot
fake it** — the moment the child holds the stick and goes "anywhere," the world
must actually *be* drivable. This is the single biggest new engineering
implication of the direction, and we should build toward it deliberately:

- **A real road network, not cosmetic strips.** Today `RouteGraph` is a
  fully‑connected set of waypoints (good enough for "go to target"), and
  `NeighborhoodScene` draws decorative road strips. Free Drive needs a **drivable
  `RoadNetwork`**: nodes = intersections, edges = road **segments with width /
  lanes**, where the rendered road *is* the surface the bus drives on. Adventure
  routing then runs **on** this network (turn‑by‑turn over real roads) instead of
  beelining — which also makes the `choice` fork lead somewhere visibly different.
- **Lane‑follow / soft containment, never a wall.** Assisted/Free steering keeps
  the bus near the road centre and gently nudges it back at the edges; the world
  boundary is a **soft U‑turn**, not a crash or an invisible wall.
- **Curated, small, hand‑authored world** (per `GAME_DESIGN.md` §3) — *not*
  procedural. The network is **data** (a `roads.json`‑style file) so designers /
  Claude author it without engine work, consistent with the data‑driven pillar.
- **Everything roams on the same map.** Passengers wait at stops, collectibles sit
  along segments, NPC vehicles drive loops — all positioned in the same world
  space so Adventure and Free Drive share one neighborhood.

**New decision to record in `RISKS_AND_DECISIONS.md`:** evolve `RouteGraph` →
a drivable `RoadNetwork` (authoring format + lane model + how Adventure routing and
Free Drive steering both consume it). Until Free Drive is scheduled, keep the cheap
waypoint routing — but **don't paint ourselves into a corner**: new world data
(places, collectibles, signs) should carry real world positions so the eventual
network can adopt them.

---

## Making the ride a game — the "Agency pass" (next build, smallest‑first)

Turn *watching* into *playing* by adding **verbs** — all of them "win or
win‑slower," all Siri‑Remote‑friendly:

- **Honk that matters** — friends/animals wave back, ducks waddle off the road,
  lights blink. The world **reacts** to the child.
- **Collectibles** lightly scattered along routes (balloons / shiny coins) the
  child steers a touch to scoop — a reason to engage with steering even under
  Auto‑Drive; feeds the star economy; never required.
- **"Spot it!"** — a new `find` beat: the voice names something ("find the **red**
  house!", "where's the **dog**?") and the child points/clicks it. Pure engagement
  + first real **learning** hook, zero reading.
- **Deliberate micro‑actions** with juicy feedback: open/close doors, ring the
  bell, wipers in rain, headlights at dusk.
- **Choices that visibly matter** — the LEFT/RIGHT fork leads to *different*,
  now‑distinct districts (beach vs. park).
- **A world that reacts** — NPCs wave, the bus's eyes blink/react, small
  surprises (a duck crossing → a natural STOP moment).

---

## Educational layer (a bus driving a town is a perfect teacher)

All fit the beat/data model and the **no‑reading** rule; introduce gradually:

| Domain | How it rides along |
|---|---|
| **Traffic safety** | Beyond lights: STOP sign (full stop), crosswalk ("let them cross"), school zone (slow), "look both ways" |
| **Colors** | "Find the red car," bus paint, light colors |
| **Counting / numbers** | Count passengers, "3 stars," house numbers, stops left |
| **Letters / phonics** | Bus‑stop letters, "P is for Park," friends' initials |
| **Shapes** | Signs are shapes; sort cargo by shape |
| **Left/right & spatial** | Already core — lean on the minimap |
| **Bilingual (a pillar)** | Name objects in EN+ES; the language toggle becomes a teaching tool |
| **Social‑emotional** | Helping friends, patience at red lights, taking turns, empathy |
| **Sequencing / cause‑effect** | The "first we…, then we…" beat flow itself |

Add a **learning tracker** (parent‑facing, **local‑only**, never uploaded) that
quietly notes which concepts were practiced — strong parent value, zero privacy
cost. (Already foreshadowed in `GAME_DESIGN.md` §7.)

---

## Sequenced plan (how it ladders up)

Each step is small, reviewable PRs against `BACKLOG.md`; do them smallest‑first
and don't start the next until the previous is solid.

1. **Agency pass (verbs)** — honk‑reacts, collectibles, the `find`/"spot it" beat,
   deliberate door/bell. *Turns watching into playing; first learning hook.* ← next
2. **Educational beats** — signs (STOP / crosswalk / school zone), colors,
   counting; the local learning tracker.
3. **Second episode as data** (Phase 3) — variety on a loop that's now fun
   (e.g. Beach Trip / Lost Puppy), proving "content, not engine."
4. **Surface Assisted driving** — let 5–6‑year‑olds actually steer (UI + tuning).
5. **Free Drive groundwork** — `RouteGraph` → drivable `RoadNetwork`
   (`roads.json`), lane‑follow steering, soft world bounds → **Free Drive mode**.
6. **Economy & home** (Phase 4) — stars → cosmetics + garage decorations;
   **Jobs/Helper** mode on the open world; friends/sticker collection screen.

---

## How this maps to what exists today

- **Modes:** the garage is already the hub; add a **Free Drive** card (and a
  Jobs card) to the adventure board. Adventure mode is built.
- **Driving levels:** `AssistLevel { auto, assisted, free }` exists and is wired
  through `GameCore`; Assisted/Free just need UI + the drivable world.
- **World:** `NeighborhoodScene` now renders distinct districts + landmarks;
  the **drivable road network** is the missing piece for Free Drive.
- **Beats/content:** `EpisodeRunner` + `Beat` enum are data‑driven; new verbs
  (`find`, collectibles, honk‑react) extend that pattern, not replace it.

## Open decisions (need the owner)

- **The third mode** — confirm **Jobs/Helper**, or name the intended one.
- **When Free Drive unlocks** — after the tutorial? after N episodes? always on?
- **Road‑network authoring** — hand‑authored `roads.json` vs. derived from places;
  lane count / one‑ vs. two‑way for a child game (probably single friendly lanes).
- **How far to push education** — gentle ambient learning vs. explicit "lessons."
