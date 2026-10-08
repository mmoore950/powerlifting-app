// Prepared reconstruction contract, not an Xcode suggested-name parser or origin proof.
// Call only with an explicit mapping reviewed against a successful actual manifest.
import {isDeepStrictEqual} from 'node:util';
import {parseStrictJSON,digest,validateLedger,verifyNativePrediction} from './adapt_labels.mjs';
import {timestampKey} from '../validate-video-manifest.mjs';

export const twoWindowTest='BarFrameBundleExporterTests/testGeneratedTwoWindowAbsolutePTSOverlap()';
const require=(ok,message)=>{if(!ok)throw Error(message);};
const expected={a:[3,5,7,9],b:[5,7,9,11,12]};
const time=value=>({value:String(value),timescale:30,epoch:0});
const basename=s=>typeof s==='string'&&s.length>0&&s!=='.'&&s!=='..'&&!/[\\/:\0]/.test(s);
const logicalPaths=new Map([['native-two-window-source','generated.mov']]);
for(const window of ['a','b']) {
  for(const kind of ['ledger','prediction','bundle']) logicalPaths.set(`native-two-window-${window}-${kind}`,`${window}/${kind}.json`);
  for(let i=0;i<6;i++) {
    const frame=`frame-${String(i).padStart(6,'0')}`;
    logicalPaths.set(`native-two-window-${window}-${frame}`,`${window}/frames/${frame}.png`);
  }
}

export function selectTwoWindowAttachments(manifestBytes,observedMapping) {
  require(Buffer.isBuffer(manifestBytes)&&manifestBytes.length>0&&manifestBytes.length<=1024*1024,'Manifest byte bound');
  const manifest=parseStrictJSON(manifestBytes.toString('utf8'));
  require(Array.isArray(manifest),'Manifest must be an array');
  const groups=manifest.filter(g=>g.testIdentifier===twoWindowTest);
  require(groups.length===1,'Expected exactly one selected test group');
  const entries=groups[0].attachments;
  require(Array.isArray(entries)&&entries.length>=9&&entries.length<=20&&Array.isArray(observedMapping)&&observedMapping.length===entries.length,'Attachment/mapping count bound');
  const usedNames=new Set(),usedPaths=new Set();
  const selected=observedMapping.map(row=>{
    require(row&&Object.keys(row).sort().join('|')==='exportedFileName|logicalName|suggestedHumanReadableName','Unexpected mapping fields');
    const relative=logicalPaths.get(row.logicalName);
    require(relative&&basename(row.exportedFileName)&&typeof row.suggestedHumanReadableName==='string'&&row.suggestedHumanReadableName.length>0,'Unsafe/unrecognized explicit mapping');
    const matches=entries.filter(e=>e.exportedFileName===row.exportedFileName&&e.suggestedHumanReadableName===row.suggestedHumanReadableName);
    require(matches.length===1&&matches[0].isAssociatedWithFailure===false,'Missing/duplicate/failure observed mapping');
    require(!usedNames.has(row.exportedFileName)&&!usedPaths.has(relative),'Duplicate attachment mapping');
    usedNames.add(row.exportedFileName);usedPaths.add(relative);
    return {...row,relative};
  });
  for(const relative of ['generated.mov',...['a','b'].flatMap(w=>['ledger','prediction','bundle'].map(k=>`${w}/${k}.json`))])
    require(usedPaths.has(relative),'Missing '+relative);
  // Exact observed strings only: no suffix, MIME, extension or UUID normalization.
  return {test:twoWindowTest,manifestSHA256:digest(manifestBytes),selected};
}

export function validateTwoWindowSnapshots(snapshots) {
  require(snapshots instanceof Map&&snapshots.size<=20,'Selected file count bound');
  let totalBytes=0;
  for(const [name,bytes] of snapshots) {
    require([...logicalPaths.values()].includes(name)&&Buffer.isBuffer(bytes)&&bytes.length>0&&bytes.length<=1024*1024,'Selected file kind/byte bound');
    totalBytes+=bytes.length;require(totalBytes<=2*1024*1024,'Combined byte bound');
  }
  const get=name=>{const b=snapshots.get(name);require(b,'Missing '+name);return b;};
  const movie=get('generated.mov'),sourceSHA256=digest(movie),rows=new Map(),ledgers=[];
  for(const window of ['a','b']) {
    const ledgerBytes=get(`${window}/ledger.json`),ledger=parseStrictJSON(ledgerBytes.toString('utf8'));
    validateLedger(ledger);
    const c=ledger.clip,a=ledger.association;
    require(c.id===`generated-native-window-${window}`&&c.sha256===sourceSHA256&&c.localPath==='generated.mov'&&c.synthetic===true&&c.split==='development'&&c.lift==='synthetic'&&c.targetID==='near-side-hub'&&c.sourceGroup==='generated-native-two-window-fixture'&&c.uprightWidth===96&&c.uprightHeight===128,'Wrong generated two-window fixture');
    require(a.modelID==='generated-two-window-capture-test'&&a.mode==='automatic'&&a.rangeStart===(window==='a'?0.1:1/6)&&a.rangeEnd===(window==='a'?0.3:0.4),'Wrong generated window range/model');
    require(ledger.frames.length===expected[window].length&&ledger.frames.length<=6,'Unexpected actual decoder count');
    verifyNativePrediction(ledger,get(`${window}/prediction.json`));
    const bundle=parseStrictJSON(get(`${window}/bundle.json`).toString('utf8'));
    require(typeof bundle.ledgerText==='string'&&Buffer.from(bundle.ledgerText).equals(ledgerBytes)&&bundle.ledgerSha256===digest(ledgerBytes)&&isDeepStrictEqual(bundle.ledger,ledger),'Bundle ledger bytes/content changed');
    require(bundle.images&&Object.keys(bundle.images).length===ledger.frames.length,'Bundle image count differs');
    for(let i=0;i<ledger.frames.length;i++) {
      const f=ledger.frames[i],key=timestampKey(f.timestamp);
      require(key===timestampKey(time(expected[window][i])),'Unexpected absolute accepted PTS');
      const png=get(`${window}/frames/${f.filename}`),embedded=bundle.images[f.id];
      require(digest(png)===f.sha256&&png.length>=24&&png.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))&&png.readUInt32BE(16)===96&&png.readUInt32BE(20)===128,'PNG hash/header geometry differs');
      require(typeof embedded==='string'&&/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(embedded)&&Buffer.from(embedded.slice('data:image/png;base64,'.length),'base64').equals(png),'Embedded PNG bytes differ');
      const prior=rows.get(key);
      if(prior) require(isDeepStrictEqual(prior.timestamp,f.timestamp)&&prior.png.equals(png)&&isDeepStrictEqual(prior.decoder,ledger.decoder),'Shared component/raster/decoder conflict');
      else rows.set(key,{timestamp:f.timestamp,png,decoder:ledger.decoder});
    }
    ledgers.push(ledger);
  }
  require(ledgers[0].association.analysisID!==ledgers[1].association.analysisID&&ledgers[0].association.captureSessionID!==ledgers[1].association.captureSessionID,'Reused original analysis/capture identity');
  require(snapshots.size===7+ledgers.reduce((n,l)=>n+l.frames.length,0),'Extra/missing selected files');
  return {synthetic:true,sourceSHA256,totalBytes,selectedFiles:snapshots.size,rawFrames:9,distinctDecodedTimestamps:rows.size,sharedDecodedTimestamps:3,
    observedAnnotations:0,accuracyGatePassed:false,scalarMetrics:null,continuity:'unverified',ledgers};
}
