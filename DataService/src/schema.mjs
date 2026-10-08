export const columns = 'Name,Sex,Event,Equipment,Age,AgeClass,BirthYearClass,Division,BodyweightKg,WeightClassKg,Squat1Kg,Squat2Kg,Squat3Kg,Squat4Kg,Best3SquatKg,Bench1Kg,Bench2Kg,Bench3Kg,Bench4Kg,Best3BenchKg,Deadlift1Kg,Deadlift2Kg,Deadlift3Kg,Deadlift4Kg,Best3DeadliftKg,TotalKg,Place,Dots,Wilks,Glossbrenner,Goodlift,Tested,Country,State,Federation,ParentFederation,Date,MeetCountry,MeetState,MeetTown,MeetName,Sanctioned'.split(',');
export const kgColumns = columns.filter(c=>c.endsWith('Kg')&&c!=='WeightClassKg');
const scores = ['Dots','Wilks','Glossbrenner','Goodlift'];
export const enums = {
  Sex: ['M','F','Mx'], Event: ['SBD','BD','SD','SB','S','B','D'],
  Equipment: ['Raw','Wraps','Single-ply','Multi-ply','Unlimited','Straps'],
  Tested: ['', 'Yes'], Sanctioned: ['', 'Yes','No']
};
export function date(value) {
  if(!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Invalid date');
  const parsed=new Date(`${value}T00:00:00Z`);
  if(!Number.isFinite(parsed.valueOf()) || parsed.toISOString().slice(0,10)!==value) throw new Error('Invalid calendar date');
  return value;
}
export function centi(value) {
  if(value==='') return null;
  if(!/^-?\d+(?:\.\d{1,2})?$/.test(value)) throw new Error(`Invalid kilogram number: ${value}`);
  const negative=value.startsWith('-'); const [whole,fraction='']=value.replace('-','').split('.');
  const number=(Number(whole)*100+Number(fraction.padEnd(2,'0')))*(negative?-1:1);
  if(!Number.isSafeInteger(number)||Math.abs(number)>1_000_000) throw new Error('Kilogram number exceeds bound');
  return number;
}
export const normalize = name => name.normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase();
export function validateHeader(header) {
  if(header.length>100 || new Set(header).size!==header.length||header.some(key=>!key||key.length>128||/[\0\r\n]/.test(key))) throw new Error('Invalid/duplicate header');
  const missing=columns.filter(c=>!header.includes(c));
  if(missing.length) throw new Error(`SCHEMA_CHANGED: missing ${missing.join(',')}`);
  return header;
}
export function validated(row, ordinal) {
  try {
    for(const [key,allowed] of Object.entries(enums)) if(!allowed.includes(row[key])) throw new Error(`Unknown ${key}: ${row[key]}`);
    for(const key of ['Name','Federation','MeetCountry','MeetName','Place']) if(!row[key]?.trim()) throw new Error(`Missing ${key}`);
    if(!/^(?:[1-9]\d*|G|DQ|DD|NS)$/.test(row.Place)) throw new Error(`Unknown Place: ${row.Place}`);
    date(row.Date);
    const result={};
    for(const key of columns) {
      const value=row[key];
      if(typeof value!=='string'||value.length>4096||value.includes('\0')) throw new Error(`Invalid text ${key}`);
      if(kgColumns.includes(key)) result[key]=centi(value);
      else if(scores.includes(key)||key==='Age') {
        if(value==='') result[key]=null;
        else {
          if(!/^\d+(?:\.\d{1,8})?$/.test(value)) throw new Error(`Invalid ${key}`);
          result[key]=Number(value);
          if(!Number.isFinite(result[key])||result[key]> (key==='Age'?150:1_000_000)) throw new Error(`Out of range ${key}`);
        }
      } else result[key]=value;
    }
    if(result.BodyweightKg!==null&&result.BodyweightKg<=0) throw new Error('Bodyweight must be positive when present');
    if(row.WeightClassKg!==''&&row.WeightClassKg!=='+'&&!/^-?\d+(?:\.\d{1,2})?\+?$/.test(row.WeightClassKg)) throw new Error('Invalid WeightClassKg');
    const extras=Object.fromEntries(Object.entries(row).filter(([key])=>!columns.includes(key)));
    for(const [key,value] of Object.entries(extras)) if(key.length>128||value.length>4096) throw new Error('Extra field exceeds bound');
    return {...result,extras:JSON.stringify(extras)};
  } catch(error) { throw new Error(`ROW_${ordinal}: ${error.message}`); }
}
export function schemaSQL() {
  return `CREATE TABLE lifters(Name TEXT PRIMARY KEY, normalized TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE results(row_id INTEGER PRIMARY KEY,${columns.map(c=>`"${c}" ${kgColumns.includes(c)?'INTEGER':scores.includes(c)||c==='Age'?'REAL':'TEXT'}`).join(',')},extras TEXT NOT NULL);`;
}
