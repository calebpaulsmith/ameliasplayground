# Amelia's Bus Adventure — Testing Plan

> How to verify the native tvOS game at each layer. Written for picking the work
> back up across sessions. Status as of 2026-06-20 (Phase 2 in progress).

There are **three layers of testing**, from "works anywhere" to "needs a Mac /
Apple TV". Most of our correctness is provable at layer 1, which is why the
gameplay lives in a rendering-agnostic Core.

---

## Layer 1 — Automated, runs anywhere / in CI (no Mac UI needed)

These run on every PR via `.github/workflows/ci-tvos.yml` and you can run them
locally too.

### 1a. Content validation (no toolchain — just Python 3)
```bash
python3 AmeliaTV/Tools/validate_content.py
```
Checks **bilingual parity** (every string id has `en` + `es`, non-empty) and that
all references resolve (passenger→place, episode beats→places/passengers/lights).
Should print `✅ content valid`.

### 1b. Game Core unit tests (needs a Swift toolchain; no GPU/Simulator)
```bash
cd AmeliaTV && swift test
```
Covers vectors, input, assist levels, save store, localizer, route graph + turn
cues, traffic-light cycle, dialogue de-dup, the episode runner, and — most
importantly — **a full headless playthrough of the real `first-day` episode**
(`GameSessionTests.testFirstDayPlaythroughCompletesUnderAutoDrive`): it drives
the bus to every target, boards the passenger, and asserts stars + sticker +
completion are awarded and persisted. **This is our proof the slice loop works.**

### 1c. tvOS app build (needs macOS + Xcode 26)
```bash
cd AmeliaTV && brew install xcodegen && xcodegen generate
xcodebuild build -project AmeliaTV.xcodeproj -scheme AmeliaTV \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO
```
Confirms the SwiftUI + RealityKit + GameController code compiles for tvOS 26.
**CI already does 1a–1c on every PR** (macos-15 runner, Xcode 26).

> When adding gameplay, **add a Core unit test for it** before/with the UI, so it
> stays provable at layer 1. New player-facing lines must be added in **both**
> languages or 1a fails.

---

## Layer 2 — Manual play-test on the tvOS Simulator (needs a Mac + Xcode 26)

This is how a human actually *sees and plays* it. Requires macOS with Xcode 26
(for the tvOS 26 SDK). **No Apple Developer account needed** for the Simulator.

1. `cd AmeliaTV && xcodegen generate && open AmeliaTV.xcodeproj`
2. Pick an **Apple TV** Simulator destination; Run (⌘R).
3. Drive the Siri Remote in the Simulator: **Editor ▸ Hardware ▸ Siri Remote**
   (or the on-screen remote / a paired game controller). Arrow/clickpad = move &
   left/right; the touch surface click = select.

### What to expect *today* (placeholder art)
- Title screen → choose **English/Español** → **Let's go!**
- A blue **placeholder box bus** on a green plane **auto-drives** the route,
  **speaks** the lines (TTS) in the chosen language, and shows a **subtitle +
  star count**; at the fork press **left/right**; it finishes with a completion
  line. (Roads, buildings, stop, light, passenger, HUD arrows, garage and reward
  screens are **not built yet** — that's the next work.)

### Manual play-test checklist (grows toward the slice acceptance bar)
Map to `VERTICAL_SLICE.md`. Today only the ticked items are expected to pass:
- [x] App launches to a title + single Play action.
- [x] Language choice works and is spoken.
- [x] Episode runs: bus moves to targets, passenger boards, stars awarded.
- [x] Every line is spoken + subtitled in EN **and** ES.
- [x] Completion screen/line + stars; progress persists across relaunch.
- [ ] Looks like a neighborhood (roads/stop/light/park/garage). *(A2-08)*
- [ ] Big readable HUD with turn arrow + beacon, couch-legible. *(A2-10)*
- [ ] Garage + Mechanic Mom intro. *(A2-07)*  Reward/sticker screen. *(A2-12)*
- [ ] Completable with **only** the Siri Remote, no reading, no adult help.
- [ ] No failure state anywhere (wrong turn / missed stop just re-prompts).
- [ ] Music + SFX present, voice always intelligible. *(A2-13)*

> Tip: to force the **red-light teaching moment** while testing, the light cycle
> is green→yellow→red on a 14s loop (`light1`, phase 0). Arrive while it's red to
> see the stop/praise; arriving on green simply proceeds (by design, no failure).

---

## Layer 3 — On a real Apple TV 4K (needs Apple Developer signing — later)

Running on hardware (and TestFlight for family testing) needs an Apple Developer
account and signing. Per `CLAUDE.md`, signing lives **only** in the future
protected `release-tvos` workflow — never in `ci-tvos` or normal PRs. **Blocked on
decision D-SIGN-1.** This is a Phase 5 concern; we don't need it to keep building
and verifying the slice via layers 1–2.

---

## Quick reference

| I want to… | Do this | Needs |
|---|---|---|
| Check content is valid + bilingual | `python3 AmeliaTV/Tools/validate_content.py` | Python 3 |
| Prove gameplay logic works | `cd AmeliaTV && swift test` | Swift toolchain |
| Confirm the app compiles for tvOS | `xcodegen generate` + `xcodebuild build …` | macOS + Xcode 26 |
| See/play it | Run in the **tvOS Simulator** | macOS + Xcode 26 |
| Play on the actual TV / share | TestFlight via `release-tvos` | Apple Dev acct (D-SIGN-1) |
