// Parent-owned, isolated synthetic root. No upstream download or public listener.
import {writeFile} from 'node:fs/promises';
import path from 'node:path';
import {tmpdir} from 'node:os';
import {once} from 'node:events';
import {importSnapshot} from '../../src/import.mjs';
import {atomicJSON} from '../../src/storage.mjs';
import {serve} from '../../src/server.mjs';
import {nativeHTTPRows,csv} from './service-data.mjs';

if(!process.send||!process.argv[2]) throw new Error('Expected IPC parent and owned fixture root');
const root=path.resolve(process.argv[2]);
if(path.dirname(root)!==path.resolve(tmpdir())||!path.basename(root).startsWith('lifting-http-contract-')) {
  throw new Error('Fixture root is outside the parent-owned temporary namespace');
}
let server,stopping=false;
async function stop() {
  if(stopping) return;
  stopping=true;clearTimeout(deadline);
  if(server) await new Promise(resolve=>server.close(resolve));
  if(process.connected) process.disconnect();
}
const deadline=setTimeout(()=>{process.exitCode=1;void stop();},150_000);
process.once('disconnect',()=>void stop());
process.once('SIGTERM',()=>void stop());
process.once('SIGINT',()=>void stop());
process.on('message',message=>{if(message==='stop') void stop();});
try {
  if(nativeHTTPRows.length>=100) throw new Error('Synthetic fixture exceeds scope');
  const file=path.join(root,'synthetic.csv'),serviceRoot=path.join(root,'service');
  await writeFile(file,csv(nativeHTTPRows));
  const imported=await importSnapshot({root:serviceRoot,file,source:{archiveDate:'2025-01-01',revision:'feedcafe'}});
  if(imported.rows!==54||imported.lifters!==29) throw new Error('Unexpected synthetic import size');
  await atomicJSON(path.join(serviceRoot,'status.json'),{validatedVersion:imported.version,
    lastSuccessfulCheckAt:'2025-01-04T00:00:00.123Z',lastSuccessfulImportAt:imported.importedAt,
    nextCheckAt:'2025-01-04T06:00:00.123Z'});
  if(stopping) throw new Error('Fixture parent stopped during import');
  server=serve({root:serviceRoot,port:0});await once(server,'listening');
  const address=server.address();
  if(address.address!=='127.0.0.1'||address.port<1) throw new Error('Unexpected listener');
  process.send({pid:process.pid,url:`http://127.0.0.1:${address.port}`,version:imported.version,rows:imported.rows,lifters:imported.lifters});
} catch(error) {console.error(error);process.exitCode=1;await stop();}
