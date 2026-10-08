import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {once} from 'node:events';
import {createWriteStream} from 'node:fs';
import {pipeline} from 'node:stream/promises';
import yazl from 'yazl';
import {DatabaseSync} from 'node:sqlite';
import {columns} from '../src/schema.mjs';
import {importSnapshot,fileHash} from '../src/import.mjs';
import {current,withLock} from '../src/storage.mjs';
import {query,dataset} from '../src/query.mjs';
import {refresh} from '../src/refresh.mjs';
import {serve} from '../src/server.mjs';
import {row,first,second,csv} from './fixtures/service-data.mjs';
const filters={sex:'F',equipment:'Raw',event:'SBD'};
const lifterId=name=>Buffer.from(name).toString('base64url');
const cleanup=temp=>{
  assert(path.resolve(temp).startsWith(path.resolve(tmpdir())+path.sep));
  return rm(temp,{recursive:true,force:true});
};

test('dataset metadata is pinned across publication/status gaps and identical-content new sources',async()=>{
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-metadata-'));
  try {
    const root=path.join(temp,'service'),seed=path.join(temp,'seed.zip'),meta=path.join(temp,'seed.json');
    const urls={landing:'https://fixture.invalid/landing',archive:'https://fixture.invalid/archive'};
    let sourceDate='2025-01-01',revision='feedcafe',etag='"source-a"';
    const prepare=async(rows)=>{
      const zip=new yazl.ZipFile();zip.addBuffer(Buffer.from(csv(rows)),`openpowerlifting-${sourceDate}/openpowerlifting-${sourceDate}-${revision}.csv`);zip.end();
      await pipeline(zip.outputStream,createWriteStream(seed));
      await writeFile(meta,JSON.stringify({etag,revision,sha256:await fileHash(seed),checkedAtUTC:sourceDate+'T00:00:00Z'}));
    };
    const fetcher=async(url,options={})=>url===urls.landing?
      new Response(`Updated: ${sourceDate} <a>${revision}</a> openpowerlifting-latest.zip<td>1M</td><td>8</td>`):
      options.method==='HEAD'?new Response(null,{headers:{etag,'last-modified':sourceDate}}):Promise.reject(Error('Unexpected download'));
    await prepare(first);
    const a=await refresh({root,seedFile:seed,seedMetadata:meta,fetcher,urls});
    assert.equal((await dataset(root)).sourceDate,'2025-01-01');
    const bFile=path.join(temp,'b.csv');await writeFile(bFile,csv(second));
    const b=await importSnapshot({root,file:bFile,source:{archiveDate:'2025-02-01',revision:'feedcafb',etag:'"source-b"',lastModified:'2025-02-01'}});
    assert.notEqual(a.version,b.version);
    const server=serve({root,port:0});await once(server,'listening');
    try {
      const response=await fetch(`http://127.0.0.1:${server.address().port}/dataset`);
      const observed=await response.json();
      assert.equal(observed.dataset.version,b.version);assert.equal(observed.sourceDate,'2025-02-01');
      assert.equal(observed.latestValidatedSource.revision,'feedcafb');assert.equal(observed.statusMatchesDataset,false);
      assert.equal(observed.validation.version,b.version);assert.equal(observed.status.validatedVersion,a.version);
    } finally {await new Promise(r=>server.close(r));}
    sourceDate='2025-02-01';revision='feedcafb';etag='"source-b"';
    const checkedB=await refresh({root,seedFile:seed,seedMetadata:meta,fetcher,urls});
    assert.equal(checkedB.unchanged,true);
    assert.equal((await dataset(root)).validation.validatedAt,b.importedAt);
    sourceDate='2025-03-01';revision='feedcafc';etag='"source-c"';await prepare(second);
    const same=await refresh({root,seedFile:seed,seedMetadata:meta,fetcher,urls});
    assert.equal(same.version,b.version);assert.equal(same.unchanged,true);
    const latest=await dataset(root);assert.equal(latest.sourceDate,'2025-03-01');
    assert.equal(latest.statusMatchesDataset,true);assert.equal(latest.validation.version,b.version);
  } finally {await cleanup(temp);}
});

test('version replacement, readers, pagination, identity, ranking semantics, exclusion, and atomic failures',async()=>{
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-service-'));
  try {
    const root=path.join(temp,'service'),v1=path.join(temp,'v1.csv'),v2=path.join(temp,'v2.csv');
    await writeFile(v1,csv(first));await writeFile(v2,csv(second));
    const initial=await importSnapshot({root,file:v1});
    assert.equal(initial.rows,8);
    const search=await query(root,'search',{q:'fixture alice',limit:1});assert.equal(search.results[0].Name,'Fixture Alice #1');assert(search.nextCursor);
    const previousRank=await query(root,'rankings',filters);assert.deepEqual(previousRank.results.map(r=>r.TotalKg),[520,500,490,480]);
    const history=await query(root,'history',{id:lifterId('Fixture Alice #1')});assert.equal(history.results.length,2);
    assert.equal(history.results[0].Squat1Kg,-100);assert.equal(history.results[0].Bench1Kg,null);assert(history.results[0].MeetName.includes('\n'));
    const heldReader=new DatabaseSync(path.join(root,'snapshots',initial.version,'data.sqlite'),{readOnly:true});
    let release,ready;const publicationReached=new Promise(r=>ready=r),wait=new Promise(r=>release=r);
    const publishing=importSnapshot({root,file:v2,beforePublish:async()=>{ready();await wait;}});
    await publicationReached;
    assert.equal((await current(root)).version,initial.version);
    assert.equal((await query(root,'rankings',filters)).results[0].TotalKg,520);
    await assert.rejects(importSnapshot({root,file:v1}),/REFRESH_BUSY/);
    release();const updated=await publishing;
    assert.notEqual(updated.version,initial.version);
    assert.equal(heldReader.prepare('SELECT count(*) AS n FROM results WHERE Name=?').get('Fixture Removed Casey').n,1);heldReader.close();
    assert.deepEqual((await query(root,'rankings',filters)).results.map(r=>r.TotalKg),[550,510,490,480]);
    assert.equal((await query(root,'search',{q:'fixture removed'})).results.length,0);
    assert.equal((await query(root,'search',{q:'fixture new'})).results.length,1);
    assert.deepEqual((await query(root,'history',{id:lifterId('Fixture Alice #1')})).results.map(r=>r.TotalKg),[530,550]);
    const oldPage=await query(root,'search',{q:'fixture alice',limit:1,cursor:search.nextCursor});assert.equal(oldPage.version,initial.version);assert.equal(oldPage.results[0].Name,'Fixture Alice #2');
    await assert.rejects(query(root,'search',{q:'fixture alice',limit:1,cursor:search.nextCursor,version:updated.version}),/VERSION_MISMATCH/);
    await assert.rejects(query(root,'search',{q:'different',limit:1,cursor:search.nextCursor}),/FILTER_MISMATCH/);
    for(const value of [null,[],true,{}, {kind:'search',offset:0,version:'invalid',signature:'invalid'}]) {
      await assert.rejects(query(root,'search',{q:'fixture alice',cursor:Buffer.from(JSON.stringify(value)).toString('base64url')}),/INVALID_CURSOR/);
    }
    assert.equal((await query(root,'rankings',{...filters,tested:'not-designated'})).results[0].Name,'Fixture Bob');
    assert.equal((await query(root,'rankings',{...filters,weightClass:'+'})).results[0].Name,'Fixture Alice #2');
    assert.equal((await query(root,'rankings',{...filters,weightClass:'-74'})).results[0].Name,'Fixture New Dan');
    assert.equal((await query(root,'rankings',{...filters,bodyweightMin:'71'})).results.length,0);
    assert.equal((await query(root,'rankings',{...filters,from:'2026-01-01'})).results[0].TotalKg,530);
    await assert.rejects(query(root,'rankings',{...filters,unknown:'ignored'}),/UNSUPPORTED_FILTER/);
    await assert.rejects(query(root,'rankings',{sex:'F'}),/REQUIRES/);
    assert.equal((await importSnapshot({root,file:v2})).unchanged,true);
    for(const [name,contents,minimumRows] of [
      ['schema',csv(second,columns.filter(c=>c!=='Name')),1],['malformed','Name,"unterminated',1],
      ['truncated',csv(second.slice(0,1)),8],['bad date',csv([row('Fixture Bad','500',{Date:'2025-02-31'})]),1],
      ['bad category',csv([row('Fixture Bad','500',{Sex:'unknown'})]),1],
      ['bad weight',csv([row('Fixture Bad','NaN')]),1],['duplicate header',csv(second,[...columns,'Name']),1]
    ]) {
      const file=path.join(temp,`${name}.csv`);await writeFile(file,contents);
      await assert.rejects(importSnapshot({root,file,minimumRows}));assert.equal((await current(root)).version,updated.version);
    }
    await assert.rejects(importSnapshot({root,file:v1,beforePublish:()=>{throw new Error('simulated publication failure');}}),/publication failure/);
    assert.equal((await current(root)).version,updated.version);
    const retry=await importSnapshot({root,file:v1});assert.equal(retry.version,initial.version);
    const server=serve({root,port:0});await once(server,'listening');
    try {
      const base=`http://127.0.0.1:${server.address().port}`;
      assert.equal((await fetch(base+'/dataset')).status,200);
      assert.equal((await (await fetch(base+'/lifters?q=fixture%20alice')).json()).results.length,2);
      assert.equal((await fetch(base+'/rankings?sex=F&equipment=Raw&event=SBD&unknown=bad')).status,400);
    } finally {await new Promise(resolve=>server.close(resolve));}
  } finally {await cleanup(temp);}
});

test('scheduler entry checks real import mechanics, no-change idempotence, logged failure recovery, and overlap exclusion',async()=>{
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-refresh-'));
  try {
    const root=path.join(temp,'service'),seed=path.join(temp,'fixture.csv'),metadata=path.join(temp,'seed.json');
    const urls={landing:'https://fixture.invalid/landing',archive:'https://fixture.invalid/archive'};
    let etag='"fixture-v1"',fail=false,revision='feedcafe';
    const fetcher=async(url,options={})=>{
      if(fail) throw new Error('simulated network failure');
      if(url===urls.landing) return new Response(`Updated: 2025-01-01. <a>${revision}</a> openpowerlifting-latest.zip<td style="text-align:right">123M</td><td>8</td>`);
      if(options.method==='HEAD') return new Response(null,{headers:{etag,'last-modified':'Wed, 01 Jan 2025 00:00:00 GMT'}});
      throw new Error('Unexpected download: fixture seed should be reused');
    };
    const prepare=async contents=>{
      await writeFile(seed,contents);await writeFile(metadata,JSON.stringify({etag,revision,sha256:await fileHash(seed),checkedAtUTC:'2025-01-01T00:00:00Z'}));
    };
    await prepare(csv(first));
    const initial=await refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls});assert.equal(initial.rows,8);
    assert.equal(initial.source.reusedArchive,true);
    const repeated=await refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls});assert.equal(repeated.unchanged,true);
    assert.equal((await refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls,dueOnly:true})).skipped,true);
    fail=true;await assert.rejects(refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls}),/network failure/);
    const failed=await dataset(root);assert.equal(failed.dataset.version,initial.version);assert.equal(failed.status.failureCount,1);assert(failed.status.retryAt);
    fail=false;etag='"fixture-v2"';revision='feedcaf1';await prepare(csv(second));
    const updated=await refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls});assert.notEqual(updated.version,initial.version);assert.equal(updated.status.failureCount,0);
    assert.equal((await query(root,'rankings',filters)).results[0].TotalKg,550);
    etag='"fixture-bad"';revision='feedbad0';await prepare('broken CSV');
    await assert.rejects(refresh({root,seedFile:seed,seedMetadata:metadata,fetcher,urls}));
    assert.equal((await current(root)).version,updated.version);assert((await dataset(root)).status.lastError);
    await withLock(root,async()=>{await assert.rejects(refresh({root,fetcher,urls}),/REFRESH_BUSY/);});
  } finally {await cleanup(temp);}
});

test('ZIP stream integrity, CRC, truncated archives, invalid UTF-8, and additive schema retention',async()=>{
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-zip-'));
  try {
    const root=path.join(temp,'service'),zipPath=path.join(temp,'fixture.zip');
    const archive=new yazl.ZipFile();archive.addBuffer(Buffer.from(csv(first)),'synthetic.csv');archive.end();
    await pipeline(archive.outputStream,createWriteStream(zipPath));
    const valid=await importSnapshot({root,file:zipPath});assert.equal(valid.rows,8);assert.equal(valid.csvEntry,'synthetic.csv');
    const original=await readFile(zipPath);
    const downloadRoot=path.join(temp,'download-service');
    let downloadFailure=false;
    const urls={landing:'https://fixture.invalid/landing',archive:'https://fixture.invalid/archive'};
    const fetcher=async(url,options={})=>{
      if(url===urls.landing) return new Response('Updated: 2025-01-01 <a>feedcafe</a> openpowerlifting-latest.zip<td>123M</td><td>8</td>');
      const etag=downloadFailure?'"changed"':'"downloaded"';
      if(options.method==='HEAD') return new Response(null,{headers:{etag}});
      return downloadFailure?new Response('failed',{status:500}):new Response(original,{headers:{etag}});
    };
    const downloaded=await refresh({root:downloadRoot,fetcher,urls});assert.equal(downloaded.rows,8);assert.equal(downloaded.source.reusedArchive,false);
    downloadFailure=true;await assert.rejects(refresh({root:downloadRoot,fetcher,urls}),/Download HTTP 500/);
    assert.equal((await current(downloadRoot)).version,downloaded.version);
    const central=original.indexOf(Buffer.from([0x50,0x4b,0x01,0x02]));assert(central>=0);
    const corrupted=Buffer.from(original);corrupted.writeUInt32LE((corrupted.readUInt32LE(central+16)^1)>>>0,central+16);
    const bad=path.join(temp,'bad.zip');await writeFile(bad,corrupted);
    await assert.rejects(importSnapshot({root,file:bad}),/CRC mismatch/);
    const truncated=path.join(temp,'truncated.zip');await writeFile(truncated,original.subarray(0,original.length-20));
    await assert.rejects(importSnapshot({root,file:truncated}));assert.equal((await current(root)).version,valid.version);
    const invalid=path.join(temp,'invalid.csv');await writeFile(invalid,Buffer.concat([Buffer.from(columns.join(',')+'\n'),Buffer.from([0xff,0xfe])]));
    await assert.rejects(importSnapshot({root,file:invalid}));assert.equal((await current(root)).version,valid.version);
    const additive=path.join(temp,'extra.csv');await writeFile(additive,csv([row('Fixture Extra','500',{NewField:'preserved'})],[...columns,'NewField']));
    await importSnapshot({root,file:additive});
    assert.equal((await query(root,'history',{id:lifterId('Fixture Extra')})).results[0].extraFields.NewField,'preserved');
  } finally {await cleanup(temp);}
});
