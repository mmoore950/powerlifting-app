// Project-specific derivative wrapper. VIA's original pixel point editor remains authoritative.
// No media upload, remote import, background persistence or timestamp Number conversion.
(() => {
  'use strict';
  const el=id=>document.getElementById(id),status=message=>{el('hub_status').textContent=message;};
  window.onbeforeunload=null; // Replace upstream unconditional prompt with actual unsaved-draft guard below.
  let bundle=null,dirty=false,lastID=null;
  const events=[];
  const observation=message=>{events.push(message);el('hub_network').textContent=events.join('\n');console.log('OFFLINE_OBSERVATION',message);};
  window.addEventListener('securitypolicyviolation',e=>observation(`CSP blocked ${e.violatedDirective}: ${e.blockedURI}`));
  // Observe attempted API requests as well as resource entries. These APIs are disabled.
  window.fetch=()=>{observation('Blocked fetch attempt');return Promise.reject(Error('Network disabled'));};
  XMLHttpRequest.prototype.open=function(){observation('Blocked XMLHttpRequest attempt');throw Error('Network disabled');};
  if(navigator.sendBeacon)navigator.sendBeacon=()=>{observation('Blocked beacon attempt');return false;};
  if(window.PerformanceObserver)new PerformanceObserver(list=>{
    for(const entry of list.getEntries())if(!entry.name.startsWith('data:')&&!entry.name.startsWith('blob:'))observation(`Resource ${entry.initiatorType}: ${entry.name}`);
  }).observe({type:'resource',buffered:true});
  const assert=(ok,message)=>{if(!ok)throw Error(message);};
  const sha=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join('');
  const current=()=>bundle&&_via_img_metadata[_via_image_id];
  const redraw=()=>{_via_load_canvas_regions();_via_redraw_reg_canvas();};
  function sync() {
    const m=current();if(!m)return;
    const f=bundle.ledger.frames.find(f=>f.id===_via_image_id),a=m.file_attributes;
    const producer=bundle.ledger.purpose==='native-analysis'?'native analysis':'PyAV development';
    el('hub_frame').textContent=`${bundle.ledger.clip.id} · ${producer} · ${_via_image_index+1}/${bundle.ledger.frames.length} · ${f.id} · actual PTS ${f.timestamp.value}/${f.timestamp.timescale} (epoch ${f.timestamp.epoch}) · ${a.reviewStatus}`;
    el('hub_visibility').value=a.visibility;el('hub_uncertainty').value=a.uncertaintyPixels??'';
    el('hub_uncertainty').disabled=a.visibility!=='visible';lastID=_via_image_id;
  }
  function checkMetadata(metadata) {
    assert(metadata&&Object.keys(metadata).length===bundle.ledger.frames.length,'Missing/extra draft frames');
    for(const f of bundle.ledger.frames) {
      const m=metadata[f.id];assert(m&&m.filename===f.filename&&m.size===-1&&Array.isArray(m.regions),'Foreign draft frame');
      assert(Object.keys(m).sort().join(',')==='file_attributes,filename,regions,size','Unexpected draft metadata');
      const a=m.file_attributes;
      assert(a&&Object.keys(a).sort().join(',')==='reviewStatus,uncertaintyPixels,visibility','Unexpected draft attributes');
      assert(['reviewed','unreviewed'].includes(a.reviewStatus)&&['','visible','occluded','outside-frame','uncertain'].includes(a.visibility),'Invalid draft labels');
      assert(a.uncertaintyPixels===null||(typeof a.uncertaintyPixels==='number'&&Number.isFinite(a.uncertaintyPixels)),'Invalid draft uncertainty');
      for(const r of m.regions) {
        assert(r&&Object.keys(r).sort().join(',')==='region_attributes,shape_attributes'&&Object.keys(r.region_attributes).length===0,'Unexpected region fields');
        const s=r.shape_attributes;
        assert(s&&Object.keys(s).sort().join(',')==='cx,cy,name'&&s.name==='point'&&Number.isInteger(s.cx)&&Number.isInteger(s.cy)&&s.cx>=0&&s.cy>=0&&s.cx<bundle.ledger.clip.uprightWidth&&s.cy<bundle.ledger.clip.uprightHeight,'Invalid original-pixel point');
      }
    }
  }
  const guard=fn=>async event=>{try{await fn(event);}catch(e){status('Error: '+e.message);console.error(e);}};
  el('hub_bundle').addEventListener('change',guard(async event=>{
    const file=event.target.files[0];if(!file)return;
    assert(file.size<=48*1024*1024,'Bundle exceeds 48 MiB');
    assert(!dirty,'Save your current draft before loading another bundle');
    const b=parseStrictJSON(await file.text()),l=b.ledger;
    if(l?.purpose==='native-analysis')validateNativeContract(l);
    else assert(l?.schemaVersion===1&&l.purpose==='development-only'&&l.nativeParityVerified===false&&l.decoder?.name==='PyAV','Invalid development frame producer');
    assert(/^[a-f0-9]{64}$/.test(b.ledgerSha256)&&Array.isArray(l.frames)&&l.frames.length>0&&l.frames.length<=450,'Invalid bundle identity/count');
    assert(typeof b.ledgerText==='string'&&await sha(new TextEncoder().encode(b.ledgerText))===b.ledgerSha256&&JSON.stringify(parseStrictJSON(b.ledgerText))===JSON.stringify(l),'Changed bundle ledger bytes/content');
    assert([l.clip.uprightWidth,l.clip.uprightHeight].every(n=>Number.isInteger(n)&&n>0&&n<=8192),'Invalid image geometry');
    const ids=new Set();let previous=null,totalBytes=0;
    for(const f of l.frames) {
      assert(/^frame-\d{6}$/.test(f.id)&&!ids.has(f.id)&&f.filename===f.id+'.png','Duplicate/foreign frame ID');ids.add(f.id);
      const t=f.timestamp;
      assert(t&&typeof t.value==='string'&&/^-?\d+$/.test(t.value)&&Number.isInteger(t.timescale)&&t.timescale>0&&t.timescale<=2147483647&&t.epoch===0,'Invalid exact PTS');
      const value=BigInt(t.value);assert(value>=-(2n**63n)&&value<2n**63n,'PTS outside Int64');
      assert(!previous||value*BigInt(previous.timescale)>BigInt(previous.value)*BigInt(t.timescale),'Duplicate/unordered PTS');previous=t;
      const data=b.images[f.id];assert(typeof data==='string'&&/^data:image\/png;base64,[A-Za-z0-9+/=]+$/.test(data),'Only embedded PNG images allowed');
      const bytes=Uint8Array.from(atob(data.split(',')[1]),x=>x.charCodeAt(0));
      totalBytes+=bytes.length;assert(totalBytes<=32*1024*1024,'Frame payload exceeds 32 MiB');
      assert(await sha(bytes)===f.sha256,'Image hash changed');
      const image=new Image();image.src=data;await image.decode();assert(image.naturalWidth===l.clip.uprightWidth&&image.naturalHeight===l.clip.uprightHeight,'Image geometry changed');
    }
    assert(Object.keys(b.images).length===ids.size,'Foreign bundle images');
    assert(!_via_is_loading_current_image,'Wait for the current frame to finish loading');
    await Promise.allSettled(_via_preload_img_promise_list);_via_preload_img_promise_list=[];
    _via_buffer_remove_all();_via_img_metadata={};_via_img_src={};_via_img_fileref={};
    _via_image_id_list=[];_via_image_filename_list=[];_via_img_count=0;_via_image_load_error=[];
    _via_current_image_loaded=false;_via_image_index=-1;lastID=null;
    bundle=b;project_init_default_project();
    for(const f of l.frames) {
      const id=project_add_new_file(f.filename,-1,f.id);_via_img_src[id]=b.images[f.id];
      _via_img_metadata[id].file_attributes={reviewStatus:'unreviewed',visibility:'',uncertaintyPixels:null};
    }
    select_region_shape(VIA_REGION_SHAPE.POINT);update_img_fn_list();_via_show_img(0);
    dirty=false;status(l.purpose==='native-analysis'?
      `Loaded native producer contract. Analysis ${l.association.analysisID}; session ${l.association.captureSessionID}. Adapter must verify prediction.json and media before scoring. No accuracy result yet.`:
      'Loaded. Native image/time parity is unverified. Save drafts locally; adapter verifies the separate ledger and media.');
    observation('Local bundle imported; embedded images only');
  }));
  el('hub_draft').addEventListener('change',guard(async event=>{
    assert(bundle,'Load the matching frame bundle first');const file=event.target.files[0];if(!file)return;assert(file.size<=4*1024*1024,'Draft exceeds 4 MiB');
    assert(!dirty,'Save your current draft before reloading another draft');
    const d=parseStrictJSON(await file.text());assert(d.schemaVersion===1&&d.ledgerSha256===bundle.ledgerSha256,'Foreign/changed draft ledger');
    checkMetadata(d.viaMetadata);_via_img_metadata=d.viaMetadata;redraw();dirty=false;sync();status('Draft reloaded.');observation('Local draft reloaded');
  }));
  function save(kind) {
    assert(bundle,'Load a frame bundle first');checkMetadata(_via_img_metadata);
    const data={schemaVersion:1,ledgerSha256:bundle.ledgerSha256,viaMetadata:_via_img_metadata};
    const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));
    const a=document.createElement('a');a.href=url;a.download=`hub-${kind}-${Date.now()}.json`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    dirty=false;status('Saved '+kind+' locally. Keep the bundle and authoritative ledger together.');observation('Local '+kind+' download created');
  }
  el('hub_save').onclick=guard(()=>save('draft'));el('hub_export').onclick=guard(()=>save('labels'));
  el('hub_prev').onclick=()=>{if(bundle)_via_show_img(Math.max(0,_via_image_index-1));};
  el('hub_next').onclick=()=>{if(bundle)_via_show_img(Math.min(bundle.ledger.frames.length-1,_via_image_index+1));};
  el('hub_zoom_in').onclick=()=>{if(bundle)zoom_in();};el('hub_zoom_out').onclick=()=>{if(bundle)zoom_out();};
  el('hub_clear').onclick=()=>{if(current()){current().regions=[];current().file_attributes.reviewStatus='unreviewed';redraw();dirty=true;sync();}};
  el('hub_visibility').onchange=()=>{
    const m=current();if(!m)return;const visibility=el('hub_visibility').value;
    if(visibility!=='visible'&&m.regions.length){status('Clear the point first, then choose a non-visible label.');sync();return;}
    m.file_attributes.visibility=visibility;m.file_attributes.reviewStatus='unreviewed';
    if(visibility!=='visible'){m.regions=[];m.file_attributes.uncertaintyPixels=null;redraw();}
    dirty=true;sync();
  };
  el('hub_uncertainty').oninput=()=>{if(current()){const value=el('hub_uncertainty').value;current().file_attributes.uncertaintyPixels=value===''?null:Number(value);current().file_attributes.reviewStatus='unreviewed';dirty=true;}};
  el('hub_review').onclick=guard(()=>{
    const m=current();assert(m,'Load a bundle first');const a=m.file_attributes;
    assert(a.visibility,'Choose visibility explicitly');
    if(a.visibility==='visible')assert(m.regions.length===1&&Number.isFinite(a.uncertaintyPixels)&&a.uncertaintyPixels>=1,'Visible label needs one point and uncertainty of at least 1 pixel');
    else assert(m.regions.length===0&&a.uncertaintyPixels===null,'Non-visible label must have no point or uncertainty');
    a.reviewStatus='reviewed';dirty=true;sync();status('Frame marked reviewed. Save your draft.');
  });
  el('hub_unreview').onclick=()=>{if(current()){current().file_attributes.reviewStatus='unreviewed';dirty=true;sync();}};
  el('region_canvas').addEventListener('mouseup',()=>{if(current()){current().file_attributes.reviewStatus='unreviewed';dirty=true;sync();}});
  window.addEventListener('beforeunload',event=>{if(dirty){event.preventDefault();event.returnValue='Unsaved annotation draft';}});
  setInterval(()=>{if(bundle&&_via_current_image_loaded&&lastID!==_via_image_id)sync();},150);
})();
