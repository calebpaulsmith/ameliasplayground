# Amelia's Bus Adventure — First Playable Vertical Slice

> Status: **Planning (Phase 0)**. This defines the **first thing we build** after
> the native project foundation: one **tiny but polished** 10–15 minute Apple TV
> adventure. It is deliberately small. Its job is to prove the whole loop end to
> end — not to be a big world.

## The slice in one sentence

**"First Day Driving":** Amelia wakes in the garage, Mechanic Mom sends her on
her very first route, she drives a short neighborhood loop — stopping at one
traffic light, making one left/right choice, picking up one passenger at a bus
stop, and dropping them at a destination — then returns home for stars and a
sticker. All bilingual, all playable with just a Siri Remote.

## Player experience (start to finish, ~10–15 min)

1. **Launch / splash** — the title, Amelia's face, a single big "Play" target.
2. **Language** — choose English or Spanish (remembered after first time, so
   returning players skip straight in). Big flag/word buttons, spoken sample.
3. **Garage home base** — Amelia parked in a cozy bay; **Mechanic Mom** walks up
   and greets her by voice (bilingual): "Good morning, Amelia! Ready for your
   first day?" One big "Let's go!" target.
4. **Roll out** — doors of the garage open; Amelia rolls onto the street.
   Auto-Drive is on by default; a glowing route ribbon + a big arrow point the
   way; Mom/GPS voice: "Follow the arrows to the bus stop."
5. **Traffic light** — the route reaches a light. It's red. The HUD shows a big
   **STOP**; voice: "Red light — stop and wait!" Player stops (or auto-drive
   stops). Light turns green; voice: "Green — let's go!" → star sparkle + praise.
6. **Left/right choice** — the road forks; a big arrow + voice asks for a turn
   ("Turn right to the bus stop!"). Player presses right on the clickpad/stick.
   Both directions are safe; the correct one is celebrated, the other gently
   redirects ("Let's try this way!") — never a failure.
7. **Bus stop pickup** — arrive at the stop; doors open; **one passenger** with
   personality (e.g. **Pip the bear** 🐻) waves, says hello (bilingual), and
   boards. Cheer + sound.
8. **Drive to destination** — new route to the passenger's place (e.g. the
   **park**). Same guidance system; a destination beacon marks the spot.
9. **Drop-off** — arrive; doors open; Pip hops off, thanks Amelia (bilingual),
   little celebration + star.
10. **Return to garage** — route flips home; roll back into the bay.
11. **Reward screen** — Mechanic Mom praises the player; show **stars earned** +
    a **first sticker** added to the garage wall. Spoken + visual.
12. **Save** — progress (stars, sticker, "First Day complete", language, assist
    level) is written **locally**. Returning lands in the garage with progress
    intact.

## In scope (the slice MUST include all of these)

- **Launch screen** with a single obvious Play action.
- **Language choice**, remembered after first run.
- **Garage home base** (a single cozy scene).
- **Mechanic Mom** introduction (a character + a few spoken lines).
- **One passenger with personality** (name, look, a few voice lines).
- **One small neighborhood route** — a short, hand-built loop (a handful of
  intersections), *not* an open world.
- **At least one traffic-light interaction** (red→green, stop teaching).
- **At least one left/right decision** (a `choice` beat).
- **A bus-stop pickup** and **a destination drop-off**.
- **A return to the garage** to close the loop.
- **Star / reward completion screen** + first sticker on the wall.
- **Local save** of progress + settings.
- **Siri Remote support** sufficient to complete the whole slice with *no other
  device* (Auto-Drive assist makes this work).
- **Controller support** (MFi/PS/Xbox) for nicer driving (parent co-play).
- **English & Spanish** spoken + on-screen for every line in the slice.
- **Basic sound/music direction**: a garage theme, a driving loop, horn, door,
  star sparkle, light/sign chimes, gentle bump. (TTS voice in v1.)
- **A simple but attractive art target**: cohesive low-poly, warm palette,
  readable from the couch — using **placeholder primitives** where final USDZ
  art isn't ready yet (gameplay must not wait on art).

## Explicitly deferred (NOT in the slice)

- Free Drive mode.
- More than one passenger / more than one route / multiple neighborhoods.
- The full episode catalog (lost puppy, parade, beach, rainy rescue, etc.).
- Cosmetic upgrades store and most garage decorations (the slice grants exactly
  **one** sticker; the *shop* comes later).
- Collectibles scattered on routes.
- Multiple/named save slots (slice uses a **single** local save).
- Parent settings area beyond the bare minimum (language + assist level may be
  surfaced minimally; full gated parent menu is later).
- Pre-recorded/voice-acted dialogue (v1 uses on-device TTS).
- Weather, day/night, and any special-event cutscenes.
- Road signs beyond what the single route needs (STOP/yield/school can wait if
  the route doesn't pass them; the traffic light is the required teaching beat).
- iPad/iPhone build.
- iCloud/cloud save, any networking.

## Acceptance criteria (the slice is "done" when…)

- A **child using only a Siri Remote** can start the app and **complete the
  whole loop** (garage → pickup → drop-off → home → reward) **without reading**
  and **without adult help** after one demo.
- A **parent with a controller** can play the same slice with nicer steering.
- The entire slice runs in **both English and Spanish**, switchable, with **every
  line spoken and shown**.
- There is **no failure state**: every mistake (run a red, take the wrong fork,
  bump a wall) results in gentle correction and the player continues.
- The loop completes in **~10–15 minutes** and ends with **stars + one sticker**.
- Progress and language **persist locally** across app relaunch.
- Runs at the **performance target** (steady frame rate, 1080p/4K) on Apple TV 4K.
- Built and unit-tested green on **CI (tvOS Simulator)** with **no signing
  secrets** (see `TECHNICAL_ARCHITECTURE.md`).

## Reused from the prototype (ideas/data, not code)

- Mission **beat structure** → `EpisodeRunner` beats
  ([`drive/missions.js`](../../drive/missions.js)).
- **Bilingual copy** for greetings, GPS cues, light/sign teaching, pickup/dropoff
  → seed strings ([`drive/i18n.js`](../../drive/i18n.js)).
- **Passenger** seed (Pip 🐻 → park) ([`drive/npc.js`](../../drive/npc.js)).
- **Driving-assist instinct** (auto-forward, soft handling) → AssistLevels
  ([`drive/bus.js`](../../drive/bus.js), [`drive/controls.js`](../../drive/controls.js)).
- **Traffic-light cycle + teaching** → Traffic system
  ([`drive/world.js`](../../drive/world.js)).
- **TTS + synthesized SFX** approach → DialogueService + audio
  ([`drive/voice.js`](../../drive/voice.js)).

## Why this slice (and not something bigger)

It exercises **every core system** — garage loop, episode/beat runner, driving +
assist, navigation/route guidance, traffic-light teaching, a `choice`, the
passenger system, rewards/save, bilingual voice, and both input devices — in the
**smallest** content footprint. Once this is polished and fun, scaling to a full
episode (Phase 3) is **adding content**, not building new engines.
