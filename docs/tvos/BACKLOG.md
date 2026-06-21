# Amelia's Bus Adventure — Backlog

> Status: **Planning (Phase 0)**. Implementation-ready backlog. Each item is sized
> to be a small, reviewable PR. Every item carries: **ID · Title · Milestone ·
> Priority · Player-facing outcome · Acceptance criteria · Dependencies ·
> Complexity (S/M/L/XL) · AI-suitable? · Needs human visual/gameplay review?**
>
> **Priority:** P0 (must), P1 (should), P2 (nice).
> **AI-suitable?** = good candidate for a Claude-authored PR.
> **Human review?** = needs a person to look/play to judge feel or art.

## Legend & conventions

- IDs are stable; reference them in GitHub issues/PRs (e.g. "Closes A1-03").
- "AI-suitable: Yes" still means a human reviews the PR — it means the *authoring*
  is a good fit for Claude.
- Items marked **Human review: Yes** require play-testing or art judgement that
  can't be verified by tests alone.

---

## Phase 1 — Native project foundation

### F1-01 — Scaffold native tvOS app `AmeliaTV/`
- **Milestone:** Phase 1 · **Priority:** P0
- **Outcome:** the app launches to a blank/placeholder scene on Apple TV.
- **Acceptance:** `AmeliaTV/` exists per `TECHNICAL_ARCHITECTURE.md` layout;
  SwiftUI app target builds for tvOS Simulator; launches to a placeholder view;
  existing web game untouched.
- **Dependencies:** D-PROJ-1, D-REPO-1 decided.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** No

### F1-02 — `ci-tvos` GitHub Actions workflow (no secrets)
- **Milestone:** Phase 1 · **Priority:** P0
- **Outcome:** every PR gets a green/red build+test signal automatically.
- **Acceptance:** workflow on a GitHub-hosted macOS runner selects Xcode, builds
  + runs unit tests on tvOS Simulator, validates content JSON against schemas,
  lints; uses **no signing secrets**; runs on PRs to the native game.
- **Dependencies:** F1-01.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** No

### F1-03 — Game Core module skeleton + first unit test
- **Milestone:** Phase 1 · **Priority:** P0
- **Outcome:** (invisible) a testable, rendering-agnostic core exists.
- **Acceptance:** pure-Swift `Core` module compiles with no RealityKit/SwiftUI
  imports; one passing unit test; wired into `ci-tvos`.
- **Dependencies:** F1-01.
- **Complexity:** S · **AI-suitable:** Yes · **Human review:** No

### F1-04 — RealityKit-on-tvOS rendering spike (R-ENG-1)
- **Milestone:** Phase 1 · **Priority:** P0
- **Outcome:** a placeholder bus visibly sits in a 3D scene on Apple TV.
- **Acceptance:** loads a USDZ scene, places a placeholder bus entity, runs a
  per-frame update hook, follow-camera works, renders at target on Apple TV 4K
  (device or Simulator); findings written to `RISKS_AND_DECISIONS.md`.
- **Dependencies:** F1-01.
- **Complexity:** L · **AI-suitable:** Partial (needs human to confirm on real
  hardware) · **Human review:** Yes

### F1-05 — Input layer: GameController → device-agnostic intents
- **Milestone:** Phase 1 · **Priority:** P0
- **Outcome:** Siri Remote and a controller both move/select in the app.
- **Acceptance:** Siri Remote (clickpad/select/play-pause) and an MFi/PS/Xbox
  controller both populate the intent layer (GO/STOP/steer/choose/honk/confirm/
  back); device-agnostic; covered by core unit tests where logic allows.
- **Dependencies:** F1-03.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes (feel on
  device)

### F1-06 — GLB→USDZ asset import path + placeholder fallback
- **Milestone:** Phase 1 · **Priority:** P1
- **Outcome:** art can be swapped in later without code changes.
- **Acceptance:** documented/scripted GLB→USDZ conversion; models referenced by
  id; missing/absent model falls back to a primitive placeholder (no crash);
  one model proven through the pipeline.
- **Dependencies:** F1-04.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** No

---

## Phase 2 — Playable vertical slice ("First Day Driving")

### A2-01 — Save store (local, single slot, Codable)
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** progress and language persist across relaunch.
- **Acceptance:** `SaveSlot` persists locally as Codable; atomic writes; corrupt
  file → fresh slot; unit-tested; no network.
- **Dependencies:** F1-03.
- **Complexity:** S · **AI-suitable:** Yes · **Human review:** No

### A2-02 — Bilingual strings + DialogueService (TTS)
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** Amelia/Mom/passengers speak in English or Spanish with subtitles.
- **Acceptance:** strings as `en`/`es` JSON (seeded from `drive/i18n.js`); a line
  plays by id via `AVSpeechSynthesizer` in the active language; subtitle shown;
  lines queue/de-dupe (no talking over itself); language switch at runtime.
- **Dependencies:** F1-03, A2-01.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes (voice feel)

### A2-03 — EpisodeRunner + beat types
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** (engine) a data-defined adventure can play start→finish.
- **Acceptance:** beats `say/driveTo/pickup/dropoff/lightStop/choice/reward`
  implemented; runner advances on arrival/stop/choice; emits hooks for
  speak/board/drop/reward; unit-tested with a sample episode JSON.
- **Dependencies:** F1-03.
- **Complexity:** L · **AI-suitable:** Yes · **Human review:** No

### A2-04 — Driving model + assist levels
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** the bus drives in a calm, child-friendly way; can't really crash.
- **Acceptance:** Auto-Drive (follows route), Assisted Steering (lane-guided),
  Free Steering implemented; capped speed; **soft collisions** (bump + nudge,
  never stuck/damaged); same intents serve all levels; core logic unit-tested.
- **Dependencies:** F1-03, F1-05, A2-06.
- **Complexity:** L · **AI-suitable:** Yes · **Human review:** Yes (feel)

### A2-05 — Route graph + navigation guidance
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** the game always shows "where do I go" via arrows + voice + beacon.
- **Acceptance:** node/edge route graph for one neighborhood; route to a target
  computed; glowing route ribbon + pulsing turn arrows + minimap + destination
  beacon; timed bilingual turn cues; generous arrival radii; pathfinding
  unit-tested.
- **Dependencies:** A2-03.
- **Complexity:** L · **AI-suitable:** Yes · **Human review:** Yes (readability)

### A2-06 — Traffic light + stop teaching
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** child learns red=stop / green=go with praise, never punishment.
- **Acceptance:** light cycles red/yellow/green; `lightStop` beat requires a stop
  on red; stopping → praise + star sparkle; running red → gentle correction +
  repeat (no failure); bilingual lines; cycle logic unit-tested.
- **Dependencies:** A2-03.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes

### A2-07 — Garage home-base scene + Mechanic Mom intro
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** a cozy home base where Mom greets the player and the day begins.
- **Acceptance:** garage scene renders (placeholder art ok); Mom character +
  greeting lines (bilingual); a single big "Let's go!" action starts the
  adventure; sticker wall placeholder present.
- **Dependencies:** F1-04, A2-02.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes (art/feel)

### A2-08 — One neighborhood route + set dressing
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** a short, pretty loop to drive (garage→stop→place→garage).
- **Acceptance:** hand-built small route (a few intersections) with road, one bus
  stop, one traffic light, one fork, one destination (e.g. park); placeholder
  buildings/trees; matches the route graph (A2-05).
- **Dependencies:** A2-05, F1-06.
- **Complexity:** M · **AI-suitable:** Partial · **Human review:** Yes (art)

### A2-09 — One passenger with personality (pickup/dropoff)
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** a friend (e.g. Pip 🐻) waves, boards, chats, thanks Amelia.
- **Acceptance:** passenger entity + waving/board/exit; bilingual hello/thanks
  lines; `pickup`/`dropoff` beats trigger doors + boarding + celebration; seeded
  from `drive/npc.js`.
- **Dependencies:** A2-03, A2-07.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes (character)

### A2-10 — HUD overlay (GO/STOP, arrows, minimap, stars)
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** big, readable controls and guidance on the TV.
- **Acceptance:** large GO/STOP targets, turn arrows, minimap, star counter;
  couch-readable at 1080p/4K; minimal text; reflects core state; works with
  Siri Remote focus + controller.
- **Dependencies:** A2-04, A2-05.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes (readability)

### A2-11 — Splash + language screen
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** a friendly start with one Play action and a language choice.
- **Acceptance:** title + Amelia; single big Play; English/Spanish choice with
  spoken sample; remembered after first run (skips next time); Siri-Remote
  navigable.
- **Dependencies:** A2-01, A2-02.
- **Complexity:** S · **AI-suitable:** Yes · **Human review:** Yes

### A2-12 — Reward / completion screen + first sticker
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** a satisfying end: Mom's praise, stars, a sticker on the wall.
- **Acceptance:** `reward` beat shows stars earned + grants one sticker (saved);
  Mom praise (bilingual); celebratory audio; returns to garage with sticker
  displayed.
- **Dependencies:** A2-03, A2-07, A2-01.
- **Complexity:** S · **AI-suitable:** Yes · **Human review:** Yes

### A2-13 — Audio: slice music themes + SFX set
- **Milestone:** Phase 2 · **Priority:** P1
- **Outcome:** the slice sounds warm and alive.
- **Acceptance:** garage theme, driving loop, horn, door, star sparkle, light/
  sign chime, gentle bump; voice mixed above all; calm, non-frantic.
- **Dependencies:** A2-02.
- **Complexity:** M · **AI-suitable:** Partial · **Human review:** Yes (audio)

### A2-14 — Slice integration + acceptance pass
- **Milestone:** Phase 2 · **Priority:** P0
- **Outcome:** the whole "First Day Driving" loop plays end-to-end.
- **Acceptance:** all `VERTICAL_SLICE.md` acceptance criteria met; completable
  with **only** a Siri Remote; both languages; no failure state; persists;
  CI green.
- **Dependencies:** A2-01…A2-13.
- **Complexity:** L · **AI-suitable:** Partial · **Human review:** Yes (full
  play-test)

---

## Character Life & Charm (Pixar feel — render-only, runs alongside Phase 2/3)

Procedural personality over placeholder geometry; no Core/gameplay change (see
`GAME_DESIGN.md` §4a). Smallest-first, one PR each. Art-free, so it ships now and
swaps to USDZ later by id. All Reduce-Motion aware; original-IP (D-IP-1).

### CL-01 — Amelia comes alive (the bus)
- **Milestone:** now · **Priority:** P1
- **Outcome:** the bus blinks, looks toward her destination, squashes on stops,
  leans into turns, breathes when idle, hops on pickup, wiggles on a honk.
- **Acceptance:** a `FaceRig` makes the eyes addressable; a pure `Easing`/`Spring`
  util lives in the Core with unit tests (CI green); motion eases/overshoots (not
  linear); honors Reduce Motion; Core untouched.
- **Dependencies:** A2-08/A2-09 (scene + bus). **Complexity:** M · **AI-suitable:**
  Yes · **Human review:** Yes (Simulator: does she feel alive?)

### CL-02 — The neighborhood is alive (NPCs/passengers)
- **Milestone:** next · **Priority:** P1
- **Outcome:** NPCs/passengers idle-bob, blink, turn to watch the bus, wave, hop
  when boarded; reuse the `FaceRig` for `character()`.
- **Acceptance:** ambient + the episode rider all show life; no Core change.
- **Dependencies:** CL-01. **Complexity:** M · **AI-suitable:** Yes
- **Status:** done — `characterRig` (eyes addressable + a wave arm) reused for every
  NPC and the rider; a shared `animateCharacter` does idle-bob, staggered blink,
  turn-to-watch the passing bus, glance, and wave-when-near, with an excited hop as
  the bus pulls up and a delighted hop on delivery. Reduce-Motion aware; Core untouched.

### CL-03 — The world reacts (honk-reacts + props)
- **Milestone:** next · **Priority:** P1
- **Outcome:** honk → friends wave, ducks/birds scatter, props boing; landmarks
  animate (flag flutter, lighthouse beam, sign spin). Completes the Agency-pass
  "world reacts" verb (`MODES_AND_DIRECTION.md`).
- **Acceptance:** honk read from `InputIntents.honkPressed` in the render loop; no
  Core change. **Dependencies:** CL-01. **Complexity:** M · **AI-suitable:** Yes
- **Status:** done — `NeighborhoodScene.updateAmbient` drives continuous landmark
  life (school flag flutter, a new lighthouse beam sweep, bus-stop sign spin,
  fountain spray, grouped cloud drift). A small bird flock perches near the stops
  and `NeighborhoodScene.honk(busPos:)` scatters the nearby ones (spring back to
  perch). Friends/rider wave back enthusiastically + hop on a honk. Reduce-Motion
  aware; Core untouched.

### CL-04 — Juice (particles & feedback)
- **Milestone:** later · **Priority:** P2
- **Outcome:** wheel dust puffs, star bursts, hearts, gentle camera bounce on
  honk/pickup, confetti into the reward screen.
- **Acceptance:** lightweight, within the perf budget (R-PERF-1); Reduce-Motion
  aware. **Dependencies:** CL-01. **Complexity:** M · **AI-suitable:** Yes
- **Status:** done — new render-only `JuiceEmitter` (pooled hand-animated primitives,
  no `ParticleEmitterComponent`) bursts `.sparkle` on star-award/collectible-scoop,
  `.heart` on pickup/honk, `.dust` on hard-stop and while rolling fast; a `SpringValue`
  camera bounce kicks on honk/pickup/stop. Reward-screen confetti already existed
  (`RewardView`). Reduce-Motion aware; Core untouched.

### CL-05 — Cozy world mood (day/dusk/night + weather)
- **Milestone:** later · **Priority:** P2
- **Outcome:** a day→dusk→night lighting/material wash (headlights, glowing
  windows, stars) + soft weather (puddle splashes); ties to §16.
- **Acceptance:** cheap lighting/material tweaks; no gameplay impact.
- **Dependencies:** A2-08. **Complexity:** M · **AI-suitable:** Yes
- **Status:** done — `SpikeEngine.updateMood` runs a slow day→dusk→night→dawn wash:
  the sun dims (with a constant fill light so it never goes black — readability is a
  hard constraint), and `NeighborhoodScene.setNight` glows the windows + lamp globes
  warm (unlit) and fades stars in overhead; the bus gains headlights that light up at
  night. Night is capped (never fully dark) and **held at bright day under Reduce
  Motion**. Material updates throttled; Core untouched. Completes the CL charm arc.

---

## Phase 3 — First complete episode

### E3-01 — Author a second episode as data
- **Milestone:** Phase 3 · **Priority:** P0
- **Outcome:** a new story (e.g. Lost Puppy / Beach Trip) playable from JSON.
- **Acceptance:** episode authored entirely as data (beats + strings + asset
  refs); no engine changes beyond any new beat it needs; passes its own
  acceptance play-test.
- **Dependencies:** A2-14.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes (fun)

### E3-02 — First real art pass (USDZ swap-in)
- **Milestone:** Phase 3 · **Priority:** P0
- **Outcome:** Amelia/Mom/passenger/garage/route look "show-quality."
- **Acceptance:** final low-poly USDZ models swapped over placeholders by id; no
  gameplay regression; within poly/texture budgets; original IP (not Tayo/Cars).
- **Dependencies:** F1-06, A2-08, D-ART-1.
- **Complexity:** L · **AI-suitable:** Partial · **Human review:** Yes (art)

### E3-03 — Art-directed audio + optional hero voice lines
- **Milestone:** Phase 3 · **Priority:** P1
- **Outcome:** warmer audio; a few recorded Amelia/Mom lines.
- **Acceptance:** improved music/SFX; optional recorded clips for key lines with
  TTS fallback intact; mix keeps voice intelligible.
- **Dependencies:** A2-13.
- **Complexity:** M · **AI-suitable:** Partial · **Human review:** Yes (audio)

---

## Phase 4 — Expandable systems

### X4-01 — Rewards shop + bus cosmetics
- **Milestone:** Phase 4 · **Priority:** P1
- **Outcome:** spend stars on bus paint/hat/horn (visual only).
- **Acceptance:** shop UI (couch-readable); cosmetics data-driven; purely
  cosmetic (never affect difficulty); persisted; no real money.
- **Dependencies:** A2-12.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes

### X4-02 — Garage decorations
- **Milestone:** Phase 4 · **Priority:** P2
- **Outcome:** decorate the garage with stars-bought items.
- **Acceptance:** decoration data + placement; persists; visible in garage.
- **Dependencies:** X4-01.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes

### X4-03 — Collectibles along routes
- **Milestone:** Phase 4 · **Priority:** P2
- **Outcome:** optional shinies to find while driving.
- **Acceptance:** collectibles placed in data; collecting gives stars; never
  required for progress; per-episode and world-wide variants.
- **Dependencies:** A2-05.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes

### X4-04 — Multiple named save slots
- **Milestone:** Phase 4 · **Priority:** P1
- **Outcome:** siblings get their own progress/bus.
- **Acceptance:** create/select/rename/reset slots; each isolates progress;
  local-only; big friendly slot picker.
- **Dependencies:** A2-01.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes

### X4-05 — Gated parent settings area
- **Milestone:** Phase 4 · **Priority:** P1
- **Outcome:** a parent can set language/assist/volume/subtitles, reset a slot.
- **Acceptance:** child-resistant gate (e.g. hold/shape gate, not a memorable
  password); few big options; no deep menus; persists.
- **Dependencies:** A2-01.
- **Complexity:** M · **AI-suitable:** Yes · **Human review:** Yes

### X4-06 — Second neighborhood + ≥3 episodes total
- **Milestone:** Phase 4 · **Priority:** P1
- **Outcome:** more world and stories; additive, gentle unlocks.
- **Acceptance:** a second neighborhood (graph + set dressing); episode catalog
  ≥3; unlocking is a gift, never a fail-gate.
- **Dependencies:** E3-01, E3-02.
- **Complexity:** L · **AI-suitable:** Partial · **Human review:** Yes

### X4-07 — Friends / passenger collection screen
- **Milestone:** Phase 4 · **Priority:** P2
- **Outcome:** track who you've met.
- **Acceptance:** screen lists met passengers; updates on first meeting;
  read-only, friendly.
- **Dependencies:** A2-09.
- **Complexity:** S · **AI-suitable:** Yes · **Human review:** No

---

## Phase 5 — TestFlight & release preparation

### R5-01 — `release-tvos` signed pipeline (protected, manual)
- **Milestone:** Phase 5 · **Priority:** P0
- **Outcome:** a signed build can reach TestFlight on demand.
- **Acceptance:** separate workflow gated by a protected environment + manual
  approval; **only** place Apple signing/App Store Connect/TestFlight secrets
  live; archives/signs/uploads; normal PRs never touch these secrets.
- **Dependencies:** F1-02, D-SIGN-1.
- **Complexity:** L · **AI-suitable:** Partial (human supplies secrets/approval)
  · **Human review:** Yes

### R5-02 — App metadata, icons, privacy labels, Kids checklist
- **Milestone:** Phase 5 · **Priority:** P0
- **Outcome:** store-ready, Kids-Category-aligned metadata.
- **Acceptance:** icons/launch assets; truthful privacy labels (no data
  collected); Kids-Category checklist pass; no external links visible to kids.
- **Dependencies:** A2-14.
- **Complexity:** M · **AI-suitable:** Partial · **Human review:** Yes

### R5-03 — Accessibility, couch-readability & performance pass
- **Milestone:** Phase 5 · **Priority:** P1
- **Outcome:** crisp, readable, smooth on a real 4K TV.
- **Acceptance:** UI legible at couch distance; steady frame rate at 4K; voice
  always intelligible; reduce-motion respected; no-failure guarantee QA'd across
  edge cases.
- **Dependencies:** A2-14.
- **Complexity:** M · **AI-suitable:** Partial · **Human review:** Yes

---

## Later (post-release)

| ID | Title | Milestone | Priority | Complexity | AI-suitable | Human review |
|---|---|---|---|---|---|---|
| L-01 | Episode: Parade Day | Later | P1 | M | Yes | Yes |
| L-02 | Episode: Rainy-Day Rescue (+ rain mood) | Later | P1 | M | Partial | Yes |
| L-03 | Episode: Helping a Friend | Later | P1 | M | Yes | Yes |
| L-04 | Free Drive mode (unlock) | Later | P1 | M | Yes | Yes |
| L-05 | Weather / day-night moods | Later | P2 | M | Partial | Yes |
| L-06 | iPad/iPhone build | Later | P2 | L | Partial | Yes |
| L-07 | iCloud save (behind decision) | Later | P2 | M | Yes | Yes |
| L-08 | Public App Store submission (behind decision) | Later | P1 | M | Partial | Yes |

> Each "Later" item, when activated, should be expanded into a full backlog entry
> with acceptance criteria before work begins.
