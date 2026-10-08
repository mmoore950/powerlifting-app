import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import assert from 'node:assert/strict';
import {dataset} from '../src/query.mjs';
import {withSnapshot} from '../src/snapshot-lifecycle.mjs';
import {rankingsPlan} from '../src/rankings-plan.mjs';
import {QueryPool} from '../src/query-pool.mjs';
import {atomicJSON} from '../src/storage.mjs';

const options={},args=process.argv.slice(2);
for(let i=0;i<args.length;i+=2) {
  if(!['--root','--output'].includes(args[i])||args[i+1]===undefined) throw new Error('Use --root existing-service-root [--output report.json]');
  options[args[i].slice(2)]=args[i+1];
}
if(!options.root) throw new Error('Existing explicit --root required; no import/index/prune performed');
const root=path.resolve(options.root),output=path.resolve(options.output??fileURLToPath(new URL('../../artifacts/ranking-plan-profile.json',import.meta.url)));
const metadata=await dataset(root),version=metadata.dataset?.version;
if(!version) throw new Error('Existing dataset required');
const params={sex:'F',equipment:'Raw',event:'SBD',tested:'yes',federation:'IPF',from:'2020-01-01',metric:'total',limit:25,version};
const report={kind:'bounded read-only existing-snapshot ranking proposal',startedAt:new Date().toISOString(),root,version,
  rows:metadata.dataset.rows,params,upstreamRequests:0,imports:0,prunes:0,indexChanges:0,cases:[],events:[],
  policy:{maxSerialQueries:3,maxWorkers:1,queryTimeoutMs:10_000,cancellationAfterMs:60_000},
  cacheControl:'Uncontrolled OS/filesystem cache. Snapshot already queried earlier today; wide first then narrow twice. No cache flush or cold-cache claim.',
  limits:'Timer/OS/filesystem cleanup can overrun. Child process peak reported before final IPC, not exit/fleet peak. Single fixed filter/host; no throughput or production SLA.'};
const controller=new AbortController(),budget=setTimeout(()=>controller.abort(),60_000),began=performance.now();
const pools=[];
try {
  report.plans=await withSnapshot(root,version,({version})=>{
    const db=new DatabaseSync(path.join(root,'snapshots',version,'data.sqlite'),{readOnly:true});
    try {
      db.exec('PRAGMA temp_store=FILE; PRAGMA cache_size=-32768;');
      return {sqliteVersion:db.prepare('select sqlite_version() version').get().version,
        existingIndexes:db.prepare("select name,sql from sqlite_master where type='index' and tbl_name='results'").all(),
        wide:db.prepare('EXPLAIN QUERY PLAN '+rankingsPlan(params,26,0).sql).all(...rankingsPlan(params,26,0).args),
        narrow:db.prepare('EXPLAIN QUERY PLAN '+rankingsPlan(params,26,0,{narrow:true}).sql).all(...rankingsPlan(params,26,0,{narrow:true}).args)};
    } finally {db.close();}
  });
  let baseline;
  for(const [label,narrow] of [['wide baseline',false],['narrow projection first',true],['narrow projection repeat',true]]) {
    const events=[];
    const pool=new QueryPool({root,maxWorkers:1,maxQueue:0,queryTimeoutMs:10_000,
      ...(narrow?{workerURL:new URL('./profile-ranking-child.mjs',import.meta.url)}:{}),onEvent:event=>events.push(event)});
    pools.push(pool);const start=performance.now();
    try {
      const result=await pool.run('rankings',params,{signal:controller.signal});
      const {durationMs,...payload}=result;
      if(baseline) assert.deepEqual(payload,baseline);else baseline=payload;
      report.cases.push({label,latencyMs:performance.now()-start,sqlDurationMs:durationMs,resultRows:result.results.length,
        jsonBytes:Buffer.byteLength(JSON.stringify(result)),samePayload:true,metrics:events.find(event=>event.type==='result')?.metrics});
    } catch(error) {
      report.cases.push({label,latencyMs:performance.now()-start,error:error.message});throw error;
    } finally {await pool.close();report.events.push({label,events});}
  }
  report.success=true;
} catch(error) {report.success=false;report.error=error.message;process.exitCode=1;}
finally {
  clearTimeout(budget);await Promise.all(pools.map(pool=>pool.close()));
  report.finishedAt=new Date().toISOString();report.elapsedMs=performance.now()-began;
  report.poolsAfterClose=pools.map(pool=>pool.stats);await atomicJSON(output,report);
}
console.log(JSON.stringify({output,success:report.success,error:report.error,elapsedMs:report.elapsedMs,cases:report.cases},null,2));
