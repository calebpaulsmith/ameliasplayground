// On-screen GPS: a north-up minimap + turn-by-turn direction logic.
// The maths here is calibrated so "left/right" match what the player sees on
// screen (the chase camera puts +Z on the player's right), so the game teaches
// real left and right.

export function normAngle(a) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

// Returns { id, dist, rel } where id is an STR key.
export function gpsInstruction(busPos, heading, target) {
  if (!target) return null;
  const dx = target.x - busPos.x, dz = target.z - busPos.z;
  const dist = Math.hypot(dx, dz);
  const rel = normAngle(Math.atan2(dz, dx) - heading);
  let id;
  if (dist < 9) id = 'arrived';
  else if (dist < 24) id = 'arriving';
  else if (Math.abs(rel) < 0.38) id = 'goStraight';
  else if (Math.abs(rel) > 2.5) id = 'uTurn';
  else if (rel > 0) id = 'turnRight';
  else id = 'turnLeft';
  return { id, dist, rel };
}

export function drawMinimap(canvas, world, busPos, heading, target) {
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  ctx.clearRect(0, 0, W, H);

  const min = -world.CELL, max = world.SPAN + world.CELL;
  const sx = (x) => ((x - min) / (max - min)) * W;
  const sz = (z) => ((z - min) / (max - min)) * H;

  // backdrop
  ctx.fillStyle = '#1b2233'; ctx.fillRect(0, 0, W, H);
  // grass blocks tint
  ctx.fillStyle = '#2b6b35';
  ctx.fillRect(sx(0), sz(0), sx(world.SPAN) - sx(0), sz(world.SPAN) - sz(0));

  // roads
  ctx.strokeStyle = '#6b7686';
  ctx.lineWidth = Math.max(3, (world.ROAD_H * 2 / (max - min)) * W);
  for (let i = 0; i <= world.GRID_N; i++) {
    ctx.beginPath(); ctx.moveTo(sx(i * world.CELL), sz(0)); ctx.lineTo(sx(i * world.CELL), sz(world.SPAN)); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(sx(0), sz(i * world.CELL)); ctx.lineTo(sx(world.SPAN), sz(i * world.CELL)); ctx.stroke();
  }

  // bus stops
  ctx.fillStyle = '#2ee6d6';
  for (const s of world.busStops) { ctx.fillRect(sx(s.x) - 3, sz(s.z) - 3, 6, 6); }

  // traffic lights coloured by state
  for (const tl of world.trafficLights) {
    ctx.fillStyle = tl.state === 'red' ? '#ff3b30' : tl.state === 'yellow' ? '#ffcc00' : '#34c759';
    ctx.beginPath(); ctx.arc(sx(tl.pos.x), sz(tl.pos.z), 3.5, 0, 7); ctx.fill();
  }

  // target pin
  if (target) {
    ctx.fillStyle = '#ffd23f';
    ctx.beginPath(); ctx.arc(sx(target.x), sz(target.z), 6, 0, 7); ctx.fill();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.stroke();
  }

  // bus arrow (heading 0 = +X). Screen y maps from world z.
  const bx = sx(busPos.x), bz = sz(busPos.z);
  ctx.save(); ctx.translate(bx, bz); ctx.rotate(heading);
  ctx.fillStyle = '#3aa0ff'; ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.moveTo(9, 0); ctx.lineTo(-6, -6); ctx.lineTo(-6, 6); ctx.closePath();
  ctx.fill(); ctx.stroke();
  ctx.restore();
}
