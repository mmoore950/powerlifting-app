import assert from 'node:assert/strict';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {once} from 'node:events';
import {mkdir,writeFile} from 'node:fs/promises';
import {serve} from '../src/server.mjs';
const project=fileURLToPath(new URL('../../',import.meta.url));
const root=path.resolve(process.argv[2]??path.join(project,'artifacts','opl-service'));
const server=serve({root,port:0});await once(server,'listening');
const base=`http://127.0.0.1:${server.address().port}`;
try {
  const get=async(route)=>{
    const start=performance.now(),response=await fetch(base+route);assert.equal(response.status,200);
    return {httpMs:performance.now()-start,body:await response.json()};
  };
  const data=await get('/dataset');assert(data.body.dataset.rows>4_000_000);
  const search=await get('/lifters?q=Taylor%20Atwood&limit=3');assert(search.body.results.length);
  const history=await get(`/lifters/${search.body.results[0].lifterId}/results?limit=3&version=${search.body.version}`);assert(history.body.results.length);
  const rank=await get(`/rankings?sex=F&equipment=Raw&event=SBD&tested=yes&federation=IPF&from=2020-01-01&limit=3&version=${search.body.version}`);assert(rank.body.results.length===3);
  for(const response of [search,history,rank]) assert.equal(response.body.version,data.body.dataset.version);
  const second=await get(`/rankings?sex=F&equipment=Raw&event=SBD&tested=yes&federation=IPF&from=2020-01-01&limit=3&cursor=${encodeURIComponent(rank.body.nextCursor)}`);
  assert.equal(second.body.version,rank.body.version);
  assert(!second.body.results.some(row=>rank.body.results.some(first=>row.Name===first.Name)));
  const evidence={checkedAt:new Date().toISOString(),data,search,history,rank,secondPage:second};
  await mkdir(path.join(project,'artifacts'),{recursive:true});
  await writeFile(path.join(project,'artifacts','opl-query-evidence.json'),JSON.stringify(evidence,null,2));
  console.log(JSON.stringify({version:search.body.version,rows:data.body.dataset.rows,lifters:data.body.dataset.lifters,
    sourceDate:data.body.sourceDate,checkStale:data.body.checkStale,sourceStale:data.body.sourceStale,
    search:search.body.results,history:history.body.results.map(r=>({Name:r.Name,Date:r.Date,MeetName:r.MeetName,TotalKg:r.TotalKg})),
    rankings:rank.body.results.map(r=>({Name:r.Name,Date:r.Date,TotalKg:r.TotalKg})),
    timingsMs:{search:search.httpMs,history:history.httpMs,rankings:rank.httpMs},saved:'artifacts/opl-query-evidence.json'},null,2));
} finally {await new Promise(resolve=>server.close(resolve));}
