import {mkdir,open,rename,unlink,stat} from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
import {pipeline} from 'node:stream/promises';
import {Readable,Transform} from 'node:stream';
import {createWriteStream} from 'node:fs';
import {atomicJSON,current,manifest,now,readJSON,withLock} from './storage.mjs';
import {fileHash,importSnapshot,limits} from './import.mjs';

export const official={landing:'https://openpowerlifting.gitlab.io/opl-csv/bulk-csv.html',archive:'https://openpowerlifting.gitlab.io/opl-csv/files/openpowerlifting-latest.zip'};
export const checkIntervalMs=6*3600*1000;
async function boundedText(url,fetcher) {
  const response=await fetcher(url,{signal:AbortSignal.timeout(20_000)});
  if(!response.ok) throw new Error(`Metadata HTTP ${response.status}`);
  let text='';for await(const chunk of response.body){text+=Buffer.from(chunk).toString('utf8');if(text.length>256_000) throw new Error('Metadata exceeds limit');}
  return text;
}
async function upstream(fetcher,urls) {
  const html=await boundedText(urls.landing,fetcher);
  const landingDate=html.match(/Updated:\s*(\d{4}-\d{2}-\d{2})/)?.[1];
  const revision=html.match(/>([a-f0-9]{8,40})<\/a>/)?.[1];
  if(!landingDate||!revision) throw new Error('Upstream revision/date metadata missing');
  const expectedRows=Number(html.match(/openpowerlifting-latest\.zip[\s\S]{0,400}?<td[^>]*>(\d+)<\/td>/)?.[1]??0);
  const head=await fetcher(urls.archive,{method:'HEAD',signal:AbortSignal.timeout(20_000)});
  if(!head.ok) throw new Error(`Archive HEAD HTTP ${head.status}`);
  const size=Number(head.headers.get('content-length')??0);
  if(size>limits.compressedBytes) throw new Error('Archive Content-Length exceeds limit');
  return {landingUrl:urls.landing,archiveUrl:urls.archive,landingDate,revision,expectedRows,
    etag:head.headers.get('etag'),lastModified:head.headers.get('last-modified'),checkedAt:now()};
}
async function download(url,file,fetcher) {
  const temp=`${file}.${randomUUID()}.tmp`;
  const signal=AbortSignal.timeout(120_000);
  try {
    const response=await fetcher(url,{signal});if(!response.ok) throw new Error(`Download HTTP ${response.status}`);
    let bytes=0;
    const guard=new Transform({transform(chunk,encoding,callback){bytes+=chunk.length;callback(bytes>limits.compressedBytes?new Error('Download byte limit exceeded'):null,chunk);}});
    await pipeline(Readable.fromWeb(response.body),guard,createWriteStream(temp,{flags:'wx'}),{signal});
    await rename(temp,file);return {bytes,downloadedAt:now(),etag:response.headers.get('etag'),lastModified:response.headers.get('last-modified')};
  } catch(error){await unlink(temp).catch(()=>{});throw error;}
}
export async function refresh({root,seedFile=null,seedMetadata=null,fetcher=fetch,urls=official,force=false,dueOnly=false,onProgress=()=>{},clock=Date.now}) {
  // Inject only the scheduling clock for accelerated local demonstrations/tests.
  // Network/download/import wall limits continue to use real elapsed time.
  const stamp=()=>new Date(clock()).toISOString();
  return withLock(root,async()=>{
    const statusFile=path.join(root,'status.json'); const old=await readJSON(statusFile,{});
    const due=old.retryAt??old.nextCheckAt;
    if(dueOnly&&!force&&due&&clock()<Date.parse(due)) return {skipped:true,reason:'not due',dueAt:due};
    const attempt=stamp();let source;
    try {
      await atomicJSON(statusFile,{...old,lastAttemptAt:attempt,running:true});
      source=await upstream(fetcher,urls);
      const pointer=await current(root);
      const previous=pointer?await manifest(root,pointer.version):null;
      const oldVersion=old.validatedVersion??old.lastPublishedVersion;
      const accepted=oldVersion===previous?.version?(old.validatedUpstream??previous?.source):previous?.source;
      // Require usable ETag and revision; a check is not a publication or a new source date.
      if(!force&&previous&&source.etag&&source.etag===accepted?.etag&&source.revision===accepted?.revision&&source.lastModified===accepted?.lastModified) {
        const status={...old,lastAttemptAt:attempt,lastSuccessfulCheckAt:stamp(),nextCheckAt:new Date(clock()+checkIntervalMs).toISOString(),
          lastSuccessfulImportAt:oldVersion===previous.version?(old.lastSuccessfulImportAt??previous.importedAt):previous.importedAt,
          running:false,failureCount:0,lastError:null,retryAt:null,upstream:source,
          validatedVersion:previous.version,validatedUpstream:accepted,lastPublishedVersion:previous.version};
        await atomicJSON(statusFile,status);return {unchanged:true,version:previous.version,status};
      }
      await mkdir(path.join(root,'downloads'),{recursive:true});
      let file=path.join(root,'downloads',`${source.revision}-${randomUUID()}.zip`);
      let reused=false;
      const seed=seedMetadata?await readJSON(seedMetadata):null;
      if(seedFile&&seed&&source.etag&&source.etag===seed.etag&&source.revision===seed.revision) {
        if((await stat(seedFile)).size<=limits.compressedBytes && await fileHash(seedFile)===seed.sha256) {file=seedFile;reused=true;}
      }
      if(!reused) {
        onProgress({phase:'download'});const downloaded=await download(urls.archive,file,fetcher);
        // Source must be stable during transfer. Different headers/revision require a fresh check.
        if(source.etag&&downloaded.etag!==source.etag) throw new Error('Upstream archive changed during download; retry');
        source.downloadedAt=downloaded.downloadedAt;
      } else source.downloadedAt=seed.checkedAtUTC;
      source.reusedArchive=reused;
      const minimumRows=Math.max(1,Math.floor((source.expectedRows||previous?.rows||1)*0.95));
      const info=await importSnapshot({root,file,source,minimumRows,onProgress,locked:true});
      const archiveDate=(info.observation?.csvEntry??info.csvEntry)?.match(/openpowerlifting-(\d{4}-\d{2}-\d{2})/)?.[1]??null;
      // The manifest already retains the archive path; date stays separate from landing/check times.
      const status={...old,lastAttemptAt:attempt,lastSuccessfulCheckAt:stamp(),lastSuccessfulImportAt:info.observation?.validatedAt??info.importedAt,
        lastPublishedVersion:info.version,validatedVersion:info.version,nextCheckAt:new Date(clock()+checkIntervalMs).toISOString(),
        running:false,failureCount:0,lastError:null,retryAt:null,upstream:{...source,archiveDate},validatedUpstream:{...source,archiveDate}};
      await atomicJSON(statusFile,status);return {...info,status};
    } catch(error) {
      const count=(old.failureCount??0)+1;
      const delay=[15*60*1000,3600*1000,6*3600*1000][Math.min(count-1,2)];
      await atomicJSON(statusFile,{...old,lastAttemptAt:attempt,lastFailureAt:stamp(),running:false,failureCount:count,
        lastError:error.message,retryAt:new Date(clock()+delay).toISOString(),...(source?{upstream:source}:{})});
      throw error;
    }
  });
}
