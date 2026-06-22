# How to bring back the 3D (RealityKit) app

The 3D RealityKit driving game is **archived, not deleted.** This is the insurance
doc so returning to it (or running it alongside the 2D game) is never a guessing
game.

## Where it lives
- **Source:** `AmeliaTV/Archive3D/App/` — the entire SwiftUI + RealityKit app
  (`AmeliaTVApp.swift`, `RootView.swift`, `Render/`, `UI/`, `Audio/`, `Input/`).
  It is **not compiled** by any target, so it can't break the 2D build.
- **History:** fully in git. The pivot commit *moved* these files (it didn't
  remove them); every prior version is reachable in the log and on `main` before
  the pivot.
- **Docs:** the original 3D plan is intact — `TECHNICAL_ARCHITECTURE.md`,
  `VERTICAL_SLICE.md`, and the 3D status in `CLAUDE.md`'s history section.

## What's shared (so restoring is cheap)
Both apps sit on the **same `AmeliaCore` package** (driving/episodes/dialogue/
rewards/save/strings) and the **same signing + TestFlight pipeline**
(`fastlane/`, `release-testflight.yml`). Restoring the 3D app is a **project +
app-shell** change, not a re-platforming.

## To restore (two paths)

**A) Replace the 2D app with the 3D app again**
1. Move the shell back: `git mv AmeliaTV/Archive3D/App AmeliaTV/App` (after moving
   the current 2D `App/` aside, e.g. to `Archive2D/`).
2. `xcodegen generate` (the `project.yml` `AmeliaTV`/`AmeliaPad` targets already
   point at `App/`).
3. Build for the tvOS Simulator; the archived code targeted tvOS 26 / RealityKit
   and built green before archival.

**B) Ship both, side by side (if they become separate products)**
1. Keep `Archive3D/App` where it is; add a **new app target** in `project.yml`
   (e.g. `AmeliaTV3D`) whose `sources:` point at `Archive3D/App`, with its **own
   bundle id**.
2. Give it its own scheme and (for release) its own App Store record.
3. Both targets share `AmeliaCore`; only the render/shell differs.

## Caveats
- The archive may have absorbed `main`'s later 3D tweaks during merges — harmless,
  it's not compiled, but re-read before trusting.
- Re-verify against the **current** Xcode/tvOS SDK; tooling moves (see
  `RISKS_AND_DECISIONS.md` F-1/F-2).
- The reason we left 3D stands (see `PLAN_2D.md` Part 0): don't restore it without
  a real plan to **see** it — the same broken-feedback-loop trap is waiting.
