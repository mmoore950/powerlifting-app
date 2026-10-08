import {readFile,realpath,open,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {validateVideoManifest,compileVideoSchema,checkSchema,timestampKey,orderedTimestamps} from './validate-video-manifest.mjs';
import {atomicJSON} from '../DataService/src/storage.mjs';

const predictionSchema=JSON.parse(await readFile(new URL('../docs/video-prediction.schema.json',import.meta.url),'utf8'));
const predictionValidator=compileVideoSchema(predictionSchema);
const require=(ok,message)=>{if(!ok)throw new Error(message);};
const maxFileBytes=500*1024*1024,maxTotalBytes=4*1024**3,maxJSONBytes=32*1024*1024;

export function validatePredictions(predictions,manifest) {
  checkSchema(predictionValidator,predictions,'Prediction export');
  const clips=new Map(manifest.clips.map(clip=>[clip.id,clip])),keys=new Set();
  for(const run of predictions.runs) {
    const clip=clips.get(run.clipID),key=JSON.stringify([run.clipID,run.mode]);
    require(clip&&!keys.has(key),'Unknown/duplicate prediction clip/mode');keys.add(key);
    require(run.sha256===clip.sha256&&run.synthetic===clip.synthetic&&run.uprightWidth===clip.uprightWidth&&run.uprightHeight===clip.uprightHeight,'Prediction media/provenance/dimensions mismatch');
    orderedTimestamps(run.samples.map(sample=>sample.timestamp));
    for(const sample of run.samples) {
      require((sample.kind==='lost')===(sample.point===null),'Lost/point state mismatch');
      require(sample.point===null||typeof sample.targetID==='string','Accepted prediction requires track identity');
      require(!sample.targetID?.includes('\0'),'Invalid track identity');
      if(run.mode==='manual-vision')require(sample.kind!=='automatic','Manual fallback labeled automatic');
    }
  }
}

/** Stream private local bytes, never fetch or upload. This verifies bytes, not video decoding/geometry. */
export async function verifyMedia(manifest,assetRoot,{fileLimit=maxFileBytes,totalLimit=maxTotalBytes,timeoutMs=60_000}={}) {
  validateVideoManifest(manifest);
  require(Number.isSafeInteger(fileLimit)&&fileLimit>0&&Number.isSafeInteger(totalLimit)&&totalLimit>0&&Number.isInteger(timeoutMs)&&timeoutMs>0,'Invalid hash limits');
  const base=await realpath(path.resolve(assetRoot)),checks=[];let totalBytes=0;
  for(const clip of manifest.clips) {
    const resolved=await realpath(path.resolve(base,clip.localPath));
    const relative=path.relative(base,resolved);
    require(relative&&!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith('..'+path.sep),'Media realpath escaped private asset root');
    const handle=await open(resolved,'r'),controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeoutMs);
    try {
      const before=await handle.stat();require(before.isFile()&&before.size>0&&before.size<=fileLimit,'Media must be a nonempty regular file within size bound');
      require(totalBytes+before.size<=totalLimit,'Total media hash byte budget exceeded');
      const hash=createHash('sha256');let bytes=0;
      for await(const chunk of handle.createReadStream({autoClose:false,signal:controller.signal})) {
        bytes+=chunk.length;require(bytes<=fileLimit&&totalBytes+bytes<=totalLimit,'Media hash byte budget exceeded');hash.update(chunk);
      }
      const after=await handle.stat();require(before.size===bytes&&after.size===before.size&&after.mtimeMs===before.mtimeMs,'Media changed during hashing');
      require(hash.digest('hex')===clip.sha256,'Media SHA-256 mismatch');
      totalBytes+=bytes;checks.push({clipID:clip.id,sha256:clip.sha256,bytes});
    } finally {clearTimeout(timer);await handle.close();}
  }
  return {checks,totalBytes,fileLimit,totalLimit,perFileCancellationMs:timeoutMs};
}

const mean=values=>values.length?values.reduce((a,b)=>a+b,0)/values.length:null;
const quantile=(values,fraction)=>{if(!values.length)return null;const sorted=[...values].sort((a,b)=>a-b);return sorted[Math.max(0,Math.ceil(fraction*sorted.length)-1)];};
const elapsed=(a,b)=>a.epoch===b.epoch?
  Number(BigInt(b.value)*BigInt(a.timescale)-BigInt(a.value)*BigInt(b.timescale))/Number(BigInt(a.timescale)*BigInt(b.timescale)):Infinity;

/** Exact rational PTS only. No nearest-frame inference, interpolated predictions or ground-truth synthesis. */
export function scoreVideoTraces(manifest,predictions,{pixelThreshold=10,minimumConfidence=0.5}={}) {
  const reference=validateVideoManifest(manifest);validatePredictions(predictions,manifest);
  require(Number.isFinite(pixelThreshold)&&pixelThreshold>0&&Number.isFinite(minimumConfidence)&&minimumConfidence>=0&&minimumConfidence<=1,'Invalid score policy');
  const cases=[];
  for(const clip of manifest.clips) for(const mode of ['automatic','manual-vision']) {
    const run=predictions.runs.find(r=>r.clipID===clip.id&&r.mode===mode);
    const samples=new Map((run?.samples??[]).map(sample=>[timestampKey(sample.timestamp),sample]));
    const segments=new Map();let segment=0,previousSample;
    for(const sample of run?.samples??[]) {
      if(!previousSample?.point||previousSample.confidence<minimumConfidence||!sample.point||sample.confidence<minimumConfidence||elapsed(previousSample.timestamp,sample.timestamp)>0.25)segment++;
      segments.set(timestampKey(sample.timestamp),segment);previousSample=sample;
    }
    const metrics={visibleReferences:0,matchedVisibleSamples:0,missingVisibleSamples:0,visibleAbstentions:0,acceptedVisible:0,
      withinThreshold:0,definitelyWithinThreshold:0,definitelyOutsideThreshold:0,uncertaintyOverlapsThreshold:0,
      ambiguousReferences:0,unobservableReferences:0,acceptedUnobservable:0,identityChanges:0,identitiesAfterGap:0,unreferencedPredictions:0};
    const errors=[],observations=[];let lastIdentity,lastSegment,lastAccepted=false;
    const keys=new Set(clip.annotations.map(a=>timestampKey(a.timestamp)));
    metrics.unreferencedPredictions=(run?.samples??[]).filter(s=>!keys.has(timestampKey(s.timestamp))).length;
    for(const annotation of clip.annotations) {
      const sample=samples.get(timestampKey(annotation.timestamp)),accepted=Boolean(sample?.point&&sample.confidence>=minimumConfidence);
      if(annotation.visibility==='uncertain') {metrics.ambiguousReferences++;lastAccepted=false;continue;}
      if(annotation.visibility!=='visible') {
        metrics.unobservableReferences++;if(accepted)metrics.acceptedUnobservable++;lastAccepted=false;continue;
      }
      metrics.visibleReferences++;
      if(!sample){metrics.missingVisibleSamples++;lastAccepted=false;continue;}
      metrics.matchedVisibleSamples++;
      if(!accepted){metrics.visibleAbstentions++;lastAccepted=false;continue;}
      metrics.acceptedVisible++;
      const distance=Math.hypot((sample.point.x-annotation.point.x)*clip.uprightWidth,(sample.point.y-annotation.point.y)*clip.uprightHeight);
      const lower=Math.max(0,distance-annotation.uncertaintyPixels),upper=distance+annotation.uncertaintyPixels;
      errors.push(distance);if(distance<=pixelThreshold+1e-9)metrics.withinThreshold++;
      if(upper<=pixelThreshold+1e-9)metrics.definitelyWithinThreshold++;
      else if(lower>pixelThreshold+1e-9)metrics.definitelyOutsideThreshold++;
      else metrics.uncertaintyOverlapsThreshold++;
      if(lastIdentity!==undefined&&lastIdentity!==sample.targetID) {
        if(lastAccepted&&lastSegment===segments.get(timestampKey(sample.timestamp)))metrics.identityChanges++;else metrics.identitiesAfterGap++;
      }
      lastIdentity=sample.targetID;lastSegment=segments.get(timestampKey(sample.timestamp));lastAccepted=true;
      observations.push({timestamp:annotation.timestamp,errorPixels:distance,uncertaintyLowerPixels:lower,uncertaintyUpperPixels:upper});
    }
    cases.push({clipID:clip.id,mode,split:clip.split,synthetic:clip.synthetic,runPresent:Boolean(run),elapsedSeconds:run?.elapsedSeconds??null,
      ...metrics,acceptedCoverage:metrics.visibleReferences?metrics.acceptedVisible/metrics.visibleReferences:null,
      localizedCoverage:metrics.visibleReferences?metrics.withinThreshold/metrics.visibleReferences:null,
      errorPixels:{mean:mean(errors),median:quantile(errors,0.5),p95:quantile(errors,0.95),maximum:errors.length?Math.max(...errors):null},observations});
  }
  const groups=[];
  for(const synthetic of [false,true])for(const split of ['training','development','holdout'])for(const mode of ['automatic','manual-vision']) {
    const selected=cases.filter(c=>c.synthetic===synthetic&&c.split===split&&c.mode===mode);
    if(!selected.length)continue;
    const visibleReferences=selected.reduce((n,c)=>n+c.visibleReferences,0),acceptedVisible=selected.reduce((n,c)=>n+c.acceptedVisible,0),withinThreshold=selected.reduce((n,c)=>n+c.withinThreshold,0);
    const errors=selected.flatMap(c=>c.observations.map(o=>o.errorPixels));
    groups.push({synthetic,split,mode,clips:selected.length,runs:selected.filter(c=>c.runPresent).length,visibleReferences,acceptedVisible,withinThreshold,
      acceptedCoverage:visibleReferences?acceptedVisible/visibleReferences:null,localizedCoverage:visibleReferences?withinThreshold/visibleReferences:null,
      errorPixels:{mean:mean(errors),median:quantile(errors,0.5),p95:quantile(errors,0.95)}});
  }
  const observedVisible=cases.filter(c=>!c.synthetic&&c.mode==='automatic').reduce((n,c)=>n+c.visibleReferences,0);
  const observedMatched=cases.filter(c=>!c.synthetic&&c.mode==='automatic').reduce((n,c)=>n+c.matchedVisibleSamples,0);
  return {schemaVersion:1,modelID:predictions.modelID,policy:{matching:'exact rational PTS and epoch; no interpolation',pixelThreshold,minimumConfidence,maximumIdentityGapSeconds:0.25,pixelComparisonEpsilon:1e-9},
    reference,accuracyGatePassed:false,evidence:observedVisible&&observedMatched?'observed frame coverage/localization measurements only; native/representativeness/held-out gates still required':'no observed automatic localization evidence; accuracy unmeasured',
    groups,cases,limits:'Track identity changes are diagnostic continuity counts, not proof of semantic near-side identity. Unobservable accepted points are assertions during occlusion/outside-frame, not labeled false positives. Unreferenced timestamps have no ground truth; uncertainty is a supplied radius, not statistical confidence. No release acceptance threshold is applied.'};
}

async function readBoundedJSON(file) {
  require((await stat(file)).size<=maxJSONBytes,'JSON exceeds32MiB bound');
  const bytes=await readFile(file);require(bytes.length<=maxJSONBytes,'JSON exceeds32MiB bound');return JSON.parse(bytes.toString('utf8'));
}
export async function evaluateVideoFiles({manifestFile,predictionsFile,assetRoot,output,pixelThreshold=10,minimumConfidence=0.5}) {
  const manifest=await readBoundedJSON(manifestFile),predictions=await readBoundedJSON(predictionsFile);
  const report=scoreVideoTraces(manifest,predictions,{pixelThreshold,minimumConfidence});
  report.media=await verifyMedia(manifest,assetRoot);report.createdAt=new Date().toISOString();
  report.limits+=' Hashes verify selected local bytes; this command does not decode media, validate upright dimensions/orientation or establish native frame provenance. Trusted local filesystem required; metadata/path races are not an adversarial filesystem security guarantee.';
  if(output)await atomicJSON(path.resolve(output),report);
  return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  const args=process.argv.slice(2),options={};
  for(let i=0;i<args.length;i+=2) {
    require(['--manifest','--predictions','--asset-root','--output','--pixel-threshold','--minimum-confidence'].includes(args[i])&&args[i+1]!==undefined,'Use --manifest --predictions --asset-root and optional --output/--pixel-threshold/--minimum-confidence');
    options[args[i].slice(2)]=args[i+1];
  }
  require(options.manifest&&options.predictions&&options['asset-root'],'Explicit manifest, predictions and private asset root required');
  const report=await evaluateVideoFiles({manifestFile:options.manifest,predictionsFile:options.predictions,assetRoot:options['asset-root'],output:options.output,
    ...(options['pixel-threshold']!==undefined?{pixelThreshold:Number(options['pixel-threshold'])}:{}),
    ...(options['minimum-confidence']!==undefined?{minimumConfidence:Number(options['minimum-confidence'])}:{})});
  console.log(JSON.stringify({output:options.output??null,evidence:report.evidence,accuracyGatePassed:report.accuracyGatePassed,reference:report.reference,media:report.media,groups:report.groups},null,2));
}
