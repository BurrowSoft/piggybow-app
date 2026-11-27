#!/usr/bin/env node
// Piggybow seed: PLACEHOLDER launcher icons until the real ones (from the
// design's icon.svg) land. A plain pig face under three arcs on cream, drawn
// here so no icon is the original app's.
//   node tool/seed/placeholder_icons.mjs [repo]
// Writes 8-bit RGB PNGs with no alpha (App Store uploads refuse alpha) for
// iOS's AppIcon set and Android's legacy mipmaps. Deterministic.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const root = process.argv[2] ?? '.';

const cream = [0xfb, 0xf6, 0xf1];
const pink = [0xf6, 0xb8, 0xc8];
const snout = [0xe8, 0x8a, 0xa3];
const nostril = [0xb8, 0x5c, 0x77];
const ink = [0x3a, 0x2e, 0x39];
const arcs = [
  { r: 0.40, c: [0xe2, 0x7d, 0x9a] }, // rose
  { r: 0.33, c: [0xf2, 0xa0, 0x7b] }, // peach
  { r: 0.26, c: [0xf3, 0xc2, 0x4f] }, // gold
];

// The colour at (x, y) in a 0..1 square.
function colour(x, y) {
  const inEllipse = (cx, cy, rx, ry) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
  if (inEllipse(0.43, 0.555, 0.022, 0.022) || inEllipse(0.57, 0.555, 0.022, 0.022)) return ink;
  if (inEllipse(0.475, 0.655, 0.016, 0.016) || inEllipse(0.525, 0.655, 0.016, 0.016)) return nostril;
  if (inEllipse(0.5, 0.655, 0.085, 0.06)) return snout;
  if (inEllipse(0.5, 0.6, 0.2, 0.2)) return pink;
  // The arcs: rings above y = 0.47, centred on (0.5, 0.47).
  const d = Math.hypot(x - 0.5, y - 0.47);
  if (y <= 0.47) for (const a of arcs) if (Math.abs(d - a.r) <= 0.03) return a.c;
  return cream;
}

function png(size) {
  const ss = 4; // 4×4 supersampling
  const raw = Buffer.alloc((size * 3 + 1) * size);
  for (let py = 0; py < size; py++) {
    raw[py * (size * 3 + 1)] = 0; // filter: none
    for (let px = 0; px < size; px++) {
      const sum = [0, 0, 0];
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const c = colour((px + (sx + 0.5) / ss) / size, (py + (sy + 0.5) / ss) / size);
          sum[0] += c[0]; sum[1] += c[1]; sum[2] += c[2];
        }
      }
      const o = py * (size * 3 + 1) + 1 + px * 3;
      for (let k = 0; k < 3; k++) raw[o + k] = Math.round(sum[k] / (ss * ss));
    }
  }
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0; // 8-bit RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// iOS: every image the AppIcon set lists, at its pixel size.
const setDir = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
const set = JSON.parse(fs.readFileSync(path.join(setDir, 'Contents.json'), 'utf8'));
for (const img of set.images) {
  if (!img.filename) continue;
  const pt = parseFloat(img.size.split('x')[0]);
  const scale = parseInt(img.scale, 10);
  fs.writeFileSync(path.join(setDir, img.filename), png(Math.round(pt * scale)));
}
// Android: the legacy launcher icons (API < 26; newer ones use the vectors).
for (const [dir, size] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) {
  fs.writeFileSync(path.join(root, `android/app/src/main/res/mipmap-${dir}/ic_launcher.png`), png(size));
}
console.log(`placeholder icons: ${set.images.filter((i) => i.filename).length} iOS, 5 Android`);
