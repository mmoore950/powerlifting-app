// Independent exhaustive check of the specification fixtures. DOES NOT execute Swift.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const fixtures = JSON.parse(readFileSync(new URL('../Packages/LiftingCore/Tests/LiftingCoreTests/Fixtures/loading.json', import.meta.url)));
const unit = {kg: 1_000_000_000_000n, lb: 453_592_370_000n};
const mass = (text, u) => {
  const [whole, fraction = ''] = text.split('.');
  return (BigInt(whole || '0') * 1000n + BigInt(fraction.padEnd(3, '0'))) * (unit[u] / 1000n);
};
for (const f of fixtures) {
  const target = mass(f.target, f.targetUnit);
  const base = mass(f.bar, f.barUnit) + 2n * mass(f.collar, f.barUnit);
  const plates = f.plates.toSorted((a,b) => b[0] - a[0]);
  let plans = [{total: base, counts: [], pairs: 0}];
  for (const [size, available] of plates) {
    plans = plans.flatMap(p => Array.from({length: available + 1}, (_, count) => ({
      total: p.total + BigInt(size) * unit[f.inventoryUnit] / 1000n * BigInt(2 * count),
      counts: [...p.counts, count], pairs: p.pairs + count
    })));
  }
  const distance = p => p.total >= target ? p.total - target : target - p.total;
  plans.sort((a,b) => {
    if (distance(a) !== distance(b)) return distance(a) < distance(b) ? -1 : 1;
    if (a.total !== b.total) return a.total < b.total ? -1 : 1;
    if (a.pairs !== b.pairs) return a.pairs - b.pairs;
    for (let i=0; i<a.counts.length; i++) if(a.counts[i] !== b.counts[i]) return b.counts[i] - a.counts[i];
    return 0;
  });
  const lower = plans.filter(p => p.total <= target).map(p => p.total).reduce((a,b) => a === null || b > a ? b : a, null);
  const upper = plans.filter(p => p.total >= target).map(p => p.total).reduce((a,b) => a === null || b < a ? b : a, null);
  assert.equal(plans[0].total, mass(f.closest, f.resultUnit), `${f.name}: closest`);
  assert.equal(lower, f.lower === null ? null : mass(f.lower, f.resultUnit), `${f.name}: lower`);
  assert.equal(upper, f.upper === null ? null : mass(f.upper, f.resultUnit), `${f.name}: upper`);
  assert.deepEqual(plates.flatMap(([size], i) => plans[0].counts[i] ? [[size, plans[0].counts[i]]] : []), f.counts, `${f.name}: plates`);
}
console.log(`PASS: ${fixtures.length} specification fixtures agree with exhaustive enumeration. Swift/XCTest/iOS were NOT executed.`);
