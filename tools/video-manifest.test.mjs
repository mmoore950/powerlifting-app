import test from 'node:test';
import assert from 'node:assert/strict';
import {validateVideoManifest} from './validate-video-manifest.mjs';
test('synthetic annotation boundaries reject held-out leaks and timestamp/identity/provenance mistakes',()=>{
  const clip={id:'synthetic-a',sourceGroup:'synthetic-group',sha256:'a'.repeat(64),localPath:'synthetic.mov',split:'development',synthetic:true,permissionEvidence:'synthetic fixture only',lift:'synthetic',targetID:'hub',uprightWidth:1920,uprightHeight:1080,
    annotations:[{timestamp:{value:'9007199254740993',timescale:600,epoch:0},targetID:'hub',visibility:'visible',point:{x:0.5,y:0.5},uncertaintyPixels:2,provenance:'synthetic-reference'}]};
  const manifest={schemaVersion:1,coordinateSpace:'upright-normalized-top-left',clips:[clip]};
  assert.equal(validateVideoManifest(manifest).observedAnnotations,0);
  for(const mutate of [
    m=>m.clips.push({...structuredClone(clip),id:'synthetic-b',split:'holdout'}),
    m=>m.clips[0].annotations.push(structuredClone(clip.annotations[0])),
    m=>m.clips[0].annotations[0].provenance='manual-reference',
    m=>m.clips[0].annotations[0].targetID='wrong',
    m=>m.clips[0].annotations[0].timestamp.timescale=0,
    m=>m.clips[0].localPath='../private.mov']) {
      const changed=structuredClone(manifest);mutate(changed);assert.throws(()=>validateVideoManifest(changed));
  }
});
