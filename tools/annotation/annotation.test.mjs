import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,mkdir,rm,stat} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';
import {adaptLabels,validateLedger,verifyAssets,verifyNativePrediction,digest,parseStrictJSON} from './adapt_labels.mjs';

function fixture() {
  const clip={id:'synthetic-ui-test',sourceGroup:'synthetic-fixture',sha256:'a'.repeat(64),localPath:'synthetic.bin',split:'development',synthetic:true,
    permissionEvidence:'Generated synthetic test only',lift:'synthetic',targetID:'near-side-hub',uprightWidth:400,uprightHeight:200};
  const frames=[0,1,2].map(i=>({id:`frame-00000${i}`,filename:`frame-00000${i}.png`,sha256:'b'.repeat(64),timestamp:{value:String(9007199254740993n+BigInt(i)),timescale:600,epoch:0}}));
  const ledger={schemaVersion:1,purpose:'development-only',nativeParityVerified:false,decoder:{name:'PyAV',version:'synthetic-test'},clip,frames};
  const labels={schemaVersion:1,ledgerSha256:'c'.repeat(64),viaMetadata:Object.fromEntries(frames.map(f=>[f.id,{filename:f.filename,size:-1,regions:[],file_attributes:{reviewStatus:'unreviewed',visibility:'',uncertaintyPixels:null}}]))};
  const m=labels.viaMetadata[frames[0].id];m.regions=[{shape_attributes:{name:'point',cx:100,cy:150},region_attributes:{}}];m.file_attributes={reviewStatus:'reviewed',visibility:'visible',uncertaintyPixels:2};
  const nonvisible=labels.viaMetadata[frames[1].id];nonvisible.file_attributes={reviewStatus:'reviewed',visibility:'occluded',uncertaintyPixels:null};
  return {ledger,labels};
}
test('Original pixels normalize without time rounding; occlusion and unreviewed remain explicit',()=>{
  const {ledger,labels}=fixture();const result=adaptLabels(ledger,labels.ledgerSha256,labels);
  assert.deepEqual(result.manifest.clips[0].annotations[0].point,{x:.25,y:.75});
  assert.equal(result.manifest.clips[0].annotations[0].timestamp.value,'9007199254740993');
  assert.equal(result.manifest.clips[0].annotations[1].point,null);
  assert.deepEqual(result.report.unreviewed,['frame-000002']);assert.equal(result.report.nativeParityVerified,false);
});

// Hand-built contract fixtures are synthetic; they do not execute the Apple producer.
function nativeFixture() {
  const f=fixture();
  f.ledger.purpose='native-analysis';f.ledger.nativeParityVerified=true;
  f.ledger.decoder={name:'AVAssetImageGenerator',version:'synthetic-contract-only',transform:'preferred-track-transform',aperture:'clean-aperture',scale:'maximum-1024x1024',tolerance:'zero',frameSource:'same-native-analysis'};
  for(let i=0;i<f.ledger.frames.length;i++)f.ledger.frames[i].timestamp={value:String(i),timescale:30,epoch:0};
  f.predictions={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',modelID:'synthetic-contract',runs:[{
    clipID:f.ledger.clip.id,sha256:f.ledger.clip.sha256,mode:'automatic',synthetic:true,uprightWidth:400,uprightHeight:200,elapsedSeconds:0.1,
    samples:f.ledger.frames.map(frame=>({timestamp:structuredClone(frame.timestamp),point:null,confidence:0,kind:'lost',targetID:null}))}]};
  f.predictionBytes=Buffer.from(JSON.stringify(f.predictions));
  f.ledger.association={analysisID:'11111111-1111-4111-8111-111111111111',captureSessionID:'22222222-2222-4222-8222-222222222222',
    predictionSHA256:digest(f.predictionBytes),modelID:f.predictions.modelID,mode:'automatic',rangeStart:0,rangeEnd:0.1,
    acceptedTimestamps:f.ledger.frames.map(frame=>structuredClone(frame.timestamp))};
  return f;
}
test('Synthetic native contract binds exact prediction bytes and exports distinct provenance',()=>{
  const f=nativeFixture();
  const r=adaptLabels(f.ledger,f.labels.ledgerSha256,f.labels,{purpose:'native-scoring',predictionBytes:f.predictionBytes});
  assert.equal(r.report.purpose,'native-scoring');assert.equal(r.report.nativeParityVerified,true);
  assert.equal(r.report.predictionSHA256,digest(f.predictionBytes));assert.equal(r.manifest.clips[0].annotations[0].timestamp.value,'0');
  assert.throws(()=>adaptLabels(f.ledger,f.labels.ledgerSha256,f.labels,{purpose:'native-scoring'}),/bytes required/);
});
test('Setting a PyAV parity flag cannot create a native producer',()=>{
  const f=fixture();f.ledger.nativeParityVerified=true;
  assert.throws(()=>validateLedger(f.ledger));f.ledger.purpose='native-analysis';assert.throws(()=>validateLedger(f.ledger));
});
const nativeRejects={
  'decoder transform':f=>{f.ledger.decoder.transform='none';},
  'analysis identity format':f=>{f.ledger.association.analysisID='foreign';},
  'capture identity format':f=>{f.ledger.association.captureSessionID='foreign';},
  'native range':f=>{f.ledger.association.rangeEnd=2;},
  'native geometry cap':f=>{f.ledger.clip.uprightWidth=1025;},
  'accepted component substitution':f=>{f.ledger.association.acceptedTimestamps[1]={value:'2',timescale:60,epoch:0};},
  'accepted count':f=>{f.ledger.association.acceptedTimestamps.pop();},
  'foreign model':f=>{f.ledger.association.modelID='other';},
  'foreign mode':f=>{f.ledger.association.mode='manual-vision';},
  'prediction digest':f=>{f.ledger.association.predictionSHA256='0'.repeat(64);},
  'foreign prediction clip':f=>{f.predictions.runs[0].clipID='other';},
  'foreign prediction geometry':f=>{f.predictions.runs[0].uprightHeight=201;},
  'foreign prediction count':f=>{f.predictions.runs[0].samples.pop();},
  'prediction component substitution':f=>{f.predictions.runs[0].samples[1].timestamp={value:'2',timescale:60,epoch:0};},
};
for(const [name,mutate] of Object.entries(nativeRejects))test('Reject '+name,()=>{
  const f=nativeFixture();mutate(f);
  if(name.startsWith('foreign prediction')||name==='prediction component substitution') {
    f.predictionBytes=Buffer.from(JSON.stringify(f.predictions));f.ledger.association.predictionSHA256=digest(f.predictionBytes);
  }
  assert.throws(()=>verifyNativePrediction(f.ledger,f.predictionBytes));
});
test('Native verification reads the actual adjacent prediction file and enforces its byte bound',async()=>{
  const dir=await mkdtemp(path.join(os.tmpdir(),'hub-native-'));
  try {
    const f=nativeFixture(),media=Buffer.from('synthetic contract bytes only');f.ledger.clip.sha256=digest(media);f.predictions.runs[0].sha256=digest(media);
    f.predictionBytes=Buffer.from(JSON.stringify(f.predictions));f.ledger.association.predictionSHA256=digest(f.predictionBytes);
    await writeFile(path.join(dir,'synthetic.bin'),media);await mkdir(path.join(dir,'frames'));
    const png=Buffer.alloc(24);Buffer.from([137,80,78,71,13,10,26,10]).copy(png);png.writeUInt32BE(400,16);png.writeUInt32BE(200,20);
    for(const frame of f.ledger.frames){frame.sha256=digest(png);await writeFile(path.join(dir,'frames',frame.filename),png);}
    const predictionPath=path.join(dir,'prediction.json');await writeFile(predictionPath,f.predictionBytes);
    assert.deepEqual(await verifyAssets(f.ledger,dir,dir),f.predictionBytes);
    const ledgerBytes=Buffer.from(JSON.stringify(f.ledger));f.labels.ledgerSha256=digest(ledgerBytes);
    const ledgerPath=path.join(dir,'ledger.json'),labelsPath=path.join(dir,'labels.json'),output=path.join(dir,'references.native-reference.json');
    await writeFile(ledgerPath,ledgerBytes);await writeFile(labelsPath,JSON.stringify(f.labels));
    const args=[fileURLToPath(new URL('./adapt_labels.mjs',import.meta.url)),'--ledger',ledgerPath,'--labels',labelsPath,
      '--asset-root',dir,'--purpose','native-scoring','--output',output];
    const run=promisify(execFile);
    await run(process.execPath,args,{timeout:30_000});
    const report=JSON.parse(await readFile(output+'.report.json','utf8'));
    assert.equal(report.purpose,'native-scoring');assert.equal(report.syntheticAnnotations,2);
    const original=await readFile(output);
    await assert.rejects(run(process.execPath,args,{timeout:30_000}),/EEXIST/);
    assert.deepEqual(await readFile(output),original);
    await writeFile(predictionPath,Buffer.from('{}'));await assert.rejects(verifyAssets(f.ledger,dir,dir),/hash changed/);
    const invalidOutput=path.join(dir,'changed.native-reference.json');
    await assert.rejects(run(process.execPath,[...args.slice(0,-1),invalidOutput],{timeout:30_000}),/hash changed/);
    await assert.rejects(stat(invalidOutput),{code:'ENOENT'});
    await assert.rejects(stat(invalidOutput+'.report.json'),{code:'ENOENT'});
    await writeFile(predictionPath,Buffer.alloc(1024*1024+1));await assert.rejects(verifyAssets(f.ledger,dir,dir),/exceeds bound/);
  } finally {await rm(dir,{recursive:true,force:true});}
});
const rejects={
  'foreign ledger':({labels})=>{labels.ledgerSha256='d'.repeat(64);},
  'missing frame':({labels})=>{delete labels.viaMetadata['frame-000002'];},
  'foreign frame':({labels})=>{labels.viaMetadata.foreign={};},
  'duplicate frame':({ledger})=>{ledger.frames[1]=structuredClone(ledger.frames[0]);},
  'duplicate rational PTS':({ledger})=>{ledger.frames[1].timestamp={value:String(9007199254740993n*2n),timescale:1200,epoch:0};},
  'unsafe timestamp Number':({ledger})=>{ledger.frames[0].timestamp.value=9007199254740993;},
  'unsupported epoch':({ledger})=>{ledger.frames[0].timestamp.epoch=1;},
  'ambiguous multiple points':({labels})=>{labels.viaMetadata['frame-000000'].regions.push(structuredClone(labels.viaMetadata['frame-000000'].regions[0]));},
  'non-point shape':({labels})=>{labels.viaMetadata['frame-000000'].regions[0].shape_attributes.name='circle';},
  'out of bounds':({labels})=>{labels.viaMetadata['frame-000000'].regions[0].shape_attributes.cx=400;},
  'zero uncertainty':({labels})=>{labels.viaMetadata['frame-000000'].file_attributes.uncertaintyPixels=0;},
  'coerced uncertainty':({labels})=>{labels.viaMetadata['frame-000000'].file_attributes.uncertaintyPixels='2';},
  'nonvisible stale point':({labels})=>{labels.viaMetadata['frame-000001'].regions=structuredClone(labels.viaMetadata['frame-000000'].regions);},
  'unknown editable metadata':({labels})=>{labels.viaMetadata['frame-000000'].file_attributes.timestamp='fake';},
  'foreign filename':({labels})=>{labels.viaMetadata['frame-000000'].filename='other.png';},
  'unreviewed foreign shape':({labels})=>{labels.viaMetadata['frame-000002'].regions=[{shape_attributes:{name:'circle',cx:10,cy:10},region_attributes:{}}];},
  'unreviewed invalid visibility':({labels})=>{labels.viaMetadata['frame-000002'].file_attributes.visibility='guessed';},
  'path traversal':({ledger})=>{ledger.clip.localPath='../outside.mp4';},
};
for(const [name,mutate] of Object.entries(rejects))test('Reject '+name,()=>{
  const f=fixture(),expectedHash=f.labels.ledgerSha256;mutate(f);assert.throws(()=>adaptLabels(f.ledger,expectedHash,f.labels));
});
test('Refuses native-scoring purpose',()=>{const f=fixture();assert.throws(()=>adaptLabels(f.ledger,f.labels.ledgerSha256,f.labels,{purpose:'native-scoring'}),/native scoring refused/);});
test('Rejects duplicate JSON object keys including escaped equivalents',()=>{
  assert.throws(()=>parseStrictJSON('{"viaMetadata":{"frame-000000":1,"frame-000000":2}}'),/Duplicate JSON key/);
  assert.throws(()=>parseStrictJSON('{"value":1,"\\u0076alue":2}'),/Duplicate JSON key/);
  assert.deepEqual(parseStrictJSON('{"one":{"value":"quote\\\""},"two":[{"value":2},null,true]}'),{one:{value:'quote"'},two:[{value:2},null,true]});
});
test('Rejects held-out source-group and media-hash partition leakage',()=>{
  const f=fixture();for(const same of ['sourceGroup','sha256']){
    const prior={...f.ledger.clip,id:'prior',sourceGroup:'different',sha256:'d'.repeat(64),split:'holdout',annotations:[]};prior[same]=f.ledger.clip[same];
    assert.throws(()=>adaptLabels(f.ledger,f.labels.ledgerSha256,f.labels,{existing:{schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[prior]}}),/partitions/);
  }
});
test('Checks actual image/media bytes and PNG dimensions',async()=>{
  const dir=await mkdtemp(path.join(os.tmpdir(),'hub-adapter-'));
  try {
    const {ledger}=fixture();ledger.frames=[ledger.frames[0]];
    const media=Buffer.from('Synthetic bytes, not a real video');ledger.clip.sha256=digest(media);await writeFile(path.join(dir,'synthetic.bin'),media);
    await mkdir(path.join(dir,'frames'));const png=Buffer.alloc(24);Buffer.from([137,80,78,71,13,10,26,10]).copy(png);png.writeUInt32BE(400,16);png.writeUInt32BE(200,20);
    ledger.frames[0].sha256=digest(png);const image=path.join(dir,'frames',ledger.frames[0].filename);await writeFile(image,png);
    await verifyAssets(ledger,dir,dir);
    await writeFile(image,Buffer.from('changed'));await assert.rejects(verifyAssets(ledger,dir,dir),/Image hash changed/);
    await writeFile(image,png);await writeFile(path.join(dir,'synthetic.bin'),'changed');await assert.rejects(verifyAssets(ledger,dir,dir),/Media hash changed/);
    await writeFile(path.join(dir,'synthetic.bin'),media);png.writeUInt32BE(399,16);ledger.frames[0].sha256=digest(png);await writeFile(image,png);await assert.rejects(verifyAssets(ledger,dir,dir),/geometry/);
  } finally {await rm(dir,{recursive:true,force:true});}
});
