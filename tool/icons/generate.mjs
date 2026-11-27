// Builds Piggybow's launcher icons and splash art from tool/icons/src/*.svg (byte copies of the
// design files). No dependencies: Node's standard library only. Deterministic.
//
//   node tool/icons/generate.mjs [repo root]
//
// Writes:
// - android/app/src/main/res/drawable/ic_launcher_foreground.xml   adaptive foreground (vector)
// - android/app/src/main/res/drawable/ic_launcher_monochrome.xml   themed icon, line art (vector)
// - android/app/src/main/res/drawable/ic_notification.xml          the reminder's small icon (vector)
// - android/app/src/main/res/drawable/splash_pig.xml               the calm pig, 160 dp (vector)
// - android/app/src/main/res/drawable/splash_icon.xml              Android 12+ splash icon, 288 dp (vector)
// - android/app/src/main/res/mipmap-*/ic_launcher.png              legacy icons, rounded tile (RGBA)
// - ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png             every size its Contents.json lists (RGB, no alpha)
// - ios/Runner/Assets.xcassets/LaunchImage.imageset/*.png           the calm pig, 160 pt at 1x/2x/3x (RGBA)

import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import zlib from 'node:zlib';

const ROOT = path.resolve(process.argv[2] ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..'));
const SRC = path.join(ROOT, 'tool', 'icons', 'src');
const RES = path.join(ROOT, 'android', 'app', 'src', 'main', 'res');
const XC = path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets');

const ICON = readFileSync(path.join(SRC, 'icon.svg'), 'utf8');
const PIG = readFileSync(path.join(SRC, 'pig-calm.svg'), 'utf8');

// ---------------------------------------------------------------- SVG subset ----
// rect (x, y, width, height, rx), ellipse, circle, path (M L H V Q A Z, absolute; circular A),
// fill / stroke / stroke-width / opacity, and <g transform="translate(a,b) scale(s)">.

function attrsOf(s) {
  const a = {};
  s.replace(/([\w:-]+)="([^"]*)"/g, (_, k, v) => {
    a[k] = v;
  });
  return a;
}

/** Every drawable element, with its group's transform (x' = s*x + tx). */
function shapesOf(svg) {
  const unsupported = /<(text|image|use|linearGradient|radialGradient|polygon|polyline|line|filter|mask|clipPath)\b/i.exec(svg);
  if (unsupported) throw new Error('unsupported element <' + unsupported[1] + '>');
  const viewBox = /viewBox="([^"]+)"/.exec(svg)[1].trim().split(/[\s,]+/).map(Number);
  const out = [];
  const stack = [{ tx: 0, ty: 0, s: 1 }];
  const re = /<(\/?)(g|ellipse|circle|rect|path)\b([^>]*?)\/?>/g;
  let m;
  while ((m = re.exec(svg))) {
    const [, close, tag, raw] = m;
    const t = stack[stack.length - 1];
    if (tag === 'g') {
      if (close) {
        stack.pop();
        continue;
      }
      const a = attrsOf(raw);
      const tr = /translate\(([-\d.]+)[ ,]+([-\d.]+)\)/.exec(a.transform || '');
      const sc = /scale\(([-\d.]+)\)/.exec(a.transform || '');
      const tx = tr ? +tr[1] : 0;
      const ty = tr ? +tr[2] : 0;
      const s = sc ? +sc[1] : 1;
      stack.push({ tx: t.tx + t.s * tx, ty: t.ty + t.s * ty, s: t.s * s });
      continue;
    }
    if (close) continue;
    out.push({ tag, a: attrsOf(raw), t: { ...t } });
  }
  return { viewBox, shapes: out };
}

const fmt = (n) => {
  const r = Math.round(n * 1000) / 1000;
  return Object.is(r, -0) ? '0' : String(r);
};

/** The shape as path data in its own coordinates (VectorDrawable paths use SVG syntax). */
function pathData({ tag, a }) {
  if (tag === 'path') return a.d;
  if (tag === 'ellipse' || tag === 'circle') {
    const cx = +a.cx;
    const cy = +a.cy;
    const rx = +(a.rx ?? a.r);
    const ry = +(a.ry ?? a.r);
    return `M${fmt(cx - rx)},${fmt(cy)} a${fmt(rx)},${fmt(ry)} 0 1,0 ${fmt(2 * rx)},0 a${fmt(rx)},${fmt(ry)} 0 1,0 ${fmt(-2 * rx)},0 Z`;
  }
  if (tag === 'rect') {
    const x = +(a.x || 0);
    const y = +(a.y || 0);
    const w = +a.width;
    const h = +a.height;
    const r = Math.min(+(a.rx || 0), w / 2, h / 2);
    if (!r) return `M${fmt(x)},${fmt(y)} h${fmt(w)} v${fmt(h)} h${fmt(-w)} Z`;
    return (
      `M${fmt(x + r)},${fmt(y)} h${fmt(w - 2 * r)} a${fmt(r)},${fmt(r)} 0 0,1 ${fmt(r)},${fmt(r)} ` +
      `v${fmt(h - 2 * r)} a${fmt(r)},${fmt(r)} 0 0,1 ${fmt(-r)},${fmt(r)} h${fmt(-(w - 2 * r))} ` +
      `a${fmt(r)},${fmt(r)} 0 0,1 ${fmt(-r)},${fmt(-r)} v${fmt(-(h - 2 * r))} a${fmt(r)},${fmt(r)} 0 0,1 ${fmt(r)},${fmt(-r)} Z`
    );
  }
  throw new Error('no path for <' + tag + '>');
}

const argb = (hex) => '#FF' + hex.slice(1).toUpperCase();

/** One VectorDrawable <path> for a shape, in colour or in white (monochrome). */
function vectorPath(shape, { white = false, outline = 0 } = {}) {
  const { a } = shape;
  const d = pathData(shape);
  const alpha = a.opacity !== undefined && !white ? ` android:fillAlpha="${a.opacity}" android:strokeAlpha="${a.opacity}"` : '';
  if (outline) {
    return `<path android:strokeColor="#FFFFFFFF" android:strokeWidth="${outline}" android:strokeLineJoin="round" android:pathData="${d}"/>`;
  }
  if (a.stroke && a.stroke !== 'none') {
    const colour = white ? '#FFFFFFFF' : argb(a.stroke);
    return `<path android:strokeColor="${colour}" android:strokeWidth="${a['stroke-width']}" android:strokeLineCap="round"${alpha} android:pathData="${d}"/>`;
  }
  const colour = white ? '#FFFFFFFF' : argb(a.fill);
  return `<path android:fillColor="${colour}"${alpha} android:pathData="${d}"/>`;
}

/** Wraps paths in nested groups: the outer placement, then each shape's own SVG group transform. */
function grouped(shapes, render) {
  const lines = [];
  let open = null;
  for (const sh of shapes) {
    const key = `${sh.t.tx},${sh.t.ty},${sh.t.s}`;
    if (key !== open) {
      if (open !== null) lines.push('        </group>');
      lines.push(
        `        <group android:translateX="${fmt(sh.t.tx)}" android:translateY="${fmt(sh.t.ty)}" android:scaleX="${fmt(sh.t.s)}" android:scaleY="${fmt(sh.t.s)}">`,
      );
      open = key;
    }
    lines.push('            ' + render(sh));
  }
  if (open !== null) lines.push('        </group>');
  return lines.join('\n');
}

function vector({ comment, size, viewport, scale, translateX, translateY, body }) {
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- ${comment}
     Generated by tool/icons/generate.mjs from tool/icons/src; edit those, not this file. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="${size}dp"
    android:height="${size}dp"
    android:viewportWidth="${viewport}"
    android:viewportHeight="${viewport}">
    <group
        android:scaleX="${fmt(scale)}"
        android:scaleY="${fmt(scale)}"
        android:translateX="${fmt(translateX)}"
        android:translateY="${fmt(translateY)}">
${body}
    </group>
</vector>
`;
}

// The icon's art without its cream tile (the tile is the adaptive background colour).
const icon = shapesOf(ICON);
const iconArt = icon.shapes.filter((s) => !(s.tag === 'rect' && s.a.width === '512' && s.a.height === '512'));
if (iconArt.length !== icon.shapes.length - 1) throw new Error("icon.svg: the 512 x 512 tile wasn't found exactly once");

// Adaptive icon: a 108 dp canvas whose visible centre is 72 dp (the 512 tile maps onto it), with a
// 66 dp safe circle. The art's farthest point (the outer arc's top, stroke included) is about 229
// units from the centre; 0.94 of the tile keeps it near 30 dp from the centre, inside the 33 dp safe radius.
const ADAPTIVE = (72 / 512) * 0.94;
const adaptiveShift = (108 - 512 * ADAPTIVE) / 2;

const foreground = vector({
  comment: 'Adaptive icon foreground: the rainbow and the pig from icon.svg, inside the 66 dp safe zone.',
  size: 108,
  viewport: 108,
  scale: ADAPTIVE,
  translateX: adaptiveShift,
  translateY: adaptiveShift,
  body: grouped(iconArt, (s) => vectorPath(s)),
});

// Monochrome (themed icons, Android 13+): only the alpha counts, so the face is drawn as lines:
// the arcs, the body's outline, the slot, the eyes, the snout's outline, the nostrils and the mouth.
// The shadow and the cheeks are left out.
function monochromeShape(s) {
  const { tag, a } = s;
  if (tag === 'ellipse' && a.cy === '184') return null; // shadow
  if (tag === 'ellipse' && (a.cx === '46' || a.cx === '154')) return null; // cheeks
  if (tag === 'path' && a.fill && a.fill !== 'none') return vectorPath(s, { outline: 7 }); // body
  if (tag === 'ellipse' && a.rx === '20') return vectorPath(s, { outline: 4 }); // snout
  return vectorPath(s, { white: true });
}
const monochrome = vector({
  comment: 'Themed icon (Android 13+): line art in white; the system uses only its alpha and tints it.',
  size: 108,
  viewport: 108,
  scale: ADAPTIVE,
  translateX: adaptiveShift,
  translateY: adaptiveShift,
  body: grouped(
    iconArt.filter((s) => monochromeShape(s) !== null),
    (s) => monochromeShape(s),
  ),
});

// The notification's small icon: white on clear, one even-odd path, so the snout, the eyes and the
// coin slot are holes in the dome. Pig units (0-200) mapped into 24 dp with 1 dp of padding.
const pig = shapesOf(PIG);
const body = pig.shapes.find((s) => s.tag === 'path' && s.a.fill && s.a.fill !== 'none');
const holes = [
  { tag: 'circle', a: { cx: '62', cy: '118', r: '9' } },
  { tag: 'circle', a: { cx: '138', cy: '118', r: '9' } },
  { tag: 'ellipse', a: { cx: '100', cy: '132', rx: '21', ry: '14' } },
  { tag: 'rect', a: { x: '84', y: '70', width: '32', height: '7', rx: '3.5' } },
];
const NOTE = 22 / 156; // the body is 156 units wide (x 22-178)
const notification = `<?xml version="1.0" encoding="utf-8"?>
<!-- The reminder's small icon: the pig's dome in white on clear (the system colours it), with the
     eyes, the snout and the coin slot cut out.
     Generated by tool/icons/generate.mjs from tool/icons/src; edit those, not this file. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <group
        android:scaleX="${fmt(NOTE)}"
        android:scaleY="${fmt(NOTE)}"
        android:translateX="${fmt(1 - 22 * NOTE)}"
        android:translateY="${fmt(12 - 121 * NOTE)}">
        <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd" android:pathData="${[body, ...holes].map(pathData).join(' ')}"/>
    </group>
</vector>
`;

// The calm pig for the splash: 160 dp on the launch background (Android before 12) ...
const splashPig = vector({
  comment: 'Splash: the calm pig (pig-calm.svg), centred on the launch background.',
  size: 160,
  viewport: 200,
  scale: 1,
  translateX: 0,
  translateY: 0,
  body: grouped(pig.shapes, (s) => vectorPath(s)),
});

// ... and Android 12+'s splash icon: 288 dp, art within the 192 dp circle. The pig's farthest point
// is about 98 units from its centre (100, 121); 0.92 keeps it about 90 dp from the centre.
const SPLASH12 = 0.92;
const splashIcon = vector({
  comment: 'Android 12+ splash icon: the calm pig, inside the 192 dp circle of a 288 dp canvas.',
  size: 288,
  viewport: 288,
  scale: SPLASH12,
  translateX: 144 - 100 * SPLASH12,
  translateY: 144 - 121 * SPLASH12,
  body: grouped(pig.shapes, (s) => vectorPath(s)),
});

// ---------------------------------------------------------------- raster ----
const SS = 3;

function hex(c) {
  if (!c || c === 'none') return null;
  const m = /^#([0-9a-f]{6})$/i.exec(c);
  if (!m) throw new Error('colour ' + c);
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function arc(pts, [x1, y1], r, large, sweep, x2, y2) {
  const dx = (x1 - x2) / 2;
  const dy = (y1 - y2) / 2;
  const d2 = dx * dx + dy * dy;
  const rr = Math.max(r, Math.sqrt(d2));
  const k = (large !== sweep ? 1 : -1) * Math.sqrt(Math.max(0, (rr * rr - d2) / d2));
  const cx = (x1 + x2) / 2 + k * dy;
  const cy = (y1 + y2) / 2 - k * dx;
  const a1 = Math.atan2(y1 - cy, x1 - cx);
  let da = Math.atan2(y2 - cy, x2 - cx) - a1;
  if (sweep && da < 0) da += 2 * Math.PI;
  if (!sweep && da > 0) da -= 2 * Math.PI;
  const n = Math.max(8, Math.ceil(Math.abs(da) / (Math.PI / 180)));
  for (let i = 1; i <= n; i++) {
    const a = a1 + (da * i) / n;
    pts.push([cx + rr * Math.cos(a), cy + rr * Math.sin(a)]);
  }
}

function flatten(d) {
  const tok = d.match(/[MLHVQAZ]|-?\d*\.?\d+/gi);
  let i = 0;
  let cmd = null;
  let cur = [0, 0];
  let start = [0, 0];
  let sp = null;
  const subs = [];
  const num = () => +tok[i++];
  while (i < tok.length) {
    if (/[A-Za-z]/.test(tok[i])) cmd = tok[i++].toUpperCase();
    if (cmd === 'M') {
      const x = num();
      const y = num();
      sp = { pts: [[x, y]], closed: false };
      subs.push(sp);
      cur = start = [x, y];
      cmd = 'L';
    } else if (cmd === 'L') {
      const x = num();
      const y = num();
      sp.pts.push([x, y]);
      cur = [x, y];
    } else if (cmd === 'Q') {
      const x1 = num();
      const y1 = num();
      const x = num();
      const y = num();
      for (let k = 1; k <= 32; k++) {
        const t = k / 32;
        const u = 1 - t;
        sp.pts.push([u * u * cur[0] + 2 * u * t * x1 + t * t * x, u * u * cur[1] + 2 * u * t * y1 + t * t * y]);
      }
      cur = [x, y];
    } else if (cmd === 'A') {
      const r = num();
      num();
      num();
      const large = num();
      const sweep = num();
      const x = num();
      const y = num();
      arc(sp.pts, cur, r, large, sweep, x, y);
      cur = [x, y];
    } else if (cmd === 'Z') {
      sp.closed = true;
      cur = start;
    } else throw new Error('path command ' + cmd);
  }
  return subs;
}

function dseg2(px, py, [ax, ay], [bx, by]) {
  const vx = bx - ax;
  const vy = by - ay;
  const L = vx * vx + vy * vy;
  const t = L ? Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / L)) : 0;
  const qx = ax + t * vx - px;
  const qy = ay + t * vy - py;
  return qx * qx + qy * qy;
}

function rasterShapes(svg) {
  const { viewBox, shapes } = shapesOf(svg);
  return {
    viewBox,
    shapes: shapes.map(({ tag, a, t }) => {
      const X = (x) => t.s * x + t.tx;
      const Y = (y) => t.s * y + t.ty;
      const sh = {
        op: a.opacity !== undefined ? +a.opacity : 1,
        fill: a.fill === undefined ? [0, 0, 0] : hex(a.fill),
        stroke: a.stroke ? hex(a.stroke) : null,
        sw: (a['stroke-width'] ? +a['stroke-width'] : 0) * t.s,
        segs: [],
      };
      if (tag === 'ellipse' || tag === 'circle') {
        const cx = X(+a.cx);
        const cy = Y(+a.cy);
        const rx = t.s * +(a.rx ?? a.r);
        const ry = t.s * +(a.ry ?? a.r);
        sh.inside = (x, y) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
        sh.bb = [cx - rx, cy - ry, cx + rx, cy + ry];
      } else if (tag === 'rect') {
        const x0 = X(+(a.x || 0));
        const y0 = Y(+(a.y || 0));
        const w = t.s * +a.width;
        const h = t.s * +a.height;
        const r = t.s * +(a.rx || 0);
        sh.inside = (x, y) => {
          if (x < x0 || x > x0 + w || y < y0 || y > y0 + h) return false;
          const dx = Math.max(x0 + r - x, 0, x - (x0 + w - r));
          const dy = Math.max(y0 + r - y, 0, y - (y0 + h - r));
          return dx * dx + dy * dy <= r * r;
        };
        sh.bb = [x0, y0, x0 + w, y0 + h];
      } else {
        const subs = flatten(a.d).map((p) => ({ pts: p.pts.map(([x, y]) => [X(x), Y(y)]), closed: p.closed }));
        for (const p of subs) {
          for (let i = 0; i + 1 < p.pts.length; i++) sh.segs.push([p.pts[i], p.pts[i + 1]]);
          if (p.closed && p.pts.length > 1) sh.segs.push([p.pts[p.pts.length - 1], p.pts[0]]);
        }
        sh.inside = (x, y) => {
          let c = false;
          for (const p of subs) {
            const q = p.pts;
            for (let i = 0, j = q.length - 1; i < q.length; j = i++) {
              const [xi, yi] = q[i];
              const [xj, yj] = q[j];
              if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
            }
          }
          return c;
        };
        const xs = subs.flatMap((p) => p.pts.map((q) => q[0]));
        const ys = subs.flatMap((p) => p.pts.map((q) => q[1]));
        sh.bb = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
      }
      const pad = sh.sw / 2 + 1;
      sh.bb = [sh.bb[0] - pad, sh.bb[1] - pad, sh.bb[2] + pad, sh.bb[3] + pad];
      return sh;
    }),
  };
}

/** RGBA pixels (0-255) of [svg] at exactly W x H (the viewBox must be square or match). */
function render(svg, W, H) {
  const { viewBox: vb, shapes } = rasterShapes(svg);
  const S = W / vb[2];
  if (Math.abs(vb[3] * S - H) > 1e-6) throw new Error('aspect ratio');
  const out = Buffer.alloc(W * H * 4);
  for (let py = 0; py < H; py++) {
    for (let qx = 0; qx < W; qx++) {
      let R = 0;
      let G = 0;
      let B = 0;
      let A = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const x = vb[0] + (qx + (sx + 0.5) / SS) / S;
          const y = vb[1] + (py + (sy + 0.5) / SS) / S;
          let cr = 0;
          let cg = 0;
          let cb = 0;
          let ca = 0;
          const paint = (col, o) => {
            const na = o + ca * (1 - o);
            cr = (col[0] * o + cr * ca * (1 - o)) / na;
            cg = (col[1] * o + cg * ca * (1 - o)) / na;
            cb = (col[2] * o + cb * ca * (1 - o)) / na;
            ca = na;
          };
          for (const s of shapes) {
            if (x < s.bb[0] || x > s.bb[2] || y < s.bb[1] || y > s.bb[3]) continue;
            if (s.fill && s.inside(x, y)) paint(s.fill, s.op);
            if (s.stroke && s.sw > 0) {
              const h = (s.sw / 2) ** 2;
              if (s.segs.some((g) => dseg2(x, y, g[0], g[1]) <= h)) paint(s.stroke, s.op);
            }
          }
          R += cr * ca;
          G += cg * ca;
          B += cb * ca;
          A += ca;
        }
      }
      const i = (py * W + qx) * 4;
      out[i] = Math.round(A ? R / A : 0);
      out[i + 1] = Math.round(A ? G / A : 0);
      out[i + 2] = Math.round(A ? B / A : 0);
      out[i + 3] = Math.round((A / (SS * SS)) * 255);
    }
  }
  return out;
}

const crcTable = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc = (b) => {
  let c = 0xffffffff;
  for (const v of b) c = crcTable[(c ^ v) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const td = Buffer.concat([Buffer.from(type), data]);
  const l = Buffer.alloc(4);
  const c = Buffer.alloc(4);
  l.writeUInt32BE(data.length);
  c.writeUInt32BE(crc(td));
  return Buffer.concat([l, td, c]);
};

/** A PNG: colour type 6 (RGBA), or 2 (RGB), which refuses any pixel that isn't opaque. */
function png(rgba, W, H, { alpha }) {
  const ch = alpha ? 4 : 3;
  if (!alpha) {
    for (let i = 3; i < rgba.length; i += 4) {
      if (rgba[i] !== 255) throw new Error(`pixel ${(i - 3) / 4} isn't opaque: refusing an RGB icon with transparency`);
    }
  }
  const raw = Buffer.alloc((W * ch + 1) * H);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const s = (y * W + x) * 4;
      const d = y * (W * ch + 1) + 1 + x * ch;
      for (let c = 0; c < ch; c++) raw[d + c] = rgba[s + c];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0);
  ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8;
  ihdr[9] = alpha ? 6 : 2;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------------------------------------------------------------- write ----
const written = [];
const write = (file, data) => {
  writeFileSync(file, data);
  written.push(path.relative(ROOT, file).split(path.sep).join('/'));
};

write(path.join(RES, 'drawable', 'ic_launcher_foreground.xml'), foreground);
write(path.join(RES, 'drawable', 'ic_launcher_monochrome.xml'), monochrome);
write(path.join(RES, 'drawable', 'ic_notification.xml'), notification);
write(path.join(RES, 'drawable', 'splash_pig.xml'), splashPig);
write(path.join(RES, 'drawable', 'splash_icon.xml'), splashIcon);

// Legacy launcher icons (Android before 8): the tile with rounded corners, the corners clear.
const roundedIcon = ICON.replace(
  /<rect x="0" y="0" width="512" height="512" fill="#FBF6F1"\/>/,
  '<rect x="0" y="0" width="512" height="512" rx="104" fill="#FBF6F1"/>',
);
if (roundedIcon === ICON) throw new Error("icon.svg: the tile to round wasn't found");
for (const [density, px] of [
  ['mdpi', 48],
  ['hdpi', 72],
  ['xhdpi', 96],
  ['xxhdpi', 144],
  ['xxxhdpi', 192],
]) {
  write(path.join(RES, `mipmap-${density}`, 'ic_launcher.png'), png(render(roundedIcon, px, px), px, px, { alpha: true }));
}

// iOS: every image the AppIcon set lists, square and full bleed (iOS rounds the corners).
const set = JSON.parse(readFileSync(path.join(XC, 'AppIcon.appiconset', 'Contents.json'), 'utf8'));
const rendered = new Map();
for (const image of set.images) {
  const points = +image.size.split('x')[0];
  const px = Math.round(points * +image.scale.replace('x', ''));
  if (!rendered.has(px)) rendered.set(px, png(render(ICON, px, px), px, px, { alpha: false }));
  write(path.join(XC, 'AppIcon.appiconset', image.filename), rendered.get(px));
}

// iOS launch image: the calm pig at 160 pt, clear around it (the storyboard draws the background).
for (const [suffix, px] of [
  ['', 160],
  ['@2x', 320],
  ['@3x', 480],
]) {
  write(path.join(XC, 'LaunchImage.imageset', `LaunchImage${suffix}.png`), png(render(PIG, px, px), px, px, { alpha: true }));
}

console.log(written.join('\n'));
console.log(`${written.length} files`);
