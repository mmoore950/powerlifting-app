import {readFile} from 'node:fs/promises';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';

const require=createRequire(new URL('../DataService/package.json',import.meta.url));
const Ajv2020=require('ajv/dist/2020.js').default;
const ajv=new Ajv2020({strict:true,allErrors:true,coerceTypes:false,useDefaults:false,removeAdditional:false});
const schema=JSON.parse(await readFile(new URL('../docs/video-evaluation.schema.json',import.meta.url),'utf8'));
const formal=ajv.compile(schema);
export function checkSchema(validator,value,label) {
  if(!validator(value)) throw new Error(`${label} schema: ${ajv.errorsText(validator.errors,{separator:'; '})}`);
}
export const compileVideoSchema=value=>ajv.compile(value);

export function timestampKey(t) {
  if(!t||typeof t.value!=='string'||!/^[-]?\d+$/.test(t.value)||!Number.isInteger(t.timescale)||t.timescale<1||t.timescale>2147483647||!Number.isSafeInteger(t.epoch)||t.epoch<0) throw new Error('Invalid actual timestamp');
  const value=BigInt(t.value),scale=BigInt(t.timescale);
  if(value<-(2n**63n)||value>=2n**63n) throw new Error('Timestamp exceeds Int64');
  let a=value<0n?-value:value,b=scale;while(b){const next=a%b;a=b;b=next;}
  return `${t.epoch}:${value/a}/${scale/a}`;
}

export function orderedTimestamps(items) {
  let previous;
  for(const t of items) {
    timestampKey(t);
    if(previous&&!(t.epoch>previous.epoch||(t.epoch===previous.epoch&&BigInt(t.value)*BigInt(previous.timescale)>BigInt(previous.value)*BigInt(t.timescale)))) throw new Error('Unordered/duplicate actual timestamps');
    previous=t;
  }
}

// Formal Draft2020-12 validation plus project-specific semantic checks. No coercion or mutation.
export function validateVideoManifest(manifest) {
  checkSchema(formal,manifest,'Reference manifest');
  const require=(condition,message)=>{if(!condition)throw Error(message);};
  require(manifest.schemaVersion===1&&manifest.coordinateSpace==='upright-normalized-top-left'&&Array.isArray(manifest.clips),'Invalid manifest envelope');
  const ids=new Set(),hashSplits=new Map(),groupSplits=new Map();let observed=0,synthetic=0;
  for(const clip of manifest.clips) {
    require(typeof clip.id==='string'&&clip.id&&!ids.has(clip.id),'Duplicate/missing clip ID');ids.add(clip.id);
    require(/^[a-f0-9]{64}$/.test(clip.sha256)&&['training','development','holdout'].includes(clip.split),'Invalid hash/split');
    require(typeof clip.sourceGroup==='string'&&clip.sourceGroup,'Missing source group');
    for(const [map,key] of [[hashSplits,clip.sha256],[groupSplits,clip.sourceGroup]]) {
      require(!map.has(key)||map.get(key)===clip.split,'Recording/hash leaked across held-out partitions');map.set(key,clip.split);
    }
    require(typeof clip.localPath==='string'&&!/^(?:[a-zA-Z]:|[\\/])/.test(clip.localPath)&&!clip.localPath.split(/[\\/]/).some(p=>p==='..'||!p)&&!clip.localPath.includes(':')&&!clip.localPath.includes('\0'),'Local path must remain relative to private asset root');
    require(typeof clip.synthetic==='boolean'&&typeof clip.permissionEvidence==='string'&&clip.permissionEvidence,'Missing provenance/permission');
    require([clip.uprightWidth,clip.uprightHeight].every(n=>Number.isInteger(n)&&n>0&&n<=8192),'Invalid upright dimensions');
    require(Array.isArray(clip.annotations),'Missing annotation array');orderedTimestamps(clip.annotations.map(a=>a.timestamp));
    for(const annotation of clip.annotations) {
      const t=annotation.timestamp;
      require(t&&typeof t.value==='string'&&/^-?\d+$/.test(t.value)&&Number.isInteger(t.timescale)&&t.timescale>0&&t.timescale<=2147483647&&Number.isInteger(t.epoch)&&t.epoch>=0,'Invalid actual timestamp');
      timestampKey(t);
      require(annotation.targetID===clip.targetID&&typeof clip.targetID==='string'&&clip.targetID,'Target identity mismatch');
      require(['visible','occluded','outside-frame','uncertain'].includes(annotation.visibility),'Invalid visibility');
      if(annotation.point!==null)require(annotation.point&&[annotation.point.x,annotation.point.y].every(n=>Number.isFinite(n)&&n>=0&&n<=1),'Invalid normalized reference');
      if(annotation.uncertaintyPixels!==null)require(Number.isFinite(annotation.uncertaintyPixels)&&annotation.uncertaintyPixels>=0,'Invalid uncertainty');
      if(annotation.visibility==='visible')require(annotation.point!==null&&annotation.uncertaintyPixels!==null,'Visible point needs reference uncertainty');
      require(annotation.provenance===(clip.synthetic?'synthetic-reference':'manual-reference'),'Synthetic/observed provenance mixed');
      if(clip.synthetic)synthetic++;else observed++;
    }
  }
  return {clips:ids.size,observedAnnotations:observed,syntheticAnnotations:synthetic,readiness:observed?'reference data present; evaluation still required':'no observed clips; accuracy unmeasured'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  const filename=process.argv[2]??fileURLToPath(new URL('../docs/video-fixture-manifest.json',import.meta.url));
  console.log(JSON.stringify(validateVideoManifest(JSON.parse(await readFile(filename,'utf8'))),null,2));
}
