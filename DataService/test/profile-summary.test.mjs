import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {once} from 'node:events';
import {importSnapshot} from '../src/import.mjs';
import {query} from '../src/query.mjs';
import {serve} from '../src/server.mjs';
import {row,csv,first,second} from './fixtures/service-data.mjs';
const scope={sex:'F',equipment:'Raw',event:'SBD'};
const id=name=>Buffer.from(name).toString('base64url');
async function fixture(t) {
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-profile-'));
  t.after(()=>{assert(path.resolve(temp).startsWith(path.resolve(tmpdir())+path.sep));return rm(temp,{recursive:true,force:true});});
  const root=path.join(temp,'service');
  return {root,importRows:async(rows,label)=>{
    const file=path.join(temp,label+'.csv');await writeFile(file,csv(rows));return importSnapshot({root,file});
  }};
}
test('full-snapshot five winners preserve categories, exclusions, nulls, suffixes and deterministic ties',async t=>{
  const {root,importRows}=await fixture(t),name='Fixture Profile #1';
  const rows=Array.from({length:30},(_,i)=>row(name,'400',{Date:`2025-01-${String(i+1).padStart(2,'0')}`}));
  rows.push(row(name,'700',{Date:'2020-01-01',Best3SquatKg:'250'}),
    row(name,'500',{Date:'2025-02-01',Best3BenchKg:'150',MeetName:'tie older'}),
    row(name,'500',{Date:'2025-03-01',Best3BenchKg:'150',MeetName:'tie first ordinal'}),
    row(name,'500',{Date:'2025-03-01',Best3BenchKg:'150',MeetName:'tie last ordinal',Best3DeadliftKg:'300',Dots:'500'}),
    row(name,'999',{Place:'DQ',Best3SquatKg:'999'}),row(name,'998',{Sanctioned:'No'}),
    row(name,'997',{Equipment:'Wraps'}),row(name,'996',{Tested:''}),
    row(name,'995',{Sex:'M'}),row(name,'994',{Event:'D'}),row(name+' extra','1000'),
    row('Fixture Profile #2','1001'),row('Fixture Missing','',{Best3SquatKg:'-100'}));
  await importRows(rows,'a');
  const params={...scope,id:id(name),tested:'yes'};
  const history=await query(root,'history',{id:id(name),limit:25});
  assert(!history.results.some(r=>r.TotalKg===700));assert(history.nextCursor);
  const response=await query(root,'summary',params),profile=response.results[0];
  assert.equal(response.nextCursor,null);assert.equal(response.results.length,1);
  assert.deepEqual(profile.scope,{...scope,tested:'yes'});assert.equal(profile.Name,name);
  const winners=Object.fromEntries(profile.bests.map(b=>[b.metric,b.result]));
  assert.equal(winners.total.TotalKg,700);assert.equal(winners.squat.Best3SquatKg,250);
  assert.equal(winners.bench.MeetName,'tie last ordinal');assert.equal(winners.deadlift.Best3DeadliftKg,300);assert.equal(winners.dots.Dots,500);
  assert.equal((await query(root,'summary',{...scope,id:id(name)})).results[0].bests[0].result.TotalKg,996);
  for(const metric of Object.keys(winners)) {
    const rank=await query(root,'rankings',{...scope,tested:'yes',metric,limit:100});
    assert.equal(rank.results.find(r=>r.Name===name).row_id,winners[metric].row_id);
  }
  for(const extra of [{federation:'OTHER'},{from:'2026-01-01'},{to:'2019-01-01'},
    {bodyweightMin:'71'},{bodyweightMax:'70'},{weightClass:'74'}]) {
    assert.deepEqual((await query(root,'summary',{...params,...extra})).results[0].bests,[]);
  }
  assert.deepEqual((await query(root,'summary',{...scope,id:id('Fixture Missing')})).results[0].bests,[]);
  assert.equal((await query(root,'summary',{...scope,id:id('absent')})).results.length,0);
  await assert.rejects(query(root,'summary',{...params,cursor:'ignored'}),/UNSUPPORTED_FILTER/);
  await assert.rejects(query(root,'summary',{...params,event:'invalid'}),/VALID_EVENT/);
  // The two routes share authoritative validation; client drafts do not reinterpret it.
  for(const [extra,error] of [
    [{from:'2025-02-30'},/Invalid calendar date/],
    [{from:'2025-03-01',to:'2025-02-01'},/INVALID_DATE_RANGE/],
    [{bodyweightMin:'80',bodyweightMax:'70'},/INVALID_BODYWEIGHT_RANGE/],
    [{bodyweightMin:'0'},/INVALID_BODYWEIGHT/],
    [{weightClass:'74 kilograms'},/INVALID_WEIGHT_CLASS/]
  ]) {
    await assert.rejects(query(root,'summary',{...params,...extra}),error);
    await assert.rejects(query(root,'rankings',{...scope,tested:'yes',metric:'total',...extra}),error);
  }
  for(const weightClass of ['+','120+','-74']) {
    assert.deepEqual((await query(root,'summary',{...params,weightClass})).results[0].bests,[]);
    assert.deepEqual((await query(root,'rankings',{...scope,weightClass})).results,[]);
  }
  const server=serve({root,port:0});await once(server,'listening');
  try {
    const url=`http://127.0.0.1:${server.address().port}/lifters/${id(name)}/summary?`+new URLSearchParams({...scope,tested:'yes',version:response.version});
    const live=await fetch(url);assert.equal(live.status,200);assert.deepEqual((await live.json()).results,response.results);
  } finally {await new Promise(resolve=>server.close(resolve));}
});
test('summary added, corrected and removed winners switch atomically while pinned old versions remain readable',async t=>{
  const {root,importRows}=await fixture(t);
  const a=await importRows(first,'a');
  const alice={...scope,id:id('Fixture Alice #1')},removed={...scope,id:id('Fixture Removed Casey')},added={...scope,id:id('Fixture New Dan')};
  assert.equal((await query(root,'summary',alice)).results[0].bests[0].result.TotalKg,500);
  assert.equal((await query(root,'summary',removed)).results.length,1);assert.equal((await query(root,'summary',added)).results.length,0);
  const b=await importRows(second,'b');assert.notEqual(a.version,b.version);
  const corrected=await query(root,'summary',alice);assert.equal(corrected.version,b.version);assert.equal(corrected.results[0].bests[0].result.TotalKg,550);
  assert.equal((await query(root,'summary',removed)).results.length,0);assert.equal((await query(root,'summary',added)).results[0].bests[0].result.TotalKg,510);
  assert.equal((await query(root,'summary',{...alice,version:a.version})).results[0].bests[0].result.TotalKg,500);
  const same=await importRows(second,'same');assert.equal(same.version,b.version);
  assert.deepEqual((await query(root,'summary',alice)).results,corrected.results);
});
