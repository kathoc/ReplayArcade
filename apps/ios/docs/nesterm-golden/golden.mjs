// Golden traces of NESTERM's TouchGamepad (web/brickboy/input.mjs, unmodified) for the Swift port's
// tests. Runs in the harness page (the real DOM + styles.css), with a manual requestAnimationFrame
// and performance.now so every step is deterministic; CSS transitions are switched off so
// getBoundingClientRect sees each state at once.
import { TouchGamepad } from './web/brickboy/input.mjs';

const BTN = { right: 0, left: 1, up: 2, down: 3, a: 4, b: 5, select: 6, start: 7 };

let rafQ = [], rafId = 1, fakeNow = 0;
window.requestAnimationFrame = (cb) => { const id = rafId++; rafQ.push({ id, cb }); return id; };
window.cancelAnimationFrame = (id) => { rafQ = rafQ.filter((r) => r.id !== id); };
Object.defineProperty(performance, 'now', { value: () => fakeNow, configurable: true });

const style = document.createElement('style');
style.textContent = '*, *::before, *::after { transition: none !important; animation: none !important; }';
document.head.append(style);

const r4 = (v) => v;
function rect(el) { const r = el.getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; }

function geometry(touch) {
  const root = document.querySelector('.bb-root');
  const cs = getComputedStyle(root), rr = root.getBoundingClientRect();
  const n = (v) => parseFloat(v) || 0;
  const side = document.querySelector('#app').classList.contains('bb-side');
  const fg = touch.faceGeometry();
  const sys = document.querySelector('.gp-system');
  return {
    viewport: [innerWidth, innerHeight],
    frame: [rr.left + n(cs.paddingLeft), rr.top + n(cs.paddingTop), rr.width - n(cs.paddingLeft) - n(cs.paddingRight), rr.height - n(cs.paddingTop) - n(cs.paddingBottom)],
    dpad: rect(document.querySelector('.gp-dpad')),
    dpadClip: side ? null : rect(document.querySelector('#gamepad')),
    face: rect(document.querySelector('.gp-face')),
    a: [fg.ax, fg.ay], b: [fg.bx, fg.by],
    system: side ? null : rect(sys),
    select: rect(document.querySelector('.gp-key[data-btn="select"]')),
    start: rect(document.querySelector('.gp-key[data-btn="start"]')),
  };
}

function regionAt(x, y) {
  const el = document.elementFromPoint(x, y);
  if (!el) return null;
  if (el.closest('.gp-face')) return 'face';
  if (el.closest('.gp-system')) return 'system';
  if (el.closest('.gp-dpad')) return 'dpad';
  return null;
}

function run(name, build) {
  rafQ = []; rafId = 1; fakeNow = 0;
  const touch = new TouchGamepad(document.querySelector('#gamepad'), () => {}, () => {});
  window.touch = touch;
  touch.setHomeGain(0.3, 1);
  const g = geometry(touch);
  const ops = build(g);
  const captured = new Map();
  const trace = [];
  for (const op of ops) {
    let region = null;
    if (op.op === 'frame') {
      fakeNow = op.t;
      const run = rafQ; rafQ = [];
      for (const r of run) r.cb(op.t);
    } else if (op.op === 'ways') {
      touch.setWays(op.n);
    } else if (op.op === 'gain') {
      touch.setHomeGain(op.x, op.y);
    } else {
      fakeNow = op.t;
      const e = { pointerId: op.id, clientX: op.x, clientY: op.y, timeStamp: op.t, type: op.op === 'cancel' ? 'pointercancel' : 'pointer' + op.op, preventDefault() {} };
      if (op.op === 'down') {
        region = regionAt(op.x, op.y);
        if (region) captured.set(op.id, region);
        if (region === 'dpad') touch.onDpadDown(e);
        else if (region === 'face') touch.onFaceDown(e);
        else if (region === 'system') touch.onSysDown(e);
      } else if (op.op === 'move') {
        const c = captured.get(op.id);
        if (c === 'dpad') touch.onDpadMove(e);
        else if (c === 'face') touch.onFaceMove(e);
        else if (c === 'system') touch.onSysMove(e);
      } else {
        const c = captured.get(op.id); captured.delete(op.id);
        if (c === 'dpad') touch.onDpadUp(e);
        else if (c === 'face') touch.onFaceUp(e);
        else if (c === 'system') touch.onSysUp(e);
        touch.releasePointer(op.id);
      }
    }
    let mask = 0;
    for (const [btn, c] of touch.counts) if (c > 0) mask |= 1 << btn;
    trace.push({ mask, ox: touch.ox, oy: touch.oy, ...(op.op === 'down' ? { region } : {}) });
  }
  return { name, geometry: g, ops, trace };
}

// ---- scenarios (coordinates from the live geometry, times in ms from 1000) ----

function frames(ops, from, to, step = 1000 / 60) { for (let t = from; t <= to + 1e-9; t += step) ops.push({ op: 'frame', t }); }

function dpadSlide(g) {
  const [x, y, w] = g.dpad, cx = x + w / 2, cy = y + w / 2, ops = [];
  ops.push({ op: 'down', id: 1, x: cx, y: cy, t: 1000 });
  frames(ops, 1010, 1040);
  ops.push({ op: 'move', id: 1, x: cx + w * 0.40, y: cy, t: 1050 });
  frames(ops, 1060, 1110);
  ops.push({ op: 'move', id: 1, x: cx + w * 0.34, y: cy - w * 0.34, t: 1120 });
  frames(ops, 1130, 1400);
  ops.push({ op: 'cancel', id: 1, x: cx + w * 0.34, y: cy - w * 0.34, t: 1420 });
  frames(ops, 1430, 2600);
  return ops;
}

function dpadTaps(g) {
  const [x, y, w] = g.dpad, r = w / 2, rx = x + r + 9, ry = y + r + 5, ops = [];
  let t = 1000, id = 10;
  for (let i = 0; i < 16; i++) {
    const th = (i * 3 % 8) * Math.PI / 4 + (i % 2 ? 0.1 : -0.07);
    const reach = r * (0.42 + 0.06 * (i % 3));
    const px = rx + Math.cos(th) * reach, py = ry + Math.sin(th) * reach;
    ops.push({ op: 'down', id, x: px, y: py, t });
    frames(ops, t + 8, t + 60);
    ops.push({ op: 'move', id, x: px + 1.5, y: py - 1, t: t + 64 });
    frames(ops, t + 70, t + 90);
    ops.push({ op: 'up', id, x: px + 1.5, y: py - 1, t: t + 95 });
    frames(ops, t + 100, t + (i === 7 ? 700 : 180));
    t += i === 7 ? 720 : 200; id++;
  }
  frames(ops, t, t + 2000);
  return ops;
}

function dpadHold(g) {
  const [x, y, w] = g.dpad, r = w / 2, cx = x + r, cy = y + r, ops = [];
  ops.push({ op: 'down', id: 1, x: cx + r * 0.75, y: cy + 9, t: 1000 });
  frames(ops, 1010, 2200);
  ops.push({ op: 'move', id: 1, x: cx + r * 0.2, y: cy + r * 0.6, t: 2210 });
  frames(ops, 2220, 2400);
  ops.push({ op: 'move', id: 1, x: cx - r * 0.1, y: cy + r * 0.7, t: 2410 });
  frames(ops, 2420, 3000);
  ops.push({ op: 'up', id: 1, x: cx - r * 0.1, y: cy + r * 0.7, t: 3010 });
  frames(ops, 3020, 4200);
  // Far left, held: the home walks left until the visible edge stops it.
  ops.push({ op: 'down', id: 2, x: cx - r * 0.9, y: cy - 3, t: 4300 });
  frames(ops, 4310, 6500);
  ops.push({ op: 'up', id: 2, x: cx - r * 0.9, y: cy - 3, t: 6510 });
  frames(ops, 6520, 7000);
  return ops;
}

function dpadSweep(g) {
  const [x, y, w] = g.dpad, r = w / 2, cx = x + r, cy = y + r, ops = [];
  let t = 1000;
  ops.push({ op: 'down', id: 1, x: cx - r * 0.6, y: cy + 8, t });
  for (let k = 0; k < 120; k++) {
    t += 8;
    const ph = Math.sin(k / 9) * r * 0.65;
    ops.push({ op: 'move', id: 1, x: cx + ph, y: cy + 8 + Math.sin(k / 5) * 2, t });
    if (k % 2) ops.push({ op: 'frame', t: t + 0.5 });
  }
  ops.push({ op: 'up', id: 1, x: cx, y: cy + 8, t: t + 10 });
  frames(ops, t + 20, t + 300);
  return ops;
}

function dpadWays(g) {
  const [x, y, w] = g.dpad, cx = x + w / 2, cy = y + w / 2, ops = [];
  ops.push({ op: 'ways', n: 4 });
  ops.push({ op: 'down', id: 2, x: cx, y: cy, t: 1000 });
  frames(ops, 1010, 1030);
  ops.push({ op: 'move', id: 2, x: cx + w * 0.34, y: cy - w * 0.34, t: 1040 });
  frames(ops, 1050, 1200);
  ops.push({ op: 'move', id: 2, x: cx - w * 0.30, y: cy - w * 0.36, t: 1210 });
  frames(ops, 1220, 1300);
  ops.push({ op: 'ways', n: 8 });
  frames(ops, 1310, 1400);
  ops.push({ op: 'up', id: 2, x: cx - w * 0.30, y: cy - w * 0.36, t: 1410 });
  frames(ops, 1420, 1500);
  return ops;
}

function dpadTwo(g) {
  const [x, y, w] = g.dpad, cx = x + w / 2, cy = y + w / 2, ops = [];
  ops.push({ op: 'down', id: 1, x: cx, y: cy - w * 0.4, t: 1000 });
  frames(ops, 1010, 1060);
  ops.push({ op: 'down', id: 2, x: cx + w * 0.4, y: cy, t: 1070 });
  frames(ops, 1080, 1120);
  ops.push({ op: 'move', id: 1, x: cx - w * 0.4, y: cy, t: 1130 });
  ops.push({ op: 'move', id: 2, x: cx + w * 0.38, y: cy + w * 0.3, t: 1140 });
  frames(ops, 1150, 1200);
  ops.push({ op: 'up', id: 2, x: cx + w * 0.38, y: cy + w * 0.3, t: 1210 });
  ops.push({ op: 'up', id: 1, x: cx - w * 0.4, y: cy, t: 1220 });
  // .gp-ext: above the pad (inside its hit extension), then outside everything.
  ops.push({ op: 'down', id: 3, x: cx, y: y - w * 0.2, t: 1300 });
  frames(ops, 1310, 1330);
  ops.push({ op: 'up', id: 3, x: cx, y: y - w * 0.2, t: 1340 });
  ops.push({ op: 'down', id: 4, x: x + w + 20, y: y - w * 0.5, t: 1400 });
  ops.push({ op: 'up', id: 4, x: x + w + 20, y: y - w * 0.5, t: 1410 });
  frames(ops, 1420, 1700);
  return ops;
}

// scripts/controller-check.mjs face sequences (positions along B→A), with event times.
function face(g) {
  const [ax, ay] = g.a, [bx, by] = g.b, ops = [];
  const along = (f) => ({ x: bx + (ax - bx) * f, y: by + (ay - by) * f });
  const fromA = (f) => ({ x: ax + (bx - ax) * f, y: ay + (by - ay) * f });
  let t = 1000;
  const at = (op, id, p, dt = 40) => { t += dt; ops.push({ op, id, x: p.x, y: p.y, t }); };
  const mid = along(0.5);
  at('down', 3, along(0)); at('move', 3, mid); at('move', 3, along(1)); at('up', 3, along(1));
  at('down', 4, along(1)); at('down', 5, along(0)); at('up', 5, along(0)); at('up', 4, along(1));
  at('down', 6, along(0)); at('move', 6, along(.55)); at('move', 6, along(.40)); at('move', 6, along(.56)); at('move', 6, along(.42)); at('up', 6, along(.42));
  at('down', 7, along(0), 300); at('move', 7, along(.18), 60); at('move', 7, along(.04)); at('up', 7, along(.04));
  at('down', 8, along(0), 300); for (let k = 1; k <= 6; k++) at('move', 8, along(.03 * k), 150); at('up', 8, along(.18), 120);
  at('down', 9, fromA(0), 300); at('move', 9, fromA(.55)); at('move', 9, fromA(.40)); at('up', 9, fromA(.40));
  at('down', 10, along(0), 300); at('move', 10, along(.55)); at('move', 10, along(.42));
  for (const f of [.45, .48, .51]) at('move', 10, along(f), 150);
  at('move', 10, along(.65), 120); at('up', 10, along(.65));
  at('down', 11, along(.45), 300); at('move', 11, along(.35)); at('up', 11, along(.35));
  // Second finger latch that walks off (FACE_LATCH_TRAVEL), and a perpendicular wobble.
  at('down', 12, along(0), 300); at('down', 13, along(0.1)); at('move', 13, { x: along(0.1).x + 8, y: along(0.1).y - 35 }); at('move', 13, along(1)); at('up', 13, along(1)); at('up', 12, along(0));
  at('down', 14, along(0.05), 300);
  for (let k = 1; k <= 8; k++) { const p = along(0.05 + 0.02 * k); at('move', 14, { x: p.x + (k % 2 ? 6 : -6), y: p.y + (k % 2 ? -6 : 6) }, 20); }
  at('up', 14, along(0.21));
  return ops;
}

function system(g) {
  const s = [g.select[0] + g.select[2] / 2, g.select[1] + g.select[3] / 2];
  const t0 = [g.start[0] + g.start[2] / 2, g.start[1] + g.start[3] / 2];
  const m = [(s[0] + t0[0]) / 2, (s[1] + t0[1]) / 2], ops = [];
  ops.push({ op: 'down', id: 6, x: m[0], y: m[1], t: 1000 });
  ops.push({ op: 'move', id: 6, x: s[0], y: s[1], t: 1040 });
  ops.push({ op: 'move', id: 6, x: t0[0], y: t0[1], t: 1080 });
  ops.push({ op: 'up', id: 6, x: t0[0], y: t0[1], t: 1120 });
  ops.push({ op: 'down', id: 7, x: s[0] - 20, y: s[1] + 3, t: 1200 });
  ops.push({ op: 'down', id: 8, x: t0[0] + 15, y: t0[1], t: 1210 });
  ops.push({ op: 'up', id: 7, x: s[0] - 20, y: s[1] + 3, t: 1260 });
  ops.push({ op: 'up', id: 8, x: t0[0] + 15, y: t0[1], t: 1270 });
  return ops;
}

window.runGolden = async (label) => {
  const all = [dpadSlide, dpadTaps, dpadHold, dpadSweep, dpadWays, dpadTwo, face, system].map((f) => run(f.name, f));
  const body = JSON.stringify({ label, viewport: [innerWidth, innerHeight], scenarios: all });
  await fetch(`/save/golden-${label}.json`, { method: 'POST', body });
  return all.map((s) => `${s.name}:${s.ops.length}`).join(' ');
};
