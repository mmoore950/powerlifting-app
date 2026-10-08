import {readFile,writeFile,realpath,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {validateVideoManifest,orderedTimestamps} from '../validate-video-manifest.mjs';
import {parseStrictJSON} from './strict_json.mjs';
import {validateNativeContract} from './native_contract.mjs';
import {validatePredictions,verifyMedia} from '../score-video-traces.mjs';
export {parseStrictJSON} from './strict_json.mjs';

export const digest=bytes=>createHash('sha256').update(bytes).digest('hex');
const require=(ok,message)=>{if(!ok)throw Error(message);};
const keys=(o,expected,label)=>require(o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('|')===expected.toSorted().join('|'),`Unexpected ${label} fields`);
export function validateLedger(ledger) {
  if(ledger?.purpose==='native-analysis')validateNativeContract(ledger);
  else {
    keys(ledger,['schemaVersion','purpose','nativeParityVerified','decoder','clip','frames'],'ledger');
    require(ledger.schemaVersion===1&&ledger.purpose==='development-only'&&ledger.nativeParityVerified===false,'Only explicitly unverified development bundles supported');
    require(ledger.decoder?.name==='PyAV'&&typeof ledger.decoder.version==='string','Missing decoder provenance');
  }
  validateVideoManifest({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[{...ledger.clip,annotations:[]}]});
  require(Array.isArray(ledger.frames)&&ledger.frames.length>0&&ledger.frames.length<=450,'Invalid frame bound');
  const ids=new Set(),names=new Set();
  for(const f of ledger.frames) {
    keys(f,['id','filename','sha256','timestamp'],'frame');
    require(/^frame-\d{6}$/.test(f.id)&&!ids.has(f.id),'Duplicate/foreign frame ID');ids.add(f.id);
    require(f.filename===f.id+'.png'&&!names.has(f.filename),'Ambiguous/foreign image filename');names.add(f.filename);
    require(/^[a-f0-9]{64}$/.test(f.sha256),'Invalid image hash');
    keys(f.timestamp,['value','timescale','epoch'],'timestamp');
    require(f.timestamp.epoch===0,'Unsupported native epoch');
  }
  orderedTimestamps(ledger.frames.map(f=>f.timestamp));
  return ledger;
}

export function verifyNativePrediction(ledger,bytes) {
  validateLedger(ledger);
  require(ledger.purpose==='native-analysis'&&bytes&&bytes.length>0&&bytes.length<=1024*1024,'Native prediction bytes required within bound');
  require(digest(bytes)===ledger.association.predictionSHA256,'Native prediction hash changed');
  const predictions=parseStrictJSON(bytes.toString('utf8'));
  validatePredictions(predictions,{clips:[{...ledger.clip,annotations:[]}]});
  const a=ledger.association,run=predictions.runs[0];
  require(predictions.runs.length===1&&predictions.modelID===a.modelID&&run.mode===a.mode&&run.samples.length===ledger.frames.length,'Native prediction association mismatch');
  for(let i=0;i<run.samples.length;i++) {
    const t=run.samples[i].timestamp,f=ledger.frames[i].timestamp;
    require(t.value===f.value&&t.timescale===f.timescale&&t.epoch===f.epoch,'Native prediction exact timestamp mismatch');
  }
  return predictions;
}

export function adaptLabels(ledger,ledgerHash,labels,{purpose='development',predictionBytes,existing={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[]}}={}) {
  validateLedger(ledger);
  require(['development','native-scoring'].includes(purpose),'Unknown annotation purpose');
  if(purpose==='native-scoring') {
    require(ledger.purpose==='native-analysis','PyAV frames are not native-parity verified: native scoring refused');
    verifyNativePrediction(ledger,predictionBytes);
  } else if(ledger.purpose==='native-analysis')verifyNativePrediction(ledger,predictionBytes);
  keys(labels,['schemaVersion','ledgerSha256','viaMetadata'],'label envelope');
  require(labels.schemaVersion===1&&labels.ledgerSha256===ledgerHash,'Foreign/changed authoritative ledger');
  keys(labels.viaMetadata,ledger.frames.map(f=>f.id),'frame metadata');
  const annotations=[],unreviewed=[];
  for(const f of ledger.frames) {
    const m=labels.viaMetadata[f.id];
    keys(m,['filename','size','regions','file_attributes'],'VIA metadata');
    require(m.filename===f.filename&&m.size===-1,'Foreign/ambiguous frame metadata');
    require(Array.isArray(m.regions),'Invalid regions');
    keys(m.file_attributes,['reviewStatus','visibility','uncertaintyPixels'],'file attributes');
    const a=m.file_attributes;
    require(['unreviewed','reviewed'].includes(a.reviewStatus),'Invalid review status');
    require(['','visible','occluded','outside-frame','uncertain'].includes(a.visibility),'Invalid visibility');
    require(a.uncertaintyPixels===null||(typeof a.uncertaintyPixels==='number'&&Number.isFinite(a.uncertaintyPixels)&&a.uncertaintyPixels>=1),'Invalid finite pixel uncertainty');
    require(m.regions.length<=1,'Ambiguous multiple points, including unreviewed frames');
    for(const r of m.regions) {
      keys(r,['shape_attributes','region_attributes'],'region');keys(r.region_attributes,[],'region attributes');
      keys(r.shape_attributes,['name','cx','cy'],'point shape');const s=r.shape_attributes;
      require(s.name==='point'&&Number.isInteger(s.cx)&&Number.isInteger(s.cy)&&s.cx>=0&&s.cx<ledger.clip.uprightWidth&&s.cy>=0&&s.cy<ledger.clip.uprightHeight,'Invalid/out-of-bounds original-pixel point');
    }
    if(a.reviewStatus==='unreviewed') {unreviewed.push(f.id);continue;}
    require(['visible','occluded','outside-frame','uncertain'].includes(a.visibility),'Missing/invalid explicit visibility');
    let point=null,uncertainty=null;
    if(a.visibility==='visible') {
      require(m.regions.length===1,'Visible frame needs exactly one point');
      const s=m.regions[0].shape_attributes,w=ledger.clip.uprightWidth,h=ledger.clip.uprightHeight;
      require(typeof a.uncertaintyPixels==='number'&&Number.isFinite(a.uncertaintyPixels)&&a.uncertaintyPixels>=1,'Visible labels need at least 1 pixel uncertainty for integer rounding');
      point={x:s.cx/w,y:s.cy/h};uncertainty=a.uncertaintyPixels;
    } else {
      require(m.regions.length===0&&a.uncertaintyPixels===null,'Non-visible labels must have no point or uncertainty');
    }
    annotations.push({timestamp:f.timestamp,targetID:ledger.clip.targetID,visibility:a.visibility,point,uncertaintyPixels:uncertainty,
                      provenance:ledger.clip.synthetic?'synthetic-reference':'manual-reference'});
  }
  const clip={...ledger.clip,annotations};
  const manifest={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[clip]};
  validateVideoManifest(existing);
  validateVideoManifest({...manifest,clips:[...existing.clips,clip]});
  const validation=validateVideoManifest(manifest);
  const native=ledger.purpose==='native-analysis';
  return {manifest,report:{...validation,unreviewed,reviewed:annotations.length,purpose:native?purpose:'development-only',nativeParityVerified:native,
    ...(native?{analysisID:ledger.association.analysisID,captureSessionID:ledger.association.captureSessionID,predictionSHA256:ledger.association.predictionSHA256}:{}),
    note:native?'Native producer contract and prediction association checked. This does not authenticate edited bundles or establish tracking accuracy.':'Decoded raster/time alignment with native output is unverified. This draft is not established native scoring evidence.'}};
}

async function within(root,relative) {
  require(typeof relative==='string'&&!path.isAbsolute(relative)&&!relative.includes(':')&&!relative.split(/[\\/]/).some(x=>x==='..'||!x),'Unsafe local path');
  const base=await realpath(root),full=await realpath(path.resolve(base,relative));
  const rel=path.relative(base,full);require(rel&&!rel.startsWith('..')&&!path.isAbsolute(rel),'Path escapes explicit asset root');return full;
}
export async function verifyAssets(ledger,bundleDir,assetRoot) {
  validateLedger(ledger);
  const fileLimit=(ledger.purpose==='native-analysis'?500:512)*1024*1024;
  // Reuse the scorer's streaming byte/count, before/after stat and 60s cancellation policy.
  try { await verifyMedia({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[{...ledger.clip,annotations:[]}]},assetRoot,{fileLimit,totalLimit:fileLimit}); }
  catch(error) { throw Error(`Media hash changed or file policy failed: ${error.message}`); }
  return verifyRasterAssets(ledger,bundleDir);
}

// The aggregate verifies each explicit physical recording separately and reuses
// these unchanged per-window raster/prediction checks. This does not skip media
// verification in verifyAssets or relax its existing caller contract.
export async function verifyRasterAssets(ledger,bundleDir) {
  validateLedger(ledger);
  let total=0;
  for(const f of ledger.frames) {
    const filename=await within(bundleDir,'frames/'+f.filename),size=(await stat(filename)).size;
    total+=size;require(total<=32*1024*1024,'Frame payload exceeds bound');const bytes=await readFile(filename);
    require(digest(bytes)===f.sha256,'Image hash changed');
    require(bytes.length>=24&&bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))&&
      bytes.readUInt32BE(16)===ledger.clip.uprightWidth&&bytes.readUInt32BE(20)===ledger.clip.uprightHeight,'PNG geometry differs from ledger');
  }
  if(ledger.purpose==='native-analysis') {
    const filename=await within(bundleDir,'prediction.json');
    require((await stat(filename)).size<=1024*1024,'Native prediction JSON exceeds bound');
    const bytes=await readFile(filename);verifyNativePrediction(ledger,bytes);return bytes;
  }
}
async function main() {
  const args={};for(let i=2;i<process.argv.length;i+=2){require(/^--[a-z-]+$/.test(process.argv[i])&&process.argv[i+1],'Expected --name value');args[process.argv[i].slice(2)]=process.argv[i+1];}
  for(const k of ['ledger','labels','asset-root','output','purpose'])require(args[k],`Missing --${k}`);
  for(const [filename,bound] of [[args.ledger,1024*1024],[args.labels,4*1024*1024],...(args.existing?[[args.existing,32*1024*1024]]:[])])require((await stat(filename)).size<=bound,'JSON exceeds input bound');
  const bytes=await readFile(args.ledger),ledger=validateLedger(parseStrictJSON(bytes.toString('utf8'))),labels=parseStrictJSON(await readFile(args.labels,'utf8'));
  const existing=args.existing?parseStrictJSON(await readFile(args.existing,'utf8')):undefined;
  const predictionBytes=await verifyAssets(ledger,path.dirname(args.ledger),args['asset-root']);
  const result=adaptLabels(ledger,digest(bytes),labels,{purpose:args.purpose,existing,predictionBytes});
  const suffix=args.purpose==='native-scoring'?'.native-reference.json':'.development-draft.json';
  require(args.output.endsWith(suffix),`Output must end ${suffix}`);
  // Exclusive creation preserves previous exports. Companion report must travel with this draft.
  await writeFile(args.output+'.report.json',JSON.stringify(result.report,null,2)+'\n',{flag:'wx'});
  await writeFile(args.output,JSON.stringify(result.manifest,null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify(result.report,null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main().catch(e=>{console.error(e.message);process.exitCode=1;});
