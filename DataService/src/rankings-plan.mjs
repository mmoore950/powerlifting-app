import {date,centi,enums} from './schema.mjs';

/** Shared filter semantics. Narrow projection is an explicit experimental option, not the serving default. */
export function performanceFilters(params) {
  const filters=[],args=[];
  for(const [parameter,column] of [['sex','Sex'],['equipment','Equipment'],['event','Event']]) {
    if(!enums[column].includes(params[parameter])) throw new Error(`RANKINGS_REQUIRES_VALID_${parameter.toUpperCase()}`);
    filters.push(`"${column}"=?`);args.push(params[parameter]);
  }
  if(params.tested!==undefined) {
    if(!['yes','not-designated'].includes(params.tested)) throw new Error('INVALID_TESTED');
    filters.push('Tested=?');args.push(params.tested==='yes'?'Yes':'');
  }
  if(params.federation!==undefined) {
    if(!params.federation||params.federation.length>64) throw new Error('INVALID_FEDERATION');
    filters.push('Federation=?');args.push(params.federation);
  }
  for(const [parameter,operator] of [['from','>='],['to','<=']]) if(params[parameter]!==undefined) {filters.push(`Date ${operator} ?`);args.push(date(params[parameter]));}
  if(params.from&&params.to&&params.from>params.to) throw new Error('INVALID_DATE_RANGE');
  for(const [parameter,operator] of [['bodyweightMin','>='],['bodyweightMax','<=']]) {
    if(params[parameter]!==undefined){const value=centi(String(params[parameter]));if(value===null||value<=0) throw new Error('INVALID_BODYWEIGHT');filters.push(`BodyweightKg ${operator} ?`);args.push(value);}
  }
  if(params.bodyweightMin&&params.bodyweightMax&&centi(String(params.bodyweightMin))>centi(String(params.bodyweightMax))) throw new Error('INVALID_BODYWEIGHT_RANGE');
  if(params.weightClass!==undefined){if(params.weightClass!=='+'&&!/^-?\d+(?:\.\d{1,2})?\+?$/.test(params.weightClass)) throw new Error('INVALID_WEIGHT_CLASS');filters.push('WeightClassKg=?');args.push(params.weightClass);}
  return {filters,args};
}

export const performanceMetrics={total:'TotalKg',squat:'Best3SquatKg',bench:'Best3BenchKg',deadlift:'Best3DeadliftKg',dots:'Dots'};

export function rankingsPlan(params,limit,offset,{narrow=false}={}) {
  const {filters,args}=performanceFilters(params);
  const metric=performanceMetrics[params.metric??'total'];if(!metric) throw new Error('INVALID_METRIC');
  filters.push(`"${metric}">0`,`Place NOT IN ('DQ','DD','NS')`,`Sanctioned IN ('Yes','')`);
  const where=filters.join(' AND ');
  const sql=narrow?`WITH best AS (
    SELECT row_id,Name,"${metric}" AS performance,Date,
      ROW_NUMBER() OVER(PARTITION BY Name ORDER BY "${metric}" DESC,Date DESC,row_id DESC) AS person_rank
    FROM results WHERE ${where}
  ), winners AS MATERIALIZED (
    SELECT row_id,performance,Date,Name FROM best WHERE person_rank=1
    ORDER BY performance DESC,Date DESC,Name,row_id DESC LIMIT ? OFFSET ?
  ) SELECT results.* FROM winners JOIN results ON results.row_id=winners.row_id
    ORDER BY winners.performance DESC,winners.Date DESC,winners.Name,winners.row_id DESC`:
    `WITH best AS (SELECT *, ROW_NUMBER() OVER(PARTITION BY Name ORDER BY "${metric}" DESC,Date DESC,row_id DESC) AS person_rank
    FROM results WHERE ${where}) SELECT * FROM best WHERE person_rank=1
    ORDER BY "${metric}" DESC,Date DESC,Name,row_id DESC LIMIT ? OFFSET ?`;
  return {sql,args:[...args,limit,offset],metric,where};
}
