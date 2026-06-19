# Aventura Espacial de Amelia 🚀

A bilingual (Español / English) space-themed learning game for little kids,
built as an installable PWA. Six games — **Aprender** (learn), **Atrapar
estrellas** (catch stars), **Torre de cohetes** (rocket tower), **Canción
de estrellas** (a Simon-says star melody memory game), **Fusión de
planetas** (a 2048-style swipe-to-merge game that grows asteroids all the
way up into a galaxy) and **Jardín de viento** (a calming, generative
chime garden — steer drifting stardust along wind currents through
expanding rings that sing in a pentatonic scale, à la *Frost*) — plus a
prize shelf, star rewards and adaptive difficulty. Works offline once
loaded.

## 🚌 Amelia el Autobús (3D driving adventure)

A heavier, longer-term project lives in [`drive/`](drive/): a **3D driving
game** where Amelia is a talking blue bus (à la *Tayo the Little Bus*). She
lives at a **mechanic's workshop** home base and learns to drive around a
small city — teaching **red-light/green-light**, **left & right**, reading
**road signs**, and **stopping at bus stops** to pick up passengers.

- **Story mode** — follow the GPS minimap and turn-by-turn arrows through a
  pick-up → drop-off → home adventure, with a talking bus, traffic lights and
  star rewards.
- **Free Drive** — cruise around the whole city with no objectives.
- Built with **Three.js** (vendored in `vendor/` for offline play) from
  primitive models, so it needs no downloaded assets. Bilingual ES/EN with
  spoken voice. Playable by touch, keyboard (arrows/WASD) or game controller.

See [`drive/MODELS.md`](drive/MODELS.md) for the long-term roadmap and
ready-to-paste **AI prompts** to generate high-fidelity GLB models that drop
straight into `drive/models/`.

## Play it

Once GitHub Pages is enabled (see below), the game lives at:

```
https://calebpaulsmith.github.io/ameliasplayground/
```

## Install on iPad / iPhone

1. Open the link above in **Safari**.
2. Tap the **Share** button, then **Add to Home Screen**.
3. Launch it from the home screen — it runs full-screen, no browser bars,
   and works without internet.

On Android/desktop Chrome, use the **Install** icon in the address bar.

## Play on a TV / Apple TV (game controller)

Every game is fully playable without touch, using a **game controller**
(Xbox, PlayStation or MFi) or a **keyboard** — so it works on the big screen:

1. Pair a Bluetooth controller to an iPhone, iPad or Mac.
2. Open the site there and **AirPlay / mirror** the screen to the Apple TV
   (or connect the Mac to the TV).
3. Sit back and play with the controller from the couch.

Controls: **d-pad / left stick** moves the highlight (and steers in Catch,
slides in Planet Merge, moves the cursor in Wind Garden); **A / Enter**
selects, plants, or drops; **B / Esc** goes back. Connecting a controller
switches the UI into a TV-safe (overscan-aware) layout automatically. On a
keyboard: **arrows/WASD**, **Enter/Space**, **Esc**.

> Note: tvOS has no web browser, so this runs on the TV via screen
> mirroring rather than as a native Apple TV app.

## Enabling GitHub Pages (one-time)

This repo deploys automatically via GitHub Actions on every push to `main`.

1. Go to **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Merge this branch into `main` (or push to `main`). The
   *Deploy to GitHub Pages* workflow publishes the site.

## Project layout

- `index.html` — the whole game (HTML/CSS/JS, no build step).
- `drive/` — Amelia el Autobús, the 3D driving adventure (ES modules + Three.js).
- `vendor/` — Three.js (vendored locally for offline play).
- `manifest.webmanifest` — PWA metadata (name, icons, colors, standalone).
- `sw.js` — service worker; precaches the app shell for offline play.
- `icons/` — app icons (any + maskable) and the Apple touch icon.
- `tools/genicons.py` — regenerates the icons from scratch (no deps).
- `.github/workflows/deploy.yml` — GitHub Pages deployment.

### Updating

When you change `index.html` or assets, bump the `CACHE` version string in
`sw.js` so installed devices pick up the new version.
