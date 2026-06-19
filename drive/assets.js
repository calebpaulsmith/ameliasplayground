// Optional high-fidelity model loading.
//
// The whole game ships playable with primitive ("blocky") models so it works
// offline with zero downloads. When you generate nicer GLB/GLTF models (see
// MODELS.md), drop them in `drive/models/` and list them in MODELS below.
// `loadModels()` will swap them in over the primitives — and silently fall
// back to the primitives if a file is missing, so the game never breaks.

import { GLTFLoader } from '../vendor/addons/GLTFLoader.js';

// id -> file. Leave empty to use the built-in primitive models.
export const MODELS = {
  // bus:    'models/bus.glb',
  // garage: 'models/garage.glb',
  // tree:   'models/tree.glb',
};

const loader = new GLTFLoader();

export function loadGLB(url) {
  return new Promise((resolve, reject) =>
    loader.load(url, (g) => resolve(g.scene), undefined, reject));
}

// Loads every model declared in MODELS. Returns { id: THREE.Object3D }.
// Missing/broken files are skipped (logged once) so the game keeps running.
export async function loadModels(base = './') {
  const out = {};
  const entries = Object.entries(MODELS);
  await Promise.all(entries.map(async ([id, file]) => {
    try { out[id] = await loadGLB(base + file); }
    catch (e) { console.info('[assets] no model for "' + id + '", using primitive.'); }
  }));
  return out;
}
