// Read-only checks of hand-authored examples, NOT a production route adapter,
// reconstruction algorithm, service, or general-purpose track validator.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

assert.equal(process.argv.length, 2, 'This checker accepts no options and never rewrites fixtures');
const root = new URL('../CQB/Packages/CQBCore/Sources/CQBFixtures/Resources/', import.meta.url);
const tracks = new URL('Tracks/minimal-v1/', root);
const plans = new URL('FloorPlans/normal-v1/', root);
const read = (root, name) => readFileSync(new URL(name, root));
const json = (root, name) => JSON.parse(read(root, name));
const sha256 = data => createHash('sha256').update(data).digest('hex');
const expected = json(tracks, 'expected.json');
const snapshots = json(tracks, 'solver-snapshots.json');
const reference = json(plans, 'reference.json');
const manifest = json(plans, 'navigation-map.json');
const mask = read(plans, 'resolved-mask.bin');
const near = (a, b) => assert(Number.isFinite(a) && Number.isFinite(b)
  && Math.abs(a - b) <= expected.numericTolerance, `${a} != ${b}`);

assert.equal(expected.fixtureFormatVersion, 1);
assert.equal(snapshots.fixtureFormatVersion, 1);
assert.equal(snapshots.source, 'hand-authored-selected-candidate-snapshots-not-v13-execution');
assert.equal(expected.algorithmExecuted, false);
assert.equal(sha256(read(plans, 'navigation-map.json')), reference.navigationSHA256);
assert.equal(sha256(mask), manifest.navigationGrid.maskSHA256);
assert.equal(sha256(read(plans, 'original.png')), manifest.imageSHA256);
assert.equal(mask.length, manifest.navigationGrid.columns * manifest.navigationGrid.rows);
const scale = Math.hypot(manifest.scale.b.x - manifest.scale.a.x,
  manifest.scale.b.y - manifest.scale.a.y) / manifest.scale.meters;
near(scale, expected.pixelsPerMeter);
assert.deepEqual(snapshots.cases.map(c => c.id), expected.cases.map(c => c.id));
assert.equal(expected.cases.length, 4);

function checkCase(c, e, raw) {
  near(c.recordingStartOffsetSeconds, 0.4);
  assert.equal(raw.fixtureFormatVersion, 1);
  assert.deepEqual(raw.floorPlan, reference);
  assert.equal(raw.sessionID, expected.sessionID);
  assert.equal(raw.memberID, expected.memberID);
  assert.equal(raw.recordingID, e.recordingID);
  assert.equal(c.resultID, e.resultID);
  const start = { x: raw.startPose.positionNormalized.x * manifest.imageWidth,
    y: raw.startPose.positionNormalized.y * manifest.imageHeight };
  assert.deepEqual(start, expected.startPixels);
  const direction = { x: raw.startPose.directionPointNormalized.x * manifest.imageWidth,
    y: raw.startPose.directionPointNormalized.y * manifest.imageHeight };
  const radians = Math.atan2(direction.y - start.y, direction.x - start.x)
    - raw.startPose.cameraDirectionRadians;
  near(radians * 180 / Math.PI, expected.inputRotationDegrees);
  raw.samples.forEach((s, i) => {
    assert(s.time >= 0 && (!i || s.time > raw.samples[i - 1].time));
    near(s.arTimestamp - 100, s.time);
    if (s.relativeMeters) {
      assert.equal(s.trackingState, 'normal');
      near(s.arPosition[0] - raw.originMeters.x, s.relativeMeters.x);
      near(s.arPosition[2] - raw.originMeters.z, s.relativeMeters.y);
    } else assert.notEqual(s.trackingState, 'normal');
  });
  const valid = raw.samples.filter(s => s.relativeMeters !== null).length;
  const chosen = c.solverSnapshot?.chosen;
  const vertices = chosen?.vertices ?? [];
  assert.equal(valid, e.validSampleCount);
  assert.equal(new Set(vertices.map(v => v.sampleIndex)).size, e.coveredSampleCount);
  near(e.coveredSampleCount / valid, e.validSampleCoverage);
  assert.equal(c.solverSnapshot?.selected ?? null, e.selectedCandidateIndex);
  assert.equal(vertices.length, e.vertices.length);
  const pairs = [];
  vertices.forEach((v, i) => {
    const s = raw.samples[v.sampleIndex], target = e.vertices[i];
    assert(s?.relativeMeters, 'An unavailable sample must not acquire a fabricated position');
    near(v.time, s.time);
    near(v.time + c.recordingStartOffsetSeconds, target.t);
    near(v.point.x, target.x);
    near(v.point.y, target.y);
    // These four illustrative paths have no synthetic correction displacement.
    // This is NOT an assertion that real corrected paths equal raw projection.
    near(v.point.x, start.x + scale * (Math.cos(radians) * s.relativeMeters.x - Math.sin(radians) * s.relativeMeters.y));
    near(v.point.y, start.y + scale * (Math.sin(radians) * s.relativeMeters.x + Math.cos(radians) * s.relativeMeters.y));
    assert.equal(v.part, target.part);
    assert.equal(v.sampleIndex, target.sampleIndex);
    assert.equal(target.provenance, 'unspecified');
    assert(v.point.x >= 0 && v.point.x < manifest.imageWidth && v.point.y >= 0 && v.point.y < manifest.imageHeight);
    const index = Math.floor(v.point.y / manifest.navigationGrid.cellSizePixels) * manifest.navigationGrid.columns
      + Math.floor(v.point.x / manifest.navigationGrid.cellSizePixels);
    assert.equal(mask[index], 0);
    if (i && vertices[i - 1].part === v.part) pairs.push([vertices[i - 1].sampleIndex, v.sampleIndex]);
  });
  assert.deepEqual(pairs, e.connectedSourcePairs);
  for (const pair of e.mustNotConnectSourcePairs) assert(!pairs.some(p => p[0] === pair[0] && p[1] === pair[1]));
  if (c.id === 'normal') {
    assert.equal(c.attempt, 'completed');
    assert.equal(e.status, 'done');
    assert.equal(c.solverSnapshot.searchIncomplete, false);
    assert.equal(chosen.searchLimited, false);
    assert.deepEqual(chosen.unresolved, []);
    assert.deepEqual(e.unresolvedIntervals, []);
    assert.deepEqual(e.warnings, []);
  } else if (c.id === 'tracking-gap') {
    assert.equal(e.status, 'partial');
    assert.equal(c.solverSnapshot.searchIncomplete, false);
    assert.deepEqual(raw.samples.flatMap((s, i) => s.relativeMeters === null ? [i] : []), [2, 3]);
    assert.deepEqual(chosen.unresolved, [{ from: 4, through: 4, reason: 'tracking restart connection unverified' }]);
    assert.deepEqual(e.unresolvedIntervals, [{ from: 1.4, to: 4.4, bounds: '()', reason: 'trackingLost', missingSampleIndices: [2, 3] }]);
    assert.deepEqual(e.warnings, ['trackingLost', 'connectionUnverified']);
  } else if (c.id === 'search-limit') {
    assert.equal(e.status, 'partial');
    assert.equal(c.solverSnapshot.searchIncomplete, true);
    assert.equal(chosen.searchLimited, true);
    assert.deepEqual(chosen.unresolved, [{ from: 2, through: 3, reason: 'search budget reached' }]);
    assert.deepEqual(e.unresolvedIntervals, [{ from: 1.4, to: 3.4, bounds: '(]', reason: 'searchLimit', missingSampleIndices: [2, 3] }]);
    assert.deepEqual(e.warnings, ['searchIncomplete']);
  } else {
    assert.equal(c.id, 'insufficient-movement');
    assert.equal(c.attempt, 'noCandidate');
    assert.equal(c.solverSnapshot, null);
    assert.equal(c.observedReason, 'insufficientMovement');
    assert.equal(e.status, 'failed');
    assert.equal(e.failureReason, 'insufficientMovement');
    assert.deepEqual(e.unresolvedIntervals, [{ from: 0.4, to: 1.4, bounds: '[]', reason: 'insufficientMovement', missingSampleIndices: [0, 1] }]);
    near(Math.hypot(raw.samples[1].relativeMeters.x - raw.samples[0].relativeMeters.x,
      raw.samples[1].relativeMeters.y - raw.samples[0].relativeMeters.y), 0);
  }
  if (e.status !== 'failed') assert.equal(e.failureReason, null);
}

const inputs = snapshots.cases.map((c, i) => {
  assert.match(c.rawFile, /^[a-z-]+-raw\.json$/);
  const bytes = read(tracks, c.rawFile);
  assert.equal(sha256(bytes), expected.cases[i].rawSHA256, `${c.rawFile}: raw bytes changed`);
  const raw = JSON.parse(bytes);
  checkCase(c, expected.cases[i], raw);
  return raw;
});

// Policy truth-table consistency only: this is not a fake repository execution.
assert.equal(expected.publicationExamples.length, 6);
for (const p of expected.publicationExamples) {
  const e = expected.cases.find(e => e.id === p.caseID);
  const cancelled = p.attempt === 'cancelled';
  assert(cancelled || e);
  const publishable = !cancelled && p.rawConfirmed && p.resultFilesReady;
  const selection = p.previousSelection ?? (publishable && e.status !== 'failed' ? e.resultID : null);
  // Whether failed diagnostic summaries are publicly readable is outside this sample.
  // null leaves that policy open while still checking preservation of selection.
  if (p.expectedPublic !== null) assert.equal(p.expectedPublic, publishable);
  assert.equal(p.expectedSelection, selection);
}

// Ensure accidental adapter changes are detectable, not just printable examples.
const rejects = (index, mutate) => {
  const c = structuredClone(snapshots.cases[index]);
  const e = structuredClone(expected.cases[index]);
  mutate(c, e);
  assert.throws(() => checkCase(c, e, inputs[index]));
};
rejects(0, c => { c.solverSnapshot.chosen.vertices[1].point.x *= 20; });
rejects(0, c => { c.solverSnapshot.chosen.vertices[1].time += 0.4; });
rejects(0, c => { c.solverSnapshot.selected = 0; });
rejects(1, c => { c.solverSnapshot.chosen.vertices[2].part = 0; });
rejects(1, (_, e) => { e.status = 'done'; });
rejects(3, c => { delete c.observedReason; });
console.log('PASS: 4 hand-authored track cases, 6 publication expectations, 6 mutation guards; no V13/service execution');
