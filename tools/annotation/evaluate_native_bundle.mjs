import {open,lstat,mkdir,realpath,rename,rm,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {adaptLabels,digest,parseStrictJSON,validateLedger,verifyAssets,verifyNativePrediction} from './adapt_labels.mjs';
import {scoreVideoTraces} from '../score-video-traces.mjs';

const require=(ok,message)=>{if(!ok)throw Error(message);};
const jsonBytes=value=>Buffer.from(JSON.stringify(value,null,2)+'\n');
async function absent(filename) {
  try { await lstat(filename);throw Error('Evaluation destination already exists'); }
  catch(error) { if(error.code!=='ENOENT')throw error; }
}
async function snapshot(filename,limit,check) {
  check();const handle=await open(filename,'r'),controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),60_000);
  try {
    const before=await handle.stat();
    require(before.isFile()&&before.size>0&&before.size<=limit,'JSON input exceeds regular-file/byte bound');
    const chunks=[];let count=0;
    for await(const chunk of handle.createReadStream({autoClose:false,highWaterMark:128*1024,signal:controller.signal})) {
      check();count+=chunk.length;require(count<=limit,'JSON input exceeds byte bound');chunks.push(chunk);
    }
    const after=await handle.stat();
    require(count===before.size&&after.size===before.size&&after.mtimeMs===before.mtimeMs,'JSON input changed during read');
    check();return Buffer.concat(chunks,count);
  } finally {clearTimeout(timer);await handle.close();}
}

/** Strict additional native path. Generic scorer schemas/diagnostics remain unchanged. */
export async function evaluateNativeBundle({ledgerFile,labelsFile,assetRoot,output,existingFile}) {
  for(const filename of [ledgerFile,labelsFile,assetRoot,output,...(existingFile?[existingFile]:[])])
    require(typeof filename==='string'&&filename.length>0&&!filename.includes('\0')&&!/^(?:https?:|file:)/i.test(filename),'Explicit local paths required');
  const began=performance.now(),check=()=>require(performance.now()-began<120_000,'Native evaluation exceeded cooperative 120s budget');
  const requested=path.resolve(output),parent=await realpath(path.dirname(requested));
  const destination=path.join(parent,path.basename(requested));
  await absent(destination);
  const ledgerBytes=await snapshot(ledgerFile,1024*1024,check);
  const ledger=validateLedger(parseStrictJSON(ledgerBytes.toString('utf8')));
  require(ledger.purpose==='native-analysis','Strict native evaluation refuses development producers');
  const labelsBytes=await snapshot(labelsFile,4*1024*1024,check);
  const labels=parseStrictJSON(labelsBytes.toString('utf8'));
  const existingBytes=existingFile?await snapshot(existingFile,32*1024*1024,check):null;
  const existing=existingBytes?parseStrictJSON(existingBytes.toString('utf8')):undefined;
  check();
  const predictionBytes=await verifyAssets(ledger,path.dirname(path.resolve(ledgerFile)),assetRoot);
  check();const predictions=verifyNativePrediction(ledger,predictionBytes);
  const adapted=adaptLabels(ledger,digest(ledgerBytes),labels,{purpose:'native-scoring',predictionBytes,existing});
  const referenceBytes=jsonBytes(adapted.manifest),adapterBytes=jsonBytes(adapted.report);
  const score=scoreVideoTraces(adapted.manifest,predictions);
  require(score.accuracyGatePassed===false,'Native wrapper cannot promote accuracy readiness');
  score.createdAt=new Date().toISOString();
  score.limits+=' Strict wrapper verified actual source/PNG bytes and exact native prediction association; hashes are not origin signatures. Keep evaluation.json with this score.';
  const scoreBytes=jsonBytes(score);
  const files=new Map([
    ['ledger.json',ledgerBytes],['prediction.json',predictionBytes],['references.native-reference.json',referenceBytes],
    ['references.native-reference.json.report.json',adapterBytes],['score.json',scoreBytes],
  ]);
  const clip=ledger.clip;
  const receipt={schemaVersion:1,kind:'native-evaluation',nativeAssociationChecked:true,accuracyGatePassed:false,
    createdAt:score.createdAt,files:Object.fromEntries([...files].map(([name,bytes])=>[name,{sha256:digest(bytes),bytes:bytes.length}])),
    inputLabelsSHA256:digest(labelsBytes),existingRegistrySHA256:existingBytes?digest(existingBytes):null,
    source:{clipID:clip.id,sha256:clip.sha256,localPath:clip.localPath,sourceGroup:clip.sourceGroup,split:clip.split,
      synthetic:clip.synthetic,uprightWidth:clip.uprightWidth,uprightHeight:clip.uprightHeight},
    association:ledger.association,reviewed:adapted.report.reviewed,unreviewed:adapted.report.unreviewed,
    policy:score.policy,limits:'Trusted local filesystem. Input/output byte association, not producer authentication, whole-rep coverage or accuracy acceptance.'};
  files.set('evaluation.json',jsonBytes(receipt));
  require([...files.values()].reduce((total,bytes)=>total+bytes.length,0)<=8*1024*1024,'Evaluation output exceeds 8MiB bound');
  const staging=path.join(parent,'.native-evaluation-partial-'+randomUUID());
  require(path.dirname(staging)===parent&&path.basename(staging).startsWith('.native-evaluation-partial-'),'Invalid owned staging path');
  let owned=false,published=false;
  try {
    check();await mkdir(staging);owned=true;
    for(const [name,bytes] of files) {check();await writeFile(path.join(staging,name),bytes,{flag:'wx'});}
    check();await absent(destination);await rename(staging,destination);published=true;
    return {output:destination,receipt,score};
  } finally {
    // Only our verified fresh sibling is eligible for cleanup, never destination.
    if(owned&&!published)await rm(staging,{recursive:true,force:true});
  }
}

async function main() {
  const allowed=new Set(['ledger','labels','asset-root','output','existing']),options={};
  for(let index=2;index<process.argv.length;index+=2) {
    const key=process.argv[index].replace(/^--/,'');
    require(process.argv[index]==='--'+key&&allowed.has(key)&&!Object.hasOwn(options,key)&&process.argv[index+1],'Use unique --ledger --labels --asset-root --output and optional --existing');
    options[key]=process.argv[index+1];
  }
  const result=await evaluateNativeBundle({ledgerFile:options.ledger,labelsFile:options.labels,assetRoot:options['asset-root'],output:options.output,existingFile:options.existing});
  console.log(JSON.stringify({output:result.output,nativeAssociationChecked:true,accuracyGatePassed:false,
    referenceSHA256:result.receipt.files['references.native-reference.json'].sha256,predictionSHA256:result.receipt.files['prediction.json'].sha256,
    reviewed:result.receipt.reviewed,unreviewed:result.receipt.unreviewed},null,2));
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)main().catch(error=>{console.error(error.message);process.exitCode=1;});
