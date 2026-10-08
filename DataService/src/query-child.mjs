import {executeQuery} from './query.mjs';

// Trusted parent supplies validated query and its parent-leased immutable version.
// No lifecycle locking/lease acquisition occurs in this process.
process.once('message',({root,prepared,selected})=>{
  process.send({type:'started'});
  let message;
  try {
    const json=JSON.stringify(executeQuery(root,prepared,selected));
    if(Buffer.byteLength(json)>8*1024*1024) throw new Error('QUERY_RESPONSE_TOO_LARGE');
    const usage=process.resourceUsage();
    message={type:'result',json,metrics:{rssBytes:process.memoryUsage().rss,peakRSSBytes:usage.maxRSS*1024}};
  } catch(error) {message={type:'error',error:error.message};}
  process.send(message,()=>process.disconnect());
});
