// Input: touch buttons + keyboard + gamepad, blended into one steering model.
// Everything writes into the shared `Input` object that the game loop reads.

export const Input = {
  steer: 0,        // -1 (left) .. +1 (right)
  throttle: 0,     // 0..1
  brake: 0,        // 0..1
  hornPressed: false,
};

// Pointer-held buttons: value while finger/mouse is down.
let touchSteer = 0, touchThrottle = 0, touchBrake = 0;
const keys = new Set();

function holdBtn(el, onDown, onUp) {
  if (!el) return;
  const down = (e) => { e.preventDefault(); onDown(); };
  const up   = (e) => { e.preventDefault(); onUp(); };
  el.addEventListener('pointerdown', down);
  el.addEventListener('pointerup', up);
  el.addEventListener('pointercancel', up);
  el.addEventListener('pointerleave', up);
  el.addEventListener('lostpointercapture', up);
}

export function initControls(ids, onHorn) {
  holdBtn(document.getElementById(ids.left),  () => touchSteer = -1, () => { if (touchSteer < 0) touchSteer = 0; });
  holdBtn(document.getElementById(ids.right), () => touchSteer =  1, () => { if (touchSteer > 0) touchSteer = 0; });
  holdBtn(document.getElementById(ids.go),    () => touchThrottle = 1, () => touchThrottle = 0);
  holdBtn(document.getElementById(ids.stop),  () => touchBrake = 1,    () => touchBrake = 0);
  const horn = document.getElementById(ids.horn);
  if (horn) horn.addEventListener('pointerdown', (e) => { e.preventDefault(); Input.hornPressed = true; if (onHorn) onHorn(); });

  window.addEventListener('keydown', (e) => {
    const k = e.key.toLowerCase();
    if (['arrowleft','arrowright','arrowup','arrowdown',' '].includes(k) || k === ' ') e.preventDefault();
    if (k === 'h' && !keys.has('h')) { Input.hornPressed = true; if (onHorn) onHorn(); }
    keys.add(k);
  });
  window.addEventListener('keyup', (e) => keys.delete(e.key.toLowerCase()));
}

function gamepad() {
  if (!navigator.getGamepads) return null;
  const pads = navigator.getGamepads();
  for (const p of pads) if (p && p.connected) return p;
  return null;
}

// Call once per frame to refresh the blended input.
export function pollInput(onHorn) {
  let steer = touchSteer, throttle = touchThrottle, brake = touchBrake;

  // Keyboard
  if (keys.has('arrowleft') || keys.has('a')) steer = -1;
  if (keys.has('arrowright') || keys.has('d')) steer = 1;
  if (keys.has('arrowup') || keys.has('w')) throttle = 1;
  if (keys.has('arrowdown') || keys.has('s') || keys.has(' ')) brake = 1;

  // Gamepad
  const gp = gamepad();
  if (gp) {
    const ax = gp.axes[0] || 0;
    if (Math.abs(ax) > 0.15) steer = Math.max(-1, Math.min(1, ax));
    const rt = gp.buttons[7] ? gp.buttons[7].value : 0;   // right trigger = go
    const lt = gp.buttons[6] ? gp.buttons[6].value : 0;   // left trigger = brake
    const a  = gp.buttons[0] && gp.buttons[0].pressed;     // A = go
    if (rt > 0.1 || a) throttle = Math.max(throttle, a ? 1 : rt);
    if (lt > 0.1 || (gp.buttons[1] && gp.buttons[1].pressed)) brake = 1;
    if (gp.buttons[3] && gp.buttons[3].pressed && !Input._gpHorn) { Input.hornPressed = true; if (onHorn) onHorn(); }
    Input._gpHorn = gp.buttons[3] && gp.buttons[3].pressed;
    // d-pad steering
    if (gp.buttons[14] && gp.buttons[14].pressed) steer = -1;
    if (gp.buttons[15] && gp.buttons[15].pressed) steer = 1;
  }

  Input.steer = steer;
  Input.throttle = throttle;
  Input.brake = brake;
}

export function consumeHorn() { const h = Input.hornPressed; Input.hornPressed = false; return h; }
