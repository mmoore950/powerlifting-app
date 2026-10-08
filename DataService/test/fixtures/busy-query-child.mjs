// A real long-running read-only SQLite operation, only in synthetic roots.
import {DatabaseSync} from 'node:sqlite';
import path from 'node:path';
import {executeQuery} from '../../src/query.mjs';
process.once('message',({root,prepared,selected})=>{
  if(prepared.params.q==='blocking') {
    const db=new DatabaseSync(path.join(root,'snapshots',selected.version,'data.sqlite'),{readOnly:true});
    try {
      const statement=db.prepare('WITH RECURSIVE numbers(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<1000000000) SELECT sum(n) FROM numbers');
      process.send({type:'started'});statement.get();
    } finally {db.close();}
  } else process.send({type:'started'});
  if(prepared.params.q==='wrongversion') {
    process.send({type:'result',json:JSON.stringify({version:'f'.repeat(64),results:[]})},()=>process.disconnect());return;
  }
  if(prepared.params.q==='crash') {process.exit(7);}
  try {process.send({type:'result',json:JSON.stringify(executeQuery(root,prepared,selected))},()=>process.disconnect());}
  catch(error) {process.send({type:'error',error:error.message},()=>process.disconnect());}
});
