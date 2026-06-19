# Amelia el Autobús — 3D models & assets

The game ships **fully playable today** using simple "blocky" models built in
code (`bus.js`, `world.js`, `npc.js`). Nothing has to be downloaded, so it
works offline. When you want nicer art, generate **GLB** models with an AI tool
and drop them in `drive/models/`. The game will swap them in automatically and
fall back to the blocky models if a file is missing — so it can never break.

## How to add a model

1. Generate a `.glb` (preferred) or `.gltf` model with one of the tools below.
2. Save it into `drive/models/`, e.g. `drive/models/bus.glb`.
3. In `drive/assets.js`, uncomment/add the entry, e.g. `bus: 'models/bus.glb'`.
4. Bump the `CACHE` version in `sw.js` so installed devices pick it up.

> Models should be **Y-up**, roughly **real-world scale in meters** (the bus is
> ~7 m long), centered at the origin, and **low-poly** (under ~20k triangles)
> so iPads stay smooth. Bake colors/materials into the GLB.

## Tools that make GLB from a text prompt

- **Meshy.ai**, **Tripo3D**, **Rodin (Hyper3D)**, **Luma Genie** — text→3D, export GLB.
- **Sloyd.ai** — parametric, great for vehicles/buildings.
- **Blender** (free) — for hand-tuning anything the AI gets wrong, then export GLB.

ChatGPT can't export a 3D file directly, but it's excellent for **writing the
generation prompt** and for **Blender Python scripts**. Paste the prompts below
into a text→3D tool, or ask ChatGPT: *"Write a Blender 4.x Python script that
builds this as a low-poly mesh and exports a GLB"* and run it in Blender.

---

## Prompts (copy/paste into a text→3D generator)

### 🚌 Amelia the bus (the star)
> A cute cartoon city bus character named Amelia, in the style of *Tayo the
> Little Bus* / Pixar *Cars*. Short and chubby, rounded boxy body, glossy sky-blue
> paint with a white roof stripe. Big friendly eyes set into the front windshield
> (two large round eyes with shiny pupils), a small happy smile below them, rosy
> cheeks. Round yellow headlights. Four chunky black wheels with silver hubcaps.
> A folding passenger door on the right side. Low-poly, clean, mobile-game ready,
> baked flat colors, no text. ~7 meters long, Y-up, centered at origin.

Variations to also generate (so she can emote): `happy`, `surprised`, `sleepy`.

### 🔧 Home base — the mechanic's workshop
> A friendly small-town auto repair garage, cartoon low-poly style. Cream walls,
> red pitched roof, one big blue roll-up garage door facing the street, a hanging
> wrench sign, stacked tires and a red toolbox outside, a couple of potted plants.
> Cheerful kids-cartoon look. ~26 m wide. Y-up, origin centered.

### 👩‍🔧 Mechanic Mom (the buses' caretaker)
> A warm, friendly cartoon mechanic mom character, low-poly. Blue overalls, red
> bandana, work gloves, holding a wrench, kind smiling face. Stylized like a kids'
> animated show. ~1.7 m tall standing, Y-up, origin at feet.

### 🐻 Passengers (generate a few)
> A small cute cartoon animal passenger for a kids' bus game, low-poly, standing
> and waving. Make versions: a bear in an orange shirt, a pink bunny, a green frog,
> a purple cat. Big friendly eyes, simple shapes. ~1.6 m tall, Y-up, origin at feet.

### 🏙️ City pieces
> A set of low-poly cartoon city buildings for a kids' game: pastel houses and
> shops (bakery, market with striped awning, school with a clock), 2–4 stories,
> flat baked colors, simple windows, no text. Modular, each centered at origin, Y-up.

### 🚏 Street furniture
> Low-poly cartoon set: a bus stop shelter with a teal roof and a bench, a traffic
> light on a pole (separate red/yellow/green lamp objects so they can light up), a
> red octagonal STOP sign, a yellow school-zone sign, leafy round trees, a park
> bench, a street lamp. Kids-cartoon style, flat colors, Y-up.

### 🌆 Skybox / environment (optional)
> A soft, cheerful daytime cartoon sky: gentle blue gradient with a few fluffy
> rounded clouds. Seamless. (Export as an equirectangular image, not a model.)

---

## Roadmap (long-term)

This is **v1: the foundation** — a drivable talking bus, a small city, GPS
missions (pick-up → drop-off → home), red-light/green-light, road signs, bus
stops with passengers, plus a free-drive mode. From here:

- **World**: bigger map, distinct neighborhoods, day/night, weather, a real road
  graph with A* routing for true turn-by-turn "follow the road" navigation.
- **Characters**: Mechanic Mom at home base, named bus friends, more passengers
  with little stories and dialogue.
- **Learning**: more signs, lane keeping, looking both ways, counting passengers,
  shapes/colors of signs, simple letters on the routes.
- **Adventures**: scripted mini-stories (a lost puppy, a parade, a trip to the
  beach), collectibles, a garage where Mom upgrades/repairs Amelia.
- **Polish**: GLB models from the prompts above, nicer audio, recorded voice
  lines, controller/TV support, save slots.
