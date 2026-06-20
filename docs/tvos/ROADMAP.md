# Amelia's Bus Adventure — Roadmap

> Status: **Planning (Phase 0)**. Phases are **milestones**, not dates. Each is
> broken into small, reviewable PRs (see `BACKLOG.md` for the item-level detail).
> The guiding rule: **a great small game over a huge weak game** — we don't start
> a phase until the previous one is genuinely solid.

## Phase overview

| Phase | Name | Goal | Exit criteria |
|---|---|---|---|
| **0** | Planning & architecture | Decide what & how | This docs set merged; engine chosen; first 5 issues filed |
| **1** | Native project foundation | A buildable, CI-green empty native app | `AmeliaTV/` builds & tests on CI; runs on Apple TV; input + 3D spike proven |
| **2** | Playable vertical slice | The "First Day Driving" loop | All `VERTICAL_SLICE.md` acceptance criteria met |
| **3** | First complete episode | One full, polished story episode | A second episode shippable end-to-end with art + voice direction |
| **4** | Expandable systems | Content scales without engine work | Rewards shop, cosmetics, multiple slots, ≥3 episodes, 2nd neighborhood |
| **5** | TestFlight & release prep | Family/TestFlight-ready build | Signed release pipeline + privacy/Kids review pass |
| **Later** | More worlds & Free Drive | Ongoing content | Additional neighborhoods, episodes, Free Drive |

---

## Phase 0 — Planning & architecture (this PR)

**Goal:** establish vision, design, architecture, slice, roadmap, backlog, risks.

- [x] Inspect the existing web prototype (`drive/`).
- [x] Verify time-sensitive tvOS facts (SceneKit deprecation, RealityKit on
      tvOS, Unity tvOS, GameController, macOS CI).
- [x] Recommend a single engine/framework with justification.
- [x] Define the vertical slice scope (in / deferred).
- [x] Author this documentation set + root `CLAUDE.md`.
- [ ] **Decisions from the human** (see end of this file & `RISKS_AND_DECISIONS.md`).

**Exit:** docs merged; open decisions resolved; first 5 implementation issues
created.

## Phase 1 — Native project foundation

**Goal:** a real, buildable native tvOS app skeleton with CI — *no gameplay yet*,
but every technical risk de-risked.

- Scaffold `AmeliaTV/` (Xcode project / Swift Package per D-PROJ-1).
- `ci-tvos` GitHub Actions workflow: build + test on tvOS Simulator, JSON-schema
  validation, lint — **no secrets**.
- **RealityKit-on-tvOS spike** (R-ENG-1): load a USDZ scene, follow camera,
  per-frame gameplay update hook, render a placeholder bus on an Apple TV / 4K
  Simulator.
- **Input spike:** GameController reading Siri Remote *and* an MFi/PS/Xbox
  controller into the device-agnostic intent layer.
- **GLB→USDZ import** path validated with one placeholder model.
- Pure-Swift **Game Core** module compiles and has a first unit test.

**Exit:** app launches to a placeholder scene on device/Simulator; CI green;
spikes prove RealityKit + input + asset pipeline on tvOS. If the spike fails,
trigger R-ENG-1 fallback evaluation **before** Phase 2.

## Phase 2 — Playable vertical slice

**Goal:** ship the complete "First Day Driving" loop from `VERTICAL_SLICE.md`.

Build, roughly in dependency order:
- Game Core: `GameState`/`SaveStore`, `EpisodeRunner` + beat types, `DrivingModel`
  + AssistLevels, `RouteGraph`/Navigation, Traffic light, Rewards.
- Render: garage scene, one neighborhood route, bus + Mom + one passenger
  (placeholder art ok), route ribbon/arrows/beacon, HUD.
- DialogueService (TTS) + bilingual strings + subtitles.
- Audio: garage/driving themes + SFX set.
- Screens: splash, language, garage/adventure intro, reward/sticker screen.
- Local single-slot save.
- Full Siri-Remote-only playability + controller co-play.

**Exit:** every `VERTICAL_SLICE.md` acceptance criterion is met; a child can
finish it on a remote; CI green.

## Phase 3 — First complete episode

**Goal:** one full, polished, "show-quality" episode beyond the tutorial slice
(e.g. **The Lost Puppy** or **Beach Trip**), proving the content pipeline.

- Author a second episode entirely as **data** (JSON beats + strings + assets).
- First pass of **real art** (Amelia, Mom, one passenger, garage, route set
  dressing) as USDZ swapped in over placeholders.
- First pass of **art-directed audio** + (optional) recorded voice for a few
  hero lines, TTS fallback intact.
- Add any new beat type the episode needs (e.g. richer `cutscene`).

**Exit:** a non-tutorial episode is fun and shippable; adding episodes is
demonstrably "content, not engine."

## Phase 4 — Expandable systems

**Goal:** the systems that create long-term replayability, built data-driven.

- **Rewards shop** + **cosmetics** (bus paint/hat/horn) + **garage decorations**.
- **Collectibles** along routes.
- **Multiple named save slots** + the **gated parent settings** area.
- **Second neighborhood** + ≥3 total episodes.
- Passenger/friends collection screen.

**Exit:** content can grow broadly without touching the engine; ≥3 episodes,
2 neighborhoods, working economy.

## Phase 5 — TestFlight & release preparation

**Goal:** a build a family can install, and that could pass Kids-Category review.

- **`release-tvos`** signed pipeline behind a protected, manually-approved
  environment (Apple certs / App Store Connect / TestFlight secrets isolated).
- App metadata, icons, privacy nutrition labels (truthfully: no data collected),
  Kids-Category checklist pass.
- Accessibility & couch-readability pass; performance pass on 4K.
- Onboarding/first-run polish; QA the no-failure guarantee across edge cases.

**Exit:** TestFlight build distributed to the family; release checklist green.

## Later — additional neighborhoods, stories & Free Drive

- More episodes: **Parade Day**, **Rainy-Day Rescue**, **Helping a Friend**, etc.
- More neighborhoods, passengers, cosmetics, collectibles.
- **Free Drive** unlock after the first episodes.
- **Weather / day-night** moods.
- Possible **iPad/iPhone** build (mostly input + layout).
- Possible **iCloud** save / public App Store submission (each behind an explicit
  decision in `RISKS_AND_DECISIONS.md`).

---

## What the human needs to decide before Phase 1 (see `RISKS_AND_DECISIONS.md`)

1. **Confirm engine:** Swift + RealityKit + SwiftUI, tvOS 26+ / Apple TV 4K
   minimum. (D-MINOS-1, R-ENG-1)
2. **Repo layout:** `AmeliaTV/` in this repo vs. a new repo. (D-REPO-1)
3. **Project format:** Xcode project vs. Swift-Package-first. (D-PROJ-1)
4. **Apple Developer account / signing** availability for the eventual release
   pipeline (not needed for Phase 1–2 simulator CI). (D-SIGN-1)
5. **Art sourcing** plan: AI-generated GLB vs. commissioned, and who reviews art.
   (D-ART-1)
