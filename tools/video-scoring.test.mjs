import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm,mkdir,symlink,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {validateVideoManifest} from './validate-video-manifest.mjs';
import {scoreVideoTraces,verifyMedia,evaluateVideoFiles} from './score-video-traces.mjs';

const time=(value,timescale=10,epoch=0)=>({value:String(value),timescale,epoch});
const annotation=(timestamp,extra={})=>({timestamp,targetID:'hub',visibility:'visible',point:{x:0.5,y:0.5},uncertaintyPixels:1,provenance:'synthetic-reference',...extra});
const clip={id:'synthetic-only',sourceGroup:'synthetic-group',sha256:'a'.repeat(64),localPath:'synthetic.bin',split:'development',synthetic:true,permissionEvidence:'generated test bytes, not video',lift:'synthetic',targetID:'hub',uprightWidth:100,uprightHeight:100,annotations:[]};
const manifest=annotations=>({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[{...clip,annotations}]});
const sample=(timestamp,extra={})=>({timestamp,point:{x:0.53,y:0.54},confidence:0.9,kind:'automatic',targetID:'track-1',...extra});
const predictions=samples=>({schemaVersion:1,coordinateSpace:'upright-normalized-top-left',modelID:'synthetic-test-only',runs:[{clipID:clip.id,sha256:clip.sha256,mode:'automatic',synthetic:true,uprightWidth:100,uprightHeight:100,elapsedSeconds:1,samples}]});
const automatic=report=>report.cases.find(c=>c.mode==='automatic');
const cleanup=async temp=>{assert(path.resolve(temp).startsWith(path.resolve(tmpdir())+path.sep));await rm(temp,{recursive:true,force:true});};

test('formal schemas reject unknown/missing fields, wrong types, loss/manual inconsistencies and unsafe timestamp epoch',()=>{
  const m=manifest([annotation(time(0))]),p=predictions([sample(time(0))]);
  assert.equal(validateVideoManifest(m).syntheticAnnotations,1);
  for(const mutate of [m=>m.unknown=true,m=>delete m.clips[0].lift,m=>m.clips[0].synthetic='true',m=>m.clips[0].annotations[0].point.extra=1,m=>m.clips[0].annotations[0].timestamp.epoch=Number.MAX_SAFE_INTEGER+1,
    ...['C:\\private.mov','clip.mov:stream','folder//clip.mov','../clip.mov'].map(localPath=>m=>m.clips[0].localPath=localPath)]) {
    const changed=structuredClone(m);mutate(changed);assert.throws(()=>validateVideoManifest(changed));
  }
  for(const mutate of [p=>p.runs[0].samples[0].kind='manualReference',p=>p.runs[0].samples[0].point=null,p=>p.runs[0].mode='manual-vision',p=>p.runs[0].sha256='b'.repeat(64),p=>p.runs[0].samples[0].confidence='0.9',p=>p.runs.push(structuredClone(p.runs[0]))]) {
    const changed=structuredClone(p);mutate(changed);assert.throws(()=>scoreVideoTraces(m,changed));
  }
});

test('exact rational timestamps above safe integer match without FPS, interpolation or cross-epoch matching',()=>{
  const t=time('9007199254740993',600),equal=time('18014398509481986',1200);
  const report=scoreVideoTraces(manifest([annotation(t)]),predictions([sample(equal)]),{pixelThreshold:5});
  const c=automatic(report);assert.equal(c.acceptedVisible,1);assert.equal(c.withinThreshold,1);assert(Math.abs(c.errorPixels.mean-5)<1e-10);
  assert.equal(c.definitelyWithinThreshold,0);assert.equal(c.uncertaintyOverlapsThreshold,1);
  const outside=automatic(scoreVideoTraces(manifest([annotation(t)]),predictions([sample(equal)]),{pixelThreshold:3}));
  assert.equal(outside.definitelyOutsideThreshold,1);assert.equal(outside.withinThreshold,0);
  assert(Math.abs(outside.observations[0].uncertaintyLowerPixels-4)<1e-10);assert(Math.abs(outside.observations[0].uncertaintyUpperPixels-6)<1e-10);
  assert.equal(automatic(scoreVideoTraces(manifest([annotation(t)]),predictions([sample({...equal,epoch:1})]))).missingVisibleSamples,1);
  assert.equal(automatic(scoreVideoTraces(manifest([annotation(t)]),predictions([sample(time('9007199254740994',600))]))).missingVisibleSamples,1);
  assert.throws(()=>scoreVideoTraces(manifest([annotation(t)]),predictions([sample(t),sample(equal)])),/duplicate/);
});

test('missing, abstained, ambiguous and unobservable references remain separate from accepted localization and identity gaps',()=>{
  const refs=[annotation(time(0)),annotation(time(1)),annotation(time(2)),annotation(time(3)),annotation(time(4)),
    annotation(time(5),{visibility:'uncertain',point:null,uncertaintyPixels:null}),
    annotation(time(6),{visibility:'occluded',point:null,uncertaintyPixels:null}),annotation(time(7)),annotation(time(8))];
  const p=predictions([sample(time(0)),sample(time(1),{targetID:'track-2'}),sample(time(2),{point:null,kind:'lost',confidence:0,targetID:null}),
    sample(time(4),{targetID:'track-3'}),sample(time(5)),sample(time(6)),sample(time(7),{targetID:'track-4'}),sample(time(8),{confidence:0.1})]);
  const c=automatic(scoreVideoTraces(manifest(refs),p,{pixelThreshold:10}));
  assert.equal(c.visibleReferences,7);assert.equal(c.acceptedVisible,4);assert.equal(c.missingVisibleSamples,1);assert.equal(c.visibleAbstentions,2);
  assert.equal(c.ambiguousReferences,1);assert.equal(c.unobservableReferences,1);assert.equal(c.acceptedUnobservable,1);
  assert.equal(c.identityChanges,1);assert.equal(c.identitiesAfterGap,2);assert.equal(c.definitelyWithinThreshold,4);
  const missing=automatic(scoreVideoTraces(manifest(refs),{...p,runs:[]}));assert.equal(missing.runPresent,false);assert.equal(missing.missingVisibleSamples,7);assert.equal(missing.errorPixels.mean,null);
  const sparse=scoreVideoTraces(manifest([annotation(time(0)),annotation(time(2))]),predictions([
    sample(time(0)),sample(time(1),{point:null,kind:'lost',confidence:0,targetID:null}),sample(time(2),{targetID:'track-2'})]));
  assert.equal(automatic(sparse).identityChanges,0);assert.equal(automatic(sparse).identitiesAfterGap,1);
});

test('synthetic/splits/modes stay separate; empty corpus has null metrics and no accuracy evidence',()=>{
  const m=manifest([annotation(time(0))]),p=predictions([sample(time(0))]);
  const second={...structuredClone(clip),id:'synthetic-holdout',sourceGroup:'other',sha256:'b'.repeat(64),split:'holdout',annotations:[annotation(time(0))]};m.clips.push(second);
  p.runs.push({...structuredClone(p.runs[0]),clipID:second.id,sha256:second.sha256,mode:'manual-vision',samples:[sample(time(0),{kind:'tracked',targetID:'manual-vision'})]});
  const result=scoreVideoTraces(m,p);assert.equal(result.groups.length,4);assert.equal(result.accuracyGatePassed,false);assert.match(result.evidence,/no observed/);
  assert.equal(result.groups.find(g=>g.split==='holdout'&&g.mode==='automatic').acceptedCoverage,0);
  assert.throws(()=>scoreVideoTraces({...m,clips:[m.clips[0],{...second,sha256:clip.sha256}]},p),/leaked/);
  const empty=scoreVideoTraces({...m,clips:[]},{...p,runs:[]});assert.deepEqual(empty.groups,[]);assert.equal(empty.reference.observedAnnotations,0);assert.equal(empty.accuracyGatePassed,false);assert.match(empty.evidence,/unmeasured/);
});

test('shared native encoder contract fixture is explicitly synthetic and validates; it is not native execution',async()=>{
  const fixture=JSON.parse(await readFile(new URL('../Packages/LiftingCore/Tests/LiftingCoreTests/Fixtures/video-prediction-synthetic.json',import.meta.url),'utf8'));
  const result=scoreVideoTraces(manifest([annotation(time(0)),annotation(time(1))]),fixture);
  assert.equal(fixture.modelID,'synthetic-test-only');assert.equal(fixture.runs[0].synthetic,true);
  const c=automatic(result);assert.equal(c.acceptedVisible,1);assert.equal(c.visibleAbstentions,1);assert.equal(c.errorPixels.mean,0);
  assert.equal(result.reference.observedAnnotations,0);assert.equal(result.accuracyGatePassed,false);
});

test('local file hashes, byte bounds, changed media and outside junction fail before report publication',async()=>{
  const temp=await mkdtemp(path.join(tmpdir(),'lifting-video-eval-'));
  try {
    const assetRoot=path.join(temp,'assets'),outside=path.join(temp,'outside');await mkdir(assetRoot);await mkdir(outside);
    const bytes=Buffer.from('synthetic bytes only; not an observed video');await writeFile(path.join(assetRoot,'synthetic.bin'),bytes);
    const sha256=createHash('sha256').update(bytes).digest('hex'),m=manifest([annotation(time(0))]);m.clips[0].sha256=sha256;
    const p=predictions([sample(time(0))]);p.runs[0].sha256=sha256;
    assert.equal((await verifyMedia(m,assetRoot)).totalBytes,bytes.length);
    await assert.rejects(verifyMedia(m,assetRoot,{fileLimit:1}),/size bound/);await assert.rejects(verifyMedia(m,assetRoot,{totalLimit:1}),/budget/);
    const manifestFile=path.join(temp,'manifest.json'),predictionsFile=path.join(temp,'predictions.json'),output=path.join(temp,'report.json');
    await writeFile(manifestFile,JSON.stringify(m));await writeFile(predictionsFile,JSON.stringify(p));
    await evaluateVideoFiles({manifestFile,predictionsFile,assetRoot,output});assert.equal(JSON.parse(await readFile(output,'utf8')).accuracyGatePassed,false);
    await writeFile(path.join(assetRoot,'synthetic.bin'),'changed');await assert.rejects(evaluateVideoFiles({manifestFile,predictionsFile,assetRoot,output:path.join(temp,'bad-report.json')}),/SHA-256/);
    await assert.rejects(readFile(path.join(temp,'bad-report.json')),error=>error.code==='ENOENT');
    await writeFile(path.join(outside,'synthetic.bin'),bytes);await symlink(outside,path.join(assetRoot,'escape'),process.platform==='win32'?'junction':'dir');
    const escaped=structuredClone(m);escaped.clips[0].localPath='escape/synthetic.bin';await assert.rejects(verifyMedia(escaped,assetRoot),/escaped/);
  } finally {await cleanup(temp);}
});
