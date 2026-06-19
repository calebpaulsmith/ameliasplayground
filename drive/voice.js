// Amelia's voice + sound effects.
// Speech uses the Web Speech API (offline on most devices). Sounds are
// synthesised with WebAudio so there are no audio files to ship.

let AC = null;
function ctx() {
  if (!AC) { try { AC = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) {} }
  if (AC && AC.state === 'suspended') AC.resume();
  return AC;
}

// ---- Speech --------------------------------------------------------------
let voices = [];
function loadVoices() { try { voices = speechSynthesis.getVoices() || []; } catch (e) {} }
if ('speechSynthesis' in window) {
  loadVoices();
  speechSynthesis.onvoiceschanged = loadVoices;
}

function pickVoice(lang) {
  const want = lang === 'es' ? 'es' : 'en';
  // Prefer a cheerful/female voice in the right language when one exists.
  const inLang = voices.filter(v => (v.lang || '').toLowerCase().startsWith(want));
  const nice = inLang.find(v => /female|samantha|mónica|monica|paulina|google/i.test(v.name));
  return nice || inLang[0] || null;
}

let lastSpoken = '';
export function say(text, lang, opts = {}) {
  if (!text || !('speechSynthesis' in window)) return;
  if (!opts.force && text === lastSpoken) return;
  lastSpoken = text;
  try {
    speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.lang = lang === 'es' ? 'es-ES' : 'en-US';
    const v = pickVoice(lang); if (v) u.voice = v;
    u.pitch = opts.pitch != null ? opts.pitch : 1.25; // bright, kid-friendly
    u.rate  = opts.rate  != null ? opts.rate  : 0.98;
    u.volume = 1;
    speechSynthesis.speak(u);
  } catch (e) {}
}
export function clearLastSpoken() { lastSpoken = ''; }

// ---- Sound effects -------------------------------------------------------
function tone(freq, dur, type = 'sine', gain = 0.2, when = 0) {
  const ac = ctx(); if (!ac) return;
  const t0 = ac.currentTime + when;
  const o = ac.createOscillator(), g = ac.createGain();
  o.type = type; o.frequency.setValueAtTime(freq, t0);
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.exponentialRampToValueAtTime(gain, t0 + 0.02);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  o.connect(g); g.connect(ac.destination);
  o.start(t0); o.stop(t0 + dur + 0.02);
  return o;
}

export const SFX = {
  horn() { tone(310, 0.18, 'square', 0.18); tone(233, 0.22, 'square', 0.16, 0.04); },
  chime() { [523, 659, 784].forEach((f, i) => tone(f, 0.4, 'sine', 0.18, i * 0.09)); },
  good() { [659, 880, 1047].forEach((f, i) => tone(f, 0.3, 'triangle', 0.18, i * 0.08)); },
  oops() { tone(220, 0.25, 'sawtooth', 0.14); tone(170, 0.3, 'sawtooth', 0.12, 0.08); },
  doorOpen() { tone(440, 0.12, 'sine', 0.1); tone(660, 0.18, 'sine', 0.1, 0.08); },
  doorClose() { tone(660, 0.12, 'sine', 0.1); tone(440, 0.18, 'sine', 0.1, 0.08); },
  blip() { tone(880, 0.07, 'square', 0.08); },
};

// Continuous engine hum whose pitch tracks speed.
let engine = null;
export function engineStart() {
  const ac = ctx(); if (!ac || engine) return;
  const o = ac.createOscillator(), g = ac.createGain(), lp = ac.createBiquadFilter();
  o.type = 'sawtooth'; o.frequency.value = 60;
  lp.type = 'lowpass'; lp.frequency.value = 360;
  g.gain.value = 0.0001;
  o.connect(lp); lp.connect(g); g.connect(ac.destination);
  o.start();
  engine = { o, g, lp, ac };
}
export function engineUpdate(speed01) {
  if (!engine) return;
  const f = 55 + speed01 * 140;
  engine.o.frequency.setTargetAtTime(f, engine.ac.currentTime, 0.08);
  engine.g.gain.setTargetAtTime(0.018 + speed01 * 0.05, engine.ac.currentTime, 0.1);
  engine.lp.frequency.setTargetAtTime(300 + speed01 * 700, engine.ac.currentTime, 0.1);
}
export function engineStop() {
  if (!engine) return;
  try { engine.g.gain.setTargetAtTime(0.0001, engine.ac.currentTime, 0.1);
        engine.o.stop(engine.ac.currentTime + 0.3); } catch (e) {}
  engine = null;
}

export function resumeAudio() { ctx(); }
