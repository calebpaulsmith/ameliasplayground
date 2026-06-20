# AmeliaTV — native Apple TV game (Phase 1 foundation)

This is the native **tvOS** implementation of *Amelia's Bus Adventure*. The plan
and rationale live in [`../docs/tvos/`](../docs/tvos/). The existing web games at
the repo root and in [`../drive/`](../drive/) are **separate and untouched**.

> **Status: Phase 1 (foundation).** This is the project skeleton + a
> rendering/input spike, **not** the playable game. The vertical slice is Phase 2
> (see `../docs/tvos/VERTICAL_SLICE.md`).

## What's here

```
AmeliaTV/
├─ Package.swift              # Swift package: AmeliaCore (pure-Swift Game Core)
├─ project.yml                # XcodeGen spec for the tvOS app target
├─ Sources/AmeliaCore/        # rendering-agnostic core (no RealityKit/SwiftUI)
│   ├─ Math/ Input/ Driving/ Save/ Content/ Localization/  GameCore.swift
├─ Tests/AmeliaCoreTests/     # unit tests (run on CI without a GPU)
├─ App/                       # tvOS app: SwiftUI shell + RealityKit + input
│   ├─ AmeliaTVApp.swift RootView.swift
│   ├─ Render/  (DriveSpikeView, ModelLibrary)
│   └─ Input/   (GameControllerInput)
├─ Content/                   # data-driven content (bundled into the app)
│   ├─ strings/{en,es}.json  places.json  passengers.json  episodes/*.json
│   └─ schema/                # JSON schemas (reference) — enforced by the validator
└─ Tools/validate_content.py  # bilingual + reference validator (CI + local)
```

## Engine decision (one line)

Native **Swift + SwiftUI (UI/HUD) + RealityKit (3D)**, **tvOS 26+ / Apple TV 4K**,
input via **GameController**. Full rationale + sources:
[`../docs/tvos/TECHNICAL_ARCHITECTURE.md`](../docs/tvos/TECHNICAL_ARCHITECTURE.md).

## Build & test

Requires macOS + Xcode (tvOS 26 SDK). The Game Core also tests on any platform
with a Swift toolchain.

```bash
# 1. Validate content (no deps; runs anywhere with Python 3)
python3 Tools/validate_content.py

# 2. Unit-test the Game Core (no GPU / simulator needed)
swift test

# 3. Generate the Xcode project and build the app for the tvOS Simulator
brew install xcodegen
xcodegen generate
open AmeliaTV.xcodeproj            # or:
xcodebuild build -project AmeliaTV.xcodeproj -scheme AmeliaTV \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO
```

> `AmeliaTV.xcodeproj` is **generated** by XcodeGen and is intentionally **not**
> committed — the source of truth is `project.yml`. This keeps the project
> definition a small, reviewable diff (no churny `.pbxproj`).

## Architecture rules (enforced by structure)

- **`AmeliaCore` imports no RealityKit/SwiftUI/GameController** — gameplay is
  unit-testable on CI without a GPU, and the engine stays swappable (SceneKit is
  the documented fallback; see `RISKS_AND_DECISIONS.md` R-ENG-1).
- **Everything player-facing is a bilingual string id.** `validate_content.py`
  and `ContentLoaderTests` fail the build if a translation is missing.
- **Models are referenced by id with a placeholder fallback** (`ModelLibrary`):
  drop `bus.usdz` (etc.) into the bundle later to upgrade art with no code change.

## CI

Two workflows (see `../.github/workflows/`):

- **`ci-tvos`** (this phase): content validation + `swift test` + Simulator
  build. **No signing secrets.**
- **`release-tvos`** (Phase 5, not yet added): the only place Apple
  signing/TestFlight secrets will live, behind a protected, manually-approved
  environment.
