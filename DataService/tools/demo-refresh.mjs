import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {columns} from '../src/schema.mjs';
import {refresh,checkIntervalMs} from '../src/refresh.mjs';
import {fileHash} from '../src/import.mjs';
import {dataset,query} from '../src/query.mjs';
import {atomicJSON} from '../src/storage.mjs';

// Synthetic source/scheduling clock only. Actual parser/index/query/storage execute.
const project=fileURLToPath(new URL('../../',import.meta.url));
const directory=path.join(project,'artifacts','refresh-demo');
const root=path.join(directory,'synthetic-'+randomUUID());
await mkdir(root,{recursive:true});
const seed=path.join(root,'source.csv'),metadata=path.join(root,'seed.json');
let virtual=Date.parse('2026-10-03T12:00:00Z'),sourceDate='2026-10-01',revision='feedcafe',etag='"a"',failure=false,requests=0;
const urls={landing:'https://synthetic.invalid/landing',archive:'https://synthetic.invalid/archive'};
const row=(Name,TotalKg)=>({Name,TotalKg,Sex:'F',Event:'SBD',Equipment:'Raw',Place:'1',Federation:'SYNTHETIC',MeetCountry:'USA',MeetName:'Synthetic scheduler fixture',Date:sourceDate,Tested:'Yes',Sanctioned:'Yes'});
const original=[['Synthetic Alice','500'],['Synthetic Removed','510'],['Synthetic Bob','400']];
const changed=[['Synthetic Alice','550'],['Synthetic Added','800'],['Synthetic Bob','400']];
const seedRows=async(values)=>{
  // Keep meet date fixed across source rechecks; source date is independent metadata.
  const rows=values.map(([name,total])=>({...row(name,total),Date:'2026-09-01'}));
  await writeFile(seed,[columns.join(','),...rows.map(r=>columns.map(c=>r[c]??'').join(','))].join('\n')+'\n');
  await writeFile(metadata,JSON.stringify({etag,revision,sha256:await fileHash(seed),checkedAtUTC:new Date(virtual).toISOString()}));
};
const fetcher=async(url,options={})=>{
  requests++;if(failure)throw new Error('Synthetic network failure');
  if(url===urls.landing)return new Response(`Updated: ${sourceDate} <a>${revision}</a> openpowerlifting-latest.zip<td>1M</td><td>3</td>`);
  if(options.method==='HEAD')return new Response(null,{headers:{etag,'last-modified':sourceDate}});
  throw Error('Synthetic source is seeded; no real download permitted');
};
const events=[];
const tick=async(label)=>{
  let outcome,error;
  try{outcome=await refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls,dueOnly:true,clock:()=>virtual});}
  catch(value){error=value.message;}
  const info=await dataset(root);
  const event={label,virtualAt:new Date(virtual).toISOString(),outcome:outcome?.skipped?'skipped':error?'failed':outcome?.unchanged?'unchanged':'published',error,
    version:info.dataset?.version,sourceDate:info.sourceDate,retryAt:info.status.retryAt,nextCheckAt:info.status.nextCheckAt,requests};
  events.push(event);await atomicJSON(path.join(root,'timeline.json'),{synthetic:true,events});return event;
};
await seedRows(original);
const a=await tick('bootstrap');assert.equal(a.outcome,'published');
virtual+=5*60_000;const early=await tick('not due');assert.equal(early.outcome,'skipped');assert.equal(early.requests,a.requests);
virtual=Date.parse('2026-10-03T12:00:00Z')+checkIntervalMs;
sourceDate='2026-10-02';revision='feedcafb';etag='"b"';await seedRows(changed);
const b=await tick('due: addition correction removal');assert.notEqual(b.version,a.version);
assert.equal((await query(root,'search',{q:'Synthetic Removed'})).results.length,0);
assert.equal((await query(root,'search',{q:'Synthetic Added'})).results.length,1);
assert.equal((await query(root,'history',{id:Buffer.from('Synthetic Alice').toString('base64url')})).results[0].TotalKg,550);
assert.equal((await query(root,'rankings',{sex:'F',equipment:'Raw',event:'SBD'})).results[0].TotalKg,800);
virtual+=checkIntervalMs;failure=true;const failed=await tick('due: network failure');assert.equal(failed.version,b.version);assert.equal(failed.outcome,'failed');
assert.equal(Date.parse(failed.retryAt)-virtual,15*60_000);
virtual+=5*60_000;const waiting=await tick('before retry');assert.equal(waiting.outcome,'skipped');assert.equal(waiting.requests,failed.requests);
virtual=Date.parse(failed.retryAt);failure=false;sourceDate='2026-10-03';revision='feedcafc';etag='"c"';await seedRows(changed);
const recovered=await tick('retry: same content new source date');assert.equal(recovered.outcome,'unchanged');assert.equal(recovered.version,b.version);assert.equal(recovered.sourceDate,'2026-10-03');assert.equal(recovered.retryAt,null);
const report={synthetic:true,root,events,realUpstreamRequests:0,passed:true,
  caveat:'Scheduling timestamps/source facts are synthetic. Parser/SQLite/query/atomic storage ran locally. Import/metadata network-limit measurements use the real clock. Not production scheduled freshness.'};
await atomicJSON(path.join(directory,'latest-synthetic.json'),report);
console.log(JSON.stringify(report,null,2));
