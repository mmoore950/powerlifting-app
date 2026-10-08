// Shared source contract for Node validation and the embedded offline panel.
// UUIDs identify a writer session; they are not a signature authenticating origin.
export function validateNativeContract(ledger) {
  const require=(ok,message)=>{if(!ok)throw Error(message);};
  const keys=(o,k)=>require(o&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join('|')===k.toSorted().join('|'),'Unexpected native producer fields');
  const same=(a,b)=>a?.value===b?.value&&a?.timescale===b?.timescale&&a?.epoch===b?.epoch;
  keys(ledger,['schemaVersion','purpose','nativeParityVerified','decoder','clip','frames','association']);
  require(ledger.schemaVersion===1&&ledger.purpose==='native-analysis'&&ledger.nativeParityVerified===true,'Invalid native producer purpose');
  const d=ledger.decoder;
  keys(d,['name','version','transform','aperture','scale','tolerance','frameSource']);
  require(d.name==='AVAssetImageGenerator'&&typeof d.version==='string'&&d.version.length>0&&d.version.length<=4096&&
    d.transform==='preferred-track-transform'&&d.aperture==='clean-aperture'&&d.scale==='maximum-1024x1024'&&
    d.tolerance==='zero'&&d.frameSource==='same-native-analysis','Invalid native decoder provenance');
  const a=ledger.association;
  keys(a,['analysisID','captureSessionID','predictionSHA256','modelID','mode','acceptedTimestamps','rangeStart','rangeEnd']);
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  require(uuid.test(a.analysisID)&&uuid.test(a.captureSessionID)&&/^[a-f0-9]{64}$/.test(a.predictionSHA256),'Invalid native association identity');
  require(typeof a.modelID==='string'&&a.modelID.trim().length>0&&Array.from(a.modelID).length<=200&&!a.modelID.includes('\0')&&['automatic','manual-vision'].includes(a.mode),'Invalid native association model/mode');
  require(Number.isFinite(a.rangeStart)&&Number.isFinite(a.rangeEnd)&&a.rangeStart>=0&&a.rangeEnd>a.rangeStart&&a.rangeEnd<=1800&&a.rangeEnd-a.rangeStart<=1,'Invalid native capture range');
  require(Array.isArray(ledger.frames)&&ledger.frames.length>0&&ledger.frames.length<=16&&Array.isArray(a.acceptedTimestamps)&&a.acceptedTimestamps.length===ledger.frames.length,'Invalid native frame count');
  require([ledger.clip?.uprightWidth,ledger.clip?.uprightHeight].every(n=>Number.isInteger(n)&&n>0&&n<=1024),'Invalid native geometry');
  let previous=null;
  for(let i=0;i<ledger.frames.length;i++) {
    const f=ledger.frames[i],t=f.timestamp;
    require(f.id===`frame-${String(i).padStart(6,'0')}`&&f.filename===f.id+'.png','Invalid native frame sequence');
    keys(t,['value','timescale','epoch']);keys(a.acceptedTimestamps[i],['value','timescale','epoch']);
    require(typeof t.value==='string'&&/^(0|[1-9][0-9]*)$/.test(t.value)&&Number.isInteger(t.timescale)&&t.timescale>0&&t.timescale<=2147483647&&t.epoch===0&&same(t,a.acceptedTimestamps[i]),'Changed native accepted timestamp components');
    const value=BigInt(t.value),scale=BigInt(t.timescale);
    require(value<=1800n*scale&&(!previous||value*BigInt(previous.timescale)>BigInt(previous.value)*scale),'Invalid native timestamp ordering/range');
    const seconds=Number(value)/t.timescale;
    require(seconds>=a.rangeStart-1e-9&&seconds<=a.rangeEnd+1e-9,'Native timestamp outside selected range');
    previous=t;
  }
  return ledger;
}
