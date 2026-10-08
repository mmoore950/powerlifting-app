import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {adaptLabels,validateLedger,verifyAssets,digest,parseStrictJSON} from './adapt_labels.mjs';

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
