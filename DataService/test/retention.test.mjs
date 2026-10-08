import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm,mkdir,readdir,symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {once} from 'node:events';
import {fork} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import {columns} from '../src/schema.mjs';
import {importSnapshot} from '../src/import.mjs';
import {current,atomicJSON,manifest} from '../src/storage.mjs';
import {withSnapshot,pruneSnapshots,recoverCatalogLock,withCatalogLock} from '../src/snapshot-lifecycle.mjs';
import {query,prepareQuery} from '../src/query.mjs';
import {serve} from '../src/server.mjs';

const day=86_400_000;
async function fixture() {
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-retention-')),root=path.join(temp,'service'),versions=[];
  const at=Date.now();
  for(let index=0;index<4;index++) {
    const rows=['Fixture Alpha','Fixture Beta'].map(Name=>({Name,Sex:'F',Event:'SBD',Equipment:'Raw',Place:'1',
      Federation:'FIX',MeetCountry:'USA',MeetName:'Synthetic retention only',Date:'2025-01-01',TotalKg:String(400+index)}));
    const csv=[columns.join(','),...rows.map(row=>columns.map(c=>row[c]??'').join(','))].join('\n');
    const file=path.join(temp,index+'.csv');await writeFile(file,csv);
    versions.push((await importSnapshot({root,file})).version);
    // Remove millisecond tie uncertainty from count-retention assertions in synthetic fixtures.
    const info=await manifest(root,versions[index]);
    await atomicJSON(path.join(root,'snapshots',versions[index],'manifest.json'),{...info,importedAt:new Date(at+index).toISOString()});
  }
  return {temp,root,versions,at};
}
async function cleanup(temp) {
  assert(path.resolve(temp).startsWith(path.resolve(tmpdir())+path.sep));
  await rm(temp,{recursive:true,force:true});
}
const heldReaderFile=fileURLToPath(new URL('./fixtures/held-reader.mjs',import.meta.url));

test('reader registration waits behind catalog/prune ownership; waiting child gets no SQL until commit',async()=>{
  const f=await fixture();
  try {
    await withSnapshot(f.root,f.versions[0],async selected=>{
      let enter,release;const entered=new Promise(resolve=>enter=resolve),wait=new Promise(resolve=>release=resolve);
      const holder=withCatalogLock(f.root,async()=>{enter();await wait;});await entered;
      const child=fork(fileURLToPath(new URL('../src/query-child.mjs',import.meta.url)),[],{stdio:['ignore','ignore','ignore','ipc'],windowsHide:true});
      const closed=once(child,'close'),messages=[];child.on('message',message=>messages.push(message));
      let registered=false,sent=false;
      const registering=selected.registerReader(child.pid).then(()=>{
        registered=true;
        if(!child.killed) {sent=true;child.send({root:f.root,prepared:prepareQuery('search',{q:'fixture'}),
          selected:{version:selected.version,info:selected.info,pointer:selected.pointer}});}
      });
      try {
        await delay(60);
        assert.equal(registered,false,'registration bypassed the held prune/catalog critical section');
        assert.equal(sent,false);assert.deepEqual(messages,[]);
        const leaseNames=await readdir(path.join(f.root,'reader-leases'));
        const lease=JSON.parse(await readFile(path.join(f.root,'reader-leases',leaseNames[0]),'utf8'));
        assert.equal(lease.readerPID,undefined);
        release();await holder;await registering;
        const [code]=await closed;assert.equal(code,0);assert.equal(messages[0].type,'started');
        const result=JSON.parse(messages.find(message=>message.type==='result').json);assert.equal(result.version,f.versions[0]);
      } finally {
        release();await holder;
        if(child.exitCode===null&&child.signalCode===null) child.kill('SIGKILL');
        await closed;await registering;
      }
    });
    assert.deepEqual(await readdir(path.join(f.root,'reader-leases')),[]);
  } finally {await cleanup(f.temp);}
});
async function hold(root,version) {
  const child=fork(heldReaderFile,[root,version],{stdio:['ignore','ignore','pipe','ipc']});
  let stderr='';child.stderr.on('data',data=>stderr+=data);
  const exited=once(child,'exit');
  let timer;
  try {
    const [message]=await Promise.race([once(child,'message'),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Reader readiness timeout: '+stderr)),5000);})]);
    assert.equal(message.type,'ready');assert.equal(message.count,2);
  } catch(error) {child.kill();await exited;throw error;}
  finally {clearTimeout(timer);}
  return {child,exited,release:async()=>{child.send({release:true});const [code]=await exited;assert.equal(code,0,stderr);}};
}

test('cross-process active version lease survives pruning; release expires cursor with stable HTTP 409',async()=>{
  const f=await fixture();let reader;
  try {
    const [a,b,c,d]=f.versions;
    assert.equal((await current(f.root)).previousVersion,c);
    const page=await query(f.root,'search',{q:'fixture',limit:1,version:a});assert(page.nextCursor);
    reader=await hold(f.root,a);
    const protectedReport=await pruneSnapshots({root:f.root,apply:true,clock:()=>f.at+10*day});
    assert(protectedReport.kept.some(x=>x.version===a&&x.reason==='active reader'));
    assert.equal(protectedReport.deleted.length,0);
    await reader.release();reader=null;
    const report=await pruneSnapshots({root:f.root,apply:true,clock:()=>f.at+10*day});
    assert.deepEqual(report.eligible,[a]);assert.equal(report.deleted.length,1);assert.equal(report.failures.length,0);
    assert.deepEqual((await readdir(path.join(f.root,'snapshots'))).sort(),[b,c,d].sort());
    assert.equal((await query(f.root,'search',{q:'fixture'})).version,d);
    await assert.rejects(query(f.root,'search',{q:'fixture',limit:1,cursor:page.nextCursor}),/VERSION_UNAVAILABLE/);
    const server=serve({root:f.root,port:0});await once(server,'listening');
    try {
      const response=await fetch(`http://127.0.0.1:${server.address().port}/lifters?q=fixture&limit=1&cursor=${page.nextCursor}`);
      assert.equal(response.status,409);assert.deepEqual(await response.json(),{error:'VERSION_UNAVAILABLE'});
    } finally {await new Promise(resolve=>server.close(resolve));}
    assert.equal((await readdir(path.join(f.root,'reader-leases'))).length,0);
  } finally {if(reader) {reader.child.kill();await reader.exited;}await cleanup(f.temp);}
});

test('dry run preserves all files, access grace protects continuations and explicit rollback outranks age/count',async()=>{
  const f=await fixture();
  try {
    const [a,b,c,d]=f.versions;
    const dry=await pruneSnapshots({root:f.root,clock:()=>f.at+10*day,keepVersions:2});
    assert.equal(dry.dryRun,true);assert.deepEqual(dry.eligible.sort(),[a,b].sort());
    assert.equal((await readdir(path.join(f.root,'snapshots'))).length,4);
    await withSnapshot(f.root,a,async()=>{}, {clock:()=>f.at+9*day});
    const recent=await pruneSnapshots({root:f.root,apply:true,keepVersions:2,clock:()=>f.at+10*day});
    assert(recent.kept.some(x=>x.version===a&&x.reason==='recent import/publication/read'));
    assert.deepEqual(recent.eligible,[b]);
    // Synthetic rollback pointer deliberately targets the oldest rather than newest retained version.
    const pointer=await current(f.root);await atomicJSON(path.join(f.root,'current.json'),{...pointer,previousVersion:a});
    const later=await pruneSnapshots({root:f.root,apply:true,keepVersions:2,clock:()=>f.at+20*day});
    assert(later.kept.some(x=>x.version===a&&x.reason==='current/rollback/count'));
    assert.equal((await query(f.root,'search',{q:'fixture',version:a})).version,a);
    assert.equal((await current(f.root)).version,d);assert.equal((await manifest(f.root,c)).version,c);
  } finally {await cleanup(f.temp);}
});

test('publication refresh lock excludes prune; failed reader cleans its lease; dead process lease is recoverable',async()=>{
  const f=await fixture();
  try {
    const a=f.versions[0];
    await assert.rejects(withSnapshot(f.root,a,async()=>{throw new Error('Synthetic query failure');}),/Synthetic query failure/);
    assert.equal((await readdir(path.join(f.root,'reader-leases'))).length,0);
    let entered,release;const ready=new Promise(resolve=>entered=resolve),wait=new Promise(resolve=>release=resolve);
    const publishing=importSnapshot({root:f.root,file:path.join(f.temp,'0.csv'),beforePublish:async()=>{entered();await wait;}});
    await ready;
    try {await assert.rejects(pruneSnapshots({root:f.root,apply:true}),/REFRESH_BUSY/);}
    finally {release();}
    await publishing;
    assert.equal((await current(f.root)).previousVersion,f.versions[3]);
    const reader=await hold(f.root,f.versions[1]);reader.child.kill();await reader.exited;
    const cleaned=await pruneSnapshots({root:f.root,apply:true,keepVersions:2,clock:()=>f.at+10*day});
    assert.equal(cleaned.deadLeases.length,1);
    assert(cleaned.eligible.includes(f.versions[1]));
    assert.equal((await readdir(path.join(f.root,'reader-leases'))).length,0);
    const lockFile=path.join(f.root,'lifecycle','catalog.lock');
    await writeFile(lockFile,JSON.stringify({pid:process.pid,nonce:'synthetic-live-owner'}));
    await assert.rejects(recoverCatalogLock(f.root,process.pid),/owner is still alive/);await rm(lockFile);
    await writeFile(lockFile,JSON.stringify({pid:reader.child.pid,nonce:'synthetic-interrupted-owner'}));
    await assert.rejects(recoverCatalogLock(f.root,process.pid),/EXACT_DEAD_CATALOG_PID_REQUIRED/);
    assert.equal((await recoverCatalogLock(f.root,reader.child.pid)).recovered,true);
    assert.equal((await query(f.root,'search',{q:'fixture'})).version,a);
  } finally {await cleanup(f.temp);}
});

test('malformed leases, missing rollback and managed junctions fail closed; unknown directories are never deleted',async()=>{
  const f=await fixture();
  try {
    const lease=path.join(f.root,'reader-leases','11111111-1111-1111-1111-111111111111.json');
    await mkdir(path.dirname(lease),{recursive:true});
    await writeFile(lease,JSON.stringify({version:f.versions[0],pid:0,startedAt:new Date().toISOString()}));
    await assert.rejects(pruneSnapshots({root:f.root,apply:true,clock:()=>f.at+10*day}),/INVALID_READER_LEASE/);
    assert.equal((await readdir(path.join(f.root,'snapshots'))).length,4);await rm(lease);
    const pointer=await current(f.root);await atomicJSON(path.join(f.root,'current.json'),{...pointer,previousVersion:'f'.repeat(64)});
    await assert.rejects(pruneSnapshots({root:f.root,apply:true}),/VERSION_UNAVAILABLE/);await atomicJSON(path.join(f.root,'current.json'),pointer);
    const unknown=path.join(f.root,'snapshots','not-a-snapshot');await mkdir(unknown);await writeFile(path.join(unknown,'keep.txt'),'preserve');
    const unverified='e'.repeat(64)+'-11111111-1111-1111-1111-111111111111';
    await mkdir(path.join(f.root,'retired-snapshots',unverified));
    const report=await pruneSnapshots({root:f.root,apply:true,clock:()=>f.at+10*day});
    assert(report.unknownEntries.includes('not-a-snapshot'));assert(report.unknownEntries.includes('unverified retired/'+unverified));
    assert.equal(await readFile(path.join(unknown,'keep.txt'),'utf8'),'preserve');
    await assert.rejects(pruneSnapshots({root:f.root,keepVersions:1}),/INVALID_RETENTION_POLICY/);
    const linkedRoot=path.join(f.temp,'linked-service'),outside=path.join(f.temp,'outside');await mkdir(linkedRoot);await mkdir(outside);
    await writeFile(path.join(outside,'sentinel'),'preserve');
    await symlink(outside,path.join(linkedRoot,'snapshots'),process.platform==='win32'?'junction':'dir');
    await assert.rejects(pruneSnapshots({root:linkedRoot,apply:true}),/UNSAFE_MANAGED_DIRECTORY/);
    assert.equal(await readFile(path.join(outside,'sentinel'),'utf8'),'preserve');
  } finally {await cleanup(f.temp);}
});
