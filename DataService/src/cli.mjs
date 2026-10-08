import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {importSnapshot} from './import.mjs';
import {refresh} from './refresh.mjs';
import {query,dataset} from './query.mjs';
import {serve} from './server.mjs';
import {readJSON,atomicJSON,now} from './storage.mjs';
import {unlink} from 'node:fs/promises';
import {pruneSnapshots,recoverCatalogLock} from './snapshot-lifecycle.mjs';

const [command,...args]=process.argv.slice(2);
const options={};for(let i=0;i<args.length;i+=2){if(!args[i].startsWith('--')||args[i+1]===undefined) throw new Error('Use --key value');options[args[i].slice(2)]=args[i+1];}
const project=fileURLToPath(new URL('../../',import.meta.url));
const root=path.resolve(options.root??path.join(project,'artifacts','opl-service'));
const progress=message=>console.error(JSON.stringify({at:new Date().toISOString(),...message}));
try {
  let result;
  if(command==='import') {
    if(!options.file) throw new Error('--file is required');
    result=await importSnapshot({root,file:path.resolve(options.file),minimumRows:Number(options.minimumRows??1),
      source:{kind:'explicit local import',revision:options.revision??'unverified',landingDate:options.sourceDate??null},onProgress:progress});
  } else if(command==='refresh') {
    result=await refresh({root,seedFile:options.seed??path.join(project,'artifacts','openpowerlifting-latest.zip'),
      seedMetadata:options.seedMetadata??path.join(project,'artifacts','opl-inspection.json'),force:options.force==='true',dueOnly:options.due==='true',onProgress:progress});
  } else if(command==='recover-lock') {
    const pid=Number(options.pid);const file=path.join(root,'refresh.lock');const lock=await readJSON(file);
    if(!Number.isInteger(pid)||pid<1||lock?.pid!==pid) throw new Error('Lock PID must exactly match --pid');
    try {process.kill(pid,0);throw new Error('Lock owner is still alive; refusing recovery');}
    catch(error){if(error.code!=='ESRCH') throw error;}
    await unlink(file);
    const status=await readJSON(path.join(root,'status.json'),{});
    await atomicJSON(path.join(root,'status.json'),{...status,running:false,lastFailureAt:now(),lastError:'Refresh owner exited or was terminated; lock explicitly recovered',failureCount:(status.failureCount??0)+1,retryAt:new Date(Date.now()+15*60*1000).toISOString()});
    result={recovered:true,pid};
  } else if(command==='dataset') result=await dataset(root);
  else if(command==='recover-catalog-lock') {
    if(!options.root) throw new Error('Catalog recovery requires explicit --root');
    result=await recoverCatalogLock(root,Number(options.pid));
  }
  else if(command==='prune') {
    if(!options.root) throw new Error('prune requires an explicit --root; dry run unless --apply true');
    if(options.apply!==undefined&&!['true','false'].includes(options.apply)) throw new Error('--apply must be true or false');
    result=await pruneSnapshots({root,apply:options.apply==='true',keepVersions:Number(options.keep??3),minimumAgeDays:Number(options.days??7)});
  }
  else if(command==='query') {
    const params={...options};delete params.root;delete params.kind;
    result=await query(root,options.kind??'search',params);
  } else if(command==='serve') {
    const port=Number(options.port??8787);if(!Number.isInteger(port)||port<1024||port>65535) throw new Error('Invalid port');
    serve({root,port});console.log(JSON.stringify({listening:`http://127.0.0.1:${port}`,root}));
  } else throw new Error('Commands: import, refresh, dataset, query, serve, prune, recover-lock, recover-catalog-lock');
  if(result) console.log(JSON.stringify(result,null,2));
} catch(error){console.error(JSON.stringify({error:error.message}));process.exitCode=1;}
