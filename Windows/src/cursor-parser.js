// Cursor usage summary and weekly-plan adapter.
const {number}=require('./parsers');
const clamp=n=>Math.max(0,Math.min(100,n));
function cursor(summary,planInfo,period){
 const start=Date.parse(summary.billingCycleStart),end=Date.parse(summary.billingCycleEnd);const length=Number.isFinite(start)&&Number.isFinite(end)&&end>start?Math.round((end-start)/1000):null;
 const reset=Number.isFinite(end)?new Date(end).toISOString():null;const actual=summary.individualUsage?.plan??summary.teamUsage?.pooled,overall=summary.individualUsage?.overall,onDemand=summary.individualUsage?.onDemand??summary.teamUsage?.onDemand;let windows=[];
 const money=(v,name,kind)=>{const used=number(v?.used),limit=number(v?.limit);if(v?.enabled===false||used===null||limit===null||limit<=0)return null;return {name,kind,seconds:length??2592000,reportsLength:length!==null,usedPercent:clamp(100*used/limit),reset,exhausted:used>=limit};};
 for(const [field,scope] of [['autoPercentUsed','Cursor Models'],['apiPercentUsed','Other Models']]){const pct=number(actual?.[field]);if(pct!==null)windows.push({name:'月度额度',scope,seconds:length??2592000,reportsLength:length!==null,usedPercent:clamp(pct),reset,exhausted:pct>=100});}
 if(!windows.length){const fallback=money(actual??overall,'月度额度','monthly');if(fallback)windows.push(fallback);}
 const extra=money(onDemand,'额外支出','spend');if(extra)windows.push(extra);
 const info=planInfo?.planInfo,weekly=info?.includedUsagePeriod===2||['INCLUDED_USAGE_PERIOD_WEEKLY','WEEKLY'].includes(String(info?.includedUsagePeriod??'').toUpperCase());
 if(weekly){const pct=number(period?.planUsage?.totalPercentUsed),at=number(info.includedUsageResetsAt);windows=windows.filter(x=>x.kind==='spend');if(pct!==null)windows.unshift({name:'每周额度',seconds:604800,reportsLength:true,usedPercent:clamp(pct),reset:at>0&&Number.isFinite(new Date(at).getTime())?new Date(at).toISOString():null,exhausted:pct>=100});}
 const remaining=number((actual??overall)?.remaining);const balances=remaining!==null?[{currency:'USD',amount:remaining/100}]:[];
 const plan=typeof summary.membershipType==='string'?summary.membershipType.split('_').filter(Boolean).map(x=>x.toLowerCase()==='plus'?'+':x[0].toUpperCase()+x.slice(1).toLowerCase()).join(' ').replace(' +','+'):null;
 return {windows,balances,plan};
}
module.exports={cursor};
