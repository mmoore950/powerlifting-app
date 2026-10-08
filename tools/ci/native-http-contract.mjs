// Run one real Swift/Node HTTP boundary test; fail if it is absent or skipped.
import {fork,spawn} from 'node:child_process';
import {mkdir,mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';

const repository=fileURLToPath(new URL('../../',import.meta.url));
const output=path.join(repository,'artifacts/native-ci');
await mkdir(output,{recursive:true});
const root=await mkdtemp(path.join(tmpdir(),'lifting-http-contract-'));
const descriptor=path.join(root,'ready.json'),proof=path.join(root,'executed.json');
const token=randomUUID();
let service,swift,timedOut=false;
const serviceLog=createWriteStream(path.join(output,'http-service.log'));
const swiftLog=createWriteStream(path.join(output,'http-swift.log'));
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function terminate(child,group=false) {
  if(!child) return;
  const kill=signal=>{
    try {if(group&&process.platform!=='win32'&&child.pid) process.kill(-child.pid,signal);else if(!exited(child)) child.kill(signal);}
    catch(error) {if(error.code!=='ESRCH') throw error;}
  };
  // An exited parent may still have workers in its owned POSIX group.
  if(exited(child)) {if(group) kill('SIGKILL');return;}
  const end=once(child,'exit');
  kill('SIGTERM');
  const force=setTimeout(()=>kill('SIGKILL'),5_000);
  try {await end;} finally {clearTimeout(force);if(group) kill('SIGKILL');}
}
const deadline=setTimeout(()=>{
  timedOut=true;
  void terminate(swift,true);void terminate(service,true);
},150_000);
const interrupt=()=>{timedOut=true;void terminate(swift,true);void terminate(service,true);};
process.once('SIGINT',interrupt);process.once('SIGTERM',interrupt);
try {
  service=fork(fileURLToPath(new URL('../../DataService/test/fixtures/native-http-server.mjs',import.meta.url)),[root],
    {stdio:['ignore','pipe','pipe','ipc'],windowsHide:true,detached:process.platform!=='win32'});
  service.stdout.pipe(serviceLog,{end:false});service.stderr.pipe(serviceLog,{end:false});
  const ready=await new Promise((resolve,reject)=>{
    const startup=setTimeout(()=>reject(new Error('Fixture startup exceeded 15 seconds')),15_000);
    const fail=()=>{clearTimeout(startup);reject(new Error('Fixture exited before ready'));};
    service.once('error',reject);service.once('exit',fail);
    service.once('message',message=>{clearTimeout(startup);service.removeListener('exit',fail);resolve(message);});
  });
  const url=new URL(ready.url);
  if(ready.pid!==service.pid||url.protocol!=='http:'||url.hostname!=='127.0.0.1'||!url.port||
    url.username||url.password||url.pathname!=='/'||url.search||url.hash||ready.rows!==54||ready.lifters!==29||
    !/^[a-f0-9]{64}$/.test(ready.version)) throw new Error('Invalid launcher ready descriptor');
  await writeFile(descriptor,JSON.stringify({...ready,token,proof}));
  console.log(`Synthetic Node HTTP fixture ready: ${ready.url}, version=${ready.version}, rows=54, names=29`);
  swift=spawn('swift',['test','--package-path','Packages/LiftingCore','--filter','OPLHTTPContractTests/testActualNodeHTTPContract'],
    {cwd:repository,env:{...process.env,OPL_HTTP_CONTRACT:'1',OPL_HTTP_DESCRIPTOR:descriptor},
      stdio:['ignore','pipe','pipe'],detached:process.platform!=='win32',windowsHide:true});
  swift.stdout.pipe(swiftLog,{end:false});swift.stderr.pipe(swiftLog,{end:false});
  swift.stdout.pipe(process.stdout);swift.stderr.pipe(process.stderr);
  const [code,signal]=await once(swift,'exit');
  if(timedOut||code!==0||signal) throw new Error(`Swift contract failed: code=${code}, signal=${signal}, deadline=${timedOut}`);
  const executed=JSON.parse(await readFile(proof,'utf8'));
  if(executed.token!==token||executed.method!=='testActualNodeHTTPContract'||executed.version!==ready.version) {
    throw new Error('Opt-in test did not produce its execution proof');
  }
  console.log('OPL_HTTP_CONTRACT_VERIFIED: one method executed to completion; no skip counted as pass');
} finally {
  clearTimeout(deadline);process.removeListener('SIGINT',interrupt);process.removeListener('SIGTERM',interrupt);
  if(service&&!exited(service)&&service.connected) service.send('stop');
  const cleanup=await Promise.allSettled([terminate(swift,true),terminate(service,true)]);
  serviceLog.end();swiftLog.end();
  if(cleanup.some(result=>result.status==='rejected')||[swift,service].some(child=>child&&!exited(child))) {
    throw new Error('Child termination unconfirmed; preserving owned root for diagnostics');
  }
  const resolved=path.resolve(root),parent=path.resolve(tmpdir());
  if(path.dirname(resolved)!==parent||!path.basename(resolved).startsWith('lifting-http-contract-')) {
    throw new Error('Refusing cleanup outside owned temporary root');
  }
  await rm(resolved,{recursive:true,force:true});
}
