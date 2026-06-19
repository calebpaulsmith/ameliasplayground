# Aventura Espacial de Amelia 🚀

A bilingual (Español / English) space-themed learning game for little kids,
built as an installable PWA. Five games — **Aprender** (learn), **Atrapar
estrellas** (catch stars), **Torre de cohetes** (rocket tower), **Canción
de estrellas** (a Simon-says star melody memory game) and **Fusión de
planetas** (a 2048-style swipe-to-merge game that grows asteroids all the
way up into a galaxy) — plus a prize shelf, star rewards and adaptive
difficulty. Works offline once loaded.

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

## Enabling GitHub Pages (one-time)

This repo deploys automatically via GitHub Actions on every push to `main`.

1. Go to **Settings → Pages**.
2. Under **Build and deployment → Source**, choose **GitHub Actions**.
3. Merge this branch into `main` (or push to `main`). The
   *Deploy to GitHub Pages* workflow publishes the site.

## Project layout

- `index.html` — the whole game (HTML/CSS/JS, no build step).
- `manifest.webmanifest` — PWA metadata (name, icons, colors, standalone).
- `sw.js` — service worker; precaches the app shell for offline play.
- `icons/` — app icons (any + maskable) and the Apple touch icon.
- `tools/genicons.py` — regenerates the icons from scratch (no deps).
- `.github/workflows/deploy.yml` — GitHub Pages deployment.

### Updating

When you change `index.html` or assets, bump the `CACHE` version string in
`sw.js` so installed devices pick up the new version.
