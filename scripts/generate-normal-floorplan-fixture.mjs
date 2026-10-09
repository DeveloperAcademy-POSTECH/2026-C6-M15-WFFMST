// Generates synthetic binary assets only; not the production extraction algorithm.
// Default mode verifies committed assets without modifying them.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

const destination = new URL('../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/FloorPlans/normal-v1/', import.meta.url);
const width = 1000, height = 600, cellSize = 2;
const columns = 500, rows = 300;
const mask = Buffer.alloc(columns * rows);
for (let row = 0; row < rows; row++) {
  for (let column = 0; column < columns; column++) {
    const outside = column < 10 || column >= 490 || row < 10 || row >= 290;
    const upperLeft = column >= 100 && column < 120 && row >= 40 && row < 80;
    const wall = column >= 300 && column < 305 && row >= 40 && row < 260
      && !(row >= 140 && row < 160);
    const lowerRight = column >= 400 && column < 430 && row >= 210 && row < 230;
    mask[row * columns + column] = Number(outside || upperLeft || wall || lowerRight);
  }
}

// Opaque 8-bit RGBA, top-left origin, PNG filter 0 on every row.
const scanlines = Buffer.alloc(height * (1 + width * 4));
for (let y = 0; y < height; y++) {
  for (let x = 0; x < width; x++) {
    const outside = x < 20 || x >= 980 || y < 20 || y >= 580;
    const blocked = mask[Math.floor(y / cellSize) * columns + Math.floor(x / cellSize)] === 1;
    const value = outside ? 192 : blocked ? 0 : 255;
    const offset = y * (1 + width * 4) + 1 + x * 4;
    scanlines.set([value, value, value, 255], offset);
  }
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(name, payload) {
  const typeAndPayload = Buffer.concat([Buffer.from(name, 'ascii'), payload]);
  const size = Buffer.alloc(4), crc = Buffer.alloc(4);
  size.writeUInt32BE(payload.length);
  crc.writeUInt32BE(crc32(typeAndPayload));
  return Buffer.concat([size, typeAndPayload, crc]);
}
const header = Buffer.alloc(13);
header.writeUInt32BE(width, 0);
header.writeUInt32BE(height, 4);
header[8] = 8;
header[9] = 6; // RGBA
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk('IHDR', header), chunk('sRGB', Buffer.from([0])),
  chunk('IDAT', deflateSync(scanlines, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
]);

const write = process.argv.slice(2).includes('--write');
assert(process.argv.slice(2).every(arg => arg === '--write'), 'Only --write is supported');
if (write) mkdirSync(destination, { recursive: true });
for (const [name, data] of [['original.png', png], ['resolved-mask.bin', mask]]) {
  const url = new URL(name, destination);
  if (write) writeFileSync(url, data);
  else assert.deepEqual(readFileSync(url), data, `${name} differs; do not silently regenerate published fixture hashes`);
  console.log(`${name}: ${data.length} bytes; sha256=${createHash('sha256').update(data).digest('hex')}`);
}
console.log(write ? 'Generated binary assets. Verify/update manifest and reference hashes explicitly.' : 'PASS: binary assets match the synthetic source');
