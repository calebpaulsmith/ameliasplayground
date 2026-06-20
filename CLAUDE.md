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

## Current status

- **Phase 0 (planning):** this docs set + this file. **No native code yet** —
  implementation begins only after the plan is approved (see
  `RISKS_AND_DECISIONS.md` D-IMPL-START-1) and the first five issues (F1-01…F1-05)
  are created.

## Web game notes (only if a task targets the web games)

- `index.html` is the whole space-themed PWA (no build step). `drive/` is the
  Three.js driving prototype (ES modules; Three.js vendored in `vendor/`).
- If you change `index.html` or assets, **bump the `CACHE` version in `sw.js`**.
- Deploys to GitHub Pages via `.github/workflows/deploy.yml` on push to `main`.
