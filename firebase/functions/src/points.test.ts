import {strict as assert} from "node:assert";
import {test} from "node:test";
import {computeRedemption, InvalidDraftError} from "./points";

function close(actual: number, expected: number) {
  assert.ok(Math.abs(actual - expected) < 1e-9, `${actual} != ${expected}`);
}

test("bin doc with stored co2 uses it and passes it through", () => {
  const r = computeRedemption({
    materials: [
      {type: "plastic", weight: 0.5, pricePerKg: 0, isFree: true, co2: 0.4},
    ],
    totalWeight: 0.5,
  });
  // 0.5×100×1.5 + 0.4×100 = 75 + 40 = 115
  assert.equal(r.pointsUser, 115);
  close(r.co2Saved, 0.4);
  close(r.totalWeight, 0.5);
  close(r.materials[0].co2!, 0.4);
  close(r.stats.plastic, 0.5);
});

test("center doc without co2 falls back via the slug map", () => {
  const r = computeRedemption({
    materials: [{type: "paper", weight: 1, pricePerKg: 0, isFree: true}],
    totalWeight: 1,
  });
  // 1×100×1.5 + (1×0.65)×100 = 150 + 65 = 215
  assert.equal(r.pointsUser, 215);
  close(r.co2Saved, 0.65);
  // no stored co2 → transaction material has no co2 key
  assert.equal("co2" in r.materials[0], false);
});

test("multi-material doc: per-item entries, total rounded once", () => {
  const r = computeRedemption({
    materials: [
      {type: "plastic", weight: 0.5, pricePerKg: 0, isFree: true, co2: 0.4},
      {type: "plastic", weight: 0.3, pricePerKg: 0, isFree: true, co2: 0.2},
      {type: "aluminum", weight: 0.015, pricePerKg: 0, isFree: true, co2: 0.01},
    ],
    totalWeight: 0.815,
  });
  // (75+40) + (45+20) + (2.25+1.0) = 183.25 → 183
  assert.equal(r.pointsUser, 183);
  close(r.co2Saved, 0.61);
  assert.equal(r.materials.length, 3);
  close(r.stats.plastic, 0.8);
  close(r.stats.aluminum, 0.015);
});

test("paid (isFree false) material gets ×1.0 base plus CO2 fallback", () => {
  const r = computeRedemption({
    materials: [{type: "metal", weight: 2, pricePerKg: 1.2, isFree: false}],
    totalWeight: 2,
  });
  // 2×100×1.0 + (2×0.85)×100 = 200 + 170 = 370
  assert.equal(r.pointsUser, 370);
  close(r.co2Saved, 1.7);
});

test("missing isFree defaults to free", () => {
  const r = computeRedemption({
    materials: [{type: "paper", weight: 1}],
    totalWeight: 1,
  });
  assert.equal(r.pointsUser, 215);
  assert.equal(r.materials[0].isFree, true);
  assert.equal(r.materials[0].pricePerKg, 0);
});

test("unknown slug falls back to the 0.5 default multiplier", () => {
  const r = computeRedemption({
    materials: [{type: "mystery", weight: 1, pricePerKg: 0, isFree: true}],
    totalWeight: 1,
  });
  // 150 + (1×0.5)×100 = 200
  assert.equal(r.pointsUser, 200);
  close(r.co2Saved, 0.5);
});

test("empty or malformed drafts are rejected", () => {
  const bad: unknown[] = [
    undefined,
    null,
    "draft",
    {materials: [], totalWeight: 0},
    {materials: [{type: "paper", weight: 1}], totalWeight: 0},
    {materials: [{type: "paper", weight: 1}]},
    {materials: [{weight: 1}], totalWeight: 1},
    {materials: [{type: "", weight: 1}], totalWeight: 1},
    {materials: [{type: "paper", weight: -5}], totalWeight: 1},
    {materials: [{type: "paper", weight: "1"}], totalWeight: 1},
    {materials: [{type: "paper", weight: 1, co2: -1}], totalWeight: 1},
    {materials: [null], totalWeight: 1},
  ];
  for (const draft of bad) {
    assert.throws(
      () => computeRedemption(draft),
      InvalidDraftError,
      JSON.stringify(draft),
    );
  }
});
