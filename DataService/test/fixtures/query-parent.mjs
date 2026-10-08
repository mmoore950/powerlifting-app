// Parent-crash fixture. Parent supplies only an isolated synthetic service root.
import {QueryPool} from '../../src/query-pool.mjs';
const [root,version]=process.argv.slice(2);
const pool=new QueryPool({root,workerURL:new URL('./busy-query-child.mjs',import.meta.url),queryTimeoutMs:10_000,
  onEvent:event=>{if(event.type==='started') process.send({type:'ready',readerPID:event.pid});}});
try {await pool.run('search',{q:'blocking',version});}
catch(error) {process.send?.({type:'error',error:error.message});}
await pool.close();process.disconnect?.();
