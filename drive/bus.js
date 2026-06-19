// Amelia — a friendly blue talking bus, à la Tayo. Built from primitives so
// she needs no downloaded model. `Bus` wraps a kid-friendly arcade driving
// model; the game loop feeds it input and resolves collisions.

import * as THREE from 'three';

const BLUE = 0x3aa0ff, DKBLUE = 0x1f6fd0, WHITE = 0xfbfdff, GLASS = 0x9fd9ff;

export function createBusMesh() {
  const g = new THREE.Group();
  const body = new THREE.Group(); g.add(body);

  // main body (rounded look via stacked boxes)
  const main = box(7, 4.2, 3.6, BLUE, 0, 3.0, 0); body.add(main);
  body.add(box(7.2, 1.4, 3.8, DKBLUE, 0, 1.3, 0));            // lower skirt
  body.add(box(7.2, 0.6, 3.9, 0x16324f, 0, 0.7, 0));          // bumper line
  body.add(box(6.2, 1.0, 3.4, WHITE, 0, 5.3, 0));             // white roof band
  const rooftop = box(5.4, 0.6, 3.0, BLUE, 0, 5.9, 0); body.add(rooftop);

  // windshield + side windows (glass)
  body.add(box(0.3, 2.0, 3.0, GLASS, 3.55, 3.3, 0));          // front glass
  body.add(box(0.3, 1.6, 3.0, GLASS, -3.55, 3.4, 0));         // rear glass
  for (let s = -1; s <= 1; s += 2)
    for (let k = -1; k <= 1; k++)
      body.add(box(1.6, 1.4, 0.2, GLASS, k * 1.9, 3.5, s * 1.82));

  // face on the front
  const face = new THREE.Group(); face.position.set(3.62, 0, 0); body.add(face);
  const eyeWhiteL = sphere(0.62, WHITE, 0, 3.85, -0.85);
  const eyeWhiteR = sphere(0.62, WHITE, 0, 3.85, 0.85);
  const pupilL = sphere(0.28, 0x16314a, 0.34, 3.85, -0.85);
  const pupilR = sphere(0.28, 0x16314a, 0.34, 3.85, 0.85);
  const lidL = box(1.4, 0.7, 1.4, BLUE, 0.05, 4.5, -0.85); lidL.scale.y = 0.01;
  const lidR = box(1.4, 0.7, 1.4, BLUE, 0.05, 4.5, 0.85); lidR.scale.y = 0.01;
  face.add(eyeWhiteL, eyeWhiteR, pupilL, pupilR, lidL, lidR);
  // smile (a torus arc)
  const mouth = new THREE.Mesh(
    new THREE.TorusGeometry(0.55, 0.12, 8, 16, Math.PI),
    new THREE.MeshStandardMaterial({ color: 0x16314a }));
  mouth.rotation.z = Math.PI; mouth.rotation.y = Math.PI / 2;
  mouth.position.set(0.18, 2.7, 0); face.add(mouth);
  // rosy cheeks
  face.add(sphere(0.24, 0xff9bb0, 0.2, 3.0, -1.2));
  face.add(sphere(0.24, 0xff9bb0, 0.2, 3.0, 1.2));

  // headlights
  body.add(sphere(0.3, 0xfff2a8, 3.58, 1.7, -1.2));
  body.add(sphere(0.3, 0xfff2a8, 3.58, 1.7, 1.2));

  // roof route sign
  const sign = box(2.6, 0.7, 0.2, WHITE, 0.4, 6.3, 1.55);
  body.add(sign);

  // wheels
  const wheels = [];
  const wheelPos = [[2.3, -1.55], [2.3, 1.55], [-2.3, -1.55], [-2.3, 1.55]];
  for (const [x, z] of wheelPos) {
    const w = new THREE.Mesh(new THREE.CylinderGeometry(1.0, 1.0, 0.7, 16),
      new THREE.MeshStandardMaterial({ color: 0x1a1a1f }));
    w.rotation.x = Math.PI / 2; w.position.set(x, 1.0, z); w.castShadow = true;
    const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.4, 0.4, 0.74, 10),
      new THREE.MeshStandardMaterial({ color: 0xcfd6dd }));
    hub.rotation.x = Math.PI / 2; w.add(hub);
    const holder = new THREE.Group(); holder.position.copy(w.position);
    w.position.set(0, 0, 0); holder.add(w);
    body.add(holder);
    wheels.push({ holder, spin: w, front: x > 0 });
  }

  // door (right side) that slides up to open
  const door = box(0.2, 2.6, 2.2, 0x16314a, 3.0, 2.3, 1.85);
  body.add(door);

  main.castShadow = true; body.children.forEach(c => { c.castShadow = true; });
  return { group: g, wheels, door, face: { eyeWhiteL, eyeWhiteR, pupilL, pupilR, lidL, lidR, mouth } };
}

function box(w, h, d, color, x, y, z) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d),
    new THREE.MeshStandardMaterial({ color, roughness: 0.55, metalness: 0.05 }));
  m.position.set(x, y, z); return m;
}
function sphere(r, color, x, y, z) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, 16, 12),
    new THREE.MeshStandardMaterial({ color, roughness: 0.5 }));
  m.position.set(x, y, z); return m;
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
      this.face.lidL.scale.y = 0.01 + lid * 1;
      this.face.lidR.scale.y = 0.01 + lid * 1;
      this.face.lidL.position.y = 4.5 - lid * 0.6;
      this.face.lidR.position.y = 4.5 - lid * 0.6;
    }
  }

  setExpression(kind) {
    const m = this.face.mouth;
    if (kind === 'surprised') { m.scale.set(0.8, 1.4, 0.8); m.rotation.z = 0; }
    else if (kind === 'happy') { m.scale.set(1.2, 1, 1); m.rotation.z = Math.PI; }
    else { m.scale.set(1, 1, 1); m.rotation.z = Math.PI; }
  }

  setDoor(open) { this._doorTarget = open ? 1 : 0; }
  animateDoor(dt) {
    const tgt = this._doorTarget || 0;
    this.doorOpen += (tgt - this.doorOpen) * Math.min(1, dt * 4);
  }

  speed01() { return Math.abs(this.speed) / this.maxSpeed; }
}
