// Story mode: a sequence of "beats" that turn free driving into a guided
// adventure. Missions own the objective; the HUD turns the objective into
// turn-by-turn GPS cues. Hooks let the game loop react (speak, board, etc.).

import { passengerList } from './npc.js';

export class Story {
  constructor(world, hooks) {
    this.world = world;
    this.hooks = hooks;          // { say(id,vars), board(spec,placeName), drop(spec,placeName), setTarget(t), complete() }
    this.beats = [];
    this.i = -1;
    this.wait = 0;
    this.activePassenger = null;
    this.done = false;
    this._build();
  }

  _build() {
    const stops = this.world.busStops;
    const places = this.world.places;
    const people = passengerList().filter(p => places[p.place]);
    const ride = people.slice(0, Math.min(2, stops.length)); // two deliveries for v1

    this.beats.push({ type: 'say', id: 'mDawn' });
    this.beats.push({ type: 'say', id: 'mGoStop' });

    ride.forEach((p, idx) => {
      const stop = stops[idx];
      this.beats.push({ type: 'goto', target: { x: stop.x, z: stop.z, label: 'stop' }, radius: 12, stop: true, arriveId: 'mPickup' });
      this.beats.push({ type: 'board', passenger: p });
      const place = places[p.place];
      this.beats.push({
        type: 'goto', target: { x: place.x, z: place.z, label: p.place }, radius: 12, stop: true,
        sayId: 'mDropoff', sayVars: () => ({ name: p[this.hooks.lang()], place: this.hooks.placeName(p.place) }),
      });
      this.beats.push({ type: 'drop', passenger: p, place: p.place });
    });

    const g = places.garage;
    this.beats.push({ type: 'goto', target: { x: g.x, z: g.z, label: 'garage' }, radius: 13, stop: true, arriveId: 'mHome' });
    this.beats.push({ type: 'complete' });
  }

  start() { this.i = -1; this._next(); }

  _next() {
    this.i++;
    if (this.i >= this.beats.length) { this.done = true; this.hooks.setTarget(null); return; }
    const b = this.beats[this.i];
    if (b.type === 'say') {
      this.hooks.say(b.id);
      this.wait = 2.4;
    } else if (b.type === 'goto') {
      this.hooks.setTarget(b.target);
      if (b.sayId) this.hooks.say(b.sayId, b.sayVars ? b.sayVars() : null);
      this._arrived = false;
    } else if (b.type === 'board') {
      this.activePassenger = b.passenger;
      this.hooks.board(b.passenger);
      this.hooks.say('mBoarded', { name: b.passenger[this.hooks.lang()] });
      this.wait = 2.2;
    } else if (b.type === 'drop') {
      this.hooks.drop(b.passenger, b.place);
      this.hooks.say('mDelivered', { name: b.passenger[this.hooks.lang()], place: this.hooks.placeName(b.place) });
      this.activePassenger = null;
      this.wait = 2.6;
    } else if (b.type === 'complete') {
      this.hooks.complete();
      this.done = true;
      this.hooks.setTarget(null);
    }
  }

  currentTarget() {
    const b = this.beats[this.i];
    return b && b.type === 'goto' ? b.target : null;
  }

  update(dt, busPos, busSpeed) {
    if (this.done || this.i < 0) return;
    if (this.wait > 0) { this.wait -= dt; if (this.wait <= 0) this._next(); return; }

    const b = this.beats[this.i];
    if (!b) return;
    if (b.type === 'goto') {
      const dx = busPos.x - b.target.x, dz = busPos.z - b.target.z;
      const dist = Math.hypot(dx, dz);
      const near = dist <= b.radius;
      const stoppedEnough = !b.stop || Math.abs(busSpeed) < 2.2;
      if (near && !this._arrived) {
        this._arrived = true;
        if (b.arriveId) this.hooks.say(b.arriveId);
      }
      if (near && stoppedEnough) { this.wait = 0.6; this._advanceAfterArrive = true; this._next(); }
    }
  }
}
