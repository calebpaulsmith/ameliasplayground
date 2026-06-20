// Amelia — a friendly blue talking bus, à la Tayo. Built from primitives so
// she needs no downloaded model. `Bus` wraps a kid-friendly arcade driving
// model; the game loop feeds it input and resolves collisions.

import * as THREE from 'three';
import { RoundedBoxGeometry } from '../vendor/addons/RoundedBoxGeometry.js';

const BLUE = 0x3aa0ff, DKBLUE = 0x1f6fd0, NAVY = 0x16314a, WHITE = 0xfbfdff, GLASS = 0x9fd9ff;

export function createBusMesh() {
  const g = new THREE.Group();
  const body = new THREE.Group(); g.add(body);

  // ---- rounded, chunky body (the Tayo look) ----
  body.add(rbox(7.0, 1.7, 3.5, 0.5, DKBLUE, 0, 1.5));          // chassis / skirt
  const main = rbox(6.9, 3.3, 3.5, 0.9, BLUE, 0, 3.35); body.add(main);
  body.add(rbox(7.02, 0.5, 3.62, 0.22, WHITE, 0, 2.45));        // white belt stripe
  body.add(rbox(6.1, 0.9, 3.42, 0.45, WHITE, 0, 5.05));         // white roof band
  body.add(rbox(5.2, 0.8, 3.0, 0.4, BLUE, 0, 5.6));             // blue roof cap

  // glass: dark front visor (where the eyes live) + side & rear windows
  body.add(rbox(0.5, 1.5, 2.95, 0.35, NAVY, 3.45, 4.05));
  body.add(rbox(0.4, 1.3, 2.7, 0.3, GLASS, -3.5, 4.0));         // rear window
  for (let s = -1; s <= 1; s += 2)
    for (let k = -1; k <= 1; k++)
      body.add(rbox(1.7, 1.3, 0.16, 0.16, GLASS, k * 1.95, 4.05, s * 1.74));

  // ---- face (friendly, Tayo-style: forward gaze, eyelids, soft brows) ----
  const face = new THREE.Group(); body.add(face);
  const EYE_Y = 3.28;
  const mkEye = (z) => {
    const white = sphere(0.6, WHITE, 3.64, EYE_Y, z); white.scale.set(0.42, 1.05, 0.82);
    // pupil looks straight ahead (centred), sitting just on the eye surface
    const pupil = sphere(0.3, 0x101a26, 3.8, EYE_Y - 0.05, z); pupil.scale.set(0.4, 1, 1);
    const shine = sphere(0.09, WHITE, 3.92, EYE_Y + 0.14, z - 0.12);
    // dark upper eyelid bar — the key to a gentle (non-creepy) gaze
    const eyelid = rbox(0.2, 0.14, 0.98, 0.06, NAVY, 3.82, EYE_Y + 0.32, z);
    // blink lid (body colour), animated in sync()
    const lid = rbox(1.2, 0.9, 1.18, 0.42, BLUE, 3.55, EYE_Y + 0.7, z);
    lid.scale.y = 0.02; lid.userData.openY = EYE_Y + 0.7;
    // soft eyebrow, slightly raised toward the outside
    const brow = rbox(0.16, 0.1, 0.62, 0.05, NAVY, 3.66, EYE_Y + 0.66, z);
    brow.rotation.x = z < 0 ? -0.18 : 0.18;
    face.add(white, pupil, shine, eyelid, lid, brow);
    return { white, pupil, lid };
  };
  const L = mkEye(-0.82), R = mkEye(0.82);
  // wide, gentle chrome smile (broad and shallow, like the reference)
  const mouth = new THREE.Mesh(
    new THREE.TorusGeometry(0.7, 0.095, 10, 24, Math.PI),
    new THREE.MeshStandardMaterial({ color: 0xccd4dc, metalness: 0.5, roughness: 0.35 }));
  mouth.rotation.z = Math.PI; mouth.rotation.y = Math.PI / 2;
  mouth.scale.set(1.65, 0.6, 1);
  mouth.position.set(3.66, 2.92, 0); face.add(mouth);

  // headlights (warm glow)
  for (const z of [-1.25, 1.25]) {
    const hl = new THREE.Mesh(new THREE.SphereGeometry(0.34, 16, 12),
      new THREE.MeshStandardMaterial({ color: 0xfff2a8, emissive: 0xffd86b, emissiveIntensity: 0.7 }));
    hl.position.set(3.5, 1.95, z); hl.scale.set(0.5, 1, 1); body.add(hl);
  }

  // route sign on the windshield: "120" + three little lights (Tayo style)
  body.add(frontSign(3.72, 4.45, 0));
  // "120" on each side
  body.add(sideNumber(-0.6, 3.0, 1.77, 0));
  body.add(sideNumber(-0.6, 3.0, -1.77, Math.PI));

  // ---- wheels (fat tyre + hubcap + bolts) ----
  const wheels = [];
  const wheelPos = [[2.35, -1.6], [2.35, 1.6], [-2.35, -1.6], [-2.35, 1.6]];
  for (const [x, z] of wheelPos) {
    const w = new THREE.Mesh(new THREE.CylinderGeometry(1.05, 1.05, 0.85, 20),
      new THREE.MeshStandardMaterial({ color: 0x1b1b20, roughness: 0.9 }));
    w.rotation.x = Math.PI / 2;
    const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.5, 0.9, 14),
      new THREE.MeshStandardMaterial({ color: 0xdfe6ee, metalness: 0.4, roughness: 0.4 }));
    cap.rotation.x = Math.PI / 2; w.add(cap);
    for (let b = 0; b < 5; b++) {
      const a = b / 5 * Math.PI * 2;
      const bolt = sphere(0.07, 0x9aa3ad, 0, 0, 0);
      bolt.position.set(Math.cos(a) * 0.3, Math.sin(a) * 0.3, 0.46); w.add(bolt);
    }
    const holder = new THREE.Group(); holder.position.set(x, 1.05, z); holder.add(w);
    body.add(holder);
    wheels.push({ holder, spin: w, front: x > 0 });
  }

  // passenger door (right side) that slides up to open
  const door = rbox(1.7, 2.5, 0.2, 0.18, NAVY, 2.7, 2.45, 1.76);
  body.add(door);

  g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
  return {
    group: g, wheels, door,
    face: { eyeWhiteL: L.white, eyeWhiteR: R.white, pupilL: L.pupil, pupilR: R.pupil, lidL: L.lid, lidR: R.lid, mouth },
  };
}

function rbox(w, h, d, r, color, x, y, z) {
  const m = new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 3, r),
    new THREE.MeshStandardMaterial({ color, roughness: 0.5, metalness: 0.05 }));
  m.position.set(x, y, z || 0); return m;
}
function sphere(r, color, x, y, z) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, 16, 12),
    new THREE.MeshStandardMaterial({ color, roughness: 0.5 }));
  m.position.set(x, y, z); return m;
}
// The destination roller sign on the windshield: a black "120" panel and
// three round indicator lights, drawn on a canvas and faced forward (+X).
function frontSign(x, y, z) {
  const c = document.createElement('canvas'); c.width = 480; c.height = 100;
  const g = c.getContext('2d');
  g.fillStyle = '#f6f3ea'; g.fillRect(0, 0, 480, 100);
  // black "120" box
  g.fillStyle = '#161616'; roundRect(g, 8, 14, 196, 72, 12); g.fill();
  g.fillStyle = '#ffffff'; g.font = 'bold 62px sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText('120', 106, 52);
  // three lights
  const cols = ['#efe2bd', '#6ec6f0', '#efe2bd'];
  cols.forEach((col, i) => {
    g.fillStyle = col; g.beginPath();
    g.arc(268 + i * 78, 50, 30, 0, 7); g.fill();
    g.strokeStyle = '#cabf9a'; g.lineWidth = 3; g.stroke();
  });
  const tex = new THREE.CanvasTexture(c);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(2.5, 0.52),
    new THREE.MeshStandardMaterial({ map: tex }));
  m.rotation.y = Math.PI / 2; m.position.set(x, y, z); return m;
}

function sideNumber(x, y, z, rot) {
  const c = document.createElement('canvas'); c.width = 200; c.height = 120;
  const g = c.getContext('2d');
  g.clearRect(0, 0, 200, 120);
  g.fillStyle = '#16314a'; g.font = 'bold 86px sans-serif';
  g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText('120', 100, 64);
  const tex = new THREE.CanvasTexture(c);
  const m = new THREE.Mesh(new THREE.PlaneGeometry(1.5, 0.9),
    new THREE.MeshStandardMaterial({ map: tex, transparent: true }));
  m.rotation.y = rot; m.position.set(x, y, z); return m;
}

function roundRect(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r); g.closePath();
}

export class Bus {
  constructor(scene) {
    const built = createBusMesh();
    this.mesh = built.group;
    this.wheels = built.wheels;
    this.doorMesh = built.door;
    this.face = built.face;
    scene.add(this.mesh);

    this.pos = new THREE.Vector3(0, 0, 0);
    this.heading = 0;          // radians, 0 = +X
    this.speed = 0;            // units/sec (can be negative for reverse)
    this.steerAngle = 0;       // visual front-wheel angle
    this.maxSpeed = 17;
    this.doorOpen = 0;         // 0..1
    this.blink = 0; this.blinkT = 2 + Math.random() * 3;
    this._wheelRoll = 0;
  }

  reset(x, z, heading) {
    this.pos.set(x, 0, z); this.heading = heading || 0; this.speed = 0;
    this.sync();
  }

  // Integrate one step. Returns the proposed position so the caller can
  // resolve collisions before committing via sync().
  update(dt, input) {
    const accel = 16, brakeForce = 28, drag = 3.2;
    if (input.throttle > 0) this.speed += accel * input.throttle * dt;
    if (input.brake > 0) {
      if (this.speed > 0.2) this.speed -= brakeForce * input.brake * dt;
      else this.speed -= 7 * input.brake * dt;        // gentle reverse
    }
    // natural drag
    if (input.throttle === 0) this.speed -= Math.sign(this.speed) * drag * dt;
    if (Math.abs(this.speed) < 0.05) this.speed = 0;
    this.speed = Math.max(-5, Math.min(this.maxSpeed, this.speed));

    // steering: stronger at speed, only when moving
    const moveFactor = Math.min(1, Math.abs(this.speed) / 5);
    const targetSteer = input.steer * 0.5;
    this.steerAngle += (targetSteer - this.steerAngle) * Math.min(1, dt * 8);
    const turn = input.steer * 2.0 * moveFactor * Math.sign(this.speed);
    this.heading += turn * dt;

    const vx = Math.cos(this.heading) * this.speed * dt;
    const vz = Math.sin(this.heading) * this.speed * dt;
    return { x: this.pos.x + vx, z: this.pos.z + vz };
  }

  commit(x, z) { this.pos.x = x; this.pos.z = z; }

  // Visual update (wheels, doors, face) + transform sync.
  sync(dt = 0) {
    this.mesh.position.set(this.pos.x, 0, this.pos.z);
    this.mesh.rotation.y = -this.heading;     // mesh +X faces heading

    this._wheelRoll += this.speed * dt * 0.9;
    for (const w of this.wheels) {
      w.spin.rotation.y = this._wheelRoll;
      if (w.front) w.holder.rotation.y = this.steerAngle;
    }
    // door slide
    this.doorMesh.position.y = 2.3 + this.doorOpen * 2.4;
    this.doorMesh.scale.y = 1 - this.doorOpen * 0.9;

    // blinking
    if (dt) {
      this.blinkT -= dt;
      if (this.blinkT < 0) { this.blink = 1; this.blinkT = 2.5 + Math.random() * 3.5; }
      if (this.blink > 0) this.blink -= dt * 6;
      const lid = Math.max(0, Math.min(1, this.blink));
      const baseY = this.face.lidL.userData.openY;
      this.face.lidL.scale.y = 0.02 + lid * 0.95;
      this.face.lidR.scale.y = 0.02 + lid * 0.95;
      this.face.lidL.position.y = baseY - lid * 0.72;
      this.face.lidR.position.y = baseY - lid * 0.72;
    }
  }

  setExpression(kind) {
    const m = this.face.mouth;   // base smile is wide + shallow: keep that shape
    if (kind === 'surprised') { m.scale.set(1.0, 1.1, 1); m.rotation.z = 0; }
    else if (kind === 'happy') { m.scale.set(1.8, 0.68, 1); m.rotation.z = Math.PI; }
    else { m.scale.set(1.65, 0.6, 1); m.rotation.z = Math.PI; }
  }

  setDoor(open) { this._doorTarget = open ? 1 : 0; }
  animateDoor(dt) {
    const tgt = this._doorTarget || 0;
    this.doorOpen += (tgt - this.doorOpen) * Math.min(1, dt * 4);
  }

  speed01() { return Math.abs(this.speed) / this.maxSpeed; }
}
