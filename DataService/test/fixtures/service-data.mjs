import {columns} from '../../src/schema.mjs';

// Synthetic names/results only, never genuine lifters or current records.
export const row=(Name,TotalKg,extra={})=>({Name,TotalKg,Sex:'F',Event:'SBD',Equipment:'Raw',Place:'1',Federation:'FIX',MeetCountry:'USA',
  MeetName:'Synthetic, meet\nwith quoted text',Date:'2025-01-01',Tested:'Yes',Sanctioned:'Yes',BodyweightKg:'70.5',WeightClassKg:'75',Squat1Kg:'-100',...extra});
export const first=[row('Fixture Alice #1','500'),row('Fixture Alice #1','450',{Date:'2024-01-01'}),row('Fixture Bob','480',{Tested:''}),
  row('Fixture Removed Casey','520'),row('Fixture Alice #2','490',{WeightClassKg:'+'}),row('Fixture DQ','900',{Place:'DQ'}),
  row('Fixture Unofficial','1000',{Sanctioned:'No'}),row('Fixture Failed','',{Best3SquatKg:'-100'})];
export const second=[row('Fixture Alice #1','550'),row('Fixture Alice #1','530',{Date:'2026-01-01'}),row('Fixture Bob','480',{Tested:''}),
  row('Fixture Alice #2','490',{WeightClassKg:'+'}),row('Fixture New Dan','510',{WeightClassKg:'-74'}),row('Fixture DQ','900',{Place:'DQ'}),
  row('Fixture Unofficial','1000',{Sanctioned:'No'}),row('Fixture Failed','',{Best3SquatKg:'-100'})];
export const csv=(rows,header=columns)=>'\uFEFF'+[header,...rows.map(r=>header.map(c=>r[c]??''))].map(r=>r.map(v=>/[",\r\n]/.test(v)?'"'+v.replaceAll('"','""')+'"':v).join(',')).join('\r\n')+'\r\n';

// 54 rows / 29 exact names / 26 qualifying best performances / 26 Alice #1 history rows.
export const nativeHTTPRows=[...first,
  ...Array.from({length:22},(_,i)=>row(`Fixture Extra ${String(i+1).padStart(2,'0')}`,String(399-i))),
  ...Array.from({length:24},(_,i)=>row('Fixture Alice #1',String(299-i),{
    Date:`2023-01-${String(i+1).padStart(2,'0')}`,Best3SquatKg:'-100'}))];
