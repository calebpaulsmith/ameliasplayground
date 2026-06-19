// Little passenger characters who wait at bus stops, wave, board Amelia and
// thank her. Built from primitives; designed to be swapped for GLB later.

import * as THREE from 'three';

const PEOPLE = [
  { id: 'pip',   emoji: '🐻', color: 0xff8a3d, es: 'Pip',   en: 'Pip',   place: 'park'   },
  { id: 'lola',  emoji: '🐰', color: 0xff5d9e, es: 'Lola',  en: 'Lola',  place: 'school' },
  { id: 'tomas', emoji: '🐸', color: 0x57b85a, es: 'Tomás', en: 'Tomas', place: 'market' },
  { id: 'mia',   emoji: '🐱', color: 0xa06bff, es: 'Mía',   en: 'Mia',   place: 'beach'  },
];

export function makePassenger(spec) {
  const g = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.CapsuleGeometry(0.7, 1.3, 6, 12),
    new THREE.MeshStandardMaterial({ color: spec.color }));
  body.position.y = 1.4; body.castShadow = true; g.add(body);
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.7, 16, 12),
    new THREE.MeshStandardMaterial({ color: 0xffe0bd }));
  head.position.y = 2.7; head.castShadow = true; g.add(head);
  // eyes
  for (const z of [-0.28, 0.28]) {
    const e = new THREE.Mesh(new THREE.SphereGeometry(0.12, 8, 8),
      new THREE.MeshStandardMaterial({ color: 0x222 }));
    e.position.set(0.6, 2.8, z); g.add(e);
  }
  // an arm that waves
  const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.18, 0.9, 4, 8),
    new THREE.MeshStandardMaterial({ color: spec.color }));
  arm.position.set(0, 2.0, -0.85); g.add(arm);

  return { group: g, arm, spec, _t: Math.random() * 6 };
}

export function animatePassenger(p, dt, waving) {
  p._t += dt;
  p.group.children[0].position.y = 1.4 + Math.sin(p._t * 2) * 0.05; // gentle bob
  if (waving) { p.arm.rotation.x = -2.2 + Math.sin(p._t * 9) * 0.5; }
  else { p.arm.rotation.x = 0; }
}

export function passengerList() { return PEOPLE.slice(); }
