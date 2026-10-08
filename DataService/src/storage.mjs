import {mkdir, open, readFile, rename, unlink, stat} from 'node:fs/promises';
import path from 'node:path';
import {randomUUID} from 'node:crypto';

export const now = () => new Date().toISOString();
export function childPath(root,...parts) {
  const base=path.resolve(root),target=path.resolve(base,...parts);
  if(!target.startsWith(base+path.sep)) throw new Error('Service path escaped its explicit root');
  return target;
}
export async function readJSON(file, fallback = null) {
  try { return JSON.parse(await readFile(file,'utf8')); }
  catch(error) { if(error.code === 'ENOENT') return fallback; throw error; }
}
export async function atomicJSON(file, value) {
  await mkdir(path.dirname(file),{recursive:true});
  const temp = `${file}.${randomUUID()}.tmp`;
  const handle = await open(temp,'wx');
  try { await handle.writeFile(JSON.stringify(value,null,2)); await handle.sync(); }
  finally { await handle.close(); }
  // Same-directory rename is the publication point. A Windows sharing error preserves the old file.
  try { await rename(temp,file); } catch(error) { await unlink(temp).catch(()=>{}); throw error; }
}
export async function withLock(root, operation) {
  await mkdir(root,{recursive:true});
  const file=path.join(root,'refresh.lock');
  let handle;
  try { handle=await open(file,'wx'); }
  catch(error) { if(error.code==='EEXIST') throw new Error('REFRESH_BUSY: refresh.lock already exists; no overlapping import allowed'); throw error; }
  try {
    await handle.writeFile(JSON.stringify({pid:process.pid,startedAt:now()})); await handle.sync();
    return await operation();
  } finally { await handle.close(); await unlink(file); }
}
export async function current(root) { return readJSON(path.join(root,'current.json')); }
export async function manifest(root, version) {
  if(!/^[a-f0-9]{64}$/.test(version??'')) throw new Error('INVALID_VERSION');
  const info = await readJSON(path.join(root,'snapshots',version,'manifest.json'));
  if(!info) throw new Error('VERSION_UNAVAILABLE');
  try {await stat(path.join(root,'snapshots',version,'data.sqlite'));}
  catch(error) {if(error.code==='ENOENT') throw new Error('VERSION_UNAVAILABLE');throw error;}
  return info;
}
