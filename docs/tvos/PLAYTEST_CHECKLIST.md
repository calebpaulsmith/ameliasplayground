# Play-test checklist — Amelia's Bus Adventure (tvOS + iPad)

A **running** checklist for verifying the game by hand on the **Apple TV /
tvOS Simulator** and the **iPad / iOS Simulator**. The two are meant to be the
*same game* (shared code; only input differs), so most items have a **TV** and an
**iPad** box — tick both and note any difference.

How to use: check items as you confirm them, jot findings in **Notes**, and log
anything broken in the **Bug log** at the bottom. This file is meant to be edited
as we go.

Legend: `[ ]` to do · `[x]` pass · `[!]` problem (see Bug log) · `[-]` N/A

---

## 0. Build & launch

```bash
cd AmeliaTV
xcodegen generate
open AmeliaTV.xcodeproj
```

- [ ] **TV** — scheme **AmeliaTV** + an **Apple TV Simulator** → Run, launches to title.
- [ ] **iPad** — scheme **AmeliaPad** + an **iPad Simulator** → Run, launches to title.
- [ ] No signing prompt for the Simulator (CODE_SIGNING_ALLOWED=NO).
- [ ] iPad runs in **landscape** and fills the screen.
- [ ] First launch is reasonably quick (note seconds): TV ____ / iPad ____.

> Physical devices need a Team + unique bundle id set locally (don't commit that).
> Real Apple TV needs pairing; real iPad just needs a free Apple ID.

## 1. Title / language

- [ ] **TV** / [ ] **iPad** — big "Amelia" title + language choice visible, readable.
- [ ] English / Español both selectable; current choice is clearly marked.
- [ ] Choice persists after quit + relaunch.
- [ ] **TV** — fully navigable with the Siri Remote (focus moves, no dead ends).
- [ ] **iPad** — language buttons + "Let's go!" are easily tappable (big targets).

## 2. Garage + Mechanic Mom (A2-07)

- [ ] **TV** / [ ] **iPad** — garage scene renders: lift, bus on it, Mom, toolbox.
- [ ] The bus shows its friendly **face** toward the camera.
- [ ] Mom **speaks** a greeting on entry; subtitle matches the spoken line.
- [ ] Greeting is in the **chosen language** (test EN and ES).
- [ ] **Sticker wall** is present (empty slots first run; filled after a win).
- [ ] One big **"Let's go!"** starts the drive; no other confusing buttons.
- [ ] Back returns to the title.

## 3. The drive — neighborhood scene (A2-08)

- [ ] Roads, bus-stop shelter, park, garage, storefronts all appear.
- [ ] The **traffic light** shows lit lamps and changes (red ↔ green) over time.
- [ ] The bus **auto-drives** the route smoothly (no jitter / spinning / stalls).
- [ ] Camera follows the bus and keeps it comfortably in frame.
- [ ] Bus **stops at the red light** and continues on green.
- [ ] Scene reads as cozy/original — **no** resemblance to any real toy/show brand.

## 4. HUD (A2-10)

- [ ] **GO / STOP** badge is large and matches what the bus is doing.
- [ ] **Turn arrow** points the right way and is hidden when going straight.
- [ ] **Destination** label shows the right place name (localized).
- [ ] **Star counter** updates when stars are earned (with a little animation).
- [ ] **Minimap** shows places, the ringed active destination, and the bus marker.
- [ ] **Destination beacon** (floating pillar) sits on the current target and bobs.
- [ ] **Subtitle** is readable and stays in sync with speech.
- [ ] Couch-readable on the TV at viewing distance; comfortable on iPad up close.

## 5. Passengers & friends (A2-09)

- [ ] Ambient **NPC friends** stand around town at their places.
- [ ] **Pip** waits at the bus stop before pickup.
- [ ] At the stop, Pip **boards** (disappears into the bus); Pip speaks if applicable.
- [ ] After the fork, Pip is **dropped at the park** and reappears there.
- [ ] No duplicate/overlapping characters; nobody stuck inside a building.

## 6. The fork choice + completion (A2-12 still pending)

- [ ] At the fork, the prompt to choose is clear (spoken + arrow).
- [ ] **TV** — turn chosen with the Siri Remote (swipe) **and** the on-screen buttons.
- [ ] **iPad** — big **LEFT/RIGHT buttons** appear and a tap makes the turn.
- [ ] A "wrong" choice is **never punishing** — the game still guides to success.
- [ ] On finishing: reward stars + sticker granted, "You did it!" message shown.
- [ ] Progress (stars, sticker, completion) **persists** after relaunch.

## 7. Audio / voice (A2-13 still pending — voice only today)

- [ ] TTS voice is clear and friendly; not too fast for a young child.
- [ ] EN uses an English voice; ES uses a Spanish voice.
- [ ] Speech never talks over itself; stops when leaving a screen.
- [ ] (Pending) music + sound effects — not implemented yet.

## 8. Input

**tvOS**
- [ ] Whole slice is completable with the **Siri Remote alone**.
- [ ] If you have a game controller, it also works (steer/confirm/back).

**iPad (touch)**
- [ ] Whole slice is completable with **touch only** (no controller needed).
- [ ] Buttons are big enough for small fingers; nothing critical off-screen.
- [ ] An attached MFi controller (optional) also works.

## 9. tvOS ↔ iPad parity (the "very similar" goal)

- [ ] Same screens in the same order: title → garage → drive → reward.
- [ ] Same art, colors, characters, and copy on both.
- [ ] Same spoken lines and subtitles on both.
- [ ] HUD layout looks right on both (nothing clipped on iPad's aspect ratio).
- [ ] Difficulty/pacing feels the same on both.
- [ ] Anything that feels different → note it (we want them to match).

## 10. Child-UX & safety (hard constraints)

- [ ] Minimal reading required; a pre-reader could follow via voice + arrows.
- [ ] UI elements are big and high-contrast.
- [ ] **No harsh failure** — the child can't "lose," crash badly, or get stuck.
- [ ] Immediate positive feedback for actions (stars, sounds, Mom's praise).
- [ ] No way to reach Settings / system / external links from inside play.

## 11. Privacy & offline

- [ ] Turn the Simulator/device **offline** → the game plays fully with no network.
- [ ] No accounts, ads, chat, purchases, or analytics prompts anywhere.
- [ ] All progress is local (survives relaunch; nothing asks to sign in).

## 12. Performance & stability

- [ ] Smooth frame rate during the drive on both targets.
- [ ] No crashes across a full play-through; no runaway memory over a few loops.
- [ ] Backgrounding/foregrounding mid-drive recovers gracefully.

---

## Open design questions to answer while testing

These aren't bugs — they're judgment calls we want your read on:

1. **Camera framing** — is the chase camera distance/height right on a TV across
   the room *and* on an iPad held close, or does one need its own framing?
2. **Drive speed / pacing** — too slow (boring) or too fast for a 3–5 year old?
3. **Fork choice clarity** — does a young child understand they should pick a
   direction? Are the arrows + voice enough, or do we need a stronger highlight?
4. **GO/STOP comprehension** — is the badge meaningful to a child, or just decor?
5. **TTS quality** — is the synthesized voice good enough for v1, or should we
   prioritize recorded "hero" lines sooner?
6. **Garage dwell time** — does Mom's intro feel warm, or does the child just want
   to press "Let's go!" immediately? Should we let them skip/repeat the line?
7. **Sticker wall** — motivating as-is, or does it need to feel more like a reward?
8. **iPad-specific touches** — do we ever want touch *driving* (assisted/free
   modes), or keep iPad on auto-drive to stay identical to the Siri-Remote TV feel?
9. **Readability** — any text too small on a real TV at distance? Too big on iPad?
10. **Originality gut-check** — does anything read as derivative of an existing
    brand? Flag it for the art pass.

---

## Bug log

| # | Platform | Where | What happened | Severity | Status |
|---|----------|-------|---------------|----------|--------|
|   |          |       |               |          |        |
