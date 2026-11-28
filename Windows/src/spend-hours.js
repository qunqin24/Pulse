// Hourly totals and measured quarter-hour instants; aggregate-only records add neither.
const slotsByHours=new WeakMap(),keys=['input','cacheRead','cacheWrite','output','unclassified'];
function hourStart(ms){const date=new Date(ms),offset=date.getTimezoneOffset()*60000;let start=Math.floor((ms-offset)/3600000)*3600000+offset;if(new Date(start).getHours()!==date.getHours()){while(start<ms&&new Date(start).getHours()!==date.getHours())start+=60000}return start}
function addHour(hours,ms,model,tally){const key=String(hourStart(ms)),by=hours[key]??(hours[key]={}),out=by[model]??(by[model]={input:0,cacheRead:0,cacheWrite:0,output:0,unclassified:0});for(const k of keys)out[k]+=tally[k]??0}
function add(hours,timestamp,model,tally){const ms=Date.parse(timestamp);if(!Number.isFinite(ms))return;addHour(hours,ms,model,tally);if(keys.some(k=>Number.isFinite(tally?.[k])&&tally[k]>0)){let slots=slotsByHours.get(hours);if(!slots){slots=new Set();slotsByHours.set(hours,slots)}slots.add(Math.floor(ms/900000)*900000)}}
function merge(target,source){for(const [hour,models] of Object.entries(source??{}))for(const [model,tally] of Object.entries(models)){const at=Number(hour);if(Number.isFinite(at))addHour(target,at,model,tally)}const sourceSlots=slotsByHours.get(source);if(sourceSlots?.size){let dest=slotsByHours.get(target);if(!dest){dest=new Set();slotsByHours.set(target,dest)}for(const at of sourceSlots)dest.add(at)}}
function instants(hours){return [...(slotsByHours.get(hours)??[])].sort((a,b)=>a-b)}
module.exports={hourStart,add,merge,instants};
