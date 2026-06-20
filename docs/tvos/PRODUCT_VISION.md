# Amelia's Bus Adventure — Product Vision

> Status: **Planning (Phase 0)**. This document is the "north star." It defines
> who the game is for, what it feels like, and the boundaries we will not cross.
> Everything in `GAME_DESIGN.md`, `VERTICAL_SLICE.md`, and the backlog should be
> traceable back to a statement here.

## One-line pitch

*Amelia's Bus Adventure* is a cozy, bilingual (English / Spanish) 3D
driving-and-adventure game for **Apple TV**, designed for a young child and a
grown-up to play together on the couch.

## The fantasy

You are **Amelia**, a friendly original blue city bus who lives at a mechanic's
garage with her caretaker, **Mechanic Mom**. Each day you wake up in the garage,
get a little pep talk, and roll out into a small, cheerful neighborhood to help
friendly animal passengers get where they need to go — learning the rules of the
road and earning stars, stickers, and decorations along the way.

It should feel like **a warm animated children's show crossed with a gentle
open-world driving adventure**: short, satisfying, funny, and safe.

## Who it's for

- **Primary player:** a child, roughly **ages 3–6**.
- **Co-player:** a parent or older sibling, who can pick up a controller and play
  alongside (driving better, narrating, or just watching).
- **Buyer / gatekeeper:** the same parent, who needs to trust that the game is
  safe, ad-free, and won't surprise them with purchases or chat.

The child should be able to **launch and play the main activity without adult
help** after a little familiarity. The parent should be able to sit down with a
controller and immediately feel useful, not bored.

## What success feels like

A 4-year-old presses the big button on the screen, hears Amelia say "¡Vamos!",
and drives to the bus stop while a parent quietly helps steer. They pick up a
nervous little frog, follow the glowing arrows past a red light (they *stop!*),
drop the frog at the market, roll home to a hug from Mechanic Mom, and get a
gold star and a new sticker for the garage wall. Total time: ~12 minutes. The
child asks to do it again. Nobody got frustrated. Nobody saw an ad.

## Pillars (the feelings we protect)

1. **Cozy & safe.** No harsh failure, no time pressure that punishes, no scary
   content. Mistakes are gentle teaching moments ("Oops — red means stop. Let's
   wait together!"), never a "Game Over."
2. **Warm characters.** Amelia and Mechanic Mom have real personalities. The
   passengers are little friends with names and feelings. The world should feel
   *loved*, like a favorite show.
3. **Learn by doing.** Stop/go, red/green lights, left/right, bus stops, basic
   signs — taught through play and repetition, never through quizzes or reading.
4. **Bilingual by design.** English and Spanish are first-class and switchable
   at any time. Spoken guidance carries the experience so reading is optional.
5. **Couch-first.** Designed for a living-room TV at a distance, with a Siri
   Remote in a small hand or a controller in a parent's.
6. **A great small game.** We would rather ship one polished, replayable
   neighborhood than ten shallow ones.

## Original IP — hard requirement

Amelia's Bus Adventure is an **original property**. We do **not** use, imitate,
or reference Tayo, Pixar/*Cars*, or any other existing character names, designs,
logos, liveries, voices, or distinctive visual identity.

- Amelia may be a cute anthropomorphic bus, but she has her **own** recognizable
  silhouette, color story, face design, and personality.
- Any prompt, asset, or note inherited from the prototype that references
  another property (e.g. "à la Tayo," "Pixar Cars style" in `drive/MODELS.md`)
  is **reference shorthand only** and must be rewritten before it informs final
  art. See `RISKS_AND_DECISIONS.md` (D-IP-1).

## Platform intent

- **Apple TV / tvOS first**, as a *real native app* — not a webview, PWA,
  Capacitor wrapper, browser shell, or a port of the existing HTML/Three.js
  prototype.
- Looks great on a living-room TV at **1080p and 4K**.
- **Siri Remote supported for the core experience**; MFi / PlayStation / Xbox
  controllers supported and *preferred* for driving — but never *required* for
  the first playable story.
- Architected so a later **iPad / iPhone** version is a small step, not a
  rewrite.

## Privacy & business constraints (non-negotiable for v1)

This is a **private, family-first** project initially, with the *option* to go
public later. For the first version:

- **No ads. No analytics. No accounts. No chat. No social features.**
- **No in-app purchases or monetization.**
- **No external links** visible to children.
- **No network dependency** for normal play — the game is fully playable offline.
- **All game state stored locally** on the device.
- Designed to be compatible with **Apple's Kids Category** expectations so a
  future public release is realistic without re-architecting.

If any future feature would compromise these constraints, it is out of scope by
default and must be raised explicitly in `RISKS_AND_DECISIONS.md`.

## Relationship to the existing prototype

The repository already contains a web prototype, **"Amelia el Autobús,"** under
[`drive/`](../../drive/) (Three.js, primitive models, bilingual, GPS missions,
traffic lights, free drive). It is a **playable reference and a source of ideas**
— mission structure, bilingual copy, the garage/home-base loop, passengers,
bus stops, the driving-assist instinct — **not** an architecture to preserve.

- The web prototype **stays untouched and playable** while native development
  happens in a separate directory (`AmeliaTV/`, see `TECHNICAL_ARCHITECTURE.md`).
- We **preserve good gameplay ideas** and reusable data (bilingual strings,
  mission beats) and **discard weak technical decisions** simply because they
  exist.

## Explicit non-goals (for the foreseeable future)

- Realistic physics or simulation driving.
- Large open world / many neighborhoods at launch.
- Online multiplayer or any networked play.
- User-generated content, sharing, or anything resembling social.
- Difficulty that can frustrate or "fail" a young child.
- Twitch reflexes or precision required to progress.

## How we'll know the vision is intact

Before shipping any milestone, we ask:

- Could a 4-year-old understand what to do **without reading**?
- Did anything feel **punishing** or scary?
- Is every player-facing line available in **both languages**?
- Does it work with **only a Siri Remote**?
- Did we add a feature the pillars didn't ask for? (If so, justify or cut it.)
