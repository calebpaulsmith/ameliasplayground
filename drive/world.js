// Builds Amelia's city: a low-poly, Tayo-style world made entirely from
// Three.js primitives + a couple of canvas textures, so nothing has to be
// downloaded. Returns a handle the game loop uses for nav, traffic and
// collisions. High-fidelity GLB models can later replace pieces in-place
// (see MODELS.md and drive/assets.js).

import * as THREE from 'three';

export const CELL = 44;       // spacing between road centre-lines
export const ROAD_W = 13;     // full road width
export const ROAD_H = ROAD_W / 2;
export const GRID_N = 5;      // grid lines 0..GRID_N  ->  GRID_N x GRID_N blocks
export const SPAN = GRID_N * CELL;

// ---- shared materials & textures ----------------------------------------
function facadeTexture(base, win) {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const x = c.getContext('2d');
  x.fillStyle = base; x.fillRect(0, 0, 128, 128);
  x.fillStyle = win;
  for (let r = 0; r < 5; r++) for (let k = 0; k < 4; k++) {
    if (Math.random() < 0.12) continue;
    x.fillRect(14 + k * 28, 14 + r * 24, 16, 14);
  }
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

const BUILDING_COLORS = [
  ['#f4a6c0', '#fff4d6'], ['#9ad0ec', '#fffbe6'], ['#ffcf8b', '#fff7e0'],
  ['#b6e3b0', '#fffde7'], ['#c9b6f0', '#fff0fb'], ['#ffd1d1', '#fff6e9'],
  ['#a7e8e0', '#fffef0'], ['#ffe39a', '#fffce0'],
];

export function buildCity() {
  const group = new THREE.Group();
  const buildings = [];          // AABBs for collision {minX,maxX,minZ,maxZ}
  const trafficLights = [];
  const busStops = [];
  const places = {};             // name -> {x,z,label}

  const rng = mulberry32(20240619);

  // ---- ground ----
  const grass = new THREE.Mesh(
    new THREE.PlaneGeometry(SPAN + CELL * 2.4, SPAN + CELL * 2.4),
    new THREE.MeshStandardMaterial({ color: 0x76c66a })
  );
  grass.rotation.x = -Math.PI / 2; grass.position.set(SPAN / 2, -0.02, SPAN / 2);
  grass.receiveShadow = true; group.add(grass);

  // ---- roads ----
  const roadMat = new THREE.MeshStandardMaterial({ color: 0x515962, roughness: 0.95 });
  const curbMat = new THREE.MeshStandardMaterial({ color: 0xcdd3da });
  const lineMat = new THREE.MeshStandardMaterial({ color: 0xffe14d, emissive: 0x332a00 });
  const roadLen = SPAN + ROAD_W;

  function roadStrip(horizontal, lineCoord) {
    // curb (slightly wider, slightly lower) + road on top + dashed centre line
    const w = ROAD_W, l = roadLen;
    const mk = (geoW, geoL, mat, y) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(geoW, 0.2, geoL), mat);
      m.receiveShadow = true; return m;
    };
    const curb = mk(w + 2.4, l, curbMat); curb.position.y = 0.0;
    const road = mk(w, l, roadMat); road.position.y = 0.06;
    const grp = new THREE.Group(); grp.add(curb); grp.add(road);
    // dashed centre line
    const dashGeo = new THREE.BoxGeometry(0.5, 0.22, 3.2);
    for (let p = -l / 2 + 3; p < l / 2 - 3; p += 7) {
      const d = new THREE.Mesh(dashGeo, lineMat); d.position.set(0, 0.07, p); grp.add(d);
    }
    if (horizontal) { grp.rotation.y = Math.PI / 2; grp.position.set(SPAN / 2, 0, lineCoord); }
    else { grp.position.set(lineCoord, 0, SPAN / 2); }
    group.add(grp);
  }
  for (let i = 0; i <= GRID_N; i++) { roadStrip(false, i * CELL); roadStrip(true, i * CELL); }

  // ---- crosswalks at every intersection ----
  const cwMat = new THREE.MeshStandardMaterial({ color: 0xf3f4f6 });
  for (let i = 0; i <= GRID_N; i++) for (let j = 0; j <= GRID_N; j++) {
    for (let s = 0; s < 2; s++) {
      for (let b = -2; b <= 2; b++) {
        const bar = new THREE.Mesh(new THREE.BoxGeometry(s ? 1.1 : 6, 0.21, s ? 6 : 1.1), cwMat);
        const off = ROAD_H + 2.2;
        if (s === 0) bar.position.set(i * CELL + b * 1.8, 0.08, j * CELL - off);
        else bar.position.set(i * CELL - off, 0.08, j * CELL + b * 1.8);
        group.add(bar);
      }
    }
  }

  // ---- block contents ----
  // Reserve specific blocks for named places; fill the rest with buildings.
  const placePlan = {
    '0,0': 'garage',  // homebase mechanic shop (corner)
    '3,1': 'park',
    '1,3': 'school',
    '4,4': 'market',
    '4,0': 'beach',
  };

  for (let bx = 0; bx < GRID_N; bx++) for (let bz = 0; bz < GRID_N; bz++) {
    const cx = bx * CELL + CELL / 2;   // block centre
    const cz = bz * CELL + CELL / 2;
    const key = bx + ',' + bz;
    const plan = placePlan[key];
    if (plan === 'garage') buildGarage(group, cx, cz, buildings, places, rng);
    else if (plan === 'park') buildPark(group, cx, cz, places, rng);
    else if (plan === 'school') buildSchool(group, cx, cz, buildings, places);
    else if (plan === 'market') buildMarket(group, cx, cz, buildings, places);
    else if (plan === 'beach') buildBeach(group, cx, cz, places, buildings);
    else fillBlock(group, cx, cz, buildings, rng);
  }

  // ---- bus stops (road-side, near a few blocks) ----
  const stopSpecs = [
    { x: 1 * CELL, z: 2 * CELL + ROAD_H + 3, name: 'A' },
    { x: 3 * CELL, z: 3 * CELL - ROAD_H - 3, name: 'B' },
    { x: 2 * CELL + ROAD_H + 3, z: 4 * CELL, name: 'C' },
    { x: 4 * CELL - ROAD_H - 3, z: 1 * CELL, name: 'D' },
  ];
  stopSpecs.forEach(s => { buildBusStop(group, s.x, s.z, buildings); busStops.push({ x: s.x, z: s.z, name: s.name }); });

  // ---- traffic lights at busy intersections ----
  const lightSpecs = [ [1, 1], [2, 3], [3, 2], [2, 1], [3, 4] ];
  lightSpecs.forEach(([i, j], n) => {
    const tl = buildTrafficLight(group, i * CELL - ROAD_H - 2.5, j * CELL - ROAD_H - 2.5);
    tl.phase = (n % 2) * 4; // stagger
    trafficLights.push(tl);
  });

  // ---- a few road signs ----
  buildStopSign(group, 2 * CELL + ROAD_H + 2.2, 2 * CELL - ROAD_H - 2.2);
  buildSign(group, 1 * CELL - ROAD_H - 2.2, 3 * CELL + ROAD_H + 2.2, 0xffd23f, 'school');

  // ---- trees scattered along grass verges ----
  for (let i = 0; i < 26; i++) {
    const bx = Math.floor(rng() * GRID_N), bz = Math.floor(rng() * GRID_N);
    if (placePlan[bx + ',' + bz]) continue;
    const x = bx * CELL + CELL / 2 + (rng() - 0.5) * (CELL - ROAD_W - 8);
    const z = bz * CELL + CELL / 2 + (rng() - 0.5) * (CELL - ROAD_W - 8);
    group.add(makeTree(x, z, 0.8 + rng() * 0.6));
  }

  // ---- nav graph: nodes at every intersection ----
  const graph = { nodes: [] };
  for (let i = 0; i <= GRID_N; i++) for (let j = 0; j <= GRID_N; j++)
    graph.nodes.push({ i, j, x: i * CELL, z: j * CELL });

  function isOnRoad(x, z) {
    const nx = Math.round(x / CELL) * CELL, nz = Math.round(z / CELL) * CELL;
    return Math.abs(x - nx) <= ROAD_H + 0.5 || Math.abs(z - nz) <= ROAD_H + 0.5;
  }

  function update(dt) { for (const tl of trafficLights) tl.update(dt); }

  return {
    group, buildings, trafficLights, busStops, places, graph, update, isOnRoad,
    CELL, ROAD_H, GRID_N, SPAN, bounds: { min: -CELL, max: SPAN + CELL },
  };
}

// ---- piece builders ------------------------------------------------------
function addBox(group, w, h, d, color, x, y, z, buildings) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d),
    new THREE.MeshStandardMaterial({ color }));
  m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true;
  group.add(m);
  if (buildings) buildings.push({ minX: x - w / 2, maxX: x + w / 2, minZ: z - d / 2, maxZ: z + d / 2 });
  return m;
}

function building(group, x, z, w, d, h, pal, buildings) {
  const tex = facadeTexture(pal[0], pal[1]);
  tex.repeat.set(Math.max(1, w / 12), Math.max(1, h / 10));
  const mat = new THREE.MeshStandardMaterial({ map: tex });
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
  m.position.set(x, h / 2, z); m.castShadow = true; m.receiveShadow = true;
  group.add(m);
  // little roof cap
  const roof = new THREE.Mesh(new THREE.BoxGeometry(w + 1, 1.2, d + 1),
    new THREE.MeshStandardMaterial({ color: 0x6b5e57 }));
  roof.position.set(x, h + 0.5, z); roof.castShadow = true; group.add(roof);
  buildings.push({ minX: x - w / 2, maxX: x + w / 2, minZ: z - d / 2, maxZ: z + d / 2 });
}

function fillBlock(group, cx, cz, buildings, rng) {
  const inner = CELL - ROAD_W - 6;
  const n = 1 + Math.floor(rng() * 3);
  for (let k = 0; k < n; k++) {
    const w = 10 + rng() * 8, d = 10 + rng() * 8, h = 9 + rng() * 16;
    const ox = (rng() - 0.5) * (inner - w), oz = (rng() - 0.5) * (inner - d);
    const pal = BUILDING_COLORS[Math.floor(rng() * BUILDING_COLORS.length)];
    building(group, cx + ox, cz + oz, w, d, h, pal, buildings);
  }
}

function buildGarage(group, cx, cz, buildings, places, rng) {
  // The homebase: a friendly red-roofed mechanic's workshop with a big door.
  const w = 26, d = 20, h = 11;
  addBox(group, w, h, d, 0xeae3d6, cx, h / 2, cz, buildings);
  // pitched roof
  const roof = new THREE.Mesh(new THREE.CylinderGeometry(w * 0.62, w * 0.62, d + 2, 3, 1, false),
    new THREE.MeshStandardMaterial({ color: 0xe2574c }));
  roof.rotation.z = Math.PI / 2; roof.rotation.y = Math.PI / 2;
  roof.position.set(cx, h + 2.4, cz); roof.castShadow = true; group.add(roof);
  // garage door (darker, facing -z / toward the road)
  const door = new THREE.Mesh(new THREE.BoxGeometry(14, 8, 0.6),
    new THREE.MeshStandardMaterial({ color: 0x3b4a63 }));
  door.position.set(cx, 4, cz - d / 2 - 0.2); group.add(door);
  // toolbox + tyres stacked outside, for character
  addBox(group, 3, 3, 2, 0xd23b3b, cx - 9, 1.5, cz - d / 2 - 4);
  for (let k = 0; k < 3; k++) {
    const tyre = new THREE.Mesh(new THREE.TorusGeometry(1.3, 0.6, 8, 16),
      new THREE.MeshStandardMaterial({ color: 0x222 }));
    tyre.rotation.x = Math.PI / 2; tyre.position.set(cx + 9, 0.7 + k * 1.3, cz - d / 2 - 4);
    group.add(tyre);
  }
  signBoard(group, cx, cz - d / 2 - 0.4, h + 0.6, 0xffd23f, '🔧');
  places.garage = { x: cx, z: cz - d / 2 - 7, label: 'garage', heading: 0 };
}

function buildPark(group, cx, cz, places, rng) {
  const lawn = new THREE.Mesh(new THREE.CircleGeometry((CELL - ROAD_W) / 2, 24),
    new THREE.MeshStandardMaterial({ color: 0x57b85a }));
  lawn.rotation.x = -Math.PI / 2; lawn.position.set(cx, 0.12, cz); group.add(lawn);
  // pond
  const pond = new THREE.Mesh(new THREE.CircleGeometry(5, 20),
    new THREE.MeshStandardMaterial({ color: 0x4ea7e0 }));
  pond.rotation.x = -Math.PI / 2; pond.position.set(cx + 6, 0.16, cz + 6); group.add(pond);
  for (let k = 0; k < 6; k++) {
    const a = k / 6 * Math.PI * 2;
    group.add(makeTree(cx + Math.cos(a) * 11, cz + Math.sin(a) * 11, 1 + rng() * 0.5));
  }
  // slide / playground hint
  addBox(group, 3, 0.6, 6, 0xff8a3d, cx - 7, 1.4, cz - 6);
  signBoard(group, cx, cz - 12, 5, 0x57b85a, '🌳');
  places.park = { x: cx, z: cz - (CELL - ROAD_W) / 2 - 3, label: 'park', heading: 0 };
}

function buildSchool(group, cx, cz, buildings, places) {
  building(group, cx, cz, 24, 16, 13, ['#ffd27f', '#fff6e0'], buildings);
  addBox(group, 4, 4, 0.6, 0x8a5a2b, cx, 2, cz - 8.2); // door
  signBoard(group, cx, cz - 9, 14, 0xffd23f, '🏫');
  places.school = { x: cx, z: cz - (CELL - ROAD_W) / 2 - 2, label: 'school', heading: 0 };
}

function buildMarket(group, cx, cz, buildings, places) {
  building(group, cx, cz, 22, 18, 10, ['#9ad0ec', '#fffbe6'], buildings);
  // striped awning
  for (let k = -3; k <= 3; k++)
    addBox(group, 2.4, 0.4, 4, k % 2 ? 0xff5d5d : 0xffffff, cx + k * 2.4, 7, cz - 10);
  signBoard(group, cx, cz - 10.5, 11, 0xff7e5f, '🛒');
  places.market = { x: cx, z: cz - (CELL - ROAD_W) / 2 - 2, label: 'market', heading: 0 };
}

function buildBeach(group, cx, cz, places, buildings) {
  const sand = new THREE.Mesh(new THREE.PlaneGeometry(CELL - 6, CELL - 6),
    new THREE.MeshStandardMaterial({ color: 0xf3e2a9 }));
  sand.rotation.x = -Math.PI / 2; sand.position.set(cx, 0.13, cz); group.add(sand);
  const water = new THREE.Mesh(new THREE.PlaneGeometry(CELL - 6, 14),
    new THREE.MeshStandardMaterial({ color: 0x3fb6e6, transparent: true, opacity: 0.92 }));
  water.rotation.x = -Math.PI / 2; water.position.set(cx, 0.18, cz + (CELL - 6) / 2 - 7); group.add(water);
  // umbrella — collide the pole so the bus can't drive through it
  const pole = addBox(group, 0.4, 5, 0.4, 0xffffff, cx - 6, 2.5, cz - 4);
  if (buildings) buildings.push({ minX: cx - 6 - 0.8, maxX: cx - 6 + 0.8, minZ: cz - 4 - 0.8, maxZ: cz - 4 + 0.8 });
  const umb = new THREE.Mesh(new THREE.ConeGeometry(4, 1.6, 12),
    new THREE.MeshStandardMaterial({ color: 0xff5d5d })); umb.position.set(cx - 6, 5.5, cz - 4); group.add(umb);
  signBoard(group, cx, cz - (CELL - 6) / 2, 5, 0x3fb6e6, '🏖️');
  places.beach = { x: cx, z: cz - (CELL - 6) / 2 - 2, label: 'beach', heading: 0 };
}

function buildBusStop(group, x, z, buildings) {
  // shelter
  addBox(group, 6, 0.4, 3, 0x2ee6d6, x, 4.4, z);      // roof
  addBox(group, 0.4, 4.4, 0.4, 0xbfc7cf, x - 2.6, 2.2, z + 1.2);
  addBox(group, 0.4, 4.4, 0.4, 0xbfc7cf, x + 2.6, 2.2, z + 1.2);
  addBox(group, 6, 1.6, 0.3, 0x9fd9ff, x, 1.4, z + 1.4); // bench-ish back
  // sign post with bus glyph
  const post = addBox(group, 0.3, 6, 0.3, 0x8a8f96, x + 3.4, 3, z);
  signBoard(group, x + 3.4, z, 6, 0x2255cc, '🚏');
  // one collider over the shelter footprint so the bus stops at it instead of
  // driving through (pickup uses a 12-unit radius, so this won't block boarding).
  if (buildings) buildings.push({ minX: x - 3.2, maxX: x + 3.7, minZ: z - 1.6, maxZ: z + 1.7 });
}

function buildTrafficLight(group, x, z) {
  const post = addBox(group, 0.5, 9, 0.5, 0x2b2f36, x, 4.5, z);
  const arm = addBox(group, 0.4, 0.4, 3, 0x2b2f36, x, 8.6, z + 1.5);
  const housing = addBox(group, 1.6, 4.4, 1.2, 0x15171b, x, 7.4, z + 3);
  const mk = (col, y) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(0.55, 16, 16),
      new THREE.MeshStandardMaterial({ color: col, emissive: col, emissiveIntensity: 0.15 }));
    m.position.set(x, y, z + 3.65); group.add(m); return m;
  };
  const red = mk(0xff3b30, 8.5), yellow = mk(0xffcc00, 7.4), green = mk(0x34c759, 6.3);
  const obj = {
    pos: new THREE.Vector3(x, 0, z), state: 'green', phase: 0, t: 0,
    red, yellow, green,
    setState(s) {
      this.state = s;
      const dim = (m) => m.material.emissiveIntensity = 0.12;
      dim(red); dim(yellow); dim(green);
      const lit = s === 'red' ? red : s === 'yellow' ? yellow : green;
      lit.material.emissiveIntensity = 1.4;
    },
    update(dt) {
      this.t += dt;
      // cycle: green 6 -> yellow 2 -> red 6
      const cyc = (this.t + this.phase) % 14;
      const s = cyc < 6 ? 'green' : cyc < 8 ? 'yellow' : 'red';
      if (s !== this.state) this.setState(s);
    },
  };
  obj.setState('green');
  return obj;
}

function buildStopSign(group, x, z) {
  addBox(group, 0.3, 5, 0.3, 0x8a8f96, x, 2.5, z);
  const oct = new THREE.Mesh(new THREE.CylinderGeometry(1.5, 1.5, 0.2, 8),
    new THREE.MeshStandardMaterial({ color: 0xd11a1a }));
  oct.rotation.x = Math.PI / 2; oct.rotation.z = Math.PI / 8;
  oct.position.set(x, 5, z); group.add(oct);
  signBoard(group, x, z + 0.12, 5, 0xd11a1a, 'STOP', true);
  return { x, z, type: 'stop' };
}

function buildSign(group, x, z, color, type) {
  addBox(group, 0.3, 5, 0.3, 0x8a8f96, x, 2.5, z);
  const face = new THREE.Mesh(new THREE.BoxGeometry(2.6, 2.6, 0.2),
    new THREE.MeshStandardMaterial({ color }));
  face.rotation.z = Math.PI / 4; face.position.set(x, 5.2, z); group.add(face);
  return { x, z, type };
}

// A small canvas-textured board (emoji/text) that always reads clearly.
function signBoard(group, x, z, y, bg, text, big) {
  const c = document.createElement('canvas'); c.width = c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#ffffff'; g.fillRect(0, 0, 128, 128);
  g.fillStyle = '#' + bg.toString(16).padStart(6, '0');
  g.fillRect(6, 6, 116, 116);
  g.fillStyle = '#ffffff'; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.font = (big ? 'bold 34px' : '64px') + ' sans-serif';
  g.fillText(text, 64, 70);
  const tex = new THREE.CanvasTexture(c);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(3, 3),
    new THREE.MeshBasicMaterial({ map: tex, transparent: true }));
  m.position.set(x, y, z); group.add(m);
  return m;
}

function makeTree(x, z, s) {
  const g = new THREE.Group();
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.5 * s, 0.7 * s, 3 * s, 6),
    new THREE.MeshStandardMaterial({ color: 0x7a4a25 }));
  trunk.position.y = 1.5 * s; trunk.castShadow = true; g.add(trunk);
  const leaf = new THREE.Mesh(new THREE.SphereGeometry(2.4 * s, 8, 6),
    new THREE.MeshStandardMaterial({ color: 0x3f9e4d }));
  leaf.position.y = 4 * s; leaf.castShadow = true; g.add(leaf);
  g.position.set(x, 0, z);
  return g;
}

// deterministic RNG so the city is the same every visit
function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
