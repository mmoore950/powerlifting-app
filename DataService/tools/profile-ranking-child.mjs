import {executeQuery} from '../src/query.mjs';

// Profiling-only trusted worker. Normal HTTP serving does not select this module.
process.once('message',({root,prepared,selected})=>{
  process.send({type:'started'});
  let message;
  try {
    const json=JSON.stringify(executeQuery(root,prepared,selected,{narrowRankings:true}));
    if(Buffer.byteLength(json)>8*1024*1024) throw new Error('QUERY_RESPONSE_TOO_LARGE');
    message={type:'result',json,metrics:{rssBytes:process.memoryUsage().rss,peakRSSBytes:process.resourceUsage().maxRSS*1024}};
  } catch(error) {message={type:'error',error:error.message};}
  process.send(message,()=>process.disconnect());
});
