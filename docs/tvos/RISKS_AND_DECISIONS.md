# Amelia's Bus Adventure — Risks, Assumptions & Decisions

> Status: **Planning (Phase 0)**. This is the honest ledger: what we **assume**,
> what we're **unsure** of, the **risks** we're taking, and the **decisions** that
> need a human. Per the working rules, major assumptions are listed here rather
> than made silently, and **confirmed facts** are separated from **judgement**.

## Confirmed facts (with sources)

These were verified against official/primary sources during planning (June 2026).

- **F-1 — SceneKit is soft-deprecated.** WWDC 2025 session 288 ("Bring your
  SceneKit project to RealityKit"): SceneKit is in maintenance mode (critical
  bug fixes only, no new features); RealityKit is the recommended successor for
  new apps. Apps still run; no hard-removal announced.
  Sources: <https://developer.apple.com/videos/play/wwdc2025/288/>,
  <https://developer.apple.com/documentation/scenekit/>
- **F-2 — RealityKit now runs on tvOS (tvOS 26+).** WWDC 2025 "What's new in
  RealityKit" (session 287) and the RealityKit docs indicate RealityKit support
  extended to Apple TV with tvOS 26 on Apple TV 4K hardware.
  Sources: <https://developer.apple.com/videos/play/wwdc2025/287/>,
  <https://developer.apple.com/documentation/realitykit/>
- **F-3 — Unity supports tvOS** as a build target but cannot produce one Xcode
  project with both iOS and tvOS targets, and ships its own runtime/plugins.
  Sources: <https://docs.unity3d.com/2020.1/Documentation/Manual/tvOS.html>,
  <https://discussions.unity.com/t/build-app-for-both-tvos-and-ios-in-a-single-xcode-project/942175>,
  <https://github.com/apple/unityplugins>
- **F-4 — GameController framework** abstracts the Siri Remote and MFi/PS/Xbox
  controllers under one API on tvOS.
  Source: <https://developer.apple.com/documentation/gamecontroller>
- **F-5 — GitHub-hosted macOS runners include Xcode** and run `xcodebuild` for
  tvOS Simulator builds/tests (simulator builds need no signing).
  Source: <https://github.com/actions/runner-images>

> These should be **re-verified at the start of Phase 1** against the then-current
> Xcode/tvOS SDK, since tooling moves fast.

## Assumptions (stated, not silently made)

- **AS-1** The target household has at least one **Apple TV 4K** (required for
  RealityKit per F-2). If only an older **Apple TV HD** is available, the engine
  choice must be revisited (likely SceneKit fallback). *Needs confirmation —
  see D-MINOS-1.*
- **AS-2** On-device **TTS** quality (English + Spanish) is good enough for a warm
  v1 voice; recorded hero lines come later. *Validate during A2-02.*
- **AS-3** Requiring **tvOS 26+** is acceptable for a private/family-first launch.
- **AS-4** **AI-generated GLB** art (per the existing `drive/MODELS.md` workflow),
  converted to USDZ, can reach an acceptable, cohesive, *original* look. *Validate
  in Phase 3; see D-ART-1.*
- **AS-5** A solo creator + Claude Code can carry a native Swift/RealityKit
  project through GitHub PRs with cloud macOS CI **without owning a Mac** for
  normal development (device-only verification — real-hardware feel/art — is the
  exception and needs a human + device).
- **AS-6** The family has (or will obtain) an **Apple Developer account** for the
  eventual TestFlight/release pipeline. Not needed for Phase 1–2 simulator CI.
  *See D-SIGN-1.*
- **AS-7** "Private/family-first" means **no public listing** initially; the code
  may live in a private or public repo regardless, but **no secrets** are ever
  committed and signing is isolated (R5-01).

## Risks & mitigations

### R-ENG-1 — RealityKit on tvOS is new and less game-proven *(High impact)*
- **Risk:** RealityKit on tvOS (F-2) is recent and historically AR-centric; it
  may lack a game convenience we need, or have rough edges, vs. mature
  SceneKit/Unity. Min device rises to Apple TV 4K.
- **Mitigation:** **Phase 1 spike (F1-04/F1-05/F1-06) de-risks this before any
  gameplay is built** — prove scene loading, follow camera, per-frame update,
  GLB→USDZ assets, and GameController on real Apple TV. The rendering-agnostic
  **Game Core** boundary means presentation can be swapped without rewriting
  gameplay.
- **Documented fallback:** if the spike shows RealityKit-on-tvOS blocks the
  slice, fall back to **SceneKit** (mature, lower min-OS, still fully functional
  despite F-1) — **not** Unity. Re-evaluate before Phase 2.

### R-PERF-1 — Frame rate / readability on a real 4K TV *(Medium)*
- **Risk:** looks fine in Simulator but hitches or reads poorly on a real TV.
- **Mitigation:** strict low-poly/atlas budgets; performance + couch-readability
  passes (R5-03); test on real hardware early in Phase 2.

### R-UX-1 — Siri-Remote-only driving feels bad *(Medium-High)*
- **Risk:** the remote can't deliver satisfying driving; the youngest can't play
  solo.
- **Mitigation:** the **Auto-Drive assist level** makes the remote sufficient by
  design (driving = decisions, not analog steering); controller is the *nicer*
  option, never required. Validate feel in A2-04/A2-10 on device.

### R-VOICE-1 — TTS sounds cold or mispronounces Spanish names *(Medium)*
- **Risk:** TTS undermines the "warm show" tone; mispronounces e.g. "Tomás."
- **Mitigation:** tune voice/pitch/rate; allow per-line pronunciation overrides;
  plan recorded hero lines in Phase 3 (E3-03).

### R-IP-1 — Accidental imitation of existing IP *(High — legal/brand)*
- **Risk:** inherited prototype prompts reference Tayo/Pixar Cars; final art
  could drift into imitation.
- **Mitigation:** see **D-IP-1**; rewrite all art prompts to be original; human
  art review (E3-02) explicitly checks for non-imitation before anything ships.

### R-CI-1 — Cloud macOS CI cost/flakiness *(Low-Medium)*
- **Risk:** macOS runner minutes are costlier/slower; Xcode version drift breaks
  builds.
- **Mitigation:** keep CI fast (unit tests + simulator build only); pin Xcode
  where possible; cache deps; reserve signed device builds for the manual
  release workflow.

### R-SCOPE-1 — Feature creep / "huge weak game" *(Medium)*
- **Risk:** adding systems before the slice is fun.
- **Mitigation:** the anti-bloat guardrails (`GAME_DESIGN.md`); nothing past the
  slice scope starts until `VERTICAL_SLICE.md` acceptance is met.

### R-CONTENT-1 — Bilingual drift *(Low-Medium)*
- **Risk:** a line ships in one language only.
- **Mitigation:** every line is an id with both `en`/`es`; CI schema check fails
  the build if a translation is missing.

## Decisions needed from the human (before/early in Phase 1)

> These are **judgement calls for the owner**, not facts. Recommendations given;
> the owner decides.

- **D-MINOS-1 — Minimum OS / device floor.**
  *Recommendation:* **tvOS 26+, Apple TV 4K minimum** (implied by RealityKit,
  F-2). *Decide:* acceptable? Or must we support Apple TV HD (→ SceneKit)?
- **D-REPO-1 — Repo layout.**
  *Recommendation:* keep the native game as `AmeliaTV/` **in this repo**
  (web game untouched). *Alternative:* a separate repo for cleaner CI/signing
  isolation. *Decide:* same-repo vs. new repo.
- **D-PROJ-1 — Project format.**
  *Recommendation:* a thin **Xcode project** wrapping a Swift-Package **Core**
  (best of both: GUI-debuggable app + package-testable core). *Decide:* confirm.
- **D-SIGN-1 — Apple Developer account & signing.**
  *Recommendation:* not needed for Phase 1–2 (simulator CI). Needed for Phase 5
  release. *Decide:* who owns the account; supply secrets only into the protected
  release environment.
- **D-ART-1 — Art sourcing & review.**
  *Recommendation:* AI-generated low-poly **GLB → USDZ** for v1, with a human art
  review per asset for quality + originality. *Alternative:* commission art.
  *Decide:* sourcing path + who signs off on art.
- **D-IP-1 — Original IP enforcement.**
  *Decision (proposed, please ratify):* **all** references to Tayo/Pixar/Cars
  (incl. in `drive/MODELS.md`) are reference-only and must be rewritten to an
  original brief before informing final art; Amelia gets her own name, palette,
  face, and silhouette. *Decide:* ratify.
- **D-VOICE-1 — Voice strategy.**
  *Recommendation:* TTS for v1, recorded hero lines in Phase 3. *Decide:* confirm
  (and who would record, if anyone).
- **D-IMPL-START-1 — When to start coding.**
  This planning PR is **documentation only** per the task. *Decide:* approve the
  plan and the first five issues (below) to begin Phase 1.

## Decisions already made in this plan (recorded)

- **DM-1** Primary engine: **Swift + RealityKit + SwiftUI** (over SceneKit and
  Unity). Rationale in `TECHNICAL_ARCHITECTURE.md`.
- **DM-2** **Game Core is rendering-agnostic** (pure Swift, unit-tested) to keep
  gameplay testable and the engine swappable.
- **DM-3** Everything **data-driven** (episodes/passengers/places/strings as JSON
  + localized strings).
- **DM-4** **Two CI workflows**: secret-free `ci-tvos` for all PRs; protected,
  manual `release-tvos` for signing/TestFlight.
- **DM-5** **Web game stays untouched**; native game in `AmeliaTV/`.
- **DM-6** **Privacy posture is a hard constraint**, not a preference (no ads/
  analytics/accounts/chat/IAP/network; local-only saves; Kids-Category aligned).

## First five implementation issues to create next

(Pending **D-IMPL-START-1** approval. These map to the backlog.)

1. **F1-01** — Scaffold native tvOS app `AmeliaTV/`.
2. **F1-02** — `ci-tvos` GitHub Actions workflow (build + test on tvOS
   Simulator, schema validation, lint; **no secrets**).
3. **F1-03** — Game Core module skeleton + first unit test.
4. **F1-04** — RealityKit-on-tvOS rendering spike (de-risk R-ENG-1).
5. **F1-05** — Input layer: GameController → device-agnostic intents (Siri Remote
   + controller).
