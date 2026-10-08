import {fork} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {prepareQuery} from './query.mjs';
import {withSnapshot} from './snapshot-lifecycle.mjs';

const failure=code=>new Error(code);
const productionChild=new URL('./query-child.mjs',import.meta.url);
export class QueryPool {
  constructor({root,maxWorkers=2,maxQueue=8,queueTimeoutMs=5000,queryTimeoutMs=10_000,workerURL=productionChild,onEvent=()=>{}}) {
    if(!Number.isInteger(maxWorkers)||maxWorkers<1||maxWorkers>8||!Number.isInteger(maxQueue)||maxQueue<0||maxQueue>100||
      !Number.isInteger(queueTimeoutMs)||queueTimeoutMs<1||queueTimeoutMs>60_000||
      !Number.isInteger(queryTimeoutMs)||queryTimeoutMs<1||queryTimeoutMs>60_000) throw failure('INVALID_QUERY_LIMITS');
    Object.assign(this,{root,maxWorkers,maxQueue,queueTimeoutMs,queryTimeoutMs,workerURL,onEvent});
    this.queue=[];this.active=new Set();this.closed=false;
  }
  get stats() {return {active:this.active.size,queued:this.queue.length,closed:this.closed};}
  event(value) {try {this.onEvent(value);}catch{/* Diagnostics cannot break cleanup. */}}
  run(kind,params={}, {signal}={}) {
    if(this.closed) return Promise.reject(failure('QUERY_SERVICE_CLOSED'));
    let prepared;
    try {prepared=prepareQuery(kind,params);}catch(error) {return Promise.reject(error);}
    if(signal?.aborted) return Promise.reject(failure('QUERY_CANCELLED'));
    if(this.active.size>=this.maxWorkers&&this.queue.length>=this.maxQueue) return Promise.reject(failure('QUERY_BUSY'));
    return new Promise((resolve,reject)=>{
      const job={prepared,resolve,reject,signal,state:'queued'};
      job.abort=()=>{
        if(job.state==='queued') this.rejectQueued(job,'QUERY_CANCELLED');
        else if(job.state==='active') job.controller.abort(failure('QUERY_CANCELLED'));
      };
      signal?.addEventListener('abort',job.abort,{once:true});
      job.queueTimer=setTimeout(()=>this.rejectQueued(job,'QUERY_QUEUE_TIMEOUT'),this.queueTimeoutMs);
      this.queue.push(job);this.pump();
    });
  }
  rejectQueued(job,code) {
    if(job.state!=='queued') return;
    this.queue=this.queue.filter(item=>item!==job);job.state='done';
    clearTimeout(job.queueTimer);job.signal?.removeEventListener('abort',job.abort);job.reject(failure(code));
  }
  pump() {
    while(!this.closed&&this.active.size<this.maxWorkers&&this.queue.length) {
      const job=this.queue.shift();clearTimeout(job.queueTimer);job.state='active';
      job.controller=new AbortController();this.active.add(job);
      job.completion=this.execute(job);
    }
  }
  async execute(job) {
    const deadline=setTimeout(()=>job.controller.abort(failure('QUERY_TIMEOUT')),this.queryTimeoutMs);
    let result,error;
    try {
      result=await withSnapshot(this.root,job.prepared.requestedVersion,async selected=>{
        if(job.controller.signal.aborted) throw job.controller.signal.reason;
        return this.invoke(job,selected);
      });
    } catch(caught) {error=caught;}
    finally {
      clearTimeout(deadline);job.state='done';job.signal?.removeEventListener('abort',job.abort);
      this.active.delete(job);this.pump();
    }
    if(error) job.reject(error);else job.resolve(result);
  }
  invoke(job,selected) {
    return new Promise((resolve,reject)=>{
      const child=fork(fileURLToPath(this.workerURL),[],{stdio:['ignore','ignore','ignore','ipc'],windowsHide:true,execArgv:['--max-old-space-size=64']});
      let result,error,received=false,stopping=false,registration=Promise.resolve();
      const stop=cause=>{
        if(cause) error??=cause;
        if(stopping) return;
        stopping=true;
        try {if(!child.kill('SIGKILL')) this.event({type:'killNotConfirmed',pid:child.pid});}
        catch {error??=failure('QUERY_WORKER_FAILED');this.event({type:'killNotConfirmed',pid:child.pid});}
      };
      const abort=()=>stop(job.controller.signal.reason??failure('QUERY_CANCELLED'));
      job.controller.signal.addEventListener('abort',abort,{once:true});
      if(job.controller.signal.aborted) abort();
      child.on('error',caught=>{stop(failure('QUERY_WORKER_FAILED'));this.event({type:'workerError',pid:child.pid,code:caught.code});});
      child.on('message',message=>{
        if(message?.type==='started') {this.event({type:'started',pid:child.pid,version:selected.version});return;}
        if(received) {stop(failure('QUERY_WORKER_PROTOCOL'));return;}
        received=true;
        if(message?.type==='error'&&typeof message.error==='string') stop(failure(message.error));
        else if(message?.type==='result'&&typeof message.json==='string'&&Buffer.byteLength(message.json)<=8*1024*1024) {
          try {
            result=JSON.parse(message.json);
            if(result?.version!==selected.version||!Array.isArray(result.results)) throw failure('QUERY_WORKER_PROTOCOL');
            const measured=message.metrics;
            if(measured&&[measured.rssBytes,measured.peakRSSBytes].every(value=>Number.isSafeInteger(value)&&value>0)) {
              this.event({type:'result',pid:child.pid,version:selected.version,metrics:measured});
            }
            // SQL and database close completed before the result was sent; confirm OS exit before lease release.
            stop();
          } catch {stop(failure('QUERY_WORKER_PROTOCOL'));}
        } else stop(failure('QUERY_WORKER_PROTOCOL'));
      });
      // close follows confirmed exit or a spawn error where no child was created.
      child.once('close',async(code,signal)=>{
        // Registration must finish before releasing the lease, even if cancellation killed the waiting child.
        await registration.catch(caught=>{error??=caught;});
        job.controller.signal.removeEventListener('abort',abort);
        this.event({type:'exit',pid:child.pid,code,signal});
        if(error) reject(error);else if(result) resolve(result);else reject(failure('QUERY_WORKER_FAILED'));
      });
      if(child.pid) registration=selected.registerReader(child.pid);
      registration.then(()=>{
        if(stopping) return;
        const {info,pointer,version}=selected;
        try {child.send({root:this.root,prepared:job.prepared,selected:{info,pointer,version}},caught=>{if(caught) stop(failure('QUERY_WORKER_FAILED'));});}
        catch {stop(failure('QUERY_WORKER_FAILED'));}
      },caught=>stop(caught));
    });
  }
  async close() {
    this.closed=true;
    for(const job of [...this.queue]) this.rejectQueued(job,'QUERY_SERVICE_CLOSED');
    const running=[...this.active];
    for(const job of running) job.controller.abort(failure('QUERY_SERVICE_CLOSED'));
    await Promise.all(running.map(job=>job.completion));
  }
}
