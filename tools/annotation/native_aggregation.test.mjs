import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm,readdir,stat,cp} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import path from 'node:path';
import os from 'node:os';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {digest} from './adapt_labels.mjs';
import {evaluateNativeBundle} from './evaluate_native_bundle.mjs';
import {aggregateNativeWindows} from './aggregate_native_windows.mjs';
import {timestampKey} from '../validate-video-manifest.mjs';

const t=(value,scale=30)=>({value:String(value),timescale:scale,epoch:0});
const movie=Buffer.from('Generated registry contract bytes only; not a video');
async function window(root,id,{start=10,scale=30,values=[start*scale,start*scale+1,start*scale+2],mode='automatic',model='synthetic-model-a',raster=0,reviews=['visible','occluded','unreviewed'],point=100,sourceName='generated.bin',predicted=false,decoderVersion='synthetic-contract-only',permissionEvidence='Generated contracts only'}={}) {
  const dir=path.join(root,id);await mkdir(path.join(dir,'frames'),{recursive:true});
  await writeFile(path.join(dir,sourceName),movie);
  // Header-shaped synthetic contract bytes; not a decoder/PNG-validity claim.
  const png=Buffer.alloc(25);Buffer.from([137,80,78,71,13,10,26,10]).copy(png);png.writeUInt32BE(400,16);png.writeUInt32BE(200,20);png[24]=raster;
  const frames=values.map((v,i)=>({id:`frame-${String(i).padStart(6,'0')}`,filename:`frame-${String(i).padStart(6,'0')}.png`,sha256:digest(png),timestamp:t(v,scale)}));
  for(const f of frames)await writeFile(path.join(dir,'frames',f.filename),png);
  const clip={id,sha256:digest(movie),localPath:sourceName,sourceGroup:'synthetic-recording-group',split:'development',synthetic:true,permissionEvidence,lift:'synthetic',targetID:'near-side-hub',uprightWidth:400,uprightHeight:200};
  const prediction={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',modelID:model,runs:[{clipID:id,sha256:clip.sha256,synthetic:true,mode,uprightWidth:400,uprightHeight:200,elapsedSeconds:.1,
    samples:frames.map(f=>({timestamp:f.timestamp,point:predicted?{x:.25,y:.75}:null,confidence:predicted?.9:0,kind:predicted?(mode==='automatic'?'automatic':'tracked'):'lost',targetID:predicted?'local-track-1':null}))}]};
  const predictionBytes=Buffer.from(JSON.stringify(prediction));await writeFile(path.join(dir,'prediction.json'),predictionBytes);
  const ledger={schemaVersion:1,purpose:'native-analysis',nativeParityVerified:true,decoder:{name:'AVAssetImageGenerator',version:decoderVersion,transform:'preferred-track-transform',aperture:'clean-aperture',scale:'maximum-1024x1024',tolerance:'zero',frameSource:'same-native-analysis'},clip,frames,
    association:{analysisID:randomUUID(),captureSessionID:randomUUID(),predictionSHA256:digest(predictionBytes),modelID:model,mode,rangeStart:start,rangeEnd:start+.1,acceptedTimestamps:frames.map(f=>f.timestamp)}};
  const ledgerBytes=Buffer.from(JSON.stringify(ledger));await writeFile(path.join(dir,'ledger.json'),ledgerBytes);
  const labels={schemaVersion:1,ledgerSha256:digest(ledgerBytes),viaMetadata:Object.fromEntries(frames.map((f,i)=>{
    const visibility=reviews[i]??'unreviewed',visible=visibility==='visible',reviewed=visibility!=='unreviewed';
    return [f.id,{filename:f.filename,size:-1,regions:visible?[{shape_attributes:{name:'point',cx:point,cy:150},region_attributes:{}}]:[],file_attributes:{reviewStatus:reviewed?'reviewed':'unreviewed',visibility:reviewed?visibility:'',uncertaintyPixels:visible?2:null}}];
  }))};await writeFile(path.join(dir,'labels.json'),JSON.stringify(labels));
  await evaluateNativeBundle({ledgerFile:path.join(dir,'ledger.json'),labelsFile:path.join(dir,'labels.json'),assetRoot:dir,output:path.join(dir,'evaluated')});
  return {id,ledger:path.join(dir,'ledger.json'),labels:path.join(dir,'labels.json'),assetRoot:dir,evaluation:path.join(dir,'evaluated','evaluation.json')};
}
async function setup(options=[{},{}]) {
  const root=await mkdtemp(path.join(os.tmpdir(),'native-aggregate-'));
  try {
    const windows=[];for(let i=0;i<options.length;i++)windows.push(await window(root,'window-'+i,options[i]));
    const plan={schemaVersion:1,kind:'native-window-plan',repID:'generated-rep',recordingSHA256:digest(movie),interval:{start:t(300),end:t(390)},windows};
    const planFile=path.join(root,'plan.json'),output=path.join(root,'aggregated');await writeFile(planFile,JSON.stringify(plan));
    return {root,plan,planFile,output,save:()=>writeFile(planFile,JSON.stringify(plan)),run:extra=>aggregateNativeWindows({planFile,output,...extra})};
  } catch(e){await rm(root,{recursive:true,force:true});throw e;}
}
async function temporary(options,body) {
  const f=await setup(options);
  try {await body(f);}
  finally {
    if(process.env.AGGREGATION_TEST_EVIDENCE_DIR) {
      try {
        const evidence=path.resolve(process.env.AGGREGATION_TEST_EVIDENCE_DIR,path.basename(f.root));
        for(const name of ['registry.json','aggregation.json','aggregation-receipt.json']) {
          const filename=path.join(f.output,name),size=(await stat(filename)).size;
          assert.ok(size<=8*1024*1024);await mkdir(evidence,{recursive:true});await writeFile(path.join(evidence,name),await readFile(filename));
        }
      } catch(error){if(error.code!=='ENOENT')throw error;}
    }
    await rm(f.root,{recursive:true,force:true});
  }
}

test('Disjoint nonzero windows preserve absolute PTS, gaps, unreviewed counts and unknown groups',async()=>temporary([{}, {start:12}],async f=>{
  const result=await f.run(),a=result.aggregation;
  assert.equal(result.receipt.kind,'native-window-aggregation');assert.equal(a.accuracyGatePassed,false);assert.equal(a.scalarMetrics,null);
  assert.equal(a.counts.distinctDecodedTimestamps,6);assert.equal(a.counts.reviewedUniqueTimestamps,4);assert.equal(a.counts.unreviewedUniqueTimestamps,2);assert.equal(a.counts.observedReviewedUniqueTimestamps,0);
  assert.deepEqual(a.timestamps[0].rows[0].timestamp,t(300));assert.equal(a.seams[0].sharedDecodedTimestamps,0);assert.equal(a.seams[0].continuity,'unverified');
  assert.deepEqual(a.declaredRequestCoverage.gaps[0],{start:{numerator:'101',denominator:'10'},end:{numerator:'12',denominator:'1'}});
  const registry=JSON.parse(await readFile(path.join(result.output,'registry.json')));assert.equal(registry.groups.reviewStatus,'unknown');assert.equal(registry.groups.subjectGroupID,null);
  for(const [name,descriptor] of Object.entries(result.receipt.files)){const bytes=await readFile(path.join(result.output,name));assert.equal(descriptor.sha256,digest(bytes));assert.equal(descriptor.bytes,bytes.length);}
  assert.equal(result.receipt.mediaReadBytes,2*result.receipt.counts.distinctMediaBytes);
}));

test('Identical reviewed overlaps count once; unreviewed overlaps do not inherit labels',async()=>temporary([{},{}],async f=>{
  f.plan.expectedOverlaps=[{windows:['window-0','window-1'],interval:{start:t(300),end:t(302)}}];await f.save();
  const result=await f.run(),a=result.aggregation;
  assert.equal(a.counts.distinctDecodedTimestamps,3);assert.equal(a.counts.reviewedUniqueTimestamps,2);assert.equal(a.counts.unreviewedUniqueTimestamps,1);
  assert.equal(a.timestamps[0].identicalReviewedDuplicate,true);assert.equal(a.timestamps[2].referenceState,'unreviewed');assert.equal(a.timestamps[2].rows.length,2);
  assert.equal(a.expectedOverlaps[0].sharedDecodedTimestamps,3);assert.equal(a.expectedOverlaps[0].continuity,'unverified');
}));

test('Equivalent rational tuples, raster/geometry and reference disagreement preserve every conflict row',async()=>{
  for(const [options,reason] of [[{scale:60,values:[600,602,604]},'component-tuples'],[{raster:1},'raster-bytes'],[{decoderVersion:'other-synthetic-decoder'},'geometry-decoder'],[{point:101},'reference-review'],[{reviews:['unreviewed','occluded','unreviewed']},'reference-review']])
    await temporary([{},options],async f=>{const result=await f.run(),a=result.aggregation;assert.equal(a.counts.distinctDecodedTimestamps,3);assert.ok(a.timestamps[0].conflicts.includes(reason));assert.equal(a.timestamps[0].rows.length,2);assert.equal(a.scalarMetrics,null);assert.equal(a.timestamps[0].referenceState,'conflict');});
} );

test('Predictions remain mode/model separated and local track identity never proves continuity',async()=>temporary([{}, {predicted:true}, {predicted:true,model:'synthetic-model-b'}, {predicted:true,mode:'manual-vision'}],async f=>{
  const a=(await f.run()).aggregation,comparisons=a.timestamps[0].predictionComparisons;
  assert.equal(comparisons.length,3);assert.equal(comparisons.find(c=>c.modelID==='synthetic-model-a'&&c.mode==='automatic').stateDisagreement,true);
  assert.ok(comparisons.every(c=>c.crossWindowTrackIdentity==='unverified'));assert.equal(a.counts.conflictedUniqueTimestamps,0);assert.equal(a.scalarMetrics,null);
}));

test('Copied byte-identical original windows deduplicate, while changed original identity refuses',async()=>temporary([{}],async f=>{
  const copy=path.join(f.root,'copied');await cp(f.plan.windows[0].assetRoot,copy,{recursive:true,errorOnExist:true,force:false});
  f.plan.windows.push({...f.plan.windows[0],id:'copied',ledger:path.join(copy,'ledger.json'),labels:path.join(copy,'labels.json'),assetRoot:copy,evaluation:path.join(copy,'evaluated','evaluation.json')});await f.save();
  const r=await f.run();assert.equal(r.receipt.counts.selectedWindows,2);assert.equal(r.receipt.counts.uniqueWindows,1);assert.equal(r.aggregation.counts.distinctDecodedTimestamps,3);
  const registry=JSON.parse(await readFile(path.join(r.output,'registry.json')));assert.equal(registry.windows[1].duplicateOf,'window-0');assert.equal(r.receipt.media.length,2);
}));

test('Same recording with different basenames and an explicit shared source root stays one hash group',async()=>temporary([{sourceName:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.mov'}, {sourceName:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.mov'}],async f=>{
  const common=path.join(f.root,'media');await mkdir(common);
  for(const w of f.plan.windows){const ledger=JSON.parse(await readFile(w.ledger));await writeFile(path.join(common,ledger.clip.localPath),movie);w.assetRoot=common;}await f.save();
  const r=await f.run();assert.equal(r.receipt.media.length,2);assert.equal(r.receipt.recordingSHA256,digest(movie));assert.equal(r.aggregation.counts.reviewedUniqueTimestamps,2);
}));

test('Existing registry catches hash/group split leakage and authoritative100-clip bound',async()=>temporary([{}],async f=>{
  const ledger=JSON.parse(await readFile(f.plan.windows[0].ledger)),existingFile=path.join(f.root,'existing.json');
  const prior={...ledger.clip,id:'prior',split:'holdout',annotations:[]};
  await writeFile(existingFile,JSON.stringify({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[prior]}));await assert.rejects(f.run({existingFile}),/partitions/);
  const clips=Array.from({length:100},(_,i)=>({...ledger.clip,id:'prior-'+i,annotations:[]}));await writeFile(existingFile,JSON.stringify({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips}));
  await assert.rejects(f.run({existingFile}),/authoritative100-clip/);await assert.rejects(stat(f.output),{code:'ENOENT'});
}));

test('Changed receipt, score, source and labels never publish or overwrite prior output',async()=>{
  const mutators={receipt:async f=>{const p=f.plan.windows[0].evaluation,x=JSON.parse(await readFile(p));x.nativeAssociationChecked=false;await writeFile(p,JSON.stringify(x));},
    score:async f=>{const w=f.plan.windows[0],p=path.join(path.dirname(w.evaluation),'score.json');await writeFile(p,'{}');},
    source:async f=>{await writeFile(path.join(f.plan.windows[0].assetRoot,'generated.bin'),'changed');},labels:async f=>{const p=f.plan.windows[0].labels,x=JSON.parse(await readFile(p));x.viaMetadata['frame-000000'].regions[0].shape_attributes.cx=101;await writeFile(p,JSON.stringify(x));}};
  for(const mutate of Object.values(mutators))await temporary([{}],async f=>{await mutate(f);await assert.rejects(f.run());await assert.rejects(stat(f.output),{code:'ENOENT'});assert.equal((await readdir(f.root)).some(n=>n.startsWith('.native-aggregation-partial-')),false);});
  await temporary([{}],async f=>{const r=await f.run(),receipt=await readFile(path.join(r.output,'aggregation-receipt.json'));await assert.rejects(f.run(),/already exists/);assert.deepEqual(await readFile(path.join(r.output,'aggregation-receipt.json')),receipt);});
});

test('Strict plan bounds/cancellation/invalid native timestamps refuse; generic BigInt arithmetic remains exact',async()=>temporary([{}],async f=>{
  assert.equal(timestampKey(t('9007199254740993',600)),timestampKey(t('18014398509481986',1200)));
  const invalid=JSON.parse(await readFile(f.plan.windows[0].ledger));invalid.frames[0].timestamp=t('9007199254740993',600);invalid.association.acceptedTimestamps[0]=invalid.frames[0].timestamp;
  const ledgerBytes=await readFile(f.plan.windows[0].ledger);await writeFile(f.plan.windows[0].ledger,JSON.stringify(invalid));await assert.rejects(f.run(),/timestamp ordering\/range/);await writeFile(f.plan.windows[0].ledger,ledgerBytes);
  const controller=new AbortController();controller.abort();await assert.rejects(f.run({signal:controller.signal}),/cancelled/);
  const interval=f.plan.interval;f.plan.interval={start:t(300),end:t(1231)};await f.save();await assert.rejects(f.run(),/30s/);f.plan.interval=interval;
  f.plan.groups={inventedKey:'x'};await f.save();await assert.rejects(f.run(),/groups/);delete f.plan.groups;
  const original=f.plan.windows;f.plan.windows=Array.from({length:65},(_,i)=>({...original[0],id:'w'+i}));await f.save();await assert.rejects(f.run(),/64/);f.plan.windows=original;await f.save();
  await writeFile(f.plan.windows[0].labels,Buffer.alloc(4*1024*1024+1));await assert.rejects(f.run(),/bound/);await assert.rejects(stat(f.output),{code:'ENOENT'});
}));

test('Actual CLI rejects bypass flags and publishes only explicit local selected inputs',async()=>temporary([{}],async f=>{
  const run=promisify(execFile),script=fileURLToPath(new URL('./aggregate_native_windows.mjs',import.meta.url));
  const args=[script,'--plan',f.planFile,'--output',f.output];await assert.rejects(run(process.execPath,[...args,'--purpose','native-scoring'],{timeout:30_000}),/unique --plan/);
  const result=JSON.parse((await run(process.execPath,args,{timeout:30_000})).stdout);assert.equal(result.accuracyGatePassed,false);assert.equal(result.counts.distinctDecodedTimestamps,3);
}));

test('Mutations immediately before publication and late cancellation refuse without partial outputs',async()=>{
  for(const selected of ['ledger','evaluation','source','png','cancel'])await temporary([{}],async f=>{
    const controller=new AbortController();
    const onPhase=async phase=>{
      assert.equal(phase,'validating-publication');const w=f.plan.windows[0];
      if(selected==='cancel'){controller.abort();return;}
      const filename=selected==='source'?path.join(w.assetRoot,'generated.bin'):selected==='png'?path.join(w.assetRoot,'frames','frame-000000.png'):w[selected];
      await writeFile(filename,'changed after initial verification');
    };
    await assert.rejects(f.run({onPhase,signal:controller.signal}),selected==='cancel'?/cancelled/:/changed|mismatch/);
    await assert.rejects(stat(f.output),{code:'ENOENT'});assert.equal((await readdir(f.root)).some(n=>n.startsWith('.native-aggregation-partial-')),false);
  });
});

test('Correction links verified previous receipt and cannot erase prior group constraints',async()=>temporary([{}],async f=>{
  f.plan.groups={recordingGroupID:'anonymous-recording',sessionGroupID:'anonymous-session',subjectGroupID:'anonymous-subject',reviewStatus:'reviewed',permissionEvidence:'Generated contract only'};await f.save();
  const first=await f.run(),previousReceiptFile=path.join(first.output,'aggregation-receipt.json'),next=path.join(f.root,'corrected');
  const corrected=await f.run({output:next,previousReceiptFile});
  const registry=JSON.parse(await readFile(path.join(corrected.output,'registry.json')));
  assert.equal(registry.previousAggregation.receiptSHA256,digest(await readFile(previousReceiptFile)));
  delete f.plan.groups;await f.save();await assert.rejects(f.run({output:path.join(f.root,'erased'),previousReceiptFile}),/erase\/change/);
  const saved=await readFile(previousReceiptFile);await writeFile(path.join(first.output,'aggregation.json'),'{}');
  await assert.rejects(f.run({output:path.join(f.root,'changed-prior'),previousReceiptFile}),/Previous aggregation bytes changed/);assert.deepEqual(await readFile(previousReceiptFile),saved);
}));

test('One explicitly shared canonical recording is verified once initially and once before publication',async()=>temporary([{},{}],async f=>{
  const common=path.join(f.root,'shared-media');await mkdir(common);await writeFile(path.join(common,'generated.bin'),movie);
  for(const w of f.plan.windows)w.assetRoot=common;await f.save();
  const r=await f.run();assert.equal(r.receipt.media.length,1);assert.equal(r.receipt.counts.distinctMediaBytes,movie.length);
  assert.equal(r.receipt.mediaReadBytes,2*movie.length);assert.equal(r.receipt.counts.uniqueWindows,2);
}));

test('Changed original analysis/capture identity refuses even with newly valid evaluation bytes',async()=>temporary([{},{}],async f=>{
  const first=JSON.parse(await readFile(f.plan.windows[0].ledger)),w=f.plan.windows[1],ledger=JSON.parse(await readFile(w.ledger)),labels=JSON.parse(await readFile(w.labels));
  ledger.association.analysisID=first.association.analysisID;
  const bytes=Buffer.from(JSON.stringify(ledger));labels.ledgerSha256=digest(bytes);await writeFile(w.ledger,bytes);await writeFile(w.labels,JSON.stringify(labels));
  const replacement=path.join(w.assetRoot,'reevaluated');await evaluateNativeBundle({ledgerFile:w.ledger,labelsFile:w.labels,assetRoot:w.assetRoot,output:replacement});
  w.evaluation=path.join(replacement,'evaluation.json');await f.save();await assert.rejects(f.run(),/original window identity has changed bytes/);await assert.rejects(stat(f.output),{code:'ENOENT'});
}));

test('Valid large metadata cannot exceed derived8MiB output; selected JSON shares32MiB across inputs',async()=>{
  await temporary(Array.from({length:32},()=>({permissionEvidence:'Generated contract only '+ 'x'.repeat(150000)})),async f=>{
    await assert.rejects(f.run(),/Derived output exceeds8MiB/);await assert.rejects(stat(f.output),{code:'ENOENT'});
    assert.equal((await readdir(f.root)).some(n=>n.startsWith('.native-aggregation-partial-')),false);
  });
  await temporary([{}],async f=>{
    const existingFile=path.join(f.root,'oversized-total.json');await writeFile(existingFile,Buffer.alloc(32*1024*1024));
    await assert.rejects(f.run({existingFile}),/Selected JSON exceeds32MiB/);await assert.rejects(stat(f.output),{code:'ENOENT'});
  });
});
