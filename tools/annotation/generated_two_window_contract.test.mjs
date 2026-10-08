import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {digest} from './adapt_labels.mjs';
import {selectTwoWindowAttachments,validateTwoWindowSnapshots,twoWindowTest} from './generated_two_window_contract.mjs';
import {evaluateNativeBundle} from './evaluate_native_bundle.mjs';
import {aggregateNativeWindows} from './aggregate_native_windows.mjs';

const json=o=>Buffer.from(JSON.stringify(o)),time=n=>({value:String(n),timescale:30,epoch:0});
// Deliberately header-shaped bytes, not valid decoded PNGs or a native movie.
function fixture() {
  const movie=Buffer.from('Generated contract only; not Apple output or a MOV'),snapshots=new Map([['generated.mov',movie]]);
  for(const [window,values] of [['a',[3,5,7,9]],['b',[5,7,9,11,12]]]) {
    const frames=values.map((value,i)=>{
      const id=`frame-${String(i).padStart(6,'0')}`,png=Buffer.alloc(25);
      Buffer.from([137,80,78,71,13,10,26,10]).copy(png);png.writeUInt32BE(96,16);png.writeUInt32BE(128,20);png[24]=value;
      snapshots.set(`${window}/frames/${id}.png`,png);
      return {id,filename:id+'.png',sha256:digest(png),timestamp:time(value)};
    });
    const clip={id:`generated-native-window-${window}`,sha256:digest(movie),localPath:'generated.mov',sourceGroup:'generated-native-two-window-fixture',split:'development',synthetic:true,
      permissionEvidence:'Generated contract only',lift:'synthetic',targetID:'near-side-hub',uprightWidth:96,uprightHeight:128};
    const prediction={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',modelID:'generated-two-window-capture-test',runs:[{
      clipID:clip.id,sha256:clip.sha256,synthetic:true,mode:'automatic',uprightWidth:96,uprightHeight:128,elapsedSeconds:.1,
      samples:frames.map(f=>({timestamp:f.timestamp,point:null,confidence:0,kind:'lost',targetID:null}))}]};
    const predictionBytes=json(prediction);snapshots.set(`${window}/prediction.json`,predictionBytes);
    const ledger={schemaVersion:1,purpose:'native-analysis',nativeParityVerified:true,
      decoder:{name:'AVAssetImageGenerator',version:'synthetic-contract-only',transform:'preferred-track-transform',aperture:'clean-aperture',scale:'maximum-1024x1024',tolerance:'zero',frameSource:'same-native-analysis'},
      clip,frames,association:{analysisID:randomUUID(),captureSessionID:randomUUID(),predictionSHA256:digest(predictionBytes),modelID:prediction.modelID,
        mode:'automatic',rangeStart:window==='a'?.1:1/6,rangeEnd:window==='a'?.3:.4,acceptedTimestamps:frames.map(f=>f.timestamp)}};
    rebindBundle(snapshots,window,ledger);
  }
  return snapshots;
}
function rebindBundle(snapshots,window,ledger) {
  const bytes=json(ledger);snapshots.set(`${window}/ledger.json`,bytes);
  snapshots.set(`${window}/bundle.json`,json({ledger,ledgerText:bytes.toString(),ledgerSha256:digest(bytes),
    images:Object.fromEntries(ledger.frames.map(f=>[f.id,'data:image/png;base64,'+snapshots.get(`${window}/frames/${f.filename}`).toString('base64')]))}));
}
function mapping(snapshots) {
  // Synthetic opaque observed strings intentionally unlike an assumed Xcode format.
  const rows=[...snapshots.keys()].map((relative,i)=>({logicalName:relative==='generated.mov'?'native-two-window-source':
    'native-two-window-'+relative.split('/')[0]+'-'+path.basename(relative,path.extname(relative)),
    exportedFileName:`opaque-${i}.blob`,suggestedHumanReadableName:`synthetic exact entry ${i}`}));
  return {rows,manifest:json([{testIdentifier:twoWindowTest,attachments:rows.map(r=>({exportedFileName:r.exportedFileName,suggestedHumanReadableName:r.suggestedHumanReadableName,isAssociatedWithFailure:false}))}])};
}

test('Explicit reviewed strings select every original attachment without suggested-name normalization',()=>{
  const snapshots=fixture(),m=mapping(snapshots),selected=selectTwoWindowAttachments(m.manifest,m.rows);
  assert.equal(selected.selected.length,16);assert.deepEqual(new Set(selected.selected.map(r=>r.relative)),new Set(snapshots.keys()));
  const report=validateTwoWindowSnapshots(snapshots);
  assert.equal(report.rawFrames,9);assert.equal(report.distinctDecodedTimestamps,6);assert.equal(report.sharedDecodedTimestamps,3);
  assert.equal(report.observedAnnotations,0);assert.equal(report.accuracyGatePassed,false);
  // A new temporal state may produce different predictions at the same PTS.
  const originalA=Buffer.from(snapshots.get('a/prediction.json'));
  const prediction=JSON.parse(snapshots.get('b/prediction.json'));
  Object.assign(prediction.runs[0].samples[0],{point:{x:.25,y:.75},confidence:.9,kind:'automatic',targetID:'local-track-1'});
  const bytes=json(prediction),ledger=JSON.parse(snapshots.get('b/ledger.json'));
  snapshots.set('b/prediction.json',bytes);ledger.association.predictionSHA256=digest(bytes);rebindBundle(snapshots,'b',ledger);
  assert.equal(validateTwoWindowSnapshots(snapshots).sharedDecodedTimestamps,3);
  assert.deepEqual(snapshots.get('a/prediction.json'),originalA);
});

test('Mapping rejects failed/duplicate/missing groups, altered exact strings and traversal',()=>{
  for(const mutation of ['failed','group','duplicate-group','duplicate-name','suggested','traversal','logical','extra']) {
    const m=mapping(fixture()),manifest=JSON.parse(m.manifest),rows=structuredClone(m.rows);
    if(mutation==='failed')manifest[0].attachments[0].isAssociatedWithFailure=true;
    if(mutation==='group')manifest[0].testIdentifier='another test';
    if(mutation==='duplicate-group')manifest.push(structuredClone(manifest[0]));
    if(mutation==='duplicate-name')rows[1]=structuredClone(rows[0]);
    if(mutation==='suggested')rows[0].suggestedHumanReadableName+=' normalized';
    if(mutation==='traversal')rows[0].exportedFileName='../outside';
    if(mutation==='logical')rows[0].logicalName='native-generated-source';
    if(mutation==='extra')rows.push(structuredClone(rows[0]));
    assert.throws(()=>selectTwoWindowAttachments(json(manifest),rows),undefined,mutation);
  }
  assert.throws(()=>selectTwoWindowAttachments(Buffer.alloc(1024*1024+1),[]),/bound/);
});

test('Snapshot contracts refuse substituted bytes, identities, equivalent component tuples and byte budgets',()=>{
  for(const mutation of ['movie','prediction','png','bundle-text','identity','tuple','decoder','extra','file-budget','total-budget']) {
    const snapshots=fixture(),ledger=JSON.parse(snapshots.get('b/ledger.json'));
    if(mutation==='movie')snapshots.set('generated.mov',Buffer.from('changed'));
    if(mutation==='prediction')snapshots.set('b/prediction.json',Buffer.from('{}'));
    if(mutation==='png')snapshots.set('b/frames/frame-000000.png',Buffer.from('changed'));
    if(mutation==='bundle-text') {const b=JSON.parse(snapshots.get('b/bundle.json'));b.ledgerText+=' ';snapshots.set('b/bundle.json',json(b));}
    if(mutation==='identity') {ledger.association.analysisID=JSON.parse(snapshots.get('a/ledger.json')).association.analysisID;rebindBundle(snapshots,'b',ledger);}
    if(mutation==='decoder') {ledger.decoder.version='different';rebindBundle(snapshots,'b',ledger);}
    if(mutation==='tuple') {
      const prediction=JSON.parse(snapshots.get('b/prediction.json')),t={value:'10',timescale:60,epoch:0};
      ledger.frames[0].timestamp=t;ledger.association.acceptedTimestamps[0]=t;prediction.runs[0].samples[0].timestamp=t;
      const bytes=json(prediction);snapshots.set('b/prediction.json',bytes);ledger.association.predictionSHA256=digest(bytes);rebindBundle(snapshots,'b',ledger);
    }
    if(mutation==='extra')snapshots.set('b/frames/frame-000005.png',Buffer.from('extra'));
    if(mutation==='file-budget')snapshots.set('generated.mov',Buffer.alloc(1024*1024+1));
    if(mutation==='total-budget')for(const name of ['generated.mov','a/bundle.json','b/bundle.json'])snapshots.set(name,Buffer.alloc(800000));
    assert.throws(()=>validateTwoWindowSnapshots(snapshots),undefined,mutation);
  }
});

test('Generated all-unreviewed contract bytes use both strict evaluators and existing aggregate with zero accuracy claims',async()=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'generated-two-window-'));
  try {
    const snapshots=fixture(),contract=validateTwoWindowSnapshots(snapshots);
    for(const [relative,bytes] of snapshots) {const file=path.join(root,relative);await mkdir(path.dirname(file),{recursive:true});await writeFile(file,bytes,{flag:'wx'});}
    const windows=[];
    for(const [i,w] of ['a','b'].entries()) {
      const ledger=contract.ledgers[i],ledgerFile=path.join(root,w,'ledger.json'),labelsFile=path.join(root,w,'generated-all-unreviewed-labels.json'),output=path.join(root,w,'evaluated');
      const labels={schemaVersion:1,ledgerSha256:digest(snapshots.get(`${w}/ledger.json`)),viaMetadata:Object.fromEntries(ledger.frames.map(f=>[f.id,{filename:f.filename,size:-1,regions:[],file_attributes:{reviewStatus:'unreviewed',visibility:'',uncertaintyPixels:null}}]))};
      await writeFile(labelsFile,json(labels));const result=await evaluateNativeBundle({ledgerFile,labelsFile,assetRoot:root,output});
      assert.equal(result.score.accuracyGatePassed,false);assert.equal(result.score.reference.observedAnnotations,0);
      assert.deepEqual(await readFile(path.join(output,'ledger.json')),snapshots.get(`${w}/ledger.json`));
      windows.push({id:w,ledger:ledgerFile,labels:labelsFile,assetRoot:root,evaluation:path.join(output,'evaluation.json')});
    }
    const plan={schemaVersion:1,kind:'native-window-plan',repID:'generated-two-window-contract',recordingSHA256:contract.sourceSHA256,
      interval:{start:time(3),end:time(12)},windows,expectedOverlaps:[{windows:['a','b'],interval:{start:time(5),end:time(9)}}]};
    const planFile=path.join(root,'plan.json');await writeFile(planFile,json(plan));
    const result=await aggregateNativeWindows({planFile,output:path.join(root,'aggregated')}),a=result.aggregation;
    assert.equal(a.counts.distinctDecodedTimestamps,6);assert.equal(a.counts.reviewedUniqueTimestamps,0);assert.equal(a.counts.unreviewedUniqueTimestamps,6);
    assert.equal(a.counts.observedReviewedUniqueTimestamps,0);assert.equal(a.counts.conflictedUniqueTimestamps,0);
    assert.equal(a.expectedOverlaps[0].sharedDecodedTimestamps,3);assert.equal(a.expectedOverlaps[0].continuity,'unverified');
    assert.equal(a.timestamps.reduce((n,t)=>n+t.rows.length,0),9);assert.equal(a.accuracyGatePassed,false);assert.equal(a.scalarMetrics,null);
    assert.ok(a.timestamps.every(t=>t.rows.every(r=>Number(r.timestamp.value)>0)));
    const registry=JSON.parse(await readFile(path.join(result.output,'registry.json')));assert.equal(registry.groups.subjectGroupID,null);assert.equal(registry.groups.reviewStatus,'unknown');
  } finally {await rm(root,{recursive:true,force:true});}
});
