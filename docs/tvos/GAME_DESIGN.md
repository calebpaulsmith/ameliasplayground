# Amelia's Bus Adventure — Game Design

> Status: **Planning (Phase 0)**. This is the long-term design of the *whole*
> game. The first thing we actually build is a small slice of it — see
> `VERTICAL_SLICE.md` for exactly what ships first. Anything here not in the
> slice is a future milestone in `ROADMAP.md` / `BACKLOG.md`.

## Design principles (child usability is a feature, not polish)

1. **Minimal reading.** Spoken guidance and big icons carry meaning. Text is a
   bonus for readers, never a requirement.
2. **One clear thing to do at a time.** The game always answers "where do I go?"
   with a glowing route and a voice line.
3. **Big, forgiving targets.** Large UI, generous trigger radii, soft collisions.
4. **Immediate positive feedback.** Every good action gets a sound, a sparkle,
   and a kind word within a fraction of a second.
5. **No harsh failure.** You cannot lose. You can only succeed slower. Mistakes
   are gentle, repeatable teaching moments.
6. **Short loops, satisfying ends.** A play session has a clear beginning
   (garage), middle (a route), and end (stars + home), in ~10–15 minutes.
7. **Two-hands-optional.** Designed so a Siri Remote alone works, and a
   controller makes driving nicer for a parent.
8. **Data-driven.** Episodes, passengers, places, dialogue, and rewards are
   defined in data (JSON), not hardcoded, so new content is content — not code.

## The core loop

```
        ┌──────────────────────────────────────────────┐
        │                                              │
        ▼                                              │
   GARAGE (home base)                                  │
   • Mechanic Mom greeting                             │
   • Pick today's adventure (or Free Drive later)     │
   • See stars, stickers, decorations, bus cosmetics   │
        │                                              │
        ▼                                              │
   ADVENTURE (a story episode)                         │
   • Drive a short guided route                        │
   • Pick up a passenger at a bus stop                 │
   • Obey a traffic light / sign                       │
   • Make a left/right route decision                  │
   • Drop off the passenger at a destination           │
        │                                              │
        ▼                                              │
   RETURN HOME                                         │
   • Roll back to the garage                           │
        │                                              │
        ▼                                              │
   REWARD                                              │
   • Stars + sticker + Mom's praise                    │
   • Unlock progress                                   │
        └──────────────────────────────────────────────┘
```

Replayability comes from a **small number of deep systems**, not many shallow
ones. The systems that matter most (ranked):

1. **Passengers/friends** — characters kids want to see again.
2. **Story episodes** — the parade, the lost puppy, the beach trip.
3. **Rewards & garage decoration** — visible, collectible progress.
4. **Driving-assist that scales** — feels good for a 3-year-old *and* a parent.

Everything else supports these.

## Systems

### 1. Garage / home base

The emotional anchor. A small, cozy interior + forecourt you always return to.

- **Mechanic Mom** greets the player (spoken, bilingual), reacts to progress,
  and introduces each adventure.
- **Adventure board:** a few big picture-cards to choose today's episode. Locked
  episodes show as friendly "coming soon" cards, never as failures.
- **Trophy/sticker wall:** earned stickers and stars are displayed here.
- **Bus bay:** Amelia parked; tapping/selecting her opens cosmetic upgrades.
- The garage is the launch destination after the splash/language screen, and the
  end destination of every adventure (close the loop).

### 2. Story episode system (the main game)

Structured story adventures are the **primary** mode; Free Drive is a later
unlock. An **episode** is a data-defined sequence of *beats*. This generalizes
the prototype's `Story`/beats concept in [`drive/missions.js`](../../drive/missions.js).

Beat types (initial set):
- `say` — Amelia/Mom/passenger speaks a line (bilingual id).
- `driveTo` — set a route target; guide the player there (arrows + voice).
- `pickup` — stop at a bus stop, open doors, board a passenger.
- `dropoff` — arrive at a destination, drop the passenger, celebrate.
- `lightStop` — a traffic-light teaching beat (must stop on red).
- `choice` — a left/right route decision (both choices are valid/safe).
- `cutscene` — a short scripted camera/animation moment (e.g. parade).
- `reward` — grant stars/sticker; show completion screen.

Episodes declare their passengers, places, route, and dialogue **as data**.
Designers (and Claude) author episodes as JSON + string ids, not new code.

Planned launch episodes (themes, not all in the slice):
- **First Day Driving** (the vertical slice / tutorial episode).
- **The Lost Puppy** (find-and-return a wandering puppy).
- **Parade Day** (slow, ceremonial drive; learn to follow a leader).
- **Beach Trip** (longer route; introduces a new place + weather mood).
- **Rainy-Day Rescue** (rain visuals; careful slow driving).
- **Helping a Friend Get Somewhere Important** (mild time-soft urgency, never
  punishing).

### 3. Neighborhood / world progression

- The world is **small and curated**, not a giant procedural city. Think a
  hand-placed "block" the size of a few intersections, themed and readable.
- New **neighborhoods** unlock over time as cozy expansions (each adds places,
  passengers, and episodes). Progression is **additive and gentle** — unlocking
  is a gift, not a gate you can fail.
- Roads use a **node/edge graph** (intersections = nodes) so routing,
  turn-by-turn guidance, and `choice` beats are computed, not hand-scripted.
  (The prototype already sketches an intersection graph in
  [`drive/world.js`](../../drive/world.js).)

### 4. Passenger / friend system

- Passengers are named animal friends with a **home place**, a **color/identity**,
  a **personality**, and **a few voice lines** (greeting, in-transit chatter,
  thank-you), all bilingual. (Prototype seed: Pip 🐻 park, Lola 🐰 school,
  Tomás 🐸 market, Mía 🐱 beach — see [`drive/npc.js`](../../drive/npc.js).)
- Meeting a passenger the first time is a small event. Repeat rides build
  familiarity ("Hi Amelia, it's me again!").
- A friends/collection screen (later) tracks who you've met.

### 4a. Character Life & Charm (Pixar feel — "personality, not robots")

The thing that makes kids **fall in love with the world**: everything has
personality, the world *reacts* to the child, and every action has juice. This is
a **render-layer** workstream — procedural animation over today's placeholder
geometry, swappable to USDZ later by id — and needs **no Core/gameplay change**
(it only observes existing `GameSession` state). It deepens the "Warm characters"
pillar (`PRODUCT_VISION.md`) and the Agency pass (`MODES_AND_DIRECTION.md`).

**Principles (the Pixar lens):**
- **Everything is a character** — the bus, houses, the traffic light, the mailbox
  have eyes/moods; nothing is inert set-dressing.
- **Anticipation → action → reaction** — wind-up before a honk, overshoot-and-settle
  after. Robots snap; characters **squash & stretch** (springs, never linear).
- **The world notices the child** — drive past and a friend waves, a duck scurries,
  flowers turn to look. Cause → delightful effect, every time.
- **Warmth over challenge** — the hook is *love* (cozy ritual, surprise, friends who
  are happy to see you), never loss. No dark patterns; honor **Reduce Motion**.

**Per-element checklist (built smallest-first, one PR each):**
1. **Amelia comes alive** *(built first)* — blink, eyes that look toward her
   destination/passenger, squash on stops, lean into turns, idle "breathing", a
   honk wiggle, a happy hop on pickup. (Foundations: a `FaceRig` so eyes are
   addressable; a pure `Easing`/`Spring` util in the Core, unit-tested.)
2. **The neighborhood is alive** — NPCs/passengers idle-bob, blink, turn to watch
   the bus, wave, hop when boarded.
3. **The world reacts** — honk-reacts (friends wave, ducks/birds scatter, props
   boing); landmarks animate (flag flutters, lighthouse beam sweeps).
4. **Juice** — wheel dust puffs, star bursts, hearts, a gentle camera bounce on
   honk/pickup, confetti into the reward screen.
5. **Cozy world mood** — day→dusk→night lighting wash (headlights, glowing windows,
   stars) + soft weather (puddle splashes).

**Rules:** all data-/state-driven and original-IP (D-IP-1); cheap per-frame
transforms within the performance budget (R-PERF-1); the Game Core stays GPU-free
(animation is the renderer's job, one-way observing Core state).

### 5. Route & navigation system

The "where do I go" system. Must be understandable without reading.

- **Glowing route ribbon** on the road ahead toward the current target.
- **Big turn arrows** that pulse before a turn; a **minimap/GPS** corner widget.
- **Spoken cues**, bilingual, timed to the turn ("Turn right!" / "¡Gira a la
  derecha!") — generalizing the prototype's GPS strings in
  [`drive/i18n.js`](../../drive/i18n.js).
- **Destination beacon**: a tall, friendly light pillar over the target so it's
  visible from anywhere.

### 6. Driving-assist model for children (critical)

The single most important UX system. Driving must feel good with a **Siri
Remote** and *better* with a controller, for both a 3-year-old and a parent.

Design it as **assist levels** rather than one driving model:

- **Auto-Drive (default for youngest):** Amelia follows the route automatically
  at a calm speed. The child's job is the *fun decisions*: press **GO** to start,
  **STOP** at lights, **tap left/right** at a `choice`, honk the horn, open doors.
  This makes the Siri Remote (clickpad + Play/Pause) completely sufficient.
- **Assisted Steering (default for ~5–6 / parent):** the player steers, but the
  bus has strong **lane guidance / rails** — it gently auto-corrects toward the
  road and can't really crash. Speed is capped and child-friendly.
- **Free Steering (parent / Free Drive):** looser assist, full analog steering
  on a controller stick. Still no harsh consequences.

Shared rules across all levels:
- **Soft collisions:** the bus bumps, says "whoops, slow down," and is nudged
  back — never stuck, never damaged.
- **Auto-forward in story moments** where movement isn't the lesson.
- **Generous arrival radii** so "stop at the stop" is easy to satisfy.
- Assist level is a **parent-facing setting**, remembered per save, with a sane
  default that the game can also infer from input device.

### 7. Traffic-light & road-sign learning mechanics

Taught through repetition inside normal driving:

- **Traffic lights:** red = stop, yellow = slow, green = go. Stopping on red
  earns praise + a star sparkle; rolling through is gently corrected and simply
  repeated, never punished. (Prototype copy exists: `redStop`, `greenGo`,
  `goodStop`, `ranRed`.)
- **Signs (introduced gradually):** STOP (full stop), school zone (go slow),
  yield. Each sign, on first encounter, gets a friendly spoken explanation.
- A subtle **"learning tracker"** (parent-facing) can note which concepts the
  child has practiced — stored locally, never uploaded.

### 8. Reward / economy system

Visible, generous, non-punitive.

- **Stars** for completing beats and good behavior (stopping on red, gentle
  driving, arriving). Stars are the soft currency.
- **Stickers** awarded per episode / milestone, displayed on the garage wall.
- **Collectibles** hidden lightly along routes (e.g. shiny coins, balloons) to
  reward curiosity — optional, never required.
- Stars unlock **cosmetics** (bus paint, hats, horn sounds) and **garage
  decorations**. No real money, ever. No dark patterns, no "energy" timers.

### 9. Cosmetic upgrades & garage decorations

- **Bus cosmetics:** paint colors, roof accessory/hat, horn sound, headlight
  style. Purely visual; never affect difficulty. Swappable from the bus bay.
- **Garage decorations:** banners, plants, posters, string lights bought with
  stars. Makes the home base feel like *yours* over time.
- All cosmetics are **data + asset references** so adding more is content work.

### 10. Collectibles

- Lightly scattered along routes; collecting is optional delight, not a chore.
- Some are **per-episode** (find all balloons in the parade), some **world-wide**.
- Feed the reward economy; never block progression.

### 11. Free Drive (later unlock)

- Unlocks after the first few story episodes are complete (a *reward* for
  playing, framed positively — "You know the neighborhood now — go explore!").
- No objectives, no fail; passengers and collectibles still exist as optional fun.
- Uses the looser assist level by default.

### 12. Save slots & parent-facing options

- **Local-only** save (see privacy constraints). Multiple **named slots** so
  siblings can have their own progress and bus.
- A small, **gated parent area** (e.g. "hold to enter" or a simple
  shape/age-gate, not a password the child will memorize) for: language default,
  assist level, audio/voice volume, subtitle on/off, reset slot.
- Settings are few and big. No deep menus.

### 13. Bilingual content architecture

- Every player-facing line is a **string id** with `en` and `es` (and room for
  more languages later), exactly like the prototype's `STR` map in
  [`drive/i18n.js`](../../drive/i18n.js), but moved into versioned **data files**
  (JSON/`.lproj`) rather than source.
- Language is switchable **any time** and remembered per save.
- Spoken audio: v1 uses on-device **text-to-speech** (mirrors the prototype's
  Web Speech approach); later episodes can layer **pre-recorded voice** for
  Amelia/Mom for warmth, with TTS as fallback.

### 14. Voice & dialogue system

- A **dialogue service** plays a line by id: resolves language, speaks it
  (recorded clip if present, else TTS), and shows optional subtitle text.
- Lines are **queued and de-duped** so the game never talks over itself
  (the prototype already guards against repeating the last line).
- Speaker identity (Amelia / Mom / passenger) drives pitch/voice selection.

### 15. Audio & music direction (high level)

- **Music:** gentle, warm, looping themes — a cozy garage theme, a bright
  driving theme, soft stingers for rewards. Calm, never frantic.
- **SFX:** friendly horn, door whoosh, star sparkle, soft bump, light/sign
  chimes — synthesized or sampled, mixed low under voice.
- **Mix priority:** voice > stingers > SFX > music. Voice is always intelligible.

### 16. Future: weather & day/night

- Cozy weather *moods* (sunshine, light rain, evening glow) tied to episodes
  (Rainy-Day Rescue, Beach Trip). Visual + audio only; never make driving harder
  in a punishing way.

### 17. Future: special events

- **Parade**, **beach trip**, **lost puppy**, **rainy rescue**, **helping a
  friend** — authored as episodes using the beat system + a few bespoke
  `cutscene` beats. These are content milestones, not new engines.

## Anti-bloat guardrails

- A new system must serve a **pillar** and ideally one of the **top-4
  replayability systems**. If it doesn't, it waits.
- Prefer **more content in existing systems** (a new passenger, a new episode, a
  new sticker) over **new systems**.
- Every system ships **data-driven** so content can grow without engine changes.
