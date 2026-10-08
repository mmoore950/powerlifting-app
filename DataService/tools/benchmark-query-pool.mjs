import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {QueryPool} from '../src/query-pool.mjs';
import {dataset} from '../src/query.mjs';
import {atomicJSON} from '../src/storage.mjs';

const args=process.argv.slice(2),options={};
for(let index=0;index<args.length;index+=2) {
  if(!['--root','--output'].includes(args[index])||args[index+1]===undefined) throw new Error('Use explicit --root path and optional --output report.json');
  options[args[index].slice(2)]=args[index+1];
}
if(!options.root) throw new Error('An existing explicit service --root is required; this tool never imports or prunes');
const root=path.resolve(options.root),project=fileURLToPath(new URL('../../',import.meta.url));
const output=path.resolve(options.output??path.join(project,'artifacts','query-isolation-benchmark.json'));
const metadata=await dataset(root);
if(!metadata.dataset) throw new Error('Existing dataset required');
const events=[],measurements=[],version=metadata.dataset.version;
const pool=new QueryPool({root,onEvent:event=>events.push({...event,at:new Date().toISOString()})});
const controller=new AbortController(),budget=setTimeout(()=>controller.abort(),60_000);
const began=performance.now(),report={kind:'existing local snapshot query worker measurement',startedAt:new Date().toISOString(),
  root,version,sourceDate:metadata.sourceDate,rows:metadata.dataset.rows,lifters:metadata.dataset.lifters,
  policy:{maxWorkers:2,maxQueue:8,queueTimeoutMs:5000,queryTimeoutMs:10_000,toolCancellationAfterMs:60_000},
  cases:measurements,events,upstreamRequests:0,imports:0,prunes:0,
  limits:'Tool cancellation/OS/lease filesystem cleanup may overrun timers. Child peak RSS is reported before final IPC send, not an exact exit-time or fleet peak. Cache state/host/query distribution limit extrapolation.'};
async function run(label,kind,params) {
  const start=performance.now();
  const result=await pool.run(kind,{...params,version},{signal:controller.signal});
  if(result.version!==version) throw new Error('Benchmark version changed');
  measurements.push({label,kind,latencyMs:performance.now()-start,sqlDurationMs:result.durationMs,
    resultRows:result.results.length,jsonBytes:Buffer.byteLength(JSON.stringify(result)),hasNextPage:Boolean(result.nextCursor)});
  return result;
}
try {
  const search=await run('exact-name prefix search','search',{q:'taylor atwood',limit:25});
  const person=search.results.find(row=>row.Name==='Taylor Atwood');
  if(!person) throw new Error('Expected existing public lifter not found; this fixed benchmark needs a suitable OpenPowerlifting snapshot');
  const filters={sex:'F',equipment:'Raw',event:'SBD',tested:'yes',federation:'IPF',from:'2020-01-01',metric:'total',limit:25};
  const concurrent=[
    run('history concurrent with rankings','history',{id:person.lifterId,limit:25}),
    run('filtered best totals concurrent with history','rankings',filters)];
  const combined=Promise.all(concurrent);
  // Metadata failure/cancellation must not leave rejected query promises unobserved.
  void combined.catch(()=>{});
  // Observe filesystem metadata while both requests are admitted; record actual pool state at both ends.
  const metadataStart=performance.now(),atStart=pool.stats;
  const observed=await dataset(root);
  if(observed.dataset?.version!==version) throw new Error('Metadata changed during benchmark');
  report.metadataProbe={latencyMs:performance.now()-metadataStart,version,atStart,atFinish:pool.stats};
  const [history,rankings]=await combined;
  if(!history.results.length||!rankings.results.length) throw new Error('Benchmark queries returned no observations');
  if(rankings.nextCursor) await run('version-bound ranking continuation','rankings',{...filters,cursor:rankings.nextCursor});
  await run('repeated prefix search','search',{q:'taylor atwood',limit:25});
  report.success=true;
} catch(error) {report.success=false;report.error=error.message;process.exitCode=1;}
finally {
  clearTimeout(budget);await pool.close();
  report.finishedAt=new Date().toISOString();report.elapsedMs=performance.now()-began;
  report.parentRSSBytes=process.memoryUsage().rss;report.parentPeakRSSBytes=process.resourceUsage().maxRSS*1024;
  report.poolAfterClose=pool.stats;await atomicJSON(output,report);
}
console.log(JSON.stringify({output,success:report.success,elapsedMs:report.elapsedMs,version,cases:measurements,childPeaks:events.filter(event=>event.type==='result').map(event=>event.metrics.peakRSSBytes)},null,2));
