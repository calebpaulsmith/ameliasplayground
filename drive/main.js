// Amelia el Autobús — main game loop. Wires the world, the bus, passengers,
// missions and HUD together, runs the chase camera and resolves collisions.

import * as THREE from 'three';
import { buildCity } from './world.js';
import { Bus } from './bus.js';
import { makePassenger, animatePassenger, passengerList } from './npc.js';
import { Story } from './missions.js';
import { Input, initControls, pollInput, consumeHorn } from './controls.js';
import { drawMinimap, gpsInstruction } from './hud.js';
import { t } from './i18n.js';
import * as Voice from './voice.js';

let LANG = localStorage.getItem('amelia_lang') || 'es';
let renderer, scene, camera, world, bus, story, clock;
let target = null, beacon = null, mode = 'story';
let passengers = [], dropped = [];
let running = false, paused = false;
let lastBump = 0, lastInstr = '', lastInstrSpoken = 0;
let rewardStars = parseInt(localStorage.getItem('amelia_stars') || '0', 10);

const $ = (id) => document.getElementById(id);

// ---- bootstrapping -------------------------------------------------------
export function boot() {
  setupThree();
  world = buildCity();
  scene.add(world.group);
  bus = new Bus(scene);
  buildBeacon();
  wireUI();
  applyLang();
  clock = new THREE.Clock();
  renderer.setAnimationLoop(loop);
  window.addEventListener('resize', onResize);
}

function setupThree() {
  const canvas = $('view');
  renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.setSize(window.innerWidth, window.innerHeight);

  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x9fd3ff);
  scene.fog = new THREE.Fog(0x9fd3ff, 160, 320);

  camera = new THREE.PerspectiveCamera(55, window.innerWidth / window.innerHeight, 0.5, 600);
  camera.position.set(-20, 14, 0);

  const hemi = new THREE.HemisphereLight(0xcfe9ff, 0x5a7a4a, 0.95);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xfff4d6, 1.1);
  sun.position.set(80, 120, 40); sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  const d = 160;
  sun.shadow.camera.left = -d; sun.shadow.camera.right = d;
  sun.shadow.camera.top = d; sun.shadow.camera.bottom = -d;
  sun.shadow.camera.far = 400;
  scene.add(sun);
  scene.add(sun.target);
}

function buildBeacon() {
  beacon = new THREE.Group();
  const pillar = new THREE.Mesh(
    new THREE.CylinderGeometry(2, 2, 40, 16, 1, true),
    new THREE.MeshBasicMaterial({ color: 0xffd23f, transparent: true, opacity: 0.28, side: THREE.DoubleSide }));
  pillar.position.y = 20; beacon.add(pillar);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(3.4, 0.4, 8, 24),
    new THREE.MeshBasicMaterial({ color: 0xffd23f }));
  ring.rotation.x = Math.PI / 2; ring.position.y = 0.5; beacon.add(ring);
  beacon.visible = false; scene.add(beacon);
  beacon._ring = ring;
}

// ---- passengers ----------------------------------------------------------
function spawnPassengers() {
  passengers.forEach(p => scene.remove(p.p.group));
  dropped.forEach(p => scene.remove(p.group));
  passengers = []; dropped = [];

  const people = passengerList().filter(pp => world.places[pp.place]);
  const stops = world.busStops;
  const count = mode === 'story' ? Math.min(2, stops.length) : Math.min(people.length, stops.length);
  for (let i = 0; i < count; i++) {
    const p = makePassenger(people[i]);
    const s = stops[i];
    p.group.position.set(s.x, 0, s.z + 1.5);
    p.group.lookAt(s.x + 1, 0, s.z + 1.5);
    scene.add(p.group);
    passengers.push({ p, spec: people[i], stop: s, onboard: false, gone: false });
  }
}

function boardPassenger(spec) {
  const rec = passengers.find(r => r.spec.id === spec.id && !r.onboard && !r.gone);
  if (rec) { rec.onboard = true; scene.remove(rec.p.group); }
  bus.setDoor(true); Voice.SFX.doorOpen();
  setTimeout(() => { bus.setDoor(false); Voice.SFX.doorClose(); }, 1800);
  addStar();
}

function dropPassenger(spec, placeName) {
  bus.setDoor(true); Voice.SFX.doorOpen();
  setTimeout(() => { bus.setDoor(false); Voice.SFX.doorClose(); }, 1800);
  const place = world.places[placeName];
  if (place) {
    const p = makePassenger(spec);
    p.group.position.set(place.x + (Math.random() - 0.5) * 4, 0, place.z + 2);
    scene.add(p.group);
    dropped.push({ group: p.group, p, born: clock.getElapsedTime() });
  }
  addStar();
}

// ---- speech --------------------------------------------------------------
let bubbleTimer = 0;
function speak(id, vars, opts) {
  const text = t(id, LANG, vars);
  if (!text) return;
  $('bubbleText').textContent = text;
  $('bubble').classList.add('show');
  bubbleTimer = Math.max(2.6, Math.min(7, text.length * 0.07));
  Voice.say(text, LANG, opts);
}

// ---- mode / lifecycle ----------------------------------------------------
function startGame(which) {
  mode = which;
  Voice.resumeAudio();
  Voice.engineStart();
  $('startScreen').classList.remove('show');
  $('hud').classList.add('show');
  const g = world.places.garage;
  bus.reset(g.x, g.z, -Math.PI / 2); // face the road in front of the garage (toward -Z)
  spawnPassengers();
  running = true; paused = false;

  if (which === 'story') {
    story = new Story(world, {
      lang: () => LANG,
      placeName: (k) => t(k, LANG),
      say: (id, vars) => speak(id, vars),
      setTarget: (tg) => setTarget(tg),
      board: (spec) => boardPassenger(spec),
      drop: (spec, place) => dropPassenger(spec, place),
      complete: () => { speak('mComplete'); Voice.SFX.chime(); celebrate(); },
    });
    setTimeout(() => story.start(), 600);
  } else {
    story = null; setTarget(null);
    setTimeout(() => speak('exploreHi'), 600);
  }
}

function setTarget(tg) {
  target = tg;
  if (tg) { beacon.visible = true; beacon.position.set(tg.x, 0, tg.z); }
  else beacon.visible = false;
}

function quitToMenu() {
  running = false; Voice.engineStop();
  $('hud').classList.remove('show');
  $('pauseScreen').classList.remove('show');
  $('startScreen').classList.add('show');
}

// ---- main loop -----------------------------------------------------------
function loop() {
  const dt = Math.min(0.05, clock.getDelta());
  if (!running || paused) { renderer.render(scene, camera); return; }

  pollInput(() => doHorn());
  const proposed = bus.update(dt, Input);
  const fixed = resolveCollision(proposed.x, proposed.z);
  bus.commit(fixed.x, fixed.z);
  if (fixed.hit) onBump();
  bus.animateDoor(dt);
  bus.sync(dt);

  world.update(dt);
  updateCamera(dt);
  updateTraffic();
  updatePassengers(dt);
  updateBeacon(dt);
  updateGPS(dt);

  Voice.engineUpdate(bus.speed01());

  if (story) story.update(dt, bus.pos, bus.speed);

  if (bubbleTimer > 0) { bubbleTimer -= dt; if (bubbleTimer <= 0) $('bubble').classList.remove('show'); }

  renderer.render(scene, camera);
}

function updateCamera(dt) {
  const h = bus.heading;
  const fwd = new THREE.Vector3(Math.cos(h), 0, Math.sin(h));
  const desired = new THREE.Vector3()
    .copy(bus.pos).addScaledVector(fwd, -17).add(new THREE.Vector3(0, 10, 0));
  camera.position.lerp(desired, Math.min(1, dt * 3.2));
  const look = new THREE.Vector3().copy(bus.pos).addScaledVector(fwd, 6).add(new THREE.Vector3(0, 3, 0));
  camera.lookAt(look);
}

function resolveCollision(x, z) {
  const r = 2.7;
  let hit = false;
  // keep inside the world
  const lo = world.bounds.min + r, hi = world.bounds.max - r;
  if (x < lo) { x = lo; hit = true; } if (x > hi) { x = hi; hit = true; }
  if (z < lo) { z = lo; hit = true; } if (z > hi) { z = hi; hit = true; }
  for (const b of world.buildings) {
    const ex = Math.max(b.minX, Math.min(x, b.maxX));
    const ez = Math.max(b.minZ, Math.min(z, b.maxZ));
    const dx = x - ex, dz = z - ez;
    const d2 = dx * dx + dz * dz;
    if (d2 < r * r) {
      hit = true;
      if (d2 > 1e-4) {
        const d = Math.sqrt(d2); const push = (r - d) / d;
        x += dx * push; z += dz * push;
      } else {
        // bus centre inside box: shove out along the nearest face
        const toL = x - b.minX, toR = b.maxX - x, toB = z - b.minZ, toT = b.maxZ - z;
        const m = Math.min(toL, toR, toB, toT);
        if (m === toL) x = b.minX - r; else if (m === toR) x = b.maxX + r;
        else if (m === toB) z = b.minZ - r; else z = b.maxZ + r;
      }
    }
  }
  return { x, z, hit };
}

function onBump() {
  const now = clock.getElapsedTime();
  if (now - lastBump < 1.5) { bus.speed *= 0.2; return; }
  lastBump = now;
  bus.speed *= 0.15;
  bus.setExpression('surprised');
  setTimeout(() => bus.setExpression('happy'), 700);
  speak('bump');
}

function doHorn() { Voice.SFX.horn(); speak('honk', null, { force: true, rate: 1.1 }); }

// Red light / green light teaching.
function updateTraffic() {
  for (const tl of world.trafficLights) {
    const d = Math.hypot(bus.pos.x - tl.pos.x, bus.pos.z - tl.pos.z);
    if (d > 18) { tl._near = false; tl._praised = false; tl._scolded = false; continue; }
    if (!tl._near) { tl._near = true; }
    if (d < 13) {
      if (tl.state === 'red') {
        if (Math.abs(bus.speed) > 4.5 && !tl._scolded) {
          tl._scolded = true; speak('ranRed'); Voice.SFX.oops();
          bus.setExpression('surprised'); setTimeout(() => bus.setExpression('happy'), 700);
        } else if (Math.abs(bus.speed) < 1.2 && !tl._praised) {
          tl._praised = true; speak('goodStop'); Voice.SFX.good(); addStar();
        }
      }
    }
  }
}

function updatePassengers(dt) {
  for (const r of passengers) if (!r.onboard && !r.gone) {
    const near = Math.hypot(bus.pos.x - r.stop.x, bus.pos.z - r.stop.z) < 12;
    animatePassenger(r.p, dt, near);
  }
  const now = clock.getElapsedTime();
  for (let i = dropped.length - 1; i >= 0; i--) {
    const d = dropped[i];
    animatePassenger(d.p, dt, true);
    const age = now - d.born;
    if (age > 6) { scene.remove(d.group); dropped.splice(i, 1); }
  }
}

function updateBeacon(dt) {
  if (!beacon.visible) return;
  beacon._ring.rotation.z += dt * 1.5;
  beacon._ring.scale.setScalar(1 + Math.sin(now() * 2) * 0.12);
}
function now() { return clock.getElapsedTime(); }

let lastSpokenInstr = '';
function updateGPS(dt) {
  if (!target) { $('gpsPanel').classList.remove('show'); return; }
  $('gpsPanel').classList.add('show');
  const instr = gpsInstruction(bus.pos, bus.heading, target);
  if (!instr) return;
  // rotate the arrow: +rel = right = clockwise
  $('gpsArrow').style.transform = `rotate(${instr.rel}rad)`;
  $('gpsText').textContent = t(instr.id, LANG);
  $('gpsDist').textContent = Math.round(instr.dist) + 'm';
  // speak turn cues sparingly
  const tnow = now();
  const speakable = ['turnLeft', 'turnRight', 'uTurn', 'arrived'];
  if (speakable.includes(instr.id) && instr.id !== lastSpokenInstr && tnow - lastInstrSpoken > 3.5) {
    if (instr.id !== 'arrived') { Voice.say(t(instr.id, LANG), LANG); }
    lastSpokenInstr = instr.id; lastInstrSpoken = tnow;
  }
  if (instr.id !== 'turnLeft' && instr.id !== 'turnRight') lastSpokenInstr = instr.id;
}

// ---- rewards & celebrate -------------------------------------------------
function addStar() {
  rewardStars++; localStorage.setItem('amelia_stars', String(rewardStars));
  $('starCount').textContent = rewardStars;
  $('starCount').parentElement.classList.add('pop');
  setTimeout(() => $('starCount').parentElement.classList.remove('pop'), 300);
}

function celebrate() {
  const c = $('celebrate'); c.classList.add('show');
  for (let i = 0; i < 40; i++) {
    const conf = document.createElement('div'); conf.className = 'confetti';
    conf.style.left = Math.random() * 100 + 'vw';
    conf.style.background = ['#ff5da2', '#ffd23f', '#2ee6d6', '#a8e063', '#ff7e5f'][i % 5];
    conf.style.animationDuration = (1.5 + Math.random() * 1.5) + 's';
    c.appendChild(conf);
    setTimeout(() => conf.remove(), 3000);
  }
  setTimeout(() => {
    c.classList.remove('show');
    speak('allDone'); mode = 'explore'; story = null; setTarget(null);
  }, 3600);
}

// ---- UI wiring -----------------------------------------------------------
function wireUI() {
  $('btnStory').addEventListener('click', () => startGame('story'));
  $('btnExplore').addEventListener('click', () => startGame('explore'));
  $('btnPause').addEventListener('click', () => { paused = true; $('pauseScreen').classList.add('show'); });
  $('btnResume').addEventListener('click', () => { paused = false; $('pauseScreen').classList.remove('show'); });
  $('btnQuit').addEventListener('click', quitToMenu);
  $('btnHowto').addEventListener('click', () => $('howtoBox').classList.toggle('show'));
  document.querySelectorAll('.lang').forEach(b =>
    b.addEventListener('click', () => { LANG = b.dataset.l; localStorage.setItem('amelia_lang', LANG); applyLang(); }));
  initControls({ left: 'cLeft', right: 'cRight', go: 'cGo', stop: 'cStop', horn: 'cHorn' }, () => doHorn());
  $('starCount').textContent = rewardStars;

  // resize minimap on tick
  const mm = $('minimap');
  function drawMM() { if (running && !paused) drawMinimap(mm, world, bus.pos, bus.heading, target); requestAnimationFrame(drawMM); }
  requestAnimationFrame(drawMM);
}

function applyLang() {
  document.querySelectorAll('[data-t]').forEach(el => { el.textContent = t(el.dataset.t, LANG); });
  document.querySelectorAll('.lang').forEach(b => b.classList.toggle('on', b.dataset.l === LANG));
  document.documentElement.lang = LANG;
}

function onResize() {
  renderer.setSize(window.innerWidth, window.innerHeight);
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
}

boot();
