import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm,readdir,access,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {once} from 'node:events';
import {fork,spawn} from 'node:child_process';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath} from 'node:url';
import http from 'node:http';
import {setTimeout as delay} from 'node:timers/promises';
import {columns} from '../src/schema.mjs';
import {importSnapshot} from '../src/import.mjs';
import {current} from '../src/storage.mjs';
import {query,dataset} from '../src/query.mjs';
import {QueryPool} from '../src/query-pool.mjs';
import {pruneSnapshots} from '../src/snapshot-lifecycle.mjs';
import {serve} from '../src/server.mjs';

const busyWorker=new URL('./fixtures/busy-query-child.mjs',import.meta.url),day=86_400_000;
async function fixture() {
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-query-pool-')),root=path.join(temp,'service'),versions=[];
  for(let index=0;index<4;index++) {
    const rows=['Fixture Alpha','Fixture Beta'].map(Name=>({Name,Sex:'F',Event:'SBD',Equipment:'Raw',Place:'1',Federation:'FIX',
      MeetCountry:'USA',MeetName:'Synthetic worker isolation',Date:'2025-01-01',TotalKg:String(400+index)}));
    const file=path.join(temp,index+'.csv');await writeFile(file,[columns.join(','),...rows.map(row=>columns.map(c=>row[c]??'').join(','))].join('\n'));
    versions.push((await importSnapshot({root,file})).version);
    await delay(2); // Deterministic oldest version for retention count in a small synthetic fixture.
  }
  await mkdir(path.join(root,'reader-leases'),{recursive:true});
  return {temp,root,versions};
}
async function cleanup(temp) {
  assert(path.resolve(temp).startsWith(path.resolve(tmpdir())+path.sep));await rm(temp,{recursive:true,force:true});
}
async function clean(root) {
  assert.deepEqual(await readdir(path.join(root,'reader-leases')),[]);
  await assert.rejects(access(path.join(root,'lifecycle','catalog.lock')),error=>error.code==='ENOENT');
}
function events() {
  const log=[],waiters=[];
  return {log,onEvent:event=>{log.push(event);if(event.type==='started') waiters.splice(0).forEach(resolve=>resolve(event));},
    started:()=>new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('Worker did not start within two seconds')),2000);
      waiters.push(event=>{clearTimeout(timer);resolve(event);});
    })};
}
function dead(pid) {assert.throws(()=>process.kill(pid,0),error=>error.code==='ESRCH');}

test('parent death cannot retire a surviving SQLite child; recorded reader PID protects until confirmed death',async t=>{
  const f=await fixture();let parent,readerPID;
  try {
    parent=fork(fileURLToPath(new URL('./fixtures/query-parent.mjs',import.meta.url)),[f.root,f.versions[0]],
      {stdio:['ignore','ignore','ignore','ipc'],windowsHide:true});
    const parentExit=once(parent,'exit');let timer;
    const [message]=await Promise.race([once(parent,'message'),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Parent fixture did not start child')),3000);})]);
    clearTimeout(timer);assert.equal(message.type,'ready');readerPID=message.readerPID;
    const files=await readdir(path.join(f.root,'reader-leases'));assert.equal(files.length,1);
    const lease=JSON.parse(await readFile(path.join(f.root,'reader-leases',files[0]),'utf8'));
    assert.equal(lease.pid,parent.pid);assert.equal(lease.readerPID,readerPID);
    parent.kill('SIGKILL');await parentExit;dead(parent.pid);parent=null;
    let survives=true;try {process.kill(readerPID,0);}catch(error) {if(error.code==='ESRCH') survives=false;else throw error;}
    t.diagnostic('Reader survived parent termination: '+survives);
    if(survives) {
      const protectedReport=await pruneSnapshots({root:f.root,apply:true,clock:()=>Date.now()+10*day});
      assert(protectedReport.kept.some(item=>item.version===f.versions[0]&&item.reason==='active reader'));
      process.kill(readerPID,'SIGKILL');
      const until=performance.now()+2000;
      for(;;) {try {process.kill(readerPID,0);}catch(error) {if(error.code==='ESRCH') break;throw error;}
        assert(performance.now()<until,'Orphan child teardown exceeded test tolerance');await delay(10);}
    }
    dead(readerPID);readerPID=null;
    const report=await pruneSnapshots({root:f.root,apply:true,clock:()=>Date.now()+10*day});
    assert(report.eligible.includes(f.versions[0]));assert.equal(report.deadLeases.length,1);await clean(f.root);
  } finally {
    if(parent) parent.kill('SIGKILL');
    if(readerPID) {try {process.kill(readerPID,'SIGKILL');}catch(error) {if(error.code!=='ESRCH') throw error;}}
    await cleanup(f.temp);
  }
});

test('actual blocking SQLite child is terminated on deadline; metadata remains responsive and lease releases after confirmed exit',async()=>{
  const f=await fixture(),diagnostics=events(),pool=new QueryPool({root:f.root,maxWorkers:1,workerURL:busyWorker,queryTimeoutMs:400,onEvent:diagnostics.onEvent});
  try {
    const started=diagnostics.started(),began=performance.now();
    const blocked=assert.rejects(pool.run('search',{q:'blocking',version:f.versions[0]}),/QUERY_TIMEOUT/);
    const worker=await started;
    const metadataBegan=performance.now();assert.equal((await dataset(f.root)).dataset.version,f.versions[3]);
    assert(performance.now()-metadataBegan<500,'metadata blocked behind child SQL');
    assert((await readdir(path.join(f.root,'reader-leases'))).length>=1);
    await blocked;
    assert(performance.now()-began<2000,'deadline teardown did not complete in test tolerance');
    dead(worker.pid);assert(diagnostics.log.some(event=>event.type==='exit'&&event.pid===worker.pid));await clean(f.root);
    assert.equal(pool.stats.active,0);
    assert.equal((await pool.run('search',{q:'fixture'})).version,f.versions[3]);await clean(f.root);
    const pruned=await pruneSnapshots({root:f.root,apply:true,clock:()=>Date.now()+10*day});
    assert(pruned.eligible.includes(f.versions[0]));assert.equal(pruned.failures.length,0);
  } finally {await pool.close();await cleanup(f.temp);}
});

test('simulated dead controller with a real surviving independent database reader is protected by reader PID alone',async()=>{
  const f=await fixture();let db;
  try {
    const controller=spawn(process.execPath,['-e','process.exit(0)'],{stdio:'ignore',windowsHide:true});
    await once(controller,'close');dead(controller.pid);
    db=new DatabaseSync(path.join(f.root,'snapshots',f.versions[0],'data.sqlite'),{readOnly:true});
    assert.equal(db.prepare('SELECT count(*) AS n FROM results').get().n,2);
    const leaseFile=path.join(f.root,'reader-leases','11111111-1111-1111-1111-111111111111.json');
    // This ledger simulates a controller/reader relationship; the reader/database and both PID states are real.
    await writeFile(leaseFile,JSON.stringify({version:f.versions[0],pid:controller.pid,readerPID:process.pid,startedAt:new Date().toISOString()}));
    const protectedReport=await pruneSnapshots({root:f.root,apply:true,clock:()=>Date.now()+10*day});
    assert(protectedReport.kept.some(item=>item.version===f.versions[0]&&item.reason==='active reader'));
    assert.equal(db.prepare('SELECT count(*) AS n FROM results').get().n,2);db.close();db=null;
    await rm(leaseFile);
    const pruned=await pruneSnapshots({root:f.root,apply:true,clock:()=>Date.now()+10*day});
    assert(pruned.eligible.includes(f.versions[0]));
  } finally {db?.close();await cleanup(f.temp);}
});

test('queue bound, queue expiry and queued/active cancellation leave no leases and allow a subsequent query',async()=>{
  const f=await fixture(),diagnostics=events(),pool=new QueryPool({root:f.root,maxWorkers:1,maxQueue:1,queueTimeoutMs:40,
    queryTimeoutMs:3000,workerURL:busyWorker,onEvent:diagnostics.onEvent});
  try {
    const controller=new AbortController(),started=diagnostics.started();
    const blocked=assert.rejects(pool.run('search',{q:'blocking'},{signal:controller.signal}),/QUERY_CANCELLED/);
    const worker=await started;
    const queued=assert.rejects(pool.run('search',{q:'fixture'}),/QUERY_QUEUE_TIMEOUT/);
    await assert.rejects(pool.run('search',{q:'fixture'}),/QUERY_BUSY/);await queued;
    const waitingController=new AbortController();
    const waiting=assert.rejects(pool.run('search',{q:'fixture'},{signal:waitingController.signal}),/QUERY_CANCELLED/);
    waitingController.abort();await waiting;
    controller.abort();await blocked;dead(worker.pid);await clean(f.root);
    assert.deepEqual(pool.stats,{active:0,queued:0,closed:false});
    assert.equal((await pool.run('search',{q:'fixture'})).results.length,2);await clean(f.root);
  } finally {await pool.close();await cleanup(f.temp);}
});

test('HTTP timeout/busy/disconnect/shutdown cancel children without orphaning catalog ownership',async()=>{
  const f=await fixture(),diagnostics=events();let server;
  try {
    server=serve({root:f.root,port:0,queryOptions:{maxWorkers:1,maxQueue:0,queryTimeoutMs:500,workerURL:busyWorker,onEvent:diagnostics.onEvent}});
    await once(server,'listening');const base=`http://127.0.0.1:${server.address().port}`;
    let started=diagnostics.started();const timed=fetch(base+'/lifters?q=blocking');const worker=await started;
    const busy=await fetch(base+'/lifters?q=fixture');assert.equal(busy.status,503);assert.equal(busy.headers.get('retry-after'),'1');
    assert.equal((await fetch(base+'/dataset')).status,200);
    const timeout=await timed;assert.equal(timeout.status,504);assert.equal((await timeout.json()).error,'QUERY_TIMEOUT');dead(worker.pid);await clean(f.root);
    started=diagnostics.started();const disconnected=http.get(base+'/lifters?q=blocking');disconnected.on('error',()=>{});const second=await started;
    const closed=new Promise(resolve=>disconnected.once('close',resolve));disconnected.destroy();await closed;
    const until=performance.now()+2000;
    while(!diagnostics.log.some(event=>event.type==='exit'&&event.pid===second.pid)&&performance.now()<until) await delay(10);
    dead(second.pid);
    // HTTP disconnect cleanup finishes after confirmed child exit and async lease unlink.
    for(let attempt=0;attempt<100&&(await readdir(path.join(f.root,'reader-leases'))).length;attempt++) await delay(10);
    await clean(f.root);assert.equal((await fetch(base+'/lifters?q=fixture')).status,200);
    started=diagnostics.started();const shutting=fetch(base+'/lifters?q=blocking');const third=await started;
    await new Promise(resolve=>server.close(resolve));server=null;
    assert.equal((await shutting).status,503);dead(third.pid);await clean(f.root);
    assert.equal((await query(f.root,'search',{q:'fixture'})).version,(await current(f.root)).version);
  } finally {if(server) await new Promise(resolve=>server.close(resolve));await cleanup(f.temp);}
});

test('real child contract matches direct queries; worker crash/wrong version and closed pool fail safely',async()=>{
  const f=await fixture(),pool=new QueryPool({root:f.root});let fixturePool;
  try {
    const direct=await query(f.root,'search',{q:'fixture',limit:1}),isolated=await pool.run('search',{q:'fixture',limit:1});
    assert.deepEqual(isolated.results,direct.results);assert.equal(isolated.nextCursor,direct.nextCursor);
    const next=await pool.run('search',{q:'fixture',limit:1,cursor:isolated.nextCursor});assert.equal(next.results[0].Name,'Fixture Beta');
    const rankings=await pool.run('rankings',{sex:'F',equipment:'Raw',event:'SBD'});assert.equal(rankings.results[0].TotalKg,403);
    const history=await pool.run('history',{id:isolated.results[0].lifterId});assert.equal(history.results[0].Name,'Fixture Alpha');
    fixturePool=new QueryPool({root:f.root,workerURL:busyWorker});
    await assert.rejects(fixturePool.run('search',{q:'crash'}),/QUERY_WORKER_FAILED/);await clean(f.root);
    await assert.rejects(fixturePool.run('search',{q:'wrongversion'}),/QUERY_WORKER_PROTOCOL/);await clean(f.root);
    await pool.close();await assert.rejects(pool.run('search',{q:'fixture'}),/QUERY_SERVICE_CLOSED/);
    assert.throws(()=>new QueryPool({root:f.root,maxWorkers:0}),/INVALID_QUERY_LIMITS/);
  } finally {await pool.close();await fixturePool?.close();await cleanup(f.temp);}
});
