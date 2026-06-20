# Amelia's Bus Adventure — Technical Architecture

> Status: **Planning (Phase 0)**. This document recommends **one** primary
> implementation approach and explains why, then sketches the project structure,
> data model, and dev/CI workflow. It distinguishes **confirmed facts**
> (with sources) from **recommendations/judgement**.
>
> **Confirmed facts** are tagged `[FACT]` with a source. Everything else is a
> recommendation for *this* game and may be revised as we learn.

## TL;DR recommendation

**Build a native tvOS app in Swift, using SwiftUI for menus/HUD and RealityKit
for the 3D world, targeting tvOS 26+ on Apple TV 4K. Input via the
GameController framework (Siri Remote + MFi/PS/Xbox). Build & test on
GitHub-hosted macOS runners with stock Xcode; isolate signing/TestFlight behind
a separate, manually-approved release workflow.**

This is recommended over **SceneKit** (deprecated — a dead end for a new
flagship) and **Unity** (powerful but heavyweight, AI/Git-unfriendly, and a poor
fit for the Kids-Category, no-third-party-runtime, "diff-reviewable" constraints
of this specific project).

---

## The decision: engine / framework

### Candidates evaluated

| Approach | Native tvOS | 3D maturity for games | Diff/AI-friendly | 3rd-party runtime | Cross-Apple later |
|---|---|---|---|---|---|
| **Swift + RealityKit + SwiftUI** (recommended) | First-class | Newer on tvOS, improving | Excellent (plain Swift) | None | Trivial (same APIs) |
| Swift + SceneKit + SwiftUI | First-class | Mature but **deprecated** | Excellent | None | Yes, but on a dead framework |
| Unity | Supported | Excellent / industry-leading | Poor (binary/YAML scenes) | Heavy (Unity runtime) | Excellent |

### Confirmed facts behind the table

- `[FACT]` **SceneKit is soft-deprecated.** At WWDC 2025 ("Bring your SceneKit
  project to RealityKit," session 288) Apple put SceneKit into maintenance mode
  (critical bug fixes only, no new features) and named **RealityKit** as its
  successor for new apps and significant updates.
  Sources: <https://developer.apple.com/videos/play/wwdc2025/288/>,
  <https://developer.apple.com/documentation/scenekit/>
- `[FACT]` **RealityKit is now supported on tvOS** (tvOS 26.0+), on Apple TV 4K
  models — enabling native 3D/RealityKit experiences on Apple TV for the first
  time. Source: <https://developer.apple.com/videos/play/wwdc2025/287/> ("What's
  new in RealityKit," WWDC25), <https://developer.apple.com/documentation/realitykit/>
- `[FACT]` **Unity supports tvOS as a build target**, but does not support a
  single Xcode project containing both iOS and tvOS targets, and ships its own
  runtime/plugins. Sources:
  <https://docs.unity3d.com/2020.1/Documentation/Manual/tvOS.html>,
  <https://discussions.unity.com/t/build-app-for-both-tvos-and-ios-in-a-single-xcode-project/942175>,
  <https://github.com/apple/unityplugins>
- `[FACT]` **The GameController framework** models the Siri Remote
  (`GCMicroGamepad` / extended remote) and MFi/PlayStation/Xbox controllers on
  tvOS, giving one API for all of them. Source:
  <https://developer.apple.com/documentation/gamecontroller>
- `[FACT]` **GitHub-hosted macOS runners include Xcode** and can run
  `xcodebuild` for tvOS simulator builds/tests. Source:
  <https://github.com/actions/runner-images>

### Why RealityKit + SwiftUI is right for *this* game (recommendation)

1. **It's the only forward-looking native option.** Building a *new flagship* on
   SceneKit means starting on a deprecated framework. RealityKit is Apple's
   declared 3D future and `[FACT]` now runs on tvOS — so we get the long-term
   bet without leaving the platform's first-party stack.
2. **No third-party runtime — best fit for the privacy/Kids constraints.** The
   product vision forbids ads/analytics/accounts and wants Kids-Category
   compatibility and "independent from third-party services at runtime." A pure
   Apple stack has **zero** bundled SDKs that could phone home, no extra privacy
   manifests to police, and the smallest attack surface. Unity adds a runtime and
   an ecosystem of SDKs we'd have to keep clean.
3. **Plain-text, diff-reviewable code — ideal for Claude Code + GitHub PRs.**
   The whole game is Swift source + JSON/USDZ assets. PRs are readable line
   diffs that a human can review. Unity's scenes/prefabs are binary or
   merge-hostile YAML that AI agents and humects review poorly, and that GitHub
   can't render meaningfully.
4. **Performance & install size on Apple TV.** A native Metal-backed RealityKit
   app for a low-poly cozy world is light, launches fast, and is easy to keep at
   a steady frame rate on Apple TV 4K — well-suited to a young audience and a
   small download. Unity's footprint is larger for a game this simple.
5. **First-class input.** GameController `[FACT]` gives Siri Remote *and*
   controllers through one API, exactly matching our "remote-friendly, controller
   if you have one" model — no plugins required.
6. **Asset pipeline is clean.** RealityKit's native format is **USDZ**; our
   target authoring format is **glTF/GLB**, converted to USDZ at import (see
   Asset Pipeline below). This is a well-trodden path and keeps assets swappable.
7. **Future iPad/iPhone is nearly free.** SwiftUI + RealityKit are the same APIs
   across Apple platforms, so an iPad/iPhone build is mostly input + layout work,
   not a re-engine.
8. **Maintainable by a solo creator with AI assistance.** One language (Swift),
   one toolchain (Xcode), no license tier to manage, no engine version churn
   beyond Xcode/tvOS SDK updates.

### Honest trade-offs of the recommendation (see `RISKS_AND_DECISIONS.md`)

- `[FACT-derived]` **RealityKit on tvOS is new (tvOS 26).** Minimum device is
  **Apple TV 4K** and the framework is **less battle-tested for games** than
  Unity or even SceneKit. We accept a higher minimum OS and some "early-adopter"
  rough edges in exchange for being on the right long-term framework. (Risk
  R-ENG-1.)
- RealityKit is **ECS-oriented** and historically AR-centric; some "game engine"
  conveniences (built-in character controllers, a scene editor as rich as
  Unity's) are thinner. We mitigate with a small custom gameplay layer (below)
  and Reality Composer Pro for scene assembly.
- If, during the Phase-1 spike, RealityKit on tvOS proves to block the slice
  (e.g. a critical missing capability), the **documented fallback** is
  **SceneKit** (still fully functional, mature, well-documented, lower min-OS) —
  *not* Unity. See R-ENG-1 mitigation.

### Why not Unity (despite being the most capable engine)

Unity would absolutely *work* and is the strongest pure 3D engine. We decline it
for this project because: it conflicts with the no-third-party-runtime / Kids
posture; its binary/YAML project format is hostile to AI-authored,
human-reviewed GitHub PRs (the core dev workflow); it's heavier than this small
cozy game needs; it adds licensing and version-management overhead for a solo
creator; and its tvOS toolchain has known friction `[FACT]`. The capability
upside doesn't pay for the workflow and constraint downsides *here*.

---

## High-level architecture

A thin, testable **game/simulation core** in pure Swift, rendered by RealityKit,
fronted by SwiftUI, fed by GameController input, and driven by **data** (episodes,
passengers, places, strings) loaded from bundle resources.

```
┌─────────────────────────────────────────────────────────────┐
│ SwiftUI App shell                                            │
│  • Splash / language screen   • Garage UI / adventure board  │
│  • HUD overlay (GO/STOP, arrows, minimap, stars)             │
│  • Parent settings (gated)                                    │
└───────────────▲───────────────────────────┬─────────────────┘
                │ observes (state)           │ sends (intents)
┌───────────────┴───────────────────────────▼─────────────────┐
│ Game Core (pure Swift, no rendering deps — unit-testable)    │
│  • GameState / SaveStore (local, Codable)                    │
│  • EpisodeRunner (beats: say/driveTo/pickup/dropoff/...)     │
│  • DrivingModel + AssistLevels (auto / assisted / free)      │
│  • RouteGraph + Navigation (nodes/edges, turn cues)          │
│  • Traffic + Signs (light cycles, rules, teaching)           │
│  • Rewards/Economy (stars, stickers, unlocks)                │
│  • DialogueService (line ids → speech + subtitle)            │
│  • InputState (device-agnostic intents)                      │
└───────────────▲───────────────────────────┬─────────────────┘
                │                            │
┌───────────────┴──────────┐   ┌────────────▼─────────────────┐
│ GameController (input)    │   │ RealityKit (3D presentation) │
│  Siri Remote + MFi/PS/Xbox│   │  Scenes, entities, anims,    │
│  → device-agnostic intents│   │  camera, materials, audio    │
└───────────────────────────┘   │  Assets: USDZ (← GLB import) │
                                 └──────────────────────────────┘
```

**Key boundary:** the **Game Core is rendering-agnostic**. It knows the bus is at
`(x, z)` heading `θ` with assist level *L*; it does **not** know about RealityKit
entities. RealityKit and SwiftUI *observe* core state and *send* intents. This
keeps gameplay unit-testable on CI without a GPU **and** preserves the SceneKit
fallback (only the presentation layer would change).

## Data model (everything data-driven)

Content lives in bundled resources, authored as JSON + localized strings +
asset references — never hardcoded.

- `Strings` — `en`/`es` per id (port of [`drive/i18n.js`](../../drive/i18n.js)
  `STR`). Stored as JSON or `.lproj` `.strings`.
- `Place` — `{ id, name(id), kind, position, beaconColor }`.
- `Passenger` — `{ id, name(id), homePlace, color/identity, lines[], modelRef }`.
- `Episode` — `{ id, title(id), neighborhood, beats[], rewards }`.
- `Beat` — tagged union: `say`, `driveTo`, `pickup`, `dropoff`, `lightStop`,
  `choice`, `cutscene`, `reward` (generalizes [`drive/missions.js`](../../drive/missions.js)).
- `Neighborhood` — road graph (nodes/edges), place anchors, bus stops, lights,
  signs, set dressing.
- `Cosmetic` / `Decoration` — `{ id, kind, cost(stars), assetRef }`.
- `SaveSlot` — `{ name, language, assistLevel, stars, unlocked[], stickers[],
  cosmetics[], episodeProgress }`, persisted locally via `Codable` (see Save).

A JSON schema for each type lives alongside the data so Claude can author content
PRs that are validated in CI.

## Input model

One **device-agnostic intent layer** the Game Core consumes, populated by
GameController `[FACT]`:

| Intent | Siri Remote | Controller |
|---|---|---|
| GO / forward | Click / swipe up / Play-Pause | A / right trigger |
| STOP / brake | Click STOP target / swipe down | B / left trigger |
| Steer left/right | Clickpad left/right | Left stick / d-pad |
| Choose left/right (at `choice`) | Clickpad left/right | d-pad / stick |
| Honk | Play/Pause or dedicated button | X / Y |
| Confirm / Back (menus) | Select / Menu | A / B |

The **assist level** decides how much "steer" the player must supply vs.
auto-drive — so the *same intents* serve a 3-year-old on a remote and a parent on
a stick (see `GAME_DESIGN.md` §6). The current input device can also pick a
sensible default assist level.

## Asset pipeline (GLB → USDZ, swappable)

- **Authoring/interchange format:** glTF 2.0 / **GLB** (what AI generators and
  the existing prototype already target — see
  [`drive/MODELS.md`](../../drive/MODELS.md)).
- **Runtime format:** **USDZ** (RealityKit native). Convert GLB→USDZ at import
  via Apple's tooling (Reality Converter / `usdz` tooling) or a build step.
- **Swappability is a requirement:** every model is referenced by **id**; the
  game must run with **placeholder primitive/low-poly stand-ins** and swap in
  final USDZ when present — mirroring the prototype's "primitive fallback if the
  GLB is missing" design in [`drive/assets.js`](../../drive/assets.js). This lets
  gameplay land before final art.
- **Scene assembly:** use **Reality Composer Pro** for hand-placing neighborhood
  set dressing and authoring simple animations/materials, exported for the app.
- **Budgets:** keep models low-poly (target a few thousand tris each), bake
  materials, atlas textures — to hold a steady frame rate on Apple TV 4K.

## Save / persistence

- **Local only**, no network. Store the `SaveSlot` model as `Codable` JSON in the
  app's Application Support / Documents directory (or `UserDefaults` for tiny
  prefs). No iCloud in v1 (avoids accounts/sync complexity; revisit later behind
  an explicit decision).
- Multiple **named slots**. Writes are atomic; a corrupt slot falls back to a
  fresh slot rather than crashing.

## Audio

- **Voice (v1):** on-device text-to-speech via `AVSpeechSynthesizer` (the native
  analog of the prototype's Web Speech use), selecting an `en`/`es` voice and a
  bright, kid-friendly pitch.
- **Later:** pre-recorded clips for Amelia/Mom, with TTS fallback. Music/SFX via
  RealityKit spatial audio or `AVAudioEngine`; mix keeps **voice intelligible
  above all**.

## Project / folder structure (recommendation)

The **existing web game stays untouched** at the repo root / `drive/`. The native
game lives in its own top-level directory so the two never collide.

```
ameliasplayground/                 # existing repo
├─ index.html, drive/, vendor/...  # EXISTING web game — DO NOT TOUCH
├─ docs/tvos/                       # this planning set
├─ CLAUDE.md                        # project-wide guidance (this PR)
└─ AmeliaTV/                        # NEW native tvOS game (added in Phase 1)
   ├─ AmeliaTV.xcodeproj           #   (or a Swift Package + thin xcodeproj)
   ├─ App/                          #   SwiftUI app shell, scenes, HUD
   ├─ Core/                         #   pure-Swift Game Core (unit-tested)
   │   ├─ Episodes/  Driving/  Navigation/  Rewards/  Dialogue/  Save/
   ├─ Render/                       #   RealityKit presentation layer
   ├─ Input/                        #   GameController → intents
   ├─ Content/                      #   data-driven game content
   │   ├─ episodes/*.json  passengers.json  places.json
   │   ├─ strings/en.json  strings/es.json
   │   └─ schema/*.json             #   JSON schemas (validated in CI)
   ├─ Assets/                       #   USDZ models, RC Pro scenes, audio
   │   └─ source-glb/               #   GLB sources (converted to USDZ)
   ├─ Resources/                    #   icons, app metadata
   └─ Tests/                        #   unit tests for Core
```

> Note: keeping `AmeliaTV/` as a separate directory in the **same repo** is the
> default. A separate repository is a viable alternative (cleaner CI isolation)
> and is recorded as an open decision in `RISKS_AND_DECISIONS.md` (D-REPO-1).

## Build, test & CI workflow

Two clearly separated GitHub Actions workflows so **normal coding PRs never touch
Apple signing credentials**:

1. **`ci-tvos` (every PR/push):** on a GitHub-hosted **macOS runner** `[FACT]`,
   select Xcode, then:
   - validate content JSON against schemas,
   - `xcodebuild build`/`test` for the **tvOS Simulator** (no signing needed),
   - run Game Core **unit tests** (pure Swift, no GPU),
   - lint (SwiftFormat/SwiftLint).
   This gives Claude-authored PRs a green/red signal with **no secrets**.
2. **`release-tvos` (manual, protected):** gated behind a protected environment
   with **manual approval** and the only place Apple **signing certs /
   App Store Connect / TestFlight** secrets live. Archives, signs, and uploads to
   TestFlight. Triggered intentionally, not on every PR.

This satisfies the constraint that *signing/TestFlight is isolated behind
protected release secrets and manual approval, and normal coding PRs never access
Apple signing credentials.*

> `[FACT]` GitHub-hosted macOS runners can build/test tvOS via `xcodebuild`.
> Simulator builds need no signing; device/TestFlight builds need signing
> secrets, which is exactly why they're isolated in the release workflow.

## Performance targets (recommendation)

- **Resolution:** render well at 1080p and 4K on Apple TV 4K.
- **Frame rate:** steady 60 fps target for the cozy low-poly world; never let it
  hitch during a child's drive.
- **Launch:** fast cold start to the splash/garage (a young child won't wait).
- **Memory/size:** keep the install small via low-poly atlased assets and TTS
  (no shipped voice audio) in v1.

## Open technical questions (tracked in `RISKS_AND_DECISIONS.md`)

- Minimum tvOS / device floor (Apple TV 4K + tvOS 26 implied by RealityKit) —
  confirm acceptable. (D-MINOS-1)
- Same-repo `AmeliaTV/` vs. separate repository. (D-REPO-1)
- Xcode project vs. Swift Package-first layout. (D-PROJ-1)
- RealityKit-on-tvOS spike must validate: scene loading, camera follow, custom
  per-frame gameplay update, GLB→USDZ assets, GameController on a real Apple TV.
  (R-ENG-1)
