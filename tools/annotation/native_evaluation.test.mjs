import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,readdir,rm,stat,cp} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import os from 'node:os';
import path from 'node:path';
import {evaluateNativeBundle} from './evaluate_native_bundle.mjs';

const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
// Synthetic shape/header fixture ONLY; actual Apple-produced bytes are a later gate.
async function fixture(root,{mediaName='generated.bin'}={}) {
  await mkdir(path.join(root,'frames'));
  const media=Buffer.from('Synthetic wrapper contract bytes, not a movie');
  await writeFile(path.join(root,mediaName),media);
  const png=Buffer.alloc(24);Buffer.from([137,80,78,71,13,10,26,10]).copy(png);png.writeUInt32BE(400,16);png.writeUInt32BE(200,20);
  const frames=[];
  for(let index=0;index<3;index++) {
    const id=`frame-${String(index).padStart(6,'0')}`;
    frames.push({id,filename:id+'.png',sha256:sha(png),timestamp:{value:String(index),timescale:30,epoch:0}});
    await writeFile(path.join(root,'frames',id+'.png'),png);
  }
  const clip={id:'generated-wrapper',sha256:sha(media),localPath:mediaName,sourceGroup:'synthetic-wrapper-group',split:'development',synthetic:true,
    permissionEvidence:'Generated contract only',lift:'synthetic',targetID:'near-side-hub',uprightWidth:400,uprightHeight:200};
  const predictions={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',modelID:'synthetic-wrapper-only',runs:[{
    clipID:clip.id,sha256:clip.sha256,synthetic:true,mode:'automatic',uprightWidth:400,uprightHeight:200,elapsedSeconds:0.1,
    samples:frames.map(f=>({timestamp:f.timestamp,point:null,confidence:0,kind:'lost',targetID:null}))}]};
  const predictionBytes=Buffer.from(JSON.stringify(predictions));await writeFile(path.join(root,'prediction.json'),predictionBytes);
  const ledger={schemaVersion:1,purpose:'native-analysis',nativeParityVerified:true,
    decoder:{name:'AVAssetImageGenerator',version:'synthetic-contract-only',transform:'preferred-track-transform',aperture:'clean-aperture',scale:'maximum-1024x1024',tolerance:'zero',frameSource:'same-native-analysis'},
    clip,frames,association:{analysisID:'11111111-1111-4111-8111-111111111111',captureSessionID:'22222222-2222-4222-8222-222222222222',
      predictionSHA256:sha(predictionBytes),modelID:predictions.modelID,mode:'automatic',rangeStart:0,rangeEnd:0.1,acceptedTimestamps:frames.map(f=>f.timestamp)}};
  const ledgerBytes=Buffer.from(JSON.stringify(ledger));await writeFile(path.join(root,'ledger.json'),ledgerBytes);
  const labels={schemaVersion:1,ledgerSha256:sha(ledgerBytes),viaMetadata:Object.fromEntries(frames.map(f=>[f.id,{filename:f.filename,size:-1,regions:[],file_attributes:{reviewStatus:'unreviewed',visibility:'',uncertaintyPixels:null}}]))};
  labels.viaMetadata[frames[0].id].regions=[{shape_attributes:{name:'point',cx:100,cy:150},region_attributes:{}}];
  labels.viaMetadata[frames[0].id].file_attributes={reviewStatus:'reviewed',visibility:'visible',uncertaintyPixels:2};
  labels.viaMetadata[frames[1].id].file_attributes={reviewStatus:'reviewed',visibility:'occluded',uncertaintyPixels:null};
  await writeFile(path.join(root,'labels.json'),JSON.stringify(labels));
  return {ledger,labels,predictions,ledgerBytes,predictionBytes,
    options:{ledgerFile:path.join(root,'ledger.json'),labelsFile:path.join(root,'labels.json'),assetRoot:root,output:path.join(root,'evaluated')}};
}

test('Portable root remains usable after source removal and supplementary receipt cannot bypass media verification',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'portable-native-contract-'));
  try {
    const source=path.join(root,'source'),saved=path.join(root,'saved');await mkdir(source);
    const mediaName='33333333-3333-4333-8333-333333333333.mov',f=await fixture(source,{mediaName});
    // Hand-built contract bytes, not Swift/AVFoundation output or a Files-provider save.
    await writeFile(path.join(source,'bundle.json'),JSON.stringify({ledger:f.ledger,ledgerText:f.ledgerBytes.toString(),ledgerSha256:sha(f.ledgerBytes)}));
    await writeFile(path.join(source,'export-receipt.json'),JSON.stringify({supplementary:true,sourceSHA256:f.ledger.clip.sha256}));
    const movie=await readFile(path.join(source,mediaName));
    await cp(source,saved,{recursive:true,errorOnExist:true,force:false});await rm(source,{recursive:true});
    const options={ledgerFile:path.join(saved,'ledger.json'),labelsFile:path.join(saved,'labels.json'),assetRoot:saved,output:path.join(root,'evaluated')};
    const result=await evaluateNativeBundle(options);
    assert.deepEqual(await readFile(path.join(saved,mediaName)),movie);
    assert.deepEqual(await readFile(path.join(result.output,'ledger.json')),f.ledgerBytes);
    assert.deepEqual(await readFile(path.join(result.output,'prediction.json')),f.predictionBytes);
    assert.equal(result.receipt.source.localPath,mediaName);assert.equal(result.score.reference.observedAnnotations,0);
    assert.equal(result.score.accuracyGatePassed,false);
    // The strict wrapper continues checking the actual movie, regardless of receipt claims.
    await writeFile(path.join(saved,mediaName),'changed movie');
    await writeFile(path.join(saved,'export-receipt.json'),JSON.stringify({sourceSHA256:sha(Buffer.from('changed movie'))}));
    const refused=path.join(root,'refused');await assert.rejects(evaluateNativeBundle({...options,output:refused}));
    await assert.rejects(stat(refused),{code:'ENOENT'});
    assert.deepEqual(await readFile(path.join(result.output,'ledger.json')),f.ledgerBytes);
  } finally {await rm(root,{recursive:true,force:true});}
});

test('Native wrapper binds exact verified buffers and derived references without accuracy promotion',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'native-evaluation-'));
  try {
    const f=await fixture(root),result=await evaluateNativeBundle(f.options);
    assert.equal(result.receipt.accuracyGatePassed,false);assert.equal(result.score.accuracyGatePassed,false);
    assert.equal(result.receipt.nativeAssociationChecked,true);assert.equal(result.receipt.source.sha256,f.ledger.clip.sha256);
    assert.equal(result.receipt.reviewed,2);assert.deepEqual(result.receipt.unreviewed,['frame-000002']);
    assert.deepEqual(await readFile(path.join(result.output,'ledger.json')),f.ledgerBytes);
    assert.deepEqual(await readFile(path.join(result.output,'prediction.json')),f.predictionBytes);
    const ref=JSON.parse(await readFile(path.join(result.output,'references.native-reference.json'),'utf8'));
    assert.deepEqual(ref.clips[0].annotations[0].point,{x:.25,y:.75});assert.equal(ref.clips[0].annotations[1].point,null);
    assert.equal(ref.clips[0].annotations[0].provenance,'synthetic-reference');assert.equal(result.score.reference.observedAnnotations,0);
    for(const [name,expected] of Object.entries(result.receipt.files)) {
      const bytes=await readFile(path.join(result.output,name));assert.equal(sha(bytes),expected.sha256);assert.equal(bytes.length,expected.bytes);
    }
    const saved=await readFile(path.join(result.output,'evaluation.json'));
    await assert.rejects(evaluateNativeBundle(f.options),/already exists/);
    assert.deepEqual(await readFile(path.join(result.output,'evaluation.json')),saved);
    assert.equal((await readdir(root)).some(name=>name.startsWith('.native-evaluation-partial-')),false);
    // A later modified artifact no longer matches its retained receipt, not origin authentication.
    const refPath=path.join(result.output,'references.native-reference.json');await writeFile(refPath,'{}');
    assert.notEqual(sha(await readFile(refPath)),result.receipt.files['references.native-reference.json'].sha256);
  } finally {await rm(root,{recursive:true,force:true});}
});

test('Producer/label/prediction/media/PNG substitutions never publish completed evaluations',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'native-refuse-'));
  try {
    const mutators={
      pyav:async f=>{f.ledger.purpose='development-only';f.ledger.nativeParityVerified=false;f.ledger.decoder={name:'PyAV',version:'fixture'};delete f.ledger.association;await writeFile(f.options.ledgerFile,JSON.stringify(f.ledger));},
      renamedDraft:async f=>{await writeFile(f.options.ledgerFile,JSON.stringify({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[]}));},
      labels:async f=>{f.labels.ledgerSha256='0'.repeat(64);await writeFile(f.options.labelsFile,JSON.stringify(f.labels));},
      prediction:async f=>{await writeFile(path.join(f.options.assetRoot,'prediction.json'),'{}');},
      media:async f=>{await writeFile(path.join(f.options.assetRoot,'generated.bin'),'changed');},
      png:async f=>{await writeFile(path.join(f.options.assetRoot,'frames','frame-000000.png'),'changed');},
      components:async f=>{f.predictions.runs[0].samples[1].timestamp={value:'2',timescale:60,epoch:0};const bytes=Buffer.from(JSON.stringify(f.predictions));f.ledger.association.predictionSHA256=sha(bytes);await writeFile(path.join(f.options.assetRoot,'prediction.json'),bytes);await writeFile(f.options.ledgerFile,JSON.stringify(f.ledger));},
    };
    for(const [name,mutate] of Object.entries(mutators)) {
      const caseRoot=path.join(root,name);await mkdir(caseRoot);const f=await fixture(caseRoot);await mutate(f);
      await assert.rejects(evaluateNativeBundle(f.options));await assert.rejects(stat(f.options.output),{code:'ENOENT'});
      assert.equal((await readdir(caseRoot)).some(n=>n.startsWith('.native-evaluation-partial-')),false);
    }
  } finally {await rm(root,{recursive:true,force:true});}
});

test('Wrapper keeps registry partition checks and bounded strict JSON reads',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'native-partition-'));
  try {
    const f=await fixture(root),prior={...f.ledger.clip,id:'prior',split:'holdout',annotations:[]};
    const registry=path.join(root,'registry.json');await writeFile(registry,JSON.stringify({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[prior]}));
    await assert.rejects(evaluateNativeBundle({...f.options,existingFile:registry}),/partitions/);
    await writeFile(f.options.labelsFile,Buffer.alloc(4*1024*1024+1));await assert.rejects(evaluateNativeBundle(f.options),/bound/);
    await writeFile(f.options.labelsFile,'{"schemaVersion":1,"schemaVersion":1}');await assert.rejects(evaluateNativeBundle(f.options),/Duplicate JSON key/);
    await assert.rejects(stat(f.options.output),{code:'ENOENT'});
  } finally {await rm(root,{recursive:true,force:true});}
});

test('Strict native CLI offers no renamed-manifest or purpose bypass and creates one bound output',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'native-cli-'));
  try {
    const f=await fixture(root),run=promisify(execFile),script=fileURLToPath(new URL('./evaluate_native_bundle.mjs',import.meta.url));
    const args=[script,'--ledger',f.options.ledgerFile,'--labels',f.options.labelsFile,'--asset-root',root,'--output',f.options.output];
    for(const extra of [['--manifest',f.options.ledgerFile],['--purpose','development'],['--ledger',f.options.ledgerFile]])
      await assert.rejects(run(process.execPath,[...args,...extra],{timeout:30_000}),/unique --ledger/);
    await assert.rejects(stat(f.options.output),{code:'ENOENT'});
    const result=JSON.parse((await run(process.execPath,args,{timeout:30_000})).stdout);
    assert.equal(result.nativeAssociationChecked,true);assert.equal(result.accuracyGatePassed,false);
    assert.equal(result.referenceSHA256,sha(await readFile(path.join(f.options.output,'references.native-reference.json'))));
  } finally {await rm(root,{recursive:true,force:true});}
});
