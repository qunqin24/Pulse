// Monthly notice rules derived from Pulse under Apache-2.0.
function candidate(now=new Date()){if(!(now instanceof Date)||!Number.isFinite(+now)||now.getDate()>3)return null;const last=new Date(now.getFullYear(),now.getMonth()-1,1);return last.getFullYear()+'-'+String(last.getMonth()+1).padStart(2,'0')}
function total(snapshot,month){if(!snapshot?.days||typeof snapshot.days!=='object'||!/^[0-9]{4}-[0-9]{2}$/.test(month))return null;let sum=0;for(const [day,models] of Object.entries(snapshot.days)){if(!day.startsWith(month+'-')||!models||typeof models!=='object')continue;for(const row of Object.values(models))for(const key of ['input','cacheRead','cacheWrite','output','unclassified'])if(Number.isFinite(row?.[key])&&row[key]>0)sum+=row[key]}return sum}
function due(now,announced,snapshot){const month=candidate(now);return month&&month!==announced&&total(snapshot,month)>0?month:null}
module.exports={candidate,total,due};
