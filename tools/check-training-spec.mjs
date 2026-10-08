// Runs independent mathematical specification checks, not the Swift implementation.
import assert from 'node:assert/strict';
const ng = {kg: 1_000_000_000_000n, lb: 453_592_370_000n};
const epley = (w,r) => r === 1 ? w : w * BigInt(30+r) / 30n;
const brzycki = (w,r) => r === 1 ? w : w * 36n / BigInt(37-r);
assert.equal(epley(100n*ng.kg,5), 116_666_666_666_666n);
assert.equal(brzycki(100n*ng.kg,5), 112_500_000_000_000n);
assert.equal(epley(225n*ng.lb,3), 2475n*ng.lb/10n);
for(const formula of [epley,brzycki]) {
  assert.equal(formula(225n*ng.lb,1),225n*ng.lb);
  assert.equal(formula(100n*ng.kg,10),133_333_333_333_333n);
}
// Enumerate whole vectors instead of using the app's merged-sum dynamic program.
const sizes = [[25000,4],[20000,4],[15000,2],[10000,2],[5000,2],[2500,2],[1250,2],[500,2],[250,2]];
let sideSums = [0];
for(const [size,count] of sizes) sideSums = sideSums.flatMap(sum => Array.from({length:count+1},(_,i) => sum+size*i));
const loads = [...new Set(sideSums.map(s => 20000+2*s))].sort((a,b)=>a-b);
const floor = desired => loads.filter(w=>w<=desired).at(-1);
assert.deepEqual([40,55,70,85].map(p=>floor(140000*p/100)),[56000,77000,98000,119000]);
const nearBar = [...new Set([40,55,70,85].map(p=>Math.max(20000,floor(25000*p/100)??20000)))];
assert.deepEqual(nearBar,[20000,21000]);
const allowed = loads.filter(w=>w%2500===0);
const third=allowed.filter(w=>w<=201000).at(-1);
const nearest=(range,desired)=>range.toSorted((a,b)=>Math.abs(a-desired)-Math.abs(b-desired)||a-b)[0];
const opener=nearest(allowed.filter(w=>w>=third*.8&&w<=third*.9),third*.85);
const second=nearest(allowed.filter(w=>w>=third*.9&&w<=third*.97&&w>opener),third*.935);
assert.deepEqual([opener,second,third],[170000,187500,200000]);
assert(opener<second&&second<third&&third<=201000);
console.log('PASS: formula identity/reference arithmetic, exhaustive warm-up rounding/duplicates, and attempt ordering/increments. Swift/XCTest/iOS were NOT executed.');
