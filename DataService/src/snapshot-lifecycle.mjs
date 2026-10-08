import {mkdir,open,unlink,readdir,lstat,realpath,rename,rm} from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {atomicJSON,readJSON,current,manifest,withLock,childPath} from './storage.mjs';

const versionPattern=/^[a-f0-9]{64}$/;
const retiredPattern=/^[a-f0-9]{64}-[a-f0-9-]{36}$/;
const leasePattern=/^[a-f0-9-]{36}\.json$/;
const day=86_400_000;
function timestamp(clock) {
  const value=clock();
  if(!Number.isFinite(value)||!Number.isFinite(Date.parse(new Date(value).toISOString()))) throw new Error('INVALID_RETENTION_CLOCK');
  return value;
}
function dateValue(value) {
  const parsed=Date.parse(value);
  if(typeof value!=='string'||!Number.isFinite(parsed)) throw new Error('INVALID_RETENTION_METADATA');
  return parsed;
}
// Local managed directories only. Reject junctions/symlinks before any retirement/deletion.
async function managedDirectory(root,name) {
  await mkdir(root,{recursive:true});
  const base=await realpath(root),folder=childPath(base,name);
  await mkdir(folder,{recursive:true});
  const info=await lstat(folder);
  if(!info.isDirectory()||info.isSymbolicLink()||path.resolve(await realpath(folder))!==folder) throw new Error('UNSAFE_MANAGED_DIRECTORY');
  return folder;
}
export async function withCatalogLock(root,operation) {
  const folder=await managedDirectory(root,'lifecycle');
  const file=path.join(folder,'catalog.lock'),deadline=performance.now()+5000;
  let handle;
  for(;;) {
    try {handle=await open(file,'wx');break;}
    catch(error) {
      if(error.code!=='EEXIST') throw error;
      if(performance.now()>=deadline) throw new Error('SNAPSHOT_BUSY: catalog lock requires owner completion or explicit recovery');
      await delay(20);
    }
  }
  try {
    await handle.writeFile(JSON.stringify({pid:process.pid,nonce:randomUUID(),startedAt:new Date().toISOString()}));await handle.sync();
    return await operation();
  } finally {await handle.close();await unlink(file);}
}
/** Explicit operator recovery only; serialize recovery commands and never remove a live owner's lock. */
export async function recoverCatalogLock(root,pid) {
  if(!Number.isInteger(pid)||pid<1) throw new Error('EXACT_DEAD_CATALOG_PID_REQUIRED');
  const folder=await managedDirectory(root,'lifecycle'),file=path.join(folder,'catalog.lock');
  const info=await lstat(file);
  if(!info.isFile()||info.isSymbolicLink()) throw new Error('INVALID_CATALOG_LOCK');
  const lock=await readJSON(file);
  if(lock?.pid!==pid||typeof lock.nonce!=='string') throw new Error('EXACT_DEAD_CATALOG_PID_REQUIRED');
  try {process.kill(pid,0);throw new Error('Catalog lock owner is still alive; refusing recovery');}
  catch(error) {if(error.code!=='ESRCH') throw error;}
  const confirmed=await readJSON(file);
  if(confirmed?.pid!==pid||confirmed.nonce!==lock.nonce) throw new Error('CATALOG_LOCK_CHANGED');
  await unlink(file);
  return {recovered:true,pid};
}
async function usage(root,version,fields) {
  const folder=await managedDirectory(root,'snapshot-usage'),file=path.join(folder,version+'.json');
  const old=await readJSON(file,{});
  await atomicJSON(file,{...old,version,...fields});
}

/** Lease spans opening/closing the database and all asynchronous work in operation. */
export async function withSnapshot(root,requestedVersion,operation,{allowEmpty=false,clock=Date.now}={}) {
  let lease;
  const selected=await withCatalogLock(root,async()=>{
    const pointer=await current(root),version=requestedVersion??pointer?.version;
    if(!version) {if(allowEmpty) return {info:null,pointer,version:null};throw new Error('NO_DATASET');}
    if(!versionPattern.test(version)) throw new Error('INVALID_VERSION');
    const info=await manifest(root,version),folder=await managedDirectory(root,'reader-leases');
    lease=path.join(folder,randomUUID()+'.json');
    const at=new Date(timestamp(clock)).toISOString();
    try {
      await atomicJSON(lease,{version,pid:process.pid,startedAt:at});
      await usage(root,version,{lastReadAt:at});
    } catch(error) {await unlink(lease).catch(()=>{});throw error;}
    return {info,pointer,version,registerReader:async pid=>{
      if(!Number.isInteger(pid)||pid<1||pid>2_147_483_647) throw new Error('INVALID_READER_PID');
      // Prune must not probe a stale parent-only lease after the child is registered and SQL starts.
      await withCatalogLock(root,async()=>{
        const existing=await readJSON(lease);
        if(existing?.version!==version||existing?.pid!==process.pid||existing?.startedAt!==at) throw new Error('READER_LEASE_OWNERSHIP_CHANGED');
        if(existing.readerPID!==undefined&&existing.readerPID!==pid) throw new Error('READER_ALREADY_REGISTERED');
        await atomicJSON(lease,{...existing,readerPID:pid});
      });
    }};
  });
  try {return await operation(selected);}
  finally {if(lease) await unlink(lease);}
}

/** Caller holds refresh.lock; publication shares the short reader/prune critical section. */
export async function publishSnapshot(root,version,{clock=Date.now}={}) {
  if(!versionPattern.test(version)) throw new Error('INVALID_VERSION');
  return withCatalogLock(root,async()=>{
    await manifest(root,version);
    const previous=await current(root),publishedAt=new Date(timestamp(clock)).toISOString();
    await usage(root,version,{lastPublishedAt:publishedAt});
    const pointer={version,publishedAt,...(previous?.version&&previous.version!==version?{previousVersion:previous.version}:
      previous?.previousVersion?{previousVersion:previous.previousVersion}:{})};
    await atomicJSON(path.join(root,'current.json'),pointer);
    return pointer;
  });
}

/** Dry run by default. No automatic scheduler invokes retention. */
export async function pruneSnapshots({root,apply=false,keepVersions=3,minimumAgeDays=7,clock=Date.now}) {
  if(typeof root!=='string'||!root||path.resolve(root)===path.parse(path.resolve(root)).root) throw new Error('EXPLICIT_SERVICE_ROOT_REQUIRED');
  if(typeof apply!=='boolean'||!Number.isInteger(keepVersions)||keepVersions<2||keepVersions>100||
    !Number.isFinite(minimumAgeDays)||minimumAgeDays<1||minimumAgeDays>3650) throw new Error('INVALID_RETENTION_POLICY');
  const time=timestamp(clock),report={dryRun:!apply,at:new Date(time).toISOString(),keepVersions,minimumAgeDays,
    kept:[],eligible:[],retired:[],deleted:[],failures:[],deadLeases:[],unknownEntries:[]};
  return withLock(root,async()=>{
    const snapshots=await managedDirectory(root,'snapshots'),retired=await managedDirectory(root,'retired-snapshots');
    await withCatalogLock(root,async()=>{
      const pointer=await current(root);
      if(!pointer?.version||!versionPattern.test(pointer.version)) throw new Error('NO_VALID_CURRENT_DATASET');
      await manifest(root,pointer.version);
      if(pointer.previousVersion) {
        if(!versionPattern.test(pointer.previousVersion)) throw new Error('INVALID_ROLLBACK_POINTER');
        await manifest(root,pointer.previousVersion);
      }
      const leases=await managedDirectory(root,'reader-leases'),active=new Set();
      for(const entry of await readdir(leases,{withFileTypes:true})) {
        if(!leasePattern.test(entry.name)||!entry.isFile()||entry.isSymbolicLink()) throw new Error('INVALID_READER_LEASE');
        const file=path.join(leases,entry.name),lease=await readJSON(file);
        // Release can unlink concurrently after closing the reader; missing means complete.
        if(!lease) continue;
        if(!versionPattern.test(lease.version??'')||!Number.isInteger(lease.pid)||lease.pid<1||lease.pid>2_147_483_647) throw new Error('INVALID_READER_LEASE');
        if(lease.readerPID!==undefined&&(!Number.isInteger(lease.readerPID)||lease.readerPID<1||lease.readerPID>2_147_483_647)) throw new Error('INVALID_READER_LEASE');
        dateValue(lease.startedAt);
        const alive=[lease.pid,lease.readerPID].filter(pid=>pid!==undefined).some(pid=>{
          try {process.kill(pid,0);return true;}catch(error) {return error.code!=='ESRCH';}
        });
        if(alive) active.add(lease.version);
        else {report.deadLeases.push(entry.name);if(apply) await unlink(file).catch(error=>{if(error.code!=='ENOENT') throw error;});}
      }
      const all=[];
      for(const entry of await readdir(snapshots,{withFileTypes:true})) {
        if(!versionPattern.test(entry.name)) {report.unknownEntries.push(entry.name);continue;}
        if(!entry.isDirectory()||entry.isSymbolicLink()) throw new Error('UNSAFE_SNAPSHOT_DIRECTORY');
        const info=await manifest(root,entry.name);
        if(info.version!==entry.name) throw new Error('INVALID_RETENTION_METADATA');
        const imported=dateValue(info.importedAt),access=await readJSON(path.join(root,'snapshot-usage',entry.name+'.json'),{});
        if(access.version!==undefined&&access.version!==entry.name) throw new Error('INVALID_RETENTION_METADATA');
        const recent=Math.max(imported,...['lastReadAt','lastPublishedAt'].filter(k=>access[k]!==undefined).map(k=>dateValue(access[k])));
        all.push({version:entry.name,imported,recent});
      }
      all.sort((a,b)=>b.imported-a.imported||a.version.localeCompare(b.version));
      const protectedVersions=new Set([pointer.version,pointer.previousVersion,...all.slice(0,keepVersions).map(x=>x.version)].filter(Boolean));
      // Legacy current pointers have no explicit rollback; always retain at least one other snapshot.
      if(!pointer.previousVersion) {const other=all.find(x=>x.version!==pointer.version);if(other) protectedVersions.add(other.version);}
      for(const item of all) {
        const reason=protectedVersions.has(item.version)?'current/rollback/count':active.has(item.version)?'active reader':
          time-item.recent<minimumAgeDays*day?'recent import/publication/read':null;
        if(reason) {report.kept.push({version:item.version,reason});continue;}
        report.eligible.push(item.version);
        if(apply) {
          const destination=path.join(retired,item.version+'-'+randomUUID());
          const receipt=destination+'.json';
          // Persist provenance outside the directory so partial deletion can be retried safely.
          await atomicJSON(receipt,{version:item.version,directory:path.basename(destination),retiredAt:report.at});
          try {await rename(path.join(snapshots,item.version),destination);report.retired.push(path.basename(destination));}
          catch(error) {await unlink(receipt);report.failures.push({version:item.version,phase:'retire',code:error.code});}
        }
      }
    });
    // New readers cannot see atomically retired directories. Failure leaves quarantine for retry.
    if(apply) for(const entry of await readdir(retired,{withFileTypes:true})) {
      if(entry.isFile()&&retiredPattern.test(entry.name.replace(/\.json$/,''))&&entry.name.endsWith('.json')) continue;
      if(!retiredPattern.test(entry.name)||!entry.isDirectory()||entry.isSymbolicLink()) {
        report.unknownEntries.push('retired/'+entry.name);continue;
      }
      const target=childPath(retired,entry.name);
      const receiptFile=target+'.json',receiptInfo=await lstat(receiptFile).catch(error=>{if(error.code==='ENOENT') return null;throw error;});
      if(!receiptInfo?.isFile()||receiptInfo.isSymbolicLink()) {report.unknownEntries.push('unverified retired/'+entry.name);continue;}
      const receipt=await readJSON(receiptFile);
      if(receipt?.directory!==entry.name||receipt?.version!==entry.name.slice(0,64)||!Number.isFinite(Date.parse(receipt?.retiredAt))) {
        report.unknownEntries.push('unverified retired/'+entry.name);continue;
      }
      try {await rm(target,{recursive:true,force:true});await unlink(receiptFile);report.deleted.push(entry.name);}
      catch(error) {report.failures.push({version:entry.name.slice(0,64),phase:'delete retired',code:error.code});}
    }
    return report;
  });
}
