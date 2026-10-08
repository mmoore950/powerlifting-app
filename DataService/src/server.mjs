import http from 'node:http';
import {dataset} from './query.mjs';
import {QueryPool} from './query-pool.mjs';
export function serve({root,port=8787,queryOptions={}}) {
  const pool=new QueryPool({...queryOptions,root});
  const server=http.createServer(async(request,response)=>{
    const controller=new AbortController();
    const cancel=()=>controller.abort();
    request.once('aborted',cancel);
    response.once('close',()=>{if(!response.writableEnded) cancel();});
    try {
      if(request.method!=='GET') {response.writeHead(405);return response.end();}
      if(request.url.length>8192) throw new Error('REQUEST_TOO_LONG');
      const url=new URL(request.url,'http://127.0.0.1');
      const params={};for(const [key,value] of url.searchParams){if(key in params) throw new Error('DUPLICATE_PARAMETER');params[key]=value;}
      let result;
      if(url.pathname==='/dataset') {if(Object.keys(params).length) throw new Error('UNSUPPORTED_FILTER');result=await dataset(root);}
      else if(url.pathname==='/lifters') result=await pool.run('search',params,{signal:controller.signal});
      else if(url.pathname==='/rankings') result=await pool.run('rankings',params,{signal:controller.signal});
      else {
        const match=url.pathname.match(/^\/lifters\/([A-Za-z0-9_-]+)\/results$/);
        if(!match) {response.writeHead(404);return response.end();}
        if(params.id) throw new Error('DUPLICATE_PARAMETER');result=await pool.run('history',{...params,id:match[1]},{signal:controller.signal});
      }
      if(response.destroyed) return;
      response.writeHead(200,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});
      response.end(JSON.stringify(result));
    } catch(error) {
      if(response.destroyed) return;
      const code=/VERSION_UNAVAILABLE|CURSOR_VERSION_MISMATCH/.test(error.message)?409:/QUERY_TIMEOUT/.test(error.message)?504:
        /NO_DATASET|SNAPSHOT_BUSY|QUERY_BUSY|QUERY_QUEUE_TIMEOUT|QUERY_SERVICE_CLOSED/.test(error.message)?503:
        /QUERY_WORKER|QUERY_RESPONSE_TOO_LARGE/.test(error.message)?500:400;
      response.writeHead(code,{'Content-Type':'application/json',...(code===503?{'Retry-After':'1'}:{})});response.end(JSON.stringify({error:error.message}));
    } finally {request.removeListener('aborted',cancel);}
  });
  const close=server.close;
  server.close=function(callback) {void pool.close();return close.call(this,callback);};
  server.requestTimeout=30_000;server.headersTimeout=10_000;
  server.listen(port,'127.0.0.1');return server;
}
