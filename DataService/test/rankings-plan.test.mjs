import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {columns} from '../src/schema.mjs';
import {importSnapshot} from '../src/import.mjs';
import {prepareQuery,executeQuery} from '../src/query.mjs';
import {withSnapshot} from '../src/snapshot-lifecycle.mjs';

test('narrow ranking proposal preserves independently expected ties, eligibility, filters and full paginated records',async()=>{
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-ranking-plan-'));
  const root=path.join(temp,'service'),file=path.join(temp,'fixture.csv');
  const row=(Name,TotalKg,extra={})=>({Name,TotalKg,Sex:'F',Equipment:'Raw',Event:'SBD',Place:'1',Sanctioned:'Yes',
    Tested:'Yes',Federation:'FIX',Date:'2025-01-01',BodyweightKg:'70.5',WeightClassKg:'75',Best3SquatKg:'200',
    Best3BenchKg:'100',Best3DeadliftKg:'200',Dots:'500',MeetCountry:'USA',MeetName:'Synthetic only',Squat1Kg:'-100',...extra});
  const rows=[
    row('Fixture Alpha #1','500',{MeetName:'older'}),
    row('Fixture Alpha #1','500',{Date:'2025-02-01',MeetName:'same-date earlier row'}),
    row('Fixture Alpha #1','500',{Date:'2025-02-01',MeetName:'winning last row',Best3BenchKg:'110'}),
    row('Fixture Alpha #1','900',{Federation:'OTHER',Date:'2025-03-01'}),
    row('Fixture Alpha #2','500',{Date:'2025-02-01',WeightClassKg:'+'}),
    row('Fixture Beta','500',{Date:'2025-02-01',WeightClassKg:'-74'}),
    row('Fixture Guest','490',{Place:'G',Sanctioned:''}),
    row('Fixture Untested','510',{Tested:''}),
    row('Fixture Heavy','520',{BodyweightKg:'100',WeightClassKg:'100+'}),
    row('Fixture DQ','999',{Place:'DQ'}),row('Fixture DD','999',{Place:'DD'}),row('Fixture NS','999',{Place:'NS'}),
    row('Fixture Unsanctioned','999',{Sanctioned:'No'}),
    row('Fixture Failed','',{Best3SquatKg:'-200',Best3BenchKg:'',Best3DeadliftKg:'0',Dots:''}),
    row('Fixture WrongSex','999',{Sex:'M'}),row('Fixture WrongEquipment','999',{Equipment:'Wraps'}),
    row('Fixture WrongEvent','999',{Event:'B'}),
    row('Fixture Alpha #1','950',{Tested:'',Date:'2025-04-01',BodyweightKg:'100',WeightClassKg:'100+'}),
    row('Fixture Alpha #1','960',{Date:'2026-01-01',BodyweightKg:'100',WeightClassKg:'100+'})];
  const base={sex:'F',equipment:'Raw',event:'SBD',tested:'yes',federation:'FIX',from:'2025-01-01',to:'2025-12-31',
    bodyweightMin:'70.5',bodyweightMax:'70.5',limit:2};
  const strip=({durationMs,...result})=>result;
  try {
    await writeFile(file,[columns,...rows.map(r=>columns.map(c=>r[c]??''))].map(r=>r.join(',')).join('\n')+'\n');
    const info=await importSnapshot({root,file});
    const run=(params,narrow)=>withSnapshot(root,info.version,selected=>
      executeQuery(root,prepareQuery('rankings',{...params,version:info.version}),selected,{narrowRankings:narrow}));
    const first=await run(base,true);
    assert.deepEqual(first.results.map(r=>[r.Name,r.row_id,r.MeetName]),[
      ['Fixture Alpha #1',3,'winning last row'],['Fixture Alpha #2',5,'Synthetic only']]);
    assert.equal(first.results[0].Squat1Kg,-100);assert.equal(first.results[0].Bench1Kg,null);
    const second=await run({...base,cursor:first.nextCursor},true);
    assert.deepEqual(second.results.map(r=>r.Name),['Fixture Beta','Fixture Guest']);assert.equal(second.nextCursor,null);
    assert.deepEqual((await run({...base,weightClass:'+'},true)).results.map(r=>r.Name),['Fixture Alpha #2']);
    assert.deepEqual((await run({...base,weightClass:'-74'},true)).results.map(r=>r.Name),['Fixture Beta']);
    assert.deepEqual((await run({...base,tested:'not-designated'},true)).results.map(r=>r.Name),['Fixture Untested']);
    assert.equal((await run({...base,from:'2025-02-01',to:'2025-02-01'},true)).results[0].row_id,3);
    const cases=[base,{sex:'F',equipment:'Raw',event:'SBD',limit:1},
      {...base,weightClass:'75'},{...base,weightClass:'+'},{...base,weightClass:'-74'},
      {...base,tested:'not-designated'},{...base,federation:'OTHER'},
      {...base,from:'2025-02-01',to:'2025-02-01'},{...base,bodyweightMin:'71',bodyweightMax:'100',weightClass:'100+'},
      {...base,federation:'NONE'},...['squat','bench','deadlift','dots'].map(metric=>({...base,metric}))];
    for(const params of cases) {
      let cursor;
      do {
        const input={...params,...(cursor?{cursor}:{})};
        const wide=await run(input,false),narrow=await run(input,true);
        assert.deepEqual(strip(narrow),strip(wide),JSON.stringify(input));cursor=wide.nextCursor;
      } while(cursor);
    }
  } finally {
    assert(path.resolve(temp).startsWith(path.resolve(tmpdir())+path.sep));await rm(temp,{recursive:true,force:true});
  }
});
