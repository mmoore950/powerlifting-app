import {createReadStream} from 'node:fs';
import {mkdir,rename,rm,stat} from 'node:fs/promises';
import path from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {DatabaseSync} from 'node:sqlite';
import {parse} from 'csv-parse';
import yauzl from 'yauzl';
import CRC32 from 'crc-32';
import {columns,kgColumns,validated,validateHeader,normalize,schemaSQL} from './schema.mjs';
import {atomicJSON,current,manifest,now,withLock,childPath} from './storage.mjs';
import {publishSnapshot} from './snapshot-lifecycle.mjs';

export const limits={compressedBytes:256*1024*1024,csvBytes:2*1024*1024*1024,rows:10_000_000,recordBytes:64*1024,importMs:20*60*1000};
export async function fileHash(file) {
  const hash=createHash('sha256');
  for await(const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
export async function csvSource(file) {
  if(!file.endsWith('.zip')) return {stream:createReadStream(file),entry:null,close:()=>{}};
  if((await stat(file)).size>limits.compressedBytes) throw new Error('Compressed archive exceeds limit');
  const zip=await new Promise((resolve,reject)=>yauzl.open(file,{lazyEntries:true,autoClose:false,validateEntrySizes:true},(error,value)=>error?reject(error):resolve(value)));
  try {
    const entries=await new Promise((resolve,reject)=>{
      if(zip.entryCount>1000) return reject(new Error('Too many ZIP entries'));
      const found=[]; zip.on('error',reject); zip.on('entry',entry=>{ if(entry.fileName.endsWith('.csv')) found.push(entry); zip.readEntry(); });
      zip.on('end',()=>resolve(found)); zip.readEntry();
    });
    if(entries.length!==1) throw new Error('Expected exactly one CSV');
    const entry=entries[0];
    if(entry.uncompressedSize>limits.csvBytes) throw new Error('Declared CSV size exceeds limit');
    const stream=await new Promise((resolve,reject)=>zip.openReadStream(entry,(error,value)=>error?reject(error):resolve(value)));
    return {stream,entry,close:()=>zip.close()};
  } catch(error) {zip.close();throw error;}
}

export async function importSnapshot({root,file,source={},minimumRows=1,onProgress=()=>{},beforePublish=null,locked=false}) {
  if(!locked) return withLock(root,()=>importSnapshot({root,file,source,minimumRows,onProgress,beforePublish,locked:true}));
  const started=performance.now();
  const fileBytes=(await stat(file)).size;
  if(fileBytes>(file.endsWith('.zip')?limits.compressedBytes:limits.csvBytes)) throw new Error('Input file exceeds byte limit');
  const archiveHash=await fileHash(file);
  const stage=childPath(root,'staging',randomUUID()); await mkdir(stage,{recursive:true});
  const dbFile=path.join(stage,'data.sqlite');
  let db, input;
  try {
    input=await csvSource(file);
    let bytes=0,crc=0,rows=0,header,peakRSS=process.memoryUsage().rss;
    const warnings={barePlusWeightClass:0,negativeWeightClass:0};
    const csvHash=createHash('sha256');
    const utf8=new TextDecoder('utf-8',{fatal:true});
    const guard=new Transform({transform(chunk,encoding,callback){
      try {utf8.decode(chunk,{stream:true});}catch(error){return callback(error);}
      bytes+=chunk.length;
      if(bytes>limits.csvBytes||performance.now()-started>limits.importMs) return callback(new Error('Import byte/time limit exceeded'));
      csvHash.update(chunk); if(input.entry) crc=CRC32.buf(chunk,crc);
      callback(null,chunk);
    },flush(callback){try{utf8.decode();callback();}catch(error){callback(error);}}});
    const parser=parse({bom:true,columns:values=>{header=validateHeader(values);return header;},max_record_size:limits.recordBytes,
                        skip_empty_lines:false,relax_column_count:false,encoding:'utf8'});
    db=new DatabaseSync(dbFile);
    db.exec('PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; PRAGMA temp_store=FILE; PRAGMA cache_size=-65536;');
    db.exec(schemaSQL());
    const insert=db.prepare(`INSERT INTO results VALUES(${Array.from({length:columns.length+2},()=>'?').join(',')})`);
    const lifter=db.prepare('INSERT OR IGNORE INTO lifters VALUES(?,?)');
    const names=new Set();
    const consume=async()=>{
      db.exec('BEGIN');
      for await(const raw of parser) {
        rows++; if(rows>limits.rows) throw new Error('Row limit exceeded');
        const row=validated(raw,rows);
        if(row.WeightClassKg==='+') warnings.barePlusWeightClass++;
        if(row.WeightClassKg.startsWith('-')) warnings.negativeWeightClass++;
        insert.run(rows,...columns.map(c=>row[c]),row.extras);
        if(!names.has(row.Name)) {
          lifter.run(row.Name,normalize(row.Name));
          if(names.size>=50_000) names.clear(); names.add(row.Name);
        }
        if(rows%10_000===0){db.exec('COMMIT; BEGIN');peakRSS=Math.max(peakRSS,process.memoryUsage().rss);}
        if(rows%250_000===0) onProgress({phase:'parse',rows,seconds:Math.round((performance.now()-started)/1000),rssMB:Math.round(peakRSS/1024/1024)});
      }
      db.exec('COMMIT');
    };
    const pumping=pipeline(input.stream,guard,parser);
    // Both promises are immediately observed; failure destroys the entire pipeline.
    const consuming=consume().catch(error=>{parser.destroy(error);throw error;});
    const outcomes=await Promise.allSettled([pumping,consuming]);
    const failed=[outcomes[1],outcomes[0]].find(result=>result.status==='rejected');
    if(failed) throw failed.reason;
    if(input.entry&&(bytes!==input.entry.uncompressedSize||(crc>>>0)!==input.entry.crc32)) throw new Error('ZIP size/CRC mismatch');
    if(rows<minimumRows) throw new Error(`Too few rows: ${rows}; minimum ${minimumRows}`);
    const contentHash=csvHash.digest('hex');
    const version=createHash('sha256').update(`schema-1\n${contentHash}`).digest('hex');
    const old=current(root); // Fully read/validated CSV even if this content was previously imported.
    const previous=await old;
    if(previous?.version===version) {
      const observation={source,archiveHash,csvEntry:input.entry?.fileName??null,validatedAt:now(),durationSeconds:(performance.now()-started)/1000};
      input.close();input=null;
      db.close();db=null;await rm(stage,{recursive:true,force:true});
      return {unchanged:true,...await manifest(root,version),observation};
    }
    onProgress({phase:'indexes',rows,seconds:Math.round((performance.now()-started)/1000)});
    db.exec(`CREATE INDEX lifter_search ON lifters(normalized,Name);
      CREATE INDEX result_lifter ON results(Name,Date DESC,row_id DESC);
      CREATE INDEX result_category_total ON results(Sex,Equipment,Event,TotalKg DESC,Name);
      CREATE INDEX result_date ON results(Date); ANALYZE;`);
    const integrity=db.prepare('PRAGMA integrity_check').get();
    if(Object.values(integrity)[0]!=='ok') throw new Error('SQLite integrity check failed');
    const lifters=db.prepare('SELECT count(*) AS count FROM lifters').get().count;
    const archiveEntry=input.entry?.fileName??null;
    db.close();db=null;input.close();input=null;
    if(performance.now()-started>limits.importMs) throw new Error('Import time limit exceeded before publication');
    const info={schemaVersion:1,version,contentHash,archiveHash,source:{...source,archiveDate:archiveEntry?.match(/openpowerlifting-(\d{4}-\d{2}-\d{2})/)?.[1]??source.archiveDate??null},header,rows,lifters,csvBytes:bytes,warnings,
      csvEntry:archiveEntry,importedAt:now(),durationSeconds:(performance.now()-started)/1000,
      databaseBytes:(await stat(dbFile)).size,peakSampledRSSBytes:Math.max(peakRSS,process.memoryUsage().rss),
      peakProcessRSSBytes:process.resourceUsage().maxRSS ? process.resourceUsage().maxRSS*1024 : null,validated:'All CSV records: column count, text bounds, required values, categories, calendar dates, numeric shapes/ranges; ZIP size+CRC when ZIP input; SQLite integrity.'};
    await atomicJSON(path.join(stage,'manifest.json'),info);
    const target=childPath(root,'snapshots',version); await mkdir(path.dirname(target),{recursive:true});
    try { await rename(stage,target); }
    catch(error) {
      if(!['EEXIST','ENOTEMPTY','EPERM'].includes(error.code)) throw error;
      await manifest(root,version); await rm(stage,{recursive:true,force:true});
    }
    if(beforePublish) await beforePublish(info);
    await publishSnapshot(root,version);
    return info;
  } catch(error) {
    if(db) {try{db.close();}catch{}}
    if(input){input.stream.destroy();input.close();}
    await rm(stage,{recursive:true,force:true}).catch(()=>{});
    throw error;
  }
}
