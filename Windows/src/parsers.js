// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const number = value => {
  if ((typeof value !== 'number' && typeof value !== 'string') || (typeof value === 'string' && !value.trim())) return null;
  const n = Number(value); return Number.isFinite(n) ? n : null;
};
const clamp = n => Math.max(0, Math.min(100, n));
function kimi(root) {
 const windows=[],units={TIME_UNIT_SECOND:1,TIME_UNIT_MINUTE:60,TIME_UNIT_HOUR:3600,TIME_UNIT_DAY:86400},date=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))?new Date(value).toISOString():null;
 const make=(detail,id,name,seconds,reportsLength)=>{if(!detail||typeof detail!=='object')return;const limit=number(detail.limit),used=number(detail.used),remaining=number(detail.remaining);if(!(limit>0)||used===null&&remaining===null)return;const amount=used??limit-remaining;windows.push({id,name,seconds,reportsLength,usedPercent:clamp(100*amount/limit),reset:date(detail.resetTime),exhausted:amount>=limit})};
 for(const [i,item] of (Array.isArray(root?.limits)?root.limits:[]).entries()){const duration=number(item?.window?.duration),unit=units[item?.window?.timeUnit],seconds=duration*unit;if(!Number.isSafeInteger(duration)||duration<=0||!unit||!Number.isSafeInteger(seconds)||seconds>10*366*86400)continue;make(item.detail,'limit.'+i+'.'+seconds,seconds===18000?'5 小时额度':seconds===604800?'每周额度':seconds===2592000?'月度额度':duration+' '+({1:'秒',60:'分钟',3600:'小时',86400:'天'}[unit])+'额度',seconds,true)}
 make(root?.usage,'weekly','每周额度',604800,false);
 for(const [key,id,scope] of [['limit_month_code','month.code','Code'],['limit_month_total','month.total','Total']]){const item=root?.usages?.[key],ratio=number(item?.used_ratio);if(ratio!==null)windows.push({id,name:'月度额度',scope,legacyKeys:['window:'+JSON.stringify(['月度额度 · '+(scope==='Total'?'总计':scope),null,2592000])],seconds:2592000,reportsLength:false,usedPercent:clamp(ratio*100),reset:date(item.reset_time),exhausted:ratio>=1})}
 windows.sort((a,b)=>a.seconds-b.seconds);const level=root?.user?.membership?.level,plan=typeof level==='string'&&level?level.replace(/^LEVEL_/,'').split('_').filter(Boolean).map(x=>x[0].toUpperCase()+x.slice(1).toLowerCase()).join(' ')||null:null;return {windows,plan};
}
function deepseek(root) {
  const balances = (root.balance_infos ?? []).flatMap(v => { const amount = number(v.total_balance); return v.currency && amount !== null ? [{currency:v.currency, amount}] : []; });
  return {windows:[], balances, available:root.is_available ?? null};
}
function codex(root) {
 const windows=[],details=require('./codex-details');
 const group=(limits,scope,key,spent)=>{if(!limits||typeof limits!=='object')return;const rows=[];for(const slot of ['primary_window','secondary_window']){const w=limits[slot],used=number(w?.used_percent),seconds=number(w?.limit_window_seconds),at=number(w?.reset_at);if(used===null)continue;rows.push({id:key+'.'+slot,name:seconds===18000?'5 小时额度':seconds===604800?'每周额度':seconds?`${seconds/3600} 小时额度`:'额度',scope,seconds,reportsLength:seconds>0,usedPercent:clamp(used),reset:at===null||!Number.isFinite(new Date(at*1000).getTime())?null:new Date(at*1000).toISOString(),exhausted:false})}if(rows.length&&(spent||limits.limit_reached===true||limits.allowed===false)){rows.reduce((a,b)=>a.usedPercent>=b.usedPercent?a:b).exhausted=true}windows.push(...rows)};
 group(root.rate_limit,null,'codex',root.rate_limit_reached_type!=null||root.spend_control?.reached===true);for(const extra of root.additional_rate_limits??[])group(extra.rate_limit,extra.limit_name??null,extra.metered_feature??extra.limit_name??'extra',false);
 return {windows,plan:details.plan(root.plan_type),displayBalance:details.balance(root.credits)};
}

module.exports={number,kimi,deepseek,codex};
