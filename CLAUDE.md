# CLAUDE.md — Amelia's Playground

Guidance for Claude Code (and humans) working in this repository.

## What this repo contains

This repository holds **two separate things** that must not be confused:

1. **The existing web games** (root + [`drive/`](drive/)) — a bilingual PWA
   ("Aventura Espacial de Amelia") plus a 3D web driving prototype
   ("Amelia el Autobús", in `drive/`, Three.js). These are **playable today** and
   deploy to GitHub Pages. **Leave them untouched** unless a task is explicitly
   about the web games.

2. **The new native game: `Amelia's Bus Adventure`** — a cozy, bilingual
   (EN/ES) 3D driving-and-adventure game for **Apple TV (tvOS)**. This is the
   flagship effort. Its plan lives in [`docs/tvos/`](docs/tvos/); its code will
   live in `AmeliaTV/` (added in Phase 1). It is a **native** app — **not** a
   webview, PWA, Capacitor wrapper, or a port of the web prototype.

> The web prototype in `drive/` is a **reference and idea source** for the native
> game (mission beats, bilingual copy, the garage loop, passengers, driving
> assist) — **not** an architecture to preserve.

## Read these first (the plan)

Start with [`docs/tvos/`](docs/tvos/):

- `PRODUCT_VISION.md` — who it's for, the feeling, hard constraints.
- `GAME_DESIGN.md` — the whole-game design & systems.
- `TECHNICAL_ARCHITECTURE.md` — **engine decision** + structure + CI.
- `VERTICAL_SLICE.md` — the first thing we build (10–15 min adventure).
- `ROADMAP.md` — phases 0→5 and beyond.
- `BACKLOG.md` — implementation-ready, item-level work.
- `RISKS_AND_DECISIONS.md` — assumptions, risks, decisions, facts vs. judgement.

## The decision in one line

**Native Swift + SwiftUI (UI/HUD) + RealityKit (3D), targeting tvOS 26+ on
Apple TV 4K.** Input via **GameController** (Siri Remote + MFi/PS/Xbox). Build &
test on **GitHub-hosted macOS runners** with stock Xcode. Chosen over SceneKit
(deprecated) and Unity (heavyweight, AI/Git-unfriendly, poor fit for the
privacy/Kids constraints). Rationale + sources in `TECHNICAL_ARCHITECTURE.md`.

## Non-negotiable constraints (apply to all native-game work)

- **Child-first usability is a feature**, not later polish: minimal reading, big
  readable UI, spoken EN/ES guidance, immediate positive feedback.
- **No harsh failure.** A young child must never be able to "lose" or get stuck.
- **Privacy is a hard constraint:** **no** ads, analytics, accounts, chat, social
  features, in-app purchases, or external links visible to children. **No network
  dependency** for normal play. **All state stored locally.** Stay
  **Kids-Category compatible**.
- **No third-party runtime services.** Prefer first-party Apple frameworks.
- **Original IP only.** Do **not** use, imitate, or reference Tayo, Pixar/*Cars*,
  or any other property's names, designs, liveries, voices, or look. Any such
  reference in inherited files (e.g. `drive/MODELS.md`) is shorthand to be
  rewritten before informing final art (see `RISKS_AND_DECISIONS.md` D-IP-1).
- **Bilingual by construction.** Every player-facing line is a string id with
  both `en` and `es`. CI should fail if a translation is missing.
- **Works with Siri Remote alone**; controller is the *nicer* option, never
  required for the first playable story.
- **Data-driven where practical:** episodes, passengers, places, dialogue,
  rewards live in versioned **data** (JSON / localized strings), not hardcoded.

## Architecture rules for the native game

- Keep a **rendering-agnostic Game Core** (pure Swift, no RealityKit/SwiftUI
  imports) that is **unit-tested on CI without a GPU**. RealityKit/SwiftUI observe
  core state and send intents. This keeps gameplay testable and the engine
  swappable (SceneKit is the documented fallback if the RealityKit-on-tvOS spike
  fails — see R-ENG-1).
- Reference all 3D models by **id** with a **placeholder fallback**, so gameplay
  never waits on final art and art can be swapped without code changes
  (GLB authoring → USDZ runtime).
- Folder layout for the native app is specified in `TECHNICAL_ARCHITECTURE.md`
  (`AmeliaTV/` with `App/ Core/ Render/ Input/ Content/ Assets/ Tests/`).

## Development workflow

- Work proceeds through **small, reviewable GitHub issues/PRs**, each mapping to a
  `BACKLOG.md` item (reference the item ID, e.g. "Closes F1-02").
- **Two CI workflows:**
  - `ci-tvos` (every PR): macOS runner → build + unit-test on **tvOS Simulator**,
    validate content JSON against schemas, lint. **Never uses signing secrets.**
  - `release-tvos` (manual, protected): the **only** place Apple signing /
    App Store Connect / TestFlight secrets live; gated by a protected environment
    + manual approval. **Normal coding PRs must never touch these secrets.**
- Don't start work beyond the current phase's scope; respect the anti-bloat
  guardrails. A great small game beats a huge weak one.
- When uncertain about tvOS capabilities or tooling, **verify against official
  Apple/engine docs** and record facts vs. judgement in `RISKS_AND_DECISIONS.md`.

## Current status (updated 2026-06-20)

Phases 0–1 are merged to `main`; Phase 2 (the vertical slice) is well underway.
**How to test everything is in [`docs/tvos/TESTING.md`](docs/tvos/TESTING.md).**

### Done & merged to `main`
- **Phase 0 — planning** (PR #9): `docs/tvos/*` + this file.
- **Phase 1 — native foundation** (PR #9): `AmeliaTV/` scaffold (XcodeGen app +
  `AmeliaCore` Swift package), **secret-free `ci-tvos`** workflow (content
  validation + `swift test` + tvOS 26 Simulator build), and RealityKit /
  GameController / GLB→USDZ spikes. **CI confirmed RealityKit runs on tvOS 26**
  on GitHub-hosted macOS runners (Xcode 26.3 / tvOS 26.2 SDK) — R-ENG-1 de-risked.
- **Phase 2 — gameplay backbone** (PR #10): `RouteGraph` (pathfinding + turn
  cues), `TrafficLight`, `EpisodeRunner` (beat state machine), `DialogueDirector`,
  and the `Light` content model — all unit-tested.

### In review — green CI, **merge this first next session** (PR #11)
- **Phase 2 — `GameSession` + playable loop:** the orchestrator (Auto-Drive,
  episode events, rewards, local persistence), an `AVSpeech` speaker, and app
  wiring so the **`first-day` episode runs end to end**. A headless `swift test`
  plays the *real* episode to completion (reaches every target, boards the
  passenger, awards + persists stars/sticker/completion). All 3 CI checks green.

### What works today
- The Game Core logic of the whole slice loop is **functionally complete and
  unit-tested** (drive → bus stop → red-light stop → left/right choice →
  drop-off → home → reward), playable with a Siri Remote via Auto-Drive.
- The app builds for tvOS 26 and runs the episode with a **placeholder** bus on a
  green plane: it auto-drives the route, speaks (TTS, EN/ES), and shows a live
  subtitle + star count.

### Not done yet (the rest of Phase 2 — "make it look like the game")
- Real neighborhood **3D scene**: roads, bus-stop shelter, traffic light with lit
  lamps, park, garage, passenger (placeholder primitives are fine; USDZ later).
- **HUD**: big GO/STOP, pulsing turn arrow, destination beacon, minimap.
- **Garage + Mechanic Mom** intro scene and the **reward/sticker** screen.
- **Splash/language** polish (RootView is minimal today).
- ~~**Audio**: music themes + SFX (only TTS voice exists).~~ **A2-13 done:** a
  procedural `AVAudioEngine` synth (`App/Audio/ProceduralAudio.swift`) plays
  garage/driving/reward music beds, a speed-reactive engine hum, and a synthesized
  SFX set (horn, door, star sparkle, light chime, gentle bump, reward + sticker
  flourish), mixed below the TTS voice. The Core stays GPU/AV-free: `GameSession`
  emits `SoundCue`/`MusicTheme` intents through a `SoundPlayer` protocol
  (spy-tested headlessly). The remaining audio work is the *art-directed* pass
  (E3-03): real samples / hero voice swapped in behind the same ids.
- **Human play-test** on the tvOS Simulator / a real Apple TV (see TESTING.md).

## Next steps (start here next session)

1. **Merge PR #11** (green) so the playable loop is on `main`.
2. **Human smoke-test** per `docs/tvos/TESTING.md` (run the Simulator, press
   "Let's go", watch the bus auto-drive and talk). Capture anything that feels off.
3. Build the slice's presentation, smallest-first, each a own PR:
   - **A2-10 HUD** (GO/STOP, turn arrow from `GameSession.currentTurnCue`,
     star count, subtitle, beacon).
   - **A2-08 neighborhood scene** (roads + stop + light + park + garage as
     placeholders, positioned from `Content/places.json` / `lights.json`).
   - **A2-09 passenger** entity (board/exit at the stop).
   - **A2-07 garage + Mechanic Mom** intro; **A2-12 reward/sticker** screen.
   - **A2-13 audio** pass.
4. **A2-14 integration & acceptance pass** against `docs/tvos/VERTICAL_SLICE.md`.

## Outstanding questions / decisions (need the human)

These gate later work; recorded in full in `docs/tvos/RISKS_AND_DECISIONS.md`.
- **D-SIGN-1 — Apple Developer account / signing.** Needed to run on a *real*
  Apple TV and for Phase 5 TestFlight. Not needed for Simulator or CI. *Who owns
  the account? Provide secrets only to the future protected `release-tvos` env.*
- **D-ART-1 — art sourcing & reviewer.** AI-generated GLB→USDZ vs. commissioned,
  and who signs off on look/originality. Blocks final art, not gameplay.
- **D-IP-1 — ratify the original-IP rule** (no Tayo/Cars/Pixar likeness) before
  any art is generated.
- **Testing access:** do you have a Mac with **Xcode 26** (to run the Simulator),
  or should human testing wait until a TestFlight build (which needs D-SIGN-1)?
  This decides how we verify the presentation work — see TESTING.md.


## Web game notes (only if a task targets the web games)

- `index.html` is the whole space-themed PWA (no build step). `drive/` is the
  Three.js driving prototype (ES modules; Three.js vendored in `vendor/`).
- If you change `index.html` or assets, **bump the `CACHE` version in `sw.js`**.
- Deploys to GitHub Pages via `.github/workflows/deploy.yml` on push to `main`.
