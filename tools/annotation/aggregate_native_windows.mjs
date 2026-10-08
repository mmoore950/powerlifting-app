import {open,lstat,realpath,mkdir,writeFile,rename,rm} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {adaptLabels,digest,parseStrictJSON,validateLedger,verifyNativePrediction,verifyRasterAssets} from './adapt_labels.mjs';
import {timestampKey,validateVideoManifest} from '../validate-video-manifest.mjs';
import {scoreVideoTraces,verifyMedia} from '../score-video-traces.mjs';

const MiB=1024*1024;
const limits={windows:64,rawFrames:1024,jsonBytes:32*MiB,mediaBytes:4*1024**3,outputBytes:8*MiB,
  perFileMs:60_000,cooperativeMs:300_000,repSeconds:30,partitionAssignments:4096};
const require=(ok,message)=>{if(!ok)throw Error(message);};
const object=x=>x&&typeof x==='object'&&!Array.isArray(x);
const keys=(x,required,optional=[],label='object')=>require(object(x)&&required.every(k=>Object.hasOwn(x,k))&&Object.keys(x).every(k=>[...required,...optional].includes(k)),`Unexpected ${label} fields`);
const canonical=x=>JSON.stringify(object(x)?Object.fromEntries(Object.keys(x).sort().map(k=>[k,JSON.parse(canonical(x[k]))])):Array.isArray(x)?x.map(v=>JSON.parse(canonical(v))):x);
const equal=(a,b)=>canonical(a)===canonical(b);
const json=x=>Buffer.from(JSON.stringify(x,null,2)+'\n');
const identifier=x=>typeof x==='string'&&/^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/.test(x);
function rational(n,d=1n) {
  let a=n<0n?-n:n,b=d;while(b){[a,b]=[b,a%b];}return {n:n/a,d:d/a};
}
const cmp=(a,b)=>a.n*b.d<b.n*a.d?-1:a.n*b.d>b.n*a.d?1:0;
const plus=(a,b)=>rational(a.n*b.d+b.n*a.d,a.d*b.d);
const minus=(a,b)=>rational(a.n*b.d-b.n*a.d,a.d*b.d);
const encoded=x=>({numerator:String(x.n),denominator:String(x.d)});
function time(t) {
  keys(t,['value','timescale','epoch'],[],'boundary timestamp');timestampKey(t);
  require(t.epoch===0&&BigInt(t.value)>=0n,'Only nonnegative epoch-zero intervals supported');
  return rational(BigInt(t.value),BigInt(t.timescale));
}
function interval(x) {
  keys(x,['start','end'],[],'interval');const start=time(x.start),end=time(x.end);
  require(cmp(start,end)<0&&cmp(end,rational(1800n))<=0,'Invalid positive interval');return {start,end};
}
// Exact decimal representation of the serialized requested Double. It does not
// reconstruct exact decoder boundaries; actual samples use original CMTime only.
function requested(value) {
  const [mantissa,exponent='0']=String(value).split('e'),[whole,fraction='']=mantissa.split('.');
  const shift=Number(exponent)-fraction.length,n=BigInt(whole+fraction);
  return shift>=0?rational(n*10n**BigInt(shift)):rational(n,10n**BigInt(-shift));
}
const withinInterval=(t,r)=>cmp(t,r.start)>=0&&cmp(t,r.end)<=0;
const local=x=>typeof x==='string'&&x.length>0&&!x.includes('\0')&&!/^(?:[a-z][a-z0-9+.-]*:\/\/|file:)/i.test(x);
async function absent(filename) {
  try {await lstat(filename);throw Error('Aggregation destination already exists');}
  catch(e){if(e.code!=='ENOENT')throw e;}
}

const partitionKinds=['recording-sha256','source-group','recording-group','session-group','subject-group'];
const groupKinds={recordingGroupID:'recording-group',sessionGroupID:'session-group',subjectGroupID:'subject-group'};
function partitionMap(evidence) {
  keys(evidence,['schemaVersion','assignments'],[],'cumulative partition constraints');
  require(evidence.schemaVersion===1&&Array.isArray(evidence.assignments)&&evidence.assignments.length<=limits.partitionAssignments,'Invalid/bounded cumulative partition history');
  const result=new Map();
  for(const row of evidence.assignments) {
    keys(row,['kind','id','split'],[],'partition assignment');
    require(partitionKinds.includes(row.kind)&&typeof row.id==='string'&&row.id.length>0&&!row.id.includes('\0')&&['training','development','holdout'].includes(row.split),'Invalid partition assignment');
    if(row.kind==='recording-sha256')require(/^[a-f0-9]{64}$/.test(row.id),'Invalid partition recording hash');
    else if(row.kind!=='source-group')require(identifier(row.id),'Invalid anonymous partition group');
    const key=canonical([row.kind,row.id]);require(!result.has(key),'Duplicate cumulative partition assignment');result.set(key,row);
  }
  return result;
}
function assignPartition(map,kind,id,split,{mustExist=false}={}) {
  const key=canonical([kind,id]),prior=map.get(key);
  require(!mustExist||prior,'Previous registry is missing its own cumulative partition assignment');
  require(!prior||prior.split===split,'Cumulative recording/group leaked across partitions');
  if(!prior){require(map.size<limits.partitionAssignments,'Cumulative partition assignment bound4096 exceeded');map.set(key,{kind,id,split});}
}

function validatePlan(plan) {
  keys(plan,['schemaVersion','kind','repID','recordingSHA256','interval','windows'],['groups','expectedOverlaps'],'plan');
  require(plan.schemaVersion===1&&plan.kind==='native-window-plan'&&identifier(plan.repID)&&/^[a-f0-9]{64}$/.test(plan.recordingSHA256),'Invalid plan identity');
  const rep=interval(plan.interval);require(cmp(minus(rep.end,rep.start),rational(30n))<=0,'Rep exceeds30s bound');
  require(Array.isArray(plan.windows)&&plan.windows.length>0&&plan.windows.length<=limits.windows,'Window count exceeds64 bound');
  const ids=new Set();
  for(const w of plan.windows) {
    keys(w,['id','ledger','labels','assetRoot','evaluation'],[],'window');
    require(identifier(w.id)&&!ids.has(w.id)&&[w.ledger,w.labels,w.assetRoot,w.evaluation].every(local),'Duplicate window ID or invalid explicit path');ids.add(w.id);
  }
  const groups={recordingGroupID:null,sessionGroupID:null,subjectGroupID:null,reviewStatus:'unknown',permissionEvidence:null,...plan.groups};
  if(plan.groups!==undefined)keys(plan.groups,[],['recordingGroupID','sessionGroupID','subjectGroupID','reviewStatus','permissionEvidence'],'groups');
  require(['unknown','reviewed'].includes(groups.reviewStatus)&&['recordingGroupID','sessionGroupID','subjectGroupID'].every(k=>groups[k]===null||identifier(groups[k])),'Invalid anonymous group/review metadata');
  require(groups.permissionEvidence===null||(typeof groups.permissionEvidence==='string'&&groups.permissionEvidence.trim().length>0&&groups.permissionEvidence.length<=4096),'Invalid explicit research permission evidence');
  const expected=plan.expectedOverlaps??[];require(Array.isArray(expected)&&expected.length<=2016,'Expected overlap bound exceeded');
  const pairs=new Set();
  for(const overlap of expected) {
    keys(overlap,['windows','interval'],[],'expected overlap');
    require(Array.isArray(overlap.windows)&&overlap.windows.length===2&&overlap.windows.every(w=>ids.has(w))&&overlap.windows[0]!==overlap.windows[1],'Expected overlap needs two named windows');
    const r=interval(overlap.interval),pair=canonical(overlap.windows.toSorted());
    require(!pairs.has(pair)&&cmp(r.start,rep.start)>=0&&cmp(r.end,rep.end)<=0,'Duplicate/outside-rep expected overlap');pairs.add(pair);
  }
  return {rep,groups,expected};
}

/** Explicit local derived reports. Never pool scalar scores or select a conflict winner. */
export async function aggregateNativeWindows({planFile,output,existingFile,previousReceiptFile,signal,onPhase}) {
  require([planFile,output,...(existingFile?[existingFile]:[]),...(previousReceiptFile?[previousReceiptFile]:[])].every(local),'Explicit local plan/output paths required');
  require(onPhase===undefined||typeof onPhase==='function','Invalid phase observer');
  const started=performance.now();
  const check=()=>{require(!signal?.aborted,'Aggregation cancelled');require(performance.now()-started<limits.cooperativeMs,'Aggregation exceeded cooperative300s budget');};
  const requestedOutput=path.resolve(output),parent=await realpath(path.dirname(requestedOutput));
  const destination=path.join(parent,path.basename(requestedOutput));await absent(destination);
  const snapshots=new Map(),assets=new Map(),media=new Map();let jsonBytes=0,mediaBytes=0,mediaReadBytes=0,rawFrames=0;
  async function read(filename,bound) {
    check();const absolute=path.resolve(filename),s=await lstat(absolute);
    require(!s.isSymbolicLink()&&s.isFile()&&s.size>0&&s.size<=bound,'Input must be a nonempty regular non-symlink file within bound');
    const resolved=await realpath(absolute),prior=snapshots.get(resolved);
    if(prior){require(prior.bytes.length<=bound,'Cached input exceeds file bound');return prior.bytes;}
    require(jsonBytes+s.size<=limits.jsonBytes,'Selected JSON exceeds32MiB bound');
    const bytes=await readFileBounded(resolved,bound,check,signal);
    jsonBytes+=bytes.length;snapshots.set(resolved,{bytes,sha256:digest(bytes),bound});return bytes;
  }
  async function named(root,name) {
    const base=await realpath(root),filename=path.resolve(base,name),resolved=await realpath(filename),relative=path.relative(base,resolved);
    require(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep),'Named file escapes explicit root');
    require(!(await lstat(filename)).isSymbolicLink(),'Named symlink file refused');return resolved;
  }
  async function source(ledger,root) {
    const filename=await named(root,ledger.clip.localPath),prior=media.get(filename);
    if(prior){require(prior.ledger.clip.sha256===ledger.clip.sha256,'One physical source has conflicting recording hashes');return filename;}
    const size=(await lstat(filename)).size;
    require(2*(mediaBytes+size)<=limits.mediaBytes,'Initial plus final distinct physical media reads exceed4GiB bound');
    check();const verified=await verifyMedia({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[{...ledger.clip,annotations:[]}]},root,{fileLimit:500*MiB,totalLimit:500*MiB});check();
    mediaBytes+=verified.totalBytes;mediaReadBytes+=verified.totalBytes;
    media.set(filename,{ledger,root,bytes:verified.totalBytes});return filename;
  }
  const planBytes=await read(planFile,MiB),plan=parseStrictJSON(planBytes.toString('utf8'));
  const {rep,groups,expected}=validatePlan(plan),base=path.dirname(path.resolve(planFile));
  const resolve=x=>path.resolve(base,x),windows=[],unique=[],identities=new Map();
  const existingBytes=existingFile?await read(existingFile,32*MiB):null;
  const existing=existingBytes?parseStrictJSON(existingBytes.toString('utf8')):{schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[]};
  validateVideoManifest(existing);
  let previous=null;const constraints=new Map();
  if(previousReceiptFile) {
    const bytes=await read(previousReceiptFile,8*MiB),prior=parseStrictJSON(bytes.toString('utf8'));
    require(prior.schemaVersion===1&&prior.kind==='native-window-aggregation'&&prior.complete===true&&prior.accuracyGatePassed===false,'Previous aggregation receipt is incomplete/foreign');
    keys(prior.files,['registry.json','aggregation.json'],[],'previous aggregation files');
    const artifacts={};
    for(const name of Object.keys(prior.files)) {
      keys(prior.files[name],['sha256','bytes'],[],'previous file descriptor');
      const data=await read(await named(path.dirname(path.resolve(previousReceiptFile)),name),8*MiB);
      require(prior.files[name].sha256===digest(data)&&prior.files[name].bytes===data.length,'Previous aggregation bytes changed');
      artifacts[name]=parseStrictJSON(data.toString('utf8'));
    }
    const registry=artifacts['registry.json'];
    require(registry.schemaVersion===1&&registry.kind==='native-window-registry'&&registry.recordingSHA256===prior.recordingSHA256&&registry.repID===prior.repID&&object(registry.groups)&&['training','development','holdout'].includes(registry.split),'Previous registry identity changed');
    require(artifacts['aggregation.json'].accuracyGatePassed===false&&artifacts['aggregation.json'].scalarMetrics===null,'Previous aggregation contains unsupported pooled metrics');
    require(registry.partitionConstraints!==undefined,'Previous registry lacks transitive partition evidence; chaining this prior format is refused');
    const inherited=partitionMap(registry.partitionConstraints);
    assignPartition(inherited,'recording-sha256',registry.recordingSHA256,registry.split,{mustExist:true});
    for(const [key,kind] of Object.entries(groupKinds))if(registry.groups[key]!==null)assignPartition(inherited,kind,registry.groups[key],registry.split,{mustExist:true});
    require(Array.isArray(registry.windows)&&registry.windows.length>0&&registry.windows.length<=limits.windows,'Invalid previous window count');
    for(const w of registry.windows) {
      require(object(w.clip)&&w.clip.sha256===registry.recordingSHA256&&w.clip.split===registry.split&&typeof w.clip.sourceGroup==='string','Previous window partition identity changed');
      assignPartition(inherited,'source-group',w.clip.sourceGroup,w.clip.split,{mustExist:true});
    }
    for(const [key,row] of inherited)constraints.set(key,row);
    previous={receiptSHA256:digest(bytes),receiptPath:await realpath(previousReceiptFile),registry};
  }
  for(const input of plan.windows) {
    check();const ledgerPath=resolve(input.ledger),labelsPath=resolve(input.labels),evaluationPath=resolve(input.evaluation),assetRoot=resolve(input.assetRoot);
    const ledgerBytes=await read(ledgerPath,MiB),ledger=validateLedger(parseStrictJSON(ledgerBytes.toString('utf8')));
    require(ledger.purpose==='native-analysis','Aggregate refuses development producers');
    require(ledger.clip.sha256===plan.recordingSHA256,'Window belongs to another recording');
    rawFrames+=ledger.frames.length;require(rawFrames<=limits.rawFrames,'Raw frame count exceeds1024');
    const range={start:requested(ledger.association.rangeStart),end:requested(ledger.association.rangeEnd)};
    require(cmp(range.start,rep.end)<0&&cmp(range.end,rep.start)>0,'Window requested range does not intersect selected rep');
    const labelsBytes=await read(labelsPath,4*MiB),labels=parseStrictJSON(labelsBytes.toString('utf8'));
    const bundleDir=path.dirname(ledgerPath),physicalSource=await source(ledger,assetRoot);
    const predictionBytes=await verifyRasterAssets(ledger,bundleDir);check();
    // Snapshot the same prediction bytes and each PNG for final publication checks.
    require(digest(await read(await named(bundleDir,'prediction.json'),MiB))===digest(predictionBytes),'Prediction changed during verification');
    for(const f of ledger.frames) {
      const filename=await named(bundleDir,'frames/'+f.filename);
      const actual=await hashFile(filename,32*MiB,check,signal);require(actual.sha256===f.sha256,'PNG changed during verification');
      assets.set(filename,{...actual,bound:32*MiB});
    }
    const predictions=verifyNativePrediction(ledger,predictionBytes);
    const adapted=adaptLabels(ledger,digest(ledgerBytes),labels,{purpose:'native-scoring',predictionBytes});
    const receiptBytes=await read(evaluationPath,MiB),receipt=parseStrictJSON(receiptBytes.toString('utf8'));
    const evaluationDir=path.dirname(evaluationPath),files={};
    keys(receipt,['schemaVersion','kind','nativeAssociationChecked','accuracyGatePassed','createdAt','files','inputLabelsSHA256','existingRegistrySHA256','source','association','reviewed','unreviewed','policy','limits'],[],'native evaluation receipt');
    require(receipt.schemaVersion===1&&receipt.kind==='native-evaluation'&&receipt.nativeAssociationChecked===true&&receipt.accuracyGatePassed===false,'Incomplete/foreign native evaluation receipt');
    const names=['ledger.json','prediction.json','references.native-reference.json','references.native-reference.json.report.json','score.json'];
    keys(receipt.files,names,[],'evaluation files');
    for(const name of names) {
      keys(receipt.files[name],['sha256','bytes'],[],'evaluation file descriptor');
      const bytes=await read(await named(evaluationDir,name),name==='ledger.json'||name==='prediction.json'?MiB:8*MiB);
      require(receipt.files[name].sha256===digest(bytes)&&receipt.files[name].bytes===bytes.length,'Evaluation file hash/size changed');files[name]=bytes;
    }
    require(receiptBytes.length+Object.values(files).reduce((n,b)=>n+b.length,0)<=8*MiB,'Per-window evaluation exceeds existing8MiB output bound');
    require(files['ledger.json'].equals(ledgerBytes)&&files['prediction.json'].equals(predictionBytes)&&receipt.inputLabelsSHA256===digest(labelsBytes),'Evaluation binds different ledger/prediction/labels');
    const reference=parseStrictJSON(files['references.native-reference.json'].toString('utf8'));
    const report=parseStrictJSON(files['references.native-reference.json.report.json'].toString('utf8'));
    require(equal(reference,adapted.manifest)&&equal(report,adapted.report),'Evaluation reference/report disagrees with freshly adapted labels');
    const score=parseStrictJSON(files['score.json'].toString('utf8')),freshScore=scoreVideoTraces(reference,predictions);
    const {createdAt,limits:scoreLimits,...scoreCore}=score,{limits:freshLimits,...freshCore}=freshScore;
    require(equal(scoreCore,freshCore)&&typeof scoreLimits==='string'&&scoreLimits.startsWith(freshLimits)&&typeof createdAt==='string'&&createdAt===receipt.createdAt&&Number.isFinite(Date.parse(createdAt)),'Evaluation score differs from fresh same-buffer scoring');
    const c=ledger.clip,receiptSource={clipID:c.id,sha256:c.sha256,localPath:c.localPath,sourceGroup:c.sourceGroup,split:c.split,synthetic:c.synthetic,uprightWidth:c.uprightWidth,uprightHeight:c.uprightHeight};
    require(equal(receipt.source,receiptSource)&&equal(receipt.association,ledger.association)&&receipt.reviewed===adapted.report.reviewed&&equal(receipt.unreviewed,adapted.report.unreviewed)&&equal(receipt.policy,freshScore.policy),'Evaluation identity/review/policy association changed');
    require(receipt.existingRegistrySHA256===null||/^[a-f0-9]{64}$/.test(receipt.existingRegistrySHA256),'Invalid prior reference registry digest');
    const hashes={ledger:digest(ledgerBytes),labels:digest(labelsBytes),prediction:digest(predictionBytes),evaluation:digest(receiptBytes)};
    let duplicate;
    for(const key of ['clip:'+c.id,'analysis:'+ledger.association.analysisID.toLowerCase(),'capture:'+ledger.association.captureSessionID.toLowerCase()]) {
      const prior=identities.get(key);
      require(!prior||equal(prior.hashes,hashes),'Repeated original window identity has changed bytes');
      if(prior)duplicate=prior;
    }
    const entry={id:input.id,duplicateOf:duplicate?.id??null,input:{ledger:await realpath(ledgerPath),labels:await realpath(labelsPath),assetRoot:await realpath(assetRoot),evaluation:await realpath(evaluationPath)},hashes,physicalSource,
      clip:ledger.clip,association:ledger.association,decoder:ledger.decoder,frames:ledger.frames,
      reference:reference.clips[0],perWindowEvaluation:{receipt,score},predictions:predictions.runs[0].samples};
    windows.push(entry);
    if(!duplicate){unique.push(entry);for(const key of ['clip:'+c.id,'analysis:'+ledger.association.analysisID.toLowerCase(),'capture:'+ledger.association.captureSessionID.toLowerCase()])identities.set(key,entry);}
  }
  const first=unique[0];
  for(const w of unique)require(['sha256','split','synthetic','lift','targetID'].every(k=>w.clip[k]===first.clip[k]),'Windows disagree on recording/split/provenance/lift/target');
  if(previous) {
    const prior=previous.registry,sameRecording=prior.recordingSHA256===plan.recordingSHA256;
    if(sameRecording)require(prior.split===first.clip.split,'Previous recording leaked across partitions');
    for(const key of ['recordingGroupID','sessionGroupID','subjectGroupID']) {
      if(sameRecording&&prior.groups[key]!==null)require(groups[key]===prior.groups[key],'Cannot erase/change a prior recording group relationship');
      if(groups[key]!==null&&groups[key]===prior.groups[key])require(prior.split===first.clip.split,'Previous group leaked across partitions');
    }
  }
  const combined=new Map(existing.clips.map(c=>[c.id,c]));
  for(const w of unique){const prior=combined.get(w.clip.id);require(!prior||equal(prior,w.reference),'Existing registry clip ID changed');combined.set(w.clip.id,w.reference);}
  require(combined.size<=100,'Existing plus selected registry exceeds authoritative100-clip validator bound; reduce explicitly selected inputs');
  validateVideoManifest({...existing,clips:[...combined.values()]});
  for(const clip of combined.values()) {
    assignPartition(constraints,'recording-sha256',clip.sha256,clip.split);
    assignPartition(constraints,'source-group',clip.sourceGroup,clip.split);
  }
  for(const [key,kind] of Object.entries(groupKinds))if(groups[key]!==null)assignPartition(constraints,kind,groups[key],first.clip.split);
  const partitionConstraints={schemaVersion:1,assignments:[...constraints.values()].toSorted((a,b)=>canonical([a.kind,a.id]).localeCompare(canonical([b.kind,b.id])))};
  const aggregation=deriveCoverage(unique,windows,rep,expected);
  const registry={schemaVersion:1,kind:'native-window-registry',createdAt:new Date().toISOString(),repID:plan.repID,recordingSHA256:plan.recordingSHA256,
    interval:plan.interval,groups,independence:'unknown; a recording hash or supplied group ID does not establish independent subjects/sessions',
    split:first.clip.split,synthetic:first.clip.synthetic,lift:first.clip.lift,targetID:first.clip.targetID,
    planSHA256:digest(planBytes),existingReferenceRegistrySHA256:existingBytes?digest(existingBytes):null,
    previousAggregation:previous?{receiptSHA256:previous.receiptSHA256,receiptPath:previous.receiptPath}:null,partitionConstraints,windows};
  const files=new Map([['registry.json',json(registry)],['aggregation.json',json(aggregation)]]);
  const receipt={schemaVersion:1,kind:'native-window-aggregation',complete:true,accuracyGatePassed:false,createdAt:registry.createdAt,
    recordingSHA256:plan.recordingSHA256,repID:plan.repID,files:Object.fromEntries([...files].map(([name,bytes])=>[name,{sha256:digest(bytes),bytes:bytes.length}])),
    inputs:[...snapshots].map(([filename,x])=>({path:filename,sha256:x.sha256,bytes:x.bytes.length})),
    assets:[...assets].map(([filename,x])=>({path:filename,sha256:x.sha256,bytes:x.bytes})),
    media:[...media].map(([filename,x])=>({path:filename,sha256:x.ledger.clip.sha256,bytes:x.bytes})),limits,
    counts:{selectedWindows:windows.length,uniqueWindows:unique.length,rawFrames,jsonBytes,distinctMediaBytes:mediaBytes},
    policy:'Coverage/conflicts only; no pooled localization metric, automatic conflict winner, label propagation, cross-window track identity or accuracy acceptance. Trusted local filesystem; byte association is not origin authentication.'};
  // Freshly check every selected JSON/PNG and every distinct source before publish.
  // A phase observer can show progress/cancel; it cannot bypass the fresh checks.
  if(onPhase)await onPhase('validating-publication');check();
  for(const [filename,x] of snapshots)require((await hashFile(filename,x.bound,check,signal)).sha256===x.sha256,'JSON input changed before publication');
  for(const [filename,x] of assets)require((await hashFile(filename,x.bound,check,signal)).sha256===x.sha256,'PNG input changed before publication');
  for(const x of media.values()) {
    check();const verified=await verifyMedia({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[{...x.ledger.clip,annotations:[]}]},x.root,{fileLimit:500*MiB,totalLimit:500*MiB});check();mediaReadBytes+=verified.totalBytes;
    require(verified.totalBytes===x.bytes,'Media changed before publication');
  }
  receipt.mediaReadBytes=mediaReadBytes;files.set('aggregation-receipt.json',json(receipt));
  require([...files.values()].reduce((n,b)=>n+b.length,0)<=limits.outputBytes,'Derived output exceeds8MiB bound');
  const staging=path.join(parent,'.native-aggregation-partial-'+randomUUID());let owned=false,published=false;
  try {
    check();await mkdir(staging);owned=true;
    for(const [name,bytes] of files){check();await writeFile(path.join(staging,name),bytes,{flag:'wx'});}
    check();await absent(destination);await rename(staging,destination);published=true;return {output:destination,receipt,aggregation};
  } finally {if(owned&&!published)await rm(staging,{recursive:true,force:true});}
}

async function readFileBounded(filename,bound,check,signal) {
  return (await streamFile(filename,bound,check,signal,true)).buffer;
}
async function hashFile(filename,bound,check,signal) {return streamFile(filename,bound,check,signal,false);}
async function streamFile(filename,bound,check,signal,collect) {
  check();require(!(await lstat(filename)).isSymbolicLink(),'Changed input became a symlink');
  const controller=new AbortController(),abort=()=>controller.abort(),timer=setTimeout(abort,limits.perFileMs);
  signal?.addEventListener('abort',abort,{once:true});let handle;
  try {
    check();handle=await open(filename,'r');const before=await handle.stat();
    require(before.isFile()&&before.size>0&&before.size<=bound,'Regular file/byte bound failed');
    const chunks=[],hash=createHash('sha256');let bytes=0;
    for await(const chunk of handle.createReadStream({autoClose:false,highWaterMark:128*1024,signal:controller.signal})) {
      check();bytes+=chunk.length;require(bytes<=bound,'Stream byte bound exceeded');hash.update(chunk);if(collect)chunks.push(chunk);
    }
    const after=await handle.stat();check();
    require(bytes===before.size&&after.size===before.size&&after.mtimeMs===before.mtimeMs,'File changed during read');
    return {bytes,sha256:hash.digest('hex'),...(collect?{buffer:Buffer.concat(chunks,bytes)}:{})};
  } finally {clearTimeout(timer);signal?.removeEventListener('abort',abort);await handle?.close();}
}

function deriveCoverage(unique,windows,rep,expected) {
  const byTime=new Map(),ranges=[],seams=[];
  for(const w of unique) {
    ranges.push({start:requested(w.association.rangeStart),end:requested(w.association.rangeEnd)});
    const refs=new Map(w.reference.annotations.map(a=>[timestampKey(a.timestamp),a]));
    w.frames.forEach((f,i)=>{
      const key=timestampKey(f.timestamp),rows=byTime.get(key)??[];
      rows.push({windowID:w.id,frameID:f.id,timestamp:f.timestamp,sha256:f.sha256,
        geometry:{width:w.clip.uprightWidth,height:w.clip.uprightHeight,decoder:w.decoder},
        reference:refs.get(key)??null,referenceStatus:refs.has(key)?'reviewed':'unreviewed',
        prediction:{modelID:w.association.modelID,mode:w.association.mode,sample:w.predictions[i]}});byTime.set(key,rows);
    });
  }
  const timestamps=[...byTime].map(([key,rows])=>{
    const first=rows[0],conflicts=[];
    for(const [field,reason] of [['timestamp','component-tuples'],['sha256','raster-bytes'],['geometry','geometry-decoder']])
      if(rows.some(row=>!equal(row[field],first[field])))conflicts.push(reason);
    const meaning=reference=>reference===null?null:Object.fromEntries(Object.entries(reference).filter(([key])=>key!=='timestamp'));
    if(rows.some(row=>!equal(meaning(row.reference),meaning(first.reference))))conflicts.push('reference-review');
    const partitions=new Map();
    for(const row of rows){const p=row.prediction,key=canonical([p.mode,p.modelID]);const list=partitions.get(key)??[];list.push(row);partitions.set(key,list);}
    const predictionComparisons=[...partitions.values()].map(list=>{
      // Local targetID is retained in rows but deliberately excluded from semantic comparison.
      const semantic=s=>({point:s.point,kind:s.kind,confidence:s.confidence});
      return {mode:list[0].prediction.mode,modelID:list[0].prediction.modelID,windowIDs:list.map(r=>r.windowID),
        stateDisagreement:list.some(r=>!equal(semantic(r.prediction.sample),semantic(list[0].prediction.sample))),crossWindowTrackIdentity:'unverified'};
    });
    const reviewed=rows.filter(r=>r.referenceStatus==='reviewed');
    return {key,inRep:withinInterval(time(first.timestamp),rep),rows,conflicts,predictionComparisons,
      referenceState:conflicts.length?'conflict':reviewed.length===rows.length?'reviewed':'unreviewed',
      identicalReviewedDuplicate:rows.length>1&&conflicts.length===0&&reviewed.length===rows.length};
  }).toSorted((a,b)=>cmp(time(a.rows[0].timestamp),time(b.rows[0].timestamp)));
  for(let i=0;i<unique.length;i++)for(let j=i+1;j<unique.length;j++) {
    const a=unique[i],b=unique[j],shared=timestamps.filter(t=>t.rows.some(r=>r.windowID===a.id)&&t.rows.some(r=>r.windowID===b.id));
    seams.push({windows:[a.id,b.id],sharedDecodedTimestamps:shared.length,conflictedTimestamps:shared.filter(t=>t.conflicts.length).length,
      continuity:'unverified',reason:shared.length?'Shared samples permit diagnostics only; tracker state is local to each window':'No shared decoded timestamp'});
  }
  const union=[];
  for(const r of ranges.toSorted((a,b)=>cmp(a.start,b.start))) {
    const start=cmp(r.start,rep.start)<0?rep.start:r.start,end=cmp(r.end,rep.end)>0?rep.end:r.end;
    if(cmp(start,end)>=0)continue;const last=union.at(-1);
    if(last&&cmp(start,last.end)<=0){if(cmp(end,last.end)>0)last.end=end;}else union.push({start,end});
  }
  let cursor=rep.start,covered=rational(0n);const gaps=[];
  for(const r of union){if(cmp(cursor,r.start)<0)gaps.push({start:encoded(cursor),end:encoded(r.start)});cursor=r.end;covered=plus(covered,minus(r.end,r.start));}
  if(cmp(cursor,rep.end)<0)gaps.push({start:encoded(cursor),end:encoded(rep.end)});
  const selected=timestamps.filter(t=>t.inRep),aliases=new Map(windows.map(w=>[w.id,w.duplicateOf??w.id]));
  return {schemaVersion:1,kind:'native-window-coverage',accuracyGatePassed:false,scalarMetrics:null,
    declaredRequestCoverage:{basis:'Serialized ledger request Doubles as decimal rationals; not exact decoder boundary or frame coverage',
      union:union.map(r=>({start:encoded(r.start),end:encoded(r.end)})),gaps,coveredSeconds:encoded(covered)},
    counts:{distinctDecodedTimestamps:selected.length,reviewedUniqueTimestamps:selected.filter(t=>t.referenceState==='reviewed').length,
      unreviewedUniqueTimestamps:selected.filter(t=>t.referenceState==='unreviewed').length,conflictedUniqueTimestamps:selected.filter(t=>t.referenceState==='conflict').length,
      syntheticReviewedUniqueTimestamps:unique[0].clip.synthetic?selected.filter(t=>t.referenceState==='reviewed').length:0,
      observedReviewedUniqueTimestamps:unique[0].clip.synthetic?0:selected.filter(t=>t.referenceState==='reviewed').length},
    reviewedVisibility:Object.fromEntries(['visible','occluded','outside-frame','uncertain'].map(visibility=>[visibility,selected.filter(t=>t.referenceState==='reviewed'&&t.rows[0].reference.visibility===visibility).length])),
    expectedOverlaps:expected.map(o=>({...o,sharedDecodedTimestamps:timestamps.filter(t=>withinInterval(time(t.rows[0].timestamp),interval(o.interval))&&o.windows.every(id=>t.rows.some(r=>r.windowID===aliases.get(id)))).length,continuity:'unverified'})),
    timestamps,seams,limits:'Distinct-time counts are not full-rep completeness or a pooled score. Conflicts preserve every original row. Unreviewed rows never inherit labels; no interpolation or cross-window identity assertion.'};
}

async function main() {
  const options={},allowed=new Set(['plan','output','existing','previous-receipt']);
  for(let i=2;i<process.argv.length;i+=2){const key=process.argv[i].slice(2);require(process.argv[i]==='--'+key&&allowed.has(key)&&!Object.hasOwn(options,key)&&process.argv[i+1],'Use unique --plan --output and optional --existing/--previous-receipt');options[key]=process.argv[i+1];}
  const controller=new AbortController(),cancel=()=>controller.abort();process.on('SIGINT',cancel);process.on('SIGTERM',cancel);
  try {const result=await aggregateNativeWindows({planFile:options.plan,output:options.output,existingFile:options.existing,previousReceiptFile:options['previous-receipt'],signal:controller.signal});console.log(JSON.stringify({output:result.output,counts:result.aggregation.counts,accuracyGatePassed:false},null,2));}
  finally {process.removeListener('SIGINT',cancel);process.removeListener('SIGTERM',cancel);}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main().catch(e=>{console.error(e.message);process.exitCode=1;});
