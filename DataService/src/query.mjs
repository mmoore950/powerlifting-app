import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {readJSON,now} from './storage.mjs';
import {kgColumns,normalize} from './schema.mjs';
import {withSnapshot} from './snapshot-lifecycle.mjs';
import {rankingsPlan,performanceMetrics} from './rankings-plan.mjs';

const id=name=>Buffer.from(name,'utf8').toString('base64url');
const exactName=value=>{
  if(!value||value.length>6000||!/^[a-zA-Z0-9_-]+$/.test(value)) throw new Error('INVALID_LIFTER_ID');
  const name=Buffer.from(value,'base64url').toString('utf8');
  if(id(name)!==value) throw new Error('INVALID_LIFTER_ID');
  return name;
};
function record(row) {
  const out={...row,lifterId:id(row.Name)};
  for(const key of kgColumns) if(key in out&&out[key]!==null) out[key]/=100;
  if(out.extras) {out.extraFields=JSON.parse(out.extras);delete out.extras;}
  return out;
}
export async function dataset(root) {
  return withSnapshot(root,null,async({info,pointer})=>{
  const status=await readJSON(path.join(root,'status.json'),{});
  const lastCheck=status.lastSuccessfulCheckAt??null;
  const statusVersion=status.validatedVersion??status.lastPublishedVersion??null;
  const statusMatchesDataset=Boolean(info&&statusVersion===info.version);
  const acceptedSource=statusMatchesDataset?(status.validatedUpstream??info.source):info?.source;
  const sourceDate=acceptedSource?.archiveDate??info?.csvEntry?.match(/openpowerlifting-(\d{4}-\d{2}-\d{2})/)?.[1]??acceptedSource?.landingDate??null;
  const sourceAgeDays=sourceDate?(Date.now()-Date.parse(sourceDate))/86400_000:null;
  return {dataset:info,publishedAt:pointer?.publishedAt??null,status,latestValidatedSource:acceptedSource??null,
    statusMatchesDataset,validation:info?{version:info.version,validatedAt:statusMatchesDataset?(status.lastSuccessfulImportAt??info.importedAt):info.importedAt}:null,
    checkedAt:now(),checkStale:!lastCheck||Date.now()-Date.parse(lastCheck)>24*3600*1000,
    sourceDate,sourceAgeDays,sourceStale:sourceAgeDays===null||sourceAgeDays>2,
    attribution:'Data from OpenPowerlifting, public domain. Best performances in this dataset; not necessarily ratified records.'};
  },{allowEmpty:true});
}
export function prepareQuery(kind,params={}) {
  const allowed={search:['q','limit','cursor','version'],history:['id','limit','cursor','version'],
    rankings:['sex','equipment','event','tested','federation','from','to','bodyweightMin','bodyweightMax','weightClass','metric','limit','cursor','version']};
  allowed.summary=['id',...allowed.rankings.filter(key=>!['metric','cursor'].includes(key))];
  if(!allowed[kind]) throw new Error('UNKNOWN_QUERY');
  for(const key of Object.keys(params)) if(!allowed[kind].includes(key)) throw new Error(`UNSUPPORTED_FILTER: ${key}`);
  const limit=Number(params.limit??25);
  if(!Number.isInteger(limit)||limit<1||limit>100) throw new Error('INVALID_LIMIT');
  let cursor;
  if(params.cursor) {
    if(params.cursor.length>2048) throw new Error('INVALID_CURSOR');
    try {cursor=JSON.parse(Buffer.from(params.cursor,'base64url').toString('utf8'));}catch{throw new Error('INVALID_CURSOR');}
    if(!cursor||typeof cursor!=='object'||Array.isArray(cursor)||cursor.kind!==kind||
      typeof cursor.version!=='string'||!/^[a-f0-9]{64}$/.test(cursor.version)||
      typeof cursor.signature!=='string'||!/^[a-f0-9]{64}$/.test(cursor.signature)||
      !Number.isInteger(cursor.offset)||cursor.offset<0||cursor.offset>1_000_000) throw new Error('INVALID_CURSOR');
    if(params.version&&params.version!==cursor.version) throw new Error('CURSOR_VERSION_MISMATCH');
  }
  const signature=createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries({...params,limit}).filter(([key])=>!['cursor','version'].includes(key)).sort(([a],[b])=>a.localeCompare(b))))).digest('hex');
  if(cursor&&cursor.signature!==signature) throw new Error('CURSOR_FILTER_MISMATCH');
  const offset=cursor?.offset??0;
  return {kind,params:{...params},limit,signature,offset,requestedVersion:params.version??cursor?.version};
}
export async function query(root,kind,params={}) {
  const prepared=prepareQuery(kind,params);
  return withSnapshot(root,prepared.requestedVersion,selected=>executeQuery(root,prepared,selected));
}
/** Internal read-only execution against an already leased immutable version. */
export function executeQuery(root,{kind,params,limit,signature,offset},{info,version},{narrowRankings=false}={}) {
  const db=new DatabaseSync(path.join(root,'snapshots',version,'data.sqlite'),{readOnly:true,timeout:5000});
  const started=performance.now();
  try {
    db.exec('PRAGMA temp_store=FILE; PRAGMA cache_size=-32768;');
    let rows;
    if(kind==='search') {
      const q=normalize(String(params.q??'').trim());
      if(q.length<2||q.length>128) throw new Error('SEARCH_REQUIRES_2_TO_128_CHARACTERS');
      // Literal normalized prefix search; no wildcard expansion or suffix stripping.
      rows=db.prepare('SELECT Name FROM lifters WHERE normalized >= ? AND normalized < ? ORDER BY normalized,Name LIMIT ? OFFSET ?')
        .all(q,q+'\u{10FFFF}',limit+1,offset).map(row=>({Name:row.Name,lifterId:id(row.Name)}));
    } else if(kind==='history') {
      const name=exactName(params.id);
      rows=db.prepare('SELECT * FROM results WHERE Name=? ORDER BY Date DESC,row_id DESC LIMIT ? OFFSET ?')
        .all(name,limit+1,offset).map(record);
    } else if(kind==='summary') {
      const name=exactName(params.id);
      const bests=[];
      for(const metric of Object.keys(performanceMetrics)) {
        const plan=rankingsPlan({...params,metric},1,0);
        const winner=db.prepare(`SELECT * FROM results WHERE Name=? AND ${plan.where} ORDER BY \"${plan.metric}\" DESC,Date DESC,row_id DESC LIMIT 1`).get(name,...plan.args.slice(0,-2));
        if(winner) bests.push({metric,result:record(winner)});
      }
      rows=db.prepare('SELECT Name FROM lifters WHERE Name=?').get(name)?[{Name:name,lifterId:id(name),bests,scope:Object.fromEntries(Object.entries(params).filter(([key])=>!['id','version','limit'].includes(key)))}]:[];
    } else {
      const plan=rankingsPlan(params,limit+1,offset,{narrow:narrowRankings});
      rows=db.prepare(plan.sql).all(...plan.args).map(row=>{delete row.person_rank;return record(row);});
    }
    const more=rows.length>limit; const results=rows.slice(0,limit);
    const nextCursor=more?Buffer.from(JSON.stringify({version,kind,signature,offset:offset+limit})).toString('base64url'):null;
    return {version,source:info.source,results,nextCursor,durationMs:performance.now()-started,
      ...(['rankings','summary'].includes(kind)?{label:'Best performance per source lifter name in this filtered dataset; not ratified records.'}:{})};
  } finally {db.close();}
}
