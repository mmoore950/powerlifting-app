// Synthetic-root concurrency fixture only. Parent supplies an isolated root/version.
import {DatabaseSync} from 'node:sqlite';
import path from 'node:path';
import {withSnapshot} from '../../src/snapshot-lifecycle.mjs';

const [root,version]=process.argv.slice(2);
try {
  await withSnapshot(root,version,async()=>{
    const db=new DatabaseSync(path.join(root,'snapshots',version,'data.sqlite'),{readOnly:true});
    try {
      const count=()=>db.prepare('SELECT count(*) AS n FROM results').get().n;
      process.send({type:'ready',count:count()});
      await new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>reject(new Error('Held-reader fixture exceeded 10 seconds')),10_000);
        process.once('message',()=>{clearTimeout(timer);resolve();});
        process.once('disconnect',()=>{clearTimeout(timer);resolve();});
      });
      process.send?.({type:'released',count:count()});
    } finally {db.close();}
  });
} catch(error) {process.send?.({type:'error',message:error.message});process.exitCode=1;}
process.disconnect?.();
